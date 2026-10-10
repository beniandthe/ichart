import copy
import json
import math
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import numpy as np
import torch

from ichart_recognition_ml.research import personal_broad_transfer as fit
from ichart_recognition_ml.research.uji_personal import Sample


class BroadTransferTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)
        torch.use_deterministic_algorithms(True)
        cls.vocabulary = tuple(sorted(tuple(fit.nist.LABELS) + tuple(chr(0x100 + i) for i in range(35))))
        cls.records = tuple(Sample(f"{prefix}_UPV_W{writer:02d}", session, label, ())
                            for prefix, count in (("trn", 40), ("tst", 20)) for writer in range(count)
                            for session in (1, 2) for label in cls.vocabulary)
        cls.training, cls.writers, cls.development, cls.reserved = fit.select_training_samples(cls.records)

    def protocol(self):
        return {"settings": fit.frozen_protocol(), "sourceSHA256": fit.SOURCE_SHA256,
            "markdownProtocolSHA256": fit.PROTOCOL_DOCUMENT_SHA256,
            "researchUseDecisionSHA256": fit.RESEARCH_DECISION_SHA256,
            "nistTrainingSource": {key: "a" * 64 for key in
                ("receiptSHA256", "selectionJSONLSHA256", "rastersBinSHA256")}}

    def test_fixed_budget_scheduler_and_contract(self):
        contract = fit.frozen_protocol()
        self.assertEqual(fit.PRETRAIN_ROWS, 512 * 62)
        self.assertEqual(fit.PRETRAIN_BATCHES * fit.PRETRAIN_BATCH_ROWS, fit.PRETRAIN_ROWS)
        self.assertEqual(fit.FINETUNE_BATCHES * 194, fit.FINETUNE_ROWS)
        self.assertEqual(5 * 248 + 30 * 32, 2200)
        self.assertEqual(contract["arms"], ["ujiReplayPretrain", "nistBroadPretrain"])
        self.assertFalse(contract["productionEligible"])
        self.assertFalse(contract["commercialTrainingEligibilityEstablished"])
        for epochs in (5, 30):
            value = torch.nn.Parameter(torch.tensor(1.))
            optimizer = torch.optim.AdamW([value], lr=.001, weight_decay=.0001)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
            for epoch in range(epochs):
                self.assertAlmostEqual(optimizer.param_groups[0]["lr"], .001 * (1 + math.cos(math.pi * epoch / epochs)) / 2)
                optimizer.step()
                scheduler.step()
            self.assertEqual(scheduler.last_epoch, epochs)
            self.assertEqual(optimizer.param_groups[0]["lr"], 0.)

    def test_protocol_rejects_changed_duplicate_and_nonfinite_fields(self):
        protocol = self.protocol()
        self.assertEqual(fit._read_protocol(json.dumps(protocol).encode()), protocol)
        invalid = [b"[]", b"", b'{"settings":{},"settings":{}}', b'{"value":NaN}']
        for key in ("sourceSHA256", "markdownProtocolSHA256", "researchUseDecisionSHA256"):
            invalid.append(json.dumps({**protocol, key: "b" * 64}).encode())
        invalid.extend((json.dumps({**protocol, "settings": {**protocol["settings"], "extra": 1}}).encode(),
                        json.dumps({**protocol, "nistTrainingSource": {}}).encode()))
        for payload in invalid:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                fit._read_protocol(payload)

    def test_matched_initialization_does_not_change_external_rng(self):
        torch.manual_seed(100)
        before = torch.get_rng_state().clone()
        models, initial, receipt = fit.initialized_models(self.vocabulary)
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual(len(set(receipt["armSHA256"].values())), 1)
        for arm in fit.ARMS:
            self.assertEqual(models[arm].classifier.out_features, 97)
            self.assertEqual(fit._state_digest(models[arm].state_dict()), receipt["sha256"])
            self.assertEqual(set(initial), set(models[arm].state_dict()))
        with self.assertRaises(ValueError):
            fit.initialized_models(tuple(reversed(self.vocabulary)))

    def test_pretraining_head_selects_original_rows_and_reset_preserves_trunk(self):
        models, initial, _ = fit.initialized_models(self.vocabulary)
        model = models[fit.ARMS[0]]
        fit.install_ascii_head(model, self.vocabulary, initial)
        self.assertEqual(model.classifier.out_features, 62)
        for index, label in enumerate(fit.nist.LABELS):
            source = self.vocabulary.index(label)
            torch.testing.assert_close(model.classifier.weight[index], initial["classifier.weight"][source], rtol=0, atol=0)
            torch.testing.assert_close(model.classifier.bias[index], initial["classifier.bias"][source], rtol=0, atol=0)
        with torch.no_grad():
            model.classifier.weight.add_(100)
            model.projection.weight.add_(.25)
            model.convolution[2].running_mean.add_(.5)
        trunk = {key: value.clone() for key, value in model.state_dict().items() if not key.startswith("classifier.")}
        fit.reset_original_head(model, initial)
        self.assertEqual(model.classifier.out_features, 97)
        for key in ("classifier.weight", "classifier.bias"):
            self.assertTrue(torch.equal(model.state_dict()[key], initial[key]))
        for key, value in trunk.items():
            self.assertTrue(torch.equal(model.state_dict()[key], value))

    def test_replay_uses_exact_training64_per_label_eight_times(self):
        rows = fit.replay_row_indices(self.training)
        self.assertEqual(len(rows), 31744)
        for label_index, label in enumerate(fit.nist.LABELS):
            block = rows[label_index * 512:(label_index + 1) * 512]
            self.assertEqual(block, block[:64] * 8)
            self.assertEqual(len(set(block)), 64)
            self.assertEqual({self.training[index].label for index in block}, {label})
            self.assertEqual({self.training[index].writer for index in block}, set(self.writers))
        self.assertEqual(rows, fit.replay_row_indices(self.training))
        bad = tuple(replace(sample, writer="tst_UPV_W00") if index == rows[0] else sample
                    for index, sample in enumerate(self.training))
        with self.assertRaises(ValueError):
            fit.replay_row_indices(bad)
        with self.assertRaises(ValueError):
            fit.replay_row_indices(self.training[:-1])

    def test_shared_pretraining_plans_cover_exact_rows_and_change_by_epoch(self):
        plan = fit.pretrain_batch_plan(0)
        self.assertEqual(len(plan), 248)
        self.assertTrue(all(len(batch) == 128 for batch in plan))
        self.assertEqual(sorted(index for batch in plan for index in batch), list(range(31744)))
        self.assertEqual(plan, fit.pretrain_batch_plan(0))
        self.assertNotEqual(plan, fit.pretrain_batch_plan(1))
        for epoch in (True, -1, 5, .5):
            with self.assertRaises(ValueError):
                fit.pretrain_batch_plan(epoch)

    def nist_record(self):
        source = {"sample_id": "hsf_0/f0001_00/d0001_00/00000", "writer_id": "0001",
            "partition": "hsf_0", "template_id": "00", "form_id": "f0001_00", "field_id": "d0001_00",
            "image_index": 0, "split": "train", "label": "0", "label_byte_hex": "30", "label_raw_token": "30",
            "png_member": "by_write/hsf_0/f0001_00/d0001_00/d0001_00_00000.png",
            "png_sha256": "a" * 64, "cls_member": "1stEdition1995/data/by_write/hsf_0/f0001_00/d0001_00.cls",
            "cls_sha256": "b" * 64, "cls_label_line": 2, "decoded_raster_sha256": "c" * 64}
        return {"selectionIndex": 0, "sourceRow": source, "adaptedRasterSHA256": "d" * 64,
            "rasterByteOffset": 0, "rasterByteLength": 24576}

    def test_nist_metadata_retains_exact_original_identity_and_only_train_roles(self):
        record = self.nist_record()
        roles = {}
        self.assertEqual(fit._validate_nist_record(record, 0, roles), record["sourceRow"])
        self.assertEqual(roles, {"0001": "train"})
        invalid = []
        for key, value in (("split", "dev"), ("writer_id", "0002"), ("label", "1"),
                           ("image_index", True), ("cls_label_line", 3), ("cls_member", "by_write/hsf_0/f0002_00/d0002_00.cls")):
            invalid.append({**record, "sourceRow": {**record["sourceRow"], key: value}})
        invalid.extend(({**record, "selectionIndex": True}, {**record, "rasterByteOffset": 1},
                        {**record, "extra": 0}, {**record, "sourceRow": {**record["sourceRow"], "extra": 0}}))
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValueError):
                fit._validate_nist_record(value, 0, {})

    def test_nist_loader_rejects_wrong_receipt_before_raster_mapping(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            payload = b'{"productionEligible":true}'
            for name, value in (("receipt.json", payload), ("selection.jsonl", b""), ("rasters.bin", b"")):
                with (folder / name).open("xb") as stream:
                    stream.write(value)
            pins = {"receiptSHA256": fit._sha256(payload), "selectionJSONLSHA256": fit._sha256(b""), "rastersBinSHA256": fit._sha256(b"")}
            with self.assertRaises(ValueError):
                fit.load_nist_training_source(folder, pins)
            with self.assertRaises(ValueError):
                fit.load_nist_training_source(folder, {**pins, "receiptSHA256": "a" * 64})

    def test_tiny_real_training_update_matches_grid_draws_and_changes_parameters(self):
        models, _, _ = fit.initialized_models(self.vocabulary)
        images = torch.zeros((2, 1, 96, 256), dtype=torch.uint8)
        images[0, :, 20:70, 80:85] = 255
        images[1, :, 35:40, 60:180] = 255
        target = torch.tensor([0, 1], dtype=torch.long)
        receipts = []
        for arm in fit.ARMS:
            model = models[arm].train()
            before = fit._state_digest(model.state_dict())
            generator = torch.Generator().manual_seed(29)
            optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
            loss, pixels = fit._training_update(model, images, target, optimizer, generator)
            self.assertTrue(math.isfinite(loss))
            self.assertNotEqual(before, fit._state_digest(model.state_dict()))
            features, logits = model.eval()(images.float() / 255)
            self.assertEqual(tuple(features.shape), (2, 128))
            self.assertEqual(tuple(logits.shape), (2, 97))
            receipts.append((loss, pixels, generator.get_state().numpy().tobytes(), fit._state_digest(model.state_dict())))
        self.assertEqual(receipts[0], receipts[1])

    def test_training_batch_and_phase_count_guards(self):
        models, _, _ = fit.initialized_models(self.vocabulary)
        model = models[fit.ARMS[0]]
        images = torch.zeros((2, 1, 96, 256), dtype=torch.uint8)
        generator = torch.Generator().manual_seed(29)
        optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
        for bad in (images.float(), images[:, :, :-1], images[:, :, :, :-1]):
            with self.assertRaises(ValueError):
                fit._training_update(model, bad, torch.tensor([0, 1]), optimizer, generator)
        for targets in (torch.tensor([-1, 0]), torch.tensor([0, 97]), torch.tensor([0., 1.]), torch.tensor([0])):
            with self.assertRaises(ValueError):
                fit._training_update(model, images, targets, optimizer, generator)
        for phase in ("pretrain", "finetune", "other"):
            with self.assertRaises(ValueError):
                fit._train_phase(model, fit.ARMS[0], images, torch.tensor([0, 1]), ((),), phase)

    def test_unknown_feature_arm_and_research_decision_fail_closed(self):
        with self.assertRaises(ValueError):
            fit.load_training_feature_bundle(Path("/private/tmp/missing-broad-transfer-fit"), "unknown")
        with self.assertRaises(ValueError):
            fit._read_research_decision(b'{"localResearchFitAllowed":true,"commercialUseOrDerivedWeightShippingAllowed":true}')


if __name__ == "__main__":
    unittest.main()
