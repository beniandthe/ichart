"""Synthetic full-cohort fixtures; no public model or private ink is loaded."""
from collections import Counter, defaultdict
from copy import deepcopy
import tempfile
import unittest
from pathlib import Path

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.research import stroke_affinity_baseline as baseline
from ichart_recognition_ml.research.uji_personal import Sample, SOURCE_SHA256


class StrokeAffinityBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        stroke = InkStroke((InkPoint(0, 0), InkPoint(10, 10)))
        writers = tuple(f"trn_UJI_W{i:02d}" for i in range(40)) + tuple(f"tst_UPV_W{i:02d}" for i in range(20))
        cls.records = tuple(Sample(writer, session, chr(label), (stroke, stroke)) for writer in writers
                            for session in (1, 2) for label in range(33, 130))
        cls.samples = baseline.development_samples(cls.records)
        cls.writers = sorted({sample.writer for sample in cls.samples})

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.code = {}
        for name in baseline.SWIFT_FILES | {baseline.PAIR_FILE} | baseline.LEARNED_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("source fixture:" + name).encode())
            self.code[name] = baseline.digest(path.read_bytes())
        self.isolated = self.make_baseline(paired=False)
        self.paired = self.make_baseline(paired=True)
        self.evaluation = self.make_evaluation()
        self.refresh_evaluation_summaries()

    @staticmethod
    def counts(paired, count, arm):
        if paired:
            return dict(pairs=count, groupCount=2 * count, twoGroupCount=count, exactTwoOwnerMatches=count,
                falseMergedGroups=0, falseMergedPairs=0, falseSplitOwners=0, falseSplitPairs=0,
                missingIndexes=0, duplicateIndexes=0, invalidIndexes=0, exactIndexPartitions=count,
                modelInputMismatchGroups=0, exactOwnersAndModelInputs=count, zeroExtentCharacters=0)
        return dict(records=count, groupCount=count, oneCompleteGroup=count, splitRecords=0, emptyRecords=0,
            missingIndexes=0, duplicateIndexes=0, invalidIndexes=0, exactIndexPartition=count,
            modelInputMismatchGroups=0, completeExactModelInput=count, rasterChecks=count if arm == "points32" else 0,
            rasterMismatches=0, rasterEncodingFailures=0, zeroExtent=0)

    def make_baseline(self, *, paired):
        report = dict(version="public-adjacent-character-ownership-v1" if paired else "public-isolated-glyph-ownership-v1",
            sourceSHA256=SOURCE_SHA256, sourceRecords=11640, evaluatedRecords=1552, evaluatedWriters=8,
            reservedWritersNotGroupedOrRasterized=20, codeSHA256={name: self.code[name] for name in
                baseline.SWIFT_FILES | ({baseline.PAIR_FILE} if paired else set())}, summaries=[])
        if paired:
            report.update(pairs=1552, firstDimension=32, bottomAlignment=32, rasterChecks=0,
                          classificationAndPersonalizationRuns=0, failedPairs=[])
        else:
            report.update(labels=97, sessions=[1, 2], failedRecords=[])
        arms = baseline.PAIR_ARMS if paired else ("raw", "points24", "points32", "points48")
        for policy in baseline.POLICIES:
            for arm in arms:
                summary_arm = arm
                if paired:
                    dimension, gap = arm.removeprefix("second").split("-gap")
                    summary_arm = dict(secondDimension=int(dimension), gap=float(gap))
                report["summaries"].append(dict(policy=policy, arm=summary_arm,
                    counts=self.counts(paired, 1552, arm),
                    byWriter={writer: self.counts(paired, 194, arm) for writer in self.writers}))
        return report

    @staticmethod
    def metrics(groups, expected):
        stats = baseline.partition_stats(groups, expected)
        return dict(exactPartition=stats["matchesExpectedGroups"], expectedOwnerCount=len(expected.owners),
            **{name: stats[name] for name in ("groupCount", "missingIndexes", "duplicateIndexes", "invalidIndexes",
                "falseMergedGroups", "falseSplitOwners")})

    def make_evaluation(self):
        rows = []
        for arm in baseline.ARMS + (baseline.TRIPLE_ARM,):
            cohort = baseline.expected_targets(self.samples, 1 if arm == "single32" else 3 if arm == baseline.TRIPLE_ARM else 2)
            for ids, expected in cohort.items():
                groups = [list(owner) for owner in expected.owners]
                rows.append(dict(role="development", arm=arm, sourceIDs=list(ids), writer=expected.writer,
                    session=expected.session, sourceStrokeCount=sum(map(len, expected.owners)), groups=groups,
                    expectedOwners=deepcopy(groups), exactOwnerMatch=True, metrics=self.metrics(groups, expected)))
        return dict(sourceSHA256=SOURCE_SHA256, developmentWriters=self.writers,
            codeSHA256={name: self.code[name] for name in baseline.LEARNED_FILES},
            reservedWritersEvaluated=False, privateInkUsed=False, productionEligible=False, targets=len(rows), rows=rows)

    def refresh_evaluation_summaries(self):
        totals, writers = defaultdict(Counter), defaultdict(lambda: defaultdict(Counter))
        sources = {sample.identity: sample for sample in self.samples}
        for row in self.evaluation["rows"]:
            stats = row["metrics"]
            counts = dict(targets=1, exactPartitions=int(row["exactOwnerMatch"]),
                falseMergedTargets=int(stats["falseMergedGroups"] > 0),
                falseSplitTargets=int(stats["falseSplitOwners"] > 0),
                singletonTargets=int(row["sourceStrokeCount"] == 1), sourceStrokes=row["sourceStrokeCount"],
                sourcePoints=sum(len(stroke.points) for identity in row["sourceIDs"] for stroke in sources[identity].strokes),
                zeroExtentCharacters=0, **{name: stats[name] for name in ("falseMergedGroups", "falseSplitOwners",
                    "missingIndexes", "duplicateIndexes", "invalidIndexes")})
            totals[row["arm"]].update(counts); writers[row["arm"]][row["writer"]].update(counts)
        self.evaluation["summaries"] = [dict(arm=arm, counts=dict(counts),
            byWriter={writer: dict(values) for writer, values in writers[arm].items()}) for arm, counts in totals.items()]

    def comparison(self):
        return baseline.compare_reports(self.records, self.isolated, self.paired, self.evaluation, self.root)

    def summary(self, policy="preserveOriginalInk", arm="second16-gap8"):
        return next(row for row in self.paired["summaries"] if row["policy"] == policy
            and baseline.pair_arm(row["arm"]) == arm)

    def add_pair_failure(self, *, input_only=False, policy="preserveOriginalInk"):
        arm = "second16-gap8"
        ids, expected = next(iter(baseline.expected_targets(self.samples, 2).items()))
        groups = [list(owner) for owner in expected.owners] if input_only else [[0, 1, 2, 3]]
        stats = baseline.partition_stats(groups, expected)
        source = {name: value for name, value in stats.items() if not name.startswith("false")}
        source.update(modelInputMismatchGroups=int(input_only), zeroExtent=False,
            rasterChecked=False, rasterMismatch=False, rasterEncodingFailed=False)
        self.paired["failedPairs"].append(dict(policy=policy, arm="second16-gap8.0", sourceIDs=list(ids),
            expectedOwners=[list(owner) for owner in expected.owners], groupStrokeIndexes=groups,
            result=dict(source=source, exactTwoOwnerMatch=input_only, falseMergedGroups=int(not input_only),
                falseSplitOwners=0, zeroExtentCharacters=0)))
        summary = self.summary(policy, arm)
        for counts in (summary["counts"], summary["byWriter"][expected.writer]):
            counts["exactOwnersAndModelInputs"] -= 1
            if input_only:
                counts["modelInputMismatchGroups"] += 1
            else:
                for name in ("groupCount", "twoGroupCount", "exactTwoOwnerMatches"):
                    counts[name] -= 1
                counts["falseMergedGroups"] += 1
                counts["falseMergedPairs"] += 1
        return ids

    def test_full_cohort_and_separate_code_maps_are_comparable_without_triple_baseline(self):
        self.assertNotEqual(self.isolated["codeSHA256"], self.evaluation["codeSHA256"])
        result = self.comparison()
        self.assertEqual(len(result["summaries"]), 14)
        self.assertEqual(len(result["rows"]), 2 * 7 * 1552)
        self.assertEqual(result["uncomparedArms"], [baseline.TRIPLE_ARM])
        for row in result["summaries"]:
            self.assertEqual(row["counts"]["denominator"], 1552)
            self.assertEqual(row["counts"]["baselineCorrect"], 1552)
            self.assertEqual(row["counts"]["gainedCorrect"], 0)
            self.assertEqual(row["counts"]["lostCorrect"], 0)
            self.assertTrue(all(counts["denominator"] == 194 for counts in row["byWriter"].values()))

    def test_input_only_failed_row_remains_ownership_correct(self):
        self.add_pair_failure(input_only=True, policy="semanticNormalization")
        result = self.comparison()
        row = next(row for row in result["summaries"] if row["policy"] == "semanticNormalization" and row["arm"] == "second16-gap8")
        self.assertEqual(row["counts"]["baselineCorrect"], 1552)
        self.assertEqual(row["counts"]["gainedCorrect"], 0)

    def test_gain_and_harm_use_exact_owner_partitions_not_group_count(self):
        gained_ids = self.add_pair_failure()
        arm = "second16-gap8"
        harmed = next(row for row in self.evaluation["rows"] if row["arm"] == arm and tuple(row["sourceIDs"]) != gained_ids)
        expected = baseline.expected_targets(self.samples, 2)[tuple(harmed["sourceIDs"])]
        wrong_two_groups = [[0], [1, 2, 3]]
        self.assertEqual(len(wrong_two_groups), len(expected.owners))
        harmed.update(groups=wrong_two_groups, exactOwnerMatch=False, metrics=self.metrics(wrong_two_groups, expected))
        self.refresh_evaluation_summaries()
        result = self.comparison()
        row = next(row for row in result["summaries"] if row["policy"] == "preserveOriginalInk" and row["arm"] == arm)
        self.assertEqual(row["counts"]["denominator"], 1552)
        self.assertEqual(row["counts"]["gainedCorrect"], 1)
        self.assertEqual(row["counts"]["lostCorrect"], 1)
        self.assertEqual(row["counts"]["learnedFalseMergedTargets"], 1)

    def test_predeclared_root_harm_gate_and_evaluation_summary_mismatch(self):
        harmed = next(row for row in self.evaluation["rows"] if row["arm"] == "single32"
                      and next(sample for sample in self.samples if sample.identity == row["sourceIDs"][0]).label == "A")
        expected = baseline.expected_targets(self.samples)[tuple(harmed["sourceIDs"])]
        harmed.update(groups=[[0], [1]], exactOwnerMatch=False, metrics=self.metrics([[0], [1]], expected))
        self.refresh_evaluation_summaries()
        result = self.comparison()
        self.assertEqual(result["integrationGate"]["isolatedRootBaselineCorrectHarms"], 1)
        self.assertFalse(result["integrationGate"]["eligibleForComparisonOnlyIntegration"])
        self.evaluation["summaries"][0]["counts"]["targets"] -= 1
        with self.assertRaises(ValueError):
            self.comparison()

    def test_missing_duplicate_or_reversed_source_rows_and_wrong_role_writer_arm_are_rejected(self):
        original = deepcopy(self.evaluation)
        for change in (lambda rows: rows.pop(), lambda rows: rows.append(deepcopy(rows[0])),
                lambda rows: rows[0].update(role="training"), lambda rows: rows[0].update(writer="tst_UPV_W00"),
                lambda rows: rows[0].update(arm="best-arm"), lambda rows: rows[0].update(sourceIDs=["unknown"])):
            self.evaluation = deepcopy(original)
            change(self.evaluation["rows"])
            with self.assertRaises(ValueError):
                self.comparison()
        self.evaluation = deepcopy(original)
        row = next(row for row in self.evaluation["rows"] if row["arm"] == "second16-gap8")
        row["sourceIDs"].reverse()
        with self.assertRaises(ValueError):
            self.comparison()

    def test_baseline_duplicate_or_missing_failure_and_per_writer_mismatch_are_rejected(self):
        self.add_pair_failure()
        original = deepcopy(self.paired)
        self.paired["failedPairs"].append(deepcopy(self.paired["failedPairs"][0]))
        with self.assertRaises(ValueError):
            self.comparison()
        self.paired = deepcopy(original)
        self.paired["failedPairs"].clear()
        with self.assertRaises(ValueError):
            self.comparison()
        self.paired = deepcopy(original)
        self.summary()["byWriter"][self.writers[0]]["pairs"] -= 1
        with self.assertRaises(ValueError):
            self.comparison()

    def test_source_digest_authoritative_code_and_recorded_answer_contradictions_are_rejected(self):
        for field, value in (("sourceSHA256", "0" * 64), ("developmentWriters", list(reversed(self.writers)))):
            original = self.evaluation[field]
            self.evaluation[field] = value
            with self.assertRaises(ValueError):
                self.comparison()
            self.evaluation[field] = original
        name = next(iter(baseline.SWIFT_FILES))
        (self.root / name).write_bytes(b"changed source")
        with self.assertRaises(ValueError):
            self.comparison()
        (self.root / name).write_bytes(("source fixture:" + name).encode())
        self.evaluation["rows"][0]["exactOwnerMatch"] = False
        with self.assertRaises(ValueError):
            self.comparison()
        self.evaluation["rows"][0]["exactOwnerMatch"] = True
        self.evaluation["rows"][0]["expectedOwners"] = [[99]]
        with self.assertRaises(ValueError):
            self.comparison()


if __name__ == "__main__":
    unittest.main()
