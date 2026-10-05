"""Deterministic, label-blind near-neighbor candidate generation.

This scanner is deliberately conservative.  It exhaustively compares the
human lineage roots in one bounded corpus and emits candidates for protected
manual adjudication.  It does not assign geometry clusters, declare a corpus
leak-free, or make any record eligible for a model role.
"""

import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Mapping, Sequence, Tuple

from .contracts import (
    CorpusRecord,
    load_validated_feature_artifacts,
    records_digest,
)
from .errors import ContractError
from .features import TrajectoryChannel
from .schema import FEATURE_SCHEMA, SOURCE_HUMAN


LEAKAGE_SCAN_REPORT_SCHEMA_VERSION = "recognition-leakage-scan-report-v1"
LEAKAGE_SCANNER_VERSION = "near-neighbor-v1"
PARTS_PER_MILLION = 1_000_000


def _popcount(value: int) -> int:
    return value.bit_count()


@dataclass(frozen=True)
class LeakageScanConfig:
    """Frozen candidate-generation thresholds for the bounded pilot scanner."""

    scanner_version: str = LEAKAGE_SCANNER_VERSION
    maximum_root_sample_count: int = 5_000
    high_similarity_radius_1_coverage_ppm: int = 970_000
    high_similarity_ink_ratio_ppm: int = 850_000
    manual_review_radius_2_coverage_ppm: int = 880_000
    manual_review_ink_ratio_ppm: int = 650_000
    manual_review_trajectory_distance_microunits: int = 25_000
    manual_review_trajectory_raster_coverage_ppm: int = 780_000

    def as_dict(self) -> Dict[str, object]:
        return {
            "high_similarity_ink_ratio_ppm": self.high_similarity_ink_ratio_ppm,
            "high_similarity_radius_1_coverage_ppm": (
                self.high_similarity_radius_1_coverage_ppm
            ),
            "manual_review_ink_ratio_ppm": self.manual_review_ink_ratio_ppm,
            "manual_review_radius_2_coverage_ppm": (
                self.manual_review_radius_2_coverage_ppm
            ),
            "manual_review_trajectory_distance_microunits": (
                self.manual_review_trajectory_distance_microunits
            ),
            "manual_review_trajectory_raster_coverage_ppm": (
                self.manual_review_trajectory_raster_coverage_ppm
            ),
            "maximum_root_sample_count": self.maximum_root_sample_count,
            "scanner_version": self.scanner_version,
        }


DEFAULT_LEAKAGE_SCAN_CONFIG = LeakageScanConfig()


@dataclass(frozen=True)
class _Geometry:
    sample_id: str
    stroke_payload_sha256: str
    trajectory_sha256: str
    raster_sha256: str
    raster_bits: int
    dilated_radius_1_bits: int
    dilated_radius_2_bits: int
    foreground_pixel_count: int
    trajectory_points: Tuple[Tuple[float, float], ...]
    stroke_count: int


