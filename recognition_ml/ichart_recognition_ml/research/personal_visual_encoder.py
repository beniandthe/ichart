"""Fixed public-development experiment for iChart's customizable visual features.

Not reachable from the app or production model CLI. Produces uncalibrated
research rankings, never a production artifact manifest or acceptance policy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from ..features import RASTER_HEIGHT, RASTER_WIDTH, rasterize
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers, trajectory_fingerprint

VERSION = "personal-visual-encoder-v1"
SEED = 29
EPOCHS = 30
ROOTS = tuple("ABCDEFG")


class PersonalVisualEncoder(nn.Module):
    def __init__(self, label_count: int):
        super().__init__()
        if label_count < 2:
            raise ValueError("At least two character labels required")
        blocks: list[nn.Module] = [nn.AvgPool2d(2)]
        incoming = 1
        for outgoing in (16, 32, 64, 64):
            blocks.extend((nn.Conv2d(incoming, outgoing, 3, stride=2, padding=1),
                           nn.BatchNorm2d(outgoing), nn.ReLU()))
            incoming = outgoing
        self.convolution = nn.Sequential(*blocks)
        self.projection = nn.Linear(64 * 3 * 8, 128)
        self.classifier = nn.Linear(128, label_count)

    def forward(self, raster: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        raw = self.projection(self.convolution(raster).flatten(1))
        return F.normalize(raw, dim=1), self.classifier(raw)


def augment(rasters: torch.Tensor, generator: torch.Generator) -> torch.Tensor:
    """Label-blind training augmentation; never used for query prediction."""
    count = len(rasters)
    random = torch.rand((count, 4), generator=generator)
    angle = (random[:, 0] * 16 - 8) * math.pi / 180
    scale = random[:, 1] * 0.2 + 0.9
    theta = torch.zeros((count, 2, 3))
    theta[:, 0, 0] = angle.cos() * scale
    theta[:, 1, 1] = angle.cos() * scale
    theta[:, 0, 1] = -angle.sin() * scale * RASTER_HEIGHT / RASTER_WIDTH
    theta[:, 1, 0] = angle.sin() * scale * RASTER_WIDTH / RASTER_HEIGHT
    # Grid coordinates span [-1, 1], hence factor two for fractional translation.
    theta[:, 0, 2] = (random[:, 2] * 2 - 1) * 0.03 * 2
    theta[:, 1, 2] = (random[:, 3] * 2 - 1) * 0.05 * 2
    grid = F.affine_grid(theta, rasters.shape, align_corners=False)
    return F.grid_sample(rasters, grid, mode="bilinear", padding_mode="zeros", align_corners=False)


def fit_personal(features: np.ndarray, labels: tuple[str, ...], regularization: float = 0.1):
    """Same balanced ridge objective as Swift. No query/expected-label argument."""
    features = np.asarray(features, dtype=np.float64)
    if features.ndim != 2 or not 0 < len(features) <= 192 or len(features) != len(labels):
        raise ValueError("Invalid personal training dimensions")
    if not 0 < features.shape[1] <= 2048 or not np.isfinite(features).all():
        raise ValueError("Invalid personal features")
    if not math.isfinite(regularization) or regularization <= 0 or any(not label for label in labels):
        raise ValueError("Invalid personal fit")
    classes = tuple(sorted(set(labels)))
    if len(classes) < 2:
        raise ValueError("Need multiple explicit labels")
    weights = np.array([1 / math.sqrt(labels.count(label)) for label in labels])
    x = features * weights[:, None]
    y = np.array([[float(label == c) for c in classes] for label in labels]) * weights[:, None]
    # Explicit finite contractions avoid the matmul floating-point warnings
    # reproduced with bounded 97x128 inputs on the pinned macOS NumPy runtime.
    # The normal-equation residual and Swift solver are independent checks;
    # do not silence warnings or change the ridge objective/regularization.
    gram = np.einsum("nd,md->nm", x, x, optimize=False)
    coefficients = np.linalg.solve(gram + regularization * np.eye(len(x)), y)
    fitted = np.einsum("nd,nc->dc", x, coefficients, optimize=False)
    if not np.isfinite(fitted).all():
        raise ValueError("Nonfinite fitted weights")
    return classes, fitted


def rank_personal(model, query: np.ndarray) -> list[dict]:
    classes, weights = model
    query = np.asarray(query, dtype=np.float64)
    if query.shape != (weights.shape[0],) or not np.isfinite(query).all():
        raise ValueError("Invalid personal query")
    scores = np.einsum("d,dc->c", query, weights, optimize=False)
    if not np.isfinite(scores).all():
        raise ValueError("Nonfinite personal scores")
    return sorted(({"label": label, "score": float(score)} for label, score in zip(classes, scores)),
                  key=lambda item: (-item["score"], item["label"]))


def encode_samples(samples: tuple[Sample, ...], allowed_writers: tuple[str, ...]):
    if any(sample.writer not in allowed_writers or not sample.writer.startswith("trn_") for sample in samples):
        raise ValueError("Reserved or wrong-role writer reached rasterization")
    pixels = [rasterize(sample.strokes).pixels for sample in samples]
    array = np.frombuffer(b"".join(pixels), dtype=np.uint8).copy().reshape(-1, 1, RASTER_HEIGHT, RASTER_WIDTH)
    return torch.from_numpy(array), [hashlib.sha256(pixel).hexdigest() for pixel in pixels]


def infer(model: PersonalVisualEncoder, images: torch.Tensor):
    model.eval()
    features, logits = [], []
    with torch.inference_mode():
        for batch in images.split(128):
            feature, logit = model(batch.float() / 255)
            features.append(feature.numpy())
            logits.append(logit.numpy())
    return np.concatenate(features), np.concatenate(logits)


def load_geometric_reference(path: Path):
    report = json.loads(path.read_text())
    if report["sourceSHA256"] != SOURCE_SHA256 or len(report["rows"]) != 280:
        raise ValueError("Wrong geometric source/reference count")
    rows = {row["queryID"]: row for row in report["rows"]}
    if len(rows) != 280:
        raise ValueError("Duplicate geometric query identity")
    return rows


def evaluate(samples, pixels, features, logits, untrained, labels, train_rasters, reference):
    rows = []
    roots_index = [labels.index(root) for root in ROOTS]
    for writer in sorted({sample.writer for sample in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1 and s.label in ROOTS]
        queries = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 2 and s.label in ROOTS]
        if len(support) != 7 or len(queries) != 7:
            raise ValueError("Incomplete root personal session")
        support_labels = tuple(samples[i].label for i in support)
        learned = fit_personal(features[support], support_labels)
        control = fit_personal(untrained[support], support_labels)
        support_ids = sorted(samples[i].identity for i in support)
        fingerprints = {trajectory_fingerprint(samples[i]) for i in support}
        for index in queries:
            query = samples[index]
            prior = reference[query.identity]
            if prior["supportIDs"] != support_ids:
                raise ValueError("Geometric reference support identity mismatch")
            # All predictions made before checking query.label for correctness.
            rankings = rank_personal(learned, features[index])
            untrained_rankings = rank_personal(control, untrained[index])
            similarities = np.einsum("nd,d->n", features[support], features[index], optimize=False)
            nearest = support[int(np.argmax(similarities))]
            predicted = {"learnedPersonal": rankings[0]["label"],
                         "untrainedPersonal": untrained_rankings[0]["label"],
                         "learnedNearest": samples[nearest].label,
                         "genericSevenWay": ROOTS[int(np.argmax(logits[index, roots_index]))],
                         "oldGeometric": prior["nearest"], "oldFixedRidge": prior["learned"]}
            exclusions = []
            if trajectory_fingerprint(query) in fingerprints:
                exclusions.append("normalized_support_copy")
            if pixels[index] in {pixels[i] for i in support}:
                exclusions.append("support_raster_copy")
            if pixels[index] in train_rasters:
                exclusions.append("encoder_training_raster_copy")
            if prior["intended"] != query.label:
                raise ValueError("Geometric reference label mismatch")
            rows.append({"queryID": query.identity, "writer": writer, "supportIDs": support_ids,
                         "intended": query.label, "eligible": not exclusions, "exclusions": exclusions,
                         "predictions": predicted, "correct": {key: p == query.label for key, p in predicted.items()},
                         "learnedRanks": rankings, "rankOnlyNotAccepted": True})
    eligible = [row for row in rows if row["eligible"]]
    correct = {key: sum(row["correct"][key] for row in eligible) for key in rows[0]["predictions"]}
    comparisons = {}
    for key in correct:
        comparisons[key] = {
            "gains": sum(row["correct"]["learnedPersonal"] and not row["correct"][key] for row in eligible),
            "harms": sum(not row["correct"]["learnedPersonal"] and row["correct"][key] for row in eligible)}
    expected = np.array([labels.index(s.label) for s in samples])
    return {"queries": len(rows), "eligibleQueries": len(eligible), "correct": correct,
            "learnedPersonalVersus": comparisons, "rows": rows,
            "generic97Way": {"samples": len(samples), "correct": int((logits.argmax(1) == expected).sum())},
            "writers": [{"writer": w, "eligible": sum(r["writer"] == w for r in eligible),
                         "correct": {key: sum(r["writer"] == w and r["correct"][key] for r in eligible) for key in correct}}
                        for w in sorted({s.writer for s in samples})]}


def run(source: Path, geometric_report: Path, output: Path):
    if output.exists():
        raise ValueError("Output directory must be new; preserve previous evidence")
    records = load_official_source(source)
    training_writers, development_writers, reserved_writers = split_writers(records)
    training = tuple(r for r in records if r.writer in training_writers)
    development = tuple(r for r in records if r.writer in development_writers)
    reference = load_geometric_reference(geometric_report)
    labels = tuple(sorted({r.label for r in training}))
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "seed": SEED, "epochs": EPOCHS,
                "trainingWriters": training_writers, "developmentWriters": development_writers,
                "reservedWriters": reserved_writers, "trainingSamples": len(training),
                "developmentSamples": len(development), "labels": labels,
                "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
                "platform": platform.platform(), "inferenceAuthority": "research-rank-only",
                "productionEligible": False, "reservedWritersEvaluated": False,
                "geometricReportSHA256": hashlib.sha256(geometric_report.read_bytes()).hexdigest()}
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    np.random.seed(SEED)
    generator = torch.Generator().manual_seed(SEED)
    started = time.monotonic()
    print(f"Preparing {len(training)} training and {len(development)} development samples; reserved untouched", flush=True)
    train_images, train_hashes = encode_samples(training, training_writers)
    dev_images, dev_hashes = encode_samples(development, development_writers)
    model = PersonalVisualEncoder(len(labels))
    untrained, _ = infer(model, dev_images)
    targets = torch.tensor([labels.index(r.label) for r in training])
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
    schedule = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=EPOCHS)
    history = []
    for epoch in range(EPOCHS):
        model.train()
        permutation = torch.randperm(len(training), generator=generator)
        total_loss = 0.0
        correct = 0
        for indices in permutation.split(128):
            images = augment(train_images[indices].float() / 255, generator)
            optimizer.zero_grad(set_to_none=True)
            _, logits = model(images)
            loss = F.cross_entropy(logits, targets[indices])
            if not torch.isfinite(loss):
                raise ValueError("Training diverged")
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach()) * len(indices)
            correct += int((logits.detach().argmax(1) == targets[indices]).sum())
        schedule.step()
        epoch_report = {"epoch": epoch + 1, "trainLoss": total_loss / len(training),
                        "trainCorrect": correct, "elapsedSeconds": time.monotonic() - started}
        history.append(epoch_report)
        print(json.dumps(epoch_report, sort_keys=True), flush=True)
    model.eval()
    torch.save(model.state_dict(), output / "research-weights.pt")
    features, logits = infer(model, dev_images)
    result = evaluate(development, dev_hashes, features, logits, untrained, labels, set(train_hashes), reference)
    metadata["weightsSHA256"] = hashlib.sha256((output / "research-weights.pt").read_bytes()).hexdigest()
    metadata["trainingRasterSHA256"] = hashlib.sha256(train_images.numpy().tobytes()).hexdigest()
    metadata["sourceUnchanged"] = hashlib.sha256(source.read_bytes()).hexdigest() == SOURCE_SHA256
    if not metadata["sourceUnchanged"]:
        raise ValueError("Source changed during research run")
    result.update(metadata)
    result["trainingHistory"] = history
    result["parameterCount"] = sum(p.numel() for p in model.parameters())
    (output / "report.json").write_text(json.dumps(result, indent=2, sort_keys=True))
    print(json.dumps({key: result[key] for key in ("eligibleQueries", "correct", "learnedPersonalVersus", "generic97Way")}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--geometric-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.source.resolve(), args.geometric_report.resolve(), args.output.resolve())
