import contextlib
import hashlib
import importlib.util
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path

from ichart_recognition_ml.cli import main
from ichart_recognition_ml.schema import FEATURE_SCHEMA, SPLITS
from corpus_v2_fixture import record_mapping


class CLITests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.data_root = self.root / "data"
        self.records_path = self.root / "records.jsonl"
        self.manifest_path = self.root / "manifest.json"
        self._write_valid_records()

    def tearDown(self):
        self.temporary.cleanup()

    def _write_valid_records(self):
        records = []
        for index, split in enumerate(SPLITS, start=1):
            trajectory = struct.pack(
                f"<{FEATURE_SCHEMA.trajectory_value_count}f",
                *([float(index)] * FEATURE_SCHEMA.trajectory_value_count),
            )
            raster = bytes([index]) * FEATURE_SCHEMA.raster_byte_count
            trajectory_relative = f"trajectory/{index}.f32le"
            raster_relative = f"raster/{index}.u8"
            for relative, payload in ((trajectory_relative, trajectory), (raster_relative, raster)):
                path = self.data_root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
            records.append(
                record_mapping(
                    index,
                    split,
                    "G7",
                    trajectory={
                        "relative_path": trajectory_relative,
                        "sha256": hashlib.sha256(trajectory).hexdigest(),
                        "byte_count": len(trajectory),
                        "encoding": "float32-le",
                    },
                    raster={
                        "relative_path": raster_relative,
                        "sha256": hashlib.sha256(raster).hexdigest(),
                        "byte_count": len(raster),
                        "encoding": "uint8-gray",
                    },
                )
            )
        self.records = records
        self._save_records()

    def _save_records(self):
        self.records_path.write_text(
            "".join(json.dumps(record, sort_keys=True) + "\n" for record in self.records),
            encoding="utf-8",
        )

    def _run(self, arguments):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(arguments)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_build_and_validate_manifest(self):
        code, output, error = self._run(
            [
                "build-manifest",
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
                "--dataset-version",
                "pilot-001",
                "--output",
                str(self.manifest_path),
            ]
        )
        self.assertEqual((code, error), (0, ""))
        self.assertEqual(json.loads(output)["status"], "manifest-written")
        code, output, error = self._run(
            [
                "validate-manifest",
                "--manifest",
                str(self.manifest_path),
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
            ]
        )
        self.assertEqual((code, error), (0, ""))
        self.assertEqual(json.loads(output)["status"], "manifest-valid")

    def test_cli_fails_closed_for_missing_provenance(self):
        del self.records[0]["provenance_record_sha256"]
        self._save_records()
        code, output, error = self._run(
            [
                "validate-records",
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
            ]
        )
        self.assertEqual((code, output), (2, ""))
        self.assertEqual(json.loads(error)["error"]["code"], "missing_field")

    def test_training_handles_optional_dependencies_after_successful_full_preflight(self):
        build_code, _, _ = self._run(
            [
                "build-manifest",
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
                "--dataset-version",
                "pilot-001",
                "--output",
                str(self.manifest_path),
            ]
        )
        self.assertEqual(build_code, 0)
        code, output, error = self._run(
            [
                "train",
                "--manifest",
                str(self.manifest_path),
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
                "--output-dir",
                str(self.root / "output"),
                "--model-identifier",
                "dual-view-test-v1",
            ]
        )
        has_training_dependencies = all(
            importlib.util.find_spec(module_name) is not None
            for module_name in ("numpy", "torch")
        )
        if has_training_dependencies:
            self.assertEqual((code, error), (0, ""))
            payload = json.loads(output)
            self.assertEqual(payload["status"], "development-training-complete")
            self.assertFalse(payload["negative_no_read_supervision"])
            self.assertFalse(payload["promotion_eligible"])
            checkpoint = Path(payload["checkpoint"])
            self.assertTrue(checkpoint.is_file())

            if importlib.util.find_spec("coremltools") is not None:
                compiled_model = self.root / "ChordInk.mlmodelc"
                model_manifest = self.root / "ChordInk.manifest.json"
                export_code, export_output, export_error = self._run(
                    [
                        "export",
                        "--manifest",
                        str(self.manifest_path),
                        "--records",
                        str(self.records_path),
                        "--data-root",
                        str(self.data_root),
                        "--checkpoint",
                        str(checkpoint),
                        "--output",
                        str(compiled_model),
                        "--manifest-output",
                        str(model_manifest),
                        "--model-identifier",
                        "dual-view-test-v1",
                        "--detached-manifest-sha256",
                        "d" * 64,
                    ]
                )
                # Core ML Tools may emit compatibility warnings for a newer
                # installed PyTorch version even when conversion succeeds.
                # The exit code and immutable artifacts are the authority.
                self.assertEqual(export_code, 0, export_error)
                export_payload = json.loads(export_output)
                self.assertEqual(
                    export_payload["status"],
                    "uncalibrated-shadow-model-exported",
                )
                self.assertEqual(export_payload["authority"], "learned-shadow-only")
                self.assertFalse(export_payload["no_read_trust_established"])
                self.assertTrue(compiled_model.is_dir())
                self.assertTrue(model_manifest.is_file())
        else:
            self.assertEqual((code, output), (2, ""))
            self.assertEqual(
                json.loads(error)["error"]["code"],
                "missing_optional_dependency",
            )
            self.assertFalse((self.root / "output").exists())

    def test_calibration_refuses_without_bound_checkpoint_and_writes_nothing(self):
        build_code, _, _ = self._run(
            [
                "build-manifest",
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
                "--dataset-version",
                "pilot-001",
                "--output",
                str(self.manifest_path),
            ]
        )
        self.assertEqual(build_code, 0)
        output_dir = self.root / "calibration"
        code, output, error = self._run(
            [
                "calibrate",
                "--manifest",
                str(self.manifest_path),
                "--records",
                str(self.records_path),
                "--data-root",
                str(self.data_root),
                "--checkpoint",
                str(self.root / "missing.pt"),
                "--output-dir",
                str(output_dir),
                "--fit-dataset-identifier",
                "calibration-writers-v1",
            ]
        )
        self.assertEqual((code, output), (2, ""))
        self.assertEqual(json.loads(error)["error"]["code"], "checkpoint_unavailable")
        self.assertFalse(output_dir.exists())


if __name__ == "__main__":
    unittest.main()
