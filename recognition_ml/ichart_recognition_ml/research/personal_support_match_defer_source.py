"""Training-role-only UJI source reader for support match/defer research.

The complete public file is authenticated and its metadata grid is validated,
but coordinate tokens become numeric ink objects only for the 32 writers that
the bound parent receipt assigns to training.  Development and reserved rows
are never materialized as points, strokes, or samples.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from typing import Mapping

from ..features import InkPoint, InkStroke
from .uji_personal import SOURCE_SHA256, Sample


VERSION = "personal-support-match-defer-training-source-v1"
PARENT_RECEIPT_SHA256 = "d2a31e73d53b25b812f0ba4f24f812014515606f97a20e6b7170eaf94d0e20d2"
PARENT_METADATA_SHA256 = "97653c8a59077588a886cdee2577f94084cf704f55435f320016720870642332"
MAX_SOURCE_BYTES = 128 * 1024 * 1024
OFFICIAL_WRITER_COUNT = 60
OFFICIAL_TRAINING_WRITERS = 32
OFFICIAL_DEVELOPMENT_WRITERS = 8
OFFICIAL_RESERVED_WRITERS = 20
OFFICIAL_VOCABULARY_COUNT = 97
OFFICIAL_SESSION_COUNT = 2
OFFICIAL_ROW_COUNT = 11_640
OFFICIAL_TRAINING_ROW_COUNT = 6_208

_WRITER = re.compile(r"((?:trn|tst)_(?:UJI|UPV)_W[0-9]{2})-0([12])")
_TRAINING_WRITER = re.compile(r"trn_(?:UJI|UPV)_W[0-9]{2}")
_RESERVED_WRITER = re.compile(r"tst_(?:UJI|UPV)_W[0-9]{2}")
_DECIMAL = re.compile(r"[0-9]+")
_COORDINATE_TOKEN = re.compile(r"[+-]?[0-9]{1,8}")
_SHA256 = re.compile(r"[0-9a-f]{64}")


@dataclass(frozen=True)
class SourceRolePlan:
    source_sha256: str
    parent_receipt_sha256: str
    training_writers: tuple[str, ...]
    development_writers: tuple[str, ...]
    reserved_writers: tuple[str, ...]
    vocabulary: tuple[str, ...]

    @property
    def excluded_writers(self) -> tuple[str, ...]:
        return self.development_writers + self.reserved_writers


def _canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode()


def _validate_plan(plan: SourceRolePlan) -> None:
    if not isinstance(plan, SourceRolePlan):
        raise ValueError("Source role plan is required")
    roles = plan.training_writers + plan.development_writers + plan.reserved_writers
    if (
        not isinstance(plan.source_sha256, str)
        or _SHA256.fullmatch(plan.source_sha256) is None
        or not isinstance(plan.parent_receipt_sha256, str)
        or _SHA256.fullmatch(plan.parent_receipt_sha256) is None
        or not roles
        or any(not isinstance(writer, str) for writer in roles)
        or len(set(roles)) != len(roles)
        or tuple(sorted(plan.training_writers)) != plan.training_writers
        or tuple(sorted(plan.development_writers)) != plan.development_writers
        or tuple(sorted(plan.reserved_writers)) != plan.reserved_writers
        or any(_TRAINING_WRITER.fullmatch(writer) is None for writer in plan.training_writers + plan.development_writers)
        or any(_RESERVED_WRITER.fullmatch(writer) is None for writer in plan.reserved_writers)
        or not plan.vocabulary
        or tuple(sorted(set(plan.vocabulary))) != plan.vocabulary
        or any(not isinstance(label, str) or len(label) != 1 or label.isspace() for label in plan.vocabulary)
    ):
        raise ValueError("Malformed or overlapping source role plan")


def _validate_official_plan(plan: SourceRolePlan) -> None:
    _validate_plan(plan)
    training_domain = plan.training_writers + plan.development_writers
    ranked = sorted(
        training_domain,
        key=lambda writer: hashlib.sha256(("personal-encoder-v1:" + writer).encode()).hexdigest(),
    )
    expected_training = tuple(sorted(ranked[OFFICIAL_DEVELOPMENT_WRITERS:]))
    expected_development = tuple(sorted(ranked[:OFFICIAL_DEVELOPMENT_WRITERS]))
    if (
        plan.source_sha256 != SOURCE_SHA256
        or len(plan.training_writers) != OFFICIAL_TRAINING_WRITERS
        or len(plan.development_writers) != OFFICIAL_DEVELOPMENT_WRITERS
        or len(plan.reserved_writers) != OFFICIAL_RESERVED_WRITERS
        or len(training_domain) + len(plan.reserved_writers) != OFFICIAL_WRITER_COUNT
        or len(plan.vocabulary) != OFFICIAL_VOCABULARY_COUNT
        or plan.training_writers != expected_training
        or plan.development_writers != expected_development
        or plan.reserved_writers != tuple(sorted(plan.reserved_writers))
    ):
        raise ValueError("Receipt does not bind the official 32/8/20 role split")


def role_plan_from_receipt(
    receipt: Mapping[str, object],
    *,
    receipt_sha256: str,
) -> SourceRolePlan:
    if (
        not isinstance(receipt, Mapping)
        or not isinstance(receipt_sha256, str)
        or _SHA256.fullmatch(receipt_sha256) is None
    ):
        raise ValueError("Bound parent receipt is required")
    try:
        plan = SourceRolePlan(
            source_sha256=receipt["sourceSHA256"],
            parent_receipt_sha256=receipt_sha256,
            training_writers=tuple(receipt["trainingWriters"]),
            development_writers=tuple(receipt["developmentWriters"]),
            reserved_writers=tuple(receipt["reservedWriters"]),
            vocabulary=tuple(receipt["vocabulary"]),
        )
    except (KeyError, TypeError) as exc:
        raise ValueError("Parent receipt is missing source roles") from exc
    if hashlib.sha256(_canonical_json(dict(receipt))).hexdigest() != receipt_sha256:
        raise ValueError("Parent receipt digest mismatch")
    _validate_official_plan(plan)
    return plan


def _construct_point(x_token: str, y_token: str) -> InkPoint:
    x, y = int(x_token), int(y_token)
    if abs(x) >= 100_000_000 or abs(y) >= 100_000_000:
        raise ValueError("UJI coordinate out of range")
    return InkPoint(x, y)


def _construct_stroke(points: tuple[InkPoint, ...]) -> InkStroke:
    return InkStroke(points)


def _construct_sample(
    writer: str,
    session: int,
    label: str,
    strokes: tuple[InkStroke, ...],
) -> Sample:
    return Sample(writer, session, label, strokes)


def parse_training_source(text: str, plan: SourceRolePlan) -> tuple[Sample, ...]:
    """Validate the full grid while materializing only allowed training ink."""

    _validate_plan(plan)
    if not isinstance(text, str):
        raise ValueError("Decoded UJI text is required")
    lines = iter(
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith("//")
    )
    all_writers = set(plan.training_writers + plan.excluded_writers)
    allowed = set(plan.training_writers)
    vocabulary = set(plan.vocabulary)
    metadata_rows: set[tuple[str, int, str]] = set()
    samples: list[Sample] = []
    try:
        for line in lines:
            header = line.split()
            if len(header) != 3 or header[0] != "WORD" or len(header[1]) != 1 or header[1].isspace():
                raise ValueError("Malformed UJI WORD")
            identity = _WRITER.fullmatch(header[2])
            if identity is None:
                raise ValueError("Malformed UJI writer/session")
            writer, session, label = identity[1], int(identity[2]), header[1]
            if writer not in all_writers or label not in vocabulary:
                raise ValueError("UJI row falls outside the bound metadata domain")
            key = (writer, session, label)
            if key in metadata_rows:
                raise ValueError("Duplicate UJI sample")
            metadata_rows.add(key)

            count = next(lines).split()
            if len(count) != 2 or count[0] != "NUMSTROKES" or _DECIMAL.fullmatch(count[1]) is None:
                raise ValueError("Malformed UJI NUMSTROKES")
            stroke_count = int(count[1])
            if not 1 <= stroke_count <= 64:
                raise ValueError("Malformed UJI NUMSTROKES")
            construct = writer in allowed
            strokes: list[InkStroke] | None = [] if construct else None
            for _ in range(stroke_count):
                points = next(lines).split()
                if (
                    len(points) < 3
                    or points[0] != "POINTS"
                    or _DECIMAL.fullmatch(points[1]) is None
                    or points[2] != "#"
                ):
                    raise ValueError("Malformed UJI POINTS")
                point_count = int(points[1])
                coordinate_tokens = points[3:]
                if (
                    not 1 <= point_count <= 32_768
                    or len(coordinate_tokens) != 2 * point_count
                    or any(_COORDINATE_TOKEN.fullmatch(token) is None for token in coordinate_tokens)
                ):
                    raise ValueError("UJI point count or coordinate syntax mismatch")
                if construct:
                    assert strokes is not None
                    ink_points = tuple(
                        _construct_point(x_token, y_token)
                        for x_token, y_token in zip(coordinate_tokens[::2], coordinate_tokens[1::2])
                    )
                    strokes.append(_construct_stroke(ink_points))
            if construct:
                assert strokes is not None
                samples.append(_construct_sample(writer, session, label, tuple(strokes)))
    except StopIteration as exc:
        raise ValueError("Truncated UJI source") from exc

    expected_grid = {
        (writer, session, label)
        for writer in all_writers
        for session in (1, 2)
        for label in plan.vocabulary
    }
    if metadata_rows != expected_grid:
        raise ValueError("Incomplete or unexpected UJI metadata grid")
    expected_training_rows = len(plan.training_writers) * 2 * len(plan.vocabulary)
    if len(samples) != expected_training_rows:
        raise ValueError("Training source row count changed")
    return tuple(sorted(samples, key=lambda sample: sample.identity))


def _read_bounded_regular(path: Path) -> bytes:
    path = Path(path)
    if (
        not path.is_absolute()
        or path.resolve() != path
        or path.is_symlink()
        or not path.is_file()
        or not 0 < path.stat().st_size <= MAX_SOURCE_BYTES
    ):
        raise ValueError("Bounded regular UJI source file is required")
    return path.read_bytes()


def _load_bound_training_source(path: Path, plan: SourceRolePlan) -> tuple[Sample, ...]:
    source = _read_bounded_regular(path)
    if hashlib.sha256(source).hexdigest() != plan.source_sha256:
        raise ValueError("Source digest does not match the bound receipt")
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("UJI source is not UTF-8") from exc
    return parse_training_source(text, plan)


def load_official_training_source(
    path: Path,
    receipt: Mapping[str, object],
    *,
    receipt_sha256: str,
) -> tuple[Sample, ...]:
    """Load exactly the official 6,208 training rows and no excluded ink."""

    if (
        receipt_sha256 != PARENT_RECEIPT_SHA256
        or receipt.get("metadataSHA256") != PARENT_METADATA_SHA256
    ):
        raise ValueError("Protocol-pinned parent artifacts are required")
    plan = role_plan_from_receipt(receipt, receipt_sha256=receipt_sha256)
    samples = _load_bound_training_source(path, plan)
    if len(samples) != OFFICIAL_TRAINING_ROW_COUNT:
        raise ValueError("Official training row count changed")
    return samples
