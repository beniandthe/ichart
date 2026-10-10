"""Public-only, writer-separated stroke ownership experiment.

Fit and evaluation are separate commands. No app/profile mutation, private ink,
reserved-writer feature construction, chord answers, or acceptance authority.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import platform
import time
from typing import Iterable

import numpy as np
import torch
from torch.nn import functional as F

from ..features import InkBounds, InkPoint, InkStroke
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers, trajectory_fingerprint
from .stroke_affinity import FEATURE_SCHEMA, StrokeAffinityModel, all_pair_features, partition_from_logits

VERSION = "public-stroke-affinity-experiment-v1"
FEATURE_COUNT = 202
SEED = 29
EPOCHS = 30
BATCH_SIZE = 512
SINGLE_ARM = "single32"
PAIR_ARMS = tuple((dimension, gap) for dimension in (16.0, 32.0) for gap in (3.2, 8.0, 16.0))
TRIPLE_ARM = "triple32-16-16-gap8-8"


@dataclass(frozen=True)
class Target:
    identity: str
    role: str
    writer: str
    session: int
    arm: str
    source_ids: tuple[str, ...]
    strokes: tuple[InkStroke, ...]
    owners: tuple[tuple[int, ...], ...]
    zero_extent_characters: int
    single_label: str | None = None  # Audit only; never passed to features/model.


@dataclass(frozen=True)
class TrainingRows:
    ab: np.ndarray
    ba: np.ndarray
    labels: np.ndarray
    weights: np.ndarray
    summary: dict


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    paths = (Path(__file__).resolve(), Path(__file__).with_name("stroke_affinity.py"),
             Path(__file__).with_name("uji_personal.py"), root / "recognition_ml/ichart_recognition_ml/features.py",
             root / "recognition_ml/ichart_recognition_ml/schema.py",
             root / "recognition_ml/tests/test_stroke_affinity_experiment.py",
             root / "recognition_ml/tests/test_stroke_affinity.py",
             root / "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md")
    return {str(path.relative_to(root)): _digest(path.read_bytes()) for path in paths}


@contextmanager
def preserved_inputs(paths: tuple[Path, ...]):
    originals, code = {path: path.read_bytes() for path in paths}, code_identity()
    try:
        yield
    finally:
        if any(path.read_bytes() != data for path, data in originals.items()) or code_identity() != code:
            raise ValueError("Source, frozen artifacts, protocol, or code changed during the operation")


def validate_role(samples: tuple[Sample, ...], role: str, allowed_writers: tuple[str, ...]) -> None:
    expected = {"training": 32, "development": 8}.get(role)
    if (expected is None or len(allowed_writers) != expected or len(set(allowed_writers)) != expected
            or any(not writer.startswith("trn_") for writer in allowed_writers)
            or not samples or any(sample.writer not in allowed_writers or sample.session not in (1, 2)
                                   for sample in samples)
            or len({sample.identity for sample in samples}) != len(samples)):
        raise ValueError("Reserved, duplicate, or wrong-role public sample")


def point_bounds(strokes: tuple[InkStroke, ...]) -> tuple[float, float, float, float]:
    points = [point for stroke in strokes for point in stroke.points]
    if not points or any(not math.isfinite(value) for point in points for value in (point.x, point.y)):
        raise ValueError("Invalid public geometry")
    return min(p.x for p in points), min(p.y for p in points), max(p.x for p in points), max(p.y for p in points)


def affine(strokes: tuple[InkStroke, ...], scale: float, dx: float, dy: float) -> tuple[InkStroke, ...]:
    if not math.isfinite(scale) or scale <= 0 or not all(map(math.isfinite, (dx, dy))):
        raise ValueError("Invalid affine representation")
    result = []
    for stroke in strokes:
        bounds = stroke.bounds
        if (bounds is None or not stroke.points or any(not math.isfinite(value) for value in
                (bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y))
                or bounds.min_x > bounds.max_x or bounds.min_y > bounds.max_y):
            raise ValueError("Invalid public stroke bounds")
        result.append(InkStroke(tuple(InkPoint(point.x * scale + dx, point.y * scale + dy,
                                             point.time_offset) for point in stroke.points),
            InkBounds(bounds.min_x * scale + dx, bounds.min_y * scale + dy,
                      bounds.max_x * scale + dx, bounds.max_y * scale + dy),
            stroke.creation_time_offset))
    return tuple(result)


def normalize(strokes: tuple[InkStroke, ...], dimension: float = 32) -> tuple[InkStroke, ...]:
    if not math.isfinite(dimension) or dimension <= 0:
        raise ValueError("Invalid dimension")
    left, top, right, bottom = point_bounds(strokes)
    span = max(right - left, bottom - top)
    scale = dimension / span if span > 0 else 1
    return affine(strokes, scale, -left * scale, -top * scale)


def compose(stroke_sets: tuple[tuple[InkStroke, ...], ...], dimensions: tuple[float, ...],
            gaps: tuple[float, ...]) -> tuple[tuple[InkStroke, ...], tuple[tuple[int, ...], ...], int]:
    if (len(stroke_sets) not in (2, 3) or len(dimensions) != len(stroke_sets)
            or len(gaps) != len(stroke_sets) - 1 or any(gap <= 0 or not math.isfinite(gap) for gap in gaps)):
        raise ValueError("Invalid composition")
    result, owners, left_edge, zero_extent = [], [], 0.0, 0
    for index, (source, dimension) in enumerate(zip(stroke_sets, dimensions)):
        # Match Swift: normalize to 32, then apply the second uniform scale;
        # zero-extent glyphs retain scale one and every original point.
        at32 = normalize(source)
        left, top, right, bottom = point_bounds(at32)
        normalized = affine(at32, dimension / 32 if max(right - left, bottom - top) > 0 else 1, 0, 0)
        left, top, right, bottom = point_bounds(normalized)
        zero_extent += int(right == left and bottom == top)
        translated = affine(normalized, 1, left_edge - left, 32 - bottom)
        owners.append(tuple(range(len(result), len(result) + len(translated))))
        result.extend(translated)
        left_edge += right - left
        if index < len(gaps):
            left_edge += gaps[index]
    return tuple(result), tuple(owners), zero_extent


def cyclic_sequences(samples: tuple[Sample, ...], count: int) -> tuple[tuple[Sample, ...], ...]:
    if count not in (2, 3):
        raise ValueError("Invalid cyclic composition size")
    batches = defaultdict(list)
    for sample in samples:
        batches[(sample.writer, sample.session)].append(sample)
    if any(len(batch) != 97 or len({sample.label for sample in batch}) != 97 for batch in batches.values()):
        raise ValueError("Incomplete writer/session composition source")
    prefix = "public-pair-v1:" if count == 2 else "public-triple-v1:"
    result = []
    for key in sorted(batches):
        ordered = sorted(batches[key], key=lambda sample: (_digest((prefix + sample.identity).encode()), sample.identity))
        result.extend(tuple(ordered[(index + offset) % len(ordered)] for offset in range(count))
                      for index in range(len(ordered)))
    return tuple(result)


def build_targets(samples: tuple[Sample, ...], role: str, allowed_writers: tuple[str, ...],
                  *, include_triple: bool = False) -> tuple[Target, ...]:
    # Role rejection precedes any affine transformation or feature construction.
    validate_role(samples, role, allowed_writers)
    if include_triple and role != "development":
        raise ValueError("Triple stress targets are development-only")
    result = []
    for sample in sorted(samples, key=lambda item: item.identity):
        strokes = normalize(sample.strokes)
        bounds = point_bounds(strokes)
        result.append(Target(sample.identity + "/" + SINGLE_ARM, role, sample.writer, sample.session,
            SINGLE_ARM, (sample.identity,), strokes, (tuple(range(len(strokes))),),
            int(bounds[0] == bounds[2] and bounds[1] == bounds[3]), sample.label))
    for first, second in cyclic_sequences(samples, 2):
        for dimension, gap in PAIR_ARMS:
            strokes, owners, zero_extent = compose((first.strokes, second.strokes), (32, dimension), (gap,))
            arm = f"second{int(dimension)}-gap{gap:g}"
            result.append(Target(first.identity + "+" + second.identity + "/" + arm, role,
                first.writer, first.session, arm, (first.identity, second.identity), strokes, owners, zero_extent))
    if include_triple:
        for first, second, third in cyclic_sequences(samples, 3):
            strokes, owners, zero_extent = compose((first.strokes, second.strokes, third.strokes),
                                                   (32, 16, 16), (8, 8))
            result.append(Target("+".join((first.identity, second.identity, third.identity)) + "/" + TRIPLE_ARM,
                role, first.writer, first.session, TRIPLE_ARM, (first.identity, second.identity, third.identity),
                strokes, owners, zero_extent))
    return tuple(result)


def owner_labels(count: int, edges: tuple[tuple[int, int], ...], owners: tuple[tuple[int, ...], ...]) -> np.ndarray:
    flattened = [index for owner in owners for index in owner]
    if not owners or any(not owner for owner in owners) or sorted(flattened) != list(range(count)):
        raise ValueError("Ownership truth must cover source exactly once")
    lookup = {index: owner_index for owner_index, owner in enumerate(owners) for index in owner}
    if len(edges) != count * (count - 1) // 2 or set(edges) != {(i, j) for i in range(count) for j in range(i + 1, count)}:
        raise ValueError("Incomplete pair features")
    return np.asarray([float(lookup[i] == lookup[j]) for i, j in edges], dtype=np.float32)


def audit_trajectory_copies(training_samples: tuple[Sample, ...], development_samples: tuple[Sample, ...],
                            training_writers: tuple[str, ...], development_writers: tuple[str, ...]) -> dict:
    validate_role(training_samples, "training", training_writers)
    validate_role(development_samples, "development", development_writers)
    if set(training_writers) & set(development_writers):
        raise ValueError("Training/development writers overlap")
    by_hash = defaultdict(lambda: {"training": [], "development": []})
    for role, samples in (("training", training_samples), ("development", development_samples)):
        for sample in samples:
            by_hash[trajectory_fingerprint(sample)][role].append(sample.identity)
    overlaps = [{"normalizedTrajectorySHA256": digest, "trainingSourceIDs": sorted(roles["training"]),
                 "developmentSourceIDs": sorted(roles["development"])}
                for digest, roles in sorted(by_hash.items()) if roles["training"] and roles["development"]]
    return {"method": "exact-existing-normalized-trajectory-fingerprint-rounded-8-decimals",
        "sourceTrainingSamples": len(training_samples), "sourceDevelopmentSamples": len(development_samples),
        "crossRoleFingerprintGroups": len(overlaps),
        "developmentSourceCopyExposure": sum(len(row["developmentSourceIDs"]) for row in overlaps),
        "withinTrainingDuplicateSamples": sum(max(0, len(roles["training"]) - 1) for roles in by_hash.values()),
        "withinDevelopmentDuplicateSamples": sum(max(0, len(roles["development"]) - 1) for roles in by_hash.values()),
        "overlaps": overlaps, "exclusionPolicy": "no-posthoc-exclusions; expose-copies-separately"}


def training_target_stream(samples: tuple[Sample, ...], allowed_writers: tuple[str, ...]):
    # Validate the complete source role before any target/features are yielded.
    validate_role(samples, "training", allowed_writers)
    def iterator():
        for writer in sorted({sample.writer for sample in samples}):
            writer_samples = tuple(sample for sample in samples if sample.writer == writer)
            yield from build_targets(writer_samples, "training", allowed_writers)
    return iterator()


def training_plan(samples: tuple[Sample, ...], allowed_writers: tuple[str, ...]) -> dict:
    """Geometry/metadata preflight only: no affinity features or predictions."""
    validate_role(samples, "training", allowed_writers)
    targets, edges, singletons, arm_counts = 0, 0, 0, Counter()
    for target in training_target_stream(samples, allowed_writers):
        count = len(target.strokes)
        if not 1 <= count <= 64 or sum(len(stroke.points) for stroke in target.strokes) > 8192:
            raise ValueError("Public target exceeds the frozen affinity contract")
        targets += 1
        edges += count * (count - 1) // 2
        singletons += int(count == 1)
        arm_counts[target.arm] += 1
    return {"trainingSamples": len(samples), "targets": targets, "targetsByArm": dict(sorted(arm_counts.items())),
        "edgeRows": edges, "singletonTargetsExcludedFromLoss": singletons,
        "rawABBAFloat32Bytes": edges * FEATURE_COUNT * 4 * 2,
        "standardizedABBAFloat32Bytes": edges * FEATURE_COUNT * 4 * 2,
        "epochs": EPOCHS, "batchesPerEpoch": math.ceil(edges / BATCH_SIZE),
        "fittingBatchSteps": EPOCHS * math.ceil(edges / BATCH_SIZE),
        "affinityFeaturesConstructed": False, "developmentFeaturesConstructed": False}


def training_rows(targets: Iterable[Target], allowed_writers: tuple[str, ...], *, progress: bool = False) -> TrainingRows:
    if (len(allowed_writers) != 32 or len(set(allowed_writers)) != 32 or not targets
            or any(not writer.startswith("trn_") for writer in allowed_writers)):
        raise ValueError("Only original training writers may reach training features")
    def valid_target(target):
        return target.role == "training" and target.writer in allowed_writers and target.arm != TRIPLE_ARM
    if isinstance(targets, (tuple, list)) and any(not valid_target(target) for target in targets):
        raise ValueError("Wrong-role target reached training")
    ab_rows, ba_rows, labels, base_weights = [], [], [], []
    per_arm, singletons, zero_extent, edge_row_count = Counter(), 0, 0, 0
    target_count = 0
    for target_index, target in enumerate(targets):
        if not valid_target(target):
            raise ValueError("Wrong-role target reached training")
        target_count += 1
        # The feature API receives ink only. Truth is applied afterward.
        edges, ab, ba = all_pair_features(target.strokes)
        truth = owner_labels(len(target.strokes), edges, target.owners)
        if ab.shape != (len(edges), FEATURE_COUNT) or ba.shape != ab.shape:
            raise ValueError("Wrong affinity feature contract")
        per_arm[target.arm] += 1
        zero_extent += target.zero_extent_characters
        if not edges:
            singletons += 1
        else:
            ab_rows.append(ab); ba_rows.append(ba); labels.append(truth)
            base_weights.append(np.full(len(edges), 1 / len(edges), dtype=np.float64))
            edge_row_count += len(edges)
        if progress and (target_index + 1) % 1000 == 0:
            print(json.dumps({"stage": "training-features", "targetsCompleted": target_index + 1,
                              "edgeRowsCompleted": edge_row_count}, sort_keys=True), flush=True)
    if not ab_rows:
        raise ValueError("No non-singleton training edges")
    ab, ba, y, base = np.concatenate(ab_rows), np.concatenate(ba_rows), np.concatenate(labels), np.concatenate(base_weights)
    if not np.isfinite(ab).all() or not np.isfinite(ba).all():
        raise ValueError("Nonfinite training features")
    positive_mass, negative_mass = float(base[y == 1].sum()), float(base[y == 0].sum())
    if min(positive_mass, negative_mass) <= 0:
        raise ValueError("Both ownership classes are required")
    total = positive_mass + negative_mass
    weights = base * np.where(y == 1, total / (2 * positive_mass), total / (2 * negative_mass))
    return TrainingRows(ab, ba, y, weights, {"targets": target_count, "targetsByArm": dict(sorted(per_arm.items())),
        "singletonTargetsExcludedFromLoss": singletons, "zeroExtentCharacters": zero_extent,
        "edgeRows": len(y), "positiveEdges": int((y == 1).sum()), "negativeEdges": int((y == 0).sum()),
        "unbalancedPositiveMass": positive_mass, "unbalancedNegativeMass": negative_mass,
        "balancedPositiveMass": float(weights[y == 1].sum()), "balancedNegativeMass": float(weights[y == 0].sum())})


def weighted_standardization(rows: TrainingRows) -> tuple[torch.Tensor, torch.Tensor]:
    if (rows.ab.shape != rows.ba.shape or rows.ab.ndim != 2 or rows.ab.shape[1] != FEATURE_COUNT
            or rows.weights.shape != (len(rows.ab),) or not np.isfinite(rows.weights).all()
            or np.any(rows.weights <= 0) or not np.isfinite(rows.ab).all() or not np.isfinite(rows.ba).all()):
        raise ValueError("Invalid training statistics")
    sums = torch.zeros(FEATURE_COUNT, dtype=torch.float64)
    squares = torch.zeros_like(sums)
    for start in range(0, len(rows.weights), 4096):
        weight = torch.as_tensor(rows.weights[start:start + 4096], dtype=torch.float64)[:, None]
        for features in (rows.ab, rows.ba):
            x = torch.as_tensor(features[start:start + 4096], dtype=torch.float64)
            sums += (x * weight).sum(0)
            squares += (x.square() * weight).sum(0)
    mass = float(rows.weights.sum()) * 2
    mean = sums / mass
    variance = squares / mass - mean.square()
    if not torch.isfinite(mean).all() or not torch.isfinite(variance).all() or torch.any(variance < -1e-8):
        raise ValueError("Invalid weighted feature moments")
    std = variance.clamp_min(0).sqrt().clamp_min(1e-6)
    return mean.float(), std.float()


def fit_rows(rows: TrainingRows, *, epochs: int = EPOCHS, unit_test: bool = False):
    if (not isinstance(epochs, int) or epochs <= 0 or (epochs != EPOCHS and not unit_test)
            or rows.labels.shape != (len(rows.ab),) or not np.isin(rows.labels, (0, 1)).all()):
        raise ValueError("Invalid fixed training configuration")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    torch.manual_seed(SEED)
    generator = torch.Generator().manual_seed(SEED)
    mean, std = weighted_standardization(rows)
    ab = (torch.as_tensor(rows.ab, dtype=torch.float32) - mean) / std
    ba = (torch.as_tensor(rows.ba, dtype=torch.float32) - mean) / std
    labels = torch.as_tensor(rows.labels, dtype=torch.float32)
    weights = torch.as_tensor(rows.weights, dtype=torch.float32)
    total_weight_mass = weights.sum()
    if not torch.isfinite(ab).all() or not torch.isfinite(ba).all():
        raise ValueError("Standardization produced nonfinite features")
    model = StrokeAffinityModel()
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
    history, started = [], time.perf_counter()
    for epoch in range(epochs):
        model.train()
        permutation = torch.randperm(len(labels), generator=generator)
        weighted_loss = 0.0
        for indices in permutation.split(BATCH_SIZE):
            optimizer.zero_grad(set_to_none=True)
            logits = (model(ab[indices]) + model(ba[indices])) / 2
            if logits.shape != labels[indices].shape or not torch.isfinite(logits).all():
                raise ValueError("Invalid symmetric affinity logits")
            losses = F.binary_cross_entropy_with_logits(logits, labels[indices], reduction="none")
            # Preserve the fixed global weighted objective, not each batch's class prior.
            batch_mass = (losses * weights[indices]).sum()
            loss = batch_mass * len(labels) / (len(indices) * total_weight_mass)
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite affinity loss")
            loss.backward()
            if any(parameter.grad is not None and not torch.isfinite(parameter.grad).all() for parameter in model.parameters()):
                raise ValueError("Nonfinite affinity gradient")
            optimizer.step()
            weighted_loss += float(batch_mass.detach())
        history.append({"epoch": epoch + 1, "onlineWeightedLoss": weighted_loss / float(total_weight_mass),
                        "elapsedSeconds": time.perf_counter() - started})
        if not unit_test:
            print(json.dumps(history[-1], sort_keys=True), flush=True)
    model.eval()
    if any(not torch.isfinite(parameter).all() for parameter in model.parameters()):
        raise ValueError("Nonfinite final affinity checkpoint")
    return model, mean, std, history


def partition_metrics(count: int, groups, owners: tuple[tuple[int, ...], ...]) -> dict:
    owner_labels(count, tuple((i, j) for i in range(count) for j in range(i + 1, count)), owners)
    flat = [index for group in groups for index in group]
    valid = [index for index in flat if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < count]
    indexes = Counter(valid)
    invalid = len(flat) - len(valid)
    missing = sum(index not in indexes for index in range(count))
    duplicate = sum(max(0, value - 1) for value in indexes.values())
    group_sets, owner_sets = [set(group) for group in groups], [set(owner) for owner in owners]
    exact = (not invalid and not missing and not duplicate and all(groups)
             and {frozenset(group) for group in group_sets} == {frozenset(owner) for owner in owner_sets})
    return {"exactPartition": exact, "falseMergedGroups": sum(sum(bool(group & owner) for owner in owner_sets) > 1
                for group in group_sets), "falseSplitOwners": sum(sum(bool(owner & group) for group in group_sets) > 1
                for owner in owner_sets), "missingIndexes": missing, "duplicateIndexes": duplicate,
            "invalidIndexes": invalid, "groupCount": len(groups), "expectedOwnerCount": len(owners)}


def predict_target(model, mean: torch.Tensor, std: torch.Tensor, strokes: tuple[InkStroke, ...]):
    started = time.perf_counter()
    edges, ab, ba = all_pair_features(strokes)
    features_elapsed = time.perf_counter() - started
    inference_started = time.perf_counter()
    with torch.inference_mode():
        logits = ((model((torch.as_tensor(ab) - mean) / std)
                   + model((torch.as_tensor(ba) - mean) / std)) / 2).numpy()
    if logits.shape != (len(edges),) or not np.isfinite(logits).all():
        raise ValueError("Invalid evaluated affinity logits")
    groups = partition_from_logits(len(strokes), edges, logits)
    return groups, edges, logits, {"featureSeconds": features_elapsed,
                                  "inferenceAndPartitionSeconds": time.perf_counter() - inference_started}


def evaluate_targets(model, mean, std, targets: tuple[Target, ...], allowed_writers: tuple[str, ...],
                     *, progress: bool = False) -> dict:
    if (len(allowed_writers) != 8 or len(set(allowed_writers)) != 8 or not targets
            or any(not writer.startswith("trn_") for writer in allowed_writers)
            or any(target.role != "development" or target.writer not in allowed_writers for target in targets)):
        raise ValueError("Only original development writers may reach evaluation")
    rows, totals, per_writer, per_label = [], defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), defaultdict(Counter)
    for target_index, target in enumerate(targets):
        # Predictions are fixed before ownership truth is consulted by the scorer.
        groups, edges, logits, timings = predict_target(model, mean, std, target.strokes)
        metrics = partition_metrics(len(target.strokes), groups, target.owners)
        labels = owner_labels(len(target.strokes), edges, target.owners)
        same_owner = logits > 0
        confusion = {"edgeTruePositive": int(np.sum(same_owner & (labels == 1))),
            "edgeFalsePositive": int(np.sum(same_owner & (labels == 0))),
            "edgeTrueNegative": int(np.sum(~same_owner & (labels == 0))),
            "edgeFalseNegative": int(np.sum(~same_owner & (labels == 1))), "edgeZeroLogitTies": int(np.sum(logits == 0))}
        counts = {"targets": 1, "exactPartitions": int(metrics["exactPartition"]),
            "singletonTargets": int(len(target.strokes) == 1), "sourceStrokes": len(target.strokes),
            "sourcePoints": sum(len(stroke.points) for stroke in target.strokes),
            "zeroExtentCharacters": target.zero_extent_characters,
            "falseMergedTargets": int(metrics["falseMergedGroups"] > 0),
            "falseSplitTargets": int(metrics["falseSplitOwners"] > 0), **confusion,
            **{key: metrics[key] for key in ("falseMergedGroups", "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}}
        totals[target.arm].update(counts)
        per_writer[target.arm][target.writer].update(counts)
        if target.arm == SINGLE_ARM:
            if target.single_label is None:
                raise ValueError("Missing postprediction single-character audit label")
            per_label[target.single_label].update(counts)
        rows.append({"candidateID": target.identity, "role": target.role, "sourceIDs": target.source_ids, "writer": target.writer,
            "session": target.session, "arm": target.arm, "sourceStrokeCount": len(target.strokes),
            "expectedOwners": target.owners, "groups": groups, "exactOwnerMatch": metrics["exactPartition"],
            "metrics": metrics, "edgeConfusion": confusion, "timings": timings})
        if progress and ((target_index + 1) % 1000 == 0 or target_index + 1 == len(targets)):
            print(json.dumps({"stage": "development-partitions", "targetsCompleted": target_index + 1,
                              "targets": len(targets)}, sort_keys=True), flush=True)
    return {"targets": len(rows), "summaries": [{"arm": arm, "counts": dict(totals[arm]),
        "byWriter": {writer: dict(counts) for writer, counts in sorted(per_writer[arm].items())}}
        for arm in sorted(totals)], "singlePartitionsByLabel": {label: dict(counts) for label, counts in sorted(per_label.items())},
        "edgeDecision": "strict-positive-symmetric-logit; zero-ties-negative", "rows": rows}


def _new_output(output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new; preserve prior evidence")
    output.mkdir(parents=True, exist_ok=False)


def _write_json(path: Path, value) -> None:
    with path.open("x") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)


def _fit(source: Path, protocol: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    source_bytes, protocol_bytes, code = source.read_bytes(), protocol.read_bytes(), code_identity()
    if _digest(protocol_bytes) != code["docs/personal-learned-stroke-ownership-protocol-2026-09-30.md"]:
        raise ValueError("Supplied protocol differs from the frozen ownership protocol")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    # No development model features/targets are constructed by fit. The fixed
    # copy audit alone normalizes development source trajectories for exposure.
    samples = tuple(sample for sample in records if sample.writer in training)
    if len(samples) != 6208:
        raise ValueError("Incomplete fixed training partition")
    copy_audit = audit_trajectory_copies(samples, tuple(sample for sample in records if sample.writer in development),
                                       training, development)
    plan = training_plan(samples, training)
    targets = training_target_stream(samples, training)
    _new_output(output)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": _digest(protocol_bytes),
        "codeSHA256": code, "trainingWriters": training, "developmentWriters": development,
        "reservedWriters": reserved, "reservedWritersEvaluated": False, "developmentFeaturesConstructed": False,
        "privateInkUsed": False, "productionEligible": False, "inferenceAuthority": "research-partition-only",
        "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT, "seed": SEED, "epochs": EPOCHS, "batchSize": BATCH_SIZE,
        "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
        "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "featureStandardization": "weighted-training-AB-BA-population-std-clamp-1e-6",
        "symmetry": "mean-forward-AB-forward-BA", "selection": "final-epoch-only", "trajectoryCopyAudit": copy_audit,
        "trainingPlan": plan}
    _write_json(output / "protocol.json", metadata)
    with (output / "frozen-protocol.md").open("xb") as handle:
        handle.write(protocol_bytes)
    rows = training_rows(targets, training, progress=True)
    print(json.dumps(rows.summary, sort_keys=True), flush=True)
    model, mean, std, history = fit_rows(rows)
    checkpoint = {"state_dict": model.state_dict(), "feature_mean": mean, "feature_std": std}
    torch.save(checkpoint, output / "affinity-weights.pt")
    if (source.read_bytes() != source_bytes or protocol.read_bytes() != protocol_bytes or code_identity() != code):
        raise ValueError("Source, protocol, or code changed during fit")
    metadata.update({"sourceUnchanged": True, "weightsSHA256": _digest((output / "affinity-weights.pt").read_bytes()),
        "training": rows.summary, "trainingHistory": history,
        "normalizationDiagnostics": {"minimumStd": float(std.min()), "maximumStd": float(std.max()),
            "flooredDimensions": int((std == torch.tensor(1e-6, dtype=std.dtype)).sum())},
        "parameterCount": sum(parameter.numel() for parameter in model.parameters())})
    _write_json(output / "report.json", metadata)


def fit(source: Path, protocol: Path, output: Path) -> None:
    with preserved_inputs((source, protocol)):
        _fit(source, protocol, output)


def _evaluate(source: Path, run: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    source_bytes, code = source.read_bytes(), code_identity()
    report_bytes = (run / "report.json").read_bytes()
    report = json.loads(report_bytes)
    if (report.get("version") != VERSION or report.get("sourceSHA256") != SOURCE_SHA256
            or report.get("productionEligible") is not False or report.get("reservedWritersEvaluated") is not False
            or report.get("developmentFeaturesConstructed") is not False or report.get("privateInkUsed") is not False
            or report.get("epochs") != EPOCHS or len(report.get("trainingHistory", [])) != EPOCHS
            or report.get("featureSchema") != FEATURE_SCHEMA or report.get("featureCount") != FEATURE_COUNT
            or report.get("codeSHA256") != code or report.get("seed") != SEED or report.get("batchSize") != BATCH_SIZE
            or report.get("optimizer") != {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001}
            or report.get("featureStandardization") != "weighted-training-AB-BA-population-std-clamp-1e-6"
            or report.get("symmetry") != "mean-forward-AB-forward-BA" or report.get("selection") != "final-epoch-only"
            or report.get("protocolSHA256") != code["docs/personal-learned-stroke-ownership-protocol-2026-09-30.md"]
            or _digest((run / "frozen-protocol.md").read_bytes()) != report.get("protocolSHA256")):
        raise ValueError("Invalid or changed final research run")
    weights_bytes = (run / "affinity-weights.pt").read_bytes()
    if _digest(weights_bytes) != report.get("weightsSHA256"):
        raise ValueError("Checkpoint digest mismatch")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    if any(report[key] != list(value) for key, value in (("trainingWriters", training),
            ("developmentWriters", development), ("reservedWriters", reserved))):
        raise ValueError("Writer split changed")
    checkpoint = torch.load(run / "affinity-weights.pt", map_location="cpu", weights_only=True)
    if set(checkpoint) != {"state_dict", "feature_mean", "feature_std"}:
        raise ValueError("Wrong checkpoint fields")
    mean, std = checkpoint["feature_mean"], checkpoint["feature_std"]
    if (mean.shape != (FEATURE_COUNT,) or std.shape != mean.shape or mean.dtype != torch.float32
            or std.dtype != torch.float32 or not torch.isfinite(mean).all() or not torch.isfinite(std).all()
            or torch.any(std < 1e-6)):
        raise ValueError("Invalid frozen training statistics")
    torch.set_num_threads(4)
    torch.use_deterministic_algorithms(True)
    model = StrokeAffinityModel().eval()
    model.load_state_dict(checkpoint["state_dict"], strict=True)
    if any(not torch.isfinite(parameter).all() for parameter in model.parameters()):
        raise ValueError("Nonfinite frozen model parameters")
    samples = tuple(sample for sample in records if sample.writer in development)
    if len(samples) != 1552:
        raise ValueError("Incomplete fixed development partition")
    targets = build_targets(samples, "development", development, include_triple=True)
    _new_output(output)
    started = time.perf_counter()
    result = evaluate_targets(model, mean, std, targets, development, progress=True)
    if (source.read_bytes() != source_bytes or code_identity() != code or (run / "report.json").read_bytes() != report_bytes
            or (run / "affinity-weights.pt").read_bytes() != weights_bytes):
        raise ValueError("Source, checkpoint, or code changed during evaluation")
    result.update({"version": VERSION, "sourceSHA256": SOURCE_SHA256, "sourceUnchanged": True,
        "codeSHA256": code, "trainingReportSHA256": _digest(report_bytes), "weightsSHA256": report["weightsSHA256"],
        "protocolSHA256": report["protocolSHA256"], "developmentWriters": development,
        "trajectoryCopyAudit": report["trajectoryCopyAudit"],
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False,
        "scope": "public synthetic ownership development, not chord accuracy", "elapsedSeconds": time.perf_counter() - started})
    _write_json(output / "report.json", result)
    print(json.dumps({"targets": result["targets"], "summaries": result["summaries"],
                      "elapsedSeconds": result["elapsedSeconds"]}, sort_keys=True), flush=True)


def evaluate(source: Path, run: Path, output: Path) -> None:
    with preserved_inputs((source, run / "report.json", run / "affinity-weights.pt", run / "frozen-protocol.md")):
        _evaluate(source, run, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preflight_parser = commands.add_parser("preflight")
    preflight_parser.add_argument("--source", type=Path, required=True)
    fit_parser = commands.add_parser("fit")
    fit_parser.add_argument("--source", type=Path, required=True)
    fit_parser.add_argument("--protocol", type=Path, required=True)
    fit_parser.add_argument("--output", type=Path, required=True)
    evaluate_parser = commands.add_parser("evaluate")
    evaluate_parser.add_argument("--source", type=Path, required=True)
    evaluate_parser.add_argument("--run", type=Path, required=True)
    evaluate_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "preflight":
        records = load_official_source(args.source.resolve())
        training, development, reserved = split_writers(records)
        samples = tuple(sample for sample in records if sample.writer in training)
        print(json.dumps(training_plan(samples, training), sort_keys=True), flush=True)
    elif args.command == "fit":
        fit(args.source.resolve(), args.protocol.resolve(), args.output.resolve())
    else:
        evaluate(args.source.resolve(), args.run.resolve(), args.output.resolve())
