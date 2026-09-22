import math
import tempfile
import unittest
from pathlib import Path

from ichart_recognition_ml.calibrate import (
    SCORE_CONTRACT_VERSION,
    JointPathCalibrationObservation,
    TemperatureSearchConfig,
    build_joint_path_observations,
    calibrated_one_vs_rest_support,
    fit_joint_path_temperature,
    make_swift_calibration_artifact,
)
from ichart_recognition_ml.checkpoint import (
    CHECKPOINT_CONTRACT_VERSION,
    CheckpointMetadata,
    require_negative_no_read_supervision,
)
from ichart_recognition_ml.contracts import CorpusRecord
from ichart_recognition_ml.dataset import (
    PipelineRole,
    assert_exact_role,
    require_optional_dependency,
    select_role_records,
)
from ichart_recognition_ml.decode import DecodeResult, DecodedCandidate
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.evaluate import evaluate_sealed_logits
from ichart_recognition_ml.export_coreml import (
    build_swift_model_manifest,
    export_uncalibrated_coreml,
    fingerprint_compiled_model,
)
from ichart_recognition_ml.models.output_contract import (
    HEAD_NAMES,
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
    FactorLogits,
    factorize_canonical_label,
    factorize_ground_truth,
)
from ichart_recognition_ml.schema import GROUND_TRUTH_NO_READ
from ichart_recognition_ml.train_pipeline import TrainingConfig
from corpus_v2_fixture import record_mapping


def root_record(index, split, label):
    return CorpusRecord.from_mapping(record_mapping(index, split, label))


def corpus():
    return (
        root_record(1, "development", "C△7"),
        root_record(2, "calibration", "Db7(b9)/F"),
        root_record(3, "sealed-evaluation", "•/•"),
    )


def perfect_logits(label, magnitude=4.0):
    target = factorize_canonical_label(label)
    values = {}
    for head in OUTPUT_HEADS:
        if head.is_independent_bernoulli:
            values[head.name] = tuple(
                magnitude if expected else -magnitude
                for expected in target.values[head.name]
            )
        else:
            index = target.values[head.name]
            values[head.name] = tuple(
                magnitude if offset == index else -magnitude
                for offset in range(len(head.labels))
            )
    return FactorLogits.from_mapping(values)


