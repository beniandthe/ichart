"""Strict whole-session intake for the isolated Recognition Study app.

This module verifies the complete local engineering pass, binds every capture
to its commit marker and semantic outcome, and deterministically generates the
frozen feature artifacts.  Its output is deliberately *not* a corpus record:
the Study app does not establish research consent, participant provenance, an
independent transcription, adjudicated ground truth, or a writer-disjoint role.
"""

import hashlib
import math
import os
import re
import stat
import struct
import unicodedata
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import List, Mapping, Optional, Sequence, Set, Tuple

from .chord_notation import CanonicalChordLabelError, require_canonical_chord_label
from .contracts import canonical_json_bytes, strict_json_loads
from .errors import ContractError, OperationRefusedError
from .features import encode_feature_artifacts
from .schema import FEATURE_SCHEMA, TOOL_VERSION
from .study_import import (
    MAXIMUM_CANONICAL_PACKET_BYTE_COUNT,
    MAXIMUM_COMMIT_BYTE_COUNT,
    MAXIMUM_ENVELOPE_BYTE_COUNT,
    decode_canonical_commit,
    decode_canonical_study_packet,
)


SESSION_SCHEMA_VERSION = "recognition-study-session-manifest-v1"
SESSION_ARTIFACT_KIND = "engineering-dry-run-session-v1"
COLLECTION_PROTOCOL_VERSION = "engineering-dry-run-v1"
CAPTURE_LIMITS_VERSION = "capture-limits-v1"
STUDY_BUNDLE_IDENTIFIER = "com.ichart.recognitionstudy"

CAPTURE_ENVELOPE_SCHEMA_VERSION = "recognition-study-capture-envelope-v1"
CAPTURE_ARTIFACT_KIND = "engineering-dry-run-trajectory-v1"
AUTHORIZATION_SCHEMA_VERSION = "recognition-study-authorization-binding-v1"
AUTHORIZATION_KIND = "local-engineering-dry-run-v1"
PRESENTED_SURFACE_VERSION = "recognition-study-presented-surface-v1"
TRAJECTORY_DESCRIPTOR_SCHEMA_VERSION = "recognition-study-trajectory-descriptor-v1"

LEGACY_OUTCOME_SCHEMA_VERSION = "recognition-study-semantic-outcome-v1"
OUTCOME_SCHEMA_VERSION = "recognition-study-semantic-outcome-v2"
OUTCOME_SCHEMA_VERSIONS = (
    LEGACY_OUTCOME_SCHEMA_VERSION,
    OUTCOME_SCHEMA_VERSION,
)
OUTCOME_ARTIFACT_KIND = "local-engineering-semantic-outcome-v1"
OUTCOME_DATA_USE = "local-engineering-only-not-corpus-eligible-v1"
OUTCOME_EVIDENCE_STATUS = "not-established"
OUTCOME_COMMIT_SCHEMA_VERSION = "recognition-study-outcome-commit-v1"

IMPORT_RECEIPT_SCHEMA_VERSION = "recognition-study-session-import-receipt-v2"
IMPORT_STATUS = "validated-local-engineering-session"
IMPORT_AUTHORITY = "mechanical-validation-only"

CAPTURE_STORE_DIRECTORY = "recognition-study-store-v1"
OUTCOME_STORE_DIRECTORY = "recognition-study-outcome-store-v1"
DELETION_TOMBSTONE_SCHEMA_VERSION = "recognition-study-session-deletion-v1"
MAXIMUM_SESSION_MANIFEST_BYTE_COUNT = 32 * 1024
MAXIMUM_OUTCOME_BYTE_COUNT = 64 * 1024
MAXIMUM_CAPTURE_COUNT = 256

_LOWER_HEX_16 = re.compile(r"^[0-9a-f]{16}$")
_LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
_PROMPT_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_UINT16_MAXIMUM = (1 << 16) - 1
_UINT32_MAXIMUM = (1 << 32) - 1
_UINT64_MAXIMUM = (1 << 64) - 1
_MAXIMUM_RECOGNITION_LATENCY_MICROSECONDS = 10 * 60 * 1_000_000
_INT64_MINIMUM = -(1 << 63)
_INT64_MAXIMUM = (1 << 63) - 1


@dataclass(frozen=True)
class EngineeringPrompt:
    prompt_id: str
    canonical_chord: str
    chart_style: str
    pace: str
    size: str
    construction: str


# This is the exact frozen pass presented by RecognitionStudyCaptureView.
# Mirroring it here lets intake distinguish a complete pass from a merely
# contiguous prefix.  A future consented protocol must use a new version and a
# separate contract rather than silently widening this engineering-only one.
ENGINEERING_DRY_RUN_PROMPTS: Tuple[EngineeringPrompt, ...] = (
    EngineeringPrompt(
        "c-natural-normal-root",
        "C",
        "simple-chord-sheet",
        "natural",
        "normal",
        "root-first",
    ),
    EngineeringPrompt(
        "b-natural-normal-root",
        "B",
        "rhythm-section-sheet",
        "natural",
        "normal",
        "root-first",
    ),
    EngineeringPrompt(
        "g-fast-normal-root",
        "G7",
        "simple-chord-sheet",
        "fast",
        "normal",
        "root-first",
    ),
    EngineeringPrompt(
        "bb-natural-small-root",
        "Bb",
        "rhythm-section-sheet",
        "natural",
        "small",
        "root-first",
    ),
    EngineeringPrompt(
        "b-major-seven-careful-large-mixed",
        "B△7",
        "simple-chord-sheet",
        "careful",
        "large",
        "mixed-or-retraced",
    ),
    EngineeringPrompt(
        "c-minor-seven-fast-normal-modifier",
        "C-7",
        "rhythm-section-sheet",
        "fast",
        "normal",
        "modifier-first",
    ),
    EngineeringPrompt(
        "d-half-diminished-natural-normal-mixed",
        "Dø7",
        "simple-chord-sheet",
        "natural",
        "normal",
        "mixed-or-retraced",
    ),
    EngineeringPrompt(
        "g-altered-natural-normal-root",
        "G7(b9)",
        "rhythm-section-sheet",
        "natural",
        "normal",
        "root-first",
    ),
    EngineeringPrompt(
        "c-over-e-fast-small-root",
        "C/E",
        "simple-chord-sheet",
        "fast",
        "small",
        "root-first",
    ),
    EngineeringPrompt(
        "db-major-nine-careful-large-modifier",
        "Db△9",
        "rhythm-section-sheet",
        "careful",
        "large",
        "modifier-first",
    ),
)


_SESSION_FIELDS = {
    "artifactKind",
    "clientAppContext",
    "clientCreatedAtUnixMilliseconds",
    "collectionProtocolVersion",
    "limitsVersion",
    "localSessionID",
    "schemaVersion",
}
_APP_CONTEXT_FIELDS = {
    "appVersion",
    "buildNumber",
    "bundleIdentifier",
    "operatingSystemMajorVersion",
    "operatingSystemMinorVersion",
}
_ENVELOPE_FIELDS = {
    "artifactKind",
    "authorizationBinding",
    "captureOrdinal",
    "clientCapturedAtUnixMilliseconds",
    "collectionProtocolVersion",
    "localCaptureID",
    "localSessionID",
    "presentedSurface",
    "schemaVersion",
    "sessionManifestSHA256",
    "trajectoryDescriptor",
}
_AUTHORIZATION_FIELDS = {"authorizationID", "kind", "schemaVersion"}
_SURFACE_FIELDS = {
    "canvasHeight",
    "canvasWidth",
    "clientObservedOrientation",
    "presentedChartStyle",
    "presentedConstructionInstruction",
    "presentedPaceInstruction",
    "presentedSizeInstruction",
    "surfaceVersion",
}
_DESCRIPTOR_FIELDS = {
    "canonicalPacketByteCount",
    "canonicalPacketSHA256",
    "containsNonFiniteTiming",
    "coordinateSpace",
    "creationTimingCoverage",
    "emptyStrokeCount",
    "overallTimingCoverage",
    "packetFormatVersion",
    "pointCount",
    "pointTimingCoverage",
    "schemaVersion",
    "strokeCount",
}
_OUTCOME_COMMIT_FIELDS = {
    "authorizationID",
    "localCaptureID",
    "localSessionID",
    "outcomeByteCount",
    "outcomeSHA256",
    "schemaVersion",
}
_OUTCOME_FIELDS = {
    "adaptedRecognizerOutcome",
    "artifactKind",
    "authorizationID",
    "baseRecognizerOutcome",
    "captureEnvelopeSHA256",
    "clientRecordedAtUnixMilliseconds",
    "consentProvenanceStatus",
    "corpusAdjudicationStatus",
    "dataUse",
    "localCaptureID",
    "localSessionID",
    "promptOutcome",
    "schemaVersion",
    "trajectoryPacketSHA256",
}
_PROMPT_OUTCOME_FIELDS = {
    "intendedChord",
    "promptID",
    "writerConfirmationState",
}
_BASE_REQUIRED_FIELDS = {
    "disposition",
    "recognizerID",
    "recognizerVersion",
}
_BASE_OPTIONAL_FIELDS = {
    "candidate",
    "canonicalCandidate",
    "latencyMicroseconds",
}
_ADAPTED_REQUIRED_FIELDS = {
    "adaptationState",
    "correctionMemoryState",
    "disposition",
}
_ADAPTED_OPTIONAL_FIELDS = {"candidate", "canonicalCandidate"}
_DELETION_TOMBSTONE_FIELDS = {
    "clientRequestedAtUnixMilliseconds",
    "localSessionID",
    "schemaVersion",
    "sessionManifestSHA256",
}


