import copy
import hashlib
import json
import math
import struct
import tempfile
import unittest
import uuid
from pathlib import Path

from ichart_recognition_ml.contracts import (
    CorpusRecord,
    load_records_jsonl,
    validate_dataset,
    validate_feature_artifacts,
)
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.manifest import build_manifest, validate_manifest
from ichart_recognition_ml.schema import FEATURE_SCHEMA, SPLITS
from corpus_v2_fixture import record_mapping


def identifier(index: int) -> str:
    return str(uuid.UUID(int=index))


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


class CorpusFixture:
    def __init__(self, root: Path):
        self.root = root
        self.trajectory = struct.pack(
            f"<{FEATURE_SCHEMA.trajectory_value_count}f",
            *([0.0] * FEATURE_SCHEMA.trajectory_value_count),
        )
        self.raster = bytes(FEATURE_SCHEMA.raster_byte_count)

    def record(self, index: int, split: str, writer_hash: str = None):
        trajectory = struct.pack(
            f"<{FEATURE_SCHEMA.trajectory_value_count}f",
            *([float(index)] * FEATURE_SCHEMA.trajectory_value_count),
        )
        raster = bytes([index % 256]) * FEATURE_SCHEMA.raster_byte_count
        trajectory_path = f"trajectory/{index}.f32le"
        raster_path = f"raster/{index}.u8"
        self._write(trajectory_path, trajectory)
        self._write(raster_path, raster)
        return record_mapping(
            index,
            split,
            writer_hash=writer_hash,
            trajectory={
                "relative_path": trajectory_path,
                "sha256": digest(trajectory),
                "byte_count": len(trajectory),
                "encoding": "float32-le",
            },
            raster={
                "relative_path": raster_path,
                "sha256": digest(raster),
                "byte_count": len(raster),
                "encoding": "uint8-gray",
            },
        )

    def _write(self, relative_path: str, payload: bytes):
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)


class CorpusContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = CorpusFixture(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def valid_records(self):
        return [
            CorpusRecord.from_mapping(self.fixture.record(index, split), f"records[{index}]")
            for index, split in enumerate(SPLITS, start=1)
        ]

    def test_feature_schema_matches_swift_contract(self):
        self.assertEqual(FEATURE_SCHEMA.trajectory_shape, (1, 256, 10))
        self.assertEqual(FEATURE_SCHEMA.trajectory_byte_count, 10_240)
        self.assertEqual((FEATURE_SCHEMA.raster_width, FEATURE_SCHEMA.raster_height), (256, 96))
        self.assertEqual(FEATURE_SCHEMA.raster_byte_count, 24_576)

    def test_valid_writer_disjoint_corpus_and_artifacts(self):
        records = self.valid_records()
        validate_dataset(records)
        validate_feature_artifacts(records, self.root)

    def test_missing_consent_provenance_writer_session_label_split_and_lineage_fail_closed(self):
        required = (
            "consent_record_id",
            "provenance_record_sha256",
            "writer_id_hash",
            "capture_session_id",
            "label_schema_version",
            "split",
            "lineage_version",
        )
        for field in required:
            with self.subTest(field=field):
                value = self.fixture.record(1, "development")
                del value[field]
                with self.assertRaisesRegex(ContractError, "missing_field"):
                    CorpusRecord.from_mapping(value)

    def test_inactive_consent_is_rejected(self):
        value = self.fixture.record(1, "development")
        value["consent_status"] = "withdrawn"
        with self.assertRaisesRegex(ContractError, "inactive_consent"):
            CorpusRecord.from_mapping(value)

    def test_noncanonical_chord_alias_is_rejected_by_record_contract(self):
        value = self.fixture.record(1, "development")
        value["canonical_label"] = "Cmaj7"
        with self.assertRaisesRegex(ContractError, "invalid_canonical_label"):
            CorpusRecord.from_mapping(value)

    def test_writer_may_not_cross_splits(self):
        records = self.valid_records()
        changed = self.fixture.record(4, "calibration", writer_hash=records[0].writer_id_hash)
        records.append(CorpusRecord.from_mapping(changed))
        with self.assertRaisesRegex(ContractError, "writer_split_leakage"):
            validate_dataset(records)

    def test_session_may_not_cross_writers_or_splits(self):
        values = [self.fixture.record(index, split) for index, split in enumerate(SPLITS, start=1)]
        values[1]["capture_session_id"] = values[0]["capture_session_id"]
        records = [CorpusRecord.from_mapping(value) for value in values]
        with self.assertRaisesRegex(ContractError, "session_leakage"):
            validate_dataset(records)

    def test_derived_record_must_inherit_identity_split_label_and_cluster(self):
        records = self.valid_records()
        value = self.fixture.record(4, "development", writer_hash=records[0].writer_id_hash)
        parent = records[0].as_dict()
        value.update(
            {
                "source_kind": "derived-augmentation",
                "root_sample_id": records[0].sample_id,
                "parent_sample_id": records[0].sample_id,
                "consent_record_id": records[0].consent_record_id,
                "consent_ledger_version": records[0].consent_ledger_version,
                "consent_record_sha256": records[0].consent_record_sha256,
                "provenance_registry_version": records[0].provenance_registry_version,
                "provenance_record_sha256": records[0].provenance_record_sha256,
                "capture_protocol_version": records[0].capture_protocol_version,
                "label_record_id": records[0].label_record_id,
                "geometry_cluster_id": records[0].geometry_cluster_id,
                "canonical_label": records[0].canonical_label,
                "ground_truth_outcome": parent["ground_truth_outcome"],
                "legibility_class": parent["legibility_class"],
                "prompted_intent": parent["prompted_intent"],
                "writer_confirmed_intent": parent["writer_confirmed_intent"],
                "first_reader_transcription": parent["first_reader_transcription"],
                "second_reader_transcription": parent["second_reader_transcription"],
                "adjudication": parent["adjudication"],
                "ground_truth_frozen": parent["ground_truth_frozen"],
            }
        )
        records.append(CorpusRecord.from_mapping(value))
        with self.assertRaisesRegex(ContractError, "lineage_inheritance_mismatch"):
            validate_dataset(records)

    def test_nonfinite_trajectory_is_rejected_even_with_matching_hash(self):
        value = self.fixture.record(1, "development")
        path = self.root / value["trajectory"]["relative_path"]
        payload = bytearray(path.read_bytes())
        payload[:4] = struct.pack("<f", math.nan)
        path.write_bytes(payload)
        value["trajectory"]["sha256"] = digest(payload)
        record = CorpusRecord.from_mapping(value)
        with self.assertRaisesRegex(ContractError, "nonfinite_trajectory"):
            validate_feature_artifacts([record], self.root)

    def test_artifact_hash_tamper_is_rejected(self):
        record = self.valid_records()[0]
        path = self.root / record.raster.relative_path
        payload = bytearray(path.read_bytes())
        payload[0] ^= 0xFF
        path.write_bytes(payload)
        with self.assertRaisesRegex(ContractError, "artifact_digest_mismatch"):
            validate_feature_artifacts([record], self.root)

    def test_manifest_is_deterministic_and_tamper_evident(self):
        records = self.valid_records()
        first = build_manifest(records, "pilot-001")
        second = build_manifest(list(reversed(records)), "pilot-001")
        self.assertEqual(first, second)
        validate_manifest(first, records)
        tampered = copy.deepcopy(first)
        tampered["record_count"] += 1
        with self.assertRaisesRegex(ContractError, "manifest_mismatch"):
            validate_manifest(tampered, records)

    def test_jsonl_rejects_blank_lines_and_unknown_fields(self):
        path = self.root / "records.jsonl"
        record = self.fixture.record(1, "development")
        path.write_text(json.dumps(record) + "\n\n", encoding="utf-8")
        with self.assertRaisesRegex(ContractError, "blank_jsonl_line"):
            load_records_jsonl(path)
        record["answer_from_prompt"] = "Cmaj7"
        path.write_text(json.dumps(record) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(ContractError, "unknown_field"):
            load_records_jsonl(path)


if __name__ == "__main__":
    unittest.main()
