import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import torch

from ichart_recognition_ml.research import personal_domain_reject as core
from ichart_recognition_ml.research import personal_domain_reject_data as data
from ichart_recognition_ml.research import personal_domain_reject_train as train
from ichart_recognition_ml.research import personal_domain_reject_evaluate as e
from test_personal_domain_reject_data import complete_parent_rows, synthetic_receipt, vocabulary


VOCAB = core.make_vocabulary(vocabulary(), vocabulary()[:41])


def reading(label, *, invalid=False):
    return {"domainTop1": label, "failure": "invalid retained" if invalid else None}


def metric_row(label, control, candidate, *, writer="w0", source="uji", native=None):
    return {"label": label, "writer": writer if source == "uji" else None, "source": source,
            "nativeSymbolID": native, "results": {e.ARMS[0]: reading(control), e.ARMS[1]: reading(candidate)}}


def good_rows():
    rows = [metric_row("L000", "L001", "L000"), metric_row("L050", "L000", None),
            metric_row("L002", "L002", "L002", writer="w1")]
    rows += [metric_row(label, label, label, source="hwrt", native=native) for native, label in e.NATIVE.items()]
    return rows


class Tiny(torch.nn.Module):
    def __init__(self, arm, invalid=False):
        super().__init__(); self.arm = arm; self.invalid = invalid
        self.register_buffer("unchanged", torch.tensor([1.]))

    def forward(self, batch):
        features = torch.zeros(len(batch), 128); features[:, 0] = 1
        logits = torch.zeros(len(batch), 102 if self.arm == "control" else 47); logits[:, 0] = 2
        if self.invalid: logits[0, 0] = float("nan")
        return features, logits


