"""Deterministic Python mirror of iChart's learned-feature encoders.

This module intentionally has no numerical-library dependency.  The emitted
trajectory bytes and raster bytes are the portable artifacts described by
``chord-ink-features-v1``.  Any behavioral change here must be paired with a
new feature-schema version in both the app and training workspace.
"""

import math
import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Optional, Sequence, Tuple

from .errors import ContractError
from .schema import FEATURE_SCHEMA


TRAJECTORY_SAMPLE_COUNT = FEATURE_SCHEMA.trajectory_shape[1]
TRAJECTORY_CHANNEL_COUNT = FEATURE_SCHEMA.trajectory_shape[2]
MAXIMUM_WITHIN_STROKE_DELTA_TIME_SECONDS = 0.250
MAXIMUM_PEN_UP_DELTA_TIME_SECONDS = 1.0

RASTER_WIDTH = FEATURE_SCHEMA.raster_width
RASTER_HEIGHT = FEATURE_SCHEMA.raster_height
RASTER_PADDING = 8.0
RASTER_STROKE_WIDTH = 3.0
RASTER_BACKGROUND = 0
RASTER_FOREGROUND = 255

MAXIMUM_STROKE_COUNT = 512
MAXIMUM_INPUT_POINT_COUNT = 8_192


class TrajectoryChannel(IntEnum):
    X = 0
    Y = 1
    DELTA_X = 2
    DELTA_Y = 3
    ARC_STEP = 4
    NORMALIZED_DELTA_TIME = 5
    TIMING_AVAILABLE = 6
    STROKE_START = 7
    STROKE_END = 8
    VALID = 9


class FeatureEncodingError(ContractError):
    """A fail-closed feature-contract violation."""


@dataclass(frozen=True)
class InkPoint:
    x: float
    y: float
    time_offset: Optional[float] = None


@dataclass(frozen=True)
class InkBounds:
    min_x: float
    min_y: float
    max_x: float
    max_y: float


@dataclass(frozen=True)
class InkStroke:
    points: Tuple[InkPoint, ...]
    bounds: Optional[InkBounds] = None
    creation_time_offset: Optional[float] = None

    def __init__(
        self,
        points: Sequence[InkPoint],
        bounds: Optional[InkBounds] = None,
        creation_time_offset: Optional[float] = None,
    ) -> None:
        frozen_points = tuple(points)
        object.__setattr__(self, "points", frozen_points)
        object.__setattr__(
            self,
            "bounds",
            bounds if bounds is not None else _enclosing_bounds(frozen_points),
        )
        object.__setattr__(self, "creation_time_offset", creation_time_offset)


@dataclass(frozen=True)
class TrajectoryFeatureTensor:
    values: Tuple[float, ...]
    shape: Tuple[int, int, int] = FEATURE_SCHEMA.trajectory_shape

    def __post_init__(self) -> None:
        if len(self.values) != FEATURE_SCHEMA.trajectory_value_count:
            raise ValueError(
                "trajectory tensor must contain exactly "
                f"{FEATURE_SCHEMA.trajectory_value_count} values"
            )

    def sample(self, sample_index: int, channel: TrajectoryChannel) -> float:
        return self.values[
            sample_index * TRAJECTORY_CHANNEL_COUNT + int(channel)
        ]

    def to_bytes(self) -> bytes:
        return struct.pack(
            f"<{FEATURE_SCHEMA.trajectory_value_count}f", *self.values
        )


@dataclass(frozen=True)
class RasterFeaturePlane:
    pixels: bytes
    width: int = RASTER_WIDTH
    height: int = RASTER_HEIGHT

    def __post_init__(self) -> None:
        if len(self.pixels) != FEATURE_SCHEMA.raster_byte_count:
            raise ValueError(
                "raster plane must contain exactly "
                f"{FEATURE_SCHEMA.raster_byte_count} pixels"
            )

    def pixel(self, x: int, y: int) -> int:
        return self.pixels[y * self.width + x]

    def to_bytes(self) -> bytes:
        return self.pixels


@dataclass(frozen=True)
class _PreparedPoint:
    x: float
    y: float
    time_offset: Optional[float]


@dataclass(frozen=True)
class _PreparedStroke:
    points: Tuple[_PreparedPoint, ...]
    creation_time_offset: Optional[float]
    arc_length: float


