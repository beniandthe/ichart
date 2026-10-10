"""Synthetic source-contract tests only; no downloads, fitting, or app inputs."""
from dataclasses import replace
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import warnings
from zipfile import ZipFile

from PIL import Image

from ichart_recognition_ml.research import nist_sd19 as nist


def png(*, mode="RGB", size=(128, 128), gray=False, color=False, compression=6):
    image = Image.new(mode, size, "white" if mode == "RGB" else 255)
    image.putpixel((30, 30), (255, 0, 0) if color else ((127, 127, 127) if gray else (0, 0, 0)) if mode == "RGB" else (127 if gray else 0))
    stream = io.BytesIO()
    image.save(stream, format="PNG", compress_level=compression)
    return stream.getvalue()


def paths(writer="0001", template="14", partition="hsf_0", kind="d", index=0):
    base = f"by_write/{partition}/f{writer}_{template}/{kind}{writer}_{template}"
    return f"{base}/{kind}{writer}_{template}_{index:05d}.png", f"legacy/data/{base}.cls"


class NISTSourceAuditTests(unittest.TestCase):
    def archives(self, root, images, classes):
        source, labels = root / "images.zip", root / "classes.zip"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with ZipFile(source, "w") as archive:
                for name, data in images:
                    archive.writestr(name, data)
            with ZipFile(labels, "w") as archive:
                for name, data in classes:
                    archive.writestr(name, data)
        return source, labels

    def audit(self, images, classes, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            source, labels = self.archives(Path(directory), images, classes)
            rows = []
            report = nist.audit_zips(source, labels, row_sink=rows.append, **kwargs)
            return report, rows

    def test_exact_writer_form_field_index_and_wrappers(self):
        member, cls = paths(index=12)
        field, index = nist.parse_png_path("wrapper/" + member)
        self.assertEqual((field.writer_id, field.template_id, field.kind, index), ("0001", "14", "d", 12))
        self.assertEqual((field.form_id, field.field_id, field.key), ("f0001_14", "d0001_14", "hsf_0/f0001_14/d0001_14"))
        self.assertEqual(nist.parse_cls(b"1\n30\n", cls).field, field)

    def test_path_mismatches_and_invalid_indices_are_rejected(self):
        member, _ = paths()
        for altered in (member.replace("d0001_14/", "d0002_14/"), member.replace("d0001_14_", "u0001_14_"),
                        member.replace("_00000.png", "_0000.png"), member.replace("hsf_0", "hsf_9"),
                        member.replace(".png", ".PNG"), "/" + member, "../" + member, "by_write/" + member):
            with self.subTest(member=altered), self.assertRaises(ValueError):
                nist.parse_png_path(altered)

    def test_cls_preserves_checked_raw_hex_case_and_control_status_bytes(self):
        _, cls = paths()
        parsed = nist.parse_cls(b"4\n4A\n6a\n00\n7f\n", cls)
        self.assertEqual(parsed.raw_tokens, ("4A", "6a", "00", "7f"))
        self.assertEqual(parsed.values, (74, 106, 0, 127))
        self.assertEqual(parsed.sha256, hashlib.sha256(b"4\n4A\n6a\n00\n7f\n").hexdigest())

    def test_cls_header_count_and_lf_are_strict(self):
        _, cls = paths()
        for data in (b"01\n30\n", b" 1\n30\n", b"-1\n30\n", b"1\r\n30\r\n", b"1\n30", b"2\n30\n", b"0\n30\n", b"100001\n"):
            with self.subTest(data=data), self.assertRaisesRegex(ValueError, "CLS"):
                nist.parse_cls(data, cls)
        self.assertEqual(nist.parse_cls(b"0\n", cls).values, ())

    def test_invalid_label_bytes_and_field_paths_are_rejected(self):
        _, cls = paths()
        for token in (b"80", b"ff", b"g0", b"0", b"030", b"30 ", b""):
            with self.subTest(token=token), self.assertRaisesRegex(ValueError, "label"):
                nist.parse_cls(b"1\n" + token + b"\n", cls)
        with self.assertRaisesRegex(ValueError, "identity"):
            nist.parse_cls(b"1\n30\n", cls.replace("d0001_14.cls", "d0002_14.cls"))

    def test_raster_validation_requires_explicit_polarity_without_resize(self):
        data = png()
        black = nist.decode_png(data, foreground="black")
        white = nist.decode_png(data, foreground="white")
        self.assertEqual(len(black), 128 * 128)
        self.assertEqual((black[30 * 128 + 30], black[0], white[30 * 128 + 30], white[0]), (255, 0, 0, 255))
        for altered in (png(size=(32, 32)), png(gray=True), png(color=True), png(mode="RGBA")):
            with self.subTest(data=altered[:30]), self.assertRaises(ValueError):
                nist.decode_png(altered, foreground="black")
        with self.assertRaisesRegex(ValueError, "polarity"):
            nist.decode_png(data, foreground="automatic")
        with self.assertRaises(TypeError):
            nist.decode_png(data)

    def test_join_preserves_exact_label_and_source_provenance(self):
        member, cls = paths()
        data = png()
        report, rows = self.audit([(member, data)], [(cls, b"1\n41\n")], verify_rasters=True, development_fraction=0)
        row = rows[0]
        self.assertEqual((row.label, row.label_raw_token, row.label_byte_hex, row.cls_label_line), ("A", "41", "41", 2))
        self.assertEqual(row.png_sha256, hashlib.sha256(data).hexdigest())
        self.assertEqual(row.cls_sha256, hashlib.sha256(b"1\n41\n").hexdigest())
        self.assertEqual(row.decoded_raster_sha256, hashlib.sha256(nist.decode_png(data, foreground="black")).hexdigest())
        self.assertEqual((row.png_member, row.cls_member), (member, cls))
        self.assertEqual((report["sampleCount"], report["rasterVerification"]["verifiedCount"]), (1, 1))
        self.assertEqual(report["importerSourceSHA256"], nist.sha256_file(Path(nist.__file__)))
        self.assertEqual(report["runtime"]["pillow"], Image.__version__)
        self.assertFalse(report["trainingEligibilityEstablished"])
        self.assertFalse(report["observedTrajectories"])
        self.assertEqual(report["rightsStatus"], nist.RIGHTS_STATUS)

    def test_missing_cls_is_rejected(self):
        member, _ = paths()
        with self.assertRaisesRegex(ValueError, "Missing CLS"):
            self.audit([(member, png())], [])

    def test_uniform_rasters_are_reported_and_preserved(self):
        images, classes = [], []
        for index, color in enumerate((0, 255)):
            image = Image.new("L", (128, 128), color)
            data = io.BytesIO()
            image.save(data, format="PNG")
            images.append((paths(index=index)[0], data.getvalue()))
        classes.append((paths()[1], b"2\n30\n31\n"))
        report, rows = self.audit(images, classes, verify_rasters=True)
        self.assertEqual(len(rows), 2)
        self.assertEqual(report["rasterVerification"]["uniformRasterCount"], 2)
        self.assertEqual(report["rasterVerification"]["uniformRasters"],
            [{"sampleID": rows[0].sample_id, "foregroundPixelValue": 255},
             {"sampleID": rows[1].sample_id, "foregroundPixelValue": 0}])

    def test_noncontiguous_missing_or_extra_indices_are_rejected(self):
        member, cls = paths(index=1)
        for images, data in (([(member, png())], b"1\n30\n"), ([], b"1\n30\n"),
                             ([(paths(index=i)[0], png()) for i in (0, 2)], b"2\n30\n31\n")):
            with self.subTest(indices=[name for name, _ in images]), self.assertRaisesRegex(ValueError, "indices"):
                self.audit(images, [(cls, data)])

    def test_zero_count_fields_and_status_rows_are_retained(self):
        member, cls = paths()
        empty_cls = paths(kind="u")[1]
        report, rows = self.audit([(member, png())], [(cls, b"1\n00\n"), (empty_cls, b"0\n")])
        self.assertEqual((report["fieldCount"], report["sampleCount"], rows[0].label), (2, 1, "\x00"))
        self.assertEqual(report["preservedASCIIControlOrStatusLabels"], {"00": 1})

    def test_duplicate_zip_members_and_png_identity_aliases_are_rejected(self):
        member, cls = paths()
        for alias in (member, "alternate/" + member):
            with self.subTest(alias=alias), self.assertRaisesRegex(ValueError, "Duplicate"):
                self.audit([(member, png()), (alias, png(gray=True))], [(cls, b"1\n30\n")])

    def test_conflicting_cls_identity_aliases_are_rejected(self):
        member, cls = paths()
        with self.assertRaisesRegex(ValueError, "Duplicate CLS"):
            self.audit([(member, png())], [(cls, b"1\n30\n"), ("alternate/" + cls, b"1\n31\n")])

    def test_unsafe_unrelated_member_is_rejected_without_extraction(self):
        member, cls = paths()
        with patch.object(ZipFile, "extract", side_effect=AssertionError("No extraction")), \
             patch.object(ZipFile, "extractall", side_effect=AssertionError("No extraction")), \
             self.assertRaisesRegex(ValueError, "Unsafe"):
            self.audit([(member, png()), ("../outside", b"bad")], [(cls, b"1\n30\n")])

    def test_archive_audit_is_read_only_and_metadata_mode_does_not_decode(self):
        member, cls = paths()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, labels = self.archives(root, [(member, png())], [(cls, b"1\n30\n")])
            before = {p.name: p.read_bytes() for p in root.iterdir()}
            with patch.object(nist, "decode_png", side_effect=AssertionError("No raster decode")), \
                 patch.object(ZipFile, "extractall", side_effect=AssertionError("No extraction")):
                report = nist.audit_zips(source, labels)
            self.assertEqual(before, {p.name: p.read_bytes() for p in root.iterdir()})
            self.assertEqual(report["rasterVerification"]["verifiedCount"], 0)
            self.assertIsNone(report["decodedRasterCopies"])

    def test_all_templates_and_partitions_for_writer_share_reserved_split(self):
        images, classes = [], []
        for template, partition in (("14", "hsf_0"), ("33", "hsf_4"), ("47", "hsf_7")):
            member, cls = paths(template=template, partition=partition)
            images.append((member, png()))
            classes.append((cls, b"1\n30\n"))
        report, rows = self.audit(images, classes)
        self.assertEqual((report["writerCount"], report["formCount"]), (1, 3))
        self.assertEqual({row.split for row in rows}, {"reserved"})
        nist.assert_grouped_splits(rows)
        with self.assertRaisesRegex(ValueError, "crosses splits"):
            nist.assert_grouped_splits([rows[0], replace(rows[1], split="train")])

    def test_grouped_assignment_is_deterministic_and_hsf5_hsf8_are_ineligible(self):
        groups = {"0001": ["hsf_0"], "0002": ["hsf_4"], "0003": ["hsf_5"], "0004": ["hsf_8"]}
        result = nist.grouped_splits(groups, seed="fixed", development_fraction=1)
        self.assertEqual(result, {"0001": "dev", "0002": "reserved", "0003": "withheld", "0004": "unprocessed"})
        self.assertEqual(result, nist.grouped_splits(dict(reversed(list(groups.items()))), seed="fixed", development_fraction=1))
        for groups, seed, fraction in (({"1": ["hsf_0"]}, "x", .1), ({"0001": ["hsf_9"]}, "x", .1),
                                       ({"0001": []}, "x", .1), ({"0001": ["hsf_0"]}, "", .1),
                                       ({"0001": ["hsf_0"]}, "x", float("nan"))):
            with self.assertRaises(ValueError):
                nist.grouped_splits(groups, seed=seed, development_fraction=fraction)

    def test_raw_file_and_decoded_pixel_copies_have_separate_cross_split_receipts(self):
        images, classes = [], []
        for writer, partition, label, compression in (("0001", "hsf_0", b"30", 0),
                                                     ("0002", "hsf_4", b"31", 0),
                                                     ("0003", "hsf_7", b"30", 9)):
            member, cls = paths(writer=writer, partition=partition)
            images.append((member, png(compression=compression)))
            classes.append((cls, b"1\n" + label + b"\n"))
        report, rows = self.audit(images, classes, verify_rasters=True, development_fraction=0)
        self.assertEqual(len(rows), 3)
        self.assertEqual(report["rawPNGCopies"], {"duplicateGroups": 1, "extraDuplicateRows": 1,
            "crossSplitGroups": 1, "crossSplitRows": 2, "conflictingLabelGroups": 1, "conflictingLabelRows": 2})
        self.assertEqual(report["decodedRasterCopies"], {"duplicateGroups": 1, "extraDuplicateRows": 2,
            "crossSplitGroups": 1, "crossSplitRows": 3, "conflictingLabelGroups": 1, "conflictingLabelRows": 3})

    def test_cli_streams_exclusive_receipts_and_never_overwrites(self):
        member, cls = paths()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, labels = self.archives(root, [(member, png())], [(cls, b"1\n30\n")])
            output = root / "audit"
            args = ["--png-zip", str(source), "--cls-zip", str(labels), "--output", str(output), "--foreground", "black", "--verify-rasters"]
            with patch("builtins.print"):
                nist.main(args)
            report = json.loads((output / "summary.json").read_text())
            row = json.loads((output / "samples.jsonl").read_text())
            self.assertEqual(row["label"], "0")
            self.assertEqual(report["samplesJSONLSHA256"], nist.sha256_file(output / "samples.jsonl"))
            before = (output / "summary.json").read_bytes()
            with self.assertRaises(FileExistsError):
                nist.main(args)
            self.assertEqual((output / "summary.json").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
