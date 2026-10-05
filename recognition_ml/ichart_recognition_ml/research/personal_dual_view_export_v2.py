"""Versioned, representation-only Core ML export for the frozen dual-view fit.

This module changes only the order used to select trajectory geometry channels
at export time.  It neither fits a model nor reads a recognition corpus.
"""

from __future__ import annotations

import argparse
import hashlib
import stat
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from ..contracts import canonical_json_bytes
from . import personal_dual_view as dual
from . import personal_dual_view_export as v1


EXPORT_VERSION = "personal-dual-view-coreml-export-v2"
EQUIVALENCE_VERSION = "personal-dual-view-export-equivalence-v2"
PARITY_PROTOCOL_PATH = "docs/personal-dual-view-runtime-parity-v2-protocol-2026-09-30.md"
PARITY_PROTOCOL_SHA256 = "fa91b0e4c2432bd43cfce56a5a35d7f4ec708feb3cf87fa9244271ba225a8207"
EXPORT_MODULE_PATH = (
    "recognition_ml/ichart_recognition_ml/research/personal_dual_view_export_v2.py"
)
EXPORT_TEST_PATH = "recognition_ml/tests/test_personal_dual_view_export_v2.py"
SWIFT_GATE_PATH = "recognition_ml/tests/PersonalDualViewCoreMLParityGateV2.swift"
BOUND_SOURCE_PATHS = tuple(
    sorted(
        set(
            v1.BOUND_SOURCE_PATHS
            + (PARITY_PROTOCOL_PATH, EXPORT_MODULE_PATH, EXPORT_TEST_PATH, SWIFT_GATE_PATH)
        )
    )
)
ARMS = v1.ARMS
INDEXES = tuple(dual.GEOMETRY_CHANNELS)
PARENT_ROOT = Path(
    "/Users/benirossman/.local/share/ichart/recognition-development/"
    "dual-view-runtime-parity-20260930.bmxl5o"
)
PARENT_FAILURE_PATH = PARENT_ROOT / "invariance-diagnosis.json"
PARENT_FAILURE_SHA256 = "73097c61d8c70c35917881dde30229d7a82624c9945873ec968f0eb00e7af02f"
STAGE_DIAGNOSTIC_PATH = PARENT_ROOT / "selection-stages-diagnostic-v1/results.json"
STAGE_DIAGNOSTIC_SHA256 = "19361e405e56041558dd169de58511cb1f57b0bb24386c8d99918755c41c0778"
STAGE_SOURCE_SHA256 = "d455c806367f6c8722b950513dd2b1ad12f36213d246b5d448ab7016ad88f658"
FAILED_V1_MODELS = PARENT_ROOT / "export/models"
EQUIVALENCE_RECEIPT_NAME = "equivalence-receipt.json"
PARENT_PACKAGE_PINS = {
    "rasterOnly": {
        "byteCount": 1_222_028,
        "learnedWeightBlob": {
            "byteCount": 1_211_072,
            "relativePath": "Data/com.apple.CoreML/weights/weight.bin",
            "sha256": "cc14fcb5003bace1eaa4f1bc4aea2dbccec904635fc01f42df3b6454fe30543a",
        },
        "treeSHA256": "43232de93f58739ccbe4bb13180072f44d5867fc0b614ebf6ef209e022ac1a03",
    },
    "trajectoryOnly": {
        "byteCount": 562_082,
        "learnedWeightBlob": {
            "byteCount": 543_680,
            "relativePath": "Data/com.apple.CoreML/weights/weight.bin",
            "sha256": "174656c41b66c95182dff8e2f7556592c97dd2f721fd1ed3629cc1261ed4199e",
        },
        "treeSHA256": "85d67f7409fac018a3ff30d0621697ffd959ab6795f8b9dd5fa7265e8bf12db9",
    },
}


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def source_artifacts() -> list[dict[str, object]]:
    if len(v1.BOUND_SOURCE_PATHS) != 20 or len(BOUND_SOURCE_PATHS) != 24:
        raise ValueError("V2 source binding must extend exactly 20 V1 paths to 24 paths")
    root = v1._repo_root()
    result = []
    for relative in BOUND_SOURCE_PATHS:
        payload = v1._file(root / relative, kind=f"bound source {relative}").read_bytes()
        result.append(
            {"byteCount": len(payload), "relativePath": relative, "sha256": sha256(payload)}
        )
    protocol = next(item for item in result if item["relativePath"] == PARITY_PROTOCOL_PATH)
    if protocol["sha256"] != PARITY_PROTOCOL_SHA256:
        raise ValueError("V2 runtime parity protocol differs from its frozen digest")
    return result


class _ExportWrapperV2(nn.Module):
    """Register the original model and reorder only its trajectory selector."""

    def __init__(self, model: dual.PersonalDualViewEncoder):
        super().__init__()
        self.model = model

    def forward(self, ink_trajectory, ink_raster):
        model = self.model
        geometry = ink_trajectory.permute(0, 1, 3, 2)[:, 0, :, :].index_select(
            1, model.geometry_channel_indexes
        )
        trajectory_raw = model.trajectory_projection(
            model.trajectory_convolution(geometry).flatten(1)
        )
        raster_raw = model.raster_projection(model.raster_convolution(ink_raster).flatten(1))
        if model.arm == "rasterOnly":
            trajectory_raw = torch.zeros_like(trajectory_raw)
        elif model.arm == "trajectoryOnly":
            raster_raw = torch.zeros_like(raster_raw)
        fused_raw = model.fusion(torch.cat((raster_raw, trajectory_raw), dim=1))
        return F.normalize(fused_raw, dim=1), model.classifier(fused_raw)


