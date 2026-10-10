import hashlib
import json
import math
import re
import struct
import unicodedata
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Set, Tuple

from .chord_notation import CanonicalChordLabelError, require_canonical_chord_label
from .errors import ContractError
from .schema import (
    ADJUDICATION_INDEPENDENT,
    ADJUDICATION_PENDING,
    ADJUDICATION_READERS_AGREED,
    ADJUDICATION_STATES,
    CAPTURE_PROTOCOL_VERSION,
    CHART_STYLES,
    CONSENT_SCOPE,
    CONSENT_STATUS,
    CONSTRUCTION_VARIATIONS,
    DEVICE_PERFORMANCE_CLASSES,
    EVIDENCE_NOT_APPLICABLE,
    EVIDENCE_NOT_COLLECTED,
    EVIDENCE_OUTCOMES,
    FEATURE_SCHEMA,
    GROUND_TRUTH_AMBIGUOUS,
    GROUND_TRUTH_CANONICAL,
    GROUND_TRUTH_EXECUTION_ERROR,
    GROUND_TRUTH_NO_READ,
    GROUND_TRUTH_OUTCOMES,
    GROUND_TRUTH_TECHNICAL_FAILURE,
    GROUND_TRUTH_UNRESOLVED,
    HANDEDNESS,
    LABEL_SCHEMA_VERSION,
    LEGACY_RECORD_SCHEMA_VERSION,
    LEGIBILITY_CLASSES,
    LEGIBILITY_EXECUTION_ERROR,
    LEGIBILITY_HUMAN_AMBIGUOUS,
    LEGIBILITY_LEGIBLE_NEGATIVE,
    LEGIBILITY_LEGIBLE_VALID,
    LEGIBILITY_TECHNICAL_FAILURE,
    LEGIBILITY_UNASSESSED,
    LINEAGE_VERSION,
    ORIENTATIONS,
    PACES,
    PENCIL_EXPERIENCE_BUCKETS,
    READER_EVIDENCE_OUTCOMES,
    RASTER_ALLOWED_VALUES,
    RECORD_SCHEMA_VERSION,
    RECORD_SPLITS,
    SIZE_BUCKETS,
    SOURCE_DERIVED,
    SOURCE_HUMAN,
    SOURCE_KINDS,
    SPLITS,
    TRAJECTORY_CHANNEL_CONTRACTS,
    UNASSIGNED_SPLIT,
)


_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
_VERSION = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")

_RECORD_FIELDS = {
    "schema_version",
    "sample_id",
    "writer_id_hash",
    "capture_session_id",
    "split",
    "feature_schema_version",
    "label_schema_version",
    "label_record_id",
    "canonical_label",
    "ground_truth_outcome",
    "legibility_class",
    "prompted_intent",
    "writer_confirmed_intent",
    "first_reader_transcription",
    "second_reader_transcription",
    "adjudication",
    "ground_truth_frozen",
    "source_kind",
    "consent_record_id",
    "consent_scope",
    "consent_status",
    "consent_ledger_version",
    "consent_record_sha256",
    "provenance_registry_version",
    "provenance_record_sha256",
    "capture_protocol_version",
    "chart_style",
    "orientation",
    "device_performance_class",
    "pace",
    "size_bucket",
    "handedness",
    "pencil_experience",
    "construction_variation",
    "app_build",
    "recognition_pipeline_version",
    "leakage_check_version",
    "lineage_version",
    "root_sample_id",
    "parent_sample_id",
    "geometry_cluster_id",
    "stroke_payload_sha256",
    "trajectory",
    "raster",
}
_ARTIFACT_FIELDS = {"relative_path", "sha256", "byte_count", "encoding"}
_LABEL_EVIDENCE_FIELDS = {"outcome", "canonical_label"}
_READER_EVIDENCE_FIELDS = {"reader_id_hash", "outcome", "canonical_label"}
_ADJUDICATION_FIELDS = {
    "state",
    "adjudicator_id_hash",
    "outcome",
    "canonical_label",
}


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def strict_json_loads(payload: str, path: str) -> object:
    def reject_duplicate_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ContractError("duplicate_json_key", path, str(key))
            result[key] = value
        return result

    def reject_nonfinite(token: str):
        raise ContractError("nonfinite_json_number", path, token)

    try:
        return json.loads(
            payload,
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_nonfinite,
        )
    except json.JSONDecodeError as error:
        raise ContractError("invalid_json", path, str(error))


def _require_exact_fields(
    value: Mapping[str, object], expected: Set[str], path: str
) -> None:
    missing = sorted(expected.difference(value.keys()))
    if missing:
        raise ContractError("missing_field", path, ", ".join(missing))
    unknown = sorted(set(value.keys()).difference(expected))
    if unknown:
        raise ContractError("unknown_field", path, ", ".join(unknown))


def _require_string(value: object, path: str, maximum_bytes: int = 256) -> str:
    if not isinstance(value, str) or not value:
        raise ContractError("invalid_string", path, "must be a non-empty string")
    if len(value.encode("utf-8")) > maximum_bytes:
        raise ContractError("invalid_string", path, f"must be at most {maximum_bytes} UTF-8 bytes")
    if any(unicodedata.category(character).startswith("C") for character in value):
        raise ContractError("invalid_string", path, "control or format characters are forbidden")
    if unicodedata.normalize("NFC", value) != value:
        raise ContractError("noncanonical_string", path, "must be NFC-normalized")
    return value


def _require_version(value: object, path: str) -> str:
    parsed = _require_string(value, path, 128)
    if not _VERSION.fullmatch(parsed):
        raise ContractError("invalid_version", path, "must use lowercase version-token syntax")
    return parsed


def _require_hash(value: object, path: str) -> str:
    parsed = _require_string(value, path, 64)
    if not _HEX_64.fullmatch(parsed):
        raise ContractError("invalid_sha256", path, "must be 64 lowercase hexadecimal characters")
    return parsed


def _require_uuid(value: object, path: str) -> str:
    parsed = _require_string(value, path, 36)
    try:
        identifier = uuid.UUID(parsed)
    except (ValueError, AttributeError):
        raise ContractError("invalid_uuid", path, "must be a canonical UUID")
    if str(identifier) != parsed:
        raise ContractError("invalid_uuid", path, "must be lowercase canonical UUID text")
    return parsed


def _require_choice(value: object, choices: Sequence[str], path: str) -> str:
    parsed = _require_string(value, path)
    if parsed not in choices:
        raise ContractError("invalid_enum", path, f"must be one of {', '.join(choices)}")
    return parsed


