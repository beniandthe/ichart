"""Decision-neutral comparison baselines for writer-independent evaluation.

Nothing in this module calibrates, authorizes trust, or reads retained fixture
archives. Classical reference templates are accepted only from development
writers; calibration and sealed-evaluation samples can be query inputs during
their respective evaluations but are never learned from or retained.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import ClassVar, Dict, Mapping, Optional, Sequence, Tuple

from .chord_notation import CanonicalChordLabelError, require_canonical_chord_label
from .dataset import PipelineRole
from .errors import ContractError, OperationRefusedError
from .features import TRAJECTORY_CHANNEL_COUNT, TRAJECTORY_SAMPLE_COUNT, TrajectoryChannel
from .models.output_contract import (
    HEAD_NAMES,
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
    FactorLogits,
    factorize_canonical_label,
)
from .schema import FEATURE_SCHEMA


DTW_BASELINE_CONTRACT_VERSION = "multi-writer-dtw-baseline-v1"
EXTERNAL_LEGACY_ADAPTER_VERSION = "external-legacy-factor-adapter-v1"
_HASH = re.compile(r"^[0-9a-f]{64}$")


def factor_logits_for_external_prediction(
    canonical_label: Optional[str],
    logit_magnitude: float = 8.0,
) -> FactorLogits:
    """Represent one externally produced decision in the common head contract.

    The fixed logits encode only a ranking. They are not probabilities,
    calibrated support, or evidence that the source recognizer is eligible for
    writer-independent acceptance.
    """

    if (
        isinstance(logit_magnitude, bool)
        or not isinstance(logit_magnitude, (int, float))
        or not math.isfinite(float(logit_magnitude))
        or float(logit_magnitude) <= 0.0
    ):
        raise ContractError(
            "invalid_adapter_logit_magnitude",
            "logit_magnitude",
            "must be finite and greater than zero",
        )
    magnitude = float(logit_magnitude)
    values: Dict[str, Tuple[float, ...]] = {
        head.name: tuple(0.0 for _ in head.labels) for head in OUTPUT_HEADS
    }
    validity_labels = next(head.labels for head in OUTPUT_HEADS if head.name == "validity")

    if canonical_label is None:
        values["validity"] = tuple(
            magnitude if label == "no_read" else -magnitude
            for label in validity_labels
        )
        return FactorLogits.from_mapping(values)

    try:
        canonical = require_canonical_chord_label(canonical_label)
    except CanonicalChordLabelError as error:
        raise ContractError(
            "invalid_external_canonical_label",
            "canonical_label",
            str(error),
        )
    target = factorize_canonical_label(canonical)
    for head in OUTPUT_HEADS:
        if not target.active[head.name]:
            continue
        expected = target.values[head.name]
        if head.is_independent_bernoulli:
            assert isinstance(expected, tuple)
            values[head.name] = tuple(
                magnitude if selected else -magnitude for selected in expected
            )
        else:
            assert isinstance(expected, int)
            values[head.name] = tuple(
                magnitude if index == expected else -magnitude
                for index in range(len(head.labels))
            )
    return FactorLogits.from_mapping(values)


def factor_logits_from_batched_raw_heads(
    output: Mapping[str, object],
    batch_index: int = 0,
) -> FactorLogits:
    """Convert one ablation/dual-view output row into ``FactorLogits``."""

    if not isinstance(output, Mapping):
        raise ContractError(
            "invalid_model_output", "model_output", "expected a mapping of raw heads"
        )
    if isinstance(batch_index, bool) or not isinstance(batch_index, int) or batch_index < 0:
        raise ContractError(
            "invalid_batch_index", "batch_index", "must be a nonnegative integer"
        )
    missing = sorted(set(HEAD_NAMES).difference(output.keys()))
    unknown = sorted(set(output.keys()).difference(HEAD_NAMES))
    if missing:
        raise ContractError("missing_output_head", "model_output", ", ".join(missing))
    if unknown:
        raise ContractError("unknown_output_head", "model_output", ", ".join(unknown))

    row_values = {}
    for head in OUTPUT_HEADS:
        raw = output[head.name]
        if hasattr(raw, "detach"):
            raw = raw.detach().cpu()
        try:
            row = raw[batch_index]  # type: ignore[index]
        except (IndexError, KeyError, TypeError) as error:
            raise ContractError(
                "missing_output_batch_row",
                head.name,
                f"cannot read batch row {batch_index}: {error}",
            )
        if hasattr(row, "tolist"):
            row = row.tolist()
        row_values[head.name] = row
    return FactorLogits.from_mapping(row_values)


@dataclass(frozen=True)
class ExternalLegacyPrediction:
    sample_id: str
    canonical_label: Optional[str]


@dataclass(frozen=True)
class ExternalLegacyRuleAdapter:
    """Adapter for supplied legacy outputs, never for retained fixture ink."""

    contract_version: str = EXTERNAL_LEGACY_ADAPTER_VERSION
    logit_magnitude: float = 8.0
    is_writer_independent_claim_eligible: ClassVar[bool] = False
    is_trust_eligible: ClassVar[bool] = False

    def adapt(
        self,
        predictions: Sequence[ExternalLegacyPrediction],
    ) -> Mapping[str, FactorLogits]:
        if self.contract_version != EXTERNAL_LEGACY_ADAPTER_VERSION:
            raise ContractError(
                "legacy_adapter_version_mismatch",
                "contract_version",
                f"expected {EXTERNAL_LEGACY_ADAPTER_VERSION}, got {self.contract_version}",
            )
        result: Dict[str, FactorLogits] = {}
        for index, prediction in enumerate(predictions):
            if not isinstance(prediction, ExternalLegacyPrediction):
                raise ContractError(
                    "invalid_external_legacy_prediction",
                    f"predictions[{index}]",
                    "expected ExternalLegacyPrediction",
                )
            if not isinstance(prediction.sample_id, str) or not prediction.sample_id:
                raise ContractError(
                    "invalid_external_sample_id",
                    f"predictions[{index}].sample_id",
                    "must be a non-empty string",
                )
            if prediction.sample_id in result:
                raise ContractError(
                    "duplicate_external_sample_id",
                    f"predictions[{index}].sample_id",
                    prediction.sample_id,
                )
            result[prediction.sample_id] = factor_logits_for_external_prediction(
                prediction.canonical_label,
                self.logit_magnitude,
            )
        if not result:
            raise OperationRefusedError(
                "external_legacy_predictions_required",
                "predictions",
                "supply externally generated legacy predictions; retained fixtures are not loaded",
            )
        return result


@dataclass(frozen=True)
class DTWBaselineConfig:
    """Frozen classical comparison configuration, selected before evaluation."""

    contract_version: str = DTW_BASELINE_CONTRACT_VERSION
    channel_indices: Tuple[int, ...] = (
        int(TrajectoryChannel.X),
        int(TrajectoryChannel.Y),
        int(TrajectoryChannel.DELTA_X),
        int(TrajectoryChannel.DELTA_Y),
        int(TrajectoryChannel.ARC_STEP),
        int(TrajectoryChannel.STROKE_START),
        int(TrajectoryChannel.STROKE_END),
    )
    minimum_writers_per_label: int = 2
    writer_neighbors: int = 2
    logit_magnitude: float = 8.0

    def validate(self) -> None:
        if self.contract_version != DTW_BASELINE_CONTRACT_VERSION:
            raise ContractError(
                "dtw_contract_version_mismatch",
                "contract_version",
                f"expected {DTW_BASELINE_CONTRACT_VERSION}, got {self.contract_version}",
            )
        if self.channel_indices != DTWBaselineConfig().channel_indices:
            raise ContractError(
                "nonfrozen_dtw_channels",
                "channel_indices",
                "v1 comparison channels are frozen and cannot be tuned per evaluation",
            )
        if self.minimum_writers_per_label != 2 or self.writer_neighbors != 2:
            raise ContractError(
                "nonfrozen_dtw_writer_policy",
                "minimum_writers_per_label",
                "v1 requires exactly two development writers per label decision",
            )
        if self.logit_magnitude != 8.0:
            raise ContractError(
                "nonfrozen_dtw_logit_magnitude",
                "logit_magnitude",
                "v1 uses a fixed ranking-only magnitude of 8.0",
            )


@dataclass(frozen=True)
class DevelopmentTrajectoryTemplate:
    sample_id: str
    writer_id_hash: str
    split: str
    canonical_label: str
    trajectory_values: Tuple[float, ...]

    def __init__(
        self,
        sample_id: str,
        writer_id_hash: str,
        split: str,
        canonical_label: str,
        trajectory_values: Sequence[float],
    ) -> None:
        if not isinstance(sample_id, str) or not sample_id:
            raise ContractError("invalid_template_sample_id", "sample_id", "must be non-empty")
        if not isinstance(writer_id_hash, str) or not _HASH.fullmatch(writer_id_hash):
            raise ContractError(
                "invalid_template_writer_hash",
                "writer_id_hash",
                "must be 64 lowercase hexadecimal characters",
            )
        if split != PipelineRole.TRAINING.split:
            raise OperationRefusedError(
                "nondevelopment_dtw_template_refused",
                "split",
                "DTW references may come only from development writers",
            )
        try:
            canonical = require_canonical_chord_label(canonical_label)
        except CanonicalChordLabelError as error:
            raise ContractError(
                "invalid_template_canonical_label", "canonical_label", str(error)
            )
        values = _validate_trajectory_values(trajectory_values, "trajectory_values")
        object.__setattr__(self, "sample_id", sample_id)
        object.__setattr__(self, "writer_id_hash", writer_id_hash)
        object.__setattr__(self, "split", split)
        object.__setattr__(self, "canonical_label", canonical)
        object.__setattr__(self, "trajectory_values", values)


@dataclass(frozen=True)
class MultiWriterDTWBaseline:
    """Development-template DTW baseline with no calibration/trust authority."""

    templates: Tuple[DevelopmentTrajectoryTemplate, ...]
    config: DTWBaselineConfig = DTWBaselineConfig()
    output_contract_version: ClassVar[str] = OUTPUT_CONTRACT_VERSION
    is_calibrated: ClassVar[bool] = False
    is_trust_eligible: ClassVar[bool] = False

    def __post_init__(self) -> None:
        self.config.validate()
        if not isinstance(self.templates, tuple):
            raise ContractError(
                "mutable_dtw_templates",
                "templates",
                "references must be frozen in a tuple; use MultiWriterDTWBaseline.fit",
            )
        if not self.templates:
            raise OperationRefusedError(
                "development_writer_templates_required",
                "templates",
                "the classical baseline is unavailable without development-writer templates",
            )
        if any(not isinstance(item, DevelopmentTrajectoryTemplate) for item in self.templates):
            raise ContractError(
                "invalid_dtw_template", "templates", "expected DevelopmentTrajectoryTemplate"
            )
        sample_ids = [item.sample_id for item in self.templates]
        if len(sample_ids) != len(set(sample_ids)):
            raise ContractError(
                "duplicate_dtw_template_sample", "templates", "sample IDs must be unique"
            )
        writers_by_label: Dict[str, set[str]] = {}
        for item in self.templates:
            if item.split != PipelineRole.TRAINING.split:
                raise OperationRefusedError(
                    "nondevelopment_dtw_template_refused",
                    "templates",
                    "DTW references may come only from development writers",
                )
            writers_by_label.setdefault(item.canonical_label, set()).add(item.writer_id_hash)
        undercovered = sorted(
            label
            for label, writers in writers_by_label.items()
            if len(writers) < self.config.minimum_writers_per_label
        )
        if undercovered:
            raise OperationRefusedError(
                "insufficient_development_writers_per_label",
                "templates",
                ", ".join(undercovered),
            )

    @classmethod
    def fit(
        cls,
        templates: Sequence[DevelopmentTrajectoryTemplate],
        config: DTWBaselineConfig = DTWBaselineConfig(),
    ) -> "MultiWriterDTWBaseline":
        """Freeze development references; never update from prediction queries."""

        frozen = tuple(templates)
        if any(not isinstance(item, DevelopmentTrajectoryTemplate) for item in frozen):
            raise ContractError(
                "invalid_dtw_template", "templates", "expected DevelopmentTrajectoryTemplate"
            )
        return cls(
            templates=tuple(
                sorted(frozen, key=lambda item: (item.canonical_label, item.writer_id_hash, item.sample_id))
            ),
            config=config,
        )

    def predict(self, trajectory_values: Sequence[float]) -> FactorLogits:
        query = _trajectory_steps(
            _validate_trajectory_values(trajectory_values, "trajectory_values"),
            self.config.channel_indices,
        )
        writer_distance_by_label: Dict[str, Dict[str, float]] = {}
        for template in self.templates:
            reference = _trajectory_steps(
                template.trajectory_values,
                self.config.channel_indices,
            )
            distance = _dtw_distance(query, reference)
            by_writer = writer_distance_by_label.setdefault(template.canonical_label, {})
            previous = by_writer.get(template.writer_id_hash)
            if previous is None or distance < previous:
                by_writer[template.writer_id_hash] = distance

        ranked = []
        for label, by_writer in writer_distance_by_label.items():
            distances = sorted(by_writer.values())
            if len(distances) < self.config.writer_neighbors:
                raise OperationRefusedError(
                    "insufficient_development_writers_per_label",
                    "templates",
                    label,
                )
            score = sum(distances[: self.config.writer_neighbors]) / self.config.writer_neighbors
            ranked.append((score, label))
        if not ranked:
            raise OperationRefusedError(
                "development_writer_templates_required", "templates", "no usable labels"
            )
        _, label = min(ranked, key=lambda item: (item[0], item[1]))
        return factor_logits_for_external_prediction(label, self.config.logit_magnitude)


def _validate_trajectory_values(values: Sequence[float], path: str) -> Tuple[float, ...]:
    if isinstance(values, (str, bytes, bytearray)):
        raise ContractError("invalid_trajectory", path, "must be a numeric sequence")
    try:
        frozen = tuple(float(value) for value in values)
    except (TypeError, ValueError):
        raise ContractError("invalid_trajectory", path, "must be numeric")
    if len(frozen) != FEATURE_SCHEMA.trajectory_value_count:
        raise ContractError(
            "trajectory_shape_mismatch",
            path,
            f"expected {FEATURE_SCHEMA.trajectory_value_count} values, got {len(frozen)}",
        )
    if any(not math.isfinite(value) for value in frozen):
        raise ContractError("nonfinite_trajectory", path, "every value must be finite")

    saw_padding = False
    valid_count = 0
    for sample_index in range(TRAJECTORY_SAMPLE_COUNT):
        offset = sample_index * TRAJECTORY_CHANNEL_COUNT
        row = frozen[offset : offset + TRAJECTORY_CHANNEL_COUNT]
        valid = row[int(TrajectoryChannel.VALID)]
        if valid not in (0.0, 1.0):
            raise ContractError(
                "invalid_trajectory_valid_mask",
                f"{path}[{sample_index}]",
                "VALID must be binary",
            )
        if valid == 0.0:
            saw_padding = True
            if any(value != 0.0 for value in row):
                raise ContractError(
                    "nonzero_trajectory_padding",
                    f"{path}[{sample_index}]",
                    "invalid rows must be all zero",
                )
        else:
            if saw_padding:
                raise ContractError(
                    "noncontiguous_trajectory_valid_mask",
                    f"{path}[{sample_index}]",
                    "valid rows must precede padding",
                )
            valid_count += 1
    if valid_count == 0:
        raise ContractError("empty_trajectory", path, "at least one valid row is required")
    return frozen


def _trajectory_steps(
    values: Tuple[float, ...], channel_indices: Tuple[int, ...]
) -> Tuple[Tuple[float, ...], ...]:
    result = []
    for sample_index in range(TRAJECTORY_SAMPLE_COUNT):
        offset = sample_index * TRAJECTORY_CHANNEL_COUNT
        row = values[offset : offset + TRAJECTORY_CHANNEL_COUNT]
        if row[int(TrajectoryChannel.VALID)] == 0.0:
            break
        result.append(tuple(row[index] for index in channel_indices))
    return tuple(result)


def _dtw_distance(
    left: Tuple[Tuple[float, ...], ...],
    right: Tuple[Tuple[float, ...], ...],
) -> float:
    """Deterministic normalized DTW with squared Euclidean local cost."""

    previous = [(math.inf, 0)] * (len(right) + 1)
    previous[0] = (0.0, 0)
    for left_step in left:
        current = [(math.inf, 0)] * (len(right) + 1)
        for right_index, right_step in enumerate(right, start=1):
            local = sum(
                (left_value - right_value) ** 2
                for left_value, right_value in zip(left_step, right_step)
            )
            predecessor = min(
                (previous[right_index], current[right_index - 1], previous[right_index - 1]),
                key=lambda item: (item[0], item[1]),
            )
            current[right_index] = (predecessor[0] + local, predecessor[1] + 1)
        previous = current
    total, path_length = previous[-1]
    if not math.isfinite(total) or path_length <= 0:
        raise ContractError("invalid_dtw_distance", "trajectory", "no finite alignment")
    return math.sqrt(total / path_length)
