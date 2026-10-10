"""Prepare the fixed internal splits for the explicit-domain-reject experiment.

Only the already authenticated, preserved HWRT/UJI *training* bundle is read.
The adapter extracts its exact app-raster plane into new versioned artifacts;
it performs no source decoding, fitting, inference, truth scoring, or app work.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
from pathlib import Path
import platform
from typing import Mapping, Sequence

import numpy as np

from ..contracts import canonical_json_bytes
from ..features import RASTER_HEIGHT, RASTER_WIDTH
from . import personal_hwrt_stroke_data as parent_data
from . import personal_hwrt_stroke_train as parent_train


DATA_VERSION = "personal-domain-reject-data-v1"
FIT_DATA_VERSION = "personal-domain-reject-fit-data-v1"
FIT_FINGERPRINTS_VERSION = "personal-domain-reject-fit-fingerprints-v1"
QUERY_INPUTS_VERSION = "personal-domain-reject-query-inputs-v1"
QUERY_TRUTH_VERSION = "personal-domain-reject-query-truth-v1"
COPY_UNION_VERSION = "personal-domain-reject-copy-union-v1"
SPLIT_VERSION = "personal-domain-reject-split-v1"
RASTER_VERSION = "app-raster-float32-plane-v1"
PROTOCOL_PATH = "docs/personal-domain-reject-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "790ffda2fd09500a57f09da3f3dde3d18cfb8d8ad12c55b4850dbb97de43c552"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
PARENT_RECEIPT_SHA256 = "5e00aa3ce986a07b7a3d4547ebc80b42307cf37a85f9f2e82870b6508b6957e5"
PARENT_METADATA_SHA256 = "56cdb11b58b6b02f36b30b7ed23c870681c44885af4bbd27cd5020bbdf761977"
PARENT_FIELDS_SHA256 = "df6969c2860d9b867b249f65f1bbf84d93b37570ab8bb8c04119aa573620cb5f"
PARENT_ROWS = 10_073
UJI_ROWS = 6_208
HWRT_ROWS = 3_865
FIT_ROWS = 6_199
QUERY_ROWS = 3_874
DISTINCT_QUERY_ROWS = 6_978
HWRT_FIT_ROWS = 3_095
HWRT_QUERY_ROWS = 770
UJI_FOLD_ROWS = 3_104
FOLDS = ("A16-to-B16", "B16-to-A16")
WRITER_SALT = b"ichart-domain-reject-writer-v1"
HWRT_SALT = b"ichart-domain-reject-hwrt-v1"
ROOT = Path(__file__).resolve().parents[3]
RASTER_SHAPE = (1, RASTER_HEIGHT, RASTER_WIDTH)

NEW_CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_data.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_train.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_evaluate.py",
    "recognition_ml/tests/test_personal_domain_reject.py",
    "recognition_ml/tests/test_personal_domain_reject_data.py",
    "recognition_ml/tests/test_personal_domain_reject_train.py",
    "recognition_ml/tests/test_personal_domain_reject_evaluate.py",
)

_FIT_ROW_FIELDS = {
    "opaqueID", "label", "source", "writer", "session", "nativeSymbolID",
    "rasterSHA256", "normalizedGeometrySHA256",
}
_BLIND_FIELDS = {"opaqueID", "rasterSHA256", "normalizedGeometrySHA256"}
_TRUTH_FIELDS = _FIT_ROW_FIELDS | {"copyReasons"}


def _salted(salt: bytes, value: str) -> str:
    return hashlib.sha256(salt + b"\0" + value.encode("utf-8")).hexdigest()


def code_identity() -> dict[str, str]:
    """Bind the authenticated parent and all new reject-experiment code."""

    identity = dict(parent_train.code_identity())
    for relative in NEW_CODE_PATHS:
        identity[relative] = parent_data._sha(parent_data._read_regular(ROOT / relative))
    if identity[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Frozen domain-reject protocol changed")
    return dict(sorted(identity.items()))


def fit_artifact_paths(fold: str) -> tuple[str, str]:
    _validate_fold(fold)
    return (f"folds/{fold}/fit-rasters.npy", f"folds/{fold}/fit.json")


def query_artifact_paths(fold: str) -> tuple[str, str]:
    _validate_fold(fold)
    return (f"folds/{fold}/query-rasters.npy", f"folds/{fold}/query-inputs.json")


def _fold_paths(fold: str) -> dict[str, str]:
    _validate_fold(fold)
    prefix = f"folds/{fold}"
    return {
        "fitRasters": f"{prefix}/fit-rasters.npy",
        "fitMetadata": f"{prefix}/fit.json",
        "fitFingerprints": f"{prefix}/fit-fingerprints.json",
        "queryRasters": f"{prefix}/query-rasters.npy",
        "queryInputs": f"{prefix}/query-inputs.json",
        "queryTruth": f"{prefix}/query-truth.json",
    }


def _validate_fold(fold: str) -> None:
    if fold not in FOLDS:
        raise ValueError("Unknown fixed domain-reject fold")


def _domain(path: Path, source_vocabulary: Sequence[str]):
    payload = parent_data._read_regular(Path(path))
    if parent_data._sha(payload) != DOMAIN_SHA256:
        raise ValueError("Pinned chord-domain export changed")
    value = parent_data._json(payload, "domain-reject chord domain")
    old = list(source_vocabulary[:97])
    allowed = value.get("allowedLabels")
    if (
        value.get("version") != "chord-recognition-domain-v1"
        or value.get("vocabulary") != old
        or not isinstance(allowed, list)
        or len(allowed) != 41
        or len(set(allowed)) != 41
        or any(label not in old for label in allowed)
    ):
        raise ValueError("Pinned chord-domain vocabulary changed")
    from . import personal_domain_reject as core

    vocabulary = core.make_vocabulary(tuple(source_vocabulary), tuple(allowed))
    return value, vocabulary, payload


def _validate_parent_rows(metadata: Mapping[str, object]) -> tuple[list[dict], tuple[str, ...]]:
    if (
        set(metadata) != {"version", "vocabulary", "rows"}
        or metadata.get("version") != parent_data.TRAINING_VERSION
        or not isinstance(metadata.get("vocabulary"), list)
        or not isinstance(metadata.get("rows"), list)
        or len(metadata["rows"]) != PARENT_ROWS
    ):
        raise ValueError("Parent training metadata contract changed")
    vocabulary = tuple(metadata["vocabulary"])
    rows = metadata["rows"]
    if (
        len(vocabulary) != 102
        or len(set(vocabulary)) != 102
        or tuple(vocabulary[97:]) != parent_train.NOVEL_LABELS
        or len({row.get("opaqueID") for row in rows}) != PARENT_ROWS
    ):
        raise ValueError("Parent vocabulary or identity coverage changed")

    uji = [row for row in rows if row.get("source") == "uji"]
    hwrt = [row for row in rows if row.get("source") == "hwrt"]
    writers = sorted({row.get("writer") for row in uji})
    if (
        len(uji) != UJI_ROWS
        or len(hwrt) != HWRT_ROWS
        or len(writers) != 32
        or any(not isinstance(writer, str) for writer in writers)
    ):
        raise ValueError("Parent UJI/HWRT training role counts changed")
    for writer in writers:
        selected = [row for row in uji if row["writer"] == writer]
        if (
            len(selected) != 194
            or {row.get("session") for row in selected} != {1, 2}
            or any(row.get("nativeSymbolID") is not None for row in selected)
            or any(
                sum(row["session"] == session and row["label"] == label for row in selected) != 1
                for session in (1, 2)
                for label in vocabulary[:97]
            )
        ):
            raise ValueError("Parent UJI writer/session/label grid changed")
    native_counts = Counter(row.get("nativeSymbolID") for row in hwrt)
    if (
        set(native_counts) != set(parent_train.NATIVE_MAPPING)
        or any(
            row.get("writer") is not None
            or row.get("session") is not None
            or parent_train.NATIVE_MAPPING.get(row.get("nativeSymbolID")) != row.get("label")
            for row in hwrt
        )
    ):
        raise ValueError("Parent HWRT native mapping changed")
    for row in rows:
        if (
            set(row) != parent_train.ROW_FIELDS
            or row.get("label") not in vocabulary
            or any(not parent_data._digest(row.get(key)) for key in (
                "opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"
            ))
        ):
            raise ValueError("Parent training row schema changed")
    return rows, vocabulary


def _split_rows(rows: Sequence[Mapping[str, object]]) -> tuple[dict, dict[str, dict[str, list[int]]]]:
    writers = sorted(
        {row["writer"] for row in rows if row["source"] == "uji"},
        key=lambda writer: (_salted(WRITER_SALT, writer), writer),
    )
    if len(writers) != 32:
        raise ValueError("Exactly 32 training UJI writers are required")
    a_writers, b_writers = tuple(writers[:16]), tuple(writers[16:])
    uji_a = [index for index, row in enumerate(rows) if row["source"] == "uji" and row["writer"] in a_writers]
    uji_b = [index for index, row in enumerate(rows) if row["source"] == "uji" and row["writer"] in b_writers]

    native_ids = sorted(parent_train.NATIVE_MAPPING)
    hwrt_fit: list[int] = []
    hwrt_query: list[int] = []
    native_summary = {}
    for native in native_ids:
        members = [
            index for index, row in enumerate(rows)
            if row["source"] == "hwrt" and row["nativeSymbolID"] == native
        ]
        members.sort(key=lambda index: (
            _salted(HWRT_SALT, rows[index]["opaqueID"]), rows[index]["opaqueID"]
        ))
        query_count = len(members) // 5
        query, fit = members[:query_count], members[query_count:]
        hwrt_query.extend(query); hwrt_fit.extend(fit)
        native_summary[native] = {"total": len(members), "fit": len(fit), "query": len(query)}
    hwrt_fit.sort(); hwrt_query.sort()
    if (
        len(uji_a) != UJI_FOLD_ROWS
        or len(uji_b) != UJI_FOLD_ROWS
        or len(hwrt_fit) != HWRT_FIT_ROWS
        or len(hwrt_query) != HWRT_QUERY_ROWS
        or set(hwrt_fit) & set(hwrt_query)
    ):
        raise ValueError("Fixed UJI/HWRT split counts changed")

    indexes = {
        "A16-to-B16": {"fit": sorted(uji_a + hwrt_fit), "query": sorted(uji_b + hwrt_query)},
        "B16-to-A16": {"fit": sorted(uji_b + hwrt_fit), "query": sorted(uji_a + hwrt_query)},
    }
    for fold in FOLDS:
        if (
            len(indexes[fold]["fit"]) != FIT_ROWS
            or len(indexes[fold]["query"]) != QUERY_ROWS
            or set(indexes[fold]["fit"]) & set(indexes[fold]["query"])
        ):
            raise ValueError("Fixed fold coverage changed")
    distinct_queries = {
        rows[index]["opaqueID"] for fold in FOLDS for index in indexes[fold]["query"]
    }
    if len(distinct_queries) != DISTINCT_QUERY_ROWS:
        raise ValueError("Distinct/reused query coverage changed")

    split = {
        "version": SPLIT_VERSION,
        "writerSalt": WRITER_SALT.decode(),
        "hwrtSalt": HWRT_SALT.decode(),
        "writerBlocks": {"A16": list(a_writers), "B16": list(b_writers)},
        "hwrtNativeCounts": native_summary,
        "folds": {
            fold: {
                "fitOpaqueIDs": [rows[index]["opaqueID"] for index in indexes[fold]["fit"]],
                "queryOpaqueIDs": [rows[index]["opaqueID"] for index in indexes[fold]["query"]],
                "fitRows": FIT_ROWS,
                "queryRows": QUERY_ROWS,
            }
            for fold in FOLDS
        },
        "counts": {
            "parentRows": PARENT_ROWS,
            "ujiRows": UJI_ROWS,
            "hwrtRows": HWRT_ROWS,
            "hwrtFitRows": HWRT_FIT_ROWS,
            "hwrtQueryRows": HWRT_QUERY_ROWS,
            "queryExposures": QUERY_ROWS * 2,
            "distinctQueryRows": DISTINCT_QUERY_ROWS,
        },
    }
    return split, indexes


def _verify_plane(plane: np.ndarray, row: Mapping[str, object]) -> np.ndarray:
    value = np.ascontiguousarray(plane, dtype="<f4")
    if value.shape != (RASTER_HEIGHT, RASTER_WIDTH) or not np.isfinite(value).all():
        raise ValueError("Parent raster plane is malformed")
    pixels = np.rint(value * np.float32(255.0)).astype(np.uint8)
    reconstructed = pixels.astype(np.float32) / np.float32(255.0)
    if (
        not np.array_equal(value, reconstructed)
        or parent_data._sha(pixels.tobytes(order="C")) != row["rasterSHA256"]
    ):
        raise ValueError("Extracted raster differs from authenticated parent raster")
    return value


def _materialize(parent_fields: np.ndarray, rows: Sequence[Mapping[str, object]],
                 indexes: Sequence[int], path: Path) -> None:
    output = np.lib.format.open_memmap(
        path, mode="w+", dtype="<f4", shape=(len(indexes), *RASTER_SHAPE)
    )
    try:
        for target, source in enumerate(indexes):
            output[target, 0] = _verify_plane(parent_fields[source, 0], rows[source])
            if (target + 1) % 128 == 0 or target + 1 == len(indexes):
                print(f"materialized {target + 1}/{len(indexes)} rasters", flush=True)
        output.flush()
    finally:
        del output


def _project_row(row: Mapping[str, object]) -> dict:
    return {key: row[key] for key in _FIT_ROW_FIELDS}


def _blind_row(row: Mapping[str, object]) -> dict:
    return {key: row[key] for key in _BLIND_FIELDS}


def _copy_reasons(fit_rows: Sequence[Mapping[str, object]],
                  query_rows: Sequence[Mapping[str, object]]) -> dict[str, tuple[str, ...]]:
    fields = ("rasterSHA256", "normalizedGeometrySHA256")
    fit_values = {field: {row[field] for row in fit_rows} for field in fields}
    query_groups = {field: defaultdict(list) for field in fields}
    for row in query_rows:
        for field in fields:
            query_groups[field][row[field]].append(row["opaqueID"])
    reasons: dict[str, set[str]] = defaultdict(set)
    for row in query_rows:
        for field in fields:
            if row[field] in fit_values[field]:
                reasons[row["opaqueID"]].add("fit-" + field)
            peers = query_groups[field][row[field]]
            if len(peers) > 1 and row["opaqueID"] != min(peers):
                reasons[row["opaqueID"]].add("repeated-query-" + field)
    return {opaque: tuple(sorted(values)) for opaque, values in reasons.items()}


def _artifact(path: Path) -> dict:
    return parent_data._artifact(path)


def _parent_binding(receipt: Mapping[str, object]) -> dict:
    return {
        "dataReceiptSHA256": PARENT_RECEIPT_SHA256,
        "trainingMetadataSHA256": PARENT_METADATA_SHA256,
        "fieldsSHA256": PARENT_FIELDS_SHA256,
        "dataVersion": parent_data.DATA_VERSION,
        "fieldVersion": parent_data.FIELD_VERSION,
        "rows": PARENT_ROWS,
        "sourceBindings": receipt["sourceBindings"],
    }


def _receipt(artifacts: Mapping[str, dict], code: Mapping[str, str], parent: Mapping[str, object],
             domain_bytes: bytes, vocabulary, folds: Mapping[str, object]) -> dict:
    return {
        "version": DATA_VERSION,
        "protocolSHA256": PROTOCOL_SHA256,
        "rasterVersion": RASTER_VERSION,
        "parent": dict(parent),
        "domain": {"bytes": len(domain_bytes), "sha256": DOMAIN_SHA256},
        "sourceVocabulary": list(vocabulary.source_labels),
        "legalOldLabels": list(vocabulary.legal_labels[:41]),
        "candidateLabels": list(vocabulary.candidate_labels),
        "folds": dict(folds),
        "artifacts": dict(artifacts),
        "codeSHA256": dict(code),
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)},
        "roleGuards": {
            "parentTrainingBundleOnly": True,
            "oldDevelopmentWritersUsed": False,
            "reservedWritersUsed": False,
            "privateInkUsed": False,
            "modelInferencePerformed": False,
            "optimizationPerformed": False,
            "queryTruthOpenedByFitLoader": False,
            "queryTruthOpenedByPredictorLoader": False,
        },
    }


def prepare(parent_directory: Path, domain_path: Path, protocol: Path, output: Path) -> dict:
    protocol_bytes = parent_data._read_regular(Path(protocol))
    if parent_data._sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen domain-reject protocol")
    code = code_identity()
    parent_directory = Path(parent_directory)
    receipt_path = parent_directory / "data-receipt.json"
    metadata_path = parent_directory / "training.json"
    fields_path = parent_directory / "fields.npy"
    receipt_bytes = parent_data._read_regular(receipt_path)
    metadata_bytes = parent_data._read_regular(
        metadata_path, maximum=parent_data._MAX_SOURCE_BYTES
    )
    if (
        parent_data._sha(receipt_bytes) != PARENT_RECEIPT_SHA256
        or parent_data._sha(metadata_bytes) != PARENT_METADATA_SHA256
    ):
        raise ValueError("Pinned parent training receipt or metadata changed")
    parent_fields, parent_metadata, parent_receipt = parent_data.load_training(parent_directory)
    if (
        parent_receipt.get("artifacts", {}).get("fields.npy", {}).get("sha256") != PARENT_FIELDS_SHA256
        or parent_receipt.get("artifacts", {}).get("training.json", {}).get("sha256") != PARENT_METADATA_SHA256
        or parent_receipt.get("role") != "training"
    ):
        raise ValueError("Pinned parent raster artifact changed")
    rows, source_vocabulary = _validate_parent_rows(parent_metadata)
    domain, vocabulary, domain_bytes = _domain(domain_path, source_vocabulary)
    split, indexes = _split_rows(rows)
    destination = parent_data._fresh_output(output)
    (destination / "folds").mkdir(mode=0o700)
    artifacts: dict[str, dict] = {}
    fold_summary = {}
    for fold in FOLDS:
        fold_dir = destination / "folds" / fold
        fold_dir.mkdir(mode=0o700)
        selected_fit = indexes[fold]["fit"]
        selected_query = indexes[fold]["query"]
        fit_rows = [_project_row(rows[index]) for index in selected_fit]
        query_full = [_project_row(rows[index]) for index in selected_query]
        reasons = _copy_reasons(fit_rows, query_full)
        query_blind = [_blind_row(row) for row in query_full]
        truth_rows = [
            {**row, "copyReasons": list(reasons.get(row["opaqueID"], ()))}
            for row in query_full
        ]
        fit_metadata = {
            "version": FIT_DATA_VERSION, "fold": fold,
            "vocabulary": list(source_vocabulary), "rows": fit_rows,
        }
        fit_fingerprints = {
            "version": FIT_FINGERPRINTS_VERSION, "fold": fold,
            "rows": [_blind_row(row) for row in fit_rows],
        }
        query_inputs = {
            "version": QUERY_INPUTS_VERSION, "fold": fold,
            "vocabulary": list(source_vocabulary), "rows": query_blind,
        }
        query_truth = {
            "version": QUERY_TRUTH_VERSION, "fold": fold, "rows": truth_rows,
            "copyUnion": {
                "version": COPY_UNION_VERSION,
                "hashFields": ["rasterSHA256", "normalizedGeometrySHA256"],
                "fitRows": FIT_ROWS,
                "queryRows": QUERY_ROWS,
                "representativeRule": "lexicographically-smallest-opaqueID-per-query-hash",
                "affectedOpaqueIDs": sorted(reasons),
                "reasonCounts": dict(sorted(Counter(
                    reason for values in reasons.values() for reason in values
                ).items())),
            },
        }
        paths = _fold_paths(fold)
        _materialize(parent_fields, rows, selected_fit, destination / paths["fitRasters"])
        _materialize(parent_fields, rows, selected_query, destination / paths["queryRasters"])
        for key, value in (
            ("fitMetadata", fit_metadata), ("fitFingerprints", fit_fingerprints),
            ("queryInputs", query_inputs), ("queryTruth", query_truth),
        ):
            parent_data._write(destination / paths[key], canonical_json_bytes(value))
        for relative in paths.values():
            artifacts[relative] = _artifact(destination / relative)
        fold_summary[fold] = {
            "fitRows": FIT_ROWS,
            "queryRows": QUERY_ROWS,
            "fitUJI": UJI_FOLD_ROWS,
            "fitHWRT": HWRT_FIT_ROWS,
            "queryUJI": UJI_FOLD_ROWS,
            "queryHWRT": HWRT_QUERY_ROWS,
            "copyExcludedRows": len(reasons),
            "paths": paths,
        }
    parent_data._write(destination / "split.json", canonical_json_bytes(split))
    artifacts["split.json"] = _artifact(destination / "split.json")
    receipt = _receipt(
        artifacts, code, _parent_binding(parent_receipt), domain_bytes, vocabulary, fold_summary
    )

    # Reauthenticate immutable parents and executable inputs before publishing last.
    if (
        parent_data._sha(parent_data._read_regular(receipt_path)) != PARENT_RECEIPT_SHA256
        or parent_data._sha(parent_data._read_regular(
            metadata_path, maximum=parent_data._MAX_SOURCE_BYTES
        )) != PARENT_METADATA_SHA256
        or parent_data._sha_file(fields_path)[1] != PARENT_FIELDS_SHA256
        or code_identity() != code
        or parent_data._sha(parent_data._read_regular(protocol)) != PROTOCOL_SHA256
        or parent_data._sha(parent_data._read_regular(domain_path)) != DOMAIN_SHA256
    ):
        raise ValueError("Bound parent, code, protocol, or domain changed during preparation")
    parent_data._write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


def _expected_artifacts() -> set[str]:
    return {"split.json"} | {
        relative for fold in FOLDS for relative in _fold_paths(fold).values()
    }


def _validate_receipt(receipt: Mapping[str, object]) -> None:
    expected_keys = {
        "version", "protocolSHA256", "rasterVersion", "parent", "domain",
        "sourceVocabulary", "legalOldLabels", "candidateLabels", "folds",
        "artifacts", "codeSHA256", "runtime", "roleGuards",
    }
    domain = receipt.get("domain")
    if (
        set(receipt) != expected_keys
        or receipt.get("version") != DATA_VERSION
        or receipt.get("protocolSHA256") != PROTOCOL_SHA256
        or receipt.get("rasterVersion") != RASTER_VERSION
        or receipt.get("codeSHA256") != code_identity()
        or not isinstance(domain, dict)
        or set(domain) != {"bytes", "sha256"}
        or domain.get("sha256") != DOMAIN_SHA256
        or type(domain.get("bytes")) is not int
        or domain["bytes"] <= 0
        or set(receipt.get("artifacts", {})) != _expected_artifacts()
        or set(receipt.get("folds", {})) != set(FOLDS)
        or receipt.get("roleGuards") != {
            "parentTrainingBundleOnly": True,
            "oldDevelopmentWritersUsed": False,
            "reservedWritersUsed": False,
            "privateInkUsed": False,
            "modelInferencePerformed": False,
            "optimizationPerformed": False,
            "queryTruthOpenedByFitLoader": False,
            "queryTruthOpenedByPredictorLoader": False,
        }
    ):
        raise ValueError("Domain-reject data receipt contract changed")
    parent = receipt.get("parent")
    if (
        not isinstance(parent, dict)
        or parent.get("dataReceiptSHA256") != PARENT_RECEIPT_SHA256
        or parent.get("trainingMetadataSHA256") != PARENT_METADATA_SHA256
        or parent.get("fieldsSHA256") != PARENT_FIELDS_SHA256
        or parent.get("dataVersion") != parent_data.DATA_VERSION
        or parent.get("fieldVersion") != parent_data.FIELD_VERSION
        or parent.get("rows") != PARENT_ROWS
    ):
        raise ValueError("Parent training binding changed")
    parent_data._validate_bound_identity({
        "codeSHA256": parent_data.code_identity(),
        "sourceBindings": parent["sourceBindings"],
    })
    source = receipt.get("sourceVocabulary")
    legal = receipt.get("legalOldLabels")
    candidate = receipt.get("candidateLabels")
    if (
        not isinstance(source, list)
        or len(source) != 102
        or len(set(source)) != 102
        or source[:97] != sorted(source[:97])
        or tuple(source[97:]) != parent_train.NOVEL_LABELS
        or not isinstance(legal, list)
        or len(legal) != 41
        or len(set(legal)) != 41
        or any(label not in source[:97] for label in legal)
        or candidate != legal + list(parent_train.NOVEL_LABELS) + ["REJECT"]
    ):
        raise ValueError("Domain-reject source/candidate vocabulary changed")
    for fold in FOLDS:
        summary = receipt["folds"][fold]
        if (
            set(summary) != {
                "fitRows", "queryRows", "fitUJI", "fitHWRT", "queryUJI",
                "queryHWRT", "copyExcludedRows", "paths",
            }
            or summary["fitRows"] != FIT_ROWS
            or summary["queryRows"] != QUERY_ROWS
            or summary["fitUJI"] != UJI_FOLD_ROWS
            or summary["queryUJI"] != UJI_FOLD_ROWS
            or summary["fitHWRT"] != HWRT_FIT_ROWS
            or summary["queryHWRT"] != HWRT_QUERY_ROWS
            or type(summary["copyExcludedRows"]) is not int
            or not 0 <= summary["copyExcludedRows"] <= QUERY_ROWS
            or summary["paths"] != _fold_paths(fold)
        ):
            raise ValueError("Domain-reject fold summary changed")
    for identity in receipt["artifacts"].values():
        if (
            not isinstance(identity, dict)
            or set(identity) != {"bytes", "sha256"}
            or type(identity["bytes"]) is not int
            or identity["bytes"] <= 0
            or not parent_data._digest(identity["sha256"])
        ):
            raise ValueError("Domain-reject artifact identity changed")


def _read_bound(directory: Path, receipt: Mapping[str, object], relative: str,
                *, maximum: int = parent_data._MAX_SOURCE_BYTES) -> bytes:
    payload = parent_data._read_regular(directory / relative, maximum=maximum)
    if receipt["artifacts"].get(relative) != {
        "bytes": len(payload), "sha256": parent_data._sha(payload)
    }:
        raise ValueError("Bound domain-reject artifact changed")
    return payload


def _validate_rows(metadata: Mapping[str, object], fold: str, *, fit: bool) -> None:
    version = FIT_DATA_VERSION if fit else QUERY_INPUTS_VERSION
    expected_fields = _FIT_ROW_FIELDS if fit else _BLIND_FIELDS
    expected_rows = FIT_ROWS if fit else QUERY_ROWS
    if (
        set(metadata) != {"version", "fold", "vocabulary", "rows"}
        or metadata.get("version") != version
        or metadata.get("fold") != fold
        or not isinstance(metadata.get("vocabulary"), list)
        or len(metadata["vocabulary"]) != 102
        or not isinstance(metadata.get("rows"), list)
        or len(metadata["rows"]) != expected_rows
        or len({row.get("opaqueID") for row in metadata["rows"]}) != expected_rows
    ):
        raise ValueError("Domain-reject fold metadata coverage changed")
    for row in metadata["rows"]:
        if (
            not isinstance(row, dict)
            or set(row) != expected_fields
            or any(not parent_data._digest(row.get(key)) for key in _BLIND_FIELDS)
            or (
                fit
                and (
                    row["label"] not in metadata["vocabulary"]
                    or row["source"] not in ("uji", "hwrt")
                    or (
                        row["source"] == "uji"
                        and (
                            not isinstance(row["writer"], str)
                            or row["session"] not in (1, 2)
                            or row["nativeSymbolID"] is not None
                        )
                    )
                    or (
                        row["source"] == "hwrt"
                        and (
                            row["writer"] is not None
                            or row["session"] is not None
                            or not isinstance(row["nativeSymbolID"], str)
                        )
                    )
                )
            )
        ):
            raise ValueError("Domain-reject fold row changed")


def _load(data_directory: Path, fold: str, *, fit: bool):
    _validate_fold(fold)
    directory = Path(data_directory)
    receipt_bytes = parent_data._read_regular(directory / "data-receipt.json")
    receipt = parent_data._json(receipt_bytes, "domain-reject data receipt")
    _validate_receipt(receipt)
    paths = _fold_paths(fold)
    raster_relative = paths["fitRasters" if fit else "queryRasters"]
    metadata_relative = paths["fitMetadata" if fit else "queryInputs"]
    metadata_bytes = _read_bound(directory, receipt, metadata_relative)
    metadata = parent_data._json(metadata_bytes, metadata_relative)
    _validate_rows(metadata, fold, fit=fit)
    raster_path = directory / raster_relative
    identity = receipt["artifacts"][raster_relative]
    if parent_data._sha_file(raster_path) != (identity["bytes"], identity["sha256"]):
        raise ValueError("Domain-reject raster artifact changed")
    rows = FIT_ROWS if fit else QUERY_ROWS
    rasters = np.load(raster_path, mmap_mode="r", allow_pickle=False)
    if (
        not isinstance(rasters, np.memmap)
        or rasters.dtype != np.dtype("<f4")
        or rasters.shape != (rows, *RASTER_SHAPE)
        or not rasters.flags.c_contiguous
        or rasters.flags.writeable
    ):
        raise ValueError("Domain-reject raster storage changed")
    return rasters, metadata, receipt


def load_fit(data_directory: Path, fold: str):
    """Load only one fold's fitting rasters and label-bearing metadata."""

    return _load(data_directory, fold, fit=True)


