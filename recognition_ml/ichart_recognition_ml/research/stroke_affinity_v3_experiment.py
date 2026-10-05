"""Frozen v3 whole-context feature ablation of the retained v2 experiment.

Only features change: unchanged v1 ink-only features, exact unchanged v2
targets/weights/math, genuine v3 provenance and fresh artifacts. Research only.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from contextlib import contextmanager
import json
from pathlib import Path
import platform
import time
from typing import Iterable

import numpy as np
import torch

from . import stroke_affinity_experiment as v1
from . import stroke_affinity_v2_experiment as v2
from .stroke_affinity import FEATURE_COUNT, FEATURE_SCHEMA, StrokeAffinityModel, all_pair_features
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "public-stroke-affinity-experiment-v3"
PROTOCOL_PATH = "docs/personal-learned-stroke-ownership-v3-protocol-2026-09-30.md"
SEED, EPOCHS, BATCH_SIZE = v2.SEED, v2.EPOCHS, v2.BATCH_SIZE
Context, Target, TrainingRows = v2.Context, v2.Target, v2.TrainingRows
arm_name, cyclic_sequences = v2.arm_name, v2.cyclic_sequences
context_stream, target_from_context, target_stream = v2.context_stream, v2.target_from_context, v2.target_stream
training_plan = v2.training_plan
# These helpers contain no feature construction and are intentionally unchanged.
weighted_standardization, normalized_batch, fit_rows = v2.weighted_standardization, v2.normalized_batch, v2.fit_rows
digest, file_digest, write_json = v2.digest, v2.file_digest, v2.write_json
owner_labels, partition_metrics, predict_target = v1.owner_labels, v1.partition_metrics, v1.predict_target


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    # Bind the complete reused v2/v1 implementation and the genuine v3 layer.
    identity = v2.code_identity()
    names = (PROTOCOL_PATH,
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_experiment.py",
        "recognition_ml/tests/test_stroke_affinity_v3_experiment.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_baseline.py",
        "recognition_ml/tests/test_stroke_affinity_v3_baseline.py")
    identity.update({name: file_digest(root / name) for name in names})
    return identity


@contextmanager
def preserved_inputs(paths: tuple[Path, ...]):
    originals, code = {path: file_digest(path) for path in paths}, code_identity()
    try:
        yield
    finally:
        if any(file_digest(path) != value for path, value in originals.items()) or code_identity() != code:
            raise ValueError("Source, artifacts, frozen protocol, or code changed during v3 operation")


def new_output(path: Path) -> None:
    if path.exists():
        raise ValueError("Output must be new; preserve all v1/v2/v3 evidence")
    path.mkdir(parents=True, exist_ok=False)


def build_training_cache(targets: Iterable[Target], allowed_writers: tuple[str, ...], plan: dict,
                         cache: Path, *, progress: bool = False) -> TrainingRows:
    """Same v2 rows/weights/storage; each raw feature row genuinely uses v1."""
    if (len(allowed_writers) != 32 or len(set(allowed_writers)) != 32
            or any(not writer.startswith("trn_") for writer in allowed_writers)
            or not targets or plan.get("edgeRows", 0) <= 0 or plan.get("targets", 0) <= 0):
        raise ValueError("Invalid training-only cache role or row plan")
    if isinstance(targets, (tuple, list)) and any(not v2._valid_training_target(target, allowed_writers) for target in targets):
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
        if not v2._valid_training_target(target, allowed_writers):
            raise ValueError("Wrong-role/cardinality target reached training")
        # No metadata or owner labels reach this unchanged v1 feature function.
        edges, ab, ba = all_pair_features(target.strokes)
        truth = owner_labels(len(target.strokes), edges, target.owners)
        size = len(edges)
        if (ab.shape != (size, FEATURE_COUNT) or ba.shape != ab.shape or ab.dtype != np.float32 or ba.dtype != np.float32
                or not np.isfinite(ab).all() or not np.isfinite(ba).all() or offset + size > count):
            raise ValueError("Invalid v3 whole-context cache feature contract")
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
            print(json.dumps({"stage": "v3-training-features", "targetsCompleted": totals["targets"],
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
    write_json(cache / "manifest.json", {"version": VERSION, "featureSchema": FEATURE_SCHEMA,
        "rows": count, "filesSHA256": files, "summary": summary})
    arrays.clear()
    loaded = {name: np.load(cache / (name + ".npy"), mmap_mode="r", allow_pickle=False)
              for name in ("ab", "ba", "labels", "weights", "cardinalities")}
    return TrainingRows(**loaded, summary=summary)


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
        # Scoring and cardinality audit occur after ink-only predictions.
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
            print(json.dumps({"stage": "v3-development-partitions", "targetsCompleted": len(rows)}, sort_keys=True), flush=True)
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
        raise ValueError("Supplied protocol differs from canonical v3 protocol")
    records = load_official_source(source)
    training, development, reserved = split_writers(records)
    samples = tuple(sample for sample in records if sample.writer in training)
    if len(samples) != 6208:
        raise ValueError("Incomplete fixed training role")
    plan = training_plan(samples, training)
    if (plan["targets"] != 117952 or plan["edgeRows"] != 1207443
            or plan["singletonTargetsExcludedFromLoss"] != 3161):
        raise ValueError("Frozen v3 training plan changed")
    copies = v1.audit_trajectory_copies(samples, tuple(sample for sample in records if sample.writer in development), training, development)
    new_output(output)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": digest(protocol_bytes), "codeSHA256": code,
        "trainingWriters": training, "developmentWriters": development, "reservedWriters": reserved,
        "reservedWritersEvaluated": False, "developmentFeaturesConstructed": False, "privateInkUsed": False, "productionEligible": False,
        "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT, "seed": SEED, "epochs": EPOCHS, "batchSize": BATCH_SIZE,
        "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
        "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "featureStandardization": "final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6",
        "symmetry": "mean-forward-AB-forward-BA", "selection": "final-epoch-only", "trainingPlan": plan,
        "inferenceAuthority": "research-partition-only", "trajectoryCopyAudit": copies,
        "controlledChange": "v1-whole-context-features-with-unchanged-v2-targets-weights-fit-decoder"}
    write_json(output / "protocol.json", metadata)
    with (output / "frozen-protocol.md").open("xb") as handle:
        handle.write(protocol_bytes)
    rows = build_training_cache(target_stream(samples, "training", training), training, plan, output / "cache", progress=True)
    print(json.dumps({"stage": "v3-training-cache-complete", **rows.summary}, sort_keys=True), flush=True)
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
            or report.get("sourceUnchanged") is not True or report.get("parameterCount") != 15105
            or report.get("seed") != SEED or report.get("epochs") != EPOCHS or report.get("batchSize") != BATCH_SIZE
            or len(report.get("trainingHistory", [])) != EPOCHS or report.get("selection") != "final-epoch-only"
            or report.get("optimizer") != {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001}
            or report.get("featureStandardization") != "final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6"
            or report.get("symmetry") != "mean-forward-AB-forward-BA"
            or report.get("controlledChange") != "v1-whole-context-features-with-unchanged-v2-targets-weights-fit-decoder"):
        raise ValueError("Unbound or changed frozen v3 artifact")
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
        "controlledChange": report["controlledChange"], "scope": "observed-public-synthetic-ownership-development-not-chord-accuracy",
        "elapsedSeconds": time.perf_counter() - started})
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
        with preserved_inputs((args.source.resolve(),)):
            records = load_official_source(args.source.resolve())
            training, development, reserved = split_writers(records)
            samples = tuple(sample for sample in records if sample.writer in training)
            print(json.dumps(training_plan(samples, training), sort_keys=True), flush=True)
    elif args.command == "fit":
        fit(args.source.resolve(), args.protocol.resolve(), args.output.resolve())
    else:
        evaluate(args.source.resolve(), args.run.resolve(), args.output.resolve())
