"""Small synthetic broad-transfer evaluation tests; no models or data opened."""
import base64
import copy
import importlib.util
import struct
import unittest
from unittest.mock import patch


@unittest.skipUnless(importlib.util.find_spec("torch") is not None, "Optional research dependencies required")
class BroadTransferEvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from ichart_recognition_ml.research import personal_broad_transfer_evaluation as evaluation
        cls.e = evaluation

    def row(self, sid, arm, label, outcome="read"):
        return {"sampleID": sid, "arm": arm, "task": "core10", "writerID": self.e.common.WRITERS[0], "outcome": outcome,
                "genericRanks": [{"label": label, "score": 1.0}] if outcome == "read" else [],
                "personalRanks": [{"label": label, "score": 1.0}] if outcome == "read" else []}

    def test_new_arms_raw_codepoints_masks_and_pretraining_absent_stratum(self):
        e = self.e
        answers = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": label} for sid, label in (("a", "A"), ("b", "-"), ("c", "("), ("d", "z"))]
        copies = [{"sampleID": sid, "reasons": ["source-copy"] if sid == "b" else []} for sid in "abcd"]
        rows = [self.row(sid, arm, "a" if sid == "a" else label) for sid, label in (("a", "A"), ("b", "-"), ("c", "("), ("d", "z")) for arm in e.ARMS]
        joined = e.join_rows(rows, answers, copies)
        self.assertEqual([(r["taught"], r["appAvailable"], r["pretrainingAbsent35"], r["eligible"]) for r in joined],
                         [(True, True, False, True), (True, True, True, False), (False, True, True, True), (False, False, False, True)])
        self.assertFalse(joined[0]["correct"]["candidatePersonal"])  # No A/a alias rescue.
        self.assertEqual(e.summarize(joined)["denominator"], 4)
        self.assertEqual(set(e.summarize(joined)["invalid"]), set(e.ARMS))
        self.assertEqual(e.summarize([r for r in joined if r["eligible"]])["denominator"], 3)
        with self.assertRaisesRegex(ValueError, "predicted arm"):
            e.join_rows(rows + [self.row("a", e.common.ARMS[0], "A")], answers, copies)

    def test_invalid_queries_remain_paired_with_gains_harms_and_discordant_ids(self):
        e = self.e
        truth = [{"sampleID": sid, "writerID": e.common.WRITERS[0], "label": "A"} for sid in "abc"]
        copies = [{"sampleID": sid, "reasons": []} for sid in "abc"]
        rows = [self.row("a", e.ARMS[0], "B"), self.row("a", e.ARMS[1], "A"),
                self.row("b", e.ARMS[0], "A"), self.row("b", e.ARMS[1], "B")]
        rows += [self.row("c", arm, None, "invalid-ink") for arm in e.ARMS]
        summary = e.summarize(e.join_rows(rows, truth, copies))
        comparison = summary["comparisons"]["candidatePersonalVsControlPersonal"]
        self.assertEqual((comparison["denominator"], comparison["gains"], comparison["harms"], comparison["net"], comparison["neitherCorrect"]), (3, 1, 1, 0, 1))
        self.assertEqual((comparison["gainIDs"], comparison["harmIDs"], comparison["discordantIDs"]), (["a"], ["b"], ["a", "b"]))
        self.assertEqual(summary["invalid"], {a: 1 for a in e.ARMS})
        with self.assertRaisesRegex(ValueError, "Unpaired"):
            e.join_rows(rows[:-1], truth, copies)

    def test_wrong_model_protocol_source_split_and_prior_packet_versions_reject(self):
        e = self.e
        receipt = {"arms": list(e.ARMS), "sourceSHA256": e.common.SOURCE_SHA256, "developmentWriters": list(e.common.WRITERS),
                   "trainingWriters": [f"trn_fake_{i}" for i in range(32)], "reservedWriters": [f"tst_fake_{i}" for i in range(20)],
                   "vocabulary": ["A", "B"], "protocolEnvelope": {"markdownProtocolSHA256": e.PROTOCOL_SHA256}}
        e.validate_fit(receipt, ["A", "B"])
        for key, value in (("arms", list(e.common.ARMS)), ("sourceSHA256", "0" * 64), ("vocabulary", ["A", "b"]),
                           ("reservedWriters", [e.common.WRITERS[0]] + receipt["reservedWriters"][1:]),
                           ("protocolEnvelope", {"markdownProtocolSHA256": e.common.PROTOCOL_SHA256})):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "fit binding"):
                e.validate_fit({**receipt, key: value}, ["A", "B"])
        with self.assertRaisesRegex(ValueError, "Wrong broad packet"):
            e.validate_packet({"version": e.common.VERSION})

    def test_stored_support_reuses_exact_geometry_pixels_and_rejects_rehashed_changes(self):
        e = self.e.common
        numeric = {"bounds": {"minX": 2.0, "minY": 3.0, "maxX": 20.0, "maxY": 25.0}, "points": [{"x": 2.0, "y": 3.0}, {"x": 20.0, "y": 25.0}]}
        bits = lambda v: struct.pack(">d", v).hex()
        packet = e.canonical({"formatVersion": "ink-trajectory-packet-v1", "coordinateSpace": "transformed-prepared-drawing", "strokes": [{
            "bounds": {k: bits(v) for k, v in numeric["bounds"].items()}, "creationTimeOffset": {"state": "missing"},
            "points": [{"x": bits(p["x"]), "y": bits(p["y"]), "timeOffset": {"state": "missing"}} for p in numeric["points"]]}]})
        lesson = {"sampleID": "a" * 64, "exampleID": "example", "label": "A"}
        task = {"profileRevision": "revision", "profileGeneration": "generation", "lessons": [lesson]}
        profile = {"version": 1, "isEnabled": True, "revision": "revision", "generation": "generation", "examples": [{
            "id": "example", "label": "A", "kind": "glyph", "source": "setup", "strokes": [numeric]}]}
        data = e.canonical(profile)
        row = {"profileCanonicalData": base64.b64encode(data).decode(), "profileSHA256": e.sha(data), "supportLessons": [{
            **lesson, "storedCanonicalData": base64.b64encode(packet).decode(), "storedPacketSHA256": e.sha(packet),
            "storedRasterSHA256": e.sha(e.rasterize(e.numeric_strokes([numeric])).pixels)}]}
        self.assertEqual(e.project_stored_support(task, row)[0]["storedCanonicalData"], row["supportLessons"][0]["storedCanonicalData"])
        changed = copy.deepcopy(profile); changed["examples"][0]["strokes"][0]["points"][0]["x"] = 4.0
        changed_data = e.canonical(changed)
        with self.assertRaisesRegex(ValueError, "geometry mismatch"):
            e.project_stored_support(task, {**row, "profileCanonicalData": base64.b64encode(changed_data).decode(), "profileSHA256": e.sha(changed_data)})

    def test_bad_prediction_hash_cannot_open_truth_or_copy_ledger(self):
        e = self.e
        with patch.object(e, "read", return_value=b"{}") as read_input:
            with self.assertRaisesRegex(ValueError, "Prediction SHA mismatch"):
                e.score("predictions.json", "0" * 64, "truth.json", "copies.json", "score.json")
            self.assertEqual(read_input.call_count, 1)
            self.assertEqual(read_input.call_args.args, ("predictions.json",))


if __name__ == "__main__":
    unittest.main()