def _tensor_entry(key: str, tensor: torch.Tensor) -> dict[str, object]:
    value = tensor.detach().cpu().contiguous()
    payload = value.numpy().tobytes(order="C")
    return {
        "byteCount": len(payload),
        "dtype": str(value.dtype),
        "key": key,
        "sha256": sha256(payload),
        "shape": list(value.shape),
    }


def _state_identity(module: nn.Module, *, wrapper: bool) -> dict[str, object]:
    raw = module.state_dict()
    prefix = "model."
    if wrapper and any(not key.startswith(prefix) for key in raw):
        raise ValueError("Export wrapper added state outside the registered original model")
    normalized = {
        (key[len(prefix) :] if wrapper else key): value for key, value in raw.items()
    }
    if len(normalized) != len(raw):
        raise ValueError("State-key normalization collided")
    return {
        "normalizedKeys": sorted(normalized),
        "normalizedStateSHA256": dual._state_digest(normalized),
        "rawKeys": sorted(raw),
        "tensors": [_tensor_entry(key, normalized[key]) for key in sorted(normalized)],
    }


def _wrapper_identity(model: nn.Module, wrapper: nn.Module) -> dict[str, object]:
    expected_parameters = {f"model.{key}": id(value) for key, value in model.named_parameters()}
    actual_parameters = {key: id(value) for key, value in wrapper.named_parameters()}
    expected_buffers = {f"model.{key}": id(value) for key, value in model.named_buffers()}
    actual_buffers = {key: id(value) for key, value in wrapper.named_buffers()}
    if actual_parameters != expected_parameters or actual_buffers != expected_buffers:
        raise ValueError("Export wrapper copied, replaced, or added model state")
    identity = _state_identity(wrapper, wrapper=True)
    original = _state_identity(model, wrapper=False)
    if (
        identity["normalizedKeys"] != original["normalizedKeys"]
        or identity["normalizedStateSHA256"] != original["normalizedStateSHA256"]
        or identity["tensors"] != original["tensors"]
    ):
        raise ValueError("Export wrapper state differs from the original model")
    return identity


def _state_bundle(models: Mapping[str, dual.PersonalDualViewEncoder]) -> dict[str, object]:
    result = {}
    for arm in ARMS:
        model = models[arm]
        original = _state_identity(model, wrapper=False)
        v1_wrapper = _wrapper_identity(model, v1._ExportWrapper(model).eval())
        v2_wrapper = _wrapper_identity(model, _ExportWrapperV2(model).eval())
        result[arm] = {
            "original": original,
            "v1Wrapper": v1_wrapper,
            "v2Wrapper": v2_wrapper,
        }
    return result


def _array_payload(array: np.ndarray, shape: tuple[int, ...], name: str) -> tuple[dict, bytes]:
    value = np.asarray(array)
    if value.shape != shape or value.dtype != np.dtype("float32") or not np.isfinite(value).all():
        raise ValueError(f"{name} output shape, type, or finiteness changed")
    payload = value.astype("<f4", copy=False).tobytes(order="C")
    return (
        {
            "byteCount": len(payload),
            "elementCount": int(value.size),
            "sha256": sha256(payload),
            "shape": list(shape),
        },
        payload,
    )


def _output_identity(outputs) -> tuple[dict[str, object], tuple[bytes, bytes]]:
    if not isinstance(outputs, (tuple, list)) or len(outputs) != 2:
        raise ValueError("Torch model must return embedding and logits")
    embedding = outputs[0].detach().cpu().contiguous().numpy()
    logits = outputs[1].detach().cpu().contiguous().numpy()
    embedding_identity, embedding_bytes = _array_payload(
        embedding, (1, 128), "personalEmbedding"
    )
    logits_identity, logits_bytes = _array_payload(logits, (1, 97), "genericLogits")
    if abs(float(np.linalg.norm(embedding[0])) - 1.0) > v1.EMBEDDING_TOLERANCE:
        raise ValueError("Torch embedding is not unit normalized")
    return (
        {
            "firstGenericArgmax": int(np.argmax(logits[0])),
            "genericLogits": logits_identity,
            "personalEmbedding": embedding_identity,
        },
        (embedding_bytes, logits_bytes),
    )


