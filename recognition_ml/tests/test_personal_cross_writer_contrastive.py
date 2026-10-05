import importlib.util
import math
import unittest
from dataclasses import replace
from unittest.mock import patch

from ichart_recognition_ml.research.uji_personal import Sample, split_writers

HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "Optional training dependencies required")
class CrossWriterContrastiveTests(unittest.TestCase):
    def setUp(self):
        import torch
        torch.set_num_threads(2)
        torch.use_deterministic_algorithms(True)

    def test_loss_matches_explicit_cross_writer_log_probability_and_gradients(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import cross_writer_contrastive_loss
        features = torch.tensor([[1., 0.], [1., 0.], [0.6, 0.8], [0., 1.]],
                                dtype=torch.float64, requires_grad=True)
        labels, writers = torch.tensor([0, 0, 0, 1]), torch.tensor([0, 0, 1, 0])
        terms = []
        for anchor in (0, 1, 2):
            positive = [index for index in range(4)
                        if labels[index] == labels[anchor] and writers[index] != writers[anchor]]
            denominator = [index for index in range(4)
                           if labels[index] != labels[anchor] or writers[index] != writers[anchor]]
            similarity = features[anchor] @ features.T / 0.2
            terms.append(torch.logsumexp(similarity[denominator], dim=0) - similarity[positive].mean())
        expected = torch.stack(terms).mean()
        loss = cross_writer_contrastive_loss(features, labels, writers, 0.2)
        torch.testing.assert_close(loss, expected, rtol=0, atol=1e-14)
        loss.backward()
        self.assertTrue(torch.isfinite(features.grad).all())
        self.assertGreater(float(features.grad.abs().sum()), 0)

    def test_same_writer_same_class_is_ignored_in_denominator_and_other_classes_compete(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import cross_writer_contrastive_loss
        features = torch.tensor([[1., 0.], [1., 0.], [0., 1.], [-1., 0.]], dtype=torch.float64)
        labels, writers = torch.tensor([0, 0, 0, 1]), torch.tensor([0, 0, 1, 0])
        actual = cross_writer_contrastive_loss(features, labels, writers, 1.)
        # Anchors0/1 have one cross-writer positive and one other-class negative;
        # anchor2 has two positives plus one negative. Their own-writer rows
        # (including self) never compete, despite their perfect similarity.
        expected = (2 * math.log1p(math.exp(-1)) + math.log(3)) / 3
        self.assertAlmostEqual(float(actual), expected, places=14)
        without_negative = cross_writer_contrastive_loss(features[:3], labels[:3], writers[:3], 1.)
        self.assertAlmostEqual(float(without_negative), math.log(2) / 3, places=14)
        self.assertGreater(float(actual), float(without_negative))

    def test_anchors_without_positives_are_skipped_and_all_absent_returns_differentiable_zero(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import (
            contrastive_anchor_counts, cross_writer_contrastive_loss)
        features = torch.eye(3, dtype=torch.float64, requires_grad=True)
        labels, writers = torch.tensor([0, 1, 2]), torch.tensor([0, 0, 1])
        loss = cross_writer_contrastive_loss(features, labels, writers)
        self.assertEqual(float(loss.detach()), 0.)
        self.assertTrue(loss.requires_grad)
        loss.backward()
        torch.testing.assert_close(features.grad, torch.zeros_like(features), rtol=0, atol=0)
        counts = contrastive_anchor_counts(labels, writers)
        self.assertEqual((counts["validAnchors"], counts["skippedAnchors"]), (0, 3))
        singleton = cross_writer_contrastive_loss(features[:1], labels[:1], writers[:1])
        self.assertEqual(float(singleton.detach()), 0.)

    def test_loss_rejects_malformed_nonfinite_nonunit_and_index_inputs(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import cross_writer_contrastive_loss
        features = torch.eye(2)
        labels, writers = torch.tensor([0, 0]), torch.tensor([0, 1])
        bad_features = (features[:0], torch.ones(2, 0), torch.ones(2), features.to(torch.long),
                        features * 2, torch.zeros_like(features), features * float("nan"),
                        features * float("inf"), [[1., 0.], [0., 1.]])
        for value in bad_features:
            with self.subTest(features=value), self.assertRaises(ValueError):
                cross_writer_contrastive_loss(value, labels, writers)
        for temperature in (0, -1, float("nan"), float("inf"), True, "0.07", 1e-300):
            with self.subTest(temperature=temperature), self.assertRaises(ValueError):
                cross_writer_contrastive_loss(features, labels, writers, temperature)
        for value in (labels[:1], labels[:, None], labels.float(), torch.tensor([-1, 0]), [0, 0]):
            for position in (1, 2):
                args = [features, labels, writers]
                args[position] = value
                with self.subTest(value=value, position=position), self.assertRaises(ValueError):
                    cross_writer_contrastive_loss(*args)


@unittest.skipUnless(HAS_TORCH, "Optional training dependencies required")
class CrossWriterBatchPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.labels = tuple(chr(0x100 + index) for index in range(97))
        cls.records = tuple(Sample(f"{prefix}_UPV_W{writer:02d}", session, label, ())
                            for prefix, count in (("trn", 40), ("tst", 20))
                            for writer in range(count) for session in (1, 2) for label in cls.labels)

    def test_exact_once_full_vocabulary_and_one_cross_writer_positive_in_every_batch(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import (
            contrastive_anchor_counts, epoch_batch_plan, select_training_samples)
        training, training_writers, development, reserved = select_training_samples(self.records)
        batches = epoch_batch_plan(self.records, 0)
        self.assertEqual([len(batch) for batch in batches], [194] * 32)
        flat = [index for batch in batches for index in batch]
        self.assertEqual(sorted(flat), list(range(6208)))
        self.assertTrue(set(sample.writer for sample in training).isdisjoint(development + reserved))
        self.assertEqual(set(sample.writer for sample in training), set(training_writers))
        for batch in batches:
            for offset in range(0, len(batch), 2):
                group = [training[index] for index in batch[offset:offset + 2]]
                self.assertEqual(len({sample.label for sample in group}), 1)
                self.assertEqual(len({sample.writer for sample in group}), 2)
            self.assertEqual({training[index].label for index in batch}, set(self.labels))
            targets = torch.tensor([self.labels.index(training[index].label) for index in batch])
            writers = torch.tensor([training_writers.index(training[index].writer) for index in batch])
            counts = contrastive_anchor_counts(targets, writers)
            self.assertEqual(counts["skippedAnchors"], 0)
            self.assertEqual(counts["minimumPositives"], 1)
            self.assertEqual(counts["maximumPositives"], 1)
        for label in self.labels:
            for writer in training_writers:
                positions = [batch_index for batch_index, batch in enumerate(batches)
                             if any(training[index].label == label and training[index].writer == writer
                                    for index in batch)]
                self.assertEqual(len(positions), 2)
                partners = []
                for position in positions:
                    partners.append({training[index].writer for index in batches[position]
                                     if training[index].label == label and training[index].writer != writer})
                self.assertEqual(partners[0], partners[1])

    def test_plan_is_repeatable_order_independent_and_epoch_changes_permutation(self):
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import epoch_batch_plan
        first = epoch_batch_plan(self.records, 0)
        self.assertEqual(first, epoch_batch_plan(self.records, 0))
        self.assertEqual(first, epoch_batch_plan(tuple(reversed(self.records)), 0))
        self.assertNotEqual(first, epoch_batch_plan(self.records, 1))

    def test_role_and_completeness_guards_fail_before_rasterization(self):
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import epoch_batch_plan
        training_writers, development, _ = split_writers(self.records)
        train_only = tuple(sample for sample in self.records if sample.writer in training_writers)
        duplicates = self.records[:-1] + self.records[:1]
        contaminated = tuple(replace(sample, writer=development[0])
                             if sample.writer == training_writers[0] else sample for sample in self.records)
        malformed = (replace(self.records[0], session=3),) + self.records[1:]
        with patch("ichart_recognition_ml.research.personal_visual_encoder.rasterize") as raster:
            for records in (train_only, duplicates, contaminated, malformed, self.records[:-1]):
                with self.subTest(records_count=len(records)), self.assertRaises(ValueError):
                    epoch_batch_plan(records, 0)
            raster.assert_not_called()
        for epoch, seed in ((-1, 29), (30, 29), (True, 29), (0, -1), (0, True)):
            with self.subTest(epoch=epoch, seed=seed), self.assertRaises(ValueError):
                epoch_batch_plan(self.records, epoch, seed=seed)

    def test_matched_models_reuse_original_architecture_and_initial_tensors(self):
        import torch
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import (
            ARMS, initialized_models)
        from ichart_recognition_ml.research.personal_visual_encoder import PersonalVisualEncoder
        models, receipt = initialized_models()
        self.assertEqual(set(models), set(ARMS))
        self.assertEqual(len(set(receipt["armSHA256"].values())), 1)
        for model in models.values():
            self.assertIsInstance(model, PersonalVisualEncoder)
            self.assertEqual(model.classifier.out_features, 97)
        for name in models[ARMS[0]].state_dict():
            self.assertTrue(torch.equal(models[ARMS[0]].state_dict()[name], models[ARMS[1]].state_dict()[name]))

    def test_json_protocol_requires_exact_fixed_settings_and_rejects_duplicate_or_nonfinite_fields(self):
        import json
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import (
            PROTOCOL_DOCUMENT_SHA256, _read_protocol, frozen_protocol)
        envelope = {"settings": frozen_protocol(), "purpose": "synthetic test",
                    "markdownProtocolSHA256": PROTOCOL_DOCUMENT_SHA256}
        self.assertEqual(_read_protocol(json.dumps(envelope).encode()), envelope)
        changed = {**frozen_protocol(), "batchRows": 128}
        for payload in (b"", b"[]", b'{"settings": {}, "settings": {}}',
                        b'{"settings": {}, "value": NaN}',
                        json.dumps({**envelope, "settings": changed}).encode(),
                        json.dumps({**envelope, "markdownProtocolSHA256": "a" * 64}).encode(),
                        json.dumps({**envelope, "sourceSHA256": "a" * 64}).encode(),
                        json.dumps({**envelope, "settings": {**frozen_protocol(), "extra": 1}}).encode()):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                _read_protocol(payload)

    def test_training_feature_export_is_unit_float32_and_binds_exact_opaque_source_order(self):
        import io
        import numpy as np
        from ichart_recognition_ml.research.personal_cross_writer_contrastive import (
            _training_feature_payload, opaque_training_id, select_training_samples)
        training, _, _, _ = select_training_samples(self.records)
        inputs = [{"sourceID": sample.identity, "writer": sample.writer,
                   "session": sample.session, "label": sample.label, "rasterSHA256": "a" * 64}
                  for sample in training]
        features = np.zeros((6208, 128), dtype=np.float32)
        features[:, 0] = 1
        payload = _training_feature_payload(features, inputs)
        with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
            self.assertEqual(set(bundle.files), {"features", "labels", "writers", "sourceIDs", "sessions", "rasterSHA256"})
            np.testing.assert_array_equal(bundle["features"], features)
            self.assertEqual(bundle["sourceIDs"].tolist(), [opaque_training_id(sample.identity) for sample in training])
            self.assertEqual(bundle["labels"].tolist(), [sample.label for sample in training])
            self.assertEqual(bundle["writers"].tolist(), [sample.writer for sample in training])
        for bad in (features.astype(np.float64), features * 2, features * float("nan"), features[:-1]):
            with self.subTest(shape=bad.shape), self.assertRaises(ValueError):
                _training_feature_payload(bad, inputs)
        for bad in (inputs[:-1], inputs[:-1] + inputs[:1], list(reversed(inputs)),
                    [{**row, "writer": "tst_UPV_W01"} if index == 0 else row
                     for index, row in enumerate(inputs)]):
            with self.assertRaises(ValueError):
                _training_feature_payload(features, bad)


if __name__ == "__main__":
    unittest.main()
