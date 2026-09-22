"""Strict, weights-only serialization for learned-model research checkpoints."""

from __future__ import annotations

import hashlib
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Mapping, Sequence, Tuple

from .contracts import CorpusRecord, CorpusSupervisionKind, records_digest
from .dataset import PipelineRole, require_optional_dependency, select_role_records
from .errors import ContractError, OperationRefusedError
from .models.dual_view import DualViewChordModel, DualViewModelConfig
from .models.output_contract import OUTPUT_CONTRACT_VERSION
from .schema import FEATURE_SCHEMA
from .train_pipeline import TrainingConfig, TrainingResult


CHECKPOINT_CONTRACT_VERSION = "chord-ink-training-checkpoint-v1"
_CHECKPOINT_FIELDS = {"metadata", "state_dict"}
_METADATA_FIELDS = {
    "checkpoint_contract_version",
    "feature_schema_version",
    "output_contract_version",
    "model_identifier",
    "model_config",
    "training_config",
    "development_records_sha256",
    "development_sample_count",
    "development_writer_count",
    "epoch_losses",
    "has_negative_no_read_supervision",
}
_MODEL_CONFIG_FIELDS = {"trajectory_channels", "raster_channels", "fused_width", "dropout"}
_TRAINING_CONFIG_FIELDS = {
    "seed",
    "epochs",
    "batch_size",
    "learning_rate",
    "weight_decay",
    "device",
    "deterministic",
}


@dataclass(frozen=True)
class CheckpointMetadata:
    checkpoint_contract_version: str
    feature_schema_version: str
    output_contract_version: str
    model_identifier: str
    model_config: DualViewModelConfig
    training_config: TrainingConfig
    development_records_sha256: str
    development_sample_count: int
    development_writer_count: int
    epoch_losses: Tuple[float, ...]
    has_negative_no_read_supervision: bool

    @classmethod
    def from_mapping(cls, value: object) -> "CheckpointMetadata":
        if not isinstance(value, dict):
            raise ContractError("invalid_checkpoint_metadata", "metadata", "must be an object")
        missing = sorted(_METADATA_FIELDS.difference(value.keys()))
        unknown = sorted(set(value.keys()).difference(_METADATA_FIELDS))
        if missing:
            raise ContractError("missing_checkpoint_field", "metadata", ", ".join(missing))
        if unknown:
            raise ContractError("unknown_checkpoint_field", "metadata", ", ".join(unknown))
        if value["checkpoint_contract_version"] != CHECKPOINT_CONTRACT_VERSION:
            raise ContractError(
                "checkpoint_contract_version_mismatch",
                "metadata.checkpoint_contract_version",
                f"expected {CHECKPOINT_CONTRACT_VERSION}",
            )
        if value["feature_schema_version"] != FEATURE_SCHEMA.version:
            raise ContractError(
                "feature_schema_mismatch",
                "metadata.feature_schema_version",
                f"expected {FEATURE_SCHEMA.version}",
            )
        if value["output_contract_version"] != OUTPUT_CONTRACT_VERSION:
            raise ContractError(
                "output_contract_version_mismatch",
                "metadata.output_contract_version",
                f"expected {OUTPUT_CONTRACT_VERSION}",
            )
        model_identifier = value["model_identifier"]
        if not isinstance(model_identifier, str) or not model_identifier.strip():
            raise ContractError(
                "invalid_model_identifier", "metadata.model_identifier", "must not be empty"
            )
        model_config_value = _exact_dict(
            value["model_config"], _MODEL_CONFIG_FIELDS, "metadata.model_config"
        )
        training_config_value = _exact_dict(
            value["training_config"], _TRAINING_CONFIG_FIELDS, "metadata.training_config"
        )
        try:
            model_config = DualViewModelConfig(**model_config_value)
            training_config = TrainingConfig(**training_config_value)
        except TypeError as error:
            raise ContractError("invalid_checkpoint_config", "metadata", str(error))
        model_config.validate()
        training_config.validate()

        digest = value["development_records_sha256"]
        if not _is_sha256(digest):
            raise ContractError(
                "invalid_sha256", "metadata.development_records_sha256", "invalid digest"
            )
        sample_count = _positive_integer(
            value["development_sample_count"], "metadata.development_sample_count"
        )
        writer_count = _positive_integer(
            value["development_writer_count"], "metadata.development_writer_count"
        )
        epoch_losses_value = value["epoch_losses"]
        if not isinstance(epoch_losses_value, (tuple, list)) or not epoch_losses_value:
            raise ContractError(
                "invalid_epoch_losses", "metadata.epoch_losses", "must be a non-empty sequence"
            )
        try:
            epoch_losses = tuple(float(item) for item in epoch_losses_value)
        except (TypeError, ValueError):
            raise ContractError(
                "invalid_epoch_losses", "metadata.epoch_losses", "must contain numbers"
            )
        if len(epoch_losses) != training_config.epochs or any(
            not math.isfinite(item) or item < 0 for item in epoch_losses
        ):
            raise ContractError(
                "invalid_epoch_losses",
                "metadata.epoch_losses",
                "count must equal epochs and every loss must be finite and nonnegative",
            )
        negative_supervision = value["has_negative_no_read_supervision"]
        if not isinstance(negative_supervision, bool):
            raise ContractError(
                "invalid_boolean",
                "metadata.has_negative_no_read_supervision",
                "must be a boolean",
            )
        return cls(
            checkpoint_contract_version=CHECKPOINT_CONTRACT_VERSION,
            feature_schema_version=FEATURE_SCHEMA.version,
            output_contract_version=OUTPUT_CONTRACT_VERSION,
            model_identifier=model_identifier,
            model_config=model_config,
            training_config=training_config,
            development_records_sha256=digest,
            development_sample_count=sample_count,
            development_writer_count=writer_count,
            epoch_losses=epoch_losses,
            has_negative_no_read_supervision=negative_supervision,
        )

    def as_dict(self) -> Dict[str, object]:
        return {
            "checkpoint_contract_version": self.checkpoint_contract_version,
            "feature_schema_version": self.feature_schema_version,
            "output_contract_version": self.output_contract_version,
            "model_identifier": self.model_identifier,
            "model_config": asdict(self.model_config),
            "training_config": asdict(self.training_config),
            "development_records_sha256": self.development_records_sha256,
            "development_sample_count": self.development_sample_count,
            "development_writer_count": self.development_writer_count,
            "epoch_losses": list(self.epoch_losses),
            "has_negative_no_read_supervision": self.has_negative_no_read_supervision,
        }


