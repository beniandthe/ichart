"""Synthetic adapter/chronology checks; no source or fitted model access."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ichart_recognition_ml.research import personal_unoriented_hwrt_evaluate as n
from ichart_recognition_ml.research import personal_hwrt_stroke_evaluate as old
from test_personal_hwrt_stroke_evaluate import VOCABULARY, ALLOWED, OLD_ALLOWED, TinyModel, blind_rows, rows


def fixture_receipts(state=n.CONTROL_STATE):
    fit = {"version": n.FIT_VERSION, "fieldVersion": n.FIELD_VERSION, "modelVersion": n.MODEL_VERSION,
           "protocolSHA256": n.PROTOCOL_SHA256, "codeSHA256": {}, "vocabulary": VOCABULARY,
           "dataReceiptSHA256": "a" * 64, "weightsSHA256": {a: "b" * 64 for a in n.ARMS},
           "finalStateSHA256": {a: state for a in n.ARMS},
           "augmentationLedger": {"rasterControl": {"scheduleSHA256": n.CONTROL_SCHEDULE,
                                                   "augmentationDrawStreamSHA256": n.CONTROL_AFFINE}}}
    pin = n.sha(n.canonical(fit))
    receipt = {"version": n.DATA_VERSION, "role": "development", "fieldVersion": n.FIELD_VERSION,
               "protocolSHA256": n.PROTOCOL_SHA256, "fitReceiptSHA256": pin, "codeSHA256": {},
               "trainingDataReceiptSHA256": "a" * 64, "sourceBindings": {"domain": {"sha256": n.DOMAIN_SHA256}},
               "vocabulary": VOCABULARY}
    return fit, receipt, pin


def full_rows():
    output = old.result([1.] + [0.] * 127, [1.] + [0.] * 101, VOCABULARY, ALLOWED)
    return [{**r, "results": {a: dict(output) for a in n.ARMS}} for r in blind_rows()]


def prior_packet(frozen):
    return {"version": old.VERSION, "protocolSHA256": n.OLD_PROTOCOL_SHA256,
            "vocabulary": VOCABULARY, "allowedLabels": ALLOWED,
            "rows": [{**r, "fieldSHA256": "f" * 64} for r in frozen]}


class NeutralEvaluationTests(unittest.TestCase):
    def test_neutral_versions_and_all_predevelopment_control_sentinels_fail_closed(self):
        fit, receipt, pin = fixture_receipts()
        n.validate_receipts(receipt, fit, pin, {}, {})
        cases = (("version", old.VERSION), ("fieldVersion", "personal-stroke-field-v1"),
                 ("protocolSHA256", n.OLD_PROTOCOL_SHA256))
        for key, value in cases:
            with self.subTest(key=key):
                bad = copy.deepcopy(receipt); bad[key] = value
                with self.assertRaises(ValueError): n.validate_receipts(bad, fit, pin, {}, {})
        for key, value in (("version", "personal-hwrt-stroke-field-fit-v1"),
                           ("modelVersion", "personal-stroke-field-encoder-v1-97-or-102")):
            bad = copy.deepcopy(fit); bad[key] = value; changed = n.sha(n.canonical(bad))
            r = copy.deepcopy(receipt); r["fitReceiptSHA256"] = changed
            with self.assertRaises(ValueError): n.validate_receipts(r, bad, changed, {}, {})
        for key in ("state", "scheduleSHA256", "augmentationDrawStreamSHA256"):
            bad = copy.deepcopy(fit)
            if key == "state": bad["finalStateSHA256"]["rasterControl"] = "f" * 64
            else: bad["augmentationLedger"]["rasterControl"][key] = "f" * 64
            changed = n.sha(n.canonical(bad)); r = copy.deepcopy(receipt); r["fitReceiptSHA256"] = changed
            with self.assertRaises(ValueError): n.validate_receipts(r, bad, changed, {}, {})
        inputs = {"version": n.INPUT_VERSION, "vocabulary": VOCABULARY, "rows": blind_rows()}
        n.validate_inputs(inputs)
        inputs["version"] = "personal-hwrt-stroke-field-development-inputs-v1"
        with self.assertRaises(ValueError): n.validate_inputs(inputs)

    def test_control_parity_is_exact_full_output_and_label_free_source_alignment(self):
        frozen = full_rows(); prior = prior_packet(frozen)
        self.assertTrue(n.control_parity(frozen, prior, VOCABULARY, ALLOWED)["equalFullOutputs"])
        # A nonwinning logit changes while top one remains equal: still reject.
        changed = copy.deepcopy(frozen); changed[0]["results"]["rasterControl"]["rawLogits"][100] = .001
        with self.assertRaises(ValueError): n.control_parity(changed, prior, VOCABULARY, ALLOWED)
        changed = copy.deepcopy(frozen); changed[0]["results"]["rasterControl"]["embedding"][1] = .001
        with self.assertRaises(ValueError): n.control_parity(changed, prior, VOCABULARY, ALLOWED)
        for key in ("opaqueID", "rasterSHA256", "normalizedGeometrySHA256"):
            changed = copy.deepcopy(frozen); changed[0][key] = "9" * 64
            with self.assertRaises(ValueError): n.control_parity(changed, prior, VOCABULARY, ALLOWED)
        self.assertNotEqual(frozen[0]["fieldSHA256"], prior["rows"][0]["fieldSHA256"])

    def test_new_truth_copy_union_has_variable_denominator_and_old_truth_is_rejected(self):
        source = rows()
        for row in source[:9]: row["copyReasons"] = ["training-fieldSHA256"]
        union = {"version": n.COPY_VERSION, "hashFields": ["rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"],
                 "representativeRule": "lexicographically-smallest-opaqueID-per-development-hash",
                 "affectedOpaqueIDs": sorted(r["opaqueID"] for r in source[:9]), "reasonCounts": {"training-fieldSHA256": 9},
                 "trainingDataReceiptSHA256": "a" * 64}
        truth = {"version": n.TRUTH_VERSION, "rows": [{k: v for k, v in r.items() if k != "results"} for r in source], "copyUnion": union}
        packet = {"vocabulary": VOCABULARY, "rows": [{k: r[k] for k in n.BLIND_FIELDS | {"results"}} for r in source]}
        joined = n.join_truth(packet, truth)
        self.assertEqual(len(joined), 1987)
        self.assertEqual(old.summarize([r for r in joined if not r["copyReasons"]], OLD_ALLOWED)["uji"]["count"], 1543)
        self.assertEqual(old.summarize(joined, OLD_ALLOWED)["uji"]["count"], 1552)
        for target, key, value in (("truth", "version", "personal-hwrt-stroke-field-development-truth-v1"),
                                   ("union", "version", "personal-hwrt-stroke-field-input-copy-union-v1")):
            bad = copy.deepcopy(truth); (bad if target == "truth" else bad["copyUnion"])[key] = value
            with self.assertRaises(ValueError): n.join_truth(packet, bad)
        bad = copy.deepcopy(truth); bad["copyUnion"]["affectedOpaqueIDs"] = []
        with self.assertRaises(ValueError): n.join_truth(packet, bad)

    def test_inherited_metric_gates_failures_and_no_promotion_are_unchanged(self):
        original_protocol = old.PROTOCOL_SHA256
        source = rows(); view = old.summarize(source, OLD_ALLOWED)
        self.assertTrue(old.fixed_screen(view, raw=True)["passes"])
        source[0]["results"]["strokeField"] = {"rawTop1": None, "domainTop1": None, "failure": "synthetic-invalid"}
        invalid = old.summarize(source, OLD_ALLOWED)
        self.assertEqual(invalid["uji"]["count"], 1552)
        self.assertFalse(old.fixed_screen(invalid, raw=True)["passes"])
        values = [0.] * 102; values[50] = 2; values[0] = 1
        self.assertIsNone(old.result([1.] + [0.] * 127, values, VOCABULARY, ALLOWED)["domainTop1"])
        self.assertEqual(old.PROTOCOL_SHA256, original_protocol)

    def test_predictor_real_digest_seam_truth_isolation_and_score_authentication_first(self):
        from ichart_recognition_ml.research import personal_unoriented_hwrt_data as data, personal_unoriented_hwrt_train as train
        self.assertTrue(callable(train._state_digest))  # real cross-module export, not a fabricated alias.
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve(); data_dir = directory / "data"; data_dir.mkdir(); fit_dir = directory / "fit"; fit_dir.mkdir()
            models = {a: TinyModel().eval() for a in n.ARMS}
            state = train._state_digest(models["rasterControl"].state_dict())
            fit, receipt, fit_sha = fixture_receipts(state)
            frozen = full_rows(); prior = prior_packet(frozen)
            inputs = {"version": n.INPUT_VERSION, "vocabulary": VOCABULARY, "rows": blind_rows()}
            domain = {"version": "chord-recognition-domain-v1", "vocabulary": VOCABULARY[:97], "allowedLabels": OLD_ALLOWED}
            domain_sha = n.write_exclusive(directory / "domain.json", domain, ())
            receipt["sourceBindings"]["domain"]["sha256"] = domain_sha
            receipt["artifacts"] = {"inputs.json": {"bytes": len(n.canonical(inputs)), "sha256": n.sha(n.canonical(inputs))},
                                    "fields.npy": {"bytes": 1, "sha256": "d" * 64}, "truth.json": {"bytes": 1, "sha256": "e" * 64}}
            receipt_sha = n.write_exclusive(data_dir / "data-receipt.json", receipt, ())
            n.write_exclusive(data_dir / "inputs.json", inputs, ())
            prior_sha = n.write_exclusive(directory / "prior.json", prior, ())
            events = []
            def load_models(*args): events.append("final-models"); return models, fit
            def load_inputs(*args): events.append("blind-inputs"); return None, inputs, receipt
            original = Path.read_bytes
            def guarded(path):
                self.assertNotIn(path.name, ("truth.json", "training.json", "selected_records.jsonl"))
                return original(path)
            with patch.object(Path, "read_bytes", guarded), patch.object(n, "CONTROL_STATE", state), \
                 patch.object(n, "DOMAIN_SHA256", domain_sha), patch.object(n, "PRIOR_PREDICTIONS_SHA256", prior_sha), \
                 patch.object(n, "code_identity", return_value={}), patch.object(data, "code_identity", return_value={}), \
                 patch.object(train, "load_fitted_models", side_effect=load_models), \
                 patch.object(data, "load_development_inputs", side_effect=load_inputs), patch.object(n, "freeze_forward", return_value=frozen):
                output = directory / "predictions.json"
                prediction_sha = n.predict(data_dir, fit_dir, directory / "domain.json", directory / "prior.json", output,
                                           data_receipt_sha256=receipt_sha, fit_receipt_sha256=fit_sha)
                packet, _ = n.read_json(output, prediction_sha)
                self.assertEqual(events, ["final-models", "blind-inputs", "final-models", "blind-inputs"])
                n.validate_packet(packet, receipt, inputs, prior)
                with self.assertRaises(ValueError):
                    n.score(output, data_dir, directory / "prior.json", directory / "score.json",
                            predictions_sha256="0" * 64, data_receipt_sha256=receipt_sha)
                bad = copy.deepcopy(packet); bad["fieldVersion"] = "personal-stroke-field-v1"
                bad_sha = n.write_exclusive(directory / "bad.json", bad, ())
                with self.assertRaises(ValueError):
                    n.score(directory / "bad.json", data_dir, directory / "prior.json", directory / "score.json",
                            predictions_sha256=bad_sha, data_receipt_sha256=receipt_sha)
                self.assertFalse((directory / "score.json").exists())
                with self.assertRaises(ValueError): n.write_exclusive(output, {}, ())
                self.assertEqual(n.sha(output.read_bytes()), prediction_sha)


if __name__ == "__main__":
    unittest.main()
