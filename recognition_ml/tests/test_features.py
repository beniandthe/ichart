import hashlib
import math
import unittest

from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.features import (
    MAXIMUM_INPUT_POINT_COUNT,
    MAXIMUM_STROKE_COUNT,
    InkBounds,
    InkPoint,
    InkStroke,
    TrajectoryChannel,
    encode_trajectory,
    rasterize,
)


def stroke(points, creation_time_offset=None, bounds=None):
    return InkStroke(
        tuple(
            InkPoint(*point) if len(point) == 3 else InkPoint(point[0], point[1])
            for point in points
        ),
        bounds=bounds,
        creation_time_offset=creation_time_offset,
    )


def fnv1a64(payload):
    value = 14_695_981_039_346_656_037
    for byte in payload:
        value = ((value ^ byte) * 1_099_511_628_211) & 0xFFFF_FFFF_FFFF_FFFF
    return value


class LearnedFeatureParityTests(unittest.TestCase):
    def test_golden_horizontal_trajectory_has_frozen_shape_channels_and_bytes(self):
        tensor = encode_trajectory((stroke(((0.0, 0.0), (10.0, 0.0))),))

        self.assertEqual(tensor.shape, (1, 256, 10))
        self.assertEqual(len(tensor.values), 2_560)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.X), -0.5)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.Y), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.DELTA_X), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.ARC_STEP), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.TIMING_AVAILABLE), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.STROKE_START), 1.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.STROKE_END), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.VALID), 1.0)
        self.assertAlmostEqual(
            tensor.sample(1, TrajectoryChannel.X), -0.5 + 1.0 / 255.0, places=6
        )
        self.assertAlmostEqual(
            tensor.sample(1, TrajectoryChannel.DELTA_X), 1.0 / 255.0, places=6
        )
        self.assertAlmostEqual(
            tensor.sample(1, TrajectoryChannel.ARC_STEP), 1.0 / 255.0, places=6
        )
        self.assertEqual(tensor.sample(255, TrajectoryChannel.X), 0.5)
        self.assertEqual(tensor.sample(255, TrajectoryChannel.STROKE_END), 1.0)
        self.assertEqual(len(tensor.to_bytes()), 10_240)
        self.assertEqual(
            hashlib.sha256(tensor.to_bytes()).hexdigest(),
            "566333bce82eecec3493e8dfb67187fb4e236ce1d49ce41d5163e1848885bbe1",
        )

    def test_trajectory_and_raster_are_translation_and_scale_invariant(self):
        original = (
            stroke(((0.0, 0.0), (5.0, 10.0), (10.0, 0.0))),
            stroke(((12.0, 4.0), (16.0, 8.0))),
        )
        transformed = (
            stroke(((100.0, -50.0), (110.0, -30.0), (120.0, -50.0))),
            stroke(((124.0, -42.0), (132.0, -34.0))),
        )

        self.assertEqual(encode_trajectory(original), encode_trajectory(transformed))
        self.assertEqual(rasterize(original), rasterize(transformed))

    def test_missing_nonfinite_and_nonmonotonic_timing_use_explicit_fallback(self):
        unavailable = stroke(((0.0, 0.0), (10.0, 0.0)))
        invalid = stroke(((0.0, 0.0, math.nan), (10.0, 0.0, math.inf)))
        nonmonotonic = stroke(
            ((0.0, 0.0, 0.0), (5.0, 5.0, 0.2), (10.0, 0.0, 0.1))
        )
        unavailable_tensor = encode_trajectory((unavailable,))
        invalid_tensor = encode_trajectory((invalid,))
        nonmonotonic_tensor = encode_trajectory((nonmonotonic,))

        for sample_index in range(256):
            self.assertEqual(
                unavailable_tensor.sample(sample_index, TrajectoryChannel.X),
                invalid_tensor.sample(sample_index, TrajectoryChannel.X),
            )
            for tensor in (unavailable_tensor, invalid_tensor, nonmonotonic_tensor):
                self.assertEqual(
                    tensor.sample(sample_index, TrajectoryChannel.NORMALIZED_DELTA_TIME),
                    0.0,
                )
                self.assertEqual(
                    tensor.sample(sample_index, TrajectoryChannel.TIMING_AVAILABLE), 0.0
                )

    def test_within_stroke_and_pen_up_timing_use_distinct_frozen_caps(self):
        first = stroke(
            ((0.0, 0.0, 0.0), (1.0, 0.0, 0.25)), creation_time_offset=10.0
        )
        second = stroke(
            ((2.0, 0.0, 0.0), (3.0, 0.0, 0.25)), creation_time_offset=11.25
        )
        tensor = encode_trajectory((first, second))
        second_start = next(
            index
            for index in range(1, 256)
            if tensor.sample(index, TrajectoryChannel.STROKE_START) == 1.0
        )

        self.assertEqual(second_start, 128)
        self.assertEqual(
            tensor.sample(second_start, TrajectoryChannel.NORMALIZED_DELTA_TIME), 1.0
        )
        self.assertEqual(
            tensor.sample(second_start, TrajectoryChannel.TIMING_AVAILABLE), 1.0
        )
        self.assertAlmostEqual(
            tensor.sample(1, TrajectoryChannel.NORMALIZED_DELTA_TIME),
            1.0 / 127.0,
            places=6,
        )

        capped = encode_trajectory(
            (stroke(((0.0, 0.0, 0.0), (1.0, 0.0, 100.0))),)
        )
        self.assertEqual(
            capped.sample(1, TrajectoryChannel.NORMALIZED_DELTA_TIME), 1.0
        )

    def test_stroke_boundaries_reset_deltas_and_largest_remainder_is_stable(self):
        tensor = encode_trajectory(
            (
                stroke(((0.0, 0.0), (1.0, 0.0))),
                stroke(((10.0, 0.0), (11.0, 0.0))),
                stroke(((20.0, 0.0), (22.0, 0.0))),
            )
        )

        self.assertEqual(tensor.sample(0, TrajectoryChannel.STROKE_START), 1.0)
        self.assertEqual(tensor.sample(64, TrajectoryChannel.STROKE_END), 1.0)
        self.assertEqual(tensor.sample(65, TrajectoryChannel.STROKE_START), 1.0)
        self.assertEqual(tensor.sample(65, TrajectoryChannel.DELTA_X), 0.0)
        self.assertEqual(tensor.sample(128, TrajectoryChannel.STROKE_END), 1.0)
        self.assertEqual(tensor.sample(129, TrajectoryChannel.STROKE_START), 1.0)
        self.assertEqual(tensor.sample(129, TrajectoryChannel.DELTA_X), 0.0)
        self.assertEqual(tensor.sample(255, TrajectoryChannel.STROKE_END), 1.0)

    def test_zero_length_stroke_is_stable_and_unused_samples_are_masked(self):
        tensor = encode_trajectory(
            (stroke(((4.0, 7.0), (4.0, 7.0))),)
        )
        self.assertEqual(tensor.sample(0, TrajectoryChannel.X), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.Y), 0.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.STROKE_START), 1.0)
        self.assertEqual(tensor.sample(0, TrajectoryChannel.VALID), 1.0)
        self.assertEqual(tensor.sample(1, TrajectoryChannel.STROKE_END), 1.0)
        self.assertEqual(tensor.sample(1, TrajectoryChannel.VALID), 1.0)
        self.assertEqual(tensor.sample(2, TrajectoryChannel.VALID), 0.0)
        self.assertTrue(all(math.isfinite(value) for value in tensor.values))

    def test_representation_and_input_limits_fail_closed(self):
        with self.assertRaisesRegex(ContractError, "representation_cannot_fit"):
            encode_trajectory(
                tuple(stroke(((float(index), 0.0),)) for index in range(257))
            )

        with self.assertRaisesRegex(ContractError, "stroke_complexity_exceeded"):
            encode_trajectory(
                tuple(
                    stroke(((float(index), 0.0),))
                    for index in range(MAXIMUM_STROKE_COUNT + 1)
                )
            )

        excessive_points = tuple(
            InkPoint(float(index), 0.0)
            for index in range(MAXIMUM_INPUT_POINT_COUNT + 1)
        )
        with self.assertRaisesRegex(ContractError, "point_complexity_exceeded"):
            encode_trajectory((InkStroke(excessive_points),))

    def test_empty_invalid_and_unrepresentable_geometry_fail_closed(self):
        with self.assertRaisesRegex(ContractError, "empty_input"):
            encode_trajectory(())
        with self.assertRaisesRegex(ContractError, "empty_stroke"):
            encode_trajectory((InkStroke(()),))
        with self.assertRaisesRegex(ContractError, "invalid_bounds"):
            encode_trajectory(
                (
                    stroke(
                        ((0.0, 0.0),),
                        bounds=InkBounds(2.0, 0.0, 1.0, 0.0),
                    ),
                )
            )
        with self.assertRaisesRegex(ContractError, "nonfinite_geometry"):
            rasterize((stroke(((math.nan, 0.0),)),))
        with self.assertRaisesRegex(ContractError, "geometry_extent_not_representable"):
            encode_trajectory(
                (stroke(((-1.0e308, 0.0), (1.0e308, 0.0))),)
            )

    def test_golden_raster_matches_swift_hash_and_never_connects_strokes(self):
        raster = rasterize((stroke(((0.0, 0.0), (10.0, 0.0))),))
        repeated = rasterize((stroke(((0.0, 0.0), (10.0, 0.0))),))

        self.assertEqual((raster.width, raster.height), (256, 96))
        self.assertEqual(raster, repeated)
        self.assertEqual(fnv1a64(raster.pixels), 6_717_323_988_239_542_465)

        separated = rasterize(
            (
                stroke(((0.0, 0.0), (20.0, 0.0))),
                stroke(((80.0, 0.0), (100.0, 0.0))),
            )
        )
        self.assertTrue(any(separated.pixel(x, 48) == 255 for x in range(8, 70)))
        self.assertTrue(any(separated.pixel(x, 48) == 255 for x in range(186, 248)))
        for y in range(44, 53):
            for x in range(90, 167):
                self.assertEqual(separated.pixel(x, y), 0)


if __name__ == "__main__":
    unittest.main()
