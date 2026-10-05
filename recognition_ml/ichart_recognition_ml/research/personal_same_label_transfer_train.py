"""One candidate-only same-label source-diversity fit; research only.

Replay the authenticated 102-way control schedule and replace only second UJI
occurrences. Never open parent query/truth/prediction files or 47-way weights.
All schedules and eligible inputs are frozen before the first optimizer step.
"""
from __future__ import annotations

import argparse
import hashlib
import io
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F

from ..contracts import canonical_json_bytes as canonical
from . import personal_domain_reject_train as parent
from . import personal_domain_reject_data as parent_data
from . import personal_same_label_eligibility as eligibility

VERSION = "personal-same-label-transfer-fit-v1"
PLAN_VERSION = "personal-same-label-transfer-plan-v1"
FINGERPRINT_VERSION = "personal-same-label-transfer-fit-fingerprints-v1"
SCOPE = "research-only-same-label-source-transfer-v1"
PROTOCOL = "docs/personal-same-label-transfer-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "cbab15675ed16698c0a9cfb32f420df1ef54c80bd6054cd034b793f9ba713061"
PARENT_DATA_SHA256 = "d835b1e01ec21cdaac4f8882d8ef02309c3cd9960408b45fa17cc74a0b5023d5"
PARENT_FIT_SHA256 = "556dbc308fc778ce6273910301b13ab1652742a474ed1a0d000f1ec65ef90bdb"
INITIAL_STATE_SHA256 = "d3ccc13b94cce764ddecc31d43d09f155848e6951a4f6c24ad0d10508b4bd332"
DRAW_STREAM_SHA256 = "1fb59eaa47d693eab351ea9b909659fd48b66eb411dd06ac7767a884e7ebeabc"
ROOT, FOLDS = parent.ROOT, parent.FOLDS
RECIPE = {**parent.frozen.RECIPE, "sourceClasses": 102, "perClassExposuresPerEpoch": 64,
          "overlapClasses": 35, "UJIExposuresPerOverlapClassPerEpoch": 32,
          "newHWRTExposuresPerOverlapClassPerEpoch": 32, "optimizer": parent.frozen.OPTIMIZATION}
CODE_PATHS = (PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/personal_same_label_transfer_train.py",
    "recognition_ml/tests/test_personal_same_label_transfer_train.py",
    "recognition_ml/ichart_recognition_ml/research/personal_same_label_transfer_evaluate.py",
    "recognition_ml/tests/test_personal_same_label_transfer_evaluate.py")
require, sha, digest, read, parsed, file_sha = parent.require, parent.sha, parent.digest, parent.read, parent.parsed, parent.file_sha
state_digest, tensor_sha, tensor_bytes = parent.state_digest, parent.tensor_sha, parent.tensor_bytes
stream_update, runtime_contract = parent.stream_update, parent.runtime_contract
write = parent.frozen._write_exclusive


def code_identity():
    result = {**parent.code_identity(), **eligibility.code_identity()}
    result.update({name: sha(read(ROOT / name, maximum=32 * 1024 * 1024)) for name in CODE_PATHS})
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Fixed same-label protocol changed")
    return result


def initialized_model(vocabulary):
    model = parent.core.make_matched_models(vocabulary)["control"]
    require(state_digest(model.state_dict()) == INITIAL_STATE_SHA256 and model.label_count == 102,
            "Original fresh 102-way control initialization changed")
    return model


