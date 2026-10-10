"""Full fixed toy cohorts, no learned model, public predictions or private ink."""
from collections import Counter, defaultdict
import tempfile
import unittest
from pathlib import Path

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.research import stroke_affinity_baseline as base
from ichart_recognition_ml.research import stroke_affinity_v2_baseline as v2
from ichart_recognition_ml.research.uji_personal import Sample, SOURCE_SHA256


class StrokeAffinityV2BaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        stroke = InkStroke((InkPoint(0, 0), InkPoint(10, 10)))
        writers = tuple(f"trn_UJI_W{i:02d}" for i in range(40)) + tuple(f"tst_UPV_W{i:02d}" for i in range(20))
        cls.records = tuple(Sample(writer, session, chr(label), (stroke, stroke)) for writer in writers
                            for session in (1, 2) for label in range(33, 130))
        cls.samples = base.development_samples(cls.records)
        cls.contexts = {count: v2.expected_contexts(cls.samples, count) for count in range(1, 6)}
        cls.sources = {sample.identity: sample for sample in cls.samples}

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.code = {}
        for name in base.SWIFT_FILES | {base.PAIR_FILE} | v2.V2_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("code fixture:" + name).encode())
            self.code[name] = base.digest(path.read_bytes())
        self.isolated, self.paired = self.make_swift(False), self.make_swift(True)
        self.old, self.new = self.make_evaluation(False), self.make_evaluation(True)

    @staticmethod
    def swift_counts(paired, count, arm):
        if paired:
            return dict(pairs=count, groupCount=2 * count, twoGroupCount=count, exactTwoOwnerMatches=count,
                falseMergedGroups=0, falseMergedPairs=0, falseSplitOwners=0, falseSplitPairs=0,
                missingIndexes=0, duplicateIndexes=0, invalidIndexes=0, exactIndexPartitions=count,
                modelInputMismatchGroups=0, exactOwnersAndModelInputs=count, zeroExtentCharacters=0)
        return dict(records=count, groupCount=count, oneCompleteGroup=count, splitRecords=0, emptyRecords=0,
            missingIndexes=0, duplicateIndexes=0, invalidIndexes=0, exactIndexPartition=count,
            modelInputMismatchGroups=0, completeExactModelInput=count, rasterChecks=count if arm == "points32" else 0,
            rasterMismatches=0, rasterEncodingFailures=0, zeroExtent=0)

    def make_swift(self, paired):
        report = dict(version="public-adjacent-character-ownership-v1" if paired else "public-isolated-glyph-ownership-v1",
            sourceSHA256=SOURCE_SHA256, sourceRecords=11640, evaluatedRecords=1552, evaluatedWriters=8,
            reservedWritersNotGroupedOrRasterized=20, codeSHA256={name: self.code[name] for name in
                base.SWIFT_FILES | ({base.PAIR_FILE} if paired else set())}, summaries=[])
        if paired:
            report.update(pairs=1552, firstDimension=32, bottomAlignment=32, rasterChecks=0,
                          classificationAndPersonalizationRuns=0, failedPairs=[])
        else:
            report.update(labels=97, sessions=[1, 2], failedRecords=[])
        for policy in base.POLICIES:
            for arm in base.PAIR_ARMS if paired else ("raw", "points24", "points32", "points48"):
                summary_arm = arm
                if paired:
                    dimension, gap = arm.removeprefix("second").split("-gap")
                    summary_arm = dict(secondDimension=int(dimension), gap=float(gap))
                report["summaries"].append(dict(policy=policy, arm=summary_arm, counts=self.swift_counts(paired, 1552, arm),
                    byWriter={writer: self.swift_counts(paired, 194, arm) for writer in sorted({sample.writer for sample in self.samples})}))
        return report

    @staticmethod
    def set_partition(row, groups):
        expected = base.Expected(row["writer"], row["session"], tuple(tuple(owner) for owner in row["expectedOwners"]), 0)
        stats = base.partition_stats(groups, expected)
        row.update(groups=groups, exactOwnerMatch=stats["matchesExpectedGroups"], metrics=dict(
            exactPartition=stats["matchesExpectedGroups"], expectedOwnerCount=len(expected.owners),
            **{name: stats[name] for name in ("groupCount", "falseMergedGroups", "falseSplitOwners",
                "missingIndexes", "duplicateIndexes", "invalidIndexes")}))
        confusion = dict.fromkeys(v2.EDGE_FIELDS, 0)
        owner_sets, group_sets = list(map(set, expected.owners)), list(map(set, groups))
        for a in range(row["sourceStrokeCount"]):
            for b in range(a + 1, row["sourceStrokeCount"]):
                truth = any(a in owner and b in owner for owner in owner_sets)
                prediction = any(a in group and b in group for group in group_sets)
                confusion["edge" + ("True" if truth == prediction else "False") + ("Positive" if prediction else "Negative")] += 1
        row["edgeConfusion"] = confusion

    def make_evaluation(self, new):
        protocol = v2.V2_PROTOCOL if new else v2.V1_PROTOCOL
        report = dict(version=v2.V2_VERSION if new else v2.V1_VERSION, sourceSHA256=SOURCE_SHA256,
            sourceUnchanged=True, developmentWriters=sorted({sample.writer for sample in self.samples}),
            reservedWritersEvaluated=False, privateInkUsed=False, productionEligible=False,
            protocolSHA256=self.code[protocol], weightsSHA256="1" * 64, trainingReportSHA256="2" * 64,
            trajectoryCopyAudit={"fixtureOnly": True}, codeSHA256={name: self.code[name] for name in
                (v2.V2_FILES if new else base.LEARNED_FILES)}, rows=[])
        if new:
            report.update(featureSchema="stroke-affinity-pair-local-v2", featureCount=202)
        for arm in sorted(v2.ARM_CARDINALITY if new else v2.V1_ARMS):
            for ids, expected in self.contexts[v2.ARM_CARDINALITY[arm]].items():
                owners = [list(owner) for owner in expected.owners]
                row = dict(arm=arm, sourceIDs=list(ids), expectedOwners=owners, candidateID="+".join(ids) + "/" + arm,
                    writer=expected.writer, session=expected.session, role="development",
                    sourceStrokeCount=sum(map(len, expected.owners)),
                    timings={"featureSeconds": 0.0, "inferenceAndPartitionSeconds": 0.0})
                if new:
                    row["cardinality"] = len(ids)
                self.set_partition(row, owners)
                report["rows"].append(row)
        report["targets"] = len(report["rows"])
        self.refresh_summaries(report)
        return report

    def refresh_summaries(self, report):
        totals, writers = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter))
        for row in report["rows"]:
            metrics = row["metrics"]
            counts = dict(targets=1, exactPartitions=int(row["exactOwnerMatch"]),
                singletonTargets=int(row["sourceStrokeCount"] == 1), sourceStrokes=row["sourceStrokeCount"],
                sourcePoints=sum(len(stroke.points) for identity in row["sourceIDs"] for stroke in self.sources[identity].strokes),
                zeroExtentCharacters=0, falseMergedTargets=int(metrics["falseMergedGroups"] > 0),
                falseSplitTargets=int(metrics["falseSplitOwners"] > 0), **row["edgeConfusion"],
                **{name: metrics[name] for name in ("falseMergedGroups", "falseSplitOwners", "missingIndexes", "duplicateIndexes", "invalidIndexes")})
            totals[row["arm"]].update(counts); writers[row["arm"]][row["writer"]].update(counts)
        report["summaries"] = [dict(arm=arm, counts=dict(values), byWriter={writer: dict(counts)
            for writer, counts in writers[arm].items()}) for arm, values in totals.items()]

    def compare(self):
        return v2.compare_reports(self.records, self.isolated, self.paired, self.old, self.new, self.root)

    def test_all25_arms_reconciled_with_exact_old_triple_join_and17_explicit_new_arms(self):
        old_triple = next(row for row in self.old["rows"] if row["arm"] == base.TRIPLE_ARM)
        self.set_partition(old_triple, [list(range(old_triple["sourceStrokeCount"]))])
        self.refresh_summaries(self.old)
        result = self.compare()
        self.assertEqual(result["v2Targets"], 25 * 1552)
        self.assertEqual(len(result["v2Summaries"]), 25)
        self.assertEqual(len(result["comparisons"]), 14 + 8)
        self.assertEqual(sum(row["status"] == "new-no-historical-baseline" for row in result["armStatus"]), 17)
        triple = next(row for row in result["comparisons"] if row["baseline"] == "learned-v1" and row["arm"] == base.TRIPLE_ARM)
        self.assertEqual(triple["counts"]["gainedCorrect"], 1)
        self.assertEqual(triple["counts"]["baselineFalseMergedTargets"], 1)
        self.assertTrue(result["swiftIntegrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.assertFalse(result["swiftIntegrationGate"]["productionEligible"])
        self.assertTrue(all(row["counts"]["denominator"] == 1552 for row in result["comparisons"]))

    def test_unchanged_root_and_far_pair_merge_gates_and_explicit_new_context_failures(self):
        root = next(row for row in self.new["rows"] if row["arm"] == "single32" and self.sources[row["sourceIDs"][0]].label == "A")
        self.set_partition(root, [[0], [1]])
        far = next(row for row in self.new["rows"] if row["arm"] == "second32-gap16")
        self.set_partition(far, [list(range(far["sourceStrokeCount"]))])
        five = next(row for row in self.new["rows"] if row["arm"] == v2.arm_name(5, 16, 8))
        self.set_partition(five, [list(range(five["sourceStrokeCount"]))])
        self.refresh_summaries(self.new)
        result = self.compare()
        gate = result["swiftIntegrationGate"]
        self.assertFalse(gate["eligibleForComparisonOnlyIntegration"])
        self.assertEqual(gate["isolatedRootBaselineCorrectHarms"], 1)
        self.assertIn("new-isolated-A-G-baseline-correct-harms", gate["violations"])
        self.assertIn("higher-false-merged-pair-count:second32-gap16", gate["violations"])
        self.assertEqual(len(result["newContextFailures"]), 1)
        self.assertEqual(result["newContextFailures"][0]["candidateID"], five["candidateID"])

    def test_missing_duplicate_reversed_wrong_owner_role_writer_and_arm_rows_fail(self):
        removed = self.new["rows"].pop()
        with self.assertRaises(ValueError): self.compare()
        self.new["rows"].append(removed)
        self.new["rows"].append(self.new["rows"][0])
        with self.assertRaises(ValueError): self.compare()
        self.new["rows"].pop()
        row = next(row for row in self.new["rows"] if row["arm"] == base.TRIPLE_ARM)
        for field, replacement in (("sourceIDs", list(reversed(row["sourceIDs"]))), ("expectedOwners", list(reversed(row["expectedOwners"]))),
                ("role", "training"), ("writer", "tst_UPV_W00"), ("arm", "best-context")):
            previous = row[field]
            row[field] = replacement
            with self.assertRaises(ValueError): self.compare()
            row[field] = previous

    def test_source_protocol_model_and_current_code_bindings_fail_closed(self):
        for field, replacement in (("sourceSHA256", "0" * 64), ("protocolSHA256", "0" * 64),
                ("weightsSHA256", "not-a-digest"), ("featureSchema", "stroke-affinity-context-v1"), ("sourceUnchanged", False)):
            previous = self.new[field]
            self.new[field] = replacement
            with self.assertRaises(ValueError): self.compare()
            self.new[field] = previous
        path = self.root / "recognition_ml/ichart_recognition_ml/research/stroke_affinity_v2.py"
        path.write_bytes(b"changed code")
        with self.assertRaises(ValueError): self.compare()

    def test_summary_edge_confusion_and_new_context_source_defects_cannot_be_hidden(self):
        summary = self.new["summaries"][0]
        summary["counts"]["targets"] -= 1
        with self.assertRaises(ValueError): self.compare()
        summary["counts"]["targets"] += 1
        row = self.new["rows"][0]
        previous_timings = row["timings"]
        row["timings"] = {}
        with self.assertRaises(ValueError): self.compare()
        row["timings"] = previous_timings
        row["edgeConfusion"]["edgeTruePositive"] += 1
        with self.assertRaises(ValueError): self.compare()
        row["edgeConfusion"]["edgeTruePositive"] -= 1
        five = next(row for row in self.new["rows"] if row["cardinality"] == 5)
        duplicate_groups = [list(owner) for owner in five["expectedOwners"]]
        duplicate_groups[0].append(0)
        self.set_partition(five, duplicate_groups)
        self.refresh_summaries(self.new)
        result = self.compare()
        self.assertIn("source-index-defects", result["swiftIntegrationGate"]["violations"])
        self.assertEqual(len(result["newContextFailures"]), 1)


if __name__ == "__main__":
    unittest.main()
