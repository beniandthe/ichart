"""Synthetic contracts only; no actual writer answers or prompt annotations."""

import base64
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import uuid

from ichart_recognition_ml.research import fresh_symbol_transfer_scoring as scoring


def identifier(text):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "synthetic-score:" + text)).upper()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixture():
    old = {"version": 1, "isEnabled": True, "revision": identifier("old-revision"),
           "generation": identifier("generation"), "learnsFromReviews": True,
           "examples": [{"id": identifier("lesson-" + str(index)), "kind": "glyph",
                         "source": "setup", "label": "synthetic", "strokes": []}
                        for index in range(34)]}
    new = copy.deepcopy(old)
    new["revision"] = identifier("new-revision")
    new["examples"].extend({"id": identifier("addition-" + str(index)), "kind": "glyph",
                            "source": "explicitCorrection", "label": "synthetic", "strokes": []}
                           for index in range(3))
    source = {"version": 1, "runs": []}
    composition = {"version": scoring.COMPOSITION_VERSION, "codeFileMapSHA256": "c" * 64,
                   "inferenceRerun": False, "profileChanged": False, "accuracyMeasured": False,
                   "requestSHA256": "r" * 64, "composerDependencyHashes": {}, "targets": []}
    prediction = {"version": scoring.PREDICTION_VERSION, "codeFileMapSHA256": "c" * 64,
                  "newProfileCanonicalSHA256": "e" * 64, "oldExampleCount": 34,
                  "newExampleCount": 37, "sources": []}
    specifications = []
    for style in sorted(scoring.STYLES):
        run_id = identifier(style)
        records, targets, groups = [], [], []
        for index in range(6):
            record_id = identifier(style + ":record:" + str(index))
            records.append({"id": record_id, "targetOrdinal": index, "baseline": "F13",
                            "personalized": "F13", "fingerprint": "synthetic-" + str(index),
                            "strokes": [], "recognitionStrokes": [], "groupingIssue": False,
                            "taught": False, "knownInk": False, "capturedAt": 2.0,
                            "recognitionMilliseconds": 1.0, "sourceRequestID": identifier(style + ":source")})
            groups.append({"targetOrdinal": index, "visibleFragmentIndices": [index]})
            arm = {"outcome": "read", "glyphs": [{"originalStrokeIndexes": [0],
                                                      "sharedRanks": [{"label": "synthetic", "score": 1.0}]}]}
            frozen = {"automatic": arm, "supplied": None, "glyphOwnershipVerified": False}
            packet = scoring.canonical({"syntheticSourceIndex": index})
            targets.append({"recordID": record_id, "targetOrdinal": index,
                            "childToParentVisibleFragmentIndices": [index],
                            "sourcePacketData": base64.b64encode(packet).decode(),
                            "sourcePacketSHA256": digest(packet),
                            "olderProfileFreeze": copy.deepcopy(frozen), "newerProfileFreeze": copy.deepcopy(frozen)})
            composition["targets"].append({"runID": run_id, "recordID": record_id,
                                            "targetOrdinal": index, "style": style,
                                            "sourcePacketSHA256": digest(packet),
                                            "parentSourcePacketSHA256": "p" * 64,
                                            "glyphOwnershipVerified": False,
                                            "methods": {method: "F13" for method in scoring.ML_METHODS}})
        snapshot = {"visibleStrokes": [{"points": [{"x": index, "y": 0.0}]} for index in range(6)],
                    "ownership": {"targetGroups": groups, "unassignedVisibleFragmentIndices": [],
                                  "barlineVisibleFragmentIndices": []}}
        run = {"id": run_id, "style": style, "phase": "afterCorrections", "status": "labeling",
               "profile": copy.deepcopy(new), "pipeline": "synthetic-pipeline", "records": records,
               "sourceCaptureState": "complete", "sourceSnapshot": snapshot,
               "profileLineage": {"querySessionID": run_id, "assuranceNote": "synthetic-only"}, "startedAt": 1.0}
        source["runs"].append(run)
        prediction["sources"].append({"runID": run_id, "style": style, "pipeline": run["pipeline"],
                                       "sourceSnapshot": copy.deepcopy(snapshot),
                                       "profileLineage": copy.deepcopy(run["profileLineage"]),
                                       "frozenProfileSHA256": "e" * 64, "sourcePacketSHA256": "p" * 64,
                                       "targets": targets})
        specifications.append({"runID": run_id, "style": style, "expectedChordCount": 6})
    annotated = copy.deepcopy(source)
    for run in annotated["runs"]:
        run.update(status="complete", finishedAt=3.0, expectedChordCount=6,
                   inkFeltSlow=False, unexpectedChartChanges=False)
        for record in run["records"]:
            record["intended"] = "F13"
    return {"prediction": prediction, "composition": composition, "sourceJournal": source,
            "annotatedJournal": annotated, "oldProfile": old, "newProfile": new,
            "currentProfile": copy.deepcopy(new)}, specifications


