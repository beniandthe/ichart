"""Separate frozen, reused-public-development diagnostic for broad pretraining.

No query truth is opened by preparation/prediction. NIST never supplies personal
anchors: these are recomputed only from the final encoder's 6,208 UJI training
embeddings. The exact prior Swift stored-support geometry/pixels are reused.
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

ARMS = ("ujiReplayPretrain", "nistBroadPretrain")
VERSION = "personal-broad-transfer-evaluation-predictions-v1"
COMMITMENT_VERSION = "personal-broad-transfer-evaluation-commitment-v1"
PROTOCOL_SHA256 = "a03afefbe741eed7bb8e0eea4ad96bd8bcfe4f72e159b7b9e12bcdd3ea8d341d"
PRETRAINING_LABELS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
CODE_PATHS = common.CODE_PATHS + (
    "recognition_ml/ichart_recognition_ml/research/personal_broad_transfer.py",
    "recognition_ml/ichart_recognition_ml/research/personal_broad_transfer_evaluation.py",
    "recognition_ml/tests/test_personal_broad_transfer_evaluation.py",
    "docs/personal-broad-transfer-protocol-2026-10-01.md",
)
canonical, sha, require, read, parsed, blob = (common.canonical, common.sha, common.require,
                                            common.read, common.parsed, common.blob)


def code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: sha(read(root / name, 4 * 1024 * 1024)) for name in CODE_PATHS}


def validate_fit(receipt, vocabulary):
    require(tuple(receipt["arms"]) == ARMS and receipt["sourceSHA256"] == common.SOURCE_SHA256
            and tuple(receipt["developmentWriters"]) == common.WRITERS and len(receipt["trainingWriters"]) == 32
            and len(set(receipt["trainingWriters"])) == 32 and all(w.startswith("trn_") for w in receipt["trainingWriters"])
            and len(set(receipt["reservedWriters"])) == 20
            and not set(receipt["trainingWriters"]) & set(common.WRITERS)
            and not set(receipt["reservedWriters"]) & (set(common.WRITERS) | set(receipt["trainingWriters"]))
            and receipt["vocabulary"] == vocabulary
            and receipt["protocolEnvelope"]["markdownProtocolSHA256"] == PROTOCOL_SHA256, "Broad fit binding mismatch")


def prepare(fit, fixture, app_report, protocol, output):
    from .personal_broad_transfer import load_fitted_models
    common.configure()
    inputs, app, _, _, _ = common.load_projection(fixture, app_report)
    require(sha(read(protocol)) == PROTOCOL_SHA256, "Wrong broad protocol")
    _, receipt = load_fitted_models(fit)
    validate_fit(receipt, inputs["vocabulary97"])
    value = {"version": COMMITMENT_VERSION, "sourceSHA256": common.SOURCE_SHA256,
             "fixtureSHA256": common.FIXTURE_SHA256, "appReportSHA256": common.APP_REPORT_SHA256,
             "protocolSHA256": PROTOCOL_SHA256, "fitReceiptSHA256": sha(read(Path(fit) / "fit-receipt.json")),
             "fitFilesSHA256": common.tree_identity(fit), "codeSHA256": code_identity(), "runtime": common.runtime_identity(),
             "queryScheduleSHA256": sha(canonical(common.query_schedule(inputs))), "queryTruthSHA256": app["queryTruthSHA256"],
             "sourceCopyLedgerSHA256": app["sourceCopyLedgerSHA256"], "inferencePerformed": False}
    common.exclusive(output, canonical(value), (fit, fixture, app_report, protocol))
    return value


def predict(fit, fixture, app_report, protocol, commitment_path, output):
    from .personal_broad_transfer import load_fitted_models, load_training_feature_bundle
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
            and binding["sourceCopyLedgerSHA256"] == app["sourceCopyLedgerSHA256"], "Broad evaluation commitment mismatch")
    models, receipt = load_fitted_models(fit)
    vocabulary = tuple(inputs["vocabulary97"]); validate_fit(receipt, list(vocabulary))
    query_ids = sorted({sid for task in schedule for sid in task["queryIDs"]})
    require(len(query_ids) == 776, "Changed query denominator")
    valid = [sid for sid in query_ids if pixels[sid] is not None]
    rows, stored_fits, banks = [], [], {}
    for arm in ARMS:
        bundle = load_training_feature_bundle(fit, arm, receipt)
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
            and sha(read(protocol)) == PROTOCOL_SHA256, "Inputs changed during broad prediction")
    data = canonical(packet); common.exclusive(output, data, (fit, fixture, app_report, protocol, commitment_path))
    return {"predictionSHA256": sha(data), "rowCount": len(rows), "queryTruthOpened": False}


def validate_packet(packet):
    require(packet["version"] == VERSION and packet["productionEligible"] is False and packet["queryTruthOpened"] is False
            and packet["reservedFeatureCount"] == packet["reservedInferenceCount"] == 0
            and packet["regularization"] == 0.1 and packet["learner"] == "personal-untaught-anchor-v1", "Wrong broad packet")
    binding, vocabulary = packet["bindings"], packet["vocabulary"]
    require(binding["version"] == COMMITMENT_VERSION and binding["protocolSHA256"] == PROTOCOL_SHA256
            and binding["fixtureSHA256"] == common.FIXTURE_SHA256 and binding["appReportSHA256"] == common.APP_REPORT_SHA256
            and binding["sourceSHA256"] == common.SOURCE_SHA256 and binding["inferencePerformed"] is False
            and sha(blob(packet["commitmentCanonicalData"])) == packet["commitmentSHA256"]
            and parsed(blob(packet["commitmentCanonicalData"])) == binding
            and len(set(vocabulary)) == len(vocabulary) == 97 and vocabulary == sorted(vocabulary), "Broad packet binding mismatch")
    receipt_data = blob(packet["fitReceiptCanonicalData"])
    require(sha(receipt_data) == binding["fitReceiptSHA256"], "Broad fit receipt mismatch")
    receipt = parsed(receipt_data); validate_fit(receipt, vocabulary)
    schedule = packet["querySchedule"]
    require(sha(canonical(schedule)) == binding["queryScheduleSHA256"] and len(schedule) == 16
            and {(s["task"], s["writerID"]) for s in schedule} == {(t, w) for t in common.TASKS for w in common.WRITERS}
            and all(len(set(s["queryIDs"])) == len(s["queryIDs"]) == 97 for s in schedule), "Broad schedule mismatch")
    require(set(packet["anchorBanks"]) == set(ARMS) and len(packet["supports"]) == 32, "Missing broad fits")
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
        evidence = canonical({k: row[k] for k in ("writerID", "outcome", "embedding", "genericLogits", "baseScores", "genericRanks")})
        require(key not in shared or shared[key] == evidence, "Generic inference changed across tasks"); shared[key] = evidence


def join_rows(predictions, truth, copies):
    answers = {r["sampleID"]: r for r in truth}; exclusions = {r["sampleID"]: r["reasons"] for r in copies}
    require(len(answers) == len(truth) and len(exclusions) == len(copies) and set(answers) == set(exclusions), "Truth/copy cohort mismatch")
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
                       "pretrainingAbsent35": answer["label"] not in PRETRAINING_LABELS,
                       "predictions": predictions, "outcomes": {a: arms[a]["outcome"] for a in ARMS}, "correct": {k: v == answer["label"] for k, v in predictions.items()}})
    return result


def summarize(rows):
    pairs = (("candidateGenericVsControlGeneric", "candidateGeneric", "controlGeneric"), ("candidatePersonalVsControlPersonal", "candidatePersonal", "controlPersonal"),
             ("candidatePersonalVsOwnGeneric", "candidatePersonal", "candidateGeneric"), ("controlPersonalVsOwnGeneric", "controlPersonal", "controlGeneric"))
    return {"denominator": len(rows), "correct": {k: sum(r["correct"][k] for r in rows) for k in ("controlGeneric", "controlPersonal", "candidateGeneric", "candidatePersonal")},
            "invalid": {a: sum(r["outcomes"][a] != "read" for r in rows) for a in ARMS}, "comparisons": {name: common.paired_summary(rows, c, r) for name, c, r in pairs}}


def score(predictions, prediction_sha256, truth_path, copy_path, output):
    data = read(predictions); require(common.digest_string(prediction_sha256) and sha(data) == prediction_sha256, "Prediction SHA mismatch")
    packet = parsed(data); validate_packet(packet)  # Immutable predictions validated before the first truth read.
    truth_data, copy_data = read(truth_path), read(copy_path)
    require(sha(truth_data) == packet["bindings"]["queryTruthSHA256"] and sha(copy_data) == packet["bindings"]["sourceCopyLedgerSHA256"], "Frozen truth/copy hash mismatch")
    truth, copies = parsed(truth_data), parsed(copy_data)
    require(truth["version"] == "public-app-local-transfer-truth-v1" and copies["version"] == "public-app-local-transfer-source-copy-ledger-v1"
            and truth["sourceSHA256"] == copies["sourceSHA256"] == common.SOURCE_SHA256 and truth["fixtureSHA256"] == copies["fixtureSHA256"] == common.FIXTURE_SHA256
            and copies["reservedWriterRasterCount"] == 0 and len(truth["queries"]) == len(copies["queryRows"]) == 776, "Truth/copy source mismatch")
    rows = join_rows(packet["rows"], truth["queries"], copies["queryRows"])
    require(len(rows) == 1552 and sum(not c["reasons"] for c in copies["queryRows"]) == 772, "Raw/no-copy denominator changed")
    tasks, passed = {}, True
    for task in common.TASKS:
        task_rows = [r for r in rows if r["task"] == task]; tasks[task] = {}
        for view, group in (("raw", task_rows), ("noCopy", [r for r in task_rows if r["eligible"]])):
            totals = summarize(group)
            strata = {name: summarize([r for r in group if predicate(r)]) for name, predicate in (("taught", lambda r: r["taught"]), ("untaught", lambda r: not r["taught"]),
                ("appAvailable", lambda r: r["appAvailable"]), ("appUntaught", lambda r: r["appAvailable"] and not r["taught"]), ("nonApp", lambda r: not r["appAvailable"]),
                ("pretrainingAbsent35", lambda r: r["pretrainingAbsent35"]))}
            writers = {w: summarize([r for r in group if r["writerID"] == w]) for w in common.WRITERS}; c = totals["comparisons"]
            conditions = (c["candidateGenericVsControlGeneric"]["net"] >= 0, c["candidatePersonalVsControlPersonal"]["net"] > 0,
                          strata["untaught"]["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0,
                          all(w["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0 for w in writers.values()),
                          c["candidatePersonalVsOwnGeneric"]["net"] > 0, strata["untaught"]["comparisons"]["candidatePersonalVsOwnGeneric"]["harms"] == 0,
                          strata["pretrainingAbsent35"]["comparisons"]["candidateGenericVsControlGeneric"]["net"] >= 0,
                          strata["pretrainingAbsent35"]["comparisons"]["candidatePersonalVsControlPersonal"]["net"] >= 0)
            passed &= all(conditions); tasks[task][view] = {**totals, "strata": strata, "writers": writers, "fixedFutilityConditions": list(conditions)}
    value = {"version": "personal-broad-transfer-evaluation-score-v1", "predictionSHA256": prediction_sha256, "queryTruthSHA256": sha(truth_data),
             "sourceCopyLedgerSHA256": sha(copy_data), "protocolSHA256": PROTOCOL_SHA256, "descriptiveReusedDevelopmentOnly": True,
             "freshWriterAccuracyMeasured": False, "naturalChordAccuracyMeasured": False, "productionEligible": False, "reservedWriterInferencePerformed": False,
             "tasks": tasks, "rows": rows, "passesFixedFutilityScreen": passed,
             "disposition": "eligible-for-separate-gate-planning-only" if passed else "reject-fixed-candidate-no-retuning"}
    common.exclusive(output, canonical(value), (predictions, truth_path, copy_path)); return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    for name in ("prepare", "predict"):
        p = sub.add_parser(name)
        for key in ("fit", "fixture", "app-report", "protocol", "output"): p.add_argument("--" + key, type=Path, required=True)
        if name == "predict": p.add_argument("--commitment", type=Path, required=True)
    p = sub.add_parser("score")
    for key in ("predictions", "truth", "copy-ledger", "output"): p.add_argument("--" + key, type=Path, required=True)
    p.add_argument("--predictions-sha256", required=True); args = parser.parse_args()
    if args.operation == "prepare": result = prepare(args.fit, args.fixture, args.app_report, args.protocol, args.output)
    elif args.operation == "predict": result = predict(args.fit, args.fixture, args.app_report, args.protocol, args.commitment, args.output)
    else: result = score(args.predictions, args.predictions_sha256, args.truth, args.copy_ledger, args.output)
    print(canonical({k: v for k, v in result.items() if k not in ("rows", "tasks", "fitFilesSHA256", "codeSHA256")}).decode())


if __name__ == "__main__":
    main()
