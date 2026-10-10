"""Synthetic metadata only: source roles, episode accounting, RNG commitments."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import torch

from ichart_recognition_ml.research import personal_support_match_defer_plan as p
from ichart_recognition_ml.research.uji_personal import Sample


def fixture():
    labels = sorted(set().union(*map(set, p.TASKS.values())) | {chr(0x100 + i) for i in range(76)})
    synthetic = tuple(Sample(f"{prefix}_UPV_W{w:02}", session, label, ())
        for prefix, count in (("trn", 40), ("tst", 20)) for w in range(count) for session in (1, 2) for label in labels)
    training, folds, development, reserved = p.crossfit.fold_writers(synthetic)
    rows = []
    for sample in training:
        unavailable = sample.writer in (folds["A"][0], folds["B"][0]) and sample.session == 1 and sample.label == "m"
        rows.append({"sourceID": sample.identity, "writer": sample.writer, "session": sample.session, "label": sample.label,
            "rawRasterSHA256": p.sha(("raw:" + sample.identity).encode()), "trajectorySHA256": p.sha(("trajectory:" + sample.identity).encode()),
            "storedRasterSHA256": None if unavailable else p.sha(("stored:" + sample.identity).encode()),
            "storedTrajectorySHA256": None if unavailable else p.sha(("stored-trajectory:" + sample.identity).encode()),
            "storedFailure": "PersonalInkShape-unavailable" if unavailable else None,
            "generator": "fitA" if sample.writer in folds["B"] else "fitB"})
    metadata = {"version": p.crossfit.VERSION, "vocabulary": labels, "rows": rows}
    receipt = {"version": p.crossfit.VERSION, "sourceSHA256": p.SOURCE_SHA256, "vocabulary": labels,
        "trainingWriters": sorted(folds["A"] + folds["B"]), "folds": {k: list(v) for k, v in folds.items()},
        "developmentWriters": list(development), "reservedWriters": list(reserved), "metadataSHA256": p.sha(p.canonical(metadata)),
        "codeSHA256": {"syntheticSourceOnly": "0" * 64}, "supportAdapterGolden": {"synthetic": True},
        "roleGuards": {"training32Only": True, "privateInkUsed": False, "developmentModelInferencePerformed": False, "reservedRastersConstructed": False}}
    return receipt, metadata


def build(receipt, metadata):
    receipt = {**receipt, "metadataSHA256": p.sha(p.canonical(metadata))}
    data = domain_bytes(metadata)
    with patch.dict(p.PARENT, receipt=p.sha(p.canonical(receipt)), metadata=receipt["metadataSHA256"]), patch.object(p, "DOMAIN_SHA256", p.sha(data)):
        return p.build_plan(receipt, metadata, receipt_sha256=p.sha(p.canonical(receipt)), metadata_sha256=receipt["metadataSHA256"],
            domain_data=data, domain_sha256=p.sha(data))


def domain_bytes(metadata):
    vocabulary = metadata["vocabulary"]
    allowed = list(p.TASKS["catalog21"]) + [l for l in vocabulary if l not in p.TASKS["catalog21"]][:20]
    return p.canonical({"version": "chord-recognition-domain-v1", "vocabulary": vocabulary, "allowedLabels": allowed})


class MatchDeferPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.receipt, cls.metadata = fixture()
        cls.plan = build(cls.receipt, cls.metadata)

    def test_exact_disjoint_source_roles_and_fixed_update_budget(self):
        for direction, forward in self.plan["forward"].items():
            self.assertEqual(len(forward["fitWriters"]), 16); self.assertEqual(len(forward["heldoutWriters"]), 16)
            self.assertFalse(set(forward["fitWriters"]) & set(forward["heldoutWriters"]))
            self.assertEqual(len(forward["trainingEpisodes"]), 64); self.assertEqual(len(forward["heldoutEpisodes"]), 64)
            self.assertEqual(sum(len(e["updates"]) for e in forward["epochs"]), 1920)
            self.assertEqual(self.plan["counts"][direction]["trainingRawDistinctSources"], 3104)
            self.assertEqual(self.plan["counts"][direction]["trainingQueryExposuresPerEpoch"], 6208)
            self.assertEqual(self.plan["counts"][direction]["trainingScheduledSupportSlotsPerEpoch"], 992)
        self.assertEqual(self.plan["recipe"]["scheduler"]["tMax"], 1920)
        self.assertFalse(self.plan["protocolBindingDeferred"])
        self.assertEqual(self.plan["protocolSHA256"], p.PROTOCOL_SHA256)

    def test_both_sessions_full97_no_heldout_truth_forward(self):
        for forward in self.plan["forward"].values():
            episodes = forward["trainingEpisodes"] + [h["trueSupport"] for h in forward["heldoutEpisodes"]]
            for e in episodes:
                self.assertEqual(len(e["querySourceIndices"]), 97)
                self.assertEqual(len(set(e["querySourceIndices"])), 97)
                self.assertEqual(e["supportSession"], 3 - e["querySession"])
                self.assertEqual(e["requestedSupportLabels"], list(p.TASKS[e["catalog"]]))
                self.assertEqual([b["role"] for b in e["batchSources"][:e["queryBatchOffset"]]], ["storedSupport"] * e["queryBatchOffset"])
                self.assertEqual([b["role"] for b in e["batchSources"][e["queryBatchOffset"]:]], ["rawQuery"] * 97)
                self.assertTrue(all("label" not in b and "target" not in b for b in e["batchSources"] if b["role"] == "rawQuery"))
        self.assertTrue(all("label" not in s and "sourceID" not in s for s in self.plan["sourceLedger"]))

    def test_unavailable_slots_retained_separate_defer_target(self):
        direction = "A16-to-B16"; writer = self.receipt["folds"]["A"][0]
        e = next(e for e in self.plan["forward"][direction]["trainingEpisodes"] if e["writer"] == writer and e["querySession"] == 2 and e["catalog"] == "catalog21")
        self.assertEqual(e["scheduledSupportSlots"], 21); self.assertEqual(e["availableSupportRows"], 20)
        self.assertEqual(len(e["batchSources"]), 117)
        m = next(s for s in e["support"] if s["label"] == "m")
        self.assertIsNone(m["storedRasterSHA256"]); self.assertEqual(m["storedFailure"], "PersonalInkShape-unavailable")
        targets = [t for t in self.plan["trainingTargets"][direction] if t["episodeID"] == e["episodeID"]]
        unavailable = [t for t in targets if t["cohort"] == "requestedSupportUnavailable"]
        self.assertEqual(len(unavailable), 1); self.assertIsNone(unavailable[0]["matchPrototypeIndex"]); self.assertTrue(unavailable[0]["defer"])
        self.assertEqual(sum(t["cohort"] == "taught" for t in targets), 20)
        for target in targets:
            label = self.plan["vocabulary"][target["genericClassIndex"]]
            expected = e["availablePrototypeLabels"].index(label) if label in e["availablePrototypeLabels"] else None
            self.assertEqual(target["matchPrototypeIndex"], expected)

    def test_source_only_cyclic_donor_no_geometry_or_feature_load(self):
        with patch.object(p.crossfit, "setup_shape", side_effect=AssertionError("No geometry allowed")), patch.object(p.crossfit, "load_crossfit_bundle", side_effect=AssertionError("No feature/model load allowed")):
            plan = build(self.receipt, self.metadata)
        for forward in plan["forward"].values():
            writers = forward["heldoutWriters"]
            for h in forward["heldoutEpisodes"]:
                true, wrong = h["trueSupport"], h["wrongSupport"]
                self.assertEqual(wrong["supportWriter"], writers[(writers.index(true["writer"]) + 1) % 16])
                self.assertNotEqual(wrong["supportWriter"], true["writer"])
                self.assertEqual(true["querySourceIndices"], wrong["querySourceIndices"])
                self.assertEqual(true["supportSession"], wrong["supportSession"])
                self.assertIn("eval-fixed", h["batchNormalization"])

    def test_matched_epoch_order_and_actual_torch_draw_hashes(self):
        for forward in self.plan["forward"].values():
            self.assertEqual(len(set(forward["matchedArmScheduleSHA256"].values())), 1)
            generator = torch.Generator().manual_seed(29)
            for epoch in forward["epochs"]:
                expected = sorted(forward["trainingEpisodes"], key=lambda e: p.sha(("personal-support-match-defer-v1:epoch:" + str(epoch["epoch"]) + e["episodeID"]).encode()))
                self.assertEqual([u["episodeID"] for u in epoch["updates"]], [e["episodeID"] for e in expected])
                for update in epoch["updates"]:
                    self.assertEqual(update["generatorBeforeSHA256"], p.sha(generator.get_state().numpy().tobytes()))
                    draws = torch.rand((update["batchRows"], 4), generator=generator)
                    self.assertEqual(update["augmentationDrawsSHA256"], p.sha(draws.numpy().tobytes()))
                    self.assertEqual(update["generatorAfterSHA256"], p.sha(generator.get_state().numpy().tobytes()))

    def test_tamper_roles_grid_availability_and_pins_fail(self):
        for mutation in ("grid", "role", "availability"):
            receipt, metadata = copy.deepcopy(self.receipt), copy.deepcopy(self.metadata)
            if mutation == "grid": metadata["rows"].pop()
            elif mutation == "role": receipt["folds"]["A"].reverse()
            else: metadata["rows"][0]["storedFailure"] = "unavailable-but-hashes-remain"
            with self.assertRaises(ValueError): build(receipt, metadata)
        with self.assertRaisesRegex(ValueError, "Pinned"):
            p.build_plan(self.receipt, self.metadata, receipt_sha256="0" * 64, metadata_sha256=self.receipt["metadataSHA256"],
                domain_data=domain_bytes(self.metadata), domain_sha256=p.sha(domain_bytes(self.metadata)))

    def test_wrong_support_coverage_mismatch_is_unavailable_no_donor_repair(self):
        forward = self.plan["forward"]["A16-to-B16"]; writer = forward["heldoutWriters"][0]
        h = next(h for h in forward["heldoutEpisodes"] if h["trueSupport"]["writer"] == writer and h["trueSupport"]["querySession"] == 2 and h["trueSupport"]["catalog"] == "catalog21")
        self.assertFalse(h["availableLabelSetsEqual"])
        evidence = next(e for e in self.plan["sourceCopyLedger"]["A16-to-B16"]["episodeEvidence"] if e["episodeID"] == h["trueSupport"]["episodeID"])
        self.assertTrue(evidence["evidenceUnavailable"])
        self.assertNotEqual(h["trueSupport"]["availablePrototypeLabels"], h["wrongSupport"]["availablePrototypeLabels"])
        self.assertEqual(h["wrongSupport"]["supportWriter"], forward["heldoutWriters"][1])
        self.assertEqual(len(h["trueSupport"]["support"]), len(h["wrongSupport"]["support"]))

    def test_duplicate_ink_profiles_retained_but_unusable(self):
        metadata = copy.deepcopy(self.metadata); writer = self.receipt["folds"]["A"][0]
        selected = [r for r in metadata["rows"] if r["writer"] == writer and r["session"] == 1 and r["label"] in ("A", "B")]
        selected[1]["storedRasterSHA256"] = selected[0]["storedRasterSHA256"]
        selected[1]["storedTrajectorySHA256"] = selected[0]["storedTrajectorySHA256"]
        result = build(self.receipt, metadata); forward = result["forward"]["A16-to-B16"]
        e = next(e for e in forward["trainingEpisodes"] if e["writer"] == writer and e["querySession"] == 2 and e["catalog"] == "core10")
        self.assertEqual(len(e["support"]), 10); self.assertEqual(len(e["batchSources"]), 107)
        self.assertFalse(e["profileUsable"]); self.assertIn("duplicate-storedRasterSHA256", e["profileIssues"])
        self.assertFalse(result["counts"]["A16-to-B16"]["numericalFitAllowed"])

    def test_source_copy_union_and_exhausted_evidence_not_dropped(self):
        query = {"rawRasterSHA256": "r", "trajectorySHA256": "t"}
        sources = [{"rawRasterSHA256": "r", "trajectorySHA256": "t", "storedRasterSHA256": "r", "storedTrajectorySHA256": "t"}]
        self.assertEqual(len(p.copy_reasons(query, p.copy_sets({"encoder-fit": sources, "true-support": sources, "wrong-support": sources}))), 12)
        metadata = copy.deepcopy(self.metadata)
        for row in metadata["rows"]:
            row["rawRasterSHA256"] = "a" * 64; row["trajectorySHA256"] = "b" * 64
        result = build(self.receipt, metadata)
        for direction, forward in result["forward"].items():
            self.assertEqual(len(forward["heldoutEpisodes"]), 64)
            self.assertTrue(all(h["evidenceUnavailable"] for h in result["sourceCopyLedger"][direction]["episodeEvidence"]))
            self.assertEqual(len(result["sourceCopyLedger"][direction]["queryRows"]), 6208)
            self.assertEqual(result["counts"][direction]["heldoutCopyEligibleExposures"], 0)

    def test_prepare_writes_separate_targets_without_geometry_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve(); parent = base / "crossfit"; parent.mkdir()
            old_plan = {k: self.receipt[k] for k in ("version", "sourceSHA256", "trainingWriters", "folds", "developmentWriters", "reservedWriters")}
            receipt = {**self.receipt, "fitPlanSHA256": p.sha(p.canonical(old_plan))}
            for name, value in (("fit-receipt.json", receipt), ("fit-plan.json", old_plan), ("metadata.json", self.metadata)):
                (parent / name).write_bytes(p.canonical(value))
            output = base / "planned"
            domain = base / "domain.json"; data = domain_bytes(self.metadata); domain.write_bytes(data)
            pins = {"receipt": p.sha(p.canonical(receipt)), "plan": p.sha(p.canonical(old_plan)), "metadata": receipt["metadataSHA256"]}
            kwargs = {"receipt_sha256": pins["receipt"], "domain_path": domain, "domain_sha256": p.sha(data)}
            with patch.dict(p.PARENT, pins), patch.object(p, "DOMAIN_SHA256", p.sha(data)), patch.object(p, "read", wraps=p.read) as reads:
                result = p.prepare(parent, output, **kwargs)
                self.assertFalse(any(Path(c.args[0]).name in ("features.npz", "fitA.pt", "fitB.pt") for c in reads.call_args_list))
            self.assertNotIn("trainingTargets", result)
            self.assertEqual({f.name for f in output.iterdir()}, {"forward-plan.json", "A16-to-B16-training-targets.json", "B16-to-A16-training-targets.json",
                "A16-to-B16-scoring-ledger.json", "B16-to-A16-scoring-ledger.json", "plan-receipt.json"})
            saved = p.parsed(p.read(output / "forward-plan.json"))
            for forbidden in ("trainingTargets", "sourceCopyLedger", "counts", "sourceOnlyEligibleCohortCounts", "evidenceUnavailable", "genericClassIndex", "cohort"):
                self.assertNotIn('"' + forbidden + '"', p.canonical(saved).decode())
            for direction, binding in saved["trainingTargetBindings"].items():
                self.assertEqual(p.sha(p.read(output / binding["path"])), binding["SHA256"])
            for binding in saved["scoringLedgerBindings"].values():
                self.assertEqual(p.sha(p.read(output / binding["path"])), binding["SHA256"])
            self.assertEqual(len(p.parsed(p.read(output / "A16-to-B16-scoring-ledger.json"))["episodeEvidence"]), 64)
            with patch.dict(p.PARENT, pins), patch.object(p, "DOMAIN_SHA256", p.sha(data)), self.assertRaisesRegex(ValueError, "Fresh"):
                p.prepare(parent, output, **kwargs)


if __name__ == "__main__":
    unittest.main()
