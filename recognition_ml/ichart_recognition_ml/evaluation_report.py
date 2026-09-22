"""Descriptive writer-disjoint evaluation for the corpus-v2 contract.

This module computes metrics; it does not choose a threshold, authorize a
model, or declare recognition quality.  Calibration and sealed-evaluation
remain separate corpus roles, and development rows are never accepted as an
evaluation partition.
"""

from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import ClassVar, Dict, Mapping, Optional, Sequence, Tuple

from .contracts import CorpusRecord, CorpusSupervisionKind
from .dataset import PipelineRole, assert_prediction_sample_ids, select_role_records
from .errors import ContractError, OperationRefusedError
from .selective_evaluation import (
    SelectiveDisposition,
    SelectivePrediction,
    evaluate_selective_predictions,
    top_k_is_correct,
)


EVALUATION_REPORT_VERSION = "writer-disjoint-evaluation-report-v1"
JOINT_PATH_PROBABILITY_VERSION = "normalized-joint-path-mass-v1"
ASSESSMENT_AUTHORITY = "descriptive-only-no-promotion"
NO_READ_TRUTH = "<no-read>"
NO_CANDIDATE = "<no-candidate>"

STRATUM_FIELDS = (
    "chart_style",
    "orientation",
    "device_performance_class",
    "pace",
    "size_bucket",
    "handedness",
    "pencil_experience",
    "construction_variation",
)


def _require_probability(value: object, path: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(float(value))
        or float(value) < 0.0
        or float(value) > 1.0
    ):
        raise ContractError(
            "invalid_joint_path_probability",
            path,
            "must be a finite number in the closed interval [0, 1]",
        )
    return float(value)


@dataclass(frozen=True)
class JointPathProbabilityMass:
    """Normalized probability mass aligned to a ``DecodeResult``.

    Candidate entries are in the exact decoded-candidate order.  Explicit
    no-read and omitted-grammar-path mass make the supplied distribution
    auditable; a bare factor marginal or an unnormalized top-k score cannot
    satisfy this contract.
    """

    candidate_probabilities: Tuple[float, ...]
    no_read_probability: float
    other_path_probability: float
    contract_version: str = JOINT_PATH_PROBABILITY_VERSION

    def __post_init__(self) -> None:
        if self.contract_version != JOINT_PATH_PROBABILITY_VERSION:
            raise ContractError(
                "joint_path_probability_version_mismatch",
                "joint_path_probability.contract_version",
                f"expected {JOINT_PATH_PROBABILITY_VERSION}",
            )
        if not isinstance(self.candidate_probabilities, tuple):
            raise ContractError(
                "mutable_joint_path_probabilities",
                "joint_path_probability.candidate_probabilities",
                "must be an immutable tuple aligned to decoded candidates",
            )
        candidate_probabilities = tuple(
            _require_probability(value, f"joint_path_probability.candidates[{index}]")
            for index, value in enumerate(self.candidate_probabilities)
        )
        no_read = _require_probability(
            self.no_read_probability,
            "joint_path_probability.no_read_probability",
        )
        other = _require_probability(
            self.other_path_probability,
            "joint_path_probability.other_path_probability",
        )
        if any(
            candidate_probabilities[index] < candidate_probabilities[index + 1]
            for index in range(len(candidate_probabilities) - 1)
        ):
            raise ContractError(
                "joint_path_candidate_order_mismatch",
                "joint_path_probability.candidate_probabilities",
                "probabilities must follow nonincreasing decoded-candidate order",
            )
        total = sum(candidate_probabilities) + no_read + other
        if not math.isclose(total, 1.0, rel_tol=0.0, abs_tol=1e-9):
            raise ContractError(
                "unnormalized_joint_path_probability",
                "joint_path_probability",
                f"candidate, no-read, and other-path mass must sum to 1; got {total!r}",
            )
        object.__setattr__(self, "candidate_probabilities", candidate_probabilities)
        object.__setattr__(self, "no_read_probability", no_read)
        object.__setattr__(self, "other_path_probability", other)


@dataclass(frozen=True)
class EvaluationObservation:
    prediction: SelectivePrediction
    joint_path_probability: Optional[JointPathProbabilityMass] = None
    latency_milliseconds: Optional[float] = None


