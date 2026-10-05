from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.research import personal_same_label_eligibility as eligibility


def _digest(value: int) -> str:
    return f"{value:064x}"


def _new(index: int, label: str, raster: str, geometry: str) -> dict:
    return {
        "opaqueID": _digest(1_000 + index),
        "sourceRecordID": _digest(2_000 + index),
        "sourceSymbolID": str(30 + index),
        "sourceLabel": label,
        "sourceRecordIndex": index,
        "source": "hwrt-literal",
        "writer": None,
        "session": None,
        "rasterSHA256": raster,
        "modelPlaneSHA256": _digest(3_000 + index),
        "normalizedGeometrySHA256": geometry,
        "encodingFailure": None,
        "sourceHASYPath": eligibility._source_hasy_path(index),
    }


def _old(index: int, raster: str, geometry: str, label: str = "ignored") -> dict:
    return {
        "opaqueID": _digest(9_000 + index),
        "rasterSHA256": raster,
        "normalizedGeometrySHA256": geometry,
        "label": label,
        "writer": "must-not-affect-eligibility",
    }


def _rows_by_id(result: dict) -> dict[str, dict]:
    return {row["opaqueID"]: row for row in result["rows"]}


class SameLabelEligibilityTests(unittest.TestCase):
    def test_transitive_hash_union_propagates_prior_input_exclusion(self) -> None:
        first = _new(1, "A", _digest(11), _digest(21))
        second = _new(2, "A", _digest(12), _digest(21))
        fallback = _new(3, "A", _digest(13), _digest(23))
        prior = eligibility.project_old_inputs([_old(1, _digest(12), _digest(29))])

        result = eligibility.build_eligibility(
            [first, second, fallback], prior, set(), required_labels=("A",)
        )
        rows = _rows_by_id(result)
        for row in (rows[first["opaqueID"]], rows[second["opaqueID"]]):
            self.assertFalse(row["eligible"])
            self.assertEqual(
                row["exclusionReasons"], ["component-touches-prior-training-input"]
            )
            self.assertEqual(row["componentOldRowCount"], 1)
        self.assertTrue(rows[fallback["opaqueID"]]["eligible"])

    def test_prior_labels_cannot_change_projection_or_eligibility(self) -> None:
        colliding = _new(1, "A", _digest(31), _digest(41))
        fallback = _new(2, "A", _digest(32), _digest(42))
        before = [_old(1, _digest(31), _digest(49), label="A")]
        after = [_old(1, _digest(31), _digest(49), label="unrelated-answer")]
        projected_before = eligibility.project_old_inputs(before)
        projected_after = eligibility.project_old_inputs(after)

        self.assertEqual(projected_before, projected_after)
        self.assertEqual(set(projected_before[0]), eligibility.OLD_FIELDS)
        self.assertEqual(
            eligibility.build_eligibility(
                [colliding, fallback], projected_before, set(), required_labels=("A",)
            ),
            eligibility.build_eligibility(
                [colliding, fallback], projected_after, set(), required_labels=("A",)
            ),
        )

    def test_hasy_pixel_duplicate_flag_propagates_to_whole_component(self) -> None:
        flagged = _new(1, "A", _digest(51), _digest(61))
        connected = _new(2, "A", _digest(52), _digest(61))
        fallback = _new(3, "A", _digest(53), _digest(63))

        result = eligibility.build_eligibility(
            [flagged, connected, fallback], [], {flagged["sourceHASYPath"]},
            required_labels=("A",),
        )
        rows = _rows_by_id(result)
        for row in (rows[flagged["opaqueID"]], rows[connected["opaqueID"]]):
            self.assertEqual(
                row["exclusionReasons"], ["component-touches-hasy-pixel-duplicate"]
            )
            self.assertFalse(row["eligible"])
        self.assertTrue(rows[fallback["opaqueID"]]["eligible"])

    def test_conflicts_exclude_component_and_same_label_keeps_minimum_id(self) -> None:
        conflict_a = _new(1, "A", _digest(71), _digest(81))
        conflict_b = _new(2, "B", _digest(72), _digest(81))
        keep_a = _new(3, "A", _digest(73), _digest(83))
        keep_b = _new(4, "B", _digest(74), _digest(84))
        duplicate_later = _new(6, "C", _digest(75), _digest(85))
        duplicate_first = _new(5, "C", _digest(75), _digest(86))

        result = eligibility.build_eligibility(
            [conflict_a, conflict_b, keep_a, keep_b, duplicate_later, duplicate_first],
            [], set(), required_labels=("A", "B", "C"),
        )
        rows = _rows_by_id(result)
        self.assertEqual(
            rows[conflict_a["opaqueID"]]["exclusionReasons"],
            ["component-conflicting-new-labels"],
        )
        self.assertEqual(
            rows[conflict_b["opaqueID"]]["exclusionReasons"],
            ["component-conflicting-new-labels"],
        )
        self.assertTrue(rows[duplicate_first["opaqueID"]]["eligible"])
        self.assertEqual(
            rows[duplicate_later["opaqueID"]]["exclusionReasons"],
            ["same-label-component-nonrepresentative"],
        )
        self.assertEqual(
            result["selectedOpaqueIDs"],
            sorted([keep_a["opaqueID"], keep_b["opaqueID"], duplicate_first["opaqueID"]]),
        )
        self.assertEqual(
            result["byClass"]["C"]["eligibleComponentMultiplicityCounts"], {"2": 1}
        )

    def test_every_fixed_class_must_retain_an_eligible_record(self) -> None:
        only = _new(1, "A", _digest(91), _digest(101))
        prior = eligibility.project_old_inputs([_old(1, _digest(91), _digest(109))])
        with self.assertRaisesRegex(ValueError, "lost all eligible records: A"):
            eligibility.build_eligibility([only], prior, set(), required_labels=("A",))

    def test_hasy_ledger_is_hash_pinned_and_paths_are_exact(self) -> None:
        payload = json.dumps([
            {"pngMembers": ["hasy-data/v2-17074.png", "hasy-data/v2-17075.png"]}
        ]).encode()
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            path = Path(temporary) / "pixel_duplicates.json"
            path.write_bytes(payload)
            with mock.patch.object(
                eligibility, "HASY_PIXEL_LEDGER_SHA256", eligibility._sha(payload)
            ):
                paths, retained = eligibility._load_hasy_duplicate_paths(path)
                self.assertEqual(retained, payload)
                self.assertEqual(
                    paths, {"hasy-data/v2-17074.png", "hasy-data/v2-17075.png"}
                )
                self.assertEqual(eligibility._source_hasy_path(0), "hasy-data/v2-17074.png")
                path.write_bytes(payload + b"\n")
                with self.assertRaisesRegex(ValueError, "ledger changed"):
                    eligibility._load_hasy_duplicate_paths(path)

    def test_loader_requires_exact_receipt_and_binds_both_artifacts(self) -> None:
        retained = _new(1, "A", _digest(111), _digest(121))
        result = eligibility.build_eligibility(
            [retained], [], set(), required_labels=("A",)
        )
        selected = {
            "version": eligibility.SELECTED_VERSION,
            "selectedOpaqueIDs": result["selectedOpaqueIDs"],
            "byClass": result["byClass"],
        }
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temporary:
            directory = Path(temporary)
            (directory / "eligibility.json").write_bytes(canonical_json_bytes(result))
            (directory / "selected-ids.json").write_bytes(canonical_json_bytes(selected))
            artifacts = {
                name: eligibility.parent_data._artifact(directory / name)
                for name in ("eligibility.json", "selected-ids.json")
            }
            receipt = {
                "version": eligibility.VERSION,
                "protocolSHA256": eligibility.PROTOCOL_SHA256,
                "inputBindings": {
                    "encodedDataReceiptSHA256": eligibility.ENCODED_RECEIPT_SHA256,
                    "encodedRowsSHA256": eligibility.ENCODED_ROWS_SHA256,
                    "oldDataReceiptSHA256": eligibility.literal_data.OLD_DATA_RECEIPT_SHA256,
                    "oldTrainingMetadataSHA256": eligibility.literal_data.OLD_TRAINING_SHA256,
                    "hasyPixelDuplicateLedgerSHA256": eligibility.HASY_PIXEL_LEDGER_SHA256,
                    "encodedSourceBindings": {},
                },
                "counts": {
                    "sourceRows": 1, "priorTrainingInputRows": 0,
                    "hasyDuplicatePathRows": 0, "eligibleRows": 1, "excludedRows": 0,
                },
                "selectedOpaqueIDs": result["selectedOpaqueIDs"],
                "byClass": result["byClass"],
                "exclusionReasonCounts": {},
                "artifacts": artifacts,
                "codeSHA256": eligibility.code_identity(),
                "roleGuards": {
                    "oldLabelsConsumedByEligibility": False,
                    "predictionOutcomesUsed": False,
                    "privateDataUsed": False,
                    "dedicatedDevelopmentOrQueryArtifactsRead": False,
                    "priorTrainingContainsInternalHoldouts": True,
                    "sourceRecordsModified": False,
                    "modelFittingOrInferencePerformed": False,
                },
            }
            receipt_bytes = canonical_json_bytes(receipt)
            (directory / "eligibility-receipt.json").write_bytes(receipt_bytes)
            loaded, loaded_receipt = eligibility.load_eligibility(
                directory, eligibility._sha(receipt_bytes)
            )
            self.assertEqual(loaded, result)
            self.assertEqual(loaded_receipt, receipt)
            (directory / "selected-ids.json").write_bytes(
                canonical_json_bytes({**selected, "selectedOpaqueIDs": []})
            )
            with self.assertRaisesRegex(ValueError, "artifact identity changed"):
                eligibility.load_eligibility(directory, eligibility._sha(receipt_bytes))


if __name__ == "__main__":
    unittest.main()
