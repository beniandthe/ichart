"""Finite synthetic binding/count tests, not handwriting-recognition evidence."""

import copy
import hashlib
import inspect
import math
import unittest
from unittest.mock import patch

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_dual_view_scoring as previous
from ichart_recognition_ml.research import personal_synchronized_dual_view_scoring as scoring


def digest(value):
    return hashlib.sha256(canonical_json_bytes(value)).hexdigest()


class SynchronizedScoringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.protocol_sha = "f" * 64
        cls.code = {name: hashlib.sha256(name.encode()).hexdigest() for name in scoring.CODE_PATHS}
        cls.code[scoring.PROTOCOL_PATH] = cls.protocol_sha
        cls.weights = {a: hashlib.sha256(a.encode()).hexdigest() for a in scoring.ARMS}
        cls.vocabulary = [chr(i) for i in range(32, 129)]
        hashes = [{key: "a" * 64 for key in previous.HASH_FIELDS} for _ in range(6208)]
        mappings = [{"opaqueID": f"{i:064x}", "normalizedWidth": 1.0, "normalizedHeight": 1.0,
                     "sourceRasterScale": 77.0, "effectivePixelsPerUnit": 77.0} for i in range(6208)]
        ordinals = list(range(6208))
        permutation_bytes = b"".join(i.to_bytes(8, "little", signed=True) for i in ordinals)
        permutation_sha = hashlib.sha256(permutation_bytes).hexdigest()
        complete_permutations = hashlib.sha256()
        for _ in range(30):
            complete_permutations.update(len(permutation_bytes).to_bytes(8, "big"))
            complete_permutations.update(permutation_bytes)
        ledger = {"sampleExposures": 6208 * 30, "updateCount": 49 * 30,
            "drawStreamSHA256": "b" * 64, "permutationStreamSHA256": complete_permutations.hexdigest(),
            "augmentedFeatureStreamSHA256": "c" * 64,
            "epochs": [{"epoch": e, "sampleCount": 6208, "batchCount": 49,
                "drawStreamSHA256": "d" * 64, "permutationSHA256": permutation_sha,
                "permutationOrdinals": ordinals, "augmentedFeatureSHA256": "e" * 64} for e in range(1, 31)]}
        cls.fit = {"version": scoring.FIT_VERSION, "scope": scoring.SCOPE, "sourceSHA256": previous.SOURCE_SHA256,
            "protocolSHA256": cls.protocol_sha, "codeSHA256": cls.code, "arms": list(scoring.ARMS),
            "trainingSamples": 6208, "developmentSamples": 1552, "reservedSamples": 3880,
            "trainingWriters": [f"trn_toy_{i:02}" for i in range(32)],
            "developmentWriters": [f"trn_toy_{i:02}" for i in range(32, 40)],
            "reservedWriters": [f"tst_toy_{i:02}" for i in range(20)],
            "vocabulary": cls.vocabulary, "vocabularySHA256": digest(cls.vocabulary),
            "runtime": {"python": "toy", "platform": "toy", "torch": "toy", "numpy": "toy", "cpuThreads": 4, "deterministicAlgorithms": True},
            "featureContract": scoring.FEATURE_CONTRACT, "modelContract": scoring.MODEL_CONTRACT,
            "optimization": scoring.OPTIMIZATION, "initialState": scoring.INITIAL_STATE,
            "augmentationContract": scoring.AUGMENTATION_CONTRACT,
            "augmentationLedger": {a: copy.deepcopy(ledger) for a in scoring.ARMS},
            "sourceRasterMappings": mappings, "sourceRasterMappingsSHA256": digest(mappings),
            "trainingInputHashes": hashes, "trainingInputHashesSHA256": digest(hashes),
            "trainingHistory": {a: [{"epoch": e, "trainCorrect": 0, "trainLoss": 1.0} for e in range(1, 31)] for a in scoring.ARMS},
            "weightFiles": {a: f"weights/{a}.pt" for a in scoring.ARMS}, "weightsSHA256": cls.weights,
            "selection": "final-epoch-only", "roleGuards": scoring.ROLE_GUARDS}
        cls.fit_bytes = canonical_json_bytes(cls.fit)
        cls.packet = {"version": scoring.PREDICTION_VERSION, "scope": scoring.SCOPE, "arms": list(scoring.ARMS),
            "rowCount": 1552, "sourceSHA256": previous.SOURCE_SHA256, "protocolSHA256": cls.protocol_sha,
            "codeSHA256": cls.code, "runtime": cls.fit["runtime"], "featureContract": scoring.FEATURE_CONTRACT,
            "fitReceiptSHA256": hashlib.sha256(cls.fit_bytes).hexdigest(), "weightsSHA256": cls.weights,
            "vocabularySHA256": cls.fit["vocabularySHA256"],
            "rows": [{"opaqueID": f"{i:064x}", "rasterSHA256": "d" * 64, "trajectorySHA256": "e" * 64,
                "sourceGroups": [[0]], "outputs": {a: {"embedding": [1.0] + [0.0] * 127,
                    "rawLogits": [1.0] + [0.0] * 96} for a in scoring.ARMS}} for i in range(1552)]}
        cls.packet_bytes = canonical_json_bytes(cls.packet)

    def validate(self, packet=None, fit=None):
        fit = self.fit if fit is None else fit
        return scoring.validate_prediction_packet(self.packet_bytes if packet is None else canonical_json_bytes(packet),
            fit, canonical_json_bytes(fit), self.code, self.protocol_sha, self.weights)

    def test_full_synthetic_packet_is_two_arm_label_free_and_nonproduction(self):
        self.assertEqual(self.validate()["rowCount"], 1552)
        self.assertFalse(self.fit["roleGuards"]["productionEligible"])
        self.assertEqual(set(self.fit["augmentationLedger"]), {"rasterOnly", "dual"})
        self.assertNotIn("torch", inspect.getsource(scoring).split("def personalize")[0].split("def code_identity")[0])

    def test_fit_and_prediction_bindings_reject_mutated_versions_weights_code_or_cohorts(self):
        for key, value in (("version", "other"), ("rowCount", 1551), ("sourceSHA256", "a" * 64),
                           ("fitReceiptSHA256", "0" * 64), ("weightsSHA256", {"dual": "0" * 64})):
            packet = copy.deepcopy(self.packet)
            packet[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(packet)
        for mutate in (lambda f: f["roleGuards"].update(reservedWritersEncoded=True),
                       lambda f: f["initialState"].update(sha256="0" * 64),
                       lambda f: f["optimization"].update(epochs=29),
                       lambda f: f["trainingHistory"]["dual"].pop()):
            fit = copy.deepcopy(self.fit)
            mutate(fit)
            with self.assertRaises(ValueError):
                self.validate(fit=fit)

    def test_augmentation_mismatch_counts_and_permutation_corruption_are_rejected(self):
        for mutate in (lambda l: l["dual"].update(drawStreamSHA256="a" * 64),
                       lambda l: l["dual"].update(sampleExposures=1),
                       lambda l: l["dual"]["epochs"][0]["permutationOrdinals"].__setitem__(0, 1),
                       lambda l: l["dual"]["epochs"][0].update(permutationSHA256="0" * 64),
                       lambda l: l["dual"].update(permutationStreamSHA256="0" * 64)):
            ledger = copy.deepcopy(self.fit["augmentationLedger"])
            mutate(ledger)
            with self.assertRaises(ValueError):
                scoring.validate_ledger(ledger)

    def test_source_mapping_rejects_resampled_scale_and_retains_zero_extent_convention(self):
        mappings = copy.deepcopy(self.fit["sourceRasterMappings"])
        mappings[0].update(normalizedWidth=0.0, normalizedHeight=0.0, sourceRasterScale=0.0, effectivePixelsPerUnit=77.0)
        scoring.validate_source_mappings(mappings)
        mappings[0]["effectivePixelsPerUnit"] = 1.0
        with self.assertRaises(ValueError):
            scoring.validate_source_mappings(mappings)
        mappings = copy.deepcopy(self.fit["sourceRasterMappings"])
        mappings[0]["sourceRasterScale"] = 78.0
        with self.assertRaises(ValueError):
            scoring.validate_source_mappings(mappings)

    def test_prediction_rows_reject_duplicates_labels_missing_arm_nonfinite_or_owner_loss(self):
        for mutate in (lambda p: p["rows"][1].update(opaqueID=p["rows"][0]["opaqueID"]),
                       lambda p: p["rows"][0].update(intended="A"),
                       lambda p: p["rows"][0]["outputs"].pop("rasterOnly"),
                       lambda p: p["rows"][0].update(sourceGroups=[[1]]),
                       lambda p: p["rows"].pop()):
            packet = copy.deepcopy(self.packet)
            mutate(packet)
            with self.assertRaises(ValueError):
                self.validate(packet)
        self.assertEqual(previous.argmax_label([2.0, 2.0], ["B", "A"]), "B")
        with self.assertRaises(ValueError):
            previous.argmax_label([math.nan, 0.0], ["A", "B"])

    def gate_rows(self, correct=150, deltas=None):
        deltas = [5] * 8 if deltas is None else deltas
        rows = []
        for writer, delta in enumerate(deltas):
            for i in range(194):
                rows.append({"writer": f"toy-{writer}", "intended": "A", "predictions": {
                    "rasterOnly": "A" if i < correct else "B", "dual": "A" if i < correct + delta else "C"}})
        return rows

    def test_historical_floor_and_writer_guards_are_all_required_with_raw_denominator(self):
        passing = scoring.advancement_gate(self.gate_rows())
        self.assertTrue(passing["nextBlindDevelopmentGateEligible"])
        self.assertEqual(passing["writerSignFlip"]["totalAssignments"], 256)
        self.assertFalse(passing["productionEligible"])
        below_floor = scoring.advancement_gate(self.gate_rows(correct=100))
        self.assertFalse(below_floor["rules"]["historicalOperationalFloor1229"])
        self.assertTrue(below_floor["rules"]["gainsExceedHarms"])
        self.assertFalse(below_floor["nextBlindDevelopmentGateEligible"])
        worst = scoring.advancement_gate(self.gate_rows(deltas=[10] * 7 + [-3]))
        self.assertFalse(worst["rules"]["worstWriterLossAtMostTwo"])
        with self.assertRaises(ValueError):
            scoring.advancement_gate(self.gate_rows()[:-1])
        wrong = previous.paired_summary([{"writer": "toy", "intended": "A", "predictions": {"rasterOnly": "B", "dual": "C"}}], "rasterOnly", "dual")
        self.assertEqual((wrong["gains"], wrong["harms"]), (0, 0))

    def test_personal_diagnostic_is_support_only_all97taught_and_never_claims_untaught_safety(self):
        rows = []
        for writer in range(8):
            for session in (1, 2):
                for label in self.vocabulary:
                    rows.append({"opaqueID": f"{len(rows):064x}", "writer": f"toy-{writer}", "session": session,
                        "intended": label, "predictions": {a: self.vocabulary[0] for a in scoring.ARMS},
                        "inputHashes": {key: "d" * 64 for key in previous.HASH_FIELDS}, "noveltyExclusions": []})
        packet_rows = {r["opaqueID"]: r for r in self.packet["rows"]}
        before = digest(rows)
        calls = []
        def predict(support_features, support_labels, query_features):
            calls.append((len(support_features), list(support_labels), len(query_features)))
            return [self.vocabulary[0]] * len(query_features)
        with patch.object(previous, "predict_personal", side_effect=predict):
            result = scoring.personalize(rows, packet_rows, self.vocabulary)
        self.assertEqual(len(calls), 16)
        self.assertTrue(all(n == q == 97 and labels == self.vocabulary for n, labels, q in calls))
        for report in result.values():
            self.assertEqual(report["rawPaired"]["count"], 776)
            self.assertTrue(report["all97ClassesTaught"])
            self.assertFalse(report["untaughtSafetyMeasured"])
            self.assertFalse(report["productionEligible"])
            self.assertEqual(report["noveltyCount"], 0)
        self.assertEqual(digest(rows), before)


if __name__ == "__main__":
    unittest.main()