def build_transfer_plan(parent_plan, parent_rows, new_rows, selected_ids, source_vocabulary):
    require(parent_plan["sourceVocabulary"] == list(source_vocabulary), "Parent plan/model target vocabulary order changed")
    require(len(parent_rows) == 6199 and len(parent_plan["epochs"]) == 30 and len(set(selected_ids)) == len(selected_ids), "Incomplete replay sources")
    by_id = {r["opaqueID"]: i for i, r in enumerate(new_rows)}
    require(len(by_id) == len(new_rows) and set(selected_ids) <= set(by_id), "Eligibility IDs do not join encoded rows")
    selected = [by_id[value] for value in selected_ids]
    labels = sorted({new_rows[i]["sourceLabel"] for i in selected})
    require(len(labels) == 35 and set(labels) <= {r["label"] for r in parent_rows if r["source"] == "uji"}, "Fixed 35-class overlap missing")
    pools = {label: sorted([i for i in selected if new_rows[i]["sourceLabel"] == label],
        key=lambda i: (sha(("same-label-hwrt-cycle-v1\0" + new_rows[i]["opaqueID"]).encode()), new_rows[i]["opaqueID"])) for label in labels}
    parent_counts = np.zeros(len(parent_rows), dtype=np.int64); new_counts = np.zeros(len(new_rows), dtype=np.int64)
    replay_stream, replacement_stream = hashlib.sha256(), hashlib.sha256(); epochs = []
    source_labels = parent_plan["sourceVocabulary"]
    for e, epoch in enumerate(parent_plan["epochs"]):
        order = epoch["rowIndices"]
        require(epoch["epoch"] == e and len(order) == 6528 and all(type(i) is int and 0 <= i < len(parent_rows) for i in order), "Parent epoch/indices changed")
        payload = np.asarray(order, dtype="<i8").tobytes()
        require(sha(payload) == epoch["permutationSHA256"], "Saved parent slot order changed")
        stream_update(replay_stream, payload); seen = np.zeros(len(parent_rows), dtype=np.int64); slots = {label: 0 for label in labels}; replacements = []
        counts = {label: 0 for label in source_labels}
        for i in order:
            row = parent_rows[i]; seen[i] += 1; counts[row["label"]] += 1; replacement = -1
            if row["source"] == "uji" and row["label"] in pools and seen[i] == 2:
                label = row["label"]; j = slots[label]; replacement = pools[label][(32 * e + j) % len(pools[label])]; slots[label] += 1
                require(new_rows[replacement]["sourceLabel"] == label, "Replacement changed literal target")
                new_counts[replacement] += 1
            else:
                parent_counts[i] += 1
            replacements.append(replacement)
        require(set(counts.values()) == {64} and set(slots.values()) == {32}
                and all(seen[i] == 2 for i, r in enumerate(parent_rows) if r["source"] == "uji"), "Parent UJI repeat/class exposure contract changed")
        replacement_bytes = np.asarray(replacements, dtype="<i8").tobytes(); stream_update(replacement_stream, replacement_bytes)
        epochs.append({"epoch": e, "parentRowIndices": order, "newRowIndices": replacements,
            "parentOrderSHA256": sha(payload), "replacementIndicesSHA256": sha(replacement_bytes), "replacements": 1120})
    require(replay_stream.hexdigest() == parent_plan["scheduleSHA256"] and bool((parent_counts > 0).all())
            and all(new_counts[i] > 0 for i in selected), "Replay digest or actual fitting-source coverage changed")
    pool_coverage = {l: {"eligibleRows": len(pool), "uniqueRowsSeen": int(np.count_nonzero(new_counts[pool])),
        "exposures": int(new_counts[pool].sum()), "minimumMultiplicity": int(new_counts[pool].min()),
        "maximumMultiplicity": int(new_counts[pool].max())} for l, pool in pools.items()}
    require(all(c["exposures"] == 960 and c["eligibleRows"] == c["uniqueRowsSeen"] for c in pool_coverage.values()), "Eligible pool coverage changed")
    return {"version": PLAN_VERSION, "recipe": RECIPE, "sourceVocabulary": source_labels, "eligibleOpaqueIDs": sorted(selected_ids),
        "epochs": epochs, "parentScheduleSHA256": replay_stream.hexdigest(), "replacementScheduleSHA256": replacement_stream.hexdigest(),
        "parentRowMultiplicity": {r["opaqueID"]: int(parent_counts[i]) for i, r in enumerate(parent_rows)},
        "newRowMultiplicity": {new_rows[i]["opaqueID"]: int(new_counts[i]) for i in selected}, "newPoolCoverage": pool_coverage,
        "targetsUnchanged": True, "replaceOnlySecondUJIExposure": True, "replacementsPerEpoch": 1120}


