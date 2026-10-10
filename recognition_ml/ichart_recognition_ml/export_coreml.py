"""Fail-closed export of raw factor logits to a compiled Core ML artifact."""

from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import stat
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Tuple

from .checkpoint import CHECKPOINT_CONTRACT_VERSION
from .dataset import require_optional_dependency
from .errors import ContractError, OperationRefusedError
from .models.factory import require_model_architecture_id
from .models.output_contract import HEAD_NAMES, OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS
from .schema import FEATURE_SCHEMA, TRAJECTORY_CHANNEL_CONTRACTS
from .selection_contract import validate_development_selection_binding


_COMPILED_DIRECTORY_FINGERPRINT_PREFIX = b"ichart-compiled-coreml-directory-v1\0"
COREML_EXPORT_PARITY_CONTRACT_VERSION = "chord-ink-coreml-export-parity-v1"
COREML_EXPORT_PARITY_PROBE_COUNT = 2
COREML_EXPORT_PARITY_MAXIMUM_ABSOLUTE_ERROR = 1e-4
COREML_INFERENCE_COMPUTE_UNITS = "cpuOnly"


@dataclass(frozen=True)
class CompiledCoreMLFingerprint:
    sha256: str
    byte_count: int


@dataclass(frozen=True)
class CoreMLExportParityEvidence:
    contract_version: str
    probe_count: int
    maximum_absolute_error: float
    inference_compute_units: str


@dataclass(frozen=True)
class CoreMLTrainingProvenance:
    checkpoint_contract_version: str
    checkpoint_artifact_sha256: str
    checkpoint_artifact_byte_count: int
    model_architecture_id: str
    development_records_sha256: str
    development_sample_count: int
    development_writer_count: int
    development_selection_authority: str
    development_selection_report_sha256: str | None


@dataclass(frozen=True)
class CoreMLExportReceipt:
    model_path: Path
    manifest_path: Path
    model_sha256: str
    model_byte_count: int
    detached_manifest_sha256: str
    parity_evidence: CoreMLExportParityEvidence
    output_head_names: Tuple[str, ...] = HEAD_NAMES
    is_calibrated: bool = False


