"""Inventory literal chord-fragment coverage in pinned HWRT training ink only.

This is a source-quality audit, not a model-data adapter.  It selects a native
HWRT class only when its exact source label occurs in the pinned chord-domain
allowlist.  It never parses test geometry and performs no rasterization,
feature extraction, fitting, inference, label aliasing, or normalization.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import platform
import stat
import tarfile
from typing import Mapping, Sequence

from . import hwrt_source_intake as intake


VERSION = "hwrt-literal-training-inventory-v1"
CLASS_REPORT_VERSION = "hwrt-literal-training-classes-v1"
DUPLICATE_LEDGER_VERSION = "hwrt-literal-training-duplicates-v1"
SOURCE_CLASSES_SHA256 = "3265af383b023ffafc8192ae04944e6e4003d0abf7a50b03a75e15ca8a231788"
SOURCE_RECEIPT_SHA256 = "f705c1696878bcc105f3b543dc381f3e78b7dff27e7693864280ac25e5e15545"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
EXPECTED_LITERAL_CLASS_COUNT = 35
EXPECTED_LITERAL_TRAINING_RECORDS = 2_439
EXPECTED_MISSING_ALLOWED_LABELS = ("%", "(", ")", ".", "t", "º")
MAX_METADATA_BYTES = 16 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[3]
CODE_PATHS = (
    "recognition_ml/ichart_recognition_ml/research/hwrt_source_intake.py",
    "recognition_ml/tests/test_hwrt_source_intake.py",
    "recognition_ml/ichart_recognition_ml/research/hwrt_literal_training_inventory.py",
    "recognition_ml/tests/test_hwrt_literal_training_inventory.py",
)
CLASS_FIELDS = {
    "canonicalChordLabel", "declaredTestSamples", "declaredTrainingSamples",
    "observedTestSamples", "observedTrainingSamples", "selectedForGeometryAudit",
    "sourceLabel", "sourceSymbolID",
}
TIMING_ISSUES = frozenset({"missingTime", "nonnumericTime", "nonfiniteTime", "nonmonotonicTime"})


def _sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _canonical(value) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def _read_regular(path: Path, *, maximum: int = MAX_METADATA_BYTES) -> bytes:
    path = Path(path)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
        raise ValueError(f"Unsafe or oversized regular-file input: {path}")
    payload = path.read_bytes()
    if len(payload) != info.st_size:
        raise ValueError(f"Truncated regular-file input: {path}")
    return payload


def _decode_json(payload: bytes, name: str):
    try:
        return json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Invalid {name} JSON") from error


def _identity(payload: bytes) -> dict:
    return {"bytes": len(payload), "sha256": _sha(payload)}


def _code_identity() -> dict[str, str]:
    return {
        relative: _sha(_read_regular(ROOT / relative))
        for relative in CODE_PATHS
    }


def _validate_classes(value) -> tuple[dict, ...]:
    if not isinstance(value, list) or not value:
        raise ValueError("Pinned source classes must be a nonempty array")
    rows, ids, labels = [], set(), set()
    for row in value:
        if not isinstance(row, dict) or set(row) != CLASS_FIELDS:
            raise ValueError("Pinned source-class schema changed")
        symbol_id, label = row["sourceSymbolID"], row["sourceLabel"]
        intake._natural(symbol_id, "source symbol ID")
        counts = (
            row["declaredTrainingSamples"], row["declaredTestSamples"],
            row["observedTrainingSamples"], row["observedTestSamples"],
        )
        if (
            symbol_id in ids or label in labels or not isinstance(label, str) or not label
            or any(type(count) is not int or count < 0 for count in counts)
            or counts[0] != counts[2] or counts[1] != counts[3]
            or row["canonicalChordLabel"] is not None
            or type(row["selectedForGeometryAudit"]) is not bool
        ):
            raise ValueError("Pinned source-class identity/count changed")
        ids.add(symbol_id); labels.add(label); rows.append(dict(row))
    if [int(row["sourceSymbolID"]) for row in rows] != sorted(int(row["sourceSymbolID"]) for row in rows):
        raise ValueError("Pinned source classes are not in native-ID order")
    return tuple(rows)


def _validate_domain(value) -> tuple[str, ...]:
    if (
        not isinstance(value, dict)
        or set(value) != {"allowedLabels", "scope", "version", "vocabulary"}
        or value.get("version") != "chord-recognition-domain-v1"
        or not isinstance(value.get("scope"), str)
        or not isinstance(value.get("allowedLabels"), list)
        or not isinstance(value.get("vocabulary"), list)
    ):
        raise ValueError("Pinned chord-domain schema changed")
    allowed, vocabulary = value["allowedLabels"], value["vocabulary"]
    if (
        not allowed or len(set(allowed)) != len(allowed)
        or len(set(vocabulary)) != len(vocabulary)
        or any(not isinstance(label, str) or not label for label in allowed + vocabulary)
        or any(label not in vocabulary for label in allowed)
    ):
        raise ValueError("Pinned chord-domain vocabulary changed")
    return tuple(allowed)


def _validate_source_receipt(value, classes: Sequence[Mapping[str, object]],
                             classes_identity: Mapping[str, object]) -> dict:
    if not isinstance(value, dict):
        raise ValueError("Pinned source receipt is not an object")
    members = value.get("members")
    archive = value.get("archive")
    if (
        value.get("version") != intake.VERSION
        or value.get("classCount") != len(classes)
        or value.get("trainingRecordCount") != sum(row["observedTrainingSamples"] for row in classes)
        or value.get("testRecordCount") != sum(row["observedTestSamples"] for row in classes)
        or value.get("recordCount") != value.get("trainingRecordCount") + value.get("testRecordCount")
        or value.get("memberCount") != 3
        or not isinstance(members, dict) or tuple(members) != intake.MEMBERS
        or not isinstance(archive, dict)
        or archive.get("bytes") != intake.ARCHIVE_BYTES
        or archive.get("md5") != intake.ARCHIVE_MD5
        or archive.get("sha256") != intake.ARCHIVE_SHA256
        or value.get("artifacts", {}).get("source_classes.json") != dict(classes_identity)
        or value.get("allMetadataRowsCounted") is not True
        or value.get("canonicalChordMappingPerformed") is not False
        or value.get("modelOrFeatureWorkPerformed") is not False
    ):
        raise ValueError("Pinned source receipt contract changed")
    for name in intake.MEMBERS:
        identity = members.get(name)
        if (
            not isinstance(identity, dict) or set(identity) != {"bytes", "sha256"}
            or type(identity["bytes"]) is not int or identity["bytes"] <= 0
            or not isinstance(identity["sha256"], str) or len(identity["sha256"]) != 64
        ):
            raise ValueError("Pinned source-member identity changed")
    return value


def _load_pinned_inputs(classes_path: Path, receipt_path: Path, domain_path: Path):
    classes_bytes = _read_regular(classes_path)
    receipt_bytes = _read_regular(receipt_path)
    domain_bytes = _read_regular(domain_path)
    if (
        _sha(classes_bytes) != SOURCE_CLASSES_SHA256
        or _sha(receipt_bytes) != SOURCE_RECEIPT_SHA256
        or _sha(domain_bytes) != DOMAIN_SHA256
    ):
        raise ValueError("Pinned source classes, receipt, or chord domain changed")
    classes = _validate_classes(_decode_json(classes_bytes, "source classes"))
    receipt = _validate_source_receipt(
        _decode_json(receipt_bytes, "source receipt"), classes, _identity(classes_bytes)
    )
    allowed = _validate_domain(_decode_json(domain_bytes, "chord domain"))
    selected = tuple(row for row in classes if row["sourceLabel"] in set(allowed))
    missing = tuple(label for label in allowed if label not in {row["sourceLabel"] for row in classes})
    if (
        len(selected) != EXPECTED_LITERAL_CLASS_COUNT
        or sum(row["observedTrainingSamples"] for row in selected) != EXPECTED_LITERAL_TRAINING_RECORDS
        or missing != EXPECTED_MISSING_ALLOWED_LABELS
    ):
        raise ValueError("Pinned literal source/domain overlap changed")
    return classes, receipt, allowed, {
        "sourceClasses": classes_bytes, "sourceReceipt": receipt_bytes, "domain": domain_bytes,
    }


def _hash_member(archive: tarfile.TarFile, member: tarfile.TarInfo) -> dict:
    stream = archive.extractfile(member)
    if stream is None:
        raise ValueError(f"Unable to read TAR member: {member.name}")
    digest, count = hashlib.sha256(), 0
    with stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk); count += len(chunk)
    if count != member.size:
        raise ValueError(f"Truncated TAR member: {member.name}")
    return {"bytes": count, "sha256": digest.hexdigest()}


def _class_report(classes, allowed, per_class) -> dict:
    source_labels = {row["sourceLabel"] for row in classes}
    selected = []
    for row in classes:
        if row["sourceLabel"] not in set(allowed):
            continue
        counts = per_class[row["sourceSymbolID"]]
        selected.append({
            "sourceSymbolID": row["sourceSymbolID"],
            "sourceLabel": row["sourceLabel"],
            "declaredTrainingSamples": row["declaredTrainingSamples"],
            "observedTrainingSamples": counts["records"],
            "invalidTrajectoryCount": counts["invalid"],
            "timingIssueRecordCount": counts["timing"],
            "issueCounts": dict(sorted(counts["issues"].items())),
        })
    return {
        "version": CLASS_REPORT_VERSION,
        "selectionRule": "exact-sourceLabel-in-chord-domain-allowedLabels",
        "aliasesCaseFoldingOrTeXNormalizationUsed": False,
        "sourceClassCount": len(classes),
        "allowedLabelCount": len(allowed),
        "overlapCount": len(selected),
        "overlapLabels": [row["sourceLabel"] for row in selected],
        "missingAllowedLabels": [label for label in allowed if label not in source_labels],
        "selectedClasses": selected,
    }


def scan_tar(archive: tarfile.TarFile, *, archive_identity: Mapping[str, object],
             classes: Sequence[Mapping[str, object]], allowed_labels: Sequence[str],
             expected_members: Mapping[str, Mapping[str, object]],
             expected_training_count: int, expected_literal_class_count: int,
             row_reader=intake.read_stream) -> dict:
    """Scan symbols + training rows; test bytes are authenticated but never parsed."""

    classes = _validate_classes(list(classes))
    allowed = tuple(allowed_labels)
    if not allowed or len(set(allowed)) != len(allowed):
        raise ValueError("Literal allowlist is empty or duplicated")
    by_id = {row["sourceSymbolID"]: row for row in classes}
    selected_ids = {
        row["sourceSymbolID"] for row in classes if row["sourceLabel"] in set(allowed)
    }
    if len(selected_ids) != expected_literal_class_count:
        raise ValueError("Literal selected-class count changed")

    observed, records = Counter(), []
    issue_counts, invalid, timing = Counter(), 0, 0
    per_class = {
        symbol_id: {"records": 0, "invalid": 0, "timing": 0, "issues": Counter()}
        for symbol_id in selected_ids
    }
    raw_groups, coordinate_groups, coordinate_unavailable = {}, {}, 0
    member_identities = {}
    for member in intake._members(archive):
        if member.name == "test-data.csv":
            identity = _hash_member(archive, member)
            member_identities[member.name] = identity
            if identity != expected_members.get(member.name):
                raise ValueError("Pinned test member changed")
            continue
        header = intake.SYMBOL_HEADER if member.name == "symbols.csv" else intake.DATA_HEADER
        rows = intake._member_rows(archive, member, header, row_reader)
        if member.name == "symbols.csv":
            seen = set()
            for row in rows:
                symbol_id = row["symbol_id"]
                if symbol_id in seen or symbol_id not in by_id:
                    raise ValueError("symbols.csv native identity changed")
                seen.add(symbol_id)
                expected = by_id[symbol_id]
                if (
                    row["latex"] != expected["sourceLabel"]
                    or intake._natural(row["training_samples"], "training count")
                    != expected["declaredTrainingSamples"]
                    or intake._natural(row["test_samples"], "test count")
                    != expected["declaredTestSamples"]
                ):
                    raise ValueError("symbols.csv metadata differs from pinned source classes")
            if seen != set(by_id):
                raise ValueError("symbols.csv class coverage changed")
        else:
            for index, row in enumerate(rows):
                symbol_id = row["symbol_id"]
                if symbol_id not in by_id:
                    raise ValueError("Unknown native symbol ID in training member")
                observed[symbol_id] += 1
                if symbol_id not in selected_ids:
                    continue
                source_class = by_id[symbol_id]
                raw_digest = intake._sha(row["data"].encode("utf-8"))
                record_id = intake._sha(
                    f"{archive_identity['sha256']}\0train\0{index}".encode()
                )
                ref = {
                    "recordID": record_id, "role": "train", "recordIndex": index,
                    "sourceSymbolID": symbol_id, "sourceLabel": source_class["sourceLabel"],
                }
                trajectory, coordinate_digest, issues, strokes, points = intake._trajectory(row["data"])
                has_timing_issue = any(issue in TIMING_ISSUES for issue in issues)
                invalid_trajectory = (
                    trajectory is None
                    or coordinate_digest is None
                    or any(issue not in TIMING_ISSUES for issue in issues)
                )
                issue_counts.update(issues); invalid += invalid_trajectory; timing += has_timing_issue
                summary = per_class[symbol_id]
                summary["records"] += 1
                summary["invalid"] += invalid_trajectory
                summary["timing"] += has_timing_issue
                summary["issues"].update(issues)
                intake._group_add(raw_groups, raw_digest, ref)
                intake._group_add(coordinate_groups, coordinate_digest, ref)
                coordinate_unavailable += coordinate_digest is None
                item = {
                    **ref,
                    "archiveSHA256": archive_identity["sha256"],
                    "dataSHA256": raw_digest,
                    "coordinatePayloadSHA256": coordinate_digest,
                    "issues": issues,
                    "strokeCount": strokes,
                    "pointCount": points,
                    "strokes": trajectory,
                }
                if trajectory is None:
                    item["rawData"] = row["data"]
                records.append(item)
        identity = intake._member_rows.last_identity
        member_identities[member.name] = identity
        if identity != expected_members.get(member.name):
            raise ValueError(f"Pinned {member.name} member changed")

    expected_counts = {row["sourceSymbolID"]: row["observedTrainingSamples"] for row in classes}
    if observed != Counter(expected_counts) or sum(observed.values()) != expected_training_count:
        raise ValueError("Every native training-class count did not reconcile")
    expected_selected = sum(expected_counts[symbol_id] for symbol_id in selected_ids)
    if len(records) != expected_selected:
        raise ValueError("Selected literal training-row count changed")
    duplicates = {
        "version": DUPLICATE_LEDGER_VERSION,
        "scope": "literal-selected-training-rows-only",
        "selectedTrainingRecordCount": len(records),
        "rawDataSelectedTraining": intake._duplicate_summary(raw_groups, len(records)),
        "coordinatePayloadIgnoringTimingSelectedTraining": intake._duplicate_summary(
            coordinate_groups, len(records), coordinate_unavailable
        ),
    }
    return {
        "memberIdentities": member_identities,
        "records": records,
        "classReport": _class_report(classes, allowed, per_class),
        "duplicateLedger": duplicates,
        "trainingRecordCount": sum(observed.values()),
        "selectedTrainingRecordCount": len(records),
        "selectedTrainingIssueCounts": dict(sorted(issue_counts.items())),
        "selectedTrainingInvalidTrajectoryCount": invalid,
        "selectedTrainingTimingIssueCount": timing,
        "testMemberHashedWithoutCSVOrGeometryParsing": True,
    }


def _archive_identity(path: Path) -> dict:
    path = Path(path)
    if stat.S_ISLNK(path.lstat().st_mode):
        raise ValueError("Pinned archive must not be a symbolic link")
    return intake._source_identity(path)


def _write_exclusive(path: Path, payload: bytes) -> None:
    with path.open("xb") as stream:
        stream.write(payload)


def prepare(source_tar: Path, source_classes: Path, source_receipt: Path,
            domain_path: Path, output: Path) -> dict:
    classes, prior_receipt, allowed, input_bytes = _load_pinned_inputs(
        source_classes, source_receipt, domain_path
    )
    code = _code_identity()
    archive_before = _archive_identity(source_tar)
    with tarfile.open(source_tar, "r|bz2") as archive:
        result = scan_tar(
            archive,
            archive_identity=archive_before,
            classes=classes,
            allowed_labels=allowed,
            expected_members=prior_receipt["members"],
            expected_training_count=prior_receipt["trainingRecordCount"],
            expected_literal_class_count=EXPECTED_LITERAL_CLASS_COUNT,
        )
    if (
        result["selectedTrainingRecordCount"] != EXPECTED_LITERAL_TRAINING_RECORDS
        or tuple(result["classReport"]["missingAllowedLabels"])
        != EXPECTED_MISSING_ALLOWED_LABELS
    ):
        raise ValueError("Literal training inventory totals changed")
    if _archive_identity(source_tar) != archive_before:
        raise ValueError("Pinned archive changed during inventory")

    destination = intake._fresh_output(Path(output))
    values = {
        "literal_classes.json": _canonical(result["classReport"]),
        "training_records.jsonl": b"".join(_canonical(row) for row in result["records"]),
        "duplicate_ledger.json": _canonical(result["duplicateLedger"]),
    }
    artifacts = {}
    for name, payload in values.items():
        _write_exclusive(destination / name, payload)
        artifacts[name] = _identity(payload)
    receipt = {
        "version": VERSION,
        "artifactKind": "research-only-literal-training-source-inventory-v1",
        "sourceURL": intake.SOURCE_URL,
        "archive": archive_before,
        "sourceBindings": {
            "sourceClasses": _identity(input_bytes["sourceClasses"]),
            "sourceReceipt": _identity(input_bytes["sourceReceipt"]),
            "chordDomain": _identity(input_bytes["domain"]),
        },
        "members": result["memberIdentities"],
        "sourceClassCount": len(classes),
        "allowedLabelCount": len(allowed),
        "literalClassCount": result["classReport"]["overlapCount"],
        "missingAllowedLabels": result["classReport"]["missingAllowedLabels"],
        "trainingRecordCount": result["trainingRecordCount"],
        "selectedTrainingRecordCount": result["selectedTrainingRecordCount"],
        "selectedTrainingIssueCounts": result["selectedTrainingIssueCounts"],
        "selectedTrainingInvalidTrajectoryCount": result["selectedTrainingInvalidTrajectoryCount"],
        "selectedTrainingTimingIssueCount": result["selectedTrainingTimingIssueCount"],
        "testMemberHashedWithoutCSVOrGeometryParsing": True,
        "selectionRule": "exact-sourceLabel-in-chord-domain-allowedLabels",
        "aliasesCaseFoldingOrTeXNormalizationUsed": False,
        "writerIdentityUsed": False,
        "testRowsParsed": False,
        "rasterFeatureModelFitOrInferencePerformed": False,
        "artifacts": artifacts,
        "codeSHA256": code,
        "runtime": {"python": platform.python_version()},
    }
    if (
        _archive_identity(source_tar) != archive_before
        or _read_regular(source_classes) != input_bytes["sourceClasses"]
        or _read_regular(source_receipt) != input_bytes["sourceReceipt"]
        or _read_regular(domain_path) != input_bytes["domain"]
        or _code_identity() != code
        or any(_identity(_read_regular(destination / name, maximum=int(identity["bytes"]))) != identity
               for name, identity in artifacts.items())
    ):
        raise ValueError("Source, code, or output changed before receipt publication")
    _write_exclusive(destination / "inventory-receipt.json", _canonical(receipt))
    return receipt


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-tar", type=Path, required=True)
    parser.add_argument("--source-classes", type=Path, required=True)
    parser.add_argument("--source-receipt", type=Path, required=True)
    parser.add_argument("--domain", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    receipt = prepare(
        args.source_tar, args.source_classes, args.source_receipt, args.domain, args.output
    )
    print(json.dumps({
        "literalClassCount": receipt["literalClassCount"],
        "selectedTrainingRecordCount": receipt["selectedTrainingRecordCount"],
        "version": receipt["version"],
    }, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
