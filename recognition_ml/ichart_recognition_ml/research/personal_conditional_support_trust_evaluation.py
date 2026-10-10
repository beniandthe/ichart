"""Frozen training-writer internal-reuse evaluation; never live recognition.

Preparation uses source labels only to establish the grid and explicit lessons.
Prediction opens no query-label metadata and gives the candidate five tensors.
Scoring joins labels only after validating the serialized prediction SHA.
"""
from __future__ import annotations

import argparse
import base64
import io
from pathlib import Path

import numpy as np
import torch

from . import personal_cross_writer_evaluation as common

VERSION = "personal-conditional-support-trust-predictions-v1"
COMMITMENT_VERSION = "personal-conditional-support-trust-commitment-v1"
PROTOCOL = "docs/personal-conditional-support-trust-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "aef2c1db98bc12bce63575f11b0fd7930306c18d4d3b1350880cbeec09647680"
ROLE_SHA256 = "47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa"
TASKS = ("K10", "K21")
canonical, sha, read, parsed, require = common.canonical, common.sha, common.read, common.parsed, common.require


def code_identity():
    from . import personal_conditional_support_trust as learner
    root = Path(__file__).resolve().parents[3]
    paths = ("recognition_ml/ichart_recognition_ml/research/personal_conditional_support_trust_evaluation.py",
             "recognition_ml/tests/test_personal_conditional_support_trust_evaluation.py",
             "recognition_ml/ichart_recognition_ml/research/personal_cross_writer_evaluation.py",
             "recognition_ml/ichart_recognition_ml/research/personal_residual.py", PROTOCOL)
    result = {**learner.code_identity(), **{p: sha(read(root / p)) for p in paths}}
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Conditional trust protocol changed")
    return result


def source_plan(rows, vocabulary, roles):
    from .personal_conditional_support_trust import episode_plan
    plans = episode_plan(rows, vocabulary, roles["internalValidationWriters"], epochs=1, seed=42)
    for number, plan in enumerate(plans):
        plan.update(episodeIndex=number, role="internalValidation", task=f'K{len(plan["support"])}',
                    supportLabels=[rows[i]["label"] for i in plan["support"]],
                    unavailableSetup=[{"index": i, "failure": rows[i]["storedFailure"]}
                        for i in roles["sourceIndices"]["internalValidation"]
                        if rows[i]["writer"] == plan["writer"] and rows[i]["session"] == plan["session"]
                        and rows[i]["storedFailure"] is not None])
    validate_plan(plans, vocabulary, roles)
    return plans


def validate_plan(plans, vocabulary, roles):
    writers, indices = roles["internalValidationWriters"], roles["sourceIndices"]["internalValidation"]
    require(len(writers) == len(set(writers)) == 8 and len(indices) == len(set(indices)) == 1552
            and all(type(i) is int and 0 <= i < 6208 for i in indices)
            and not set(writers) & (set(roles["metaFitWriters"]) | set(roles["encoderFitWriters"]))
            and roles["generator"] == "fitA" and roles["freshValidation"] is False
            and len(vocabulary) == 97 and vocabulary == sorted(set(vocabulary)), "Invalid internal writer roles")
    require(len(plans) == 32 and {(p["writer"], p["session"], p["task"]) for p in plans}
            == {(w, s, k) for w in writers for s in (1, 2) for k in TASKS}, "Incomplete validation directions")
    scheduled = []
    reasons = ("generic-fit-raw-raster-copy", "generic-fit-normalized-trajectory-copy",
               "support-raster-copy", "support-normalized-trajectory-copy")
    for number, p in enumerate(plans):
        support, queries, excluded = p["support"], p["queries"], p["exclusions"]
        all_queries = p["scheduledQueries"]
        require(p["episodeIndex"] == number and p["role"] == "internalValidation" and p["epoch"] == 1
                and p["querySession"] == 3 - p["session"] and len(support) == int(p["task"][1:])
                and len(set(support)) == len(set(p["supportLabels"])) == len(support)
                and all(label in vocabulary for label in p["supportLabels"])
                and len(all_queries) == len(set(all_queries)) == 97 and not set(support) & set(all_queries)
                and len(queries) == len(set(queries)) and len(excluded) == len({e["index"] for e in excluded})
                and not set(queries) & {e["index"] for e in excluded}
                and set(queries) | {e["index"] for e in excluded} == set(all_queries)
                and all(type(i) is int and i in indices for i in support + all_queries)
                and all(e["reasons"] and e["reasons"] == [r for r in reasons if r in e["reasons"]] for e in excluded)
                and all(type(e["index"]) is int and e["index"] in indices and e["index"] not in support
                        and isinstance(e["failure"], str) for e in p["unavailableSetup"]), "Malformed source-only episode")
        scheduled.extend(all_queries)
    require(len(scheduled) == 3104 and set(scheduled) == set(indices)
            and all(scheduled.count(i) == 2 for i in indices), "Scheduled source coverage changed")