@dataclass(frozen=True)
class TopKAccuracySummary:
    notation_sample_count: int
    notation_writer_count: int
    top_one_correct_count: int
    top_three_correct_count: int
    sample_micro_top_one: Optional[float]
    sample_micro_top_three: Optional[float]
    writer_macro_top_one: Optional[float]
    writer_macro_top_three: Optional[float]


@dataclass(frozen=True)
class SupervisionSummary:
    supervised_notation_count: int
    supervised_no_read_count: int
    correct_no_read_count: int
    false_no_read_count: int
    sample_micro_no_read_recall: Optional[float]
    writer_macro_no_read_recall: Optional[float]
    false_no_read_rate_on_notation: Optional[float]


@dataclass(frozen=True)
class SelectiveDecisionSummary:
    trusted_count: int
    review_count: int
    no_read_count: int
    trusted_wrong_count: int
    trusted_coverage: float
    review_rate: float
    no_read_rate: float
    selective_risk: Optional[float]


@dataclass(frozen=True)
class ConfusionCount:
    expected: str
    observed: str
    count: int


@dataclass(frozen=True)
class EvaluationSlice:
    sample_count: int
    writer_count: int
    accuracy: TopKAccuracySummary
    supervision: SupervisionSummary
    decisions: SelectiveDecisionSummary
    primary_candidate_confusions: Tuple[ConfusionCount, ...]
    disposition_confusions: Tuple[ConfusionCount, ...]


@dataclass(frozen=True)
class StratumSlice:
    dimension: str
    value: str
    metrics: EvaluationSlice


@dataclass(frozen=True)
class CalibrationBin:
    lower_bound_inclusive: float
    upper_bound_inclusive: float
    sample_count: int
    mean_confidence: float
    empirical_accuracy: float


@dataclass(frozen=True)
class CandidateCalibrationSummary:
    source_role: PipelineRole
    observation_count: int
    bin_count: int
    expected_calibration_error: float
    binary_brier_score: float
    bins: Tuple[CalibrationBin, ...]
    may_inform_policy_selection: bool


@dataclass(frozen=True)
class LatencySummary:
    unit: str
    observation_count: int
    missing_count: int
    complete_coverage: bool
    p50: float
    p90: float
    p95: float
    p99: float
    maximum: float


@dataclass(frozen=True)
class WriterDisjointEvaluationReport:
    report_version: str
    role: PipelineRole
    sample_count: int
    writer_count: int
    records_sha256: str
    overall: EvaluationSlice
    strata: Tuple[StratumSlice, ...]
    candidate_calibration: Optional[CandidateCalibrationSummary]
    latency: Optional[LatencySummary]
    assessment_authority: str = ASSESSMENT_AUTHORITY

    is_quality_gate: ClassVar[bool] = False

    @property
    def may_inform_policy_selection(self) -> bool:
        return self.role is PipelineRole.CALIBRATION


