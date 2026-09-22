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

from .dataset import require_optional_dependency
from .errors import ContractError, OperationRefusedError
from .models.output_contract import HEAD_NAMES, OUTPUT_CONTRACT_VERSION, OUTPUT_HEADS
from .schema import FEATURE_SCHEMA


_COMPILED_DIRECTORY_FINGERPRINT_PREFIX = b"ichart-compiled-coreml-directory-v1\0"


@dataclass(frozen=True)
class CompiledCoreMLFingerprint:
    sha256: str
    byte_count: int


@dataclass(frozen=True)
class CoreMLExportReceipt:
    model_path: Path
    manifest_path: Path
    model_sha256: str
    model_byte_count: int
    detached_manifest_sha256: str
    output_head_names: Tuple[str, ...] = HEAD_NAMES
    is_calibrated: bool = False


def _require_sha256(value: str, path: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(
        character not in "0123456789abcdef" for character in value
    ):
        raise ContractError("invalid_sha256", path, "must be 64 lowercase hexadecimal characters")
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
    definitions = (
        ("x", -0.5, 0.5, None),
        ("y", -0.5, 0.5, None),
        ("delta_x", -1.0, 1.0, None),
        ("delta_y", -1.0, 1.0, None),
        ("arc_step", 0.0, math.sqrt(2.0), None),
        ("normalized_delta_time", 0.0, 1.0, None),
        ("timing_available", 0.0, 1.0, [0.0, 1.0]),
        ("stroke_start", 0.0, 1.0, [0.0, 1.0]),
        ("stroke_end", 0.0, 1.0, [0.0, 1.0]),
        ("valid", 0.0, 1.0, [0.0, 1.0]),
    )
    return [
        {
            "index": index,
            "name": name,
            "range": _value_range(minimum, maximum, allowed),
        }
        for index, (name, minimum, maximum, allowed) in enumerate(definitions)
    ]


def _preflight_export(
    model: object,
    model_path: Path,
    manifest_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
) -> None:
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
    if getattr(model, "output_contract_version", None) != OUTPUT_CONTRACT_VERSION:
        raise ContractError(
            "output_contract_version_mismatch",
            "model",
            f"expected {OUTPUT_CONTRACT_VERSION}",
        )
    if tuple(getattr(model, "output_head_names", ())) != HEAD_NAMES:
        raise ContractError("output_heads_mismatch", "model", "model head order is not frozen")


def build_swift_model_manifest(
    model_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
) -> Dict[str, object]:
    if not isinstance(model_identifier, str) or not model_identifier.strip():
        raise ContractError("invalid_model_identifier", "model_identifier", "must not be empty")
    fingerprint = fingerprint_compiled_model(model_path)
    if fingerprint.byte_count <= 0:
        raise ContractError(
            "empty_model_artifact", str(model_path), "compiled model must contain file bytes"
        )
    binary_range = _value_range(0.0, 255.0, [0.0, 255.0])
    raw_logit_range = _value_range()
    return {
        "manifestContractVersion": "chord-ink-model-manifest-v2",
        "outputContractVersion": OUTPUT_CONTRACT_VERSION,
        "modelIdentifier": model_identifier,
        "manifestArtifactSHA256": _require_sha256(
            detached_manifest_sha256, "detached_manifest_sha256"
        ),
        "modelArtifactSHA256": fingerprint.sha256,
        "modelArtifactByteCount": fingerprint.byte_count,
        "featureSchemaVersion": FEATURE_SCHEMA.version,
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


def export_uncalibrated_coreml(
    model: object,
    model_path: Path,
    manifest_path: Path,
    model_identifier: str,
    detached_manifest_sha256: str,
) -> CoreMLExportReceipt:
    """Export raw logits and bind the manifest to the compiled model directory."""

    _preflight_export(
        model,
        model_path,
        manifest_path,
        model_identifier,
        detached_manifest_sha256,
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

    model.eval()
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
            manifest = build_swift_model_manifest(
                staged_model,
                model_identifier,
                detached_manifest_sha256,
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
    )