def _require_bool(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise ContractError("invalid_boolean", path, "must be a boolean")
    return value


def _canonical_label_for_outcome(
    outcome: str,
    raw_label: object,
    path: str,
    allow_unresolved_evidence: bool = False,
) -> Optional[str]:
    if outcome == GROUND_TRUTH_CANONICAL:
        label = _require_string(raw_label, path, 64)
        try:
            return require_canonical_chord_label(label)
        except CanonicalChordLabelError as error:
            raise ContractError("invalid_canonical_label", path, str(error))
    if outcome in (
        GROUND_TRUTH_NO_READ,
        GROUND_TRUTH_AMBIGUOUS,
        GROUND_TRUTH_EXECUTION_ERROR,
        GROUND_TRUTH_TECHNICAL_FAILURE,
        EVIDENCE_NOT_APPLICABLE,
        EVIDENCE_NOT_COLLECTED,
    ):
        if raw_label is not None:
            raise ContractError(
                "unexpected_canonical_label",
                path,
                f"{outcome} evidence must not carry chord text",
            )
        return None
    if allow_unresolved_evidence and outcome == GROUND_TRUTH_UNRESOLVED:
        if raw_label is not None:
            raise ContractError(
                "unexpected_canonical_label",
                path,
                "unresolved ground truth must not carry chord text",
            )
        return None
    raise ContractError("invalid_ground_truth_outcome", path, outcome)


@dataclass(frozen=True)
class GroundTruthLabelEvidence:
    outcome: str
    canonical_label: Optional[str]

    @classmethod
    def from_mapping(
        cls,
        value: object,
        path: str,
        allowed_outcomes: Sequence[str] = EVIDENCE_OUTCOMES,
    ) -> "GroundTruthLabelEvidence":
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(value, _LABEL_EVIDENCE_FIELDS, path)
        outcome = _require_choice(value["outcome"], allowed_outcomes, f"{path}.outcome")
        return cls(
            outcome=outcome,
            canonical_label=_canonical_label_for_outcome(
                outcome,
                value["canonical_label"],
                f"{path}.canonical_label",
            ),
        )

    def as_dict(self) -> Dict[str, object]:
        return {"canonical_label": self.canonical_label, "outcome": self.outcome}


@dataclass(frozen=True)
class GroundTruthReaderEvidence:
    reader_id_hash: Optional[str]
    outcome: str
    canonical_label: Optional[str]

    @classmethod
    def from_mapping(cls, value: object, path: str) -> "GroundTruthReaderEvidence":
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(value, _READER_EVIDENCE_FIELDS, path)
        outcome = _require_choice(
            value["outcome"], READER_EVIDENCE_OUTCOMES, f"{path}.outcome"
        )
        reader_value = value["reader_id_hash"]
        if outcome == EVIDENCE_NOT_COLLECTED:
            if reader_value is not None:
                raise ContractError(
                    "unexpected_reader_identity",
                    f"{path}.reader_id_hash",
                    "not-collected evidence must not claim a reader",
                )
            reader_id_hash = None
        else:
            reader_id_hash = _require_hash(reader_value, f"{path}.reader_id_hash")
        return cls(
            reader_id_hash=reader_id_hash,
            outcome=outcome,
            canonical_label=_canonical_label_for_outcome(
                outcome,
                value["canonical_label"],
                f"{path}.canonical_label",
            ),
        )

    def as_dict(self) -> Dict[str, object]:
        return {
            "canonical_label": self.canonical_label,
            "outcome": self.outcome,
            "reader_id_hash": self.reader_id_hash,
        }


@dataclass(frozen=True)
class GroundTruthAdjudication:
    state: str
    adjudicator_id_hash: Optional[str]
    outcome: Optional[str]
    canonical_label: Optional[str]

    @classmethod
    def from_mapping(cls, value: object, path: str) -> "GroundTruthAdjudication":
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(value, _ADJUDICATION_FIELDS, path)
        state = _require_choice(value["state"], ADJUDICATION_STATES, f"{path}.state")
        if state == ADJUDICATION_PENDING:
            if any(
                value[field] is not None
                for field in ("adjudicator_id_hash", "outcome", "canonical_label")
            ):
                raise ContractError(
                    "pending_adjudication_has_result",
                    path,
                    "pending adjudication must not claim an adjudicator or result",
                )
            return cls(state=state, adjudicator_id_hash=None, outcome=None, canonical_label=None)

        outcome = _require_choice(
            value["outcome"],
            (GROUND_TRUTH_CANONICAL, GROUND_TRUTH_NO_READ, GROUND_TRUTH_AMBIGUOUS),
            f"{path}.outcome",
        )
        canonical_label = _canonical_label_for_outcome(
            outcome,
            value["canonical_label"],
            f"{path}.canonical_label",
        )
        if state == ADJUDICATION_READERS_AGREED:
            if value["adjudicator_id_hash"] is not None:
                raise ContractError(
                    "unexpected_adjudicator",
                    f"{path}.adjudicator_id_hash",
                    "reader agreement must not claim a third adjudicator",
                )
            adjudicator_id_hash = None
        else:
            adjudicator_id_hash = _require_hash(
                value["adjudicator_id_hash"], f"{path}.adjudicator_id_hash"
            )
        return cls(
            state=state,
            adjudicator_id_hash=adjudicator_id_hash,
            outcome=outcome,
            canonical_label=canonical_label,
        )

    def as_dict(self) -> Dict[str, object]:
        return {
            "adjudicator_id_hash": self.adjudicator_id_hash,
            "canonical_label": self.canonical_label,
            "outcome": self.outcome,
            "state": self.state,
        }


class CorpusSupervisionKind(str, Enum):
    """How a validated row may supervise the learned recognizer.

    Ambiguous ink and collection failures remain first-class corpus records for
    abstention/failure reporting, but they are not silently converted into a
    notation or no-read training target.
    """

    NOTATION = "supervised-notation"
    NO_READ = "supervised-no-read"
    EXCLUDED = "excluded-from-model-supervision"


def _safe_relative_path(value: object, path: str) -> str:
    parsed = _require_string(value, path, 512)
    if "\\" in parsed:
        raise ContractError("unsafe_path", path, "backslashes are forbidden")
    candidate = Path(parsed)
    if candidate.is_absolute() or parsed != candidate.as_posix():
        raise ContractError("unsafe_path", path, "must be a normalized POSIX relative path")
    if any(part in ("", ".", "..") for part in candidate.parts):
        raise ContractError("unsafe_path", path, "empty, dot, and parent components are forbidden")
    return parsed


@dataclass(frozen=True)
class ArtifactReference:
    relative_path: str
    sha256: str
    byte_count: int
    encoding: str

    @classmethod
    def from_mapping(
        cls,
        value: object,
        path: str,
        expected_encoding: str,
        expected_byte_count: int,
    ) -> "ArtifactReference":
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        _require_exact_fields(value, _ARTIFACT_FIELDS, path)
        byte_count = value["byte_count"]
        if isinstance(byte_count, bool) or not isinstance(byte_count, int):
            raise ContractError("invalid_integer", f"{path}.byte_count", "must be an integer")
        if byte_count != expected_byte_count:
            raise ContractError(
                "feature_size_mismatch",
                f"{path}.byte_count",
                f"expected {expected_byte_count}, got {byte_count}",
            )
        encoding = _require_string(value["encoding"], f"{path}.encoding", 32)
        if encoding != expected_encoding:
            raise ContractError(
                "feature_encoding_mismatch",
                f"{path}.encoding",
                f"expected {expected_encoding}, got {encoding}",
            )
        return cls(
            relative_path=_safe_relative_path(value["relative_path"], f"{path}.relative_path"),
            sha256=_require_hash(value["sha256"], f"{path}.sha256"),
            byte_count=byte_count,
            encoding=encoding,
        )

    def as_dict(self) -> Dict[str, object]:
        return {
            "byte_count": self.byte_count,
            "encoding": self.encoding,
            "relative_path": self.relative_path,
            "sha256": self.sha256,
        }


@dataclass(frozen=True)
class CorpusRecord:
    schema_version: str
    sample_id: str
    writer_id_hash: str
    capture_session_id: str
    split: str
    feature_schema_version: str
    label_schema_version: str
    label_record_id: str
    canonical_label: Optional[str]
    source_kind: str
    consent_record_id: str
    consent_scope: str
    consent_status: str
    consent_ledger_version: str
    consent_record_sha256: str
    provenance_registry_version: str
    provenance_record_sha256: str
    capture_protocol_version: str
    lineage_version: str
    root_sample_id: str
    parent_sample_id: Optional[str]
    geometry_cluster_id: str
    stroke_payload_sha256: str
    trajectory: ArtifactReference
    raster: ArtifactReference
    ground_truth_outcome: str = GROUND_TRUTH_UNRESOLVED
    legibility_class: str = LEGIBILITY_UNASSESSED
    prompted_intent: Optional[GroundTruthLabelEvidence] = None
    writer_confirmed_intent: Optional[GroundTruthLabelEvidence] = None
    first_reader_transcription: Optional[GroundTruthReaderEvidence] = None
    second_reader_transcription: Optional[GroundTruthReaderEvidence] = None
    adjudication: Optional[GroundTruthAdjudication] = None
    ground_truth_frozen: bool = False
    chart_style: Optional[str] = None
    orientation: Optional[str] = None
    device_performance_class: Optional[str] = None
    pace: Optional[str] = None
    size_bucket: Optional[str] = None
    handedness: Optional[str] = None
    pencil_experience: Optional[str] = None
    construction_variation: Optional[str] = None
    app_build: Optional[str] = None
    recognition_pipeline_version: Optional[str] = None
    leakage_check_version: Optional[str] = None

    @property
    def supervision_kind(self) -> CorpusSupervisionKind:
        if (
            self.schema_version != RECORD_SCHEMA_VERSION
            or not self.ground_truth_frozen
            or self.split not in SPLITS
        ):
            return CorpusSupervisionKind.EXCLUDED
        if self.ground_truth_outcome == GROUND_TRUTH_CANONICAL:
            return CorpusSupervisionKind.NOTATION
        if self.ground_truth_outcome == GROUND_TRUTH_NO_READ:
            return CorpusSupervisionKind.NO_READ
        return CorpusSupervisionKind.EXCLUDED

    @property
    def supervised_canonical_label(self) -> Optional[str]:
        """Return chord text only for a frozen notation supervision target."""

        if self.supervision_kind == CorpusSupervisionKind.NOTATION:
            return self.canonical_label
        return None

    @property
    def has_model_supervision(self) -> bool:
        return self.supervision_kind != CorpusSupervisionKind.EXCLUDED

    @property
    def is_role_assigned(self) -> bool:
        return self.split in SPLITS

    @classmethod
    def from_mapping(cls, value: object, path: str = "record") -> "CorpusRecord":
        if not isinstance(value, dict):
            raise ContractError("invalid_object", path, "must be an object")
        if "schema_version" not in value:
            raise ContractError("missing_field", path, "schema_version")
        schema_version = _require_version(value["schema_version"], f"{path}.schema_version")
        if schema_version == LEGACY_RECORD_SCHEMA_VERSION:
            raise ContractError(
                "legacy_record_ineligible",
                f"{path}.schema_version",
                "v1 rows lack independent ground truth and immutable collection strata",
            )
        if schema_version != RECORD_SCHEMA_VERSION:
            raise ContractError(
                "schema_version_mismatch",
                f"{path}.schema_version",
                f"expected {RECORD_SCHEMA_VERSION}, got {schema_version}",
            )
        _require_exact_fields(value, _RECORD_FIELDS, path)
        feature_version = _require_version(
            value["feature_schema_version"], f"{path}.feature_schema_version"
        )
        if feature_version != FEATURE_SCHEMA.version:
            raise ContractError(
                "feature_schema_mismatch",
                f"{path}.feature_schema_version",
                f"expected {FEATURE_SCHEMA.version}, got {feature_version}",
            )

        consent_scope = _require_version(value["consent_scope"], f"{path}.consent_scope")
        if consent_scope != CONSENT_SCOPE:
            raise ContractError("invalid_consent_scope", f"{path}.consent_scope", CONSENT_SCOPE)
        consent_status = _require_string(value["consent_status"], f"{path}.consent_status", 32)
        if consent_status != CONSENT_STATUS:
            raise ContractError(
                "inactive_consent", f"{path}.consent_status", "only active consent is eligible"
            )

        label_schema_version = _require_version(
            value["label_schema_version"], f"{path}.label_schema_version"
        )
        if label_schema_version != LABEL_SCHEMA_VERSION:
            raise ContractError(
                "label_schema_mismatch",
                f"{path}.label_schema_version",
                f"expected {LABEL_SCHEMA_VERSION}, got {label_schema_version}",
            )

        capture_protocol_version = _require_version(
            value["capture_protocol_version"], f"{path}.capture_protocol_version"
        )
        if capture_protocol_version != CAPTURE_PROTOCOL_VERSION:
            raise ContractError(
                "capture_protocol_mismatch",
                f"{path}.capture_protocol_version",
                f"expected {CAPTURE_PROTOCOL_VERSION}, got {capture_protocol_version}",
            )

        parent_value = value["parent_sample_id"]
        parent_sample_id = (
            None
            if parent_value is None
            else _require_uuid(parent_value, f"{path}.parent_sample_id")
        )
        ground_truth_outcome = _require_choice(
            value["ground_truth_outcome"],
            GROUND_TRUTH_OUTCOMES,
            f"{path}.ground_truth_outcome",
        )
        canonical_label = _canonical_label_for_outcome(
            ground_truth_outcome,
            value["canonical_label"],
            f"{path}.canonical_label",
            allow_unresolved_evidence=True,
        )

        prompted_intent = GroundTruthLabelEvidence.from_mapping(
            value["prompted_intent"], f"{path}.prompted_intent"
        )
        writer_confirmed_intent = GroundTruthLabelEvidence.from_mapping(
            value["writer_confirmed_intent"], f"{path}.writer_confirmed_intent"
        )
        first_reader = GroundTruthReaderEvidence.from_mapping(
            value["first_reader_transcription"], f"{path}.first_reader_transcription"
        )
        second_reader = GroundTruthReaderEvidence.from_mapping(
            value["second_reader_transcription"], f"{path}.second_reader_transcription"
        )
        adjudication = GroundTruthAdjudication.from_mapping(
            value["adjudication"], f"{path}.adjudication"
        )

        record = cls(
            schema_version=schema_version,
            sample_id=_require_uuid(value["sample_id"], f"{path}.sample_id"),
            writer_id_hash=_require_hash(value["writer_id_hash"], f"{path}.writer_id_hash"),
            capture_session_id=_require_uuid(
                value["capture_session_id"], f"{path}.capture_session_id"
            ),
            split=_require_choice(value["split"], RECORD_SPLITS, f"{path}.split"),
            feature_schema_version=feature_version,
            label_schema_version=label_schema_version,
            label_record_id=_require_uuid(value["label_record_id"], f"{path}.label_record_id"),
            canonical_label=canonical_label,
            source_kind=_require_choice(value["source_kind"], SOURCE_KINDS, f"{path}.source_kind"),
            consent_record_id=_require_uuid(
                value["consent_record_id"], f"{path}.consent_record_id"
            ),
            consent_scope=consent_scope,
            consent_status=consent_status,
            consent_ledger_version=_require_version(
                value["consent_ledger_version"], f"{path}.consent_ledger_version"
            ),
            consent_record_sha256=_require_hash(
                value["consent_record_sha256"], f"{path}.consent_record_sha256"
            ),
            provenance_registry_version=_require_version(
                value["provenance_registry_version"], f"{path}.provenance_registry_version"
            ),
            provenance_record_sha256=_require_hash(
                value["provenance_record_sha256"], f"{path}.provenance_record_sha256"
            ),
            capture_protocol_version=capture_protocol_version,
            lineage_version=_require_version(value["lineage_version"], f"{path}.lineage_version"),
            root_sample_id=_require_uuid(value["root_sample_id"], f"{path}.root_sample_id"),
            parent_sample_id=parent_sample_id,
            geometry_cluster_id=_require_uuid(
                value["geometry_cluster_id"], f"{path}.geometry_cluster_id"
            ),
            stroke_payload_sha256=_require_hash(
                value["stroke_payload_sha256"], f"{path}.stroke_payload_sha256"
            ),
            trajectory=ArtifactReference.from_mapping(
                value["trajectory"],
                f"{path}.trajectory",
                FEATURE_SCHEMA.trajectory_encoding,
                FEATURE_SCHEMA.trajectory_byte_count,
            ),
            raster=ArtifactReference.from_mapping(
                value["raster"],
                f"{path}.raster",
                FEATURE_SCHEMA.raster_encoding,
                FEATURE_SCHEMA.raster_byte_count,
            ),
            ground_truth_outcome=ground_truth_outcome,
            legibility_class=_require_choice(
                value["legibility_class"], LEGIBILITY_CLASSES, f"{path}.legibility_class"
            ),
            prompted_intent=prompted_intent,
            writer_confirmed_intent=writer_confirmed_intent,
            first_reader_transcription=first_reader,
            second_reader_transcription=second_reader,
            adjudication=adjudication,
            ground_truth_frozen=_require_bool(
                value["ground_truth_frozen"], f"{path}.ground_truth_frozen"
            ),
            chart_style=_require_choice(value["chart_style"], CHART_STYLES, f"{path}.chart_style"),
            orientation=_require_choice(
                value["orientation"], ORIENTATIONS, f"{path}.orientation"
            ),
            device_performance_class=_require_choice(
                value["device_performance_class"],
                DEVICE_PERFORMANCE_CLASSES,
                f"{path}.device_performance_class",
            ),
            pace=_require_choice(value["pace"], PACES, f"{path}.pace"),
            size_bucket=_require_choice(
                value["size_bucket"], SIZE_BUCKETS, f"{path}.size_bucket"
            ),
            handedness=_require_choice(
                value["handedness"], HANDEDNESS, f"{path}.handedness"
            ),
            pencil_experience=_require_choice(
                value["pencil_experience"],
                PENCIL_EXPERIENCE_BUCKETS,
                f"{path}.pencil_experience",
            ),
            construction_variation=_require_choice(
                value["construction_variation"],
                CONSTRUCTION_VARIATIONS,
                f"{path}.construction_variation",
            ),
            app_build=_require_version(value["app_build"], f"{path}.app_build"),
            recognition_pipeline_version=_require_version(
                value["recognition_pipeline_version"],
                f"{path}.recognition_pipeline_version",
            ),
            leakage_check_version=_require_version(
                value["leakage_check_version"], f"{path}.leakage_check_version"
            ),
        )
        _validate_v2_record_contract(record)
        return record

    def as_dict(self) -> Dict[str, object]:
        return {
            "adjudication": self.adjudication.as_dict() if self.adjudication else None,
            "app_build": self.app_build,
            "canonical_label": self.canonical_label,
            "capture_protocol_version": self.capture_protocol_version,
            "capture_session_id": self.capture_session_id,
            "chart_style": self.chart_style,
            "construction_variation": self.construction_variation,
            "consent_ledger_version": self.consent_ledger_version,
            "consent_record_id": self.consent_record_id,
            "consent_record_sha256": self.consent_record_sha256,
            "consent_scope": self.consent_scope,
            "consent_status": self.consent_status,
            "device_performance_class": self.device_performance_class,
            "feature_schema_version": self.feature_schema_version,
            "first_reader_transcription": (
                self.first_reader_transcription.as_dict()
                if self.first_reader_transcription
                else None
            ),
            "geometry_cluster_id": self.geometry_cluster_id,
            "ground_truth_frozen": self.ground_truth_frozen,
            "ground_truth_outcome": self.ground_truth_outcome,
            "handedness": self.handedness,
            "label_record_id": self.label_record_id,
            "label_schema_version": self.label_schema_version,
            "leakage_check_version": self.leakage_check_version,
            "legibility_class": self.legibility_class,
            "lineage_version": self.lineage_version,
            "orientation": self.orientation,
            "pace": self.pace,
            "parent_sample_id": self.parent_sample_id,
            "pencil_experience": self.pencil_experience,
            "prompted_intent": self.prompted_intent.as_dict() if self.prompted_intent else None,
            "provenance_record_sha256": self.provenance_record_sha256,
            "provenance_registry_version": self.provenance_registry_version,
            "raster": self.raster.as_dict(),
            "recognition_pipeline_version": self.recognition_pipeline_version,
            "root_sample_id": self.root_sample_id,
            "sample_id": self.sample_id,
            "schema_version": self.schema_version,
            "second_reader_transcription": (
                self.second_reader_transcription.as_dict()
                if self.second_reader_transcription
                else None
            ),
            "size_bucket": self.size_bucket,
            "source_kind": self.source_kind,
            "split": self.split,
            "stroke_payload_sha256": self.stroke_payload_sha256,
            "trajectory": self.trajectory.as_dict(),
            "writer_confirmed_intent": (
                self.writer_confirmed_intent.as_dict()
                if self.writer_confirmed_intent
                else None
            ),
            "writer_id_hash": self.writer_id_hash,
        }


def load_records_jsonl(path: Path) -> List[CorpusRecord]:
    try:
        raw = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ContractError("records_unreadable", str(path), str(error))
    records: List[CorpusRecord] = []
    for line_number, line in enumerate(raw.splitlines(), start=1):
        if not line.strip():
            raise ContractError("blank_jsonl_line", f"{path}:{line_number}", "blank lines are forbidden")
        value = strict_json_loads(line, f"{path}:{line_number}")
        records.append(CorpusRecord.from_mapping(value, f"records[{line_number - 1}]"))
    if not records:
        raise ContractError("empty_corpus", str(path), "at least one record is required")
    return records


def _evidence_identity(evidence: GroundTruthLabelEvidence) -> Tuple[object, ...]:
    return (evidence.outcome, evidence.canonical_label)


def _reader_identity(evidence: GroundTruthReaderEvidence) -> Tuple[object, ...]:
    return (evidence.reader_id_hash, evidence.outcome, evidence.canonical_label)


def _adjudication_identity(evidence: GroundTruthAdjudication) -> Tuple[object, ...]:
    return (
        evidence.state,
        evidence.adjudicator_id_hash,
        evidence.outcome,
        evidence.canonical_label,
    )


def _ground_truth_identity(record: CorpusRecord) -> Tuple[object, ...]:
    assert record.prompted_intent is not None
    assert record.writer_confirmed_intent is not None
    assert record.first_reader_transcription is not None
    assert record.second_reader_transcription is not None
    assert record.adjudication is not None
    return (
        record.ground_truth_outcome,
        record.canonical_label,
        record.legibility_class,
        _evidence_identity(record.prompted_intent),
        _evidence_identity(record.writer_confirmed_intent),
        _reader_identity(record.first_reader_transcription),
        _reader_identity(record.second_reader_transcription),
        _adjudication_identity(record.adjudication),
        record.ground_truth_frozen,
    )


def _validate_v2_record_contract(record: CorpusRecord) -> None:
    if record.schema_version != RECORD_SCHEMA_VERSION:
        code = (
            "legacy_record_ineligible"
            if record.schema_version == LEGACY_RECORD_SCHEMA_VERSION
            else "schema_version_mismatch"
        )
        raise ContractError(
            code,
            record.sample_id,
            f"model-role corpus rows must use {RECORD_SCHEMA_VERSION}",
        )
    if record.label_schema_version != LABEL_SCHEMA_VERSION:
        raise ContractError(
            "label_schema_mismatch",
            record.sample_id,
            f"expected {LABEL_SCHEMA_VERSION}",
        )
    if record.capture_protocol_version != CAPTURE_PROTOCOL_VERSION:
        raise ContractError(
            "capture_protocol_mismatch",
            record.sample_id,
            f"expected {CAPTURE_PROTOCOL_VERSION}",
        )
    if record.split not in RECORD_SPLITS:
        raise ContractError("invalid_enum", record.sample_id, "unsupported split")

    strata = (
        (record.chart_style, CHART_STYLES, "chart_style"),
        (record.orientation, ORIENTATIONS, "orientation"),
        (
            record.device_performance_class,
            DEVICE_PERFORMANCE_CLASSES,
            "device_performance_class",
        ),
        (record.pace, PACES, "pace"),
        (record.size_bucket, SIZE_BUCKETS, "size_bucket"),
        (record.handedness, HANDEDNESS, "handedness"),
        (record.pencil_experience, PENCIL_EXPERIENCE_BUCKETS, "pencil_experience"),
        (
            record.construction_variation,
            CONSTRUCTION_VARIATIONS,
            "construction_variation",
        ),
    )
    for value, choices, field in strata:
        if value not in choices:
            raise ContractError(
                "missing_collection_stratum",
                f"{record.sample_id}.{field}",
                "v2 corpus rows require an immutable protocol value",
            )
    for value, field in (
        (record.app_build, "app_build"),
        (record.recognition_pipeline_version, "recognition_pipeline_version"),
        (record.leakage_check_version, "leakage_check_version"),
    ):
        if value is None:
            raise ContractError(
                "missing_collection_stratum",
                f"{record.sample_id}.{field}",
                "v2 corpus rows require immutable collection provenance",
            )
        _require_version(value, f"{record.sample_id}.{field}")

    evidence = (
        record.prompted_intent,
        record.writer_confirmed_intent,
        record.first_reader_transcription,
        record.second_reader_transcription,
        record.adjudication,
    )
    if any(item is None for item in evidence):
        raise ContractError(
            "missing_ground_truth_evidence",
            record.sample_id,
            "prompt, writer, two-reader, and adjudication layers are required",
        )
    assert record.prompted_intent is not None
    assert record.writer_confirmed_intent is not None
    assert record.first_reader_transcription is not None
    assert record.second_reader_transcription is not None
    assert record.adjudication is not None

    final_label = _canonical_label_for_outcome(
        record.ground_truth_outcome,
        record.canonical_label,
        f"{record.sample_id}.canonical_label",
        allow_unresolved_evidence=True,
    )
    if final_label != record.canonical_label:
        raise ContractError(
            "noncanonical_ground_truth_label",
            record.sample_id,
            "stored final chord text must already be canonical",
        )

    expected_legibility_by_outcome = {
        GROUND_TRUTH_CANONICAL: LEGIBILITY_LEGIBLE_VALID,
        GROUND_TRUTH_NO_READ: LEGIBILITY_LEGIBLE_NEGATIVE,
        GROUND_TRUTH_AMBIGUOUS: LEGIBILITY_HUMAN_AMBIGUOUS,
        GROUND_TRUTH_EXECUTION_ERROR: LEGIBILITY_EXECUTION_ERROR,
        GROUND_TRUTH_TECHNICAL_FAILURE: LEGIBILITY_TECHNICAL_FAILURE,
        GROUND_TRUTH_UNRESOLVED: LEGIBILITY_UNASSESSED,
    }
    expected_legibility = expected_legibility_by_outcome.get(record.ground_truth_outcome)
    if expected_legibility is None or record.legibility_class != expected_legibility:
        raise ContractError(
            "ground_truth_legibility_mismatch",
            record.sample_id,
            f"{record.ground_truth_outcome} requires {expected_legibility}",
        )

    prompted = record.prompted_intent
    writer = record.writer_confirmed_intent
    first = record.first_reader_transcription
    second = record.second_reader_transcription
    adjudication = record.adjudication

    if prompted.outcome == EVIDENCE_NOT_COLLECTED:
        if record.split != UNASSIGNED_SPLIT:
            raise ContractError(
                "ground_truth_not_collected",
                record.sample_id,
                "a role-assigned record requires prompted-intent evidence",
            )
    if prompted.outcome == EVIDENCE_NOT_APPLICABLE and record.legibility_class not in (
        LEGIBILITY_LEGIBLE_NEGATIVE,
        LEGIBILITY_HUMAN_AMBIGUOUS,
        LEGIBILITY_UNASSESSED,
    ):
        raise ContractError(
            "invalid_not_applicable_evidence",
            record.sample_id,
            "prompt intent is not-applicable only for negative/open-set collection",
        )
    if writer.outcome == EVIDENCE_NOT_APPLICABLE:
        raise ContractError(
            "invalid_not_applicable_evidence",
            record.sample_id,
            "writer confirmation is collected or explicitly not-collected",
        )

    readers_collected = (
        first.outcome != EVIDENCE_NOT_COLLECTED
        and second.outcome != EVIDENCE_NOT_COLLECTED
    )
    readers_missing = (
        first.outcome == EVIDENCE_NOT_COLLECTED
        or second.outcome == EVIDENCE_NOT_COLLECTED
    )
    if readers_collected:
        assert first.reader_id_hash is not None and second.reader_id_hash is not None
        if first.reader_id_hash == second.reader_id_hash:
            raise ContractError(
                "readers_not_independent",
                record.sample_id,
                "two distinct music-literate readers are required",
            )
        first_result = (first.outcome, first.canonical_label)
        second_result = (second.outcome, second.canonical_label)
        readers_agree = first_result == second_result
        if readers_agree:
            if adjudication.state != ADJUDICATION_READERS_AGREED:
                raise ContractError(
                    "invalid_adjudication_state",
                    record.sample_id,
                    "matching readers require readers-agreed adjudication state",
                )
            if (adjudication.outcome, adjudication.canonical_label) != first_result:
                raise ContractError(
                    "invalid_adjudication_result",
                    record.sample_id,
                    "reader agreement must become the final adjudicated result",
                )
        else:
            if adjudication.state != ADJUDICATION_INDEPENDENT:
                raise ContractError(
                    "adjudication_required",
                    record.sample_id,
                    "reader disagreement requires independent adjudication",
                )
            if adjudication.adjudicator_id_hash in (
                first.reader_id_hash,
                second.reader_id_hash,
            ):
                raise ContractError(
                    "adjudicator_not_independent",
                    record.sample_id,
                    "the adjudicator must be distinct from both readers",
                )
        if record.ground_truth_outcome != GROUND_TRUTH_EXECUTION_ERROR:
            if (record.ground_truth_outcome, record.canonical_label) != (
                adjudication.outcome,
                adjudication.canonical_label,
            ):
                raise ContractError(
                    "final_ground_truth_mismatch",
                    record.sample_id,
                    "the final result must equal the frozen reader/adjudicator result",
                )
    else:
        if adjudication.state != ADJUDICATION_PENDING:
            raise ContractError(
                "missing_reader_evidence",
                record.sample_id,
                "missing reader evidence requires pending adjudication",
            )
        if not readers_missing:
            raise ContractError("invalid_reader_evidence", record.sample_id, "reader state mismatch")

    if record.ground_truth_outcome == GROUND_TRUTH_CANONICAL:
        intended = (GROUND_TRUTH_CANONICAL, record.canonical_label)
        if _evidence_identity(prompted) != intended or _evidence_identity(writer) != intended:
            raise ContractError(
                "intent_visible_label_mismatch",
                record.sample_id,
                "legible notation supervision requires prompt, writer confirmation, and visible label to agree",
            )
    elif record.ground_truth_outcome == GROUND_TRUTH_NO_READ:
        if (
            prompted.outcome not in (GROUND_TRUTH_NO_READ, EVIDENCE_NOT_APPLICABLE)
            or writer.outcome != GROUND_TRUTH_NO_READ
        ):
            raise ContractError(
                "invalid_no_read_supervision",
                record.sample_id,
                "supervised no-read is reserved for confirmed negative/open-set ink",
            )
    elif record.ground_truth_outcome == GROUND_TRUTH_EXECUTION_ERROR:
        if (
            prompted.outcome != GROUND_TRUTH_CANONICAL
            or writer.outcome != GROUND_TRUTH_CANONICAL
            or _evidence_identity(prompted) != _evidence_identity(writer)
            or adjudication.state == ADJUDICATION_PENDING
            or adjudication.outcome != GROUND_TRUTH_CANONICAL
            or adjudication.canonical_label == writer.canonical_label
        ):
            raise ContractError(
                "invalid_execution_error",
                record.sample_id,
                "execution error requires confirmed intent and a different independently read visible notation",
            )

    is_role_assigned = record.split in SPLITS
    if is_role_assigned:
        if record.ground_truth_outcome == GROUND_TRUTH_UNRESOLVED:
            raise ContractError(
                "unresolved_ground_truth_in_role",
                record.sample_id,
                "role-assigned rows require canonical notation or an adjudicated no-read",
            )
        if record.legibility_class in (
            LEGIBILITY_TECHNICAL_FAILURE,
            LEGIBILITY_UNASSESSED,
        ):
            raise ContractError(
                "collection_failure_in_model_role",
                record.sample_id,
                "collection failures are retained for reporting but not model roles",
            )
        if writer.outcome == EVIDENCE_NOT_COLLECTED or readers_missing:
            raise ContractError(
                "ground_truth_not_collected",
                record.sample_id,
                "role-assigned rows require writer confirmation and two readers",
            )
        if adjudication.state == ADJUDICATION_PENDING or not record.ground_truth_frozen:
            raise ContractError(
                "unadjudicated_record_in_role",
                record.sample_id,
                "role-assigned rows require frozen independent adjudication",
            )
    else:
        if record.ground_truth_frozen and adjudication.state == ADJUDICATION_PENDING:
            raise ContractError(
                "invalid_frozen_ground_truth",
                record.sample_id,
                "pending ground truth cannot be frozen",
            )
        if adjudication.state == ADJUDICATION_PENDING:
            if record.ground_truth_outcome not in (
                GROUND_TRUTH_UNRESOLVED,
                GROUND_TRUTH_EXECUTION_ERROR,
                GROUND_TRUTH_TECHNICAL_FAILURE,
            ):
                raise ContractError(
                    "self_asserted_final_ground_truth",
                    record.sample_id,
                    "writer-only notation/no-read evidence remains unresolved until review",
                )
            if record.ground_truth_frozen:
                raise ContractError(
                    "invalid_frozen_ground_truth",
                    record.sample_id,
                    "unresolved ground truth cannot be frozen",
                )


def validate_dataset(records: Sequence[CorpusRecord], require_all_splits: bool = True) -> None:
    if not records:
        raise ContractError("empty_corpus", "records", "at least one record is required")

    by_id: Dict[str, CorpusRecord] = {}
    for record in records:
        _validate_v2_record_contract(record)
        if record.sample_id in by_id:
            raise ContractError("duplicate_sample", record.sample_id, "sample IDs must be unique")
        by_id[record.sample_id] = record
        if record.lineage_version != LINEAGE_VERSION:
            raise ContractError(
                "lineage_version_mismatch", record.sample_id, f"expected {LINEAGE_VERSION}"
            )

    labels = {record.label_schema_version for record in records}
    if len(labels) != 1:
        raise ContractError("mixed_label_schema", "records", "one label schema version is required")

    split_membership = {split: 0 for split in SPLITS}
    writer_splits: Dict[str, Set[str]] = {}
    for record in records:
        if record.split in split_membership:
            split_membership[record.split] += 1
        writer_splits.setdefault(record.writer_id_hash, set()).add(record.split)
    leaking_writers = sorted(writer for writer, splits in writer_splits.items() if len(splits) != 1)
    if leaking_writers:
        raise ContractError(
            "writer_split_leakage",
            "records",
            f"writers occur in multiple splits: {', '.join(leaking_writers)}",
        )
    if require_all_splits:
        missing_splits = [split for split, count in split_membership.items() if count == 0]
        if missing_splits:
            raise ContractError(
                "missing_split", "records", f"empty required splits: {', '.join(missing_splits)}"
            )

    session_identity: Dict[str, Tuple[str, str]] = {}
    consent_identity: Dict[str, Tuple[str, str, str, str, str]] = {}
    writer_consent: Dict[str, str] = {}
    label_identity: Dict[str, Tuple[object, ...]] = {}
    cluster_identity: Dict[str, Tuple[str, str, str]] = {}
    payload_identity: Dict[str, Tuple[str, str, str, str]] = {}
    feature_identity: Dict[Tuple[str, str], Tuple[str, str, str, str]] = {}

    for record in records:
        session = (record.writer_id_hash, record.split)
        previous_session = session_identity.setdefault(record.capture_session_id, session)
        if previous_session != session:
            raise ContractError(
                "session_leakage",
                record.capture_session_id,
                "a capture session may belong to only one writer and split",
            )

        consent = (
            record.writer_id_hash,
            record.consent_scope,
            record.consent_status,
            record.consent_ledger_version,
            record.consent_record_sha256,
        )
        previous_consent_identity = consent_identity.setdefault(record.consent_record_id, consent)
        if previous_consent_identity != consent:
            raise ContractError(
                "consent_identity_collision",
                record.consent_record_id,
                "one consent record must retain one writer, scope, status, ledger, and digest",
            )
        previous_consent = writer_consent.setdefault(record.writer_id_hash, record.consent_record_id)
        if previous_consent != record.consent_record_id:
            raise ContractError(
                "writer_consent_mismatch",
                record.writer_id_hash,
                "a writer must retain one consent record within a corpus",
            )

        label = (
            record.root_sample_id,
            record.writer_id_hash,
            record.label_schema_version,
            *_ground_truth_identity(record),
        )
        previous_label = label_identity.setdefault(record.label_record_id, label)
        if previous_label != label:
            raise ContractError(
                "label_identity_collision",
                record.label_record_id,
                "one label record cannot identify multiple roots, writers, schemas, or ground truths",
            )

        cluster = (record.writer_id_hash, record.split, record.root_sample_id)
        previous_cluster = cluster_identity.setdefault(record.geometry_cluster_id, cluster)
        if previous_cluster != cluster:
            raise ContractError(
                "geometry_cluster_leakage",
                record.geometry_cluster_id,
                "one geometry cluster cannot cross writer, split, or lineage root",
            )

        payload = (
            record.writer_id_hash,
            record.split,
            record.root_sample_id,
            record.geometry_cluster_id,
        )
        previous_payload = payload_identity.setdefault(record.stroke_payload_sha256, payload)
        if previous_payload != payload:
            raise ContractError(
                "duplicate_geometry_leakage",
                record.stroke_payload_sha256,
                "identical stroke payloads cannot cross writer, split, root, or cluster",
            )

        feature_pair = (record.trajectory.sha256, record.raster.sha256)
        previous_feature = feature_identity.setdefault(feature_pair, payload)
        if previous_feature != payload:
            raise ContractError(
                "duplicate_feature_leakage",
                record.sample_id,
                "identical feature artifacts cannot cross writer, split, root, or cluster",
            )

    for record in records:
        if record.parent_sample_id is None:
            if record.root_sample_id != record.sample_id or record.source_kind != SOURCE_HUMAN:
                raise ContractError(
                    "invalid_lineage_root",
                    record.sample_id,
                    "a root must be a consented human capture whose root ID equals its sample ID",
                )
            continue
        if record.source_kind != SOURCE_DERIVED:
            raise ContractError(
                "invalid_derived_source", record.sample_id, "a child must be derived-augmentation"
            )
        parent = by_id.get(record.parent_sample_id)
        if parent is None:
            raise ContractError(
                "missing_lineage_parent", record.sample_id, f"missing {record.parent_sample_id}"
            )
        inherited = (
            record.root_sample_id,
            record.writer_id_hash,
            record.capture_session_id,
            record.split,
            record.consent_record_id,
            record.label_record_id,
            record.label_schema_version,
            _ground_truth_identity(record),
            record.geometry_cluster_id,
            record.consent_scope,
            record.consent_status,
            record.consent_ledger_version,
            record.consent_record_sha256,
            record.provenance_registry_version,
            record.provenance_record_sha256,
            record.capture_protocol_version,
            record.chart_style,
            record.orientation,
            record.device_performance_class,
            record.pace,
            record.size_bucket,
            record.handedness,
            record.pencil_experience,
            record.construction_variation,
            record.app_build,
            record.recognition_pipeline_version,
            record.leakage_check_version,
        )
        parent_values = (
            parent.root_sample_id,
            parent.writer_id_hash,
            parent.capture_session_id,
            parent.split,
            parent.consent_record_id,
            parent.label_record_id,
            parent.label_schema_version,
            _ground_truth_identity(parent),
            parent.geometry_cluster_id,
            parent.consent_scope,
            parent.consent_status,
            parent.consent_ledger_version,
            parent.consent_record_sha256,
            parent.provenance_registry_version,
            parent.provenance_record_sha256,
            parent.capture_protocol_version,
            parent.chart_style,
            parent.orientation,
            parent.device_performance_class,
            parent.pace,
            parent.size_bucket,
            parent.handedness,
            parent.pencil_experience,
            parent.construction_variation,
            parent.app_build,
            parent.recognition_pipeline_version,
            parent.leakage_check_version,
        )
        if inherited != parent_values:
            raise ContractError(
                "lineage_inheritance_mismatch",
                record.sample_id,
                "derived records must inherit root, writer, session, split, consent, truth, strata, and cluster",
            )

        seen = {record.sample_id}
        cursor = parent
        while cursor.parent_sample_id is not None:
            if cursor.sample_id in seen:
                raise ContractError("lineage_cycle", record.sample_id, "lineage graph contains a cycle")
            seen.add(cursor.sample_id)
            next_parent = by_id.get(cursor.parent_sample_id)
            if next_parent is None:
                raise ContractError(
                    "missing_lineage_parent", cursor.sample_id, f"missing {cursor.parent_sample_id}"
                )
            cursor = next_parent


def _resolve_artifact(data_root: Path, reference: ArtifactReference, path: str) -> Path:
    try:
        root = data_root.resolve(strict=True)
    except OSError as error:
        raise ContractError("data_root_unreadable", str(data_root), str(error))
    if not root.is_dir():
        raise ContractError("data_root_unreadable", str(data_root), "must be a directory")
    candidate = root.joinpath(reference.relative_path)
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as error:
        raise ContractError("artifact_unreadable", path, str(error))
    try:
        resolved.relative_to(root)
    except ValueError:
        raise ContractError("artifact_escape", path, "artifact resolves outside data root")
    if not resolved.is_file():
        raise ContractError("artifact_not_file", path, "artifact must be a regular file")
    return resolved


def _validate_artifact_bytes(
    data_root: Path,
    reference: ArtifactReference,
    path: str,
    require_finite_float32: bool,
) -> bytes:
    artifact = _resolve_artifact(data_root, reference, path)
    try:
        payload = artifact.read_bytes()
    except OSError as error:
        raise ContractError("artifact_unreadable", path, str(error))
    if len(payload) != reference.byte_count:
        raise ContractError(
            "artifact_size_mismatch", path, f"expected {reference.byte_count}, got {len(payload)}"
        )
    digest = hashlib.sha256(payload).hexdigest()
    if digest != reference.sha256:
        raise ContractError("artifact_digest_mismatch", path, f"expected {reference.sha256}, got {digest}")
    if require_finite_float32:
        for index, (value,) in enumerate(struct.iter_unpack("<f", payload)):
            if not math.isfinite(value):
                raise ContractError(
                    "nonfinite_trajectory", path, f"Float32 value {index} is not finite"
                )
    return payload


def _validate_trajectory_contract(payload: bytes, path: str) -> None:
    channel_count = FEATURE_SCHEMA.trajectory_shape[2]
    for flat_index, (value,) in enumerate(struct.iter_unpack("<f", payload)):
        channel = TRAJECTORY_CHANNEL_CONTRACTS[flat_index % channel_count]
        if value < channel.minimum_inclusive or value > channel.maximum_inclusive:
            raise ContractError(
                "trajectory_value_out_of_contract",
                path,
                f"Float32 value {flat_index} for {channel.name} is {value}",
            )
        if (
            channel.allowed_discrete_values is not None
            and value not in channel.allowed_discrete_values
        ):
            raise ContractError(
                "trajectory_value_out_of_contract",
                path,
                f"Float32 value {flat_index} for {channel.name} is not discrete",
            )


def _validate_raster_contract(payload: bytes, path: str) -> None:
    allowed = set(RASTER_ALLOWED_VALUES)
    for index, value in enumerate(payload):
        if value not in allowed:
            raise ContractError(
                "raster_value_out_of_contract",
                path,
                f"UInt8 value {index} is {value}; expected 0 or 255",
            )


def load_validated_feature_artifacts(
    record: CorpusRecord, data_root: Path
) -> Tuple[bytes, bytes]:
    """Read and validate one record's exact trajectory and raster artifacts.

    Callers that need the payload bytes must use this single-pass helper rather
    than validate and then reopen the files.  That keeps the bytes used by an
    operation bound to the digest and semantic checks performed for that same
    read.
    """

    trajectory_payload = _validate_artifact_bytes(
        data_root,
        record.trajectory,
        f"{record.sample_id}.trajectory",
        require_finite_float32=True,
    )
    raster_payload = _validate_artifact_bytes(
        data_root,
        record.raster,
        f"{record.sample_id}.raster",
        require_finite_float32=False,
    )
    _validate_trajectory_contract(
        trajectory_payload,
        f"{record.sample_id}.trajectory",
    )
    _validate_raster_contract(
        raster_payload,
        f"{record.sample_id}.raster",
    )
    return trajectory_payload, raster_payload


def validate_feature_artifacts(records: Sequence[CorpusRecord], data_root: Path) -> None:
    for record in records:
        load_validated_feature_artifacts(record, data_root)


def records_digest(records: Iterable[CorpusRecord]) -> str:
    ordered = sorted(records, key=lambda record: record.sample_id)
    payload = b"".join(canonical_json_bytes(record.as_dict()) + b"\n" for record in ordered)
    return hashlib.sha256(payload).hexdigest()
