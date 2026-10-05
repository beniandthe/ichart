import importlib.util
import math
import unittest
from dataclasses import replace
from itertools import combinations

from ichart_recognition_ml.features import InkBounds, InkPoint, InkStroke

HAS_NUMPY = importlib.util.find_spec("numpy") is not None
HAS_TORCH = importlib.util.find_spec("torch") is not None


def stroke(*points):
    return InkStroke(tuple(InkPoint(x, y, i * .03) for i, (x, y) in enumerate(points)),
                     creation_time_offset=3.0)


@unittest.skipUnless(HAS_NUMPY, "Optional NumPy feature dependencies required")
class StrokeAffinityV2FeatureTests(unittest.TestCase):
    def setUp(self):
        import numpy as np
        from ichart_recognition_ml.research import stroke_affinity as v1
        from ichart_recognition_ml.research import stroke_affinity_v2 as v2
        self.np, self.v1, self.v2 = np, v1, v2
        self.pair = (stroke((0, 0), (0, 3)), stroke((4, 0), (4, 3)))

    def test_schema_api_shapes_and_frozen_dependency_identity(self):
        self.assertEqual(self.v2.FEATURE_SCHEMA, "stroke-affinity-pair-local-v2")
        self.assertEqual(self.v2.FEATURE_COUNT, 202)
        self.assertEqual(self.v2.SAMPLE_COUNT, 32)
        self.assertEqual((self.v2.MAXIMUM_STROKES, self.v2.MAXIMUM_POINTS), (64, 8192))
        for name in ("StrokeAffinityModel", "partition_from_logits", "validate_strokes",
                     "validate_partition", "reconstruct_groups"):
            self.assertIs(getattr(self.v2, name), getattr(self.v1, name))
        source = self.pair + (stroke((9, 2)),)
        edges, ab, ba = self.v2.all_pair_features(source)
        self.assertEqual(edges, tuple(combinations(range(3), 2)))
        self.assertEqual(ab.shape, (3, 202))
        self.assertEqual(ba.shape, ab.shape)
        self.assertEqual(ab.dtype, self.np.float32)
        self.assertEqual(ba.dtype, self.np.float32)
        self.np.testing.assert_array_equal(ab[0], self.v2.affinity_features(source, 0, 1))
        self.np.testing.assert_array_equal(ba[0], self.v2.affinity_features(source, 1, 0))

    def test_first_82_are_exactly_independent_of_distant_context(self):
        pair = (stroke((.1, .2), (1.9, 2.3), (3.5, .8)),
                stroke((5.2, -.7), (6.3, 1.1), (7.9, 3.4)))
        for direction in ((0, 1), (1, 0)):
            expected = self.v2.affinity_features(pair, *direction)
            for distant in (stroke((1000, -300), (1002, -290)),
                            stroke((-1e100, 1e100), (-1e100, 1e100))):
                actual = self.v2.affinity_features(pair + (distant,), *direction)
                self.np.testing.assert_array_equal(actual[:82], expected[:82])

    def test_surrounding_histograms_may_change_and_retain_v1_definitions(self):
        original = self.v2.affinity_features(self.pair, 0, 1)
        extended = self.pair + (stroke((100, 100), (104, 109)),)
        actual = self.v2.affinity_features(extended, 0, 1)
        self.np.testing.assert_array_equal(actual[:82], original[:82])
        self.assertFalse(self.np.array_equal(actual[82:], original[82:]))
        self.np.testing.assert_array_equal(actual[82:], self.v1.affinity_features(extended, 0, 1)[82:])
        self.assertFalse(self.np.array_equal(self.v1.affinity_features(extended, 0, 1)[:22], original[:22]))

    def test_explicit_pair_geometry_and_pair_union_aspect_not_target_aspect(self):
        extended = self.pair + (stroke((0, 100)),)
        values = self.v2.affinity_features(extended, 0, 1)
        expected = [0, .75, .75, 0, .75, .75, 1, 0, 1, 1.25, 1.25, 1,
                    1, 1, 1, 0, 0, .75, 1, .75 / (1.5 + 1e-6),
                    .75 / (1.5 + 1e-6), 4 / 7]
        self.np.testing.assert_allclose(values[:22], expected, atol=1e-7, rtol=0)
        self.assertNotEqual(values[21], self.v1.affinity_features(extended, 0, 1)[21])
        for offset in (22, 82, 142):
            self.assertAlmostEqual(float(values[offset:offset + 60].sum()), 1, places=6)

    def test_uniform_affine_features_and_source_objects_are_preserved(self):
        source = self.pair + (stroke((9, 2)),)
        expected = self.v2.affinity_features(source, 0, 1)
        for scale in (.25, 9.0):
            moved = tuple(InkStroke(tuple(replace(p, x=p.x * scale - 70, y=p.y * scale + 21)
                                           for p in s.points), creation_time_offset=s.creation_time_offset)
                          for s in source)
            self.np.testing.assert_allclose(self.v2.affinity_features(moved, 0, 1), expected, atol=2e-7, rtol=0)
        edges, _, _ = self.v2.all_pair_features(source)
        groups = self.v2.partition_from_logits(3, edges, (4, -5, -5))
        self.assertEqual(groups, ((0, 1), (2,)))
        restored = self.v2.reconstruct_groups(source, groups)
        self.assertIs(restored[0][0], source[0])
        self.assertIs(restored[0][1], source[1])
        self.assertIs(restored[1][0], source[2])
        self.assertEqual(source[0].points[1].time_offset, .03)
        self.assertEqual(source[0].creation_time_offset, 3)

    def test_permuted_sources_keep_features_equivariant(self):
        source = self.pair + (stroke((7, -2), (9, 2)), stroke((0, 7)),
                              stroke((12, 5), (13, 8)), stroke((-3, 1), (-2, 2)))
        order = (4, 2, 0, 5, 1, 3)
        moved = tuple(source[i] for i in order)
        for i, j in combinations(range(6), 2):
            self.np.testing.assert_array_equal(self.v2.affinity_features(moved, order.index(i), order.index(j)),
                                              self.v2.affinity_features(source, i, j))

    def test_dots_duplicate_points_and_empty_one_stroke_edges(self):
        dot = stroke((3, 4), (3, 4))
        edges, ab, ba = self.v2.all_pair_features((dot,))
        self.assertEqual(edges, ())
        self.assertEqual(ab.shape, (0, 202))
        self.assertEqual(ba.shape, (0, 202))
        values = self.v2.affinity_features((dot, dot), 0, 1)
        self.np.testing.assert_array_equal(values[:22], self.np.zeros(22, dtype=self.np.float32))
        for offset in (22, 82, 142):
            self.assertEqual(values[offset], 1)
            self.assertEqual(float(values[offset + 1:offset + 60].sum()), 0)
        repeated = stroke((0, 0), (0, 0), (0, 3), (0, 3))
        self.np.testing.assert_array_equal(self.v2.affinity_features((repeated, self.pair[1]), 0, 1),
                                          self.v2.affinity_features(self.pair, 0, 1))

    def test_malformed_geometry_indices_and_coverage_remain_fail_closed(self):
        for bad in ((), None, (self.pair[0],) * 65, (stroke((math.nan, 0)),),
                    (stroke(*([(0, 0)] * 8193)),),
                    (InkStroke((), bounds=InkBounds(0, 0, 0, 0)),),
                    (stroke((10 ** 400, 0)),), (stroke((-1e308, 0), (1e308, 0)),)):
            with self.subTest(source_type=type(bad)), self.assertRaises(ValueError):
                self.v2.all_pair_features(bad)
        for i, j in ((0, 0), (-1, 1), (0, 2), (False, 1), (0, 1.0)):
            with self.subTest(indexes=(i, j)), self.assertRaises(ValueError):
                self.v2.affinity_features(self.pair, i, j)
        with self.assertRaises(ValueError):
            self.v2.partition_from_logits(2, ((0, 1),), (math.inf,))
        with self.assertRaises(ValueError):
            self.v2.reconstruct_groups(self.pair, ((0,), (0,)))


@unittest.skipUnless(HAS_NUMPY and HAS_TORCH, "Optional PyTorch training dependencies required")
class StrokeAffinityV2ModelTests(unittest.TestCase):
    def test_shared_model_preserves_parameter_count_and_symmetric_output(self):
        import torch
        from ichart_recognition_ml.research import stroke_affinity_v2 as v2
        torch.set_num_threads(2)
        torch.manual_seed(29)
        model = v2.StrokeAffinityModel()
        self.assertEqual(sum(p.numel() for p in model.parameters()), 15_105)
        _, ab, ba = v2.all_pair_features((stroke((0, 0), (2, 3)), stroke((4, 0), (4, 3))))
        a, b = torch.from_numpy(ab), torch.from_numpy(ba)
        actual = model.symmetric_logits(a, b)
        self.assertEqual(actual.shape, (1,))
        torch.testing.assert_close(actual, model.symmetric_logits(b, a), rtol=0, atol=0)
        self.assertTrue(torch.isfinite(actual).all())
