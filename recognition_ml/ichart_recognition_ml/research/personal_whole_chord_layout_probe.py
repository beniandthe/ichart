"""Input-only synthetic layout probes for the frozen whole-chord factor model.

This module never trains or selects a model.  ``predict`` authenticates an
already-frozen whole-chord fit and its complete base predictions, publishes
the two fixed probe geometries, and only then replays the unchanged checkpoint.
``score`` authenticates both raw freezes before rebuilding or consulting truth.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, replace
import hashlib
import math
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np

from ..contracts import canonical_json_bytes
from ..features import InkStroke
from . import personal_whole_chord_factor as factor
from . import personal_whole_chord_scoring as base_scoring
from . import personal_whole_chord_source as source
from .stroke_affinity_experiment import affine, normalize, point_bounds


VERSION = "personal-whole-chord-layout-probe-v1"
PROVENANCE_VERSION = "personal-whole-chord-layout-provenance-v1"
PREDICTION_VERSION = "personal-whole-chord-layout-predictions-v1"
RECEIPT_VERSION = "personal-whole-chord-layout-prediction-receipt-v1"
SCORE_VERSION = "personal-whole-chord-layout-score-v1"
SCOPE = "public-uji-synthetic-whole-chord-layout-sensitivity-research-not-production"
PROTOCOL_PATH = "docs/personal-whole-chord-layout-probe-protocol-2026-10-02.md"
MODULE_PATH = "recognition_ml/ichart_recognition_ml/research/personal_whole_chord_layout_probe.py"
TEST_PATH = "recognition_ml/tests/test_personal_whole_chord_layout_probe.py"
CODE_PATHS = factor.CODE_PATHS + (PROTOCOL_PATH, MODULE_PATH, TEST_PATH)

BASE_ROW_COUNT = factor.DEVELOPMENT_EXAMPLE_COUNT
PROBE_ROW_COUNT = BASE_ROW_COUNT * 2
ROWS_PER_ORDER_PER_PROBE = BASE_ROW_COUNT // len(source.ACQUISITION_ORDERS)


@dataclass(frozen=True)
class LayoutDefinition:
    name: str
    root_dimension: float
    other_dimension: float
    gap: float
    bottom: float = source.BOTTOM_ALIGNMENT

    def value(self) -> dict[str, object]:
        return {
            "bottom": self.bottom,
            "gap": self.gap,
            "name": self.name,
            "otherAtomDimension": self.other_dimension,
            "rootAtomDimension": self.root_dimension,
        }


PROBES = (
    LayoutDefinition("equalAtomSize", 32.0, 32.0, 8.0),
    LayoutDefinition("zeroAtomGap", 32.0, 16.0, 0.0),
)
PROBE_BY_NAME = {probe.name: probe for probe in PROBES}


@dataclass(frozen=True)
class LayoutProbeExample:
    probe_id: str
    probe_name: str
    base_sample_id: str
    base_pair_id: str
    base_input_sha256: str
    base_transformation_sha256: str
    role: str
    writer: str
    session: int
    canonical_label: str
    acquisition_order: str
    source_membership_sha256: str
    atoms: tuple[source.WholeChordAtomPlacement, ...]
    strokes: tuple[InkStroke, ...]
    stroke_count: int
    point_count: int
    minimum_required_trajectory_samples: int
    transformation_sha256: str
    input_sha256: str


@dataclass(frozen=True)
class LayoutProbePlan:
    version: str
    source_plan_version: str
    source_sha256: str
    writers: tuple[str, ...]
    base_row_count: int
    examples: tuple[LayoutProbeExample, ...]


@dataclass(frozen=True)
class LayoutProbePredictionInput:
    probe_id: str
    input_sha256: str
    strokes: tuple[InkStroke, ...]

    @property
    def sample_id(self) -> str:
        return self.probe_id


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _source_atom_value(atom: source.WholeChordAtomPlacement) -> dict[str, object]:
    return {
        "sourceID": atom.source_id,
        "sourceLabel": atom.source_label,
        "strokes": source.canonical_strokes_value(atom.original_strokes),
    }


def _transformation_value(atoms: Sequence[source.WholeChordAtomPlacement]) -> list[dict[str, object]]:
    return [
        {
            "atomOrdinal": atom.atom_ordinal,
            "spatialStrokeIndexes": list(atom.spatial_stroke_indexes),
            "transform": atom.transform.value(),
            "transformSHA256": atom.transform.sha256,
            "transformedSHA256": atom.transformed_sha256,
        }
        for atom in atoms
    ]


def _validate_base_example(example: source.WholeChordSourceExample) -> None:
    if (
        not isinstance(example, source.WholeChordSourceExample)
        or example.role != "development"
        or example.acquisition_order not in source.ACQUISITION_ORDERS
        or not example.atoms
        or tuple(atom.atom_ordinal for atom in example.atoms) != tuple(range(len(example.atoms)))
        or tuple(atom.source_label for atom in example.atoms) != example.atom_labels
    ):
        raise ValueError("base whole-chord example is malformed or outside development")
    for atom in example.atoms:
        if (
            _sha256(canonical_json_bytes(_source_atom_value(atom))) != atom.source_sha256
            or source.canonical_strokes_sha256(atom.transformed_strokes) != atom.transformed_sha256
            or any(stroke.creation_time_offset is not None for stroke in atom.original_strokes)
            or any(point.time_offset is not None for stroke in atom.original_strokes for point in stroke.points)
        ):
            raise ValueError("base atom source or timing binding changed")
    membership = [
        {
            "atomOrdinal": atom.atom_ordinal,
            "sourceID": atom.source_id,
            "sourceLabel": atom.source_label,
            "sourceSHA256": atom.source_sha256,
        }
        for atom in example.atoms
    ]
    spatial = [index for atom in example.atoms for index in atom.spatial_stroke_indexes]
    acquisition = [index for atom in example.atoms for index in atom.acquisition_stroke_indexes]
    expected = tuple(
        stroke
        for atom in (
            example.atoms
            if example.acquisition_order == "forwardOwnerBlocks"
            else tuple(reversed(example.atoms))
        )
        for stroke in atom.transformed_strokes
    )
    if (
        expected != example.strokes
        or source.canonical_strokes_sha256(expected) != example.trajectory_source_sha256
        or _sha256(canonical_json_bytes(membership)) != example.source_membership_sha256
        or sorted(spatial) != list(range(example.stroke_count))
        or sorted(acquisition) != list(range(example.stroke_count))
        or example.stroke_count != len(example.strokes)
        or example.point_count != sum(len(stroke.points) for stroke in example.strokes)
        or _sha256(canonical_json_bytes(_transformation_value(example.atoms)))
        != example.transformation_sha256
    ):
        raise ValueError("base whole-chord geometry binding changed")


def compose_probe_example(
    example: source.WholeChordSourceExample, definition: LayoutDefinition
) -> LayoutProbeExample:
    """Recompose one base example from its exact original atom strokes."""

    _validate_base_example(example)
    if definition not in PROBES:
        raise ValueError("layout probe definition is not frozen")
    placements: list[source.WholeChordAtomPlacement] = []
    spatial_strokes: list[InkStroke] = []
    left_edge = 0.0
    for ordinal, base_atom in enumerate(example.atoms):
        original = base_atom.original_strokes
        source_left, source_top, source_right, source_bottom = point_bounds(original)
        source_span = max(source_right - source_left, source_bottom - source_top)
        source_scale = source.ROOT_DIMENSION / source_span if source_span > 0.0 else 1.0
        source_dx, source_dy = -source_left * source_scale, -source_top * source_scale
        normalized = normalize(original, source.ROOT_DIMENSION)
        norm_left, norm_top, norm_right, norm_bottom = point_bounds(normalized)
        norm_span = max(norm_right - norm_left, norm_bottom - norm_top)
        target = definition.root_dimension if ordinal == 0 else definition.other_dimension
        atom_scale = target / source.ROOT_DIMENSION if norm_span > 0.0 else 1.0
        scaled = affine(normalized, atom_scale, 0.0, 0.0)
        left, _, right, bottom = point_bounds(scaled)
        dx, dy = left_edge - left, definition.bottom - bottom
        transformed = affine(scaled, 1.0, dx, dy)
        start = len(spatial_strokes)
        spatial_indexes = tuple(range(start, start + len(transformed)))
        spatial_strokes.extend(transformed)
        gap_after = definition.gap if ordinal + 1 < len(example.atoms) else 0.0
        transform = source.WholeChordAtomTransform(
            target_dimension=target,
            source_normalization_scale=source_scale,
            source_normalization_dx=source_dx,
            source_normalization_dy=source_dy,
            atom_scale=atom_scale,
            translation_dx=dx,
            translation_dy=dy,
            combined_scale=source_scale * atom_scale,
            combined_dx=source_dx * atom_scale + dx,
            combined_dy=source_dy * atom_scale + dy,
            gap_after=gap_after,
        )
        placements.append(
            replace(
                base_atom,
                spatial_stroke_indexes=spatial_indexes,
                acquisition_stroke_indexes=(),
                transformed_strokes=tuple(transformed),
                transformed_sha256=source.canonical_strokes_sha256(transformed),
                transform=transform,
            )
        )
        left_edge += right - left + gap_after

    block_order = (
        tuple(range(len(placements)))
        if example.acquisition_order == "forwardOwnerBlocks"
        else tuple(reversed(range(len(placements))))
    )
    acquired: list[InkStroke] = []
    acquisition_indexes: dict[int, tuple[int, ...]] = {}
    for atom_index in block_order:
        atom = placements[atom_index]
        start = len(acquired)
        acquired.extend(atom.transformed_strokes)
        acquisition_indexes[atom_index] = tuple(range(start, start + len(atom.transformed_strokes)))
    frozen_atoms = tuple(
        replace(atom, acquisition_stroke_indexes=acquisition_indexes[atom.atom_ordinal])
        for atom in placements
    )
    strokes = tuple(acquired)
    if (
        len(strokes) != example.stroke_count
        or sum(len(stroke.points) for stroke in strokes) != example.point_count
        or any(stroke.creation_time_offset is not None for stroke in strokes)
        or any(point.time_offset is not None for stroke in strokes for point in stroke.points)
    ):
        raise ValueError("layout probe changed source membership, points, or timing")
    transformation_sha = _sha256(canonical_json_bytes(_transformation_value(frozen_atoms)))
    input_sha = source.canonical_strokes_sha256(strokes)
    probe_id = _sha256(
        canonical_json_bytes(
            {
                "baseSampleID": example.sample_id,
                "predictionContract": "opaque-layout-probe-id-and-strokes-only-v1",
                "probe": definition.name,
                "version": VERSION,
            }
        )
    )
    return LayoutProbeExample(
        probe_id=probe_id,
        probe_name=definition.name,
        base_sample_id=example.sample_id,
        base_pair_id=example.pair_id,
        base_input_sha256=example.trajectory_source_sha256,
        base_transformation_sha256=example.transformation_sha256,
        role=example.role,
        writer=example.writer,
        session=example.session,
        canonical_label=example.canonical_label,
        acquisition_order=example.acquisition_order,
        source_membership_sha256=example.source_membership_sha256,
        atoms=frozen_atoms,
        strokes=strokes,
        stroke_count=example.stroke_count,
        point_count=example.point_count,
        minimum_required_trajectory_samples=example.minimum_required_trajectory_samples,
        transformation_sha256=transformation_sha,
        input_sha256=input_sha,
    )


def build_probe_plan(base_plan: source.WholeChordSourcePlan) -> LayoutProbePlan:
    if (
        not isinstance(base_plan, source.WholeChordSourcePlan)
        or base_plan.version != source.VERSION
        or base_plan.source_sha256 != factor.SOURCE_SHA256
        or base_plan.role != "development"
        or len(base_plan.writers) != factor.DEVELOPMENT_WRITER_COUNT
        or len(base_plan.examples) != BASE_ROW_COUNT
    ):
        raise ValueError("layout probes require the complete frozen development plan")
    examples = tuple(
        compose_probe_example(base, probe)
        for probe in PROBES
        for base in base_plan.examples
    )
    if (
        len(examples) != PROBE_ROW_COUNT
        or len({row.probe_id for row in examples}) != PROBE_ROW_COUNT
        or Counter(row.probe_name for row in examples)
        != Counter({probe.name: BASE_ROW_COUNT for probe in PROBES})
    ):
        raise ValueError("layout probe workload is incomplete or duplicated")
    return LayoutProbePlan(
        version=VERSION,
        source_plan_version=base_plan.version,
        source_sha256=base_plan.source_sha256,
        writers=base_plan.writers,
        base_row_count=len(base_plan.examples),
        examples=examples,
    )


def prediction_inputs(
    plan: LayoutProbePlan, probe_name: str | None = None
) -> tuple[LayoutProbePredictionInput, ...]:
    if not isinstance(plan, LayoutProbePlan) or plan.version != VERSION:
        raise ValueError("unexpected layout probe plan")
    if probe_name is not None and probe_name not in PROBE_BY_NAME:
        raise ValueError("unknown layout probe")
    rows = plan.examples if probe_name is None else tuple(
        row for row in plan.examples if row.probe_name == probe_name
    )
    return tuple(LayoutProbePredictionInput(row.probe_id, row.input_sha256, row.strokes) for row in rows)


def _atom_value(atom: source.WholeChordAtomPlacement, base_atom: source.WholeChordAtomPlacement) -> dict[str, object]:
    return {
        "acquisitionStrokeIndexes": list(atom.acquisition_stroke_indexes),
        "atomOrdinal": atom.atom_ordinal,
        "baseTransform": base_atom.transform.value(),
        "baseTransformSHA256": base_atom.transform.sha256,
        "baseTransformedSHA256": base_atom.transformed_sha256,
        "probeTransform": atom.transform.value(),
        "probeTransformSHA256": atom.transform.sha256,
        "probeTransformedSHA256": atom.transformed_sha256,
        "sourceID": atom.source_id,
        "sourceLabel": atom.source_label,
        "sourceSHA256": atom.source_sha256,
        "sourceStrokeIndexes": list(atom.source_stroke_indexes),
        "spatialStrokeIndexes": list(atom.spatial_stroke_indexes),
    }


def provenance_value(plan: LayoutProbePlan, base_plan: source.WholeChordSourcePlan,
                     *, probe_protocol_sha256: str, original_protocol_sha256: str) -> dict[str, object]:
    if (
        plan.source_plan_version != base_plan.version
        or plan.writers != base_plan.writers
        or plan.base_row_count != len(base_plan.examples)
        or len(plan.examples) != len(PROBES) * len(base_plan.examples)
    ):
        raise ValueError("layout and base source plans differ")
    base_index = {row.sample_id: row for row in base_plan.examples}
    source_bank: dict[str, dict[str, object]] = {}
    base_bank: dict[str, dict[str, object]] = {}
    probe_bank: dict[str, dict[str, object]] = {}
    rows = []
    for row in plan.examples:
        base = base_index.get(row.base_sample_id)
        if base is None or len(base.atoms) != len(row.atoms):
            raise ValueError("layout probe lacks exact base lineage")
        atoms = []
        for atom, base_atom in zip(row.atoms, base.atoms):
            if atom.source_sha256 != base_atom.source_sha256:
                raise ValueError("layout probe atom differs from base source atom")
            original = _source_atom_value(atom)
            base_value = {"strokes": source.canonical_strokes_value(base_atom.transformed_strokes)}
            probe_value = {"strokes": source.canonical_strokes_value(atom.transformed_strokes)}
            if _sha256(canonical_json_bytes(original)) != atom.source_sha256:
                raise ValueError("layout source atom bank binding changed")
            for bank, key, value in (
                (source_bank, atom.source_sha256, original),
                (base_bank, base_atom.transformed_sha256, base_value),
                (probe_bank, atom.transformed_sha256, probe_value),
            ):
                prior = bank.setdefault(key, value)
                if prior != value:
                    raise ValueError("layout provenance bank hash collision")
            atoms.append(_atom_value(atom, base_atom))
        rows.append(
            {
                "acquisitionOrder": row.acquisition_order,
                "atoms": atoms,
                "baseInputSHA256": row.base_input_sha256,
                "basePairID": row.base_pair_id,
                "baseSampleID": row.base_sample_id,
                "baseTransformationSHA256": row.base_transformation_sha256,
                "canonicalLabel": row.canonical_label,
                "inputSHA256": row.input_sha256,
                "minimumRequiredTrajectorySamples": row.minimum_required_trajectory_samples,
                "pointCount": row.point_count,
                "probe": row.probe_name,
                "probeID": row.probe_id,
                "role": row.role,
                "session": row.session,
                "sourceMembershipSHA256": row.source_membership_sha256,
                "strokeCount": row.stroke_count,
                "syntheticNotNaturalInk": True,
                "timingAvailable": False,
                "transformationSHA256": row.transformation_sha256,
                "writer": row.writer,
            }
        )
    return {
        "artifactKind": "research-only-whole-chord-layout-provenance-v1",
        "baseRowCount": plan.base_row_count,
        "baseTransformedAtomBank": base_bank,
        "labelsSuppliedToPredictor": False,
        "originalProtocolSHA256": original_protocol_sha256,
        "probeDefinitions": [probe.value() for probe in PROBES],
        "probeProtocolSHA256": probe_protocol_sha256,
        "probeRowCount": len(rows),
        "probeTransformedAtomBank": probe_bank,
        "role": "development",
        "rows": rows,
        "sourceAtomBank": source_bank,
        "sourcePlanVersion": plan.source_plan_version,
        "sourceSHA256": plan.source_sha256,
        "syntheticNotNaturalInk": True,
        "version": PROVENANCE_VERSION,
        "writers": list(plan.writers),
    }


def _counts(rows: Sequence[Mapping[str, object]]) -> dict[str, int]:
    result = Counter()
    for row in rows:
        base_correct, probe_correct = bool(row["baseCorrect"]), bool(row["probeCorrect"])
        result.update(
            {
                "baseCorrect": int(base_correct),
                "baseInputFailures": int(row["baseInputFailure"] is not None),
                "baseNull": int(row["baseLabel"] is None),
                "bothCorrect": int(base_correct and probe_correct),
                "bothWrong": int(not base_correct and not probe_correct),
                "count": 1,
                "gains": int(not base_correct and probe_correct),
                "harms": int(base_correct and not probe_correct),
                "probeCorrect": int(probe_correct),
                "probeInputFailures": int(row["probeInputFailure"] is not None),
                "probeNull": int(row["probeLabel"] is None),
            }
        )
    result["net"] = result["probeCorrect"] - result["baseCorrect"]
    return dict(sorted(result.items()))


def score_selected_probes(provenance_rows: Sequence[Mapping[str, object]], base_rows,
                          probe_rows, *, expected_writers: Sequence[str], canonical_labels=None):
    """Pure complete paired arithmetic; raw packet authentication is external."""

    writers = tuple(expected_writers)
    labels = tuple(canonical_labels if canonical_labels is not None else
                   (label for label, _ in source.canonical_chord_specs()))
    if not writers or len(set(writers)) != len(writers) or not labels or len(set(labels)) != len(labels):
        raise ValueError("layout scoring requires explicit complete writers and labels")
    base = base_scoring._selected(base_rows)
    probes = base_scoring._selected(probe_rows)
    joined, cells, seen_probe_ids = [], set(), set()
    for truth in provenance_rows:
        required = {
            "acquisitionOrder", "baseInputSHA256", "baseSampleID", "canonicalLabel",
            "inputSHA256", "probe", "probeID", "role", "session", "syntheticNotNaturalInk", "writer",
        }
        if not isinstance(truth, dict) or not required <= set(truth):
            raise ValueError("layout truth row is incomplete")
        probe_id, base_id = truth["probeID"], truth["baseSampleID"]
        if probe_id in seen_probe_ids or probe_id not in probes or base_id not in base:
            raise ValueError("layout truth is duplicate or unmatched")
        seen_probe_ids.add(probe_id)
        writer, session, label = truth["writer"], truth["session"], truth["canonicalLabel"]
        order, probe_name = truth["acquisitionOrder"], truth["probe"]
        cell = (probe_name, writer, session, label, order)
        if (
            truth["role"] != "development"
            or truth["syntheticNotNaturalInk"] is not True
            or writer not in writers
            or type(session) is not int
            or session not in (1, 2)
            or label not in labels
            or order not in source.ACQUISITION_ORDERS
            or probe_name not in PROBE_BY_NAME
            or cell in cells
            or base[base_id]["inputSHA256"] != truth["baseInputSHA256"]
            or probes[probe_id]["inputSHA256"] != truth["inputSHA256"]
        ):
            raise ValueError("layout truth or source binding is outside the frozen workload")
        cells.add(cell)
        base_prediction, probe_prediction = base[base_id], probes[probe_id]
        joined.append(
            {
                "acquisitionOrder": order,
                "baseCorrect": base_prediction["canonicalLabel"] == label,
                "baseInputFailure": base_prediction["inputFailure"],
                "baseLabel": base_prediction["canonicalLabel"],
                "baseSampleID": base_id,
                "canonicalLabel": label,
                "probe": probe_name,
                "probeCorrect": probe_prediction["canonicalLabel"] == label,
                "probeID": probe_id,
                "probeInputFailure": probe_prediction["inputFailure"],
                "probeLabel": probe_prediction["canonicalLabel"],
                "session": session,
                "writer": writer,
            }
        )
    expected = {
        (probe.name, writer, session, label, order)
        for probe in PROBES
        for writer in writers
        for session in (1, 2)
        for label in labels
        for order in source.ACQUISITION_ORDERS
    }
    expected_base = {row["baseSampleID"] for row in provenance_rows}
    if cells != expected or seen_probe_ids != set(probes) or expected_base != set(base):
        raise ValueError("layout scoring omitted or added a workload cell")
    summaries = {}
    for definition in PROBES:
        selected = [row for row in joined if row["probe"] == definition.name]
        summaries[definition.name] = {
            "overall": _counts(selected),
            "orders": {
                order: _counts([row for row in selected if row["acquisitionOrder"] == order])
                for order in source.ACQUISITION_ORDERS
            },
            "writerOrders": {
                writer: {
                    order: _counts([row for row in selected if row["writer"] == writer
                                    and row["acquisitionOrder"] == order])
                    for order in source.ACQUISITION_ORDERS
                }
                for writer in writers
            },
            "writers": {
                writer: _counts([row for row in selected if row["writer"] == writer])
                for writer in writers
            },
        }
    losses = any(
        counts["harms"] > 0
        for summary in summaries.values()
        for writer in summary["writerOrders"].values()
        for counts in writer.values()
    )
    failures = any(
        row["baseInputFailure"] is not None or row["probeInputFailure"] is not None for row in joined
    )
    return {
        "anyInputFailureObserved": failures,
        "anyWriterOrderLossObserved": losses,
        "baseRowCount": len(base),
        "freshWriterAccuracyTested": False,
        "naturalChordAccuracyTested": False,
        "pairedVariantsAreIndependent": False,
        "probeRowCount": len(joined),
        "productionEligible": False,
        "promotionAuthorized": False,
        "rows": joined,
        "scope": SCOPE,
        "summaries": summaries,
        "version": SCORE_VERSION,
    }


def _code_snapshot() -> tuple[dict[str, str], dict[Path, str]]:
    identity, snapshot = {}, {}
    for relative in CODE_PATHS:
        path = factor._require_regular_file(factor._repo_root() / relative, name=f"probe code {relative}")
        digest = _sha256(path.read_bytes())
        identity[relative], snapshot[path] = digest, digest
    if len(identity) != len(CODE_PATHS):
        raise ValueError("layout probe code map contains duplicates")
    return identity, snapshot


def _validate_output_location(output_path: Path, forbidden: Sequence[Path]) -> None:
    output = Path(output_path).expanduser()
    if not output.is_absolute() or ".." in output.parts or output == factor._repo_root() \
            or factor._repo_root() in output.parents:
        raise ValueError("layout output must be a new absolute path outside the repository")
    for item in forbidden:
        item = Path(item)
        if output == item or item in output.parents:
            raise ValueError("layout output must be outside every input directory")


def _capture(path: Path, snapshot: dict[Path, str], name: str) -> bytes:
    path = factor._require_regular_file(path, name=name)
    payload = path.read_bytes()
    snapshot[path] = _sha256(payload)
    return payload


def _capture_original_freeze(source_path: Path, probe_protocol_path: Path,
                             original_protocol_path: Path, fit_directory: Path,
                             factor_directory: Path):
    code, snapshot = _code_snapshot()
    original_code = {path: code[path] for path in factor.CODE_PATHS}
    source_bytes = _capture(source_path, snapshot, "public source")
    probe_protocol = _capture(probe_protocol_path, snapshot, "layout probe protocol")
    original_protocol = _capture(original_protocol_path, snapshot, "original factor protocol")
    if (
        _sha256(source_bytes) != factor.SOURCE_SHA256
        or _sha256(probe_protocol) != code[PROTOCOL_PATH]
        or _sha256(original_protocol) != original_code[factor.PROTOCOL_PATH]
    ):
        raise ValueError("source or protocol differs from its bound repository bytes")
    fit_directory = factor._require_directory(fit_directory, name="factor fit directory")
    factor_directory = factor._require_directory(factor_directory, name="base factor prediction directory")
    fit_files = {name: _capture(fit_directory / name, snapshot, f"fit {name}") for name in (
        "fit-receipt.json", "weights.pt", "frozen-protocol.md",
        "training-history.jsonl", "training-source-truth.json",
    )}
    factor_files = {name: _capture(factor_directory / name, snapshot, f"base factor {name}") for name in (
        "predictions.json", "prediction-receipt.json", "frozen-protocol.md",
    )}
    base_packet, base_selected = base_scoring._factor_binding(
        fit_files, factor_files, original_code, original_protocol
    )
    if len(base_selected) != BASE_ROW_COUNT:
        raise ValueError("base factor freeze is not the complete development workload")
    receipt = factor.validate_fit_receipt(
        factor._read_canonical_json_bytes(fit_files["fit-receipt.json"], "fit receipt"),
        code=original_code,
        protocol_sha256=_sha256(original_protocol),
    )
    return {
        "basePacket": base_packet,
        "baseSelected": base_selected,
        "code": code,
        "factorDirectory": factor_directory,
        "factorFiles": factor_files,
        "fitDirectory": fit_directory,
        "fitFiles": fit_files,
        "fitReceipt": receipt,
        "originalCode": original_code,
        "originalProtocol": original_protocol,
        "probeProtocol": probe_protocol,
        "snapshot": snapshot,
        "sourceBytes": source_bytes,
    }


def _validate_probe_packet(packet: object, *, frozen: Mapping[str, object]):
    fields = {
        "baseFactorPacketSHA256", "checkpointSHA256", "codeSHA256", "featureContract",
        "fitReceiptSHA256", "inputFeatureStreamSHA256", "labelsSuppliedToPredictor",
        "modelContract", "originalCodeSHA256", "originalProtocolSHA256", "probeCounts",
        "probeDefinitions", "probeProtocolSHA256", "probeProjectionSHA256", "productionEligible",
        "roleGuards", "rowCount", "rows", "runtime", "scope", "sourcePlanVersion",
        "sourceSHA256", "truthJoined", "version",
    }
    packet = factor._require_exact_keys(packet, fields, "layout prediction packet")
    expected = {
        "baseFactorPacketSHA256": _sha256(frozen["factorFiles"]["predictions.json"]),
        "checkpointSHA256": frozen["fitReceipt"]["checkpointSHA256"],
        "codeSHA256": frozen["code"],
        "featureContract": factor._feature_contract(),
        "fitReceiptSHA256": _sha256(frozen["fitFiles"]["fit-receipt.json"]),
        "labelsSuppliedToPredictor": False,
        "modelContract": factor._model_contract(),
        "originalCodeSHA256": frozen["originalCode"],
        "originalProtocolSHA256": _sha256(frozen["originalProtocol"]),
        "probeCounts": {probe.name: BASE_ROW_COUNT for probe in PROBES},
        "probeDefinitions": [probe.value() for probe in PROBES],
        "probeProtocolSHA256": _sha256(frozen["probeProtocol"]),
        "productionEligible": False,
        "roleGuards": {**factor._role_guards(), "originalFactorPredictionsFrozenFirst": True,
                       "truthSuppliedToProbePredictor": False},
        "rowCount": PROBE_ROW_COUNT,
        "runtime": factor._runtime_contract(),
        "scope": SCOPE,
        "sourcePlanVersion": source.VERSION,
        "sourceSHA256": factor.SOURCE_SHA256,
        "truthJoined": False,
        "version": PREDICTION_VERSION,
    }
    if any(packet.get(key) != value for key, value in expected.items()):
        raise ValueError("layout prediction fixed execution contract changed")
    if (
        not isinstance(packet["rows"], list)
        or len(packet["rows"]) != PROBE_ROW_COUNT
        or set(packet["inputFeatureStreamSHA256"]) != set(PROBE_BY_NAME)
        or any(not factor._is_sha256(value) for value in packet["inputFeatureStreamSHA256"].values())
        or not factor._is_sha256(packet["probeProjectionSHA256"])
    ):
        raise ValueError("layout prediction rows or hash bindings are incomplete")
    selected = base_scoring._raw_factor_selection(packet["rows"])
    if len(selected) != PROBE_ROW_COUNT:
        raise ValueError("layout prediction selection shortened the workload")
    return packet, selected


def predict(source_path: Path, probe_protocol_path: Path, original_protocol_path: Path,
            fit_directory: Path, factor_directory: Path, output_path: Path) -> None:
    factor._configure_runtime()
    _validate_output_location(output_path, (fit_directory, factor_directory))
    frozen = _capture_original_freeze(
        source_path, probe_protocol_path, original_protocol_path, fit_directory, factor_directory
    )
    records, roles = factor._load_records(frozen["sourceBytes"])
    base_plan = source.build_role_plan(records, "development")
    if tuple(base_plan.writers) != tuple(roles[1]):
        raise ValueError("probe source plan is not the frozen development role")
    base_index = {row.sample_id: row for row in base_plan.examples}
    for selected in frozen["baseSelected"]:
        base = base_index.get(selected["sampleID"])
        if base is None or selected["inputSHA256"] != base.trajectory_source_sha256:
            raise ValueError("base factor freeze differs from complete source geometry")
    plan = build_probe_plan(base_plan)
    probe_protocol_sha = _sha256(frozen["probeProtocol"])
    original_protocol_sha = _sha256(frozen["originalProtocol"])
    provenance = provenance_value(
        plan, base_plan,
        probe_protocol_sha256=probe_protocol_sha,
        original_protocol_sha256=original_protocol_sha,
    )
    provenance_bytes = canonical_json_bytes(provenance)
    projections = prediction_inputs(plan)
    probe_ids = {
        probe.name: {row.probe_id for row in plan.examples if row.probe_name == probe.name}
        for probe in PROBES
    }
    projection_value = [
        {"inputSHA256": row.input_sha256, "probeID": row.probe_id} for row in projections
    ]
    projection_sha = _sha256(canonical_json_bytes(projection_value))

    output = factor._new_output_directory(output_path)
    factor._write_exclusive(output / "frozen-protocol.md", frozen["probeProtocol"])
    factor._write_exclusive(output / "code-snapshot.json", canonical_json_bytes(frozen["code"]))
    factor._write_exclusive(output / "probe-source-truth.json", provenance_bytes)
    del plan, base_plan, base_index, records, provenance
    factor._preserved(frozen["snapshot"])

    model = factor.load_checkpoint(
        frozen["fitFiles"]["weights.pt"],
        code=frozen["originalCode"],
        protocol_sha256=original_protocol_sha,
        source_plan_version=frozen["fitReceipt"]["sourcePlanVersion"],
        truth_sha256=frozen["fitReceipt"]["trainingTruthLedgerSHA256"],
    )
    if (
        factor._state_digest(model.state_dict()) != frozen["fitReceipt"]["finalStateSHA256"]
        or factor._tensor_digests(model.state_dict()) != frozen["fitReceipt"]["finalTensorSHA256"]
        or factor._head_state_digest(model.state_dict(), factor.INACTIVE_HEADS)
        != frozen["fitReceipt"]["finalInactiveHeadSHA256"]
    ):
        raise ValueError("unchanged checkpoint differs from original fit receipt")
    all_rows, stream_hashes = [], {}
    for probe in PROBES:
        selected_inputs = tuple(row for row in projections if row.probe_id in probe_ids[probe.name])
        # The projection itself has no target, writer, source ID, or probe label.
        encoding = factor.encode_prediction_inputs(selected_inputs)
        outputs = (
            factor.infer(model, encoding.successful)
            if encoding.successful is not None
            else {head.name: np.empty((0, len(head.labels)), dtype=np.float32)
                  for head in factor.OUTPUT_HEADS}
        )
        rows = factor.prediction_rows(encoding, outputs)
        all_rows.extend(rows)
        stream_hashes[probe.name] = encoding.stream_sha256
    all_rows.sort(key=lambda row: row["sampleID"])
    packet = {
        "baseFactorPacketSHA256": _sha256(frozen["factorFiles"]["predictions.json"]),
        "checkpointSHA256": frozen["fitReceipt"]["checkpointSHA256"],
        "codeSHA256": frozen["code"],
        "featureContract": factor._feature_contract(),
        "fitReceiptSHA256": _sha256(frozen["fitFiles"]["fit-receipt.json"]),
        "inputFeatureStreamSHA256": stream_hashes,
        "labelsSuppliedToPredictor": False,
        "modelContract": factor._model_contract(),
        "originalCodeSHA256": frozen["originalCode"],
        "originalProtocolSHA256": original_protocol_sha,
        "probeCounts": {probe.name: BASE_ROW_COUNT for probe in PROBES},
        "probeDefinitions": [probe.value() for probe in PROBES],
        "probeProtocolSHA256": probe_protocol_sha,
        "probeProjectionSHA256": projection_sha,
        "productionEligible": False,
        "roleGuards": {**factor._role_guards(), "originalFactorPredictionsFrozenFirst": True,
                       "truthSuppliedToProbePredictor": False},
        "rowCount": len(all_rows),
        "rows": all_rows,
        "runtime": factor._runtime_contract(),
        "scope": SCOPE,
        "sourcePlanVersion": source.VERSION,
        "sourceSHA256": factor.SOURCE_SHA256,
        "truthJoined": False,
        "version": PREDICTION_VERSION,
    }
    packet, selected = _validate_probe_packet(packet, frozen=frozen)
    projected = {row.probe_id: row.input_sha256 for row in projections}
    if {row["sampleID"]: row["inputSHA256"] for row in selected} != projected:
        raise ValueError("layout raw outputs differ from the complete label-free projection")
    packet_bytes = canonical_json_bytes(packet)
    receipt = {
        "baseFactorPacketSHA256": packet["baseFactorPacketSHA256"],
        "checkpointSHA256": packet["checkpointSHA256"],
        "codeSHA256": frozen["code"],
        "fitReceiptSHA256": packet["fitReceiptSHA256"],
        "packetByteCount": len(packet_bytes),
        "packetRelativePath": "predictions.json",
        "packetSHA256": _sha256(packet_bytes),
        "probeProtocolSHA256": probe_protocol_sha,
        "provenanceByteCount": len(provenance_bytes),
        "provenanceRelativePath": "probe-source-truth.json",
        "provenanceSHA256": _sha256(provenance_bytes),
        "rowCount": len(all_rows),
        "sourceSHA256": factor.SOURCE_SHA256,
        "version": RECEIPT_VERSION,
    }
    factor._preserved(frozen["snapshot"])
    factor._write_exclusive(output / "predictions.json", packet_bytes)
    factor._write_exclusive(output / "prediction-receipt.json", canonical_json_bytes(receipt))


def _parser():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("predict", "score"):
        child = commands.add_parser(name)
        child.add_argument("--source", required=True, type=Path)
        child.add_argument("--probe-protocol", required=True, type=Path)
        child.add_argument("--original-protocol", required=True, type=Path)
        child.add_argument("--fit-directory", required=True, type=Path)
        child.add_argument("--factor-directory", required=True, type=Path)
        if name == "score":
            child.add_argument("--probe-directory", required=True, type=Path)
        child.add_argument("--output", required=True, type=Path)
    return parser


def score(source_path: Path, probe_protocol_path: Path, original_protocol_path: Path,
          fit_directory: Path, factor_directory: Path, probe_directory: Path,
          output_path: Path):
    factor._configure_runtime()
    _validate_output_location(output_path, (fit_directory, factor_directory, probe_directory))
    frozen = _capture_original_freeze(
        source_path, probe_protocol_path, original_protocol_path, fit_directory, factor_directory
    )
    probe_directory = factor._require_directory(probe_directory, name="layout prediction directory")
    files = {name: _capture(probe_directory / name, frozen["snapshot"], f"layout {name}") for name in (
        "predictions.json", "prediction-receipt.json", "frozen-protocol.md",
        "code-snapshot.json", "probe-source-truth.json",
    )}
    if files["frozen-protocol.md"] != frozen["probeProtocol"] or files["code-snapshot.json"] != canonical_json_bytes(frozen["code"]):
        raise ValueError("layout frozen code or protocol changed")
    packet, selected = _validate_probe_packet(
        factor._read_canonical_json_bytes(files["predictions.json"], "layout predictions"),
        frozen=frozen,
    )
    receipt = factor._read_canonical_json_bytes(files["prediction-receipt.json"], "layout receipt")
    expected_receipt = {
        "baseFactorPacketSHA256": packet["baseFactorPacketSHA256"],
        "checkpointSHA256": packet["checkpointSHA256"],
        "codeSHA256": frozen["code"],
        "fitReceiptSHA256": packet["fitReceiptSHA256"],
        "packetByteCount": len(files["predictions.json"]),
        "packetRelativePath": "predictions.json",
        "packetSHA256": _sha256(files["predictions.json"]),
        "probeProtocolSHA256": _sha256(frozen["probeProtocol"]),
        "provenanceByteCount": len(files["probe-source-truth.json"]),
        "provenanceRelativePath": "probe-source-truth.json",
        "provenanceSHA256": _sha256(files["probe-source-truth.json"]),
        "rowCount": PROBE_ROW_COUNT,
        "sourceSHA256": factor.SOURCE_SHA256,
        "version": RECEIPT_VERSION,
    }
    if receipt != expected_receipt:
        raise ValueError("layout prediction receipt differs from frozen artifacts")
    # Raw base and probe outputs are now frozen and revalidated.  Only now build truth.
    records, roles = factor._load_records(frozen["sourceBytes"])
    base_plan = source.build_role_plan(records, "development")
    plan = build_probe_plan(base_plan)
    rebuilt = provenance_value(
        plan, base_plan,
        probe_protocol_sha256=_sha256(frozen["probeProtocol"]),
        original_protocol_sha256=_sha256(frozen["originalProtocol"]),
    )
    rebuilt_bytes = canonical_json_bytes(rebuilt)
    if rebuilt_bytes != files["probe-source-truth.json"]:
        raise ValueError("layout provenance differs from exact frozen source reconstruction")
    expected_projection = [
        {"inputSHA256": row.input_sha256, "probeID": row.probe_id}
        for row in prediction_inputs(plan)
    ]
    selected_projection = {row["sampleID"]: row["inputSHA256"] for row in selected}
    if (
        _sha256(canonical_json_bytes(expected_projection)) != packet["probeProjectionSHA256"]
        or selected_projection != {row["probeID"]: row["inputSHA256"] for row in expected_projection}
    ):
        raise ValueError("layout prediction projection differs from frozen source reconstruction")
    report = score_selected_probes(
        rebuilt["rows"], frozen["baseSelected"], selected,
        expected_writers=roles[1],
    )
    report.update(
        {
            "baseFactorPacketSHA256": packet["baseFactorPacketSHA256"],
            "codeSHA256": frozen["code"],
            "fitReceiptSHA256": packet["fitReceiptSHA256"],
            "modelInferencePerformedDuringScoring": False,
            "originalProtocolSHA256": _sha256(frozen["originalProtocol"]),
            "probePacketSHA256": _sha256(files["predictions.json"]),
            "probeProtocolSHA256": _sha256(frozen["probeProtocol"]),
            "provenanceSHA256": _sha256(rebuilt_bytes),
            "rawTenHeadOutputsModified": False,
            "sourceSHA256": factor.SOURCE_SHA256,
        }
    )
    selections = canonical_json_bytes({"base": frozen["baseSelected"], "probes": selected})
    factor._preserved(frozen["snapshot"])
    output = factor._new_output_directory(output_path)
    factor._write_exclusive(output / "selected-predictions.json", selections)
    factor._write_exclusive(output / "score.json", canonical_json_bytes(report))
    return report


def main(argv=None):
    args = _parser().parse_args(argv)
    if args.command == "predict":
        predict(args.source, args.probe_protocol, args.original_protocol,
                args.fit_directory, args.factor_directory, args.output)
    else:
        report = score(args.source, args.probe_protocol, args.original_protocol,
                       args.fit_directory, args.factor_directory, args.probe_directory, args.output)
        print(
            f"LAYOUT_PROBE_SCORE_FROZEN rows={report['probeRowCount']} "
            f"anyWriterOrderLoss={report['anyWriterOrderLossObserved']} productionEligible=False",
            flush=True,
        )


if __name__ == "__main__":
    main()