def _require_sha256(value: str, path: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(
        character not in "0123456789abcdef" for character in value
    ):
        raise ContractError("invalid_sha256", path, "must be 64 lowercase hexadecimal characters")
    return value


def _require_positive_integer(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ContractError("invalid_integer", path, "must be a positive integer")
    return value


def _validate_training_provenance(
    value: object,
    model: object | None = None,
) -> CoreMLTrainingProvenance:
    if not isinstance(value, CoreMLTrainingProvenance):
        raise ContractError(
            "missing_training_provenance",
            "training_provenance",
            "an exact loaded-checkpoint provenance record is required",
        )
    if value.checkpoint_contract_version != CHECKPOINT_CONTRACT_VERSION:
        raise ContractError(
            "checkpoint_contract_version_mismatch",
            "training_provenance.checkpoint_contract_version",
            f"expected {CHECKPOINT_CONTRACT_VERSION}",
        )
    _require_sha256(
        value.checkpoint_artifact_sha256,
        "training_provenance.checkpoint_artifact_sha256",
    )
    _require_positive_integer(
        value.checkpoint_artifact_byte_count,
        "training_provenance.checkpoint_artifact_byte_count",
    )
    architecture_id = require_model_architecture_id(value.model_architecture_id)
    _require_sha256(
        value.development_records_sha256,
        "training_provenance.development_records_sha256",
    )
    _require_positive_integer(
        value.development_sample_count,
        "training_provenance.development_sample_count",
    )
    _require_positive_integer(
        value.development_writer_count,
        "training_provenance.development_writer_count",
    )
    if value.development_writer_count > value.development_sample_count:
        raise ContractError(
            "invalid_integer",
            "training_provenance.development_writer_count",
            "must not exceed development_sample_count",
        )
    validate_development_selection_binding(
        value.development_selection_authority,
        value.development_selection_report_sha256,
    )
    if model is not None and getattr(model, "model_architecture_id", None) != architecture_id:
        raise ContractError(
            "model_architecture_mismatch",
            "training_provenance.model_architecture_id",
            "provenance does not describe the model being exported",
        )
    return value


def _compiled_files(root: Path) -> Iterable[Tuple[str, Path, int]]:
    if root.is_symlink() or not root.is_dir():
        raise ContractError(
            "compiled_model_artifact_is_not_directory",
            str(root),
            "compiled Core ML artifact must be a non-symlink directory",
        )

    entries = []
    for current_root, directory_names, file_names in os.walk(root, followlinks=False):
        current = Path(current_root)
        for name in tuple(directory_names):
            candidate = current / name
            if candidate.is_symlink():
                raise ContractError(
                    "compiled_model_artifact_contains_symbolic_link",
                    candidate.relative_to(root).as_posix(),
                    "symbolic links are not permitted",
                )
            mode = candidate.lstat().st_mode
            if not stat.S_ISDIR(mode):
                raise ContractError(
                    "compiled_model_artifact_contains_unsupported_entry",
                    candidate.relative_to(root).as_posix(),
                    "only directories and regular files are permitted",
                )
        for name in file_names:
            candidate = current / name
            relative = candidate.relative_to(root).as_posix()
            if candidate.is_symlink():
                raise ContractError(
                    "compiled_model_artifact_contains_symbolic_link",
                    relative,
                    "symbolic links are not permitted",
                )
            metadata = candidate.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise ContractError(
                    "compiled_model_artifact_contains_unsupported_entry",
                    relative,
                    "only directories and regular files are permitted",
                )
            entries.append((relative, candidate, metadata.st_size))
    return tuple(sorted(entries, key=lambda entry: entry[0]))


def fingerprint_compiled_model(directory: Path) -> CompiledCoreMLFingerprint:
    """Match ``ChordInkCoreMLModelRuntime.fingerprintCompiledModel`` byte-for-byte."""

    if directory.is_symlink():
        raise ContractError(
            "compiled_model_artifact_is_not_directory",
            str(directory),
            "compiled Core ML artifact must be a non-symlink directory",
        )
    root = directory.resolve(strict=True)
    digest = hashlib.sha256()
    digest.update(_COMPILED_DIRECTORY_FINGERPRINT_PREFIX)
    total = 0
    for relative, path, expected_size in _compiled_files(root):
        encoded_path = relative.encode("utf-8")
        digest.update(struct.pack(">Q", len(encoded_path)))
        digest.update(encoded_path)
        digest.update(struct.pack(">Q", expected_size))
        observed = 0
        with path.open("rb") as stream:
            while True:
                chunk = stream.read(1_048_576)
                if not chunk:
                    break
                digest.update(chunk)
                observed += len(chunk)
        if observed != expected_size:
            raise ContractError(
                "compiled_model_artifact_changed_while_reading",
                relative,
                f"expected {expected_size} bytes, observed {observed}",
            )
        total += observed
    return CompiledCoreMLFingerprint(digest.hexdigest(), total)


def _value_range(minimum=None, maximum=None, allowed=None) -> Dict[str, object]:
    return {
        "minimumInclusive": minimum,
        "maximumInclusive": maximum,
        "allowedDiscreteValues": allowed,
        "finiteValuesRequired": True,
    }


def _trajectory_channels():
    return [
        {
            "index": contract.index,
            "name": contract.name,
            "range": _value_range(
                contract.minimum_inclusive,
                contract.maximum_inclusive,
                None
                if contract.allowed_discrete_values is None
                else list(contract.allowed_discrete_values),
            ),
        }
        for contract in TRAJECTORY_CHANNEL_CONTRACTS
    ]


def _coreml_feature_map(features, expected_names, path):
    names = [feature.name for feature in features]
    if len(names) != len(set(names)) or sorted(names) != sorted(expected_names):
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            path,
            f"expected {sorted(expected_names)}, got {sorted(names)}",
        )
    return {feature.name: feature for feature in features}


def _normalize_coreml_source_spec(spec, coremltools) -> None:
    """Bind converter-omitted output shapes and reject other interface drift.

    Core ML Tools 9's neural-network converter leaves tuple-output shapes empty
    even though the graph produces fixed-size tensors. The Swift runtime rightly
    treats that as unverifiable. Fill only those missing declarations from the
    frozen head contract; compiled-model parity separately verifies the graph's
    actual finite logit counts.
    """

    float32 = coremltools.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    grayscale = coremltools.proto.FeatureTypes_pb2.ImageFeatureType.GRAYSCALE
    inputs = _coreml_feature_map(
        spec.description.input,
        ("trajectory", "raster"),
        "source_model.inputs",
    )
    outputs = _coreml_feature_map(
        spec.description.output,
        HEAD_NAMES,
        "source_model.outputs",
    )

    trajectory = inputs["trajectory"]
    if trajectory.type.WhichOneof("Type") != "multiArrayType":
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.trajectory",
            "must be a multi-array",
        )
    if trajectory.type.isOptional:
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.trajectory",
            "must not be optional",
        )
    trajectory_type = trajectory.type.multiArrayType
    if tuple(trajectory_type.shape) != tuple(FEATURE_SCHEMA.trajectory_shape):
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.trajectory.shape",
            f"expected {tuple(FEATURE_SCHEMA.trajectory_shape)}, "
            f"got {tuple(trajectory_type.shape)}",
        )
    if trajectory_type.dataType != float32:
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.trajectory.data_type",
            "must be float32",
        )

    raster = inputs["raster"]
    if raster.type.WhichOneof("Type") != "imageType":
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.raster",
            "must be an image",
        )
    if raster.type.isOptional:
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.raster",
            "must not be optional",
        )
    raster_type = raster.type.imageType
    raster_shape = (raster_type.height, raster_type.width)
    expected_raster_shape = (FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width)
    if raster_shape != expected_raster_shape:
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.raster.shape",
            f"expected {expected_raster_shape}, got {raster_shape}",
        )
    if raster_type.colorSpace != grayscale:
        raise OperationRefusedError(
            "coreml_source_interface_mismatch",
            "source_model.inputs.raster.color_space",
            "must be grayscale",
        )

    for head in OUTPUT_HEADS:
        output = outputs[head.name]
        path = f"source_model.outputs.{head.name}"
        if output.type.WhichOneof("Type") != "multiArrayType":
            raise OperationRefusedError(
                "coreml_source_interface_mismatch",
                path,
                "must be a multi-array",
            )
        if output.type.isOptional:
            raise OperationRefusedError(
                "coreml_source_interface_mismatch",
                path,
                "must not be optional",
            )
        output_type = output.type.multiArrayType
        if not output_type.shape:
            output_type.shape.extend(head.shape)
        if tuple(output_type.shape) != head.shape:
            raise OperationRefusedError(
                "coreml_source_interface_mismatch",
                f"{path}.shape",
                f"expected {head.shape}, got {tuple(output_type.shape)}",
            )
        if output_type.dataType != float32:
            raise OperationRefusedError(
                "coreml_source_interface_mismatch",
                f"{path}.data_type",
                "must be float32",
            )


