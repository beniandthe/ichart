"""Fixed writer-blocked literal-102 versus domain-47 research fitting.

Only a chosen fold's fitting rasters/labels are opened. Sampling and shared
affine augmentation are frozen before optimization; success receipts are last.
No prior fitted model, query artifact, threshold or outcome selection is used.
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
from . import personal_hwrt_stroke_train as frozen
from . import personal_domain_reject as core
from . import personal_domain_reject_data as data

VERSION = "personal-domain-reject-fit-v1"
SCOPE = "research-only-writer-blocked-domain-reject-v1"
PLAN_VERSION = "personal-domain-reject-training-plan-v1"
PROTOCOL = "docs/personal-domain-reject-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "790ffda2fd09500a57f09da3f3dde3d18cfb8d8ad12c55b4850dbb97de43c552"
ROOT, ARMS, FOLDS = frozen.ROOT, ("control", "domainReject"), ("A16-to-B16", "B16-to-A16")
RECIPE = {**frozen.RECIPE, "sourceClasses": 102, "perClassExposuresPerEpoch": 64,
          "rejectExposuresPerEpoch": 3584, "optimizer": frozen.OPTIMIZATION}
CODE_PATHS = tuple(dict.fromkeys((*frozen.CODE_PATHS, PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_data.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_train.py",
    "recognition_ml/ichart_recognition_ml/research/personal_domain_reject_evaluate.py",
    "recognition_ml/tests/test_personal_domain_reject.py",
    "recognition_ml/tests/test_personal_domain_reject_data.py",
    "recognition_ml/tests/test_personal_domain_reject_train.py",
    "recognition_ml/tests/test_personal_domain_reject_evaluate.py")))
require, sha, digest = frozen._require, frozen._sha256, frozen._digest
read, parsed, file_sha = frozen._read, frozen._parsed, frozen._file_sha256
state_digest, tensor_sha = frozen._state_digest, frozen._tensor_sha256
stream_update, tensor_bytes, runtime_contract = frozen._stream_update, frozen._tensor_bytes, frozen._runtime_contract


def code_identity():
    result = {name: sha(read(ROOT / name, maximum=32 * 1024 * 1024)) for name in CODE_PATHS}
    result.update(data.code_identity())
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Fixed domain-reject protocol changed")
    frozen.code_identity()
    return result


def build_training_plan(rows, source_vocabulary):
    """Literal-class cycling, never balancing away the 56-way rejection pool."""
    require(len(rows) == 6199 and len(source_vocabulary) == len(set(source_vocabulary)) == 102
            and len({r["opaqueID"] for r in rows}) == len(rows), "Complete unique fitting rows required")
    pools = {label: sorted([i for i, row in enumerate(rows) if row["label"] == label],
        key=lambda i: (sha(("ichart-domain-reject-cycle-v1\0" + rows[i]["opaqueID"]).encode()), rows[i]["opaqueID"]))
        for label in source_vocabulary}
    require(all(pools.values()) and sum(map(len, pools.values())) == 6199, "Missing/unknown fitting class")
    require(all(len(pools[label]) == 32 for label in source_vocabulary[:97])
            and sum(len(pools[l]) for l in source_vocabulary[97:]) == 3095, "Fixed UJI32/HWRT3095 fitting counts changed")
    multiplicity = np.zeros(len(rows), dtype=np.int64); schedule = hashlib.sha256(); epochs = []
    for epoch in range(30):
        selected = [pool[(64 * epoch + j) % len(pool)] for label in source_vocabulary for pool in (pools[label],) for j in range(64)]
        order = np.random.default_rng(29 + epoch).permutation(selected).tolist()
        payload = np.asarray(order, dtype="<i8").tobytes(); stream_update(schedule, payload)
        for index in order:
            multiplicity[index] += 1
        require(len(order) == 6528, "Epoch exposure count changed")
        epochs.append({"epoch": epoch, "rowIndices": order, "permutationSHA256": sha(payload), "exposures": 6528, "updates": 51})
    require(bool((multiplicity > 0).all()), "A fitting source was never scheduled")
    coverage = {label: {"availableRows": len(pool), "uniqueRowsSeen": int(np.count_nonzero(multiplicity[pool])),
        "exposures": int(multiplicity[pool].sum()), "minimumMultiplicity": int(multiplicity[pool].min()),
        "maximumMultiplicity": int(multiplicity[pool].max())} for label, pool in pools.items()}
    require(all(c["exposures"] == 1920 and c["uniqueRowsSeen"] == c["availableRows"] for c in coverage.values()), "Class coverage changed")
    return {"version": PLAN_VERSION, "recipe": RECIPE, "sourceVocabulary": list(source_vocabulary),
        "trainingRows": 6199, "epochs": epochs, "scheduleSHA256": schedule.hexdigest(), "classCoverage": coverage,
        "rowMultiplicitySHA256": sha(multiplicity.astype("<i8").tobytes()),
        "sourceCycle": "SHA256(ichart-domain-reject-cycle-v1+NUL+opaqueID),opaqueID; (64*epoch+j)%classSize",
        "epochPermutation": "NumPy default_rng(29+zeroBasedEpoch)"}


def augment_images(images, draws):
    require(images.dtype == torch.float32 and images.shape[1:] == (1, 96, 256), "One-channel affine input required")
    fields = torch.cat((images, images.new_zeros((len(images), 4, 96, 256))), dim=1)
    before = tensor_sha(images)
    augmented = frozen.field.augment_stroke_fields(fields, draws)[:, :1].contiguous()
    require(tensor_sha(images) == before and bool(torch.isfinite(augmented).all()), "Frozen affine adapter changed input")
    return augmented


def _optimizers(models):
    optim = {a: torch.optim.AdamW(models[a].parameters(), lr=.001, weight_decay=.0001) for a in ARMS}
    sched = {a: torch.optim.lr_scheduler.CosineAnnealingLR(optim[a], T_max=30) for a in ARMS}
    return optim, sched


def paired_step(models, optimizers, images, source_targets, vocabulary):
    targets = core.map_targets(source_targets, vocabulary); input_sha = tensor_sha(images); reports = {}
    for arm in ARMS:
        model = models[arm]; model.train(); optimizers[arm].zero_grad(set_to_none=True); calls = []
        def hook(_module, args):
            calls.append(tensor_sha(args[0]))
        handle = model.register_forward_pre_hook(hook)
        try:
            embedding, logits = model(images)
        finally:
            handle.remove()
        width = 102 if arm == "control" else 47
        require(calls == [input_sha] and logits.shape == (len(images), width) and embedding.shape == (len(images), 128)
                and bool(torch.isfinite(logits).all()) and bool(torch.isfinite(embedding).all()), "Complete matched numerical forward changed")
        loss = F.cross_entropy(logits, targets[arm]); require(bool(torch.isfinite(loss)), "Nonfinite paired loss")
        loss.backward()
        require(all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in model.parameters()), "Missing/nonfinite gradient")
        optimizers[arm].step()
        require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values() if t.is_floating_point()), "Nonfinite updated state")
        reports[arm] = {"loss": float(loss.detach()), "correct": int((logits.detach().argmax(1) == targets[arm]).sum()),
                        "actualInputSHA256": calls[0]}
    require(tensor_sha(images) == input_sha, "Shared model input was mutated")
    return reports


def train_models(models, images, rows, source_vocabulary, vocabulary, plan, fold):
    require(plan["version"] == PLAN_VERSION and len(plan["epochs"]) == 30, "Frozen 30-epoch plan changed")
    optim, sched = _optimizers(models); generator = torch.Generator().manual_seed(29)
    label_index = {label: i for i, label in enumerate(source_vocabulary)}
    histories = {a: [] for a in ARMS}; draw_stream, input_stream, order_stream = (hashlib.sha256() for _ in range(3))
    actual = {a: hashlib.sha256() for a in ARMS}; updates = 0
    for epoch in plan["epochs"]:
        order = epoch["rowIndices"]; order_bytes = np.asarray(order, dtype="<i8").tobytes()
        require(len(order) == 6528 and sha(order_bytes) == epoch["permutationSHA256"], "Frozen epoch order changed")
        stream_update(order_stream, order_bytes); totals = {a: {"loss": 0.0, "correct": 0} for a in ARMS}
        for offset in range(0, len(order), 128):
            indices = order[offset:offset + 128]; require(len(indices) == 128, "Partial batch forbidden")
            source = torch.from_numpy(np.array(images[indices], dtype=np.float32, copy=True, order="C"))
            draws = frozen.field.sample_affine_draws(128, generator); stream_update(draw_stream, tensor_bytes(draws))
            augmented = augment_images(source, draws); payload = tensor_bytes(augmented); stream_update(input_stream, payload)
            targets = torch.tensor([label_index[rows[i]["label"]] for i in indices], dtype=torch.long)
            reports = paired_step(models, optim, augmented, targets, vocabulary)
            for arm in ARMS:
                require(reports[arm]["actualInputSHA256"] == sha(payload), "Actual input proof changed")
                stream_update(actual[arm], payload); totals[arm]["loss"] += reports[arm]["loss"] * 128; totals[arm]["correct"] += reports[arm]["correct"]
            updates += 1
        for arm in ARMS:
            sched[arm].step()
            histories[arm].append({"epoch": epoch["epoch"] + 1, "meanLoss": totals[arm]["loss"] / 6528,
                "correct": totals[arm]["correct"], "learningRate": float(sched[arm].get_last_lr()[0])})
        print(canonical({"fold": fold, "epoch": epoch["epoch"] + 1, "updatesPerArm": updates,
                         "exposuresPerArm": (epoch["epoch"] + 1) * 6528, "arms": {a: histories[a][-1] for a in ARMS}}).decode(), flush=True)
    require(updates == 1530 and all(s.last_epoch == 30 for s in sched.values()) and order_stream.hexdigest() == plan["scheduleSHA256"]
            and {h.hexdigest() for h in actual.values()} == {input_stream.hexdigest()}, "Matched completed training counts/streams changed")
    ledger = {a: {"epochs": 30, "updates": updates, "exposures": 195840, "scheduleSHA256": plan["scheduleSHA256"],
        "batchOrderStreamSHA256": order_stream.hexdigest(), "augmentationDrawStreamSHA256": draw_stream.hexdigest(),
        "augmentedImageStreamSHA256": input_stream.hexdigest(), "actualForwardInputStreamSHA256": actual[a].hexdigest()} for a in ARMS}
    return histories, ledger


def _feature_state(model):
    return {n: t for n, t in model.state_dict().items() if "classifier" not in n.split(".")}


def initialized_models(vocabulary):
    models = core.make_matched_models(vocabulary)
    feature_hashes = {a: state_digest(_feature_state(models[a])) for a in ARMS}
    require(len(set(feature_hashes.values())) == 1, "Matched complete feature state differs")
    control, candidate = (models[a].classifier for a in ARMS)
    legal = torch.tensor(vocabulary.legal_source_indices, dtype=torch.long)
    forbidden = torch.tensor(vocabulary.forbidden_source_indices, dtype=torch.long)
    require(torch.equal(candidate.weight[:46], control.weight.index_select(0, legal))
            and torch.equal(candidate.bias[:46], control.bias.index_select(0, legal)), "Legal classifier initialization differs")
    require(len(forbidden) == 56 and torch.equal(candidate.weight[46], control.weight.index_select(0, forbidden).mean(0))
            and torch.equal(candidate.bias[46], control.bias.index_select(0, forbidden).mean(0)), "Reject arithmetic mean initialization differs")
    return models, {"featureStateSHA256": feature_hashes[ARMS[0]],
                    "armStateSHA256": {a: state_digest(m.state_dict()) for a, m in models.items()},
                    "legalClassifierRowsExact": True, "rejectMean56Exact": True}


def checkpoint_bytes(model, arm, output_labels):
    require(isinstance(model, core.DomainRejectModel) and arm in ARMS and model.arm == arm
            and model.label_count == len(output_labels) == (102 if arm == "control" else 47), "Checkpoint arm/width changed")
    buffer = io.BytesIO()
    torch.save({"version": VERSION, "modelVersion": core.MODEL_VERSION, "arm": arm, "labelCount": len(output_labels),
        "outputVocabularySHA256": sha(canonical(list(output_labels))), "stateDict": model.state_dict()}, buffer)
    return buffer.getvalue()


def load_checkpoint(payload, arm, output_labels, vocabulary):
    try:
        value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    except Exception as error:
        raise ValueError("Invalid domain-reject checkpoint") from error
    require(isinstance(value, dict) and set(value) == {"version", "modelVersion", "arm", "labelCount", "outputVocabularySHA256", "stateDict"}
            and (value["version"], value["modelVersion"], value["arm"], value["labelCount"], value["outputVocabularySHA256"])
            == (VERSION, core.MODEL_VERSION, arm, len(output_labels), sha(canonical(list(output_labels)))), "Domain-reject checkpoint identity changed")
    model = core.make_matched_models(vocabulary)[arm]
    try:
        model.load_state_dict(value["stateDict"], strict=True)
    except (RuntimeError, ValueError, TypeError) as error:
        raise ValueError("Domain-reject checkpoint state changed") from error
    require(all(bool(torch.isfinite(t).all()) for t in model.state_dict().values() if t.is_floating_point()), "Nonfinite domain-reject checkpoint")
    return model


def _snapshot_fold(directory, fold, receipt):
    result = {}
    for name in data.fit_artifact_paths(fold):
        identity = receipt["artifacts"][name]; path = directory / name
        require(identity == {"bytes": path.stat().st_size, "sha256": file_sha(path)}, "Fold fit artifact changed")
        result[path] = identity["sha256"]
    return result


def fit(data_directory, protocol, output):
    directory, protocol = Path(data_directory), frozen._regular(Path(protocol), maximum=2 * 1024 * 1024)
    require(directory.is_absolute() and directory.resolve() == directory and directory.is_dir() and not directory.is_symlink(), "Canonical data directory required")
    protocol_bytes = protocol.read_bytes()
    require(sha(protocol_bytes) == PROTOCOL_SHA256 and protocol_bytes == read(ROOT / PROTOCOL), "Frozen protocol changed")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True); code = code_identity()
    receipt_bytes = read(directory / "data-receipt.json"); data_receipt = parsed(receipt_bytes, name="domain-reject-data")
    source_labels, legal_labels, candidate_labels = (data_receipt[k] for k in ("sourceVocabulary", "legalOldLabels", "candidateLabels"))
    vocabulary = core.make_vocabulary(tuple(source_labels), tuple(legal_labels))
    output = frozen._fresh_directory(Path(output)); (output / "weights").mkdir(mode=0o700)
    frozen._write_exclusive(output / "frozen-protocol.md", protocol_bytes); frozen._write_exclusive(output / "data-receipt.json", receipt_bytes)
    frozen._copy_code_snapshot(output, code)
    snapshot = {directory / "data-receipt.json": sha(receipt_bytes)}
    plans, initial, histories, ledgers, weights, final = ({} for _ in range(6))
    for fold in FOLDS:
        images, metadata, receipt = data.load_fit(directory, fold)
        require(receipt == data_receipt and metadata["fold"] == fold and metadata["vocabulary"] == source_labels
                and images.shape == (6199, 1, 96, 256) and images.dtype == np.float32 and isinstance(images, np.memmap)
                and not images.flags.writeable, "Chosen fold training seam changed")
        rows = metadata["rows"]; plan = build_training_plan(rows, tuple(source_labels)); snapshot.update(_snapshot_fold(directory, fold, receipt))
        models, initial[fold] = initialized_models(vocabulary)
        plan.update({"fold": fold, "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code,
            "dataReceiptSHA256": sha(receipt_bytes), "fitArtifactsSHA256": {str(p.relative_to(directory)): h for p, h in snapshot.items() if fold in p.parts},
            "initialization": initial[fold]})
        plan_bytes = canonical(plan); name = f"training-plans/{fold}.json"; frozen._write_exclusive(output / name, plan_bytes)
        plans[fold] = {"path": name, "sha256": sha(plan_bytes)}
        histories[fold], ledgers[fold] = train_models(models, images, rows, tuple(source_labels), vocabulary, plan, fold)
        weights[fold], final[fold] = {}, {}
        for arm in ARMS:
            labels = source_labels if arm == "control" else candidate_labels
            payload = checkpoint_bytes(models[arm], arm, labels); restored = load_checkpoint(payload, arm, labels, vocabulary)
            expected = state_digest(models[arm].state_dict())
            require(state_digest(restored.state_dict()) == expected and expected != initial[fold]["armStateSHA256"][arm], "Final checkpoint reload/change proof failed")
            name = f"weights/{fold}-{arm}.pt"; frozen._write_exclusive(output / name, payload)
            weights[fold][arm] = {"path": name, "sha256": sha(payload)}; final[fold][arm] = expected
    require(initial[FOLDS[0]] == initial[FOLDS[1]], "Fresh initial states differed between writer folds")
    require(code_identity() == code and all(file_sha(p) == h for p, h in snapshot.items()), "Bound fitting inputs/code changed")
    for relative, expected in code.items():
        require(sha(read(output / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Executed code snapshot changed")
    require(read(output / "data-receipt.json") == receipt_bytes and read(output / "frozen-protocol.md") == protocol_bytes
            and all(sha(read(output / p["path"])) == p["sha256"] for p in plans.values()), "Frozen source/plan snapshot changed")
    for fold in FOLDS:
        for arm in ARMS:
            payload = read(output / weights[fold][arm]["path"], maximum=256 * 1024 * 1024)
            labels = source_labels if arm == "control" else candidate_labels
            require(sha(payload) == weights[fold][arm]["sha256"]
                    and state_digest(load_checkpoint(payload, arm, labels, vocabulary).state_dict()) == final[fold][arm], "Final disk checkpoint reload changed")
    result = {"version": VERSION, "scope": SCOPE, "protocolSHA256": PROTOCOL_SHA256, "modelVersion": core.MODEL_VERSION,
        "codeSHA256": code, "dataReceiptSHA256": sha(receipt_bytes), "sourceVocabulary": source_labels, "legalOldLabels": legal_labels,
        "candidateLabels": candidate_labels, "runtime": runtime_contract(), "recipe": RECIPE, "folds": list(FOLDS), "plans": plans,
        "initialization": initial, "trainingHistory": histories, "augmentationLedger": ledgers, "weights": weights,
        "finalStateSHA256": final, "selection": "final-epoch-only"}
    _validate_fit_receipt(result, code)
    frozen._write_exclusive(output / "fit-receipt.json", canonical(result))
    return result


def _validate_fit_receipt(receipt, code=None):
    require(set(receipt) == {"version", "scope", "protocolSHA256", "modelVersion", "codeSHA256", "dataReceiptSHA256", "sourceVocabulary",
        "legalOldLabels", "candidateLabels", "runtime", "recipe", "folds", "plans", "initialization", "trainingHistory", "augmentationLedger",
        "weights", "finalStateSHA256", "selection"}, "Fit receipt schema changed")
    require((receipt["version"], receipt["scope"], receipt["protocolSHA256"], receipt["modelVersion"], receipt["recipe"], receipt["folds"], receipt["selection"])
            == (VERSION, SCOPE, PROTOCOL_SHA256, core.MODEL_VERSION, RECIPE, list(FOLDS), "final-epoch-only")
            and digest(receipt["dataReceiptSHA256"]) and (code is None or receipt["codeSHA256"] == code), "Fit identity/code/recipe changed")
    core.make_vocabulary(tuple(receipt["sourceVocabulary"]), tuple(receipt["legalOldLabels"]))
    require(receipt["candidateLabels"] == receipt["legalOldLabels"] + list(frozen.NOVEL_LABELS) + ["REJECT"], "Candidate labels changed")
    for key in ("plans", "initialization", "trainingHistory", "augmentationLedger", "weights", "finalStateSHA256"):
        require(set(receipt[key]) == set(FOLDS), "Incomplete writer fold")
    for fold in FOLDS:
        require(receipt["plans"][fold]["path"] == f"training-plans/{fold}.json" and digest(receipt["plans"][fold]["sha256"]), "Training plan binding changed")
        initialization = receipt["initialization"][fold]
        require(set(initialization) == {"featureStateSHA256", "armStateSHA256", "legalClassifierRowsExact", "rejectMean56Exact"}
                and initialization["legalClassifierRowsExact"] is True and initialization["rejectMean56Exact"] is True
                and digest(initialization["featureStateSHA256"])
                and set(initialization["armStateSHA256"]) == set(ARMS) and all(digest(x) for x in initialization["armStateSHA256"].values()), "Initial feature/arm identity changed")
        for key in ("trainingHistory", "augmentationLedger", "weights", "finalStateSHA256"):
            require(set(receipt[key][fold]) == set(ARMS), "Incomplete fitted arm")
        for arm in ARMS:
            require(receipt["weights"][fold][arm]["path"] == f"weights/{fold}-{arm}.pt" and digest(receipt["weights"][fold][arm]["sha256"])
                    and digest(receipt["finalStateSHA256"][fold][arm])
                    and receipt["finalStateSHA256"][fold][arm] != initialization["armStateSHA256"][arm], "Final weight binding changed")
            ledger = receipt["augmentationLedger"][fold][arm]
            require(set(ledger) == {"epochs", "updates", "exposures", "scheduleSHA256", "batchOrderStreamSHA256", "augmentationDrawStreamSHA256",
                    "augmentedImageStreamSHA256", "actualForwardInputStreamSHA256"} and (ledger["epochs"], ledger["updates"], ledger["exposures"]) == (30, 1530, 195840)
                    and all(digest(v) for k, v in ledger.items() if k not in {"epochs", "updates", "exposures"})
                    and ledger["scheduleSHA256"] == ledger["batchOrderStreamSHA256"]
                    and ledger["augmentedImageStreamSHA256"] == ledger["actualForwardInputStreamSHA256"], "Completed matched input/count ledger changed")
            history = receipt["trainingHistory"][fold][arm]
            require(len(history) == 30, "Incomplete final epoch history")
            for epoch, h in enumerate(history, 1):
                require(set(h) == {"epoch", "meanLoss", "correct", "learningRate"} and h["epoch"] == epoch
                        and type(h["correct"]) is int and 0 <= h["correct"] <= 6528
                        and all(type(h[k]) in (int, float) and np.isfinite(h[k]) and h[k] >= 0 for k in ("meanLoss", "learningRate")), "Invalid finite epoch history")
        require(receipt["augmentationLedger"][fold][ARMS[0]] == receipt["augmentationLedger"][fold][ARMS[1]], "Matched arm ledgers differ")
    require(receipt["initialization"][FOLDS[0]] == receipt["initialization"][FOLDS[1]], "Fold initial states differ")


def load_fitted_models(directory, expected_receipt_sha256):
    """Blind loader: fit receipt, safe snapshots and final weights, never data."""
    directory = Path(directory); require(digest(expected_receipt_sha256), "Caller-pinned fit receipt required")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    payload = read(directory / "fit-receipt.json", maximum=32 * 1024 * 1024)
    require(sha(payload) == expected_receipt_sha256, "Fit receipt SHA changed")
    receipt = parsed(payload, name="domain-reject-fit"); code = code_identity(); _validate_fit_receipt(receipt, code)
    require(receipt["runtime"] == runtime_contract() and sha(read(directory / "frozen-protocol.md")) == PROTOCOL_SHA256, "Runtime/protocol snapshot changed")
    data_bytes = read(directory / "data-receipt.json"); require(sha(data_bytes) == receipt["dataReceiptSHA256"], "Data receipt snapshot changed")
    data_receipt = parsed(data_bytes, name="copied-source-only-data-receipt")
    require(all(data_receipt[k] == receipt[k] for k in ("sourceVocabulary", "legalOldLabels", "candidateLabels")), "Source vocabulary lineage changed")
    for relative, expected in code.items():
        require(sha(read(directory / "executed-code" / relative, maximum=32 * 1024 * 1024)) == expected, "Executed code snapshot changed")
    vocabulary = core.make_vocabulary(tuple(receipt["sourceVocabulary"]), tuple(receipt["legalOldLabels"])); models = {}
    for fold in FOLDS:
        p = receipt["plans"][fold]; require(sha(read(directory / p["path"])) == p["sha256"], "Frozen training plan changed")
        models[fold] = {}
        for arm in ARMS:
            w = receipt["weights"][fold][arm]; payload = read(directory / w["path"], maximum=256 * 1024 * 1024)
            require(sha(payload) == w["sha256"], "Checkpoint bytes changed")
            labels = receipt["sourceVocabulary"] if arm == "control" else receipt["candidateLabels"]
            model = load_checkpoint(payload, arm, labels, vocabulary)
            require(state_digest(model.state_dict()) == receipt["finalStateSHA256"][fold][arm], "Saved/reloaded state changed")
            models[fold][arm] = model.cpu().eval()
    return models, receipt


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", type=Path, required=True); p.add_argument("--protocol", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args(); fit(a.data, a.protocol, a.output)


if __name__ == "__main__":
    main()
