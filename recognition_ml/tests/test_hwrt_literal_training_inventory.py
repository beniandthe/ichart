import csv
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from ichart_recognition_ml.research import hwrt_literal_training_inventory as inventory
from ichart_recognition_ml.research import hwrt_source_intake as intake


def source_class(symbol_id, label, training, test=0):
    return {
        "canonicalChordLabel": None,
        "declaredTestSamples": test,
        "declaredTrainingSamples": training,
        "observedTestSamples": test,
        "observedTrainingSamples": training,
        "selectedForGeometryAudit": False,
        "sourceLabel": label,
        "sourceSymbolID": str(symbol_id),
    }


def csv_bytes(header, rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(
        stream, fieldnames=header, delimiter=";", quotechar="'", lineterminator="\n"
    )
    writer.writeheader(); writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def symbols_bytes(classes):
    return csv_bytes(intake.SYMBOL_HEADER, ({
        "symbol_id": row["sourceSymbolID"],
        "latex": row["sourceLabel"],
        "training_samples": str(row["declaredTrainingSamples"]),
        "test_samples": str(row["declaredTestSamples"]),
    } for row in classes))


def data_row(symbol_id, payload, user="secret-user"):
    return {
        "symbol_id": str(symbol_id), "user_id": user,
        "data": payload, "user_agent": "synthetic-test",
    }


def point_payload(points):
    return json.dumps([points], separators=(",", ":"))


def member_identity(payload):
    return {"bytes": len(payload), "sha256": inventory._sha(payload)}


def tar_bytes(members):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:bz2") as archive:
        for name in intake.MEMBERS:
            payload = members[name]
            member = tarfile.TarInfo(name); member.size = len(payload)
            archive.addfile(member, io.BytesIO(payload))
    return stream.getvalue()


def scan(classes, training_rows, allowed, *, test_payload=b"not,csv\n", row_reader=intake.read_stream,
         expected_members=None, symbol_classes=None):
    members = {
        "symbols.csv": symbols_bytes(symbol_classes or classes),
        "test-data.csv": test_payload,
        "train-data.csv": csv_bytes(intake.DATA_HEADER, training_rows),
    }
    expected = expected_members or {name: member_identity(payload) for name, payload in members.items()}
    with tarfile.open(fileobj=io.BytesIO(tar_bytes(members)), mode="r|bz2") as archive:
        return inventory.scan_tar(
            archive,
            archive_identity={"bytes": 1, "md5": "0" * 32, "sha256": "a" * 64},
            classes=classes,
            allowed_labels=allowed,
            expected_members=expected,
            expected_training_count=len(training_rows),
            expected_literal_class_count=sum(row["sourceLabel"] in allowed for row in classes),
            row_reader=row_reader,
        )


class HWRTLiteralTrainingInventoryTests(unittest.TestCase):
    def test_selection_is_strict_literal_and_test_member_is_never_parsed(self):
        classes = [
            source_class(1, "A", 1), source_class(2, "a", 1),
            source_class(3, "#", 1), source_class(4, "\\#", 1),
        ]
        rows = [
            data_row(index, point_payload([{"x": index, "y": 0, "time": 0}]))
            for index in range(1, 5)
        ]
        parsed_headers = []

        def observed_reader(lines, header):
            parsed_headers.append(tuple(header))
            yield from intake.read_stream(lines, header)

        result = scan(classes, rows, ("A", "a", "#"), row_reader=observed_reader)
        self.assertEqual(parsed_headers, [intake.SYMBOL_HEADER, intake.DATA_HEADER])
        self.assertTrue(result["testMemberHashedWithoutCSVOrGeometryParsing"])
        self.assertEqual([row["sourceLabel"] for row in result["records"]], ["A", "a", "#"])
        self.assertNotIn("\\#", result["classReport"]["overlapLabels"])
        self.assertFalse(result["classReport"]["aliasesCaseFoldingOrTeXNormalizationUsed"])
        expected_id = intake._sha(("a" * 64 + "\0train\0" + "0").encode())
        self.assertEqual(result["records"][0]["recordID"], expected_id)
        self.assertNotIn("secret-user", json.dumps(result, sort_keys=True))

    def test_symbols_counts_and_member_hashes_fail_closed(self):
        classes = [source_class(1, "A", 1), source_class(2, "B", 1)]
        rows = [
            data_row(1, point_payload([{"x": 0, "y": 0, "time": 0}])),
            data_row(2, point_payload([{"x": 1, "y": 1, "time": 0}])),
        ]
        changed_label = [dict(classes[0]), dict(classes[1])]
        changed_label[0]["sourceLabel"] = "C"
        with self.assertRaisesRegex(ValueError, "metadata"):
            scan(changed_label, rows, ("C", "B"), symbol_classes=classes)
        changed_count = [dict(classes[0]), dict(classes[1])]
        changed_count[0]["declaredTrainingSamples"] = 2
        changed_count[0]["observedTrainingSamples"] = 2
        with self.assertRaisesRegex(ValueError, "count"):
            scan(changed_count, rows, ("A", "B"))
        members = {
            "symbols.csv": symbols_bytes(classes), "test-data.csv": b"not,csv\n",
            "train-data.csv": csv_bytes(intake.DATA_HEADER, rows),
        }
        expected = {name: member_identity(payload) for name, payload in members.items()}
        expected["test-data.csv"] = {**expected["test-data.csv"], "sha256": "f" * 64}
        with self.assertRaisesRegex(ValueError, "test member"):
            scan(classes, rows, ("A", "B"), expected_members=expected)

    def test_invalid_and_timing_rows_are_retained_and_duplicates_are_scoped(self):
        classes = [source_class(1, "A", 3), source_class(2, "B", 1)]
        nonmonotonic = point_payload([
            {"x": 0, "y": 0, "time": 2}, {"x": 1, "y": 1, "time": 1},
        ])
        rows = [
            data_row(1, nonmonotonic),
            data_row(1, "[]"),
            data_row(1, point_payload([{"x": 2, "time": 0}])),
            data_row(2, nonmonotonic),
        ]
        result = scan(classes, rows, ("A", "B"))
        self.assertEqual(len(result["records"]), 4)
        self.assertEqual(result["selectedTrainingInvalidTrajectoryCount"], 2)
        self.assertEqual(result["selectedTrainingTimingIssueCount"], 2)
        self.assertIn("emptyTrajectory", result["records"][1]["issues"])
        self.assertIn("missingCoordinate", result["records"][2]["issues"])
        raw = result["duplicateLedger"]["rawDataSelectedTraining"]
        coordinate = result["duplicateLedger"]["coordinatePayloadIgnoringTimingSelectedTraining"]
        self.assertEqual(raw["duplicateGroupCount"], 1)
        self.assertEqual(raw["labelConflictGroupCount"], 1)
        self.assertEqual(coordinate["duplicateGroupCount"], 1)
        self.assertEqual(coordinate["unavailableRecordCount"], 1)
        self.assertEqual(result["duplicateLedger"]["scope"], "literal-selected-training-rows-only")

    def test_input_schema_and_exact_hash_pins_reject_mismatch(self):
        classes = [source_class(1, "A", 1)]
        malformed = [dict(classes[0])]
        malformed[0]["unexpected"] = True
        with self.assertRaisesRegex(ValueError, "schema"):
            inventory._validate_classes(malformed)
        with self.assertRaisesRegex(ValueError, "schema"):
            inventory._validate_domain({"version": "chord-recognition-domain-v1"})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("classes.json", "receipt.json", "domain.json"):
                (root / name).write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "changed"):
                inventory._load_pinned_inputs(
                    root / "classes.json", root / "receipt.json", root / "domain.json"
                )

    def test_source_receipt_counts_and_output_exclusivity_are_enforced(self):
        classes = [source_class(1, "A", 1)]
        classes_bytes = inventory._canonical(classes)
        members = {
            name: {"bytes": index + 1, "sha256": str(index) * 64}
            for index, name in enumerate(intake.MEMBERS, start=1)
        }
        receipt = {
            "version": intake.VERSION,
            "archive": {
                "bytes": intake.ARCHIVE_BYTES, "md5": intake.ARCHIVE_MD5,
                "sha256": intake.ARCHIVE_SHA256,
            },
            "members": members, "memberCount": 3, "classCount": 1,
            "trainingRecordCount": 1, "testRecordCount": 0, "recordCount": 1,
            "artifacts": {"source_classes.json": member_identity(classes_bytes)},
            "allMetadataRowsCounted": True,
            "canonicalChordMappingPerformed": False,
            "modelOrFeatureWorkPerformed": False,
        }
        inventory._validate_source_receipt(receipt, classes, member_identity(classes_bytes))
        changed = dict(receipt); changed["trainingRecordCount"] = 2
        with self.assertRaisesRegex(ValueError, "contract"):
            inventory._validate_source_receipt(changed, classes, member_identity(classes_bytes))
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "artifact.json"
            inventory._write_exclusive(target, b"first")
            with self.assertRaises(FileExistsError):
                inventory._write_exclusive(target, b"overwrite")
            repository = Path(directory) / "repository"
            repository.mkdir(); (repository / ".git").mkdir()
            with self.assertRaises(ValueError):
                intake._fresh_output(repository / "forbidden-output")


if __name__ == "__main__":
    unittest.main()
