"""Synthetic source binding, actual residual solves, and freeze/score boundaries."""
import base64
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.research import personal_class_frozen_append_only_evaluation as r


def encoded(value):
    data = r.canonical(value)
    return base64.b64encode(data).decode(), r.sha(data)


def fixture():
    allowed = list(r.CATALOG) + [f"u{i:02}" for i in range(20)]
    vocab = sorted(allowed + [f"z{i:02}" for i in range(56)])
    def vectors(label):
        x = np.eye(128)[vocab.index(label)]; b = np.zeros(97)
        if label in r.CATALOG:
            b[vocab.index("z00")] = .7; b[vocab.index(label)] = .3
        else:
            b[vocab.index(label)] = 1
        return r.vector(x, b)
    raw, truth, copies = [], [], []
    for writer in r.WRITERS:
        for session in (1, 2):
            for label in vocab:
                packet, digest = encoded([writer, session, label])
                sid = r.sha(r.canonical([writer, session, label, "opaque-ID"]))
                raw.append({"id": sid, "writerID": writer, "session": session, "sourceCanonicalData": packet,
                            "sourcePacketSHA256": digest, "rawRasterSHA256": r.sha(packet.encode()), "failure": None})
                if session == 2:
                    truth.append({"sampleID": sid, "writerID": writer, "label": label})
                    copies.append({"sampleID": sid, "reasons": ["synthetic-source-copy"] if label == "u00" and writer in r.WRITERS[:4] else []})
    truth = {"version": "public-app-local-transfer-truth-v1", "sourceSHA256": r.SOURCE_SHA, "fixtureSHA256": r.FIXTURE_SHA, "queries": truth}
    copies = {"version": "public-app-local-transfer-source-copy-ledger-v1", "sourceSHA256": r.SOURCE_SHA, "fixtureSHA256": r.FIXTURE_SHA, "reservedWriterRasterCount": 0, "queryRows": copies}
    pins = {**r.PINS, "truth": r.sha(r.canonical(truth)), "copies": r.sha(r.canonical(copies))}
    train_writers = [f"training-{i}" for i in range(32)]
    fit = {"vocabulary": vocab, "sourceSHA256": r.SOURCE_SHA, "trainingWriters": train_writers, "developmentWriters": list(r.WRITERS),
           "weightsSHA256": {"crossEntropyControl": r.CE_WEIGHTS_SHA},
           "trainingInputs": [{"writer": w, "session": s, "label": l} for w in train_writers for s in (1, 2) for l in vocab]}
    fit_blob, pins["ceReceipt"] = encoded(fit)
    app = {"version": "public-app-local-transfer-predictions-v1", "vocabulary": vocab, "encoderIdentity": "synthetic-frozen-encoder",
           "trainingEligible": False, "intendedQueryLabelsSupplied": False, "trainingWriterMembershipVerified": False,
           "reservedWriterInferencePerformed": False, "sourceSHA256": r.SOURCE_SHA, "fixtureSHA256": r.FIXTURE_SHA,
           "queryTruthSHA256": pins["truth"], "sourceCopyLedgerSHA256": pins["copies"], "rawSamples": raw,
           "profiles": [], "rows": [], "codeFilesSHA256": {}, "runtimeFilesSHA256": {"weights": "synthetic"}}
    ce = {"vocabulary": vocab, "queryTruthOpened": False, "reservedFeatureCount": 0, "reservedInferenceCount": 0,
          "bindings": {"sourceSHA256": r.SOURCE_SHA, "fixtureSHA256": r.FIXTURE_SHA, "fitReceiptSHA256": pins["ceReceipt"],
                       "queryTruthSHA256": pins["truth"], "sourceCopyLedgerSHA256": pins["copies"], "codeSHA256": {}},
          "fitReceiptCanonicalData": fit_blob, "supports": [], "rows": []}
    raw_by_key = {(s["writerID"], s["session"], json_label): s for s in raw for json_label in [r.parsed(base64.b64decode(s["sourceCanonicalData"]))[2]]}
    for writer in r.WRITERS:
        for task, labels in (("core10", r.CORE[5:] + r.CORE[:5]), ("catalog21", tuple(reversed(r.CATALOG)))):
            stored, app_vectors, ce_vectors, examples = [], [], [], []
            for label in labels:
                source = raw_by_key[writer, 1, label]; example_id = f"{writer}/{task}/{label}"
                packet, digest = encoded(["exact-stored-lesson", example_id])
                row = {"sampleID": source["id"], "exampleID": example_id, "label": label,
                       "storedCanonicalData": packet, "storedPacketSHA256": digest, "storedRasterSHA256": r.sha(packet.encode())}
                stored.append(row); examples.append({"id": example_id, "label": label, "kind": "glyph", "source": "setup"})
                app_vectors.append({"exampleID": example_id, "label": label, "source": "setup", "storedInkSHA256": digest, **vectors(label)})
                ce_vectors.append({**row, **vectors(label)})
            profile_blob, profile_sha = encoded({"examples": examples})
            for c in ce_vectors:
                c["profileSHA256"] = profile_sha
            app["profiles"].append({"writerID": writer, "task": task, "profileCanonicalData": profile_blob, "profileSHA256": profile_sha,
                "supportLessons": stored, "modelIdentity": {"profileSHA256": profile_sha}, "support": {"lessons": app_vectors,
                "profileSHA256": profile_sha, "encoderIdentity": app["encoderIdentity"]}})
            ce["supports"].append({"writerID": writer, "task": task, "arm": "crossEntropyControl", "lessons": list(reversed(ce_vectors))})
            for label in vocab:
                source = raw_by_key[writer, 2, label]; shared = {"sampleID": source["id"], "writerID": writer, "task": task, "outcome": "read", "failure": None}
                app["rows"].append({**shared, "reading": {"glyphs": [vectors(label)], "sourceInkSHA256": source["sourcePacketSHA256"], "encoderIdentity": app["encoderIdentity"]}})
                ce["rows"].append({**shared, "arm": "crossEntropyControl", **vectors(label), **{k: source[k] for k in ("sourceCanonicalData", "sourcePacketSHA256", "rawRasterSHA256")}})
    pins["app"] = r.sha(r.canonical(app)); ce["bindings"]["appReportSHA256"] = pins["app"]
    domain = {"version": "chord-recognition-domain-v1", "vocabulary": vocab, "allowedLabels": allowed}
    pins.update(ce=r.sha(r.canonical(ce)), domain=r.sha(r.canonical(domain)))
    with patch.dict(r.PINS, pins):
        plan = r.prepare_views(app, ce, fit, domain)
    return app, ce, fit, domain, truth, copies, pins, plan


