"""Fixed training-row diagnosis, not optimization or generalization evidence."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

import numpy as np
import torch

from . import personal_conditional_support_trust as core
from .personal_support_retrieval import canonical, require, sha, balanced_loss
from .personal_cross_writer_contrastive import _new_output, _regular_file, _state_digest, _write_exclusive

VERSION = "personal-support-training-risk-v1"
ARMS = ("generic", "initialGate", "finalGate")
PROTOCOL = "docs/personal-support-training-risk-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "f3d577178622118575cdc15fb9b3a2eb0db501fa7a675c7e89515fd896b76523"
WEIGHTS_SHA256 = "0fc0096f9d57d43ac7518e9768c9643cab1c207e7bba4a28074fd7be2b68db4b"
RECEIPT_SHA256 = "6f349defbc1fccdded6df5963c6f346fb885538ea220577e0e4ea0e98f39a789"
PROBABILITY_ENCODING = "float64-le-row-major"


def code_identity():
    root = Path(__file__).resolve().parents[3]
    files = (PROTOCOL, "recognition_ml/ichart_recognition_ml/research/personal_support_training_risk.py",
        "recognition_ml/tests/test_personal_support_training_risk.py")
    result = {**core.code_identity(), **{name: sha((root / name).read_bytes()) for name in files}}
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Training-risk protocol changed")
    return result


def predict_episode(generic, cache, scalars, final_model, initial_model):
    """Three matched full97 outputs; no query targets, labels or source IDs."""
    core.audit._probability_matrix(generic)
    core.audit._probability_matrix(cache)
    require(generic.shape == cache.shape and generic.shape[1] == 97
        and scalars.shape == (len(generic), 14) and scalars.dtype == torch.float64
        and scalars.device.type == "cpu" and bool(torch.isfinite(scalars).all()), "Frozen full97 scalar contract required")
    with torch.no_grad():
        gates = (generic.new_zeros((len(generic), 1)), initial_model.gate(scalars).sigmoid(),
            final_model.gate(scalars).sigmoid())
        outputs = [(1 - gate) * generic + gate * cache for gate in gates]
    require(torch.equal(outputs[0], generic), "Exact generic identity failed")
    result = {}
    for arm, gate, probabilities in zip(ARMS, gates, outputs):
        core.audit._probability_matrix(probabilities)
        result[arm] = {"top1": probabilities.argmax(1).tolist(), "gate": gate[:, 0].tolist(),
            "probabilityEncoding": PROBABILITY_ENCODING, "full97Shape": list(probabilities.shape),
            "full97ProbabilitySHA256": probability_digest(probabilities)}
    return result


def probability_digest(probabilities):
    core.audit._probability_matrix(probabilities)
    require(probabilities.shape[1] == 97, "Complete full97 probability array required")
    return sha(probabilities.detach().contiguous().numpy().astype("<f8", copy=False).tobytes(order="C"))


def score_episode(prediction, generic, cache, targets, taught):
    """Supervised TRAINING score only, after truth-free prediction serialization."""
    require(set(prediction) == set(ARMS), "Matched arms required")
    outputs, scores = {}, {}
    for arm in ARMS:
        gate = torch.tensor(prediction[arm]["gate"], dtype=torch.float64)[:, None]
        require(gate.shape == (len(generic), 1) and bool(torch.isfinite(gate).all())
            and bool(((gate >= 0) & (gate <= 1)).all()), "Invalid frozen gates")
        probabilities = (1 - gate) * generic + gate * cache
        core.audit._probability_matrix(probabilities)
        require(prediction[arm]["probabilityEncoding"] == PROBABILITY_ENCODING
            and prediction[arm]["full97Shape"] == list(probabilities.shape)
            and prediction[arm]["full97ProbabilitySHA256"] == probability_digest(probabilities)
            and prediction[arm]["top1"] == probabilities.argmax(1).tolist(), "Frozen training arithmetic changed")
        outputs[arm] = probabilities.argmax(1)
        scores[arm] = {"balancedNLL": float(balanced_loss(probabilities, targets, taught)), "strata": {}}
    require(torch.equal(outputs["generic"], generic.argmax(1)) and all(v == 0 for v in prediction["generic"]["gate"]),
        "Generic diagnostic arm changed")
    for arm in ARMS:
        for name, mask in (("all", torch.ones_like(taught)), ("taught", taught), ("untaught", ~taught)):
            base, correct = outputs["generic"] == targets, outputs[arm] == targets
            scores[arm]["strata"][name] = {"queryExposures": int(mask.sum()), "correct": int((correct & mask).sum()),
                "gains": int((~base & correct & mask).sum()), "harms": int((base & ~correct & mask).sum())}
    return scores


def ensure_training_scope(plans, roles):
    core.validate_saved_plans(plans, roles)
    require(len(roles["metaFitWriters"]) == 8 and all(w.startswith("trn_") for w in roles["metaFitWriters"])
        and all(p["writer"] in roles["metaFitWriters"] for p in plans), "Meta-fit training writers only")


def summarize(predictions, prepared, plans, rows):
    require(len(predictions) == len(prepared) == len(plans), "Training exposure order changed")
    cells, source_cells = defaultdict(list), defaultdict(list)
    for prediction, tensors, plan in zip(predictions, prepared, plans):
        generic, cache, _, targets, taught = tensors
        scored = score_episode(prediction, generic, cache, targets, taught)
        for key in ("all", f'{plan["writer"]}:K{len(plan["support"])}',
                    f'{plan["writer"]}:K{len(plan["support"])}:S{plan["session"]}'):
            cells[key].append(scored)
            source_cells[key].append(plan)
    summary = {}
    for key, episodes in sorted(cells.items()):
        summary[key] = {arm: {"episodes": len(episodes),
            "meanEpisodeBalancedNLL": float(np.mean([e[arm]["balancedNLL"] for e in episodes])),
            "strata": {name: {field: sum(e[arm]["strata"][name][field] for e in episodes)
                for field in ("queryExposures", "correct", "gains", "harms")}
                for name in ("all", "taught", "untaught")}} for arm in ARMS}
    return {"counts": source_counts(plans, rows), "matchedScores": summary,
        "sourceCountsByWriterTaskAndDirection": {key: source_counts(value, rows)
            for key, value in sorted(source_cells.items()) if key != "all"}}


def source_counts(plans, rows):
    scheduled = [i for p in plans for i in p["scheduledQueries"]]
    eligible = [i for p in plans for i in p["queries"]]
    excluded = [e["index"] for p in plans for e in p["exclusions"]]
    unavailable = [e["index"] for p in plans for e in p["unavailableSetup"]]
    reasons = Counter(reason for p in plans for e in p["exclusions"] for reason in e["reasons"])
    counts = {"episodes": len(plans), "scheduledQueryExposures": len(scheduled), "eligibleQueryExposures": len(eligible),
        "excludedQueryExposures": len(excluded), "unavailableSetupExposures": len(unavailable),
        "distinctScheduledSourceIndices": len(set(scheduled)), "distinctEligibleSourceIndices": len(set(eligible)),
        "distinctExcludedSourceIndices": len(set(excluded)), "distinctUnavailableSetupIndices": len(set(unavailable)),
        "repeatedEligibleSourceExposures": len(eligible) - len(set(eligible)), "exclusionReasonExposures": dict(sorted(reasons.items())),
        "distinctEligibleJointInkFingerprints": len({(rows[i]["rawRasterSHA256"], rows[i]["trajectorySHA256"]) for i in eligible}),
        "physicalSampleIndependenceEstablished": False,
        "sourceExposureMultiplicityHistograms": {name: {str(n): count for n, count in sorted(Counter(Counter(indices).values()).items())}
            for name, indices in (("scheduled", scheduled), ("eligible", eligible), ("excluded", excluded), ("unavailableSetup", unavailable))}}
    require(counts["scheduledQueryExposures"] == counts["eligibleQueryExposures"] + counts["excludedQueryExposures"],
        "Training denominator changed")
    return counts


def learner_identity(directory):
    names = ("fit-receipt.json", "weights.pt", "episode-plan.json", "fit-plan.json", "code-before.json",
        "parent-binding.json", "role-manifest.json", "protocol.md")
    return {name: sha(_regular_file(Path(directory) / name, "frozen learner input").read_bytes()) for name in names}


def run(crossfit, manifest, learner, output):
    crossfit, manifest, learner, output = map(Path, (crossfit, manifest, learner, output))
    require(Path(__file__).resolve().parents[3] not in output.parents
        and not any(path == output or path in output.parents for path in (crossfit, learner)), "New outside-repo output only")
    code, parent_before, learner_before = code_identity(), core.input_identity(crossfit), learner_identity(learner)
    require(learner_before["weights.pt"] == WEIGHTS_SHA256 and learner_before["fit-receipt.json"] == RECEIPT_SHA256,
        "Only the frozen final conditional learner may be diagnosed")
    manifest_before = sha(_regular_file(manifest, "training-role manifest").read_bytes())
    arrays, rows, parent, roles = core.load_parent(crossfit, manifest)
    final, receipt = core.load_fitted_learner(learner)
    require(receipt["parentBinding"] == parent_before and receipt["roleManifest"] == roles
        and manifest_before == core.ROLE_SHA256, "Matched training parents changed")
    plans = json.loads(_regular_file(learner / "episode-plan.json", "retained fit plans").read_bytes())
    ensure_training_scope(plans, roles)
    require(plans == core.episode_plan(rows, parent["vocabulary"], roles["metaFitWriters"], epochs=30, seed=41),
        "Retained fit plan changed")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    prepared = core.prepare_training(arrays, rows, parent["vocabulary"], plans, roles["sourceIndices"]["metaFit"])
    initial = core.ConditionalSupportTrust().eval()
    states = (_state_digest(final.state_dict()), _state_digest(initial.state_dict()))
    require(states[0] == receipt["finalStateSHA256"] and states[1] == receipt["initialStateSHA256"], "Fixed gate states changed")
    predictions = [predict_episode(*tensors[:3], final, initial) for tensors in prepared]
    packet = {"version": VERSION, "trainingOnly": True, "freshValidation": False, "optimizationPerformed": False,
        "internalValidationInferred": False, "productionEligible": False, "codeSHA256": code,
        "parentBinding": parent_before, "learnerBinding": learner_before, "roleManifestSHA256": manifest_before,
        "gateStateSHA256": {"initialGate": states[1], "finalGate": states[0]}, "plans": plans, "predictions": predictions}
    output = _new_output(output)
    frozen = canonical(packet)
    _write_exclusive(output / "predictions.json", frozen)
    # The supervised scorer receives targets only after exact bytes are saved.
    require((output / "predictions.json").read_bytes() == frozen, "Training prediction freeze failed")
    restored = json.loads(frozen)
    score = summarize(restored["predictions"], prepared, plans, rows)
    require(code_identity() == code and core.input_identity(crossfit) == parent_before
        and learner_identity(learner) == learner_before and sha(manifest.read_bytes()) == manifest_before
        and states == (_state_digest(final.state_dict()), _state_digest(initial.state_dict())), "Inputs/code/weights changed during diagnosis")
    report = {"version": VERSION, "trainingOnly": True, "freshValidation": False, "optimizationPerformed": False,
        "selectionPerformed": False, "internalValidationInferred": False, "productionEligible": False,
        "predictionSHA256": sha(frozen), "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code,
        "unchangedInputsAndWeightsVerified": True, **score}
    _write_exclusive(output / "training-score.json", canonical(report))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("crossfit", "manifest", "learner", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    result = run(args.crossfit, args.manifest, args.learner, args.output)
    print(json.dumps({"trainingOnly": True, "predictionSHA256": result["predictionSHA256"], "counts": result["counts"]}), flush=True)
