import copy
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


@unittest.skipUnless(importlib.util.find_spec("torch"), "Optional training dependencies required")
class PersonalDualViewAdaptationTests(unittest.TestCase):
    def setUp(self):
        import torch
        torch.set_num_threads(2)
        torch.manual_seed(29)

    @staticmethod
    def vocabulary():
        from ichart_recognition_ml.research.personal_dual_view_adaptation import SPARSE_LABELS
        return tuple(sorted(set(SPARSE_LABELS) | {chr(0x400 + index) for index in range(81)}))

    @staticmethod
    def samples(writers, vocabulary):
        from ichart_recognition_ml.research.uji_personal import Sample
        return tuple(Sample(writer, session, label, ())
                     for writer in writers for session in (1, 2) for label in vocabulary)

    def test_episode_plan_is_seeded_balanced_complete_and_copy_excluding(self):
        from ichart_recognition_ml.research.personal_dual_view_adaptation import (
            CODE_PATHS, EPOCHS, episode_manifest, plan_episodes, support_window,
            validate_episode_manifest,
        )
        vocabulary = self.vocabulary()
        writers = tuple(f"trn_UJI_W{index:02d}" for index in range(32))
        samples = self.samples(writers, vocabulary)
        rasters = [hashlib.sha256((sample.identity + ":r").encode()).hexdigest() for sample in samples]
        normalized = [hashlib.sha256((sample.identity + ":n").encode()).hexdigest() for sample in samples]
        # One exact raster pair must be excluded whenever its source label is in
        # that directed episode's rotating support window.
        first = {(sample.writer, sample.session, sample.label): index for index, sample in enumerate(samples)}
        rasters[first[writers[0], 2, vocabulary[0]]] = rasters[first[writers[0], 1, vocabulary[0]]]
        episodes, counts = plan_episodes(samples, writers, vocabulary, rasters, normalized)
        repeated, repeated_counts = plan_episodes(samples, writers, vocabulary, rasters, normalized)
        self.assertEqual(episodes, repeated)
        self.assertEqual(counts, repeated_counts)
        self.assertEqual(len(episodes), EPOCHS * 64)
        self.assertLessEqual(max(counts.values()) - min(counts.values()), 1)
        self.assertEqual([episode.global_index for episode in episodes], list(range(len(episodes))))
        self.assertTrue(any(episode.exclusions for episode in episodes))
        for episode in episodes:
            self.assertEqual(tuple(samples[index].label for index in episode.support),
                             support_window(vocabulary, episode.global_index))
            self.assertTrue(set(episode.support).isdisjoint(episode.queries))
            self.assertTrue(all(samples[index].writer == episode.writer
                                and samples[index].session == episode.support_session
                                for index in episode.support))
            self.assertTrue(all(samples[index].writer == episode.writer
                                and samples[index].session == 3 - episode.support_session
                                for index in episode.queries))
        code = {path: "a" * 64 for path in CODE_PATHS}
        sample_hashes = [{"normalizedTrajectorySHA256": normalized[index],
                          "rasterSHA256": rasters[index],
                          "trajectorySHA256": hashlib.sha256((sample.identity + ":t").encode()).hexdigest()}
                         for index, sample in enumerate(samples)]
        manifest = episode_manifest(episodes, samples, sample_hashes, counts, vocabulary, code, "b" * 64)
        self.assertIs(validate_episode_manifest(manifest, code=code, protocol_sha="b" * 64,
                                                vocabulary=vocabulary), manifest)
        tampered = copy.deepcopy(manifest)
        tampered["episodes"][0]["globalEpisodeIndex"] = 1
        with self.assertRaises(ValueError):
            validate_episode_manifest(tampered, code=code, protocol_sha="b" * 64,
                                      vocabulary=vocabulary)
        swapped = copy.deepcopy(manifest)
        low = next(label for label, count in swapped["supportCounts"].items() if count == min(counts.values()))
        high = next(label for label, count in swapped["supportCounts"].items() if count == max(counts.values()))
        swapped["supportCounts"][low], swapped["supportCounts"][high] = (
            swapped["supportCounts"][high], swapped["supportCounts"][low])
        # Sum and max-min balance are unchanged; only reconstruction from the
        # 640 recorded windows can reject this falsified receipt.
        with self.assertRaises(ValueError):
            validate_episode_manifest(swapped, code=code, protocol_sha="b" * 64,
                                      vocabulary=vocabulary)

    def test_role_or_coverage_contamination_refuses_before_planning(self):
        from dataclasses import replace
        from ichart_recognition_ml.research.personal_dual_view_adaptation import plan_episodes
        vocabulary = self.vocabulary()
        writers = ("trn_UJI_W00",)
        samples = self.samples(writers, vocabulary)
        hashes = [hashlib.sha256(str(index).encode()).hexdigest() for index in range(len(samples))]
        for invalid in (samples[:-1], samples + samples[:1],
                        tuple(replace(sample, writer="tst_UJI_W00") for sample in samples)):
            with self.assertRaises(ValueError):
                plan_episodes(invalid, writers, vocabulary, hashes[:len(invalid)],
                              hashes[:len(invalid)], epochs=1)

    def test_float64_solver_matches_unchanged_numpy_residual_and_has_gradients(self):
        import numpy as np
        import torch
        from ichart_recognition_ml.research.personal_adaptability import adapted_scores
        from ichart_recognition_ml.research.personal_residual import ResidualHead, normalized_scores
        support = torch.nn.functional.normalize(torch.randn(4, 7, dtype=torch.float64), dim=1).requires_grad_()
        support_logits = torch.randn(4, 5, dtype=torch.float64, requires_grad=True)
        labels = torch.tensor([0, 0, 2, 4])
        queries = torch.nn.functional.normalize(torch.randn(3, 7, dtype=torch.float64), dim=1).requires_grad_()
        query_logits = torch.randn(3, 5, dtype=torch.float64, requires_grad=True)
        actual = adapted_scores(support, support_logits, labels, queries, query_logits)
        vocabulary = tuple("ABCDE")
        head = ResidualHead.fit(support.detach().numpy(), normalized_scores(support_logits.detach().numpy()),
                                tuple(vocabulary[index] for index in labels), vocabulary, regularization=0.1)
        expected = []
        for feature, logits in zip(queries.detach().numpy(), query_logits.detach().numpy()):
            by_label = {row["label"]: row["score"] for row in head.rank(feature, normalized_scores(logits[None])[0])}
            expected.append([by_label[label] for label in vocabulary])
        np.testing.assert_allclose(actual.detach().numpy(), expected, atol=1e-12, rtol=1e-12)
        torch.nn.functional.cross_entropy(actual, torch.tensor([1, 2, 3])).backward()
        for value in (support, support_logits, queries, query_logits):
            self.assertTrue(torch.isfinite(value.grad).all())
            self.assertGreater(float(value.grad.abs().sum()), 0)

    def test_matched_control_scale_and_candidate_use_query_truth_only_as_outer_target(self):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research.personal_dual_view_adaptation import Episode, episode_losses

        class Tiny(torch.nn.Module):
            def __init__(self):
                super().__init__()
                self.projection = torch.nn.Linear(1, 128)
                self.classifier = torch.nn.Linear(128, 97)

            def forward(self, trajectory, raster):
                feature = torch.nn.functional.normalize(self.projection(trajectory[:, 0, 0, :1]), dim=1)
                return feature, self.classifier(feature)

        count = 7
        trajectory = torch.zeros(count, 1, 256, 10)
        trajectory[:, 0, 0, 0] = torch.arange(1, count + 1)
        batch = dual.FeatureBatch(trajectory, torch.zeros(count, 1, 96, 256),
                                  tuple("a" * 64 for _ in range(count)),
                                  tuple("b" * 64 for _ in range(count)), None)
        targets = torch.tensor([0, 1, 2, 3, 4, 5, 6])
        episode = Episode(1, 0, "trn_UJI_W00", 1, (0, 1), (2, 3, 4, 5, 6), ())
        model = Tiny()
        control, generic, repeated = episode_losses(model, batch, targets, episode, adaptation_aware=False)
        self.assertEqual(float(control), float(generic))
        self.assertEqual(float(repeated), float(generic))
        candidate, same_generic, residual = episode_losses(model, batch, targets, episode, adaptation_aware=True)
        self.assertEqual(float(same_generic), float(generic))
        self.assertEqual(candidate.dtype, torch.float64)
        self.assertEqual(residual.dtype, torch.float64)
        # Query answers alter only the outer loss; the learner has no query-label argument.
        changed = targets.clone()
        changed[list(episode.queries)] = (changed[list(episode.queries)] + 11) % 97
        changed_loss, changed_generic, _ = episode_losses(model, batch, changed, episode, adaptation_aware=True)
        self.assertNotEqual(float(changed_loss), float(candidate))
        self.assertNotEqual(float(changed_generic), float(generic))

    def test_synthetic_continuation_preserves_source_model_and_batchnorm_buffers(self):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research.personal_dual_view_adaptation import Episode, train_arm
        model = dual.PersonalDualViewEncoder(97, "dual").eval()
        original = {key: value.clone() for key, value in model.state_dict().items()}
        count = 6
        batch = dual.FeatureBatch(
            torch.randn(count, 1, 256, 10), torch.randint(0, 256, (count, 1, 96, 256), dtype=torch.uint8),
            tuple("a" * 64 for _ in range(count)), tuple("b" * 64 for _ in range(count)), None)
        episode = Episode(1, 0, "trn_UJI_W00", 1, (0, 1), (2, 3, 4, 5), ())
        trained, history, _ = train_arm(model, "adaptationAware", batch,
                                        torch.tensor([0, 1, 2, 3, 4, 5]), (episode,), epochs=1)
        self.assertEqual(len(history), 1)
        self.assertFalse(torch.equal(trained.classifier.weight, model.classifier.weight))
        for key, value in model.state_dict().items():
            torch.testing.assert_close(value, original[key], rtol=0, atol=0)
            if "running_" in key or "num_batches_tracked" in key:
                torch.testing.assert_close(trained.state_dict()[key], value, rtol=0, atol=0)

    def test_checkpoint_round_trip_binds_training_arm_and_parent(self):
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research.personal_dual_view_adaptation import (
            PARENT_DUAL_WEIGHT_SHA256, VOCABULARY_SHA256, _checkpoint_bytes, _load_checkpoint,
        )
        model = dual.PersonalDualViewEncoder(97, "dual")
        payload = _checkpoint_bytes(model, "genericControl", VOCABULARY_SHA256, PARENT_DUAL_WEIGHT_SHA256)
        restored = _load_checkpoint(payload, "genericControl", VOCABULARY_SHA256)
        for key, value in model.state_dict().items():
            torch.testing.assert_close(restored.state_dict()[key], value, rtol=0, atol=0)
        with self.assertRaises(ValueError):
            _load_checkpoint(payload, "adaptationAware", VOCABULARY_SHA256)

    def _prediction_fixture(self):
        from ichart_recognition_ml.research.personal_dual_view_adaptation import (
            ARMS, CODE_PATHS, PREDICTION_VERSION, SCOPE, SPARSE_LABELS, VOCABULARY_SHA256,
        )
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research.personal_dual_view_adaptation import _residual_ranks, opaque_id
        vocabulary = list(self.vocabulary())
        writers = ["trn_UJI_W00"]
        code = {path: "c" * 64 for path in CODE_PATHS}
        receipt = {"developmentWriters": writers, "vocabulary": vocabulary,
                   "weightsSHA256": {arm: hashlib.sha256(arm.encode()).hexdigest() for arm in ARMS}}
        def output(index):
            embedding = [0.0] * 128
            embedding[index] = 1.0
            logits = [-1.0] * 97
            logits[index] = 2.0
            return {arm: {"embedding": embedding[:], "rawLogits": logits[:]} for arm in ARMS}
        support, queries = [], []
        ordinal = 0
        for writer in writers:
            for index, label in enumerate(vocabulary):
                base = {"inputHashes": {key: hashlib.sha256(f"{writer}:1:{label}:{key}".encode()).hexdigest()
                                         for key in ("normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256")},
                        "opaqueID": opaque_id(ordinal, writer, 1), "outputs": output(index),
                        "session": 1, "sourceOrdinal": ordinal, "writer": writer, "label": label}
                ordinal += 1
                support.append(base)
                query = {"inputHashes": {key: hashlib.sha256(f"{writer}:2:{label}:{key}".encode()).hexdigest()
                                          for key in ("normalizedTrajectorySHA256", "rasterSHA256", "trajectorySHA256")},
                         "opaqueID": opaque_id(ordinal, writer, 2), "outputs": output(index),
                         "session": 2, "sourceOrdinal": ordinal, "writer": writer}
                ordinal += 1
                queries.append(query)
        support.sort(key=lambda row: row["opaqueID"])
        queries.sort(key=lambda row: row["opaqueID"])
        for writer in writers:
            writer_support = [row for row in support if row["writer"] == writer]
            writer_queries = sorted((row for row in queries if row["writer"] == writer), key=lambda row: row["opaqueID"])
            frozen = {arm: _residual_ranks(writer_support, writer_queries, vocabulary, arm) for arm in ARMS}
            for index, row in enumerate(writer_queries):
                row["predictions"] = {arm: frozen[arm][index] for arm in ARMS}
        runtime = {"synthetic": True}
        fit_bytes = b"synthetic-fit"
        packet = {"arms": list(ARMS), "codeSHA256": code, "featureContract": dual._feature_contract(),
                  "fitReceiptSHA256": hashlib.sha256(fit_bytes).hexdigest(), "protocolSHA256": "d" * 64,
                  "queryCount": 97, "queryRows": queries, "runtime": runtime, "scope": SCOPE,
                  "sourceSHA256": dual.SOURCE_SHA256, "sparseSupportLabels": list(SPARSE_LABELS),
                  "supportCount": 97, "supportRows": support, "version": PREDICTION_VERSION,
                  "vocabulary": vocabulary, "vocabularySHA256": VOCABULARY_SHA256,
                  "weightsSHA256": receipt["weightsSHA256"]}
        return packet, receipt, fit_bytes, code, runtime

    def test_prediction_packet_is_query_unlabeled_complete_and_arithmetic_bound(self):
        from ichart_recognition_ml.research import personal_dual_view_adaptation as module
        from ichart_recognition_ml.research.personal_dual_view_adaptation import validate_prediction
        packet, receipt, fit_bytes, code, runtime = self._prediction_fixture()
        with patch.object(module, "QUERY_COUNT", 97), patch.object(module, "DEVELOPMENT_SAMPLE_COUNT", 194):
            validated = validate_prediction(packet, receipt=receipt, receipt_bytes=fit_bytes, code=code,
                                            protocol_sha="d" * 64, runtime=runtime)
        self.assertIs(validated, packet)
        self.assertTrue(all("label" not in row for row in packet["queryRows"]))
        self.assertTrue(all(len(row["predictions"]["adaptationAware"]["residualRanking"]) == 97
                            for row in packet["queryRows"]))
        for mutate in ("query_label", "missing_rank", "score_tamper", "duplicate_id"):
            changed = copy.deepcopy(packet)
            if mutate == "query_label":
                changed["queryRows"][0]["label"] = "wrong"
            elif mutate == "missing_rank":
                changed["queryRows"][0]["predictions"]["genericControl"]["residualRanking"].pop()
            elif mutate == "score_tamper":
                changed["queryRows"][0]["predictions"]["genericControl"]["residualRanking"][0]["score"] += 1
            else:
                changed["queryRows"][1]["opaqueID"] = changed["queryRows"][0]["opaqueID"]
            with self.assertRaises(ValueError, msg=mutate):
                with patch.object(module, "QUERY_COUNT", 97), patch.object(module, "DEVELOPMENT_SAMPLE_COUNT", 194):
                    validate_prediction(changed, receipt=receipt, receipt_bytes=fit_bytes, code=code,
                                        protocol_sha="d" * 64, runtime=runtime)

    def test_query_answer_mutation_preserves_projected_ids_order_and_blind_rows(self):
        from dataclasses import replace
        import numpy as np
        import torch
        from ichart_recognition_ml.research import personal_dual_view as dual
        from ichart_recognition_ml.research.personal_dual_view_adaptation import (
            ARMS, _output_rows, development_projection,
        )
        from ichart_recognition_ml.research.uji_personal import Sample
        writer = "trn_UJI_W00"
        records = (Sample(writer, 2, "A", ()), Sample(writer, 2, "B", ()))
        changed = tuple(replace(sample, label=label) for sample, label in zip(records, ("X", "Y")))
        first = development_projection(records, (writer,), expected_count=2)
        second = development_projection(changed, (writer,), expected_count=2)
        self.assertEqual([(row[1], row[2]) for row in first], [(row[1], row[2]) for row in second])
        batch = dual.FeatureBatch(torch.zeros(2, 1, 256, 10), torch.zeros(2, 1, 96, 256),
                                  ("a" * 64,) * 2, ("b" * 64,) * 2, ("c" * 64,) * 2)
        embedding = np.zeros((2, 128), dtype=np.float32)
        embedding[:, 0] = 1
        outputs = {arm: (embedding, np.zeros((2, 97), dtype=np.float32)) for arm in ARMS}
        self.assertEqual(_output_rows(first, batch, outputs, expose_support_labels=False),
                         _output_rows(second, batch, outputs, expose_support_labels=False))

    def test_snapshot_uses_captured_bytes_and_source_parser_has_no_path_reread(self):
        import inspect
        from ichart_recognition_ml.research import personal_dual_view_adaptation as module
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "input"
            path.write_bytes(b"captured")
            captured = path.read_bytes()
            path.write_bytes(b"changed")
            snapshot = module._snapshot_bytes({path: captured})
            with patch.object(module, "code_identity", return_value={}):
                with self.assertRaises(ValueError):
                    module._preserved(snapshot, {})
        self.assertNotIn("read_bytes", inspect.getsource(module._load_source_bytes))

    def test_generic_ties_preserve_vocabulary_order(self):
        from ichart_recognition_ml.research.personal_dual_view_adaptation import _generic_rank
        vocabulary = ("z", "a", "m")
        ranking = _generic_rank(vocabulary, (1.0, 1.0, 0.0))
        self.assertEqual([row["label"] for row in ranking], ["z", "a", "m"])
        self.assertAlmostEqual(sum(row["score"] for row in ranking), 1.0)

    def test_output_directory_is_exclusive_and_canonical(self):
        from ichart_recognition_ml.research.personal_dual_view_adaptation import _new_directory
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary).resolve()
            created = _new_directory(parent / "new")
            self.assertTrue(created.is_dir())
            with self.assertRaises(ValueError):
                _new_directory(created)


if __name__ == "__main__":
    unittest.main()