def load_query(data_directory: Path, fold: str):
    """Load only one fold's blind query rasters and input hashes; never truth."""

    return _load(data_directory, fold, fit=False)


def load_fit_fingerprints(data_directory: Path, fold: str):
    """Load label-free fit fingerprints for copy accounting; never fit labels/truth."""

    _validate_fold(fold)
    directory = Path(data_directory)
    receipt_bytes = parent_data._read_regular(directory / "data-receipt.json")
    receipt = parent_data._json(receipt_bytes, "domain-reject data receipt")
    _validate_receipt(receipt)
    relative = _fold_paths(fold)["fitFingerprints"]
    payload = _read_bound(directory, receipt, relative)
    value = parent_data._json(payload, relative)
    if (
        set(value) != {"version", "fold", "rows"}
        or value.get("version") != FIT_FINGERPRINTS_VERSION
        or value.get("fold") != fold
        or not isinstance(value.get("rows"), list)
        or len(value["rows"]) != FIT_ROWS
        or len({row.get("opaqueID") for row in value["rows"]}) != FIT_ROWS
        or any(
            not isinstance(row, dict)
            or set(row) != _BLIND_FIELDS
            or any(not parent_data._digest(row.get(key)) for key in _BLIND_FIELDS)
            for row in value["rows"]
        )
    ):
        raise ValueError("Domain-reject fit fingerprints changed")
    return value, receipt


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent-data", type=Path, required=True)
    parser.add_argument("--domain", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    receipt = prepare(args.parent_data, args.domain, args.protocol, args.output)
    print(canonical_json_bytes({
        "folds": receipt["folds"], "version": receipt["version"]
    }).decode("utf-8"), flush=True)


if __name__ == "__main__":
    main()
