"""Fixed matched CE / cross-writer contrastive representation experiment.

This callable research fit uses only the 32 UJI training writers. It never
constructs development or reserved rasters, selects an epoch, calibrates an
acceptance policy, or writes an app/profile artifact. Prediction and scoring
belong to a separately frozen operation after both final checkpoints exist.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import math
import platform
import re
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch.nn import functional as F

from ..features import RASTER_HEIGHT, RASTER_WIDTH
from .personal_visual_encoder import PersonalVisualEncoder, augment, encode_samples, infer
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers

FIT_VERSION = "personal-cross-writer-contrastive-fit-v1"
SCOPE = "public-uji-training-only-uncalibrated-offline-representation-research"
ARMS = ("crossEntropyControl", "crossWriterContrastive")
SEED, EPOCHS, CPU_THREADS = 29, 30, 4
VOCABULARY_SIZE, TRAINING_WRITERS, TRAINING_SAMPLES = 97, 32, 6_208
BATCH_SIZE, BATCHES_PER_EPOCH = 194, 32
TEMPERATURE, CONTRASTIVE_COEFFICIENT = 0.07, 0.1
LEARNING_RATE, WEIGHT_DECAY = 0.001, 0.0001
PROTOCOL_DOCUMENT_SHA256 = "ca6c2eca8b7609eaa18ef97d48553546fbd685c1dfcb2b28621e4ae2293c073c"
CODE_PATHS = (
    "docs/personal-cross-writer-contrastive-protocol-2026-10-01.md",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
    "recognition_ml/tests/test_personal_cross_writer_contrastive.py",
)


def _json_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _index_vectors(labels: torch.Tensor, writer_indices: torch.Tensor, count: int,
                   device: torch.device) -> None:
    for value in (labels, writer_indices):
        if (not isinstance(value, torch.Tensor) or value.shape != (count,)
                or value.dtype != torch.long or value.device != device
                or (count and int(value.min()) < 0)):
            raise ValueError("Labels and writer indices must be matching nonnegative int64 vectors")


def _contrastive_masks(labels: torch.Tensor, writer_indices: torch.Tensor):
    same_class = labels[:, None] == labels[None, :]
    same_writer = writer_indices[:, None] == writer_indices[None, :]
    positives = same_class & ~same_writer
    # The second same-writer session is not a negative. Self is excluded too.
    denominator = ~(same_class & same_writer)
    return positives, denominator


def cross_writer_contrastive_loss(unit_features: torch.Tensor, labels: torch.Tensor,
                                 writer_indices: torch.Tensor,
                                 temperature: float = TEMPERATURE) -> torch.Tensor:
    """Mean positive log probability over anchors with another writer present.

    Positives have the same class and a different writer. The denominator
    contains these positives and every different-class row; same-class rows
    from the anchor writer (including self) are excluded. An anchor without a
    positive is skipped. If all anchors lack positives, return a differentiable
    zero. Inputs are unit vectors rather than silently normalized here.
    """
    if (not isinstance(unit_features, torch.Tensor) or unit_features.ndim != 2
            or not len(unit_features) or not unit_features.shape[1]
            or unit_features.dtype not in (torch.float32, torch.float64)
            or not torch.isfinite(unit_features).all()):
        raise ValueError("Features must be a nonempty finite floating matrix")
    if (isinstance(temperature, bool) or not isinstance(temperature, (int, float))
            or not math.isfinite(temperature) or temperature <= 0):
        raise ValueError("Temperature must be positive and finite")
    _index_vectors(labels, writer_indices, len(unit_features), unit_features.device)
    norms = unit_features.norm(dim=1)
    if not torch.allclose(norms, torch.ones_like(norms), rtol=1e-4, atol=1e-5):
        raise ValueError("Contrastive features must have unit length")
    positives, denominator = _contrastive_masks(labels, writer_indices)
    valid_anchors = positives.any(dim=1)
    if not bool(valid_anchors.any()):
        return unit_features.sum() * 0
    logits = (unit_features[valid_anchors] @ unit_features.T) / temperature
    if not torch.isfinite(logits).all():
        raise ValueError("Contrastive temperature overflowed finite similarities")
    positive_rows = positives[valid_anchors]
    normalization = torch.logsumexp(
        logits.masked_fill(~denominator[valid_anchors], -torch.inf), dim=1)
    log_probability = logits - normalization[:, None]
    loss = -(log_probability.masked_fill(~positive_rows, 0).sum(dim=1)
             / positive_rows.sum(dim=1)).mean()
    if not torch.isfinite(loss):
        raise ValueError("Nonfinite cross-writer contrastive loss")
    return loss


def contrastive_anchor_counts(labels: torch.Tensor, writer_indices: torch.Tensor) -> dict[str, int]:
    if not isinstance(labels, torch.Tensor) or labels.ndim != 1 or not len(labels):
        raise ValueError("Cannot count an empty or malformed contrastive batch")
    _index_vectors(labels, writer_indices, len(labels), labels.device)
    positives, _ = _contrastive_masks(labels, writer_indices)
    counts = positives.sum(dim=1)
    return {"anchors": len(labels), "validAnchors": int((counts > 0).sum()),
            "skippedAnchors": int((counts == 0).sum()),
            "directedPositivePairs": int(counts.sum()),
            "minimumPositives": int(counts.min()), "maximumPositives": int(counts.max())}


def select_training_samples(records: Sequence[Sample]):
    """Derive the frozen split from complete source metadata before encoding.

    Checking all identities does not transform development/reserved ink. The
    returned training tuple is the one shared row order for pixels, labels,
    writer indices, plans, and all receipts.
    """
    records = tuple(records)
    if len(records) != 11_640 or any(not isinstance(record, Sample) for record in records):
        raise ValueError("Expected complete strict-source metadata")
    for record in records:
        if (not isinstance(record.writer, str)
                or re.fullmatch(r"(?:trn|tst)_(?:UJI|UPV)_W[0-9]{2}", record.writer) is None
                or type(record.session) is not int or record.session not in (1, 2)
                or not isinstance(record.label, str) or len(record.label) != 1
                or record.label.isspace()):
            raise ValueError("Malformed source writer, session, or label metadata")
    training_writers, development_writers, reserved_writers = split_writers(records)
    labels = tuple(sorted({record.label for record in records}))
    identities = {(record.writer, record.session, record.label) for record in records}
    writers = training_writers + development_writers + reserved_writers
    if (len(labels) != VOCABULARY_SIZE or len(identities) != len(records)
            or identities != {(writer, session, label) for writer in writers
                              for session in (1, 2) for label in labels}):
        raise ValueError("Incomplete or duplicate source writer/session/label metadata")
    allowed = set(training_writers)
    training = tuple(sorted((record for record in records if record.writer in allowed),
                            key=lambda record: record.identity))
    if (len(training) != TRAINING_SAMPLES or len(allowed) != TRAINING_WRITERS
            or any(not record.writer.startswith("trn_") for record in training)
            or set(record.writer for record in training) != allowed):
        raise ValueError("Training source must be exactly the frozen 32 trn_ writers")
    return training, training_writers, development_writers, reserved_writers


def epoch_batch_plan(records: Sequence[Sample], epoch: int, *, seed: int = SEED):
    """32 full-vocabulary batches, indexed into canonical training rows.

    For each sorted label, seed+epoch independently permutes the 32 training
    writers into 16 pairs, then permutes 32 batch positions. Each writer pair
    supplies two positions, with both writers' session order independently
    permuted. Each batch contains exactly two different-writer sources for
    every label, hence 194 rows and exactly one positive per anchor. All 6,208
    original sources appear once. Epoch is zero based.
    """
    if type(epoch) is not int or not 0 <= epoch < EPOCHS or type(seed) is not int or seed < 0:
        raise ValueError("Expected a nonnegative seed and a fixed zero-based epoch")
    training, training_writers, _, _ = select_training_samples(records)
    labels = tuple(sorted({record.label for record in training}))
    lookup = {(record.label, record.writer, record.session): index
              for index, record in enumerate(training)}
    generator = np.random.default_rng(seed + epoch)
    batches: list[list[int]] = [[] for _ in range(BATCHES_PER_EPOCH)]
    for label in labels:
        permutation = generator.permutation(len(training_writers))
        positions = generator.permutation(BATCHES_PER_EPOCH)
        for offset in range(0, len(permutation), 2):
            writers = tuple(training_writers[int(index)] for index in permutation[offset:offset + 2])
            sessions = tuple(generator.permutation((1, 2)) for _ in writers)
            for session_offset, position in enumerate(positions[offset:offset + 2]):
                batches[int(position)].extend(
                    lookup[(label, writer, int(order[session_offset]))]
                    for writer, order in zip(writers, sessions))
    result = tuple(tuple(batch) for batch in batches)
    flattened = [index for batch in result for index in batch]
    if (len(result) != BATCHES_PER_EPOCH or any(len(batch) != BATCH_SIZE for batch in result)
            or len(flattened) != TRAINING_SAMPLES
            or set(flattened) != set(range(TRAINING_SAMPLES))):
        raise ValueError("Epoch plan lost or duplicated a source row")
    return result


def frozen_protocol() -> dict:
    return {
        "architecture": "original-PersonalVisualEncoder-97",
        "augmentation": "original-personal_visual_encoder.augment-affine",
        "augmentationGeneratorSeedPerArm": SEED,
        "arms": {ARMS[0]: {"contrastiveCoefficient": 0.0},
                 ARMS[1]: {"contrastiveCoefficient": CONTRASTIVE_COEFFICIENT}},
        "batchPlan": "sorted-label-independent-writer-pairs-shuffled-batch-positions-and-session-order-seed-plus-zero-based-epoch",
        "batchRows": BATCH_SIZE, "batchesPerEpoch": BATCHES_PER_EPOCH,
        "cpuThreads": CPU_THREADS, "deterministicAlgorithms": True, "epochs": EPOCHS,
        "embedding": "original-l2-normalized-128", "labelsPerBatch": VOCABULARY_SIZE,
        "initializationSeed": SEED, "learningRate": LEARNING_RATE,
        "loss": "cross-entropy-plus-arm-coefficient-times-cross-writer-contrastive",
        "negativeRows": "different-class-only", "noPositiveAnchors": "skip-differentiable-zero-if-none",
        "optimizer": "AdamW", "positiveRows": "same-class-different-writer",
        "sameClassSameWriterRows": "excluded-from-denominator-including-self",
        "scheduler": {"name": "CosineAnnealingLR", "tMax": EPOCHS},
        "selection": "final-epoch-only-no-development-selection",
        "temperature": TEMPERATURE, "weightDecay": WEIGHT_DECAY,
        "trainingFeatureExport": "final-eval-mode-training-only-original-infer-batch128",
        "samplesPerLabelPerBatch": 2,
        "crossWriterPositivesPerAnchor": 1,
    }


def _read_protocol(payload: bytes) -> dict:
    def unique_pairs(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise ValueError("Duplicate field in frozen protocol")
            result[name] = value
        return result

    def reject_constant(value):
        raise ValueError(f"Nonfinite JSON value {value}")

    try:
        value = json.loads(payload.decode("utf-8"), object_pairs_hook=unique_pairs,
                           parse_constant=reject_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Frozen protocol must be UTF-8 JSON") from error
    if (not isinstance(value, dict) or "settings" not in value
            or value.get("markdownProtocolSHA256") != PROTOCOL_DOCUMENT_SHA256
            or ("sourceSHA256" in value and value["sourceSHA256"] != SOURCE_SHA256)
            or _json_bytes(value["settings"]) != _json_bytes(frozen_protocol())):
        raise ValueError("Frozen protocol settings differ from the fixed experiment")
    return value


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    result = {relative: _sha256((root / relative).read_bytes()) for relative in CODE_PATHS}
    if result[CODE_PATHS[0]] != PROTOCOL_DOCUMENT_SHA256:
        raise ValueError("Frozen protocol document changed")
    return result


def _state_digest(state: Mapping[str, torch.Tensor]) -> str:
    digest = hashlib.sha256()
    for name in sorted(state):
        tensor = state[name].detach().cpu().contiguous()
        descriptor = _json_bytes({"name": name, "dtype": str(tensor.dtype), "shape": list(tensor.shape)})
        raw = tensor.numpy().tobytes()
        for payload in (descriptor, raw):
            digest.update(len(payload).to_bytes(8, "big"))
            digest.update(payload)
    return digest.hexdigest()


def initialized_models():
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        original = PersonalVisualEncoder(VOCABULARY_SIZE)
    models = {arm: copy.deepcopy(original) for arm in ARMS}
    hashes = {arm: _state_digest(model.state_dict()) for arm, model in models.items()}
    if len(set(hashes.values())) != 1:
        raise ValueError("Matched arms did not receive identical initial tensors")
    return models, {"sha256": hashes[ARMS[0]], "armSHA256": hashes,
                    "parameterCount": sum(parameter.numel() for parameter in original.parameters())}


def _train_arm(model, arm, images, targets, writers, plans, initial_state):
    coefficient = 0.0 if arm == ARMS[0] else CONTRASTIVE_COEFFICIENT
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    generator = torch.Generator().manual_seed(SEED)
    history = []
    for epoch, batches in enumerate(plans):
        model.train()
        totals = np.zeros(3, dtype=np.float64)
        anchors = {"anchors": 0, "validAnchors": 0, "skippedAnchors": 0,
                   "directedPositivePairs": 0, "minimumPositives": TRAINING_SAMPLES,
                   "maximumPositives": 0}
        augmentation_hash = hashlib.sha256()
        for rows in batches:
            indices = torch.tensor(rows, dtype=torch.long)
            augmented = augment(images[indices].float() / 255, generator)
            augmentation_hash.update(augmented.numpy().tobytes())
            features, logits = model(augmented)
            supervised = F.cross_entropy(logits, targets[indices])
            contrastive = cross_writer_contrastive_loss(features, targets[indices], writers[indices])
            counts = contrastive_anchor_counts(targets[indices], writers[indices])
            if (counts["skippedAnchors"] or counts["minimumPositives"] != 1
                    or counts["maximumPositives"] != 1):
                raise ValueError("Planned batch must have exactly one cross-writer positive per anchor")
            for key in ("anchors", "validAnchors", "skippedAnchors", "directedPositivePairs"):
                anchors[key] += counts[key]
            anchors["minimumPositives"] = min(anchors["minimumPositives"], counts["minimumPositives"])
            anchors["maximumPositives"] = max(anchors["maximumPositives"], counts["maximumPositives"])
            loss = supervised + coefficient * contrastive
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite matched training objective")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if any(parameter.grad is None or not torch.isfinite(parameter.grad).all()
                   for parameter in model.parameters()):
                raise ValueError("Missing or nonfinite matched training gradient")
            optimizer.step()
            if any(not torch.isfinite(parameter).all() for parameter in model.parameters()):
                raise ValueError("Nonfinite fitted encoder parameter")
            totals += [float(loss.detach()) * len(rows), float(supervised.detach()) * len(rows),
                       float(contrastive.detach()) * len(rows)]
        row = {"epoch": epoch + 1, "updates": len(batches), "samples": TRAINING_SAMPLES,
               "loss": totals[0] / TRAINING_SAMPLES,
               "crossEntropyLoss": totals[1] / TRAINING_SAMPLES,
               "contrastiveLoss": totals[2] / TRAINING_SAMPLES,
               "learningRate": optimizer.param_groups[0]["lr"],
               "batchPlanSHA256": _sha256(_json_bytes(batches)),
               "augmentationSHA256": augmentation_hash.hexdigest(),
               "contrastiveAnchors": anchors}
        scheduler.step()
        history.append(row)
        print(json.dumps({"arm": arm, **row}, sort_keys=True, allow_nan=False), flush=True)
    changed = [name for name, parameter in model.named_parameters()
               if not torch.equal(parameter.detach(), initial_state[name])]
    if not changed or len(history) != EPOCHS:
        raise ValueError("Incomplete fit or unchanged encoder parameters")
    return model.eval(), history, changed


def _regular_file(path: Path, kind: str) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or not path.is_file() or path.resolve() != path):
        raise ValueError(f"{kind} must be an existing canonical absolute regular file")
    return path


def _new_output(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink()
            or not path.parent.is_dir() or path.parent.resolve() != path.parent):
        raise ValueError("Output must be a new canonical absolute directory with an existing parent")
    path.mkdir(mode=0o700)
    return path


def _write_exclusive(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(payload)


def opaque_training_id(source_id: str) -> str:
    if not isinstance(source_id, str) or not source_id:
        raise ValueError("Invalid training source identity")
    return _sha256(FIT_VERSION.encode("ascii") + b"\0" + SOURCE_SHA256.encode("ascii")
                   + b"\0" + source_id.encode("utf-8"))


def _training_feature_order(training_inputs: Sequence[dict]) -> list[dict]:
    if len(training_inputs) != TRAINING_SAMPLES:
        raise ValueError("Training feature order must contain exactly 6,208 sources")
    fields = {"sourceID", "writer", "session", "label", "rasterSHA256"}
    rows = []
    for row in training_inputs:
        if (not isinstance(row, dict) or set(row) != fields
                or not isinstance(row["writer"], str)
                or re.fullmatch(r"trn_(?:UJI|UPV)_W[0-9]{2}", row["writer"]) is None
                or type(row["session"]) is not int or row["session"] not in (1, 2)
                or not isinstance(row["label"], str) or len(row["label"]) != 1
                or row["label"].isspace()
                or row["sourceID"] != f'{row["writer"]}-{row["session"]}-{row["label"]}'
                or not isinstance(row["rasterSHA256"], str)
                or re.fullmatch(r"[0-9a-f]{64}", row["rasterSHA256"]) is None):
            raise ValueError("Malformed training feature source receipt")
        rows.append({**row, "sourceID": opaque_training_id(row["sourceID"])})
    writers = {row["writer"] for row in training_inputs}
    labels = {row["label"] for row in training_inputs}
    keys = {(row["writer"], row["session"], row["label"]) for row in training_inputs}
    if (len(writers) != TRAINING_WRITERS or len(labels) != VOCABULARY_SIZE
            or len(keys) != TRAINING_SAMPLES
            or keys != {(writer, session, label) for writer in writers
                        for session in (1, 2) for label in labels}
            or list(training_inputs) != sorted(training_inputs, key=lambda row: row["sourceID"])):
        raise ValueError("Training feature order is incomplete, duplicated, or noncanonical")
    return rows


def _training_feature_payload(features: np.ndarray, training_inputs: Sequence[dict]) -> bytes:
    if (not isinstance(features, np.ndarray) or features.dtype != np.float32
            or features.shape != (TRAINING_SAMPLES, 128) or not np.isfinite(features).all()
            or not np.allclose(np.linalg.norm(features, axis=1), 1, rtol=1e-4, atol=1e-5)):
        raise ValueError("Final training representation must contain finite float32 unit vectors")
    order = _training_feature_order(training_inputs)
    buffer = io.BytesIO()
    np.savez(buffer, features=features,
             labels=np.array([row["label"] for row in order]),
             writers=np.array([row["writer"] for row in order]),
             sourceIDs=np.array([row["sourceID"] for row in order]),
             sessions=np.array([row["session"] for row in order], dtype=np.int64),
             rasterSHA256=np.array([row["rasterSHA256"] for row in order]))
    return buffer.getvalue()


def fit(source: Path, protocol: Path, new_output: Path) -> dict:
    """Execute the fixed fit only when the caller authorizes the frozen protocol.

    `protocol` is JSON with `settings` exactly equal to frozen_protocol(). Its
    caller-owned envelope and exact bytes are frozen and hashed. This function
    constructs only training features and no development/reserved predictions,
    correctness scores, or epoch selection. Output preserves prior evidence.
    """
    source, protocol = _regular_file(source, "source"), _regular_file(protocol, "protocol")
    source_hash, protocol_bytes, code = _sha256(source.read_bytes()), protocol.read_bytes(), code_identity()
    if source_hash != SOURCE_SHA256:
        raise ValueError("Wrong frozen source or empty frozen protocol")
    protocol_document = _read_protocol(protocol_bytes)
    records = load_official_source(source)
    training, training_writers, development_writers, reserved_writers = select_training_samples(records)
    vocabulary = tuple(sorted({sample.label for sample in training}))
    targets = torch.tensor([vocabulary.index(sample.label) for sample in training], dtype=torch.long)
    writers = torch.tensor([training_writers.index(sample.writer) for sample in training], dtype=torch.long)
    plans = tuple(epoch_batch_plan(records, epoch) for epoch in range(EPOCHS))
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    models, initial = initialized_models()
    initial_state = {name: value.detach().clone() for name, value in models[ARMS[0]].state_dict().items()}
    # This is the only rasterization call in fit. The canonical order above is
    # shared by rasters, targets, writer indexes, and every epoch's plan.
    images, raster_hashes = encode_samples(training, training_writers)
    if images.shape != (TRAINING_SAMPLES, 1, RASTER_HEIGHT, RASTER_WIDTH) or images.dtype != torch.uint8:
        raise ValueError("Wrong original encoder raster contract")
    training_inputs = [{"sourceID": sample.identity, "writer": sample.writer,
                        "session": sample.session, "label": sample.label, "rasterSHA256": raster_hash}
                       for sample, raster_hash in zip(training, raster_hashes)]
    if len(training_inputs) != TRAINING_SAMPLES:
        raise ValueError("Incomplete training raster receipt")
    plan = {"version": FIT_VERSION, "scope": SCOPE, "sourceSHA256": source_hash,
            "protocolSHA256": _sha256(protocol_bytes), "codeSHA256": code,
            "contract": frozen_protocol(), "protocolEnvelope": protocol_document,
            "initialState": initial,
            "trainingWriters": list(training_writers), "developmentWriters": list(development_writers),
            "reservedWriters": list(reserved_writers), "trainingSamples": TRAINING_SAMPLES,
            "developmentSamples": 1_552, "reservedSamples": 3_880,
            "vocabulary": list(vocabulary), "vocabularySHA256": _sha256(_json_bytes(vocabulary)),
            "trainingInputs": training_inputs,
            "trainingInputsSHA256": _sha256(_json_bytes(training_inputs)),
            "trainingRasterSHA256": _sha256(images.numpy().tobytes()),
            "epochBatchPlanSHA256": [_sha256(_json_bytes(batches)) for batches in plans],
            "runtime": {"cpuThreads": torch.get_num_threads(),
                        "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled(),
                        "torch": str(torch.__version__), "numpy": str(np.__version__),
                        "python": platform.python_version(), "platform": platform.platform()},
            "roleGuards": {"rasterizedWriterRole": "training-32-only",
                           "developmentRastersConstructed": False, "reservedRastersConstructed": False,
                           "developmentEvaluatedDuringFit": False, "reservedEvaluatedDuringFit": False,
                           "privateInkUsed": False, "productionEligible": False,
                           "calibratedAcceptance": False, "appOrProfileMutated": False}}
    output = _new_output(new_output)
    weights_folder = output / "weights"
    weights_folder.mkdir(mode=0o700)
    _write_exclusive(output / "frozen-protocol.json", protocol_bytes)
    _write_exclusive(output / "fit-plan.json", _json_bytes(plan))
    training_features_folder = output / "training-features"
    training_features_folder.mkdir(mode=0o700)
    histories, weight_hashes, state_hashes, changes, feature_hashes = {}, {}, {}, {}, {}
    for arm in ARMS:
        if _state_digest(models[arm].state_dict()) != initial["sha256"]:
            raise ValueError("Arm initialization changed before training")
        model, histories[arm], changes[arm] = _train_arm(
            models[arm], arm, images, targets, writers, plans, initial_state)
        state_hashes[arm] = _state_digest(model.state_dict())
        checkpoint = {"version": FIT_VERSION, "arm": arm, "finalEpoch": EPOCHS,
                      "sourceSHA256": source_hash, "protocolSHA256": plan["protocolSHA256"],
                      "initialStateSHA256": initial["sha256"],
                      "vocabulary": list(vocabulary), "state_dict": model.state_dict()}
        buffer = io.BytesIO()
        torch.save(checkpoint, buffer)
        payload = buffer.getvalue()
        _write_exclusive(weights_folder / f"{arm}.pt", payload)
        weight_hashes[arm] = _sha256(payload)
        # Public training rows only: export the fixed final representation for
        # later anchor construction without reopening development query truth.
        features, _ = infer(model, images)
        feature_payload = _training_feature_payload(features, training_inputs)
        _write_exclusive(training_features_folder / f"{arm}.npz", feature_payload)
        feature_hashes[arm] = _sha256(feature_payload)
    for before, after in zip(histories[ARMS[0]], histories[ARMS[1]]):
        for key in ("epoch", "updates", "samples", "batchPlanSHA256", "augmentationSHA256", "contrastiveAnchors"):
            if before[key] != after[key]:
                raise ValueError(f"Matched arms received different {key}")
    if (_sha256(source.read_bytes()) != source_hash or protocol.read_bytes() != protocol_bytes
            or code_identity() != code):
        raise ValueError("Frozen source, protocol, or code changed during fitting")
    receipt = {**plan, "arms": list(ARMS), "fitPlanSHA256": _sha256(_json_bytes(plan)),
               "trainingHistory": histories, "changedParameterNames": changes,
               "parametersChanged": {arm: bool(changes[arm]) for arm in ARMS},
               "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS},
               "weightsSHA256": weight_hashes, "finalStateSHA256": state_hashes,
               "trainingFeatureFiles": {arm: f"training-features/{arm}.npz" for arm in ARMS},
               "trainingFeaturesSHA256": feature_hashes,
               "trainingFeatureOrderSHA256": _sha256(_json_bytes(_training_feature_order(training_inputs))),
               "matchedInitialTensors": True, "matchedBatchPlans": True,
               "matchedAugmentationInputs": True, "selection": "final-epoch-only"}
    _write_exclusive(output / "fit-receipt.json", _json_bytes(receipt))
    return receipt


def _load_fit_receipt(output: Path) -> dict:
    output = Path(output)
    receipt_path = _regular_file(output / "fit-receipt.json", "fit receipt")
    receipt_payload = receipt_path.read_bytes()
    receipt = json.loads(receipt_payload)
    plan_payload = _regular_file(output / "fit-plan.json", "fit plan").read_bytes()
    plan = json.loads(plan_payload)
    protocol_payload = _regular_file(output / "frozen-protocol.json", "frozen protocol").read_bytes()
    protocol_document = _read_protocol(protocol_payload)
    if (receipt.get("version") != FIT_VERSION or receipt.get("scope") != SCOPE
            or receipt.get("arms") != list(ARMS) or receipt.get("contract") != frozen_protocol()
            or receipt.get("sourceSHA256") != SOURCE_SHA256
            or receipt.get("selection") != "final-epoch-only"
            or receipt.get("codeSHA256") != code_identity()
            or receipt_payload != _json_bytes(receipt) or plan_payload != _json_bytes(plan)
            or _sha256(plan_payload) != receipt.get("fitPlanSHA256")
            or _sha256(protocol_payload) != receipt.get("protocolSHA256")
            or protocol_document != receipt.get("protocolEnvelope")
            or any(receipt.get(key) != value for key, value in plan.items())):
        raise ValueError("Fit evidence does not match the frozen experiment")
    return receipt


def load_fitted_models(output: Path):
    """Load both frozen final checkpoints without transforming any ink."""
    output = Path(output)
    receipt = _load_fit_receipt(output)
    models = {}
    for arm in ARMS:
        if receipt["weightFiles"][arm] != f"weights/{arm}.pt":
            raise ValueError("Unexpected checkpoint path")
        path = _regular_file(output / receipt["weightFiles"][arm], "checkpoint")
        payload = path.read_bytes()
        if _sha256(payload) != receipt["weightsSHA256"][arm]:
            raise ValueError("Checkpoint bytes changed")
        checkpoint = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
        expected = {"version": FIT_VERSION, "arm": arm, "finalEpoch": EPOCHS,
                    "sourceSHA256": SOURCE_SHA256, "protocolSHA256": receipt["protocolSHA256"],
                    "initialStateSHA256": receipt["initialState"]["sha256"],
                    "vocabulary": receipt["vocabulary"]}
        if set(checkpoint) != set(expected) | {"state_dict"} or any(checkpoint[key] != value for key, value in expected.items()):
            raise ValueError("Checkpoint metadata changed")
        model = PersonalVisualEncoder(VOCABULARY_SIZE)
        model.load_state_dict(checkpoint["state_dict"], strict=True)
        if (any(not torch.isfinite(value).all() for value in model.state_dict().values())
                or _state_digest(model.state_dict()) != receipt["finalStateSHA256"][arm]):
            raise ValueError("Checkpoint state changed or is nonfinite")
        models[arm] = model.eval()
    return models, receipt


def load_training_feature_bundle(output: Path, arm: str, receipt: dict | None = None):
    """Load final public training features without reading any query source."""
    if arm not in ARMS:
        raise ValueError("Unknown matched arm")
    output = Path(output)
    saved_receipt = _load_fit_receipt(output)
    if receipt is not None and _json_bytes(receipt) != _json_bytes(saved_receipt):
        raise ValueError("Supplied fit receipt differs from saved evidence")
    receipt = saved_receipt
    if (receipt.get("version") != FIT_VERSION or receipt.get("scope") != SCOPE
            or receipt.get("arms") != list(ARMS) or receipt.get("sourceSHA256") != SOURCE_SHA256
            or receipt.get("contract") != frozen_protocol()
            or receipt.get("codeSHA256") != code_identity()
            or receipt.get("trainingFeatureFiles", {}).get(arm) != f"training-features/{arm}.npz"
            or _sha256(_json_bytes(receipt["trainingInputs"])) != receipt["trainingInputsSHA256"]):
        raise ValueError("Training feature evidence differs from frozen fit")
    order = _training_feature_order(receipt["trainingInputs"])
    if (_sha256(_json_bytes(order)) != receipt["trainingFeatureOrderSHA256"]
            or set(row["writer"] for row in order) != set(receipt["trainingWriters"])
            or set(row["label"] for row in order) != set(receipt["vocabulary"])):
        raise ValueError("Training feature roles or vocabulary changed")
    payload = _regular_file(output / receipt["trainingFeatureFiles"][arm], "training features").read_bytes()
    if _sha256(payload) != receipt["trainingFeaturesSHA256"][arm]:
        raise ValueError("Training feature bytes changed")
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        expected = {"labels": [row["label"] for row in order],
                    "writers": [row["writer"] for row in order],
                    "sourceIDs": [row["sourceID"] for row in order],
                    "sessions": [row["session"] for row in order],
                    "rasterSHA256": [row["rasterSHA256"] for row in order]}
        if set(bundle.files) != set(expected) | {"features"}:
            raise ValueError("Training feature bundle fields changed")
        arrays = {name: bundle[name].copy() for name in bundle.files}
        if any(arrays[name].shape != (TRAINING_SAMPLES,)
               or arrays[name].tolist() != values for name, values in expected.items()):
            raise ValueError("Training feature source order changed")
    features = arrays["features"]
    if (features.dtype != np.float32 or features.shape != (TRAINING_SAMPLES, 128)
            or not np.isfinite(features).all()
            or not np.allclose(np.linalg.norm(features, axis=1), 1, rtol=1e-4, atol=1e-5)):
        raise ValueError("Training feature vector contract changed")
    return arrays


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    fit(arguments.source, arguments.protocol, arguments.output)
