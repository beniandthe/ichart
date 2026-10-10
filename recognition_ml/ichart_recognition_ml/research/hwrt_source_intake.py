"""Pinned HWRT 2015 source-quality intake; no mapping, fitting, or inference."""
from __future__ import annotations

import argparse
import codecs
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
import platform
import tarfile

SOURCE_URL = "https://zenodo.org/records/50022"
ARCHIVE_BYTES = 140_790_596
ARCHIVE_MD5 = "2bf1d089ce65c0a39e57064516f1bd1c"
ARCHIVE_SHA256 = "b96feafd71b01f1623997dff3cc8ac4d18628d128cee1b3df1880518bba3ea4a"
MEMBERS = ("symbols.csv", "test-data.csv", "train-data.csv")
SYMBOL_HEADER = ("symbol_id", "latex", "training_samples", "test_samples")
DATA_HEADER = ("symbol_id", "user_id", "data", "user_agent")
SELECTED_SYMBOL_IDS = frozenset({"196", "922", "266", "948", "1394", "1385",
                                 "950", "974", "1184", "959", "977", "152"})
MAX_MEMBER_BYTES = 2 * 1024 * 1024 * 1024
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024
MAX_CSV_FIELD_BYTES = 64 * 1024 * 1024
VERSION = "hwrt-source-intake-v1"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _json(value) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False, allow_nan=False) + "\n").encode()


def _natural(text: str, field: str) -> int:
    if not text or (text != "0" and (not text.isascii() or not text.isdigit() or text[0] == "0")):
        raise ValueError(f"Invalid {field}: {text!r}")
    return int(text)


def _source_identity(path: Path) -> dict:
    path = Path(path)
    if not path.is_file() or path.stat().st_size != ARCHIVE_BYTES:
        raise ValueError("Pinned archive byte-size mismatch")
    sha, md5 = hashlib.sha256(), hashlib.md5()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
            md5.update(chunk)
    result = {"bytes": path.stat().st_size, "md5": md5.hexdigest(), "sha256": sha.hexdigest()}
    if result["sha256"] != ARCHIVE_SHA256 or result["md5"] != ARCHIVE_MD5:
        raise ValueError("Pinned archive SHA-256/MD5 mismatch")
    return result


def read_stream(binary_lines, expected_header):
    """Yield strict semicolon/single-quote CSV rows from an iterable of byte lines."""
    previous = csv.field_size_limit()
    csv.field_size_limit(MAX_CSV_FIELD_BYTES)
    try:
        reader = csv.DictReader(codecs.iterdecode(binary_lines, "utf-8"), delimiter=";",
                                quotechar="'", strict=True)
        if tuple(reader.fieldnames or ()) != tuple(expected_header):
            raise ValueError(f"Unexpected CSV header; expected {tuple(expected_header)!r}")
        for row in reader:
            if set(row) != set(expected_header) or any(value is None for value in row.values()):
                raise ValueError("Corrupted CSV row width")
            yield row
    finally:
        csv.field_size_limit(previous)


def _members(archive: tarfile.TarFile):
    seen, expanded = set(), 0
    for index, member in enumerate(archive):
        name = member.name
        if (not name or name.startswith("/") or "\\" in name or "\x00" in name
                or any(part in ("", ".", "..") or ":" in part for part in name.split("/"))
                or not member.isfile() or member.issparse()):
            raise ValueError(f"Unsafe TAR member: {name!r}")
        if name in seen:
            raise ValueError(f"Duplicate TAR member: {name!r}")
        if index >= len(MEMBERS) or name != MEMBERS[index]:
            raise ValueError(f"Unexpected TAR member: {name!r}")
        if member.size < 0 or member.size > MAX_MEMBER_BYTES:
            raise ValueError(f"TAR member-byte budget exceeded: {name!r}")
        expanded += member.size
        if expanded > MAX_EXPANDED_BYTES:
            raise ValueError("TAR expanded-byte budget exceeded")
        seen.add(name)
        yield member
    if seen != set(MEMBERS):
        raise ValueError("Missing/extra TAR members")


