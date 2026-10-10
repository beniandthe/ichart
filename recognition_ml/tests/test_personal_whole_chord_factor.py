"""Synthetic contract tests only; no UJI/private source, fitting, or inference."""

import copy
from pathlib import Path
import tempfile
import unittest

import numpy as np
import torch

from ichart_recognition_ml.features import InkPoint, InkStroke, TrajectoryChannel
from ichart_recognition_ml.models.output_contract import HEAD_BY_NAME, OUTPUT_HEADS, factorize_canonical_label
from ichart_recognition_ml.research import personal_whole_chord_factor as factor
from ichart_recognition_ml.research import personal_whole_chord_source as source


def strokes():
    return (
        InkStroke((InkPoint(0, 0), InkPoint(5, 8), InkPoint(9, 0))),
        InkStroke((InkPoint(13, 2), InkPoint(18, 2))),
    )


def input_row(identity="row", value=None):
    value = strokes() if value is None else value
    return source.WholeChordPredictionInput(
        sample_id=identity,
        input_sha256=source.canonical_strokes_sha256(value),
        strokes=tuple(value),
    )


def perfect_logits(label, magnitude=9.0):
    target = factorize_canonical_label(label)
    result = {}
    for head in OUTPUT_HEADS:
        if head.is_independent_bernoulli:
            result[head.name] = [magnitude if selected else -magnitude
                                 for selected in target.values[head.name]]
        else:
            selected = int(target.values[head.name])
            result[head.name] = [magnitude if index == selected else -magnitude
                                 for index in range(len(head.labels))]
    return result


class WholeChordFactorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def test_fixed_scope_counts_configuration_and_complete_ten_head_shapes(self):
        self.assertEqual(factor.TRAINING_EXAMPLE_COUNT, 21_504)
        self.assertEqual(factor.DEVELOPMENT_EXAMPLE_COUNT, 5_376)
        self.assertEqual((factor.SEED, factor.EPOCHS, factor.BATCH_SIZE), (29, 30, 128))
        self.assertEqual(set(factor.TRAINED_HEADS) | set(factor.INACTIVE_HEADS),
                         {head.name for head in OUTPUT_HEADS})
        model, _ = factor.initialized_model()
        batch = factor.encode_inputs((input_row(),))
        output = model(batch.trajectory.float(), batch.raster.float() / 255.0)
        self.assertEqual(set(output), {head.name for head in OUTPUT_HEADS})
        for head in OUTPUT_HEADS:
            self.assertEqual(tuple(output[head.name].shape), (1, len(head.labels)))

    def test_conditional_targets_have_only_covered_active_heads_and_reject_slash_or_alteration(self):
        targets = factor.conditional_targets(("C", "Db-13"))
        self.assertEqual(set(targets), set(factor.TRAINED_HEADS))
        self.assertTrue(torch.equal(targets["alteration_logits"], torch.zeros(2, 7)))
        self.assertTrue(torch.equal(targets["slash_presence"], torch.zeros(2, dtype=torch.long)))
        for label in ("C7(b9)", "C/D"):
            with self.assertRaisesRegex(ValueError, "outside this fixed experiment"):
                factor.conditional_targets((label,))

    def test_loss_backpropagates_shared_and_six_active_heads_but_not_inactive_heads(self):
        model, initial = factor.initialized_model()
        batch = factor.encode_inputs((input_row("a"), input_row("b")))
        optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
        optimizer.zero_grad(set_to_none=True)
        output = model(batch.trajectory.float(), batch.raster.float() / 255.0)
        loss, components = factor.conditional_factor_loss(
            output, factor.conditional_targets(("C", "Db-13"))
        )
        loss.backward()
        self.assertTrue(torch.isfinite(loss))
        self.assertEqual(set(components), set(factor.TRAINED_HEADS))
        for name, parameter in model.named_parameters():
            if any(name.startswith(f"heads.{head}.") for head in factor.INACTIVE_HEADS):
                self.assertIsNone(parameter.grad, name)
            elif any(name.startswith(f"heads.{head}.") for head in factor.TRAINED_HEADS):
                self.assertIsNotNone(parameter.grad, name)
        optimizer.step()
        self.assertEqual(
            factor._head_state_digest(model.state_dict(), factor.INACTIVE_HEADS),
            initial["inactiveHeadSHA256"],
        )

    def test_frozen_code_map_includes_protocol_all_four_modules_tests_and_import_initializers(self):
        code, _ = factor._code_snapshot()
        self.assertEqual(set(code), set(factor.CODE_PATHS))
        for required in (
            factor.PROTOCOL_PATH, factor.SOURCE_MODULE_PATH, factor.SOURCE_TEST_PATH,
            factor.MODULE_PATH, factor.TEST_PATH, factor.ATOMIC_CONTROL_PATH,
            factor.ATOMIC_CONTROL_TEST_PATH, factor.SCORING_PATH, factor.SCORING_TEST_PATH,
            "recognition_ml/ichart_recognition_ml/__init__.py",
            "recognition_ml/ichart_recognition_ml/models/__init__.py",
            "recognition_ml/ichart_recognition_ml/research/__init__.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
        ):
            self.assertIn(required, code)
        self.assertEqual(code[factor.PROTOCOL_PATH], factor._sha256(
            (factor._repo_root() / factor.PROTOCOL_PATH).read_bytes()
        ))

    def test_conditional_identity_ignores_raw_validity_and_repeat_without_mutating_logits(self):
        raw = perfect_logits("Bb-11")
        raw["validity"] = [40.0, -40.0]
        raw["kind"] = [-40.0, 40.0]
        before = copy.deepcopy(raw)
        self.assertEqual(factor.conditional_identity(raw), "Bb-11")
        projected = factor.conditional_valid_rooted_logits(raw)
        self.assertEqual(projected.values["validity"], (0.0, 0.0))
        self.assertEqual(projected.values["kind"][HEAD_BY_NAME["kind"].labels.index("rooted")], 0.0)
        self.assertEqual(raw, before)

    def test_feature_batch_binds_full_strokes_and_keeps_absent_timing_zero(self):
        row = input_row()
        before = copy.deepcopy(row)
        batch = factor.encode_inputs((row,))
        self.assertEqual(tuple(batch.trajectory.shape), (1, 1, 256, 10))
        self.assertEqual(tuple(batch.raster.shape), (1, 96, 256, 1))
        self.assertEqual(batch.input_hashes, (row.input_sha256,))
        self.assertTrue(torch.equal(batch.trajectory[0, 0, :, int(TrajectoryChannel.NORMALIZED_DELTA_TIME)],
                                    torch.zeros(256)))
        self.assertTrue(torch.equal(batch.trajectory[0, 0, :, int(TrajectoryChannel.TIMING_AVAILABLE)],
                                    torch.zeros(256)))
        self.assertEqual(row, before)
        corrupt = source.WholeChordPredictionInput(row.sample_id, "0" * 64, row.strokes)
        with self.assertRaisesRegex(ValueError, "does not bind"):
            factor.encode_inputs((corrupt,))

    def test_prediction_retains_feature_failure_and_success_raw_outputs(self):
        valid = input_row("valid")
        too_many = tuple(InkStroke((InkPoint(float(index), 0),)) for index in range(513))
        invalid = input_row("invalid", too_many)
        encoding = factor.encode_prediction_inputs((valid, invalid))
        self.assertEqual(len(encoding.sample_ids), 2)
        self.assertEqual(set(encoding.failures), {"invalid"})
        self.assertIsNotNone(encoding.successful)
        raw = perfect_logits("C")
        outputs = {head.name: np.asarray([raw[head.name]], dtype=np.float32) for head in OUTPUT_HEADS}
        rows = factor.prediction_rows(encoding, outputs)
        indexed = {row["sampleID"]: row for row in rows}
        self.assertIsNone(indexed["valid"]["inputFailure"])
        self.assertEqual(set(indexed["valid"]["logits"]), {head.name for head in OUTPUT_HEADS})
        self.assertEqual(indexed["valid"]["conditionalCanonicalLabel"], "C")
        self.assertIsNotNone(indexed["invalid"]["inputFailure"])
        self.assertIsNone(indexed["invalid"]["logits"])
        self.assertEqual(indexed["invalid"]["inputSHA256"], invalid.input_sha256)

    def test_checkpoint_roundtrip_binds_code_protocol_plan_and_truth(self):
        model, initial = factor.initialized_model()
        code = {"synthetic": "a" * 64}
        payload = factor.checkpoint_bytes(
            model, code=code, protocol_sha256="b" * 64,
            source_plan_version=source.VERSION, truth_sha256="c" * 64,
        )
        loaded = factor.load_checkpoint(
            payload, code=code, protocol_sha256="b" * 64,
            source_plan_version=source.VERSION, truth_sha256="c" * 64,
        )
        self.assertEqual(factor._state_digest(loaded.state_dict()), initial["stateSHA256"])
        with self.assertRaisesRegex(ValueError, "binding differs"):
            factor.load_checkpoint(
                payload, code=code, protocol_sha256="d" * 64,
                source_plan_version=source.VERSION, truth_sha256="c" * 64,
            )

    def test_incomplete_training_and_reused_output_are_refused_before_updates(self):
        model, _ = factor.initialized_model()
        batch = factor.encode_inputs((input_row(),))
        before = factor._state_digest(model.state_dict())
        with self.assertRaisesRegex(ValueError, "complete fixed"):
            factor.train_model(model, batch, factor.conditional_targets(("C",)))
        self.assertEqual(factor._state_digest(model.state_dict()), before)
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            output = Path(directory) / "new"
            factor._new_output_directory(output)
            with self.assertRaises(ValueError):
                factor._new_output_directory(output)


if __name__ == "__main__":
    unittest.main()
