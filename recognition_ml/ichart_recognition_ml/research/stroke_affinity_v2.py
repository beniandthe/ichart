"""Research-only pair-local ownership features; v1 remains immutable.

Pair geometry and its histogram are derived independently from the original
two strokes. Neighborhood/global histograms retain v1's surrounding context.
This does not classify characters, confer trust, or rewrite source ink.
"""

from __future__ import annotations

from itertools import combinations
from typing import Sequence

import numpy as np

from ..features import InkStroke
from . import stroke_affinity as v1

FEATURE_SCHEMA = "stroke-affinity-pair-local-v2"
FEATURE_COUNT = v1.FEATURE_COUNT
SAMPLE_COUNT = v1.SAMPLE_COUNT
MAXIMUM_STROKES = v1.MAXIMUM_STROKES
MAXIMUM_POINTS = v1.MAXIMUM_POINTS
RADIAL_UPPER_FRACTIONS = v1.RADIAL_UPPER_FRACTIONS
ANGULAR_BINS = v1.ANGULAR_BINS

# Frozen dependencies are reused, never patched or copied into a new learner.
StrokeAffinityModel = v1.StrokeAffinityModel
partition_from_logits = v1.partition_from_logits
validate_strokes = v1.validate_strokes
validate_partition = v1.validate_partition
reconstruct_groups = v1.reconstruct_groups


class _Preparation:
    """One full-context preparation plus short-lived independent pair frames."""

    def __init__(self, strokes: Sequence[InkStroke]):
        self.context = v1._Preparation(strokes)
        self.source = self.context.source

    def _features(self, i: int, j: int, pair: v1._Preparation, a: int, b: int) -> np.ndarray:
        # Pair resampling, scale, centroid and aspect all come from A+B alone.
        # Re-scaling already globally sampled points would break this guarantee.
        local_pair = pair.features(a, b)
        surrounding = self.context.features(i, j)
        result = np.concatenate((local_pair[:82], surrounding[82:]))
        if result.shape != (FEATURE_COUNT,) or result.dtype != np.float32 or not np.isfinite(result).all():
            raise ValueError("Invalid derived pair-local affinity features")
        return result

    def features(self, i: int, j: int) -> np.ndarray:
        i, j = v1._index(i, len(self.source)), v1._index(j, len(self.source))
        if i == j:
            raise ValueError("Affinity requires two distinct source strokes")
        pair = v1._Preparation((self.source[i], self.source[j]))
        return self._features(i, j, pair, 0, 1)


def affinity_features(strokes: Sequence[InkStroke], i: int, j: int) -> np.ndarray:
    return _Preparation(strokes).features(i, j)


def all_pair_features(strokes: Sequence[InkStroke]) -> tuple[tuple[tuple[int, int], ...], np.ndarray, np.ndarray]:
    prepared = _Preparation(strokes)
    edges = tuple(combinations(range(len(prepared.source)), 2))
    if not edges:
        return edges, np.empty((0, FEATURE_COUNT), dtype=np.float32), np.empty((0, FEATURE_COUNT), dtype=np.float32)
    ab, ba = [], []
    for i, j in edges:
        # Computing both directions here shares one pair frame, without retaining
        # O(n^2) copies of original point-derived geometry for the entire target.
        pair = v1._Preparation((prepared.source[i], prepared.source[j]))
        ab.append(prepared._features(i, j, pair, 0, 1))
        ba.append(prepared._features(j, i, pair, 1, 0))
    return edges, np.stack(ab), np.stack(ba)
