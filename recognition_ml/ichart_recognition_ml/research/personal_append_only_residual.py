"""Research-only class-frozen append updates for the existing residual head.

This module does not choose chord-domain labels, acceptance thresholds, or query
answers.  It preserves an exact fitted-array/ID prefix and only replaces
correction columns whose labels occur in newly appended support rows.  Caller-
provided IDs and encoded arrays are not proof of original lesson strokes or app
profile provenance; an evaluator must bind those source bytes separately.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence

import numpy as np

from .personal_residual import ResidualHead, validate_features, validate_scores


VERSION = "personal-append-only-class-frozen-residual-v1"
REGULARIZATION = 0.1


def _float64(values: object) -> np.ndarray:
    return np.ascontiguousarray(np.asarray(values, dtype=np.float64))


def _freeze(values: np.ndarray) -> np.ndarray:
    canonical = _float64(values)
    return np.frombuffer(canonical.tobytes(order="C"), dtype=np.float64).reshape(
        canonical.shape
    )


def _same_bytes(left: np.ndarray, right: np.ndarray) -> bool:
    left = _float64(left)
    right = _float64(right)
    return left.shape == right.shape and left.tobytes(order="C") == right.tobytes(order="C")


def _source_ids(values: Sequence[str], count: int) -> tuple[str, ...]:
    if isinstance(values, (str, bytes)):
        raise ValueError("Support source IDs must be a sequence")
    result = tuple(values)
    if (
        len(result) != count
        or len(set(result)) != len(result)
        or any(not isinstance(value, str) or not value for value in result)
    ):
        raise ValueError("Support source IDs must be nonempty and unique")
    return result


def _encoder_identity(value: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError("Encoder identity is required")
    return value


@dataclass(frozen=True, slots=True)
class ClassFrozenResidualSnapshot:
    version: str
    encoder_identity: str
    encoder_vocabulary: tuple[str, ...]
    regularization: float
    vocabulary: tuple[str, ...]
    source_ids: tuple[str, ...]
    labels: tuple[str, ...]
    support_features: np.ndarray
    support_base_scores: np.ndarray
    weights: np.ndarray
    last_refitted_labels: tuple[str, ...]

    @property
    def lesson_count(self) -> int:
        return len(self.labels)

    def adjusted_scores(self, feature: object, base_scores: object) -> np.ndarray:
        feature_array = _float64(feature)
        score_array = _float64(base_scores)
        if feature_array.shape != (self.weights.shape[0],):
            raise ValueError("Wrong query feature shape")
        validate_features(feature_array[None, :])
        if score_array.shape != (len(self.vocabulary),):
            raise ValueError("Wrong query score shape")
        encoder_width = len(self.encoder_vocabulary)
        if np.any(score_array[encoder_width:] != 0):
            raise ValueError("Query scores require zero non-encoder padding")
        validate_scores(score_array[None, :], 1, len(self.vocabulary))
        # Match the Swift head's per-column, left-associated feature-order dot.
        # Keeping the column outside the reduction makes untouched score bits
        # independent of output-vocabulary growth.
        correction = np.empty(len(self.vocabulary), dtype=np.float64)
        for column in range(len(self.vocabulary)):
            total = 0.0
            for feature_index in range(feature_array.shape[0]):
                total += feature_array[feature_index] * self.weights[feature_index, column]
            correction[column] = total
        adjusted = score_array + correction
        if not np.isfinite(adjusted).all():
            raise ValueError("Nonfinite adjusted ranks")
        return _freeze(adjusted)

    def rank(self, feature: object, base_scores: object) -> list[dict[str, object]]:
        adjusted = self.adjusted_scores(feature, base_scores)
        return sorted(
            (
                {"label": label, "score": float(score)}
                for label, score in zip(self.vocabulary, adjusted, strict=True)
            ),
            key=lambda row: (-row["score"], row["label"]),
        )


def _snapshot(
    *,
    encoder_identity: str,
    encoder_vocabulary: tuple[str, ...],
    vocabulary: tuple[str, ...],
    source_ids: tuple[str, ...],
    labels: tuple[str, ...],
    features: np.ndarray,
    base_scores: np.ndarray,
    weights: np.ndarray,
    last_refitted_labels: tuple[str, ...],
) -> ClassFrozenResidualSnapshot:
    return ClassFrozenResidualSnapshot(
        version=VERSION,
        encoder_identity=encoder_identity,
        encoder_vocabulary=encoder_vocabulary,
        regularization=REGULARIZATION,
        vocabulary=vocabulary,
        source_ids=source_ids,
        labels=labels,
        support_features=_freeze(features),
        support_base_scores=_freeze(base_scores),
        weights=_freeze(weights),
        last_refitted_labels=last_refitted_labels,
    )


def fit_reference(
    features: object,
    base_scores: object,
    labels: Sequence[str],
    source_ids: Sequence[str],
    vocabulary: Sequence[str],
    encoder_identity: str,
    encoder_vocabulary: Sequence[str] | None = None,
) -> ClassFrozenResidualSnapshot:
    """Fit the unchanged residual head and freeze its exact support snapshot."""

    features_array = _float64(features)
    scores_array = _float64(base_scores)
    label_tuple = tuple(labels)
    vocabulary_tuple = tuple(vocabulary)
    encoder_vocabulary_tuple = (
        vocabulary_tuple if encoder_vocabulary is None else tuple(encoder_vocabulary)
    )
    identity = _encoder_identity(encoder_identity)
    ids = _source_ids(source_ids, len(label_tuple))
    if (
        isinstance(encoder_vocabulary, (str, bytes))
        or scores_array.ndim != 2
        or not encoder_vocabulary_tuple
        or len(set(encoder_vocabulary_tuple)) != len(encoder_vocabulary_tuple)
        or vocabulary_tuple[:len(encoder_vocabulary_tuple)] != encoder_vocabulary_tuple
    ):
        raise ValueError("Encoder vocabulary must be an exact output-vocabulary prefix")
    if np.any(scores_array[:, len(encoder_vocabulary_tuple):] != 0):
        raise ValueError("Support scores require zero non-encoder padding")
    head = ResidualHead.fit(
        features_array,
        scores_array,
        label_tuple,
        vocabulary_tuple,
        regularization=REGULARIZATION,
    )
    return _snapshot(
        encoder_identity=identity,
        encoder_vocabulary=encoder_vocabulary_tuple,
        vocabulary=vocabulary_tuple,
        source_ids=ids,
        labels=label_tuple,
        features=features_array,
        base_scores=scores_array,
        weights=head.weights,
        last_refitted_labels=tuple(vocabulary_tuple),
    )


def append_only_refit(
    reference: ClassFrozenResidualSnapshot,
    *,
    features: object,
    base_scores: object,
    labels: Sequence[str],
    source_ids: Sequence[str],
    vocabulary: Sequence[str],
    encoder_identity: str,
) -> ClassFrozenResidualSnapshot:
    """Validate a complete appended history and replace only its taught columns."""

    if not isinstance(reference, ClassFrozenResidualSnapshot) or reference.version != VERSION:
        raise ValueError("Invalid append-only reference")
    if reference.regularization != REGULARIZATION or not math.isfinite(reference.regularization):
        raise ValueError("Reference regularization changed")
    if _encoder_identity(encoder_identity) != reference.encoder_identity:
        raise ValueError("Encoder identity changed")

    features_array = _float64(features)
    scores_array = _float64(base_scores)
    label_tuple = tuple(labels)
    vocabulary_tuple = tuple(vocabulary)
    ids = _source_ids(source_ids, len(label_tuple))
    old_count = reference.lesson_count
    old_width = len(reference.vocabulary)
    encoder_width = len(reference.encoder_vocabulary)
    if len(label_tuple) < old_count:
        raise ValueError("Support history was deleted")
    if vocabulary_tuple[:old_width] != reference.vocabulary:
        raise ValueError("Vocabulary must retain the exact reference prefix")
    if vocabulary_tuple[:encoder_width] != reference.encoder_vocabulary:
        raise ValueError("Encoder vocabulary changed")
    new_vocabulary = vocabulary_tuple[old_width:]
    if new_vocabulary != tuple(sorted(new_vocabulary)) or len(set(vocabulary_tuple)) != len(vocabulary_tuple):
        raise ValueError("New vocabulary must be a unique sorted suffix")

    if (
        features_array.ndim != 2
        or features_array.shape[0] != len(label_tuple)
        or not 0 <= len(label_tuple) <= 192
        or scores_array.shape != (len(label_tuple), len(vocabulary_tuple))
        or not 2 <= len(vocabulary_tuple) <= 512
        or any(not isinstance(label, str) or not label for label in vocabulary_tuple)
        or any(label not in vocabulary_tuple for label in label_tuple)
    ):
        raise ValueError("Malformed combined support")
    validate_features(features_array)
    if features_array.shape[1:] != reference.support_features.shape[1:]:
        raise ValueError("Feature schema changed")
    if ids[:old_count] != reference.source_ids or label_tuple[:old_count] != reference.labels:
        raise ValueError("Support identity or label prefix changed")
    if not _same_bytes(features_array[:old_count], reference.support_features):
        raise ValueError("Support feature prefix changed")
    if np.any(scores_array[:, encoder_width:] != 0):
        raise ValueError("Support scores require zero vocabulary padding")
    if not _same_bytes(
        scores_array[:old_count, :old_width], reference.support_base_scores
    ):
        raise ValueError("Support score prefix changed")
    validate_scores(scores_array, len(label_tuple), len(vocabulary_tuple))

    appended_labels = label_tuple[old_count:]
    if not appended_labels:
        if vocabulary_tuple != reference.vocabulary:
            raise ValueError("Vocabulary cannot change without appended support")
        return reference
    changed_set = set(appended_labels)
    if any(label not in changed_set for label in new_vocabulary):
        raise ValueError("Every new vocabulary label requires appended support")
    changed_labels = tuple(label for label in vocabulary_tuple if label in changed_set)

    # The unchanged fitter performs the only solve, after the append-only
    # history and padding have been accepted.
    full_refit = ResidualHead.fit(
        features_array,
        scores_array,
        label_tuple,
        vocabulary_tuple,
        regularization=REGULARIZATION,
    )

    weights = np.zeros_like(full_refit.weights)
    weights[:, :old_width] = reference.weights
    for label in changed_labels:
        column = vocabulary_tuple.index(label)
        weights[:, column] = full_refit.weights[:, column]
    if not np.isfinite(weights).all():
        raise ValueError("Nonfinite class-frozen correction")

    return _snapshot(
        encoder_identity=reference.encoder_identity,
        encoder_vocabulary=reference.encoder_vocabulary,
        vocabulary=vocabulary_tuple,
        source_ids=ids,
        labels=label_tuple,
        features=features_array,
        base_scores=scores_array,
        weights=weights,
        last_refitted_labels=changed_labels,
    )
