import inspect
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from torch.nn import functional as F

from ichart_recognition_ml.research.personal_support_retrieval import (
    SupportRetrieval, balanced_loss, episode_plan, fit, load_fitted_learner,
)


class SupportRetrievalTests(unittest.TestCase):
    def setUp(self):
        torch.set_num_threads(1)
        torch.manual_seed(29)
        self.model = SupportRetrieval().double()
        # Exercise invariants with nonzero learned layers, not only the safe
        # initialization whose relation residual and gate weights are zero.
        with torch.no_grad():
            for parameter in self.model.parameters():
                parameter.uniform_(-0.3, 0.3)
        self.sf = F.normalize(torch.randn(5, 8, dtype=torch.float64), dim=1)
        self.qf = F.normalize(torch.randn(4, 8, dtype=torch.float64), dim=1)
        self.sp = torch.randn(5, 7, dtype=torch.float64).softmax(1)
        self.qp = torch.randn(4, 7, dtype=torch.float64).softmax(1)
        self.labels = torch.tensor([0, 1, 2, 1, 3])

    def probabilities(self, sf=None, sp=None, labels=None, qf=None, qp=None):
        return self.model.probabilities(self.sf if sf is None else sf, self.sp if sp is None else sp,
                                        self.labels if labels is None else labels,
                                        self.qf if qf is None else qf, self.qp if qp is None else qp)

    def test_complete_normalized_finite_distribution(self):
        result = self.probabilities()
        self.assertEqual(result.shape, (4, 7))
        self.assertTrue(torch.isfinite(result).all())
        torch.testing.assert_close(result.sum(1), torch.ones(4, dtype=torch.float64), atol=1e-12, rtol=0)
        self.assertTrue((result > 0).all())

    def test_empty_support_is_exact_same_tensor(self):
        result = self.probabilities(sf=self.sf[:0], sp=self.sp[:0], labels=self.labels[:0])
        self.assertIs(result, self.qp)
        self.assertEqual(result.numpy().tobytes(), self.qp.numpy().tobytes())

    def test_class_permutation_equivariance(self):
        order = torch.tensor([5, 2, 1, 6, 0, 3, 4])
        inverse = torch.argsort(order)
        expected = self.probabilities()[:, order]
        actual = self.probabilities(sp=self.sp[:, order], labels=inverse[self.labels], qp=self.qp[:, order])
        torch.testing.assert_close(actual, expected, atol=1e-12, rtol=0)

    def test_support_permutation_invariance(self):
        order = torch.tensor([3, 1, 4, 0, 2])
        actual = self.probabilities(sf=self.sf[order], sp=self.sp[order], labels=self.labels[order])
        torch.testing.assert_close(actual, self.probabilities(), atol=1e-12, rtol=0)

    def test_identical_duplicated_lesson_invariance(self):
        expected = self.probabilities()
        # Label1 already has two distinct shapes: repeat only one of them.
        order = torch.tensor([0, 1, 2, 3, 4, 1, 1])
        actual = self.probabilities(sf=self.sf[order], sp=self.sp[order], labels=self.labels[order])
        torch.testing.assert_close(actual, expected, atol=1e-12, rtol=0)

    def test_safe_initialization(self):
        model = SupportRetrieval().double()
        self.assertTrue(torch.equal(model.relation[-1].weight, torch.zeros_like(model.relation[-1].weight)))
        self.assertTrue(torch.equal(model.gate[-1].weight, torch.zeros_like(model.gate[-1].weight)))
        self.assertEqual(float(model.gate[-1].bias.detach()), -4)

    def test_untaught_relative_order_is_preserved(self):
        output = self.probabilities()
        untaught = [4, 5, 6]
        for row in range(4):
            self.assertEqual(torch.argsort(output[row, untaught]).tolist(), torch.argsort(self.qp[row, untaught]).tolist())
        ratios = output[:, untaught] / self.qp[:, untaught]
        torch.testing.assert_close(ratios, ratios[:, :1].expand_as(ratios), atol=1e-12, rtol=0)

    def test_no_query_truth_or_learned_class_axis(self):
        self.assertEqual(list(inspect.signature(SupportRetrieval.probabilities).parameters),
                         ["self", "support_features", "support_probabilities", "support_labels", "query_features", "query_probabilities"])
        self.assertTrue(all(97 not in p.shape and 128 not in p.shape for p in self.model.parameters()))

    def test_basis_rotation_invariance(self):
        rotation, _ = torch.linalg.qr(torch.randn(8, 8, dtype=torch.float64))
        actual = self.probabilities(sf=self.sf @ rotation, qf=self.qf @ rotation)
        torch.testing.assert_close(actual, self.probabilities(), atol=1e-12, rtol=0)

    def test_rejects_nonfinite_and_wrong_contract(self):
        bad = self.qp.clone()
        bad[0, 0] = float("nan")
        for change in ({"qp": bad}, {"qp": self.qp * 0.5}, {"sf": self.sf * 2},
                       {"labels": self.labels.double()}, {"labels": torch.tensor([0, 1, 2, 7, 3])},
                       {"qp": self.qp.float()}, {"sp": self.sp[:, :6]}):
            with self.subTest(change=list(change)):
                with self.assertRaises(ValueError):
                    self.probabilities(**change)

    def test_actual_nonzero_gradient_and_weight_updates(self):
        optimizer = torch.optim.AdamW(self.model.parameters(), lr=0.001, weight_decay=0.0001)
        targets, taught = torch.tensor([0, 1, 4, 6]), torch.tensor([True, True, False, False])
        initial = [p.detach().clone() for p in self.model.parameters()]
        before = float(balanced_loss(self.probabilities(), targets, taught).detach())
        for _ in range(15):
            loss = balanced_loss(self.probabilities(), targets, taught)
            optimizer.zero_grad()
            loss.backward()
            self.assertTrue(all(p.grad is not None and torch.isfinite(p.grad).all() for p in self.model.parameters()))
            self.assertGreater(max(float(p.grad.abs().max()) for p in self.model.parameters()), 0)
            optimizer.step()
        self.assertLess(float(balanced_loss(self.probabilities(), targets, taught).detach()), before)
        self.assertTrue(all(not torch.equal(before, after) for before, after in zip(initial, self.model.parameters())))

    def test_balanced_loss_and_missing_strata(self):
        targets, taught = torch.tensor([0, 1, 4, 6]), torch.tensor([True, True, False, False])
        actual = balanced_loss(self.qp, targets, taught)
        expected = -0.5 * self.qp[[0, 1], [0, 1]].log().mean() - 0.5 * self.qp[[2, 3], [4, 6]].log().mean()
        torch.testing.assert_close(actual, expected)
        with self.assertRaises(ValueError):
            balanced_loss(self.qp, targets, torch.ones(4, dtype=torch.bool))


