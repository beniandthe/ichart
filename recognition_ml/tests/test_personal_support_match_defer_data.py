import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from ichart_recognition_ml.features import InkPoint, InkStroke, rasterize
from ichart_recognition_ml.research import personal_support_crossfit as crossfit
from ichart_recognition_ml.research import personal_support_match_defer_data as data
from ichart_recognition_ml.research.uji_personal import Sample, trajectory_fingerprint


def sample(label, offset, *, session=1):
    return Sample(
        "trn_UJI_W00",
        session,
        label,
        (InkStroke((InkPoint(offset, 0), InkPoint(offset + 2, 3), InkPoint(offset + 5, 1))),),
    )


def digest(value):
    return hashlib.sha256(value).hexdigest()


def ledger_row(record, index, *, stored=True, failure="synthetic-unrequested-failure"):
    raw = rasterize(record.strokes).pixels
    shape = crossfit.setup_shape(record.strokes) if stored else None
    if stored:
        assert shape is not None
        stored_bytes = rasterize(shape).pixels
        stored_trajectory = trajectory_fingerprint(
            Sample(record.writer, record.session, record.label, shape)
        )
    else:
        stored_bytes = None
        stored_trajectory = None
    return {
        "sourceIndex": index,
        "sourceKey": digest(record.identity.encode()),
        "writer": record.writer,
        "session": record.session,
        "rawRasterSHA256": digest(raw),
        "trajectorySHA256": trajectory_fingerprint(record),
        "storedRasterSHA256": digest(stored_bytes) if stored_bytes is not None else None,
        "storedTrajectorySHA256": stored_trajectory,
        "storedFailure": None if stored else failure,
    }


def support(row):
    return {key: row[key] for key in (
        "sourceIndex", "sourceKey", "rawRasterSHA256", "trajectorySHA256",
        "storedRasterSHA256", "storedTrajectorySHA256", "storedFailure",
    )}


def fixture():
    records = (
        sample("A", 0),
        sample("B", 10),
        sample("C", 20, session=2),
        sample("D", 30, session=2),
    )
    rows = [
        ledger_row(records[0], 0),
        ledger_row(records[1], 1, stored=False),
        ledger_row(records[2], 2),
        ledger_row(records[3], 3, stored=False, failure="PersonalInkShape-unavailable"),
    ]
    forward = {
        "version": "personal-support-match-defer-source-plan-v1",
        "protocolSHA256": data.PROTOCOL_SHA256,
        "bindings": {"sourceSHA256": data.SOURCE_SHA256},
        "roleGuards": {
            "developmentOrReservedSamplesOpened": False,
            "rastersConstructed": False,
        },
        "sourceLedger": rows,
        "forward": {
            "A-to-B": {
                "trainingEpisodes": [{"support": [support(rows[0])]}],
                "heldoutEpisodes": [{
                    "trueSupport": {"support": [support(rows[2])]},
                    "wrongSupport": {"support": [support(rows[3])]},
                }],
            }
        },
    }
    return records, forward


def materialized_fixture(directory):
    records, forward = fixture()
    calls = []

    def setup(strokes):
        calls.append(strokes)
        if strokes == records[3].strokes:
            return None
        return crossfit.setup_shape(strokes)

    arrays, truth, facts = data.build_raster_payload(
        (records[2], records[0], records[3], records[1]), forward, setup_shape=setup
    )
    raster_bytes = data._npz_bytes(arrays)
    truth_bytes = data._canonical(truth)
    forward_sha = digest(data._canonical(forward))
    receipt = data._receipt(
        arrays, truth_bytes, raster_bytes, facts, forward_sha, {"synthetic": "0" * 64}
    )
    root = Path(directory).resolve()
    (root / "rasters.npz").write_bytes(raster_bytes)
    (root / "data-receipt.json").write_bytes(data._canonical(receipt))
    return records, forward, arrays, truth, facts, calls, receipt


