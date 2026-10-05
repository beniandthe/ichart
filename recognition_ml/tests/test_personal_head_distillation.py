import contextlib
import io
import unittest

import torch

from ichart_recognition_ml.research.personal_head_distillation import fit_head, paired_changes, teacher_loss


class SharedHeadDistillationTests(unittest.TestCase):
    def setUp(self):
        torch.set_num_threads(2)
        torch.use_deterministic_algorithms(True)
        torch.manual_seed(11)

    def test_kl_matches_explicit_padded_distribution_and_temperature_squared(self):
        student = torch.tensor([[2., -1., 0.5], [-2., 3., 1.]], dtype=torch.float64, requires_grad=True)
        teacher = torch.tensor([[1., -0.5], [0., 4.]], dtype=torch.float64, requires_grad=True)
        p = (teacher.detach() / 2).softmax(1)
        expected = (p * (p.log() - (student / 2).log_softmax(1)[:, :2])).sum(1).mean() * 4
        loss = teacher_loss(student, teacher)
        torch.testing.assert_close(loss, expected, rtol=0, atol=1e-14)
        loss.backward()
        self.assertIsNone(teacher.grad)
        self.assertTrue(torch.isfinite(student.grad).all())
        # Extra student class competes in normalization and is suppressed, not ignored.
        self.assertTrue(torch.all(student.grad[:, 2] > 0))
        self.assertGreater(float(loss.detach()), float(teacher_loss(student[:, :2], teacher).detach()))

    def test_equal_teacher_and_student_have_zero_loss_and_gradient(self):
        logits = torch.tensor([[1., 2., -1.]], dtype=torch.float64, requires_grad=True)
        loss = teacher_loss(logits, logits.detach().clone())
        self.assertAlmostEqual(float(loss.detach()), 0., places=14)
        loss.backward()
        torch.testing.assert_close(logits.grad, torch.zeros_like(logits), rtol=0, atol=1e-14)

    def inputs(self):
        head = torch.nn.Linear(3, 3)
        uji = torch.tensor([[1., 0., 0.], [0., 1., 0.]], requires_grad=True)
        hasy = torch.tensor([[0., 0., 1.], [0., 0.1, 0.9]], requires_grad=True)
        teacher = torch.tensor([[5., -2.], [-2., 5.]], requires_grad=True)
        return head, uji, torch.tensor([0, 1]), hasy, torch.tensor([2, 2]), teacher

    def test_fit_is_deterministic_copies_head_and_detaches_all_feature_inputs(self):
        inputs = self.inputs()
        snapshots = [p.detach().clone() for p in inputs[0].parameters()]
        with contextlib.redirect_stdout(io.StringIO()):
            head, history = fit_head(*inputs, distilled=True, epochs=2, steps=3)
            again, repeated = fit_head(*inputs, distilled=True, epochs=2, steps=3)
        self.assertEqual(history, repeated)
        self.assertEqual(len(history), 2)
        self.assertTrue(all(row["updates"] == 3 for row in history))
        for initial, prior, fitted, repeat in zip(inputs[0].parameters(), snapshots, head.parameters(), again.parameters()):
            self.assertTrue(torch.equal(initial, prior))
            self.assertTrue(torch.equal(fitted, repeat))
            self.assertFalse(torch.equal(fitted, initial))
            self.assertIsNone(initial.grad)
        for tensor in (inputs[1], inputs[3], inputs[5]):
            self.assertIsNone(tensor.grad)

    def test_inference_mode_features_are_safe_to_fit_and_control_is_not_distilled(self):
        inputs = list(self.inputs())
        with torch.inference_mode():
            for i in (1, 3, 5):
                inputs[i] = inputs[i].detach().clone()
        with contextlib.redirect_stdout(io.StringIO()):
            control, ch = fit_head(*inputs, distilled=False, epochs=2, steps=3)
            distilled, dh = fit_head(*inputs, distilled=True, epochs=2, steps=3)
        self.assertAlmostEqual(ch[0]["loss"], ch[0]["supervisedLoss"], places=12)
        self.assertAlmostEqual(dh[0]["loss"], dh[0]["supervisedLoss"] + dh[0]["teacherLoss"], places=6)
        self.assertFalse(torch.equal(control.weight, distilled.weight))

    def test_invalid_teacher_and_missing_classes_are_rejected(self):
        inputs = self.inputs()
        cases = [(torch.ones((0, 3)), torch.ones((0, 2)), 2.),
                 (torch.ones((2, 3)), torch.ones((2, 4)), 2.),
                 (torch.full((2, 3), float("nan")), torch.ones((2, 2)), 2.),
                 (torch.ones((2, 3)), torch.ones((2, 2)), 0.),
                 (torch.ones((2, 3)), torch.ones((2, 2)), float("inf")),
                 (torch.ones((2, 3)), torch.ones((2, 2)), float("nan"))]
        for args in cases:
            with self.subTest(args=args), self.assertRaises(ValueError):
                teacher_loss(*args)
        for index, replacement in ((4, torch.tensor([1, 1])), (2, torch.tensor([0, 2])),
                                   (1, torch.ones((2, 4))), (5, torch.ones((3, 2)))):
            changed = list(inputs)
            changed[index] = replacement
            with self.assertRaises(ValueError):
                fit_head(*changed, distilled=True, epochs=1, steps=1)

    def test_paired_report_excludes_copies_and_detects_unpaired_evidence(self):
        before = [{"queryID": str(i), "writer": "writer", "intended": "A", "eligible": i < 2,
                   "exclusions": [] if i < 2 else ["copy"], "generic": label} for i, label in enumerate(("B", "A", "A"))]
        after = [{**r, "generic": label} for r, label in zip(before, ("A", "C", "B"))]
        report = paired_changes({"rows": before}, {"rows": after}, key="generic")
        self.assertEqual((report["count"], report["gains"], report["harms"]), (2, 1, 1))
        self.assertEqual(len(report["changes"]), 2)
        for invalid in (after[:-1], after + after[:1], [{**r, "intended": "B"} for r in after]):
            with self.assertRaises(ValueError):
                paired_changes({"rows": before}, {"rows": invalid}, key="generic")


if __name__ == "__main__":
    unittest.main()
