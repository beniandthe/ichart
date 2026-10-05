import hashlib
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image
import torch

from ichart_recognition_ml.research.personal_symbol_data import (
    BitmapSample, NOVEL_LABELS, bitmap_tensor, load_hasy, map_label, normalize_bitmap, quarantine_copies,
)
from ichart_recognition_ml.research.personal_symbol_training import balanced_weights, expand_model
from ichart_recognition_ml.research.personal_symbol_expansion import fit_new_outputs
from ichart_recognition_ml.research.personal_visual_encoder import PersonalVisualEncoder


class PersonalSymbolDataTests(unittest.TestCase):
    def test_visual_mappings_do_not_coerce_unrelated_math_symbols(self):
        old = tuple("ABCDEFGb0123456789-<>")
        for source, expected in ((r"\sharp", "#"), (r"\#", "#"), (r"\flat", "b"),
                                 (r"\Delta", "△"), (r"\triangle", "△"), (r"\vartriangle", "△"),
                                 (r"\emptyset", "ø"), ("/", "/"), ("+", "+"), ("B", "B")):
            self.assertEqual(map_label(source, old), expected)
        for unrelated in (r"\delta", r"\triangledown", r"\phi", r"\backslash", "G7", ""):
            self.assertIsNone(map_label(unrelated, old))

    def test_bitmap_geometry_is_centered_and_aspect_preserving(self):
        image = Image.new("L", (32, 32), 255)
        for y in range(8, 24):
            for x in range(12, 20):
                image.putpixel((x, y), 0)
        pixels = normalize_bitmap(image)
        self.assertEqual(len(pixels), 96 * 256)
        ys, xs = np.nonzero(np.frombuffer(pixels, np.uint8).reshape(96, 256))
        self.assertEqual((xs.min(), xs.max(), ys.min(), ys.max()), (108, 147, 8, 87))
        self.assertEqual(pixels, normalize_bitmap(image.convert("RGB")))

    def test_invalid_bitmaps_and_unpinned_archive_refused(self):
        for image in (Image.new("L", (32, 32), 255), Image.new("L", (31, 32), 0),
                      Image.new("L", (32, 32), 128), Image.new("RGB", (32, 32), "red")):
            with self.assertRaises(ValueError):
                normalize_bitmap(image)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "wrong.tar.bz2"
            path.write_bytes(b"not the pinned source")
            with self.assertRaisesRegex(ValueError, "Wrong HASY"):
                load_hasy(path, tuple("AB"))

    @staticmethod
    def sample(identity, role="training", label="A", pixels=None):
        pixels = pixels or bytes([1]) * (96 * 256)
        digest = hashlib.sha256(pixels).hexdigest()
        return BitmapSample(identity, label, label, role, "not-a-writer", digest, digest, pixels)

    def test_copies_and_conflicting_labels_are_not_independent_queries(self):
        rows = quarantine_copies((self.sample("train-a"), self.sample("train-b"), self.sample("dev", "development")))
        self.assertEqual(rows[0].exclusions, ())
        self.assertEqual(rows[1].exclusions, ("same_role_raster_copy",))
        self.assertEqual(rows[2].exclusions, ("training_raster_copy",))
        conflicts = quarantine_copies((self.sample("a"), self.sample("b", label="B")))
        self.assertTrue(all(r.exclusions == ("conflicting_identical_raster",) for r in conflicts))

    def test_tensor_roles_and_exclusions_fail_before_training(self):
        sample = self.sample("train")
        self.assertEqual(tuple(bitmap_tensor((sample,), "training").shape), (1, 1, 96, 256))
        for rows, role in (((sample,), "development"), ((), "training"), ((sample,), "anything")):
            with self.assertRaises(ValueError):
                bitmap_tensor(rows, role)
        excluded = quarantine_copies((sample, self.sample("dev", "development")))[1]
        with self.assertRaises(ValueError):
            bitmap_tensor((excluded,), "development")


class PersonalSymbolTrainingTests(unittest.TestCase):
    def test_output_only_fit_learns_new_class_without_backpropagating_into_base(self):
        raw = torch.tensor([[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]], requires_grad=True)
        base = torch.tensor([[6., -1.], [-1., 6.], [2., 2.]], requires_grad=True)
        raw_before, base_before = raw.detach().clone(), base.detach().clone()
        targets = torch.tensor([0, 1, 2])
        weights, biases, fit = fit_new_outputs(raw, base, targets, 1, 2)
        scores = torch.cat((base.detach(), torch.nn.functional.linear(raw.detach(), weights, biases)), dim=1)
        self.assertEqual(scores.argmax(1).tolist(), [0, 1, 2])
        self.assertTrue(torch.equal(raw.detach(), raw_before))
        self.assertTrue(torch.equal(base.detach(), base_before))
        self.assertIsNone(raw.grad)
        self.assertIsNone(base.grad)
        self.assertLess(fit['losses'][-1], fit['losses'][0])
        again, again_bias, _ = fit_new_outputs(raw, base, targets, 1, 2)
        self.assertTrue(torch.equal(weights, again))
        self.assertTrue(torch.equal(biases, again_bias))
        with self.assertRaises(ValueError):
            fit_new_outputs(raw, base, torch.tensor([0, 1, 1]), 1, 2)

    def test_extension_preserves_original_weights_logits_and_features(self):
        torch.set_num_threads(2)
        torch.manual_seed(1)
        source = PersonalVisualEncoder(97).eval()
        labels = tuple(chr(0x400 + i) for i in range(97))
        expanded, vocabulary = expand_model(source, labels)
        again, _ = expand_model(source, labels)
        self.assertEqual(vocabulary, labels + NOVEL_LABELS)
        for key, value in expanded.state_dict().items():
            self.assertTrue(torch.equal(value, again.state_dict()[key]))
        images = torch.zeros((2, 1, 96, 256))
        with torch.inference_mode():
            features, logits = source(images)
            expanded_features, expanded_logits = expanded(images)
        torch.testing.assert_close(features, expanded_features, rtol=0, atol=0)
        self.assertTrue(torch.equal(source.classifier.weight, expanded.classifier.weight[:97]))
        self.assertTrue(torch.equal(source.classifier.bias, expanded.classifier.bias[:97]))
        # Wider GEMM can select a different accumulation kernel; the copied
        # parameters and embeddings are exact, not the float32 summation order.
        torch.testing.assert_close(logits, expanded_logits[:, :97], rtol=0, atol=1e-6)
        with self.assertRaises(ValueError):
            expand_model(source, tuple("AB"))

    def test_balanced_sampling_has_equal_total_mass_per_class(self):
        targets = torch.tensor([0, 0, 0, 4])
        weights = balanced_weights(targets)
        self.assertAlmostEqual(float(weights[:3].sum()), float(weights[3]))
        for invalid in (torch.tensor([]), torch.tensor([-1]), torch.tensor([[1]])):
            with self.assertRaises(ValueError):
                balanced_weights(invalid)


if __name__ == "__main__":
    unittest.main()
