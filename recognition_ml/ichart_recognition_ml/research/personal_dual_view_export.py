"""Isolated Core ML export and synthetic parity fixture for frozen glyph arms.

This module never loads the UJI source, fits a tensor, reads private ink, or
modifies an app resource.  It only verifies the already-frozen three-arm fit,
converts those exact checkpoints, and records synthetic feature/runtime parity.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import platform
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch import nn

from ..contracts import canonical_json_bytes, strict_json_loads
from ..features import InkPoint, InkStroke, encode_trajectory, rasterize
from ..schema import FEATURE_SCHEMA
from . import personal_dual_view as dual
from . import personal_dual_view_scoring as scoring


EXPORT_VERSION = "personal-dual-view-coreml-export-v1"
FIXTURE_VERSION = "personal-dual-view-coreml-parity-v1"
FIT_DIRECTORY = Path(
    "/Users/benirossman/.local/share/ichart/recognition-development/"
    "dual-view-glyph-20260930.ttfIcd/fit"
)
FIT_RECEIPT_SHA256 = "ce60efb539ce4d0897e0c339e6d1e1d90485ec07798aa1da499047482724a46f"
PARITY_PROTOCOL_PATH = "docs/personal-dual-view-runtime-parity-protocol-2026-09-30.md"
PARITY_PROTOCOL_SHA256 = "795b34713affc4ebeb85c9718faf56e6ac17c63f6dfb37105208a655015c0ad9"
EXPORT_MODULE_PATH = (
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view_export.py"
)
EXPORT_TEST_PATH = "recognition_ml/tests/test_personal_dual_view_export.py"
SWIFT_GATE_PATH = "recognition_ml/tests/PersonalDualViewCoreMLParityGate.swift"
APP_FEATURE_PATHS = (
    "iChart/Recognition/InkTrajectoryTypes.swift",
    "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
    "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
    "iChart/Recognition/Learned/ChordInkRasterizer.swift",
    "iChart/Recognition/Learned/ChordInkTrajectoryFeatureEncoder.swift",
)
BOUND_SOURCE_PATHS = tuple(
    sorted(
        set(
            scoring.CODE_PATHS
            + (
                PARITY_PROTOCOL_PATH,
                EXPORT_MODULE_PATH,
                EXPORT_TEST_PATH,
                SWIFT_GATE_PATH,
            )
            + APP_FEATURE_PATHS
        )
    )
)
ARMS = dual.ARMS
WEIGHT_SEED = dual.SEED
FEATURE_SCHEMA_VERSION = FEATURE_SCHEMA.version
SCOPE = "research-runtime-parity-only-not-production"
EMBEDDING_TOLERANCE = 0.0001
LOGIT_TOLERANCE = 0.001
CASE_IDS = (
    "singlePoint",
    "horizontal",
    "vertical",
    "corner",
    "curve",
    "unequalMultiStroke",
    "reversedDirection",
    "reversedStrokeOrder",
    "timedMultiStroke",
    "retimedMultiStroke",
    "translatedMultiStroke",
    "scaledMultiStroke",
)
MODEL_METADATA_KEYS = (
    "ichart.featureSchemaVersion",
    "ichart.fitReceiptSHA256",
    "ichart.modelArm",
    "ichart.scope",
    "ichart.vocabularySHA256",
    "ichart.weightSeed",
    "ichart.weightsSHA256",
)


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _absolute_unaliased(path: Path, *, kind: str) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{kind} path must be absolute and canonical")
    try:
        resolved = path.resolve(strict=True)
    except (FileNotFoundError, RuntimeError) as error:
        raise ValueError(f"{kind} does not exist") from error
    if path.is_symlink() or resolved != path:
        raise ValueError(f"{kind} aliases and symlinks are forbidden")
    return path


def _file(path: Path, *, kind: str) -> Path:
    path = _absolute_unaliased(path, kind=kind)
    if not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"{kind} must be a regular file")
    return path


def _directory(path: Path, *, kind: str) -> Path:
    path = _absolute_unaliased(path, kind=kind)
    if not stat.S_ISDIR(path.stat().st_mode):
        raise ValueError(f"{kind} must be a directory")
    return path


def _new_directory(path: Path) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink():
        raise ValueError("Output must be a new absolute canonical directory")
    _directory(path.parent, kind="output parent")
    path.mkdir(mode=0o700)
    return path


def _write(path: Path, payload: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(payload)


def _canonical_json(path: Path, *, kind: str) -> tuple[dict, bytes]:
    path = _file(path, kind=kind)
    payload = path.read_bytes()
    try:
        value = strict_json_loads(payload.decode("utf-8"), str(path))
    except UnicodeDecodeError as error:
        raise ValueError(f"{kind} is not UTF-8") from error
    if not isinstance(value, dict) or canonical_json_bytes(value) != payload:
        raise ValueError(f"{kind} is not canonical JSON")
    return value, payload


def source_artifacts() -> list[dict[str, object]]:
    root = _repo_root()
    artifacts = []
    for relative in BOUND_SOURCE_PATHS:
        path = _file(root / relative, kind=f"bound source {relative}")
        payload = path.read_bytes()
        artifacts.append(
            {"byteCount": len(payload), "relativePath": relative, "sha256": sha256(payload)}
        )
    if next(item for item in artifacts if item["relativePath"] == PARITY_PROTOCOL_PATH)[
        "sha256"
    ] != PARITY_PROTOCOL_SHA256:
        raise ValueError("Runtime parity protocol differs from its frozen digest")
    return artifacts


def _input_features() -> list[dict[str, object]]:
    return sorted(
        (
            {"dataType": "float32", "name": "inkTrajectory", "shape": [1, 1, 256, 10]},
            {"dataType": "float32", "name": "inkRaster", "shape": [1, 1, 96, 256]},
        ),
        key=lambda value: value["name"],
    )


def _output_features() -> list[dict[str, object]]:
    return sorted(
        (
            {"dataType": "float32", "name": "personalEmbedding", "shape": [1, 128]},
            {"dataType": "float32", "name": "genericLogits", "shape": [1, 97]},
        ),
        key=lambda value: value["name"],
    )


def _tolerances() -> dict[str, float]:
    return {
        "genericLogitsMaximumAbsoluteError": LOGIT_TOLERANCE,
        "personalEmbeddingMaximumAbsoluteError": EMBEDDING_TOLERANCE,
    }


def _invariance_contract() -> dict[str, object]:
    return {
        "inactiveInputProbe": {
            "zeroRasterForArms": ["trajectoryOnly"],
            "zeroTrajectoryForArms": ["rasterOnly"],
        },
        "timingProbe": {"trajectoryChannel5": 0.37, "trajectoryChannel6": 1.0},
    }


@dataclass(frozen=True)
class FrozenFit:
    directory: Path
    receipt: dict
    receipt_bytes: bytes
    weight_paths: dict[str, Path]
    weight_payloads: dict[str, bytes]
    models: dict[str, dual.PersonalDualViewEncoder]


def load_frozen_fit(path: Path) -> FrozenFit:
    path = _directory(path, kind="frozen fit")
    if path != FIT_DIRECTORY:
        raise ValueError("Only the predeclared frozen fit directory may be exported")
    receipt, receipt_bytes = _canonical_json(path / dual.FIT_RECEIPT_NAME, kind="fit receipt")
    if sha256(receipt_bytes) != FIT_RECEIPT_SHA256:
        raise ValueError("Fit receipt does not match the predeclared frozen digest")
    code = scoring.code_identity()
    if (
        receipt.get("codeSHA256") != code
        or receipt.get("protocolSHA256") != code[scoring.PROTOCOL_PATH]
    ):
        raise ValueError("Original producer/scorer code or protocol changed")
    frozen_protocol = _file(path / dual.FROZEN_PROTOCOL_NAME, kind="fit protocol")
    if sha256(frozen_protocol.read_bytes()) != receipt["protocolSHA256"]:
        raise ValueError("Fit protocol bytes changed")
    if receipt.get("weightFiles") != {arm: f"weights/{arm}.pt" for arm in ARMS}:
        raise ValueError("Unexpected frozen checkpoint paths")
    weight_paths = {
        arm: _file(path / receipt["weightFiles"][arm], kind=f"{arm} checkpoint")
        for arm in ARMS
    }
    weight_payloads = {arm: weight_paths[arm].read_bytes() for arm in ARMS}
    weights = {arm: sha256(weight_payloads[arm]) for arm in ARMS}
    if weights != receipt.get("weightsSHA256"):
        raise ValueError("Frozen checkpoint bytes changed")
    scoring.validate_fit_receipt(receipt, code, code[scoring.PROTOCOL_PATH], weights)
    fit_runtime = receipt["runtime"]
    if (
        fit_runtime["torch"] != str(torch.__version__)
        or fit_runtime["numpy"] != str(np.__version__)
        or fit_runtime["python"] != platform.python_version()
        or fit_runtime["platform"] != platform.platform()
    ):
        raise ValueError("Export runtime differs from the frozen fit runtime")
    # All receipt/code/protocol/weight bytes and all three hashes are checked
    # before deserializing the first checkpoint tensor.
    models = {
        arm: dual._load_checkpoint(weight_payloads[arm], arm, receipt["vocabularySHA256"]).eval()
        for arm in ARMS
    }
    return FrozenFit(path, receipt, receipt_bytes, weight_paths, weight_payloads, models)


def _stroke(
    points: Sequence[tuple[float, float, float | None]],
    creation_time_offset: float | None = None,
) -> InkStroke:
    return InkStroke(
        tuple(InkPoint(float(x), float(y), time) for x, y, time in points),
        creation_time_offset=creation_time_offset,
    )


def synthetic_cases() -> tuple[tuple[str, tuple[InkStroke, ...]], ...]:
    horizontal = ((-9, 0, None), (0, 0, None), (11, 0, None))
    first = ((-7, -4, None), (-3, 3, None), (2, 7, None), (8, 2, None))
    second = ((-5, 8, None), (6, -6, None))
    unequal = (_stroke(first), _stroke(second))
    timed = (
        _stroke(((-7, -4, 0.0), (-3, 3, 0.1), (2, 7, 0.2), (8, 2, 0.3)), 0.0),
        _stroke(((-5, 8, 0.0), (6, -6, 0.2)), 0.5),
    )
    retimed = (
        _stroke(((-7, -4, 0.0), (-3, 3, 0.25), (2, 7, 0.5), (8, 2, 0.75)), 4.0),
        _stroke(((-5, 8, 0.0), (6, -6, 0.9)), 7.0),
    )

    def transform(scale: float, dx: float, dy: float) -> tuple[InkStroke, ...]:
        return tuple(
            _stroke(tuple((x * scale + dx, y * scale + dy, None) for x, y, _ in points))
            for points in (first, second)
        )

    cases = (
        ("singlePoint", (_stroke(((1.25, -2.5, None),)),)),
        ("horizontal", (_stroke(horizontal),)),
        ("vertical", (_stroke(((0, -10, None), (0, 0, None), (0, 13, None))),)),
        ("corner", (_stroke(((-6, 7, None), (-6, -5, None), (8, -5, None))),)),
        ("curve", (_stroke(((-9, 4, None), (-7, 0, None), (-3, -5, None), (3, -6, None), (9, -1, None))),)),
        ("unequalMultiStroke", unequal),
        ("reversedDirection", (_stroke(tuple(reversed(horizontal))),)),
        ("reversedStrokeOrder", tuple(reversed(unequal))),
        ("timedMultiStroke", timed),
        ("retimedMultiStroke", retimed),
        ("translatedMultiStroke", transform(1.0, 103.0, -47.0)),
        ("scaledMultiStroke", transform(2.5, 0.0, 0.0)),
    )
    if tuple(identifier for identifier, _ in cases) != CASE_IDS:
        raise ValueError("Synthetic case cohort changed")
    return cases


def _raw_strokes(strokes: Sequence[InkStroke]) -> list[dict[str, object]]:
    result = []
    for stroke in strokes:
        result.append(
            {
                "creationTimeOffset": stroke.creation_time_offset,
                "points": [
                    {"timeOffset": point.time_offset, "x": point.x, "y": point.y}
                    for point in stroke.points
                ],
            }
        )
    return result


@dataclass(frozen=True)
class FeatureCase:
    case_id: str
    raw_strokes: list[dict[str, object]]
    trajectory: np.ndarray
    trajectory_bytes: bytes
    raster: np.ndarray
    raster_uint8: bytes
    raster_float32_bytes: bytes


def feature_cases() -> tuple[FeatureCase, ...]:
    result = []
    for case_id, strokes in synthetic_cases():
        trajectory_bytes = encode_trajectory(strokes).to_bytes()
        raster_uint8 = rasterize(strokes).pixels
        trajectory = np.frombuffer(trajectory_bytes, dtype="<f4").copy().reshape(1, 1, 256, 10)
        raster = (
            np.frombuffer(raster_uint8, dtype=np.uint8)
            .astype("<f4")
            .reshape(1, 1, 96, 256)
            / np.float32(255.0)
        )
        raster_float32_bytes = raster.astype("<f4", copy=False).tobytes(order="C")
        result.append(
            FeatureCase(
                case_id,
                _raw_strokes(strokes),
                trajectory,
                trajectory_bytes,
                raster,
                raster_uint8,
                raster_float32_bytes,
            )
        )
    return tuple(result)


def _vector(embedding: np.ndarray, logits: np.ndarray) -> dict[str, object]:
    embedding = np.asarray(embedding, dtype=np.float32)
    logits = np.asarray(logits, dtype=np.float32)
    if (
        embedding.shape != (1, 128)
        or logits.shape != (1, 97)
        or not np.isfinite(embedding).all()
        or not np.isfinite(logits).all()
        or abs(float(np.linalg.norm(embedding[0])) - 1.0) > EMBEDDING_TOLERANCE
    ):
        raise ValueError("Model output has wrong shape, nonfinite values, or nonunit embedding")
    return {
        "firstGenericArgmax": int(np.argmax(logits[0])),
        "genericLogits": [float(value) for value in logits[0]],
        "personalEmbedding": [float(value) for value in embedding[0]],
    }


def _torch_predict(
    model: dual.PersonalDualViewEncoder, trajectory: np.ndarray, raster: np.ndarray
) -> dict[str, object]:
    with torch.inference_mode():
        embedding, logits = model(
            torch.from_numpy(np.asarray(trajectory, dtype=np.float32).copy()),
            torch.from_numpy(np.asarray(raster, dtype=np.float32).copy()),
        )
    return _vector(embedding.detach().cpu().numpy(), logits.detach().cpu().numpy())


def _coreml_predict(runtime, trajectory: np.ndarray, raster: np.ndarray) -> dict[str, object]:
    output = runtime.predict(
        {
            "inkRaster": np.asarray(raster, dtype=np.float32),
            "inkTrajectory": np.asarray(trajectory, dtype=np.float32),
        }
    )
    if set(output) != {"personalEmbedding", "genericLogits"}:
        raise ValueError("Core ML prediction output names changed")
    return _vector(output["personalEmbedding"], output["genericLogits"])


def _maximum_difference(first: Sequence[float], second: Sequence[float]) -> float:
    if len(first) != len(second) or not first:
        raise ValueError("Cannot compare different output vectors")
    return max(abs(float(left) - float(right)) for left, right in zip(first, second))


def _parity(torch_vector: dict, coreml_vector: dict) -> dict[str, object]:
    result = {
        "embeddingMaximumAbsoluteError": _maximum_difference(
            torch_vector["personalEmbedding"], coreml_vector["personalEmbedding"]
        ),
        "firstGenericArgmaxEqual": (
            torch_vector["firstGenericArgmax"] == coreml_vector["firstGenericArgmax"]
        ),
        "logitsMaximumAbsoluteError": _maximum_difference(
            torch_vector["genericLogits"], coreml_vector["genericLogits"]
        ),
    }
    if (
        result["embeddingMaximumAbsoluteError"] > EMBEDDING_TOLERANCE
        or result["logitsMaximumAbsoluteError"] > LOGIT_TOLERANCE
        or result["firstGenericArgmaxEqual"] is not True
    ):
        raise ValueError("Torch/Core ML numerical parity failed")
    return result


def _invariance(torch_probe: dict, coreml_probe: dict, torch_base: dict, coreml_base: dict) -> dict:
    result = {
        "coreMLPythonEmbeddingMaximumAbsoluteError": _maximum_difference(
            coreml_probe["personalEmbedding"], coreml_base["personalEmbedding"]
        ),
        "coreMLPythonFirstGenericArgmaxEqual": (
            coreml_probe["firstGenericArgmax"] == coreml_base["firstGenericArgmax"]
        ),
        "coreMLPythonLogitsMaximumAbsoluteError": _maximum_difference(
            coreml_probe["genericLogits"], coreml_base["genericLogits"]
        ),
        "torchEmbeddingMaximumAbsoluteError": _maximum_difference(
            torch_probe["personalEmbedding"], torch_base["personalEmbedding"]
        ),
        "torchFirstGenericArgmaxEqual": (
            torch_probe["firstGenericArgmax"] == torch_base["firstGenericArgmax"]
        ),
        "torchLogitsMaximumAbsoluteError": _maximum_difference(
            torch_probe["genericLogits"], torch_base["genericLogits"]
        ),
    }
    if (
        result["coreMLPythonEmbeddingMaximumAbsoluteError"] > EMBEDDING_TOLERANCE
        or result["torchEmbeddingMaximumAbsoluteError"] > EMBEDDING_TOLERANCE
        or result["coreMLPythonLogitsMaximumAbsoluteError"] > LOGIT_TOLERANCE
        or result["torchLogitsMaximumAbsoluteError"] > LOGIT_TOLERANCE
        or result["coreMLPythonFirstGenericArgmaxEqual"] is not True
        or result["torchFirstGenericArgmaxEqual"] is not True
    ):
        raise ValueError("Timing or inactive-input invariance failed")
    return result


def _probe(
    model,
    runtime,
    trajectory,
    raster,
    torch_base,
    coreml_base,
) -> dict[str, object]:
    torch_probe = _torch_predict(model, trajectory, raster)
    coreml_probe = _coreml_predict(runtime, trajectory, raster)
    return {
        "coreMLPython": coreml_probe,
        "invariance": _invariance(
            torch_probe, coreml_probe, torch_base, coreml_base
        ),
        "parity": _parity(torch_probe, coreml_probe),
        "torch": torch_probe,
    }


def _metadata(arm: str, fit: FrozenFit) -> dict[str, str]:
    values = {
        "ichart.featureSchemaVersion": FEATURE_SCHEMA_VERSION,
        "ichart.fitReceiptSHA256": FIT_RECEIPT_SHA256,
        "ichart.modelArm": arm,
        "ichart.scope": SCOPE,
        "ichart.vocabularySHA256": fit.receipt["vocabularySHA256"],
        "ichart.weightSeed": str(WEIGHT_SEED),
        "ichart.weightsSHA256": fit.receipt["weightsSHA256"][arm],
    }
    if tuple(sorted(values)) != MODEL_METADATA_KEYS:
        raise ValueError("Core ML creator metadata keys changed")
    return values


class _ExportWrapper(nn.Module):
    def __init__(self, model: dual.PersonalDualViewEncoder):
        super().__init__()
        self.model = model

    def forward(self, ink_trajectory, ink_raster):
        return self.model(ink_trajectory, ink_raster)


def _validate_traced_output_contract(
    traced, trajectory: torch.Tensor, raster: torch.Tensor
) -> None:
    with torch.inference_mode():
        outputs = traced(trajectory, raster)
    if (
        not isinstance(outputs, tuple)
        or len(outputs) != 2
        or tuple(outputs[0].shape) != (1, 128)
        or tuple(outputs[1].shape) != (1, 97)
        or outputs[0].dtype != torch.float32
        or outputs[1].dtype != torch.float32
    ):
        raise ValueError("Traced Torch output shape or type changed")


def _validate_model_contract(runtime, coremltools, metadata: dict[str, str]) -> None:
    spec = runtime.get_spec()
    float32 = coremltools.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    for actual, expected in (
        (spec.description.input, _input_features()),
        (spec.description.output, _output_features()),
    ):
        by_name = {feature.name: feature for feature in actual}
        if set(by_name) != {item["name"] for item in expected}:
            raise ValueError("Core ML feature names changed or an inactive input was removed")
        for item in expected:
            feature = by_name[item["name"]]
            if (
                feature.type.WhichOneof("Type") != "multiArrayType"
                or list(feature.type.multiArrayType.shape) != item["shape"]
                or feature.type.multiArrayType.dataType != float32
                or feature.type.isOptional
            ):
                raise ValueError("Core ML feature shape/type/optionality changed")
    actual_metadata = dict(spec.description.metadata.userDefined)
    if actual_metadata != metadata:
        raise ValueError("Core ML creator metadata is missing, extra, or changed")


def package_tree_identity(path: Path) -> tuple[str, int]:
    path = _directory(path, kind="Core ML package")
    files = []
    for entry in path.rglob("*"):
        if entry.is_symlink():
            raise ValueError("Core ML package contains a symlink")
        if entry.is_dir():
            continue
        if not stat.S_ISREG(entry.stat().st_mode):
            raise ValueError("Core ML package contains an unsupported entry")
        files.append(entry)
    if not files:
        raise ValueError("Core ML package is empty")
    digest = hashlib.sha256()
    byte_count = 0
    for file in sorted(files, key=lambda value: value.relative_to(path).as_posix()):
        payload = file.read_bytes()
        byte_count += len(payload)
        digest.update(file.relative_to(path).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(payload).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest(), byte_count


def _convert_arm(coremltools, arm: str, fit: FrozenFit, package: Path):
    model = fit.models[arm].eval()
    example_trajectory = torch.zeros((1, 1, 256, 10), dtype=torch.float32)
    example_raster = torch.zeros((1, 1, 96, 256), dtype=torch.float32)
    traced = torch.jit.trace(
        _ExportWrapper(model).eval(),
        (example_trajectory, example_raster),
        strict=True,
        check_trace=True,
    )
    _validate_traced_output_contract(traced, example_trajectory, example_raster)
    converted = coremltools.convert(
        traced,
        inputs=[
            coremltools.TensorType(
                name="inkTrajectory", shape=(1, 1, 256, 10), dtype=np.float32
            ),
            coremltools.TensorType(
                name="inkRaster", shape=(1, 1, 96, 256), dtype=np.float32
            ),
        ],
        # Core ML Tools 9 rejects `shape=` on output TensorType declarations.
        # The fixed shapes are therefore derived from the traced graph above
        # and must independently survive in the saved model description below.
        outputs=[
            coremltools.TensorType(name="personalEmbedding", dtype=np.float32),
            coremltools.TensorType(name="genericLogits", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=coremltools.target.macOS13,
        compute_precision=coremltools.precision.FLOAT32,
        compute_units=coremltools.ComputeUnit.CPU_ONLY,
    )
    metadata = _metadata(arm, fit)
    converted.user_defined_metadata.clear()
    converted.user_defined_metadata.update(metadata)
    if package.exists():
        raise ValueError("Core ML package output already exists")
    converted.save(str(package))
    runtime = coremltools.models.MLModel(
        str(package), compute_units=coremltools.ComputeUnit.CPU_ONLY
    )
    _validate_model_contract(runtime, coremltools, metadata)
    return runtime


def _case_expected(
    arm: str,
    model,
    runtime,
    feature: FeatureCase,
) -> dict[str, object]:
    torch_base = _torch_predict(model, feature.trajectory, feature.raster)
    coreml_base = _coreml_predict(runtime, feature.trajectory, feature.raster)
    timing_trajectory = feature.trajectory.copy()
    timing_trajectory[:, :, :, 5] = np.float32(0.37)
    timing_trajectory[:, :, :, 6] = np.float32(1.0)
    timing_probe = _probe(
        model,
        runtime,
        timing_trajectory,
        feature.raster,
        torch_base,
        coreml_base,
    )
    inactive_probe = None
    if arm == "rasterOnly":
        inactive_probe = _probe(
            model,
            runtime,
            np.zeros_like(feature.trajectory),
            feature.raster,
            torch_base,
            coreml_base,
        )
    elif arm == "trajectoryOnly":
        inactive_probe = _probe(
            model,
            runtime,
            feature.trajectory,
            np.zeros_like(feature.raster),
            torch_base,
            coreml_base,
        )
    return {
        "coreMLPython": coreml_base,
        "inactiveInputProbe": inactive_probe,
        "parity": _parity(torch_base, coreml_base),
        "rasterFloat32LEBase64": base64.b64encode(feature.raster_float32_bytes).decode("ascii"),
        "rasterFloat32SHA256": sha256(feature.raster_float32_bytes),
        "rasterSHA256": sha256(feature.raster_uint8),
        "rasterUInt8Base64": base64.b64encode(feature.raster_uint8).decode("ascii"),
        "timingProbe": timing_probe,
        "torch": torch_base,
        "trajectoryFloat32LEBase64": base64.b64encode(feature.trajectory_bytes).decode("ascii"),
        "trajectorySHA256": sha256(feature.trajectory_bytes),
    }


def _fixture(
    arm: str,
    fit: FrozenFit,
    runtime,
    features: tuple[FeatureCase, ...],
    model_relative_path: str,
    package_tree_sha256: str,
    package_byte_count: int,
) -> dict[str, object]:
    cases = [
        {
            "caseID": feature.case_id,
            "expected": _case_expected(arm, fit.models[arm], runtime, feature),
            "rawStrokes": feature.raw_strokes,
        }
        for feature in features
    ]
    if [case["caseID"] for case in cases] != list(CASE_IDS):
        raise ValueError("Fixture case order or coverage changed")
    return {
        "cases": cases,
        "featureSchemaVersion": FEATURE_SCHEMA_VERSION,
        "fitSHA256": FIT_RECEIPT_SHA256,
        "inputFeatures": _input_features(),
        "invarianceChecks": _invariance_contract(),
        "modelArm": arm,
        "modelPackageByteCount": package_byte_count,
        "modelPackageRelativePath": model_relative_path,
        "modelPackageTreeSHA256": package_tree_sha256,
        "outputFeatures": _output_features(),
        "schemaVersion": FIXTURE_VERSION,
        "tolerances": _tolerances(),
        "vocabularySHA256": fit.receipt["vocabularySHA256"],
        "weightSeed": WEIGHT_SEED,
        "weightsSHA256": fit.receipt["weightsSHA256"][arm],
    }


def _snapshot(paths: Sequence[Path]) -> dict[Path, str]:
    return {path: sha256(path.read_bytes()) for path in paths}


def _assert_preserved(snapshot: Mapping[Path, str]) -> None:
    if any(sha256(path.read_bytes()) != digest for path, digest in snapshot.items()):
        raise ValueError("Bound source, fit receipt, protocol, or checkpoint changed")


def run(fit_directory: Path, protocol: Path, output: Path) -> dict[str, object]:
    protocol = _file(protocol, kind="runtime parity protocol")
    expected_protocol = _file(
        _repo_root() / PARITY_PROTOCOL_PATH, kind="bound runtime parity protocol"
    )
    if protocol != expected_protocol:
        raise ValueError("Only the bound runtime parity protocol path may be used")
    if sha256(protocol.read_bytes()) != PARITY_PROTOCOL_SHA256:
        raise ValueError("Wrong runtime parity protocol")
    artifacts = source_artifacts()
    root = _repo_root()
    source_paths = tuple(root / item["relativePath"] for item in artifacts)
    source_snapshot = _snapshot(source_paths + (protocol,))
    fit = load_frozen_fit(fit_directory)
    fit_paths = (
        fit.directory / dual.FIT_RECEIPT_NAME,
        fit.directory / dual.FROZEN_PROTOCOL_NAME,
    ) + tuple(fit.weight_paths[arm] for arm in ARMS)
    fit_snapshot = _snapshot(fit_paths)

    import coremltools as ct

    if str(ct.__version__) != "9.0":
        raise ValueError("Core ML Tools 9.0 is required")
    torch.set_num_threads(dual.CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    features = feature_cases()
    if len(features) != 12:
        raise ValueError("Expected exactly 12 frozen synthetic cases")

    output = _new_directory(output)
    models_directory = output / "models"
    fixtures_directory = output / "fixtures"
    models_directory.mkdir(mode=0o700)
    fixtures_directory.mkdir(mode=0o700)
    arm_receipts = []
    package_identities = {}
    for arm in ARMS:
        model_relative = f"models/{arm}.mlpackage"
        package = output / model_relative
        runtime = _convert_arm(ct, arm, fit, package)
        package_sha, package_bytes = package_tree_identity(package)
        fixture = _fixture(
            arm,
            fit,
            runtime,
            features,
            model_relative,
            package_sha,
            package_bytes,
        )
        fixture_relative = f"fixtures/{arm}.json"
        fixture_payload = canonical_json_bytes(fixture)
        _write(output / fixture_relative, fixture_payload)
        arm_receipts.append(
            {
                "fitSHA256": FIT_RECEIPT_SHA256,
                "fixtureByteCount": len(fixture_payload),
                "fixtureRelativePath": fixture_relative,
                "fixtureSHA256": sha256(fixture_payload),
                "modelArm": arm,
                "modelPackageByteCount": package_bytes,
                "modelPackageRelativePath": model_relative,
                "modelPackageTreeSHA256": package_sha,
                "vocabularySHA256": fit.receipt["vocabularySHA256"],
                "weightSeed": WEIGHT_SEED,
                "weightsSHA256": fit.receipt["weightsSHA256"][arm],
            }
        )
        package_identities[arm] = (package_sha, package_bytes)

    if len(arm_receipts) != 3:
        raise ValueError("All three arm exports are required")
    for arm in ARMS:
        if package_tree_identity(output / f"models/{arm}.mlpackage") != package_identities[arm]:
            raise ValueError("Core ML package changed during parity prediction")
    _assert_preserved(source_snapshot)
    _assert_preserved(fit_snapshot)
    receipt = {
        "arms": arm_receipts,
        "featureSchemaVersion": FEATURE_SCHEMA_VERSION,
        "schemaVersion": EXPORT_VERSION,
        "sourceArtifacts": artifacts,
    }
    # Receipt is the final artifact. Its own detached SHA is reported by the
    # caller/root rather than recursively embedded in the receipt.
    _write(output / "export-receipt.json", canonical_json_bytes(receipt))
    print(
        canonical_json_bytes(
            {
                "arms": list(ARMS),
                "basePredictions": 36,
                "inactiveInputProbePredictions": 24,
                "timingProbePredictions": 36,
                "totalCoreMLPredictions": 96,
            }
        ).decode("utf-8"),
        flush=True,
    )
    return receipt


def entrypoint(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fit-directory", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args(argv)
    run(arguments.fit_directory, arguments.protocol, arguments.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(entrypoint())
