"""Frozen public-development evaluation of matched CE/contrastive encoders.

Prediction never opens query truth or the copy ledger. It consumes only opaque
query IDs/geometry, previously stored app support, and training-only final
embedding bundles. Scoring is a separate operation after prediction bytes exist.
No local/RBF learner, private profile, reserved feature construction or promotion.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import platform
import struct
from pathlib import Path

import numpy as np
import torch

from ..contracts import strict_json_loads
from ..features import FeatureEncodingError, InkBounds, InkPoint, InkStroke, rasterize
from ..study_import import decode_canonical_study_packet
from .personal_anchors import AnchorBank, fit_anchored
from .personal_residual import normalized_scores, validate_features, validate_scores
from .personal_visual_encoder import infer
from .uji_personal import SOURCE_SHA256

VERSION = "personal-cross-writer-evaluation-predictions-v1"
FIXTURE_SHA256 = "d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d"
APP_REPORT_SHA256 = "52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618"
PROTOCOL_SHA256 = "ca6c2eca8b7609eaa18ef97d48553546fbd685c1dfcb2b28621e4ae2293c073c"
ARMS = ("crossEntropyControl", "crossWriterContrastive")
WRITERS = ("trn_UJI_W04", "trn_UJI_W06", "trn_UJI_W08", "trn_UJI_W11",
           "trn_UPV_W35", "trn_UPV_W43", "trn_UPV_W47", "trn_UPV_W56")
CORE = tuple("ABCDEFG") + ("b", "-", "7")
CATALOG = CORE + ("m", "o", "6", "9", "2", "4", "5", "1", "3", "(", ")")
TASKS = {"core10": CORE, "catalog21": CATALOG}
CODE_PATHS = (
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_evaluation.py",
    "recognition_ml/tests/test_personal_cross_writer_evaluation.py",
    "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_contrastive.py",
    "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
    "recognition_ml/ichart_recognition_ml/research/personal_anchors.py",
    "recognition_ml/ichart_recognition_ml/research/personal_residual.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/study_import.py",
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "docs/personal-cross-writer-contrastive-protocol-2026-10-01.md",
)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path, limit=256 * 1024 * 1024):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file()
            and not path.is_symlink() and path.stat().st_size <= limit, "Unbounded/aliased input file")
    return path.read_bytes()


def parsed(data):
    return strict_json_loads(data.decode("utf-8"), "cross-writer-evaluation")


def blob(value):
    require(isinstance(value, str), "Canonical base64 required")
    data = base64.b64decode(value, validate=True)
    require(base64.b64encode(data).decode() == value, "Noncanonical base64")
    return data


def digest_string(value):
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: sha(read(root / name, 4 * 1024 * 1024)) for name in CODE_PATHS}


def runtime_identity():
    return {"python": platform.python_version(), "numpy": np.__version__, "torch": str(torch.__version__),
            "platform": platform.platform(), "cpuThreads": torch.get_num_threads(),
            "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled()}


def configure():
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)


def tree_identity(root):
    root = Path(root)
    require(root.is_absolute() and root.resolve() == root and root.is_dir(), "Invalid fit directory")
    files = list(root.rglob("*"))
    require(not any(p.is_symlink() for p in files), "Fit directory symlink")
    return {p.relative_to(root).as_posix(): sha(read(p)) for p in sorted(files) if p.is_file()}


def exclusive(path, data, inputs=()):
    path = Path(path)
    root = Path(__file__).resolve().parents[3]
    require(path.is_absolute() and path.parent.resolve() == path.parent and path.parent.is_dir()
            and not path.exists() and not path.is_symlink() and root not in path.parents
            and all(path != Path(p) and Path(p) not in path.parents for p in inputs), "Output must be exclusive/nonalias/outside source")
    with path.open("xb") as stream:
        stream.write(data)


def numeric_strokes(values):
    """Decode stored Swift numeric strokes without resampling/normalization."""
    def number(value):
        require(type(value) in (int, float) and math.isfinite(value), "Nonfinite stored geometry")
        return float(value)
    strokes = []
    require(isinstance(values, list) and len(values) <= 256, "Stored stroke budget")
    total = 0
    for value in values:
        require(set(value) <= {"points", "bounds", "creationTimeOffset"} and {"points", "bounds"} <= set(value), "Stored stroke fields")
        bounds = value["bounds"]
        require(set(bounds) == {"minX", "minY", "maxX", "maxY"}, "Stored bounds fields")
        points = []
        require(isinstance(value["points"], list) and len(value["points"]) <= 8192, "Stored point budget")
        total += len(value["points"])
        require(total <= 32768, "Stored total point budget")
        for point in value["points"]:
            require({"x", "y"} <= set(point) <= {"x", "y", "timeOffset"}, "Stored point fields")
            timing = point.get("timeOffset")
            points.append(InkPoint(number(point["x"]), number(point["y"]), None if timing is None else number(timing)))
        creation = value.get("creationTimeOffset")
        strokes.append(InkStroke(points, InkBounds(*(number(bounds[k]) for k in ("minX", "minY", "maxX", "maxY"))),
                                None if creation is None else number(creation)))
    return tuple(strokes)


def stroke_bits(strokes):
    def bits(value):
        return None if value is None else struct.pack("<d", value).hex()
    return [{"points": [[bits(p.x), bits(p.y), bits(p.time_offset)] for p in s.points],
             "bounds": [bits(getattr(s.bounds, k)) for k in ("min_x", "min_y", "max_x", "max_y")],
             "creation": bits(s.creation_time_offset)} for s in strokes]


def project_stored_support(task, row):
    """Bind exact existing profile, packet and Swift pixels; never normalize."""
    data = blob(row["profileCanonicalData"])
    require(sha(data) == row["profileSHA256"], "Stored profile digest mismatch")
    profile = parsed(data)
    require(profile["version"] == 1 and profile["isEnabled"] is True
            and profile["revision"] == task["profileRevision"] and profile["generation"] == task["profileGeneration"], "Stored profile metadata mismatch")
    require(len(profile["examples"]) == len(task["lessons"]) == len(row["supportLessons"]), "Stored support count mismatch")
    examples = {example["id"]: example for example in profile["examples"]}
    require(len(examples) == len(profile["examples"]), "Duplicate stored example")
    result = []
    for planned, stored in zip(task["lessons"], row["supportLessons"]):
        require(all(planned[k] == stored[k] for k in ("sampleID", "label", "exampleID")), "Stored support order/identity mismatch")
        example = examples[stored["exampleID"]]
        require(example["label"] == stored["label"] and example["kind"] == "glyph" and example["source"] == "setup", "Stored support label/source mismatch")
        packet = blob(stored["storedCanonicalData"])
        require(sha(packet) == stored["storedPacketSHA256"], "Stored packet digest mismatch")
        strokes = decode_canonical_study_packet(packet)
        require(stroke_bits(strokes) == stroke_bits(numeric_strokes(example["strokes"])), "Stored packet/profile geometry mismatch")
        pixels = rasterize(strokes).pixels
        require(sha(pixels) == stored["storedRasterSHA256"], "Python/Swift stored-support raster mismatch")
        result.append({**stored, "pixels": pixels, "profileSHA256": row["profileSHA256"]})
    return result


def load_projection(fixture_path, app_report_path):
    fixture_data, app_data = read(fixture_path, 32 * 1024 * 1024), read(app_report_path)
    require(sha(fixture_data) == FIXTURE_SHA256 and sha(app_data) == APP_REPORT_SHA256, "Wrong retained fixture/profile artifact")
    fixture, app = parsed(fixture_data), parsed(app_data)
    require(fixture["version"] == "public-app-local-transfer-fixture-v1" and fixture["sourceSHA256"] == SOURCE_SHA256
            and fixture["writerIDs"] == list(WRITERS) and app["fixtureSHA256"] == FIXTURE_SHA256
            and app["sourceSHA256"] == SOURCE_SHA256 and app["intendedQueryLabelsSupplied"] is False
            and app["reservedWriterInferencePerformed"] is False, "Retained public binding mismatch")
    require(len(fixture["vocabulary97"]) == len(set(fixture["vocabulary97"])) == 97
            and fixture["vocabulary97"] == sorted(fixture["vocabulary97"]), "Wrong full vocabulary")
    samples = {s["id"]: s for s in fixture["samples"]}
    raw = {s["id"]: s for s in app["rawSamples"]}
    profiles = {(p["task"], p["writerID"]): p for p in app["profiles"]}
    require(len(samples) == len(fixture["samples"]) == len(raw) == len(app["rawSamples"]) == 1552 and set(samples) == set(raw), "Raw source identity mismatch")
    keys = {(task, writer) for task in TASKS for writer in WRITERS}
    require(len(fixture["tasks"]) == len(profiles) == len(app["profiles"]) == 16
            and {(t["name"], t["writerID"]) for t in fixture["tasks"]} == set(profiles) == keys, "Wrong fixed task cohort")
    pixels = {}
    for sid, sample in samples.items():
        require(set(sample) == {"id", "writerID", "session", "strokes"} and sample["writerID"] in WRITERS
                and type(sample["session"]) is int and sample["session"] in (1, 2), "Query DTO contains answers or wrong roles")
        for stroke in sample["strokes"]:
            require(all(set(p) == {"x", "y"} for p in stroke), "Query point fields")
        source = blob(raw[sid]["sourceCanonicalData"])
        require(sha(source) == raw[sid]["sourcePacketSHA256"] and all(raw[sid][k] == sample[k] for k in ("writerID", "session")), "Raw source commitment mismatch")
        strokes = decode_canonical_study_packet(source)
        expected = tuple(InkStroke([InkPoint(p["x"], p["y"]) for p in st]) for st in sample["strokes"])
        require(stroke_bits(strokes) == stroke_bits(expected), "Query source geometry changed")
        try:
            pixels[sid] = rasterize(strokes).pixels
            require(sha(pixels[sid]) == raw[sid]["rawRasterSHA256"], "Python/Swift raw raster mismatch")
        except FeatureEncodingError:
            require(sample["session"] == 2 and raw[sid]["rawRasterSHA256"] is None, "Support/source raster failure")
            pixels[sid] = None
    supports = {}
    for task in fixture["tasks"]:
        key = (task["name"], task["writerID"])
        require(tuple(l["label"] for l in task["lessons"]) == TASKS[key[0]]
                and len(task["queryIDs"]) == len(set(task["queryIDs"])) == 97
                and set(task["queryIDs"]) == {sid for sid, s in samples.items() if s["writerID"] == key[1] and s["session"] == 2}, "Fixed lesson/query schedule changed")
        require(all(samples[l["sampleID"]]["writerID"] == key[1] and samples[l["sampleID"]]["session"] == 1 for l in task["lessons"]), "Support role mismatch")
        supports[key] = project_stored_support(task, profiles[key])
    return fixture, app, raw, pixels, supports


def validate_fit(receipt, vocabulary):
    require(tuple(receipt["arms"]) == ARMS and receipt["sourceSHA256"] == SOURCE_SHA256
            and tuple(receipt["developmentWriters"]) == WRITERS and len(receipt["trainingWriters"]) == 32
            and len(set(receipt["trainingWriters"])) == 32 and not set(receipt["trainingWriters"]) & set(WRITERS)
            and all(w.startswith("trn_") for w in receipt["trainingWriters"])
            and len(receipt["reservedWriters"]) == 20 and not set(receipt["reservedWriters"]) & (set(WRITERS) | set(receipt["trainingWriters"]))
            and receipt["vocabulary"] == vocabulary and receipt["protocolEnvelope"].get("markdownProtocolSHA256") == PROTOCOL_SHA256,
            "Fit source/split/protocol/vocabulary binding mismatch")


def query_schedule(fixture):
    return [{"task": t["name"], "writerID": t["writerID"], "queryIDs": t["queryIDs"]} for t in fixture["tasks"]]


def prepare(fit, fixture, app_report, protocol, output):
    """Create a derivative commitment; no model inference or truth reads."""
    from .personal_cross_writer_contrastive import load_fitted_models
    configure()
    projection, app, _, _, _ = load_projection(fixture, app_report)
    protocol_data = read(protocol, 256 * 1024)
    require(sha(protocol_data) == PROTOCOL_SHA256, "Wrong fixed Markdown protocol")
    _, receipt = load_fitted_models(fit)
    validate_fit(receipt, projection["vocabulary97"])
    value = {"version": "personal-cross-writer-evaluation-commitment-v1", "sourceSHA256": SOURCE_SHA256,
             "fixtureSHA256": FIXTURE_SHA256, "appReportSHA256": APP_REPORT_SHA256, "protocolSHA256": PROTOCOL_SHA256,
             "fitReceiptSHA256": sha(read(Path(fit) / "fit-receipt.json")), "fitFilesSHA256": tree_identity(fit),
             "queryTruthSHA256": app["queryTruthSHA256"], "sourceCopyLedgerSHA256": app["sourceCopyLedgerSHA256"],
             "queryScheduleSHA256": sha(canonical(query_schedule(projection))),
             "codeSHA256": code_identity(), "runtime": runtime_identity(), "inferencePerformed": False}
    exclusive(output, canonical(value), (fit, fixture, app_report, protocol))
    return value


def rank(vocabulary, scores):
    require(len(scores) == len(vocabulary) and np.isfinite(scores).all(), "Incomplete/nonfinite ranking")
    return sorted(({"label": label, "score": float(value)} for label, value in zip(vocabulary, scores)), key=lambda r: (-r["score"], r["label"]))


def image_tensor(pixels):
    require(pixels and all(len(p) == 96 * 256 for p in pixels), "Invalid image batch")
    return torch.from_numpy(np.frombuffer(b"".join(pixels), dtype=np.uint8).copy().reshape(-1, 1, 96, 256))


def predict(fit, fixture, app_report, protocol, commitment_path, output):
    from .personal_cross_writer_contrastive import load_fitted_models, load_training_feature_bundle
    configure()
    committed_bytes = read(commitment_path, 1024 * 1024)
    committed = parsed(committed_bytes)
    fixture_value, app, raw, pixels, supports = load_projection(fixture, app_report)
    require(committed["version"] == "personal-cross-writer-evaluation-commitment-v1" and committed["inferencePerformed"] is False
            and committed["sourceSHA256"] == SOURCE_SHA256 and committed["fixtureSHA256"] == FIXTURE_SHA256
            and committed["appReportSHA256"] == APP_REPORT_SHA256 and committed["protocolSHA256"] == sha(read(protocol)) == PROTOCOL_SHA256
            and committed["fitReceiptSHA256"] == sha(read(Path(fit) / "fit-receipt.json"))
            and committed["fitFilesSHA256"] == tree_identity(fit) and committed["codeSHA256"] == code_identity()
            and committed["runtime"] == runtime_identity() and committed["queryTruthSHA256"] == app["queryTruthSHA256"]
            and committed["sourceCopyLedgerSHA256"] == app["sourceCopyLedgerSHA256"]
            and committed["queryScheduleSHA256"] == sha(canonical(query_schedule(fixture_value))), "Derivative evaluation commitment mismatch")
    models, receipt = load_fitted_models(fit)
    vocabulary = tuple(fixture_value["vocabulary97"])
    validate_fit(receipt, list(vocabulary))
    query_ids = sorted({sid for task in fixture_value["tasks"] for sid in task["queryIDs"]})
    require(len(query_ids) == 776, "Changed query denominator")
    valid_ids = [sid for sid in query_ids if pixels[sid] is not None]
    rows, support_artifacts, banks = [], [], {}
    for arm in ARMS:
        bundle = load_training_feature_bundle(fit, arm, receipt)
        training = np.asarray(bundle["features"], dtype=np.float64)
        validate_features(training)
        require(training.shape == (6208, 128) and set(bundle["writers"].tolist()) == set(receipt["trainingWriters"])
                and set(bundle["labels"].tolist()) == set(vocabulary), "Wrong training-only anchor source")
        bank = AnchorBank.from_training(training, tuple(bundle["labels"].tolist()), vocabulary)
        bank_value = {"vocabulary": list(vocabulary), "features": bank.features.tolist(), "trainingFeatureSHA256": receipt["trainingFeaturesSHA256"][arm],
                      "trainingFeatureOrderSHA256": receipt["trainingFeatureOrderSHA256"], "weightsSHA256": receipt["weightsSHA256"][arm],
                      "trainingWriters": receipt["trainingWriters"], "trainingSamples": 6208, "reservedFeatureCount": 0}
        banks[arm] = {**bank_value, "sha256": sha(canonical(bank_value))}
        heads = {}
        # Exact app-stored support is encoded and every fixed fit completed
        # before this arm's first query inference. Nothing reads query labels.
        for task in fixture_value["tasks"]:
            key = (task["name"], task["writerID"])
            source_support = supports[key]
            features, logits = infer(models[arm], image_tensor([s["pixels"] for s in source_support]))
            features, logits = np.asarray(features, dtype=np.float64), np.asarray(logits, dtype=np.float64)
            validate_features(features)
            require(features.shape == (len(source_support), 128) and logits.shape == (len(source_support), 97), "Support encoder contract")
            base = normalized_scores(logits)
            labels = tuple(s["label"] for s in source_support)
            heads[key] = fit_anchored(features, base, labels, vocabulary, bank)
            lessons = [{k: v for k, v in stored.items() if k != "pixels"} | {"embedding": features[i].tolist(), "genericLogits": logits[i].tolist(), "baseScores": base[i].tolist()}
                       for i, stored in enumerate(source_support)]
            value = {"arm": arm, "task": key[0], "writerID": key[1], "lessons": lessons,
                     "anchorSHA256": banks[arm]["sha256"], "regularization": 0.1, "weights": heads[key].weights.tolist()}
            support_artifacts.append({**value, "sha256": sha(canonical(value))})
        inferred = {}
        if valid_ids:
            features, logits = infer(models[arm], image_tensor([pixels[sid] for sid in valid_ids]))
            features, logits = np.asarray(features, dtype=np.float64), np.asarray(logits, dtype=np.float64)
            validate_features(features)
            require(features.shape == (len(valid_ids), 128) and logits.shape == (len(valid_ids), 97), "Query encoder contract")
            base = normalized_scores(logits)
            inferred = {sid: (features[i], logits[i], base[i]) for i, sid in enumerate(valid_ids)}
        for task in fixture_value["tasks"]:
            key = (task["name"], task["writerID"])
            for sid in task["queryIDs"]:
                common = {"arm": arm, "task": key[0], "writerID": key[1], "sampleID": sid,
                          "sourceCanonicalData": raw[sid]["sourceCanonicalData"], "sourcePacketSHA256": raw[sid]["sourcePacketSHA256"],
                          "rawRasterSHA256": raw[sid]["rawRasterSHA256"]}
                if sid not in inferred:
                    rows.append({**common, "outcome": "invalid-ink", "failure": "query-raster-no-read", "embedding": None,
                                 "genericLogits": None, "baseScores": None, "genericRanks": [], "personalRanks": []})
                    continue
                feature, logit, base = inferred[sid]
                personal = heads[key].rank(feature, base)
                rows.append({**common, "outcome": "read", "failure": None, "embedding": feature.tolist(), "genericLogits": logit.tolist(),
                             "baseScores": base.tolist(), "genericRanks": rank(vocabulary, base), "personalRanks": personal})
    packet = {"version": VERSION, "artifactKind": "engineering-only-reused-public-development-v1", "productionEligible": False,
              "naturalChordAccuracyMeasured": False, "newWriterValidationPerformed": False, "liveRecognitionChanged": False,
              "privateProfileChanged": False, "reservedFeatureCount": 0, "reservedInferenceCount": 0,
              "queryTruthOpened": False, "regularization": 0.1, "learner": "personal-untaught-anchor-v1",
              "commitmentCanonicalData": base64.b64encode(committed_bytes).decode(), "commitmentSHA256": sha(committed_bytes),
              "fitReceiptCanonicalData": base64.b64encode(read(Path(fit) / "fit-receipt.json")).decode(),
              "bindings": committed, "querySchedule": query_schedule(fixture_value), "vocabulary": list(vocabulary),
              "anchorBanks": banks, "supports": support_artifacts, "rows": rows}
    validate_prediction_packet(packet)
    require(tree_identity(fit) == committed["fitFilesSHA256"] and code_identity() == committed["codeSHA256"]
            and runtime_identity() == committed["runtime"] and read(commitment_path) == committed_bytes
            and sha(read(fixture)) == FIXTURE_SHA256 and sha(read(app_report)) == APP_REPORT_SHA256
            and sha(read(protocol)) == PROTOCOL_SHA256, "Evaluation inputs changed during prediction")
    data = canonical(packet)
    exclusive(output, data, (fit, fixture, app_report, protocol, commitment_path))
    return {"predictionSHA256": sha(data), "rows": len(rows), "queryTruthOpened": False}


def validate_prediction_packet(packet):
    require(packet["version"] == VERSION and packet["queryTruthOpened"] is False
            and packet["productionEligible"] is False and packet["reservedFeatureCount"] == packet["reservedInferenceCount"] == 0
            and packet["learner"] == "personal-untaught-anchor-v1" and packet["regularization"] == 0.1, "Wrong prediction contract")
    binding = packet["bindings"]
    require(binding["fixtureSHA256"] == FIXTURE_SHA256 and binding["appReportSHA256"] == APP_REPORT_SHA256
            and binding["sourceSHA256"] == SOURCE_SHA256 and binding["protocolSHA256"] == PROTOCOL_SHA256
            and sha(blob(packet["commitmentCanonicalData"])) == packet["commitmentSHA256"]
            and parsed(blob(packet["commitmentCanonicalData"])) == binding, "Prediction binding mismatch")
    vocabulary = packet["vocabulary"]
    require(len(vocabulary) == len(set(vocabulary)) == 97 and vocabulary == sorted(vocabulary), "Prediction full vocabulary mismatch")
    receipt_data = blob(packet["fitReceiptCanonicalData"])
    require(sha(receipt_data) == binding["fitReceiptSHA256"], "Prediction fit receipt binding mismatch")
    receipt = parsed(receipt_data); validate_fit(receipt, vocabulary)
    schedule = packet["querySchedule"]
    require(sha(canonical(schedule)) == binding["queryScheduleSHA256"]
            and len(schedule) == 16 and {(s["task"], s["writerID"]) for s in schedule} == {(t, w) for t in TASKS for w in WRITERS}
            and all(len(s["queryIDs"]) == len(set(s["queryIDs"])) == 97 for s in schedule), "Frozen query schedule mismatch")
    expected_rows = {(arm, s["task"], s["writerID"], sid) for arm in ARMS for s in schedule for sid in s["queryIDs"]}
    heads = {}
    require(set(packet["anchorBanks"]) == set(ARMS) and len(packet["supports"]) == 32, "Missing model anchors/support fits")
    for arm in ARMS:
        anchor = packet["anchorBanks"][arm]
        require(anchor["sha256"] == sha(canonical({k: v for k, v in anchor.items() if k != "sha256"}))
                and anchor["vocabulary"] == vocabulary and anchor["trainingSamples"] == 6208 and anchor["reservedFeatureCount"] == 0
                and anchor["trainingWriters"] == receipt["trainingWriters"]
                and anchor["weightsSHA256"] == receipt["weightsSHA256"][arm] == binding["fitFilesSHA256"][receipt["weightFiles"][arm]]
                and anchor["trainingFeatureSHA256"] == receipt["trainingFeaturesSHA256"][arm] == binding["fitFilesSHA256"][receipt["trainingFeatureFiles"][arm]]
                and anchor["trainingFeatureOrderSHA256"] == receipt["trainingFeatureOrderSHA256"], "Anchor/model commitments disagree")
        bank_features = np.asarray(anchor["features"], dtype=np.float64)
        validate_features(bank_features)
        require(bank_features.shape == (97, 128), "Incomplete public anchor features")
        bank = AnchorBank(tuple(vocabulary), bank_features)
        for support in [s for s in packet["supports"] if s["arm"] == arm]:
            key = (arm, support["task"], support["writerID"])
            require(key not in heads and support["task"] in TASKS and support["writerID"] in WRITERS
                    and support["sha256"] == sha(canonical({k: v for k, v in support.items() if k != "sha256"}))
                    and support["anchorSHA256"] == anchor["sha256"] and support["regularization"] == 0.1
                    and tuple(s["label"] for s in support["lessons"]) == TASKS[support["task"]], "Support fit commitment mismatch")
            x = np.asarray([s["embedding"] for s in support["lessons"]], dtype=np.float64)
            base = np.asarray([s["baseScores"] for s in support["lessons"]], dtype=np.float64)
            logits = np.asarray([s["genericLogits"] for s in support["lessons"]], dtype=np.float64)
            validate_features(x); validate_scores(base, len(x), 97)
            require(x.shape == (len(support["lessons"]), 128) and np.array_equal(normalized_scores(logits), base), "Support numeric binding mismatch")
            head = fit_anchored(x, base, tuple(s["label"] for s in support["lessons"]), tuple(vocabulary), bank)
            require(np.array_equal(head.weights, np.asarray(support["weights"])), "Anchored fit numerical recomputation mismatch")
            for stored in support["lessons"]:
                packet_data = blob(stored["storedCanonicalData"])
                require(sha(packet_data) == stored["storedPacketSHA256"]
                        and sha(rasterize(decode_canonical_study_packet(packet_data)).pixels) == stored["storedRasterSHA256"], "Support geometry/raster commitment mismatch")
            heads[key] = head
    require(set(heads) == {(a, t, w) for a in ARMS for t in TASKS for w in WRITERS}, "Incomplete paired support fits")
    rows = packet["rows"]
    keys = {(r["arm"], r["task"], r["sampleID"]) for r in rows}
    require(len(rows) == len(keys) == 3104 and set(r["arm"] for r in rows) == set(ARMS)
            and set(r["task"] for r in rows) == set(TASKS) and set(r["writerID"] for r in rows) == set(WRITERS), "Prediction denominator mismatch")
    require({(r["arm"], r["task"], r["writerID"], r["sampleID"]) for r in rows} == expected_rows, "Rows differ from frozen schedule")
    shared = {}
    for row in rows:
        require(row["arm"] in ARMS and row["task"] in TASKS and row["writerID"] in WRITERS and digest_string(row["sampleID"]), "Prediction identity mismatch")
        if row["outcome"] == "invalid-ink":
            require(row["embedding"] is None and row["genericLogits"] is None and row["baseScores"] is None
                    and row["genericRanks"] == row["personalRanks"] == [] and isinstance(row["failure"], str), "Malformed retained invalid row")
        else:
            require(row["outcome"] == "read" and row["failure"] is None, "Unsupported outcome")
            feature, base, logits = np.asarray(row["embedding"]), np.asarray(row["baseScores"]), np.asarray(row["genericLogits"])
            validate_features(feature[None, :]); validate_scores(base[None, :], 1, 97)
            require(feature.shape == (128,) and logits.shape == (97,) and np.isfinite(logits).all()
                    and np.array_equal(normalized_scores(logits), base) and row["genericRanks"] == rank(vocabulary, base), "Prediction numeric binding mismatch")
            for ranks in (row["genericRanks"], row["personalRanks"]):
                require(len(ranks) == 97 and set(r["label"] for r in ranks) == set(vocabulary)
                        and all(type(r["score"]) in (int, float) and math.isfinite(r["score"]) for r in ranks)
                        and ranks == sorted(ranks, key=lambda r: (-r["score"], r["label"])), "Malformed complete ranking")
            require(row["personalRanks"] == heads[(row["arm"], row["task"], row["writerID"])].rank(feature, base), "Personal rank numerical recomputation mismatch")
        key = (row["arm"], row["sampleID"])
        evidence = canonical({k: row[k] for k in ("writerID", "outcome", "embedding", "genericLogits", "baseScores", "genericRanks")})
        require(key not in shared or shared[key] == evidence, "Shared inference changed across tasks")
        shared[key] = evidence
    for arm in ARMS:
        for task in TASKS:
            group = [r for r in rows if r["arm"] == arm and r["task"] == task]
            require(len(group) == 776 and all(sum(r["writerID"] == w for r in group) == 97 for w in WRITERS), "Per-writer denominator changed")


def paired_summary(rows, candidate, reference):
    gains = [r["sampleID"] for r in rows if r["correct"][candidate] and not r["correct"][reference]]
    harms = [r["sampleID"] for r in rows if not r["correct"][candidate] and r["correct"][reference]]
    return {"denominator": len(rows), "candidateCorrect": sum(r["correct"][candidate] for r in rows),
            "referenceCorrect": sum(r["correct"][reference] for r in rows), "gains": len(gains), "harms": len(harms),
            "net": len(gains) - len(harms), "bothCorrect": sum(r["correct"][candidate] and r["correct"][reference] for r in rows),
            "neitherCorrect": sum(not r["correct"][candidate] and not r["correct"][reference] for r in rows),
            "gainIDs": gains, "harmIDs": harms, "discordantIDs": [r["sampleID"] for r in rows if r["predictions"][candidate] != r["predictions"][reference]]}


def summarize(rows):
    fields = ("controlGeneric", "controlPersonal", "candidateGeneric", "candidatePersonal")
    return {"denominator": len(rows), "correct": {k: sum(r["correct"][k] for r in rows) for k in fields},
            "invalid": {arm: sum(r["outcomes"][arm] != "read" for r in rows) for arm in ARMS},
            "comparisons": {name: paired_summary(rows, candidate, reference) for name, candidate, reference in (
                ("candidateGenericVsControlGeneric", "candidateGeneric", "controlGeneric"),
                ("candidatePersonalVsControlPersonal", "candidatePersonal", "controlPersonal"),
                ("candidatePersonalVsOwnGeneric", "candidatePersonal", "candidateGeneric"),
                ("controlPersonalVsOwnGeneric", "controlPersonal", "controlGeneric"))}}


def join_rows(predictions, truth, copies):
    """Pure scoring seam. No alias, parser, top-k rescue or hidden exclusion."""
    require(len(truth) == len({q["sampleID"] for q in truth}), "Duplicate truth identity")
    answers = {q["sampleID"]: q for q in truth}
    require(len(copies) == len({c["sampleID"] for c in copies}), "Duplicate copy identity")
    exclusions = {c["sampleID"]: c["reasons"] for c in copies}
    require(set(answers) == set(exclusions), "Truth/copy cohort mismatch")
    grouped = {}
    for row in predictions:
        key = (row["task"], row["sampleID"])
        require(row["arm"] in ARMS and row["arm"] not in grouped.setdefault(key, {}), "Duplicate predicted arm")
        grouped[key][row["arm"]] = row
    require({sid for _, sid in grouped} == set(answers), "Missing/extra predicted query")
    joined = []
    for (task, sid), arms in sorted(grouped.items()):
        require(set(arms) == set(ARMS) and task in TASKS, "Missing paired prediction")
        answer = answers[sid]
        require(all(r["writerID"] == answer["writerID"] for r in arms.values()) and isinstance(answer["label"], str) and len(answer["label"]) == 1, "Truth writer/codepoint mismatch")
        predicted = {}
        for arm, prefix in zip(ARMS, ("control", "candidate")):
            row = arms[arm]
            for field, route in (("genericRanks", "Generic"), ("personalRanks", "Personal")):
                predicted[prefix + route] = row[field][0]["label"] if row["outcome"] == "read" else None
        joined.append({"task": task, "sampleID": sid, "writerID": answer["writerID"], "intended": answer["label"],
                       "exclusions": exclusions[sid], "eligible": not exclusions[sid], "taught": answer["label"] in TASKS[task],
                       "appAvailable": answer["label"] in CATALOG, "predictions": predicted,
                       "outcomes": {arm: arms[arm]["outcome"] for arm in ARMS},
                       "correct": {k: v == answer["label"] for k, v in predicted.items()}})
    return joined


def score(predictions, prediction_sha256, truth_path, copy_path, output):
    # Read/freeze/validate all predictions BEFORE the first truth-file read.
    data = read(predictions)
    require(digest_string(prediction_sha256) and sha(data) == prediction_sha256, "Prediction SHA mismatch")
    packet = parsed(data); validate_prediction_packet(packet)
    truth_data, copy_data = read(truth_path, 1024 * 1024), read(copy_path, 16 * 1024 * 1024)
    require(sha(truth_data) == packet["bindings"]["queryTruthSHA256"] and sha(copy_data) == packet["bindings"]["sourceCopyLedgerSHA256"], "Frozen truth/copy digest mismatch")
    truth, copies = parsed(truth_data), parsed(copy_data)
    require(truth["version"] == "public-app-local-transfer-truth-v1" and copies["version"] == "public-app-local-transfer-source-copy-ledger-v1"
            and truth["sourceSHA256"] == copies["sourceSHA256"] == SOURCE_SHA256
            and truth["fixtureSHA256"] == copies["fixtureSHA256"] == FIXTURE_SHA256
            and copies["reservedWriterRasterCount"] == 0 and len(truth["queries"]) == len(copies["queryRows"]) == 776, "Truth/copy source binding mismatch")
    joined = join_rows(packet["rows"], truth["queries"], copies["queryRows"])
    require(len(joined) == 1552 and sum(not c["reasons"] for c in copies["queryRows"]) == 772, "Fixed raw/no-copy cohorts changed")
    tasks = {}
    passed = True
    for task in TASKS:
        task_rows = [r for r in joined if r["task"] == task]
        tasks[task] = {}
        for view, group in (("raw", task_rows), ("noCopy", [r for r in task_rows if r["eligible"]])):
            totals = summarize(group)
            strata = {name: summarize([r for r in group if predicate(r)]) for name, predicate in (
                ("taught", lambda r: r["taught"]), ("untaught", lambda r: not r["taught"]),
                ("appAvailable", lambda r: r["appAvailable"]), ("appUntaught", lambda r: r["appAvailable"] and not r["taught"]),
                ("nonApp", lambda r: not r["appAvailable"]))}
            by_writer = {writer: summarize([r for r in group if r["writerID"] == writer]) for writer in WRITERS}
            c = totals["comparisons"]
            conditions = (c["candidateGenericVsControlGeneric"]["net"] >= 0,
                          c["candidatePersonalVsControlPersonal"]["net"] > 0,
                          strata["untaught"]["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0,
                          all(w["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0 for w in by_writer.values()),
                          c["candidatePersonalVsOwnGeneric"]["net"] > 0,
                          strata["untaught"]["comparisons"]["candidatePersonalVsOwnGeneric"]["harms"] == 0)
            passed &= all(conditions)
            tasks[task][view] = {**totals, "strata": strata, "writers": by_writer, "fixedFutilityConditions": list(conditions)}
    value = {"version": "personal-cross-writer-evaluation-score-v1", "predictionSHA256": prediction_sha256,
             "queryTruthSHA256": sha(truth_data), "sourceCopyLedgerSHA256": sha(copy_data), "protocolSHA256": PROTOCOL_SHA256,
             "descriptiveReusedDevelopmentOnly": True, "freshWriterAccuracyMeasured": False, "naturalChordAccuracyMeasured": False,
             "productionEligible": False, "reservedWriterInferencePerformed": False, "tasks": tasks, "rows": joined,
             "passesFixedFutilityScreen": passed, "disposition": "eligible-for-separate-gate-planning-only" if passed else "reject-fixed-candidate-no-retuning"}
    exclusive(output, canonical(value), (predictions, truth_path, copy_path))
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="operation", required=True)
    for name in ("prepare", "predict"):
        p = sub.add_parser(name)
        for key in ("fit", "fixture", "app-report", "protocol", "output"):
            p.add_argument("--" + key, type=Path, required=True)
        if name == "predict": p.add_argument("--commitment", type=Path, required=True)
    p = sub.add_parser("score")
    for key in ("predictions", "truth", "copy-ledger", "output"): p.add_argument("--" + key, type=Path, required=True)
    p.add_argument("--predictions-sha256", required=True)
    args = parser.parse_args()
    if args.operation == "prepare": result = prepare(args.fit, args.fixture, args.app_report, args.protocol, args.output)
    elif args.operation == "predict": result = predict(args.fit, args.fixture, args.app_report, args.protocol, args.commitment, args.output)
    else: result = score(args.predictions, args.predictions_sha256, args.truth, args.copy_ledger, args.output)
    print(json.dumps({k: v for k, v in result.items() if k not in ("rows", "tasks", "fitFilesSHA256", "codeSHA256")}, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
