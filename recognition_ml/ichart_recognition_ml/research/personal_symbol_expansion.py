"""Research-only convex symbol-output fit with frozen visual/personal features."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F

from .personal_adaptability import STARTING_SHA256, evaluate, novelty_exclusions, sparse_labels
from .personal_anchors import AnchorBank, evaluate_anchored
from .personal_encoder_export import load_research_model
from .personal_symbol_data import SOURCE_SHA256 as HASY_SHA256, bitmap_tensor, load_hasy, source_summary
from .personal_symbol_training import balanced_weights, bitmap_results, expand_model
from .personal_visual_encoder import encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-symbol-expansion-v1"


def raw_features(model, images):
    model.eval()
    with torch.inference_mode():
        return torch.cat([model.projection(model.convolution(batch.float() / 255).flatten(1))
                          for batch in images.split(128)])


def fit_new_outputs(raw, fixed_logits, targets, new_count, old_count):
    if (raw.ndim != 2 or fixed_logits.shape != (len(raw), old_count) or targets.shape != (len(raw),)
            or targets.dtype != torch.long or not 1 <= new_count <= 16 or not 2 <= old_count <= 512
            or not torch.isfinite(raw).all() or not torch.isfinite(fixed_logits).all()
            or set(targets.tolist()) != set(range(old_count + new_count))):
        raise ValueError("Incomplete or invalid expansion training data")
    x, base = raw.detach().double(), fixed_logits.detach().double()
    weight = torch.zeros((new_count, raw.shape[1]), dtype=torch.float64, requires_grad=True)
    bias = torch.full((new_count,), -5.0, dtype=torch.float64, requires_grad=True)
    balance = balanced_weights(targets)
    balance /= balance.sum()
    optimizer = torch.optim.LBFGS([weight, bias], lr=1, max_iter=200, max_eval=400,
        tolerance_grad=1e-7, tolerance_change=1e-10, line_search_fn="strong_wolfe")
    losses = []

    def closure():
        optimizer.zero_grad(set_to_none=True)
        logits = torch.cat((base, F.linear(x, weight, bias)), dim=1)
        loss = (F.cross_entropy(logits, targets, reduction="none") * balance).sum() + 0.0001 * weight.square().mean()
        if not torch.isfinite(loss):
            raise ValueError("Nonfinite expansion objective")
        loss.backward()
        if not torch.isfinite(weight.grad).all() or not torch.isfinite(bias.grad).all():
            raise ValueError("Nonfinite expansion gradient")
        losses.append(float(loss.detach()))
        if len(losses) % 25 == 0:
            print(json.dumps({"evaluations": len(losses), "loss": losses[-1]}), flush=True)
        return loss

    optimizer.step(closure)
    return weight.detach().float(), bias.detach().float(), {
        "iterations": optimizer.state[weight]["n_iter"], "evaluations": len(losses), "losses": losses}


def run(checkpoint: Path, source: Path, hasy: Path, protocol: Path, output: Path):
    if output.exists():
        raise ValueError("Output directory must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    original, original_report = load_research_model(checkpoint)
    if original_report["weightsSHA256"] != STARTING_SHA256:
        raise ValueError("Wrong original encoder")
    old_vocabulary = tuple(original_report["labels"])
    model, vocabulary = expand_model(original, old_vocabulary)
    records = load_official_source(source)
    training_writers, development_writers, reserved = split_writers(records)
    if any(original_report[key] != list(value) for key, value in (
        ("trainingWriters", training_writers), ("developmentWriters", development_writers), ("reservedWriters", reserved))):
        raise ValueError("Writer split changed")
    training = tuple(s for s in records if s.writer in training_writers)
    development = tuple(s for s in records if s.writer in development_writers)
    output.mkdir(parents=True, exist_ok=False)
    protocol_bytes = protocol.read_bytes()
    metadata = {"version": VERSION, "startingWeightsSHA256": STARTING_SHA256, "ujiSHA256": SOURCE_SHA256,
        "labels": vocabulary, "trainingWriters": training_writers, "developmentWriters": development_writers,
        "reservedWriters": reserved, "reservedWritersEvaluated": False, "privateInkUsed": False,
        "productionEligible": False, "inferenceAuthority": "research-rank-only",
        "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
        "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))}}
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    (output / "frozen-protocol.md").write_bytes(protocol_bytes)
    bitmaps = load_hasy(hasy, old_vocabulary)
    hasy_training = tuple(s for s in bitmaps if s.role == "training" and not s.exclusions)
    hasy_development = tuple(s for s in bitmaps if s.role == "development" and not s.exclusions)
    train_images, train_hashes = encode_samples(training, training_writers)
    dev_images, dev_hashes = encode_samples(development, development_writers)
    hasy_train_images = bitmap_tensor(hasy_training, "training")
    hasy_development = tuple(s for s in hasy_development if s.raster_hash not in set(train_hashes))
    hasy_dev_images = bitmap_tensor(hasy_development, "development")
    metadata["hasySource"] = source_summary(bitmaps)
    metadata["usableHasyTraining"], metadata["usableHasyDevelopment"] = len(hasy_training), len(hasy_development)
    print("Fitting only five symbol rows; original features and 97 classifier rows frozen", flush=True)
    uji_raw, hasy_raw = raw_features(original, train_images), raw_features(original, hasy_train_images)
    raw = torch.cat((uji_raw, hasy_raw))
    with torch.inference_mode():
        fixed = original.classifier(raw)
    targets = torch.tensor([vocabulary.index(s.label) for s in training + hasy_training])
    weights, bias, fit = fit_new_outputs(raw, fixed, targets, 5, len(old_vocabulary))
    with torch.no_grad():
        model.classifier.weight[97:].copy_(weights)
        model.classifier.bias[97:].copy_(bias)
    original_state, expanded_state = original.state_dict(), model.state_dict()
    for name, expected in original_state.items():
        actual = expanded_state[name][:97] if name.startswith("classifier.") else expanded_state[name]
        if not torch.equal(actual, expected):
            raise ValueError("Frozen parameter changed")
    folder = output / "frozen"
    folder.mkdir()
    torch.save(model.state_dict(), folder / "research-weights.pt")
    # Validate the exact float32 saved model, not optimizer's double weights.
    model.load_state_dict(torch.load(folder / "research-weights.pt", weights_only=True, map_location="cpu"), strict=True)
    original_features, original_logits = infer(original, dev_images)
    features, logits = infer(model, dev_images)
    if not np.array_equal(original_features, features):
        raise ValueError("Original personal representation changed")
    logit_error = float(np.max(np.abs(original_logits - logits[:, :97])))
    if logit_error >= 1e-4:
        raise ValueError("Original logits changed")
    # Existing anchors stay UJI-derived; only new symbol means use HASY.
    uji_features = F.normalize(uji_raw, dim=1).numpy()
    hasy_features = F.normalize(hasy_raw, dim=1).numpy()
    novel = [i for i, s in enumerate(hasy_training) if s.label not in old_vocabulary]
    bank = AnchorBank.from_training(np.concatenate((uji_features, hasy_features[novel])),
        tuple(s.label for s in training) + tuple(hasy_training[i].label for i in novel), vocabulary)
    old_bank = AnchorBank.from_training(uji_features, tuple(s.label for s in training), old_vocabulary)
    if not np.array_equal(bank.features[:97], old_bank.features):
        raise ValueError("Original public anchors changed")
    exclusions = novelty_exclusions(development, dev_hashes, training, train_hashes + [s.raster_hash for s in hasy_training])
    results = {}
    for name, support in (("sparse16", sparse_labels(old_vocabulary)), ("full97", old_vocabulary)):
        reference = evaluate(development, features, logits, vocabulary, support, exclusions)
        results[name] = {"original": reference, "anchored": evaluate_anchored(development, features, logits, vocabulary, bank, reference)}
    result = {"weightsSHA256": hashlib.sha256((folder / "research-weights.pt").read_bytes()).hexdigest(),
        "fit": fit, "uji": results, "hasy": bitmap_results(model, vocabulary, hasy_dev_images, hasy_development, old_vocabulary),
        "unchangedFeatures": True, "originalLogitsMaxError": logit_error}
    (folder / "public-anchor-bank.json").write_text(json.dumps({"vocabulary": bank.vocabulary,
        "features": bank.features.tolist(), "encoderSHA256": result["weightsSHA256"]}, indent=2, sort_keys=True))
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256 or hashlib.sha256(hasy.read_bytes()).hexdigest() != HASY_SHA256:
        raise ValueError("Training source changed")
    (output / "report.json").write_text(json.dumps({**metadata, "sourceUnchanged": True, "results": {"frozen": result}}, indent=2, sort_keys=True))
    print(json.dumps({"hasy": {k: result["hasy"][k] for k in ("count", "correct", "macroAccuracy", "old", "novel")},
        "uji": {task: {method: {k: r[k] for k in ("eligibleQueries", "genericCorrect", "personalCorrect", "gains", "harms")}
                       for method, r in variants.items()} for task, variants in results.items()},
        "unchangedFeatures": True, "originalLogitsMaxError": logit_error}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("checkpoint", "source", "hasy", "protocol", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    run(**{key: value.resolve() for key, value in vars(parser.parse_args()).items()})
