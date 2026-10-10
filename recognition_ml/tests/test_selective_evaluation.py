import unittest

from ichart_recognition_ml.contracts import CorpusRecord
from ichart_recognition_ml.dataset import PipelineRole
from ichart_recognition_ml.decode import DecodeResult, DecodedCandidate
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.selective_evaluation import (
    SelectiveDisposition,
    SelectivePrediction,
    evaluate_selective_predictions,
    top_k_is_correct,
)
from corpus_v2_fixture import record_mapping


def record(index, split, label):
    return CorpusRecord.from_mapping(record_mapping(index, split, label))


def corpus():
    return (
        record(1, "development", "C△7"),
        record(2, "calibration", "Db7(b9)/F"),
        record(3, "sealed-evaluation", "•/•"),
    )


def decoded(*labels):
    return DecodeResult(
        candidates=tuple(
            DecodedCandidate(label, -0.1 - index)
            for index, label in enumerate(labels)
        ),
        no_read_log_score=-2.0,
    )


class SelectiveEvaluationTests(unittest.TestCase):
    def test_top_k_uses_exact_canonical_labels(self):
        result = decoded("C7", "Db7(b9)/F", "•/•")
        self.assertFalse(top_k_is_correct("Db7(b9)/F", result, 1))
        self.assertTrue(top_k_is_correct("Db7(b9)/F", result, 3))
        with self.assertRaisesRegex(ContractError, "invalid_expected_label"):
            top_k_is_correct("Db7b9/F", result, 3)

    def test_calibration_role_reports_top_k_and_zero_selective_risk(self):
        calibration = corpus()[1]
        result = decoded("Db7(b9)/F", "C7", "F-7")
        report = evaluate_selective_predictions(
            corpus(),
            {
                calibration.sample_id: SelectivePrediction(
                    result,
                    SelectiveDisposition.TRUSTED,
                    trusted_label="Db7(b9)/F",
                )
            },
            PipelineRole.CALIBRATION,
        )

        self.assertEqual(report.sample_count, 1)
        self.assertEqual(report.writer_count, 1)
        self.assertEqual(report.top_one_accuracy, 1.0)
        self.assertEqual(report.top_three_accuracy, 1.0)
        self.assertEqual(report.trusted_coverage, 1.0)
        self.assertEqual(report.selective_risk, 0.0)
        self.assertEqual(report.no_read_rate, 0.0)

    def test_no_read_is_an_explicit_abstention_and_has_undefined_risk(self):
        sealed = corpus()[2]
        report = evaluate_selective_predictions(
            corpus(),
            {
                sealed.sample_id: SelectivePrediction(
                    decoded("C", "•/•"),
                    SelectiveDisposition.NO_READ,
                )
            },
            PipelineRole.SEALED_EVALUATION,
        )

        self.assertEqual(report.top_one_accuracy, 0.0)
        self.assertEqual(report.top_three_accuracy, 1.0)
        self.assertEqual(report.no_read_rate, 1.0)
        self.assertIsNone(report.selective_risk)

    def test_adjudicated_no_read_has_separate_recall_denominator(self):
        records = (
            record(1, "development", "C△7"),
            record(2, "calibration", "Db7(b9)/F"),
            record(3, "sealed-evaluation", None),
        )
        sealed = records[2]
        report = evaluate_selective_predictions(
            records,
            {
                sealed.sample_id: SelectivePrediction(
                    decoded("C"),
                    SelectiveDisposition.NO_READ,
                )
            },
            PipelineRole.SEALED_EVALUATION,
        )
        self.assertEqual(report.notation_sample_count, 0)
        self.assertEqual(report.no_read_ground_truth_count, 1)
        self.assertEqual(report.no_read_recall, 1.0)
        self.assertIsNone(report.false_no_read_rate)

    def test_wrong_trusted_primary_has_unit_selective_risk(self):
        calibration = corpus()[1]
        report = evaluate_selective_predictions(
            corpus(),
            {
                calibration.sample_id: SelectivePrediction(
                    decoded("C", "Db7(b9)/F"),
                    SelectiveDisposition.TRUSTED,
                    trusted_label="C",
                )
            },
            PipelineRole.CALIBRATION,
        )
        self.assertEqual(report.top_one_accuracy, 0.0)
        self.assertEqual(report.top_three_accuracy, 1.0)
        self.assertEqual(report.selective_risk, 1.0)

    def test_development_role_is_refused(self):
        development = corpus()[0]
        with self.assertRaisesRegex(
            OperationRefusedError, "unsupported_selective_evaluation_role"
        ):
            evaluate_selective_predictions(
                corpus(),
                {
                    development.sample_id: SelectivePrediction(
                        decoded("C△7"),
                        SelectiveDisposition.REVIEW,
                    )
                },
                PipelineRole.TRAINING,
            )

    def test_trusted_label_must_be_primary(self):
        calibration = corpus()[1]
        with self.assertRaisesRegex(ContractError, "trusted_label_is_not_primary"):
            evaluate_selective_predictions(
                corpus(),
                {
                    calibration.sample_id: SelectivePrediction(
                        decoded("C", "Db7(b9)/F"),
                        SelectiveDisposition.TRUSTED,
                        trusted_label="Db7(b9)/F",
                    )
                },
                PipelineRole.CALIBRATION,
            )

    def test_malformed_candidate_type_and_score_fail_closed(self):
        calibration = corpus()[1]
        invalid = DecodeResult(candidates=("Db7(b9)/F",), no_read_log_score=-2.0)
        with self.assertRaisesRegex(ContractError, "invalid_decoded_candidate"):
            evaluate_selective_predictions(
                corpus(),
                {
                    calibration.sample_id: SelectivePrediction(
                        invalid,
                        SelectiveDisposition.REVIEW,
                    )
                },
                PipelineRole.CALIBRATION,
            )

        invalid = DecodeResult(
            candidates=(DecodedCandidate("Db7(b9)/F", 0.1),),
            no_read_log_score=-2.0,
        )
        with self.assertRaisesRegex(ContractError, "invalid_candidate_log_score"):
            evaluate_selective_predictions(
                corpus(),
                {
                    calibration.sample_id: SelectivePrediction(
                        invalid,
                        SelectiveDisposition.REVIEW,
                    )
                },
                PipelineRole.CALIBRATION,
            )


if __name__ == "__main__":
    unittest.main()
