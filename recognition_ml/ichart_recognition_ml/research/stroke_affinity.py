"""Research-only, label-free stroke ownership features and partitioning.

This module does not classify characters, read expected answers, learn personal
profiles, or mutate source ink. Its logits are uncalibrated research scores.
The contract is separate from the existing chord visual-feature schema.
"""

from __future__ import annotations

import math
from bisect import bisect_left
from dataclasses import dataclass
from itertools import combinations
from numbers import Integral, Real
from typing import Sequence

import numpy as np

try:
    import torch
    from torch import nn
except ImportError:  # Geometry research remains usable without training tools.
    torch = None
    nn = None

from ..features import InkBounds, InkPoint, InkStroke

FEATURE_SCHEMA = "stroke-affinity-context-v1"
FEATURE_COUNT = 202
SAMPLE_COUNT = 32
MAXIMUM_STROKES = 64
MAXIMUM_POINTS = 8_192
RADIAL_UPPER_FRACTIONS = (1 / 16, 1 / 8, 1 / 4, 1 / 2, 1.0)
ANGULAR_BINS = 12


def _number(value: object) -> float:
    if isinstance(value, bool) or not isinstance(value, Real):
        raise ValueError("Expected a finite real number")
    try:
        result = float(value)
    except (OverflowError, TypeError, ValueError) as exc:
        raise ValueError("Affinity value cannot be represented finitely") from exc
    if not math.isfinite(result):
        raise ValueError("Nonfinite affinity input")
    return result


def _index(value: object, count: int) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral) or not 0 <= value < count:
        raise ValueError("Invalid source stroke index")
    return int(value)


def validate_strokes(strokes: Sequence[InkStroke]) -> tuple[InkStroke, ...]:
    """Validate and freeze the container, retaining the exact source objects."""
    try:
        source = tuple(strokes)
    except TypeError as exc:
        raise ValueError("Expected source strokes") from exc
    if not 1 <= len(source) <= MAXIMUM_STROKES:
        raise ValueError("Expected one to 64 source strokes")
    point_count = 0
    for stroke in source:
        if not isinstance(stroke, InkStroke) or not isinstance(stroke.points, tuple) or not stroke.points:
            raise ValueError("Expected a nonempty immutable source stroke")
        point_count += len(stroke.points)
        if point_count > MAXIMUM_POINTS:
            raise ValueError("Source exceeds the 8192-point affinity limit")
        for point in stroke.points:
            if not isinstance(point, InkPoint):
                raise ValueError("Expected an immutable source point")
            _number(point.x)
            _number(point.y)
            if point.time_offset is not None:
                _number(point.time_offset)
        if stroke.creation_time_offset is not None:
            _number(stroke.creation_time_offset)
        if stroke.bounds is not None:
            if not isinstance(stroke.bounds, InkBounds):
                raise ValueError("Expected immutable source bounds")
            bounds = tuple(_number(v) for v in (stroke.bounds.min_x, stroke.bounds.min_y,
                                                stroke.bounds.max_x, stroke.bounds.max_y))
            if bounds[0] > bounds[2] or bounds[1] > bounds[3]:
                raise ValueError("Invalid source bounds")
    return source


def validate_partition(count: int, groups: Sequence[Sequence[int]]) -> tuple[tuple[int, ...], ...]:
    """Return a canonical complete partition or reject; never repair coverage."""
    if isinstance(count, bool) or not isinstance(count, Integral) or not 1 <= count <= MAXIMUM_STROKES:
        raise ValueError("Invalid source stroke count")
    try:
        frozen = tuple(tuple(_index(i, count) for i in group) for group in groups)
    except TypeError as exc:
        raise ValueError("Expected source index groups") from exc
    if not frozen or any(not group for group in frozen):
        raise ValueError("Empty source index group")
    if sorted(i for group in frozen for i in group) != list(range(count)):
        raise ValueError("Source groups must cover every index exactly once")
    return tuple(sorted((tuple(sorted(group)) for group in frozen), key=lambda group: group[0]))


