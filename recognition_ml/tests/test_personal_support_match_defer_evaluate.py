"""Synthetic numerical/paired-row checks; no corpus or fitted model is opened."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from torch import nn

from ichart_recognition_ml.research import personal_support_match_defer_evaluate as e


def row(**changes):
    result = {"direction": "A16-to-B16", "catalog": "core10", "writer": "writer1", "querySession": 1,
        "episodeID": "e1", "queryPosition": 0, "sourceIndex": 0, "intended": "C", "inDomain": True,
        "cohort": "taught", "copyReasons": [], "invalid": False, "control": "C", "generic": None,
        "personal": "C", "wrongSupport": None, "trueRoute": "explicit-support", "wrongRoute": "generic"}
    return result | changes


def passing_rows():
    return [row(), row(sourceIndex=1, queryPosition=1, intended="D", cohort="untaught", control=None,
                       generic="D", personal="D", wrongSupport="D", trueRoute="generic"),
            row(sourceIndex=2, queryPosition=2, intended="H", inDomain=False, cohort="untaught",
                control=None, generic=None, personal=None, trueRoute="generic")]


def synthetic_forward():
    vocabulary = ["C", "D", "H"] + [chr(0x400 + i) for i in range(94)]
    ledger = [{"sourceIndex": i, "sourceKey": e.sha(f"source{i}".encode()), "writer": "writer1" if i < 4 else "writer2",
        "session": 1 if i < 3 else 2, "rawRasterSHA256": e.sha(f"raw{i}".encode()), "trajectorySHA256": e.sha(f"ink{i}".encode()),
        "storedRasterSHA256": e.sha(f"stored{i}".encode()), "storedTrajectorySHA256": e.sha(f"storedInk{i}".encode()), "storedFailure": None} for i in range(5)]
    def episode(support_index):
        s = {**ledger[support_index], "slot": 0, "label": "C", "sourceID": f"support{support_index}"}
        return {"episodeID": "e1", "writer": "writer1", "querySession": 1, "supportSession": 2,
            "supportWriter": s["writer"], "catalog": "core10", "support": [s], "querySourceIndices": [0, 1, 2],
            "availableSupportRows": 1, "availablePrototypeLabels": ["C"], "requestedSupportLabels": ["C"], "profileUsable": True}
    pair = {"trueSupport": episode(3), "wrongSupport": episode(4), "availableLabelSetsEqual": True}
    return {"version": e.plan.VERSION, "protocolSHA256": e.PROTOCOL_SHA256, "vocabulary": vocabulary,
        "allowedLabels": ["C", "D"], "sourceLedger": ledger, "catalogs": {"core10": ["C"]},
        "bindings": {"sourceSHA256": "1" * 64, "domainSHA256": "2" * 64},
        "forward": {"A16-to-B16": {"heldoutWriters": ["writer1"], "heldoutEpisodes": [pair], "trainingEpisodes": []}}}


def packet_fixture():
    forward = synthetic_forward()
    def context(arm, wrong=False):
        labels = ["C", "C", "H"] if arm == "genericCEControl" else ["H", "D", "H"]
        logits = [[5.0 if label == v else -2.0 for v in forward["vocabulary"]] for label in labels]
        raw, generic = e.projected(logits, forward["vocabulary"], forward["allowedLabels"])
        scores = ([[0.0, 1.0]] * 3 if wrong else [[1.0, 0.0], [0.0, 1.0], [0.0, 1.0]]) if arm == "jointMatchDefer" else None
        support_labels = ["C"] if arm == "jointMatchDefer" else []
        kinds, selected, personal = e.route(scores, support_labels, generic, forward["allowedLabels"])
        unit = [1.0] + [0.0] * 127
        return {"failure": None, "matcherActive": arm == "jointMatchDefer", "genericLogits": logits,
            "genericRawTop1": raw, "genericDomainTop1": generic, "route": kinds, "selectedSupportLabel": selected,
            "personalDomainTop1": personal, "queryEmbeddings": [unit] * 3, "supportEmbeddings": [unit],
            "prototypeLabels": support_labels, "prototypes": [unit] if support_labels else [], "matchDeferLogits": scores}
    frozen = {"direction": "A16-to-B16", "episodeID": "e1", "sourcePlan": forward["forward"]["A16-to-B16"]["heldoutEpisodes"][0],
        "results": {a: {c: context(a, c == "wrongSupport") for c in e.CONTEXTS} for a in e.ARMS},
        "deterministicReplayEqual": True, "genericContextInvariant": True}
    runtime = {"cpuThreads": 4, "deterministicAlgorithms": True, "batchNormalizationUpdates": 0}
    packet = {"version": e.VERSION, "protocolSHA256": e.PROTOCOL_SHA256,
        "bindings": {"forwardPlanSHA256": e.sha(e.canonical(forward)), **forward["bindings"], "runtimeSHA256": e.sha(e.canonical(runtime))},
        "vocabulary": forward["vocabulary"], "allowedLabels": forward["allowedLabels"], "episodes": [frozen], "runtime": runtime,
        "scope": {k: False for k in ("productionEligible", "freshValidation", "naturalChordAccuracyMeasured",
                  "developmentOrReservedInferencePerformed", "privateInkUsed", "queryTruthRead")}}
    truth = {"version": e.data.TRUTH_VERSION, "sourceSHA256": forward["bindings"]["sourceSHA256"],
        "forwardPlanSHA256": e.sha(e.canonical(forward)), "rows": [{"sourceIndex": i, "intended": label} for i, label in enumerate(["C", "D", "H", "C", "C"])]}
    ledger = {"A16-to-B16": {"queryRows": [{"episodeID": "e1", "queryPosition": i, "sourceIndex": i,
        "reasons": ["true-support-raw-raster-copy"] if i == 0 else []} for i in range(3)]}}
    return packet, forward, truth, ledger


class TinyEncoder(nn.Module):
    def __init__(self):
        super().__init__(); self.calls = 0
        self.register_buffer("unchanged", torch.tensor(1.0))

    def forward(self, rasters):
        self.calls += 1
        features = torch.zeros((len(rasters), 128)); features[:, 0] = 1
        logits = torch.zeros((len(rasters), 97)); logits[:, 0] = 2
        return features, logits


class MatchDeferEvaluationTests(unittest.TestCase):
    def test_actual_raw_winner_and_strict_ties_never_promote_or_alias(self):
        raw, domain = e.projected([[8, 7, 6]], ["ñ", "C", "D"], ["C", "D"])
        self.assertEqual(raw, ["ñ"]); self.assertEqual(domain, [None])
        kinds, labels, outputs = e.route([[2, 2], [1, 2], [3, 2]], ["C"], ["D", None, None], ["C", "D"])
        self.assertEqual(kinds, ["generic", "generic", "explicit-support"])
        self.assertEqual(labels, [None, None, "C"]); self.assertEqual(outputs, ["D", None, "C"])
        with self.assertRaises(ValueError): e.route([[3, 2]], ["ñ"], [None], ["C"])
        with self.assertRaises(ValueError): e.projected([[float("nan"), 0]], ["C", "D"], ["C"])

    def test_every_predeclared_safety_gate_has_a_counterexample(self):
        baseline, evidence = passing_rows(), {"e1": {"valid": True, "sameAvailability": True}}
        self.assertTrue(e.fixed_screen(baseline, evidence)["passes"])
        cases = {
            "genericDomainNonnegativeNet": baseline[:1] + baseline[2:],
            "genericNoNewOutOfDomainOutput": baseline + [row(intended="H", inDomain=False, control=None, generic="C", personal="C")],
            "genericNoCorrectOrNoReadToWrong": baseline + [row(control=None, generic="D")],
            "personalNoCorrectOrNoReadToWrong": baseline + [row(control=None, generic=None, personal="D")],
            "personalStrictlyPositiveDomainNet": [r | {"personal": r["generic"]} for r in baseline],
            "zeroUntaughtDomainHarms": baseline + [row(cohort="untaught", generic="C", personal=None)],
            "everyWriterNonnegativePersonalNet": baseline + [row(writer="writer2", episodeID="e2", generic="C", personal=None),
                row(writer="writer2", episodeID="e2", cohort="untaught", intended="D", generic="D", personal="D")],
            "trueSupportFinalCorrectBeatsFixedWrongSupport": [r | {"wrongSupport": r["personal"]} for r in baseline],
            "personalNoNewOutOfDomainOutput": baseline + [row(intended="H", inDomain=False, generic=None, personal="C")],
            "completeFiniteDeterministicEvidence": [r | {"invalid": True} for r in baseline],
            "eligibleTaughtUntaughtEveryEpisode": baseline[:1],
        }
        for gate, rows in cases.items():
            ev = evidence | ({"e2": {"valid": True, "sameAvailability": True}} if gate == "everyWriterNonnegativePersonalNet" else {})
            with self.subTest(gate=gate): self.assertFalse(e.fixed_screen(rows, ev)["gates"][gate])
        self.assertFalse(e.fixed_screen(baseline, {"e1": {"valid": True, "sameAvailability": False}})["gates"]["equalAvailableLabelsEveryEpisode"])
        self.assertFalse(e.fixed_screen(baseline, {"e1": {"valid": False, "sameAvailability": True}})["gates"]["completeFiniteDeterministicEvidence"])

    def test_explicit_match_counts_cannot_fake_true_writer_final_output_benefit(self):
        rows = passing_rows()
        rows[0]["wrongSupport"] = "C"  # wrong support DEFER is already correct
        self.assertGreater(e.summarize(rows)["trueRoutedCorrect"], e.summarize(rows)["wrongRoutedCorrect"])
        self.assertFalse(e.fixed_screen(rows, {"e1": {"valid": True, "sameAvailability": True}})["gates"]["trueSupportFinalCorrectBeatsFixedWrongSupport"])

    def test_raw_no_copy_pairing_failures_and_all_cohort_denominators(self):
        packet, forward, truth, ledgers = packet_fixture()
        report = e.score_packet(packet, forward, truth, ledgers)
        views = report["results"]["A16-to-B16"]["core10"]
        self.assertEqual(report["exposures"], 3); self.assertEqual(report["distinctSources"], 3)
        self.assertTrue(views["raw"]["screen"]["passes"])
        self.assertEqual(views["noCopy"]["exposures"], 2); self.assertEqual(views["noCopy"]["excludedCopyExposures"], 1)
        self.assertFalse(report["passesFixedScreen"])
        for view in views.values():
            self.assertEqual(sum(v["exposures"] for v in view["strata"].values()), view["exposures"])
            self.assertEqual(sum(v["exposures"] for v in view["writers"].values()), view["exposures"])
            self.assertEqual(sum(v["exposures"] for v in view["domainStrata"].values()), view["exposures"])
            for out in view["outputs"].values(): self.assertEqual(sum(out.values()), view["exposures"])
        broken = copy.deepcopy(packet)
        for a in e.ARMS:
            for c in e.CONTEXTS: broken["episodes"][0]["results"][a][c] = e.failed_context(3, a, ValueError("synthetic technical failure"))
        broken["episodes"][0]["genericContextInvariant"] = False; broken["episodes"][0]["deterministicReplayEqual"] = False
        failed = e.score_packet(broken, forward, truth, ledgers)["results"]["A16-to-B16"]["core10"]["raw"]
        self.assertEqual(failed["exposures"], 3); self.assertEqual(failed["invalidRows"], 3)
        self.assertFalse(failed["screen"]["passes"])

    def test_bound_schedule_top1_truth_and_paired_ledger_tampering_rejects(self):
        packet, forward, truth, ledgers = packet_fixture()
        for change in (lambda p: p["bindings"].update(forwardPlanSHA256="0" * 64),
                       lambda p: p["episodes"].append(copy.deepcopy(p["episodes"][0])),
                       lambda p: p["episodes"][0]["results"]["jointMatchDefer"]["trueSupport"]["personalDomainTop1"].__setitem__(0, "D")):
            bad = copy.deepcopy(packet); change(bad)
            with self.assertRaises(ValueError): e.score_packet(bad, forward, truth, ledgers)
        bad_truth = copy.deepcopy(truth); bad_truth["rows"][0]["sourceIndex"] = True
        with self.assertRaises(ValueError): e.score_packet(packet, forward, bad_truth, ledgers)
        bad_ledger = copy.deepcopy(ledgers); bad_ledger["A16-to-B16"]["queryRows"][1]["sourceIndex"] = 0
        with self.assertRaises(ValueError): e.score_packet(packet, forward, truth, bad_ledger)

    def test_synthetic_single_concat_eval_replay_never_opens_truth_and_does_not_mutate_state(self):
        forward = synthetic_forward(); models = {}
        for a in e.ARMS:
            model = e.core.PersonalSupportMatchDeferModel(); model.encoder = TinyEncoder(); model.eval()
            models[a] = model
        arrays = {"raw_rasters": np.zeros((5, 1, 96, 256), np.uint8),
                  "stored_rasters": np.zeros((2, 1, 96, 256), np.uint8), "stored_source_indices": np.array([3, 4], np.int64)}
        before = {a: e.state_sha(m) for a, m in models.items()}
        with patch.object(Path, "read_bytes", side_effect=AssertionError("No labels, targets, metadata, or scoring ledger may be opened")):
            frozen = e.freeze_forward({"A16-to-B16": models}, forward, arrays)
        self.assertEqual(len(frozen), 1); self.assertTrue(frozen[0]["deterministicReplayEqual"])
        self.assertTrue(frozen[0]["genericContextInvariant"])
        self.assertEqual(before, {a: e.state_sha(m) for a, m in models.items()})
        for a, model in models.items():
            self.assertEqual(model.encoder.calls, 4, "Two support contexts, one concatenated encode per replay")
            for c in e.CONTEXTS:
                result = frozen[0]["results"][a][c]
                self.assertEqual(np.asarray(result["genericLogits"]).shape, (3, 97))
                if a == "genericCEControl":
                    self.assertFalse(result["matcherActive"]); self.assertIsNone(result["matchDeferLogits"])
                    self.assertEqual(result["personalDomainTop1"], result["genericDomainTop1"])

    def test_pooling_provenance_and_prototypes_are_exactly_the_training_contract(self):
        forward = synthetic_forward(); episode = forward["forward"]["A16-to-B16"]["heldoutEpisodes"][0]["trueSupport"]
        model = e.core.PersonalSupportMatchDeferModel(); model.encoder = TinyEncoder(); model.eval()
        arrays = {"raw_rasters": np.zeros((5, 1, 96, 256), np.uint8), "stored_rasters": np.zeros((2, 1, 96, 256), np.uint8)}
        s = episode["support"][0]; original = e.core.pool_confirmed_support
        with torch.inference_mode(), patch.object(e.core, "pool_confirmed_support", wraps=original) as called:
            result = e.predict_episode(model, episode, arrays, {3: 0, 4: 1}, forward["vocabulary"], forward["allowedLabels"], arm="jointMatchDefer")
        args = called.call_args.args
        self.assertEqual(args[2], [s["sourceID"]]); self.assertEqual(args[3], [s["storedTrajectorySHA256"]])
        self.assertEqual(args[4], [s["storedRasterSHA256"]])
        reference = original(args[0], [s["label"]], [s["sourceID"]], [s["storedTrajectorySHA256"]], [s["storedRasterSHA256"]], lambda label: label in forward["allowedLabels"])
        self.assertEqual(reference.source_hashes, ((s["storedTrajectorySHA256"],),))
        self.assertEqual(reference.ink_hashes, ((s["storedRasterSHA256"],),))
        self.assertEqual(result["prototypes"], reference.prototypes.tolist())

    def test_prediction_sha_is_checked_before_any_truth_or_source_read_and_outputs_are_exclusive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve(); prediction = root / "predictions.json"
            prediction.write_bytes(e.canonical({"version": e.VERSION}))
            with patch.object(e.data, "load_forward_plan", side_effect=AssertionError("Must authenticate predictions first")):
                with self.assertRaises(ValueError): e.score(prediction, root, root, root / "score.json", predictions_sha256="0" * 64)
            output = root / "new.json"; digest = e.write_exclusive(output, {"frozen": True})
            self.assertEqual(e.sha(output.read_bytes()), digest)
            original = output.read_bytes()
            with self.assertRaises(ValueError): e.write_exclusive(output, {"frozen": False})
            self.assertEqual(output.read_bytes(), original)
            with self.assertRaises(ValueError): e.write_exclusive(root / "inside-source.json", {}, (root,))


if __name__ == "__main__":
    unittest.main()
