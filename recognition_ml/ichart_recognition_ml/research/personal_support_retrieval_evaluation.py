"""Frozen CE-cache evaluation of the fixed support-conditioned retrieval learner.

Only support/query embeddings and generic probabilities enter the learner.
Prior linear ranks remain controls. Truth/copy ledgers are opened only by score.
"""
from __future__ import annotations
import argparse
import base64
from pathlib import Path

import numpy as np
import torch

from . import personal_cross_writer_evaluation as common

VERSION = "personal-support-retrieval-evaluation-v1"
PROTOCOL_SHA256 = "638533ec5bc3a1b29dc2cf9d01b0c683bebb57ba3290e6decbe80ac130675c78"
PRIOR_SHA256 = "6dea2572ced1c8c21fe8523b8fc9d192bb7cfe427a58fb32908e77e664ff5fe9"
ENCODER_SHA256 = "59bd1e9de8c349cef7209663245cb2b5582497fa31d70207502f1e38ded115d3"
ENCODER_ARM = "crossEntropyControl"
CODE_PATHS = common.CODE_PATHS + (
    "recognition_ml/ichart_recognition_ml/research/personal_support_retrieval.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_retrieval_evaluation.py",
    "recognition_ml/tests/test_personal_support_retrieval_evaluation.py",
    "docs/personal-support-retrieval-protocol-2026-10-01.md",
)
canonical, sha, read, parsed, require, blob = common.canonical, common.sha, common.read, common.parsed, common.require, common.blob
SOURCE_FIELDS = ("task", "writerID", "sampleID", "sourceCanonicalData", "sourcePacketSHA256", "rawRasterSHA256",
                 "outcome", "failure", "embedding", "genericLogits", "baseScores", "genericRanks")


def code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: sha(read(root / name, 4 * 1024 * 1024)) for name in CODE_PATHS}


def load_prior(path):
    data = read(path); require(sha(data) == PRIOR_SHA256, "Wrong frozen CE packet")
    packet = parsed(data); common.validate_prediction_packet(packet)
    receipt = parsed(blob(packet["fitReceiptCanonicalData"]))
    require(receipt["weightsSHA256"][ENCODER_ARM] == ENCODER_SHA256, "Wrong frozen CE encoder")
    return packet


def prepare(prior, learner_directory, protocol, output):
    from .personal_support_retrieval import load_fitted_learner
    common.configure(); packet = load_prior(prior)
    require(sha(read(protocol)) == PROTOCOL_SHA256, "Wrong retrieval protocol")
    _, receipt = load_fitted_learner(learner_directory)
    receipt_data = read(Path(learner_directory) / "fit-receipt.json")
    require(parsed(receipt_data) == receipt, "Learner receipt changed")
    value = {"version": "personal-support-retrieval-commitment-v1", "priorPacketSHA256": PRIOR_SHA256,
             "encoderSHA256": ENCODER_SHA256, "protocolSHA256": PROTOCOL_SHA256, "learnerReceiptSHA256": sha(receipt_data),
             "learnerFilesSHA256": common.tree_identity(learner_directory), "codeSHA256": code_identity(), "runtime": common.runtime_identity(),
             "queryScheduleSHA256": packet["bindings"]["queryScheduleSHA256"], "queryTruthSHA256": packet["bindings"]["queryTruthSHA256"],
             "sourceCopyLedgerSHA256": packet["bindings"]["sourceCopyLedgerSHA256"], "predictionPerformed": False}
    common.exclusive(output, canonical(value), (prior, learner_directory, protocol)); return value


