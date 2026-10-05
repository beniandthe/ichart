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
from ichart_recognition_ml.research import personal_stroke_field as field


class PersonalStrokeFieldTests(unittest.TestCase):
    @staticmethod
    def _tensor(strokes):
        return torch.from_numpy(field.encode_stroke_field(strokes)).unsqueeze(0)

    def test_occupancy_is_exact_existing_raster_and_dot_is_symmetric(self):
        strokes = (InkStroke((InkPoint(3.0, -2.0, 0.75),)),)
        encoded = field.encode_stroke_field(strokes)
        expected = (
            np.frombuffer(rasterize(strokes).pixels, dtype=np.uint8)
            .reshape(RASTER_HEIGHT, RASTER_WIDTH)
            .astype(np.float32)
            / np.float32(255.0)
        )
        self.assertEqual(encoded.shape, (5, RASTER_HEIGHT, RASTER_WIDTH))
        self.assertEqual(encoded.dtype, np.float32)
        self.assertTrue(np.array_equal(encoded[0], expected))
        self.assertTrue(np.array_equal(encoded[1], np.zeros_like(encoded[1])))
        self.assertTrue(np.array_equal(encoded[2], np.zeros_like(encoded[2])))
        self.assertTrue(np.array_equal(encoded[3], encoded[4]))
        self.assertTrue(np.array_equal(encoded[3], np.flip(encoded[3], axis=(0, 1))))

    def test_horizontal_vertical_and_diagonal_tangents_use_isotropic_pixels(self):
        fixtures = (
            ((InkPoint(-5, 0), InkPoint(5, 0)), (1.0, 0.0)),
            ((InkPoint(0, -5), InkPoint(0, 5)), (0.0, 1.0)),
            ((InkPoint(-5, -2.5), InkPoint(5, 2.5)), (2 / math.sqrt(5), 1 / math.sqrt(5))),
        )
        for points, expected in fixtures:
            with self.subTest(expected=expected):
                encoded = field.encode_stroke_field((InkStroke(points),))
                mask = np.hypot(encoded[1], encoded[2]) > 0.5
                self.assertTrue(mask.any())
                self.assertTrue(np.allclose(encoded[1][mask], expected[0], atol=1e-6))
                self.assertTrue(np.allclose(encoded[2][mask], expected[1], atol=1e-6))

    def test_reversing_a_stroke_negates_tangent_and_swaps_endpoints(self):
        points = (InkPoint(-7, -3), InkPoint(4, 6))
        forward = field.encode_stroke_field((InkStroke(points),))
        reverse = field.encode_stroke_field((InkStroke(tuple(reversed(points))),))
        self.assertTrue(np.array_equal(forward[0], reverse[0]))
        self.assertTrue(np.allclose(forward[1:3], -reverse[1:3], atol=1e-7))
        self.assertTrue(np.array_equal(forward[3], reverse[4]))
        self.assertTrue(np.array_equal(forward[4], reverse[3]))

    def test_subdivision_and_stroke_order_are_invariant_without_pen_lift_bridges(self):
        whole = (InkStroke((InkPoint(-9, -3), InkPoint(9, 3))),)
        split = (
            InkStroke(
                (
                    InkPoint(-9, -3),
                    InkPoint(-3, -1),
                    InkPoint(3, 1),
                    InkPoint(9, 3),
                )
            ),
        )
        self.assertTrue(
            np.allclose(
                field.encode_stroke_field(whole),
                field.encode_stroke_field(split),
                rtol=0,
                atol=2e-6,
            )
        )

        first = InkStroke((InkPoint(-10, -5), InkPoint(-10, -2)))
        second = InkStroke((InkPoint(10, 2), InkPoint(10, 5)))
        ordered = field.encode_stroke_field((first, second))
        swapped = field.encode_stroke_field((second, first))
        self.assertTrue(np.allclose(ordered, swapped, rtol=0, atol=1e-7))
        self.assertEqual(float(ordered[0, RASTER_HEIGHT // 2, RASTER_WIDTH // 2]), 0.0)
        self.assertEqual(float(ordered[1, RASTER_HEIGHT // 2, RASTER_WIDTH // 2]), 0.0)

        horizontal = InkStroke((InkPoint(-8, 0), InkPoint(8, 0)))
        vertical = InkStroke((InkPoint(0, -8), InkPoint(0, 8)))
        crossing = field.encode_stroke_field((horizontal, vertical))
        crossing_swapped = field.encode_stroke_field((vertical, horizontal))
        self.assertTrue(np.allclose(crossing, crossing_swapped, rtol=0, atol=1e-7))

    def test_timing_is_not_encoded_and_zero_length_segments_add_no_tangent(self):
        geometry = (InkPoint(-2, 1), InkPoint(-2, 1), InkPoint(4, 1))
        missing = (InkStroke(geometry),)
        timed = (
            InkStroke(
                tuple(InkPoint(point.x, point.y, index * 0.1) for index, point in enumerate(geometry)),
                creation_time_offset=2.0,
            ),
        )
        self.assertTrue(
            np.array_equal(
                field.encode_stroke_field(missing),
                field.encode_stroke_field(timed),
            )
        )
        duplicate_only = field.encode_stroke_field(
            (InkStroke((InkPoint(1, 1), InkPoint(1, 1))),)
        )
        self.assertFalse(np.any(duplicate_only[1:3]))

    def test_augmentation_uses_historical_grid_and_corotates_tangents(self):
        source = self._tensor((InkStroke((InkPoint(-8, 0), InkPoint(8, 0))),))
        unchanged = source.clone()
        draws = torch.tensor([[1.0, 0.5, 0.5, 0.5]], dtype=torch.float32)
        augmented = field.augment_stroke_fields(source, draws)
        self.assertTrue(torch.equal(source, unchanged))

        angle = torch.tensor(math.radians(8.0), dtype=torch.float32)
        theta = torch.zeros((1, 2, 3), dtype=torch.float32)
        theta[:, 0, 0] = torch.cos(angle)
        theta[:, 1, 1] = torch.cos(angle)
        theta[:, 0, 1] = -torch.sin(angle) * RASTER_HEIGHT / RASTER_WIDTH
        theta[:, 1, 0] = torch.sin(angle) * RASTER_WIDTH / RASTER_HEIGHT
        grid = F.affine_grid(theta, source[:, :1].shape, align_corners=False)
        expected_occupancy = F.grid_sample(
            source[:, :1], grid, mode="bilinear", padding_mode="zeros", align_corners=False
        )
        torch.testing.assert_close(augmented[:, :1], expected_occupancy, rtol=0, atol=0)

        weight = torch.linalg.vector_norm(augmented[0, 1:3], dim=0)
        mask = weight > 0.2
        direction = augmented[0, 1:3, mask].mean(dim=1)
        direction = direction / torch.linalg.vector_norm(direction)
        expected = torch.tensor(
            [math.cos(math.radians(-8)), math.sin(math.radians(-8))],
            dtype=torch.float32,
        )
        torch.testing.assert_close(direction, expected, rtol=0, atol=2e-5)

    def test_matched_model_control_zeros_added_channels_and_candidate_backpropagates(self):
        torch.manual_seed(29)
        candidate = field.PersonalStrokeFieldEncoder(97, "strokeField")
        torch.manual_seed(29)
        control = field.PersonalStrokeFieldEncoder(97, "rasterControl")
        control.load_state_dict(candidate.state_dict(), strict=True)
        base = self._tensor(
            (
                InkStroke((InkPoint(-6, -3), InkPoint(5, 4))),
                InkStroke((InkPoint(-2, 5), InkPoint(6, -4))),
            )
        )
        batch = torch.cat((base, base.flip(-1)), dim=0)
        changed = batch.clone()
        changed[:, 1:] = torch.randn_like(changed[:, 1:])
        control.eval()
        with torch.inference_mode():
            first = control(batch)
            second = control(changed)
        torch.testing.assert_close(first[0], second[0], rtol=0, atol=0)
        torch.testing.assert_close(first[1], second[1], rtol=0, atol=0)

        candidate.train()
        differentiable = batch.clone().requires_grad_(True)
        embedding, logits = candidate(differentiable)
        self.assertEqual(tuple(embedding.shape), (2, 128))
        self.assertEqual(tuple(logits.shape), (2, 97))
        F.cross_entropy(logits, torch.tensor([0, 1])).backward()
        self.assertGreater(float(differentiable.grad[:, 1:].abs().sum()), 0.0)
        first_convolution = candidate.convolution[1]
        self.assertGreater(float(first_convolution.weight.grad[:, 1:].abs().sum()), 0.0)

    def test_invalid_geometry_shapes_and_nonfinite_values_fail_closed(self):
        with self.assertRaises(FeatureEncodingError):
            field.encode_stroke_field((InkStroke(()),))
        with self.assertRaises(FeatureEncodingError):
            field.encode_stroke_field(
                (InkStroke((InkPoint(float("nan"), 0.0), InkPoint(1.0, 0.0))),)
            )
        with self.assertRaises(FeatureEncodingError):
            field.encode_stroke_field(
                (
                    InkStroke(
                        (InkPoint(0.0, 0.0), InkPoint(1.0, 1.0)),
                        bounds=InkBounds(1.0, 0.0, 0.0, 1.0),
                    ),
                )
            )
        source = torch.zeros((1, 5, RASTER_HEIGHT, RASTER_WIDTH), dtype=torch.float32)
        draws = torch.full((1, 4), 0.5, dtype=torch.float32)
        with self.assertRaisesRegex(ValueError, "wrong shape"):
            field.augment_stroke_fields(source[:, :4], draws)
        broken = source.clone()
        broken[0, 0, 0, 0] = float("nan")
        with self.assertRaisesRegex(ValueError, "finite"):
            field.augment_stroke_fields(broken, draws)
        with self.assertRaisesRegex(ValueError, r"\[0,1\]"):
            field.augment_stroke_fields(source, torch.tensor([[1.1, 0.5, 0.5, 0.5]]))


if __name__ == "__main__":
    unittest.main()