@dataclass(frozen=True)
class _PreparedGeometry:
    strokes: Tuple[_PreparedStroke, ...]
    normalized_width: float
    normalized_height: float


@dataclass(frozen=True)
class _Sample:
    x: float
    y: float
    local_time: Optional[float]
    absolute_time: Optional[float]


def encode_trajectory(strokes: Sequence[InkStroke]) -> TrajectoryFeatureTensor:
    """Encode strokes into the frozen ``[1, 256, 10]`` Float32 tensor."""

    prepared = _prepare(strokes)
    allocations = _sample_allocations(prepared.strokes)
    values = [0.0] * FEATURE_SCHEMA.trajectory_value_count
    output_index = 0
    previous_global_sample = None  # type: Optional[_Sample]

    for stroke, allocation in zip(prepared.strokes, allocations):
        samples = _resample(stroke, allocation)
        previous_stroke_sample = None  # type: Optional[_Sample]

        for sample_index, sample in enumerate(samples):
            previous_x = sample.x if previous_stroke_sample is None else previous_stroke_sample.x
            previous_y = sample.y if previous_stroke_sample is None else previous_stroke_sample.y
            delta_x = sample.x - previous_x
            delta_y = sample.y - previous_y
            arc_step = math.hypot(delta_x, delta_y)
            timing_value, timing_available = _timing_delta(
                current=sample,
                previous_in_stroke=previous_stroke_sample,
                previous_globally=previous_global_sample,
            )

            _set(values, output_index, TrajectoryChannel.X, sample.x)
            _set(values, output_index, TrajectoryChannel.Y, sample.y)
            _set(values, output_index, TrajectoryChannel.DELTA_X, delta_x)
            _set(values, output_index, TrajectoryChannel.DELTA_Y, delta_y)
            _set(values, output_index, TrajectoryChannel.ARC_STEP, arc_step)
            _set(
                values,
                output_index,
                TrajectoryChannel.NORMALIZED_DELTA_TIME,
                timing_value,
            )
            _set(
                values,
                output_index,
                TrajectoryChannel.TIMING_AVAILABLE,
                1.0 if timing_available else 0.0,
            )
            _set(
                values,
                output_index,
                TrajectoryChannel.STROKE_START,
                1.0 if sample_index == 0 else 0.0,
            )
            _set(
                values,
                output_index,
                TrajectoryChannel.STROKE_END,
                1.0 if sample_index == len(samples) - 1 else 0.0,
            )
            _set(values, output_index, TrajectoryChannel.VALID, 1.0)

            output_index += 1
            previous_stroke_sample = sample
            previous_global_sample = sample

    return TrajectoryFeatureTensor(tuple(values))


def rasterize(strokes: Sequence[InkStroke]) -> RasterFeaturePlane:
    """Rasterize strokes into the frozen centered 256x96 UInt8 plane."""

    prepared = _prepare(strokes)
    pixels = bytearray([RASTER_BACKGROUND]) * (RASTER_WIDTH * RASTER_HEIGHT)
    radius = RASTER_STROKE_WIDTH / 2.0
    horizontal_span = RASTER_WIDTH - 2.0 * (RASTER_PADDING + radius)
    vertical_span = RASTER_HEIGHT - 2.0 * (RASTER_PADDING + radius)
    horizontal_scale = (
        horizontal_span / prepared.normalized_width
        if prepared.normalized_width > 0.0
        else math.inf
    )
    vertical_scale = (
        vertical_span / prepared.normalized_height
        if prepared.normalized_height > 0.0
        else math.inf
    )
    finite_scales = tuple(
        scale for scale in (horizontal_scale, vertical_scale) if math.isfinite(scale)
    )
    scale = min(finite_scales) if finite_scales else 0.0
    center_x = RASTER_WIDTH / 2.0
    center_y = RASTER_HEIGHT / 2.0

    def mapped(point: _PreparedPoint) -> Tuple[float, float]:
        return (center_x + point.x * scale, center_y + point.y * scale)

    for stroke in prepared.strokes:
        if len(stroke.points) == 1:
            point = mapped(stroke.points[0])
            _draw_round_segment(point, point, radius, pixels)
            continue
        for index in range(1, len(stroke.points)):
            _draw_round_segment(
                mapped(stroke.points[index - 1]),
                mapped(stroke.points[index]),
                radius,
                pixels,
            )

    return RasterFeaturePlane(bytes(pixels))


