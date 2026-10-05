"""Research-only direction-neutral spatial stroke fields for isolated glyphs.

Channel zero is the exact existing app raster.  The next three channels are
the length-weighted mean of each segment's unoriented outer product, and the
last channel is the union of both endpoints of every stroke.  No corpus,
label, writer, fit, score, profile, or app route is present here.
"""

from __future__ import annotations

import math
from typing import Sequence

import numpy as np
import torch
from torch.nn import functional as F

from ..features import InkStroke, RASTER_HEIGHT, RASTER_WIDTH, _prepare, rasterize
from . import personal_stroke_field as directed


VERSION = "personal-unoriented-stroke-field-v1"
MODEL_VERSION = "personal-unoriented-stroke-field-encoder-v1-97-or-102"
CHANNEL_NAMES = (
    "occupancy",
    "orientationXX",
    "orientationXY",
    "orientationYY",
    "endpointUnion",
)
CHANNEL_COUNT = len(CHANNEL_NAMES)
ARMS = ("rasterControl", "strokeField")
SUPPORTED_VOCABULARY_SIZES = directed.SUPPORTED_VOCABULARY_SIZES
EMBEDDING_SIZE = directed.EMBEDDING_SIZE

MAXIMUM_ABSOLUTE_ANGLE_DEGREES = directed.MAXIMUM_ABSOLUTE_ANGLE_DEGREES
MINIMUM_SAMPLING_SCALE = directed.MINIMUM_SAMPLING_SCALE
MAXIMUM_SAMPLING_SCALE = directed.MAXIMUM_SAMPLING_SCALE
MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION = directed.MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION
MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION = directed.MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION


def _canonical_segment(start, end):
    """Give reversal-equivalent segments the same floating-point arithmetic."""

    return (start, end) if start <= end else (end, start)


def _validate_orientation(result: np.ndarray) -> None:
    xx, xy, yy = result[1], result[2], result[3]
    trace = xx + yy
    determinant = xx * yy - xy * xy
    active = trace > np.float32(1e-7)
    if (
        not np.isfinite(result).all()
        or np.any(xx < -2e-6)
        or np.any(yy < -2e-6)
        or np.any(xx > 1.0 + 2e-6)
        or np.any(yy > 1.0 + 2e-6)
        or np.any(np.abs(xy) > 0.5 + 2e-6)
        or np.any(np.abs(trace[active] - 1.0) > 2e-6)
        or np.any(determinant[active] < -2e-6)
    ):
        raise ValueError("Unoriented stroke-field tensor invariant failed")


