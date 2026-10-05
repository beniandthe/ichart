"""Fixed paired broad-raster pretraining, followed by unchanged UJI CE fitting.

Offline research only. No query rasterization, personal fitting, epoch selection,
app mutation, or claim of commercial source clearance occurs in this module.
"""
from __future__ import annotations

import argparse
import copy
from dataclasses import fields
import hashlib
import io
import json
import platform
import re
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from ..features import RASTER_HEIGHT, RASTER_WIDTH
from . import nist_sd19, nist_sd19_training_source as nist
from .personal_cross_writer_contrastive import (
    _json_bytes, _new_output, _regular_file, _sha256, _state_digest,
    _training_feature_order, _training_feature_payload, _write_exclusive,
    epoch_batch_plan, select_training_samples)
from .personal_visual_encoder import PersonalVisualEncoder, augment, encode_samples, infer
from .uji_personal import SOURCE_SHA256, Sample, load_official_source

FIT_VERSION = "personal-broad-transfer-fit-v1"
SCOPE = "fixed-paired-broad-raster-transfer-offline-research-only"
ARMS = ("ujiReplayPretrain", "nistBroadPretrain")
SEED, CPU_THREADS, VOCABULARY_SIZE = 29, 4, 97
PRETRAIN_EPOCHS, PRETRAIN_ROWS, PRETRAIN_BATCH_ROWS = 5, 31_744, 128
PRETRAIN_BATCHES, ROWS_PER_ASCII_LABEL, REPLAY_COPIES = 248, 512, 8
FINETUNE_EPOCHS, FINETUNE_ROWS, FINETUNE_BATCHES = 30, 6_208, 32
LEARNING_RATE, WEIGHT_DECAY = 0.001, 0.0001
PROTOCOL_DOCUMENT_SHA256 = "a03afefbe741eed7bb8e0eea4ad96bd8bcfe4f72e159b7b9e12bcdd3ea8d341d"
RESEARCH_DECISION_SHA256 = "3117283ce66b09a3453e42db4309f2883743f814f91ad93d955889f3d6481dc8"
PROTOCOL_PATH = "docs/personal-broad-transfer-protocol-2026-10-01.md"
CODE_PATHS = (PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
    "recognition_ml/ichart_recognition_ml/research/nist_sd19.py",
    "recognition_ml/ichart_recognition_ml/research/nist_sd19_training_source.py",
    "recognition_ml/ichart_recognition_ml/research/personal_broad_transfer.py",
    "recognition_ml/tests/test_nist_sd19_training_source.py",
    "recognition_ml/tests/test_personal_broad_transfer.py")
_HASH = re.compile(r"[0-9a-f]{64}")


def frozen_protocol() -> dict:
    return {"architecture": "original-PersonalVisualEncoder-97",
        "embedding": "original-l2-normalized-128", "arms": list(ARMS),
        "initializationSeed": SEED, "cpuThreads": CPU_THREADS,
        "deterministicAlgorithms": True, "loss": "cross-entropy-only",
        "optimizer": "AdamW", "learningRate": LEARNING_RATE, "weightDecay": WEIGHT_DECAY,
        "augmentation": "original-personal_visual_encoder.augment-affine",
        "augmentationGeneratorSeedPerArmPerPhase": SEED,
        "pretrain": {"epochs": PRETRAIN_EPOCHS, "rows": PRETRAIN_ROWS,
            "batchRows": PRETRAIN_BATCH_ROWS, "batchesPerEpoch": PRETRAIN_BATCHES,
            "labels": list(nist.LABELS), "rowsPerLabel": ROWS_PER_ASCII_LABEL,
            "headInitialization": "select-original-initial-97-classifier-rows-for-ASCII62",
            "batchPlan": "numpy-seed-plus-epoch-permutation-of-canonical-31744-rows",
            "replaySelection": "per-label-sha256-fit-version-null-source-identity-sort-64-rows-repeat8",
            "replayCopies": REPLAY_COPIES,
            "nistSelectionVersion": nist.SELECTION_VERSION,
            "nistRasterTransformVersion": nist.TRANSFORM_VERSION,
            "scheduler": {"name": "CosineAnnealingLR", "tMax": PRETRAIN_EPOCHS}},
        "headReset": "discard-trained-62-head-reset-entire97-classifier-to-original-initial-tensors",
        "finetune": {"epochs": FINETUNE_EPOCHS, "rows": FINETUNE_ROWS,
            "batchRows": 194, "batchesPerEpoch": FINETUNE_BATCHES,
            "batchPlan": "original-personal-cross-writer-contrastive.epoch_batch_plan",
            "newOptimizerAndScheduler": True,
            "scheduler": {"name": "CosineAnnealingLR", "tMax": FINETUNE_EPOCHS}},
        "selection": "fixed-final-epoch-only-no-development-selection",
        "trainingFeatureExport": "final-eval-mode-UJI-training-only-original-infer-batch128",
        "trainingFeatureIdentity": "frozen-personal-cross-writer-contrastive-fit-v1-opaque-IDs",
        "productionEligible": False, "commercialTrainingEligibilityEstablished": False}