@dataclass(frozen=True)
class StudySessionImportReceipt:
    value: Mapping[str, object]
    output_directory: Path

    @property
    def capture_count(self) -> int:
        return int(self.value["capture_count"])

    @property
    def receipt_path(self) -> Path:
        return self.output_directory / "receipt.json"

    @property
    def receipt_sha256(self) -> str:
        return hashlib.sha256(canonical_json_bytes(self.value)).hexdigest()


@dataclass(frozen=True)
class _ValidatedCapture:
    ordinal: int
    local_capture_id: str
    authorization_id: str
    strokes: Tuple[object, ...]
    receipt_value: Mapping[str, object]


def import_study_session(
    study_root: Path,
    output_directory: Path,
    local_session_id: Optional[str] = None,
) -> StudySessionImportReceipt:
    """Validate one complete engineering pass and atomically stage features.

    The resulting receipt is never a corpus row and is never training,
    calibration, or sealed-evaluation eligible.
    """

    study_root = Path(study_root)
    output_directory = Path(output_directory)
    _require_new_output_directory(output_directory)
    _require_real_directory(study_root, "study_root")
    study_root = study_root.resolve(strict=True)
    output_directory = output_directory.resolve(strict=False)
    _require_disjoint_tree_paths(study_root, output_directory)
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    output_directory = (
        output_directory.parent.resolve(strict=True) / output_directory.name
    )
    _require_disjoint_tree_paths(study_root, output_directory)
    _require_new_output_directory(output_directory)

    capture_store = study_root / CAPTURE_STORE_DIRECTORY
    outcome_store = study_root / OUTCOME_STORE_DIRECTORY
    sessions_directory = capture_store / "sessions"
    outcomes_directory = outcome_store / "outcomes"
    _require_real_directory(capture_store, "capture_store")
    _require_real_directory(outcome_store, "outcome_store")
    _require_real_directory(sessions_directory, "capture_store.sessions")
    _require_real_directory(outcomes_directory, "outcome_store.outcomes")
    _require_empty_store_work_queues(capture_store, outcome_store)
    deletion_tombstones = _load_deletion_tombstones(
        capture_store / "deletion-tombstones"
    )

    session_directory = _select_session_directory(
        sessions_directory, local_session_id, deletion_tombstones
    )
    session_data = _read_canonical_file(
        session_directory / "session.json",
        MAXIMUM_SESSION_MANIFEST_BYTE_COUNT,
        "session.json",
    )
    session = _validate_session_manifest(session_data)
    session_id = session["localSessionID"]
    if session_directory.name != session_id:
        _refuse(
            "session_directory_mismatch",
            "session_directory",
            f"expected {session_id}, got {session_directory.name}",
        )
    if local_session_id is not None and local_session_id != session_id:
        _refuse(
            "session_identifier_mismatch",
            "local_session_id",
            f"expected {local_session_id}, got {session_id}",
        )

    session_digest = hashlib.sha256(session_data).hexdigest()
    tombstone = deletion_tombstones.get(session_id)
    if tombstone is not None:
        tombstone_digest = tombstone["sessionManifestSHA256"]
        if tombstone_digest != session_digest:
            _refuse(
                "deletion_tombstone_binding_mismatch",
                f"deletion-tombstones/{session_id}.json.sessionManifestSHA256",
                f"expected {session_digest}, got {tombstone_digest}",
            )
        _refuse(
            "session_deleted",
            f"deletion-tombstones/{session_id}.json",
            "the canonical deletion tombstone dominates retained session files",
        )

    _require_exact_session_layout(session_directory)
    captures_directory = session_directory / "captures"
    capture_directories = _uuid_directories(captures_directory, "captures")
    expected_count = len(ENGINEERING_DRY_RUN_PROMPTS)
    if len(capture_directories) != expected_count:
        _refuse(
            "incomplete_engineering_pass",
            "captures",
            f"expected {expected_count} captures, got {len(capture_directories)}",
        )

    validated = []  # type: List[_ValidatedCapture]
    seen_capture_ids = set()  # type: Set[str]
    seen_authorization_ids = set()  # type: Set[str]
    seen_ordinals = set()  # type: Set[int]
    for capture_directory in capture_directories:
        item = _validate_capture_bundle(
            capture_directory=capture_directory,
            outcomes_directory=outcomes_directory,
            session=session,
            session_digest=session_digest,
        )
        if item.local_capture_id in seen_capture_ids:
            _refuse(
                "duplicate_capture_id",
                "captures",
                item.local_capture_id,
            )
        if item.authorization_id in seen_authorization_ids:
            _refuse(
                "duplicate_authorization_id",
                "captures",
                item.authorization_id,
            )
        if item.ordinal in seen_ordinals:
            _refuse("duplicate_capture_ordinal", "captures", str(item.ordinal))
        seen_capture_ids.add(item.local_capture_id)
        seen_authorization_ids.add(item.authorization_id)
        seen_ordinals.add(item.ordinal)
        validated.append(item)

    validated.sort(key=lambda item: item.ordinal)
    ordinals = [item.ordinal for item in validated]
    if ordinals != list(range(expected_count)):
        _refuse(
            "noncontiguous_capture_ordinals",
            "captures",
            f"expected {list(range(expected_count))}, got {ordinals}",
        )

    output_parent_descriptor = _open_output_parent_descriptor(
        study_root, output_directory
    )
    staging_name = ""
    staging_descriptor = None
    feature_descriptor = None
    feature_filenames = []  # type: List[str]
    try:
        staging_name, staging_descriptor = _create_staging_directory(
            output_parent_descriptor, output_directory.name
        )
        os.mkdir("features", 0o700, dir_fd=staging_descriptor)
        feature_descriptor = _open_child_directory(
            staging_descriptor, "features"
        )
        capture_receipts = []
        for item in validated:
            trajectory, raster = encode_feature_artifacts(item.strokes)
            trajectory_data = trajectory.to_bytes()
            raster_data = raster.to_bytes()
            stem = f"{item.ordinal:03d}-{item.local_capture_id}"
            trajectory_relative = f"features/{stem}.trajectory.f32le"
            raster_relative = f"features/{stem}.raster.u8"
            trajectory_filename = f"{stem}.trajectory.f32le"
            raster_filename = f"{stem}.raster.u8"
            feature_filenames.extend(
                (trajectory_filename, raster_filename)
            )
            _write_new_file_at(
                feature_descriptor, trajectory_filename, trajectory_data
            )
            _write_new_file_at(
                feature_descriptor, raster_filename, raster_data
            )

            capture_value = dict(item.receipt_value)
            capture_value["features"] = {
                "raster": {
                    "byte_count": len(raster_data),
                    "encoding": FEATURE_SCHEMA.raster_encoding,
                    "relative_path": raster_relative,
                    "sha256": hashlib.sha256(raster_data).hexdigest(),
                },
                "trajectory": {
                    "byte_count": len(trajectory_data),
                    "encoding": FEATURE_SCHEMA.trajectory_encoding,
                    "relative_path": trajectory_relative,
                    "sha256": hashlib.sha256(trajectory_data).hexdigest(),
                },
            }
            capture_receipts.append(capture_value)

        _synchronize_directory_descriptor(feature_descriptor)
        os.close(feature_descriptor)
        feature_descriptor = None

        receipt_value = {
            "authority": IMPORT_AUTHORITY,
            "capture_count": len(capture_receipts),
            "captures": capture_receipts,
            "collection_protocol_version": COLLECTION_PROTOCOL_VERSION,
            "consent_provenance_status": OUTCOME_EVIDENCE_STATUS,
            "corpus_adjudication_status": OUTCOME_EVIDENCE_STATUS,
            "corpus_eligible": False,
            "data_use": OUTCOME_DATA_USE,
            "evaluation_eligible": False,
            "feature_schema": FEATURE_SCHEMA.as_dict(),
            "ground_truth_status": OUTCOME_EVIDENCE_STATUS,
            "local_session_id": session_id,
            "model_supervision_eligible": False,
            "schema_version": IMPORT_RECEIPT_SCHEMA_VERSION,
            "session_manifest": {
                "app_context": _snake_case_app_context(session["clientAppContext"]),
                "byte_count": len(session_data),
                "client_created_at_unix_milliseconds": session[
                    "clientCreatedAtUnixMilliseconds"
                ],
                "sha256": session_digest,
            },
            "status": IMPORT_STATUS,
            "tool_version": TOOL_VERSION,
        }
        receipt_data = canonical_json_bytes(receipt_value)
        _write_new_file_at(staging_descriptor, "receipt.json", receipt_data)
        _synchronize_directory_descriptor(staging_descriptor)
        _publish_staged_output(
            output_parent_descriptor,
            staging_descriptor,
            output_directory.name,
            feature_filenames,
        )
        _require_published_output_binding(
            study_root,
            output_directory,
            output_parent_descriptor,
        )
    finally:
        if feature_descriptor is not None:
            os.close(feature_descriptor)
        if staging_descriptor is not None:
            _cleanup_staging_directory(
                output_parent_descriptor,
                staging_descriptor,
                staging_name,
                feature_filenames,
            )
            os.close(staging_descriptor)
        os.close(output_parent_descriptor)

    return StudySessionImportReceipt(receipt_value, output_directory)


