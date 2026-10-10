"""Fixed public-only, class-equivariant support retrieval. Research ranks only."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

VERSION = "personal-support-retrieval-v1"
SEED, EPOCHS = 29, 10
PROTOCOL = "docs/personal-support-retrieval-protocol-2026-10-01.md"
CODE_FILES = (
    "recognition_ml/ichart_recognition_ml/research/personal_support_retrieval.py",
    "recognition_ml/tests/test_personal_support_retrieval.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_crossfit.py",
    "recognition_ml/tests/test_personal_support_crossfit.py", PROTOCOL,
)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def code_identity():
    root = Path(__file__).resolve().parents[3]
    return {name: sha((root / name).read_bytes()) for name in CODE_FILES}


def summaries(probabilities):
    top = probabilities.topk(2, dim=1).values
    entropy = -(probabilities * probabilities.clamp_min(1e-300).log()).sum(1) / np.log(probabilities.shape[1])
    return top[:, 0], top[:, 0] - top[:, 1], entropy


class SupportRetrieval(nn.Module):
    """Learns scalar relations, never embedding axes or codepoint identities.

    Probabilities are categorical model outputs, not calibrated correctness.
    All untaught ordering is preserved, but taught classes can overtake them.
    """
    def __init__(self):
        super().__init__()
        self.relation = nn.Sequential(nn.Linear(7, 32), nn.Tanh(), nn.Linear(32, 1))
        self.gate = nn.Sequential(nn.Linear(6, 32), nn.Tanh(), nn.Linear(32, 1))
        nn.init.zeros_(self.relation[-1].weight)
        nn.init.zeros_(self.relation[-1].bias)
        nn.init.zeros_(self.gate[-1].weight)
        nn.init.constant_(self.gate[-1].bias, -4)

    def probabilities(self, support_features, support_probabilities, support_labels, query_features, query_probabilities):
        tensors = (support_features, support_probabilities, query_features, query_probabilities)
        require(all(t.ndim == 2 and t.dtype == torch.float64 and t.device.type == "cpu"
                    and torch.isfinite(t).all() for t in tensors), "Finite CPU float64 matrices required")
        support_count, width = support_features.shape
        query_count, classes = query_probabilities.shape
        require(0 <= support_count <= 192 and 1 <= width <= 2048 and 1 <= query_count <= 4096
                and 2 <= classes <= 512 and query_features.shape == (query_count, width)
                and support_probabilities.shape == (support_count, classes)
                and support_labels.shape == (support_count,) and support_labels.dtype == torch.long
                and support_labels.device.type == "cpu"
                and (not support_count or (int(support_labels.min()) >= 0 and int(support_labels.max()) < classes)),
                "Mismatched support/query contract")
        require(all(torch.all(torch.abs(t.norm(dim=1) - 1) <= 1e-3) for t in (support_features, query_features)),
                "Unit feature vectors required")
        require(all(torch.all(t >= 0) and torch.all(t <= 1)
                    and torch.all(torch.abs(t.sum(1) - 1) <= 1e-8)
                    for t in (support_probabilities, query_probabilities)), "Normalized probabilities required")
        if not support_count:
            return query_probabilities
        # Exact repeated lessons are not additional independent evidence. This
        # source-only deduplication precedes label balancing; balancing alone
        # would overweight one copied example among other same-label shapes.
        unique = torch.unique(torch.cat((support_features, support_probabilities,
                                         support_labels[:, None].double()), dim=1), dim=0)
        support_features = unique[:, :width]
        support_probabilities = unique[:, width:-1]
        support_labels = unique[:, -1].long()
        support_count = len(unique)
        qmax, qmargin, qentropy = summaries(query_probabilities)
        _, smargin, sentropy = summaries(support_probabilities)
        cosine = query_features @ support_features.T
        qlabel = query_probabilities[:, support_labels]
        slabel = support_probabilities[torch.arange(support_count), support_labels]
        pair = torch.stack((cosine, qlabel, slabel.expand(query_count, -1),
                            qentropy[:, None].expand(-1, support_count), sentropy.expand(query_count, -1),
                            qmargin[:, None].expand(-1, support_count), smargin.expand(query_count, -1)), dim=2)
        counts = torch.bincount(support_labels, minlength=classes)
        relation = 10 * cosine + self.relation(pair).squeeze(2) - counts[support_labels].double().log()
        attention = relation.softmax(1)
        cache = attention @ F.one_hot(support_labels, classes).double()
        unique_fraction = query_probabilities.new_full((query_count,), float((counts > 0).sum()) / classes)
        gate_input = torch.stack((qmax, qmargin, qentropy, cosine.max(1).values, cache.max(1).values,
                                  unique_fraction), dim=1)
        gate = self.gate(gate_input).sigmoid()
        result = (1 - gate) * query_probabilities + gate * cache
        require(torch.isfinite(result).all() and torch.all(result >= 0)
                and torch.all(torch.abs(result.sum(1) - 1) <= 1e-8), "Invalid retrieval probabilities")
        return result


def balanced_loss(probabilities, targets, taught):
    require(targets.dtype == torch.long and targets.shape == taught.shape == (len(probabilities),)
            and taught.dtype == torch.bool and bool(taught.any()) and bool((~taught).any())
            and int(targets.min()) >= 0 and int(targets.max()) < probabilities.shape[1], "Both query strata required")
    nll = -probabilities[torch.arange(len(targets)), targets].clamp_min(1e-300).log()
    return 0.5 * nll[taught].mean() + 0.5 * nll[~taught].mean()


def episode_plan(rows, vocabulary, *, epochs=EPOCHS):
    """Source-only plan. No logits, predictions, query outcomes or dev rows."""
    require(1 <= epochs <= EPOCHS and len(vocabulary) == len(set(vocabulary)) == 97,
            "Fixed full vocabulary required")
    lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
    writers = tuple(sorted({r["writer"] for r in rows}))
    require(len(writers) == 32 and all(w.startswith("trn_") for w in writers)
            and len(rows) == len(lookup) == 6208
            and set(lookup) == {(w, s, c) for w in writers for s in (1, 2) for c in vocabulary},
            "Complete training-only writer/session grid required")
    allowed_reasons = ("generic-fit-raw-raster-copy", "generic-fit-normalized-trajectory-copy")
    require(all(isinstance(row["genericFitCopyReasons"], list)
                and row["genericFitCopyReasons"] == [r for r in allowed_reasons if r in row["genericFitCopyReasons"]]
                and ((row["storedRasterSHA256"] is None) == (row["storedTrajectorySHA256"] is None))
                for row in rows), "Malformed source-only copy/availability metadata")
    generator = torch.Generator().manual_seed(SEED)
    directions = [(w, s, k) for w in writers for s in (1, 2) for k in (10, 21)]
    plans = []
    for epoch in range(epochs):
        for direction in torch.randperm(len(directions), generator=generator).tolist():
            writer, session, count = directions[direction]
            eligible = [lookup[writer, session, c] for c in vocabulary
                        if rows[lookup[writer, session, c]]["storedRasterSHA256"] is not None]
            require(len(eligible) >= 21, "Too few valid stored support shapes")
            support = [eligible[i] for i in torch.randperm(len(eligible), generator=generator)[:count].tolist()]
            pixels = {rows[i][key] for i in support for key in ("rawRasterSHA256", "storedRasterSHA256")}
            ink = {rows[i][key] for i in support for key in ("trajectorySHA256", "storedTrajectorySHA256")}
            queries, exclusions = [], []
            for label in vocabulary:
                i = lookup[writer, 3 - session, label]
                reasons = list(rows[i]["genericFitCopyReasons"])
                if rows[i]["rawRasterSHA256"] in pixels:
                    reasons.append("support-raster-copy")
                if rows[i]["trajectorySHA256"] in ink:
                    reasons.append("support-normalized-trajectory-copy")
                (exclusions if reasons else queries).append({"index": i, "reasons": reasons} if reasons else i)
            taught = [rows[i]["label"] in {rows[j]["label"] for j in support} for i in queries]
            require(any(taught) and not all(taught), "Source-only exclusions removed a stratum")
            plans.append({"epoch": epoch + 1, "writer": writer, "session": session, "support": support,
                          "queries": queries, "exclusions": exclusions})
    return plans


def crossfit_binding(directory):
    return {key: sha((directory / filename).read_bytes()) for key, filename in
            (("receiptSHA256", "fit-receipt.json"), ("metadataSHA256", "metadata.json"), ("featuresSHA256", "features.npz"))}


def fit(crossfit_directory: Path, output: Path):
    from .personal_support_crossfit import load_crossfit_bundle
    require(output.is_absolute() and output.parent.is_dir() and not output.exists(), "New outside-repo output required")
    require(Path(__file__).resolve().parents[3] not in output.parents, "Research outputs stay outside source")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    binding = crossfit_binding(crossfit_directory)
    bundle, rows, meta = load_crossfit_bundle(crossfit_directory)
    require(crossfit_binding(crossfit_directory) == binding, "Cross-fit changed while loading")
    vocabulary = tuple(meta["vocabulary"])
    plans, code = episode_plan(rows, vocabulary), code_identity()
    arrays = {key: torch.from_numpy(np.array(bundle[key], dtype=np.float64, copy=True))
              for key in ("raw_features", "raw_logits", "stored_features", "stored_logits")}
    raw_base, stored_base = arrays["raw_logits"].softmax(1), arrays["stored_logits"].softmax(1)
    targets = torch.tensor([vocabulary.index(row["label"]) for row in rows], dtype=torch.long)
    model = SupportRetrieval().double()
    initial = {name: value.detach().clone() for name, value in model.state_dict().items()}
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.0001, weight_decay=0.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    output.mkdir(mode=0o700)
    plan_payload = canonical(plans)
    (output / "episode-plan.json").write_bytes(plan_payload)
    (output / "code-before.json").write_bytes(canonical(code))
    binding_payload = canonical(binding)
    (output / "crossfit-binding.json").write_bytes(binding_payload)
    history = []
    for epoch in range(1, EPOCHS + 1):
        losses, maximum_gradient = [], 0.0
        for episode in (p for p in plans if p["epoch"] == epoch):
            si, qi = episode["support"], episode["queries"]
            probabilities = model.probabilities(arrays["stored_features"][si], stored_base[si], targets[si],
                                                arrays["raw_features"][qi], raw_base[qi])
            taught = torch.isin(targets[qi], targets[si])
            loss = balanced_loss(probabilities, targets[qi], taught)
            require(torch.isfinite(loss), "Nonfinite relation objective")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            require(all(p.grad is not None and torch.isfinite(p.grad).all() for p in model.parameters()), "Invalid learned gradient")
            maximum_gradient = max(maximum_gradient, max(float(p.grad.abs().max()) for p in model.parameters()))
            optimizer.step()
            losses.append(float(loss.detach()))
        scheduler.step()
        require(len(losses) == 128 and maximum_gradient > 0, "Missing updates or zero gradients")
        entry = {"epoch": epoch, "updates": len(losses), "meanBalancedLoss": float(np.mean(losses)),
                 "maximumAbsoluteGradient": maximum_gradient}
        history.append(entry)
        print(json.dumps(entry), flush=True)
    require(code_identity() == code and crossfit_binding(crossfit_directory) == binding,
            "Code or cross-fit source changed during fit")
    require(all(torch.isfinite(p).all() for p in model.parameters()), "Nonfinite learned parameter")
    changed = [name for name, value in model.state_dict().items() if not torch.equal(initial[name], value)]
    require(changed, "No learned weights changed")
    stream = io.BytesIO()
    torch.save(model.state_dict(), stream)
    weights = stream.getvalue()
    (output / "weights.pt").write_bytes(weights)
    receipt = {"version": VERSION, "weightsSHA256": sha(weights), "codeSHA256": code,
               "protocolSHA256": code[PROTOCOL], "episodePlanSHA256": sha(plan_payload),
               "crossfitReceiptSHA256": binding["receiptSHA256"], "crossfitBinding": binding,
               "crossfitBindingSHA256": sha(binding_payload),
               "history": history, "updates": 1280, "changedParameterNames": changed,
               "productionEligible": False, "reservedWritersEvaluated": False, "privateInkUsed": False,
               "vocabulary": list(vocabulary), "runtime": {"torch": str(torch.__version__), "numpy": np.__version__}}
    (output / "fit-receipt.json").write_bytes(canonical(receipt))
    return receipt


def load_fitted_learner(directory: Path):
    require(directory.is_absolute() and directory.resolve() == directory and directory.is_dir(), "Invalid learner directory")
    receipt_path, weights_path = directory / "fit-receipt.json", directory / "weights.pt"
    require(not receipt_path.is_symlink() and not weights_path.is_symlink(), "Aliased learner artifact")
    data, weights = receipt_path.read_bytes(), weights_path.read_bytes()
    receipt = json.loads(data)
    binding_payload = (directory / "crossfit-binding.json").read_bytes()
    require(data == canonical(receipt) and receipt["version"] == VERSION
            and receipt["weightsSHA256"] == sha(weights) and receipt["codeSHA256"] == code_identity()
            and receipt["protocolSHA256"] == receipt["codeSHA256"][PROTOCOL]
            and receipt["productionEligible"] is False and receipt["reservedWritersEvaluated"] is False
            and receipt["privateInkUsed"] is False and receipt["updates"] == 1280
            and binding_payload == canonical(receipt["crossfitBinding"])
            and sha(binding_payload) == receipt["crossfitBindingSHA256"]
            and receipt["crossfitBinding"]["receiptSHA256"] == receipt["crossfitReceiptSHA256"]
            and sha((directory / "episode-plan.json").read_bytes()) == receipt["episodePlanSHA256"], "Learner binding changed")
    model = SupportRetrieval().double()
    model.load_state_dict(torch.load(io.BytesIO(weights), map_location="cpu", weights_only=True), strict=True)
    require(all(torch.isfinite(p).all() for p in model.parameters()), "Nonfinite learned parameter")
    return model.eval(), receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--crossfit", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fit(args.crossfit.resolve(), args.output.resolve())
