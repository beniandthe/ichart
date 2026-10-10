import inspect
import unittest

import numpy as np
import torch
from torch.nn import functional as F

from ichart_recognition_ml.research import personal_centroid_transport as transport


class CentroidTransportTests(unittest.TestCase):
    def setUp(self):
        torch.set_num_threads(2)
        rng = torch.Generator().manual_seed(173)
        unit = lambda n: F.normalize(torch.randn(n, 6, dtype=torch.float64, generator=rng), dim=1)
        self.centroids, self.support, self.query = unit(97), unit(7), unit(8)
        self.labels = torch.tensor([0, 0, 1, 2, 3, 4, 6])
        self.logits = torch.randn(8, 97, dtype=torch.float64, generator=rng)
        self.model = transport.CentroidTransport()

    def nonzero(self):
        with torch.no_grad():
            self.model.scorer[-1].weight.copy_(torch.linspace(-.2, .3, 32, dtype=torch.float64)[None, :])
        return self.model

    def test_seed_initial_identity_empty_bit_identity_and_full_mass(self):
        other = transport.CentroidTransport()
        self.assertTrue(all(torch.equal(v, other.state_dict()[k]) for k, v in self.model.state_dict().items()))
        self.assertGreater(float(self.model.scorer[0].weight.abs().max()), 0.)
        self.assertTrue(torch.equal(self.model.adapted_logits(self.centroids, self.support, self.labels, self.query, self.logits), self.logits))
        self.nonzero()
        empty = self.model.adapted_logits(self.centroids, self.support[:0], self.labels[:0], self.query, self.logits)
        self.assertIs(empty, self.logits)
        probability = self.model.probabilities(self.centroids, self.support, self.labels, self.query, self.logits)
        self.assertEqual(probability.shape, (8, 97))
        torch.testing.assert_close(probability.sum(1), torch.ones(8, dtype=torch.float64))

    def test_nonzero_class_support_and_orthogonal_basis_equivariance(self):
        model = self.nonzero()
        expected = model.adapted_logits(self.centroids, self.support, self.labels, self.query, self.logits)
        permutation = torch.randperm(97, generator=torch.Generator().manual_seed(6))
        actual = model.adapted_logits(self.centroids[permutation], self.support, permutation.argsort()[self.labels],
            self.query, self.logits[:, permutation])
        torch.testing.assert_close(actual, expected[:, permutation], rtol=1e-12, atol=1e-13)
        order = torch.tensor([6, 0, 4, 2, 1, 5, 3])
        torch.testing.assert_close(expected, model.adapted_logits(self.centroids, self.support[order], self.labels[order], self.query, self.logits))
        basis = torch.linalg.qr(torch.randn(6, 6, dtype=torch.float64, generator=torch.Generator().manual_seed(4))).Q
        torch.testing.assert_close(expected, model.adapted_logits(self.centroids @ basis, self.support @ basis,
            self.labels, self.query @ basis, self.logits), rtol=1e-12, atol=1e-13)
        self.assertTrue(torch.allclose((expected - self.logits).mean(1), torch.zeros(8, dtype=torch.float64), atol=1e-14))

    def test_exact_duplicate_lessons_and_label_balanced_style(self):
        moved, style = transport.transported_centroids(self.centroids, self.support, self.labels)
        manual = torch.stack([self.support[self.labels == label].mean(0) - self.centroids[label]
            for label in self.labels.unique().tolist()]).mean(0)
        torch.testing.assert_close(style, manual)
        copied = torch.tensor([0, 1, 2, 3, 4, 5, 6, 0, 0, 0, 2])
        copied_moved, copied_style = transport.transported_centroids(self.centroids, self.support[copied], self.labels[copied])
        torch.testing.assert_close(moved, copied_moved, rtol=0, atol=0)
        torch.testing.assert_close(style, copied_style, rtol=0, atol=0)
        model = self.nonzero()
        torch.testing.assert_close(model.probabilities(self.centroids, self.support, self.labels, self.query, self.logits),
            model.probabilities(self.centroids, self.support[copied], self.labels[copied], self.query, self.logits), rtol=0, atol=0)

    def test_exact_class_ties_and_untaught_ordering_can_change(self):
        centroids = torch.tensor([[1., 0.]] * 97, dtype=torch.float64)
        centroids[1] = torch.tensor([0., 1.]); centroids[2] = torch.tensor([-1., 0.])
        support = torch.tensor([[.8, .6]], dtype=torch.float64)
        query = torch.tensor([[-.2, np.sqrt(.96)]], dtype=torch.float64)
        logits = torch.full((1, 97), -15., dtype=torch.float64); logits[0, 1:3] = torch.tensor([0., .1])
        with torch.no_grad():
            self.model.scorer[0].weight.zero_(); self.model.scorer[0].bias.zero_()
            self.model.scorer[0].weight[0, 3] = 1.; self.model.scorer[-1].weight.zero_()
            self.model.scorer[-1].weight[0, 0] = -10.
        result = self.model.adapted_logits(centroids, support, torch.tensor([0]), query, logits)
        self.assertEqual(int(logits.argmax(1)[0]), 2)
        self.assertEqual(int(result.argmax(1)[0]), 1)  # Target1 was never taught.
        centroids[3] = centroids[1]; logits[0, 3] = logits[0, 1]
        result = self.model.adapted_logits(centroids, support, torch.tensor([0]), query, logits)
        self.assertEqual(float(result[0, 1]), float(result[0, 3]))
        permutation = torch.arange(97); permutation[1], permutation[3] = 3, 1
        torch.testing.assert_close(self.model.adapted_logits(centroids[permutation], support, permutation.argsort()[torch.tensor([0])],
            query, logits[:, permutation]), result[:, permutation], rtol=1e-12, atol=1e-13)

    def test_explicit_zero_transport_rejection_and_invalid_inputs(self):
        centroids = torch.tensor([[1., 0.]] * 97, dtype=torch.float64)
        centroids[0] = torch.tensor([.5, np.sqrt(.75)], dtype=torch.float64)
        support = torch.tensor([[-.5, np.sqrt(.75)]], dtype=torch.float64)
        with self.assertRaises(ValueError):
            self.model.adapted_logits(centroids, support, torch.tensor([0]), support, torch.zeros(1, 97, dtype=torch.float64))
        for c, s, labels, q, logits in ((self.centroids.float(), self.support, self.labels, self.query, self.logits),
            (self.centroids, self.support * 2, self.labels, self.query, self.logits),
            (self.centroids, self.support, self.labels + 97, self.query, self.logits),
            (self.centroids, self.support, self.labels, self.query, self.logits[:, :96])):
            with self.assertRaises(ValueError): self.model.adapted_logits(c, s, labels, q, logits)

    def test_independent_objective_arithmetic_and_symmetric_tied_margin(self):
        g = np.full((4, 97), -15.); c = g.copy(); wrong = g.copy()
        g[:, :2] = np.log([[.8, .2], [.4, .6], [.2, .8], [.5, .5]])
        c[:, :2] = np.log([[.7, .3], [.9, .1], [.5, .5], [.8, .2]])
        wrong[:, :2] = np.log([[.6, .4], [.2, .8], [.1, .9], [.3, .7]])
        targets, taught = torch.tensor([0, 0, 1, 1]), torch.tensor([True, True, False, False])
        loss, parts = transport.training_objective(torch.tensor(c), torch.tensor(g), torch.tensor(wrong), targets, taught)
        logsoft = lambda x: x - x.max(1)[:, None] - np.log(np.exp(x - x.max(1)[:, None]).sum(1))[:, None]
        nll = -logsoft(c)[np.arange(4), targets.numpy()]
        balanced = .5 * nll[:2].mean() + .5 * nll[2:].mean()
        margin = np.mean([max(0., g[i, t] - max(np.delete(g[i], t)) - c[i, t] + max(np.delete(c[i], t)))
            for i, t in enumerate(targets.tolist()) if g[i, t] == g[i].max()])
        kl = np.mean(np.sum(np.exp(logsoft(g)) * (logsoft(g) - logsoft(wrong)), axis=1))
        for name, expected in (("balancedCE", balanced), ("preservationMargin", margin), ("unrelatedSupportKL", kl)):
            self.assertAlmostEqual(float(parts[name]), float(expected), places=13)
        self.assertAlmostEqual(float(loss), balanced + margin + kl, places=13)
        perm = torch.arange(97); perm[0], perm[1] = 1, 0
        other, _ = transport.training_objective(torch.tensor(c)[:, perm], torch.tensor(g)[:, perm],
            torch.tensor(wrong)[:, perm], perm.argsort()[targets], taught)
        torch.testing.assert_close(loss, other, rtol=1e-13, atol=1e-13)
        none_correct = torch.tensor([96, 95, 94, 93])
        _, none_parts = transport.training_objective(torch.tensor(c), torch.tensor(g), torch.tensor(wrong), none_correct, taught)
        self.assertEqual(float(none_parts["preservationMargin"]), 0.)

    def test_real_synthetic_fit_nonzero_gradients_without_frozen_input_updates(self):
        for frozen_input in (self.centroids, self.support, self.query, self.logits):
            frozen_input.requires_grad_(True)
        targets = torch.tensor([0, 1, 2, 10, 11, 12, 13, 14]); taught = torch.isin(targets, self.labels)
        unrelated = -self.support
        before = {k: v.detach().clone() for k, v in self.model.state_dict().items()}
        optimizer = torch.optim.AdamW(self.model.parameters(), lr=.01, weight_decay=.0001)
        losses = []
        for _ in range(25):
            candidate = self.model.adapted_logits(self.centroids, self.support, self.labels, self.query, self.logits)
            control = self.model.adapted_logits(self.centroids, unrelated, self.labels, self.query, self.logits)
            loss, _ = transport.training_objective(candidate, self.logits, control, targets, taught)
            optimizer.zero_grad(); loss.backward()
            self.assertTrue(all(p.grad is not None and torch.isfinite(p.grad).all() for p in self.model.parameters()))
            optimizer.step(); losses.append(float(loss.detach()))
        self.assertLess(losses[-1], losses[0])
        for key in ("scorer.0.weight", "scorer.0.bias", "scorer.2.weight"):
            self.assertFalse(torch.equal(before[key], self.model.state_dict()[key]))
        self.assertLess(abs(float(self.model.scorer[-1].bias.detach())), 1e-12)  # Shared bias cancels.
        self.assertTrue(all(x.grad is None for x in (self.centroids, self.support, self.query, self.logits)))

    def test_forward_is_answer_and_identity_blind_and_protocol_bound(self):
        self.assertEqual(tuple(inspect.signature(transport.CentroidTransport.adapted_logits).parameters),
            ("self", "centroids", "support", "labels", "query", "logits"))
        self.assertEqual(transport.code_identity()[transport.PROTOCOL], transport.PROTOCOL_SHA256)
        with self.assertRaises(ValueError):
            transport.training_objective(self.logits, self.logits, self.logits, torch.zeros(8, dtype=torch.long), torch.ones(8, dtype=torch.bool))


if __name__ == "__main__":
    unittest.main()
