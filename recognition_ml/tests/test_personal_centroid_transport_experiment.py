"""Synthetic fitting, leakage and denominator gates; no real corpus opened."""
import copy
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_centroid_transport_experiment as experiment
from ichart_recognition_ml.research import personal_centroid_transport as core


def source_fixture():
    vocabulary = sorted(set(experiment.TASKS["catalog21"]) | {chr(1000 + i) for i in range(76)})
    writers = [f"trn_UPV_W{i:02d}" for i in range(1, 33)]
    rows = []
    for writer in writers:
        for session in (1, 2):
            for label in vocabulary:
                identity = f"{writer}-{session}-{label}"
                raster, trajectory = (experiment.sha((identity + suffix).encode()) for suffix in (":raster", ":trajectory"))
                rows.append({"sourceID": identity, "writer": writer, "session": session, "label": label,
                    "rawRasterSHA256": raster, "storedRasterSHA256": raster, "trajectorySHA256": trajectory,
                    "storedTrajectorySHA256": trajectory, "storedFailure": None, "generator": "fitB" if writer in writers[:16] else "fitA"})
    roles = {"metaFitWriters": writers[16:24], "encoderFitWriters": writers[:16], "internalValidationWriters": writers[24:],
        "generator": "fitA", "generatorWeightsSHA256": experiment.GENERATOR_SHA256, "freshValidation": False,
        "sourceIndices": {"metaFit": [i for i, r in enumerate(rows) if r["writer"] in writers[16:24]],
                          "internalValidation": [i for i, r in enumerate(rows) if r["writer"] in writers[24:]]}}
    owners = {str(i): {k: rows[i][k] for k in ("writer", "session", "generator")} for i in roles["sourceIndices"]["metaFit"]}
    return vocabulary, rows, roles, owners


def synthetic_tensors():
    generator = torch.Generator().manual_seed(17)
    unit = lambda count: torch.nn.functional.normalize(torch.randn(count, 8, generator=generator, dtype=torch.float64), dim=1)
    centroids, support, query, unrelated = unit(97), unit(10), unit(4), unit(10)
    logits = torch.randn(4, 97, generator=generator, dtype=torch.float64)
    labels, targets = torch.arange(10), torch.tensor([0, 1, 11, 12])
    return centroids, support, labels, query, logits, unrelated, targets, torch.tensor([True, True, False, False])