def reconstruct_groups(strokes: Sequence[InkStroke], groups: Sequence[Sequence[int]]) -> tuple[tuple[InkStroke, ...], ...]:
    """Reconstruct classifier inputs from original objects, not feature samples."""
    source = validate_strokes(strokes)
    partition = validate_partition(len(source), groups)
    return tuple(tuple(source[i] for i in group) for group in partition)


@dataclass(frozen=True)
class _DerivedStroke:
    points: tuple[tuple[float, float], ...]
    samples: tuple[tuple[float, float], ...]
    bounds: tuple[float, float, float, float]
    arc: float
    centroid: tuple[float, float]

    @property
    def center(self) -> tuple[float, float]:
        return ((self.bounds[0] + self.bounds[2]) / 2, (self.bounds[1] + self.bounds[3]) / 2)


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def _derive(points: tuple[tuple[float, float], ...]) -> _DerivedStroke:
    lengths = tuple(_distance(a, b) for a, b in zip(points, points[1:]))
    arc = math.fsum(lengths)
    if arc == 0:
        samples = (points[0],) * SAMPLE_COUNT
    else:
        sampled = [points[0]]
        segment = 0
        consumed = 0.0
        for position in range(1, SAMPLE_COUNT - 1):
            desired = arc * position / (SAMPLE_COUNT - 1)
            while segment < len(lengths) - 1 and consumed + lengths[segment] < desired:
                consumed += lengths[segment]
                segment += 1
            while lengths[segment] == 0 and segment < len(lengths) - 1:
                segment += 1
            fraction = min(1.0, max(0.0, (desired - consumed) / lengths[segment]))
            start, end = points[segment], points[segment + 1]
            sampled.append((start[0] + (end[0] - start[0]) * fraction,
                            start[1] + (end[1] - start[1]) * fraction))
        sampled.append(points[-1])
        samples = tuple(sampled)
    return _DerivedStroke(points, samples,
        (min(p[0] for p in points), min(p[1] for p in points),
         max(p[0] for p in points), max(p[1] for p in points)), arc,
        (math.fsum(p[0] for p in samples) / SAMPLE_COUNT,
         math.fsum(p[1] for p in samples) / SAMPLE_COUNT))


def _histogram(center: tuple[float, float], context: tuple[_DerivedStroke, ...]) -> tuple[float, ...]:
    points = tuple(point for stroke in context for point in stroke.samples)
    offsets = tuple((x - center[0], y - center[1]) for x, y in points)
    distances = tuple(math.hypot(x, y) for x, y in offsets)
    radius = max(distances)
    counts = [0] * (len(RADIAL_UPPER_FRACTIONS) * ANGULAR_BINS)
    for (x, y), distance in zip(offsets, distances):
        if distance == 0 or radius == 0:
            radial, angular = 0, 0
        else:
            radial = min(4, bisect_left(RADIAL_UPPER_FRACTIONS, distance / radius))
            angle = math.atan2(y, x) % math.tau
            angular = min(ANGULAR_BINS - 1, int(angle / math.tau * ANGULAR_BINS))
        counts[radial * ANGULAR_BINS + angular] += 1
    return tuple(count / len(points) for count in counts)


