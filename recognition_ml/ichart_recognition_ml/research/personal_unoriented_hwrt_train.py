"""One fixed direction-neutral HWRT/UJI paired fit; research only.

Reuse the frozen planner, initialization tensors, optimizer and numerical
update helpers. Only the field augmenter and public artifact identity change.
No development field or truth is opened; reproducibility sentinels must pass
before a success receipt can be published.
"""
from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path

import numpy as np
import torch

from ..contracts import canonical_json_bytes as canonical
from . import personal_hwrt_stroke_train as old
from . import personal_unoriented_stroke_field as field
from . import personal_unoriented_hwrt_data as data

VERSION = "personal-unoriented-hwrt-fit-v1"
SCOPE = "research-only-matched-unoriented-hwrt-v1"
PLAN_VERSION = "personal-unoriented-hwrt-training-plan-v1"
PROTOCOL = "docs/personal-unoriented-stroke-field-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "4d72f1e61e409e8da9c563dc7a8eca430370675b5b6fa81eeab9dad327178fe3"
ROOT, ARMS, RECIPE = old.ROOT, old.ARMS, old.RECIPE
SENTINELS = {
    "rasterControlStateSHA256": "ca97f42d345c3e7e777ef92412db30e7a26930f0b2f8411873e5db8505970c99",
    "scheduleSHA256": "d1ef91c13bb4477de88c57510851149177e528858f0e2bfcf69643b8c062d6ed",
    "augmentationDrawStreamSHA256": "1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc",
}
FIT_RECEIPT_FIELDS = old.FIT_RECEIPT_FIELDS | {"reproducibilitySentinels"}
_require, _sha256, _digest = old._require, old._sha256, old._digest
_read, _parsed, _file_sha256 = old._read, old._parsed, old._file_sha256
_tensor_bytes, _tensor_sha256, _stream_update = old._tensor_bytes, old._tensor_sha256, old._stream_update
_state_digest, _runtime_contract = old._state_digest, old._runtime_contract


def code_identity():
    result = data.code_identity()
    _require(result.get(PROTOCOL) == PROTOCOL_SHA256
             and result.get("recognition_ml/ichart_recognition_ml/research/personal_unoriented_hwrt_train.py")
             == _sha256(_read(Path(__file__).resolve(), maximum=32 * 1024 * 1024)), "Neutral executable identity changed")
    return result


def _new_model(arm):
    _require(arm in ARMS and tuple(field.ARMS) == tuple(ARMS), "Neutral arm seam changed")
    with torch.random.fork_rng(devices=[]):
        model = field.PersonalUnorientedStrokeFieldEncoder(old.LABEL_COUNT, arm)
    return model


def initialized_models():
    # The old stateless initializer is used only for new seed29 tensors, never
    # a historical checkpoint. New model objects retain the neutral identity.
    tensors, expected = old.initialized_models()
    models = {arm: _new_model(arm) for arm in ARMS}
    for arm in ARMS:
        models[arm].load_state_dict(tensors[arm].state_dict(), strict=True)
    _require({_state_digest(m.state_dict()) for m in models.values()} == {expected}, "Complete initial states diverged")
    return models, expected


def _validate_training(fields, metadata, receipt):
    _require(isinstance(fields, np.memmap) and fields.dtype == np.float32 and fields.shape == (10073, 5, 96, 256)
             and not fields.flags.writeable and fields.flags.c_contiguous, "Read-only complete training mmap required")
    _require(set(metadata) == {"version", "vocabulary", "rows"} and metadata["version"] == data.TRAINING_VERSION
             and receipt["version"] == data.DATA_VERSION and receipt["fieldVersion"] == field.VERSION
             and receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["role"] == "training"
             and receipt["codeSHA256"] == data.code_identity() and receipt["fitReceiptSHA256"] is None
             and receipt["trainingDataReceiptSHA256"] is None, "Neutral training role/identity changed")
    rows, vocabulary = metadata["rows"], tuple(metadata["vocabulary"])
    _require(len(rows) == 10073 and len(vocabulary) == len(set(vocabulary)) == 102
             and vocabulary[:97] == tuple(sorted(vocabulary[:97])) and vocabulary[97:] == old.NOVEL_LABELS
             and receipt["vocabulary"] == list(vocabulary)
             and receipt["vocabularySHA256"] == old._vocabulary_sha256(vocabulary), "Training vocabulary/count changed")
    ids, counts = set(), {label: 0 for label in vocabulary}
    for row in rows:
        _require(set(row) == old.ROW_FIELDS and row["opaqueID"] not in ids and row["label"] in counts
                 and all(_digest(row[k]) for k in ("rasterSHA256", "fieldSHA256", "normalizedGeometrySHA256")), "Training row changed")
        ids.add(row["opaqueID"]); counts[row["label"]] += 1
        if row["source"] == "uji":
            _require(row["label"] in vocabulary[:97] and row["writer"] is not None and row["session"] in (1, 2)
                     and row["nativeSymbolID"] is None, "UJI training role changed")
        else:
            _require(row["source"] == "hwrt" and row["writer"] is row["session"] is None
                     and old.NATIVE_MAPPING.get(row["nativeSymbolID"]) == row["label"], "HWRT native training role changed")
    _require(all(counts[label] == 64 for label in vocabulary[:97])
             and {label: counts[label] for label in old.NOVEL_LABELS} == old.NOVEL_COUNTS, "Training source counts changed")
    return rows, vocabulary


