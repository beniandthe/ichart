"""Synthetic train-only selection and raster adapter tests; no actual NIST reads."""
from collections import Counter
from dataclasses import asdict
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

from PIL import Image

from ichart_recognition_ml.research import nist_sd19 as source
from ichart_recognition_ml.research import nist_sd19_training_source as adapter


def sample(writer, label, *, index=None, role="train", template="14", bad_image=False):
    index = adapter.LABELS.index(label) if index is None else index
    partition = "hsf_4" if role == "reserved" else "hsf_0"
    form, field = f"f{writer}_{template}", f"c{writer}_{template}"
    key = f"{partition}/{form}/{field}"
    image = Image.new("RGB", (128, 128), "white")
    image.paste((0, 0, 0), (10, 20, 30, 26))
    image.putpixel((40 + index % 64, 60 + int(writer) % 40), (0, 0, 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG")
    data = b"held-out image must not be decoded" if bad_image else stream.getvalue()
    decoded = b"\xff" * (128 * 128) if bad_image else source.decode_png(data, foreground="black")
    row = asdict(source.RasterSample(f"{key}/{index:05d}", writer, partition, template, form, field,
        index, role, label, f"{ord(label):02x}", f"{ord(label):02x}", f"by_write/{key}/{field}_{index:05d}.png",
        hashlib.sha256(data).hexdigest(), f"legacy/data/by_write/{key}.cls", "c" * 64,
        index + 2, hashlib.sha256(decoded).hexdigest()))
    return row, data


def samples(writer="0001", **kwargs):
    return [sample(writer, label, **kwargs) for label in adapter.LABELS]


class NISTTrainingSourceTests(unittest.TestCase):
    def fixture(self, root, values):
        root.mkdir()
        manifest, receipt, archive = root / "clean.jsonl", root / "quarantine.json", root / "images.zip"
        rows = [value[0] for value in values]
        manifest.write_bytes(b"".join((json.dumps(row) + "\n").encode() for row in rows))
        with ZipFile(archive, "w") as zipped:
            for row, data in values:
                zipped.writestr(row["png_member"], data)
        archive_hash = source.sha256_file(archive)
        counts = {"sampleCount": len(rows), "roleCounts": dict(Counter(r["split"] for r in rows)),
                  "classCountsByByteHex": dict(Counter(r["label_byte_hex"] for r in rows))}
        receipt.write_text(json.dumps({"cleanManifestSHA256": source.sha256_file(manifest), "clean": counts,
            "policy": "remove-all-members-of-every-repeated-raw-png-or-decoded-raster-hash",
            "sourceReceipt": {"sourceID": source.SOURCE_ID, "rightsStatus": source.RIGHTS_STATUS,
                "trainingEligibilityEstablished": False, "inputKind": "raster-only", "observedTrajectories": False,
                "sourceArchiveSHA256": {"pngZIP": archive_hash, "clsZIP": "a" * 64},
                "importerSourceSHA256": source.sha256_file(Path(source.__file__)),
                "runtime": {"python": "3.12.14", "pillow": "11.3.0"}}}) + "\n")
        pins = {"expected_manifest_sha256": source.sha256_file(manifest),
                "expected_receipt_sha256": source.sha256_file(receipt), "expected_archive_sha256": archive_hash}
        return manifest, receipt, archive, pins, counts

    def select(self, manifest, pins, counts, **kwargs):
        return adapter.select_training_rows(manifest, expected_sha256=pins["expected_manifest_sha256"],
            expected_counts=counts, salt="fixed", **kwargs)

    def test_selection_precedes_decoding_and_reads_only_train_members(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, receipt, archive, pins, _ = self.fixture(root / "input", samples() + samples("0002", role="reserved", bad_image=True))
            original_read = ZipFile.read
            def training_read(zipped, member, *args, **kwargs):
                self.assertNotIn("hsf_4", member)
                return original_read(zipped, member, *args, **kwargs)
            with patch.object(ZipFile, "read", training_read), patch.object(source, "decode_png", wraps=source.decode_png) as decode:
                report = adapter.prepare_training_source(manifest, receipt, archive, root / "output", salt="fixed", writers_per_label=1, **pins)
            self.assertEqual(decode.call_count, 62)
            self.assertEqual(report["selectedRoleCounts"], {"train": 62})
            self.assertEqual(report["selectedClassCounts"], {label: 1 for label in adapter.LABELS})

    def test_lowest_sample_per_writer_label_and_lowest_writer_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            values = samples() + samples("0003") + [sample("0001", "A", index=200)]
            manifest, _, _, pins, counts = self.fixture(root / "input", values)
            selected, available = self.select(manifest, pins, counts, writers_per_label=2)
            self.assertEqual(len(selected), 124)
            self.assertEqual(available["availableTrainingWriterCountsByLabel"]["A"], 2)
            choices = [v[0] for v in values if v[0]["writer_id"] == "0001" and v[0]["label"] == "A"]
            expected = min(choices, key=lambda r: hashlib.sha256(f"nist-sd19-writer-label-salted-sha256-v1\0fixed\0sample\0{r['sample_id']}".encode()).hexdigest())
            actual = next(r for r in selected if r["writer_id"] == "0001" and r["label"] == "A")
            self.assertEqual(actual["sample_id"], expected["sample_id"])
            one, _ = self.select(manifest, pins, counts, writers_per_label=1)
            for actual in one:
                writer = min(("0001", "0003"), key=lambda w: hashlib.sha256(f"nist-sd19-writer-label-salted-sha256-v1\0fixed\0writer-label\0{w}\0{actual['label']}".encode()).hexdigest())
                self.assertEqual(actual["writer_id"], writer)

    def test_selection_is_input_order_independent_and_grouped(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            values = samples() + samples("0003")
            first = self.fixture(root / "first", values)
            second = self.fixture(root / "second", list(reversed(values)))
            a, _ = self.select(first[0], first[3], first[4], writers_per_label=1)
            b, _ = self.select(second[0], second[3], second[4], writers_per_label=1)
            self.assertEqual(a, b)
            self.assertEqual([r["label"] for r in a], list(adapter.LABELS))

    def test_missing_classes_or_insufficient_distinct_writers_fail(self):
        for values, budget in ((samples()[:-1], 1), (samples(), 2)):
            with self.subTest(budget=budget), tempfile.TemporaryDirectory() as directory:
                data = self.fixture(Path(directory) / "input", values)
                with self.assertRaisesRegex(ValueError, "Insufficient distinct training writers"):
                    self.select(data[0], data[3], data[4], writers_per_label=budget)

    def test_writer_role_and_reserved_partition_violations_fail_before_decode(self):
        for changes in ([("split", "dev")], [("split", "train"), ("partition", "hsf_4")]):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as directory:
                values = samples()
                modified, image = sample("0001", "A", index=200)
                for key, value in changes:
                    modified[key] = value
                values.append((modified, image))
                data = self.fixture(Path(directory) / "input", values)
                with patch.object(source, "decode_png", side_effect=AssertionError("No decoding")), self.assertRaises(ValueError):
                    self.select(data[0], data[3], data[4], writers_per_label=1)

    def test_manifest_hash_count_and_duplicate_ids_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            data = self.fixture(Path(directory) / "input", samples())
            data[0].write_bytes(b" " + data[0].read_bytes())
            with self.assertRaisesRegex(ValueError, "manifest SHA256"):
                self.select(data[0], data[3], data[4], writers_per_label=1)
        with tempfile.TemporaryDirectory() as directory:
            data = self.fixture(Path(directory) / "input", samples())
            data[4]["sampleCount"] += 1
            with self.assertRaisesRegex(ValueError, "count/role/class"):
                self.select(data[0], data[3], data[4], writers_per_label=1)
        with tempfile.TemporaryDirectory() as directory:
            values = samples()
            data = self.fixture(Path(directory) / "input", values + [values[0]])
            with self.assertRaisesRegex(ValueError, "Duplicate source sample"):
                self.select(data[0], data[3], data[4], writers_per_label=1)

    def test_labels_are_exact_ascii62_without_aliases_or_controls(self):
        for key, value in (("label", "ø"), ("label", "\x00"), ("label_raw_token", "61"), ("label_byte_hex", "61")):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                values = samples()
                values[0][0][key] = value
                data = self.fixture(Path(directory) / "input", values)
                with self.assertRaisesRegex(ValueError, "62 ASCII"):
                    self.select(data[0], data[3], data[4], writers_per_label=1)

    def test_nearest_transform_keeps_binary_foreground_aspect_fit_and_padding(self):
        pixels = bytearray(128 * 128)
        for y in range(30, 40):
            pixels[y * 128 + 20:y * 128 + 60] = b"\xff" * 40
        adapted = adapter.adapt_raster(bytes(pixels))
        image = Image.frombytes("L", (256, 96), adapted)
        self.assertEqual(image.getbbox(), (8, 18, 248, 78))
        self.assertEqual(set(adapted), {0, 255})
        self.assertEqual(len(adapted), 256 * 96)
        with self.assertRaisesRegex(ValueError, "no sample is silently dropped"):
            adapter.adapt_raster(b"\x00" * (128 * 128))
        with self.assertRaisesRegex(ValueError, "binary 128x128"):
            adapter.adapt_raster(b"\x01" * (128 * 128))

    def test_output_binds_pixel_offsets_source_hashes_protocol_and_unresolved_rights(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = self.fixture(root / "input", samples())
            report = adapter.prepare_training_source(*data[:3], root / "output", salt="fixed", writers_per_label=1, **data[3])
            records = [json.loads(line) for line in (root / "output" / "selection.jsonl").read_text().splitlines()]
            pixels = (root / "output" / "rasters.bin").read_bytes()
            self.assertEqual(len(pixels), 62 * 256 * 96)
            for index, record in enumerate(records):
                start = index * 256 * 96
                self.assertEqual((record["rasterByteOffset"], record["rasterByteLength"]), (start, 256 * 96))
                self.assertEqual(record["adaptedRasterSHA256"], hashlib.sha256(pixels[start:start + 256 * 96]).hexdigest())
                self.assertEqual(record["sourceRow"]["split"], "train")
            self.assertEqual(report["selectionJSONLSHA256"], source.sha256_file(root / "output" / "selection.jsonl"))
            self.assertEqual(report["rastersBinSHA256"], source.sha256_file(root / "output" / "rasters.bin"))
            self.assertEqual(report["protocolSHA256"], adapter.PROTOCOL_SHA256)
            self.assertEqual(report["transform"]["contentLimit"], [240, 80])
            self.assertFalse(report["productionEligible"])
            self.assertFalse(report["trainingEligibilityEstablished"])
            self.assertTrue(report["researchPurposeSupported"])
            self.assertFalse(report["transform"]["observedTrajectories"])

    def test_tampered_receipt_archive_or_selected_hash_fails(self):
        for kind in ("receipt", "archive", "decoded"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                values = samples()
                if kind == "decoded":
                    values[0][0]["decoded_raster_sha256"] = "0" * 64
                data = self.fixture(root / "input", values)
                if kind == "receipt":
                    data[1].write_bytes(data[1].read_bytes() + b" ")
                elif kind == "archive":
                    data[2].write_bytes(data[2].read_bytes() + b" ")
                with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                    adapter.prepare_training_source(*data[:3], root / "output", salt="fixed", writers_per_label=1, **data[3])
                self.assertFalse((root / "output" / "receipt.json").exists())

    def test_existing_output_is_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = self.fixture(root / "input", samples())
            output = root / "output"
            output.mkdir()
            with patch.object(source, "sha256_file", side_effect=AssertionError("Must reject first")), self.assertRaises(FileExistsError):
                adapter.prepare_training_source(*data[:3], output, salt="fixed", writers_per_label=1, **data[3])
            self.assertEqual(list(output.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