def _validate_session_manifest(payload: bytes) -> Mapping[str, object]:
    value = _decode_canonical_json(payload, "session.json")
    session = _require_object(value, "session.json")
    _require_exact_fields(session, _SESSION_FIELDS, "session.json")
    _require_fixed_string(
        session["schemaVersion"], SESSION_SCHEMA_VERSION, "session.json.schemaVersion"
    )
    _require_fixed_string(
        session["artifactKind"], SESSION_ARTIFACT_KIND, "session.json.artifactKind"
    )
    _require_uuid(session["localSessionID"], "session.json.localSessionID")
    _require_fixed_string(
        session["collectionProtocolVersion"],
        COLLECTION_PROTOCOL_VERSION,
        "session.json.collectionProtocolVersion",
    )
    _require_fixed_string(
        session["limitsVersion"],
        CAPTURE_LIMITS_VERSION,
        "session.json.limitsVersion",
    )
    _require_int64(
        session["clientCreatedAtUnixMilliseconds"],
        "session.json.clientCreatedAtUnixMilliseconds",
    )
    app = _require_object(session["clientAppContext"], "session.json.clientAppContext")
    _require_exact_fields(app, _APP_CONTEXT_FIELDS, "session.json.clientAppContext")
    _require_fixed_string(
        app["bundleIdentifier"],
        STUDY_BUNDLE_IDENTIFIER,
        "session.json.clientAppContext.bundleIdentifier",
    )
    _require_printable_ascii(
        app["appVersion"], "session.json.clientAppContext.appVersion", 32
    )
    _require_printable_ascii(
        app["buildNumber"], "session.json.clientAppContext.buildNumber", 32
    )
    major = _require_uint(
        app["operatingSystemMajorVersion"],
        "session.json.clientAppContext.operatingSystemMajorVersion",
        _UINT16_MAXIMUM,
    )
    _require_uint(
        app["operatingSystemMinorVersion"],
        "session.json.clientAppContext.operatingSystemMinorVersion",
        _UINT16_MAXIMUM,
    )
    if major == 0:
        _refuse(
            "invalid_operating_system_version",
            "session.json.clientAppContext.operatingSystemMajorVersion",
            "must be positive",
        )
    return session