def _retained_output_identity(vector: object) -> tuple[dict, tuple[bytes, bytes]]:
    if not isinstance(vector, dict) or set(vector) != {
        "firstGenericArgmax", "genericLogits", "personalEmbedding"
    }:
        raise ValueError("Retained V1 Torch vector schema changed")
    embedding = np.asarray(vector["personalEmbedding"], dtype=np.float32).reshape(1, -1)
    logits = np.asarray(vector["genericLogits"], dtype=np.float32).reshape(1, -1)
    embedding_identity, embedding_bytes = _array_payload(
        embedding, (1, 128), "retained personalEmbedding"
    )
    logits_identity, logits_bytes = _array_payload(logits, (1, 97), "retained genericLogits")
    argmax = int(np.argmax(logits[0]))
    if type(vector["firstGenericArgmax"]) is not int or vector["firstGenericArgmax"] != argmax:
        raise ValueError("Retained V1 first argmax changed")
    return (
        {
            "firstGenericArgmax": argmax,
            "genericLogits": logits_identity,
            "personalEmbedding": embedding_identity,
        },
        (embedding_bytes, logits_bytes),
    )


def _load_parent_failure() -> tuple[dict[str, dict], dict[str, object]]:
    value, payload = v1._canonical_json(PARENT_FAILURE_PATH, kind="V1 failure diagnostic")
    if sha256(payload) != PARENT_FAILURE_SHA256:
        raise ValueError("V1 failure diagnostic bytes changed")
    if set(value) != {"fitSHA256", "modelParametersChanged", "rows", "scope"}:
        raise ValueError("V1 failure diagnostic schema changed")
    if value["fitSHA256"] != v1.FIT_RECEIPT_SHA256 or value["modelParametersChanged"] is not False:
        raise ValueError("V1 failure diagnostic fit/state binding changed")
    expected = {
        (arm, case_id, kind)
        for arm in ("rasterOnly", "trajectoryOnly")
        for case_id in v1.CASE_IDS
        for kind in ("base", "timingProbe", "inactiveInputProbe")
    }
    rows = {}
    for row in value["rows"]:
        if not isinstance(row, dict) or set(row) != {
            "arm", "baseFirstArgmax", "caseID", "errors", "firstArgmax", "kind", "vectors"
        }:
            raise ValueError("V1 failure diagnostic row schema changed")
        key = (row["arm"], row["caseID"], row["kind"])
        if key in rows or key not in expected or set(row["vectors"]) != {"coreMLPython", "torch"}:
            raise ValueError("V1 failure diagnostic coverage changed")
        _retained_output_identity(row["vectors"]["torch"])
        rows[key] = row["vectors"]["torch"]
    if set(rows) != expected:
        raise ValueError("V1 failure diagnostic is incomplete")
    artifact = {
        "byteCount": len(payload),
        "path": str(PARENT_FAILURE_PATH),
        "sha256": PARENT_FAILURE_SHA256,
    }
    return rows, artifact


def _load_stage_diagnostic() -> dict[str, object]:
    value, payload = v1._canonical_json(STAGE_DIAGNOSTIC_PATH, kind="stage diagnostic")
    if sha256(payload) != STAGE_DIAGNOSTIC_SHA256:
        raise ValueError("Stage diagnostic bytes changed")
    expected_passes = {
        "gatherWithoutTranspose": False,
        "slicesWithoutTranspose": False,
        "squeezeOnly": True,
        "transposeAllChannels": False,
        "transposeFirstThenSlices": False,
        "transposeRank4ThenSelect": True,
    }
    if (
        value.get("predictionCount") != 18
        or len(value.get("rows", ())) != 18
        or value.get("programBitExactAcrossAllCases") != expected_passes
        or value.get("source", {}).get("sha256") != STAGE_SOURCE_SHA256
    ):
        raise ValueError("Stage diagnostic outcome/source binding changed")
    programs = []
    for item in value.get("programs", ()):
        package = item.get("package") if isinstance(item, dict) else None
        if not isinstance(package, dict) or set(package) != {"byteCount", "fileCount", "treeSHA256"}:
            raise ValueError("Stage diagnostic package identity changed")
        programs.append(
            {
                "modelPackageIdentity": package,
                "modelPackageRelativePath": item.get("packageRelativePath"),
                "program": item.get("program"),
            }
        )
    if len(programs) != 6 or len({item["program"] for item in programs}) != 6:
        raise ValueError("Stage diagnostic program coverage changed")
    return {
        "byteCount": len(payload),
        "path": str(STAGE_DIAGNOSTIC_PATH),
        "programPackages": programs,
        "recordedSource": value["source"],
        "sha256": STAGE_DIAGNOSTIC_SHA256,
    }


def _fit_artifacts(fit: v1.FrozenFit) -> list[dict[str, object]]:
    paths = (
        fit.directory / dual.FIT_RECEIPT_NAME,
        fit.directory / dual.FROZEN_PROTOCOL_NAME,
    ) + tuple(fit.weight_paths[arm] for arm in ARMS)
    result = []
    for path in paths:
        payload = path.read_bytes()
        result.append(
            {
                "byteCount": len(payload),
                "relativePath": path.relative_to(fit.directory).as_posix(),
                "sha256": sha256(payload),
            }
        )
    return sorted(result, key=lambda item: item["relativePath"])


def _verify_parent_package_identity(arm: str, actual: dict[str, object]) -> None:
    if arm not in PARENT_PACKAGE_PINS or actual != PARENT_PACKAGE_PINS[arm]:
        raise ValueError(f"Retained failed V1 {arm} package differs from its fixed identity")


