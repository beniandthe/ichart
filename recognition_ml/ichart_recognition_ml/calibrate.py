"""Joint-path one-vs-rest temperature calibration matching Swift policy."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Dict, Mapping, Sequence, Tuple

from .contracts import CorpusRecord, CorpusSupervisionKind, records_digest
from .dataset import PipelineRole, assert_prediction_sample_ids, select_role_records
from .decode import DecodeResult, decode_factor_logits
from .errors import ContractError, OperationRefusedError
from .models.output_contract import OUTPUT_CONTRACT_VERSION
from .schema import FEATURE_SCHEMA


SCORE_CONTRACT_VERSION = "joint-path-one-vs-rest-v1"
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class TemperatureSearchConfig:
    minimum: float = 0.20
    maximum: float = 5.0
    steps: int = 241

    def validate(self) -> None:
        if (
            isinstance(self.minimum, bool)
            or not isinstance(self.minimum, (int, float))
            or not math.isfinite(self.minimum)
            or self.minimum <= 0
        ):
            raise ContractError("invalid_calibration_search", "minimum", "must be finite and positive")
        if (
            isinstance(self.maximum, bool)
            or not isinstance(self.maximum, (int, float))
            or not math.isfinite(self.maximum)
            or self.maximum <= self.minimum
        ):
            raise ContractError("invalid_calibration_search", "maximum", "must exceed minimum")
        if isinstance(self.steps, bool) or not isinstance(self.steps, int) or self.steps < 3:
            raise ContractError("invalid_calibration_search", "steps", "must be an integer of at least 3")


@dataclass(frozen=True)
class JointPathCalibrationObservation:
    """One decoded path versus every other possible model outcome."""

    sample_id: str
    writer_id_hash: str
    raw_joint_log_probability: float
    is_correct: bool
    is_no_read_path: bool

    def validate(self) -> None:
        if not isinstance(self.sample_id, str) or not self.sample_id:
            raise ContractError("invalid_calibration_observation", "sample_id", "must not be empty")
        if not isinstance(self.writer_id_hash, str) or not self.writer_id_hash:
            raise ContractError(
                "invalid_calibration_observation", "writer_id_hash", "must not be empty"
            )
        if (
            isinstance(self.raw_joint_log_probability, bool)
            or not isinstance(self.raw_joint_log_probability, (int, float))
            or not math.isfinite(self.raw_joint_log_probability)
            or self.raw_joint_log_probability > 0
        ):
            raise ContractError(
                "invalid_joint_log_probability",
                self.sample_id,
                "must be a finite log probability no greater than zero",
            )
        if not isinstance(self.is_correct, bool) or not isinstance(self.is_no_read_path, bool):
            raise ContractError(
                "invalid_calibration_observation", self.sample_id, "flags must be booleans"
            )


@dataclass(frozen=True)
class TemperatureCalibrationResult:
    temperature: float
    nll_before: float
    nll_after: float
    calibration_sample_count: int
    calibration_writer_count: int
    calibration_records_sha256: str
    score_contract_version: str = SCORE_CONTRACT_VERSION
    used_writer_disjoint_data: bool = False
    is_independently_fitted: bool = False
    has_positive_no_read_supervision: bool = True
    calibration_observation_count: int = 0


def calibrated_one_vs_rest_support(
    raw_joint_log_probability: float,
    temperature: float,
) -> float:
    """Mirror Swift without renormalizing the decoded top-three survivors."""

    if not math.isfinite(raw_joint_log_probability) or raw_joint_log_probability > 0:
        raise ContractError(
            "invalid_joint_log_probability",
            "raw_joint_log_probability",
            "must be finite and no greater than zero",
        )
    if not math.isfinite(temperature) or temperature <= 0:
        raise ContractError("invalid_temperature", "temperature", "must be finite and positive")
    if raw_joint_log_probability == 0:
        return 1.0
    log_one_minus = (
        math.log1p(-math.exp(raw_joint_log_probability))
        if raw_joint_log_probability < -math.log(2.0)
        else math.log(-math.expm1(raw_joint_log_probability))
    )
    scaled_logit = (raw_joint_log_probability - log_one_minus) / temperature
    if scaled_logit >= 0:
        return 1.0 / (1.0 + math.exp(-scaled_logit))
    exponential = math.exp(scaled_logit)
    return exponential / (1.0 + exponential)


def fit_joint_path_temperature(
    observations: Sequence[JointPathCalibrationObservation],
    calibration_sample_count: int,
    calibration_writer_count: int,
    calibration_records_sha256: str,
    config: TemperatureSearchConfig = TemperatureSearchConfig(),
) -> TemperatureCalibrationResult:
    """Fit exactly the score transformed by Swift's selective policy."""

    config.validate()
    if not observations:
        raise ContractError("empty_calibration_observations", "observations", "must not be empty")
    for observation in observations:
        observation.validate()
    if (
        isinstance(calibration_sample_count, bool)
        or not isinstance(calibration_sample_count, int)
        or calibration_sample_count <= 0
    ):
        raise ContractError("invalid_integer", "calibration_sample_count", "must be positive")
    if (
        isinstance(calibration_writer_count, bool)
        or not isinstance(calibration_writer_count, int)
        or calibration_writer_count <= 0
    ):
        raise ContractError("invalid_integer", "calibration_writer_count", "must be positive")
    _require_sha256(calibration_records_sha256, "calibration_records_sha256")

    categories = {
        (observation.is_no_read_path, observation.is_correct) for observation in observations
    }
    required = {(False, False), (False, True), (True, False), (True, True)}
    if required.difference(categories):
        raise OperationRefusedError(
            "incomplete_no_read_calibration_supervision",
            "observations",
            "candidate and no-read paths each require positive and negative examples",
        )

    log_minimum = math.log(config.minimum)
    log_maximum = math.log(config.maximum)
    temperatures = tuple(
        math.exp(log_minimum + (log_maximum - log_minimum) * index / (config.steps - 1))
        for index in range(config.steps)
    )
    scored = tuple((_mean_binary_nll(observations, temperature), temperature) for temperature in temperatures)
    nll_after, temperature = min(
        scored,
        key=lambda item: (item[0], abs(math.log(item[1])), item[1]),
    )
    return TemperatureCalibrationResult(
        temperature=temperature,
        nll_before=_mean_binary_nll(observations, 1.0),
        nll_after=nll_after,
        calibration_sample_count=calibration_sample_count,
        calibration_writer_count=calibration_writer_count,
        calibration_records_sha256=calibration_records_sha256,
        calibration_observation_count=len(observations),
    )


