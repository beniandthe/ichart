import importlib.util
import unittest

from ichart_recognition_ml.research.uji_personal import Sample, parse_source, split_writers, trajectory_fingerprint

HAS_TORCH = importlib.util.find_spec("torch") is not None


class PublicPersonalSourceTests(unittest.TestCase):
    SOURCE = "// source\nWORD A trn_UJI_W03-01\nNUMSTROKES 1\nPOINTS 3 # -1 0 -1 0 3 4\n"

    def test_parser_keeps_repeated_coordinates_and_no_invented_timing(self):
        sample, = parse_source(self.SOURCE)
        self.assertEqual(sample.identity, "trn_UJI_W03-1-A")
        self.assertEqual(len(sample.strokes[0].points), 3)
        self.assertEqual(sample.strokes[0].points[0].x, -1)
        self.assertIsNone(sample.strokes[0].points[0].time_offset)

    def test_parser_refuses_malformed_duplicate_truncated_source(self):
        for source in (self.SOURCE + self.SOURCE, self.SOURCE.replace("POINTS 3", "POINTS 2"),
                       self.SOURCE.replace("-01", "-03"), "WORD A trn_UJI_W03-01", ""):
            with self.subTest(source=source), self.assertRaises(ValueError):
                parse_source(source)

    def test_partition_is_deterministic_disjoint_and_order_independent(self):
        samples = tuple(Sample(f"{prefix}_UPV_W{i:02d}", 1, "A", ())
                        for prefix, count in (("trn", 40), ("tst", 20)) for i in range(count))
        a = split_writers(samples)
        self.assertEqual(a, split_writers(tuple(reversed(samples))))
        self.assertEqual(tuple(map(len, a)), (32, 8, 20))
        self.assertTrue(set(a[0]).isdisjoint(a[1]))
        self.assertTrue(set(a[2]).isdisjoint(a[0] + a[1]))
        with self.assertRaises(ValueError):
            split_writers(samples[:-1])

    def test_normalized_identity_does_not_depend_on_label_or_uniform_scale(self):
        original, = parse_source(self.SOURCE)
        translated, = parse_source(self.SOURCE.replace("WORD A", "WORD G").replace("-1 0 -1 0 3 4", "8 20 8 20 16 28"))
        self.assertEqual(trajectory_fingerprint(original), trajectory_fingerprint(translated))


