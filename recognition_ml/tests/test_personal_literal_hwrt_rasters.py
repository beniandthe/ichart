import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.features import InkPoint, InkStroke, rasterize
from ichart_recognition_ml.research import personal_hwrt_stroke_data as old_data
from ichart_recognition_ml.research import personal_literal_hwrt_rasters as data


def digest(number):
    return f"{number:064x}"


def raw_strokes():
    return [[
        {"x": 0, "y": 1, "time": 99},
        {"x": 2, "y": 4, "time": 3},
        {"x": 6, "y": 2},
    ]]


def literal_row(index=0, *, label="A", native="31", record_id=None):
    archive = "a" * 64
    record_id = record_id or data._sha(f"{archive}\0train\0{index}".encode())
    return {
        "archiveSHA256": archive,
        "coordinatePayloadSHA256": digest(2),
        "dataSHA256": digest(3),
        "issues": [],
        "pointCount": 3,
        "recordID": record_id,
        "recordIndex": index,
        "role": "train",
        "sourceLabel": label,
        "sourceSymbolID": native,
        "strokeCount": 1,
        "strokes": raw_strokes(),
    }


def publish_inventory(root, record, *, class_label="A", native="31"):
    classes = {
        "version": "hwrt-literal-training-classes-v1",
        "selectionRule": "exact-sourceLabel-in-chord-domain-allowedLabels",
        "aliasesCaseFoldingOrTeXNormalizationUsed": False,
        "selectedClasses": [{
            "sourceSymbolID": native,
            "sourceLabel": class_label,
            "observedTrainingSamples": 1,
        }],
    }
    classes_bytes = canonical_json_bytes(classes) + b"\n"
    records_bytes = canonical_json_bytes(record) + b"\n"
    receipt = {
        "version": "hwrt-literal-training-inventory-v1",
        "literalClassCount": 1,
        "selectedTrainingRecordCount": 1,
        "selectedTrainingInvalidTrajectoryCount": 0,
        "testRowsParsed": False,
        "rasterFeatureModelFitOrInferencePerformed": False,
        "archive": {"sha256": "a" * 64},
        "artifacts": {
            "literal_classes.json": {
                "bytes": len(classes_bytes), "sha256": data._sha(classes_bytes),
            },
            "training_records.jsonl": {
                "bytes": len(records_bytes), "sha256": data._sha(records_bytes),
            },
        },
    }
    receipt_bytes = canonical_json_bytes(receipt) + b"\n"
    (root / "literal_classes.json").write_bytes(classes_bytes)
    (root / "training_records.jsonl").write_bytes(records_bytes)
    (root / "inventory-receipt.json").write_bytes(receipt_bytes)
    return receipt_bytes, records_bytes


