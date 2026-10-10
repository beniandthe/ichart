"""Research-only residual learning with public untaught-shape anchors.

Anchors are not user lessons or pseudo-labels. They constrain a learned personal
correction toward zero on shared character shapes absent from explicit lessons.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

from .personal_adaptability import STARTING_SHA256, VERSION as REFERENCE_VERSION, summarize
from .personal_encoder_export import load_research_model
from .personal_residual import ResidualHead, normalized_scores, validate_features
from .personal_visual_encoder import encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-untaught-anchor-v1"


@dataclass(frozen=True)
class AnchorBank:
    vocabulary: tuple[str, ...]
    features: np.ndarray

    @classmethod
    def from_training(cls, features, explicit_labels, vocabulary):
        features = np.asarray(features, dtype=np.float64)
        validate_features(features)
        if (len(features) != len(explicit_labels) or not 2 <= len(vocabulary) <= 512
                or len(set(vocabulary)) != len(vocabulary) or set(explicit_labels) != set(vocabulary)
                or any(not isinstance(label, str) or not label for label in vocabulary)):
            raise ValueError("Invalid public anchor training source")
        anchors = np.array([features[[i for i, label in enumerate(explicit_labels) if label == c]].mean(0)
                            for c in vocabulary])
        norms = np.sqrt(np.einsum("nd,nd->n", anchors, anchors, optimize=False))
        if np.any(norms < 1e-8):
            raise ValueError("Degenerate public anchor mean")
        anchors /= norms[:, None]
        validate_features(anchors)
        anchors.setflags(write=False)
        return cls(tuple(vocabulary), anchors)


def fit_anchored(features, base_scores, explicit_labels, vocabulary, bank: AnchorBank):
    features = np.asarray(features, dtype=np.float64)
    base_scores = np.asarray(base_scores, dtype=np.float64)
    # Reuse the existing independent validation and exact empty/full-profile limit.
    original = ResidualHead.fit(features, base_scores, explicit_labels, vocabulary)
    validate_features(bank.features)
    if (len(bank.vocabulary) != len(bank.features) or not 2 <= len(bank.vocabulary) <= 512
            or len(set(bank.vocabulary)) != len(bank.vocabulary)
            or not set(bank.vocabulary).issubset(vocabulary) or bank.features.shape[1] != features.shape[1]):
        raise ValueError("Anchor bank does not match encoder vocabulary/features")
    untaught = [i for i, label in enumerate(bank.vocabulary) if label not in explicit_labels]
    if not explicit_labels or not untaught:
        return original
    balance = np.array([1 / np.sqrt(explicit_labels.count(label)) for label in explicit_labels])[:, None]
    x = features * balance
    targets = np.array([[float(label == c) for c in vocabulary] for label in explicit_labels])
    residuals = (targets - base_scores) * balance
    anchors = bank.features[untaught]
    normal = (np.einsum("nd,ne->de", x, x, optimize=False)
              + np.einsum("nd,ne->de", anchors, anchors, optimize=False) + 0.1 * np.eye(x.shape[1]))
    rhs = np.einsum("nd,nc->dc", x, residuals, optimize=False)
    fitted = np.linalg.solve(normal, rhs)
    if not np.isfinite(fitted).all():
        raise ValueError("Nonfinite anchored personal fit")
    fitted.setflags(write=False)
    return ResidualHead(tuple(vocabulary), fitted, len(explicit_labels))


def evaluate_anchored(samples, features, logits, vocabulary, bank, reference):
    base = normalized_scores(logits)
    support_labels = tuple(reference["supportLabels"])
    predictions = {}
    for writer in sorted({sample.writer for sample in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1 and s.label in support_labels]
        if len(support) != len(support_labels):
            raise ValueError("Incomplete personal support")
        fitted = fit_anchored(features[support], base[support], tuple(samples[i].label for i in support), vocabulary, bank)
        for i, sample in enumerate(samples):
            if sample.writer == writer and sample.session == 2:
                predictions[i] = fitted.rank(features[i], base[i])
    rows = []
    seen = set()
    # No query labels are consulted until every prediction is fixed.
    for prior in reference["rows"]:
        i = prior["sampleIndex"]
        if i in seen or i not in predictions:
            raise ValueError("Duplicate/missing query reference")
        seen.add(i)
        sample = samples[i]
        generic = vocabulary[int(base[i].argmax())]
        if (sample.identity != prior["queryID"] or sample.label != prior["intended"]
                or generic != prior["generic"] or prior["eligible"] != (not prior["exclusions"])):
            raise ValueError("Query reference/model binding changed")
        rows.append({**prior, "personal": predictions[i][0]["label"], "personalRanks": predictions[i][:5],
                     "personalCorrect": predictions[i][0]["label"] == sample.label})
    if seen != set(predictions):
        raise ValueError("Unreported queries")
    eligible = [r for r in rows if r["eligible"]]
    prior_by_id = {r["queryID"]: r for r in reference["rows"]}
    return {**summarize(rows), "supportLabels": support_labels,
            "versusUnanchored": {"gains": sum(r["personalCorrect"] and not prior_by_id[r["queryID"]]["personalCorrect"] for r in eligible),
                                 "harms": sum(not r["personalCorrect"] and prior_by_id[r["queryID"]]["personalCorrect"] for r in eligible)},
            "writers": [{"writer": w, **summarize([r for r in rows if r["writer"] == w])}
                        for w in sorted({s.writer for s in samples})],
            "taught": summarize([r for r in rows if r["taughtLabel"]]),
            "untaught": summarize([r for r in rows if not r["taughtLabel"]]), "rows": rows}


def run(checkpoint: Path, source: Path, reference_path: Path, protocol: Path, output: Path):
    if output.exists():
        raise ValueError("Output must be new; preserve prior evidence")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model, training_report = load_research_model(checkpoint)
    reference_data = reference_path.read_bytes()
    reference = json.loads(reference_data)
    if (training_report["weightsSHA256"] != STARTING_SHA256 or reference["version"] != REFERENCE_VERSION
            or reference["startingWeightsSHA256"] != STARTING_SHA256 or reference["sourceSHA256"] != SOURCE_SHA256
            or reference["reservedWritersEvaluated"] is not False):
        raise ValueError("Wrong frozen source/reference")
    records = load_official_source(source)
    train_writers, dev_writers, reserved = split_writers(records)
    for key, expected in (("trainingWriters", train_writers), ("developmentWriters", dev_writers), ("reservedWriters", reserved)):
        if training_report[key] != list(expected) or reference[key] != list(expected):
            raise ValueError("Writer split changed")
    training = tuple(s for s in records if s.writer in train_writers)
    development = tuple(s for s in records if s.writer in dev_writers)
    vocabulary = tuple(training_report["labels"])
    if vocabulary != tuple(sorted({s.label for s in training})):
        raise ValueError("Encoder vocabulary changed")
    protocol_bytes = protocol.read_bytes()
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "weightsSHA256": STARTING_SHA256,
                "referenceSHA256": hashlib.sha256(reference_data).hexdigest(), "reservedWritersEvaluated": False,
                "trainingWriters": train_writers, "developmentWriters": dev_writers, "reservedWriters": reserved,
                "productionEligible": False, "inferenceAuthority": "research-rank-only",
                "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(),
                "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(Path(__file__).parent.glob("*.py"))}}
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    (output / "frozen-protocol.md").write_bytes(protocol_bytes)
    print("Building public anchors from encoder-training writers only", flush=True)
    training_images, _ = encode_samples(training, train_writers)
    training_features, _ = infer(model, training_images)
    bank = AnchorBank.from_training(training_features, tuple(s.label for s in training), vocabulary)
    anchor_data = json.dumps({"vocabulary": bank.vocabulary, "features": bank.features.tolist(),
                              "sourceSHA256": SOURCE_SHA256, "encoderSHA256": STARTING_SHA256},
                             sort_keys=True, indent=2).encode()
    (output / "public-anchor-bank.json").write_bytes(anchor_data)
    metadata["anchorSHA256"] = hashlib.sha256(anchor_data).hexdigest()
    development_images, _ = encode_samples(development, dev_writers)
    features, logits = infer(model, development_images)
    results = {name: evaluate_anchored(development, features, logits, vocabulary, bank, task)
               for name, task in reference["results"]["starting"].items()}
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source changed")
    report = {**metadata, "sourceUnchanged": True, "results": results}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
    for name, result in results.items():
        print(json.dumps({"profile": name, **summarize(result["rows"]),
                          "versusUnanchored": result["versusUnanchored"],
                          "taught": result["taught"], "untaught": result["untaught"]}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.checkpoint.resolve(), args.source.resolve(), args.reference.resolve(), args.protocol.resolve(), args.output.resolve())
