import importlib.util
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalSupportMetricTests(unittest.TestCase):
    @staticmethod
    def _unit(torch, rows):
        value = torch.as_tensor(rows, dtype=torch.float64)
        return torch.nn.functional.normalize(value, dim=1)

    @staticmethod
    def _fixture(torch, query_count=4):
        generator = torch.Generator().manual_seed(800)
        anchors = torch.nn.functional.normalize(
            torch.randn(97, 128, generator=generator, dtype=torch.float64), dim=1,
        )
        queries = torch.nn.functional.normalize(
            torch.randn(query_count, 128, generator=generator, dtype=torch.float64), dim=1,
        )
        generic = torch.randn(query_count, 97, generator=generator, dtype=torch.float64)
        vocabulary = tuple(f"label-{index:02d}" for index in range(97))
        support = torch.stack((
            torch.nn.functional.normalize(anchors[1] + 0.2 * anchors[40], dim=0),
            torch.nn.functional.normalize(anchors[2] - 0.15 * anchors[41], dim=0),
            torch.nn.functional.normalize(anchors[1] + 0.1 * anchors[42], dim=0),
        ))
        labels = (vocabulary[1], vocabulary[2], vocabulary[1])
        return anchors, queries, generic, vocabulary, support, labels

    def test_empty_and_zero_residual_support_are_exact_generic(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import PersonalSupportMetric

        anchors, queries, generic, vocabulary, _, _ = self._fixture(torch)
        model = PersonalSupportMetric()
        for support, labels in (
            (anchors[:0], ()),
            (anchors[[1, 2]], (vocabulary[1], vocabulary[2])),
        ):
            output = model(queries, generic, anchors, vocabulary, support, labels)
            self.assertTrue(torch.equal(output.candidate_logits, generic))
            self.assertTrue(torch.equal(output.delta_metric, torch.zeros_like(output.delta_metric)))
            self.assertEqual(output.effective_support_count, 0)

    def test_seed_initialization_is_exact_identity_but_retains_gradient_path(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import (
            PersonalSupportMetric,
            support_metric_loss,
        )

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        model = PersonalSupportMetric()
        output = model(queries, generic, anchors, vocabulary, support, labels)
        self.assertTrue(torch.equal(output.candidate_logits, generic))
        targets = torch.tensor([1, 7, 2, 9], dtype=torch.long)
        loss = support_metric_loss(output, targets)
        loss.total.backward()
        self.assertGreater(
            torch.linalg.vector_norm(model.scorer[-1].weight.grad).detach().item(), 0,
        )

    def test_zero_initialized_model_learns_a_finite_nonzero_metric_update(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import (
            PersonalSupportMetric,
            support_metric_loss,
        )

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        frozen = tuple(value.clone() for value in (anchors, queries, generic, support))
        model = PersonalSupportMetric()
        initial_state = {
            key: value.detach().clone() for key, value in model.state_dict().items()
        }
        optimizer = torch.optim.AdamW(model.parameters(), lr=0.01, weight_decay=0.0)
        targets = torch.tensor([1, 7, 2, 9], dtype=torch.long)
        for _ in range(4):
            optimizer.zero_grad(set_to_none=True)
            output = model(queries, generic, anchors, vocabulary, support, labels)
            loss = support_metric_loss(output, targets)
            self.assertTrue(bool(torch.isfinite(loss.total)))
            loss.total.backward()
            optimizer.step()

        learned = model(queries, generic, anchors, vocabulary, support, labels)
        self.assertGreater(torch.linalg.vector_norm(learned.delta_metric).detach().item(), 0)
        self.assertGreater(
            torch.linalg.vector_norm(learned.candidate_logits - generic).detach().item(), 0,
        )
        self.assertTrue(bool(torch.isfinite(learned.candidate_logits).all()))
        self.assertTrue(any(
            not torch.equal(value, initial_state[key])
            for key, value in model.state_dict().items()
        ))
        for value, expected in zip((anchors, queries, generic, support), frozen, strict=True):
            self.assertTrue(torch.equal(value, expected))

    def test_support_order_duplicates_and_class_axis_permutations_are_equivariant(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import PersonalSupportMetric

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        model = PersonalSupportMetric()
        with torch.no_grad():
            model.scorer[-1].weight.fill_(0.015)
            model.scorer[-1].bias.fill_(0.2)
        original = model(queries, generic, anchors, vocabulary, support, labels)
        order = torch.tensor([2, 0, 1])
        reordered = model(
            queries, generic, anchors, vocabulary, support[order], tuple(labels[i] for i in order),
        )
        duplicated = model(
            queries, generic, anchors, vocabulary,
            torch.cat((support, support[[0]])), labels + (labels[0],),
        )
        self.assertTrue(torch.equal(original.delta_metric, reordered.delta_metric))
        self.assertTrue(torch.equal(original.candidate_logits, reordered.candidate_logits))
        self.assertTrue(torch.equal(original.delta_metric, duplicated.delta_metric))
        self.assertTrue(torch.equal(original.candidate_logits, duplicated.candidate_logits))

        permutation = torch.randperm(97, generator=torch.Generator().manual_seed(29))
        permuted_words = tuple(vocabulary[i] for i in permutation)
        permuted = model(
            queries, generic[:, permutation], anchors[permutation], permuted_words, support, labels,
        )
        self.assertTrue(torch.equal(original.delta_metric, permuted.delta_metric))
        self.assertTrue(torch.equal(permuted.candidate_logits, original.candidate_logits[:, permutation]))

    def test_metric_is_bounded_and_acts_only_in_residual_span(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import (
            METRIC_DELTA_BOUND,
            PersonalSupportMetric,
        )

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        model = PersonalSupportMetric()
        with torch.no_grad():
            model.scorer[-1].bias.fill_(3.0)
        output = model(queries, generic, anchors, vocabulary, support, labels)
        self.assertTrue(torch.equal(output.delta_metric, output.delta_metric.T))
        self.assertTrue(torch.equal(output.metric, output.metric.T))
        eigenvalues = torch.linalg.eigvalsh(output.metric)
        self.assertGreaterEqual(
            eigenvalues.min().detach().item(), 1 - METRIC_DELTA_BOUND - 1e-12,
        )
        self.assertLessEqual(
            eigenvalues.max().detach().item(), 1 + METRIC_DELTA_BOUND + 1e-12,
        )
        residuals = torch.stack((support[0] - anchors[1], support[1] - anchors[2], support[2] - anchors[1]))
        candidate = torch.arange(1, 129, dtype=torch.float64)
        basis = torch.linalg.svd(residuals, full_matrices=False).Vh.T
        orthogonal = candidate - basis @ (basis.T @ candidate)
        orthogonal /= torch.linalg.vector_norm(orthogonal)
        self.assertLessEqual(
            torch.linalg.vector_norm(output.delta_metric @ orthogonal).detach().item(), 1e-12,
        )
        self.assertGreater(torch.linalg.vector_norm(output.delta_metric).detach().item(), 0)

    def test_zero_residual_retains_its_class_balance_weight(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import PersonalSupportMetric

        anchors, queries, generic, vocabulary, support, _ = self._fixture(torch)
        model = PersonalSupportMetric()
        with torch.no_grad():
            model.scorer[-1].weight.zero_()
            model.scorer[-1].bias.fill_(1.0)
        active_only = model(
            queries, generic, anchors, vocabulary, support[[1]], (vocabulary[2],),
        )
        with_zero_class = model(
            queries, generic, anchors, vocabulary,
            torch.stack((support[1], anchors[1])), (vocabulary[2], vocabulary[1]),
        )
        self.assertEqual(with_zero_class.effective_support_count, 1)
        self.assertEqual(with_zero_class.support_class_indices, (1, 2))
        self.assertTrue(torch.equal(with_zero_class.delta_metric * 2, active_only.delta_metric))

    def test_full_vocabulary_competes_and_is_not_support_only(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import PersonalSupportMetric

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        generic.fill_(-4)
        generic[:, 80] = 20
        output = PersonalSupportMetric()(queries, generic, anchors, vocabulary, support, labels)
        self.assertEqual(output.candidate_logits.shape, (len(queries), 97))
        self.assertEqual(torch.argmax(output.candidate_logits, dim=1).tolist(), [80] * len(queries))
        self.assertNotIn(80, output.support_class_indices)

    def test_conflicts_and_malformed_frozen_inputs_fail_closed(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import PersonalSupportMetric

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        model = PersonalSupportMetric()
        cases = [
            dict(support_embeddings=torch.stack((support[0], support[0])),
                 support_labels=(vocabulary[1], vocabulary[2])),
            dict(support_embeddings=support * 2),
            dict(query_embeddings=queries.float()),
            dict(anchors=anchors.clone().index_fill(0, torch.tensor([0]), float("nan"))),
            dict(generic_logits=generic[:, :-1]),
            dict(vocabulary=vocabulary[:-1]),
            dict(support_labels=(vocabulary[1], "missing", vocabulary[1])),
        ]
        base = dict(query_embeddings=queries, generic_logits=generic, anchors=anchors,
                    vocabulary=vocabulary, support_embeddings=support, support_labels=labels)
        for mutation in cases:
            with self.subTest(mutation=tuple(mutation)):
                with self.assertRaises(ValueError):
                    model(**{**base, **mutation})
        model.float()
        with self.assertRaisesRegex(ValueError, "CPU Float64"):
            model(**base)

    def test_loss_uses_truth_only_after_forward_and_never_updates_frozen_inputs(self):
        import torch
        from ichart_recognition_ml.research.personal_support_metric import (
            PersonalSupportMetric,
            support_metric_loss,
        )

        anchors, queries, generic, vocabulary, support, labels = self._fixture(torch)
        anchors.requires_grad_(); queries.requires_grad_(); generic.requires_grad_(); support.requires_grad_()
        model = PersonalSupportMetric()
        first = model(queries, generic, anchors, vocabulary, support, labels)
        first_bytes = first.candidate_logits.detach().clone()
        targets = torch.tensor([1, 7, 2, 9], dtype=torch.long)
        changed_targets = torch.tensor([2, 7, 1, 9], dtype=torch.long)
        first_loss = support_metric_loss(first, targets)
        second_loss = support_metric_loss(first, changed_targets)
        self.assertTrue(torch.equal(first.candidate_logits, first_bytes))
        self.assertNotEqual(
            first_loss.total.detach().item(), second_loss.total.detach().item(),
        )
        first_loss.total.backward()
        self.assertIsNone(anchors.grad)
        self.assertIsNone(queries.grad)
        self.assertIsNone(generic.grad)
        self.assertIsNone(support.grad)
        self.assertGreater(
            torch.linalg.vector_norm(model.scorer[-1].weight.grad).detach().item(), 0,
        )

        # Once the zero-initialized final layer moves, matcher loss reaches the
        # preceding DeepSets projection while frozen inputs remain detached.
        with torch.no_grad():
            model.scorer[-1].weight.fill_(0.01)
        model.zero_grad(set_to_none=True)
        moved = model(queries, generic, anchors, vocabulary, support, labels)
        support_metric_loss(moved, targets).total.backward()
        self.assertGreater(
            torch.linalg.vector_norm(model.scorer[0].weight.grad).detach().item(), 0,
        )

        with self.assertRaisesRegex(ValueError, "taught and untaught"):
            support_metric_loss(moved, torch.tensor([1, 2, 1, 2], dtype=torch.long))


if __name__ == "__main__":
    unittest.main()
