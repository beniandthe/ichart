"""Fixed, offline append-only screen; frozen cache vectors, then separate truth join.

No encoder, rasterizer, query-target fitter, live-reader or profile-writing API.
Full scores are audit-only, never confidence; only the actual permitted winner
is a reader result. The two reused encoder views are not independent datasets.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import platform

import numpy as np

from ..contracts import strict_json_loads
from . import personal_append_only_residual as learner
from .personal_residual import validate_features, validate_scores

VERSION = "personal-class-frozen-append-only-predictions-v1"
PROTOCOL = "docs/personal-class-frozen-append-only-protocol-2026-10-03.md"
PROTOCOL_SHA = "582d403c069a8650785e111e15731dce8945283dfc963cc0432564769ab6b39b"
PINS = {
    "app": "52b97f84d40998a22f2c10402ff7ece5dae57a4f54cc744c11e0284d9015a618",
    "ce": "6dea2572ced1c8c21fe8523b8fc9d192bb7cfe427a58fb32908e77e664ff5fe9",
    "ceReceipt": "65a46d208f1f33cc4b773b01ae13eb239e76a03a4c75d2874d27c674848736a2",
    "domain": "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010",
    "truth": "38c97b7d8b065d45d359ea401c18ef7cb2a0062ed7f3733a17e8cfbc1c8b57fe",
    "copies": "6a96bf1de6acce0bda4a445e8f92a9437092969cedd78636f4f4f3435f653985",
}
SOURCE_SHA = "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61"
FIXTURE_SHA = "d3de7699f1175b8a77aab37eaf64ab2a3e47042cd58cc7416839122cd4baa55d"
CE_WEIGHTS_SHA = "59bd1e9de8c349cef7209663245cb2b5582497fa31d70207502f1e38ded115d3"
WRITERS = ("trn_UJI_W04", "trn_UJI_W06", "trn_UJI_W08", "trn_UJI_W11",
           "trn_UPV_W35", "trn_UPV_W43", "trn_UPV_W47", "trn_UPV_W56")
CORE = tuple("ABCDEFG") + ("b", "-", "7")
ADDED = tuple("()1234569mo")
CATALOG = CORE + ADDED
VIEWS = ("originalAppRuntime", "writerSeparatedCEControl")
ARMS = ("generic", "reference10", "fullRefit21", "classFrozen21")
ROOT = Path(__file__).resolve().parents[3]
CODE = (PROTOCOL, "recognition_ml/ichart_recognition_ml/research/personal_class_frozen_append_only_evaluation.py",
        "recognition_ml/tests/test_personal_class_frozen_append_only_evaluation.py",
        "recognition_ml/ichart_recognition_ml/research/personal_append_only_residual.py",
        "recognition_ml/tests/test_personal_append_only_residual.py",
        "recognition_ml/ichart_recognition_ml/research/personal_residual.py",
        "recognition_ml/ichart_recognition_ml/contracts.py", "iChart/Shared/ChordNotation/ChordRecognitionDomain.swift",
        "iChart/Shared/ChordNotation/ChordNotation.swift")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def parsed(data):
    return strict_json_loads(data.decode(), "append-only-screen")


def read(path):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and path.stat().st_size <= 256 * 1024 * 1024, "Unbounded/aliased input")
    return path.read_bytes()


def exclusive(path, data):
    path = Path(path)
    require(path.is_absolute() and path.parent.resolve() == path.parent and path.parent.is_dir()
            and ROOT not in path.parents and not path.exists() and not path.is_symlink(), "Exclusive outside-source output required")
    with path.open("xb") as stream:
        stream.write(data)


def code_identity():
    result = {name: sha(read(ROOT / name)) for name in CODE}
    require(result[PROTOCOL] == PROTOCOL_SHA, "Fixed protocol changed")
    require(result["recognition_ml/ichart_recognition_ml/research/personal_append_only_residual.py"] == "871773e34631f079b256f0aed4a6fb9c0da8756b874d6f002d565da6be1227ff", "Fixed candidate module changed")
    require(result["iChart/Shared/ChordNotation/ChordRecognitionDomain.swift"] == "c1c4d50e5317e8872987d123bcfbe5defa97189c149638c038a5235e7f78b385"
            and result["iChart/Shared/ChordNotation/ChordNotation.swift"] == "b725238345c881c7d0ee1fcfba52c49bca7469b1e301663265c7d50bd6d6e25d", "Swift domain source changed")
    return result


def blob(value, expected):
    data = base64.b64decode(value, validate=True)
    require(base64.b64encode(data).decode() == value and sha(data) == expected, "Source bytes digest mismatch")
    return data


def bits(value):
    return np.ascontiguousarray(value, dtype="<f8").tobytes()


def vector(feature, scores, feature_sha=None, score_sha=None):
    x, b = np.asarray(feature, dtype=np.float64), np.asarray(scores, dtype=np.float64)
    require(x.shape == (128,) and b.shape == (97,), "128/97 vector dimensions required")
    validate_features(x[None, :]); validate_scores(b[None, :], 1, 97)
    require(feature_sha is None or sha(bits(x)) == feature_sha, "Embedding commitment mismatch")
    require(score_sha is None or sha(bits(b)) == score_sha, "Score commitment mismatch")
    return {"embedding": x.tolist(), "baseScores": b.tolist(), "embeddingSHA256": sha(bits(x)), "baseScoresSHA256": sha(bits(b))}


def index(rows, key):
    result = {key(row): row for row in rows}
    require(len(result) == len(rows), "Duplicate identity")
    return result


def prepare_views(app, ce, fit, domain):
    """Source/vector validation only. This function neither fits nor opens truth."""
    vocab, allowed = app["vocabulary"], domain["allowedLabels"]
    require(len(vocab) == len(set(vocab)) == 97 and domain["version"] == "chord-recognition-domain-v1"
            and domain["vocabulary"] == ce["vocabulary"] == fit["vocabulary"] == vocab
            and len(allowed) == len(set(allowed)) == 41 and set(CATALOG) <= set(allowed) <= set(vocab), "Fixed domain/vocabulary mismatch")
    require(app["version"] == "public-app-local-transfer-predictions-v1" and app["trainingEligible"] is False
            and app["intendedQueryLabelsSupplied"] is False and app["trainingWriterMembershipVerified"] is False
            and app["reservedWriterInferencePerformed"] is False and ce["queryTruthOpened"] is False
            and ce["reservedFeatureCount"] == ce["reservedInferenceCount"] == 0, "Cache role guard changed")
    require(app["sourceSHA256"] == ce["bindings"]["sourceSHA256"] == fit["sourceSHA256"] == SOURCE_SHA
            and app["fixtureSHA256"] == ce["bindings"]["fixtureSHA256"] == FIXTURE_SHA
            and ce["bindings"]["appReportSHA256"] == PINS["app"] and ce["bindings"]["fitReceiptSHA256"] == PINS["ceReceipt"], "Parent binding mismatch")
    require(app["queryTruthSHA256"] == ce["bindings"]["queryTruthSHA256"] == PINS["truth"]
            and app["sourceCopyLedgerSHA256"] == ce["bindings"]["sourceCopyLedgerSHA256"] == PINS["copies"]
            and parsed(blob(ce["fitReceiptCanonicalData"], PINS["ceReceipt"])) == fit, "Scoring/fit receipt binding mismatch")
    training = fit["trainingInputs"]; training_writers = fit["trainingWriters"]
    require(len(training) == 6208 and len(training_writers) == len(set(training_writers)) == 32
            and not set(training_writers) & set(WRITERS) and fit["developmentWriters"] == list(WRITERS)
            and fit["weightsSHA256"]["crossEntropyControl"] == CE_WEIGHTS_SHA, "CE fit writer/checkpoint mismatch")
    require({(r["writer"], r["session"], r["label"]) for r in training}
            == {(w, s, l) for w in training_writers for s in (1, 2) for l in vocab}, "CE training grid incomplete")
    raw = index(app["rawSamples"], lambda r: r["id"])
    require(len(raw) == 1552 and {r["writerID"] for r in raw.values()} == set(WRITERS), "Raw source cohort mismatch")
    for row in raw.values():
        blob(row["sourceCanonicalData"], row["sourcePacketSHA256"])
    profiles = index(app["profiles"], lambda p: (p["writerID"], p["task"]))
    ce_support = index([p for p in ce["supports"] if p["arm"] == "crossEntropyControl"], lambda p: (p["writerID"], p["task"]))
    require(set(profiles) == set(ce_support) == {(w, t) for w in WRITERS for t in ("core10", "catalog21")}, "Support schedule mismatch")
    supports = {name: {} for name in VIEWS}
    for writer in WRITERS:
        tasks = {}
        for task, labels in (("core10", CORE), ("catalog21", CATALOG)):
            p = profiles[writer, task]; profile = parsed(blob(p["profileCanonicalData"], p["profileSHA256"]))
            stored = p["supportLessons"]; examples = index(profile["examples"], lambda e: e["id"])
            app_vectors = index(p["support"]["lessons"], lambda l: l["exampleID"])
            ce_vectors = index(ce_support[writer, task]["lessons"], lambda l: l["exampleID"])
            require(len(stored) == len(examples) == len(app_vectors) == len(ce_vectors) == len(labels)
                    and {r["label"] for r in stored} == set(labels) and [r["exampleID"] for r in stored] == [e["id"] for e in profile["examples"]]
                    and set(examples) == set(app_vectors) == set(ce_vectors), "Support ID/count/order mismatch")
            require(p["support"]["profileSHA256"] == p["modelIdentity"]["profileSHA256"] == p["profileSHA256"]
                    and p["support"]["encoderIdentity"] == app["encoderIdentity"], "Support profile/encoder mismatch")
            joined = {name: [] for name in VIEWS}
            for row in stored:
                example, a, c, source = examples[row["exampleID"]], app_vectors[row["exampleID"]], ce_vectors[row["exampleID"]], raw[row["sampleID"]]
                require(source["session"] == 1 and source["writerID"] == writer and example["kind"] == "glyph"
                        and example["source"] == a["source"] == "setup" and example["label"] == a["label"] == row["label"], "Explicit support source/label mismatch")
                blob(row["storedCanonicalData"], row["storedPacketSHA256"])
                require(a["storedInkSHA256"] == row["storedPacketSHA256"], "Profile example/stored packet commitment mismatch")
                require(all(c[k] == row[k] for k in ("sampleID", "exampleID", "label", "storedCanonicalData", "storedPacketSHA256", "storedRasterSHA256"))
                        and c["profileSHA256"] == p["profileSHA256"], "CE/app original stored ink mismatch")
                identity = {**row, "profileSHA256": p["profileSHA256"], "storedInkSHA256": a["storedInkSHA256"],
                            "rawSourcePacketSHA256": source["sourcePacketSHA256"], "rawRasterSHA256": source["rawRasterSHA256"]}
                for name, v in ((VIEWS[0], vector(a["embedding"], a["baseScores"], a["embeddingSHA256"], a["baseScoresSHA256"])),
                                (VIEWS[1], vector(c["embedding"], c["baseScores"]))):
                    joined[name].append({"identity": identity, **v})
            tasks[task] = joined
        for name in VIEWS:
            prefix = tasks["core10"][name]
            suffix = sorted((r for r in tasks["catalog21"][name] if r["identity"]["label"] not in CORE), key=lambda r: r["identity"]["label"])
            require(tuple(r["identity"]["label"] for r in suffix) == ADDED, "Fixed append suffix changed")
            require(all(len({r["identity"][key] for r in prefix + suffix}) == 21 for key in ("exampleID", "sampleID")), "Duplicate logical lesson/source identity")
            supports[name][writer] = prefix + suffix
    app_rows = index(app["rows"], lambda r: (r["task"], r["sampleID"]))
    ce_rows = index([r for r in ce["rows"] if r["arm"] == "crossEntropyControl"], lambda r: (r["task"], r["sampleID"]))
    query_ids = sorted(sid for sid, r in raw.items() if r["session"] == 2)
    require(len(query_ids) == 776 and set(app_rows) == set(ce_rows) == {(t, sid) for t in ("core10", "catalog21") for sid in query_ids}, "776 distinct query schedule required")
    queries = {name: [] for name in VIEWS}
    for sid in query_ids:
        source = raw[sid]; identity = {"sampleID": sid, "writerID": source["writerID"], "sourcePacketSHA256": source["sourcePacketSHA256"], "rawRasterSHA256": source["rawRasterSHA256"]}
        for name, rows in ((VIEWS[0], app_rows), (VIEWS[1], ce_rows)):
            duplicates = []
            for task in ("core10", "catalog21"):
                r = rows[task, sid]; require(r["writerID"] == source["writerID"], "Query writer mismatch")
                v, failure = None, r["failure"]
                if name == VIEWS[1]:
                    require(r["sourcePacketSHA256"] == source["sourcePacketSHA256"] and r["rawRasterSHA256"] == source["rawRasterSHA256"]
                            and r["sourceCanonicalData"] == source["sourceCanonicalData"], "CE/app query source mismatch")
                if r["outcome"] == "read":
                    g = r["reading"]["glyphs"][0] if name == VIEWS[0] else r
                    if name == VIEWS[0]:
                        require(len(r["reading"]["glyphs"]) == 1 and r["reading"]["sourceInkSHA256"] == source["sourcePacketSHA256"]
                                and r["reading"]["encoderIdentity"] == app["encoderIdentity"], "App query source/encoder mismatch")
                    try:
                        v = vector(g["embedding"], g["baseScores"], g.get("embeddingSHA256"), g.get("baseScoresSHA256")); failure = None
                    except ValueError:
                        failure = "invalid-cached-vector"
                else:
                    require(r["outcome"] == "invalid-ink", "Unknown cached query outcome")
                duplicates.append({**identity, "vector": v, "failure": failure})
            require(canonical(duplicates[0]) == canonical(duplicates[1]), "Task-duplicate query vector/hash/failure mismatch")
            queries[name].append(duplicates[0])
    return {"version": VERSION, "protocolSHA256": PROTOCOL_SHA, "vocabulary": vocab, "allowedLabels": allowed,
            "encoderIdentity": {VIEWS[0]: app["encoderIdentity"], VIEWS[1]: "crossEntropyControl:" + CE_WEIGHTS_SHA},
            "supports": supports, "queries": queries, "parentCodeBindings": {"app": app["codeFilesSHA256"], "ce": ce["bindings"]["codeSHA256"]},
            "parentWeightBindings": {"appRuntime": app["runtimeFilesSHA256"], "ce": fit["weightsSHA256"]},
            "parentHistoryReceiptSHA256": PINS["ceReceipt"], "queryTruthOpened": False, "productionEligible": False}


def permitted_top(scores, vocabulary, allowed):
    winner = min(range(len(vocabulary)), key=lambda c: (-scores[c], vocabulary[c]))
    return vocabulary[winner] if vocabulary[winner] in allowed else None


def adjusted_from_weights(weights, feature, base_scores):
    # Vectorize independent columns, never the reduction: each column still
    # starts at +0 and accumulates feature 0..127, matching the frozen prototype.
    correction = np.zeros(97, dtype=np.float64)
    weights = np.asarray(weights, dtype=np.float64)
    for feature_index in range(128):
        correction += feature[feature_index] * weights[feature_index, :]
    return np.asarray(base_scores, dtype=np.float64) + correction


def fit_snapshots(plan):
    """Only explicit support enters the fitter; all views fit before any query."""
    vocabulary = plan["vocabulary"]
    untouched = [i for i, label in enumerate(vocabulary) if label not in ADDED]
    models, snapshots = {}, {}
    for view in VIEWS:
        models[view], snapshots[view] = {}, {}
        for writer in WRITERS:
            history = plan["supports"][view][writer]
            x = np.array([r["embedding"] for r in history]); b = np.array([r["baseScores"] for r in history])
            labels = [r["identity"]["label"] for r in history]; ids = [sha(canonical(r["identity"])) for r in history]
            require(len(history) == 21 and set(labels[:10]) == set(CORE) and tuple(labels[10:]) == ADDED, "Malformed fixed support history")
            ref = learner.fit_reference(x[:10], b[:10], labels[:10], ids[:10], vocabulary, plan["encoderIdentity"][view])
            full = learner.fit_reference(x, b, labels, ids, vocabulary, plan["encoderIdentity"][view])
            candidate = learner.append_only_refit(ref, features=x, base_scores=b, labels=labels, source_ids=ids, vocabulary=vocabulary, encoder_identity=ref.encoder_identity)
            require(bits(ref.weights[:, untouched]) == bits(candidate.weights[:, untouched]), "Untouched weights changed")
            models[view][writer] = {"reference10": ref, "fullRefit21": full, "classFrozen21": candidate}
            snapshots[view][writer] = {arm: {"weights": head.weights.tolist(), "weightsSHA256": sha(bits(head.weights)),
                "supportHistorySHA256": sha(canonical(history[:head.lesson_count])), "sourceIDs": list(head.source_ids),
                "labels": list(head.labels), "lastRefittedLabels": list(head.last_refitted_labels), "regularization": head.regularization}
                for arm, head in models[view][writer].items()}
    return models, snapshots


def predict_queries(plan, models):
    """The forward method sees numeric vectors only, never query IDs/targets."""
    vocabulary, allowed = plan["vocabulary"], set(plan["allowedLabels"])
    untouched = [i for i, label in enumerate(vocabulary) if label not in ADDED]
    rows = {view: [] for view in VIEWS}
    for view in VIEWS:
        for query in plan["queries"][view]:
            scores = {arm: None for arm in ARMS}; predictions = {arm: None for arm in ARMS}; invariant = True
            if query["vector"] is not None:
                v = query["vector"]; x, b = np.array(v["embedding"]), np.array(v["baseScores"])
                scores["generic"] = b.tolist()
                for arm, head in models[view][query["writerID"]].items():
                    scores[arm] = head.adjusted_scores(x, b).tolist()
                invariant = bits(np.array(scores["reference10"])[untouched]) == bits(np.array(scores["classFrozen21"])[untouched])
                require(invariant, "Untouched query scores changed")
                predictions = {arm: permitted_top(s, vocabulary, allowed) for arm, s in scores.items()}
            rows[view].append({"sampleID": query["sampleID"], "writerID": query["writerID"], "failure": query["failure"],
                              "scores": scores, "predictions": predictions, "untouchedScoresBitIdentical": invariant})
    return {"version": VERSION, "vocabulary": vocabulary, "allowedLabels": plan["allowedLabels"], "rows": rows}


def freeze(app_report, ce_predictions, ce_receipt, domain, output):
    inputs = dict(zip(("app", "ce", "ceReceipt", "domain"), (app_report, ce_predictions, ce_receipt, domain), strict=True))
    data = {name: read(path) for name, path in inputs.items()}
    require(all(sha(value) == PINS[name] for name, value in data.items()), "Fixed source pin mismatch")
    before = code_identity(); plan = prepare_views(*(parsed(data[n]) for n in ("app", "ce", "ceReceipt", "domain")))
    plan["inputSHA256"] = {name: sha(value) for name, value in data.items()}; plan["codeSHA256"] = before
    output = Path(output)
    require(output.is_absolute() and output.parent.resolve() == output.parent and output.parent.is_dir()
            and ROOT not in output.parents and not output.exists() and all(output != Path(p) and Path(p) not in output.parents for p in inputs.values()), "Fresh outside-source directory required")
    output.mkdir()
    exclusive(output / "fit-plan.json", canonical(plan))  # Every support/query source/vector frozen before first solve.
    models, snapshots = fit_snapshots(plan)
    exclusive(output / "snapshots.json", canonical(snapshots))  # All weights/history receipts precede all query predictions.
    snapshot_receipt = {"fitPlanSHA256": sha(canonical(plan)), "snapshotsSHA256": sha(canonical(snapshots)),
                        "codeSHA256": before, "queryPredictionsStarted": False}
    exclusive(output / "snapshot-receipt.json", canonical(snapshot_receipt))
    require(read(output / "fit-plan.json") == canonical(plan) and read(output / "snapshots.json") == canonical(snapshots)
            and read(output / "snapshot-receipt.json") == canonical(snapshot_receipt), "Pre-prediction snapshot freeze changed")
    packet = predict_queries(plan, models)
    require(code_identity() == before and all(read(path) == data[name] for name, path in inputs.items()), "Code/source changed during freeze")
    require(read(output / "fit-plan.json") == canonical(plan) and read(output / "snapshots.json") == canonical(snapshots)
            and read(output / "snapshot-receipt.json") == canonical(snapshot_receipt), "Frozen plan/snapshots changed during prediction")
    exclusive(output / "predictions.json", canonical(packet))
    receipt = {"version": VERSION, "protocolSHA256": PROTOCOL_SHA, "inputSHA256": plan["inputSHA256"], "codeSHA256": before,
               "artifacts": {name: sha(read(output / name)) for name in ("fit-plan.json", "snapshots.json", "snapshot-receipt.json", "predictions.json")},
               "runtime": {"python": platform.python_version(), "numpy": np.__version__, "platform": platform.platform()},
               "distinctQueriesPerEncoder": 776, "queryTruthOpened": False, "encoderInferencePerformed": False,
               "rastersConstructed": False, "privateOrReservedUsed": False, "productionEligible": False}
    exclusive(output / "freeze-receipt.json", canonical(receipt)); return receipt


def validate_frozen(directory, receipt_sha):
    directory = Path(directory); receipt_data = read(directory / "freeze-receipt.json")
    require({p.name for p in directory.iterdir()} == {"fit-plan.json", "snapshots.json", "snapshot-receipt.json", "predictions.json", "freeze-receipt.json"}, "Immutable freeze directory changed")
    require(sha(receipt_data) == receipt_sha, "Freeze receipt pin mismatch")
    receipt = parsed(receipt_data)
    require(receipt["version"] == VERSION and receipt["protocolSHA256"] == PROTOCOL_SHA
            and receipt["codeSHA256"] == code_identity() and receipt["inputSHA256"] == {k: PINS[k] for k in ("app", "ce", "ceReceipt", "domain")}, "Frozen code/source/protocol changed")
    files = {name: read(directory / name) for name in ("fit-plan.json", "snapshots.json", "snapshot-receipt.json", "predictions.json")}
    require(receipt["artifacts"] == {name: sha(data) for name, data in files.items()}, "Frozen artifact changed")
    plan, snapshots, packet = (parsed(files[name]) for name in ("fit-plan.json", "snapshots.json", "predictions.json"))
    require(parsed(files["snapshot-receipt.json"]) == {"fitPlanSHA256": sha(files["fit-plan.json"]),
            "snapshotsSHA256": sha(files["snapshots.json"]), "codeSHA256": receipt["codeSHA256"], "queryPredictionsStarted": False}, "Snapshot pre-prediction receipt mismatch")
    require(plan["codeSHA256"] == receipt["codeSHA256"] and plan["inputSHA256"] == receipt["inputSHA256"]
            and plan["protocolSHA256"] == PROTOCOL_SHA and packet["version"] == VERSION and packet["vocabulary"] == plan["vocabulary"]
            and packet["allowedLabels"] == plan["allowedLabels"], "Plan/prediction binding mismatch")
    vocabulary, allowed = packet["vocabulary"], set(packet["allowedLabels"])
    untouched = [i for i, label in enumerate(vocabulary) if label not in ADDED]
    for view in VIEWS:
        queries = index(plan["queries"][view], lambda r: r["sampleID"])
        rows = index(packet["rows"][view], lambda r: r["sampleID"])
        require(len(rows) == len(queries) == 776 and set(rows) == set(queries), "Frozen query denominator changed")
        for writer in WRITERS:
            history = plan["supports"][view][writer]
            require(set(snapshots[view][writer]) == set(ARMS[1:]), "Complete snapshot arms required")
            for arm, snap in snapshots[view][writer].items():
                count = 10 if arm == "reference10" else 21
                require(sha(bits(snap["weights"])) == snap["weightsSHA256"] and np.asarray(snap["weights"]).shape == (128, 97)
                        and np.isfinite(np.asarray(snap["weights"])).all() and snap["regularization"] == learner.REGULARIZATION
                        and snap["supportHistorySHA256"] == sha(canonical(history[:count]))
                        and snap["sourceIDs"] == [sha(canonical(r["identity"])) for r in history[:count]]
                        and snap["labels"] == [r["identity"]["label"] for r in history[:count]]
                        and snap["lastRefittedLabels"] == (list(vocabulary) if arm != "classFrozen21" else [l for l in vocabulary if l in ADDED]), "Weight/history receipt mismatch")
            require(bits(np.array(snapshots[view][writer]["reference10"]["weights"])[:, untouched])
                    == bits(np.array(snapshots[view][writer]["classFrozen21"]["weights"])[:, untouched]), "Untouched weight binding failed")
            changed = [i for i, label in enumerate(vocabulary) if label in ADDED]
            require(bits(np.array(snapshots[view][writer]["fullRefit21"]["weights"])[:, changed])
                    == bits(np.array(snapshots[view][writer]["classFrozen21"]["weights"])[:, changed]), "Changed-column full-solve binding failed")
        for sid, r in rows.items():
            require(set(r["scores"]) == set(r["predictions"]) == set(ARMS), "Complete prediction arms required")
            require(r["writerID"] == queries[sid]["writerID"] and r["failure"] == queries[sid]["failure"], "Frozen query identity/failure changed")
            if queries[sid]["vector"] is None:
                require(all(r["scores"][a] is None and r["predictions"][a] is None for a in ARMS), "Invalid query rescued")
            else:
                for arm in ARMS:
                    s = np.asarray(r["scores"][arm]); require(s.shape == (97,) and np.isfinite(s).all(), "Invalid full97 output")
                    require(r["predictions"][arm] == permitted_top(s, vocabulary, allowed), "Domain projection/rank rescue changed")
                    if arm != "generic":
                        v = queries[sid]["vector"]
                        expected = adjusted_from_weights(snapshots[view][r["writerID"]][arm]["weights"], v["embedding"], v["baseScores"])
                        require(bits(s) == bits(expected), "Query scores do not match frozen snapshot")
                require(bits(r["scores"]["generic"]) == bits(queries[sid]["vector"]["baseScores"])
                        and r["untouchedScoresBitIdentical"] is True
                        and bits(np.array(r["scores"]["reference10"])[untouched]) == bits(np.array(r["scores"]["classFrozen21"])[untouched]), "Generic/untouched score invariant failed")
    return packet, receipt


def summarize(rows):
    def pair(arm):
        gains = sum(r["correct"][arm] and not r["correct"]["reference10"] for r in rows)
        harms = sum(r["correct"]["reference10"] and not r["correct"][arm] for r in rows)
        return {"gains": gains, "harms": harms, "net": gains - harms,
                "correctToWrong": sum(r["correct"]["reference10"] and not r["correct"][arm] and r["predictions"][arm] is not None for r in rows),
                "correctToUnresolved": sum(r["correct"]["reference10"] and r["predictions"][arm] is None for r in rows)}
    return {"denominator": len(rows), "invalid": sum(r["failure"] is not None for r in rows),
            "arms": {a: {"correct": sum(r["correct"][a] for r in rows), "wrongNonNull": sum(not r["correct"][a] and r["predictions"][a] is not None for r in rows),
                         "unresolved": sum(r["predictions"][a] is None for r in rows)} for a in ARMS},
            "candidateVsReference": pair("classFrozen21"), "fullRefitVsReferenceDiagnosticOnly": pair("fullRefit21")}


def score_packet(packet, truth, copies):
    require(truth["version"] == "public-app-local-transfer-truth-v1" and copies["version"] == "public-app-local-transfer-source-copy-ledger-v1"
            and truth["sourceSHA256"] == copies["sourceSHA256"] == SOURCE_SHA and truth["fixtureSHA256"] == copies["fixtureSHA256"] == FIXTURE_SHA
            and copies["reservedWriterRasterCount"] == 0, "Truth/copy parent mismatch")
    answers = index(truth["queries"], lambda r: r["sampleID"]); excluded = index(copies["queryRows"], lambda r: r["sampleID"])
    require(len(answers) == len(excluded) == 776 and set(answers) == set(excluded)
            and sum(not r["reasons"] for r in excluded.values()) == 772, "Raw/no-copy denominator changed")
    allowed, vocabulary = set(packet["allowedLabels"]), set(packet["vocabulary"])
    require(all(isinstance(r["reasons"], list) for r in excluded.values()), "Copy reasons malformed")
    require({(r["writerID"], r["label"]) for r in answers.values()} == {(w, l) for w in WRITERS for l in vocabulary}, "Scoring grid incomplete")
    views = {}; all_pass = True
    for encoder in VIEWS:
        pred = index(packet["rows"][encoder], lambda r: r["sampleID"])
        require(set(pred) == set(answers) and len(pred) == 776, "Truth/freeze cohort mismatch")
        joined = []
        for sid, r in pred.items():
            answer = answers[sid]; label = answer["label"]
            require(set(r["predictions"]) == set(ARMS) and r["writerID"] == answer["writerID"]
                    and all(p is None or p in allowed for p in r["predictions"].values()), "Truth writer/domain output mismatch")
            stratum = "old10" if label in CORE else "added11" if label in ADDED else "remaining20" if label in allowed else "outOfDomain56"
            joined.append({**{k: r[k] for k in ("sampleID", "writerID", "failure", "predictions", "untouchedScoresBitIdentical")},
                           "stratum": stratum, "intended": label if label in allowed else None,
                           "eligible": not excluded[sid]["reasons"], "exclusions": excluded[sid]["reasons"],
                           "correct": {a: r["predictions"][a] == label for a in ARMS}})
        views[encoder] = {}
        for name, group in (("raw", joined), ("noCopy", [r for r in joined if r["eligible"]])):
            domain = [r for r in group if r["stratum"] != "outOfDomain56"]; ood = [r for r in group if r["stratum"] == "outOfDomain56"]
            require(len(domain) == (328 if name == "raw" else 324) and len(ood) == 448, "Domain/OOD denominator changed")
            totals = summarize(domain); strata = {s: summarize([r for r in domain if r["stratum"] == s]) for s in ("old10", "added11", "remaining20")}
            writers = {w: summarize([r for r in domain if r["writerID"] == w]) for w in WRITERS}
            new_ood = sum(r["predictions"]["reference10"] is None and r["predictions"]["classFrozen21"] is not None for r in ood)
            conditions = {"untouchedScoresBitIdentical": all(r["untouchedScoresBitIdentical"] for r in group),
                          "addedLabelNetPositive": strata["added11"]["candidateVsReference"]["net"] > 0,
                          "overallDomainNetPositive": totals["candidateVsReference"]["net"] > 0,
                          "zeroOldAndRemainingHarms": all(strata[s]["candidateVsReference"]["harms"] == 0 for s in ("old10", "remaining20")),
                          "everyWriterNonnegative": all(v["candidateVsReference"]["net"] >= 0 for v in writers.values()),
                          "zeroNewOutOfDomainReads": new_ood == 0}
            all_pass &= all(conditions.values())
            views[encoder][name] = {**totals, "strata": strata, "writers": writers, "outOfDomain": {"denominator": len(ood), "newCandidatePermittedReads": new_ood,
                "arms": {a: {"rejected": sum(r["predictions"][a] is None for r in ood), "falsePermittedReads": sum(r["predictions"][a] is not None for r in ood)} for a in ARMS}},
                "fixedScreenConditions": conditions, "scheduled": len(joined), "eligible": sum(r["eligible"] for r in joined), "excluded": sum(not r["eligible"] for r in joined)}
        views[encoder]["rows"] = joined
    return {"version": "personal-class-frozen-append-only-score-v1", "views": views, "passesFixedScreen": all_pass,
            "disposition": "separate-runtime-parity-and-fresh-handwriting-gates-only" if all_pass else "reject-fixed-candidate-no-retuning",
            "reusedDevelopmentOnly": True, "confidenceMeasured": False, "naturalChordAccuracyMeasured": False, "productionEligible": False}


def score(directory, truth_path, copy_path, output, *, receipt_sha256):
    require(Path(output) != Path(directory) and Path(directory) not in Path(output).parents, "Score output must not mutate immutable freeze")
    packet, receipt = validate_frozen(directory, receipt_sha256)  # Validate complete freeze BEFORE either truth file opens.
    truth_data, copy_data = read(truth_path), read(copy_path)
    require(sha(truth_data) == PINS["truth"] and sha(copy_data) == PINS["copies"], "Scoring source pin mismatch")
    result = score_packet(packet, parsed(truth_data), parsed(copy_data))
    result.update({"freezeReceiptSHA256": receipt_sha256, "protocolSHA256": PROTOCOL_SHA,
                   "predictionSHA256": receipt["artifacts"]["predictions.json"], "queryTruthSHA256": sha(truth_data), "sourceCopyLedgerSHA256": sha(copy_data)})
    validate_frozen(directory, receipt_sha256)
    require(read(truth_path) == truth_data and read(copy_path) == copy_data, "Scoring source changed")
    exclusive(output, canonical(result)); return result


def main():
    p = argparse.ArgumentParser(description=__doc__); sub = p.add_subparsers(dest="operation", required=True)
    f = sub.add_parser("freeze")
    for key in ("app-report", "ce-predictions", "ce-receipt", "domain", "output"):
        f.add_argument("--" + key, type=Path, required=True)
    s = sub.add_parser("score")
    for key in ("frozen", "truth", "copy-ledger", "output"):
        s.add_argument("--" + key, type=Path, required=True)
    s.add_argument("--freeze-receipt-sha256", required=True); a = p.parse_args()
    if a.operation == "freeze":
        result = freeze(a.app_report, a.ce_predictions, a.ce_receipt, a.domain, a.output)
    else:
        result = score(a.frozen, a.truth, a.copy_ledger, a.output, receipt_sha256=a.freeze_receipt_sha256)
    print(json.dumps({"operation": a.operation, "output": str(a.output), "passesFixedScreen": result.get("passesFixedScreen")}, sort_keys=True))


if __name__ == "__main__":
    main()
