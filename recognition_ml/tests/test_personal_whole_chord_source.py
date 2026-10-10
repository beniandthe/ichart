import dataclasses
import unittest
from unittest import mock

from ichart_recognition_ml.features import InkPoint, InkStroke
from ichart_recognition_ml.models.output_contract import factorize_canonical_label
from ichart_recognition_ml.research import personal_whole_chord_source as source
from ichart_recognition_ml.research.stroke_affinity_experiment import point_bounds
from ichart_recognition_ml.research.uji_personal import Sample, split_writers


def _labels() -> tuple[str, ...]:
    required = tuple("ABCDEFGb-13679")
    extras = tuple(chr(0x400 + index) for index in range(97 - len(required)))
    result = required + extras
    assert len(result) == 97 and len(set(result)) == 97
    return result


def _strokes(label: str) -> tuple[InkStroke, ...]:
    ordinal = ord(label)
    first = InkStroke(
        (
            InkPoint(float(ordinal % 7), float(ordinal % 5)),
            InkPoint(float(10 + ordinal % 3), float(18 + ordinal % 4)),
            InkPoint(float(15 + ordinal % 2), float(4 + ordinal % 6)),
        )
    )
    if label != "A":
        return (first,)
    return (
        first,
        InkStroke((InkPoint(2.0, 3.0), InkPoint(6.0, 11.0))),
    )


def _complete_records() -> tuple[Sample, ...]:
    writers = tuple(f"trn_UJI_W{index:02d}" for index in range(40)) + tuple(
        f"tst_UJI_W{index:02d}" for index in range(20)
    )
    return tuple(
        Sample(writer, session, label, _strokes(label))
        for writer in writers
        for session in (1, 2)
        for label in _labels()
    )


class PersonalWholeChordSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.records = _complete_records()
        cls.plan = source.build_role_plan(cls.records, "development")

    def _example(
        self, label: str, acquisition_order: str
    ) -> source.WholeChordSourceExample:
        return next(
            example
            for example in self.plan.examples
            if example.writer == self.plan.writers[0]
            and example.session == 1
            and example.canonical_label == label
            and example.acquisition_order == acquisition_order
        )

    def test_fixed_vocabulary_is_exact_and_factorizable(self) -> None:
        specs = source.canonical_chord_specs()
        self.assertEqual(len(specs), 168)
        self.assertEqual(
            tuple(label for label, _ in specs),
            tuple(root + descriptor for root in source.ROOTS for descriptor in source.DESCRIPTORS),
        )
        self.assertTrue(all(factorize_canonical_label(label) for label, _ in specs))
        self.assertEqual(dict(specs)["Ab-11"], ("A", "b", "-", "1", "1"))
        self.assertLessEqual(max(len(atoms) for _, atoms in specs), 5)

    def test_wrong_role_and_incomplete_metadata_fail_before_geometry(self) -> None:
        with mock.patch.object(source, "normalize", side_effect=AssertionError) as normalize:
            with self.assertRaisesRegex(ValueError, "training or development"):
                source.build_role_plan(self.records, "reserved")
            normalize.assert_not_called()
        with mock.patch.object(source, "normalize", side_effect=AssertionError) as normalize:
            with self.assertRaisesRegex(ValueError, "Complete frozen UJI metadata"):
                source.build_role_plan(self.records[:-1], "development")
            normalize.assert_not_called()

    def test_development_role_has_fixed_complete_paired_coverage(self) -> None:
        _, expected_writers, reserved = split_writers(self.records)
        self.assertEqual(self.plan.writers, expected_writers)
        self.assertFalse(set(self.plan.writers) & set(reserved))
        self.assertEqual(len(self.plan.examples), 5_376)
        self.assertEqual(source.ROLE_COUNTS["training"] * 2 * 168 * 2, 21_504)
        self.assertEqual(len({row.pair_id for row in self.plan.examples}), 2_688)
        self.assertEqual(len({row.sample_id for row in self.plan.examples}), 5_376)
        ledger = self.plan.exposure_ledger
        self.assertEqual(ledger["recordCount"], 5_376)
        self.assertEqual(ledger["spatialCompositionCount"], 2_688)
        self.assertEqual(ledger["canonicalLabelCount"], 168)
        self.assertEqual(set(ledger["canonicalLabelExposureCounts"].values()), {32})
        self.assertEqual(ledger["uniqueSourceAtomCount"], 224)
        self.assertEqual(ledger["withinCompositionRepeatedSourceOccurrenceCount"], 448)
        self.assertTrue(ledger["acquisitionVariantsArePairedNotIndependent"])
        self.assertTrue(ledger["syntheticNotNaturalInk"])

    def test_geometry_preserves_atoms_and_fixed_layout(self) -> None:
        example = self._example("Ab-13", "forwardOwnerBlocks")
        self.assertEqual(example.atom_labels, ("A", "b", "-", "1", "3"))
        self.assertEqual(
            tuple(atom.transform.target_dimension for atom in example.atoms),
            (32.0, 16.0, 16.0, 16.0, 16.0),
        )
        previous_right = None
        for ordinal, atom in enumerate(example.atoms):
            left, top, right, bottom = point_bounds(atom.transformed_strokes)
            self.assertAlmostEqual(bottom, 32.0)
            self.assertAlmostEqual(max(right - left, bottom - top), 32.0 if ordinal == 0 else 16.0)
            if previous_right is not None:
                self.assertAlmostEqual(left - previous_right, 8.0)
            previous_right = right
            self.assertEqual(
                tuple(len(stroke.points) for stroke in atom.original_strokes),
                tuple(len(stroke.points) for stroke in atom.transformed_strokes),
            )
            for original, transformed in zip(atom.original_strokes, atom.transformed_strokes):
                self.assertEqual(len(original.points), len(transformed.points))
                self.assertTrue(all(point.time_offset is None for point in transformed.points))
                self.assertIsNone(transformed.creation_time_offset)
        self.assertEqual(example.stroke_count, len(example.strokes))
        self.assertEqual(example.point_count, sum(len(stroke.points) for stroke in example.strokes))

    def test_owner_block_variants_reorder_only_complete_blocks(self) -> None:
        forward = self._example("Ab-11", "forwardOwnerBlocks")
        reverse = self._example("Ab-11", "reverseOwnerBlocks")
        self.assertEqual(forward.pair_id, reverse.pair_id)
        self.assertEqual(forward.source_membership_sha256, reverse.source_membership_sha256)
        self.assertEqual(forward.transformation_sha256, reverse.transformation_sha256)
        self.assertNotEqual(forward.sample_id, reverse.sample_id)
        self.assertNotEqual(forward.trajectory_source_sha256, reverse.trajectory_source_sha256)
        self.assertEqual(
            tuple(atom.source_id for atom in forward.atoms[-2:]),
            (forward.atoms[-2].source_id, forward.atoms[-2].source_id),
        )
        for left, right in zip(forward.atoms, reverse.atoms):
            self.assertEqual(left.original_strokes, right.original_strokes)
            self.assertEqual(left.transformed_strokes, right.transformed_strokes)
            self.assertEqual(left.spatial_stroke_indexes, right.spatial_stroke_indexes)
        self.assertEqual(
            forward.strokes,
            tuple(stroke for atom in forward.atoms for stroke in atom.transformed_strokes),
        )
        self.assertEqual(
            reverse.strokes,
            tuple(stroke for atom in reversed(reverse.atoms) for stroke in atom.transformed_strokes),
        )

    def test_prediction_and_atomic_projections_are_truth_free(self) -> None:
        forward = self._example("Ab-11", "forwardOwnerBlocks")
        reverse = self._example("Ab-11", "reverseOwnerBlocks")
        mini = dataclasses.replace(self.plan, examples=(forward, reverse))
        predictions = source.prediction_inputs(mini)
        atomic = source.atomic_owner_inputs(mini)
        self.assertEqual(
            tuple(field.name for field in dataclasses.fields(source.WholeChordPredictionInput)),
            ("sample_id", "input_sha256", "strokes"),
        )
        self.assertEqual(
            tuple(field.name for field in dataclasses.fields(source.WholeChordAtomicOwnerInput)),
            ("sample_id", "input_sha256", "strokes", "oracle_owner_groups"),
        )
        for prediction, owner_input, example in zip(predictions, atomic, mini.examples):
            self.assertEqual(prediction.sample_id, example.sample_id)
            self.assertEqual(prediction.input_sha256, example.trajectory_source_sha256)
            self.assertEqual(
                prediction.input_sha256,
                source.canonical_strokes_sha256(prediction.strokes),
            )
            self.assertEqual(prediction.strokes, example.strokes)
            self.assertEqual(owner_input.strokes, example.strokes)
            self.assertEqual(
                owner_input.oracle_owner_groups,
                tuple(atom.acquisition_stroke_indexes for atom in example.atoms),
            )
            indexes = tuple(index for group in owner_input.oracle_owner_groups for index in group)
            self.assertEqual(set(indexes), set(range(len(example.strokes))))
            self.assertEqual(len(indexes), len(set(indexes)))
            for forbidden in ("canonical_label", "writer", "source_id", "source_label"):
                self.assertFalse(hasattr(prediction, forbidden))
                self.assertFalse(hasattr(owner_input, forbidden))
        self.assertLess(
            max(atomic[1].oracle_owner_groups[-1]),
            min(atomic[1].oracle_owner_groups[0]),
        )

    def test_compact_truth_banks_retain_exact_values_and_refs(self) -> None:
        forward = self._example("Ab-11", "forwardOwnerBlocks")
        reverse = self._example("Ab-11", "reverseOwnerBlocks")
        mini = dataclasses.replace(self.plan, examples=(forward, reverse))
        ledger = source.truth_ledger(mini)
        self.assertEqual(len(ledger["rows"]), 2)
        self.assertNotIn("strokes", ledger["rows"][0])
        self.assertNotIn("originalStrokes", ledger["rows"][0]["atoms"][0])
        self.assertNotIn("transformedStrokes", ledger["rows"][0]["atoms"][0])
        for atom in forward.atoms:
            source_entry = ledger["sourceAtomBank"][atom.source_sha256]
            transformed_entry = ledger["transformedAtomBank"][atom.transformed_sha256]
            self.assertEqual(source_entry["sourceID"], atom.source_id)
            self.assertEqual(source_entry["sourceLabel"], atom.source_label)
            self.assertEqual(len(source_entry["strokes"]), len(atom.original_strokes))
            self.assertEqual(len(transformed_entry["strokes"]), len(atom.transformed_strokes))
        self.assertEqual(
            source.truth_ledger_sha256(mini),
            source.truth_ledger_sha256(mini),
        )

    def test_trajectory_overflow_and_timing_fail_without_drops(self) -> None:
        writer = "trn_UJI_W00"
        many = tuple(InkStroke((InkPoint(float(index), 0.0),)) for index in range(52))
        overflow = tuple(
            Sample(writer, 1, label, many) for label in ("A", "b", "-", "1", "3")
        )
        with self.assertRaisesRegex(ValueError, "cannot fit"):
            source._compose_chord_examples(overflow, "training", "Ab-13")

        timed = Sample(
            writer,
            1,
            "A",
            (InkStroke((InkPoint(0.0, 0.0, 0.1), InkPoint(1.0, 1.0, 0.2))),),
        )
        with self.assertRaisesRegex(ValueError, "must not invent timing"):
            source._compose_chord_examples((timed,), "training", "A")


if __name__ == "__main__":
    unittest.main()
