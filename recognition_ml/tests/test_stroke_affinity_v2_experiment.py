from collections import Counter
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
from ichart_recognition_ml.research import stroke_affinity_experiment as v1
from ichart_recognition_ml.research import stroke_affinity_v2_experiment as v2


class StrokeAffinityV2ExperimentTests(unittest.TestCase):
    def setUp(self):
        metadata = tuple(Sample(f"{role}_UPV_W{index:02d}", 1, "A", ())
                         for role, count in (("trn", 40), ("tst", 20)) for index in range(count))
        self.training, self.development, self.reserved = split_writers(metadata)
        self.writer, self.dev_writer = self.training[0], self.development[0]
        first = InkStroke((InkPoint(-5, 2, 0), InkPoint(-5, 2), InkPoint(5, 7, 0.2)),
                          InkBounds(-6, 1, 6, 8), creation_time_offset=3)
        second = InkStroke((InkPoint(1, 1), InkPoint(5, 5)))
        self.strokes = (first, second)

    def samples(self, writer):
        return tuple(Sample(writer, session, chr(0x400 + index), self.strokes)
                     for session in (1, 2) for index in range(97))

    def toy_targets(self, role="training", writer=None, include_singleton=False):
        writer = writer or (self.writer if role == "training" else self.dev_writer)
        samples = tuple(Sample(writer, 1, label, self.strokes) for label in "ABCD")
        targets = tuple(v2.target_from_context(v2.Context(samples[:cardinality], 32 if cardinality == 1 else 16,
            0 if cardinality == 1 else 8, v2.arm_name(cardinality, 16, 8)), role) for cardinality in (1, 2, 3, 4))
        if include_singleton:
            dot = Sample(writer, 1, ".", (InkStroke((InkPoint(9, 9),)),))
            targets += (v2.target_from_context(v2.Context((dot,), 32, 0, "single32"), role),)
        return targets

    @staticmethod
    def plan(targets):
        arms, eligible, edges = Counter(), Counter(), 0
        for target in targets:
            arms[target.arm] += 1
            count = len(target.strokes)
            edges += count * (count - 1) // 2
            eligible[target.cardinality] += int(count > 1)
        return {"targets": len(targets), "edgeRows": edges, "targetsByArm": dict(sorted(arms.items())),
                "eligibleTargetsByCardinality": {str(key): value for key, value in sorted(eligible.items())}}

    def cache(self, directory, targets=None):
        targets = targets or self.toy_targets()
        return v2.build_training_cache(targets, self.training, self.plan(targets), Path(directory) / "cache")

    def test_original_writer_roles_reject_before_geometry_or_features(self):
        reserved = Sample(self.reserved[0], 1, "A", self.strokes)
        with patch.object(v2, "normalize") as geometry, patch.object(v2, "all_pair_features") as features:
            for role, writers in (("training", self.training), ("development", self.development)):
                with self.assertRaises(ValueError):
                    v2.target_stream((reserved,), role, writers)
            geometry.assert_not_called(); features.assert_not_called()
        mixed = v2.Context((Sample(self.writer, 1, "A", self.strokes), reserved), 16, 8, "second16-gap8")
        with self.assertRaises(ValueError):
            v2.target_from_context(mixed, "training")

    def test_five_character_contexts_are_evaluation_only(self):
        samples = self.samples(self.writer)
        with self.assertRaises(ValueError):
            v2.context_stream(samples, "training", self.training, include_five=True)
        five_sources = self.samples(self.dev_writer)[:5]
        target = v2.target_from_context(v2.Context(five_sources, 16, 8, v2.arm_name(5, 16, 8)), "development")
        with tempfile.TemporaryDirectory() as directory, patch.object(v2, "all_pair_features") as features:
            with self.assertRaises(ValueError):
                v2.build_training_cache((replace(target, role="training", writer=self.writer),), self.training,
                                       self.plan((target,)), Path(directory) / "cache")
            features.assert_not_called()

    def test_all_declared_contexts_and_names_match_fixed_cardinalities(self):
        samples = self.samples(self.dev_writer)
        contexts = tuple(v2.context_stream(samples, "development", self.development, include_five=True))
        self.assertEqual(len(contexts), 194 * 25)
        counts = Counter(context.arm for context in contexts)
        self.assertEqual(len(counts), 25)
        self.assertTrue(all(value == 194 for value in counts.values()))
        self.assertIn("triple32-16-16-gap8-8", counts)
        for cardinality in (2, 3, 4, 5):
            sequences = v2.cyclic_sequences(samples, cardinality)
            for offset in range(cardinality):
                self.assertEqual({sequence[offset].identity for sequence in sequences}, {sample.identity for sample in samples})
            self.assertTrue(all(len({sample.identity for sample in sequence}) == cardinality for sequence in sequences))
            self.assertTrue(all(len({(sample.writer, sample.session) for sample in sequence}) == 1 for sequence in sequences))

    def test_old_v1_singles_pairs_and_triple_are_exactly_preserved(self):
        samples = self.samples(self.dev_writer)
        old = v1.build_targets(samples, "development", self.development, include_triple=True)
        old_by_id = {target.identity: target for target in old}
        matched = 0
        for target in v2.target_stream(samples, "development", self.development, include_five=True):
            if target.identity not in old_by_id:
                continue
            previous = old_by_id[target.identity]
            for field in ("role", "writer", "session", "arm", "source_ids", "strokes", "owners", "zero_extent_characters", "single_label"):
                self.assertEqual(getattr(target, field), getattr(previous, field), (target.identity, field))
            matched += 1
        self.assertEqual(matched, 194 * 8)

    def test_affine_metadata_and_zero_extent_remain_lossless(self):
        dot = InkStroke((InkPoint(9, 9), InkPoint(9, 9)))
        sources = (Sample(self.writer, 1, "A", self.strokes), Sample(self.writer, 1, ".", (dot,)),
                   Sample(self.writer, 1, "C", self.strokes), Sample(self.writer, 1, "D", self.strokes))
        target = v2.target_from_context(v2.Context(sources, 16, 8, v2.arm_name(4, 16, 8)), "training")
        self.assertEqual(target.zero_extent_characters, 1)
        self.assertEqual(target.strokes[0].creation_time_offset, 3)
        self.assertEqual(tuple(point.time_offset for point in target.strokes[0].points), (0, None, 0.2))
        self.assertEqual(target.strokes[2].points[0], target.strokes[2].points[1])
        self.assertEqual(target.strokes[2].points[0].y, 32)
        self.assertEqual(sources[0].strokes, self.strokes)
        self.assertEqual(sum(len(stroke.points) for stroke in target.strokes), sum(len(stroke.points) for sample in sources for stroke in sample.strokes))

    def test_metadata_preflight_never_builds_affinity_features(self):
        samples = self.samples(self.writer)
        with patch.object(v2, "all_pair_features") as features:
            plan = v2.training_plan(samples, self.training)
            features.assert_not_called()
        self.assertEqual(plan["targets"], 194 * 19)
        self.assertEqual(plan["eligibleTargetsByCardinality"], {"1": 194, "2": 194 * 6, "3": 194 * 6, "4": 194 * 6})
        self.assertFalse(plan["affinityFeaturesConstructed"])
        self.assertFalse(plan["developmentFeaturesConstructed"])
        self.assertEqual(plan["rawABBAFloat32Bytes"], plan["edgeRows"] * 202 * 4 * 2)

    def test_cardinality_base_mass_one_then_global_class_balance(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory, self.toy_targets(include_singleton=True))
            self.assertTrue(all(abs(value - 1) < 1e-12 for value in rows.summary["baseMassByCardinality"].values()))
            self.assertAlmostEqual(rows.weights[rows.labels == 1].sum(), rows.weights[rows.labels == 0].sum())
            self.assertAlmostEqual(sum(rows.summary["finalMassByCardinality"].values()), 4)
            self.assertNotAlmostEqual(rows.summary["finalMassByCardinality"]["1"], 1)
            self.assertEqual(rows.summary["singletonTargetsExcludedFromLoss"], 1)
            self.assertIsInstance(rows.ab, np.memmap)
            self.assertFalse(rows.ab.flags.writeable)
            self.assertEqual(rows.ab.dtype, np.float32)
            self.assertEqual(rows.weights.dtype, np.float64)

    def test_storage_statistics_batches_and_fit_match_direct_arithmetic_exactly(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            # Exercise more than one4096-row moment block, several512-row
            # batches, and a short final batch without computing more features.
            maps = {}
            for name, values in (("ab", rows.ab), ("ba", rows.ba)):
                path = Path(directory) / ("tiled-" + name + ".npy")
                writable = np.lib.format.open_memmap(path, mode="w+", dtype=np.float32, shape=(4250, 202))
                writable[:] = np.tile(values, (85, 1))
                writable.flush()
                del writable
                maps[name] = np.load(path, mmap_mode="r", allow_pickle=False)
            rows = replace(rows, **maps, labels=np.tile(rows.labels, 85), weights=np.tile(rows.weights, 85),
                           cardinalities=np.tile(rows.cardinalities, 85))
            self.assertEqual(len(rows.ab), 4250)
            direct = v1.TrainingRows(rows.ab.copy(), rows.ba.copy(), rows.labels.copy(), rows.weights.copy(), rows.summary)
            mean, std = v2.weighted_standardization(rows)
            direct_mean, direct_std = v1.weighted_standardization(direct)
            torch.testing.assert_close(mean, direct_mean, rtol=0, atol=0)
            torch.testing.assert_close(std, direct_std, rtol=0, atol=0)
            indexes = np.array([4000, 0, 4200, 49, 1])
            full = (torch.as_tensor(direct.ab, dtype=torch.float32) - mean) / std
            torch.testing.assert_close(v2.normalized_batch(rows.ab, indexes, mean, std), full[indexes], rtol=0, atol=0)
            model, mean2, std2, history = v2.fit_rows(rows, epochs=2, unit_test=True)
            reference, reference_mean, reference_std, reference_history = v1.fit_rows(direct, epochs=2, unit_test=True)
            for key, value in model.state_dict().items():
                torch.testing.assert_close(value, reference.state_dict()[key], rtol=0, atol=0)
            torch.testing.assert_close(mean2, reference_mean, rtol=0, atol=0)
            torch.testing.assert_close(std2, reference_std, rtol=0, atol=0)
            self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in reference_history])

    def test_tiny_fit_is_deterministic_and_preserves_raw_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            paths = tuple((Path(directory) / "cache").glob("*"))
            original = {path: v2.file_digest(path) for path in paths}
            first, mean, std, history = v2.fit_rows(rows, epochs=2, unit_test=True)
            second, mean2, std2, history2 = v2.fit_rows(rows, epochs=2, unit_test=True)
            for key, value in first.state_dict().items():
                torch.testing.assert_close(value, second.state_dict()[key], rtol=0, atol=0)
            torch.testing.assert_close(mean, mean2, rtol=0, atol=0)
            torch.testing.assert_close(std, std2, rtol=0, atol=0)
            self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in history2])
            self.assertEqual(original, {path: v2.file_digest(path) for path in paths})
            with self.assertRaises(ValueError):
                v2.fit_rows(rows, epochs=2)

    def test_identity_label_and_expected_count_do_not_enter_features(self):
        targets = self.toy_targets()
        calls = []
        actual = v2.all_pair_features
        def features(strokes):
            calls.append(strokes)
            return actual(strokes)
        with tempfile.TemporaryDirectory() as directory, patch.object(v2, "all_pair_features", side_effect=features):
            self.cache(directory, tuple(replace(target, identity="renamed-" + target.identity,
                source_ids=tuple("metadata-" + str(i) for i in range(target.cardinality)), single_label="G") for target in targets))
        self.assertEqual(calls, [target.strokes for target in targets])

    def test_prediction_precedes_truth_and_all_fields_are_retained(self):
        target = self.toy_targets(role="development")[0]
        calls = []
        def predict(*args):
            self.assertEqual(len(args), 4); calls.append("predict")
            return ((0, 1),), ((0, 1),), np.array([1.]), {"featureSeconds": 0, "inferenceAndPartitionSeconds": 0}
        score = v2.partition_metrics
        def measured(*args):
            calls.append("score"); return score(*args)
        with patch.object(v2, "predict_target", side_effect=predict), patch.object(v2, "partition_metrics", side_effect=measured):
            report = v2.evaluate_targets(None, None, None, (target,), self.development)
        self.assertEqual(calls, ["predict", "score"])
        row = report["rows"][0]
        self.assertEqual(row["cardinality"], 1)
        self.assertTrue(row["exactOwnerMatch"])
        self.assertEqual(row["sourceIDs"], target.source_ids)
        self.assertEqual(row["edgeConfusion"]["edgeTruePositive"], 1)
        self.assertEqual(report["singlePartitionsByLabel"]["A"]["exactPartitions"], 1)
        with patch.object(v2, "predict_target") as predicted:
            with self.assertRaises(ValueError):
                v2.evaluate_targets(None, None, None, (target, replace(target, writer=self.reserved[0])), self.development)
            predicted.assert_not_called()

    def test_finite_and_shape_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            with self.assertRaises(ValueError):
                v2.weighted_standardization(replace(rows, weights=np.full(len(rows.weights), float("nan"))))
            with self.assertRaises(ValueError):
                v2.weighted_standardization(replace(rows, ab=rows.ab[:, :-1]))
            with self.assertRaises(ValueError):
                v2.normalized_batch(rows.ab, [0], torch.full((202,), float("nan")), torch.ones(202))

    def test_input_guards_run_on_exception_and_protocol_is_canonical(self):
        with tempfile.TemporaryDirectory() as directory:
            source, protocol = Path(directory) / "source", Path(directory) / "protocol"
            source.write_bytes(b"source"); protocol.write_bytes(b"wrong protocol")
            with self.assertRaisesRegex(RuntimeError, "failure"):
                with v2.preserved_inputs((source,)):
                    raise RuntimeError("failure")
            with self.assertRaisesRegex(ValueError, "changed during"):
                with v2.preserved_inputs((source,)):
                    source.write_bytes(b"changed"); raise RuntimeError("failure")
            with patch.object(v2, "load_official_source") as loaded:
                with self.assertRaisesRegex(ValueError, "canonical v2"):
                    v2.fit(source, protocol, Path(directory) / "out")
                loaded.assert_not_called()

    def test_output_and_v1_dependency_bindings_are_not_overwritten(self):
        identity = v2.code_identity()
        self.assertIn("recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py", identity)
        self.assertIn("recognition_ml/tests/test_stroke_affinity.py", identity)
        self.assertIn("recognition_ml/ichart_recognition_ml/research/stroke_affinity_baseline.py", identity)
        self.assertIn("recognition_ml/tests/test_stroke_affinity_baseline.py", identity)
        self.assertIn("recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_baseline.py", identity)
        self.assertIn(v2.PROTOCOL_PATH, identity)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.json"
            v2.write_json(path, {"keep": True})
            before = hashlib.sha256(path.read_bytes()).hexdigest()
            with self.assertRaises(FileExistsError):
                v2.write_json(path, {"keep": False})
            self.assertEqual(before, hashlib.sha256(path.read_bytes()).hexdigest())
            with self.assertRaises(ValueError):
                v2.new_output(Path(directory))


if __name__ == "__main__":
    unittest.main()
