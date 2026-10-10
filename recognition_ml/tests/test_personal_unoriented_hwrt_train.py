"""Synthetic integrity tests, not a real HWRT/UJI fit or quality evaluation."""
import copy
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_unoriented_hwrt_train as train


def vocabulary():
    return tuple(f"old-{i:02}" for i in range(97)) + train.old.NOVEL_LABELS


def synthetic_fields(count=4):
    generator = torch.Generator().manual_seed(81)
    fields = torch.zeros((count, 5, 96, 256), dtype=torch.float32)
    fields[:, 0] = torch.rand((count, 96, 256), generator=generator)
    fields[:, 1] = .8; fields[:, 2] = .2; fields[:, 3] = .2
    fields[:, 4] = torch.rand((count, 96, 256), generator=generator)
    return fields


def synthetic_receipt():
    ledger = {"epochs": 30, "updates": 1530, "exposures": 195840,
        "scheduleSHA256": train.SENTINELS["scheduleSHA256"], "batchOrderStreamSHA256": train.SENTINELS["scheduleSHA256"],
        "augmentationDrawStreamSHA256": train.SENTINELS["augmentationDrawStreamSHA256"],
        "augmentedFeatureStreamSHA256": "1" * 64, "actualForwardInputStreamSHA256": "1" * 64}
    return {"version": train.VERSION, "scope": train.SCOPE, "arms": list(train.ARMS), "fieldVersion": train.field.VERSION,
        "modelVersion": train.field.MODEL_VERSION, "labelCount": 102, "vocabulary": list(vocabulary()),
        "vocabularySHA256": train.old._vocabulary_sha256(vocabulary()), "protocolSHA256": train.PROTOCOL_SHA256,
        "codeSHA256": {}, "dataReceiptSHA256": "2" * 64, "dataArtifactsSHA256": {"fields.npy": "3" * 64, "training.json": "4" * 64},
        "runtime": train._runtime_contract(), "recipe": train.RECIPE, "initialStateSHA256": "5" * 64,
        "initialArmStateSHA256": {a: "5" * 64 for a in train.ARMS}, "trainingPlanPath": "training-plan.json", "trainingPlanSHA256": "6" * 64,
        "augmentationLedger": {a: copy.deepcopy(ledger) for a in train.ARMS},
        "trainingHistory": {a: [{"epoch": i, "meanLoss": 1.0, "correct": 1, "learningRate": .001} for i in range(1, 31)] for a in train.ARMS},
        "weightFiles": {a: f"weights/{a}.pt" for a in train.ARMS}, "weightsSHA256": {a: "7" * 64 for a in train.ARMS},
        "finalStateSHA256": {"rasterControl": train.SENTINELS["rasterControlStateSHA256"], "strokeField": "8" * 64},
        "selection": "final-epoch-only", "reproducibilitySentinels": train.SENTINELS}


class NeutralTrainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(4); torch.use_deterministic_algorithms(True)

    def test_initial_state_matches_frozen_fresh_initializer_and_preserves_rng(self):
        before = torch.get_rng_state().clone(); models, digest = train.initialized_models()
        old_models, old_digest = train.old.initialized_models()
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual(digest, old_digest)
        for arm in train.ARMS:
            self.assertIsInstance(models[arm], train.field.PersonalUnorientedStrokeFieldEncoder)
            self.assertEqual(models[arm].arm, arm)
            self.assertEqual(train._state_digest(models[arm].state_dict()), train._state_digest(old_models[arm].state_dict()))
        with torch.no_grad():
            next(models["strokeField"].parameters()).add_(1)
        self.assertEqual(train._state_digest(models["rasterControl"].state_dict()), digest)

    def test_two_nonzero_steps_and_bit_equal_control_to_old_augmenter(self):
        models, initial = train.initialized_models(); old_models, _ = train.old.initialized_models()
        optim, _ = train.old._optimizers(models); old_optim, _ = train.old._optimizers(old_models)
        generator = torch.Generator().manual_seed(29); source = synthetic_fields(); targets = torch.tensor([0, 1, 97, 101])
        before = {a: {n: t.clone() for n, t in m.state_dict().items()} for a, m in models.items()}
        source_digest = train._tensor_sha256(source)
        for _ in range(2):
            draws = train.field.sample_affine_draws(4, generator)
            neutral = train.field.augment_unoriented_stroke_fields(source, draws)
            signed = train.old.field.augment_stroke_fields(source, draws)
            self.assertTrue(torch.equal(neutral[:, 0], signed[:, 0]))
            reports = train.old._paired_step(models, optim, neutral, targets)
            train.old._paired_step(old_models, old_optim, signed, targets)
            self.assertEqual({r["actualInputSHA256"] for r in reports.values()}, {train._tensor_sha256(neutral)})
            self.assertTrue(all(np.isfinite(r["loss"]) for r in reports.values()))
        self.assertEqual(train._tensor_sha256(source), source_digest)
        self.assertEqual(train._state_digest(models["rasterControl"].state_dict()), train._state_digest(old_models["rasterControl"].state_dict()))
        self.assertNotEqual(train._state_digest(models["strokeField"].state_dict()), train._state_digest(old_models["strokeField"].state_dict()))
        for arm in train.ARMS:
            self.assertNotEqual(train._state_digest(models[arm].state_dict()), initial)
            for block in ("convolution", "projection", "classifier"):
                self.assertTrue(any(not torch.equal(t, before[arm][n]) for n, t in models[arm].named_parameters() if n.startswith(block)))

    def test_new_checkpoints_reload_exactly_and_reject_old_or_nonfinite_state(self):
        models, _ = train.initialized_models(); arm = "strokeField"; vocab_sha = train.old._vocabulary_sha256(vocabulary())
        payload = train.checkpoint_bytes(models[arm], arm, vocab_sha)
        restored = train.load_checkpoint(payload, arm, vocab_sha)
        self.assertEqual(train._state_digest(restored.state_dict()), train._state_digest(models[arm].state_dict()))
        old_model = train.old.initialized_models()[0][arm]
        with self.assertRaisesRegex(ValueError, "Neutral checkpoint identity"):
            train.load_checkpoint(train.old.checkpoint_bytes(old_model, arm, vocab_sha), arm, vocab_sha)
        with self.assertRaisesRegex(ValueError, "model identity"):
            train.checkpoint_bytes(old_model, arm, vocab_sha)
        value = torch.load(io.BytesIO(payload), weights_only=True)
        value["stateDict"]["classifier.weight"][0, 0] = float("nan")
        stream = io.BytesIO(); torch.save(value, stream)
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            train.load_checkpoint(stream.getvalue(), arm, vocab_sha)

    def test_real_sentinel_constants_and_mismatch_stops(self):
        self.assertEqual(train.SENTINELS["rasterControlStateSHA256"], "ca97f42d345c3e7e777ef92412db30e7a26930f0b2f8411873e5db8505970c99")
        self.assertEqual(train.SENTINELS["scheduleSHA256"], "d1ef91c13bb4477de88c57510851149177e528858f0e2bfcf69643b8c062d6ed")
        self.assertEqual(train.SENTINELS["augmentationDrawStreamSHA256"], "1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc")
        receipt = synthetic_receipt(); train.validate_sentinels(receipt["finalStateSHA256"], receipt["augmentationLedger"])
        bad = copy.deepcopy(receipt["finalStateSHA256"]); bad["rasterControl"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "state sentinel"):
            train.validate_sentinels(bad, receipt["augmentationLedger"])
        for key in ("scheduleSHA256", "augmentationDrawStreamSHA256"):
            bad = copy.deepcopy(receipt["augmentationLedger"]); bad["strokeField"][key] = "0" * 64
            with self.assertRaisesRegex(ValueError, "draw sentinel"):
                train.validate_sentinels(receipt["finalStateSHA256"], bad)

    def test_reused_planner_counts_all_sources_and_new_guard_rejects_different_schedule(self):
        vocab = vocabulary(); rows = [{"source": "uji", "label": label} for label in vocab[:97] for _ in range(64)]
        rows += [{"source": "hwrt", "label": label} for label in train.old.NOVEL_LABELS for _ in range(train.old.NOVEL_COUNTS[label])]
        value = train.old.build_training_plan(rows, vocab)
        self.assertEqual(value, train.old.build_training_plan(rows, vocab))
        self.assertEqual(len(rows), 10073); self.assertEqual(len(value["epochs"]), 30)
        self.assertEqual(sum(e["exposures"] for e in value["epochs"]), 195840)
        self.assertEqual(sum(e["updates"] for e in value["epochs"]), 1530)
        self.assertEqual(value["oldRowMultiplicity"], {"minimum": 30, "maximum": 30})
        self.assertTrue(all(c["uniqueRowsSeen"] == c["availableRows"] for c in value["novelPoolCoverage"].values()))
        with self.assertRaisesRegex(ValueError, "schedule sentinel"):
            train.build_training_plan(rows, vocab)

    def test_new_receipt_rejects_old_identity_incomplete_counts_and_bad_history(self):
        receipt = synthetic_receipt(); train._validate_fit_receipt(receipt, code={})
        for key, value in (("version", train.old.VERSION), ("fieldVersion", train.old.field.VERSION),
                           ("modelVersion", train.old.field.MODEL_VERSION), ("protocolSHA256", train.old.PROTOCOL_SHA256)):
            bad = copy.deepcopy(receipt); bad[key] = value
            with self.assertRaises(ValueError):
                train._validate_fit_receipt(bad, code={})
        bad = copy.deepcopy(receipt); bad["augmentationLedger"]["strokeField"]["updates"] = 1529
        with self.assertRaisesRegex(ValueError, "count ledger"):
            train._validate_fit_receipt(bad)
        bad = copy.deepcopy(receipt); bad["trainingHistory"]["strokeField"].pop()
        with self.assertRaisesRegex(ValueError, "history incomplete"):
            train._validate_fit_receipt(bad)

    def test_blind_loader_reads_no_data_truth_and_authenticates_snapshot_bytes(self):
        # Synthetic loader fixture: only the historical *result* sentinel is
        # bypassed; its strict production validation has a separate test above.
        models, initial = train.initialized_models(); receipt = synthetic_receipt()
        with tempfile.TemporaryDirectory() as td:
            directory = Path(td).resolve(); (directory / "weights").mkdir()
            protocol_bytes = (train.ROOT / train.PROTOCOL).read_bytes()
            plan_bytes = train.canonical({"version": train.PLAN_VERSION})
            snapshot = b"synthetic-executed-code"; code = {"synthetic-source.py": train._sha256(snapshot)}
            train.old._write_exclusive(directory / "executed-code" / "synthetic-source.py", snapshot)
            train.old._write_exclusive(directory / "frozen-protocol.md", protocol_bytes)
            train.old._write_exclusive(directory / "training-plan.json", plan_bytes)
            receipt.update({"codeSHA256": code, "initialStateSHA256": initial,
                            "initialArmStateSHA256": {a: initial for a in train.ARMS}, "trainingPlanSHA256": train._sha256(plan_bytes)})
            for arm in train.ARMS:
                with torch.no_grad():
                    next(models[arm].parameters()).add_(.001)
                payload = train.checkpoint_bytes(models[arm], arm, receipt["vocabularySHA256"])
                train.old._write_exclusive(directory / "weights" / f"{arm}.pt", payload)
                receipt["weightsSHA256"][arm] = train._sha256(payload)
                receipt["finalStateSHA256"][arm] = train._state_digest(models[arm].state_dict())
            receipt_bytes = train.canonical(receipt); train.old._write_exclusive(directory / "fit-receipt.json", receipt_bytes)
            for decoy in ("truth.json", "training.json", "fields.npy", "development-inputs.json"):
                train.old._write_exclusive(directory / decoy, b"NEVER-READ")
            original_read = train._read; calls = []
            def guarded(path, **kwargs):
                calls.append(Path(path).name)
                self.assertNotIn(Path(path).name, {"truth.json", "training.json", "fields.npy", "development-inputs.json"})
                return original_read(path, **kwargs)
            with patch.object(train, "code_identity", return_value=code), patch.object(train, "validate_sentinels"), \
                 patch.object(train, "_read", side_effect=guarded):
                loaded, _ = train.load_fitted_models(directory, train._sha256(receipt_bytes))
                self.assertTrue(all(not m.training for m in loaded.values()))
                self.assertEqual({a: train._state_digest(m.state_dict()) for a, m in loaded.items()}, receipt["finalStateSHA256"])
                with self.assertRaisesRegex(ValueError, "receipt SHA"):
                    train.load_fitted_models(directory, "0" * 64)
                (directory / "executed-code" / "synthetic-source.py").write_bytes(b"tampered")
                with self.assertRaisesRegex(ValueError, "code snapshot"):
                    train.load_fitted_models(directory, train._sha256(receipt_bytes))

    def test_failed_control_sentinel_cannot_publish_weights_or_success_receipt(self):
        # Orchestration-only fixture; training/data helpers are stubbed, and
        # the real sentinel rejects the fresh (unfitted) control before save.
        fixture = synthetic_receipt(); models, initial = train.initialized_models()
        protocol = train.ROOT / train.PROTOCOL
        code = {train.PROTOCOL: train.PROTOCOL_SHA256}
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve(); data_dir = root / "data"; data_dir.mkdir(); output = root / "fit"
            artifacts = {}
            for name, payload in (("fields.npy", b"synthetic fields"), ("training.json", b"synthetic metadata")):
                train.old._write_exclusive(data_dir / name, payload)
                artifacts[name] = {"bytes": len(payload), "sha256": train._sha256(payload)}
            data_receipt = {"artifacts": artifacts}
            train.old._write_exclusive(data_dir / "data-receipt.json", train.canonical(data_receipt))
            for decoy in ("truth.json", "inputs.json"):
                train.old._write_exclusive(data_dir / decoy, b"DECOY")
            plan = {"version": train.PLAN_VERSION, "vocabularySHA256": fixture["vocabularySHA256"]}
            with patch.object(train, "code_identity", return_value=code), \
                 patch.object(train.data, "load_training", return_value=(None, {}, data_receipt)), \
                 patch.object(train, "_validate_training", return_value=([], vocabulary())), \
                 patch.object(train, "build_training_plan", return_value=plan), \
                 patch.object(train, "initialized_models", return_value=(models, initial)), \
                 patch.object(train, "train_models", return_value=(fixture["trainingHistory"], fixture["augmentationLedger"])), \
                 patch.object(train, "checkpoint_bytes", side_effect=AssertionError("Saved before sentinel")):
                with self.assertRaisesRegex(ValueError, "control state sentinel"):
                    train.fit(data_dir, protocol, output)
                self.assertTrue((output / "training-plan.json").is_file())
                self.assertFalse((output / "fit-receipt.json").exists())
                self.assertEqual(list((output / "weights").iterdir()), [])
                with self.assertRaisesRegex(ValueError, "resume is forbidden"):
                    train.fit(data_dir, protocol, output)


if __name__ == "__main__":
    unittest.main()