def validate_binding(binding, crossfit, roles, learner_directory, protocol):
    from .personal_conditional_support_trust import input_identity
    require(binding["version"] == COMMITMENT_VERSION and binding["predictionPerformed"] is False
            and binding["protocolSHA256"] == sha(read(protocol)) == PROTOCOL_SHA256
            and binding["roleManifestSHA256"] == sha(read(roles)) == ROLE_SHA256
            and binding["roleManifest"] == parsed(read(roles))
            and binding["parentBinding"] == input_identity(crossfit)
            and binding["learnerFilesSHA256"] == common.tree_identity(learner_directory)
            and binding["learnerReceiptSHA256"] == sha(read(Path(learner_directory) / "fit-receipt.json"))
            and binding["codeSHA256"] == code_identity() and binding["runtime"] == common.runtime_identity()
            and binding["sourcePlanSHA256"] == sha(canonical(binding["sourcePlan"])), "Frozen evaluation binding changed")
    receipt = parsed(read(Path(learner_directory) / "fit-receipt.json"))
    require(receipt["version"] == "personal-conditional-support-trust-v1"
            and receipt["protocolSHA256"] == PROTOCOL_SHA256 and receipt["parentBinding"] == binding["parentBinding"]
            and receipt["roleManifestSHA256"] == ROLE_SHA256 and receipt["roleManifest"] == binding["roleManifest"]
            and receipt["vocabulary"] == binding["vocabulary"]
            and receipt["weightsSHA256"] == binding["learnerFilesSHA256"]["weights.pt"]
            and all(receipt[key] is False for key in ("productionEligible", "freshValidation", "privateInkUsed", "internalValidationUsedDuringFit")),
            "Learner receipt/roles changed")
    validate_plan(binding["sourcePlan"], binding["vocabulary"], binding["roleManifest"])


def prepare(crossfit, roles, learner_directory, protocol, output):
    from .personal_conditional_support_trust import input_identity, load_parent, load_fitted_learner
    common.configure()
    parent = input_identity(crossfit)
    _, rows, receipt, manifest = load_parent(crossfit, roles)
    _, fitted = load_fitted_learner(learner_directory)
    require(fitted["parentBinding"] == parent and fitted["roleManifest"] == manifest, "Wrong fitted learner parents")
    plans = source_plan(rows, receipt["vocabulary"], manifest)
    value = {"version": COMMITMENT_VERSION, "predictionPerformed": False, "protocolSHA256": PROTOCOL_SHA256,
             "parentBinding": parent, "roleManifestSHA256": sha(read(roles)), "roleManifest": manifest,
             "learnerReceiptSHA256": sha(read(Path(learner_directory) / "fit-receipt.json")),
             "learnerFilesSHA256": common.tree_identity(learner_directory), "codeSHA256": code_identity(),
             "runtime": common.runtime_identity(), "vocabulary": receipt["vocabulary"],
             "sourcePlan": plans, "sourcePlanSHA256": sha(canonical(plans))}
    validate_binding(value, crossfit, roles, learner_directory, protocol)
    common.exclusive(output, canonical(value), (crossfit, roles, learner_directory, protocol))
    return value


def feature_arrays(crossfit):
    # Deliberately no metadata/labels read in prediction.
    with np.load(io.BytesIO(read(Path(crossfit) / "features.npz")), allow_pickle=False) as bundle:
        arrays = {k: np.array(bundle[k], copy=True) for k in bundle.files}
    return arrays