def evaluate_writer_disjoint_report(
    records: Sequence[CorpusRecord],
    observations: Mapping[str, EvaluationObservation],
    role: PipelineRole,
    calibration_bin_count: int = 10,
) -> WriterDisjointEvaluationReport:
    """Compute descriptive metrics for exactly one non-development role.

    The complete corpus is required so the corpus-v2 writer-disjoint validator
    can check split leakage before role selection.  Prediction keys must then
    match the selected role exactly; development, cross-role, missing, or extra
    observations are refused.
    """

    if role not in (PipelineRole.CALIBRATION, PipelineRole.SEALED_EVALUATION):
        role_name = role.value if isinstance(role, PipelineRole) else repr(role)
        raise OperationRefusedError(
            "unsupported_writer_disjoint_evaluation_role",
            "role",
            f"expected calibration or sealed-evaluation, got {role_name}",
        )
    if (
        isinstance(calibration_bin_count, bool)
        or not isinstance(calibration_bin_count, int)
        or calibration_bin_count < 2
        or calibration_bin_count > 100
    ):
        raise ContractError(
            "invalid_calibration_bin_count",
            "calibration_bin_count",
            "must be an integer from 2 through 100",
        )

    selected = select_role_records(records, role)
    assert_prediction_sample_ids(selected, observations, f"{role.value}_observations")
    for record in selected:
        observation = observations[record.sample_id]
        if not isinstance(observation, EvaluationObservation):
            raise ContractError(
                "invalid_evaluation_observation",
                record.sample_id,
                "expected EvaluationObservation",
            )

    predictions = {
        record.sample_id: observations[record.sample_id].prediction
        for record in selected
    }
    selective = evaluate_selective_predictions(records, predictions, role)
    overall = _evaluate_slice(selected, observations)
    strata = _evaluate_strata(selected, observations)
    calibration = _evaluate_candidate_calibration(
        selected,
        observations,
        role,
        calibration_bin_count,
    )
    latency = _evaluate_latency(selected, observations)

    if overall.sample_count != selective.sample_count:
        raise AssertionError("evaluation layer sample-count disagreement")
    if overall.writer_count != selective.writer_count:
        raise AssertionError("evaluation layer writer-count disagreement")
    if overall.decisions.trusted_count != selective.trusted_count:
        raise AssertionError("evaluation layer trusted-count disagreement")
    if overall.decisions.trusted_wrong_count != selective.trusted_wrong_count:
        raise AssertionError("evaluation layer selective-risk disagreement")

    return WriterDisjointEvaluationReport(
        report_version=EVALUATION_REPORT_VERSION,
        role=role,
        sample_count=len(selected),
        writer_count=len({record.writer_id_hash for record in selected}),
        records_sha256=selective.records_sha256,
        overall=overall,
        strata=strata,
        candidate_calibration=calibration,
        latency=latency,
    )


def _evaluate_strata(
    records: Sequence[CorpusRecord],
    observations: Mapping[str, EvaluationObservation],
) -> Tuple[StratumSlice, ...]:
    result = []
    for dimension in STRATUM_FIELDS:
        values: Dict[str, list[CorpusRecord]] = defaultdict(list)
        for record in records:
            raw_value = getattr(record, dimension)
            if not isinstance(raw_value, str) or not raw_value:
                raise OperationRefusedError(
                    "missing_evaluation_stratum",
                    f"{record.sample_id}.{dimension}",
                    "corpus-v2 evaluation requires an explicit immutable stratum",
                )
            values[raw_value].append(record)
        for value in sorted(values):
            members = tuple(values[value])
            result.append(
                StratumSlice(
                    dimension=dimension,
                    value=value,
                    metrics=_evaluate_slice(members, observations),
                )
            )
    return tuple(result)