def apply_to_task(learner, lessons, rows, vocabulary):
    """The learner receives exactly five tensors, never query labels/ranks/IDs."""
    x = np.asarray([s["embedding"] for s in lessons], dtype=np.float64)
    base = np.asarray([s["baseScores"] for s in lessons], dtype=np.float64)
    common.validate_features(x); common.validate_scores(base, len(x), 97)
    require(x.shape == (len(lessons), 128), "Support shape")
    labels = torch.tensor([vocabulary.index(s["label"]) for s in lessons], dtype=torch.long)
    valid = [r for r in rows if r["outcome"] == "read"]
    inferred = {}
    if valid:
        q = np.asarray([r["embedding"] for r in valid], dtype=np.float64)
        p = np.asarray([r["baseScores"] for r in valid], dtype=np.float64)
        common.validate_features(q); common.validate_scores(p, len(q), 97)
        require(q.shape == (len(q), 128), "Query shape")
        with torch.no_grad():
            result = learner.probabilities(torch.from_numpy(x), torch.from_numpy(base), labels, torch.from_numpy(q), torch.from_numpy(p))
        require(isinstance(result, torch.Tensor) and result.dtype == torch.float64 and tuple(result.shape) == (len(valid), 97), "Retrieval output contract")
        probabilities = result.detach().cpu().numpy(); common.validate_scores(probabilities, len(valid), 97)
        inferred = {r["sampleID"]: probabilities[i] for i, r in enumerate(valid)}
    output = []
    for row in rows:
        require(row["outcome"] in ("read", "invalid-ink"), "Unsupported source outcome")
        probability = inferred.get(row["sampleID"])
        output.append({**{k: row[k] for k in SOURCE_FIELDS}, "linearRanks": row["personalRanks"],
                       "retrievalProbabilities": None if probability is None else probability.tolist(),
                       "retrievalRanks": [] if probability is None else common.rank(vocabulary, probability)})
    return output


def predict(prior, learner_directory, protocol, commitment, output):
    from .personal_support_retrieval import load_fitted_learner
    common.configure(); frozen = read(commitment); binding = parsed(frozen); prior_packet = load_prior(prior)
    require(binding["version"] == "personal-support-retrieval-commitment-v1" and binding["predictionPerformed"] is False
            and binding["priorPacketSHA256"] == PRIOR_SHA256 and binding["encoderSHA256"] == ENCODER_SHA256
            and binding["protocolSHA256"] == sha(read(protocol)) == PROTOCOL_SHA256
            and binding["learnerReceiptSHA256"] == sha(read(Path(learner_directory) / "fit-receipt.json"))
            and binding["learnerFilesSHA256"] == common.tree_identity(learner_directory) and binding["codeSHA256"] == code_identity()
            and binding["runtime"] == common.runtime_identity(), "Retrieval commitment mismatch")
    learner, receipt = load_fitted_learner(learner_directory)
    before = {k: v.clone() for k, v in learner.state_dict().items()}
    supports = [s for s in prior_packet["supports"] if s["arm"] == ENCODER_ARM]
    source_rows = [r for r in prior_packet["rows"] if r["arm"] == ENCODER_ARM]
    rows = []
    for support in supports:
        queries = [r for r in source_rows if r["task"] == support["task"] and r["writerID"] == support["writerID"]]
        rows.extend(apply_to_task(learner, support["lessons"], queries, prior_packet["vocabulary"]))
    packet = {"version": VERSION, "artifactKind": "engineering-only-reused-public-development-v1", "productionEligible": False,
              "naturalChordAccuracyMeasured": False, "freshWriterValidationPerformed": False, "liveRecognitionChanged": False,
              "reservedWriterInferencePerformed": False, "encoderInferencePerformed": False, "queryTruthOpened": False,
              "commitmentCanonicalData": base64.b64encode(frozen).decode(), "commitmentSHA256": sha(frozen), "bindings": binding,
              "learnerReceiptCanonicalData": base64.b64encode(read(Path(learner_directory) / "fit-receipt.json")).decode(),
              "vocabulary": prior_packet["vocabulary"], "supports": supports, "rows": rows}
    validate_packet(packet, prior_packet)
    require(all(torch.equal(v, before[k]) for k, v in learner.state_dict().items()) and receipt == parsed(blob(packet["learnerReceiptCanonicalData"]))
            and read(commitment) == frozen and common.tree_identity(learner_directory) == binding["learnerFilesSHA256"]
            and code_identity() == binding["codeSHA256"] and common.runtime_identity() == binding["runtime"]
            and sha(read(prior)) == PRIOR_SHA256 and sha(read(protocol)) == PROTOCOL_SHA256, "Retrieval inputs/model changed")
    data = canonical(packet); common.exclusive(output, data, (prior, learner_directory, protocol, commitment))
    return {"predictionSHA256": sha(data), "rowCount": len(rows), "queryTruthOpened": False}