def _validate_capture_bundle(
    capture_directory: Path,
    outcomes_directory: Path,
    session: Mapping[str, object],
    session_digest: str,
) -> _ValidatedCapture:
    _require_exact_directory_entries(
        capture_directory,
        {"commit.json", "envelope.json", "trajectory.json"},
        f"captures/{capture_directory.name}",
    )
    commit_data = _read_canonical_file(
        capture_directory / "commit.json",
        MAXIMUM_COMMIT_BYTE_COUNT,
        "capture.commit.json",
    )
    envelope_data = _read_canonical_file(
        capture_directory / "envelope.json",
        MAXIMUM_ENVELOPE_BYTE_COUNT,
        "capture.envelope.json",
    )
    trajectory_data = _read_canonical_file(
        capture_directory / "trajectory.json",
        MAXIMUM_CANONICAL_PACKET_BYTE_COUNT,
        "capture.trajectory.json",
    )

    commit = decode_canonical_commit(commit_data)
    if capture_directory.name != commit.authorization_id:
        _refuse(
            "authorization_directory_mismatch",
            "capture_directory",
            f"expected {commit.authorization_id}, got {capture_directory.name}",
        )
    if commit.local_session_id != session["localSessionID"]:
        _refuse(
            "capture_session_mismatch",
            "capture.commit.json.localSessionID",
            commit.local_session_id,
        )
    _require_digest_and_count(
        trajectory_data,
        commit.trajectory_sha256,
        commit.trajectory_byte_count,
        "capture.trajectory.json",
    )
    _require_digest_and_count(
        envelope_data,
        commit.envelope_sha256,
        commit.envelope_byte_count,
        "capture.envelope.json",
    )

    strokes = decode_canonical_study_packet(trajectory_data)
    trajectory_value = _decode_canonical_json(
        trajectory_data, "capture.trajectory.json"
    )
    trajectory_packet = _require_object(
        trajectory_value, "capture.trajectory.json"
    )
    envelope_value = _decode_canonical_json(envelope_data, "capture.envelope.json")
    envelope = _require_object(envelope_value, "capture.envelope.json")
    _require_exact_fields(envelope, _ENVELOPE_FIELDS, "capture.envelope.json")
    _validate_envelope(
        envelope,
        trajectory_packet,
        trajectory_data,
        session,
        session_digest,
        commit.local_capture_id,
        commit.authorization_id,
    )
    ordinal = _require_uint(
        envelope["captureOrdinal"],
        "capture.envelope.json.captureOrdinal",
        _UINT32_MAXIMUM,
    )
    if ordinal >= len(ENGINEERING_DRY_RUN_PROMPTS):
        _refuse(
            "unexpected_capture_ordinal",
            "capture.envelope.json.captureOrdinal",
            str(ordinal),
        )
    expected_prompt = ENGINEERING_DRY_RUN_PROMPTS[ordinal]

    outcome_directory = outcomes_directory / commit.authorization_id
    _require_real_directory(
        outcome_directory, f"outcomes/{commit.authorization_id}"
    )
    _require_exact_directory_entries(
        outcome_directory,
        {"commit.json", "outcome.json"},
        f"outcomes/{commit.authorization_id}",
    )
    outcome_commit_data = _read_canonical_file(
        outcome_directory / "commit.json",
        MAXIMUM_COMMIT_BYTE_COUNT,
        "outcome.commit.json",
    )
    outcome_data = _read_canonical_file(
        outcome_directory / "outcome.json",
        MAXIMUM_OUTCOME_BYTE_COUNT,
        "outcome.json",
    )
    outcome_commit_value = _decode_canonical_json(
        outcome_commit_data, "outcome.commit.json"
    )
    outcome_commit = _require_object(
        outcome_commit_value, "outcome.commit.json"
    )
    _require_exact_fields(
        outcome_commit, _OUTCOME_COMMIT_FIELDS, "outcome.commit.json"
    )
    _require_fixed_string(
        outcome_commit["schemaVersion"],
        OUTCOME_COMMIT_SCHEMA_VERSION,
        "outcome.commit.json.schemaVersion",
    )
    for field, expected in (
        ("localSessionID", commit.local_session_id),
        ("localCaptureID", commit.local_capture_id),
        ("authorizationID", commit.authorization_id),
    ):
        actual = _require_uuid(
            outcome_commit[field], f"outcome.commit.json.{field}"
        )
        if actual != expected:
            _refuse(
                "outcome_commit_binding_mismatch",
                f"outcome.commit.json.{field}",
                f"expected {expected}, got {actual}",
            )
    outcome_digest = _require_sha256(
        outcome_commit["outcomeSHA256"], "outcome.commit.json.outcomeSHA256"
    )
    outcome_byte_count = _require_uint(
        outcome_commit["outcomeByteCount"],
        "outcome.commit.json.outcomeByteCount",
        _UINT64_MAXIMUM,
    )
    _require_digest_and_count(
        outcome_data, outcome_digest, outcome_byte_count, "outcome.json"
    )

    outcome_value = _decode_canonical_json(outcome_data, "outcome.json")
    outcome = _require_object(outcome_value, "outcome.json")
    baseline = _validate_outcome(
        outcome=outcome,
        expected_prompt=expected_prompt,
        expected_session_id=commit.local_session_id,
        expected_capture_id=commit.local_capture_id,
        expected_authorization_id=commit.authorization_id,
        trajectory_digest=commit.trajectory_sha256,
        envelope_digest=commit.envelope_sha256,
    )

    surface = _require_object(
        envelope["presentedSurface"], "capture.envelope.json.presentedSurface"
    )
    prompt = _require_object(outcome["promptOutcome"], "outcome.json.promptOutcome")
    receipt_value = {
        "authorization_id": commit.authorization_id,
        "baseline_observation": baseline,
        "capture_ordinal": ordinal,
        "local_capture_id": commit.local_capture_id,
        "presented_surface": {
            "canvas_height_bits": surface["canvasHeight"],
            "canvas_width_bits": surface["canvasWidth"],
            "chart_style": surface["presentedChartStyle"],
            "construction_instruction": surface[
                "presentedConstructionInstruction"
            ],
            "orientation": surface["clientObservedOrientation"],
            "pace_instruction": surface["presentedPaceInstruction"],
            "size_instruction": surface["presentedSizeInstruction"],
        },
        "prompt_intent": {
            "canonical_chord": prompt["intendedChord"],
            "prompt_id": prompt["promptID"],
        },
        "source_artifacts": {
            "capture_commit": _artifact_digest(commit_data),
            "capture_envelope": _artifact_digest(envelope_data),
            "outcome": _artifact_digest(outcome_data),
            "outcome_commit": _artifact_digest(outcome_commit_data),
            "trajectory_packet": _artifact_digest(trajectory_data),
        },
        "writer_self_report": prompt["writerConfirmationState"],
    }
    return _ValidatedCapture(
        ordinal=ordinal,
        local_capture_id=commit.local_capture_id,
        authorization_id=commit.authorization_id,
        strokes=strokes,
        receipt_value=receipt_value,
    )


def _validate_envelope(
    envelope: Mapping[str, object],
    trajectory_packet: Mapping[str, object],
    trajectory_data: bytes,
    session: Mapping[str, object],
    session_digest: str,
    expected_capture_id: str,
    expected_authorization_id: str,
) -> None:
    _require_fixed_string(
        envelope["schemaVersion"],
        CAPTURE_ENVELOPE_SCHEMA_VERSION,
        "capture.envelope.json.schemaVersion",
    )
    _require_fixed_string(
        envelope["artifactKind"],
        CAPTURE_ARTIFACT_KIND,
        "capture.envelope.json.artifactKind",
    )
    for field, expected in (
        ("localCaptureID", expected_capture_id),
        ("localSessionID", session["localSessionID"]),
    ):
        actual = _require_uuid(envelope[field], f"capture.envelope.json.{field}")
        if actual != expected:
            _refuse(
                "capture_envelope_binding_mismatch",
                f"capture.envelope.json.{field}",
                f"expected {expected}, got {actual}",
            )
    ordinal = _require_uint(
        envelope["captureOrdinal"],
        "capture.envelope.json.captureOrdinal",
        _UINT32_MAXIMUM,
    )
    if ordinal >= MAXIMUM_CAPTURE_COUNT:
        _refuse(
            "capture_ordinal_limit_exceeded",
            "capture.envelope.json.captureOrdinal",
            str(ordinal),
        )
    if ordinal >= len(ENGINEERING_DRY_RUN_PROMPTS):
        _refuse(
            "unexpected_capture_ordinal",
            "capture.envelope.json.captureOrdinal",
            str(ordinal),
        )
    _require_fixed_string(
        envelope["collectionProtocolVersion"],
        COLLECTION_PROTOCOL_VERSION,
        "capture.envelope.json.collectionProtocolVersion",
    )
    _require_int64(
        envelope["clientCapturedAtUnixMilliseconds"],
        "capture.envelope.json.clientCapturedAtUnixMilliseconds",
    )
    manifest_digest = _require_sha256(
        envelope["sessionManifestSHA256"],
        "capture.envelope.json.sessionManifestSHA256",
    )
    if manifest_digest != session_digest:
        _refuse(
            "session_manifest_digest_mismatch",
            "capture.envelope.json.sessionManifestSHA256",
            f"expected {session_digest}, got {manifest_digest}",
        )

    authorization = _require_object(
        envelope["authorizationBinding"],
        "capture.envelope.json.authorizationBinding",
    )
    _require_exact_fields(
        authorization,
        _AUTHORIZATION_FIELDS,
        "capture.envelope.json.authorizationBinding",
    )
    _require_fixed_string(
        authorization["schemaVersion"],
        AUTHORIZATION_SCHEMA_VERSION,
        "capture.envelope.json.authorizationBinding.schemaVersion",
    )
    _require_fixed_string(
        authorization["kind"],
        AUTHORIZATION_KIND,
        "capture.envelope.json.authorizationBinding.kind",
    )
    authorization_id = _require_uuid(
        authorization["authorizationID"],
        "capture.envelope.json.authorizationBinding.authorizationID",
    )
    if authorization_id != expected_authorization_id:
        _refuse(
            "authorization_binding_mismatch",
            "capture.envelope.json.authorizationBinding.authorizationID",
            f"expected {expected_authorization_id}, got {authorization_id}",
        )

    surface = _require_object(
        envelope["presentedSurface"], "capture.envelope.json.presentedSurface"
    )
    _require_exact_fields(
        surface, _SURFACE_FIELDS, "capture.envelope.json.presentedSurface"
    )
    _require_fixed_string(
        surface["surfaceVersion"],
        PRESENTED_SURFACE_VERSION,
        "capture.envelope.json.presentedSurface.surfaceVersion",
    )
    _require_choice(
        surface["presentedChartStyle"],
        ("simple-chord-sheet", "rhythm-section-sheet"),
        "capture.envelope.json.presentedSurface.presentedChartStyle",
    )
    _require_choice(
        surface["clientObservedOrientation"],
        ("portrait", "landscape"),
        "capture.envelope.json.presentedSurface.clientObservedOrientation",
    )
    for field in ("canvasWidth", "canvasHeight"):
        dimension = _decode_finite_double(
            surface[field], f"capture.envelope.json.presentedSurface.{field}"
        )
        if dimension <= 0:
            _refuse(
                "invalid_canvas_dimension",
                f"capture.envelope.json.presentedSurface.{field}",
                "must be positive",
            )
    _require_choice(
        surface["presentedPaceInstruction"],
        ("natural", "fast", "careful"),
        "capture.envelope.json.presentedSurface.presentedPaceInstruction",
    )
    _require_choice(
        surface["presentedSizeInstruction"],
        ("small", "normal", "large"),
        "capture.envelope.json.presentedSurface.presentedSizeInstruction",
    )
    _require_choice(
        surface["presentedConstructionInstruction"],
        ("root-first", "modifier-first", "mixed-or-retraced"),
        "capture.envelope.json.presentedSurface.presentedConstructionInstruction",
    )

    prompt = ENGINEERING_DRY_RUN_PROMPTS[ordinal]
    expected_surface = (
        prompt.chart_style,
        prompt.pace,
        prompt.size,
        prompt.construction,
    )
    actual_surface = (
        surface["presentedChartStyle"],
        surface["presentedPaceInstruction"],
        surface["presentedSizeInstruction"],
        surface["presentedConstructionInstruction"],
    )
    if actual_surface != expected_surface:
        _refuse(
            "presented_surface_prompt_mismatch",
            "capture.envelope.json.presentedSurface",
            f"expected {expected_surface}, got {actual_surface}",
        )

    descriptor = _require_object(
        envelope["trajectoryDescriptor"],
        "capture.envelope.json.trajectoryDescriptor",
    )
    _require_exact_fields(
        descriptor,
        _DESCRIPTOR_FIELDS,
        "capture.envelope.json.trajectoryDescriptor",
    )
    _validate_trajectory_descriptor(descriptor, trajectory_packet, trajectory_data)


