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

from ichart_recognition_ml.research import personal_append_only_glyph_setup_scoring as scoring


def identifier(text):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "synthetic-score:" + text)).upper()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def lesson_delta(reference, candidate, raw_examples=None):
    additions = candidate["examples"][len(reference["examples"]):]
    raw_examples = raw_examples or [scoring.canonical(example) for example in additions]
    return {"referenceCount": len(reference["examples"]), "candidateCount": len(candidate["examples"]),
            "addedLessons": [{**{key: example[key] for key in ("id", "label", "kind", "source")},
                              "exampleData": base64.b64encode(raw).decode(), "exampleSHA256": digest(raw)}
                             for example, raw in zip(additions, raw_examples)]}


def fixture(reference_count=2, added_count=3):
    old = {"version": 1, "isEnabled": True, "revision": identifier("old-revision"),
           "generation": identifier("generation"), "learnsFromReviews": True,
           "examples": [{"id": identifier("lesson-" + str(index)), "kind": "glyph",
                         "source": "setup", "label": sorted(scoring.GLYPH_LABELS)[index % len(scoring.GLYPH_LABELS)], "strokes": []}
                        for index in range(reference_count)]}
    new = copy.deepcopy(old)
    new["revision"] = identifier("new-revision")
    new["examples"].extend({"id": identifier("addition-" + str(index)), "kind": "glyph",
                            "source": "setup", "label": "m" if index % 2 == 0 else "9", "strokes": []}
                           for index in range(added_count))
    delta = lesson_delta(old, new)
    source = {"version": 1, "runs": []}
    composition = {"version": scoring.COMPOSITION_VERSION, "codeFileMapSHA256": "c" * 64,
                   "inferenceRerun": False, "profileChanged": False, "accuracyMeasured": False,
                   "requestSHA256": "r" * 64, "composerDependencyHashes": {}, "targets": []}
    prediction = {"version": scoring.PREDICTION_VERSION, "codeFileMapSHA256": "c" * 64,
                  "referenceProfileCanonicalSHA256": "d" * 64, "candidateProfileCanonicalSHA256": "e" * 64,
                  "referenceExampleCount": reference_count, "candidateExampleCount": reference_count + added_count,
                  "supportDelta": copy.deepcopy(delta), "sources": []}
    composition.update(referenceProfileCanonicalSHA256="d" * 64, candidateProfileCanonicalSHA256="e" * 64,
                       referenceExampleCount=reference_count, candidateExampleCount=reference_count + added_count,
                       supportDelta=copy.deepcopy(delta))
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
                            "referenceProfileFreeze": {**copy.deepcopy(frozen), "legacyFreeze": {"profileSHA256": "d" * 64}},
                            "candidateProfileFreeze": {**copy.deepcopy(frozen), "legacyFreeze": {"profileSHA256": "e" * 64}}})
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
            "annotatedJournal": annotated, "referenceProfile": old, "candidateProfile": new,
            "currentProfile": copy.deepcopy(new), "supportDelta": delta}, specifications


def committed(objects, specifications, root=Path("/private/tmp/synthetic-score")):
    objects = copy.deepcopy(objects)
    payloads = {key: scoring.canonical(objects[key]) for key in ("sourceJournal", "annotatedJournal", "referenceProfile", "candidateProfile", "currentProfile")}
    objects["prediction"].update(sourceJournalSHA256=digest(payloads["sourceJournal"]),
                                  referenceProfileFileSHA256=digest(payloads["referenceProfile"]),
                                  candidateProfileFileSHA256=digest(payloads["candidateProfile"]))
    payloads["prediction"] = scoring.canonical(objects["prediction"])
    objects["composition"].update(predictionSHA256=digest(payloads["prediction"]),
                                   sourceJournalSHA256=digest(payloads["sourceJournal"]))
    payloads["composition"] = scoring.canonical(objects["composition"])
    request = {"version": scoring.REQUEST_VERSION, "runs": copy.deepcopy(specifications),
               "supportDelta": copy.deepcopy(objects["supportDelta"]), "outputPath": str(root / "report.json")}
    for key in scoring.FILES:
        request[key + "Path"] = str(root / (key + ".json"))
        request[key + "SHA256"] = digest(payloads[key])
    return scoring.canonical(request), payloads


