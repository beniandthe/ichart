"""Synthetic source-only contracts; no saved handwriting, model or fit."""

import base64
import contextlib
import copy
import hashlib
import io
import json
import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import blind_ink_capture as capture
from ichart_recognition_ml.research.blind_ink_tool import entrypoint as blind_tool, validate_review_bundle


RUN_ID = "11111111-1111-4111-8111-111111111111"
REQUEST_ID = "22222222-2222-4222-8222-222222222222"
OTHER_ID = "33333333-3333-4333-8333-333333333333"


def encoded_data(data):
    return base64.b64encode(data).decode()


def trajectory_bytes(strokes):
    def bits(value):
        return struct.pack(">d", float(value)).hex()

    def time(value):
        return {"state": "missing"} if value is None else {"state": "finite", "bitPattern": bits(value)}

    return canonical_json_bytes({
        "formatVersion": "ink-trajectory-packet-v1",
        "coordinateSpace": "transformed-prepared-drawing",
        "strokes": [{"bounds": {key: bits(value) for key, value in stroke["bounds"].items()},
                     "creationTimeOffset": time(stroke.get("creationTimeOffset")),
                     "points": [{"x": bits(point["x"]), "y": bits(point["y"]),
                                 "timeOffset": time(point.get("timeOffset"))} for point in stroke["points"]]}
                    for stroke in strokes],
    })


def fixture(style="simpleChordSheet"):
    strokes = [
        {"points": [{"x": -0.0, "y": 2.0, "timeOffset": -0.1},
                    {"x": -0.0, "y": 2.0, "timeOffset": -0.1},
                    {"x": 4.0, "y": 8.0}],
         "bounds": {"minX": -0.0, "minY": 2.0, "maxX": 4.0, "maxY": 8.0},
         "creationTimeOffset": -0.5},
        {"points": [{"x": 10.0, "y": 0.0}, {"x": 10.0, "y": 15.0}],
         "bounds": {"minX": 10.0, "minY": 0.0, "maxX": 10.0, "maxY": 15.0}},
        {"points": [{"x": 20.0, "y": 2.0, "timeOffset": 0.1}, {"x": 24.0, "y": 8.0}],
         "bounds": {"minX": 20.0, "minY": 2.0, "maxX": 24.0, "maxY": 8.0},
         "creationTimeOffset": 0.3},
    ]
    source = {
        "schemaVersion": 1, "requestID": REQUEST_ID, "inkRevision": 9,
        # Opaque normalized drawing bytes. Python makes no PencilKit validity claim.
        "normalizedDrawingData": encoded_data(b"synthetic-normalized-drawing"),
        "canonicalVisibleTrajectoryData": encoded_data(trajectory_bytes(strokes)),
        "visibleStrokes": strokes, "chordFrame": [[-10, -20], [300, 80]],
        "pageBounds": [[0, 0], [500, 700]], "pages": [{"index": 0, "frame": [[0, 0], [500, 700]]}],
        # Visual order is retained: display indexes/target IDs may repeat.
        "measures": [{"measureID": OTHER_ID, "targetMeasureID": RUN_ID, "index": 7,
                      "chordWritingFrame": [[0, 0], [150, 80]]},
                     {"measureID": REQUEST_ID, "targetMeasureID": RUN_ID, "index": 2,
                      "chordWritingFrame": [[150, 0], [150, 80]]}],
        "recognitionVisibleFragmentIndices": [0, 2],
        "ownership": {"schemaVersion": 1, "indexSpace": "visibleFragmentsBeforeBarlineFilteringV1",
                      "sourcePencilStrokeCount": 2, "visibleFragmentSourceStrokeIndices": [0, 0, 1],
                      "barlineVisibleFragmentIndices": [1],
                      "targetGroups": [{"targetOrdinal": 0, "visibleFragmentIndices": [0]},
                                       {"targetOrdinal": 1, "visibleFragmentIndices": [2]}],
                      "unassignedVisibleFragmentIndices": []},
        "outcome": "ready",
    }
    run = {"id": RUN_ID, "chartID": OTHER_ID, "style": style, "phase": "beforeCorrections",
           "pipeline": "synthetic-source-pipeline", "status": "cancelled", "sourceCaptureState": "complete",
           "sourceRequestID": REQUEST_ID, "sourceInkRevision": 9, "sourceSnapshot": source,
           "profile": {"version": 1, "revision": REQUEST_ID, "generation": OTHER_ID,
                       "isEnabled": False, "learnsFromReviews": False, "examples": []},
           "profileLineage": {"querySessionID": RUN_ID, "trackedExampleIDs": [], "untrackedExampleIDs": [],
                              "mismatchedExampleIDs": [], "observedSupportSessionIDs": [], "overlapExampleIDs": [],
                              "isMetadataComplete": True, "areObservedSupportSessionsDisjoint": True,
                              "assuranceNote": "Synthetic, not verified identity or consent."},
           "records": [{"sourceRequestID": REQUEST_ID, "targetOrdinal": 0, "recognitionStrokes": [strokes[0]]},
                       {"sourceRequestID": REQUEST_ID, "targetOrdinal": 1, "recognitionStrokes": [strokes[2]]}]}
    return {"version": 1, "runs": [run]}


