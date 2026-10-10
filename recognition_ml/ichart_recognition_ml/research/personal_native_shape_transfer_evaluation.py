"""Frozen native-shape transfer diagnostic, not fresh accuracy or live OCR.
Exact Swift setup geometry is reused; personal anchors remain UJI-only.
Selected adapted-HASY/query pixel copies are marked before inference, without
query answers, and excluded symmetrically only in the fixed no-copy view.
"""
from __future__ import annotations

import argparse
import base64
from pathlib import Path

import numpy as np

from . import personal_cross_writer_evaluation as common
from .personal_anchors import AnchorBank, fit_anchored
from .personal_residual import normalized_scores, validate_features, validate_scores
from .personal_visual_encoder import infer

ARMS = ("uji97ReplayPretrain", "hasy369NativePretrain")
VERSION = "personal-native-shape-transfer-evaluation-predictions-v1"
COMMITMENT_VERSION = "personal-native-shape-transfer-evaluation-commitment-v1"
PROTOCOL_SHA256 = "54f426735c0f364bb466329298c5649f6b1f8928aab1be19d45bba9b48e509fb"
ASCII_LABELS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
CODE_PATHS = common.CODE_PATHS + (
    "recognition_ml/ichart_recognition_ml/research/personal_native_shape_transfer.py",
    "recognition_ml/ichart_recognition_ml/research/personal_native_shape_transfer_evaluation.py",
    "recognition_ml/tests/test_personal_native_shape_transfer_evaluation.py",
    "docs/personal-native-shape-transfer-protocol-2026-10-01.md",
)
canonical, sha, require, read, parsed, blob = (common.canonical, common.sha, common.require,
                                            common.read, common.parsed, common.blob)


def code_identity():
    from .personal_native_shape_transfer import code_identity as fit_code_identity
    from .hasy_native_training_source import code_identity as source_code_identity
    root = Path(__file__).resolve().parents[3]
    return {**fit_code_identity(), **source_code_identity(), **{name: sha(read(root / name, 4 * 1024 * 1024)) for name in CODE_PATHS}}


def copy_binding(evidence, raw, query_ids):
    selected = evidence["selectedAdaptedRasterHashes"]
    require(common.digest_string(evidence["receiptSHA256"]) and selected == sorted(set(selected))
            and all(common.digest_string(h) for h in selected) and bool(selected)
            and evidence["selectedAdaptedRasterHashesSHA256"] == sha(canonical(selected))
            and len(set(query_ids)) == len(query_ids) == 776 and all(common.digest_string(i) for i in query_ids), "Malformed HASY copy evidence")
    hashes = set(selected)
    ledger = [{"sampleID": sid, "rawRasterSHA256": raw[sid]["rawRasterSHA256"],
               "reasons": ["selected-hasy-adapted-raster-copy"] if raw[sid]["rawRasterSHA256"] in hashes else []} for sid in sorted(query_ids)]
    require(all(r["rawRasterSHA256"] is None or common.digest_string(r["rawRasterSHA256"]) for r in ledger), "Invalid query raster hash")
    return {"receiptSHA256": evidence["receiptSHA256"], "selectedAdaptedRasterHashes": selected,
            "selectedAdaptedRasterHashesSHA256": evidence["selectedAdaptedRasterHashesSHA256"], "queryRows": ledger}


def load_copy_binding(hasy_dir, hasy_receipt_sha256, raw, query_ids):
    from .hasy_native_training_source import load_prepared
    _, _, evidence = load_prepared(hasy_dir, hasy_receipt_sha256)
    require(evidence["receiptSHA256"] == hasy_receipt_sha256, "HASY preparation receipt mismatch")
    return copy_binding(evidence, raw, query_ids)


def validate_fit(receipt, vocabulary):
    require(tuple(receipt["arms"]) == ARMS and receipt["sourceSHA256"] == common.SOURCE_SHA256
            and tuple(receipt["developmentWriters"]) == common.WRITERS and len(receipt["trainingWriters"]) == 32
            and len(set(receipt["trainingWriters"])) == 32 and all(w.startswith("trn_") for w in receipt["trainingWriters"])
            and len(set(receipt["reservedWriters"])) == 20
            and not set(receipt["trainingWriters"]) & set(common.WRITERS)
            and not set(receipt["reservedWriters"]) & (set(common.WRITERS) | set(receipt["trainingWriters"]))
            and receipt["vocabulary"] == vocabulary
            and receipt["protocolEnvelope"]["markdownProtocolSHA256"] == PROTOCOL_SHA256, "Native-shape fit binding mismatch")


