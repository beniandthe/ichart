"""Fixed research-only paired fitting; never opens heldout targets or truth.

One augmented support+query batch is shared by the two arms at each update.
Encoder hooks bind the bytes actually forwarded, not merely the planned rows.
Only final checkpoints are published; a failed run cannot silently resume.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import os
from pathlib import Path
import platform

import numpy as np
import torch
from torch.nn import functional as F

from . import personal_support_match_defer as core
from . import personal_support_match_defer_data as data
from . import personal_support_match_defer_plan as plan
from .personal_cross_writer_contrastive import _state_digest
from .personal_visual_encoder import augment

VERSION = "personal-support-match-defer-fit-v1"
ARMS = plan.ARMS
DIRECTIONS = ("A16-to-B16", "B16-to-A16")
UPDATES = 1920
CODE_PATHS = tuple(dict.fromkeys((*plan.CODE_PATHS, *data.CODE_PATHS,
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_train.py",
    "recognition_ml/tests/test_personal_support_match_defer_train.py")))
canonical, sha, read, parsed, require = plan.canonical, plan.sha, plan.read, plan.parsed, plan.require


def code_identity():
    result = {name: sha(read(plan.ROOT / name)) for name in CODE_PATHS}
    require(result[plan.PROTOCOL] == plan.PROTOCOL_SHA256, "Fixed training protocol changed")
    plan.code_identity(); data.code_identity()
    return result


def tensor_sha(tensor):
    return sha(tensor.detach().cpu().contiguous().numpy().tobytes())


def _file_sha(path):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path and path.is_file() and not path.is_symlink()
            and 0 < path.stat().st_size <= 256 * 1024 * 1024, "Bounded regular binary required")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _write(path, content):
    with path.open("xb") as stream:
        stream.write(content); stream.flush(); os.fsync(stream.fileno())


def _json(path):
    content = read(path)
    value = parsed(content)
    require(canonical(value) == content, "Canonical metadata required")
    return value, content


def initialized_models():
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(plan.SEED)
        original = core.PersonalSupportMatchDeferModel()
    models = {d: {a: copy.deepcopy(original) for a in ARMS} for d in DIRECTIONS}
    state = {name: tensor.clone() for name, tensor in original.state_dict().items()}
    digest = _state_digest(state)
    require(all(_state_digest(m.state_dict()) == digest for arms in models.values() for m in arms.values()),
            "Complete seed29 state did not match all four fits")
    return models, state, digest


def optimizers(models, total_updates=UPDATES):
    optim = {a: torch.optim.AdamW(models[a].encoder.parameters() if a == ARMS[0] else models[a].parameters(),
                                lr=.001, weight_decay=.0001) for a in ARMS}
    sched = {a: torch.optim.lr_scheduler.CosineAnnealingLR(optim[a], T_max=total_updates) for a in ARMS}
    return optim, sched


def training_targets(directory, forward, receipt, direction):
    """The only label-bearing file read by fitting, one chosen fold at a time."""
    require(direction in DIRECTIONS, "Unknown training direction")
    binding = forward["trainingTargetBindings"][direction]
    name = direction + "-training-targets.json"
    require(binding["path"] == name, "Training target path changed")
    records, content = _json(Path(directory) / name)
    require(sha(content) == binding["SHA256"] == receipt["artifacts"][name]
            and len(records) == binding["rows"] == 6208, "Training targets changed or incomplete")
    episodes = forward["forward"][direction]["trainingEpisodes"]
    by_episode = {e["episodeID"]: [] for e in episodes}
    for row in records:
        require(set(row) == {"episodeID", "queryPosition", "sourceIndex", "genericClassIndex", "matchPrototypeIndex",
                            "defer", "matchDeferClassIndex", "cohort"} and row["episodeID"] in by_episode,
                "Unexpected training target field/episode")
        by_episode[row["episodeID"]].append(row)
    for e in episodes:
        rows = by_episode[e["episodeID"]]
        require(len(rows) == 97 and [r["queryPosition"] for r in rows] == list(range(97))
                and [r["sourceIndex"] for r in rows] == e["querySourceIndices"], "Target/query order mismatch")
        paired_targets(rows, forward["vocabulary"], e)
    return by_episode, content


def paired_targets(rows, vocabulary, episode):
    require(all(type(r["genericClassIndex"]) is int and 0 <= r["genericClassIndex"] < 97 for r in rows),
            "Invalid generic training index")
    # Training truth remains an external loss sidecar; numerical forward gets no labels.
    labels = [vocabulary[r["genericClassIndex"]] for r in rows]
    target = core.joint_training_targets(labels, vocabulary, episode["availablePrototypeLabels"])
    require(target.match_defer.tolist() == [r["matchDeferClassIndex"] for r in rows], "Joint targets disagree")
    for r, label, index in zip(rows, labels, target.match_defer.tolist()):
        taught = label in episode["availablePrototypeLabels"]
        expected_cohort = "taught" if taught else "requestedSupportUnavailable" if label in episode["requestedSupportLabels"] else "untaught"
        require(type(r["defer"]) is bool and r["defer"] == (not taught) and r["cohort"] == expected_cohort
                and r["matchPrototypeIndex"] == (index if taught else None), "Training target cohort contradiction")
    require(bool((target.match_defer < len(episode["availablePrototypeLabels"])).any())
            and bool((target.match_defer == len(episode["availablePrototypeLabels"])).any()), "Empty fixed loss cohort")
    return target


def batch_tensor(arrays, episode):
    require(episode["profileUsable"] and not episode["profileIssues"] and episode["availableSupportRows"] > 0,
            "Unusable training support profile; fixed schedule cannot be repaired")
    support = [s for s in episode["support"] if s["storedFailure"] is None]
    for key in ("sourceID", "storedRasterSHA256", "storedTrajectorySHA256"):
        require(len({s[key] for s in support}) == len(support), "Duplicate support payload")
    require(sha(canonical(episode["batchSources"])) == episode["batchSHA256"]
            and len(support) == episode["availableSupportRows"] == episode["queryBatchOffset"], "Batch plan changed")
    stored = {int(index): position for position, index in enumerate(arrays["stored_source_indices"])}
    result = []
    for position, row in enumerate(episode["batchSources"]):
        if position < len(support):
            s = support[position]
            require(row == {"sourceIndex": s["sourceIndex"], "role": "storedSupport", "supportSlot": s["slot"],
                            "rasterSHA256": s["storedRasterSHA256"]} and s["sourceIndex"] in stored,
                    "Stored support missing or reordered")
            pixels = arrays["stored_rasters"][stored[s["sourceIndex"]]]
        else:
            p = position - len(support)
            require(row["role"] == "rawQuery" and row["queryPosition"] == p
                    and row["sourceIndex"] == episode["querySourceIndices"][p], "Raw query order changed")
            pixels = arrays["raw_rasters"][row["sourceIndex"]]
        require(pixels.dtype == np.uint8 and pixels.shape == (1, 96, 256)
                and sha(pixels.tobytes()) == row["rasterSHA256"], "Actual fitted raster changed")
        result.append(pixels)
    return torch.from_numpy(np.stack(result)).float() / 255


def matched_augmentation(batch, generator, update):
    before = tensor_sha(generator.get_state())
    audit = torch.Generator(); audit.set_state(generator.get_state())
    draws = torch.rand((len(batch), 4), generator=audit)
    after = tensor_sha(audit.get_state())
    require(before == update["generatorBeforeSHA256"] and after == update["generatorAfterSHA256"]
            and tensor_sha(draws) == update["augmentationDrawsSHA256"] and len(batch) == update["batchRows"],
            "Frozen Torch augmentation draws/order changed")
    augmented = augment(batch, generator)
    require(tensor_sha(generator.get_state()) == after and bool(torch.isfinite(augmented).all()), "Augmentation replay changed")
    return augmented


def paired_step(models, optim, sched, augmented, episode, rows, vocabulary, allowed):
    """One real gradient update for both arms; also used by short synthetic tests."""
    target = paired_targets(rows, vocabulary, episode)
    count, digest = episode["availableSupportRows"], tensor_sha(augmented)
    support_rows = [s for s in episode["support"] if s["storedFailure"] is None]
    hashes, losses, bn = {}, {}, {}
    for arm in ARMS:
        model = models[arm]; model.train(); optim[arm].zero_grad(set_to_none=True)
        calls = []
        before = {n: int(t) for n, t in model.named_buffers() if n.endswith("num_batches_tracked")}
        def hook(_module, args):
            calls.append(tensor_sha(args[0]))
            require(calls[-1] == digest and args[0].shape == augmented.shape, "Actual encoder input diverged")
        handle = model.encoder.register_forward_pre_hook(hook)
        try:
            encoded = model.encode_episode(augmented[:count], augmented[count:])
        finally:
            handle.remove()
        require(calls == [digest] and tensor_sha(augmented) == digest, "Single shared batch was mutated/re-encoded")
        bn[arm] = {n: int(t) - before[n] for n, t in model.named_buffers() if n in before}
        require(bn[arm] and set(bn[arm].values()) == {1}, "Batch-normalization exposure changed")
        if arm == ARMS[0]:
            generic = F.cross_entropy(encoded.query_generic_logits, target.generic)
            loss = generic; matcher = 0.0
        else:
            pooled = core.pool_confirmed_support(encoded.support_embeddings, [s["label"] for s in support_rows],
                [s["sourceID"] for s in support_rows], [s["storedTrajectorySHA256"] for s in support_rows],
                [s["storedRasterSHA256"] for s in support_rows], lambda label: label in allowed)
            require(list(pooled.labels) == episode["availablePrototypeLabels"], "Prototype/target order changed")
            output = core.make_match_defer_output(model, encoded, pooled)
            parts = core.joint_training_loss(encoded.query_generic_logits, target.generic, output.match_defer_logits, target.match_defer)
            loss, generic, matcher = parts.total, parts.generic, float(parts.match_defer.detach())
        require(bool(torch.isfinite(loss)), "Nonfinite paired training loss")
        loss.backward()
        require(all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in model.encoder.parameters()), "Invalid encoder gradient")
        matcher_parameters = tuple(model.relation_mlp.parameters()) + tuple(model.defer_mlp.parameters())
        require(all(p.grad is None for p in matcher_parameters) if arm == ARMS[0] else
                all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in matcher_parameters), "Matcher gradient boundary changed")
        optim[arm].step(); sched[arm].step()
        require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values()), "Nonfinite updated state")
        hashes[arm] = calls[0]
        losses[arm] = {"total": float(loss.detach()), "generic": float(generic.detach()), "matchDefer": matcher}
    require(hashes[ARMS[0]] == hashes[ARMS[1]] and bn[ARMS[0]] == bn[ARMS[1]], "Matched exposure diverged")
    return {"actualInputSHA256": hashes, "batchRows": len(augmented), "batchNormIncrements": bn, "losses": losses}


def _changes(model, initial):
    result = {}
    for block in ("encoder.convolution", "encoder.projection", "encoder.classifier", "relation_mlp", "defer_mlp"):
        result[block] = max(float((t.detach() - initial[n]).abs().max()) for n, t in model.named_parameters() if n.startswith(block + "."))
    return result


def _validate_schedule(forward):
    require(forward["protocolSHA256"] == plan.PROTOCOL_SHA256 and forward["bindings"]["codeSHA256"] == plan.code_identity()
            and set(forward["forward"]) == set(DIRECTIONS) and len(forward["vocabulary"]) == 97
            and len(set(forward["vocabulary"])) == 97 and len(set(forward["allowedLabels"])) == 41,
            "Frozen schedule lineage changed")
    r = forward["recipe"]
    require((r["seed"], r["epochs"], r["episodesPerEpoch"], r["arms"], r["optimizer"], r["cpuThreads"],
             r["learningRate"], r["weightDecay"], r["scheduler"], r["selection"]) ==
            (29, 30, 64, list(ARMS), "AdamW", 4, .001, .0001,
             {"name": "CosineAnnealingLR", "tMax": UPDATES, "stepPer": "optimizer-update"}, "final-epoch-only-no-heldout-selection"),
            "Fixed training recipe changed")
    for direction in DIRECTIONS:
        f = forward["forward"][direction]; episodes = f["trainingEpisodes"]
        require(len(episodes) == len({e["episodeID"] for e in episodes}) == 64 and len(f["fitWriters"]) == 16
                and not set(f["fitWriters"]) & set(f["heldoutWriters"]), "Wrong training writer schedule")
        require(all(e["profileUsable"] and not e["profileIssues"] and len(e["querySourceIndices"]) == 97 for e in episodes),
                "Unusable training episode")
        require(f["epochs"] == plan.epoch_schedule(episodes), "Fixed 30x64 augmentation schedule changed")


def fit(source_plan, data_dir, output, *, data_receipt_sha256):
    source_plan, data_dir, output = map(Path, (source_plan, data_dir, output))
    require(plan.digest(data_receipt_sha256), "Caller-pinned data receipt required")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    forward = data.load_forward_plan(source_plan); _validate_schedule(forward)
    source_receipt, source_bytes = _json(source_plan / "plan-receipt.json")
    data_receipt, data_bytes = _json(data_dir / "data-receipt.json")
    require(sha(data_bytes) == data_receipt_sha256, "Data receipt pin changed")
    arrays, validated = data.load_raster_bundle(data_dir, forward)
    require(validated == data_receipt, "Data receipt changed during load")
    code = code_identity(); models, initial, initial_sha = initialized_models()
    target_hashes = {d: forward["trainingTargetBindings"][d]["SHA256"] for d in DIRECTIONS}
    fit_plan = {"version": VERSION, "protocolSHA256": plan.PROTOCOL_SHA256, "codeSHA256": code,
        "sourcePlanReceiptSHA256": sha(source_bytes), "forwardPlanSHA256": sha(canonical(forward)),
        "dataReceiptSHA256": data_receipt_sha256, "rasterDataSHA256": data_receipt["rastersSHA256"],
        "vocabulary": forward["vocabulary"], "allowedLabels": forward["allowedLabels"], "recipe": forward["recipe"],
        "initialStateSHA256": initial_sha, "initialArmStateSHA256": {d: {a: initial_sha for a in ARMS} for d in DIRECTIONS},
        "trainingTargetSHA256": target_hashes, "scheduleSHA256": {d: sha(canonical(forward["forward"][d]["epochs"])) for d in DIRECTIONS},
        "augmentationExecution": "one-shared-tensor-per-paired-update-two-direct-encoder-input-hooks",
        "runtime": {"python": platform.python_version(), "torch": str(torch.__version__), "numpy": str(np.__version__),
                    "device": "cpu", "threads": torch.get_num_threads(), "deterministicAlgorithms": torch.are_deterministic_algorithms_enabled()}}
    require(output.is_absolute() and output.parent.resolve() == output.parent and output.parent.is_dir() and not output.exists()
            and plan.ROOT not in output.parents and source_plan not in output.parents and data_dir not in output.parents,
            "Fresh outside-source/Git output required; no resume")
    output.mkdir(); (output / "weights").mkdir()
    artifacts = {"fit-plan.json": canonical(fit_plan), "forward-plan.json": canonical(forward),
                 "source-plan-receipt.json": source_bytes, "data-receipt.json": data_bytes}
    for name, content in artifacts.items():
        _write(output / name, content)
    trace, history, weights = [], {}, {}
    with (output / "progress.jsonl").open("x") as progress:
        for direction in DIRECTIONS:
            targets, target_bytes = training_targets(source_plan, forward, source_receipt, direction)
            episodes = {e["episodeID"]: e for e in forward["forward"][direction]["trainingEpisodes"]}
            optim, sched = optimizers(models[direction]); generator = torch.Generator().manual_seed(plan.SEED)
            epoch_history = []; input_hashes = {a: hashlib.sha256() for a in ARMS}; exposure = 0
            for epoch in forward["forward"][direction]["epochs"]:
                total = {a: 0.0 for a in ARMS}
                for update in epoch["updates"]:
                    e = episodes[update["episodeID"]]
                    augmented = matched_augmentation(batch_tensor(arrays, e), generator, update)
                    result = paired_step(models[direction], optim, sched, augmented, e, targets[e["episodeID"]],
                                         forward["vocabulary"], set(forward["allowedLabels"]))
                    for arm in ARMS:
                        input_hashes[arm].update(bytes.fromhex(result["actualInputSHA256"][arm])); total[arm] += result["losses"][arm]["total"]
                    exposure += result["batchRows"]
                    trace.append({"direction": direction, "epoch": epoch["epoch"], **update, **result})
                event = {"direction": direction, "epoch": epoch["epoch"], "updatesPerArm": (epoch["epoch"] + 1) * 64,
                         "meanTrainingLoss": {a: total[a] / 64 for a in ARMS}}
                epoch_history.append(event); progress.write(canonical(event).decode() + "\n"); progress.flush(); os.fsync(progress.fileno())
                print(canonical(event).decode(), flush=True)
            require(len(epoch_history) == 30 and all(s.last_epoch == UPDATES for s in sched.values())
                    and len({h.hexdigest() for h in input_hashes.values()}) == 1, "Exact matched update count failed")
            require(read(source_plan / (direction + "-training-targets.json")) == target_bytes, "Training targets changed during fit")
            changes = {a: _changes(models[direction][a], initial) for a in ARMS}
            require(all(changes[a][b] > 0 for a in ARMS for b in ("encoder.convolution", "encoder.projection", "encoder.classifier"))
                    and changes[ARMS[0]]["relation_mlp"] == changes[ARMS[0]]["defer_mlp"] == 0
                    and changes[ARMS[1]]["relation_mlp"] > 0 and changes[ARMS[1]]["defer_mlp"] > 0, "Expected learned/unused blocks did not match")
            history[direction] = {"epochs": epoch_history, "updatesPerArm": UPDATES, "encodedRowsPerArm": exposure,
                "orderedActualInputSHA256": {a: h.hexdigest() for a, h in input_hashes.items()}, "parameterMaxAbsChanges": changes,
                "controlMatcherUnchanged": True}
            weights[direction] = {}
            for arm in ARMS:
                state = models[direction][arm].state_dict(); state_sha = _state_digest(state)
                name = f"weights/{direction}-{arm}.pt"
                with (output / name).open("xb") as stream:
                    torch.save({"version": VERSION, "direction": direction, "arm": arm, "protocolSHA256": plan.PROTOCOL_SHA256,
                                "initialStateSHA256": initial_sha, "finalStateSHA256": state_sha, "state_dict": state}, stream)
                    stream.flush(); os.fsync(stream.fileno())
                weights[direction][arm] = {"path": name, "SHA256": _file_sha(output / name), "stateSHA256": state_sha}
    require(code_identity() == code and data.load_forward_plan(source_plan) == forward
            and read(source_plan / "plan-receipt.json") == source_bytes and read(data_dir / "data-receipt.json") == data_bytes
            and _file_sha(data_dir / "rasters.npz") == data_receipt["rastersSHA256"], "Inputs/code changed before final publication")
    for direction in DIRECTIONS:
        require(sha(read(source_plan / (direction + "-training-targets.json"))) == target_hashes[direction], "Previously used targets changed")
    _write(output / "training-trace.json", canonical(trace))
    manifest = {name: sha(content) for name, content in artifacts.items()}
    require(all(sha(read(output / name)) == expected for name, expected in manifest.items()), "Frozen fit-plan metadata changed")
    manifest.update({"training-trace.json": sha(canonical(trace)), "progress.jsonl": _file_sha(output / "progress.jsonl")})
    receipt = {**fit_plan, "fitPlanSHA256": manifest["fit-plan.json"], "artifacts": manifest, "weights": weights,
        "trainingHistory": history, "roleGuards": {"heldoutRastersInferred": False, "heldoutTruthOpened": False,
            "scoringLedgersOpened": False, "privateInkUsed": False, "historicalEncoderWeightsUsed": False,
            "finalEpochOnly": True, "productionEligible": False}}
    _write(output / "fit-receipt.json", canonical(receipt))
    load_fitted_models(output, sha(canonical(receipt)))
    return receipt


def load_fitted_models(directory, expected_receipt_sha256):
    """Prediction-facing: strict final receipt, safe metadata and weights only."""
    directory = Path(directory); receipt, content = _json(directory / "fit-receipt.json")
    require(plan.digest(expected_receipt_sha256) and sha(content) == expected_receipt_sha256
            and receipt["version"] == VERSION and receipt["protocolSHA256"] == plan.PROTOCOL_SHA256
            and receipt["codeSHA256"] == code_identity(), "Frozen fit receipt/code pin changed")
    required_artifacts = {"fit-plan.json", "forward-plan.json", "source-plan-receipt.json", "data-receipt.json", "training-trace.json", "progress.jsonl"}
    require(set(receipt["artifacts"]) == required_artifacts, "Fit artifact manifest changed")
    for name, expected in receipt["artifacts"].items():
        require(_file_sha(directory / name) == expected, "Frozen fit artifact changed")
    fit_plan, _ = _json(directory / "fit-plan.json"); forward, _ = _json(directory / "forward-plan.json")
    source_receipt, source_bytes = _json(directory / "source-plan-receipt.json"); data_receipt, data_bytes = _json(directory / "data-receipt.json")
    require(all(receipt[k] == value for k, value in fit_plan.items()) and receipt["fitPlanSHA256"] == receipt["artifacts"]["fit-plan.json"]
            and receipt["sourcePlanReceiptSHA256"] == sha(source_bytes) == data.PLAN_RECEIPT_SHA256
            and receipt["forwardPlanSHA256"] == sha(canonical(forward)) == data.FORWARD_PLAN_SHA256
            and source_receipt["artifacts"]["forward-plan.json"] == receipt["forwardPlanSHA256"]
            and receipt["dataReceiptSHA256"] == sha(data_bytes) and data_receipt["rastersSHA256"] == receipt["rasterDataSHA256"]
            and data_receipt["codeSHA256"] == data.code_identity() and data_receipt["forwardPlanSHA256"] == receipt["forwardPlanSHA256"]
            and receipt["vocabulary"] == forward["vocabulary"] and receipt["allowedLabels"] == forward["allowedLabels"], "Fit lineage changed")
    require(set(receipt["weights"]) == set(DIRECTIONS) and set(receipt["trainingHistory"]) == set(DIRECTIONS), "Missing fitted direction")
    models = {}
    for direction in DIRECTIONS:
        require(set(receipt["weights"][direction]) == set(ARMS) and receipt["trainingHistory"][direction]["updatesPerArm"] == UPDATES,
                "Missing arm or wrong update count")
        models[direction] = {}
        for arm in ARMS:
            info = receipt["weights"][direction][arm]; name = f"weights/{direction}-{arm}.pt"
            require(info["path"] == name and _file_sha(directory / name) == info["SHA256"], "Final checkpoint changed")
            checkpoint = torch.load(directory / name, weights_only=True, map_location="cpu")
            require(set(checkpoint) == {"version", "direction", "arm", "protocolSHA256", "initialStateSHA256", "finalStateSHA256", "state_dict"}
                    and (checkpoint["version"], checkpoint["direction"], checkpoint["arm"], checkpoint["protocolSHA256"], checkpoint["initialStateSHA256"])
                    == (VERSION, direction, arm, plan.PROTOCOL_SHA256, receipt["initialStateSHA256"])
                    and _state_digest(checkpoint["state_dict"]) == checkpoint["finalStateSHA256"] == info["stateSHA256"]
                    and all(bool(torch.isfinite(t).all()) for t in checkpoint["state_dict"].values()), "Invalid final model state")
            with torch.random.fork_rng(devices=[]):
                model = core.PersonalSupportMatchDeferModel()
            model.load_state_dict(checkpoint["state_dict"], strict=True); model.cpu().eval()
            require(_state_digest(model.state_dict()) == info["stateSHA256"], "Checkpoint reload changed state")
            models[direction][arm] = model
    return models, receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-plan", type=Path, required=True); p.add_argument("--data", type=Path, required=True)
    p.add_argument("--data-receipt-sha256", required=True); p.add_argument("--output", type=Path, required=True)
    a = p.parse_args(); result = fit(a.source_plan, a.data, a.output, data_receipt_sha256=a.data_receipt_sha256)
    print(canonical({"output": str(a.output), "weights": result["weights"]}).decode(), flush=True)


if __name__ == "__main__":
    main()
