"""Strict RecognitionStudy trajectory-to-feature artifact bridge.

This importer performs mechanical packet validation and deterministic feature
generation only.  It does not attach a chord label, establish consent or
provenance, assign a corpus split, or make a capture training/evaluation
eligible.
"""

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Mapping, Optional, Sequence, Set, Tuple

from .contracts import canonical_json_bytes, strict_json_loads
from .errors import ContractError
from .features import InkBounds, InkPoint, InkStroke, encode_feature_artifacts


PACKET_FORMAT_VERSION = "ink-trajectory-packet-v1"
PACKET_COORDINATE_SPACE = "transformed-prepared-drawing"
COMMIT_SCHEMA_VERSION = "recognition-study-local-commit-v1"

MAXIMUM_CANONICAL_PACKET_BYTE_COUNT = 4 * 1024 * 1024
MAXIMUM_COMMIT_BYTE_COUNT = 8 * 1024
MAXIMUM_ENVELOPE_BYTE_COUNT = 64 * 1024
MAXIMUM_STROKE_COUNT = 256
MAXIMUM_POINT_COUNT_PER_STROKE = 8_192
MAXIMUM_TOTAL_POINT_COUNT = 32_768

_PACKET_FIELDS = {"coordinateSpace", "formatVersion", "strokes"}
_STROKE_FIELDS = {"bounds", "creationTimeOffset", "points"}
_BOUNDS_FIELDS = {"maxX", "maxY", "minX", "minY"}
_POINT_FIELDS = {"timeOffset", "x", "y"}
_COMMIT_FIELDS = {
    "authorizationID",
    "envelopeByteCount",
    "envelopeSHA256",
    "localCaptureID",
    "localSessionID",
    "schemaVersion",
    "trajectoryByteCount",
    "trajectorySHA256",
}
_LOWER_HEX_16 = re.compile(r"^[0-9a-f]{16}$")
_LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
_UINT64_MAXIMUM = (1 << 64) - 1


@dataclass(frozen=True)
class StudyCommitBinding:
    local_session_id: str
    authorization_id: str
    local_capture_id: str
    trajectory_sha256: str
    trajectory_byte_count: int
    envelope_sha256: str
    envelope_byte_count: int


@dataclass(frozen=True)
class StudyFeatureImportReceipt:
    packet_sha256: str
    packet_byte_count: int
    trajectory_sha256: str
    trajectory_byte_count: int
    raster_sha256: str
    raster_byte_count: int
    local_capture_id: Optional[str]

    def as_dict(self) -> Dict[str, object]:
        value = {
            "packet_byte_count": self.packet_byte_count,
            "packet_sha256": self.packet_sha256,
            "raster_byte_count": self.raster_byte_count,
            "raster_sha256": self.raster_sha256,
            "trajectory_byte_count": self.trajectory_byte_count,
            "trajectory_sha256": self.trajectory_sha256,
        }
        if self.local_capture_id is not None:
            value["local_capture_id"] = self.local_capture_id
        return value


