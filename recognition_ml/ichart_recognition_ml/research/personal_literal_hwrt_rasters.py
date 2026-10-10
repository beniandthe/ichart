"""Prepare app-raster training rows for the pinned literal HWRT inventory.

This research-only adapter uses the unchanged HWRT x/y conversion and the
existing app rasterizer.  It does not render through another implementation,
encode stroke fields, run a model, or read any query/test/private material.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import platform
import shutil
import tempfile
from typing import Mapping, Sequence

import numpy as np

from ..contracts import canonical_json_bytes
from ..features import InkPoint, InkStroke, RASTER_HEIGHT, RASTER_WIDTH, rasterize
from . import personal_hwrt_stroke_data as parent_data
from .uji_personal import Sample, trajectory_fingerprint


VERSION = "personal-literal-hwrt-raster-data-v1"
METADATA_VERSION = "personal-literal-hwrt-raster-rows-v1"
COLLISION_VERSION = "personal-literal-hwrt-training-collisions-v1"
RASTER_VERSION = "app-raster-float32-plane-v1"
INVENTORY_RECEIPT_SHA256 = "1f3e7b26c8bf31a884956f5f1fb938e27941c28d6cb0f76ae9085e02e52123be"
INVENTORY_RECORDS_SHA256 = "3288da7e34071539e87882c8a10eeb6ed8acad1aadfc97ba7522248679954521"
OLD_DATA_RECEIPT_SHA256 = "5e00aa3ce986a07b7a3d4547ebc80b42307cf37a85f9f2e82870b6508b6957e5"
OLD_TRAINING_SHA256 = "56cdb11b58b6b02f36b30b7ed23c870681c44885af4bbd27cd5020bbdf761977"
ROWS = 2_439
LITERAL_CLASSES = 35
RASTER_SHAPE = (1, RASTER_HEIGHT, RASTER_WIDTH)
ROOT = Path(__file__).resolve().parents[3]
EXTRA_CODE_PATHS = (
    "recognition_ml/ichart_recognition_ml/research/hwrt_literal_training_inventory.py",
    "recognition_ml/tests/test_hwrt_literal_training_inventory.py",
    "recognition_ml/ichart_recognition_ml/research/personal_literal_hwrt_rasters.py",
    "recognition_ml/tests/test_personal_literal_hwrt_rasters.py",
)
RECORD_FIELDS = {
    "archiveSHA256", "coordinatePayloadSHA256", "dataSHA256", "issues",
    "pointCount", "recordID", "recordIndex", "role", "sourceLabel",
    "sourceSymbolID", "strokeCount", "strokes",
}


class EncodingFailures(ValueError):
    def __init__(self, rows):
        super().__init__("One or more literal HWRT rows failed raster encoding")
        self.rows = tuple(rows)


FAILURE_REPORT_VERSION = "personal-literal-hwrt-raster-failures-v1"


@dataclass(frozen=True)
class _LiteralRow:
    opaque_id: str
    source_record_id: str
    source_symbol_id: str
    source_label: str
    source_record_index: int
    strokes: tuple[InkStroke, ...]


def _sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def code_identity() -> dict[str, str]:
    identity = dict(parent_data.code_identity())
    for relative in EXTRA_CODE_PATHS:
        identity[relative] = _sha(parent_data._read_regular(ROOT / relative))
    return dict(sorted(identity.items()))


def _opaque(record_id: str) -> str:
    return _sha(f"{VERSION}\0{record_id}".encode())


def _strokes(raw_strokes) -> tuple[InkStroke, ...]:
    """Match frozen ``personal_hwrt_stroke_data._hwrt_rows`` exactly."""

    if not isinstance(raw_strokes, list) or not raw_strokes:
        raise ValueError("Literal HWRT trajectory is unavailable")
    strokes = []
    for raw_stroke in raw_strokes:
        if not isinstance(raw_stroke, list) or not raw_stroke:
            raise ValueError("Literal HWRT stroke is unavailable")
        points = []
        for point in raw_stroke:
            if (
                not isinstance(point, dict) or not {"x", "y"} <= point.keys()
                or isinstance(point["x"], bool) or isinstance(point["y"], bool)
            ):
                raise ValueError("Malformed literal HWRT point")
            points.append(InkPoint(float(point["x"]), float(point["y"])))
        strokes.append(InkStroke(tuple(points)))
    return tuple(strokes)


def _load_inventory(directory: Path) -> tuple[tuple[_LiteralRow, ...], dict, dict[str, bytes]]:
    directory = Path(directory)
    receipt_bytes = parent_data._read_regular(directory / "inventory-receipt.json")
    records_bytes = parent_data._read_regular(
        directory / "training_records.jsonl", maximum=parent_data._MAX_SOURCE_BYTES
    )
    if (
        _sha(receipt_bytes) != INVENTORY_RECEIPT_SHA256
        or _sha(records_bytes) != INVENTORY_RECORDS_SHA256
    ):
        raise ValueError("Pinned literal inventory receipt or records changed")
    receipt = parent_data._json(receipt_bytes, "literal inventory receipt", newline=True)
    classes_identity = receipt.get("artifacts", {}).get("literal_classes.json")
    classes_bytes = parent_data._read_regular(directory / "literal_classes.json")
    if (
        receipt.get("version") != "hwrt-literal-training-inventory-v1"
        or receipt.get("literalClassCount") != LITERAL_CLASSES
        or receipt.get("selectedTrainingRecordCount") != ROWS
        or receipt.get("selectedTrainingInvalidTrajectoryCount") != 0
        or receipt.get("testRowsParsed") is not False
        or receipt.get("rasterFeatureModelFitOrInferencePerformed") is not False
        or receipt.get("artifacts", {}).get("training_records.jsonl")
        != {"bytes": len(records_bytes), "sha256": INVENTORY_RECORDS_SHA256}
        or classes_identity != {"bytes": len(classes_bytes), "sha256": _sha(classes_bytes)}
    ):
        raise ValueError("Pinned literal inventory contract changed")
    class_report = parent_data._json(classes_bytes, "literal classes", newline=True)
    selected = class_report.get("selectedClasses")
    if (
        class_report.get("selectionRule") != "exact-sourceLabel-in-chord-domain-allowedLabels"
        or class_report.get("aliasesCaseFoldingOrTeXNormalizationUsed") is not False
        or not isinstance(selected, list) or len(selected) != LITERAL_CLASSES
    ):
        raise ValueError("Literal class report changed")
    native_labels = {}
    expected_counts = {}
    for item in selected:
        native, label, count = (
            item.get("sourceSymbolID"), item.get("sourceLabel"),
            item.get("observedTrainingSamples"),
        )
        if (
            not isinstance(native, str) or not isinstance(label, str) or not label
            or type(count) is not int or count <= 0 or native in native_labels
            or label in native_labels.values()
        ):
            raise ValueError("Literal class identity/count changed")
        native_labels[native] = label; expected_counts[native] = count

    rows, counts, ids, ordinals = [], Counter(), set(), set()
    for line_number, line in enumerate(records_bytes.splitlines(), 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"Malformed literal inventory row {line_number}") from error
        if canonical_json_bytes(value) != line or not isinstance(value, dict) or set(value) != RECORD_FIELDS:
            raise ValueError("Literal inventory row schema/canonical bytes changed")
        native, label = value["sourceSymbolID"], value["sourceLabel"]
        record_id, index = value["recordID"], value["recordIndex"]
        if (
            native_labels.get(native) != label or value["role"] != "train"
            or not parent_data._digest(record_id) or record_id in ids
            or type(index) is not int or index < 0 or index in ordinals
            or record_id != _sha(f"{value['archiveSHA256']}\0train\0{index}".encode())
            or not parent_data._digest(value["dataSHA256"])
            or not parent_data._digest(value["coordinatePayloadSHA256"])
            or value["issues"] != []
        ):
            raise ValueError("Literal source identity/label/ordinal changed")
        ids.add(record_id); ordinals.add(index); counts[native] += 1
        rows.append(_LiteralRow(
            _opaque(record_id), record_id, native, label, index, _strokes(value["strokes"])
        ))
    if len(rows) != ROWS or counts != Counter(expected_counts):
        raise ValueError("Literal source row/class coverage changed")
    return tuple(rows), receipt, {
        "inventoryReceipt": receipt_bytes,
        "inventoryRecords": records_bytes,
        "literalClasses": classes_bytes,
    }


def _load_old_training(directory: Path) -> tuple[list[dict], dict, dict[str, bytes]]:
    directory = Path(directory)
    receipt_bytes = parent_data._read_regular(directory / "data-receipt.json")
    metadata_bytes = parent_data._read_regular(
        directory / "training.json", maximum=parent_data._MAX_SOURCE_BYTES
    )
    if (
        _sha(receipt_bytes) != OLD_DATA_RECEIPT_SHA256
        or _sha(metadata_bytes) != OLD_TRAINING_SHA256
    ):
        raise ValueError("Pinned old training receipt or metadata changed")
    metadata, receipt, receipt_sha = parent_data._training_metadata(directory)
    if receipt_sha != OLD_DATA_RECEIPT_SHA256 or metadata.get("rows") is None:
        raise ValueError("Pinned old training metadata contract changed")
    return metadata["rows"], receipt, {
        "oldDataReceipt": receipt_bytes, "oldTrainingMetadata": metadata_bytes,
    }


def _base_metadata(row: _LiteralRow) -> dict:
    return {
        "opaqueID": row.opaque_id,
        "sourceRecordID": row.source_record_id,
        "sourceSymbolID": row.source_symbol_id,
        "sourceLabel": row.source_label,
        "sourceRecordIndex": row.source_record_index,
        "source": "hwrt-literal",
        "writer": None,
        "session": None,
    }


def _encode_rows(rows: Sequence[_LiteralRow], path: Path, *, rasterizer=rasterize):
    rasters = np.lib.format.open_memmap(
        path, mode="w+", dtype="<f4", shape=(len(rows), *RASTER_SHAPE)
    )
    metadata, failures = [], []
    try:
        for index, row in enumerate(rows):
            item = _base_metadata(row)
            try:
                pixels = rasterizer(row.strokes).pixels
                if len(pixels) != RASTER_HEIGHT * RASTER_WIDTH:
                    raise ValueError("Unexpected app-raster byte count")
                plane = np.frombuffer(pixels, np.uint8).reshape(
                    RASTER_HEIGHT, RASTER_WIDTH
                ).astype("<f4") / np.float32(255.0)
                plane = np.ascontiguousarray(plane, dtype="<f4")
                rasters[index, 0] = plane
                item.update({
                    "rasterSHA256": _sha(pixels),
                    "modelPlaneSHA256": _sha(plane.tobytes(order="C")),
                    "normalizedGeometrySHA256": trajectory_fingerprint(
                        Sample("hwrt", 1, row.source_label, row.strokes)
                    ),
                    "encodingFailure": None,
                })
            except Exception as error:  # retain every source identity; never publish its zero row
                item.update({
                    "rasterSHA256": None, "modelPlaneSHA256": None,
                    "normalizedGeometrySHA256": None,
                    "encodingFailure": {"type": type(error).__name__, "message": str(error)},
                })
                failures.append(item)
            metadata.append(item)
        rasters.flush()
    finally:
        del rasters
    return metadata, failures


def _require_fit_ready(metadata, failures) -> None:
    if failures:
        raise EncodingFailures(metadata)


def collision_ledger(new_rows: Sequence[Mapping[str, object]],
                     old_rows: Sequence[Mapping[str, object]]) -> dict:
    fields = ("rasterSHA256", "normalizedGeometrySHA256")
    groups = {field: defaultdict(list) for field in fields}
    seen = set()
    for row in (*old_rows, *new_rows):
        opaque = row.get("opaqueID")
        label = row.get("label", row.get("sourceLabel"))
        source = row.get("source")
        writer = row.get("writer")
        if (
            not parent_data._digest(opaque) or opaque in seen or not isinstance(label, str)
            or source not in ("uji", "hwrt", "hwrt-literal")
            or any(not parent_data._digest(row.get(field)) for field in fields)
        ):
            raise ValueError("Collision input metadata is malformed")
        seen.add(opaque)
        cohort = f"{source}:{writer if isinstance(writer, str) else 'unavailable'}"
        ref = {"opaqueID": opaque, "label": label, "source": source, "writerCohort": cohort}
        for field in fields:
            groups[field][row[field]].append(ref)

    summaries = {}
    for field in fields:
        collisions = []
        for digest, records in sorted(groups[field].items()):
            if len(records) < 2:
                continue
            labels = sorted({row["label"] for row in records})
            sources = sorted({row["source"] for row in records})
            cohorts = sorted({row["writerCohort"] for row in records})
            collisions.append({
                "sha256": digest, "count": len(records), "records": records,
                "labels": labels, "labelConflict": len(labels) > 1,
                "sources": sources, "crossSource": len(sources) > 1,
                "writerCohorts": cohorts, "crossWriterCohort": len(cohorts) > 1,
            })
        summaries[field] = {
            "duplicateGroupCount": len(collisions),
            "labelConflictGroupCount": sum(row["labelConflict"] for row in collisions),
            "crossSourceGroupCount": sum(row["crossSource"] for row in collisions),
            "crossWriterCohortGroupCount": sum(row["crossWriterCohort"] for row in collisions),
            "groups": collisions,
        }
    return {
        "version": COLLISION_VERSION,
        "scope": "literal-2439-plus-pinned-old-training-10073-only",
        "newRowCount": len(new_rows), "oldRowCount": len(old_rows),
        "hashFields": list(fields), "summaries": summaries,
    }


def prepare(inventory_directory: Path, old_training_directory: Path, output: Path) -> dict:
    code = code_identity()
    rows, inventory_receipt, inventory_bytes = _load_inventory(inventory_directory)
    old_rows, old_receipt, old_bytes = _load_old_training(old_training_directory)
    snapshots = {**inventory_bytes, **old_bytes}
    with tempfile.TemporaryDirectory(prefix="ichart-literal-raster-") as temporary:
        temporary_rasters = Path(temporary) / "rasters.npy"
        metadata_rows, failures = _encode_rows(rows, temporary_rasters)
        _require_fit_ready(metadata_rows, failures)
        ledger = collision_ledger(metadata_rows, old_rows)
        destination = parent_data._fresh_output(Path(output))
        shutil.copyfile(temporary_rasters, destination / "rasters.npy")
    metadata = {"version": METADATA_VERSION, "rows": metadata_rows}
    parent_data._write(destination / "rows.json", canonical_json_bytes(metadata))
    parent_data._write(destination / "collision-ledger.json", canonical_json_bytes(ledger))
    artifacts = {
        name: parent_data._artifact(destination / name)
        for name in ("rasters.npy", "rows.json", "collision-ledger.json")
    }
    receipt = {
        "version": VERSION,
        "role": "training",
        "rasterVersion": RASTER_VERSION,
        "counts": {"rows": ROWS, "encodingFailures": 0, "oldTrainingRows": len(old_rows)},
        "sourceBindings": {
            "inventoryReceiptSHA256": INVENTORY_RECEIPT_SHA256,
            "inventoryRecordsSHA256": INVENTORY_RECORDS_SHA256,
            "oldDataReceiptSHA256": OLD_DATA_RECEIPT_SHA256,
            "oldTrainingMetadataSHA256": OLD_TRAINING_SHA256,
            "inventoryArchiveSHA256": inventory_receipt["archive"]["sha256"],
            "oldSourceBindings": old_receipt["sourceBindings"],
        },
        "artifacts": artifacts,
        "codeSHA256": code,
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)},
        "claims": {
            "appRasterizerReused": True,
            "xYOnlyHWRTAdapterReused": True,
            "strokeFieldEncoded": False,
            "modelInferencePerformed": False,
            "privateDataUsed": False,
            "dedicatedDevelopmentOrQueryArtifactsRead": False,
            "priorTrainingContainsInternalHoldouts": True,
            "eligibilitySelected": False,
            "swiftRuntimeParityClaimed": False,
            "encodedWithoutFailures": True,
        },
    }
    final_rows, final_inventory_receipt, final_inventory_bytes = _load_inventory(inventory_directory)
    final_old_rows, final_old_receipt, final_old_bytes = _load_old_training(old_training_directory)
    if (
        final_rows != rows or final_inventory_receipt != inventory_receipt
        or final_old_rows != old_rows or final_old_receipt != old_receipt
        or {**final_inventory_bytes, **final_old_bytes} != snapshots
        or code_identity() != code
        or any(parent_data._artifact(destination / name) != identity
               for name, identity in artifacts.items())
    ):
        raise ValueError("Bound source, code, or artifacts changed before publication")
    parent_data._write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


def _publish_failures(output: Path, rows: Sequence[Mapping[str, object]]) -> Path:
    destination = parent_data._fresh_output(Path(output))
    failed = [row for row in rows if row.get("encodingFailure") is not None]
    report = {
        "version": FAILURE_REPORT_VERSION,
        "status": "encoding-failed-no-raster-or-data-receipt-published",
        "sourceRowCount": len(rows),
        "failureCount": len(failed),
        "rows": list(rows),
        "sourceBindings": {
            "inventoryReceiptSHA256": INVENTORY_RECEIPT_SHA256,
            "inventoryRecordsSHA256": INVENTORY_RECORDS_SHA256,
            "oldDataReceiptSHA256": OLD_DATA_RECEIPT_SHA256,
            "oldTrainingMetadataSHA256": OLD_TRAINING_SHA256,
        },
        "codeSHA256": code_identity(),
    }
    parent_data._write(destination / "encoding-failures.json", canonical_json_bytes(report))
    return destination / "encoding-failures.json"


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--old-training-data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        receipt = prepare(args.inventory, args.old_training_data, args.output)
    except EncodingFailures as error:
        path = _publish_failures(args.output, error.rows)
        print(json.dumps({
            "failureReport": str(path),
            "failures": sum(row["encodingFailure"] is not None for row in error.rows),
            "version": FAILURE_REPORT_VERSION,
        }, sort_keys=True), flush=True)
        raise SystemExit(2) from error
    print(json.dumps({"rows": receipt["counts"]["rows"], "version": receipt["version"]},
                     sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
