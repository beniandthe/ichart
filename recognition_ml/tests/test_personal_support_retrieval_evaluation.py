"""Synthetic adapter/scoring tests; no cached public data or fitted models."""
import copy
import importlib.util
import unittest
from unittest.mock import patch


@unittest.skipUnless(importlib.util.find_spec("torch") is not None, "Optional research dependencies required")
class SupportRetrievalEvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        from ichart_recognition_ml.research import personal_support_retrieval_evaluation as evaluation
        cls.e, cls.torch = evaluation, torch
        cls.vocabulary = sorted(list(evaluation.common.CATALOG) + [chr(0x100 + i) for i in range(76)])

    def row(self, sid, label="A", outcome="read", task="core10"):
        e = self.e
        feature = [1.0] + [0.0] * 127
        base = [1.0 / 97] * 97
        return {"task": task, "writerID": e.common.WRITERS[0], "sampleID": sid, "outcome": outcome,
                "failure": None if outcome == "read" else "cached-raster-no-read", "sourceCanonicalData": "opaque",
                "sourcePacketSHA256": "a" * 64, "rawRasterSHA256": "b" * 64 if outcome == "read" else None,
                "embedding": feature if outcome == "read" else None, "genericLogits": [0.0] * 97 if outcome == "read" else None,
                "baseScores": base if outcome == "read" else None, "genericRanks": [{"label": label, "score": 1.0}] if outcome == "read" else [],
                "personalRanks": [{"label": label, "score": 1.0}] if outcome == "read" else []}

    def test_candidate_receives_only_five_tensors_not_prior_ranks_ids_or_answers(self):
        e, torch = self.e, self.torch
        lesson = {"label": "A", "embedding": [1.0] + [0.0] * 127, "baseScores": [1.0 / 97] * 97}
        calls = []
        class Learner:
            def probabilities(self, *args):
                calls.append(tuple(a.clone() for a in args)); return args[4].clone()
        source = self.row("opaque-query")
        first = e.apply_to_task(Learner(), [lesson], [source], self.vocabulary)[0]
        changed = copy.deepcopy(source)
        changed["personalRanks"] = [{"label": "B", "score": 99.0}]
        changed["genericRanks"] = [{"label": "C", "score": 99.0}]
        second = e.apply_to_task(Learner(), [lesson], [changed], self.vocabulary)[0]
        self.assertEqual(first["retrievalRanks"], second["retrievalRanks"])
        self.assertNotEqual(first["linearRanks"], second["linearRanks"])
        self.assertEqual(len(calls[0]), 5)
        self.assertTrue(all(torch.equal(a, b) for a, b in zip(calls[0], calls[1])))
        self.assertEqual([tuple(a.shape) for a in calls[0]], [(1, 128), (1, 97), (1,), (1, 128), (1, 97)])
        self.assertEqual([a.dtype for a in calls[0]], [torch.float64, torch.float64, torch.int64, torch.float64, torch.float64])

    def test_invalid_rows_retained_and_nonfinite_or_incomplete_probabilities_fail(self):
        e, torch = self.e, self.torch
        lesson = {"label": "A", "embedding": [1.0] + [0.0] * 127, "baseScores": [1.0 / 97] * 97}
        class Learner:
            def probabilities(self, x, base, labels, q, p): return p.clone()
        rows = [self.row("valid"), self.row("invalid", outcome="invalid-ink")]
        output = e.apply_to_task(Learner(), [lesson], rows, self.vocabulary)
        self.assertEqual(len(output), 2)
        self.assertEqual(len(output[0]["retrievalRanks"]), 97)
        self.assertIsNone(output[1]["retrievalProbabilities"])
        self.assertEqual(output[1]["retrievalRanks"], [])
        for value in (torch.full((1, 97), float("nan"), dtype=torch.float64), torch.ones((1, 97), dtype=torch.float64), torch.ones((1, 96), dtype=torch.float64)):
            with self.subTest(shape=tuple(value.shape)), patch.object(Learner, "probabilities", return_value=value), self.assertRaises(ValueError):
                e.apply_to_task(Learner(), [lesson], rows, self.vocabulary)

    def scoring_rows(self):
        e = self.e
        rows = []
        for task in e.common.TASKS:
            for sid, generic, linear, retrieval, outcome in (("a", "B", "B", "A", "read"), ("b", "A", "A", "B", "read"), ("c", None, None, None, "invalid-ink")):
                row = self.row(sid, generic, outcome, task)
                row["linearRanks"] = [{"label": linear, "score": 1.0}] if outcome == "read" else []
                row["retrievalRanks"] = [{"label": retrieval, "score": 1.0}] if outcome == "read" else []
                rows.append(row)
        truth = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": "A"} for sid in "abc"]
        copies = [{"sampleID": sid, "reasons": ["source-copy"] if sid == "b" else []} for sid in "abc"]
        return rows, truth, copies

    def test_scoring_retains_failures_and_exact_gains_harms_with_fixed_copy_mask(self):
        e = self.e
        rows, truth, copies = self.scoring_rows()
        joined = [r for r in e.join_rows(rows, truth, copies) if r["task"] == "core10"]
        summary = e.summarize(joined); comparison = summary["comparisons"]["retrievalVsLinear"]
        self.assertEqual((summary["denominator"], summary["invalid"], comparison["gains"], comparison["harms"], comparison["net"]), (3, 1, 1, 1, 0))
        self.assertEqual((comparison["gainIDs"], comparison["harmIDs"], comparison["discordantIDs"]), (["a"], ["b"], ["a", "b"]))
        self.assertEqual(e.summarize([r for r in joined if r["eligible"]])["denominator"], 2)
        truth[0]["label"] = "a"
        self.assertFalse(e.join_rows(rows, truth, copies)[3]["correct"]["retrieval"])  # Raw A != a.

    def test_scorer_rejects_missing_task_duplicate_rows_and_wrong_copy_cohort(self):
        rows, truth, copies = self.scoring_rows()
        for predictions, mask in ((rows[:-1], copies), (rows + rows[:1], copies), (rows, copies[:-1])):
            with self.assertRaises(ValueError): self.e.join_rows(predictions, truth, mask)

    def test_prediction_and_cache_hash_checks_precede_any_truth_read(self):
        e = self.e
        with patch.object(e, "read", return_value=b"{}") as read_input:
            with self.assertRaisesRegex(ValueError, "Prediction SHA mismatch"):
                e.score("prediction", "0" * 64, "prior", "truth", "copies", "output")
            self.assertEqual(read_input.call_args_list, [unittest.mock.call("prediction")])
        with patch.object(e, "read", return_value=b"{}"), patch.object(e.common, "validate_prediction_packet") as validate:
            with self.assertRaisesRegex(ValueError, "Wrong frozen CE packet"): e.load_prior("prior")
            validate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
