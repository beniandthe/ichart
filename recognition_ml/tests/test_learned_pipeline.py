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
    load_training_checkpoint,
    require_negative_no_read_supervision,
    require_bound_development_selection,
    save_training_checkpoint,
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
    COREML_EXPORT_PARITY_CONTRACT_VERSION,
    COREML_INFERENCE_COMPUTE_UNITS,
    CoreMLExportParityEvidence,
    CoreMLTrainingProvenance,
    _normalize_coreml_source_spec,
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
from ichart_recognition_ml.models.dual_view import (
    DUAL_VIEW_ARCHITECTURE_VERSION,
    DualViewChordModel,
    DualViewModelConfig,
)
from ichart_recognition_ml.models.factory import (
    DUAL_VIEW_MODEL_ARCHITECTURE_ID,
    MODEL_ARCHITECTURE_IDS,
    default_model_config,
    make_chord_model,
)
from ichart_recognition_ml.schema import FEATURE_SCHEMA, GROUND_TRUTH_NO_READ
from ichart_recognition_ml.selection_contract import (
    BOUND_DEVELOPMENT_SELECTION_AUTHORITY,
    UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY,
)
from ichart_recognition_ml.train_pipeline import (
    CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1,
    LOSS_NORMALIZATION_CONTRACT_VERSION,
    TRAJECTORY_AUGMENTATION_CONTRACT_VERSION,
    TrainingConfig,
    TrainingResult,
    _masked_factor_loss,
    build_trajectory_invariance_variants,
    normalize_head_weights_for_minibatches,
    training_head_weights,
    writer_balanced_head_weights,
)
from ichart_recognition_ml.features import (
    InkPoint,
    InkStroke,
    TrajectoryChannel,
    encode_trajectory,
)
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


def coreml_source_spec(coremltools):
    spec = coremltools.proto.Model_pb2.Model()
    float32 = coremltools.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    grayscale = coremltools.proto.FeatureTypes_pb2.ImageFeatureType.GRAYSCALE

    trajectory = spec.description.input.add()
    trajectory.name = "trajectory"
    trajectory.type.multiArrayType.shape.extend((1, 256, 10))
    trajectory.type.multiArrayType.dataType = float32
    raster = spec.description.input.add()
    raster.name = "raster"
    raster.type.imageType.width = 256
    raster.type.imageType.height = 96
    raster.type.imageType.colorSpace = grayscale
    for head in OUTPUT_HEADS:
        output = spec.description.output.add()
        output.name = head.name
        output.type.multiArrayType.dataType = float32
    return spec


