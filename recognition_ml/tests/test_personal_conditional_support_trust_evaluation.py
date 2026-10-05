"""Synthetic evaluator boundaries; no retained source or fitted model opened."""
import base64
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_conditional_support_trust_evaluation as evaluation


def plan_fixture():
    vocabulary = [chr(33 + i) for i in range(97)]
    writers = [f"trn_UPV_W{i:02d}" for i in range(1, 9)]
    roles = {"generator": "fitA", "freshValidation": False, "internalValidationWriters": writers,
             "metaFitWriters": [f"meta{i}" for i in range(8)], "encoderFitWriters": [f"fit{i}" for i in range(16)],
             "sourceIndices": {"internalValidation": list(range(1552))}}
    plans = []
    for writer_position, writer in enumerate(writers):
        for session in (1, 2):
            support_start = writer_position * 194 + (session - 1) * 97
            queries = list(range(writer_position * 194 + (2 - session) * 97,
                                 writer_position * 194 + (2 - session) * 97 + 97))
            for count in (10, 21):
                plans.append({"episodeIndex": len(plans), "role": "internalValidation", "epoch": 1,
                    "writer": writer, "session": session, "querySession": 3 - session, "task": f"K{count}",
                    "support": list(range(support_start, support_start + count)), "supportLabels": vocabulary[:count],
                    "queries": queries[1:], "scheduledQueries": queries,
                    "exclusions": [{"index": queries[0], "reasons": ["support-raster-copy"]}], "unavailableSetup": []})
    return vocabulary, roles, plans


def packet_fixture():
    vocabulary, roles, plans = plan_fixture()
    bindings = {"vocabulary": vocabulary, "roleManifest": roles, "sourcePlan": plans}
    frozen = evaluation.canonical(bindings)
    probability = [1 / 97] * 97
    feature = [1.] + [0.] * 127
    return {"version": evaluation.VERSION,
            **{k: False for k in ("queryTruthOpened", "productionEligible", "freshValidation", "encoderInferencePerformed",
                "developmentWritersEvaluated", "reservedWritersEvaluated", "privateInkUsed", "appOrProfileChanged")},
            "bindings": bindings, "commitmentCanonicalData": base64.b64encode(frozen).decode(),
            "commitmentSHA256": evaluation.sha(frozen),
            "episodes": [{"episodeIndex": p["episodeIndex"], "supportFeatures": [feature] * len(p["support"]),
                "supportProbabilities": [probability] * len(p["support"]),
                "supportLabelIndices": list(range(len(p["support"]))),
                "rows": [{"sourceIndex": i, "genericProbabilities": probability, "candidateProbabilities": probability,
                          "outcome": "read", "failure": None} for i in p["scheduledQueries"]]} for p in plans]}


