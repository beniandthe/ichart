"""Frozen matched-control experiment: train features through personal learning.

Development only. Not imported by the app/export CLI; no acceptance authority.
"""
from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import platform
import time

import numpy as np
import torch
from torch.nn import functional as F

from .personal_encoder_export import load_research_model
from .personal_residual import ResidualHead, normalized_scores
from .personal_visual_encoder import augment, encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint

VERSION = "personal-adaptability-v1"
STARTING_SHA256 = "5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0"
EPOCHS, SEED, SUPPORT_COUNT = 10, 29, 16


def adapted_scores(support_features, support_logits, explicit_labels, query_features, query_logits):
    """Differentiable version of ResidualHead; deliberately has no query labels."""
    matrices = (support_features, support_logits, query_features, query_logits)
    if any(value.ndim != 2 or not torch.isfinite(value).all() for value in matrices):
        raise ValueError("Invalid personal learning matrices")
    count, width = support_features.shape
    classes = support_logits.shape[1]
    if (not 0 <= count <= 192 or not 1 <= width <= 2048 or not 2 <= classes <= 512
            or support_logits.shape != (count, classes) or query_features.shape[1] != width
            or query_logits.shape != (len(query_features), classes)
            or explicit_labels.shape != (count,) or explicit_labels.dtype != torch.long
            or any(value.dtype != support_features.dtype or value.device != support_features.device for value in matrices)
            or explicit_labels.device != support_features.device
            or (count and (explicit_labels.min() < 0 or explicit_labels.max() >= classes))):
        raise ValueError("Mismatched personal learning contract")
    if any(torch.any(torch.abs(value.norm(dim=1) - 1) > 1e-3)
           for value in (support_features, query_features)):
        raise ValueError("Personal features must have unit norm")
    base = query_logits.softmax(dim=1)
    if not count:
        return base
    frequencies = torch.bincount(explicit_labels, minlength=classes)
    balance = frequencies[explicit_labels].to(support_features.dtype).rsqrt()[:, None]
    x = support_features * balance
    residual = (F.one_hot(explicit_labels, classes).to(x.dtype) - support_logits.softmax(dim=1)) * balance
    gram = x @ x.T + 0.1 * torch.eye(count, dtype=x.dtype, device=x.device)
    coefficients = torch.linalg.solve(gram, residual)
    result = base + query_features @ (x.T @ coefficients)
    if not torch.isfinite(result).all():
        raise ValueError("Nonfinite adapted scores")
    return result


@dataclass(frozen=True)
class Episode:
    epoch: int
    writer: str
    support_session: int
    support: tuple[int, ...]
    queries: tuple[int, ...]
    augmentation_seed: int
    excluded_copies: tuple[int, ...]


def plan_episodes(samples, allowed_writers, vocabulary, raster_hashes, *, epochs=EPOCHS, support_count=SUPPORT_COUNT):
    if (not samples or len(samples) != len(raster_hashes) or not 1 <= support_count <= len(vocabulary)
            or epochs < 1 or len(set(vocabulary)) != len(vocabulary)
            or any(s.writer not in allowed_writers or not s.writer.startswith("trn_") for s in samples)):
        raise ValueError("Wrong-role or incomplete episode source")
    lookup = {(s.writer, s.session, s.label): i for i, s in enumerate(samples)}
    required = {(writer, session, label) for writer in allowed_writers for session in (1, 2) for label in vocabulary}
    if len(lookup) != len(samples) or set(lookup) != required:
        raise ValueError("Missing or duplicate writer/session/label")
    fingerprints = [trajectory_fingerprint(s) for s in samples]
    generator = torch.Generator().manual_seed(SEED)
    pairs = [(writer, session) for writer in sorted(allowed_writers) for session in (1, 2)]
    episodes = []
    for epoch in range(1, epochs + 1):
        for pair_index in torch.randperm(len(pairs), generator=generator).tolist():
            writer, session = pairs[pair_index]
            selected = sorted(torch.randperm(len(vocabulary), generator=generator)[:support_count].tolist())
            support = tuple(lookup[writer, session, vocabulary[i]] for i in selected)
            ink = {fingerprints[i] for i in support}
            pixels = {raster_hashes[i] for i in support}
            candidates = tuple(lookup[writer, 3 - session, label] for label in vocabulary)
            excluded = tuple(i for i in candidates if fingerprints[i] in ink or raster_hashes[i] in pixels)
            queries = tuple(i for i in candidates if i not in excluded)
            if not queries:
                raise ValueError("No non-copy training queries")
            seed = int(torch.randint(0, 2**31 - 1, (1,), generator=generator))
            episodes.append(Episode(epoch, writer, session, support, queries, seed, excluded))
    return tuple(episodes)


def sparse_labels(vocabulary):
    ordered = sorted(vocabulary, key=lambda label: hashlib.sha256(f"{VERSION}:sparse16:{label}".encode()).hexdigest())
    return tuple(sorted(ordered[:SUPPORT_COUNT]))