def validate_packet(packet, prior):
    require(packet["version"] == VERSION and packet["productionEligible"] is False and packet["queryTruthOpened"] is False
            and packet["reservedWriterInferencePerformed"] is False and packet["encoderInferencePerformed"] is False, "Wrong retrieval packet")
    binding = packet["bindings"]
    require(binding["version"] == "personal-support-retrieval-commitment-v1" and binding["predictionPerformed"] is False
            and binding["priorPacketSHA256"] == PRIOR_SHA256 and binding["encoderSHA256"] == ENCODER_SHA256 and binding["protocolSHA256"] == PROTOCOL_SHA256
            and sha(blob(packet["commitmentCanonicalData"])) == packet["commitmentSHA256"] and parsed(blob(packet["commitmentCanonicalData"])) == binding
            and all(binding[k] == prior["bindings"][k] for k in ("queryScheduleSHA256", "queryTruthSHA256", "sourceCopyLedgerSHA256"))
            and packet["vocabulary"] == prior["vocabulary"], "Retrieval binding mismatch")
    receipt_data = blob(packet["learnerReceiptCanonicalData"]); receipt = parsed(receipt_data)
    require(sha(receipt_data) == binding["learnerReceiptSHA256"] and receipt["version"] == "personal-support-retrieval-v1"
            and receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["productionEligible"] is False and receipt["reservedWritersEvaluated"] is False
            and receipt["weightsSHA256"] == binding["learnerFilesSHA256"]["weights.pt"], "Learner receipt binding mismatch")
    require(packet["supports"] == [s for s in prior["supports"] if s["arm"] == ENCODER_ARM], "Stored support changed")
    source = {(r["task"], r["sampleID"]): r for r in prior["rows"] if r["arm"] == ENCODER_ARM}
    require(len(packet["rows"]) == len(source) == 1552 and {(r["task"], r["sampleID"]) for r in packet["rows"]} == set(source), "Retrieval query cohort mismatch")
    for row in packet["rows"]:
        original = source[(row["task"], row["sampleID"])]
        require(all(row[k] == original[k] for k in SOURCE_FIELDS) and row["linearRanks"] == original["personalRanks"], "Frozen generic/linear/source changed")
        if row["outcome"] == "invalid-ink":
            require(row["retrievalProbabilities"] is None and row["retrievalRanks"] == [], "Invalid row deleted/rescued")
        else:
            probability = np.asarray(row["retrievalProbabilities"], dtype=np.float64)
            common.validate_scores(probability[None, :], 1, 97)
            require(row["retrievalRanks"] == common.rank(packet["vocabulary"], probability), "Incomplete/nonfinite retrieval ranks")


def join_rows(predictions, truth, copies):
    answers = {r["sampleID"]: r for r in truth}; exclusions = {r["sampleID"]: r["reasons"] for r in copies}
    require(len(answers) == len(truth) and len(exclusions) == len(copies) and set(answers) == set(exclusions), "Truth/copy cohort mismatch")
    keys = {(r["task"], r["sampleID"]) for r in predictions}
    require(len(keys) == len(predictions) and keys == {(t, sid) for t in common.TASKS for sid in answers}, "Query task cohort mismatch")
    result = []
    for row in sorted(predictions, key=lambda r: (r["task"], r["sampleID"])):
        answer = answers[row["sampleID"]]
        require(row["writerID"] == answer["writerID"] and isinstance(answer["label"], str) and len(answer["label"]) == 1, "Truth identity mismatch")
        predictions = {name: row[field][0]["label"] if row["outcome"] == "read" else None for name, field in
                       (("generic", "genericRanks"), ("linear", "linearRanks"), ("retrieval", "retrievalRanks"))}
        result.append({"task": row["task"], "sampleID": row["sampleID"], "writerID": row["writerID"], "intended": answer["label"],
                       "outcome": row["outcome"], "eligible": not exclusions[row["sampleID"]], "exclusions": exclusions[row["sampleID"]],
                       "taught": answer["label"] in common.TASKS[row["task"]], "predictions": predictions,
                       "correct": {k: v == answer["label"] for k, v in predictions.items()}})
    return result


def summarize(rows):
    return {"denominator": len(rows), "invalid": sum(r["outcome"] != "read" for r in rows),
            "correct": {k: sum(r["correct"][k] for r in rows) for k in ("generic", "linear", "retrieval")},
            "comparisons": {name: common.paired_summary(rows, c, r) for name, c, r in
                            (("retrievalVsLinear", "retrieval", "linear"), ("retrievalVsGeneric", "retrieval", "generic"), ("linearVsGeneric", "linear", "generic"))}}


