import copy
import inspect
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
import torch

from ichart_recognition_ml.research import personal_conditional_support_trust as trust


class ConditionalTrustTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)
        cls.vocabulary = [chr(33 + i) for i in range(97)]
        cls.writers = [f"trn_UJI_W{i:02}" for i in range(8)]
        cls.rows = []
        for w in cls.writers:
            for s in (1, 2):
                for c in cls.vocabulary:
                    identity = f"{w}-{s}-{c}"
                    cls.rows.append({"sourceID": identity, "writer": w, "session": s, "label": c,
                        "generator": "fitA", "rawRasterSHA256": trust.sha((identity + "raw").encode()),
                        "storedRasterSHA256": trust.sha((identity + "stored").encode()),
                        "trajectorySHA256": trust.sha((identity + "trajectory").encode()),
                        "storedTrajectorySHA256": trust.sha((identity + "stored-trajectory").encode()),
                        "storedFailure": None, "genericFitCopyReasons": []})

    def inputs(self, classes=97):
        generator = torch.Generator().manual_seed(901)
        sf = torch.randn(5, 6, dtype=torch.float64, generator=generator)
        sf /= sf.norm(dim=1, keepdim=True)
        qf = torch.randn(7, 6, dtype=torch.float64, generator=generator)
        qf /= qf.norm(dim=1, keepdim=True)
        sp = torch.randn(5, classes, dtype=torch.float64, generator=generator).softmax(1)
        qp = torch.randn(7, classes, dtype=torch.float64, generator=generator).softmax(1)
        return sf, sp, torch.tensor([0, 0, 1, 2, 3]), qf, qp

    def nonzero_model(self):
        model = trust.ConditionalSupportTrust()
        with torch.no_grad():
            model.gate[-1].weight.copy_(torch.linspace(-.2, .3, 32, dtype=torch.float64)[None, :])
        self.assertGreater(float(model.gate[-1].weight.abs().max()), 0)
        return model

    def test_initialization_is_fixed_and_only_final_layer_zero(self):
        state = torch.random.get_rng_state().clone()
        a, b = trust.ConditionalSupportTrust(), trust.ConditionalSupportTrust()
        self.assertTrue(torch.equal(state, torch.random.get_rng_state()))
        self.assertTrue(all(torch.equal(a.state_dict()[k], v) for k, v in b.state_dict().items()))
        self.assertGreater(float(a.gate[0].weight.abs().max()), 0)
        self.assertTrue(torch.equal(a.gate[-1].weight, torch.zeros(1, 32, dtype=torch.float64)))
        self.assertEqual(float(a.gate[-1].bias.detach()), -2.)

    def test_full_mass_empty_identity_and_untaught_ordering(self):
        sf, sp, sl, qf, qp = self.inputs()
        model = self.nonzero_model()
        output = model.probabilities(sf, sp, sl, qf, qp)
        self.assertEqual(output.shape, (7, 97))
        torch.testing.assert_close(output.sum(1), torch.ones(7, dtype=torch.float64))
        untaught = torch.tensor([i for i in range(97) if i not in sl.tolist()])
        self.assertTrue(torch.equal(output[:, untaught].argsort(1), qp[:, untaught].argsort(1)))
        empty = model.probabilities(sf[:0], sp[:0], sl[:0], qf, qp)
        self.assertIs(empty, qp)
        self.assertTrue(torch.equal(empty, qp))

    def test_support_permutation_and_exact_duplicate_invariance_nonzero_gate(self):
        values = self.inputs()
        sf, sp, sl, qf, qp = values
        model = self.nonzero_model()
        expected = model.probabilities(*values)
        order = torch.tensor([4, 0, 3, 1, 2])
        torch.testing.assert_close(expected, model.probabilities(sf[order], sp[order], sl[order], qf, qp), rtol=1e-13, atol=1e-14)
        order = torch.tensor([0, 1, 2, 3, 4, 0, 0, 3])
        torch.testing.assert_close(expected, model.probabilities(sf[order], sp[order], sl[order], qf, qp), rtol=1e-13, atol=1e-14)
        _, first = trust.prepare_inputs(*values)
        _, repeated = trust.prepare_inputs(sf[order], sp[order], sl[order], qf, qp)
        torch.testing.assert_close(first, repeated, rtol=1e-13, atol=1e-14)

    def test_class_and_orthogonal_basis_equivariance_nonzero_gate(self):
        sf, sp, sl, qf, qp = self.inputs()
        model = self.nonzero_model()
        expected = model.probabilities(sf, sp, sl, qf, qp)
        permutation = torch.randperm(97, generator=torch.Generator().manual_seed(52))
        inverse = permutation.argsort()
        actual = model.probabilities(sf, sp[:, permutation], inverse[sl], qf, qp[:, permutation])
        torch.testing.assert_close(actual, expected[:, permutation], rtol=1e-12, atol=1e-14)
        basis = torch.linalg.qr(torch.randn(6, 6, dtype=torch.float64, generator=torch.Generator().manual_seed(45))).Q
        torch.testing.assert_close(expected, model.probabilities(sf @ basis, sp, sl, qf @ basis, qp), rtol=1e-12, atol=1e-14)

    def test_all_exact_class_and_nearest_support_ties_are_symmetric(self):
        sf = torch.tensor([[1., 0.]] * 4, dtype=torch.float64)
        sp = torch.tensor([[.6, .2, .1, .1], [.2, .4, .2, .2], [.8, .1, .05, .05], [.4, .2, .2, .2]], dtype=torch.float64)
        sl = torch.tensor([0, 1, 0, 1])
        qf = sf[:1]
        qp = torch.tensor([[.3, .3, .2, .2]], dtype=torch.float64)
        cache, scalar = trust.prepare_inputs(sf, sp, sl, qf, qp)
        torch.testing.assert_close(cache, torch.tensor([[.5, .5, 0., 0.]], dtype=torch.float64))
        self.assertAlmostEqual(float(scalar[0, 6]), .3)
        self.assertAlmostEqual(float(scalar[0, 10]), (.6 + .4 + .8 + .2) / 4)
        self.assertEqual(float(scalar[0, 9]), 0.)
        self.assertEqual(float(scalar[0, 12]), 1.)
        self.assertEqual(float(scalar[0, 13]), 1.)
        swapped = torch.tensor([1, 0, 3, 2])
        model = self.nonzero_model()
        torch.testing.assert_close(model.probabilities(sf, sp[:, swapped], swapped.argsort()[sl], qf, qp[:, swapped]),
            model.probabilities(sf, sp, sl, qf, qp)[:, swapped], rtol=1e-13, atol=1e-14)

    def test_single_label_zero_contrast_and_entropy_uses_full_vocabulary(self):
        sf, sp, sl, qf, qp = self.inputs()
        cache, scalar = trust.prepare_inputs(sf[:1], sp[:1], sl[:1], qf, qp)
        self.assertTrue(torch.equal(scalar[:, 9], torch.zeros(7, dtype=torch.float64)))
        self.assertTrue(torch.equal(scalar[:, 5], torch.zeros(7, dtype=torch.float64)))
        self.assertTrue(torch.equal(scalar[:, 11], torch.full((7,), 1 / 97, dtype=torch.float64)))
        self.assertEqual(int((cache > 0).sum(1)[0]), 1)

    def test_exact_and_near_ties_transform_all_fourteen_scalars_with_nonzero_gate(self):
        model = self.nonzero_model()
        basis = torch.linalg.qr(torch.randn(3, 3, dtype=torch.float64,
            generator=torch.Generator().manual_seed(173))).Q
        support_order = torch.tensor([3, 0, 2, 1])
        class_order = torch.tensor([2, 1, 3, 0])
        labels = torch.tensor([0, 1, 0, 1])
        probabilities = torch.tensor([[.6, .2, .1, .1], [.2, .4, .2, .2],
            [.8, .1, .05, .05], [.4, .2, .2, .2]], dtype=torch.float64)
        query = torch.tensor([[1., 0., 0.]], dtype=torch.float64)
        for exact in (True, False):
            with self.subTest(exact=exact):
                # Near gaps are 1e-5 in cosine and 2e-6 in generic score:
                # safely larger than float64 roundoff, never tolerance ties.
                cosines = [1.] * 4 if exact else [.95, .94999, .94998, .94997]
                features = torch.tensor([[c, np.sqrt(1 - c * c), 0.] for c in cosines], dtype=torch.float64)
                generic = torch.tensor([[.3, .3, .2, .2] if exact else [.300001, .299999, .2, .2]], dtype=torch.float64)
                cache, scalars = trust.prepare_inputs(features, probabilities, labels, query, generic)
                result = model.probabilities(features, probabilities, labels, query, generic)
                if exact:
                    self.assertEqual(float(scalars[0, 1]), 0.)
                    self.assertEqual(float(scalars[0, 4]), 0.)
                    self.assertAlmostEqual(float(scalars[0, 10]), .5)
                else:
                    self.assertGreater(float(scalars[0, 1]), 1e-6)
                    self.assertGreater(float(scalars[0, 4]), 1e-6)
                    self.assertAlmostEqual(float(scalars[0, 10]), .6)
                transformations = ((features[support_order], probabilities[support_order], labels[support_order], query, generic),
                    (features, probabilities[:, class_order], class_order.argsort()[labels], query, generic[:, class_order]),
                    (features @ basis, probabilities, labels, query @ basis, generic))
                for i, values in enumerate(transformations):
                    other_cache, other_scalars = trust.prepare_inputs(*values)
                    torch.testing.assert_close(other_scalars, scalars, rtol=1e-12, atol=1e-13)
                    expected_cache = cache[:, class_order] if i == 1 else cache
                    expected_result = result[:, class_order] if i == 1 else result
                    torch.testing.assert_close(other_cache, expected_cache, rtol=1e-12, atol=1e-13)
                    torch.testing.assert_close(model.probabilities(*values), expected_result, rtol=1e-12, atol=1e-13)

    def test_invalid_matrices_labels_and_features_fail(self):
        sf, sp, sl, qf, qp = self.inputs()
        bad = [(sf.float(), sp, sl, qf, qp), (sf * 2, sp, sl, qf, qp),
            (sf, sp, sl.float(), qf, qp), (sf, sp, sl + 200, qf, qp),
            (sf, sp[:, :3], sl, qf, qp), (sf, sp, sl, qf, qp * .5)]
        nan = qp.clone(); nan[0, 0] = torch.nan
        bad.append((sf, sp, sl, qf, nan))
        for values in bad:
            with self.subTest(shape=[x.shape for x in values]), self.assertRaises(ValueError):
                trust.ConditionalSupportTrust().probabilities(*values)

    def test_candidate_interface_has_no_query_answers_or_source_identity(self):
        parameters = tuple(inspect.signature(trust.ConditionalSupportTrust.probabilities).parameters)
        self.assertEqual(parameters, ("self", "sf", "sp", "sl", "qf", "qp"))
        preparation = tuple(inspect.signature(trust.prepare_inputs).parameters)
        self.assertEqual(preparation, ("sf", "sp", "sl", "qf", "qp"))
        loader = inspect.getsource(trust.load_fitted_learner)
        self.assertNotIn("load_parent(", loader)
        self.assertNotIn("episode_plan(", loader)
        self.assertNotIn('"metadata.json"', loader)

    def test_source_plan_complete_disjoint_counts_and_determinism(self):
        plans = trust.episode_plan(self.rows, self.vocabulary, self.writers, epochs=30, seed=41)
        self.assertEqual(len(plans), 960)
        self.assertEqual(plans, trust.episode_plan(self.rows, self.vocabulary, self.writers, epochs=30, seed=41))
        roles = {"sourceIndices": {"metaFit": list(range(1552)), "internalValidation": list(range(1552, 3104))},
            "metaFitWriters": self.writers, "internalValidationWriters": [f"trn_UPV_W{i:02}" for i in range(8)],
            "encoderFitWriters": [f"trn_UJI_W{i:02}" for i in range(8, 24)]}
        trust.validate_saved_plans(plans, roles)
        self.assertEqual(sum(len(p["scheduledQueries"]) for p in plans), 960 * 97)
        self.assertNotEqual(plans[:32], plans[32:64])
        altered = copy.deepcopy(plans); altered[0]["support"][0] = 1552
        with self.assertRaises(ValueError): trust.validate_saved_plans(altered, roles)
        roles["internalValidationWriters"][0] = self.writers[0]
        with self.assertRaises(ValueError): trust.validate_saved_plans(plans, roles)

    def test_source_copies_and_unavailable_setup_retained(self):
        rows = copy.deepcopy(self.rows)
        for row in rows:
            if row["session"] == 2 and row["label"] == self.vocabulary[0]:
                row["genericFitCopyReasons"] = ["generic-fit-raw-raster-copy"]
            if row["session"] == 1:
                row["storedRasterSHA256"] = "shared-stored-pixel"
                row["storedTrajectorySHA256"] = "shared-stored-trajectory"
            if row["session"] == 2 and row["label"] == self.vocabulary[1]:
                row["rawRasterSHA256"] = "shared-stored-pixel"
                row["trajectorySHA256"] = "shared-stored-trajectory"
            if row["label"] == self.vocabulary[-1]:
                row["storedRasterSHA256"] = row["storedTrajectorySHA256"] = None
                row["storedFailure"] = "PersonalInkShape-unavailable"
        plans = trust.episode_plan(rows, self.vocabulary, self.writers)
        for p in plans:
            self.assertFalse(any(rows[i]["storedRasterSHA256"] is None for i in p["support"]))
            expected_unavailable = [{"index": i, "failure": "PersonalInkShape-unavailable"}
                for i, row in enumerate(rows) if row["writer"] == p["writer"]
                and row["session"] == p["session"] and row["label"] == self.vocabulary[-1]]
            self.assertEqual(p["unavailableSetup"], expected_unavailable)
            self.assertEqual(len(p["queries"]) + len(p["exclusions"]), 97)
            if p["session"] == 1:
                reasons = {rows[e["index"]]["label"]: e["reasons"] for e in p["exclusions"]}
                self.assertEqual(reasons[self.vocabulary[0]], ["generic-fit-raw-raster-copy"])
                self.assertEqual(reasons[self.vocabulary[1]], ["support-raster-copy", "support-normalized-trajectory-copy"])

    def test_planner_rejects_nontraining_wrong_generator_and_incomplete_grid(self):
        for rows, writers in ((self.rows[:-1], self.writers), (self.rows, ["dev_UJI_W00", *self.writers[1:]])):
            with self.assertRaises(ValueError): trust.episode_plan(rows, self.vocabulary, writers)
        rows = copy.deepcopy(self.rows); rows[0]["generator"] = "fitB"
        with self.assertRaises(ValueError): trust.episode_plan(rows, self.vocabulary, self.writers)
        with self.assertRaises(ValueError): trust.episode_plan(self.rows, self.vocabulary, self.writers, epochs=31)

    def test_real_960_update_synthetic_fit_checkpoint_reload_and_tamper(self):
        sf, sp, sl, qf, qp = self.inputs()
        cache, scalars = trust.prepare_inputs(sf, sp, sl, qf, qp)
        targets = torch.tensor([0, 1, 2, 4, 5, 6, 7])
        taught = torch.isin(targets, sl)
        prepared = [(qp, cache, scalars, targets, taught)] * 960
        plans = [{"epoch": e} for e in range(1, 31) for _ in range(32)]
        model = trust.ConditionalSupportTrust()
        with mock.patch("builtins.print"):
            history, deltas = trust.train_gate(model, prepared, plans)
        self.assertEqual(sum(h["updates"] for h in history), 960)
        self.assertEqual(len(deltas), 4)
        self.assertTrue(all(d > 0 for d in deltas.values()))
        self.assertEqual(history[0]["learningRate"], .001)
        self.assertLess(history[-1]["learningRate"], history[0]["learningRate"])
        binding = {"purpose": "synthetic-only", "finalEpoch": 30}
        payload = trust.checkpoint_bytes(model, binding)
        restored = trust.load_checkpoint(payload, trust.sha(payload), binding)
        torch.testing.assert_close(model.probabilities(sf, sp, sl, qf, qp), restored.probabilities(sf, sp, sl, qf, qp), rtol=0, atol=0)
        with self.assertRaises(ValueError): trust.load_checkpoint(payload + b"x", trust.sha(payload), binding)
        with self.assertRaises(ValueError): trust.load_checkpoint(payload, trust.sha(payload), {"purpose": "other"})
        saved = torch.load(io.BytesIO(payload), weights_only=True)
        saved["state_dict"]["gate.0.bias"][0] = torch.nan
        stream = io.BytesIO(); torch.save(saved, stream)
        broken = stream.getvalue()
        with self.assertRaises(ValueError): trust.load_checkpoint(broken, trust.sha(broken), binding)
        json.loads(trust.canonical({"history": history, "deltas": deltas}))

    def test_parent_hash_boundary_rejects_changed_input_before_parse(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp).resolve()
            for name in ("fit-receipt.json", "fit-plan.json", "metadata.json", "features.npz", "protocol.md",
                         "weights/fitA.pt", "weights/fitB.pt"):
                path = directory / name; path.parent.mkdir(exist_ok=True)
                path.write_bytes(b"synthetic-only")
            manifest = directory / "roles.json"; manifest.write_bytes(b"synthetic-only")
            with mock.patch.object(trust.inner, "inner_roles", side_effect=AssertionError("must reject before parsing")):
                with self.assertRaises(ValueError): trust.load_parent(directory, manifest)
            before = trust.input_identity(directory)
            (directory / "metadata.json").write_bytes(b"changed")
            self.assertNotEqual(before, trust.input_identity(directory))

    def test_code_protocol_and_parent_identity_are_explicit(self):
        identity = trust.code_identity()
        self.assertEqual(identity[trust.PROTOCOL], trust.PROTOCOL_SHA256)
        self.assertIn(trust.CODE_FILES[0], identity)
        self.assertIn(trust.CODE_FILES[1], identity)
        with mock.patch.object(trust.audit, "code_identity", return_value={}), mock.patch.object(Path, "read_bytes", return_value=b"changed"):
            with self.assertRaises(ValueError): trust.code_identity()


if __name__ == "__main__":
    unittest.main()
