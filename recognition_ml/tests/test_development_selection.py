import hashlib
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from corpus_v2_fixture import record_mapping, valid_feature_payloads
from ichart_recognition_ml.contracts import CorpusRecord, canonical_json_bytes
from ichart_recognition_ml.development_selection import (
    DEVELOPMENT_COMPARISON_SCHEMA_VERSION,
    DEVELOPMENT_FOLD_ASSIGNMENT_VERSION,
    DEVELOPMENT_SELECTION_RANKING_VERSION,
    MODEL_CANDIDATE_IDS,
    DevelopmentComparisonConfig,
    build_development_model_comparison,
    build_writer_folds,
    load_bound_development_model_selection,
)
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.cli import main as recognition_cli
from ichart_recognition_ml.checkpoint import load_training_checkpoint
from ichart_recognition_ml.manifest import build_manifest, write_manifest
from ichart_recognition_ml.models.output_contract import OUTPUT_CONTRACT_VERSION
from ichart_recognition_ml.schema import FEATURE_SCHEMA
from ichart_recognition_ml.train_pipeline import (
    LOSS_NORMALIZATION_CONTRACT_VERSION,
    TRAJECTORY_AUGMENTATION_CONTRACT_VERSION,
)


class DevelopmentSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.data_root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def _record(self, index, split, label, writer_hash=None, consent=None):
        trajectory, raster = valid_feature_payloads(index)
        trajectory_relative = f"trajectory/{index}.f32le"
        raster_relative = f"raster/{index}.u8"
        if split == "development":
            for relative, payload in (
                (trajectory_relative, trajectory),
                (raster_relative, raster),
            ):
                path = self.data_root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
        mapping = record_mapping(
            index,
            split,
            label,
            writer_hash=writer_hash,
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
        if consent is not None:
            for field in (
                "consent_record_id",
                "consent_record_sha256",
                "consent_ledger_version",
                "consent_scope",
                "consent_status",
            ):
                mapping[field] = consent[field]
        return CorpusRecord.from_mapping(mapping), mapping

    def corpus(self):
        records = []
        index = 1
        for writer_index in range(1, 5):
            writer_hash = f"{writer_index:064x}"
            notation, consent = self._record(
                index, "development", "C", writer_hash=writer_hash
            )
            index += 1
            negative, _ = self._record(
                index,
                "development",
                None,
                writer_hash=writer_hash,
                consent=consent,
            )
            index += 1
            records.extend((notation, negative))
        calibration, _ = self._record(index, "calibration", "G7")
        index += 1
        sealed, _ = self._record(index, "sealed-evaluation", "F")
        records.extend((calibration, sealed))
        return tuple(records)

    def test_folds_are_deterministic_writer_disjoint_and_sample_balanced(self):
        development = self.corpus()[:8]
        first = build_writer_folds(development, 3)
        second = build_writer_folds(tuple(reversed(development)), 3)
        self.assertEqual(first, second)
        flattened = [writer for fold in first for writer in fold]
        self.assertEqual(len(flattened), len(set(flattened)))
        self.assertEqual(len(flattened), 4)
        fold_samples = [
            sum(record.writer_id_hash in fold for record in development)
            for fold in first
        ]
        self.assertLessEqual(max(fold_samples) - min(fold_samples), 2)

    def test_comparison_never_loads_non_development_feature_bytes(self):
        report = build_development_model_comparison(
            self.corpus(),
            self.data_root,
            DevelopmentComparisonConfig(
                fold_count=2,
                seeds=(17, 29),
                epochs=1,
                batch_size=8,
            ),
        )
        self.assertEqual(
            report["schema_version"], DEVELOPMENT_COMPARISON_SCHEMA_VERSION
        )
        self.assertEqual(
            {item["candidate_id"] for item in report["candidate_aggregates"]},
            set(MODEL_CANDIDATE_IDS),
        )
        self.assertIn(report["selected_candidate_id"], MODEL_CANDIDATE_IDS)
        self.assertEqual(report["authority"], "development-model-selection-only")
        self.assertEqual(report["feature_schema_version"], FEATURE_SCHEMA.version)
        self.assertEqual(report["output_contract_version"], OUTPUT_CONTRACT_VERSION)
        self.assertEqual(
            report["fold_assignment_version"],
            DEVELOPMENT_FOLD_ASSIGNMENT_VERSION,
        )
        self.assertEqual(
            report["selection_ranking_version"],
            DEVELOPMENT_SELECTION_RANKING_VERSION,
        )
        self.assertEqual(
            report["loss_normalization_contract_version"],
            LOSS_NORMALIZATION_CONTRACT_VERSION,
        )
        self.assertEqual(
            report["trajectory_augmentation_contract_version"],
            TRAJECTORY_AUGMENTATION_CONTRACT_VERSION,
        )
        self.assertTrue(report["writer_balanced_loss"])
        self.assertEqual(
            report["candidate_ids_in_tie_break_order"],
            list(MODEL_CANDIDATE_IDS),
        )
        self.assertIn(
            report["selected_categorical_class_reweighting"],
            ("none", "categorical-inverse-frequency-v1"),
        )
        self.assertEqual(len(report["runs"]), 4 * len(MODEL_CANDIDATE_IDS))
        self.assertFalse(report["calibration_features_loaded"])
        self.assertFalse(report["sealed_features_loaded"])
        self.assertFalse(report["promotion_eligible"])

        report_path = self.data_root / "development-selection.json"
        report_bytes = canonical_json_bytes(report) + b"\n"
        report_path.write_bytes(report_bytes)
        selection = load_bound_development_model_selection(
            report_path,
            self.corpus(),
        )
        self.assertEqual(
            selection.report_sha256,
            hashlib.sha256(report_bytes).hexdigest(),
        )
        self.assertEqual(
            selection.selected_candidate_id,
            report["selected_candidate_id"],
        )
        self.assertEqual(
            selection.selected_architecture_id,
            report["selected_architecture_id"],
        )
        self.assertEqual(
            selection.selected_categorical_class_reweighting,
            report["selected_categorical_class_reweighting"],
        )

        # Training consumes the report rather than relying on copied winner
        # flags, and carries the exact report-byte digest into the checkpoint.
        records = self.corpus()
        records_path = self.data_root / "selection-records.jsonl"
        manifest_path = self.data_root / "selection-manifest.json"
        records_path.write_text(
            "".join(
                json.dumps(record.as_dict(), sort_keys=True) + "\n"
                for record in records
            ),
            encoding="utf-8",
        )
        write_manifest(
            manifest_path,
            build_manifest(records, "bound-selection-test-v1"),
        )
        training_output = self.data_root / "bound-training"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = recognition_cli(
                [
                    "train",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--development-selection-report",
                    str(report_path),
                    "--model-identifier",
                    "bound-selection-test",
                    "--output-dir",
                    str(training_output),
                ]
            )
        self.assertEqual(code, 0, stderr.getvalue())
        training_payload = json.loads(stdout.getvalue())
        self.assertEqual(
            training_payload["development_selection_report_sha256"],
            selection.report_sha256,
        )
        checkpoint = load_training_checkpoint(Path(training_payload["checkpoint"]))
        self.assertEqual(
            checkpoint.metadata.development_selection_report_sha256,
            selection.report_sha256,
        )
        self.assertEqual(
            checkpoint.metadata.model_architecture_id,
            selection.selected_architecture_id,
        )
        self.assertEqual(
            checkpoint.metadata.training_config.categorical_class_reweighting,
            selection.selected_categorical_class_reweighting,
        )
        self.assertEqual(
            checkpoint.metadata.training_config.epochs,
            selection.comparison_config.epochs,
        )
        self.assertEqual(
            checkpoint.metadata.training_config.seed,
            selection.comparison_config.seeds[0],
        )

        missing_report_output = self.data_root / "missing-report-evaluation"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = recognition_cli(
                [
                    "evaluate",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--checkpoint",
                    str(training_payload["checkpoint"]),
                    "--require-promotion-gate",
                    "--output-dir",
                    str(missing_report_output),
                ]
            )
        self.assertEqual(code, 2)
        self.assertEqual(
            json.loads(stderr.getvalue())["error"]["code"],
            "development_selection_report_required",
        )
        self.assertFalse(missing_report_output.exists())

        # Held-out features were absent throughout comparison, training, and
        # the rejected evaluation. Only an actual evaluation needs sealed ink;
        # calibration ink remains unavailable even for this command.
        trajectory, raster = valid_feature_payloads(10)
        for relative, payload in (
            ("trajectory/10.f32le", trajectory),
            ("raster/10.u8", raster),
        ):
            artifact = self.data_root / relative
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(payload)

        promotion_evaluation_output = self.data_root / "promotion-evaluation"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = recognition_cli(
                [
                    "evaluate",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--checkpoint",
                    str(training_payload["checkpoint"]),
                    "--development-selection-report",
                    str(report_path),
                    "--require-promotion-gate",
                    "--output-dir",
                    str(promotion_evaluation_output),
                ]
            )
        self.assertEqual(code, 0, stderr.getvalue())
        evaluation_payload = json.loads(stdout.getvalue())
        self.assertTrue(
            evaluation_payload["development_selection_revalidated"]
        )
        self.assertEqual(
            evaluation_payload["development_selection_report_sha256"],
            selection.report_sha256,
        )
        self.assertFalse(evaluation_payload["promotion_eligible"])
        self.assertFalse(evaluation_payload["sealed_gate_receipt_produced"])
        self.assertEqual(
            evaluation_payload["status"],
            "sealed-descriptive-evaluation-only",
        )

        # A second, internally valid comparison is not interchangeable with
        # the report that actually selected this checkpoint. Reject it before
        # any predictions, including when supplied for descriptive evaluation.
        alternate_report = build_development_model_comparison(
            records,
            self.data_root,
            DevelopmentComparisonConfig(
                fold_count=2,
                seeds=(29,),
                epochs=1,
                batch_size=8,
            ),
        )
        alternate_report_path = self.data_root / "alternate-selection.json"
        alternate_report_path.write_bytes(
            canonical_json_bytes(alternate_report) + b"\n"
        )
        for require_gate in (False, True):
            with self.subTest(alternate_report_requires_gate=require_gate):
                refused_output = self.data_root / f"alternate-evaluation-{require_gate}"
                stdout = io.StringIO()
                stderr = io.StringIO()
                with (
                    patch("ichart_recognition_ml.cli.run_sealed_model_assessment")
                    as assessment,
                    contextlib.redirect_stdout(stdout),
                    contextlib.redirect_stderr(stderr),
                ):
                    code = recognition_cli(
                        [
                            "evaluate",
                            "--records",
                            str(records_path),
                            "--data-root",
                            str(self.data_root),
                            "--manifest",
                            str(manifest_path),
                            "--checkpoint",
                            str(training_payload["checkpoint"]),
                            "--development-selection-report",
                            str(alternate_report_path),
                            "--output-dir",
                            str(refused_output),
                        ]
                        + (["--require-promotion-gate"] if require_gate else [])
                    )
                self.assertEqual(code, 2)
                self.assertEqual(
                    json.loads(stderr.getvalue())["error"]["code"],
                    "checkpoint_development_selection_mismatch",
                )
                assessment.assert_not_called()
                self.assertFalse(refused_output.exists())

        mismatch_output = self.data_root / "mismatched-training"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = recognition_cli(
                [
                    "train",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--development-selection-report",
                    str(report_path),
                    "--model-identifier",
                    "mismatched-selection-test",
                    "--epochs",
                    str(selection.comparison_config.epochs + 1),
                    "--output-dir",
                    str(mismatch_output),
                ]
            )
        self.assertEqual(code, 2)
        self.assertEqual(
            json.loads(stderr.getvalue())["error"]["code"],
            "development_selection_training_config_mismatch",
        )
        self.assertFalse(mismatch_output.exists())

        mismatched_seed_output = self.data_root / "mismatched-seed-training"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = recognition_cli(
                [
                    "train",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--development-selection-report",
                    str(report_path),
                    "--model-identifier",
                    "mismatched-seed-selection-test",
                    "--seed",
                    "29",
                    "--output-dir",
                    str(mismatched_seed_output),
                ]
            )
        self.assertEqual(code, 2)
        self.assertEqual(
            json.loads(stderr.getvalue())["error"]["code"],
            "development_selection_seed_mismatch",
        )
        self.assertFalse(mismatched_seed_output.exists())

        tampered = json.loads(json.dumps(report))
        tampered["selected_candidate_id"] = next(
            candidate
            for candidate in MODEL_CANDIDATE_IDS
            if candidate != report["selected_candidate_id"]
        )
        report_path.write_bytes(canonical_json_bytes(tampered) + b"\n")
        with self.assertRaisesRegex(
            ContractError, "development_selection_winner_mismatch"
        ):
            load_bound_development_model_selection(report_path, self.corpus())

    def test_comparison_refuses_insufficient_writers_and_invalid_seeds(self):
        development = self.corpus()[:6]
        with self.assertRaisesRegex(
            OperationRefusedError, "insufficient_development_writers"
        ):
            build_writer_folds(development, 2)
        with self.assertRaisesRegex(
            ContractError, "invalid_development_comparison_config"
        ):
            DevelopmentComparisonConfig(seeds=(17, 17)).validate()

    def test_cli_does_not_prevalidate_calibration_or_sealed_feature_bytes(self):
        records = self.corpus()
        records_path = self.data_root / "records.jsonl"
        manifest_path = self.data_root / "manifest.json"
        output_path = self.data_root / "comparison"
        records_path.write_text(
            "".join(json.dumps(record.as_dict(), sort_keys=True) + "\n" for record in records),
            encoding="utf-8",
        )
        write_manifest(manifest_path, build_manifest(records, "test-development-v1"))
        fake_report = {
            "authority": "architecture-selection-only",
            "promotion_eligible": False,
            "selected_candidate_id": MODEL_CANDIDATE_IDS[0],
            "status": "development-only-model-comparison",
        }
        stdout = io.StringIO()
        with patch(
            "ichart_recognition_ml.cli.build_development_model_comparison",
            return_value=fake_report,
        ), contextlib.redirect_stdout(stdout):
            code = recognition_cli(
                [
                    "compare-development-models",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--manifest",
                    str(manifest_path),
                    "--output-dir",
                    str(output_path),
                ]
            )
        self.assertEqual(code, 0, stdout.getvalue())
        self.assertTrue((output_path / "development_model_comparison.json").is_file())


if __name__ == "__main__":
    unittest.main()