def _failed_v1_packages() -> dict[str, dict[str, object]]:
    if (FAILED_V1_MODELS / "dual.mlpackage").exists():
        raise ValueError("Retained failed V1 export unexpectedly contains a dual package")
    result = {}
    for arm in ("rasterOnly", "trajectoryOnly"):
        package = v1._directory(FAILED_V1_MODELS / f"{arm}.mlpackage", kind=f"failed {arm} package")
        digest, byte_count = v1.package_tree_identity(package)
        actual = {
            "byteCount": byte_count,
            "learnedWeightBlob": _weight_blob(package),
            "treeSHA256": digest,
        }
        _verify_parent_package_identity(arm, actual)
        result[arm] = {
            **actual,
            "relativePath": f"export/models/{arm}.mlpackage",
        }
    return result


def _cell_inputs(feature: v1.FeatureCase, arm: str, kind: str) -> tuple[np.ndarray, np.ndarray]:
    trajectory, raster = feature.trajectory.copy(), feature.raster.copy()
    if kind == "timingProbe":
        trajectory[:, :, :, 5] = np.float32(0.37)
        trajectory[:, :, :, 6] = np.float32(1.0)
    elif kind == "inactiveInputProbe" and arm == "rasterOnly":
        trajectory.fill(0)
    elif kind == "inactiveInputProbe" and arm == "trajectoryOnly":
        raster.fill(0)
    elif kind != "base":
        raise ValueError("Invalid equivalence cell kind/arm")
    return trajectory, raster


def _preconversion_equivalence(
    models: Mapping[str, dual.PersonalDualViewEncoder],
    features: Sequence[v1.FeatureCase],
    retained: Mapping[tuple[str, str, str], dict],
) -> tuple[list[dict[str, object]], dict[str, object], dict[str, object]]:
    state_before = _state_bundle(models)
    prepared = {}
    zero_trajectory = torch.zeros((1, 1, 256, 10), dtype=torch.float32)
    zero_raster = torch.zeros((1, 1, 96, 256), dtype=torch.float32)
    for arm in ARMS:
        original = v1._ExportWrapper(models[arm]).eval()
        rewritten = _ExportWrapperV2(models[arm]).eval()
        original_traced = torch.jit.trace(
            original, (zero_trajectory, zero_raster), strict=True, check_trace=True
        )
        rewritten_traced = torch.jit.trace(
            rewritten, (zero_trajectory, zero_raster), strict=True, check_trace=True
        )
        v1._validate_traced_output_contract(original_traced, zero_trajectory, zero_raster)
        v1._validate_traced_output_contract(rewritten_traced, zero_trajectory, zero_raster)
        prepared[arm] = (original, original_traced, rewritten, rewritten_traced)

    cells = []
    retained_count = 0
    for arm in ARMS:
        kinds = ("base", "timingProbe") + (
            ("inactiveInputProbe",) if arm != "dual" else ()
        )
        for feature in features:
            for kind in kinds:
                trajectory, raster = _cell_inputs(feature, arm, kind)
                trajectory_tensor = torch.from_numpy(trajectory.copy())
                raster_tensor = torch.from_numpy(raster.copy())
                with torch.inference_mode():
                    outputs = (
                        models[arm](trajectory_tensor, raster_tensor),
                        prepared[arm][1](trajectory_tensor, raster_tensor),
                        prepared[arm][2](trajectory_tensor, raster_tensor),
                        prepared[arm][3](trajectory_tensor, raster_tensor),
                    )
                names = ("originalEager", "originalTraced", "rewrittenEager", "rewrittenTraced")
                identities, payloads = {}, {}
                for name, output in zip(names, outputs):
                    identities[name], payloads[name] = _output_identity(output)
                if any(payloads[name] != payloads["originalEager"] for name in names[1:]):
                    raise ValueError(f"V2 Torch export expression is not bit exact: {arm}/{feature.case_id}/{kind}")
                retained_identity = None
                if arm != "dual":
                    retained_identity, retained_payload = _retained_output_identity(
                        retained[(arm, feature.case_id, kind)]
                    )
                    if retained_payload != payloads["originalEager"]:
                        raise ValueError(
                            f"Original Torch output differs from retained V1: {arm}/{feature.case_id}/{kind}"
                        )
                    retained_count += 1
                cells.append(
                    {
                        "allTorchVariantsBitExact": True,
                        "arm": arm,
                        "caseID": feature.case_id,
                        "inputSHA256": {
                            "rasterFloat32": sha256(raster.astype("<f4", copy=False).tobytes(order="C")),
                            "trajectoryFloat32": sha256(
                                trajectory.astype("<f4", copy=False).tobytes(order="C")
                            ),
                        },
                        "kind": kind,
                        "retainedV1Torch": retained_identity,
                        "variants": identities,
                    }
                )
    if len(cells) != 96 or retained_count != 72:
        raise ValueError("Preconversion equivalence coverage changed")
    state_after = _state_bundle(models)
    if state_after != state_before:
        raise ValueError("Tracing/equivalence mutated the original model state")
    return cells, state_before, state_after


