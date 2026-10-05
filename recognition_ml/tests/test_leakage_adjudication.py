import contextlib
import hashlib
import io
import json
import tempfile
import unittest
import uuid
from pathlib import Path

from corpus_v2_fixture import record_mapping
from ichart_recognition_ml.cli import main
from ichart_recognition_ml.contracts import CorpusRecord, canonical_json_bytes
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.features import InkPoint, InkStroke, encode_feature_artifacts
from ichart_recognition_ml.leakage_adjudication import (
    DECISION_DISTINCT,
    DECISION_SAME,
    LEAKAGE_ADJUDICATION_PROTOCOL_VERSION,
    LEAKAGE_ADJUDICATION_SCHEMA_VERSION,
    build_leakage_cluster_receipt,
    scan_report_sha256,
)
from ichart_recognition_ml.leakage_scan import build_leakage_scan_report


def _stroke(*points):
    return InkStroke(
        tuple(
            InkPoint(float(x), float(y), float(index) * 0.01)
            for index, (x, y) in enumerate(points)
        )
    )


class LeakageAdjudicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.data_root = self.root / "features"
        (self.data_root / "trajectory").mkdir(parents=True)
        (self.data_root / "raster").mkdir(parents=True)

    def materialize(self, index, strokes, *, split="development"):
        trajectory, raster = encode_feature_artifacts(tuple(strokes))
        trajectory_payload = trajectory.to_bytes()
        raster_payload = raster.to_bytes()
        trajectory_path = self.data_root / "trajectory" / f"{index}.f32le"
        raster_path = self.data_root / "raster" / f"{index}.u8"
        trajectory_path.write_bytes(trajectory_payload)
        raster_path.write_bytes(raster_payload)
        return record_mapping(
            index,
            split,
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

    def records(self, *mappings):
        return tuple(
            CorpusRecord.from_mapping(mapping, f"records[{index}]")
            for index, mapping in enumerate(mappings)
        )

    def report_with_three_candidates(self):
        first = self.materialize(
            1,
            (_stroke((0, 0), (4, 8), (8, 0)), _stroke((2, 4), (6, 4))),
        )
        second = self.materialize(
            2,
            (_stroke((10, 10), (18, 26), (26, 10)), _stroke((14, 18), (22, 18))),
            split="calibration",
        )
        third = self.materialize(
            3,
            (_stroke((0, 0), (4.1, 8), (8, 0)), _stroke((2, 4), (6, 4.1))),
            split="sealed-evaluation",
        )
        records = self.records(first, second, third)
        return records, build_leakage_scan_report(records, self.data_root)

    def adjudication(self, report, decisions):
        return {
            "adjudication_protocol_version": LEAKAGE_ADJUDICATION_PROTOCOL_VERSION,
            "decisions": decisions,
            "scan_report_sha256": scan_report_sha256(report),
            "schema_version": LEAKAGE_ADJUDICATION_SCHEMA_VERSION,
        }

    def decision(
        self,
        candidate,
        final,
        *,
        disagree=False,
    ):
        first = DECISION_SAME if not disagree else DECISION_DISTINCT
        second = final
        if not disagree:
            first = final
        return {
            "adjudicator_decision": final if disagree else None,
            "adjudicator_id_hash": f"{303:064x}" if disagree else None,
            "final_decision": final,
            "first_decision": first,
            "first_reviewer_id_hash": f"{101:064x}",
            "left_sample_id": candidate["left_sample_id"],
            "right_sample_id": candidate["right_sample_id"],
            "second_decision": second,
            "second_reviewer_id_hash": f"{202:064x}",
        }

    def all_same_decisions(self, report):
        return [
            self.decision(candidate, DECISION_SAME)
            for candidate in report["candidate_pairs"]
        ]

    def write_json(self, path, value):
        path.write_bytes(canonical_json_bytes(value) + b"\n")

    def test_every_candidate_requires_two_independent_reviews(self):
        _, report = self.report_with_three_candidates()
        decisions = self.all_same_decisions(report)
        decisions[0]["second_reviewer_id_hash"] = decisions[0][
            "first_reviewer_id_hash"
        ]
        with self.assertRaisesRegex(ContractError, "reviewers_not_independent"):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, decisions)
            )

    def test_disagreement_requires_an_independent_adjudicator(self):
        _, report = self.report_with_three_candidates()
        decisions = self.all_same_decisions(report)
        decisions[0] = self.decision(
            report["candidate_pairs"][0], DECISION_SAME, disagree=True
        )
        decisions[0]["adjudicator_id_hash"] = decisions[0][
            "first_reviewer_id_hash"
        ]
        with self.assertRaisesRegex(ContractError, "adjudicator_not_independent"):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, decisions)
            )

        decisions[0]["adjudicator_id_hash"] = f"{303:064x}"
        receipt = build_leakage_cluster_receipt(
            report, self.adjudication(report, decisions)
        )
        self.assertTrue(receipt["all_candidates_resolved"])

    def test_missing_or_extra_candidate_decision_is_rejected(self):
        _, report = self.report_with_three_candidates()
        decisions = self.all_same_decisions(report)
        with self.assertRaisesRegex(ContractError, "adjudication_completeness_mismatch"):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, decisions[:-1])
            )

        extra = dict(decisions[-1])
        extra["left_sample_id"], extra["right_sample_id"] = (
            report["artifact_commitments"][0]["sample_id"],
            str(uuid.UUID(int=999)),
        )
        with self.assertRaisesRegex(
            ContractError, "noncanonical_adjudication_decisions|adjudication_completeness_mismatch"
        ):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, sorted(decisions + [extra], key=lambda item: (item["left_sample_id"], item["right_sample_id"])))
            )

    def test_exact_content_cannot_be_marked_distinct(self):
        _, report = self.report_with_three_candidates()
        exact = next(
            candidate
            for candidate in report["candidate_pairs"]
            if candidate["tier"] == "exact-content"
        )
        decisions = self.all_same_decisions(report)
        index = report["candidate_pairs"].index(exact)
        decisions[index] = self.decision(exact, DECISION_DISTINCT)
        with self.assertRaisesRegex(ContractError, "exact_content_marked_distinct"):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, decisions)
            )

    def test_transitive_same_and_distinct_conflict_is_rejected(self):
        _, report = self.report_with_three_candidates()
        self.assertEqual(report["candidate_pair_count"], 3)
        decisions = self.all_same_decisions(report)
        nonexact_index = next(
            index
            for index, candidate in enumerate(report["candidate_pairs"])
            if candidate["tier"] != "exact-content"
        )
        decisions[nonexact_index] = self.decision(
            report["candidate_pairs"][nonexact_index], DECISION_DISTINCT
        )
        with self.assertRaisesRegex(ContractError, "transitive_adjudication_conflict"):
            build_leakage_cluster_receipt(
                report, self.adjudication(report, decisions)
            )

    def test_resolved_clusters_are_deterministic_and_unsigned(self):
        _, report = self.report_with_three_candidates()
        adjudication = self.adjudication(report, self.all_same_decisions(report))
        first = build_leakage_cluster_receipt(report, adjudication)
        second = build_leakage_cluster_receipt(report, adjudication)
        self.assertEqual(first, second)
        self.assertEqual(first["cluster_count"], 1)
        self.assertEqual(first["authority"], "unsigned-registry-preparation-only")
        self.assertFalse(first["registry_signed"])
        self.assertFalse(first["corpus_qualified"])

    def test_cli_recomputes_scan_and_refuses_tampered_report(self):
        records, report = self.report_with_three_candidates()
        mappings = [record.as_dict() for record in records]
        records_path = self.root / "records.jsonl"
        records_path.write_bytes(
            b"".join(canonical_json_bytes(value) + b"\n" for value in mappings)
        )
        report_path = self.root / "leakage_scan.json"
        adjudication_path = self.root / "adjudication.json"
        self.write_json(report_path, report)
        self.write_json(
            adjudication_path,
            self.adjudication(report, self.all_same_decisions(report)),
        )
        output = self.root / "finalized"
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = main(
                [
                    "finalize-leakage-adjudication",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--scan-report",
                    str(report_path),
                    "--adjudication",
                    str(adjudication_path),
                    "--output-dir",
                    str(output),
                ]
            )
        self.assertEqual(code, 0)
        response = json.loads(stdout.getvalue())
        self.assertFalse(response["registry_signed"])
        self.assertTrue((output / "leakage_cluster_receipt.json").is_file())

        tampered = dict(report)
        tampered["candidate_pairs"] = []
        tampered["candidate_pair_count"] = 0
        tampered["tier_counts"] = {
            "exact-content": 0,
            "high-similarity": 0,
            "manual-review": 0,
        }
        tampered["requires_protected_adjudication"] = False
        tampered_path = self.root / "tampered.json"
        self.write_json(tampered_path, tampered)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            rejected = main(
                [
                    "finalize-leakage-adjudication",
                    "--records",
                    str(records_path),
                    "--data-root",
                    str(self.data_root),
                    "--scan-report",
                    str(tampered_path),
                    "--adjudication",
                    str(adjudication_path),
                    "--output-dir",
                    str(self.root / "tampered-output"),
                ]
            )
        self.assertEqual(rejected, 2)
        self.assertEqual(
            json.loads(stderr.getvalue())["error"]["code"], "scan_report_mismatch"
        )


if __name__ == "__main__":
    unittest.main()
