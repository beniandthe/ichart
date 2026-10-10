"""One fixed native-HASY auxiliary fit, then matched UJI97 fine-tuning.

Local offline research only. Shared phase/augmentation helpers retain the prior
fixed training behavior. No development/reserved source is rasterized here.
"""
from __future__ import annotations

import argparse
import copy
import io
import math
import re
from pathlib import Path

import numpy as np
import torch
from torch import nn

from . import personal_broad_transfer as broad
from .personal_cross_writer_contrastive import (_json_bytes, _new_output, _regular_file, _sha256,
    _state_digest, _training_feature_order, _training_feature_payload, _write_exclusive,
    epoch_batch_plan, select_training_samples)
from .personal_visual_encoder import PersonalVisualEncoder, encode_samples, infer
from .uji_personal import SOURCE_SHA256, Sample, load_official_source

FIT_VERSION = "personal-native-shape-transfer-fit-v1"
SCOPE = "fixed-paired-native-shape-transfer-offline-research-only"
ARMS = ("uji97ReplayPretrain", "hasy369NativePretrain")
SEED, PRETRAIN_ROWS, FINETUNE_ROWS = 29, 31744, 6208
PROTOCOL_PATH = "docs/personal-native-shape-transfer-protocol-2026-10-01.md"
PROTOCOL_DOCUMENT_SHA256 = "54f426735c0f364bb466329298c5649f6b1f8928aab1be19d45bba9b48e509fb"
SALT = b"native-shape-transfer-v1"
pretrain_batch_plan, reset_original_head = broad.pretrain_batch_plan, broad.reset_original_head
_train_phase, _runtime = broad._train_phase, broad._runtime
def require(condition, message):
    if not condition: raise ValueError(message)


def frozen_protocol():
    return {"arms": list(ARMS), "architecture": "original-PersonalVisualEncoder", "seed": 29,
        "cpuThreads": 4, "deterministicAlgorithms": True, "loss": "cross-entropy-only", "optimizer": "AdamW",
        "learningRate": .001, "weightDecay": .0001, "auxiliaryHeads": [97, 369],
        "auxiliaryInitialization": "independent-seed29-Linear128-n", "selectionSalt": SALT.decode(),
        "pretrain": {"epochs": 5, "rows": 31744, "batchesPerEpoch": 248, "batchRows": 128, "cosineTMax": 5,
            "ujiPerClass": 327, "ujiExtraClasses": 25, "hasyPerClass": 86, "hasyExtraClasses": 10},
        "headReset": "discard-auxiliary-head-restore-exact-original-seed29-head97-preserve-trunk-projection-BN",
        "finetune": {"epochs": 30, "rows": 6208, "batchesPerEpoch": 32, "batchRows": 194, "cosineTMax": 30},
        "updatesPerArm": 2200, "augmentation": "original-affine-seed29-independent-per-arm-per-phase",
        "selection": "fixed-final-epoch-only-no-development-selection", "productionEligible": False,
        "commercialTrainingEligibilityEstablished": False}


def code_identity():
    from . import hasy_native_training_source as hasy
    root = Path(__file__).resolve().parents[3]
    result = dict(broad.code_identity())
    for path in (PROTOCOL_PATH, "recognition_ml/ichart_recognition_ml/research/personal_native_shape_transfer.py",
        "recognition_ml/tests/test_personal_native_shape_transfer.py", "recognition_ml/ichart_recognition_ml/research/hasy_native_training_source.py",
        "recognition_ml/tests/test_hasy_native_training_source.py"):
        result[path] = _sha256((root / path).read_bytes())
    require(result[PROTOCOL_PATH] == PROTOCOL_DOCUMENT_SHA256, "Frozen native-shape protocol changed")
    if hasattr(hasy, "code_identity"): result.update(hasy.code_identity())
    return result