def build_training_plan(rows, vocabulary):
    value = old.build_training_plan(rows, vocabulary)
    value.update({"version": PLAN_VERSION, "fieldVersion": field.VERSION, "modelVersion": field.MODEL_VERSION,
                  "reproducibilitySentinels": SENTINELS})
    _require(value["scheduleSHA256"] == SENTINELS["scheduleSHA256"], "Preserved exposure schedule sentinel failed")
    return value


def train_models(models, fields, rows, vocabulary, plan):
    _require(plan["version"] == PLAN_VERSION and plan["fieldVersion"] == field.VERSION
             and len(plan["epochs"]) == old.EPOCHS, "Neutral training plan changed")
    optimizers, schedulers = old._optimizers(models)
    label_index = {label: i for i, label in enumerate(vocabulary)}
    generator = torch.Generator(device="cpu").manual_seed(old.SEED)
    histories = {arm: [] for arm in ARMS}
    draw_stream, input_stream, order_stream = (hashlib.sha256() for _ in range(3))
    actual_streams = {arm: hashlib.sha256() for arm in ARMS}
    updates = 0
    for epoch in plan["epochs"]:
        order = epoch["rowIndices"]; order_bytes = np.asarray(order, dtype="<i8").tobytes()
        _require(len(order) == 6528 and _sha256(order_bytes) == epoch["permutationSHA256"], "Frozen epoch order changed")
        _stream_update(order_stream, order_bytes)
        aggregates = {arm: {"loss": 0.0, "correct": 0} for arm in ARMS}
        for offset in range(0, len(order), old.BATCH_SIZE):
            indexes = order[offset:offset + old.BATCH_SIZE]
            _require(len(indexes) == 128, "Fixed training batch size changed")
            source = torch.from_numpy(np.array(fields[indexes], dtype=np.float32, copy=True, order="C"))
            source_before = _tensor_sha256(source)
            draws = field.sample_affine_draws(128, generator)
            _stream_update(draw_stream, _tensor_bytes(draws))
            augmented = field.augment_unoriented_stroke_fields(source, draws)
            _require(_tensor_sha256(source) == source_before, "Neutral augmentation mutated prepared fields")
            payload = _tensor_bytes(augmented); _stream_update(input_stream, payload)
            targets = torch.tensor([label_index[rows[i]["label"]] for i in indexes], dtype=torch.long)
            reports = old._paired_step(models, optimizers, augmented, targets)
            for arm in ARMS:
                _require(reports[arm]["actualInputSHA256"] == _sha256(payload), "Forward input proof changed")
                _stream_update(actual_streams[arm], payload)
                aggregates[arm]["loss"] += reports[arm]["loss"] * len(indexes)
                aggregates[arm]["correct"] += reports[arm]["correct"]
            updates += 1
        for arm in ARMS:
            schedulers[arm].step()
            histories[arm].append({"epoch": epoch["epoch"], "meanLoss": aggregates[arm]["loss"] / 6528,
                "correct": aggregates[arm]["correct"], "learningRate": float(schedulers[arm].get_last_lr()[0])})
        print(canonical({"epoch": epoch["epoch"], "cumulativeUpdatesPerArm": updates,
            "cumulativeExposuresPerArm": epoch["epoch"] * 6528,
            "arms": {arm: {"meanTrainingLoss": histories[arm][-1]["meanLoss"],
                           "trainingCorrect": histories[arm][-1]["correct"]} for arm in ARMS}}).decode(), flush=True)
    _require(updates == 1530 and order_stream.hexdigest() == plan["scheduleSHA256"]
             and all(s.last_epoch == 30 for s in schedulers.values()), "Completed optimizer/order count changed")
    _require({s.hexdigest() for s in actual_streams.values()} == {input_stream.hexdigest()}, "Matched input streams diverged")
    ledgers = {arm: {"epochs": 30, "updates": updates, "exposures": 195840, "scheduleSHA256": plan["scheduleSHA256"],
        "batchOrderStreamSHA256": order_stream.hexdigest(), "augmentationDrawStreamSHA256": draw_stream.hexdigest(),
        "augmentedFeatureStreamSHA256": input_stream.hexdigest(), "actualForwardInputStreamSHA256": actual_streams[arm].hexdigest()}
        for arm in ARMS}
    return histories, ledgers