class _Preparation:
    """Private immutable geometry plus memoized derived-only measurements."""

    def __init__(self, strokes: Sequence[InkStroke]):
        self.source = validate_strokes(strokes)
        points = tuple((float(p.x), float(p.y)) for stroke in self.source for p in stroke.points)
        left, top = min(p[0] for p in points), min(p[1] for p in points)
        width, height = max(p[0] for p in points) - left, max(p[1] for p in points) - top
        scale = max(width, height)
        if not math.isfinite(scale):
            raise ValueError("Nonfinite target extent")
        if scale == 0:
            scale = 1.0
        self.width, self.height = width / scale, height / scale
        self.derived = tuple(_derive(tuple(((float(p.x) - left) / scale, (float(p.y) - top) / scale)
                                          for p in stroke.points)) for stroke in self.source)
        self.samples = tuple(np.asarray(stroke.samples, dtype=np.float64) for stroke in self.derived)
        self.distances: dict[tuple[int, int], float] = {}
        self.global_histograms: dict[int, tuple[float, ...]] = {}

    def minimum_distance(self, i: int, j: int) -> float:
        key = tuple(sorted((i, j)))
        if key not in self.distances:
            delta = self.samples[i][:, None, :] - self.samples[j][None, :, :]
            self.distances[key] = float(np.hypot(delta[:, :, 0], delta[:, :, 1]).min())
        return self.distances[key]

    def features(self, i: int, j: int) -> np.ndarray:
        count = len(self.source)
        i, j = _index(i, count), _index(j, count)
        if i == j:
            raise ValueError("Affinity requires two distinct source strokes")
        a, b = self.derived[i], self.derived[j]
        aw, ah = a.bounds[2] - a.bounds[0], a.bounds[3] - a.bounds[1]
        bw, bh = b.bounds[2] - b.bounds[0], b.bounds[3] - b.bounds[1]
        a_chord, b_chord = _distance(a.points[0], a.points[-1]), _distance(b.points[0], b.points[-1])
        if a_chord == 0 or b_chord == 0:
            cosine = 0.0
        else:
            ad = tuple((a.points[-1][k] - a.points[0][k]) / a_chord for k in (0, 1))
            bd = tuple((b.points[-1][k] - b.points[0][k]) / b_chord for k in (0, 1))
            cosine = min(1.0, max(-1.0, math.fsum(x * y for x, y in zip(ad, bd))))
        geometry = (
            aw, ah, a.arc, bw, bh, b.arc,
            b.centroid[0] - a.centroid[0], b.centroid[1] - a.centroid[1],
            _distance(a.points[0], b.points[0]), _distance(a.points[0], b.points[-1]),
            _distance(a.points[-1], b.points[0]), _distance(a.points[-1], b.points[-1]),
            _distance(a.centroid, b.centroid), self.minimum_distance(i, j),
            max(0.0, a.bounds[0] - b.bounds[2], b.bounds[0] - a.bounds[2]),
            max(0.0, a.bounds[1] - b.bounds[3], b.bounds[1] - a.bounds[3]),
            max(0.0, min(a.bounds[2], b.bounds[2]) - max(a.bounds[0], b.bounds[0])),
            max(0.0, min(a.bounds[3], b.bounds[3]) - max(a.bounds[1], b.bounds[1])),
            cosine, a.arc / (a.arc + a_chord + 1e-6), b.arc / (b.arc + b_chord + 1e-6),
            self.width / (self.width + self.height) if self.width + self.height > 0 else 0.0)
        # Original point-derived normalized content breaks equal-distance ties.
        # Equal content produces equal histogram mass regardless of source index.
        remaining = sorted((k for k in range(count) if k not in (i, j)),
            key=lambda k: (min(self.minimum_distance(i, k), self.minimum_distance(j, k)),
                           self.derived[k].points))
        pair = (a, b)
        local = pair + tuple(self.derived[k] for k in remaining[:3])
        if i not in self.global_histograms:
            self.global_histograms[i] = _histogram(a.center, self.derived)
        result = np.asarray(geometry + _histogram(a.center, pair) + _histogram(a.center, local)
                            + self.global_histograms[i], dtype=np.float32)
        if result.shape != (FEATURE_COUNT,) or not np.isfinite(result).all():
            raise ValueError("Invalid derived affinity features")
        return result


def affinity_features(strokes: Sequence[InkStroke], i: int, j: int) -> np.ndarray:
    return _Preparation(strokes).features(i, j)