def _evaluate_slice(
    records: Sequence[CorpusRecord],
    observations: Mapping[str, EvaluationObservation],
) -> EvaluationSlice:
    notation_count = 0
    no_read_truth_count = 0
    top_one_correct = 0
    top_three_correct = 0
    correct_no_read = 0
    false_no_read = 0
    trusted_count = 0
    trusted_wrong = 0
    review_count = 0
    no_read_decision_count = 0
    writer_notation = defaultdict(lambda: [0, 0, 0])
    writer_no_read = defaultdict(lambda: [0, 0])
    candidate_confusions: Counter[Tuple[str, str]] = Counter()
    disposition_confusions: Counter[Tuple[str, str]] = Counter()

    for record in records:
        prediction = observations[record.sample_id].prediction
        result = prediction.decode_result
        is_notation = record.supervision_kind == CorpusSupervisionKind.NOTATION
        is_no_read_truth = record.supervision_kind == CorpusSupervisionKind.NO_READ
        if not is_notation and not is_no_read_truth:
            raise OperationRefusedError(
                "excluded_ground_truth_in_evaluation_slice",
                record.sample_id,
                "writer-disjoint metrics require frozen notation or no-read supervision",
            )

        expected_confusion = (
            record.supervised_canonical_label if is_notation else NO_READ_TRUTH
        )
        assert expected_confusion is not None
        observed_candidate = (
            result.candidates[0].canonical_label if result.candidates else NO_CANDIDATE
        )
        candidate_confusions[(expected_confusion, observed_candidate)] += 1
        disposition_confusions[
            ("notation" if is_notation else "no-read", prediction.disposition.value)
        ] += 1

        if is_notation:
            notation_count += 1
            expected_label = record.supervised_canonical_label
            assert expected_label is not None
            top_one = top_k_is_correct(expected_label, result, 1)
            top_three = top_k_is_correct(expected_label, result, 3)
            top_one_correct += int(top_one)
            top_three_correct += int(top_three)
            writer_bucket = writer_notation[record.writer_id_hash]
            writer_bucket[0] += 1
            writer_bucket[1] += int(top_one)
            writer_bucket[2] += int(top_three)
        else:
            no_read_truth_count += 1
            writer_bucket = writer_no_read[record.writer_id_hash]
            writer_bucket[0] += 1

        if prediction.disposition is SelectiveDisposition.TRUSTED:
            trusted_count += 1
            if (
                not is_notation
                or prediction.trusted_label != record.supervised_canonical_label
            ):
                trusted_wrong += 1
        elif prediction.disposition is SelectiveDisposition.REVIEW:
            review_count += 1
        elif prediction.disposition is SelectiveDisposition.NO_READ:
            no_read_decision_count += 1
            if is_no_read_truth:
                correct_no_read += 1
                writer_no_read[record.writer_id_hash][1] += 1
            else:
                false_no_read += 1
        else:
            raise ContractError(
                "invalid_selective_disposition",
                record.sample_id,
                "expected trusted, review, or no-read",
            )

    sample_count = len(records)
    if sample_count == 0:
        raise ContractError(
            "empty_evaluation_slice",
            "records",
            "at least one supervised record is required",
        )
    writer_top_one = [correct_one / count for count, correct_one, _ in writer_notation.values()]
    writer_top_three = [correct_three / count for count, _, correct_three in writer_notation.values()]
    writer_no_read_recall = [correct / count for count, correct in writer_no_read.values()]

    return EvaluationSlice(
        sample_count=sample_count,
        writer_count=len({record.writer_id_hash for record in records}),
        accuracy=TopKAccuracySummary(
            notation_sample_count=notation_count,
            notation_writer_count=len(writer_notation),
            top_one_correct_count=top_one_correct,
            top_three_correct_count=top_three_correct,
            sample_micro_top_one=(top_one_correct / notation_count if notation_count else None),
            sample_micro_top_three=(
                top_three_correct / notation_count if notation_count else None
            ),
            writer_macro_top_one=(
                sum(writer_top_one) / len(writer_top_one) if writer_top_one else None
            ),
            writer_macro_top_three=(
                sum(writer_top_three) / len(writer_top_three)
                if writer_top_three
                else None
            ),
        ),
        supervision=SupervisionSummary(
            supervised_notation_count=notation_count,
            supervised_no_read_count=no_read_truth_count,
            correct_no_read_count=correct_no_read,
            false_no_read_count=false_no_read,
            sample_micro_no_read_recall=(
                correct_no_read / no_read_truth_count if no_read_truth_count else None
            ),
            writer_macro_no_read_recall=(
                sum(writer_no_read_recall) / len(writer_no_read_recall)
                if writer_no_read_recall
                else None
            ),
            false_no_read_rate_on_notation=(
                false_no_read / notation_count if notation_count else None
            ),
        ),
        decisions=SelectiveDecisionSummary(
            trusted_count=trusted_count,
            review_count=review_count,
            no_read_count=no_read_decision_count,
            trusted_wrong_count=trusted_wrong,
            trusted_coverage=trusted_count / sample_count,
            review_rate=review_count / sample_count,
            no_read_rate=no_read_decision_count / sample_count,
            selective_risk=(trusted_wrong / trusted_count if trusted_count else None),
        ),
        primary_candidate_confusions=_frozen_confusions(candidate_confusions),
        disposition_confusions=_frozen_confusions(disposition_confusions),
    )


def _frozen_confusions(
    counts: Mapping[Tuple[str, str], int]
) -> Tuple[ConfusionCount, ...]:
    return tuple(
        ConfusionCount(expected=expected, observed=observed, count=count)
        for (expected, observed), count in sorted(counts.items())
    )


