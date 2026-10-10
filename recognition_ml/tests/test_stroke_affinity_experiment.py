from dataclasses import replace
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.features import InkBounds, InkPoint, InkStroke
from ichart_recognition_ml.research.uji_personal import Sample, split_writers
from ichart_recognition_ml.research import stroke_affinity_experiment as experiment


class StrokeAffinityExperimentTests(unittest.TestCase):
    def setUp(self):
        metadata = tuple(Sample(f"{role}_UPV_W{index:02d}", 1, "A", ())
                         for role, count in (("trn", 40), ("tst", 20)) for index in range(count))
        self.training, self.development, self.reserved = split_writers(metadata)
        self.writer = self.training[0]
        self.dev_writer = self.development[0]
        self.first = InkStroke((InkPoint(-5, 2, 0), InkPoint(-5, 2), InkPoint(5, 7, 0.2)),
                               InkBounds(-6, 1, 6, 8), creation_time_offset=3)
        self.second = InkStroke((InkPoint(1, 1), InkPoint(5, 5)))

    def target(self, role="training", writer=None, owners=((0, 1),), strokes=None, identity="target", arm="single32"):
        source = strokes or (self.first, self.second)
        return experiment.Target(identity, role, writer or self.writer, 1, arm, ("source-A",),
                                 tuple(source), tuple(owners), 0, "A")

    def rows(self):
        singles = self.target()
        pair_strokes, owners, zeros = experiment.compose(((self.first, self.second), (self.first, self.second)),
                                                        (32, 16), (8,))
        pair = self.target(strokes=pair_strokes, owners=owners, identity="pair", arm="second16-gap8")
        return experiment.training_rows((singles, pair), self.training)

    @staticmethod
    def session_samples(writer):
        stroke = InkStroke((InkPoint(0, 0), InkPoint(8, 12)))
        return tuple(Sample(writer, session, chr(0x400 + index), (stroke,))
                     for session in (1, 2) for index in range(97))

    def test_wrong_source_roles_rejected_before_geometry_or_features(self):
        sample = Sample(self.reserved[0], 1, "A", (self.first,))
        with patch.object(experiment, "normalize") as geometry, patch.object(experiment, "all_pair_features") as features:
            for role, writers in (("training", self.training), ("development", self.development)):
                with self.assertRaises(ValueError):
                    experiment.build_targets((sample,), role, writers)
            with self.assertRaises(ValueError):
                experiment.training_target_stream((sample,), self.training)
            geometry.assert_not_called(); features.assert_not_called()
        for wrong in ((), self.training[:-1], self.training + (self.training[0],)):
            with self.assertRaises(ValueError):
                experiment.validate_role((Sample(self.writer, 1, "A", (self.first,)),), "training", wrong)

    def test_development_targets_never_reach_training_features(self):
        target = self.target(role="development", writer=self.dev_writer)
        with patch.object(experiment, "all_pair_features") as features:
            with self.assertRaises(ValueError):
                experiment.training_rows((self.target(), target), self.training)
            features.assert_not_called()
        with self.assertRaises(ValueError):
            experiment.build_targets(self.session_samples(self.writer), "training", self.training, include_triple=True)

    def test_affine_composition_matches_swift_metadata_and_point_bounds(self):
        original = (self.first, self.second)
        for dimension, gap in experiment.PAIR_ARMS:
            strokes, owners, zeros = experiment.compose(((self.first,), (self.second,)), (32, dimension), (gap,))
            a, b = experiment.point_bounds((strokes[0],)), experiment.point_bounds((strokes[1],))
            self.assertAlmostEqual(max(a[2] - a[0], a[3] - a[1]), 32)
            self.assertAlmostEqual(max(b[2] - b[0], b[3] - b[1]), dimension)
            self.assertAlmostEqual(b[0] - a[2], gap)
            self.assertAlmostEqual(a[3], 32); self.assertAlmostEqual(b[3], 32)
            self.assertEqual(owners, ((0,), (1,)))
            self.assertEqual(zeros, 0)
            self.assertEqual(tuple(point.time_offset for point in strokes[0].points), (0, None, 0.2))
            self.assertEqual(strokes[0].creation_time_offset, 3)
            self.assertAlmostEqual(strokes[0].bounds.min_x, -3.2)
            self.assertAlmostEqual(strokes[0].bounds.max_y, 35.2)
            self.assertEqual(original, (self.first, self.second))

    def test_zero_extent_preserves_points_without_inventing_geometry(self):
        dot = InkStroke((InkPoint(9, 9), InkPoint(9, 9)))
        strokes, owners, zeros = experiment.compose(((self.first,), (dot,)), (32, 16), (8,))
        self.assertEqual(zeros, 1)
        self.assertEqual(strokes[1].points, (InkPoint(40, 32), InkPoint(40, 32)))
        self.assertEqual(owners, ((0,), (1,)))
        self.assertEqual(experiment.normalize((dot,))[0].points, (InkPoint(0, 0), InkPoint(0, 0)))
        for dimension in (0, float("nan")):
            with self.assertRaises(ValueError):
                experiment.normalize((dot,), dimension)

    def test_pair_and_triple_sequences_cover_every_source_without_labels_entering_features(self):
        samples = self.session_samples(self.dev_writer)
        targets = experiment.build_targets(samples, "development", self.development, include_triple=True)
        self.assertEqual(len(targets), 194 * 8)
        self.assertEqual(set(target.arm for target in targets),
            {"single32", "second16-gap3.2", "second16-gap8", "second16-gap16", "second32-gap3.2", "second32-gap8", "second32-gap16", experiment.TRIPLE_ARM})
        for count in (2, 3):
            sequences = experiment.cyclic_sequences(samples, count)
            self.assertEqual(len(sequences), len(samples))
            for offset in range(count):
                self.assertEqual({sequence[offset].identity for sequence in sequences}, {sample.identity for sample in samples})
            self.assertTrue(all(len({sample.identity for sample in sequence}) == count for sequence in sequences))
            self.assertTrue(all(len({(sample.writer, sample.session) for sample in sequence}) == 1 for sequence in sequences))
        triples = [target for target in targets if target.arm == experiment.TRIPLE_ARM]
        first = triples[0]
        self.assertEqual(first.owners, ((0,), (1,), (2,)))
        bounds = [experiment.point_bounds((stroke,)) for stroke in first.strokes]
        self.assertAlmostEqual(bounds[1][0] - bounds[0][2], 8)
        self.assertAlmostEqual(bounds[2][0] - bounds[1][2], 8)
        self.assertTrue(all(bound[3] == 32 for bound in bounds))

    def test_training_stream_preflight_does_not_construct_features(self):
        samples = self.session_samples(self.writer)
        with patch.object(experiment, "all_pair_features") as features:
            plan = experiment.training_plan(samples, self.training)
            features.assert_not_called()
        self.assertEqual(plan["targets"], 194 * 7)
        self.assertEqual(plan["edgeRows"], 194 * 6)
        self.assertEqual(plan["singletonTargetsExcludedFromLoss"], 194)
        self.assertFalse(plan["developmentFeaturesConstructed"])
        self.assertEqual(tuple(experiment.training_target_stream(samples, self.training)),
                         experiment.build_targets(samples, "training", self.training))

    def test_per_target_weights_then_global_class_balance(self):
        rows = self.rows()
        self.assertEqual(rows.ab.shape, (7, 202))
        self.assertEqual(rows.ba.shape, rows.ab.shape)
        self.assertAlmostEqual(rows.summary["unbalancedPositiveMass"], 1 + 2 / 6)
        self.assertAlmostEqual(rows.summary["unbalancedNegativeMass"], 4 / 6)
        self.assertAlmostEqual(rows.weights[rows.labels == 1].sum(), rows.weights[rows.labels == 0].sum())
        singleton = self.target(strokes=(self.first,), owners=((0,),), identity="singleton")
        more = experiment.training_rows((self.target(), singleton,
            self.target(strokes=(self.first, self.second), owners=((0,), (1,)), identity="negative", arm="second16-gap8")), self.training)
        self.assertEqual(more.summary["singletonTargetsExcludedFromLoss"], 1)
        self.assertEqual(more.summary["targets"], 3)

    def test_supervision_and_identity_are_not_feature_arguments(self):
        first = self.target()
        second = replace(first, identity="different", source_ids=("different-G",), single_label="G", owners=((0,), (1,)))
        rows = experiment.training_rows((first, second), self.training)
        np.testing.assert_array_equal(rows.ab[0], rows.ab[1])
        np.testing.assert_array_equal(rows.ba[0], rows.ba[1])
        self.assertEqual(rows.labels.tolist(), [1, 0])

    def test_standardization_uses_both_directions_and_final_weight_mass(self):
        ab, ba = np.zeros((2, 202), np.float32), np.zeros((2, 202), np.float32)
        ab[:, 0], ba[:, 0] = (0, 2), (2, 4)
        rows = experiment.TrainingRows(ab, ba, np.array([0, 1], np.float32), np.array([1, 3], np.float64), {})
        mean, std = experiment.weighted_standardization(rows)
        self.assertAlmostEqual(float(mean[0]), 2.5)
        self.assertAlmostEqual(float(std[0]), np.sqrt(1.75), places=6)
        self.assertAlmostEqual(float(std[1]), 1e-6, places=12)
        with self.assertRaises(ValueError):
            experiment.weighted_standardization(replace(rows, weights=np.array([1, float("nan")])) )

    def test_tiny_fit_repeatability_source_preservation_and_no_development_argument(self):
        rows = self.rows()
        copies = tuple(array.copy() for array in (rows.ab, rows.ba, rows.labels, rows.weights))
        model, mean, std, history = experiment.fit_rows(rows, epochs=2, unit_test=True)
        again, mean2, std2, history2 = experiment.fit_rows(rows, epochs=2, unit_test=True)
        for key, value in model.state_dict().items():
            torch.testing.assert_close(value, again.state_dict()[key], rtol=0, atol=0)
        torch.testing.assert_close(mean, mean2, rtol=0, atol=0)
        torch.testing.assert_close(std, std2, rtol=0, atol=0)
        self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in history2])
        for array, copy in zip((rows.ab, rows.ba, rows.labels, rows.weights), copies):
            np.testing.assert_array_equal(array, copy)
        with self.assertRaises(ValueError):
            experiment.fit_rows(rows, epochs=2)

    def test_truth_is_scored_only_after_partition_prediction_and_rows_keep_all_cases(self):
        target = self.target(role="development", writer=self.dev_writer)
        calls = []
        def predicted(*args):
            self.assertEqual(len(args), 4)
            calls.append("predict")
            return ((0, 1),), ((0, 1),), np.array([1.0]), {"featureSeconds": 0, "inferenceAndPartitionSeconds": 0}
        real_score = experiment.partition_metrics
        def scored(*args):
            calls.append("score")
            return real_score(*args)
        with patch.object(experiment, "predict_target", side_effect=predicted), patch.object(experiment, "partition_metrics", side_effect=scored):
            result = experiment.evaluate_targets(None, None, None, (target,), self.development)
        self.assertEqual(calls, ["predict", "score"])
        row, = result["rows"]
        self.assertEqual(row["role"], "development")
        self.assertEqual(row["groups"], ((0, 1),))
        self.assertTrue(row["exactOwnerMatch"])
        self.assertEqual(result["singlePartitionsByLabel"]["A"]["exactPartitions"], 1)
        self.assertEqual(row["edgeConfusion"]["edgeTruePositive"], 1)

    def test_partition_metrics_detect_count_illusion_and_index_defects(self):
        result = experiment.partition_metrics(4, ((0,), (1, 2, 3)), ((0, 1), (2, 3)))
        self.assertFalse(result["exactPartition"])
        self.assertEqual(result["falseMergedGroups"], 1)
        self.assertEqual(result["falseSplitOwners"], 1)
        defects = experiment.partition_metrics(4, ((0, 0, 9), (2,)), ((0, 1), (2, 3)))
        self.assertEqual((defects["missingIndexes"], defects["duplicateIndexes"], defects["invalidIndexes"]), (2, 1, 1))
        with self.assertRaises(ValueError):
            experiment.partition_metrics(4, ((0, 1),), ((0,), (1,)))

    def test_copy_exposure_is_audit_not_posthoc_exclusion(self):
        sample = Sample(self.writer, 1, "A", (self.first,))
        dev = Sample(self.dev_writer, 2, "G", experiment.affine(sample.strokes, 2, 10, 20))
        with patch.object(experiment, "all_pair_features") as features:
            audit = experiment.audit_trajectory_copies((sample,), (dev,), self.training, self.development)
            features.assert_not_called()
        self.assertEqual(audit["developmentSourceCopyExposure"], 1)
        self.assertEqual(audit["crossRoleFingerprintGroups"], 1)
        self.assertIn("no-posthoc-exclusions", audit["exclusionPolicy"])
        with self.assertRaises(ValueError):
            experiment.audit_trajectory_copies((sample,), (replace(dev, writer=self.reserved[0]),), self.training, self.development)

    def test_sources_and_outputs_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source.txt"
            source.write_bytes(b"incorrect official source")
            before = source.read_bytes()
            with self.assertRaises(ValueError):
                experiment.fit(source, source, Path(folder) / "new-fit")
            self.assertEqual(source.read_bytes(), before)
            output = Path(folder) / "result.json"
            experiment._write_json(output, {"preserved": True})
            digest = hashlib.sha256(output.read_bytes()).hexdigest()
            with self.assertRaises(FileExistsError):
                experiment._write_json(output, {"preserved": False})
            self.assertEqual(hashlib.sha256(output.read_bytes()).hexdigest(), digest)
            with self.assertRaises(ValueError):
                experiment._new_output(Path(folder))

    def test_code_identity_binds_protocol_and_core_contract(self):
        identity = experiment.code_identity()
        self.assertIn("recognition_ml/ichart_recognition_ml/research/stroke_affinity.py", identity)
        self.assertIn("recognition_ml/tests/test_stroke_affinity.py", identity)
        self.assertIn("docs/personal-learned-stroke-ownership-protocol-2026-09-30.md", identity)
        self.assertTrue(all(len(value) == 64 for value in identity.values()))

    def test_preservation_checks_run_when_computation_raises(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "source.txt"
            source.write_bytes(b"source")
            with self.assertRaisesRegex(RuntimeError, "computation"):
                with experiment.preserved_inputs((source,)):
                    raise RuntimeError("computation failed")
            with self.assertRaisesRegex(ValueError, "changed during"):
                with experiment.preserved_inputs((source,)):
                    source.write_bytes(b"changed")
                    raise RuntimeError("computation failed after corruption")

    def test_supplied_protocol_must_match_the_frozen_protocol(self):
        with tempfile.TemporaryDirectory() as folder:
            source, protocol = Path(folder) / "source.txt", Path(folder) / "protocol.md"
            source.write_bytes(b"not loaded yet")
            protocol.write_bytes(b"another protocol")
            with patch.object(experiment, "load_official_source") as load:
                with self.assertRaisesRegex(ValueError, "Supplied protocol differs"):
                    experiment.fit(source, protocol, Path(folder) / "out")
                load.assert_not_called()


if __name__ == "__main__":
    unittest.main()