def _bind_coreml_source_interface(converted, coremltools):
    spec = converted.get_spec()
    _normalize_coreml_source_spec(spec, coremltools)
    bound = coremltools.models.MLModel(spec)
    _normalize_coreml_source_spec(bound.get_spec(), coremltools)
    return bound


def _preflight_export(
    model: object,
    model_path: Path,
    manifest_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
    training_provenance: CoreMLTrainingProvenance | None,
) -> CoreMLTrainingProvenance:
    if model_path.suffix != ".mlmodelc":
        raise OperationRefusedError(
            "unsupported_coreml_container",
            str(model_path),
            "export the exact compiled .mlmodelc directory consumed by the app",
        )
    if model_path == manifest_path:
        raise OperationRefusedError(
            "artifact_path_collision", str(model_path), "model and manifest paths must differ"
        )
    if model_path.exists() or manifest_path.exists():
        raise OperationRefusedError(
            "export_would_overwrite", str(model_path), "existing artifacts are never overwritten"
        )
    if not isinstance(model_identifier, str) or not model_identifier.strip():
        raise ContractError("invalid_model_identifier", "model_identifier", "must not be empty")
    _require_sha256(detached_manifest_sha256, "detached_manifest_sha256")
    training_provenance = _validate_training_provenance(training_provenance, model)
    if getattr(model, "output_contract_version", None) != OUTPUT_CONTRACT_VERSION:
        raise ContractError(
            "output_contract_version_mismatch",
            "model",
            f"expected {OUTPUT_CONTRACT_VERSION}",
        )
    if tuple(getattr(model, "output_head_names", ())) != HEAD_NAMES:
        raise ContractError("output_heads_mismatch", "model", "model head order is not frozen")
    return training_provenance