def _ppm(numerator: int, denominator: int) -> int:
    if denominator <= 0:
        raise ContractError(
            "invalid_similarity_denominator",
            "leakage_scan",
            "similarity metrics require nonempty ink",
        )
    return (numerator * PARTS_PER_MILLION + denominator // 2) // denominator


def _raster_rows(payload: bytes) -> Tuple[int, ...]:
    width = FEATURE_SCHEMA.raster_width
    rows = []
    for y in range(FEATURE_SCHEMA.raster_height):
        offset = y * width
        row = 0
        for x, value in enumerate(payload[offset : offset + width]):
            if value:
                row |= 1 << x
        rows.append(row)
    return tuple(rows)


def _dilate_rows(rows: Sequence[int], radius: int) -> Tuple[int, ...]:
    width_mask = (1 << FEATURE_SCHEMA.raster_width) - 1
    output = []
    for y in range(FEATURE_SCHEMA.raster_height):
        combined = 0
        for source_y in range(max(0, y - radius), min(len(rows), y + radius + 1)):
            source = rows[source_y]
            combined |= source
            for horizontal in range(1, radius + 1):
                combined |= source << horizontal
                combined |= source >> horizontal
        output.append(combined & width_mask)
    return tuple(output)


def _flatten_rows(rows: Sequence[int]) -> int:
    width = FEATURE_SCHEMA.raster_width
    flattened = 0
    for y, row in enumerate(rows):
        flattened |= row << (y * width)
    return flattened


def _trajectory_geometry(payload: bytes) -> Tuple[Tuple[Tuple[float, float], ...], int]:
    channel_count = FEATURE_SCHEMA.trajectory_shape[2]
    values = tuple(item[0] for item in struct.iter_unpack("<f", payload))
    points = []
    stroke_count = 0
    for sample_index in range(FEATURE_SCHEMA.trajectory_shape[1]):
        offset = sample_index * channel_count
        if values[offset + int(TrajectoryChannel.VALID)] != 1.0:
            continue
        points.append(
            (
                values[offset + int(TrajectoryChannel.X)],
                values[offset + int(TrajectoryChannel.Y)],
            )
        )
        if values[offset + int(TrajectoryChannel.STROKE_START)] == 1.0:
            stroke_count += 1
    if not points or stroke_count <= 0:
        raise ContractError(
            "empty_trajectory_geometry",
            "leakage_scan",
            "a scanned root must contain valid trajectory points and a stroke start",
        )
    return tuple(points), stroke_count


def _geometry(record: CorpusRecord, trajectory: bytes, raster: bytes) -> _Geometry:
    rows = _raster_rows(raster)
    foreground_count = sum(_popcount(row) for row in rows)
    if foreground_count <= 0:
        raise ContractError(
            "empty_raster_geometry",
            record.sample_id,
            "a scanned root must contain foreground pixels",
        )
    points, stroke_count = _trajectory_geometry(trajectory)
    dilated_radius_1_rows = _dilate_rows(rows, 1)
    dilated_radius_2_rows = _dilate_rows(rows, 2)
    return _Geometry(
        sample_id=record.sample_id,
        stroke_payload_sha256=record.stroke_payload_sha256,
        trajectory_sha256=record.trajectory.sha256,
        raster_sha256=record.raster.sha256,
        raster_bits=_flatten_rows(rows),
        dilated_radius_1_bits=_flatten_rows(dilated_radius_1_rows),
        dilated_radius_2_bits=_flatten_rows(dilated_radius_2_rows),
        foreground_pixel_count=foreground_count,
        trajectory_points=points,
        stroke_count=stroke_count,
    )


def _symmetric_coverage_ppm(
    left: _Geometry,
    right: _Geometry,
    *,
    radius: int,
) -> int:
    if radius == 1:
        left_dilated = left.dilated_radius_1_bits
        right_dilated = right.dilated_radius_1_bits
    elif radius == 2:
        left_dilated = left.dilated_radius_2_bits
        right_dilated = right.dilated_radius_2_bits
    else:
        raise ValueError("only the frozen radius-1 and radius-2 metrics are supported")
    left_covered = _popcount(left.raster_bits & right_dilated)
    right_covered = _popcount(right.raster_bits & left_dilated)
    return min(
        _ppm(left_covered, left.foreground_pixel_count),
        _ppm(right_covered, right.foreground_pixel_count),
    )


def _sample_trajectory(points: Sequence[Tuple[float, float]], count: int = 64):
    if len(points) == 1:
        return tuple(points[0] for _ in range(count))
    return tuple(
        points[(index * (len(points) - 1) + (count - 1) // 2) // (count - 1)]
        for index in range(count)
    )


def _trajectory_distance_microunits(left: _Geometry, right: _Geometry) -> int:
    left_points = _sample_trajectory(left.trajectory_points)
    right_points = _sample_trajectory(right.trajectory_points)

    def distance(candidate: Sequence[Tuple[float, float]]) -> float:
        squared = sum(
            (left_x - right_x) ** 2 + (left_y - right_y) ** 2
            for (left_x, left_y), (right_x, right_y) in zip(left_points, candidate)
        )
        return math.sqrt(squared / len(left_points))

    normalized = min(distance(right_points), distance(tuple(reversed(right_points))))
    return int(normalized * PARTS_PER_MILLION + 0.5)


def _raster_pair_metrics(left: _Geometry, right: _Geometry) -> Dict[str, int]:
    if left.raster_sha256 == right.raster_sha256:
        return {
            "dilated_coverage_radius_1_ppm": PARTS_PER_MILLION,
            "dilated_coverage_radius_2_ppm": PARTS_PER_MILLION,
            "foreground_pixel_count_left": left.foreground_pixel_count,
            "foreground_pixel_count_right": right.foreground_pixel_count,
            "ink_count_ratio_ppm": PARTS_PER_MILLION,
            "raster_iou_ppm": PARTS_PER_MILLION,
        }
    intersection = _popcount(left.raster_bits & right.raster_bits)
    union = _popcount(left.raster_bits | right.raster_bits)
    smaller_count = min(left.foreground_pixel_count, right.foreground_pixel_count)
    larger_count = max(left.foreground_pixel_count, right.foreground_pixel_count)
    return {
        "dilated_coverage_radius_1_ppm": _symmetric_coverage_ppm(
            left, right, radius=1
        ),
        "dilated_coverage_radius_2_ppm": _symmetric_coverage_ppm(
            left, right, radius=2
        ),
        "foreground_pixel_count_left": left.foreground_pixel_count,
        "foreground_pixel_count_right": right.foreground_pixel_count,
        "ink_count_ratio_ppm": _ppm(smaller_count, larger_count),
        "raster_iou_ppm": _ppm(intersection, union),
    }


def _complete_pair_metrics(
    raster_metrics: Mapping[str, int], left: _Geometry, right: _Geometry
) -> Dict[str, int]:
    trajectory_distance = (
        0
        if left.trajectory_sha256 == right.trajectory_sha256
        else _trajectory_distance_microunits(left, right)
    )
    return {
        **raster_metrics,
        "stroke_count_left": left.stroke_count,
        "stroke_count_right": right.stroke_count,
        "trajectory_distance_microunits": trajectory_distance,
    }


def _candidate_pair(
    left: _Geometry,
    right: _Geometry,
    config: LeakageScanConfig,
) -> Mapping[str, object]:
    exact_reasons = []
    if left.stroke_payload_sha256 == right.stroke_payload_sha256:
        exact_reasons.append("same-stroke-payload-digest")
    if left.trajectory_sha256 == right.trajectory_sha256:
        exact_reasons.append("same-trajectory-digest")
    if left.raster_sha256 == right.raster_sha256:
        exact_reasons.append("same-raster-digest")

    raster_metrics = _raster_pair_metrics(left, right)
    tier = None
    reasons = list(exact_reasons)
    if exact_reasons:
        tier = "exact-content"
    elif (
        raster_metrics["dilated_coverage_radius_1_ppm"]
        >= config.high_similarity_radius_1_coverage_ppm
        and raster_metrics["ink_count_ratio_ppm"]
        >= config.high_similarity_ink_ratio_ppm
    ):
        tier = "high-similarity"
        reasons.append("radius-1-raster-coverage")
    else:
        raster_review = (
            raster_metrics["dilated_coverage_radius_2_ppm"]
            >= config.manual_review_radius_2_coverage_ppm
            and raster_metrics["ink_count_ratio_ppm"]
            >= config.manual_review_ink_ratio_ppm
        )
        trajectory_review = False
        if (
            raster_metrics["dilated_coverage_radius_2_ppm"]
            >= config.manual_review_trajectory_raster_coverage_ppm
        ):
            trajectory_review = (
                _trajectory_distance_microunits(left, right)
                <= config.manual_review_trajectory_distance_microunits
            )
        if raster_review or trajectory_review:
            tier = "manual-review"
            if raster_review:
                reasons.append("radius-2-raster-coverage")
            if trajectory_review:
                reasons.append("ordered-trajectory-distance")

    if tier is None:
        return {}
    metrics = _complete_pair_metrics(raster_metrics, left, right)
    return {
        "left_sample_id": left.sample_id,
        "metrics": metrics,
        "reasons": reasons,
        "right_sample_id": right.sample_id,
        "tier": tier,
    }


def build_leakage_scan_report(
    records: Sequence[CorpusRecord],
    data_root: Path,
    config: LeakageScanConfig = DEFAULT_LEAKAGE_SCAN_CONFIG,
) -> Dict[str, object]:
    """Build a deterministic candidate report without consulting labels or writers."""

    if not records:
        raise ContractError("empty_corpus", "records", "at least one record is required")
    by_id = {}
    for record in records:
        if record.sample_id in by_id:
            raise ContractError(
                "duplicate_sample", record.sample_id, "sample IDs must be unique"
            )
        by_id[record.sample_id] = record
        if record.leakage_check_version != config.scanner_version:
            raise ContractError(
                "leakage_scanner_version_mismatch",
                record.sample_id,
                f"expected {config.scanner_version}, got {record.leakage_check_version}",
            )

    payloads = {
        record.sample_id: load_validated_feature_artifacts(record, data_root)
        for record in sorted(records, key=lambda item: item.sample_id)
    }
    roots = tuple(
        record
        for record in sorted(records, key=lambda item: item.sample_id)
        if record.source_kind == SOURCE_HUMAN
        and record.parent_sample_id is None
        and record.root_sample_id == record.sample_id
    )
    if not roots:
        raise ContractError(
            "empty_root_set",
            "records",
            "at least one consented human lineage root is required",
        )
    if len(roots) > config.maximum_root_sample_count:
        raise ContractError(
            "leakage_scan_capacity_exceeded",
            "records",
            (
                f"{len(roots)} roots exceed the exhaustive scanner limit of "
                f"{config.maximum_root_sample_count}; a new versioned scaling plan is required"
            ),
        )

    geometries = tuple(
        _geometry(root, *payloads[root.sample_id])
        for root in roots
    )
    candidates: List[Mapping[str, object]] = []
    comparison_count = 0
    for left_index, left in enumerate(geometries):
        for right in geometries[left_index + 1 :]:
            comparison_count += 1
            candidate = _candidate_pair(left, right, config)
            if candidate:
                candidates.append(candidate)

    tier_counts = {
        "exact-content": 0,
        "high-similarity": 0,
        "manual-review": 0,
    }
    for candidate in candidates:
        tier_counts[str(candidate["tier"])] += 1

    commitments = [
        {
            "raster_sha256": root.raster.sha256,
            "sample_id": root.sample_id,
            "stroke_payload_sha256": root.stroke_payload_sha256,
            "trajectory_sha256": root.trajectory.sha256,
        }
        for root in roots
    ]
    return {
        "all_root_pairs_compared": True,
        "artifact_commitments": commitments,
        "authority": "candidate-generation-only",
        "candidate_pair_count": len(candidates),
        "candidate_pairs": candidates,
        "config": config.as_dict(),
        "corpus_qualified": False,
        "feature_schema": FEATURE_SCHEMA.as_dict(),
        "labels_inspected": False,
        "pair_comparison_count": comparison_count,
        "records_sha256": records_digest(records),
        "requires_protected_adjudication": bool(candidates),
        "root_sample_count": len(roots),
        "schema_version": LEAKAGE_SCAN_REPORT_SCHEMA_VERSION,
        "status": "leakage-candidates-generated",
        "tier_counts": tier_counts,
    }
