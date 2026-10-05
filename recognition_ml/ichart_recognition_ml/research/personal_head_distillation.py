"""Fixed shared-head experiment; preserve the customizable visual representation.

Public training only, research ranks only, no app/profile/acceptance mutation.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import platform

import numpy as np
import torch
from torch.nn import functional as F

from .personal_adaptability import STARTING_SHA256, evaluate, novelty_exclusions, sparse_labels
from .personal_anchors import AnchorBank, evaluate_anchored
from .personal_encoder_export import load_research_model
from .personal_symbol_data import SOURCE_SHA256 as HASY_SHA256, bitmap_tensor, load_hasy, source_summary
from .personal_symbol_expansion import raw_features
from .personal_symbol_training import balanced_weights, bitmap_results, expand_model
from .personal_visual_encoder import encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-shared-head-distillation-v1"
EXPANSION_SHA256 = "71ee9e135114156a56778a6f2110f5ff51191ce58c58c81412e9be1e771089da"
EXPANSION_REPORT_SHA256 = "45d1f3e1926b5eef238a4b44ab495636ca25a6c3261706772da18f0d140d0be3"
EPOCHS, STEPS, SEED = 20, 50, 29


def teacher_loss(student, teacher, temperature=2.0):
    """KL(teacher || student), including student competition from added classes."""
    if (student.ndim != 2 or teacher.ndim != 2 or not len(student)
            or len(student) != len(teacher) or not 2 <= teacher.shape[1] <= student.shape[1] <= 512
            or student.dtype not in (torch.float32, torch.float64) or teacher.dtype != student.dtype
            or teacher.device != student.device or not 0 < temperature < float("inf")
            or not torch.isfinite(student).all() or not torch.isfinite(teacher).all()):
        raise ValueError("Invalid distillation logits")
    targets = F.pad((teacher.detach() / temperature).softmax(1), (0, student.shape[1] - teacher.shape[1]))
    return F.kl_div((student / temperature).log_softmax(1), targets, reduction="batchmean") * temperature**2


def fit_head(starting, uji_raw, uji_targets, hasy_raw, hasy_targets, teacher, *, distilled,
             epochs=EPOCHS, steps=STEPS):
    """Fit a copied linear head; inputs have no query labels or trainable encoder."""
    if (not isinstance(starting, torch.nn.Linear) or starting.bias is None
            or not isinstance(distilled, bool) or not isinstance(epochs, int) or not isinstance(steps, int)
            or not 1 <= epochs <= EPOCHS or not 1 <= steps <= STEPS):
        raise ValueError("Invalid fixed head configuration")
    width, classes = starting.in_features, starting.out_features
    for raw, targets in ((uji_raw, uji_targets), (hasy_raw, hasy_targets)):
        if (raw.ndim != 2 or raw.shape[1] != width or not len(raw) or raw.dtype != torch.float32
                or raw.device.type != "cpu" or not torch.isfinite(raw).all()
                or targets.shape != (len(raw),) or targets.dtype != torch.long or targets.device.type != "cpu"
                or int(targets.min()) < 0 or int(targets.max()) >= classes):
            raise ValueError("Invalid shared-head training features/labels")
    if (teacher.ndim != 2 or len(teacher) != len(uji_raw) or not 2 <= teacher.shape[1] <= classes <= 512
            or teacher.dtype != torch.float32 or teacher.device.type != "cpu" or not torch.isfinite(teacher).all()
            or int(uji_targets.max()) >= teacher.shape[1]
            or set(torch.cat((uji_targets, hasy_targets)).tolist()) != set(range(classes))
            or any(p.dtype != torch.float32 or p.device.type != "cpu" or not torch.isfinite(p).all()
                   for p in starting.parameters())):
        raise ValueError("Incomplete classifier or teacher contract")
    # Clone out of inference-mode tensors; never backpropagate into source inputs.
    uji_raw, hasy_raw, teacher = (t.detach().clone() for t in (uji_raw, hasy_raw, teacher))
    head = copy.deepcopy(starting)
    head.requires_grad_(True)
    optimizer = torch.optim.AdamW(head.parameters(), lr=0.0005, weight_decay=0.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)
    uw, hw = balanced_weights(uji_targets), balanced_weights(hasy_targets)
    ug, hg = torch.Generator().manual_seed(SEED), torch.Generator().manual_seed(SEED + 1)
    history = []
    for epoch in range(1, epochs + 1):
        total = np.zeros(3, dtype=np.float64)
        for _ in range(steps):
            ui = torch.multinomial(uw, 64, replacement=True, generator=ug)
            hi = torch.multinomial(hw, 64, replacement=True, generator=hg)
            logits = head(torch.cat((uji_raw[ui], hasy_raw[hi])))
            supervised = F.cross_entropy(logits, torch.cat((uji_targets[ui], hasy_targets[hi])))
            preservation = teacher_loss(logits[:64], teacher[ui])
            loss = supervised + preservation if distilled else supervised
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite shared-head objective")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if any(p.grad is None or not torch.isfinite(p.grad).all() for p in head.parameters()):
                raise ValueError("Nonfinite shared-head gradient")
            optimizer.step()
            total += [float(loss.detach()), float(supervised.detach()), float(preservation.detach())]
        scheduler.step()
        row = {"epoch": epoch, "updates": steps, "loss": total[0] / steps,
               "supervisedLoss": total[1] / steps, "teacherLoss": total[2] / steps}
        history.append(row)
        print(json.dumps({"arm": "distilled" if distilled else "supervised", **row}), flush=True)
    if any(not torch.isfinite(p).all() for p in head.parameters()):
        raise ValueError("Nonfinite fitted head")
    return head.eval(), history


def paired_changes(reference, candidate, *, key):
    """Keep identical eligible inputs; report both gains and harms, not just net."""
    before = {r["queryID"]: r for r in reference["rows"]}
    after = {r["queryID"]: r for r in candidate["rows"]}
    if len(before) != len(reference["rows"]) or len(after) != len(candidate["rows"]) or set(before) != set(after):
        raise ValueError("Unpaired development queries")
    rows = []
    for identity, prior in before.items():
        current = after[identity]
        if any(prior[k] != current[k] for k in ("intended", "writer", "eligible", "exclusions")):
            raise ValueError("Development roles/labels/exclusions changed")
        if prior["eligible"]:
            rows.append({"queryID": identity, "writer": prior["writer"], "intended": prior["intended"],
                         "before": prior[key], "after": current[key],
                         "gain": prior[key] != prior["intended"] and current[key] == current["intended"],
                         "harm": prior[key] == prior["intended"] and current[key] != current["intended"]})

    def counts(values):
        return {"count": len(values), "gains": sum(r["gain"] for r in values), "harms": sum(r["harm"] for r in values)}

    return {**counts(rows), "writers": {w: counts([r for r in rows if r["writer"] == w]) for w in sorted({r["writer"] for r in rows})},
            "classes": {c: counts([r for r in rows if r["intended"] == c]) for c in sorted({r["intended"] for r in rows})},
            "changes": [r for r in rows if r["before"] != r["after"]]}


def run(checkpoint: Path, expansion: Path, source: Path, hasy: Path, protocol: Path, output: Path):
    if output.exists():
        raise ValueError("Output directory must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    original, original_report = load_research_model(checkpoint)
    expansion_weights = expansion / "frozen" / "research-weights.pt"
    if (original_report["weightsSHA256"] != STARTING_SHA256
            or hashlib.sha256((expansion / "report.json").read_bytes()).hexdigest() != EXPANSION_REPORT_SHA256
            or hashlib.sha256(expansion_weights.read_bytes()).hexdigest() != EXPANSION_SHA256):
        raise ValueError("Wrong pinned starting models")
    old_vocabulary = tuple(original_report["labels"])
    starting, vocabulary = expand_model(original, old_vocabulary)
    starting.load_state_dict(torch.load(expansion_weights, map_location="cpu", weights_only=True), strict=True)
    for name, expected in original.state_dict().items():
        actual = starting.state_dict()[name][:97] if name.startswith("classifier.") else starting.state_dict()[name]
        if not torch.equal(expected, actual):
            raise ValueError("Original feature or output weights changed")
    records = load_official_source(source)
    training_writers, development_writers, reserved = split_writers(records)
    if any(original_report[k] != list(v) for k, v in (("trainingWriters", training_writers),
            ("developmentWriters", development_writers), ("reservedWriters", reserved))):
        raise ValueError("Writer split changed")
    training = tuple(s for s in records if s.writer in training_writers)
    development = tuple(s for s in records if s.writer in development_writers)
    output.mkdir(parents=True, exist_ok=False)
    protocol_bytes = protocol.read_bytes()
    metadata = {"version": VERSION, "startingWeightsSHA256": STARTING_SHA256, "expandedWeightsSHA256": EXPANSION_SHA256,
        "expansionReportSHA256": EXPANSION_REPORT_SHA256, "ujiSHA256": SOURCE_SHA256, "hasySHA256": HASY_SHA256,
        "trainingWriters": training_writers, "developmentWriters": development_writers, "reservedWriters": reserved,
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False,
        "inferenceAuthority": "research-rank-only", "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "labels": vocabulary, "epochs": EPOCHS, "steps": STEPS, "temperature": 2.0, "distillationCoefficient": 1.0,
        "seed": SEED, "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))}}
    (output / "frozen-protocol.md").write_bytes(protocol_bytes)
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    print("Loading pinned public training sources; no private or reserved-writer inference", flush=True)
    bitmaps = load_hasy(hasy, old_vocabulary)
    hasy_training = tuple(s for s in bitmaps if s.role == "training" and not s.exclusions)
    hasy_development = tuple(s for s in bitmaps if s.role == "development" and not s.exclusions)
    train_images, train_hashes = encode_samples(training, training_writers)
    hasy_development = tuple(s for s in hasy_development if s.raster_hash not in set(train_hashes))
    hasy_train_images = bitmap_tensor(hasy_training, "training")
    metadata["hasySource"] = source_summary(bitmaps)
    metadata["usableHasyTraining"], metadata["usableHasyDevelopment"] = len(hasy_training), len(hasy_development)
    uji_raw, hasy_raw = raw_features(original, train_images), raw_features(original, hasy_train_images)
    with torch.inference_mode():
        teacher = original.classifier(uji_raw)
    uji_targets = torch.tensor([vocabulary.index(s.label) for s in training])
    hasy_targets = torch.tensor([vocabulary.index(s.label) for s in hasy_training])
    fitted = [("original", original, old_vocabulary, []), ("expandedStart", starting, vocabulary, [])]
    # Fit BOTH arms completely before development encoding or predictions.
    for name, distilled in (("supervised", False), ("distilled", True)):
        head, history = fit_head(starting.classifier, uji_raw, uji_targets, hasy_raw, hasy_targets, teacher, distilled=distilled)
        model = copy.deepcopy(starting)
        model.classifier = head
        folder = output / name
        folder.mkdir()
        torch.save(model.state_dict(), folder / "research-weights.pt")
        model.load_state_dict(torch.load(folder / "research-weights.pt", map_location="cpu", weights_only=True), strict=True)
        for key, expected in original.state_dict().items():
            if not key.startswith("classifier.") and not torch.equal(model.state_dict()[key], expected):
                raise ValueError("Frozen encoder parameter changed")
        fitted.append((name, model.eval(), vocabulary, history))
    # Anchor geometry stays fixed; old-class HASY images do not replace UJI means.
    uji_features, hasy_features = F.normalize(uji_raw, dim=1).numpy(), F.normalize(hasy_raw, dim=1).numpy()
    old_bank = AnchorBank.from_training(uji_features, tuple(s.label for s in training), old_vocabulary)
    novel = [i for i, s in enumerate(hasy_training) if s.label not in old_vocabulary]
    bank = AnchorBank.from_training(np.concatenate((uji_features, hasy_features[novel])),
        tuple(s.label for s in training) + tuple(hasy_training[i].label for i in novel), vocabulary)
    if not np.array_equal(bank.features[:97], old_bank.features):
        raise ValueError("Original public anchors changed")
    dev_images, dev_hashes = encode_samples(development, development_writers)
    hasy_dev_images = bitmap_tensor(hasy_development, "development")
    exclusions = novelty_exclusions(development, dev_hashes, training, train_hashes + [s.raster_hash for s in hasy_training])
    original_features, _ = infer(original, dev_images)
    results = {}
    for name, model, labels, history in fitted:
        print(f"Evaluating fixed final checkpoint: {name}", flush=True)
        features, logits = infer(model, dev_images)
        if not np.array_equal(features, original_features):
            raise ValueError("Personal features changed")
        tasks = {}
        for task, support in (("sparse16", sparse_labels(old_vocabulary)), ("full97", old_vocabulary)):
            reference = evaluate(development, features, logits, labels, support, exclusions)
            tasks[task] = {"original": reference, "anchored": evaluate_anchored(development, features, logits, labels,
                              old_bank if name == "original" else bank, reference)}
        result = {"uji": tasks, "hasy": bitmap_results(model, labels, hasy_dev_images, hasy_development, old_vocabulary),
                  "trainingHistory": history, "unchangedFeatures": True}
        if name in ("supervised", "distilled"):
            result["weightsSHA256"] = hashlib.sha256((output / name / "research-weights.pt").read_bytes()).hexdigest()
            (output / name / "public-anchor-bank.json").write_text(json.dumps({"vocabulary": bank.vocabulary,
                "features": bank.features.tolist(), "encoderSHA256": result["weightsSHA256"]}, indent=2, sort_keys=True))
        results[name] = result
        print(json.dumps({"arm": name, "hasy": {k: result["hasy"][k] for k in ("old", "novel")},
            "uji": {task: {"generic": variants["anchored"]["genericCorrect"], "personal": variants["anchored"]["personalCorrect"]}
                    for task, variants in tasks.items()}}), flush=True)
    comparisons = {}
    for name in ("expandedStart", "supervised", "distilled"):
        comparisons[name] = {}
        for reference in ("original", "expandedStart"):
            comparisons[name][reference] = {
                "generic": paired_changes(results[reference]["uji"]["sparse16"]["anchored"], results[name]["uji"]["sparse16"]["anchored"], key="generic"),
                **{task: paired_changes(results[reference]["uji"][task]["anchored"], results[name]["uji"][task]["anchored"], key="personal")
                   for task in ("sparse16", "full97")}}
    gates = {}
    for name in ("supervised", "distilled"):
        result = results[name]
        gates[name] = {"generic": result["uji"]["sparse16"]["anchored"]["genericCorrect"] >= 609,
            "sparse16": result["uji"]["sparse16"]["anchored"]["personalCorrect"] >= 614,
            "full97": result["uji"]["full97"]["anchored"]["personalCorrect"] >= 628,
            "hasyOld": result["hasy"]["old"]["correct"] > 304, "hasyNovel": result["hasy"]["novel"]["correct"] >= 411}
        gates[name]["meritsFurtherComparisonNotPromotion"] = all(gates[name].values())
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256 or hashlib.sha256(hasy.read_bytes()).hexdigest() != HASY_SHA256:
        raise ValueError("Training source changed")
    (output / "report.json").write_text(json.dumps({**metadata, "results": results, "comparisons": comparisons,
        "gates": gates, "sourceUnchanged": True}, indent=2, sort_keys=True))
    print(json.dumps({"gates": gates}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("checkpoint", "expansion", "source", "hasy", "protocol", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    run(**{key: value.resolve() for key, value in vars(parser.parse_args()).items()})
