"""Fixed toy V4 report cohorts: no model, public predictions or private ink."""
import json
import unittest

import test_stroke_affinity_v3_baseline as v3_fixtures
from ichart_recognition_ml.research import stroke_affinity_baseline as base
from ichart_recognition_ml.research import stroke_affinity_v2_baseline as v2
from ichart_recognition_ml.research import stroke_affinity_v3_baseline as v3
from ichart_recognition_ml.research import stroke_affinity_v4_baseline as v4


class StrokeAffinityV4BaselineTests(unittest.TestCase):
    # Fresh TestCase, so none of the immutable V2/V3 tests are inherited.
    @classmethod
    def setUpClass(cls):
        v3_fixtures.StrokeAffinityV3BaselineTests.setUpClass.__func__(cls)

    swift_counts = staticmethod(v3_fixtures.StrokeAffinityV3BaselineTests.swift_counts)
    set_partition = staticmethod(v3_fixtures.StrokeAffinityV3BaselineTests.set_partition)
    make_swift = v3_fixtures.StrokeAffinityV3BaselineTests.make_swift
    make_evaluation = v3_fixtures.StrokeAffinityV3BaselineTests.make_evaluation
    refresh_summaries = v3_fixtures.StrokeAffinityV3BaselineTests.refresh_summaries
    preserved_compare = v3_fixtures.StrokeAffinityV3BaselineTests.preserved_compare
    comparison = staticmethod(v3_fixtures.StrokeAffinityV3BaselineTests.comparison)

    def setUp(self):
        v3_fixtures.StrokeAffinityV3BaselineTests.setUp(self)
        for name in v4.V4_FILES - set(self.code):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("code fixture:" + name).encode())
            self.code[name] = base.digest(path.read_bytes())
        self.v4_report = self.make_evaluation(True)
        self.v4_report.update(version=v4.V4_VERSION, featureSchema="stroke-affinity-context-v1", featureCount=202,
            protocolSHA256=self.code[v4.V4_PROTOCOL],
            codeSHA256={name: self.code[name] for name in v4.V4_FILES})

    def compare(self):
        return v4.compare_reports(self.records, self.isolated, self.paired,
                                  self.v1_report, self.v2_report, self.v3_report, self.v4_report, self.root)

    def report_digests(self):
        return tuple(base.digest(json.dumps(report, sort_keys=True).encode()) for report in
                     (self.isolated, self.paired, self.v1_report, self.v2_report, self.v3_report, self.v4_report))

    def invalid_v4(self):
        with self.assertRaises(ValueError):
            v4.validate_evaluation(self.v4_report, self.samples, self.root)

    def test_all72_joins_keep_full25_cohort_retained_triple_v3_gains_harms_and_reports(self):
        v1_triple = next(row for row in self.v1_report["rows"] if row["arm"] == base.TRIPLE_ARM)
        self.set_partition(v1_triple, [list(range(v1_triple["sourceStrokeCount"]))])
        self.refresh_summaries(self.v1_report)
        v2_arm = v2.arm_name(5, 16, 8)
        v2_failure = next(row for row in self.v2_report["rows"] if row["arm"] == v2_arm)
        self.set_partition(v2_failure, [list(range(v2_failure["sourceStrokeCount"]))])
        self.refresh_summaries(self.v2_report)
        v3_triple = next(row for row in self.v3_report["rows"] if row["arm"] == base.TRIPLE_ARM)
        self.set_partition(v3_triple, [list(range(v3_triple["sourceStrokeCount"]))])
        v3_triple["timings"] = dict(featureSeconds=0.012, inferenceAndPartitionSeconds=0.034)
        self.refresh_summaries(self.v3_report)
        harmed_arm = v2.arm_name(4, 32, 16)
        v4_failure = next(row for row in self.v4_report["rows"] if row["arm"] == harmed_arm)
        self.set_partition(v4_failure, [list(range(v4_failure["sourceStrokeCount"]))])
        self.refresh_summaries(self.v4_report)
        current_triple = next(row for row in self.v4_report["rows"] if row["candidateID"] == v3_triple["candidateID"])
        current_triple["timings"] = dict(featureSeconds=0.004, inferenceAndPartitionSeconds=0.006)

        result = self.preserved_compare()
        self.assertEqual(result["v4Targets"], 25 * 1552)
        self.assertEqual(len(result["v4Summaries"]), 25)
        self.assertEqual(len(result["comparisons"]), 14 + 8 + 25 + 25)
        expected_joins = {(f"swift-{policy}", arm) for policy in base.POLICIES for arm in base.ARMS}
        expected_joins.update(("learned-v1", arm) for arm in v2.V1_ARMS)
        expected_joins.update((baseline, arm) for baseline in ("learned-v2", "learned-v3")
                              for arm in v2.ARM_CARDINALITY)
        self.assertEqual({(row["baseline"], row["arm"]) for row in result["comparisons"]}, expected_joins)
        self.assertEqual(result["controlledWeightingComparison"], dict(baseline="learned-v3", current="learned-v4",
            baselineWeightingRule="cardinality-balanced-eligible-target", currentWeightingRule="equal-eligible-target"))
        statuses = {row["arm"]: row for row in result["armStatus"]}
        self.assertEqual(set(statuses), set(v2.ARM_CARDINALITY))
        self.assertEqual(sum(row["hasSwiftBaseline"] for row in statuses.values()), 7)
        self.assertEqual(sum(row["hasV1Baseline"] for row in statuses.values()), 8)
        self.assertTrue(all(row["hasV2Baseline"] and row["hasV3Baseline"] for row in statuses.values()))
        for arm, status in statuses.items():
            self.assertEqual(status["cardinality"], v2.ARM_CARDINALITY[arm])
            self.assertEqual(status["denominator"], 1552)
            self.assertEqual(status["status"], "matched-historical-cohort" if arm in v2.V1_ARMS
                             else "matched-v2-v3-only-no-Swift-or-v1-baseline")
        self.assertEqual(self.comparison(result, "learned-v1", base.TRIPLE_ARM)["counts"]["gainedCorrect"], 1)
        self.assertEqual(self.comparison(result, "learned-v2", v2_arm)["counts"]["gainedCorrect"], 1)
        triple_counts = self.comparison(result, "learned-v3", base.TRIPLE_ARM)["counts"]
        self.assertEqual(triple_counts["gainedCorrect"], 1)
        self.assertEqual(triple_counts["baselineFalseMergedTargets"], 1)
        harmed = self.comparison(result, "learned-v3", harmed_arm)["counts"]
        self.assertEqual(harmed["lostCorrect"], 1)
        self.assertEqual(harmed["v4FalseMergedTargets"], 1)
        self.assertEqual(harmed["v4FalseSplitTargets"], 0)
        for row in result["comparisons"]:
            counts = row["counts"]
            self.assertEqual(counts["denominator"], 1552)
            self.assertEqual(counts["v4Correct"], counts["gainedCorrect"] + counts["bothCorrect"])
            self.assertEqual(counts["baselineCorrect"], counts["lostCorrect"] + counts["bothCorrect"])
            self.assertEqual(sum(counts[key] for key in ("gainedCorrect", "lostCorrect", "bothCorrect", "bothIncorrect")), 1552)
            self.assertEqual(set(row["byWriter"]), set(self.v4_report["developmentWriters"]))
            self.assertTrue(all(values["denominator"] == 194 for values in row["byWriter"].values()))
            for key, value in counts.items():
                self.assertEqual(sum(values[key] for values in row["byWriter"].values()), value)
        for baseline, previous in (("learned-v1", v1_triple), ("learned-v3", v3_triple)):
            joined = next(row for row in result["rows"] if row["baseline"] == baseline
                          and row["arm"] == base.TRIPLE_ARM and tuple(row["sourceIDs"]) == tuple(previous["sourceIDs"]))
            self.assertEqual(joined["baselineEdgeConfusion"], previous["edgeConfusion"])
            self.assertEqual(joined["baselineTimings"], previous["timings"])
            self.assertEqual(joined["v4EdgeConfusion"], current_triple["edgeConfusion"])
            self.assertEqual(joined["v4Timings"], current_triple["timings"])
        self.assertEqual([row["candidateID"] for row in result["newContextFailures"]], [v4_failure["candidateID"]])
        self.assertTrue(result["swiftIntegrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.assertFalse(result["swiftIntegrationGate"]["productionEligible"])

    def test_genuine_v4_exact27_path_contract_and_every_required_binding_fail_closed(self):
        before = self.report_digests()
        self.assertEqual(v4.V4_VERSION, "public-stroke-affinity-experiment-v4")
        self.assertEqual(v4.V4_PROTOCOL, "docs/personal-learned-stroke-ownership-v4-protocol-2026-09-30.md")
        expected_code = {
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
            "recognition_ml/ichart_recognition_ml/features.py",
            "recognition_ml/ichart_recognition_ml/schema.py",
            "recognition_ml/tests/test_stroke_affinity.py",
            "recognition_ml/tests/test_stroke_affinity_experiment.py",
            "recognition_ml/tests/test_stroke_affinity_baseline.py",
            "recognition_ml/tests/test_stroke_affinity_v2.py",
            "recognition_ml/tests/test_stroke_affinity_v2_experiment.py",
            "recognition_ml/tests/test_stroke_affinity_v2_baseline.py",
            "recognition_ml/tests/test_stroke_affinity_v3_experiment.py",
            "recognition_ml/tests/test_stroke_affinity_v3_baseline.py",
            "recognition_ml/tests/test_stroke_affinity_v4_experiment.py",
            "recognition_ml/tests/test_stroke_affinity_v4_baseline.py",
            "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md",
            "docs/personal-learned-stroke-ownership-v2-protocol-2026-09-30.md",
            "docs/personal-learned-stroke-ownership-v3-protocol-2026-09-30.md",
            "docs/personal-learned-stroke-ownership-v4-protocol-2026-09-30.md",
        }
        self.assertEqual(len(expected_code), 27)
        self.assertEqual(v4.V4_FILES, expected_code)
        self.assertEqual(v4.V4_FILES, v3.V3_FILES | {
            v4.V4_PROTOCOL, "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v4_baseline.py",
            "recognition_ml/tests/test_stroke_affinity_v4_experiment.py",
            "recognition_ml/tests/test_stroke_affinity_v4_baseline.py"})
        with self.assertRaises(ValueError):
            v3.validate_evaluation(self.v4_report, self.samples, self.root)
        with self.assertRaises(ValueError):
            v2.validate_evaluation(self.v4_report, self.samples, self.root, v2=True)
        for historical in (self.v1_report, self.v2_report, self.v3_report):
            with self.subTest(historical_version=historical["version"]):
                previous = historical["version"]
                historical["version"] = v4.V4_VERSION
                try:
                    with self.assertRaises(ValueError):
                        self.compare()
                finally:
                    historical["version"] = previous
        for field, replacement in (("version", v3.V3_VERSION), ("featureSchema", "stroke-affinity-pair-local-v2"),
                ("featureCount", 201), ("protocolSHA256", "0" * 64), ("sourceSHA256", "0" * 64),
                ("weightsSHA256", "not-a-digest"), ("trainingReportSHA256", "not-a-digest"),
                ("sourceUnchanged", False), ("reservedWritersEvaluated", True), ("privateInkUsed", True)):
            with self.subTest(field=field):
                previous = self.v4_report[field]
                self.v4_report[field] = replacement
                try:
                    self.invalid_v4()
                finally:
                    self.v4_report[field] = previous
        for required in sorted(expected_code):
            with self.subTest(omitted_required_path=required):
                omitted = self.v4_report["codeSHA256"].pop(required)
                try:
                    self.invalid_v4()
                finally:
                    self.v4_report["codeSHA256"][required] = omitted
        path = self.root / "recognition_ml/tests/test_stroke_affinity_v4_baseline.py"
        contents = path.read_bytes()
        try:
            path.write_bytes(b"changed toy V4 test source")
            self.invalid_v4()
        finally:
            path.write_bytes(contents)
        self.assertEqual(self.report_digests(), before)

    def test_missing_duplicate_reversed_wrong_owner_role_writer_cardinality_and_arm_rows_fail(self):
        before = self.report_digests()
        removed = self.v4_report["rows"].pop()
        self.invalid_v4()
        self.v4_report["rows"].append(removed)
        self.v4_report["rows"].append(self.v4_report["rows"][0])
        self.invalid_v4()
        self.v4_report["rows"].pop()
        row = next(row for row in self.v4_report["rows"] if row["arm"] == base.TRIPLE_ARM)
        for field, replacement in (("sourceIDs", list(reversed(row["sourceIDs"]))),
                ("expectedOwners", list(reversed(row["expectedOwners"]))), ("role", "training"),
                ("writer", "tst_UPV_W00"), ("cardinality", 5), ("arm", "best-context")):
            with self.subTest(field=field):
                previous = row[field]
                row[field] = replacement
                try:
                    self.invalid_v4()
                finally:
                    row[field] = previous
        self.assertEqual(self.report_digests(), before)

    def test_summaries_edge_confusion_timings_and_new_context_index_defects_cannot_be_hidden(self):
        before = self.report_digests()
        summary = self.v4_report["summaries"][0]
        writer = next(iter(summary["byWriter"]))
        for counts in (summary["counts"], summary["byWriter"][writer]):
            counts["targets"] -= 1
            self.invalid_v4()
            counts["targets"] += 1
        removed = self.v4_report["summaries"].pop()
        self.invalid_v4()
        self.v4_report["summaries"].append(removed)
        self.v4_report["summaries"].append(summary)
        self.invalid_v4()
        self.v4_report["summaries"].pop()
        row = self.v4_report["rows"][0]
        previous = row["timings"]
        for replacement in ({}, dict(featureSeconds=-1, inferenceAndPartitionSeconds=0),
                dict(featureSeconds=float("nan"), inferenceAndPartitionSeconds=0),
                dict(featureSeconds=True, inferenceAndPartitionSeconds=0)):
            row["timings"] = replacement
            self.invalid_v4()
        row["timings"] = previous
        row["edgeConfusion"]["edgeTruePositive"] += 1
        self.invalid_v4()
        row["edgeConfusion"]["edgeTruePositive"] -= 1
        self.assertEqual(self.report_digests(), before)
        five = next(row for row in self.v4_report["rows"] if row["cardinality"] == 5)
        groups = [list(owner) for owner in five["expectedOwners"]]
        groups[0].append(0)
        self.set_partition(five, groups)
        self.refresh_summaries(self.v4_report)
        result = self.preserved_compare()
        self.assertIn("source-index-defects", result["swiftIntegrationGate"]["violations"])
        self.assertFalse(result["swiftIntegrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.assertEqual([row["candidateID"] for row in result["newContextFailures"]], [five["candidateID"]])

    def test_root_far_pair_merge_gate_and_all17_v2_v3_only_context_failures_are_retained(self):
        root = next(row for row in self.v4_report["rows"] if row["arm"] == "single32"
                    and self.sources[row["sourceIDs"][0]].label == "A")
        self.set_partition(root, [[0], [1]])
        far = next(row for row in self.v4_report["rows"] if row["arm"] == "second32-gap16")
        self.set_partition(far, [list(range(far["sourceStrokeCount"]))])
        new_arms = set(v2.ARM_CARDINALITY) - v2.V1_ARMS
        failures = []
        for arm in sorted(new_arms):
            row = next(row for row in self.v4_report["rows"] if row["arm"] == arm)
            self.set_partition(row, [list(range(row["sourceStrokeCount"]))])
            failures.append(row)
        self.refresh_summaries(self.v4_report)
        result = self.preserved_compare()
        gate = result["swiftIntegrationGate"]
        self.assertFalse(gate["eligibleForComparisonOnlyIntegration"])
        self.assertEqual(gate["isolatedRootBaselineCorrectHarms"], 1)
        self.assertIn("new-isolated-A-G-baseline-correct-harms", gate["violations"])
        self.assertIn("higher-false-merged-pair-count:second32-gap16", gate["violations"])
        self.assertIn("lower-exact-arm:single32", gate["violations"])
        self.assertIn("lower-exact-writer:single32/" + root["writer"], gate["violations"])
        self.assertEqual(len(result["newContextFailures"]), 17)
        self.assertEqual({row["candidateID"] for row in result["newContextFailures"]},
                         {row["candidateID"] for row in failures})
        self.assertEqual({row["arm"] for row in result["newContextFailures"]}, new_arms)
        for row in result["newContextFailures"]:
            self.assertEqual(row["cardinality"], v2.ARM_CARDINALITY[row["arm"]])
            for historical in ("learned-v2", "learned-v3"):
                self.assertEqual(self.comparison(result, historical, row["arm"])["counts"]["lostCorrect"], 1)
        root_counts = self.comparison(result, "swift-preserveOriginalInk", "single32")["counts"]
        self.assertEqual(root_counts["v4FalseSplitTargets"], 1)
        self.assertEqual(root_counts["v4Correct"], 1551)
        far_counts = self.comparison(result, "swift-preserveOriginalInk", "second32-gap16")["counts"]
        self.assertEqual(far_counts["v4FalseMergedTargets"], 1)


if __name__ == "__main__":
    unittest.main()
