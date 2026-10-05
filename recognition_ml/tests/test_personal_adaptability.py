import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalAdaptabilityTests(unittest.TestCase):
    def setUp(self):
        import torch
        torch.set_num_threads(2)
        torch.manual_seed(29)

    def matrices(self):
        import torch
        x = torch.nn.functional.normalize(torch.randn(4, 5, dtype=torch.float64), dim=1)
        q = torch.nn.functional.normalize(torch.randn(3, 5, dtype=torch.float64), dim=1)
        return x, torch.randn(4, 3, dtype=torch.float64), torch.tensor([0, 0, 1, 2]), q, torch.randn(3, 3, dtype=torch.float64)

    def test_differentiable_solver_matches_independent_balanced_numpy_solver(self):
        import numpy as np
        from ichart_recognition_ml.research.personal_adaptability import adapted_scores
        from ichart_recognition_ml.research.personal_residual import ResidualHead, normalized_scores
        x, logits, labels, q, qlogits = self.matrices()
        vocabulary = ("B", "D", "G")
        model = ResidualHead.fit(x.numpy(), normalized_scores(logits.numpy()),
                                 tuple(vocabulary[i] for i in labels), vocabulary)
        result = adapted_scores(x, logits, labels, q, qlogits).detach().numpy()
        for i in range(len(q)):
            expected = {r["label"]: r["score"] for r in model.rank(q[i].numpy(), normalized_scores(qlogits[i].numpy()))}
            np.testing.assert_allclose(result[i], [expected[label] for label in vocabulary], atol=1e-12, rtol=1e-12)

    def test_gradients_through_support_solve_and_queries_match_finite_difference(self):
        import torch
        from ichart_recognition_ml.research.personal_adaptability import adapted_scores
        x, logits, labels, q, qlogits = self.matrices()
        inputs = tuple(value.requires_grad_() for value in (x, logits, q, qlogits))
        function = lambda a, b, c, d: adapted_scores(a, b, labels, c, d)
        self.assertTrue(torch.autograd.gradcheck(function, inputs, eps=1e-6, atol=1e-5, rtol=1e-4))
        function(*inputs).square().sum().backward()
        for value in inputs:
            self.assertTrue(torch.isfinite(value.grad).all())
            self.assertGreater(float(value.grad.abs().sum()), 1e-8)

    def test_empty_lessons_are_generic_and_support_order_does_not_change_fit(self):
        import torch
        from ichart_recognition_ml.research.personal_adaptability import adapted_scores
        x, logits, labels, q, qlogits = self.matrices()
        torch.testing.assert_close(adapted_scores(x[:0], logits[:0], labels[:0], q, qlogits), qlogits.softmax(1))
        order = torch.tensor([3, 1, 0, 2])
        torch.testing.assert_close(adapted_scores(x, logits, labels, q, qlogits),
                                   adapted_scores(x[order], logits[order], labels[order], q, qlogits))

    def test_invalid_labels_shapes_or_features_refuse(self):
        import torch
        from ichart_recognition_ml.research.personal_adaptability import adapted_scores
        x, logits, labels, q, qlogits = self.matrices()
        for invalid in (torch.tensor([0, 1, 2, 3]), torch.tensor([0, 0, -1, 2]), labels.float(), labels[:2]):
            with self.assertRaises(ValueError):
                adapted_scores(x, logits, invalid, q, qlogits)
        for invalid in (x * 0, x * float("nan"), x[:, :2]):
            with self.assertRaises(ValueError):
                adapted_scores(invalid, logits, labels, q, qlogits)

    @staticmethod
    def samples():
        from ichart_recognition_ml.features import InkPoint, InkStroke
        from ichart_recognition_ml.research.uji_personal import Sample
        return tuple(Sample(writer, session, label,
                            (InkStroke((InkPoint(0, 0), InkPoint(3 + session, i + 2), InkPoint(12, 0))),))
                     for writer in ("trn_UPV_W01", "trn_UPV_W02")
                     for session in (1, 2) for i, label in enumerate(("A", "B", "C")))

    def test_episode_plan_is_deterministic_role_separated_and_label_agnostic(self):
        from dataclasses import replace
        from ichart_recognition_ml.research.personal_adaptability import plan_episodes
        samples = self.samples()
        writers, vocabulary = ("trn_UPV_W01", "trn_UPV_W02"), ("A", "B", "C")
        pixels = [str(i) for i in range(len(samples))]
        plan = plan_episodes(samples, writers, vocabulary, pixels, epochs=2, support_count=2)
        self.assertEqual(plan, plan_episodes(samples, writers, vocabulary, pixels, epochs=2, support_count=2))
        self.assertEqual(len(plan), 8)
        for episode in plan:
            self.assertEqual(len(episode.support), 2)
            self.assertTrue(set(episode.support).isdisjoint(episode.queries))
            self.assertTrue(all(samples[i].writer == episode.writer and samples[i].session == episode.support_session for i in episode.support))
            self.assertTrue(all(samples[i].writer == episode.writer and samples[i].session != episode.support_session for i in episode.queries))
        for bad in (tuple(replace(s, writer="tst_UPV_W01") for s in samples), samples[:-1], samples + samples[:1]):
            with self.assertRaises(ValueError):
                plan_episodes(bad, writers, vocabulary, pixels[:len(bad)], epochs=2, support_count=2)

    def test_episode_copies_removed_before_outer_training_loss(self):
        from dataclasses import replace
        from ichart_recognition_ml.research.personal_adaptability import plan_episodes
        samples = list(self.samples())
        samples[3] = replace(samples[3], strokes=samples[0].strokes)
        plan = plan_episodes(tuple(samples), ("trn_UPV_W01", "trn_UPV_W02"), ("A", "B", "C"),
                             [str(i) for i in range(len(samples))], epochs=1, support_count=3)
        first = next(e for e in plan if e.writer == "trn_UPV_W01" and e.support_session == 1)
        self.assertIn(3, first.excluded_copies)
        self.assertNotIn(3, first.queries)

    def test_query_answers_cannot_change_predictions_and_unknown_classes_remain_competitors(self):
        from dataclasses import replace
        import numpy as np
        from ichart_recognition_ml.research.personal_adaptability import predict_task, sparse_labels
        samples = self.samples()
        features = np.tile(np.eye(3), (4, 1))
        logits = features * 5
        first = predict_task(samples, features, logits, ("A", "B", "C"), ("A",))
        changed = tuple(replace(s, label="WRONG") if s.session == 2 else s for s in samples)
        self.assertEqual(first, predict_task(changed, features, logits, ("A", "B", "C"), ("A",)))
        self.assertEqual({row["personal"] for row in first}, {"A", "B", "C"})
        self.assertTrue(all(len(row["personalRanks"]) == 3 for row in first))
        vocabulary = tuple(chr(65 + i) for i in range(26))
        self.assertEqual(sparse_labels(vocabulary), sparse_labels(tuple(reversed(vocabulary))))
        self.assertEqual(len(sparse_labels(vocabulary)), 16)

    def test_novelty_exclusions_are_shared_and_include_training_normalized_copies(self):
        from dataclasses import replace
        from ichart_recognition_ml.research.personal_adaptability import novelty_exclusions
        samples = self.samples()
        training = (replace(samples[3], writer="trn_UPV_W03"),)
        result = novelty_exclusions(samples, [str(i) for i in range(len(samples))], training, ["other"])
        self.assertIn("encoder_training_normalized_copy", result[samples[3].identity])
        self.assertEqual(len(result), 6)

    def test_fine_tuning_keeps_original_model_and_batchnorm_statistics_unchanged(self):
        from pathlib import Path
        import tempfile
        from unittest.mock import patch
        import torch
        from ichart_recognition_ml.research.personal_adaptability import Episode, fit_arm
        from ichart_recognition_ml.research.personal_visual_encoder import PersonalVisualEncoder
        model = PersonalVisualEncoder(3).eval()
        original = {key: value.clone() for key, value in model.state_dict().items()}
        images = torch.randint(0, 256, (5, 1, 96, 256), dtype=torch.uint8)
        targets = torch.tensor([0, 1, 0, 1, 2])
        episode = Episode(1, "trn_UPV_W01", 1, (0, 1), (2, 3, 4), 29, ())
        with tempfile.TemporaryDirectory() as temporary, patch("ichart_recognition_ml.research.personal_adaptability.EPOCHS", 1):
            trained, history = fit_arm(model, images, targets, (episode,), personal=True, output=Path(temporary))
        self.assertEqual(len(history), 1)
        self.assertFalse(torch.equal(trained.projection.weight, model.projection.weight))
        for key, value in model.state_dict().items():
            torch.testing.assert_close(value, original[key], rtol=0, atol=0)
            if "running_" in key or "num_batches_tracked" in key:
                torch.testing.assert_close(trained.state_dict()[key], original[key], rtol=0, atol=0)