@dataclass(frozen=True)
class LoadedCheckpoint:
    model: object
    metadata: CheckpointMetadata
    artifact_sha256: str
    artifact_byte_count: int


def metadata_for_training_result(
    result: TrainingResult,
    model_identifier: str,
) -> CheckpointMetadata:
    return CheckpointMetadata.from_mapping(
        {
            "checkpoint_contract_version": CHECKPOINT_CONTRACT_VERSION,
            "feature_schema_version": FEATURE_SCHEMA.version,
            "output_contract_version": OUTPUT_CONTRACT_VERSION,
            "model_identifier": model_identifier,
            "model_config": asdict(result.model_config),
            "training_config": asdict(result.training_config),
            "development_records_sha256": result.development_records_sha256,
            "development_sample_count": len(result.development_sample_ids),
            "development_writer_count": len(result.development_writer_hashes),
            "epoch_losses": list(result.epoch_losses),
            "has_negative_no_read_supervision": result.has_negative_no_read_supervision,
        }
    )


def save_training_checkpoint(
    result: TrainingResult,
    path: Path,
    model_identifier: str,
) -> CheckpointMetadata:
    if path.exists():
        raise OperationRefusedError(
            "checkpoint_would_overwrite", str(path), "existing checkpoints are immutable"
        )
    torch = require_optional_dependency("torch", "training")
    metadata = metadata_for_training_result(result, model_identifier)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    try:
        torch.save(
            {"metadata": metadata.as_dict(), "state_dict": result.model.state_dict()},
            temporary,
        )
        temporary.replace(path)
    except Exception as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        if isinstance(error, ContractError):
            raise
        raise OperationRefusedError("checkpoint_write_failed", str(path), str(error))
    return metadata