def apply_episode(learner, arrays, plan, vocabulary):
    """Only explicit support labels enter the five-tensor interface."""
    si, qi = plan["support"], plan["scheduledQueries"]
    sf, qf = (np.asarray(arrays[k][indices], dtype=np.float64) for k, indices in
              (("stored_features", si), ("raw_features", qi)))
    common.validate_features(sf); common.validate_features(qf)
    require(sf.shape == (len(si), 128) and qf.shape == (len(qi), 128), "Feature dimensions changed")
    sp = torch.from_numpy(np.asarray(arrays["stored_logits"][si], dtype=np.float64)).softmax(1)
    qp = torch.from_numpy(np.asarray(arrays["raw_logits"][qi], dtype=np.float64)).softmax(1)
    common.validate_scores(sp.numpy(), len(si), 97); common.validate_scores(qp.numpy(), len(qi), 97)
    sl = torch.tensor([vocabulary.index(label) for label in plan["supportLabels"]], dtype=torch.long)
    failure, result = None, None
    try:
        with torch.inference_mode():
            result = learner.probabilities(torch.from_numpy(sf), sp, sl, torch.from_numpy(qf), qp)
        require(isinstance(result, torch.Tensor) and result.dtype == torch.float64 and result.device.type == "cpu"
                and result.shape == qp.shape, "Candidate output dimensions/dtype changed")
    except (ValueError, RuntimeError) as error:
        failure = f"{type(error).__name__}: {str(error)[:240]}"
    rows = []
    for position, index in enumerate(qi):
        probability, error = None, failure
        if error is None:
            try:
                probability = result[position].detach().numpy()
                common.validate_scores(probability[None, :], 1, 97)
            except ValueError as invalid:
                probability, error = None, f"invalid-output: {invalid}"
        rows.append({"sourceIndex": index, "genericProbabilities": qp[position].tolist(),
                     "candidateProbabilities": None if probability is None else probability.tolist(),
                     "outcome": "read" if probability is not None else "invalid", "failure": error})
    return {"episodeIndex": plan["episodeIndex"], "supportFeatures": sf.tolist(),
            "supportProbabilities": sp.tolist(), "supportLabelIndices": sl.tolist(), "rows": rows}


def validate_packet(packet):
    require(packet["version"] == VERSION and packet["queryTruthOpened"] is False
            and all(packet[k] is False for k in ("productionEligible", "freshValidation", "encoderInferencePerformed",
                "developmentWritersEvaluated", "reservedWritersEvaluated", "privateInkUsed", "appOrProfileChanged")), "Wrong evidence boundary")
    binding = packet["bindings"]
    raw = common.blob(packet["commitmentCanonicalData"])
    require(raw == canonical(binding) and sha(raw) == packet["commitmentSHA256"], "Prediction commitment mismatch")
    validate_plan(binding["sourcePlan"], binding["vocabulary"], binding["roleManifest"])
    require(len(packet["episodes"]) == len(binding["sourcePlan"]), "Missing episode output")
    for p, output in zip(binding["sourcePlan"], packet["episodes"]):
        require(output["episodeIndex"] == p["episodeIndex"] and [r["sourceIndex"] for r in output["rows"]] == p["scheduledQueries"]
                and output["supportLabelIndices"] == [binding["vocabulary"].index(c) for c in p["supportLabels"]], "Prediction/source alignment changed")
        support = np.asarray(output["supportFeatures"], dtype=np.float64)
        common.validate_features(support); common.validate_scores(np.asarray(output["supportProbabilities"]), len(p["support"]), 97)
        require(support.shape == (len(p["support"]), 128), "Support shape changed")
        for row in output["rows"]:
            common.validate_scores(np.asarray(row["genericProbabilities"])[None, :], 1, 97)
            if row["outcome"] == "read":
                common.validate_scores(np.asarray(row["candidateProbabilities"])[None, :], 1, 97)
                require(row["failure"] is None, "Successful row has failure")
            else:
                require(row["outcome"] == "invalid" and row["candidateProbabilities"] is None
                        and isinstance(row["failure"], str) and row["failure"], "Invalid row repaired or deleted")


def predict(crossfit, roles, learner_directory, protocol, commitment, output):
    from .personal_conditional_support_trust import load_fitted_learner
    common.configure(); frozen = read(commitment); binding = parsed(frozen)
    require(frozen == canonical(binding), "Noncanonical preparation")
    validate_binding(binding, crossfit, roles, learner_directory, protocol)
    learner, _ = load_fitted_learner(learner_directory)
    before = {k: v.clone() for k, v in learner.state_dict().items()}
    arrays = feature_arrays(crossfit)
    episodes = [apply_episode(learner, arrays, p, binding["vocabulary"]) for p in binding["sourcePlan"]]
    packet = {"version": VERSION, "artifactKind": "engineering-only-writer-disjoint-internal-reuse-v1",
              **{key: False for key in ("queryTruthOpened", "productionEligible", "freshValidation", "encoderInferencePerformed",
                  "developmentWritersEvaluated", "reservedWritersEvaluated", "privateInkUsed", "appOrProfileChanged")},
              "bindings": binding, "commitmentCanonicalData": base64.b64encode(frozen).decode(),
              "commitmentSHA256": sha(frozen), "episodes": episodes}
    validate_packet(packet)
    require(read(commitment) == frozen and all(torch.equal(v, before[k]) for k, v in learner.state_dict().items()), "Model/preparation mutated")
    validate_binding(binding, crossfit, roles, learner_directory, protocol)
    data = canonical(packet); common.exclusive(output, data, (crossfit, roles, learner_directory, protocol, commitment))
    return {"predictionSHA256": sha(data), "scheduledExposures": 3104, "distinctSourceIndices": 1552, "queryTruthOpened": False}


