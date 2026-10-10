"""Nonzero synthetic paired fitting; no official rasters, targets or models."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_support_match_defer_train as train


def fixture():
    vocabulary = ["A", "B", "C", "D"] + [f"symbol-{i}" for i in range(93)]
    rng = np.random.default_rng(71)
    raw = rng.integers(0, 256, (4, 1, 96, 256), dtype=np.uint8)
    stored = rng.integers(0, 256, (2, 1, 96, 256), dtype=np.uint8)
    support = [{"slot": i, "label": label, "sourceIndex": 10 + i, "sourceID": f"lesson-{i}",
                "storedTrajectorySHA256": train.sha(f"trajectory-{i}".encode()),
                "storedRasterSHA256": train.sha(stored[i].tobytes()), "storedFailure": None} for i, label in enumerate(("A", "B"))]
    support.append({"slot": 2, "label": "C", "sourceIndex": 12, "sourceID": "unavailable-C",
                    "storedTrajectorySHA256": None, "storedRasterSHA256": None, "storedFailure": "unavailable"})
    batch = [{"sourceIndex": s["sourceIndex"], "role": "storedSupport", "supportSlot": s["slot"],
              "rasterSHA256": s["storedRasterSHA256"]} for s in support[:2]]
    batch += [{"sourceIndex": i, "role": "rawQuery", "queryPosition": i,
               "rasterSHA256": train.sha(raw[i].tobytes())} for i in range(4)]
    episode = {"episodeID": "synthetic", "support": support, "profileUsable": True, "profileIssues": [],
               "availableSupportRows": 2, "queryBatchOffset": 2, "querySourceIndices": list(range(4)),
               "availablePrototypeLabels": ["A", "B"], "requestedSupportLabels": ["A", "B", "C"],
               "batchSources": batch, "batchSHA256": train.sha(train.canonical(batch))}
    rows = [{"episodeID": "synthetic", "queryPosition": i, "sourceIndex": i, "genericClassIndex": i,
             "matchPrototypeIndex": i if i < 2 else None, "defer": i >= 2,
             "matchDeferClassIndex": i if i < 2 else 2,
             "cohort": "taught" if i < 2 else "requestedSupportUnavailable" if i == 2 else "untaught"} for i in range(4)]
    arrays = {"raw_rasters": raw, "stored_rasters": stored, "stored_source_indices": np.array([10, 11], dtype=np.int64)}
    return vocabulary, episode, rows, arrays


def augmentation_update(generator, rows):
    audit = torch.Generator(); audit.set_state(generator.get_state())
    before = train.tensor_sha(audit.get_state())
    draws = torch.rand((rows, 4), generator=audit)
    return {"batchRows": rows, "generatorBeforeSHA256": before, "generatorAfterSHA256": train.tensor_sha(audit.get_state()),
            "augmentationDrawsSHA256": train.tensor_sha(draws)}


class PairedTrainerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(4); torch.use_deterministic_algorithms(True)

    def test_entire_seed_state_cloned_across_four_models_without_global_rng_change(self):
        torch.manual_seed(117); before = torch.get_rng_state().clone()
        models, state, digest = train.initialized_models()
        self.assertTrue(torch.equal(before, torch.get_rng_state()))
        self.assertEqual({train._state_digest(m.state_dict()) for arms in models.values() for m in arms.values()}, {digest})
        self.assertTrue(any(n.endswith("running_mean") for n in state))
        model = models[train.DIRECTIONS[0]][train.ARMS[0]]
        with torch.no_grad():
            next(model.parameters()).add_(1)
        self.assertNotEqual(train._state_digest(model.state_dict()), digest)
        self.assertEqual(train._state_digest(models[train.DIRECTIONS[1]][train.ARMS[0]].state_dict()), digest)

    def test_two_real_gradient_steps_share_actual_batch_and_leave_control_matcher_unused(self):
        vocabulary, episode, rows, arrays = fixture()
        models, initial, _ = train.initialized_models(); models = models[train.DIRECTIONS[0]]
        optim, sched = train.optimizers(models, total_updates=2)
        generator = torch.Generator().manual_seed(29); records = []
        with patch.object(models[train.ARMS[0]], "forward", side_effect=AssertionError("Control used matcher")):
            for _ in range(2):
                batch = train.batch_tensor(arrays, episode)
                update = augmentation_update(generator, len(batch))
                augmented = train.matched_augmentation(batch, generator, update)
                records.append(train.paired_step(models, optim, sched, augmented, episode, rows, vocabulary, {"A", "B", "C"}))
        for record in records:
            self.assertEqual(len(set(record["actualInputSHA256"].values())), 1)
            self.assertEqual(record["batchRows"], 6)
            self.assertEqual(record["batchNormIncrements"][train.ARMS[0]], record["batchNormIncrements"][train.ARMS[1]])
            control, candidate = (record["losses"][a] for a in train.ARMS)
            self.assertEqual(control["total"], control["generic"])
            self.assertEqual(control["matchDefer"], 0)
            self.assertAlmostEqual(candidate["total"], candidate["generic"] + candidate["matchDefer"], places=5)
        self.assertEqual(records[0]["losses"][train.ARMS[0]]["generic"], records[0]["losses"][train.ARMS[1]]["generic"])
        for arm in train.ARMS:
            changes = train._changes(models[arm], initial)
            for block in ("encoder.convolution", "encoder.projection", "encoder.classifier"):
                self.assertGreater(changes[block], 0)
            for block in ("relation_mlp", "defer_mlp"):
                self.assertGreater(changes[block], 0) if arm == train.ARMS[1] else self.assertEqual(changes[block], 0)
            self.assertEqual(sched[arm].last_epoch, 2)
            self.assertEqual({int(t) for n, t in models[arm].named_buffers() if n.endswith("num_batches_tracked")}, {2})
        matcher_keys = [n for n in initial if n.startswith(("relation_mlp.", "defer_mlp."))]
        self.assertEqual(train._state_digest({n: initial[n] for n in matcher_keys}),
                         train._state_digest({n: models[train.ARMS[0]].state_dict()[n] for n in matcher_keys}))

    def test_actual_encoder_input_hook_rejects_arm_mutation(self):
        vocabulary, episode, rows, arrays = fixture()
        models, _, _ = train.initialized_models(); models = models[train.DIRECTIONS[0]]
        optim, sched = train.optimizers(models, 1)
        original = models[train.ARMS[0]].encode_episode
        with patch.object(models[train.ARMS[0]], "encode_episode", side_effect=lambda s, q: original(s, q.roll(1, dims=0))):
            with self.assertRaisesRegex(ValueError, "Actual encoder input"):
                train.paired_step(models, optim, sched, train.batch_tensor(arrays, episode), episode, rows, vocabulary, {"A", "B"})

    def test_rng_raster_duplicate_and_unavailable_fail_closed(self):
        _, episode, _, arrays = fixture(); batch = train.batch_tensor(arrays, episode)
        generator = torch.Generator().manual_seed(29); update = augmentation_update(generator, len(batch))
        update["augmentationDrawsSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "augmentation"):
            train.matched_augmentation(batch, generator, update)
        bad = copy.deepcopy(arrays); bad["stored_rasters"][0, 0, 0, 0] ^= 1
        with self.assertRaisesRegex(ValueError, "raster changed"):
            train.batch_tensor(bad, episode)
        duplicate = copy.deepcopy(episode); duplicate["support"][1]["storedTrajectorySHA256"] = duplicate["support"][0]["storedTrajectorySHA256"]
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            train.batch_tensor(arrays, duplicate)
        unusable = copy.deepcopy(episode); unusable["profileUsable"] = False
        with self.assertRaisesRegex(ValueError, "Unusable"):
            train.batch_tensor(arrays, unusable)
        missing = copy.deepcopy(arrays); missing["stored_source_indices"][0] = 99
        with self.assertRaisesRegex(ValueError, "missing"):
            train.batch_tensor(missing, episode)

    def test_joint_targets_reject_inconsistent_cohort_and_empty_fixed_loss(self):
        vocabulary, episode, rows, _ = fixture()
        target = train.paired_targets(rows, vocabulary, episode)
        self.assertEqual(target.generic.tolist(), [0, 1, 2, 3]); self.assertEqual(target.match_defer.tolist(), [0, 1, 2, 2])
        bad = copy.deepcopy(rows); bad[2]["matchDeferClassIndex"] = 0
        with self.assertRaisesRegex(ValueError, "Joint targets disagree"):
            train.paired_targets(bad, vocabulary, episode)
        bad = copy.deepcopy(rows); bad[2]["cohort"] = "untaught"
        with self.assertRaisesRegex(ValueError, "cohort contradiction"):
            train.paired_targets(bad, vocabulary, episode)
        with self.assertRaisesRegex(ValueError, "Empty fixed loss"):
            train.paired_targets(rows[:2], vocabulary, episode)

    def test_target_reader_only_opens_chosen_fold_not_decoy_truth_or_ledgers(self):
        vocabulary, episode, _, _ = fixture(); episodes, records = [], []
        for i in range(64):
            e = {**episode, "episodeID": f"fit-{i}", "querySourceIndices": list(range(97))}; episodes.append(e)
            for index, label in enumerate(vocabulary):
                taught = index < 2
                records.append({"episodeID": e["episodeID"], "queryPosition": index, "sourceIndex": index,
                    "genericClassIndex": index, "matchPrototypeIndex": index if taught else None, "defer": not taught,
                    "matchDeferClassIndex": index if taught else 2,
                    "cohort": "taught" if taught else "requestedSupportUnavailable" if label == "C" else "untaught"})
        direction = train.DIRECTIONS[0]; name = direction + "-training-targets.json"; content = train.canonical(records)
        forward = {"vocabulary": vocabulary, "trainingTargetBindings": {direction: {"path": name, "SHA256": train.sha(content), "rows": 6208}},
                   "forward": {direction: {"trainingEpisodes": episodes}}}
        receipt = {"artifacts": {name: train.sha(content)}}
        with tempfile.TemporaryDirectory() as td:
            directory = Path(td).resolve(); train._write(directory / name, content)
            for decoy in ("score-truth.json", direction + "-scoring-ledger.json", train.DIRECTIONS[1] + "-training-targets.json"):
                train._write(directory / decoy, b"DECOY-DO-NOT-READ")
            original = train.read; calls = []
            def guarded(path):
                calls.append(Path(path).name)
                self.assertEqual(Path(path).name, name)
                return original(path)
            with patch.object(train, "read", side_effect=guarded):
                targets, _ = train.training_targets(directory, forward, receipt, direction)
            self.assertEqual(calls, [name]); self.assertEqual(sum(map(len, targets.values())), 6208)
            with self.assertRaisesRegex(ValueError, "changed or incomplete"):
                train.training_targets(directory, forward, {"artifacts": {name: "0" * 64}}, direction)

    def test_nonfinite_matcher_gradient_rejected_before_candidate_step(self):
        vocabulary, episode, rows, arrays = fixture()
        models, _, _ = train.initialized_models(); models = models[train.DIRECTIONS[0]]
        optim, sched = train.optimizers(models, 1)
        handle = next(models[train.ARMS[1]].relation_mlp.parameters()).register_hook(lambda g: torch.full_like(g, float("nan")))
        try:
            with self.assertRaisesRegex(ValueError, "Matcher gradient"):
                train.paired_step(models, optim, sched, train.batch_tensor(arrays, episode), episode, rows, vocabulary, {"A", "B"})
        finally:
            handle.remove()

    def test_exact_30_by_64_frozen_schedule_and_hashes(self):
        vocabulary, template, _, _ = fixture()
        episodes = [{**template, "episodeID": f"episode-{i}", "querySourceIndices": list(range(97))} for i in range(64)]
        epochs = train.plan.epoch_schedule(episodes)
        forward = {"protocolSHA256": train.plan.PROTOCOL_SHA256, "bindings": {"codeSHA256": {}},
            "vocabulary": vocabulary, "allowedLabels": vocabulary[:41],
            "recipe": {"seed": 29, "epochs": 30, "episodesPerEpoch": 64, "arms": list(train.ARMS), "optimizer": "AdamW",
                "cpuThreads": 4, "learningRate": .001, "weightDecay": .0001,
                "scheduler": {"name": "CosineAnnealingLR", "tMax": 1920, "stepPer": "optimizer-update"},
                "selection": "final-epoch-only-no-heldout-selection"},
            "forward": {d: {"trainingEpisodes": episodes, "epochs": copy.deepcopy(epochs),
                "fitWriters": [f"fit-{i}" for i in range(16)], "heldoutWriters": [f"heldout-{i}" for i in range(16)]}
                for d in train.DIRECTIONS}}
        with patch.object(train.plan, "code_identity", return_value={}):
            train._validate_schedule(forward)
            self.assertEqual(len(epochs), 30); self.assertEqual(sum(len(e["updates"]) for e in epochs), 1920)
            forward["forward"][train.DIRECTIONS[1]]["epochs"][-1]["updates"].pop()
            with self.assertRaisesRegex(ValueError, "30x64"):
                train._validate_schedule(forward)

    def test_receipt_last_target_failure_and_fresh_output_no_resume(self):
        # Synthetic orchestration stubs: no real source-plan or raster read.
        forward = {"vocabulary": [str(i) for i in range(97)], "allowedLabels": [str(i) for i in range(41)], "recipe": {},
                   "trainingTargetBindings": {d: {"SHA256": "1" * 64} for d in train.DIRECTIONS},
                   "forward": {d: {"epochs": []} for d in train.DIRECTIONS}}
        source_receipt = {}; source_bytes = train.canonical(source_receipt)
        data_receipt = {"rastersSHA256": "2" * 64}; data_bytes = train.canonical(data_receipt)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve(); source = root / "source"; data_dir = root / "data"; output = root / "fit"
            def metadata(path):
                return (source_receipt, source_bytes) if Path(path).name == "plan-receipt.json" else (data_receipt, data_bytes)
            with patch.object(train.data, "load_forward_plan", return_value=forward), \
                 patch.object(train, "_validate_schedule"), patch.object(train, "_json", side_effect=metadata), \
                 patch.object(train.data, "load_raster_bundle", return_value=({}, data_receipt)), \
                 patch.object(train, "code_identity", return_value={}), \
                 patch.object(train, "training_targets", side_effect=ValueError("synthetic target failure")) as targets, \
                 patch.object(train, "optimizers", side_effect=AssertionError("Optimization before targets")):
                with self.assertRaisesRegex(ValueError, "synthetic target failure"):
                    train.fit(source, data_dir, output, data_receipt_sha256=train.sha(data_bytes))
                self.assertTrue((output / "fit-plan.json").is_file())
                self.assertFalse((output / "fit-receipt.json").exists())
                self.assertEqual(list((output / "weights").iterdir()), [])
                with self.assertRaisesRegex(ValueError, "Fresh outside"):
                    train.fit(source, data_dir, output, data_receipt_sha256=train.sha(data_bytes))
                self.assertEqual(targets.call_count, 1)


if __name__ == "__main__":
    unittest.main()
