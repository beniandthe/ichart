"""Pure synthetic checks for the frozen, observed-development glyph scorer.

No source corpus, checkpoint, encoder, or application is loaded by this suite.
The full-size packet is synthetic; its cardinality is a contract check, not
evidence about handwriting accuracy.
"""

import copy
import hashlib
import inspect
import math
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_dual_view_scoring as scoring


def digest(value):
    return hashlib.sha256(canonical_json_bytes(value)).hexdigest()


class PersonalDualViewScoringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.protocol_bytes = b"frozen synthetic dual-view protocol\n"
        cls.protocol_sha = hashlib.sha256(cls.protocol_bytes).hexdigest()
        cls.required_code_paths = {
            "docs/personal-dual-view-glyph-protocol-2026-09-30.md",
            "recognition_ml/ichart_recognition_ml/contracts.py",
            "recognition_ml/ichart_recognition_ml/errors.py",
            "recognition_ml/ichart_recognition_ml/features.py",
            "recognition_ml/ichart_recognition_ml/schema.py",
            "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
            "recognition_ml/ichart_recognition_ml/research/personal_visual_encoder.py",
            "recognition_ml/ichart_recognition_ml/research/personal_dual_view.py",
            "recognition_ml/tests/test_personal_dual_view.py",
            "recognition_ml/ichart_recognition_ml/research/personal_dual_view_scoring.py",
            "recognition_ml/tests/test_personal_dual_view_scoring.py",
        }
        cls.code = {name: hashlib.sha256(name.encode()).hexdigest() for name in cls.required_code_paths}
        cls.code[scoring.PROTOCOL_PATH] = cls.protocol_sha
        cls.weight_bytes = {arm: f"synthetic non-checkpoint {arm}".encode() for arm in scoring.ARMS}
        cls.weights = {arm: hashlib.sha256(value).hexdigest() for arm, value in cls.weight_bytes.items()}
        cls.vocabulary = [chr(index) for index in range(32, 129)]
        training_hashes = [{key: "a" * 64 for key in (
            "rasterSHA256", "trajectorySHA256", "normalizedTrajectorySHA256"
        )} for _ in range(6208)]
        cls.fit = {
            "version": "personal-dual-view-fit-v1", "scope": scoring.SCOPE,
            "sourceSHA256": "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61",
            "protocolSHA256": cls.protocol_sha, "codeSHA256": cls.code,
            "arms": ["rasterOnly", "trajectoryOnly", "dual"],
            "trainingSamples": 6208, "developmentSamples": 1552, "reservedSamples": 3880,
            "trainingWriters": [f"trn_toy_{index:02}" for index in range(32)],
            "developmentWriters": [f"trn_toy_{index:02}" for index in range(32, 40)],
            "reservedWriters": [f"tst_toy_{index:02}" for index in range(20)],
            "vocabulary": cls.vocabulary, "vocabularySHA256": digest(cls.vocabulary),
            "runtime": {"python": "toy", "platform": "toy", "torch": "toy", "numpy": "toy",
                        "cpuThreads": 4, "deterministicAlgorithms": True},
            "featureContract": {
                "augmentation": "none", "featureSchemaVersion": "chord-ink-features-v1",
                "geometryChannelIndexes": [0, 1, 2, 3, 4, 7, 8, 9],
                "rasterEncoding": "uint8-gray", "rasterHashEncoding": "sha256-exact-uint8-plane",
                "rasterNormalization": "float32-divide-255", "rasterShape": [1, 96, 256],
                "sourceGroups": "single-source-glyph-all-original-stroke-indexes",
                "timingChannelIndexesExcluded": [5, 6], "trajectoryEncoding": "float32-le",
                "trajectoryHashEncoding": "sha256-exact-full-10-channel-float32-le",
                "trajectoryShape": [1, 256, 10],
            },
            "modelContract": {
                "architectureVersion": "personal-dual-view-glyph-v1",
                "embedding": "l2-normalized-fused-raw-128", "embeddingSize": 128,
                "fusion": "concatenate-raw-128-plus-128-linear-256-to-128",
                "inactiveBranchMask": "zeros-after-projection", "labelCount": 97,
                "rasterBranch": "avgpool2;conv-bn-relu-16-32-64-64;linear1536-to-128",
                "trajectoryBranch": "conv1d-8-32-k7;32-64-k5s2;64-64-k3s2;pool8;linear512-to-128",
            },
            "optimization": {
                "augmentation": "none", "batchSize": 128, "cpuThreads": 4,
                "deterministicAlgorithms": True, "epochs": 30, "loss": "cross-entropy",
                "optimizer": {"learningRate": 0.001, "name": "AdamW", "weightDecay": 0.0001},
                "permutationGeneratorSeedPerArm": 29,
                "scheduler": {"name": "CosineAnnealingLR", "tMax": 30}, "seed": 29,
            },
            "initialState": {"armSHA256": {arm: "b" * 64 for arm in scoring.ARMS},
                             "sha256": "b" * 64, "stateKeysSHA256": "c" * 64,
                             "parameterCount": 1, "stateKeyCount": 1},
            "weightFiles": {arm: f"weights/{arm}.pt" for arm in scoring.ARMS},
            "weightsSHA256": cls.weights, "trainingInputHashes": training_hashes,
            "trainingInputHashesSHA256": digest(training_hashes),
            "trainingHistory": {arm: [{"epoch": epoch, "trainCorrect": 0, "trainLoss": 1.0}
                                      for epoch in range(1, 31)] for arm in scoring.ARMS},
            "selection": "final-epoch-only",
            "roleGuards": {key: False for key in (
                "developmentFeaturesConstructedDuringFit", "developmentInferredDuringFit",
                "privateInkUsed", "productionEligible", "reservedWritersEncoded",
                "reservedWritersInferred", "reservedWritersTransformed",
            )},
        }
        cls.fit_bytes = canonical_json_bytes(cls.fit)
        cls.packet = {
            "version": "personal-dual-view-predictions-v1", "scope": scoring.SCOPE,
            "sourceSHA256": cls.fit["sourceSHA256"], "protocolSHA256": cls.protocol_sha,
            "codeSHA256": cls.code, "arms": ["rasterOnly", "trajectoryOnly", "dual"],
            "rowCount": 1552, "runtime": cls.fit["runtime"],
            "featureContract": cls.fit["featureContract"],
            "fitReceiptSHA256": hashlib.sha256(cls.fit_bytes).hexdigest(),
            "weightsSHA256": cls.weights, "vocabularySHA256": cls.fit["vocabularySHA256"],
            "rows": [{"opaqueID": f"{index:064x}", "rasterSHA256": "d" * 64,
                      "trajectorySHA256": "e" * 64, "sourceGroups": [[0, 1]],
                      "outputs": {arm: {"embedding": [1.0] + [0.0] * 127,
                                        "rawLogits": [1.0] + [0.0] * 96}
                                  for arm in scoring.ARMS}} for index in range(1552)],
        }
        cls.packet_bytes = canonical_json_bytes(cls.packet)

    def test_argmax_uses_first_bound_vocabulary_index_and_rejects_bad_logits(self):
        vocabulary = ("B", "A", "C")
        self.assertEqual(scoring.argmax_label([4.0, 4.0, -1.0], vocabulary), "B")
        self.assertEqual(scoring.argmax_label([-3.0, -2.0, -4.0], vocabulary), "A")
        for logits in ([], [0.0], [0.0, math.nan, 1.0], [0.0, math.inf, 1.0]):
            with self.subTest(logits=logits), self.assertRaises(ValueError):
                scoring.argmax_label(logits, vocabulary)

    def test_exact_mcnemar_retains_integer_arithmetic_and_is_descriptive(self):
        for gains, harms, numerator, denominator in (
            (0, 0, 1, 1),
            (4, 1, 3, 8),
            (1, 4, 3, 8),
            (8, 0, 1, 128),
            (0, 64, 1, 2**63),
        ):
            with self.subTest(gains=gains, harms=harms):
                result = scoring.exact_mcnemar(gains, harms)
                self.assertEqual(result["numerator"], str(numerator))
                self.assertEqual(result["denominator"], str(denominator))
                self.assertEqual(result["pValue"], numerator / denominator)
                self.assertEqual(result["discordantRows"], gains + harms)
                self.assertIn("descriptive", result["scope"])
        for gains, harms in ((-1, 0), (0, -1), (True, 0), (1.5, 0)):
            with self.subTest(gains=gains, harms=harms), self.assertRaises(ValueError):
                scoring.exact_mcnemar(gains, harms)

    def test_writer_sign_flip_enumerates_all_eight_units_including_zero_deltas(self):
        for deltas, tails, absolute_delta in (
            ([1] * 8, 2, 8),
            ([1] * 6 + [0] * 2, 8, 6),
            ([1, -1] * 4, 256, 0),
            ([5] * 6 + [-2] * 2, 8, 26),
        ):
            with self.subTest(deltas=deltas):
                result = scoring.writer_sign_flip(dict(zip(self.writers(), deltas)))
                self.assertEqual(result["writerUnits"], 8)
                self.assertEqual(result["totalAssignments"], 256)
                self.assertEqual(result["tailAssignments"], tails)
                self.assertEqual(result["absoluteDelta"], absolute_delta)
                self.assertEqual(result["pValue"], tails / 256)
        for values in (
            {f"writer-{index}": 1 for index in range(7)},
            {f"writer-{index}": 1 for index in range(9)},
            dict(zip(self.writers(), [1] * 7 + [True])),
            dict(zip(self.writers(), [1] * 7 + [1.5])),
        ):
            with self.subTest(values=values), self.assertRaises(ValueError):
                scoring.writer_sign_flip(values)

    def test_paired_denominators_and_case_only_confusion_do_not_relabel_misses(self):
        rows = []
        for writer in self.writers():
            for intended, reference, candidate in (
                ("A", "A", "A"), ("A", "B", "A"),
                ("a", "a", "A"), ("B", "A", "C"),
            ):
                rows.append({"writer": writer, "intended": intended,
                             "predictions": {"rasterOnly": reference, "dual": candidate}})
        before = digest(rows)
        paired = scoring.paired_summary(rows, "rasterOnly", "dual")
        self.assertEqual({key: paired[key] for key in (
            "count", "referenceCorrect", "candidateCorrect", "bothCorrect", "neitherCorrect",
            "gains", "harms", "net",
        )}, {"count": 32, "referenceCorrect": 16, "candidateCorrect": 16,
             "bothCorrect": 8, "neitherCorrect": 8, "gains": 8, "harms": 8, "net": 0})
        self.assertEqual(set(paired["perWriter"]), set(self.writers()))
        self.assertEqual({row["count"] for row in paired["perWriter"].values()}, {4})
        self.assertEqual(sum(row["count"] for row in paired["perLabel"].values()), 32)
        self.assertEqual(paired["rowMcNemarDescriptive"]["discordantRows"], 16)
        identity = scoring.identity_summary(rows, "dual")
        self.assertEqual((identity["count"], identity["correct"], identity["asciiCaseOnlyMisses"]), (32, 16, 8))
        self.assertEqual(identity["confusions"], [
            {"intended": "A", "predicted": "A", "count": 16},
            {"intended": "B", "predicted": "C", "count": 8},
            {"intended": "a", "predicted": "A", "count": 8},
        ])
        self.assertEqual(digest(rows), before)

    def test_advancement_requires_writer_significance_and_each_frozen_guard(self):
        passing = scoring.advancement_gate(self.rows_for_deltas([5] * 6 + [-2] * 2))
        self.assertTrue(passing["nextBlindDevelopmentGateEligible"])
        self.assertEqual(passing["writerSignFlip"]["tailAssignments"], 8)
        self.assertEqual(passing["paired"]["count"], 1552)
        self.assertFalse(passing["productionEligible"])
        for deltas, failed_rule in (
            ([10] * 7 + [-3], "worstWriterLossAtMostTwo"),
            ([50] + [0] * 7, "writerSignFlipPBelow005"),
            ([-1] * 8, "gainsExceedHarms"),
            ([20] * 5 + [-1] * 3, "atLeastSixWritersNonWorse"),
        ):
            with self.subTest(deltas=deltas):
                gate = scoring.advancement_gate(self.rows_for_deltas(deltas))
                self.assertFalse(gate["nextBlindDevelopmentGateEligible"])
                self.assertFalse(gate["rules"][failed_rule])
        rows = self.rows_for_deltas([1] * 8)
        shifted = copy.deepcopy(rows)
        shifted[0]["writer"] = self.writers()[1]
        for invalid in (rows[:-1], shifted):
            with self.subTest(count=len(invalid)), self.assertRaises(ValueError):
                scoring.advancement_gate(invalid)

    def test_duplicated_correlated_rows_do_not_create_additional_writer_units(self):
        rows = self.rows_for_deltas([50] + [0] * 7)
        original = scoring.paired_summary(rows, "rasterOnly", "dual")
        duplicated = scoring.paired_summary(rows * 3, "rasterOnly", "dual")
        self.assertLess(original["rowMcNemarDescriptive"]["pValue"], 0.05)
        self.assertEqual(duplicated["count"], original["count"] * 3)
        for paired in (original, duplicated):
            clustered = scoring.writer_sign_flip({w: row["net"] for w, row in paired["perWriter"].items()})
            self.assertEqual((clustered["writerUnits"], clustered["totalAssignments"],
                              clustered["tailAssignments"], clustered["pValue"]), (8, 256, 256, 1.0))
        with self.assertRaises(ValueError):
            scoring.advancement_gate(rows * 3)

    def test_personal_prediction_uses_only_explicit_support_and_direct_fixed_ridge(self):
        import numpy as np
        from ichart_recognition_ml.research import personal_visual_encoder as personal

        self.assertEqual(tuple(inspect.signature(scoring.predict_personal).parameters),
                         ("support_features", "support_labels", "query_features"))
        support = np.eye(97, 128, dtype=np.float64)
        labels = tuple(self.vocabulary)
        queries = support[::-1].copy()
        before = (support.tobytes(), queries.tobytes(), labels)
        with patch.object(personal, "fit_personal", wraps=personal.fit_personal) as fit:
            predicted = scoring.predict_personal(support, labels, queries)
        self.assertEqual(predicted, list(reversed(labels)))
        self.assertEqual(fit.call_count, 1)
        self.assertEqual(fit.call_args.kwargs, {"regularization": 0.1})
        # Contradictory expected labels exist only here, after the first frozen
        # predictions; neither can be passed to the inference API.
        expected_labels = list(labels)
        self.assertNotEqual(expected_labels, predicted)
        expected_labels.reverse()
        self.assertEqual(expected_labels, predicted)
        self.assertEqual(scoring.predict_personal(support, labels, queries), predicted)
        self.assertEqual((support.tobytes(), queries.tobytes(), labels), before)

    def test_personal_diagnostic_retains_copies_and_has_consistent_prediction_correctness_maps(self):
        rows = []
        for writer in self.writers():
            for session in (1, 2):
                for label in self.vocabulary:
                    predictions = {arm: self.vocabulary[0] for arm in scoring.ARMS}
                    predictions["historicalCoreML"] = self.vocabulary[0]
                    rows.append({
                        "opaqueID": f"{len(rows):064x}", "writer": writer, "session": session,
                        "intended": label, "predictions": predictions,
                        "correct": {arm: predicted == label for arm, predicted in predictions.items()},
                        "inputHashes": {key: "d" * 64 for key in (
                            "rasterSHA256", "trajectorySHA256", "normalizedTrajectorySHA256"
                        )},
                        "noveltyExclusions": ["training:rasterSHA256"],
                    })
        before = digest(rows)
        packet_rows = {row["opaqueID"]: row for row in self.packet["rows"]}
        with patch.object(scoring, "predict_personal", side_effect=lambda _features, _labels, _queries:
                          list(self.vocabulary)) as predict:
            diagnostic = scoring._personalize(rows, packet_rows, self.vocabulary)
        self.assertEqual(predict.call_count, 3 * 8)
        for call in predict.call_args_list:
            support_features, labels, query_features = call.args
            self.assertEqual((len(support_features), len(query_features)), (97, 97))
            self.assertEqual(labels, self.vocabulary)
        self.assertEqual(set(diagnostic), {"rasterOnly", "trajectoryOnly", "dual"})
        for arm, report in diagnostic.items():
            with self.subTest(arm=arm):
                self.assertEqual((len(report["rows"]), report["rawPaired"]["count"],
                                  report["noveltyCount"], report["noveltyPaired"]["count"]),
                                 (776, 776, 0, 0))
                self.assertEqual(report["personal"]["correct"], 776)
                self.assertEqual({row["count"] for row in report["rawPaired"]["perWriter"].values()}, {97})
                for row in report["rows"]:
                    self.assertEqual(set(row["predictions"]), {"generic", "personal"})
                    self.assertEqual(row["correct"], {name: prediction == row["intended"]
                                                      for name, prediction in row["predictions"].items()})
                    self.assertIn("training:rasterSHA256", row["noveltyExclusions"])
                    self.assertIn("support:rasterSHA256", row["noveltyExclusions"])
        self.assertEqual(digest(rows), before)

    def test_complete_bound_packet_is_pure_and_invalid_packet_precedes_source_join(self):
        self.assertEqual(set(scoring.CODE_PATHS), self.required_code_paths)
        before = (digest(self.fit), digest(self.packet), digest(self.code), digest(self.weights))
        with patch.dict(sys.modules, {"torch": None,
                                    "ichart_recognition_ml.research.personal_dual_view": None}), \
                patch.object(scoring, "load_official_source") as source:
            validated = self.validate()
            source.assert_not_called()
        self.assertEqual(len(validated["rows"]), 1552)
        self.assertEqual(set(validated["rows"][0]["outputs"]), {"rasterOnly", "trajectoryOnly", "dual"})
        self.assertEqual(before, (digest(self.fit), digest(self.packet), digest(self.code), digest(self.weights)))

        invalid = {**self.packet, "fitReceiptSHA256": "f" * 64}
        contents = {
            Path("/toy/predictions.json"): canonical_json_bytes(invalid),
            Path("/toy/fit/fit-receipt.json"): self.fit_bytes,
            Path("/toy/protocol.md"): self.protocol_bytes,
            Path("/toy/fit/frozen-protocol.md"): self.protocol_bytes,
            **{Path(f"/toy/fit/weights/{arm}.pt"): value for arm, value in self.weight_bytes.items()},
        }
        with patch.object(scoring, "_file", side_effect=lambda path: path), \
                patch.object(scoring, "code_identity", return_value=self.code), \
                patch.object(Path, "read_bytes", autospec=True, side_effect=lambda path: contents[path]), \
                patch.object(scoring, "load_official_source") as source, \
                patch.object(scoring, "rasterize") as raster, \
                patch.object(scoring, "encode_trajectory") as trajectory:
            with self.assertRaises(ValueError):
                scoring.score(Path("/toy/predictions.json"), Path("/toy/fit"),
                              Path("/never/source"), Path("/never/baseline"),
                              Path("/toy/protocol.md"), Path("/never/output"))
            source.assert_not_called()
            raster.assert_not_called()
            trajectory.assert_not_called()

    def test_changed_packet_bindings_and_noncanonical_receipt_bytes_are_rejected(self):
        for key, value in (
            ("version", "different"), ("scope", "different"), ("sourceSHA256", "f" * 64),
            ("protocolSHA256", "f" * 64), ("fitReceiptSHA256", "f" * 64),
            ("vocabularySHA256", "f" * 64), ("rowCount", 1551),
            ("arms", ["dual", "trajectoryOnly", "rasterOnly"]),
            ("codeSHA256", {**self.code,
                            "recognition_ml/ichart_recognition_ml/research/personal_dual_view_scoring.py": "f" * 64}),
            ("weightsSHA256", {**self.weights, "dual": "f" * 64}),
            ("featureContract", {**self.fit["featureContract"], "timingChannelIndexesExcluded": []}),
            ("runtime", {**self.fit["runtime"], "cpuThreads": 2}),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(packet={**self.packet, key: value})
        for fit_bytes in (self.fit_bytes + b"\n", b"{}"):
            with self.subTest(fit_bytes=fit_bytes[:20]), self.assertRaises(ValueError):
                self.validate(fit_bytes=fit_bytes)
        with self.assertRaises(ValueError):
            self.validate(payload=self.packet_bytes + b"\n")
        with self.assertRaises(ValueError):
            self.validate(payload=self.packet_bytes.replace(b'{"arms":', b'{"arms":[],"arms":', 1))
        for key, value in (("roleGuards", {**self.fit["roleGuards"], "productionEligible": True}),
                           ("selection", "best-development-checkpoint"),
                           ("developmentWriters", self.fit["trainingWriters"][:8]),
                           ("vocabulary", self.vocabulary[:-1] + [self.vocabulary[0]])):
            fit = {**self.fit, key: value}
            with self.subTest(fit_key=key), self.assertRaises(ValueError):
                self.validate(fit=fit, fit_bytes=canonical_json_bytes(fit))

    def test_missing_duplicate_unsorted_and_label_bearing_prediction_rows_are_rejected(self):
        for defect in ("missing", "duplicate", "unsorted", "unknownArm", "sourceID", "writer",
                       "label", "intended", "correct", "unknownPacketField", "missingPacketField"):
            packet = copy.deepcopy(self.packet)
            if defect == "missing":
                packet["rows"].pop()
            elif defect == "duplicate":
                packet["rows"][1]["opaqueID"] = packet["rows"][0]["opaqueID"]
            elif defect == "unsorted":
                packet["rows"][0], packet["rows"][1] = packet["rows"][1], packet["rows"][0]
            elif defect == "unknownArm":
                packet["rows"][0]["outputs"]["personal"] = packet["rows"][0]["outputs"]["dual"]
            elif defect == "unknownPacketField":
                packet["writer"] = "label-bearing leak"
            elif defect == "missingPacketField":
                del packet["rowCount"]
            else:
                packet["rows"][0][defect] = "label-bearing leak"
            with self.subTest(defect=defect), self.assertRaises(ValueError):
                self.validate(packet=packet)

    def test_exact_output_shapes_finite_numbers_and_complete_source_index_owner_are_required(self):
        cases = (
            ("embedding", [0.0] * 127), ("rawLogits", [0.0] * 96),
            ("embedding", [0.0] * 128), ("embedding", [2.0] + [0.0] * 127),
            ("embedding", [True] + [0.0] * 127), ("rawLogits", ["0"] + [0.0] * 96),
        )
        for field, value in cases:
            packet = copy.deepcopy(self.packet)
            packet["rows"][0]["outputs"]["dual"][field] = value
            with self.subTest(field=field, length=len(value)), self.assertRaises(ValueError):
                self.validate(packet=packet)
        # JSON parsers may accept nonfinite extension tokens; validation must
        # reject them rather than depending on our canonical serializer.
        for token in (b"NaN", b"Infinity", b"-Infinity"):
            payload = self.packet_bytes.replace(b'"rawLogits":[1.0', b'"rawLogits":[' + token, 1)
            with self.subTest(token=token), self.assertRaises(ValueError):
                self.validate(payload=payload)
        for groups in ([], [[]], [[0], [1]], [[1]], [[0, 0]], [[1, 0]], [[False]], [list(range(65))]):
            packet = copy.deepcopy(self.packet)
            packet["rows"][0]["sourceGroups"] = groups
            with self.subTest(groups=groups), self.assertRaises(ValueError):
                self.validate(packet=packet)

    def validate(self, *, packet=None, payload=None, fit=None, fit_bytes=None):
        if payload is None:
            payload = self.packet_bytes if packet is None else canonical_json_bytes(packet)
        return scoring.validate_prediction_packet(payload, self.fit if fit is None else fit,
                                                  self.fit_bytes if fit_bytes is None else fit_bytes,
                                                  self.code, self.protocol_sha, self.weights)

    def rows_for_deltas(self, deltas):
        rows = []
        for writer, delta in zip(self.writers(), deltas):
            for index in range(194):
                reference, candidate = "B", "B"
                if index < abs(delta):
                    reference, candidate = ("B", "A") if delta >= 0 else ("A", "B")
                rows.append({"writer": writer, "intended": "A", "predictions": {
                    "rasterOnly": reference, "trajectoryOnly": "B", "dual": candidate,
                }})
        return rows

    @staticmethod
    def writers():
        return tuple(f"writer-{index}" for index in range(8))


if __name__ == "__main__":
    unittest.main()
