"""Pure public-source construction for synthetic whole-chord research.

This module composes already isolated UJI glyphs into explicitly synthetic
whole-chord ink.  It does not encode features, run a model, score predictions,
or expose a production/app entry point.  The label-bearing truth ledger and
the label-free prediction projection are deliberately separate objects.

The two acquisition-order rows for one spatial composition are paired stress
variants, not independent handwriting samples.  Reversing owner blocks never
reverses a glyph's strokes or points and never changes its spatial geometry.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass, replace
import hashlib
from typing import Sequence

from ..chord_notation import require_canonical_chord_label
from ..contracts import canonical_json_bytes
from ..features import (
    MAXIMUM_INPUT_POINT_COUNT,
    MAXIMUM_STROKE_COUNT,
    TRAJECTORY_SAMPLE_COUNT,
    InkStroke,
)
from ..models.output_contract import factorize_canonical_label
from .stroke_affinity_experiment import affine, normalize, point_bounds
from .uji_personal import SOURCE_SHA256, Sample, split_writers


VERSION = "personal-whole-chord-source-v1"
ARTIFACT_KIND = "research-only-synthetic-whole-chord-source-v1"
PREDICTION_CONTRACT = "opaque-id-and-synthetic-strokes-only-v1"

ROOTS = tuple(
    letter + accidental
    for letter in "ABCDEFG"
    for accidental in ("", "b")
)
DESCRIPTORS = (
    "",
    "6",
    "7",
    "9",
    "11",
    "13",
    "-",
    "-6",
    "-7",
    "-9",
    "-11",
    "-13",
)
ACQUISITION_ORDERS = ("forwardOwnerBlocks", "reverseOwnerBlocks")
ROOT_DIMENSION = 32.0
OTHER_ATOM_DIMENSION = 16.0
ATOM_GAP = 8.0
BOTTOM_ALIGNMENT = 32.0
MAXIMUM_ATOM_COUNT = 6

ROLE_COUNTS = {"training": 32, "development": 8}
ROLE_SAMPLE_COUNTS = {"training": 6_208, "development": 1_552}


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _stroke_value(stroke: InkStroke) -> dict[str, object]:
    if stroke.bounds is None:
        raise ValueError("Synthetic source strokes require explicit bounds")
    return {
        "bounds": {
            "maxX": float(stroke.bounds.max_x),
            "maxY": float(stroke.bounds.max_y),
            "minX": float(stroke.bounds.min_x),
            "minY": float(stroke.bounds.min_y),
        },
        "creationTimeOffset": (
            None
            if stroke.creation_time_offset is None
            else float(stroke.creation_time_offset)
        ),
        "points": [
            {
                "timeOffset": None if point.time_offset is None else float(point.time_offset),
                "x": float(point.x),
                "y": float(point.y),
            }
            for point in stroke.points
        ],
    }


def canonical_strokes_value(strokes: Sequence[InkStroke]) -> list[dict[str, object]]:
    """Exact canonical full-geometry value shared by prediction/control receipts."""

    return [_stroke_value(stroke) for stroke in strokes]


def canonical_strokes_sha256(strokes: Sequence[InkStroke]) -> str:
    return _sha256(canonical_json_bytes(canonical_strokes_value(strokes)))


@dataclass(frozen=True)
class WholeChordAtomTransform:
    target_dimension: float
    source_normalization_scale: float
    source_normalization_dx: float
    source_normalization_dy: float
    atom_scale: float
    translation_dx: float
    translation_dy: float
    combined_scale: float
    combined_dx: float
    combined_dy: float
    gap_after: float

    def value(self) -> dict[str, float]:
        return {
            "atomScale": self.atom_scale,
            "combinedDX": self.combined_dx,
            "combinedDY": self.combined_dy,
            "combinedScale": self.combined_scale,
            "gapAfter": self.gap_after,
            "sourceNormalizationDX": self.source_normalization_dx,
            "sourceNormalizationDY": self.source_normalization_dy,
            "sourceNormalizationScale": self.source_normalization_scale,
            "targetDimension": self.target_dimension,
            "translationDX": self.translation_dx,
            "translationDY": self.translation_dy,
        }

    @property
    def sha256(self) -> str:
        return _sha256(canonical_json_bytes(self.value()))


@dataclass(frozen=True)
class WholeChordAtomPlacement:
    atom_ordinal: int
    source_label: str
    source_id: str
    source_sha256: str
    source_stroke_indexes: tuple[int, ...]
    spatial_stroke_indexes: tuple[int, ...]
    acquisition_stroke_indexes: tuple[int, ...]
    original_strokes: tuple[InkStroke, ...]
    transformed_strokes: tuple[InkStroke, ...]
    transformed_sha256: str
    transform: WholeChordAtomTransform


@dataclass(frozen=True)
class WholeChordSourceExample:
    sample_id: str
    pair_id: str
    role: str
    writer: str
    session: int
    canonical_label: str
    atom_labels: tuple[str, ...]
    acquisition_order: str
    atoms: tuple[WholeChordAtomPlacement, ...]
    strokes: tuple[InkStroke, ...]
    stroke_count: int
    point_count: int
    minimum_required_trajectory_samples: int
    source_membership_sha256: str
    transformation_sha256: str
    trajectory_source_sha256: str


@dataclass(frozen=True)
class WholeChordPredictionInput:
    """The only object supplied to a prediction process."""

    sample_id: str
    input_sha256: str
    strokes: tuple[InkStroke, ...]


@dataclass(frozen=True)
class WholeChordAtomicOwnerInput:
    """Label-free exact-owner input for the separately disclosed atomic control.

    The outer group order is spatial atom order.  Each inner index addresses
    ``strokes`` in acquisition order, so reversed-owner rows keep identical
    spatial owner order without pretending acquisition order is reading order.
    """

    sample_id: str
    input_sha256: str
    strokes: tuple[InkStroke, ...]
    oracle_owner_groups: tuple[tuple[int, ...], ...]


@dataclass(frozen=True)
class WholeChordSourcePlan:
    version: str
    source_sha256: str
    role: str
    writers: tuple[str, ...]
    examples: tuple[WholeChordSourceExample, ...]
    exposure_ledger: dict[str, object]


def canonical_chord_specs() -> tuple[tuple[str, tuple[str, ...]], ...]:
    """Return the fixed 168 labels and their exact isolated-source atoms."""

    result = []
    for root in ROOTS:
        for descriptor in DESCRIPTORS:
            canonical = require_canonical_chord_label(root + descriptor)
            factorize_canonical_label(canonical)
            atoms = tuple(root) + tuple(descriptor)
            if not 1 <= len(atoms) <= MAXIMUM_ATOM_COUNT:
                raise ValueError("Canonical synthetic chord exceeds the atom limit")
            result.append((canonical, atoms))
    frozen = tuple(result)
    if len(frozen) != 168 or len({label for label, _ in frozen}) != 168:
        raise ValueError("Fixed synthetic chord vocabulary is incomplete")
    return frozen


def _validate_complete_source_metadata(
    records: tuple[Sample, ...], role: str
) -> tuple[tuple[Sample, ...], tuple[str, ...]]:
    """Select the fixed role before any point, bound, or feature operation."""

    if role not in ROLE_COUNTS:
        raise ValueError("Whole-chord source role must be training or development")
    if not isinstance(records, tuple) or len(records) != 11_640:
        raise ValueError("Complete frozen UJI metadata is required")
    if len({sample.identity for sample in records}) != len(records):
        raise ValueError("Duplicate UJI source identity")
    writers = {sample.writer for sample in records}
    labels = {sample.label for sample in records}
    if (
        len(writers) != 60
        or len(labels) != 97
        or any(not isinstance(label, str) or len(label) != 1 for label in labels)
    ):
        raise ValueError("Incomplete UJI writer or label metadata")
    by_writer_session: dict[tuple[str, int], set[str]] = defaultdict(set)
    for sample in records:
        if sample.session not in (1, 2):
            raise ValueError("UJI source has an invalid session")
        by_writer_session[(sample.writer, sample.session)].add(sample.label)
    expected_keys = {(writer, session) for writer in writers for session in (1, 2)}
    if set(by_writer_session) != expected_keys or any(
        observed != labels for observed in by_writer_session.values()
    ):
        raise ValueError("Incomplete UJI writer/session label grid")

    training, development, reserved = split_writers(records)
    selected_writers = training if role == "training" else development
    if (
        len(selected_writers) != ROLE_COUNTS[role]
        or set(selected_writers) & set(reserved)
        or set(training) & set(development)
    ):
        raise ValueError("Frozen UJI writer roles overlap or changed")
    required_labels = {atom for _, atoms in canonical_chord_specs() for atom in atoms}
    if not required_labels <= labels:
        raise ValueError("UJI source lacks a required synthetic chord atom")
    selected = tuple(sample for sample in records if sample.writer in selected_writers)
    if (
        len(selected) != ROLE_SAMPLE_COUNTS[role]
        or any(sample.writer not in selected_writers for sample in selected)
    ):
        raise ValueError("Wrong-role sample entered the source selection")
    return selected, selected_writers


def _validate_atom_sources(samples: Sequence[Sample]) -> tuple[int, int, int]:
    if not 1 <= len(samples) <= MAXIMUM_ATOM_COUNT:
        raise ValueError("Synthetic chord has an invalid atom count")
    identities = {(sample.writer, sample.session) for sample in samples}
    if len(identities) != 1:
        raise ValueError("Every atom must come from one writer and session")
    stroke_count = 0
    point_count = 0
    minimum_samples = 0
    for sample in samples:
        if not sample.strokes:
            raise ValueError("Synthetic atom has no strokes")
        for stroke in sample.strokes:
            if not stroke.points:
                raise ValueError("Synthetic atom has an empty stroke")
            if stroke.creation_time_offset is not None or any(
                point.time_offset is not None for point in stroke.points
            ):
                raise ValueError("UJI synthetic atoms must not invent timing")
            stroke_count += 1
            point_count += len(stroke.points)
            minimum_samples += 1 if len(stroke.points) == 1 else 2
    if stroke_count > MAXIMUM_STROKE_COUNT:
        raise ValueError("Synthetic chord exceeds the stroke limit")
    if point_count > MAXIMUM_INPUT_POINT_COUNT:
        raise ValueError("Synthetic chord exceeds the point limit")
    if minimum_samples > TRAJECTORY_SAMPLE_COUNT:
        raise ValueError("Synthetic chord cannot fit the trajectory representation")
    return stroke_count, point_count, minimum_samples


def _source_atom_value(sample: Sample) -> dict[str, object]:
    return {
        "sourceID": sample.identity,
        "sourceLabel": sample.label,
        "strokes": canonical_strokes_value(sample.strokes),
    }


def _compose_spatial_atoms(
    samples: Sequence[Sample],
) -> tuple[tuple[WholeChordAtomPlacement, ...], tuple[InkStroke, ...]]:
    _validate_atom_sources(samples)
    placements = []
    spatial_strokes = []
    left_edge = 0.0
    for atom_ordinal, sample in enumerate(samples):
        source_left, source_top, source_right, source_bottom = point_bounds(sample.strokes)
        source_span = max(source_right - source_left, source_bottom - source_top)
        source_scale = ROOT_DIMENSION / source_span if source_span > 0.0 else 1.0
        source_dx = -source_left * source_scale
        source_dy = -source_top * source_scale

        normalized = normalize(sample.strokes, ROOT_DIMENSION)
        normalized_left, normalized_top, normalized_right, normalized_bottom = point_bounds(
            normalized
        )
        target_dimension = ROOT_DIMENSION if atom_ordinal == 0 else OTHER_ATOM_DIMENSION
        normalized_span = max(
            normalized_right - normalized_left,
            normalized_bottom - normalized_top,
        )
        atom_scale = target_dimension / ROOT_DIMENSION if normalized_span > 0.0 else 1.0
        scaled = affine(normalized, atom_scale, 0.0, 0.0)
        left, _, right, bottom = point_bounds(scaled)
        translation_dx = left_edge - left
        translation_dy = BOTTOM_ALIGNMENT - bottom
        transformed = affine(scaled, 1.0, translation_dx, translation_dy)
        start = len(spatial_strokes)
        spatial_indexes = tuple(range(start, start + len(transformed)))
        spatial_strokes.extend(transformed)
        gap_after = ATOM_GAP if atom_ordinal + 1 < len(samples) else 0.0
        transform = WholeChordAtomTransform(
            target_dimension=target_dimension,
            source_normalization_scale=source_scale,
            source_normalization_dx=source_dx,
            source_normalization_dy=source_dy,
            atom_scale=atom_scale,
            translation_dx=translation_dx,
            translation_dy=translation_dy,
            combined_scale=source_scale * atom_scale,
            combined_dx=source_dx * atom_scale + translation_dx,
            combined_dy=source_dy * atom_scale + translation_dy,
            gap_after=gap_after,
        )
        source_payload = canonical_json_bytes(_source_atom_value(sample))
        placements.append(
            WholeChordAtomPlacement(
                atom_ordinal=atom_ordinal,
                source_label=sample.label,
                source_id=sample.identity,
                source_sha256=_sha256(source_payload),
                source_stroke_indexes=tuple(range(len(sample.strokes))),
                spatial_stroke_indexes=spatial_indexes,
                acquisition_stroke_indexes=(),
                original_strokes=tuple(sample.strokes),
                transformed_strokes=tuple(transformed),
                transformed_sha256=canonical_strokes_sha256(transformed),
                transform=transform,
            )
        )
        left_edge += right - left + gap_after
    return tuple(placements), tuple(spatial_strokes)


def _compose_chord_examples(
    samples: Sequence[Sample], role: str, canonical_label: str
) -> tuple[WholeChordSourceExample, WholeChordSourceExample]:
    canonical_label = require_canonical_chord_label(canonical_label)
    atom_labels = tuple(canonical_label)
    if tuple(sample.label for sample in samples) != atom_labels:
        raise ValueError("Synthetic chord atoms do not match its canonical label")
    stroke_count, point_count, minimum_samples = _validate_atom_sources(samples)
    placements, spatial_strokes = _compose_spatial_atoms(samples)
    if len(spatial_strokes) != stroke_count:
        raise ValueError("Synthetic spatial transform changed stroke count")

    source_membership = [
        {
            "atomOrdinal": atom.atom_ordinal,
            "sourceID": atom.source_id,
            "sourceLabel": atom.source_label,
            "sourceSHA256": atom.source_sha256,
        }
        for atom in placements
    ]
    source_membership_sha256 = _sha256(canonical_json_bytes(source_membership))
    transformation = [
        {
            "atomOrdinal": atom.atom_ordinal,
            "spatialStrokeIndexes": list(atom.spatial_stroke_indexes),
            "transform": atom.transform.value(),
            "transformSHA256": atom.transform.sha256,
            "transformedSHA256": atom.transformed_sha256,
        }
        for atom in placements
    ]
    transformation_sha256 = _sha256(canonical_json_bytes(transformation))
    writer, session = samples[0].writer, samples[0].session
    pair_id = _sha256(
        canonical_json_bytes(
            {
                "canonicalLabel": canonical_label,
                "role": role,
                "session": session,
                "sourceMembershipSHA256": source_membership_sha256,
                "transformationSHA256": transformation_sha256,
                "version": VERSION,
                "writer": writer,
            }
        )
    )

    examples = []
    for acquisition_order in ACQUISITION_ORDERS:
        block_order = (
            tuple(range(len(placements)))
            if acquisition_order == "forwardOwnerBlocks"
            else tuple(reversed(range(len(placements))))
        )
        acquisition_strokes = []
        acquisition_indexes: dict[int, tuple[int, ...]] = {}
        for atom_index in block_order:
            atom = placements[atom_index]
            start = len(acquisition_strokes)
            acquisition_strokes.extend(atom.transformed_strokes)
            acquisition_indexes[atom_index] = tuple(
                range(start, start + len(atom.transformed_strokes))
            )
        variant_atoms = tuple(
            replace(
                atom,
                acquisition_stroke_indexes=acquisition_indexes[atom.atom_ordinal],
            )
            for atom in placements
        )
        final_strokes = tuple(acquisition_strokes)
        sample_id = _sha256(
            canonical_json_bytes(
                {
                    "acquisitionOrder": acquisition_order,
                    "pairID": pair_id,
                    "predictionContract": PREDICTION_CONTRACT,
                    "version": VERSION,
                }
            )
        )
        examples.append(
            WholeChordSourceExample(
                sample_id=sample_id,
                pair_id=pair_id,
                role=role,
                writer=writer,
                session=session,
                canonical_label=canonical_label,
                atom_labels=atom_labels,
                acquisition_order=acquisition_order,
                atoms=variant_atoms,
                strokes=final_strokes,
                stroke_count=stroke_count,
                point_count=point_count,
                minimum_required_trajectory_samples=minimum_samples,
                source_membership_sha256=source_membership_sha256,
                transformation_sha256=transformation_sha256,
                trajectory_source_sha256=canonical_strokes_sha256(final_strokes),
            )
        )
    if sorted(canonical_strokes_sha256(example.strokes) for example in examples) != sorted(
        canonical_strokes_sha256(
            tuple(
                stroke
                for atom_index in block_order
                for stroke in placements[atom_index].transformed_strokes
            )
        )
        for block_order in (
            tuple(range(len(placements))),
            tuple(reversed(range(len(placements)))),
        )
    ):
        raise ValueError("Synthetic acquisition variants lost transformed ink")
    return examples[0], examples[1]


def _source_exposure_ledger(
    role: str,
    writers: tuple[str, ...],
    examples: tuple[WholeChordSourceExample, ...],
) -> dict[str, object]:
    pairs: dict[str, list[WholeChordSourceExample]] = defaultdict(list)
    source_counts: Counter[str] = Counter()
    label_counts: Counter[str] = Counter()
    canonical_counts: Counter[str] = Counter()
    for example in examples:
        pairs[example.pair_id].append(example)
        canonical_counts[example.canonical_label] += 1
        for atom in example.atoms:
            source_counts[atom.source_id] += 1
            label_counts[atom.source_label] += 1
    if any(
        len(rows) != 2
        or {row.acquisition_order for row in rows} != set(ACQUISITION_ORDERS)
        or len({row.source_membership_sha256 for row in rows}) != 1
        or len({row.transformation_sha256 for row in rows}) != 1
        for rows in pairs.values()
    ):
        raise ValueError("Acquisition-order pairs are incomplete")
    expected_pairs = len(writers) * 2 * 168
    if len(pairs) != expected_pairs or len(examples) != expected_pairs * 2:
        raise ValueError("Whole-chord role plan has the wrong fixed size")
    return {
        "acquisitionVariantsArePairedNotIndependent": True,
        "atomExposureCount": sum(source_counts.values()),
        "atomExposureCountWithoutPairedDuplication": sum(source_counts.values()) // 2,
        "canonicalLabelCount": len(canonical_counts),
        "canonicalLabelExposureCounts": dict(sorted(canonical_counts.items())),
        "recordCount": len(examples),
        "role": role,
        "sessionCountPerWriter": 2,
        "sourceAtomExposureCounts": dict(sorted(source_counts.items())),
        "sourceLabelExposureCounts": dict(sorted(label_counts.items())),
        "sameObservedAtomMayAppearMultipleTimesWithinAComposition": True,
        "spatialCompositionCount": len(pairs),
        "syntheticNotNaturalInk": True,
        "uniqueSourceAtomCount": len(source_counts),
        "version": VERSION,
        "withinCompositionRepeatedSourceOccurrenceCount": sum(
            len(rows[0].atoms) - len({atom.source_id for atom in rows[0].atoms})
            for rows in pairs.values()
        ),
        "writerCount": len(writers),
    }


def build_role_plan(records: tuple[Sample, ...], role: str) -> WholeChordSourcePlan:
    """Build one complete fixed role without encoding features or model inputs."""

    selected, writers = _validate_complete_source_metadata(records, role)
    lookup = {
        (sample.writer, sample.session, sample.label): sample for sample in selected
    }
    if len(lookup) != len(selected):
        raise ValueError("Selected UJI role contains duplicate atoms")
    examples = []
    for writer in writers:
        for session in (1, 2):
            for canonical_label, atom_labels in canonical_chord_specs():
                atom_samples = tuple(lookup[(writer, session, label)] for label in atom_labels)
                examples.extend(_compose_chord_examples(atom_samples, role, canonical_label))
    frozen = tuple(examples)
    if len({example.sample_id for example in frozen}) != len(frozen):
        raise ValueError("Opaque whole-chord sample identity collision")
    ledger = _source_exposure_ledger(role, writers, frozen)
    return WholeChordSourcePlan(
        version=VERSION,
        source_sha256=SOURCE_SHA256,
        role=role,
        writers=writers,
        examples=frozen,
        exposure_ledger=ledger,
    )


def prediction_inputs(plan: WholeChordSourcePlan) -> tuple[WholeChordPredictionInput, ...]:
    """Project only opaque identity and synthetic ink into prediction."""

    if not isinstance(plan, WholeChordSourcePlan) or plan.version != VERSION:
        raise ValueError("Unexpected whole-chord source plan")
    return tuple(
        WholeChordPredictionInput(
            sample_id=example.sample_id,
            input_sha256=example.trajectory_source_sha256,
            strokes=example.strokes,
        )
        for example in plan.examples
    )


def atomic_owner_inputs(
    plan: WholeChordSourcePlan,
) -> tuple[WholeChordAtomicOwnerInput, ...]:
    """Project complete spatially ordered ownership without source or label truth."""

    if not isinstance(plan, WholeChordSourcePlan) or plan.version != VERSION:
        raise ValueError("Unexpected whole-chord source plan")
    result = []
    for example in plan.examples:
        groups = tuple(atom.acquisition_stroke_indexes for atom in example.atoms)
        flattened = tuple(index for group in groups for index in group)
        if (
            any(not group for group in groups)
            or len(flattened) != len(set(flattened))
            or set(flattened) != set(range(len(example.strokes)))
        ):
            raise ValueError("Synthetic atomic ownership is not a complete partition")
        result.append(
            WholeChordAtomicOwnerInput(
                sample_id=example.sample_id,
                input_sha256=example.trajectory_source_sha256,
                strokes=example.strokes,
                oracle_owner_groups=groups,
            )
        )
    return tuple(result)


def _atom_truth_value(atom: WholeChordAtomPlacement) -> dict[str, object]:
    return {
        "acquisitionStrokeIndexes": list(atom.acquisition_stroke_indexes),
        "atomOrdinal": atom.atom_ordinal,
        "sourceID": atom.source_id,
        "sourceLabel": atom.source_label,
        "sourceSHA256": atom.source_sha256,
        "sourceStrokeIndexes": list(atom.source_stroke_indexes),
        "spatialStrokeIndexes": list(atom.spatial_stroke_indexes),
        "transform": atom.transform.value(),
        "transformationSHA256": atom.transform.sha256,
        "transformedSHA256": atom.transformed_sha256,
    }


def _example_truth_value(example: WholeChordSourceExample) -> dict[str, object]:
    return {
        "acquisitionOrder": example.acquisition_order,
        "atomLabels": list(example.atom_labels),
        "atoms": [_atom_truth_value(atom) for atom in example.atoms],
        "canonicalLabel": example.canonical_label,
        "inputSHA256": example.trajectory_source_sha256,
        "minimumRequiredTrajectorySamples": example.minimum_required_trajectory_samples,
        "pairID": example.pair_id,
        "pointCount": example.point_count,
        "role": example.role,
        "sampleID": example.sample_id,
        "session": example.session,
        "sourceMembershipSHA256": example.source_membership_sha256,
        "strokeCount": example.stroke_count,
        "syntheticNotNaturalInk": True,
        "trajectorySourceSHA256": example.trajectory_source_sha256,
        "transformationSHA256": example.transformation_sha256,
        "writer": example.writer,
    }


def _ink_banks(examples: Sequence[WholeChordSourceExample]) -> tuple[dict, dict]:
    """Deduplicate exact original and transformed point values in durable truth."""

    source_bank: dict[str, dict[str, object]] = {}
    transformed_bank: dict[str, dict[str, object]] = {}
    for example in examples:
        for atom in example.atoms:
            source_value = {
                "sourceID": atom.source_id,
                "sourceLabel": atom.source_label,
                "strokes": canonical_strokes_value(atom.original_strokes),
            }
            if _sha256(canonical_json_bytes(source_value)) != atom.source_sha256:
                raise ValueError("Source atom hash does not bind exact original ink")
            previous_source = source_bank.setdefault(atom.source_sha256, source_value)
            if previous_source != source_value:
                raise ValueError("Source atom hash collision")

            transformed_value = {"strokes": canonical_strokes_value(atom.transformed_strokes)}
            if canonical_strokes_sha256(atom.transformed_strokes) != atom.transformed_sha256:
                raise ValueError("Transformed atom hash does not bind exact derived ink")
            previous_transformed = transformed_bank.setdefault(
                atom.transformed_sha256, transformed_value
            )
            if previous_transformed != transformed_value:
                raise ValueError("Transformed atom hash collision")
    return source_bank, transformed_bank


def truth_ledger(plan: WholeChordSourcePlan) -> dict[str, object]:
    """Return complete label/source truth, never a prediction-process input."""

    if not isinstance(plan, WholeChordSourcePlan) or plan.version != VERSION:
        raise ValueError("Unexpected whole-chord source plan")
    source_bank, transformed_bank = _ink_banks(plan.examples)
    return {
        "artifactKind": ARTIFACT_KIND,
        "exposureLedger": plan.exposure_ledger,
        "predictionContract": PREDICTION_CONTRACT,
        "role": plan.role,
        "rows": [_example_truth_value(example) for example in plan.examples],
        "sourceAtomBank": source_bank,
        "sourceSHA256": plan.source_sha256,
        "syntheticNotNaturalInk": True,
        "transformedAtomBank": transformed_bank,
        "version": VERSION,
        "writers": list(plan.writers),
    }


def truth_ledger_bytes(plan: WholeChordSourcePlan) -> bytes:
    return canonical_json_bytes(truth_ledger(plan))


def truth_ledger_sha256(plan: WholeChordSourcePlan) -> str:
    return _sha256(truth_ledger_bytes(plan))


__all__ = (
    "ACQUISITION_ORDERS",
    "ARTIFACT_KIND",
    "ATOM_GAP",
    "BOTTOM_ALIGNMENT",
    "DESCRIPTORS",
    "MAXIMUM_ATOM_COUNT",
    "OTHER_ATOM_DIMENSION",
    "PREDICTION_CONTRACT",
    "ROOTS",
    "ROOT_DIMENSION",
    "VERSION",
    "WholeChordAtomPlacement",
    "WholeChordAtomTransform",
    "WholeChordAtomicOwnerInput",
    "WholeChordPredictionInput",
    "WholeChordSourceExample",
    "WholeChordSourcePlan",
    "atomic_owner_inputs",
    "build_role_plan",
    "canonical_strokes_sha256",
    "canonical_strokes_value",
    "canonical_chord_specs",
    "prediction_inputs",
    "truth_ledger",
    "truth_ledger_bytes",
    "truth_ledger_sha256",
)
