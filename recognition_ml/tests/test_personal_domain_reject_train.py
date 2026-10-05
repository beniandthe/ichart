"""Synthetic matched-training and publication integrity, not accuracy evidence."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch
from torch.nn import functional as F

from ichart_recognition_ml.research import personal_domain_reject_train as train


def vocab():
    source = tuple(f"old-{i:02}" for i in range(97)) + train.frozen.NOVEL_LABELS
    return train.core.make_vocabulary(source, source[:41])


def rows():
    result = [{"opaqueID": train.sha(f"uji:{w}:{s}:{label}".encode()), "label": label, "source": "uji"}
              for label in vocab().source_labels[:97] for w in range(16) for s in (1, 2)]
    counts = {"#": 939, "+": 65, "/": 383, "ø": 683, "△": 1025}
    result += [{"opaqueID": train.sha(f"hwrt:{label}:{i}".encode()), "label": label, "source": "hwrt"}
               for label in train.frozen.NOVEL_LABELS for i in range(counts[label])]
    return result


def receipt_fixture():
    vocabulary = vocab(); _, initial = train.initialized_models(vocabulary)
    ledger = {"epochs": 30, "updates": 1530, "exposures": 195840, "scheduleSHA256": "1" * 64,
        "batchOrderStreamSHA256": "1" * 64, "augmentationDrawStreamSHA256": "2" * 64,
        "augmentedImageStreamSHA256": "3" * 64, "actualForwardInputStreamSHA256": "3" * 64}
    return {"version": train.VERSION, "scope": train.SCOPE, "protocolSHA256": train.PROTOCOL_SHA256,
        "modelVersion": train.core.MODEL_VERSION, "codeSHA256": {}, "dataReceiptSHA256": "4" * 64,
        "sourceVocabulary": list(vocabulary.source_labels), "legalOldLabels": list(vocabulary.legal_labels[:41]),
        "candidateLabels": list(vocabulary.candidate_labels), "runtime": train.runtime_contract(), "recipe": train.RECIPE,
        "folds": list(train.FOLDS), "plans": {d: {"path": f"training-plans/{d}.json", "sha256": "5" * 64} for d in train.FOLDS},
        "initialization": {d: copy.deepcopy(initial) for d in train.FOLDS},
        "trainingHistory": {d: {a: [{"epoch": i, "meanLoss": 1., "correct": 1, "learningRate": .001} for i in range(1, 31)]
                               for a in train.ARMS} for d in train.FOLDS},
        "augmentationLedger": {d: {a: copy.deepcopy(ledger) for a in train.ARMS} for d in train.FOLDS},
        "weights": {d: {a: {"path": f"weights/{d}-{a}.pt", "sha256": "6" * 64} for a in train.ARMS} for d in train.FOLDS},
        "finalStateSHA256": {d: {a: "7" * 64 for a in train.ARMS} for d in train.FOLDS}, "selection": "final-epoch-only"}


class DomainRejectTrainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(4); torch.use_deterministic_algorithms(True)

    def test_identical_fresh_features_legal_rows_mean_reject_and_rng(self):
        before = torch.get_rng_state().clone(); models, initial = train.initialized_models(vocab())
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual(initial, train.initialized_models(vocab())[1])
        self.assertEqual({train.state_digest(train._feature_state(m)) for m in models.values()}, {initial["featureStateSHA256"]})
        self.assertTrue(initial["legalClassifierRowsExact"]); self.assertTrue(initial["rejectMean56Exact"])
        self.assertEqual(models["control"].classifier.out_features, 102)
        self.assertEqual(models["domainReject"].classifier.out_features, 47)
        self.assertNotEqual(initial["armStateSHA256"]["control"], initial["armStateSHA256"]["domainReject"])

    def test_two_real_steps_share_one_channel_bytes_and_unweighted_losses(self):
        vocabulary = vocab(); models, initial = train.initialized_models(vocabulary); optim, _ = train._optimizers(models)
        generator = torch.Generator().manual_seed(29)
        images = torch.rand((4, 1, 96, 256), generator=torch.Generator().manual_seed(74))
        source_targets = torch.tensor([0, 40, 56, 97]); source_hash = train.tensor_sha(images)
        for iteration in range(2):
            draws = train.frozen.field.sample_affine_draws(4, generator); augmented = train.augment_images(images, draws)
            if iteration == 0:
                expected = {}
                targets = train.core.map_targets(source_targets, vocabulary)
                for arm in train.ARMS:
                    reference = copy.deepcopy(models[arm]).train()
                    expected[arm] = float(F.cross_entropy(reference(augmented)[1], targets[arm]).detach())
            reports = train.paired_step(models, optim, augmented, source_targets, vocabulary)
            self.assertEqual({r["actualInputSHA256"] for r in reports.values()}, {train.tensor_sha(augmented)})
            if iteration == 0:
                self.assertEqual({a: r["loss"] for a, r in reports.items()}, expected)
        self.assertEqual(source_hash, train.tensor_sha(images))
        for arm in train.ARMS:
            self.assertNotEqual(train.state_digest(models[arm].state_dict()), initial["armStateSHA256"][arm])
            self.assertEqual({int(t) for n, t in models[arm].named_buffers() if n.endswith("num_batches_tracked")}, {2})
            fresh = train.initialized_models(vocabulary)[0][arm]
            for block in ("convolution", "projection", "classifier"):
                self.assertTrue(any(not torch.equal(t, dict(fresh.named_parameters())[n]) for n, t in models[arm].named_parameters() if n.startswith(block)))

    def test_exact_cycle_shuffle_complete_source_coverage_and_reject_exposures(self):
        records = rows(); source = vocab().source_labels; plan = train.build_training_plan(records, source)
        self.assertEqual(plan, train.build_training_plan(records, source))
        self.assertEqual(len(records), 6199); self.assertEqual(len(plan["epochs"]), 30)
        self.assertEqual(sum(e["updates"] for e in plan["epochs"]), 1530)
        self.assertEqual(sum(e["exposures"] for e in plan["epochs"]), 195840)
        self.assertTrue(all(c["availableRows"] == c["uniqueRowsSeen"] and c["exposures"] == 1920 for c in plan["classCoverage"].values()))
        by_label = {label: sorted([i for i, r in enumerate(records) if r["label"] == label],
            key=lambda i: (train.sha(b"ichart-domain-reject-cycle-v1\0" + records[i]["opaqueID"].encode()), records[i]["opaqueID"])) for label in source}
        selected = [pool[j % len(pool)] for label in source for pool in (by_label[label],) for j in range(64)]
        self.assertEqual(plan["epochs"][0]["rowIndices"], np.random.default_rng(29).permutation(selected).tolist())
        for epoch in plan["epochs"]:
            indices = [source.index(records[i]["label"]) for i in epoch["rowIndices"]]
            counts = np.bincount(indices, minlength=102); self.assertEqual(set(counts), {64})
            collapsed = train.core.map_targets(torch.tensor(indices), vocab())["domainReject"]
            self.assertEqual(int((collapsed == 46).sum()), 3584)
        with self.assertRaisesRegex(ValueError, "unique fitting"):
            train.build_training_plan(records[:-1], source)

    def test_nonfinite_gradient_and_actual_input_hook_fail_closed(self):
        models, _ = train.initialized_models(vocab()); optim, _ = train._optimizers(models)
        images = torch.rand((4, 1, 96, 256)); target = torch.tensor([0, 1, 56, 97])
        handle = models["control"].register_forward_pre_hook(lambda _m, args: (args[0].roll(1, dims=0),))
        try:
            with self.assertRaisesRegex(ValueError, "matched numerical"):
                train.paired_step(models, optim, images, target, vocab())
        finally:
            handle.remove()
        handle = models["domainReject"].classifier.weight.register_hook(lambda g: torch.full_like(g, float("nan")))
        try:
            with self.assertRaisesRegex(ValueError, "nonfinite gradient"):
                train.paired_step(models, optim, images, target, vocab())
        finally:
            handle.remove()

    def test_checkpoint_exact_reload_old_version_wrong_width_and_nonfinite_rejected(self):
        vocabulary = vocab(); models, _ = train.initialized_models(vocabulary)
        for arm in train.ARMS:
            labels = vocabulary.source_labels if arm == "control" else vocabulary.candidate_labels
            payload = train.checkpoint_bytes(models[arm], arm, labels)
            restored = train.load_checkpoint(payload, arm, labels, vocabulary)
            self.assertEqual(train.state_digest(restored.state_dict()), train.state_digest(models[arm].state_dict()))
        old_model = train.frozen.initialized_models()[0]["rasterControl"]
        old_payload = train.frozen.checkpoint_bytes(old_model, "rasterControl", "0" * 64)
        with self.assertRaisesRegex(ValueError, "checkpoint identity"):
            train.load_checkpoint(old_payload, "control", vocabulary.source_labels, vocabulary)
        with self.assertRaisesRegex(ValueError, "arm/width"):
            train.checkpoint_bytes(models["control"], "domainReject", vocabulary.candidate_labels)
        with torch.no_grad():
            models["domainReject"].classifier.weight[0, 0] = float("nan")
        with self.assertRaisesRegex(ValueError, "Nonfinite"):
            train.load_checkpoint(train.checkpoint_bytes(models["domainReject"], "domainReject", vocabulary.candidate_labels),
                                  "domainReject", vocabulary.candidate_labels, vocabulary)

    def test_receipt_rejects_wrong_experiment_missing_fold_miscounts_and_streams(self):
        receipt = receipt_fixture(); train._validate_fit_receipt(receipt, {})
        bad = copy.deepcopy(receipt); bad["version"] = train.frozen.VERSION
        with self.assertRaisesRegex(ValueError, "identity"):
            train._validate_fit_receipt(bad)
        bad = copy.deepcopy(receipt); bad["weights"].pop(train.FOLDS[1])
        with self.assertRaisesRegex(ValueError, "Incomplete writer fold"):
            train._validate_fit_receipt(bad)
        bad = copy.deepcopy(receipt); bad["augmentationLedger"][train.FOLDS[0]]["domainReject"]["updates"] = 1529
        with self.assertRaisesRegex(ValueError, "count ledger"):
            train._validate_fit_receipt(bad)
        bad = copy.deepcopy(receipt); bad["augmentationLedger"][train.FOLDS[0]]["domainReject"]["actualForwardInputStreamSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "count ledger"):
            train._validate_fit_receipt(bad)

    def test_blind_loader_only_safe_snapshots_and_weights(self):
        receipt = receipt_fixture(); vocabulary = vocab()
        with tempfile.TemporaryDirectory() as td:
            directory = Path(td).resolve(); code_bytes = b"synthetic snapshot"; code = {"synthetic.py": train.sha(code_bytes)}
            receipt["codeSHA256"] = code
            source = {k: receipt[k] for k in ("sourceVocabulary", "legalOldLabels", "candidateLabels")}; source_bytes = train.canonical(source)
            receipt["dataReceiptSHA256"] = train.sha(source_bytes)
            train.frozen._write_exclusive(directory / "data-receipt.json", source_bytes)
            train.frozen._write_exclusive(directory / "frozen-protocol.md", (train.ROOT / train.PROTOCOL).read_bytes())
            train.frozen._write_exclusive(directory / "executed-code" / "synthetic.py", code_bytes)
            for fold in train.FOLDS:
                plan_bytes = train.canonical({"version": train.PLAN_VERSION})
                train.frozen._write_exclusive(directory / receipt["plans"][fold]["path"], plan_bytes)
                receipt["plans"][fold]["sha256"] = train.sha(plan_bytes); models, _ = train.initialized_models(vocabulary)
                for arm in train.ARMS:
                    with torch.no_grad():
                        next(models[arm].parameters()).add_(.001)
                    labels = vocabulary.source_labels if arm == "control" else vocabulary.candidate_labels
                    payload = train.checkpoint_bytes(models[arm], arm, labels)
                    train.frozen._write_exclusive(directory / receipt["weights"][fold][arm]["path"], payload)
                    receipt["weights"][fold][arm]["sha256"] = train.sha(payload)
                    receipt["finalStateSHA256"][fold][arm] = train.state_digest(models[arm].state_dict())
                for name in ("query-truth.json", "fit.json", "query-inputs.json", "query-rasters.npy"):
                    train.frozen._write_exclusive(directory / "folds" / fold / name, b"DECOY-DO-NOT-OPEN")
            payload = train.canonical(receipt); train.frozen._write_exclusive(directory / "fit-receipt.json", payload)
            original = train.read
            def guarded(path, **kwargs):
                self.assertNotIn(Path(path).name, {"query-truth.json", "fit.json", "query-inputs.json", "query-rasters.npy"})
                return original(path, **kwargs)
            with patch.object(train, "code_identity", return_value=code), patch.object(train, "read", side_effect=guarded):
                models, _ = train.load_fitted_models(directory, train.sha(payload))
                self.assertTrue(all(not m.training for arms in models.values() for m in arms.values()))
                self.assertEqual({f: {a: train.state_digest(m.state_dict()) for a, m in arms.items()} for f, arms in models.items()}, receipt["finalStateSHA256"])
                with self.assertRaisesRegex(ValueError, "receipt SHA"):
                    train.load_fitted_models(directory, "0" * 64)
                (directory / "executed-code" / "synthetic.py").write_bytes(b"tampered")
                with self.assertRaisesRegex(ValueError, "code snapshot"):
                    train.load_fitted_models(directory, train.sha(payload))

    def test_fit_failure_opens_only_chosen_fold_and_publishes_no_success(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve(); directory = root / "data"; directory.mkdir(); output = root / "fit"
            # Sparse disk-backed synthetic image fixture; no model forward.
            image_path = root / "synthetic.npy"
            images = np.lib.format.open_memmap(image_path, mode="w+", dtype=np.float32, shape=(6199, 1, 96, 256))
            del images; images = np.load(image_path, mmap_mode="r")
            vocabulary = vocab(); data_receipt = {"sourceVocabulary": list(vocabulary.source_labels),
                "legalOldLabels": list(vocabulary.legal_labels[:41]), "candidateLabels": list(vocabulary.candidate_labels)}
            train.frozen._write_exclusive(directory / "data-receipt.json", train.canonical(data_receipt))
            metadata = {"fold": train.FOLDS[0], "vocabulary": list(vocabulary.source_labels), "rows": rows()}
            calls = []
            def load_fit(_directory, fold):
                calls.append(fold); self.assertEqual(fold, train.FOLDS[0]); return images, metadata, data_receipt
            code = {train.PROTOCOL: train.PROTOCOL_SHA256}
            with patch.object(train, "code_identity", return_value=code), patch.object(train.data, "load_fit", side_effect=load_fit), \
                 patch.object(train, "_snapshot_fold", return_value={}), \
                 patch.object(train, "train_models", side_effect=ValueError("synthetic training failure")):
                with self.assertRaisesRegex(ValueError, "synthetic training failure"):
                    train.fit(directory, train.ROOT / train.PROTOCOL, output)
                self.assertEqual(calls, [train.FOLDS[0]])
                self.assertTrue((output / "training-plans" / f"{train.FOLDS[0]}.json").is_file())
                self.assertFalse((output / "fit-receipt.json").exists())
                self.assertEqual(list((output / "weights").iterdir()), [])
                with self.assertRaisesRegex(ValueError, "resume is forbidden"):
                    train.fit(directory, train.ROOT / train.PROTOCOL, output)
            del images


if __name__ == "__main__":
    unittest.main()