def _json_load(payload: bytes):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate JSON field")
            result[key] = value
        return result
    def reject(value):
        raise ValueError(f"Nonfinite JSON constant {value}")
    try:
        return json.loads(payload.decode("utf-8"), object_pairs_hook=unique, parse_constant=reject)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Expected strict UTF-8 JSON") from error


def _valid_hash(value):
    return isinstance(value, str) and _HASH.fullmatch(value) is not None


def _read_protocol(payload: bytes) -> dict:
    value = _json_load(payload)
    pins = value.get("nistTrainingSource") if isinstance(value, dict) else None
    if (not isinstance(value, dict) or value.get("sourceSHA256") != SOURCE_SHA256
            or value.get("markdownProtocolSHA256") != PROTOCOL_DOCUMENT_SHA256
            or value.get("researchUseDecisionSHA256") != RESEARCH_DECISION_SHA256
            or _json_bytes(value.get("settings")) != _json_bytes(frozen_protocol())
            or not isinstance(pins, dict)
            or set(pins) != {"receiptSHA256", "selectionJSONLSHA256", "rastersBinSHA256"}
            or not all(_valid_hash(item) for item in pins.values())):
        raise ValueError("Frozen protocol differs from the fixed paired transfer experiment")
    return value


def _read_research_decision(payload, nist_receipt=None):
    decision = _json_load(payload)
    if (_sha256(payload) != RESEARCH_DECISION_SHA256 or not isinstance(decision, dict)
            or decision.get("version") != "nist-sd19-local-research-use-decision-v1"
            or decision.get("purpose") != "local-offline-OCR-research-only"
            or decision.get("localResearchFitAllowed") is not True
            or decision.get("commercialUseOrDerivedWeightShippingAllowed") is not False
            or decision.get("commercialRightsStatus") != "unresolved"
            or decision.get("legalDeterminationMade") is not False
            or decision.get("originalIntakeReceiptsUnchanged") is not True
            or decision.get("protocolDocumentSHA256") != PROTOCOL_DOCUMENT_SHA256
            or decision.get("officialSourceURL") != "https://www.nist.gov/srd/nist-special-database-19"
            or decision.get("officialPolicyURL") != "https://www.nist.gov/open/license"
            or not isinstance(decision.get("recordedAtUTC"), str)
            or not isinstance(decision.get("officialSourceRetrievedOnUTC"), str)):
        raise ValueError("Additive research-use decision differs from the frozen offline-only scope")
    if nist_receipt is not None and any(decision[name] != nist_receipt[key] for name, key in
        (("cleanManifestSHA256", "sourceManifestSHA256"), ("quarantineReceiptSHA256", "sourceQuarantineReceiptSHA256"),
         ("archiveSHA256", "sourceArchiveSHA256"))):
        raise ValueError("Research-use decision is bound to a different NIST source")
    return decision


def code_identity() -> dict:
    root = Path(__file__).resolve().parents[3]
    result = {path: _sha256((root / path).read_bytes()) for path in CODE_PATHS}
    if result[PROTOCOL_PATH] != PROTOCOL_DOCUMENT_SHA256:
        raise ValueError("Frozen Markdown protocol changed or has not been pinned")
    return result


def initialized_models(vocabulary):
    vocabulary = tuple(vocabulary)
    if (len(vocabulary) != VOCABULARY_SIZE or vocabulary != tuple(sorted(set(vocabulary)))
            or not set(nist.LABELS).issubset(vocabulary)):
        raise ValueError("Expected original sorted 97-label vocabulary containing ASCII62")
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        original = PersonalVisualEncoder(VOCABULARY_SIZE)
    initial = {name: value.detach().clone() for name, value in original.state_dict().items()}
    models = {arm: copy.deepcopy(original) for arm in ARMS}
    hashes = {arm: _state_digest(model.state_dict()) for arm, model in models.items()}
    if len(set(hashes.values())) != 1:
        raise ValueError("Arms have unequal initial tensors")
    return models, initial, {"sha256": hashes[ARMS[0]], "armSHA256": hashes,
        "parameterCount": sum(value.numel() for value in original.parameters())}


def install_ascii_head(model, vocabulary, initial_state):
    indices = torch.tensor([tuple(vocabulary).index(label) for label in nist.LABELS], dtype=torch.long)
    with torch.random.fork_rng(devices=[]):
        head = nn.Linear(128, len(nist.LABELS))
    with torch.no_grad():
        head.weight.copy_(initial_state["classifier.weight"][indices])
        head.bias.copy_(initial_state["classifier.bias"][indices])
    model.classifier = head


def reset_original_head(model, initial_state):
    with torch.random.fork_rng(devices=[]):
        head = nn.Linear(128, VOCABULARY_SIZE)
    with torch.no_grad():
        head.weight.copy_(initial_state["classifier.weight"])
        head.bias.copy_(initial_state["classifier.bias"])
    model.classifier = head


