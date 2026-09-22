"""Role-isolated corpus selection and portable feature loading."""

from __future__ import annotations

import importlib
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, Mapping, Sequence, Tuple

from .contracts import CorpusRecord, validate_dataset, validate_feature_artifacts
from .errors import ContractError, OperationRefusedError
from .models.output_contract import factorize_corpus_record
from .schema import FEATURE_SCHEMA


class PipelineRole(Enum):
    TRAINING = "development"
    CALIBRATION = "calibration"
    SEALED_EVALUATION = "sealed-evaluation"

    @property
    def split(self) -> str:
        return self.value


def require_optional_dependency(module_name: str, extra: str):
    try:
        return importlib.import_module(module_name)
    except (ImportError, ModuleNotFoundError) as error:
        raise OperationRefusedError(
            "missing_optional_dependency",
            module_name,
            f"install the recognition_ml[{extra}] dependency set: {error}",
        )


def select_role_records(
    records: Sequence[CorpusRecord],
    role: PipelineRole,
) -> Tuple[CorpusRecord, ...]:
    """Validate the complete corpus, then return exactly one immutable role."""

    validate_dataset(records, require_all_splits=True)
    selected = tuple(
        sorted(
            (
                item
                for item in records
                if item.split == role.split and item.has_model_supervision
            ),
            key=lambda r: r.sample_id,
        )
    )
    if not selected:
        raise ContractError("empty_role_partition", role.split, "at least one record is required")
    assert_exact_role(selected, role)
    return selected


def assert_exact_role(records: Sequence[CorpusRecord], role: PipelineRole) -> None:
    if not records:
        raise ContractError("empty_role_partition", role.split, "at least one record is required")
    unexpected = sorted({record.split for record in records if record.split != role.split})
    if unexpected:
        raise OperationRefusedError(
            "role_boundary_violation",
            role.split,
            f"expected only {role.split}; received {', '.join(unexpected)}",
        )
    excluded = sorted(record.sample_id for record in records if not record.has_model_supervision)
    if excluded:
        raise OperationRefusedError(
            "excluded_ground_truth_in_model_batch",
            role.split,
            f"records lack notation/no-read model supervision: {', '.join(excluded)}",
        )


def assert_prediction_sample_ids(
    records: Sequence[CorpusRecord],
    predictions: Mapping[str, object],
    path: str,
) -> None:
    expected = {record.sample_id for record in records}
    actual = set(predictions.keys())
    missing = sorted(expected.difference(actual))
    extra = sorted(actual.difference(expected))
    if missing:
        raise ContractError("missing_prediction_samples", path, ", ".join(missing))
    if extra:
        raise ContractError("unexpected_prediction_samples", path, ", ".join(extra))


@dataclass(frozen=True)
class NumpyFeatureBatch:
    trajectory: object
    raster: object
    targets: Mapping[str, object]
    active: Mapping[str, object]
    sample_ids: Tuple[str, ...]


def load_numpy_feature_batch(
    records: Sequence[CorpusRecord],
    data_root: Path,
) -> NumpyFeatureBatch:
    """Load already role-checked records into exact model input tensors."""

    if not records:
        raise ContractError("empty_feature_batch", "records", "at least one record is required")
    numpy = require_optional_dependency("numpy", "training")
    validate_feature_artifacts(records, data_root)

    trajectories = []
    rasters = []
    factor_targets = []
    root = data_root.resolve(strict=True)
    for record in records:
        trajectory_payload = root.joinpath(record.trajectory.relative_path).read_bytes()
        raster_payload = root.joinpath(record.raster.relative_path).read_bytes()
        trajectory = numpy.frombuffer(trajectory_payload, dtype="<f4").copy().reshape(
            FEATURE_SCHEMA.trajectory_shape
        )
        raster = numpy.frombuffer(raster_payload, dtype=numpy.uint8).copy().reshape(
            FEATURE_SCHEMA.raster_height,
            FEATURE_SCHEMA.raster_width,
            1,
        )
        trajectories.append(trajectory)
        rasters.append(raster.astype(numpy.float32) / 255.0)
        factor_targets.append(factorize_corpus_record(record))

    names = tuple(factor_targets[0].values.keys())
    targets: Dict[str, object] = {}
    active: Dict[str, object] = {}
    for name in names:
        values = [item.values[name] for item in factor_targets]
        if isinstance(values[0], tuple):
            targets[name] = numpy.asarray(values, dtype=numpy.float32)
        else:
            targets[name] = numpy.asarray(values, dtype=numpy.int64)
        active[name] = numpy.asarray(
            [item.active[name] for item in factor_targets], dtype=numpy.bool_
        )

    return NumpyFeatureBatch(
        trajectory=numpy.stack(trajectories).astype(numpy.float32),
        raster=numpy.stack(rasters).astype(numpy.float32),
        targets=targets,
        active=active,
        sample_ids=tuple(record.sample_id for record in records),
    )
