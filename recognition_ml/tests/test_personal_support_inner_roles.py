import copy
import unittest

from ichart_recognition_ml.research.personal_support_inner_roles import inner_roles
from ichart_recognition_ml.research.personal_support_retrieval import canonical, sha


def fixture():
    writers = [f"trn_synthetic_{i:02}" for i in range(32)]
    ordered = sorted(writers, key=lambda w: sha(("personal-support-retrieval-v1:fold:" + w).encode()))
    vocabulary = [chr(i + 33) for i in range(97)]
    receipt = {"vocabulary": vocabulary, "folds": {"A": ordered[:16], "B": ordered[16:]},
               "trainingWriters": sorted(writers), "developmentWriters": ["trn_synthetic_dev"],
               "reservedWriters": ["tst_synthetic_reserved"], "weightsSHA256": {"fitA": "a" * 64, "fitB": "b" * 64},
               "metadataSHA256": "c" * 64, "featuresSHA256": "d" * 64, "sourceSHA256": "e" * 64,
               "protocolSHA256": "f" * 64, "codeSHA256": {"synthetic.py": "0" * 64}}
    rows = [{"sourceID": f"{w}:{s}:{c}", "writer": w, "session": s, "label": c,
             "generator": "fitA" if w in ordered[16:] else "fitB"}
            for w in writers for s in (1, 2) for c in vocabulary]
    return receipt, rows


class InnerRolesTests(unittest.TestCase):
    def setUp(self):
        self.receipt, self.rows = fixture()

    def test_disjoint_stage_sets_same_generator_and_explicit_reuse_ceiling(self):
        plan = inner_roles(self.receipt, self.rows)
        sets = [set(plan[key]) for key in ("encoderFitWriters", "metaFitWriters", "internalValidationWriters")]
        self.assertEqual([len(s) for s in sets], [16, 8, 8])
        self.assertFalse(sets[0] & sets[1] or sets[0] & sets[2] or sets[1] & sets[2])
        self.assertEqual(plan["rowCounts"], {"metaFit": 1552, "internalValidation": 1552})
        self.assertTrue(plan["previouslyUsedInAllWriterLearnerFit"])
        for key in ("otherGeneratorUsed", "freshValidation", "candidateSelected", "modelFitted", "productionEligible"):
            self.assertFalse(plan[key])
        for indices in plan["sourceIndices"].values():
            self.assertTrue(all(self.rows[i]["generator"] == "fitA" for i in indices))

    def test_source_only_determinism_and_role_hash_changes_with_row_order(self):
        first = inner_roles(self.receipt, self.rows)
        second = inner_roles(copy.deepcopy(self.receipt), copy.deepcopy(self.rows))
        self.assertEqual(first, second)
        reordered = inner_roles(self.receipt, list(reversed(self.rows)))
        self.assertEqual(first["metaFitWriters"], reordered["metaFitWriters"])
        self.assertNotEqual(first["roleRowsSHA256"], reordered["roleRowsSHA256"])

    def test_parent_bindings_and_mutation_isolation(self):
        original = copy.deepcopy(self.receipt)
        plan = inner_roles(self.receipt, self.rows)
        self.assertEqual(plan["crossfitReceiptSHA256"], sha(canonical(self.receipt)))
        self.assertEqual(plan["parentInputsSHA256"]["featuresSHA256"], self.receipt["featuresSHA256"])
        plan["encoderFitWriters"].clear()
        plan["metaFitWriters"].clear()
        plan["internalValidationWriters"].clear()
        plan["parentCodeSHA256"].clear()
        self.assertEqual(self.receipt, original)
        changed = copy.deepcopy(self.receipt)
        changed["featuresSHA256"] = "1" * 64
        other = inner_roles(changed, self.rows)
        self.assertNotEqual(other["crossfitReceiptSHA256"], sha(canonical(self.receipt)))

    def test_rejects_overlap_prohibited_writer_and_outcome_selected_fold_order(self):
        changes = [lambda r: r["folds"]["B"].__setitem__(0, r["folds"]["A"][0]),
                   lambda r: r["developmentWriters"].append(r["trainingWriters"][0]),
                   lambda r: r["folds"]["B"].reverse()]
        for change in changes:
            receipt = copy.deepcopy(self.receipt)
            change(receipt)
            with self.assertRaises(ValueError):
                inner_roles(receipt, self.rows)

    def test_rejects_mixed_generator_incomplete_grid_and_duplicate_source(self):
        for mutation in ("generator", "grid", "source"):
            rows = copy.deepcopy(self.rows)
            if mutation == "generator":
                rows[0]["generator"] = "fitB" if rows[0]["generator"] == "fitA" else "fitA"
            elif mutation == "grid":
                rows[0]["session"] = 3
            else:
                rows[0]["sourceID"] = rows[1]["sourceID"]
            with self.assertRaises(ValueError):
                inner_roles(self.receipt, rows)

    def test_rejects_bad_generator_hash_and_vocabulary(self):
        receipt = copy.deepcopy(self.receipt)
        receipt["weightsSHA256"]["fitA"] = "x" * 64
        with self.assertRaises(ValueError):
            inner_roles(receipt, self.rows)
        receipt = copy.deepcopy(self.receipt)
        receipt["vocabulary"].reverse()
        with self.assertRaises(ValueError):
            inner_roles(receipt, self.rows)


if __name__ == "__main__":
    unittest.main()
