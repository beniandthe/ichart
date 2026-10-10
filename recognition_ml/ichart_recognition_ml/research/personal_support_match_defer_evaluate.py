"""Fixed public training-fold match/defer comparison; never app acceptance.

Prediction reads only the committed forward plan, label-free rasters and fitted
states. Query labels and source-copy cohorts are joined by a separate command,
only after authenticating the exclusive canonical prediction artifact.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform

import numpy as np
import torch

from . import personal_support_match_defer as core
from . import personal_support_match_defer_data as data
from . import personal_support_match_defer_plan as plan

VERSION = "personal-support-match-defer-predictions-v1"
SCORE_VERSION = "personal-support-match-defer-score-v1"
ARMS = ("genericCEControl", "jointMatchDefer")
CONTEXTS = ("trueSupport", "wrongSupport")
DIRECTIONS = ("A16-to-B16", "B16-to-A16")
PROTOCOL_SHA256 = "b8bc1c371f3e5cfd60c8f8867e8380148d93d7105ff62289c4ff1b02484d5c33"
canonical, sha, require = plan.canonical, plan.sha, plan.require
OWN_PATHS = ("recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_evaluate.py",
             "recognition_ml/tests/test_personal_support_match_defer_evaluate.py")


def code_identity():
    from . import personal_support_match_defer_train as train
    return {**plan.code_identity(), **data.code_identity(), **train.code_identity(),
            **{name: sha(plan.read(plan.ROOT / name)) for name in OWN_PATHS}}


def read_json(path, *, maximum=512 * 1024 * 1024, expected_sha256=None):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and 0 < path.stat().st_size <= maximum, "Bounded regular JSON required")
    payload = path.read_bytes()
    if expected_sha256 is not None:
        require(plan.digest(expected_sha256) and sha(payload) == expected_sha256, "Artifact SHA256 changed")
    value = plan.parsed(payload)
    require(isinstance(value, dict) and canonical(value) == payload, "Canonical object JSON required")
    return value, payload


def write_exclusive(path, value, protected=()):
    path = Path(path)
    require(path.is_absolute() and path.parent.resolve() == path.parent and path.parent.is_dir()
            and not path.exists() and not path.is_symlink() and plan.ROOT not in path.parents
            and all(path != Path(p).resolve() and Path(p).resolve() not in path.parents for p in protected),
            "Exclusive outside-input/repository output required")
    payload = canonical(value)
    with path.open("xb") as stream:
        stream.write(payload)
    require(path.read_bytes() == payload, "Published bytes changed")
    return sha(payload)


def state_sha(model):
    return sha(canonical({name: {"shape": list(t.shape), "dtype": str(t.dtype),
                                "bytesSHA256": sha(t.detach().cpu().numpy().tobytes())}
                          for name, t in sorted(model.state_dict().items())}))


def runtime_identity():
    return {"python": platform.python_version(), "numpy": str(np.__version__), "torch": str(torch.__version__),
            "cpuThreads": torch.get_num_threads(), "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled(),
            "batchNormalizationUpdates": 0}


def projected(logits, vocabulary, allowed):
    values = np.asarray(logits)
    require(values.ndim == 2 and values.shape[1] == len(vocabulary) and np.isfinite(values).all(), "Invalid generic logits")
    raw = [vocabulary[i] for i in values.argmax(axis=1).tolist()]
    return raw, [label if label in allowed else None for label in raw]


def route(scores, labels, generic, allowed):
    require(len(set(labels)) == len(labels) and set(labels) <= set(allowed), "Unsupported/duplicate support sidecar")
    if scores is None:
        require(not labels, "Nonempty support needs match/DEFER scores")
        return ["generic"] * len(generic), [None] * len(generic), list(generic)
    values = np.asarray(scores)
    require(values.shape == (len(generic), len(labels) + 1) and np.isfinite(values).all(), "Invalid match/DEFER scores")
    kinds, selected, outputs = [], [], []
    for row, fallback in zip(values, generic):
        winners = np.flatnonzero(row == row.max())
        label = labels[int(winners[0])] if len(winners) == 1 and int(winners[0]) < len(labels) else None
        kinds.append("explicit-support" if label is not None else "generic")
        selected.append(label); outputs.append(label if label is not None else fallback)
    return kinds, selected, outputs


def predict_episode(model, episode, arrays, stored_lookup, vocabulary, allowed, *, arm):
    """One support-then-query encode; numerical forward never receives answers."""
    require(arm in ARMS and not model.training and all(not m.training for m in model.modules()), "CPU eval model required")
    require(episode["profileUsable"], "Unusable support profile cannot be repaired")
    support = [s for s in episode["support"] if s["storedFailure"] is None]
    query = episode["querySourceIndices"]
    sr = torch.from_numpy(arrays["stored_rasters"][[stored_lookup[s["sourceIndex"]] for s in support]].copy()).float() / 255
    qr = torch.from_numpy(arrays["raw_rasters"][query].copy()).float() / 255
    encoding = model.encode_episode(sr, qr)
    logits = encoding.query_generic_logits.detach().cpu().tolist()
    raw, generic = projected(logits, vocabulary, allowed)
    pooled = scores = None
    if arm == "jointMatchDefer":
        pooled = core.pool_confirmed_support(encoding.support_embeddings, [s["label"] for s in support],
            [s["sourceID"] for s in support], [s["storedTrajectorySHA256"] for s in support],
            [s["storedRasterSHA256"] for s in support], lambda label: label in allowed)
        scores = model(encoding.query_embeddings, pooled.prototypes).detach().cpu().tolist() if pooled.labels else None
    labels = list(pooled.labels) if pooled is not None else []
    kinds, selected, personal = route(scores, labels, generic, allowed)
    return {"failure": None, "matcherActive": arm == "jointMatchDefer", "genericLogits": logits,
            "genericRawTop1": raw, "genericDomainTop1": generic, "route": kinds,
            "selectedSupportLabel": selected, "personalDomainTop1": personal,
            "queryEmbeddings": encoding.query_embeddings.detach().cpu().tolist(),
            "supportEmbeddings": encoding.support_embeddings.detach().cpu().tolist(),
            "prototypeLabels": labels, "prototypes": pooled.prototypes.detach().cpu().tolist() if pooled is not None else [],
            "matchDeferLogits": scores}


def failed_context(count, arm, error):
    return {"failure": f"{type(error).__name__}: {error}", "matcherActive": arm == "jointMatchDefer",
            "genericLogits": None, "genericRawTop1": [None] * count, "genericDomainTop1": [None] * count,
            "route": ["invalid"] * count, "selectedSupportLabel": [None] * count,
            "personalDomainTop1": [None] * count, "queryEmbeddings": None, "supportEmbeddings": None,
            "prototypeLabels": [], "prototypes": [], "matchDeferLogits": None}


def freeze_forward(models, forward, arrays):
    vocabulary, allowed = forward["vocabulary"], set(forward["allowedLabels"])
    stored_lookup = {int(i): p for p, i in enumerate(arrays["stored_source_indices"])}
    episodes = []
    with torch.inference_mode():
        for direction, schedule in forward["forward"].items():
            for pair in schedule["heldoutEpisodes"]:
                results, replay_equal = {}, True
                for arm in ARMS:
                    results[arm] = {}
                    for context in CONTEXTS:
                        episode = pair[context]
                        try:
                            args = (models[direction][arm], episode, arrays, stored_lookup, vocabulary, allowed)
                            result = predict_episode(*args, arm=arm)
                            replay_equal &= result == predict_episode(*args, arm=arm)
                        except (ValueError, RuntimeError, FloatingPointError) as error:
                            result = failed_context(len(episode["querySourceIndices"]), arm, error)
                            replay_equal = False
                        results[arm][context] = result
                invariant = all(results[arm]["trueSupport"]["genericLogits"] == results[arm]["wrongSupport"]["genericLogits"]
                                and results[arm]["trueSupport"]["queryEmbeddings"] == results[arm]["wrongSupport"]["queryEmbeddings"]
                                and results[arm]["trueSupport"]["failure"] is None and results[arm]["wrongSupport"]["failure"] is None for arm in ARMS)
                episodes.append({"direction": direction, "episodeID": pair["trueSupport"]["episodeID"],
                    "sourcePlan": pair, "results": results, "deterministicReplayEqual": replay_equal,
                    "genericContextInvariant": invariant})
    return episodes


def predict(plan_dir, data_dir, fit_dir, output, *, fit_receipt_sha256):
    from . import personal_support_match_defer_train as train
    plan_dir, data_dir, fit_dir = map(Path, (plan_dir, data_dir, fit_dir))
    forward = data.load_forward_plan(plan_dir)
    arrays, receipt = data.load_raster_bundle(data_dir, forward)
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    models, fit = train.load_fitted_models(fit_dir, fit_receipt_sha256)
    require(fit["protocolSHA256"] == PROTOCOL_SHA256 and fit["vocabulary"] == forward["vocabulary"]
            and fit["allowedLabels"] == forward["allowedLabels"] and fit["forwardPlanSHA256"] == sha(canonical(forward))
            and fit["dataReceiptSHA256"] == sha(plan.read(data_dir / "data-receipt.json"))
            and fit["rasterDataSHA256"] == receipt["rastersSHA256"]
            and fit["sourcePlanReceiptSHA256"] == sha(plan.read(plan_dir / "plan-receipt.json")), "Fit/input binding changed")
    code = code_identity()
    runtime = runtime_identity()
    states = {d: {a: state_sha(models[d][a]) for a in ARMS} for d in DIRECTIONS}
    bindings = {"fitReceiptSHA256": fit_receipt_sha256, "weights": fit["weights"], "modelStatesSHA256": states,
        "forwardPlanSHA256": sha(canonical(forward)), "sourcePlanReceiptSHA256": fit["sourcePlanReceiptSHA256"],
        "dataReceiptSHA256": fit["dataReceiptSHA256"], "rasterDataSHA256": receipt["rastersSHA256"],
        "queryTruthSHA256": receipt["truthSHA256"], "sourceSHA256": forward["bindings"]["sourceSHA256"],
        "domainSHA256": forward["bindings"]["domainSHA256"], "codeSHA256": code, "runtimeSHA256": sha(canonical(runtime))}
    episodes = freeze_forward(models, forward, arrays)
    require(states == {d: {a: state_sha(models[d][a]) for a in ARMS} for d in DIRECTIONS}, "State/BN mutated during prediction")
    again, again_fit = train.load_fitted_models(fit_dir, fit_receipt_sha256)
    require(again_fit == fit and states == {d: {a: state_sha(again[d][a]) for a in ARMS} for d in DIRECTIONS}
            and runtime_identity() == runtime
            and data.load_forward_plan(plan_dir) == forward and code_identity() == code, "Frozen inputs/code changed")
    _, after_data = data.load_raster_bundle(data_dir, forward)
    require(after_data == receipt, "Raster receipt changed")
    packet = {"version": VERSION, "protocolSHA256": PROTOCOL_SHA256, "bindings": bindings,
        "vocabulary": forward["vocabulary"], "allowedLabels": forward["allowedLabels"], "episodes": episodes,
        "runtime": runtime,
        "scope": {"productionEligible": False, "freshValidation": False, "naturalChordAccuracyMeasured": False,
                  "developmentOrReservedInferencePerformed": False, "privateInkUsed": False, "queryTruthRead": False}}
    validate_packet(packet, forward)
    digest = write_exclusive(output, packet, (plan_dir, data_dir, fit_dir))
    return {"predictionsSHA256": digest, "episodes": len(episodes), "queryExposuresPerArm": sum(len(e["sourcePlan"]["trueSupport"]["querySourceIndices"]) for e in episodes)}


def validate_packet(packet, forward):
    require(packet["version"] == VERSION and packet["protocolSHA256"] == PROTOCOL_SHA256
            and packet["vocabulary"] == forward["vocabulary"] and packet["allowedLabels"] == forward["allowedLabels"]
            and packet["bindings"]["forwardPlanSHA256"] == sha(canonical(forward))
            and packet["bindings"]["sourceSHA256"] == forward["bindings"]["sourceSHA256"]
            and packet["bindings"]["domainSHA256"] == forward["bindings"]["domainSHA256"]
            and packet["bindings"]["runtimeSHA256"] == sha(canonical(packet["runtime"]))
            and packet["runtime"]["cpuThreads"] == 4 and packet["runtime"]["deterministicAlgorithms"] is True
            and packet["runtime"]["batchNormalizationUpdates"] == 0
            and all(packet["scope"][k] is False for k in ("productionEligible", "freshValidation", "naturalChordAccuracyMeasured",
                "developmentOrReservedInferencePerformed", "privateInkUsed", "queryTruthRead")), "Wrong prediction cohort/domain/runtime/binding")
    expected = [(d, pair) for d, s in forward["forward"].items() for pair in s["heldoutEpisodes"]]
    require(len(packet["episodes"]) == len(expected), "Missing/extra prediction episodes")
    for frozen, (direction, pair) in zip(packet["episodes"], expected):
        require(frozen["direction"] == direction and frozen["sourcePlan"] == pair
                and frozen["episodeID"] == pair["trueSupport"]["episodeID"] and set(frozen["results"]) == set(ARMS), "Episode/source alignment changed")
        count = len(pair["trueSupport"]["querySourceIndices"])
        for arm in ARMS:
            require(set(frozen["results"][arm]) == set(CONTEXTS), "Missing context")
            for context in CONTEXTS:
                result = frozen["results"][arm][context]
                require(result["matcherActive"] == (arm == "jointMatchDefer"), "Inactive control matcher was routed")
                if result["failure"] is not None:
                    require(isinstance(result["failure"], str) and bool(result["failure"])
                            and result == (failed_context(count, arm, ValueError("placeholder")) | {"failure": result["failure"]}), "Malformed retained failure")
                    continue
                raw, generic = projected(result["genericLogits"], packet["vocabulary"], packet["allowedLabels"])
                labels = pair[context]["availablePrototypeLabels"] if arm == "jointMatchDefer" else []
                require(result["prototypeLabels"] == labels, "Support projection changed")
                kinds, selected, personal = route(result["matchDeferLogits"], labels, generic, packet["allowedLabels"])
                require(len(raw) == count and result["genericRawTop1"] == raw and result["genericDomainTop1"] == generic
                        and result["route"] == kinds and result["selectedSupportLabel"] == selected
                        and result["personalDomainTop1"] == personal, "Frozen route/top-one changed")
                for key, rows in (("queryEmbeddings", count), ("supportEmbeddings", pair[context]["availableSupportRows"]), ("prototypes", len(labels))):
                    a = np.asarray(result[key])
                    require(a.shape == ((rows, 128) if rows else (0,)) and np.isfinite(a).all()
                            and (not rows or np.all(np.abs(np.linalg.norm(a, axis=1) - 1) <= 1e-3)), "Malformed/nonfinite feature vectors")
        actual_invariant = all(frozen["results"][a]["trueSupport"]["failure"] is None
            and frozen["results"][a]["wrongSupport"]["failure"] is None
            and all(frozen["results"][a]["trueSupport"][k] == frozen["results"][a]["wrongSupport"][k]
                    for k in ("genericLogits", "queryEmbeddings")) for a in ARMS)
        require(type(frozen["deterministicReplayEqual"]) is bool and frozen["genericContextInvariant"] is actual_invariant, "Replay/context assertion changed")


def comparison(rows, before, after):
    domain = [r for r in rows if r["inDomain"]]
    gains = sum(r[before] != r["intended"] and r[after] == r["intended"] for r in domain)
    harms = sum(r[before] == r["intended"] and r[after] != r["intended"] for r in domain)
    return {"denominator": len(domain), "gains": gains, "harms": harms, "net": gains - harms,
        "correctOrNoReadToWrong": sum(r[before] in (None, r["intended"]) and r[after] not in (None, r["intended"]) for r in domain),
        "newOutOfDomainOutputs": sum(not r["inDomain"] and r[before] is None and r[after] is not None for r in rows)}


def summarize(rows):
    outputs = {method: {"correct": sum(r["inDomain"] and r[method] == r["intended"] for r in rows),
        "wrongDomainRead": sum(r[method] is not None and r[method] != r["intended"] for r in rows),
        "noRead": sum(r[method] is None for r in rows)} for method in ("control", "generic", "personal", "wrongSupport")}
    return {"exposures": len(rows), "distinctSources": len({r["sourceIndex"] for r in rows}),
        "domainQueries": sum(r["inDomain"] for r in rows), "outOfDomainQueries": sum(not r["inDomain"] for r in rows),
        "invalidRows": sum(r["invalid"] for r in rows), "outputs": outputs,
        "genericVsControl": comparison(rows, "control", "generic"), "personalVsOwnGeneric": comparison(rows, "generic", "personal"),
        "trueRoutedCorrect": sum(r["trueRoute"] == "explicit-support" and r["personal"] == r["intended"] for r in rows),
        "wrongRoutedCorrect": sum(r["wrongRoute"] == "explicit-support" and r["wrongSupport"] == r["intended"] for r in rows)}


def fixed_screen(rows, episode_evidence):
    summary = summarize(rows); generic, personal = summary["genericVsControl"], summary["personalVsOwnGeneric"]
    writers = sorted({r["writer"] for r in rows})
    untaught = [r for r in rows if r["cohort"] == "untaught"]
    eligible = {e: [r for r in rows if r["episodeID"] == e] for e in episode_evidence}
    gates = {"genericDomainNonnegativeNet": generic["net"] >= 0,
        "genericNoNewOutOfDomainOutput": generic["newOutOfDomainOutputs"] == 0,
        "genericNoCorrectOrNoReadToWrong": generic["correctOrNoReadToWrong"] == 0,
        "personalNoCorrectOrNoReadToWrong": personal["correctOrNoReadToWrong"] == 0,
        "personalStrictlyPositiveDomainNet": personal["net"] > 0,
        "zeroUntaughtDomainHarms": comparison(untaught, "generic", "personal")["harms"] == 0,
        "everyWriterNonnegativePersonalNet": bool(writers) and all(comparison([r for r in rows if r["writer"] == w], "generic", "personal")["net"] >= 0 for w in writers),
        "trueSupportFinalCorrectBeatsFixedWrongSupport": summary["outputs"]["personal"]["correct"] > summary["outputs"]["wrongSupport"]["correct"],
        "personalNoNewOutOfDomainOutput": personal["newOutOfDomainOutputs"] == 0,
        "completeFiniteDeterministicEvidence": summary["invalidRows"] == 0 and all(e["valid"] for e in episode_evidence.values()),
        "equalAvailableLabelsEveryEpisode": all(e["sameAvailability"] for e in episode_evidence.values()),
        "eligibleTaughtUntaughtEveryEpisode": all(any(r["inDomain"] and r["cohort"] == c for r in group) for group in eligible.values() for c in ("taught", "untaught"))}
    return {"passes": all(gates.values()), "gates": gates}


def join_rows(packet, forward, truth, ledgers):
    require(truth["version"] == data.TRUTH_VERSION and truth["sourceSHA256"] == forward["bindings"]["sourceSHA256"]
            and truth["forwardPlanSHA256"] == sha(canonical(forward)), "Truth/source binding changed")
    truth_rows = truth["rows"]
    require(len(truth_rows) == len(forward["sourceLedger"]) and all(set(r) == {"sourceIndex", "intended"}
            and type(r["sourceIndex"]) is int and r["sourceIndex"] == i and r["intended"] in packet["vocabulary"] for i, r in enumerate(truth_rows)), "Incomplete/duplicate truth indices")
    rows, evidence = [], {}
    for direction, schedule in forward["forward"].items():
        ledger = ledgers[direction]["queryRows"]
        expected = {(p["trueSupport"]["episodeID"], pos, i) for p in schedule["heldoutEpisodes"] for pos, i in enumerate(p["trueSupport"]["querySourceIndices"])}
        require(len(ledger) == len(expected) and {(r["episodeID"], r["queryPosition"], r["sourceIndex"]) for r in ledger} == expected
                and all(type(r["sourceIndex"]) is int and type(r["queryPosition"]) is int and isinstance(r["reasons"], list)
                        and len(r["reasons"]) == len(set(r["reasons"])) and all(isinstance(x, str) and x for x in r["reasons"]) for r in ledger), "Paired copy-ledger alignment changed")
    reasons = {(d, r["episodeID"], r["queryPosition"]): r["reasons"] for d, ledger in ledgers.items() for r in ledger["queryRows"]}
    for frozen in packet["episodes"]:
        pair, d, e = frozen["sourcePlan"], frozen["direction"], frozen["episodeID"]
        for context in CONTEXTS:
            require(all(truth_rows[s["sourceIndex"]]["intended"] == s["label"] for s in pair[context]["support"]), "Confirmed support/truth mismatch")
        evidence[d, e] = {"valid": frozen["deterministicReplayEqual"] and frozen["genericContextInvariant"]
            and all(pair[c]["profileUsable"] for c in CONTEXTS), "sameAvailability": pair["availableLabelSetsEqual"]
            and pair["trueSupport"]["availablePrototypeLabels"] == pair["wrongSupport"]["availablePrototypeLabels"]}
        results = frozen["results"]
        for pos, index in enumerate(pair["trueSupport"]["querySourceIndices"]):
            label, source = truth_rows[index]["intended"], forward["sourceLedger"][index]
            require(source["writer"] == pair["trueSupport"]["writer"] and source["session"] == pair["trueSupport"]["querySession"], "Query source metadata changed")
            rows.append({"direction": d, "catalog": pair["trueSupport"]["catalog"], "writer": source["writer"], "querySession": source["session"],
                "episodeID": e, "queryPosition": pos, "sourceIndex": index, "intended": label, "inDomain": label in packet["allowedLabels"],
                "cohort": "taught" if label in pair["trueSupport"]["availablePrototypeLabels"] else "unavailableRequest" if label in pair["trueSupport"]["requestedSupportLabels"] else "untaught",
                "copyReasons": reasons[d, e, pos], "invalid": any(results[a][c]["failure"] is not None for a in ARMS for c in CONTEXTS),
                "control": results["genericCEControl"]["trueSupport"]["genericDomainTop1"][pos],
                "generic": results["jointMatchDefer"]["trueSupport"]["genericDomainTop1"][pos],
                "personal": results["jointMatchDefer"]["trueSupport"]["personalDomainTop1"][pos],
                "wrongSupport": results["jointMatchDefer"]["wrongSupport"]["personalDomainTop1"][pos],
                "trueRoute": results["jointMatchDefer"]["trueSupport"]["route"][pos], "wrongRoute": results["jointMatchDefer"]["wrongSupport"]["route"][pos]})
    return rows, evidence


def score_packet(packet, forward, truth, ledgers):
    validate_packet(packet, forward)
    rows, evidence = join_rows(packet, forward, truth, ledgers)
    results = {}
    for direction in forward["forward"]:
        results[direction] = {}
        for catalog in forward["catalogs"]:
            group = [r for r in rows if r["direction"] == direction and r["catalog"] == catalog]
            episode_evidence = {e: v for (d, e), v in evidence.items() if d == direction and any(r["episodeID"] == e for r in group)}
            results[direction][catalog] = {}
            for name, selected in (("raw", group), ("noCopy", [r for r in group if not r["copyReasons"]])):
                results[direction][catalog][name] = {**summarize(selected), "excludedCopyExposures": len(group) - len(selected),
                    "screen": fixed_screen(selected, episode_evidence),
                    "writers": {w: summarize([r for r in selected if r["writer"] == w]) for w in forward["forward"][direction]["heldoutWriters"]},
                    "strata": {c: summarize([r for r in selected if r["cohort"] == c]) for c in ("taught", "untaught", "unavailableRequest")},
                    "domainStrata": {c: summarize([r for r in selected if r["inDomain"] == inside]) for c, inside in (("supportedDomain", True), ("outOfDomain", False))}}
    passes = all(v[view]["screen"]["passes"] for tasks in results.values() for v in tasks.values() for view in ("raw", "noCopy"))
    return {"version": SCORE_VERSION, "protocolSHA256": PROTOCOL_SHA256, "passesFixedScreen": passes,
        "decision": "runtime-and-fresh-writing-check-only" if passes else "reject-fixed-recipe-no-retuning",
        "exposures": len(rows), "distinctSources": len({r["sourceIndex"] for r in rows}), "results": results, "rows": rows,
        "scope": {"productionEligible": False, "freshValidation": False, "naturalChordAccuracyMeasured": False,
            "developmentOrReservedInferencePerformed": False, "privateInkUsed": False,
            "note": "Reused public glyph fragments and literal labels only; catalog/session/support exposures are paired, not independent handwriting."}}


def score(predictions, plan_dir, data_dir, output, *, predictions_sha256):
    # Authentication and all prediction/source alignment precede any truth read.
    packet, frozen_bytes = read_json(predictions, expected_sha256=predictions_sha256)
    forward = data.load_forward_plan(Path(plan_dir))
    validate_packet(packet, forward)
    require(packet["bindings"]["codeSHA256"] == code_identity(), "Evaluation code changed after prediction")
    receipt, receipt_bytes = read_json(Path(data_dir) / "data-receipt.json")
    require(sha(receipt_bytes) == packet["bindings"]["dataReceiptSHA256"] and receipt["truthSHA256"] == packet["bindings"]["queryTruthSHA256"]
            and receipt["forwardPlanSHA256"] == packet["bindings"]["forwardPlanSHA256"]
            and receipt["rastersSHA256"] == packet["bindings"]["rasterDataSHA256"]
            and receipt["planReceiptSHA256"] == packet["bindings"]["sourcePlanReceiptSHA256"]
            and receipt["sourceSHA256"] == packet["bindings"]["sourceSHA256"]
            and receipt["truthFile"] == "score-truth.json", "Truth/data commitment changed")
    truth, truth_bytes = read_json(Path(data_dir) / receipt["truthFile"], expected_sha256=receipt["truthSHA256"])
    ledgers, ledger_bytes = {}, {}
    for d, binding in forward["scoringLedgerBindings"].items():
        require(binding["path"] == d + "-scoring-ledger.json", "Unexpected scoring path")
        ledgers[d], ledger_bytes[d] = read_json(Path(plan_dir) / binding["path"], expected_sha256=binding["SHA256"])
    result = score_packet(packet, forward, truth, ledgers)
    result["bindings"] = {**packet["bindings"], "predictionsSHA256": predictions_sha256,
                          "scoringLedgerSHA256": {d: sha(b) for d, b in ledger_bytes.items()}}
    require(Path(predictions).read_bytes() == frozen_bytes and data.load_forward_plan(Path(plan_dir)) == forward
            and plan.read(Path(data_dir) / "data-receipt.json") == receipt_bytes
            and plan.read(Path(data_dir) / receipt["truthFile"]) == truth_bytes
            and all(plan.read(Path(plan_dir) / forward["scoringLedgerBindings"][d]["path"]) == b for d, b in ledger_bytes.items())
            and code_identity() == packet["bindings"]["codeSHA256"], "Frozen scoring inputs changed")
    return {"scoreSHA256": write_exclusive(output, result, (predictions, plan_dir, data_dir)), "passesFixedScreen": result["passesFixedScreen"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("predict", "score"):
        p = commands.add_parser(name)
        p.add_argument("--source-plan", dest="plan_dir", type=Path, required=True)
        p.add_argument("--data", dest="data_dir", type=Path, required=True)
        p.add_argument("--output", type=Path, required=True)
    commands.choices["predict"].add_argument("--fit", dest="fit_dir", type=Path, required=True)
    commands.choices["predict"].add_argument("--fit-receipt-sha256", required=True)
    commands.choices["score"].add_argument("--predictions", type=Path, required=True)
    commands.choices["score"].add_argument("--predictions-sha256", required=True)
    args = vars(parser.parse_args()); command = args.pop("command")
    print(json.dumps((predict if command == "predict" else score)(**args), sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
