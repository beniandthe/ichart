"""Fixed toy report cohorts only: no model, public predictions or private ink."""
import json
from pathlib import Path
import tempfile
import unittest

import test_stroke_affinity_v2_baseline as v2_fixtures
from ichart_recognition_ml.research import stroke_affinity_baseline as base
from ichart_recognition_ml.research import stroke_affinity_v2_baseline as v2
from ichart_recognition_ml.research import stroke_affinity_v3_baseline as v3


class StrokeAffinityV3BaselineTests(unittest.TestCase):
    # Reuse immutable V2 fixture helpers without inheriting its test methods.
    @classmethod
    def setUpClass(cls):
        v2_fixtures.StrokeAffinityV2BaselineTests.setUpClass.__func__(cls)

    swift_counts = staticmethod(v2_fixtures.StrokeAffinityV2BaselineTests.swift_counts)
    set_partition = staticmethod(v2_fixtures.StrokeAffinityV2BaselineTests.set_partition)
    make_swift = v2_fixtures.StrokeAffinityV2BaselineTests.make_swift
    make_evaluation = v2_fixtures.StrokeAffinityV2BaselineTests.make_evaluation
    refresh_summaries = v2_fixtures.StrokeAffinityV2BaselineTests.refresh_summaries

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.code = {}
        for name in base.SWIFT_FILES | {base.PAIR_FILE} | v2.V2_FILES | v3.V3_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("code fixture:" + name).encode())
            self.code[name] = base.digest(path.read_bytes())
        self.isolated, self.paired = self.make_swift(False), self.make_swift(True)
        self.v1_report, self.v2_report = self.make_evaluation(False), self.make_evaluation(True)
        self.v3_report = self.make_evaluation(True)
        self.v3_report.update(version=v3.V3_VERSION, featureSchema="stroke-affinity-context-v1", featureCount=202,
            protocolSHA256=self.code[v3.V3_PROTOCOL],
            codeSHA256={name: self.code[name] for name in v3.V3_FILES})

    def compare(self):
        return v3.compare_reports(self.records, self.isolated, self.paired,
                                  self.v1_report, self.v2_report, self.v3_report, self.root)

    def report_digests(self):
        return tuple(base.digest(json.dumps(report, sort_keys=True).encode()) for report in
                     (self.isolated, self.paired, self.v1_report, self.v2_report, self.v3_report))

    def preserved_compare(self):
        before = self.report_digests()
        try:
            return self.compare()
        finally:
            self.assertEqual(self.report_digests(), before, "A join must not rewrite any source report")

    def invalid_v3(self):
        with self.assertRaises(ValueError):
            v3.validate_evaluation(self.v3_report, self.samples, self.root)

    @staticmethod
    def comparison(result, baseline, arm):
        return next(row for row in result["comparisons"] if row["baseline"] == baseline and row["arm"] == arm)

    def test_exact25_arm_v2_join_retains_triple_gains_harms_and_source_reports(self):
        v1_triple = next(row for row in self.v1_report["rows"] if row["arm"] == base.TRIPLE_ARM)
        self.set_partition(v1_triple, [list(range(v1_triple["sourceStrokeCount"]))])
        self.refresh_summaries(self.v1_report)
        gained_arm = v2.arm_name(5, 16, 8)
        v2_failure = next(row for row in self.v2_report["rows"] if row["arm"] == gained_arm)
        self.set_partition(v2_failure, [list(range(v2_failure["sourceStrokeCount"]))])
        self.refresh_summaries(self.v2_report)
        harmed_arm = v2.arm_name(4, 32, 16)
        v3_failure = next(row for row in self.v3_report["rows"] if row["arm"] == harmed_arm)
        self.set_partition(v3_failure, [list(range(v3_failure["sourceStrokeCount"]))])
        self.refresh_summaries(self.v3_report)

        result = self.preserved_compare()
        self.assertEqual(result["v3Targets"], 25 * 1552)
        self.assertEqual(len(result["v3Summaries"]), 25)
        self.assertEqual(len(result["comparisons"]), 14 + 8 + 25)
        self.assertEqual(result["controlledFeatureFamilyComparison"], dict(baseline="learned-v2", current="learned-v3",
            baselineFeatureSchema="stroke-affinity-pair-local-v2", currentFeatureSchema="stroke-affinity-context-v1"))
        statuses = {row["arm"]: row for row in result["armStatus"]}
        self.assertEqual(set(statuses), set(v2.ARM_CARDINALITY))
        self.assertEqual(sum(row["hasSwiftBaseline"] for row in statuses.values()), 7)
        self.assertEqual(sum(row["hasV1Baseline"] for row in statuses.values()), 8)
        self.assertTrue(all(row["hasV2Baseline"] for row in statuses.values()))
        for arm, status in statuses.items():
            self.assertEqual(status["cardinality"], v2.ARM_CARDINALITY[arm])
            self.assertEqual(status["denominator"], 1552)
            self.assertEqual(status["status"], "matched-historical-cohort" if arm in v2.V1_ARMS
                             else "matched-v2-only-no-Swift-or-v1-baseline")
        self.assertEqual(self.comparison(result, "learned-v1", base.TRIPLE_ARM)["counts"]["gainedCorrect"], 1)
        self.assertEqual(self.comparison(result, "learned-v1", base.TRIPLE_ARM)["counts"]["baselineFalseMergedTargets"], 1)
        self.assertEqual(self.comparison(result, "learned-v2", gained_arm)["counts"]["gainedCorrect"], 1)
        harmed = self.comparison(result, "learned-v2", harmed_arm)["counts"]
        self.assertEqual(harmed["lostCorrect"], 1)
        self.assertEqual(harmed["v3FalseMergedTargets"], 1)
        self.assertEqual(harmed["v3FalseSplitTargets"], 0)
        for row in result["comparisons"]:
            counts = row["counts"]
            self.assertEqual(counts["denominator"], 1552)
            self.assertEqual(counts["v3Correct"], counts["gainedCorrect"] + counts["bothCorrect"])
            self.assertEqual(counts["baselineCorrect"], counts["lostCorrect"] + counts["bothCorrect"])
            self.assertEqual(sum(counts[key] for key in ("gainedCorrect", "lostCorrect", "bothCorrect", "bothIncorrect")), 1552)
            self.assertEqual(set(row["byWriter"]), set(self.v3_report["developmentWriters"]))
            self.assertTrue(all(values["denominator"] == 194 for values in row["byWriter"].values()))
        joined = next(row for row in result["rows"] if row["baseline"] == "learned-v1"
                      and row["arm"] == base.TRIPLE_ARM and tuple(row["sourceIDs"]) == tuple(v1_triple["sourceIDs"]))
        self.assertEqual(joined["baselineEdgeConfusion"], v1_triple["edgeConfusion"])
        self.assertEqual(joined["baselineTimings"], v1_triple["timings"])
        current = next(row for row in self.v3_report["rows"] if row["candidateID"] == v1_triple["candidateID"])
        self.assertEqual(joined["v3EdgeConfusion"], current["edgeConfusion"])
        self.assertEqual(joined["v3Timings"], current["timings"])
        self.assertEqual([row["candidateID"] for row in result["newContextFailures"]], [v3_failure["candidateID"]])
        self.assertTrue(result["swiftIntegrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.assertFalse(result["swiftIntegrationGate"]["productionEligible"])

    def test_genuine_v3_cannot_masquerade_as_v2_or_lose_source_protocol_schema_bindings(self):
        before = self.report_digests()
        self.assertEqual(v3.V3_VERSION, "public-stroke-affinity-experiment-v3")
        self.assertEqual(v3.V3_PROTOCOL, "docs/personal-learned-stroke-ownership-v3-protocol-2026-09-30.md")
        # Explicit current harness code_identity contract, without importing a model.
        expected_code = {
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2_baseline.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_experiment.py",
            "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v3_baseline.py",
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
            "docs/personal-learned-stroke-ownership-protocol-2026-09-30.md",
            "docs/personal-learned-stroke-ownership-v2-protocol-2026-09-30.md",
            "docs/personal-learned-stroke-ownership-v3-protocol-2026-09-30.md",
        }
        self.assertEqual(v3.V3_FILES, expected_code)
        own_test = "recognition_ml/tests/test_stroke_affinity_v3_baseline.py"
        self.assertIn(own_test, v3.V3_FILES)
        with self.assertRaises(ValueError):
            v2.validate_evaluation(self.v3_report, self.samples, self.root, v2=True)
        for field, replacement in (("version", v2.V2_VERSION), ("featureSchema", "stroke-affinity-pair-local-v2"),
                ("featureCount", 201), ("protocolSHA256", "0" * 64), ("sourceSHA256", "0" * 64),
                ("weightsSHA256", "not-a-digest"), ("trainingReportSHA256", "not-a-digest"),
                ("sourceUnchanged", False), ("reservedWritersEvaluated", True), ("privateInkUsed", True)):
            with self.subTest(field=field):
                previous = self.v3_report[field]
                self.v3_report[field] = replacement
                self.invalid_v3()
                self.v3_report[field] = previous
        for required in sorted(expected_code):
            with self.subTest(omitted_required_path=required):
                omitted = self.v3_report["codeSHA256"].pop(required)
                try:
                    self.invalid_v3()
                finally:
                    self.v3_report["codeSHA256"][required] = omitted
        path = self.root / own_test
        contents = path.read_bytes()
        try:
            path.write_bytes(b"changed toy test source")
            self.invalid_v3()
        finally:
            path.write_bytes(contents)
        self.assertEqual(self.report_digests(), before)

    def test_missing_duplicate_reversed_wrong_owner_role_writer_cardinality_and_arm_rows_fail(self):
        before = self.report_digests()
        removed = self.v3_report["rows"].pop()
        self.invalid_v3()
        self.v3_report["rows"].append(removed)
        self.v3_report["rows"].append(self.v3_report["rows"][0])
        self.invalid_v3()
        self.v3_report["rows"].pop()
        row = next(row for row in self.v3_report["rows"] if row["arm"] == base.TRIPLE_ARM)
        for field, replacement in (("sourceIDs", list(reversed(row["sourceIDs"]))),
                ("expectedOwners", list(reversed(row["expectedOwners"]))), ("role", "training"),
                ("writer", "tst_UPV_W00"), ("cardinality", 5), ("arm", "best-context")):
            with self.subTest(field=field):
                previous = row[field]
                row[field] = replacement
                self.invalid_v3()
                row[field] = previous
        self.assertEqual(self.report_digests(), before)

    def test_summaries_edge_confusion_timings_and_new_context_index_defects_cannot_be_hidden(self):
        before = self.report_digests()
        summary = self.v3_report["summaries"][0]
        writer = next(iter(summary["byWriter"]))
        for counts in (summary["counts"], summary["byWriter"][writer]):
            counts["targets"] -= 1
            self.invalid_v3()
            counts["targets"] += 1
        removed = self.v3_report["summaries"].pop()
        self.invalid_v3()
        self.v3_report["summaries"].append(removed)
        self.v3_report["summaries"].append(summary)
        self.invalid_v3()
        self.v3_report["summaries"].pop()
        row = self.v3_report["rows"][0]
        previous = row["timings"]
        for replacement in ({}, dict(featureSeconds=-1, inferenceAndPartitionSeconds=0),
                dict(featureSeconds=float("nan"), inferenceAndPartitionSeconds=0),
                dict(featureSeconds=True, inferenceAndPartitionSeconds=0)):
            row["timings"] = replacement
            self.invalid_v3()
        row["timings"] = previous
        row["edgeConfusion"]["edgeTruePositive"] += 1
        self.invalid_v3()
        row["edgeConfusion"]["edgeTruePositive"] -= 1
        self.assertEqual(self.report_digests(), before)
        five = next(row for row in self.v3_report["rows"] if row["cardinality"] == 5)
        groups = [list(owner) for owner in five["expectedOwners"]]
        groups[0].append(0)
        self.set_partition(five, groups)
        self.refresh_summaries(self.v3_report)
        result = self.preserved_compare()
        self.assertIn("source-index-defects", result["swiftIntegrationGate"]["violations"])
        self.assertFalse(result["swiftIntegrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.assertEqual([row["candidateID"] for row in result["newContextFailures"]], [five["candidateID"]])

    def test_root_far_pair_merge_gate_and_all17_v2_only_context_failures_are_retained(self):
        root = next(row for row in self.v3_report["rows"] if row["arm"] == "single32"
                    and self.sources[row["sourceIDs"][0]].label == "A")
        self.set_partition(root, [[0], [1]])
        far = next(row for row in self.v3_report["rows"] if row["arm"] == "second32-gap16")
        self.set_partition(far, [list(range(far["sourceStrokeCount"]))])
        new_arms = set(v2.ARM_CARDINALITY) - v2.V1_ARMS
        failures = []
        for arm in sorted(new_arms):
            row = next(row for row in self.v3_report["rows"] if row["arm"] == arm)
            self.set_partition(row, [list(range(row["sourceStrokeCount"]))])
            failures.append(row)
        self.refresh_summaries(self.v3_report)
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
            self.assertEqual(self.comparison(result, "learned-v2", row["arm"])["counts"]["lostCorrect"], 1)
        root_counts = self.comparison(result, "swift-preserveOriginalInk", "single32")["counts"]
        self.assertEqual(root_counts["v3FalseSplitTargets"], 1)
        self.assertEqual(root_counts["v3Correct"], 1551)
        far_counts = self.comparison(result, "swift-preserveOriginalInk", "second32-gap16")["counts"]
        self.assertEqual(far_counts["v3FalseMergedTargets"], 1)


if __name__ == "__main__":
    unittest.main()