def prepare(fit, fixture, app_report, protocol, hasy_dir, hasy_receipt_sha256, output):
    from .personal_native_shape_transfer import load_fitted_models
    common.configure()
    inputs, app, raw, _, _ = common.load_projection(fixture, app_report)
    require(sha(read(protocol)) == PROTOCOL_SHA256, "Wrong native-shape protocol")
    fit_sha = sha(read(Path(fit) / "fit-receipt.json")); _, receipt = load_fitted_models(fit, fit_sha)
    validate_fit(receipt, inputs["vocabulary97"])
    hasy = load_copy_binding(hasy_dir, hasy_receipt_sha256, raw, sorted({i for s in common.query_schedule(inputs) for i in s["queryIDs"]}))
    require(receipt["hasyPreparedReceiptSHA256"] == hasy_receipt_sha256
            and receipt["hasySelectedAdaptedRasterHashesSHA256"] == hasy["selectedAdaptedRasterHashesSHA256"], "Wrong fitted HASY selection")
    value = {"version": COMMITMENT_VERSION, "sourceSHA256": common.SOURCE_SHA256,
             "fixtureSHA256": common.FIXTURE_SHA256, "appReportSHA256": common.APP_REPORT_SHA256,
             "protocolSHA256": PROTOCOL_SHA256, "fitReceiptSHA256": fit_sha,
             "hasyCopyBinding": hasy, "hasyCopyBindingSHA256": sha(canonical(hasy)),
             "fitFilesSHA256": common.tree_identity(fit), "codeSHA256": code_identity(), "runtime": common.runtime_identity(),
             "queryScheduleSHA256": sha(canonical(common.query_schedule(inputs))), "queryTruthSHA256": app["queryTruthSHA256"],
             "sourceCopyLedgerSHA256": app["sourceCopyLedgerSHA256"], "inferencePerformed": False}
    require(common.tree_identity(fit) == value["fitFilesSHA256"] and code_identity() == value["codeSHA256"]
            and sha(read(protocol)) == PROTOCOL_SHA256 and hasy == load_copy_binding(hasy_dir, hasy_receipt_sha256, raw,
                sorted({i for s in common.query_schedule(inputs) for i in s["queryIDs"]})), "Preparation inputs changed")
    common.exclusive(output, canonical(value), (fit, fixture, app_report, protocol, hasy_dir))
    return value


