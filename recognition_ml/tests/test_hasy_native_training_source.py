"""Synthetic fixed native-shape preparation contracts; no public-data preparation."""
from collections import Counter
from contextlib import ExitStack
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

from ichart_recognition_ml.research import hasy_native_training_source as source
from ichart_recognition_ml.research import hasy_source_intake as intake
from ichart_recognition_ml.research import personal_symbol_data

POINTS = (((8, 8), (9, 8), (9, 9)), ((8, 8), (9, 8), (9, 10)),
          ((8, 8), (10, 8), (9, 9)), ((8, 8), (11, 8), (9, 9)),
          ((8, 8), (10, 8), (8, 10)), ((8, 8), (10, 8), (9, 10)))


def png(points):
    image = Image.new("RGB", (32, 32), "white")
    for point in points:
        image.putpixel(point, (0, 0, 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


class NativeSourceTests(unittest.TestCase):
    def fixture(self, root, *, points=None, additions=()):
        native_ids, labels = ("31", "152", "1394"), ("B", r"\Delta", r"\o")
        rows, payloads = [], {}
        specifications = [(native_ids[i // 2], labels[i // 2], f"source-{i:03d}", (points or POINTS)[i]) for i in range(6)]
        specifications.extend(additions)
        for index, (native_id, label, sample_id, shape) in enumerate(specifications):
            path = f"hasy-data/v2-{index * 7:05d}.png"
            data = png(shape)
            payloads[path] = data
            rows.append({"sampleID": sample_id, "pngMember": path, "sourceSymbolID": native_id,
                         "sourceLabel": label, "sourceUserID": "16925", "rawPNGSHA256": hashlib.sha256(data).hexdigest(),
                         "usableRaster": True, **intake._raster(data), **intake.FLAGS})
        archive = root / "source.tar.bz2"
        with tarfile.open(archive, "w:bz2") as stream:
            for name in sorted(intake.DIRECTORIES):
                member = tarfile.TarInfo(name)
                member.type = tarfile.DIRTYPE
                stream.addfile(member)
            for name, data in sorted(payloads.items() | {name: b"inert source evidence" for name in intake.TEXT_FILES}.items()):
                member = tarfile.TarInfo(name)
                member.size = len(data)
                stream.addfile(member, io.BytesIO(data))
        intake_dir = root / "intake"
        intake_dir.mkdir()
        artifacts = {}
        classes = [{"sourceSymbolID": native_id, "sourceLabel": label,
                    "sampleCount": sum(row["sourceSymbolID"] == native_id for row in rows)} for native_id, label in zip(native_ids, labels)]
        for name, data in {"source_manifest.jsonl": b"".join(source._canonical(row) + b"\n" for row in rows),
                           "source_classes.json": source._canonical(classes), "pixel_duplicates.json": b"[]\n"}.items():
            (intake_dir / name).write_bytes(data)
            artifacts[name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
        receipt = {"archive": {"sha256": source._hash(archive)}, "classCount": 3, "artifacts": artifacts}
        (intake_dir / "source_receipt.json").write_bytes(source._canonical(receipt))
        protocol = root / "protocol.md"
        protocol.write_bytes(b"Synthetic fixed source-only protocol")
        return archive, intake_dir, protocol, rows, payloads

    def pins(self, archive, intake_dir, protocol, rows):
        stack = ExitStack()
        for key, value in {"ARCHIVE_SHA256": source._hash(archive), "INTAKE_SHA256": source._hash(intake_dir / "source_receipt.json"),
                           "MANIFEST_SHA256": source._hash(intake_dir / "source_manifest.jsonl"),
                           "PROTOCOL_SHA256": source._hash(protocol), "CLASS_COUNT": 3, "BASE_EXPOSURES": 2, "EXTRA_CLASSES": 1}.items():
            stack.enter_context(patch.object(source, key, value))
        stack.enter_context(patch.object(intake, "EXPECTED_ROWS", len(rows)))
        return stack

    def prepared(self, root, **kwargs):
        archive, intake_dir, protocol, rows, payloads = self.fixture(root, **kwargs)
        output = root / "prepared"
        with self.pins(archive, intake_dir, protocol, rows):
            receipt = source.prepare(archive, intake_dir, protocol, output)
        return output, receipt, (archive, intake_dir, protocol, rows, payloads)

    def ledger(self, output, name="source_ledger.jsonl"):
        return [json.loads(line) for line in (output / name).read_text().splitlines()]

    def test_exact_normalizer_all_clean_sources_native_labels_and_inert_tar(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(personal_symbol_data, "map_label", side_effect=AssertionError("No aliases")), \
                 patch.object(tarfile.TarFile, "extractall", side_effect=AssertionError("No extraction")), \
                 patch.object(source, "normalize_bitmap", wraps=personal_symbol_data.normalize_bitmap) as normalize:
                output, receipt, (_, _, _, rows, payloads) = self.prepared(root)
            self.assertEqual(normalize.call_count, 12)  # All six clean rows plus six selected distinct rows.
            self.assertEqual(receipt["nativeClassIDs"], ["31", "152", "1394"])
            self.assertIsNone(receipt["labelMapping"])
            self.assertEqual(receipt["declaredDatasetLicense"], "ODbL")
            self.assertIs(receipt["shippingOrModelLicenseCleared"], False)
            self.assertIs(receipt["derivedWeightDistributionCleared"], False)
            ledger = self.ledger(output)
            self.assertEqual({row["sourceLabel"] for row in ledger}, {"B", r"\Delta", r"\o"})
            for row in ledger:
                with Image.open(io.BytesIO(payloads[row["pngMember"]])) as image:
                    expected = personal_symbol_data.normalize_bitmap(image)
                self.assertEqual(row["adaptedRasterSHA256"], hashlib.sha256(expected).hexdigest())
                self.assertIsNone(row["canonicalCodepoint"])
            self.assertEqual(receipt["sourceCounts"]["originalRows"], len(rows))

    def test_all_native_conflict_members_are_excluded(self):
        points = list(POINTS)
        points[2] = points[0]
        with tempfile.TemporaryDirectory() as directory:
            output, receipt, _ = self.prepared(Path(directory), points=points)
            ledger = {row["sampleID"]: row for row in self.ledger(output)}
            for identity in ("source-000", "source-002"):
                self.assertIn("native-conflicting-pixels", ledger[identity]["exclusions"])
                self.assertIsNone(ledger[identity]["adaptedRasterSHA256"])
            self.assertEqual(receipt["sourceCounts"]["nativeCleanRows"], 4)

    def test_same_native_label_copy_uses_lexically_smallest_sample_id(self):
        addition = ("31", "B", "aaa-copy", POINTS[0])
        with tempfile.TemporaryDirectory() as directory:
            output, _, _ = self.prepared(Path(directory), additions=[addition])
            ledger = {row["sampleID"]: row for row in self.ledger(output)}
            self.assertEqual(ledger["source-000"]["exclusions"], ["native-same-label-copy"])
            self.assertEqual(ledger["source-000"]["representativeSampleID"], "aaa-copy")
            self.assertFalse(ledger["aaa-copy"]["exclusions"])

    def test_all_adapted_cross_native_label_collisions_precede_selection(self):
        points = list(POINTS)
        points[2] = tuple((x + 8, y + 8) for x, y in points[0])
        with tempfile.TemporaryDirectory() as directory:
            output, receipt, _ = self.prepared(Path(directory), points=points)
            ledger = {row["sampleID"]: row for row in self.ledger(output)}
            for identity in ("source-000", "source-002"):
                self.assertEqual(ledger[identity]["exclusions"], ["adapted-conflicting-pixels"])
                self.assertIsNotNone(ledger[identity]["adaptedRasterSHA256"])
            selected = {row["sampleID"] for row in self.ledger(output, "selection.jsonl")}
            self.assertFalse(selected & {"source-000", "source-002"})
            self.assertEqual(receipt["sourceCounts"]["nativeCleanRows"], 6)
            self.assertEqual(receipt["sourceCounts"]["adaptedCleanRows"], 4)

    def test_same_label_adapted_copy_is_collapsed_lexically(self):
        addition = ("31", "B", "aaa-adapted-copy", tuple((x + 8, y + 8) for x, y in POINTS[0]))
        with tempfile.TemporaryDirectory() as directory:
            output, _, _ = self.prepared(Path(directory), additions=[addition])
            ledger = {row["sampleID"]: row for row in self.ledger(output)}
            self.assertEqual(ledger["source-000"]["exclusions"], ["adapted-same-label-copy"])
            self.assertEqual(ledger["source-000"]["representativeSampleID"], "aaa-adapted-copy")
            self.assertFalse(ledger["aaa-adapted-copy"]["exclusions"])

    def test_empty_native_class_stops_without_reducing_vocabulary(self):
        points = list(POINTS)
        points[2], points[3] = points[0], points[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, intake_dir, protocol, rows, _ = self.fixture(root, points=points)
            with self.pins(archive, intake_dir, protocol, rows), self.assertRaisesRegex(ValueError, "Native class empty"):
                source.prepare(archive, intake_dir, protocol, root / "prepared")
            self.assertFalse((root / "prepared").exists())

    def test_salted_balancing_rank_cycles_and_distinct_repeat_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            output, receipt, fixture = self.prepared(Path(directory))
            selection = self.ledger(output, "selection.jsonl")
            ledger = self.ledger(output)
            extra = min(receipt["nativeClassIDs"], key=lambda value: hashlib.sha256(b"native-shape-transfer-v1\0" + value.encode()).hexdigest())
            self.assertEqual(receipt["extraNativeClassIDs"], [extra])
            self.assertEqual(Counter(row["sourceSymbolID"] for row in selection), {value: 2 + int(value == extra) for value in receipt["nativeClassIDs"]})
            for native_id in receipt["nativeClassIDs"]:
                available = sorted([row["sampleID"] for row in ledger if row["sourceSymbolID"] == native_id],
                                   key=lambda value: hashlib.sha256(b"native-shape-transfer-v1\0" + value.encode()).hexdigest())
                selected = [row for row in selection if row["sourceSymbolID"] == native_id]
                self.assertEqual([row["sampleID"] for row in selected], [available[i % 2] for i in range(len(selected))])
                self.assertEqual([row["cycleIndex"] for row in selected], [i // 2 for i in range(len(selected))])
            self.assertEqual((receipt["exposureCount"], receipt["distinctSourceCount"], receipt["repeatedExposureCount"]), (7, 6, 1))

    def test_loader_returns_readonly_memmaps_targets_and_selected_hash_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            output, receipt, fixture = self.prepared(Path(directory))
            archive, intake_dir, protocol, rows, _ = fixture
            pin = source._hash(output / "source_receipt.json")
            with self.pins(archive, intake_dir, protocol, rows):
                images, targets, evidence = source.load_prepared(output, pin)
                self.assertIsInstance(images, np.memmap)
                self.assertIsInstance(targets, np.memmap)
                self.assertEqual(images.shape, (7, 1, 96, 256))
                self.assertEqual(targets.shape, (7,))
                self.assertFalse(images.flags.writeable or targets.flags.writeable)
                self.assertEqual(evidence["receipt"], receipt)
                self.assertEqual(evidence["receiptSHA256"], pin)
                hashes = sorted({row["adaptedRasterSHA256"] for row in self.ledger(output, "selection.jsonl")})
                self.assertEqual(evidence["selectedAdaptedRasterHashes"], hashes)
                self.assertEqual(evidence["selectedAdaptedRasterHashesSHA256"], hashlib.sha256(source._canonical(hashes)).hexdigest())
                with self.assertRaises(ValueError):
                    images[0, 0, 0, 0] = 0

    def test_all_input_pins_and_intake_artifacts_fail_closed(self):
        for field in ("ARCHIVE_SHA256", "INTAKE_SHA256", "MANIFEST_SHA256", "PROTOCOL_SHA256"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive, intake_dir, protocol, rows, _ = self.fixture(root)
                with self.pins(archive, intake_dir, protocol, rows), patch.object(source, field, "0" * 64), self.assertRaises(ValueError):
                    source.prepare(archive, intake_dir, protocol, root / "prepared")
                self.assertFalse((root / "prepared").exists())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, intake_dir, protocol, rows, _ = self.fixture(root)
            with self.pins(archive, intake_dir, protocol, rows):
                (intake_dir / "pixel_duplicates.json").write_bytes(b"modified")
                with self.assertRaisesRegex(ValueError, "Changed evidence artifact"):
                    source.prepare(archive, intake_dir, protocol, root / "prepared")

    def test_native_join_and_binary_normalization_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, intake_dir, protocol, rows, _ = self.fixture(root)
            rows[0]["decodedPixelSHA256"] = "0" * 64
            data = b"".join(source._canonical(row) + b"\n" for row in rows)
            (intake_dir / "source_manifest.jsonl").write_bytes(data)
            receipt = json.loads((intake_dir / "source_receipt.json").read_text())
            receipt["artifacts"]["source_manifest.jsonl"] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
            (intake_dir / "source_receipt.json").write_bytes(source._canonical(receipt))
            with self.pins(archive, intake_dir, protocol, rows), self.assertRaisesRegex(ValueError, "native raster/intake join"):
                source.prepare(archive, intake_dir, protocol, root / "prepared")
            self.assertFalse((root / "prepared").exists())
        image = Image.new("RGB", (32, 32), "white")
        image.putpixel((8, 8), (128, 128, 128))
        with self.assertRaisesRegex(ValueError, "binary"):
            personal_symbol_data.normalize_bitmap(image)

    def test_loader_rejects_receipt_artifact_schema_and_code_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            output, receipt, fixture = self.prepared(Path(directory))
            archive, intake_dir, protocol, rows, _ = fixture
            pin = source._hash(output / "source_receipt.json")
            with self.pins(archive, intake_dir, protocol, rows):
                with self.assertRaisesRegex(ValueError, "receipt SHA256"):
                    source.load_prepared(output, "0" * 64)
                with patch.object(source, "code_identity", return_value={}), self.assertRaisesRegex(ValueError, "code"):
                    source.load_prepared(output, pin)
                raster = output / "rasters.bin"
                original = raster.read_bytes()
                raster.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "Changed evidence artifact"):
                    source.load_prepared(output, pin)
                raster.write_bytes(original)
                receipt["labelMapping"] = {r"\Delta": "triangle"}
                (output / "source_receipt.json").write_bytes(source._canonical(receipt))
                with self.assertRaisesRegex(ValueError, "schema"):
                    source.load_prepared(output, source._hash(output / "source_receipt.json"))

    def test_changed_inputs_during_preparation_do_not_publish_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, intake_dir, protocol, rows, _ = self.fixture(root)
            def normalize(image):
                protocol.write_bytes(b"changed during preparation")
                return personal_symbol_data.normalize_bitmap(image)
            with self.pins(archive, intake_dir, protocol, rows), patch.object(source, "normalize_bitmap", side_effect=normalize), \
                 self.assertRaisesRegex(ValueError, "Changed fixed protocol"):
                source.prepare(archive, intake_dir, protocol, root / "prepared")
            self.assertFalse((root / "prepared/source_receipt.json").exists())

    def test_fresh_output_is_required_and_git_output_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, _, fixture = self.prepared(root)
            archive, intake_dir, protocol, rows, _ = fixture
            before = source._hash(output / "source_receipt.json")
            with self.pins(archive, intake_dir, protocol, rows), self.assertRaises(FileExistsError):
                source.prepare(archive, intake_dir, protocol, output)
            self.assertEqual(source._hash(output / "source_receipt.json"), before)
            (root / ".git").write_text("gitdir: synthetic")
            with self.pins(archive, intake_dir, protocol, rows), self.assertRaisesRegex(ValueError, "outside Git"):
                source.prepare(archive, intake_dir, protocol, root / "forbidden")


if __name__ == "__main__":
    unittest.main()
