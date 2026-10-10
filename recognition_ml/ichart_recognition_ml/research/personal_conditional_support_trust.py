"""One frozen, training-only conditional setup-cache gate. Never shipping OCR."""
from __future__ import annotations

import argparse
import io
import json
from pathlib import Path
import re

import numpy as np
import torch
from torch import nn

from . import personal_support_crossfit as crossfit
from . import personal_support_inner_roles as inner
from . import personal_support_signal_audit as audit
from .personal_support_retrieval import balanced_loss, canonical, require, sha, summaries
from .personal_cross_writer_contrastive import _new_output, _regular_file, _state_digest, _write_exclusive

VERSION = "personal-conditional-support-trust-v1"
SEED, EPOCHS, UPDATES_PER_EPOCH = 41, 30, 32
PROTOCOL = "docs/personal-conditional-support-trust-protocol-2026-10-01.md"
PROTOCOL_SHA256 = "aef2c1db98bc12bce63575f11b0fd7930306c18d4d3b1350880cbeec09647680"
ROLE_SHA256 = "47b90ce553240d516c3cf308b5777f5a7d75ba1ec7700e981aa9705259e58daa"
GENERATOR_SHA256 = "1cfbcd2c11fe5173bbd7367121fdb9c4c1d965618d9272a6c7421dd6901261c1"
CODE_FILES = ("recognition_ml/ichart_recognition_ml/research/personal_conditional_support_trust.py",
              "recognition_ml/tests/test_personal_conditional_support_trust.py", PROTOCOL,
              "recognition_ml/ichart_recognition_ml/research/personal_support_inner_roles.py",
              "recognition_ml/tests/test_personal_support_inner_roles.py")


def code_identity():
    root = Path(__file__).resolve().parents[3]
    result = dict(audit.code_identity())
    result.update({name: sha((root / name).read_bytes()) for name in CODE_FILES})
    require(result[PROTOCOL] == PROTOCOL_SHA256, "Conditional trust protocol changed")
    return result


def input_identity(directory):
    return audit.input_identity(Path(directory))


def validate_inputs(sf, sp, sl, qf, qp):
    require(all(isinstance(t, torch.Tensor) and t.ndim == 2 and t.dtype == torch.float64
        and t.device.type == "cpu" and bool(torch.isfinite(t).all()) for t in (sf, sp, qf, qp)),
        "Finite CPU float64 matrices required")
    count, width = sf.shape
    queries, classes = qp.shape
    require(0 <= count <= 192 and 1 <= width <= 2048 and 1 <= queries <= 4096 and 2 <= classes <= 512
        and sp.shape == (count, classes) and qf.shape == (queries, width)
        and isinstance(sl, torch.Tensor) and sl.dtype == torch.long and sl.device.type == "cpu"
        and sl.shape == (count,) and (not count or 0 <= int(sl.min()) <= int(sl.max()) < classes),
        "Mismatched support/query contract")
    require(all(bool(torch.all(torch.abs(t.norm(dim=1) - 1) <= 1e-3)) for t in (sf, qf)),
        "Unit feature vectors required")
    audit._probability_matrix(sp)
    audit._probability_matrix(qp)


def prepare_inputs(sf, sp, sl, qf, qp):
    """Frozen cache and fourteen symmetric scalars; no query-answer argument."""
    validate_inputs(sf, sp, sl, qf, qp)
    require(len(sf) > 0, "Nonempty lessons required for scalar preparation")
    cache, details = audit.cache_evidence(sf, sp, sl, qf, qp)
    representatives = [group[0] for group in details["deduplicatedSupportGroups"]]
    features, probabilities, labels = sf[representatives], sp[representatives], sl[representatives]
    cosine = qf @ features.T
    qmax, qmargin, qentropy = summaries(qp)
    cmax, cmargin, centropy = summaries(cache)
    qtops, ctops = qp == qmax[:, None], cache == cmax[:, None]
    taught = torch.bincount(labels, minlength=qp.shape[1]) > 0
    top_support = ctops[:, labels]
    top_cosine = cosine.masked_fill(~top_support, -torch.inf).max(1).values
    other_cosine = cosine.masked_fill(top_support, -torch.inf).max(1).values
    contrast = torch.where((~top_support).any(1), top_cosine - other_cosine, 0.)
    nearest = top_support & (cosine == top_cosine[:, None])
    self_probability = probabilities[torch.arange(len(labels)), labels]
    scalar = torch.stack((qmax, qmargin, qentropy, cmax, cmargin, centropy,
        (qp * ctops).sum(1) / ctops.sum(1), qp[:, taught].sum(1), cosine.max(1).values,
        contrast, (nearest * self_probability).sum(1) / nearest.sum(1),
        qp.new_full((len(qp),), float(taught.sum()) / qp.shape[1]),
        (qtops & taught).sum(1) / qtops.sum(1), (qtops & ctops).any(1).double()), dim=1)
    require(scalar.shape == (len(qp), 14) and bool(torch.isfinite(scalar).all()), "Invalid gate scalars")
    return cache.detach(), scalar.detach()


