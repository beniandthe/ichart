import contextlib
import copy
import hashlib
import io
import stat
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.research import blind_ink_annotation as annotation
from ichart_recognition_ml.research import blind_ink_evaluation as evaluation
from test_blind_ink_annotation import changed, decode, role_hash
from test_study_import import packet_bytes, point, stroke


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def arm(groups, shared, personal):
    return {
        "outcome": "read",
        "glyphs": [
            {"originalStrokeIndexes": list(indexes), "sharedTop1": baseline,
             "personalTop1": adapted}
            for indexes, baseline, adapted in zip(groups, shared, personal)
        ],
    }


class BlindInkEvaluationTests(unittest.TestCase):
    WRITER = role_hash("evaluation-writer")
    OWNERS = (role_hash("evaluation-owner-one"), role_hash("evaluation-owner-two"))
    READERS = (role_hash("evaluation-reader-one"), role_hash("evaluation-reader-two"))

    def make_query(self, *, groups=((0, 2), (1, 3)), symbols=("B", "G"),
                   shared=None, personal=None, identity_outcomes=None,
                   unresolved=False, seed=0, writer=None, style="simple-chord-sheet"):
        """Every packet, review, prediction and metadata value is synthetic."""
        writer = self.WRITER if writer is None else writer
        source = packet_bytes([
            stroke([point(seed * 100 + index * 10, index),
                    point(seed * 100 + index * 10 + 1, index + 2)])
            for index in range(max(index for group in groups for index in group) + 1)
        ])
        packet = annotation.make_ownership_packet(source)
        reviews = [
            annotation.make_ownership_review(packet, reviewer, outcome="unresolved")
            if unresolved else annotation.make_ownership_review(packet, reviewer, groups)
            for reviewer in self.OWNERS
        ]
        receipt = annotation.freeze_ownership(packet, *reviews, writer_hash=writer)
        identities = []
        if not unresolved:
            identity_outcomes = identity_outcomes or ("symbol",) * len(symbols)
            for identity, symbol, outcome in zip(
                    annotation.make_identity_packets(packet, receipt), symbols, identity_outcomes):
                kwargs = {"symbol": symbol} if outcome == "symbol" else {"outcome": outcome}
                identity_reviews = [
                    annotation.make_identity_review(identity, reviewer, **kwargs)
                    for reviewer in self.READERS
                ]
                identities.append((identity, annotation.freeze_identity(
                    identity, *identity_reviews, writer_hash=writer,
                    ownership_reviewer_hashes=self.OWNERS,
                    ownership_packet_bytes=packet, ownership_receipt_bytes=receipt,
                )))
        hypotheses = arm(groups, symbols if shared is None else shared,
                         symbols if personal is None else personal)
        prediction = canonical_json_bytes({
            "version": evaluation.PREDICTION_VERSION,
            "artifactKind": evaluation.ARTIFACT_KIND,
            "sourcePacketSHA256": digest(source),
            "ownershipReceiptSHA256": digest(receipt),
            "sourceStrokeCount": len(decode(source)["strokes"]),
            "encoderIdentity": "synthetic-encoder-v1",
            "profileSHA256": role_hash("evaluation-profile"),
            "runtimeSHA256": role_hash("evaluation-runtime"),
            "codeSHA256": role_hash("evaluation-code"),
            "automatic": hypotheses,
            "supplied": None if unresolved else copy.deepcopy(hypotheses),
        })
        return evaluation.QueryEvidence(prediction, packet, receipt, tuple(identities), {
            "writerIDHash": writer,
            "querySessionIDHash": role_hash("evaluation-query-session"),
            "supportSessionIDHashes": [role_hash("evaluation-support-session")],
            "chartStyle": style,
            "evidenceClass": "synthetic-contract-test",
        })

    def mutate_prediction(self, query, mutate):
        return replace(query, prediction=changed(query.prediction, mutate))

    def assert_code(self, code, operation):
        with self.assertRaises(ContractError) as caught:
            operation()
        self.assertEqual(caught.exception.code, code)

    def report(self, *queries):
        return decode(evaluation.evaluate_batch(queries))

    def write_manifest(self, directory, queries):
        items = []
        for index, query in enumerate(queries):
            paths = {}
            for key, payload in (("prediction", query.prediction),
                                 ("ownershipPacket", query.ownership_packet),
                                 ("ownershipReceipt", query.ownership_receipt)):
                name = f"query-{index}-{key}.json"
                (directory / name).write_bytes(payload)
                paths[key] = name
            paths["identityArtifacts"] = []
            for owner, (packet, receipt) in enumerate(query.identity_artifacts):
                names = {"packet": f"query-{index}-identity-{owner}.json",
                         "receipt": f"query-{index}-identity-{owner}-receipt.json"}
                for name, payload in ((names["packet"], packet), (names["receipt"], receipt)):
                    (directory / name).write_bytes(payload)
                paths["identityArtifacts"].append(names)
            paths["metadata"] = dict(query.metadata)
            items.append(paths)
        manifest = directory / "manifest.json"
        manifest.write_bytes(canonical_json_bytes({
            "version": "blind-ink-evaluation-manifest-v1", "queries": items,
        }))
        return manifest

    def test_exact_original_index_join_survives_reordered_outer_groups(self):
        query = self.make_query(shared=("X", "G"), personal=("B", "Y"))
        reordered = self.mutate_prediction(query, lambda value: [
            value[mode]["glyphs"].reverse() for mode in ("automatic", "supplied")
        ])
        reordered = replace(reordered, identity_artifacts=query.identity_artifacts[::-1])
        before = (query.prediction, query.ownership_packet, query.ownership_receipt,
                  query.identity_artifacts)
        result = evaluation.evaluate_query(reordered)
        self.assertEqual(result["glyphs"], evaluation.evaluate_query(query)["glyphs"])
        self.assertEqual([row["originalStrokeIndexes"] for row in result["glyphs"]],
                         [[0, 2], [1, 3]])
        self.assertEqual([(row["sharedTop1"], row["personalTop1"]) for row in result["glyphs"]],
                         [("X", "B"), ("G", "Y")])
        self.assertTrue(result["automaticExactOwnership"])
        self.assertEqual(before, (query.prediction, query.ownership_packet,
                                  query.ownership_receipt, query.identity_artifacts))

    def test_raw_case_and_symbol_spelling_are_never_chord_canonicalized(self):
        query = self.make_query(groups=((0,), (1,), (2,), (3,)),
                                symbols=("b", "♯", "∆", "é"),
                                shared=("B", "#", "△", "e"))
        result = evaluation.evaluate_query(query)
        self.assertEqual(result["counts"]["conditionalSharedCorrect"], 0)
        self.assertEqual(result["counts"]["conditionalPersonalCorrect"], 4)
        self.assertEqual(result["counts"]["personalGains"], 4)
        self.assertEqual([row["symbol"] for row in result["glyphs"]], ["b", "♯", "∆", "é"])
        for symbol in ("Bb7", "e\u0301", "", " ", "\n", 7):
            with self.subTest(symbol=repr(symbol)):
                bad = self.mutate_prediction(query, lambda value: value["supplied"]["glyphs"][0].update(
                    {"sharedTop1": symbol}))
                self.assert_code("invalid_symbol", lambda: evaluation.evaluate_query(bad))

    def test_personal_gains_and_harms_and_both_outcomes_are_paired(self):
        query = self.make_query(groups=((0,), (1,), (2,), (3,)),
                                symbols=("B", "G", "C", "D"),
                                shared=("X", "G", "C", "Y"),
                                personal=("B", "X", "C", "Z"))
        counts = evaluation.evaluate_query(query)["counts"]
        for name, expected in (("resolvedGlyphs", 4), ("conditionalSharedCorrect", 2),
                               ("conditionalPersonalCorrect", 2), ("personalGains", 1),
                               ("personalHarms", 1), ("bothCorrect", 1), ("bothWrong", 1)):
            with self.subTest(counter=name):
                self.assertEqual(counts[name], expected)
        report = self.report(query)
        self.assertEqual(report["rates"]["personalGain"],
                         {"numerator": 1, "denominator": 4, "value": 0.25})
        self.assertEqual(report["rates"]["personalHarm"],
                         {"numerator": 1, "denominator": 4, "value": 0.25})

    def test_conditional_matched_and_overall_owner_denominators_are_explicit(self):
        query = self.make_query(groups=((0, 2), (1, 3), (4,), (5,)),
                                symbols=("B", "G", "C", "D"))
        query = self.mutate_prediction(query, lambda value: value.update({
            "automatic": arm(((0, 2), (1, 3, 4), (5,)), ("B", "G", "D"), ("B", "G", "D"))}))
        report = self.report(query)
        self.assertEqual(report["counts"]["automaticMatchedOwners"], 2)
        self.assertEqual(report["counts"]["automaticResolvedMatchedOwners"], 2)
        for name, expected in (
                ("conditionalSharedIdentity", {"numerator": 4, "denominator": 4, "value": 1.0}),
                ("automaticSharedOverResolvedOwners", {"numerator": 2, "denominator": 4, "value": 0.5}),
                ("automaticSharedOnMatchedOwners", {"numerator": 2, "denominator": 2, "value": 1.0}),
                ("exactOwnership", {"numerator": 0, "denominator": 1, "value": 0.0})):
            with self.subTest(rate=name):
                self.assertEqual(report["rates"][name], expected)

    def test_split_or_merged_automatic_owners_are_not_answer_aligned(self):
        query = self.make_query()
        for groups, shared in ((((0,), (1,), (2,), (3,)), ("B", "G", "B", "G")),
                               (((0, 1, 2, 3),), ("B",))):
            with self.subTest(groups=groups):
                bad_groups = self.mutate_prediction(query, lambda value: value.update({
                    "automatic": arm(groups, shared, shared)}))
                result = evaluation.evaluate_query(bad_groups)
                self.assertFalse(result["automaticExactOwnership"])
                self.assertEqual(result["counts"]["automaticMatchedOwners"], 0)
                self.assertEqual(result["counts"]["automaticSharedCorrect"], 0)
                self.assertEqual(result["counts"]["conditionalSharedCorrect"], 2)
                self.assertTrue(all(not row["automaticMatchedOwner"] for row in result["glyphs"]))

    def test_unresolved_ownership_is_retained_and_zero_denominators_are_null(self):
        query = self.make_query(unresolved=True)
        report = self.report(query)
        row = report["rows"][0]
        self.assertEqual(report["counts"]["queries"], 1)
        self.assertEqual(report["counts"]["ownershipUnresolvedQueries"], 1)
        self.assertEqual(report["counts"]["resolvedGlyphs"], 0)
        self.assertIsNone(row["automaticExactOwnership"])
        self.assertEqual(row["glyphs"], [])
        for name, rate in report["rates"].items():
            with self.subTest(rate=name):
                self.assertEqual(rate, {"numerator": 0, "denominator": 0, "value": None})
        guessed = self.mutate_prediction(query, lambda value: value.update({"supplied": value["automatic"]}))
        self.assert_code("unresolved_supplied_arm", lambda: evaluation.evaluate_query(guessed))

    def test_unresolved_identity_is_retained_without_success_credit(self):
        query = self.make_query(groups=((0,), (1,), (2,), (3,)), symbols=("B", "G", "C", "D"),
                                identity_outcomes=("symbol", "human-ambiguous", "no-read", "symbol"))
        result = evaluation.evaluate_query(query)
        counts = result["counts"]
        self.assertEqual(counts["resolvedGlyphs"], 2)
        self.assertEqual(counts["unresolvedGlyphs"], 2)
        self.assertEqual(counts["conditionalSharedCorrect"], 2)
        self.assertEqual(counts["automaticMatchedOwners"], 4)
        self.assertEqual(counts["automaticResolvedMatchedOwners"], 2)
        for row, outcome in zip(result["glyphs"][1:3], ("human-ambiguous", "no-read")):
            with self.subTest(outcome=outcome):
                self.assertEqual(row["identityOutcome"], outcome)
                for key in ("symbol", "sharedCorrect", "personalCorrect"):
                    self.assertIsNone(row[key])
        self.assertEqual(self.report(query)["rates"]["conditionalSharedIdentity"]["denominator"], 2)

    def test_invalid_ink_stays_in_query_and_resolved_glyph_denominators(self):
        query = self.make_query()
        query = self.mutate_prediction(query, lambda value: value.update({
            mode: {"outcome": "invalid-ink", "glyphs": []} for mode in ("automatic", "supplied")}))
        report = self.report(query)
        for name, expected in (("queries", 1), ("resolvedGlyphs", 2),
                               ("automaticInvalidInkQueries", 1), ("suppliedInvalidInkQueries", 1),
                               ("conditionalSharedNoRead", 2), ("conditionalPersonalNoRead", 2),
                               ("bothWrong", 2), ("automaticSharedCorrect", 0)):
            with self.subTest(counter=name):
                self.assertEqual(report["counts"][name], expected)
        self.assertEqual(report["rates"]["conditionalSharedIdentity"],
                         {"numerator": 0, "denominator": 2, "value": 0.0})
        self.assertIsNone(report["rates"]["automaticSharedOnMatchedOwners"]["value"])

    def test_no_read_is_distinct_from_wrong_top1_and_neither_is_correct(self):
        query = self.make_query(shared=(None, "X"), personal=("Y", None))
        result = evaluation.evaluate_query(query)
        counts = result["counts"]
        self.assertEqual(counts["conditionalSharedNoRead"], 1)
        self.assertEqual(counts["conditionalPersonalNoRead"], 1)
        self.assertEqual(counts["bothWrong"], 2)
        self.assertEqual(counts["conditionalSharedCorrect"], 0)
        self.assertEqual(counts["conditionalPersonalCorrect"], 0)
        self.assertEqual([row["sharedTop1"] for row in result["glyphs"]], [None, "X"])
        self.assertEqual([row["personalTop1"] for row in result["glyphs"]], ["Y", None])
        self.assertTrue(all(row["sharedCorrect"] is False and row["personalCorrect"] is False
                            for row in result["glyphs"]))

    def test_source_receipt_prediction_and_identity_tamper_are_refused(self):
        query = self.make_query()
        identity, receipt = query.identity_artifacts[0]
        cases = [
            ("source_binding_mismatch", replace(query, ownership_packet=changed(query.ownership_packet,
                lambda value: value.update({"sourcePacketSHA256": "0" * 64})))),
            ("receipt_evidence_mismatch", replace(query, ownership_receipt=changed(query.ownership_receipt,
                lambda value: value.update({"originalIndexGroups": [[0, 1], [2, 3]]})))),
            ("identity_binding_mismatch", replace(query, identity_artifacts=((changed(identity,
                lambda value: value.update({"sourcePacketSHA256": "0" * 64})), receipt),
                query.identity_artifacts[1]))),
            ("receipt_evidence_mismatch", replace(query, identity_artifacts=((identity, changed(receipt,
                lambda value: value.update({"symbol": "X"}))), query.identity_artifacts[1]))),
        ]
        for field in ("sourcePacketSHA256", "ownershipReceiptSHA256"):
            cases.append(("prediction_binding_mismatch", self.mutate_prediction(query,
                lambda value, field=field: value.update({field: "0" * 64}))))
        for code, bad in cases:
            with self.subTest(code=code, prediction=digest(bad.prediction)):
                self.assert_code(code, lambda: evaluation.evaluate_query(bad))

    def test_missing_duplicate_or_foreign_identity_evidence_is_refused(self):
        query = self.make_query()
        cases = (
            ("incomplete_identity_evidence", query.identity_artifacts[:1]),
            ("duplicate_identity", query.identity_artifacts + query.identity_artifacts[:1]),
            ("identity_binding_mismatch", self.make_query(seed=1).identity_artifacts),
        )
        for code, identities in cases:
            with self.subTest(code=code):
                self.assert_code(code, lambda: evaluation.evaluate_query(
                    replace(query, identity_artifacts=identities)))
        unresolved = self.make_query(unresolved=True)
        self.assert_code("identity_binding_mismatch", lambda: evaluation.evaluate_query(
            replace(unresolved, identity_artifacts=query.identity_artifacts)))
        for identities in (None, [query.identity_artifacts[0][:1]], [[b"{}", "receipt"]]):
            with self.subTest(malformed=identities):
                self.assert_code("invalid_identity_artifacts", lambda: evaluation.evaluate_query(
                    replace(query, identity_artifacts=identities)))

    def test_malformed_partial_and_wrong_supplied_partitions_are_refused(self):
        query = self.make_query()
        partitions = (
            ("invalid_indexes", ((2, 0), (1, 3))),
            ("invalid_indexes", ((0, 0, 2), (1, 3))),
            ("invalid_indexes", ((True, 2), (1, 3))),
            ("invalid_indexes", ((-1, 2), (1, 3))),
            ("invalid_indexes", ((0, 4), (1, 3))),
            ("invalid_partition", ((0, 2), (1,))),
            ("invalid_partition", ((0, 2), (0, 1, 3))),
            ("invalid_partition", ((0, 1, 2, 3), (0, 1, 2, 3))),
        )
        for mode in ("automatic", "supplied"):
            for code, groups in partitions:
                with self.subTest(mode=mode, groups=groups):
                    bad = self.mutate_prediction(query, lambda value: value.update({
                        mode: arm(groups, ("B", "G"), ("B", "G"))}))
                    self.assert_code(code, lambda: evaluation.evaluate_query(bad))
            for code, bad_arm in (("invalid_arm", None),
                                  ("invalid_arm", {"outcome": "read", "glyphs": []}),
                                  ("invalid_arm", {"outcome": "no-read", "glyphs": []}),
                                  ("partial_failed_arm", {"outcome": "invalid-ink", "glyphs": [{}]})):
                with self.subTest(mode=mode, arm=bad_arm):
                    bad = self.mutate_prediction(query, lambda value: value.update({mode: bad_arm}))
                    self.assert_code(code, lambda: evaluation.evaluate_query(bad))
        wrong = self.mutate_prediction(query, lambda value: value.update({
            "supplied": arm(((0, 1), (2, 3)), ("B", "G"), ("B", "G"))}))
        self.assert_code("supplied_ownership_mismatch", lambda: evaluation.evaluate_query(wrong))

    def test_invalid_metadata_profile_runtime_and_source_counts_are_refused(self):
        query = self.make_query()
        self.assert_code("invalid_query", lambda: evaluation.evaluate_query(None))
        metadata_cases = (
            ("writer_binding_mismatch", {"writerIDHash": role_hash("different-writer")}),
            ("invalid_sha256", {"querySessionIDHash": "session"}),
            ("invalid_sha256", {"writerIDHash": "writer"}),
            ("invalid_support_sessions", {"supportSessionIDHashes": "session"}),
            ("invalid_sha256", {"supportSessionIDHashes": ["session"]}),
            ("support_query_overlap", {"supportSessionIDHashes": [query.metadata["querySessionIDHash"]]}),
            ("support_query_overlap", {"supportSessionIDHashes": [role_hash("s")] * 2}),
            ("invalid_chart_style", {"chartStyle": "lead-sheet"}),
            ("invalid_evidence_class", {"evidenceClass": "sealed-new-writer"}),
            ("wrong_fields", {"profile": "answer-aware"}),
        )
        for code, update in metadata_cases:
            with self.subTest(metadata=update):
                bad = replace(query, metadata={**query.metadata, **update})
                self.assert_code(code, lambda: evaluation.evaluate_query(bad))
        self.assert_code("invalid_metadata", lambda: evaluation.evaluate_query(replace(query, metadata=None)))
        prediction_cases = [
            ("source_count_mismatch", {"sourceStrokeCount": value}) for value in (3, True, 4.0)
        ] + [
            ("invalid_sha256", {field: "not-a-sha256"})
            for field in ("profileSHA256", "runtimeSHA256", "codeSHA256")
        ] + [
            ("invalid_encoder_identity", {"encoderIdentity": value}) for value in (" ", "x" * 513, None)
        ] + [("wrong_version", {"version": "other"}), ("wrong_fields", {"sessionIDHash": "0" * 64})]
        for code, update in prediction_cases:
            with self.subTest(prediction=update):
                bad = self.mutate_prediction(query, lambda value: value.update(update))
                self.assert_code(code, lambda: evaluation.evaluate_query(bad))

    def test_batch_refuses_duplicate_sources_and_mixed_writer_profiles_or_runtime(self):
        first, second = self.make_query(), self.make_query(seed=1)
        for queries in ((), (first,) * 513):
            with self.subTest(query_count=len(queries)):
                self.assert_code("invalid_query_count", lambda: evaluation.evaluate_batch(queries))
        self.assert_code("duplicate_source", lambda: evaluation.evaluate_batch((first, first)))
        for field in ("runtimeSHA256", "codeSHA256", "encoderIdentity", "profileSHA256"):
            with self.subTest(field=field):
                bad = self.mutate_prediction(second, lambda value: value.update({
                    field: "synthetic-other-encoder" if field == "encoderIdentity" else role_hash("other-" + field)}))
                self.assert_code("mixed_writer_profile" if field == "profileSHA256" else "mixed_runtime",
                                 lambda: evaluation.evaluate_batch((first, bad)))
        bad = replace(second, metadata={**second.metadata,
                                      "supportSessionIDHashes": [role_hash("other-support")]})
        self.assert_code("mixed_writer_profile", lambda: evaluation.evaluate_batch((first, bad)))
        support = [role_hash("support-a"), role_hash("support-b")]
        forward = replace(first, metadata={**first.metadata, "supportSessionIDHashes": support})
        reverse = replace(second, metadata={**second.metadata, "supportSessionIDHashes": support[::-1]})
        report = self.report(forward, reverse)
        self.assertTrue(all(row["metadata"]["supportSessionIDHashes"] == sorted(support)
                            for row in report["rows"]))

    def test_canonical_batch_has_both_chart_styles_and_explicit_metadata_slices(self):
        first = self.make_query()
        second = self.make_query(seed=1, style="rhythm-section-sheet", writer=role_hash("writer-two"))
        second = replace(second, metadata={**second.metadata,
            "querySessionIDHash": role_hash("session-two"), "evidenceClass": "development-capture"})
        second = self.mutate_prediction(second, lambda value: value.update({"profileSHA256": role_hash("profile-two")}))
        payload = evaluation.evaluate_batch((first, second))
        report = decode(payload)
        self.assertEqual(payload, canonical_json_bytes(report))
        self.assertEqual(payload, evaluation.evaluate_batch((second, first)))
        self.assertEqual(report["counts"]["queries"], 2)
        self.assertEqual(set(report["slices"]),
                         {"writerIDHash", "querySessionIDHash", "chartStyle", "evidenceClass"})
        self.assertEqual(set(report["slices"]["chartStyle"]),
                         {"simple-chord-sheet", "rhythm-section-sheet"})
        for field, slices in report["slices"].items():
            with self.subTest(slice=field):
                self.assertEqual(len(slices), 2)
                self.assertEqual(sum(counts["queries"] for counts in slices.values()), 2)
                self.assertTrue(all(counts["resolvedGlyphs"] == 2 for counts in slices.values()))
        self.assertEqual([row["sourcePacketSHA256"] for row in report["rows"]],
                         sorted(row["sourcePacketSHA256"] for row in report["rows"]))
        for field in ("trainingEligible", "newWriterAccuracyVerified", "fullChordAccuracyMeasured",
                      "metadataProvenanceVerified", "predictionChronologyVerified"):
            self.assertIs(report[field], False)

    def test_cli_canonical_manifest_exclusive_output_and_receipt_last(self):
        query = self.make_query()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = self.write_manifest(directory, (query,))
            before = {path.name: path.read_bytes() for path in directory.iterdir()}
            output = directory / "report"
            write = evaluation._write
            published = []
            def recording_write(path, payload):
                if path.name == "evaluation-receipt.json":
                    self.assertTrue((output / "paired-evaluation.json").is_file())
                published.append(path.name)
                return write(path, payload)
            with mock.patch.object(evaluation, "_write", side_effect=recording_write), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(evaluation.main(["--manifest", str(manifest), "--output-dir", str(output)]), 0)
            self.assertEqual(published, ["paired-evaluation.json", "evaluation-receipt.json"])
            self.assertEqual({path.name for path in output.iterdir()}, set(published))
            report = (output / "paired-evaluation.json").read_bytes()
            receipt_bytes = (output / "evaluation-receipt.json").read_bytes()
            self.assertEqual(report, evaluation.evaluate_batch((query,)))
            self.assertEqual(receipt_bytes, canonical_json_bytes(decode(receipt_bytes)))
            self.assertEqual(decode(receipt_bytes), {
                "artifactKind": evaluation.ARTIFACT_KIND, "manifestSHA256": digest(manifest.read_bytes()),
                "reportSHA256": digest(report), "trainingEligible": False,
                "version": "blind-ink-evaluation-bundle-v1",
            })
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            self.assertTrue(all(stat.S_IMODE(path.stat().st_mode) == 0o600 for path in output.iterdir()))
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as refused:
                evaluation.main(["--manifest", str(manifest), "--output-dir", str(output)])
            self.assertEqual(refused.exception.code, 2)
            self.assertEqual((output / "paired-evaluation.json").read_bytes(), report)
            self.assertEqual((output / "evaluation-receipt.json").read_bytes(), receipt_bytes)
            self.assertEqual(before, {name: (directory / name).read_bytes() for name in before})

    def test_cli_invalid_or_noncanonical_manifest_produces_no_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = self.write_manifest(directory, (self.make_query(),))
            good = manifest.read_bytes()
            cases = [good + b"\n", b"{}", changed(good, lambda value: value.update({"version": "other"})),
                     changed(good, lambda value: value.update({"queries": []})),
                     changed(good, lambda value: value["queries"][0].update({"prediction": "missing.json"})),
                     changed(good, lambda value: value["queries"][0].update({"ownershipPacket": None})),
                     changed(good, lambda value: value["queries"][0].update({"identityArtifacts": [{}]})),
                     changed(good, lambda value: value["queries"][0]["metadata"].update({"writerIDHash": "0" * 64}))]
            for index, payload in enumerate(cases):
                with self.subTest(case=index):
                    manifest.write_bytes(payload)
                    output = directory / f"refused-{index}"
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as refused:
                        evaluation.main(["--manifest", str(manifest), "--output-dir", str(output)])
                    self.assertEqual(refused.exception.code, 2)
                    self.assertFalse(output.exists())

    def test_cli_interrupted_publication_never_publishes_a_complete_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = self.write_manifest(directory, (self.make_query(),))
            write = evaluation._write
            for failed_name in ("paired-evaluation.json", "evaluation-receipt.json"):
                with self.subTest(interrupted=failed_name):
                    output = directory / failed_name.removesuffix(".json")
                    def interrupted_write(path, payload):
                        if path.name == failed_name:
                            raise OSError("synthetic publication interruption")
                        return write(path, payload)
                    with mock.patch.object(evaluation, "_write", side_effect=interrupted_write), \
                            contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as refused:
                        evaluation.main(["--manifest", str(manifest), "--output-dir", str(output)])
                    self.assertEqual(refused.exception.code, 2)
                    self.assertTrue(output.is_dir())
                    self.assertFalse((output / "evaluation-receipt.json").exists())
                    if failed_name == "evaluation-receipt.json":
                        self.assertEqual((output / "paired-evaluation.json").read_bytes(),
                                         evaluation.evaluate_batch((self.make_query(),)))


if __name__ == "__main__":
    unittest.main()