def decode_canonical_study_packet(packet_data: bytes) -> Tuple[InkStroke, ...]:
    """Decode one exact Swift canonical trajectory packet into feature strokes."""

    _require_byte_budget(
        packet_data,
        MAXIMUM_CANONICAL_PACKET_BYTE_COUNT,
        "trajectory.json",
    )
    value = _decode_canonical_json(packet_data, "trajectory.json")
    packet = _require_object(value, "trajectory.json")
    _require_exact_fields(packet, _PACKET_FIELDS, "trajectory.json")
    _require_fixed_string(
        packet["formatVersion"],
        PACKET_FORMAT_VERSION,
        "trajectory.json.formatVersion",
    )
    _require_fixed_string(
        packet["coordinateSpace"],
        PACKET_COORDINATE_SPACE,
        "trajectory.json.coordinateSpace",
    )

    encoded_strokes = packet["strokes"]
    if not isinstance(encoded_strokes, list):
        _refuse("invalid_array", "trajectory.json.strokes", "must be an array")
    if len(encoded_strokes) > MAXIMUM_STROKE_COUNT:
        _refuse(
            "stroke_complexity_exceeded",
            "trajectory.json.strokes",
            f"limit {MAXIMUM_STROKE_COUNT}, actual {len(encoded_strokes)}",
        )

    total_point_count = 0
    strokes = []
    for stroke_index, encoded_stroke in enumerate(encoded_strokes):
        stroke_path = f"trajectory.json.strokes[{stroke_index}]"
        stroke_value = _require_object(encoded_stroke, stroke_path)
        _require_exact_fields(stroke_value, _STROKE_FIELDS, stroke_path)

        bounds_path = f"{stroke_path}.bounds"
        bounds_value = _require_object(stroke_value["bounds"], bounds_path)
        _require_exact_fields(bounds_value, _BOUNDS_FIELDS, bounds_path)
        bounds = InkBounds(
            min_x=_decode_geometry(bounds_value["minX"], f"{bounds_path}.minX"),
            min_y=_decode_geometry(bounds_value["minY"], f"{bounds_path}.minY"),
            max_x=_decode_geometry(bounds_value["maxX"], f"{bounds_path}.maxX"),
            max_y=_decode_geometry(bounds_value["maxY"], f"{bounds_path}.maxY"),
        )

        encoded_points = stroke_value["points"]
        if not isinstance(encoded_points, list):
            _refuse("invalid_array", f"{stroke_path}.points", "must be an array")
        if len(encoded_points) > MAXIMUM_POINT_COUNT_PER_STROKE:
            _refuse(
                "point_complexity_exceeded",
                f"{stroke_path}.points",
                f"limit {MAXIMUM_POINT_COUNT_PER_STROKE}, actual {len(encoded_points)}",
            )
        total_point_count += len(encoded_points)
        if total_point_count > MAXIMUM_TOTAL_POINT_COUNT:
            _refuse(
                "point_complexity_exceeded",
                "trajectory.json.strokes",
                f"limit {MAXIMUM_TOTAL_POINT_COUNT}, actual {total_point_count}",
            )

        points = []
        for point_index, encoded_point in enumerate(encoded_points):
            point_path = f"{stroke_path}.points[{point_index}]"
            point_value = _require_object(encoded_point, point_path)
            _require_exact_fields(point_value, _POINT_FIELDS, point_path)
            points.append(
                InkPoint(
                    x=_decode_geometry(point_value["x"], f"{point_path}.x"),
                    y=_decode_geometry(point_value["y"], f"{point_path}.y"),
                    time_offset=_decode_timing(
                        point_value["timeOffset"], f"{point_path}.timeOffset"
                    ),
                )
            )

        strokes.append(
            InkStroke(
                points=tuple(points),
                bounds=bounds,
                creation_time_offset=_decode_timing(
                    stroke_value["creationTimeOffset"],
                    f"{stroke_path}.creationTimeOffset",
                ),
            )
        )

    if total_point_count == 0:
        _refuse(
            "empty_capture",
            "trajectory.json.strokes",
            "a study capture must contain at least one prepared point",
        )
    return tuple(strokes)


def decode_canonical_commit(commit_data: bytes) -> StudyCommitBinding:
    """Decode and validate an optional local Study commit marker."""

    _require_byte_budget(commit_data, MAXIMUM_COMMIT_BYTE_COUNT, "commit.json")
    value = _decode_canonical_json(commit_data, "commit.json")
    commit = _require_object(value, "commit.json")
    _require_exact_fields(commit, _COMMIT_FIELDS, "commit.json")
    _require_fixed_string(
        commit["schemaVersion"], COMMIT_SCHEMA_VERSION, "commit.json.schemaVersion"
    )
    trajectory_byte_count = _require_uint64(
        commit["trajectoryByteCount"], "commit.json.trajectoryByteCount"
    )
    envelope_byte_count = _require_uint64(
        commit["envelopeByteCount"], "commit.json.envelopeByteCount"
    )
    if not 0 < trajectory_byte_count <= MAXIMUM_CANONICAL_PACKET_BYTE_COUNT:
        _refuse(
            "invalid_byte_count",
            "commit.json.trajectoryByteCount",
            f"must be in 1...{MAXIMUM_CANONICAL_PACKET_BYTE_COUNT}",
        )
    if not 0 < envelope_byte_count <= MAXIMUM_ENVELOPE_BYTE_COUNT:
        _refuse(
            "invalid_byte_count",
            "commit.json.envelopeByteCount",
            f"must be in 1...{MAXIMUM_ENVELOPE_BYTE_COUNT}",
        )
    return StudyCommitBinding(
        local_session_id=_require_canonical_uuid(
            commit["localSessionID"], "commit.json.localSessionID"
        ),
        authorization_id=_require_canonical_uuid(
            commit["authorizationID"], "commit.json.authorizationID"
        ),
        local_capture_id=_require_canonical_uuid(
            commit["localCaptureID"], "commit.json.localCaptureID"
        ),
        trajectory_sha256=_require_sha256(
            commit["trajectorySHA256"], "commit.json.trajectorySHA256"
        ),
        trajectory_byte_count=trajectory_byte_count,
        envelope_sha256=_require_sha256(
            commit["envelopeSHA256"], "commit.json.envelopeSHA256"
        ),
        envelope_byte_count=envelope_byte_count,
    )


