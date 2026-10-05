import itertools
import math
import unittest

import numpy as np
import torch
from torch.nn import functional as F

from ichart_recognition_ml.features import (
    FeatureEncodingError,
    InkBounds,
    InkPoint,
    InkStroke,
    RASTER_HEIGHT,
    RASTER_WIDTH,
    rasterize,
)
from ichart_recognition_ml.research import personal_stroke_field as directed
from ichart_recognition_ml.research import personal_unoriented_stroke_field as unoriented


class PersonalUnorientedStrokeFieldTests(unittest.TestCase):
    @staticmethod
    def _tensor(strokes):
        return torch.from_numpy(
            unoriented.encode_unoriented_stroke_field(strokes)
        ).unsqueeze(0)

    def test_occupancy_is_app_exact_and_dot_or_zero_length_has_endpoint_only(self):
        strokes = (
            InkStroke((InkPoint(-5.0, 1.0),)),
            InkStroke((InkPoint(5.0, -1.0), InkPoint(5.0, -1.0))),
        )
        encoded = unoriented.encode_unoriented_stroke_field(strokes)
        occupancy = (
            np.frombuffer(rasterize(strokes).pixels, dtype=np.uint8)
            .reshape(RASTER_HEIGHT, RASTER_WIDTH)
            .astype(np.float32)
            / np.float32(255.0)
        )
        self.assertEqual(unoriented.VERSION, "personal-unoriented-stroke-field-v1")
        self.assertEqual(unoriented.CHANNEL_NAMES, (
            "occupancy", "orientationXX", "orientationXY", "orientationYY",
            "endpointUnion",
        ))
        self.assertEqual(encoded.shape, (5, RASTER_HEIGHT, RASTER_WIDTH))
        self.assertEqual(encoded.dtype, np.float32)
        self.assertTrue(np.array_equal(encoded[0], occupancy))
        self.assertFalse(np.any(encoded[1:4]))
        self.assertTrue(np.array_equal(encoded[4], occupancy))

    def test_every_stroke_reversal_subset_and_enumeration_permutation_are_exact(self):
        strokes = (
            InkStroke((InkPoint(-11, -4), InkPoint(-5, 3), InkPoint(1, 5))),
            InkStroke((InkPoint(-7, 6), InkPoint(7, -6))),
            InkStroke((InkPoint(-9, 0), InkPoint(9, 0), InkPoint(-9, 0))),
        )
        expected = unoriented.encode_unoriented_stroke_field(strokes)
        for reversals in itertools.product((False, True), repeat=len(strokes)):
            changed = tuple(
                InkStroke(tuple(reversed(stroke.points))) if reverse else stroke
                for stroke, reverse in zip(strokes, reversals)
            )
            with self.subTest(reversals=reversals):
                self.assertEqual(
                    unoriented.encode_unoriented_stroke_field(changed).tobytes(),
                    expected.tobytes(),
                )
        for permutation in itertools.permutations(strokes):
            with self.subTest(permutation=permutation):
                self.assertEqual(
                    unoriented.encode_unoriented_stroke_field(permutation).tobytes(),
                    expected.tobytes(),
                )

    def test_retracing_does_not_cancel_and_crossing_averages_outer_products(self):
        retraced = (InkStroke((InkPoint(-8, 0), InkPoint(8, 0), InkPoint(-8, 0))),)
        encoded = unoriented.encode_unoriented_stroke_field(retraced)
        signed = directed.encode_stroke_field(retraced)
        active = encoded[1] + encoded[3] > 0.99
        self.assertTrue(active.any())
        self.assertLess(float(np.abs(signed[1:3, active]).max()), 1e-7)
        self.assertTrue(np.allclose(encoded[1, active], 1.0, rtol=0, atol=1e-7))
        self.assertFalse(np.any(encoded[2:4, active]))

        crossing = unoriented.encode_unoriented_stroke_field((
            InkStroke((InkPoint(-10, 0), InkPoint(10, 0))),
            InkStroke((InkPoint(0, -10), InkPoint(0, 10))),
        ))
        center = (RASTER_HEIGHT // 2, RASTER_WIDTH // 2)
        self.assertGreater(float(crossing[1][center]), 0.2)
        self.assertGreater(float(crossing[3][center]), 0.2)
        self.assertAlmostEqual(float(crossing[1][center] + crossing[3][center]), 1.0, places=6)
        self.assertAlmostEqual(float(crossing[2][center]), 0.0, places=6)

    def test_subdivision_is_stable_and_no_pen_lift_bridge_is_invented(self):
        whole = (InkStroke((InkPoint(-9, -3), InkPoint(9, 3))),)
        subdivided = (InkStroke((
            InkPoint(-9, -3), InkPoint(-3, -1), InkPoint(3, 1), InkPoint(9, 3),
        )),)
        np.testing.assert_allclose(
            unoriented.encode_unoriented_stroke_field(whole),
            unoriented.encode_unoriented_stroke_field(subdivided),
            rtol=0,
            atol=2e-6,
        )

        separated = unoriented.encode_unoriented_stroke_field((
            InkStroke((InkPoint(-10, -5), InkPoint(-10, -2))),
            InkStroke((InkPoint(10, 2), InkPoint(10, 5))),
        ))
        self.assertEqual(float(separated[0, RASTER_HEIGHT // 2, RASTER_WIDTH // 2]), 0.0)
        self.assertEqual(float(separated[1:4, RASTER_HEIGHT // 2, RASTER_WIDTH // 2].sum()), 0.0)

    def test_orientation_is_finite_positive_semidefinite_and_unit_trace_when_active(self):
        encoded = unoriented.encode_unoriented_stroke_field((
            InkStroke((InkPoint(-12, -5), InkPoint(-8, 4), InkPoint(0, 7), InkPoint(9, 1))),
            InkStroke((InkPoint(-7, 6), InkPoint(8, -4))),
            InkStroke((InkPoint(-6, -6), InkPoint(6, 6))),
        ))
        xx, xy, yy = encoded[1], encoded[2], encoded[3]
        trace = xx + yy
        determinant = xx * yy - xy * xy
        active = trace > 1e-7
        self.assertTrue(np.isfinite(encoded).all())
        self.assertTrue(active.any())
        self.assertGreaterEqual(float(xx.min()), 0.0)
        self.assertGreaterEqual(float(yy.min()), 0.0)
        self.assertLessEqual(float(xx.max()), 1.0)
        self.assertLessEqual(float(yy.max()), 1.0)
        self.assertLessEqual(float(np.abs(xy).max()), 0.5 + 1e-7)
        np.testing.assert_allclose(trace[active], 1.0, rtol=0, atol=2e-6)
        self.assertGreaterEqual(float(determinant[active].min()), -2e-6)

    def test_augmentation_uses_historical_grid_and_rotates_orientation_tensor(self):
        source = self._tensor((InkStroke((InkPoint(-8, 0), InkPoint(8, 0))),))
        unchanged = source.clone()
        draws = torch.tensor([[1.0, 0.5, 0.5, 0.5]], dtype=torch.float32)
        augmented = unoriented.augment_unoriented_stroke_fields(source, draws)
        self.assertTrue(torch.equal(source, unchanged))

        angle = torch.tensor(math.radians(8.0), dtype=torch.float32)
        theta = torch.zeros((1, 2, 3), dtype=torch.float32)
        theta[:, 0, 0] = torch.cos(angle)
        theta[:, 1, 1] = torch.cos(angle)
        theta[:, 0, 1] = -torch.sin(angle) * RASTER_HEIGHT / RASTER_WIDTH
        theta[:, 1, 0] = torch.sin(angle) * RASTER_WIDTH / RASTER_HEIGHT
        grid = F.affine_grid(theta, source.shape, align_corners=False)
        spatial = F.grid_sample(
            source, grid, mode="bilinear", padding_mode="zeros", align_corners=False
        )
        torch.testing.assert_close(augmented[:, :1], spatial[:, :1], rtol=0, atol=0)
        torch.testing.assert_close(augmented[:, 4:5], spatial[:, 4:5], rtol=0, atol=0)

        trace = augmented[0, 1] + augmented[0, 3]
        active = trace > 0.2
        observed = torch.stack((
            (augmented[0, 1] / trace.clamp_min(1e-8))[active].mean(),
            (augmented[0, 2] / trace.clamp_min(1e-8))[active].mean(),
            (augmented[0, 3] / trace.clamp_min(1e-8))[active].mean(),
        ))
        cosine = math.cos(math.radians(-8.0))
        sine = math.sin(math.radians(-8.0))
        expected = torch.tensor(
            [cosine * cosine, cosine * sine, sine * sine], dtype=torch.float32
        )
        torch.testing.assert_close(observed, expected, rtol=0, atol=2e-5)

        generator = torch.Generator().manual_seed(29)
        mixed_draws = unoriented.sample_affine_draws(4, generator)
        mixed_source = source.repeat(4, 1, 1, 1)
        neutral_mixed = unoriented.augment_unoriented_stroke_fields(
            mixed_source, mixed_draws
        )
        directed_mixed = directed.augment_stroke_fields(mixed_source, mixed_draws)
        torch.testing.assert_close(
            neutral_mixed[:, :1], directed_mixed[:, :1], rtol=0, atol=0
        )

    def test_matched_model_reuses_architecture_masks_control_and_backpropagates(self):
        torch.manual_seed(29)
        candidate = unoriented.PersonalUnorientedStrokeFieldEncoder(
            102, "strokeField"
        )
        torch.manual_seed(29)
        control = unoriented.PersonalUnorientedStrokeFieldEncoder(102, "rasterControl")
        self.assertEqual(candidate.state_dict().keys(), control.state_dict().keys())
        self.assertTrue(all(
            torch.equal(candidate.state_dict()[name], control.state_dict()[name])
            for name in candidate.state_dict()
        ))

        base = self._tensor((
            InkStroke((InkPoint(-6, -3), InkPoint(5, 4))),
            InkStroke((InkPoint(-2, 5), InkPoint(6, -4))),
        ))
        changed = base.clone()
        changed[:, 1:] = torch.randn_like(changed[:, 1:])
        control.eval()
        with torch.inference_mode():
            first = control(base)
            second = control(changed)
        torch.testing.assert_close(first[0], second[0], rtol=0, atol=0)
        torch.testing.assert_close(first[1], second[1], rtol=0, atol=0)

        candidate.train()
        differentiable = base.clone().requires_grad_(True)
        embedding, logits = candidate(differentiable)
        self.assertEqual(tuple(embedding.shape), (1, 128))
        self.assertEqual(tuple(logits.shape), (1, 102))
        F.cross_entropy(logits, torch.tensor([0])).backward()
        self.assertGreater(float(differentiable.grad[:, 1:].abs().sum()), 0.0)
        self.assertGreater(float(candidate.convolution[1].weight.grad[:, 1:].abs().sum()), 0.0)

    def test_invalid_geometry_fields_draws_and_model_arms_fail_closed(self):
        with self.assertRaises(FeatureEncodingError):
            unoriented.encode_unoriented_stroke_field((InkStroke(()),))
        with self.assertRaises(FeatureEncodingError):
            unoriented.encode_unoriented_stroke_field((
                InkStroke((InkPoint(float("nan"), 0), InkPoint(1, 1))),
            ))
        with self.assertRaises(FeatureEncodingError):
            unoriented.encode_unoriented_stroke_field((
                InkStroke(
                    (InkPoint(0, 0), InkPoint(1, 1)),
                    bounds=InkBounds(1, 0, 0, 1),
                ),
            ))
        fields = torch.zeros((1, 5, 96, 256), dtype=torch.float32)
        draws = torch.full((1, 4), 0.5, dtype=torch.float32)
        with self.assertRaisesRegex(ValueError, "wrong shape"):
            unoriented.augment_unoriented_stroke_fields(fields[:, :4], draws)
        broken = fields.clone()
        broken[0, 2, 0, 0] = float("nan")
        with self.assertRaisesRegex(ValueError, "finite"):
            unoriented.augment_unoriented_stroke_fields(broken, draws)
        with self.assertRaisesRegex(ValueError, r"\[0,1\]"):
            unoriented.augment_unoriented_stroke_fields(
                fields, torch.tensor([[1.1, 0.5, 0.5, 0.5]], dtype=torch.float32)
            )
        with self.assertRaisesRegex(ValueError, "Unknown"):
            unoriented.PersonalUnorientedStrokeFieldEncoder(102, "unknown")


if __name__ == "__main__":
    unittest.main()