def initialized_models(vocabulary):
    require(len(vocabulary) == 97 and tuple(vocabulary) == tuple(sorted(set(vocabulary))), "Exact ordered vocabulary97 required")
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(29); original = PersonalVisualEncoder(97)
    initial = {k: v.detach().clone() for k, v in original.state_dict().items()}
    models = {arm: copy.deepcopy(original) for arm in ARMS}
    hashes = {arm: _state_digest(model.state_dict()) for arm, model in models.items()}
    require(len(set(hashes.values())) == 1, "Initial trunks differ")
    return models, initial, {"sha256": hashes[ARMS[0]], "armSHA256": hashes}


def install_auxiliary_head(model, count):
    require(type(count) is int and count in (97, 369), "Native auxiliary head size changed")
    with torch.random.fork_rng(devices=[]):
        torch.manual_seed(29); model.classifier = nn.Linear(128, count)
    return {k: v.detach().clone() for k, v in model.classifier.state_dict().items()}


def replay_row_indices(training):
    training = tuple(training); labels = sorted({s.label for s in training if isinstance(s, Sample)})
    writers = {s.writer for s in training if isinstance(s, Sample)}
    require(len(training) == 6208 and len(labels) == 97 and len(writers) == 32
        and all(isinstance(s, Sample) and re.fullmatch(r"trn_(?:UJI|UPV)_W[0-9]{2}", s.writer)
            and type(s.session) is int and s.session in (1, 2) for s in training)
        and len({s.identity for s in training}) == 6208
        and {(s.writer, s.session, s.label) for s in training} == {(w, t, c) for w in writers for t in (1, 2) for c in labels}
        and training == tuple(sorted(training, key=lambda s: s.identity)), "Replay requires canonical complete training32 grid")
    extras = set(sorted(labels, key=lambda c: (_sha256(SALT + b"\0" + c.encode()), c))[:25])
    result = []
    for label in labels:
        sources = sorted([i for i, s in enumerate(training) if s.label == label],
            key=lambda i: (_sha256(SALT + b"\0" + training[i].identity.encode()), training[i].identity))
        require(len(sources) == 64, "UJI replay class lost a writer/session")
        result.extend(sources[n % 64] for n in range(327 + (label in extras)))
    require(len(result) == 31744 and len(set(result)) == 6208, "UJI replay exposure count changed")
    return tuple(result)


def validate_matching(histories, plan=None):
    for phase, epochs, updates, samples in (("pretrain", 5, 248, 31744), ("finetune", 30, 32, 6208)):
        left, right = (histories[arm][phase] for arm in ARMS)
        require(len(left) == len(right) == epochs, "Missing phase epochs")
        for epoch, (control, candidate) in enumerate(zip(left, right)):
            require(all(control[k] == candidate[k] for k in ("phase", "epoch", "samples", "updates", "learningRate",
                "batchPlanSHA256", "augmentationGeneratorTraceSHA256")) and control["phase"] == phase
                and control["epoch"] == epoch + 1 and control["updates"] == updates and control["samples"] == samples
                and math.isclose(control["learningRate"], .001 * (1 + math.cos(math.pi * epoch / epochs)) / 2, abs_tol=1e-15)
                and all(np.isfinite(r["crossEntropyLoss"]) and r["crossEntropyLoss"] >= 0 for r in (control, candidate))
                and (phase != "finetune" or control["augmentationInputsSHA256"] == candidate["augmentationInputsSHA256"]), "Unmatched/nonfinite fixed training phase")
            if plan is not None:
                require(control["batchPlanSHA256"] == plan["pretrainBatchPlanSHA256" if phase == "pretrain" else "epochBatchPlanSHA256"][epoch], "Actual batch plan differs from frozen plan")


def _checkpoint(model, arm, phase, vocabulary, plan):
    stream = io.BytesIO(); torch.save({"version": FIT_VERSION, "arm": arm, "phase": phase,
        "finalEpoch": 5 if phase == "pretrain" else 30, "sourceSHA256": SOURCE_SHA256,
        "protocolSHA256": PROTOCOL_DOCUMENT_SHA256, "fitPlanSHA256": _sha256(_json_bytes(plan)),
        "initialStateSHA256": plan["initialState"]["sha256"], "vocabulary": list(vocabulary), "state_dict": model.state_dict()}, stream)
    return stream.getvalue()


