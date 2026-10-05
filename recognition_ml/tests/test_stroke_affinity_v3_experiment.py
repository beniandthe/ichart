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
from ichart_recognition_ml.research import stroke_affinity as core
from ichart_recognition_ml.research import stroke_affinity_experiment as v1
from ichart_recognition_ml.research import stroke_affinity_v2_experiment as v2
from ichart_recognition_ml.research import stroke_affinity_v3_experiment as v3


class StrokeAffinityV3ExperimentTests(unittest.TestCase):
    def setUp(self):
        metadata = tuple(Sample(f"{role}_UPV_W{index:02d}", 1, "A", ())
                         for role, count in (("trn", 40), ("tst", 20)) for index in range(count))
        self.training, self.development, self.reserved = split_writers(metadata)
        self.writer, self.dev_writer = self.training[0], self.development[0]
        self.strokes = (InkStroke((InkPoint(-5, 2, 0), InkPoint(-5, 2), InkPoint(5, 7, 0.2)),
            InkBounds(-6, 1, 6, 8), creation_time_offset=3),
            InkStroke((InkPoint(1, 1), InkPoint(5, 5))))

    def samples(self, writer):
        return tuple(Sample(writer, session, chr(0x400 + index), self.strokes)
                     for session in (1, 2) for index in range(97))

    def toy_targets(self, role="training", writer=None, include_singleton=False):
        writer = writer or (self.writer if role == "training" else self.dev_writer)
        samples = tuple(Sample(writer, 1, label, self.strokes) for label in "ABCD")
        targets = tuple(v3.target_from_context(v3.Context(samples[:cardinality], 32 if cardinality == 1 else 16,
            0 if cardinality == 1 else 8, v3.arm_name(cardinality, 16, 8)), role) for cardinality in (1, 2, 3, 4))
        if include_singleton:
            dot = Sample(writer, 1, ".", (InkStroke((InkPoint(9, 9),)),))
            targets += (v3.target_from_context(v3.Context((dot,), 32, 0, "single32"), role),)
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
        return v3.build_training_cache(targets, self.training, self.plan(targets), Path(directory) / "cache")

    def test_only_feature_family_changes_and_no_v2_globals_are_patched(self):
        self.assertIs(v3.all_pair_features, core.all_pair_features)
        self.assertIs(v3.predict_target, v1.predict_target)
        self.assertIs(v3.fit_rows, v2.fit_rows)
        self.assertIs(v3.weighted_standardization, v2.weighted_standardization)
        self.assertIs(v3.normalized_batch, v2.normalized_batch)
        self.assertIs(v3.target_stream, v2.target_stream)
        self.assertIs(v3.training_plan, v2.training_plan)
        self.assertEqual(v3.VERSION, "public-stroke-affinity-experiment-v3")
        self.assertEqual(v3.FEATURE_SCHEMA, "stroke-affinity-context-v1")
        self.assertEqual(v2.VERSION, "public-stroke-affinity-experiment-v2")
        self.assertEqual(v2.FEATURE_SCHEMA, "stroke-affinity-pair-local-v2")
        self.assertIsNot(v2.all_pair_features, v3.all_pair_features)

    def test_unchanged_v2_targets_source_roles_and_all_25_contexts(self):
        samples = self.samples(self.dev_writer)
        before = tuple(samples)
        contexts = tuple(v3.context_stream(samples, "development", self.development, include_five=True))
        self.assertEqual(contexts, tuple(v2.context_stream(samples, "development", self.development, include_five=True)))
        self.assertEqual(len(contexts), 194 * 25)
        self.assertEqual(len({context.arm for context in contexts}), 25)
        for context in contexts[:194] + contexts[194::97]:
            self.assertEqual(v3.target_from_context(context, "development"), v2.target_from_context(context, "development"))
        self.assertEqual(samples, before)
        self.assertIn("triple32-16-16-gap8-8", {context.arm for context in contexts})
        for target in self.toy_targets():
            self.assertEqual(target.strokes[0].creation_time_offset, 3)
            self.assertEqual(tuple(point.time_offset for point in target.strokes[0].points), (0, None, 0.2))

    def test_reserved_wrong_role_and_five_training_rejected_before_features(self):
        reserved = Sample(self.reserved[0], 1, "A", self.strokes)
        with patch.object(v3, "all_pair_features") as features:
            for role, writers in (("training", self.training), ("development", self.development)):
                with self.assertRaises(ValueError):
                    v3.target_stream((reserved,), role, writers)
            with self.assertRaises(ValueError):
                v3.context_stream(self.samples(self.writer), "training", self.training, include_five=True)
            five_sources = self.samples(self.dev_writer)[:5]
            target = v3.target_from_context(v3.Context(five_sources, 16, 8, v3.arm_name(5, 16, 8)), "development")
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    v3.build_training_cache((replace(target, role="training", writer=self.writer),), self.training,
                        self.plan((target,)), Path(directory) / "cache")
            features.assert_not_called()
        with patch.object(v3, "predict_target") as predicted:
            with self.assertRaises(ValueError):
                v3.evaluate_targets(None, None, None, (replace(self.toy_targets("development")[0], writer=self.reserved[0]),), self.development)
            predicted.assert_not_called()

    def test_metadata_preflight_matches_v2_without_constructing_features(self):
        samples = self.samples(self.writer)
        with patch.object(v3, "all_pair_features") as features, patch.object(v2, "all_pair_features") as pair_features:
            plan = v3.training_plan(samples, self.training)
            self.assertEqual(plan, v2.training_plan(samples, self.training))
            features.assert_not_called(); pair_features.assert_not_called()
        self.assertEqual(plan["targets"], 194 * 19)
        self.assertFalse(plan["affinityFeaturesConstructed"])
        self.assertFalse(plan["developmentFeaturesConstructed"])

    def test_cache_has_genuine_v1_features_and_exact_v2_supervision_weights(self):
        targets = self.toy_targets(include_singleton=True)
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory, targets)
            second = v2.build_training_cache(targets, self.training, self.plan(targets), Path(directory) / "v2-cache")
            for field in ("labels", "weights", "cardinalities"):
                np.testing.assert_array_equal(getattr(rows, field), getattr(second, field))
            self.assertEqual(rows.summary, second.summary)
            ab, ba = [], []
            for target in targets:
                _, direct_ab, direct_ba = core.all_pair_features(target.strokes)
                ab.append(direct_ab); ba.append(direct_ba)
            np.testing.assert_array_equal(rows.ab, np.concatenate(ab))
            np.testing.assert_array_equal(rows.ba, np.concatenate(ba))
            self.assertFalse(np.array_equal(rows.ab, second.ab))
            self.assertIsInstance(rows.ab, np.memmap)
            self.assertFalse(rows.ab.flags.writeable)
            self.assertEqual(rows.ab.dtype, np.float32)
            self.assertEqual(rows.weights.dtype, np.float64)
            self.assertTrue(all(abs(value - 1) < 1e-12 for value in rows.summary["baseMassByCardinality"].values()))
            self.assertAlmostEqual(rows.weights[rows.labels == 1].sum(), rows.weights[rows.labels == 0].sum())
            self.assertEqual(rows.summary["singletonTargetsExcludedFromLoss"], 1)
            manifest = json.loads((Path(directory) / "cache/manifest.json").read_text())
            self.assertEqual(manifest["version"], v3.VERSION)
            self.assertEqual(manifest["featureSchema"], v3.FEATURE_SCHEMA)

    def test_multiblock_bounded_statistics_batches_and_final_state_match_direct(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            maps = {}
            for name, values in (("ab", rows.ab), ("ba", rows.ba)):
                path = Path(directory) / ("tiled-" + name + ".npy")
                writable = np.lib.format.open_memmap(path, mode="w+", dtype=np.float32, shape=(4250, 202))
                writable[:] = np.tile(values, (85, 1))
                writable.flush(); del writable
                maps[name] = np.load(path, mmap_mode="r", allow_pickle=False)
            rows = replace(rows, **maps, labels=np.tile(rows.labels, 85), weights=np.tile(rows.weights, 85),
                cardinalities=np.tile(rows.cardinalities, 85))
            direct = v1.TrainingRows(rows.ab.copy(), rows.ba.copy(), rows.labels.copy(), rows.weights.copy(), rows.summary)
            mean, std = v3.weighted_standardization(rows)
            direct_mean, direct_std = v1.weighted_standardization(direct)
            torch.testing.assert_close(mean, direct_mean, rtol=0, atol=0)
            torch.testing.assert_close(std, direct_std, rtol=0, atol=0)
            indexes = np.array([4000, 0, 4200, 49, 1])
            full = (torch.as_tensor(direct.ab, dtype=torch.float32) - mean) / std
            torch.testing.assert_close(v3.normalized_batch(rows.ab, indexes, mean, std), full[indexes], rtol=0, atol=0)
            model, mean2, std2, history = v3.fit_rows(rows, epochs=2, unit_test=True)
            reference, reference_mean, reference_std, reference_history = v1.fit_rows(direct, epochs=2, unit_test=True)
            for key, value in model.state_dict().items():
                torch.testing.assert_close(value, reference.state_dict()[key], rtol=0, atol=0)
            torch.testing.assert_close(mean2, reference_mean, rtol=0, atol=0)
            torch.testing.assert_close(std2, reference_std, rtol=0, atol=0)
            self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in reference_history])

    def test_tiny_fit_deterministic_final_only_and_cache_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            paths = tuple((Path(directory) / "cache").glob("*"))
            before = {path: v3.file_digest(path) for path in paths}
            first, mean, std, history = v3.fit_rows(rows, epochs=2, unit_test=True)
            second, mean2, std2, history2 = v3.fit_rows(rows, epochs=2, unit_test=True)
            for key, value in first.state_dict().items():
                torch.testing.assert_close(value, second.state_dict()[key], rtol=0, atol=0)
            torch.testing.assert_close(mean, mean2, rtol=0, atol=0)
            torch.testing.assert_close(std, std2, rtol=0, atol=0)
            self.assertEqual([row["onlineWeightedLoss"] for row in history], [row["onlineWeightedLoss"] for row in history2])
            self.assertEqual(before, {path: v3.file_digest(path) for path in paths})
            with self.assertRaises(ValueError):
                v3.fit_rows(rows, epochs=2)

    def test_feature_calls_only_receive_original_ink_not_expected_answers(self):
        targets, calls = self.toy_targets(), []
        actual = v3.all_pair_features
        def features(strokes):
            calls.append(strokes); return actual(strokes)
        renamed = tuple(replace(target, identity="renamed-" + target.identity,
            source_ids=tuple("metadata-" + str(i) for i in range(target.cardinality)), single_label="G") for target in targets)
        with tempfile.TemporaryDirectory() as directory, patch.object(v3, "all_pair_features", side_effect=features), patch.object(v2, "all_pair_features") as pair_features:
            self.cache(directory, renamed)
            pair_features.assert_not_called()
        self.assertEqual(calls, [target.strokes for target in targets])

    def test_prediction_precedes_scoring_and_cardinality_audit(self):
        target, calls = self.toy_targets("development")[0], []
        def predict(*args):
            self.assertEqual(len(args), 4); calls.append("predict")
            return ((0, 1),), ((0, 1),), np.array([1.]), {"featureSeconds": 0, "inferenceAndPartitionSeconds": 0}
        actual = v3.partition_metrics
        def score(*args):
            calls.append("score"); return actual(*args)
        with patch.object(v3, "predict_target", side_effect=predict), patch.object(v3, "partition_metrics", side_effect=score):
            result = v3.evaluate_targets(None, None, None, (target,), self.development)
        self.assertEqual(calls, ["predict", "score"])
        row = result["rows"][0]
        self.assertEqual(row["cardinality"], 1)
        self.assertTrue(row["exactOwnerMatch"])
        self.assertEqual(row["groups"], ((0, 1),))
        self.assertEqual(row["expectedOwners"], target.owners)
        self.assertEqual(row["sourceIDs"], target.source_ids)
        self.assertEqual(row["edgeConfusion"]["edgeTruePositive"], 1)
        self.assertEqual(result["singlePartitionsByLabel"]["A"]["exactPartitions"], 1)

    def test_shape_finite_and_complete_plan_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = self.cache(directory)
            with self.assertRaises(ValueError):
                v3.weighted_standardization(replace(rows, ab=rows.ab[:, :-1]))
            with self.assertRaises(ValueError):
                v3.weighted_standardization(replace(rows, weights=np.full(len(rows.weights), float("nan"))))
            with self.assertRaises(ValueError):
                v3.normalized_batch(rows.ab, [0], torch.full((202,), float("nan")), torch.ones(202))
        with tempfile.TemporaryDirectory() as directory, patch.object(v3, "all_pair_features", return_value=((), np.empty((0, 201), dtype=np.float32), np.empty((0, 201), dtype=np.float32))):
            with self.assertRaises(ValueError):
                self.cache(directory)

    def test_genuine_v3_provenance_canonical_protocol_and_guards_on_failure(self):
        identity = v3.code_identity()
        for path in (v1.PROTOCOL_PATH if hasattr(v1, "PROTOCOL_PATH") else "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md",
                v2.PROTOCOL_PATH, v3.PROTOCOL_PATH,
                "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
                "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_experiment.py",
                "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_baseline.py",
                "recognition_ml/tests/test_stroke_affinity_v3_baseline.py"):
            self.assertIn(path, identity)
        with tempfile.TemporaryDirectory() as directory:
            source, protocol = Path(directory) / "source", Path(directory) / "protocol"
            source.write_bytes(b"source"); protocol.write_bytes(b"wrong protocol")
            with self.assertRaisesRegex(RuntimeError, "failure"):
                with v3.preserved_inputs((source,)):
                    raise RuntimeError("failure")
            with self.assertRaisesRegex(ValueError, "changed during v3"):
                with v3.preserved_inputs((source,)):
                    source.write_bytes(b"changed"); raise RuntimeError("failure")
            with patch.object(v3, "load_official_source") as loaded:
                with self.assertRaisesRegex(ValueError, "canonical v3"):
                    v3.fit(source, protocol, Path(directory) / "out")
                loaded.assert_not_called()

    def test_historical_versions_cannot_masquerade_as_v3_and_no_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory) / "run"; run.mkdir()
            for version in (v1.VERSION, v2.VERSION):
                (run / "report.json").write_text(json.dumps({"version": version}))
                with patch.object(v3, "load_official_source") as loaded:
                    with self.assertRaisesRegex(ValueError, "frozen v3"):
                        v3._evaluate(Path(directory) / "source", run, Path(directory) / "out")
                    loaded.assert_not_called()
            output = Path(directory) / "keep.json"
            v3.write_json(output, {"keep": True})
            before = v3.file_digest(output)
            with self.assertRaises(FileExistsError):
                v3.write_json(output, {"keep": False})
            self.assertEqual(before, v3.file_digest(output))
            with self.assertRaises(ValueError):
                v3.new_output(run)


if __name__ == "__main__":
    unittest.main()
