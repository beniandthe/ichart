"""One fixed action-utility screen over frozen public predictions, never app input.

prepare -> targets -> fit -> score are separate processes. Only targets/score
read old answers; fit receives exclusively the meta-fit target sidecar.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from . import personal_support_match_defer_evaluate as prior
from . import personal_support_action_selector as selector

VERSION = "personal-support-action-experiment-v1"
ROOT = prior.plan.ROOT
PROTOCOL = "docs/personal-support-action-selector-protocol-2026-10-03.md"
FILES = (PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/personal_support_action_selector.py",
    "recognition_ml/tests/test_personal_support_action_selector.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_action_experiment.py",
    "recognition_ml/tests/test_personal_support_action_experiment.py")
PREDICTIONS_SHA = "49183adb624e690c4f50b99e41de1d4616f35ad5cbac51518f7baa3c75243c03"
SCORE_SHA = "28037b416f85307a020901fa4061f6d70434a3b120caca26b9a5fe66297987b5"
PLAN_SHA = "c6fa6c953a87c471c18316cfa39f818869a9b50ac8327363e921486ed9988995"
ROLES_SHA = "47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa"
FIT_SHA = "74574a8db6816150896bfb781905d15f4e2354f84ca499ddd4f9b8f8680c26e7"
DIRECTION = "A16-to-B16"
require, sha, canonical = prior.require, prior.sha, prior.canonical


def identity():
    return {**prior.code_identity(), **{p: sha((ROOT / p).read_bytes()) for p in FILES}}


def read(path, expected=None):
    return prior.read_json(Path(path), expected_sha256=expected)[0]


def publish(directory, name, value):
    return prior.write_exclusive(Path(directory) / name, value)


def key(row):
    return row["episodeID"], row["queryPosition"], row["sourceIndex"]


def feature_row(base, candidate, pos, vocabulary, allowed):
    proposal = candidate["selectedSupportLabel"][pos]
    if candidate["route"][pos] != "explicit-support":
        require(proposal is None, "Deferred prediction manufactured proposal")
    return selector.feature_row(
        base["genericLogits"][pos], candidate["matchDeferLogits"][pos],
        candidate["queryEmbeddings"][pos], candidate["prototypes"],
        vocabulary, candidate["prototypeLabels"], allowed,
        base["genericDomainTop1"][pos], proposal)


def prepare(bundle, roles_path, directory):
    bundle, directory = Path(bundle), Path(directory)
    require(directory.is_dir() and not list(directory.iterdir()), "New empty evidence directory required")
    packet = read(bundle / "predictions.json", PREDICTIONS_SHA)
    forward = read(bundle / "source-plan/forward-plan.json", PLAN_SHA)
    roles = read(roles_path, ROLES_SHA)
    prior.validate_packet(packet, forward)
    require(packet["bindings"]["fitReceiptSHA256"] == FIT_SHA, "Wrong base models")
    schedule = forward["forward"][DIRECTION]
    fit_writers, check_writers = schedule["heldoutWriters"][:8], schedule["heldoutWriters"][8:]
    require(fit_writers == roles["metaFitWriters"] and check_writers == roles["internalValidationWriters"]
        and schedule["fitWriters"] == roles["encoderFitWriters"]
        and len(set(fit_writers + check_writers + schedule["fitWriters"])) == 32,
        "Writer roles changed")
    ledger = read(bundle / "source-plan/A16-to-B16-scoring-ledger.json",
        "1f0a34a763916815008517e3fc51b9528d38b8e319135155631fbd68d1a483a2")
    reasons = {key(r): r["reasons"] for r in ledger["queryRows"]}
    require(len(reasons) == len(ledger["queryRows"]), "Duplicate copy row")
    rows = []
    for episode in packet["episodes"]:
        if episode["direction"] != DIRECTION:
            continue
        require(episode["deterministicReplayEqual"] and episode["genericContextInvariant"], "Invalid frozen episode")
        plan = episode["sourcePlan"]["trueSupport"]
        require(plan["writer"] in fit_writers + check_writers, "Unexpected writer")
        base = episode["results"]["genericCEControl"]["trueSupport"]
        true = episode["results"]["jointMatchDefer"]["trueSupport"]
        wrong = episode["results"]["jointMatchDefer"]["wrongSupport"]
        require(all(r["failure"] is None for r in (base, true, wrong)), "Frozen failure retained; screen stopped")
        for pos, index in enumerate(plan["querySourceIndices"]):
            row = {"episodeID": episode["episodeID"], "queryPosition": pos, "sourceIndex": index,
                "writer": plan["writer"], "catalog": plan["catalog"], "session": plan["querySession"],
                "role": "metaFit" if plan["writer"] in fit_writers else "reusedCheck",
                "baseline": base["genericDomainTop1"][pos],
                "proposal": true["selectedSupportLabel"][pos],
                "wrongProposal": wrong["selectedSupportLabel"][pos],
                "features": feature_row(base, true, pos, packet["vocabulary"], packet["allowedLabels"]),
                "wrongFeatures": feature_row(base, wrong, pos, packet["vocabulary"], packet["allowedLabels"]),
                "taughtLabels": true["prototypeLabels"]}
            row["copyReasons"] = reasons[key(row)]
            require(row["features"] is not None or row["proposal"] is None, "Invalid true proposal features")
            require(row["wrongFeatures"] is not None or row["wrongProposal"] is None, "Invalid diagnostic proposal features")
            rows.append(row)
    require(len(rows) == 6208 and len({key(r) for r in rows}) == 6208
        and {key(r) for r in rows} == set(reasons), "Incomplete duplicate feature rows")
    value = {"version": VERSION, "codeSHA256": identity(), "parentPredictionsSHA256": PREDICTIONS_SHA,
        "forwardPlanSHA256": PLAN_SHA, "rolesSHA256": ROLES_SHA, "features": list(selector.FEATURE_NAMES),
        "fitWriters": fit_writers, "checkWriters": check_writers, "allowedLabels": packet["allowedLabels"],
        "scope": {"freshValidation": False, "productionEligible": False, "privateInkUsed": False,
            "newCNNInference": False, "queryTruthRead": False}, "rows": rows}
    return {"featuresSHA256": publish(directory, "features.json", value), "rows": len(rows)}


def features(directory):
    path = Path(directory) / "features.json"
    value = read(path)
    require(value["version"] == VERSION and value["codeSHA256"] == identity()
        and value["parentPredictionsSHA256"] == PREDICTIONS_SHA and value["rolesSHA256"] == ROLES_SHA,
        "Feature code/source binding changed")
    return value, sha(path.read_bytes())


def targets(bundle, directory):
    forward, digest = features(directory)
    # Previously scored answers are read in this staging process, never fitter.
    scored = read(Path(bundle) / "score.json", SCORE_SHA)
    truth = {key(r): r for r in scored["rows"] if r["direction"] == DIRECTION and r["writer"] in forward["fitWriters"]}
    rows = []
    for row in forward["rows"]:
        if row["role"] != "metaFit":
            continue
        source = truth[key(row)]
        require(source["writer"] == row["writer"] and source["catalog"] == row["catalog"]
            and source["control"] == row["baseline"] and source["copyReasons"] == row["copyReasons"], "Target row mismatch")
        rows.append({"episodeID": row["episodeID"], "queryPosition": row["queryPosition"],
            "sourceIndex": row["sourceIndex"], "action": selector.action_target(row["baseline"], row["proposal"], source["intended"])})
    require(len(rows) == 3104 and len(truth) == 3104, "Meta-fit target coverage changed")
    value = {"version": VERSION, "featuresSHA256": digest, "parentScoreSHA256": SCORE_SHA,
        "role": "metaFitOnly", "rows": rows}
    return {"targetsSHA256": publish(directory, "fit-targets.json", value), "rows": len(rows)}


def fit(directory):
    forward, digest = features(directory)
    target_path = Path(directory) / "fit-targets.json"
    target = read(target_path)
    require(target["version"] == VERSION and target["featuresSHA256"] == digest
        and target["parentScoreSHA256"] == SCORE_SHA and target["role"] == "metaFitOnly", "Invalid training target binding")
    by_key = {key(r): r["action"] for r in target["rows"]}
    require(len(by_key) == len(target["rows"]) == 3104
        and set(by_key) == {key(r) for r in forward["rows"] if r["role"] == "metaFit"}, "Training target coverage changed")
    train = [r for r in forward["rows"] if r["role"] == "metaFit" and not r["copyReasons"] and r["features"] is not None]
    counts = Counter(r["sourceIndex"] for r in train)
    weights = [1 / counts[r["sourceIndex"]] for r in train]
    action = [by_key[key(r)] for r in train]
    state = selector.fit_action_selector([r["features"] for r in train], action, weights)
    receipt = {"version": VERSION, "codeSHA256": identity(), "featuresSHA256": digest,
        "targetsSHA256": sha(target_path.read_bytes()), "state": state,
        "runtime": prior.runtime_identity(),
        "fitRows": len(train), "fitDistinctSources": len(counts), "fitTargetCounts": dict(Counter(map(str, action))),
        "fitKeys": [list(key(r)) for r in train], "fitWeights": weights,
        "claim": "Reused public development only; no app promotion"}
    fit_digest = publish(directory, "fit.json", receipt)
    rows = []
    for row in forward["rows"]:
        logits = selector.action_logits([row["features"]], state)[0] if row["features"] is not None else None
        wrong_logits = selector.action_logits([row["wrongFeatures"]], state)[0] if row["wrongFeatures"] is not None else None
        result = {"episodeID": row["episodeID"], "queryPosition": row["queryPosition"], "sourceIndex": row["sourceIndex"],
            "logits": logits, "wrongLogits": wrong_logits,
            "selected": selector.select_output(row["baseline"], row["proposal"], logits, forward["allowedLabels"]),
            "wrongSelected": selector.select_output(row["baseline"], row["wrongProposal"], wrong_logits, forward["allowedLabels"])}
        rows.append(result)
    packet = {"version": VERSION, "featuresSHA256": digest, "fitSHA256": fit_digest, "codeSHA256": identity(),
        "checkTruthRead": False, "rows": rows}
    return {"fitSHA256": fit_digest, "predictionsSHA256": publish(directory, "predictions.json", packet),
        "fitRows": len(train), "fitTargetCounts": receipt["fitTargetCounts"]}


def summarize(rows):
    domain = [r for r in rows if r["inDomain"]]
    gains = sum(r["baseline"] != r["truth"] and r["selected"] == r["truth"] for r in domain)
    harms = sum(r["baseline"] == r["truth"] and r["selected"] != r["truth"] for r in domain)
    danger = sum(r["baseline"] in (None, r["truth"]) and r["selected"] not in (None, r["truth"]) for r in domain)
    ood = sum(not r["inDomain"] and r["baseline"] is None and r["selected"] is not None for r in rows)
    methods = {m: {"correct": sum(r["inDomain"] and r[m] == r["truth"] for r in rows),
        "wrong": sum(r[m] is not None and r[m] != r["truth"] for r in rows),
        "noRead": sum(r[m] is None for r in rows)} for m in ("baseline", "selected", "wrongSelected")}
    writer_net = {w: sum(int(r["selected"] == r["truth"]) - int(r["baseline"] == r["truth"])
        for r in domain if r["writer"] == w) for w in sorted({r["writer"] for r in rows})}
    untaught = sum(not r["taught"] and r["baseline"] == r["truth"] and r["selected"] != r["truth"] for r in domain)
    gates = {"positiveNet": gains > harms, "noCorrectOrNoReadToWrong": danger == 0,
        "noUntaughtHarms": untaught == 0, "noNewOutOfDomainRead": ood == 0,
        "everyWriterNonnegative": bool(writer_net) and min(writer_net.values()) >= 0,
        "trueBeatsWrongSupport": methods["selected"]["correct"] > methods["wrongSelected"]["correct"],
        "completeFiniteEvidence": bool(rows) and all(not r["invalid"] for r in rows)}
    return {"exposures": len(rows), "distinctSources": len({r["sourceIndex"] for r in rows}),
        "domainQueries": len(domain), "methods": methods, "gains": gains, "harms": harms, "net": gains - harms,
        "correctOrNoReadToWrong": danger, "noReadToWrong": sum(r["baseline"] is None and r["selected"] not in (None, r["truth"]) for r in domain),
        "newOutOfDomainReads": ood, "untaughtHarms": untaught, "writerNet": writer_net,
        "changedOutputs": sum(r["baseline"] != r["selected"] for r in rows), "gates": gates, "passes": all(gates.values())}


def score(bundle, directory, predictions_sha):
    forward, digest = features(directory)
    prediction = read(Path(directory) / "predictions.json", predictions_sha)
    fit_value = read(Path(directory) / "fit.json", prediction["fitSHA256"])
    require(prediction["version"] == VERSION and prediction["featuresSHA256"] == digest
        and prediction["codeSHA256"] == identity() and prediction["checkTruthRead"] is False
        and fit_value["featuresSHA256"] == digest, "Prediction bindings changed")
    outputs = {key(r): r for r in prediction["rows"]}
    require(len(outputs) == len(prediction["rows"]) == len(forward["rows"])
        and set(outputs) == {key(r) for r in forward["rows"]}, "Prediction coverage changed")
    # Only now join check labels. Both subsets remain reused development data.
    scored = read(Path(bundle) / "score.json", SCORE_SHA)
    labels = {key(r): r for r in scored["rows"] if r["direction"] == DIRECTION}
    rows = []
    for row in forward["rows"]:
        output, label = outputs[key(row)], labels[key(row)]
        require(label["control"] == row["baseline"] and label["writer"] == row["writer"]
            and label["catalog"] == row["catalog"] and label["copyReasons"] == row["copyReasons"], "Score row mismatch")
        for fk, lk, pk, sk in (("features", "logits", "proposal", "selected"),
            ("wrongFeatures", "wrongLogits", "wrongProposal", "wrongSelected")):
            expected = selector.action_logits([row[fk]], fit_value["state"])[0] if row[fk] is not None else None
            require(expected == output[lk] and output[sk] == selector.select_output(row["baseline"], row[pk], expected, forward["allowedLabels"]), "Routed result changed")
        rows.append({**row, **output, "truth": label["intended"], "inDomain": label["inDomain"],
            "taught": label["intended"] in row["taughtLabels"], "invalid": False})
    results = {}
    for role in ("metaFit", "reusedCheck"):
        results[role] = {}
        for catalog in sorted({r["catalog"] for r in rows}):
            group = [r for r in rows if r["role"] == role and r["catalog"] == catalog]
            results[role][catalog] = {"raw": summarize(group), "noCopy": summarize([r for r in group if not r["copyReasons"]])}
    value = {"version": VERSION, "codeSHA256": identity(), "featuresSHA256": digest,
        "predictionsSHA256": predictions_sha, "parentScoreSHA256": SCORE_SHA,
        "results": results, "rows": rows,
        "passes": all(s[cohort]["passes"] for s in results["reusedCheck"].values() for cohort in ("raw", "noCopy")),
        "scope": {"freshValidation": False, "productionEligible": False, "privateInkUsed": False}}
    return {"scoreSHA256": publish(directory, "score.json", value), "passes": value["passes"], "results": results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("prepare", "targets", "fit", "score"))
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--roles", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--predictions-sha256")
    args = parser.parse_args()
    if args.stage == "prepare":
        result = prepare(args.bundle, args.roles, args.output)
    elif args.stage == "targets":
        result = targets(args.bundle, args.output)
    elif args.stage == "fit":
        result = fit(args.output)
    else:
        result = score(args.bundle, args.output, args.predictions_sha256)
    print(canonical(result).decode())


if __name__ == "__main__":
    main()
