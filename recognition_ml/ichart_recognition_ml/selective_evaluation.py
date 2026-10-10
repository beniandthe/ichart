"""Decision-neutral selective metrics for writer-disjoint evaluation roles."""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Mapping, Optional, Sequence

from .chord_notation import CanonicalChordLabelError, require_canonical_chord_label
from .contracts import CorpusRecord, CorpusSupervisionKind, records_digest
from .dataset import (
    PipelineRole,
    assert_prediction_sample_ids,
    select_role_records,
)
from .decode import DecodeResult, DecodedCandidate
from .errors import ContractError, OperationRefusedError


class SelectiveDisposition(Enum):
    TRUSTED = "trusted"
    REVIEW = "review"
    NO_READ = "no-read"


@dataclass(frozen=True)
class SelectivePrediction:
    """One decoded result plus a decision made by an external policy.

    This type contains no threshold.  A trusted decision must name the first
    decoded candidate so top-three membership cannot be relabeled as trust.
    """

    decode_result: DecodeResult
    disposition: SelectiveDisposition
    trusted_label: Optional[str] = None


@dataclass(frozen=True)
class SelectiveEvaluationReport:
    role: PipelineRole
    sample_count: int
    writer_count: int
    records_sha256: str
    top_one_correct_count: int
    top_three_correct_count: int
    trusted_count: int
    trusted_wrong_count: int
    review_count: int
    no_read_count: int
    notation_sample_count: int = 0
    no_read_ground_truth_count: int = 0
    correct_no_read_count: int = 0
    false_no_read_count: int = 0

    @property
    def top_one_accuracy(self) -> float:
        return (
            self.top_one_correct_count / self.notation_sample_count
            if self.notation_sample_count
            else 0.0
        )

    @property
    def top_three_accuracy(self) -> float:
        return (
            self.top_three_correct_count / self.notation_sample_count
            if self.notation_sample_count
            else 0.0
        )

    @property
    def trusted_coverage(self) -> float:
        return self.trusted_count / self.sample_count

    @property
    def review_rate(self) -> float:
        return self.review_count / self.sample_count

    @property
    def no_read_rate(self) -> float:
        return self.no_read_count / self.sample_count

    @property
    def selective_risk(self) -> Optional[float]:
        if self.trusted_count == 0:
            return None
        return self.trusted_wrong_count / self.trusted_count

    @property
    def no_read_recall(self) -> Optional[float]:
        if self.no_read_ground_truth_count == 0:
            return None
        return self.correct_no_read_count / self.no_read_ground_truth_count

    @property
    def false_no_read_rate(self) -> Optional[float]:
        if self.notation_sample_count == 0:
            return None
        return self.false_no_read_count / self.notation_sample_count


def top_k_is_correct(expected_label: str, result: DecodeResult, k: int) -> bool:
    """Return exact canonical-label correctness within the first ``k`` paths."""

    try:
        canonical = require_canonical_chord_label(expected_label)
    except CanonicalChordLabelError as error:
        raise ContractError(
            "invalid_expected_label",
            "expected_label",
            str(error),
        )
    if isinstance(k, bool) or not isinstance(k, int) or k <= 0:
        raise ContractError("invalid_top_k", "k", "must be a positive integer")
    _validate_decode_result(result)
    return canonical in tuple(candidate.canonical_label for candidate in result.candidates[:k])