def encode_feature_artifacts(
    strokes: Sequence[InkStroke],
) -> Tuple[TrajectoryFeatureTensor, RasterFeaturePlane]:
    """Encode both model inputs from one validated stroke sequence."""

    # Keep each public encoder independently fail-closed, matching the app.
    return encode_trajectory(strokes), rasterize(strokes)


def _enclosing_bounds(points: Sequence[InkPoint]) -> InkBounds:
    if not points:
        return InkBounds(0.0, 0.0, 0.0, 0.0)
    first = points[0]
    min_x = max_x = first.x
    min_y = max_y = first.y
    for point in points[1:]:
        min_x = min(min_x, point.x)
        min_y = min(min_y, point.y)
        max_x = max(max_x, point.x)
        max_y = max(max_y, point.y)
    return InkBounds(min_x, min_y, max_x, max_y)


def _prepare(source_strokes: Sequence[InkStroke]) -> _PreparedGeometry:
    strokes = tuple(source_strokes)
    if not strokes:
        _refuse("empty_input", "strokes", "at least one stroke is required")
    if len(strokes) > MAXIMUM_STROKE_COUNT:
        _refuse(
            "stroke_complexity_exceeded",
            "strokes",
            f"limit {MAXIMUM_STROKE_COUNT}, actual {len(strokes)}",
        )

    point_count = 0
    min_x = math.inf
    min_y = math.inf
    max_x = -math.inf
    max_y = -math.inf

    for stroke_index, stroke in enumerate(strokes):
        if not stroke.points:
            _refuse(
                "empty_stroke",
                f"strokes[{stroke_index}].points",
                "a stroke must contain at least one point",
            )
        point_count += len(stroke.points)
        if point_count > MAXIMUM_INPUT_POINT_COUNT:
            _refuse(
                "point_complexity_exceeded",
                "strokes",
                f"limit {MAXIMUM_INPUT_POINT_COUNT}, actual {point_count}",
            )

        bounds = stroke.bounds
        if bounds is None:  # Construction normally supplies it; remain fail closed.
            _refuse(
                "invalid_bounds",
                f"strokes[{stroke_index}].bounds",
                "bounds are required",
            )
        bounds_components = (
            ("min_x", bounds.min_x),
            ("min_y", bounds.min_y),
            ("max_x", bounds.max_x),
            ("max_y", bounds.max_y),
        )
        for component, value in bounds_components:
            if not math.isfinite(value):
                _refuse(
                    "nonfinite_geometry",
                    f"strokes[{stroke_index}].bounds.{component}",
                    "must be finite",
                )
        if bounds.min_x > bounds.max_x or bounds.min_y > bounds.max_y:
            _refuse(
                "invalid_bounds",
                f"strokes[{stroke_index}].bounds",
                "minimums must not exceed maximums",
            )

        for point_index, point in enumerate(stroke.points):
            if not math.isfinite(point.x):
                _refuse(
                    "nonfinite_geometry",
                    f"strokes[{stroke_index}].points[{point_index}].x",
                    "must be finite",
                )
            if not math.isfinite(point.y):
                _refuse(
                    "nonfinite_geometry",
                    f"strokes[{stroke_index}].points[{point_index}].y",
                    "must be finite",
                )
            min_x = min(min_x, point.x)
            min_y = min(min_y, point.y)
            max_x = max(max_x, point.x)
            max_y = max(max_y, point.y)

    width = max_x - min_x
    height = max_y - min_y
    maximum_dimension = max(width, height)
    if not (
        math.isfinite(width)
        and math.isfinite(height)
        and math.isfinite(maximum_dimension)
    ):
        _refuse(
            "geometry_extent_not_representable",
            "strokes",
            "combined finite coordinates overflowed the representable extent",
        )

    normalized_width = width / maximum_dimension if maximum_dimension > 0.0 else 0.0
    normalized_height = height / maximum_dimension if maximum_dimension > 0.0 else 0.0
    prepared_strokes = []

    for source_stroke in strokes:
        has_monotonic_local_timing = all(
            point.time_offset is not None and math.isfinite(point.time_offset)
            for point in source_stroke.points
        ) and all(
            current.time_offset >= previous.time_offset
            for previous, current in zip(
                source_stroke.points, source_stroke.points[1:]
            )
        )
        points = []
        for source_point in source_stroke.points:
            if maximum_dimension > 0.0:
                x = (
                    (source_point.x - min_x) / maximum_dimension
                    - normalized_width / 2.0
                )
                y = (
                    (source_point.y - min_y) / maximum_dimension
                    - normalized_height / 2.0
                )
            else:
                x = 0.0
                y = 0.0
            points.append(
                _PreparedPoint(
                    x=x,
                    y=y,
                    time_offset=(
                        source_point.time_offset
                        if has_monotonic_local_timing
                        else None
                    ),
                )
            )

        arc_length = sum(
            math.hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y,
            )
            for index in range(1, len(points))
        )
        creation_time = source_stroke.creation_time_offset
        if creation_time is not None and not math.isfinite(creation_time):
            creation_time = None
        prepared_strokes.append(
            _PreparedStroke(tuple(points), creation_time, arc_length)
        )

    return _PreparedGeometry(
        strokes=tuple(prepared_strokes),
        normalized_width=normalized_width,
        normalized_height=normalized_height,
    )