def _number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _trajectory(raw: str) -> tuple[object | None, str | None, list[str], int, int]:
    issues, coordinate_value, stroke_count, point_count = set(), None, 0, 0
    try:
        value = json.loads(raw)
    except (json.JSONDecodeError, UnicodeError):
        return None, None, ["invalidJSON"], 0, 0
    if not isinstance(value, list):
        return value, None, ["trajectoryNotList"], 0, 0
    stroke_count = len(value)
    if not value:
        issues.add("emptyTrajectory")
    coordinates, valid_coordinates = [], True
    for stroke in value:
        if not isinstance(stroke, list):
            issues.add("strokeNotList")
            valid_coordinates = False
            continue
        if not stroke:
            issues.add("emptyStroke")
        coordinate_stroke, previous_time = [], None
        for point in stroke:
            point_count += 1
            if not isinstance(point, dict):
                issues.add("pointNotObject")
                valid_coordinates = False
                continue
            if "x" not in point or "y" not in point:
                issues.add("missingCoordinate")
                valid_coordinates = False
            else:
                xy = (point["x"], point["y"])
                if not all(_number(component) for component in xy):
                    issues.add("nonnumericCoordinate")
                    valid_coordinates = False
                elif not all(math.isfinite(component) for component in xy):
                    issues.add("nonfiniteCoordinate")
                    valid_coordinates = False
                else:
                    coordinate_stroke.append(list(xy))
            if "time" not in point:
                issues.add("missingTime")
            elif not _number(point["time"]):
                issues.add("nonnumericTime")
            elif not math.isfinite(point["time"]):
                issues.add("nonfiniteTime")
            else:
                if previous_time is not None and point["time"] < previous_time:
                    issues.add("nonmonotonicTime")
                previous_time = point["time"]
        coordinates.append(coordinate_stroke)
    if valid_coordinates:
        coordinate_value = _sha(_json(coordinates))
    try:
        json.dumps(value, allow_nan=False)
        retained = value
    except (TypeError, ValueError):
        retained = None
    return retained, coordinate_value, sorted(issues), stroke_count, point_count


def _group_add(groups: dict, digest: str | None, ref: dict) -> None:
    if digest is None:
        return
    item = groups.setdefault(digest, {"count": 0, "first": None, "duplicates": [],
                                      "roles": set(), "ids": set(), "labels": set()})
    item["count"] += 1
    item["roles"].add(ref["role"])
    item["ids"].add(ref["sourceSymbolID"])
    item["labels"].add(ref["sourceLabel"])
    if item["count"] == 1:
        item["first"] = ref
    elif item["count"] == 2:
        item["duplicates"] = [item.pop("first"), ref]
    else:
        item["duplicates"].append(ref)


def _duplicate_summary(groups: dict, total: int, unavailable: int = 0) -> dict:
    rows, duplicate_records, excess = [], 0, 0
    for digest, item in sorted(groups.items()):
        if item["count"] < 2:
            continue
        duplicate_records += item["count"]
        excess += item["count"] - 1
        rows.append({"sha256": digest, "count": item["count"],
                     "records": item["duplicates"], "roles": sorted(item["roles"]),
                     "sourceSymbolIDs": sorted(item["ids"], key=int),
                     "sourceLabels": sorted(item["labels"]),
                     "conflictingSourceLabels": len(item["labels"]) > 1,
                     "crossesTrainTest": len(item["roles"]) > 1})
    return {"hashedRecordCount": total - unavailable, "unavailableRecordCount": unavailable,
            "duplicateGroupCount": len(rows), "duplicateRecordCount": duplicate_records,
            "excessDuplicateCount": excess,
            "duplicateRecordRate": duplicate_records / total if total else 0.0,
            "labelConflictGroupCount": sum(row["conflictingSourceLabels"] for row in rows),
            "trainTestCrossingGroupCount": sum(row["crossesTrainTest"] for row in rows),
            "groups": rows}