def replay_row_indices(training):
    """512 positions/class are 64 original training sources repeated eight times."""
    training = tuple(training)
    labels = {sample.label for sample in training if isinstance(sample, Sample)}
    writers = {sample.writer for sample in training if isinstance(sample, Sample)}
    if (len(training) != FINETUNE_ROWS or len(labels) != VOCABULARY_SIZE or len(writers) != 32
            or any(not isinstance(sample, Sample) or type(sample.session) is not int
                   or sample.session not in (1, 2) or not sample.writer.startswith("trn_") for sample in training)
            or {(sample.writer, sample.session, sample.label) for sample in training}
                != {(writer, session, label) for writer in writers for session in (1, 2) for label in labels}
            or training != tuple(sorted(training, key=lambda sample: sample.identity))):
        raise ValueError("Replay requires the complete canonical 6,208-row training source")
    by_label = {label: [] for label in nist.LABELS}
    for index, sample in enumerate(training):
        if sample.label in by_label:
            if not sample.writer.startswith("trn_"):
                raise ValueError("Replay includes a non-training writer")
            by_label[sample.label].append(index)
    result = []
    for label in nist.LABELS:
        rows = sorted(by_label[label], key=lambda index: (
            _sha256(FIT_VERSION.encode("ascii") + b"\0" + training[index].identity.encode("utf-8")),
            training[index].identity))
        if (len(rows) != 64 or len({training[index].identity for index in rows}) != 64
                or len({training[index].writer for index in rows}) != 32
                or {(training[index].writer, training[index].session) for index in rows}
                    != {(training[index].writer, session) for index in rows for session in (1, 2)}):
            raise ValueError("Replay class must have 32 frozen writers and two sessions each")
        result.extend(rows * REPLAY_COPIES)
    if len(result) != PRETRAIN_ROWS:
        raise ValueError("Replay count changed")
    return tuple(result)


def pretrain_batch_plan(epoch):
    if type(epoch) is not int or not 0 <= epoch < PRETRAIN_EPOCHS:
        raise ValueError("Invalid fixed pretraining epoch")
    order = np.random.default_rng(SEED + epoch).permutation(PRETRAIN_ROWS)
    result = tuple(tuple(int(value) for value in row) for row in order.reshape(PRETRAIN_BATCHES, PRETRAIN_BATCH_ROWS))
    if sorted(index for row in result for index in row) != list(range(PRETRAIN_ROWS)):
        raise ValueError("Pretraining plan lost a row")
    return result


