"""Materialize the frozen training32 source plan into label-free rasters.

The predictor-facing loader reads only the forward plan, data receipt, and
raster archive.  Ground-truth labels remain in a separately hashed artifact
that this module's shared loader never opens.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import platform
import re
from typing import Callable, Mapping, Sequence

import numpy as np

from ..contracts import strict_json_loads
from ..features import FeatureEncodingError, RASTER_HEIGHT, RASTER_WIDTH, rasterize
from . import personal_support_crossfit as crossfit
from . import personal_support_match_defer_source as filtered_source
from .uji_personal import SOURCE_SHA256, Sample, trajectory_fingerprint


VERSION = "personal-support-match-defer-raster-bundle-v1"
TRUTH_VERSION = "personal-support-match-defer-score-truth-v1"
PROTOCOL_PATH = "docs/personal-support-match-defer-protocol-2026-10-03.md"
PROTOCOL_SHA256 = "b8bc1c371f3e5cfd60c8f8867e8380148d93d7105ff62289c4ff1b02484d5c33"
FORWARD_PLAN_SHA256 = "c6fa6c953a87c471c18316cfa39f818869a9b50ac8327363e921486ed9988995"
PLAN_RECEIPT_SHA256 = "db84ea5c90d7844ae6a4691eac1e62847c5667a5913b086e6400c9a4c4969291"
RAW_ROWS = 6_208
STORED_ROWS = 1_344
UNREQUESTED_METADATA_FAILURES = 23
ROOT = Path(__file__).resolve().parents[3]
_SHA256 = re.compile(r"[0-9a-f]{64}")
_MAX_METADATA_BYTES = 64 * 1024 * 1024
_MAX_RASTER_BYTES = 256 * 1024 * 1024

CODE_PATHS = (
    PROTOCOL_PATH,
    "recognition_ml/ichart_recognition_ml/contracts.py",
    "recognition_ml/ichart_recognition_ml/errors.py",
    "recognition_ml/ichart_recognition_ml/features.py",
    "recognition_ml/ichart_recognition_ml/schema.py",
    "recognition_ml/ichart_recognition_ml/research/uji_personal.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_crossfit.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_source.py",
    "recognition_ml/tests/test_personal_support_match_defer_source.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_plan.py",
    "recognition_ml/tests/test_personal_support_match_defer_plan.py",
    "recognition_ml/ichart_recognition_ml/research/personal_support_match_defer_data.py",
    "recognition_ml/tests/test_personal_support_match_defer_data.py",
)

ROLE_GUARDS = {
    "training32CoordinatesOnly": True,
    "developmentOrReservedCoordinatesConstructed": False,
    "labelsInRasterArchive": False,
    "truthSeparateFromLoader": True,
    "modelInferencePerformed": False,
    "optimizationPerformed": False,
    "privateInkUsed": False,
    "productionEligible": False,
}


def _canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def _sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _digest(value: object) -> bool:
    return isinstance(value, str) and _SHA256.fullmatch(value) is not None


def _read_regular(path: Path, *, maximum: int = _MAX_METADATA_BYTES) -> bytes:
    path = Path(path)
    if (not path.is_absolute() or path.resolve() != path or path.is_symlink() or not path.is_file()
            or not 0 < path.stat().st_size <= maximum):
        raise ValueError("Bounded regular artifact is required")
    return path.read_bytes()


def _parsed(data: bytes, name: str) -> dict:
    value = strict_json_loads(data.decode(), name)
    if not isinstance(value, dict) or _canonical(value) != data:
        raise ValueError(f"{name} must be canonical JSON")
    return value


def code_identity() -> dict[str, str]:
    result = {name: _sha(_read_regular(ROOT / name)) for name in CODE_PATHS}
    if result[PROTOCOL_PATH] != PROTOCOL_SHA256:
        raise ValueError("Frozen protocol changed")
    return result


def _validate_forward_plan(forward: Mapping[str, object]) -> None:
    if (not isinstance(forward, Mapping) or forward.get("version") != "personal-support-match-defer-source-plan-v1"
            or forward.get("protocolSHA256") != PROTOCOL_SHA256
            or forward.get("bindings", {}).get("sourceSHA256") != SOURCE_SHA256
            or forward.get("roleGuards", {}).get("developmentOrReservedSamplesOpened") is not False
            or forward.get("roleGuards", {}).get("rastersConstructed") is not False):
        raise ValueError("Wrong frozen forward-plan boundary")
    ledger = forward.get("sourceLedger")
    if not isinstance(ledger, list) or not ledger:
        raise ValueError("Source ledger is required")
    required = {"sourceIndex", "sourceKey", "writer", "session", "rawRasterSHA256", "trajectorySHA256",
                "storedRasterSHA256", "storedTrajectorySHA256", "storedFailure"}
    for index, row in enumerate(ledger):
        if (not isinstance(row, dict) or set(row) != required or row["sourceIndex"] != index
                or not _digest(row["sourceKey"]) or not _digest(row["rawRasterSHA256"])
                or not _digest(row["trajectorySHA256"]) or row["session"] not in (1, 2)
                or not isinstance(row["writer"], str)):
            raise ValueError("Malformed source ledger")
        available = row["storedFailure"] is None
        if available != (_digest(row["storedRasterSHA256"]) and _digest(row["storedTrajectorySHA256"])):
            raise ValueError("Stored metadata availability contradiction")
        if not available and not isinstance(row["storedFailure"], str):
            raise ValueError("Stored failure must remain explicit")
    if not isinstance(forward.get("forward"), dict) or not forward["forward"]:
        raise ValueError("Forward episode schedules are required")


def load_forward_plan(plan_directory: Path) -> dict:
    """Read only the fixed plan receipt and label-free forward plan."""

    directory = Path(plan_directory)
    forward_bytes = _read_regular(directory / "forward-plan.json")
    receipt_bytes = _read_regular(directory / "plan-receipt.json")
    if _sha(forward_bytes) != FORWARD_PLAN_SHA256 or _sha(receipt_bytes) != PLAN_RECEIPT_SHA256:
        raise ValueError("Frozen source-plan artifacts changed")
    forward = _parsed(forward_bytes, "forward-plan")
    receipt = _parsed(receipt_bytes, "plan-receipt")
    if (receipt.get("artifacts", {}).get("forward-plan.json") != FORWARD_PLAN_SHA256
            or receipt.get("protocolSHA256") != PROTOCOL_SHA256
            or receipt.get("bindings") != forward.get("bindings")):
        raise ValueError("Source-plan receipt binding changed")
    _validate_forward_plan(forward)
    return forward


def requested_stored_indices(forward: Mapping[str, object]) -> tuple[int, ...]:
    _validate_forward_plan(forward)
    ledger = forward["sourceLedger"]
    requested: set[int] = set()

    def retain(support_rows: object) -> None:
        if not isinstance(support_rows, list):
            raise ValueError("Support rows are required")
        for support in support_rows:
            if not isinstance(support, dict) or not isinstance(support.get("sourceIndex"), int):
                raise ValueError("Malformed support source reference")
            index = support["sourceIndex"]
            if not 0 <= index < len(ledger):
                raise ValueError("Support source index outside ledger")
            row = ledger[index]
            for key in ("sourceKey", "rawRasterSHA256", "trajectorySHA256", "storedRasterSHA256",
                        "storedTrajectorySHA256", "storedFailure"):
                if support.get(key) != row[key]:
                    raise ValueError("Support reference does not match source ledger")
            requested.add(index)

    for direction in forward["forward"].values():
        if not isinstance(direction, dict):
            raise ValueError("Malformed direction schedule")
        for episode in direction.get("trainingEpisodes", ()):
            retain(episode.get("support"))
        for episode in direction.get("heldoutEpisodes", ()):
            if not isinstance(episode, dict):
                raise ValueError("Malformed heldout schedule")
            retain(episode.get("trueSupport", {}).get("support"))
            retain(episode.get("wrongSupport", {}).get("support"))
    if not requested:
        raise ValueError("No stored support was requested")
    return tuple(sorted(requested))


def build_raster_payload(
    samples: Sequence[Sample],
    forward: Mapping[str, object],
    *,
    setup_shape: Callable = crossfit.setup_shape,
) -> tuple[dict[str, np.ndarray], dict, dict]:
    """Pure materialization core used by the strict entry and synthetic tests."""

    _validate_forward_plan(forward)
    ledger = forward["sourceLedger"]
    by_key = {_sha(sample.identity.encode()): sample for sample in samples}
    if len(by_key) != len(samples) or set(by_key) != {row["sourceKey"] for row in ledger}:
        raise ValueError("Filtered samples do not exactly cover the source ledger")
    requested = requested_stored_indices(forward)
    requested_set = set(requested)
    raw = np.empty((len(ledger), 1, RASTER_HEIGHT, RASTER_WIDTH), dtype=np.uint8)
    stored_pixels: list[np.ndarray] = []
    stored_indices: list[int] = []
    truth_rows = []
    requested_failures = 0
    for row in ledger:
        index = row["sourceIndex"]
        sample = by_key[row["sourceKey"]]
        if sample.writer != row["writer"] or sample.session != row["session"]:
            raise ValueError("Source-key metadata does not match filtered sample")
        try:
            raw_pixels = rasterize(sample.strokes).pixels
        except FeatureEncodingError as exc:
            raise ValueError("Raw source raster is unavailable") from exc
        if _sha(raw_pixels) != row["rawRasterSHA256"] or trajectory_fingerprint(sample) != row["trajectorySHA256"]:
            raise ValueError("Raw source feature hash changed")
        raw[index, 0] = np.frombuffer(raw_pixels, dtype=np.uint8).reshape(RASTER_HEIGHT, RASTER_WIDTH)
        truth_rows.append({"sourceIndex": index, "intended": sample.label})

    for index in requested:
        row, sample = ledger[index], by_key[ledger[index]["sourceKey"]]
        shape = setup_shape(sample.strokes)
        stored_bytes = None
        failure = None
        if shape is None:
            failure = "PersonalInkShape-unavailable"
        else:
            try:
                stored_bytes = rasterize(shape).pixels
            except FeatureEncodingError:
                failure = "feature-raster-unavailable"
        if failure is not None:
            requested_failures += 1
            if row["storedFailure"] != failure or row["storedRasterSHA256"] is not None or row["storedTrajectorySHA256"] is not None:
                raise ValueError("Requested stored failure changed")
            continue
        assert shape is not None and stored_bytes is not None
        stored_sample = Sample(sample.writer, sample.session, sample.label, shape)
        if (row["storedFailure"] is not None or _sha(stored_bytes) != row["storedRasterSHA256"]
                or trajectory_fingerprint(stored_sample) != row["storedTrajectorySHA256"]):
            raise ValueError("Requested stored feature hash changed")
        stored_indices.append(index)
        stored_pixels.append(np.frombuffer(stored_bytes, dtype=np.uint8).copy().reshape(1, RASTER_HEIGHT, RASTER_WIDTH))
    stored = np.stack(stored_pixels) if stored_pixels else np.empty((0, 1, RASTER_HEIGHT, RASTER_WIDTH), dtype=np.uint8)
    indices = np.asarray(stored_indices, dtype=np.int64)
    arrays = {"raw_rasters": raw, "stored_rasters": stored, "stored_source_indices": indices}
    truth = {"version": TRUTH_VERSION, "sourceSHA256": SOURCE_SHA256,
             "forwardPlanSHA256": _sha(_canonical(forward)), "rows": truth_rows}
    facts = {"rawRows": len(ledger), "requestedStoredRows": len(requested), "storedRows": len(indices),
             "requestedStoredFailures": requested_failures,
             "unrequestedRows": len(ledger) - len(requested),
             "unrequestedMetadataFailures": sum(i not in requested_set and row["storedFailure"] is not None
                                                  for i, row in enumerate(ledger))}
    return arrays, truth, facts


def _npz_bytes(arrays: Mapping[str, np.ndarray]) -> bytes:
    buffer = io.BytesIO()
    np.savez(buffer, **arrays)
    return buffer.getvalue()


def _new_output(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or path.parent.resolve() != path.parent or not path.parent.is_dir()
            or path.exists() or ROOT == path or ROOT in path.parents):
        raise ValueError("Fresh outside-repository output directory required")
    path.mkdir(mode=0o700)
    return path


def _write_exclusive(path: Path, data: bytes) -> None:
    with path.open("xb") as stream:
        stream.write(data)


def _receipt(
    arrays: Mapping[str, np.ndarray], truth_bytes: bytes, raster_bytes: bytes,
    facts: Mapping[str, int], forward_sha256: str, code: Mapping[str, str],
) -> dict:
    return {"version": VERSION, "protocolSHA256": PROTOCOL_SHA256, "sourceSHA256": SOURCE_SHA256,
        "parentReceiptSHA256": filtered_source.PARENT_RECEIPT_SHA256,
        "parentMetadataSHA256": filtered_source.PARENT_METADATA_SHA256,
        "forwardPlanSHA256": forward_sha256, "planReceiptSHA256": PLAN_RECEIPT_SHA256,
        "codeSHA256": dict(code), "rastersFile": "rasters.npz", "rastersSHA256": _sha(raster_bytes),
        "rawRastersSHA256": _sha(arrays["raw_rasters"].tobytes(order="C")),
        "storedRastersSHA256": _sha(arrays["stored_rasters"].tobytes(order="C")),
        "storedSourceIndicesSHA256": _sha(arrays["stored_source_indices"].tobytes(order="C")),
        "truthFile": "score-truth.json", "truthSHA256": _sha(truth_bytes), **dict(facts),
        "rasterShape": [1, RASTER_HEIGHT, RASTER_WIDTH],
        "runtime": {"python": platform.python_version(), "numpy": str(np.__version__)},
        "roleGuards": dict(ROLE_GUARDS)}


def materialize(
    source_path: Path, parent_receipt_path: Path, plan_directory: Path, output: Path,
) -> dict:
    forward = load_forward_plan(plan_directory)
    forward_bytes = _canonical(forward)
    parent_bytes = _read_regular(parent_receipt_path)
    parent = _parsed(parent_bytes, "parent-receipt")
    if _sha(parent_bytes) != filtered_source.PARENT_RECEIPT_SHA256:
        raise ValueError("Pinned parent receipt changed")
    code = code_identity()
    samples = filtered_source.load_official_training_source(
        Path(source_path), parent, receipt_sha256=filtered_source.PARENT_RECEIPT_SHA256)
    arrays, truth, facts = build_raster_payload(samples, forward)
    if facts != {"rawRows": RAW_ROWS, "requestedStoredRows": STORED_ROWS, "storedRows": STORED_ROWS,
                  "requestedStoredFailures": 0, "unrequestedRows": RAW_ROWS - STORED_ROWS,
                  "unrequestedMetadataFailures": UNREQUESTED_METADATA_FAILURES}:
        raise ValueError("Frozen materialization counts changed")
    raster_bytes, truth_bytes = _npz_bytes(arrays), _canonical(truth)
    receipt = _receipt(arrays, truth_bytes, raster_bytes, facts, FORWARD_PLAN_SHA256, code)
    destination = _new_output(output)
    _write_exclusive(destination / "rasters.npz", raster_bytes)
    _write_exclusive(destination / "score-truth.json", truth_bytes)
    if (load_forward_plan(plan_directory) != forward or _read_regular(parent_receipt_path) != parent_bytes
            or code_identity() != code or _sha(_read_regular(Path(source_path), maximum=_MAX_RASTER_BYTES)) != SOURCE_SHA256):
        raise ValueError("Materialization inputs changed before publication")
    _write_exclusive(destination / "data-receipt.json", _canonical(receipt))
    return receipt


def _load_raster_bundle(
    data_directory: Path, forward: Mapping[str, object], *, expected_raw_rows: int,
    expected_stored_rows: int, expected_forward_sha256: str, require_current_code: bool,
) -> tuple[dict[str, np.ndarray], dict]:
    _validate_forward_plan(forward)
    receipt_bytes = _read_regular(Path(data_directory) / "data-receipt.json")
    receipt = _parsed(receipt_bytes, "data-receipt")
    raster_bytes = _read_regular(Path(data_directory) / "rasters.npz", maximum=_MAX_RASTER_BYTES)
    required = {"version", "protocolSHA256", "sourceSHA256", "parentReceiptSHA256", "parentMetadataSHA256",
        "forwardPlanSHA256", "planReceiptSHA256", "codeSHA256", "rastersFile", "rastersSHA256",
        "rawRastersSHA256", "storedRastersSHA256", "storedSourceIndicesSHA256", "truthFile", "truthSHA256",
        "rawRows", "requestedStoredRows", "storedRows", "requestedStoredFailures", "unrequestedRows",
        "unrequestedMetadataFailures", "rasterShape", "runtime", "roleGuards"}
    if (set(receipt) != required or receipt["version"] != VERSION or receipt["protocolSHA256"] != PROTOCOL_SHA256
            or receipt["sourceSHA256"] != SOURCE_SHA256
            or receipt["parentReceiptSHA256"] != filtered_source.PARENT_RECEIPT_SHA256
            or receipt["parentMetadataSHA256"] != filtered_source.PARENT_METADATA_SHA256
            or receipt["forwardPlanSHA256"] != expected_forward_sha256
            or _sha(_canonical(forward)) != expected_forward_sha256
            or receipt["planReceiptSHA256"] != PLAN_RECEIPT_SHA256
            or receipt["rastersFile"] != "rasters.npz" or receipt["truthFile"] != "score-truth.json"
            or not _digest(receipt["truthSHA256"]) or _sha(raster_bytes) != receipt["rastersSHA256"]
            or receipt["rawRows"] != expected_raw_rows or receipt["storedRows"] != expected_stored_rows
            or receipt["rasterShape"] != [1, RASTER_HEIGHT, RASTER_WIDTH]
            or (require_current_code and receipt["codeSHA256"] != code_identity())):
        raise ValueError("Raster bundle receipt binding changed")
    with np.load(io.BytesIO(raster_bytes), allow_pickle=False) as archive:
        if set(archive.files) != {"raw_rasters", "stored_rasters", "stored_source_indices"}:
            raise ValueError("Raster archive fields changed")
        arrays = {name: archive[name].copy() for name in archive.files}
    raw, stored, indices = arrays["raw_rasters"], arrays["stored_rasters"], arrays["stored_source_indices"]
    requested = requested_stored_indices(forward)
    expected_indices = tuple(i for i in requested if forward["sourceLedger"][i]["storedFailure"] is None)
    unrequested_failures = sum(
        index not in set(requested) and row["storedFailure"] is not None
        for index, row in enumerate(forward["sourceLedger"])
    )
    if (raw.shape != (expected_raw_rows, 1, RASTER_HEIGHT, RASTER_WIDTH) or raw.dtype != np.uint8
            or stored.shape != (expected_stored_rows, 1, RASTER_HEIGHT, RASTER_WIDTH) or stored.dtype != np.uint8
            or indices.shape != (expected_stored_rows,) or indices.dtype != np.int64
            or tuple(indices.tolist()) != expected_indices or receipt["requestedStoredRows"] != len(requested)
            or receipt["requestedStoredFailures"] != len(requested) - len(expected_indices)
            or receipt["unrequestedRows"] != expected_raw_rows - len(requested)
            or receipt["unrequestedMetadataFailures"] != unrequested_failures
            or receipt["roleGuards"] != ROLE_GUARDS
            or not isinstance(receipt["runtime"], dict) or set(receipt["runtime"]) != {"python", "numpy"}
            or not all(isinstance(value, str) and value for value in receipt["runtime"].values())
            or _sha(raw.tobytes(order="C")) != receipt["rawRastersSHA256"]
            or _sha(stored.tobytes(order="C")) != receipt["storedRastersSHA256"]
            or _sha(indices.tobytes(order="C")) != receipt["storedSourceIndicesSHA256"]):
        raise ValueError("Raster bundle shape, compact selection, or byte hash changed")
    ledger = forward["sourceLedger"]
    if any(_sha(raw[index].tobytes(order="C")) != row["rawRasterSHA256"] for index, row in enumerate(ledger)):
        raise ValueError("Raw raster row no longer matches source ledger")
    if any(_sha(stored[position].tobytes(order="C")) != ledger[index]["storedRasterSHA256"]
           for position, index in enumerate(expected_indices)):
        raise ValueError("Stored raster row no longer matches source ledger")
    return arrays, receipt


def load_raster_bundle(data_directory: Path, forward_plan: Mapping[str, object]) -> tuple[dict[str, np.ndarray], dict]:
    """Load label-free rasters; deliberately never read score-truth.json."""

    return _load_raster_bundle(data_directory, forward_plan, expected_raw_rows=RAW_ROWS,
        expected_stored_rows=STORED_ROWS, expected_forward_sha256=FORWARD_PLAN_SHA256,
        require_current_code=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--parent-receipt", type=Path, required=True)
    parser.add_argument("--source-plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = materialize(args.source, args.parent_receipt, args.source_plan, args.output)
    print(json.dumps({"output": str(args.output), "rawRows": receipt["rawRows"],
                      "storedRows": receipt["storedRows"], "rastersSHA256": receipt["rastersSHA256"]},
                     sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
