"""Fixed native-only HASY source preparation; no model or query data access."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

import numpy as np
from PIL import Image

from . import hasy_source_intake as intake_tools
from .personal_symbol_data import normalize_bitmap

ARCHIVE_SHA256 = "7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d"
INTAKE_SHA256 = "ab9293fb5f81f9dd39ee9ade02f01ecb2bd203d783686f6e28dedab977f220d2"
MANIFEST_SHA256 = "4d604325cae34dc7d08ebb533d30a5469d60a9a50dcc8db135c6287ffab95c3b"
PROTOCOL_SHA256 = "54f426735c0f364bb466329298c5649f6b1f8928aab1be19d45bba9b48e509fb"
CLASS_COUNT, BASE_EXPOSURES, EXTRA_CLASSES = 369, 86, 10
SALT = b"native-shape-transfer-v1"
RASTER_SHAPE = (1, 96, 256)
RASTER_BYTES = 96 * 256
SOURCE_KIND = "hasy369-native-shapes"
ARTIFACT_NAMES = {"source_ledger.jsonl", "selection.jsonl", "rasters.bin", "targets.bin"}


def _canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def _hash(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _code_paths() -> dict[str, Path]:
    source = Path(__file__).resolve()
    return {path.name: path for path in (source, source.parent / "personal_symbol_data.py",
            source.parent / "hasy_source_intake.py", source.parents[1] / "features.py",
            source.parents[2] / "tests/test_hasy_native_training_source.py")}


def code_identity() -> dict[str, str]:
    return {name: _hash(path) for name, path in _code_paths().items()}


def _artifact(root: Path, relative: str) -> Path:
    parts = PurePosixPath(relative).parts
    if (not parts or "\\" in relative or any(part in (".", "..") or ":" in part for part in parts)
            or PurePosixPath(relative).is_absolute() or str(PurePosixPath(relative)) != relative):
        raise ValueError("Unsafe evidence artifact path")
    path = root / relative
    if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Evidence artifact escaped its directory")
    return path


def _verify_artifacts(root: Path, artifacts: dict) -> None:
    for name, expected in artifacts.items():
        path = _artifact(root, name)
        if path.stat().st_size != expected["bytes"] or _hash(path) != expected["sha256"]:
            raise ValueError(f"Changed evidence artifact: {name}")


def _pins(archive: Path, intake: Path, protocol: Path) -> dict:
    if archive.stat().st_size > intake_tools.MAX_ARCHIVE_BYTES or _hash(archive) != ARCHIVE_SHA256:
        raise ValueError("Changed pinned HASY archive")
    if _hash(protocol) != PROTOCOL_SHA256:
        raise ValueError("Changed fixed protocol")
    receipt_path = intake / "source_receipt.json"
    if _hash(receipt_path) != INTAKE_SHA256:
        raise ValueError("Changed pinned intake receipt")
    receipt = json.loads(receipt_path.read_text())
    if receipt["archive"]["sha256"] != ARCHIVE_SHA256 or receipt["classCount"] != CLASS_COUNT:
        raise ValueError("Intake archive/class identity mismatch")
    if receipt["artifacts"]["source_manifest.jsonl"]["sha256"] != MANIFEST_SHA256:
        raise ValueError("Pinned manifest identity mismatch")
    _verify_artifacts(intake, receipt["artifacts"])
    return {"archiveSHA256": ARCHIVE_SHA256, "intakeReceiptSHA256": INTAKE_SHA256,
            "manifestSHA256": MANIFEST_SHA256, "protocolSHA256": PROTOCOL_SHA256}


def _source_rows(intake: Path) -> tuple[list[dict], list[str]]:
    classes = json.loads((intake / "source_classes.json").read_text())
    native_ids = [row["sourceSymbolID"] for row in classes]
    if (len(native_ids) != CLASS_COUNT or len(set(native_ids)) != CLASS_COUNT
            or any(not value.isdecimal() or str(int(value)) != value for value in native_ids)):
        raise ValueError("Invalid full native vocabulary")
    native_ids.sort(key=int)
    labels = {row["sourceSymbolID"]: row["sourceLabel"] for row in classes}
    rows, identities, paths, counts = [], set(), set(), Counter()
    with (intake / "source_manifest.jsonl").open() as stream:
        for line in stream:
            row = json.loads(line)
            if (row["sampleID"] in identities or row["pngMember"] in paths
                    or row["sourceSymbolID"] not in labels or labels[row["sourceSymbolID"]] != row["sourceLabel"]
                    or intake_tools._PNG_PATH.fullmatch(row["pngMember"]) is None
                    or any(row.get(key) != value for key, value in intake_tools.FLAGS.items())):
                raise ValueError("Invalid native source grain/metadata/provenance")
            identities.add(row["sampleID"])
            paths.add(row["pngMember"])
            counts[row["sourceSymbolID"]] += 1
            rows.append({"sampleID": row["sampleID"], "pngMember": row["pngMember"],
                         "sourceSymbolID": row["sourceSymbolID"], "sourceLabel": row["sourceLabel"],
                         "sourceUserID": row["sourceUserID"], "rawPNGSHA256": row["rawPNGSHA256"],
                         "nativePixelSHA256": row["decodedPixelSHA256"],
                         "adaptedRasterSHA256": None, "exclusions": ([] if row["usableRaster"] else ["native-unusable-raster"]),
                         "representativeSampleID": None, **intake_tools.FLAGS})
    if len(rows) != intake_tools.EXPECTED_ROWS or any(counts[row["sourceSymbolID"]] != row["sampleCount"] for row in classes):
        raise ValueError("Incomplete native source counts")
    return rows, native_ids


def _quarantine(rows: list[dict], hash_key: str, stage: str) -> None:
    groups = defaultdict(list)
    for row in rows:
        if row[hash_key] is not None:
            groups[row[hash_key]].append(row)
    for group in groups.values():
        if len({row["sourceSymbolID"] for row in group}) > 1:
            for row in group:
                row["exclusions"].append(f"{stage}-conflicting-pixels")
        else:
            representative = min(row["sampleID"] for row in group)
            for row in group:
                if row["sampleID"] != representative:
                    row["exclusions"].append(f"{stage}-same-label-copy")
                    row["representativeSampleID"] = representative


def _adapted_stream(archive: Path, rows: list[dict]):
    selected = {row["pngMember"]: row for row in rows}
    seen = set()
    # Pinned source bytes plus bounded observed inventory precede these passes.
    with tarfile.open(archive, "r|bz2") as source:
        for member in source:
            if member.name not in selected:
                continue
            if member.name in seen or not member.isfile() or member.size > intake_tools.MAX_PNG_BYTES:
                raise ValueError("Invalid selected TAR image")
            seen.add(member.name)
            with source.extractfile(member) as stream:
                data = stream.read(intake_tools.MAX_PNG_BYTES + 1)
            row = selected[member.name]
            native = intake_tools._raster(data)
            if (len(data) != member.size or hashlib.sha256(data).hexdigest() != row["rawPNGSHA256"]
                    or native["decodedPixelSHA256"] != row["nativePixelSHA256"] or native["rasterStatus"] != "usable"):
                raise ValueError("Archived native raster/intake join mismatch")
            with Image.open(io.BytesIO(data)) as image:
                pixels = normalize_bitmap(image)
            if len(pixels) != RASTER_BYTES:
                raise ValueError("Unexpected normalized raster shape")
            yield row, pixels
    if seen != selected.keys():
        raise ValueError("Missing selected source images")


def _rank(identity: str) -> str:
    return hashlib.sha256(SALT + b"\0" + identity.encode()).hexdigest()


def _selection(rows: list[dict], native_ids: list[str]) -> tuple[list[dict], list[str]]:
    extra = sorted(native_ids, key=lambda identity: (_rank(identity), identity))[:EXTRA_CLASSES]
    by_class = defaultdict(list)
    for row in rows:
        if not row["exclusions"]:
            by_class[row["sourceSymbolID"]].append(row)
    selection = []
    for target, native_id in enumerate(native_ids):
        candidates = sorted(by_class[native_id], key=lambda row: (_rank(row["sampleID"]), row["sampleID"]))
        if not candidates:
            raise ValueError(f"Native class empty after fixed exclusions: {native_id}")
        for exposure in range(BASE_EXPOSURES + int(native_id in extra)):
            row = candidates[exposure % len(candidates)]
            selection.append({key: row[key] for key in ("sampleID", "pngMember", "sourceSymbolID", "sourceLabel",
                                                       "nativePixelSHA256", "adaptedRasterSHA256")}
                             | {"exposureIndex": len(selection), "targetIndex": target,
                                "sourceRank": exposure % len(candidates), "cycleIndex": exposure // len(candidates)})
    return selection, extra


def prepare(archive: Path, intake: Path, protocol: Path, output: Path) -> dict:
    archive, intake, protocol = (Path(path).resolve() for path in (archive, intake, protocol))
    pins, bindings = _pins(archive, intake, protocol), code_identity()
    inventory, _ = intake_tools._inventory(archive)
    rows, native_ids = _source_rows(intake)
    if {row["pngMember"] for row in rows} != inventory["pngPaths"]:
        raise ValueError("Intake/archive path coverage mismatch")
    _quarantine(rows, "nativePixelSHA256", "native")
    native_clean = [row for row in rows if not row["exclusions"]]
    for row, pixels in _adapted_stream(archive, native_clean):
        row["adaptedRasterSHA256"] = hashlib.sha256(pixels).hexdigest()
    _quarantine(native_clean, "adaptedRasterSHA256", "adapted")
    selection, extra = _selection(rows, native_ids)
    count = CLASS_COUNT * BASE_EXPOSURES + EXTRA_CLASSES
    if len(selection) != count:
        raise ValueError("Fixed exposure count mismatch")
    output = intake_tools._fresh_output(Path(output))
    for name, values in (("source_ledger.jsonl", rows), ("selection.jsonl", selection)):
        with (output / name).open("xb") as stream:
            for row in values:
                stream.write(_canonical(row) + b"\n")
    positions = defaultdict(list)
    for item in selection:
        positions[item["sampleID"]].append(item["exposureIndex"])
    selected_rows = [row for row in rows if row["sampleID"] in positions]
    with (output / "rasters.bin").open("xb") as stream:
        stream.truncate(count * RASTER_BYTES)
        for row, pixels in _adapted_stream(archive, selected_rows):
            if hashlib.sha256(pixels).hexdigest() != row["adaptedRasterSHA256"]:
                raise ValueError("Changed adaptation between source passes")
            for index in positions[row["sampleID"]]:
                stream.seek(index * RASTER_BYTES)
                stream.write(pixels)
    targets = np.asarray([row["targetIndex"] for row in selection], dtype="<i8")
    with (output / "targets.bin").open("xb") as stream:
        stream.write(targets.tobytes())
    implementation = {}
    for name, path in _code_paths().items():
        relative = f"implementation/{name}"
        (output / "implementation").mkdir(exist_ok=True)
        (output / relative).write_bytes(path.read_bytes())
        implementation[relative] = {"bytes": (output / relative).stat().st_size, "sha256": _hash(output / relative)}
    relative = "implementation/protocol.md"
    (output / relative).write_bytes(protocol.read_bytes())
    implementation[relative] = {"bytes": (output / relative).stat().st_size, "sha256": _hash(output / relative)}
    artifacts = {name: {"bytes": (output / name).stat().st_size, "sha256": _hash(output / name)} for name in sorted(ARTIFACT_NAMES)} | implementation
    selected_hashes = sorted({row["adaptedRasterSHA256"] for row in selection})
    receipt = {"schemaVersion": 1, "sourceKind": SOURCE_KIND, "pins": pins, "codeBindings": bindings,
               "inputs": {"archive": str(archive), "intake": str(intake), "protocol": str(protocol)},
               "nativeClassIDs": native_ids, "extraNativeClassIDs": extra,
               "classCounts": dict(Counter(row["sourceSymbolID"] for row in selection)),
               "exposureCount": count, "distinctSourceCount": len(positions), "repeatedExposureCount": count - len(positions),
               "sourceCounts": {"originalRows": len(rows), "nativeCleanRows": len(native_clean),
                                "adaptedCleanRows": sum(not row["exclusions"] for row in rows),
                                "excludedRows": sum(bool(row["exclusions"]) for row in rows)},
               "exclusionCounts": dict(Counter(reason for row in rows for reason in row["exclusions"])),
               "rasterShape": [count, *RASTER_SHAPE], "rasterDtype": "uint8", "targetDtype": "<i8",
               "selectedAdaptedRasterHashesSHA256": hashlib.sha256(_canonical(selected_hashes)).hexdigest(),
               "artifacts": artifacts, "labelMapping": None, "declaredDatasetLicense": "ODbL",
               "shippingOrModelLicenseCleared": False, "derivedWeightDistributionCleared": False,
               **intake_tools.FLAGS}
    if code_identity() != bindings or _pins(archive, intake, protocol) != pins:
        raise ValueError("Changed inputs/code before source publication")
    _verify_artifacts(output, artifacts)
    with (output / "source_receipt.json").open("xb") as stream:
        stream.write(_canonical(receipt) + b"\n")
    return receipt


def load_prepared(directory: Path, expected_receipt_sha256: str):
    directory = Path(directory).resolve()
    receipt_path = directory / "source_receipt.json"
    if _hash(receipt_path) != expected_receipt_sha256:
        raise ValueError("Prepared receipt SHA256 mismatch")
    receipt = json.loads(receipt_path.read_text())
    count = CLASS_COUNT * BASE_EXPOSURES + EXTRA_CLASSES
    native_ids = receipt["nativeClassIDs"]
    if (receipt["schemaVersion"] != 1 or receipt["sourceKind"] != SOURCE_KIND or receipt["exposureCount"] != count
            or receipt["rasterShape"] != [count, *RASTER_SHAPE] or receipt["rasterDtype"] != "uint8"
            or receipt["targetDtype"] != "<i8" or receipt["labelMapping"] is not None
            or receipt.get("declaredDatasetLicense") != "ODbL"
            or receipt.get("shippingOrModelLicenseCleared") is not False
            or receipt.get("derivedWeightDistributionCleared") is not False
            or len(native_ids) != CLASS_COUNT or len(set(native_ids)) != CLASS_COUNT
            or native_ids != sorted(native_ids, key=int)
            or any(receipt.get(key) != value for key, value in intake_tools.FLAGS.items())):
        raise ValueError("Prepared native source schema mismatch")
    if receipt["codeBindings"] != code_identity():
        raise ValueError("Changed source adapter/normalizer code")
    inputs = receipt["inputs"]
    if _pins(Path(inputs["archive"]), Path(inputs["intake"]), Path(inputs["protocol"])) != receipt["pins"]:
        raise ValueError("Changed preparation inputs")
    if not ARTIFACT_NAMES.issubset(receipt["artifacts"]):
        raise ValueError("Missing prepared source artifacts")
    _verify_artifacts(directory, receipt["artifacts"])
    if (receipt["artifacts"]["rasters.bin"]["bytes"] != count * RASTER_BYTES
            or receipt["artifacts"]["targets.bin"]["bytes"] != count * 8):
        raise ValueError("Prepared raster/target size mismatch")
    images = np.memmap(directory / "rasters.bin", dtype=np.uint8, mode="r", shape=(count, *RASTER_SHAPE))
    targets = np.memmap(directory / "targets.bin", dtype="<i8", mode="r", shape=(count,))
    selected_hashes, identities, classes, seen = set(), set(), Counter(), 0
    with (directory / "selection.jsonl").open() as stream:
        for index, line in enumerate(stream):
            row = json.loads(line)
            target = row["targetIndex"]
            if (index >= count or row["exposureIndex"] != index or not 0 <= target < CLASS_COUNT
                    or row["sourceSymbolID"] != native_ids[target] or int(targets[index]) != target
                    or hashlib.sha256(images[index].tobytes()).hexdigest() != row["adaptedRasterSHA256"]):
                raise ValueError("Prepared selection/raster/target join mismatch")
            selected_hashes.add(row["adaptedRasterSHA256"])
            identities.add(row["sampleID"])
            classes[row["sourceSymbolID"]] += 1
            seen += 1
    extra = sorted(native_ids, key=lambda identity: (_rank(identity), identity))[:EXTRA_CLASSES]
    expected_counts = {native_id: BASE_EXPOSURES + int(native_id in extra) for native_id in native_ids}
    selected_hashes = sorted(selected_hashes)
    selected_digest = hashlib.sha256(_canonical(selected_hashes)).hexdigest()
    if (seen != count or dict(classes) != expected_counts or receipt["classCounts"] != expected_counts
            or receipt["extraNativeClassIDs"] != extra or receipt["distinctSourceCount"] != len(identities)
            or receipt["repeatedExposureCount"] != count - len(identities)
            or selected_digest != receipt["selectedAdaptedRasterHashesSHA256"]):
        raise ValueError("Prepared fixed selection evidence mismatch")
    return images, targets, {"receipt": receipt, "receiptSHA256": expected_receipt_sha256,
                            "nativeClassIDs": native_ids, "selectedAdaptedRasterHashes": selected_hashes,
                            "selectedAdaptedRasterHashesSHA256": selected_digest}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source-tar", "intake-dir", "protocol", "output-dir"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    args = parser.parse_args(argv)
    receipt = prepare(args.source_tar, args.intake_dir, args.protocol, args.output_dir)
    print(json.dumps({key: receipt[key] for key in ("exposureCount", "distinctSourceCount", "repeatedExposureCount")}, sort_keys=True))


if __name__ == "__main__":
    main()
