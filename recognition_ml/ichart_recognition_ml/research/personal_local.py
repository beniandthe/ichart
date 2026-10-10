"""Research-only local residual learning over the frozen personal ML encoder."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import torch

from .personal_adaptability import STARTING_SHA256, VERSION as REFERENCE_VERSION, summarize
from .personal_anchors import VERSION as ANCHOR_VERSION
from .personal_encoder_export import load_research_model
from .personal_residual import normalized_scores, validate_features, validate_scores
from .personal_visual_encoder import encode_samples, infer
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers, trajectory_fingerprint

VERSION = "personal-local-residual-v1"


def rbf(left, right, width):
    left = np.asarray(left, dtype=np.float64)
    right = np.asarray(right, dtype=np.float64)
    validate_features(left)
    validate_features(right)
    if left.shape[1] != right.shape[1] or not math.isfinite(width) or width <= 0:
        raise ValueError("Invalid local kernel width or feature dimensions")
    distance = (np.einsum("nd,nd->n", left, left)[:, None]
                + np.einsum("md,md->m", right, right)[None, :]
                - 2 * np.einsum("nd,md->nm", left, right, optimize=False))
    # Round-off at identical unit vectors must not produce similarities > 1.
    return np.exp(-np.maximum(distance, 0) / width)


@dataclass(frozen=True)
class LocalResidualHead:
    vocabulary: tuple[str, ...]
    features: np.ndarray
    coefficients: np.ndarray
    width: float

    @classmethod
    def fit(cls, features, base_scores, explicit_labels, vocabulary, width, regularization=0.1):
        features = np.array(features, dtype=np.float64, copy=True)
        base_scores = np.asarray(base_scores, dtype=np.float64)
        labels, vocabulary = tuple(explicit_labels), tuple(vocabulary)
        validate_features(features)
        count = len(features)
        if (not 0 <= count <= 192 or count != len(labels)
                or not 2 <= len(vocabulary) <= 512 or len(set(vocabulary)) != len(vocabulary)
                or any(not isinstance(label, str) or not label for label in vocabulary)
                or any(label not in vocabulary for label in labels)):
            raise ValueError("Invalid explicit lessons or vocabulary")
        if not math.isfinite(regularization) or regularization <= 0:
            raise ValueError("Invalid regularization")
        validate_scores(base_scores, count, len(vocabulary))
        gram = rbf(features, features, width)
        if count:
            balance = np.array([1 / math.sqrt(labels.count(label)) for label in labels])
            residuals = np.array([[float(label == c) for c in vocabulary] for label in labels]) - base_scores
            weighted = gram * balance[:, None] * balance[None, :]
            beta = np.linalg.solve(weighted + regularization * np.eye(count), residuals * balance[:, None])
            coefficients = beta * balance[:, None]
        else:
            coefficients = np.zeros((0, len(vocabulary)))
        if not np.isfinite(coefficients).all():
            raise ValueError("Nonfinite local personal fit")
        features.setflags(write=False)
        coefficients.setflags(write=False)
        return cls(vocabulary, features, coefficients, float(width))

    def rank(self, feature, base_scores):
        feature = np.asarray(feature, dtype=np.float64)
        scores = np.asarray(base_scores, dtype=np.float64)
        if feature.shape != (self.features.shape[1],):
            raise ValueError("Wrong query feature shape")
        validate_scores(scores[None, :], 1, len(self.vocabulary))
        correction = np.einsum("n,nc->c", rbf(feature[None, :], self.features, self.width)[0], self.coefficients)
        adjusted = scores + correction
        if not np.isfinite(adjusted).all():
            raise ValueError("Nonfinite adjusted ranks")
        return sorted(({"label": c, "score": float(s)} for c, s in zip(self.vocabulary, adjusted)),
                      key=lambda row: (-row["score"], row["label"]))


def training_width(samples, features, raster_hashes, training_writers, vocabulary):
    """Use known training-writer pairs only; no development queries are accepted."""
    features = np.asarray(features, dtype=np.float64)
    validate_features(features)
    if (len(samples) != len(features) or len(samples) != len(raster_hashes)
            or len(set(training_writers)) != len(training_writers)
            or len(set(vocabulary)) != len(vocabulary) or not vocabulary
            or any(not writer.startswith("trn_") for writer in training_writers)
            or any(s.writer not in training_writers or s.session not in (1, 2) or s.label not in vocabulary for s in samples)):
        raise ValueError("Wrong training-only width source")
    by_key = {(s.writer, s.session, s.label): i for i, s in enumerate(samples)}
    if len(by_key) != len(samples) or len(samples) != len(training_writers) * 2 * len(vocabulary):
        raise ValueError("Incomplete or duplicate training sessions")
    pairs = []
    for writer in sorted(training_writers):
        for label in vocabulary:
            a, b = by_key[(writer, 1, label)], by_key[(writer, 2, label)]
            distance = float(np.sum((features[a] - features[b]) ** 2))
            exclusions = []
            if trajectory_fingerprint(samples[a]) == trajectory_fingerprint(samples[b]):
                exclusions.append("normalized-trajectory-copy")
            if raster_hashes[a] == raster_hashes[b]:
                exclusions.append("raster-copy")
            if distance <= 0:
                exclusions.append("zero-feature-distance")
            pairs.append({"sourceIDs": [samples[a].identity, samples[b].identity], "squaredDistance": distance,
                          "exclusions": exclusions})
    eligible = [row["squaredDistance"] for row in pairs if not row["exclusions"]]
    if not eligible:
        raise ValueError("No non-copy training pairs for kernel width")
    width = float(np.median(eligible))
    if not math.isfinite(width) or width <= 0:
        raise ValueError("Invalid training-derived width")
    return {"width": width, "pairCount": len(pairs), "eligiblePairs": len(eligible),
            "rule": "median-positive-within-writer-cross-session-same-label-squared-distance", "pairs": pairs}


def evaluate_local(samples, features, logits, vocabulary, width, reference, anchor_reference, *, fit=None):
    base = normalized_scores(logits)
    support_labels = tuple(reference["supportLabels"])
    if tuple(anchor_reference["supportLabels"]) != support_labels:
        raise ValueError("Reference support labels changed")
    predictions, support_ids = {}, {}
    for writer in sorted({s.writer for s in samples}):
        support = [i for i, s in enumerate(samples) if s.writer == writer and s.session == 1 and s.label in support_labels]
        if len(support) != len(support_labels) or {samples[i].label for i in support} != set(support_labels):
            raise ValueError("Incomplete explicit support")
        fitter = fit or LocalResidualHead.fit
        model = fitter(features[support], base[support], tuple(samples[i].label for i in support), vocabulary, width)
        support_ids[writer] = sorted(samples[i].identity for i in support)
        for i, s in enumerate(samples):
            if s.writer == writer and s.session == 2:
                predictions[i] = model.rank(features[i], base[i])
    # No query labels are consulted above; scoring begins only after inference.
    rows, seen = [], set()
    anchors = {row["queryID"]: row for row in anchor_reference["rows"]}
    if len(anchors) != len(anchor_reference["rows"]):
        raise ValueError("Duplicate anchor reference")
    for prior in reference["rows"]:
        i = prior["sampleIndex"]
        if i in seen or i not in predictions:
            raise ValueError("Missing or duplicate query")
        seen.add(i)
        s = samples[i]
        anchor = anchors.get(s.identity)
        if (s.identity != prior["queryID"] or s.label != prior["intended"]
                or vocabulary[int(base[i].argmax())] != prior["generic"]
                or prior["eligible"] != (not prior["exclusions"]) or anchor is None
                or prior["supportIDs"] != support_ids[s.writer]
                or prior["taughtLabel"] != (s.label in support_labels)
                or any(anchor[k] != prior[k] for k in ("generic", "queryID", "eligible", "exclusions", "intended"))):
            raise ValueError("Changed source or comparison binding")
        rows.append({**prior, "linearPersonal": prior["personal"], "anchoredPersonal": anchor["personal"],
                     "personal": predictions[i][0]["label"], "personalRanks": predictions[i][:5],
                     "personalCorrect": predictions[i][0]["label"] == s.label})
    if seen != set(predictions) or {row["queryID"] for row in rows} != set(anchors):
        raise ValueError("Unreported query identities")
    eligible = [row for row in rows if row["eligible"]]
    changes = {name: {"correct": sum(row[name] == row["intended"] for row in eligible),
                      "gains": sum(row["personalCorrect"] and row[name] != row["intended"] for row in eligible),
                      "harms": sum(not row["personalCorrect"] and row[name] == row["intended"] for row in eligible)}
               for name in ("generic", "linearPersonal", "anchoredPersonal")}
    return {**summarize(rows), "supportLabels": support_labels, "comparisons": changes,
            "taught": summarize([r for r in rows if r["taughtLabel"]]),
            "untaught": summarize([r for r in rows if not r["taughtLabel"]]),
            "writers": [{"writer": w, **summarize([r for r in rows if r["writer"] == w])}
                        for w in sorted({s.writer for s in samples})], "rows": rows}


def run(checkpoint: Path, source: Path, reference_path: Path, anchor_path: Path, protocol: Path, output: Path):
    if output.exists():
        raise ValueError("Output must be new")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model, training = load_research_model(checkpoint)
    reference_bytes, anchor_bytes, protocol_bytes = reference_path.read_bytes(), anchor_path.read_bytes(), protocol.read_bytes()
    reference, anchor = json.loads(reference_bytes), json.loads(anchor_bytes)
    reference_sha = hashlib.sha256(reference_bytes).hexdigest()
    if (training["weightsSHA256"] != STARTING_SHA256 or reference["version"] != REFERENCE_VERSION
            or reference["startingWeightsSHA256"] != STARTING_SHA256 or reference["sourceSHA256"] != SOURCE_SHA256
            or anchor["version"] != ANCHOR_VERSION or anchor["weightsSHA256"] != STARTING_SHA256
            or anchor["sourceSHA256"] != SOURCE_SHA256 or anchor["referenceSHA256"] != reference_sha
            or reference["reservedWritersEvaluated"] is not False or anchor["reservedWritersEvaluated"] is not False):
        raise ValueError("Wrong frozen source, weights or references")
    records = load_official_source(source)
    train_writers, dev_writers, reserved = split_writers(records)
    for key, expected in (("trainingWriters", train_writers), ("developmentWriters", dev_writers), ("reservedWriters", reserved)):
        if any(report[key] != list(expected) for report in (training, reference, anchor)):
            raise ValueError("Writer split changed")
    vocabulary = tuple(training["labels"])
    tasks = reference["results"]["starting"]
    if (set(tasks) != {"sparse16", "full97"} or set(anchor["results"]) != set(tasks)
            or any(len(task["rows"]) != 776 or sum(row["eligible"] for row in task["rows"]) != 772 for task in tasks.values())):
        raise ValueError("Frozen task denominator changed")
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "weightsSHA256": STARTING_SHA256,
                "referenceSHA256": reference_sha, "anchorReferenceSHA256": hashlib.sha256(anchor_bytes).hexdigest(),
                "protocolSHA256": hashlib.sha256(protocol_bytes).hexdigest(), "productionEligible": False,
                "inferenceAuthority": "research-rank-only", "reservedWritersEvaluated": False,
                "trainingWriters": train_writers, "developmentWriters": dev_writers, "reservedWriters": reserved,
                "regularization": 0.1, "numpy": np.__version__, "torch": torch.__version__,
                "codeSHA256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(Path(__file__).parent.glob("*.py"))}}
    output.mkdir(parents=True, exist_ok=False)
    (output / "protocol.json").write_text(json.dumps(metadata, indent=2, sort_keys=True))
    (output / "frozen-protocol.md").write_bytes(protocol_bytes)
    public_training = tuple(s for s in records if s.writer in train_writers)
    images, rasters = encode_samples(public_training, train_writers)
    train_features, _ = infer(model, images)
    width_report = training_width(public_training, train_features, rasters, train_writers, vocabulary)
    width_bytes = json.dumps(width_report, indent=2, sort_keys=True).encode()
    (output / "public-width.json").write_bytes(width_bytes)
    print(json.dumps({k: width_report[k] for k in ("width", "pairCount", "eligiblePairs")}), flush=True)
    development = tuple(s for s in records if s.writer in dev_writers)
    dev_images, _ = encode_samples(development, dev_writers)
    features, logits = infer(model, dev_images)
    results = {name: evaluate_local(development, features, logits, vocabulary, width_report["width"], task, anchor["results"][name])
               for name, task in tasks.items()}
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source changed")
    # Fixed next-step gate, not a ship/accuracy gate.
    may_advance = (all(result["personalCorrect"] >= max(result["comparisons"][key]["correct"]
                     for key in ("linearPersonal", "anchoredPersonal")) for result in results.values())
                   and results["sparse16"]["comparisons"]["generic"]["harms"] <= anchor["results"]["sparse16"]["harms"])
    report = {**metadata, "widthSHA256": hashlib.sha256(width_bytes).hexdigest(), "width": width_report["width"],
              "sourceUnchanged": True, "mayAdvanceToAppComparison": may_advance, "results": results}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True))
    for name, result in results.items():
        print(json.dumps({"profile": name, **summarize(result["rows"]), "comparisons": result["comparisons"],
                          "taught": result["taught"], "untaught": result["untaught"]}), flush=True)
    print(json.dumps({"mayAdvanceToAppComparison": may_advance}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("checkpoint", "source", "reference", "anchors", "protocol", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    run(args.checkpoint.resolve(), args.source.resolve(), args.reference.resolve(), args.anchors.resolve(),
        args.protocol.resolve(), args.output.resolve())