def fit_arm(starting_model, images, targets, episodes, *, personal, output):
    model = copy.deepcopy(starting_model)
    # Frozen running statistics prevent training-time query batches from changing
    # support features. eval() does not disable parameter gradients.
    model.eval()
    torch.manual_seed(SEED)
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.0001, weight_decay=0.0001)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    history, started = [], time.monotonic()
    for epoch in range(1, EPOCHS + 1):
        losses, generic_losses, personal_losses = [], [], []
        for episode in (e for e in episodes if e.epoch == epoch):
            indices = list(episode.support + episode.queries)
            batch = augment(images[indices].float() / 255,
                            torch.Generator().manual_seed(episode.augmentation_seed))
            truth = targets[indices]
            features, logits = model(batch)
            support_count = len(episode.support)
            generic_loss = F.cross_entropy(logits, truth)
            adjusted = adapted_scores(features[:support_count], logits[:support_count], truth[:support_count],
                                      features[support_count:], logits[support_count:])
            personal_loss = ((adjusted - F.one_hot(truth[support_count:], logits.shape[1])) ** 2).sum(1).mean()
            loss = generic_loss + personal_loss if personal else generic_loss
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite training loss")
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if any(p.grad is not None and not torch.isfinite(p.grad).all() for p in model.parameters()):
                raise ValueError("Nonfinite training gradient")
            optimizer.step()
            losses.append(float(loss.detach()))
            generic_losses.append(float(generic_loss.detach()))
            personal_losses.append(float(personal_loss.detach()))
        schedule.step()
        row = {"epoch": epoch, "episodes": len(losses), "loss": float(np.mean(losses)),
               "genericLoss": float(np.mean(generic_losses)), "personalLoss": float(np.mean(personal_losses)),
               "elapsedSeconds": time.monotonic() - started}
        history.append(row)
        print(json.dumps({"arm": "personal" if personal else "genericControl", **row}), flush=True)
    torch.save(model.state_dict(), output / "research-weights.pt")
    (output / "training-history.json").write_text(json.dumps(history, indent=2))
    return model, history


