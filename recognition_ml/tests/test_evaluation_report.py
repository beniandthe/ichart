import math
import unittest
import uuid

from ichart_recognition_ml.contracts import CorpusRecord
from ichart_recognition_ml.dataset import PipelineRole
from ichart_recognition_ml.decode import DecodeResult, DecodedCandidate
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.evaluation_report import (
    ASSESSMENT_AUTHORITY,
    EvaluationObservation,
    JointPathProbabilityMass,
    evaluate_writer_disjoint_report,
)
from ichart_recognition_ml.selective_evaluation import (
    SelectiveDisposition,
    SelectivePrediction,
)


def identifier(index):
    return str(uuid.UUID(int=index))


def label_evidence(label):
    if label is None:
        return {"outcome": "no-read", "canonical_label": None}
    return {"outcome": "canonical-notation", "canonical_label": label}


def corpus_record(index, writer, split, label="C", **strata):
    no_read = label is None
    sample_id = identifier(index)
    reader_result = label_evidence(label)
    return CorpusRecord.from_mapping(
        {
            "schema_version": "recognition-corpus-record-v2",
            "sample_id": sample_id,
            "writer_id_hash": f"{writer:064x}",
            "capture_session_id": identifier(10_000 + index),
            "split": split,
            "feature_schema_version": "chord-ink-features-v1",
            "label_schema_version": "writer-independent-ground-truth-v2",
            "label_record_id": identifier(20_000 + index),
            "canonical_label": label,
            "ground_truth_outcome": "no-read" if no_read else "canonical-notation",
            "legibility_class": (
                "legible-negative-or-open-set" if no_read else "legible-valid"
            ),
            "prompted_intent": (
                {"outcome": "not-applicable", "canonical_label": None}
                if no_read
                else label_evidence(label)
            ),
            "writer_confirmed_intent": reader_result,
            "first_reader_transcription": {
                "reader_id_hash": f"{30_000 + index:064x}",
                **reader_result,
            },
            "second_reader_transcription": {
                "reader_id_hash": f"{40_000 + index:064x}",
                **reader_result,
            },
            "adjudication": {
                "state": "readers-agreed",
                "adjudicator_id_hash": None,
                **reader_result,
            },
            "ground_truth_frozen": True,
            "source_kind": "consented-human-capture",
            "consent_record_id": identifier(50_000 + writer),
            "consent_scope": "chord-recognition-research-v1",
            "consent_status": "active",
            "consent_ledger_version": "consent-ledger-v1",
            "consent_record_sha256": f"{60_000 + writer:064x}",
            "provenance_registry_version": "provenance-v1",
            "provenance_record_sha256": f"{70_000 + index:064x}",
            "capture_protocol_version": "writer-independent-capture-v2",
            "chart_style": strata.get("chart_style", "simple-chord-sheet"),
            "orientation": strata.get("orientation", "portrait"),
            "device_performance_class": strata.get(
                "device_performance_class", "current-reference"
            ),
            "pace": strata.get("pace", "natural"),
            "size_bucket": strata.get("size_bucket", "normal"),
            "handedness": strata.get("handedness", "right"),
            "pencil_experience": strata.get("pencil_experience", "experienced"),
            "construction_variation": strata.get(
                "construction_variation", "root-first"
            ),
            "app_build": "study-build-1",
            "recognition_pipeline_version": "dual-view-v1",
            "leakage_check_version": "near-neighbor-v1",
            "lineage_version": "recognition-lineage-v1",
            "root_sample_id": sample_id,
            "parent_sample_id": None,
            "geometry_cluster_id": identifier(80_000 + index),
            "stroke_payload_sha256": f"{90_000 + index:064x}",
            "trajectory": {
                "relative_path": f"trajectory/{index}.f32le",
                "sha256": f"{100_000 + index:064x}",
                "byte_count": 10_240,
                "encoding": "float32-le",
            },
            "raster": {
                "relative_path": f"raster/{index}.u8",
                "sha256": f"{110_000 + index:064x}",
                "byte_count": 24_576,
                "encoding": "uint8-gray",
            },
        }
    )


