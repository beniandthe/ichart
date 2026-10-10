"""Pinned HASYv2 bitmap supplement for research, never fabricated trajectories.

HASY user IDs are not reliable writer identities. Its fold-1 holdout is a
sample-level development check only, not evidence of writer generalization.
Dataset: Martin Thoma, DOI 10.5281/zenodo.259444, ODbL 1.0.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import csv
from dataclasses import dataclass, replace
import hashlib
import io
from pathlib import Path
import re
import tarfile

import numpy as np
from PIL import Image, ImageOps
import torch

from ..features import RASTER_HEIGHT, RASTER_WIDTH

SOURCE_SHA256 = "7c3ffe709e8c2b83f6ab7d8afc79f7b5f46421657981b1752d22a0ed0052aa2d"
NOVEL_LABELS = ("#", "+", "/", "ø", "△")
# Visual glyph mappings, not substitutions in recognized chord strings.
ALIASES = {r"\#": "#", r"\sharp": "#", r"\flat": "b",
           r"\Delta": "△", r"\triangle": "△", r"\vartriangle": "△",
           r"\emptyset": "ø"}


@dataclass(frozen=True)
class BitmapSample:
    identity: str
    latex: str
    label: str
    role: str
    user_id: str  # Metadata only; deliberately not named writer.
    raw_hash: str
    raster_hash: str
    pixels: bytes
    exclusions: tuple[str, ...] = ()


def map_label(latex: str, old_vocabulary: tuple[str, ...]) -> str | None:
    label = ALIASES.get(latex, latex)
    return label if len(label) == 1 and label in set(old_vocabulary) | set(NOVEL_LABELS) else None


def normalize_bitmap(image: Image.Image) -> bytes:
    """Black-on-white 32px bitmap to centered, aspect-preserving research input.

    Bitmap interpolation is NOT the app's vector rasterizer. No stroke order,
    timing, or trajectories are invented. Live input/feature schema is unchanged.
    """
    if image.size != (32, 32) or image.mode not in ("L", "RGB"):
        raise ValueError("Expected original 32x32 HASY bitmap")
    values = np.asarray(image)
    if values.ndim == 3 and not np.all(values == values[:, :, :1]):
        raise ValueError("Unexpected color bitmap")
    if not np.isin(values, [0, 255]).all():
        raise ValueError("Expected binary source pixels")
    foreground = ImageOps.invert(image.convert("L"))
    bounds = foreground.getbbox()
    if bounds is None:
        raise ValueError("Empty source glyph")
    cropped = foreground.crop(bounds)
    scale = min((RASTER_WIDTH - 16) / cropped.width, (RASTER_HEIGHT - 16) / cropped.height)
    width, height = max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))
    resized = cropped.resize((width, height), Image.Resampling.BILINEAR)
    canvas = Image.new("L", (RASTER_WIDTH, RASTER_HEIGHT))
    canvas.paste(resized, ((RASTER_WIDTH - width) // 2, (RASTER_HEIGHT - height) // 2))
    return canvas.tobytes()


def quarantine_copies(samples: tuple[BitmapSample, ...]) -> tuple[BitmapSample, ...]:
    if (len({s.identity for s in samples}) != len(samples)
            or any(s.role not in ("training", "development") for s in samples)):
        raise ValueError("Invalid sample identity or role")
    by_pixels: dict[str, list[BitmapSample]] = defaultdict(list)
    for sample in samples:
        by_pixels[sample.raster_hash].append(sample)
    result = []
    for sample in samples:
        group = by_pixels[sample.raster_hash]
        reasons = []
        if len({s.label for s in group}) != 1:
            reasons.append("conflicting_identical_raster")
        elif sample.role == "development" and any(s.role == "training" for s in group):
            reasons.append("training_raster_copy")
        elif sample.identity != min(s.identity for s in group if s.role == sample.role):
            reasons.append("same_role_raster_copy")
        result.append(replace(sample, exclusions=tuple(reasons)))
    return tuple(result)


def load_hasy(path: Path, old_vocabulary: tuple[str, ...]) -> tuple[BitmapSample, ...]:
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Wrong HASYv2 source bytes")
    required = {"symbols.csv", "hasy-data-labels.csv",
                "classification-task/fold-1/train.csv", "classification-task/fold-1/test.csv"}
    tables = {}
    # Stream twice rather than repeatedly seeking through a compressed archive.
    # No archive entry is extracted to disk and no supplied code is executed.
    with tarfile.open(path, "r|bz2") as archive:
        for member in archive:
            if member.name in required:
                if not member.isfile() or member.name in tables or member.size > 20_000_000:
                    raise ValueError("Invalid source metadata")
                tables[member.name] = list(csv.DictReader(io.StringIO(archive.extractfile(member).read().decode())))
    if set(tables) != required or len(tables["symbols.csv"]) != 369 or len(tables["hasy-data-labels.csv"]) != 168233:
        raise ValueError("Incomplete official source metadata")
    symbols = {r["symbol_id"]: r["latex"] for r in tables["symbols.csv"]}
    source = {r["path"]: r for r in tables["hasy-data-labels.csv"]}
    if len(source) != 168233 or len(symbols) != 369:
        raise ValueError("Duplicate official identities")
    roles = {}
    for filename, role in (("train", "training"), ("test", "development")):
        for row in tables[f"classification-task/fold-1/{filename}.csv"]:
            if not re.fullmatch(r"\.\./\.\./hasy-data/v2-[0-9]+\.png", row["path"]):
                raise ValueError("Invalid official fold path")
            name = row["path"][6:]
            if name in roles or source.get(name) != {**row, "path": name}:
                raise ValueError("Overlapping folds or metadata mismatch")
            roles[name] = role
    if set(roles) != set(source):
        raise ValueError("Incomplete fold partition")
    selected = {}
    for name, row in source.items():
        if symbols.get(row["symbol_id"]) != row["latex"]:
            raise ValueError("Symbol mapping mismatch")
        label = map_label(row["latex"], old_vocabulary)
        if label is not None:
            selected[name] = (row, label)
    records, seen = [], set()
    with tarfile.open(path, "r|bz2") as archive:
        for member in archive:
            if member.name not in selected:
                continue
            if member.name in seen or not member.isfile() or member.size > 100_000:
                raise ValueError("Invalid selected image member")
            seen.add(member.name)
            row, label = selected[member.name]
            with Image.open(io.BytesIO(archive.extractfile(member).read())) as image:
                pixels = normalize_bitmap(image)
                raw_hash = hashlib.sha256(image.convert("L").tobytes()).hexdigest()
            records.append(BitmapSample(member.name, row["latex"], label, roles[member.name], row["user_id"],
                                        raw_hash, hashlib.sha256(pixels).hexdigest(), pixels))
    if seen != set(selected) or not set(NOVEL_LABELS).issubset(s.label for s in records):
        raise ValueError("Missing required symbol images")
    return quarantine_copies(tuple(sorted(records, key=lambda s: s.identity)))


def bitmap_tensor(samples: tuple[BitmapSample, ...], role: str) -> torch.Tensor:
    if role not in ("training", "development") or not samples or any(s.role != role or s.exclusions for s in samples):
        raise ValueError("Wrong role or quarantined bitmap reached tensor conversion")
    return torch.from_numpy(np.frombuffer(b"".join(s.pixels for s in samples), dtype=np.uint8).copy()
                            .reshape(-1, 1, RASTER_HEIGHT, RASTER_WIDTH))


def source_summary(samples):
    return {"samples": len(samples), "byRole": dict(Counter(s.role for s in samples)),
            "byLabel": dict(sorted(Counter(s.label for s in samples).items())),
            "exclusions": dict(Counter(reason for s in samples for reason in s.exclusions)),
            "writerIndependent": False, "license": "ODbL-1.0", "sourceSHA256": SOURCE_SHA256}
