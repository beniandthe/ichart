import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.features import InkPoint, InkStroke, rasterize
from ichart_recognition_ml.research import personal_hwrt_stroke_data as data
from ichart_recognition_ml.research.uji_personal import Sample


def sha(value):
    return hashlib.sha256(value).hexdigest()


def stroke(offset=0):
    return (InkStroke((InkPoint(offset, 0), InkPoint(offset + 2, 3), InkPoint(offset + 5, 1))),)


def source_row(index, *, source="uji", label="L000"):
    return data._SourceRow(
        data._opaque(source, "training", index), label, source,
        "trn_UJI_W00" if source == "uji" else None,
        1 if source == "uji" else None,
        None if source == "uji" else "196",
        f"source-{index}", index, stroke(index * 10),
    )


def vocabulary():
    return [f"L{index:03d}" for index in range(102)]


def source_bindings():
    return {
        "ujiSourceSHA256": data.SOURCE_SHA256,
        "hwrtReceiptSHA256": data.HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": data.HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": data.HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": data.HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": data.HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": data.JOIN_REPORT_SHA256,
        "domain": {"bytes": 1, "sha256": data.DOMAIN_SHA256},
        "hwrtArchiveSHA256": data.HWRT_ARCHIVE_SHA256,
    }


def metadata_row(index, *, source="uji"):
    digest = f"{index + 1:064x}"
    return {
        "opaqueID": f"{index + 100:064x}",
        "label": "L000",
        "source": source,
        "writer": "trn_UJI_W00" if source == "uji" else None,
        "session": 1 if source == "uji" else None,
        "nativeSymbolID": None if source == "uji" else "196",
        "rasterSHA256": digest,
        "normalizedGeometrySHA256": f"{index + 10:064x}",
        "fieldSHA256": f"{index + 20:064x}",
    }


def publish_bundle(root, role, rows, fields, *, truth_identity=None):
    np.save(root / "fields.npy", fields, allow_pickle=False)
    name = "training.json" if role == "training" else "inputs.json"
    payload_rows = rows if role == "training" else [
        {key: row[key] for key in ("opaqueID", "rasterSHA256",
                                   "normalizedGeometrySHA256", "fieldSHA256")}
        for row in rows
    ]
    metadata = {
        "version": data.TRAINING_VERSION if role == "training" else data.DEVELOPMENT_INPUTS_VERSION,
        "vocabulary": vocabulary(),
        "rows": payload_rows,
    }
    (root / name).write_bytes(canonical_json_bytes(metadata))
    artifacts = {item: data._artifact(root / item) for item in ("fields.npy", name)}
    if role == "development":
        artifacts["truth.json"] = truth_identity or {"bytes": 17, "sha256": "f" * 64}
    receipt = data._receipt(
        role, vocabulary(), artifacts, {"synthetic": "0" * 64},
        {"rows": len(rows)}, source_bindings(),
        fit_receipt_sha="a" * 64 if role == "development" else None,
        training_receipt_sha="b" * 64 if role == "development" else None,
    )
    (root / "data-receipt.json").write_bytes(canonical_json_bytes(receipt))
    return metadata, receipt


