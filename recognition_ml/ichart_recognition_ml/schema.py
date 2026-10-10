import math
from dataclasses import dataclass
from typing import Dict, Optional, Tuple


TOOL_VERSION = "ichart-recognition-ml-v2"
RECORD_SCHEMA_VERSION = "recognition-corpus-record-v2"
LEGACY_RECORD_SCHEMA_VERSION = "recognition-corpus-record-v1"
MANIFEST_SCHEMA_VERSION = "recognition-corpus-manifest-v2"


@dataclass(frozen=True)
class FeatureSchema:
    version: str = "chord-ink-features-v1"
    trajectory_shape: Tuple[int, int, int] = (1, 256, 10)
    trajectory_encoding: str = "float32-le"
    raster_width: int = 256
    raster_height: int = 96
    raster_encoding: str = "uint8-gray"

    @property
    def trajectory_value_count(self) -> int:
        return self.trajectory_shape[0] * self.trajectory_shape[1] * self.trajectory_shape[2]

    @property
    def trajectory_byte_count(self) -> int:
        return self.trajectory_value_count * 4

    @property
    def raster_byte_count(self) -> int:
        return self.raster_width * self.raster_height

    def as_dict(self) -> Dict[str, object]:
        return {
            "raster_encoding": self.raster_encoding,
            "raster_height": self.raster_height,
            "raster_width": self.raster_width,
            "trajectory_encoding": self.trajectory_encoding,
            "trajectory_shape": list(self.trajectory_shape),
            "version": self.version,
        }


FEATURE_SCHEMA = FeatureSchema()


@dataclass(frozen=True)
class TrajectoryChannelContract:
    index: int
    name: str
    minimum_inclusive: float
    maximum_inclusive: float
    allowed_discrete_values: Optional[Tuple[float, ...]] = None


# Byte-level semantic contract emitted by the frozen Swift and Python feature
# encoders. Corpus validation, model export, and the on-device runtime must all
# reject values outside these same bounds.
TRAJECTORY_CHANNEL_CONTRACTS = (
    TrajectoryChannelContract(0, "x", -0.5, 0.5),
    TrajectoryChannelContract(1, "y", -0.5, 0.5),
    TrajectoryChannelContract(2, "delta_x", -1.0, 1.0),
    TrajectoryChannelContract(3, "delta_y", -1.0, 1.0),
    TrajectoryChannelContract(4, "arc_step", 0.0, math.sqrt(2.0)),
    TrajectoryChannelContract(5, "normalized_delta_time", 0.0, 1.0),
    TrajectoryChannelContract(6, "timing_available", 0.0, 1.0, (0.0, 1.0)),
    TrajectoryChannelContract(7, "stroke_start", 0.0, 1.0, (0.0, 1.0)),
    TrajectoryChannelContract(8, "stroke_end", 0.0, 1.0, (0.0, 1.0)),
    TrajectoryChannelContract(9, "valid", 0.0, 1.0, (0.0, 1.0)),
)
RASTER_ALLOWED_VALUES = (0, 255)

if len(TRAJECTORY_CHANNEL_CONTRACTS) != FEATURE_SCHEMA.trajectory_shape[2]:
    raise RuntimeError("trajectory channel contract does not match the frozen feature shape")
if tuple(item.index for item in TRAJECTORY_CHANNEL_CONTRACTS) != tuple(
    range(FEATURE_SCHEMA.trajectory_shape[2])
):
    raise RuntimeError("trajectory channel contract indices must be contiguous")

SPLITS = ("development", "calibration", "sealed-evaluation")
UNASSIGNED_SPLIT = "unassigned"
RECORD_SPLITS = SPLITS + (UNASSIGNED_SPLIT,)
CONSENT_SCOPE = "chord-recognition-research-v1"
CONSENT_STATUS = "active"
SOURCE_HUMAN = "consented-human-capture"
SOURCE_DERIVED = "derived-augmentation"
SOURCE_KINDS = (SOURCE_HUMAN, SOURCE_DERIVED)
LINEAGE_VERSION = "recognition-lineage-v1"

# A corpus row is eligible for a model role only when it was collected under
# this protocol and its independently reviewed ground truth uses this schema.
CAPTURE_PROTOCOL_VERSION = "writer-independent-capture-v2"
LABEL_SCHEMA_VERSION = "writer-independent-ground-truth-v2"

GROUND_TRUTH_CANONICAL = "canonical-notation"
GROUND_TRUTH_NO_READ = "no-read"
GROUND_TRUTH_AMBIGUOUS = "human-ambiguous"
GROUND_TRUTH_EXECUTION_ERROR = "execution-error"
GROUND_TRUTH_TECHNICAL_FAILURE = "technical-failure"
GROUND_TRUTH_UNRESOLVED = "unresolved"
GROUND_TRUTH_OUTCOMES = (
    GROUND_TRUTH_CANONICAL,
    GROUND_TRUTH_NO_READ,
    GROUND_TRUTH_AMBIGUOUS,
    GROUND_TRUTH_EXECUTION_ERROR,
    GROUND_TRUTH_TECHNICAL_FAILURE,
    GROUND_TRUTH_UNRESOLVED,
)

EVIDENCE_NOT_APPLICABLE = "not-applicable"
EVIDENCE_NOT_COLLECTED = "not-collected"
EVIDENCE_OUTCOMES = (
    GROUND_TRUTH_CANONICAL,
    GROUND_TRUTH_NO_READ,
    EVIDENCE_NOT_APPLICABLE,
    EVIDENCE_NOT_COLLECTED,
)
READER_EVIDENCE_OUTCOMES = (
    GROUND_TRUTH_CANONICAL,
    GROUND_TRUTH_NO_READ,
    GROUND_TRUTH_AMBIGUOUS,
    EVIDENCE_NOT_COLLECTED,
)

LEGIBILITY_LEGIBLE_VALID = "legible-valid"
LEGIBILITY_LEGIBLE_NEGATIVE = "legible-negative-or-open-set"
LEGIBILITY_HUMAN_AMBIGUOUS = "human-ambiguous"
LEGIBILITY_EXECUTION_ERROR = "execution-error"
LEGIBILITY_TECHNICAL_FAILURE = "technical-failure"
LEGIBILITY_UNASSESSED = "unassessed"
LEGIBILITY_CLASSES = (
    LEGIBILITY_LEGIBLE_VALID,
    LEGIBILITY_LEGIBLE_NEGATIVE,
    LEGIBILITY_HUMAN_AMBIGUOUS,
    LEGIBILITY_EXECUTION_ERROR,
    LEGIBILITY_TECHNICAL_FAILURE,
    LEGIBILITY_UNASSESSED,
)

ADJUDICATION_READERS_AGREED = "readers-agreed"
ADJUDICATION_INDEPENDENT = "independently-adjudicated"
ADJUDICATION_PENDING = "pending"
ADJUDICATION_STATES = (
    ADJUDICATION_READERS_AGREED,
    ADJUDICATION_INDEPENDENT,
    ADJUDICATION_PENDING,
)

CHART_STYLES = ("simple-chord-sheet", "rhythm-section-sheet")
ORIENTATIONS = ("portrait", "landscape")
DEVICE_PERFORMANCE_CLASSES = ("oldest-supported", "current-reference")
PACES = ("natural", "fast", "careful")
SIZE_BUCKETS = ("small", "normal", "large")
HANDEDNESS = ("left", "right")
PENCIL_EXPERIENCE_BUCKETS = ("novice", "experienced")
CONSTRUCTION_VARIATIONS = ("root-first", "modifier-first", "mixed-or-retraced")
