import importlib.util
import json
import math
import unittest


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalSupportActionSelectorTests(unittest.TestCase):
    @staticmethod
    def _unit(axis):
        row = [0.0] * 128
        row[axis] = 1.0
        return row

    def _feature(self, *, matcher=(1.0, 4.0, 0.0), labels=("A", "B"),
                 prototypes=None, vocabulary=("A", "B", "X"), baseline="A", proposal="B"):
        from ichart_recognition_ml.research.personal_support_action_selector import feature_row

        prototypes = prototypes or (self._unit(0), self._unit(1))
        return feature_row(
            (3.0, 2.0, 0.0), matcher, self._unit(1), prototypes,
            vocabulary, labels, {"A", "B"}, baseline, proposal,
        )

    def test_feature_row_is_label_and_prototype_permutation_equivariant(self):
        from ichart_recognition_ml.research.personal_support_action_selector import FEATURE_NAMES, feature_row

        original = self._feature()
        renamed = feature_row(
            (3.0, 2.0, 0.0), (1.0, 4.0, 0.0), self._unit(1),
            (self._unit(0), self._unit(1)), ("q", "r", "z"), ("q", "r"),
            {"q", "r"}, "q", "r",
        )
        permuted = self._feature(
            matcher=(4.0, 1.0, 0.0), labels=("B", "A"),
            prototypes=(self._unit(1), self._unit(0)),
        )
        self.assertEqual(len(original), len(FEATURE_NAMES))
        self.assertEqual(original, renamed)
        self.assertEqual(original, permuted)
        self.assertEqual(original[5], 0.0)
        self.assertGreater(original[6], 0.0)
        self.assertGreater(original[8], 0.999)

    def test_action_target_distinguishes_help_harm_and_neutral_without_identity(self):
        from ichart_recognition_ml.research.personal_support_action_selector import (
            HARM, HELP, NEUTRAL, action_target,
        )

        self.assertEqual(action_target("A", "B", "B"), HELP)
        self.assertEqual(action_target(None, "A", "B"), HARM)
        self.assertEqual(action_target("B", "A", "B"), HARM)
        self.assertEqual(action_target("X", "A", "B"), NEUTRAL)
        self.assertEqual(action_target("B", "B", "B"), NEUTRAL)
        self.assertEqual(action_target("renamed-a", "renamed-b", "renamed-b"), HELP)
        with self.assertRaises(ValueError):
            action_target("A", "B", "")

    def test_missing_tied_nonfinite_or_ineligible_proposal_preserves_baseline(self):
        from ichart_recognition_ml.research.personal_support_action_selector import feature_row, select_output

        baseline = "A"
        self.assertEqual(select_output(baseline, None, (9.0, 0.0, 0.0), {"A", "B"}), baseline)
        self.assertEqual(select_output(baseline, "X", (9.0, 0.0, 0.0), {"A", "B"}), baseline)
        self.assertEqual(select_output(baseline, "B", (9.0, 9.0, 0.0), {"A", "B"}), baseline)
        self.assertEqual(select_output(baseline, "B", (float("nan"), 0.0, 0.0), {"A", "B"}), baseline)
        self.assertEqual(select_output(baseline, "B", (9.0, 0.0, 0.0), {"A", "B"}), "B")
        self.assertIsNone(select_output(None, "B", (0.0, 9.0, 0.0), {"A", "B"}))

        common = ((3.0, 2.0, 0.0), self._unit(1), (self._unit(0), self._unit(1)),
                  ("A", "B", "X"), ("A", "B"), {"A", "B"}, "A", "B")
        self.assertIsNone(feature_row(common[0], (4.0, 4.0, 0.0), *common[1:]))
        self.assertIsNone(feature_row(common[0], (1.0, 2.0, 3.0), *common[1:]))
        self.assertIsNone(feature_row(common[0], (1.0, float("nan"), 0.0), *common[1:]))
        self.assertIsNone(feature_row((0.0, 3.0, 0.0), (1.0, 4.0, 0.0), *common[1:]))

    def test_fit_rejects_missing_class_and_invalid_inputs(self):
        from ichart_recognition_ml.research.personal_support_action_selector import fit_action_selector

        rows = [[float(i + column) for column in range(10)] for i in range(3)]
        with self.assertRaisesRegex(ValueError, "Complete"):
            fit_action_selector(rows[:2], (0, 1), (1.0, 1.0))
        with self.assertRaisesRegex(ValueError, "Complete"):
            fit_action_selector(rows, (0, 1, 2), (1.0, 0.0, 1.0))
        invalid = [row[:] for row in rows]
        invalid[0][0] = float("nan")
        with self.assertRaisesRegex(ValueError, "Finite"):
            fit_action_selector(invalid, (0, 1, 2), (1.0, 1.0, 1.0))

    def test_inverse_exposure_weights_preserve_group_balance(self):
        from ichart_recognition_ml.research.personal_support_action_selector import fit_action_selector

        base = [
            [0.0] * 10,
            [1.0] * 10,
            [2.0] * 10,
        ]
        reference = fit_action_selector(base, (0, 1, 2), (1.0, 1.0, 1.0))
        duplicated = fit_action_selector(
            [base[0], base[0], base[1], base[2]],
            (0, 0, 1, 2),
            (0.5, 0.5, 1.0, 1.0),
        )
        self.assertEqual(reference["featureMean"], duplicated["featureMean"])
        self.assertEqual(reference["featureStd"], duplicated["featureStd"])
        self.assertEqual(reference["fit"]["classWeightSums"], [1.0, 1.0, 1.0])
        self.assertEqual(duplicated["fit"]["classWeightSums"], [1.0, 1.0, 1.0])
        for left, right in zip(reference["weights"], duplicated["weights"]):
            for a, b in zip(left, right):
                self.assertLess(abs(a - b), 1e-5)
        for a, b in zip(reference["bias"], duplicated["bias"]):
            self.assertLess(abs(a - b), 1e-5)

    def test_fit_and_prediction_are_finite_deterministic_and_serializable(self):
        from ichart_recognition_ml.research.personal_support_action_selector import (
            ACTION_NAMES, FEATURE_NAMES, action_logits, fit_action_selector, select_output,
        )

        rows = [
            [0.1 + 0.01 * column for column in range(10)],
            [0.8 - 0.02 * column for column in range(10)],
            [(-0.2 if column % 2 else 0.3) for column in range(10)],
            [0.4 + 0.005 * column for column in range(10)],
            [0.6 - 0.003 * column for column in range(10)],
            [(-0.1 if column % 3 else 0.2) for column in range(10)],
        ]
        targets = (0, 1, 2, 0, 1, 2)
        weights = (1.0, 2.0, 0.5, 1.5, 1.0, 2.0)
        first = fit_action_selector(rows, targets, weights)
        second = fit_action_selector(rows, targets, weights)
        self.assertEqual(first, second)
        self.assertEqual(first["featureNames"], list(FEATURE_NAMES))
        self.assertEqual(first["actionNames"], list(ACTION_NAMES))
        self.assertEqual(len(first["trace"]), 1000)
        self.assertTrue(all(math.isfinite(value) for value in first["trace"]))
        self.assertTrue(all(value > 0 for value in first["featureStd"]))
        json.dumps(first, allow_nan=False, sort_keys=True)
        logits = action_logits(rows, first)
        self.assertEqual(len(logits), len(rows))
        self.assertTrue(all(len(row) == 3 and all(math.isfinite(value) for value in row) for row in logits))
        expected = "B" if logits[0].index(max(logits[0])) == 0 and logits[0].count(max(logits[0])) == 1 else "A"
        self.assertEqual(select_output("A", "B", logits[0], {"A", "B"}), expected)


if __name__ == "__main__":
    unittest.main()