def build_swift_model_manifest(
    model_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
    parity_evidence: CoreMLExportParityEvidence,
    training_provenance: CoreMLTrainingProvenance,
) -> Dict[str, object]:
    if not isinstance(model_identifier, str) or not model_identifier.strip():
        raise ContractError("invalid_model_identifier", "model_identifier", "must not be empty")
    fingerprint = fingerprint_compiled_model(model_path)
    if fingerprint.byte_count <= 0:
        raise ContractError(
            "empty_model_artifact", str(model_path), "compiled model must contain file bytes"
        )
    _validate_parity_evidence(parity_evidence)
    training_provenance = _validate_training_provenance(training_provenance)
    binary_range = _value_range(0.0, 255.0, [0.0, 255.0])
    raw_logit_range = _value_range()
    return {
        "manifestContractVersion": "chord-ink-model-manifest-v4",
        "outputContractVersion": OUTPUT_CONTRACT_VERSION,
        "modelIdentifier": model_identifier,
        "manifestArtifactSHA256": _require_sha256(
            detached_manifest_sha256, "detached_manifest_sha256"
        ),
        "modelArtifactSHA256": fingerprint.sha256,
        "modelArtifactByteCount": fingerprint.byte_count,
        "trainingProvenance": {
            "checkpointContractVersion": training_provenance.checkpoint_contract_version,
            "checkpointArtifactSHA256": training_provenance.checkpoint_artifact_sha256,
            "checkpointArtifactByteCount": training_provenance.checkpoint_artifact_byte_count,
            "modelArchitectureID": training_provenance.model_architecture_id,
            "developmentRecordsSHA256": training_provenance.development_records_sha256,
            "developmentSampleCount": training_provenance.development_sample_count,
            "developmentWriterCount": training_provenance.development_writer_count,
            "developmentSelectionAuthority": (
                training_provenance.development_selection_authority
            ),
            "developmentSelectionReportSHA256": (
                training_provenance.development_selection_report_sha256
            ),
        },
        "featureSchemaVersion": FEATURE_SCHEMA.version,
        "inferenceComputeUnits": parity_evidence.inference_compute_units,
        "exportParity": {
            "contractVersion": parity_evidence.contract_version,
            "probeCount": parity_evidence.probe_count,
            "maximumAbsoluteError": parity_evidence.maximum_absolute_error,
        },
        "trajectoryInput": {
            "name": "trajectory",
            "shape": list(FEATURE_SCHEMA.trajectory_shape),
            "numericType": "float32",
            "layout": "BSC",
            "scaling": "trajectoryFeatureV1Channelwise",
            "valueSemantics": "trajectoryFeatureV1",
            "range": _value_range(-math.sqrt(2.0), math.sqrt(2.0)),
            "channels": _trajectory_channels(),
        },
        "rasterInput": {
            "name": "raster",
            "shape": [1, FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width, 1],
            "numericType": "uint8",
            "layout": "BHWC",
            "scaling": "identity",
            "valueSemantics": "binaryInkMask",
            "range": binary_range,
            "channels": [{"index": 0, "name": "ink_mask", "range": binary_range}],
        },
        "outputHeads": [
            {
                "name": head.name,
                "shape": list(head.shape),
                "labels": list(head.labels),
                "numericType": "float32",
                "layout": "BC",
                "scaling": "identity",
                "valueSemantics": "rawLogit",
                "range": raw_logit_range,
            }
            for head in OUTPUT_HEADS
        ],
    }


