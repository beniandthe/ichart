"""Synthetic frozen-manifest tests; no actual NIST images, fitting, or decoding."""
import base64
from collections import Counter, defaultdict
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ichart_recognition_ml.research import nist_sd19 as source
from ichart_recognition_ml.research import nist_sd19_quarantine as quarantine


def row(number, *, raw=None, pixels=None, label="A", role="train", writer=None, template="14"):
    writer = writer or f"{number:04d}"
    partition = "hsf_4" if role == "reserved" else "hsf_0"
    form, field = f"f{writer}_{template}", f"d{writer}_{template}"
    key = f"{partition}/{form}/{field}"
    return asdict(source.RasterSample(f"{key}/00000", writer, partition, template, form, field, 0,
        role, label, f"{ord(label):02x}", f"{ord(label):02x}", f"by_write/{key}/{field}_00000.png",
        raw or f"{number:064x}", f"legacy/data/by_write/{key}.cls", "c" * 64, 2,
        pixels or f"{number + 100:064x}"))


class NISTQuarantineTests(unittest.TestCase):
    def fixture(self, root, rows, *, transform_summary=None, lines=None):
        root.mkdir()
        samples, summary_path = root / "samples.jsonl", root / "summary.json"
        lines = lines or [("  " + json.dumps(value, ensure_ascii=False) + " \n").encode("utf-8") for value in rows]
        samples.write_bytes(b"".join(lines))
        writers, fields = {}, {}
        field_counts = Counter(value["sample_id"].rsplit("/", 1)[0] for value in rows)
        for value in rows:
            identity = value["writer_id"]
            writer = writers.setdefault(identity, {"writerID": identity, "split": value["split"], "partitions": [], "forms": []})
            writer["partitions"] = sorted(set(writer["partitions"]) | {value["partition"]})
            writer["forms"] = sorted(set(writer["forms"]) | {f"{value['partition']}/{value['form_id']}"})
            key = value["sample_id"].rsplit("/", 1)[0]
            fields[key] = {"fieldKey": key, "count": field_counts[key], "clsMember": value["cls_member"], "clsSHA256": value["cls_sha256"]}
        summary = {"sourceID": source.SOURCE_ID, "sourceArchiveSHA256": {"pngZIP": "a" * 64, "clsZIP": "b" * 64},
            "importerSourceSHA256": source.sha256_file(Path(source.__file__)), "runtime": {"python": "3.12.14", "pillow": "11.3.0"},
            "rightsStatus": source.RIGHTS_STATUS, "trainingEligibilityEstablished": False,
            "inputKind": "raster-only", "observedTrajectories": False, "sampleCount": len(rows),
            "writerCount": len(writers), "fieldCount": len(fields), "writers": list(writers.values()), "fields": list(fields.values()),
            "sampleCountsBySplit": dict(Counter(value["split"] for value in rows)),
            "labelsByByteHex": dict(Counter(value["label_byte_hex"] for value in rows)),
            "rasterVerification": {"verifiedCount": len(rows), "binary": True, "dimensions": [128, 128]},
            "samplesJSONLSHA256": source.sha256_file(samples)}
        if transform_summary:
            transform_summary(summary)
        summary_path.write_text(json.dumps(summary, sort_keys=True) + "\n")
        return summary_path, samples, source.sha256_file(summary_path), lines

    def run_quarantine(self, root, rows, **kwargs):
        summary, samples, expected, lines = self.fixture(root / "input", rows, **kwargs)
        output = root / "output"
        receipt = quarantine.quarantine_source(summary, samples, output, expected_summary_sha256=expected)
        return receipt, output, lines

    def test_all_repeated_members_removed_instead_of_arbitrary_representative(self):
        rows = [row(i, raw="d" * 64, pixels="e" * 64) for i in (1, 2, 3)] + [row(4)]
        with tempfile.TemporaryDirectory() as directory:
            receipt, output, lines = self.run_quarantine(Path(directory), rows)
            self.assertEqual([receipt[key]["sampleCount"] for key in ("original", "clean", "quarantined")], [4, 1, 3])
            self.assertEqual((output / "clean-source-integrity-manifest.jsonl").read_bytes(), lines[3])
            removed = [json.loads(line) for line in (output / "quarantined.jsonl").read_bytes().splitlines()]
            self.assertEqual([base64.b64decode(value["sourceLineBase64"]) for value in removed], lines[:3])
            self.assertEqual([value["sourceRow"] for value in removed], rows[:3])
            self.assertFalse(receipt["trainingEligibilityEstablished"])
            self.assertFalse(receipt["fitOrInferencePerformed"])
            self.assertEqual(receipt["sourceReceipt"]["rightsStatus"], source.RIGHTS_STATUS)

    def test_different_png_encoding_unions_reasons_and_reports_conflicts_cross_roles(self):
        rows = [row(1, raw="a" * 64, pixels="f" * 64), row(2, raw="b" * 64, pixels="f" * 64, label="B", role="reserved"),
                row(3, raw="b" * 64, pixels="f" * 64, label="B")]
        with tempfile.TemporaryDirectory() as directory:
            receipt, output, _ = self.run_quarantine(Path(directory), rows)
            removed = [json.loads(line) for line in (output / "quarantined.jsonl").read_text().splitlines()]
            self.assertEqual(removed[0]["reasons"], ["repeated-decoded-raster-hash"])
            self.assertEqual(removed[1]["reasons"], ["repeated-decoded-raster-hash", "repeated-raw-png-hash"])
            groups = {value["hashKind"]: value for value in receipt["copyGroups"]}
            self.assertEqual(groups["decoded-raster"]["memberCount"], 3)
            self.assertTrue(groups["decoded-raster"]["conflictingLabels"])
            self.assertTrue(groups["decoded-raster"]["crossSplit"])
            self.assertFalse(groups["raw-png"]["conflictingLabels"])
            self.assertTrue(groups["raw-png"]["crossSplit"])
            self.assertEqual(receipt["quarantined"]["classCountsByByteHex"], {"41": 1, "42": 2})
            self.assertEqual(receipt["quarantined"]["roleCounts"], {"train": 2, "reserved": 1})

    def test_no_copies_preserves_every_source_byte_and_never_decodes_images(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary, samples, expected, lines = self.fixture(root / "input", [row(1), row(2, label="a")])
            before = {path.name: path.read_bytes() for path in (root / "input").iterdir()}
            with patch.object(source, "decode_png", side_effect=AssertionError("Must not decode")):
                receipt = quarantine.quarantine_source(summary, samples, root / "output", expected_summary_sha256=expected)
            self.assertEqual((root / "output" / "clean-source-integrity-manifest.jsonl").read_bytes(), b"".join(lines))
            self.assertEqual((root / "output" / "quarantined.jsonl").read_bytes(), b"")
            self.assertEqual(receipt["cleanManifestSHA256"], hashlib.sha256(b"".join(lines)).hexdigest())
            self.assertEqual(before, {path.name: path.read_bytes() for path in (root / "input").iterdir()})

    def test_summary_tamper_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary, samples, expected, _ = self.fixture(root / "input", [row(1)])
            summary.write_bytes(summary.read_bytes() + b" ")
            with self.assertRaisesRegex(ValueError, "summary SHA256"):
                quarantine.quarantine_source(summary, samples, root / "output", expected_summary_sha256=expected)
            self.assertFalse((root / "output").exists())

    def test_stream_tamper_rejected_before_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary, samples, expected, _ = self.fixture(root / "input", [row(1)])
            samples.write_bytes(b" " + samples.read_bytes())
            with self.assertRaisesRegex(ValueError, "stream SHA256"):
                quarantine.quarantine_source(summary, samples, root / "output", expected_summary_sha256=expected)
            self.assertFalse((root / "output").exists())

    def test_missing_or_invalid_decoded_hash_rejected(self):
        for value in (None, "", "0" * 63, "G" * 64):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                changed = row(1)
                changed["decoded_raster_sha256"] = value
                with self.assertRaisesRegex(ValueError, "decoded raster SHA256"):
                    self.run_quarantine(Path(directory), [changed])

    def test_duplicate_sample_id_rejected(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "Duplicate source sample"):
            self.run_quarantine(Path(directory), [row(1), row(1)])

    def test_declared_sample_class_role_or_field_counts_must_match(self):
        changes = [lambda s: (s.update(sampleCount=2), s["rasterVerification"].update(verifiedCount=2)),
                   lambda s: s.update(labelsByByteHex={"42": 1}), lambda s: s.update(sampleCountsBySplit={"dev": 1}),
                   lambda s: s["fields"][0].update(count=2)]
        for change in changes:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "count mismatch"):
                self.run_quarantine(Path(directory), [row(1)], transform_summary=change)

    def test_same_writer_cannot_cross_roles_and_form_receipt_is_required(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "writer role/form"):
            self.run_quarantine(Path(directory), [row(1), row(2, writer="0001", template="15", role="dev")])
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "writer role/form"):
            self.run_quarantine(Path(directory), [row(1)], transform_summary=lambda s: s["writers"][0].update(forms=[]))

    def test_identity_and_exact_label_bytes_cannot_be_aliased(self):
        for key, value in (("sample_id", "different"), ("label", "a"), ("label_raw_token", "61"), ("cls_label_line", 3)):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                changed = row(1)
                changed[key] = value
                with self.assertRaises(ValueError):
                    self.run_quarantine(Path(directory), [changed])

    def test_unverified_source_or_different_rights_importer_runtime_is_rejected(self):
        changes = [lambda s: s.update(rightsStatus="eligible"), lambda s: s.update(importerSourceSHA256="0" * 64),
                   lambda s: s["runtime"].update(pillow=None), lambda s: s["rasterVerification"].update(binary=False)]
        for change in changes:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
                self.run_quarantine(Path(directory), [row(1)], transform_summary=change)

    def test_existing_output_is_rejected_and_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary, samples, expected, _ = self.fixture(root / "input", [row(1)])
            output = root / "output"
            quarantine.quarantine_source(summary, samples, output, expected_summary_sha256=expected)
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            with patch.object(quarantine, "_load_summary", side_effect=AssertionError("Must reject first")), self.assertRaises(FileExistsError):
                quarantine.quarantine_source(summary, samples, output, expected_summary_sha256=expected)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})

    def test_group_descriptions_are_order_stable_and_source_row_order_is_preserved(self):
        rows = [row(3, raw="d" * 64, pixels="e" * 64), row(1, raw="d" * 64, pixels="e" * 64), row(2)]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "first").mkdir()
            (root / "second").mkdir()
            first, output, lines = self.run_quarantine(root / "first", rows)
            second, _, _ = self.run_quarantine(root / "second", list(reversed(rows)))
            self.assertEqual(first["copyGroups"], second["copyGroups"])
            self.assertEqual(first["quarantinedSampleIDs"], second["quarantinedSampleIDs"])
            self.assertEqual((output / "clean-source-integrity-manifest.jsonl").read_bytes(), lines[2])

    def test_receipt_binds_inputs_outputs_and_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            summary, samples, expected, _ = self.fixture(root / "input", [row(1)])
            output = root / "output"
            with patch("builtins.print"):
                quarantine.main(["--source-summary", str(summary), "--source-samples", str(samples),
                                 "--summary-sha256", expected, "--output", str(output)])
            receipt = json.loads((output / "receipt.json").read_text())
            self.assertEqual(receipt["sourceSummarySHA256"], expected)
            self.assertEqual(receipt["sourceSamplesJSONLSHA256"], source.sha256_file(samples))
            self.assertEqual(receipt["quarantineSourceSHA256"], source.sha256_file(Path(quarantine.__file__)))
            self.assertEqual(receipt["quarantinedJSONLSHA256"], source.sha256_file(output / "quarantined.jsonl"))


if __name__ == "__main__":
    unittest.main()