class LearnedPipelineContractTests(unittest.TestCase):
    def test_dual_view_architecture_is_explicit_and_layout_preserving(self):
        try:
            torch = require_optional_dependency("torch", "training")
        except OperationRefusedError:
            self.skipTest("torch is not installed")
        self.assertEqual(
            DualViewChordModel.architecture_contract_version,
            DUAL_VIEW_ARCHITECTURE_VERSION,
        )
        with self.assertRaisesRegex(
            ContractError, "model_architecture_version_mismatch"
        ):
            DualViewModelConfig(architecture_contract_version="legacy-global-pool").validate()

        torch.manual_seed(17)
        model = DualViewChordModel().eval()
        trajectory = torch.zeros(2, *FEATURE_SCHEMA.trajectory_shape)
        raster = torch.zeros(
            2,
            FEATURE_SCHEMA.raster_height,
            FEATURE_SCHEMA.raster_width,
            1,
        )
        raster[0, 24:72, 18:26, 0] = 1
        raster[1, 24:72, -26:-18, 0] = 1
        with torch.no_grad():
            output = model(trajectory, raster)
        self.assertTrue(
            any(
                not torch.allclose(output[name][0], output[name][1])
                for name in HEAD_NAMES
            ),
            "left/right glyph placement must survive the raster encoder",
        )

    def test_dual_view_rejects_mismatched_view_batches(self):
        try:
            torch = require_optional_dependency("torch", "training")
        except OperationRefusedError:
            self.skipTest("torch is not installed")
        model = DualViewChordModel()
        trajectory = torch.zeros(2, *FEATURE_SCHEMA.trajectory_shape)
        raster = torch.zeros(
            1,
            FEATURE_SCHEMA.raster_height,
            FEATURE_SCHEMA.raster_width,
            1,
        )
        with self.assertRaisesRegex(ValueError, "batch dimensions must match"):
            model(trajectory, raster)

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
            "model_architecture_id": DUAL_VIEW_MODEL_ARCHITECTURE_ID,
            "model_config": {
                "trajectory_channels": 64,
                "raster_channels": 48,
                "fused_width": 192,
                "dropout": 0.1,
                "architecture_contract_version": DUAL_VIEW_ARCHITECTURE_VERSION,
            },
            "training_config": {
                "seed": 17,
                "epochs": 2,
                "batch_size": 64,
                "learning_rate": 0.001,
                "weight_decay": 0.0001,
                "device": "cpu",
                "deterministic": True,
                "writer_balanced_loss": True,
                "categorical_class_reweighting": "none",
                "loss_normalization_contract_version": (
                    LOSS_NORMALIZATION_CONTRACT_VERSION
                ),
                "trajectory_augmentation_contract_version": (
                    TRAJECTORY_AUGMENTATION_CONTRACT_VERSION
                ),
            },
            "development_records_sha256": "a" * 64,
            "development_sample_count": 3,
            "development_writer_count": 2,
            "development_selection_authority": (
                UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
            ),
            "development_selection_report_sha256": None,
            "epoch_losses": [1.0, 0.5],
            "has_negative_no_read_supervision": False,
        }
        metadata = CheckpointMetadata.from_mapping(value)
        self.assertEqual(metadata.model_identifier, "dual-view-v1")
        with self.assertRaisesRegex(
            OperationRefusedError, "negative_no_read_supervision_required"
        ):
            require_negative_no_read_supervision(metadata, "promotion")
        with self.assertRaisesRegex(
            OperationRefusedError, "bound_development_selection_required"
        ):
            require_bound_development_selection(metadata, "promotion")

        selected = CheckpointMetadata.from_mapping(
            {
                **value,
                "development_selection_authority": (
                    BOUND_DEVELOPMENT_SELECTION_AUTHORITY
                ),
                "development_selection_report_sha256": "f" * 64,
                "has_negative_no_read_supervision": True,
            }
        )
        require_bound_development_selection(selected, "promotion")
        require_negative_no_read_supervision(selected, "promotion")
        with self.assertRaisesRegex(ContractError, "unknown_checkpoint_field"):
            CheckpointMetadata.from_mapping({**value, "trusted": True})

    def test_every_selectable_architecture_round_trips_its_exact_checkpoint(self):
        try:
            require_optional_dependency("torch", "training")
        except OperationRefusedError:
            self.skipTest("torch is not installed")
        for architecture_id in MODEL_ARCHITECTURE_IDS:
            with self.subTest(architecture_id=architecture_id):
                config = default_model_config(architecture_id, 17)
                training_config = TrainingConfig(epochs=1)
                result = TrainingResult(
                    model=make_chord_model(architecture_id, config),
                    epoch_losses=(1.0,),
                    development_sample_ids=("sample-1",),
                    development_writer_hashes=("a" * 64,),
                    seed=17,
                    model_architecture_id=architecture_id,
                    model_config=config,
                    training_config=training_config,
                    development_records_sha256="b" * 64,
                    development_selection_authority=(
                        UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
                    ),
                    development_selection_report_sha256=None,
                    has_negative_no_read_supervision=True,
                )
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "checkpoint.pt"
                    save_training_checkpoint(result, path, "candidate-001")
                    loaded = load_training_checkpoint(path)
                self.assertEqual(
                    loaded.metadata.model_architecture_id,
                    architecture_id,
                )
                self.assertEqual(loaded.metadata.model_config, config)
                self.assertIs(type(loaded.model), type(result.model))

    def test_missing_optional_dependency_fails_closed(self):
        with self.assertRaisesRegex(OperationRefusedError, "missing_optional_dependency"):
            require_optional_dependency("ichart_dependency_that_does_not_exist", "training")

    def test_training_config_refuses_nondeterminism_and_nan(self):
        with self.assertRaisesRegex(ContractError, "nondeterministic_training_refused"):
            TrainingConfig(deterministic=False).validate()
        with self.assertRaisesRegex(ContractError, "invalid_training_config"):
            TrainingConfig(learning_rate=math.nan).validate()
        with self.assertRaisesRegex(
            ContractError, "writer_balanced_training_required"
        ):
            TrainingConfig(writer_balanced_loss=False).validate()
        with self.assertRaisesRegex(ContractError, "invalid_training_config"):
            TrainingConfig(categorical_class_reweighting="unreviewed").validate()
        with self.assertRaisesRegex(
            ContractError, "loss_normalization_version_mismatch"
        ):
            TrainingConfig(
                loss_normalization_contract_version="batch-local-v0"
            ).validate()

    def test_writer_balanced_loss_gives_each_active_writer_equal_mass_per_head(self):
        try:
            numpy = require_optional_dependency("numpy", "training")
        except OperationRefusedError:
            self.skipTest("numpy is not installed")
        first = root_record(1, "development", "C")
        records = (
            first,
            CorpusRecord(
                **{
                    **root_record(4, "development", "D").__dict__,
                    "writer_id_hash": first.writer_id_hash,
                }
            ),
            CorpusRecord(
                **{
                    **root_record(7, "development", "E").__dict__,
                    "writer_id_hash": first.writer_id_hash,
                }
            ),
            root_record(10, "development", "F"),
        )
        active = {
            head.name: numpy.ones(len(records), dtype=numpy.bool_)
            for head in OUTPUT_HEADS
        }
        weights = writer_balanced_head_weights(records, active, numpy)
        root_weights = weights["root_letter"]
        self.assertAlmostEqual(float(root_weights[:3].sum()), 1.0)
        self.assertAlmostEqual(float(root_weights[3:].sum()), 1.0)
        self.assertAlmostEqual(float(root_weights[0]), 1.0 / 3.0)

    def test_augmentation_variants_split_one_source_capture_weight(self):
        try:
            numpy = require_optional_dependency("numpy", "training")
        except OperationRefusedError:
            self.skipTest("numpy is not installed")
        first = root_record(1, "development", "C")
        records = tuple(
            CorpusRecord(
                **{
                    **root_record(index, "development", "C").__dict__,
                    "writer_id_hash": first.writer_id_hash,
                }
            )
            for index in (1, 4, 7, 10, 13)
        )
        active = {
            head.name: numpy.ones(len(records), dtype=numpy.bool_)
            for head in OUTPUT_HEADS
        }
        weights = writer_balanced_head_weights(
            records,
            active,
            numpy,
            source_indices=(0, 0, 0, 1, 1),
        )["root_letter"]
        self.assertAlmostEqual(float(weights[:3].sum()), 0.5)
        self.assertAlmostEqual(float(weights[3:].sum()), 0.5)
        self.assertAlmostEqual(float(weights.sum()), 1.0)

    def test_categorical_class_reweighting_is_explicit_and_does_not_fake_bernoulli_balance(self):
        try:
            numpy = require_optional_dependency("numpy", "training")
        except OperationRefusedError:
            self.skipTest("numpy is not installed")
        first = root_record(1, "development", "C")
        records = tuple(
            CorpusRecord(
                **{
                    **root_record(index, "development", label).__dict__,
                    "writer_id_hash": first.writer_id_hash,
                }
            )
            for index, label in ((1, "C"), (4, "C"), (7, "C"), (10, "G"))
        )
        active = {
            head.name: numpy.ones(len(records), dtype=numpy.bool_)
            for head in OUTPUT_HEADS
        }
        targets = {
            head.name: (
                numpy.zeros(
                    (len(records), len(head.labels)), dtype=numpy.float32
                )
                if head.is_independent_bernoulli
                else numpy.zeros(len(records), dtype=numpy.int64)
            )
            for head in OUTPUT_HEADS
        }
        targets["root_letter"][-1] = 6
        writer_only = writer_balanced_head_weights(records, active, numpy)
        adjusted = training_head_weights(
            records,
            targets,
            active,
            CATEGORICAL_CLASS_REWEIGHTING_INVERSE_FREQUENCY_V1,
            numpy,
        )
        self.assertAlmostEqual(
            float(adjusted["root_letter"][:3].sum()),
            float(adjusted["root_letter"][3]),
        )
        numpy.testing.assert_array_equal(
            adjusted["alteration_logits"],
            writer_only["alteration_logits"],
        )

    def test_minibatch_weighting_reconstructs_the_global_weighted_objective(self):
        try:
            numpy = require_optional_dependency("numpy", "training")
            torch = require_optional_dependency("torch", "training")
        except OperationRefusedError:
            self.skipTest("numpy and torch are required")
        raw = {
            head.name: numpy.zeros(4, dtype=numpy.float32)
            for head in OUTPUT_HEADS
        }
        raw["validity"] = numpy.asarray(
            [0.25, 0.25, 0.25, 1.25], dtype=numpy.float32
        )
        normalized, supervised = normalize_head_weights_for_minibatches(
            raw, 4, numpy
        )
        self.assertEqual(supervised, ("validity",))
        self.assertAlmostEqual(float(normalized["validity"].sum()), 4.0)

        outputs = {
            "validity": torch.tensor(
                [[5.0, 0.0], [0.0, 5.0], [2.0, 0.0], [0.0, 2.0]]
            )
        }
        targets = {"validity": torch.tensor([0, 0, 1, 1])}
        active = {"validity": torch.tensor([True, True, True, True])}
        weights = {"validity": torch.from_numpy(normalized["validity"])}
        full = _masked_factor_loss(
            outputs, targets, active, weights, supervised, 4, torch
        )
        parts = []
        for start, stop in ((0, 2), (2, 4)):
            parts.append(
                _masked_factor_loss(
                    {"validity": outputs["validity"][start:stop]},
                    {"validity": targets["validity"][start:stop]},
                    {"validity": active["validity"][start:stop]},
                    {"validity": weights["validity"][start:stop]},
                    supervised,
                    stop - start,
                    torch,
                )
            )
        combined = (parts[0] * 2 + parts[1] * 2) / 4
        self.assertAlmostEqual(float(full), float(combined), places=6)

    def test_trajectory_augmentation_changes_order_and_direction_not_geometry(self):
        try:
            numpy = require_optional_dependency("numpy", "training")
        except OperationRefusedError:
            self.skipTest("numpy is not installed")
        encoded = encode_trajectory(
            (
                InkStroke((InkPoint(0, 0, 0), InkPoint(10, 0, 0.1))),
                InkStroke((InkPoint(30, 0, 0.3), InkPoint(30, 10, 0.4))),
            )
        )
        source = numpy.frombuffer(encoded.to_bytes(), dtype="<f4").copy().reshape(
            1, 256, 10
        )
        variants = build_trajectory_invariance_variants(source, numpy)
        self.assertEqual(len(variants), 2)
        valid_channel = int(TrajectoryChannel.VALID)
        timing_channel = int(TrajectoryChannel.TIMING_AVAILABLE)
        source_count = int((source[0, :, valid_channel] > 0.5).sum())
        for variant in variants:
            self.assertEqual(
                int((variant[0, :, valid_channel] > 0.5).sum()), source_count
            )
            self.assertTrue((variant[0, :, timing_channel] == 0).all())
            source_points = sorted(
                tuple(row)
                for row in source[0, :source_count, :2].tolist()
            )
            variant_points = sorted(
                tuple(row)
                for row in variant[0, :source_count, :2].tolist()
            )
            self.assertEqual(variant_points, source_points)
        self.assertFalse(numpy.array_equal(variants[0], source))
        self.assertFalse(numpy.array_equal(variants[1], source))

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

    def test_export_refuses_missing_or_mismatched_training_provenance(self):
        class ContractModel:
            output_contract_version = OUTPUT_CONTRACT_VERSION
            output_head_names = HEAD_NAMES
            model_architecture_id = DUAL_VIEW_MODEL_ARCHITECTURE_ID

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ContractError, "missing_training_provenance"):
                export_uncalibrated_coreml(
                    ContractModel(),
                    root / "missing.mlmodelc",
                    root / "missing.manifest.json",
                    "dual-view-v1",
                    "a" * 64,
                )
            with self.assertRaisesRegex(ContractError, "model_architecture_mismatch"):
                export_uncalibrated_coreml(
                    ContractModel(),
                    root / "mismatch.mlmodelc",
                    root / "mismatch.manifest.json",
                    "dual-view-v1",
                    "a" * 64,
                    CoreMLTrainingProvenance(
                        checkpoint_contract_version=CHECKPOINT_CONTRACT_VERSION,
                        checkpoint_artifact_sha256="b" * 64,
                        checkpoint_artifact_byte_count=1,
                        model_architecture_id="raster-only-v2-layout-preserving",
                        development_records_sha256="c" * 64,
                        development_sample_count=1,
                        development_writer_count=1,
                        development_selection_authority=(
                            UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
                        ),
                        development_selection_report_sha256=None,
                    ),
                )

    def test_source_coreml_contract_declares_converter_omitted_output_shapes(self):
        try:
            coremltools = require_optional_dependency("coremltools", "export")
        except OperationRefusedError:
            self.skipTest("coremltools is not installed")
        spec = coreml_source_spec(coremltools)

        _normalize_coreml_source_spec(spec, coremltools)

        outputs = {feature.name: feature for feature in spec.description.output}
        self.assertEqual(
            {name: tuple(feature.type.multiArrayType.shape) for name, feature in outputs.items()},
            {head.name: head.shape for head in OUTPUT_HEADS},
        )

    def test_source_coreml_contract_rejects_nonempty_wrong_output_shape(self):
        try:
            coremltools = require_optional_dependency("coremltools", "export")
        except OperationRefusedError:
            self.skipTest("coremltools is not installed")
        spec = coreml_source_spec(coremltools)
        spec.description.output[0].type.multiArrayType.shape.extend((1, 99))

        with self.assertRaisesRegex(
            OperationRefusedError, "coreml_source_interface_mismatch"
        ):
            _normalize_coreml_source_spec(spec, coremltools)

    def test_manifest_is_swift_compatible_and_binds_single_file_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "model.mlmodelc"
            path.mkdir()
            payload = b"not-a-real-model-but-stable-contract-bytes"
            (path / "model.mil").write_bytes(payload)
            manifest = build_swift_model_manifest(
                path,
                "dual-view-v1",
                "a" * 64,
                CoreMLExportParityEvidence(
                    contract_version=COREML_EXPORT_PARITY_CONTRACT_VERSION,
                    probe_count=2,
                    maximum_absolute_error=0.0,
                    inference_compute_units=COREML_INFERENCE_COMPUTE_UNITS,
                ),
                CoreMLTrainingProvenance(
                    checkpoint_contract_version=CHECKPOINT_CONTRACT_VERSION,
                    checkpoint_artifact_sha256="b" * 64,
                    checkpoint_artifact_byte_count=1234,
                    model_architecture_id=DUAL_VIEW_MODEL_ARCHITECTURE_ID,
                    development_records_sha256="c" * 64,
                    development_sample_count=12,
                    development_writer_count=4,
                    development_selection_authority=(
                        UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
                    ),
                    development_selection_report_sha256=None,
                ),
            )
        self.assertEqual(manifest["manifestContractVersion"], "chord-ink-model-manifest-v4")
        self.assertEqual(
            manifest["trainingProvenance"],
            {
                "checkpointContractVersion": CHECKPOINT_CONTRACT_VERSION,
                "checkpointArtifactSHA256": "b" * 64,
                "checkpointArtifactByteCount": 1234,
                "modelArchitectureID": DUAL_VIEW_MODEL_ARCHITECTURE_ID,
                "developmentRecordsSHA256": "c" * 64,
                "developmentSampleCount": 12,
                "developmentWriterCount": 4,
                "developmentSelectionAuthority": (
                    UNBOUND_DEVELOPMENT_SELECTION_AUTHORITY
                ),
                "developmentSelectionReportSHA256": None,
            },
        )
        self.assertEqual(manifest["inferenceComputeUnits"], "cpuOnly")
        self.assertEqual(
            manifest["exportParity"],
            {
                "contractVersion": "chord-ink-coreml-export-parity-v1",
                "probeCount": 2,
                "maximumAbsoluteError": 0.0,
            },
        )
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