def build_joint_path_observations(
    records: Sequence[CorpusRecord],
    decoded_results: Mapping[str, DecodeResult],
) -> Tuple[Tuple[CorpusRecord, ...], Tuple[JointPathCalibrationObservation, ...]]:
    """Bind decoded paths to independently adjudicated calibration truth."""

    calibration = select_role_records(records, PipelineRole.CALIBRATION)
    assert_prediction_sample_ids(calibration, decoded_results, "calibration_decoded_results")
    kinds = {record.supervision_kind for record in calibration}
    if not {
        CorpusSupervisionKind.NOTATION,
        CorpusSupervisionKind.NO_READ,
    }.issubset(kinds):
        raise OperationRefusedError(
            "incomplete_no_read_calibration_supervision",
            "calibration",
            "writer-disjoint calibration requires both notation and adjudicated no-read rows",
        )

    observations = []
    for record in calibration:
        result = decoded_results[record.sample_id]
        expected = record.supervised_canonical_label
        for candidate in result.candidates:
            observations.append(
                JointPathCalibrationObservation(
                    sample_id=record.sample_id,
                    writer_id_hash=record.writer_id_hash,
                    raw_joint_log_probability=candidate.raw_joint_log_score,
                    is_correct=(
                        record.supervision_kind == CorpusSupervisionKind.NOTATION
                        and candidate.canonical_label == expected
                    ),
                    is_no_read_path=False,
                )
            )
        observations.append(
            JointPathCalibrationObservation(
                sample_id=record.sample_id,
                writer_id_hash=record.writer_id_hash,
                raw_joint_log_probability=result.no_read_log_score,
                is_correct=record.supervision_kind == CorpusSupervisionKind.NO_READ,
                is_no_read_path=True,
            )
        )
    return calibration, tuple(observations)