def _validate_parity_evidence(value: CoreMLExportParityEvidence) -> None:
    if not isinstance(value, CoreMLExportParityEvidence):
        raise ContractError("missing_export_parity", "parity_evidence", "evidence is required")
    if value.contract_version != COREML_EXPORT_PARITY_CONTRACT_VERSION:
        raise ContractError(
            "export_parity_contract_mismatch",
            "parity_evidence.contract_version",
            f"expected {COREML_EXPORT_PARITY_CONTRACT_VERSION}",
        )
    if value.probe_count != COREML_EXPORT_PARITY_PROBE_COUNT:
        raise ContractError(
            "export_parity_probe_count_mismatch",
            "parity_evidence.probe_count",
            f"expected {COREML_EXPORT_PARITY_PROBE_COUNT}",
        )
    if value.inference_compute_units != COREML_INFERENCE_COMPUTE_UNITS:
        raise ContractError(
            "export_compute_units_mismatch",
            "parity_evidence.inference_compute_units",
            f"expected {COREML_INFERENCE_COMPUTE_UNITS}",
        )
    if (
        not isinstance(value.maximum_absolute_error, (int, float))
        or isinstance(value.maximum_absolute_error, bool)
        or not math.isfinite(float(value.maximum_absolute_error))
        or float(value.maximum_absolute_error) < 0
        or float(value.maximum_absolute_error) > COREML_EXPORT_PARITY_MAXIMUM_ABSOLUTE_ERROR
    ):
        raise ContractError(
            "export_parity_error_exceeded",
            "parity_evidence.maximum_absolute_error",
            f"must be finite and at most {COREML_EXPORT_PARITY_MAXIMUM_ABSOLUTE_ERROR}",
        )


def _parity_probe_inputs(numpy):
    zero_trajectory = numpy.zeros(tuple(FEATURE_SCHEMA.trajectory_shape), dtype=numpy.float32)
    zero_raster = numpy.zeros(
        (FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width),
        dtype=numpy.uint8,
    )

    structured_trajectory = zero_trajectory.copy()
    positions = numpy.linspace(-0.5, 0.5, FEATURE_SCHEMA.trajectory_shape[1], dtype=numpy.float32)
    structured_trajectory[0, :, 0] = positions
    structured_trajectory[0, :, 1] = positions[::-1]
    structured_trajectory[0, 1:, 2] = numpy.diff(positions)
    structured_trajectory[0, 1:, 3] = numpy.diff(positions[::-1])
    structured_trajectory[0, :, 5] = 0.25
    structured_trajectory[0, :, 6] = 1
    structured_trajectory[0, 0, 7] = 1
    structured_trajectory[0, -1, 8] = 1
    structured_trajectory[0, :, 9] = 1
    structured_raster = zero_raster.copy()
    for row in range(FEATURE_SCHEMA.raster_height):
        column = (row * 5 + 17) % FEATURE_SCHEMA.raster_width
        structured_raster[row, column : min(column + 3, FEATURE_SCHEMA.raster_width)] = 255
    return (
        (zero_trajectory, zero_raster),
        (structured_trajectory, structured_raster),
    )


