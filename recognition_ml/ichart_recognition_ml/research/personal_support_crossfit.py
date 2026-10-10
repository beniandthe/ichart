"""Training-writer-only cross-fitted packets for support-retrieval research.

The disposable encoders never fit their exported writers. Setup geometry mirrors
Swift PersonalInkShape and must pass retained geometry/pixel goldens before fit.
No development model inference, query-truth read, app change or promotion occurs.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import platform

import numpy as np
import torch
from torch.nn import functional as F

from ..features import FeatureEncodingError, InkPoint, InkStroke, RASTER_HEIGHT, RASTER_WIDTH, rasterize
from ..study_import import decode_canonical_study_packet
from .personal_cross_writer_contrastive import (_json_bytes, _new_output, _regular_file,
    _sha256, _state_digest, _write_exclusive, select_training_samples)
from .personal_cross_writer_evaluation import numeric_strokes, stroke_bits
from .personal_visual_encoder import PersonalVisualEncoder, augment, encode_samples, infer
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, trajectory_fingerprint

VERSION = "personal-support-crossfit-v1"
ARMS = ("fitA", "fitB")
SEED, EPOCHS, CPU_THREADS, FIT_ROWS, BATCH_ROWS, UPDATES_PER_ENCODER = 29, 30, 4, 3104, 128, 750
PROTOCOL_PATH = "docs/personal-support-retrieval-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "638533ec5bc3a1b29dc2cf9d01b0c683bebb57ba3290e6decbe80ac130675c78"
FIXTURE_SHA256 = "d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d"
APP_REPORT_SHA256 = "52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618"
GOLDEN_ROOT = Path("/Users/benirossman/.local/share/ichart/recognition-development/public-app-local-transfer-20261001.IGj03b")
CODE_PATHS = (PROTOCOL_PATH, "iChart/Recognition/ChordInkPersonalization.swift",
    "recognition_ml/ichart_recognition_ml/features.py", "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/schema.py", "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/study_import.py", "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_evaluation.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_crossfit.py",
    "recognition_ml/tests/test_personal_support_crossfit.py")


def code_identity():
    root = Path(__file__).resolve().parents[3]
    result = {path: _sha256((root / path).read_bytes()) for path in CODE_PATHS}
    if result[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Cross-fit protocol changed before execution")
    return result


def setup_shape(strokes):
    """Exact Double normalization/endpoint decimation; no invented extent.

    Swift rounds grid occupancy halfway away from zero. Occupancy is checked
    from *every mapped point*, not only the bounded retained stroke geometry.
    Distances/aspect are not model inputs and need not be reconstructed here.
    """
    strokes = tuple(strokes)
    points = [point for stroke in strokes for point in stroke.points]
    if (not strokes or len(strokes) > 64 or len(points) > 32768 or len(points) < 2
            or any(not math.isfinite(point.x) or not math.isfinite(point.y)
                   or abs(point.x) >= 1e8 or abs(point.y) >= 1e8 for point in points)):
        return None
    min_x, max_x = min(point.x for point in points), max(point.x for point in points)
    min_y, max_y = min(point.y for point in points), max(point.y for point in points)
    width, height = max_x - min_x, max_y - min_y
    extent = max(width, height)
    if extent < .5:
        return None
    scale = min(42. / max(width, extent * .025), 26. / max(height, extent * .025))
    offset_x, offset_y = (47. - width * scale) / 2., (31. - height * scale) / 2.
    normalized, occupied = [], set()
    for stroke in strokes:
        if not stroke.points:
            continue
        mapped = tuple(InkPoint((point.x - min_x) * scale + offset_x,
                                (point.y - min_y) * scale + offset_y) for point in stroke.points)
        step = max(1, math.ceil(len(mapped) / 128.))
        retained = list(mapped[::step])
        if retained[-1] != mapped[-1]:
            retained.append(mapped[-1])
        normalized.append(InkStroke(retained))
        for index, end in enumerate(mapped):
            start = mapped[max(0, index - 1)]
            count = max(1, math.ceil(math.hypot(end.x - start.x, end.y - start.y) * 2.))
            for sample in range(count + 1):
                fraction = sample / count
                x = min(47, max(0, math.floor(start.x + (end.x - start.x) * fraction + .5)))
                y = min(31, max(0, math.floor(start.y + (end.y - start.y) * fraction + .5)))
                occupied.add(y * 48 + x)
    return tuple(normalized) if len(occupied) >= 2 else None


def _geometry_close(actual, expected):
    return (len(actual) == len(expected) and all(len(left.points) == len(right.points)
        and all(abs(a.x - b.x) <= 1e-12 and abs(a.y - b.y) <= 1e-12
                and a.time_offset is None and b.time_offset is None for a, b in zip(left.points, right.points))
        and left.creation_time_offset is None and right.creation_time_offset is None
        for left, right in zip(actual, expected)))


def verify_support_adapter(fixture=GOLDEN_ROOT / "fixture.json", app_report=GOLDEN_ROOT / "report.json"):
    """Read declared support geometry only; never infer development queries."""
    fixture_bytes = _regular_file(fixture, "support golden fixture").read_bytes()
    report_bytes = _regular_file(app_report, "support golden app report").read_bytes()
    if _sha256(fixture_bytes) != FIXTURE_SHA256 or _sha256(report_bytes) != APP_REPORT_SHA256:
        raise ValueError("Retained support golden artifacts changed")
    fixture, report = json.loads(fixture_bytes), json.loads(report_bytes)
    if fixture["sourceSHA256"] != SOURCE_SHA256 or report["fixtureSHA256"] != FIXTURE_SHA256:
        raise ValueError("Retained support golden source mismatch")
    samples = {sample["id"]: sample for sample in fixture["samples"]}
    tasks = {(task["name"], task["writerID"]): task for task in fixture["tasks"]}
    checks = []
    for profile_row in report["profiles"]:
        task = tasks[(profile_row["task"], profile_row["writerID"])]
        profile_bytes = base64.b64decode(profile_row["profileCanonicalData"], validate=True)
        if _sha256(profile_bytes) != profile_row["profileSHA256"]:
            raise ValueError("Golden profile bytes changed")
        examples = {example["id"]: example for example in json.loads(profile_bytes)["examples"]}
        if len(task["lessons"]) != len(profile_row["supportLessons"]):
            raise ValueError("Golden support count changed")
        for lesson, stored in zip(task["lessons"], profile_row["supportLessons"]):
            if any(lesson[key] != stored[key] for key in ("sampleID", "exampleID", "label")):
                raise ValueError("Golden support order changed")
            sample = samples[lesson["sampleID"]]
            if sample["writerID"] != task["writerID"] or sample["session"] != 1:
                raise ValueError("Golden lesson is not a declared setup support")
            raw = tuple(InkStroke(tuple(InkPoint(point["x"], point["y"]) for point in stroke)) for stroke in sample["strokes"])
            shape = setup_shape(raw)
            packet = base64.b64decode(stored["storedCanonicalData"], validate=True)
            expected = decode_canonical_study_packet(packet)
            example = examples[lesson["exampleID"]]
            if (shape is None or not _geometry_close(shape, expected)
                    or stroke_bits(expected) != stroke_bits(numeric_strokes(example["strokes"]))
                    or _sha256(packet) != stored["storedPacketSHA256"]
                    or _sha256(rasterize(shape).pixels) != stored["storedRasterSHA256"]):
                raise ValueError("Python setup normalization differs from retained Swift geometry/pixels")
            checks.append({"sampleID": lesson["sampleID"], "profileSHA256": profile_row["profileSHA256"],
                "storedPacketSHA256": stored["storedPacketSHA256"], "storedRasterSHA256": stored["storedRasterSHA256"]})
    if len(checks) != 248:
        raise ValueError("Retained support golden coverage changed")
    return {"fixtureSHA256": FIXTURE_SHA256, "appReportSHA256": APP_REPORT_SHA256,
        "supportChecks": len(checks), "checksSHA256": _sha256(_json_bytes(checks)),
        "geometryTolerance": 1e-12, "pixelsExactlyMatched": True, "modelInferencePerformed": False,
        "queryTruthRead": False}


def fold_writers(records):
    training, writers, development, reserved = select_training_samples(records)
    ranked = tuple(sorted(writers, key=lambda writer: _sha256(("personal-support-retrieval-v1:fold:" + writer).encode())))
    folds = {"A": ranked[:16], "B": ranked[16:]}
    if (len(set(folds["A"]) | set(folds["B"])) != 32 or set(folds["A"]) & set(folds["B"])
            or set(writers) & (set(development) | set(reserved))):
        raise ValueError("Cross-fit writer roles overlap")
    return training, folds, development, reserved


def initialized_models():
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(SEED)
        original = PersonalVisualEncoder(97)
    models = {arm: copy.deepcopy(original) for arm in ARMS}
    digest = _state_digest(original.state_dict())
    return models, digest


def _train_update(model, images, targets, optimizer, generator):
    if (images.dtype != torch.uint8 or images.ndim != 4 or tuple(images.shape[1:]) != (1, RASTER_HEIGHT, RASTER_WIDTH)
            or targets.dtype != torch.long or targets.shape != (len(images),)
            or not len(images) or int(targets.min()) < 0 or int(targets.max()) >= 97):
        raise ValueError("Cross-fit training batch contract changed")
    _, logits = model(augment(images.float() / 255, generator))
    loss = F.cross_entropy(logits, targets)
    if not torch.isfinite(loss):
        raise ValueError("Nonfinite cross-fit training objective")
    optimizer.zero_grad(set_to_none=True)
    loss.backward()
    if any(value.grad is None or not torch.isfinite(value.grad).all() for value in model.parameters()):
        raise ValueError("Missing or nonfinite cross-fit gradient")
    optimizer.step()
    if any(not torch.isfinite(value).all() for value in model.state_dict().values()):
        raise ValueError("Nonfinite cross-fit encoder state")
    return float(loss.detach())


def epoch_batch_plan(generator):
    permutation = torch.randperm(FIT_ROWS, generator=generator)
    batches = tuple(permutation.split(BATCH_ROWS))
    if len(batches) != 25 or sorted(permutation.tolist()) != list(range(FIT_ROWS)):
        raise ValueError("Cross-fit epoch lost training rows")
    return permutation, batches


def train_encoder(model, arm, images, targets):
    if len(images) != FIT_ROWS or len(targets) != FIT_ROWS:
        raise ValueError("Disposable encoder must fit exactly its 16 writers")
    optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    generator = torch.Generator().manual_seed(SEED)
    history = []
    for epoch in range(EPOCHS):
        model.train()
        permutation, batches = epoch_batch_plan(generator)
        loss_total, updates = 0., 0
        start = _sha256(generator.get_state().numpy().tobytes())
        for indices in batches:
            loss_total += _train_update(model, images[indices], targets[indices], optimizer, generator) * len(indices)
            updates += 1
        if updates != 25 or sorted(permutation.tolist()) != list(range(FIT_ROWS)):
            raise ValueError("Cross-fit epoch lost training rows")
        row = {"epoch": epoch + 1, "samples": FIT_ROWS, "updates": updates,
            "crossEntropyLoss": loss_total / FIT_ROWS, "learningRate": optimizer.param_groups[0]["lr"],
            "permutationSHA256": _sha256(permutation.numpy().tobytes()),
            "generatorStartSHA256": start, "generatorEndSHA256": _sha256(generator.get_state().numpy().tobytes())}
        history.append(row)
        scheduler.step()
        print(json.dumps({"arm": arm, **row}, sort_keys=True, allow_nan=False), flush=True)
    if sum(row["updates"] for row in history) != UPDATES_PER_ENCODER:
        raise ValueError("Incomplete disposable cross-fit training")
    return history


def source_copy_reasons(raw_raster_hash, trajectory_hash, fit_rasters, fit_trajectories):
    reasons = []
    if raw_raster_hash in fit_rasters:
        reasons.append("generic-fit-raw-raster-copy")
    if trajectory_hash in fit_trajectories:
        reasons.append("generic-fit-normalized-trajectory-copy")
    return reasons


def fit(source, output):
    source = _regular_file(source, "frozen UJI source")
    root = Path(__file__).resolve().parents[3]
    if Path(output).is_relative_to(root):
        raise ValueError("Cross-fit output must be outside Git")
    code = code_identity()
    protocol = (root / PROTOCOL_PATH).read_bytes()
    goldens = verify_support_adapter()  # Must pass before any encoder is fitted.
    records = load_official_source(source)
    training, folds, development, reserved = fold_writers(records)
    vocabulary = tuple(sorted({sample.label for sample in training}))
    torch.set_num_threads(CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    models, initial = initialized_models()
    images, raster_hashes = encode_samples(training, tuple(sorted(set(sample.writer for sample in training))))
    targets = torch.tensor([vocabulary.index(sample.label) for sample in training], dtype=torch.long)
    stored_pixels, rows = [], []
    for sample, raster_hash in zip(training, raster_hashes):
        shape = setup_shape(sample.strokes)
        try:
            pixels = None if shape is None else rasterize(shape).pixels
        except FeatureEncodingError:
            pixels = None
        stored_pixels.append(pixels)
        generator = "fitA" if sample.writer in folds["B"] else "fitB"
        rows.append({"sourceID": sample.identity, "writer": sample.writer, "session": sample.session, "label": sample.label,
            "rawRasterSHA256": raster_hash, "storedRasterSHA256": None if pixels is None else _sha256(pixels),
            "trajectorySHA256": trajectory_fingerprint(sample),
            "storedTrajectorySHA256": None if pixels is None else trajectory_fingerprint(Sample(sample.writer, sample.session, sample.label, shape)),
            "storedFailure": None if pixels is not None else ("PersonalInkShape-unavailable" if shape is None else "feature-raster-unavailable"),
            "generator": generator, "genericFitCopyReasons": []})
    arrays = {"raw_features": np.zeros((6208, 128), dtype=np.float32), "raw_logits": np.zeros((6208, 97), dtype=np.float32),
        "stored_features": np.zeros((6208, 128), dtype=np.float32), "stored_logits": np.zeros((6208, 97), dtype=np.float32),
        "stored_available": np.array([pixels is not None for pixels in stored_pixels], dtype=np.bool_)}
    plan = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code,
        "seed": SEED, "epochs": EPOCHS, "batchRows": BATCH_ROWS, "updatesPerEncoder": UPDATES_PER_ENCODER,
        "shuffleAndAugmentationGenerator": "shared-per-model-torch-seed29-original-run-behavior",
        "trainingWriters": sorted(set(sample.writer for sample in training)), "folds": {key: list(value) for key, value in folds.items()},
        "developmentWriters": list(development), "reservedWriters": list(reserved), "vocabulary": list(vocabulary),
        "initialStateSHA256": initial, "supportAdapterGolden": goldens,
        "runtime": {"python": platform.python_version(), "torch": str(torch.__version__), "numpy": str(np.__version__),
            "platform": platform.platform(), "cpuThreads": torch.get_num_threads(), "deterministicAlgorithms": True},
        "roleGuards": {"training32Only": True, "crossFoldExportsOnly": True, "developmentModelInferencePerformed": False,
            "reservedRastersConstructed": False, "queryTruthRead": False, "privateInkUsed": False,
            "productionEligible": False, "appOrProfileMutated": False}}
    output = _new_output(output)
    _write_exclusive(output / "fit-plan.json", _json_bytes(plan))
    _write_exclusive(output / "protocol.md", protocol)
    (output / "weights").mkdir(mode=0o700)
    history, weights, states = {}, {}, {}
    for arm, fit_fold, heldout_fold in (("fitA", "A", "B"), ("fitB", "B", "A")):
        model = models[arm]
        if _state_digest(model.state_dict()) != initial:
            raise ValueError("Disposable generators have unequal initialization")
        fit_indices = [index for index, sample in enumerate(training) if sample.writer in folds[fit_fold]]
        export_indices = [index for index, sample in enumerate(training) if sample.writer in folds[heldout_fold]]
        if len(fit_indices) != FIT_ROWS or len(export_indices) != FIT_ROWS or set(fit_indices) & set(export_indices):
            raise ValueError("Cross-fit model row roles overlap")
        fit_rasters = {rows[index]["rawRasterSHA256"] for index in fit_indices}
        fit_trajectories = {rows[index]["trajectorySHA256"] for index in fit_indices}
        for index in export_indices:
            rows[index]["genericFitCopyReasons"] = source_copy_reasons(rows[index]["rawRasterSHA256"], rows[index]["trajectorySHA256"], fit_rasters, fit_trajectories)
        history[arm] = train_encoder(model, arm, images[fit_indices], targets[fit_indices])
        states[arm] = _state_digest(model.state_dict())
        checkpoint = {"version": VERSION, "arm": arm, "finalEpoch": EPOCHS, "sourceSHA256": SOURCE_SHA256,
            "protocolSHA256": PROTOCOL_SHA256, "initialStateSHA256": initial, "fitWriters": list(folds[fit_fold]),
            "exportWriters": list(folds[heldout_fold]), "vocabulary": list(vocabulary), "state_dict": model.state_dict()}
        buffer = io.BytesIO()
        torch.save(checkpoint, buffer)
        payload = buffer.getvalue()
        _write_exclusive(output / "weights" / f"{arm}.pt", payload)
        weights[arm] = _sha256(payload)
        features, logits = infer(model, images[export_indices])
        arrays["raw_features"][export_indices], arrays["raw_logits"][export_indices] = features, logits
        eligible = [index for index in export_indices if stored_pixels[index] is not None]
        if eligible:
            stored_images = torch.from_numpy(np.frombuffer(b"".join(stored_pixels[index] for index in eligible), dtype=np.uint8).copy()
                .reshape(-1, 1, RASTER_HEIGHT, RASTER_WIDTH))
            features, logits = infer(model, stored_images)
            arrays["stored_features"][eligible], arrays["stored_logits"][eligible] = features, logits
    for left, right in zip(history["fitA"], history["fitB"]):
        if any(left[key] != right[key] for key in ("epoch", "samples", "updates", "learningRate", "permutationSHA256", "generatorStartSHA256", "generatorEndSHA256")):
            raise ValueError("Cross-fit generators did not use matched budgets/draws")
    metadata = {"version": VERSION, "vocabulary": list(vocabulary), "rows": rows}
    metadata_bytes = _json_bytes(metadata)
    buffer = io.BytesIO()
    np.savez(buffer, **arrays)
    features_bytes = buffer.getvalue()
    if (_sha256(source.read_bytes()) != SOURCE_SHA256 or code_identity() != code
            or (root / PROTOCOL_PATH).read_bytes() != protocol or verify_support_adapter() != goldens):
        raise ValueError("Cross-fit source/code/protocol/support goldens changed during fitting")
    _write_exclusive(output / "metadata.json", metadata_bytes)
    _write_exclusive(output / "features.npz", features_bytes)
    unavailable = [row for row in rows if row["storedFailure"] is not None]
    receipt = {**plan, "fitPlanSHA256": _sha256(_json_bytes(plan)), "trainingHistory": history,
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in ARMS}, "weightsSHA256": weights, "finalStateSHA256": states,
        "metadataSHA256": _sha256(metadata_bytes), "featuresSHA256": _sha256(features_bytes), "exportRows": len(rows),
        "storedUnavailable": len(unavailable), "storedUnavailableByLabel": {label: sum(row["label"] == label for row in unavailable) for label in vocabulary},
        "genericFitCopyRows": sum(bool(row["genericFitCopyReasons"]) for row in rows), "selection": "final-epoch-only"}
    _write_exclusive(output / "fit-receipt.json", _json_bytes(receipt))
    return receipt


def load_crossfit_bundle(output):
    output = Path(output)
    receipt_bytes = _regular_file(output / "fit-receipt.json", "cross-fit receipt").read_bytes()
    receipt = json.loads(receipt_bytes)
    plan_bytes = _regular_file(output / "fit-plan.json", "cross-fit plan").read_bytes()
    plan = json.loads(plan_bytes)
    metadata_bytes = _regular_file(output / "metadata.json", "cross-fit metadata").read_bytes()
    features_bytes = _regular_file(output / "features.npz", "cross-fit features").read_bytes()
    if (receipt_bytes != _json_bytes(receipt) or plan_bytes != _json_bytes(plan)
            or receipt.get("version") != VERSION or receipt.get("sourceSHA256") != SOURCE_SHA256
            or receipt.get("codeSHA256") != code_identity() or receipt.get("protocolSHA256") != PROTOCOL_SHA256
            or _sha256(plan_bytes) != receipt.get("fitPlanSHA256") or any(receipt.get(key) != value for key, value in plan.items())
            or _sha256(metadata_bytes) != receipt.get("metadataSHA256") or _sha256(features_bytes) != receipt.get("featuresSHA256")
            or _sha256(_regular_file(output / "protocol.md", "cross-fit protocol").read_bytes()) != PROTOCOL_SHA256):
        raise ValueError("Cross-fit evidence binding changed")
    folds, writers = receipt["folds"], receipt["trainingWriters"]
    ranked = sorted(writers, key=lambda writer: _sha256(("personal-support-retrieval-v1:fold:" + writer).encode()))
    if (len(writers) != len(set(writers)) != 32 or len(writers) != 32
            or any(not writer.startswith("trn_") for writer in writers)
            or folds != {"A": ranked[:16], "B": ranked[16:]}
            or set(writers) & (set(receipt["developmentWriters"]) | set(receipt["reservedWriters"]))
            or receipt["epochs"] != EPOCHS or receipt["updatesPerEncoder"] != UPDATES_PER_ENCODER
            or receipt["roleGuards"] != {"training32Only": True, "crossFoldExportsOnly": True,
                "developmentModelInferencePerformed": False, "reservedRastersConstructed": False,
                "queryTruthRead": False, "privateInkUsed": False, "productionEligible": False, "appOrProfileMutated": False}):
        raise ValueError("Cross-fit fixed writer roles changed")
    models, expected_initial = initialized_models()
    if receipt["initialStateSHA256"] != expected_initial:
        raise ValueError("Cross-fit seed29 initialization changed")
    for arm in ARMS:
        if receipt["weightFiles"][arm] != f"weights/{arm}.pt":
            raise ValueError("Cross-fit checkpoint path changed")
        payload = _regular_file(output / receipt["weightFiles"][arm], "cross-fit checkpoint").read_bytes()
        if _sha256(payload) != receipt["weightsSHA256"][arm]:
            raise ValueError("Cross-fit checkpoint bytes changed")
        checkpoint = torch.load(io.BytesIO(payload), weights_only=True, map_location="cpu")
        fit_fold, export_fold = ("A", "B") if arm == "fitA" else ("B", "A")
        expected = {"version": VERSION, "arm": arm, "finalEpoch": EPOCHS, "sourceSHA256": SOURCE_SHA256,
            "protocolSHA256": PROTOCOL_SHA256, "initialStateSHA256": expected_initial,
            "fitWriters": folds[fit_fold], "exportWriters": folds[export_fold], "vocabulary": receipt["vocabulary"]}
        if (set(checkpoint) != set(expected) | {"state_dict"} or any(checkpoint[key] != value for key, value in expected.items())
                or set(checkpoint["fitWriters"]) & set(checkpoint["exportWriters"])):
            raise ValueError("Cross-fit checkpoint writer/metadata roles changed")
        schema, state = models[arm].state_dict(), checkpoint["state_dict"]
        if (set(state) != set(schema) or any(not isinstance(state[key], torch.Tensor)
                or state[key].shape != schema[key].shape or state[key].dtype != schema[key].dtype
                or not torch.isfinite(state[key]).all() for key in schema)
                or _state_digest(state) != receipt["finalStateSHA256"][arm]):
            raise ValueError("Cross-fit checkpoint metadata/state changed")
    metadata = json.loads(metadata_bytes)
    rows = metadata["rows"]
    vocabulary = receipt["vocabulary"]
    if (metadata["version"] != VERSION or metadata["vocabulary"] != vocabulary or len(rows) != 6208
            or len(vocabulary) != 97 or vocabulary != sorted(set(vocabulary))
            or [row["sourceID"] for row in rows] != sorted(row["sourceID"] for row in rows)
            or {(row["writer"], row["session"], row["label"]) for row in rows}
                != {(writer, session, label) for writer in receipt["trainingWriters"] for session in (1, 2) for label in vocabulary}
            or any(row["generator"] != ("fitA" if row["writer"] in receipt["folds"]["B"] else "fitB") for row in rows)):
        raise ValueError("Cross-fit source roles/order changed")
    with np.load(io.BytesIO(features_bytes), allow_pickle=False) as bundle:
        arrays = {name: bundle[name].copy() for name in bundle.files}
    expected_shapes = {"raw_features": (6208, 128), "raw_logits": (6208, 97),
        "stored_features": (6208, 128), "stored_logits": (6208, 97), "stored_available": (6208,)}
    if set(arrays) != set(expected_shapes) or any(arrays[name].shape != shape for name, shape in expected_shapes.items()):
        raise ValueError("Cross-fit feature shapes changed")
    available = arrays["stored_available"]
    if (available.dtype != np.bool_ or available.tolist() != [row["storedFailure"] is None for row in rows]
            or any(value.dtype != np.float32 or not np.isfinite(value).all() for name, value in arrays.items() if name != "stored_available")
            or not np.allclose(np.linalg.norm(arrays["raw_features"], axis=1), 1, rtol=1e-4, atol=1e-5)
            or not np.allclose(np.linalg.norm(arrays["stored_features"][available], axis=1), 1, rtol=1e-4, atol=1e-5)
            or arrays["stored_features"][~available].any() or arrays["stored_logits"][~available].any()):
        raise ValueError("Cross-fit numeric/availability contract changed")
    return arrays, rows, receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    result = fit(arguments.source, arguments.output)
    print(json.dumps({"version": result["version"], "exportRows": result["exportRows"],
        "storedUnavailable": result["storedUnavailable"], "featuresSHA256": result["featuresSHA256"]}, sort_keys=True), flush=True)