def committed(objects, specifications, root=Path("/private/tmp/synthetic-score")):
    objects = copy.deepcopy(objects)
    payloads = {key: scoring.canonical(objects[key]) for key in ("sourceJournal", "annotatedJournal", "oldProfile", "newProfile", "currentProfile")}
    objects["prediction"].update(sourceJournalSHA256=digest(payloads["sourceJournal"]),
                                  oldProfileFileSHA256=digest(payloads["oldProfile"]),
                                  newProfileFileSHA256=digest(payloads["newProfile"]))
    payloads["prediction"] = scoring.canonical(objects["prediction"])
    objects["composition"].update(predictionSHA256=digest(payloads["prediction"]),
                                   sourceJournalSHA256=digest(payloads["sourceJournal"]))
    payloads["composition"] = scoring.canonical(objects["composition"])
    request = {"version": scoring.REQUEST_VERSION, "runs": copy.deepcopy(specifications), "outputPath": str(root / "report.json")}
    for key in scoring.FILES:
        request[key + "Path"] = str(root / (key + ".json"))
        request[key + "SHA256"] = digest(payloads[key])
    return scoring.canonical(request), payloads


class FreshSymbolTransferScoringTests(unittest.TestCase):
    def setUp(self):
        self.objects, self.specifications = fixture()

    def report(self):
        request, payloads = committed(self.objects, self.specifications)
        return json.loads(scoring.score(request, payloads))

    def refuses(self, fragment):
        request, payloads = committed(self.objects, self.specifications)
        with self.assertRaisesRegex(scoring.ScoringError, fragment):
            scoring.score(request, payloads)

    def test_success_retains_seven_methods_two_styles_and_no_quality_claim(self):
        report = self.report()
        self.assertTrue(report["sameWriterDevelopmentOnly"])
        self.assertFalse(report["inferenceRerun"])
        self.assertFalse(report["trainingEligible"])
        self.assertFalse(report["ownershipVerified"])
        self.assertFalse(report["acrossWriterAccuracyEstablished"])
        for run in report["runs"]:
            self.assertEqual(run["writtenCount"], 6)
            self.assertEqual(run["eligibleCount"], 6)
            self.assertIsNone(run["wholeChartPercentage"])
            self.assertEqual(set(run["methods"]), set(scoring.METHODS))
            self.assertTrue(all(value["correct"] == 6 for value in run["methods"].values()))
        self.assertEqual(self.report(), report)

    def test_forbidden_run_native_profile_source_and_trajectory_mutations_refused(self):
        for kind in ("pipeline", "profile", "source", "native", "trajectory", "timing", "taught", "teachingReceipt"):
            with self.subTest(kind=kind):
                self.objects, self.specifications = fixture()
                run = self.objects["annotatedJournal"]["runs"][0]
                if kind == "pipeline": run["pipeline"] = "changed"
                elif kind == "profile": run["profile"]["generation"] = identifier("changed")
                elif kind == "source": run["sourceSnapshot"]["ownership"]["targetGroups"][0]["visibleFragmentIndices"] = [2]
                elif kind == "native": run["records"][0]["baseline"] = "E6"
                elif kind == "trajectory": run["sourceSnapshot"]["visibleStrokes"][0]["points"][0]["y"] = -0.0
                elif kind == "timing": run["records"][0]["recognitionMilliseconds"] = 2.0
                elif kind == "taught": run["records"][0]["taught"] = True
                else: run["teachingReceipt"] = {"savedAt": 4.0}
                self.refuses("mutation|taught|mismatch")

    def test_duplicate_run_and_record_identifiers_refused(self):
        self.objects["annotatedJournal"]["runs"][1]["id"] = self.objects["annotatedJournal"]["runs"][0]["id"]
        self.refuses("duplicate identifier")
        self.objects, self.specifications = fixture()
        records = self.objects["annotatedJournal"]["runs"][0]["records"]
        records[1]["id"] = records[0]["id"]
        self.refuses("duplicate identifier")

    def test_uncompleted_or_missing_annotation_refused_not_guessed(self):
        self.objects["annotatedJournal"] = copy.deepcopy(self.objects["sourceJournal"])
        self.refuses("completed run required")
        self.objects, self.specifications = fixture()
        self.objects["annotatedJournal"]["runs"][0]["records"][0].pop("intended")
        self.refuses("invalid saved label")

    def test_grouping_without_label_is_excluded_and_written_count_preserved(self):
        record = self.objects["annotatedJournal"]["runs"][0]["records"][0]
        record.update(intended=None, groupingIssue=True)
        run = self.report()["runs"][0]
        self.assertEqual((run["writtenCount"], run["capturedCount"], run["eligibleCount"], run["groupingIssueCount"]), (6, 6, 5, 1))
        self.assertEqual(run["rows"][0]["exclusions"], ["incorrectGrouping"])
        self.assertEqual(run["methods"]["sharedML"]["correct"], 5)

    def test_wrong_to_other_wrong_and_no_read_are_not_corrections(self):
        target = self.objects["composition"]["targets"][0]
        target["methods"].update(original34="E6", original37="Cmaj7", anchored34=None, anchored37="F13")
        run = self.report()["runs"][0]
        original = next(pair for pair in run["comparisons"] if pair["reference"] == "original34" and pair["candidate"] == "original37")
        self.assertEqual((original["corrections"], original["regressions"]), (0, 0))
        self.assertEqual(len(original["discordances"]), 1)
        anchored = next(pair for pair in run["comparisons"] if pair["reference"] == "anchored34" and pair["candidate"] == "anchored37")
        self.assertEqual((anchored["corrections"], anchored["regressions"]), (1, 0))
        self.assertEqual(run["methods"]["anchored34"]["noReads"], 1)
        self.assertEqual(run["methods"]["original37"]["wrongReads"], 1)

    def test_no_read_candidate_regresses_and_empty_native_is_wrong_not_nil(self):
        self.objects["composition"]["targets"][0]["methods"]["original37"] = None
        for key in ("sourceJournal", "annotatedJournal"):
            self.objects[key]["runs"][0]["records"][0]["baseline"] = ""
        run = self.report()["runs"][0]
        pair = next(pair for pair in run["comparisons"] if pair["reference"] == "original34" and pair["candidate"] == "original37")
        self.assertEqual((pair["corrections"], pair["regressions"]), (0, 1))
        self.assertEqual(run["methods"]["nativeBaseline"]["wrongReads"], 1)
        self.assertEqual(run["methods"]["nativeBaseline"]["noReads"], 0)

    def test_one_method_cannot_replace_other_or_missing_output(self):
        self.objects["composition"]["targets"][0]["methods"].pop("anchored37")
        self.refuses("all five methods required")
        self.objects, self.specifications = fixture()
        self.objects["composition"]["targets"][0]["methods"]["nativeBaseline"] = "F13"
        self.refuses("all five methods required")

    def test_composition_wrong_code_child_parent_or_duplicate_target_refused(self):
        for field in ("codeFileMapSHA256", "sourcePacketSHA256", "parentSourcePacketSHA256", "duplicate"):
            with self.subTest(field=field):
                self.objects, self.specifications = fixture()
                composition = self.objects["composition"]
                if field == "codeFileMapSHA256": composition[field] = "x" * 64
                elif field == "duplicate": composition["targets"][1] = copy.deepcopy(composition["targets"][0])
                else: composition["targets"][0][field] = "x" * 64
                self.refuses("binding|mismatched")

    def test_current_profile_or_old_support_change_refused(self):
        self.objects["currentProfile"]["revision"] = identifier("changed")
        self.refuses("current support changed")
        self.objects, self.specifications = fixture()
        self.objects["newProfile"]["examples"][0]["label"] = "changed"
        self.objects["currentProfile"] = copy.deepcopy(self.objects["newProfile"])
        self.refuses("previous support changed")

    def test_known_ink_exclusion_is_preserved(self):
        for key in ("sourceJournal", "annotatedJournal"):
            self.objects[key]["runs"][0]["records"][0]["knownInk"] = True
        run = self.report()["runs"][0]
        self.assertEqual(run["eligibleCount"], 5)
        self.assertEqual(run["rows"][0]["exclusions"], ["knownInk"])

    def test_no_fuzzy_or_enharmonic_label_matching(self):
        self.objects["composition"]["targets"][0]["methods"]["sharedML"] = "f13"
        run = self.report()["runs"][0]
        self.assertEqual(run["methods"]["sharedML"]["correct"], 5)
        self.assertEqual(run["methods"]["sharedML"]["wrongReads"], 1)

    def test_input_hash_duplicates_nonfinite_and_explicit_run_request_refused(self):
        request, payloads = committed(self.objects, self.specifications)
        changed = dict(payloads)
        changed["annotatedJournal"] += b" "
        with self.assertRaisesRegex(scoring.ScoringError, "SHA-256 mismatch"):
            scoring.score(request, changed)
        for data in (b'{"version":1,"version":1}', b'{"number":NaN}', b'{"number":1e999}'):
            with self.assertRaises(scoring.ScoringError):
                scoring._decode(data, 100, "synthetic")
        specification = copy.deepcopy(self.specifications)
        specification[0]["expectedChordCount"] = 5
        request, payloads = committed(self.objects, specification)
        with self.assertRaisesRegex(scoring.ScoringError, "six-written"):
            scoring.score(request, payloads)

    def test_cli_metadata_only_nonoverwrite_and_input_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            request, payloads = committed(self.objects, self.specifications, root)
            request_path = root / "request.json"
            request_path.write_bytes(request)
            for key, payload in payloads.items():
                (root / (key + ".json")).write_bytes(payload)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(scoring.main(["--request", str(request_path)]), 0)
            metadata = json.loads(output.getvalue())
            self.assertEqual(set(metadata), {"version", "runs", "reportSHA256", "inferenceRerun", "acrossWriterAccuracyEstablished"})
            self.assertEqual(metadata["reportSHA256"], digest((root / "report.json").read_bytes()))
            self.assertNotIn("F13", output.getvalue())
            with self.assertRaisesRegex(scoring.ScoringError, "already exists"):
                scoring.run_request(str(request_path))
            self.assertEqual(request_path.read_bytes(), request)
            for key, payload in payloads.items():
                self.assertEqual((root / (key + ".json")).read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
