import math
import unittest

from ichart_recognition_ml.decode import decode_factor_logits
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.models.output_contract import (
    HEAD_BY_NAME,
    OUTPUT_HEADS,
    FactorLogits,
    factorize_canonical_label,
)


def logits_for_label(label, high=10.0, low=-10.0):
    target = factorize_canonical_label(label)
    values = {}
    for head in OUTPUT_HEADS:
        if head.is_independent_bernoulli:
            values[head.name] = tuple(
                high if selected else low for selected in target.values[head.name]
            )
        else:
            selected = target.values[head.name]
            values[head.name] = tuple(
                high if index == selected else low for index in range(len(head.labels))
            )
    return FactorLogits.from_mapping(values)


class DecoderParityTests(unittest.TestCase):
    def test_decodes_canonical_candidate_and_exposes_raw_no_read_score(self):
        output = logits_for_label("Bb△7(#11)/D")
        result = decode_factor_logits(output)

        self.assertEqual(len(result.candidates), 3)
        self.assertEqual(result.candidates[0].canonical_label, "Bb△7(#11)/D")
        self.assertTrue(
            all(
                left.raw_joint_log_score >= right.raw_joint_log_score
                for left, right in zip(result.candidates, result.candidates[1:])
            )
        )
        expected_no_read = -20.0 - math.log1p(math.exp(-20.0))
        self.assertAlmostEqual(result.no_read_log_score, expected_no_read)
        self.assertLessEqual(result.candidates[0].raw_joint_log_score, 0.0)

    def test_grammar_pruning_does_not_renormalize_invalid_winner_mass(self):
        base = logits_for_label("C")
        values = dict(base.values)
        quality = [-10.0] * len(HEAD_BY_NAME["quality"].labels)
        quality[HEAD_BY_NAME["quality"].labels.index("halfDiminished")] = 10.0
        quality[HEAD_BY_NAME["quality"].labels.index("plain")] = 0.0
        extension = [-10.0] * len(HEAD_BY_NAME["extension"].labels)
        extension[HEAD_BY_NAME["extension"].labels.index("none")] = 10.0
        extension[HEAD_BY_NAME["extension"].labels.index("7")] = 0.0
        values["quality"] = tuple(quality)
        values["extension"] = tuple(extension)

        result = decode_factor_logits(FactorLogits.from_mapping(values))

        self.assertNotIn("Cø", tuple(item.canonical_label for item in result.candidates))
        self.assertLess(result.candidates[0].raw_joint_log_score, -9.0)

    def test_tied_heads_use_deterministic_score_then_canonical_label_order(self):
        output = FactorLogits.from_mapping(
            {
                head.name: tuple(0.0 for _ in head.labels)
                for head in OUTPUT_HEADS
            }
        )
        first = decode_factor_logits(output)
        second = decode_factor_logits(output)

        self.assertEqual(first, second)
        self.assertEqual(
            tuple(candidate.canonical_label for candidate in first.candidates),
            ("•/•", "A", "A#"),
        )

    def test_independent_head_preserves_five_legal_alterations(self):
        result = decode_factor_logits(
            logits_for_label("C13(b3)(b5)(b9)(#11)(b13)")
        )
        self.assertEqual(
            result.candidates[0].canonical_label,
            "C13(b3)(b5)(b9)(#11)(b13)",
        )

    def test_conflicting_alteration_mass_is_not_renormalized(self):
        base = logits_for_label("C")
        values = dict(base.values)
        alterations = [-10.0] * len(HEAD_BY_NAME["alteration_logits"].labels)
        alterations[HEAD_BY_NAME["alteration_logits"].labels.index("b5")] = 10.0
        alterations[HEAD_BY_NAME["alteration_logits"].labels.index("#5")] = 10.0
        values["alteration_logits"] = tuple(alterations)

        result = decode_factor_logits(FactorLogits.from_mapping(values))

        self.assertTrue(
            all(
                not ("(b5)" in item.canonical_label and "(#5)" in item.canonical_label)
                for item in result.candidates
            )
        )
        self.assertLess(result.candidates[0].raw_joint_log_score, -9.0)

    def test_candidate_count_is_clamped_and_zero_keeps_no_read_evidence(self):
        output = logits_for_label("C△7")
        zero = decode_factor_logits(output, maximum_candidate_count=-5)
        many = decode_factor_logits(output, maximum_candidate_count=99)
        self.assertEqual(zero.candidates, ())
        self.assertEqual(zero.no_read_log_score, many.no_read_log_score)
        self.assertEqual(len(many.candidates), 3)
        with self.assertRaisesRegex(ContractError, "invalid_candidate_count"):
            decode_factor_logits(output, maximum_candidate_count=True)

    def test_revalidates_directly_constructed_factor_output(self):
        valid = logits_for_label("C")
        missing = dict(valid.values)
        del missing["kind"]
        with self.assertRaisesRegex(ContractError, "missing_output_head"):
            decode_factor_logits(FactorLogits(missing))

        nonfinite = dict(valid.values)
        nonfinite["kind"] = (math.nan, 0.0)
        with self.assertRaisesRegex(ContractError, "nonfinite_output_logit"):
            decode_factor_logits(FactorLogits(nonfinite))

        with self.assertRaisesRegex(ContractError, "output_contract_version_mismatch"):
            decode_factor_logits(FactorLogits(valid.values, contract_version="wrong"))


if __name__ == "__main__":
    unittest.main()
