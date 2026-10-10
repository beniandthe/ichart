"""Strict UJI v2 source adapter for personal-feature research, not corpus intake."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from ..features import InkPoint, InkStroke

SOURCE_SHA256 = "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61"


@dataclass(frozen=True)
class Sample:
    writer: str
    session: int
    label: str
    strokes: tuple[InkStroke, ...]

    @property
    def identity(self) -> str:
        return f"{self.writer}-{self.session}-{self.label}"


def parse_source(text: str) -> tuple[Sample, ...]:
    lines = iter(line.strip() for line in text.splitlines()
                 if line.strip() and not line.strip().startswith("//"))
    records: list[Sample] = []
    seen: set[str] = set()
    try:
        for line in lines:
            header = line.split()
            if len(header) != 3 or header[0] != "WORD" or len(header[1]) != 1:
                raise ValueError("Malformed UJI WORD")
            identity = re.fullmatch(r"((?:trn|tst)_(?:UJI|UPV)_W[0-9]{2})-0([12])", header[2])
            if identity is None:
                raise ValueError("Malformed UJI writer/session")
            count = next(lines).split()
            if len(count) != 2 or count[0] != "NUMSTROKES" or not 1 <= int(count[1]) <= 64:
                raise ValueError("Malformed UJI NUMSTROKES")
            strokes = []
            for _ in range(int(count[1])):
                points = next(lines).split()
                if len(points) < 3 or points[0] != "POINTS" or points[2] != "#":
                    raise ValueError("Malformed UJI POINTS")
                size = int(points[1])
                if not 1 <= size <= 32_768 or len(points) != 3 + 2 * size:
                    raise ValueError("UJI point count mismatch")
                coordinates = tuple(int(value) for value in points[3:])
                if any(abs(value) >= 100_000_000 for value in coordinates):
                    raise ValueError("UJI coordinate out of range")
                strokes.append(InkStroke(tuple(InkPoint(x, y) for x, y in
                                               zip(coordinates[::2], coordinates[1::2]))))
            record = Sample(identity[1], int(identity[2]), header[1], tuple(strokes))
            if record.identity in seen:
                raise ValueError("Duplicate UJI sample")
            seen.add(record.identity)
            records.append(record)
    except StopIteration as exc:
        raise ValueError("Truncated UJI source") from exc
    if not records:
        raise ValueError("Empty UJI source")
    return tuple(records)


def load_official_source(path: Path) -> tuple[Sample, ...]:
    source = path.read_bytes()
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source digest does not match the frozen public dataset")
    records = parse_source(source.decode("utf-8"))
    writers = {record.writer for record in records}
    labels = {record.label for record in records}
    if len(records) != 11_640 or len(writers) != 60 or len(labels) != 97:
        raise ValueError("Incomplete public dataset")
    for writer in writers:
        for session in (1, 2):
            if {r.label for r in records if r.writer == writer and r.session == session} != labels:
                raise ValueError("Incomplete writer/session")
    split_writers(records)
    return records


def split_writers(records: tuple[Sample, ...]) -> tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    writers = {record.writer for record in records}
    development = sorted((w for w in writers if w.startswith("trn_")),
                         key=lambda w: hashlib.sha256(("personal-encoder-v1:" + w).encode()).hexdigest())
    reserved = tuple(sorted(w for w in writers if w.startswith("tst_")))
    if len(development) != 40 or len(reserved) != 20:
        raise ValueError("Expected 40 development and 20 reserved writers")
    return tuple(sorted(development[8:])), tuple(sorted(development[:8])), reserved


def trajectory_fingerprint(record: Sample) -> str:
    """Translation/scale normalization, keeping every point and stroke boundary."""
    points = [p for stroke in record.strokes for p in stroke.points]
    left, top = min(p.x for p in points), min(p.y for p in points)
    span = max(max(p.x for p in points) - left, max(p.y for p in points) - top)
    normalized = [[(round((p.x - left) / span, 8), round((p.y - top) / span, 8))
                   if span else (0, 0) for p in stroke.points] for stroke in record.strokes]
    return hashlib.sha256(json.dumps(normalized, separators=(",", ":")).encode()).hexdigest()
