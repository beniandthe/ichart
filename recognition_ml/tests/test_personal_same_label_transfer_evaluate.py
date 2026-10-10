import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_same_label_transfer_evaluate as e
from ichart_recognition_ml.research import personal_domain_reject_data as data
from ichart_recognition_ml.research import personal_same_label_transfer_train as train
from test_personal_domain_reject_data import complete_parent_rows, vocabulary
from test_personal_domain_reject_evaluate import good_rows, Tiny


VOCAB = e.core.make_vocabulary(vocabulary(), vocabulary()[:41])


def output(index=50):
    logits = [0.] * 102; logits[index] = 2
    return e.parent.result([1.] + [0.] * 127, logits, "control", VOCAB)


def fingerprint(key):
    return {"opaqueID": e.sha(f"id/{key}".encode()), "rasterSHA256": e.sha(f"raster/{key}".encode()),
            "normalizedGeometrySHA256": e.sha(f"geometry/{key}".encode())}


def renamed_rows():
    return [{**r, "results": {"control": r["results"]["control"], "sameLabelTransfer": r["results"]["domainReject"]}} for r in good_rows()]


class SameLabelTransferEvaluationTests(unittest.TestCase):
    def test_both102_heads_preserve_first_argmax_forbidden_ties_and_full_vectors(self):
        for index in range(102):
            current = output(index); e.validate_output(current, VOCAB)
            self.assertEqual(current["rawTop1"], VOCAB.source_labels[index])
            self.assertEqual(current["domainTop1"], VOCAB.source_labels[index] if VOCAB.source_labels[index] in VOCAB.legal_labels else None)
        logits = [0.] * 102; logits[50] = 3; logits[0] = 2
        self.assertIsNone(e.parent.result([1.] + [0.] * 127, logits, "control", VOCAB)["domainTop1"])
        logits[0] = 3
        self.assertEqual(e.parent.result([1.] + [0.] * 127, logits, "control", VOCAB)["domainTop1"], "L000")
        for mutate in (lambda v: v.update(rawLogits=[0.] * 47), lambda v: v.update(embedding=[0.] * 128),
                       lambda v: v["rawLogits"].__setitem__(0, float("nan")), lambda v: v.update(domainTop1="L000")):
            changed = output(); mutate(changed)
            with self.assertRaises(ValueError): e.validate_output(changed, VOCAB)

    def test_candidate_forward_keeps_baseline_exact_and_retains_nonfinite_rows(self):
        rasters = np.zeros((2, 1, 96, 256), dtype=np.float32)
        blind = [{**fingerprint(i), "rasterSHA256": e.sha(bytes(96 * 256))} for i in range(2)]
        old = [{**r, "results": {"control": output(), "domainReject": {"mustNotBeUsed": True}}} for r in blind]
        model = Tiny("control", invalid=True).eval(); initial = train.state_digest(model.state_dict())
        rows = e.freeze_forward(model, rasters, {"rows": blind}, VOCAB, old, batch_size=2)
        self.assertEqual([r["results"]["control"] for r in rows], [r["results"]["control"] for r in old])
        self.assertTrue(all(set(r["results"]) == set(e.ARMS) for r in rows))
        self.assertIsNotNone(rows[0]["results"]["sameLabelTransfer"]["failure"])
        self.assertIsNone(rows[1]["results"]["sameLabelTransfer"]["failure"])
        self.assertEqual(initial, train.state_digest(model.state_dict())); self.assertFalse(rasters.any())

    def test_common_union_includes_new_actual_fit_without_label_inputs(self):
        original = {"rows": [fingerprint("old")]}; added = fingerprint("added")
        candidate = {"version": e.FINGERPRINT_VERSION, "fold": e.FOLDS[0], "rows": [*original["rows"], added]}
        merged = e.merge_fingerprints(original, candidate, e.FOLDS[0])
        query = [fingerprint("query0"), fingerprint("query1"), fingerprint("query2")]
        query[0]["rasterSHA256"] = added["rasterSHA256"]
        query[2]["normalizedGeometrySHA256"] = query[1]["normalizedGeometrySHA256"]
        union = e.common_union(query, merged)
        self.assertEqual(union["version"], e.COPY_VERSION)
        self.assertIn("fit-rasterSHA256", union["rows"][0]["reasons"])
        self.assertEqual(len(union["affectedOpaqueIDs"]), 2)
        self.assertNotIn("label", str(union["rows"]))
        old_union = e.parent.copy_union(query, original["rows"])
        self.assertNotIn(query[0]["opaqueID"], old_union["affectedOpaqueIDs"])
        for change in (lambda v: v["rows"].pop(0), lambda v: v["rows"].append(v["rows"][0]),
                       lambda v: v["rows"][0].update(label="L000"), lambda v: v.update(version="old-fingerprints")):
            bad = copy.deepcopy(candidate); change(bad)
            with self.assertRaises(ValueError): e.merge_fingerprints(original, bad, e.FOLDS[0])

    def test_parent_gate_arithmetic_paired_denominators_and_all97_class_reports(self):
        rows = renamed_rows(); value = e.view(rows, ["w0", "w1"], VOCAB)
        previous = e.parent.view(good_rows(), ["w0", "w1"], VOCAB.legal_labels)
        self.assertEqual(e.fixed_screen(value), e.parent.fixed_screen(previous))
        self.assertTrue(e.fixed_screen(value)["passes"])
        self.assertEqual(len(value["classes"]), 97)
        self.assertEqual(sum(v["count"] for v in value["classes"].values()), value["uji"]["count"])
        self.assertEqual(set(value["safety"]), {"invalid", "newCorrectOrUnresolvedToWrongLegal"})
        changes = {
            "completeFiniteOutputs": lambda v: v["safety"]["invalid"].update(sameLabelTransfer=1),
            "strictlyMoreCorrectLegalUJI": lambda v: v["ujiLegal"]["arms"]["sameLabelTransfer"].update(correct=1),
            "fewerTotalWrongLegalUJI": lambda v: v["uji"]["arms"]["sameLabelTransfer"].update(wrongLegal=2),
            "everyQueryWriterCorrectNonWorse": lambda v: v["writers"]["w1"]["arms"]["sameLabelTransfer"].update(correct=0),
            "zeroNewCorrectOrUnresolvedToWrongLegal": lambda v: v["safety"].update(newCorrectOrUnresolvedToWrongLegal=1),
            "everyMappedHWRTClassCorrectNonWorse": lambda v: v["mappedClasses"]["#"]["arms"]["sameLabelTransfer"].update(correct=0),
        }
        for gate, change in changes.items():
            broken = copy.deepcopy(value); change(broken)
            self.assertFalse(e.fixed_screen(broken)["checks"][gate], gate)
        no_copy = e.view(rows[1:], ["w0", "w1"], VOCAB)
        self.assertEqual(value["uji"]["count"] - no_copy["uji"]["count"], 1)
        self.assertFalse(e.fixed_screen(no_copy)["passes"])
        rows[0]["results"]["sameLabelTransfer"] = {"failure": "retained", "domainTop1": None}
        self.assertEqual(e.view(rows, ["w0", "w1"], VOCAB)["uji"]["count"], 3)
        self.assertFalse(e.fixed_screen(e.view(rows, ["w0", "w1"], VOCAB))["passes"])

    def test_full_source_join_uses_new_common_mask_not_parent_mask(self):
        rows = complete_parent_rows(); _, indexes = data._split_rows(rows); fold = e.FOLDS[0]
        originals = {"rows": [data._blind_row(rows[i]) for i in indexes[fold]["fit"]]}
        labeled = [data._project_row(rows[i]) for i in indexes[fold]["query"]]
        blind = [data._blind_row(r) for r in labeled]
        original_union = e.parent.copy_union(blind, originals["rows"])
        truth = {"version": data.QUERY_TRUTH_VERSION, "fold": fold,
                 "rows": [{**r, "copyReasons": []} for r in labeled],
                 "copyUnion": {k: v for k, v in original_union.items() if k != "rows"}}
        added = {**fingerprint("added"), "rasterSHA256": blind[0]["rasterSHA256"]}
        frozen = {"rows": [{**r, "results": {a: {"failure": None, "domainTop1": None} for a in e.ARMS}} for r in blind],
                  "copyUnion": e.common_union(blind, [*originals["rows"], added])}
        joined, writers = e.join_truth(fold, frozen, truth, VOCAB, originals)
        self.assertEqual(len(joined), 3874); self.assertEqual(len(writers), 16)
        self.assertEqual(len([r for r in joined if r["copyReasons"]]), 1)
        self.assertEqual(joined[0]["copyReasons"], ["fit-rasterSHA256"])
        self.assertEqual(truth["rows"][0]["copyReasons"], [])
        bad = copy.deepcopy(truth); bad["rows"][0]["label"] = "REJECT"
        with self.assertRaises(ValueError): e.join_truth(fold, frozen, bad, VOCAB, originals)

    def test_preinference_manifest_and_score_hash_precede_truth(self):
        from ichart_recognition_ml.research import personal_domain_reject_data as source
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); data_dir = root / "data"; fit_dir = root / "fit"
            data_dir.mkdir(); fit_dir.mkdir(); baseline_path = root / "baseline.json"; prediction_path = root / "predictions.json"
            inputs = {f: {"version": source.QUERY_INPUTS_VERSION, "fold": f, "vocabulary": list(VOCAB.source_labels),
                          "rows": [fingerprint(f + str(i)) for i in range(2)]} for f in e.FOLDS}
            originals = {f: {"rows": [fingerprint("fit-old")]} for f in e.FOLDS}
            candidates = {f: {"version": e.FINGERPRINT_VERSION, "fold": f, "rows": originals[f]["rows"]} for f in e.FOLDS}
            baseline_fit = {"weights": {f: {"control": {"path": "old-control.pt", "sha256": "a" * 64}} for f in e.FOLDS}}
            baseline = {"fitReceipt": baseline_fit, "folds": {f: {"rows": [{**r, "results": {"control": output(), "domainReject": {"unused": True}}} for r in inputs[f]["rows"]]} for f in e.FOLDS}}
            baseline_path.write_bytes(e.canonical(baseline))
            receipt = {"artifacts": {e.parent.fold_path(f, name): {"sha256": "b" * 64} for f in e.FOLDS for name in ("query-inputs.json", "query-rasters.npy", "fit-fingerprints.json")}}
            (data_dir / "data-receipt.json").write_bytes(e.canonical(receipt))
            models = {f: Tiny("control").eval() for f in e.FOLDS}
            fit = {"codeSHA256": {"test": "c" * 64}, "weights": {f: {"path": "candidate.pt", "sha256": "d" * 64} for f in e.FOLDS},
                   "finalStateSHA256": {f: train.state_digest(m.state_dict()) for f, m in models.items()},
                   "fitFingerprints": {f: {"path": "safe.json", "sha256": e.sha(e.canonical(candidates[f]))} for f in e.FOLDS}}
            events = []; original_open = Path.open
            def guarded_open(path, *args, **kwargs):
                if path.name in {"query-truth.json", "fit.json", "eligibility.json", "selected-ids.json", "encoded.json"}:
                    self.fail(f"Truth or labeled fitting artifact opened: {path}")
                return original_open(path, *args, **kwargs)
            def load_models(*args): events.append("both-final-candidates"); return models, fit
            def load_query(_, fold): events.append("blind-inputs"); return np.zeros((2, 1, 96, 256), np.float32), inputs[fold], receipt
            def load_common(_, __, fold, *args):
                return originals[fold], candidates[fold], e.canonical(candidates[fold]), originals[fold]["rows"]
            def forward(_, __, current, ___, prior):
                events.append("candidate-forward")
                manifest_path = prediction_path.with_name("predictions-input-manifest.json")
                manifest, _ = e.read_json(manifest_path)
                self.assertEqual(manifest["weights"], fit["weights"])
                self.assertTrue(all(manifest["folds"][f]["copyUnion"] for f in e.FOLDS))
                return [{**r, "results": {"control": old["results"]["control"], "sameLabelTransfer": e.parent.failed(ValueError("retained"))}} for r, old in zip(current["rows"], prior)]
            with patch.object(e, "PARENT_DATA_SHA256", e.sha(e.canonical(receipt))), patch.object(e, "BASELINE_SHA256", e.sha(e.canonical(baseline))), \
                 patch.object(e, "EXPOSURES", 4), patch.object(e, "DISTINCT_DRAWINGS", 4), patch.object(e, "validate_fit", return_value=VOCAB), \
                 patch.object(e, "validate_baseline"), patch.object(source, "_validate_receipt"), patch.object(source, "load_query", side_effect=load_query), \
                 patch.object(train, "load_fitted_models", side_effect=load_models), patch.object(e, "load_common_fingerprints", side_effect=load_common), \
                 patch.object(e, "code_identity", return_value=fit["codeSHA256"]), patch.object(e, "freeze_forward", side_effect=forward), patch.object(Path, "open", guarded_open):
                digest = e.predict(data_dir, fit_dir, baseline_path, prediction_path, fit_receipt_sha256="e" * 64)
                packet, payload = e.read_json(prediction_path, digest)
                self.assertEqual(events[:3], ["both-final-candidates", "blind-inputs", "blind-inputs"])
                frozen_manifest_path = e.manifest_path(prediction_path, packet)
                self.assertEqual(packet["inputManifestPath"], "predictions-input-manifest.json")
                manifest, manifest_bytes = e.read_json(frozen_manifest_path, packet["inputManifestSHA256"])
                self.assertEqual(e.sha(manifest_bytes), packet["inputManifestSHA256"])
                self.assertEqual(manifest["version"], e.MANIFEST_VERSION)
                with self.assertRaises(ValueError): e.score(prediction_path, data_dir, baseline_path, root / "score.json", predictions_sha256="0" * 64)
                with self.assertRaises(ValueError): e.write_exclusive(frozen_manifest_path, manifest)
                self.assertEqual(prediction_path.read_bytes(), payload)
                archive = root / "archive"; archive.mkdir()
                archived_prediction = archive / prediction_path.name
                archived_prediction.write_bytes(payload)
                (archive / frozen_manifest_path.name).write_bytes(manifest_bytes)
                archived_packet, archived_bytes = e.read_json(archived_prediction, digest)
                self.assertEqual(archived_bytes, payload)
                self.assertEqual(e.read_json(e.manifest_path(archived_prediction, archived_packet), packet["inputManifestSHA256"])[1], manifest_bytes)
                for forbidden in (str(frozen_manifest_path), "../predictions-input-manifest.json", "other.json"):
                    with self.assertRaises(ValueError): e.manifest_path(archived_prediction, {**packet, "inputManifestPath": forbidden})


if __name__ == "__main__":
    unittest.main()
