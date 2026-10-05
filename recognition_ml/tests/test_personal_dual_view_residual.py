"""Synthetic contract tests for the frozen dual-view residual diagnostic."""

import copy
import hashlib
import inspect
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_dual_view_residual as diagnostic


def digest(value):
    return hashlib.sha256(canonical_json_bytes(value)).hexdigest()


class PersonalDualViewResidualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        extras = [chr(0x400 + index) for index in range(81)]
        cls.vocabulary = sorted(set(diagnostic.SPARSE_LABELS) | set(extras))
        assert len(cls.vocabulary) == 97
        cls.vocabulary_sha = digest(cls.vocabulary)
        cls.writers = [f"trn_toy_{index:02}" for index in range(8)]
        cls.code = {name: hashlib.sha256(name.encode()).hexdigest() for name in diagnostic.CODE_PATHS}
        cls.protocol_sha = cls.code[diagnostic.PROTOCOL_PATH]
        cls.parents = {
            "dualWeightsSHA256": diagnostic.DUAL_WEIGHT_SHA256,
            "fitReceiptSHA256": diagnostic.FIT_SHA256,
            "parentCodeSHA256": {name: cls.code[name] for name in diagnostic.parent.CODE_PATHS},
            "parentPredictionSHA256": diagnostic.PARENT_PREDICTION_SHA256,
            "parentProtocolSHA256": cls.code[diagnostic.parent.PROTOCOL_PATH],
            "parentScoreSHA256": diagnostic.PARENT_SCORE_SHA256,
        }
        support, queries = [], []
        counter = 0
        for writer in cls.writers:
            for label in cls.vocabulary:
                support.append(cls.feature_row(counter, writer, 1, label))
                counter += 1
        for writer in cls.writers:
            for _ in cls.vocabulary:
                queries.append(cls.feature_row(counter, writer, 2))
                counter += 1
        cls.plan = {
            "version": diagnostic.PLAN_VERSION, "scope": diagnostic.SCOPE,
            "sourceSHA256": diagnostic.SOURCE_SHA256, "protocolSHA256": cls.protocol_sha,
            "codeSHA256": cls.code, "runtime": diagnostic._runtime(),
            "algorithm": diagnostic.ALGORITHM, "parentBindings": cls.parents,
            "regimes": list(diagnostic.REGIMES), "developmentWriters": cls.writers,
            "vocabulary": cls.vocabulary, "vocabularySHA256": cls.vocabulary_sha,
            "sparseSupportLabels": list(diagnostic.SPARSE_LABELS), "supportCount": 776,
            "queryCount": 776, "supportRows": support, "queryRows": queries,
            "roleGuards": {"privateInkUsed": False, "productionEligible": False,
                           "reservedWritersUsed": False, "sharedModelInferencePerformed": False},
        }

    @staticmethod
    def feature_row(index, writer, session, label=None):
        row = {
            "opaqueID": f"{index:064x}", "writer": writer, "session": session,
            "inputHashes": {"normalizedTrajectorySHA256": "a" * 64,
                            "rasterSHA256": "b" * 64, "trajectorySHA256": "c" * 64},
            "embedding": [1.0] + [0.0] * 127, "rawLogits": [0.0] * 97,
        }
        if label is not None:
            row["label"] = label
        return row

    def validate_plan(self, plan=None):
        plan = self.plan if plan is None else plan
        with patch.object(diagnostic, "VOCABULARY_SHA256", self.vocabulary_sha), \
                patch.object(diagnostic, "sparse_labels", return_value=diagnostic.SPARSE_LABELS):
            return diagnostic.validate_plan(canonical_json_bytes(plan), expected_code=self.code,
                                            expected_protocol_sha=self.protocol_sha)

    def test_fixed_contract_and_dependencies_are_explicit(self):
        self.assertEqual(diagnostic.REGIMES, ("sparse16", "full97"))
        self.assertEqual(diagnostic.ALGORITHM["regularization"], 0.1)
        self.assertEqual(diagnostic.ALGORITHM["correctionAlpha"], 1.0)
        self.assertEqual(len(diagnostic.SPARSE_LABELS), 16)
        self.assertEqual(set(diagnostic.parent.CODE_PATHS).issubset(diagnostic.CODE_PATHS), True)
        for path in (diagnostic.PROTOCOL_PATH, diagnostic.MODULE_PATH, diagnostic.TEST_PATH,
                     diagnostic.RESIDUAL_PATH, diagnostic.SWIFT_RESIDUAL_PATH, diagnostic.SELECTOR_PATH):
            self.assertIn(path, diagnostic.CODE_PATHS)

    def test_predictor_matches_fixed_normal_equations_without_query_answers(self):
        self.assertEqual(tuple(inspect.signature(diagnostic.predict_residual).parameters),
                         ("support_features", "support_logits", "support_labels",
                          "query_features", "query_logits", "vocabulary"))
        support = np.eye(3, 128, dtype=np.float64)
        queries = np.stack((support[0], support[1] + support[2]))
        queries[1] /= np.linalg.norm(queries[1])
        support_logits = np.zeros((3, 97), dtype=np.float64)
        query_logits = np.zeros((2, 97), dtype=np.float64)
        labels = tuple(self.vocabulary[:3])
        before = tuple(array.tobytes() for array in (support, queries, support_logits, query_logits))
        output = diagnostic.predict_residual(support, support_logits, labels, queries, query_logits, self.vocabulary)

        base = np.full((3, 97), 1 / 97, dtype=np.float64)
        target = np.array([[float(label == candidate) for candidate in self.vocabulary] for label in labels])
        coefficients = np.linalg.solve(support @ support.T + 0.1 * np.eye(3), target - base)
        # The synthetic support is the first three basis vectors, so spell out
        # the independent reference rather than exercising the same matrix path.
        expected = np.stack((base[0] + coefficients[0],
                             base[0] + (coefficients[1] + coefficients[2]) / np.sqrt(2)))
        for index, row in enumerate(output):
            scores = {item["label"]: item["score"] for item in row["residualRanking"]}
            np.testing.assert_allclose([scores[label] for label in self.vocabulary], expected[index], rtol=0, atol=1e-12)
            self.assertEqual(len(row["baselineRanking"]), 97)
            self.assertEqual(len(row["residualRanking"]), 97)
        self.assertEqual(before, tuple(array.tobytes() for array in (support, queries, support_logits, query_logits)))

    def test_empty_profile_is_exact_all_competitor_baseline(self):
        query = np.zeros((1, 128), dtype=np.float64); query[0, 5] = 1
        logits = np.arange(97, dtype=np.float64)[None, :] / 10
        result = diagnostic.predict_residual(np.empty((0, 128)), np.empty((0, 97)), (),
                                             query, logits, self.vocabulary)[0]
        self.assertEqual(result["baselineRanking"], result["residualRanking"])
        self.assertEqual(len({row["label"] for row in result["residualRanking"]}), 97)
        self.assertEqual(result["residualRanking"][0]["label"], self.vocabulary[-1])
        reversed_vocabulary = list(reversed(self.vocabulary))
        tie = diagnostic.predict_residual(np.empty((0, 128)), np.empty((0, 97)), (), query,
                                          np.zeros((1, 97)), reversed_vocabulary)[0]
        self.assertEqual(tie["baselineRanking"][0]["label"], reversed_vocabulary[0])
        self.assertEqual(tie["residualRanking"][0]["label"], min(reversed_vocabulary))
        almost_tied_logits = np.zeros((1, 97))
        almost_tied_logits[0, 1] = np.nextafter(0.0, 1.0)
        almost_tied = diagnostic.predict_residual(
            np.empty((0, 128)), np.empty((0, 97)), (), query,
            almost_tied_logits, reversed_vocabulary,
        )[0]
        self.assertEqual(almost_tied["baselineRanking"][0]["score"],
                         almost_tied["baselineRanking"][1]["score"])
        self.assertEqual(almost_tied["baselineRanking"][0]["label"], reversed_vocabulary[1])

    def test_projection_is_invariant_to_query_truth_reference_and_novelty(self):
        packet, metadata = [], []
        for row in self.plan["supportRows"] + self.plan["queryRows"]:
            packet.append({"opaqueID": row["opaqueID"], "rasterSHA256": row["inputHashes"]["rasterSHA256"],
                           "trajectorySHA256": row["inputHashes"]["trajectorySHA256"],
                           "outputs": {"dual": {"embedding": row["embedding"], "rawLogits": row["rawLogits"]}}})
            metadata.append({"opaqueID": row["opaqueID"], "writer": row["writer"], "session": row["session"],
                             "inputHashes": row["inputHashes"], "intended": row.get("label", "query-answer"),
                             "correct": {"dual": False}, "predictions": {"dual": "wrong"},
                             "noveltyExclusions": ["answer-shaped"], "sourceID": "label-bearing"})
        original = diagnostic.project_plan_rows(packet, metadata)
        changed = copy.deepcopy(metadata)
        for row in changed:
            if row["session"] == 2:
                row.update(intended="contradiction", correct={"dual": True}, predictions={"dual": "different"},
                           noveltyExclusions=[], sourceID="different")
        self.assertEqual(diagnostic.project_plan_rows(packet, changed), original)
        self.assertNotEqual(digest(metadata), digest(changed))
        self.assertTrue(all(set(row) == diagnostic.QUERY_FIELDS for row in original[1]))

    def test_plan_rejects_unknown_missing_duplicate_role_and_nonfinite_fields(self):
        self.assertEqual(len(self.validate_plan()["queryRows"]), 776)
        defects = []
        unknown = copy.deepcopy(self.plan); unknown["queryRows"][0]["intended"] = "A"; defects.append(unknown)
        missing = copy.deepcopy(self.plan); missing["queryRows"].pop(); defects.append(missing)
        duplicate = copy.deepcopy(self.plan); duplicate["queryRows"][1]["opaqueID"] = duplicate["queryRows"][0]["opaqueID"]; defects.append(duplicate)
        wrong_role = copy.deepcopy(self.plan); wrong_role["queryRows"][0]["writer"] = "tst_reserved"; defects.append(wrong_role)
        nonfinite = copy.deepcopy(self.plan); nonfinite["queryRows"][0]["rawLogits"][0] = float("nan"); defects.append(nonfinite)
        altered = copy.deepcopy(self.plan); altered["parentBindings"]["fitReceiptSHA256"] = "f" * 64; defects.append(altered)
        for plan in defects:
            with self.subTest(defect=len(defects)), self.assertRaises(ValueError):
                self.validate_plan(plan)

    def test_complete_rankings_and_receipt_bindings_fail_closed(self):
        scores = np.linspace(-1, 1, 97)
        ranking = diagnostic._baseline_rank(self.vocabulary, scores, scores)
        diagnostic._validate_ranking(ranking, self.vocabulary, normalized=False)
        wrong_label = copy.deepcopy(ranking)
        wrong_label[0]["label"] = "not-in-vocabulary"
        for bad in (ranking[:-1], ranking + [ranking[0]],
                    [{**ranking[0], "score": float("inf")}] + ranking[1:], wrong_label):
            with self.assertRaises(ValueError):
                diagnostic._validate_ranking(bad, self.vocabulary, normalized=False)
        plan_bytes, packet_bytes = canonical_json_bytes(self.plan), b"synthetic prediction bytes"
        receipt = {
            "artifactKind": "personal-dual-view-residual-prediction-receipt", "codeSHA256": self.code,
            "passed": True, "planSHA256": hashlib.sha256(plan_bytes).hexdigest(),
            "predictionByteCount": len(packet_bytes), "predictionSHA256": hashlib.sha256(packet_bytes).hexdigest(),
            "rowCount": 1552, "supportSetCount": 16, "version": diagnostic.VERSION,
        }
        diagnostic._validate_receipt(canonical_json_bytes(receipt), packet_bytes, plan_bytes, self.code)
        receipt["predictionSHA256"] = "f" * 64
        with self.assertRaises(ValueError):
            diagnostic._validate_receipt(canonical_json_bytes(receipt), packet_bytes, plan_bytes, self.code)

    def test_full_prediction_packet_recomputes_and_rejects_tampering(self):
        plan = self.validate_plan()
        support_by_writer = {
            writer: sorted((row for row in plan["supportRows"] if row["writer"] == writer),
                           key=lambda row: row["label"])
            for writer in plan["developmentWriters"]
        }
        rows, support_sets = [], []
        for regime in diagnostic.REGIMES:
            for writer in plan["developmentWriters"]:
                support = support_by_writer[writer]
                if regime == "sparse16":
                    support = [row for row in support if row["label"] in diagnostic.SPARSE_LABELS]
                queries = sorted((row for row in plan["queryRows"] if row["writer"] == writer),
                                 key=lambda row: row["opaqueID"])
                support_sets.append({"regime": regime,
                                     "supportOpaqueIDs": [row["opaqueID"] for row in support],
                                     "writer": writer})
                predicted = diagnostic.predict_residual(
                    [row["embedding"] for row in support], [row["rawLogits"] for row in support],
                    [row["label"] for row in support], [row["embedding"] for row in queries],
                    [row["rawLogits"] for row in queries], plan["vocabulary"],
                )
                rows.extend({"opaqueID": query["opaqueID"], "writer": writer,
                             "regime": regime, **result}
                            for query, result in zip(queries, predicted))
        rows.sort(key=lambda row: (row["regime"], row["opaqueID"]))
        plan_bytes = canonical_json_bytes(plan)
        packet = {
            "version": diagnostic.PREDICTION_VERSION, "scope": diagnostic.SCOPE,
            "algorithm": diagnostic.ALGORITHM, "codeSHA256": self.code,
            "protocolSHA256": self.protocol_sha, "runtime": diagnostic._runtime(),
            "planSHA256": hashlib.sha256(plan_bytes).hexdigest(),
            "parentBindings": self.parents, "regimes": list(diagnostic.REGIMES),
            "rowCount": 1552, "rows": rows, "supportSets": support_sets,
            "vocabulary": self.vocabulary, "vocabularySHA256": self.vocabulary_sha,
        }

        def validate(candidate):
            with patch.object(diagnostic, "VOCABULARY_SHA256", self.vocabulary_sha):
                return diagnostic.validate_prediction(canonical_json_bytes(candidate), plan, plan_bytes,
                                                      expected_code=self.code)

        self.assertEqual(len(validate(packet)["rows"]), 1552)
        defects = []
        altered = copy.deepcopy(packet); altered["rows"][0]["residualRanking"][0]["score"] += 1; defects.append(altered)
        duplicate = copy.deepcopy(packet); duplicate["rows"][1] = duplicate["rows"][0]; defects.append(duplicate)
        missing = copy.deepcopy(packet); missing["rows"].pop(); defects.append(missing)
        query_truth = copy.deepcopy(packet); query_truth["rows"][0]["intended"] = "answer"; defects.append(query_truth)
        for index, candidate in enumerate(defects):
            with self.subTest(defect=index), self.assertRaises(ValueError):
                validate(candidate)

    def test_primary_denominators_retain_exclusions_and_sparse_label_slices(self):
        rows = []
        for writer in self.writers:
            for label in self.vocabulary:
                index = len(rows)
                rows.append({"writer": writer, "intended": label, "opaqueID": f"{index:064x}",
                             "regime": "sparse16", "commonNoveltyExclusions": ["fixed-copy"] if index < 4 else [],
                             "predictions": {"generic": self.vocabulary[0], "residual": label},
                             "correct": {"generic": label == self.vocabulary[0], "residual": True}})
        report = diagnostic._regime_report(rows, direct_reference=False)
        slices = diagnostic._sparse_label_slices(rows)
        self.assertEqual(report["rawPaired"]["count"], 776)
        self.assertEqual((report["commonNovelty"]["count"], report["commonNovelty"]["excluded"]), (772, 4))
        self.assertEqual((slices["taught16"]["count"], slices["untaught81"]["count"]), (128, 648))
        self.assertEqual({value["count"] for value in report["rawPaired"]["perWriter"].values()}, {97})
        self.assertEqual(sum(value["count"] for value in report["rawPaired"]["perLabel"].values()), 776)

    def test_module_has_no_shared_model_inference_or_checkpoint_execution(self):
        source = inspect.getsource(diagnostic)
        for forbidden in ("load_research_model(", "load_state_dict(", "torch.load(", "coremltools"):
            self.assertNotIn(forbidden, source)
        self.assertIn('commands.add_parser("prepare")', source)
        self.assertIn('commands.add_parser("predict")', source)
        self.assertIn('commands.add_parser("score")', source)
        prepare_source = inspect.getsource(diagnostic.prepare)
        score_source = inspect.getsource(diagnostic.score)
        self.assertLess(prepare_source.index("snapshot ="), prepare_source.index("load_official_source"))
        self.assertLess(score_source.index("blind_snapshot ="), score_source.index("validate_prediction"))
        self.assertLess(score_source.index("snapshot ="), score_source.index("load_official_source"))


if __name__ == "__main__":
    unittest.main()