def summarize(rows):
    gains = [r["exposureID"] for r in rows if not r["genericCorrect"] and r["candidateCorrect"]]
    harms = [r["exposureID"] for r in rows if r["genericCorrect"] and not r["candidateCorrect"]]
    return {"queryExposures": len(rows), "distinctSourceIndices": len({r["sourceIndex"] for r in rows}),
            "invalid": sum(r["outcome"] != "read" for r in rows), "genericCorrect": sum(r["genericCorrect"] for r in rows),
            "candidateCorrect": sum(r["candidateCorrect"] for r in rows), "gains": len(gains), "harms": len(harms),
            "netCorrect": len(gains) - len(harms), "gainExposureIDs": gains, "harmExposureIDs": harms,
            "bothCorrect": sum(r["genericCorrect"] and r["candidateCorrect"] for r in rows),
            "neitherCorrect": sum(not r["genericCorrect"] and not r["candidateCorrect"] for r in rows)}


def summaries(rows, writers):
    tasks, passed = {}, True
    for task in TASKS:
        tasks[task] = {}
        for view in ("rawScheduled", "sourceOnlyNoCopy"):
            selected = [r for r in rows if r["task"] == task and (view == "rawScheduled" or not r["exclusions"])]
            totals = {**summarize(selected), "excludedExposures": sum(bool(r["exclusions"]) for r in selected),
                      "distinctExcludedSourceIndices": len({r["sourceIndex"] for r in selected if r["exclusions"]}),
                      "exclusionReasonExposures": {reason: sum(reason in r["exclusions"] for r in selected)
                          for reason in sorted({reason for r in selected for reason in r["exclusions"]})}}
            strata = {name: summarize([r for r in selected if r["taught"] == taught]) for name, taught in (("taught", True), ("untaught", False))}
            by_writer = {w: summarize([r for r in selected if r["writer"] == w]) for w in writers}
            conditions = [totals["netCorrect"] > 0, all(cell["netCorrect"] >= 0 for cell in by_writer.values()),
                          strata["untaught"]["netCorrect"] >= 0, strata["untaught"]["harms"] == 0]
            if view == "sourceOnlyNoCopy":
                passed &= all(conditions)
            tasks[task][view] = {**totals, "strata": strata, "writers": by_writer,
                "supportSessions": {str(s): summarize([r for r in selected if r["supportSession"] == s]) for s in (1, 2)},
                "writerSessions": {w: {str(s): summarize([r for r in selected if r["writer"] == w and r["supportSession"] == s])
                    for s in (1, 2)} for w in writers},
                "writerStrata": {w: {name: summarize([r for r in selected if r["writer"] == w and r["taught"] == taught])
                    for name, taught in (("taught", True), ("untaught", False))} for w in writers},
                "sessionStrata": {str(s): {name: summarize([r for r in selected if r["supportSession"] == s and r["taught"] == taught])
                    for name, taught in (("taught", True), ("untaught", False))} for s in (1, 2)},
                "screenConditions": conditions, "authoritativeFixedScreen": view == "sourceOnlyNoCopy"}
    return tasks, bool(passed)