class ConditionalSupportTrust(nn.Module):
    def __init__(self):
        super().__init__()
        with torch.random.fork_rng():
            torch.manual_seed(SEED)
            self.gate = nn.Sequential(nn.Linear(14, 32), nn.Tanh(), nn.Linear(32, 1)).double()
        nn.init.zeros_(self.gate[-1].weight)
        nn.init.constant_(self.gate[-1].bias, -2.)

    def probabilities(self, sf, sp, sl, qf, qp):
        validate_inputs(sf, sp, sl, qf, qp)
        if not len(sf):
            return qp
        cache, scalar = prepare_inputs(sf, sp, sl, qf, qp)
        gate = self.gate(scalar).sigmoid()
        result = (1 - gate) * qp + gate * cache
        audit._probability_matrix(result)
        return result


def episode_plan(rows, vocabulary, writers, *, epochs=1, seed=42):
    """Source-only fitA plan; query answers never choose supports or exclusions."""
    require(type(epochs) is int and 1 <= epochs <= EPOCHS and seed in (41, 42)
        and len(vocabulary) == 97 and list(vocabulary) == sorted(set(vocabulary)), "Fixed plan recipe required")
    require(len(writers) == len(set(writers)) == 8 and all(re.fullmatch(r"trn_(?:UJI|UPV)_W[0-9]{2}", w) for w in writers),
        "Eight training-only writers required")
    selected = [(i, r) for i, r in enumerate(rows) if r["writer"] in writers]
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in selected}
    require(len(selected) == len(lookup) == 1552 and set(lookup) ==
        {(w, s, c) for w in writers for s in (1, 2) for c in vocabulary}
        and all(r["generator"] == "fitA" for _, r in selected), "Incomplete or non-fitA stage grid")
    reasons_allowed = ("generic-fit-raw-raster-copy", "generic-fit-normalized-trajectory-copy")
    require(all(type(r["session"]) is int and isinstance(r["genericFitCopyReasons"], list)
        and r["genericFitCopyReasons"] == [x for x in reasons_allowed if x in r["genericFitCopyReasons"]]
        and (r["storedRasterSHA256"] is None) == (r["storedTrajectorySHA256"] is None)
        and (r["storedRasterSHA256"] is None) == (r["storedFailure"] is not None)
        and (r["storedFailure"] is None or isinstance(r["storedFailure"], str) and bool(r["storedFailure"]))
        for _, r in selected), "Malformed source-only exclusions/availability")
    generator = torch.Generator().manual_seed(seed)
    directions = [(w, s, k) for w in sorted(writers) for s in (1, 2) for k in (10, 21)]
    plans = []
    for epoch in range(1, epochs + 1):
        for direction in torch.randperm(len(directions), generator=generator).tolist():
            writer, session, count = directions[direction]
            eligible = [lookup[writer, session, c] for c in vocabulary
                if rows[lookup[writer, session, c]]["storedRasterSHA256"] is not None]
            unavailable = [{"index": lookup[writer, session, c], "failure": rows[lookup[writer, session, c]]["storedFailure"]}
                for c in vocabulary if rows[lookup[writer, session, c]]["storedRasterSHA256"] is None]
            require(len(eligible) >= 21, "Too few valid stored setup shapes")
            support = [eligible[i] for i in torch.randperm(len(eligible), generator=generator)[:count].tolist()]
            pixels = {rows[i][key] for i in support for key in ("rawRasterSHA256", "storedRasterSHA256")}
            ink = {rows[i][key] for i in support for key in ("trajectorySHA256", "storedTrajectorySHA256")}
            scheduled = [lookup[writer, 3 - session, c] for c in vocabulary]
            queries, exclusions = [], []
            for i in scheduled:
                reasons = list(rows[i]["genericFitCopyReasons"])
                if rows[i]["rawRasterSHA256"] in pixels:
                    reasons.append("support-raster-copy")
                if rows[i]["trajectorySHA256"] in ink:
                    reasons.append("support-normalized-trajectory-copy")
                (exclusions if reasons else queries).append({"index": i, "reasons": reasons} if reasons else i)
            labels = {rows[i]["label"] for i in support}
            taught = [rows[i]["label"] in labels for i in queries]
            require(any(taught) and not all(taught), "Exclusions removed a query stratum")
            plans.append({"epoch": epoch, "writer": writer, "session": session, "querySession": 3 - session,
                "support": support, "unavailableSetup": unavailable,
                "scheduledQueries": scheduled, "queries": queries, "exclusions": exclusions})
    return plans


