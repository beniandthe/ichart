import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.research import personal_training_residual_signal as signal


def fixture(count=3, vocabulary="ABC", tasks=None):
    writers = [f"trn_UPV_W{i:02d}" for i in range(count)]
    vocabulary = sorted(vocabulary)
    rows = [{"sourceID": f"{w}-{s}-{c}", "writer": w, "session": s, "label": c,
        "rawRasterSHA256": hashlib.sha256(f"pixel:{w}:{s}:{c}".encode()).hexdigest(),
        "trajectorySHA256": hashlib.sha256(f"ink:{w}:{s}:{c}".encode()).hexdigest(), "generator": "fitA"}
        for w in writers for s in (1, 2) for c in vocabulary]
    rows.sort(key=lambda r: r["sourceID"])
    # The writer coordinate is independent of character identity and session.
    raw = np.array([[0.8 if r["writer"] == writers[0] else -0.4,
        1 if r["label"] == vocabulary[0] else 0, 1 if r["label"] != vocabulary[0] else 0] for r in rows], dtype=np.float64)
    features = (raw / np.linalg.norm(raw, axis=1, keepdims=True)).astype(np.float32)
    return features, rows, writers, vocabulary, tasks or {"small": [vocabulary[0]]}


def synthetic_error_record(writer, task, session, source, focal, zero, unrelated, excluded=False):
    return {"cellID": f"{writer}:{task}:{session}->{3 - session}", "writer": writer, "task": task,
        "supportSession": session, "querySession": 3 - session, "source": {"sourceID": source},
        "copyReasons": [{"reason": "synthetic", "matchingSourceIDs": ["other"]}] if excluded else [],
        "errors": {"focal": focal, "zero": zero, "unrelated": unrelated, "donors": {"donor": unrelated}}}


def screen_plan(writers=("w0",), tasks=("task",)):
    return {"writers": list(writers), "tasks": {t: ["A"] for t in tasks},
        "cells": [{"cellID": f"{w}:{t}:{s}->{3 - s}"} for w in writers for t in tasks for s in (1, 2)]}


