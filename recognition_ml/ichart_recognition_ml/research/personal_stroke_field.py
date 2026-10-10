"""Research-only spatial stroke-field representation for isolated glyphs.

The frozen app raster is retained exactly as channel zero.  Four additive
channels register local pen direction and stroke endpoints in the same physical
pixel frame.  This module has no corpus loader, fit, score, app, or profile
entry point.
"""

from __future__ import annotations

import math
from typing import Sequence

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from ..features import (
    InkStroke,
    RASTER_HEIGHT,
    RASTER_PADDING,
    RASTER_STROKE_WIDTH,
    RASTER_WIDTH,
    _draw_round_segment,
    _prepare,
    rasterize,
)


VERSION = "personal-spatial-stroke-field-v1"
MODEL_VERSION = "personal-stroke-field-encoder-v2-97-or-102"
CHANNEL_NAMES = ("occupancy", "tangentX", "tangentY", "strokeStart", "strokeEnd")
CHANNEL_COUNT = len(CHANNEL_NAMES)
ARMS = ("rasterControl", "strokeField")
VOCABULARY_SIZE = 97
SUPPORTED_VOCABULARY_SIZES = (97, 102)
EMBEDDING_SIZE = 128

MAXIMUM_ABSOLUTE_ANGLE_DEGREES = 8.0
MINIMUM_SAMPLING_SCALE = 0.9
MAXIMUM_SAMPLING_SCALE = 1.1
MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION = 0.03
MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION = 0.05

_RADIUS = RASTER_STROKE_WIDTH / 2.0
_HORIZONTAL_SPAN = RASTER_WIDTH - 2.0 * (RASTER_PADDING + _RADIUS)
_VERTICAL_SPAN = RASTER_HEIGHT - 2.0 * (RASTER_PADDING + _RADIUS)


def _raster_mapping(prepared):
    horizontal = (
        _HORIZONTAL_SPAN / prepared.normalized_width
        if prepared.normalized_width > 0.0
        else math.inf
    )
    vertical = (
        _VERTICAL_SPAN / prepared.normalized_height
        if prepared.normalized_height > 0.0
        else math.inf
    )
    finite = tuple(value for value in (horizontal, vertical) if math.isfinite(value))
    scale = min(finite) if finite else 0.0

    def mapped(point):
        return (
            RASTER_WIDTH / 2.0 + point.x * scale,
            RASTER_HEIGHT / 2.0 + point.y * scale,
        )

    return mapped


def _segment_circle_intersection_length(start, end, center_x, center_y):
    """Length of one centerline segment inside a radius-1.5 pixel disk."""

    delta_x = end[0] - start[0]
    delta_y = end[1] - start[1]
    squared_length = delta_x * delta_x + delta_y * delta_y
    if squared_length == 0.0:
        return 0.0
    offset_x = start[0] - center_x
    offset_y = start[1] - center_y
    linear = 2.0 * (offset_x * delta_x + offset_y * delta_y)
    constant = offset_x * offset_x + offset_y * offset_y - _RADIUS * _RADIUS
    discriminant = linear * linear - 4.0 * squared_length * constant
    tolerance = 1e-12 * max(1.0, linear * linear, abs(4.0 * squared_length * constant))
    if discriminant < -tolerance:
        return 0.0
    root = math.sqrt(max(0.0, discriminant))
    denominator = 2.0 * squared_length
    lower = max(0.0, (-linear - root) / denominator)
    upper = min(1.0, (-linear + root) / denominator)
    if upper <= lower:
        return 0.0
    return (upper - lower) * math.sqrt(squared_length)


def _segment_pixels(start, end):
    min_x = max(0, math.floor(min(start[0], end[0]) - _RADIUS - 0.5))
    max_x = min(
        RASTER_WIDTH - 1,
        math.ceil(max(start[0], end[0]) + _RADIUS - 0.5),
    )
    min_y = max(0, math.floor(min(start[1], end[1]) - _RADIUS - 0.5))
    max_y = min(
        RASTER_HEIGHT - 1,
        math.ceil(max(start[1], end[1]) + _RADIUS - 0.5),
    )
    if min_x > max_x or min_y > max_y:
        return
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            length = _segment_circle_intersection_length(
                start, end, x + 0.5, y + 0.5
            )
            if length > 0.0:
                yield y * RASTER_WIDTH + x, length


def _paint_endpoint(pixels: bytearray, point) -> None:
    # Reuse the frozen raster painter so endpoint disks have the exact same
    # radius, pixel-center convention, clipping, and inclusive bounds.
    _draw_round_segment(point, point, _RADIUS, pixels)