class DomainRejectEvaluationTests(unittest.TestCase):
    def test_exact_projection_core_parity_no_reject_tie_or_runner_promotion(self):
        embedding = [1.] + [0.] * 127
        for arm in e.ARMS:
            width = 102 if arm == "control" else 47
            for winner in range(width):
                logits = [0.] * width; logits[winner] = 1
                output = e.result(embedding, logits, arm, VOCAB)
                self.assertEqual(output["domainTop1"], core.decode(torch.tensor([logits]), arm, VOCAB)[0])
        logits = [0.] * 47; logits[0] = logits[46] = 3
        self.assertIsNone(e.result(embedding, logits, "domainReject", VOCAB)["domainTop1"])
        logits[46] = 4
        self.assertEqual(e.result(embedding, logits, "domainReject", VOCAB)["rawTop1"], "REJECT")
        self.assertIsNone(e.result(embedding, logits, "domainReject", VOCAB)["domainTop1"])
        control = [0.] * 102; control[50] = 4; control[0] = 3
        self.assertIsNone(e.result(embedding, control, "control", VOCAB)["domainTop1"])
        for bad in ([True] * 47, [0.] * 46, [float("nan")] * 47):
            with self.assertRaises(ValueError): e.result(embedding, bad, "domainReject", VOCAB)
        self.assertNotIn("REJECT", VOCAB.legal_labels)
        with self.assertRaises(ValueError): core.validate_teaching_labels(["REJECT"], VOCAB)

    def test_forward_retains_nonfinite_failure_and_source_model_identity(self):
        rasters = np.zeros((2, 1, 96, 256), dtype=np.float32)
        blind = [{"opaqueID": e.sha(f"query{i}".encode()), "rasterSHA256": e.sha(bytes(96 * 256)),
                  "normalizedGeometrySHA256": e.sha(f"geometry{i}".encode())} for i in range(2)]
        models = {a: Tiny(a, invalid=a == "domainReject").eval() for a in e.ARMS}
        states = {a: train.state_digest(m.state_dict()) for a, m in models.items()}
        rows = e.freeze_forward(models, rasters, {"rows": blind}, VOCAB, batch_size=2)
        self.assertEqual(len(rows), 2); self.assertIsNotNone(rows[0]["results"]["domainReject"]["failure"])
        self.assertIsNone(rows[1]["results"]["domainReject"]["failure"])
        self.assertIsNone(rows[0]["results"]["domainReject"]["rawLogits"])
        self.assertEqual(states, {a: train.state_digest(m.state_dict()) for a, m in models.items()})
        self.assertFalse(rasters.any())
        with self.assertRaises(ValueError):
            e.freeze_forward(models, rasters, {"rows": [{**blind[0], "rasterSHA256": "e" * 64}, blind[1]]}, VOCAB)

    def test_every_fixed_gate_reject_all_and_source_separate_coverage(self):
        value = e.view(good_rows(), ["w0", "w1"], VOCAB.legal_labels)
        self.assertTrue(e.fixed_screen(value)["passes"])
        self.assertEqual(set(value["safety"]), {"invalid", "newCorrectOrUnresolvedToWrongLegal"})
        self.assertNotIn("allQueries", value)
        changes = {
            "completeFiniteOutputs": lambda v: v["safety"]["invalid"].update(domainReject=1),
            "strictlyMoreCorrectLegalUJI": lambda v: v["ujiLegal"]["arms"]["domainReject"].update(correct=1),
            "fewerTotalWrongLegalUJI": lambda v: v["uji"]["arms"]["domainReject"].update(wrongLegal=2),
            "everyQueryWriterCorrectNonWorse": lambda v: v["writers"]["w1"]["arms"]["domainReject"].update(correct=0),
            "zeroNewCorrectOrUnresolvedToWrongLegal": lambda v: v["safety"].update(newCorrectOrUnresolvedToWrongLegal=1),
            "everyMappedHWRTClassCorrectNonWorse": lambda v: v["mappedClasses"]["#"]["arms"]["domainReject"].update(correct=0),
        }
        for gate, change in changes.items():
            broken = copy.deepcopy(value); change(broken)
            self.assertFalse(e.fixed_screen(broken)["checks"][gate], gate)
            self.assertFalse(e.fixed_screen(broken)["passes"], gate)
        rejected = good_rows()
        for row in rejected: row["results"]["domainReject"] = reading(None)
        self.assertFalse(e.fixed_screen(e.view(rejected, ["w0", "w1"], VOCAB.legal_labels))["passes"])
        unsafe = [metric_row("L050", None, "L000"), metric_row("+", "+", "#", source="hwrt", native="196")]
        self.assertEqual(e.view(unsafe, ["w0"], VOCAB.legal_labels)["safety"]["newCorrectOrUnresolvedToWrongLegal"], 2)

    def test_failures_and_copy_exclusions_keep_paired_denominators(self):
        rows = good_rows(); rows[0]["copyReasons"] = ["fit-rasterSHA256"]
        for row in rows[1:]: row["copyReasons"] = []
        raw = e.view(rows, ["w0", "w1"], VOCAB.legal_labels)
        no_copy = e.view([r for r in rows if not r["copyReasons"]], ["w0", "w1"], VOCAB.legal_labels)
        self.assertTrue(e.fixed_screen(raw)["passes"]); self.assertFalse(e.fixed_screen(no_copy)["passes"])
        self.assertEqual(raw["uji"]["count"] - no_copy["uji"]["count"], 1)
        rows[0]["results"]["domainReject"] = reading(None, invalid=True)
        value = e.view(rows, ["w0", "w1"], VOCAB.legal_labels)
        self.assertEqual(value["uji"]["count"], 3)
        self.assertEqual(sum(value["uji"]["transitions"].values()), 3)
        self.assertEqual(value["uji"]["arms"]["domainReject"]["unresolved"], 2)
        self.assertFalse(e.fixed_screen(value)["checks"]["completeFiniteOutputs"])

    def test_crossmodule_copy_union_truth_alignment_and_malformed_roles(self):
        parent = complete_parent_rows(); _, indexes = data._split_rows(parent); fold = e.FOLDS[0]
        fit_rows = [data._blind_row(parent[i]) for i in indexes[fold]["fit"]]
        labels = [data._project_row(parent[i]) for i in indexes[fold]["query"]]
        labels[1]["rasterSHA256"] = labels[0]["rasterSHA256"]
        labels[2]["normalizedGeometrySHA256"] = fit_rows[0]["normalizedGeometrySHA256"]
        blind = [data._blind_row(r) for r in labels]
        union = e.copy_union(blind, fit_rows)
        expected = data._copy_reasons(fit_rows, labels)
        self.assertEqual({r["opaqueID"]: tuple(r["reasons"]) for r in union["rows"] if r["reasons"]}, expected)
        truth_rows = [{**r, "copyReasons": list(expected.get(r["opaqueID"], ()))} for r in labels]
        truth = {"version": data.QUERY_TRUTH_VERSION, "fold": fold, "rows": truth_rows,
                 "copyUnion": {k: v for k, v in union.items() if k != "rows"}}
        frozen = {"copyUnion": union, "rows": [{**r, "results": {a: reading(None) for a in e.ARMS}} for r in blind]}
        joined, writers = e.join_truth(fold, frozen, truth, VOCAB)
        self.assertEqual(len(joined), 3874); self.assertEqual(len(writers), 16)
        self.assertEqual(len([r for r in joined if r["copyReasons"]]), len(expected))
        for mutate in (lambda v: v["copyUnion"].pop("version"), lambda v: v["rows"][0].update(label="REJECT"),
                       lambda v: v["rows"][0].update(rasterSHA256="e" * 64),
                       lambda v: v["rows"][0].update(session=True), lambda v: v.update(version="old-query-truth")):
            changed = copy.deepcopy(truth); mutate(changed)
            with self.assertRaises(ValueError): e.join_truth(fold, frozen, changed, VOCAB)
        contaminated = {"version": e.INPUT_VERSION, "fold": fold, "vocabulary": list(VOCAB.source_labels), "rows": blind}
        e.validate_inputs(contaminated, fold, VOCAB)
        contaminated["rows"][0] = {**contaminated["rows"][0], "label": "L000"}
        with self.assertRaises(ValueError): e.validate_inputs(contaminated, fold, VOCAB)

    def test_real_blind_loader_truth_decoys_and_predict_score_chronology(self):
        fit_rows = [{"opaqueID": e.sha(f"fit{i}".encode()), "label": "L000", "source": "uji", "writer": "w",
                     "session": 1, "nativeSymbolID": None, "rasterSHA256": e.sha(f"fit-raster{i}".encode()),
                     "normalizedGeometrySHA256": e.sha(f"fit-geometry{i}".encode())} for i in range(2)]
        query_rows = [{**r, "opaqueID": e.sha(f"query{i}".encode())} for i, r in enumerate(fit_rows)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve(); data_dir = root / "data"; data_dir.mkdir(); fit_dir = root / "fit"; fit_dir.mkdir()
            receipt = synthetic_receipt(data_dir, fit_rows, query_rows)
            second = data_dir / e.fold_path(e.FOLDS[1], "query-inputs.json")
            changed, _ = e.read_json(second); changed["rows"][0]["opaqueID"] = e.sha(b"otherfold")
            second.write_bytes(e.canonical(changed)); receipt["artifacts"][str(second.relative_to(data_dir))] = data.parent_data._artifact(second)
            (data_dir / "data-receipt.json").write_bytes(e.canonical(receipt))
            for fold in e.FOLDS:
                (data_dir / e.fold_path(fold, "query-truth.json")).write_bytes(b"truth-decoy-do-not-open")
            models = {f: {a: Tiny(a).eval() for a in e.ARMS} for f in e.FOLDS}
            fit = {"version": e.FIT_VERSION, "modelVersion": core.MODEL_VERSION, "protocolSHA256": e.PROTOCOL_SHA256,
                   "sourceVocabulary": list(VOCAB.source_labels), "legalOldLabels": list(VOCAB.legal_labels[:41]),
                   "candidateLabels": list(VOCAB.candidate_labels), "codeSHA256": {"synthetic": "0" * 64},
                   "weights": {f: {a: {"path": f"weights/{f}-{a}.pt", "sha256": "f" * 64} for a in e.ARMS} for f in e.FOLDS},
                   "finalStateSHA256": {f: {a: train.state_digest(m.state_dict()) for a, m in models[f].items()} for f in e.FOLDS}}
            events = []; original_open = Path.open; original_query = data.load_query

            def guarded_open(path, *args, **kwargs):
                if path.name in {"fit.json", "query-truth.json", "split.json", "training.json"}:
                    self.fail(f"Label-bearing/role file opened during prediction: {path}")
                return original_open(path, *args, **kwargs)

            def load_models(*args): events.append("both-final-folds"); return models, fit
            def load_query(*args): events.append("blind-query"); return original_query(*args)
            def freeze(models, rasters, inputs, vocab):
                events.append("forward")
                return [{**r, "results": {a: e.failed(ValueError("synthetic retained failure")) for a in e.ARMS}} for r in inputs["rows"]]

            output = root / "predictions.json"
            with patch.object(data, "FIT_ROWS", 2), patch.object(data, "QUERY_ROWS", 2), patch.object(data, "RASTER_SHAPE", (1, 2, 3)), \
                 patch.object(data, "_validate_receipt"), patch.object(data, "load_query", side_effect=load_query), \
                 patch.object(e, "QUERY_ROWS", 2), patch.object(e, "FIT_ROWS", 2), patch.object(e, "EXPOSURES", 4), patch.object(e, "DISTINCT_DRAWINGS", 3), \
                 patch.object(train, "load_fitted_models", side_effect=load_models), patch.object(e, "validate_receipts", return_value=VOCAB), \
                 patch.object(e, "code_identity", return_value=fit["codeSHA256"]), patch.object(e, "freeze_forward", side_effect=freeze), \
                 patch.object(Path, "open", guarded_open):
                digest = e.predict(data_dir, fit_dir, output, data_receipt_sha256=e.sha(e.canonical(receipt)), fit_receipt_sha256=e.sha(e.canonical(fit)))
                self.assertEqual(events[:3], ["both-final-folds", "blind-query", "blind-query"])
                packet, original = e.read_json(output, digest)
                self.assertEqual(packet["queryExposures"], 4)
                self.assertEqual(packet["distinctQueryDrawings"], 3)
                self.assertTrue(all(r["results"]["domainReject"]["failure"] for f in packet["folds"].values() for r in f["rows"]))
                with self.assertRaises(ValueError): e.score(output, data_dir, root / "score.json", predictions_sha256="0" * 64, data_receipt_sha256=e.sha(e.canonical(receipt)))
                with self.assertRaises(ValueError): e.write_exclusive(output, {})
                self.assertEqual(output.read_bytes(), original)
            self.assertTrue(callable(train.state_digest))


if __name__ == "__main__":
    unittest.main()
