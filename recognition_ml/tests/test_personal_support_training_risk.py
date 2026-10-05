import copy
import inspect
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import torch

from ichart_recognition_ml.research import personal_conditional_support_trust as core
from ichart_recognition_ml.research import personal_support_training_risk as risk


class TrainingRiskTests(unittest.TestCase):
    def setUp(self):
        torch.set_num_threads(2)
        self.generic = torch.zeros(4, 97, dtype=torch.float64)
        self.generic[:, 0] = torch.tensor([.8, .4, .1, .7])
        self.generic[:, 1] = 1 - self.generic[:, 0]
        self.cache = torch.zeros_like(self.generic)
        self.cache[:, 0] = 1
        self.scalars = torch.randn(4, 14, dtype=torch.float64, generator=torch.Generator().manual_seed(8))
        self.targets = torch.tensor([0, 0, 1, 1])
        self.taught = torch.tensor([True, True, False, False])
        self.initial, self.final = core.ConditionalSupportTrust().eval(), core.ConditionalSupportTrust().eval()
        with torch.no_grad():
            self.final.gate[-1].weight.fill_(.03)
            self.final.gate[-1].bias.fill_(2.)

    def prediction(self):
        return risk.predict_episode(self.generic, self.cache, self.scalars, self.final, self.initial)

    def test_real_nonzero_gate_outputs_frozen_full97_and_unchanged_weights(self):
        states = tuple(core._state_digest(m.state_dict()) for m in (self.final, self.initial))
        output = self.prediction()
        self.assertEqual(set(output), set(risk.ARMS))
        self.assertEqual(output["generic"]["top1"], [0, 1, 1, 0])
        self.assertEqual(output["finalGate"]["top1"], [0, 0, 0, 0])
        self.assertTrue(all(g > .5 for g in output["finalGate"]["gate"]))
        self.assertTrue(all(0 < g < .2 for g in output["initialGate"]["gate"]))
        self.assertNotEqual(output["initialGate"]["full97ProbabilitySHA256"], output["finalGate"]["full97ProbabilitySHA256"])
        self.assertEqual(states, tuple(core._state_digest(m.state_dict()) for m in (self.final, self.initial)))
        json.loads(risk.canonical(output))

    def test_prediction_has_no_targets_answers_or_optimizer(self):
        self.assertEqual(tuple(inspect.signature(risk.predict_episode).parameters),
            ("generic", "cache", "scalars", "final_model", "initial_model"))
        names = (*risk.predict_episode.__code__.co_varnames, *risk.predict_episode.__code__.co_names)
        for forbidden in ("targets", "taught", "optimizer", "backward", "balanced_loss"):
            self.assertNotIn(forbidden, names)
        packet = self.prediction()
        a = risk.score_episode(packet, self.generic, self.cache, self.targets, self.taught)
        b = risk.score_episode(packet, self.generic, self.cache, 1 - self.targets, self.taught)
        self.assertNotEqual(a, b)
        self.assertEqual(packet, self.prediction())

    def test_separate_training_arithmetic_balanced_loss_gains_and_harms(self):
        scores = risk.score_episode(json.loads(risk.canonical(self.prediction())), self.generic, self.cache, self.targets, self.taught)
        self.assertEqual(scores["generic"]["strata"]["all"], {"queryExposures": 4, "correct": 2, "gains": 0, "harms": 0})
        self.assertEqual(scores["finalGate"]["strata"]["taught"], {"queryExposures": 2, "correct": 2, "gains": 1, "harms": 0})
        self.assertEqual(scores["finalGate"]["strata"]["untaught"], {"queryExposures": 2, "correct": 0, "gains": 0, "harms": 1})
        expected = float(core.balanced_loss(self.generic, self.targets, self.taught))
        self.assertEqual(scores["generic"]["balancedNLL"], expected)
        for position in ("top1", "gate", "full97ProbabilitySHA256"):
            changed = self.prediction()
            if position == "top1": changed["finalGate"][position][0] = 96
            elif position == "gate": changed["finalGate"][position][0] = .5
            else: changed["finalGate"][position] = "0" * 64
            with self.assertRaises(ValueError): risk.score_episode(changed, self.generic, self.cache, self.targets, self.taught)

    def test_repeated_exposures_not_distinct_samples_and_writer_task_cells(self):
        prediction = self.prediction()
        prepared = (self.generic, self.cache, self.scalars, self.targets, self.taught)
        plans = [{"writer": "trn_UJI_W00", "session": 1, "support": list(range(k)),
            "scheduledQueries": [0, 1, 2, 3, 4], "queries": [0, 1, 2, 3],
            "exclusions": [{"index": 4, "reasons": ["generic-fit-raw-raster-copy"]}],
            "unavailableSetup": [{"index": 5, "failure": "PersonalInkShape-unavailable"}]} for k in (10, 21, 10)]
        rows = [{"rawRasterSHA256": f"p{i}", "trajectorySHA256": f"t{i}"} for i in range(6)]
        rows[1] = dict(rows[0])  # Two source rows need not be independent physical ink.
        report = risk.summarize([prediction] * 3, [prepared] * 3, plans, rows)
        counts = report["counts"]
        self.assertEqual(counts["scheduledQueryExposures"], 15)
        self.assertEqual(counts["eligibleQueryExposures"], 12)
        self.assertEqual(counts["excludedQueryExposures"], 3)
        self.assertEqual(counts["distinctEligibleSourceIndices"], 4)
        self.assertEqual(counts["repeatedEligibleSourceExposures"], 8)
        self.assertEqual(counts["distinctEligibleJointInkFingerprints"], 3)
        self.assertIs(counts["physicalSampleIndependenceEstablished"], False)
        self.assertEqual(counts["sourceExposureMultiplicityHistograms"]["eligible"], {"3": 4})
        self.assertEqual(counts["distinctUnavailableSetupIndices"], 1)
        self.assertEqual(report["matchedScores"]["trn_UJI_W00:K10"]["finalGate"]["strata"]["all"]["gains"], 2)
        self.assertEqual(report["matchedScores"]["all"]["finalGate"]["strata"]["untaught"]["harms"], 3)
        source_cell = report["sourceCountsByWriterTaskAndDirection"]["trn_UJI_W00:K10:S1"]
        self.assertEqual(source_cell["scheduledQueryExposures"], 10)
        self.assertEqual(source_cell["distinctEligibleSourceIndices"], 4)
        self.assertEqual(source_cell["sourceExposureMultiplicityHistograms"]["eligible"], {"2": 4})
        self.assertEqual(report["matchedScores"]["all"]["generic"]["meanEpisodeBalancedNLL"],
            risk.score_episode(prediction, self.generic, self.cache, self.targets, self.taught)["generic"]["balancedNLL"])
        json.loads(risk.canonical(report))

    def test_probability_byte_encoding_and_frozen_recipe_binding(self):
        packet = self.prediction()
        self.assertEqual(packet["generic"]["probabilityEncoding"], "float64-le-row-major")
        self.assertEqual(packet["generic"]["full97Shape"], [4, 97])
        self.assertEqual(packet["generic"]["full97ProbabilitySHA256"],
            risk.sha(self.generic.numpy().astype("<f8", copy=False).tobytes(order="C")))
        changed = copy.deepcopy(packet); changed["generic"]["probabilityEncoding"] = "float32"
        with self.assertRaises(ValueError): risk.score_episode(changed, self.generic, self.cache, self.targets, self.taught)
        self.assertEqual(risk.code_identity()[risk.PROTOCOL], risk.PROTOCOL_SHA256)
        self.assertEqual(len(risk.WEIGHTS_SHA256), 64)
        self.assertEqual(len(risk.RECEIPT_SHA256), 64)

    def test_training_scope_accepts_only_meta_fit_grid(self):
        writers = [f"trn_UJI_W{i:02}" for i in range(8)]
        rows = [{"writer": w, "session": s, "label": chr(33 + c), "generator": "fitA",
            "rawRasterSHA256": f"raw{w}{s}{c}", "storedRasterSHA256": f"stored{w}{s}{c}",
            "trajectorySHA256": f"ink{w}{s}{c}", "storedTrajectorySHA256": f"setup{w}{s}{c}",
            "storedFailure": None, "genericFitCopyReasons": []} for w in writers for s in (1, 2) for c in range(97)]
        plans = core.episode_plan(rows, [chr(33 + c) for c in range(97)], writers, epochs=30, seed=41)
        roles = {"sourceIndices": {"metaFit": list(range(1552)), "internalValidation": list(range(1552, 3104))},
            "metaFitWriters": writers, "internalValidationWriters": [f"trn_UPV_W{i:02}" for i in range(8)],
            "encoderFitWriters": [f"trn_UJI_W{i:02}" for i in range(8, 24)]}
        risk.ensure_training_scope(plans, roles)
        broken = copy.deepcopy(plans); broken[0]["writer"] = roles["internalValidationWriters"][0]
        with self.assertRaises(ValueError): risk.ensure_training_scope(broken, roles)
        broken = copy.deepcopy(plans); broken[0]["queries"][0] = 1552
        with self.assertRaises(ValueError): risk.ensure_training_scope(broken, roles)

    def test_invalid_full97_or_scalar_matrices_and_learner_input_tamper(self):
        for generic, cache, scalars in ((self.generic[:, :2], self.cache[:, :2], self.scalars),
            (self.generic, self.cache, self.scalars.float()), (self.generic * .5, self.cache, self.scalars)):
            with self.assertRaises(ValueError): risk.predict_episode(generic, cache, scalars, self.final, self.initial)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            names = ("fit-receipt.json", "weights.pt", "episode-plan.json", "fit-plan.json", "code-before.json",
                "parent-binding.json", "role-manifest.json", "protocol.md")
            for name in names: (directory / name).write_bytes(b"synthetic only")
            before = risk.learner_identity(directory)
            (directory / "weights.pt").write_bytes(b"changed")
            self.assertNotEqual(before, risk.learner_identity(directory))


if __name__ == "__main__":
    unittest.main()