def fit_writer_disjoint_model_temperature(
    records: Sequence[CorpusRecord],
    data_root: Path,
    model: object,
    batch_size: int = 128,
    config: TemperatureSearchConfig = TemperatureSearchConfig(),
) -> TemperatureCalibrationResult:
    """Infer only on calibration writers and fit the exact Swift score transform."""

    # Local import keeps pure calibration math usable without optional ML deps.
    from .evaluate import run_role_model_logits

    calibration, logits = run_role_model_logits(
        records, data_root, model, PipelineRole.CALIBRATION, batch_size
    )
    decoded = {
        sample_id: decode_factor_logits(output) for sample_id, output in logits.items()
    }
    bound_records, observations = build_joint_path_observations(records, decoded)
    if tuple(record.sample_id for record in calibration) != tuple(
        record.sample_id for record in bound_records
    ):
        raise OperationRefusedError(
            "calibration_role_changed",
            "calibration",
            "role membership changed during calibration",
        )
    result = fit_joint_path_temperature(
        observations,
        calibration_sample_count=len(calibration),
        calibration_writer_count=len({record.writer_id_hash for record in calibration}),
        calibration_records_sha256=records_digest(calibration),
        config=config,
    )
    return replace(
        result,
        used_writer_disjoint_data=True,
        is_independently_fitted=True,
        has_positive_no_read_supervision=True,
    )


def _mean_binary_nll(
    observations: Sequence[JointPathCalibrationObservation],
    temperature: float,
) -> float:
    total = 0.0
    minimum_probability = float.fromhex("0x1.0p-1022")
    for observation in observations:
        support = calibrated_one_vs_rest_support(
            observation.raw_joint_log_probability,
            temperature,
        )
        if observation.is_correct:
            total += -math.log(max(support, minimum_probability))
        else:
            total += -math.log(max(1.0 - support, minimum_probability))
    return total / len(observations)


def make_swift_calibration_artifact(
    result: TemperatureCalibrationResult,
    calibration_artifact_sha256: str,
    manifest_artifact_sha256: str,
    model_artifact_sha256: str,
    fit_dataset_identifier: str,
    independent_fit_receipt_sha256: str,
) -> Dict[str, object]:
    if result.score_contract_version != SCORE_CONTRACT_VERSION:
        raise ContractError(
            "score_contract_version_mismatch",
            "calibration_result",
            f"expected {SCORE_CONTRACT_VERSION}",
        )
    if not result.used_writer_disjoint_data or not result.is_independently_fitted:
        raise OperationRefusedError(
            "writer_disjoint_calibration_required",
            "calibration_result",
            "standalone score fitting is diagnostic; artifact emission requires a corpus-bound fit",
        )
    if not result.has_positive_no_read_supervision:
        raise OperationRefusedError(
            "negative_no_read_supervision_required",
            "calibration_result",
            "a Swift calibration artifact requires positive no-read examples",
        )
    if not isinstance(fit_dataset_identifier, str) or not fit_dataset_identifier.strip():
        raise ContractError("invalid_dataset_identifier", "fit_dataset_identifier", "must not be empty")
    return {
        "artifactContractVersion": "chord-ink-calibration-v1",
        "calibrationArtifactSHA256": _require_sha256(
            calibration_artifact_sha256, "calibrationArtifactSHA256"
        ),
        "manifestArtifactSHA256": _require_sha256(
            manifest_artifact_sha256, "manifestArtifactSHA256"
        ),
        "modelArtifactSHA256": _require_sha256(model_artifact_sha256, "modelArtifactSHA256"),
        "featureSchemaVersion": FEATURE_SCHEMA.version,
        "outputContractVersion": OUTPUT_CONTRACT_VERSION,
        "method": "temperature_scaling",
        "temperature": result.temperature,
        "wasIndependentlyFitted": result.is_independently_fitted,
        "usedWriterDisjointData": result.used_writer_disjoint_data,
        "fitDatasetIdentifier": fit_dataset_identifier,
        "independentFitReceiptSHA256": _require_sha256(
            independent_fit_receipt_sha256, "independentFitReceiptSHA256"
        ),
    }


def _require_sha256(value: str, path: str) -> str:
    if not isinstance(value, str) or _SHA256.fullmatch(value) is None:
        raise ContractError("invalid_sha256", path, "must be 64 lowercase hexadecimal characters")
    return value
