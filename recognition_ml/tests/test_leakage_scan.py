import contextlib
import copy
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from corpus_v2_fixture import record_mapping
from ichart_recognition_ml.cli import main
from ichart_recognition_ml.contracts import CorpusRecord, canonical_json_bytes
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.features import InkPoint, InkStroke, encode_feature_artifacts
from ichart_recognition_ml.leakage_scan import (
    LeakageScanConfig,
    build_leakage_scan_report,
)


def _stroke(*points):
    return InkStroke(tuple(InkPoint(float(x), float(y), float(index) * 0.01) for index, (x, y) in enumerate(points)))


class LeakageScanTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.data_root = self.root / "features"
        (self.data_root / "trajectory").mkdir(parents=True)
        (self.data_root / "raster").mkdir(parents=True)

    def materialize(self, index, strokes, *, label="C△7", split="development"):
        trajectory, raster = encode_feature_artifacts(tuple(strokes))
        trajectory_payload = trajectory.to_bytes()
        raster_payload = raster.to_bytes()
        trajectory_path = self.data_root / "trajectory" / f"{index}.f32le"
        raster_path = self.data_root / "raster" / f"{index}.u8"
        trajectory_path.write_bytes(trajectory_payload)
        raster_path.write_bytes(raster_payload)
        mapping = record_mapping(
            index,
            split,
            label,
            trajectory={
                "relative_path": f"trajectory/{index}.f32le",
                "sha256": hashlib.sha256(trajectory_payload).hexdigest(),
                "byte_count": len(trajectory_payload),
                "encoding": "float32-le",
            },
            raster={
                "relative_path": f"raster/{index}.u8",
                "sha256": hashlib.sha256(raster_payload).hexdigest(),
                "byte_count": len(raster_payload),
                "encoding": "uint8-gray",
            },
        )
        return mapping

    def records(self, *mappings):
        return tuple(
            CorpusRecord.from_mapping(value, f"records[{index}]")
            for index, value in enumerate(mappings)
        )

    def write_records(self, *mappings):
        path = self.root / "records.jsonl"
        path.write_bytes(b"".join(canonical_json_bytes(value) + b"\n" for value in mappings))
        return path

    def test_translation_and_scale_equivalent_geometry_is_an_exact_candidate(self):
        first = self.materialize(
            1,
            (_stroke((0, 0), (4, 8), (8, 0)), _stroke((2, 4), (6, 4))),
        )
        second = self.materialize(
            2,
            (_stroke((100, 50), (108, 66), (116, 50)), _stroke((104, 58), (112, 58))),
            split="calibration",
        )

        report = build_leakage_scan_report(self.records(first, second), self.data_root)

        self.assertEqual(report["candidate_pair_count"], 1)
        self.assertEqual(report["candidate_pairs"][0]["tier"], "exact-content")
        self.assertIn(
            "same-raster-digest", report["candidate_pairs"][0]["reasons"]
        )
        self.assertFalse(report["corpus_qualified"])
        self.assertTrue(report["requires_protected_adjudication"])
        self.assertFalse(report["labels_inspected"])

    def test_small_geometric_change_is_reviewed_but_different_shape_is_not(self):
        base = self.materialize(
            10,
            (_stroke((0, 0), (5, 10), (10, 0)), _stroke((2, 4), (8, 4))),
        )
        near = self.materialize(
            11,
            (_stroke((0, 0), (5.2, 10), (10, 0)), _stroke((2, 4.2), (8, 4))),
            split="calibration",
        )
        different = self.materialize(
            12,
            (_stroke((0, 0), (0, 10)), _stroke((0, 10), (10, 10))),
            split="sealed-evaluation",
        )

        report = build_leakage_scan_report(
            self.records(base, near, different), self.data_root
        )

        pairs = {
            (item["left_sample_id"], item["right_sample_id"]): item
            for item in report["candidate_pairs"]
        }
        expected_pair = tuple(sorted((base["sample_id"], near["sample_id"])))
        self.assertIn(expected_pair, pairs)
        self.assertIn(
            pairs[expected_pair]["tier"], ("high-similarity", "manual-review")
        )
        self.assertEqual(len(pairs), 1)
        self.assertEqual(report["pair_comparison_count"], 3)

    def test_pair_decision_is_label_blind(self):
        first = self.materialize(
            20,
            (_stroke((0, 0), (4, 9), (8, 0)), _stroke((2, 4), (6, 4))),
            label="B",
        )
        second = self.materialize(
            21,
            (_stroke((40, 10), (48, 28), (56, 10)), _stroke((44, 18), (52, 18))),
            label="G7",
            split="calibration",
        )
        first_alternate = copy.deepcopy(first)
        second_alternate = copy.deepcopy(second)
        for mapping, label in ((first_alternate, "C-7"), (second_alternate, "Db△9")):
            mapping["canonical_label"] = label
            mapping["prompted_intent"]["canonical_label"] = label
            mapping["writer_confirmed_intent"]["canonical_label"] = label
            mapping["first_reader_transcription"]["canonical_label"] = label
            mapping["second_reader_transcription"]["canonical_label"] = label
            mapping["adjudication"]["canonical_label"] = label

        original = build_leakage_scan_report(
            self.records(first, second), self.data_root
        )
        relabeled = build_leakage_scan_report(
            self.records(first_alternate, second_alternate), self.data_root
        )

        self.assertEqual(original["candidate_pairs"], relabeled["candidate_pairs"])
        self.assertNotEqual(original["records_sha256"], relabeled["records_sha256"])

    def test_input_order_does_not_change_report(self):
        mappings = (
            self.materialize(30, (_stroke((0, 0), (4, 8), (8, 0)),)),
            self.materialize(
                31,
                (_stroke((20, 20), (28, 36), (36, 20)),),
                split="calibration",
            ),
            self.materialize(
                32,
                (_stroke((0, 0), (10, 0)),),
                split="sealed-evaluation",
            ),
        )
        forward = build_leakage_scan_report(self.records(*mappings), self.data_root)
        reverse = build_leakage_scan_report(
            self.records(*reversed(mappings)), self.data_root
        )
        self.assertEqual(forward, reverse)
        self.assertEqual(
            canonical_json_bytes(forward), canonical_json_bytes(reverse)
        )

    def test_tampered_feature_artifact_is_rejected_before_comparison(self):
        mapping = self.materialize(40, (_stroke((0, 0), (10, 10)),))
        (self.data_root / mapping["raster"]["relative_path"]).write_bytes(
            b"\0" * mapping["raster"]["byte_count"]
        )
        with self.assertRaisesRegex(ContractError, "artifact_digest_mismatch"):
            build_leakage_scan_report(self.records(mapping), self.data_root)

    def test_scanner_version_mismatch_is_rejected(self):
        mapping = self.materialize(50, (_stroke((0, 0), (10, 10)),))
        mapping["leakage_check_version"] = "near-neighbor-v2"
        with self.assertRaisesRegex(ContractError, "leakage_scanner_version_mismatch"):
            build_leakage_scan_report(self.records(mapping), self.data_root)

    def test_capacity_guard_refuses_instead_of_silently_skipping_pairs(self):
        first = self.materialize(60, (_stroke((0, 0), (10, 10)),))
        second = self.materialize(
            61, (_stroke((0, 0), (10, 0)),), split="calibration"
        )
        config = LeakageScanConfig(maximum_root_sample_count=1)
        with self.assertRaisesRegex(ContractError, "leakage_scan_capacity_exceeded"):
            build_leakage_scan_report(
                self.records(first, second), self.data_root, config
            )

    def test_cli_publishes_an_immutable_candidate_only_report(self):
        first = self.materialize(70, (_stroke((0, 0), (4, 8), (8, 0)),))
        second = self.materialize(
            71,
            (_stroke((10, 10), (18, 26), (26, 10)),),
            split="calibration",
        )
        records_path = self.write_records(first, second)
        output = self.root / "scan-output"
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = main(
                [
                    "scan-leakage",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--output-dir",
                    str(output),
                ]
            )
        self.assertEqual(code, 0)
        response = json.loads(stdout.getvalue())
        report = json.loads((output / "leakage_scan.json").read_text())
        self.assertEqual(response["authority"], "candidate-generation-only")
        self.assertFalse(response["corpus_qualified"])
        self.assertFalse(report["corpus_qualified"])

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            repeated = main(
                [
                    "scan-leakage",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--output-dir",
                    str(output),
                ]
            )
        self.assertEqual(repeated, 2)
        self.assertEqual(
            json.loads(stderr.getvalue())["error"]["code"],
            "output_directory_exists",
        )


if __name__ == "__main__":
    unittest.main()