class EpisodePlanTests(unittest.TestCase):
    @staticmethod
    def source():
        vocabulary = tuple(chr(33 + i) for i in range(97))
        rows = [{"writer": f"trn_W{writer:02d}", "session": session, "label": label,
                 "rawRasterSHA256": f"raw:{writer}:{session}:{label}",
                 "storedRasterSHA256": f"stored:{writer}:{session}:{label}",
                 "trajectorySHA256": f"ink:{writer}:{session}:{label}",
                 "storedTrajectorySHA256": f"stored-ink:{writer}:{session}:{label}",
                 "genericFitCopyReasons": []}
                for writer in range(32) for session in (1, 2) for label in vocabulary]
        return rows, vocabulary

    def test_complete_deterministic_plan_and_disjoint_sessions(self):
        rows, vocabulary = self.source()
        plan = episode_plan(rows, vocabulary, epochs=1)
        self.assertEqual(len(plan), 128)
        self.assertEqual(plan, episode_plan(rows, vocabulary, epochs=1))
        self.assertEqual({len(p["support"]) for p in plan}, {10, 21})
        for p in plan:
            self.assertEqual(len(p["queries"]), 97)
            self.assertTrue(all(rows[i]["writer"] == p["writer"] and rows[i]["session"] == p["session"] for i in p["support"]))
            self.assertTrue(all(rows[i]["writer"] == p["writer"] and rows[i]["session"] == 3 - p["session"] for i in p["queries"]))

    def test_source_only_unavailability_and_copy_exclusion(self):
        rows, vocabulary = self.source()
        rows[0]["storedRasterSHA256"] = None
        rows[0]["storedTrajectorySHA256"] = None
        rows[97]["genericFitCopyReasons"] = ["generic-fit-raw-raster-copy"]
        plan = episode_plan(rows, vocabulary, epochs=1)
        self.assertTrue(all(0 not in p["support"] for p in plan))
        relevant = [p for p in plan if p["writer"] == "trn_W00" and p["session"] == 1]
        self.assertTrue(all(97 not in p["queries"] and {"index": 97, "reasons": ["generic-fit-raw-raster-copy"]} in p["exclusions"] for p in relevant))

    def test_rejects_answer_dependent_reasons_or_half_available_shapes(self):
        for reason in (["model-wrong"], ["generic-fit-raw-raster-copy"] * 2):
            rows, vocabulary = self.source()
            rows[0]["genericFitCopyReasons"] = reason
            with self.assertRaises(ValueError):
                episode_plan(rows, vocabulary, epochs=1)
        rows, vocabulary = self.source()
        rows[0]["storedTrajectorySHA256"] = None
        with self.assertRaises(ValueError):
            episode_plan(rows, vocabulary, epochs=1)

    def test_rejects_incomplete_or_nontraining_source(self):
        rows, vocabulary = self.source()
        with self.assertRaises(ValueError):
            episode_plan(rows[:-1], vocabulary)
        rows[0]["writer"] = "tst_W00"
        with self.assertRaises(ValueError):
            episode_plan(rows, vocabulary)