def scoring_packet(plan, truth):
    """A known favorable synthetic result; controls are not alternate winners."""
    rows = {view: [] for view in r.VIEWS}
    for view in r.VIEWS:
        for answer in truth["queries"]:
            label = answer["label"]; permitted = label if label in plan["allowedLabels"] else None
            reference = None if label in r.ADDED else permitted
            rows[view].append({"sampleID": answer["sampleID"], "writerID": answer["writerID"], "failure": None,
                "predictions": {"generic": reference, "reference10": reference, "fullRefit21": permitted, "classFrozen21": permitted},
                "untouchedScoresBitIdentical": True})
    return {"vocabulary": plan["vocabulary"], "allowedLabels": plan["allowedLabels"], "rows": rows}


class AppendEvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app, cls.ce, cls.fit, cls.domain, cls.truth, cls.copies, cls.pins, cls.plan = fixture()

    def prepare(self, app=None, ce=None):
        with patch.dict(r.PINS, self.pins):
            return r.prepare_views(app or self.app, ce or self.ce, self.fit, self.domain)

    def test_exact_source_join_order_and_no_query_targets(self):
        for view in r.VIEWS:
            history = self.plan["supports"][view][r.WRITERS[0]]
            self.assertEqual([x["identity"]["label"] for x in history[:10]], list(r.CORE[5:] + r.CORE[:5]))
            self.assertEqual([x["identity"]["label"] for x in history[10:]], list(r.ADDED))
            self.assertEqual(len(self.plan["queries"][view]), 776)
            self.assertTrue(all("label" not in q and "intended" not in q for q in self.plan["queries"][view]))
        self.assertEqual([x["identity"] for x in self.plan["supports"][r.VIEWS[0]][r.WRITERS[0]]],
                         [x["identity"] for x in self.plan["supports"][r.VIEWS[1]][r.WRITERS[0]]])

    def test_source_and_duplicate_query_tamper_rejected(self):
        ce = copy.deepcopy(self.ce); ce["supports"][0]["lessons"][0]["storedRasterSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "stored ink"):
            self.prepare(ce=ce)
        app = copy.deepcopy(self.app); app["rows"][0]["reading"]["glyphs"][0]["embeddingSHA256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Task-duplicate"):
            self.prepare(app=app)

    def test_denominator_and_encoder_grid_miscount_rejected(self):
        app = copy.deepcopy(self.app); app["rows"].pop()
        with self.assertRaisesRegex(ValueError, "776"):
            self.prepare(app=app)
        truth = copy.deepcopy(self.truth); truth["queries"].pop()
        with self.assertRaisesRegex(ValueError, "denominator"):
            r.score_packet(scoring_packet(self.plan, self.truth), truth, self.copies)

    def test_real_nonzero_support_solve_and_forward_without_queries(self):
        plan = {k: v for k, v in self.plan.items() if k != "queries"}
        models, snaps = r.fit_snapshots(plan)  # The fitter cannot inspect any query array or target.
        writer, view = r.WRITERS[0], r.VIEWS[0]; ref = models[view][writer]["reference10"]; candidate = models[view][writer]["classFrozen21"]
        untouched = [i for i, l in enumerate(self.plan["vocabulary"]) if l not in r.ADDED]
        self.assertGreater(float(np.linalg.norm(candidate.weights - ref.weights)), 0)
        self.assertEqual(r.bits(ref.weights[:, untouched]), r.bits(candidate.weights[:, untouched]))
        history = self.plan["supports"][view][writer]; v = history[10]; x, b = np.array(v["embedding"]), np.array(v["baseScores"])
        a, c = ref.adjusted_scores(x, b), candidate.adjusted_scores(x, b)
        self.assertEqual(r.bits(a[untouched]), r.bits(c[untouched]))
        self.assertEqual(r.permitted_top(c, self.plan["vocabulary"], self.domain["allowedLabels"]), v["identity"]["label"])
        self.assertEqual(len(snaps[view][writer]["reference10"]["sourceIDs"]), 10)
        self.assertEqual(len(snaps[view][writer]["classFrozen21"]["sourceIDs"]), 21)

    def test_actual_winner_only_no_runner_up_or_confidence(self):
        scores = np.zeros(97); scores[self.plan["vocabulary"].index("z00")] = 3; scores[self.plan["vocabulary"].index("A")] = 2
        self.assertIsNone(r.permitted_top(scores, self.plan["vocabulary"], self.domain["allowedLabels"]))

    def test_snapshot_recomputation_exact_feature_order(self):
        rng = np.random.default_rng(19); x = rng.normal(size=(21, 128)); x /= np.linalg.norm(x, axis=1, keepdims=True)
        b = np.full((21, 97), 1 / 97)
        head = r.learner.fit_reference(x, b, list(r.CATALOG), [str(i) for i in range(21)], self.plan["vocabulary"], "synthetic")
        query = rng.normal(size=128); query /= np.linalg.norm(query)
        self.assertEqual(r.bits(head.adjusted_scores(query, b[0])), r.bits(r.adjusted_from_weights(head.weights, query, b[0])))

    def test_invalid_queries_retained_as_unresolved(self):
        app, ce = copy.deepcopy(self.app), copy.deepcopy(self.ce); sid = app["rows"][0]["sampleID"]
        for collection in (app["rows"], ce["rows"]):
            for row in collection:
                if row["sampleID"] == sid:
                    row.update(outcome="invalid-ink", failure="synthetic-invalid-geometry", reading=None)
        plan = self.prepare(app, ce)
        for view in r.VIEWS:
            plan["queries"][view] = [q for q in plan["queries"][view] if q["sampleID"] == sid]
            self.assertIsNone(plan["queries"][view][0]["vector"])
        packet = r.predict_queries(plan, {})  # No model forward is allowed/needed for these rows.
        for view in r.VIEWS:
            self.assertEqual(len(packet["rows"][view]), 1)
            self.assertTrue(all(x is None for x in packet["rows"][view][0]["predictions"].values()))

    def test_reporting_and_both_view_fixed_gate(self):
        packet = scoring_packet(self.plan, self.truth); result = r.score_packet(packet, self.truth, self.copies)
        self.assertTrue(result["passesFixedScreen"])
        for view in r.VIEWS:
            self.assertEqual(result["views"][view]["raw"]["denominator"], 328)
            self.assertEqual(result["views"][view]["noCopy"]["denominator"], 324)
            self.assertEqual(result["views"][view]["raw"]["outOfDomain"]["denominator"], 448)
            self.assertEqual(result["views"][view]["raw"]["strata"]["added11"]["candidateVsReference"]["gains"], 88)
            self.assertTrue(all(x["intended"] is None for x in result["views"][view]["rows"] if x["stratum"] == "outOfDomain56"))
        for row in packet["rows"][r.VIEWS[1]]:
            row["predictions"]["classFrozen21"] = row["predictions"]["reference10"]
        self.assertFalse(r.score_packet(packet, self.truth, self.copies)["passesFixedScreen"])

    def test_old_harm_and_new_ood_read_reject_without_tuning(self):
        packet = scoring_packet(self.plan, self.truth)
        row = next(x for x in packet["rows"][r.VIEWS[0]] if x["predictions"]["reference10"] == "A")
        row["predictions"]["classFrozen21"] = None
        result = r.score_packet(packet, self.truth, self.copies)
        self.assertFalse(result["passesFixedScreen"])
        self.assertEqual(result["views"][r.VIEWS[0]]["raw"]["strata"]["old10"]["candidateVsReference"]["correctToUnresolved"], 1)
        row = next(x for x in packet["rows"][r.VIEWS[1]] if x["predictions"]["reference10"] is None and x["predictions"]["classFrozen21"] is None)
        row["predictions"]["classFrozen21"] = "A"
        self.assertFalse(r.score_packet(packet, self.truth, self.copies)["views"][r.VIEWS[1]]["raw"]["fixedScreenConditions"]["zeroNewOutOfDomainReads"])

    def test_freeze_then_score_tamper_and_exclusive_boundary(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(r.PINS, self.pins):
            base = Path(tmp).resolve(); paths = []
            for name, value in zip(("app", "ce", "fit", "domain"), (self.app, self.ce, self.fit, self.domain), strict=True):
                path = base / (name + ".json"); path.write_bytes(r.canonical(value)); paths.append(path)
            output = base / "frozen"
            def synthetic_fast_forward(head, x, b):
                self.assertTrue(all((output / n).is_file() for n in ("fit-plan.json", "snapshots.json", "snapshot-receipt.json")))
                self.assertFalse((output / "predictions.json").exists())
                # Unit-basis synthetic inputs make this byte-identical to the fixed feature-order reduction.
                return np.asarray(b) + np.einsum("d,dc->c", x, head.weights, optimize=False)
            with patch.object(r.learner.ClassFrozenResidualSnapshot, "adjusted_scores", synthetic_fast_forward):
                r.freeze(*paths, output)
            receipt_sha = r.sha(r.read(output / "freeze-receipt.json")); packet, _ = r.validate_frozen(output, receipt_sha)
            self.assertEqual(len(packet["rows"][r.VIEWS[0]]), 776)
            truth_path, copy_path = base / "truth.json", base / "copies.json"
            truth_path.write_bytes(r.canonical(self.truth)); copy_path.write_bytes(r.canonical(self.copies))
            with self.assertRaisesRegex(ValueError, "immutable freeze"):
                r.score(output, truth_path, copy_path, output / "score.json", receipt_sha256=receipt_sha)
            self.assertTrue(r.score(output, truth_path, copy_path, base / "score.json", receipt_sha256=receipt_sha)["passesFixedScreen"])
            prediction_data = r.read(output / "predictions.json"); receipt_data = r.read(output / "freeze-receipt.json")
            changed = r.parsed(prediction_data); changed["rows"][r.VIEWS[0]][0]["scores"]["classFrozen21"][self.plan["vocabulary"].index("m")] += 1e-12
            (output / "predictions.json").write_bytes(r.canonical(changed))
            updated = r.parsed(receipt_data); updated["artifacts"]["predictions.json"] = r.sha(r.canonical(changed))
            (output / "freeze-receipt.json").write_bytes(r.canonical(updated))
            with self.assertRaisesRegex(ValueError, "frozen snapshot"):
                r.validate_frozen(output, r.sha(r.canonical(updated)))
            (output / "predictions.json").write_bytes(prediction_data); (output / "freeze-receipt.json").write_bytes(receipt_data)
            with self.assertRaisesRegex(ValueError, "Fresh"):
                r.freeze(*paths, output)
            (output / "predictions.json").write_bytes(b"{}")
            with patch.object(r, "read", wraps=r.read) as reads:
                with self.assertRaisesRegex(ValueError, "artifact"):
                    r.score(output, truth_path, copy_path, base / "bad-score.json", receipt_sha256=receipt_sha)
                self.assertFalse(any(Path(call.args[0]) in (truth_path, copy_path) for call in reads.call_args_list))

    def test_missing_prediction_arm_and_copy_miscount_rejected(self):
        packet = scoring_packet(self.plan, self.truth); del packet["rows"][r.VIEWS[0]][0]["predictions"]["fullRefit21"]
        with self.assertRaisesRegex(ValueError, "domain output"):
            r.score_packet(packet, self.truth, self.copies)
        copies = copy.deepcopy(self.copies); copies["queryRows"][0]["reasons"] = ["changed-denominator"]
        with self.assertRaisesRegex(ValueError, "denominator"):
            r.score_packet(scoring_packet(self.plan, self.truth), self.truth, copies)


if __name__ == "__main__":
    unittest.main()
