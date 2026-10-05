import copy
from pathlib import Path
import platform
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.research import personal_training_centroids as centroids
from ichart_recognition_ml.research.personal_cross_writer_contrastive import _state_digest
from ichart_recognition_ml.research.personal_support_retrieval import canonical, sha
from ichart_recognition_ml.research.uji_personal import Sample, SOURCE_SHA256, trajectory_fingerprint


def fixture():
    writers = [f"trn_UPV_W{i:02d}" for i in range(16)]
    vocabulary = [chr(0x100 + i) for i in range(97)]
    samples = tuple(Sample(w, s, c, (InkStroke((InkPoint(0, 0), InkPoint(10, 20))),))
        for w in writers for s in (1, 2) for c in vocabulary)
    rows = [{"sourceID": x.identity, "writer": x.writer, "session": x.session, "label": x.label,
        "rawRasterSHA256": "a" * 64, "trajectorySHA256": trajectory_fingerprint(x), "generator": "fitA"} for x in samples]
    features = np.zeros((3104, 128), dtype=np.float32)
    features[:, 0] = 1
    return writers, vocabulary, samples, rows, features


class TrainingCentroidsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(2)
        cls.writers, cls.vocabulary, cls.samples, cls.rows, cls.features = fixture()

    def test_header_selector_skips_malformed_unselected_coordinates_opaquely(self):
        blocks = [f"WORD {s.label} {s.writer}-0{s.session}\nNUMSTROKES 1\nPOINTS 2 # 0 0 10 20" for s in self.samples]
        blocks.insert(7, "WORD A tst_UPV_W99-01\nNUMSTROKES 2\nnot coordinates or a POINTS header\nWORD invalid point payload")
        blocks.append("WORD B trn_UPV_W99-02\nNUMSTROKES 1\nPOINTS hopelessly malformed")
        actual = centroids.select_training_source("\n".join(reversed(blocks)), self.writers, self.vocabulary)
        self.assertEqual(actual, self.samples)
        self.assertTrue(all(s.writer in self.writers for s in actual))
        for broken in (blocks[:-2], blocks + [blocks[0]], [blocks[0].replace("10 20", "NaN bad")] + blocks[1:]):
            with self.assertRaises(ValueError):
                centroids.select_training_source("\n".join(broken), self.writers, self.vocabulary)

    def test_grid_rejects_wrong_writer_session_duplicate_generator_order_and_labels(self):
        changes = [lambda r: r[0].__setitem__("writer", "tst_UPV_W00"),
                   lambda r: r[0].__setitem__("session", True),
                   lambda r: r.__setitem__(0, r[1]),
                   lambda r: r[0].__setitem__("generator", "fitB"),
                   lambda r: r.reverse(), lambda r: r[0].__setitem__("label", "unknown")]
        for change in changes:
            rows = copy.deepcopy(self.rows)
            change(rows)
            with self.assertRaises(ValueError):
                centroids.validate_rows(rows, self.writers, self.vocabulary)
        with self.assertRaises(ValueError):
            centroids.validate_rows(self.rows, ["tst_UPV_W00"] + self.writers[1:], self.vocabulary)
        with self.assertRaises(ValueError):
            centroids.validate_rows(self.rows, self.writers, self.vocabulary[::-1])

    def test_role_manifest_requires_exact_extra_planner_key_values_and_current_code(self):
        expected = {"encoderFitWriters": self.writers, "generator": "fitA", "sourceIndices": {"metaFit": [1, 2]}}
        planner = {name: "d" * 64 for name in centroids.PLANNER_FILES}
        roles = {**copy.deepcopy(expected), "plannerCodeSHA256": planner.copy()}
        with patch.object(centroids, "inner_roles", return_value=expected), \
                patch.object(centroids, "planner_code_identity", return_value=planner):
            centroids.validate_role_manifest({}, [], roles)
            mutations = [lambda r: r.pop("plannerCodeSHA256"), lambda r: r.__setitem__("unexpected", True),
                         lambda r: r.__setitem__("generator", "fitB"),
                         lambda r: r["plannerCodeSHA256"].pop(centroids.PLANNER_FILES[1]),
                         lambda r: r["plannerCodeSHA256"].__setitem__(centroids.PLANNER_FILES[0], "e" * 64),
                         lambda r: r["sourceIndices"]["metaFit"].reverse()]
            for mutate in mutations:
                changed = copy.deepcopy(roles)
                mutate(changed)
                with self.assertRaises(ValueError):
                    centroids.validate_role_manifest({}, [], changed)

    def test_source_fingerprints_match_order_and_retain_unavailable_raw_rows(self):
        reference = copy.deepcopy(self.rows)
        for i, row in enumerate(reference):
            row.update(generator="fitB", storedFailure="unavailable" if i < 12 else None)
        rows = centroids.match_source_rows(self.samples, ["a" * 64] * 3104, reference, self.writers, self.vocabulary)
        self.assertEqual(rows, self.rows)
        self.assertEqual(len(rows), 3104)
        for key in ("rawRasterSHA256", "trajectorySHA256", "sourceID"):
            bad = copy.deepcopy(reference)
            bad[3][key] = "b" * 64
            with self.assertRaises(ValueError):
                centroids.match_source_rows(self.samples, ["a" * 64] * 3104, bad, self.writers, self.vocabulary)

    def test_session_balanced_float64_means_match_independent_arithmetic(self):
        features = self.features.copy()
        for i, row in enumerate(self.rows):
            if row["session"] == 2:
                features[i, :2] = (0, 1)
        actual = centroids.session_balanced_centroids(features, self.rows, self.writers, self.vocabulary)
        expected = np.zeros((97, 128), dtype=np.float64)
        expected[:, :2] = 1 / np.sqrt(2)
        self.assertEqual(actual.dtype, np.float64)
        np.testing.assert_array_equal(actual, expected)
        # Every raw row contributes, including the original stored-unavailable rows.
        features[:12, :2] = (0, 1)
        shifted = centroids.session_balanced_centroids(features, self.rows, self.writers, self.vocabulary)
        self.assertFalse(np.array_equal(shifted, actual))

    def test_centroid_rejects_zero_nonfinite_nonunit_and_wrong_shape(self):
        zero = self.features.copy()
        for i, row in enumerate(self.rows):
            zero[i, 0] = 1 if row["session"] == 1 else -1
        nan = self.features.copy()
        nan[0, 0] = np.nan
        for bad in (zero, nan, self.features * 2, self.features.astype(np.float64), self.features[:-1]):
            with self.assertRaises(ValueError):
                centroids.session_balanced_centroids(bad, self.rows, self.writers, self.vocabulary)

    def checkpoint_fixture(self):
        with torch.random.fork_rng(devices=[]):
            torch.manual_seed(29)
            model = centroids.PersonalVisualEncoder(97)
        digest = _state_digest(model.state_dict())
        receipt = {"folds": {"A": self.writers, "B": [f"trn_UPV_W{i:02d}" for i in range(16, 32)]},
            "vocabulary": self.vocabulary, "initialStateSHA256": digest, "finalStateSHA256": {"fitA": digest}}
        checkpoint = {"version": centroids.crossfit.VERSION, "arm": "fitA", "finalEpoch": 30,
            "sourceSHA256": SOURCE_SHA256, "protocolSHA256": centroids.crossfit.PROTOCOL_SHA256,
            "initialStateSHA256": digest, "fitWriters": receipt["folds"]["A"],
            "exportWriters": receipt["folds"]["B"], "vocabulary": self.vocabulary, "state_dict": model.state_dict()}
        return receipt, checkpoint

    def test_checkpoint_validates_metadata_schema_finiteness_digest_and_freezes_model(self):
        receipt, checkpoint = self.checkpoint_fixture()
        rng = torch.get_rng_state().clone()
        model = centroids.validate_checkpoint(checkpoint, receipt)
        self.assertTrue(torch.equal(rng, torch.get_rng_state()))
        self.assertFalse(model.training)
        self.assertTrue(all(not p.requires_grad for p in model.parameters()))
        mutations = [lambda c: c.__setitem__("arm", "fitB"), lambda c: c.__setitem__("extra", 1),
                     lambda c: c["fitWriters"].reverse(),
                     lambda c: c["state_dict"].__setitem__("classifier.bias", torch.ones(96)),
                     lambda c: c["state_dict"]["classifier.bias"].fill_(float("inf")),
                     lambda c: c["state_dict"]["classifier.bias"].add_(1)]
        for mutation in mutations:
            changed = copy.deepcopy(checkpoint)
            mutation(changed)
            with self.assertRaises(ValueError):
                centroids.validate_checkpoint(changed, receipt)

    def test_loader_requires_receipt_pin_data_binding_and_reconstructs_centroids(self):
        roles = {"encoderFitWriters": self.writers, "generator": "fitA", "generatorWeightsSHA256": centroids.WEIGHTS_SHA256}
        parent = {"fit-receipt.json": centroids.core.RECEIPT_SHA256, "weights/fitA.pt": centroids.WEIGHTS_SHA256}
        code = {"synthetic-code": "e" * 64}
        vectors = centroids.session_balanced_centroids(self.features, self.rows, self.writers, self.vocabulary)
        files = {"centroids.npz": centroids._npz(centroids=vectors), "training-features.npz": centroids._npz(features=self.features),
                 "training-rows.json": canonical({"vocabulary": self.vocabulary, "rows": self.rows})}
        receipt = {"version": centroids.VERSION, "vocabulary": self.vocabulary, "parentBinding": parent,
            "roleManifestSHA256": sha(canonical(roles)), "generator": "fitA", "generatorWeightsSHA256": centroids.WEIGHTS_SHA256,
            "generatorStateSHA256": centroids.STATE_SHA256,
            "runtime": {"python": platform.python_version(), "torch": str(torch.__version__), "numpy": str(np.__version__),
                        "cpuThreads": 4, "deterministicAlgorithms": True},
            "encoderFitWriters": self.writers, "sourceCount": 3104, "countPerLabel": 32, "codeSHA256": code,
            "sourceSHA256": SOURCE_SHA256, "inSampleTrainingCentroids": True, "privateInkUsed": False,
            "developmentOrReservedInferred": False, "productionEligible": False, "sourceAndEncoderUnchanged": True,
            "storedUnavailableRawRowsRetained": 12, "dataSHA256": sha(files["centroids.npz"]),
            "trainingFeaturesSHA256": sha(files["training-features.npz"]), "trainingRowsSHA256": sha(files["training-rows.json"])}
        payload = canonical(receipt)
        files["centroid-receipt.json"] = payload
        with tempfile.TemporaryDirectory() as temporary, patch.object(centroids, "code_identity", return_value=code), \
                patch.object(centroids, "MANIFEST_SHA256", sha(canonical(roles))):
            directory = Path(temporary).resolve()
            for name, blob in files.items():
                (directory / name).write_bytes(blob)
            actual, saved = centroids.load_frozen_centroids(directory, parent, roles, self.vocabulary, receipt_sha256=sha(payload))
            self.assertEqual(saved, receipt)
            self.assertEqual(actual.dtype, torch.float64)
            np.testing.assert_array_equal(actual.numpy(), vectors)
            with self.assertRaises(ValueError):
                centroids.load_frozen_centroids(directory, parent, roles, self.vocabulary, receipt_sha256="0" * 64)
            changed = copy.deepcopy(receipt)
            changed["generatorStateSHA256"] = "0" * 64
            (directory / "centroid-receipt.json").write_bytes(canonical(changed))
            with self.assertRaises(ValueError):
                centroids.load_frozen_centroids(directory, parent, roles, self.vocabulary, receipt_sha256=sha(canonical(changed)))
            (directory / "centroid-receipt.json").write_bytes(payload)
            (directory / "centroids.npz").write_bytes(centroids._npz(centroids=vectors * -1))
            with self.assertRaises(ValueError):
                centroids.load_frozen_centroids(directory, parent, roles, self.vocabulary, receipt_sha256=sha(payload))


if __name__ == "__main__":
    unittest.main()
