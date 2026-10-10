"""Pinned BHMSDS raster intake; no adaptation, split inference, or model work."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import io
import json
from pathlib import Path
import platform
import re
import stat
from zipfile import ZipFile

COMMIT = "07d208e41923b061e338c241e59daacdd2752d53"
ARCHIVE_SHA256 = "5e109303251854908f361e35bf260ebb30248fa9967bd70d2bf3703df11a5274"
SOURCE_URL = "https://github.com/wblachowski/bhmsds"
LABELS = tuple("0123456789") + ("dot", "minus", "plus", "slash", "w", "x", "y", "z")
PER_LABEL = 1500
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_EXPANDED_BYTES = 32 * 1024 * 1024
FLAGS = {"writerID": None, "sessionID": None, "auxiliaryTrainingOnly": True,
         "newWriterEvidence": False, "noObservedTrajectory": True}
_PNG_NAME = re.compile(r"([a-z]+|[0-9])-([0-9]{4})\.png")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe_inventory(archive: ZipFile) -> dict:
    prefix = f"bhmsds-{COMMIT}"
    files, seen, expanded = {}, set(), 0
    members = archive.infolist()
    if len(members) > len(LABELS) * PER_LABEL + 16:
        raise ValueError("ZIP member-count budget exceeded")
    for info in members:
        name = info.orig_filename
        parts = name.rstrip("/").split("/")
        mode = stat.S_IFMT(info.external_attr >> 16)
        if (not name or len(name) > 512 or "\\" in name or "\x00" in name
                or any(p in ("", ".", "..") or ":" in p for p in parts)
                or parts[0] != prefix or mode not in (0, stat.S_IFREG, stat.S_IFDIR)
                or bool(mode == stat.S_IFDIR) != info.is_dir() and mode != 0):
            raise ValueError(f"Unsafe ZIP member: {name!r}")
        if name in seen or info.flag_bits & 1 or info.compress_type not in (0, 8):
            raise ValueError(f"Duplicate, encrypted, or unsupported ZIP member: {name!r}")
        seen.add(name)
        expanded += info.file_size
        if expanded > MAX_EXPANDED_BYTES:
            raise ValueError("ZIP expanded-byte budget exceeded")
        relative = "/".join(parts[1:])
        if info.is_dir():
            if relative not in ("", "assets", "symbols") or info.file_size:
                raise ValueError(f"Unexpected ZIP directory: {name!r}")
            continue
        limit = 2 * 1024 * 1024 if relative == "assets/symbols.gif" else 65536
        if info.file_size > limit:
            raise ValueError(f"ZIP member-byte budget exceeded: {name!r}")
        if relative not in ("README.md", "LICENSE", "assets/symbols.gif") and not relative.startswith("symbols/"):
            raise ValueError(f"Unexpected ZIP file: {name!r}")
        files[relative] = info
    if not {"README.md", "LICENSE"} <= files.keys():
        raise ValueError("Missing archived README or LICENSE")
    return {"files": files, "expandedBytes": expanded, "memberCount": len(members)}


def _raster(data: bytes, foreground: str) -> dict:
    from PIL import Image
    result = {"decodedPixelSHA256": None, "width": None, "height": None, "mode": None,
              "foregroundPixelCount": None, "isUniformRaster": None, "rasterStatus": "invalid-raster"}
    try:
        with Image.open(io.BytesIO(data)) as image:
            result.update(width=image.width, height=image.height, mode=image.mode)
            if image.format != "PNG" or image.size != (28, 28) or image.mode != "L" or getattr(image, "n_frames", 1) != 1:
                raise ValueError("Expected single-frame 28x28 grayscale 8-bit PNG")
            image.load()
            pixels = image.tobytes()
            if len(pixels) != 784:
                raise ValueError("Decoded pixel count mismatch")
            # Hash native pixels with a geometry/mode frame; no conversion or inversion.
            result["decodedPixelSHA256"] = _sha(b"L:28x28\0" + pixels)
            count = sum(v < 255 if foreground == "black" else v > 0 for v in pixels)
            result["foregroundPixelCount"] = count
            result["isUniformRaster"] = min(pixels) == max(pixels)
            result["rasterStatus"] = ("empty-foreground" if count == 0 else
                                      "full-foreground" if count == 784 else "usable")
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
        result["rasterError"] = f"{type(error).__name__}: {str(error)[:180]}"
    return result


def _duplicates(groups: dict[str, list[dict]]) -> list[dict]:
    return [{"sha256": digest, "sampleIDs": [r["sampleID"] for r in rows],
             "sourceLabels": sorted({r["sourceLabel"] for r in rows}),
             "conflictingSourceLabels": len({r["sourceLabel"] for r in rows}) > 1}
            for digest, rows in sorted(groups.items()) if len(rows) > 1]


def audit_archive(path: Path, *, foreground: str, row_sink=None) -> dict:
    """Keep every source row; structural/budget failures abort before raster decoding."""
    if foreground not in ("black", "white"):
        raise ValueError("Foreground polarity must explicitly be black or white")
    path = Path(path)
    if path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValueError("ZIP compressed-byte budget exceeded")
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        if digest.hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Pinned archive SHA-256 mismatch")
        stream.seek(0)
        with ZipFile(stream) as archive:
            inventory = _safe_inventory(archive)
            files, identities, docs = inventory["files"], {}, {}
            for relative, info in files.items():
                if relative.startswith("symbols/"):
                    match = _PNG_NAME.fullmatch(relative.removeprefix("symbols/"))
                    if match is None or match[1] not in LABELS or int(match[2]) >= PER_LABEL:
                        raise ValueError(f"Invalid literal source label/index: {relative}")
                    identity = (match[1], int(match[2]))
                    if identity in identities:
                        raise ValueError(f"Duplicate source label/index identity: {relative}")
                    identities[identity] = info
            expected = {(label, index) for label in LABELS for index in range(PER_LABEL)}
            if set(identities) != expected:
                raise ValueError("Missing/extra source PNG identities; expected 18 labels with contiguous IDs")
            for name in ("README.md", "LICENSE"):
                data = archive.read(files[name])
                docs[name] = {"sha256": _sha(data), "text": data.decode("utf-8")}
            if "licensed under the MIT License" not in docs["README.md"]["text"] or "MIT License" not in docs["LICENSE"]["text"]:
                raise ValueError("Missing archived dataset MIT declaration/notice")
            raw, decoded, statuses, labels = defaultdict(list), defaultdict(list), Counter(), Counter()
            for (label, index), info in sorted(identities.items()):
                data = archive.read(info)
                row = {"sampleID": f"bhmsds:{COMMIT}:{label}:{index}", "sourceLabel": label,
                       "canonicalCodepoint": None, "sourceIndex": index, "sourceCommit": COMMIT,
                       "archiveSHA256": ARCHIVE_SHA256, "pngMember": info.filename,
                       "rawPNGSHA256": _sha(data), "foregroundPolarity": foreground, **FLAGS,
                       **_raster(data, foreground)}
                row["usableRaster"] = row["rasterStatus"] == "usable"
                labels[label] += 1
                statuses[row["rasterStatus"]] += 1
                raw[row["rawPNGSHA256"]].append(row)
                if row["decodedPixelSHA256"] is not None:
                    decoded[row["decodedPixelSHA256"]].append(row)
                if row_sink is not None:
                    row_sink(row)
    import PIL
    return {"schemaVersion": 1, "sourceURL": SOURCE_URL, "sourceCommit": COMMIT,
            "archiveSHA256": ARCHIVE_SHA256, "archiveBytes": path.stat().st_size,
            "importerSHA256": _sha(Path(__file__).read_bytes()), "documents": docs,
            "declaredDatasetLicense": "MIT", "foregroundPolarity": foreground, **FLAGS,
            "sampleCount": sum(labels.values()), "sourceLabelCounts": dict(sorted(labels.items())),
            "rasterStatusCounts": dict(sorted(statuses.items())), "allSourceRowsPreserved": True,
            "sourceVocabularyIssue": {"READMELists": "*", "filenamePrefix": "dot", "mapping": None},
            "rawPNGCopies": _duplicates(raw), "decodedPixelCopies": _duplicates(decoded),
            "expandedBytes": inventory["expandedBytes"], "memberCount": inventory["memberCount"],
            "runtime": {"python": platform.python_version(), "pillow": PIL.__version__}}


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--foreground", choices=("black", "white"), required=True)
    args = parser.parse_args(argv)
    rows = []
    report = audit_archive(args.source_zip, foreground=args.foreground, row_sink=rows.append)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    with (args.output_dir / "source_manifest.jsonl").open("w", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True) + "\n")
    for name, doc in report["documents"].items():
        (args.output_dir / name).write_bytes(doc["text"].encode("utf-8"))
    (args.output_dir / "source_receipt.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"sampleCount": report["sampleCount"], "rasterStatusCounts": report["rasterStatusCounts"]}, sort_keys=True))


if __name__ == "__main__":
    main()
