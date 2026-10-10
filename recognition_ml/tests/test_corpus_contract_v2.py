import copy
import unittest
import uuid

from ichart_recognition_ml.contracts import (
    CorpusRecord,
    CorpusSupervisionKind,
    validate_dataset,
)
from ichart_recognition_ml.errors import ContractError
from ichart_recognition_ml.schema import SPLITS


def identifier(index: int) -> str:
    return str(uuid.UUID(int=index))


def label_evidence(label="C△7"):
    if label is None:
        return {"outcome": "no-read", "canonical_label": None}
    return {"outcome": "canonical-notation", "canonical_label": label}


def reader_evidence(index: int, label="C△7"):
    return {"reader_id_hash": f"{index:064x}", **label_evidence(label)}


def artifact(kind: str, index: int):
    if kind == "trajectory":
        return {
            "relative_path": f"trajectory/{index}.f32le",
            "sha256": f"{800 + index:064x}",
            "byte_count": 10_240,
            "encoding": "float32-le",
        }
    return {
        "relative_path": f"raster/{index}.u8",
        "sha256": f"{900 + index:064x}",
        "byte_count": 24_576,
        "encoding": "uint8-gray",
    }


def record(index: int, split: str, label="C△7"):
    sample_id = identifier(index)
    outcome = "canonical-notation" if label is not None else "no-read"
    return {
        "schema_version": "recognition-corpus-record-v2",
        "sample_id": sample_id,
        "writer_id_hash": f"{index:064x}",
        "capture_session_id": identifier(100 + index),
        "split": split,
        "feature_schema_version": "chord-ink-features-v1",
        "label_schema_version": "writer-independent-ground-truth-v2",
        "label_record_id": identifier(200 + index),
        "canonical_label": label,
        "ground_truth_outcome": outcome,
        "legibility_class": (
            "legible-valid" if label is not None else "legible-negative-or-open-set"
        ),
        "prompted_intent": (
            label_evidence(label)
            if label is not None
            else {"outcome": "not-applicable", "canonical_label": None}
        ),
        "writer_confirmed_intent": label_evidence(label),
        "first_reader_transcription": reader_evidence(1_000 + index, label),
        "second_reader_transcription": reader_evidence(2_000 + index, label),
        "adjudication": {
            "state": "readers-agreed",
            "adjudicator_id_hash": None,
            "outcome": outcome,
            "canonical_label": label,
        },
        "ground_truth_frozen": True,
        "source_kind": "consented-human-capture",
        "consent_record_id": identifier(300 + index),
        "consent_scope": "chord-recognition-research-v1",
        "consent_status": "active",
        "consent_ledger_version": "consent-ledger-v1",
        "consent_record_sha256": f"{400 + index:064x}",
        "provenance_registry_version": "provenance-v1",
        "provenance_record_sha256": f"{500 + index:064x}",
        "capture_protocol_version": "writer-independent-capture-v2",
        "chart_style": "simple-chord-sheet" if index % 2 else "rhythm-section-sheet",
        "orientation": "portrait" if index % 2 else "landscape",
        "device_performance_class": (
            "oldest-supported" if index % 2 else "current-reference"
        ),
        "pace": ("natural", "fast", "careful")[(index - 1) % 3],
        "size_bucket": ("small", "normal", "large")[(index - 1) % 3],
        "handedness": "left" if index % 2 else "right",
        "pencil_experience": "novice" if index % 2 else "experienced",
        "construction_variation": (
            "root-first",
            "modifier-first",
            "mixed-or-retraced",
        )[(index - 1) % 3],
        "app_build": "study-build-1",
        "recognition_pipeline_version": "dual-view-v1",
        "leakage_check_version": "near-neighbor-v1",
        "lineage_version": "recognition-lineage-v1",
        "root_sample_id": sample_id,
        "parent_sample_id": None,
        "geometry_cluster_id": identifier(600 + index),
        "stroke_payload_sha256": f"{700 + index:064x}",
        "trajectory": artifact("trajectory", index),
        "raster": artifact("raster", index),
    }


def unresolved_record(index: int, legibility="unassessed"):
    value = record(index, "unassigned")
    outcome = {
        "technical-failure": "technical-failure",
        "execution-error": "execution-error",
    }.get(legibility, "unresolved")
    value.update(
        {
            "canonical_label": None,
            "ground_truth_outcome": outcome,
            "legibility_class": legibility,
            "writer_confirmed_intent": label_evidence("C△7"),
            "first_reader_transcription": {
                "reader_id_hash": None,
                "outcome": "not-collected",
                "canonical_label": None,
            },
            "second_reader_transcription": {
                "reader_id_hash": None,
                "outcome": "not-collected",
                "canonical_label": None,
            },
            "adjudication": {
                "state": "pending",
                "adjudicator_id_hash": None,
                "outcome": None,
                "canonical_label": None,
            },
            "ground_truth_frozen": False,
        }
    )
    return value