def encode_stroke_field(strokes: Sequence[InkStroke]) -> np.ndarray:
    """Return one finite Float32 ``[5, 96, 256]`` spatial stroke field."""

    prepared = _prepare(strokes)
    occupancy_bytes = rasterize(strokes).pixels
    result = np.zeros((CHANNEL_COUNT, RASTER_HEIGHT, RASTER_WIDTH), dtype=np.float32)
    result[0] = (
        np.frombuffer(occupancy_bytes, dtype=np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )

    mapped = _raster_mapping(prepared)
    contributions: dict[int, list[tuple[float, float, float]]] = {}
    starts = bytearray(RASTER_WIDTH * RASTER_HEIGHT)
    ends = bytearray(RASTER_WIDTH * RASTER_HEIGHT)

    for stroke in prepared.strokes:
        mapped_points = tuple(mapped(point) for point in stroke.points)
        _paint_endpoint(starts, mapped_points[0])
        _paint_endpoint(ends, mapped_points[-1])
        for start, end in zip(mapped_points, mapped_points[1:]):
            delta_x = end[0] - start[0]
            delta_y = end[1] - start[1]
            length = math.hypot(delta_x, delta_y)
            if length == 0.0:
                continue
            unit_x = delta_x / length
            unit_y = delta_y / length
            for pixel, inside_length in _segment_pixels(start, end):
                contributions.setdefault(pixel, []).append(
                    (inside_length, unit_x, unit_y)
                )

    flat_x = result[1].reshape(-1)
    flat_y = result[2].reshape(-1)
    for pixel, values in contributions.items():
        # A stable contribution order keeps overlapping-stroke accumulation
        # independent of source stroke enumeration, apart from the declared
        # final Float32 rounding.
        ordered = sorted(values)
        total = math.fsum(value[0] for value in ordered)
        if total > 0.0:
            flat_x[pixel] = np.float32(
                math.fsum(value[0] * value[1] for value in ordered) / total
            )
            flat_y[pixel] = np.float32(
                math.fsum(value[0] * value[2] for value in ordered) / total
            )

    result[3] = (
        np.frombuffer(starts, dtype=np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )
    result[4] = (
        np.frombuffer(ends, dtype=np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )
    if not np.isfinite(result).all():
        raise ValueError("Stroke-field encoding produced nonfinite values")
    return result


def sample_affine_draws(count: int, generator: torch.Generator) -> torch.Tensor:
    """Draw the historical four affine uniforms for an entire batch."""

    if isinstance(count, bool) or not isinstance(count, int) or count <= 0:
        raise ValueError("Affine draw count must be a positive integer")
    if not isinstance(generator, torch.Generator):
        raise ValueError("A Torch generator is required")
    return torch.rand((count, 4), generator=generator, dtype=torch.float32)


def augment_stroke_fields(fields: torch.Tensor, draws: torch.Tensor) -> torch.Tensor:
    """Apply shared historical-range affine draws to five registered planes."""

    if not isinstance(fields, torch.Tensor) or not isinstance(draws, torch.Tensor):
        raise ValueError("Stroke fields and affine draws must be Torch tensors")
    if fields.dtype != torch.float32 or draws.dtype != torch.float32:
        raise ValueError("Stroke fields and affine draws must be Float32")
    if fields.ndim != 4 or tuple(fields.shape[1:]) != (
        CHANNEL_COUNT,
        RASTER_HEIGHT,
        RASTER_WIDTH,
    ):
        raise ValueError("Stroke-field batch has the wrong shape")
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
    transformed = F.grid_sample(
        fields,
        grid,
        mode="bilinear",
        padding_mode="zeros",
        align_corners=False,
    )

    # ``theta`` maps output pixels to input pixels. Displayed ink therefore
    # rotates by ``-angle`` in the physical pixel frame, and its tangent vector
    # must undergo that same forward transform.
    tangent_x = transformed[:, 1]
    tangent_y = transformed[:, 2]
    cosine = torch.cos(angle).reshape(-1, 1, 1)
    sine = torch.sin(angle).reshape(-1, 1, 1)
    rotated_x = cosine * tangent_x + sine * tangent_y
    rotated_y = -sine * tangent_x + cosine * tangent_y
    transformed = torch.cat(
        (
            transformed[:, :1],
            rotated_x.unsqueeze(1),
            rotated_y.unsqueeze(1),
            transformed[:, 3:],
        ),
        dim=1,
    )
    if not bool(torch.isfinite(transformed).all()):
        raise ValueError("Stroke-field augmentation produced nonfinite values")
    return transformed


class PersonalStrokeFieldEncoder(nn.Module):
    """Matched five-input encoder; the control zeros channels 1...4."""

    def __init__(self, label_count: int, arm: str):
        super().__init__()
        if isinstance(label_count, bool) or label_count not in SUPPORTED_VOCABULARY_SIZES:
            raise ValueError(f"Expected exactly one of {SUPPORTED_VOCABULARY_SIZES} labels")
        if arm not in ARMS:
            raise ValueError("Unknown stroke-field arm")
        self.arm = arm
        self.label_count = label_count
        blocks: list[nn.Module] = [nn.AvgPool2d(2)]
        incoming = CHANNEL_COUNT
        for outgoing in (16, 32, 64, 64):
            blocks.extend(
                (
                    nn.Conv2d(incoming, outgoing, 3, stride=2, padding=1),
                    nn.BatchNorm2d(outgoing),
                    nn.ReLU(),
                )
            )
            incoming = outgoing
        self.convolution = nn.Sequential(*blocks)
        self.projection = nn.Linear(64 * 3 * 8, EMBEDDING_SIZE)
        self.classifier = nn.Linear(EMBEDDING_SIZE, label_count)

    def forward(self, fields: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        if fields.ndim != 4 or tuple(fields.shape[1:]) != (
            CHANNEL_COUNT,
            RASTER_HEIGHT,
            RASTER_WIDTH,
        ):
            raise ValueError("Stroke fields have the wrong shape")
        if fields.dtype != torch.float32 or not bool(torch.isfinite(fields).all()):
            raise ValueError("Stroke fields must be finite Float32")
        active = fields
        if self.arm == "rasterControl":
            active = torch.cat((fields[:, :1], torch.zeros_like(fields[:, 1:])), dim=1)
        raw = self.projection(self.convolution(active).flatten(1))
        return F.normalize(raw, dim=1), self.classifier(raw)