def evaluate_selective_predictions(
    records: Sequence[CorpusRecord],
    predictions: Mapping[str, SelectivePrediction],
    role: PipelineRole,
) -> SelectiveEvaluationReport:
    """Evaluate calibration or sealed writers without authoring policy.

    ``records`` is the complete corpus.  Role selection therefore runs the
    existing writer-disjoint validation before any aggregate is computed.
    Development writers are deliberately ineligible for these metrics.
    """

    if role not in (PipelineRole.CALIBRATION, PipelineRole.SEALED_EVALUATION):
        role_name = role.value if isinstance(role, PipelineRole) else repr(role)
        raise OperationRefusedError(
            "unsupported_selective_evaluation_role",
            "role",
            f"expected calibration or sealed-evaluation, got {role_name}",
        )
    selected = select_role_records(records, role)
    assert_prediction_sample_ids(selected, predictions, f"{role.value}_predictions")

    top_one_correct = 0
    top_three_correct = 0
    trusted_count = 0
    trusted_wrong = 0
    review_count = 0
    no_read_count = 0
    notation_sample_count = 0
    no_read_ground_truth_count = 0
    correct_no_read_count = 0
    false_no_read_count = 0

    for record in selected:
        prediction = predictions[record.sample_id]
        _validate_prediction(prediction)
        result = prediction.decode_result
        is_notation = record.supervision_kind == CorpusSupervisionKind.NOTATION
        is_no_read_ground_truth = record.supervision_kind == CorpusSupervisionKind.NO_READ
        if is_notation:
            notation_sample_count += 1
            expected_label = record.supervised_canonical_label
            assert expected_label is not None
            if top_k_is_correct(expected_label, result, 1):
                top_one_correct += 1
            if top_k_is_correct(expected_label, result, 3):
                top_three_correct += 1
        elif is_no_read_ground_truth:
            no_read_ground_truth_count += 1
        else:
            raise OperationRefusedError(
                "excluded_ground_truth_in_model_batch",
                record.sample_id,
                "selective metrics require notation or adjudicated no-read supervision",
            )

        if prediction.disposition is SelectiveDisposition.TRUSTED:
            trusted_count += 1
            if not is_notation or prediction.trusted_label != record.supervised_canonical_label:
                trusted_wrong += 1
        elif prediction.disposition is SelectiveDisposition.REVIEW:
            review_count += 1
        else:
            no_read_count += 1
            if is_no_read_ground_truth:
                correct_no_read_count += 1
            else:
                false_no_read_count += 1

    return SelectiveEvaluationReport(
        role=role,
        sample_count=len(selected),
        writer_count=len({record.writer_id_hash for record in selected}),
        records_sha256=records_digest(selected),
        top_one_correct_count=top_one_correct,
        top_three_correct_count=top_three_correct,
        trusted_count=trusted_count,
        trusted_wrong_count=trusted_wrong,
        review_count=review_count,
        no_read_count=no_read_count,
        notation_sample_count=notation_sample_count,
        no_read_ground_truth_count=no_read_ground_truth_count,
        correct_no_read_count=correct_no_read_count,
        false_no_read_count=false_no_read_count,
    )


def _validate_prediction(prediction: SelectivePrediction) -> None:
    if not isinstance(prediction, SelectivePrediction):
        raise ContractError(
            "invalid_selective_prediction",
            "prediction",
            "expected SelectivePrediction",
        )
    _validate_decode_result(prediction.decode_result)
    if not isinstance(prediction.disposition, SelectiveDisposition):
        raise ContractError(
            "invalid_selective_disposition",
            "prediction.disposition",
            "expected SelectiveDisposition",
        )
    if prediction.disposition is SelectiveDisposition.TRUSTED:
        if not prediction.decode_result.candidates:
            raise ContractError(
                "trusted_without_candidate",
                "prediction.trusted_label",
                "a trusted decision requires a decoded candidate",
            )
        if prediction.trusted_label != prediction.decode_result.candidates[0].canonical_label:
            raise ContractError(
                "trusted_label_is_not_primary",
                "prediction.trusted_label",
                "trusted label must equal the first decoded candidate",
            )
    elif prediction.trusted_label is not None:
        raise ContractError(
            "unexpected_trusted_label",
            "prediction.trusted_label",
            "review and no-read decisions must not carry a trusted label",
        )


def _validate_decode_result(result: DecodeResult) -> None:
    if not isinstance(result, DecodeResult):
        raise ContractError(
            "invalid_decode_result",
            "decode_result",
            "expected DecodeResult",
        )
    if len(result.candidates) > 3:
        raise ContractError(
            "too_many_decoded_candidates",
            "decode_result.candidates",
            "at most three candidates are allowed",
        )
    if not math.isfinite(result.no_read_log_score) or result.no_read_log_score > 0:
        raise ContractError(
            "invalid_no_read_log_score",
            "decode_result.no_read_log_score",
            "must be a finite log probability no greater than zero",
        )

    previous_key = None
    seen = set()
    for index, candidate in enumerate(result.candidates):
        if not isinstance(candidate, DecodedCandidate):
            raise ContractError(
                "invalid_decoded_candidate",
                f"decode_result.candidates[{index}]",
                "expected DecodedCandidate",
            )
        try:
            canonical = require_canonical_chord_label(candidate.canonical_label)
        except CanonicalChordLabelError as error:
            raise ContractError(
                "invalid_decoded_label",
                f"decode_result.candidates[{index}]",
                str(error),
            )
        if canonical in seen:
            raise ContractError(
                "duplicate_decoded_candidate",
                f"decode_result.candidates[{index}]",
                canonical,
            )
        seen.add(canonical)
        score = candidate.raw_joint_log_score
        if not math.isfinite(score) or score > 0:
            raise ContractError(
                "invalid_candidate_log_score",
                f"decode_result.candidates[{index}].raw_joint_log_score",
                "must be a finite log probability no greater than zero",
            )
        key = (-score, canonical)
        if previous_key is not None and key < previous_key:
            raise ContractError(
                "nondeterministic_candidate_order",
                "decode_result.candidates",
                "candidates must be sorted by score descending then label ascending",
            )
        previous_key = key