def _mil_nodes(coremltools, package: Path) -> list[dict[str, object]]:
    spec = coremltools.utils.load_spec(str(package))
    if set(spec.mlProgram.functions) != {"main"}:
        raise ValueError("Saved MIL function set changed")
    function = spec.mlProgram.functions["main"]
    if set(function.block_specializations) != {"CoreML6"}:
        raise ValueError("Saved MIL specialization changed")
    nodes = []
    for operation in function.block_specializations["CoreML6"].operations:
        outputs = []
        for output in operation.outputs:
            tensor_type = output.type.tensorType
            outputs.append(
                {
                    "name": output.name,
                    "shape": [int(dimension.constant.size) for dimension in tensor_type.dimensions],
                }
            )
        node = {
            "inputs": {
                key: [argument.name for argument in value.arguments]
                for key, value in operation.inputs.items()
            },
            "outputs": outputs,
            "type": operation.type,
        }
        if operation.type == "const":
            tensor = operation.attributes["val"].immediateValue.tensor
            if tensor.ints.values:
                node["constInts"] = [int(value) for value in tensor.ints.values]
            if tensor.bools.values:
                node["constBools"] = [bool(value) for value in tensor.bools.values]
        nodes.append(node)
    return nodes


def _const_values(nodes: Sequence[dict], field: str) -> dict[str, list]:
    result = {}
    for node in nodes:
        if node["type"] == "const" and field in node and len(node["outputs"]) == 1:
            result[node["outputs"][0]["name"]] = node[field]
    return result


def _single_input(node: dict, key: str) -> str | None:
    values = node.get("inputs", {}).get(key, ())
    return values[0] if len(values) == 1 else None


def _selector_graph(nodes: Sequence[dict], arm: str) -> dict[str, object]:
    ints, bools = _const_values(nodes, "constInts"), _const_values(nodes, "constBools")
    producers = {
        output["name"]: (index, node, output)
        for index, node in enumerate(nodes)
        for output in node["outputs"]
    }
    candidates = []
    for transpose_index, transpose in enumerate(nodes):
        if transpose["type"] != "transpose" or _single_input(transpose, "x") != "inkTrajectory":
            continue
        if ints.get(_single_input(transpose, "perm")) != [0, 1, 3, 2]:
            continue
        transpose_output = transpose["outputs"][0]
        if transpose_output["shape"] != [1, 1, 10, 256]:
            continue
        for slice_index, sliced in enumerate(nodes):
            if slice_index <= transpose_index or sliced["type"] != "slice_by_index":
                continue
            if _single_input(sliced, "x") != transpose_output["name"]:
                continue
            if bools.get(_single_input(sliced, "squeeze_mask")) != [False, True, False, False]:
                continue
            slice_output = sliced["outputs"][0]
            if slice_output["shape"] != [1, 10, 256]:
                continue
            for gather_index, gather in enumerate(nodes):
                if gather_index <= slice_index or gather["type"] != "gather":
                    continue
                if (
                    _single_input(gather, "x") == slice_output["name"]
                    and ints.get(_single_input(gather, "axis")) == [1]
                    and ints.get(_single_input(gather, "indices")) == list(INDEXES)
                    and gather["outputs"][0]["shape"] == [1, 8, 256]
                ):
                    candidates.append((transpose_index, slice_index, gather_index, gather))
    broken = [
        node
        for node in nodes
        if node["type"] == "gather"
        and ints.get(_single_input(node, "indices")) == list(INDEXES)
        and ints.get(_single_input(node, "axis")) == [2]
    ]
    if broken:
        raise ValueError("Saved MIL restored the rejected gather-before-rank3-transpose selector")
    if arm == "rasterOnly" and not candidates:
        return {"optimizedAwayAsInactiveBranch": True, "selectorCandidateCount": 0}
    if len(candidates) != 1:
        raise ValueError(f"Saved MIL has {len(candidates)} valid V2 selector paths for {arm}")
    transpose_index, slice_index, gather_index, gather = candidates[0]
    gather_output = gather["outputs"][0]["name"]
    consumers = [
        node["type"]
        for node in nodes[gather_index + 1 :]
        if gather_output in sum(node.get("inputs", {}).values(), [])
    ]
    if consumers != ["conv"]:
        raise ValueError("Saved MIL selector no longer feeds exactly the trajectory convolution")
    argument_names = {
        name for node in nodes for names in node.get("inputs", {}).values() for name in names
    }
    required = {
        "model_trajectory_convolution_0_weight",
        "model_trajectory_convolution_0_bias",
        "model_trajectory_convolution_2_weight",
        "model_trajectory_convolution_2_bias",
        "model_trajectory_convolution_4_weight",
        "model_trajectory_convolution_4_bias",
        "model_trajectory_projection_weight",
        "model_trajectory_projection_bias",
        "model_fusion_weight",
        "model_fusion_bias",
        "model_classifier_weight",
        "model_classifier_bias",
    }
    if not required.issubset(argument_names):
        raise ValueError("Saved MIL lost or renamed learned trajectory/downstream constants")
    return {
        "gatherIndex": gather_index,
        "gatherOutput": gather_output,
        "optimizedAwayAsInactiveBranch": False,
        "selectorCandidateCount": 1,
        "sliceIndex": slice_index,
        "transposeIndex": transpose_index,
    }


def _dynamic_types(nodes: Sequence[dict], start: int = -1) -> list[str]:
    return [node["type"] for node in nodes[start + 1 :] if node["type"] != "const"]


