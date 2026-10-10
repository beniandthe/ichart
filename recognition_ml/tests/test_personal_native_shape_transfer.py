"""Synthetic source/count/initialization/gradient contracts; no real source fit."""
import copy
import io
from dataclasses import replace
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_native_shape_transfer as fit
from ichart_recognition_ml.research.uji_personal import Sample


class NativeShapeTransferTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2); torch.use_deterministic_algorithms(True)
        cls.vocabulary = tuple(sorted(tuple(fit.broad.nist.LABELS) + tuple(chr(0x100 + i) for i in range(35))))
        cls.records = tuple(Sample(f"{prefix}_UPV_W{writer:02d}", session, label, ())
            for prefix, count in (("trn", 40), ("tst", 20)) for writer in range(count)
            for session in (1, 2) for label in cls.vocabulary)
        cls.training, cls.writers, cls.development, cls.reserved = fit.select_training_samples(cls.records)

    def test_fixed_budget_original_helpers_and_source_task_boundary(self):
        contract = fit.frozen_protocol()
        self.assertEqual(contract["arms"], ["uji97ReplayPretrain", "hasy369NativePretrain"])
        self.assertEqual(contract["auxiliaryHeads"], [97, 369])
        self.assertEqual(97 * 327 + 25, 31744); self.assertEqual(369 * 86 + 10, 31744)
        self.assertEqual(5 * 248 + 30 * 32, contract["updatesPerArm"])
        self.assertIs(fit._train_phase, fit.broad._train_phase)
        self.assertIs(fit.pretrain_batch_plan, fit.broad.pretrain_batch_plan)
        self.assertIs(fit.reset_original_head, fit.broad.reset_original_head)
        self.assertFalse(contract["productionEligible"])

    def test_current_protocol_adapter_and_reused_helper_code_are_bound(self):
        identity = fit.code_identity()
        self.assertEqual(identity[fit.PROTOCOL_PATH], fit.PROTOCOL_DOCUMENT_SHA256)
        for path in ("recognition_ml/ichart_recognition_ml/research/personal_broad_transfer.py",
            "recognition_ml/ichart_recognition_ml/research/hasy_native_training_source.py", "personal_symbol_data.py"):
            self.assertIn(path, identity)

    def test_full97_replay_counts_extras_hash_order_and_cycles(self):
        replay = fit.replay_row_indices(self.training)
        self.assertEqual(len(replay), 31744); self.assertEqual(len(set(replay)), 6208)
        self.assertEqual(replay, fit.replay_row_indices(self.training))
        extras = set(sorted(self.vocabulary, key=lambda c: (fit._sha256(b"native-shape-transfer-v1\0" + c.encode()), c))[:25])
        offset = 0
        for label in self.vocabulary:
            count = 327 + (label in extras); block = replay[offset:offset + count]; offset += count
            expected = sorted((i for i, s in enumerate(self.training) if s.label == label),
                key=lambda i: (fit._sha256(b"native-shape-transfer-v1\0" + self.training[i].identity.encode()), self.training[i].identity))
            self.assertEqual(block, tuple(expected[n % 64] for n in range(count)))
            self.assertEqual(len(set(block)), 64); self.assertEqual({self.training[i].writer for i in block}, set(self.writers))
            self.assertEqual({self.training[i].label for i in block}, {label})
        bad = [self.training[:-1], tuple(reversed(self.training)), self.training[:-1] + (self.training[0],),
            tuple(replace(s, session=True) if n == 0 else s for n, s in enumerate(self.training)),
            tuple(replace(s, writer=self.reserved[0]) if n == 0 else s for n, s in enumerate(self.training))]
        for sources in bad:
            with self.assertRaises(ValueError): fit.replay_row_indices(sources)

    def test_independent_seeded_auxiliary_heads_equal_trunks_and_external_rng(self):
        torch.manual_seed(73); before = torch.get_rng_state().clone()
        models, initial, receipt = fit.initialized_models(self.vocabulary)
        self.assertTrue(torch.equal(before, torch.get_rng_state())); self.assertEqual(len(set(receipt["armSHA256"].values())), 1)
        trunks = []
        for arm, count in zip(fit.ARMS, (97, 369)):
            state = fit.install_auxiliary_head(models[arm], count)
            with torch.random.fork_rng(devices=[]):
                torch.manual_seed(29); expected = torch.nn.Linear(128, count)
            self.assertTrue(all(torch.equal(state[k], expected.state_dict()[k]) for k in state))
            self.assertEqual(models[arm].classifier.out_features, count)
            trunks.append({k: v for k, v in models[arm].state_dict().items() if not k.startswith("classifier.")})
        self.assertTrue(all(torch.equal(trunks[0][k], trunks[1][k]) for k in trunks[0]))
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        for count in (True, 62, 368):
            with self.assertRaises(ValueError): fit.install_auxiliary_head(models[fit.ARMS[0]], count)
        with self.assertRaises(ValueError): fit.initialized_models(tuple(reversed(self.vocabulary)))

    def test_nonzero_real_gradient_auxiliary_reset_preserves_learned_trunk_bn_and_matching_draws(self):
        models, initial, _ = fit.initialized_models(self.vocabulary)
        images = torch.zeros(2, 1, 96, 256, dtype=torch.uint8); images[0, :, 20:70, 80:85] = 255; images[1, :, 35:40, 60:180] = 255
        targets = torch.tensor([0, 1]); traces = []
        for arm, count in zip(fit.ARMS, (97, 369)):
            model = models[arm]; fit.install_auxiliary_head(model, count); model.train()
            before = {k: v.clone() for k, v in model.state_dict().items()}; generator = torch.Generator().manual_seed(29)
            optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
            loss, augmented = fit.broad._training_update(model, images, targets, optimizer, generator)
            self.assertTrue(math.isfinite(loss))
            self.assertTrue(all(p.grad is not None and torch.isfinite(p.grad).all() for p in model.parameters()))
            self.assertFalse(torch.equal(before["projection.weight"], model.state_dict()["projection.weight"]))
            self.assertFalse(torch.equal(before["classifier.weight"], model.state_dict()["classifier.weight"]))
            self.assertFalse(torch.equal(before["convolution.2.running_mean"], model.state_dict()["convolution.2.running_mean"]))
            trunk = {k: v.clone() for k, v in model.state_dict().items() if not k.startswith("classifier.")}
            fit.reset_original_head(model, initial)
            self.assertTrue(all(torch.equal(v, model.state_dict()[k]) for k, v in trunk.items()))
            self.assertTrue(all(torch.equal(model.state_dict()[k], initial[k]) for k in ("classifier.weight", "classifier.bias")))
            features, logits = model.eval()(images.float() / 255)
            self.assertEqual(tuple(features.shape), (2, 128)); self.assertEqual(tuple(logits.shape), (2, 97))
            traces.append((augmented, generator.get_state().numpy().tobytes()))
        self.assertEqual(traces[0], traces[1])

    def test_shared_pretraining_and_finetuning_plans_have_complete_roles(self):
        for epoch in range(5):
            plan = fit.pretrain_batch_plan(epoch); self.assertEqual(len(plan), 248)
            self.assertTrue(all(len(b) == 128 for b in plan)); self.assertEqual(sorted(i for b in plan for i in b), list(range(31744)))
        plan = fit.epoch_batch_plan(self.records, 0)
        self.assertEqual(len(plan), 32); self.assertTrue(all(len(b) == 194 for b in plan))
        self.assertEqual(sorted(i for b in plan for i in b), list(range(6208)))
        self.assertEqual(plan, fit.epoch_batch_plan(self.records, 0))
        with self.assertRaises(ValueError): fit._train_phase(None, fit.ARMS[0], None, torch.zeros(2, dtype=torch.long), ((),), "pretrain")

    def histories(self):
        result = {}
        for arm in fit.ARMS:
            result[arm] = {}
            for phase, epochs, updates, samples in (("pretrain", 5, 248, 31744), ("finetune", 30, 32, 6208)):
                result[arm][phase] = [{"phase": phase, "epoch": e + 1, "samples": samples, "updates": updates,
                    "learningRate": .001 * (1 + math.cos(math.pi * e / epochs)) / 2, "crossEntropyLoss": 1.,
                    "batchPlanSHA256": "a" * 64, "augmentationGeneratorTraceSHA256": "b" * 64,
                    "augmentationInputsSHA256": "c" * 64} for e in range(epochs)]
        return result

    def test_matching_all2200updates_traces_finite_loss_and_no_early_checkpoint_choice(self):
        histories = self.histories(); fit.validate_matching(histories)
        self.assertEqual(sum(r["updates"] for phase in histories[fit.ARMS[0]].values() for r in phase), 2200)
        changed = copy.deepcopy(histories); changed[fit.ARMS[1]]["pretrain"][0]["augmentationInputsSHA256"] = "d" * 64
        fit.validate_matching(changed)  # Native/control pixels may differ.
        for phase, field, value in (("finetune", "augmentationInputsSHA256", "d" * 64), ("pretrain", "augmentationGeneratorTraceSHA256", "d" * 64),
            ("finetune", "crossEntropyLoss", float("nan")), ("pretrain", "updates", 247), ("finetune", "learningRate", .1)):
            changed = copy.deepcopy(histories); changed[fit.ARMS[1]][phase][0][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): fit.validate_matching(changed)
        changed = copy.deepcopy(histories); changed[fit.ARMS[1]]["finetune"].pop()
        with self.assertRaises(ValueError): fit.validate_matching(changed)
        with self.assertRaises(ValueError): fit.validate_matching(histories, {"pretrainBatchPlanSHA256": ["d" * 64] * 5, "epochBatchPlanSHA256": ["a" * 64] * 30})

    def test_receipt_digest_gate_and_unknown_feature_arm_fail_before_source_open(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve(); (output / "fit-receipt.json").write_bytes(b"{}")
            with self.assertRaisesRegex(ValueError, "receipt SHA"):
                fit.load_fitted_models(output, "0" * 64)
            with self.assertRaisesRegex(ValueError, "receipt SHA"):
                fit.load_training_feature_bundle(output, fit.ARMS[0], None, "0" * 64)
        with self.assertRaisesRegex(ValueError, "Unknown"):
            fit.load_training_feature_bundle(Path("/private/tmp/missing-native-fit"), "unknown")

    def test_synthetic_final_checkpoint_reload_hash_state_and_metadata_tampering(self):
        models, _, initial = fit.initialized_models(self.vocabulary); plan = {"initialState": initial}
        receipt = {"vocabulary": list(self.vocabulary), "fitPlanSHA256": fit._sha256(fit._json_bytes(plan)), "initialState": initial,
            "weightFiles": {a: f"weights/{a}.pt" for a in fit.ARMS}, "weightsSHA256": {}, "finalStateSHA256": {a: fit._state_digest(m.state_dict()) for a, m in models.items()}}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve(); (output / "weights").mkdir()
            for arm in fit.ARMS:
                data = fit._checkpoint(models[arm], arm, "finetune", self.vocabulary, plan)
                (output / receipt["weightFiles"][arm]).write_bytes(data); receipt["weightsSHA256"][arm] = fit._sha256(data)
            # Synthetic checkpoint fixture only, not a claimed 2,200-update fit.
            with patch.object(fit, "_load_fit_receipt", return_value=receipt):
                loaded, _ = fit.load_fitted_models(output)
                self.assertTrue(all(fit._state_digest(loaded[a].state_dict()) == receipt["finalStateSHA256"][a] for a in fit.ARMS))
                path = output / receipt["weightFiles"][fit.ARMS[0]]; data = path.read_bytes(); path.write_bytes(data + b"tamper")
                with self.assertRaisesRegex(ValueError, "checkpoint bytes"): fit.load_fitted_models(output)
                path.write_bytes(data); receipt["finalStateSHA256"][fit.ARMS[0]] = "0" * 64
                with self.assertRaisesRegex(ValueError, "state changed"): fit.load_fitted_models(output)
                receipt["finalStateSHA256"][fit.ARMS[0]] = fit._state_digest(models[fit.ARMS[0]].state_dict())
                value = torch.load(io.BytesIO(data), map_location="cpu", weights_only=True); value["finalEpoch"] = 29
                stream = io.BytesIO(); torch.save(value, stream); changed = stream.getvalue(); path.write_bytes(changed)
                receipt["weightsSHA256"][fit.ARMS[0]] = fit._sha256(changed)
                with self.assertRaisesRegex(ValueError, "metadata/schema"): fit.load_fitted_models(output)


if __name__ == "__main__": unittest.main()