def all_pair_features(strokes: Sequence[InkStroke]) -> tuple[tuple[tuple[int, int], ...], np.ndarray, np.ndarray]:
    prepared = _Preparation(strokes)
    edges = tuple(combinations(range(len(prepared.source)), 2))
    if not edges:
        return edges, np.empty((0, FEATURE_COUNT), dtype=np.float32), np.empty((0, FEATURE_COUNT), dtype=np.float32)
    return (edges, np.stack([prepared.features(i, j) for i, j in edges]),
            np.stack([prepared.features(j, i) for i, j in edges]))


class StrokeAffinityModel(nn.Module if nn is not None else object):
    """Tiny learned head; no character classifier or calibrated trust output."""

    def __init__(self):
        if nn is None:
            raise RuntimeError("Optional PyTorch training dependencies required")
        super().__init__()
        self.network = nn.Sequential(nn.Linear(FEATURE_COUNT, 64), nn.ReLU(),
                                     nn.Linear(64, 32), nn.ReLU(), nn.Linear(32, 1))

    def forward(self, features):
        if (not isinstance(features, torch.Tensor) or features.ndim != 2
                or features.shape[1] != FEATURE_COUNT or features.dtype != torch.float32
                or not bool(torch.isfinite(features).all())):
            raise ValueError("Expected finite float32 affinity features [N,202]")
        result = self.network(features).squeeze(-1)
        if not bool(torch.isfinite(result).all()):
            raise ValueError("Nonfinite affinity logits")
        return result

    def symmetric_logits(self, ab, ba):
        if (not isinstance(ab, torch.Tensor) or not isinstance(ba, torch.Tensor)
                or ab.shape != ba.shape):
            raise ValueError("Ordered affinity directions must have matching shapes")
        result = (self(ab) + self(ba)) * 0.5
        if not bool(torch.isfinite(result).all()):
            raise ValueError("Nonfinite symmetric affinity logits")
        return result


def partition_from_logits(count: int, edges: Sequence[tuple[int, int]],
                          logits: Sequence[float]) -> tuple[tuple[int, ...], ...]:
    """Greedy within-group affinity maximization; no expected symbol count."""
    if isinstance(count, bool) or not isinstance(count, Integral) or not 1 <= count <= MAXIMUM_STROKES:
        raise ValueError("Invalid source stroke count")
    try:
        frozen_edges, frozen_logits = tuple(edges), tuple(logits)
    except TypeError as exc:
        raise ValueError("Expected a complete pair-score table") from exc
    expected = count * (count - 1) // 2
    if len(frozen_edges) != expected or len(frozen_logits) != expected:
        raise ValueError("Missing or surplus source edges/logits")
    scores = {}
    for edge, value in zip(frozen_edges, frozen_logits):
        try:
            i, j = edge
        except (TypeError, ValueError) as exc:
            raise ValueError("Expected two source indexes per edge") from exc
        i, j = _index(i, count), _index(j, count)
        key = tuple(sorted((i, j)))
        if i == j or key in scores:
            raise ValueError("Self or duplicate source edge")
        scores[key] = _number(value)
    if set(scores) != set(combinations(range(count), 2)):
        raise ValueError("Incomplete source edge coverage")
    groups = [(i,) for i in range(count)]
    while True:
        best = None
        best_score = 0.0
        for left, right in combinations(range(len(groups)), 2):
            try:
                score = math.fsum(scores[tuple(sorted((i, j)))] for i in groups[left] for j in groups[right])
            except OverflowError as exc:
                raise ValueError("Nonfinite merge objective") from exc
            if not math.isfinite(score):
                raise ValueError("Nonfinite merge objective")
            candidate = (groups[left], groups[right])
            if score > best_score or (score > 0 and score == best_score and (best is None or candidate < best)):
                best, best_score = candidate, score
        if best is None:
            break
        groups = [group for group in groups if group not in best] + [tuple(sorted(best[0] + best[1]))]
        groups.sort(key=lambda group: group[0])
    return validate_partition(count, groups)
