import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.features import InkPoint, InkStroke, encode_trajectory, rasterize
from ichart_recognition_ml.research.uji_personal import Sample


HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional training dependencies required")
class PersonalDualViewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as experiment

        cls.torch = torch
        cls.experiment = experiment
        torch.set_num_threads(2)

    def random_inputs(self, count=3):
        generator = self.torch.Generator().manual_seed(71)
        trajectory = self.torch.rand((count, 1, 256, 10), generator=generator)
        raster = self.torch.rand((count, 1, 96, 256), generator=generator)
        return trajectory, raster

    def sample(self, label="A", writer="trn_UJI_W01", session=1, *, time=False):
        points = (
            InkPoint(-3, 1, 0.0 if time else None),
            InkPoint(0, 5, 0.1 if time else None),
            InkPoint(4, -2, 0.2 if time else None),
        )
        return Sample(writer, session, label, (InkStroke(points), InkStroke((InkPoint(7, 3),))))

    def test_frozen_architecture_outputs_finite_raw_logits_and_normalized_embedding(self):
        e = self.experiment
        trajectory, raster = self.random_inputs()
        model = e.PersonalDualViewEncoder(97, "dual").eval()
        embedding, logits = model(trajectory, raster)
        self.assertEqual(embedding.shape, (3, 128))
        self.assertEqual(logits.shape, (3, 97))
        self.assertTrue(self.torch.isfinite(embedding).all())
        self.assertTrue(self.torch.isfinite(logits).all())
        self.torch.testing.assert_close(
            embedding.norm(dim=1), self.torch.ones(3), rtol=1e-6, atol=1e-6
        )
        trajectory_convs = [
            layer for layer in model.trajectory_convolution if isinstance(layer, self.torch.nn.Conv1d)
        ]
        self.assertEqual(
            [(layer.in_channels, layer.out_channels, layer.kernel_size, layer.stride, layer.padding)
             for layer in trajectory_convs],
            [(8, 32, (7,), (1,), (3,)), (32, 64, (5,), (2,), (2,)),
             (64, 64, (3,), (2,), (1,))],
        )
        raster_convs = [
            layer for layer in model.raster_convolution if isinstance(layer, self.torch.nn.Conv2d)
        ]
        self.assertEqual([layer.out_channels for layer in raster_convs], [16, 32, 64, 64])
        self.assertEqual(model.raster_projection.in_features, 64 * 3 * 8)
        self.assertEqual(model.trajectory_projection.in_features, 64 * 8)

    def test_all_arms_have_bit_identical_initial_tensors_keys_and_parameter_count(self):
        e = self.experiment
        models, metadata = e.initialized_models()
        self.assertEqual(set(models), set(e.ARMS))
        self.assertEqual(len(set(metadata["armSHA256"].values())), 1)
        self.assertEqual(metadata["sha256"], metadata["armSHA256"]["dual"])
        reference = models["rasterOnly"].state_dict()
        for arm in e.ARMS[1:]:
            state = models[arm].state_dict()
            self.assertEqual(tuple(reference), tuple(state))
            for key in reference:
                self.torch.testing.assert_close(reference[key], state[key], rtol=0, atol=0)
        counts = {sum(parameter.numel() for parameter in model.parameters()) for model in models.values()}
        self.assertEqual(counts, {metadata["parameterCount"]})

    def test_inactive_input_is_independent_only_after_projection(self):
        e = self.experiment
        models, _ = e.initialized_models()
        trajectory, raster = self.random_inputs()
        changed_trajectory = trajectory.clone()
        changed_trajectory[:, :, :, list(e.GEOMETRY_CHANNELS)] += 9
        changed_raster = 1 - raster

        for arm, first, second in (
            ("rasterOnly", (trajectory, raster), (changed_trajectory, raster)),
            ("trajectoryOnly", (trajectory, raster), (trajectory, changed_raster)),
        ):
            model = models[arm].eval()
            before = model(*first)
            after = model(*second)
            for left, right in zip(before, after):
                self.torch.testing.assert_close(left, right, rtol=0, atol=0)

        dual = models["dual"].eval()
        base_embedding, base_logits = dual(trajectory, raster)
        trajectory_embedding, trajectory_logits = dual(changed_trajectory, raster)
        raster_embedding, raster_logits = dual(trajectory, changed_raster)
        self.assertFalse(self.torch.equal(base_embedding, trajectory_embedding))
        self.assertFalse(self.torch.equal(base_logits, trajectory_logits))
        self.assertFalse(self.torch.equal(base_embedding, raster_embedding))
        self.assertFalse(self.torch.equal(base_logits, raster_logits))

    def test_timing_channels_are_excluded_even_when_supplied(self):
        e = self.experiment
        model = e.PersonalDualViewEncoder(97, "dual").eval()
        trajectory, raster = self.random_inputs()
        changed = trajectory.clone()
        changed[:, :, :, 5] = 1000
        changed[:, :, :, 6] = 1
        before = model(trajectory, raster)
        after = model(changed, raster)
        for left, right in zip(before, after):
            self.torch.testing.assert_close(left, right, rtol=0, atol=0)
        self.assertEqual(e.GEOMETRY_CHANNELS, (0, 1, 2, 3, 4, 7, 8, 9))
        self.assertEqual(e.TIMING_CHANNELS_EXCLUDED, (5, 6))

    def test_wrong_role_is_refused_before_any_feature_or_fingerprint_call(self):
        e = self.experiment
        reserved = self.sample(writer="tst_UJI_W01")
        with patch.object(e, "encode_trajectory") as trajectory, \
                patch.object(e, "rasterize") as raster, \
                patch.object(e, "trajectory_fingerprint") as fingerprint:
            with self.assertRaisesRegex(ValueError, "wrong-role"):
                e.encode_samples(
                    (reserved,),
                    (reserved.writer,),
                    include_normalized_trajectory_hashes=True,
                )
            trajectory.assert_not_called()
            raster.assert_not_called()
            fingerprint.assert_not_called()

    def test_synthetic_encoding_uses_exact_frozen_artifacts_and_retains_hash_multiplicity(self):
        e = self.experiment
        sample = self.sample(time=True)
        batch = e.encode_samples(
            (sample,),
            (sample.writer,),
            include_normalized_trajectory_hashes=True,
        )
        expected_trajectory = encode_trajectory(sample.strokes).to_bytes()
        expected_raster = rasterize(sample.strokes).pixels
        self.assertEqual(batch.trajectory.shape, (1, 1, 256, 10))
        self.assertEqual(batch.raster.shape, (1, 1, 96, 256))
        self.assertEqual(batch.trajectory_hashes, (hashlib.sha256(expected_trajectory).hexdigest(),))
        self.assertEqual(batch.raster_hashes, (hashlib.sha256(expected_raster).hexdigest(),))
        duplicated = e.FeatureBatch(
            trajectory=self.torch.cat((batch.trajectory, batch.trajectory)),
            raster=self.torch.cat((batch.raster, batch.raster)),
            trajectory_hashes=batch.trajectory_hashes * 2,
            raster_hashes=batch.raster_hashes * 2,
            normalized_trajectory_hashes=batch.normalized_trajectory_hashes * 2,
        )
        hashes = e._training_input_hashes(duplicated)
        self.assertEqual(len(hashes), 2)
        self.assertEqual(hashes[0], hashes[1])
        self.assertEqual(
            set(hashes[0]),
            {"normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256"},
        )
        self.assertNotIn("writer", repr(hashes).lower())
        self.assertNotIn("label", repr(hashes).lower())

    def test_checkpoint_is_bound_to_arm_mask_and_final_output_rows_are_label_free(self):
        e = self.experiment
        models, _ = e.initialized_models()
        vocabulary_hash = "a" * 64
        payload = e._checkpoint_bytes(models["rasterOnly"], "rasterOnly", vocabulary_hash)
        restored = e._load_checkpoint(payload, "rasterOnly", vocabulary_hash)
        self.assertEqual(restored.arm, "rasterOnly")
        with self.assertRaisesRegex(ValueError, "arm mask"):
            e._load_checkpoint(payload, "dual", vocabulary_hash)

        samples = (self.sample("A"), self.sample("B", session=2))
        batch = e.encode_samples(
            samples,
            (samples[0].writer,),
            include_normalized_trajectory_hashes=False,
        )
        outputs = {
            arm: (
                np.zeros((2, 128), dtype=np.float32),
                np.zeros((2, 97), dtype=np.float32),
            )
            for arm in e.ARMS
        }
        rows = e._prediction_rows(samples, batch, outputs, "b" * 64)
        self.assertEqual([row["opaqueID"] for row in rows], sorted(row["opaqueID"] for row in rows))
        self.assertEqual({len(row["outputs"]["dual"]["rawLogits"]) for row in rows}, {97})
        self.assertEqual({len(row["outputs"]["dual"]["embedding"]) for row in rows}, {128})
        serialized = repr(rows).lower()
        for forbidden in ("writer", "label", "correct", "intended", "sourceid"):
            self.assertNotIn(forbidden, serialized)

    def test_paths_are_append_only_and_symlink_aliases_are_rejected(self):
        e = self.experiment
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            source = root / "source"
            source.write_bytes(b"synthetic")
            alias = root / "alias"
            alias.symlink_to(source)
            self.assertEqual(e._require_regular_file(source, kind="synthetic"), source)
            with self.assertRaisesRegex(ValueError, "aliases and symlinks"):
                e._require_regular_file(alias, kind="synthetic alias")
            output = root / "new-output"
            e._new_output_directory(output)
            with self.assertRaisesRegex(ValueError, "must be a new"):
                e._new_output_directory(output)


if __name__ == "__main__":
    unittest.main()
