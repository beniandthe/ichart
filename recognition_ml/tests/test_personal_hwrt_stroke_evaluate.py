import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_hwrt_stroke_evaluate as e


VOCABULARY = [f"old{i:02}" for i in range(97)] + list(e.NOVEL)
OLD_ALLOWED = VOCABULARY[:41]
ALLOWED = OLD_ALLOWED + list(e.NOVEL)


def outputs(label, *, bad=False):
    return {a: {"rawTop1": label, "domainTop1": label if label in ALLOWED else None,
                "failure": "synthetic-invalid" if bad else None} for a in e.ARMS}


def rows():
    """Complete source-shaped synthetic grid; not public or private ink."""
    result = []
    for writer in e.WRITERS:
        for session in (1, 2):
            for index, label in enumerate(VOCABULARY[:97]):
                predicted = label if index < 80 else VOCABULARY[96]
                row = {"opaqueID": e.sha(f"{writer}/{session}/{label}".encode()), "source": "uji",
                       "label": label, "writer": writer, "session": session, "nativeSymbolID": None,
                       "copyReasons": [], "results": outputs(predicted), "rasterSHA256": "1" * 64,
                       "normalizedGeometrySHA256": "2" * 64, "fieldSHA256": "3" * 64}
                if index == 0 and session == 1:
                    row["results"][e.ARMS[0]] = outputs(VOCABULARY[96])[e.ARMS[0]]
                result.append(row)
    for label, count in e.NOVEL_COUNTS.items():
        aliases = [i for i, (_, mapped) in e.NATIVE.items() if mapped == label]
        for index in range(count):
            row = {"opaqueID": e.sha(f"native/{label}/{index}".encode()), "source": "hwrt", "label": label,
                   "writer": None, "session": None, "nativeSymbolID": aliases[index % len(aliases)],
                   "copyReasons": [], "results": outputs(label), "rasterSHA256": "1" * 64,
                   "normalizedGeometrySHA256": "2" * 64, "fieldSHA256": "3" * 64}
            if label == "+" and index == 0:
                row["results"][e.ARMS[0]] = outputs("/")[e.ARMS[0]]
            result.append(row)
    return result


def blind_rows(count=1987):
    return [{"opaqueID": e.sha(f"blind/{i}".encode()), "rasterSHA256": "1" * 64,
             "fieldSHA256": "2" * 64, "normalizedGeometrySHA256": "3" * 64} for i in range(count)]


def empty_union():
    return {"version": "personal-hwrt-stroke-field-input-copy-union-v1", "trainingDataReceiptSHA256": "a" * 64,
            "hashFields": ["rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"],
            "representativeRule": "lexicographically-smallest-opaqueID-per-development-hash",
            "affectedOpaqueIDs": [], "reasonCounts": {}}


class TinyModel(torch.nn.Module):
    def __init__(self, invalid=False):
        super().__init__()
        self.register_buffer("unchanged", torch.tensor([1.]))
        self.invalid = invalid

    def forward(self, batch):
        features = torch.zeros(len(batch), 128); features[:, 0] = 1
        logits = torch.zeros(len(batch), 102); logits[:, 50] = 2; logits[:, 0] = 1
        if self.invalid:
            logits[0, 0] = float("nan")
        return features, logits


