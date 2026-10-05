"""Synthetic checks for the fixed HWRT stroke-field trainer; no corpus fit."""

import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_hwrt_stroke_train as train
from ichart_recognition_ml.research import personal_stroke_field as field


def synthetic_rows():
    old = tuple(f"label-{index:02d}" for index in range(97))
    vocabulary = old + train.NOVEL_LABELS
    rows = []
    for label in old:
        rows.extend({"source": "uji", "label": label} for _ in range(64))
    for label in train.NOVEL_LABELS:
        rows.extend({"source": "hwrt", "label": label} for _ in range(train.NOVEL_COUNTS[label]))
    return rows, vocabulary


def changed_models():
    models, initial = train.initialized_models()
    for offset, arm in enumerate(train.ARMS, start=1):
        with torch.no_grad():
            next(models[arm].parameters()).add_(offset / 1000)
    return models, initial


def receipt_for(models, initial, plan_sha, weights_sha):
    final = {arm: train._state_digest(models[arm].state_dict()) for arm in train.ARMS}
    ledger = {
        "epochs": train.EPOCHS,
        "updates": train.UPDATES_PER_ARM,
        "exposures": train.EXPOSURES_PER_ARM,
        "scheduleSHA256": "1" * 64,
        "batchOrderStreamSHA256": "2" * 64,
        "augmentationDrawStreamSHA256": "3" * 64,
        "augmentedFeatureStreamSHA256": "4" * 64,
        "actualForwardInputStreamSHA256": "4" * 64,
    }
    return {
        "version": train.VERSION,
        "scope": train.SCOPE,
        "arms": list(train.ARMS),
        "fieldVersion": field.VERSION,
        "modelVersion": field.MODEL_VERSION,
        "labelCount": train.LABEL_COUNT,
        "vocabulary": [f"label-{index}" for index in range(train.LABEL_COUNT)],
        "vocabularySHA256": train._vocabulary_sha256([f"label-{index}" for index in range(train.LABEL_COUNT)]),
        "protocolSHA256": train.PROTOCOL_SHA256,
        "codeSHA256": {},
        "dataReceiptSHA256": "5" * 64,
        "dataArtifactsSHA256": {"fields.npy": "6" * 64, "training.json": "7" * 64},
        "runtime": train._runtime_contract(),
        "recipe": train.RECIPE,
        "initialStateSHA256": initial,
        "initialArmStateSHA256": {arm: initial for arm in train.ARMS},
        "trainingPlanPath": "training-plan.json",
        "trainingPlanSHA256": plan_sha,
        "augmentationLedger": {arm: copy.deepcopy(ledger) for arm in train.ARMS},
        "trainingHistory": {
            arm: [{"epoch": epoch, "meanLoss": 1.0, "correct": 0, "learningRate": 0.0}
                  for epoch in range(1, train.EPOCHS + 1)]
            for arm in train.ARMS
        },
        "weightFiles": {arm: f"weights/{arm}.pt" for arm in train.ARMS},
        "weightsSHA256": weights_sha,
        "finalStateSHA256": final,
        "selection": "final-epoch-only",
    }


class HWRTStrokeFieldTrainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(4)
        torch.use_deterministic_algorithms(True)

    def test_encoder_accepts_exactly_97_or_102_labels_and_matched_initial_state(self):
        before = torch.get_rng_state().clone()
        models, digest = train.initialized_models()
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual({model.label_count for model in models.values()}, {102})
        self.assertEqual({train._state_digest(model.state_dict()) for model in models.values()}, {digest})
        batch = torch.zeros((2, 5, 96, 256), dtype=torch.float32)
        for count in (97, 102):
            embedding, logits = field.PersonalStrokeFieldEncoder(count, "strokeField").eval()(batch)
            self.assertEqual(embedding.shape, (2, 128))
            self.assertEqual(logits.shape, (2, count))
        for count in (0, 96, 98, 101, 103):
            with self.assertRaisesRegex(ValueError, "exactly one"):
                field.PersonalStrokeFieldEncoder(count, "strokeField")

    def test_complete_schedule_is_deterministic_balanced_and_exhausts_every_novel_pool(self):
        rows, vocabulary = synthetic_rows()
        first = train.build_training_plan(rows, vocabulary)
        second = train.build_training_plan(rows, vocabulary)
        self.assertEqual(canonical_json_bytes(first), canonical_json_bytes(second))
        self.assertEqual(len(first["epochs"]), 30)
        self.assertEqual(sum(epoch["exposures"] for epoch in first["epochs"]), 195_840)
        self.assertEqual(sum(epoch["updates"] for epoch in first["epochs"]), 1_530)
        for epoch in first["epochs"]:
            counts = {label: 0 for label in vocabulary}
            for index in epoch["rowIndices"]:
                counts[rows[index]["label"]] += 1
            self.assertEqual(set(counts.values()), {64})
            self.assertEqual(len(epoch["rowIndices"]), 6_528)
        expected_shuffles = {"+": 24, "/": 5, "#": 2, "ø": 3, "△": 2}
        for label, values in first["novelPoolCoverage"].items():
            self.assertEqual(values["uniqueRowsSeen"], values["availableRows"])
            self.assertEqual(values["exposures"], 1_920)
            self.assertEqual(values["shuffleCount"], expected_shuffles[label])
        self.assertEqual(first["oldRowMultiplicity"], {"minimum": 30, "maximum": 30})

    def test_one_real_paired_step_uses_identical_input_and_control_masks_auxiliary_planes(self):
        generator = torch.Generator().manual_seed(701)
        inputs = torch.rand((4, 5, 96, 256), generator=generator)
        original = inputs.clone()
        targets = torch.tensor([0, 1, 2, 3], dtype=torch.long)
        models, initial = train.initialized_models()
        optimizers, _ = train._optimizers(models)
        reports = train._paired_step(models, optimizers, inputs, targets)
        self.assertEqual({reports[arm]["actualInputSHA256"] for arm in train.ARMS}, {train._tensor_sha256(inputs)})
        torch.testing.assert_close(inputs, original, rtol=0, atol=0)
        for arm in train.ARMS:
            self.assertTrue(np.isfinite(reports[arm]["loss"]))
            self.assertNotEqual(train._state_digest(models[arm].state_dict()), initial)
        control = field.PersonalStrokeFieldEncoder(102, "rasterControl").eval()
        candidate = field.PersonalStrokeFieldEncoder(102, "strokeField").eval()
        candidate.load_state_dict(control.state_dict(), strict=True)
        changed = inputs.clone()
        changed[:, 1:] = 1.0 - changed[:, 1:]
        with torch.no_grad():
            control_a = control(inputs)[1]
            control_b = control(changed)[1]
            candidate_a = candidate(inputs)[1]
            candidate_b = candidate(changed)[1]
        torch.testing.assert_close(control_a, control_b, rtol=0, atol=0)
        self.assertFalse(torch.equal(candidate_a, candidate_b))

    def test_checkpoint_roundtrip_requires_arm_vocabulary_and_finite_complete_state(self):
        models, _ = changed_models()
        vocabulary_sha = "a" * 64
        for arm in train.ARMS:
            payload = train.checkpoint_bytes(models[arm], arm, vocabulary_sha)
            restored = train.load_checkpoint(payload, arm, vocabulary_sha)
            self.assertEqual(train._state_digest(restored.state_dict()), train._state_digest(models[arm].state_dict()))
            other = next(candidate for candidate in train.ARMS if candidate != arm)
            with self.assertRaisesRegex(ValueError, "identity"):
                train.load_checkpoint(payload, other, vocabulary_sha)
            with self.assertRaisesRegex(ValueError, "identity"):
                train.load_checkpoint(payload, arm, "b" * 64)
        with torch.no_grad():
            next(models["strokeField"].parameters()).fill_(float("nan"))
        payload = train.checkpoint_bytes(models["strokeField"], "strokeField", vocabulary_sha)
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            train.load_checkpoint(payload, "strokeField", vocabulary_sha)

    def test_receipt_rejects_missing_arm_epoch_update_and_unchanged_final_state(self):
        models, initial = changed_models()
        receipt = receipt_for(models, initial, "8" * 64, {arm: "9" * 64 for arm in train.ARMS})
        train._validate_fit_receipt(receipt, code={})
        missing = copy.deepcopy(receipt)
        del missing["weightsSHA256"]["strokeField"]
        with self.assertRaisesRegex(ValueError, "artifact"):
            train._validate_fit_receipt(missing, code={})
        epoch = copy.deepcopy(receipt)
        epoch["trainingHistory"]["rasterControl"].pop()
        with self.assertRaisesRegex(ValueError, "history"):
            train._validate_fit_receipt(epoch, code={})
        update = copy.deepcopy(receipt)
        update["augmentationLedger"]["strokeField"]["updates"] = 1_529
        with self.assertRaisesRegex(ValueError, "ledger"):
            train._validate_fit_receipt(update, code={})
        both_updates = copy.deepcopy(receipt)
        for arm in train.ARMS:
            both_updates["augmentationLedger"][arm]["updates"] = 1_529
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            train._validate_fit_receipt(both_updates, code={})
        unchanged = copy.deepcopy(receipt)
        unchanged["finalStateSHA256"]["strokeField"] = initial
        with self.assertRaisesRegex(ValueError, "remained initial"):
            train._validate_fit_receipt(unchanged, code={})

    def test_final_loader_requires_both_checkpoints_and_never_opens_data_or_truth(self):
        models, initial = changed_models()
        vocabulary = [f"label-{index}" for index in range(102)]
        vocabulary_sha = train._vocabulary_sha256(vocabulary)
        plan = canonical_json_bytes({"synthetic": True})
        payloads = {arm: train.checkpoint_bytes(models[arm], arm, vocabulary_sha) for arm in train.ARMS}
        weights = {arm: train._sha256(payload) for arm, payload in payloads.items()}
        receipt = receipt_for(models, initial, train._sha256(plan), weights)
        receipt["vocabulary"] = vocabulary
        receipt["vocabularySHA256"] = vocabulary_sha
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            directory = Path(temporary).resolve()
            (directory / "weights").mkdir()
            (directory / "frozen-protocol.md").write_bytes((train.ROOT / train.PROTOCOL).read_bytes())
            (directory / "training-plan.json").write_bytes(plan)
            for arm, payload in payloads.items():
                (directory / "weights" / f"{arm}.pt").write_bytes(payload)
            receipt_bytes = canonical_json_bytes(receipt)
            (directory / "fit-receipt.json").write_bytes(receipt_bytes)
            original = train._read
            opened = []

            def guarded(path, **kwargs):
                opened.append(str(path))
                self.assertNotIn("truth", str(path).lower())
                self.assertNotIn("development", str(path).lower())
                self.assertNotIn("fields.npy", str(path).lower())
                return original(path, **kwargs)

            with patch.object(train, "code_identity", return_value={}), patch.object(train, "_read", side_effect=guarded):
                loaded, validated = train.load_fitted_models(directory, train._sha256(receipt_bytes))
            self.assertEqual(set(loaded), set(train.ARMS))
            self.assertEqual(validated, receipt)
            self.assertTrue(all(not model.training for model in loaded.values()))
            (directory / "weights" / "strokeField.pt").unlink()
            with patch.object(train, "code_identity", return_value={}):
                with self.assertRaisesRegex(ValueError, "regular file"):
                    train.load_fitted_models(directory, train._sha256(receipt_bytes))

    def test_large_training_field_snapshot_streams_above_two_gib_and_never_opens_truth(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            directory = Path(temporary).resolve()
            fields = directory / "fields.npy"
            with fields.open("wb") as stream:
                stream.truncate(2 * 1024 * 1024 * 1024 + 1)
            (directory / "training.json").write_bytes(b"x")
            receipt = {
                "artifacts": {
                    "fields.npy": {"bytes": fields.stat().st_size, "sha256": "a" * 64},
                    "training.json": {"bytes": 1, "sha256": "b" * 64},
                    "development-truth.json": {"bytes": 999, "sha256": "c" * 64},
                }
            }

            def streamed(path, **_kwargs):
                self.assertNotIn("truth", Path(path).name)
                return "a" * 64 if Path(path).name == "fields.npy" else "b" * 64

            with patch.object(train, "_file_sha256", side_effect=streamed) as hashing:
                snapshot = train._snapshot_data(directory, receipt, b"receipt")
            self.assertEqual([call.args[0].name for call in hashing.call_args_list], ["fields.npy", "training.json"])
            self.assertEqual(set(path.name for path in snapshot), {"data-receipt.json", "fields.npy", "training.json"})

    def test_failed_training_publishes_plan_but_no_receipt_and_cannot_resume(self):
        rows, vocabulary = synthetic_rows()
        data_receipt = {"artifacts": {"training.json": {"bytes": 1, "sha256": "a" * 64}}}
        receipt_bytes = canonical_json_bytes(data_receipt)
        protocol = (train.ROOT / train.PROTOCOL).resolve()
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            root = Path(temporary).resolve()
            data_directory = root / "data"
            data_directory.mkdir()
            (data_directory / "data-receipt.json").write_bytes(receipt_bytes)
            output = root / "fit"
            models, initial = train.initialized_models()
            with patch.object(train, "code_identity", return_value={}), \
                 patch.object(train.data, "load_training", return_value=(object(), {}, data_receipt)), \
                 patch.object(train, "_validate_training_bundle", return_value=(rows, vocabulary)), \
                 patch.object(train, "_snapshot_data", return_value={}), \
                 patch.object(train, "build_training_plan", return_value={"version": train.PLAN_VERSION, "epochs": []}), \
                 patch.object(train, "initialized_models", return_value=(models, initial)), \
                 patch.object(train, "_copy_code_snapshot"), \
                 patch.object(train, "train_models", side_effect=ValueError("synthetic fit failure")):
                with self.assertRaisesRegex(ValueError, "synthetic fit failure"):
                    train.fit(data_directory, protocol, output)
                self.assertTrue((output / "training-plan.json").is_file())
                self.assertFalse((output / "fit-receipt.json").exists())
                self.assertEqual(list((output / "weights").iterdir()), [])
                with self.assertRaisesRegex(ValueError, "Fresh output"):
                    train.fit(data_directory, protocol, output)


if __name__ == "__main__":
    unittest.main()