def import_study_packet(
    packet_path: Path,
    trajectory_output_path: Path,
    raster_output_path: Path,
    expected_packet_sha256: Optional[str] = None,
    commit_path: Optional[Path] = None,
) -> StudyFeatureImportReceipt:
    """Validate one packet and exclusively create its two feature artifacts."""

    packet_path = Path(packet_path)
    trajectory_output_path = Path(trajectory_output_path)
    raster_output_path = Path(raster_output_path)
    if _normalized_path(trajectory_output_path) == _normalized_path(raster_output_path):
        _refuse(
            "duplicate_output_path",
            "outputs",
            "trajectory and raster outputs must be different paths",
        )

    packet_data = _read_bounded(
        packet_path,
        MAXIMUM_CANONICAL_PACKET_BYTE_COUNT,
        "trajectory.json",
    )
    packet_sha256 = hashlib.sha256(packet_data).hexdigest()
    if expected_packet_sha256 is not None:
        expected = _require_sha256(expected_packet_sha256, "expected_packet_sha256")
        if expected != packet_sha256:
            _refuse(
                "packet_digest_mismatch",
                "trajectory.json",
                f"expected {expected}, got {packet_sha256}",
            )

    commit = None  # type: Optional[StudyCommitBinding]
    if commit_path is not None:
        commit_data = _read_bounded(
            Path(commit_path), MAXIMUM_COMMIT_BYTE_COUNT, "commit.json"
        )
        commit = decode_canonical_commit(commit_data)
        if commit.trajectory_sha256 != packet_sha256:
            _refuse(
                "commit_digest_mismatch",
                "commit.json.trajectorySHA256",
                f"expected {commit.trajectory_sha256}, got {packet_sha256}",
            )
        if commit.trajectory_byte_count != len(packet_data):
            _refuse(
                "commit_byte_count_mismatch",
                "commit.json.trajectoryByteCount",
                f"expected {commit.trajectory_byte_count}, got {len(packet_data)}",
            )

    strokes = decode_canonical_study_packet(packet_data)
    trajectory, raster = encode_feature_artifacts(strokes)
    trajectory_data = trajectory.to_bytes()
    raster_data = raster.to_bytes()

    _write_exclusive_pair(
        trajectory_output_path,
        trajectory_data,
        raster_output_path,
        raster_data,
    )
    return StudyFeatureImportReceipt(
        packet_sha256=packet_sha256,
        packet_byte_count=len(packet_data),
        trajectory_sha256=hashlib.sha256(trajectory_data).hexdigest(),
        trajectory_byte_count=len(trajectory_data),
        raster_sha256=hashlib.sha256(raster_data).hexdigest(),
        raster_byte_count=len(raster_data),
        local_capture_id=None if commit is None else commit.local_capture_id,
    )