class PersonalLiteralHWRTRastersTests(unittest.TestCase):
    def test_xy_adapter_matches_frozen_hwrt_adapter_and_ignores_time(self):
        strokes = data._strokes(raw_strokes())
        old_record = {
            "recordID": digest(1), "role": "train", "recordIndex": 0,
            "sourceSymbolID": "196", "sourceLabel": "+",
            "coordinatePayloadSHA256": digest(2), "strokes": raw_strokes(),
        }
        line = canonical_json_bytes(old_record) + b"\n"
        with patch.object(old_data, "HWRT_TRAINING_ROWS", 1), patch.dict(
            old_data._HWRT_COUNTS, {"training": {"+": 1}}, clear=False
        ):
            old = old_data._hwrt_rows(line, "training")[0].strokes
        self.assertEqual(strokes, old)
        self.assertTrue(all(point.time_offset is None for ink in strokes for point in ink.points))
        altered = json.loads(json.dumps(raw_strokes()))
        altered[0][0]["time"] = -10_000
        self.assertEqual(data._strokes(altered), strokes)

    def test_encoding_uses_app_raster_and_retains_explicit_failures(self):
        literal = data._LiteralRow(
            digest(10), digest(11), "31", "A", 7,
            (InkStroke((InkPoint(0, 0), InkPoint(3, 4), InkPoint(7, 1))),),
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "valid.npy"
            metadata, failures = data._encode_rows((literal,), path)
            self.assertEqual(failures, [])
            pixels = rasterize(literal.strokes).pixels
            plane = np.frombuffer(pixels, np.uint8).reshape(96, 256).astype("<f4") / 255
            loaded = np.load(path, allow_pickle=False)
            np.testing.assert_array_equal(loaded[0, 0], plane)
            self.assertEqual(metadata[0]["rasterSHA256"], data._sha(pixels))
            self.assertEqual(metadata[0]["modelPlaneSHA256"], data._sha(plane.tobytes()))
            self.assertIsNone(metadata[0]["encodingFailure"])

            def broken(_):
                raise RuntimeError("synthetic encoder failure")

            failed_rows, failures = data._encode_rows((literal,), Path(directory) / "failed.npy",
                                                       rasterizer=broken)
            self.assertEqual(len(failures), 1)
            self.assertEqual(failed_rows[0]["sourceRecordID"], literal.source_record_id)
            self.assertEqual(failed_rows[0]["encodingFailure"]["type"], "RuntimeError")
            with self.assertRaises(data.EncodingFailures) as captured:
                data._require_fit_ready(failed_rows, failures)
            self.assertEqual(captured.exception.rows, tuple(failed_rows))

    def test_collision_ledger_distinguishes_same_and_conflicting_labels(self):
        old = [{
            "opaqueID": digest(1), "label": "A", "source": "uji", "writer": "W1",
            "rasterSHA256": digest(100), "normalizedGeometrySHA256": digest(200),
        }]
        new = [
            {
                "opaqueID": digest(2), "sourceLabel": "A", "source": "hwrt-literal",
                "writer": None, "rasterSHA256": digest(100),
                "normalizedGeometrySHA256": digest(201),
            },
            {
                "opaqueID": digest(3), "sourceLabel": "B", "source": "hwrt-literal",
                "writer": None, "rasterSHA256": digest(101),
                "normalizedGeometrySHA256": digest(201),
            },
        ]
        ledger = data.collision_ledger(new, old)
        raster = ledger["summaries"]["rasterSHA256"]
        geometry = ledger["summaries"]["normalizedGeometrySHA256"]
        self.assertEqual(raster["duplicateGroupCount"], 1)
        self.assertEqual(raster["labelConflictGroupCount"], 0)
        self.assertTrue(raster["groups"][0]["crossSource"])
        self.assertEqual(geometry["labelConflictGroupCount"], 1)
        self.assertEqual(geometry["groups"][0]["labels"], ["A", "B"])
        self.assertEqual(ledger["scope"], "literal-2439-plus-pinned-old-training-10073-only")

    def test_inventory_loader_requires_literal_label_id_ordinal_and_exact_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            receipt_bytes, records_bytes = publish_inventory(root, literal_row())
            patches = (
                patch.object(data, "ROWS", 1), patch.object(data, "LITERAL_CLASSES", 1),
                patch.object(data, "INVENTORY_RECEIPT_SHA256", data._sha(receipt_bytes)),
                patch.object(data, "INVENTORY_RECORDS_SHA256", data._sha(records_bytes)),
            )
            with patches[0], patches[1], patches[2], patches[3]:
                rows, _, _ = data._load_inventory(root)
            self.assertEqual(rows[0].source_label, "A")
            self.assertEqual(rows[0].source_record_index, 0)

            mismatch = literal_row(label="a")
            receipt_bytes, records_bytes = publish_inventory(root, mismatch, class_label="A")
            with patch.object(data, "ROWS", 1), patch.object(data, "LITERAL_CLASSES", 1), \
                    patch.object(data, "INVENTORY_RECEIPT_SHA256", data._sha(receipt_bytes)), \
                    patch.object(data, "INVENTORY_RECORDS_SHA256", data._sha(records_bytes)), \
                    self.assertRaisesRegex(ValueError, "identity/label"):
                data._load_inventory(root)

            with patch.object(data, "ROWS", 1), patch.object(data, "LITERAL_CLASSES", 1), \
                    patch.object(data, "INVENTORY_RECEIPT_SHA256", "f" * 64), \
                    self.assertRaisesRegex(ValueError, "changed"):
                data._load_inventory(root)

    def test_fresh_output_rejects_existing_or_repository_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory).resolve() / "existing"
            existing.mkdir()
            with self.assertRaises(ValueError):
                old_data._fresh_output(existing)
        with self.assertRaises(ValueError):
            old_data._fresh_output(data.ROOT / "forbidden-literal-raster-output")

    def test_failure_report_retains_every_identity_without_tensor_or_data_receipt(self):
        rows = [
            {
                "opaqueID": digest(1), "sourceRecordID": digest(2),
                "encodingFailure": None,
            },
            {
                "opaqueID": digest(3), "sourceRecordID": digest(4),
                "encodingFailure": {"type": "RuntimeError", "message": "synthetic"},
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "failed-output"
            with patch.object(data, "code_identity", return_value={"synthetic": digest(9)}):
                report_path = data._publish_failures(output, rows)
            report = json.loads(report_path.read_text())
            self.assertEqual(report["sourceRowCount"], 2)
            self.assertEqual(report["failureCount"], 1)
            self.assertEqual(report["rows"], rows)
            self.assertEqual({path.name for path in output.iterdir()}, {"encoding-failures.json"})
            self.assertFalse((output / "data-receipt.json").exists())
            self.assertFalse((output / "rasters.npy").exists())


if __name__ == "__main__":
    unittest.main()