def _original_selector_end(nodes: Sequence[dict]) -> int:
    ints = _const_values(nodes, "constInts")
    for gather_index, gather in enumerate(nodes):
        if (
            gather["type"] == "gather"
            and ints.get(_single_input(gather, "indices")) == list(INDEXES)
            and ints.get(_single_input(gather, "axis")) == [2]
        ):
            output = gather["outputs"][0]["name"]
            for index, node in enumerate(nodes[gather_index + 1 :], gather_index + 1):
                if (
                    node["type"] == "transpose"
                    and _single_input(node, "x") == output
                    and ints.get(_single_input(node, "perm")) == [0, 2, 1]
                ):
                    return index
    raise ValueError("Retained V1 trajectory package selector is not the frozen failed graph")


def _original_selector_graph(nodes: Sequence[dict]) -> dict[str, object]:
    ints = _const_values(nodes, "constInts")
    candidates = []
    for gather_index, gather in enumerate(nodes):
        if (
            gather["type"] != "gather"
            or ints.get(_single_input(gather, "indices")) != list(INDEXES)
            or ints.get(_single_input(gather, "axis")) != [2]
        ):
            continue
        gather_output = gather["outputs"][0]["name"]
        for transpose_index, transpose in enumerate(nodes[gather_index + 1 :], gather_index + 1):
            if (
                transpose["type"] == "transpose"
                and _single_input(transpose, "x") == gather_output
                and ints.get(_single_input(transpose, "perm")) == [0, 2, 1]
                and transpose["outputs"][0]["shape"] == [1, 8, 256]
            ):
                candidates.append((gather_index, transpose_index, transpose))
    if len(candidates) != 1:
        raise ValueError(f"Dual V1 control has {len(candidates)} original selector paths")
    gather_index, transpose_index, transpose = candidates[0]
    transpose_output = transpose["outputs"][0]["name"]
    consumers = [
        node["type"]
        for node in nodes[transpose_index + 1 :]
        if transpose_output in sum(node.get("inputs", {}).values(), [])
    ]
    if consumers != ["conv"]:
        raise ValueError("Dual V1 control selector no longer feeds exactly the trajectory convolution")
    return {
        "gatherIndex": gather_index,
        "selectorCandidateCount": 1,
        "transposeIndex": transpose_index,
    }


def _weight_blob(package: Path) -> dict[str, object]:
    root = package / "Data/com.apple.CoreML/weights"
    files = [path for path in root.rglob("*") if path.is_file() and not path.is_symlink()]
    if len(files) != 1 or not stat.S_ISREG(files[0].stat().st_mode):
        raise ValueError("Expected exactly one regular Core ML weight blob")
    payload = files[0].read_bytes()
    return {
        "byteCount": len(payload),
        "relativePath": files[0].relative_to(package).as_posix(),
        "sha256": sha256(payload),
    }


def _validate_against_reference(
    nodes: Sequence[dict],
    selector_end: int,
    learned_blob: dict[str, object],
    reference: Mapping[str, object],
    *,
    kind: str,
) -> dict[str, object]:
    downstream = _dynamic_types(nodes, selector_end)
    if downstream != reference["downstreamDynamicOperationTypes"]:
        raise ValueError(f"{kind} downstream MIL topology changed")
    if learned_blob != reference["learnedWeightBlob"]:
        raise ValueError(f"{kind} learned weight blob changed")
    return {
        "downstreamDynamicOperationTypes": downstream,
        "learnedWeightBlob": learned_blob,
    }


def _validate_dual_control(coremltools, package: Path) -> dict[str, object]:
    nodes = _mil_nodes(coremltools, package)
    selector = _original_selector_graph(nodes)
    tree_sha, byte_count = v1.package_tree_identity(package)
    return {
        "downstreamDynamicOperationTypes": _dynamic_types(nodes, selector["transposeIndex"]),
        "dynamicOperationTypes": _dynamic_types(nodes),
        "learnedWeightBlob": _weight_blob(package),
        "packageIdentity": {"byteCount": byte_count, "treeSHA256": tree_sha},
        "packageRelativePath": "control/dual-v1.mlpackage",
        "selector": selector,
    }


