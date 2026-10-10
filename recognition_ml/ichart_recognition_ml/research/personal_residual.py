"""Comparison-only personal correction learning over frozen visual features.

No private profile mutation, model confidence, or app acceptance authority.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import torch

from .personal_encoder_export import load_research_model
from .personal_visual_encoder import ROOTS, encode_samples, fit_personal, infer, rank_personal
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "personal-residual-ridge-v1"


def normalized_scores(logits: np.ndarray) -> np.ndarray:
    logits = np.asarray(logits, dtype=np.float64)
    if logits.ndim not in (1, 2) or not 2 <= logits.shape[-1] <= 512 or not np.isfinite(logits).all():
        raise ValueError("Invalid generic logits")
    if np.any(np.abs(logits) > 1e6):
        raise ValueError("Unrepresentable generic logits")
    shifted = logits - logits.max(axis=-1, keepdims=True)
    values = np.exp(shifted)
    return values / values.sum(axis=-1, keepdims=True)


def validate_features(features: np.ndarray) -> None:
    if features.ndim != 2 or not 0 < features.shape[1] <= 2048 or not np.isfinite(features).all():
        raise ValueError("Invalid personal feature matrix")
    norms = np.sqrt(np.einsum("nd,nd->n", features, features, optimize=False))
    if np.any(np.abs(norms - 1) > 1e-3):
        raise ValueError("Personal embeddings must have unit norm")


def validate_scores(scores: np.ndarray, count: int, width: int) -> None:
    if scores.shape != (count, width) or not np.isfinite(scores).all():
        raise ValueError("Invalid normalized score matrix")
    if np.any(scores < 0) or np.any(scores > 1) or np.any(np.abs(scores.sum(axis=1) - 1) > 1e-8):
        raise ValueError("Generic scores must be normalized, not raw logits")


@dataclass(frozen=True)
class ResidualHead:
    vocabulary: tuple[str, ...]
    weights: np.ndarray
    lesson_count: int

    @classmethod
    def fit(cls, features, base_scores, explicit_labels: tuple[str, ...], vocabulary: tuple[str, ...], regularization=0.1):
        features = np.asarray(features, dtype=np.float64)
        base_scores = np.asarray(base_scores, dtype=np.float64)
        validate_features(features)
        count, width = features.shape
        if not 0 <= count <= 192 or count != len(explicit_labels):
            raise ValueError("Invalid lesson count")
        if (not 2 <= len(vocabulary) <= 512 or len(set(vocabulary)) != len(vocabulary)
                or any(not isinstance(label, str) or not label for label in vocabulary)
                or any(label not in vocabulary for label in explicit_labels)):
            raise ValueError("Invalid or unknown explicit vocabulary")
        if not math.isfinite(regularization) or regularization <= 0:
            raise ValueError("Invalid regularization")
        validate_scores(base_scores, count, len(vocabulary))
        if count == 0:
            fitted = np.zeros((width, len(vocabulary)))
        else:
            weights = np.array([1 / math.sqrt(explicit_labels.count(label)) for label in explicit_labels])
            targets = np.array([[float(label == c) for c in vocabulary] for label in explicit_labels])
            residuals = (targets - base_scores) * weights[:, None]
            x = features * weights[:, None]
            gram = np.einsum("nd,md->nm", x, x, optimize=False)
            coefficients = np.linalg.solve(gram + regularization * np.eye(count), residuals)
            fitted = np.einsum("nd,nc->dc", x, coefficients, optimize=False)
        if not np.isfinite(fitted).all():
            raise ValueError("Nonfinite personal correction")
        fitted.setflags(write=False)
        return cls(tuple(vocabulary), fitted, count)

    def rank(self, feature, base_scores) -> list[dict]:
        feature = np.asarray(feature, dtype=np.float64)
        scores = np.asarray(base_scores, dtype=np.float64)
        if feature.shape != (self.weights.shape[0],):
            raise ValueError("Wrong query feature shape")
        validate_features(feature[None, :])
        validate_scores(scores[None, :], 1, len(self.vocabulary))
        correction = np.einsum("d,dc->c", feature, self.weights, optimize=False)
        adjusted = scores + correction
        if not np.isfinite(adjusted).all():
            raise ValueError("Nonfinite adjusted ranks")
        return sorted(({"label": label, "score": float(value)} for label, value in zip(self.vocabulary, adjusted)),
                      key=lambda row: (-row["score"], row["label"]))


def evaluate_task(samples, features, logits, all_labels, vocabulary, copy_reference):
    columns = [all_labels.index(label) for label in vocabulary]
    base = normalized_scores(logits[:, columns])
    rows, writers = [], []
    for writer in sorted({sample.writer for sample in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1 and s.label in vocabulary]
        queries = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 2 and s.label in vocabulary]
        if len(support) != len(vocabulary) or len(queries) != len(vocabulary):
            raise ValueError("Incomplete personal comparison session")
        labels = tuple(samples[i].label for i in support)
        personal = fit_personal(features[support], labels)
        residual = ResidualHead.fit(features[support], base[support], labels, vocabulary)
        writer_rows = []
        for i in queries:
            generic_label = vocabulary[int(base[i].argmax())]
            personal_label = rank_personal(personal, features[i])[0]["label"]
            residual_ranks = residual.rank(features[i], base[i])
            predictions = {"generic": generic_label, "replacementPersonal": personal_label,
                           "correctionPersonal": residual_ranks[0]["label"]}
            # Query answers are consulted only after predictions are fixed.
            query = samples[i]
            reference = copy_reference[query.identity]
            if reference["intended"] != query.label:
                raise ValueError("Copy/reference identity does not match source")
            row = {"queryID": query.identity, "writer": writer, "intended": query.label,
                   "eligible": reference["eligible"], "exclusions": reference["exclusions"],
                   "predictions": predictions, "correct": {key: label == query.label for key, label in predictions.items()},
                   "correctionRanks": residual_ranks[:5], "rankOnlyNotAccepted": True}
            rows.append(row)
            writer_rows.append(row)
        eligible = [r for r in writer_rows if r["eligible"]]
        writers.append({"writer": writer, "supportIDs": sorted(samples[i].identity for i in support),
                        "eligible": len(eligible), "correct": {key: sum(r["correct"][key] for r in eligible)
                                                              for key in predictions}})
    eligible = [r for r in rows if r["eligible"]]
    correct = {key: sum(r["correct"][key] for r in eligible) for key in rows[0]["correct"]}
    comparisons = {key: {"gains": sum(r["correct"]["correctionPersonal"] and not r["correct"][key] for r in eligible),
                         "harms": sum(not r["correct"]["correctionPersonal"] and r["correct"][key] for r in eligible)}
                   for key in ("generic", "replacementPersonal")}
    return {"vocabulary": vocabulary, "queries": len(rows), "eligibleQueries": len(eligible),
            "correct": correct, "correctionVersus": comparisons, "writers": writers, "rows": rows}


def run(checkpoint: Path, source: Path, reference_path: Path, output: Path):
    if output.exists():
        raise ValueError("Output directory must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model, training_report = load_research_model(checkpoint)
    reference_bytes = reference_path.read_bytes()
    reference = json.loads(reference_bytes)
    training_sha = hashlib.sha256((checkpoint / "report.json").read_bytes()).hexdigest()
    if reference["trainingReportSHA256"] != training_sha or reference["weightsSHA256"] != training_report["weightsSHA256"]:
        raise ValueError("Wrong reference/checkpoint binding")
    rows = {r["queryID"]: r for r in reference["rows"]}
    if len(rows) != 776 or len(reference["rows"]) != 776:
        raise ValueError("Missing or duplicate reference queries")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    if (list(training) != training_report["trainingWriters"] or list(development) != training_report["developmentWriters"]
            or list(reserved) != training_report["reservedWriters"]):
        raise ValueError("Frozen writer split changed")
    samples = tuple(s for s in records if s.writer in development)
    images, _ = encode_samples(samples, development)
    features, logits = infer(model, images)
    labels = tuple(training_report["labels"])
    result = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "weightsSHA256": training_report["weightsSHA256"],
              "trainingReportSHA256": training_sha, "referenceSHA256": hashlib.sha256(reference_bytes).hexdigest(),
              "regularization": 0.1, "productionEligible": False, "reservedWritersEvaluated": False,
              "developmentWriters": development,
              "rootTask": evaluate_task(samples, features, logits, labels, ROOTS, rows),
              "characterTask": evaluate_task(samples, features, logits, labels, labels, rows)}
    output.mkdir(parents=True, exist_ok=False)
    (output / "report.json").write_text(json.dumps(result, indent=2, sort_keys=True))
    for name in ("rootTask", "characterTask"):
        print(json.dumps({"task": name, **{k: result[name][k] for k in ("eligibleQueries", "correct", "correctionVersus")}}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.checkpoint.resolve(), args.source.resolve(), args.reference.resolve(), args.output.resolve())