def decoded(*labels):
    return DecodeResult(
        candidates=tuple(
            DecodedCandidate(label, -0.1 - index)
            for index, label in enumerate(labels)
        ),
        no_read_log_score=-2.0,
    )


def observation(
    labels,
    disposition,
    trusted_label=None,
    probabilities=None,
    no_read_probability=None,
    other_path_probability=None,
    latency=None,
):
    result = decoded(*labels)
    mass = None
    if probabilities is not None:
        mass = JointPathProbabilityMass(
            candidate_probabilities=tuple(probabilities),
            no_read_probability=no_read_probability,
            other_path_probability=other_path_probability,
        )
    return EvaluationObservation(
        prediction=SelectivePrediction(result, disposition, trusted_label),
        joint_path_probability=mass,
        latency_milliseconds=latency,
    )


def complete_corpus():
    return (
        corpus_record(1, 1, "development", "F"),
        corpus_record(2, 2, "calibration", "C", pace="fast"),
        corpus_record(
            3,
            2,
            "calibration",
            "D",
            orientation="landscape",
            chart_style="rhythm-section-sheet",
            construction_variation="modifier-first",
        ),
        corpus_record(
            4,
            3,
            "calibration",
            "E",
            handedness="left",
            pencil_experience="novice",
            size_bucket="large",
        ),
        corpus_record(
            5,
            3,
            "calibration",
            None,
            device_performance_class="oldest-supported",
            construction_variation="mixed-or-retraced",
        ),
        corpus_record(6, 4, "sealed-evaluation", "G"),
        corpus_record(7, 5, "sealed-evaluation", None),
    )


def calibration_observations(include_probabilities=True):
    probability_arguments = (
        {
            "probabilities": (0.8, 0.1),
            "no_read_probability": 0.05,
            "other_path_probability": 0.05,
        }
        if include_probabilities
        else {}
    )
    result = {
        identifier(2): observation(
            ("C", "D"),
            SelectiveDisposition.TRUSTED,
            "C",
            latency=10.0,
            **probability_arguments,
        ),
        identifier(3): observation(
            ("G", "D"),
            SelectiveDisposition.REVIEW,
            latency=20.0,
            **(
                {
                    "probabilities": (0.6, 0.2),
                    "no_read_probability": 0.1,
                    "other_path_probability": 0.1,
                }
                if include_probabilities
                else {}
            ),
        ),
        identifier(4): observation(
            ("E", "F"),
            SelectiveDisposition.TRUSTED,
            "E",
            **(
                {
                    "probabilities": (0.7, 0.1),
                    "no_read_probability": 0.1,
                    "other_path_probability": 0.1,
                }
                if include_probabilities
                else {}
            ),
        ),
        identifier(5): observation(
            ("A", "B"),
            SelectiveDisposition.NO_READ,
            latency=40.0,
            **(
                {
                    "probabilities": (0.2, 0.1),
                    "no_read_probability": 0.6,
                    "other_path_probability": 0.1,
                }
                if include_probabilities
                else {}
            ),
        ),
    }
    return result


