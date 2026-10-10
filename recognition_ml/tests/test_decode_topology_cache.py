import random
import unittest
from dataclasses import FrozenInstanceError
from unittest import mock

from ichart_recognition_ml import decode
from ichart_recognition_ml.chord_notation import (
    CanonicalChordLabel,
    CanonicalChordLabelError,
    Pitch,
    parse_canonical_chord_label,
)
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.models.output_contract import (
    HEAD_BY_NAME,
    OUTPUT_HEADS,
    FactorLogits,
)


def _uncached_original_suffix_choices(scores, alteration_logits):
    quality_head = decode.HEAD_BY_NAME["quality"]
    extension_head = decode.HEAD_BY_NAME["extension"]
    result = []
    subsets = decode._alteration_subsets(alteration_logits)
    for quality_index, quality_label in enumerate(quality_head.labels):
        form = decode._FORM_BY_FACTOR_LABEL[quality_label]
        for extension_index, extension_label in enumerate(extension_head.labels):
            extension = None if extension_label == "none" else extension_label
            for alterations, alteration_score in subsets:
                probe = CanonicalChordLabel(
                    is_repeat=False,
                    root=Pitch("C"),
                    form=form,
                    extension=extension,
                    alterations=alterations,
                )
                try:
                    canonical = probe.canonical_display
                    parse_canonical_chord_label(canonical)
                except CanonicalChordLabelError:
                    continue
                decode._retain(
                    decode._Ranked(
                        decode._Suffix(form, extension, alterations),
                        scores["quality"][quality_index]
                        + scores["extension"][extension_index]
                        + alteration_score,
                        canonical,
                    ),
                    result,
                    3,
                )
    return tuple(result)


def _reference_decode(output, maximum_candidate_count=3):
    with mock.patch.object(
        decode,
        "_top_suffix_choices",
        _uncached_original_suffix_choices,
    ):
        return decode.decode_factor_logits(output, maximum_candidate_count)