def _evaluate_candidate_calibration(
    records: Sequence[CorpusRecord],
    observations: Mapping[str, EvaluationObservation],
    role: PipelineRole,
    bin_count: int,
) -> Optional[CandidateCalibrationSummary]:
    supplied = [
        observations[record.sample_id].joint_path_probability is not None
        for record in records
    ]
    if not any(supplied):
        return None
    if not all(supplied):
        raise OperationRefusedError(
            "incomplete_joint_path_probability_coverage",
            role.value,
            "candidate calibration requires normalized mass for every selected sample",
        )

    bin_members: Dict[int, list[Tuple[float, float]]] = defaultdict(list)
    brier_terms = []
    for record in records:
        observation = observations[record.sample_id]
        probability = observation.joint_path_probability
        assert probability is not None
        if not isinstance(probability, JointPathProbabilityMass):
            raise ContractError(
                "invalid_joint_path_probability_contract",
                record.sample_id,
                "expected JointPathProbabilityMass",
            )
        candidate_count = len(observation.prediction.decode_result.candidates)
        if candidate_count == 0:
            raise OperationRefusedError(
                "primary_candidate_required_for_calibration",
                record.sample_id,
                "candidate ECE and Brier are undefined without a primary candidate",
            )
        if len(probability.candidate_probabilities) != candidate_count:
            raise ContractError(
                "joint_path_candidate_count_mismatch",
                record.sample_id,
                f"expected {candidate_count} candidate probabilities, got "
                f"{len(probability.candidate_probabilities)}",
            )
        confidence = probability.candidate_probabilities[0]
        expected_label = record.supervised_canonical_label
        correct = float(
            expected_label is not None
            and top_k_is_correct(expected_label, observation.prediction.decode_result, 1)
        )
        bin_index = min(int(confidence * bin_count), bin_count - 1)
        bin_members[bin_index].append((confidence, correct))
        brier_terms.append((confidence - correct) ** 2)

    populated_bins = []
    weighted_error = 0.0
    for bin_index in sorted(bin_members):
        members = bin_members[bin_index]
        mean_confidence = sum(confidence for confidence, _ in members) / len(members)
        empirical_accuracy = sum(correct for _, correct in members) / len(members)
        weighted_error += (
            len(members)
            * abs(mean_confidence - empirical_accuracy)
            / len(records)
        )
        populated_bins.append(
            CalibrationBin(
                lower_bound_inclusive=bin_index / bin_count,
                upper_bound_inclusive=(bin_index + 1) / bin_count,
                sample_count=len(members),
                mean_confidence=mean_confidence,
                empirical_accuracy=empirical_accuracy,
            )
        )
    return CandidateCalibrationSummary(
        source_role=role,
        observation_count=len(records),
        bin_count=bin_count,
        expected_calibration_error=weighted_error,
        binary_brier_score=sum(brier_terms) / len(brier_terms),
        bins=tuple(populated_bins),
        may_inform_policy_selection=role is PipelineRole.CALIBRATION,
    )


def _evaluate_latency(
    records: Sequence[CorpusRecord],
    observations: Mapping[str, EvaluationObservation],
) -> Optional[LatencySummary]:
    values = []
    missing = 0
    for record in records:
        value = observations[record.sample_id].latency_milliseconds
        if value is None:
            missing += 1
            continue
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(float(value))
            or float(value) < 0.0
        ):
            raise ContractError(
                "invalid_latency_observation",
                f"{record.sample_id}.latency_milliseconds",
                "must be an explicit finite nonnegative number of milliseconds",
            )
        values.append(float(value))
    if not values:
        return None
    values.sort()
    return LatencySummary(
        unit="milliseconds",
        observation_count=len(values),
        missing_count=missing,
        complete_coverage=missing == 0,
        p50=_percentile(values, 0.50),
        p90=_percentile(values, 0.90),
        p95=_percentile(values, 0.95),
        p99=_percentile(values, 0.99),
        maximum=values[-1],
    )


def _percentile(sorted_values: Sequence[float], quantile: float) -> float:
    if not sorted_values:
        raise ContractError(
            "empty_latency_observations",
            "latency",
            "at least one value is required",
        )
    rank = (len(sorted_values) - 1) * quantile
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return sorted_values[lower]
    fraction = rank - lower
    return sorted_values[lower] + (
        sorted_values[upper] - sorted_values[lower]
    ) * fraction