def load_training_checkpoint(path: Path) -> LoadedCheckpoint:
    if not path.is_file():
        raise OperationRefusedError(
            "checkpoint_unavailable", str(path), "checkpoint file does not exist"
        )
    torch = require_optional_dependency("torch", "training")
    try:
        payload = torch.load(path, map_location="cpu", weights_only=True)
    except Exception as error:
        raise OperationRefusedError("checkpoint_load_failed", str(path), str(error))
    if not isinstance(payload, dict):
        raise ContractError("invalid_checkpoint", str(path), "checkpoint must be an object")
    missing = sorted(_CHECKPOINT_FIELDS.difference(payload.keys()))
    unknown = sorted(set(payload.keys()).difference(_CHECKPOINT_FIELDS))
    if missing:
        raise ContractError("missing_checkpoint_field", str(path), ", ".join(missing))
    if unknown:
        raise ContractError("unknown_checkpoint_field", str(path), ", ".join(unknown))
    metadata = CheckpointMetadata.from_mapping(payload["metadata"])
    state_dict = payload["state_dict"]
    if not isinstance(state_dict, Mapping) or not state_dict:
        raise ContractError("invalid_state_dict", str(path), "must be a non-empty mapping")
    model = DualViewChordModel(metadata.model_config)
    try:
        model.load_state_dict(state_dict, strict=True)
    except Exception as error:
        raise ContractError("state_dict_contract_mismatch", str(path), str(error))
    model.eval()
    artifact = path.read_bytes()
    return LoadedCheckpoint(
        model=model,
        metadata=metadata,
        artifact_sha256=hashlib.sha256(artifact).hexdigest(),
        artifact_byte_count=len(artifact),
    )


def validate_checkpoint_corpus_binding(
    checkpoint: LoadedCheckpoint,
    records: Sequence[CorpusRecord],
) -> None:
    development = select_role_records(records, PipelineRole.TRAINING)
    actual_digest = records_digest(development)
    if actual_digest != checkpoint.metadata.development_records_sha256:
        raise OperationRefusedError(
            "checkpoint_corpus_mismatch",
            "checkpoint.metadata.development_records_sha256",
            f"expected {actual_digest}, got {checkpoint.metadata.development_records_sha256}",
        )
    if len(development) != checkpoint.metadata.development_sample_count:
        raise OperationRefusedError(
            "checkpoint_corpus_mismatch", "development_sample_count", "count changed"
        )
    writer_count = len({record.writer_id_hash for record in development})
    if writer_count != checkpoint.metadata.development_writer_count:
        raise OperationRefusedError(
            "checkpoint_corpus_mismatch", "development_writer_count", "count changed"
        )
    actual_kinds = {record.supervision_kind for record in development}
    actual_negative_supervision = {
        CorpusSupervisionKind.NOTATION,
        CorpusSupervisionKind.NO_READ,
    }.issubset(actual_kinds)
    if actual_negative_supervision != checkpoint.metadata.has_negative_no_read_supervision:
        raise OperationRefusedError(
            "checkpoint_supervision_claim_mismatch",
            "has_negative_no_read_supervision",
            "checkpoint claim does not match the bound eligible development rows",
        )


def require_negative_no_read_supervision(metadata: CheckpointMetadata, operation: str) -> None:
    if not metadata.has_negative_no_read_supervision:
        raise OperationRefusedError(
            "negative_no_read_supervision_required",
            operation,
            "the bound development corpus lacks both notation and adjudicated no-read examples; "
            "no-read calibration, trust thresholds, and promotion gates are forbidden",
        )


def _exact_dict(value: object, fields, path: str) -> Dict[str, object]:
    if not isinstance(value, dict):
        raise ContractError("invalid_object", path, "must be an object")
    missing = sorted(fields.difference(value.keys()))
    unknown = sorted(set(value.keys()).difference(fields))
    if missing:
        raise ContractError("missing_checkpoint_field", path, ", ".join(missing))
    if unknown:
        raise ContractError("unknown_checkpoint_field", path, ", ".join(unknown))
    return dict(value)


def _positive_integer(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractError("invalid_integer", path, "must be a positive integer")
    return value


def _is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )
