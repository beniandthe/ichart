import importlib.util
import math
import unittest
from dataclasses import replace
from itertools import combinations

from ichart_recognition_ml.features import InkBounds, InkPoint, InkStroke

HAS_NUMPY = importlib.util.find_spec("numpy") is not None
HAS_TORCH = importlib.util.find_spec("torch") is not None


def stroke(*points):
    return InkStroke(tuple(InkPoint(x, y, i * 0.03) for i, (x, y) in enumerate(points)),
                     creation_time_offset=2.0)


@unittest.skipUnless(HAS_NUMPY, "Optional NumPy feature dependencies required")
class StrokeAffinityFeatureTests(unittest.TestCase):
    def setUp(self):
        import numpy as np
        from ichart_recognition_ml.research import stroke_affinity as affinity
        self.np, self.affinity = np, affinity
        self.source = (stroke((0, 0), (0, 3)), stroke((4, 0), (4, 3)))

    def test_explicit_geometry_contract_and_histogram_mass(self):
        values = self.affinity.affinity_features(self.source, 0, 1)
        expected = [0, .75, .75, 0, .75, .75, 1, 0, 1, 1.25, 1.25, 1,
                    1, 1, 1, 0, 0, .75, 1, .75 / (1.5 + 1e-6),
                    .75 / (1.5 + 1e-6), 4 / 7]
        self.assertEqual(values.dtype, self.np.float32)
        self.assertEqual(values.shape, (202,))
        self.np.testing.assert_allclose(values[:22], expected, atol=1e-7, rtol=0)
        for offset in (22, 82, 142):
            self.assertAlmostEqual(float(values[offset:offset + 60].sum()), 1, places=6)
        self.assertTrue(self.np.isfinite(values).all())

    def test_uniform_scale_translation_and_source_immutability(self):
        source = self.source + (stroke((7, -2), (9, 2), (10, 0)), stroke((0, 7)))
        original = tuple(source)
        expected = self.affinity.affinity_features(source, 0, 2)
        for scale in (.25, 9.0):
            transformed = tuple(InkStroke(tuple(replace(p, x=p.x * scale - 101, y=p.y * scale + 27)
                                                  for p in s.points), creation_time_offset=s.creation_time_offset)
                                for s in source)
            self.np.testing.assert_allclose(self.affinity.affinity_features(transformed, 0, 2),
                                           expected, atol=2e-7, rtol=0)
        self.assertEqual(source, original)
        self.assertTrue(all(a is b for a, b in zip(source, original)))
        self.assertTrue(all(p.time_offset is not None for s in source for p in s.points))

    def test_all_pairs_and_permutation_equivariance_without_geometry_ties(self):
        source = self.source + (stroke((7, -2), (9, 2)), stroke((0, 7)),
                                stroke((12, 5), (13, 8)), stroke((-3, 1), (-2, 2)))
        edges, ab, ba = self.affinity.all_pair_features(source)
        self.assertEqual(edges, tuple(combinations(range(6), 2)))
        self.assertEqual(ab.shape, (15, 202))
        self.assertEqual(ba.shape, ab.shape)
        self.np.testing.assert_array_equal(ab[1], self.affinity.affinity_features(source, 0, 2))
        self.np.testing.assert_array_equal(ba[1], self.affinity.affinity_features(source, 2, 0))
        order = (4, 2, 0, 5, 1, 3)
        permuted = tuple(source[i] for i in order)
        for i, j in edges:
            self.np.testing.assert_array_equal(self.affinity.affinity_features(permuted, order.index(i), order.index(j)),
                                              self.affinity.affinity_features(source, i, j))

    def test_single_stroke_empty_pairs_dot_and_duplicate_points(self):
        dot = stroke((3, 4), (3, 4), (3, 4))
        edges, ab, ba = self.affinity.all_pair_features((dot,))
        self.assertEqual(edges, ())
        self.assertEqual(ab.shape, (0, 202))
        self.assertEqual(ba.shape, (0, 202))
        values = self.affinity.affinity_features((dot, dot), 0, 1)
        self.np.testing.assert_array_equal(values[:22], self.np.zeros(22, dtype=self.np.float32))
        for offset in (22, 82, 142):
            self.assertEqual(values[offset], 1)
            self.assertEqual(float(values[offset + 1:offset + 60].sum()), 0)
        repeated = stroke((0, 0), (0, 0), (0, 3), (0, 3))
        self.np.testing.assert_array_equal(self.affinity.affinity_features((repeated, self.source[1]), 0, 1),
                                          self.affinity.affinity_features(self.source, 0, 1))

    def test_neighborhood_equal_content_ties_are_not_index_features(self):
        source = self.source + (stroke((8, 4)),) * 4
        order = (0, 1, 5, 4, 3, 2)
        permuted = tuple(source[i] for i in order)
        self.np.testing.assert_array_equal(self.affinity.affinity_features(source, 0, 1),
                                          self.affinity.affinity_features(permuted, 0, 1))

    def test_histogram_radial_major_order_zero_and_opposite_angle_bins(self):
        source = (stroke((0, 0)), stroke((1, 0)))
        forward = self.affinity.affinity_features(source, 0, 1)
        backward = self.affinity.affinity_features(source, 1, 0)
        for offset in (22, 82, 142):
            expected = self.np.zeros(60, dtype=self.np.float32)
            expected[0] = expected[48] = .5
            self.np.testing.assert_array_equal(forward[offset:offset + 60], expected)
            expected[48], expected[54] = 0, .5
            self.np.testing.assert_array_equal(backward[offset:offset + 60], expected)

    def test_invalid_or_oversized_geometry_fails_closed(self):
        invalid = [(), None, (None,), (self.source[0],) * 65,
                   (InkStroke((), bounds=InkBounds(0, 0, 0, 0)),),
                   (stroke((math.nan, 0)),), (stroke((0, math.inf)),),
                   (InkStroke((InkPoint(0, 0, math.nan),)),),
                   (InkStroke((InkPoint(0, 0),), creation_time_offset=math.inf),),
                   (InkStroke((InkPoint(0, 0),), bounds=InkBounds(1, 0, 0, 1)),),
                   (InkStroke((None,), bounds=InkBounds(0, 0, 0, 0)),),
                   (InkStroke((InkPoint(0, 0),), bounds={}),),
                   (stroke((10 ** 400, 0)),),
                   (stroke((-1e308, 0), (1e308, 0)),),
                   (stroke(*([(0, 0)] * 8193)),)]
        for source in invalid:
            with self.subTest(source_type=type(source)), self.assertRaises(ValueError):
                self.affinity.all_pair_features(source)
        for i, j in ((0, 0), (-1, 1), (0, 2), (False, 1), (0, 1.0)):
            with self.subTest(indexes=(i, j)), self.assertRaises(ValueError):
                self.affinity.affinity_features(self.source, i, j)

    def test_exact_validation_limits_are_inclusive(self):
        self.assertEqual(len(self.affinity.validate_strokes((stroke((0, 0)),) * 64)), 64)
        source = (stroke(*([(0, 0)] * 8192)),)
        self.assertIs(self.affinity.validate_strokes(source)[0], source[0])

    def test_validation_and_reconstruction_retain_original_object_identity(self):
        source = self.source + (stroke((8, 4)),)
        frozen = self.affinity.validate_strokes(list(source))
        self.assertIsInstance(frozen, tuple)
        groups = self.affinity.reconstruct_groups(source, ((2,), (1, 0)))
        self.assertEqual(groups, ((source[0], source[1]), (source[2],)))
        self.assertIs(groups[0][0], source[0])
        self.assertIs(groups[0][1], source[1])
        self.assertIs(groups[1][0], source[2])
        for bad in (((0,), (1,)), ((0, 1), (1, 2)), ((0, 1, 2), ()), ((0, 1, 3),)):
            with self.subTest(groups=bad), self.assertRaises(ValueError):
                self.affinity.reconstruct_groups(source, bad)


@unittest.skipUnless(HAS_NUMPY, "Optional NumPy feature dependencies required")
class StrokeAffinityPartitionTests(unittest.TestCase):
    def setUp(self):
        from ichart_recognition_ml.research.stroke_affinity import partition_from_logits
        self.partition = partition_from_logits

    def test_complete_source_cover_and_negative_bridge_prevents_transitive_merge(self):
        edges = tuple(combinations(range(4), 2))
        groups = self.partition(4, edges, (3, -5, -5, -5, -5, 2))
        self.assertEqual(groups, ((0, 1), (2, 3)))
        self.assertEqual(sorted(i for group in groups for i in group), list(range(4)))
        self.assertEqual(self.partition(3, ((0, 1), (0, 2), (1, 2)), (4, -10, 3)), ((0, 1), (2,)))

    def test_no_positive_merge_singletons_and_one_stroke(self):
        self.assertEqual(self.partition(1, (), ()), ((0,),))
        self.assertEqual(self.partition(3, ((0, 1), (0, 2), (1, 2)), (0, -1, 0)), ((0,), (1,), (2,)))

    def test_ties_use_index_tuples_and_edge_order_does_not_change_results(self):
        edges, scores = ((0, 1), (0, 2), (1, 2)), (1, -10, 1)
        expected = ((0, 1), (2,))
        self.assertEqual(self.partition(3, edges, scores), expected)
        self.assertEqual(self.partition(3, tuple(reversed(edges)), tuple(reversed(scores))), expected)
        self.assertEqual(self.partition(3, tuple((j, i) for i, j in edges), scores), expected)

    def test_partition_permutation_equivariance_when_merge_scores_have_no_ties(self):
        count = 5
        edges = tuple(combinations(range(count), 2))
        weights = {edge: (-11.0 - k) for k, edge in enumerate(edges)}
        weights[(0, 1)] = 5
        weights[(2, 3)] = 3
        expected = self.partition(count, edges, tuple(weights[e] for e in edges))
        order = (3, 0, 4, 2, 1)
        moved_scores = tuple(weights[tuple(sorted((order[i], order[j])))] for i, j in edges)
        actual = self.partition(count, edges, moved_scores)
        restored = tuple(sorted((tuple(sorted(order[i] for i in group)) for group in actual), key=lambda g: g[0]))
        self.assertEqual(restored, expected)

    def test_decoder_rejects_incomplete_duplicate_nonfinite_and_bad_indexes(self):
        malformed = [
            (0, (), ()), (65, (), ()), (True, (), ()), (2.0, ((0, 1),), (1,)),
            (3, ((0, 1),), (1,)), (2, ((0, 1),), ()),
            (3, ((0, 1), (1, 0), (1, 2)), (1, 1, 1)),
            (2, ((0, 0),), (1,)), (2, ((0, 2),), (1,)),
            (2, ((False, 1),), (1,)), (2, ((0, 1.0),), (1,)),
            (2, ((0, 1, 2),), (1,)), (2, ((0, 1),), (math.nan,)),
            (2, ((0, 1),), (math.inf,)), (2, ((0, 1),), (True,)),
            (2, ((0, 1),), ("1",)), (3, ((0, 1), (0, 2), (1, 2)), (1e308, 1e308, 1e308)),
            (2, ((0, 1),), (10 ** 400,)),
        ]
        for count, edges, scores in malformed:
            with self.subTest(count=count, edges=edges), self.assertRaises(ValueError):
                self.partition(count, edges, scores)


