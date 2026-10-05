from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ichart_recognition_ml.research import personal_support_match_defer_source as source
from ichart_recognition_ml.research import uji_personal


def synthetic_plan(*, source_sha256="0" * 64):
    return source.SourceRolePlan(
        source_sha256=source_sha256,
        parent_receipt_sha256="1" * 64,
        training_writers=("trn_UJI_W00",),
        development_writers=("trn_UJI_W01",),
        reserved_writers=("tst_UJI_W00",),
        vocabulary=("A", "B"),
    )


def blocks():
    result = []
    writers = (("trn_UJI_W00", 100), ("trn_UJI_W01", 9_000), ("tst_UJI_W00", 8_000))
    for writer, base in writers:
        for session in (1, 2):
            for offset, label in enumerate(("A", "B")):
                value = base + session * 10 + offset
                result.append([
                    f"WORD {label} {writer}-0{session}",
                    "NUMSTROKES 1",
                    f"POINTS 2 # {value} {value + 1} {value + 2} {value + 3}",
                ])
    return result


def text_from_blocks(value):
    return "\n".join(line for block in value for line in block) + "\n"


def official_receipt():
    training_domain = tuple(f"trn_UJI_W{index:02}" for index in range(40))
    ranked = sorted(
        training_domain,
        key=lambda writer: source.hashlib.sha256(("personal-encoder-v1:" + writer).encode()).hexdigest(),
    )
    vocabulary = tuple(chr(0x100 + index) for index in range(97))
    return {
        "sourceSHA256": source.SOURCE_SHA256,
        "trainingWriters": sorted(ranked[8:]),
        "developmentWriters": sorted(ranked[:8]),
        "reservedWriters": [f"tst_UJI_W{index:02}" for index in range(20)],
        "vocabulary": list(vocabulary),
    }


