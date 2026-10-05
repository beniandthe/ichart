"""Synthetic-only checks for the fixed whole-chord layout probes."""

import copy
import dataclasses
from pathlib import Path
import tempfile
import unittest

import numpy as np

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.models.output_contract import OUTPUT_HEADS, factorize_canonical_label
from ichart_recognition_ml.research import personal_whole_chord_factor as factor
from ichart_recognition_ml.research import personal_whole_chord_layout_probe as probe
from ichart_recognition_ml.research import personal_whole_chord_source as source
from ichart_recognition_ml.research.stroke_affinity_experiment import point_bounds
from ichart_recognition_ml.research.uji_personal import Sample


WRITER = "trn_UJI_W99"
LABEL = "Ab-7"


def atom_strokes(label: str):
    value = float(ord(label))
    first = InkStroke((
        InkPoint(value % 5, value % 3),
        InkPoint(8 + value % 4, 15 + value % 5),
        InkPoint(14 + value % 2, 2 + value % 7),
    ))
    if label != "A":
        return (first,)
    return (first, InkStroke((InkPoint(1, 2), InkPoint(5, 9))))


def base_examples(session=1):
    samples = tuple(Sample(WRITER, session, label, atom_strokes(label)) for label in LABEL)
    return source._compose_chord_examples(samples, "development", LABEL)


def base_plan(examples):
    return source.WholeChordSourcePlan(
        version=source.VERSION,
        source_sha256=factor.SOURCE_SHA256,
        role="development",
        writers=(WRITER,),
        examples=tuple(examples),
        exposure_ledger={"synthetic": True},
    )


def probe_plan(examples, bases):
    return probe.LayoutProbePlan(
        version=probe.VERSION,
        source_plan_version=source.VERSION,
        source_sha256=factor.SOURCE_SHA256,
        writers=(WRITER,),
        base_row_count=len(bases),
        examples=tuple(examples),
    )


def selected(identity, digest, label, failure=None):
    return {
        "sampleID": identity,
        "inputSHA256": digest,
        "canonicalLabel": label,
        "inputFailure": failure,
    }


def perfect_logits(label):
    target = factorize_canonical_label(label)
    result = {}
    for head in OUTPUT_HEADS:
        if head.is_independent_bernoulli:
            result[head.name] = [8.0 if enabled else -8.0 for enabled in target.values[head.name]]
        else:
            chosen = int(target.values[head.name])
            result[head.name] = [8.0 if index == chosen else -8.0 for index in range(len(head.labels))]
    return result


