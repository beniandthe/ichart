import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_domain_reject_data as data
from ichart_recognition_ml.research import personal_hwrt_stroke_data as parent_data
from ichart_recognition_ml.research import personal_hwrt_stroke_train as parent_train


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def vocabulary():
    return tuple([f"L{index:03d}" for index in range(97)] + list(parent_train.NOVEL_LABELS))


def row(index, *, source="uji", label="L000", writer="W00", session=1, native=None):
    return {
        "opaqueID": sha(f"opaque-{index}".encode()),
        "label": label,
        "source": source,
        "writer": writer if source == "uji" else None,
        "session": session if source == "uji" else None,
        "nativeSymbolID": native if source == "hwrt" else None,
        "rasterSHA256": sha(f"raster-{index}".encode()),
        "normalizedGeometrySHA256": sha(f"geometry-{index}".encode()),
        "fieldSHA256": sha(f"field-{index}".encode()),
    }


def complete_parent_rows():
    result = []
    index = 0
    old = vocabulary()[:97]
    for writer_index in range(32):
        writer = f"trn_UJI_W{writer_index:02d}"
        for session in (1, 2):
            for label in old:
                result.append(row(index, label=label, writer=writer, session=session))
                index += 1
    native_ids = sorted(parent_train.NATIVE_MAPPING)
    counts = (487, 487, 482, 482, 482, 482, 482, 481)
    for native, count in zip(native_ids, counts):
        for _ in range(count):
            result.append(row(
                index, source="hwrt", label=parent_train.NATIVE_MAPPING[native],
                writer=None, session=None, native=native,
            ))
            index += 1
    return result


def source_bindings():
    return {
        "ujiSourceSHA256": parent_data.SOURCE_SHA256,
        "hwrtReceiptSHA256": parent_data.HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": parent_data.HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": parent_data.HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": parent_data.HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": parent_data.HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": parent_data.JOIN_REPORT_SHA256,
        "domain": {"bytes": 1, "sha256": parent_data.DOMAIN_SHA256},
        "hwrtArchiveSHA256": parent_data.HWRT_ARCHIVE_SHA256,
    }