def _validate_trajectory_descriptor(
    descriptor: Mapping[str, object],
    packet: Mapping[str, object],
    packet_data: bytes,
) -> None:
    path = "capture.envelope.json.trajectoryDescriptor"
    _require_fixed_string(
        descriptor["schemaVersion"],
        TRAJECTORY_DESCRIPTOR_SCHEMA_VERSION,
        f"{path}.schemaVersion",
    )
    _require_fixed_string(
        descriptor["packetFormatVersion"],
        "ink-trajectory-packet-v1",
        f"{path}.packetFormatVersion",
    )
    _require_fixed_string(
        descriptor["coordinateSpace"],
        "transformed-prepared-drawing",
        f"{path}.coordinateSpace",
    )
    packet_digest = _require_sha256(
        descriptor["canonicalPacketSHA256"], f"{path}.canonicalPacketSHA256"
    )
    if packet_digest != hashlib.sha256(packet_data).hexdigest():
        _refuse(
            "trajectory_descriptor_mismatch",
            f"{path}.canonicalPacketSHA256",
            "does not match trajectory.json",
        )
    packet_byte_count = _require_uint(
        descriptor["canonicalPacketByteCount"],
        f"{path}.canonicalPacketByteCount",
        _UINT64_MAXIMUM,
    )
    if packet_byte_count != len(packet_data):
        _refuse(
            "trajectory_descriptor_mismatch",
            f"{path}.canonicalPacketByteCount",
            f"expected {len(packet_data)}, got {packet_byte_count}",
        )

    strokes = packet["strokes"]
    stroke_count = len(strokes)
    empty_stroke_count = sum(1 for stroke in strokes if not stroke["points"])
    point_count = sum(len(stroke["points"]) for stroke in strokes)
    point_states = [
        point["timeOffset"]["state"]
        for stroke in strokes
        for point in stroke["points"]
    ]
    creation_states = [stroke["creationTimeOffset"]["state"] for stroke in strokes]
    overall_states = []
    for stroke in strokes:
        overall_states.append(stroke["creationTimeOffset"]["state"])
        overall_states.extend(point["timeOffset"]["state"] for point in stroke["points"])
    derived = {
        "strokeCount": stroke_count,
        "emptyStrokeCount": empty_stroke_count,
        "pointCount": point_count,
        "pointTimingCoverage": _timing_coverage(point_states),
        "creationTimingCoverage": _timing_coverage(creation_states),
        "overallTimingCoverage": _timing_coverage(overall_states),
        "containsNonFiniteTiming": any(
            state == "nonFinite" for state in overall_states
        ),
    }
    for field, expected in derived.items():
        actual = descriptor[field]
        if isinstance(expected, bool):
            actual = _require_bool(actual, f"{path}.{field}")
        elif isinstance(expected, int):
            actual = _require_uint(actual, f"{path}.{field}", _UINT32_MAXIMUM)
        else:
            actual = _require_choice(
                actual, ("unavailable", "partial", "complete"), f"{path}.{field}"
            )
        if actual != expected:
            _refuse(
                "trajectory_descriptor_mismatch",
                f"{path}.{field}",
                f"expected {expected}, got {actual}",
            )