def score(predictions, prediction_sha256, prior, truth_path, copy_path, output):
    data = read(predictions); require(common.digest_string(prediction_sha256) and sha(data) == prediction_sha256, "Prediction SHA mismatch")
    packet = parsed(data); validate_packet(packet, load_prior(prior))  # Entire frozen prediction/cache validated before truth.
    truth_data, copy_data = read(truth_path), read(copy_path)
    require(sha(truth_data) == packet["bindings"]["queryTruthSHA256"] and sha(copy_data) == packet["bindings"]["sourceCopyLedgerSHA256"], "Truth/copy hash mismatch")
    truth, copies = parsed(truth_data), parsed(copy_data)
    require(truth["version"] == "public-app-local-transfer-truth-v1" and copies["version"] == "public-app-local-transfer-source-copy-ledger-v1"
            and truth["sourceSHA256"] == copies["sourceSHA256"] == common.SOURCE_SHA256 and truth["fixtureSHA256"] == copies["fixtureSHA256"] == common.FIXTURE_SHA256
            and copies["reservedWriterRasterCount"] == 0 and len(truth["queries"]) == len(copies["queryRows"]) == 776, "Truth/copy source mismatch")
    rows = join_rows(packet["rows"], truth["queries"], copies["queryRows"])
    require(len(rows) == 1552 and sum(not c["reasons"] for c in copies["queryRows"]) == 772, "Fixed raw/no-copy denominator changed")
    tasks, passed = {}, True
    for task in common.TASKS:
        task_rows = [r for r in rows if r["task"] == task]; tasks[task] = {}
        for view, group in (("raw", task_rows), ("noCopy", [r for r in task_rows if r["eligible"]])):
            totals = summarize(group); strata = {name: summarize([r for r in group if r["taught"] == taught]) for name, taught in (("taught", True), ("untaught", False))}
            writers = {w: summarize([r for r in group if r["writerID"] == w]) for w in common.WRITERS}
            conditions = (totals["comparisons"]["retrievalVsLinear"]["net"] > 0, totals["comparisons"]["retrievalVsGeneric"]["net"] > 0,
                          strata["untaught"]["comparisons"]["retrievalVsLinear"]["net"] >= 0,
                          all(w["comparisons"]["retrievalVsLinear"]["net"] >= 0 for w in writers.values()), strata["untaught"]["comparisons"]["retrievalVsGeneric"]["harms"] == 0)
            passed &= all(conditions); tasks[task][view] = {**totals, "strata": strata, "writers": writers, "fixedScreenConditions": list(conditions)}
    value = {"version": "personal-support-retrieval-score-v1", "predictionSHA256": prediction_sha256, "priorPacketSHA256": PRIOR_SHA256,
             "protocolSHA256": PROTOCOL_SHA256, "queryTruthSHA256": sha(truth_data), "sourceCopyLedgerSHA256": sha(copy_data),
             "descriptiveReusedDevelopmentOnly": True, "productionEligible": False, "freshWriterAccuracyMeasured": False,
             "naturalChordAccuracyMeasured": False, "reservedWriterInferencePerformed": False, "tasks": tasks, "rows": rows,
             "passesFixedScreen": passed, "disposition": "eligible-for-separate-fresh-writer-runtime-planning-only" if passed else "reject-fixed-candidate-no-retuning"}
    common.exclusive(output, canonical(value), (predictions, prior, truth_path, copy_path)); return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    for name in ("prepare", "predict"):
        p = sub.add_parser(name)
        for key in ("prior", "learner-directory", "protocol", "output"): p.add_argument("--" + key, type=Path, required=True)
        if name == "predict": p.add_argument("--commitment", type=Path, required=True)
    p = sub.add_parser("score")
    for key in ("predictions", "prior", "truth", "copy-ledger", "output"): p.add_argument("--" + key, type=Path, required=True)
    p.add_argument("--predictions-sha256", required=True); a = parser.parse_args()
    if a.operation == "prepare": result = prepare(a.prior, a.learner_directory, a.protocol, a.output)
    elif a.operation == "predict": result = predict(a.prior, a.learner_directory, a.protocol, a.commitment, a.output)
    else: result = score(a.predictions, a.predictions_sha256, a.prior, a.truth, a.copy_ledger, a.output)
    print(canonical({k: v for k, v in result.items() if k not in ("rows", "tasks", "learnerFilesSHA256", "codeSHA256")}).decode())


if __name__ == "__main__":
    main()