def entrypoint(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Strictly convert one RecognitionStudy trajectory.json packet into "
            "deterministic feature artifacts. This does not qualify corpus data."
        )
    )
    parser.add_argument("--trajectory-json", required=True, type=Path)
    parser.add_argument("--trajectory-output", required=True, type=Path)
    parser.add_argument("--raster-output", required=True, type=Path)
    parser.add_argument("--expected-packet-sha256")
    parser.add_argument("--commit-json", type=Path)
    arguments = parser.parse_args(argv)
    try:
        receipt = import_study_packet(
            packet_path=arguments.trajectory_json,
            trajectory_output_path=arguments.trajectory_output,
            raster_output_path=arguments.raster_output,
            expected_packet_sha256=arguments.expected_packet_sha256,
            commit_path=arguments.commit_json,
        )
    except (ContractError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(
        json.dumps(receipt.as_dict(), sort_keys=True, separators=(",", ":")),
        file=sys.stdout,
    )
    return 0


def _decode_canonical_json(payload: bytes, path: str) -> object:
    try:
        text = payload.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        _refuse("invalid_utf8", path, str(error))
    value = strict_json_loads(text, path)
    try:
        encoded = canonical_json_bytes(value)
    except (TypeError, ValueError, UnicodeError) as error:
        _refuse("invalid_json_value", path, str(error))
    if encoded != payload:
        _refuse("noncanonical_json", path, "bytes do not match canonical encoding")
    return value


def _require_object(value: object, path: str) -> Mapping[str, object]:
    if not isinstance(value, dict):
        _refuse("invalid_object", path, "must be an object")
    return value


def _require_exact_fields(
    value: Mapping[str, object], expected: Set[str], path: str
) -> None:
    missing = sorted(expected.difference(value.keys()))
    if missing:
        _refuse("missing_field", path, ", ".join(missing))
    unknown = sorted(set(value.keys()).difference(expected))
    if unknown:
        _refuse("unknown_field", path, ", ".join(unknown))


def _require_fixed_string(value: object, expected: str, path: str) -> str:
    if not isinstance(value, str):
        _refuse("invalid_string", path, "must be a string")
    if value != expected:
        _refuse("fixed_value_mismatch", path, f"expected {expected}, got {value}")
    return value


def _decode_geometry(value: object, path: str) -> float:
    decoded = _decode_bit_pattern(value, path)
    if not math.isfinite(decoded):
        _refuse("nonfinite_geometry", path, "geometry must be finite")
    return decoded


def _decode_timing(value: object, path: str) -> Optional[float]:
    timing = _require_object(value, path)
    state = timing.get("state")
    if state == "missing":
        _require_exact_fields(timing, {"state"}, path)
        return None
    if state not in ("finite", "nonFinite"):
        _refuse(
            "invalid_timing_state",
            f"{path}.state",
            "must be missing, finite, or nonFinite",
        )
    _require_exact_fields(timing, {"bitPattern", "state"}, path)
    decoded = _decode_bit_pattern(timing["bitPattern"], f"{path}.bitPattern")
    if math.isfinite(decoded) != (state == "finite"):
        _refuse(
            "timing_state_mismatch",
            path,
            "timing state does not match its IEEE-754 value",
        )
    return decoded


def _decode_bit_pattern(value: object, path: str) -> float:
    if not isinstance(value, str) or _LOWER_HEX_16.fullmatch(value) is None:
        _refuse(
            "invalid_bit_pattern",
            path,
            "must be 16 lowercase hexadecimal digits",
        )
    return struct.unpack(">d", bytes.fromhex(value))[0]


def _require_canonical_uuid(value: object, path: str) -> str:
    if not isinstance(value, str):
        _refuse("invalid_uuid", path, "must be canonical UUID text")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        _refuse("invalid_uuid", path, "must be canonical UUID text")
    if str(parsed) != value:
        _refuse("invalid_uuid", path, "must be lowercase canonical UUID text")
    return value


def _require_sha256(value: object, path: str) -> str:
    if not isinstance(value, str) or _LOWER_HEX_64.fullmatch(value) is None:
        _refuse(
            "invalid_sha256",
            path,
            "must be 64 lowercase hexadecimal characters",
        )
    return value


def _require_uint64(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        _refuse("invalid_integer", path, "must be an unsigned integer")
    if value < 0 or value > _UINT64_MAXIMUM:
        _refuse("invalid_integer", path, "must fit UInt64")
    return value


def _read_bounded(path: Path, maximum: int, label: str) -> bytes:
    with path.open("rb") as handle:
        payload = handle.read(maximum + 1)
    _require_byte_budget(payload, maximum, label)
    return payload


def _require_byte_budget(payload: bytes, maximum: int, path: str) -> None:
    if len(payload) > maximum:
        _refuse(
            "byte_budget_exceeded",
            path,
            f"limit {maximum}, actual at least {len(payload)}",
        )


def _normalized_path(path: Path) -> str:
    return os.path.normcase(os.path.abspath(os.fspath(path)))


def _write_exclusive_pair(
    first_path: Path, first_payload: bytes, second_path: Path, second_payload: bytes
) -> None:
    created = []
    descriptors = []
    try:
        for path in (first_path, second_path):
            descriptor = os.open(
                os.fspath(path),
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            descriptors.append(descriptor)
            created.append(path)
        _write_all(descriptors[0], first_payload)
        os.fsync(descriptors[0])
        _write_all(descriptors[1], second_payload)
        os.fsync(descriptors[1])
    except BaseException:
        for descriptor in descriptors:
            try:
                os.close(descriptor)
            except OSError:
                pass
        descriptors.clear()
        for path in created:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise
    finally:
        for descriptor in descriptors:
            os.close(descriptor)


def _write_all(descriptor: int, payload: bytes) -> None:
    view = memoryview(payload)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise OSError("feature artifact write made no progress")
        view = view[written:]


def _refuse(code: str, path: str, detail: str) -> None:
    raise ContractError(code, path, detail)


if __name__ == "__main__":
    raise SystemExit(entrypoint())
