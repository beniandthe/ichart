"""Synthetic producer checks only; no public/private corpus or actual fit."""

import copy
import hashlib
from pathlib import Path
import tempfile
import unittest

import numpy as np
import torch

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.research.uji_personal import Sample
from ichart_recognition_ml.research import personal_dual_view as previous
from ichart_recognition_ml.research import personal_synchronized_augmentation as augmentation
from ichart_recognition_ml.research import personal_synchronized_dual_view as experiment
from ichart_recognition_ml.research import personal_synchronized_dual_view_scoring as scoring


class SynchronizedProducerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)

    def samples(self):
        return tuple(Sample("trn_toy_W01", session, label,
            (InkStroke((InkPoint(-3, 1), InkPoint(0, 5), InkPoint(4, -2))),
             InkStroke((InkPoint(7, 3),)))) for session, label in ((1, "A"), (2, "B")))

    def test_two_arms_start_at_exact_original_seed29_tensors(self):
        models, initial = experiment.initialized_models()
        self.assertEqual(set(models), {"rasterOnly", "dual"})
        self.assertEqual(initial, scoring.INITIAL_STATE)
        reference = models["rasterOnly"].state_dict()
        for name, tensor in models["dual"].state_dict().items():
            torch.testing.assert_close(tensor, reference[name], rtol=0, atol=0)

    def test_raw_source_extent_maps_horizontal_vertical_and_degenerate_without_resampling(self):
        for points, width, height, scale, effective in (
            ((InkPoint(0, 0), InkPoint(100, 0)), 1.0, 0.0, 237.0, 237.0),
            ((InkPoint(0, 0), InkPoint(0, 100)), 0.0, 1.0, 77.0, 77.0),
            ((InkPoint(0, 0), InkPoint(100, 50)), 1.0, 0.5, 154.0, 154.0),
            ((InkPoint(7, 3),), 0.0, 0.0, 0.0, 77.0),
        ):
            sample = Sample("trn_toy_W01", 1, "A", (InkStroke(points),))
            before = copy.deepcopy(sample)
            mapping = experiment.source_mapping(sample)
            self.assertEqual((mapping.normalized_width, mapping.normalized_height, mapping.pixels_per_unit,
                              mapping.effective_pixels_per_unit), (width, height, scale, effective))
            self.assertEqual(sample, before)

    def test_synthetic_augmented_step_changes_parameters_with_finite_ce_and_source_preserved(self):
        samples = self.samples()
        batch = previous.encode_samples(samples, (samples[0].writer,), include_normalized_trajectory_hashes=False)
        maps, _ = experiment.source_mappings(samples)
        transforms = [augmentation.derive_transform(29, 1, previous.opaque_id(previous.SOURCE_SHA256, s.identity)) for s in samples]
        before = (batch.trajectory.clone(), batch.raster.clone())
        paired = augmentation.augment_batch(batch.trajectory.float(), batch.raster.float() / 255.0, transforms, maps)
        models, _ = experiment.initialized_models()
        model = models["dual"].train()
        initial = previous._state_digest(model.state_dict())
        optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
        loss, correct = experiment.training_step(model, paired.trajectory, paired.raster, torch.tensor([0, 1]), optimizer)
        self.assertTrue(np.isfinite(loss))
        self.assertIn(correct, (0, 1, 2))
        self.assertNotEqual(initial, previous._state_digest(model.state_dict()))
        torch.testing.assert_close(before[0], batch.trajectory, rtol=0, atol=0)
        torch.testing.assert_close(before[1], batch.raster, rtol=0, atol=0)

    def test_checkpoint_requires_trained_mask_version_and_exact_roundtrip(self):
        models, _ = experiment.initialized_models()
        payload = experiment.checkpoint_bytes(models["rasterOnly"], "rasterOnly", "a" * 64)
        restored = experiment.load_checkpoint(payload, "rasterOnly", "a" * 64)
        self.assertEqual(previous._state_digest(restored.state_dict()), scoring.INITIAL_STATE["sha256"])
        for arm, vocabulary in (("dual", "a" * 64), ("rasterOnly", "b" * 64), ("trajectoryOnly", "a" * 64)):
            with self.assertRaises(ValueError):
                experiment.load_checkpoint(payload, arm, vocabulary)
        with self.assertRaisesRegex(ValueError, "arm mask"):
            experiment.checkpoint_bytes(models["rasterOnly"], "dual", "a" * 64)

    def test_prediction_rows_are_complete_two_arm_outputs_without_labels_or_writers(self):
        samples = self.samples()
        batch = previous.encode_samples(samples, (samples[0].writer,), include_normalized_trajectory_hashes=False)
        outputs = {a: (np.tile(np.eye(1, 128, dtype=np.float32), (2, 1)), np.zeros((2, 97), dtype=np.float32)) for a in experiment.ARMS}
        rows = experiment.prediction_rows(samples, batch, outputs)
        self.assertEqual(len(rows), 2)
        self.assertEqual([r["opaqueID"] for r in rows], sorted(r["opaqueID"] for r in rows))
        self.assertEqual({tuple(r["outputs"]) for r in rows}, {experiment.ARMS})
        for forbidden in ("writer", "label", "intended", "correct", "sourceid"):
            self.assertNotIn(forbidden, repr(rows).lower())
        with self.assertRaises(ValueError):
            experiment.prediction_rows(samples, batch, {"dual": outputs["dual"]})

    def test_wrong_role_and_incomplete_cohort_are_rejected_and_outputs_append_only(self):
        reserved = Sample("tst_toy_W01", 1, "A", (InkStroke((InkPoint(0, 0),)),))
        with self.assertRaisesRegex(ValueError, "wrong-role"):
            previous.encode_samples((reserved,), (reserved.writer,), include_normalized_trajectory_hashes=False)
        models, _ = experiment.initialized_models()
        batch = previous.encode_samples(self.samples(), ("trn_toy_W01",), include_normalized_trajectory_hashes=False)
        with self.assertRaisesRegex(ValueError, "Incomplete training"):
            experiment.train_arm(models["dual"], "dual", batch, torch.tensor([0, 1]), ("a", "b"), ())
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            output = Path(directory) / "new"
            previous._new_output_directory(output)
            with self.assertRaises(ValueError):
                previous._new_output_directory(output)
            path = output / "receipt"
            previous._write_exclusive(path, b"first")
            with self.assertRaises(FileExistsError):
                previous._write_exclusive(path, b"second")
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), hashlib.sha256(b"first").hexdigest())


if __name__ == "__main__":
    unittest.main()
