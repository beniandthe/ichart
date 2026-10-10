"""Synthetic BHMSDS intake contracts; no public raster corpus or model work."""
import hashlib
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import warnings
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

from PIL import Image

from ichart_recognition_ml.research import bhmsds_source_intake as intake

README = b"Symbols: `0,1,2,3,4,5,6,7,8,9,*,-,+,/,w,x,y,z`.\r\nFeel free to use this dataset, it's licensed under the MIT License.\r\n"
LICENSE = b"MIT License\nCopyright synthetic fixture\nPermission is hereby granted, free of charge.\n"


def png(index=0, *, mode="L", size=(28, 28), uniform=None, compression=6):
    image = Image.new(mode, size, 255 if mode == "L" else "white")
    if uniform is not None:
        image.paste(uniform, (0, 0, *size))
    else:
        image.putpixel((index % size[0], index // size[0] % size[1]), 0 if mode == "L" else (0, 0, 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG", compress_level=compression)
    return stream.getvalue()


class BHMSDSIntakeTests(unittest.TestCase):
    def fixture(self, root, *, edits=None, extras=()):
        prefix = f"bhmsds-{intake.COMMIT}/"
        members = {prefix + "README.md": README, prefix + "LICENSE": LICENSE}
        for label_index, label in enumerate(intake.LABELS):
            for index in range(2):
                members[prefix + f"symbols/{label}-{index:04d}.png"] = png(label_index * 2 + index)
        for name, data in (edits or {}).items():
            key = prefix + name
            if data is None:
                members.pop(key)
            else:
                members[key] = data
        path = root / "source.zip"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with ZipFile(path, "w", compression=ZIP_DEFLATED) as archive:
                for name, data in members.items():
                    archive.writestr(name, data)
                for name, data in extras:
                    archive.writestr(name, data)
        return path

    def audit(self, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            path = self.fixture(Path(directory), **kwargs)
            rows = []
            with patch.object(intake, "ARCHIVE_SHA256", hashlib.sha256(path.read_bytes()).hexdigest()), \
                 patch.object(intake, "PER_LABEL", 2):
                report = intake.audit_archive(path, foreground="black", row_sink=rows.append)
            return report, rows

    def test_canonical_leading_zero_ids_literal_labels_provenance_and_notice(self):
        report, rows = self.audit()
        self.assertEqual(report["sampleCount"], 36)
        self.assertEqual(report["sourceLabelCounts"], dict.fromkeys(intake.LABELS, 2))
        self.assertEqual(report["documents"]["README.md"]["text"].encode(), README)
        self.assertEqual(report["documents"]["LICENSE"]["sha256"], hashlib.sha256(LICENSE).hexdigest())
        self.assertEqual(report["sourceVocabularyIssue"], {"READMELists": "*", "filenamePrefix": "dot", "mapping": None})
        first = rows[0]
        self.assertTrue(first["pngMember"].endswith("symbols/0-0000.png"))
        self.assertEqual((first["sourceLabel"], first["sourceIndex"], first["width"], first["height"], first["mode"]), ("0", 0, 28, 28, "L"))
        self.assertEqual(first["rawPNGSHA256"], hashlib.sha256(png()).hexdigest())
        expected_pixels = bytearray([255] * 784)
        expected_pixels[0] = 0
        self.assertEqual(first["decodedPixelSHA256"], hashlib.sha256(b"L:28x28\0" + expected_pixels).hexdigest())
        for row in rows:
            self.assertIsNone(row["writerID"])
            self.assertIsNone(row["sessionID"])
            self.assertIsNone(row["canonicalCodepoint"])
            self.assertTrue(row["auxiliaryTrainingOnly"] and row["noObservedTrajectory"])
            self.assertFalse(row["newWriterEvidence"])

    def test_hash_and_commit_are_pinned_before_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.fixture(Path(directory))
            with self.assertRaisesRegex(ValueError, "SHA-256"), patch.object(intake, "_raster", side_effect=AssertionError("No decode")):
                intake.audit_archive(path, foreground="black")
        wrong = f"bhmsds-{'0' * 40}/README.md"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.audit(extras=[(wrong, README)])

    def test_unsafe_paths_symlinks_and_identity_collisions_are_rejected(self):
        prefix = f"bhmsds-{intake.COMMIT}/"
        for name in ("../escape", "/escape", prefix + "../escape", prefix + "symbols\\escape", prefix + "C:escape"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe"):
                self.audit(extras=[(name, b"bad")])
        link = ZipInfo(prefix + "symbols/link.png")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.audit(extras=[(link, b"target")])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.audit(extras=[(prefix + "symbols/0-0000.png", png())])
        for alias in ("symbols/0-0.png", "symbols/0-00000.png", "symbols/*-0000.png"):
            with self.subTest(alias=alias), self.assertRaisesRegex(ValueError, "label/index"):
                self.audit(edits={alias: png()})

    def test_exact_vocabulary_counts_indices_and_source_notices_are_required(self):
        for edits, message in (({"symbols/plus-0001.png": None}, "identities"),
                               ({"symbols/plus-0002.png": png()}, "label/index"),
                               ({"symbols/plus-0000.png": None, "symbols/sharp-0000.png": png()}, "label/index"),
                               ({"LICENSE": None}, "Missing"), ({"README.md": b"No dataset grant"}, "MIT")):
            with self.subTest(edits=list(edits)), self.assertRaisesRegex(ValueError, message):
                self.audit(edits=edits)

    def test_byte_and_member_budgets_abort_before_raster_decode(self):
        for constant in ("MAX_ARCHIVE_BYTES", "MAX_EXPANDED_BYTES"):
            with self.subTest(budget=constant), patch.object(intake, constant, 1), \
                 patch.object(intake, "_raster", side_effect=AssertionError("No decode")), self.assertRaisesRegex(ValueError, "budget"):
                self.audit()
        with self.assertRaisesRegex(ValueError, "member-byte"):
            self.audit(edits={"symbols/0-0000.png": b"x" * 65537})

    def test_empty_full_and_invalid_images_are_retained_with_explicit_counts(self):
        edits = {"symbols/0-0000.png": png(uniform=255), "symbols/0-0001.png": png(uniform=0),
                 "symbols/1-0000.png": b"not a PNG", "symbols/1-0001.png": png(mode="RGB"),
                 "symbols/2-0000.png": png(size=(29, 28))}
        report, rows = self.audit(edits=edits)
        self.assertEqual((len(rows), report["sampleCount"]), (36, 36))
        self.assertEqual(report["rasterStatusCounts"], {"empty-foreground": 1, "full-foreground": 1, "invalid-raster": 3, "usable": 31})
        self.assertEqual([r["foregroundPixelCount"] for r in rows[:2]], [0, 784])
        for row in rows[2:5]:
            self.assertFalse(row["usableRaster"])
            self.assertIsNone(row["decodedPixelSHA256"])
            self.assertIn("rasterError", row)
            self.assertEqual(len(row["rawPNGSHA256"]), 64)

    def test_raw_and_pixel_duplicate_groups_preserve_cross_label_rows(self):
        report, rows = self.audit(edits={"symbols/0-0000.png": png(100, compression=0),
                                        "symbols/plus-0000.png": png(100, compression=0),
                                        "symbols/slash-0000.png": png(100, compression=9)})
        self.assertEqual(len(rows), 36)
        self.assertEqual(len(report["rawPNGCopies"]), 1)
        self.assertEqual(len(report["rawPNGCopies"][0]["sampleIDs"]), 2)
        self.assertEqual(len(report["decodedPixelCopies"]), 1)
        group = report["decodedPixelCopies"][0]
        self.assertEqual((len(group["sampleIDs"]), group["sourceLabels"], group["conflictingSourceLabels"]), (3, ["0", "plus", "slash"], True))

    def test_cli_outputs_all_rows_preserves_documents_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = self.fixture(root)
            output = root / "receipt"
            args = ["--source-zip", str(path), "--output-dir", str(output), "--foreground", "black"]
            with patch.object(intake, "ARCHIVE_SHA256", hashlib.sha256(path.read_bytes()).hexdigest()), \
                 patch.object(intake, "PER_LABEL", 2), patch("builtins.print"), \
                 patch.object(ZipFile, "extractall", side_effect=AssertionError("No extraction")):
                intake.main(args)
                self.assertEqual((output / "README.md").read_bytes(), README)
                self.assertEqual((output / "LICENSE").read_bytes(), LICENSE)
                rows = [json.loads(line) for line in (output / "source_manifest.jsonl").read_text().splitlines()]
                self.assertEqual(len(rows), 36)
                self.assertEqual(json.loads((output / "source_receipt.json").read_text())["sampleCount"], 36)
                before = {p.name: p.read_bytes() for p in output.iterdir()}
                with self.assertRaises(FileExistsError):
                    intake.main(args)
                self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})


if __name__ == "__main__":
    unittest.main()