def validate_sentinels(final_states, ledgers):
    _require(final_states["rasterControl"] == SENTINELS["rasterControlStateSHA256"], "Refitted raster control state sentinel failed")
    for arm in ARMS:
        _require(ledgers[arm]["scheduleSHA256"] == SENTINELS["scheduleSHA256"]
                 and ledgers[arm]["augmentationDrawStreamSHA256"] == SENTINELS["augmentationDrawStreamSHA256"],
                 "Preserved schedule/affine draw sentinel failed")


def checkpoint_bytes(model, arm, vocabulary_sha256):
    _require(isinstance(model, field.PersonalUnorientedStrokeFieldEncoder) and arm in ARMS and model.arm == arm
             and model.label_count == 102 and _digest(vocabulary_sha256), "Neutral checkpoint model identity changed")
    buffer = io.BytesIO()
    torch.save({"version": VERSION, "arm": arm, "fieldVersion": field.VERSION, "modelVersion": field.MODEL_VERSION,
        "labelCount": 102, "vocabularySHA256": vocabulary_sha256, "stateDict": model.state_dict()}, buffer)
    return buffer.getvalue()


def load_checkpoint(payload, arm, vocabulary_sha256):
    try:
        value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    except Exception as error:
        raise ValueError("Invalid neutral checkpoint") from error
    _require(isinstance(value, dict) and set(value) == {"version", "arm", "fieldVersion", "modelVersion", "labelCount", "vocabularySHA256", "stateDict"}
             and (value["version"], value["arm"], value["fieldVersion"], value["modelVersion"], value["labelCount"], value["vocabularySHA256"])
             == (VERSION, arm, field.VERSION, field.MODEL_VERSION, 102, vocabulary_sha256), "Neutral checkpoint identity changed")
    model = _new_model(arm)
    try:
        model.load_state_dict(value["stateDict"], strict=True)
    except (RuntimeError, ValueError, TypeError) as error:
        raise ValueError("Neutral checkpoint state changed") from error
    _require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values() if t.is_floating_point()), "Nonfinite neutral checkpoint")
    return model


