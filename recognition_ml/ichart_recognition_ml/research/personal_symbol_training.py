"""Fixed public symbol-coverage experiment for the customizable visual encoder.

Research ranks only. No private input, app installation, or acceptance policy.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import platform
import time

import numpy as np
import torch
from torch.nn import functional as F

from .personal_adaptability import STARTING_SHA256, evaluate, novelty_exclusions, sparse_labels
from .personal_anchors import AnchorBank, evaluate_anchored
from .personal_encoder_export import load_research_model
from .personal_symbol_data import NOVEL_LABELS, bitmap_tensor, load_hasy, source_summary
from .personal_visual_encoder import PersonalVisualEncoder, augment, encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-symbol-coverage-v1"
SEED, EPOCHS, STEPS = 29, 20, 50


def expand_model(starting, old_vocabulary):
    if set(old_vocabulary) & set(NOVEL_LABELS) or len(old_vocabulary) != 97:
        raise ValueError("Unexpected original vocabulary")
    vocabulary = tuple(old_vocabulary) + NOVEL_LABELS
    torch.manual_seed(SEED)
    model = PersonalVisualEncoder(len(vocabulary))
    model.convolution.load_state_dict(starting.convolution.state_dict(), strict=True)
    model.projection.load_state_dict(starting.projection.state_dict(), strict=True)
    with torch.no_grad():
        model.classifier.weight[:len(old_vocabulary)].copy_(starting.classifier.weight)
        model.classifier.bias[:len(old_vocabulary)].copy_(starting.classifier.bias)
    model.eval()
    return model, vocabulary


def balanced_weights(targets):
    if targets.ndim != 1 or targets.dtype != torch.long or not len(targets) or int(targets.min()) < 0:
        raise ValueError("Invalid training targets")
    counts = torch.bincount(targets)
    return counts[targets].double().reciprocal()


def train_arm(starting, uji_images, uji_targets, hasy_images, hasy_targets, output, *, mixed):
    model = copy.deepcopy(starting).eval()  # Freeze BN running state, not gradients.
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.0005, weight_decay=0.0001)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    uji_weights, hasy_weights = balanced_weights(uji_targets), balanced_weights(hasy_targets)
    uji_generator = torch.Generator().manual_seed(SEED)
    hasy_generator = torch.Generator().manual_seed(SEED + 1)
    augmentation_generator = torch.Generator().manual_seed(SEED + 2)
    history, began = [], time.monotonic()
    for epoch in range(1, EPOCHS + 1):
        total_loss = 0.0
        for _ in range(STEPS):
            ui = torch.multinomial(uji_weights, 64 if mixed else 128, replacement=True, generator=uji_generator)
            images, targets = uji_images[ui], uji_targets[ui]
            if mixed:
                hi = torch.multinomial(hasy_weights, 64, replacement=True, generator=hasy_generator)
                images = torch.cat((images, hasy_images[hi]))
                targets = torch.cat((targets, hasy_targets[hi]))
            batch = augment(images.float() / 255, augmentation_generator)
            _, logits = model(batch)
            loss = F.cross_entropy(logits, targets)
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite training loss")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if any(p.grad is not None and not torch.isfinite(p.grad).all() for p in model.parameters()):
                raise ValueError("Nonfinite training gradient")
            optimizer.step()
            total_loss += float(loss.detach())
        scheduler.step()
        row = {"epoch": epoch, "updates": STEPS, "loss": total_loss / STEPS,
               "elapsedSeconds": time.monotonic() - began}
        history.append(row)
        print(json.dumps({"arm": "mixed" if mixed else "ujiControl", **row}), flush=True)
    torch.save(model.state_dict(), output / "research-weights.pt")
    (output / "training-history.json").write_text(json.dumps(history, indent=2))
    return model, history


def bitmap_results(model, vocabulary, images, samples, old_vocabulary):
    _, logits = infer(model, images)
    # Predictions fixed without consulting any holdout labels.
    predictions = [vocabulary[int(index)] for index in logits.argmax(1)]
    rows = [{"identity": s.identity, "intended": s.label, "prediction": p, "correct": p == s.label,
             "newSymbol": s.label not in old_vocabulary, "rasterSHA256": s.raster_hash}
            for s, p in zip(samples, predictions)]
    by_class = {label: {"count": sum(r["intended"] == label for r in rows),
                        "correct": sum(r["intended"] == label and r["correct"] for r in rows)}
                for label in sorted({s.label for s in samples})}
    return {"scope": "HASY fold-1 sample-level development; NOT writer-separated or chord accuracy",
            "count": len(rows), "correct": sum(r["correct"] for r in rows), "classes": by_class,
            "macroAccuracy": sum(c["correct"] / c["count"] for c in by_class.values()) / len(by_class),
            "old": {"count": sum(not r["newSymbol"] for r in rows),
                    "correct": sum(not r["newSymbol"] and r["correct"] for r in rows)},
            "novel": {"count": sum(r["newSymbol"] for r in rows),
                      "correct": sum(r["newSymbol"] and r["correct"] for r in rows)}, "rows": rows}


def evaluate_arm(model, vocabulary, training, train_images, development, dev_images, exclusions,
                 hasy_training, hasy_train_images, hasy_development, hasy_dev_images, old_vocabulary, *, mixed):
    training_features, _ = infer(model, train_images)
    training_labels = tuple(s.label for s in training)
    if mixed:
        hasy_features, _ = infer(model, hasy_train_images)
        training_features = np.concatenate((training_features, hasy_features))
        training_labels += tuple(s.label for s in hasy_training)
    # Control has no learned new-symbol examples: its anchor vocabulary is the
    # original 97, a valid subset of the expanded classifier's 102 outputs.
    anchor_vocabulary = tuple(label for label in vocabulary if label in training_labels)
    bank = AnchorBank.from_training(training_features, training_labels, anchor_vocabulary)
    features, logits = infer(model, dev_images)
    tasks = {}
    for name, support in (("sparse16", sparse_labels(old_vocabulary)), ("full97", tuple(old_vocabulary))):
        original = evaluate(development, features, logits, vocabulary, support, exclusions)
        anchored = evaluate_anchored(development, features, logits, vocabulary, bank, original)
        tasks[name] = {"original": original, "anchored": anchored}
    return {"uji": tasks,
            "hasy": bitmap_results(model, vocabulary, hasy_dev_images, hasy_development, old_vocabulary)}, bank


def run(checkpoint: Path, source: Path, hasy: Path, protocol: Path, output: Path):
    if output.exists():
        raise ValueError("Output directory must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    starting, original = load_research_model(checkpoint)
    if original["weightsSHA256"] != STARTING_SHA256:
        raise ValueError("Wrong frozen starting model")
    records = load_official_source(source)
    train_writers, dev_writers, reserved = split_writers(records)
    for field, expected in (("trainingWriters", train_writers), ("developmentWriters", dev_writers), ("reservedWriters", reserved)):
        if original[field] != list(expected):
            raise ValueError("Writer split changed")
    training = tuple(s for s in records if s.writer in train_writers)
    development = tuple(s for s in records if s.writer in dev_writers)
    old_vocabulary = tuple(original["labels"])
    expanded, vocabulary = expand_model(starting, old_vocabulary)
    protocol_bytes = protocol.read_bytes()
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"version": VERSION, "startingWeightsSHA256": STARTING_SHA256, "ujiSHA256": SOURCE_SHA256,
                "epochs": EPOCHS, "stepsPerEpoch": STEPS, "seed": SEED, "labels": vocabulary,
                "trainingWriters": train_writers, "developmentWriters": dev_writers, "reservedWriters": reserved,
                "reservedWritersEvaluated": False, "productionEligible": False, "privateInkUsed": False,
                "inferenceAuthority": "research-rank-only", "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
                "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
                "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(Path(__file__).parent.glob("*.py"))}}
    (output / "frozen-protocol.md").write_bytes(protocol_bytes)
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    print("Loading pinned public sources; no private ink and no reserved-writer rasterization", flush=True)
    bitmaps = load_hasy(hasy, old_vocabulary)
    hasy_training = tuple(s for s in bitmaps if s.role == "training" and not s.exclusions)
    hasy_development = tuple(s for s in bitmaps if s.role == "development" and not s.exclusions)
    metadata["hasySource"] = source_summary(bitmaps)
    (output / "bitmap-manifest.json").write_text(json.dumps([
        {"identity": s.identity, "latex": s.latex, "label": s.label, "role": s.role, "sourceUserID": s.user_id,
         "rawSHA256": s.raw_hash, "rasterSHA256": s.raster_hash, "exclusions": s.exclusions} for s in bitmaps], indent=2))
    train_images, train_hashes = encode_samples(training, train_writers)
    dev_images, dev_hashes = encode_samples(development, dev_writers)
    hasy_train_images = bitmap_tensor(hasy_training, "training")
    hasy_dev_images = bitmap_tensor(hasy_development, "development")
    exclusions = novelty_exclusions(development, dev_hashes, training,
                                     train_hashes + [s.raster_hash for s in hasy_training])
    # Same public development rows for every arm. Cross-source exact copies do
    # not become valid merely because one arm did not fit on the copied input.
    uji_hashes = set(train_hashes)
    retained = [i for i, s in enumerate(hasy_development) if s.raster_hash not in uji_hashes]
    metadata["hasyUjiTrainingCopiesExcluded"] = len(hasy_development) - len(retained)
    hasy_development = tuple(hasy_development[i] for i in retained)
    hasy_dev_images = hasy_dev_images[retained]
    metadata["usableHasyTraining"] = len(hasy_training)
    metadata["usableHasyDevelopment"] = len(hasy_development)
    print(json.dumps({"source": metadata["hasySource"], "training": len(hasy_training),
                      "development": len(hasy_development), "novelLabels": NOVEL_LABELS}), flush=True)
    uji_targets = torch.tensor([vocabulary.index(s.label) for s in training])
    hasy_targets = torch.tensor([vocabulary.index(s.label) for s in hasy_training])
    results = {}
    # No development predictions are evaluated while either arm is fitting.
    fitted = [("starting", starting, old_vocabulary, False, [])]
    for name, mixed in (("ujiControl", False), ("mixed", True)):
        folder = output / name
        folder.mkdir()
        model, history = train_arm(expanded, train_images, uji_targets, hasy_train_images, hasy_targets, folder, mixed=mixed)
        fitted.append((name, model, vocabulary, mixed, history))
    for name, model, labels, mixed, history in fitted:
        print(f"Evaluating fixed final checkpoint: {name}", flush=True)
        result, bank = evaluate_arm(model, labels, training, train_images, development, dev_images, exclusions,
            hasy_training, hasy_train_images, hasy_development, hasy_dev_images, old_vocabulary, mixed=mixed)
        result["trainingHistory"] = history
        if name != "starting":
            result["weightsSHA256"] = hashlib.sha256((output / name / "research-weights.pt").read_bytes()).hexdigest()
            (output / name / "public-anchor-bank.json").write_text(json.dumps({"vocabulary": bank.vocabulary,
                "features": bank.features.tolist(), "encoderSHA256": result["weightsSHA256"]}, indent=2, sort_keys=True))
        results[name] = result
        print(json.dumps({"arm": name, "hasy": {k: result["hasy"][k] for k in ("count", "correct", "macroAccuracy", "old", "novel")},
            "uji": {task: {method: {key: values[key] for key in ("eligibleQueries", "genericCorrect", "personalCorrect", "gains", "harms")}
                          for method, values in variants.items()} for task, variants in result["uji"].items()}}), flush=True)
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("UJI source changed")
    report = {**metadata, "results": results, "sourceUnchanged": True}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("checkpoint", "source", "hasy", "protocol", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    args = parser.parse_args()
    run(**{key: value.resolve() for key, value in vars(args).items()})