class ConditionalSupportTrustEvaluationTests(unittest.TestCase):
    def test_failures_and_task_repetition_remain_denominators(self):
        rows = [{"exposureID": "0:1", "sourceIndex": 1, "outcome": "read", "genericCorrect": False, "candidateCorrect": True},
                {"exposureID": "1:1", "sourceIndex": 1, "outcome": "invalid", "genericCorrect": True, "candidateCorrect": False},
                {"exposureID": "0:2", "sourceIndex": 2, "outcome": "invalid", "genericCorrect": False, "candidateCorrect": False}]
        result = evaluation.summarize(rows)
        self.assertEqual((result["queryExposures"], result["distinctSourceIndices"], result["invalid"]), (3, 2, 2))
        self.assertEqual((result["gains"], result["harms"], result["netCorrect"], result["neitherCorrect"]), (1, 1, 0, 1))
        self.assertEqual(result["harmExposureIDs"], ["1:1"])

    def test_source_only_screen_not_raw_copy_diagnostic(self):
        rows = []
        for task in evaluation.TASKS:
            for position, (taught, generic, candidate, reasons) in enumerate(
                    ((True, False, True, []), (False, True, True, []), (False, True, False, ["support-raster-copy"]))):
                rows.append({"task": task, "writer": "w", "supportSession": 1, "sourceIndex": position,
                    "exposureID": f"{task}:{position}", "outcome": "read", "taught": taught,
                    "genericCorrect": generic, "candidateCorrect": candidate, "exclusions": reasons})
        tasks, passed = evaluation.summaries(rows, ["w"])
        self.assertTrue(passed)
        self.assertFalse(tasks["K10"]["rawScheduled"]["authoritativeFixedScreen"])
        self.assertEqual(tasks["K10"]["rawScheduled"]["strata"]["untaught"]["harms"], 1)
        rows[-1]["exclusions"] = []
        self.assertFalse(evaluation.summaries(rows, ["w"])[1])

    def test_writer_roles_and_complete_source_plan_reject_tampering(self):
        vocabulary, roles, plans = plan_fixture()
        evaluation.validate_plan(plans, vocabulary, roles)
        self.assertEqual(sum(len(p["scheduledQueries"]) for p in plans), 3104)
        changed = copy.deepcopy(roles); changed["metaFitWriters"][0] = roles["internalValidationWriters"][0]
        with self.assertRaises(ValueError): evaluation.validate_plan(plans, vocabulary, changed)
        changed = copy.deepcopy(plans); changed[0]["scheduledQueries"][0] = True
        with self.assertRaises(ValueError): evaluation.validate_plan(changed, vocabulary, roles)
        changed = copy.deepcopy(plans); changed.pop()
        with self.assertRaises(ValueError): evaluation.validate_plan(changed, vocabulary, roles)

    def test_inference_receives_five_tensors_not_query_answers_and_retains_invalid(self):
        class Spy:
            def probabilities(self, *args):
                self.arguments = args
                result = args[4].clone(); result[1, 0] = float("nan")
                return result
        spy = Spy(); feature = np.zeros((3, 128), dtype=np.float32); feature[:, 0] = 1
        arrays = {"stored_features": feature, "raw_features": feature,
                  "stored_logits": np.zeros((3, 97), np.float32), "raw_logits": np.zeros((3, 97), np.float32)}
        vocabulary = [chr(33 + i) for i in range(97)]
        plan = {"support": [0], "scheduledQueries": [1, 2], "supportLabels": [vocabulary[4]], "episodeIndex": 0}
        result = evaluation.apply_episode(spy, arrays, plan, vocabulary)
        self.assertEqual(len(spy.arguments), 5)
        self.assertTrue(all(isinstance(t, torch.Tensor) for t in spy.arguments))
        self.assertEqual(spy.arguments[2].tolist(), [4])
        self.assertEqual([r["sourceIndex"] for r in result["rows"]], [1, 2])
        self.assertEqual([r["outcome"] for r in result["rows"]], ["read", "invalid"])
        self.assertIsNone(result["rows"][1]["candidateProbabilities"])
        self.assertEqual(len(result["rows"][1]["genericProbabilities"]), 97)

    def test_packet_alignment_hash_and_full_probability_contract(self):
        packet = packet_fixture(); evaluation.validate_packet(packet)
        changed = copy.deepcopy(packet); changed["commitmentSHA256"] = "0" * 64
        with self.assertRaises(ValueError): evaluation.validate_packet(changed)
        changed = copy.deepcopy(packet); changed["episodes"][0]["rows"].pop()
        with self.assertRaises(ValueError): evaluation.validate_packet(changed)
        changed = copy.deepcopy(packet); changed["episodes"][0]["rows"][0]["candidateProbabilities"] = [0.] * 97
        with self.assertRaises(ValueError): evaluation.validate_packet(changed)

    def test_prediction_sha_gate_precedes_query_metadata_join_and_output_is_exclusive(self):
        predictions = Path("/private/tmp/only-predictions.json")
        with patch.object(evaluation, "read", return_value=b"{}") as reader:
            with self.assertRaisesRegex(ValueError, "SHA mismatch before truth"):
                evaluation.score(predictions, "0" * 64, Path("/private/tmp/no-crossfit"), Path("/private/tmp/no-roles"),
                                 Path("/private/tmp/no-learner"), Path("/private/tmp/no-protocol"), Path("/private/tmp/no-score"))
            reader.assert_called_once_with(predictions)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "new.json"
            evaluation.common.exclusive(output, b"{}")
            with self.assertRaises(ValueError): evaluation.common.exclusive(output, b"replacement")
            self.assertEqual(output.read_bytes(), b"{}")

    def test_real_fitted_loader_and_predict_never_parse_query_metadata(self):
        from ichart_recognition_ml.research import personal_conditional_support_trust as core
        vocabulary, roles, validation = plan_fixture()
        roles["sourceIndices"]["metaFit"] = list(range(1552, 3104))
        training = []
        for epoch in range(1, 31):
            for p in validation:
                p = copy.deepcopy(p); p["epoch"] = epoch
                p["writer"] = roles["metaFitWriters"][roles["internalValidationWriters"].index(p["writer"])]
                for key in ("support", "scheduledQueries", "queries"):
                    p[key] = [i + 1552 for i in p[key]]
                p["exclusions"] = [{"index": e["index"] + 1552, "reasons": e["reasons"]} for e in p["exclusions"]]
                training.append(p)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); parent = root / "crossfit"; parent.mkdir()
            learner = root / "learner"; learner.mkdir()
            # Invalid JSON makes an accidental metadata/receipt parse fail.
            marker = b"QUERY_ANSWER_MARKER must never be parsed at inference"
            for name in ("fit-receipt.json", "fit-plan.json", "metadata.json", "protocol.md"):
                (parent / name).write_bytes(marker)
            (parent / "weights").mkdir()
            for arm in ("fitA", "fitB"): (parent / "weights" / f"{arm}.pt").write_bytes(b"hash-only-parent")
            features = np.zeros((6208, 128), np.float32); features[:, 0] = 1
            np.savez(parent / "features.npz", raw_features=features, stored_features=features,
                     raw_logits=np.zeros((6208, 97), np.float32), stored_logits=np.zeros((6208, 97), np.float32),
                     stored_available=np.ones(6208, np.bool_))
            parents = core.input_identity(parent)
            role_data = evaluation.canonical(roles); role_sha = evaluation.sha(role_data)
            protocol = Path(evaluation.__file__).resolve().parents[3] / evaluation.PROTOCOL
            (learner / "protocol.md").write_bytes(protocol.read_bytes())
            code = {"synthetic-fixture": "1" * 64}
            for name, value in (("role-manifest.json", roles), ("parent-binding.json", parents),
                                ("episode-plan.json", training), ("fit-plan.json", core.frozen_fit_plan()), ("code-before.json", code)):
                (learner / name).write_bytes(evaluation.canonical(value))
            plans_sha = evaluation.sha((learner / "episode-plan.json").read_bytes())
            checkpoint_binding = {"protocolSHA256": evaluation.PROTOCOL_SHA256,
                "parentBindingSHA256": evaluation.sha(evaluation.canonical(parents)), "roleManifestSHA256": role_sha,
                "episodePlanSHA256": plans_sha, "finalEpoch": 30}
            model = core.ConditionalSupportTrust()
            weights = core.checkpoint_bytes(model, checkpoint_binding); (learner / "weights.pt").write_bytes(weights)
            receipt = {**core.frozen_fit_plan(), "protocolSHA256": evaluation.PROTOCOL_SHA256, "codeSHA256": code,
                "parentDirectory": str(parent), "parentBinding": parents, "parentBindingSHA256": checkpoint_binding["parentBindingSHA256"],
                "roleManifestSHA256": role_sha, "roleManifest": roles, "episodePlanSHA256": plans_sha,
                "fitPlanSHA256": evaluation.sha(evaluation.canonical(core.frozen_fit_plan())), "weightsSHA256": evaluation.sha(weights),
                "checkpointBinding": checkpoint_binding, "vocabulary": vocabulary, "finalStateSHA256": core._state_digest(model.state_dict()),
                "history": [{"epoch": epoch, "updates": 32, "maximumAbsoluteGradient": 1.} for epoch in range(1, 31)],
                **{k: False for k in ("productionEligible", "freshValidation", "privateInkUsed", "reservedWritersEvaluated",
                                      "internalValidationUsedDuringFit", "otherGeneratorUsed", "appOrProfileMutated")}}
            receipt_data = evaluation.canonical(receipt); (learner / "fit-receipt.json").write_bytes(receipt_data)
            roles_path = root / "roles.json"; roles_path.write_bytes(role_data)
            evaluation.common.configure()
            binding = {"version": evaluation.COMMITMENT_VERSION, "predictionPerformed": False,
                "protocolSHA256": evaluation.PROTOCOL_SHA256, "parentBinding": parents,
                "roleManifestSHA256": role_sha, "roleManifest": roles, "learnerReceiptSHA256": evaluation.sha(receipt_data),
                "learnerFilesSHA256": evaluation.common.tree_identity(learner), "codeSHA256": code,
                "runtime": evaluation.common.runtime_identity(), "vocabulary": vocabulary,
                "sourcePlan": validation, "sourcePlanSHA256": evaluation.sha(evaluation.canonical(validation))}
            commitment = root / "commitment.json"; commitment.write_bytes(evaluation.canonical(binding))
            original_loads = json.loads
            def guarded_loads(data, *args, **kwargs):
                self.assertNotIn("QUERY_ANSWER_MARKER", data.decode() if isinstance(data, bytes) else data)
                return original_loads(data, *args, **kwargs)
            # Only pinned SHA/code constants are substituted for synthetic artifacts.
            # The real loader, parent-file hashing, checkpoint and predictor run unchanged.
            with patch.object(core, "ROLE_SHA256", role_sha), patch.object(evaluation, "ROLE_SHA256", role_sha), \
                    patch.object(core.audit, "RECEIPT_SHA256", parents["fit-receipt.json"]), \
                    patch.object(core.audit, "FEATURES_SHA256", parents["features.npz"]), \
                    patch.object(core, "code_identity", return_value=code), patch.object(evaluation, "code_identity", return_value=code), \
                    patch.object(core, "load_parent", side_effect=AssertionError("query metadata join reached inference")) as source_join, \
                    patch.object(core.json, "loads", side_effect=guarded_loads):
                result = evaluation.predict(parent, roles_path, learner, protocol, commitment, root / "predictions.json")
                source_join.assert_not_called()
            self.assertEqual(result["scheduledExposures"], 3104)
            self.assertFalse(result["queryTruthOpened"])


if __name__ == "__main__":
    unittest.main()