def fit(source, hasy_dir, hasy_receipt_sha, output):
    from .hasy_native_training_source import load_prepared
    root = Path(__file__).resolve().parents[3]; source = _regular_file(Path(source), "UJI source")
    protocol_bytes = (root / PROTOCOL_PATH).read_bytes(); code = code_identity()
    require(_sha256(source.read_bytes()) == SOURCE_SHA256 and broad._valid_hash(hasy_receipt_sha), "Source/receipt pin changed")
    output = Path(output); hasy_dir = Path(hasy_dir)
    require(output.is_absolute() and root not in output.parents and output != hasy_dir
        and hasy_dir not in output.parents and output not in hasy_dir.parents and source not in output.parents, "Aliased/repository fit output")
    records = load_official_source(source); training, writers, development, reserved = select_training_samples(records)
    vocabulary = tuple(sorted({s.label for s in training})); replay = replay_row_indices(training)
    hasy_images, hasy_targets, hasy_evidence = load_prepared(hasy_dir, hasy_receipt_sha)
    native = hasy_evidence["nativeClassIDs"]
    extras = set(sorted(native, key=lambda c: (_sha256(SALT + b"\0" + str(c).encode()), str(c)))[:10])
    require(len(native) == len(set(native)) == 369 and hasy_images.shape == (31744, 1, 96, 256)
        and hasy_images.dtype == np.uint8 and hasy_targets.shape == (31744,) and hasy_targets.dtype == np.dtype("<i8")
        and set(hasy_targets.tolist()) == set(range(369)) and hasy_evidence["receiptSHA256"] == hasy_receipt_sha
        and np.bincount(hasy_targets, minlength=369).tolist() == [86 + (c in extras) for c in native], "Native source contract changed")
    hasy_targets = torch.from_numpy(np.array(hasy_targets, dtype=np.int64, copy=True))
    pre_plans = tuple(pretrain_batch_plan(e) for e in range(5)); fine_plans = tuple(epoch_batch_plan(records, e) for e in range(30))
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    models, initial_state, initial = initialized_models(vocabulary)
    images, raster_hashes = encode_samples(training, writers)
    require(images.shape == (6208, 1, 96, 256) and images.dtype == torch.uint8, "Training-only UJI raster contract changed")
    targets = torch.tensor([vocabulary.index(s.label) for s in training], dtype=torch.long)
    replay_targets = targets[list(replay)]
    inputs = [{"sourceID": s.identity, "writer": s.writer, "session": s.session, "label": s.label, "rasterSHA256": h}
        for s, h in zip(training, raster_hashes)]; _training_feature_order(inputs)
    auxiliary_initial = {arm: install_auxiliary_head(models[arm], count) for arm, count in zip(ARMS, (97, 369))}
    plan = {"version": FIT_VERSION, "scope": SCOPE, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": PROTOCOL_DOCUMENT_SHA256,
        "protocolEnvelope": {"markdownProtocolSHA256": PROTOCOL_DOCUMENT_SHA256, "sourceSHA256": SOURCE_SHA256, "settings": frozen_protocol()},
        "codeSHA256": code, "contract": frozen_protocol(), "initialState": initial, "runtime": _runtime(),
        "trainingWriters": list(writers), "developmentWriters": list(development), "reservedWriters": list(reserved),
        "trainingSamples": 6208, "vocabulary": list(vocabulary), "trainingInputs": inputs, "trainingInputsSHA256": _sha256(_json_bytes(inputs)),
        "trainingRasterSHA256": _sha256(images.numpy().tobytes()), "replayRowIndices": list(replay),
        "replayExposureCounts": {c: int((replay_targets == vocabulary.index(c)).sum()) for c in vocabulary},
        "replayDistinctSources": len(set(replay)), "replayRepeatedExposures": 31744 - len(set(replay)),
        "pretrainBatchPlanSHA256": [_sha256(_json_bytes(p)) for p in pre_plans], "epochBatchPlanSHA256": [_sha256(_json_bytes(p)) for p in fine_plans],
        "auxiliaryInitialStateSHA256": {a: _state_digest(v) for a, v in auxiliary_initial.items()},
        "hasyReceiptSHA256": hasy_receipt_sha, "hasyPreparedReceiptSHA256": hasy_receipt_sha, "hasyTrainingSource": hasy_evidence,
        "hasySelectedAdaptedRasterHashesSHA256": hasy_evidence["selectedAdaptedRasterHashesSHA256"],
        "roleGuards": {"rasterizedUJIWriterRole": "training-32-only", **{k: False for k in ("developmentRastersConstructed",
            "reservedRastersConstructed", "developmentEvaluatedDuringFit", "reservedEvaluatedDuringFit", "privateInkUsed",
            "productionEligible", "commercialTrainingEligibilityEstablished", "calibratedAcceptance", "appOrProfileMutated")}}}
    output = _new_output(output)
    for name in ("weights", "training-features"): (output / name).mkdir(mode=0o700)
    _write_exclusive(output / "protocol.md", protocol_bytes); _write_exclusive(output / "fit-plan.json", _json_bytes(plan))
    histories, weights, states, feature_hashes, changed, resets, pre_states, pre_weights, aux_weights = ({ } for _ in range(9))
    for arm in ARMS:
        model = models[arm]; initial_pre = _state_digest(model.state_dict())
        stream = io.BytesIO(); torch.save(auxiliary_initial[arm], stream); auxiliary_payload = stream.getvalue()
        _write_exclusive(output / "weights" / f"{arm}-aux-initial.pt", auxiliary_payload); aux_weights[arm] = _sha256(auxiliary_payload)
        pre_images, pre_targets, indices = ((images, replay_targets, replay) if arm == ARMS[0] else (hasy_images, hasy_targets, None))
        pre_history = _train_phase(model, arm, pre_images, pre_targets, pre_plans, "pretrain", indices)
        pre_states[arm] = {"initialSHA256": initial_pre, "finalSHA256": _state_digest(model.state_dict()),
            "auxiliaryInitialSHA256": _state_digest(auxiliary_initial[arm]), "auxiliaryFinalSHA256": _state_digest(model.classifier.state_dict())}
        pre_states[arm]["changedTrunkParameterNames"] = [k for k, v in model.named_parameters()
            if not k.startswith("classifier.") and not torch.equal(v.detach(), initial_state[k])]
        require(pre_states[arm]["initialSHA256"] != pre_states[arm]["finalSHA256"]
            and pre_states[arm]["changedTrunkParameterNames"], "Auxiliary trunk parameters never changed")
        data = _checkpoint(model, arm, "pretrain", vocabulary if arm == ARMS[0] else native, plan)
        _write_exclusive(output / "weights" / f"{arm}-pretrain.pt", data); pre_weights[arm] = _sha256(data)
        trunk = {k: v.clone() for k, v in model.state_dict().items() if not k.startswith("classifier.")}
        reset_original_head(model, initial_state)
        resets[arm] = {"trunkPreserved": all(torch.equal(v, model.state_dict()[k]) for k, v in trunk.items()),
            "full97HeadEqualsOriginal": all(torch.equal(model.state_dict()[k], initial_state[k]) for k in ("classifier.weight", "classifier.bias"))}
        require(all(resets[arm].values()), "Auxiliary reset changed trunk or retained a trained head")
        fine_history = _train_phase(model, arm, images, targets, fine_plans, "finetune")
        histories[arm] = {"pretrain": pre_history, "finetune": fine_history}
        changed[arm] = [k for k, v in model.named_parameters() if not torch.equal(v.detach(), initial_state[k])]
        require(changed[arm], "Final encoder did not learn")
        states[arm] = _state_digest(model.state_dict()); data = _checkpoint(model, arm, "finetune", vocabulary, plan)
        _write_exclusive(output / "weights" / f"{arm}.pt", data); weights[arm] = _sha256(data)
        features, _ = infer(model, images); data = _training_feature_payload(features, inputs)
        _write_exclusive(output / "training-features" / f"{arm}.npz", data); feature_hashes[arm] = _sha256(data)
    validate_matching(histories, plan)
    _, _, after_hasy = load_prepared(hasy_dir, hasy_receipt_sha)
    require(after_hasy == hasy_evidence and _sha256(source.read_bytes()) == SOURCE_SHA256 and code_identity() == code
        and (root / PROTOCOL_PATH).read_bytes() == protocol_bytes and _sha256(images.numpy().tobytes()) == plan["trainingRasterSHA256"], "Sources/code/protocol changed during fitting")
    receipt = {**plan, "arms": list(ARMS), "fitPlanSHA256": _sha256(_json_bytes(plan)), "trainingHistory": histories,
        "changedParameterNames": changed, "parametersChanged": {a: bool(changed[a]) for a in ARMS}, "headReset": resets,
        "pretrainStates": pre_states, "pretrainWeightsSHA256": pre_weights, "auxiliaryInitialWeightsSHA256": aux_weights,
        "weightFiles": {a: f"weights/{a}.pt" for a in ARMS}, "weightsSHA256": weights, "finalStateSHA256": states,
        "trainingFeatureFiles": {a: f"training-features/{a}.npz" for a in ARMS}, "trainingFeaturesSHA256": feature_hashes,
        "trainingFeatureOrderSHA256": _sha256(_json_bytes(_training_feature_order(inputs))),
        "matchedInitialTensors": True, "matchedBatchPlans": True, "matchedAugmentationDraws": True,
        "selection": "fixed-final-epoch-only-no-development-selection", "updatesPerArm": 2200}
    _write_exclusive(output / "fit-receipt.json", _json_bytes(receipt)); return receipt


