"""Report-only v2 comparison: fixed Swift cohorts and retained v1 predictions.

No model import, features, grouping, fitting, prediction, or v1 mutation. New
contexts are measured explicitly rather than assigned a nonexistent baseline.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re

from . import stroke_affinity_baseline as base
from .uji_personal import SOURCE_SHA256, Sample, load_official_source

VERSION = "public-stroke-affinity-v2-baseline-join-v1"
V1_VERSION = "public-stroke-affinity-experiment-v1"
V2_VERSION = "public-stroke-affinity-experiment-v2"
V1_PROTOCOL = "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md"
V2_PROTOCOL = "docs/personal-learned-stroke-ownership-v2-protocol-2026-09-30.md"
V2_FILES = base.LEARNED_FILES | frozenset((V2_PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_experiment.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_baseline.py",
    "recognition_ml/tests/test_stroke_affinity_v2.py",
    "recognition_ml/tests/test_stroke_affinity_v2_experiment.py",
    "recognition_ml/tests/test_stroke_affinity_v2_baseline.py"))
PREFIXES = {2: "public-pair-v1:", 3: "public-triple-v1:",
    4: "public-quad-v2:", 5: "public-five-stress-v2:"}
EDGE_FIELDS = ("edgeTruePositive", "edgeFalsePositive", "edgeTrueNegative", "edgeFalseNegative", "edgeZeroLogitTies")


def arm_name(cardinality: int, dimension: int = 32, gap: float = 8) -> str:
    if cardinality == 1:
        return "single32"
    if cardinality not in PREFIXES or dimension not in (16, 32) or gap not in (3.2, 8, 16):
        raise ValueError("Undeclared context")
    if cardinality == 2:
        return f"second{dimension}-gap{gap:g}"
    name = {3: "triple", 4: "quad", 5: "five"}[cardinality]
    return name + "32-" + "-".join([str(dimension)] * (cardinality - 1)) + "-gap" + "-".join([f"{gap:g}"] * (cardinality - 1))


ARM_CARDINALITY = {"single32": 1, **{arm_name(count, dimension, gap): count
    for count in (2, 3, 4, 5) for dimension in (16, 32) for gap in (3.2, 8, 16)}}
V1_ARMS = frozenset(base.ARMS + (base.TRIPLE_ARM,))


def expected_contexts(samples: tuple[Sample, ...], cardinality: int) -> dict:
    if cardinality <= 3:
        return base.expected_targets(samples, cardinality)
    if cardinality not in PREFIXES:
        raise ValueError("Undeclared source cardinality")
    batches = defaultdict(list)
    for sample in samples:
        batches[(sample.writer, sample.session)].append(sample)
    result = {}
    for key in sorted(batches):
        ordered = sorted(batches[key], key=lambda sample: (
            base.digest((PREFIXES[cardinality] + sample.identity).encode()), sample.identity))
        for index in range(len(ordered)):
            sources = tuple(ordered[(index + offset) % len(ordered)] for offset in range(cardinality))
            owners, count, zero = [], 0, 0
            for source in sources:
                if not source.strokes or any(not stroke.points for stroke in source.strokes):
                    raise ValueError("Empty public trajectory")
                owners.append(tuple(range(count, count + len(source.strokes))))
                count += len(source.strokes)
                zero += int(len({(point.x, point.y) for stroke in source.strokes for point in stroke.points}) == 1)
            ids = tuple(source.identity for source in sources)
            if ids in result:
                raise ValueError("Duplicate cyclic source sequence")
            result[ids] = base.Expected(sources[0].writer, sources[0].session, tuple(owners), zero)
    if len(result) != base.COUNT:
        raise ValueError("Wrong source-key denominator")
    return result


def validate_evaluation(report: dict, samples: tuple[Sample, ...], root: Path, *, v2: bool) -> dict:
    protocol = V2_PROTOCOL if v2 else V1_PROTOCOL
    base.verify_code(report, root, V2_FILES if v2 else base.LEARNED_FILES)
    base._assert_fields(report, {"version": V2_VERSION if v2 else V1_VERSION,
        "sourceSHA256": SOURCE_SHA256, "sourceUnchanged": True,
        "developmentWriters": sorted({sample.writer for sample in samples}),
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False,
        "protocolSHA256": base.digest((root / protocol).read_bytes())})
    if report["codeSHA256"].get(protocol) != report["protocolSHA256"]:
        raise ValueError("Protocol and code bindings disagree")
    if v2:
        base._assert_fields(report, {"featureSchema": "stroke-affinity-pair-local-v2", "featureCount": 202})
    for field in ("weightsSHA256", "trainingReportSHA256"):
        if not isinstance(report.get(field), str) or re.fullmatch(r"[0-9a-f]{64}", report[field]) is None:
            raise ValueError("Missing frozen model/report digest")
    arms = set(ARM_CARDINALITY) if v2 else set(V1_ARMS)
    contexts = {count: expected_contexts(samples, count) for count in {ARM_CARDINALITY[arm] for arm in arms}}
    sources = {sample.identity: sample for sample in samples}
    rows, stats_by_key, totals, by_writer, by_label = {}, {}, defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), defaultdict(Counter)
    for row in report["rows"]:
        arm, ids = row["arm"], tuple(row["sourceIDs"])
        if arm not in arms:
            raise ValueError("Undeclared evaluation arm")
        context = contexts[ARM_CARDINALITY[arm]]
        key = (arm, ids)
        if ids not in context or key in rows:
            raise ValueError("Duplicate, reversed, or wrong-context source IDs")
        expected = context[ids]
        count = sum(map(len, expected.owners))
        base._assert_fields(row, {"role": "development", "writer": expected.writer, "session": expected.session,
            "sourceStrokeCount": count, "candidateID": "+".join(ids) + "/" + arm})
        if v2:
            base._assert_fields(row, {"cardinality": len(ids)})
        base.canonical(row["expectedOwners"])
        if tuple(tuple(owner) for owner in row["expectedOwners"]) != expected.owners:
            raise ValueError("Changed ordered source-owner mapping")
        stats = base.partition_stats(row["groups"], expected)
        base._assert_fields(row, {"exactOwnerMatch": stats["matchesExpectedGroups"]})
        base._assert_fields(row["metrics"], {"exactPartition": stats["matchesExpectedGroups"],
            "expectedOwnerCount": len(ids), **{name: stats[name] for name in ("groupCount", "falseMergedGroups",
                "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}})
        confusion = row["edgeConfusion"]
        if set(confusion) != set(EDGE_FIELDS) or any(type(confusion[name]) is not int or confusion[name] < 0 for name in EDGE_FIELDS):
            raise ValueError("Invalid binary edge confusion")
        positives = sum(len(owner) * (len(owner) - 1) // 2 for owner in expected.owners)
        if (confusion["edgeTruePositive"] + confusion["edgeFalseNegative"] != positives
                or confusion["edgeTrueNegative"] + confusion["edgeFalsePositive"] != count * (count - 1) // 2 - positives
                or confusion["edgeZeroLogitTies"] > confusion["edgeTrueNegative"] + confusion["edgeFalseNegative"]):
            raise ValueError("Edge confusion cannot describe this source target")
        if (set(row["timings"]) != {"featureSeconds", "inferenceAndPartitionSeconds"}
                or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0
                       for value in row["timings"].values())):
            raise ValueError("Invalid timing")
        counts = {"targets": 1, "exactPartitions": int(stats["matchesExpectedGroups"]),
            "singletonTargets": int(count == 1), "sourceStrokes": count, "sourcePoints": sum(
                len(stroke.points) for identity in ids for stroke in sources[identity].strokes),
            "zeroExtentCharacters": expected.zero_extent, "falseMergedTargets": int(stats["falseMergedGroups"] > 0),
            "falseSplitTargets": int(stats["falseSplitOwners"] > 0), **confusion,
            **{name: stats[name] for name in ("falseMergedGroups", "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}}
        totals[arm].update(counts); by_writer[arm][expected.writer].update(counts)
        if arm == "single32":
            by_label[sources[ids[0]].label].update(counts)
        rows[key], stats_by_key[key] = row, stats
    expected_keys = {(arm, ids) for arm in arms for ids in contexts[ARM_CARDINALITY[arm]]}
    if set(rows) != expected_keys or type(report.get("targets")) is not int or report["targets"] != len(expected_keys):
        raise ValueError("Incomplete fixed evaluation cohort")
    seen = set()
    for summary in report["summaries"]:
        arm = summary["arm"]
        if arm not in arms or arm in seen or set(summary["byWriter"]) != set(by_writer[arm]):
            raise ValueError("Duplicate/missing evaluation summary cohort")
        seen.add(arm)
        base._assert_fields(summary["counts"], dict(totals[arm]))
        for writer, values in by_writer[arm].items():
            base._assert_fields(summary["byWriter"][writer], dict(values))
    if seen != arms:
        raise ValueError("Missing arm summary")
    if "singlePartitionsByLabel" in report:
        if set(report["singlePartitionsByLabel"]) != set(by_label):
            raise ValueError("Wrong single-character audit population")
        for label, values in by_label.items():
            base._assert_fields(report["singlePartitionsByLabel"][label], dict(values))
    return {"rows": rows, "stats": stats_by_key, "totals": totals, "byWriter": by_writer}


def compare_reports(records: tuple[Sample, ...], isolated: dict, paired: dict,
                    v1_report: dict, v2_report: dict, root: Path) -> dict:
    samples = base.development_samples(records)
    base.verify_code(isolated, root, base.SWIFT_FILES)
    base.verify_code(paired, root, base.SWIFT_FILES | {base.PAIR_FILE})
    swift = base.reconstruct_baseline(isolated, samples, paired=False)
    swift.update(base.reconstruct_baseline(paired, samples, paired=True))
    old, new = validate_evaluation(v1_report, samples, root, v2=False), validate_evaluation(v2_report, samples, root, v2=True)
    baselines = {(f"swift-{policy}", arm, ids): stats for (policy, arm, ids), stats in swift.items()}
    baselines.update({("learned-v1", arm, ids): stats for (arm, ids), stats in old["stats"].items()})
    totals, by_writer, rows, root_harms = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), [], 0
    sources = {sample.identity: sample for sample in samples}
    for (baseline, arm, ids), previous in sorted(baselines.items()):
        current = new["stats"][(arm, ids)]
        a, b = previous["matchesExpectedGroups"], current["matchesExpectedGroups"]
        writer = new["rows"][(arm, ids)]["writer"]
        counts = {"denominator": 1, "baselineCorrect": int(a), "v2Correct": int(b),
            "gainedCorrect": int(b and not a), "lostCorrect": int(a and not b),
            "bothCorrect": int(a and b), "bothIncorrect": int(not a and not b),
            "baselineFalseMergedTargets": int(previous["falseMergedGroups"] > 0),
            "v2FalseMergedTargets": int(current["falseMergedGroups"] > 0),
            "baselineFalseSplitTargets": int(previous["falseSplitOwners"] > 0),
            "v2FalseSplitTargets": int(current["falseSplitOwners"] > 0),
            "baselineFalseMergedGroups": previous["falseMergedGroups"], "v2FalseMergedGroups": current["falseMergedGroups"],
            "baselineFalseSplitOwners": previous["falseSplitOwners"], "v2FalseSplitOwners": current["falseSplitOwners"]}
        totals[(baseline, arm)].update(counts); by_writer[(baseline, arm)][writer].update(counts)
        rows.append({"baseline": baseline, "arm": arm, "sourceIDs": ids, "writer": writer,
            "baselineMetrics": previous, "v2Metrics": current})
        if baseline == "swift-preserveOriginalInk" and arm == "single32" and a and not b and sources[ids[0]].label in "ABCDEFG":
            root_harms += 1
    violations = []
    if any(sum(values[name] for name in ("missingIndexes", "duplicateIndexes", "invalidIndexes")) for values in new["totals"].values()):
        violations.append("source-index-defects")
    for (baseline, arm), values in sorted(totals.items()):
        if baseline != "swift-preserveOriginalInk":
            continue
        if values["v2Correct"] < values["baselineCorrect"]:
            violations.append("lower-exact-arm:" + arm)
        for writer, counts in sorted(by_writer[(baseline, arm)].items()):
            if counts["v2Correct"] < counts["baselineCorrect"]:
                violations.append("lower-exact-writer:" + arm + "/" + writer)
        if arm in base.PAIR_ARMS and values["v2FalseMergedTargets"] > values["baselineFalseMergedTargets"]:
            violations.append("higher-false-merged-pair-count:" + arm)
    if root_harms:
        violations.append("new-isolated-A-G-baseline-correct-harms")
    new_arms = sorted(set(ARM_CARDINALITY) - V1_ARMS)
    return {"version": VERSION, "sourceSHA256": SOURCE_SHA256,
        "scope": "Observed public component comparison, not a causal ablation, natural-chord or new-writer accuracy",
        "denominatorPerArm": base.COUNT, "v2Targets": len(new["rows"]),
        "protocolSHA256": {"v1": v1_report["protocolSHA256"], "v2": v2_report["protocolSHA256"]},
        "codeSHA256": {"swiftIsolated": isolated["codeSHA256"], "swiftPairs": paired["codeSHA256"],
            "v1": v1_report["codeSHA256"], "v2": v2_report["codeSHA256"]},
        "modelSHA256": {"v1": v1_report["weightsSHA256"], "v2": v2_report["weightsSHA256"]},
        "trainingReportSHA256": {"v1": v1_report["trainingReportSHA256"], "v2": v2_report["trainingReportSHA256"]},
        "reportedTrajectoryCopyAudit": {"v1": v1_report["trajectoryCopyAudit"], "v2": v2_report["trajectoryCopyAudit"]},
        "swiftIntegrationGate": {"eligibleForComparisonOnlyIntegration": not violations,
            "productionEligible": False, "isolatedRootBaselineCorrectHarms": root_harms, "violations": violations},
        "armStatus": [{"arm": arm, "cardinality": ARM_CARDINALITY[arm], "denominator": base.COUNT,
            "hasSwiftBaseline": arm in base.ARMS, "hasV1Baseline": arm in V1_ARMS,
            "status": "new-no-historical-baseline" if arm in new_arms else "matched-historical-cohort"}
            for arm in sorted(ARM_CARDINALITY)],
        "v2Summaries": [{"arm": arm, "counts": dict(values), "byWriter": {
            writer: dict(counts) for writer, counts in sorted(new["byWriter"][arm].items())}}
            for arm, values in sorted(new["totals"].items())],
        "comparisons": [{"baseline": baseline, "arm": arm, "counts": dict(values), "byWriter": {
            writer: dict(counts) for writer, counts in sorted(by_writer[(baseline, arm)].items())}}
            for (baseline, arm), values in sorted(totals.items())], "rows": rows,
        "newContextFailures": [row for (arm, _), row in sorted(new["rows"].items())
            if arm in new_arms and not row["exactOwnerMatch"]]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "repo-root", "isolated-report", "pair-report", "v1-evaluation-report", "v2-evaluation-report", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    inputs = [args.source.resolve(), args.isolated_report.resolve(), args.pair_report.resolve(),
        args.v1_evaluation_report.resolve(), args.v2_evaluation_report.resolve()]
    roles = ("source", "isolatedSwiftBaseline", "pairedSwiftBaseline", "v1Evaluation", "v2Evaluation")
    output, root = args.output.resolve(), args.repo_root.resolve()
    if output.exists() or output in inputs or len(set(inputs)) != len(inputs):
        raise ValueError("Distinct immutable inputs and a new append-only output are required")
    snapshots = {path: path.read_bytes() for path in inputs}
    helper_paths = (Path(__file__).resolve(), Path(base.__file__).resolve(),
        (root / "recognition_ml/tests/test_stroke_affinity_v2_baseline.py").resolve())
    helpers = {path: path.read_bytes() for path in helper_paths}
    reports = []
    try:
        isolated, paired, v1_report, v2_report = (json.loads(snapshots[path]) for path in inputs[1:])
        reports = [(isolated, base.SWIFT_FILES), (paired, base.SWIFT_FILES | {base.PAIR_FILE}),
            (v1_report, base.LEARNED_FILES), (v2_report, V2_FILES)]
        result = compare_reports(load_official_source(inputs[0]), isolated, paired, v1_report, v2_report, root)
        result.update(inputSHA256={role: base.digest(snapshots[path]) for role, path in zip(roles, inputs)},
            comparisonCodeSHA256={str(path.relative_to(root)): base.digest(data) for path, data in helpers.items()})
        for report, required in reports:
            base.verify_code(report, root, required)
        if any(path.read_bytes() != data for path, data in {**snapshots, **helpers}.items()):
            raise ValueError("Source, reports, or comparison helpers changed")
        with output.open("x") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
        print(json.dumps({"version": VERSION, "v2Targets": result["v2Targets"],
            "swiftIntegrationGate": result["swiftIntegrationGate"], "comparisons": [
                {"baseline": row["baseline"], "arm": row["arm"], "counts": row["counts"]}
                for row in result["comparisons"]]}, sort_keys=True))
    finally:
        if any(path.read_bytes() != data for path, data in {**snapshots, **helpers}.items()):
            raise ValueError("Immutable source/report/helper bytes changed")
        for report, required in reports:
            base.verify_code(report, root, required)


if __name__ == "__main__":
    main()
