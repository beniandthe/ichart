"""Strict report-only join to frozen Swift public ownership measurements.

No grouping, model import, fitting, feature construction, or prediction occurs
here. Unlisted baseline rows are successes only after full-cohort and aggregate
reconciliation. Encoder-input defects are not ownership defects.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re

from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers

VERSION = "public-stroke-affinity-baseline-join-v1"
COUNT = 1552
POLICIES = ("preserveOriginalInk", "semanticNormalization")
PAIR_ARMS = tuple(f"second{dimension}-gap{gap:g}" for dimension in (16, 32) for gap in (3.2, 8, 16))
ARMS = ("single32",) + PAIR_ARMS
TRIPLE_ARM = "triple32-16-16-gap8-8"
SWIFT_FILES = frozenset((
    "iChart/Recognition/StrokeClusterer.swift", "iChart/Recognition/StrokeClustererSupport.swift",
    "iChart/Recognition/InkTrajectoryTypes.swift", "iChart/Recognition/InkTypes.swift",
    "iChart/Recognition/Learned/ChordInkRasterizer.swift", "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
    "iChartTests/Recognition/PersonalInkPublicGroupingTests.swift",
    "iChartTests/Recognition/PersonalInkPublicRootBenchmarkTests.swift"))
PAIR_FILE = "iChartTests/Recognition/PersonalInkPublicPairGroupingTests.swift"
LEARNED_FILES = frozenset((
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
    "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/features.py", "recognition_ml/ichart_recognition_ml/schema.py",
    "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md"))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_code(report: dict, root: Path, required: frozenset[str]) -> None:
    code = report.get("codeSHA256")
    if not isinstance(code, dict) or not required <= set(code):
        raise ValueError("Missing source code provenance")
    for name, expected in code.items():
        path = Path(name)
        if (path.is_absolute() or ".." in path.parts or not isinstance(expected, str)
                or re.fullmatch(r"[0-9a-f]{64}", expected) is None):
            raise ValueError("Invalid code provenance path/digest")
        resolved = (root / path).resolve()
        if not resolved.is_relative_to(root.resolve()) or digest(resolved.read_bytes()) != expected:
            raise ValueError(f"Changed authoritative source: {name}")


@dataclass(frozen=True)
class Expected:
    writer: str
    session: int
    owners: tuple[tuple[int, ...], ...]
    zero_extent: int


def development_samples(records: tuple[Sample, ...]) -> tuple[Sample, ...]:
    _, writers, _ = split_writers(records)
    samples = tuple(sample for sample in records if sample.writer in writers)
    labels = {sample.label for sample in records}
    if (len(records) != 11640 or len({sample.identity for sample in records}) != len(records)
            or len(labels) != 97 or len(samples) != COUNT):
        raise ValueError("Incomplete or repeated strict public source")
    for writer in writers:
        for session in (1, 2):
            batch = [sample for sample in samples if sample.writer == writer and sample.session == session]
            if len(batch) != 97 or {sample.label for sample in batch} != labels:
                raise ValueError("Incomplete development writer/session")
    return samples


def expected_targets(samples: tuple[Sample, ...], owners: int = 1) -> dict[tuple[str, ...], Expected]:
    """Only identity order/stroke counts; no transforms, features or grouping."""
    if owners not in (1, 2, 3):
        raise ValueError("Unsupported source owner count")
    batches = defaultdict(list)
    for sample in samples:
        batches[(sample.writer, sample.session)].append(sample)
    sequences = []
    for key in sorted(batches):
        batch = batches[key]
        prefix = "public-pair-v1:" if owners == 2 else "public-triple-v1:"
        ordered = sorted(batch, key=lambda sample: (digest((prefix + sample.identity).encode()), sample.identity))
        sequences.extend(tuple(ordered[(index + offset) % len(ordered)] for offset in range(owners))
                         for index in range(len(ordered)))
    result = {}
    for sequence in sequences:
        groups, count, zero = [], 0, 0
        for sample in sequence:
            if not sample.strokes or any(not stroke.points for stroke in sample.strokes):
                raise ValueError("Empty source trajectory")
            groups.append(tuple(range(count, count + len(sample.strokes))))
            count += len(sample.strokes)
            points = [point for stroke in sample.strokes for point in stroke.points]
            zero += int(len({(point.x, point.y) for point in points}) == 1)
        key = tuple(sample.identity for sample in sequence)
        if key in result:
            raise ValueError("Repeated source key")
        result[key] = Expected(sequence[0].writer, sequence[0].session, tuple(groups), zero)
    if len(result) != COUNT:
        raise ValueError("Wrong source-key denominator")
    return result


def canonical(groups) -> tuple[tuple[int, ...], ...]:
    if (not isinstance(groups, (list, tuple)) or any(not isinstance(group, (list, tuple)) for group in groups)
            or any(type(index) is not int for group in groups for index in group)):
        raise ValueError("Invalid ownership indexes")
    return tuple(sorted(tuple(sorted(group)) for group in groups))


def partition_stats(groups, expected: Expected) -> dict:
    canonical_groups = canonical(groups)
    count = sum(map(len, expected.owners))
    flat = [index for group in groups for index in group]
    valid = [index for index in flat if 0 <= index < count]
    missing = count - len(set(valid))
    duplicates = len(valid) - len(set(valid))
    invalid = len(flat) - len(valid)
    exact_indexes = not (missing or duplicates or invalid)
    owner_sets, group_sets = list(map(set, expected.owners)), list(map(set, groups))
    merged = sum(sum(bool(group & owner) for owner in owner_sets) > 1 for group in group_sets)
    split = sum(sum(bool(owner & group) for group in group_sets) > 1 for owner in owner_sets)
    return {"groupCount": len(groups), "missingIndexes": missing, "duplicateIndexes": duplicates,
        "invalidIndexes": invalid, "exactIndexPartition": exact_indexes,
        "matchesExpectedGroups": exact_indexes and canonical_groups == canonical(expected.owners),
        "oneCompleteGroup": len(groups) == 1 and exact_indexes,
        "falseMergedGroups": merged, "falseSplitOwners": split}


def pair_arm(arm) -> str:
    if isinstance(arm, dict):
        dimension, gap = arm.get("secondDimension"), arm.get("gap")
    elif isinstance(arm, str):
        match = re.fullmatch(r"second(16|32)-gap(3\.2|8(?:\.0)?|16(?:\.0)?)", arm)
        if match is None:
            raise ValueError("Unsupported pair arm")
        dimension, gap = map(float, match.groups())
    else:
        raise ValueError("Invalid pair arm")
    if type(dimension) not in (int, float) or type(gap) not in (int, float) or (dimension, gap) not in (
            (16, 3.2), (16, 8), (16, 16), (32, 3.2), (32, 8), (32, 16)):
        raise ValueError("Unsupported pair geometry")
    return f"second{int(dimension)}-gap{gap:g}"


def _assert_fields(actual: dict, expected: dict) -> None:
    for name, value in expected.items():
        if name not in actual or type(actual[name]) is not type(value) or actual[name] != value:
            raise ValueError(f"Contradictory report field: {name}")


def reconstruct_baseline(report: dict, samples: tuple[Sample, ...], *, paired: bool) -> dict:
    """Reconcile every report arm, not only the later comparable points32 arm."""
    _assert_fields(report, {"sourceSHA256": SOURCE_SHA256, "sourceRecords": 11640,
        "evaluatedRecords": COUNT, "evaluatedWriters": 8, "reservedWritersNotGroupedOrRasterized": 20,
        "version": "public-adjacent-character-ownership-v1" if paired else "public-isolated-glyph-ownership-v1"})
    if paired:
        _assert_fields(report, {"pairs": COUNT, "firstDimension": 32, "bottomAlignment": 32,
            "rasterChecks": 0, "classificationAndPersonalizationRuns": 0})
    else:
        _assert_fields(report, {"labels": 97, "sessions": [1, 2]})
    cohort = expected_targets(samples, 2 if paired else 1)
    arms = PAIR_ARMS if paired else ("raw", "points24", "points32", "points48")
    failures, seen = {}, set()
    for row in report["failedPairs" if paired else "failedRecords"]:
        arm = pair_arm(row["arm"]) if paired else row["arm"]
        ids = tuple(row["sourceIDs"]) if paired else (row["sourceID"],)
        key = (row["policy"], arm, ids)
        if row["policy"] not in POLICIES or arm not in arms or ids not in cohort or key in seen:
            raise ValueError("Duplicate, unknown, reversed, or out-of-cohort baseline failure")
        seen.add(key)
        expected = cohort[ids]
        if paired and canonical(row["expectedOwners"]) != canonical(expected.owners):
            raise ValueError("Changed baseline source-owner mapping")
        stats = partition_stats(row["groupStrokeIndexes"], expected)
        result = row["result"]["source"] if paired else row["result"]
        _assert_fields(result, {name: value for name, value in stats.items() if not name.startswith("false")})
        mismatch = result["modelInputMismatchGroups"]
        if type(mismatch) is not int or not 0 <= mismatch <= stats["groupCount"]:
            raise ValueError("Invalid model-input mismatch count")
        if paired:
            _assert_fields(row["result"], {"exactTwoOwnerMatch": stats["matchesExpectedGroups"],
                "falseMergedGroups": stats["falseMergedGroups"], "falseSplitOwners": stats["falseSplitOwners"],
                "zeroExtentCharacters": expected.zero_extent})
        if (stats["matchesExpectedGroups"] and mismatch == 0
                and not result.get("rasterMismatch", False) and not result.get("rasterEncodingFailed", False)):
            raise ValueError("Unexpected fully successful failed row")
        failures[key] = (stats, result)

    summaries, output = set(), {}
    for summary in report["summaries"]:
        arm = pair_arm(summary["arm"]) if paired else summary["arm"]
        key = (summary["policy"], arm)
        if summary["policy"] not in POLICIES or arm not in arms or key in summaries:
            raise ValueError("Duplicate/unknown baseline summary")
        summaries.add(key)
        totals, by_writer = Counter(), defaultdict(Counter)
        for ids, expected in cohort.items():
            failed = failures.get((*key, ids))
            stats, result = failed if failed else (partition_stats(expected.owners, expected), {})
            correct = stats["matchesExpectedGroups"]
            mismatch = result.get("modelInputMismatchGroups", 0)
            values = {"pairs" if paired else "records": 1, "groupCount": stats["groupCount"],
                "exactTwoOwnerMatches" if paired else "oneCompleteGroup": int(correct),
                "exactIndexPartitions" if paired else "exactIndexPartition": int(stats["exactIndexPartition"]),
                "modelInputMismatchGroups": mismatch, "missingIndexes": stats["missingIndexes"],
                "duplicateIndexes": stats["duplicateIndexes"], "invalidIndexes": stats["invalidIndexes"],
                "exactOwnersAndModelInputs" if paired else "completeExactModelInput": int(correct and mismatch == 0)}
            if paired:
                values.update(twoGroupCount=int(stats["groupCount"] == 2), falseMergedGroups=stats["falseMergedGroups"],
                    falseMergedPairs=int(stats["falseMergedGroups"] > 0), falseSplitOwners=stats["falseSplitOwners"],
                    falseSplitPairs=int(stats["falseSplitOwners"] > 0), zeroExtentCharacters=expected.zero_extent)
            else:
                values.update(splitRecords=int(stats["groupCount"] > 1), emptyRecords=int(stats["groupCount"] == 0),
                    zeroExtent=expected.zero_extent, rasterChecks=int(arm == "points32" and stats["oneCompleteGroup"]),
                    rasterMismatches=int(result.get("rasterMismatch", False)),
                    rasterEncodingFailures=int(result.get("rasterEncodingFailed", False)))
            totals.update(values); by_writer[expected.writer].update(values)
            comparable_arm = arm if paired else "single32"
            if paired or arm == "points32":
                output[(summary["policy"], comparable_arm, ids)] = stats
        _assert_fields(summary["counts"], dict(totals))
        if set(summary["byWriter"]) != set(by_writer):
            raise ValueError("Baseline writer population mismatch")
        for writer, counts in by_writer.items():
            _assert_fields(summary["byWriter"][writer], dict(counts))
    if summaries != {(policy, arm) for policy in POLICIES for arm in arms}:
        raise ValueError("Missing baseline arm/policy")
    return output


def compare_reports(records: tuple[Sample, ...], isolated: dict, paired: dict, evaluation: dict,
                    repo_root: Path) -> dict:
    samples = development_samples(records)
    writers = sorted({sample.writer for sample in samples})
    verify_code(isolated, repo_root, SWIFT_FILES)
    verify_code(paired, repo_root, SWIFT_FILES | {PAIR_FILE})
    # Different implementations must retain their OWN code identities; equality
    # between the learned and Swift maps would be the wrong provenance check.
    verify_code(evaluation, repo_root, LEARNED_FILES)
    _assert_fields(evaluation, {"sourceSHA256": SOURCE_SHA256, "developmentWriters": writers,
        "reservedWritersEvaluated": False, "privateInkUsed": False, "productionEligible": False})
    baseline = reconstruct_baseline(isolated, samples, paired=False)
    baseline.update(reconstruct_baseline(paired, samples, paired=True))
    cohorts = {"single32": expected_targets(samples), **{arm: expected_targets(samples, 2) for arm in PAIR_ARMS},
        TRIPLE_ARM: expected_targets(samples, 3)}
    learned, seen, totals, by_writer, rows = {}, set(), defaultdict(Counter), defaultdict(lambda: defaultdict(Counter)), []
    eval_totals, eval_writers = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter))
    source_by_id = {sample.identity: sample for sample in samples}
    for row in evaluation["rows"]:
        arm = row["arm"]
        ids = tuple(row["sourceIDs"])
        key = (arm, ids)
        if arm not in cohorts or ids not in cohorts[arm] or key in seen:
            raise ValueError("Duplicate, unknown, reversed, or incomplete evaluation cohort")
        seen.add(key)
        expected = cohorts[arm][ids]
        _assert_fields(row, {"role": "development", "writer": expected.writer, "session": expected.session,
            "sourceStrokeCount": sum(map(len, expected.owners))})
        if canonical(row["expectedOwners"]) != canonical(expected.owners):
            raise ValueError("Changed evaluation source-owner mapping")
        stats = partition_stats(row["groups"], expected)
        _assert_fields(row, {"exactOwnerMatch": stats["matchesExpectedGroups"]})
        _assert_fields(row["metrics"], {"exactPartition": stats["matchesExpectedGroups"],
            **{name: stats[name] for name in ("groupCount", "missingIndexes", "duplicateIndexes",
                "invalidIndexes", "falseMergedGroups", "falseSplitOwners")},
            "expectedOwnerCount": len(expected.owners)})
        learned[key] = stats
        counts = {"targets": 1, "exactPartitions": int(stats["matchesExpectedGroups"]),
            "falseMergedTargets": int(stats["falseMergedGroups"] > 0),
            "falseSplitTargets": int(stats["falseSplitOwners"] > 0),
            "singletonTargets": int(sum(map(len, expected.owners)) == 1),
            "sourceStrokes": sum(map(len, expected.owners)), "sourcePoints": sum(
                len(stroke.points) for identity in ids for stroke in source_by_id[identity].strokes),
            "zeroExtentCharacters": expected.zero_extent,
            **{name: stats[name] for name in ("falseMergedGroups", "falseSplitOwners", "missingIndexes",
                "duplicateIndexes", "invalidIndexes")}}
        eval_totals[arm].update(counts); eval_writers[arm][expected.writer].update(counts)
    expected_keys = {(arm, ids) for arm, cohort in cohorts.items() for ids in cohort}
    if seen != expected_keys or evaluation.get("targets") != len(expected_keys):
        raise ValueError("Missing evaluation targets; denominator cannot shrink")
    summary_arms = set()
    for summary in evaluation["summaries"]:
        arm = summary["arm"]
        if arm not in cohorts or arm in summary_arms or set(summary["byWriter"]) != set(writers):
            raise ValueError("Missing, duplicate, or wrong evaluation summary cohort")
        summary_arms.add(arm)
        _assert_fields(summary["counts"], dict(eval_totals[arm]))
        for writer in writers:
            _assert_fields(summary["byWriter"][writer], dict(eval_writers[arm][writer]))
    if summary_arms != set(cohorts):
        raise ValueError("Missing evaluation arm summary")
    root_harms = 0
    for (policy, arm, ids), old_stats in sorted(baseline.items()):
        new_stats = learned[(arm, ids)]
        old, new = old_stats["matchesExpectedGroups"], new_stats["matchesExpectedGroups"]
        writer = cohorts[arm][ids].writer
        counts = {"denominator": 1, "baselineCorrect": int(old), "learnedCorrect": int(new),
            "gainedCorrect": int(new and not old), "lostCorrect": int(old and not new),
            "bothCorrect": int(old and new), "bothIncorrect": int(not old and not new),
            "baselineFalseMergedTargets": int(old_stats["falseMergedGroups"] > 0),
            "learnedFalseMergedTargets": int(new_stats["falseMergedGroups"] > 0),
            "baselineFalseSplitTargets": int(old_stats["falseSplitOwners"] > 0),
            "learnedFalseSplitTargets": int(new_stats["falseSplitOwners"] > 0)}
        totals[(policy, arm)].update(counts); by_writer[(policy, arm)][writer].update(counts)
        rows.append({"policy": policy, "arm": arm, "writer": writer, "sourceIDs": ids,
            "baselineExactOwnerMatch": old, "learnedExactOwnerMatch": new,
            "baselinePartitionMetrics": old_stats, "learnedPartitionMetrics": new_stats})
        # Public source labels enter only this post-prediction, predeclared gate.
        if (policy == "preserveOriginalInk" and arm == "single32" and old and not new
                and source_by_id[ids[0]].label in "ABCDEFG"):
            root_harms += 1
    violations = []
    if any(sum(counts[name] for name in ("missingIndexes", "duplicateIndexes", "invalidIndexes"))
           for counts in eval_totals.values()):
        violations.append("source-index-defects")
    for (policy, arm), counts in sorted(totals.items()):
        if policy != "preserveOriginalInk":
            continue
        if counts["learnedCorrect"] < counts["baselineCorrect"]:
            violations.append("lower-exact-arm:" + arm)
        for writer, values in sorted(by_writer[(policy, arm)].items()):
            if values["learnedCorrect"] < values["baselineCorrect"]:
                violations.append("lower-exact-writer:" + arm + "/" + writer)
        if arm in PAIR_ARMS and counts["learnedFalseMergedTargets"] > counts["baselineFalseMergedTargets"]:
            violations.append("higher-false-merged-pair-count:" + arm)
    if root_harms:
        violations.append("new-isolated-A-G-baseline-correct-harms")
    return {"version": VERSION, "sourceSHA256": SOURCE_SHA256,
        "scope": "Matched public development ownership only; not natural chord or new-user accuracy",
        "primaryPolicy": "preserveOriginalInk", "legacyPolicy": "semanticNormalization",
        "uncomparedArms": [TRIPLE_ARM], "denominatorPerArm": COUNT,
        "integrationGate": {"eligibleForComparisonOnlyIntegration": not violations,
            "productionEligible": False, "isolatedRootBaselineCorrectHarms": root_harms, "violations": violations},
        "uncomparedArmCounts": {TRIPLE_ARM: dict(eval_totals[TRIPLE_ARM])},
        "baselineCodeSHA256": {"isolated": isolated["codeSHA256"], "paired": paired["codeSHA256"]},
        "learnedCodeSHA256": evaluation["codeSHA256"], "summaries": [
            {"policy": policy, "arm": arm, "counts": dict(counts), "byWriter": {
                writer: dict(values) for writer, values in sorted(by_writer[(policy, arm)].items())}}
            for (policy, arm), counts in sorted(totals.items())], "rows": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("source", "repo-root", "isolated-report", "pair-report", "evaluation-report", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    args = parser.parse_args()
    inputs = [args.source.resolve(), args.isolated_report.resolve(), args.pair_report.resolve(),
        args.evaluation_report.resolve()]
    output = args.output.resolve()
    if output in inputs or output.exists():
        raise ValueError("Output must be a new append-only report")
    snapshots = {path: path.read_bytes() for path in inputs}
    join_code = Path(__file__).resolve().read_bytes()
    try:
        isolated, paired, evaluation = (json.loads(snapshots[path]) for path in inputs[1:])
        result = compare_reports(load_official_source(inputs[0]), isolated, paired, evaluation, args.repo_root.resolve())
        result.update(inputSHA256={name: digest(snapshots[path]) for name, path in zip(
            ("source", "isolatedBaseline", "pairedBaseline", "learnedEvaluation"), inputs)},
            joinCodeSHA256=digest(join_code))
        for path, data in snapshots.items():
            if path.read_bytes() != data:
                raise ValueError("Input changed during baseline join")
        for report, required in ((isolated, SWIFT_FILES), (paired, SWIFT_FILES | {PAIR_FILE}), (evaluation, LEARNED_FILES)):
            verify_code(report, args.repo_root.resolve(), required)
        if Path(__file__).resolve().read_bytes() != join_code:
            raise ValueError("Join source changed")
        with output.open("x") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
        print(json.dumps({"version": VERSION, "summaries": [{"policy": row["policy"], "arm": row["arm"],
            "counts": row["counts"]} for row in result["summaries"]]}, sort_keys=True))
    finally:
        if any(path.read_bytes() != data for path, data in snapshots.items()):
            raise ValueError("Input source/report bytes changed")


if __name__ == "__main__":
    main()
