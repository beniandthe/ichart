import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout

import numpy as np

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.features import InkPoint, InkStroke, rasterize
from ichart_recognition_ml.research import personal_hwrt_stroke_data as frozen_data
from ichart_recognition_ml.research import personal_unoriented_hwrt_data as data


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def stroke(offset=0.0):
    return (
        InkStroke((
            InkPoint(offset, 0.0), InkPoint(offset + 2.0, 3.0),
            InkPoint(offset + 5.0, 1.0),
        )),
        InkStroke((InkPoint(offset + 8.0, 4.0),)),
    )


def source_row(index, *, role="training", source="uji", label="L000"):
    return frozen_data._SourceRow(
        frozen_data._opaque(source, role, index), label, source,
        "trn_UJI_W00" if source == "uji" else None,
        1 if source == "uji" else None,
        None if source == "uji" else "196",
        f"source-{index}", index, stroke(index * 10.0),
    )


def vocabulary():
    return [f"L{index:03d}" for index in range(102)]


def source_bindings():
    return {
        "ujiSourceSHA256": frozen_data.SOURCE_SHA256,
        "hwrtReceiptSHA256": frozen_data.HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": frozen_data.HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": frozen_data.HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": frozen_data.HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": frozen_data.HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": frozen_data.JOIN_REPORT_SHA256,
        "domain": {"bytes": 1, "sha256": frozen_data.DOMAIN_SHA256},
        "hwrtArchiveSHA256": frozen_data.HWRT_ARCHIVE_SHA256,
    }


def metadata_row(index, *, source="uji"):
    return {
        "opaqueID": f"{index + 100:064x}",
        "label": "L000",
        "source": source,
        "writer": "trn_UJI_W00" if source == "uji" else None,
        "session": 1 if source == "uji" else None,
        "nativeSymbolID": None if source == "uji" else "196",
        "rasterSHA256": f"{index + 1:064x}",
        "normalizedGeometrySHA256": f"{index + 10:064x}",
        "fieldSHA256": f"{index + 20:064x}",
    }


def reversal_ledger(rows):
    return {
        "version": "personal-unoriented-training-global-reversal-check-v1",
        "rowsChecked": rows,
        "auxiliaryRowsBitEqual": rows,
        "auxiliaryMismatchRows": 0,
        "occupancyMismatchRows": 0,
        "occupancyMismatchPixels": 0,
        "occupancyMaximumAbsoluteError": 0.0,
        "occupancyMismatchOpaqueIDs": [],
    }


def publish_bundle(root, role, rows, fields):
    np.save(root / "fields.npy", fields, allow_pickle=False)
    name = "training.json" if role == "training" else "inputs.json"
    payload_rows = rows if role == "training" else [
        {key: row[key] for key in data._BLIND_FIELDS} for row in rows
    ]
    metadata = {
        "version": data.TRAINING_VERSION if role == "training" else data.DEVELOPMENT_INPUTS_VERSION,
        "vocabulary": vocabulary(),
        "rows": payload_rows,
    }
    (root / name).write_bytes(canonical_json_bytes(metadata))
    artifacts = {
        "fields.npy": frozen_data._artifact(root / "fields.npy"),
        name: frozen_data._artifact(root / name),
    }
    if role == "development":
        artifacts["truth.json"] = {"bytes": 17, "sha256": "f" * 64}
    receipt = data._receipt(
        role, vocabulary(), artifacts, {"synthetic": "0" * 64},
        {
            "rows": len(rows),
            "ujiRows": sum(row["source"] == "uji" for row in rows),
            "hwrtRows": sum(row["source"] == "hwrt" for row in rows),
            **({"copyUnionRows": 0} if role == "development" else {}),
        },
        source_bindings(),
        prior_identity=data._prior_identity(),
        reversal_checks=reversal_ledger(len(rows)) if role == "training" else None,
        fit_receipt_sha="a" * 64 if role == "development" else None,
        training_receipt_sha="b" * 64 if role == "development" else None,
    )
    (root / "data-receipt.json").write_bytes(canonical_json_bytes(receipt))
    return metadata, receipt


