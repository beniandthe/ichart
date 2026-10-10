"""Synthetic seams only: no public samples, model inference, or model fitting."""
import base64
import copy
import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional evaluation dependencies required")
class CrossWriterEvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from ichart_recognition_ml.research import personal_cross_writer_evaluation as evaluation
        cls.e = evaluation

    def support_fixture(self):
        e = self.e
        numeric = {"bounds": {"minX": 2.0, "minY": 3.0, "maxX": 20.0, "maxY": 25.0},
                   "points": [{"x": 2.0, "y": 3.0}, {"x": 20.0, "y": 25.0}]}
        bits = lambda value: struct.pack(">d", value).hex()
        packet = e.canonical({"coordinateSpace": "transformed-prepared-drawing",
            "formatVersion": "ink-trajectory-packet-v1", "strokes": [{
                "bounds": {key: bits(value) for key, value in numeric["bounds"].items()},
                "creationTimeOffset": {"state": "missing"},
                "points": [{"x": bits(p["x"]), "y": bits(p["y"]), "timeOffset": {"state": "missing"}}
                           for p in numeric["points"]]}]})
        example_id = "00000000-0000-0000-0000-000000000001"
        revision = "00000000-0000-0000-0000-000000000002"
        generation = "00000000-0000-0000-0000-000000000003"
        profile = {"version": 1, "isEnabled": True, "revision": revision, "generation": generation,
                   "examples": [{"id": example_id, "kind": "glyph", "label": "A", "source": "setup", "strokes": [numeric]}]}
        profile_data = e.canonical(profile)
        lesson = {"sampleID": "a" * 64, "label": "A", "exampleID": example_id}
        stored = {**lesson, "storedCanonicalData": base64.b64encode(packet).decode(),
                  "storedPacketSHA256": e.sha(packet), "storedRasterSHA256": e.sha(e.rasterize(e.numeric_strokes([numeric])).pixels)}
        task = {"profileRevision": revision, "profileGeneration": generation, "lessons": [lesson]}
        row = {"profileCanonicalData": base64.b64encode(profile_data).decode(),
               "profileSHA256": e.sha(profile_data), "supportLessons": [stored]}
        return task, row, profile

    def test_stored_support_is_exact_app_geometry_and_pixel_binding_not_renormalized(self):
        task, row, profile = self.support_fixture()
        frozen = self.e.project_stored_support(task, row)
        self.assertEqual(len(frozen), 1)
        self.assertEqual(frozen[0]["storedRasterSHA256"], self.e.sha(frozen[0]["pixels"]))
        self.assertEqual(frozen[0]["storedCanonicalData"], row["supportLessons"][0]["storedCanonicalData"])
        # Re-hashing a modified profile cannot make its different geometry agree
        # with the exact previously stored canonical trajectory packet.
        profile["examples"][0]["strokes"][0]["points"][0]["x"] = 4.0
        data = self.e.canonical(profile)
        altered = {**row, "profileCanonicalData": base64.b64encode(data).decode(), "profileSHA256": self.e.sha(data)}
        with self.assertRaisesRegex(ValueError, "geometry mismatch"):
            self.e.project_stored_support(task, altered)
        bad_pixels = copy.deepcopy(row)
        bad_pixels["supportLessons"][0]["storedRasterSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "raster mismatch"):
            self.e.project_stored_support(task, bad_pixels)

    def predicted(self, sid, generic, personal, arm, outcome="read", task="core10"):
        return {"sampleID": sid, "task": task, "writerID": self.e.WRITERS[0], "arm": arm, "outcome": outcome,
                "genericRanks": [] if outcome != "read" else [{"label": generic, "score": 1.0}],
                "personalRanks": [] if outcome != "read" else [{"label": personal, "score": 1.0}]}

    def test_raw_codepoints_copy_masks_and_taught_available_strata(self):
        e = self.e
        truth = [{"sampleID": sid, "writerID": e.WRITERS[0], "label": label}
                 for sid, label in (("a", "A"), ("b", "m"), ("c", "z"))]
        copies = [{"sampleID": sid, "reasons": ["declared-training-raster"] if sid == "b" else []} for sid in "abc"]
        rows = [self.predicted(sid, label, label, arm) for sid, label in (("a", "a"), ("b", "m"), ("c", "z")) for arm in e.ARMS]
        joined = e.join_rows(rows, truth, copies)
        self.assertEqual([(r["taught"], r["appAvailable"], r["eligible"]) for r in joined],
                         [(True, True, True), (False, True, False), (False, False, True)])
        self.assertFalse(joined[0]["correct"]["candidatePersonal"])  # A != a; no alias/parser rescue.
        self.assertEqual(e.summarize(joined)["denominator"], 3)
        self.assertEqual(e.summarize([r for r in joined if r["eligible"]])["denominator"], 2)
        duplicate = copies + [copies[0]]
        with self.assertRaisesRegex(ValueError, "Duplicate copy"):
            e.join_rows(rows, truth, duplicate)

    def test_failures_remain_in_paired_denominator_and_all_gains_harms_are_retained(self):
        e = self.e
        truth = [{"sampleID": sid, "writerID": e.WRITERS[0], "label": "A"} for sid in "abcd"]
        copies = [{"sampleID": sid, "reasons": []} for sid in "abcd"]
        rows = []
        for sid, control, candidate in (("a", "B", "A"), ("b", "A", "B"), ("c", "A", "A")):
            rows += [self.predicted(sid, control, control, e.ARMS[0]), self.predicted(sid, candidate, candidate, e.ARMS[1])]
        rows += [self.predicted("d", None, None, arm, "invalid-ink") for arm in e.ARMS]
        summary = e.summarize(e.join_rows(rows, truth, copies))
        comparison = summary["comparisons"]["candidatePersonalVsControlPersonal"]
        self.assertEqual((comparison["denominator"], comparison["gains"], comparison["harms"], comparison["net"],
                          comparison["bothCorrect"], comparison["neitherCorrect"]), (4, 1, 1, 0, 1, 1))
        self.assertEqual(comparison["gainIDs"], ["a"])
        self.assertEqual(comparison["harmIDs"], ["b"])
        self.assertEqual(comparison["discordantIDs"], ["a", "b"])
        self.assertEqual(summary["invalid"], {arm: 1 for arm in e.ARMS})
        with self.assertRaisesRegex(ValueError, "Missing paired"):
            e.join_rows(rows[:-1], truth, copies)

    def test_reject_wrong_source_split_vocabulary_or_protocol_fit_binding(self):
        e = self.e
        receipt = {"arms": list(e.ARMS), "sourceSHA256": e.SOURCE_SHA256,
                   "developmentWriters": list(e.WRITERS), "trainingWriters": [f"trn_fake_{i}" for i in range(32)],
                   "reservedWriters": [f"tst_fake_{i}" for i in range(20)], "vocabulary": ["A", "B"],
                   "protocolEnvelope": {"markdownProtocolSHA256": e.PROTOCOL_SHA256}}
        e.validate_fit(receipt, ["A", "B"])
        changes = (("sourceSHA256", "0" * 64), ("arms", list(reversed(e.ARMS))),
                   ("developmentWriters", list(reversed(e.WRITERS))), ("vocabulary", ["A", "b"]),
                   ("reservedWriters", [e.WRITERS[0]] + receipt["reservedWriters"][1:]),
                   ("protocolEnvelope", {"markdownProtocolSHA256": "0" * 64}))
        for key, value in changes:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "binding mismatch"):
                e.validate_fit({**receipt, key: value}, ["A", "B"])

    def test_fixture_digest_rejects_before_rasterization_and_outputs_are_exclusive(self):
        e = self.e
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            fixture, report = root / "fixture.json", root / "report.json"
            fixture.write_bytes(b"{}")
            report.write_bytes(b"{}")
            with patch.object(e, "rasterize", side_effect=AssertionError("must not rasterize")), self.assertRaisesRegex(ValueError, "Wrong retained"):
                e.load_projection(fixture, report)
            output = root / "prediction.json"
            e.exclusive(output, b"frozen", (fixture, report))
            with self.assertRaisesRegex(ValueError, "exclusive"):
                e.exclusive(output, b"replacement", (fixture, report))
            self.assertEqual(output.read_bytes(), b"frozen")
            with self.assertRaisesRegex(ValueError, "exclusive"):
                e.exclusive(fixture, b"replacement", (fixture, report))


if __name__ == "__main__":
    unittest.main()