def encode_unoriented_stroke_field(strokes: Sequence[InkStroke]) -> np.ndarray:
    """Return a finite direction-neutral Float32 ``[5, 96, 256]`` field."""

    prepared = _prepare(strokes)
    occupancy = rasterize(strokes).pixels
    result = np.zeros((CHANNEL_COUNT, RASTER_HEIGHT, RASTER_WIDTH), dtype=np.float32)
    result[0] = (
        np.frombuffer(occupancy, dtype=np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )

    mapped = directed._raster_mapping(prepared)
    contributions: dict[int, list[tuple[float, float, float, float]]] = {}
    endpoints = bytearray(RASTER_WIDTH * RASTER_HEIGHT)
    for stroke in prepared.strokes:
        points = tuple(mapped(point) for point in stroke.points)
        directed._paint_endpoint(endpoints, points[0])
        directed._paint_endpoint(endpoints, points[-1])
        for first, second in zip(points, points[1:]):
            start, end = _canonical_segment(first, second)
            delta_x = end[0] - start[0]
            delta_y = end[1] - start[1]
            length = math.hypot(delta_x, delta_y)
            if length == 0.0:
                continue
            unit_x = delta_x / length
            unit_y = delta_y / length
            outer_xx = unit_x * unit_x
            outer_xy = unit_x * unit_y
            outer_yy = unit_y * unit_y
            for pixel, inside_length in directed._segment_pixels(start, end):
                contributions.setdefault(pixel, []).append(
                    (inside_length, outer_xx, outer_xy, outer_yy)
                )

    flat_xx = result[1].reshape(-1)
    flat_xy = result[2].reshape(-1)
    flat_yy = result[3].reshape(-1)
    for pixel, values in contributions.items():
        ordered = sorted(values)
        total = math.fsum(value[0] for value in ordered)
        if total > 0.0:
            flat_xx[pixel] = np.float32(
                math.fsum(value[0] * value[1] for value in ordered) / total
            )
            flat_xy[pixel] = np.float32(
                math.fsum(value[0] * value[2] for value in ordered) / total
            )
            flat_yy[pixel] = np.float32(
                math.fsum(value[0] * value[3] for value in ordered) / total
            )
    result[4] = (
        np.frombuffer(endpoints, dtype=np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )
    _validate_orientation(result)
    return result


sample_affine_draws = directed.sample_affine_draws


def augment_unoriented_stroke_fields(fields: torch.Tensor, draws: torch.Tensor) -> torch.Tensor:
    """Apply the historical affine and co-rotate each orientation tensor."""

    if not isinstance(fields, torch.Tensor) or not isinstance(draws, torch.Tensor):
        raise ValueError("Stroke fields and affine draws must be Torch tensors")
    if fields.dtype != torch.float32 or draws.dtype != torch.float32:
        raise ValueError("Stroke fields and affine draws must be Float32")
    if fields.ndim != 4 or tuple(fields.shape[1:]) != (
        CHANNEL_COUNT,
        RASTER_HEIGHT,
        RASTER_WIDTH,
    ):
        raise ValueError("Unoriented stroke-field batch has the wrong shape")
    if draws.shape != (len(fields), 4):
        raise ValueError("Affine draw batch has the wrong shape")
    if fields.device != draws.device:
        raise ValueError("Stroke fields and affine draws must share a device")
    if not bool(torch.isfinite(fields).all()) or not bool(torch.isfinite(draws).all()):
        raise ValueError("Stroke fields and affine draws must be finite")
    if bool((draws < 0.0).any()) or bool((draws > 1.0).any()):
        raise ValueError("Affine draws must lie in [0,1]")

    angle = (draws[:, 0] * 16.0 - 8.0) * math.pi / 180.0
    scale = draws[:, 1] * 0.2 + 0.9
    theta = torch.zeros((len(fields), 2, 3), dtype=torch.float32, device=fields.device)
    theta[:, 0, 0] = torch.cos(angle) * scale
    theta[:, 1, 1] = torch.cos(angle) * scale
    theta[:, 0, 1] = -torch.sin(angle) * scale * RASTER_HEIGHT / RASTER_WIDTH
    theta[:, 1, 0] = torch.sin(angle) * scale * RASTER_WIDTH / RASTER_HEIGHT
    theta[:, 0, 2] = (draws[:, 2] * 2.0 - 1.0) * 0.03 * 2.0
    theta[:, 1, 2] = (draws[:, 3] * 2.0 - 1.0) * 0.05 * 2.0
    grid = F.affine_grid(theta, fields.shape, align_corners=False)
    spatial = F.grid_sample(
        fields,
        grid,
        mode="bilinear",
        padding_mode="zeros",
        align_corners=False,
    )

    # The grid maps output to input.  Visible ink rotates by -angle, so the
    # symmetric tensor co-rotates as R(-angle) T R(-angle)^T.
    xx, xy, yy = spatial[:, 1], spatial[:, 2], spatial[:, 3]
    cosine = torch.cos(angle).reshape(-1, 1, 1)
    sine = torch.sin(angle).reshape(-1, 1, 1)
    rotated_xx = cosine.square() * xx + 2.0 * cosine * sine * xy + sine.square() * yy
    rotated_xy = (
        -cosine * sine * xx
        + (cosine.square() - sine.square()) * xy
        + cosine * sine * yy
    )
    rotated_yy = sine.square() * xx - 2.0 * cosine * sine * xy + cosine.square() * yy
    result = torch.cat(
        (
            spatial[:, :1],
            rotated_xx.unsqueeze(1),
            rotated_xy.unsqueeze(1),
            rotated_yy.unsqueeze(1),
            spatial[:, 4:5],
        ),
        dim=1,
    )
    if not bool(torch.isfinite(result).all()):
        raise ValueError("Unoriented stroke-field augmentation produced nonfinite values")
    return result


class PersonalUnorientedStrokeFieldEncoder(directed.PersonalStrokeFieldEncoder):
    """The same five-input architecture with a new direction-neutral identity."""

    def __init__(self, label_count: int, arm: str):
        if arm not in ARMS:
            raise ValueError("Unknown unoriented stroke-field arm")
        super().__init__(label_count, arm)