class FitBindingTests(unittest.TestCase):
    def test_synthetic_fit_save_reload_and_binding_tamper(self):
        """Real 1280 learner updates; synthetic loader, not public accuracy."""
        from ichart_recognition_ml.research import personal_support_crossfit as crossfit
        from ichart_recognition_ml.research import personal_support_retrieval as learner
        rows, vocabulary = EpisodePlanTests.source()
        raw = np.zeros((6208, 128), dtype=np.float32)
        raw[:, 0] = 1
        arrays = {"raw_features": raw, "stored_features": raw.copy(),
                  "raw_logits": np.zeros((6208, 97), dtype=np.float32),
                  "stored_logits": np.zeros((6208, 97), dtype=np.float32)}
        plans = [{"epoch": epoch, "support": [0], "queries": [0, 1]} for epoch in range(1, 11) for _ in range(128)]
        with tempfile.TemporaryDirectory(prefix="ichart-retrieval-fit-") as temporary:
            source = Path(temporary).resolve() / "crossfit"
            source.mkdir()
            for filename in ("fit-receipt.json", "metadata.json", "features.npz"):
                (source / filename).write_bytes(b"synthetic-parent")
            output = Path(temporary).resolve() / "learner"
            with patch.object(crossfit, "load_crossfit_bundle", return_value=(arrays, rows, {"vocabulary": vocabulary})), \
                 patch.object(learner, "episode_plan", return_value=plans), patch("builtins.print"):
                receipt = fit(source, output)
            self.assertEqual(receipt["updates"], 1280)
            model, reloaded = load_fitted_learner(output)
            self.assertEqual(receipt, reloaded)
            self.assertTrue(all(torch.isfinite(p).all() for p in model.parameters()))
            self.assertEqual(set(receipt["crossfitBinding"]), {"receiptSHA256", "metadataSHA256", "featuresSHA256"})
            (output / "crossfit-binding.json").write_bytes(b"{}")
            with self.assertRaisesRegex(ValueError, "Learner binding changed"):
                load_fitted_learner(output)


if __name__ == "__main__":
    unittest.main()