def _sample_allocations(strokes: Sequence[_PreparedStroke]) -> Tuple[int, ...]:
    minimum = [1 if len(stroke.points) == 1 else 2 for stroke in strokes]
    required = sum(minimum)
    if required > TRAJECTORY_SAMPLE_COUNT:
        _refuse(
            "representation_cannot_fit",
            "strokes",
            f"required minimum {required}, capacity {TRAJECTORY_SAMPLE_COUNT}",
        )

    allocations = list(minimum)
    remaining = TRAJECTORY_SAMPLE_COUNT - required
    total_arc_length = sum(stroke.arc_length for stroke in strokes)
    if remaining <= 0 or total_arc_length <= 0.0:
        return tuple(allocations)

    remainders = []
    assigned = 0
    for index, stroke in enumerate(strokes):
        exact = remaining * stroke.arc_length / total_arc_length
        whole = math.floor(exact)
        allocations[index] += whole
        assigned += whole
        remainders.append((exact - whole, index))

    remainders.sort(key=lambda value: (-value[0], value[1]))
    for _, index in remainders[: remaining - assigned]:
        allocations[index] += 1
    return tuple(allocations)


def _resample(stroke: _PreparedStroke, count: int) -> Tuple[_Sample, ...]:
    if count <= 0:
        raise AssertionError("sample count must be positive")
    points = stroke.points
    if count == 1:
        return (_sample(points[0], stroke.creation_time_offset),)
    if stroke.arc_length == 0.0:
        return (
            _sample(points[0], stroke.creation_time_offset),
            _sample(points[-1], stroke.creation_time_offset),
        )

    cumulative = [0.0] * len(points)
    for index in range(1, len(points)):
        cumulative[index] = cumulative[index - 1] + math.hypot(
            points[index].x - points[index - 1].x,
            points[index].y - points[index - 1].y,
        )

    result = []
    segment = 1
    for sample_index in range(count):
        if sample_index == 0:
            result.append(_sample(points[0], stroke.creation_time_offset))
            continue
        if sample_index == count - 1:
            result.append(_sample(points[-1], stroke.creation_time_offset))
            continue

        target = stroke.arc_length * sample_index / (count - 1)
        while segment < len(cumulative) - 1 and cumulative[segment] < target:
            segment += 1
        lower = segment - 1
        segment_length = cumulative[segment] - cumulative[lower]
        if segment_length <= 0.0:
            result.append(_sample(points[segment], stroke.creation_time_offset))
            continue
        fraction = (target - cumulative[lower]) / segment_length
        local_time = _interpolated_time(
            points[lower].time_offset,
            points[segment].time_offset,
            fraction,
        )
        result.append(
            _make_sample(
                x=points[lower].x + (points[segment].x - points[lower].x) * fraction,
                y=points[lower].y + (points[segment].y - points[lower].y) * fraction,
                local_time=local_time,
                creation_time=stroke.creation_time_offset,
            )
        )
    return tuple(result)


def _sample(point: _PreparedPoint, creation_time: Optional[float]) -> _Sample:
    return _make_sample(point.x, point.y, point.time_offset, creation_time)


def _make_sample(
    x: float,
    y: float,
    local_time: Optional[float],
    creation_time: Optional[float],
) -> _Sample:
    absolute_time = None
    if local_time is not None and creation_time is not None:
        candidate = local_time + creation_time
        if math.isfinite(candidate):
            absolute_time = candidate
    return _Sample(x, y, local_time, absolute_time)