def _member_rows(archive, member, header, row_reader):
    digest, count = hashlib.sha256(), 0
    stream = archive.extractfile(member)
    if stream is None:
        raise ValueError(f"Unable to read TAR member: {member.name}")
    with stream:
        def lines():
            nonlocal count
            for line in stream:
                digest.update(line)
                count += len(line)
                yield line
        yield from row_reader(lines(), header)
    if count != member.size:
        raise ValueError(f"Truncated TAR member: {member.name}")
    _member_rows.last_identity = {"bytes": count, "sha256": digest.hexdigest()}


def audit_tar(archive: tarfile.TarFile, *, archive_identity: dict, row_reader=read_stream) -> dict:
    """Audit an already-open tar; synthetic tests use this without weakening the real CLI pin."""
    classes, member_identities = {}, {}
    observed = {role: Counter() for role in ("train", "test")}
    selected, raw_groups, coordinate_groups = [], {}, {}
    selected_issues, total, coordinate_unavailable = Counter(), 0, 0
    for member in _members(archive):
        if member.name == "symbols.csv":
            for row in _member_rows(archive, member, SYMBOL_HEADER, row_reader):
                symbol_id = row["symbol_id"]
                _natural(symbol_id, "source symbol ID")
                if symbol_id in classes or not row["latex"]:
                    raise ValueError("Duplicate native symbol ID or empty native label")
                classes[symbol_id] = {"sourceSymbolID": symbol_id, "sourceLabel": row["latex"],
                                      "declaredTrainingSamples": _natural(row["training_samples"], "training count"),
                                      "declaredTestSamples": _natural(row["test_samples"], "test count"),
                                      "canonicalChordLabel": None,
                                      "selectedForGeometryAudit": symbol_id in SELECTED_SYMBOL_IDS}
            member_identities[member.name] = _member_rows.last_identity
            if not SELECTED_SYMBOL_IDS <= classes.keys():
                raise ValueError("Selected native symbol IDs missing from symbols.csv")
            continue
        role = "test" if member.name == "test-data.csv" else "train"
        for index, row in enumerate(_member_rows(archive, member, DATA_HEADER, row_reader)):
            symbol_id = row["symbol_id"]
            if symbol_id not in classes:
                raise ValueError(f"Unknown source symbol ID in {member.name}: {symbol_id!r}")
            observed[role][symbol_id] += 1
            total += 1
            raw_digest = _sha(row["data"].encode("utf-8"))
            opaque = _sha(f"{archive_identity['sha256']}\0{role}\0{index}".encode())
            ref = {"recordID": opaque, "role": role, "recordIndex": index,
                   "sourceSymbolID": symbol_id, "sourceLabel": classes[symbol_id]["sourceLabel"]}
            _group_add(raw_groups, raw_digest, ref)
            if symbol_id in SELECTED_SYMBOL_IDS:
                trajectory, coordinate_digest, row_issues, strokes, points = _trajectory(row["data"])
                selected_issues.update(row_issues)
                coordinate_unavailable += coordinate_digest is None
                _group_add(coordinate_groups, coordinate_digest, ref)
                item = {**ref, "archiveSHA256": archive_identity["sha256"],
                        "sourceLabel": classes[symbol_id]["sourceLabel"],
                        "canonicalChordLabel": None,
                        "userIDHash": _sha(b"hwrt2015-user-v1\0" + row["user_id"].encode()),
                        "writerIdentityReliable": False, "dataSHA256": raw_digest,
                        "coordinatePayloadSHA256": coordinate_digest, "issues": row_issues,
                        "strokeCount": strokes, "pointCount": points, "strokes": trajectory}
                if trajectory is None:
                    item["rawData"] = row["data"]
                selected.append(item)
        member_identities[member.name] = _member_rows.last_identity

    class_rows = []
    for symbol_id, row in classes.items():
        train, test = observed["train"][symbol_id], observed["test"][symbol_id]
        if (train, test) != (row["declaredTrainingSamples"], row["declaredTestSamples"]):
            raise ValueError(f"Native class count mismatch: {symbol_id}")
        class_rows.append({**row, "observedTrainingSamples": train, "observedTestSamples": test})
    class_rows.sort(key=lambda row: int(row["sourceSymbolID"]))
    duplicates = {"version": VERSION, "allMetadataRecordCount": total,
                  "selectedGeometryRecordCount": len(selected),
                  "rawDataAllRecords": _duplicate_summary(raw_groups, total),
                  "selectedCoordinatePayloadIgnoringTiming": _duplicate_summary(
                      coordinate_groups, len(selected), coordinate_unavailable)}
    receipt = {"version": VERSION, "artifactKind": "research-only-source-quality-audit-v1",
               "sourceURL": SOURCE_URL, "archive": archive_identity,
               "members": member_identities, "memberCount": len(member_identities),
               "expandedBytes": sum(row["bytes"] for row in member_identities.values()),
               "classCount": len(class_rows),
               "recordCount": total, "trainingRecordCount": sum(observed["train"].values()),
               "testRecordCount": sum(observed["test"].values()),
               "selectedSourceSymbolIDs": sorted(SELECTED_SYMBOL_IDS, key=int),
               "selectedRecordCount": len(selected),
               "selectedGeometryIssueCounts": dict(sorted(selected_issues.items())),
               "trajectoryObserved": True, "writerIdentityReliable": False,
               "userIDInterpretation": "opaque-source-identifier-not-verified-writer",
               "canonicalChordMappingPerformed": False, "modelOrFeatureWorkPerformed": False,
               "allMetadataRowsCounted": True, "selectedInvalidRowsPreserved": True,
               "declaredDatasetLicense": "ODbL", "shippingOrModelLicenseCleared": False,
               "runtime": {"python": platform.python_version()}}
    return {"receipt": receipt, "classes": class_rows, "selectedRecords": selected,
            "duplicateLedger": duplicates}