class SupportMatchDeferDataTests(unittest.TestCase):
    def test_compact_materialization_uses_only_requested_stored_rows_and_keeps_truth_separate(self):
        records, forward = fixture()
        calls = []

        def setup(strokes):
            calls.append(strokes)
            return None if strokes == records[3].strokes else crossfit.setup_shape(strokes)

        arrays, truth, facts = data.build_raster_payload(
            tuple(reversed(records)), forward, setup_shape=setup
        )
        self.assertEqual(tuple(arrays), ("raw_rasters", "stored_rasters", "stored_source_indices"))
        self.assertEqual(arrays["raw_rasters"].shape, (4, 1, 96, 256))
        self.assertEqual(arrays["raw_rasters"].dtype, np.uint8)
        self.assertEqual(arrays["stored_rasters"].shape, (2, 1, 96, 256))
        self.assertEqual(arrays["stored_rasters"].dtype, np.uint8)
        np.testing.assert_array_equal(arrays["stored_source_indices"], np.array([0, 2], np.int64))
        self.assertEqual(calls, [records[0].strokes, records[2].strokes, records[3].strokes])
        self.assertNotIn(records[1].strokes, calls)
        self.assertEqual(
            facts,
            {"rawRows": 4, "requestedStoredRows": 3, "storedRows": 2,
             "requestedStoredFailures": 1, "unrequestedRows": 1,
             "unrequestedMetadataFailures": 1},
        )
        self.assertEqual(truth["rows"], [
            {"sourceIndex": 0, "intended": "A"},
            {"sourceIndex": 1, "intended": "B"},
            {"sourceIndex": 2, "intended": "C"},
            {"sourceIndex": 3, "intended": "D"},
        ])
        self.assertFalse(any("label" in name or "truth" in name for name in arrays))
        for position, source_index in enumerate((0, 2)):
            shape = crossfit.setup_shape(records[source_index].strokes)
            self.assertIsNotNone(shape)
            expected = np.frombuffer(rasterize(shape).pixels, np.uint8).reshape(1, 96, 256)
            np.testing.assert_array_equal(arrays["stored_rasters"][position], expected)

    def test_source_coverage_feature_hash_and_support_binding_tampering_fail(self):
        records, forward = fixture()
        cases = []
        cases.append((records[:-1], forward))
        duplicate = list(records); duplicate[-1] = records[0]; cases.append((tuple(duplicate), forward))
        changed = json.loads(json.dumps(forward)); changed["sourceLedger"][0]["rawRasterSHA256"] = "f" * 64
        changed["forward"]["A-to-B"]["trainingEpisodes"][0]["support"][0]["rawRasterSHA256"] = "f" * 64
        cases.append((records, changed))
        changed = json.loads(json.dumps(forward)); changed["sourceLedger"][2]["writer"] = "trn_UJI_W01"
        cases.append((records, changed))
        changed = json.loads(json.dumps(forward)); changed["forward"]["A-to-B"]["heldoutEpisodes"][0]["trueSupport"]["support"][0]["sourceKey"] = "e" * 64
        cases.append((records, changed))
        for index, (current_records, current_forward) in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(ValueError):
                data.build_raster_payload(current_records, current_forward)

    def test_shared_loader_never_opens_truth_and_validates_compact_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            records, forward, expected, truth, facts, calls, receipt = materialized_fixture(directory)
            self.assertFalse((Path(directory) / "score-truth.json").exists())
            opened = []
            original = data._read_regular

            def observed(path, **kwargs):
                opened.append(Path(path).name)
                return original(path, **kwargs)

            with patch.object(data, "_read_regular", side_effect=observed):
                arrays, loaded_receipt = data._load_raster_bundle(
                    Path(directory).resolve(), forward, expected_raw_rows=4, expected_stored_rows=2,
                    expected_forward_sha256=digest(data._canonical(forward)),
                    require_current_code=False,
                )
            self.assertEqual(opened, ["data-receipt.json", "rasters.npz"])
            self.assertEqual(loaded_receipt, receipt)
            for name in expected:
                np.testing.assert_array_equal(arrays[name], expected[name])
            self.assertEqual(receipt["truthFile"], "score-truth.json")
            self.assertEqual(receipt["truthSHA256"], digest(data._canonical(truth)))

    def test_loader_rejects_repacked_indices_rows_and_receipt_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            _, forward, arrays, truth, facts, _, _ = materialized_fixture(directory)
            root = Path(directory)

            def publish(current_arrays, *, mutate_receipt=None):
                raster_bytes = data._npz_bytes(current_arrays)
                receipt = data._receipt(
                    current_arrays, data._canonical(truth), raster_bytes, facts,
                    digest(data._canonical(forward)), {"synthetic": "0" * 64},
                )
                if mutate_receipt:
                    mutate_receipt(receipt)
                (root / "rasters.npz").write_bytes(raster_bytes)
                (root / "data-receipt.json").write_bytes(data._canonical(receipt))

            cases = []
            changed = {key: value.copy() for key, value in arrays.items()}
            changed["stored_source_indices"] = np.array([2, 0], np.int64)
            cases.append((changed, None))
            changed = {key: value.copy() for key, value in arrays.items()}
            changed["raw_rasters"][0, 0, 0, 0] ^= np.uint8(1)
            cases.append((changed, None))
            cases.append((arrays, lambda receipt: receipt["roleGuards"].update({"privateInkUsed": True})))
            cases.append((arrays, lambda receipt: receipt.update({"unrequestedMetadataFailures": 0})))
            for index, (current_arrays, mutation) in enumerate(cases):
                with self.subTest(index=index):
                    publish(current_arrays, mutate_receipt=mutation)
                    with self.assertRaises(ValueError):
                        data._load_raster_bundle(
                            root, forward, expected_raw_rows=4, expected_stored_rows=2,
                            expected_forward_sha256=digest(data._canonical(forward)),
                            require_current_code=False,
                        )

    def test_forward_plan_loader_opens_only_receipt_and_forward(self):
        _, forward = fixture()
        forward_bytes = data._canonical(forward)
        receipt = {
            "artifacts": {"forward-plan.json": digest(forward_bytes),
                          "unused-training-targets.json": "a" * 64,
                          "unused-scoring-ledger.json": "b" * 64},
            "protocolSHA256": data.PROTOCOL_SHA256,
            "bindings": forward["bindings"],
        }
        receipt_bytes = data._canonical(receipt)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / "forward-plan.json").write_bytes(forward_bytes)
            (root / "plan-receipt.json").write_bytes(receipt_bytes)
            opened = []
            original = data._read_regular

            def observed(path, **kwargs):
                opened.append(Path(path).name)
                return original(path, **kwargs)

            with (
                patch.object(data, "FORWARD_PLAN_SHA256", digest(forward_bytes)),
                patch.object(data, "PLAN_RECEIPT_SHA256", digest(receipt_bytes)),
                patch.object(data, "_read_regular", side_effect=observed),
            ):
                self.assertEqual(data.load_forward_plan(root), forward)
            self.assertEqual(opened, ["forward-plan.json", "plan-receipt.json"])

    def test_public_loader_refuses_synthetic_forward_and_code_map_is_complete(self):
        _, forward = fixture()
        with tempfile.TemporaryDirectory() as directory:
            materialized_fixture(directory)
            with self.assertRaises(ValueError):
                data.load_raster_bundle(Path(directory), forward)
        identity = data.code_identity()
        self.assertEqual(tuple(identity), data.CODE_PATHS)
        self.assertEqual(identity[data.PROTOCOL_PATH], data.PROTOCOL_SHA256)

    def test_npz_serialization_is_deterministic_and_has_only_three_numeric_arrays(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, arrays, _, _, _, _ = materialized_fixture(directory)
            first = data._npz_bytes(arrays)
            second = data._npz_bytes(arrays)
            self.assertEqual(first, second)
            archive_path = Path(directory) / "check.npz"
            archive_path.write_bytes(first)
            with np.load(archive_path, allow_pickle=False) as archive:
                self.assertEqual(set(archive.files), set(arrays))
                self.assertTrue(all(archive[name].dtype.kind in "uib" for name in archive.files))


if __name__ == "__main__":
    unittest.main()
