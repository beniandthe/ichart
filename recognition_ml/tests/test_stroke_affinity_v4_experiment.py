from collections import Counter
from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.features import InkBounds, InkPoint, InkStroke
from ichart_recognition_ml.research.uji_personal import Sample, split_writers
from ichart_recognition_ml.research import stroke_affinity_experiment as v1
from ichart_recognition_ml.research import stroke_affinity_v2_experiment as v2
from ichart_recognition_ml.research import stroke_affinity_v3_experiment as v3
from ichart_recognition_ml.research import stroke_affinity_v4_experiment as v4


class StrokeAffinityV4ExperimentTests(unittest.TestCase):
    def setUp(self):
        metadata = tuple(Sample(f"{role}_UPV_W{index:02d}", 1, "A", ())
            for role, count in (("trn", 40), ("tst", 20)) for index in range(count))
        self.roles = self.training, self.development, self.reserved = split_writers(metadata)
        self.writer = self.training[0]
        self.strokes = (InkStroke((InkPoint(-5, 2, 0), InkPoint(-5, 2), InkPoint(5, 7, 0.2)),
            InkBounds(-6, 1, 6, 8), creation_time_offset=3), InkStroke((InkPoint(1, 1), InkPoint(5, 5))))

    def targets(self, singleton=True):
        samples = tuple(Sample(self.writer, 1, label, self.strokes) for label in "ABCD")
        targets = tuple(v3.target_from_context(v3.Context(samples[:cardinality], 32 if cardinality == 1 else 16,
            0 if cardinality == 1 else 8, v3.arm_name(cardinality, 16, 8)), "training") for cardinality in (1, 2, 3, 4))
        if singleton:
            dot = Sample(self.writer, 1, ".", (InkStroke((InkPoint(9, 9),)),))
            targets += (v3.target_from_context(v3.Context((dot,), 32, 0, "single32"), "training"),)
        return targets

    @staticmethod
    def plan(targets):
        arms, eligible, edges = Counter(), Counter(), 0
        for target in targets:
            count = len(target.strokes)
            arms[target.arm] += 1; edges += count * (count - 1) // 2
            eligible[target.cardinality] += int(count > 1)
        return {"targets": len(targets), "edgeRows": edges, "targetsByArm": dict(sorted(arms.items())),
            "eligibleTargetsByCardinality": {str(key): value for key, value in sorted(eligible.items())}}

    def artifact(self, directory):
        """A complete synthetic v3 contract; never uses public trajectories."""
        run, source = Path(directory) / "v3-run", Path(directory) / "source"
        run.mkdir(); source.write_bytes(b"synthetic-source-only")
        source_sha = v4.file_digest(source)
        targets = self.targets()
        plan = self.plan(targets)
        rows = v3.build_training_cache(targets, self.training, plan, run / "cache")
        root = Path(v4.__file__).resolve().parents[3]
        protocol_bytes = (root / v3.PROTOCOL_PATH).read_bytes()
        (run / "frozen-protocol.md").write_bytes(protocol_bytes)
        (run / "affinity-weights.pt").write_bytes(b"must-not-load-prior-model")
        report = {"version": v3.VERSION, "sourceSHA256": source_sha, "sourceUnchanged": True,
            "codeSHA256": v3.code_identity(), "featureSchema": v3.FEATURE_SCHEMA, "featureCount": 202,
            "protocolSHA256": v4.digest(protocol_bytes), "trainingWriters": list(self.training),
            "developmentWriters": list(self.development), "reservedWriters": list(self.reserved),
            "trainingPlan": plan, "training": rows.summary, "parameterCount": 15105,
            "seed": 29, "epochs": 30, "batchSize": 512, "selection": "final-epoch-only",
            "productionEligible": False, "privateInkUsed": False, "reservedWritersEvaluated": False,
            "developmentFeaturesConstructed": False, "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
            "featureStandardization": "final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6",
            "symmetry": "mean-forward-AB-forward-BA",
            "controlledChange": "v1-whole-context-features-with-unchanged-v2-targets-weights-fit-decoder",
            "trainingHistory": [{"epoch": index, "onlineWeightedLoss": 0} for index in range(1, 31)],
            "weightsSHA256": v4.file_digest(run / "affinity-weights.pt"),
            "cacheManifestSHA256": v4.file_digest(run / "cache/manifest.json"), "trajectoryCopyAudit": {"toy": True}}
        v4.write_json(run / "report.json", report)
        v4.write_json(run / "protocol.json", {key: report[key] for key in ("version", "sourceSHA256", "codeSHA256", "trainingPlan")})
        with patch.object(v4, "SOURCE_SHA256", source_sha), patch.object(torch, "load") as checkpoint:
            reference = v4.verify_v3_cache(source, run, self.roles, plan)
            checkpoint.assert_not_called()
        return source, run, targets, plan, reference

    def new_rows(self, directory):
        source, run, targets, plan, reference = self.artifact(directory)
        rows = v4.reweight_training_cache(targets, self.training, plan, reference, Path(directory) / "v4-cache")
        return rows, source, run, targets, plan, reference

    @staticmethod
    def direct_weights(targets, labels):
        base_rows, positive_mass, negative_mass = [], 0., 0.
        for target in targets:
            count = len(target.strokes)
            edges = count * (count - 1) // 2
            if not edges:
                continue
            base = 1 / edges
            positive = sum(len(owner) * (len(owner) - 1) // 2 for owner in target.owners)
            positive_mass += positive * base
            negative_mass += (edges - positive) * base
            base_rows.append(np.full(edges, base, dtype=np.float64))
        mass = positive_mass + negative_mass
        factors = {"positive": mass / (2 * positive_mass), "negative": mass / (2 * negative_mass)}
        return np.concatenate(base_rows) * np.where(labels == 1, factors["positive"], factors["negative"]), factors

    def test_sole_rule_change_reuses_immutable_helpers_not_prior_model(self):
        for name in ("target_stream", "training_plan", "weighted_standardization", "normalized_batch", "fit_rows", "evaluate_targets"):
            self.assertIs(getattr(v4, name), getattr(v3, name))
        self.assertIs(v4.fit_rows, v2.fit_rows)
        self.assertEqual(v4.VERSION, "public-stroke-affinity-experiment-v4")
        self.assertEqual(v4.FEATURE_SCHEMA, "stroke-affinity-context-v1")
        self.assertEqual((v4.SEED, v4.EPOCHS, v4.BATCH_SIZE), (29, 30, 512))
        self.assertFalse(hasattr(v4, "all_pair_features"))
        self.assertEqual(v3.VERSION, "public-stroke-affinity-experiment-v3")

    def test_cache_references_readonly_arrays_only_new_weights_written(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, source, run, targets, plan, reference = self.new_rows(directory)
            for name in ("ab", "ba", "labels", "cardinalities"):
                self.assertIs(getattr(rows, name), getattr(reference, name))
                self.assertFalse(getattr(rows, name).flags.writeable)
            self.assertEqual({path.name for path in (Path(directory) / "v4-cache").iterdir()}, {"weights.npy", "manifest.json"})
            self.assertFalse(rows.weights.flags.writeable)
            self.assertEqual(rows.weights.dtype, np.float64)
            manifest = json.loads((Path(directory) / "v4-cache/manifest.json").read_text())
            self.assertEqual(manifest["version"], v4.VERSION)
            self.assertEqual(manifest["reuse"]["v3Run"], str(run.resolve()))
            self.assertEqual(len(manifest["reuse"]["referencedArrays"]), 5)
            self.assertFalse(manifest["reuse"]["featureArraysRegenerated"])
            self.assertFalse(manifest["reuse"]["priorModelInitialized"])
            for contract in manifest["reuse"]["referencedArrays"].values():
                self.assertEqual(v4.file_digest(Path(contract["path"])), contract["sha256"])
                self.assertTrue(contract["readOnly"])

    def test_equal_target_rule_and_retained_reduction_match_direct_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, source, run, targets, plan, reference = self.new_rows(directory)
            direct, factors = self.direct_weights(targets, rows.labels)
            np.testing.assert_array_equal(rows.weights, direct)
            for mass_by_cardinality in rows.summary["baseMassByCardinality"].values():
                self.assertAlmostEqual(mass_by_cardinality, 1., places=12)
            self.assertEqual(rows.summary["globalClassMultipliers"], factors)
            self.assertAlmostEqual(sum(rows.summary["finalShareByCardinality"].values()), 1)
            self.assertAlmostEqual(rows.weights[rows.labels == 1].sum(), rows.weights[rows.labels == 0].sum())
            self.assertEqual(rows.summary["singletonTargetsExcludedFromLoss"], 1)

    def test_base_cardinality_mass_tracks_eligible_target_count_not_equal_one(self):
        with tempfile.TemporaryDirectory() as directory:
            source, run, targets, plan, reference = self.artifact(directory)
            # Repeat one isolated target with a new corresponding immutable toy
            # reference to distinguish equal-target from old equal-cardinality.
            targets = targets + (targets[0],)
            plan = self.plan(targets)
            old = v3.build_training_cache(targets, self.training, plan, Path(directory) / "more-v3")
            reference = replace(reference, ab=old.ab, ba=old.ba, labels=old.labels, cardinalities=old.cardinalities)
            rows = v4.reweight_training_cache(targets, self.training, plan, reference, Path(directory) / "more-v4")
            direct, factors = self.direct_weights(targets, rows.labels)
            np.testing.assert_array_equal(rows.weights, direct)
            self.assertEqual(rows.summary["globalClassMultipliers"], factors)
            for key, expected in {"1": 2., "2": 1., "3": 1., "4": 1.}.items():
                self.assertAlmostEqual(rows.summary["baseMassByCardinality"][key], expected, places=12)

    def test_4250_rows_exact_direct_moments_minibatches_final_parameters_losses(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, *_ = self.new_rows(directory)
            maps = {}
            for name, values in (("ab", rows.ab), ("ba", rows.ba)):
                path = Path(directory) / ("tiled-" + name + ".npy")
                writable = np.lib.format.open_memmap(path, mode="w+", dtype=np.float32, shape=(4250, 202))
                writable[:] = np.tile(values, (85, 1)); writable.flush(); del writable
                maps[name] = np.load(path, mmap_mode="r", allow_pickle=False)
            rows = replace(rows, **maps, labels=np.tile(rows.labels, 85), weights=np.tile(rows.weights, 85),
                cardinalities=np.tile(rows.cardinalities, 85))
            direct = v1.TrainingRows(rows.ab.copy(), rows.ba.copy(), rows.labels.copy(), rows.weights.copy(), rows.summary)
            mean, std = v4.weighted_standardization(rows)
            reference_mean, reference_std = v1.weighted_standardization(direct)
            torch.testing.assert_close(mean, reference_mean, rtol=0, atol=0)
            torch.testing.assert_close(std, reference_std, rtol=0, atol=0)
            indexes = np.array([4200, 0, 4096, 49, 1])
            full = (torch.as_tensor(direct.ab, dtype=torch.float32) - mean) / std
            torch.testing.assert_close(v4.normalized_batch(rows.ab, indexes, mean, std), full[indexes], rtol=0, atol=0)
            model, mean2, std2, history = v4.fit_rows(rows, epochs=2, unit_test=True)
            other, mean3, std3, history2 = v1.fit_rows(direct, epochs=2, unit_test=True)
            for key, value in model.state_dict().items():
                torch.testing.assert_close(value, other.state_dict()[key], rtol=0, atol=0)
            torch.testing.assert_close(mean2, mean3, rtol=0, atol=0)
            torch.testing.assert_close(std2, std3, rtol=0, atol=0)
            self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in history2])

    def test_each_referenced_array_digest_verified_before_any_mapping_access(self):
        for name in v4.ARRAY_NAMES:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                source, run, targets, plan, reference = self.artifact(directory)
                path = run / "cache" / (name + ".npy")
                path.write_bytes(path.read_bytes() + b"changed")
                with patch.object(v4, "SOURCE_SHA256", v4.file_digest(source)), patch.object(np, "load") as mapped:
                    with self.assertRaisesRegex(ValueError, "array content digest"):
                        v4.verify_v3_cache(source, run, self.roles, plan)
                    mapped.assert_not_called()

    def test_report_protocol_source_plan_roles_and_code_reject_before_mapping(self):
        changes = (("version", v2.VERSION), ("featureSchema", "stroke-affinity-pair-local-v2"),
            ("sourceSHA256", "0" * 64), ("privateInkUsed", True), ("reservedWritersEvaluated", True),
            ("trainingWriters", list(self.reserved)), ("codeSHA256", {}), ("trainingPlan", {}), ("epochs", 29))
        for key, value in changes:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                source, run, targets, plan, reference = self.artifact(directory)
                report = json.loads((run / "report.json").read_text()); report[key] = value
                (run / "report.json").write_text(json.dumps(report))
                with patch.object(v4, "SOURCE_SHA256", v4.file_digest(source)), patch.object(np, "load") as mapped:
                    with self.assertRaises(ValueError):
                        v4.verify_v3_cache(source, run, self.roles, plan)
                    mapped.assert_not_called()
        with tempfile.TemporaryDirectory() as directory:
            source, run, targets, plan, reference = self.artifact(directory)
            with patch.object(np, "load") as mapped:
                with self.assertRaisesRegex(ValueError, "32/8/20"):
                    v4.verify_v3_cache(source, run, (self.training, self.development, self.reserved[:-1]), plan)
                mapped.assert_not_called()

    def test_wrong_role_and_five_training_rejected_before_referenced_rows(self):
        targets = self.targets()
        for changed in (replace(targets[0], role="development"), replace(targets[0], writer=self.reserved[0]),
                replace(targets[-2], cardinality=5)):
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, "before referenced"):
                    v4.reweight_training_cache((changed,), self.training, self.plan(targets), None, Path(directory) / "new")
        reserved = Sample(self.reserved[0], 1, "A", self.strokes)
        with self.assertRaises(ValueError):
            v4.target_stream((reserved,), "training", self.training)

    def test_replay_rejects_labels_cards_boundary_and_incomplete_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            source, run, targets, plan, reference = self.artifact(directory)
            cases = []
            labels = reference.labels.copy(); labels[0] = 0; labels.flags.writeable = False
            cards = reference.cardinalities.copy(); cards[0] = 4; cards.flags.writeable = False
            cases += [replace(reference, labels=labels), replace(reference, cardinalities=cards)]
            for index, changed in enumerate(cases):
                with self.assertRaisesRegex(ValueError, "Replay owner"):
                    v4.reweight_training_cache(targets, self.training, plan, changed, Path(directory) / f"bad-{index}")
            with self.assertRaisesRegex(ValueError, "complete frozen"):
                v4.reweight_training_cache(targets[:-1], self.training, plan, reference, Path(directory) / "missing-singleton")
            with self.assertRaisesRegex(ValueError, "edge boundary"):
                v4.reweight_training_cache(targets + (targets[0],), self.training, plan, reference, Path(directory) / "too-many")

    def test_failed_operations_preserve_source_references_and_new_weights(self):
        with tempfile.TemporaryDirectory() as directory:
            rows, source, run, *_ = self.new_rows(directory)
            paths = (source,) + v4.v3_reference_paths(run) + (Path(directory) / "v4-cache/weights.npy",)
            before = {path: v4.file_digest(path) for path in paths}
            with self.assertRaisesRegex(RuntimeError, "failure"):
                with v4.preserved_inputs(paths):
                    raise RuntimeError("failure")
            self.assertEqual(before, {path: v4.file_digest(path) for path in paths})
            changed = run / "cache/labels.npy"
            with self.assertRaisesRegex(ValueError, "changed during v4"):
                with v4.preserved_inputs(paths):
                    changed.write_bytes(changed.read_bytes() + b"changed")
                    raise RuntimeError("failure")

    def test_all_27_bindings_canonical_v4_protocol_and_append_only_outputs(self):
        identity = v4.code_identity()
        self.assertEqual(len(identity), 27)
        self.assertEqual({key: identity[key] for key in v3.code_identity()}, v3.code_identity())
        for path in (v4.PROTOCOL_PATH, "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_experiment.py",
                "recognition_ml/tests/test_stroke_affinity_v4_experiment.py", "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_baseline.py",
                "recognition_ml/tests/test_stroke_affinity_v4_baseline.py"):
            self.assertIn(path, identity)
        with tempfile.TemporaryDirectory() as directory:
            source, run, targets, plan, reference = self.artifact(directory)
            wrong = Path(directory) / "wrong-protocol"; wrong.write_bytes(b"wrong")
            with patch.object(v4, "load_official_source") as loaded:
                with self.assertRaisesRegex(ValueError, "canonical v4"):
                    v4.fit(source, wrong, run, Path(directory) / "fit")
                loaded.assert_not_called()
            output = Path(directory) / "keep.json"; v4.write_json(output, {"keep": True})
            before = v4.file_digest(output)
            with self.assertRaises(FileExistsError):
                v4.write_json(output, {"keep": False})
            self.assertEqual(before, v4.file_digest(output))
            with self.assertRaises(ValueError):
                v4.new_output(run)


if __name__ == "__main__":
    unittest.main()