def candidate_step(model, optimizer, images, targets):
    require(model.arm == "control" and model.label_count == 102, "A fresh 102-way control architecture is required")
    model.train(); optimizer.zero_grad(set_to_none=True); expected = tensor_sha(images); calls = []
    def hook(_module, args):
        calls.append(tensor_sha(args[0]))
    handle = model.register_forward_pre_hook(hook)
    try:
        embedding, logits = model(images)
    finally:
        handle.remove()
    require(calls == [expected] and logits.shape == (len(images), 102) and embedding.shape == (len(images), 128)
            and bool(torch.isfinite(logits).all()) and bool(torch.isfinite(embedding).all()), "Complete actual 102-way forward changed")
    loss = F.cross_entropy(logits, targets); require(bool(torch.isfinite(loss)), "Nonfinite candidate loss")
    loss.backward()
    require(all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in model.parameters()), "Missing/nonfinite candidate gradient")
    optimizer.step()
    require(tensor_sha(images) == expected and all(bool(torch.isfinite(t).all()) for t in model.state_dict().values() if t.is_floating_point()), "Input mutation/nonfinite candidate state")
    return {"loss": float(loss.detach()), "correct": int((logits.detach().argmax(1) == targets).sum()), "actualInputSHA256": calls[0]}


def train_model(model, parent_images, new_images, parent_rows, plan, fold):
    require(plan["version"] == PLAN_VERSION and len(plan["epochs"]) == 30, "Frozen replacement plan changed")
    optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=30)
    generator = torch.Generator().manual_seed(29); source_index = {l: i for i, l in enumerate(plan["sourceVocabulary"])}
    draw_stream, input_stream, target_stream, unchanged_stream = (hashlib.sha256() for _ in range(4)); history = []; updates = 0
    for epoch in plan["epochs"]:
        require(sha(np.asarray(epoch["parentRowIndices"], dtype="<i8").tobytes()) == epoch["parentOrderSHA256"]
            and sha(np.asarray(epoch["newRowIndices"], dtype="<i8").tobytes()) == epoch["replacementIndicesSHA256"], "Frozen replacement slots changed")
        total_loss, correct = 0., 0
        for offset in range(0, 6528, 128):
            indices = epoch["parentRowIndices"][offset:offset + 128]; replacement = epoch["newRowIndices"][offset:offset + 128]
            source = torch.from_numpy(np.array(parent_images[indices], dtype=np.float32, copy=True, order="C")); original = source.clone()
            for position, new_index in enumerate(replacement):
                if new_index >= 0:
                    source[position] = torch.from_numpy(np.array(new_images[new_index], dtype=np.float32, copy=True))
            unchanged = torch.tensor([i for i, index in enumerate(replacement) if index < 0], dtype=torch.long)
            require(torch.equal(source[unchanged], original[unchanged]), "Unaffected source slots changed")
            stream_update(unchanged_stream, tensor_bytes(source[unchanged]))
            draws = parent.frozen.field.sample_affine_draws(128, generator); stream_update(draw_stream, tensor_bytes(draws))
            augmented = parent.augment_images(source, draws); payload = tensor_bytes(augmented); stream_update(input_stream, payload)
            targets = torch.tensor([source_index[parent_rows[i]["label"]] for i in indices], dtype=torch.long); stream_update(target_stream, tensor_bytes(targets))
            report = candidate_step(model, optimizer, augmented, targets); require(report["actualInputSHA256"] == sha(payload), "Actual input trace changed")
            total_loss += report["loss"] * 128; correct += report["correct"]; updates += 1
        scheduler.step(); history.append({"epoch": epoch["epoch"] + 1, "meanLoss": total_loss / 6528,
            "correct": correct, "learningRate": float(scheduler.get_last_lr()[0])})
        print(canonical({"fold": fold, "updates": updates, **history[-1]}).decode(), flush=True)
    require(updates == 1530 and scheduler.last_epoch == 30 and draw_stream.hexdigest() == DRAW_STREAM_SHA256, "Fixed completed count/affine draw replay failed")
    return history, {"epochs": 30, "updates": updates, "exposures": 195840, "replacements": 33600,
        "augmentationDrawStreamSHA256": draw_stream.hexdigest(), "actualForwardInputStreamSHA256": input_stream.hexdigest(),
        "sourceTargetStreamSHA256": target_stream.hexdigest(), "unaffectedSourceSlotStreamSHA256": unchanged_stream.hexdigest(),
        "parentScheduleSHA256": plan["parentScheduleSHA256"], "replacementScheduleSHA256": plan["replacementScheduleSHA256"]}