class WriterDisjointEvaluationReportTests(unittest.TestCase):
    def test_reports_micro_macro_supervision_selective_strata_calibration_and_latency(self):
        report = evaluate_writer_disjoint_report(
            complete_corpus(),
            calibration_observations(),
            PipelineRole.CALIBRATION,
            calibration_bin_count=5,
        )

        self.assertEqual(report.role, PipelineRole.CALIBRATION)
        self.assertEqual(report.assessment_authority, ASSESSMENT_AUTHORITY)
        self.assertFalse(report.is_quality_gate)
        self.assertTrue(report.may_inform_policy_selection)
        self.assertEqual(report.sample_count, 4)
        self.assertEqual(report.writer_count, 2)

        accuracy = report.overall.accuracy
        self.assertEqual(accuracy.notation_sample_count, 3)
        self.assertEqual(accuracy.notation_writer_count, 2)
        self.assertEqual(accuracy.top_one_correct_count, 2)
        self.assertEqual(accuracy.top_three_correct_count, 3)
        self.assertAlmostEqual(accuracy.sample_micro_top_one, 2 / 3)
        self.assertEqual(accuracy.sample_micro_top_three, 1.0)
        self.assertEqual(accuracy.writer_macro_top_one, 0.75)
        self.assertEqual(accuracy.writer_macro_top_three, 1.0)

        supervision = report.overall.supervision
        self.assertEqual(supervision.supervised_notation_count, 3)
        self.assertEqual(supervision.supervised_no_read_count, 1)
        self.assertEqual(supervision.correct_no_read_count, 1)
        self.assertEqual(supervision.sample_micro_no_read_recall, 1.0)
        self.assertEqual(supervision.writer_macro_no_read_recall, 1.0)
        self.assertEqual(supervision.false_no_read_rate_on_notation, 0.0)

        decisions = report.overall.decisions
        self.assertEqual(decisions.trusted_count, 2)
        self.assertEqual(decisions.review_count, 1)
        self.assertEqual(decisions.no_read_count, 1)
        self.assertEqual(decisions.trusted_coverage, 0.5)
        self.assertEqual(decisions.review_rate, 0.25)
        self.assertEqual(decisions.no_read_rate, 0.25)
        self.assertEqual(decisions.selective_risk, 0.0)

        dimensions = {item.dimension for item in report.strata}
        self.assertEqual(
            dimensions,
            {
                "chart_style",
                "orientation",
                "device_performance_class",
                "pace",
                "size_bucket",
                "handedness",
                "pencil_experience",
                "construction_variation",
            },
        )
        landscape = next(
            item
            for item in report.strata
            if item.dimension == "orientation" and item.value == "landscape"
        )
        self.assertEqual(landscape.metrics.sample_count, 1)
        self.assertEqual(landscape.metrics.accuracy.sample_micro_top_one, 0.0)

        calibration = report.candidate_calibration
        self.assertIsNotNone(calibration)
        self.assertTrue(calibration.may_inform_policy_selection)
        self.assertAlmostEqual(calibration.binary_brier_score, 0.1325)
        self.assertAlmostEqual(calibration.expected_calibration_error, 0.175)
        self.assertEqual(sum(item.sample_count for item in calibration.bins), 4)

        latency = report.latency
        self.assertIsNotNone(latency)
        self.assertEqual(latency.observation_count, 3)
        self.assertEqual(latency.missing_count, 1)
        self.assertFalse(latency.complete_coverage)
        self.assertEqual(latency.p50, 20.0)
        self.assertEqual(latency.p90, 36.0)
        self.assertEqual(latency.p95, 38.0)
        self.assertAlmostEqual(latency.p99, 39.6)
        self.assertEqual(latency.maximum, 40.0)

        candidate_confusions = {
            (item.expected, item.observed): item.count
            for item in report.overall.primary_candidate_confusions
        }
        self.assertEqual(candidate_confusions[("C", "C")], 1)
        self.assertEqual(candidate_confusions[("D", "G")], 1)
        self.assertEqual(candidate_confusions[("<no-read>", "A")], 1)
        disposition_confusions = {
            (item.expected, item.observed): item.count
            for item in report.overall.disposition_confusions
        }
        self.assertEqual(disposition_confusions[("no-read", "no-read")], 1)
        self.assertEqual(disposition_confusions[("notation", "trusted")], 2)

    def test_sealed_role_is_reporting_only_and_kept_distinct_from_calibration(self):
        observations = {
            identifier(6): observation(
                ("G", "C"), SelectiveDisposition.TRUSTED, "G"
            ),
            identifier(7): observation(("C",), SelectiveDisposition.NO_READ),
        }
        report = evaluate_writer_disjoint_report(
            complete_corpus(), observations, PipelineRole.SEALED_EVALUATION
        )
        self.assertEqual(report.role, PipelineRole.SEALED_EVALUATION)
        self.assertFalse(report.may_inform_policy_selection)
        self.assertIsNone(report.candidate_calibration)
        self.assertIsNone(report.latency)

        observations[identifier(2)] = calibration_observations(False)[identifier(2)]
        with self.assertRaisesRegex(ContractError, "unexpected_prediction_samples"):
            evaluate_writer_disjoint_report(
                complete_corpus(), observations, PipelineRole.SEALED_EVALUATION
            )

    def test_development_role_is_never_evaluation_eligible(self):
        with self.assertRaisesRegex(
            OperationRefusedError, "unsupported_writer_disjoint_evaluation_role"
        ):
            evaluate_writer_disjoint_report(
                complete_corpus(),
                {
                    identifier(1): observation(
                        ("F",), SelectiveDisposition.TRUSTED, "F"
                    )
                },
                PipelineRole.TRAINING,
            )

    def test_complete_corpus_writer_leakage_is_rejected_before_metrics(self):
        records = list(complete_corpus())
        records[0] = corpus_record(1, 2, "development", "F")
        with self.assertRaisesRegex(ContractError, "writer_split_leakage"):
            evaluate_writer_disjoint_report(
                records,
                calibration_observations(False),
                PipelineRole.CALIBRATION,
            )

    def test_calibration_is_absent_without_probabilities_and_partial_coverage_is_refused(self):
        no_probabilities = calibration_observations(False)
        report = evaluate_writer_disjoint_report(
            complete_corpus(), no_probabilities, PipelineRole.CALIBRATION
        )
        self.assertIsNone(report.candidate_calibration)

        partial = dict(no_probabilities)
        partial[identifier(2)] = calibration_observations(True)[identifier(2)]
        with self.assertRaisesRegex(
            OperationRefusedError, "incomplete_joint_path_probability_coverage"
        ):
            evaluate_writer_disjoint_report(
                complete_corpus(), partial, PipelineRole.CALIBRATION
            )

    def test_joint_path_probability_contract_rejects_marginals_and_bad_alignment(self):
        with self.assertRaisesRegex(
            ContractError, "unnormalized_joint_path_probability"
        ):
            JointPathProbabilityMass((0.8,), 0.1, 0.2)
        with self.assertRaisesRegex(
            ContractError, "joint_path_candidate_order_mismatch"
        ):
            JointPathProbabilityMass((0.2, 0.4), 0.2, 0.2)
        with self.assertRaisesRegex(ContractError, "invalid_joint_path_probability"):
            JointPathProbabilityMass((math.nan,), 0.5, 0.5)

        observations = calibration_observations(True)
        observations[identifier(2)] = observation(
            ("C", "D"),
            SelectiveDisposition.TRUSTED,
            "C",
            probabilities=(0.8,),
            no_read_probability=0.1,
            other_path_probability=0.1,
        )
        with self.assertRaisesRegex(
            ContractError, "joint_path_candidate_count_mismatch"
        ):
            evaluate_writer_disjoint_report(
                complete_corpus(), observations, PipelineRole.CALIBRATION
            )

    def test_latency_rejects_nonfinite_negative_and_boolean_values(self):
        for invalid in (math.nan, math.inf, -0.1, True):
            with self.subTest(invalid=invalid):
                observations = calibration_observations(False)
                original = observations[identifier(4)]
                observations[identifier(4)] = EvaluationObservation(
                    prediction=original.prediction,
                    latency_milliseconds=invalid,
                )
                with self.assertRaisesRegex(ContractError, "invalid_latency_observation"):
                    evaluate_writer_disjoint_report(
                        complete_corpus(), observations, PipelineRole.CALIBRATION
                    )


if __name__ == "__main__":
    unittest.main()