def predict(fit, fixture, app_report, protocol, hasy_dir, hasy_receipt_sha256, commitment_path, output):
    from .personal_native_shape_transfer import load_fitted_models, load_training_feature_bundle
    common.configure()
    frozen = read(commitment_path); binding = parsed(frozen)
    inputs, app, raw, pixels, supports = common.load_projection(fixture, app_report)
    schedule = common.query_schedule(inputs)
    require(binding["version"] == COMMITMENT_VERSION and binding["inferencePerformed"] is False
            and binding["sourceSHA256"] == common.SOURCE_SHA256 and binding["fixtureSHA256"] == common.FIXTURE_SHA256
            and binding["appReportSHA256"] == common.APP_REPORT_SHA256 and binding["protocolSHA256"] == sha(read(protocol)) == PROTOCOL_SHA256
            and binding["fitReceiptSHA256"] == sha(read(Path(fit) / "fit-receipt.json"))
            and binding["fitFilesSHA256"] == common.tree_identity(fit) and binding["codeSHA256"] == code_identity()
            and binding["runtime"] == common.runtime_identity() and binding["queryScheduleSHA256"] == sha(canonical(schedule))
            and binding["queryTruthSHA256"] == app["queryTruthSHA256"]
            and binding["sourceCopyLedgerSHA256"] == app["sourceCopyLedgerSHA256"]
            and binding["hasyCopyBindingSHA256"] == sha(canonical(binding["hasyCopyBinding"])), "Native-shape evaluation commitment mismatch")
    models, receipt = load_fitted_models(fit, binding["fitReceiptSHA256"])
    vocabulary = tuple(inputs["vocabulary97"]); validate_fit(receipt, list(vocabulary))
    query_ids = sorted({sid for task in schedule for sid in task["queryIDs"]})
    require(len(query_ids) == 776, "Changed query denominator")
    require(binding["hasyCopyBinding"] == load_copy_binding(hasy_dir, hasy_receipt_sha256, raw, query_ids)
            and receipt["hasyPreparedReceiptSHA256"] == hasy_receipt_sha256
            and receipt["hasySelectedAdaptedRasterHashesSHA256"] == binding["hasyCopyBinding"]["selectedAdaptedRasterHashesSHA256"], "HASY copy commitment changed")
    valid = [sid for sid in query_ids if pixels[sid] is not None]
    rows, stored_fits, banks = [], [], {}
    for arm in ARMS:
        bundle = load_training_feature_bundle(fit, arm, receipt, binding["fitReceiptSHA256"])
        training = np.asarray(bundle["features"], dtype=np.float64); validate_features(training)
        require(training.shape == (6208, 128) and set(bundle["writers"].tolist()) == set(receipt["trainingWriters"])
                and set(bundle["labels"].tolist()) == set(vocabulary), "Anchors require UJI training-only features")
        bank = AnchorBank.from_training(training, tuple(bundle["labels"].tolist()), vocabulary)
        value = {"vocabulary": list(vocabulary), "features": bank.features.tolist(), "trainingWriters": receipt["trainingWriters"],
                 "trainingSamples": 6208, "source": "uji-final-training-only", "reservedFeatureCount": 0,
                 "trainingFeatureSHA256": receipt["trainingFeaturesSHA256"][arm], "trainingFeatureOrderSHA256": receipt["trainingFeatureOrderSHA256"],
                 "weightsSHA256": receipt["weightsSHA256"][arm]}
        banks[arm] = {**value, "sha256": sha(canonical(value))}
        heads = {}
        for task in schedule:  # All16 fixed supports/fits before this arm's query inference.
            key = (task["task"], task["writerID"]); lessons = supports[key]
            features, logits = infer(models[arm], common.image_tensor([s["pixels"] for s in lessons]))
            features, logits = np.asarray(features, dtype=np.float64), np.asarray(logits, dtype=np.float64)
            validate_features(features)
            require(features.shape == (len(lessons), 128) and logits.shape == (len(lessons), 97), "Support encoder shape")
            base = normalized_scores(logits)
            heads[key] = fit_anchored(features, base, tuple(s["label"] for s in lessons), vocabulary, bank)
            stored = [{k: v for k, v in s.items() if k != "pixels"} | {"embedding": features[i].tolist(), "genericLogits": logits[i].tolist(), "baseScores": base[i].tolist()}
                      for i, s in enumerate(lessons)]
            value = {"arm": arm, "task": key[0], "writerID": key[1], "lessons": stored,
                     "anchorSHA256": banks[arm]["sha256"], "regularization": 0.1, "weights": heads[key].weights.tolist()}
            stored_fits.append({**value, "sha256": sha(canonical(value))})
        inferred = {}
        if valid:
            features, logits = infer(models[arm], common.image_tensor([pixels[sid] for sid in valid]))
            features, logits = np.asarray(features, dtype=np.float64), np.asarray(logits, dtype=np.float64)
            validate_features(features)
            require(features.shape == (len(valid), 128) and logits.shape == (len(valid), 97), "Query encoder shape")
            base = normalized_scores(logits)
            inferred = {sid: (features[i], logits[i], base[i]) for i, sid in enumerate(valid)}
        for task in schedule:
            for sid in task["queryIDs"]:
                row = {"arm": arm, "task": task["task"], "writerID": task["writerID"], "sampleID": sid,
                       **{k: raw[sid][k] for k in ("sourceCanonicalData", "sourcePacketSHA256", "rawRasterSHA256")}}
                if sid not in inferred:
                    rows.append({**row, "outcome": "invalid-ink", "failure": "query-raster-no-read", "embedding": None,
                                 "genericLogits": None, "baseScores": None, "genericRanks": [], "personalRanks": []})
                else:
                    feature, logit, base = inferred[sid]
                    rows.append({**row, "outcome": "read", "failure": None, "embedding": feature.tolist(), "genericLogits": logit.tolist(),
                                 "baseScores": base.tolist(), "genericRanks": common.rank(vocabulary, base),
                                 "personalRanks": heads[(task["task"], task["writerID"])].rank(feature, base)})
    packet = {"version": VERSION, "artifactKind": "engineering-only-reused-public-development-v1", "productionEligible": False,
              "naturalChordAccuracyMeasured": False, "newWriterValidationPerformed": False, "liveRecognitionChanged": False,
              "privateProfileChanged": False, "reservedFeatureCount": 0, "reservedInferenceCount": 0, "queryTruthOpened": False,
              "regularization": 0.1, "learner": "personal-untaught-anchor-v1", "commitmentCanonicalData": base64.b64encode(frozen).decode(),
              "commitmentSHA256": sha(frozen), "fitReceiptCanonicalData": base64.b64encode(read(Path(fit) / "fit-receipt.json")).decode(),
              "bindings": binding, "querySchedule": schedule, "vocabulary": list(vocabulary), "anchorBanks": banks, "supports": stored_fits, "rows": rows}
    validate_packet(packet)
    require(read(commitment_path) == frozen and common.tree_identity(fit) == binding["fitFilesSHA256"]
            and code_identity() == binding["codeSHA256"] and common.runtime_identity() == binding["runtime"]
            and sha(read(fixture)) == common.FIXTURE_SHA256 and sha(read(app_report)) == common.APP_REPORT_SHA256
            and sha(read(protocol)) == PROTOCOL_SHA256
            and binding["hasyCopyBinding"] == load_copy_binding(hasy_dir, hasy_receipt_sha256, raw, query_ids), "Inputs changed during native-shape prediction")
    data = canonical(packet); common.exclusive(output, data, (fit, fixture, app_report, protocol, hasy_dir, commitment_path))
    return {"predictionSHA256": sha(data), "rowCount": len(rows), "queryTruthOpened": False}


