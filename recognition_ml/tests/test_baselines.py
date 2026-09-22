import unittest

from ichart_recognition_ml.baselines import (
    DTWBaselineConfig,
    DevelopmentTrajectoryTemplate,
    ExternalLegacyPrediction,
    ExternalLegacyRuleAdapter,
    MultiWriterDTWBaseline,
    factor_logits_for_external_prediction,
    factor_logits_from_batched_raw_heads,
)
from ichart_recognition_ml.decode import decode_factor_logits
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.features import TRAJECTORY_CHANNEL_COUNT, TrajectoryChannel
from ichart_recognition_ml.models.ablations import (
    RasterOnlyChordModel,
    RasterOnlyModelConfig,
    TrajectoryOnlyChordModel,
    TrajectoryOnlyModelConfig,
)
from ichart_recognition_ml.models.output_contract import (
    HEAD_NAMES,
    OUTPUT_CONTRACT_VERSION,
    OUTPUT_HEADS,
)
from ichart_recognition_ml.schema import FEATURE_SCHEMA


def trajectory(*xs):
    values = [0.0] * FEATURE_SCHEMA.trajectory_value_count
    for sample_index, x in enumerate(xs):
        offset = sample_index * TRAJECTORY_CHANNEL_COUNT
        values[offset + int(TrajectoryChannel.X)] = float(x)
        values[offset + int(TrajectoryChannel.DELTA_X)] = (
            0.0 if sample_index == 0 else float(x - xs[sample_index - 1])
        )
        values[offset + int(TrajectoryChannel.ARC_STEP)] = abs(
            values[offset + int(TrajectoryChannel.DELTA_X)]
        )
        values[offset + int(TrajectoryChannel.STROKE_START)] = (
            1.0 if sample_index == 0 else 0.0
        )
        values[offset + int(TrajectoryChannel.STROKE_END)] = (
            1.0 if sample_index == len(xs) - 1 else 0.0
        )
        values[offset + int(TrajectoryChannel.VALID)] = 1.0
    return tuple(values)


def template(index, writer_digit, label, values, split="development"):
    return DevelopmentTrajectoryTemplate(
        sample_id=f"sample-{index}",
        writer_id_hash=writer_digit * 64,
        split=split,
        canonical_label=label,
        trajectory_values=values,
    )


class ExternalBaselineContractTests(unittest.TestCase):
    def test_external_prediction_adapter_emits_same_logits_and_decoder_contract(self):
        adapter = ExternalLegacyRuleAdapter()
        outputs = adapter.adapt(
            (
                ExternalLegacyPrediction("one", "C7(b9)/E"),
                ExternalLegacyPrediction("two", None),
            )
        )
        self.assertFalse(adapter.is_writer_independent_claim_eligible)
        self.assertFalse(adapter.is_trust_eligible)
        self.assertEqual(tuple(outputs["one"].values), HEAD_NAMES)
        self.assertEqual(outputs["one"].contract_version, OUTPUT_CONTRACT_VERSION)
        decoded = decode_factor_logits(outputs["one"])
        self.assertEqual(decoded.candidates[0].canonical_label, "C7(b9)/E")
        no_read = decode_factor_logits(outputs["two"])
        self.assertGreater(no_read.no_read_log_score, decoded.no_read_log_score)
        with self.assertRaisesRegex(ContractError, "invalid_model_output"):
            factor_logits_from_batched_raw_heads(())

    def test_external_adapter_refuses_empty_duplicate_and_noncanonical_input(self):
        adapter = ExternalLegacyRuleAdapter()
        with self.assertRaisesRegex(
            OperationRefusedError, "external_legacy_predictions_required"
        ):
            adapter.adapt(())
        with self.assertRaisesRegex(ContractError, "duplicate_external_sample_id"):
            adapter.adapt(
                (
                    ExternalLegacyPrediction("same", "C"),
                    ExternalLegacyPrediction("same", "D"),
                )
            )
        with self.assertRaisesRegex(ContractError, "invalid_external_canonical_label"):
            factor_logits_for_external_prediction("Cmaj7")
        with self.assertRaises(TypeError):
            ExternalLegacyRuleAdapter(is_trust_eligible=True)

    def test_dtw_is_unavailable_without_two_development_writers_per_label(self):
        with self.assertRaisesRegex(
            OperationRefusedError, "development_writer_templates_required"
        ):
            MultiWriterDTWBaseline.fit(())
        with self.assertRaisesRegex(ContractError, "invalid_dtw_template"):
            MultiWriterDTWBaseline.fit((object(),))
        with self.assertRaisesRegex(
            OperationRefusedError, "insufficient_development_writers_per_label"
        ):
            MultiWriterDTWBaseline.fit((template(1, "a", "C", trajectory(0, 1)),))
        with self.assertRaisesRegex(
            OperationRefusedError, "nondevelopment_dtw_template_refused"
        ):
            template(2, "b", "C", trajectory(0, 1), split="calibration")

    def test_dtw_uses_two_development_writers_and_feeds_shared_decoder(self):
        baseline = MultiWriterDTWBaseline.fit(
            (
                template(1, "a", "C", trajectory(0.0, 0.1, 0.2)),
                template(2, "b", "C", trajectory(0.0, 0.2, 0.3)),
                template(3, "a", "G7", trajectory(0.0, 0.8, 1.0)),
                template(4, "b", "G7", trajectory(0.0, 0.9, 1.0)),
            )
        )
        before = baseline.templates
        logits = baseline.predict(trajectory(0.0, 0.85, 1.0))
        self.assertEqual(decode_factor_logits(logits).candidates[0].canonical_label, "G7")
        self.assertEqual(baseline.templates, before)
        self.assertFalse(baseline.is_calibrated)
        self.assertFalse(baseline.is_trust_eligible)

    def test_dtw_refuses_nonfrozen_config_and_invalid_padding(self):
        with self.assertRaisesRegex(ContractError, "nonfrozen_dtw_channels"):
            DTWBaselineConfig(channel_indices=(0, 1)).validate()
        with self.assertRaisesRegex(ContractError, "nonfrozen_dtw_logit_magnitude"):
            DTWBaselineConfig(logit_magnitude=7.0).validate()
        invalid = list(trajectory(0.0))
        padding_offset = TRAJECTORY_CHANNEL_COUNT
        invalid[padding_offset] = 1.0
        with self.assertRaisesRegex(ContractError, "nonzero_trajectory_padding"):
            template(1, "a", "C", invalid)