def journal_bytes(journal):
    return json.dumps(journal, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()


class BlindInkCaptureTests(unittest.TestCase):
    def artifacts(self, journal=None):
        return capture.prepare_capture_artifacts(journal_bytes(journal or fixture()), RUN_ID)

    def test_exact_visible_bytes_mapping_and_frozen_profile_are_retained_without_answers(self):
        journal = fixture()
        run = journal["runs"][0]
        run["expectedChordCount"] = 999  # Deliberately unrelated; not a source field.
        for record in run["records"]:
            record.update(intended="ANSWER-SECRET", baseline="PREDICTION-SECRET", personalized="MODEL-SECRET")
        data = journal_bytes(journal)
        artifacts = capture.prepare_capture_artifacts(data, RUN_ID)
        source_bytes = base64.b64decode(run["sourceSnapshot"]["canonicalVisibleTrajectoryData"])
        self.assertEqual(artifacts["trajectory.json"], source_bytes)
        envelope = json.loads(artifacts["source-envelope.json"])
        provenance = json.loads(artifacts["capture-provenance.json"])
        self.assertEqual(envelope["sourceSnapshot"], run["sourceSnapshot"])
        self.assertEqual(envelope["frozenProfile"], run["profile"])
        self.assertFalse(envelope["frozenProfile"]["isEnabled"])
        self.assertEqual(provenance["sourcePacketSHA256"], hashlib.sha256(source_bytes).hexdigest())
        self.assertEqual(provenance["journalSHA256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(provenance["counts"]["visibleStrokes"], 3)
        self.assertEqual(provenance["counts"]["recognitionStrokes"], 2)
        self.assertEqual(envelope["capturedChartStyle"], "simpleChordSheet")
        for artifact in artifacts.values():
            self.assertNotIn(b"ANSWER-SECRET", artifact)
            self.assertNotIn(b"PREDICTION-SECRET", artifact)
            self.assertNotIn(b"MODEL-SECRET", artifact)
            self.assertNotIn(b"expectedChordCount", artifact)
        for name in ("trainingEligible", "writerIdentityVerified", "consentVerified", "rawOriginalDrawingArchived",
                     "recognitionAccuracyMeasured"):
            self.assertFalse(provenance[name])

    def test_native_styles_optional_rect_and_integer_negative_zero_are_compatible(self):
        for style, expected in capture._CHART_STYLES.items():
            with self.subTest(style=style):
                journal = fixture(style)
                journal["runs"][0]["sourceSnapshot"].pop("pageBounds")
                # Foundation may spell a stored Double signed zero as -0.
                data = journal_bytes(journal).replace(b'"x":-0.0', b'"x":-0').replace(b'"minX":-0.0', b'"minX":-0')
                result = capture.prepare_capture_artifacts(data, RUN_ID)
                self.assertEqual(json.loads(result["capture-provenance.json"])["chartStyle"], expected)
                self.assertEqual(result["trajectory.json"], base64.b64decode(journal["runs"][0]["sourceSnapshot"]["canonicalVisibleTrajectoryData"]))

    def test_no_target_source_retains_unassigned_and_barline_fragments(self):
        journal = fixture()
        run = journal["runs"][0]
        run["sourceSnapshot"]["ownership"]["targetGroups"] = []
        run["sourceSnapshot"]["ownership"]["unassignedVisibleFragmentIndices"] = [0, 2]
        run["sourceSnapshot"]["outcome"] = "noTarget"
        run["records"] = []
        artifacts = self.artifacts(journal)
        self.assertEqual(len(json.loads(artifacts["trajectory.json"])["strokes"]), 3)
        self.assertEqual(json.loads(artifacts["capture-provenance.json"])["counts"]["unassignedFragments"], 2)

    def test_pending_legacy_missing_stale_and_incomplete_captures_are_rejected_before_writes(self):
        mutations = [
            lambda run: run.update(sourceCaptureState="pendingPreparation"),
            lambda run: run.update(sourceCaptureState="awaitingPredictions"),
            lambda run: run.pop("sourceSnapshot"),
            lambda run: run.pop("sourceRequestID"),
            lambda run: run.update(sourceInkRevision=8),
            lambda run: run.update(sourceRequestID=OTHER_ID),
            lambda run: run.update(status="capturing"),
            lambda run: run["records"].pop(),
            lambda run: run["records"].reverse(),
            lambda run: run["records"][0].update(sourceRequestID=OTHER_ID),
            lambda run: run["records"][0].pop("recognitionStrokes"),
            lambda run: run["records"][0]["recognitionStrokes"][0]["points"][0].update(x=1.0),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as directory:
                journal = copy.deepcopy(fixture())
                mutate(journal["runs"][0])
                path = Path(directory) / "journal.json"
                path.write_bytes(journal_bytes(journal))
                output = Path(directory) / "new-export"
                with self.assertRaises(ValueError):
                    capture.extract_capture(path, RUN_ID, output)
                self.assertFalse(output.exists())

    def test_partition_map_boolean_index_and_duplicate_keys_are_not_repaired(self):
        mutations = [
            lambda source: source["ownership"].update(unassignedVisibleFragmentIndices=[0]),
            lambda source: source["ownership"]["targetGroups"][1].update(visibleFragmentIndices=[0, 2]),
            lambda source: source["ownership"]["targetGroups"][0].update(visibleFragmentIndices=[False]),
            lambda source: source["ownership"]["targetGroups"][0].update(targetOrdinal=True),
            lambda source: source.update(recognitionVisibleFragmentIndices=[2, 0]),
            lambda source: source.update(recognitionVisibleFragmentIndices=[0, 1, 2]),
            lambda source: source["ownership"].update(visibleFragmentSourceStrokeIndices=[0, 0, 2]),
            lambda source: source.update(inkRevision=True),
            lambda source: source.update(outcome="ready-but-repaired"),
            lambda source: source["ownership"]["targetGroups"].clear(),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                journal = fixture()
                mutate(journal["runs"][0]["sourceSnapshot"])
                with self.assertRaises(ValueError):
                    self.artifacts(journal)
        data = journal_bytes(fixture()).replace(b'"version":1', b'"version":1,"version":1', 1)
        with self.assertRaises(ValueError):
            capture.prepare_capture_artifacts(data, RUN_ID)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "deeply-nested.json"
            path.write_bytes(b"[" * 1500 + b"0" + b"]" * 1500)
            output = Path(directory) / "no-export"
            with contextlib.redirect_stdout(io.StringIO()) as stdout:
                self.assertEqual(capture.entrypoint(["--journal-json", str(path), "--run-id", RUN_ID,
                                                    "--output-dir", str(output)]), 1)
            self.assertEqual(json.loads(stdout.getvalue())["status"], "rejected-capture-source")
            self.assertFalse(output.exists())

    def test_canonical_data_geometry_and_existing_blind_budgets_fail_closed(self):
        for changed in (b" ", b"\n"):
            journal = fixture()
            source = journal["runs"][0]["sourceSnapshot"]
            source["canonicalVisibleTrajectoryData"] = encoded_data(base64.b64decode(source["canonicalVisibleTrajectoryData"]) + changed)
            with self.assertRaises((ValueError, capture.ContractError)):
                self.artifacts(journal)
        journal = fixture()
        source = journal["runs"][0]["sourceSnapshot"]
        source["visibleStrokes"][0]["bounds"]["maxX"] = 1.0
        source["canonicalVisibleTrajectoryData"] = encoded_data(trajectory_bytes(source["visibleStrokes"]))
        with self.assertRaises(capture.ContractError):
            self.artifacts(journal)
        journal = fixture()
        source = journal["runs"][0]["sourceSnapshot"]
        source["visibleStrokes"] = [source["visibleStrokes"][0]] * 257
        source["canonicalVisibleTrajectoryData"] = encoded_data(trajectory_bytes(source["visibleStrokes"]))
        with self.assertRaises(capture.ContractError):
            self.artifacts(journal)
        journal = fixture()
        journal["runs"][0]["sourceSnapshot"]["normalizedDrawingData"] = encoded_data(b"x" * 1_000_001)
        with self.assertRaises(ValueError):
            self.artifacts(journal)
        with mock.patch.object(capture, "MAXIMUM_JOURNAL_BYTES", 8), self.assertRaises(ValueError):
            self.artifacts()
        data = journal_bytes(fixture()).replace(b'"x":-0.0', b'"x":NaN', 1)
        with self.assertRaises(ValueError):
            capture.prepare_capture_artifacts(data, RUN_ID)

    def test_run_set_and_support_lineage_mismatches_are_rejected(self):
        journal = fixture()
        journal["runs"].append(copy.deepcopy(journal["runs"][0]))
        with self.assertRaises(ValueError):
            self.artifacts(journal)
        with self.assertRaises(ValueError):
            capture.prepare_capture_artifacts(journal_bytes(fixture()), OTHER_ID)
        journal = fixture()
        journal["runs"][0]["profileLineage"]["trackedExampleIDs"] = [OTHER_ID]
        with self.assertRaises(ValueError):
            self.artifacts(journal)
        journal = fixture()
        journal["runs"][0]["profileLineage"]["querySessionID"] = OTHER_ID
        with self.assertRaises(ValueError):
            self.artifacts(journal)

    def test_nonempty_frozen_support_counts_bind_stored_input_sessions_without_teaching(self):
        journal = fixture()
        run = journal["runs"][0]
        strokes = copy.deepcopy(run["sourceSnapshot"]["visibleStrokes"][:1])
        example = {"id": OTHER_ID, "kind": "glyph", "label": "PRIVATE-SUPPORT-LABEL", "strokes": strokes,
                   "source": "setup", "learningProvenance": {"version": 1, "taughtAt": 12.5,
                   "context": {"sessionID": REQUEST_ID, "captureID": OTHER_ID, "capturedAt": 10.0,
                               "origin": "setup", "chartStyle": "simple-chord-sheet"},
                   "originalInputSHA256": "a" * 64,
                   "storedInputSHA256": hashlib.sha256(trajectory_bytes(strokes)).hexdigest()}}
        run["profile"]["examples"] = [example]
        run["profileLineage"]["trackedExampleIDs"] = [OTHER_ID]
        run["profileLineage"]["observedSupportSessionIDs"] = [REQUEST_ID]
        artifacts = self.artifacts(journal)
        provenance = json.loads(artifacts["capture-provenance.json"])
        self.assertEqual(provenance["counts"]["glyphSupportExamples"], 1)
        self.assertEqual(provenance["counts"]["observedSupportSessions"], 1)
        self.assertNotIn(b"PRIVATE-SUPPORT-LABEL", artifacts["trajectory.json"])
        run["profileLineage"]["observedSupportSessionIDs"] = []
        with self.assertRaises(ValueError):
            self.artifacts(journal)
        run["profileLineage"]["observedSupportSessionIDs"] = [REQUEST_ID]
        example["learningProvenance"]["storedInputSHA256"] = "b" * 64
        with self.assertRaises(ValueError):
            self.artifacts(journal)

    def test_exclusive_private_publication_and_existing_blind_cli_accept_exact_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "journal.json"
            original = journal_bytes(fixture())
            path.write_bytes(original)
            output = Path(directory) / "capture"
            with contextlib.redirect_stdout(io.StringIO()) as stdout:
                status = capture.entrypoint(["--journal-json", str(path), "--run-id", RUN_ID, "--output-dir", str(output)])
            self.assertEqual(status, 0)
            source_sha = json.loads(stdout.getvalue())["sourcePacketSHA256"]
            receipt = json.loads((output / "prepared-receipt.json").read_bytes())
            self.assertEqual(set(receipt["artifacts"]), {"trajectory.json", "source-envelope.json", "capture-provenance.json"})
            for name, digest in receipt["artifacts"].items():
                self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), digest)
                self.assertEqual(os.stat(output / name).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o700)
            before = {entry.name: entry.read_bytes() for entry in output.iterdir()}
            with self.assertRaises(FileExistsError):
                capture.extract_capture(path, RUN_ID, output)
            self.assertEqual(before, {entry.name: entry.read_bytes() for entry in output.iterdir()})
            self.assertEqual(path.read_bytes(), original)
            review = Path(directory) / "review"
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(blind_tool(["prepare-ownership", "--trajectory-json", str(output / "trajectory.json"),
                                            "--expected-source-sha256", source_sha, "--output-dir", str(review)]), 0)
            validate_review_bundle(review)
            html = (review / "ownership-review.html").read_bytes()
            self.assertNotIn(b"frozenProfile", html)
            self.assertNotIn(b"source-envelope", html)
            self.assertNotIn(b"querySessionID", html)


if __name__ == "__main__":
    unittest.main()
