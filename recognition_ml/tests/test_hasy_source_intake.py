"""Synthetic HASY archive contracts; no public raster corpus or ML execution."""
from contextlib import ExitStack
import csv
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

from ichart_recognition_ml.research import hasy_source_intake as intake


def png(index=0, *, mode="RGB", size=(32, 32), uniform=None, compression=6):
    image = Image.new(mode, size, "white" if mode == "RGB" else 255)
    if uniform is not None:
        image.paste(uniform, (0, 0, *size))
    else:
        image.putpixel((index % size[0], index // size[0] % size[1]), (0, 0, 0) if mode == "RGB" else 0)
    stream = io.BytesIO()
    image.save(stream, format="PNG", compress_level=compression)
    return stream.getvalue()


def csv_bytes(header, rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=header)
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode()


class HASYIntakeTests(unittest.TestCase):
    def fixture(self, root, *, edits=None, mutate=None, extras=()):
        labels = list(intake.TARGET_LABELS)
        records = [{"path": f"hasy-data/v2-{100 + 3 * i:05d}.png", "symbol_id": str(100 + i // 2),
                    "latex": labels[i // 2], "user_id": "16925" if i % 2 == 0 else "public-id"}
                   for i in range(24)]
        members = {row["path"]: png(i) for i, row in enumerate(records)}
        members["README.txt"] = b"HASYv2: 168236 images. Original archived notice.\r\n"
        members["hasy_tools.py"] = b"raise AssertionError('Archived helper must remain inert')\n"
        members["symbols.csv"] = csv_bytes(intake._CLASS_HEADER, [
            {"symbol_id": str(100 + i), "latex": label, "training_samples": "1", "test_samples": "1"}
            for i, label in enumerate(labels)])
        members["hasy-data-labels.csv"] = csv_bytes(intake._RECORD_HEADER, records)
        for fold_index, fold in enumerate(intake.FOLDS):
            for part in ("train", "test"):
                selected = [dict(row, path="../../" + row["path"]) for i, row in enumerate(records)
                            if (i % 10 == fold_index) == (part == "test")]
                members[f"{fold}/{part}.csv"] = csv_bytes(intake._RECORD_HEADER, selected)
        members["verification-task/train.csv"] = b"path,symbol_id,latex,user_id\n../hasy-data/v2-00100.png,100,+,16925\n"
        for version in range(1, 4):
            members[f"verification-task/test-v{version}.csv"] = b"path1,path2,is_same\n../hasy-data/v2-00100.png,../hasy-data/v2-00103.png,True\n"
        if mutate is not None:
            mutate(members)
        for name, data in (edits or {}).items():
            if data is None:
                members.pop(name)
            else:
                members[name] = data
        path = root / "source.tar.bz2"
        with tarfile.open(path, "w:bz2") as archive:
            for name in sorted(intake.DIRECTORIES):
                member = tarfile.TarInfo(name)
                member.type = tarfile.DIRTYPE
                archive.addfile(member)
            for name, data in sorted(members.items()):
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            for name, data, kind in extras:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.size = len(data)
                member.linkname = "hasy-data/v2-00100.png" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
                archive.addfile(member, io.BytesIO(data))
        return path, members

    def pins(self, path):
        stack = ExitStack()
        data = path.read_bytes()
        for key, value in {"ARCHIVE_SHA256": hashlib.sha256(data).hexdigest(),
                           "ARCHIVE_MD5": hashlib.md5(data).hexdigest(),
                           "EXPECTED_ROWS": 24, "EXPECTED_CLASSES": 12}.items():
            stack.enter_context(patch.object(intake, key, value))
        return stack

    def audit(self, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            path, members = self.fixture(Path(directory), **kwargs)
            rows = []
            with self.pins(path):
                report = intake.audit_archive(path, row_sink=rows.append)
            return report, rows, members

    def mutate_csv(self, name, action):
        def mutate(members):
            reader = csv.DictReader(io.StringIO(members[name].decode(), newline=""))
            rows = list(reader)
            action(rows)
            members[name] = csv_bytes(reader.fieldnames, rows)
        return mutate

    def test_native_labels_ids_rgb_pixels_and_provenance_are_preserved(self):
        report, rows, members = self.audit()
        self.assertEqual((len(rows), report["sampleCount"], report["classCount"]), (24, 24, 12))
        self.assertEqual((report["regularFileCount"], report["directoryCount"]), (52, 13))
        self.assertEqual(set(report["targetFamilies"]), set(intake.TARGET_LABELS))
        self.assertTrue(all(group[0]["sampleCount"] == 2 for group in report["targetFamilies"].values()))
        first = rows[0]
        self.assertEqual((first["sourceSymbolID"], first["sourceLabel"], first["sourceUserID"]), ("100", "+", "16925"))
        self.assertEqual((first["mode"], first["width"], first["height"], first["nativePixelBytes"]), ("RGB", 32, 32, 3072))
        frame = json.dumps({"mode": "RGB", "width": 32, "height": 32}, sort_keys=True, separators=(",", ":")).encode()
        pixels = bytearray([255] * 3072)
        pixels[:3] = b"\0\0\0"
        self.assertEqual(first["decodedPixelSHA256"], hashlib.sha256(frame + b"\0" + pixels).hexdigest())
        self.assertEqual(first["rawPNGSHA256"], hashlib.sha256(members[first["pngMember"]]).hexdigest())
        for row in rows:
            for key, value in intake.FLAGS.items():
                self.assertEqual(row[key], value)
        self.assertEqual(report["testAssignmentMultiplicity"], {"1": 24})
        self.assertTrue(all(fold["fullUnionCoverage"] and not fold["writerIndependent"] for fold in report["classificationFolds"]))
        self.assertFalse(report["shippingOrModelLicenseCleared"])

    def test_both_source_hashes_are_required_before_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.fixture(Path(directory))
            with self.assertRaisesRegex(ValueError, "SHA-256/MD5"), patch.object(intake, "_raster", side_effect=AssertionError("No decode")):
                intake.audit_archive(path)
            with self.pins(path), patch.object(intake, "ARCHIVE_MD5", "0" * 32), self.assertRaisesRegex(ValueError, "SHA-256/MD5"):
                intake.audit_archive(path)

    def test_unsafe_names_links_devices_and_duplicate_members_are_rejected(self):
        for name in ("../escape", "/escape", "hasy-data/../escape", "hasy-data\\escape", "C:escape", "hasy-data//escape"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe"):
                self.audit(extras=[(name, b"bad", tarfile.REGTYPE)])
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.FIFOTYPE):
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "Unsafe"):
                self.audit(extras=[("hasy-data/link", b"", kind)])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.audit(extras=[("hasy-data/v2-00100.png", png(), tarfile.REGTYPE)])

    def test_archive_member_expansion_and_individual_size_budgets_precede_decode(self):
        for key in ("MAX_ARCHIVE_BYTES", "MAX_MEMBERS", "MAX_EXPANDED_BYTES", "MAX_PNG_BYTES", "MAX_TEXT_BYTES"):
            with self.subTest(key=key), patch.object(intake, key, 1), \
                 patch.object(intake, "_raster", side_effect=AssertionError("No decode")), self.assertRaisesRegex(ValueError, "budget"):
                self.audit()

    def test_only_observed_directories_and_files_are_allowed(self):
        for name, kind in (("unobserved", tarfile.DIRTYPE), ("LICENSE", tarfile.REGTYPE), ("hasy-data/x.png", tarfile.REGTYPE)):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unexpected"):
                self.audit(extras=[(name, b"", kind)])
        with self.assertRaisesRegex(ValueError, "Missing/extra"):
            self.audit(edits={"verification-task/test-v3.csv": None})
        with self.assertRaisesRegex(ValueError, "PNG/file count"):
            self.audit(edits={"hasy-data/v2-00100.png": None})

    def test_csv_header_and_row_width_are_strict(self):
        for data in (b"path,symbol_id,latex,wrong\n", b"path,symbol_id,latex,user_id\np,100,+\n",
                     b"path,symbol_id,latex,user_id\np,100,+,x,extra\n"):
            with self.subTest(data=data), self.assertRaisesRegex(ValueError, "CSV"):
                self.audit(edits={"hasy-data-labels.csv": data})

    def test_native_class_identity_counts_and_join_are_strict(self):
        mutations = [("symbols.csv", lambda rows: rows.append(rows[0].copy()), "Duplicate native"),
                     ("symbols.csv", lambda rows: rows[0].update(training_samples="3"), "class count mismatch"),
                     ("symbols.csv", lambda rows: rows[0].update(test_samples="-1"), "Invalid native"),
                     ("symbols.csv", lambda rows: rows.pop(), "class count"),
                     ("hasy-data-labels.csv", lambda rows: rows[0].update(latex="unapproved"), "symbol ID/LaTeX"),
                     ("hasy-data-labels.csv", lambda rows: rows[0].update(symbol_id="999"), "symbol ID/LaTeX")]
        for name, action, message in mutations:
            with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                self.audit(mutate=self.mutate_csv(name, action))

    def test_main_path_grain_and_png_coverage_are_strict(self):
        for action in (lambda rows: rows.append(rows[0].copy()), lambda rows: rows[0].update(path="../hasy-data/v2-00100.png")):
            with self.assertRaisesRegex(ValueError, "grain|PNG/label"):
                self.audit(mutate=self.mutate_csv("hasy-data-labels.csv", action))
        with self.assertRaisesRegex(ValueError, "coverage"):
            self.audit(mutate=self.mutate_csv("hasy-data-labels.csv", lambda rows: rows.pop()))

    def test_all_ten_fold_metadata_joins_and_partition_grain_are_checked(self):
        for fold in intake.FOLDS:
            for action, message in ((lambda rows: rows[0].update(user_id="different"), "metadata join"),
                                    (lambda rows: rows[0].update(path="../hasy-data/v2-00100.png"), "path prefix"),
                                    (lambda rows: rows.append(rows[0].copy()), "Duplicate fold")):
                with self.subTest(fold=fold, message=message), self.assertRaisesRegex(ValueError, message):
                    self.audit(mutate=self.mutate_csv(f"{fold}/test.csv", action))

    def test_fold_overlap_union_and_cross_fold_test_multiplicity_are_checked(self):
        def add_test_to_train(members):
            test = list(csv.DictReader(io.StringIO(members[f"{intake.FOLDS[0]}/test.csv"].decode())))[0]
            rows = list(csv.DictReader(io.StringIO(members[f"{intake.FOLDS[0]}/train.csv"].decode())))
            members[f"{intake.FOLDS[0]}/train.csv"] = csv_bytes(intake._RECORD_HEADER, [*rows, test])
        with self.assertRaisesRegex(ValueError, "overlap"):
            self.audit(mutate=add_test_to_train)
        with self.assertRaisesRegex(ValueError, "coverage"):
            self.audit(mutate=self.mutate_csv(f"{intake.FOLDS[0]}/train.csv", lambda rows: rows.pop()))
        def repeat_test_assignment(members):
            for part in ("train", "test"):
                members[f"{intake.FOLDS[1]}/{part}.csv"] = members[f"{intake.FOLDS[0]}/{part}.csv"]
        with self.assertRaisesRegex(ValueError, "multiplicity"):
            self.audit(mutate=repeat_test_assignment)

    def test_invalid_uniform_and_different_native_modes_are_retained(self):
        report, rows, _ = self.audit(edits={"hasy-data/v2-00100.png": b"not PNG", "hasy-data/v2-00103.png": png(uniform="white"),
                                           "hasy-data/v2-00106.png": png(uniform=(255, 0, 0)), "hasy-data/v2-00109.png": png(mode="L"),
                                           "hasy-data/v2-00112.png": png(size=(33, 32))})
        self.assertEqual(len(rows), 24)
        self.assertEqual(report["rasterStatusCounts"], {"invalid-raster": 2, "uniform-raster": 2, "usable": 20})
        by_path = {row["pngMember"]: row for row in rows}
        self.assertEqual(by_path["hasy-data/v2-00109.png"]["mode"], "L")
        self.assertTrue(by_path["hasy-data/v2-00106.png"]["isUniformRaster"])
        self.assertIsNone(by_path["hasy-data/v2-00100.png"]["decodedPixelSHA256"])
        self.assertIn("rasterError", by_path["hasy-data/v2-00100.png"])

    def test_raw_pixel_conflicting_duplicates_and_fold_crossings_are_reported(self):
        edits = {"hasy-data/v2-00100.png": png(99, compression=0), "hasy-data/v2-00106.png": png(99, compression=0),
                 "hasy-data/v2-00112.png": png(99, compression=9)}
        report, rows, _ = self.audit(edits=edits)
        self.assertEqual(len(rows), 24)
        self.assertEqual(len(report["rawPNGCopies"]), 1)
        self.assertEqual(len(report["rawPNGCopies"][0]["pngMembers"]), 2)
        group = report["decodedPixelCopies"][0]
        self.assertEqual((len(group["pngMembers"]), group["conflictingSourceLabels"]), (3, True))
        crossings = report["classificationFolds"][0]["crossingNativePixelDuplicateGroups"]
        self.assertEqual(crossings[0]["testPNGs"], ["hasy-data/v2-00100.png"])
        self.assertEqual(len(crossings[0]["trainPNGs"]), 2)
        self.assertEqual(sum(fold["crossingNativePixelDuplicateGroupCount"] for fold in report["classificationFolds"]), 3)

    def test_verification_metadata_is_preserved_inert_and_hashed_only(self):
        documents = {}
        with tempfile.TemporaryDirectory() as directory:
            path, members = self.fixture(Path(directory), edits={"verification-task/test-v1.csv": b"inert arbitrary evidence bytes"})
            with self.pins(path), patch.object(tarfile.TarFile, "extractall", side_effect=AssertionError("No extraction")):
                report = intake.audit_archive(path, document_sink=lambda name, data: documents.update({name: data}))
        self.assertEqual(report["verificationTaskAudited"], "preserved-and-hashed-only")
        for name in intake.TEXT_FILES:
            self.assertEqual(documents[name], members[name])
            self.assertEqual(report["documents"][name]["sha256"], hashlib.sha256(members[name]).hexdigest())

    def test_source_recheck_prevents_publishing_changed_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self.fixture(Path(directory))
            with self.pins(path):
                identity = intake._source_identity(path)
                with patch.object(intake, "_source_identity", side_effect=[identity, {**identity, "bytes": 0}]), self.assertRaisesRegex(ValueError, "Source changed"):
                    intake.audit_archive(path)

    def test_cli_binds_artifacts_documents_code_tests_contract_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, members = self.fixture(root)
            output = root / "receipt"
            args = ["--source-tar", str(path), "--output-dir", str(output)]
            with self.pins(path), patch("builtins.print"), patch.object(tarfile.TarFile, "extractall", side_effect=AssertionError("No extraction")):
                intake.main(args)
                receipt = json.loads((output / "source_receipt.json").read_text())
                self.assertEqual(receipt["sampleCount"], 24)
                self.assertEqual(len(receipt["inputBindings"]), 3)
                for name, expected in receipt["artifacts"].items():
                    data = (output / name).read_bytes()
                    self.assertEqual((len(data), hashlib.sha256(data).hexdigest()), (expected["bytes"], expected["sha256"]))
                self.assertEqual((output / "source_metadata/README.txt").read_bytes(), members["README.txt"])
                self.assertEqual((output / "source_metadata/hasy_tools.py").read_bytes(), members["hasy_tools.py"])
                rows = [json.loads(line) for line in (output / "source_manifest.jsonl").read_text().splitlines()]
                self.assertEqual(len(rows), 24)
                before = (output / "source_receipt.json").read_bytes()
                with self.assertRaises(FileExistsError):
                    intake.main(args)
                self.assertEqual((output / "source_receipt.json").read_bytes(), before)

    def test_output_inside_git_is_rejected_before_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, _ = self.fixture(root)
            (root / ".git").write_text("gitdir: synthetic")
            with self.pins(path), patch.object(intake, "_raster", side_effect=AssertionError("No decode")), self.assertRaisesRegex(ValueError, "outside Git"):
                intake.main(["--source-tar", str(path), "--output-dir", str(root / "forbidden")])
            self.assertFalse((root / "forbidden").exists())


if __name__ == "__main__":
    unittest.main()