class AblationConfigTests(unittest.TestCase):
    def test_ablation_configs_fail_closed(self):
        with self.assertRaisesRegex(ContractError, "invalid_ablation_config"):
            TrajectoryOnlyModelConfig(channels=0).validate()
        with self.assertRaisesRegex(ContractError, "ablation_contract_version_mismatch"):
            RasterOnlyModelConfig(contract_version="wrong").validate()

    def test_ablation_classes_declare_exact_common_output_contract(self):
        for model_type in (TrajectoryOnlyChordModel, RasterOnlyChordModel):
            self.assertEqual(model_type.output_contract_version, OUTPUT_CONTRACT_VERSION)
            self.assertEqual(model_type.output_head_names, HEAD_NAMES)


class LearnedAblationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import torch
        except ImportError as error:
            raise unittest.SkipTest(str(error))
        cls.torch = torch

    def inputs(self, batch_size=2):
        torch = self.torch
        trajectory_input = torch.randn(
            batch_size, *FEATURE_SCHEMA.trajectory_shape, dtype=torch.float32
        )
        raster_input = torch.randn(
            batch_size,
            FEATURE_SCHEMA.raster_height,
            FEATURE_SCHEMA.raster_width,
            1,
            dtype=torch.float32,
        )
        return trajectory_input, raster_input

    def assert_frozen_output(self, output, batch_size):
        self.assertEqual(tuple(output), HEAD_NAMES)
        for head in OUTPUT_HEADS:
            self.assertEqual(tuple(output[head.name].shape), (batch_size, len(head.labels)))
        logits = factor_logits_from_batched_raw_heads(output, 0)
        self.assertEqual(logits.contract_version, OUTPUT_CONTRACT_VERSION)
        decode_factor_logits(logits)

    def test_trajectory_ablation_is_deterministic_and_ignores_raster(self):
        torch = self.torch
        first = TrajectoryOnlyChordModel().eval()
        second = TrajectoryOnlyChordModel().eval()
        trajectory_input, raster_input = self.inputs()
        with torch.no_grad():
            first_output = first(trajectory_input, raster_input)
            second_output = second(trajectory_input, raster_input * 100.0 + 7.0)
        self.assert_frozen_output(first_output, 2)
        for name in HEAD_NAMES:
            self.assertTrue(torch.equal(first_output[name], second_output[name]))

    def test_raster_ablation_is_deterministic_and_ignores_trajectory(self):
        torch = self.torch
        first = RasterOnlyChordModel().eval()
        second = RasterOnlyChordModel().eval()
        trajectory_input, raster_input = self.inputs()
        with torch.no_grad():
            first_output = first(trajectory_input, raster_input)
            second_output = second(trajectory_input * 100.0 + 7.0, raster_input)
        self.assert_frozen_output(first_output, 2)
        for name in HEAD_NAMES:
            self.assertTrue(torch.equal(first_output[name], second_output[name]))

    def test_ablation_batches_must_match(self):
        model = TrajectoryOnlyChordModel()
        trajectory_input, raster_input = self.inputs()
        with self.assertRaisesRegex(ValueError, "batch dimensions must match"):
            model(trajectory_input, raster_input[:1])


if __name__ == "__main__":
    unittest.main()