class HWRTStrokeEvaluationTests(unittest.TestCase):
    def test_actual_first_argmax_never_promotes_forbidden_runner_or_alias(self):
        logits = [0.] * 102; logits[50] = 3; logits[0] = 2
        self.assertEqual(e.projected(logits, VOCABULARY, ALLOWED), (VOCABULARY[50], None))
        logits[0] = 3  # exact tie chooses first raw index, not a domain re-ranking rule.
        self.assertEqual(e.projected(logits, VOCABULARY, ALLOWED), (VOCABULARY[0], VOCABULARY[0]))
        with self.assertRaises(ValueError):
            e.projected([True] * 102, VOCABULARY, ALLOWED)
        with self.assertRaises(ValueError):
            e.projected([0.] * 101, VOCABULARY, ALLOWED)
        self.assertNotEqual("△", "Δ")
        self.assertNotEqual("C", "c")

    def test_exact_256_sign_flip_counts_ties_zero_multiplicity_and_two_sides(self):
        self.assertEqual(e.sign_flip([0] * 8)["twoSidedP"], 1)
        self.assertEqual(e.sign_flip([1] + [0] * 7)["extremeAssignments"], 256)
        self.assertEqual(e.sign_flip([1] * 8)["extremeAssignments"], 2)
        self.assertEqual(e.sign_flip([-1] * 8)["twoSidedP"], 2 / 256)
        self.assertEqual(e.sign_flip([1, -1] + [0] * 6)["twoSidedP"], 1)
        with self.assertRaises(ValueError):
            e.sign_flip([1] * 7)

    def test_every_fixed_gate_and_raw_only_floor_is_explicit(self):
        view = e.summarize(rows(), OLD_ALLOWED)
        self.assertTrue(e.fixed_screen(view, raw=True)["passes"])
        modifications = {
            "completeFiniteOutputs": lambda v: v["uji"].update(invalidCandidate=1),
            "eligibleWriterAndClassCohorts": lambda v: v["mappedClasses"]["#"].update(count=0),
            "ujiGainsExceedHarms": lambda v: v["uji"].update(gains=0),
            "writerTwoSidedPBelowPoint05": lambda v: v["writerSignFlip"].update(twoSidedP=.05),
            "sixWritersNonWorse": lambda v: [x.update(net=-1) for x in list(v["writers"].values())[:3]],
            "noWriterNetBelowMinusTwo": lambda v: v["writers"][e.WRITERS[0]].update(net=-3),
            "oldDomainGainsExceedHarms": lambda v: v["oldDomain"].update(gains=0),
            "zeroNewOODPermittedTransitions": lambda v: v["ood"].update(controlNoReadToCandidatePermitted=1),
            "noIncreasedOODPermittedOutputs": lambda v: v["ood"]["permitted"].update(strokeField=1),
            "hwrtGainsExceedHarms": lambda v: v["hwrt"].update(gains=0),
            "everyNovelClassNonWorse": lambda v: v["mappedClasses"]["#"].update(net=-1),
            "rawCandidateUJIAtLeast1229": lambda v: v["uji"].update(candidateCorrect=1228),
        }
        for gate, change in modifications.items():
            with self.subTest(gate=gate):
                broken = copy.deepcopy(view); change(broken)
                self.assertFalse(e.fixed_screen(broken, raw=True)["checks"][gate])
                self.assertFalse(e.fixed_screen(broken, raw=True)["passes"])
        low = copy.deepcopy(view); low["uji"]["candidateCorrect"] = 1
        self.assertNotIn("rawCandidateUJIAtLeast1229", e.fixed_screen(low, raw=False)["checks"])
        self.assertTrue(e.fixed_screen(low, raw=False)["passes"])

    def test_copy_union_is_paired_and_cannot_hide_raw_failure_or_lost_signal(self):
        source = rows()
        raw = e.summarize(source, OLD_ALLOWED)
        for row in source:
            if row["source"] == "uji" and row["session"] == 1 and row["label"] == VOCABULARY[0]:
                row["copyReasons"] = ["training-raster", "training-normalized-geometry"]
        kept = [r for r in source if not r["copyReasons"]]
        no_copy = e.summarize(kept, OLD_ALLOWED)
        self.assertEqual(raw["uji"]["count"], 1552)
        self.assertEqual(no_copy["uji"]["count"], 1544)
        self.assertEqual(no_copy["uji"]["net"], 0)
        self.assertTrue(e.fixed_screen(raw, raw=True)["passes"])
        self.assertFalse(e.fixed_screen(no_copy, raw=False)["passes"])
        self.assertEqual(sum(v["count"] for v in no_copy["writers"].values()), 1544)
        raw["uji"]["candidateCorrect"] = 1228
        self.assertFalse(e.fixed_screen(raw, raw=True)["passes"])

    def test_invalid_rows_remain_denominator_and_alias_cohorts_are_fixed(self):
        source = rows(); source[0]["results"][e.ARMS[1]] = outputs(None, bad=True)[e.ARMS[1]]
        view = e.summarize(source, OLD_ALLOWED)
        self.assertEqual(view["uji"]["count"], 1552)
        self.assertEqual(view["uji"]["invalidCandidate"], 1)
        self.assertFalse(e.fixed_screen(view, raw=True)["passes"])
        self.assertEqual(set(view["nativeAliases"]), {str(i) for i in e.NATIVE})
        self.assertEqual(sum(v["count"] for v in view["nativeAliases"].values()), 435)
        self.assertEqual(sum(v["count"] for v in view["mappedClasses"].values()), 435)
        empty = e.summarize([], OLD_ALLOWED)
        self.assertEqual(len(empty["nativeAliases"]), 8)
        self.assertTrue(all(v["count"] == 0 for v in empty["nativeAliases"].values()))
        self.assertFalse(e.fixed_screen(empty, raw=False)["passes"])

    def test_synthetic_forward_retains_full_vectors_failure_and_unchanged_state(self):
        models = {e.ARMS[0]: TinyModel().eval(), e.ARMS[1]: TinyModel(invalid=True).eval()}
        fields = np.zeros((3, 5, 96, 256), dtype=np.float32)
        inputs = {"vocabulary": VOCABULARY, "rows": blind_rows(3)}
        for r in inputs["rows"]:
            r["fieldSHA256"] = e.sha(fields[0].tobytes())
            r["rasterSHA256"] = e.sha(bytes(96 * 256))
        frozen = e.freeze_forward(models, fields, inputs, ALLOWED, batch_size=2)
        self.assertEqual(len(frozen), 3)
        self.assertEqual(len(frozen[0]["results"][e.ARMS[0]]["embedding"]), 128)
        self.assertEqual(len(frozen[0]["results"][e.ARMS[0]]["rawLogits"]), 102)
        self.assertIsNone(frozen[0]["results"][e.ARMS[0]]["domainTop1"])
        self.assertIsNotNone(frozen[0]["results"][e.ARMS[1]]["failure"])
        self.assertIsNone(frozen[0]["results"][e.ARMS[1]]["rawTop1"])
        self.assertEqual(frozen[1]["results"][e.ARMS[1]]["failure"], None)
        self.assertTrue(all(torch.equal(m.unchanged, torch.tensor([1.])) for m in models.values()))
        self.assertEqual(e.freeze_forward({a: TinyModel().eval() for a in e.ARMS}, fields, inputs, ALLOWED),
                         e.freeze_forward({a: TinyModel().eval() for a in e.ARMS}, fields, inputs, ALLOWED))
        inputs["rows"][0]["fieldSHA256"] = "f" * 64
        with self.assertRaises(ValueError):
            e.freeze_forward(models, fields, inputs, ALLOWED)

    def test_bad_prediction_hash_or_binding_rejects_before_truth_is_opened(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            inputs = {"version": "personal-hwrt-stroke-field-development-inputs-v1", "vocabulary": VOCABULARY, "rows": blind_rows()}
            receipt = {"fitReceiptSHA256": "f" * 64, "artifacts": {"inputs.json": e.sha(e.canonical(inputs)),
                       "truth.json": "a" * 64, "fields.npy": "b" * 64}}
            e.write_exclusive(directory / "inputs.json", inputs)
            receipt_hash = e.write_exclusive(directory / "data-receipt.json", receipt)
            prediction_hash = e.write_exclusive(directory / "predictions.json", {"version": "wrong", "dataReceiptSHA256": receipt_hash})
            original = Path.read_bytes
            def guarded(path):
                self.assertNotEqual(path.name, "truth.json", "Truth opened before prediction validation")
                return original(path)
            with patch.object(Path, "read_bytes", guarded), patch.object(e, "code_identity", return_value={}):
                for pinned in ("0" * 64, prediction_hash):
                    with self.assertRaises(ValueError):
                        e.score(directory / "predictions.json", directory, directory / "score.json",
                                predictions_sha256=pinned, data_receipt_sha256=receipt_hash)
            self.assertFalse((directory / "score.json").exists())

    def test_exact_grid_row_set_and_exclusive_immutable_outputs(self):
        source = rows()
        truth = {"version": "personal-hwrt-stroke-field-development-truth-v1",
                 "rows": [{k: v for k, v in r.items() if k != "results"} for r in source], "copyUnion": empty_union()}
        packet = {"rows": [{k: r[k] for k in e.BLIND_FIELDS | {"results"}} for r in source], "vocabulary": VOCABULARY}
        self.assertEqual(len(e.join_truth(packet, truth)), 1987)
        broken = copy.deepcopy(truth); broken["rows"][0]["label"] = "OLD00"
        with self.assertRaises(ValueError):
            e.join_truth(packet, broken)
        broken = copy.deepcopy(truth); broken["copyUnion"]["affectedOpaqueIDs"] = [source[0]["opaqueID"]]
        with self.assertRaises(ValueError):
            e.join_truth(packet, broken)
        broken = copy.deepcopy(truth); broken["rows"][0]["fieldSHA256"] = "a" * 64
        with self.assertRaises(ValueError):
            e.join_truth(packet, broken)
        broken = copy.deepcopy(truth); broken["rows"][0]["opaqueID"] = broken["rows"][1]["opaqueID"]
        with self.assertRaises(ValueError):
            e.join_truth(packet, broken)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve(); path = directory / "frozen.json"
            digest = e.write_exclusive(path, {"z": None, "a": "ø/△"})
            frozen = path.read_bytes()
            self.assertEqual(frozen, b'{"a":"\xc3\xb8/\xe2\x96\xb3","z":null}')
            self.assertEqual(digest, e.sha(frozen))
            with self.assertRaises(ValueError):
                e.write_exclusive(path, {"replace": True})
            self.assertEqual(path.read_bytes(), frozen)
            with self.assertRaises(ValueError):
                e.write_exclusive(directory / "inside.json", {}, (directory,))

    def test_predictor_opens_no_truth_or_training_metadata_and_loads_final_models_first(self):
        from ichart_recognition_ml.research import personal_hwrt_stroke_data as data, personal_hwrt_stroke_train as train
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve(); data_dir = directory / "data"; data_dir.mkdir()
            fit_dir = directory / "fit"; fit_dir.mkdir()
            models = {a: TinyModel().eval() for a in e.ARMS}
            states = {a: train._state_digest(m.state_dict()) for a, m in models.items()}
            fit = {"codeSHA256": {}, "protocolSHA256": e.PROTOCOL_SHA256, "vocabulary": VOCABULARY, "finalStateSHA256": states,
                   "weightsSHA256": {a: "b" * 64 for a in e.ARMS}, "dataReceiptSHA256": "c" * 64}
            fit_sha = e.sha(e.canonical(fit))
            inputs = {"version": "personal-hwrt-stroke-field-development-inputs-v1", "vocabulary": VOCABULARY, "rows": blind_rows()}
            domain = {"version": "chord-recognition-domain-v1", "vocabulary": VOCABULARY[:97], "allowedLabels": OLD_ALLOWED}
            domain_sha = e.write_exclusive(directory / "domain.json", domain)
            receipt = {"protocolSHA256": e.PROTOCOL_SHA256, "fitReceiptSHA256": fit_sha, "codeSHA256": {},
                       "trainingDataReceiptSHA256": "c" * 64, "sourceBindings": {"domain": {"sha256": domain_sha}},
                       "artifacts": {"inputs.json": e.sha(e.canonical(inputs)), "fields.npy": "d" * 64, "truth.json": "e" * 64}}
            receipt_sha = e.write_exclusive(data_dir / "data-receipt.json", receipt)
            e.write_exclusive(data_dir / "inputs.json", inputs)
            events = []
            def load_models(*args):
                events.append("final-models"); return models, fit
            def load_inputs(*args):
                events.append("blind-inputs"); return None, inputs, receipt
            def forward(*args):
                return [{**r, "results": {a: e.result([1.] + [0.] * 127, [1.] + [0.] * 101, VOCABULARY, ALLOWED)
                        for a in e.ARMS}} for r in inputs["rows"]]
            original = Path.read_bytes
            def guarded(path):
                self.assertNotIn(path.name, ("truth.json", "training.json", "selected_records.jsonl"))
                return original(path)
            with patch.object(Path, "read_bytes", guarded), patch.object(e, "DOMAIN_SHA256", domain_sha), \
                 patch.object(e, "code_identity", return_value={}), patch.object(data, "code_identity", return_value={}), \
                 patch.object(train, "load_fitted_models", side_effect=load_models), \
                 patch.object(data, "load_development_inputs", side_effect=load_inputs), patch.object(e, "freeze_forward", side_effect=forward):
                prediction_sha = e.predict(data_dir, fit_dir, directory / "domain.json", directory / "predictions.json",
                                          data_receipt_sha256=receipt_sha, fit_receipt_sha256=fit_sha)
                packet, _ = e.read_json(directory / "predictions.json", prediction_sha)
                self.assertEqual(events, ["final-models", "blind-inputs", "final-models", "blind-inputs"])
                e.validate_packet(packet, receipt, inputs)
                packet["weightsSHA256"][e.ARMS[0]] = "f" * 64
                with self.assertRaises(ValueError):
                    e.validate_packet(packet, receipt, inputs)
                packet["weightsSHA256"][e.ARMS[0]] = "b" * 64
                packet["rows"][0]["results"][e.ARMS[1]]["rawTop1"] = VOCABULARY[1]
                with self.assertRaises(ValueError):
                    e.validate_packet(packet, receipt, inputs)
            self.assertEqual(len(packet["rows"]), 1987)


if __name__ == "__main__":
    unittest.main()