def _validate_outcome(
    outcome: Mapping[str, object],
    expected_prompt: EngineeringPrompt,
    expected_session_id: str,
    expected_capture_id: str,
    expected_authorization_id: str,
    trajectory_digest: str,
    envelope_digest: str,
) -> Mapping[str, object]:
    _require_exact_fields(outcome, _OUTCOME_FIELDS, "outcome.json")
    schema_version = _require_choice(
        outcome["schemaVersion"],
        OUTCOME_SCHEMA_VERSIONS,
        "outcome.json.schemaVersion",
    )
    for field, expected in (
        ("artifactKind", OUTCOME_ARTIFACT_KIND),
        ("dataUse", OUTCOME_DATA_USE),
        ("consentProvenanceStatus", OUTCOME_EVIDENCE_STATUS),
        ("corpusAdjudicationStatus", OUTCOME_EVIDENCE_STATUS),
    ):
        _require_fixed_string(outcome[field], expected, f"outcome.json.{field}")
    for field, expected in (
        ("localSessionID", expected_session_id),
        ("localCaptureID", expected_capture_id),
        ("authorizationID", expected_authorization_id),
    ):
        actual = _require_uuid(outcome[field], f"outcome.json.{field}")
        if actual != expected:
            _refuse(
                "outcome_binding_mismatch",
                f"outcome.json.{field}",
                f"expected {expected}, got {actual}",
            )
    for field, expected in (
        ("trajectoryPacketSHA256", trajectory_digest),
        ("captureEnvelopeSHA256", envelope_digest),
    ):
        actual = _require_sha256(outcome[field], f"outcome.json.{field}")
        if actual != expected:
            _refuse(
                "outcome_binding_mismatch",
                f"outcome.json.{field}",
                f"expected {expected}, got {actual}",
            )
    recorded = _require_int64(
        outcome["clientRecordedAtUnixMilliseconds"],
        "outcome.json.clientRecordedAtUnixMilliseconds",
    )
    if recorded < 0:
        _refuse(
            "invalid_timestamp",
            "outcome.json.clientRecordedAtUnixMilliseconds",
            "must be nonnegative",
        )

    prompt = _require_object(outcome["promptOutcome"], "outcome.json.promptOutcome")
    _require_exact_fields(prompt, _PROMPT_OUTCOME_FIELDS, "outcome.json.promptOutcome")
    prompt_id = _require_string(prompt["promptID"], "outcome.json.promptOutcome.promptID", 64)
    if _PROMPT_ID.fullmatch(prompt_id) is None:
        _refuse(
            "invalid_prompt_id",
            "outcome.json.promptOutcome.promptID",
            prompt_id,
        )
    chord = _require_canonical_chord(
        prompt["intendedChord"], "outcome.json.promptOutcome.intendedChord"
    )
    if prompt_id != expected_prompt.prompt_id or chord != expected_prompt.canonical_chord:
        _refuse(
            "prompt_plan_mismatch",
            "outcome.json.promptOutcome",
            (
                f"expected ({expected_prompt.prompt_id}, {expected_prompt.canonical_chord}), "
                f"got ({prompt_id}, {chord})"
            ),
        )
    writer_state = _require_choice(
        prompt["writerConfirmationState"],
        ("as-prompted", "execution-error", "human-ambiguous", "technical-failure"),
        "outcome.json.promptOutcome.writerConfirmationState",
    )

    base = _require_object(
        outcome["baseRecognizerOutcome"], "outcome.json.baseRecognizerOutcome"
    )
    _require_required_optional_fields(
        base,
        _BASE_REQUIRED_FIELDS,
        _BASE_OPTIONAL_FIELDS,
        "outcome.json.baseRecognizerOutcome",
    )
    recognizer_id = _require_printable_ascii(
        base["recognizerID"], "outcome.json.baseRecognizerOutcome.recognizerID", 64
    )
    recognizer_version = _require_printable_ascii(
        base["recognizerVersion"],
        "outcome.json.baseRecognizerOutcome.recognizerVersion",
        64,
    )
    disposition = _require_choice(
        base["disposition"],
        ("accepted", "review", "no-read", "not-run"),
        "outcome.json.baseRecognizerOutcome.disposition",
    )
    latency_microseconds = None
    if "latencyMicroseconds" in base:
        latency_microseconds = _require_uint(
            base["latencyMicroseconds"],
            "outcome.json.baseRecognizerOutcome.latencyMicroseconds",
            _MAXIMUM_RECOGNITION_LATENCY_MICROSECONDS,
        )
    if schema_version == LEGACY_OUTCOME_SCHEMA_VERSION:
        if latency_microseconds is not None:
            _refuse(
                "invalid_base_outcome",
                "outcome.json.baseRecognizerOutcome.latencyMicroseconds",
                "legacy v1 outcomes must not carry recognition latency",
            )
    elif disposition == "not-run":
        if latency_microseconds is not None:
            _refuse(
                "invalid_base_outcome",
                "outcome.json.baseRecognizerOutcome.latencyMicroseconds",
                "not-run must not carry recognition latency",
            )
    elif latency_microseconds is None:
        _refuse(
            "invalid_base_outcome",
            "outcome.json.baseRecognizerOutcome.latencyMicroseconds",
            "v2 recognizer observations require structured latency",
        )
    candidate = None
    if "candidate" in base:
        candidate = _require_string(
            base["candidate"], "outcome.json.baseRecognizerOutcome.candidate", 256
        )
    canonical_candidate = None
    if "canonicalCandidate" in base:
        canonical_candidate = _require_canonical_chord(
            base["canonicalCandidate"],
            "outcome.json.baseRecognizerOutcome.canonicalCandidate",
        )
    if canonical_candidate is not None and candidate != canonical_candidate:
        _refuse(
            "invalid_base_outcome",
            "outcome.json.baseRecognizerOutcome.canonicalCandidate",
            "must exactly equal candidate",
        )
    if disposition == "accepted" and (
        candidate is None or canonical_candidate is None
    ):
        _refuse(
            "invalid_base_outcome",
            "outcome.json.baseRecognizerOutcome",
            "accepted requires a strict canonical candidate",
        )
    if disposition in ("no-read", "not-run") and (
        candidate is not None or canonical_candidate is not None
    ):
        _refuse(
            "invalid_base_outcome",
            "outcome.json.baseRecognizerOutcome",
            "no-read and not-run must not carry candidates",
        )
    if writer_state == "technical-failure" and disposition != "not-run":
        _refuse(
            "technical_failure_has_observation",
            "outcome.json.baseRecognizerOutcome.disposition",
            disposition,
        )
    if writer_state != "technical-failure" and disposition == "not-run":
        _refuse(
            "technical_failure_state_required",
            "outcome.json.promptOutcome.writerConfirmationState",
            writer_state,
        )

    adapted = _require_object(
        outcome["adaptedRecognizerOutcome"],
        "outcome.json.adaptedRecognizerOutcome",
    )
    _require_required_optional_fields(
        adapted,
        _ADAPTED_REQUIRED_FIELDS,
        _ADAPTED_OPTIONAL_FIELDS,
        "outcome.json.adaptedRecognizerOutcome",
    )
    for field, expected in (
        ("adaptationState", "disabled-for-study"),
        ("correctionMemoryState", "disabled-for-study"),
        ("disposition", "not-run"),
    ):
        _require_fixed_string(
            adapted[field], expected, f"outcome.json.adaptedRecognizerOutcome.{field}"
        )
    if "candidate" in adapted or "canonicalCandidate" in adapted:
        _refuse(
            "invalid_adapted_outcome",
            "outcome.json.adaptedRecognizerOutcome",
            "disabled study adaptation must not carry candidates",
        )

    return {
        "candidate": candidate,
        "canonical_candidate": canonical_candidate,
        "disposition": disposition,
        "latency_microseconds": latency_microseconds,
        "recognizer_id": recognizer_id,
        "recognizer_version": recognizer_version,
    }


def _select_session_directory(
    sessions_directory: Path,
    local_session_id: Optional[str],
    deletion_tombstones: Mapping[str, Mapping[str, object]],
) -> Path:
    if local_session_id is not None:
        identifier = _require_uuid(local_session_id, "local_session_id")
        selected = sessions_directory / identifier
        if not selected.exists() and identifier in deletion_tombstones:
            _refuse(
                "session_deleted",
                f"deletion-tombstones/{identifier}.json",
                "the canonical deletion tombstone dominates the absent session",
            )
        _require_real_directory(selected, f"sessions/{identifier}")
        return selected
    sessions = _uuid_directories(sessions_directory, "sessions")
    live_sessions = []
    tombstoned_sessions = []
    for session_directory in sessions:
        tombstone = deletion_tombstones.get(session_directory.name)
        if tombstone is None:
            live_sessions.append(session_directory)
            continue
        _require_tombstone_binds_session_directory(
            session_directory, tombstone
        )
        tombstoned_sessions.append(session_directory)
    if len(live_sessions) == 1:
        return live_sessions[0]
    if not live_sessions and len(tombstoned_sessions) == 1:
        # Return the sole deleted candidate so the normal selected-session path
        # emits the specific session_deleted refusal.
        return tombstoned_sessions[0]
    _refuse(
        "ambiguous_session_selection",
        "sessions",
        f"expected exactly one live session, got {len(live_sessions)}",
    )


def _require_tombstone_binds_session_directory(
    session_directory: Path,
    tombstone: Mapping[str, object],
) -> None:
    session_data = _read_canonical_file(
        session_directory / "session.json",
        MAXIMUM_SESSION_MANIFEST_BYTE_COUNT,
        f"sessions/{session_directory.name}/session.json",
    )
    session = _validate_session_manifest(session_data)
    session_id = session["localSessionID"]
    if session_id != session_directory.name:
        _refuse(
            "session_directory_mismatch",
            f"sessions/{session_directory.name}",
            f"expected {session_id}, got {session_directory.name}",
        )
    session_digest = hashlib.sha256(session_data).hexdigest()
    tombstone_digest = tombstone["sessionManifestSHA256"]
    if tombstone_digest != session_digest:
        _refuse(
            "deletion_tombstone_binding_mismatch",
            f"deletion-tombstones/{session_id}.json.sessionManifestSHA256",
            f"expected {session_digest}, got {tombstone_digest}",
        )


def _load_deletion_tombstones(
    directory: Path,
) -> Mapping[str, Mapping[str, object]]:
    _require_real_directory(directory, "capture_store.deletion-tombstones")
    tombstones = {}
    for entry in _directory_entries(
        directory, "capture_store.deletion-tombstones"
    ):
        _require_regular_file(
            entry, f"capture_store.deletion-tombstones/{entry.name}"
        )
        if entry.suffix != ".json" or entry.name.count(".") != 1:
            _refuse(
                "invalid_deletion_tombstone_name",
                "capture_store.deletion-tombstones",
                entry.name,
            )
        identifier = _require_uuid(
            entry.stem,
            "capture_store.deletion-tombstones.filename",
        )
        label = f"deletion-tombstones/{entry.name}"
        payload = _read_canonical_file(
            entry, MAXIMUM_COMMIT_BYTE_COUNT, label
        )
        value = _require_object(_decode_canonical_json(payload, label), label)
        _require_exact_fields(value, _DELETION_TOMBSTONE_FIELDS, label)
        _require_fixed_string(
            value["schemaVersion"],
            DELETION_TOMBSTONE_SCHEMA_VERSION,
            f"{label}.schemaVersion",
        )
        local_session_id = _require_uuid(
            value["localSessionID"], f"{label}.localSessionID"
        )
        if local_session_id != identifier:
            _refuse(
                "deletion_tombstone_filename_mismatch",
                f"{label}.localSessionID",
                f"expected {identifier}, got {local_session_id}",
            )
        _require_sha256(
            value["sessionManifestSHA256"],
            f"{label}.sessionManifestSHA256",
        )
        _require_int64(
            value["clientRequestedAtUnixMilliseconds"],
            f"{label}.clientRequestedAtUnixMilliseconds",
        )
        tombstones[identifier] = value
    return tombstones


