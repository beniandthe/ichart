import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalAnchorTests(unittest.TestCase):
    def test_anchor_means_normalized_and_inputs_unchanged(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_anchors import AnchorBank
        features = np.array([[1., 0.], [0., 1.], [0., 1.]])
        original = features.copy()
        bank = AnchorBank.from_training(features, ("A", "A", "B"), ("A", "B"))
        np.testing.assert_allclose(bank.features, [[2 ** -.5, 2 ** -.5], [0, 1]])
        np.testing.assert_array_equal(features, original)
        with self.assertRaises(ValueError):
            bank.features[0, 0] = 4
        with self.assertRaises(ValueError):
            AnchorBank.from_training([[1, 0], [-1, 0], [0, 1]], ("A", "A", "B"), ("A", "B"))

    def test_empty_and_full_profiles_reproduce_existing_residual_learner(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, fit_anchored
        from ichart_recognition_ml.research.personal_residual import ResidualHead
        bank = AnchorBank.from_training(np.eye(2), ("B", "G"), ("B", "G"))
        for features, base, labels in ((np.eye(2), [[.2, .8], [.1, .9]], ("B", "G")),
                                       (np.empty((0, 2)), np.empty((0, 2)), ())):
            model = fit_anchored(features, base, labels, ("B", "G"), bank)
            original = ResidualHead.fit(features, base, labels, ("B", "G"))
            np.testing.assert_array_equal(model.weights, original.weights)

    def test_closed_form_prior_class_balance_and_explicit_correction(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, fit_anchored
        bank = AnchorBank.from_training([[1, 0], [1, 0]], ("A", "B"), ("A", "B"))
        model = fit_anchored([[1, 0]], [[.2, .8]], ("A",), ("A", "B"), bank)
        np.testing.assert_allclose(model.weights, [[.8 / 2.1, -.8 / 2.1], [0, 0]], atol=1e-12)
        duplicate = fit_anchored([[1, 0], [1, 0]], [[.2, .8], [.2, .8]], ("A", "A"), ("A", "B"), bank)
        np.testing.assert_allclose(model.weights, duplicate.weights, atol=1e-12)
        corrected = fit_anchored([[1, 0]], [[.2, .8]], ("B",), ("A", "B"), bank)
        self.assertLess(corrected.weights[0, 0], 0)
        self.assertGreater(model.weights[0, 0], 0)

    def test_random_normal_equations_and_anchor_order_independence(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, fit_anchored
        from ichart_recognition_ml.research.personal_residual import normalized_scores
        rng = np.random.default_rng(29)
        x = rng.standard_normal((8, 12)); x /= np.linalg.norm(x, axis=1, keepdims=True)
        anchors = rng.standard_normal((5, 12)); anchors /= np.linalg.norm(anchors, axis=1, keepdims=True)
        vocabulary = ("A", "B", "C", "D", "E")
        labels = ("A", "A", "A", "B", "B", "C", "C", "C")
        base = normalized_scores(rng.standard_normal((8, 5)))
        bank = AnchorBank.from_training(anchors, vocabulary, vocabulary)
        model = fit_anchored(x, base, labels, vocabulary, bank)
        balance = np.array([1 / np.sqrt(labels.count(label)) for label in labels])[:, None]
        weighted = x * balance
        target = (np.array([[float(label == c) for c in vocabulary] for label in labels]) - base) * balance
        normal = np.einsum('nd,ne->de', weighted, weighted, optimize=False) + np.einsum('nd,ne->de', anchors[3:], anchors[3:], optimize=False) + .1 * np.eye(12)
        residual = np.einsum('de,ec->dc', normal, model.weights, optimize=False) - np.einsum('nd,nc->dc', weighted, target, optimize=False)
        self.assertLess(np.abs(residual).max(), 1e-12)
        reversed_bank = AnchorBank.from_training(anchors, vocabulary, tuple(reversed(vocabulary)))
        np.testing.assert_allclose(fit_anchored(x, base, labels, vocabulary, reversed_bank).weights, model.weights, atol=1e-12)

    def test_invalid_bank_refuses_but_explicit_novel_label_is_not_invented(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, fit_anchored
        bank = AnchorBank.from_training(np.eye(2), ("A", "B"), ("A", "B"))
        novel = fit_anchored([[1., 0.]], [[.5, .5, 0]], ("△",), ("A", "B", "△"), bank)
        self.assertEqual(novel.lesson_count, 1)
        self.assertGreater(novel.weights[0, 2], 0)
        self.assertNotIn("△", bank.vocabulary)
        for invalid in (AnchorBank(("A", "B"), np.ones((2, 3))), AnchorBank(("A", "Z"), np.eye(2))):
            with self.assertRaises(ValueError):
                fit_anchored([[1., 0.]], [[.5, .5]], ("A",), ("A", "B"), invalid)

    def test_query_answer_changes_affect_scores_not_personal_predictions(self):
        from dataclasses import replace
        import numpy as np
        from ichart_recognition_ml.research.uji_personal import Sample
        from ichart_recognition_ml.research.personal_adaptability import evaluate
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, evaluate_anchored
        vocabulary = ("A", "B", "C")
        samples = tuple(Sample("trn_UPV_W01", session, label, ())
                        for session in (1, 2) for label in vocabulary)
        features = np.tile(np.eye(3), (2, 1))
        logits = features * 5
        bank = AnchorBank.from_training(np.eye(3), vocabulary, vocabulary)
        outcomes = []
        for inputs in (samples, tuple(replace(s, label=vocabulary[(vocabulary.index(s.label) + 1) % 3])
                                     if s.session == 2 else s for s in samples)):
            exclusions = {s.identity: [] for s in inputs if s.session == 2}
            reference = evaluate(inputs, features, logits, vocabulary, ("A",), exclusions)
            outcomes.append(evaluate_anchored(inputs, features, logits, vocabulary, bank, reference))
        self.assertEqual([r["personalRanks"] for r in outcomes[0]["rows"]],
                         [r["personalRanks"] for r in outcomes[1]["rows"]])
        self.assertEqual(outcomes[0]["personalCorrect"], 3)
        self.assertEqual(outcomes[1]["personalCorrect"], 0)
