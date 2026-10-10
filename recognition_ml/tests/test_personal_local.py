import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalLocalTests(unittest.TestCase):
    def test_rbf_matches_independent_distance_formula_and_empty_profile(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead, rbf
        x = np.array([[1., 0.], [0., 1.], [-1., 0.]])
        expected = np.array([[np.exp(-sum((a - b) ** 2) / .2) for b in x] for a in x])
        np.testing.assert_allclose(rbf(x, x, .2), expected, atol=1e-14)
        model = LocalResidualHead.fit(np.empty((0, 2)), np.empty((0, 2)), (), ("A", "B"), .2)
        self.assertEqual(model.rank(x[0], [.4, .6]), [{"label": "B", "score": .6}, {"label": "A", "score": .4}])

    def test_dual_fit_matches_independent_weighted_normal_equations(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead
        from ichart_recognition_ml.research.personal_residual import normalized_scores
        rng = np.random.default_rng(29)
        x = rng.standard_normal((6, 5)); x /= np.linalg.norm(x, axis=1, keepdims=True)
        labels, vocabulary = ("A", "A", "A", "B", "B", "C"), ("A", "B", "C")
        base = normalized_scores(rng.standard_normal((6, 3)))
        width = .3
        model = LocalResidualHead.fit(x, base, labels, vocabulary, width)
        kernel = np.exp(-((x[:, None, :] - x[None, :, :]) ** 2).sum(axis=2) / width)
        target = np.array([[float(label == c) for c in vocabulary] for label in labels]) - base
        normal = kernel + .1 * np.diag([labels.count(label) for label in labels])
        np.testing.assert_allclose(normal @ model.coefficients, target, atol=1e-12)
        query = rng.standard_normal(5); query /= np.linalg.norm(query)
        expected = np.array([.2, .3, .5]) + np.exp(-((x - query) ** 2).sum(axis=1) / width) @ np.linalg.solve(normal, target)
        observed = {r["label"]: r["score"] for r in model.rank(query, [.2, .3, .5])}
        np.testing.assert_allclose([observed[c] for c in vocabulary], expected, atol=1e-12)

    def test_duplicate_lesson_class_balance_ordering_and_owned_immutable_inputs(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead
        features, base = np.eye(2), np.array([[.2, .8], [.6, .4]])
        model = LocalResidualHead.fit(features, base, ("A", "B"), ("A", "B"), .25)
        duplicate = LocalResidualHead.fit(features[[0, 0, 1]], base[[0, 0, 1]], ("A", "A", "B"), ("A", "B"), .25)
        reversed_model = LocalResidualHead.fit(features[::-1], base[::-1, ::-1], ("B", "A"), ("B", "A"), .25)
        query = np.array([.8, .6])
        ranks = model.rank(query, [.2, .8])
        for other, scores in ((duplicate, [.2, .8]), (reversed_model, [.8, .2])):
            alternate = other.rank(query, scores)
            self.assertEqual([r["label"] for r in ranks], [r["label"] for r in alternate])
            np.testing.assert_allclose([r["score"] for r in ranks], [r["score"] for r in alternate], atol=1e-12)
        np.testing.assert_array_equal(features, np.eye(2))
        features[:] = 9; base[:] = 0
        self.assertEqual(model.rank(query, [.2, .8]), ranks)
        with self.assertRaises(ValueError):
            model.features[0, 0] = 2
        with self.assertRaises(ValueError):
            model.coefficients[0, 0] = 2

    def test_local_correction_decays_and_explicit_novel_label_can_learn(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead
        model = LocalResidualHead.fit([[1., 0.]], [[.2, .8, 0]], ("△",), ("A", "B", "△"), .1)
        self.assertEqual(model.rank([1., 0.], [.2, .8, 0])[0]["label"], "△")
        far = {r["label"]: r["score"] for r in model.rank([-1., 0.], [.2, .8, 0])}
        np.testing.assert_allclose([far[c] for c in ("A", "B", "△")], [.2, .8, 0], atol=1e-15)
        relabeled = LocalResidualHead.fit([[1., 0.]], [[.2, .8, 0]], ("A",), ("A", "B", "△"), .1)
        self.assertEqual(relabeled.rank([1., 0.], [.2, .8, 0])[0]["label"], "A")

    def test_invalid_fit_and_query_inputs_are_rejected(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead
        valid = dict(features=[[1., 0.]], base_scores=[[.2, .8]], explicit_labels=("A",), vocabulary=("A", "B"), width=.2)
        for key, values in {
            "features": ([[0, 0]], [[2, 0]], [[float("nan"), 0]], np.ones((193, 2))),
            "base_scores": ([[2, 3]], [[.1, .1]], [[float("nan"), .8]], [[.2, .8, 0]]),
            "explicit_labels": ((), ("Z",)), "vocabulary": (("A",), ("A", "A"), ("A", "")),
            "width": (0, -1, float("nan"), float("inf")), "regularization": (0, -1, float("nan"))
        }.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    LocalResidualHead.fit(**{**valid, key: value})
        model = LocalResidualHead.fit(**valid)
        for features, scores in (([0, 0], [.2, .8]), ([1, 0, 0], [.2, .8]), ([1, 0], [.2, .3])):
            with self.assertRaises(ValueError):
                model.rank(features, scores)

    def training_fixture(self):
        import math
        import numpy as np
        from ichart_recognition_ml.features import InkPoint, InkStroke
        from ichart_recognition_ml.research.uji_personal import Sample
        samples = tuple(Sample("trn_UJI_W01", session, label,
            (InkStroke((InkPoint(0, 0), InkPoint(session * 3, 2 + index), InkPoint(10, 10))),))
            for session in (1, 2) for index, label in enumerate(("A", "B")))
        return samples, np.array([[1., 0.], [0., 1.], [math.cos(.2), math.sin(.2)], [.8, .6]])

    def test_width_is_training_pair_median_with_copy_exclusions(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import training_width
        samples, features = self.training_fixture()
        result = training_width(samples, features, ["a1", "b1", "a2", "b2"], ("trn_UJI_W01",), ("A", "B"))
        self.assertEqual(result["pairCount"], 2)
        self.assertEqual(result["eligiblePairs"], 2)
        self.assertAlmostEqual(result["width"], float(np.median(((features[:2] - features[2:]) ** 2).sum(axis=1))))
        copy = training_width(samples, features, ["a1", "same", "a2", "same"], ("trn_UJI_W01",), ("A", "B"))
        self.assertEqual(copy["eligiblePairs"], 1)
        self.assertEqual(copy["pairs"][1]["exclusions"], ["raster-copy"])
        self.assertAlmostEqual(copy["width"], float(((features[0] - features[2]) ** 2).sum()))

    def test_width_refuses_wrong_writer_role_incomplete_duplicates_and_all_copies(self):
        from dataclasses import replace
        from ichart_recognition_ml.research.personal_local import training_width
        samples, features = self.training_fixture()
        for wrong in ("trn_UPV_W02", "tst_UJI_W01"):
            with self.assertRaises(ValueError):
                training_width(tuple(replace(s, writer=wrong) for s in samples), features,
                               ["a", "b", "c", "d"], ("trn_UJI_W01",), ("A", "B"))
        for bad in (samples[:-1], (samples[0], samples[0], *samples[2:])):
            with self.assertRaises(ValueError):
                training_width(bad, features, ["a", "b", "c", "d"], ("trn_UJI_W01",), ("A", "B"))
        with self.assertRaises(ValueError):
            training_width(samples, features, ["same"] * 4, ("trn_UJI_W01",), ("A", "B"))

    def test_query_answers_do_not_enter_personal_predictions_and_references_are_bound(self):
        from copy import deepcopy
        from dataclasses import replace
        import numpy as np
        from ichart_recognition_ml.research.uji_personal import Sample
        from ichart_recognition_ml.research.personal_adaptability import evaluate
        from ichart_recognition_ml.research.personal_anchors import AnchorBank, evaluate_anchored
        from ichart_recognition_ml.research.personal_local import evaluate_local
        vocabulary = ("A", "B", "C")
        samples = tuple(Sample("trn_UPV_W01", session, label, ()) for session in (1, 2) for label in vocabulary)
        features = np.tile(np.eye(3), (2, 1)); logits = features * 5
        bank = AnchorBank.from_training(np.eye(3), vocabulary, vocabulary)
        outcomes = []
        for inputs in (samples, tuple(replace(s, label=vocabulary[(vocabulary.index(s.label) + 1) % 3])
                                     if s.session == 2 else s for s in samples)):
            ref = evaluate(inputs, features, logits, vocabulary, ("A",), {s.identity: [] for s in inputs if s.session == 2})
            anchor = evaluate_anchored(inputs, features, logits, vocabulary, bank, ref)
            outcomes.append(evaluate_local(inputs, features, logits, vocabulary, .2, ref, anchor))
            tampered = deepcopy(ref); tampered["rows"][0]["supportIDs"] = ["wrong"]
            with self.assertRaises(ValueError):
                evaluate_local(inputs, features, logits, vocabulary, .2, tampered, anchor)
            tampered = deepcopy(anchor); tampered["rows"].append(tampered["rows"][0])
            with self.assertRaises(ValueError):
                evaluate_local(inputs, features, logits, vocabulary, .2, ref, tampered)
        self.assertEqual([r["personalRanks"] for r in outcomes[0]["rows"]], [r["personalRanks"] for r in outcomes[1]["rows"]])
        self.assertEqual(outcomes[0]["personalCorrect"], 3)
        self.assertEqual(outcomes[1]["personalCorrect"], 0)

    def test_local_priors_preserve_exact_empty_and_full_profile_limits(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local import LocalResidualHead
        from ichart_recognition_ml.research.personal_local_anchors import fit_local_anchored
        from ichart_recognition_ml.research.personal_anchors import AnchorBank
        bank = AnchorBank.from_training(np.eye(2), ("A", "B"), ("A", "B"))
        for x, base, labels in ((np.eye(2), [[.2, .8], [.3, .7]], ("A", "B")),
                               (np.empty((0, 2)), np.empty((0, 2)), ())):
            original = LocalResidualHead.fit(x, base, labels, ("A", "B"), .2)
            constrained = fit_local_anchored(x, base, labels, ("A", "B"), .2, bank)
            np.testing.assert_array_equal(original.features, constrained.features)
            np.testing.assert_array_equal(original.coefficients, constrained.coefficients)

    def test_local_prior_weight_and_duplicate_lesson_balance(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local_anchors import fit_local_anchored
        from ichart_recognition_ml.research.personal_anchors import AnchorBank
        bank = AnchorBank.from_training([[1., 0.], [1., 0.]], ("A", "B"), ("A", "B"))
        single = fit_local_anchored([[1., 0.]], [[.2, .8]], ("A",), ("A", "B"), .2, bank)
        repeated = fit_local_anchored([[1., 0.], [1., 0.]], [[.2, .8], [.2, .8]], ("A", "A"), ("A", "B"), .2, bank)
        expected = {"A": .2 + .8 / 2.1, "B": .8 - .8 / 2.1}
        for model in (single, repeated):
            result = {row["label"]: row["score"] for row in model.rank([1., 0.], [.2, .8])}
            np.testing.assert_allclose([result[c] for c in ("A", "B")], [expected[c] for c in ("A", "B")], atol=1e-12)

    def test_local_prior_independent_equations_ordering_and_novel_label(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_local_anchors import fit_local_anchored
        from ichart_recognition_ml.research.personal_anchors import AnchorBank
        from ichart_recognition_ml.research.personal_residual import normalized_scores
        rng = np.random.default_rng(29)
        x = rng.standard_normal((3, 5)); x /= np.linalg.norm(x, axis=1, keepdims=True)
        anchors = rng.standard_normal((3, 5)); anchors /= np.linalg.norm(anchors, axis=1, keepdims=True)
        vocabulary, labels = ("A", "B", "C", "△"), ("A", "A", "△")
        base = np.column_stack((normalized_scores(rng.standard_normal((3, 3))), np.zeros(3)))
        bank = AnchorBank(("A", "B", "C"), anchors)
        model = fit_local_anchored(x, base, labels, vocabulary, .2, bank)
        points = np.concatenate((x, anchors[1:]))
        kernel = np.exp(-((points[:, None, :] - points[None, :, :]) ** 2).sum(axis=2) / .2)
        normal = kernel + .1 * np.diag([2, 2, 1, 1, 1])
        target = np.concatenate((np.array([[float(label == c) for c in vocabulary] for label in labels]) - base, np.zeros((2, 4))))
        np.testing.assert_allclose(normal @ model.coefficients, target, atol=1e-12)
        reversed_model = fit_local_anchored(x, base, labels, vocabulary, .2, AnchorBank(tuple(reversed(bank.vocabulary)), anchors[::-1]))
        before = model.rank(x[2], base[2])
        alternate = reversed_model.rank(x[2], base[2])
        self.assertEqual([row["label"] for row in before], [row["label"] for row in alternate])
        np.testing.assert_allclose([row["score"] for row in before], [row["score"] for row in alternate], atol=1e-12)
        self.assertEqual(before[0]["label"], "△")
        x[:] = 8; anchors[:] = 4
        self.assertEqual(model.rank(points[2], base[2]), before)
        for wrong in (AnchorBank(("A", "B"), np.ones((2, 5))), AnchorBank(("A", "Z"), np.eye(2))):
            with self.assertRaises(ValueError):
                fit_local_anchored([[1., 0.]], [[.5, .5]], ("A",), ("A", "B"), .2, wrong)


if __name__ == "__main__":
    unittest.main()