def _validate_nist_record(record, index, writer_roles):
    row = record.get("sourceRow") if isinstance(record, dict) else None
    if (type(index) is not int or not 0 <= index < PRETRAIN_ROWS or not isinstance(record, dict)
            or set(record) != {"selectionIndex", "sourceRow", "adaptedRasterSHA256", "rasterByteOffset", "rasterByteLength"}
            or not isinstance(row, dict) or set(row) != {field.name for field in fields(nist_sd19.RasterSample)}
            or type(record["selectionIndex"]) is not int or record["selectionIndex"] != index
            or type(record["rasterByteOffset"]) is not int or record["rasterByteOffset"] != index * RASTER_WIDTH * RASTER_HEIGHT
            or type(record["rasterByteLength"]) is not int or record["rasterByteLength"] != RASTER_WIDTH * RASTER_HEIGHT
            or not _valid_hash(record["adaptedRasterSHA256"])
            or type(row["image_index"]) is not int or type(row["cls_label_line"]) is not int
            or row["split"] != "train" or row["label"] != nist.LABELS[index // ROWS_PER_ASCII_LABEL]):
        raise ValueError("Prepared NIST row/order/role changed")
    nist._metadata(row, writer_roles)
    png, _ = nist_sd19.parse_png_path(row["png_member"])
    if nist_sd19._relative_member(row["cls_member"]) != f"by_write/{png.partition}/{png.form_id}/{png.field_id}.cls":
        raise ValueError("Prepared NIST CLS source identity differs")
    return row


def load_nist_training_source(directory, pins):
    """Validate the exact prepared train-only raster byte stream, without ZIP reads."""
    directory = Path(directory)
    paths = {name: _regular_file(directory / name, f"NIST {name}")
             for name in ("receipt.json", "selection.jsonl", "rasters.bin")}
    payload = paths["receipt.json"].read_bytes()
    receipt = _json_load(payload)
    if (set(pins) != {"receiptSHA256", "selectionJSONLSHA256", "rastersBinSHA256"}
            or not all(_valid_hash(value) for value in pins.values())
            or _sha256(payload) != pins["receiptSHA256"]):
        raise ValueError("Prepared source receipt pin changed")
    expected_fields = {"formatVersion", "adapterSourceSHA256", "sourceManifestSHA256",
        "sourceQuarantineReceiptSHA256", "sourceArchiveSHA256", "inheritedSourceReceipt", "rightsStatus",
        "trainingEligibilityEstablished", "researchPurposeSupported", "productionEligible",
        "fitOrInferencePerformed", "researchScope", "protocolSHA256", "selectionVersion", "selectionSalt", "writersPerLabel",
        "sampleCount", "labels", "sourceCounts", "selectedWriterCount", "selectedRoleCounts",
        "selectedClassCounts", "transform", "selectionJSONLSHA256", "rastersBinSHA256"}
    inherited = receipt.get("inheritedSourceReceipt", {})
    transform = receipt.get("transform", {})
    if (set(receipt) != expected_fields or receipt["formatVersion"] != 1
            or receipt["sampleCount"] != PRETRAIN_ROWS or receipt["labels"] != list(nist.LABELS)
            or receipt["writersPerLabel"] != ROWS_PER_ASCII_LABEL
            or receipt["selectedRoleCounts"] != {"train": PRETRAIN_ROWS}
            or receipt["selectedClassCounts"] != {label: ROWS_PER_ASCII_LABEL for label in nist.LABELS}
            or receipt["selectionVersion"] != nist.SELECTION_VERSION
            or receipt["protocolSHA256"] != PROTOCOL_DOCUMENT_SHA256
            or receipt["adapterSourceSHA256"] != _sha256(Path(nist.__file__).read_bytes())
            or any(not _valid_hash(receipt[key]) for key in
                   ("sourceManifestSHA256", "sourceQuarantineReceiptSHA256", "sourceArchiveSHA256"))
            or receipt["rightsStatus"] != nist_sd19.RIGHTS_STATUS
            or receipt["productionEligible"] is not False
            or receipt["trainingEligibilityEstablished"] is not False
            or receipt["researchPurposeSupported"] is not True or receipt["fitOrInferencePerformed"] is not False
            or inherited.get("sourceID") != nist_sd19.SOURCE_ID
            or inherited.get("rightsStatus") != nist_sd19.RIGHTS_STATUS
            or inherited.get("trainingEligibilityEstablished") is not False
            or inherited.get("inputKind") != "raster-only" or inherited.get("observedTrajectories") is not False
            or inherited.get("sourceArchiveSHA256", {}).get("pngZIP") != receipt["sourceArchiveSHA256"]
            or transform.get("version") != nist.TRANSFORM_VERSION
            or transform.get("outputSize") != [RASTER_WIDTH, RASTER_HEIGHT]
            or transform.get("sourceSize") != [128, 128]
            or transform.get("contentLimit") != [240, 80]
            or transform.get("resampling") != "Pillow nearest-neighbor"
            or transform.get("foreground") != 255 or transform.get("background") != 0
            or transform.get("inputKind") != "raster-only" or transform.get("observedTrajectories") is not False):
        raise ValueError("Prepared NIST source schema, role, provenance, or transform changed")
    selection = paths["selection.jsonl"].read_bytes()
    if (_sha256(selection) != pins["selectionJSONLSHA256"]
            or receipt["selectionJSONLSHA256"] != pins["selectionJSONLSHA256"]):
        raise ValueError("Prepared selection bytes changed")
    rows, seen, writer_labels, writer_roles = [], set(), set(), {}
    for index, line in enumerate(selection.splitlines(keepends=True)):
        record = _json_load(line)
        if not line.endswith(b"\n"):
            raise ValueError("Prepared NIST row must retain LF termination")
        row = _validate_nist_record(record, index, writer_roles)
        if row["sample_id"] in seen or (row["writer_id"], row["label"]) in writer_labels:
            raise ValueError("Prepared NIST source identity duplicated")
        seen.add(row["sample_id"])
        writer_labels.add((row["writer_id"], row["label"]))
        rows.append(record)
    if (len(rows) != PRETRAIN_ROWS or len(writer_roles) != receipt["selectedWriterCount"]
            or any(value != "train" for value in writer_roles.values())):
        raise ValueError("Prepared NIST counts or writer roles changed")
    raster_size = PRETRAIN_ROWS * RASTER_WIDTH * RASTER_HEIGHT
    if paths["rasters.bin"].stat().st_size != raster_size:
        raise ValueError("Prepared NIST raster byte count changed")
    array = np.memmap(paths["rasters.bin"], mode="r", dtype=np.uint8,
                      shape=(PRETRAIN_ROWS, 1, RASTER_HEIGHT, RASTER_WIDTH))
    digest = hashlib.sha256()
    for index, record in enumerate(rows):
        pixels = array[index].tobytes()
        digest.update(pixels)
        if (_sha256(pixels) != record["adaptedRasterSHA256"] or not bool(array[index].any())
                or pixels.translate(None, b"\x00\xff")):
            raise ValueError("Prepared NIST adapted raster hash changed or has no ink")
    if (digest.hexdigest() != pins["rastersBinSHA256"]
            or receipt["rastersBinSHA256"] != pins["rastersBinSHA256"]):
        raise ValueError("Prepared NIST raster stream changed")
    # No full 780 MB copy. Each training batch copies only its chosen rows.
    targets = torch.tensor([nist.LABELS.index(record["sourceRow"]["label"]) for record in rows], dtype=torch.long)
    return array, targets, {"receipt": receipt, "pins": dict(pins), "rows": rows}


def _training_update(model, images, targets, optimizer, generator):
    if (images.dtype != torch.uint8 or images.ndim != 4
            or tuple(images.shape[1:]) != (1, RASTER_HEIGHT, RASTER_WIDTH)
            or targets.dtype != torch.long or targets.shape != (len(images),)
            or not len(images) or int(targets.min()) < 0 or int(targets.max()) >= model.classifier.out_features):
        raise ValueError("Malformed fixed training batch")
    augmented = augment(images.float() / 255, generator)
    _, logits = model(augmented)
    loss = F.cross_entropy(logits, targets)
    if not torch.isfinite(loss):
        raise ValueError("Nonfinite CE training objective")
    optimizer.zero_grad(set_to_none=True)
    loss.backward()
    if any(value.grad is None or not torch.isfinite(value.grad).all() for value in model.parameters()):
        raise ValueError("Missing or nonfinite training gradient")
    optimizer.step()
    if any(not torch.isfinite(value).all() for value in model.state_dict().values()):
        raise ValueError("Nonfinite fitted encoder state")
    return float(loss.detach()), _sha256(augmented.numpy().tobytes())


def _train_phase(model, arm, images, targets, plans, phase, row_indices=None):
    if phase == "pretrain":
        epochs, row_count, batch_count, batch_size = PRETRAIN_EPOCHS, PRETRAIN_ROWS, PRETRAIN_BATCHES, PRETRAIN_BATCH_ROWS
    elif phase == "finetune":
        epochs, row_count, batch_count, batch_size = FINETUNE_EPOCHS, FINETUNE_ROWS, FINETUNE_BATCHES, 194
    else:
        raise ValueError("Unknown fixed training phase")
    if (len(plans) != epochs or len(targets) != row_count
            or any(len(plan) != batch_count or any(len(rows) != batch_size for rows in plan) for plan in plans)):
        raise ValueError("Wrong planned fixed training count")
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    generator = torch.Generator().manual_seed(SEED)
    history = []
    for epoch, batches in enumerate(plans):
        model.train()
        total, trace, pixels = 0., hashlib.sha256(), hashlib.sha256()
        for rows in batches:
            indices = torch.tensor(rows, dtype=torch.long)
            selected = indices if row_indices is None else torch.tensor([row_indices[index] for index in rows], dtype=torch.long)
            batch = images[selected] if isinstance(images, torch.Tensor) else torch.from_numpy(np.array(images[selected.numpy()], copy=True))
            trace.update(generator.get_state().numpy().tobytes())
            loss, pixel_hash = _training_update(model, batch, targets[indices], optimizer, generator)
            trace.update(generator.get_state().numpy().tobytes())
            pixels.update(bytes.fromhex(pixel_hash))
            total += loss * len(rows)
        row = {"phase": phase, "epoch": epoch + 1, "samples": row_count, "updates": len(batches),
               "crossEntropyLoss": total / row_count, "learningRate": optimizer.param_groups[0]["lr"],
               "batchPlanSHA256": _sha256(_json_bytes(batches)),
               "augmentationGeneratorTraceSHA256": trace.hexdigest(), "augmentationInputsSHA256": pixels.hexdigest()}
        scheduler.step()
        history.append(row)
        print(json.dumps({"arm": arm, **row}, sort_keys=True, allow_nan=False), flush=True)
    return history


def _runtime():
    return {"cpuThreads": torch.get_num_threads(), "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled(),
        "torch": str(torch.__version__), "numpy": str(np.__version__), "python": platform.python_version(), "platform": platform.platform()}


def fit(source: Path, nist_dir: Path, protocol: Path, output: Path, *, research_decision: Path) -> dict:
    source, protocol = _regular_file(source, "UJI source"), _regular_file(protocol, "frozen protocol")
    protocol_bytes, code = protocol.read_bytes(), code_identity()
    envelope = _read_protocol(protocol_bytes)
    research_decision = _regular_file(research_decision, "additive research-use decision")
    decision_bytes = research_decision.read_bytes()
    decision = _read_research_decision(decision_bytes)
    if _sha256(source.read_bytes()) != SOURCE_SHA256:
        raise ValueError("Original UJI source changed")
    root = Path(__file__).resolve().parents[3]
    candidate_output = Path(output)
    if candidate_output.is_relative_to(root) or Path(nist_dir).is_relative_to(candidate_output):
        raise ValueError("Fit output must be exclusive and outside the repository/input source")
    records = load_official_source(source)
    training, train_writers, development, reserved = select_training_samples(records)
    vocabulary = tuple(sorted({sample.label for sample in training}))
    nist_images, nist_targets, nist_evidence = load_nist_training_source(nist_dir, envelope["nistTrainingSource"])
    _read_research_decision(decision_bytes, nist_evidence["receipt"])
    replay_indices = replay_row_indices(training)
    pretrain_plans = tuple(pretrain_batch_plan(epoch) for epoch in range(PRETRAIN_EPOCHS))
    fine_plans = tuple(epoch_batch_plan(records, epoch) for epoch in range(FINETUNE_EPOCHS))
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    models, initial_state, initial = initialized_models(vocabulary)
    images, raster_hashes = encode_samples(training, train_writers)
    if images.shape != (FINETUNE_ROWS, 1, RASTER_HEIGHT, RASTER_WIDTH) or images.dtype != torch.uint8:
        raise ValueError("Original UJI raster contract changed")
    targets = torch.tensor([vocabulary.index(sample.label) for sample in training], dtype=torch.long)
    replay_targets = torch.tensor([nist.LABELS.index(training[index].label) for index in replay_indices], dtype=torch.long)
    if not torch.equal(replay_targets, nist_targets):
        raise ValueError("Pretraining label orders differ")
    inputs = [{"sourceID": sample.identity, "writer": sample.writer, "session": sample.session,
               "label": sample.label, "rasterSHA256": raster_hash}
              for sample, raster_hash in zip(training, raster_hashes)]
    plan = {"version": FIT_VERSION, "scope": SCOPE, "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": _sha256(protocol_bytes), "protocolEnvelope": envelope, "codeSHA256": code,
        "contract": frozen_protocol(), "initialState": initial, "runtime": _runtime(),
        "trainingWriters": list(train_writers), "developmentWriters": list(development), "reservedWriters": list(reserved),
        "trainingSamples": FINETUNE_ROWS, "developmentSamples": 1552, "reservedSamples": 3880,
        "vocabulary": list(vocabulary), "vocabularySHA256": _sha256(_json_bytes(vocabulary)),
        "trainingInputs": inputs, "trainingInputsSHA256": _sha256(_json_bytes(inputs)),
        "trainingRasterSHA256": _sha256(images.numpy().tobytes()),
        "replayRowIndicesSHA256": _sha256(_json_bytes(replay_indices)),
        "pretrainBatchPlanSHA256": [_sha256(_json_bytes(plan)) for plan in pretrain_plans],
        "epochBatchPlanSHA256": [_sha256(_json_bytes(plan)) for plan in fine_plans],
        "nistTrainingSource": nist_evidence, "researchUseDecision": decision,
        "researchUseDecisionSHA256": RESEARCH_DECISION_SHA256,
        "roleGuards": {"rasterizedUJIWriterRole": "training-32-only", "nistSelectedRole": "train-only",
            "developmentRastersConstructed": False, "reservedRastersConstructed": False,
            "developmentEvaluatedDuringFit": False, "reservedEvaluatedDuringFit": False,
            "privateInkUsed": False, "productionEligible": False, "commercialTrainingEligibilityEstablished": False,
            "calibratedAcceptance": False, "appOrProfileMutated": False}}
    output = _new_output(output)
    for folder in ("weights", "training-features"):
        (output / folder).mkdir(mode=0o700)
    _write_exclusive(output / "frozen-protocol.json", protocol_bytes)
    _write_exclusive(output / "research-use-decision.json", decision_bytes)
    _write_exclusive(output / "fit-plan.json", _json_bytes(plan))
    histories, weights, states, feature_hashes, changed, resets, pretrain_states, pretrain_weights = {}, {}, {}, {}, {}, {}, {}, {}
    for arm in ARMS:
        model = models[arm]
        if _state_digest(model.state_dict()) != initial["sha256"]:
            raise ValueError("Arm initialization changed")
        install_ascii_head(model, vocabulary, initial_state)
        pretrain_state = _state_digest(model.state_dict())
        pre_images, pre_targets, indices = ((images, replay_targets, replay_indices) if arm == ARMS[0]
                                          else (nist_images, nist_targets, None))
        pre_history = _train_phase(model, arm, pre_images, pre_targets, pretrain_plans, "pretrain", indices)
        pretrain_states[arm] = {"initial62SHA256": pretrain_state, "final62SHA256": _state_digest(model.state_dict())}
        pre_checkpoint = {"version": FIT_VERSION, "arm": arm, "phase": "pretrain", "finalEpoch": PRETRAIN_EPOCHS,
            "sourceSHA256": SOURCE_SHA256, "protocolSHA256": plan["protocolSHA256"],
            "initialStateSHA256": initial["sha256"], "vocabulary": list(nist.LABELS), "state_dict": model.state_dict()}
        buffer = io.BytesIO()
        torch.save(pre_checkpoint, buffer)
        pre_payload = buffer.getvalue()
        _write_exclusive(output / "weights" / f"{arm}-pretrain62.pt", pre_payload)
        pretrain_weights[arm] = _sha256(pre_payload)
        trunk = {key: value.detach().clone() for key, value in model.state_dict().items() if not key.startswith("classifier.")}
        reset_original_head(model, initial_state)
        resets[arm] = {"classifierWeightSHA256": _sha256(model.classifier.weight.detach().numpy().tobytes()),
            "classifierBiasSHA256": _sha256(model.classifier.bias.detach().numpy().tobytes()),
            "trunkPreserved": all(torch.equal(value, model.state_dict()[key]) for key, value in trunk.items()),
            "full97HeadEqualsOriginal": torch.equal(model.classifier.weight.detach(), initial_state["classifier.weight"])
                and torch.equal(model.classifier.bias.detach(), initial_state["classifier.bias"])}
        if not resets[arm]["trunkPreserved"] or not resets[arm]["full97HeadEqualsOriginal"]:
            raise ValueError("Head reset changed trunk or retained a trained pretraining head")
        fine_history = _train_phase(model, arm, images, targets, fine_plans, "finetune")
        histories[arm] = {"pretrain": pre_history, "finetune": fine_history}
        changed[arm] = [name for name, value in model.named_parameters() if not torch.equal(value.detach(), initial_state[name])]
        if not changed[arm]:
            raise ValueError("Final encoder did not fit")
        states[arm] = _state_digest(model.state_dict())
        checkpoint = {"version": FIT_VERSION, "arm": arm, "finalEpoch": FINETUNE_EPOCHS,
            "sourceSHA256": SOURCE_SHA256, "protocolSHA256": plan["protocolSHA256"],
            "initialStateSHA256": initial["sha256"], "vocabulary": list(vocabulary), "state_dict": model.state_dict()}
        buffer = io.BytesIO()
        torch.save(checkpoint, buffer)
        weight = buffer.getvalue()
        _write_exclusive(output / "weights" / f"{arm}.pt", weight)
        weights[arm] = _sha256(weight)
        features, _ = infer(model, images)
        feature_payload = _training_feature_payload(features, inputs)
        _write_exclusive(output / "training-features" / f"{arm}.npz", feature_payload)
        feature_hashes[arm] = _sha256(feature_payload)
    for phase in ("pretrain", "finetune"):
        for control, candidate in zip(histories[ARMS[0]][phase], histories[ARMS[1]][phase]):
            for key in ("epoch", "samples", "updates", "learningRate", "batchPlanSHA256", "augmentationGeneratorTraceSHA256"):
                if control[key] != candidate[key]:
                    raise ValueError(f"Matched arm {phase} differs at {key}")
            if phase == "finetune" and control["augmentationInputsSHA256"] != candidate["augmentationInputsSHA256"]:
                raise ValueError("UJI fine-tuning augmentation inputs differ")
    if (len({value["initial62SHA256"] for value in pretrain_states.values()}) != 1
            or _sha256(source.read_bytes()) != SOURCE_SHA256 or protocol.read_bytes() != protocol_bytes
            or research_decision.read_bytes() != decision_bytes or code_identity() != code):
        raise ValueError("Initial heads or source/protocol/code changed")
    # Revalidate every prepared raster/selection pin after fitting; never trust an
    # mmap whose backing file could have changed while the model was training.
    load_nist_training_source(nist_dir, envelope["nistTrainingSource"])
    receipt = {**plan, "arms": list(ARMS), "fitPlanSHA256": _sha256(_json_bytes(plan)),
        "trainingHistory": histories, "changedParameterNames": changed, "headReset": resets,
        "pretrainStates": pretrain_states, "parametersChanged": {arm: bool(changed[arm]) for arm in ARMS},
        "pretrainWeightFiles": {arm: f"weights/{arm}-pretrain62.pt" for arm in ARMS},
        "pretrainWeightsSHA256": pretrain_weights,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS}, "weightsSHA256": weights,
        "finalStateSHA256": states,
        "trainingFeatureFiles": {arm: f"training-features/{arm}.npz" for arm in ARMS},
        "trainingFeaturesSHA256": feature_hashes,
        "trainingFeatureOrderSHA256": _sha256(_json_bytes(_training_feature_order(inputs))),
        "matchedInitialTensors": True, "matchedBatchPlans": True, "matchedAugmentationDraws": True,
        "selection": "fixed-final-epoch-only-no-development-selection"}
    _write_exclusive(output / "fit-receipt.json", _json_bytes(receipt))
    return receipt


def _load_fit_receipt(output):
    output = Path(output)
    payload = _regular_file(output / "fit-receipt.json", "fit receipt").read_bytes()
    receipt = _json_load(payload)
    plan_bytes = _regular_file(output / "fit-plan.json", "fit plan").read_bytes()
    plan = _json_load(plan_bytes)
    protocol = _regular_file(output / "frozen-protocol.json", "frozen protocol").read_bytes()
    envelope = _read_protocol(protocol)
    decision_bytes = _regular_file(output / "research-use-decision.json", "research-use decision").read_bytes()
    decision = _read_research_decision(decision_bytes, receipt["nistTrainingSource"]["receipt"])
    if (receipt.get("version") != FIT_VERSION or receipt.get("scope") != SCOPE
            or receipt.get("arms") != list(ARMS) or receipt.get("contract") != frozen_protocol()
            or receipt.get("sourceSHA256") != SOURCE_SHA256 or receipt.get("codeSHA256") != code_identity()
            or receipt.get("selection") != "fixed-final-epoch-only-no-development-selection"
            or receipt.get("researchUseDecision") != decision
            or receipt.get("researchUseDecisionSHA256") != RESEARCH_DECISION_SHA256
            or payload != _json_bytes(receipt) or plan_bytes != _json_bytes(plan)
            or _sha256(plan_bytes) != receipt.get("fitPlanSHA256")
            or _sha256(protocol) != receipt.get("protocolSHA256") or envelope != receipt.get("protocolEnvelope")
            or any(receipt.get(key) != value for key, value in plan.items())):
        raise ValueError("Fit evidence differs from the fixed paired experiment")
    return receipt


def load_fitted_models(output):
    output, receipt = Path(output), _load_fit_receipt(output)
    models, _, _ = initialized_models(receipt["vocabulary"])
    for arm, model in models.items():
        if receipt["weightFiles"][arm] != f"weights/{arm}.pt":
            raise ValueError("Unexpected checkpoint path")
        payload = _regular_file(output / receipt["weightFiles"][arm], "checkpoint").read_bytes()
        if _sha256(payload) != receipt["weightsSHA256"][arm]:
            raise ValueError("Checkpoint bytes changed")
        checkpoint = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
        expected = {"version": FIT_VERSION, "arm": arm, "finalEpoch": FINETUNE_EPOCHS,
            "sourceSHA256": SOURCE_SHA256, "protocolSHA256": receipt["protocolSHA256"],
            "initialStateSHA256": receipt["initialState"]["sha256"], "vocabulary": receipt["vocabulary"]}
        if set(checkpoint) != set(expected) | {"state_dict"} or any(checkpoint[key] != value for key, value in expected.items()):
            raise ValueError("Checkpoint metadata changed")
        state, schema = checkpoint["state_dict"], model.state_dict()
        if (set(state) != set(schema) or any(not isinstance(state[key], torch.Tensor)
                or state[key].shape != schema[key].shape or state[key].dtype != schema[key].dtype
                or not torch.isfinite(state[key]).all() for key in schema)):
            raise ValueError("Checkpoint tensor schema changed or is nonfinite")
        model.load_state_dict(state, strict=True)
        if _state_digest(model.state_dict()) != receipt["finalStateSHA256"][arm]:
            raise ValueError("Checkpoint state changed")
        model.eval()
    return models, receipt


def load_training_feature_bundle(output, arm, receipt=None):
    if arm not in ARMS:
        raise ValueError("Unknown broad transfer arm")
    output, saved = Path(output), _load_fit_receipt(output)
    if receipt is not None and _json_bytes(receipt) != _json_bytes(saved):
        raise ValueError("Supplied fit receipt differs")
    receipt = saved
    inputs = receipt["trainingInputs"]
    order = _training_feature_order(inputs)
    if (_sha256(_json_bytes(inputs)) != receipt["trainingInputsSHA256"]
            or _sha256(_json_bytes(order)) != receipt["trainingFeatureOrderSHA256"]
            or set(row["writer"] for row in order) != set(receipt["trainingWriters"])
            or set(row["label"] for row in order) != set(receipt["vocabulary"])
            or receipt["trainingFeatureFiles"][arm] != f"training-features/{arm}.npz"):
        raise ValueError("Training feature roles/order changed")
    payload = _regular_file(output / receipt["trainingFeatureFiles"][arm], "training features").read_bytes()
    if _sha256(payload) != receipt["trainingFeaturesSHA256"][arm]:
        raise ValueError("Training feature bytes changed")
    expected = {name: [row[key] for row in order] for name, key in
                (("labels", "label"), ("writers", "writer"), ("sourceIDs", "sourceID"),
                 ("sessions", "session"), ("rasterSHA256", "rasterSHA256"))}
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        if set(bundle.files) != set(expected) | {"features"}:
            raise ValueError("Training feature bundle schema changed")
        arrays = {name: bundle[name].copy() for name in bundle.files}
    if any(arrays[name].shape != (FINETUNE_ROWS,) or arrays[name].tolist() != values for name, values in expected.items()):
        raise ValueError("Training feature identities changed")
    features = arrays["features"]
    if (features.dtype != np.float32 or features.shape != (FINETUNE_ROWS, 128)
            or not np.isfinite(features).all()
            or not np.allclose(np.linalg.norm(features, axis=1), 1, rtol=1e-4, atol=1e-5)):
        raise ValueError("Training feature vectors changed")
    return arrays


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "nist-dir", "protocol", "output", "research-decision"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    args = parser.parse_args()
    result = fit(args.source, args.nist_dir, args.protocol, args.output, research_decision=args.research_decision)
    print(json.dumps({"version": result["version"], "weightsSHA256": result["weightsSHA256"],
        "productionEligible": result["roleGuards"]["productionEligible"]}, sort_keys=True), flush=True)