def _require_exact_session_layout(session_directory: Path) -> None:
    _require_exact_directory_entries(
        session_directory,
        {"captures", "quarantine", "session.json", "staging"},
        "session_directory",
    )
    _require_real_directory(session_directory / "captures", "session.captures")
    for name in ("quarantine", "staging"):
        directory = session_directory / name
        _require_real_directory(directory, f"session.{name}")
        _require_empty_directory(directory, f"session.{name}")


def _require_empty_store_work_queues(
    capture_store: Path, outcome_store: Path
) -> None:
    # Capture staging is session-scoped and validated with the selected session.
    for name in ("quarantine", "staging"):
        directory = outcome_store / name
        _require_real_directory(directory, f"outcome_store.{name}")
        _require_empty_directory(directory, f"outcome_store.{name}")
    capture_quarantine = capture_store / "quarantine"
    if capture_quarantine.exists():
        _require_real_directory(capture_quarantine, "capture_store.quarantine")
        _require_empty_directory(capture_quarantine, "capture_store.quarantine")


def _uuid_directories(parent: Path, path: str) -> List[Path]:
    result = []
    for entry in _directory_entries(parent, path):
        _require_real_directory(entry, f"{path}/{entry.name}")
        _require_uuid(entry.name, f"{path}.directory_name")
        result.append(entry)
    return sorted(result, key=lambda value: value.name)


def _require_new_output_directory(path: Path) -> None:
    if path.exists() or path.is_symlink():
        raise OperationRefusedError(
            "output_directory_exists",
            str(path),
            "session import outputs are immutable",
        )


def _require_disjoint_tree_paths(study_root: Path, output_directory: Path) -> None:
    if (
        study_root == output_directory
        or _path_is_within(output_directory, study_root)
        or _path_is_within(study_root, output_directory)
    ):
        raise OperationRefusedError(
            "overlapping_input_output_trees",
            str(output_directory),
            "the immutable output and authoritative Study store must be disjoint",
        )


def _path_is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def _directory_open_flags() -> int:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    return flags


def _open_output_parent_descriptor(
    study_root: Path, output_directory: Path
) -> int:
    parent = output_directory.parent
    try:
        descriptor = os.open(os.fspath(parent), _directory_open_flags())
    except OSError as error:
        raise OperationRefusedError(
            "unsafe_output_parent",
            str(parent),
            str(error),
        )
    try:
        _require_output_parent_descriptor_binding(
            study_root, output_directory, descriptor
        )
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def _require_output_parent_descriptor_binding(
    study_root: Path,
    output_directory: Path,
    descriptor: int,
) -> None:
    parent = output_directory.parent
    try:
        resolved_parent = parent.resolve(strict=True)
        named = os.stat(os.fspath(parent), follow_symlinks=False)
        opened = os.fstat(descriptor)
    except OSError as error:
        raise OperationRefusedError(
            "output_parent_changed",
            str(parent),
            str(error),
        )
    resolved_output = resolved_parent / output_directory.name
    _require_disjoint_tree_paths(study_root, resolved_output)
    if (named.st_dev, named.st_ino) != (opened.st_dev, opened.st_ino):
        raise OperationRefusedError(
            "output_parent_changed",
            str(parent),
            "the pathname no longer identifies the anchored output parent",
        )


def _require_published_output_binding(
    study_root: Path,
    output_directory: Path,
    parent_descriptor: int,
) -> None:
    _require_output_parent_descriptor_binding(
        study_root, output_directory, parent_descriptor
    )
    try:
        anchored = os.stat(
            output_directory.name,
            dir_fd=parent_descriptor,
            follow_symlinks=False,
        )
        visible = output_directory.lstat()
    except OSError as error:
        raise OperationRefusedError(
            "published_output_path_changed",
            str(output_directory),
            str(error),
        )
    if not stat.S_ISDIR(anchored.st_mode) or not stat.S_ISDIR(
        visible.st_mode
    ):
        raise OperationRefusedError(
            "published_output_path_changed",
            str(output_directory),
            "the published output must remain a real directory",
        )
    if (anchored.st_dev, anchored.st_ino) != (
        visible.st_dev,
        visible.st_ino,
    ):
        raise OperationRefusedError(
            "published_output_path_changed",
            str(output_directory),
            "the pathname no longer identifies the anchored output",
        )
    output_descriptor = _open_child_directory(
        parent_descriptor, output_directory.name
    )
    try:
        receipt = os.stat(
            "receipt.json",
            dir_fd=output_descriptor,
            follow_symlinks=False,
        )
    except OSError as error:
        raise OperationRefusedError(
            "published_receipt_missing",
            str(output_directory / "receipt.json"),
            str(error),
        )
    finally:
        os.close(output_descriptor)
    if not stat.S_ISREG(receipt.st_mode):
        raise OperationRefusedError(
            "published_receipt_missing",
            str(output_directory / "receipt.json"),
            "the publication receipt must be a regular file",
        )


def _open_child_directory(parent_descriptor: int, name: str) -> int:
    return os.open(name, _directory_open_flags(), dir_fd=parent_descriptor)


def _create_staging_directory(
    parent_descriptor: int, output_name: str
) -> Tuple[str, int]:
    for _ in range(32):
        name = f".{output_name}.{uuid.uuid4().hex}.staging"
        try:
            os.mkdir(name, 0o700, dir_fd=parent_descriptor)
        except FileExistsError:
            continue
        try:
            return name, _open_child_directory(parent_descriptor, name)
        except BaseException:
            try:
                os.rmdir(name, dir_fd=parent_descriptor)
            except OSError:
                pass
            raise
    raise OperationRefusedError(
        "staging_name_exhausted",
        output_name,
        "could not reserve a unique staging directory",
    )


def _reserve_output_directory(
    parent_descriptor: int, output_name: str
) -> None:
    try:
        os.mkdir(output_name, 0o700, dir_fd=parent_descriptor)
    except FileExistsError:
        raise OperationRefusedError(
            "output_directory_exists",
            output_name,
            "session import outputs are immutable",
        )


def _publish_staged_output(
    parent_descriptor: int,
    staging_descriptor: int,
    output_name: str,
    feature_filenames: Sequence[str],
) -> None:
    """Publish through anchored descriptors without replacing any child.

    The receipt is the commit marker and links last.  A failure after reserving
    the output leaves an intentionally incomplete directory with no receipt;
    immutable-output checks then refuse to reuse that path.
    """

    _reserve_output_directory(parent_descriptor, output_name)
    output_descriptor = _open_child_directory(
        parent_descriptor, output_name
    )
    try:
        os.mkdir("features", 0o700, dir_fd=output_descriptor)
        output_features_descriptor = _open_child_directory(
            output_descriptor, "features"
        )
        try:
            staging_features_descriptor = _open_child_directory(
                staging_descriptor, "features"
            )
            try:
                for filename in feature_filenames:
                    os.link(
                        filename,
                        filename,
                        src_dir_fd=staging_features_descriptor,
                        dst_dir_fd=output_features_descriptor,
                        follow_symlinks=False,
                    )
                _synchronize_directory_descriptor(
                    output_features_descriptor
                )
            finally:
                os.close(staging_features_descriptor)
        finally:
            os.close(output_features_descriptor)

        _synchronize_directory_descriptor(output_descriptor)
        os.link(
            "receipt.json",
            "receipt.json",
            src_dir_fd=staging_descriptor,
            dst_dir_fd=output_descriptor,
            follow_symlinks=False,
        )
        _synchronize_directory_descriptor(output_descriptor)
        _synchronize_directory_descriptor(parent_descriptor)
    finally:
        os.close(output_descriptor)