def load_parent(directory, manifest):
    """Pinned file and matrix validation only; constructs no old encoder."""
    directory, manifest = Path(directory), _regular_file(Path(manifest), "inner-role manifest")
    before, role_bytes = input_identity(directory), manifest.read_bytes()
    require(before["fit-receipt.json"] == audit.RECEIPT_SHA256 and before["features.npz"] == audit.FEATURES_SHA256
        and sha(role_bytes) == ROLE_SHA256, "Frozen parent or role manifest changed")
    receipt_bytes = _regular_file(directory / "fit-receipt.json", "cross-fit receipt").read_bytes()
    receipt = json.loads(receipt_bytes)
    require(receipt_bytes == canonical(receipt) and receipt["codeSHA256"] == crossfit.code_identity()
        and receipt["metadataSHA256"] == before["metadata.json"] and receipt["featuresSHA256"] == before["features.npz"]
        and receipt["fitPlanSHA256"] == before["fit-plan.json"] and receipt["protocolSHA256"] == before["protocol.md"]
        and receipt["weightsSHA256"] == {arm: before[f"weights/{arm}.pt"] for arm in ("fitA", "fitB")}
        and receipt["weightsSHA256"]["fitA"] == GENERATOR_SHA256, "Cross-fit evidence changed")
    metadata_bytes = _regular_file(directory / "metadata.json", "source metadata").read_bytes()
    metadata = json.loads(metadata_bytes)
    require(metadata_bytes == canonical(metadata) and metadata["vocabulary"] == receipt["vocabulary"]
        and metadata["version"] == crossfit.VERSION, "Cross-fit metadata changed")
    with np.load(io.BytesIO(_regular_file(directory / "features.npz", "source features").read_bytes()), allow_pickle=False) as bundle:
        arrays = {name: bundle[name].copy() for name in bundle.files}
    rows = metadata["rows"]
    audit.validate_bundle(arrays, rows, receipt)
    roles = json.loads(role_bytes)
    expected = inner.inner_roles(receipt, rows)
    require(role_bytes == canonical(roles) and set(roles) == set(expected) | {"plannerCodeSHA256"}
        and all(roles[name] == value for name, value in expected.items()), "Source-only learned-stage roles changed")
    root = Path(__file__).resolve().parents[3]
    require(roles["plannerCodeSHA256"] == {name: sha((root / name).read_bytes()) for name in CODE_FILES[-2:]},
        "Role planner code changed")
    require(input_identity(directory) == before and manifest.read_bytes() == role_bytes, "Parent changed during loading")
    return arrays, rows, receipt, roles


def prepare_training(arrays, rows, vocabulary, plans, indices):
    """Only the optimizer's meta-fit rows become model tensors."""
    require(len(indices) == len(set(indices)) == 1552 and all(rows[i]["generator"] == "fitA" for i in indices)
        and all(set(p["support"] + p["queries"]) <= set(indices) for p in plans), "Non-fit row entered optimizer")
    remap = {global_index: local_index for local_index, global_index in enumerate(indices)}
    tensors = {name: torch.from_numpy(np.array(arrays[name][indices], dtype=np.float64, copy=True))
        for name in ("raw_features", "raw_logits", "stored_features", "stored_logits")}
    raw, stored = tensors["raw_logits"].softmax(1), tensors["stored_logits"].softmax(1)
    labels = torch.tensor([vocabulary.index(rows[i]["label"]) for i in indices], dtype=torch.long)
    prepared = []
    for p in plans:
        si, qi = [remap[i] for i in p["support"]], [remap[i] for i in p["queries"]]
        cache, scalars = prepare_inputs(tensors["stored_features"][si], stored[si], labels[si],
            tensors["raw_features"][qi], raw[qi])
        prepared.append((raw[qi].detach(), cache, scalars, labels[qi], torch.isin(labels[qi], labels[si])))
    return prepared


