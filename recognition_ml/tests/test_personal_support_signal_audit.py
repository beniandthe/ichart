import copy
import json
import math
import unittest

import numpy as np
import torch

from ichart_recognition_ml.research import personal_support_signal_audit as audit


class SupportSignalAuditTests(unittest.TestCase):
    def example(self):
        features = torch.tensor([[1., 0.], [0., 1.], [.6, .8]], dtype=torch.float64)
        probabilities = torch.tensor([[.7, .1, .1, .1], [.1, .6, .2, .1], [.4, .1, .1, .4]], dtype=torch.float64)
        labels = torch.tensor([0, 1, 0])
        query = torch.tensor([[.8, .6], [0., 1.]], dtype=torch.float64)
        generic = torch.tensor([[.1, .1, .7, .1], [.05, .7, .1, .15]], dtype=torch.float64)
        return features, probabilities, labels, query, generic

    def test_fixed_grid_full_mass_and_alpha_zero_identity(self):
        self.assertEqual(audit.ALPHAS, (0., .01, .03, .05, .1, .2, .35, .5, .75, 1.))
        cache, details = audit.cache_evidence(*self.example())
        generic = self.example()[-1]
        self.assertEqual(cache.shape, generic.shape)
        torch.testing.assert_close(cache.sum(1), torch.ones(2, dtype=torch.float64), rtol=0, atol=1e-15)
        self.assertEqual(cache[:, 2:].count_nonzero().item(), 0)
        self.assertEqual(details["labelMultiplicity"], [2, 1, 0, 0])
        mixtures = audit.mixtures(generic, cache)
        self.assertTrue(torch.equal(mixtures[0], generic))
        self.assertTrue(torch.equal(mixtures[-1], cache))
        for index, alpha in enumerate(audit.ALPHAS):
            torch.testing.assert_close(mixtures[index][:, 2:], (1 - alpha) * generic[:, 2:], rtol=0, atol=0)

    def test_support_permutation_and_exact_duplicate_triplet_invariance(self):
        features, probabilities, labels, query, generic = self.example()
        original, _ = audit.cache_evidence(features, probabilities, labels, query, generic)
        order = torch.tensor([2, 0, 1])
        permuted, _ = audit.cache_evidence(features[order], probabilities[order], labels[order], query, generic)
        duplicate, details = audit.cache_evidence(torch.cat((features, features[:1])),
            torch.cat((probabilities, probabilities[:1])), torch.cat((labels, labels[:1])), query, generic)
        self.assertTrue(torch.equal(original, permuted))
        self.assertTrue(torch.equal(original, duplicate))
        self.assertEqual((details["supportCountBefore"], details["supportCountAfter"]), (4, 3))
        self.assertEqual(sorted(len(group) for group in details["deduplicatedSupportGroups"]), [1, 1, 2])

    def test_class_permutation_equivariance(self):
        features, probabilities, labels, query, generic = self.example()
        original, _ = audit.cache_evidence(features, probabilities, labels, query, generic)
        permutation = torch.tensor([2, 0, 3, 1])
        inverse = permutation.argsort()
        permuted, _ = audit.cache_evidence(features, probabilities[:, permutation], inverse[labels], query, generic[:, permutation])
        torch.testing.assert_close(permuted, original[:, permutation], rtol=0, atol=1e-14)

    def test_invalid_matrix_feature_label_contracts_fail(self):
        features, probabilities, labels, query, generic = self.example()
        for bad in (features.float(), features * 2, features * float("nan"), features.flatten(), [[1., 0.]]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                audit.cache_evidence(bad, probabilities, labels, query, generic)
        for bad in (probabilities.float(), probabilities * 2, probabilities * float("nan"), probabilities[:, :-1]):
            with self.assertRaises(ValueError):
                audit.cache_evidence(features, bad, labels, query, generic)
        for bad in (labels.float(), labels[:2], torch.tensor([-1, 1, 0]), torch.tensor([0, 1, 4])):
            with self.assertRaises(ValueError):
                audit.cache_evidence(features, probabilities, bad, query, generic)

    def test_frozen_predictions_do_not_use_query_answers(self):
        arrays = {name: np.zeros((4, width), dtype=np.float32) for name, width in
                  (("raw_features", 128), ("stored_features", 128), ("raw_logits", 97), ("stored_logits", 97))}
        arrays["raw_features"][:, 0] = arrays["stored_features"][:, 0] = 1
        vocabulary = [chr(0x100 + i) for i in range(97)]
        rows = [{"label": vocabulary[index]} for index in range(4)]
        plans = [{"writer": "trn_UPV_W00", "session": 1, "support": [0, 1], "queries": [2, 3]}]
        first = audit.predict_episodes(arrays, rows, vocabulary, plans)
        rows[2]["label"], rows[3]["label"] = vocabulary[20], vocabulary[30]
        second = audit.predict_episodes(arrays, rows, vocabulary, plans)
        self.assertEqual(audit.canonical(first), audit.canonical(second))
        self.assertNotIn("trueLabelIndex", first[0])

    def test_gain_harm_cache_signal_and_balanced_nll_arithmetic(self):
        generic = torch.tensor([[.1, .8, .1], [.05, .05, .9]], dtype=torch.float64)
        cache = torch.tensor([[.95, .05, 0.], [.95, .05, 0.]], dtype=torch.float64)
        prediction = {"episodeIndex": 0, "writer": "trn_UPV_W00", "supportSession": 1, "task": "K10",
            "queryIndices": [0, 1], "deduplicatedSupport": {"uniqueSupportLabels": [0, 1]},
            "genericProbabilities": generic.tolist(), "cacheProbabilities": cache.tolist(),
            "mixtureTop1Indices": [value.argmax(1).tolist() for value in audit.mixtures(generic, cache)]}
        observations = audit.score_training_predictions([prediction], [{"label": "A"}, {"label": "C"}], ["A", "B", "C"])
        summary = audit.summarize(observations)
        zero, high = summary[0], summary[audit.ALPHAS.index(.75)]
        self.assertEqual((zero["strata"]["all"]["gains"], zero["strata"]["all"]["harms"]), (0, 0))
        self.assertEqual((high["strata"]["all"]["gains"], high["strata"]["all"]["harms"], high["strata"]["all"]["netCorrect"]), (1, 1, 0))
        self.assertEqual(high["correctUntaughtOvertaken"], 1)
        self.assertEqual(high["taughtBaselineMistakesTrueCacheTop1"], 1)
        self.assertEqual(high["taughtBaselineMistakesTrueCacheCoHighest"], 1)
        expected = -.5 * math.log(.75 * .95 + .25 * .1) - .5 * math.log(.25 * .9)
        self.assertAlmostEqual(high["balancedNLL"], expected)
        self.assertAlmostEqual(high["pooledBalancedNLL"], expected)
        with self.assertRaises(ValueError):
            audit.summarize([observations[0]])

    def test_query_exposures_distinct_source_rows_and_ink_fingerprints_are_separate(self):
        rows = [{"rawRasterSHA256": "r", "trajectorySHA256": "t"},
                {"rawRasterSHA256": "r", "trajectorySHA256": "t"}]
        counts = audit.exposure_counts([0, 1, 0], rows)
        self.assertEqual((counts["queryExposures"], counts["distinctSourceIndices"], counts["distinctJointInkFingerprints"]), (3, 2, 1))
        self.assertEqual(counts["sourceIndexExposureHistogram"], {1: 1, 2: 1})
        self.assertEqual(counts["jointCopyGroups"][0]["sourceIndices"], [0, 1])
        self.assertFalse(counts["physicalSampleIndependenceEstablished"])
        with self.assertRaises(ValueError):
            audit.exposure_counts([2], rows)

    def test_training_observations_and_summary_are_canonical_json_native(self):
        generic = torch.tensor([[.1, .8, .1], [.05, .05, .9]], dtype=torch.float64)
        cache = torch.tensor([[.95, .05, 0.], [.95, .05, 0.]], dtype=torch.float64)
        prediction = {"episodeIndex": 0, "writer": "trn_UPV_W00", "supportSession": 1, "task": "K10",
            "queryIndices": [0, 1], "deduplicatedSupport": {"uniqueSupportLabels": [0, 1]},
            "genericProbabilities": generic.tolist(), "cacheProbabilities": cache.tolist(),
            "mixtureTop1Indices": [value.argmax(1).tolist() for value in audit.mixtures(generic, cache)]}
        observations = audit.score_training_predictions([prediction], [{"label": "A"}, {"label": "C"}], ["A", "B", "C"])
        self.assertIs(type(observations[0]["taughtBaselineMistakeTrueCacheCoHighest"]), bool)
        self.assertTrue(observations[0]["taughtBaselineMistakeTrueCacheCoHighest"])
        parsed_observations = json.loads(audit.canonical(observations))
        self.assertEqual(parsed_observations, observations)
        self.assertIs(type(parsed_observations[0]["taughtBaselineMistakeTrueCacheCoHighest"]), bool)
        summary = audit.summarize(observations)
        parsed_summary = json.loads(audit.canonical(summary))
        self.assertEqual(parsed_summary, summary)
        self.assertIs(type(summary[0]["taughtBaselineMistakesTrueCacheCoHighest"]), int)
        self.assertIs(type(parsed_summary[0]["taughtBaselineMistakesTrueCacheCoHighest"]), int)
        self.assertEqual(parsed_summary[0]["taughtBaselineMistakesTrueCacheCoHighest"], 1)

    def synthetic_bundle(self):
        writers = [f"trn_UPV_W{i:02d}" for i in range(32)]
        vocabulary = [chr(0x100 + i) for i in range(97)]
        ranked = sorted(writers, key=lambda writer: audit.sha(("personal-support-retrieval-v1:fold:" + writer).encode()))
        receipt = {"vocabulary": vocabulary, "trainingWriters": writers, "developmentWriters": [f"trn_UPV_W{i:02d}" for i in range(32, 40)],
            "reservedWriters": [f"tst_UPV_W{i:02d}" for i in range(20)], "folds": {"A": ranked[:16], "B": ranked[16:]}}
        rows = []
        for writer in writers:
            for session in (1, 2):
                for label in vocabulary:
                    source_id = f"{writer}-{session}-{label}"
                    rows.append({"sourceID": source_id, "writer": writer, "session": session, "label": label,
                        "generator": "fitA" if writer in receipt["folds"]["B"] else "fitB", "genericFitCopyReasons": [], "storedFailure": None,
                        **{name: audit.sha((name + source_id).encode()) for name in
                           ("rawRasterSHA256", "storedRasterSHA256", "trajectorySHA256", "storedTrajectorySHA256")}})
        arrays = {name: np.zeros((6208, width), dtype=np.float32) for name, width in
                  (("raw_features", 128), ("stored_features", 128), ("raw_logits", 97), ("stored_logits", 97))}
        arrays["raw_features"][:, 0] = arrays["stored_features"][:, 0] = 1
        arrays["stored_available"] = np.ones(6208, dtype=np.bool_)
        return arrays, rows, receipt

    def test_training_only_roles_complete_grid_and_fixed128_episodes(self):
        arrays, rows, receipt = self.synthetic_bundle()
        plans = audit.validate_bundle(arrays, rows, receipt)
        self.assertEqual(len(plans), 128)
        exposures = [index for plan in plans for index in plan["queries"]]
        self.assertEqual(len(exposures), 12416)
        self.assertEqual(len(set(exposures)), 6208)
        altered = copy.deepcopy(rows)
        altered[0]["writer"] = "tst_UPV_W00"
        with self.assertRaises(ValueError):
            audit.validate_bundle(arrays, altered, receipt)
        altered = copy.deepcopy(rows)
        altered[0]["session"] = True
        with self.assertRaises(ValueError):
            audit.validate_bundle(arrays, altered, receipt)
        with self.assertRaises(ValueError):
            audit.validate_bundle(arrays, rows[:-1], receipt)

    def test_invalid_or_unavailable_bundle_matrices_fail_closed(self):
        arrays, rows, receipt = self.synthetic_bundle()
        for bad in ({**arrays, "raw_features": arrays["raw_features"].astype(np.float64)},
                    {**arrays, "raw_logits": arrays["raw_logits"] * float("nan")},
                    {**arrays, "stored_available": arrays["stored_available"].astype(np.float32)}):
            with self.assertRaises(ValueError):
                audit.validate_bundle(bad, rows, receipt)
        rows[0].update(storedFailure="PersonalInkShape-unavailable", storedRasterSHA256=None, storedTrajectorySHA256=None)
        arrays["stored_available"][0] = False
        with self.assertRaises(ValueError):
            audit.validate_bundle(arrays, rows, receipt)
        arrays["stored_features"][0] = 0
        self.assertEqual(len(audit.validate_bundle(arrays, rows, receipt)), 128)


if __name__ == "__main__":
    unittest.main()