def _load_fit_receipt(output, expected_receipt_sha256=None):
    output = Path(output); data = _regular_file(output / "fit-receipt.json", "fit receipt").read_bytes()
    require(expected_receipt_sha256 is None or (broad._valid_hash(expected_receipt_sha256) and _sha256(data) == expected_receipt_sha256), "Fit receipt SHA changed")
    receipt = broad._json_load(data); plan_data = _regular_file(output / "fit-plan.json", "fit plan").read_bytes(); plan = broad._json_load(plan_data)
    protocol = _regular_file(output / "protocol.md", "saved protocol").read_bytes()
    require(data == _json_bytes(receipt) and plan_data == _json_bytes(plan) and _sha256(plan_data) == receipt["fitPlanSHA256"]
        and _sha256(protocol) == receipt["protocolSHA256"] == PROTOCOL_DOCUMENT_SHA256 and receipt["version"] == FIT_VERSION
        and receipt["scope"] == SCOPE and receipt["arms"] == list(ARMS) and receipt["contract"] == frozen_protocol()
        and receipt["sourceSHA256"] == SOURCE_SHA256 and receipt["codeSHA256"] == code_identity()
        and all(receipt[k] == v for k, v in plan.items()) and receipt["updatesPerArm"] == 2200
        and receipt["hasyPreparedReceiptSHA256"] == receipt["hasyReceiptSHA256"] == receipt["hasyTrainingSource"]["receiptSHA256"]
        and receipt["hasySelectedAdaptedRasterHashesSHA256"] == receipt["hasyTrainingSource"]["selectedAdaptedRasterHashesSHA256"]
        and all(receipt["roleGuards"][k] is False for k in receipt["roleGuards"] if k != "rasterizedUJIWriterRole")
        and receipt["roleGuards"]["rasterizedUJIWriterRole"] == "training-32-only"
        and all(receipt["headReset"][a][k] for a in ARMS for k in ("trunkPreserved", "full97HeadEqualsOriginal")), "Frozen fit evidence changed")
    validate_matching(receipt["trainingHistory"], plan)
    for arm in ARMS:
        for suffix, field in (("-aux-initial", "auxiliaryInitialWeightsSHA256"), ("-pretrain", "pretrainWeightsSHA256"), ("", "weightsSHA256")):
            require(_sha256(_regular_file(output / "weights" / f"{arm}{suffix}.pt", "bound checkpoint").read_bytes()) == receipt[field][arm], "Bound checkpoint changed")
        require(_sha256(_regular_file(output / "training-features" / f"{arm}.npz", "bound features").read_bytes()) == receipt["trainingFeaturesSHA256"][arm], "Bound features changed")
    return receipt