def _validate_fit_receipt(receipt, *, code=None):
    _require(isinstance(receipt, dict) and set(receipt) == FIT_RECEIPT_FIELDS, "Neutral fit receipt schema changed")
    _require((receipt["version"], receipt["scope"], receipt["fieldVersion"], receipt["modelVersion"], receipt["labelCount"], receipt["arms"])
             == (VERSION, SCOPE, field.VERSION, field.MODEL_VERSION, 102, list(ARMS)), "Neutral fit identity changed")
    v = receipt["vocabulary"]
    _require(isinstance(v, list) and len(v) == len(set(v)) == 102 and v[:97] == sorted(v[:97])
             and tuple(v[97:]) == old.NOVEL_LABELS and old._vocabulary_sha256(v) == receipt["vocabularySHA256"], "Neutral fit vocabulary changed")
    _require(receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["recipe"] == RECIPE
             and receipt["selection"] == "final-epoch-only" and receipt["reproducibilitySentinels"] == SENTINELS,
             "Neutral fit recipe/protocol/sentinel declaration changed")
    _require(code is None or receipt["codeSHA256"] == code, "Neutral executed code changed")
    _require(_digest(receipt["dataReceiptSHA256"]) and set(receipt["dataArtifactsSHA256"]) == {"fields.npy", "training.json"}
             and all(_digest(x) for x in receipt["dataArtifactsSHA256"].values()), "Neutral training artifact bindings changed")
    _require(_digest(receipt["initialStateSHA256"]) and receipt["initialArmStateSHA256"] == {a: receipt["initialStateSHA256"] for a in ARMS}
             and receipt["weightFiles"] == {a: f"weights/{a}.pt" for a in ARMS}
             and set(receipt["weightsSHA256"]) == set(receipt["finalStateSHA256"]) == set(ARMS)
             and all(_digest(x) for x in receipt["weightsSHA256"].values())
             and all(_digest(x) and x != receipt["initialStateSHA256"] for x in receipt["finalStateSHA256"].values()), "Neutral state/weight bindings changed")
    _require(receipt["trainingPlanPath"] == "training-plan.json" and _digest(receipt["trainingPlanSHA256"]), "Neutral plan binding changed")
    ledger_keys = {"epochs", "updates", "exposures", "scheduleSHA256", "batchOrderStreamSHA256", "augmentationDrawStreamSHA256",
                   "augmentedFeatureStreamSHA256", "actualForwardInputStreamSHA256"}
    _require(set(receipt["augmentationLedger"]) == set(receipt["trainingHistory"]) == set(ARMS), "Neutral paired arms missing")
    for arm in ARMS:
        ledger = receipt["augmentationLedger"][arm]
        _require(set(ledger) == ledger_keys and (ledger["epochs"], ledger["updates"], ledger["exposures"]) == (30, 1530, 195840)
                 and all(_digest(ledger[k]) for k in ledger_keys - {"epochs", "updates", "exposures"})
                 and ledger["augmentedFeatureStreamSHA256"] == ledger["actualForwardInputStreamSHA256"]
                 and ledger["batchOrderStreamSHA256"] == ledger["scheduleSHA256"], "Neutral augmentation/count ledger changed")
        history = receipt["trainingHistory"][arm]
        _require(isinstance(history, list) and len(history) == 30, "Neutral epoch history incomplete")
        for epoch, row in enumerate(history, 1):
            _require(set(row) == {"epoch", "meanLoss", "correct", "learningRate"} and row["epoch"] == epoch
                     and type(row["correct"]) is int and 0 <= row["correct"] <= 6528
                     and all(type(row[k]) in (int, float) and np.isfinite(row[k]) and row[k] >= 0 for k in ("meanLoss", "learningRate")),
                     "Neutral epoch history malformed")
    _require(receipt["augmentationLedger"][ARMS[0]] == receipt["augmentationLedger"][ARMS[1]], "Neutral matched stream ledgers differ")
    validate_sentinels(receipt["finalStateSHA256"], receipt["augmentationLedger"])


def _preserved(code, snapshot):
    _require(code_identity() == code, "Neutral source/protocol changed during fit")
    for path, expected in snapshot.items():
        _require(_file_sha256(path) == expected, "Training artifact changed during neutral fit")