def synthetic_receipt(root, fit_rows, query_rows, shape=(1, 2, 3)):
    source = list(vocabulary())
    legal = source[:41]
    artifacts = {
        relative: {"bytes": 1, "sha256": "f" * 64}
        for relative in data._expected_artifacts()
    }
    for fold in data.FOLDS:
        fold_root = root / "folds" / fold
        fold_root.mkdir(parents=True)
        fit_array = np.arange(len(fit_rows) * np.prod(shape), dtype=np.float32).reshape(
            len(fit_rows), *shape
        )
        query_array = np.arange(len(query_rows) * np.prod(shape), dtype=np.float32).reshape(
            len(query_rows), *shape
        )
        np.save(fold_root / "fit-rasters.npy", fit_array, allow_pickle=False)
        np.save(fold_root / "query-rasters.npy", query_array, allow_pickle=False)
        fit = {
            "version": data.FIT_DATA_VERSION, "fold": fold,
            "vocabulary": source,
            "rows": [{key: item[key] for key in data._FIT_ROW_FIELDS} for item in fit_rows],
        }
        blind = [{key: item[key] for key in data._BLIND_FIELDS} for item in query_rows]
        inputs = {
            "version": data.QUERY_INPUTS_VERSION, "fold": fold,
            "vocabulary": source, "rows": blind,
        }
        fingerprints = {
            "version": data.FIT_FINGERPRINTS_VERSION, "fold": fold,
            "rows": [{key: item[key] for key in data._BLIND_FIELDS} for item in fit_rows],
        }
        for name, value in (
            ("fit.json", fit), ("query-inputs.json", inputs),
            ("fit-fingerprints.json", fingerprints),
        ):
            (fold_root / name).write_bytes(canonical_json_bytes(value))
        paths = data._fold_paths(fold)
        for key in ("fitRasters", "queryRasters", "fitMetadata", "queryInputs", "fitFingerprints"):
            artifacts[paths[key]] = parent_data._artifact(root / paths[key])
    receipt = {
        "version": data.DATA_VERSION,
        "protocolSHA256": data.PROTOCOL_SHA256,
        "rasterVersion": data.RASTER_VERSION,
        "parent": {
            "dataReceiptSHA256": data.PARENT_RECEIPT_SHA256,
            "trainingMetadataSHA256": data.PARENT_METADATA_SHA256,
            "fieldsSHA256": data.PARENT_FIELDS_SHA256,
            "dataVersion": parent_data.DATA_VERSION,
            "fieldVersion": parent_data.FIELD_VERSION,
            "rows": data.PARENT_ROWS,
            "sourceBindings": source_bindings(),
        },
        "domain": {"bytes": 1, "sha256": data.DOMAIN_SHA256},
        "sourceVocabulary": source,
        "legalOldLabels": legal,
        "candidateLabels": legal + list(parent_train.NOVEL_LABELS) + ["REJECT"],
        "folds": {
            fold: {
                "fitRows": len(fit_rows), "queryRows": len(query_rows),
                "fitUJI": 1, "fitHWRT": len(fit_rows) - 1,
                "queryUJI": 1, "queryHWRT": len(query_rows) - 1,
                "copyExcludedRows": 0, "paths": data._fold_paths(fold),
            }
            for fold in data.FOLDS
        },
        "artifacts": artifacts,
        "codeSHA256": {"synthetic": "0" * 64},
        "runtime": {"python": "test", "numpy": str(np.__version__)},
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
    (root / "data-receipt.json").write_bytes(canonical_json_bytes(receipt))
    return receipt


class PersonalDomainRejectDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = complete_parent_rows()

    def test_fixed_writer_and_per_native_splits_have_exact_coverage(self):
        metadata = {
            "version": parent_data.TRAINING_VERSION,
            "vocabulary": list(vocabulary()),
            "rows": self.rows,
        }
        rows, labels = data._validate_parent_rows(metadata)
        split, indexes = data._split_rows(rows)
        self.assertEqual(labels, vocabulary())
        self.assertEqual(len(split["writerBlocks"]["A16"]), 16)
        self.assertEqual(len(split["writerBlocks"]["B16"]), 16)
        self.assertFalse(set(split["writerBlocks"]["A16"]) & set(split["writerBlocks"]["B16"]))
        self.assertEqual(split["counts"], {
            "parentRows": 10073, "ujiRows": 6208, "hwrtRows": 3865,
            "hwrtFitRows": 3095, "hwrtQueryRows": 770,
            "queryExposures": 7748, "distinctQueryRows": 6978,
        })
        first, second = (indexes[fold] for fold in data.FOLDS)
        first_query_hwrt = {i for i in first["query"] if rows[i]["source"] == "hwrt"}
        second_query_hwrt = {i for i in second["query"] if rows[i]["source"] == "hwrt"}
        self.assertEqual(first_query_hwrt, second_query_hwrt)
        self.assertEqual(len(first_query_hwrt), 770)
        self.assertNotIn("label", str(split))

    def test_parent_grid_rejects_missing_or_changed_source_role(self):
        metadata = {
            "version": parent_data.TRAINING_VERSION,
            "vocabulary": list(vocabulary()),
            "rows": list(self.rows),
        }
        changed = dict(metadata["rows"][0]); changed["session"] = 3
        metadata["rows"][0] = changed
        with self.assertRaises(ValueError):
            data._validate_parent_rows(metadata)
        metadata["rows"] = self.rows[:-1]
        with self.assertRaises(ValueError):
            data._validate_parent_rows(metadata)

    def test_raster_extraction_requires_exact_parent_uint8_hash(self):
        pixels = np.arange(
            data.RASTER_HEIGHT * data.RASTER_WIDTH, dtype=np.uint8
        ).reshape(data.RASTER_HEIGHT, data.RASTER_WIDTH)
        plane = pixels.astype(np.float32) / np.float32(255.0)
        item = {"rasterSHA256": sha(pixels.tobytes())}
        np.testing.assert_array_equal(data._verify_plane(plane, item), plane)
        with self.assertRaises(ValueError):
            data._verify_plane(plane, {"rasterSHA256": "e" * 64})
        changed = plane.copy(); changed[0, 0] = np.float32(0.123)
        with self.assertRaises(ValueError):
            data._verify_plane(changed, item)

    def test_copy_union_is_label_free_and_uses_one_query_representative(self):
        fit = [row(0)]
        first, second, third = row(1), row(2), row(3)
        second["rasterSHA256"] = first["rasterSHA256"]
        third["normalizedGeometrySHA256"] = fit[0]["normalizedGeometrySHA256"]
        reasons = data._copy_reasons(fit, [second, first, third])
        repeated = max(first["opaqueID"], second["opaqueID"])
        self.assertIn("repeated-query-rasterSHA256", reasons[repeated])
        self.assertIn("fit-normalizedGeometrySHA256", reasons[third["opaqueID"]])
        self.assertNotIn("label", str(reasons))

    def test_fit_loader_opens_only_its_fit_artifacts(self):
        fit_rows = [row(0), row(1, source="hwrt", writer=None, session=None, native="196", label="+")]
        query_rows = [row(2), row(3, source="hwrt", writer=None, session=None, native="922", label="/")]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); synthetic_receipt(root, fit_rows, query_rows)
            opened = []
            original = parent_data._read_regular

            def observed(path, **kwargs):
                try:
                    relative = str(Path(path).relative_to(root))
                except ValueError:
                    return original(path, **kwargs)
                opened.append(relative)
                if "query" in Path(path).name or "truth" in Path(path).name or "split" in Path(path).name:
                    raise AssertionError("fit loader crossed role boundary")
                return original(path, **kwargs)

            with patch.object(data, "FIT_ROWS", 2), patch.object(data, "QUERY_ROWS", 2), \
                    patch.object(data, "UJI_FOLD_ROWS", 1), patch.object(data, "HWRT_FIT_ROWS", 1), \
                    patch.object(data, "HWRT_QUERY_ROWS", 1), patch.object(data, "RASTER_SHAPE", (1, 2, 3)), \
                    patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}), \
                    patch.object(parent_data, "_read_regular", side_effect=observed):
                rasters, metadata, _ = data.load_fit(root, "A16-to-B16")
            self.assertEqual(rasters.shape, (2, 1, 2, 3))
            self.assertEqual(len(metadata["rows"]), 2)
            self.assertEqual(opened, ["data-receipt.json", "folds/A16-to-B16/fit.json"])

    def test_query_and_fingerprint_loaders_never_open_labels_or_truth(self):
        fit_rows = [row(0), row(1, source="hwrt", writer=None, session=None, native="196", label="+")]
        query_rows = [row(2), row(3, source="hwrt", writer=None, session=None, native="922", label="/")]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); synthetic_receipt(root, fit_rows, query_rows)
            opened = []
            original = parent_data._read_regular

            def observed(path, **kwargs):
                try:
                    relative = str(Path(path).relative_to(root))
                except ValueError:
                    return original(path, **kwargs)
                opened.append(relative)
                if Path(path).name in ("fit.json", "query-truth.json", "split.json"):
                    raise AssertionError("blind loader opened a forbidden artifact")
                return original(path, **kwargs)

            patches = (
                patch.object(data, "FIT_ROWS", 2), patch.object(data, "QUERY_ROWS", 2),
                patch.object(data, "UJI_FOLD_ROWS", 1), patch.object(data, "HWRT_FIT_ROWS", 1),
                patch.object(data, "HWRT_QUERY_ROWS", 1), patch.object(data, "RASTER_SHAPE", (1, 2, 3)),
                patch.object(data, "code_identity", return_value={"synthetic": "0" * 64}),
                patch.object(parent_data, "_read_regular", side_effect=observed),
            )
            with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6], patches[7]:
                rasters, inputs, _ = data.load_query(root, "B16-to-A16")
                fingerprints, _ = data.load_fit_fingerprints(root, "B16-to-A16")
            self.assertEqual(rasters.shape, (2, 1, 2, 3))
            self.assertEqual(set(inputs["rows"][0]), data._BLIND_FIELDS)
            self.assertEqual(set(fingerprints["rows"][0]), data._BLIND_FIELDS)
            self.assertEqual(opened, [
                "data-receipt.json", "folds/B16-to-A16/query-inputs.json",
                "data-receipt.json", "folds/B16-to-A16/fit-fingerprints.json",
            ])


if __name__ == "__main__":
    unittest.main()