@unittest.skipUnless(HAS_TORCH, "Optional training dependencies required")
class PersonalEncoderLearningTests(unittest.TestCase):
    def setUp(self):
        import torch
        torch.set_num_threads(2)
        torch.manual_seed(29)

    def test_ridge_closed_form_class_balance_and_explicit_label_correction(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_visual_encoder import fit_personal, rank_personal
        x = np.array([[1., 0.], [1., 0.], [0., 1.]])
        first = fit_personal(x, ("B", "B", "G"))
        np.testing.assert_allclose(first[1], np.eye(2) / 1.1, atol=1e-12)
        self.assertEqual(rank_personal(first, x[0])[0]["label"], "B")
        corrected = fit_personal(x, ("G", "G", "B"))
        self.assertEqual(rank_personal(corrected, x[0])[0]["label"], "G")
        self.assertEqual(rank_personal(first, x[0])[0]["label"], "B")

    def test_invalid_fit_and_query_refuse(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_visual_encoder import fit_personal, rank_personal
        for x, labels in (([[1], [0]], ("A", "A")), ([[float("nan")], [0]], ("A", "B")),
                          ([[1], [0]], ("A",))):
            with self.assertRaises(ValueError):
                fit_personal(np.array(x), labels)
        fitted = fit_personal(np.eye(2), ("A", "B"))
        with self.assertRaises(ValueError):
            rank_personal(fitted, np.array([float("nan"), 1]))

    def test_full_profile_fit_has_finite_arithmetic_and_small_normal_equation_residual(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_visual_encoder import fit_personal, rank_personal
        x = np.random.default_rng(29).standard_normal((97, 128))
        x /= np.linalg.norm(x, axis=1, keepdims=True)
        with np.errstate(divide="raise", over="raise", invalid="raise"):
            classes, weights = fit_personal(x, tuple(f"L{i:03d}" for i in range(97)))
            rank_personal((classes, weights), x[0])
            normal = np.einsum("nd,ne->de", x, x, optimize=False) + 0.1 * np.eye(128)
            residual = np.einsum("de,ec->dc", normal, weights, optimize=False) - x.T
            self.assertLess(np.abs(residual).max(), 1e-11)

    def test_model_features_normalized_and_training_changes_parameters(self):
        import torch
        from ichart_recognition_ml.research.personal_visual_encoder import PersonalVisualEncoder
        model = PersonalVisualEncoder(7)
        raster = torch.rand(2, 1, 96, 256)
        before = model.projection.weight.detach().clone()
        features, logits = model(raster)
        self.assertEqual(features.shape, (2, 128))
        torch.testing.assert_close(features.norm(dim=1), torch.ones(2))
        loss = torch.nn.functional.cross_entropy(logits, torch.tensor([0, 1]))
        optimizer = torch.optim.AdamW(model.parameters())
        loss.backward()
        optimizer.step()
        self.assertFalse(torch.equal(before, model.projection.weight))

    def test_augmentation_repeatable_and_does_not_mutate_source(self):
        import torch
        from ichart_recognition_ml.research.personal_visual_encoder import augment
        source = torch.rand(2, 1, 96, 256)
        copy = source.clone()
        first = augment(source, torch.Generator().manual_seed(29))
        second = augment(source, torch.Generator().manual_seed(29))
        torch.testing.assert_close(first, second, rtol=0, atol=0)
        torch.testing.assert_close(source, copy, rtol=0, atol=0)
        self.assertTrue(torch.isfinite(first).all())
        self.assertTrue((first >= 0).all() and (first <= 1).all())

    def test_reserved_writer_refused_before_rasterizer(self):
        from unittest.mock import patch
        from ichart_recognition_ml.research.personal_visual_encoder import encode_samples
        sample = Sample("tst_UPV_W01", 1, "A", ())
        with patch("ichart_recognition_ml.research.personal_visual_encoder.rasterize") as raster:
            with self.assertRaises(ValueError):
                encode_samples((sample,), (sample.writer,))
            raster.assert_not_called()

    def test_query_answers_do_not_change_personal_predictions_and_copies_are_excluded(self):
        from dataclasses import replace
        import numpy as np
        from ichart_recognition_ml.features import InkPoint, InkStroke
        from ichart_recognition_ml.research.personal_encoder_export import wider_personalization
        labels = tuple(f"L{i:03d}" for i in range(97))
        samples = tuple(Sample("trn_UPV_W01", session, label,
                              (InkStroke((InkPoint(0, 0), InkPoint(4, i + 1), InkPoint(8 + session, 2))),))
                        for session in (1, 2) for i, label in enumerate(labels))
        features = np.vstack((np.eye(97), np.eye(97)))
        pixels = [f"pixel-{i}" for i in range(194)]
        pixels[97] = "known-training-raster"
        baseline = wider_personalization(samples, features, features, labels, {pixels[97]}, pixels)
        self.assertEqual(baseline["eligibleQueries"], 96)
        self.assertEqual(baseline["personalCorrect"], 96)
        self.assertIn("encoder_training_raster_copy", baseline["rows"][0]["exclusions"])
        changed = tuple(replace(s, label=labels[(i - 97 + 1) % 97]) if i >= 97 else s
                        for i, s in enumerate(samples))
        probe = wider_personalization(changed, features, features, labels, {pixels[97]}, pixels)
        self.assertEqual([r["personal"] for r in baseline["rows"]], [r["personal"] for r in probe["rows"]])
        self.assertEqual(probe["personalCorrect"], 0)