class CentroidTransportExperimentTests(unittest.TestCase):
    def test_current_core_execution_and_centroid_helper_identity(self):
        identity = experiment.code_identity()
        self.assertEqual(identity[experiment.EXECUTION], experiment.EXECUTION_SHA256)
        self.assertEqual(identity["recognition_ml/ichart_recognition_ml/research/personal_centroid_transport.py"], experiment.CORE_SHA256)
        self.assertEqual(identity["recognition_ml/tests/test_personal_centroid_transport.py"], experiment.CORE_TEST_SHA256)
        self.assertIn("recognition_ml/ichart_recognition_ml/research/personal_training_centroids.py", identity)

    def test_fixed_source_grid_catalog_and_bijective_derangements(self):
        vocabulary, rows, roles, owners = source_fixture()
        folds = experiment.source_folds(rows, vocabulary, roles)
        experiment.validate_folds(folds, vocabulary, roles, owners)
        self.assertEqual(folds, experiment.source_folds(rows, vocabulary, roles))
        self.assertEqual(sum(len(p["scheduledQueries"]) for f in folds for p in f["oofEpisodes"]), 3104)
        self.assertEqual(sum(len(f["updateEpisodeIndices"]) for f in folds), 6720)
        for fold in folds:
            self.assertEqual(len(fold["fitIndices"]), 1358)
            self.assertNotIn(fold["heldOutWriter"], fold["fitWriters"])
            for session in (1, 2):
                for task in experiment.TASKS:
                    selected = [p for p in fold["fitEpisodes"] if p["supportSession"] == session and p["task"] == task]
                    self.assertEqual({p["unrelatedWriter"] for p in selected}, set(fold["fitWriters"]))
                    self.assertTrue(all(p["writer"] != p["unrelatedWriter"] and p["supportLabels"] == list(experiment.TASKS[task]) for p in selected))
            self.assertTrue(all("targets" not in p for p in fold["fitEpisodes"] + fold["oofEpisodes"]))

    def test_complete_copy_union_and_unavailable_rows_are_frozen(self):
        vocabulary, rows, roles, _ = source_fixture(); initial = experiment.source_folds(rows, vocabulary, roles)
        p = initial[0]["oofEpisodes"][0]; index = p["scheduledQueries"][0]
        raster, trajectory = rows[index]["rawRasterSHA256"], rows[index]["trajectorySHA256"]
        references = [0, initial[0]["fitIndices"][0], p["support"][1], p["unrelatedSupport"][1]]
        for reference in references:
            rows[reference]["storedRasterSHA256"] = raster; rows[reference]["storedTrajectorySHA256"] = trajectory
        missing = next(i for i, r in enumerate(rows) if r["writer"] == p["writer"] and r["session"] == p["supportSession"] and r["label"] not in experiment.TASKS["catalog21"])
        rows[missing].update(storedRasterSHA256=None, storedTrajectorySHA256=None, storedFailure="synthetic-unavailable")
        p = experiment.source_folds(rows, vocabulary, roles)[0]["oofEpisodes"][0]
        self.assertEqual(next(e["reasons"] for e in p["exclusions"] if e["index"] == index), list(experiment.REASONS))
        self.assertNotIn(index, p["queries"]); self.assertIn(index, p["scheduledQueries"])
        self.assertIn({"index": missing, "failure": "synthetic-unavailable"}, p["unavailableSetup"])

    def test_missing_app_support_roles_and_plan_tampering_fail(self):
        vocabulary, rows, roles, owners = source_fixture(); folds = experiment.source_folds(rows, vocabulary, roles)
        for mutation in ("oof-donor", "boolean-index", "missing-update", "truth-in-forward-plan", "invalid-role"):
            changed, changed_roles = copy.deepcopy(folds), copy.deepcopy(roles)
            if mutation == "oof-donor": changed[0]["oofEpisodes"][0]["unrelatedWriter"] = changed[0]["heldOutWriter"]
            elif mutation == "boolean-index": changed[0]["oofEpisodes"][0]["scheduledQueries"][0] = True
            elif mutation == "missing-update": changed[0]["updateEpisodeIndices"].pop()
            elif mutation == "truth-in-forward-plan": changed[0]["oofEpisodes"][0]["targets"] = [0] * 97
            else: changed_roles["sourceIndices"]["internalValidation"][0] = changed_roles["sourceIndices"]["metaFit"][0]
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): experiment.validate_folds(changed, vocabulary, changed_roles, owners)
        unavailable = folds[0]["oofEpisodes"][0]["support"][0]
        rows[unavailable].update(storedFailure="missing", storedRasterSHA256=None, storedTrajectorySHA256=None)
        with self.assertRaisesRegex(ValueError, "support coverage|support unavailable"): experiment.source_folds(rows, vocabulary, roles)

    def test_actual_840_synthetic_updates_all_three_meaningful_blocks_and_reload(self):
        experiment.common.configure(); prepared = [synthetic_tensors()] * 28
        schedule = list(range(28)) * 30; model = core.CentroidTransport()
        receipt = experiment.train_head(model, prepared, schedule)
        self.assertEqual(receipt["updates"], 840); self.assertEqual(len(receipt["history"]), 30)
        self.assertEqual(sum(r["updates"] for r in receipt["history"]), 840)
        self.assertLessEqual(receipt["canceledFinalBiasDeltaNorm"], 1e-12)
        for name in ("scorer.0.weight", "scorer.0.bias", "scorer.2.weight"):
            self.assertGreater(receipt["parameterDeltaNorms"][name], 0); self.assertGreater(receipt["maximumAbsoluteGradients"][name], 0)
        binding = {"synthetic": True}; data = experiment.checkpoint(model, binding)
        restored = experiment.load_checkpoint(data, experiment.sha(data), binding)
        self.assertTrue(all(torch.equal(v, restored.state_dict()[k]) for k, v in model.state_dict().items()))
        with self.assertRaises(ValueError): experiment.load_checkpoint(data + b"x", experiment.sha(data), binding)
        with self.assertRaises(ValueError): experiment.load_checkpoint(data, experiment.sha(data), {"synthetic": False})
        with self.assertRaises(ValueError): experiment.train_head(core.CentroidTransport(), prepared, schedule[:-1])

    def test_forward_gets_only_five_tensors_and_invalid_rows_stay_scheduled(self):
        class Spy:
            def probabilities(self, *arguments):
                self.calls.append(arguments); result = arguments[-1].softmax(1); result[1, 0] = float("nan"); return result
            def __init__(self): self.calls = []
        values = synthetic_tensors(); centroids = values[0]
        tensors = {"stored_features": torch.cat((values[1], values[5])), "raw_features": values[3], "raw_logits": values[4]}
        remap = {i: i for i in range(20)}; p = {"support": list(range(10)), "unrelatedSupport": list(range(10, 20)),
            "supportLabelIndices": list(range(10)), "scheduledQueries": list(range(4))}
        spy = Spy(); result = experiment.predict_episode(spy, tensors, remap, p, centroids)
        self.assertEqual(len(spy.calls), 2); self.assertTrue(all(len(c) == 5 and all(isinstance(t, torch.Tensor) for t in c) for c in spy.calls))
        self.assertEqual([r["sourceIndex"] for r in result["rows"]], list(range(4)))
        self.assertIsNone(result["rows"][1]["candidateProbabilities"]); self.assertIsNotNone(result["rows"][1]["candidateFailure"])
        self.assertEqual(len(result["rows"][1]["genericProbabilities"]), 97)

    def test_feature_loader_never_opens_query_metadata_and_rejects_unauthorized_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); feature = np.zeros((1552, 128), np.float64); feature[:, 0] = 1
            np.savez(root / "meta-features.npz", source_indices=np.arange(3104, 4656), raw_features=feature,
                stored_features=feature, raw_logits=np.zeros((1552, 97), np.float64))
            for name in ("metadata.json", "truth.json", "features.npz"): (root / name).write_bytes(b"MUST NOT OPEN OR PARSE")
            original = experiment.read
            with patch.object(experiment, "read", side_effect=original) as reader:
                tensors, remap = experiment.feature_tensors(root, [3104, 3105], {3104, 3105})
                reader.assert_called_once_with(root / "meta-features.npz")
            self.assertEqual(tensors["raw_logits"].shape, (2, 97)); self.assertEqual(remap, {3104: 0, 3105: 1})
            with self.assertRaises(ValueError): experiment.feature_tensors(root, [3104, 20], {3104})

    def test_seven_writer_target_loader_is_pinned_and_cannot_reassign_indices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); fold = {"foldIndex": 0, "fitIndices": [1, 2]}
            data = experiment.canonical({"indices": [1, 2], "targets": [0, 96]}); (root / "fold-0-targets.json").write_bytes(data)
            binding = {"preparationPath": str(root), "trainingTargetsSHA256": [experiment.sha(data)]}
            self.assertEqual(experiment.training_targets(binding, fold), {1: 0, 2: 96})
            (root / "fold-0-targets.json").write_bytes(experiment.canonical({"indices": [1, 3], "targets": [0, 96]}))
            with self.assertRaises(ValueError): experiment.training_targets(binding, fold)

    def test_trust_gate_counts_failures_repeats_and_unrelated_controls(self):
        rows = []
        for task in experiment.TASKS:
            for n, (taught, generic, candidate, unrelated, exclusions) in enumerate(((True, False, True, False, []),
                    (False, True, True, True, []), (False, True, False, True, ["head-fit-raster-copy"]))):
                rows.append({"exposureID": f"{task}:{n}", "sourceIndex": n, "task": task, "writer": "w", "taught": taught,
                    "genericCorrect": generic, "candidateCorrect": candidate, "unrelatedCorrect": unrelated,
                    "supportSession": 1 if n != 2 else 2, "trueLabel": "A" if taught else "Ω",
                    "candidateFailure": "invalid" if not candidate else None, "unrelatedFailure": None, "exclusions": exclusions})
        tasks, passed = experiment.screen(rows, ["w"]); self.assertTrue(passed)
        self.assertEqual(tasks["core10"]["rawScheduled"]["queryExposures"], 3)
        self.assertEqual(tasks["core10"]["rawScheduled"]["invalidCandidate"], 1)
        self.assertEqual(experiment.summarize(rows)["distinctSourceIndices"], 3)
        self.assertEqual(experiment.summarize(rows)["repeatedExposures"], 3)
        self.assertEqual(tasks["core10"]["rawScheduled"]["supportSessions"]["1"]["queryExposures"], 2)
        self.assertEqual(tasks["core10"]["rawScheduled"]["writerSessions"]["w"]["2"]["excludedExposures"], 1)
        self.assertEqual(tasks["core10"]["rawScheduled"]["sourceDomains"]["nonAppStress"]["queryExposures"], 2)
        self.assertEqual(tasks["core10"]["sourceOnlyNoCopy"]["sourceDomains"]["appCatalog21"]["queryExposures"], 1)
        changed = copy.deepcopy(rows)
        for r in changed: r["unrelatedCorrect"] = r["candidateCorrect"]
        self.assertFalse(experiment.screen(changed, ["w"])[1])
        changed = copy.deepcopy(rows); changed[-1]["exclusions"] = []
        self.assertFalse(experiment.screen(changed, ["w"])[1])
        changed = copy.deepcopy(rows); changed[1]["candidateCorrect"] = False
        self.assertFalse(experiment.screen(changed, ["w"])[1])
        changed = copy.deepcopy(rows); changed[0].update(unrelatedFailure="broken-control", unrelatedCorrect=False)
        broken_tasks, passed = experiment.screen(changed, ["w"])
        self.assertTrue(all(broken_tasks["core10"]["sourceOnlyNoCopy"]["screenConditions"]))
        self.assertFalse(broken_tasks["core10"]["sourceOnlyNoCopy"]["validPredictionOutputs"])
        self.assertFalse(passed)

    def test_prediction_digest_gate_precedes_any_truth_or_metadata_read(self):
        predictions = Path("/private/tmp/synthetic-predictions.json")
        with patch.object(experiment, "read", return_value=b"{}") as reader:
            with self.assertRaisesRegex(ValueError, "SHA mismatch before truth"):
                experiment.score(predictions, "0" * 64, Path("/private/tmp/synthetic-score.json"))
            reader.assert_called_once_with(predictions)
        with patch.object(experiment, "read", return_value=b"{}") as reader:
            with self.assertRaisesRegex(ValueError, "SHA mismatch before fitting"):
                experiment.fit_predict(predictions, "0" * 64, Path("/private/tmp/synthetic-fit"))
            reader.assert_called_once_with(predictions)

    def test_prepared_pipeline_with_stubbed_optimizer_never_opens_oof_truth(self):
        vocabulary, rows, roles, _ = source_fixture(); feature = np.zeros((6208, 128), np.float32); feature[:, 0] = 1
        arrays = {"raw_features": feature, "stored_features": feature, "raw_logits": np.zeros((6208, 97), np.float32)}
        mu = torch.zeros(97, 128, dtype=torch.float64); mu[:, 0] = 1
        calls = []
        def optimizer_stub(model, prepared, schedule):
            # File/inference integration only; actual 840-step fitting is tested above.
            self.assertEqual(len(prepared), 28); self.assertEqual(len(schedule), 840); calls.append(1)
            initial = experiment._state_digest(model.state_dict())
            with torch.no_grad():
                for name, parameter in model.named_parameters():
                    if name != "scorer.2.bias": parameter.add_(.001)
            final = experiment._state_digest(model.state_dict())
            return {"history": [{"epoch": e + 1, "updates": 28, "learningRate": .001, "meanLoss": 1.,
                "balancedCE": 1., "preservationMargin": 0., "unrelatedSupportKL": 0.} for e in range(30)], "updates": 840,
                "parameterDeltaNorms": {k: 0. if k == "scorer.2.bias" else .001 for k in model.state_dict()},
                "maximumAbsoluteGradients": {k: 0. if k == "scorer.2.bias" else .001 for k in model.state_dict()},
                "initialStateSHA256": initial, "finalStateSHA256": final, "inputTensorSHA256": "3" * 64,
                "canceledFinalBiasDeltaNorm": 0., "canceledFinalBiasTolerance": 1e-12}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); parent_path = root / "parent"; parent_path.mkdir()
            centroid_path = root / "centroids"; centroid_path.mkdir(); centroid_receipt = b"{}"
            (centroid_path / "centroid-receipt.json").write_bytes(centroid_receipt)
            for name in ("metadata.json", "features.npz"): (parent_path / name).write_bytes(b"DO NOT READ AT FIT/PREDICT")
            role_path = root / "roles.json"; role_data = experiment.canonical(roles); role_path.write_bytes(role_data)
            centroid_identity = {"centroid-receipt.json": experiment.sha(centroid_receipt)}
            with patch.object(experiment.parent, "input_identity", return_value={"fixed-parent": "1" * 64}), \
                    patch.object(experiment.parent, "load_parent", return_value=(arrays, rows, {"vocabulary": vocabulary}, roles)), \
                    patch.object(experiment, "code_identity", return_value={"synthetic-code": "2" * 64}), \
                    patch.object(experiment, "load_centroids", return_value=(mu, centroid_identity)), \
                    patch.object(experiment, "ROLE_SHA256", experiment.sha(role_data)):
                prepared_path = root / "prepared"
                summary = experiment.prepare(parent_path, role_path, centroid_path, experiment.sha(centroid_receipt), prepared_path)
                truth = (prepared_path / "truth.json").read_bytes(); (prepared_path / "truth.json").write_bytes(b"OOF TRUTH MUST NOT OPEN")
                original = experiment.read
                def no_truth(path, *args):
                    self.assertNotIn(Path(path).name, ("truth.json", "metadata.json", "features.npz")); return original(path, *args)
                with patch.object(experiment, "train_head", side_effect=optimizer_stub), patch.object(experiment, "read", side_effect=no_truth):
                    fitted = experiment.fit_predict(prepared_path / "commitment.json", summary["commitmentSHA256"], root / "fit")
                self.assertEqual(len(calls), 8); self.assertEqual(fitted["scheduledExposures"], 3104)
                (prepared_path / "truth.json").write_bytes(truth)
                scored = experiment.score(root / "fit" / "predictions.json", fitted["predictionSHA256"], root / "score.json")
                self.assertEqual((scored["scheduledExposures"], scored["distinctSourceIndices"]), (3104, 1552))
                self.assertFalse(scored["passesFixedScreen"]); self.assertFalse(scored["finalB8FitAuthorized"])


if __name__ == "__main__": unittest.main()