def novelty_exclusions(samples, pixels, training, training_pixels):
    training_ink = {trajectory_fingerprint(s) for s in training}
    training_rasters = set(training_pixels)
    result = {}
    for writer in sorted({s.writer for s in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1]
        ink = {trajectory_fingerprint(samples[i]) for i in support}
        rasters = {pixels[i] for i in support}
        for i, sample in enumerate(samples):
            if sample.writer != writer or sample.session != 2:
                continue
            reasons = []
            fingerprint = trajectory_fingerprint(sample)
            if fingerprint in ink:
                reasons.append("normalized_support_copy")
            if pixels[i] in rasters:
                reasons.append("support_raster_copy")
            if fingerprint in training_ink:
                reasons.append("encoder_training_normalized_copy")
            if pixels[i] in training_rasters:
                reasons.append("encoder_training_raster_copy")
            result[sample.identity] = reasons
    return result


def predict_task(samples, features, logits, vocabulary, support_labels):
    """Only session-one answers are read; query labels are not inference inputs."""
    base = normalized_scores(logits)
    predictions = []
    for writer in sorted({s.writer for s in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1 and s.label in support_labels]
        if len(support) != len(support_labels):
            raise ValueError("Missing personal lessons")
        head = ResidualHead.fit(features[support], base[support], tuple(samples[i].label for i in support), vocabulary)
        for i, query in enumerate(samples):
            if query.writer != writer or query.session != 2:
                continue
            ranks = head.rank(features[i], base[i])
            predictions.append({"sampleIndex": i, "generic": vocabulary[int(base[i].argmax())],
                                "personal": ranks[0]["label"], "personalRanks": ranks[:5],
                                "supportIDs": sorted(samples[j].identity for j in support)})
    return predictions


def summarize(rows):
    eligible = [r for r in rows if r["eligible"]]
    return {"queries": len(rows), "eligibleQueries": len(eligible),
            "genericCorrect": sum(r["genericCorrect"] for r in eligible),
            "personalCorrect": sum(r["personalCorrect"] for r in eligible),
            "gains": sum(r["personalCorrect"] and not r["genericCorrect"] for r in eligible),
            "harms": sum(not r["personalCorrect"] and r["genericCorrect"] for r in eligible)}


def evaluate(samples, features, logits, vocabulary, support_labels, exclusions):
    rows = []
    # Fix all predictions before consulting any query answer.
    predictions = predict_task(samples, features, logits, vocabulary, support_labels)
    for prediction in predictions:
        query = samples[prediction["sampleIndex"]]
        reasons = exclusions[query.identity]
        rows.append({**prediction, "queryID": query.identity, "writer": query.writer, "intended": query.label,
                     "eligible": not reasons, "exclusions": reasons, "taughtLabel": query.label in support_labels,
                     "genericCorrect": prediction["generic"] == query.label,
                     "personalCorrect": prediction["personal"] == query.label, "rankOnlyNotAccepted": True})
    return {**summarize(rows), "supportLabels": support_labels,
            "writers": [{"writer": w, **summarize([r for r in rows if r["writer"] == w])}
                        for w in sorted({s.writer for s in samples})],
            "taught": summarize([r for r in rows if r["taughtLabel"]]),
            "untaught": summarize([r for r in rows if not r["taughtLabel"]]), "rows": rows}


def run(checkpoint: Path, source: Path, output: Path, protocol: Path):
    if output.exists():
        raise ValueError("Preserve previous evidence: output directory must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    starting, original = load_research_model(checkpoint)
    if original["weightsSHA256"] != STARTING_SHA256:
        raise ValueError("Starting checkpoint does not match frozen protocol")
    records = load_official_source(source)
    train_writers, dev_writers, reserved = split_writers(records)
    for key, expected in (("trainingWriters", train_writers), ("developmentWriters", dev_writers), ("reservedWriters", reserved)):
        if original[key] != list(expected):
            raise ValueError("Frozen writer split changed")
    training = tuple(s for s in records if s.writer in train_writers)
    development = tuple(s for s in records if s.writer in dev_writers)
    vocabulary = tuple(original["labels"])
    if vocabulary != tuple(sorted({s.label for s in training})):
        raise ValueError("Training vocabulary changed")
    protocol_text = protocol.read_text()
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"version": VERSION, "startingWeightsSHA256": STARTING_SHA256, "sourceSHA256": SOURCE_SHA256,
                "trainingWriters": train_writers, "developmentWriters": dev_writers, "reservedWriters": reserved,
                "reservedWritersEvaluated": False, "productionEligible": False, "inferenceAuthority": "research-rank-only",
                "epochs": EPOCHS, "seed": SEED, "supportCount": SUPPORT_COUNT, "labels": vocabulary,
                "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
                "protocolSHA256": hashlib.sha256(protocol_text.encode()).hexdigest(),
                "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(Path(__file__).parent.glob("*.py"))}}
    (output / "frozen-protocol.md").write_text(protocol_text)
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    print("Rasterizing training writers only; preparing matched episode plan", flush=True)
    train_images, train_pixels = encode_samples(training, train_writers)
    episodes = plan_episodes(training, train_writers, vocabulary, train_pixels)
    episode_data = [{"epoch": e.epoch, "writer": e.writer, "supportSession": e.support_session,
                     "supportIDs": [training[i].identity for i in e.support],
                     "queryIDs": [training[i].identity for i in e.queries],
                     "excludedCopyIDs": [training[i].identity for i in e.excluded_copies],
                     "augmentationSeed": e.augmentation_seed} for e in episodes]
    encoded_plan = json.dumps(episode_data, indent=2, sort_keys=True).encode()
    (output / "episodes.json").write_bytes(encoded_plan)
    metadata["episodesSHA256"] = hashlib.sha256(encoded_plan).hexdigest()
    targets = torch.tensor([vocabulary.index(s.label) for s in training])
    models, histories = {"starting": starting}, {}
    for name, personal in (("genericControl", False), ("personalTrained", True)):
        destination = output / name
        destination.mkdir()
        models[name], histories[name] = fit_arm(starting, train_images, targets, episodes, personal=personal, output=destination)
    # No development inference or checkpoint selection occurs during training.
    print("Training complete; evaluating the fixed development set, reserved writers untouched", flush=True)
    dev_images, dev_pixels = encode_samples(development, dev_writers)
    exclusions = novelty_exclusions(development, dev_pixels, training, train_pixels)
    results = {}
    for name, model in models.items():
        features, logits = infer(model, dev_images)
        results[name] = {profile: evaluate(development, features, logits, vocabulary, support_labels, exclusions)
                         for profile, support_labels in (("sparse16", sparse_labels(vocabulary)), ("full97", vocabulary))}
        for profile, result in results[name].items():
            print(json.dumps({"arm": name, "profile": profile, **summarize(result["rows"])}), flush=True)
    report = {**metadata, "results": results, "trainingHistory": histories,
              "weightsSHA256": {name: hashlib.sha256((output / name / "research-weights.pt").read_bytes()).hexdigest()
                                for name in histories},
              "sourceUnchanged": hashlib.sha256(source.read_bytes()).hexdigest() == SOURCE_SHA256,
              "startingWeightsUnchanged": hashlib.sha256((checkpoint / "research-weights.pt").read_bytes()).hexdigest() == STARTING_SHA256}
    if not report["sourceUnchanged"] or not report["startingWeightsUnchanged"]:
        raise ValueError("Source evidence changed")
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    args = parser.parse_args()
    run(args.checkpoint.resolve(), args.source.resolve(), args.output.resolve(), args.protocol.resolve())
