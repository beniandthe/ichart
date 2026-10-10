"""Report-only genuine V3 join to immutable V1, V2 and Swift evidence.

No model import, features, grouping, fitting or prediction. Only V2/V3 is the
frozen feature-family comparison; no historical report is relabeled or mutated.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re

from . import stroke_affinity_baseline as base
from . import stroke_affinity_v2_baseline as v2
from .uji_personal import SOURCE_SHA256, Sample, load_official_source

VERSION = "public-stroke-affinity-v3-baseline-join-v1"
V3_VERSION = "public-stroke-affinity-experiment-v3"
V3_PROTOCOL = "docs/personal-learned-stroke-ownership-v3-protocol-2026-09-30.md"
V3_FILES = v2.V2_FILES | frozenset((V3_PROTOCOL,
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_baseline.py",
    "recognition_ml/tests/test_stroke_affinity.py",
    "recognition_ml/tests/test_stroke_affinity_experiment.py",
    "recognition_ml/tests/test_stroke_affinity_baseline.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_experiment.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_baseline.py",
    "recognition_ml/tests/test_stroke_affinity_v3_experiment.py",
    "recognition_ml/tests/test_stroke_affinity_v3_baseline.py"))


def validate_evaluation(report: dict, samples: tuple[Sample, ...], root: Path) -> dict:
    """Validate genuine V3 metadata and the unchanged complete V2 cohort."""
    base.verify_code(report, root, V3_FILES)
    base._assert_fields(report, {"version": V3_VERSION, "featureSchema": "stroke-affinity-context-v1",
        "featureCount": 202, "sourceSHA256": SOURCE_SHA256, "sourceUnchanged": True,
        "developmentWriters": sorted({sample.writer for sample in samples}),
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False,
        "protocolSHA256": base.digest((root / V3_PROTOCOL).read_bytes())})
    if report["codeSHA256"].get(V3_PROTOCOL) != report["protocolSHA256"]:
        raise ValueError("V3 protocol and code bindings disagree")
    for field in ("weightsSHA256", "trainingReportSHA256"):
        if not isinstance(report.get(field), str) or re.fullmatch(r"[0-9a-f]{64}", report[field]) is None:
            raise ValueError("Missing frozen V3 model/report digest")
    contexts = {count: v2.expected_contexts(samples, count) for count in range(1, 6)}
    sources = {sample.identity: sample for sample in samples}
    rows, stats_by_key = {}, {}
    totals, by_writer, by_label = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), defaultdict(Counter)
    for row in report["rows"]:
        arm, ids = row["arm"], tuple(row["sourceIDs"])
        if arm not in v2.ARM_CARDINALITY:
            raise ValueError("Undeclared V3 evaluation arm")
        key, context = (arm, ids), contexts[v2.ARM_CARDINALITY[arm]]
        if ids not in context or key in rows:
            raise ValueError("Duplicate, reversed, or wrong-context V3 source IDs")
        expected = context[ids]
        count = sum(map(len, expected.owners))
        base._assert_fields(row, {"role": "development", "writer": expected.writer, "session": expected.session,
            "cardinality": len(ids), "sourceStrokeCount": count, "candidateID": "+".join(ids) + "/" + arm})
        base.canonical(row["expectedOwners"])
        if tuple(tuple(owner) for owner in row["expectedOwners"]) != expected.owners:
            raise ValueError("Changed ordered V3 source-owner mapping")
        stats = base.partition_stats(row["groups"], expected)
        base._assert_fields(row, {"exactOwnerMatch": stats["matchesExpectedGroups"]})
        base._assert_fields(row["metrics"], {"exactPartition": stats["matchesExpectedGroups"],
            "expectedOwnerCount": len(ids), **{name: stats[name] for name in ("groupCount", "falseMergedGroups",
                "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}})
        confusion = row["edgeConfusion"]
        if set(confusion) != set(v2.EDGE_FIELDS) or any(type(confusion[name]) is not int or confusion[name] < 0 for name in v2.EDGE_FIELDS):
            raise ValueError("Invalid V3 binary edge confusion")
        positives = sum(len(owner) * (len(owner) - 1) // 2 for owner in expected.owners)
        if (confusion["edgeTruePositive"] + confusion["edgeFalseNegative"] != positives
                or confusion["edgeTrueNegative"] + confusion["edgeFalsePositive"] != count * (count - 1) // 2 - positives
                or confusion["edgeZeroLogitTies"] > confusion["edgeTrueNegative"] + confusion["edgeFalseNegative"]):
            raise ValueError("V3 edge confusion cannot describe this source target")
        if (set(row["timings"]) != {"featureSeconds", "inferenceAndPartitionSeconds"}
                or any(type(value) not in (int, float) or not math.isfinite(value) or value < 0
                       for value in row["timings"].values())):
            raise ValueError("Invalid V3 timing")
        counts = {"targets": 1, "exactPartitions": int(stats["matchesExpectedGroups"]),
            "singletonTargets": int(count == 1), "sourceStrokes": count, "sourcePoints": sum(
                len(stroke.points) for identity in ids for stroke in sources[identity].strokes),
            "zeroExtentCharacters": expected.zero_extent, "falseMergedTargets": int(stats["falseMergedGroups"] > 0),
            "falseSplitTargets": int(stats["falseSplitOwners"] > 0), **confusion,
            **{name: stats[name] for name in ("falseMergedGroups", "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")}}
        totals[arm].update(counts); by_writer[arm][expected.writer].update(counts)
        if arm == "single32":
            # Labels are audit-only and are consulted after saved predictions.
            by_label[sources[ids[0]].label].update(counts)
        rows[key], stats_by_key[key] = row, stats
    expected_keys = {(arm, ids) for arm, count in v2.ARM_CARDINALITY.items() for ids in contexts[count]}
    if set(rows) != expected_keys or type(report.get("targets")) is not int or report["targets"] != len(expected_keys):
        raise ValueError("Incomplete fixed V3 evaluation cohort")
    seen = set()
    for summary in report["summaries"]:
        arm = summary["arm"]
        if arm not in v2.ARM_CARDINALITY or arm in seen or set(summary["byWriter"]) != set(by_writer[arm]):
            raise ValueError("Duplicate/missing V3 evaluation summary cohort")
        seen.add(arm)
        base._assert_fields(summary["counts"], dict(totals[arm]))
        for writer, values in by_writer[arm].items():
            base._assert_fields(summary["byWriter"][writer], dict(values))
    if seen != set(v2.ARM_CARDINALITY):
        raise ValueError("Missing V3 arm summary")
    if "singlePartitionsByLabel" in report:
        if set(report["singlePartitionsByLabel"]) != set(by_label):
            raise ValueError("Wrong V3 single-character audit population")
        for label, values in by_label.items():
            base._assert_fields(report["singlePartitionsByLabel"][label], dict(values))
    return {"rows": rows, "stats": stats_by_key, "totals": totals, "byWriter": by_writer}


def compare_reports(records: tuple[Sample, ...], isolated: dict, paired: dict,
                    v1_report: dict, v2_report: dict, v3_report: dict, root: Path) -> dict:
    samples = base.development_samples(records)
    base.verify_code(isolated, root, base.SWIFT_FILES)
    base.verify_code(paired, root, base.SWIFT_FILES | {base.PAIR_FILE})
    swift = base.reconstruct_baseline(isolated, samples, paired=False)
    swift.update(base.reconstruct_baseline(paired, samples, paired=True))
    historical = {"learned-v1": v2.validate_evaluation(v1_report, samples, root, v2=False),
        "learned-v2": v2.validate_evaluation(v2_report, samples, root, v2=True)}
    current = validate_evaluation(v3_report, samples, root)
    baselines = {(f"swift-{policy}", arm, ids): stats for (policy, arm, ids), stats in swift.items()}
    baselines.update({(name, arm, ids): stats for name, evidence in historical.items()
                      for (arm, ids), stats in evidence["stats"].items()})
    totals, by_writer, rows, root_harms = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), [], 0
    sources = {sample.identity: sample for sample in samples}
    for (baseline, arm, ids), previous in sorted(baselines.items()):
        key, now = (arm, ids), current["stats"][(arm, ids)]
        a, b = previous["matchesExpectedGroups"], now["matchesExpectedGroups"]
        writer = current["rows"][key]["writer"]
        counts = {"denominator": 1, "baselineCorrect": int(a), "v3Correct": int(b),
            "gainedCorrect": int(b and not a), "lostCorrect": int(a and not b),
            "bothCorrect": int(a and b), "bothIncorrect": int(not a and not b),
            "baselineFalseMergedTargets": int(previous["falseMergedGroups"] > 0),
            "v3FalseMergedTargets": int(now["falseMergedGroups"] > 0),
            "baselineFalseSplitTargets": int(previous["falseSplitOwners"] > 0),
            "v3FalseSplitTargets": int(now["falseSplitOwners"] > 0),
            "baselineFalseMergedGroups": previous["falseMergedGroups"], "v3FalseMergedGroups": now["falseMergedGroups"],
            "baselineFalseSplitOwners": previous["falseSplitOwners"], "v3FalseSplitOwners": now["falseSplitOwners"]}
        totals[(baseline, arm)].update(counts); by_writer[(baseline, arm)][writer].update(counts)
        joined = {"baseline": baseline, "arm": arm, "sourceIDs": ids, "writer": writer,
            "baselineMetrics": previous, "v3Metrics": now,
            "v3EdgeConfusion": current["rows"][key]["edgeConfusion"], "v3Timings": current["rows"][key]["timings"]}
        if baseline in historical:
            old_row = historical[baseline]["rows"][key]
            joined.update(baselineEdgeConfusion=old_row["edgeConfusion"], baselineTimings=old_row["timings"])
        rows.append(joined)
        if baseline == "swift-preserveOriginalInk" and arm == "single32" and a and not b and sources[ids[0]].label in "ABCDEFG":
            root_harms += 1
    violations = []
    if any(sum(values[name] for name in ("missingIndexes", "duplicateIndexes", "invalidIndexes")) for values in current["totals"].values()):
        violations.append("source-index-defects")
    for (baseline, arm), values in sorted(totals.items()):
        if baseline != "swift-preserveOriginalInk":
            continue
        if values["v3Correct"] < values["baselineCorrect"]:
            violations.append("lower-exact-arm:" + arm)
        for writer, counts in sorted(by_writer[(baseline, arm)].items()):
            if counts["v3Correct"] < counts["baselineCorrect"]:
                violations.append("lower-exact-writer:" + arm + "/" + writer)
        if arm in base.PAIR_ARMS and values["v3FalseMergedTargets"] > values["baselineFalseMergedTargets"]:
            violations.append("higher-false-merged-pair-count:" + arm)
    if root_harms:
        violations.append("new-isolated-A-G-baseline-correct-harms")
    reports = {"v1": v1_report, "v2": v2_report, "v3": v3_report}
    context_arms = set(v2.ARM_CARDINALITY) - v2.V1_ARMS
    return {"version": VERSION, "sourceSHA256": SOURCE_SHA256,
        "scope": "Frozen V2/V3 feature-family comparison within one seed and observed cohort; V1/Swift comparisons are not causal ablations or natural-chord/new-writer accuracy",
        "controlledFeatureFamilyComparison": {"baseline": "learned-v2", "current": "learned-v3",
            "baselineFeatureSchema": v2_report["featureSchema"], "currentFeatureSchema": v3_report["featureSchema"]},
        "denominatorPerArm": base.COUNT, "v3Targets": len(current["rows"]),
        "protocolSHA256": {name: report["protocolSHA256"] for name, report in reports.items()},
        "codeSHA256": {"swiftIsolated": isolated["codeSHA256"], "swiftPairs": paired["codeSHA256"],
            **{name: report["codeSHA256"] for name, report in reports.items()}},
        "modelSHA256": {name: report["weightsSHA256"] for name, report in reports.items()},
        "trainingReportSHA256": {name: report["trainingReportSHA256"] for name, report in reports.items()},
        "reportedTrajectoryCopyAudit": {name: report["trajectoryCopyAudit"] for name, report in reports.items()},
        "swiftIntegrationGate": {"eligibleForComparisonOnlyIntegration": not violations,
            "productionEligible": False, "isolatedRootBaselineCorrectHarms": root_harms, "violations": violations},
        "armStatus": [{"arm": arm, "cardinality": v2.ARM_CARDINALITY[arm], "denominator": base.COUNT,
            "hasSwiftBaseline": arm in base.ARMS, "hasV1Baseline": arm in v2.V1_ARMS, "hasV2Baseline": True,
            "status": "matched-v2-only-no-Swift-or-v1-baseline" if arm in context_arms else "matched-historical-cohort"}
            for arm in sorted(v2.ARM_CARDINALITY)],
        "v3Summaries": [{"arm": arm, "counts": dict(values), "byWriter": {
            writer: dict(counts) for writer, counts in sorted(current["byWriter"][arm].items())}}
            for arm, values in sorted(current["totals"].items())],
        "comparisons": [{"baseline": baseline, "arm": arm, "counts": dict(values), "byWriter": {
            writer: dict(counts) for writer, counts in sorted(by_writer[(baseline, arm)].items())}}
            for (baseline, arm), values in sorted(totals.items())], "rows": rows,
        "newContextFailures": [row for (arm, _), row in sorted(current["rows"].items())
            if arm in context_arms and not row["exactOwnerMatch"]]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "repo-root", "isolated-report", "pair-report", "v1-evaluation-report", "v2-evaluation-report", "v3-evaluation-report", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    inputs = [args.source.resolve(), args.isolated_report.resolve(), args.pair_report.resolve(),
        args.v1_evaluation_report.resolve(), args.v2_evaluation_report.resolve(), args.v3_evaluation_report.resolve()]
    roles = ("source", "isolatedSwiftBaseline", "pairedSwiftBaseline", "v1Evaluation", "v2Evaluation", "v3Evaluation")
    output, root = args.output.resolve(), args.repo_root.resolve()
    if output.exists() or output in inputs or len(set(inputs)) != len(inputs):
        raise ValueError("Distinct immutable inputs and a new append-only output are required")
    snapshots = {path: path.read_bytes() for path in inputs}
    helper_paths = (Path(__file__).resolve(), Path(base.__file__).resolve(), Path(v2.__file__).resolve(),
        (root / "recognition_ml/tests/test_stroke_affinity_v3_baseline.py").resolve())
    helpers = {path: path.read_bytes() for path in helper_paths}
    reports = []
    try:
        isolated, paired, v1_report, v2_report, v3_report = (json.loads(snapshots[path]) for path in inputs[1:])
        reports = [(isolated, base.SWIFT_FILES), (paired, base.SWIFT_FILES | {base.PAIR_FILE}),
            (v1_report, base.LEARNED_FILES), (v2_report, v2.V2_FILES), (v3_report, V3_FILES)]
        result = compare_reports(load_official_source(inputs[0]), isolated, paired, v1_report, v2_report, v3_report, root)
        result.update(inputSHA256={role: base.digest(snapshots[path]) for role, path in zip(roles, inputs)},
            comparisonCodeSHA256={str(path.relative_to(root)): base.digest(data) for path, data in helpers.items()})
        for report, required in reports:
            base.verify_code(report, root, required)
        if any(path.read_bytes() != data for path, data in {**snapshots, **helpers}.items()):
            raise ValueError("Source, reports, or comparison helpers changed")
        with output.open("x") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
        print(json.dumps({"version": VERSION, "v3Targets": result["v3Targets"],
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
