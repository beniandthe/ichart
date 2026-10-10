"""Synthetic HWRT intake contracts; no official corpus or model execution."""
import csv
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from ichart_recognition_ml.research import hwrt_source_intake as intake


def csv_data(header, rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=header, delimiter=";", quotechar="'",
                            lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode()


def point(x, y, time=0, *, include_time=True):
    result = {"x": x, "y": y}
    if include_time:
        result["time"] = time
    return result


class HWRTSourceIntakeTests(unittest.TestCase):
    IDS = tuple(sorted(intake.SELECTED_SYMBOL_IDS, key=int))

    def members(self, *, symbols=None, train=None, test=None):
        symbols = symbols or [{"symbol_id": value, "latex": f"native-{value}",
                               "training_samples": "1", "test_samples": "1"} for value in self.IDS]
        def rows(role):
            offset = 0 if role == "train" else 1000
            return [{"symbol_id": value, "user_id": f"opaque-{i}",
                     "data": json.dumps([[point(offset + i, i + 1, 10),
                                           point(offset + i + 1, i + 1, 11)]]),
                     "user_agent": role} for i, value in enumerate(self.IDS)]
        return {"symbols.csv": csv_data(intake.SYMBOL_HEADER, symbols),
                "test-data.csv": csv_data(intake.DATA_HEADER, test or rows("test")),
                "train-data.csv": csv_data(intake.DATA_HEADER, train or rows("train"))}

    def archive(self, root, *, members=None, extras=()):
        path = root / "source.tar"
        with tarfile.open(path, "w:bz2") as archive:
            for name, data in (members or self.members()).items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            for member, data in extras:
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
        return path

    def audit(self, *, members=None, extras=(), row_reader=intake.read_stream):
        with tempfile.TemporaryDirectory() as directory:
            path = self.archive(Path(directory), members=members, extras=extras)
            data = path.read_bytes()
            identity = {"bytes": len(data), "md5": hashlib.md5(data).hexdigest(),
                        "sha256": hashlib.sha256(data).hexdigest()}
            with tarfile.open(path, "r|bz2") as archive:
                return intake.audit_tar(archive, archive_identity=identity, row_reader=row_reader)

    def test_stream_schema_counts_native_identity_and_selected_geometry_are_exact(self):
        calls = []
        def reader(lines, header):
            calls.append(tuple(header))
            return intake.read_stream(lines, header)
        report = self.audit(row_reader=reader)
        receipt = report["receipt"]
        self.assertEqual((receipt["classCount"], receipt["recordCount"],
                          receipt["trainingRecordCount"], receipt["testRecordCount"]),
                         (12, 24, 12, 12))
        self.assertEqual(calls, [intake.SYMBOL_HEADER, intake.DATA_HEADER, intake.DATA_HEADER])
        self.assertEqual(len(report["selectedRecords"]), 24)
        first = report["selectedRecords"][0]
        self.assertEqual((first["role"], first["recordIndex"], first["sourceLabel"]),
                         ("test", 0, f"native-{self.IDS[0]}"))
        self.assertEqual(first["strokes"][0][0], {"x": 1000, "y": 1, "time": 10})
        self.assertIsNone(first["canonicalChordLabel"])
        self.assertFalse(first["writerIdentityReliable"])
        self.assertNotIn("sourceUserID", first)
        self.assertEqual(len(first["userIDHash"]), 64)
        self.assertTrue(all(row["observedTrainingSamples"] == row["declaredTrainingSamples"] == 1
                            and row["observedTestSamples"] == row["declaredTestSamples"] == 1
                            for row in report["classes"]))

    def test_unsafe_extra_missing_duplicate_and_link_members_are_rejected(self):
        for name in ("../escape", "/escape", "nested/train-data.csv", "extra.csv"):
            with self.subTest(name=name):
                member = tarfile.TarInfo(name)
                with self.assertRaisesRegex(ValueError, "Unsafe|Unexpected"):
                    self.audit(extras=[(member, b"x")])
        link = tarfile.TarInfo("extra-link")
        link.type = tarfile.SYMTYPE
        link.linkname = "symbols.csv"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.audit(extras=[(link, b"")])
        duplicate = tarfile.TarInfo("symbols.csv")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.audit(extras=[(duplicate, b"x")])
        members = self.members()
        members.pop("train-data.csv")
        with self.assertRaisesRegex(ValueError, "Missing/extra"):
            self.audit(members=members)

    def test_strict_headers_row_width_ids_and_declared_counts_fail_closed(self):
        cases = []
        members = self.members()
        cases.append(({**members, "test-data.csv": b"symbol_id;user_id;wrong;user_agent\n"}, "header"))
        cases.append(({**members, "train-data.csv": b"symbol_id;user_id;data;user_agent\n1;x;[]\n"}, "row width"))
        symbols = [{"symbol_id": value, "latex": f"native-{value}", "training_samples": "1",
                    "test_samples": "1"} for value in self.IDS]
        symbols[0]["training_samples"] = "2"
        cases.append((self.members(symbols=symbols), "count mismatch"))
        train = list(csv.DictReader(io.StringIO(self.members()["train-data.csv"].decode()),
                                    delimiter=";", quotechar="'"))
        train[0]["symbol_id"] = "999999"
        cases.append((self.members(train=train), "Unknown"))
        for mutated, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                self.audit(members=mutated)

    def test_geometry_issues_are_retained_without_fabricating_points_or_time(self):
        train = list(csv.DictReader(io.StringIO(self.members()["train-data.csv"].decode()),
                                    delimiter=";", quotechar="'"))
        payloads = [[], [[]], [[point(1, 2, include_time=False)]],
                    [[point(1, 2, 2), point(2, 3, 1)]],
                    [[{"x": "bad", "y": 2, "time": 1}]],
                    [[{"x": float("nan"), "y": 2, "time": float("inf")}]]]
        for row, payload in zip(train, payloads):
            row["data"] = json.dumps(payload)
        report = self.audit(members=self.members(train=train))
        rows = report["selectedRecords"][12:]
        self.assertEqual(rows[0]["issues"], ["emptyTrajectory"])
        self.assertEqual(rows[1]["issues"], ["emptyStroke"])
        self.assertIn("missingTime", rows[2]["issues"])
        self.assertIn("nonmonotonicTime", rows[3]["issues"])
        self.assertIn("nonnumericCoordinate", rows[4]["issues"])
        self.assertEqual(rows[4]["strokes"], payloads[4])
        self.assertIn("nonfiniteCoordinate", rows[5]["issues"])
        self.assertIn("nonfiniteTime", rows[5]["issues"])
        self.assertIsNone(rows[5]["strokes"])
        self.assertIn("rawData", rows[5])
        self.assertIsNone(rows[5]["coordinatePayloadSHA256"])
        self.assertEqual(report["receipt"]["selectedRecordCount"], 24)

    def test_raw_and_coordinate_duplicates_report_label_conflict_and_role_crossing(self):
        members = self.members()
        train = list(csv.DictReader(io.StringIO(members["train-data.csv"].decode()),
                                    delimiter=";", quotechar="'"))
        test = list(csv.DictReader(io.StringIO(members["test-data.csv"].decode()),
                                   delimiter=";", quotechar="'"))
        same_raw = json.dumps([[point(400, 500, 10), point(500, 500, 11)]])
        train[0]["data"] = same_raw
        test[1]["data"] = same_raw
        train[2]["data"] = json.dumps([[point(400, 500, 90), point(500, 500, 99)]])
        report = self.audit(members=self.members(train=train, test=test))
        raw = report["duplicateLedger"]["rawDataAllRecords"]
        coordinate = report["duplicateLedger"]["selectedCoordinatePayloadIgnoringTiming"]
        self.assertEqual((raw["duplicateGroupCount"], raw["trainTestCrossingGroupCount"],
                          raw["labelConflictGroupCount"]), (1, 1, 1))
        self.assertEqual((coordinate["duplicateGroupCount"],
                          coordinate["trainTestCrossingGroupCount"],
                          coordinate["labelConflictGroupCount"]), (1, 1, 1))
        self.assertEqual(coordinate["groups"][0]["count"], 3)
        self.assertEqual(coordinate["duplicateRecordCount"], 3)
        self.assertEqual(coordinate["excessDuplicateCount"], 2)
        self.assertEqual(coordinate["duplicateRecordRate"], 3 / 24)

    def test_nonselected_rows_are_counted_but_never_geometry_parsed(self):
        symbols = [{"symbol_id": value, "latex": f"native-{value}", "training_samples": "1",
                    "test_samples": "1"} for value in self.IDS]
        symbols.append({"symbol_id": "9999", "latex": "outside-selection",
                        "training_samples": "1", "test_samples": "1"})
        train = list(csv.DictReader(io.StringIO(self.members()["train-data.csv"].decode()),
                                    delimiter=";", quotechar="'"))
        test = list(csv.DictReader(io.StringIO(self.members()["test-data.csv"].decode()),
                                   delimiter=";", quotechar="'"))
        invalid = {"symbol_id": "9999", "user_id": "opaque-extra", "data": "not JSON",
                   "user_agent": "synthetic"}
        train.append(invalid)
        test.append(invalid)
        with patch.object(intake, "_trajectory", wraps=intake._trajectory) as decode:
            report = self.audit(members=self.members(symbols=symbols, train=train, test=test))
        self.assertEqual(decode.call_count, 24)
        self.assertEqual(report["receipt"]["recordCount"], 26)
        self.assertEqual(report["receipt"]["selectedRecordCount"], 24)
        self.assertNotIn("invalidJSON", report["receipt"]["selectedGeometryIssueCounts"])
        ledger = report["duplicateLedger"]
        self.assertEqual((ledger["allMetadataRecordCount"], ledger["selectedGeometryRecordCount"]),
                         (26, 24))
        self.assertEqual(ledger["selectedCoordinatePayloadIgnoringTiming"]["hashedRecordCount"], 24)
        self.assertEqual(ledger["rawDataAllRecords"]["hashedRecordCount"], 26)

    def test_real_entry_pins_size_and_both_hashes_before_opening_tar(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.archive(Path(directory))
            with patch.object(tarfile, "open", side_effect=AssertionError("must not open")), \
                    self.assertRaisesRegex(ValueError, "byte-size"):
                intake.audit_archive(path)
            data = path.read_bytes()
            with patch.object(intake, "ARCHIVE_BYTES", len(data)), \
                    patch.object(intake, "ARCHIVE_SHA256", hashlib.sha256(data).hexdigest()), \
                    patch.object(intake, "ARCHIVE_MD5", "0" * 32), \
                    patch.object(tarfile, "open", side_effect=AssertionError("must not open")), \
                    self.assertRaisesRegex(ValueError, "SHA-256/MD5"):
                intake.audit_archive(path)


if __name__ == "__main__":
    unittest.main()