class PersonalHWRTStrokeDataTests(unittest.TestCase):
    def test_pretty_printed_sha_pinned_hasy_receipt_is_accepted_without_reencoding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); hwrt = root / "hwrt"; hasy = root / "hasy"
            hwrt.mkdir(); hasy.mkdir(); (hasy / "source_metadata").mkdir()
            selected = b"{}\n"; (hwrt / "selected_records.jsonl").write_bytes(selected)
            hwrt_receipt = {"artifacts": {"selected_records.jsonl": {
                "bytes": len(selected), "sha256": sha(selected)}}}
            hwrt_bytes = canonical_json_bytes(hwrt_receipt) + b"\n"
            (hwrt / "source_receipt.json").write_bytes(hwrt_bytes)
            labels, duplicates = b"labels\n", b"duplicates\n"
            (hasy / "source_metadata/hasy-data-labels.csv").write_bytes(labels)
            (hasy / "pixel_duplicates.json").write_bytes(duplicates)
            hasy_receipt = {"artifacts": {
                "source_metadata/hasy-data-labels.csv": {"bytes": len(labels), "sha256": sha(labels)},
                "pixel_duplicates.json": {"bytes": len(duplicates), "sha256": sha(duplicates)},
            }}
            hasy_bytes = (json.dumps(hasy_receipt, indent=2, sort_keys=True) + "\n").encode()
            (hasy / "source_receipt.json").write_bytes(hasy_bytes)
            join = {"schemaVersion": "hwrt-hasy-ordinal-pixel-verification-v1",
                    "join": {"metadataRowsChecked": 168233, "metadataMismatchCount": 0},
                    "pixels": {"selectedRows": 5507}}
            join_path = root / "join.json"; join_path.write_bytes(canonical_json_bytes(join))
            with patch.multiple(data,
                HWRT_RECEIPT_SHA256=sha(hwrt_bytes), HWRT_SELECTED_SHA256=sha(selected),
                HASY_RECEIPT_SHA256=sha(hasy_bytes), HASY_LABELS_SHA256=sha(labels),
                HASY_PIXEL_DUPLICATES_SHA256=sha(duplicates), JOIN_REPORT_SHA256=sha(join_path.read_bytes())):
                receipt, returned = data._validate_hwrt_bindings(hwrt, hasy, join_path)
            self.assertEqual(receipt, hwrt_receipt)
            self.assertEqual(returned, selected)

    def test_feature_row_preserves_exact_raster_plane_and_hashes(self):
        row = source_row(0)
        field, metadata = data._feature_row(row)
        pixels = rasterize(row.strokes).pixels
        expected = np.frombuffer(pixels, np.uint8).reshape(96, 256).astype(np.float32) / 255
        np.testing.assert_array_equal(field[0], expected)
        self.assertEqual(metadata["rasterSHA256"], sha(pixels))
        self.assertEqual(metadata["fieldSHA256"], sha(field.astype("<f4").tobytes()))
        self.assertEqual(field.shape, (5, 96, 256))
        self.assertEqual(field.dtype, np.float32)

    def test_uji_role_selection_never_returns_reserved_writer(self):
        records = []
        for prefix, count in (("trn_UJI_W", 40), ("tst_UJI_W", 20)):
            for index in range(count):
                records.append(Sample(f"{prefix}{index:02d}", 1, "A", stroke(index)))
        records = tuple(records)
        training, development, reserved = data.split_writers(records)
        with patch.object(data, "UJI_TRAINING_ROWS", 32), patch.object(data, "UJI_DEVELOPMENT_ROWS", 8):
            selected_training = data._uji_rows(records, "training")
            selected_development = data._uji_rows(records, "development")
        self.assertEqual({row.writer for row in selected_training}, set(training))
        self.assertEqual({row.writer for row in selected_development}, set(development))
        self.assertFalse(({row.writer for row in selected_training + selected_development}) & set(reserved))

    def test_hwrt_mapping_is_exact_and_timing_is_not_materialized(self):
        native = [
            ("196", "+", "+"), ("922", "/", "/"), ("266", r"\#", "#"),
            ("948", r"\sharp", "#"), ("950", r"\emptyset", "ø"),
            ("959", r"\triangle", "△"), ("977", r"\vartriangle", "△"),
            ("152", r"\Delta", "△"),
        ]
        lines = []
        for index, (symbol, latex, _) in enumerate(native):
            lines.append(canonical_json_bytes({
                "recordID": f"{index + 1:064x}", "role": "train", "recordIndex": index,
                "sourceSymbolID": symbol, "sourceLabel": latex,
                "coordinatePayloadSHA256": "a" * 64,
                "strokes": [[{"x": index, "y": 0, "time": 9}, {"x": index + 1, "y": 2, "time": 1}]],
            }))
        expected = {label: sum(item[2] == label for item in native) for label in {item[2] for item in native}}
        with patch.object(data, "HWRT_TRAINING_ROWS", len(native)), patch.dict(
            data._HWRT_COUNTS, {"training": expected}, clear=False
        ):
            rows = data._hwrt_rows(b"\n".join(lines) + b"\n", "training")
        self.assertEqual([row.label for row in rows], [item[2] for item in native])
        self.assertTrue(all(point.time_offset is None for row in rows for ink in row.strokes for point in ink.points))
        altered = json.loads(lines[0]); altered["sourceLabel"] = r"\O"
        with patch.object(data, "HWRT_TRAINING_ROWS", len(native)), patch.dict(
            data._HWRT_COUNTS, {"training": expected}, clear=False
        ), self.assertRaises(ValueError):
            data._hwrt_rows(canonical_json_bytes(altered) + b"\n" + b"\n".join(lines[1:]) + b"\n", "training")

    def test_copy_union_is_input_only_and_uses_one_deterministic_representative(self):
        training = [metadata_row(0)]
        first, second, third = metadata_row(1), metadata_row(2), metadata_row(3)
        second["rasterSHA256"] = first["rasterSHA256"]
        third["fieldSHA256"] = training[0]["fieldSHA256"]
        reasons, summary = data._copy_union(training, [second, first, third], "c" * 64)
        repeated = max(first["opaqueID"], second["opaqueID"])
        self.assertIn("repeated-development-rasterSHA256", reasons[repeated])
        self.assertIn("training-fieldSHA256", reasons[third["opaqueID"]])
        self.assertNotIn("label", json.dumps(summary))
        self.assertEqual(summary["trainingDataReceiptSHA256"], "c" * 64)
        self.assertEqual(summary["affectedOpaqueIDs"], sorted(reasons))

    def test_training_loader_requires_exact_nonempty_shape_hashes_and_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            fields = np.arange(2 * 5 * 2 * 3, dtype=np.float32).reshape(2, 5, 2, 3)
            rows = [metadata_row(0), metadata_row(1, source="hwrt")]
            _, receipt = publish_bundle(root, "training", rows, fields)
            with patch.object(data, "TRAINING_ROWS", 2), patch.object(data, "FIELD_SHAPE", (5, 2, 3)):
                with patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}):
                    loaded, metadata, receipt = data.load_training(root)
                self.assertIsInstance(loaded, np.memmap)
                np.testing.assert_array_equal(loaded, fields)
                self.assertEqual(metadata["rows"], rows)
                self.assertEqual(receipt["counts"]["rows"], 2)
                changed = json.loads((root / "data-receipt.json").read_text())
                changed["sourceBindings"]["joinReportSHA256"] = "e" * 64
                (root / "data-receipt.json").write_bytes(canonical_json_bytes(changed))
                with patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                        self.assertRaises(ValueError):
                    data.load_training(root)
                changed = json.loads(json.dumps(receipt)); changed["codeSHA256"] = {"stale": "e" * 64}
                (root / "data-receipt.json").write_bytes(canonical_json_bytes(changed))
                with patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                        self.assertRaises(ValueError):
                    data.load_training(root)
                (root / "data-receipt.json").write_bytes(canonical_json_bytes(receipt))
                (root / "training.json").write_bytes(b"{}")
                with patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                        self.assertRaises(ValueError):
                    data.load_training(root)

    def test_development_loader_never_opens_or_requires_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            fields = np.arange(2 * 5 * 2 * 3, dtype=np.float32).reshape(2, 5, 2, 3)
            rows = [metadata_row(0), metadata_row(1, source="hwrt")]
            publish_bundle(root, "development", rows, fields)
            self.assertFalse((root / "truth.json").exists())
            opened = []
            original = data._read_regular

            def observed(path, **kwargs):
                opened.append(Path(path).name)
                if Path(path).name == "truth.json":
                    raise AssertionError("blind loader opened truth")
                return original(path, **kwargs)

            with patch.object(data, "DEVELOPMENT_ROWS", 2), patch.object(data, "FIELD_SHAPE", (5, 2, 3)), \
                    patch.object(data, "_read_regular", side_effect=observed), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}):
                loaded, inputs, receipt = data.load_development_inputs(root)
            self.assertEqual(opened, ["data-receipt.json", "inputs.json"])
            self.assertEqual(loaded.shape, (2, 5, 2, 3))
            self.assertEqual(set(inputs["rows"][0]), data._BLIND_FIELDS)
            self.assertEqual(receipt["artifacts"]["truth.json"]["sha256"], "f" * 64)

    def test_completed_fit_is_required_and_bound_before_development_source_work(self):
        from ichart_recognition_ml.research import personal_hwrt_stroke_train as train

        vocab = vocabulary()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            weights = root / "weights"; weights.mkdir()
            weight_hashes, weight_files = {}, {}
            for arm in ("rasterControl", "strokeField"):
                path = weights / f"{arm}.pt"; path.write_bytes(arm.encode())
                weight_files[arm] = f"weights/{arm}.pt"
                weight_hashes[arm] = sha(path.read_bytes())
            ledger = {
                "epochs": 30, "updates": 1530, "exposures": 195840,
                "scheduleSHA256": "2" * 64, "batchOrderStreamSHA256": "3" * 64,
                "augmentationDrawStreamSHA256": "4" * 64,
                "augmentedFeatureStreamSHA256": "5" * 64,
                "actualForwardInputStreamSHA256": "5" * 64,
            }
            receipt = {
                "version": train.VERSION, "scope": train.SCOPE, "arms": list(train.ARMS),
                "fieldVersion": data.FIELD_VERSION, "modelVersion": train.field.MODEL_VERSION, "labelCount": 102,
                "vocabulary": vocab, "vocabularySHA256": sha(canonical_json_bytes(vocab)),
                "protocolSHA256": data.PROTOCOL_SHA256, "codeSHA256": train.code_identity(),
                "dataReceiptSHA256": "b" * 64, "dataArtifactsSHA256": {"fields.npy": "c" * 64},
                "runtime": train._runtime_contract(),
                "recipe": {"epochs": 30, "updatesPerArm": 1530, "exposuresPerArm": 195840,
                           "batchSize": 128, "seed": 29},
                "initialStateSHA256": "0" * 64,
                "initialArmStateSHA256": {arm: "0" * 64 for arm in train.ARMS},
                "trainingPlanPath": "training-plan.json", "trainingPlanSHA256": "1" * 64,
                "augmentationLedger": {arm: dict(ledger) for arm in train.ARMS},
                "trainingHistory": {arm: [
                    {"epoch": epoch, "meanLoss": 1.0, "correct": 1, "learningRate": 0.001}
                    for epoch in range(1, 31)
                ] for arm in weight_files},
                "weightFiles": weight_files, "weightsSHA256": weight_hashes,
                "finalStateSHA256": {arm: f"{index + 6:064x}" for index, arm in enumerate(train.ARMS)},
                "selection": "final-epoch-only",
            }
            payload = canonical_json_bytes(receipt)
            (root / "fit-receipt.json").write_bytes(payload)
            data._validate_fit(root, sha(payload), "b" * 64, vocab)
            receipt["augmentationLedger"]["strokeField"]["updates"] = 1529
            bad = canonical_json_bytes(receipt); (root / "fit-receipt.json").write_bytes(bad)
            with self.assertRaises(ValueError):
                data._validate_fit(root, sha(bad), "b" * 64, vocab)
            receipt["augmentationLedger"]["strokeField"]["updates"] = 1530
            receipt["trainingHistory"]["strokeField"].pop()
            bad = canonical_json_bytes(receipt); (root / "fit-receipt.json").write_bytes(bad)
            with self.assertRaises(ValueError):
                data._validate_fit(root, sha(bad), "b" * 64, vocab)

    def test_encoding_failure_publishes_no_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); protocol = root / "protocol.md"; protocol.write_bytes(b"fixed")
            output = root / "output"
            with patch.object(data, "PROTOCOL_SHA256", sha(b"fixed")), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                    patch.object(data, "_source_snapshot", return_value={}), \
                    patch.object(data, "_source_rows", return_value=((source_row(0),), tuple(vocabulary()), {})), \
                    patch.object(data, "_encode_rows", side_effect=ValueError("encoding failed")), \
                    self.assertRaisesRegex(ValueError, "encoding failed"):
                data.prepare_training(root / "uji", root / "hwrt", root / "hasy", root / "join",
                                      protocol, output)
            self.assertTrue(output.is_dir())
            self.assertFalse((output / "data-receipt.json").exists())


if __name__ == "__main__":
    unittest.main()