class SupportMatchDeferSourceTests(unittest.TestCase):
    def test_excluded_coordinates_never_construct_ink_and_allowed_geometry_matches_original(self):
        text = text_from_blocks(blocks())
        expected = tuple(sorted(
            (sample for sample in uji_personal.parse_source(text) if sample.writer == "trn_UJI_W00"),
            key=lambda sample: sample.identity,
        ))
        with (
            patch.object(source, "_construct_point", wraps=source._construct_point) as points,
            patch.object(source, "_construct_stroke", wraps=source._construct_stroke) as strokes,
            patch.object(source, "_construct_sample", wraps=source._construct_sample) as samples,
        ):
            actual = source.parse_training_source(text, synthetic_plan())
        self.assertEqual(actual, expected)
        self.assertEqual([sample.identity for sample in actual], sorted(sample.identity for sample in actual))
        self.assertEqual(points.call_count, 8)
        self.assertEqual(strokes.call_count, 4)
        self.assertEqual(samples.call_count, 4)
        self.assertTrue(all(abs(int(call.args[0])) < 1_000 for call in points.call_args_list))
        self.assertTrue(all(sample.writer == "trn_UJI_W00" for sample in actual))

    def test_excluded_metadata_malformed_duplicate_missing_and_truncated_fail(self):
        original = blocks()
        excluded = next(index for index, block in enumerate(original) if "trn_UJI_W01" in block[0])
        cases = {}
        value = [list(block) for block in original]; value[excluded][0] = value[excluded][0].replace("WORD", "BROKEN")
        cases["header"] = value
        value = [list(block) for block in original]; value[excluded][1] = "NUMSTROKES 0"
        cases["count"] = value
        value = [list(block) for block in original]; value[excluded][2] = value[excluded][2].replace("POINTS 2", "POINTS 3")
        cases["point-count"] = value
        value = [list(block) for block in original]
        tokens = value[excluded][2].split(); tokens[3] = "not-a-coordinate"; value[excluded][2] = " ".join(tokens)
        cases["coordinate-syntax"] = value
        value = [list(block) for block in original]; value.append(list(value[excluded]))
        cases["duplicate"] = value
        value = [list(block) for block in original]; value.pop(excluded)
        cases["missing-grid-row"] = value
        value = [list(block) for block in original]; value[-1].pop()
        cases["truncated"] = value
        for name, value in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    source.parse_training_source(text_from_blocks(value), synthetic_plan())

    def test_plan_overlap_unknown_writer_and_vocabulary_fail(self):
        text = text_from_blocks(blocks())
        malformed = (
            replace(synthetic_plan(), development_writers=("trn_UJI_W00",)),
            replace(synthetic_plan(), development_writers=("trn_UJI_W02",)),
            replace(synthetic_plan(), vocabulary=("A", "C")),
        )
        for plan in malformed:
            with self.subTest(plan=plan):
                with self.assertRaises(ValueError):
                    source.parse_training_source(text, plan)

    def test_bound_regular_file_digest_and_symlink_guards(self):
        data = text_from_blocks(blocks()).encode()
        digest = source.hashlib.sha256(data).hexdigest()
        plan = synthetic_plan(source_sha256=digest)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            path = root / "uji.txt"; path.write_bytes(data)
            self.assertEqual(source._load_bound_training_source(path, plan), source.parse_training_source(data.decode(), plan))
            with self.assertRaisesRegex(ValueError, "digest"):
                source._load_bound_training_source(path, replace(plan, source_sha256="f" * 64))
            link = root / "link.txt"; link.symlink_to(path)
            with self.assertRaisesRegex(ValueError, "regular"):
                source._load_bound_training_source(link, plan)
            empty = root / "empty.txt"; empty.write_bytes(b"")
            with self.assertRaisesRegex(ValueError, "regular"):
                source._read_bounded_regular(empty)

    def test_official_receipt_binds_exact_deterministic_32_8_20_roles_and_97_labels(self):
        receipt = official_receipt()
        digest = source.hashlib.sha256(source._canonical_json(receipt)).hexdigest()
        plan = source.role_plan_from_receipt(receipt, receipt_sha256=digest)
        self.assertEqual(len(plan.training_writers), 32)
        self.assertEqual(len(plan.development_writers), 8)
        self.assertEqual(len(plan.reserved_writers), 20)
        self.assertEqual(len(plan.vocabulary), 97)
        self.assertEqual(plan.source_sha256, source.SOURCE_SHA256)

        mutations = []
        value = {key: list(item) if isinstance(item, list) else item for key, item in receipt.items()}
        value["trainingWriters"][0], value["developmentWriters"][0] = value["developmentWriters"][0], value["trainingWriters"][0]
        value["trainingWriters"].sort(); value["developmentWriters"].sort(); mutations.append(value)
        value = {key: list(item) if isinstance(item, list) else item for key, item in receipt.items()}; value["vocabulary"].pop(); mutations.append(value)
        value = {**receipt, "sourceSHA256": "f" * 64}; mutations.append(value)
        for value in mutations:
            value_digest = source.hashlib.sha256(source._canonical_json(value)).hexdigest()
            with self.assertRaises(ValueError):
                source.role_plan_from_receipt(value, receipt_sha256=value_digest)
        with self.assertRaisesRegex(ValueError, "digest"):
            source.role_plan_from_receipt(receipt, receipt_sha256="0" * 64)

    def test_official_loader_refuses_small_synthetic_roles_before_file_access(self):
        receipt = {
            "sourceSHA256": source.SOURCE_SHA256,
            "trainingWriters": ["trn_UJI_W00"],
            "developmentWriters": ["trn_UJI_W01"],
            "reservedWriters": ["tst_UJI_W00"],
            "vocabulary": ["A", "B"],
        }
        digest = source.hashlib.sha256(source._canonical_json(receipt)).hexdigest()
        with patch.object(source, "_read_bounded_regular", side_effect=AssertionError("file must not open")):
            with self.assertRaisesRegex(ValueError, "Protocol-pinned"):
                source.load_official_training_source(Path("/not/opened"), receipt, receipt_sha256=digest)

    def test_official_loader_rejects_self_consistent_alternate_parent_before_file_access(self):
        receipt = {**official_receipt(), "metadataSHA256": source.PARENT_METADATA_SHA256}
        alternate_digest = source.hashlib.sha256(source._canonical_json(receipt)).hexdigest()
        self.assertNotEqual(alternate_digest, source.PARENT_RECEIPT_SHA256)
        with patch.object(source, "_read_bounded_regular", side_effect=AssertionError("file must not open")):
            with self.assertRaisesRegex(ValueError, "Protocol-pinned"):
                source.load_official_training_source(
                    Path("/not/opened"),
                    receipt,
                    receipt_sha256=alternate_digest,
                )
            wrong_metadata = {**receipt, "metadataSHA256": "f" * 64}
            with self.assertRaisesRegex(ValueError, "Protocol-pinned"):
                source.load_official_training_source(
                    Path("/not/opened"),
                    wrong_metadata,
                    receipt_sha256=source.PARENT_RECEIPT_SHA256,
                )


if __name__ == "__main__":
    unittest.main()
