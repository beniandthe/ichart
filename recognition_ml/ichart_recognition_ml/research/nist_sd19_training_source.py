"""Bounded raster-only NIST source preparation for offline recognition research.

Selection uses recorded training writers and exact 62 ASCII labels before any
image decoding. Raster bbox geometry is a transfer domain, not native stroke parity.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile

from . import nist_sd19 as source

LABELS = tuple("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
TRANSFORM_VERSION = "nist-sd19-raster-bbox-256x96-p8-nearest-v1"
SELECTION_VERSION = "nist-sd19-writer-label-salted-sha256-v1"
PROTOCOL_SHA256 = "a03afefbe741eed7bb8e0eea4ad96bd8bcfe4f72e159b7b9e12bcdd3ea8d341d"
WIDTH, HEIGHT, CONTENT_WIDTH, CONTENT_HEIGHT = 256, 96, 240, 80
_SHA = re.compile(r"[0-9a-f]{64}")


def _hash(value) -> bool:
    return isinstance(value, str) and _SHA.fullmatch(value) is not None


def _rank(salt: str, kind: str, identity: str) -> str:
    return hashlib.sha256(f"{SELECTION_VERSION}\0{salt}\0{kind}\0{identity}".encode("utf-8")).hexdigest()


def _metadata(row: dict, writer_roles: dict) -> None:
    field, index = source.parse_png_path(row["png_member"])
    label = row["label"]
    if (label not in LABELS or row["label_byte_hex"] != f"{ord(label):02x}"
            or re.fullmatch(r"[0-9a-fA-F]{2}", row["label_raw_token"]) is None
            or int(row["label_raw_token"], 16) != ord(label)):
        raise ValueError("Expected exact documented 62 ASCII labels")
    if (row["sample_id"] != f"{field.key}/{index:05d}" or row["writer_id"] != field.writer_id
            or row["partition"] != field.partition or row["template_id"] != field.template_id
            or row["form_id"] != field.form_id or row["field_id"] != field.field_id or row["image_index"] != index
            or row["split"] not in source.ROLES or row["cls_label_line"] != index + 2
            or not all(_hash(row.get(key)) for key in ("png_sha256", "decoded_raster_sha256", "cls_sha256"))):
        raise ValueError("Invalid frozen source row metadata")
    if writer_roles.setdefault(row["writer_id"], row["split"]) != row["split"]:
        raise ValueError("Source writer crosses roles")
    if (field.partition == "hsf_4" and row["split"] != "reserved") or (row["split"] == "train" and field.partition not in source.TRAIN_PARTITIONS):
        raise ValueError("Reserved/ineligible partition used as training source")


def select_training_rows(manifest: Path, *, expected_sha256: str, expected_counts: dict,
                         salt: str, writers_per_label: int = 512) -> tuple[list[dict], dict]:
    """One lowest sample hash per (writer,label), then lowest writer hashes/class."""
    if not _hash(expected_sha256) or not salt or type(writers_per_label) is not int or writers_per_label < 1:
        raise ValueError("Invalid manifest pin/selection salt/writer budget")
    digest, seen, roles, best = hashlib.sha256(), set(), {}, {}
    label_counts, role_counts, total = Counter(), Counter(), 0
    with Path(manifest).open("rb") as stream:
        for line in stream:
            digest.update(line)
            if not line.endswith(b"\n"):
                raise ValueError("Source manifest row lacks LF termination")
            row = json.loads(line)
            _metadata(row, roles)
            identity = row["sample_id"]
            if identity in seen:
                raise ValueError("Duplicate source sample ID")
            seen.add(identity)
            total += 1
            label_counts[row["label_byte_hex"]] += 1
            role_counts[row["split"]] += 1
            if row["split"] != "train":
                continue
            key = (row["writer_id"], row["label"])
            rank = (_rank(salt, "sample", identity), identity)
            if key not in best or rank < best[key][0]:
                best[key] = (rank, row)
    if digest.hexdigest() != expected_sha256:
        raise ValueError("Clean source manifest SHA256 mismatch")
    if (total != expected_counts["sampleCount"] or label_counts != expected_counts["classCountsByByteHex"]
            or role_counts != expected_counts["roleCounts"]):
        raise ValueError("Clean source manifest count/role/class mismatch")
    by_label = defaultdict(list)
    for (writer, label), (sample_rank, row) in best.items():
        by_label[label].append((_rank(salt, "writer-label", f"{writer}\0{label}"), writer, sample_rank, row))
    selected, available = [], {}
    for label in LABELS:
        candidates = sorted(by_label[label])
        available[label] = len(candidates)
        if len(candidates) < writers_per_label:
            raise ValueError(f"Insufficient distinct training writers for {label!r}: {len(candidates)} < {writers_per_label}")
        selected.extend(candidate[-1] for candidate in candidates[:writers_per_label])
    return selected, {"originalSampleCount": total, "originalRoleCounts": dict(role_counts),
                      "availableTrainingWriterCountsByLabel": available}


def adapt_raster(pixels: bytes) -> bytes:
    """Foreground-255 source bbox, nearest fit to 240x80, centered on 256x96."""
    if len(pixels) != 128 * 128 or pixels.translate(None, b"\x00\xff"):
        raise ValueError("Expected original binary 128x128 foreground raster")
    from PIL import Image
    image = Image.frombytes("L", (128, 128), pixels)
    bounds = image.getbbox()
    if bounds is None:
        raise ValueError("Empty source foreground; no sample is silently dropped")
    crop = image.crop(bounds)
    scale = min(CONTENT_WIDTH / crop.width, CONTENT_HEIGHT / crop.height)
    size = (min(CONTENT_WIDTH, max(1, round(crop.width * scale))),
            min(CONTENT_HEIGHT, max(1, round(crop.height * scale))))
    resized = crop.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("L", (WIDTH, HEIGHT), 0)
    canvas.paste(resized, ((WIDTH - size[0]) // 2, (HEIGHT - size[1]) // 2))
    return canvas.tobytes()


def prepare_training_source(manifest: Path, quarantine_receipt: Path, archive: Path, output: Path, *,
                            expected_manifest_sha256: str, expected_receipt_sha256: str,
                            expected_archive_sha256: str, salt: str, writers_per_label: int = 512) -> dict:
    manifest, quarantine_receipt, archive, output = map(Path, (manifest, quarantine_receipt, archive, output))
    if output.exists():
        raise FileExistsError(f"Exclusive output directory already exists: {output}")
    if not _hash(expected_receipt_sha256) or source.sha256_file(quarantine_receipt) != expected_receipt_sha256:
        raise ValueError("Quarantine receipt SHA256 mismatch")
    receipt = json.loads(quarantine_receipt.read_bytes())
    inherited = receipt["sourceReceipt"]
    if (receipt["cleanManifestSHA256"] != expected_manifest_sha256 or inherited["sourceID"] != source.SOURCE_ID
            or inherited["rightsStatus"] != source.RIGHTS_STATUS or inherited["trainingEligibilityEstablished"] is not False
            or inherited["inputKind"] != "raster-only" or inherited["observedTrajectories"] is not False
            or inherited["sourceArchiveSHA256"]["pngZIP"] != expected_archive_sha256
            or receipt["policy"] != "remove-all-members-of-every-repeated-raw-png-or-decoded-raster-hash"):
        raise ValueError("Invalid inherited clean source/rights/archive receipt")
    selected, source_counts = select_training_rows(manifest, expected_sha256=expected_manifest_sha256,
        expected_counts=receipt["clean"], salt=salt, writers_per_label=writers_per_label)
    if not _hash(expected_archive_sha256) or source.sha256_file(archive) != expected_archive_sha256:
        raise ValueError("Source PNG archive SHA256 mismatch")
    output.mkdir(mode=0o700)
    selection_digest, raster_digest = hashlib.sha256(), hashlib.sha256()
    with ZipFile(archive) as images, (output / "selection.jsonl").open("xb") as rows_stream, \
            (output / "rasters.bin").open("xb") as raster_stream:
        for index, row in enumerate(selected):
            data = images.read(row["png_member"])
            if hashlib.sha256(data).hexdigest() != row["png_sha256"]:
                raise ValueError("Selected raw PNG SHA256 mismatch")
            pixels = source.decode_png(data, foreground="black")
            if hashlib.sha256(pixels).hexdigest() != row["decoded_raster_sha256"]:
                raise ValueError("Selected decoded source raster SHA256 mismatch")
            adapted = adapt_raster(pixels)
            raster_stream.write(adapted)
            raster_digest.update(adapted)
            record = {"selectionIndex": index, "sourceRow": row, "adaptedRasterSHA256": hashlib.sha256(adapted).hexdigest(),
                      "rasterByteOffset": index * WIDTH * HEIGHT, "rasterByteLength": WIDTH * HEIGHT}
            line = (json.dumps(record, sort_keys=True) + "\n").encode("utf-8")
            rows_stream.write(line)
            selection_digest.update(line)
    import PIL
    report = {"formatVersion": 1, "adapterSourceSHA256": source.sha256_file(Path(__file__)),
        "sourceManifestSHA256": expected_manifest_sha256, "sourceQuarantineReceiptSHA256": expected_receipt_sha256,
        "sourceArchiveSHA256": expected_archive_sha256, "inheritedSourceReceipt": inherited,
        "rightsStatus": source.RIGHTS_STATUS, "trainingEligibilityEstablished": False,
        "researchPurposeSupported": True, "productionEligible": False, "fitOrInferencePerformed": False,
        "researchScope": "NIST stated OCR/training research purpose; bounded offline research only",
        "protocolSHA256": PROTOCOL_SHA256, "selectionVersion": SELECTION_VERSION,
        "selectionSalt": salt, "writersPerLabel": writers_per_label,
        "sampleCount": len(selected), "labels": list(LABELS), "sourceCounts": source_counts,
        "selectedWriterCount": len({r["writer_id"] for r in selected}), "selectedRoleCounts": {"train": len(selected)},
        "selectedClassCounts": dict(Counter(r["label"] for r in selected)),
        "transform": {"version": TRANSFORM_VERSION, "sourceSize": [128, 128], "outputSize": [WIDTH, HEIGHT],
            "contentLimit": [CONTENT_WIDTH, CONTENT_HEIGHT], "foreground": 255, "background": 0,
            "resampling": "Pillow nearest-neighbor", "pillowVersion": PIL.__version__, "inputKind": "raster-only",
            "observedTrajectories": False, "domainShift": "Raster bounding-box geometry differs from native stroke centerline geometry; no geometric parity claim"},
        "selectionJSONLSHA256": selection_digest.hexdigest(), "rastersBinSHA256": raster_digest.hexdigest()}
    with (output / "receipt.json").open("x", encoding="utf-8") as stream:
        json.dump(report, stream, sort_keys=True, indent=2)
        stream.write("\n")
    return report


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("manifest", "quarantine-receipt", "archive", "output"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    for name in ("manifest-sha256", "receipt-sha256", "archive-sha256", "salt"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--writers-per-label", type=int, default=512)
    args = parser.parse_args(argv)
    report = prepare_training_source(args.manifest, args.quarantine_receipt, args.archive, args.output,
        expected_manifest_sha256=args.manifest_sha256, expected_receipt_sha256=args.receipt_sha256,
        expected_archive_sha256=args.archive_sha256, salt=args.salt, writers_per_label=args.writers_per_label)
    print(json.dumps({key: report[key] for key in ("sampleCount", "selectedWriterCount", "productionEligible")}, sort_keys=True))


if __name__ == "__main__":
    main()
