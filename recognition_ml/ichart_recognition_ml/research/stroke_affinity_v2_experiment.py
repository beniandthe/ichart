"""Frozen public stroke-ownership v2 experiment; separate from retained v1.

No private ink, app/profile writes, production acceptance, or sealed-writer
features. Public fitting and observed-development evaluation are separate CLIs.
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

from ..features import InkStroke
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers
from .stroke_affinity_experiment import (affine, normalize, point_bounds, owner_labels,
                                        partition_metrics, audit_trajectory_copies, validate_role)
from .stroke_affinity_v2 import StrokeAffinityModel, all_pair_features, partition_from_logits

VERSION = "public-stroke-affinity-experiment-v2"
FEATURE_SCHEMA = "stroke-affinity-pair-local-v2"
FEATURE_COUNT = 202
SEED, EPOCHS, BATCH_SIZE = 29, 30, 512
SINGLE_ARM = "single32"
CONTEXT_ARMS = tuple((dimension, gap) for dimension in (16.0, 32.0) for gap in (3.2, 8.0, 16.0))
PREFIXES = {2: "public-pair-v1:", 3: "public-triple-v1:", 4: "public-quad-v2:", 5: "public-five-stress-v2:"}
PROTOCOL_PATH = "docs/personal-learned-stroke-ownership-v2-protocol-2026-09-30.md"


@dataclass(frozen=True)
class Context:
    sources: tuple[Sample, ...]
    dimension: float
    gap: float
    arm: str


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
    cardinality: int
    single_label: str | None = None  # Postprediction audit only.


@dataclass(frozen=True)
class TrainingRows:
    ab: np.ndarray
    ba: np.ndarray
    labels: np.ndarray
    weights: np.ndarray
    cardinalities: np.ndarray
    summary: dict


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    state = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1 << 20):
            state.update(block)
    return state.hexdigest()


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    names = ("recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_experiment.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
        "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
        "recognition_ml/ichart_recognition_ml/features.py", "recognition_ml/ichart_recognition_ml/schema.py",
        "recognition_ml/tests/test_stroke_affinity_v2_experiment.py", "recognition_ml/tests/test_stroke_affinity_v2.py",
        "recognition_ml/tests/test_stroke_affinity_experiment.py", "recognition_ml/tests/test_stroke_affinity.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_baseline.py",
        "recognition_ml/tests/test_stroke_affinity_baseline.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_baseline.py",
        "recognition_ml/tests/test_stroke_affinity_v2_baseline.py",
        PROTOCOL_PATH, "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md")
    return {name: file_digest(root / name) for name in names}


@contextmanager
def preserved_inputs(paths: tuple[Path, ...]):
    originals, code = {path: file_digest(path) for path in paths}, code_identity()
    try:
        yield
    finally:
        if any(file_digest(path) != value for path, value in originals.items()) or code_identity() != code:
            raise ValueError("Source, artifacts, frozen protocol, or code changed during operation")


def write_json(path: Path, value) -> None:
    with path.open("x") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)


def new_output(path: Path) -> None:
    if path.exists():
        raise ValueError("Output must be new; preserve all v1/v2 evidence")
    path.mkdir(parents=True, exist_ok=False)


def arm_name(cardinality: int, dimension: float, gap: float) -> str:
    if cardinality == 1:
        return SINGLE_ARM
    if cardinality not in PREFIXES or (dimension, gap) not in CONTEXT_ARMS:
        raise ValueError("Undeclared public context arm")
    if cardinality == 2:
        return f"second{int(dimension)}-gap{gap:g}"
    names = {3: "triple", 4: "quad", 5: "five"}
    return names[cardinality] + "32-" + "-".join([str(int(dimension))] * (cardinality - 1)) + "-gap" + "-".join([f"{gap:g}"] * (cardinality - 1))


def cyclic_sequences(samples: tuple[Sample, ...], cardinality: int) -> tuple[tuple[Sample, ...], ...]:
    if cardinality not in PREFIXES:
        raise ValueError("Undeclared composition cardinality")
    batches = defaultdict(list)
    for sample in samples:
        batches[(sample.writer, sample.session)].append(sample)
    if any(len(batch) != 97 or len({sample.label for sample in batch}) != 97 for batch in batches.values()):
        raise ValueError("Incomplete public writer/session")
    result = []
    for key in sorted(batches):
        ordered = sorted(batches[key], key=lambda sample: (digest((PREFIXES[cardinality] + sample.identity).encode()), sample.identity))
        result.extend(tuple(ordered[(index + offset) % len(ordered)] for offset in range(cardinality))
                      for index in range(len(ordered)))
    return tuple(result)


def context_stream(samples: tuple[Sample, ...], role: str, allowed_writers: tuple[str, ...], *, include_five: bool = False):
    # Check the complete role before returning a generator or constructing geometry.
    validate_role(samples, role, allowed_writers)
    if include_five and role != "development":
        raise ValueError("Five-character stress is development-only")
    def iterator():
        for writer in sorted({sample.writer for sample in samples}):
            writer_samples = tuple(sample for sample in samples if sample.writer == writer)
            for sample in sorted(writer_samples, key=lambda item: item.identity):
                yield Context((sample,), 32, 0, SINGLE_ARM)
            for cardinality in ((2, 3, 4, 5) if include_five else (2, 3, 4)):
                for sequence in cyclic_sequences(writer_samples, cardinality):
                    for dimension, gap in CONTEXT_ARMS:
                        yield Context(sequence, dimension, gap, arm_name(cardinality, dimension, gap))
    return iterator()


def target_from_context(context: Context, role: str) -> Target:
    cardinality = len(context.sources)
    if (role not in ("training", "development") or cardinality not in (1, 2, 3, 4, 5)
            or (role == "training" and cardinality == 5)
            or any(not sample.writer.startswith("trn_") or sample.session not in (1, 2) for sample in context.sources)
            or len({(sample.writer, sample.session) for sample in context.sources}) != 1
            or context.arm != arm_name(cardinality, context.dimension, context.gap)
            or (cardinality == 1 and (context.dimension, context.gap) != (32, 0))):
        raise ValueError("Invalid declared role/context before geometry")
    result, owners, left_edge, zero_extent = [], [], 0.0, 0
    for index, sample in enumerate(context.sources):
        at32 = normalize(sample.strokes)
        dimension = 32 if index == 0 else context.dimension
        left, top, right, bottom = point_bounds(at32)
        scaled = affine(at32, dimension / 32 if max(right - left, bottom - top) > 0 else 1, 0, 0)
        left, top, right, bottom = point_bounds(scaled)
        zero_extent += int(right == left and bottom == top)
        if len(context.sources) == 1:
            translated = scaled
        else:
            translated = affine(scaled, 1, left_edge - left, 32 - bottom)
        owners.append(tuple(range(len(result), len(result) + len(translated))))
        result.extend(translated)
        left_edge += right - left + context.gap
    first = context.sources[0]
    source_ids = tuple(sample.identity for sample in context.sources)
    return Target("+".join(source_ids) + "/" + context.arm, role, first.writer, first.session, context.arm,
        source_ids, tuple(result), tuple(owners), zero_extent, len(source_ids), first.label if len(source_ids) == 1 else None)


def target_stream(samples: tuple[Sample, ...], role: str, allowed_writers: tuple[str, ...], *, include_five: bool = False):
    contexts = context_stream(samples, role, allowed_writers, include_five=include_five)
    return (target_from_context(context, role) for context in contexts)


def training_plan(samples: tuple[Sample, ...], allowed_writers: tuple[str, ...]) -> dict:
    """Exact storage/row plan using only source metadata; no derived features."""
    totals, per_arm, eligible, edges_by_cardinality = Counter(), Counter(), Counter(), Counter()
    maximum_strokes, maximum_points = 0, 0
    for context in context_stream(samples, "training", allowed_writers):
        cardinality = len(context.sources)
        strokes = sum(len(sample.strokes) for sample in context.sources)
        points = sum(len(stroke.points) for sample in context.sources for stroke in sample.strokes)
        if not 1 <= strokes <= 64 or points > 8192:
            raise ValueError("Public context exceeds the frozen source contract")
        edges = strokes * (strokes - 1) // 2
        totals["targets"] += 1; totals["edgeRows"] += edges
        totals["singletonTargetsExcludedFromLoss"] += int(edges == 0)
        per_arm[context.arm] += 1
        edges_by_cardinality[cardinality] += edges
        eligible[cardinality] += int(edges > 0)
        maximum_strokes, maximum_points = max(maximum_strokes, strokes), max(maximum_points, points)
    rows = totals["edgeRows"]
    return {"trainingSamples": len(samples), **dict(totals), "targetsByArm": dict(sorted(per_arm.items())),
        "eligibleTargetsByCardinality": {str(key): value for key, value in sorted(eligible.items())},
        "edgesByCardinality": {str(key): value for key, value in sorted(edges_by_cardinality.items())},
        "maximumSourceStrokes": maximum_strokes, "maximumSourcePoints": maximum_points,
        "rawABBAFloat32Bytes": rows * FEATURE_COUNT * 4 * 2,
        "fullStandardizedABBAFloat32BytesAvoided": rows * FEATURE_COUNT * 4 * 2,
        "epochs": EPOCHS, "batchesPerEpoch": math.ceil(rows / BATCH_SIZE),
        "fittingBatchSteps": EPOCHS * math.ceil(rows / BATCH_SIZE),
        "affinityFeaturesConstructed": False, "developmentFeaturesConstructed": False}


def _valid_training_target(target: Target, allowed_writers: tuple[str, ...]) -> bool:
    return (target.role == "training" and target.writer in allowed_writers and target.cardinality in (1, 2, 3, 4)
            and len(target.source_ids) == target.cardinality and len(target.owners) == target.cardinality)


def build_training_cache(targets: Iterable[Target], allowed_writers: tuple[str, ...], plan: dict,
                         cache: Path, *, progress: bool = False) -> TrainingRows:
    if (len(allowed_writers) != 32 or len(set(allowed_writers)) != 32
            or any(not writer.startswith("trn_") for writer in allowed_writers)
            or not targets or plan.get("edgeRows", 0) <= 0 or plan.get("targets", 0) <= 0):
        raise ValueError("Invalid training-only cache role or row plan")
    if isinstance(targets, (tuple, list)) and any(not _valid_training_target(target, allowed_writers) for target in targets):
        raise ValueError("Wrong-role/cardinality target before features")
    eligible = {int(key): int(value) for key, value in plan["eligibleTargetsByCardinality"].items()}
    if set(eligible) != {1, 2, 3, 4} or min(eligible.values()) <= 0:
        raise ValueError("All four cardinalities need eligible targets")
    new_output(cache)
    count = int(plan["edgeRows"])
    arrays = {
        "ab": np.lib.format.open_memmap(cache / "ab.npy", mode="w+", dtype=np.float32, shape=(count, FEATURE_COUNT)),
        "ba": np.lib.format.open_memmap(cache / "ba.npy", mode="w+", dtype=np.float32, shape=(count, FEATURE_COUNT)),
        "labels": np.lib.format.open_memmap(cache / "labels.npy", mode="w+", dtype=np.float32, shape=(count,)),
        "weights": np.lib.format.open_memmap(cache / "weights.npy", mode="w+", dtype=np.float64, shape=(count,)),
        "cardinalities": np.lib.format.open_memmap(cache / "cardinalities.npy", mode="w+", dtype=np.uint8, shape=(count,)),
    }
    totals, arms, seen_eligible, positive_mass, negative_mass = Counter(), Counter(), Counter(), 0.0, 0.0
    offset = 0
    for target in targets:
        if not _valid_training_target(target, allowed_writers):
            raise ValueError("Wrong-role/cardinality target reached training")
        # Ink only enters v2 features. Owner truth is supplied afterward.
        edges, ab, ba = all_pair_features(target.strokes)
        truth = owner_labels(len(target.strokes), edges, target.owners)
        size = len(edges)
        if (ab.shape != (size, FEATURE_COUNT) or ba.shape != ab.shape or ab.dtype != np.float32 or ba.dtype != np.float32
                or not np.isfinite(ab).all() or not np.isfinite(ba).all() or offset + size > count):
            raise ValueError("Invalid v2 cache feature contract")
        totals["targets"] += 1; totals["zeroExtentCharacters"] += target.zero_extent_characters
        arms[target.arm] += 1
        if not size:
            totals["singletonTargetsExcludedFromLoss"] += 1
        else:
            seen_eligible[target.cardinality] += 1
            base = 1 / (size * eligible[target.cardinality])
            selection = slice(offset, offset + size)
            arrays["ab"][selection] = ab; arrays["ba"][selection] = ba
            arrays["labels"][selection] = truth; arrays["weights"][selection] = base
            arrays["cardinalities"][selection] = target.cardinality
            positive = int(np.sum(truth == 1))
            totals["positiveEdges"] += positive; totals["negativeEdges"] += size - positive
            positive_mass += positive * base; negative_mass += (size - positive) * base
            offset += size
        if progress and (totals["targets"] % 1000 == 0 or totals["targets"] == plan["targets"]):
            print(json.dumps({"stage": "v2-training-features", "targetsCompleted": totals["targets"],
                              "targets": plan["targets"], "edgeRowsCompleted": offset}, sort_keys=True), flush=True)
    if (offset != count or totals["targets"] != plan["targets"] or dict(seen_eligible) != eligible
            or dict(sorted(arms.items())) != plan["targetsByArm"] or min(positive_mass, negative_mass) <= 0):
        raise ValueError("Training cache did not match the frozen complete plan")
    mass = positive_mass + negative_mass
    base_by_cardinality, final_by_cardinality, balanced_class = Counter(), Counter(), Counter()
    for start in range(0, count, 4096):
        selection = slice(start, start + 4096)
        labels, weights, cards = arrays["labels"][selection], arrays["weights"][selection], arrays["cardinalities"][selection]
        for cardinality in (1, 2, 3, 4):
            base_by_cardinality[cardinality] += float(weights[cards == cardinality].sum())
        weights *= np.where(labels == 1, mass / (2 * positive_mass), mass / (2 * negative_mass))
        for cardinality in (1, 2, 3, 4):
            final_by_cardinality[cardinality] += float(weights[cards == cardinality].sum())
        balanced_class["positive"] += float(weights[labels == 1].sum())
        balanced_class["negative"] += float(weights[labels == 0].sum())
    if any(abs(value - 1) > 1e-10 for value in base_by_cardinality.values()):
        raise ValueError("Cardinality base loss masses are not one")
    for array in arrays.values():
        array.flush()
    summary = {**dict(totals), "targetsByArm": dict(sorted(arms.items())), "edgeRows": count,
        "eligibleTargetsByCardinality": {str(key): value for key, value in sorted(seen_eligible.items())},
        "baseMassByCardinality": {str(key): value for key, value in sorted(base_by_cardinality.items())},
        "finalMassByCardinality": {str(key): value for key, value in sorted(final_by_cardinality.items())},
        "unbalancedPositiveMass": positive_mass, "unbalancedNegativeMass": negative_mass,
        "balancedPositiveMass": balanced_class["positive"], "balancedNegativeMass": balanced_class["negative"],
        "storage": "raw-npy-memmap; bounded-minibatch-float32-normalization; no-full-normalized-cache"}
    files = {name + ".npy": file_digest(cache / (name + ".npy")) for name in arrays}
    write_json(cache / "manifest.json", {"featureSchema": FEATURE_SCHEMA, "rows": count, "filesSHA256": files, "summary": summary})
    # Release writable mappings; return independently reopened read-only mappings.
    arrays.clear()
    loaded = {name: np.load(cache / (name + ".npy"), mmap_mode="r", allow_pickle=False)
              for name in ("ab", "ba", "labels", "weights", "cardinalities")}
    return TrainingRows(**loaded, summary=summary)


def weighted_standardization(rows: TrainingRows) -> tuple[torch.Tensor, torch.Tensor]:
    if (rows.ab.shape != rows.ba.shape or rows.ab.ndim != 2 or rows.ab.shape[1] != FEATURE_COUNT or not len(rows.ab)
            or rows.weights.shape != (len(rows.ab),) or rows.labels.shape != rows.weights.shape):
        raise ValueError("Invalid v2 training statistics dimensions")
    sums, squares = torch.zeros(FEATURE_COUNT, dtype=torch.float64), torch.zeros(FEATURE_COUNT, dtype=torch.float64)
    for start in range(0, len(rows.weights), 4096):
        weights = np.asarray(rows.weights[start:start + 4096])
        if not np.isfinite(weights).all() or np.any(weights <= 0):
            raise ValueError("Invalid training row weights")
        weight = torch.tensor(weights, dtype=torch.float64)[:, None]
        for features in (rows.ab, rows.ba):
            values = np.asarray(features[start:start + 4096])
            if not np.isfinite(values).all():
                raise ValueError("Nonfinite raw affinity feature")
            x = torch.tensor(values, dtype=torch.float64)
            sums += (x * weight).sum(0); squares += (x.square() * weight).sum(0)
    # The small scalar reduction matches the direct-array reference exactly;
    # only feature blocks are streamed, not a differently ordered denominator.
    mass = float(rows.weights.sum()) * 2
    mean = sums / mass
    variance = squares / mass - mean.square()
    if not torch.isfinite(mean).all() or not torch.isfinite(variance).all() or torch.any(variance < -1e-8):
        raise ValueError("Invalid weighted feature moments")
    return mean.float(), variance.clamp_min(0).sqrt().clamp_min(1e-6).float()


def normalized_batch(features: np.ndarray, indexes, mean: torch.Tensor, std: torch.Tensor) -> torch.Tensor:
    # Fancy indexing makes a bounded owned copy, so read-only memmaps are never
    # passed as writable tensor storage. Arithmetic matches direct float32 ops.
    values = np.asarray(features[np.asarray(indexes, dtype=np.int64)], dtype=np.float32).copy()
    output = (torch.from_numpy(values) - mean) / std
    if output.shape != (len(indexes), FEATURE_COUNT) or not torch.isfinite(output).all():
        raise ValueError("Invalid bounded normalized batch")
    return output


def fit_rows(rows: TrainingRows, *, epochs: int = EPOCHS, unit_test: bool = False):
    if not isinstance(epochs, int) or epochs <= 0 or (epochs != EPOCHS and not unit_test):
        raise ValueError("Unfrozen v2 training schedule")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True); torch.manual_seed(SEED)
    generator = torch.Generator().manual_seed(SEED)
    mean, std = weighted_standardization(rows)
    labels = torch.tensor(np.asarray(rows.labels), dtype=torch.float32)
    weights = torch.tensor(np.asarray(rows.weights), dtype=torch.float32)
    if not torch.isfinite(labels).all() or not torch.all((labels == 0) | (labels == 1)) or not torch.isfinite(weights).all() or torch.any(weights <= 0):
        raise ValueError("Invalid ownership supervision or weights")
    total_weight_mass = weights.sum()
    model = StrokeAffinityModel()
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.0001)
    history, started = [], time.perf_counter()
    for epoch in range(epochs):
        model.train(); weighted_loss = 0.0
        permutation = torch.randperm(len(labels), generator=generator)
        for indices in permutation.split(BATCH_SIZE):
            indexes = indices.numpy()
            ab = normalized_batch(rows.ab, indexes, mean, std)
            ba = normalized_batch(rows.ba, indexes, mean, std)
            optimizer.zero_grad(set_to_none=True)
            logits = (model(ab) + model(ba)) / 2
            if logits.shape != labels[indices].shape or not torch.isfinite(logits).all():
                raise ValueError("Invalid symmetric v2 logits")
            batch_mass = (F.binary_cross_entropy_with_logits(logits, labels[indices], reduction="none") * weights[indices]).sum()
            loss = batch_mass * len(labels) / (len(indices) * total_weight_mass)
            if not torch.isfinite(loss):
                raise ValueError("Nonfinite affinity loss")
            loss.backward()
            if any(parameter.grad is not None and not torch.isfinite(parameter.grad).all() for parameter in model.parameters()):
                raise ValueError("Nonfinite affinity gradient")
            optimizer.step(); weighted_loss += float(batch_mass.detach())
        history.append({"epoch": epoch + 1, "onlineWeightedLoss": weighted_loss / float(total_weight_mass),
                        "elapsedSeconds": time.perf_counter() - started})
        if not unit_test:
            print(json.dumps(history[-1], sort_keys=True), flush=True)
    model.eval()
    if any(not torch.isfinite(parameter).all() for parameter in model.parameters()):
        raise ValueError("Nonfinite final model")
    return model, mean, std, history


def predict_target(model, mean, std, strokes):
    started = time.perf_counter()
    edges, ab, ba = all_pair_features(strokes)
    features_elapsed = time.perf_counter() - started
    inference_started = time.perf_counter()
    with torch.inference_mode():
        logits = ((model((torch.as_tensor(ab) - mean) / std) + model((torch.as_tensor(ba) - mean) / std)) / 2).numpy()
    if logits.shape != (len(edges),) or not np.isfinite(logits).all():
        raise ValueError("Invalid evaluation logits")
    groups = partition_from_logits(len(strokes), edges, logits)
    return groups, edges, logits, {"featureSeconds": features_elapsed, "inferenceAndPartitionSeconds": time.perf_counter() - inference_started}


def evaluate_targets(model, mean, std, targets: Iterable[Target], allowed_writers: tuple[str, ...], *, progress: bool = False) -> dict:
    if len(allowed_writers) != 8 or len(set(allowed_writers)) != 8 or any(not writer.startswith("trn_") for writer in allowed_writers):
        raise ValueError("Invalid development writer roles")
    def valid_target(target):
        return target.role == "development" and target.writer in allowed_writers and target.cardinality in (1, 2, 3, 4, 5)
    if isinstance(targets, (tuple, list)) and any(not valid_target(target) for target in targets):
        raise ValueError("Wrong-role evaluated target before features")
    rows, totals, per_writer, per_label = [], defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), defaultdict(Counter)
    for target in targets:
        if not valid_target(target):
            raise ValueError("Wrong-role evaluated target")
        groups, edges, logits, timings = predict_target(model, mean, std, target.strokes)
        # Ownership truth and character labels are read only after prediction.
        metrics = partition_metrics(len(target.strokes), groups, target.owners)
        labels = owner_labels(len(target.strokes), edges, target.owners)
        same_owner = logits > 0
        confusion = {"edgeTruePositive": int(np.sum(same_owner & (labels == 1))), "edgeFalsePositive": int(np.sum(same_owner & (labels == 0))),
            "edgeTrueNegative": int(np.sum(~same_owner & (labels == 0))), "edgeFalseNegative": int(np.sum(~same_owner & (labels == 1))),
            "edgeZeroLogitTies": int(np.sum(logits == 0))}
        counts = {"targets": 1, "exactPartitions": int(metrics["exactPartition"]), "singletonTargets": int(len(target.strokes) == 1),
            "sourceStrokes": len(target.strokes), "sourcePoints": sum(len(stroke.points) for stroke in target.strokes),
            "zeroExtentCharacters": target.zero_extent_characters, "falseMergedTargets": int(metrics["falseMergedGroups"] > 0),
            "falseSplitTargets": int(metrics["falseSplitOwners"] > 0), **confusion,
            **{key: metrics[key] for key in ("falseMergedGroups", "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}}
        totals[target.arm].update(counts); per_writer[target.arm][target.writer].update(counts)
        if target.cardinality == 1:
            if target.single_label is None:
                raise ValueError("Missing single-character audit label")
            per_label[target.single_label].update(counts)
        rows.append({"candidateID": target.identity, "role": target.role, "sourceIDs": target.source_ids, "writer": target.writer,
            "session": target.session, "arm": target.arm, "cardinality": target.cardinality, "sourceStrokeCount": len(target.strokes),
            "expectedOwners": target.owners, "groups": groups, "exactOwnerMatch": metrics["exactPartition"],
            "metrics": metrics, "edgeConfusion": confusion, "timings": timings})
        if progress and len(rows) % 1000 == 0:
            print(json.dumps({"stage": "v2-development-partitions", "targetsCompleted": len(rows)}, sort_keys=True), flush=True)
    if not rows:
        raise ValueError("Empty evaluation cohort")
    return {"targets": len(rows), "summaries": [{"arm": arm, "counts": dict(totals[arm]),
        "byWriter": {writer: dict(counts) for writer, counts in sorted(per_writer[arm].items())}} for arm in sorted(totals)],
        "singlePartitionsByLabel": {label: dict(counts) for label, counts in sorted(per_label.items())},
        "edgeDecision": "strict-positive-symmetric-logit;zero-ties-negative", "rows": rows}


def _fit(source: Path, protocol: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    code, protocol_bytes = code_identity(), protocol.read_bytes()
    if digest(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Supplied protocol differs from canonical v2 protocol")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    samples = tuple(sample for sample in records if sample.writer in training)
    if len(samples) != 6208:
        raise ValueError("Incomplete fixed training role")
    plan = training_plan(samples, training)
    if plan["targets"] != 117952:
        raise ValueError("Frozen training target count changed")
    # The only development geometry used here is the predeclared copy audit,
    # not development model features or target compositions.
    copies = audit_trajectory_copies(samples, tuple(sample for sample in records if sample.writer in development), training, development)
    new_output(output)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": digest(protocol_bytes), "codeSHA256": code,
        "trainingWriters": training, "developmentWriters": development, "reservedWriters": reserved,
        "reservedWritersEvaluated": False, "developmentFeaturesConstructed": False, "privateInkUsed": False, "productionEligible": False,
        "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT, "seed": SEED, "epochs": EPOCHS, "batchSize": BATCH_SIZE,
        "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
        "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "featureStandardization": "final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6",
        "symmetry": "mean-forward-AB-forward-BA", "selection": "final-epoch-only", "trainingPlan": plan,
        "inferenceAuthority": "research-partition-only", "trajectoryCopyAudit": copies}
    write_json(output / "protocol.json", metadata)
    with (output / "frozen-protocol.md").open("xb") as handle:
        handle.write(protocol_bytes)
    rows = build_training_cache(target_stream(samples, "training", training), training, plan, output / "cache", progress=True)
    print(json.dumps({"stage": "v2-training-cache-complete", **rows.summary}, sort_keys=True), flush=True)
    cache_paths = tuple((output / "cache").glob("*.npy")) + (output / "cache/manifest.json",)
    with preserved_inputs(cache_paths):
        model, mean, std, history = fit_rows(rows)
    torch.save({"state_dict": model.state_dict(), "feature_mean": mean, "feature_std": std}, output / "affinity-weights.pt")
    metadata.update({"sourceUnchanged": True, "weightsSHA256": file_digest(output / "affinity-weights.pt"), "training": rows.summary,
        "trainingHistory": history, "cacheManifestSHA256": file_digest(output / "cache/manifest.json"),
        "normalizationDiagnostics": {"minimumStd": float(std.min()), "maximumStd": float(std.max()),
            "flooredDimensions": int((std == torch.tensor(1e-6, dtype=std.dtype)).sum())},
        "parameterCount": sum(parameter.numel() for parameter in model.parameters())})
    write_json(output / "report.json", metadata)


def fit(source: Path, protocol: Path, output: Path) -> None:
    with preserved_inputs((source, protocol)):
        _fit(source, protocol, output)


def _evaluate(source: Path, run: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    report_bytes, code = (run / "report.json").read_bytes(), code_identity()
    report = json.loads(report_bytes)
    if (report.get("version") != VERSION or report.get("sourceSHA256") != SOURCE_SHA256 or report.get("codeSHA256") != code
            or report.get("featureSchema") != FEATURE_SCHEMA or report.get("featureCount") != FEATURE_COUNT
            or report.get("protocolSHA256") != code[PROTOCOL_PATH] or digest((run / "frozen-protocol.md").read_bytes()) != report.get("protocolSHA256")
            or report.get("productionEligible") is not False or report.get("privateInkUsed") is not False
            or report.get("reservedWritersEvaluated") is not False or report.get("developmentFeaturesConstructed") is not False
            or report.get("seed") != SEED or report.get("epochs") != EPOCHS or report.get("batchSize") != BATCH_SIZE
            or len(report.get("trainingHistory", [])) != EPOCHS or report.get("selection") != "final-epoch-only"
            or report.get("optimizer") != {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001}
            or report.get("featureStandardization") != "final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6"
            or report.get("symmetry") != "mean-forward-AB-forward-BA"):
        raise ValueError("Unbound or changed frozen v2 artifact")
    if file_digest(run / "affinity-weights.pt") != report.get("weightsSHA256") or file_digest(run / "cache/manifest.json") != report.get("cacheManifestSHA256"):
        raise ValueError("Frozen artifact digest mismatch")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    if any(report.get(key) != list(value) for key, value in (("trainingWriters", training), ("developmentWriters", development), ("reservedWriters", reserved))):
        raise ValueError("Frozen writer roles changed")
    checkpoint = torch.load(run / "affinity-weights.pt", map_location="cpu", weights_only=True)
    if set(checkpoint) != {"state_dict", "feature_mean", "feature_std"}:
        raise ValueError("Wrong checkpoint fields")
    mean, std = checkpoint["feature_mean"], checkpoint["feature_std"]
    if (mean.shape != (FEATURE_COUNT,) or std.shape != mean.shape or mean.dtype != torch.float32 or std.dtype != torch.float32
            or not torch.isfinite(mean).all() or not torch.isfinite(std).all() or torch.any(std < 1e-6)):
        raise ValueError("Invalid frozen normalization")
    torch.set_num_threads(4); torch.use_deterministic_algorithms(True)
    model = StrokeAffinityModel().eval(); model.load_state_dict(checkpoint["state_dict"], strict=True)
    if any(not torch.isfinite(parameter).all() for parameter in model.parameters()):
        raise ValueError("Nonfinite frozen parameters")
    samples = tuple(sample for sample in records if sample.writer in development)
    if len(samples) != 1552:
        raise ValueError("Incomplete observed development role")
    new_output(output)
    started = time.perf_counter()
    result = evaluate_targets(model, mean, std, target_stream(samples, "development", development, include_five=True), development, progress=True)
    if result["targets"] != 38800 or len(result["summaries"]) != 25 or any(summary["counts"]["targets"] != 1552 for summary in result["summaries"]):
        raise ValueError("Evaluation does not cover all frozen contexts")
    result.update({"version": VERSION, "sourceSHA256": SOURCE_SHA256, "sourceUnchanged": True, "codeSHA256": code,
        "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT, "protocolSHA256": report["protocolSHA256"],
        "trainingReportSHA256": digest(report_bytes), "weightsSHA256": report["weightsSHA256"], "developmentWriters": development,
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False, "trajectoryCopyAudit": report["trajectoryCopyAudit"],
        "scope": "observed-public-synthetic-ownership-development-not-chord-accuracy", "elapsedSeconds": time.perf_counter() - started})
    write_json(output / "report.json", result)
    print(json.dumps({"targets": result["targets"], "summaries": result["summaries"], "elapsedSeconds": result["elapsedSeconds"]}, sort_keys=True), flush=True)


def evaluate(source: Path, run: Path, output: Path) -> None:
    with preserved_inputs((source, run / "report.json", run / "affinity-weights.pt", run / "frozen-protocol.md", run / "cache/manifest.json")):
        _evaluate(source, run, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("preflight", "fit", "evaluate"):
        command_parser = commands.add_parser(command)
        command_parser.add_argument("--source", type=Path, required=True)
        if command != "preflight":
            command_parser.add_argument("--output", type=Path, required=True)
        if command == "fit":
            command_parser.add_argument("--protocol", type=Path, required=True)
        elif command == "evaluate":
            command_parser.add_argument("--run", type=Path, required=True)
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