def _validate_saved_mil(
    coremltools,
    package: Path,
    arm: str,
    dual_control: Mapping[str, object] | None = None,
) -> dict[str, object]:
    nodes = _mil_nodes(coremltools, package)
    selector = _selector_graph(nodes, arm)
    retained_package = FAILED_V1_MODELS / f"{arm}.mlpackage"
    retained_weight = None
    reference = None
    if arm in ("rasterOnly", "trajectoryOnly"):
        retained_nodes = _mil_nodes(coremltools, retained_package)
        if arm == "rasterOnly":
            if _dynamic_types(nodes) != _dynamic_types(retained_nodes):
                raise ValueError("Raster-only saved MIL topology changed from retained V1")
        else:
            old_end = _original_selector_end(retained_nodes)
            if _dynamic_types(nodes, selector["gatherIndex"]) != _dynamic_types(
                retained_nodes, old_end
            ):
                raise ValueError("Trajectory-only downstream MIL topology changed")
        retained_weight = _weight_blob(retained_package)
        reference = _validate_against_reference(
            nodes,
            selector.get("gatherIndex", -1) if arm == "trajectoryOnly" else -1,
            _weight_blob(package),
            {
                "downstreamDynamicOperationTypes": (
                    _dynamic_types(retained_nodes, old_end)
                    if arm == "trajectoryOnly"
                    else _dynamic_types(retained_nodes)
                ),
                "learnedWeightBlob": retained_weight,
            },
            kind=f"{arm} retained-V1 comparison",
        )
    elif arm == "dual":
        if dual_control is None:
            raise ValueError("Dual candidate requires its original-expression structural control")
        reference = _validate_against_reference(
            nodes,
            int(selector["gatherIndex"]),
            _weight_blob(package),
            dual_control,
            kind="Dual control comparison",
        )
        retained_weight = dual_control["learnedWeightBlob"]
    return {
        "dynamicOperationTypes": _dynamic_types(nodes),
        "learnedWeightBlob": _weight_blob(package),
        "referenceComparison": reference,
        "retainedV1LearnedWeightBlob": retained_weight,
        "selector": selector,
    }


