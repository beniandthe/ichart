"""Synthetic replay/update and blind-publication checks, not accuracy evidence."""
import copy
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from torch.nn import functional as F

from ichart_recognition_ml.research import personal_same_label_transfer_train as train


def vocabulary():
    source = tuple(f"old-{i:02}" for i in range(97)) + train.parent.frozen.NOVEL_LABELS
    return train.parent.core.make_vocabulary(source, source[:41])


def synthetic_sources():
    source = vocabulary().source_labels
    old = [{"opaqueID": train.sha(f"uji:{label}:{i}".encode()), "label": label, "source": "uji"}
           for label in source[:97] for i in range(32)]
    counts = {"#": 939, "+": 65, "/": 383, "ø": 683, "△": 1025}
    old += [{"opaqueID": train.sha(f"old-hwrt:{label}:{i}".encode()), "label": label, "source": "hwrt"}
            for label in source[97:] for i in range(counts[label])]
    new = [{"opaqueID": train.sha(f"new:{label}:{i}".encode()), "sourceLabel": label}
           for label in source[:35] for i in range(43)]
    return old, new


def receipt_fixture():
    v = vocabulary(); selected = ["a" * 64]
    ledger = {"epochs": 30, "updates": 1530, "exposures": 195840, "replacements": 33600,
        "augmentationDrawStreamSHA256": train.DRAW_STREAM_SHA256, "actualForwardInputStreamSHA256": "2" * 64,
        "sourceTargetStreamSHA256": "3" * 64, "unaffectedSourceSlotStreamSHA256": "4" * 64,
        "parentScheduleSHA256": "5" * 64, "replacementScheduleSHA256": "6" * 64}
    return {"version": train.VERSION, "scope": train.SCOPE, "protocolSHA256": train.PROTOCOL_SHA256,
        "modelVersion": train.parent.core.MODEL_VERSION, "recipe": train.RECIPE, "initialStateSHA256": train.INITIAL_STATE_SHA256,
        "parentDataReceiptSHA256": train.PARENT_DATA_SHA256, "parentFitReceiptSHA256": train.PARENT_FIT_SHA256,
        "newDataReceiptSHA256": train.eligibility.ENCODED_RECEIPT_SHA256, "eligibilityReceiptSHA256": "7" * 64,
        "manifestSHA256": "8" * 64, "codeSHA256": {}, "runtime": train.runtime_contract(),
        "sourceVocabulary": list(v.source_labels), "legalOldLabels": list(v.legal_labels[:41]), "selectedOpaqueIDs": selected,
        "selection": "final-epoch-only", "comparatorRefitted": False, "queryTruthOrPredictionsOpened": False,
        "plans": {f: {"path": f"plans/{f}.json", "sha256": "9" * 64} for f in train.FOLDS},
        "fitFingerprints": {f: {"path": f"fit-fingerprints/{f}.json", "sha256": "b" * 64, "rows": 6200} for f in train.FOLDS},
        "baselineWeights": {f: {"path": f"weights/{f}-control.pt", "sha256": "c" * 64, "stateSHA256": "d" * 64} for f in train.FOLDS},
        "weights": {f: {"path": f"weights/{f}.pt", "sha256": "e" * 64} for f in train.FOLDS},
        "finalStateSHA256": {f: "f" * 64 for f in train.FOLDS},
        "trainingHistory": {f: [{"epoch": e, "meanLoss": 1., "correct": 2, "learningRate": .001} for e in range(1, 31)] for f in train.FOLDS},
        "augmentationLedger": {f: copy.deepcopy(ledger) for f in train.FOLDS}}


class SameLabelTransferTrainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
        cls.old, cls.new = synthetic_sources()
        cls.parent_plan = train.parent.build_training_plan(cls.old, vocabulary().source_labels)
        cls.ids = sorted(r["opaqueID"] for r in cls.new)

    def test_second_only_source_slots_targets_cycle_and_complete_coverage(self):
        plan = train.build_transfer_plan(self.parent_plan, self.old, self.new, self.ids, vocabulary().source_labels)
        self.assertEqual(plan, train.build_transfer_plan(self.parent_plan, self.old, self.new, list(reversed(self.ids)), vocabulary().source_labels))
        self.assertEqual(plan["parentScheduleSHA256"], self.parent_plan["scheduleSHA256"])
        self.assertTrue(all(v > 0 for v in plan["parentRowMultiplicity"].values()))
        self.assertTrue(all(v > 0 for v in plan["newRowMultiplicity"].values()))
        self.assertEqual(sum(plan["newRowMultiplicity"].values()), 33600)
        self.assertEqual(sum(plan["parentRowMultiplicity"].values()) + 33600, 195840)
        pools = {l: sorted([i for i, r in enumerate(self.new) if r["sourceLabel"] == l],
            key=lambda i: (train.sha(b"same-label-hwrt-cycle-v1\0" + self.new[i]["opaqueID"].encode()), self.new[i]["opaqueID"]))
            for l in vocabulary().source_labels[:35]}
        for e, epoch in enumerate(plan["epochs"]):
            self.assertEqual(epoch["parentRowIndices"], self.parent_plan["epochs"][e]["rowIndices"])
            seen = {}; j = {l: 0 for l in pools}; unchanged = {l: 0 for l in vocabulary().source_labels}
            for old_i, new_i in zip(epoch["parentRowIndices"], epoch["newRowIndices"]):
                row = self.old[old_i]; seen[old_i] = seen.get(old_i, 0) + 1; label = row["label"]
                if row["source"] == "uji" and label in pools and seen[old_i] == 2:
                    self.assertEqual(new_i, pools[label][(32 * e + j[label]) % len(pools[label])]); j[label] += 1
                    self.assertEqual(self.new[new_i]["sourceLabel"], label)
                else:
                    self.assertEqual(new_i, -1); unchanged[label] += 1
            self.assertEqual(set(j.values()), {32})
            self.assertTrue(all(n == (32 if l in pools else 64) for l, n in unchanged.items()))
        self.assertEqual({c["exposures"] for c in plan["newPoolCoverage"].values()}, {960})

    def test_replay_miscount_missing_id_and_narrowed_class_fail(self):
        changed = copy.deepcopy(self.parent_plan); changed["epochs"][0]["rowIndices"][0] = -1
        with self.assertRaises(ValueError): train.build_transfer_plan(changed, self.old, self.new, self.ids, vocabulary().source_labels)
        with self.assertRaises(ValueError): train.build_transfer_plan(self.parent_plan, self.old, self.new, [*self.ids, "x"], vocabulary().source_labels)
        narrowed = [r["opaqueID"] for r in self.new if r["sourceLabel"] != "old-00"]
        with self.assertRaises(ValueError): train.build_transfer_plan(self.parent_plan, self.old, self.new, narrowed, vocabulary().source_labels)
        changed = copy.deepcopy(self.parent_plan); changed["scheduleSHA256"] = "0" * 64
        with self.assertRaises(ValueError): train.build_transfer_plan(changed, self.old, self.new, self.ids, vocabulary().source_labels)
        changed = copy.deepcopy(self.parent_plan); changed["sourceVocabulary"] = list(reversed(changed["sourceVocabulary"]))
        with self.assertRaisesRegex(ValueError, "vocabulary order"):
            train.build_transfer_plan(changed, self.old, self.new, self.ids, vocabulary().source_labels)

    def test_exact_fresh_102_control_initialization_and_rng_preserved(self):
        before = torch.get_rng_state().clone(); model = train.initialized_model(vocabulary())
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual(train.state_digest(model.state_dict()), train.INITIAL_STATE_SHA256)
        self.assertEqual(model.classifier.out_features, 102); self.assertEqual(model.arm, "control")
        self.assertEqual(train.state_digest(train.initialized_model(vocabulary()).state_dict()), train.INITIAL_STATE_SHA256)

    def test_two_real_updates_literal_ce_actual_input_and_all_blocks_change(self):
        model = train.initialized_model(vocabulary()); fresh = copy.deepcopy(model)
        optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
        images = torch.rand((4, 1, 96, 256), generator=torch.Generator().manual_seed(74))
        before = train.tensor_sha(images); generator = torch.Generator().manual_seed(29); targets = torch.tensor([0, 34, 61, 97])
        for step in range(2):
            draws = train.parent.frozen.field.sample_affine_draws(4, generator); augmented = train.parent.augment_images(images, draws)
            if step == 0:
                expected = float(F.cross_entropy(copy.deepcopy(model).train()(augmented)[1], targets).detach())
            report = train.candidate_step(model, optimizer, augmented, targets)
            self.assertEqual(report["actualInputSHA256"], train.tensor_sha(augmented)); self.assertTrue(np.isfinite(report["loss"]))
            if step == 0: self.assertEqual(report["loss"], expected)
        self.assertEqual(train.tensor_sha(images), before)
        self.assertEqual({int(t) for n, t in model.named_buffers() if n.endswith("num_batches_tracked")}, {2})
        for block in ("convolution", "projection", "classifier"):
            self.assertTrue(any(not torch.equal(t, dict(fresh.named_parameters())[n]) for n, t in model.named_parameters() if n.startswith(block)))

    def test_finite_embedding_gradient_and_47_architecture_are_required(self):
        model = train.initialized_model(vocabulary()); optimizer = torch.optim.AdamW(model.parameters(), lr=.001)
        images = torch.zeros(2, 1, 96, 256); targets = torch.tensor([0, 1])
        hook = model.register_forward_hook(lambda _m, _a, out: (out[0] * float("nan"), out[1]))
        with self.assertRaisesRegex(ValueError, "forward"): train.candidate_step(model, optimizer, images, targets)
        hook.remove(); gradient = next(model.parameters()).register_hook(lambda value: value * float("nan"))
        with self.assertRaisesRegex(ValueError, "gradient"): train.candidate_step(model, optimizer, images, targets)
        gradient.remove(); wrong = train.parent.core.make_matched_models(vocabulary())["domainReject"]
        with self.assertRaises(ValueError): train.candidate_step(wrong, optimizer, images, targets)

    def test_full_original_affine_draw_digest_without_model_fit(self):
        generator = torch.Generator().manual_seed(29); stream = hashlib.sha256()
        for _ in range(1530):
            draws = train.parent.frozen.field.sample_affine_draws(128, generator)
            train.stream_update(stream, train.tensor_bytes(draws))
        self.assertEqual(stream.hexdigest(), train.DRAW_STREAM_SHA256)

    def test_checkpoint_reload_new_version_only_and_nonfinite_refused(self):
        v = vocabulary(); model = train.initialized_model(v)
        with torch.no_grad(): model.classifier.bias.add_(.2)
        payload = train.checkpoint_bytes(model, list(v.source_labels))
        loaded = train.load_checkpoint(payload, list(v.source_labels), list(v.legal_labels[:41]))
        self.assertEqual(train.state_digest(loaded.state_dict()), train.state_digest(model.state_dict()))
        value = torch.load(io.BytesIO(payload), weights_only=True); value["version"] = train.parent.VERSION
        buffer = io.BytesIO(); torch.save(value, buffer)
        with self.assertRaises(ValueError): train.load_checkpoint(buffer.getvalue(), list(v.source_labels), list(v.legal_labels[:41]))
        value["version"] = train.VERSION; value["stateDict"]["classifier.bias"][0] = float("nan")
        buffer = io.BytesIO(); torch.save(value, buffer)
        with self.assertRaises(ValueError): train.load_checkpoint(buffer.getvalue(), list(v.source_labels), list(v.legal_labels[:41]))

    def test_receipt_pins_completed_counts_draws_and_final_selection(self):
        receipt = receipt_fixture(); train._validate_fit_receipt(receipt, {})
        for key, value in (("version", train.parent.VERSION), ("comparatorRefitted", True), ("initialStateSHA256", "0" * 64)):
            bad = copy.deepcopy(receipt); bad[key] = value
            with self.assertRaises(ValueError): train._validate_fit_receipt(bad, {})
        for key, value in (("updates", 1529), ("augmentationDrawStreamSHA256", "0" * 64), ("replacements", 33599)):
            bad = copy.deepcopy(receipt); bad["augmentationLedger"][train.FOLDS[0]][key] = value
            with self.assertRaises(ValueError): train._validate_fit_receipt(bad, {})

    def test_blind_loader_uses_only_own_safe_snapshots_weights_and_rejects_tamper(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); receipt = receipt_fixture(); code_bytes = b"synthetic-code"; code = {"synthetic.py": train.sha(code_bytes)}
            receipt["codeSHA256"] = code
            train.write(root / "executed-code/synthetic.py", code_bytes)
            train.write(root / "frozen-protocol.md", train.read(train.ROOT / train.PROTOCOL))
            v = vocabulary(); model = train.initialized_model(v)
            with torch.no_grad(): model.classifier.bias.add_(.2)
            for fold in train.FOLDS:
                for key in ("plans", "fitFingerprints"):
                    binding = receipt[key][fold]; payload = train.canonical({"syntheticSafeArtifact": key, "fold": fold})
                    train.write(root / binding["path"], payload); binding["sha256"] = train.sha(payload)
                payload = train.checkpoint_bytes(model, list(v.source_labels)); binding = receipt["weights"][fold]
                train.write(root / binding["path"], payload); binding["sha256"] = train.sha(payload)
                receipt["finalStateSHA256"][fold] = train.state_digest(model.state_dict())
            manifest = {k: v for k, v in receipt.items() if k not in {"weights", "finalStateSHA256", "trainingHistory", "augmentationLedger", "manifestSHA256"}}
            content = train.canonical(manifest); train.write(root / "run-manifest.json", content); receipt["manifestSHA256"] = train.sha(content)
            content = train.canonical(receipt); train.write(root / "fit-receipt.json", content); pin = train.sha(content)
            real_read = train.read; opened = []
            def guarded(path, **kwargs):
                path = Path(path); self.assertTrue(path.is_relative_to(root)); opened.append(path.name)
                self.assertNotIn(path.name, {"query-truth.json", "query-inputs.json", "eligibility.json", "fit.json"})
                return real_read(path, **kwargs)
            with patch.object(train, "code_identity", return_value=code), patch.object(train, "read", side_effect=guarded):
                models, loaded = train.load_fitted_models(root, pin)
                self.assertEqual(loaded, receipt); self.assertEqual(set(models), set(train.FOLDS))
                self.assertTrue(all(not m.training and m.label_count == 102 for m in models.values()))
                with self.assertRaises(ValueError): train.load_fitted_models(root, "0" * 64)
                train.write(root / "extra-safe-decoy.json", b"ignored")
                weight = root / receipt["weights"][train.FOLDS[0]]["path"]
                with weight.open("ab") as stream: stream.write(b"tamper")
                with self.assertRaises(ValueError): train.load_fitted_models(root, pin)
            self.assertNotIn("extra-safe-decoy.json", opened)

    def test_original_failure_retained_no_success_or_resume(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary).resolve() / "candidate"
            def fail(*_args, **_kwargs):
                train.parent.frozen._fresh_directory(destination)
                train.write(destination / "run-manifest.json", b"frozen-before-update")
                raise RuntimeError("synthetic numerical failure")
            with patch.object(train, "_fit", side_effect=fail):
                with self.assertRaisesRegex(RuntimeError, "synthetic numerical failure"):
                    train.fit("a", "b", "c", "d", destination, eligibility_receipt_sha256="1" * 64)
            status = train.parsed(train.read(destination / "failure.json"), name="failure")
            self.assertEqual(status["exceptionType"], "RuntimeError"); self.assertFalse(status["resumeAllowed"])
            self.assertFalse((destination / "fit-receipt.json").exists())
            with self.assertRaisesRegex(ValueError, "resume"): train.parent.frozen._fresh_directory(destination)


if __name__ == "__main__":
    unittest.main()
