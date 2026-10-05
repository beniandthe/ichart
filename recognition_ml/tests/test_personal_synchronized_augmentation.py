import hashlib
import importlib.util
import math
import unittest

import numpy as np

from ichart_recognition_ml.features import (
    InkPoint,
    InkStroke,
    RASTER_HEIGHT,
    RASTER_PADDING,
    RASTER_STROKE_WIDTH,
    RASTER_WIDTH,
    encode_trajectory,
    rasterize,
)


HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional training dependencies required")
class PersonalSynchronizedAugmentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        from ichart_recognition_ml.research import personal_synchronized_augmentation as sync

        cls.torch = torch
        cls.sync = sync
        torch.set_num_threads(2)

    def features(self, strokes):
        trajectory = encode_trajectory(strokes)
        raster = rasterize(strokes)
        trajectory_tensor = self.torch.from_numpy(
            np.frombuffer(trajectory.to_bytes(), dtype="<f4").copy().reshape(1, 1, 256, 10)
        )
        raster_tensor = self.torch.from_numpy(
            np.frombuffer(raster.pixels, dtype=np.uint8).copy().reshape(1, 1, 96, 256)
        ).float() / 255.0
        return trajectory_tensor, raster_tensor

    def mapping(self, strokes):
        points = [point for stroke in strokes for point in stroke.points]
        width = max(point.x for point in points) - min(point.x for point in points)
        height = max(point.y for point in points) - min(point.y for point in points)
        extent = max(width, height)
        if extent == 0:
            return self.sync.CanonicalRasterMapping(0.0, 0.0, 0.0)
        normalized_width = width / extent
        normalized_height = height / extent
        horizontal = RASTER_WIDTH - 2.0 * (RASTER_PADDING + RASTER_STROKE_WIDTH / 2.0)
        vertical = RASTER_HEIGHT - 2.0 * (RASTER_PADDING + RASTER_STROKE_WIDTH / 2.0)
        scales = []
        if normalized_width > 0:
            scales.append(horizontal / normalized_width)
        if normalized_height > 0:
            scales.append(vertical / normalized_height)
        return self.sync.CanonicalRasterMapping(
            normalized_width, normalized_height, min(scales)
        )

    def fixed_transform(self, *, angle_degrees=0.0, scale=1.0, tx=0.0, ty=0.0):
        return self.sync.SynchronizedAffineTransform(
            seed=0,
            epoch=0,
            source_identity_sha256="0" * 64,
            angle_radians=math.radians(angle_degrees),
            sampling_scale=scale,
            translation_x_fraction=tx,
            translation_y_fraction=ty,
        )

    @staticmethod
    def raster_centroid(raster):
        values = raster[0, 0].double()
        total = float(values.sum())
        if total <= 0:
            raise AssertionError("Synthetic raster unexpectedly empty")
        ys = np.arange(RASTER_HEIGHT, dtype=np.float64) + 0.5
        xs = np.arange(RASTER_WIDTH, dtype=np.float64) + 0.5
        array = values.numpy()
        return (
            float((array * xs[None, :]).sum() / total),
            float((array * ys[:, None]).sum() / total),
        )

    def test_draw_derivation_is_exact_order_independent_bounded_and_identity_specific(self):
        sync = self.sync
        first = sync.derive_transform(29, 7, "opaque-source-17")
        repeated = sync.derive_transform(29, 7, "opaque-source-17")
        other_epoch = sync.derive_transform(29, 8, "opaque-source-17")
        other_source = sync.derive_transform(29, 7, "opaque-source-18")
        self.assertEqual(first, repeated)
        self.assertEqual(first.sha256, repeated.sha256)
        self.assertNotEqual(first.sha256, other_epoch.sha256)
        self.assertNotEqual(first.sha256, other_source.sha256)
        self.assertLessEqual(abs(math.degrees(first.angle_radians)), 8.0)
        self.assertGreaterEqual(first.sampling_scale, 0.9)
        self.assertLessEqual(first.sampling_scale, 1.1)
        self.assertLessEqual(abs(first.translation_x_fraction), 0.03)
        self.assertLessEqual(abs(first.translation_y_fraction), 0.05)
        self.assertEqual(len(first.sha256), 64)
        self.assertEqual(
            first.source_identity_sha256,
            hashlib.sha256(b"opaque-source-17").hexdigest(),
        )

    def test_identity_preserves_geometry_flags_and_raster_but_removes_timing(self):
        strokes = (
            InkStroke((InkPoint(-4, -2, 0.0), InkPoint(3, 5, 0.2))),
            InkStroke((InkPoint(5, -1, 0.0), InkPoint(6, 2, 0.1))),
        )
        trajectory, raster = self.features(strokes)
        result = self.sync.augment_batch(
            trajectory,
            raster,
            [self.fixed_transform()],
            [self.mapping(strokes)],
        )
        self.torch.testing.assert_close(result.raster, raster, rtol=0, atol=0)
        for channel in (0, 1, 2, 3, 4, 7, 8, 9):
            self.torch.testing.assert_close(
                result.trajectory[:, :, :, channel],
                trajectory[:, :, :, channel],
                rtol=0,
                atol=1e-7,
            )
        self.assertTrue(self.torch.equal(
            result.trajectory[:, :, :, 5],
            self.torch.zeros_like(result.trajectory[:, :, :, 5]),
        ))
        self.assertTrue(self.torch.equal(
            result.trajectory[:, :, :, 6],
            self.torch.zeros_like(result.trajectory[:, :, :, 6]),
        ))
        valid_count = int(result.trajectory[0, 0, :, 9].sum())
        self.assertTrue(self.torch.equal(
            result.trajectory[0, 0, valid_count:, :],
            self.torch.zeros_like(result.trajectory[0, 0, valid_count:, :]),
        ))

    def test_translation_uses_inverse_grid_direction_and_matches_pixel_aspect(self):
        # A deliberately asymmetric two-stroke L makes left/right and up/down
        # mistakes visible. Positive affine-grid x samples to the right, so the
        # displayed ink and paired trajectory must move left.
        strokes = (
            InkStroke((InkPoint(-8, -5), InkPoint(-8, 7), InkPoint(5, 7))),
            InkStroke((InkPoint(1, -3), InkPoint(7, -3))),
        )
        trajectory, raster = self.features(strokes)
        mapping = self.mapping(strokes)
        transform = self.fixed_transform(tx=0.03, ty=-0.05)
        result = self.sync.augment_batch(trajectory, raster, [transform], [mapping])
        before_x, before_y = self.raster_centroid(raster)
        after_x, after_y = self.raster_centroid(result.raster)
        self.assertAlmostEqual(after_x - before_x, -0.03 * RASTER_WIDTH, delta=0.2)
        self.assertAlmostEqual(after_y - before_y, 0.05 * RASTER_HEIGHT, delta=0.2)

        valid = trajectory[0, 0, :, 9] == 1
        source_xy = trajectory[0, 0, valid, :2]
        output_xy = result.trajectory[0, 0, valid, :2]
        trajectory_shift = output_xy - source_xy
        self.torch.testing.assert_close(
            trajectory_shift[:, 0],
            self.torch.full_like(trajectory_shift[:, 0], -0.03 * RASTER_WIDTH / mapping.pixels_per_unit),
            rtol=0,
            atol=1e-6,
        )
        self.torch.testing.assert_close(
            trajectory_shift[:, 1],
            self.torch.full_like(trajectory_shift[:, 1], 0.05 * RASTER_HEIGHT / mapping.pixels_per_unit),
            rtol=0,
            atol=1e-6,
        )

    def test_rotation_and_scale_follow_inverse_sampling_map_on_non_square_raster(self):
        strokes = (
            InkStroke((InkPoint(-9, 4), InkPoint(8, 4))),
            InkStroke((InkPoint(6, -7), InkPoint(6, 3))),
        )
        trajectory, raster = self.features(strokes)
        mapping = self.mapping(strokes)
        transform = self.fixed_transform(angle_degrees=8.0, scale=1.1)
        result = self.sync.augment_batch(trajectory, raster, [transform], [mapping])
        valid = trajectory[0, 0, :, 9] == 1
        original = trajectory[0, 0, valid, :2]
        changed = result.trajectory[0, 0, valid, :2]

        # Sampling angle +8 degrees means displayed geometry rotates -8 degrees.
        source_vector = original[-1] - original[0]
        output_vector = changed[-1] - changed[0]
        source_angle = math.atan2(float(source_vector[1]), float(source_vector[0]))
        output_angle = math.atan2(float(output_vector[1]), float(output_vector[0]))
        self.assertAlmostEqual(output_angle - source_angle, math.radians(-8.0), delta=1e-6)
        self.assertAlmostEqual(
            float(self.torch.linalg.vector_norm(output_vector))
            / float(self.torch.linalg.vector_norm(source_vector)),
            1.0 / 1.1,
            delta=1e-6,
        )

        before_x, before_y = self.raster_centroid(raster)
        after_x, after_y = self.raster_centroid(result.raster)
        center = (RASTER_WIDTH / 2.0, RASTER_HEIGHT / 2.0)
        before_angle = math.atan2(before_y - center[1], before_x - center[0])
        after_angle = math.atan2(after_y - center[1], after_x - center[0])
        delta = (after_angle - before_angle + math.pi) % (2 * math.pi) - math.pi
        self.assertAlmostEqual(delta, math.radians(-8.0), delta=0.02)

    def test_derived_channels_restart_at_each_stroke_and_invalid_rows_are_zero(self):
        strokes = (
            InkStroke((InkPoint(-5, 0), InkPoint(0, 5), InkPoint(4, 1))),
            InkStroke((InkPoint(6, -3), InkPoint(8, 2))),
        )
        trajectory, raster = self.features(strokes)
        result = self.sync.augment_batch(
            trajectory,
            raster,
            [self.fixed_transform(angle_degrees=-7.0, scale=0.91, tx=-0.02, ty=0.04)],
            [self.mapping(strokes)],
        ).trajectory[0, 0]
        valid_count = int(result[:, 9].sum())
        for index in range(valid_count):
            if result[index, 7] == 1:
                self.torch.testing.assert_close(result[index, 2:5], self.torch.zeros(3), rtol=0, atol=0)
            else:
                delta = result[index, :2] - result[index - 1, :2]
                self.torch.testing.assert_close(result[index, 2:4], delta, rtol=0, atol=1e-7)
                self.assertAlmostEqual(float(result[index, 4]), float(self.torch.linalg.vector_norm(delta)), places=6)
        self.assertTrue(self.torch.equal(result[valid_count:], self.torch.zeros_like(result[valid_count:])))

    def test_zero_extent_source_is_retained_with_explicit_effective_scale(self):
        strokes = (InkStroke((InkPoint(2, 2),)),)
        trajectory, raster = self.features(strokes)
        mapping = self.mapping(strokes)
        self.assertEqual(mapping.pixels_per_unit, 0.0)
        self.assertEqual(mapping.effective_pixels_per_unit, 77.0)
        result = self.sync.augment_batch(
            trajectory,
            raster,
            [self.fixed_transform(tx=0.03, ty=0.05)],
            [mapping],
        )
        point = result.trajectory[0, 0, 0]
        self.assertAlmostEqual(float(point[0] * mapping.effective_pixels_per_unit), -0.03 * RASTER_WIDTH, places=5)
        self.assertAlmostEqual(float(point[1] * mapping.effective_pixels_per_unit), -0.05 * RASTER_HEIGHT, places=5)
        self.assertEqual(result.metadata["rows"][0]["mapping"]["sourcePixelsPerUnit"], 0.0)
        self.assertTrue(result.metadata["rows"][0]["mapping"]["degenerateExtent"])

    def test_batch_metadata_and_tensors_are_identical_for_shared_arm_inputs(self):
        strokes = (InkStroke((InkPoint(-2, -4), InkPoint(3, 5))),)
        trajectory, raster = self.features(strokes)
        transform = self.sync.derive_transform(29, 3, "same-opaque-source")
        mapping = self.mapping(strokes)
        first = self.sync.augment_batch(trajectory, raster, [transform], [mapping])
        second = self.sync.augment_batch(trajectory.clone(), raster.clone(), [transform], [mapping])
        self.assertEqual(first.metadata, second.metadata)
        self.assertEqual(first.metadata_sha256, second.metadata_sha256)
        self.torch.testing.assert_close(first.trajectory, second.trajectory, rtol=0, atol=0)
        self.torch.testing.assert_close(first.raster, second.raster, rtol=0, atol=0)

    def test_invalid_shapes_bounds_and_stroke_structure_fail_closed(self):
        strokes = (InkStroke((InkPoint(-2, 0), InkPoint(2, 0))),)
        trajectory, raster = self.features(strokes)
        mapping = self.mapping(strokes)
        transform = self.fixed_transform()
        with self.assertRaisesRegex(ValueError, "wrong frozen shape"):
            self.sync.augment_batch(trajectory[:, :, :-1], raster, [transform], [mapping])
        with self.assertRaisesRegex(ValueError, "normalized"):
            self.sync.augment_batch(trajectory, raster + 2.0, [transform], [mapping])
        broken = trajectory.clone()
        broken[0, 0, 1, 7] = 1.0
        with self.assertRaisesRegex(ValueError, "boundaries"):
            self.sync.augment_batch(broken, raster, [transform], [mapping])
        with self.assertRaisesRegex(ValueError, "frozen raster mapping"):
            self.sync.CanonicalRasterMapping(1.0, 0.5, 2.0)


if __name__ == "__main__":
    unittest.main()