class LearnedPipelineContractTests(unittest.TestCase):
    def test_output_contract_exactly_matches_swift_heads(self):
        self.assertEqual(OUTPUT_CONTRACT_VERSION, "chord-ink-factor-output-v1")
        self.assertEqual(
            HEAD_NAMES,
            (
                "validity",
                "kind",
                "root_letter",
                "root_accidental",
                "quality",
                "extension",
                "alteration_logits",
                "slash_presence",
                "slash_bass_letter",
                "slash_bass_accidental",
            ),
        )
        alteration = next(head for head in OUTPUT_HEADS if head.name == "alteration_logits")
        self.assertTrue(alteration.is_independent_bernoulli)
        self.assertEqual(alteration.labels, ("b3", "b5", "#5", "b9", "#9", "#11", "b13"))

    def test_factorization_preserves_five_alterations_and_slash_bass(self):
        target = factorize_canonical_label("C7(b3)(#5)(b9)(#11)(b13)/F#")
        self.assertEqual(target.values["root_letter"], 2)
        self.assertEqual(target.values["extension"], 4)
        self.assertEqual(target.values["alteration_logits"], (1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0))
        self.assertEqual(target.values["slash_presence"], 1)
        self.assertEqual(target.values["slash_bass_letter"], 5)
        self.assertEqual(target.values["slash_bass_accidental"], 1)

    def test_repeat_masks_every_inapplicable_head(self):
        target = factorize_canonical_label("•/•")
        self.assertTrue(target.active["validity"])
        self.assertTrue(target.active["kind"])
        self.assertFalse(target.active["root_letter"])
        self.assertFalse(target.active["alteration_logits"])
        self.assertFalse(target.active["slash_bass_letter"])

    def test_adjudicated_no_read_supervises_validity_only(self):
        target = factorize_ground_truth(GROUND_TRUTH_NO_READ, None)
        self.assertEqual(target.values["validity"], 0)
        self.assertTrue(target.active["validity"])
        self.assertFalse(target.active["kind"])
        self.assertFalse(target.active["root_letter"])

    def test_logits_reject_missing_extra_wrong_shape_and_nonfinite_heads(self):
        valid = perfect_logits("C△7").values
        for mutation, code in (
            ({key: value for key, value in valid.items() if key != "kind"}, "missing_output_head"),
            ({**valid, "confidence": (1.0,)}, "unknown_output_head"),
            ({**valid, "kind": (1.0,)}, "output_shape_mismatch"),
            ({**valid, "kind": (math.nan, 0.0)}, "nonfinite_output_logit"),
        ):
            with self.subTest(code=code), self.assertRaisesRegex(ContractError, code):
                FactorLogits.from_mapping(mutation)

    def test_role_selection_is_exact_and_sealed_cannot_enter_calibration(self):
        records = corpus()
        selected = select_role_records(records, PipelineRole.CALIBRATION)
        self.assertEqual(tuple(record.split for record in selected), ("calibration",))
        with self.assertRaisesRegex(OperationRefusedError, "role_boundary_violation"):
            assert_exact_role((records[2],), PipelineRole.CALIBRATION)

    def test_cross_split_writer_is_rejected_before_any_role_is_selected(self):
        records = list(corpus())
        sealed = records[2]
        records[2] = CorpusRecord(
            **{
                **sealed.__dict__,
                "writer_id_hash": records[0].writer_id_hash,
            }
        )
        with self.assertRaisesRegex(ContractError, "writer_split_leakage"):
            select_role_records(records, PipelineRole.TRAINING)

    def test_joint_path_calibration_matches_swift_one_vs_rest_math(self):
        observations = (
            JointPathCalibrationObservation("candidate-positive", "writer-a", math.log(0.80), True, False),
            JointPathCalibrationObservation("candidate-negative", "writer-b", math.log(0.20), False, False),
            JointPathCalibrationObservation("no-read-positive", "writer-c", math.log(0.70), True, True),
            JointPathCalibrationObservation("no-read-negative", "writer-d", math.log(0.10), False, True),
        )
        result = fit_joint_path_temperature(
            observations,
            calibration_sample_count=4,
            calibration_writer_count=4,
            calibration_records_sha256="e" * 64,
            config=TemperatureSearchConfig(minimum=0.5, maximum=2.0, steps=9),
        )
        self.assertEqual(result.score_contract_version, SCORE_CONTRACT_VERSION)
        self.assertEqual(result.calibration_sample_count, 4)
        self.assertEqual(result.calibration_writer_count, 4)
        self.assertFalse(result.used_writer_disjoint_data)
        self.assertLessEqual(result.nll_after, result.nll_before)
        self.assertAlmostEqual(calibrated_one_vs_rest_support(math.log(0.8), 1.0), 0.8)

    def test_calibration_refuses_without_positive_and_negative_no_read_examples(self):
        observations = (
            JointPathCalibrationObservation("candidate-positive", "writer-a", math.log(0.8), True, False),
            JointPathCalibrationObservation("candidate-negative", "writer-b", math.log(0.2), False, False),
            JointPathCalibrationObservation("no-read-negative", "writer-c", math.log(0.1), False, True),
        )
        with self.assertRaisesRegex(
            OperationRefusedError, "incomplete_no_read_calibration_supervision"
        ):
            fit_joint_path_temperature(observations, 3, 3, "e" * 64)

    def test_corpus_bound_calibration_observations_use_v2_supervision(self):
        records = (
            root_record(1, "development", "C△7"),
            root_record(2, "calibration", "G7"),
            root_record(4, "calibration", None),
            root_record(3, "sealed-evaluation", "•/•"),
        )
        calibration, observations = build_joint_path_observations(
            records,
            {
                records[1].sample_id: DecodeResult(
                    candidates=(
                        DecodedCandidate("G7", math.log(0.7)),
                        DecodedCandidate("C7", math.log(0.2)),
                    ),
                    no_read_log_score=math.log(0.1),
                ),
                records[2].sample_id: DecodeResult(
                    candidates=(DecodedCandidate("C", math.log(0.2)),),
                    no_read_log_score=math.log(0.8),
                ),
            },
        )
        self.assertEqual(len(calibration), 2)
        self.assertEqual(
            {(item.is_no_read_path, item.is_correct) for item in observations},
            {(False, False), (False, True), (True, False), (True, True)},
        )
        result = fit_joint_path_temperature(
            observations,
            len(calibration),
            2,
            "e" * 64,
        )
        self.assertEqual(result.calibration_observation_count, 5)

    def test_sealed_evaluation_selects_only_sealed_writer(self):
        records = corpus()
        sealed = records[2]
        report = evaluate_sealed_logits(
            records,
            {sealed.sample_id: perfect_logits(sealed.canonical_label)},
        )
        self.assertEqual(report.sample_count, 1)
        self.assertEqual(report.exact_active_factor_accuracy, 1.0)
        self.assertTrue(report.is_writer_disjoint_sealed_evaluation)
        self.assertTrue(report.logits_are_uncalibrated)

    def test_diagnostic_calibration_cannot_emit_swift_authority_artifact(self):
        result = fit_joint_path_temperature(
            (
                JointPathCalibrationObservation("cp", "a", math.log(0.8), True, False),
                JointPathCalibrationObservation("cn", "b", math.log(0.2), False, False),
                JointPathCalibrationObservation("np", "c", math.log(0.7), True, True),
                JointPathCalibrationObservation("nn", "d", math.log(0.1), False, True),
            ),
            4,
            4,
            "e" * 64,
        )
        with self.assertRaisesRegex(
            OperationRefusedError, "writer_disjoint_calibration_required"
        ):
            make_swift_calibration_artifact(
                result,
                "a" * 64,
                "b" * 64,
                "c" * 64,
                "pilot-calibration-001",
                "d" * 64,
            )

    def test_checkpoint_metadata_is_exact_and_blocks_no_read_authority(self):
        value = {
            "checkpoint_contract_version": CHECKPOINT_CONTRACT_VERSION,
            "feature_schema_version": "chord-ink-features-v1",
            "output_contract_version": OUTPUT_CONTRACT_VERSION,
            "model_identifier": "dual-view-v1",
            "model_config": {
                "trajectory_channels": 64,
                "raster_channels": 48,
                "fused_width": 192,
                "dropout": 0.1,
            },
            "training_config": {
                "seed": 17,
                "epochs": 2,
                "batch_size": 64,
                "learning_rate": 0.001,
                "weight_decay": 0.0001,
                "device": "cpu",
                "deterministic": True,
            },
            "development_records_sha256": "a" * 64,
            "development_sample_count": 3,
            "development_writer_count": 2,
            "epoch_losses": [1.0, 0.5],
            "has_negative_no_read_supervision": False,
        }
        metadata = CheckpointMetadata.from_mapping(value)
        self.assertEqual(metadata.model_identifier, "dual-view-v1")
        with self.assertRaisesRegex(
            OperationRefusedError, "negative_no_read_supervision_required"
        ):
            require_negative_no_read_supervision(metadata, "promotion")
        with self.assertRaisesRegex(ContractError, "unknown_checkpoint_field"):
            CheckpointMetadata.from_mapping({**value, "trusted": True})

    def test_missing_optional_dependency_fails_closed(self):
        with self.assertRaisesRegex(OperationRefusedError, "missing_optional_dependency"):
            require_optional_dependency("ichart_dependency_that_does_not_exist", "training")

    def test_training_config_refuses_nondeterminism_and_nan(self):
        with self.assertRaisesRegex(ContractError, "nondeterministic_training_refused"):
            TrainingConfig(deterministic=False).validate()
        with self.assertRaisesRegex(ContractError, "invalid_training_config"):
            TrainingConfig(learning_rate=math.nan).validate()

    def test_export_preflight_runs_before_optional_dependencies(self):
        class ContractModel:
            output_contract_version = OUTPUT_CONTRACT_VERSION
            output_head_names = HEAD_NAMES

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(OperationRefusedError, "unsupported_coreml_container"):
                export_uncalibrated_coreml(
                    ContractModel(),
                    root / "model.mlpackage",
                    root / "manifest.json",
                    "dual-view-v1",
                    "a" * 64,
                )

    def test_manifest_is_swift_compatible_and_binds_single_file_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "model.mlmodelc"
            path.mkdir()
            payload = b"not-a-real-model-but-stable-contract-bytes"
            (path / "model.mil").write_bytes(payload)
            manifest = build_swift_model_manifest(path, "dual-view-v1", "a" * 64)
        self.assertEqual(manifest["manifestContractVersion"], "chord-ink-model-manifest-v2")
        self.assertEqual(manifest["modelArtifactByteCount"], len(payload))
        self.assertEqual(manifest["trajectoryInput"]["shape"], [1, 256, 10])
        self.assertEqual(manifest["trajectoryInput"]["numericType"], "float32")
        self.assertEqual(manifest["trajectoryInput"]["layout"], "BSC")
        self.assertEqual(len(manifest["trajectoryInput"]["channels"]), 10)
        self.assertEqual(manifest["rasterInput"]["shape"], [1, 96, 256, 1])
        self.assertEqual(manifest["rasterInput"]["numericType"], "uint8")
        self.assertEqual(manifest["rasterInput"]["valueSemantics"], "binaryInkMask")
        self.assertEqual(
            tuple(head["name"] for head in manifest["outputHeads"]),
            HEAD_NAMES,
        )
        self.assertTrue(all(head["valueSemantics"] == "rawLogit" for head in manifest["outputHeads"]))

    def test_compiled_directory_fingerprint_matches_swift_framing_golden(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "model.mlmodelc"
            (path / "weights").mkdir(parents=True)
            (path / "model.mil").write_bytes(bytes((1, 2, 3)))
            (path / "weights" / "weight.bin").write_bytes(bytes((4, 5)))

            fingerprint = fingerprint_compiled_model(path)

        self.assertEqual(fingerprint.byte_count, 5)
        self.assertEqual(
            fingerprint.sha256,
            "3bae040a19029d3dd9595e36ac9b96f1c427005f668e050122bae5946caf3a21",
        )


if __name__ == "__main__":
    unittest.main()
