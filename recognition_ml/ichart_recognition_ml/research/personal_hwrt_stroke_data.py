"""Prepare the frozen UJI/HWRT stroke-field experiment inputs.

Training and development are deliberately different publication operations.
The development loader has no code path that opens ``truth.json``.  This is a
research artifact builder only; it performs no fitting or inference.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import platform
import re
from typing import Mapping, Sequence

import numpy as np

from ..contracts import canonical_json_bytes, strict_json_loads
from ..features import InkPoint, InkStroke, RASTER_HEIGHT, RASTER_WIDTH, rasterize
from .personal_stroke_field import CHANNEL_COUNT, VERSION as FIELD_VERSION, encode_stroke_field
from .personal_symbol_data import NOVEL_LABELS
from .uji_personal import SOURCE_SHA256, Sample, load_official_source, split_writers, trajectory_fingerprint


DATA_VERSION = "personal-hwrt-stroke-field-data-v1"
TRAINING_VERSION = "personal-hwrt-stroke-field-training-v1"
DEVELOPMENT_INPUTS_VERSION = "personal-hwrt-stroke-field-development-inputs-v1"
DEVELOPMENT_TRUTH_VERSION = "personal-hwrt-stroke-field-development-truth-v1"
COPY_UNION_VERSION = "personal-hwrt-stroke-field-input-copy-union-v1"
PROTOCOL_PATH = "docs/personal-hwrt-stroke-field-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "3cda2bcb7c64a79c3ef4371a8ef01fb1df0e0e75512a7f2f49f39cdc58ff9d13"
HWRT_RECEIPT_SHA256 = "f705c1696878bcc105f3b543dc381f3e78b7dff27e7693864280ac25e5e15545"
HWRT_SELECTED_SHA256 = "aeac37df06f5465aaf810e4f0da3688be1ba25283606bd4b390337fa056b929c"
HWRT_ARCHIVE_SHA256 = "b96feafd71b01f1623997dff3cc8ac4d18628d128cee1b3df1880518bba3ea4a"
HASY_RECEIPT_SHA256 = "ab9293fb5f81f9dd39ee9ade02f01ecb2bd203d783686f6e28dedab977f220d2"
HASY_LABELS_SHA256 = "c77ff976e236eefc960f640b90437fc994de2fa798f3428afb7475d95f50c222"
HASY_PIXEL_DUPLICATES_SHA256 = "9fc0a0a41cfff52c73eac50dd470c430901b1a84e5d1739293360e557cbc8336"
JOIN_REPORT_SHA256 = "8b8bd704f05ff3be6fde18856c42618b05a9ba4da6a49cdb598fd212b27cec91"
DOMAIN_SHA256 = "5d56503e0b3903b03e8e6dada57ee0fa7bac71453612ef8e992a001f9f0fc010"
DOMAIN_PATH = Path("/private/tmp/iChartAppendOnlyPublic-20261003.Tj9cxx/chord-domain.json")
ROOT = Path(__file__).resolve().parents[3]

TRAINING_ROWS = 10_073
DEVELOPMENT_ROWS = 1_987
UJI_TRAINING_ROWS = 6_208
UJI_DEVELOPMENT_ROWS = 1_552
HWRT_TRAINING_ROWS = 3_865
HWRT_DEVELOPMENT_ROWS = 435
FIELD_SHAPE = (CHANNEL_COUNT, RASTER_HEIGHT, RASTER_WIDTH)
_SHA256 = re.compile(r"[0-9a-f]{64}")
_MAX_JSON_BYTES = 128 * 1024 * 1024
_MAX_SOURCE_BYTES = 256 * 1024 * 1024

_HWRT_LABELS = {
    ("196", "+"): "+",
    ("922", "/"): "/",
    ("266", r"\#"): "#",
    ("948", r"\sharp"): "#",
    ("950", r"\emptyset"): "ø",
    ("959", r"\triangle"): "△",
    ("977", r"\vartriangle"): "△",
    ("152", r"\Delta"): "△",
}
_HWRT_COUNTS = {
    "training": {"#": 1_173, "+": 81, "/": 478, "ø": 853, "△": 1_280},
    "development": {"#": 131, "+": 9, "/": 54, "ø": 97, "△": 144},
}

CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/__init__.py",
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/__init__.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_stroke_field.py",
    "recognition_ml/ichart_recognition_ml/research/personal_symbol_data.py",
    "recognition_ml/ichart_recognition_ml/research/personal_hwrt_stroke_data.py",
    "recognition_ml/tests/test_personal_hwrt_stroke_data.py",
)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha_file(path: Path) -> tuple[int, str]:
    digest, size = hashlib.sha256(), 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def _digest(value: object) -> bool:
    return isinstance(value, str) and _SHA256.fullmatch(value) is not None


def _read_regular(path: Path, *, maximum: int = _MAX_JSON_BYTES) -> bytes:
    path = Path(path)
    if (not path.is_absolute() or path.resolve() != path or path.is_symlink()
            or not path.is_file() or not 0 < path.stat().st_size <= maximum):
        raise ValueError(f"Bounded absolute regular file required: {path}")
    return path.read_bytes()


def _json(data: bytes, name: str, *, newline: bool = False) -> dict:
    value = strict_json_loads(data.decode("utf-8"), name)
    expected = canonical_json_bytes(value) + (b"\n" if newline else b"")
    if not isinstance(value, dict) or data != expected:
        raise ValueError(f"{name} must be canonical JSON")
    return value


def _write(path: Path, data: bytes) -> None:
    with path.open("xb") as stream:
        stream.write(data)


def _fresh_output(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or path.parent.resolve() != path.parent or not path.parent.is_dir()
            or path.exists() or ROOT == path or ROOT in path.parents):
        raise ValueError("Fresh outside-repository output directory required")
    path.mkdir(mode=0o700)
    return path


def code_identity() -> dict[str, str]:
    identity = {name: _sha(_read_regular(ROOT / name)) for name in CODE_PATHS}
    if identity[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Frozen protocol changed")
    return identity


@dataclass(frozen=True)
class _SourceRow:
    opaque_id: str
    label: str
    source: str
    writer: str | None
    session: int | None
    native_symbol_id: str | None
    source_id: str
    source_index: int
    strokes: tuple[InkStroke, ...]


def _opaque(source: str, role: str, source_index: int) -> str:
    return _sha(f"{DATA_VERSION}\0{source}\0{role}\0{source_index}".encode())


def _uji_rows(records: tuple[Sample, ...], role: str) -> tuple[_SourceRow, ...]:
    training, development, reserved = split_writers(records)
    writers = training if role == "training" else development
    if set(writers) & set(reserved) or (len(writers) != (32 if role == "training" else 8)):
        raise ValueError("UJI role boundary changed")
    selected = tuple(sorted((row for row in records if row.writer in set(writers)), key=lambda row: row.identity))
    expected = UJI_TRAINING_ROWS if role == "training" else UJI_DEVELOPMENT_ROWS
    if len(selected) != expected or any(row.writer in reserved for row in selected):
        raise ValueError("Wrong UJI role row count")
    return tuple(_SourceRow(
        _opaque("uji", role, index), row.label, "uji", row.writer, row.session, None,
        row.identity, index, row.strokes,
    ) for index, row in enumerate(selected))


def _validate_hwrt_bindings(hwrt: Path, hasy: Path, join_path: Path) -> tuple[dict, bytes]:
    receipt_bytes = _read_regular(hwrt / "source_receipt.json")
    if _sha(receipt_bytes) != HWRT_RECEIPT_SHA256:
        raise ValueError("Pinned HWRT receipt changed")
    receipt = _json(receipt_bytes, "HWRT receipt", newline=True)
    selected_bytes = _read_regular(hwrt / "selected_records.jsonl", maximum=_MAX_SOURCE_BYTES)
    artifact = receipt.get("artifacts", {}).get("selected_records.jsonl")
    if (artifact != {"bytes": len(selected_bytes), "sha256": _sha(selected_bytes)}
            or artifact["sha256"] != HWRT_SELECTED_SHA256):
        raise ValueError("Pinned HWRT selected-record artifact changed")
    hasy_bytes = _read_regular(hasy / "source_receipt.json")
    if _sha(hasy_bytes) != HASY_RECEIPT_SHA256:
        raise ValueError("Pinned HASY receipt changed")
    hasy_receipt = strict_json_loads(hasy_bytes.decode("utf-8"), "HASY receipt")
    if not isinstance(hasy_receipt, dict):
        raise ValueError("Pinned HASY receipt is malformed")
    for name, digest in (("source_metadata/hasy-data-labels.csv", HASY_LABELS_SHA256),
                         ("pixel_duplicates.json", HASY_PIXEL_DUPLICATES_SHA256)):
        identity = hasy_receipt.get("artifacts", {}).get(name)
        path = hasy / name
        if not isinstance(identity, dict) or identity.get("sha256") != digest:
            raise ValueError("Pinned HASY artifact binding changed")
        data = _read_regular(path)
        if identity != {"bytes": len(data), "sha256": _sha(data)}:
            raise ValueError("Pinned HASY provenance artifact changed")
    join_bytes = _read_regular(join_path, maximum=_MAX_SOURCE_BYTES)
    if _sha(join_bytes) != JOIN_REPORT_SHA256:
        raise ValueError("Pinned HWRT/HASY join report changed")
    join = json.loads(join_bytes)
    if (join.get("schemaVersion") != "hwrt-hasy-ordinal-pixel-verification-v1"
            or join.get("join", {}).get("metadataRowsChecked") != 168_233
            or join.get("join", {}).get("metadataMismatchCount") != 0
            or join.get("pixels", {}).get("selectedRows") != 5_507):
        raise ValueError("HWRT/HASY metadata join is incomplete")
    return receipt, selected_bytes


def _hwrt_rows(selected_bytes: bytes, role: str) -> tuple[_SourceRow, ...]:
    source_role = "train" if role == "training" else "test"
    rows: list[_SourceRow] = []
    seen: set[tuple[str, int]] = set()
    for line_number, line in enumerate(selected_bytes.splitlines(), 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"Malformed HWRT selected row {line_number}") from error
        key = (row.get("sourceSymbolID"), row.get("sourceLabel"))
        label = _HWRT_LABELS.get(key)
        if label is None or row.get("role") != source_role:
            continue
        source_index = row.get("recordIndex")
        if (isinstance(source_index, bool) or not isinstance(source_index, int) or source_index < 0
                or (source_role, source_index) in seen or row.get("coordinatePayloadSHA256") is None):
            raise ValueError("Invalid HWRT role-local identity")
        seen.add((source_role, source_index))
        raw_strokes = row.get("strokes")
        if not isinstance(raw_strokes, list) or not raw_strokes:
            raise ValueError("Mapped HWRT trajectory is unavailable")
        strokes = []
        for raw_stroke in raw_strokes:
            if not isinstance(raw_stroke, list) or not raw_stroke:
                raise ValueError("Mapped HWRT stroke is unavailable")
            points = []
            for point in raw_stroke:
                if (not isinstance(point, dict) or not {"x", "y"} <= point.keys()
                        or isinstance(point["x"], bool) or isinstance(point["y"], bool)):
                    raise ValueError("Malformed mapped HWRT point")
                points.append(InkPoint(float(point["x"]), float(point["y"])))
            strokes.append(InkStroke(tuple(points)))
        source_id = row.get("recordID")
        if not _digest(source_id):
            raise ValueError("Malformed HWRT record identity")
        rows.append(_SourceRow(
            _opaque("hwrt", role, source_index), label, "hwrt", None, None,
            key[0], source_id, source_index, tuple(strokes),
        ))
    rows.sort(key=lambda item: item.source_index)
    expected = HWRT_TRAINING_ROWS if role == "training" else HWRT_DEVELOPMENT_ROWS
    counts = Counter(row.label for row in rows)
    if len(rows) != expected or counts != Counter(_HWRT_COUNTS[role]):
        raise ValueError("Mapped HWRT role counts changed")
    return tuple(rows)


def _vocabulary(uji_records: tuple[Sample, ...]) -> tuple[str, ...]:
    old = tuple(sorted({row.label for row in uji_records}))
    value = old + tuple(NOVEL_LABELS)
    if len(old) != 97 or len(value) != 102 or len(set(value)) != 102:
        raise ValueError("Frozen 97+5 vocabulary changed")
    return value


def _domain_identity(vocabulary: Sequence[str]) -> dict:
    data = _read_regular(DOMAIN_PATH)
    if _sha(data) != DOMAIN_SHA256:
        raise ValueError("Frozen chord-domain export changed")
    value = _json(data, "chord-domain")
    if value.get("version") != "chord-recognition-domain-v1" or value.get("vocabulary") != list(vocabulary[:97]):
        raise ValueError("Chord-domain vocabulary changed")
    return {"bytes": len(data), "sha256": _sha(data)}


def _feature_row(row: _SourceRow) -> tuple[np.ndarray, dict]:
    field = np.ascontiguousarray(encode_stroke_field(row.strokes), dtype="<f4")
    if field.shape != FIELD_SHAPE or not np.isfinite(field).all():
        raise ValueError("Invalid stroke-field output")
    raster = rasterize(row.strokes).pixels
    expected = np.frombuffer(raster, np.uint8).reshape(RASTER_HEIGHT, RASTER_WIDTH).astype(np.float32) / np.float32(255)
    if not np.array_equal(field[0], expected):
        raise ValueError("Stroke-field occupancy differs from app raster")
    sample = Sample(row.writer or "hwrt", row.session or 1, row.label, row.strokes)
    metadata = {
        "opaqueID": row.opaque_id,
        "label": row.label,
        "source": row.source,
        "writer": row.writer,
        "session": row.session,
        "nativeSymbolID": row.native_symbol_id,
        "rasterSHA256": _sha(raster),
        "normalizedGeometrySHA256": trajectory_fingerprint(sample),
        "fieldSHA256": _sha(field.tobytes(order="C")),
    }
    return field, metadata


def _encode_rows(rows: Sequence[_SourceRow], path: Path) -> list[dict]:
    fields = np.lib.format.open_memmap(path, mode="w+", dtype="<f4", shape=(len(rows), *FIELD_SHAPE))
    metadata: list[dict] = []
    try:
        for index, row in enumerate(rows):
            field, item = _feature_row(row)
            fields[index] = field
            metadata.append(item)
            if (index + 1) % 128 == 0 or index + 1 == len(rows):
                print(f"encoded {index + 1}/{len(rows)} {row.source} rows", flush=True)
        fields.flush()
    finally:
        del fields
    if not metadata or len(metadata) != len(rows):
        raise ValueError("Feature preparation did not retain every row")
    return metadata


def _artifact(path: Path) -> dict:
    size, digest = _sha_file(path)
    return {"bytes": size, "sha256": digest}


def _copy_union(training_rows: Sequence[Mapping[str, object]], development_rows: Sequence[Mapping[str, object]],
                training_receipt_sha: str) -> tuple[dict[str, tuple[str, ...]], dict]:
    fields = ("rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256")
    training = {field: {row[field] for row in training_rows} for field in fields}
    groups = {field: defaultdict(list) for field in fields}
    for row in development_rows:
        for field in fields:
            groups[field][row[field]].append(row["opaqueID"])
    reasons: dict[str, set[str]] = defaultdict(set)
    for row in development_rows:
        opaque = row["opaqueID"]
        for field in fields:
            if row[field] in training[field]:
                reasons[opaque].add("training-" + field)
            peers = groups[field][row[field]]
            if len(peers) > 1 and opaque != min(peers):
                reasons[opaque].add("repeated-development-" + field)
    frozen = {key: tuple(sorted(value)) for key, value in reasons.items()}
    counts = Counter(reason for values in frozen.values() for reason in values)
    summary = {
        "version": COPY_UNION_VERSION,
        "trainingDataReceiptSHA256": training_receipt_sha,
        "hashFields": list(fields),
        "representativeRule": "lexicographically-smallest-opaqueID-per-development-hash",
        "affectedOpaqueIDs": sorted(frozen),
        "reasonCounts": dict(sorted(counts.items())),
    }
    return frozen, summary


def _receipt(role: str, vocabulary: Sequence[str], artifacts: Mapping[str, dict], code: Mapping[str, str],
             counts: Mapping[str, int], source_bindings: Mapping[str, object], *,
             fit_receipt_sha: str | None = None, training_receipt_sha: str | None = None) -> dict:
    return {
        "version": DATA_VERSION,
        "role": role,
        "fieldVersion": FIELD_VERSION,
        "protocolSHA256": PROTOCOL_SHA256,
        "vocabulary": list(vocabulary),
        "vocabularySHA256": _sha(canonical_json_bytes(list(vocabulary))),
        "counts": dict(counts),
        "sourceBindings": dict(source_bindings),
        "codeSHA256": dict(code),
        "artifacts": dict(artifacts),
        "fitReceiptSHA256": fit_receipt_sha,
        "trainingDataReceiptSHA256": training_receipt_sha,
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)},
        "roleGuards": {
            "privateInkUsed": False,
            "reservedUJIEncoded": False,
            "truthOpenedByDevelopmentLoader": False,
            "modelInferencePerformed": False,
            "optimizationPerformed": False,
        },
    }


def _validate_bound_identity(receipt: Mapping[str, object]) -> None:
    if receipt.get("codeSHA256") != code_identity():
        raise ValueError("Data receipt code identity changed")
    bindings = receipt.get("sourceBindings")
    expected_keys = {"ujiSourceSHA256", "hwrtReceiptSHA256", "hwrtSelectedRecordsSHA256",
        "hasyReceiptSHA256", "hasyLabelsSHA256", "hasyPixelDuplicatesSHA256",
        "joinReportSHA256", "domain", "hwrtArchiveSHA256"}
    if not isinstance(bindings, dict) or set(bindings) != expected_keys:
        raise ValueError("Data receipt source bindings are incomplete")
    expected = {
        "ujiSourceSHA256": SOURCE_SHA256,
        "hwrtReceiptSHA256": HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": JOIN_REPORT_SHA256,
        "hwrtArchiveSHA256": HWRT_ARCHIVE_SHA256,
    }
    if any(bindings.get(key) != value for key, value in expected.items()):
        raise ValueError("Data receipt source binding changed")
    domain = bindings["domain"]
    if (not isinstance(domain, dict) or set(domain) != {"bytes", "sha256"}
            or isinstance(domain["bytes"], bool) or not isinstance(domain["bytes"], int)
            or domain["bytes"] <= 0 or domain["sha256"] != DOMAIN_SHA256):
        raise ValueError("Data receipt chord-domain binding changed")


def _validate_fit(fit_dir: Path, expected_sha: str, training_receipt_sha: str,
                  vocabulary: Sequence[str]) -> dict:
    if not _digest(expected_sha):
        raise ValueError("Expected fit-receipt SHA-256 is required")
    data = _read_regular(Path(fit_dir) / "fit-receipt.json")
    if _sha(data) != expected_sha:
        raise ValueError("Completed fit receipt changed")
    value = _json(data, "fit-receipt")
    # Lazy import avoids a module-initialization cycle: the trainer imports
    # this data seam, while development preparation runs only after fitting.
    from . import personal_hwrt_stroke_train as train
    train._validate_fit_receipt(value, code=train.code_identity())
    if value["runtime"] != train._runtime_contract():
        raise ValueError("Fit runtime contract changed")
    required = {"version", "scope", "arms", "fieldVersion", "modelVersion", "labelCount",
        "vocabulary", "vocabularySHA256", "protocolSHA256", "codeSHA256", "dataReceiptSHA256",
        "dataArtifactsSHA256", "runtime", "recipe", "initialStateSHA256", "initialArmStateSHA256",
        "trainingPlanPath", "trainingPlanSHA256", "augmentationLedger", "trainingHistory",
        "weightFiles", "weightsSHA256", "finalStateSHA256", "selection"}
    if (set(value) != required or value["arms"] != ["rasterControl", "strokeField"]
            or value["fieldVersion"] != FIELD_VERSION or value["labelCount"] != 102
            or value["vocabulary"] != list(vocabulary) or value["protocolSHA256"] != PROTOCOL_SHA256
            or value["dataReceiptSHA256"] != training_receipt_sha
            or value["recipe"] != {"epochs": 30, "updatesPerArm": 1530,
                "exposuresPerArm": 195840, "batchSize": 128, "seed": 29}):
        raise ValueError("Fit receipt is incomplete or from another experiment")
    history = value["trainingHistory"]
    if not isinstance(history, dict) or any(not isinstance(history.get(arm), list) or len(history[arm]) != 30
                                            for arm in value["arms"]):
        raise ValueError("Both 30-epoch fits must complete before development encoding")
    for arm in value["arms"]:
        relative = value["weightFiles"].get(arm)
        expected = value["weightsSHA256"].get(arm)
        if not isinstance(relative, str) or Path(relative).is_absolute() or not _digest(expected):
            raise ValueError("Malformed fitted-weight binding")
        path = (Path(fit_dir) / relative).resolve()
        if Path(fit_dir).resolve() not in path.parents or _sha_file(path)[1] != expected:
            raise ValueError("Fitted weights changed")
    return value


def _source_rows(uji_source: Path, hwrt: Path, hasy: Path, join: Path, role: str):
    records = load_official_source(uji_source)
    vocabulary = _vocabulary(records)
    hwrt_receipt, selected_bytes = _validate_hwrt_bindings(hwrt, hasy, join)
    rows = _uji_rows(records, role) + _hwrt_rows(selected_bytes, role)
    expected = TRAINING_ROWS if role == "training" else DEVELOPMENT_ROWS
    if len(rows) != expected or len({row.opaque_id for row in rows}) != expected:
        raise ValueError("Combined role rows are incomplete or duplicated")
    bindings = {
        "ujiSourceSHA256": SOURCE_SHA256,
        "hwrtReceiptSHA256": HWRT_RECEIPT_SHA256,
        "hwrtSelectedRecordsSHA256": HWRT_SELECTED_SHA256,
        "hasyReceiptSHA256": HASY_RECEIPT_SHA256,
        "hasyLabelsSHA256": HASY_LABELS_SHA256,
        "hasyPixelDuplicatesSHA256": HASY_PIXEL_DUPLICATES_SHA256,
        "joinReportSHA256": JOIN_REPORT_SHA256,
        "domain": _domain_identity(vocabulary),
        "hwrtArchiveSHA256": hwrt_receipt.get("archive", {}).get("sha256"),
    }
    return rows, vocabulary, bindings


def _source_snapshot(uji_source: Path, hwrt: Path, hasy: Path, join: Path) -> dict[str, tuple[int, str]]:
    paths = (
        Path(uji_source),
        Path(hwrt) / "source_receipt.json",
        Path(hwrt) / "selected_records.jsonl",
        Path(hasy) / "source_receipt.json",
        Path(hasy) / "source_metadata/hasy-data-labels.csv",
        Path(hasy) / "pixel_duplicates.json",
        Path(join),
        DOMAIN_PATH,
    )
    return {str(path): _sha_file(path) for path in paths}


def prepare_training(uji_source: Path, hwrt: Path, hasy: Path, join: Path,
                     protocol: Path, output: Path) -> dict:
    protocol_bytes = _read_regular(protocol)
    if _sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen protocol")
    code = code_identity()
    source_snapshot = _source_snapshot(uji_source, hwrt, hasy, join)
    rows, vocabulary, bindings = _source_rows(uji_source, hwrt, hasy, join, "training")
    destination = _fresh_output(output)
    metadata_rows = _encode_rows(rows, destination / "fields.npy")
    metadata = {"version": TRAINING_VERSION, "vocabulary": list(vocabulary), "rows": metadata_rows}
    _write(destination / "training.json", canonical_json_bytes(metadata))
    artifacts = {name: _artifact(destination / name) for name in ("fields.npy", "training.json")}
    receipt = _receipt("training", vocabulary, artifacts, code,
        {"rows": len(rows), "ujiRows": UJI_TRAINING_ROWS, "hwrtRows": HWRT_TRAINING_ROWS}, bindings)
    if (code_identity() != code or _sha(_read_regular(protocol)) != PROTOCOL_SHA256
            or _source_snapshot(uji_source, hwrt, hasy, join) != source_snapshot):
        raise ValueError("Bound code or protocol changed during preparation")
    _write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


def _training_metadata(data_dir: Path) -> tuple[dict, dict, str]:
    receipt_bytes = _read_regular(Path(data_dir) / "data-receipt.json")
    receipt = _json(receipt_bytes, "training data receipt")
    if receipt.get("version") != DATA_VERSION or receipt.get("role") != "training":
        raise ValueError("Wrong training data receipt")
    _validate_bound_identity(receipt)
    metadata_bytes = _read_regular(Path(data_dir) / "training.json", maximum=_MAX_SOURCE_BYTES)
    expected = receipt.get("artifacts", {}).get("training.json")
    if expected != {"bytes": len(metadata_bytes), "sha256": _sha(metadata_bytes)}:
        raise ValueError("Training metadata changed")
    metadata = _json(metadata_bytes, "training metadata")
    _validate_metadata(metadata, "training", TRAINING_ROWS, receipt["vocabulary"])
    return metadata, receipt, _sha(receipt_bytes)


def prepare_development(uji_source: Path, hwrt: Path, hasy: Path, join: Path, protocol: Path,
                        training_data: Path, fit: Path, fit_receipt_sha: str, output: Path) -> dict:
    protocol_bytes = _read_regular(protocol)
    if _sha(protocol_bytes) != PROTOCOL_SHA256:
        raise ValueError("Wrong frozen protocol")
    training, training_receipt, training_sha = _training_metadata(training_data)
    vocabulary = training_receipt["vocabulary"]
    _validate_fit(fit, fit_receipt_sha, training_sha, vocabulary)  # before any source/feature work
    code = code_identity()
    source_snapshot = _source_snapshot(uji_source, hwrt, hasy, join)
    rows, current_vocabulary, bindings = _source_rows(uji_source, hwrt, hasy, join, "development")
    if list(current_vocabulary) != vocabulary:
        raise ValueError("Development vocabulary differs from training")
    destination = _fresh_output(output)
    full_rows = _encode_rows(rows, destination / "fields.npy")
    copy_reasons, copy_union = _copy_union(training["rows"], full_rows, training_sha)
    blind_rows = [{key: row[key] for key in ("opaqueID", "rasterSHA256",
        "normalizedGeometrySHA256", "fieldSHA256")} for row in full_rows]
    truth_rows = [{**row, "copyReasons": list(copy_reasons.get(row["opaqueID"], ()))}
                  for row in full_rows]
    inputs = {"version": DEVELOPMENT_INPUTS_VERSION, "vocabulary": vocabulary, "rows": blind_rows}
    truth = {"version": DEVELOPMENT_TRUTH_VERSION, "rows": truth_rows, "copyUnion": copy_union}
    _write(destination / "inputs.json", canonical_json_bytes(inputs))
    _write(destination / "truth.json", canonical_json_bytes(truth))
    artifacts = {name: _artifact(destination / name)
                 for name in ("fields.npy", "inputs.json", "truth.json")}
    receipt = _receipt("development", vocabulary, artifacts, code,
        {"rows": len(rows), "ujiRows": UJI_DEVELOPMENT_ROWS, "hwrtRows": HWRT_DEVELOPMENT_ROWS,
         "copyUnionRows": len(copy_union["affectedOpaqueIDs"])}, bindings,
        fit_receipt_sha=fit_receipt_sha, training_receipt_sha=training_sha)
    final_training, final_training_receipt, final_training_sha = _training_metadata(training_data)
    _validate_fit(fit, fit_receipt_sha, training_sha, vocabulary)
    if (final_training != training or final_training_receipt != training_receipt
            or final_training_sha != training_sha or code_identity() != code
            or _sha(_read_regular(protocol)) != PROTOCOL_SHA256
            or _source_snapshot(uji_source, hwrt, hasy, join) != source_snapshot):
        raise ValueError("Bound code or protocol changed during preparation")
    _write(destination / "data-receipt.json", canonical_json_bytes(receipt))
    return receipt


_ROW_FIELDS = {"opaqueID", "label", "source", "writer", "session", "nativeSymbolID",
               "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"}
_BLIND_FIELDS = {"opaqueID", "rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256"}


def _validate_metadata(metadata: Mapping[str, object], role: str, expected_rows: int,
                       vocabulary: Sequence[str]) -> None:
    version = TRAINING_VERSION if role == "training" else DEVELOPMENT_INPUTS_VERSION
    fields = _ROW_FIELDS if role == "training" else _BLIND_FIELDS
    if set(metadata) != {"version", "vocabulary", "rows"} or metadata["version"] != version \
            or metadata["vocabulary"] != list(vocabulary) or not isinstance(metadata["rows"], list) \
            or len(metadata["rows"]) != expected_rows or not metadata["rows"]:
        raise ValueError("Metadata coverage or vocabulary is invalid")
    seen = set()
    for row in metadata["rows"]:
        if not isinstance(row, dict) or set(row) != fields or not _digest(row.get("opaqueID")):
            raise ValueError("Malformed metadata row")
        if row["opaqueID"] in seen or any(not _digest(row.get(key)) for key in
            ("rasterSHA256", "normalizedGeometrySHA256", "fieldSHA256")):
            raise ValueError("Duplicate identity or malformed feature hash")
        seen.add(row["opaqueID"])
        if role == "training":
            if (row["label"] not in vocabulary or row["source"] not in ("uji", "hwrt")
                    or (row["source"] == "uji" and (not isinstance(row["writer"], str)
                        or row["session"] not in (1, 2) or row["nativeSymbolID"] is not None))
                    or (row["source"] == "hwrt" and (row["writer"] is not None
                        or row["session"] is not None or not isinstance(row["nativeSymbolID"], str)))):
                raise ValueError("Training source metadata is invalid")


def _load(role: str, data_dir: Path, expected_rows: int, metadata_name: str):
    directory = Path(data_dir)
    receipt_bytes = _read_regular(directory / "data-receipt.json")
    receipt = _json(receipt_bytes, "data receipt")
    expected_keys = {"version", "role", "fieldVersion", "protocolSHA256", "vocabulary",
        "vocabularySHA256", "counts", "sourceBindings", "codeSHA256", "artifacts",
        "fitReceiptSHA256", "trainingDataReceiptSHA256", "runtime", "roleGuards"}
    expected_artifacts = ({"fields.npy", "training.json"} if role == "training"
                          else {"fields.npy", "inputs.json", "truth.json"})
    if (set(receipt) != expected_keys or receipt["version"] != DATA_VERSION or receipt["role"] != role
            or receipt["protocolSHA256"] != PROTOCOL_SHA256 or receipt["fieldVersion"] != FIELD_VERSION
            or receipt["counts"].get("rows") != expected_rows or expected_rows <= 0
            or not isinstance(receipt["vocabulary"], list) or len(receipt["vocabulary"]) != 102
            or len(set(receipt["vocabulary"])) != 102
            or set(receipt["artifacts"]) != expected_artifacts
            or receipt["vocabularySHA256"] != _sha(canonical_json_bytes(receipt["vocabulary"]))
            or receipt["roleGuards"] != {"privateInkUsed": False, "reservedUJIEncoded": False,
                "truthOpenedByDevelopmentLoader": False, "modelInferencePerformed": False,
                "optimizationPerformed": False}
            or (role == "training" and (receipt["fitReceiptSHA256"] is not None
                or receipt["trainingDataReceiptSHA256"] is not None))
            or (role == "development" and (not _digest(receipt["fitReceiptSHA256"])
                or not _digest(receipt["trainingDataReceiptSHA256"])))):
        raise ValueError("Data receipt contract is invalid")
    _validate_bound_identity(receipt)
    metadata_bytes = _read_regular(directory / metadata_name, maximum=_MAX_SOURCE_BYTES)
    if receipt["artifacts"].get(metadata_name) != {"bytes": len(metadata_bytes), "sha256": _sha(metadata_bytes)}:
        raise ValueError("Metadata artifact changed")
    metadata = _json(metadata_bytes, metadata_name)
    _validate_metadata(metadata, role, expected_rows, receipt["vocabulary"])
    field_path = directory / "fields.npy"
    expected_field = receipt["artifacts"].get("fields.npy")
    if not isinstance(expected_field, dict) or _sha_file(field_path) != (expected_field.get("bytes"), expected_field.get("sha256")):
        raise ValueError("Field artifact changed")
    fields = np.load(field_path, mmap_mode="r", allow_pickle=False)
    if (not isinstance(fields, np.memmap) or fields.dtype != np.dtype("<f4")
            or fields.shape != (expected_rows, *FIELD_SHAPE) or not fields.flags.c_contiguous
            or fields.size == 0):
        raise ValueError("Field artifact shape/dtype/storage is invalid")
    return fields, metadata, receipt


def load_training(data_dir: Path):
    """Load only the completed training fields, metadata, and receipt."""

    return _load("training", data_dir, TRAINING_ROWS, "training.json")


def load_development_inputs(data_dir: Path):
    """Load blind development inputs; this function never opens ``truth.json``."""

    return _load("development", data_dir, DEVELOPMENT_ROWS, "inputs.json")


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uji-source", type=Path, required=True)
    parser.add_argument("--hwrt-intake", type=Path, required=True)
    parser.add_argument("--hasy-intake", type=Path, required=True)
    parser.add_argument("--join-report", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--role", choices=("training", "development"), required=True)
    parser.add_argument("--training-data", type=Path)
    parser.add_argument("--fit", type=Path)
    parser.add_argument("--fit-receipt-sha256")
    args = parser.parse_args(argv)
    if args.role == "training":
        if args.training_data is not None or args.fit is not None or args.fit_receipt_sha256 is not None:
            raise ValueError("Training preparation cannot consume fitted/development artifacts")
        receipt = prepare_training(args.uji_source, args.hwrt_intake, args.hasy_intake,
                                   args.join_report, args.protocol, args.output)
    else:
        if args.training_data is None or args.fit is None or args.fit_receipt_sha256 is None:
            raise ValueError("Development preparation requires training data and completed fit")
        receipt = prepare_development(args.uji_source, args.hwrt_intake, args.hasy_intake,
            args.join_report, args.protocol, args.training_data, args.fit,
            args.fit_receipt_sha256, args.output)
    print(json.dumps({"role": receipt["role"], **receipt["counts"]}, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
