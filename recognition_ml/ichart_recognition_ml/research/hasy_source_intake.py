"""Pinned HASYv2 source audit only: no extraction, mapping, inference or fitting."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import platform
import re
import tarfile
import warnings

SOURCE_URL = "https://zenodo.org/records/259444"
ARCHIVE_SHA256 = "7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d"
ARCHIVE_MD5 = "fddf23f36e24b5236f6b3a0880c778e3"
EXPECTED_ROWS = 168233
EXPECTED_CLASSES = 369
MAX_ARCHIVE_BYTES = 40 * 1024 * 1024
MAX_MEMBERS = 180000
MAX_EXPANDED_BYTES = 256 * 1024 * 1024
MAX_PNG_BYTES = 64 * 1024
MAX_TEXT_BYTES = 16 * 1024 * 1024
FOLDS = tuple(f"classification-task/fold-{i}" for i in range(1, 11))
DIRECTORIES = {"classification-task", "hasy-data", "verification-task", *FOLDS}
TEXT_FILES = {"hasy-data-labels.csv", "symbols.csv", "README.txt", "hasy_tools.py",
              *(f"{fold}/{part}.csv" for fold in FOLDS for part in ("train", "test")),
              "verification-task/train.csv", "verification-task/test-v1.csv",
              "verification-task/test-v2.csv", "verification-task/test-v3.csv"}
TARGET_LABELS = ("+", "/", r"\#", r"\sharp", r"\o", r"\O", r"\emptyset",
                 r"\varnothing", r"\diameter", r"\triangle", r"\vartriangle", r"\Delta")
FLAGS = {"canonicalCodepoint": None, "writerIdentityReliable": False, "sessionID": None,
         "trajectoryObserved": False, "auxiliaryTrainingOnly": True,
         "newWriterEvidence": False, "productionEligible": False}
_PNG_PATH = re.compile(r"hasy-data/v2-[0-9]+\.png")
_RECORD_HEADER = ["path", "symbol_id", "latex", "user_id"]
_CLASS_HEADER = ["symbol_id", "latex", "training_samples", "test_samples"]
_CONTRACT_NAME = "personal-hasy-source-intake-contract-2026-10-01.md"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _source_identity(path: Path) -> dict:
    size = path.stat().st_size
    if size > MAX_ARCHIVE_BYTES:
        raise ValueError("TAR compressed-byte budget exceeded")
    sha, md5 = hashlib.sha256(), hashlib.md5()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
            md5.update(chunk)
    if sha.hexdigest() != ARCHIVE_SHA256 or md5.hexdigest() != ARCHIVE_MD5:
        raise ValueError("Pinned archive SHA-256/MD5 mismatch")
    return {"sha256": sha.hexdigest(), "md5": md5.hexdigest(), "bytes": size}


def _inventory(path: Path) -> tuple[dict, dict[str, bytes]]:
    names, pngs, directories, texts = set(), set(), set(), {}
    expanded, file_count = 0, 0
    with tarfile.open(path, "r|bz2") as archive:
        for member in archive:
            name = member.name.rstrip("/") if member.isdir() else member.name
            parts = name.split("/")
            if (not name or len(name) > 512 or "\\" in name or "\x00" in name
                    or any(p in ("", ".", "..") or ":" in p for p in parts)
                    or not (member.isfile() or member.isdir()) or member.issparse()):
                raise ValueError(f"Unsafe TAR member: {member.name!r}")
            if name in names:
                raise ValueError(f"Duplicate TAR member: {name!r}")
            names.add(name)
            if len(names) > MAX_MEMBERS:
                raise ValueError("TAR member-count budget exceeded")
            if member.size < 0:
                raise ValueError("Negative TAR member size")
            expanded += member.size
            if expanded > MAX_EXPANDED_BYTES:
                raise ValueError("TAR expanded-byte budget exceeded")
            if member.isdir():
                if name not in DIRECTORIES or member.size:
                    raise ValueError(f"Unexpected TAR directory: {name!r}")
                directories.add(name)
                continue
            file_count += 1
            is_png = _PNG_PATH.fullmatch(name) is not None
            if not is_png and name not in TEXT_FILES:
                raise ValueError(f"Unexpected TAR file: {name!r}")
            limit = MAX_PNG_BYTES if is_png else MAX_TEXT_BYTES
            if member.size > limit:
                raise ValueError(f"TAR member-byte budget exceeded: {name!r}")
            if is_png:
                pngs.add(name)
            else:
                with archive.extractfile(member) as stream:
                    data = stream.read(limit + 1)
                if len(data) != member.size:
                    raise ValueError(f"Truncated TAR member: {name!r}")
                texts[name] = data
    if directories != DIRECTORIES or texts.keys() != TEXT_FILES:
        raise ValueError("Missing/extra observed TAR directories or text files")
    if len(pngs) != EXPECTED_ROWS or file_count != EXPECTED_ROWS + len(TEXT_FILES):
        raise ValueError("Unexpected TAR PNG/file count")
    return {"pngPaths": pngs, "memberCount": len(names), "regularFileCount": file_count,
            "directoryCount": len(directories), "expandedBytes": expanded}, texts


def _csv(data: bytes, header: list[str]) -> list[dict[str, str]]:
    reader = csv.DictReader(io.StringIO(data.decode("utf-8"), newline=""), strict=True)
    if reader.fieldnames != header:
        raise ValueError(f"Unexpected CSV header; expected {header}")
    rows = list(reader)
    if any(set(row) != set(header) or any(value is None for value in row.values()) for row in rows):
        raise ValueError("Corrupted CSV row width")
    return rows


def _number(text: str) -> int:
    if re.fullmatch(r"0|[1-9][0-9]*", text) is None:
        raise ValueError(f"Invalid native count/ID: {text!r}")
    return int(text)


def _records(texts: dict[str, bytes], png_paths: set[str]) -> tuple[dict, list[dict]]:
    classes = {}
    for row in _csv(texts["symbols.csv"], _CLASS_HEADER):
        symbol_id, latex = row["symbol_id"], row["latex"]
        _number(symbol_id)
        if symbol_id in classes or not latex:
            raise ValueError("Duplicate native symbol ID or empty LaTeX label")
        classes[symbol_id] = {"sourceSymbolID": symbol_id, "sourceLabel": latex,
                             "declaredTrainingSamples": _number(row["training_samples"]),
                             "declaredTestSamples": _number(row["test_samples"])}
    if len(classes) != EXPECTED_CLASSES:
        raise ValueError("Unexpected native class count")
    records, counts = {}, Counter()
    for index, row in enumerate(_csv(texts["hasy-data-labels.csv"], _RECORD_HEADER)):
        path, symbol_id = row["path"], row["symbol_id"]
        if path in records or path not in png_paths:
            raise ValueError("Duplicate image-path grain or corrupted PNG/label join")
        if symbol_id not in classes or row["latex"] != classes[symbol_id]["sourceLabel"]:
            raise ValueError("Corrupted native symbol ID/LaTeX join")
        records[path] = {"sampleID": f"hasyv2:{symbol_id}:{path}", "sourceIndex": index,
                         "pngMember": path, "sourceSymbolID": symbol_id,
                         "sourceLabel": row["latex"], "sourceUserID": row["user_id"], **FLAGS}
        counts[symbol_id] += 1
    if len(records) != EXPECTED_ROWS or records.keys() != png_paths:
        raise ValueError("Main record/PNG path coverage mismatch")
    for symbol_id, row in classes.items():
        if counts[symbol_id] != row["declaredTrainingSamples"] + row["declaredTestSamples"]:
            raise ValueError(f"Native class count mismatch: {symbol_id}")
        row.update(sampleCount=counts[symbol_id], targetFamily= row["sourceLabel"] in TARGET_LABELS,
                   canonicalCodepoint=None)
    return records, sorted(classes.values(), key=lambda row: int(row["sourceSymbolID"]))


def _folds(texts: dict[str, bytes], records: dict) -> tuple[list[dict], list[set[str]]]:
    universe, assignments, summaries, tests = set(records), Counter(), [], []
    for fold in FOLDS:
        partitions = []
        for part in ("train", "test"):
            paths = set()
            for row in _csv(texts[f"{fold}/{part}.csv"], _RECORD_HEADER):
                relative = row["path"]
                if not relative.startswith("../../"):
                    raise ValueError("Unexpected fold path prefix")
                path = relative.removeprefix("../../")
                if path in paths or path not in records:
                    raise ValueError("Duplicate fold row or corrupted fold/main path join")
                source = records[path]
                if (row["symbol_id"], row["latex"], row["user_id"]) != (
                        source["sourceSymbolID"], source["sourceLabel"], source["sourceUserID"]):
                    raise ValueError("Corrupted fold/main metadata join")
                paths.add(path)
            partitions.append(paths)
        train, test = partitions
        if train & test or train | test != universe:
            raise ValueError("Fold train/test overlap or full-union coverage mismatch")
        assignments.update(test)
        tests.append(test)
        summaries.append({"fold": fold, "trainCount": len(train), "testCount": len(test),
                          "pathOverlapCount": 0, "fullUnionCoverage": True,
                          "writerIndependent": False})
    if assignments.keys() != universe or set(assignments.values()) != {1}:
        raise ValueError("Test assignment multiplicity across folds must be exactly one")
    return summaries, tests


def _raster(data: bytes) -> dict:
    from PIL import Image
    result = {"decodedPixelSHA256": None, "width": None, "height": None, "mode": None,
              "nativePixelBytes": None, "isUniformRaster": None, "rasterStatus": "invalid-raster"}
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                result.update(width=image.width, height=image.height, mode=image.mode)
                if image.format != "PNG" or image.size != (32, 32) or getattr(image, "n_frames", 1) != 1:
                    raise ValueError("Expected single-frame 32x32 PNG")
                image.load()
                pixels = image.tobytes()
                frame = {"mode": image.mode, "width": image.width, "height": image.height}
                # Palette and transparency affect native color identity without conversion.
                if image.palette is not None:
                    frame["paletteSHA256"] = _sha(image.palette.tobytes())
                if "transparency" in image.info:
                    frame["transparency"] = repr(image.info["transparency"])
                digest = _sha(json.dumps(frame, sort_keys=True, separators=(",", ":")).encode() + b"\0" + pixels)
                extrema = image.getextrema()
                channels = extrema if isinstance(extrema[0], tuple) else (extrema,)
                uniform = all(low == high for low, high in channels)
                result.update(decodedPixelSHA256=digest, nativePixelBytes=len(pixels),
                              isUniformRaster=uniform, rasterStatus="uniform-raster" if uniform else "usable",
                              nativePixelFrame=frame)
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        result["rasterError"] = f"{type(error).__name__}: {str(error)[:180]}"
    return result


def _duplicates(groups: dict, records: dict) -> list[dict]:
    result = []
    for digest, paths in sorted(groups.items()):
        if len(paths) < 2:
            continue
        ids = sorted({records[path]["sourceSymbolID"] for path in paths}, key=int)
        result.append({"sha256": digest, "pngMembers": sorted(paths), "sourceSymbolIDs": ids,
                       "sourceLabels": sorted({records[path]["sourceLabel"] for path in paths}),
                       "conflictingSourceLabels": len(ids) > 1})
    return result


def audit_archive(path: Path, *, row_sink=None, document_sink=None) -> dict:
    """Validate all structure/joins before decoding; keep every source row and native label."""
    path = Path(path)
    identity = _source_identity(path)
    inventory, texts = _inventory(path)
    records, classes = _records(texts, inventory["pngPaths"])
    summaries, tests = _folds(texts, records)
    documents = {name: {"sha256": _sha(data), "bytes": len(data)} for name, data in sorted(texts.items())}
    if document_sink is not None:
        for name, data in sorted(texts.items()):
            document_sink(name, data)
    raw, pixels, statuses, seen = defaultdict(list), defaultdict(list), Counter(), set()
    with tarfile.open(path, "r|bz2") as archive:
        for member in archive:
            if member.name not in records:
                continue
            if member.name in seen or not member.isfile() or member.size > MAX_PNG_BYTES:
                raise ValueError("Source changed during raster pass")
            seen.add(member.name)
            with archive.extractfile(member) as stream:
                data = stream.read(MAX_PNG_BYTES + 1)
            if len(data) != member.size:
                raise ValueError("Truncated PNG member")
            row = {**records[member.name], "archiveSHA256": identity["sha256"],
                   "rawPNGSHA256": _sha(data), **_raster(data)}
            row["usableRaster"] = row["rasterStatus"] == "usable"
            raw[row["rawPNGSHA256"]].append(member.name)
            if row["decodedPixelSHA256"] is not None:
                pixels[row["decodedPixelSHA256"]].append(member.name)
            statuses[row["rasterStatus"]] += 1
            if row_sink is not None:
                row_sink(row)
    if seen != records.keys() or _source_identity(path) != identity:
        raise ValueError("Source changed or PNG rows missing during raster pass")
    pixel_duplicates = _duplicates(pixels, records)
    for summary, test in zip(summaries, tests):
        crossing = []
        for group in pixel_duplicates:
            group_paths = set(group["pngMembers"])
            in_test = group_paths & test
            if in_test and group_paths - test:
                crossing.append({"sha256": group["sha256"], "testPNGs": sorted(in_test),
                                 "trainPNGs": sorted(group_paths - test),
                                 "conflictingSourceLabels": group["conflictingSourceLabels"]})
        summary["crossingNativePixelDuplicateGroups"] = crossing
        summary["crossingNativePixelDuplicateGroupCount"] = len(crossing)
    import PIL
    return {"schemaVersion": 1, "sourceURL": SOURCE_URL, "archive": identity,
            **{key: value for key, value in inventory.items() if key != "pngPaths"}, **FLAGS,
            "sampleCount": len(records), "classCount": len(classes), "classes": classes,
            "targetFamilies": {label: [row for row in classes if row["sourceLabel"] == label] for label in TARGET_LABELS},
            "rasterStatusCounts": dict(sorted(statuses.items())), "allSourceRowsPreserved": True,
            "classificationFolds": summaries, "testAssignmentMultiplicity": {"1": len(records)},
            "rawPNGCopies": _duplicates(raw, records), "decodedPixelCopies": pixel_duplicates,
            "documents": documents, "verificationTaskAudited": "preserved-and-hashed-only",
            "sourceVocabularyIssue": {"READMEImageClaim": 168236, "observedImages": len(records)},
            "declaredDatasetLicense": "ODbL", "individualContentGrantVerified": False,
            "shippingOrModelLicenseCleared": False, "licenseEvidenceURL": "https://arxiv.org/pdf/1701.08380",
            "runtime": {"python": platform.python_version(), "pillow": PIL.__version__}}


def _input_snapshots() -> dict[Path, bytes]:
    source = Path(__file__).resolve()
    root = source.parents[3]
    return {path: path.read_bytes() for path in (source, root / "recognition_ml/tests/test_hasy_source_intake.py",
                                                root / "docs" / _CONTRACT_NAME)}


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
    snapshots = _input_snapshots()
    output = _fresh_output(args.output_dir)
    artifacts = {}

    def preserve(relative: str, data: bytes) -> None:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        artifacts[relative] = {"sha256": _sha(data), "bytes": len(data)}

    for path, data in snapshots.items():
        preserve(f"implementation/{path.name}", data)
    manifest = output / "source_manifest.jsonl"
    manifest_hash, manifest_bytes = hashlib.sha256(), 0
    with manifest.open("xb") as stream:
        def row_sink(row):
            nonlocal manifest_bytes
            data = (json.dumps(row, sort_keys=True) + "\n").encode()
            stream.write(data)
            manifest_hash.update(data)
            manifest_bytes += len(data)
        report = audit_archive(args.source_tar, row_sink=row_sink,
                               document_sink=lambda name, data: preserve(f"source_metadata/{name}", data))
    artifacts[manifest.name] = {"sha256": manifest_hash.hexdigest(), "bytes": manifest_bytes}
    for key, name in (("classes", "source_classes.json"), ("classificationFolds", "classification_folds.json"),
                      ("rawPNGCopies", "raw_duplicates.json"), ("decodedPixelCopies", "pixel_duplicates.json")):
        value = report.pop(key)
        preserve(name, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())
    report["inputBindings"] = {str(path): _sha(data) for path, data in snapshots.items()}
    report["artifacts"] = artifacts
    # A receipt is published only after source, implementation and every artifact agree.
    if _source_identity(args.source_tar) != report["archive"]:
        raise ValueError("Source identity changed before publication")
    if any(path.read_bytes() != data for path, data in snapshots.items()):
        raise ValueError("Implementation/test/contract changed before publication")
    for relative, expected in artifacts.items():
        target = output / relative
        if target.stat().st_size != expected["bytes"] or _sha(target.read_bytes()) != expected["sha256"]:
            raise ValueError(f"Artifact changed before publication: {relative}")
    with (output / "source_receipt.json").open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"sampleCount": report["sampleCount"], "classCount": report["classCount"],
                      "rasterStatusCounts": report["rasterStatusCounts"]}, sort_keys=True))


if __name__ == "__main__":
    main()