def checkpoint_bytes(model, source_labels):
    require(isinstance(model, parent.core.DomainRejectModel) and model.arm == "control" and model.label_count == 102, "Candidate checkpoint must be literal102")
    buffer = io.BytesIO(); torch.save({"version": VERSION, "modelVersion": parent.core.MODEL_VERSION, "labelCount": 102,
        "sourceVocabularySHA256": sha(canonical(source_labels)), "stateDict": model.state_dict()}, buffer)
    return buffer.getvalue()


def load_checkpoint(payload, source_labels, legal_old_labels):
    try:
        value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    except Exception as error:
        raise ValueError("Invalid same-label candidate checkpoint") from error
    require(isinstance(value, dict) and set(value) == {"version", "modelVersion", "labelCount", "sourceVocabularySHA256", "stateDict"}
            and (value["version"], value["modelVersion"], value["labelCount"], value["sourceVocabularySHA256"])
            == (VERSION, parent.core.MODEL_VERSION, 102, sha(canonical(source_labels))), "Same-label checkpoint identity changed")
    model = initialized_model(parent.core.make_vocabulary(source_labels, legal_old_labels))
    try:
        model.load_state_dict(value["stateDict"], strict=True)
    except (RuntimeError, ValueError, TypeError) as error:
        raise ValueError("Same-label checkpoint state changed") from error
    require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values() if t.is_floating_point()), "Nonfinite candidate checkpoint")
    return model


def _load_new(encoded_directory):
    rows, receipt, _ = eligibility._load_new_rows(encoded_directory)
    path = Path(encoded_directory) / "rasters.npy"; identity = receipt["artifacts"]["rasters.npy"]
    require(identity == {"bytes": path.stat().st_size, "sha256": file_sha(path)}, "Pinned new raster bytes changed")
    images = np.load(path, mmap_mode="r", allow_pickle=False)
    require(isinstance(images, np.memmap) and images.shape == (2439, 1, 96, 256) and images.dtype == np.float32 and not images.flags.writeable, "Read-only new literal rasters required")
    for image, row in zip(images, rows):
        require(bool(np.isfinite(image).all()) and sha(image.tobytes()) == row["modelPlaneSHA256"], "Encoded new row changed")
    return images, rows, receipt