def _interpolated_time(
    start: Optional[float], end: Optional[float], fraction: float
) -> Optional[float]:
    if start is None or end is None or end < start:
        return None
    value = start + (end - start) * fraction
    return value if math.isfinite(value) else None


def _timing_delta(
    current: _Sample,
    previous_in_stroke: Optional[_Sample],
    previous_globally: Optional[_Sample],
) -> Tuple[float, bool]:
    delta_and_cap = None  # type: Optional[Tuple[float, float]]
    if (
        previous_in_stroke is not None
        and current.local_time is not None
        and previous_in_stroke.local_time is not None
    ):
        delta_and_cap = (
            current.local_time - previous_in_stroke.local_time,
            MAXIMUM_WITHIN_STROKE_DELTA_TIME_SECONDS,
        )
    elif (
        previous_in_stroke is None
        and previous_globally is not None
        and current.absolute_time is not None
        and previous_globally.absolute_time is not None
    ):
        delta_and_cap = (
            current.absolute_time - previous_globally.absolute_time,
            MAXIMUM_PEN_UP_DELTA_TIME_SECONDS,
        )

    if (
        delta_and_cap is None
        or not math.isfinite(delta_and_cap[0])
        or delta_and_cap[0] < 0.0
    ):
        return 0.0, False
    delta, cap = delta_and_cap
    return min(delta, cap) / cap, True


def _set(
    values: list,
    sample_index: int,
    channel: TrajectoryChannel,
    value: float,
) -> None:
    converted = _float32(value)
    if not math.isfinite(converted):
        # Swift treats this as an invariant.  The Python artifact boundary must
        # not emit an invalid tensor even if a future code change violates it.
        _refuse(
            "nonfinite_encoded_feature",
            f"trajectory[{sample_index}][{int(channel)}]",
            "Float32 conversion must remain finite",
        )
    values[sample_index * TRAJECTORY_CHANNEL_COUNT + int(channel)] = converted


def _float32(value: float) -> float:
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def _draw_round_segment(
    start: Tuple[float, float],
    end: Tuple[float, float],
    radius: float,
    pixels: bytearray,
) -> None:
    min_pixel_x = max(0, math.floor(min(start[0], end[0]) - radius - 0.5))
    max_pixel_x = min(
        RASTER_WIDTH - 1, math.ceil(max(start[0], end[0]) + radius - 0.5)
    )
    min_pixel_y = max(0, math.floor(min(start[1], end[1]) - radius - 0.5))
    max_pixel_y = min(
        RASTER_HEIGHT - 1, math.ceil(max(start[1], end[1]) + radius - 0.5)
    )
    if min_pixel_x > max_pixel_x or min_pixel_y > max_pixel_y:
        return

    delta_x = end[0] - start[0]
    delta_y = end[1] - start[1]
    squared_length = delta_x * delta_x + delta_y * delta_y
    squared_radius = radius * radius

    for y in range(min_pixel_y, max_pixel_y + 1):
        for x in range(min_pixel_x, max_pixel_x + 1):
            pixel_x = x + 0.5
            pixel_y = y + 0.5
            if squared_length > 0.0:
                fraction = min(
                    1.0,
                    max(
                        0.0,
                        (
                            (pixel_x - start[0]) * delta_x
                            + (pixel_y - start[1]) * delta_y
                        )
                        / squared_length,
                    ),
                )
            else:
                fraction = 0.0
            closest_x = start[0] + fraction * delta_x
            closest_y = start[1] + fraction * delta_y
            distance_x = pixel_x - closest_x
            distance_y = pixel_y - closest_y
            if distance_x * distance_x + distance_y * distance_y <= squared_radius:
                pixels[y * RASTER_WIDTH + x] = RASTER_FOREGROUND


def _refuse(code: str, path: str, detail: str) -> None:
    raise FeatureEncodingError(code, path, detail)


def strokes(points_by_stroke: Iterable[Iterable[Tuple[float, float]]]) -> Tuple[InkStroke, ...]:
    """Small convenience for deterministic fixtures and research scripts."""

    return tuple(
        InkStroke(tuple(InkPoint(x, y) for x, y in stroke_points))
        for stroke_points in points_by_stroke
    )