class AppendOnlyGlyphSetupScoringTests(unittest.TestCase):
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
        target["methods"].update(originalReference="E6", originalCandidate="Cmaj7", anchoredReference=None, anchoredCandidate="F13")
        run = self.report()["runs"][0]
        original = next(pair for pair in run["comparisons"] if pair["reference"] == "originalReference" and pair["candidate"] == "originalCandidate")
        self.assertEqual((original["corrections"], original["regressions"]), (0, 0))
        self.assertEqual(len(original["discordances"]), 1)
        anchored = next(pair for pair in run["comparisons"] if pair["reference"] == "anchoredReference" and pair["candidate"] == "anchoredCandidate")
        self.assertEqual((anchored["corrections"], anchored["regressions"]), (1, 0))
        self.assertEqual(run["methods"]["anchoredReference"]["noReads"], 1)
        self.assertEqual(run["methods"]["originalCandidate"]["wrongReads"], 1)

    def test_no_read_candidate_regresses_and_empty_native_is_wrong_not_nil(self):
        self.objects["composition"]["targets"][0]["methods"]["originalCandidate"] = None
        for key in ("sourceJournal", "annotatedJournal"):
            self.objects[key]["runs"][0]["records"][0]["baseline"] = ""
        run = self.report()["runs"][0]
        pair = next(pair for pair in run["comparisons"] if pair["reference"] == "originalReference" and pair["candidate"] == "originalCandidate")
        self.assertEqual((pair["corrections"], pair["regressions"]), (0, 1))
        self.assertEqual(run["methods"]["nativeBaseline"]["wrongReads"], 1)
        self.assertEqual(run["methods"]["nativeBaseline"]["noReads"], 0)

    def test_one_method_cannot_replace_other_or_missing_output(self):
        self.objects["composition"]["targets"][0]["methods"].pop("anchoredCandidate")
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
        self.objects["candidateProfile"]["examples"][0]["label"] = "changed"
        self.objects["currentProfile"] = copy.deepcopy(self.objects["candidateProfile"])
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
        specification[0]["expectedChordCount"] = 0
        request, payloads = committed(self.objects, specification)
        with self.assertRaisesRegex(scoring.ScoringError, "bounded written"):
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

    def test_generic_profile_counts_zero_reference_and_multiple_setup_additions(self):
        for reference_count, added_count in ((0, 1), (2, 4), (37, 3)):
            with self.subTest(reference=reference_count, added=added_count):
                self.objects, self.specifications = fixture(reference_count, added_count)
                report = self.report()
                self.assertEqual(report['referenceExampleCount'], reference_count)
                self.assertEqual(report['candidateExampleCount'], reference_count + added_count)
                self.assertEqual(report['supportDelta'], self.objects['supportDelta'])
                self.assertEqual(report['primaryComparison'], {'reference': 'originalReference', 'candidate': 'originalCandidate'})

    def test_append_requires_distinct_uuid_revision_and_unchanged_root_fields(self):
        for mutation in ('unchangedRevision', 'invalidRevision', 'generation', 'learnsFromReviews'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                candidate = self.objects['candidateProfile']
                if mutation == 'unchangedRevision': candidate['revision'] = self.objects['referenceProfile']['revision']
                elif mutation == 'invalidRevision': candidate['revision'] = 'invalid'
                elif mutation == 'generation': candidate['generation'] = identifier('changed-generation')
                else: candidate['learnsFromReviews'] = False
                self.objects['currentProfile'] = copy.deepcopy(candidate)
                self.refuses('revision|previous support changed')

    def test_delta_count_metadata_source_and_glyph_alphabet_mismatch_refused(self):
        for mutation in ('counts', 'label', 'unsupported', 'kind', 'source'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                delta = self.objects['supportDelta']
                lesson = delta['addedLessons'][0]
                if mutation == 'counts': delta['candidateCount'] += 1
                elif mutation == 'label': lesson['label'] = '9'
                elif mutation == 'unsupported': lesson['label'] = 'maj7'
                elif mutation == 'kind': lesson['kind'] = 'chord'
                else: lesson['source'] = 'explicitCorrection'
                self.refuses('supportDelta')

    def test_raw_example_hash_base64_duplicate_keys_and_nonfinite_json_refused(self):
        for mutation in ('hash', 'base64', 'duplicate', 'nonfinite'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                lesson = self.objects['supportDelta']['addedLessons'][0]
                if mutation == 'hash': lesson['exampleSHA256'] = 'f' * 64
                elif mutation == 'base64': lesson['exampleData'] = 'not base64!'
                else:
                    raw = b'{"id":1,"id":2}' if mutation == 'duplicate' else b'{"number":NaN}'
                    lesson.update(exampleData=base64.b64encode(raw).decode(), exampleSHA256=digest(raw))
                self.refuses('supportDelta')

    def test_suffix_order_and_complete_example_objects_must_match_delta(self):
        for mutation in ('order', 'point', 'extraField'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                candidate = self.objects['candidateProfile']
                if mutation == 'order': candidate['examples'][-2:] = reversed(candidate['examples'][-2:])
                elif mutation == 'point': candidate['examples'][-1]['strokes'] = [{'points': [{'x': 1.25, 'y': 2.5}]}]
                else: candidate['examples'][-1]['unexpected'] = True
                self.objects['currentProfile'] = copy.deepcopy(candidate)
                self.refuses('ordered appended suffix mismatch')

    def test_prior_reordering_removal_and_cap_eviction_are_refused(self):
        for mutation in ('reorder', 'remove', 'evict'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                candidate = self.objects['candidateProfile']
                if mutation == 'reorder': candidate['examples'][:2] = reversed(candidate['examples'][:2])
                elif mutation == 'remove': candidate['examples'].pop(0)
                else: candidate['examples'] = candidate['examples'][1:] + [copy.deepcopy(candidate['examples'][-1])]
                self.objects['currentProfile'] = copy.deepcopy(candidate)
                self.refuses('support counts|previous support changed')

    def test_duplicate_suffix_and_reference_ids_case_variants_refused(self):
        for case_variant in (False, True):
            with self.subTest(case_variant=case_variant):
                self.objects, self.specifications = fixture()
                candidate = self.objects['candidateProfile']
                candidate['examples'][-1]['id'] = self.objects['referenceProfile']['examples'][0]['id']
                if case_variant: candidate['examples'][-1]['id'] = candidate['examples'][-1]['id'].lower()
                self.objects['supportDelta'] = lesson_delta(self.objects['referenceProfile'], candidate)
                self.objects['currentProfile'] = copy.deepcopy(candidate)
                self.refuses('duplicate')
        self.objects, self.specifications = fixture()
        self.objects['supportDelta']['addedLessons'][1] = copy.deepcopy(self.objects['supportDelta']['addedLessons'][0])
        self.refuses('duplicate')

    def test_profile_count_request_and_prediction_composition_binding_mismatches_refused(self):
        for mutation in ('profileCount', 'predictionCount', 'compositionCount', 'predictionDelta', 'compositionDelta'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                if mutation == 'profileCount':
                    self.objects['supportDelta']['referenceCount'] += 1
                    self.objects['supportDelta']['candidateCount'] += 1
                elif mutation == 'predictionCount': self.objects['prediction']['referenceExampleCount'] += 1
                elif mutation == 'compositionCount': self.objects['composition']['candidateExampleCount'] = True
                else:
                    key = 'prediction' if mutation == 'predictionDelta' else 'composition'
                    self.objects[key]['supportDelta']['addedLessons'][0]['exampleSHA256'] = 'f' * 64
                self.refuses('counts|count mismatch|supportDelta mismatch')

    def test_producer_canonical_hash_is_not_python_reencoded_float_json_hash(self):
        candidate = self.objects['candidateProfile']
        candidate['examples'][-1]['strokes'] = [{'points': [{'x': 0.1094272858107098, 'y': 1e-7}]}]
        delta = lesson_delta(self.objects['referenceProfile'], candidate,
                             [json.dumps(e, ensure_ascii=False, indent=2).encode() for e in candidate['examples'][2:]])
        self.objects['supportDelta'] = delta
        for key in ('prediction', 'composition'): self.objects[key]['supportDelta'] = copy.deepcopy(delta)
        self.objects['currentProfile'] = copy.deepcopy(candidate)
        for key in ('sourceJournal', 'annotatedJournal'):
            for run in self.objects[key]['runs']: run['profile'] = copy.deepcopy(candidate)
        self.assertNotEqual('e' * 64, digest(scoring.canonical(candidate)))
        self.assertNotEqual(base64.b64decode(delta['addedLessons'][-1]['exampleData']), scoring.canonical(candidate['examples'][-1]))
        report = self.report()
        self.assertFalse(report['profileCanonicalHashRecomputed'])
        self.assertEqual(report['candidateProfileCanonicalSHA256'], 'e' * 64)
        self.assertEqual(report['supportDelta'], delta)

    def test_canonical_profile_hash_changes_per_target_or_composer_refused(self):
        for mutation in ('invalidHex', 'targetReference', 'targetCandidate', 'composer'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                if mutation == 'invalidHex': self.objects['prediction']['referenceProfileCanonicalSHA256'] = 'x' * 64
                elif mutation == 'composer': self.objects['composition']['candidateProfileCanonicalSHA256'] = 'f' * 64
                else:
                    field = 'referenceProfileFreeze' if mutation == 'targetReference' else 'candidateProfileFreeze'
                    self.objects['prediction']['sources'][0]['targets'][0][field]['legacyFreeze']['profileSHA256'] = 'f' * 64
                self.refuses('canonical|support binding')

    def test_variable_written_counts_missing_extra_and_raw_denominators(self):
        for specification, annotated in zip(self.specifications, self.objects['annotatedJournal']['runs']):
            written = 1 if specification['style'] == sorted(scoring.STYLES)[0] else 64
            specification['expectedChordCount'] = written
            annotated['expectedChordCount'] = written
        runs = self.report()['runs']
        self.assertEqual((runs[0]['writtenCount'], runs[0]['capturedCount'], runs[0]['extraCapturedCount'], runs[0]['missingCount']), (1, 6, 5, 0))
        self.assertEqual((runs[1]['writtenCount'], runs[1]['capturedCount'], runs[1]['extraCapturedCount'], runs[1]['missingCount']), (64, 6, 0, 58))
        self.assertTrue(all(value['missingWrittenAttempts'] == 58 for value in runs[1]['methods'].values()))
        self.assertTrue(all(run['wholeChartPercentage'] is None for run in runs))

    def test_written_count_type_bounds_and_annotation_count_mismatch(self):
        for value in (0, 65, True, 6.0, '6'):
            with self.subTest(value=value):
                specs = copy.deepcopy(self.specifications)
                specs[0]['expectedChordCount'] = value
                request, payloads = committed(self.objects, specs)
                with self.assertRaisesRegex(scoring.ScoringError, 'bounded written'):
                    scoring.score(request, payloads)
        self.specifications[0]['expectedChordCount'] = 4
        self.refuses('written count differs')

    def test_no_read_to_wrong_is_visible_harm_even_without_correct_read_regression(self):
        methods = self.objects['composition']['targets'][0]['methods']
        methods['originalReference'], methods['originalCandidate'] = None, 'E6'
        primary = self.report()['runs'][0]['primaryComparison']
        self.assertEqual((primary['corrections'], primary['regressions'], primary['noReadToWrong'], primary['harms']), (0, 0, 1, 1))
        self.assertTrue(primary['discordances'][0]['noReadToWrong'])
        self.assertTrue(primary['discordances'][0]['harm'])

    def test_missing_original_input_and_combined_exclusions_remain_visible(self):
        for key in ('sourceJournal', 'annotatedJournal'):
            self.objects[key]['runs'][0]['records'][0].update(recognitionStrokes=None, knownInk=True)
        run = self.report()['runs'][0]
        self.assertEqual(run['eligibleCount'], 5)
        self.assertEqual(run['rows'][0]['exclusions'], ['knownInk', 'missingOriginalInput'])
        self.assertEqual(run['capturedCount'], 6)
        self.assertEqual(run['writtenCount'], 6)

    def test_capture_coverage_not_relaxed_by_variable_written_count(self):
        for mutation in ('missingComposition', 'missingPrediction', 'wrongOrdinal', 'wrongOwnership'):
            with self.subTest(mutation=mutation):
                self.objects, self.specifications = fixture()
                self.specifications[0]['expectedChordCount'] = 1
                self.objects['annotatedJournal']['runs'][0]['expectedChordCount'] = 1
                if mutation == 'missingComposition': self.objects['composition']['targets'].pop(0)
                elif mutation == 'missingPrediction': self.objects['prediction']['sources'][0]['targets'].pop(0)
                elif mutation == 'wrongOrdinal': self.objects['prediction']['sources'][0]['targets'][0]['targetOrdinal'] = 99
                else: self.objects['prediction']['sources'][0]['targets'][0]['childToParentVisibleFragmentIndices'] = []
                self.refuses('coverage|count mismatch|ordinal|ownership')

    def test_global_profile_capacity_and_boolean_counts_are_not_accepted(self):
        for reference, candidate in ((192, 193), (True, 4), (2, True), (2.0, 5)):
            delta = copy.deepcopy(self.objects['supportDelta'])
            delta.update(referenceCount=reference, candidateCount=candidate)
            with self.subTest(reference=reference, candidate=candidate), self.assertRaisesRegex(scoring.ScoringError, 'counts'):
                scoring._validate_delta(delta)


if __name__ == "__main__":
    unittest.main()