def fit(data_directory, protocol, output):
    data_directory, protocol = Path(data_directory), old._regular(Path(protocol), maximum=2 * 1024 * 1024)
    _require(data_directory.is_absolute() and data_directory.resolve() == data_directory and data_directory.is_dir()
             and not data_directory.is_symlink(), "Canonical training directory required")
    protocol_bytes = protocol.read_bytes()
    _require(_sha256(protocol_bytes) == PROTOCOL_SHA256 and protocol_bytes == _read(ROOT / PROTOCOL, maximum=2 * 1024 * 1024), "Frozen neutral protocol changed")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    code = code_identity(); receipt_bytes = _read(data_directory / "data-receipt.json", maximum=16 * 1024 * 1024)
    fields, metadata, data_receipt = data.load_training(data_directory)
    _require(data_receipt == _parsed(receipt_bytes, name="neutral-data-receipt"), "Bound neutral data receipt changed")
    rows, vocabulary = _validate_training(fields, metadata, data_receipt)
    snapshot = old._snapshot_data(data_directory, data_receipt, receipt_bytes)
    artifacts = {name: identity["sha256"] for name, identity in data_receipt["artifacts"].items()}
    plan = build_training_plan(rows, vocabulary)
    plan.update({"protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code, "dataReceiptSHA256": _sha256(receipt_bytes),
        "dataArtifactsSHA256": artifacts, "metadataSHA256": artifacts["training.json"]})
    plan_bytes = canonical(plan); models, initial_sha = initialized_models()
    output = old._fresh_directory(Path(output)); (output / "weights").mkdir(mode=0o700)
    old._write_exclusive(output / "frozen-protocol.md", protocol_bytes)
    old._copy_code_snapshot(output, code); old._write_exclusive(output / "training-plan.json", plan_bytes)
    histories, ledgers = train_models(models, fields, rows, vocabulary, plan)
    final_sha = {arm: _state_digest(model.state_dict()) for arm, model in models.items()}
    validate_sentinels(final_sha, ledgers)
    weight_sha = {}
    for arm in ARMS:
        payload = checkpoint_bytes(models[arm], arm, plan["vocabularySHA256"])
        restored = load_checkpoint(payload, arm, plan["vocabularySHA256"])
        _require(_state_digest(restored.state_dict()) == final_sha[arm], "Neutral checkpoint reload changed state")
        old._write_exclusive(output / "weights" / f"{arm}.pt", payload); weight_sha[arm] = _sha256(payload)
    _preserved(code, snapshot)
    _require(_sha256(_read(output / "training-plan.json")) == _sha256(plan_bytes)
             and _sha256(_read(output / "frozen-protocol.md")) == PROTOCOL_SHA256, "Frozen neutral fit plan/protocol snapshot changed")
    for relative, expected in code.items():
        _require(_sha256(_read(output / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Executed neutral code snapshot changed")
    receipt = {"version": VERSION, "scope": SCOPE, "arms": list(ARMS), "fieldVersion": field.VERSION,
        "modelVersion": field.MODEL_VERSION, "labelCount": 102, "vocabulary": list(vocabulary), "vocabularySHA256": plan["vocabularySHA256"],
        "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code, "dataReceiptSHA256": _sha256(receipt_bytes), "dataArtifactsSHA256": artifacts,
        "runtime": _runtime_contract(), "recipe": RECIPE, "initialStateSHA256": initial_sha,
        "initialArmStateSHA256": {arm: initial_sha for arm in ARMS}, "trainingPlanPath": "training-plan.json", "trainingPlanSHA256": _sha256(plan_bytes),
        "augmentationLedger": ledgers, "trainingHistory": histories, "weightFiles": {a: f"weights/{a}.pt" for a in ARMS},
        "weightsSHA256": weight_sha, "finalStateSHA256": final_sha, "selection": "final-epoch-only", "reproducibilitySentinels": SENTINELS}
    _validate_fit_receipt(receipt, code=code)
    old._write_exclusive(output / "fit-receipt.json", canonical(receipt))
    return receipt


def load_fitted_models(directory, expected_receipt_sha256):
    """Blind loader: weights, safe plan, executed code and receipt; no data/truth."""
    _require(_digest(expected_receipt_sha256), "Caller-pinned neutral fit receipt required")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    directory = Path(directory)
    _require(directory.is_absolute() and directory.resolve() == directory and directory.is_dir()
             and not directory.is_symlink(), "Canonical neutral fit directory required")
    payload = _read(directory / "fit-receipt.json", maximum=32 * 1024 * 1024)
    _require(_sha256(payload) == expected_receipt_sha256, "Neutral fit receipt SHA changed")
    receipt = _parsed(payload, name="neutral-fit-receipt"); code = code_identity()
    _validate_fit_receipt(receipt, code=code)
    _require(receipt["runtime"] == _runtime_contract(), "Neutral runtime contract changed")
    _require(_sha256(_read(directory / "frozen-protocol.md", maximum=2 * 1024 * 1024)) == PROTOCOL_SHA256
             and _sha256(_read(directory / receipt["trainingPlanPath"], maximum=64 * 1024 * 1024)) == receipt["trainingPlanSHA256"], "Neutral frozen plan/protocol changed")
    for relative, expected in code.items():
        _require(_sha256(_read(directory / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Neutral executed code snapshot changed")
    models = {}
    for arm in ARMS:
        payload = _read(directory / receipt["weightFiles"][arm], maximum=256 * 1024 * 1024)
        _require(_sha256(payload) == receipt["weightsSHA256"][arm], "Neutral checkpoint bytes changed")
        model = load_checkpoint(payload, arm, receipt["vocabularySHA256"])
        _require(_state_digest(model.state_dict()) == receipt["finalStateSHA256"][arm], "Neutral final state changed")
        models[arm] = model.cpu().eval()
    return models, receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", type=Path, required=True); p.add_argument("--protocol", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args(); fit(a.data, a.protocol, a.output)


if __name__ == "__main__":
    main()