def _cleanup_staging_directory(
    parent_descriptor: int,
    staging_descriptor: int,
    staging_name: str,
    feature_filenames: Sequence[str],
) -> None:
    try:
        features_descriptor = _open_child_directory(
            staging_descriptor, "features"
        )
    except OSError:
        features_descriptor = None
    if features_descriptor is not None:
        try:
            for filename in feature_filenames:
                try:
                    os.unlink(filename, dir_fd=features_descriptor)
                except OSError:
                    pass
        finally:
            os.close(features_descriptor)
        try:
            os.rmdir("features", dir_fd=staging_descriptor)
        except OSError:
            pass
    try:
        os.unlink("receipt.json", dir_fd=staging_descriptor)
    except OSError:
        pass
    try:
        os.rmdir(staging_name, dir_fd=parent_descriptor)
    except OSError:
        pass
    try:
        _synchronize_directory_descriptor(parent_descriptor)
    except OSError:
        pass


def _read_canonical_file(path: Path, maximum: int, label: str) -> bytes:
    _require_regular_file(path, label)
    with path.open("rb") as handle:
        payload = handle.read(maximum + 1)
    if len(payload) > maximum:
        _refuse(
            "byte_budget_exceeded",
            label,
            f"limit {maximum}, actual at least {len(payload)}",
        )
    _decode_canonical_json(payload, label)
    return payload


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


def _require_required_optional_fields(
    value: Mapping[str, object],
    required: Set[str],
    optional: Set[str],
    path: str,
) -> None:
    missing = sorted(required.difference(value.keys()))
    if missing:
        _refuse("missing_field", path, ", ".join(missing))
    unknown = sorted(set(value.keys()).difference(required | optional))
    if unknown:
        _refuse("unknown_field", path, ", ".join(unknown))


def _require_string(value: object, path: str, maximum_bytes: int) -> str:
    if not isinstance(value, str) or not value:
        _refuse("invalid_string", path, "must be a non-empty string")
    if len(value.encode("utf-8")) > maximum_bytes:
        _refuse(
            "invalid_string", path, f"must be at most {maximum_bytes} UTF-8 bytes"
        )
    if unicodedata.normalize("NFC", value) != value:
        _refuse("noncanonical_string", path, "must be NFC-normalized")
    if any(unicodedata.category(character).startswith("C") for character in value):
        _refuse("invalid_string", path, "control or format characters are forbidden")
    return value


def _require_printable_ascii(
    value: object, path: str, maximum_bytes: int
) -> str:
    parsed = _require_string(value, path, maximum_bytes)
    if any(ord(character) < 0x20 or ord(character) > 0x7E for character in parsed):
        _refuse("invalid_printable_ascii", path, "must contain printable ASCII only")
    return parsed


def _require_fixed_string(value: object, expected: str, path: str) -> str:
    if not isinstance(value, str):
        _refuse("invalid_string", path, "must be a string")
    if value != expected:
        _refuse("fixed_value_mismatch", path, f"expected {expected}, got {value}")
    return value


def _require_choice(value: object, choices: Sequence[str], path: str) -> str:
    if not isinstance(value, str) or value not in choices:
        _refuse("invalid_enum", path, f"must be one of {', '.join(choices)}")
    return value


def _require_uuid(value: object, path: str) -> str:
    if not isinstance(value, str):
        _refuse("invalid_uuid", path, "must be lowercase canonical UUID text")
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        _refuse("invalid_uuid", path, "must be lowercase canonical UUID text")
    if str(parsed) != value:
        _refuse("invalid_uuid", path, "must be lowercase canonical UUID text")
    return value


def _require_sha256(value: object, path: str) -> str:
    if not isinstance(value, str) or _LOWER_HEX_64.fullmatch(value) is None:
        _refuse(
            "invalid_sha256", path, "must be 64 lowercase hexadecimal characters"
        )
    return value


def _require_uint(value: object, path: str, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        _refuse("invalid_integer", path, "must be an unsigned integer")
    if value < 0 or value > maximum:
        _refuse("invalid_integer", path, f"must be in 0...{maximum}")
    return value


def _require_int64(value: object, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        _refuse("invalid_integer", path, "must be an Int64")
    if value < _INT64_MINIMUM or value > _INT64_MAXIMUM:
        _refuse("invalid_integer", path, "must fit Int64")
    return value


def _require_bool(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        _refuse("invalid_boolean", path, "must be a boolean")
    return value


def _require_canonical_chord(value: object, path: str) -> str:
    parsed = _require_string(value, path, 64)
    try:
        return require_canonical_chord_label(parsed)
    except CanonicalChordLabelError as error:
        _refuse("invalid_canonical_label", path, str(error))


def _decode_finite_double(value: object, path: str) -> float:
    if not isinstance(value, str) or _LOWER_HEX_16.fullmatch(value) is None:
        _refuse("invalid_bit_pattern", path, "must be 16 lowercase hexadecimal digits")
    decoded = struct.unpack(">d", bytes.fromhex(value))[0]
    if not math.isfinite(decoded):
        _refuse("nonfinite_geometry", path, "must be finite")
    return decoded


def _timing_coverage(states: Sequence[str]) -> str:
    if not states:
        return "unavailable"
    available = sum(state != "missing" for state in states)
    if available == 0:
        return "unavailable"
    if available == len(states):
        return "complete"
    return "partial"


def _require_digest_and_count(
    payload: bytes, expected_digest: str, expected_count: int, path: str
) -> None:
    actual_digest = hashlib.sha256(payload).hexdigest()
    if actual_digest != expected_digest:
        _refuse(
            "artifact_digest_mismatch",
            path,
            f"expected {expected_digest}, got {actual_digest}",
        )
    if len(payload) != expected_count:
        _refuse(
            "artifact_byte_count_mismatch",
            path,
            f"expected {expected_count}, got {len(payload)}",
        )


def _artifact_digest(payload: bytes) -> Mapping[str, object]:
    return {
        "byte_count": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def _snake_case_app_context(value: object) -> Mapping[str, object]:
    app = _require_object(value, "session.json.clientAppContext")
    return {
        "app_version": app["appVersion"],
        "build_number": app["buildNumber"],
        "bundle_identifier": app["bundleIdentifier"],
        "operating_system_major_version": app["operatingSystemMajorVersion"],
        "operating_system_minor_version": app["operatingSystemMinorVersion"],
    }


def _directory_entries(path: Path, label: str) -> List[Path]:
    _require_real_directory(path, label)
    try:
        return list(path.iterdir())
    except OSError as error:
        _refuse("unreadable_directory", label, str(error))


def _require_exact_directory_entries(
    path: Path, expected: Set[str], label: str
) -> None:
    entries = _directory_entries(path, label)
    actual = {entry.name for entry in entries}
    missing = sorted(expected - actual)
    if missing:
        _refuse("missing_artifact", label, ", ".join(missing))
    unknown = sorted(actual - expected)
    if unknown:
        _refuse("unexpected_artifact", label, ", ".join(unknown))


def _require_empty_directory(path: Path, label: str) -> None:
    entries = _directory_entries(path, label)
    if entries:
        _refuse(
            "incomplete_store_transaction",
            label,
            ", ".join(sorted(entry.name for entry in entries)),
        )


def _require_real_directory(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        _refuse("missing_directory", label, str(path))
    except OSError as error:
        _refuse("unreadable_directory", label, str(error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        _refuse("invalid_directory", label, "must be a real directory, not a symlink")


def _require_regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        _refuse("missing_artifact", label, str(path))
    except OSError as error:
        _refuse("unreadable_artifact", label, str(error))
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        _refuse("invalid_artifact", label, "must be a regular file, not a symlink")


def _write_new_file_at(
    directory_descriptor: int, filename: str, payload: bytes
) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(
        filename,
        flags,
        0o600,
        dir_fd=directory_descriptor,
    )
    try:
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                raise OSError("artifact write made no progress")
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _synchronize_directory_descriptor(descriptor: int) -> None:
    os.fsync(descriptor)


def _refuse(code: str, path: str, detail: str) -> None:
    raise ContractError(code, path, detail)