class PersonalUnorientedHWRTDataTests(unittest.TestCase):
    def test_cli_summary_is_valid_json_without_source_work(self):
        summary = {
            "role": "training",
            "counts": {"rows": 10073, "ujiRows": 6208, "hwrtRows": 3865},
        }
        output = io.StringIO()
        with patch.object(data, "prepare_training", return_value=summary), redirect_stdout(output):
            data.main([
                "--uji-source", "/uji", "--hwrt-intake", "/hwrt",
                "--hasy-intake", "/hasy", "--join-report", "/join",
                "--protocol", "/protocol", "--output", "/output",
                "--role", "training",
            ])
        self.assertEqual(json.loads(output.getvalue()), {
            "hwrtRows": 3865, "role": "training", "rows": 10073, "ujiRows": 6208,
        })

    def test_feature_row_preserves_app_raster_and_global_reversal_auxiliary_bits(self):
        row = source_row(0)
        field, metadata, check = data._feature_row(row)
        pixels = rasterize(row.strokes).pixels
        expected = np.frombuffer(pixels, np.uint8).reshape(96, 256).astype(np.float32) / 255
        np.testing.assert_array_equal(field[0], expected)
        reversed_field = data.neutral_field.encode_unoriented_stroke_field(
            data._reversed_strokes(row.strokes)
        )
        self.assertEqual(field[1:].tobytes(), reversed_field[1:].tobytes())
        self.assertTrue(check.auxiliary_equal)
        self.assertEqual(metadata["opaqueID"], row.opaque_id)
        self.assertEqual(metadata["rasterSHA256"], sha(pixels))
        self.assertEqual(metadata["fieldSHA256"], sha(field.astype("<f4").tobytes()))

    def test_auxiliary_reversal_mismatch_fails_instead_of_repairing(self):
        row = source_row(0)
        raster = rasterize(row.strokes).pixels
        first = np.zeros((5, 96, 256), dtype=np.float32)
        first[0] = np.frombuffer(raster, np.uint8).reshape(96, 256).astype(np.float32) / 255
        second = first.copy(); second[1, 0, 0] = 1.0
        with patch.object(
            data.neutral_field, "encode_unoriented_stroke_field", side_effect=(first, second)
        ), self.assertRaisesRegex(ValueError, "global reversal"):
            data._feature_row(row)

    def test_prior_training_alignment_binds_order_identity_geometry_and_occupancy(self):
        first, second = metadata_row(0), metadata_row(1)
        current = [dict(first, fieldSHA256="a" * 64), dict(second, fieldSHA256="b" * 64)]
        with patch.object(data, "TRAINING_ROWS", 2):
            data._validate_prior_alignment([first, second], current)
            changed = [dict(first), dict(second)]
            changed[1]["rasterSHA256"] = "e" * 64
            with self.assertRaisesRegex(ValueError, "row 1"):
                data._validate_prior_alignment([first, second], changed)
            with self.assertRaises(ValueError):
                data._validate_prior_alignment([first, second], list(reversed(current)))

    def test_training_loader_requires_new_versions_prior_binding_and_reversal_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            fields = np.arange(2 * 5 * 2 * 3, dtype=np.float32).reshape(2, 5, 2, 3)
            rows = [metadata_row(0), metadata_row(1, source="hwrt")]
            _, receipt = publish_bundle(root, "training", rows, fields)
            patches = (
                patch.object(data, "TRAINING_ROWS", 2),
                patch.object(data, "UJI_TRAINING_ROWS", 1),
                patch.object(data, "HWRT_TRAINING_ROWS", 1),
                patch.object(data, "FIELD_SHAPE", (5, 2, 3)),
                patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}),
            )
            with patches[0], patches[1], patches[2], patches[3], patches[4]:
                loaded, metadata, returned = data.load_training(root)
            self.assertIsInstance(loaded, np.memmap)
            np.testing.assert_array_equal(loaded, fields)
            self.assertEqual(metadata["rows"], rows)
            self.assertEqual(returned["fieldVersion"], data.FIELD_VERSION)

            changed = dict(receipt)
            changed["reversalChecks"] = dict(receipt["reversalChecks"], rowsChecked=1)
            (root / "data-receipt.json").write_bytes(canonical_json_bytes(changed))
            with patch.object(data, "TRAINING_ROWS", 2), patch.object(data, "UJI_TRAINING_ROWS", 1), \
                    patch.object(data, "HWRT_TRAINING_ROWS", 1), patch.object(data, "FIELD_SHAPE", (5, 2, 3)), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                    self.assertRaises(ValueError):
                data.load_training(root)

            changed = dict(receipt); changed["priorTrainingMetadata"] = dict(
                receipt["priorTrainingMetadata"], trainingMetadataSHA256="e" * 64
            )
            (root / "data-receipt.json").write_bytes(canonical_json_bytes(changed))
            with patch.object(data, "TRAINING_ROWS", 2), patch.object(data, "UJI_TRAINING_ROWS", 1), \
                    patch.object(data, "HWRT_TRAINING_ROWS", 1), patch.object(data, "FIELD_SHAPE", (5, 2, 3)), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                    self.assertRaises(ValueError):
                data.load_training(root)

    def test_development_loader_never_opens_or_hashes_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            fields = np.arange(2 * 5 * 2 * 3, dtype=np.float32).reshape(2, 5, 2, 3)
            rows = [metadata_row(0), metadata_row(1, source="hwrt")]
            publish_bundle(root, "development", rows, fields)
            self.assertFalse((root / "truth.json").exists())
            opened = []
            original = frozen_data._read_regular

            def observed(path, **kwargs):
                opened.append(Path(path).name)
                if Path(path).name == "truth.json":
                    raise AssertionError("blind loader opened truth")
                return original(path, **kwargs)

            with patch.object(data, "DEVELOPMENT_ROWS", 2), \
                    patch.object(data, "UJI_DEVELOPMENT_ROWS", 1), \
                    patch.object(data, "HWRT_DEVELOPMENT_ROWS", 1), \
                    patch.object(data, "FIELD_SHAPE", (5, 2, 3)), \
                    patch.object(frozen_data, "_read_regular", side_effect=observed), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}):
                loaded, inputs, receipt = data.load_development_inputs(root)
            self.assertEqual(opened, ["data-receipt.json", "inputs.json"])
            self.assertEqual(loaded.shape, (2, 5, 2, 3))
            self.assertEqual(set(inputs["rows"][0]), data._BLIND_FIELDS)
            self.assertEqual(receipt["artifacts"]["truth.json"]["sha256"], "f" * 64)

    def test_development_fit_gate_precedes_all_development_source_work(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); protocol = root / "protocol.md"
            protocol.write_bytes(b"fixed")
            training_receipt = {
                "vocabulary": vocabulary(), "priorTrainingMetadata": data._prior_identity()
            }
            with patch.object(data, "PROTOCOL_SHA256", sha(b"fixed")), \
                    patch.object(data, "_training_metadata", return_value=(
                        {"rows": [metadata_row(0)]}, training_receipt, "b" * 64
                    )), \
                    patch.object(data, "_validate_fit", side_effect=ValueError("fit incomplete")), \
                    patch.object(frozen_data, "_source_rows", side_effect=AssertionError("source opened")), \
                    self.assertRaisesRegex(ValueError, "fit incomplete"):
                data.prepare_development(
                    root / "uji", root / "hwrt", root / "hasy", root / "join",
                    protocol, root / "training", root / "fit", "a" * 64,
                    root / "output",
                )
            self.assertFalse((root / "output").exists())

    def test_encoding_failure_retains_no_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); protocol = root / "protocol.md"
            protocol.write_bytes(b"fixed"); output = root / "output"
            prior = {"version": "prior", "rows": [metadata_row(0)]}
            prior_receipt = {"version": frozen_data.DATA_VERSION}
            with patch.object(data, "PROTOCOL_SHA256", sha(b"fixed")), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                    patch.object(frozen_data, "_source_snapshot", return_value={}), \
                    patch.object(data, "_load_prior_training_metadata", return_value=(
                        prior, prior_receipt, data.PRIOR_TRAINING_RECEIPT_SHA256
                    )), \
                    patch.object(frozen_data, "_source_rows", return_value=(
                        (source_row(0),), tuple(vocabulary()), source_bindings()
                    )), \
                    patch.object(data, "_encode_rows", side_effect=ValueError("encoding failed")), \
                    self.assertRaisesRegex(ValueError, "encoding failed"):
                data.prepare_training(
                    root / "uji", root / "hwrt", root / "hasy", root / "join",
                    protocol, output,
                )
            self.assertTrue(output.is_dir())
            self.assertFalse((output / "data-receipt.json").exists())


if __name__ == "__main__":
    unittest.main()