def load_fitted_models(output, expected_receipt_sha256=None):
    output = Path(output); receipt = _load_fit_receipt(output, expected_receipt_sha256)
    models, _, _ = initialized_models(receipt["vocabulary"])
    for arm, model in models.items():
        require(receipt["weightFiles"][arm] == f"weights/{arm}.pt", "Unexpected final checkpoint path")
        payload = _regular_file(output / receipt["weightFiles"][arm], "checkpoint").read_bytes()
        require(_sha256(payload) == receipt["weightsSHA256"][arm], "Final checkpoint bytes changed")
        value = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
        expected = {"version": FIT_VERSION, "arm": arm, "phase": "finetune", "finalEpoch": 30, "sourceSHA256": SOURCE_SHA256,
            "protocolSHA256": PROTOCOL_DOCUMENT_SHA256, "fitPlanSHA256": receipt["fitPlanSHA256"],
            "initialStateSHA256": receipt["initialState"]["sha256"], "vocabulary": receipt["vocabulary"]}
        schema, state = model.state_dict(), value["state_dict"]
        require(set(value) == set(expected) | {"state_dict"} and all(value[k] == v for k, v in expected.items())
            and set(state) == set(schema) and all(isinstance(state[k], torch.Tensor) and state[k].shape == schema[k].shape
            and state[k].dtype == schema[k].dtype and bool(torch.isfinite(state[k]).all()) for k in schema), "Final checkpoint metadata/schema changed")
        model.load_state_dict(state, strict=True); require(_state_digest(model.state_dict()) == receipt["finalStateSHA256"][arm], "Reloaded state changed")
        model.eval()
    return models, receipt


