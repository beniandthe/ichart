"""Research-only synchronized affine augmentation for frozen glyph features.

The existing visual encoder augments only its raster.  This module applies one
deterministic affine draw to a canonical trajectory/raster pair without running
the source geometry through ``features._prepare`` again.  It has no training,
scoring, model-selection, app, or profile entry point.

``torch.nn.functional.affine_grid`` defines an output-to-input sampling map.
Trajectory points describe input ink, so they are transformed by the inverse
map in the raster's physical pixel frame.  This distinction is intentional and
covered by asymmetric-shape tests.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import re
from typing import Sequence

import torch
from torch.nn import functional as F

from ..features import (
    RASTER_HEIGHT,
    RASTER_PADDING,
    RASTER_STROKE_WIDTH,
    RASTER_WIDTH,
    TRAJECTORY_CHANNEL_COUNT,
    TRAJECTORY_SAMPLE_COUNT,
    TrajectoryChannel,
)


VERSION = "personal-synchronized-augmentation-v1"
DRAW_CONTRACT_VERSION = "sha256-seed-epoch-source-four-u64-v1"
PAIR_CONTRACT_VERSION = "canonical-trajectory-raster-affine-pair-v1"

MAXIMUM_ABSOLUTE_ANGLE_DEGREES = 8.0
MINIMUM_SAMPLING_SCALE = 0.9
MAXIMUM_SAMPLING_SCALE = 1.1
MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION = 0.03
MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION = 0.05

_HORIZONTAL_CONTENT_SPAN = RASTER_WIDTH - 2.0 * (
    RASTER_PADDING + RASTER_STROKE_WIDTH / 2.0
)
_VERTICAL_CONTENT_SPAN = RASTER_HEIGHT - 2.0 * (
    RASTER_PADDING + RASTER_STROKE_WIDTH / 2.0
)
_DEGENERATE_EFFECTIVE_PIXELS_PER_UNIT = min(
    _HORIZONTAL_CONTENT_SPAN, _VERTICAL_CONTENT_SPAN
)
_SHA256 = re.compile(r"[0-9a-f]{64}")


def _canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _finite(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


@dataclass(frozen=True)
class CanonicalRasterMapping:
    """Exact canonical-trajectory to source-raster mapping for one glyph.

    ``pixels_per_unit`` is the exact scale chosen by ``features.rasterize``.
    It is zero only for a zero-width/zero-height source.  Such a glyph still
    rasterizes at the canvas center; the declared finite effective scale makes
    its affine displacement representable in the paired trajectory without
    inventing source extent.
    """

    normalized_width: float
    normalized_height: float
    pixels_per_unit: float

    def __post_init__(self) -> None:
        values = (self.normalized_width, self.normalized_height, self.pixels_per_unit)
        if not all(_finite(value) for value in values):
            raise ValueError("Canonical raster mapping must be finite")
        width = float(self.normalized_width)
        height = float(self.normalized_height)
        scale = float(self.pixels_per_unit)
        if width < 0.0 or height < 0.0 or width > 1.0 or height > 1.0 or scale < 0.0:
            raise ValueError("Canonical raster mapping is out of range")

        if width == 0.0 and height == 0.0:
            if scale != 0.0:
                raise ValueError("A zero-extent source must retain source raster scale zero")
            return

        if not math.isclose(max(width, height), 1.0, rel_tol=0.0, abs_tol=1e-12):
            raise ValueError("A nondegenerate canonical extent must have maximum dimension one")
        candidates = []
        if width > 0.0:
            candidates.append(_HORIZONTAL_CONTENT_SPAN / width)
        if height > 0.0:
            candidates.append(_VERTICAL_CONTENT_SPAN / height)
        expected = min(candidates)
        if not math.isclose(scale, expected, rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError("pixels_per_unit does not match the frozen raster mapping")

    @property
    def degenerate_extent(self) -> bool:
        return self.normalized_width == 0.0 and self.normalized_height == 0.0

    @property
    def effective_pixels_per_unit(self) -> float:
        return (
            _DEGENERATE_EFFECTIVE_PIXELS_PER_UNIT
            if self.degenerate_extent
            else float(self.pixels_per_unit)
        )

    def metadata(self) -> dict[str, object]:
        return {
            "degenerateExtent": self.degenerate_extent,
            "effectivePixelsPerUnit": self.effective_pixels_per_unit,
            "normalizedHeight": float(self.normalized_height),
            "normalizedWidth": float(self.normalized_width),
            "rasterCenterX": RASTER_WIDTH / 2.0,
            "rasterCenterY": RASTER_HEIGHT / 2.0,
            "rasterHeight": RASTER_HEIGHT,
            "rasterWidth": RASTER_WIDTH,
            "sourcePixelsPerUnit": float(self.pixels_per_unit),
        }


@dataclass(frozen=True)
class SynchronizedAffineTransform:
    """One historical-range affine-grid draw and its source-only identity."""

    seed: int
    epoch: int
    source_identity_sha256: str
    angle_radians: float
    sampling_scale: float
    translation_x_fraction: float
    translation_y_fraction: float

    def __post_init__(self) -> None:
        if (
            isinstance(self.seed, bool)
            or not isinstance(self.seed, int)
            or self.seed < 0
            or isinstance(self.epoch, bool)
            or not isinstance(self.epoch, int)
            or self.epoch < 0
            or _SHA256.fullmatch(self.source_identity_sha256) is None
        ):
            raise ValueError("Invalid deterministic transform identity")
        numeric = (
            self.angle_radians,
            self.sampling_scale,
            self.translation_x_fraction,
            self.translation_y_fraction,
        )
        if not all(_finite(value) for value in numeric):
            raise ValueError("Affine transform values must be finite")
        if abs(math.degrees(float(self.angle_radians))) > MAXIMUM_ABSOLUTE_ANGLE_DEGREES + 1e-12:
            raise ValueError("Rotation exceeds the frozen range")
        if not MINIMUM_SAMPLING_SCALE <= float(self.sampling_scale) <= MAXIMUM_SAMPLING_SCALE:
            raise ValueError("Sampling scale exceeds the frozen range")
        if abs(float(self.translation_x_fraction)) > MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION:
            raise ValueError("Horizontal translation exceeds the frozen range")
        if abs(float(self.translation_y_fraction)) > MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION:
            raise ValueError("Vertical translation exceeds the frozen range")

    def _identity_metadata(self) -> dict[str, object]:
        return {
            "angleRadians": float(self.angle_radians),
            "drawContractVersion": DRAW_CONTRACT_VERSION,
            "epoch": self.epoch,
            "samplingScale": float(self.sampling_scale),
            "seed": self.seed,
            "sourceIdentitySHA256": self.source_identity_sha256,
            "translationXFraction": float(self.translation_x_fraction),
            "translationYFraction": float(self.translation_y_fraction),
            "version": VERSION,
        }

    @property
    def sha256(self) -> str:
        return _sha256(_canonical_json_bytes(self._identity_metadata()))

    def metadata(self) -> dict[str, object]:
        return {**self._identity_metadata(), "drawSHA256": self.sha256}


@dataclass(frozen=True)
class SynchronizedAugmentedBatch:
    trajectory: torch.Tensor
    raster: torch.Tensor
    metadata: dict[str, object]
    metadata_sha256: str


def derive_transform(seed: int, epoch: int, source_identity: str) -> SynchronizedAffineTransform:
    """Derive four order-independent uniform draws from seed/epoch/source."""

    if (
        isinstance(seed, bool)
        or not isinstance(seed, int)
        or seed < 0
        or isinstance(epoch, bool)
        or not isinstance(epoch, int)
        or epoch < 0
        or not isinstance(source_identity, str)
        or not source_identity
    ):
        raise ValueError("Invalid transform derivation input")
    source = source_identity.encode("utf-8")
    frame = (
        DRAW_CONTRACT_VERSION.encode("ascii")
        + b"\0"
        + str(seed).encode("ascii")
        + b"\0"
        + str(epoch).encode("ascii")
        + b"\0"
        + source
    )
    digest = hashlib.sha256(frame).digest()
    denominator = float(1 << 64)
    draws = tuple(
        int.from_bytes(digest[index : index + 8], "big") / denominator
        for index in range(0, 32, 8)
    )
    return SynchronizedAffineTransform(
        seed=seed,
        epoch=epoch,
        source_identity_sha256=_sha256(source),
        angle_radians=math.radians(
            (draws[0] * 2.0 - 1.0) * MAXIMUM_ABSOLUTE_ANGLE_DEGREES
        ),
        sampling_scale=(
            MINIMUM_SAMPLING_SCALE
            + draws[1] * (MAXIMUM_SAMPLING_SCALE - MINIMUM_SAMPLING_SCALE)
        ),
        translation_x_fraction=(
            (draws[2] * 2.0 - 1.0) * MAXIMUM_ABSOLUTE_X_TRANSLATION_FRACTION
        ),
        translation_y_fraction=(
            (draws[3] * 2.0 - 1.0) * MAXIMUM_ABSOLUTE_Y_TRANSLATION_FRACTION
        ),
    )


def _sampling_theta(
    transform: SynchronizedAffineTransform, *, device: torch.device
) -> torch.Tensor:
    # Build in Float32 exactly as the historical PersonalVisualEncoder augmenter.
    angle = torch.tensor(transform.angle_radians, dtype=torch.float32, device=device)
    scale = torch.tensor(transform.sampling_scale, dtype=torch.float32, device=device)
    theta = torch.zeros((2, 3), dtype=torch.float32, device=device)
    theta[0, 0] = torch.cos(angle) * scale
    theta[1, 1] = torch.cos(angle) * scale
    theta[0, 1] = -torch.sin(angle) * scale * RASTER_HEIGHT / RASTER_WIDTH
    theta[1, 0] = torch.sin(angle) * scale * RASTER_WIDTH / RASTER_HEIGHT
    theta[0, 2] = float(transform.translation_x_fraction) * 2.0
    theta[1, 2] = float(transform.translation_y_fraction) * 2.0
    return theta


def _valid_count_and_structure(value: torch.Tensor) -> int:
    valid = value[0, :, int(TrajectoryChannel.VALID)]
    starts = value[0, :, int(TrajectoryChannel.STROKE_START)]
    ends = value[0, :, int(TrajectoryChannel.STROKE_END)]
    for name, channel in (("valid", valid), ("stroke-start", starts), ("stroke-end", ends)):
        if not bool(((channel == 0.0) | (channel == 1.0)).all()):
            raise ValueError(f"Trajectory {name} channel is not binary")
    count = int((valid == 1.0).sum().item())
    if count <= 0 or not bool((valid[:count] == 1.0).all()) or bool((valid[count:] != 0.0).any()):
        raise ValueError("Valid trajectory samples must form one nonempty prefix")
    if starts[0] != 1.0 or ends[count - 1] != 1.0:
        raise ValueError("Trajectory must begin and end on stroke boundaries")
    if count > 1 and not torch.equal(starts[1:count], ends[: count - 1]):
        raise ValueError("Trajectory stroke-start/end boundaries are inconsistent")
    if bool((starts[count:] != 0.0).any()) or bool((ends[count:] != 0.0).any()):
        raise ValueError("Invalid trajectory rows carry stroke boundaries")
    return count


def _transform_trajectory(
    source: torch.Tensor,
    theta: torch.Tensor,
    mapping: CanonicalRasterMapping,
) -> torch.Tensor:
    count = _valid_count_and_structure(source)
    result = torch.zeros_like(source)
    result[0, :count, int(TrajectoryChannel.STROKE_START)] = source[
        0, :count, int(TrajectoryChannel.STROKE_START)
    ]
    result[0, :count, int(TrajectoryChannel.STROKE_END)] = source[
        0, :count, int(TrajectoryChannel.STROKE_END)
    ]
    result[0, :count, int(TrajectoryChannel.VALID)] = 1.0

    pixels_per_unit = mapping.effective_pixels_per_unit
    frame = torch.tensor(
        [
            [2.0 * pixels_per_unit / RASTER_WIDTH, 0.0],
            [0.0, 2.0 * pixels_per_unit / RASTER_HEIGHT],
        ],
        dtype=torch.float64,
        device=source.device,
    )
    positions = source[0, :count, :2].to(dtype=torch.float64)
    sampling = theta[:, :2].to(dtype=torch.float64)
    translation = theta[:, 2].to(dtype=torch.float64)
    input_grid = positions @ frame.T
    output_grid = torch.linalg.solve(
        sampling, (input_grid - translation).T
    ).T
    output_positions = torch.linalg.solve(frame, output_grid.T).T
    if not bool(torch.isfinite(output_positions).all()):
        raise ValueError("Affine trajectory transform produced nonfinite positions")
    result[0, :count, :2] = output_positions.to(dtype=torch.float32)

    deltas = torch.zeros_like(output_positions)
    if count > 1:
        deltas[1:] = output_positions[1:] - output_positions[:-1]
    stroke_starts = source[
        0, :count, int(TrajectoryChannel.STROKE_START)
    ] == 1.0
    deltas[stroke_starts] = 0.0
    result[0, :count, int(TrajectoryChannel.DELTA_X)] = deltas[:, 0].to(torch.float32)
    result[0, :count, int(TrajectoryChannel.DELTA_Y)] = deltas[:, 1].to(torch.float32)
    result[0, :count, int(TrajectoryChannel.ARC_STEP)] = torch.linalg.vector_norm(
        deltas, dim=1
    ).to(torch.float32)

    # Timing value/availability and every invalid row intentionally remain zero.
    return result


def augment_batch(
    trajectory: torch.Tensor,
    raster: torch.Tensor,
    transforms: Sequence[SynchronizedAffineTransform],
    mappings: Sequence[CanonicalRasterMapping],
) -> SynchronizedAugmentedBatch:
    """Apply one bound affine draw to both canonical feature views per row."""

    if not isinstance(trajectory, torch.Tensor) or not isinstance(raster, torch.Tensor):
        raise ValueError("Canonical features must be Torch tensors")
    if trajectory.dtype != torch.float32 or raster.dtype != torch.float32:
        raise ValueError("Canonical features must be Float32")
    if trajectory.device != raster.device:
        raise ValueError("Canonical feature views must share one device")
    expected_trajectory = (1, TRAJECTORY_SAMPLE_COUNT, TRAJECTORY_CHANNEL_COUNT)
    expected_raster = (1, RASTER_HEIGHT, RASTER_WIDTH)
    if trajectory.ndim != 4 or tuple(trajectory.shape[1:]) != expected_trajectory:
        raise ValueError("Trajectory batch has the wrong frozen shape")
    if raster.ndim != 4 or tuple(raster.shape[1:]) != expected_raster:
        raise ValueError("Raster batch has the wrong frozen shape")
    count = int(trajectory.shape[0])
    if count <= 0 or raster.shape[0] != count or len(transforms) != count or len(mappings) != count:
        raise ValueError("Paired feature and transform batch counts differ")
    if not bool(torch.isfinite(trajectory).all()) or not bool(torch.isfinite(raster).all()):
        raise ValueError("Canonical feature views must be finite")
    if bool((raster < 0.0).any()) or bool((raster > 1.0).any()):
        raise ValueError("Canonical raster must be normalized to [0,1]")
    if any(not isinstance(value, SynchronizedAffineTransform) for value in transforms):
        raise ValueError("Unexpected transform value")
    if any(not isinstance(value, CanonicalRasterMapping) for value in mappings):
        raise ValueError("Unexpected canonical raster mapping")

    theta = torch.stack(
        [_sampling_theta(transform, device=trajectory.device) for transform in transforms]
    )
    grid = F.affine_grid(theta, raster.shape, align_corners=False)
    transformed_raster = F.grid_sample(
        raster,
        grid,
        mode="bilinear",
        padding_mode="zeros",
        align_corners=False,
    )
    # `affine_grid`'s mathematically identity grid can differ from the original
    # by a few Float32 interpolation ulps.  Preserve exact source bytes for an
    # explicitly identity draw; mixed batches still transform every other row.
    identity = torch.tensor(
        [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
        dtype=torch.float32,
        device=theta.device,
    )
    identity_rows = (theta == identity).all(dim=2).all(dim=1).reshape(-1, 1, 1, 1)
    transformed_raster = torch.where(identity_rows, raster, transformed_raster)
    transformed_trajectory = torch.stack(
        [
            _transform_trajectory(trajectory[index], theta[index], mappings[index])
            for index in range(count)
        ]
    )
    if not bool(torch.isfinite(transformed_raster).all()) or not bool(
        torch.isfinite(transformed_trajectory).all()
    ):
        raise ValueError("Synchronized augmentation produced nonfinite features")

    rows = [
        {
            "mapping": mapping.metadata(),
            "transform": transform.metadata(),
        }
        for transform, mapping in zip(transforms, mappings)
    ]
    metadata = {
        "drawContractVersion": DRAW_CONTRACT_VERSION,
        "pairContractVersion": PAIR_CONTRACT_VERSION,
        "rows": rows,
        "version": VERSION,
    }
    digest = _sha256(_canonical_json_bytes(metadata))
    return SynchronizedAugmentedBatch(
        trajectory=transformed_trajectory,
        raster=transformed_raster,
        metadata=metadata,
        metadata_sha256=digest,
    )