def score(predictions, prediction_sha256, crossfit, roles, learner_directory, protocol, output):
    common.configure(); data = read(predictions)
    require(common.digest_string(prediction_sha256) and sha(data) == prediction_sha256, "Prediction SHA mismatch before truth")
    packet = parsed(data); require(data == canonical(packet), "Noncanonical frozen predictions")
    validate_packet(packet); binding = packet["bindings"]
    validate_binding(binding, crossfit, roles, learner_directory, protocol)
    from .personal_conditional_support_trust import load_parent
    arrays, source, parent, manifest = load_parent(crossfit, roles)  # First query-label join, after the complete SHA gate.
    require(source_plan(source, parent["vocabulary"], manifest) == binding["sourcePlan"], "Frozen source plan changed")
    vocabulary, rows = binding["vocabulary"], []
    for p, episode in zip(binding["sourcePlan"], packet["episodes"]):
        si, qi = p["support"], p["scheduledQueries"]
        require(np.array_equal(np.asarray(episode["supportFeatures"]), arrays["stored_features"][si].astype(np.float64))
                and np.array_equal(np.asarray(episode["supportProbabilities"]), torch.from_numpy(arrays["stored_logits"][si].astype(np.float64)).softmax(1).numpy()),
                "Stored support changed")
        generic = torch.from_numpy(arrays["raw_logits"][qi].astype(np.float64)).softmax(1).numpy()
        excluded = {e["index"]: e["reasons"] for e in p["exclusions"]}
        for position, row in enumerate(episode["rows"]):
            index, truth = row["sourceIndex"], source[row["sourceIndex"]]["label"]
            require(np.array_equal(np.asarray(row["genericProbabilities"]), generic[position]), "Frozen generic changed")
            g = vocabulary[int(np.argmax(row["genericProbabilities"]))]
            c = vocabulary[int(np.argmax(row["candidateProbabilities"]))] if row["outcome"] == "read" else None
            rows.append({"exposureID": f'{p["episodeIndex"]}:{index}', "sourceIndex": index,
                "role": "internalValidation", "writer": p["writer"], "supportSession": p["session"], "querySession": p["querySession"],
                "task": p["task"], "trueLabel": truth, "taught": truth in p["supportLabels"], "exclusions": excluded.get(index, []),
                "outcome": row["outcome"], "failure": row["failure"], "genericTop1": g, "candidateTop1": c,
                "genericCorrect": g == truth, "candidateCorrect": c == truth})
    tasks, passed = summaries(rows, manifest["internalValidationWriters"])
    value = {"version": "personal-conditional-support-trust-score-v1", "predictionSHA256": prediction_sha256,
        "protocolSHA256": PROTOCOL_SHA256, "commitmentSHA256": packet["commitmentSHA256"], "sourcePlanSHA256": binding["sourcePlanSHA256"],
        "role": "internalValidation", "internalReuseOnly": True, "freshValidation": False, "productionEligible": False,
        "naturalChordAccuracyMeasured": False, "physicalSampleIndependenceEstablished": False,
        "scheduledExposures": len(rows), "distinctSourceIndices": len({r["sourceIndex"] for r in rows}),
        "excludedExposures": sum(bool(r["exclusions"]) for r in rows), "invalidExposures": sum(r["outcome"] != "read" for r in rows),
        "eligibleExposures": sum(not r["exclusions"] for r in rows),
        "distinctEligibleSourceIndices": len({r["sourceIndex"] for r in rows if not r["exclusions"]}),
        "unavailableSetupExposures": sum(len(p["unavailableSetup"]) for p in binding["sourcePlan"]),
        "distinctUnavailableSetupIndices": len({e["index"] for p in binding["sourcePlan"] for e in p["unavailableSetup"]}),
        "fixedScreenCohort": "sourceOnlyNoCopy",
        "tasks": tasks, "rows": rows, "passesFixedScreen": passed,
        "disposition": "separate-fresh-writer-and-runtime-checks-only" if passed else "reject-fixed-recipe-no-retuning"}
    validate_binding(binding, crossfit, roles, learner_directory, protocol)
    require(read(predictions) == data, "Frozen predictions changed during scoring")
    common.exclusive(output, canonical(value), (predictions, crossfit, roles, learner_directory, protocol)); return value


def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest="operation", required=True)
    for operation in ("prepare", "predict", "score"):
        p = sub.add_parser(operation)
        for field in ("crossfit", "roles", "learner-directory", "protocol", "output"):
            p.add_argument("--" + field, type=Path, required=True)
        if operation == "predict": p.add_argument("--commitment", type=Path, required=True)
        if operation == "score":
            p.add_argument("--predictions", type=Path, required=True); p.add_argument("--predictions-sha256", required=True)
    a = parser.parse_args(); args = (a.crossfit, a.roles, a.learner_directory, a.protocol)
    if a.operation == "prepare": result = prepare(*args, a.output)
    elif a.operation == "predict": result = predict(*args, a.commitment, a.output)
    else: result = score(a.predictions, a.predictions_sha256, *args, a.output)
    print(canonical({k: v for k, v in result.items() if k not in ("rows", "tasks", "sourcePlan", "roleManifest", "codeSHA256")}).decode())


if __name__ == "__main__":
    main()
