from pathlib import Path
from typing import Dict, List, Mapping, Sequence

from .contracts import (
    CorpusRecord,
    canonical_json_bytes,
    records_digest,
    strict_json_loads,
    validate_dataset,
)
from .errors import ContractError
from .schema import FEATURE_SCHEMA, MANIFEST_SCHEMA_VERSION, SPLITS, TOOL_VERSION


_MANIFEST_FIELDS = {
    "schema_version",
    "tool_version",
    "dataset_version",
    "feature_schema",
    "label_schema_version",
    "record_count",
    "writer_count",
    "session_count",
    "split_record_counts",
    "split_writer_counts",
    "records_sha256",
}


def _version(value: object, path: str) -> str:
    if not isinstance(value, str) or not value:
        raise ContractError("invalid_version", path, "must be a non-empty string")
    allowed = set("abcdefghijklmnopqrstuvwxyz0123456789._-")
    if len(value) > 128 or value[0] not in set("abcdefghijklmnopqrstuvwxyz0123456789"):
        raise ContractError("invalid_version", path, "invalid version token")
    if any(character not in allowed for character in value):
        raise ContractError("invalid_version", path, "invalid version token")
    return value


def build_manifest(records: Sequence[CorpusRecord], dataset_version: str) -> Dict[str, object]:
    validate_dataset(records, require_all_splits=True)
    dataset_version = _version(dataset_version, "dataset_version")
    writers = {record.writer_id_hash for record in records}
    sessions = {record.capture_session_id for record in records}
    label_versions = {record.label_schema_version for record in records}
    split_record_counts = {
        split: sum(record.split == split for record in records) for split in SPLITS
    }
    split_writer_counts = {
        split: len({record.writer_id_hash for record in records if record.split == split})
        for split in SPLITS
    }
    return {
        "dataset_version": dataset_version,
        "feature_schema": FEATURE_SCHEMA.as_dict(),
        "label_schema_version": next(iter(label_versions)),
        "record_count": len(records),
        "records_sha256": records_digest(records),
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "session_count": len(sessions),
        "split_record_counts": split_record_counts,
        "split_writer_counts": split_writer_counts,
        "tool_version": TOOL_VERSION,
        "writer_count": len(writers),
    }


def load_manifest(path: Path) -> Dict[str, object]:
    try:
        value = strict_json_loads(path.read_text(encoding="utf-8"), str(path))
    except (OSError, UnicodeError) as error:
        raise ContractError("manifest_unreadable", str(path), str(error))
    if not isinstance(value, dict):
        raise ContractError("invalid_manifest", str(path), "manifest must be an object")
    return value


def validate_manifest(manifest: Mapping[str, object], records: Sequence[CorpusRecord]) -> None:
    missing = sorted(_MANIFEST_FIELDS.difference(manifest.keys()))
    if missing:
        raise ContractError("missing_field", "manifest", ", ".join(missing))
    unknown = sorted(set(manifest.keys()).difference(_MANIFEST_FIELDS))
    if unknown:
        raise ContractError("unknown_field", "manifest", ", ".join(unknown))
    dataset_version = _version(manifest["dataset_version"], "manifest.dataset_version")
    expected = build_manifest(records, dataset_version)
    if canonical_json_bytes(dict(manifest)) != canonical_json_bytes(expected):
        changed = sorted(key for key in expected if manifest.get(key) != expected[key])
        raise ContractError(
            "manifest_mismatch",
            "manifest",
            f"does not match records for fields: {', '.join(changed)}",
        )


def write_manifest(path: Path, manifest: Mapping[str, object]) -> None:
    payload = canonical_json_bytes(dict(manifest)) + b"\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    try:
        temporary.write_bytes(payload)
        temporary.replace(path)
    except OSError as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise ContractError("manifest_write_failed", str(path), str(error))