def validate_packet(packet):
    require(packet["version"] == VERSION and packet["productionEligible"] is False and packet["queryTruthOpened"] is False
            and packet["reservedFeatureCount"] == packet["reservedInferenceCount"] == 0
            and packet["regularization"] == 0.1 and packet["learner"] == "personal-untaught-anchor-v1", "Wrong native-shape packet")
    binding, vocabulary = packet["bindings"], packet["vocabulary"]
    require(binding["version"] == COMMITMENT_VERSION and binding["protocolSHA256"] == PROTOCOL_SHA256
            and binding["fixtureSHA256"] == common.FIXTURE_SHA256 and binding["appReportSHA256"] == common.APP_REPORT_SHA256
            and binding["sourceSHA256"] == common.SOURCE_SHA256 and binding["inferencePerformed"] is False
            and sha(blob(packet["commitmentCanonicalData"])) == packet["commitmentSHA256"]
            and parsed(blob(packet["commitmentCanonicalData"])) == binding
            and len(set(vocabulary)) == len(vocabulary) == 97 and vocabulary == sorted(vocabulary), "Native-shape packet binding mismatch")
    receipt_data = blob(packet["fitReceiptCanonicalData"])
    require(sha(receipt_data) == binding["fitReceiptSHA256"], "Native-shape fit receipt mismatch")
    receipt = parsed(receipt_data); validate_fit(receipt, vocabulary)
    schedule = packet["querySchedule"]
    require(sha(canonical(schedule)) == binding["queryScheduleSHA256"] and len(schedule) == 16
            and {(s["task"], s["writerID"]) for s in schedule} == {(t, w) for t in common.TASKS for w in common.WRITERS}
            and all(len(set(s["queryIDs"])) == len(s["queryIDs"]) == 97 for s in schedule), "Native-shape schedule mismatch")
    require(set(packet["anchorBanks"]) == set(ARMS) and len(packet["supports"]) == 32, "Missing native-shape fits")
    heads = {}
    for arm in ARMS:
        anchor = packet["anchorBanks"][arm]
        require(anchor["sha256"] == sha(canonical({k: v for k, v in anchor.items() if k != "sha256"}))
                and anchor["source"] == "uji-final-training-only" and anchor["trainingSamples"] == 6208 and anchor["reservedFeatureCount"] == 0
                and anchor["trainingWriters"] == receipt["trainingWriters"] and anchor["vocabulary"] == vocabulary
                and anchor["weightsSHA256"] == receipt["weightsSHA256"][arm] == binding["fitFilesSHA256"][receipt["weightFiles"][arm]]
                and anchor["trainingFeatureSHA256"] == receipt["trainingFeaturesSHA256"][arm] == binding["fitFilesSHA256"][receipt["trainingFeatureFiles"][arm]]
                and anchor["trainingFeatureOrderSHA256"] == receipt["trainingFeatureOrderSHA256"], "Wrong UJI-only anchor binding")
        features = np.asarray(anchor["features"]); validate_features(features)
        require(features.shape == (97, 128), "Anchor shape")
        bank = AnchorBank(tuple(vocabulary), features)
        for fit in [s for s in packet["supports"] if s["arm"] == arm]:
            key = (arm, fit["task"], fit["writerID"])
            require(key not in heads and fit["task"] in common.TASKS and fit["writerID"] in common.WRITERS
                    and fit["sha256"] == sha(canonical({k: v for k, v in fit.items() if k != "sha256"}))
                    and fit["anchorSHA256"] == anchor["sha256"] and fit["regularization"] == 0.1
                    and tuple(s["label"] for s in fit["lessons"]) == common.TASKS[fit["task"]], "Support commitment mismatch")
            x, base, logits = (np.asarray([s[k] for s in fit["lessons"]]) for k in ("embedding", "baseScores", "genericLogits"))
            validate_features(x); validate_scores(base, len(x), 97)
            require(x.shape == (len(fit["lessons"]), 128) and np.array_equal(normalized_scores(logits), base), "Stored numeric binding")
            head = fit_anchored(x, base, tuple(s["label"] for s in fit["lessons"]), tuple(vocabulary), bank)
            require(np.array_equal(head.weights, np.asarray(fit["weights"])), "Anchored fit mismatch")
            for stored in fit["lessons"]:
                data = blob(stored["storedCanonicalData"])
                require(sha(data) == stored["storedPacketSHA256"] and sha(common.rasterize(common.decode_canonical_study_packet(data)).pixels) == stored["storedRasterSHA256"], "Stored geometry/pixel mismatch")
            heads[key] = head
    require(set(heads) == {(a, t, w) for a in ARMS for t in common.TASKS for w in common.WRITERS}, "Incomplete fixed support fits")
    expected = {(a, s["task"], s["writerID"], sid) for a in ARMS for s in schedule for sid in s["queryIDs"]}
    require(len(packet["rows"]) == len(expected) == 3104
            and {(r["arm"], r["task"], r["writerID"], r["sampleID"]) for r in packet["rows"]} == expected, "Retained row denominator mismatch")
    copies = binding["hasyCopyBinding"]; raw = {r["sampleID"]: r for r in packet["rows"]}
    require(copies == copy_binding(copies, raw, sorted(raw)) and sha(canonical(copies)) == binding["hasyCopyBindingSHA256"]
            and receipt["hasyPreparedReceiptSHA256"] == copies["receiptSHA256"]
            and receipt["hasySelectedAdaptedRasterHashesSHA256"] == copies["selectedAdaptedRasterHashesSHA256"], "HASY copy/source binding mismatch")
    shared = {}
    for row in packet["rows"]:
        require(common.digest_string(row["sampleID"]), "Opaque query identity required")
        if row["outcome"] == "invalid-ink":
            require(row["embedding"] is row["genericLogits"] is row["baseScores"] is None and row["genericRanks"] == row["personalRanks"] == []
                    and isinstance(row["failure"], str), "Malformed retained invalid row")
        else:
            require(row["outcome"] == "read" and row["failure"] is None, "Unsupported prediction outcome")
            feature, base, logits = (np.asarray(row[k]) for k in ("embedding", "baseScores", "genericLogits"))
            validate_features(feature[None, :]); validate_scores(base[None, :], 1, 97)
            require(feature.shape == (128,) and logits.shape == (97,) and np.array_equal(normalized_scores(logits), base)
                    and row["genericRanks"] == common.rank(vocabulary, base)
                    and row["personalRanks"] == heads[(row["arm"], row["task"], row["writerID"])].rank(feature, base), "Full ranks/numeric mismatch")
        key = (row["arm"], row["sampleID"])
        evidence = canonical({k: row[k] for k in ("writerID", "outcome", "embedding", "genericLogits", "baseScores", "genericRanks", "rawRasterSHA256", "sourcePacketSHA256", "sourceCanonicalData")})
        require(key not in shared or shared[key] == evidence, "Generic inference changed across tasks"); shared[key] = evidence
        require(row["rawRasterSHA256"] == raw[row["sampleID"]]["rawRasterSHA256"], "Raster copy evidence changed across arms")


