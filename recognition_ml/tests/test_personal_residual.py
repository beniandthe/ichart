import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalResidualTests(unittest.TestCase):
    def test_empty_and_zero_error_lessons_preserve_generic_scores(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_residual import ResidualHead
        vocabulary = ("B", "G")
        empty = ResidualHead.fit(np.empty((0, 2)), np.empty((0, 2)), (), vocabulary)
        perfect = ResidualHead.fit(np.eye(2), np.eye(2), vocabulary, vocabulary)
        for model in (empty, perfect):
            self.assertEqual(model.rank([1, 0], [.8, .2]), [{"label": "B", "score": .8}, {"label": "G", "score": .2}])

    def test_closed_form_correction_balance_and_immutable_previous_snapshot(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_residual import ResidualHead
        x = np.array([[1., 0.], [1., 0.], [0., 1.]])
        base = np.array([[.2, .8], [.2, .8], [.1, .9]])
        model = ResidualHead.fit(x, base, ("B", "B", "G"), ("B", "G"))
        np.testing.assert_allclose(model.weights, np.array([[.8, -.8], [-.1, .1]]) / 1.1, atol=1e-12)
        corrected = ResidualHead.fit(x, base, ("G", "G", "B"), ("B", "G"))
        self.assertEqual(model.rank(x[0], base[0])[0]["label"], "B")
        self.assertEqual(corrected.rank(x[0], base[0])[0]["label"], "G")
        self.assertEqual(model.rank(x[0], base[0])[0]["label"], "B")
        with self.assertRaises(ValueError):
            model.weights[0, 0] = 5

    def test_unknown_labels_and_invalid_features_or_scores_refuse(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_residual import ResidualHead
        for features, base, labels, vocabulary in (
                (np.eye(2), np.eye(2), ("A", "C"), ("A", "B")),
                (np.eye(2), [[2, -1], [0, 1]], ("A", "B"), ("A", "B")),
                ([[0, 0], [0, 1]], np.eye(2), ("A", "B"), ("A", "B")),
                ([[float("nan"), 0], [0, 1]], np.eye(2), ("A", "B"), ("A", "B"))):
            with self.assertRaises(ValueError):
                ResidualHead.fit(features, base, labels, vocabulary)

    def test_normalization_is_stable_but_not_an_acceptance_decision(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_residual import normalized_scores
        np.testing.assert_array_equal(normalized_scores([1000, -1000]), [1, 0])
        np.testing.assert_allclose(normalized_scores([3, 5]), normalized_scores([103, 105]), atol=1e-14)
        with self.assertRaises(ValueError):
            normalized_scores([float("nan"), 0])

    def test_strict_finite_full_profile_normal_equations(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_residual import ResidualHead, normalized_scores
        rng = np.random.default_rng(29)
        x = rng.standard_normal((97, 128))
        x /= np.linalg.norm(x, axis=1, keepdims=True)
        base = normalized_scores(rng.standard_normal((97, 97)))
        labels = tuple(f"L{i:03d}" for i in range(97))
        with np.errstate(divide="raise", over="raise", invalid="raise"):
            model = ResidualHead.fit(x, base, labels, labels)
            normal = np.einsum("nd,ne->de", x, x, optimize=False) + .1 * np.eye(128)
            rhs = np.einsum("nd,nc->dc", x, np.eye(97) - base, optimize=False)
            residual = np.einsum("de,ec->dc", normal, model.weights, optimize=False) - rhs
            self.assertLess(np.abs(residual).max(), 1e-11)
            self.assertEqual(len(model.rank(x[0], base[0])), 97)