class TrainingResidualSignalTests(unittest.TestCase):
    def test_frozen_protocol_and_standalone_import(self):
        identity = signal.code_identity()
        self.assertEqual(identity[signal.PROTOCOL], signal.PROTOCOL_SHA256)
        self.assertEqual(len(identity), 3)
        source = Path(signal.__file__).read_text()
        self.assertNotIn("import torch", source)
        self.assertNotIn("from .", source)

    def test_complete_grid_rejects_bad_roles_rows_hashes_and_catalogs(self):
        features, rows, writers, vocabulary, tasks = fixture()
        signal.validate_grid(rows, writers, vocabulary, tasks)
        mutations = [lambda r: r.pop(), lambda r: r.reverse(), lambda r: r.__setitem__(0, r[1]),
            lambda r: r[0].__setitem__("session", True), lambda r: r[0].__setitem__("writer", "reserved"),
            lambda r: r[0].__setitem__("generator", "fitB"), lambda r: r[0].__setitem__("sourceID", "wrong"),
            lambda r: r[0].__setitem__("rawRasterSHA256", "g" * 64), lambda r: r[0].__setitem__("extra", 1)]
        for mutate in mutations:
            changed = copy.deepcopy(rows)
            mutate(changed)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                signal.validate_grid(changed, writers, vocabulary, tasks)
        for bad in ({}, {"small": []}, {"small": ["A", "A"]}, {"small": vocabulary}, {"small": ["Z"]}):
            with self.subTest(tasks=bad), self.assertRaises(ValueError):
                signal.validate_grid(rows, writers, vocabulary, bad)
        for bad_writers in (writers[:-1], [writers[0]] * len(writers)):
            with self.assertRaises(ValueError):
                signal.validate_grid(rows, bad_writers, vocabulary, tasks)
        with self.assertRaises(ValueError):
            signal.validate_grid(rows, writers, vocabulary[::-1], tasks)

    def test_feature_validation_rejects_nonunit_nonfinite_dtype_and_shape(self):
        features, rows, *_ = fixture()
        signal.validate_features(features, rows)
        nan = features.copy()
        nan[0, 0] = np.nan
        for bad in (features.astype(np.float64), features * 2, nan, features[:-1], features[:, 0]):
            with self.subTest(shape=bad.shape), self.assertRaises(ValueError):
                signal.validate_features(bad, rows)

    def test_focal_means_are_session_balanced_unnormalized_and_exclude_focal(self):
        features, rows, writers, vocabulary, _ = fixture()
        actual = signal.focal_means(features, rows, writers, vocabulary, writers[0])
        for label in vocabulary:
            means = []
            for session in (1, 2):
                selected = [features[i].astype(np.float64) for i, r in enumerate(rows)
                    if r["writer"] != writers[0] and r["session"] == session and r["label"] == label]
                means.append(sum(selected) / (len(writers) - 1))
            np.testing.assert_array_equal(actual[label], (means[0] + means[1]) / 2)
        changed = features.copy()
        changed[[i for i, r in enumerate(rows) if r["writer"] == writers[0]]] *= -1
        again = signal.focal_means(changed, rows, writers, vocabulary, writers[0])
        for label in vocabulary:
            np.testing.assert_array_equal(actual[label], again[label])
        # An opposing donor pair makes the arithmetic mean shorter than one.
        changed[rows.index(next(r for r in rows if r["writer"] == writers[1] and r["session"] == 1 and r["label"] == "A"))] *= -1
        means = signal.focal_means(changed, rows, writers, vocabulary, writers[0])
        self.assertLess(np.linalg.norm(means["A"]), 1)

    def test_plan_contains_exact_opposite_session_untaught_queries_and_all_donors(self):
        features, rows, writers, vocabulary, tasks = fixture(tasks={"one": ["A"], "two": ["A", "B"]})
        plan = signal.make_plan(rows, writers, vocabulary, tasks)
        self.assertEqual(len(plan["cells"]), 12)
        by_source = {r["sourceID"]: r for r in rows}
        for cell in plan["cells"]:
            self.assertEqual(cell["querySession"], 3 - cell["supportSession"])
            self.assertEqual(cell["donors"], [w for w in writers if w != cell["writer"]])
            self.assertEqual(set(cell["donorSupportSources"]), set(cell["donors"]))
            self.assertEqual(len(cell["queries"]), len(vocabulary) - len(tasks[cell["task"]]))
            self.assertTrue(all(by_source[q["sourceID"]]["label"] not in cell["supportLabels"] for q in cell["queries"]))
            self.assertTrue(all(by_source[q["sourceID"]]["writer"] == cell["writer"] for q in cell["queries"]))
        changed = copy.deepcopy(plan)
        changed["cells"][0]["queries"].pop()
        with self.assertRaises(ValueError):
            signal.evaluate(features, rows, writers, vocabulary, tasks, changed)

    def test_copy_ledger_retains_union_reasons_and_every_matching_source(self):
        _, rows, writers, vocabulary, tasks = fixture()
        query = next(r for r in rows if r["writer"] == writers[0] and r["session"] == 2 and r["label"] == "B")
        own = next(r for r in rows if r["writer"] == writers[0] and r["session"] == 1 and r["label"] == "A")
        others = [r for r in rows if r["writer"] in writers[1:] and r["label"] == "A" and r["session"] == 1]
        own["rawRasterSHA256"] = query["rawRasterSHA256"]
        own["trajectorySHA256"] = query["trajectorySHA256"]
        for other in others:
            other["rawRasterSHA256"] = query["rawRasterSHA256"]
            other["trajectorySHA256"] = query["trajectorySHA256"]
        plan = signal.make_plan(rows, writers, vocabulary, tasks)
        cell = next(c for c in plan["cells"] if c["writer"] == writers[0] and c["supportSession"] == 1)
        ledger = next(q for q in cell["queries"] if q["sourceID"] == query["sourceID"])
        self.assertEqual([r["reason"] for r in ledger["copyReasons"]], ["prototype-raw-raster-copy",
            "prototype-normalized-trajectory-copy", "own-support-raw-raster-copy", "own-support-normalized-trajectory-copy"])
        self.assertEqual(ledger["copyReasons"][0]["matchingSourceIDs"], sorted(r["sourceID"] for r in others))
        self.assertEqual(ledger["copyReasons"][2]["matchingSourceIDs"], [own["sourceID"]])
        self.assertEqual(len(cell["queries"]), 2)  # Excluded queries stay scheduled.

    def test_errors_match_independent_common_focal_mean_arithmetic(self):
        features, rows, writers, vocabulary, tasks = fixture()
        # Make donors different so averaging vectors gives the wrong control.
        for i, row in enumerate(rows):
            if row["writer"] == writers[-1]:
                features[i, 0] *= -1
        plan = signal.make_plan(rows, writers, vocabulary, tasks)
        records = signal.evaluate(features, rows, writers, vocabulary, tasks, plan)
        lookup = {(r["writer"], r["session"], r["label"]): i for i, r in enumerate(rows)}
        cell = plan["cells"][0]
        record = next(r for r in records if r["cellID"] == cell["cellID"])
        focal, query = cell["writer"], record["source"]
        mean = lambda label: sum(features[lookup[w, s, label]].astype(np.float64)
            for w in writers if w != focal for s in (1, 2)) / (2 * (len(writers) - 1))
        residual = features[lookup[focal, 2, query["label"]]].astype(np.float64) - mean(query["label"])
        styles = {w: features[lookup[w, 1, "A"]].astype(np.float64) - mean("A") for w in writers}
        zero = sum(float(x) ** 2 for x in residual)
        self.assertAlmostEqual(record["errors"]["zero"], zero, places=14)
        self.assertAlmostEqual(record["errors"]["focal"], sum(float(x) ** 2 for x in residual - styles[focal]), places=14)
        donors = [sum(float(x) ** 2 for x in residual - styles[w]) for w in writers if w != focal]
        self.assertAlmostEqual(record["errors"]["unrelated"], sum(donors) / len(donors), places=14)
        averaged_style_error = sum(float(x) ** 2 for x in residual - sum(styles[w] for w in writers if w != focal) / (len(writers) - 1))
        self.assertNotAlmostEqual(record["errors"]["unrelated"], averaged_style_error, places=10)
        self.assertEqual(set(record["errors"]["donors"]), set(writers) - {focal})

    def test_orthogonal_basis_change_preserves_errors_and_no_input_mutation(self):
        features, rows, writers, vocabulary, tasks = fixture()
        before = features.tobytes()
        plan = signal.make_plan(rows, writers, vocabulary, tasks)
        first = signal.evaluate(features, rows, writers, vocabulary, tasks, plan)
        transformed = features[:, [2, 0, 1]].copy()
        transformed[:, 0] *= -1
        second = signal.evaluate(transformed, rows, writers, vocabulary, tasks, plan)
        for left, right in zip(first, second):
            for key in ("zero", "focal", "unrelated"):
                self.assertAlmostEqual(left["errors"][key], right["errors"][key], places=14)
        self.assertEqual(features.tobytes(), before)

    def test_counts_include_repeated_and_excluded_sources_and_empty_primary(self):
        records = [synthetic_error_record("w0", "task", 1, "q", 1, 2, 3),
            synthetic_error_record("w0", "task", 2, "q", 1, 2, 3, excluded=True)]
        summary = signal.summarize(records)
        self.assertEqual(summary["counts"], {"scheduledExposures": 2, "distinctScheduledSources": 1,
            "repeatedScheduledExposures": 1, "eligibleExposures": 1, "distinctEligibleSources": 1,
            "repeatedEligibleExposures": 0, "excludedExposures": 1, "distinctExcludedSources": 1})
        report = signal.screen(records, screen_plan())
        self.assertFalse(report["fixedScreen"]["passed"])
        self.assertFalse(report["fixedScreen"]["nonemptyEligibleCells"])
        empty = report["summaries"]["cells"]["w0:task:2->1"]["sourceOnlyNoCopy"]
        self.assertEqual(empty["queryExposures"], 0)
        self.assertEqual(empty["meanSquaredError"], {"zero": None, "focal": None, "unrelated": None})

    def test_writer_screen_weights_queries_across_directions(self):
        # Averaging direction means gives focal 5, zero 5.5 (a false pass),
        # but query weighting gives focal 9, zero 2.7 (the required failure).
        records = [synthetic_error_record("w0", "task", 1, "a", 0, 9, 20)]
        records += [synthetic_error_record("w0", "task", 2, f"b{i}", 10, 2, 20) for i in range(9)]
        report = signal.screen(records, screen_plan())
        weighted = report["summaries"]["writers"]["w0"]["task"]["sourceOnlyNoCopy"]["meanSquaredError"]
        self.assertEqual(weighted["focal"], 9)
        self.assertEqual(weighted["zero"], 2.7)
        self.assertFalse(report["fixedScreen"]["writerConditions"]["w0"]["task"]["noWorseThanZero"])

    def test_screen_strict_task_non_strict_writer_and_no_raw_rescue(self):
        records = [synthetic_error_record("w0", "task", s, str(s), 1, 2, 3) for s in (1, 2)]
        self.assertTrue(signal.screen(records, screen_plan())["fixedScreen"]["passed"])
        records[0]["errors"]["focal"] = records[1]["errors"]["focal"] = 2
        report = signal.screen(records, screen_plan())
        self.assertFalse(report["fixedScreen"]["passed"])
        self.assertTrue(report["fixedScreen"]["writerConditions"]["w0"]["task"]["noWorseThanZero"])
        records = [synthetic_error_record("w0", "task", s, f"eligible{s}", 4, 2, 3) for s in (1, 2)]
        records += [synthetic_error_record("w0", "task", 1, f"excluded{i}", 0, 100, 100, True) for i in range(20)]
        report = signal.screen(records, screen_plan())
        self.assertLess(report["summaries"]["overall"]["rawScheduled"]["meanSquaredError"]["focal"],
            report["summaries"]["overall"]["rawScheduled"]["meanSquaredError"]["zero"])
        self.assertFalse(report["fixedScreen"]["passed"])

    def test_real_loader_rejects_unpinned_files_before_deserializing(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in signal.INPUT_SHA256:
                (directory / name).write_bytes(b"not an input")
            with patch.object(signal.np, "load", side_effect=AssertionError("array opened")), \
                    patch.object(signal.json, "loads", side_effect=AssertionError("metadata parsed")):
                with self.assertRaisesRegex(ValueError, "Pinned training inputs"):
                    signal.load_inputs(directory)

    def test_real_loader_complete_synthetic_full_grid_receipt_and_schema(self):
        vocabulary = sorted(set(signal.TASKS["catalog21"]) | {chr(0x100 + i) for i in range(76)})
        features, rows, writers, vocabulary, _ = fixture(count=16, vocabulary=vocabulary)
        features = np.pad(features, ((0, 0), (0, 125)))
        buffer = io.BytesIO()
        np.savez(buffer, features=features)
        source = signal.canonical({"vocabulary": vocabulary, "rows": rows})
        receipt = {"version": "personal-fitA-training-centroids-v1", "generator": "fitA",
            "generatorWeightsSHA256": signal.WEIGHTS_SHA256, "generatorStateSHA256": signal.STATE_SHA256,
            "sourceSHA256": signal.SOURCE_SHA256, "parentBinding": {"weights/fitA.pt": signal.WEIGHTS_SHA256},
            "sourceCount": 3104, "countPerLabel": 32, "storedUnavailableRawRowsRetained": 12,
            "trainingFeaturesSHA256": signal.sha(buffer.getvalue()), "trainingRowsSHA256": signal.sha(source),
            "inSampleTrainingCentroids": True, "sourceAndEncoderUnchanged": True, "privateInkUsed": False,
            "developmentOrReservedInferred": False, "productionEligible": False, "encoderFitWriters": writers[::-1],
            "vocabulary": vocabulary}
        blobs = {"centroid-receipt.json": signal.canonical(receipt), "training-rows.json": source,
            "training-features.npz": buffer.getvalue()}
        pins = {k: signal.sha(v) for k, v in blobs.items()}
        with tempfile.TemporaryDirectory() as temporary, patch.object(signal, "INPUT_SHA256", pins):
            directory = Path(temporary)
            for name, blob in blobs.items():
                (directory / name).write_bytes(blob)
            loaded = signal.load_inputs(directory)
            self.assertEqual(loaded[0].shape, (3104, 128))
            self.assertFalse(loaded[0].flags.writeable)
            self.assertEqual(loaded[1], rows)
            self.assertEqual(loaded[2], writers[::-1])  # The exact pinned role order need not be lexical.
            # A metadata pin alone never excuses a wrong parent or malformed provenance.
            for key, value in (("generatorStateSHA256", "0" * 64), ("sourceSHA256", "0" * 64),
                    ("storedUnavailableRawRowsRetained", 11), ("productionEligible", True)):
                bad = copy.deepcopy(receipt)
                bad[key] = value
                payload = signal.canonical(bad)
                (directory / "centroid-receipt.json").write_bytes(payload)
                with patch.dict(signal.INPUT_SHA256, {"centroid-receipt.json": signal.sha(payload)}):
                    with self.assertRaisesRegex(ValueError, "fitA training provenance"):
                        signal.load_inputs(directory)

    def test_fresh_output_rejects_existing_inside_git_and_input_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            signal._fresh_output(directory / "fresh")
            with self.assertRaises(ValueError):
                signal._fresh_output(directory)
            (directory / ".git").mkdir()
            with self.assertRaises(ValueError):
                signal._fresh_output(directory / "fresh")
            (directory / "input").write_bytes(b"data")
            (directory / "link").symlink_to(directory / "input")
            with self.assertRaises(ValueError):
                signal.regular_bytes(directory / "link")

    def test_exclusive_publication_and_plan_precedes_geometry(self):
        features, rows, writers, vocabulary, _ = fixture()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "fresh"
            code = {"synthetic": "1" * 64}
            inputs = signal.INPUT_SHA256.copy()
            called = []
            def compute(*args):
                self.assertTrue((output / "plan.json").is_file())
                self.assertFalse((output / "geometry.json").exists())
                called.append("evaluate")
                raise RuntimeError("stop synthetic before denominator requirement")
            # The publication-boundary test uses synthetic vectors only.
            with patch.object(signal, "code_identity", return_value=code), \
                    patch.object(signal, "input_identity", return_value=inputs), \
                    patch.object(signal, "load_inputs", return_value=(features, rows, writers, vocabulary, {})), \
                    patch.object(signal, "TASKS", {"small": ["A"]}), patch.object(signal, "evaluate", side_effect=compute):
                with self.assertRaisesRegex(RuntimeError, "stop synthetic"):
                    signal.run("synthetic-input-only", output)
            self.assertEqual(called, ["evaluate"])
            with self.assertRaises(FileExistsError):
                signal._publish(output / "plan.json", {})

    def test_input_or_code_mutation_prevents_plan_and_geometry_publication(self):
        features, rows, writers, vocabulary, tasks = fixture()
        code = {"synthetic": "1" * 64}
        inputs = signal.INPUT_SHA256.copy()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "before-plan"
            with patch.object(signal, "code_identity", side_effect=[code, {"synthetic": "2" * 64}]), \
                    patch.object(signal, "input_identity", return_value=inputs), \
                    patch.object(signal, "load_inputs", return_value=(features, rows, writers, vocabulary, {})), \
                    patch.object(signal, "TASKS", tasks):
                with self.assertRaisesRegex(ValueError, "before plan publication"):
                    signal.run("synthetic-input-only", output)
            self.assertFalse(output.exists())
            output = Path(temporary).resolve() / "before-geometry"
            report = {"summaries": {"overall": {"counts": {"scheduledExposures": 5216, "distinctScheduledSources": 2784}},
                "tasks": {"core10": {"counts": {"scheduledExposures": 2784}},
                          "catalog21": {"counts": {"scheduledExposures": 2432}}}}}
            fake_plan = {"cells": [{}] * 64}
            with patch.object(signal, "code_identity", return_value=code), \
                    patch.object(signal, "input_identity", side_effect=[inputs, inputs, {"changed": "3" * 64}]), \
                    patch.object(signal, "load_inputs", return_value=(features, rows, writers, vocabulary, {})), \
                    patch.object(signal, "make_plan", return_value=fake_plan), \
                    patch.object(signal, "evaluate", return_value=[]), patch.object(signal, "screen", return_value=report):
                with self.assertRaisesRegex(ValueError, "before geometry publication"):
                    signal.run("synthetic-input-only", output)
            self.assertTrue((output / "plan.json").exists())
            self.assertFalse((output / "geometry.json").exists())

    def test_final_receipt_rechecks_inputs_code_and_all_published_artifacts(self):
        features, rows, writers, vocabulary, _ = fixture()
        code, inputs = {"synthetic": "1" * 64}, signal.INPUT_SHA256.copy()
        report = {"summaries": {"overall": {"counts": {"scheduledExposures": 5216, "distinctScheduledSources": 2784}},
            "tasks": {"core10": {"counts": {"scheduledExposures": 2784}},
                      "catalog21": {"counts": {"scheduledExposures": 2432}}}},
            "fixedScreen": {"passed": False, "disposition": "stop-single-additive-support-mean"}}
        fake_plan = {"cells": [{}] * 64}
        with tempfile.TemporaryDirectory() as temporary:
            for mode in ("success", "input", "code", "plan.json", "geometry.json", "summary.json"):
                output = Path(temporary).resolve() / mode
                original_publish = signal._publish
                def publish(path, value):
                    digest = original_publish(path, value)
                    if Path(path).name == "summary.json" and mode.endswith(".json"):
                        (output / mode).write_bytes(b"changed after publication")
                    return digest
                identities = [inputs] * 4 + ([{"changed": "2" * 64}] if mode == "input" else [inputs])
                codes = [code] * 4 + ([{"changed": "2" * 64}] if mode == "code" else [code])
                with patch.object(signal, "code_identity", side_effect=codes), \
                        patch.object(signal, "input_identity", side_effect=identities), \
                        patch.object(signal, "load_inputs", return_value=(features, rows, writers, vocabulary, {})), \
                        patch.object(signal, "make_plan", return_value=fake_plan), \
                        patch.object(signal, "evaluate", return_value=[]), patch.object(signal, "screen", return_value=report), \
                        patch.object(signal, "_publish", side_effect=publish):
                    if mode == "success":
                        signal.run("synthetic-input-only", output)
                    else:
                        with self.assertRaisesRegex(ValueError, "before receipt publication"):
                            signal.run("synthetic-input-only", output)
                self.assertEqual((output / "receipt.json").exists(), mode == "success")
                if mode == "success":
                    receipt = json.loads((output / "receipt.json").read_bytes())
                    self.assertEqual(receipt["inputBeforeSHA256"], receipt["inputAfterSHA256"])
                    self.assertEqual(receipt["codeBeforeSHA256"], receipt["codeAfterSHA256"])


if __name__ == "__main__":
    unittest.main()
