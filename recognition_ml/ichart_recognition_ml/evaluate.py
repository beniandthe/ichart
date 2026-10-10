"""Sealed-writer factor evaluation without acceptance or trust claims."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Mapping, Sequence, Tuple

from .contracts import CorpusRecord, records_digest
from .dataset import (
    PipelineRole,
    assert_exact_role,
    assert_prediction_sample_ids,
    load_numpy_feature_batch,
    require_optional_dependency,
    select_role_records,
)
from .decode import decode_factor_logits
from .errors import OperationRefusedError
from .models.output_contract import FactorLogits, OUTPUT_HEADS, factorize_corpus_record
from .selective_evaluation import (
    SelectiveDisposition,
    SelectiveEvaluationReport,
    SelectivePrediction,
    evaluate_selective_predictions,
)


@dataclass(frozen=True)
class FactorEvaluationReport:
    sample_count: int
    writer_count: int
    sealed_records_sha256: str
    per_head_accuracy: Mapping[str, float]
    exact_active_factor_accuracy: float
    is_writer_disjoint_sealed_evaluation: bool = True
    logits_are_uncalibrated: bool = True


@dataclass(frozen=True)
class SealedModelEvaluation:
    factor_report: FactorEvaluationReport
    decoded_report: SelectiveEvaluationReport
    promotion_eligible: bool = False
    no_read_trust_established: bool = False


def _argmax(values: Sequence[float]) -> int:
    return max(range(len(values)), key=lambda index: (values[index], -index))


def evaluate_sealed_logits(
    records: Sequence[CorpusRecord],
    predictions: Mapping[str, FactorLogits],
) -> FactorEvaluationReport:
    """Select sealed writers from a validated full corpus and evaluate them."""

    sealed = select_role_records(records, PipelineRole.SEALED_EVALUATION)
    return _evaluate_exact_sealed_logits(sealed, predictions)


def _evaluate_exact_sealed_logits(
    records: Sequence[CorpusRecord],
    predictions: Mapping[str, FactorLogits],
) -> FactorEvaluationReport:
    """Evaluate a previously validated exact sealed partition."""

    assert_exact_role(records, PipelineRole.SEALED_EVALUATION)
    assert_prediction_sample_ids(records, predictions, "sealed_predictions")
    correct = {head.name: 0 for head in OUTPUT_HEADS}
    active_count = {head.name: 0 for head in OUTPUT_HEADS}
    exact_count = 0

    for record in records:
        target = factorize_corpus_record(record)
        supplied_output = predictions[record.sample_id]
        output = FactorLogits.from_mapping(
            supplied_output.values,
            contract_version=supplied_output.contract_version,
        )
        sample_exact = True
        for head in OUTPUT_HEADS:
            if not target.active[head.name]:
                continue
            active_count[head.name] += 1
            logits = output.values[head.name]
            if head.is_independent_bernoulli:
                expected = tuple(int(value) for value in target.values[head.name])
                actual = tuple(1 if value > 0.0 else 0 for value in logits)
                is_correct = actual == expected
            else:
                is_correct = _argmax(logits) == target.values[head.name]
            if is_correct:
                correct[head.name] += 1
            else:
                sample_exact = False
        if sample_exact:
            exact_count += 1

    per_head = {
        head.name: (
            correct[head.name] / active_count[head.name]
            if active_count[head.name]
            else 0.0
        )
        for head in OUTPUT_HEADS
    }
    return FactorEvaluationReport(
        sample_count=len(records),
        writer_count=len({record.writer_id_hash for record in records}),
        sealed_records_sha256=records_digest(records),
        per_head_accuracy=per_head,
        exact_active_factor_accuracy=exact_count / len(records),
    )


def run_sealed_model_evaluation(
    records: Sequence[CorpusRecord],
    data_root: Path,
    model: object,
    batch_size: int = 128,
) -> FactorEvaluationReport:
    """Run inference only on the sealed partition of a validated full corpus."""

    sealed, predictions = run_role_model_logits(
        records, data_root, model, PipelineRole.SEALED_EVALUATION, batch_size
    )
    return _evaluate_exact_sealed_logits(sealed, predictions)


def run_sealed_model_assessment(
    records: Sequence[CorpusRecord],
    data_root: Path,
    model: object,
    batch_size: int = 128,
) -> SealedModelEvaluation:
    """Report factors and grammar-decoded top-k with every sample review-only."""

    sealed, predictions = run_role_model_logits(
        records, data_root, model, PipelineRole.SEALED_EVALUATION, batch_size
    )
    decoded_predictions = {
        sample_id: SelectivePrediction(
            decode_result=decode_factor_logits(output),
            disposition=SelectiveDisposition.REVIEW,
        )
        for sample_id, output in predictions.items()
    }
    return SealedModelEvaluation(
        factor_report=_evaluate_exact_sealed_logits(sealed, predictions),
        decoded_report=evaluate_selective_predictions(
            records,
            decoded_predictions,
            PipelineRole.SEALED_EVALUATION,
        ),
    )


def run_role_model_logits(
    records: Sequence[CorpusRecord],
    data_root: Path,
    model: object,
    role: PipelineRole,
    batch_size: int = 128,
):
    if role not in (PipelineRole.CALIBRATION, PipelineRole.SEALED_EVALUATION):
        raise OperationRefusedError(
            "unsupported_model_inference_role",
            "role",
            "only calibration or sealed-evaluation inference is allowed",
        )
    selected = select_role_records(records, role)
    assert_exact_role(selected, role)
    if isinstance(batch_size, bool) or not isinstance(batch_size, int) or batch_size <= 0:
        raise ValueError("batch_size must be a positive integer")
    torch = require_optional_dependency("torch", "training")
    batch = load_numpy_feature_batch(selected, data_root)
    predictions: Dict[str, FactorLogits] = {}
    try:
        device = next(model.parameters()).device
    except (AttributeError, StopIteration):
        device = torch.device("cpu")
    model.eval()
    with torch.no_grad():
        for start in range(0, len(selected), batch_size):
            stop = min(len(selected), start + batch_size)
            output = model(
                torch.from_numpy(batch.trajectory[start:stop]).to(device),
                torch.from_numpy(batch.raster[start:stop]).to(device),
            )
            for offset, sample_id in enumerate(batch.sample_ids[start:stop]):
                predictions[sample_id] = FactorLogits.from_mapping(
                    {
                        head.name: output[head.name][offset].detach().cpu().tolist()
                        for head in OUTPUT_HEADS
                    }
                )
    return selected, predictions