def _factor_grid_logits(quality_index, extension_index, ordinal):
    values = {}
    for head_index, head in enumerate(OUTPUT_HEADS):
        values[head.name] = tuple(
            ((ordinal * 17 + head_index * 11 + index * 7) % 31 - 15) / 4.0
            for index in range(len(head.labels))
        )

    def selected(head_name, selected_index, high):
        logits = list(values[head_name])
        logits[selected_index] = high
        values[head_name] = tuple(logits)

    selected("quality", quality_index, 8.0)
    selected("extension", extension_index, 7.0)
    selected("validity", ordinal % 2, 6.5)
    selected("kind", (ordinal // 2) % 2, 6.0)
    selected("root_letter", ordinal % len(HEAD_BY_NAME["root_letter"].labels), 5.5)
    selected(
        "root_accidental",
        ordinal % len(HEAD_BY_NAME["root_accidental"].labels),
        5.0,
    )
    selected("slash_presence", ordinal % 2, 4.5)
    selected(
        "slash_bass_letter",
        (ordinal * 3) % len(HEAD_BY_NAME["slash_bass_letter"].labels),
        4.0,
    )
    selected(
        "slash_bass_accidental",
        (ordinal * 5) % len(HEAD_BY_NAME["slash_bass_accidental"].labels),
        3.5,
    )
    values["alteration_logits"] = tuple(
        3.0 if ordinal & (1 << index) else -3.0
        for index in range(len(HEAD_BY_NAME["alteration_logits"].labels))
    )
    return FactorLogits.from_mapping(values)


def _random_logits(generator):
    return FactorLogits.from_mapping(
        {
            head.name: tuple(generator.uniform(-12.0, 12.0) for _ in head.labels)
            for head in OUTPUT_HEADS
        }
    )


class DecodeTopologyCacheTests(unittest.TestCase):
    def setUp(self):
        decode._suffix_topology.cache_clear()

    def tearDown(self):
        decode._suffix_topology.cache_clear()

    def test_full_result_exactly_matches_uncached_original_across_factor_grid(self):
        counts = (-4, 0, 1, 2, 3, 99)
        ordinal = 0
        for quality_index, _ in enumerate(HEAD_BY_NAME["quality"].labels):
            for extension_index, _ in enumerate(HEAD_BY_NAME["extension"].labels):
                output = _factor_grid_logits(quality_index, extension_index, ordinal)
                count = counts[ordinal % len(counts)]
                self.assertEqual(
                    decode.decode_factor_logits(output, count),
                    _reference_decode(output, count),
                    (quality_index, extension_index, ordinal, count),
                )
                ordinal += 1

    def test_exact_parity_for_ties_and_deterministic_random_ten_head_logits(self):
        tied = FactorLogits.from_mapping(
            {head.name: tuple(0.0 for _ in head.labels) for head in OUTPUT_HEADS}
        )
        self.assertEqual(decode.decode_factor_logits(tied), _reference_decode(tied))
        self.assertEqual(
            tuple(item.canonical_label for item in decode.decode_factor_logits(tied).candidates),
            ("•/•", "A", "A#"),
        )

        generator = random.Random(29)
        for index in range(24):
            output = _random_logits(generator)
            count = (1, 2, 3, 99)[index % 4]
            self.assertEqual(
                decode.decode_factor_logits(output, count),
                _reference_decode(output, count),
                index,
            )

    def test_scores_are_recomputed_for_every_row(self):
        first = _factor_grid_logits(0, 0, 1)
        second = _factor_grid_logits(9, 8, 89)
        first_result = decode.decode_factor_logits(first)
        second_result = decode.decode_factor_logits(second)
        self.assertNotEqual(first_result, second_result)
        self.assertEqual(first_result, _reference_decode(first))
        self.assertEqual(second_result, _reference_decode(second))
        self.assertEqual(decode._suffix_topology.cache_info().currsize, 1)

    def test_topology_is_immutable_and_parser_work_stops_after_warmup(self):
        key = (
            tuple(HEAD_BY_NAME["quality"].labels),
            tuple(HEAD_BY_NAME["extension"].labels),
            tuple(HEAD_BY_NAME["alteration_logits"].labels),
        )
        original_parser = decode.parse_canonical_chord_label
        calls = 0

        def counted_parser(label):
            nonlocal calls
            calls += 1
            return original_parser(label)

        with mock.patch.object(decode, "parse_canonical_chord_label", counted_parser):
            first = decode._suffix_topology(*key)
            first_call_count = calls
            second = decode._suffix_topology(*key)

        self.assertIs(first, second)
        self.assertGreater(first_call_count, 0)
        self.assertEqual(calls, first_call_count)
        self.assertIsInstance(first, tuple)
        self.assertGreater(len(first), 0)
        with self.assertRaises(TypeError):
            first[0] = first[0]
        with self.assertRaises(FrozenInstanceError):
            first[0].quality_index = 999

    def test_cache_key_binds_all_three_label_tuples_and_rejects_unknown_quality(self):
        quality = tuple(HEAD_BY_NAME["quality"].labels)
        extension = tuple(HEAD_BY_NAME["extension"].labels)
        alterations = tuple(HEAD_BY_NAME["alteration_logits"].labels)
        original = decode._suffix_topology(quality, extension, alterations)
        quality_changed = decode._suffix_topology(tuple(reversed(quality)), extension, alterations)
        extension_changed = decode._suffix_topology(quality, tuple(reversed(extension)), alterations)
        alteration_changed = decode._suffix_topology(quality, extension, tuple(reversed(alterations)))

        self.assertNotEqual(original, quality_changed)
        self.assertNotEqual(original, extension_changed)
        self.assertNotEqual(original, alteration_changed)
        self.assertEqual(decode._suffix_topology.cache_info().misses, 4)
        with self.assertRaises(KeyError):
            decode._suffix_topology(("unknownQuality",), extension, alterations)

    def test_malformed_head_contract_is_rejected_before_cache_use(self):
        output = _factor_grid_logits(0, 0, 0)
        malformed = dict(decode.HEAD_BY_NAME)
        del malformed["slash_presence"]
        with mock.patch.object(decode, "HEAD_BY_NAME", malformed):
            with self.assertRaisesRegex(ContractError, "decoder_contract_mismatch"):
                decode.decode_factor_logits(output)
        self.assertEqual(decode._suffix_topology.cache_info().currsize, 0)


if __name__ == "__main__":
    unittest.main()