def train_gate(model, prepared, plans):
    """Fixed final-only optimization; usable with wholly synthetic episodes."""
    require(len(prepared) == len(plans) == EPOCHS * UPDATES_PER_EPOCH
        and [p["epoch"] for p in plans] == [e for e in range(1, EPOCHS + 1) for _ in range(UPDATES_PER_EPOCH)],
        "Fixed 960 source-only updates required")
    initial = {name: tensor.detach().clone() for name, tensor in model.state_dict().items()}
    optimizer = torch.optim.AdamW(model.parameters(), lr=.001, weight_decay=.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    history = []
    for epoch in range(1, EPOCHS + 1):
        losses, gates, max_gradient = [], [], 0.
        start = (epoch - 1) * UPDATES_PER_EPOCH
        lr = float(optimizer.param_groups[0]["lr"])
        for generic, cache, scalars, targets, taught in prepared[start:start + UPDATES_PER_EPOCH]:
            audit._probability_matrix(generic)
            audit._probability_matrix(cache)
            require(scalars.dtype == torch.float64 and scalars.device.type == "cpu" and scalars.shape == (len(generic), 14)
                and bool(torch.isfinite(scalars).all()) and not any(t.requires_grad for t in (generic, cache, scalars)),
                "Frozen finite training inputs required")
            gate = model.gate(scalars).sigmoid()
            loss = balanced_loss((1 - gate) * generic + gate * cache, targets, taught)
            require(bool(torch.isfinite(loss)), "Nonfinite gate loss")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            require(all(p.grad is not None and bool(torch.isfinite(p.grad).all()) for p in model.parameters()), "Invalid gate gradient")
            max_gradient = max(max_gradient, max(float(p.grad.abs().max()) for p in model.parameters()))
            optimizer.step()
            losses.append(float(loss.detach()))
            gates.extend(gate.detach().flatten().tolist())
        scheduler.step()
        require(len(losses) == UPDATES_PER_EPOCH and max_gradient > 0, "Missing or zero-gradient updates")
        entry = {"epoch": epoch, "updates": len(losses), "learningRate": lr,
            "meanBalancedLoss": float(np.mean(losses)), "maximumAbsoluteGradient": max_gradient,
            "gateMean": float(np.mean(gates)), "gateMinimum": min(gates), "gateMaximum": max(gates)}
        history.append(entry)
        print(json.dumps(entry), flush=True)
    require(all(bool(torch.isfinite(p).all()) for p in model.parameters()), "Nonfinite final weights")
    deltas = {name: float((value - initial[name]).norm()) for name, value in model.state_dict().items()}
    require(all(value > 0 for value in deltas.values()), "A gate parameter block never changed")
    return history, deltas


def checkpoint_bytes(model, binding):
    stream = io.BytesIO()
    torch.save({"version": VERSION, "binding": binding, "state_dict": model.state_dict()}, stream)
    return stream.getvalue()


def load_checkpoint(payload, expected_sha, binding):
    require(sha(payload) == expected_sha, "Gate checkpoint bytes changed")
    checkpoint = torch.load(io.BytesIO(payload), map_location="cpu", weights_only=True)
    require(set(checkpoint) == {"version", "binding", "state_dict"} and checkpoint["version"] == VERSION
        and checkpoint["binding"] == binding, "Gate checkpoint binding changed")
    model = ConditionalSupportTrust()
    schema, state = model.state_dict(), checkpoint["state_dict"]
    require(set(state) == set(schema) and all(isinstance(state[k], torch.Tensor) and state[k].shape == schema[k].shape
        and state[k].dtype == torch.float64 and state[k].device.type == "cpu" and bool(torch.isfinite(state[k]).all()) for k in schema),
        "Invalid gate checkpoint state")
    model.load_state_dict(state, strict=True)
    return model.eval()


def frozen_fit_plan():
    return {"version": VERSION, "seed": SEED, "epochs": EPOCHS, "updatesPerEpoch": UPDATES_PER_EPOCH,
        "updates": EPOCHS * UPDATES_PER_EPOCH, "learningRate": .001, "weightDecay": .0001,
        "cosineTMax": EPOCHS, "architecture": "14-32-tanh-1-sigmoid", "cacheTemperature": 10,
        "finalLayerInitialWeight": 0, "finalLayerInitialBias": -2, "finalCheckpointOnly": True}


def validate_saved_plans(plans, roles):
    """Check frozen plan membership without reopening source/query-label JSON."""
    indices = set(roles["sourceIndices"]["metaFit"])
    require(len(indices) == 1552 and len(plans) == 960
        and not indices & set(roles["sourceIndices"]["internalValidation"])
        and not set(roles["metaFitWriters"]) & (set(roles["internalValidationWriters"]) | set(roles["encoderFitWriters"])),
        "Frozen plan role membership changed")
    for epoch in range(1, EPOCHS + 1):
        selected = plans[(epoch - 1) * 32:epoch * 32]
        require({(p["writer"], p["session"], len(p["support"])) for p in selected}
            == {(w, s, k) for w in roles["metaFitWriters"] for s in (1, 2) for k in (10, 21)},
            "Frozen per-epoch direction grid changed")
        for p in selected:
            support, queries, scheduled = p["support"], p["queries"], p["scheduledQueries"]
            excluded = [e["index"] for e in p["exclusions"]]
            unavailable = [e["index"] for e in p["unavailableSetup"]]
            require(p["epoch"] == epoch and p["querySession"] == 3 - p["session"]
                and len(set(support)) == len(support) and len(set(scheduled)) == len(scheduled) == 97
                and len(set(queries)) == len(queries) and len(set(excluded)) == len(excluded)
                and set(queries) | set(excluded) == set(scheduled) and not set(queries) & set(excluded)
                and not set(support) & set(scheduled) and set(support + scheduled) <= indices
                and len(set(unavailable)) == len(unavailable) and set(unavailable) <= indices
                and not set(unavailable) & set(support + scheduled)
                and all(set(e) == {"index", "failure"} and type(e["index"]) is int
                    and isinstance(e["failure"], str) and bool(e["failure"]) for e in p["unavailableSetup"])
                and all(e["reasons"] and len(e["reasons"]) == len(set(e["reasons"]))
                    and set(e["reasons"]) <= {"generic-fit-raw-raster-copy", "generic-fit-normalized-trajectory-copy",
                        "support-raster-copy", "support-normalized-trajectory-copy"} for e in p["exclusions"]),
                "Frozen query/source plan changed")


def fit(crossfit_directory, manifest, output):
    crossfit_directory, manifest, output = Path(crossfit_directory), Path(manifest), Path(output)
    require(Path(__file__).resolve().parents[3] not in output.parents and output != crossfit_directory
        and crossfit_directory not in output.parents, "New outside-repo output required")
    before, code = input_identity(crossfit_directory), code_identity()
    arrays, rows, parent, roles = load_parent(crossfit_directory, manifest)
    role_bytes = _regular_file(manifest, "role manifest").read_bytes()
    plans = episode_plan(rows, parent["vocabulary"], roles["metaFitWriters"], epochs=EPOCHS, seed=SEED)
    output = _new_output(output)
    plan_bytes = canonical(plans)
    _write_exclusive(output / "episode-plan.json", plan_bytes)
    _write_exclusive(output / "code-before.json", canonical(code))
    _write_exclusive(output / "parent-binding.json", canonical(before))
    _write_exclusive(output / "role-manifest.json", role_bytes)
    _write_exclusive(output / "fit-plan.json", canonical(frozen_fit_plan()))
    root = Path(__file__).resolve().parents[3]
    _write_exclusive(output / "protocol.md", (root / PROTOCOL).read_bytes())
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    prepared = prepare_training(arrays, rows, parent["vocabulary"], plans, roles["sourceIndices"]["metaFit"])
    model = ConditionalSupportTrust()
    initial_digest = _state_digest(model.state_dict())
    history, deltas = train_gate(model, prepared, plans)
    require(code_identity() == code and input_identity(crossfit_directory) == before and manifest.read_bytes() == role_bytes,
        "Code, parent or roles changed during fit")
    checkpoint_binding = {"protocolSHA256": PROTOCOL_SHA256, "parentBindingSHA256": sha(canonical(before)),
        "roleManifestSHA256": ROLE_SHA256, "episodePlanSHA256": sha(plan_bytes), "finalEpoch": EPOCHS}
    weights = checkpoint_bytes(model, checkpoint_binding)
    _write_exclusive(output / "weights.pt", weights)
    receipt = {**frozen_fit_plan(), "protocolSHA256": PROTOCOL_SHA256, "codeSHA256": code,
        "parentDirectory": str(crossfit_directory), "parentBinding": before,
        "parentBindingSHA256": sha(canonical(before)), "roleManifestSHA256": ROLE_SHA256, "roleManifest": roles,
        "episodePlanSHA256": sha(plan_bytes), "fitPlanSHA256": sha(canonical(frozen_fit_plan())),
        "weightsSHA256": sha(weights), "checkpointBinding": checkpoint_binding,
        "initialStateSHA256": initial_digest, "finalStateSHA256": _state_digest(model.state_dict()),
        "vocabulary": parent["vocabulary"], "history": history, "parameterDeltaNorms": deltas,
        "changedParameterNames": sorted(deltas), "productionEligible": False, "freshValidation": False,
        "privateInkUsed": False, "reservedWritersEvaluated": False, "internalValidationUsedDuringFit": False,
        "otherGeneratorUsed": False, "appOrProfileMutated": False,
        "runtime": {"torch": str(torch.__version__), "numpy": np.__version__, "threads": 4, "deterministic": True}}
    _write_exclusive(output / "fit-receipt.json", canonical(receipt))
    return receipt


def load_fitted_learner(directory):
    directory = Path(directory)
    require(directory.is_absolute() and directory.resolve() == directory and directory.is_dir(), "Invalid learner directory")
    receipt_bytes = _regular_file(directory / "fit-receipt.json", "gate receipt").read_bytes()
    receipt = json.loads(receipt_bytes)
    require(receipt_bytes == canonical(receipt) and all(receipt.get(k) == v for k, v in frozen_fit_plan().items())
        and receipt["codeSHA256"] == code_identity() and receipt["protocolSHA256"] == PROTOCOL_SHA256
        and receipt["roleManifestSHA256"] == ROLE_SHA256 and receipt["parentBinding"]["fit-receipt.json"] == audit.RECEIPT_SHA256
        and receipt["parentBinding"]["features.npz"] == audit.FEATURES_SHA256
        and all(receipt[name] is False for name in ("productionEligible", "freshValidation", "privateInkUsed",
            "reservedWritersEvaluated", "internalValidationUsedDuringFit", "otherGeneratorUsed", "appOrProfileMutated")),
        "Gate recipe or research boundary changed")
    for name, expected in (("protocol.md", PROTOCOL_SHA256), ("fit-plan.json", receipt["fitPlanSHA256"]),
        ("episode-plan.json", receipt["episodePlanSHA256"]), ("role-manifest.json", ROLE_SHA256),
        ("parent-binding.json", receipt["parentBindingSHA256"]), ("code-before.json", sha(canonical(receipt["codeSHA256"])))):
        require(sha(_regular_file(directory / name, "gate companion").read_bytes()) == expected, "Gate companion changed")
    require(json.loads((directory / "parent-binding.json").read_bytes()) == receipt["parentBinding"]
        and json.loads((directory / "role-manifest.json").read_bytes()) == receipt["roleManifest"]
        and input_identity(Path(receipt["parentDirectory"])) == receipt["parentBinding"], "Parent binding changed after fit")
    # Inference may hash parent files but must not parse query-label metadata.
    # Source-role derivation/regeneration belongs to preparation, not loading.
    plans = json.loads((directory / "episode-plan.json").read_bytes())
    validate_saved_plans(plans, receipt["roleManifest"])
    require(len(receipt["vocabulary"]) == 97 and receipt["vocabulary"] == sorted(set(receipt["vocabulary"]))
        and len(receipt["history"]) == EPOCHS and sum(h["updates"] for h in receipt["history"]) == 960
        and all(h["epoch"] == e and h["updates"] == 32 and h["maximumAbsoluteGradient"] > 0
            for e, h in enumerate(receipt["history"], 1)), "Final-only optimizer evidence changed")
    binding = {"protocolSHA256": PROTOCOL_SHA256, "parentBindingSHA256": receipt["parentBindingSHA256"],
        "roleManifestSHA256": ROLE_SHA256, "episodePlanSHA256": receipt["episodePlanSHA256"], "finalEpoch": EPOCHS}
    require(receipt["checkpointBinding"] == binding, "Checkpoint role binding changed")
    model = load_checkpoint(_regular_file(directory / "weights.pt", "gate weights").read_bytes(), receipt["weightsSHA256"], binding)
    require(_state_digest(model.state_dict()) == receipt["finalStateSHA256"], "Gate state digest changed")
    return model, receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crossfit", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = fit(args.crossfit, args.manifest, args.output)
    print(json.dumps({"version": result["version"], "updates": result["updates"], "weightsSHA256": result["weightsSHA256"]}), flush=True)