def join_rows(predictions, truth, copies, hasy_copies):
    answers = {r["sampleID"]: r for r in truth}; exclusions = {r["sampleID"]: r["reasons"] for r in copies}
    extra = {r["sampleID"]: r["reasons"] for r in hasy_copies}
    require(len(answers) == len(truth) and len(exclusions) == len(copies) and len(extra) == len(hasy_copies)
            and set(answers) == set(exclusions) == set(extra), "Truth/copy cohort mismatch")
    exclusions = {sid: list(dict.fromkeys(exclusions[sid] + extra[sid])) for sid in answers}
    grouped = {}
    for row in predictions:
        key = (row["task"], row["sampleID"])
        require(row["arm"] in ARMS and row["arm"] not in grouped.setdefault(key, {}), "Duplicate/wrong predicted arm")
        grouped[key][row["arm"]] = row
    require({sid for _, sid in grouped} == set(answers), "Missing/extra query")
    result = []
    for (task, sid), arms in sorted(grouped.items()):
        answer = answers[sid]
        require(set(arms) == set(ARMS) and task in common.TASKS and len(answer["label"]) == 1
                and all(r["writerID"] == answer["writerID"] for r in arms.values()), "Unpaired/wrong truth identity")
        predictions = {prefix + route: arms[arm][field][0]["label"] if arms[arm]["outcome"] == "read" else None
                       for arm, prefix in zip(ARMS, ("control", "candidate")) for field, route in (("genericRanks", "Generic"), ("personalRanks", "Personal"))}
        result.append({"task": task, "sampleID": sid, "writerID": answer["writerID"], "intended": answer["label"], "exclusions": exclusions[sid],
                       "eligible": not exclusions[sid], "taught": answer["label"] in common.TASKS[task], "appAvailable": answer["label"] in common.CATALOG,
                       "nonASCII35": answer["label"] not in ASCII_LABELS,
                       "predictions": predictions, "outcomes": {a: arms[a]["outcome"] for a in ARMS}, "correct": {k: v == answer["label"] for k, v in predictions.items()}})
    return result


