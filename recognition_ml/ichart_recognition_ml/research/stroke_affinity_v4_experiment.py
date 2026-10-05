"""Frozen equal-target-weight ablation; immutable v3 features, fresh v4 model.

No feature generation during fitting, no prior checkpoint initialization, no
private ink or reserved-writer transformations. Fit and evaluation are separate.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
from dataclasses import dataclass
from itertools import combinations
import json
from pathlib import Path
import platform
import time

import numpy as np
import torch

from . import stroke_affinity_v3_experiment as v3
from . import stroke_affinity_v2_experiment as v2
from .stroke_affinity import FEATURE_COUNT, FEATURE_SCHEMA, StrokeAffinityModel
from .uji_personal import SOURCE_SHA256, load_official_source, split_writers

VERSION = "public-stroke-affinity-experiment-v4"
PROTOCOL_PATH = "docs/personal-learned-stroke-ownership-v4-protocol-2026-09-30.md"
STANDARDIZATION = "final-balanced-equal-target-weighted-AB-BA-std-floor-1e-6"
CONTROLLED_CHANGE = "v1-equal-target-base-with-unchanged-v3-targets-features-fit-decoder"
SEED, EPOCHS, BATCH_SIZE = v3.SEED, v3.EPOCHS, v3.BATCH_SIZE
Target, TrainingRows = v3.Target, v3.TrainingRows
target_stream, training_plan = v3.target_stream, v3.training_plan
weighted_standardization, normalized_batch, fit_rows = v3.weighted_standardization, v3.normalized_batch, v3.fit_rows
evaluate_targets = v3.evaluate_targets
digest, file_digest, write_json = v3.digest, v3.file_digest, v3.write_json
ARRAY_NAMES = ("ab", "ba", "labels", "weights", "cardinalities")


@dataclass(frozen=True)
class V3Cache:
    ab: np.ndarray
    ba: np.ndarray
    labels: np.ndarray
    cardinalities: np.ndarray
    manifest: dict
    report: dict
    references: dict


def code_identity() -> dict[str, str]:
    root = Path(__file__).resolve().parents[3]
    identity = v3.code_identity()
    names = (PROTOCOL_PATH,
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_experiment.py",
        "recognition_ml/tests/test_stroke_affinity_v4_experiment.py",
        "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_baseline.py",
        "recognition_ml/tests/test_stroke_affinity_v4_baseline.py")
    identity.update({name: file_digest(root / name) for name in names})
    return identity


def v3_reference_paths(run: Path) -> tuple[Path, ...]:
    return tuple(run / "cache" / (name + ".npy") for name in ARRAY_NAMES) + tuple(run / name for name in
        ("report.json", "protocol.json", "frozen-protocol.md", "affinity-weights.pt", "cache/manifest.json"))


@contextmanager
def preserved_inputs(paths: tuple[Path, ...]):
    originals, code = {path: file_digest(path) for path in paths}, code_identity()
    try:
        yield
    finally:
        if any(file_digest(path) != value for path, value in originals.items()) or code_identity() != code:
            raise ValueError("Source, referenced caches, artifacts, protocol, or code changed during v4 operation")


def new_output(path: Path) -> None:
    if path.exists():
        raise ValueError("Output must be new; preserve every prior experiment")
    path.mkdir(parents=True, exist_ok=False)


def _metadata_guard(report: dict, *, version: str, code: dict, protocol_path: str,
                    standardization: str, controlled_change: str) -> None:
    expected = {"version": version, "sourceSHA256": SOURCE_SHA256, "sourceUnchanged": True,
        "codeSHA256": code, "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT,
        "protocolSHA256": code[protocol_path], "seed": SEED, "epochs": EPOCHS, "batchSize": BATCH_SIZE,
        "parameterCount": 15105, "selection": "final-epoch-only", "productionEligible": False,
        "privateInkUsed": False, "reservedWritersEvaluated": False, "developmentFeaturesConstructed": False,
        "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
        "featureStandardization": standardization, "symmetry": "mean-forward-AB-forward-BA",
        "controlledChange": controlled_change}
    if any(report.get(key) != value for key, value in expected.items()):
        raise ValueError("Unbound or changed frozen artifact metadata")
    if (any(report.get(key) is not value for key, value in expected.items() if isinstance(value, bool))
            or len(report.get("trainingHistory", [])) != EPOCHS
            or [row.get("epoch") for row in report["trainingHistory"]] != list(range(1, EPOCHS + 1))):
        raise ValueError("Wrong role flags or final-epoch schedule")


def verify_v3_cache(source: Path, run: Path, roles, plan: dict, *, open_arrays: bool = True):
    """All source/provenance/array digests checked before any mapped row access."""
    training, development, reserved = roles
    if (len(training) != 32 or len(development) != 8 or len(reserved) != 20
            or len(set(training + development + reserved)) != 60
            or any(not writer.startswith("trn_") for writer in training + development)
            or any(not writer.startswith("tst_") for writer in reserved)):
        raise ValueError("Wrong complete 32/8/20 writer roles before cache access")
    report_bytes = (run / "report.json").read_bytes()
    report, code = json.loads(report_bytes), v3.code_identity()
    _metadata_guard(report, version=v3.VERSION, code=code, protocol_path=v3.PROTOCOL_PATH,
        standardization="final-balanced-cardinality-target-weighted-AB-BA-std-floor-1e-6",
        controlled_change="v1-whole-context-features-with-unchanged-v2-targets-weights-fit-decoder")
    if (file_digest(source) != SOURCE_SHA256 or digest((run / "frozen-protocol.md").read_bytes()) != code[v3.PROTOCOL_PATH]
            or report.get("trainingPlan") != plan
            or any(report.get(key) != list(value) for key, value in (("trainingWriters", training),
                ("developmentWriters", development), ("reservedWriters", reserved)))):
        raise ValueError("Wrong v3 source, frozen protocol, training plan, or writer roles")
    initial = json.loads((run / "protocol.json").read_bytes())
    if any(report.get(key) != value for key, value in initial.items()):
        raise ValueError("V3 initial and final fit metadata disagree")
    if (file_digest(run / "affinity-weights.pt") != report.get("weightsSHA256")
            or file_digest(run / "cache/manifest.json") != report.get("cacheManifestSHA256")):
        raise ValueError("Wrong v3 checkpoint/cache manifest digest")
    manifest = json.loads((run / "cache/manifest.json").read_bytes())
    count = plan["edgeRows"]
    if (manifest.get("version") != v3.VERSION or manifest.get("featureSchema") != FEATURE_SCHEMA
            or manifest.get("rows") != count or manifest.get("summary") != report.get("training")
            or set(manifest.get("filesSHA256", {})) != {name + ".npy" for name in ARRAY_NAMES}):
        raise ValueError("Wrong genuine v3 cache contract")
    # Complete this loop before np.load: even an unrelated old weights file must
    # remain bound and unchanged, though it is never used in the v4 objective.
    for name in ARRAY_NAMES:
        if file_digest(run / "cache" / (name + ".npy")) != manifest["filesSHA256"][name + ".npy"]:
            raise ValueError("Wrong immutable v3 array content digest")
    contracts = {name: {"path": str((run / "cache" / (name + ".npy")).resolve()),
        "sha256": manifest["filesSHA256"][name + ".npy"],
        "dtype": "float32" if name in ("ab", "ba", "labels") else "float64" if name == "weights" else "uint8",
        "shape": [count, FEATURE_COUNT] if name in ("ab", "ba") else [count],
        "sourceVersion": v3.VERSION, "readOnly": True} for name in ARRAY_NAMES}
    references = {"v3Run": str(run.resolve()), "v3ReportSHA256": digest(report_bytes),
        "v3CheckpointSHA256": report["weightsSHA256"], "v3CacheManifestSHA256": report["cacheManifestSHA256"],
        "referencedArrays": contracts, "featureArraysRegenerated": False,
        "priorModelInitialized": False, "role": "training-only"}
    if not open_arrays:
        return references
    arrays = {}
    for name in ARRAY_NAMES:
        values = np.load(run / "cache" / (name + ".npy"), mmap_mode="r", allow_pickle=False)
        contract = contracts[name]
        if (list(values.shape) != contract["shape"] or str(values.dtype) != contract["dtype"]
                or values.flags.writeable or not isinstance(values, np.memmap)):
            raise ValueError("Invalid immutable v3 mapping dtype/shape/read-only contract")
        if name != "weights":
            arrays[name] = values
    return V3Cache(**arrays, manifest=manifest, report=report, references=references)


def reweight_training_cache(targets, allowed_writers, plan: dict, reference: V3Cache, cache: Path,
                            *, progress: bool = False) -> TrainingRows:
    if (len(allowed_writers) != 32 or len(set(allowed_writers)) != 32
            or any(not writer.startswith("trn_") for writer in allowed_writers) or not targets
            or plan.get("edgeRows", 0) <= 0 or plan.get("targets", 0) <= 0):
        raise ValueError("Invalid training-only reweight role/plan")
    if isinstance(targets, (tuple, list)) and any(not v2._valid_training_target(target, allowed_writers) for target in targets):
        raise ValueError("Wrong-role/cardinality before referenced row access")
    count = plan["edgeRows"]
    if (reference.ab.shape != (count, FEATURE_COUNT) or reference.ba.shape != reference.ab.shape
            or reference.labels.shape != (count,) or reference.cardinalities.shape != (count,)
            or any(array.flags.writeable for array in (reference.ab, reference.ba, reference.labels, reference.cardinalities))):
        raise ValueError("Wrong immutable reference row contract")
    new_output(cache)
    weights = np.lib.format.open_memmap(cache / "weights.npy", mode="w+", dtype=np.float64, shape=(count,))
    totals, arms, eligible = Counter(), Counter(), Counter()
    positive_mass, negative_mass, offset = 0.0, 0.0, 0
    for target in targets:
        if not v2._valid_training_target(target, allowed_writers):
            raise ValueError("Wrong-role/cardinality during training-only replay")
        edges = tuple(combinations(range(len(target.strokes)), 2))
        size = len(edges)
        if offset + size > count:
            raise ValueError("Replay exceeds referenced edge boundary")
        # Exact immutable row alignment is checked before assigning any weight.
        truth = v3.owner_labels(len(target.strokes), edges, target.owners)
        selection = slice(offset, offset + size)
        if (not np.array_equal(reference.labels[selection], truth)
                or not np.all(reference.cardinalities[selection] == target.cardinality)):
            raise ValueError("Replay owner labels/cardinality do not match immutable rows")
        totals["targets"] += 1; totals["zeroExtentCharacters"] += target.zero_extent_characters
        arms[target.arm] += 1
        if not size:
            totals["singletonTargetsExcludedFromLoss"] += 1
        else:
            eligible[target.cardinality] += 1
            base = 1 / size
            weights[selection] = base
            positive = int(np.sum(truth == 1))
            totals["positiveEdges"] += positive; totals["negativeEdges"] += size - positive
            positive_mass += positive * base; negative_mass += (size - positive) * base
            offset += size
        if progress and (totals["targets"] % 1000 == 0 or totals["targets"] == plan["targets"]):
            print(json.dumps({"stage": "v4-training-row-replay", "targetsCompleted": totals["targets"],
                "targets": plan["targets"], "edgeRowsValidated": offset}, sort_keys=True), flush=True)
    if (offset != count or totals["targets"] != plan["targets"] or dict(sorted(arms.items())) != plan["targetsByArm"]
            or {str(key): value for key, value in sorted(eligible.items())} != plan["eligibleTargetsByCardinality"]
            or min(positive_mass, negative_mass) <= 0):
        raise ValueError("Replay does not cover the complete frozen training stream")
    # Preserve v3's targetwise scalar reduction order. Only the base rule, not
    # v1's different vector reduction implementation, is restored by this ablation.
    mass = positive_mass + negative_mass
    factors = {"positive": mass / (2 * positive_mass), "negative": mass / (2 * negative_mass)}
    base_by_cardinality, final_by_cardinality, balanced_class = Counter(), Counter(), Counter()
    for start in range(0, count, 4096):
        selection = slice(start, start + 4096)
        labels, cards, values = reference.labels[selection], reference.cardinalities[selection], weights[selection]
        for cardinality in (1, 2, 3, 4):
            base_by_cardinality[cardinality] += float(values[cards == cardinality].sum())
        values *= np.where(labels == 1, factors["positive"], factors["negative"])
        for cardinality in (1, 2, 3, 4):
            final_by_cardinality[cardinality] += float(values[cards == cardinality].sum())
        balanced_class["positive"] += float(values[labels == 1].sum())
        balanced_class["negative"] += float(values[labels == 0].sum())
    if any(abs(base_by_cardinality[key] - value) > 1e-7 for key, value in eligible.items()):
        raise ValueError("Each eligible target did not retain base mass one")
    weights.flush(); del weights
    weights = np.load(cache / "weights.npy", mmap_mode="r", allow_pickle=False)
    final_mass = float(weights.sum())
    summary = {**dict(totals), "targetsByArm": dict(sorted(arms.items())), "edgeRows": count,
        "eligibleTargetsByCardinality": {str(key): value for key, value in sorted(eligible.items())},
        "baseMassByCardinality": {str(key): value for key, value in sorted(base_by_cardinality.items())},
        "finalMassByCardinality": {str(key): value for key, value in sorted(final_by_cardinality.items())},
        "finalShareByCardinality": {str(key): value / final_mass for key, value in sorted(final_by_cardinality.items())},
        "unbalancedPositiveMass": positive_mass, "unbalancedNegativeMass": negative_mass,
        "globalClassMultipliers": factors, "balancedPositiveMass": balanced_class["positive"],
        "balancedNegativeMass": balanced_class["negative"], "baseRule": "one-over-edge-count;eligible-target-base-mass-one",
        "storage": "immutable-v3-feature-references;new-float64-weights;bounded-normalization"}
    write_json(cache / "manifest.json", {"version": VERSION, "featureSchema": FEATURE_SCHEMA, "rows": count,
        "reuse": reference.references, "newArrays": {"weights.npy": {"sha256": file_digest(cache / "weights.npy"),
            "dtype": "float64", "shape": [count]}}, "summary": summary})
    return TrainingRows(reference.ab, reference.ba, reference.labels, weights, reference.cardinalities, summary)


def _fit(source: Path, protocol: Path, v3_run: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    code, protocol_bytes = code_identity(), protocol.read_bytes()
    if digest(protocol_bytes) != code[PROTOCOL_PATH]:
        raise ValueError("Supplied protocol differs from canonical v4 protocol")
    records = load_official_source(source)
    roles = training, development, reserved = split_writers(records)
    samples = tuple(sample for sample in records if sample.writer in training)
    plan = training_plan(samples, training)
    if (len(samples) != 6208 or plan["targets"] != 117952 or plan["edgeRows"] != 1207443
            or plan["singletonTargetsExcludedFromLoss"] != 3161
            or plan["eligibleTargetsByCardinality"] != {"1": 3047, "2": 37248, "3": 37248, "4": 37248}):
        raise ValueError("Metadata-only preflight does not match frozen v4 training")
    reference = verify_v3_cache(source, v3_run, roles, plan)
    new_output(output)
    metadata = {"version": VERSION, "sourceSHA256": SOURCE_SHA256, "protocolSHA256": digest(protocol_bytes), "codeSHA256": code,
        "trainingWriters": training, "developmentWriters": development, "reservedWriters": reserved,
        "reservedWritersEvaluated": False, "developmentFeaturesConstructed": False, "privateInkUsed": False, "productionEligible": False,
        "featureSchema": FEATURE_SCHEMA, "featureCount": FEATURE_COUNT, "seed": SEED, "epochs": EPOCHS, "batchSize": BATCH_SIZE,
        "optimizer": {"name": "AdamW", "learningRate": 0.001, "weightDecay": 0.0001},
        "torch": torch.__version__, "numpy": np.__version__, "python": platform.python_version(),
        "featureStandardization": STANDARDIZATION, "symmetry": "mean-forward-AB-forward-BA", "selection": "final-epoch-only",
        "trainingPlan": plan, "inferenceAuthority": "research-partition-only", "trajectoryCopyAudit": reference.report["trajectoryCopyAudit"],
        "controlledChange": CONTROLLED_CHANGE, "cacheReuse": reference.references}
    write_json(output / "protocol.json", metadata)
    with (output / "frozen-protocol.md").open("xb") as handle:
        handle.write(protocol_bytes)
    rows = reweight_training_cache(target_stream(samples, "training", training), training, plan, reference, output / "cache", progress=True)
    with preserved_inputs((output / "cache/weights.npy", output / "cache/manifest.json")):
        # Unchanged helper always creates a freshly seeded model; no v3 state is loaded.
        model, mean, std, history = fit_rows(rows)
    torch.save({"state_dict": model.state_dict(), "feature_mean": mean, "feature_std": std}, output / "affinity-weights.pt")
    metadata.update({"sourceUnchanged": True, "weightsSHA256": file_digest(output / "affinity-weights.pt"), "training": rows.summary,
        "trainingHistory": history, "cacheManifestSHA256": file_digest(output / "cache/manifest.json"),
        "normalizationDiagnostics": {"minimumStd": float(std.min()), "maximumStd": float(std.max()),
            "flooredDimensions": int((std == torch.tensor(1e-6, dtype=std.dtype)).sum())},
        "parameterCount": sum(parameter.numel() for parameter in model.parameters())})
    write_json(output / "report.json", metadata)


def fit(source: Path, protocol: Path, v3_run: Path, output: Path) -> None:
    with preserved_inputs((source, protocol) + v3_reference_paths(v3_run)):
        _fit(source, protocol, v3_run, output)


def _evaluate(source: Path, run: Path, output: Path) -> None:
    if output.exists():
        raise ValueError("Output must be new")
    report_bytes, code = (run / "report.json").read_bytes(), code_identity()
    report = json.loads(report_bytes)
    _metadata_guard(report, version=VERSION, code=code, protocol_path=PROTOCOL_PATH,
        standardization=STANDARDIZATION, controlled_change=CONTROLLED_CHANGE)
    if (digest((run / "frozen-protocol.md").read_bytes()) != code[PROTOCOL_PATH]
            or file_digest(run / "affinity-weights.pt") != report.get("weightsSHA256")
            or file_digest(run / "cache/manifest.json") != report.get("cacheManifestSHA256")):
        raise ValueError("Wrong frozen v4 artifact digest")
    records = load_official_source(source)
    roles = training, development, reserved = split_writers(records)
    if any(report.get(key) != list(value) for key, value in (("trainingWriters", training),
            ("developmentWriters", development), ("reservedWriters", reserved))):
        raise ValueError("Frozen writer roles changed")
    training_samples = tuple(sample for sample in records if sample.writer in training)
    plan = training_plan(training_samples, training)
    references = verify_v3_cache(source, Path(report["cacheReuse"]["v3Run"]), roles, plan, open_arrays=False)
    manifest = json.loads((run / "cache/manifest.json").read_bytes())
    if (report.get("trainingPlan") != plan or report["cacheReuse"] != references or manifest.get("reuse") != references
            or manifest.get("version") != VERSION or manifest.get("featureSchema") != FEATURE_SCHEMA
            or manifest.get("rows") != plan["edgeRows"] or manifest.get("summary") != report.get("training")
            or manifest.get("newArrays") != {"weights.npy": {"sha256": file_digest(run / "cache/weights.npy"),
                "dtype": "float64", "shape": [plan["edgeRows"]]}}):
        raise ValueError("Wrong v4 weights or immutable cache references")
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
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False,
        "trajectoryCopyAudit": report["trajectoryCopyAudit"], "controlledChange": CONTROLLED_CHANGE, "cacheReuse": references,
        "scope": "observed-public-synthetic-ownership-development-not-chord-accuracy", "elapsedSeconds": time.perf_counter() - started})
    write_json(output / "report.json", result)
    print(json.dumps({"targets": result["targets"], "summaries": result["summaries"], "elapsedSeconds": result["elapsedSeconds"]}, sort_keys=True), flush=True)


def evaluate(source: Path, run: Path, output: Path) -> None:
    # Read only the reference directory identity to establish failure-path guards;
    # actual report/version/digest validation still occurs before any model/data use.
    reference_run = Path(json.loads((run / "report.json").read_bytes())["cacheReuse"]["v3Run"])
    with preserved_inputs((source, run / "report.json", run / "protocol.json", run / "affinity-weights.pt",
            run / "frozen-protocol.md", run / "cache/manifest.json", run / "cache/weights.npy") + v3_reference_paths(reference_run)):
        _evaluate(source, run, output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("preflight", "fit", "evaluate"):
        sub = commands.add_parser(command)
        sub.add_argument("--source", type=Path, required=True)
        if command != "preflight":
            sub.add_argument("--output", type=Path, required=True)
        if command == "fit":
            sub.add_argument("--protocol", type=Path, required=True)
            sub.add_argument("--v3-run", type=Path, required=True)
        elif command == "evaluate":
            sub.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "preflight":
        with preserved_inputs((args.source.resolve(),)):
            records = load_official_source(args.source.resolve())
            training, development, reserved = split_writers(records)
            samples = tuple(sample for sample in records if sample.writer in training)
            print(json.dumps(training_plan(samples, training), sort_keys=True), flush=True)
    elif args.command == "fit":
        fit(args.source.resolve(), args.protocol.resolve(), args.v3_run.resolve(), args.output.resolve())
    else:
        evaluate(args.source.resolve(), args.run.resolve(), args.output.resolve())