class CorpusContractV2Tests(unittest.TestCase):
    def records_for_every_role(self):
        return [
            CorpusRecord.from_mapping(record(index, split, None if index == 2 else "C△7"))
            for index, split in enumerate(SPLITS, start=1)
        ]

    def test_adjudicated_canonical_and_no_read_targets_are_role_eligible(self):
        records = self.records_for_every_role()
        validate_dataset(records)
        self.assertEqual(records[0].canonical_label, "C△7")
        self.assertEqual(records[0].supervision_kind, CorpusSupervisionKind.NOTATION)
        self.assertEqual(records[0].supervised_canonical_label, "C△7")
        self.assertIsNone(records[1].canonical_label)
        self.assertEqual(records[1].ground_truth_outcome, "no-read")
        self.assertEqual(records[1].supervision_kind, CorpusSupervisionKind.NO_READ)
        self.assertTrue(records[1].has_model_supervision)

    def test_noncanonical_label_is_rejected_at_every_evidence_layer(self):
        fields = (
            ("canonical_label",),
            ("prompted_intent", "canonical_label"),
            ("writer_confirmed_intent", "canonical_label"),
            ("first_reader_transcription", "canonical_label"),
            ("second_reader_transcription", "canonical_label"),
            ("adjudication", "canonical_label"),
        )
        for path in fields:
            with self.subTest(path=path):
                value = record(1, "development")
                target = value
                for component in path[:-1]:
                    target = target[component]
                target[path[-1]] = "Cmaj7"
                with self.assertRaisesRegex(ContractError, "invalid_canonical_label"):
                    CorpusRecord.from_mapping(value)

    def test_writer_only_or_unfrozen_truth_cannot_enter_any_model_role(self):
        for split in SPLITS:
            with self.subTest(split=split):
                value = unresolved_record(10 + SPLITS.index(split))
                value["split"] = split
                with self.assertRaisesRegex(
                    ContractError,
                    "unresolved_ground_truth_in_role|ground_truth_not_collected",
                ):
                    CorpusRecord.from_mapping(value)

        value = record(20, "development")
        value["ground_truth_frozen"] = False
        with self.assertRaisesRegex(ContractError, "unadjudicated_record_in_role"):
            CorpusRecord.from_mapping(value)

    def test_writer_only_capture_is_explicitly_unassigned_not_ground_truth(self):
        parsed = CorpusRecord.from_mapping(unresolved_record(30))
        validate_dataset([parsed], require_all_splits=False)
        self.assertEqual(parsed.split, "unassigned")
        self.assertEqual(parsed.ground_truth_outcome, "unresolved")
        self.assertFalse(parsed.ground_truth_frozen)

    def test_reader_disagreement_requires_distinct_adjudicator_and_bound_result(self):
        value = record(40, "calibration")
        value["second_reader_transcription"] = reader_evidence(2_040, "D-7")
        with self.assertRaisesRegex(ContractError, "adjudication_required"):
            CorpusRecord.from_mapping(value)

        value["adjudication"] = {
            "state": "independently-adjudicated",
            "adjudicator_id_hash": f"{3_040:064x}",
            "outcome": "canonical-notation",
            "canonical_label": "C△7",
        }
        parsed = CorpusRecord.from_mapping(value)
        validate_dataset([parsed], require_all_splits=False)

        value["adjudication"]["adjudicator_id_hash"] = value[
            "first_reader_transcription"
        ]["reader_id_hash"]
        with self.assertRaisesRegex(ContractError, "adjudicator_not_independent"):
            CorpusRecord.from_mapping(value)

    def test_collection_failures_are_retained_but_cannot_become_model_examples(self):
        technical = CorpusRecord.from_mapping(unresolved_record(50, "technical-failure"))
        validate_dataset([technical], require_all_splits=False)
        self.assertEqual(technical.supervision_kind, CorpusSupervisionKind.EXCLUDED)
        self.assertFalse(technical.has_model_supervision)

        value = unresolved_record(51, "technical-failure")
        value["split"] = "sealed-evaluation"
        with self.assertRaisesRegex(
            ContractError,
            "unresolved_ground_truth_in_role|collection_failure_in_model_role",
        ):
            CorpusRecord.from_mapping(value)

    def test_adjudicated_ambiguous_ink_is_explicit_and_not_training_supervision(self):
        value = record(55, "sealed-evaluation", None)
        value.update(
            {
                "ground_truth_outcome": "human-ambiguous",
                "legibility_class": "human-ambiguous",
                "first_reader_transcription": {
                    "reader_id_hash": f"{1_055:064x}",
                    "outcome": "human-ambiguous",
                    "canonical_label": None,
                },
                "second_reader_transcription": {
                    "reader_id_hash": f"{2_055:064x}",
                    "outcome": "human-ambiguous",
                    "canonical_label": None,
                },
                "adjudication": {
                    "state": "readers-agreed",
                    "adjudicator_id_hash": None,
                    "outcome": "human-ambiguous",
                    "canonical_label": None,
                },
            }
        )
        parsed = CorpusRecord.from_mapping(value)
        validate_dataset([parsed], require_all_splits=False)
        self.assertEqual(parsed.supervision_kind, CorpusSupervisionKind.EXCLUDED)
        self.assertTrue(parsed.is_role_assigned)

    def test_execution_error_is_adjudicated_report_only_not_mislabeled_training_data(self):
        value = record(56, "development", "C△7")
        visible = "D-7"
        value.update(
            {
                "canonical_label": None,
                "ground_truth_outcome": "execution-error",
                "legibility_class": "execution-error",
                "first_reader_transcription": reader_evidence(1_056, visible),
                "second_reader_transcription": reader_evidence(2_056, visible),
                "adjudication": {
                    "state": "readers-agreed",
                    "adjudicator_id_hash": None,
                    "outcome": "canonical-notation",
                    "canonical_label": visible,
                },
            }
        )
        parsed = CorpusRecord.from_mapping(value)
        validate_dataset([parsed], require_all_splits=False)
        self.assertEqual(parsed.supervision_kind, CorpusSupervisionKind.EXCLUDED)
        self.assertIsNone(parsed.supervised_canonical_label)

        mislabeled = copy.deepcopy(value)
        mislabeled.update(
            {
                "canonical_label": visible,
                "ground_truth_outcome": "canonical-notation",
                "legibility_class": "legible-valid",
            }
        )
        with self.assertRaisesRegex(ContractError, "intent_visible_label_mismatch"):
            CorpusRecord.from_mapping(mislabeled)

    def test_v1_rows_are_never_silently_upgraded(self):
        value = record(60, "development")
        value["schema_version"] = "recognition-corpus-record-v1"
        with self.assertRaisesRegex(ContractError, "legacy_record_ineligible"):
            CorpusRecord.from_mapping(value)

    def test_collection_strata_have_no_unknown_escape_hatch(self):
        for field in (
            "chart_style",
            "orientation",
            "device_performance_class",
            "pace",
            "size_bucket",
            "handedness",
            "pencil_experience",
            "construction_variation",
        ):
            with self.subTest(field=field):
                value = record(70, "development")
                value[field] = "unknown"
                with self.assertRaisesRegex(ContractError, "invalid_enum"):
                    CorpusRecord.from_mapping(value)

    def test_all_truth_and_strata_are_immutable_lineage_fields(self):
        parent = CorpusRecord.from_mapping(record(80, "development"))
        child_value = copy.deepcopy(record(81, "development"))
        child_value.update(
            {
                "writer_id_hash": parent.writer_id_hash,
                "capture_session_id": parent.capture_session_id,
                "source_kind": "derived-augmentation",
                "root_sample_id": parent.root_sample_id,
                "parent_sample_id": parent.sample_id,
                "consent_record_id": parent.consent_record_id,
                "consent_ledger_version": parent.consent_ledger_version,
                "consent_record_sha256": parent.consent_record_sha256,
                "provenance_registry_version": parent.provenance_registry_version,
                "provenance_record_sha256": parent.provenance_record_sha256,
                "label_record_id": parent.label_record_id,
                "geometry_cluster_id": parent.geometry_cluster_id,
            }
        )
        parent_mapping = parent.as_dict()
        for field in (
            "canonical_label",
            "ground_truth_outcome",
            "legibility_class",
            "prompted_intent",
            "writer_confirmed_intent",
            "first_reader_transcription",
            "second_reader_transcription",
            "adjudication",
            "ground_truth_frozen",
            "chart_style",
            "device_performance_class",
            "pace",
            "size_bucket",
            "handedness",
            "pencil_experience",
            "construction_variation",
            "app_build",
            "recognition_pipeline_version",
            "leakage_check_version",
        ):
            child_value[field] = parent_mapping[field]
        child_value["orientation"] = "portrait"
        child = CorpusRecord.from_mapping(child_value)
        with self.assertRaisesRegex(ContractError, "lineage_inheritance_mismatch"):
            validate_dataset([parent, child], require_all_splits=False)


if __name__ == "__main__":
    unittest.main()