def summarize(rows):
    pairs = (("candidateGenericVsControlGeneric", "candidateGeneric", "controlGeneric"), ("candidatePersonalVsControlPersonal", "candidatePersonal", "controlPersonal"),
             ("candidatePersonalVsOwnGeneric", "candidatePersonal", "candidateGeneric"), ("controlPersonalVsOwnGeneric", "controlPersonal", "controlGeneric"))
    return {"denominator": len(rows), "correct": {k: sum(r["correct"][k] for r in rows) for k in ("controlGeneric", "controlPersonal", "candidateGeneric", "candidatePersonal")},
            "invalid": {a: sum(r["outcomes"][a] != "read" for r in rows) for a in ARMS}, "comparisons": {name: common.paired_summary(rows, c, r) for name, c, r in pairs}}


def fixed_screen(totals, strata, writers):
    c = totals["comparisons"]; stress = strata["nonASCII35"]["comparisons"]
    return (c["candidateGenericVsControlGeneric"]["net"] >= 0, c["candidatePersonalVsControlPersonal"]["net"] > 0,
            strata["untaught"]["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0,
            all(w["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0 for w in writers.values()),
            c["candidatePersonalVsOwnGeneric"]["net"] > 0,
            strata["untaught"]["comparisons"]["candidatePersonalVsOwnGeneric"]["harms"] == 0,
            stress["candidateGenericVsControlGeneric"]["net"] >= 0, stress["candidatePersonalVsControlPersonal"]["net"] >= 0)


def complete_reads(rows):
    return bool(rows) and all(r["outcome"] == "read" for r in rows)

def class_summaries(rows, vocabulary):
    require(len(set(vocabulary)) == len(vocabulary) == 97 and all(r["intended"] in vocabulary for r in rows), "Full class reporting required")
    return {label: summarize([r for r in rows if r["intended"] == label]) for label in vocabulary}

def score(predictions, prediction_sha256, truth_path, copy_path, output):
    data = read(predictions); require(common.digest_string(prediction_sha256) and sha(data) == prediction_sha256, "Prediction SHA mismatch")
    packet = parsed(data); require(data == canonical(packet), "Noncanonical frozen predictions"); validate_packet(packet)  # Before truth.
    truth_data, copy_data = read(truth_path), read(copy_path)
    require(sha(truth_data) == packet["bindings"]["queryTruthSHA256"] and sha(copy_data) == packet["bindings"]["sourceCopyLedgerSHA256"], "Frozen truth/copy hash mismatch")
    truth, copies = parsed(truth_data), parsed(copy_data)
    require(truth["version"] == "public-app-local-transfer-truth-v1" and copies["version"] == "public-app-local-transfer-source-copy-ledger-v1"
            and truth["sourceSHA256"] == copies["sourceSHA256"] == common.SOURCE_SHA256 and truth["fixtureSHA256"] == copies["fixtureSHA256"] == common.FIXTURE_SHA256
            and copies["reservedWriterRasterCount"] == 0 and len(truth["queries"]) == len(copies["queryRows"]) == 776, "Truth/copy source mismatch")
    rows = join_rows(packet["rows"], truth["queries"], copies["queryRows"], packet["bindings"]["hasyCopyBinding"]["queryRows"])
    require(len(rows) == 1552 and sum(not c["reasons"] for c in copies["queryRows"]) == 772, "Raw/no-copy denominator changed")
    tasks, passed = {}, complete_reads(packet["rows"])
    for task in common.TASKS:
        task_rows = [r for r in rows if r["task"] == task]; tasks[task] = {}
        for view, group in (("raw", task_rows), ("noCopy", [r for r in task_rows if r["eligible"]])):
            totals = summarize(group)
            strata = {name: summarize([r for r in group if predicate(r)]) for name, predicate in (("taught", lambda r: r["taught"]), ("untaught", lambda r: not r["taught"]),
                ("appAvailable", lambda r: r["appAvailable"]), ("appUntaught", lambda r: r["appAvailable"] and not r["taught"]), ("nonApp", lambda r: not r["appAvailable"]),
                ("nonASCII35", lambda r: r["nonASCII35"]))}
            writers = {w: summarize([r for r in group if r["writerID"] == w]) for w in common.WRITERS}
            conditions = fixed_screen(totals, strata, writers)
            passed &= all(conditions); tasks[task][view] = {**totals, "strata": strata, "writers": writers,
                "classes": class_summaries(group, packet["vocabulary"]), "fixedFutilityConditions": list(conditions)}
    value = {"version": "personal-native-shape-transfer-evaluation-score-v1", "predictionSHA256": prediction_sha256, "queryTruthSHA256": sha(truth_data),
             "sourceCopyLedgerSHA256": sha(copy_data), "protocolSHA256": PROTOCOL_SHA256, "descriptiveReusedDevelopmentOnly": True,
             "hasyCopyBindingSHA256": packet["bindings"]["hasyCopyBindingSHA256"], "hasyQueryCopies": sum(bool(r["reasons"]) for r in packet["bindings"]["hasyCopyBinding"]["queryRows"]),
             "distinctEligibleQueries": len({r["sampleID"] for r in rows if r["eligible"]}), "finiteCompleteEvidenceValidated": complete_reads(packet["rows"]),
             "freshWriterAccuracyMeasured": False, "naturalChordAccuracyMeasured": False, "productionEligible": False, "reservedWriterInferencePerformed": False,
             "tasks": tasks, "rows": rows, "passesFixedFutilityScreen": passed,
             "disposition": "eligible-for-separate-gate-planning-only" if passed else "reject-fixed-candidate-no-retuning"}
    common.exclusive(output, canonical(value), (predictions, truth_path, copy_path)); return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    for name in ("prepare", "predict"):
        p = sub.add_parser(name)
        for key in ("fit", "fixture", "app-report", "protocol", "output"): p.add_argument("--" + key, type=Path, required=True)
        p.add_argument("--hasy-dir", type=Path, required=True); p.add_argument("--hasy-receipt-sha256", required=True)
        if name == "predict": p.add_argument("--commitment", type=Path, required=True)
    p = sub.add_parser("score")
    for key in ("predictions", "truth", "copy-ledger", "output"): p.add_argument("--" + key, type=Path, required=True)
    p.add_argument("--predictions-sha256", required=True); args = parser.parse_args()
    if args.operation == "prepare": result = prepare(args.fit, args.fixture, args.app_report, args.protocol, args.hasy_dir, args.hasy_receipt_sha256, args.output)
    elif args.operation == "predict": result = predict(args.fit, args.fixture, args.app_report, args.protocol, args.hasy_dir, args.hasy_receipt_sha256, args.commitment, args.output)
    else: result = score(args.predictions, args.predictions_sha256, args.truth, args.copy_ledger, args.output)
    print(canonical({k: v for k, v in result.items() if k not in ("rows", "tasks", "fitFilesSHA256", "codeSHA256")}).decode())


if __name__ == "__main__":
    main()
