import copy
import unittest

from ichart_recognition_ml.research.personal_whole_chord_scoring import score_selected_predictions
from ichart_recognition_ml.research.personal_whole_chord_source import ACQUISITION_ORDERS


def fixture():
    truth, factor, atom = [], [], []
    for session in (1, 2):
        for order in ACQUISITION_ORDERS:
            identity = f"opaque-{session}-{order}"
            truth.append({"sampleID": identity, "writer": "trn_UJI_W04", "session": session,
                "canonicalLabel": "C7", "acquisitionOrder": order, "role": "development",
                "syntheticNotNaturalInk": True, "trajectorySourceSHA256": "a" * 64})
            factor.append({"sampleID": identity, "inputSHA256": "a" * 64,
                "canonicalLabel": "C7", "inputFailure": None})
            atom.append({"sampleID": identity, "inputSHA256": "a" * 64,
                "canonicalLabel": "D7", "inputFailure": None})
    return truth, factor, atom


class WholeChordScoringTests(unittest.TestCase):
    def score(self, parts):
        return score_selected_predictions(*parts, expected_writers=("trn_UJI_W04",), canonical_labels=("C7",))

    def test_exact_paired_counts_and_nonpromotion(self):
        data = fixture()
        frozen = copy.deepcopy(data)
        result = self.score(data)
        self.assertEqual(data, frozen)
        self.assertEqual(result["rowCount"], 4)
        for order in ACQUISITION_ORDERS:
            self.assertEqual(result["summaries"][order]["counts"]["net"], 2)
        self.assertTrue(result["syntheticBridgeScreenPass"])
        self.assertFalse(result["productionEligible"])
        self.assertFalse(result["personalizationBenefitTested"])

    def test_missing_duplicate_and_wrong_role_fail(self):
        for location in range(3):
            data = fixture(); data[location].pop()
            with self.assertRaises(ValueError): self.score(data)
            data = fixture(); data[location].append(copy.deepcopy(data[location][0]))
            with self.assertRaises(ValueError): self.score(data)
        for key, value in (("writer", "tst_UJI_W01"), ("session", True),
                           ("syntheticNotNaturalInk", False), ("role", "training")):
            data = fixture(); data[0][0][key] = value
            with self.assertRaises(ValueError): self.score(data)

    def test_changed_input_hash_and_unknown_prediction_fields_fail(self):
        data = fixture(); data[1][0]["inputSHA256"] = "b" * 64
        with self.assertRaises(ValueError): self.score(data)
        data = fixture(); data[2][0]["intendedLabel"] = "C7"
        with self.assertRaises(ValueError): self.score(data)

    def test_nulls_failures_and_regressions_are_not_removed(self):
        data = fixture(); data[1][0]["canonicalLabel"] = None
        data[1][0]["inputFailure"] = "representationCannotFit"
        data[2][0]["canonicalLabel"] = "C7"
        result = self.score(data)
        self.assertEqual(result["rowCount"], 4)
        primary = result["summaries"][ACQUISITION_ORDERS[0]]["counts"]
        self.assertEqual(primary["regressions"], 1)
        self.assertEqual(primary["factorInputFailures"], 1)
        self.assertFalse(result["rules"]["zeroInputFailures"])
        self.assertFalse(result["syntheticBridgeScreenPass"])

    def test_reversed_order_is_a_required_separate_guard(self):
        data = fixture()
        for index, truth in enumerate(data[0]):
            if truth["acquisitionOrder"] == ACQUISITION_ORDERS[1]:
                data[1][index]["canonicalLabel"] = "D7"
                data[2][index]["canonicalLabel"] = "C7"
        result = self.score(data)
        self.assertTrue(result["rules"]["positivePrimaryNet"])
        self.assertFalse(result["rules"]["noReversedStressWriterRegression"])
        self.assertFalse(result["syntheticBridgeScreenPass"])

    def test_valid_uncovered_output_is_wrong_not_relabeled(self):
        data = fixture(); data[1][0]["canonicalLabel"] = "C#7"
        result = self.score(data)
        self.assertFalse(result["rows"][0]["factorCorrect"])
        self.assertEqual(result["summaries"][ACQUISITION_ORDERS[0]]["factorComponentErrorsOnNonNull"]["rootPitchWrong"], 1)


class FrozenWrapperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch
        torch.set_num_threads(2)

    def factor_row(self):
        from ichart_recognition_ml.models.output_contract import OUTPUT_HEADS, factorize_canonical_label
        from ichart_recognition_ml.research import personal_whole_chord_factor as factor
        targets = factorize_canonical_label("C7")
        raw = {h.name: [9. if (targets.values[h.name][i] if h.is_independent_bernoulli else i == targets.values[h.name]) else -9.
            for i in range(len(h.labels))] for h in OUTPUT_HEADS}
        decoded = factor.decode_factor_logits(factor.conditional_valid_rooted_logits(raw), maximum_candidate_count=3)
        return {"sampleID": "0" * 64, "inputSHA256": "a" * 64, "logits": raw, "inputFailure": None,
            "conditionalCanonicalLabel": "C7", "conditionalValidRootedCandidates": [
                {"canonicalLabel": c.canonical_label, "rawJointLogScore": c.raw_joint_log_score} for c in decoded.candidates],
            "rasterSHA256": "b" * 64, "trajectorySHA256": "c" * 64}

    def atomic_packet(self):
        from ichart_recognition_ml.research import personal_whole_chord_atomic_control as atomic
        vocabulary = [chr(33 + i) for i in range(97)]
        owners = []
        for i, token in enumerate("C7"):
            logits = [-9.] * 97; first = vocabulary.index(token); logits[first] = 9.
            owners.append({"ownerOrdinal": i, "sourceStrokeIndexes": [i], "sourceStrokeCount": 1, "sourcePointCount": 2,
                "ownerInputSHA256": "b" * 64, "rasterSHA256": str(i) * 64, "rawLogits": logits,
                "firstArgmaxIndex": first, "firstArgmaxToken": token, "cacheHit": False, "failure": None})
        return {"vocabulary": vocabulary, "vocabularySHA256": atomic.sha256(atomic.canonical_bytes(vocabulary)),
            "ownerCount": 2, "ownerFailures": 0, "inputFailures": 0, "rows": [{"sampleID": "0" * 64,
                "inputSHA256": "a" * 64, "oracleProjectionRowSHA256": "c" * 64, "sourceStrokeCount": 2,
                "sourcePointCount": 4, "owners": owners, "rawTokenString": "C7", "canonicalChord": "C7",
                "inputFailure": False, "parserOutcome": "canonical"}]}

    def test_raw_ten_heads_conditioning_and_full97_greedy_are_rederived(self):
        from ichart_recognition_ml.research import personal_whole_chord_scoring as scorer
        raw = self.factor_row(); raw["logits"]["kind"] = [-40., 40.]; raw["logits"]["validity"] = [40., -40.]
        before = copy.deepcopy(raw)
        self.assertEqual(scorer._raw_factor_selection([raw])[0]["canonicalLabel"], "C7")
        self.assertEqual(raw, before)
        for key in ("conditionalCanonicalLabel", "conditionalValidRootedCandidates"):
            bad = copy.deepcopy(raw); bad[key] = "D7" if key.endswith("Label") else []
            with self.assertRaises(ValueError): scorer._raw_factor_selection([bad])
        packet = self.atomic_packet()
        self.assertEqual(scorer._raw_atomic_selection(packet)[0]["canonicalLabel"], "C7")
        bad = copy.deepcopy(packet); bad["rows"][0]["owners"][0]["firstArgmaxToken"] = "D"
        with self.assertRaises(ValueError): scorer._raw_atomic_selection(bad)
        bad = copy.deepcopy(packet); bad["rows"][0]["owners"][1]["rawLogits"][0] = float("nan")
        with self.assertRaises(ValueError): scorer._raw_atomic_selection(bad)

    def test_retained_failures_are_null_and_never_rescued(self):
        from ichart_recognition_ml.research import personal_whole_chord_scoring as scorer
        factor = self.factor_row()
        factor.update(inputFailure="representationCannotFit", logits=None, rasterSHA256=None, trajectorySHA256=None,
            conditionalCanonicalLabel=None, conditionalValidRootedCandidates=None)
        self.assertIsNone(scorer._raw_factor_selection([factor])[0]["canonicalLabel"])
        factor["conditionalCanonicalLabel"] = "C7"
        with self.assertRaises(ValueError): scorer._raw_factor_selection([factor])
        packet = self.atomic_packet(); owner = packet["rows"][0]["owners"][0]
        owner.update(failure="owner-model-output-or-inference-failure", rawLogits=None, firstArgmaxIndex=None, firstArgmaxToken=None)
        packet["rows"][0].update(rawTokenString=None, canonicalChord=None, inputFailure=True, parserOutcome="owner-failure")
        packet.update(ownerFailures=1, inputFailures=1)
        self.assertIsNotNone(scorer._raw_atomic_selection(packet)[0]["inputFailure"])
        packet["rows"][0]["canonicalChord"] = "C7"
        with self.assertRaises(ValueError): scorer._raw_atomic_selection(packet)

    def test_full168_eight_writer_grid_and_5376_denominator_cannot_narrow(self):
        from ichart_recognition_ml.research.personal_whole_chord_source import canonical_chord_specs
        writers = tuple(f"trn_UJI_W{i:02}" for i in range(8))
        truth, factor, atomic = [], [], []
        for writer in writers:
            for session in (1, 2):
                for label, _ in canonical_chord_specs():
                    for order in ACQUISITION_ORDERS:
                        identity = str(len(truth))
                        truth.append({"sampleID": identity, "writer": writer, "session": session, "canonicalLabel": label,
                            "acquisitionOrder": order, "role": "development", "syntheticNotNaturalInk": True,
                            "trajectorySourceSHA256": "a" * 64})
                        factor.append({"sampleID": identity, "inputSHA256": "a" * 64, "canonicalLabel": label, "inputFailure": None})
                        atomic.append({"sampleID": identity, "inputSHA256": "a" * 64, "canonicalLabel": None, "inputFailure": None})
        report = score_selected_predictions(truth, factor, atomic, expected_writers=writers)
        self.assertEqual(report["rowCount"], 5376)
        self.assertTrue(all(report["summaries"][o]["counts"]["count"] == 2688 for o in ACQUISITION_ORDERS))
        with self.assertRaises(ValueError): score_selected_predictions(truth[:-1], factor[:-1], atomic[:-1], expected_writers=writers)

    def test_atomic_receipt_runtime_paths_packet_sha_and_copy_manifest_binding(self):
        import importlib.metadata
        import platform
        from pathlib import Path
        import numpy as np
        from ichart_recognition_ml.research import personal_whole_chord_atomic_control as atomic
        from ichart_recognition_ml.research import personal_whole_chord_factor as factor
        from ichart_recognition_ml.research import personal_whole_chord_scoring as scorer
        from ichart_recognition_ml.research import personal_whole_chord_source as source
        packet = self.atomic_packet(); template = packet["rows"][0]
        packet["rows"] = [{**template, "sampleID": f"{i:064x}", "owners": [{**o, "cacheHit": i != 0} for o in template["owners"]]}
            for i in range(5376)]
        code, protocol, manifest = {"test-only": "d" * 64}, b"synthetic protocol", b"synthetic artifact manifest"
        artifacts = {"vocabulary": packet["vocabulary"], "vocabularySHA256": packet["vocabularySHA256"],
            "manifestSHA256": atomic.sha256(manifest), "packageSHA256": "e" * 64, "weightsMetadataSHA256": "f" * 64}
        guards = {"privateInkUsed": False, "reservedWritersComposed": False, "reservedWritersEncoded": False,
            "automaticAcceptanceAuthorized": False, "sourceTruthSuppliedToPredictor": False, "sourceWriterSuppliedToPredictor": False}
        runtime = {"kind": "pinned-operational-CoreML", "computeUnits": "CPU_ONLY", "coremltoolsVersion": importlib.metadata.version("coremltools"),
            "numpyVersion": np.__version__, "pythonVersion": platform.python_version(), "platform": platform.platform(),
            "modelExported": False, "torchWeightsReconstructed": False, **{k: v for k, v in artifacts.items() if k != "vocabulary"}}
        packet.update(version=atomic.VERSION, scope=atomic.SCOPE, productionEligible=False, automaticOwnership=False,
            swiftProbabilitySearch=False, truthJoined=False, personalizationTested=False, trustOrAcceptanceApplied=False,
            composition="unrestricted-97-first-argmax-concatenation-strict-canonical-or-null", codeSHA256=code,
            sourceSHA256=factor.SOURCE_SHA256, protocolSHA256=atomic.sha256(protocol), developmentWriterCount=8,
            trainingWriterCount=32, reservedWriterCount=20, sourcePlanVersion=source.VERSION, roleGuards=guards,
            rowCount=5376, inputDrops=0, cacheByExactRasterSHA256=True, roleBindingSHA256="d" * 64,
            oracleProjectionSHA256="a" * 64, ownerCount=10752, modelCallCount=2, runtime=runtime)
        packet["bindings"] = {"sourceSHA256": factor.SOURCE_SHA256, "protocolSHA256": atomic.sha256(protocol),
            "roleBindingSHA256": packet["roleBindingSHA256"], "codeSnapshotSHA256": atomic.sha256(atomic.canonical_bytes(code)),
            "manifestSHA256": artifacts["manifestSHA256"], "packageSHA256": artifacts["packageSHA256"]}
        files = {"predictions.json": atomic.canonical_bytes(packet), "frozen-protocol.md": protocol,
            "code-snapshot.json": atomic.canonical_bytes(code), "model-manifest.json": manifest}
        paths = Path("/private/tmp/test-only-manifest"), Path("/private/tmp/test-only-package")
        receipt = {"version": atomic.RECEIPT_VERSION, "scope": atomic.SCOPE, "productionEligible": False,
            "predictionsRelativePath": "predictions.json", "predictionsSHA256": atomic.sha256(files["predictions.json"]),
            "predictionsByteCount": len(files["predictions.json"]), "inputsUnchanged": True,
            "modelManifestPath": str(paths[0]), "modelPackagePath": str(paths[1]), "modelManifestRelativePath": "model-manifest.json",
            **{k: artifacts[k] for k in ("manifestSHA256", "packageSHA256", "weightsMetadataSHA256", "vocabularySHA256")},
            **{k: packet[k] for k in ("codeSHA256", "sourceSHA256", "protocolSHA256", "roleBindingSHA256", "sourcePlanVersion",
                "oracleProjectionSHA256", "runtime", "rowCount", "ownerCount", "modelCallCount", "inputDrops", "inputFailures", "ownerFailures", "roleGuards")}}
        files["prediction-receipt.json"] = atomic.canonical_bytes(receipt)
        before = copy.deepcopy(files)
        _, selected = scorer._atomic_binding(files, code, protocol, artifacts, *paths)
        self.assertEqual(len(selected), 5376); self.assertEqual(files, before)
        for change in ("packetSHA", "runtime", "path", "copiedManifest"):
            bad = dict(files)
            if change == "copiedManifest": bad["model-manifest.json"] = b"changed"
            else:
                altered = copy.deepcopy(receipt)
                if change == "packetSHA": altered["predictionsSHA256"] = "0" * 64
                elif change == "runtime": altered["runtime"]["computeUnits"] = "ALL"
                else: altered["modelPackagePath"] = "/private/tmp/other"
                bad["prediction-receipt.json"] = atomic.canonical_bytes(altered)
            with self.assertRaises(ValueError): scorer._atomic_binding(bad, code, protocol, artifacts, *paths)


if __name__ == "__main__":
    unittest.main()