def _validate_compiled_coreml_parity(model, compiled_model_path, torch, coremltools):
    numpy = require_optional_dependency("numpy", "export")
    image_module = require_optional_dependency("PIL.Image", "export")
    try:
        compiled = coremltools.models.CompiledMLModel(
            str(compiled_model_path),
            compute_units=coremltools.ComputeUnit.CPU_ONLY,
        )
    except Exception as error:
        raise OperationRefusedError(
            "coreml_parity_runtime_failed", "export", str(error)
        ) from error

    maximum_absolute_error = 0.0
    for probe_index, (trajectory, raster_u8) in enumerate(_parity_probe_inputs(numpy)):
        raster_float = (raster_u8.astype(numpy.float32) / 255.0)[None, :, :, None]
        try:
            with torch.no_grad():
                expected = model(
                    torch.from_numpy(trajectory).unsqueeze(0),
                    torch.from_numpy(raster_float),
                )
            actual = compiled.predict(
                {
                    "trajectory": trajectory,
                    "raster": image_module.fromarray(raster_u8),
                }
            )
        except Exception as error:
            raise OperationRefusedError(
                "coreml_parity_prediction_failed",
                f"export.probe[{probe_index}]",
                str(error),
            ) from error
        if set(actual) != set(HEAD_NAMES):
            raise OperationRefusedError(
                "coreml_parity_output_mismatch",
                f"export.probe[{probe_index}]",
                "compiled output names do not match the frozen heads",
            )
        for head in OUTPUT_HEADS:
            expected_values = expected[head.name].detach().cpu().numpy().reshape(-1)
            actual_values = numpy.asarray(actual[head.name], dtype=numpy.float32).reshape(-1)
            if actual_values.size != expected_values.size or not numpy.isfinite(actual_values).all():
                raise OperationRefusedError(
                    "coreml_parity_output_mismatch",
                    f"export.probe[{probe_index}].{head.name}",
                    "compiled output has the wrong size or nonfinite values",
                )
            absolute_error = float(numpy.max(numpy.abs(expected_values - actual_values)))
            maximum_absolute_error = max(maximum_absolute_error, absolute_error)
            if absolute_error > COREML_EXPORT_PARITY_MAXIMUM_ABSOLUTE_ERROR:
                raise OperationRefusedError(
                    "coreml_parity_error_exceeded",
                    f"export.probe[{probe_index}].{head.name}",
                    f"maximum absolute error {absolute_error} exceeds "
                    f"{COREML_EXPORT_PARITY_MAXIMUM_ABSOLUTE_ERROR}",
                )
            if not head.is_independent_bernoulli and int(numpy.argmax(expected_values)) != int(
                numpy.argmax(actual_values)
            ):
                raise OperationRefusedError(
                    "coreml_parity_ranking_changed",
                    f"export.probe[{probe_index}].{head.name}",
                    "compiled categorical winner differs from PyTorch",
                )
    evidence = CoreMLExportParityEvidence(
        contract_version=COREML_EXPORT_PARITY_CONTRACT_VERSION,
        probe_count=COREML_EXPORT_PARITY_PROBE_COUNT,
        maximum_absolute_error=maximum_absolute_error,
        inference_compute_units=COREML_INFERENCE_COMPUTE_UNITS,
    )
    _validate_parity_evidence(evidence)
    return evidence