class WholeChordLayoutProbeTests(unittest.TestCase):
    def test_both_fixed_geometries_preserve_atoms_indexes_timing_and_acquisition(self):
        forward, reverse = base_examples()
        before = copy.deepcopy((forward, reverse))
        for definition in probe.PROBES:
            for base in (forward, reverse):
                row = probe.compose_probe_example(base, definition)
                expected_dimensions = (definition.root_dimension,) + (
                    (definition.other_dimension,) * (len(row.atoms) - 1)
                )
                self.assertEqual(tuple(atom.transform.target_dimension for atom in row.atoms), expected_dimensions)
                previous_right = None
                for ordinal, atom in enumerate(row.atoms):
                    left, _, right, bottom = point_bounds(atom.transformed_strokes)
                    self.assertAlmostEqual(bottom, 32.0)
                    self.assertAlmostEqual(max(right - left, bottom - point_bounds(atom.transformed_strokes)[1]),
                                           expected_dimensions[ordinal])
                    if previous_right is not None:
                        self.assertAlmostEqual(left - previous_right, definition.gap)
                    previous_right = right
                    self.assertEqual(atom.original_strokes, base.atoms[ordinal].original_strokes)
                    self.assertTrue(all(stroke.bounds is not None for stroke in atom.transformed_strokes))
                    self.assertTrue(all(stroke.creation_time_offset is None for stroke in atom.transformed_strokes))
                    self.assertTrue(all(point.time_offset is None for stroke in atom.transformed_strokes for point in stroke.points))
                flattened = [index for atom in row.atoms for index in atom.acquisition_stroke_indexes]
                self.assertEqual(sorted(flattened), list(range(len(row.strokes))))
                expected = tuple(stroke for atom in (
                    row.atoms if base.acquisition_order == "forwardOwnerBlocks" else reversed(row.atoms)
                ) for stroke in atom.transformed_strokes)
                self.assertEqual(row.strokes, expected)
                self.assertEqual(row.input_sha256, source.canonical_strokes_sha256(row.strokes))
        self.assertEqual((forward, reverse), before)

    def test_provenance_preserves_complete_banks_lineage_and_truth_free_projection(self):
        bases = base_examples()
        derived = tuple(probe.compose_probe_example(base, definition)
                        for definition in probe.PROBES for base in bases)
        plan = probe_plan(derived, bases)
        value = probe.provenance_value(
            plan, base_plan(bases), probe_protocol_sha256="a" * 64,
            original_protocol_sha256="b" * 64,
        )
        self.assertEqual(value["baseRowCount"], 2)
        self.assertEqual(value["probeRowCount"], 4)
        self.assertFalse(value["labelsSuppliedToPredictor"])
        self.assertEqual({row["probe"] for row in value["rows"]}, set(probe.PROBE_BY_NAME))
        for row in value["rows"]:
            self.assertFalse(row["timingAvailable"])
            self.assertIn(row["baseSampleID"], {base.sample_id for base in bases})
            for atom in row["atoms"]:
                self.assertIn(atom["sourceSHA256"], value["sourceAtomBank"])
                self.assertIn(atom["baseTransformedSHA256"], value["baseTransformedAtomBank"])
                self.assertIn(atom["probeTransformedSHA256"], value["probeTransformedAtomBank"])
        inputs = probe.prediction_inputs(plan)
        self.assertEqual(
            tuple(field.name for field in dataclasses.fields(probe.LayoutProbePredictionInput)),
            ("probe_id", "input_sha256", "strokes"),
        )
        self.assertEqual(len(inputs), 4)
        self.assertTrue(all(row.input_sha256 == source.canonical_strokes_sha256(row.strokes) for row in inputs))
        self.assertFalse(any(hasattr(row, "canonical_label") or hasattr(row, "writer") for row in inputs))

    def test_feature_encoding_retains_success_and_failure_with_all_ten_raw_heads(self):
        valid_row = probe.compose_probe_example(base_examples()[0], probe.PROBES[0])
        valid = probe.LayoutProbePredictionInput(valid_row.probe_id, valid_row.input_sha256, valid_row.strokes)
        excessive = tuple(InkStroke((InkPoint(float(index), 0),)) for index in range(513))
        invalid = probe.LayoutProbePredictionInput("f" * 64, source.canonical_strokes_sha256(excessive), excessive)
        encoding = factor.encode_prediction_inputs((valid, invalid))
        raw = perfect_logits(LABEL)
        outputs = {head.name: np.asarray([raw[head.name]], dtype=np.float32) for head in OUTPUT_HEADS}
        rows = factor.prediction_rows(encoding, outputs)
        indexed = {row["sampleID"]: row for row in rows}
        self.assertEqual(set(indexed[valid.probe_id]["logits"]), {head.name for head in OUTPUT_HEADS})
        self.assertEqual(indexed[valid.probe_id]["conditionalCanonicalLabel"], LABEL)
        self.assertIsNotNone(indexed[invalid.probe_id]["inputFailure"])
        self.assertIsNone(indexed[invalid.probe_id]["logits"])

    def test_paired_scoring_reports_writer_order_gains_harms_nulls_and_failures(self):
        bases = base_examples(1) + base_examples(2)
        derived = tuple(probe.compose_probe_example(base, definition)
                        for definition in probe.PROBES for base in bases)
        plan = probe_plan(derived, bases)
        truth = probe.provenance_value(
            plan, base_plan(bases), probe_protocol_sha256="a" * 64,
            original_protocol_sha256="b" * 64,
        )["rows"]
        base_rows = [selected(row.sample_id, row.trajectory_source_sha256,
                              LABEL if index in (1, 3) else "C")
                     for index, row in enumerate(bases)]
        probe_rows = []
        for row in derived:
            base = next(item for item in base_rows if item["sampleID"] == row.base_sample_id)
            label, failure = base["canonicalLabel"], None
            if row.probe_name == "equalAtomSize" and row.session == 1 and row.acquisition_order == "forwardOwnerBlocks":
                label = LABEL  # gain: corresponding base row is wrong
            if row.probe_name == "equalAtomSize" and row.session == 2 and row.acquisition_order == "reverseOwnerBlocks":
                label = None  # harm plus retained failure: corresponding base row is correct
                failure = "synthetic-feature-failure"
            if row.probe_name == "zeroAtomGap":
                label = base["canonicalLabel"]
            probe_rows.append(selected(row.probe_id, row.input_sha256, label, failure))
        report = probe.score_selected_probes(
            truth, base_rows, probe_rows, expected_writers=(WRITER,), canonical_labels=(LABEL,)
        )
        equal = report["summaries"]["equalAtomSize"]["overall"]
        self.assertEqual(equal["count"], 4)
        self.assertEqual((equal["gains"], equal["harms"], equal["probeInputFailures"]), (1, 1, 1))
        self.assertTrue(report["anyWriterOrderLossObserved"])
        self.assertTrue(report["anyInputFailureObserved"])
        self.assertEqual(report["summaries"]["zeroAtomGap"]["overall"]["net"], 0)
        self.assertFalse(report["promotionAuthorized"])
        with self.assertRaisesRegex(ValueError, "omitted or added"):
            probe.score_selected_probes(
                truth[:-1], base_rows, probe_rows, expected_writers=(WRITER,), canonical_labels=(LABEL,)
            )

    def test_wrong_definition_or_incomplete_role_refuses_before_complete_plan(self):
        base = base_examples()[0]
        with self.assertRaisesRegex(ValueError, "not frozen"):
            probe.compose_probe_example(base, probe.LayoutDefinition("other", 32, 32, 8))
        with self.assertRaisesRegex(ValueError, "complete frozen development"):
            probe.build_probe_plan(base_plan((base,)))

    def test_code_map_binds_original_twenty_four_plus_probe_protocol_module_and_test(self):
        code, _ = probe._code_snapshot()
        self.assertEqual(tuple(code), probe.CODE_PATHS)
        self.assertEqual(len(probe.CODE_PATHS), len(factor.CODE_PATHS) + 3)
        self.assertEqual({path: code[path] for path in factor.CODE_PATHS}, factor._code_snapshot()[0])
        self.assertEqual(code[probe.PROTOCOL_PATH], probe._sha256(
            (factor._repo_root() / probe.PROTOCOL_PATH).read_bytes()
        ))

    def test_new_output_is_exclusive(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            output = Path(directory) / "new"
            factor._new_output_directory(output)
            with self.assertRaises(ValueError):
                factor._new_output_directory(output)


if __name__ == "__main__":
    unittest.main()