def load_training_feature_bundle(output, arm, receipt=None, expected_receipt_sha256=None):
    require(arm in ARMS, "Unknown native-shape arm")
    output = Path(output); saved = _load_fit_receipt(output, expected_receipt_sha256)
    require(receipt is None or _json_bytes(receipt) == _json_bytes(saved), "Supplied receipt changed")
    inputs = saved["trainingInputs"]; order = _training_feature_order(inputs)
    require(_sha256(_json_bytes(inputs)) == saved["trainingInputsSHA256"] and _sha256(_json_bytes(order)) == saved["trainingFeatureOrderSHA256"]
        and set(r["writer"] for r in order) == set(saved["trainingWriters"]) and set(r["label"] for r in order) == set(saved["vocabulary"])
        and saved["trainingFeatureFiles"][arm] == f"training-features/{arm}.npz", "Training feature source/order changed")
    expected = {name: [r[key] for r in order] for name, key in (("labels", "label"), ("writers", "writer"), ("sourceIDs", "sourceID"), ("sessions", "session"), ("rasterSHA256", "rasterSHA256"))}
    payload = _regular_file(output / saved["trainingFeatureFiles"][arm], "features").read_bytes()
    require(_sha256(payload) == saved["trainingFeaturesSHA256"][arm], "Training feature bytes changed during loading")
    with np.load(io.BytesIO(payload), allow_pickle=False) as bundle:
        require(set(bundle.files) == set(expected) | {"features"}, "Training feature fields changed"); arrays = {k: bundle[k].copy() for k in bundle.files}
    features = arrays["features"]
    require(all(arrays[k].shape == (6208,) and arrays[k].tolist() == v for k, v in expected.items())
        and features.shape == (6208, 128) and features.dtype == np.float32 and np.isfinite(features).all()
        and np.allclose(np.linalg.norm(features, axis=1), 1, rtol=1e-4, atol=1e-5), "Training feature identities/vectors changed")
    return arrays


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ("source", "hasy-directory", "output"): parser.add_argument("--" + field, type=Path, required=True)
    parser.add_argument("--hasy-receipt-sha256", required=True); args = parser.parse_args()
    receipt = fit(args.source, args.hasy_directory, args.hasy_receipt_sha256, args.output)
    print(_json_bytes({"version": receipt["version"], "weightsSHA256": receipt["weightsSHA256"], "productionEligible": False}).decode())