def audit_archive(path: Path, *, row_reader=read_stream) -> dict:
    path = Path(path)
    identity = _source_identity(path)
    with tarfile.open(path, "r|bz2") as archive:
        result = audit_tar(archive, archive_identity=identity, row_reader=row_reader)
    if _source_identity(path) != identity:
        raise ValueError("Source archive changed during audit")
    return result


def _fresh_output(path: Path) -> Path:
    path = path.resolve()
    if any((parent / ".git").exists() for parent in (path, *path.parents)):
        raise ValueError("Output directory must be outside Git")
    path.mkdir(parents=True, exist_ok=False)
    return path


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-tar", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    source, test = Path(__file__).resolve(), Path(__file__).resolve().parents[3] / "recognition_ml/tests/test_hwrt_source_intake.py"
    snapshots = {str(path): path.read_bytes() for path in (source, test)}
    result = audit_archive(args.source_tar)
    output = _fresh_output(args.output_dir)
    artifacts = {}
    values = (("source_classes.json", _json(result["classes"])),
              ("selected_records.jsonl", b"".join(_json(row) for row in result["selectedRecords"])),
              ("duplicateledger.json", _json(result["duplicateLedger"])))
    for name, data in values:
        with (output / name).open("xb") as stream:
            stream.write(data)
        artifacts[name] = {"bytes": len(data), "sha256": _sha(data)}
    receipt = {**result["receipt"], "inputBindings": {path: _sha(data) for path, data in snapshots.items()},
               "artifacts": artifacts}
    if any(Path(path).read_bytes() != data for path, data in snapshots.items()):
        raise ValueError("Implementation or tests changed before publication")
    for name, expected in artifacts.items():
        data = (output / name).read_bytes()
        if {"bytes": len(data), "sha256": _sha(data)} != expected:
            raise ValueError(f"Artifact changed before publication: {name}")
    if _source_identity(args.source_tar) != receipt["archive"]:
        raise ValueError("Source archive changed before publication")
    with (output / "source_receipt.json").open("xb") as stream:
        stream.write(_json(receipt))
    print(json.dumps({key: receipt[key] for key in ("classCount", "recordCount", "selectedRecordCount")},
                     sort_keys=True))


if __name__ == "__main__":
    main()
