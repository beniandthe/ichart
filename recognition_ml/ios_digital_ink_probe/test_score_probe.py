import copy
import hashlib
import json
import unittest

from score_probe import notation, score


class ProbeScoringTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.dumps([{"id": "one", "strokes": []}, {"id": "two", "strokes": []}]).encode()
        self.report = {"complete": True, "inputSHA256": hashlib.sha256(self.packet).hexdigest(),
                       "inputCount": 2, "rows": [
                           {"id": identity, "context": context, "milliseconds": 3,
                            "candidates": [{"text": "Ebmaj7"}, {"text": "D7"}]}
                           for identity in ("one", "two") for context in ("none", "bounds")]}
        self.labels = [{"id": "one", "intended": "Eb△7", "native": "Eb7", "personalized": "Eb△7"}]

    def testIntegrityAndNotationAreSeparateFromRawExactAndBaseline(self):
        result = score(self.packet, self.report, self.labels)
        self.assertEqual(result["unlabeledInputs"], 1)
        for total in result["totals"]:
            self.assertEqual(total["rawExactTop1"], 0)
            self.assertEqual(total["notationEquivalentTop1"], 1)
            self.assertEqual(total["nativeCorrect"], 0)
            self.assertEqual(total["personalizedCorrect"], 1)

    def testAliasesCannotRepairWrongRootAccidentalOrLostSuffix(self):
        for left, right in [("E♭maj7", "Eb△7"), ("Gm7", "G-7"), ("D min7", "D-7"), ("CΔ7", "C△7")]:
            self.assertEqual(notation(left), notation(right))
        for wrong, intended in [("D", "D7"), ("D'", "D7"), ("Eb", "Eb7"), ("Ebay", "Eb△7"),
                                ("BbD7", "Bb△7"), ("D-", "D-7"), ("B7", "Bb7"), ("G47", "G-7")]:
            self.assertNotEqual(notation(wrong), notation(intended))

    def testTopCandidateIsNotReplacedByAnExpectedLowerRank(self):
        result = score(self.packet, self.report, [{"id": "one", "intended": "D7"}])
        for total in result["totals"]:
            self.assertEqual(total["notationEquivalentTop1"], 0)
            self.assertEqual(total["notationEquivalentTop5"], 1)
            self.assertIsNone(total["nativeCorrect"], "Missing baseline is not a failed read")
            self.assertIsNone(total["personalizedCorrect"])

    def testMissingDuplicateUnexpectedAndFailedResultsAreRejected(self):
        for change in (lambda r: r["rows"].pop(), lambda r: r["rows"].append(r["rows"][0]),
                       lambda r: r.update(complete=False), lambda r: r.update(inputSHA256="wrong"),
                       lambda r: r["rows"][0].update(context="selected-after-viewing")):
            report = copy.deepcopy(self.report)
            change(report)
            with self.assertRaises(ValueError):
                score(self.packet, report, self.labels)

    def testEmptyCandidateListRemainsInDenominator(self):
        self.report["rows"][0]["candidates"] = []
        result = score(self.packet, self.report, self.labels)
        self.assertEqual(result["totals"][0]["count"], 1)
        self.assertEqual(result["totals"][0]["noCandidate"], 1)

    def testMalformedLabelsAndZeroInputsAreNotAccuracy(self):
        for labels in ([], self.labels * 2, [{"id": "absent", "intended": "C7"}], [{"id": "one", "intended": ""}]):
            with self.assertRaises(ValueError):
                score(self.packet, self.report, labels)
        with self.assertRaises(ValueError):
            score(b"[]", self.report, self.labels)


if __name__ == "__main__":
    unittest.main()