def _fit(parent_data_directory, parent_fit_directory, new_data_directory, eligibility_directory, output, *, eligibility_receipt_sha256):
    directories = [Path(p) for p in (parent_data_directory, parent_fit_directory, new_data_directory, eligibility_directory)]
    require(all(p.is_absolute() and p.resolve() == p and p.is_dir() and not p.is_symlink() for p in directories), "Canonical input directories required")
    pd, pf, nd, ed = directories; torch.set_num_threads(4); torch.use_deterministic_algorithms(True); code = code_identity()
    parent_bytes = read(pf / "fit-receipt.json"); data_bytes = read(pd / "data-receipt.json")
    require(sha(parent_bytes) == PARENT_FIT_SHA256 and sha(data_bytes) == PARENT_DATA_SHA256, "Pinned parent fit/data changed")
    parent_receipt = parsed(parent_bytes, name="parent-control-fit"); parent._validate_fit_receipt(parent_receipt, parent.code_identity())
    eligible, eligible_receipt = eligibility.load_eligibility(ed, eligibility_receipt_sha256)
    new_images, new_rows, new_receipt = _load_new(nd)
    source_labels, legal_old_labels = parent_receipt["sourceVocabulary"], parent_receipt["legalOldLabels"]
    vocabulary = parent.core.make_vocabulary(source_labels, legal_old_labels)
    snapshot = {pf / "fit-receipt.json": PARENT_FIT_SHA256, pd / "data-receipt.json": PARENT_DATA_SHA256,
                ed / "eligibility-receipt.json": eligibility_receipt_sha256}
    for directory, receipt in ((nd, new_receipt), (ed, eligible_receipt)):
        receipt_name = "data-receipt.json" if directory == nd else "eligibility-receipt.json"
        snapshot[directory / receipt_name] = file_sha(directory / receipt_name)
        for name, identity in receipt["artifacts"].items():
            require(file_sha(directory / name) == identity["sha256"], "New training/eligibility artifact changed")
            snapshot[directory / name] = identity["sha256"]
    models, fold_inputs, plans, baselines = {}, {}, {}, {}
    for fold in FOLDS:
        images, metadata, receipt = parent_data.load_fit(pd, fold)
        require(sha(canonical(receipt)) == PARENT_DATA_SHA256, "Parent loader receipt changed")
        snapshot.update(parent._snapshot_fold(pd, fold, receipt)); p = parent_receipt["plans"][fold]
        plan_bytes = read(pf / p["path"]); require(sha(plan_bytes) == p["sha256"], "Pinned parent plan changed")
        snapshot[pf / p["path"]] = p["sha256"]; old_plan = parsed(plan_bytes, name="parent-slot-plan")
        control = parent_receipt["weights"][fold]["control"]; path = pf / control["path"]
        require(file_sha(path) == control["sha256"], "Pinned 102-way baseline weight bytes changed")
        snapshot[path] = control["sha256"]; baselines[fold] = {**control, "stateSHA256": parent_receipt["finalStateSHA256"][fold]["control"]}
        require(metadata["vocabulary"] == source_labels, "Parent fit/model vocabulary order changed")
        plans[fold] = build_transfer_plan(old_plan, metadata["rows"], new_rows, eligible["selectedOpaqueIDs"], source_labels)
        models[fold] = initialized_model(vocabulary); fold_inputs[fold] = (images, metadata["rows"])
    require(code_identity() == code and all(file_sha(p) == h for p, h in snapshot.items()), "Inputs changed before immutable run freeze")
    destination = parent.frozen._fresh_directory(Path(output)); (destination / "weights").mkdir(mode=0o700)
    parent.frozen._copy_code_snapshot(destination, code)
    write(destination / "frozen-protocol.md", read(ROOT / PROTOCOL))
    plan_bindings, fingerprints = {}, {}
    for fold in FOLDS:
        path = f"plans/{fold}.json"; content = canonical(plans[fold]); write(destination / path, content); plan_bindings[fold] = {"path": path, "sha256": sha(content)}
        rows = [{k: r[k] for k in ("opaqueID", "rasterSHA256", "normalizedGeometrySHA256")} for r in fold_inputs[fold][1]]
        rows += [{k: r[k] for k in ("opaqueID", "rasterSHA256", "normalizedGeometrySHA256")} for r in new_rows if r["opaqueID"] in plans[fold]["newRowMultiplicity"]]
        content = canonical({"version": FINGERPRINT_VERSION, "fold": fold, "rows": rows}); path = f"fit-fingerprints/{fold}.json"
        write(destination / path, content); fingerprints[fold] = {"path": path, "sha256": sha(content), "rows": len(rows)}
    manifest = {"version": VERSION, "scope": SCOPE, "protocolSHA256": PROTOCOL_SHA256, "modelVersion": parent.core.MODEL_VERSION,
        "parentDataReceiptSHA256": PARENT_DATA_SHA256, "parentFitReceiptSHA256": PARENT_FIT_SHA256,
        "newDataReceiptSHA256": eligibility.ENCODED_RECEIPT_SHA256, "eligibilityReceiptSHA256": eligibility_receipt_sha256,
        "sourceVocabulary": source_labels, "legalOldLabels": legal_old_labels, "initialStateSHA256": INITIAL_STATE_SHA256,
        "codeSHA256": code, "runtime": runtime_contract(), "recipe": RECIPE, "plans": plan_bindings, "fitFingerprints": fingerprints,
        "baselineWeights": baselines, "inputArtifactsSHA256": {str(p): h for p, h in snapshot.items()}, "selectedOpaqueIDs": eligible["selectedOpaqueIDs"],
        "selection": "final-epoch-only", "comparatorRefitted": False, "queryTruthOrPredictionsOpened": False}
    manifest_bytes = canonical(manifest); write(destination / "run-manifest.json", manifest_bytes)
    histories, ledgers, weights, final = {}, {}, {}, {}
    for fold in FOLDS:
        images, rows = fold_inputs[fold]
        histories[fold], ledgers[fold] = train_model(models[fold], images, new_images, rows, plans[fold], fold)
        payload = checkpoint_bytes(models[fold], source_labels); path = f"weights/{fold}.pt"; write(destination / path, payload)
        expected = state_digest(models[fold].state_dict()); require(expected != INITIAL_STATE_SHA256, "Candidate did not change from fresh state")
        require(state_digest(load_checkpoint(read(destination / path), source_labels, legal_old_labels).state_dict()) == expected, "Final saved/reloaded state changed")
        weights[fold] = {"path": path, "sha256": sha(payload)}; final[fold] = expected
    require(code_identity() == code and all(file_sha(p) == h for p, h in snapshot.items()), "Bound inputs/code changed during candidate fit")
    require(read(destination / "run-manifest.json") == manifest_bytes and sha(read(destination / "frozen-protocol.md")) == PROTOCOL_SHA256, "Immutable run manifest/protocol changed")
    for relative, expected in code.items():
        require(sha(read(destination / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Executed code snapshot changed")
    for bindings in (plan_bindings, fingerprints, weights):
        require(all(file_sha(destination / b["path"]) == b["sha256"] for b in bindings.values()), "Frozen artifact changed before success publication")
    result = {**manifest, "manifestSHA256": sha(manifest_bytes), "trainingHistory": histories, "augmentationLedger": ledgers,
              "weights": weights, "finalStateSHA256": final}
    _validate_fit_receipt(result, code); write(destination / "fit-receipt.json", canonical(result))
    return result


def fit(parent_data_directory, parent_fit_directory, new_data_directory, eligibility_directory, output, *, eligibility_receipt_sha256):
    destination = Path(output); existed = destination.exists()
    try:
        return _fit(parent_data_directory, parent_fit_directory, new_data_directory, eligibility_directory,
                    output, eligibility_receipt_sha256=eligibility_receipt_sha256)
    except Exception as error:
        if not existed and destination.is_dir() and not (destination / "fit-receipt.json").exists():
            try:
                write(destination / "failure.json", canonical({"version": VERSION, "status": "failed",
                    "exceptionType": type(error).__name__, "message": str(error), "resumeAllowed": False}))
            except Exception:
                pass  # Never replace the original fitting exception with a status-write failure.
        raise


def _validate_fit_receipt(receipt, code=None):
    require((receipt["version"], receipt["scope"], receipt["protocolSHA256"], receipt["modelVersion"], receipt["recipe"], receipt["initialStateSHA256"])
        == (VERSION, SCOPE, PROTOCOL_SHA256, parent.core.MODEL_VERSION, RECIPE, INITIAL_STATE_SHA256)
        and receipt["parentDataReceiptSHA256"] == PARENT_DATA_SHA256 and receipt["parentFitReceiptSHA256"] == PARENT_FIT_SHA256
        and receipt["newDataReceiptSHA256"] == eligibility.ENCODED_RECEIPT_SHA256 and digest(receipt["eligibilityReceiptSHA256"])
        and digest(receipt["manifestSHA256"]) and (code is None or receipt["codeSHA256"] == code), "Candidate receipt identity/source pins changed")
    parent.core.make_vocabulary(receipt["sourceVocabulary"], receipt["legalOldLabels"])
    require(receipt["selection"] == "final-epoch-only" and receipt["comparatorRefitted"] is False and receipt["queryTruthOrPredictionsOpened"] is False
        and len(receipt["selectedOpaqueIDs"]) == len(set(receipt["selectedOpaqueIDs"])) > 0, "Candidate source/selection claims changed")
    for key in ("plans", "fitFingerprints", "baselineWeights", "weights", "finalStateSHA256", "trainingHistory", "augmentationLedger"):
        require(set(receipt[key]) == set(FOLDS), "Candidate fold incomplete")
    for fold in FOLDS:
        require(receipt["weights"][fold]["path"] == f"weights/{fold}.pt" and digest(receipt["weights"][fold]["sha256"])
            and digest(receipt["finalStateSHA256"][fold]) and receipt["finalStateSHA256"][fold] != INITIAL_STATE_SHA256, "Candidate final weight binding changed")
        require(receipt["plans"][fold]["path"] == f"plans/{fold}.json" and digest(receipt["plans"][fold]["sha256"])
            and receipt["fitFingerprints"][fold]["path"] == f"fit-fingerprints/{fold}.json" and digest(receipt["fitFingerprints"][fold]["sha256"])
            and receipt["fitFingerprints"][fold]["rows"] == 6199 + len(receipt["selectedOpaqueIDs"]), "Frozen source-plan/fingerprint binding changed")
        ledger = receipt["augmentationLedger"][fold]
        require((ledger["epochs"], ledger["updates"], ledger["exposures"], ledger["replacements"], ledger["augmentationDrawStreamSHA256"])
            == (30, 1530, 195840, 33600, DRAW_STREAM_SHA256) and all(digest(v) for k, v in ledger.items() if k.endswith("SHA256")), "Completed replay/draw ledger changed")
        history = receipt["trainingHistory"][fold]; require(len(history) == 30, "Incomplete final epoch history")
        for epoch, row in enumerate(history, 1):
            require(set(row) == {"epoch", "meanLoss", "correct", "learningRate"} and row["epoch"] == epoch
                and type(row["correct"]) is int and 0 <= row["correct"] <= 6528
                and all(type(row[k]) in (int, float) and np.isfinite(row[k]) and row[k] >= 0 for k in ("meanLoss", "learningRate")), "Invalid finite candidate history")


def load_fitted_models(directory, expected_receipt_sha256):
    directory = Path(directory); require(digest(expected_receipt_sha256), "Caller-pinned candidate receipt required")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    content = read(directory / "fit-receipt.json"); require(sha(content) == expected_receipt_sha256, "Candidate fit receipt SHA changed")
    receipt = parsed(content, name="same-label-fit"); code = code_identity(); _validate_fit_receipt(receipt, code)
    require(receipt["runtime"] == runtime_contract() and sha(read(directory / "frozen-protocol.md")) == PROTOCOL_SHA256, "Candidate runtime/protocol changed")
    manifest_bytes = read(directory / "run-manifest.json"); manifest = parsed(manifest_bytes, name="same-label-manifest")
    require(sha(manifest_bytes) == receipt["manifestSHA256"] and all(receipt[k] == v for k, v in manifest.items()), "Immutable manifest changed")
    for relative, expected in code.items():
        require(sha(read(directory / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Executed candidate code changed")
    models = {}
    for fold in FOLDS:
        for key in ("plans", "fitFingerprints", "weights"):
            binding = receipt[key][fold]; require(file_sha(directory / binding["path"]) == binding["sha256"], "Frozen candidate artifact changed")
        model = load_checkpoint(read(directory / receipt["weights"][fold]["path"]), receipt["sourceVocabulary"], receipt["legalOldLabels"])
        require(state_digest(model.state_dict()) == receipt["finalStateSHA256"][fold], "Candidate final state changed")
        models[fold] = model.cpu().eval()
    return models, receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("parent-data", "parent-fit", "new-data", "eligibility", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--eligibility-receipt-sha256", required=True); a = p.parse_args()
    fit(a.parent_data, a.parent_fit, a.new_data, a.eligibility, a.output, eligibility_receipt_sha256=a.eligibility_receipt_sha256)


if __name__ == "__main__":
    main()
