"""Offline NIST SD19 source audit: checked CLS labels joined to raster images.

Writer numbers are recorded source groups, not proof of distinct physical people.
No fitting, label aliases, prompt substitution, or inferred trajectories occur here.
Rights remain unresolved even when the source passes every integrity check.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
import hashlib
import io
import json
from pathlib import Path
import platform
import re
from typing import Callable, Iterable, Mapping
from zipfile import ZipFile, ZipInfo


SOURCE_ID = "nist-sd19-second-edition-png-with-first-edition-checked-cls"
RIGHTS_STATUS = "unresolved-no-training-or-shipping-eligibility"
TRAIN_PARTITIONS = frozenset(f"hsf_{i}" for i in (0, 1, 2, 3, 6, 7))
ROLES = ("train", "dev", "reserved", "withheld", "unprocessed")
_INVERT_BINARY = bytes.maketrans(b"\x00\xff", b"\xff\x00")
_FIELD = r"by_write/(?P<partition>hsf_[0-8])/f(?P<writer>[0-9]{4})_(?P<template>[0-9]{2})/"
_CLS = re.compile(_FIELD + r"(?P<kind>[dulc])(?P=writer)_(?P=template)\.cls")
_PNG = re.compile(_FIELD + r"(?P<kind>[dulc])(?P=writer)_(?P=template)/"
                  r"(?P=kind)(?P=writer)_(?P=template)_(?P<index>[0-9]{5})\.png")


@dataclass(frozen=True, order=True, slots=True)
class FieldIdentity:
    partition: str
    writer_id: str
    template_id: str
    kind: str

    @property
    def form_id(self) -> str:
        return f"f{self.writer_id}_{self.template_id}"

    @property
    def field_id(self) -> str:
        return f"{self.kind}{self.writer_id}_{self.template_id}"

    @property
    def key(self) -> str:
        return f"{self.partition}/{self.form_id}/{self.field_id}"


@dataclass(frozen=True, slots=True)
class ClassLabels:
    field: FieldIdentity
    member: str
    sha256: str
    raw_tokens: tuple[str, ...]
    values: tuple[int, ...]


@dataclass(frozen=True, slots=True)
class RasterSample:
    sample_id: str
    writer_id: str
    partition: str
    template_id: str
    form_id: str
    field_id: str
    image_index: int
    split: str
    label: str
    label_byte_hex: str
    label_raw_token: str
    png_member: str
    png_sha256: str
    cls_member: str
    cls_sha256: str
    cls_label_line: int
    decoded_raster_sha256: str | None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _relative_member(name: str) -> str | None:
    parts = name.rstrip("/").split("/")
    if not name or name.startswith("/") or "\\" in name or any(p in ("", ".", "..") for p in parts):
        raise ValueError(f"Unsafe ZIP member path: {name!r}")
    positions = [i for i, part in enumerate(parts) if part == "by_write"]
    if not positions:
        return None
    if len(positions) != 1:
        raise ValueError(f"Ambiguous by_write wrapper: {name!r}")
    return "/".join(parts[positions[0]:])


def _identity(match: re.Match[str]) -> FieldIdentity:
    return FieldIdentity(match["partition"], match["writer"], match["template"], match["kind"])


def parse_png_path(member: str) -> tuple[FieldIdentity, int]:
    match = _PNG.fullmatch(_relative_member(member) or "")
    if match is None:
        raise ValueError(f"Invalid by_write PNG identity: {member!r}")
    return _identity(match), int(match["index"])


def parse_cls(data: bytes, member: str) -> ClassLabels:
    match = _CLS.fullmatch(_relative_member(member) or "")
    if match is None:
        raise ValueError(f"Invalid by_write CLS identity: {member!r}")
    lines = data.split(b"\n")
    if lines[-1] != b"" or not re.fullmatch(rb"0|[1-9][0-9]*", lines[0]):
        raise ValueError(f"Invalid CLS count/header or LF termination: {member}")
    count = int(lines[0])
    if count > 100000 or len(lines) != count + 2:
        raise ValueError(f"CLS declared count mismatch: {member}")
    tokens = lines[1:-1]
    if any(not re.fullmatch(rb"[0-9a-fA-F]{2}", token) or int(token, 16) > 127 for token in tokens):
        raise ValueError(f"Invalid hex ASCII CLS label: {member}")
    # ASCII control/status values are preserved for audit, never silently dropped.
    return ClassLabels(_identity(match), member, hashlib.sha256(data).hexdigest(),
                       tuple(token.decode("ascii") for token in tokens), tuple(int(t, 16) for t in tokens))


def decode_png(data: bytes, *, foreground: str) -> bytes:
    """Return unresized 128x128 grayscale pixels with foreground explicitly 255.

    This is raster evidence only. It contains no observed order, timing, or strokes.
    Pillow is optional and imported only for requested raster verification.
    """
    if foreground not in ("black", "white"):
        raise ValueError("Foreground polarity must explicitly be black or white")
    from PIL import Image
    with Image.open(io.BytesIO(data)) as image:
        if image.format != "PNG" or image.size != (128, 128) or image.mode not in ("1", "L", "RGB"):
            raise ValueError("Expected binary 128x128 PNG raster")
        image.load()
        if image.mode == "RGB":
            red, green, blue = image.split()
            if red.tobytes() != green.tobytes() or red.tobytes() != blue.tobytes():
                raise ValueError("Unexpected color PNG raster")
        pixels = image.convert("L").tobytes()
        if pixels.translate(None, b"\x00\xff"):
            raise ValueError("Expected binary PNG pixels")
        return pixels.translate(_INVERT_BINARY) if foreground == "black" else pixels


def grouped_splits(groups: Mapping[str, Iterable[str]], *, seed: str,
                   development_fraction: float = 0.1) -> dict[str, str]:
    if not isinstance(seed, str) or not seed or not 0 <= development_fraction <= 1:
        raise ValueError("Invalid grouped split seed/fraction")
    assignments = {}
    for writer, partitions in groups.items():
        parts = frozenset(partitions)
        if not re.fullmatch(r"[0-9]{4}", writer) or not parts or not parts <= TRAIN_PARTITIONS | {"hsf_4", "hsf_5", "hsf_8"}:
            raise ValueError("Invalid recorded writer/partition group")
        if "hsf_4" in parts:
            role = "reserved"
        elif "hsf_5" in parts:
            role = "withheld"
        elif "hsf_8" in parts:
            role = "unprocessed"
        else:
            value = int.from_bytes(hashlib.sha256(f"{seed}\0{writer}".encode()).digest(), "big")
            role = "dev" if value < development_fraction * (1 << 256) else "train"
        assignments[writer] = role
    return assignments


def assert_grouped_splits(rows: Iterable[RasterSample]) -> None:
    seen = {}
    for row in rows:
        if row.split not in ROLES or seen.setdefault(row.writer_id, row.split) != row.split:
            raise ValueError(f"Same recorded writer crosses splits: {row.writer_id}")


def _members(archive: ZipFile) -> Iterable[ZipInfo]:
    seen = set()
    for info in archive.infolist():
        if info.filename in seen:
            raise ValueError(f"Duplicate ZIP member: {info.filename}")
        seen.add(info.filename)
        _relative_member(info.filename)
        if not info.is_dir():
            yield info


def _add_copy(groups: dict[str, list[int]], digest: str, label: int, role: str) -> None:
    receipt = groups.setdefault(digest, [0, 0, 0])
    receipt[0] += 1
    receipt[1] |= 1 << label
    receipt[2] |= 1 << ROLES.index(role)


def _copy_receipt(groups: Mapping[str, list[int]]) -> dict:
    duplicates = [r for r in groups.values() if r[0] > 1]
    return {"duplicateGroups": len(duplicates), "extraDuplicateRows": sum(r[0] - 1 for r in duplicates),
            "crossSplitGroups": sum(r[2].bit_count() > 1 for r in duplicates),
            "crossSplitRows": sum(r[0] for r in duplicates if r[2].bit_count() > 1),
            "conflictingLabelGroups": sum(r[1].bit_count() > 1 for r in duplicates),
            "conflictingLabelRows": sum(r[0] for r in duplicates if r[1].bit_count() > 1)}


def audit_zips(png_zip: Path, cls_zip: Path, *, seed: str = "nist-sd19-source-audit-v1",
               development_fraction: float = 0.1, verify_rasters: bool = False,
               foreground: str = "black", row_sink: Callable[[RasterSample], None] | None = None) -> dict:
    """Audit all present writer fields without extraction or model dependencies.

    Each nonempty CLS field must join exactly; absent fields are legitimate.
    Raw file copies and decoded pixel copies are distinct contamination receipts.
    Copies are reported without deduplication or removal of valid source rows.
    """
    if foreground not in ("black", "white"):
        raise ValueError("Foreground polarity must explicitly be black or white")
    source_hashes = {"pngZIP": sha256_file(png_zip), "clsZIP": sha256_file(cls_zip)}
    runtime = {"python": platform.python_version(), "pillow": None}
    if verify_rasters:
        import PIL
        runtime["pillow"] = PIL.__version__
    with ZipFile(png_zip) as images, ZipFile(cls_zip) as classes:
        png_fields: dict[FieldIdentity, dict[int, ZipInfo]] = defaultdict(dict)
        cls_fields: dict[FieldIdentity, ClassLabels] = {}
        for info in _members(images):
            relative = _relative_member(info.filename)
            if relative is None:
                continue
            field, index = parse_png_path(info.filename)
            if index in png_fields[field]:
                raise ValueError(f"Duplicate PNG identity/alias: {field.key}/{index}")
            png_fields[field][index] = info
        for info in _members(classes):
            relative = _relative_member(info.filename)
            if relative is None or not relative.endswith(".cls"):
                continue
            labels = parse_cls(classes.read(info), info.filename)
            if labels.field in cls_fields:
                raise ValueError(f"Duplicate CLS identity/alias: {labels.field.key}")
            cls_fields[labels.field] = labels
        if not cls_fields or set(png_fields) - set(cls_fields):
            raise ValueError("Missing CLS field for PNG source rows")
        partitions: dict[str, set[str]] = defaultdict(set)
        forms: dict[str, set[str]] = defaultdict(set)
        for field, labels in cls_fields.items():
            if set(png_fields.get(field, {})) != set(range(len(labels.values))):
                raise ValueError(f"Noncontiguous/missing/extra PNG indices against CLS: {field.key}")
            partitions[field.writer_id].add(field.partition)
            forms[field.writer_id].add(f"{field.partition}/{field.form_id}")
        assignments = grouped_splits(partitions, seed=seed, development_fraction=development_fraction)
        raw_copies: dict[str, list[int]] = {}
        raster_copies: dict[str, list[int]] = {}
        counts, labels_count, controls, field_receipts = Counter(), Counter(), Counter(), []
        uniform_rasters = []
        for field in sorted(cls_fields):
            labels = cls_fields[field]
            role = assignments[field.writer_id]
            field_receipts.append({"fieldKey": field.key, "count": len(labels.values),
                                   "clsMember": labels.member, "clsSHA256": labels.sha256})
            for index, label in enumerate(labels.values):
                info = png_fields[field][index]
                data = images.read(info)  # ZIP CRC is verified by ZipFile.read.
                raw_hash = hashlib.sha256(data).hexdigest()
                raster_hash = None
                if verify_rasters:
                    pixels = decode_png(data, foreground=foreground)
                    raster_hash = hashlib.sha256(pixels).hexdigest()
                    if pixels.count(pixels[:1]) == len(pixels):
                        uniform_rasters.append({"sampleID": f"{field.key}/{index:05d}",
                                                "foregroundPixelValue": pixels[0]})
                _add_copy(raw_copies, raw_hash, label, role)
                if raster_hash is not None:
                    _add_copy(raster_copies, raster_hash, label, role)
                counts[role] += 1
                labels_count[f"{label:02x}"] += 1
                if label < 32 or label == 127:
                    controls[f"{label:02x}"] += 1
                row = RasterSample(f"{field.key}/{index:05d}", field.writer_id, field.partition,
                    field.template_id, field.form_id, field.field_id, index, role, chr(label),
                    f"{label:02x}", labels.raw_tokens[index], info.filename, raw_hash,
                    labels.member, labels.sha256, index + 2, raster_hash)
                if row_sink is not None:
                    row_sink(row)
        return {"formatVersion": 1, "sourceID": SOURCE_ID, "sourceArchiveSHA256": source_hashes,
                "importerSourceSHA256": sha256_file(Path(__file__)), "runtime": runtime,
                "rightsStatus": RIGHTS_STATUS, "trainingEligibilityEstablished": False,
                "inputKind": "raster-only", "observedTrajectories": False,
                "writerIdentityMeaning": "recorded writer number; physical-person independence unproven",
                "splitSeed": seed, "developmentFraction": development_fraction,
                "groupKey": "writer number across every template and partition", "hsf4Policy": "reserved",
                "sampleCount": sum(counts.values()), "fieldCount": len(cls_fields),
                "formCount": sum(len(value) for value in forms.values()), "writerCount": len(partitions),
                "sampleCountsBySplit": dict(sorted(counts.items())), "labelsByByteHex": dict(sorted(labels_count.items())),
                "preservedASCIIControlOrStatusLabels": dict(sorted(controls.items())),
                "rasterVerification": {"verifiedCount": sum(counts.values()) if verify_rasters else 0,
                                       "dimensions": [128, 128], "binary": True if verify_rasters else None,
                                       "foreground": foreground, "transformation": "polarity only; no resize",
                                       "uniformRasterCount": len(uniform_rasters) if verify_rasters else None,
                                       "uniformRasters": uniform_rasters if verify_rasters else None},
                "rawPNGCopies": _copy_receipt(raw_copies),
                "decodedRasterCopies": _copy_receipt(raster_copies) if verify_rasters else None,
                "fields": field_receipts,
                "writers": [{"writerID": writer, "split": assignments[writer],
                             "partitions": sorted(partitions[writer]), "forms": sorted(forms[writer])}
                            for writer in sorted(partitions)]}


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--png-zip", type=Path, required=True)
    parser.add_argument("--cls-zip", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="Exclusive new output directory")
    parser.add_argument("--seed", default="nist-sd19-source-audit-v1")
    parser.add_argument("--development-fraction", type=float, default=0.1)
    parser.add_argument("--verify-rasters", action="store_true")
    parser.add_argument("--foreground", choices=("black", "white"), required=True)
    args = parser.parse_args(argv)
    args.output.mkdir(mode=0o700)
    rows_path = args.output / "samples.jsonl"
    with rows_path.open("x", encoding="utf-8") as stream:
        report = audit_zips(args.png_zip, args.cls_zip, seed=args.seed,
            development_fraction=args.development_fraction, verify_rasters=args.verify_rasters,
            foreground=args.foreground,
            row_sink=lambda row: stream.write(json.dumps(asdict(row), sort_keys=True) + "\n"))
    report["samplesJSONLSHA256"] = sha256_file(rows_path)
    with (args.output / "summary.json").open("x", encoding="utf-8") as stream:
        json.dump(report, stream, sort_keys=True, indent=2)
        stream.write("\n")
    print(json.dumps({key: report[key] for key in ("sampleCount", "writerCount", "rightsStatus")}, sort_keys=True))


if __name__ == "__main__":
    main()
