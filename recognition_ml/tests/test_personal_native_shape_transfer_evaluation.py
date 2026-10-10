"""Synthetic native-transfer checks; no dataset, model or query truth opened."""
import copy
import unittest
from unittest.mock import patch

from ichart_recognition_ml.research import personal_native_shape_transfer_evaluation as e


class NativeShapeTransferEvaluationTests(unittest.TestCase):
    def row(self, sid, arm, generic, personal=None, outcome="read"):
        return {"sampleID": sid, "arm": arm, "task": "core10", "writerID": e.common.WRITERS[0], "outcome": outcome,
                "genericRanks": [{"label": generic, "score": 1.}] if outcome == "read" else [],
                "personalRanks": [{"label": personal or generic, "score": 1.}] if outcome == "read" else []}

    def test_copy_binding_is_source_only_complete_and_hash_bound(self):
        ids = [e.sha(f"opaque:{i}".encode()) for i in range(776)]
        match, other = "1" * 64, "2" * 64
        raw = {sid: {"rawRasterSHA256": match if i == 0 else other} for i, sid in enumerate(ids)}
        evidence = {"receiptSHA256": "3" * 64, "selectedAdaptedRasterHashes": [match],
                    "selectedAdaptedRasterHashesSHA256": e.sha(e.canonical([match]))}
        value = e.copy_binding(evidence, raw, ids)
        self.assertEqual(len(value["queryRows"]), 776)
        self.assertEqual(sum(bool(r["reasons"]) for r in value["queryRows"]), 1)
        self.assertNotIn("label", str(value))
        for changed, queries in (({**evidence, "selectedAdaptedRasterHashesSHA256": "0" * 64}, ids),
                                 (evidence, ids[:-1]), (evidence, ids[:-1] + [ids[0]])):
            with self.assertRaises(ValueError): e.copy_binding(changed, raw, queries)

    def test_union_copy_exclusions_symmetric_but_raw_and_invalid_rows_remain(self):
        truth = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": label} for sid, label in (("a", "A"), ("b", "-"), ("c", "("), ("d", "z"))]
        old = [{"sampleID": sid, "reasons": ["old-source-copy"] if sid == "b" else []} for sid in "abcd"]
        hasy = [{"sampleID": sid, "reasons": ["selected-hasy-adapted-raster-copy"] if sid == "c" else []} for sid in "abcd"]
        predictions = [self.row(sid, arm, "a" if sid == "a" else label, outcome="invalid-ink" if sid == "d" else "read")
                       for sid, label in (("a", "A"), ("b", "-"), ("c", "("), ("d", "z")) for arm in e.ARMS]
        rows = e.join_rows(predictions, truth, old, hasy)
        self.assertEqual([(r["taught"], r["appAvailable"], r["nonASCII35"], r["eligible"]) for r in rows],
                         [(True, True, False, True), (True, True, True, False), (False, True, True, False), (False, False, False, True)])
        self.assertFalse(rows[0]["correct"]["candidatePersonal"])  # No A/a rescue.
        self.assertEqual(e.summarize(rows)["denominator"], 4)
        eligible = e.summarize([r for r in rows if r["eligible"]])
        self.assertEqual(eligible["denominator"], 2)
        self.assertEqual(eligible["invalid"], {arm: 1 for arm in e.ARMS})
        self.assertFalse(e.complete_reads(predictions))
        self.assertTrue(e.complete_reads([r for r in predictions if r["outcome"] == "read"]))
        self.assertFalse(e.complete_reads([]))
        with self.assertRaisesRegex(ValueError, "cohort mismatch"): e.join_rows(predictions, truth, old, hasy[:-1])

    def test_paired_gains_harms_neither_and_complete_arm_requirement(self):
        truth = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": "A"} for sid in "abc"]
        copies = [{"sampleID": sid, "reasons": []} for sid in "abc"]
        rows = [self.row("a", e.ARMS[0], "B"), self.row("a", e.ARMS[1], "A"),
                self.row("b", e.ARMS[0], "A"), self.row("b", e.ARMS[1], "B")]
        rows += [self.row("c", arm, None, outcome="invalid-ink") for arm in e.ARMS]
        result = e.summarize(e.join_rows(rows, truth, copies, copies))["comparisons"]["candidatePersonalVsControlPersonal"]
        self.assertEqual((result["denominator"], result["gains"], result["harms"], result["net"], result["neitherCorrect"]), (3, 1, 1, 0, 1))
        self.assertEqual(result["discordantIDs"], ["a", "b"])
        with self.assertRaisesRegex(ValueError, "Unpaired"): e.join_rows(rows[:-1], truth, copies, copies)
        with self.assertRaisesRegex(ValueError, "predicted arm"):
            e.join_rows(rows + [self.row("a", e.common.ARMS[0], "A")], truth, copies, copies)

    def test_all_97_classes_include_zero_eligible_denominators_and_sum_to_rows(self):
        vocabulary = [chr(33 + i) for i in range(97)]
        truth = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": label} for sid, label in (("a", "A"), ("b", "-"), ("c", "z"))]
        copies = [{"sampleID": sid, "reasons": ["old-copy"] if sid == "b" else []} for sid in "abc"]
        hasy = [{"sampleID": sid, "reasons": []} for sid in "abc"]
        predictions = [self.row(sid, arm, label, outcome="invalid-ink" if sid == "c" else "read")
                       for sid, label in (("a", "A"), ("b", "-"), ("c", "z")) for arm in e.ARMS]
        rows = e.join_rows(predictions, truth, copies, hasy)
        for selected in (rows, [r for r in rows if r["eligible"]]):
            classes = e.class_summaries(selected, vocabulary)
            self.assertEqual(list(classes), vocabulary)
            self.assertEqual(sum(c["denominator"] for c in classes.values()), len(selected))
            self.assertEqual(classes["z"]["invalid"], {arm: 1 for arm in e.ARMS})
            self.assertEqual(classes["B"]["denominator"], 0)
        self.assertEqual(e.class_summaries([r for r in rows if r["eligible"]], vocabulary)["-"]["denominator"], 0)
        with self.assertRaises(ValueError): e.class_summaries(rows, vocabulary[:-1])

    def test_all_eight_frozen_conditions_are_individually_required(self):
        def cell(generic=0, personal=1, own=1, harms=0):
            return {"comparisons": {"candidateGenericVsControlGeneric": {"net": generic},
                "candidatePersonalVsControlPersonal": {"net": personal}, "candidatePersonalVsOwnGeneric": {"net": own, "harms": harms}}}
        totals, strata, writers = cell(), {"untaught": cell(personal=0), "nonASCII35": cell(personal=0)}, {"w": cell(personal=0)}
        self.assertEqual(e.fixed_screen(totals, strata, writers), (True,) * 8)
        targets = [("totals", "candidateGenericVsControlGeneric", "net", -1),
                   ("totals", "candidatePersonalVsControlPersonal", "net", 0),
                   ("untaught", "candidatePersonalVsControlPersonal", "net", -1),
                   ("writer", "candidatePersonalVsControlPersonal", "net", -1),
                   ("totals", "candidatePersonalVsOwnGeneric", "net", 0),
                   ("untaught", "candidatePersonalVsOwnGeneric", "harms", 1),
                   ("nonASCII35", "candidateGenericVsControlGeneric", "net", -1),
                   ("nonASCII35", "candidatePersonalVsControlPersonal", "net", -1)]
        for position, (target, comparison, key, value) in enumerate(targets):
            a, b, c = copy.deepcopy((totals, strata, writers))
            selected = a if target == "totals" else c["w"] if target == "writer" else b[target]
            selected["comparisons"][comparison][key] = value
            result = e.fixed_screen(a, b, c)
            self.assertFalse(result[position]); self.assertEqual(sum(result), 7)

    def test_bad_prediction_hash_precedes_truth_and_wrong_protocol_or_roles_reject(self):
        with patch.object(e, "read", return_value=b"{}") as reader:
            with self.assertRaisesRegex(ValueError, "Prediction SHA mismatch"):
                e.score("predictions", "0" * 64, "truth", "copies", "output")
            reader.assert_called_once_with("predictions")
        receipt = {"arms": list(e.ARMS), "sourceSHA256": e.common.SOURCE_SHA256, "developmentWriters": list(e.common.WRITERS),
                   "trainingWriters": [f"trn_fake_{i}" for i in range(32)], "reservedWriters": [f"tst_fake_{i}" for i in range(20)],
                   "vocabulary": ["A", "B"], "protocolEnvelope": {"markdownProtocolSHA256": e.PROTOCOL_SHA256}}
        e.validate_fit(receipt, ["A", "B"])
        for fields in ({"arms": list(e.common.ARMS)}, {"protocolEnvelope": {"markdownProtocolSHA256": "0" * 64}},
                       {"trainingWriters": [e.common.WRITERS[0]] + receipt["trainingWriters"][1:]}):
            with self.assertRaises(ValueError): e.validate_fit({**receipt, **fields}, ["A", "B"])


if __name__ == "__main__":
    unittest.main()