@unittest.skipUnless(HAS_NUMPY and HAS_TORCH, "Optional PyTorch training dependencies required")
class StrokeAffinityModelTests(unittest.TestCase):
    def setUp(self):
        import torch
        from ichart_recognition_ml.research.stroke_affinity import StrokeAffinityModel
        self.torch = torch
        torch.set_num_threads(2)
        torch.manual_seed(29)
        self.model = StrokeAffinityModel()

    def test_symmetric_logits_shapes_finite_outputs_and_differentiability(self):
        torch = self.torch
        ab, ba = torch.rand(7, 202), torch.rand(7, 202)
        symmetric = self.model.symmetric_logits(ab, ba)
        self.assertEqual(symmetric.shape, (7,))
        torch.testing.assert_close(symmetric, self.model.symmetric_logits(ba, ab), rtol=0, atol=0)
        self.assertTrue(torch.isfinite(symmetric).all())
        symmetric.sum().backward()
        self.assertTrue(all(p.grad is not None and torch.isfinite(p.grad).all() for p in self.model.parameters()))
        self.assertEqual(self.model(torch.empty(0, 202)).shape, (0,))

    def test_model_refuses_bad_feature_shapes_dtype_and_nonfinite_values(self):
        torch = self.torch
        for bad in (torch.zeros(202), torch.zeros(2, 201), torch.zeros(2, 202, dtype=torch.float64),
                    torch.full((2, 202), math.nan), torch.full((2, 202), math.inf), [[0] * 202]):
            with self.subTest(kind=type(bad)), self.assertRaises(ValueError):
                self.model(bad)
        with self.assertRaises(ValueError):
            self.model.symmetric_logits(torch.zeros(2, 202), torch.zeros(3, 202))

    def test_symmetric_average_refuses_finite_directional_output_overflow(self):
        from unittest.mock import patch
        torch = self.torch
        features = torch.zeros(1, 202)
        maximum = torch.tensor([torch.finfo(torch.float32).max], dtype=torch.float32)
        with patch.object(self.model, "forward", side_effect=(maximum, maximum)):
            with self.assertRaisesRegex(ValueError, "Nonfinite symmetric affinity logits"):
                self.model.symmetric_logits(features, features)
        with patch.object(self.model, "forward", side_effect=(maximum, -maximum)):
            torch.testing.assert_close(self.model.symmetric_logits(features, features), torch.zeros(1), rtol=0, atol=0)