def export_uncalibrated_coreml(
    model: object,
    model_path: Path,
    manifest_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
    training_provenance: CoreMLTrainingProvenance | None = None,
) -> CoreMLExportReceipt:
    """Export raw logits and bind the manifest to the compiled model directory."""

    training_provenance = _preflight_export(
        model,
        model_path,
        manifest_path,
        model_identifier,
        detached_manifest_sha256,
        training_provenance,
    )
    torch = require_optional_dependency("torch", "export")
    coremltools = require_optional_dependency("coremltools", "export")

    class OrderedOutputWrapper(torch.nn.Module):
        def __init__(self, wrapped):
            super().__init__()
            self.wrapped = wrapped

        def forward(self, trajectory, raster):
            values = self.wrapped(trajectory, raster)
            return tuple(values[name] for name in HEAD_NAMES)

    class CoreMLInputAdapter(torch.nn.Module):
        def __init__(self, wrapped):
            super().__init__()
            self.wrapped = wrapped

        def forward(self, trajectory, raster):
            # ImageType supplies NCHW Float32 after applying the 1/255 scale.
            return self.wrapped(trajectory.unsqueeze(0), raster.permute(0, 2, 3, 1))

    model = model.cpu().eval()
    wrapper = CoreMLInputAdapter(OrderedOutputWrapper(model)).eval()
    trajectory = torch.zeros(tuple(FEATURE_SCHEMA.trajectory_shape), dtype=torch.float32)
    raster = torch.zeros(
        (1, 1, FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width),
        dtype=torch.float32,
    )
    traced = torch.jit.trace(wrapper, (trajectory, raster), strict=True)
    try:
        converted = coremltools.convert(
            traced,
            convert_to="neuralnetwork",
            inputs=[
                coremltools.TensorType(
                    name="trajectory", shape=tuple(FEATURE_SCHEMA.trajectory_shape)
                ),
                coremltools.ImageType(
                    name="raster",
                    shape=(1, 1, FEATURE_SCHEMA.raster_height, FEATURE_SCHEMA.raster_width),
                    color_layout=coremltools.colorlayout.GRAYSCALE,
                    scale=1.0 / 255.0,
                ),
            ],
            outputs=[coremltools.TensorType(name=name) for name in HEAD_NAMES],
        )
        converted = _bind_coreml_source_interface(converted, coremltools)
    except OperationRefusedError:
        raise
    except Exception as error:
        raise OperationRefusedError("coreml_conversion_failed", "export", str(error)) from error

    model_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ichart-coreml-export-", dir=model_path.parent) as temp:
        temporary_root = Path(temp)
        source_model = temporary_root / "source.mlmodel"
        staged_model = temporary_root / model_path.name
        staged_manifest = temporary_root / manifest_path.name
        try:
            converted.save(str(source_model))
            compiled_result = Path(coremltools.models.utils.compile_model(str(source_model)))
            if not compiled_result.is_dir():
                raise OperationRefusedError(
                    "coreml_compilation_failed",
                    str(compiled_result),
                    "Core ML compiler did not produce a directory",
                )
            shutil.copytree(compiled_result, staged_model, symlinks=True)
            parity_evidence = _validate_compiled_coreml_parity(
                model,
                staged_model,
                torch,
                coremltools,
            )
            manifest = build_swift_model_manifest(
                staged_model,
                model_identifier,
                detached_manifest_sha256,
                parity_evidence,
                training_provenance,
            )
            staged_manifest.write_text(
                json.dumps(
                    manifest,
                    ensure_ascii=False,
                    allow_nan=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n",
                encoding="utf-8",
            )
        except (ContractError, OperationRefusedError):
            raise
        except Exception as error:
            raise OperationRefusedError("coreml_compilation_failed", "export", str(error)) from error

        os.replace(staged_model, model_path)
        try:
            os.replace(staged_manifest, manifest_path)
        except Exception:
            shutil.rmtree(model_path, ignore_errors=True)
            raise

    return CoreMLExportReceipt(
        model_path=model_path,
        manifest_path=manifest_path,
        model_sha256=manifest["modelArtifactSHA256"],
        model_byte_count=manifest["modelArtifactByteCount"],
        detached_manifest_sha256=detached_manifest_sha256,
        parity_evidence=parity_evidence,
    )
