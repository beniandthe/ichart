"""Two-pass, pre-model copy quarantine for a frozen NIST raster source audit.

All members of every repeated raw PNG or decoded raster hash are removed from
the clean integrity manifest. Originals remain unchanged; rights remain unresolved.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from . import nist_sd19 as source

_SHA = re.compile(r"[0-9a-f]{64}")
_PROVENANCE = ("sourceID", "sourceArchiveSHA256", "importerSourceSHA256", "runtime",
               "rightsStatus", "inputKind", "observedTrajectories", "trainingEligibilityEstablished")


def _hash(value) -> bool:
    return isinstance(value, str) and _SHA.fullmatch(value) is not None


def _load_summary(path: Path, expected_sha256: str) -> tuple[dict, dict, dict]:
    data = path.read_bytes()
    if not _hash(expected_sha256) or hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError("Source summary SHA256 mismatch")
    summary = json.loads(data)
    if (summary.get("sourceID") != source.SOURCE_ID or summary.get("rightsStatus") != source.RIGHTS_STATUS
            or summary.get("inputKind") != "raster-only" or summary.get("observedTrajectories") is not False
            or summary.get("trainingEligibilityEstablished") is not False
            or summary.get("importerSourceSHA256") != source.sha256_file(Path(source.__file__))
            or not _hash(summary.get("samplesJSONLSHA256"))):
        raise ValueError("Invalid frozen source provenance/rights receipt")
    archives, runtime, raster = summary.get("sourceArchiveSHA256", {}), summary.get("runtime", {}), summary.get("rasterVerification", {})
    if (set(archives) != {"pngZIP", "clsZIP"} or not all(_hash(value) for value in archives.values())
            or not isinstance(runtime.get("python"), str) or not isinstance(runtime.get("pillow"), str)
            or raster.get("verifiedCount") != summary.get("sampleCount") or raster.get("binary") is not True
            or raster.get("dimensions") != [128, 128]):
        raise ValueError("Missing verified raster/source/runtime receipt")
    writers = {}
    for writer in summary["writers"]:
        identity = writer["writerID"]
        if identity in writers or writer["split"] not in source.ROLES:
            raise ValueError("Duplicate/invalid source writer role receipt")
        writers[identity] = writer
    fields = {}
    for field in summary["fields"]:
        if field["fieldKey"] in fields:
            raise ValueError("Duplicate source field receipt")
        fields[field["fieldKey"]] = field
    if len(writers) != summary["writerCount"] or len(fields) != summary["fieldCount"]:
        raise ValueError("Source writer/field count mismatch")
    return summary, writers, fields


def _validate_row(row: dict, writers: dict, fields: dict) -> None:
    if not _hash(row.get("png_sha256")) or not _hash(row.get("decoded_raster_sha256")):
        raise ValueError("Missing/invalid raw PNG or decoded raster SHA256")
    field, index = source.parse_png_path(row["png_member"])
    if (row["sample_id"] != f"{field.key}/{index:05d}" or row["writer_id"] != field.writer_id
            or row["partition"] != field.partition or row["template_id"] != field.template_id
            or row["form_id"] != field.form_id or row["field_id"] != field.field_id or row["image_index"] != index):
        raise ValueError("Source row identity mismatch")
    writer = writers.get(row["writer_id"], {})
    if (row["split"] != writer.get("split") or row["partition"] not in writer.get("partitions", [])
            or f"{row['partition']}/{row['form_id']}" not in writer.get("forms", [])):
        raise ValueError("Source writer role/form violation")
    receipt = fields.get(field.key, {})
    if (row["cls_member"] != receipt.get("clsMember") or row["cls_sha256"] != receipt.get("clsSHA256")
            or row["cls_label_line"] != index + 2):
        raise ValueError("Source checked-label receipt mismatch")
    token = row["label_byte_hex"]
    if (not isinstance(token, str) or re.fullmatch(r"[0-7][0-9a-f]", token) is None
            or row["label"] != chr(int(token, 16)) or re.fullmatch(r"[0-9a-fA-F]{2}", row["label_raw_token"]) is None
            or int(row["label_raw_token"], 16) != int(token, 16)):
        raise ValueError("Invalid exact source label byte")


def _remember(groups: dict, digest: str, identity: str) -> None:
    old = groups.get(digest)
    if old is None:
        groups[digest] = identity
    elif isinstance(old, str):
        groups[digest] = [old, identity]
    else:
        old.append(identity)


def _counts() -> dict:
    return {"sampleCount": 0, "classCountsByByteHex": Counter(), "roleCounts": Counter()}


def _count(counts: dict, row: dict) -> None:
    counts["sampleCount"] += 1
    counts["classCountsByByteHex"][row["label_byte_hex"]] += 1
    counts["roleCounts"][row["split"]] += 1


def _row(line: bytes) -> dict:
    if not line.endswith(b"\n"):
        raise ValueError("Source JSONL row lacks LF termination")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise ValueError("Invalid source JSONL row")
    return value


def quarantine_source(summary_path: Path, samples_path: Path, output: Path, *, expected_summary_sha256: str) -> dict:
    """Validate first, then stream verbatim clean rows and recoverable removed rows.

    Quarantine JSONL includes the complete parsed row and base64 of the exact
    original line including LF. Neither images nor their pixels are read/decoded.
    """
    summary_path, samples_path, output = Path(summary_path), Path(samples_path), Path(output)
    if output.exists():
        raise FileExistsError(f"Exclusive output directory already exists: {output}")
    summary, writers, fields = _load_summary(summary_path, expected_summary_sha256)
    original, field_counts, seen = _counts(), Counter(), set()
    raw, pixels, input_digest = {}, {}, hashlib.sha256()
    with samples_path.open("rb") as stream:
        for line in stream:
            input_digest.update(line)
            row = _row(line)
            _validate_row(row, writers, fields)
            identity = row["sample_id"]
            if identity in seen:
                raise ValueError(f"Duplicate source sample ID: {identity}")
            seen.add(identity)
            _count(original, row)
            field_counts[identity.rsplit("/", 1)[0]] += 1
            _remember(raw, row["png_sha256"], identity)
            _remember(pixels, row["decoded_raster_sha256"], identity)
    if input_digest.hexdigest() != summary["samplesJSONLSHA256"]:
        raise ValueError("Source samples stream SHA256 mismatch")
    if (original["sampleCount"] != summary["sampleCount"] or original["roleCounts"] != summary["sampleCountsBySplit"]
            or original["classCountsByByteHex"] != summary["labelsByByteHex"]
            or any(field_counts[key] != field["count"] for key, field in fields.items())):
        raise ValueError("Source sample/class/role/field count mismatch")
    repeated = [(kind, digest, sorted(members)) for kind, groups in (("raw-png", raw), ("decoded-raster", pixels))
                for digest, members in groups.items() if isinstance(members, list)]
    repeated.sort(key=lambda group: (group[0], group[1]))
    reasons = {}
    for kind, _, members in repeated:
        for identity in members:
            reasons.setdefault(identity, set()).add(f"repeated-{kind}-hash")
    del seen, raw, pixels
    output.mkdir(mode=0o700)
    clean, removed, member_details = _counts(), _counts(), {}
    clean_digest, quarantine_digest, second_digest = hashlib.sha256(), hashlib.sha256(), hashlib.sha256()
    with samples_path.open("rb") as stream, (output / "clean-source-integrity-manifest.jsonl").open("xb") as clean_stream, \
            (output / "quarantined.jsonl").open("xb") as removed_stream:
        for line in stream:
            second_digest.update(line)
            row = _row(line)
            identity = row["sample_id"]
            if identity not in reasons:
                clean_stream.write(line)
                clean_digest.update(line)
                _count(clean, row)
            else:
                record = {"sampleID": identity, "reasons": sorted(reasons[identity]), "sourceRow": row,
                          "sourceLineBase64": base64.b64encode(line).decode("ascii")}
                encoded = (json.dumps(record, sort_keys=True) + "\n").encode("utf-8")
                removed_stream.write(encoded)
                quarantine_digest.update(encoded)
                _count(removed, row)
                member_details[identity] = {"sampleID": identity, "writerID": row["writer_id"],
                    "split": row["split"], "label": row["label"], "labelByteHex": row["label_byte_hex"]}
    if second_digest.hexdigest() != summary["samplesJSONLSHA256"]:
        raise ValueError("Source samples changed between quarantine passes; no receipt written")
    groups = []
    for kind, digest, identities in repeated:
        members = [member_details[identity] for identity in identities]
        groups.append({"hashKind": kind, "sha256": digest, "memberCount": len(members), "members": members,
                       "conflictingLabels": len({m["labelByteHex"] for m in members}) > 1,
                       "crossSplit": len({m["split"] for m in members}) > 1})
    receipt = {"formatVersion": 1, "policy": "remove-all-members-of-every-repeated-raw-png-or-decoded-raster-hash",
               "sourceSummarySHA256": expected_summary_sha256, "sourceSamplesJSONLSHA256": summary["samplesJSONLSHA256"],
               "sourceReceipt": {key: summary[key] for key in _PROVENANCE},
               "quarantineSourceSHA256": source.sha256_file(Path(__file__)),
               "rightsStatus": source.RIGHTS_STATUS, "trainingEligibilityEstablished": False,
               "fitOrInferencePerformed": False, "original": original, "clean": clean, "quarantined": removed,
               "cleanManifestSHA256": clean_digest.hexdigest(), "quarantinedJSONLSHA256": quarantine_digest.hexdigest(),
               "copyGroups": groups, "quarantinedSampleIDs": sorted(reasons)}
    with (output / "receipt.json").open("x", encoding="utf-8") as stream:
        json.dump(receipt, stream, sort_keys=True, indent=2)
        stream.write("\n")
    return receipt


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-summary", type=Path, required=True)
    parser.add_argument("--source-samples", type=Path, required=True)
    parser.add_argument("--summary-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True, help="Exclusive new output directory")
    args = parser.parse_args(argv)
    receipt = quarantine_source(args.source_summary, args.source_samples, args.output,
                                expected_summary_sha256=args.summary_sha256)
    print(json.dumps({key: receipt[key]["sampleCount"] for key in ("original", "clean", "quarantined")}, sort_keys=True))


if __name__ == "__main__":
    main()