def _convert_arm(
    coremltools,
    arm: str,
    fit: v1.FrozenFit,
    package: Path,
    dual_control: Mapping[str, object] | None = None,
):
    model = fit.models[arm].eval()
    example_trajectory = torch.zeros((1, 1, 256, 10), dtype=torch.float32)
    example_raster = torch.zeros((1, 1, 96, 256), dtype=torch.float32)
    traced = torch.jit.trace(
        _ExportWrapperV2(model).eval(),
        (example_trajectory, example_raster),
        strict=True,
        check_trace=True,
    )
    v1._validate_traced_output_contract(traced, example_trajectory, example_raster)
    converted = coremltools.convert(
        traced,
        inputs=[
            coremltools.TensorType(
                name="inkTrajectory", shape=(1, 1, 256, 10), dtype=np.float32
            ),
            coremltools.TensorType(name="inkRaster", shape=(1, 1, 96, 256), dtype=np.float32),
        ],
        outputs=[
            coremltools.TensorType(name="personalEmbedding", dtype=np.float32),
            coremltools.TensorType(name="genericLogits", dtype=np.float32),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=coremltools.target.macOS13,
        compute_precision=coremltools.precision.FLOAT32,
        compute_units=coremltools.ComputeUnit.CPU_ONLY,
    )
    metadata = v1._metadata(arm, fit)
    converted.user_defined_metadata.clear()
    converted.user_defined_metadata.update(metadata)
    if package.exists() or package.is_symlink():
        raise ValueError("Core ML package output already exists")
    converted.save(str(package))
    runtime = coremltools.models.MLModel(
        str(package), compute_units=coremltools.ComputeUnit.CPU_ONLY
    )
    v1._validate_model_contract(runtime, coremltools, metadata)
    return runtime, _validate_saved_mil(coremltools, package, arm, dual_control)


def _candidate_output(path: Path) -> Path:
    path = Path(path).expanduser()
    if not path.is_absolute() or ".." in path.parts or path.exists() or path.is_symlink():
        raise ValueError("Output must be a new absolute canonical directory")
    parent = v1._directory(path.parent, kind="output parent")
    if path.parent != parent:
        raise ValueError("Output parent aliases are forbidden")
    return path


def run(fit_directory: Path, protocol: Path, output: Path) -> dict[str, object]:
    protocol = v1._file(protocol, kind="V2 runtime parity protocol")
    expected_protocol = v1._file(
        v1._repo_root() / PARITY_PROTOCOL_PATH, kind="bound V2 runtime parity protocol"
    )
    if protocol != expected_protocol or sha256(protocol.read_bytes()) != PARITY_PROTOCOL_SHA256:
        raise ValueError("Only the exact bound V2 runtime parity protocol may be used")
    output = _candidate_output(output)
    artifacts_before = source_artifacts()
    source_paths = tuple(v1._repo_root() / item["relativePath"] for item in artifacts_before)
    source_snapshot = v1._snapshot(source_paths + (protocol,))
    retained_rows, parent_failure = _load_parent_failure()
    stage_diagnostic = _load_stage_diagnostic()
    parent_snapshot = v1._snapshot((PARENT_FAILURE_PATH, STAGE_DIAGNOSTIC_PATH))
    failed_packages_before = _failed_v1_packages()
    fit = v1.load_frozen_fit(fit_directory)
    fit_before = _fit_artifacts(fit)
    fit_paths = (
        fit.directory / dual.FIT_RECEIPT_NAME,
        fit.directory / dual.FROZEN_PROTOCOL_NAME,
    ) + tuple(fit.weight_paths[arm] for arm in ARMS)
    fit_snapshot = v1._snapshot(fit_paths)

    torch.set_num_threads(dual.CPU_THREADS)
    torch.use_deterministic_algorithms(True)
    features = v1.feature_cases()
    if len(features) != 12:
        raise ValueError("Expected exactly 12 frozen synthetic cases")
    cells, states_before, states_after_equivalence = _preconversion_equivalence(
        fit.models, features, retained_rows
    )
    # No converter is imported or called before all 96 candidate cells pass.
    import coremltools as ct

    if str(ct.__version__) != "9.0":
        raise ValueError("Core ML Tools 9.0 is required")
    output = v1._new_directory(output)
    models_directory, fixtures_directory = output / "models", output / "fixtures"
    control_directory = output / "control"
    models_directory.mkdir(mode=0o700)
    fixtures_directory.mkdir(mode=0o700)
    control_directory.mkdir(mode=0o700)
    control_package = control_directory / "dual-v1.mlpackage"
    # Structural reference only: the frozen V1 converter loads the model contract but
    # no prediction or fixture is produced for this known-failing expression.
    v1._convert_arm(ct, "dual", fit, control_package)
    dual_control_before = _validate_dual_control(ct, control_package)
    arm_receipts, package_identities, mil_checks = [], {}, {}
    for arm in ARMS:
        model_relative = f"models/{arm}.mlpackage"
        package = output / model_relative
        runtime, mil_checks[arm] = _convert_arm(
            ct, arm, fit, package, dual_control_before if arm == "dual" else None
        )
        package_sha, package_bytes = v1.package_tree_identity(package)
        fixture = v1._fixture(
            arm, fit, runtime, features, model_relative, package_sha, package_bytes
        )
        fixture_relative = f"fixtures/{arm}.json"
        fixture_payload = canonical_json_bytes(fixture)
        v1._write(output / fixture_relative, fixture_payload)
        arm_receipts.append(
            {
                "fitSHA256": v1.FIT_RECEIPT_SHA256,
                "fixtureByteCount": len(fixture_payload),
                "fixtureRelativePath": fixture_relative,
                "fixtureSHA256": sha256(fixture_payload),
                "modelArm": arm,
                "modelPackageByteCount": package_bytes,
                "modelPackageRelativePath": model_relative,
                "modelPackageTreeSHA256": package_sha,
                "vocabularySHA256": fit.receipt["vocabularySHA256"],
                "weightSeed": v1.WEIGHT_SEED,
                "weightsSHA256": fit.receipt["weightsSHA256"][arm],
            }
        )
        package_identities[arm] = (package_sha, package_bytes)

    if len(arm_receipts) != 3:
        raise ValueError("All three V2 arm exports are required")
    for arm in ARMS:
        if v1.package_tree_identity(output / f"models/{arm}.mlpackage") != package_identities[arm]:
            raise ValueError("V2 Core ML package changed during parity prediction")
    v1._assert_preserved(source_snapshot)
    v1._assert_preserved(fit_snapshot)
    v1._assert_preserved(parent_snapshot)
    artifacts_after = source_artifacts()
    fit_after = _fit_artifacts(fit)
    failed_packages_after = _failed_v1_packages()
    dual_control_after = _validate_dual_control(ct, control_package)
    states_after_runtime = _state_bundle(fit.models)
    if (
        artifacts_after != artifacts_before
        or fit_after != fit_before
        or failed_packages_after != failed_packages_before
        or dual_control_after != dual_control_before
        or states_after_runtime != states_before
        or states_after_equivalence != states_before
    ):
        raise ValueError("Source, fit, failed V1 packages, or original state changed")

    equivalence = {
        "cells": cells,
        "dualOriginalExpressionControl": {
            "after": dual_control_after,
            "before": dual_control_before,
            "predictionCount": 0,
        },
        "failedV1PackageIdentities": {
            "after": failed_packages_after,
            "before": failed_packages_before,
        },
        "fitArtifactIdentities": {"after": fit_after, "before": fit_before},
        "fitSHA256": v1.FIT_RECEIPT_SHA256,
        "outputScalarCount": 96 * (128 + 97),
        "parentDiagnostics": {
            "stage18": stage_diagnostic,
            "v1Failure": parent_failure,
        },
        "passed": True,
        "predictionCount": len(cells),
        "protocolSHA256": PARITY_PROTOCOL_SHA256,
        "retainedV1ReferenceCellCount": 72,
        "savedMILValidation": mil_checks,
        "schemaVersion": EQUIVALENCE_VERSION,
        "scope": "synthetic-export-portability-not-accuracy-or-production",
        "sourceArtifactIdentities": {
            "after": artifacts_after,
            "before": artifacts_before,
        },
        "stateIdentities": {
            "afterEquivalence": states_after_equivalence,
            "afterRuntimeGate": states_after_runtime,
            "beforeEquivalence": states_before,
        },
    }
    equivalence_payload = canonical_json_bytes(equivalence)
    v1._write(output / EQUIVALENCE_RECEIPT_NAME, equivalence_payload)
    receipt = {
        "arms": arm_receipts,
        "equivalenceReceiptByteCount": len(equivalence_payload),
        "equivalenceReceiptRelativePath": EQUIVALENCE_RECEIPT_NAME,
        "equivalenceReceiptSHA256": sha256(equivalence_payload),
        "featureSchemaVersion": v1.FEATURE_SCHEMA_VERSION,
        "schemaVersion": EXPORT_VERSION,
        "sourceArtifacts": artifacts_before,
    }
    # The detached export-receipt digest anchors the equivalence artifact.
    # This final success artifact is intentionally written last.
    v1._write(output / "export-receipt.json", canonical_json_bytes(receipt))
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
