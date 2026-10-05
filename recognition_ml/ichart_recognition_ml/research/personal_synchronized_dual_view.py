"""One matched synchronized-augmentation experiment, public research only.

Fit and prediction are separate processes. No private/reserved feature encoding,
app modification, checkpoint selection, confidence claim or production export.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import io
import math
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F

from ..contracts import canonical_json_bytes
from . import personal_dual_view as previous
from . import personal_synchronized_augmentation as augmentation
from . import personal_synchronized_dual_view_scoring as scoring
from .uji_personal import SOURCE_SHA256, load_official_source

ARMS = scoring.ARMS


def initialized_models():
    """Reuse the original seed29 initial tensors, never a historical final fit."""
    initial = previous._initial_state()
    models = {}
    for arm in ARMS:
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(29)
            model = previous.PersonalDualViewEncoder(97, arm)
        model.load_state_dict(copy.deepcopy(initial), strict=True)
        models[arm] = model
    reference = models[ARMS[0]].state_dict()
    keys = sorted(reference)
    metadata = {"armSHA256": {a: previous._state_digest(m.state_dict()) for a, m in models.items()},
        "sha256": previous._state_digest(reference), "stateKeysSHA256": previous._sha256(canonical_json_bytes(keys)),
        "stateKeyCount": len(keys), "parameterCount": sum(p.numel() for p in models[ARMS[0]].parameters())}
    if metadata != scoring.INITIAL_STATE:
        raise ValueError("Initial tensors are not the fixed original seed29 state")
    return models, metadata


def source_mapping(sample):
    """Map canonical features using original source extrema, not resampled rows."""
    points = [point for stroke in sample.strokes for point in stroke.points]
    if not points or any(not math.isfinite(p.x) or not math.isfinite(p.y) for p in points):
        raise ValueError("Source mapping requires finite original geometry")
    width = max(p.x for p in points) - min(p.x for p in points)
    height = max(p.y for p in points) - min(p.y for p in points)
    extent = max(width, height)
    if not all(math.isfinite(x) for x in (width, height, extent)):
        raise ValueError("Source geometry extent overflow")
    normalized_width = width / extent if extent else 0.0
    normalized_height = height / extent if extent else 0.0
    scales = [span / dimension for span, dimension in ((237.0, normalized_width), (77.0, normalized_height)) if dimension > 0]
    scale = min(scales) if scales else 0.0
    return augmentation.CanonicalRasterMapping(normalized_width, normalized_height, scale)


def source_mappings(samples):
    mappings = tuple(source_mapping(s) for s in samples)
    rows = [{"opaqueID": previous.opaque_id(SOURCE_SHA256, sample.identity),
        "normalizedWidth": mapping.normalized_width, "normalizedHeight": mapping.normalized_height,
        "sourceRasterScale": mapping.pixels_per_unit, "effectivePixelsPerUnit": mapping.effective_pixels_per_unit}
        for sample, mapping in zip(samples, mappings)]
    return mappings, rows


def _stream_update(digest, payload):
    digest.update(len(payload).to_bytes(8, "big"))
    digest.update(payload)


def training_step(model, trajectory, raster, targets, optimizer):
    optimizer.zero_grad(set_to_none=True)
    _, logits = model(trajectory, raster)
    loss = F.cross_entropy(logits, targets)
    if not torch.isfinite(loss):
        raise ValueError("Nonfinite synchronized training loss")
    loss.backward()
    if any(p.grad is not None and not torch.isfinite(p.grad).all() for p in model.parameters()):
        raise ValueError("Nonfinite synchronized training gradient")
    optimizer.step()
    return float(loss.detach()), int((logits.detach().argmax(1) == targets).sum())


def train_arm(model, arm, batch, targets, source_ids, mappings):
    if arm not in ARMS or model.arm != arm or len(targets) != 6208 or len(batch.raster) != 6208 or len(batch.trajectory) != 6208 or len(source_ids) != 6208 or len(set(source_ids)) != 6208 or len(mappings) != 6208:
        raise ValueError("Incomplete training cohort or arm mask")
    if augmentation.VERSION != scoring.AUGMENTATION_VERSION:
        raise ValueError("Synchronized augmentation version differs")
    generator = torch.Generator(device="cpu").manual_seed(29)
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=30)
    history, epoch_ledgers = [], []
    complete_draws, complete_permutations, complete_features = (hashlib.sha256() for _ in range(3))
    for epoch in range(1, 31):
        model.train()
        permutation = torch.randperm(6208, generator=generator)
        permutation_bytes = permutation.numpy().astype("<i8", copy=False).tobytes()
        _stream_update(complete_permutations, permutation_bytes)
        draws, features = hashlib.sha256(), hashlib.sha256()
        total_loss, correct, batch_count = 0.0, 0, 0
        for indexes in permutation.split(128):
            positions = indexes.tolist()
            transforms = tuple(augmentation.derive_transform(29, epoch, source_ids[i]) for i in positions)
            augmented = augmentation.augment_batch(batch.trajectory[indexes].float(), batch.raster[indexes].float() / 255.0,
                transforms, tuple(mappings[i] for i in positions))
            metadata_bytes = canonical_json_bytes(augmented.metadata)
            if previous._sha256(metadata_bytes) != augmented.metadata_sha256:
                raise ValueError("Augmentation metadata bytes/digest mismatch")
            _stream_update(draws, metadata_bytes)
            _stream_update(complete_draws, metadata_bytes)
            for tensor in (augmented.trajectory, augmented.raster):
                payload = tensor.detach().cpu().contiguous().numpy().astype("<f4", copy=False).tobytes()
                _stream_update(features, payload)
                _stream_update(complete_features, payload)
            loss, batch_correct = training_step(model, augmented.trajectory, augmented.raster, targets[indexes], optimizer)
            total_loss += loss * len(indexes)
            correct += batch_correct
            batch_count += 1
        scheduler.step()
        report = {"epoch": epoch, "trainCorrect": correct, "trainLoss": total_loss / 6208}
        history.append(report)
        epoch_ledgers.append({"epoch": epoch, "sampleCount": 6208, "batchCount": batch_count,
            "drawStreamSHA256": draws.hexdigest(), "permutationSHA256": previous._sha256(permutation_bytes),
            "permutationOrdinals": permutation.tolist(),
            "augmentedFeatureSHA256": features.hexdigest()})
        print(canonical_json_bytes({"arm": arm, **report, "batchCount": batch_count}).decode(), flush=True)
    if any(not torch.isfinite(t).all() for t in model.state_dict().values() if t.is_floating_point()):
        raise ValueError("Nonfinite final checkpoint tensor")
    ledger = {"epochs": epoch_ledgers, "sampleExposures": 6208 * 30, "updateCount": 49 * 30,
        "drawStreamSHA256": complete_draws.hexdigest(), "permutationStreamSHA256": complete_permutations.hexdigest(),
        "augmentedFeatureStreamSHA256": complete_features.hexdigest()}
    return history, ledger


def checkpoint_bytes(model, arm, vocabulary_sha):
    if model.arm != arm or arm not in ARMS:
        raise ValueError("Checkpoint arm mask differs from trained model")
    buffer = io.BytesIO()
    torch.save({"architectureVersion": previous.ARCHITECTURE_VERSION, "arm": arm,
        "stateDict": model.state_dict(), "version": scoring.FIT_VERSION,
        "vocabularySHA256": vocabulary_sha}, buffer)
    return buffer.getvalue()


def load_checkpoint(payload, arm, vocabulary_sha):
    checkpoint = previous._require_exact_keys(torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True),
        {"architectureVersion", "arm", "stateDict", "version", "vocabularySHA256"}, "checkpoint")
    if arm not in ARMS or checkpoint["architectureVersion"] != previous.ARCHITECTURE_VERSION or checkpoint["arm"] != arm or checkpoint["version"] != scoring.FIT_VERSION or checkpoint["vocabularySHA256"] != vocabulary_sha or not isinstance(checkpoint["stateDict"], dict):
        raise ValueError("Checkpoint version/vocabulary/arm mask mismatch")
    model = previous.PersonalDualViewEncoder(97, arm)
    model.load_state_dict(checkpoint["stateDict"], strict=True)
    if any(not torch.isfinite(t).all() for t in model.state_dict().values() if t.is_floating_point()):
        raise ValueError("Nonfinite checkpoint tensor")
    return model


def prediction_rows(samples, batch, outputs):
    if set(outputs) != set(ARMS) or len(samples) != len(batch.trajectory):
        raise ValueError("Incomplete prediction arms/cohort")
    rows = []
    for index, sample in enumerate(samples):
        values = {}
        for arm in ARMS:
            embeddings, logits = outputs[arm]
            if embeddings.shape != (len(samples), 128) or logits.shape != (len(samples), 97) or not np.isfinite(embeddings[index]).all() or not np.isfinite(logits[index]).all():
                raise ValueError("Malformed or nonfinite prediction matrix")
            values[arm] = {"embedding": [float(x) for x in embeddings[index]], "rawLogits": [float(x) for x in logits[index]]}
        rows.append({"opaqueID": previous.opaque_id(SOURCE_SHA256, sample.identity), "outputs": values,
            "rasterSHA256": batch.raster_hashes[index], "trajectorySHA256": batch.trajectory_hashes[index],
            "sourceGroups": [list(range(len(sample.strokes)))]})
    rows.sort(key=lambda r: r["opaqueID"])
    if len({r["opaqueID"] for r in rows}) != len(rows):
        raise ValueError("Duplicate prediction source identity")
    return rows


def _preserved(snapshot, code):
    if any(previous._sha256(p.read_bytes()) != value for p, value in snapshot.items()) or scoring.code_identity() != code:
        raise ValueError("Bound source, protocol, fit, weights or code changed")


def _inputs(source, protocol):
    source = previous._require_regular_file(source, kind="public source")
    protocol = previous._require_regular_file(protocol, kind="frozen protocol")
    code = scoring.code_identity()
    protocol_bytes = protocol.read_bytes()
    if previous._sha256(source.read_bytes()) != SOURCE_SHA256 or previous._sha256(protocol_bytes) != code[scoring.PROTOCOL_PATH]:
        raise ValueError("Pinned source/protocol differs from frozen code")
    previous._configure_runtime()
    records = load_official_source(source)
    return source, protocol, protocol_bytes, code, records, previous._validate_roles(records)


def fit(source, protocol, output):
    source, protocol, protocol_bytes, code, records, roles = _inputs(source, protocol)
    snapshot = previous._input_snapshot((source, protocol))
    snapshot.update({source: SOURCE_SHA256, protocol: previous._sha256(protocol_bytes)})
    training = previous._select_role_samples(records, roles[0], 6208)
    vocabulary = previous._vocabulary(training)
    vocabulary_sha = previous.vocabulary_digest(vocabulary)
    targets = torch.tensor([vocabulary.index(s.label) for s in training], dtype=torch.long)
    batch = previous.encode_samples(training, roles[0], include_normalized_trajectory_hashes=True)
    mappings, mapping_rows = source_mappings(training)
    scoring.validate_source_mappings(mapping_rows)
    training_hashes = previous._training_input_hashes(batch)
    source_ids = tuple(previous.opaque_id(SOURCE_SHA256, s.identity) for s in training)
    models, initial = initialized_models()
    output = previous._new_output_directory(output)
    (output / "weights").mkdir(mode=0o700)
    previous._write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    histories, ledgers, weights = {}, {}, {}
    for arm in ARMS:
        if previous._state_digest(models[arm].state_dict()) != initial["sha256"]:
            raise ValueError("Arm initial tensors differ before fit")
        histories[arm], ledgers[arm] = train_arm(models[arm], arm, batch, targets, source_ids, mappings)
        payload = checkpoint_bytes(models[arm], arm, vocabulary_sha)
        # Validate the actual serialized final checkpoint before publication.
        loaded = load_checkpoint(payload, arm, vocabulary_sha)
        if previous._state_digest(loaded.state_dict()) != previous._state_digest(models[arm].state_dict()):
            raise ValueError("Final checkpoint save/reload differs")
        previous._write_exclusive(output / "weights" / f"{arm}.pt", payload)
        weights[arm] = previous._sha256(payload)
    scoring.validate_ledger(ledgers)
    receipt = {"version": scoring.FIT_VERSION, "scope": scoring.SCOPE, "arms": list(ARMS),
        "sourceSHA256": SOURCE_SHA256, "protocolSHA256": previous._sha256(protocol_bytes), "codeSHA256": code,
        "runtime": previous._runtime_contract(), "featureContract": scoring.FEATURE_CONTRACT,
        "modelContract": scoring.MODEL_CONTRACT, "optimization": scoring.OPTIMIZATION,
        "augmentationContract": scoring.AUGMENTATION_CONTRACT, "augmentationLedger": ledgers,
        "sourceRasterMappings": mapping_rows, "sourceRasterMappingsSHA256": previous._sha256(canonical_json_bytes(mapping_rows)),
        "trainingWriters": list(roles[0]), "developmentWriters": list(roles[1]), "reservedWriters": list(roles[2]),
        "trainingSamples": 6208, "developmentSamples": 1552, "reservedSamples": 3880,
        "vocabulary": list(vocabulary), "vocabularySHA256": vocabulary_sha, "initialState": initial,
        "weightFiles": {a: f"weights/{a}.pt" for a in ARMS}, "weightsSHA256": weights,
        "trainingInputHashes": training_hashes, "trainingInputHashesSHA256": previous._sha256(canonical_json_bytes(training_hashes)),
        "trainingHistory": histories, "selection": "final-epoch-only", "roleGuards": scoring.ROLE_GUARDS}
    scoring.validate_fit_receipt(receipt, code, previous._sha256(protocol_bytes), weights)
    _preserved(snapshot, code)
    previous._write_exclusive(output / "fit-receipt.json", canonical_json_bytes(receipt))


def predict(source, protocol, fit_directory, output):
    source, protocol, protocol_bytes, code, records, roles = _inputs(source, protocol)
    fit_directory = previous._require_directory(fit_directory, kind="fit directory")
    fit_path = fit_directory / "fit-receipt.json"
    receipt, receipt_bytes = previous._read_canonical_json(fit_path, kind="fit receipt")
    frozen_protocol = previous._require_regular_file(fit_directory / "frozen-protocol.md", kind="fit protocol")
    if frozen_protocol.read_bytes() != protocol_bytes:
        raise ValueError("Fit frozen protocol differs")
    paths = {a: previous._require_regular_file(fit_directory / "weights" / f"{a}.pt", kind="checkpoint") for a in ARMS}
    payloads = {a: p.read_bytes() for a, p in paths.items()}
    weights = {a: previous._sha256(payload) for a, payload in payloads.items()}
    scoring.validate_fit_receipt(receipt, code, previous._sha256(protocol_bytes), weights)
    if receipt["runtime"] != previous._runtime_contract() or tuple(receipt[k] for k in ("trainingWriters", "developmentWriters", "reservedWriters")) != tuple(list(r) for r in roles):
        raise ValueError("Fit source roles/runtime differ")
    snapshot = previous._input_snapshot((source, protocol, fit_path, frozen_protocol, *paths.values()))
    snapshot.update({source: SOURCE_SHA256, fit_path: previous._sha256(receipt_bytes), protocol: previous._sha256(protocol_bytes), frozen_protocol: previous._sha256(protocol_bytes), **{paths[a]: weights[a] for a in ARMS}})
    # All final checkpoints and masks validated before development encoding.
    models = {a: load_checkpoint(payloads[a], a, receipt["vocabularySHA256"]) for a in ARMS}
    development = previous._select_role_samples(records, roles[1], 1552)
    if previous._vocabulary(development) != tuple(receipt["vocabulary"]):
        raise ValueError("Development vocabulary differs")
    ordered = tuple(sorted(development, key=lambda s: previous.opaque_id(SOURCE_SHA256, s.identity)))
    batch = previous.encode_samples(ordered, roles[1], include_normalized_trajectory_hashes=False)
    outputs = {a: previous._infer(models[a], batch) for a in ARMS}
    packet = {"version": scoring.PREDICTION_VERSION, "scope": scoring.SCOPE, "arms": list(ARMS),
        "rowCount": 1552, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": previous._sha256(protocol_bytes),
        "codeSHA256": code, "runtime": previous._runtime_contract(), "featureContract": scoring.FEATURE_CONTRACT,
        "fitReceiptSHA256": previous._sha256(receipt_bytes), "weightsSHA256": weights,
        "vocabularySHA256": receipt["vocabularySHA256"], "rows": prediction_rows(ordered, batch, outputs)}
    payload = canonical_json_bytes(packet)
    scoring.validate_prediction_packet(payload, receipt, receipt_bytes, code, previous._sha256(protocol_bytes), weights)
    _preserved(snapshot, code)
    output = previous._new_output_directory(output)
    previous._write_exclusive(output / "predictions.json", payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("fit", "predict"):
        sub = commands.add_parser(command)
        for name in ("source", "protocol", "output"):
            sub.add_argument(f"--{name}", type=Path, required=True)
        if command == "predict":
            sub.add_argument("--fit", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "fit":
        fit(args.source, args.protocol, args.output)
    else:
        predict(args.source, args.protocol, args.fit, args.output)


if __name__ == "__main__":
    main()
