"""Prepare versioned UJI/HWRT inputs for the unoriented-field experiment.

This adapter deliberately reuses the frozen source-selection and provenance
helpers from :mod:`personal_hwrt_stroke_data`, while publishing a distinct
field/data identity.  It performs feature preparation only: no optimization,
model inference, correctness join, private ink, or reserved-writer encoding.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import platform
from typing import Mapping, Sequence

import numpy as np

from ..contracts import canonical_json_bytes
from ..features import InkStroke, RASTER_HEIGHT, RASTER_WIDTH, rasterize
from . import personal_hwrt_stroke_data as frozen_data
from . import personal_unoriented_stroke_field as neutral_field
from .uji_personal import Sample, trajectory_fingerprint


DATA_VERSION = "personal-unoriented-hwrt-data-v1"
TRAINING_VERSION = "personal-unoriented-hwrt-training-v1"
DEVELOPMENT_INPUTS_VERSION = "personal-unoriented-hwrt-development-inputs-v1"
DEVELOPMENT_TRUTH_VERSION = "personal-unoriented-hwrt-development-truth-v1"
COPY_UNION_VERSION = "personal-unoriented-hwrt-input-copy-union-v1"
PROTOCOL_PATH = "docs/personal-unoriented-stroke-field-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "4d72f1e61e409e8da9c563dc7a8eca430370675b5b6fa81eeab9dad327178fe3"
FIELD_VERSION = neutral_field.VERSION
MODEL_VERSION = neutral_field.MODEL_VERSION
ROOT = Path(__file__).resolve().parents[3]

TRAINING_ROWS = frozen_data.TRAINING_ROWS
DEVELOPMENT_ROWS = frozen_data.DEVELOPMENT_ROWS
UJI_TRAINING_ROWS = frozen_data.UJI_TRAINING_ROWS
UJI_DEVELOPMENT_ROWS = frozen_data.UJI_DEVELOPMENT_ROWS
HWRT_TRAINING_ROWS = frozen_data.HWRT_TRAINING_ROWS
HWRT_DEVELOPMENT_ROWS = frozen_data.HWRT_DEVELOPMENT_ROWS
FIELD_SHAPE = (neutral_field.CHANNEL_COUNT, RASTER_HEIGHT, RASTER_WIDTH)

PRIOR_TRAINING_DIRECTORY = Path(
    "/Users/benirossman/.local/share/ichart/recognition-development/"
    "hwrt-stroke-field-20261003.8ZTPn0/training-data"
)
PRIOR_TRAINING_RECEIPT_SHA256 = (
    "5e00aa3ce986a07b7a3d4547ebc80b42307cf37a85f9f2e82870b6508b6957e5"
)
PRIOR_TRAINING_METADATA_SHA256 = (
    "56cdb11b58b6b02f36b30b7ed23c870681c44885af4bbd27cd5020bbdf761977"
)
PRIOR_TRAINING_ROWS = 10_073
PRIOR_CONTROL_STATE_SHA256 = (
    "ca97f42d345c3e7e777ef92412db30e7a26930f0b2f8411873e5db8505970c99"
)
PRIOR_SCHEDULE_SHA256 = (
    "d1ef91c13bb4477de88c57510851149177e528858f0e2bfcf69643b8c062d6ed"
)
PRIOR_AFFINE_DRAWS_SHA256 = (
    "1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc"
)

NEW_CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/research/personal_unoriented_stroke_field.py",
    "recognition_ml/ichart_recognition_ml/research/personal_unoriented_hwrt_data.py",
    "recognition_ml/ichart_recognition_ml/research/personal_unoriented_hwrt_train.py",
    "recognition_ml/ichart_recognition_ml/research/personal_unoriented_hwrt_evaluate.py",
    "recognition_ml/tests/test_personal_unoriented_stroke_field.py",
    "recognition_ml/tests/test_personal_unoriented_hwrt_data.py",
    "recognition_ml/tests/test_personal_unoriented_hwrt_train.py",
    "recognition_ml/tests/test_personal_unoriented_hwrt_evaluate.py",
)

_ROW_FIELDS = {
    "opaqueID", "label", "source", "writer", "session", "nativeSymbolID",
    "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256",
}
_BLIND_FIELDS = {
    "opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256",
}
_STABLE_PRIOR_FIELDS = (
    "opaqueID", "label", "source", "writer", "session", "nativeSymbolID",
    "rasterSHA256", "normalizedGeometrySHA256",
)


def code_identity() -> dict[str, str]:
    """Bind the frozen parent pipeline and every new experiment boundary."""

    # Lazy import avoids a cycle: the new trainer imports this data seam.
    from . import personal_hwrt_stroke_train as frozen_train

    identity = dict(frozen_train.code_identity())
    for name in NEW_CODE_PATHS:
        identity[name] = frozen_data._sha(frozen_data._read_regular(ROOT / name))
    if identity[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Frozen unoriented protocol changed")
    return dict(sorted(identity.items()))


def _prior_identity() -> dict[str, object]:
    return {
        "dataReceiptSHA256": PRIOR_TRAINING_RECEIPT_SHA256,
        "trainingMetadataSHA256": PRIOR_TRAINING_METADATA_SHA256,
        "fieldVersion": frozen_data.FIELD_VERSION,
        "rows": PRIOR_TRAINING_ROWS,
    }


def _load_prior_training_metadata(
    directory: Path = PRIOR_TRAINING_DIRECTORY,
) -> tuple[dict, dict, str]:
    receipt_path = Path(directory) / "data-receipt.json"
    metadata_path = Path(directory) / "training.json"
    receipt_bytes = frozen_data._read_regular(receipt_path)
    metadata_bytes = frozen_data._read_regular(
        metadata_path, maximum=frozen_data._MAX_SOURCE_BYTES
    )
    if frozen_data._sha(receipt_bytes) != PRIOR_TRAINING_RECEIPT_SHA256:
        raise ValueError("Preserved prior training receipt changed")
    if frozen_data._sha(metadata_bytes) != PRIOR_TRAINING_METADATA_SHA256:
        raise ValueError("Preserved prior training metadata changed")
    metadata, receipt, receipt_sha = frozen_data._training_metadata(directory)
    if (
        receipt_sha != PRIOR_TRAINING_RECEIPT_SHA256
        or receipt.get("fieldVersion") != frozen_data.FIELD_VERSION
        or receipt.get("counts", {}).get("rows") != PRIOR_TRAINING_ROWS
        or metadata.get("rows") is None
    ):
        raise ValueError("Preserved prior training identity is incomplete")
    return metadata, receipt, receipt_sha


def _reversed_strokes(strokes: Sequence[InkStroke]) -> tuple[InkStroke, ...]:
    return tuple(
        InkStroke(tuple(reversed(stroke.points))) for stroke in reversed(tuple(strokes))
    )


@dataclass(frozen=True)
class _ReversalCheck:
    auxiliary_equal: bool
    occupancy_mismatch_pixels: int
    occupancy_maximum_absolute_error: float


def _feature_row(row) -> tuple[np.ndarray, dict, _ReversalCheck]:
    field = np.ascontiguousarray(
        neutral_field.encode_unoriented_stroke_field(row.strokes), dtype="<f4"
    )
    if field.shape != FIELD_SHAPE or not np.isfinite(field).all():
        raise ValueError("Invalid unoriented stroke-field output")
    raster = rasterize(row.strokes).pixels
    expected = (
        np.frombuffer(raster, np.uint8)
        .reshape(RASTER_HEIGHT, RASTER_WIDTH)
        .astype(np.float32)
        / np.float32(255.0)
    )
    if not np.array_equal(field[0], expected):
        raise ValueError("Unoriented field occupancy differs from app raster")

    reversed_field = np.ascontiguousarray(
        neutral_field.encode_unoriented_stroke_field(_reversed_strokes(row.strokes)),
        dtype="<f4",
    )
    auxiliary_equal = field[1:].tobytes(order="C") == reversed_field[1:].tobytes(order="C")
    if not auxiliary_equal:
        raise ValueError("Unoriented auxiliary planes changed under global reversal")
    occupancy_difference = np.abs(field[0] - reversed_field[0])
    mismatch_pixels = int(np.count_nonzero(occupancy_difference))
    maximum_error = float(occupancy_difference.max(initial=np.float32(0.0)))

    sample = Sample(row.writer or "hwrt", row.session or 1, row.label, row.strokes)
    metadata = {
        "opaqueID": row.opaque_id,
        "label": row.label,
        "source": row.source,
        "writer": row.writer,
        "session": row.session,
        "nativeSymbolID": row.native_symbol_id,
        "rasterSHA256": frozen_data._sha(raster),
        "normalizedGeometrySHA256": trajectory_fingerprint(sample),
        "fieldSHA256": frozen_data._sha(field.tobytes(order="C")),
    }
    return field, metadata, _ReversalCheck(True, mismatch_pixels, maximum_error)


def _encode_rows(rows: Sequence, path: Path, *, check_reversal: bool) -> tuple[list[dict], dict | None]:
    fields = np.lib.format.open_memmap(
        path, mode="w+", dtype="<f4", shape=(len(rows), *FIELD_SHAPE)
    )
    metadata: list[dict] = []
    occupancy_mismatch_ids: list[str] = []
    occupancy_mismatch_pixels = 0
    maximum_error = 0.0
    try:
        for index, row in enumerate(rows):
            if check_reversal:
                value, item, check = _feature_row(row)
                if check.occupancy_mismatch_pixels:
                    occupancy_mismatch_ids.append(row.opaque_id)
                    occupancy_mismatch_pixels += check.occupancy_mismatch_pixels
                    maximum_error = max(maximum_error, check.occupancy_maximum_absolute_error)
            else:
                value = np.ascontiguousarray(
                    neutral_field.encode_unoriented_stroke_field(row.strokes), dtype="<f4"
                )
                if value.shape != FIELD_SHAPE or not np.isfinite(value).all():
                    raise ValueError("Invalid unoriented stroke-field output")
                raster = rasterize(row.strokes).pixels
                expected = (
                    np.frombuffer(raster, np.uint8)
                    .reshape(RASTER_HEIGHT, RASTER_WIDTH)
                    .astype(np.float32)
                    / np.float32(255.0)
                )
                if not np.array_equal(value[0], expected):
                    raise ValueError("Unoriented field occupancy differs from app raster")
                sample = Sample(row.writer or "hwrt", row.session or 1, row.label, row.strokes)
                item = {
                    "opaqueID": row.opaque_id,
                    "label": row.label,
                    "source": row.source,
                    "writer": row.writer,
                    "session": row.session,
                    "nativeSymbolID": row.native_symbol_id,
                    "rasterSHA256": frozen_data._sha(raster),
                    "normalizedGeometrySHA256": trajectory_fingerprint(sample),
                    "fieldSHA256": frozen_data._sha(value.tobytes(order="C")),
                }
            fields[index] = value
            metadata.append(item)
            if (index + 1) % 128 == 0 or index + 1 == len(rows):
                print(f"encoded {index + 1}/{len(rows)} {row.source} rows", flush=True)
        fields.flush()
    finally:
        del fields
    if not metadata or len(metadata) != len(rows):
        raise ValueError("Feature preparation did not retain every row")
    ledger = None
    if check_reversal:
        ledger = {
            "version": "personal-unoriented-training-global-reversal-check-v1",
            "rowsChecked": len(rows),
            "auxiliaryRowsBitEqual": len(rows),
            "auxiliaryMismatchRows": 0,
            "occupancyMismatchRows": len(occupancy_mismatch_ids),
            "occupancyMismatchPixels": occupancy_mismatch_pixels,
            "occupancyMaximumAbsoluteError": maximum_error,
            "occupancyMismatchOpaqueIDs": occupancy_mismatch_ids,
        }
    return metadata, ledger


def _validate_prior_alignment(prior_rows: Sequence[Mapping[str, object]],
                              current_rows: Sequence[Mapping[str, object]]) -> None:
    if len(prior_rows) != TRAINING_ROWS or len(current_rows) != TRAINING_ROWS:
        raise ValueError("Prior/current training row count changed")
    for index, (prior, current) in enumerate(zip(prior_rows, current_rows)):
        if any(prior.get(key) != current.get(key) for key in _STABLE_PRIOR_FIELDS):
            raise ValueError(f"Training source/order/occupancy changed at row {index}")


def _copy_union(training_rows, development_rows, training_receipt_sha):
    reasons, summary = frozen_data._copy_union(
        training_rows, development_rows, training_receipt_sha
    )
    summary = dict(summary)
    summary["version"] = COPY_UNION_VERSION
    return reasons, summary


def _receipt(role: str, vocabulary: Sequence[str], artifacts: Mapping[str, dict],
             code: Mapping[str, str], counts: Mapping[str, int],
             source_bindings: Mapping[str, object], *, prior_identity: Mapping[str, object],
             reversal_checks: Mapping[str, object] | None,
             fit_receipt_sha: str | None = None,
             training_receipt_sha: str | None = None) -> dict:
    return {
        "version": DATA_VERSION,
        "role": role,
        "fieldVersion": FIELD_VERSION,
        "protocolSHA256": PROTOCOL_SHA256,
        "vocabulary": list(vocabulary),
        "vocabularySHA256": frozen_data._sha(canonical_json_bytes(list(vocabulary))),
        "counts": dict(counts),
        "sourceBindings": dict(source_bindings),
        "codeSHA256": dict(code),
        "artifacts": dict(artifacts),
        "fitReceiptSHA256": fit_receipt_sha,
        "trainingDataReceiptSHA256": training_receipt_sha,
        "priorTrainingMetadata": dict(prior_identity),
        "reversalChecks": None if reversal_checks is None else dict(reversal_checks),
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)},
        "roleGuards": {
            "privateInkUsed": False,
            "reservedUJIEncoded": False,
            "truthOpenedByDevelopmentLoader": False,
            "modelInferencePerformed": False,
            "optimizationPerformed": False,
        },
    }


def _validate_source_bindings(bindings: object) -> None:
    if not isinstance(bindings, dict):
        raise ValueError("Data receipt source bindings are missing")
    expected = {
        "ujiSourceSHA256": frozen_data.SOURCE_SHA256,
        "hwrtReceiptSHA256": frozen_data.HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": frozen_data.HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": frozen_data.HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": frozen_data.HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": frozen_data.HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": frozen_data.JOIN_REPORT_SHA256,
        "hwrtArchiveSHA256": frozen_data.HWRT_ARCHIVE_SHA256,
    }
    if set(bindings) != {*expected, "domain"} or any(
        bindings.get(key) != value for key, value in expected.items()
    ):
        raise ValueError("Data receipt source binding changed")
    domain = bindings["domain"]
    if (
        not isinstance(domain, dict)
        or set(domain) != {"bytes", "sha256"}
        or isinstance(domain.get("bytes"), bool)
        or not isinstance(domain.get("bytes"), int)
        or domain["bytes"] <= 0
        or domain.get("sha256") != frozen_data.DOMAIN_SHA256
    ):
        raise ValueError("Data receipt chord-domain binding changed")


def _validate_bound_identity(receipt: Mapping[str, object]) -> None:
    if receipt.get("codeSHA256") != code_identity():
        raise ValueError("Data receipt code identity changed")
    _validate_source_bindings(receipt.get("sourceBindings"))
    if receipt.get("priorTrainingMetadata") != _prior_identity():
        raise ValueError("Prior training metadata binding changed")


def _validate_reversal_checks(value: object, expected_rows: int) -> None:
    keys = {
        "version", "rowsChecked", "auxiliaryRowsBitEqual", "auxiliaryMismatchRows",
        "occupancyMismatchRows", "occupancyMismatchPixels",
        "occupancyMaximumAbsoluteError", "occupancyMismatchOpaqueIDs",
    }
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("Training reversal ledger is malformed")
    integers = (
        value["rowsChecked"], value["auxiliaryRowsBitEqual"],
        value["auxiliaryMismatchRows"], value["occupancyMismatchRows"],
        value["occupancyMismatchPixels"],
    )
    identities = value["occupancyMismatchOpaqueIDs"]
    maximum = value["occupancyMaximumAbsoluteError"]
    if (
        value["version"] != "personal-unoriented-training-global-reversal-check-v1"
        or any(isinstance(item, bool) or not isinstance(item, int) or item < 0 for item in integers)
        or value["rowsChecked"] != expected_rows
        or value["auxiliaryRowsBitEqual"] != expected_rows
        or value["auxiliaryMismatchRows"] != 0
        or value["occupancyMismatchRows"] > expected_rows
        or value["occupancyMismatchPixels"] > expected_rows * RASTER_HEIGHT * RASTER_WIDTH
        or not isinstance(identities, list)
        or len(identities) != value["occupancyMismatchRows"]
        or len(set(identities)) != len(identities)
        or any(not frozen_data._digest(item) for item in identities)
        or isinstance(maximum, bool)
        or not isinstance(maximum, (int, float))
        or not np.isfinite(maximum)
        or not 0.0 <= maximum <= 1.0
        or ((value["occupancyMismatchPixels"] == 0) != (maximum == 0.0))
    ):
        raise ValueError("Training reversal ledger coverage is invalid")


def _validate_metadata(metadata: Mapping[str, object], role: str, expected_rows: int,
                       vocabulary: Sequence[str]) -> None:
    version = TRAINING_VERSION if role == "training" else DEVELOPMENT_INPUTS_VERSION
    fields = _ROW_FIELDS if role == "training" else _BLIND_FIELDS
    if (
        set(metadata) != {"version", "vocabulary", "rows"}
        or metadata.get("version") != version
        or metadata.get("vocabulary") != list(vocabulary)
        or not isinstance(metadata.get("rows"), list)
        or len(metadata["rows"]) != expected_rows
        or not metadata["rows"]
    ):
        raise ValueError("Metadata coverage or vocabulary is invalid")
    seen: set[str] = set()
    for row in metadata["rows"]:
        if (
            not isinstance(row, dict)
            or set(row) != fields
            or not frozen_data._digest(row.get("opaqueID"))
            or row["opaqueID"] in seen
            or any(not frozen_data._digest(row.get(key)) for key in (
                "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"
            ))
        ):
            raise ValueError("Malformed, duplicated, or unhashed metadata row")
        seen.add(row["opaqueID"])
        if role == "training" and (
            row["label"] not in vocabulary
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
        ):
            raise ValueError("Training source metadata is invalid")


def _training_metadata(data_dir: Path) -> tuple[dict, dict, str]:
    directory = Path(data_dir)
    receipt_bytes = frozen_data._read_regular(directory / "data-receipt.json")
    receipt = frozen_data._json(receipt_bytes, "unoriented training data receipt")
    if receipt.get("version") != DATA_VERSION or receipt.get("role") != "training":
        raise ValueError("Wrong unoriented training data receipt")
    _validate_bound_identity(receipt)
    metadata_bytes = frozen_data._read_regular(
        directory / "training.json", maximum=frozen_data._MAX_SOURCE_BYTES
    )
    if receipt.get("artifacts", {}).get("training.json") != {
        "bytes": len(metadata_bytes), "sha256": frozen_data._sha(metadata_bytes)
    }:
        raise ValueError("Unoriented training metadata changed")
    metadata = frozen_data._json(metadata_bytes, "unoriented training metadata")
    _validate_metadata(metadata, "training", TRAINING_ROWS, receipt["vocabulary"])
    return metadata, receipt, frozen_data._sha(receipt_bytes)


def _validate_fit(fit_dir: Path, expected_sha: str, training_receipt_sha: str,
                  vocabulary: Sequence[str]) -> dict:
    if not frozen_data._digest(expected_sha):
        raise ValueError("Expected fit-receipt SHA-256 is required")
    from . import personal_unoriented_hwrt_train as train

    models, receipt = train.load_fitted_models(Path(fit_dir), expected_sha)
    del models
    expected_sentinels = {
        "rasterControlStateSHA256": PRIOR_CONTROL_STATE_SHA256,
        "scheduleSHA256": PRIOR_SCHEDULE_SHA256,
        "augmentationDrawStreamSHA256": PRIOR_AFFINE_DRAWS_SHA256,
    }
    if (
        receipt.get("version") != train.VERSION
        or receipt.get("scope") != train.SCOPE
        or receipt.get("arms") != ["rasterControl", "strokeField"]
        or receipt.get("fieldVersion") != FIELD_VERSION
        or receipt.get("modelVersion") != MODEL_VERSION
        or receipt.get("protocolSHA256") != PROTOCOL_SHA256
        or receipt.get("dataReceiptSHA256") != training_receipt_sha
        or receipt.get("vocabulary") != list(vocabulary)
        or receipt.get("recipe") != {
            "epochs": 30, "updatesPerArm": 1530, "exposuresPerArm": 195840,
            "batchSize": 128, "seed": 29,
        }
        or receipt.get("reproducibilitySentinels") != expected_sentinels
    ):
        raise ValueError("Completed unoriented fit is incomplete or mismatched")
    return receipt


def prepare_training(uji_source: Path, hwrt: Path, hasy: Path, join: Path,
                     protocol: Path, output: Path) -> dict:
    protocol_bytes = frozen_data._read_regular(protocol)
    if frozen_data._sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen unoriented protocol")
    code = code_identity()
    source_snapshot = frozen_data._source_snapshot(uji_source, hwrt, hasy, join)
    prior_metadata, prior_receipt, prior_sha = _load_prior_training_metadata()
    rows, vocabulary, bindings = frozen_data._source_rows(
        uji_source, hwrt, hasy, join, "training"
    )
    destination = frozen_data._fresh_output(output)
    metadata_rows, reversal_checks = _encode_rows(
        rows, destination / "fields.npy", check_reversal=True
    )
    _validate_prior_alignment(prior_metadata["rows"], metadata_rows)
    metadata = {
        "version": TRAINING_VERSION,
        "vocabulary": list(vocabulary),
        "rows": metadata_rows,
    }
    frozen_data._write(destination / "training.json", canonical_json_bytes(metadata))
    artifacts = {
        name: frozen_data._artifact(destination / name)
        for name in ("fields.npy", "training.json")
    }
    receipt = _receipt(
        "training", vocabulary, artifacts, code,
        {"rows": len(rows), "ujiRows": UJI_TRAINING_ROWS, "hwrtRows": HWRT_TRAINING_ROWS},
        bindings, prior_identity=_prior_identity(), reversal_checks=reversal_checks,
    )
    final_prior_metadata, final_prior_receipt, final_prior_sha = _load_prior_training_metadata()
    if (
        final_prior_metadata != prior_metadata
        or final_prior_receipt != prior_receipt
        or final_prior_sha != prior_sha
        or code_identity() != code
        or frozen_data._sha(frozen_data._read_regular(protocol)) != PROTOCOL_SHA256
        or frozen_data._source_snapshot(uji_source, hwrt, hasy, join) != source_snapshot
    ):
        raise ValueError("Bound sources, code, protocol, or prior metadata changed")
    frozen_data._write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


def prepare_development(uji_source: Path, hwrt: Path, hasy: Path, join: Path,
                        protocol: Path, training_data: Path, fit: Path,
                        fit_receipt_sha: str, output: Path) -> dict:
    protocol_bytes = frozen_data._read_regular(protocol)
    if frozen_data._sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen unoriented protocol")
    training, training_receipt, training_sha = _training_metadata(training_data)
    vocabulary = training_receipt["vocabulary"]
    _validate_fit(fit, fit_receipt_sha, training_sha, vocabulary)
    # The fit gate above intentionally precedes all development source/feature work.
    code = code_identity()
    source_snapshot = frozen_data._source_snapshot(uji_source, hwrt, hasy, join)
    rows, current_vocabulary, bindings = frozen_data._source_rows(
        uji_source, hwrt, hasy, join, "development"
    )
    if list(current_vocabulary) != vocabulary:
        raise ValueError("Development vocabulary differs from training")
    destination = frozen_data._fresh_output(output)
    full_rows, reversal_checks = _encode_rows(
        rows, destination / "fields.npy", check_reversal=False
    )
    if reversal_checks is not None:
        raise AssertionError("Development must not run the training reversal audit")
    copy_reasons, copy_union = _copy_union(training["rows"], full_rows, training_sha)
    blind_rows = [
        {key: row[key] for key in (
            "opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"
        )}
        for row in full_rows
    ]
    truth_rows = [
        {**row, "copyReasons": list(copy_reasons.get(row["opaqueID"], ()))}
        for row in full_rows
    ]
    inputs = {
        "version": DEVELOPMENT_INPUTS_VERSION,
        "vocabulary": vocabulary,
        "rows": blind_rows,
    }
    truth = {"version": DEVELOPMENT_TRUTH_VERSION, "rows": truth_rows, "copyUnion": copy_union}
    frozen_data._write(destination / "inputs.json", canonical_json_bytes(inputs))
    frozen_data._write(destination / "truth.json", canonical_json_bytes(truth))
    artifacts = {
        name: frozen_data._artifact(destination / name)
        for name in ("fields.npy", "inputs.json", "truth.json")
    }
    receipt = _receipt(
        "development", vocabulary, artifacts, code,
        {
            "rows": len(rows), "ujiRows": UJI_DEVELOPMENT_ROWS,
            "hwrtRows": HWRT_DEVELOPMENT_ROWS,
            "copyUnionRows": len(copy_union["affectedOpaqueIDs"]),
        },
        bindings, prior_identity=training_receipt["priorTrainingMetadata"],
        reversal_checks=None, fit_receipt_sha=fit_receipt_sha,
        training_receipt_sha=training_sha,
    )
    final_training, final_training_receipt, final_training_sha = _training_metadata(training_data)
    _validate_fit(fit, fit_receipt_sha, training_sha, vocabulary)
    if (
        final_training != training
        or final_training_receipt != training_receipt
        or final_training_sha != training_sha
        or code_identity() != code
        or frozen_data._sha(frozen_data._read_regular(protocol)) != PROTOCOL_SHA256
        or frozen_data._source_snapshot(uji_source, hwrt, hasy, join) != source_snapshot
    ):
        raise ValueError("Bound sources, code, protocol, training data, or fit changed")
    frozen_data._write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


def _load(role: str, data_dir: Path, expected_rows: int, metadata_name: str):
    directory = Path(data_dir)
    receipt_bytes = frozen_data._read_regular(directory / "data-receipt.json")
    receipt = frozen_data._json(receipt_bytes, "unoriented data receipt")
    expected_keys = {
        "version", "role", "fieldVersion", "protocolSHA256", "vocabulary",
        "vocabularySHA256", "counts", "sourceBindings", "codeSHA256", "artifacts",
        "fitReceiptSHA256", "trainingDataReceiptSHA256", "priorTrainingMetadata",
        "reversalChecks", "runtime", "roleGuards",
    }
    expected_artifacts = (
        {"fields.npy", "training.json"}
        if role == "training"
        else {"fields.npy", "inputs.json", "truth.json"}
    )
    reversal = receipt.get("reversalChecks")
    counts = receipt.get("counts")
    counts_valid = (
        isinstance(counts, dict)
        and (
            (
                role == "training"
                and counts == {
                    "rows": TRAINING_ROWS,
                    "ujiRows": UJI_TRAINING_ROWS,
                    "hwrtRows": HWRT_TRAINING_ROWS,
                }
            )
            or (
                role == "development"
                and set(counts) == {"rows", "ujiRows", "hwrtRows", "copyUnionRows"}
                and counts["rows"] == DEVELOPMENT_ROWS
                and counts["ujiRows"] == UJI_DEVELOPMENT_ROWS
                and counts["hwrtRows"] == HWRT_DEVELOPMENT_ROWS
                and type(counts["copyUnionRows"]) is int
                and 0 <= counts["copyUnionRows"] <= DEVELOPMENT_ROWS
            )
        )
    )
    if (
        set(receipt) != expected_keys
        or receipt.get("version") != DATA_VERSION
        or receipt.get("role") != role
        or receipt.get("protocolSHA256") != PROTOCOL_SHA256
        or receipt.get("fieldVersion") != FIELD_VERSION
        or not counts_valid
        or counts.get("rows") != expected_rows
        or expected_rows <= 0
        or not isinstance(receipt.get("vocabulary"), list)
        or len(receipt["vocabulary"]) != 102
        or len(set(receipt["vocabulary"])) != 102
        or set(receipt.get("artifacts", {})) != expected_artifacts
        or receipt.get("vocabularySHA256") != frozen_data._sha(
            canonical_json_bytes(receipt["vocabulary"])
        )
        or receipt.get("roleGuards") != {
            "privateInkUsed": False, "reservedUJIEncoded": False,
            "truthOpenedByDevelopmentLoader": False,
            "modelInferencePerformed": False, "optimizationPerformed": False,
        }
        or (
            role == "training"
            and (
                receipt.get("fitReceiptSHA256") is not None
                or receipt.get("trainingDataReceiptSHA256") is not None
                or not isinstance(reversal, dict)
            )
        )
        or (
            role == "development"
            and (
                not frozen_data._digest(receipt.get("fitReceiptSHA256"))
                or not frozen_data._digest(receipt.get("trainingDataReceiptSHA256"))
                or reversal is not None
            )
        )
    ):
        raise ValueError("Unoriented data receipt contract is invalid")
    if role == "training":
        _validate_reversal_checks(reversal, expected_rows)
    _validate_bound_identity(receipt)
    metadata_bytes = frozen_data._read_regular(
        directory / metadata_name, maximum=frozen_data._MAX_SOURCE_BYTES
    )
    if receipt["artifacts"].get(metadata_name) != {
        "bytes": len(metadata_bytes), "sha256": frozen_data._sha(metadata_bytes)
    }:
        raise ValueError("Unoriented metadata artifact changed")
    metadata = frozen_data._json(metadata_bytes, metadata_name)
    _validate_metadata(metadata, role, expected_rows, receipt["vocabulary"])
    field_path = directory / "fields.npy"
    expected_field = receipt["artifacts"].get("fields.npy")
    if (
        not isinstance(expected_field, dict)
        or frozen_data._sha_file(field_path)
        != (expected_field.get("bytes"), expected_field.get("sha256"))
    ):
        raise ValueError("Unoriented field artifact changed")
    fields = np.load(field_path, mmap_mode="r", allow_pickle=False)
    if (
        not isinstance(fields, np.memmap)
        or fields.dtype != np.dtype("<f4")
        or fields.shape != (expected_rows, *FIELD_SHAPE)
        or not fields.flags.c_contiguous
        or fields.size == 0
    ):
        raise ValueError("Unoriented field artifact shape/dtype/storage is invalid")
    return fields, metadata, receipt


def load_training(data_dir: Path):
    """Load only completed training fields, metadata, and receipt."""

    return _load("training", data_dir, TRAINING_ROWS, "training.json")


def load_development_inputs(data_dir: Path):
    """Load blind development inputs without opening or hashing ``truth.json``."""

    return _load("development", data_dir, DEVELOPMENT_ROWS, "inputs.json")


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uji-source", type=Path, required=True)
    parser.add_argument("--hwrt-intake", type=Path, required=True)
    parser.add_argument("--hasy-intake", type=Path, required=True)
    parser.add_argument("--join-report", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--role", choices=("training", "development"), required=True)
    parser.add_argument("--training-data", type=Path)
    parser.add_argument("--fit", type=Path)
    parser.add_argument("--fit-receipt-sha256")
    args = parser.parse_args(argv)
    if args.role == "training":
        if args.training_data is not None or args.fit is not None or args.fit_receipt_sha256 is not None:
            raise ValueError("Training preparation cannot consume fitted/development artifacts")
        receipt = prepare_training(
            args.uji_source, args.hwrt_intake, args.hasy_intake, args.join_report,
            args.protocol, args.output,
        )
    else:
        if args.training_data is None or args.fit is None or args.fit_receipt_sha256 is None:
            raise ValueError("Development preparation requires training data and completed fit")
        receipt = prepare_development(
            args.uji_source, args.hwrt_intake, args.hasy_intake, args.join_report,
            args.protocol, args.training_data, args.fit, args.fit_receipt_sha256,
            args.output,
        )
    print(json.dumps({"role": receipt["role"], **receipt["counts"]}, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
