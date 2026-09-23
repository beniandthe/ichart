import contextlib
import hashlib
import io
import json
import shutil
import struct
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock

from ichart_recognition_ml.cli import main
from ichart_recognition_ml.contracts import canonical_json_bytes
from ichart_recognition_ml.errors import ContractError, OperationRefusedError
from ichart_recognition_ml.study_session import (
    ENGINEERING_DRY_RUN_PROMPTS,
    import_study_session,
)
from ichart_recognition_ml import study_session


SESSION_ID = "01010101-0202-0303-0404-050505050505"


def bits(value):
    return struct.pack(">d", value).hex()


def timing(value):
    return {"bitPattern": bits(value), "state": "finite"}


def packet_value(index):
    first_x = float(index)
    second_x = float(index + 10)
    return {
        "coordinateSpace": "transformed-prepared-drawing",
        "formatVersion": "ink-trajectory-packet-v1",
        "strokes": [
            {
                "bounds": {
                    "maxX": bits(second_x),
                    "maxY": bits(0.0),
                    "minX": bits(first_x),
                    "minY": bits(0.0),
                },
                "creationTimeOffset": timing(0.0),
                "points": [
                    {"timeOffset": timing(0.0), "x": bits(first_x), "y": bits(0.0)},
                    {"timeOffset": timing(0.25), "x": bits(second_x), "y": bits(0.0)},
                ],
            }
        ],
    }


def artifact(payload):
    return hashlib.sha256(payload).hexdigest(), len(payload)


def canonical_write(path, value):
    path.write_bytes(canonical_json_bytes(value))


class SyntheticStudy:
    def __init__(self, root):
        self.root = Path(root)
        self.capture_store = self.root / "recognition-study-store-v1"
        self.outcome_store = self.root / "recognition-study-outcome-store-v1"
        self.session_directory = self.capture_store / "sessions" / SESSION_ID
        self.captures_directory = self.session_directory / "captures"
        self.outcomes_directory = self.outcome_store / "outcomes"
        self.capture_directories = {}
        self.outcome_directories = {}
        self._create_layout()
        self._create_session()
        for index, prompt in enumerate(ENGINEERING_DRY_RUN_PROMPTS):
            self._create_capture(index, prompt)

    def _create_layout(self):
        for directory in (
            self.capture_store / "sessions",
            self.capture_store / "deletion-tombstones",
            self.capture_store / "quarantine",
            self.session_directory,
            self.captures_directory,
            self.session_directory / "quarantine",
            self.session_directory / "staging",
            self.outcome_store,
            self.outcomes_directory,
            self.outcome_store / "quarantine",
            self.outcome_store / "staging",
        ):
            directory.mkdir(parents=True, exist_ok=True)

    def _create_session(self):
        self.session = {
            "artifactKind": "engineering-dry-run-session-v1",
            "clientAppContext": {
                "appVersion": "1.2.1",
                "buildNumber": "51",
                "bundleIdentifier": "com.ichart.recognitionstudy",
                "operatingSystemMajorVersion": 26,
                "operatingSystemMinorVersion": 6,
            },
            "clientCreatedAtUnixMilliseconds": 1_790_000_000_000,
            "collectionProtocolVersion": "engineering-dry-run-v1",
            "limitsVersion": "capture-limits-v1",
            "localSessionID": SESSION_ID,
            "schemaVersion": "recognition-study-session-manifest-v1",
        }
        canonical_write(self.session_directory / "session.json", self.session)

    def write_deletion_tombstone(self, digest=None, session_id=SESSION_ID):
        if digest is None:
            digest = hashlib.sha256(
                canonical_json_bytes(self.session)
            ).hexdigest()
        value = {
            "clientRequestedAtUnixMilliseconds": 1_790_000_000_500,
            "localSessionID": session_id,
            "schemaVersion": "recognition-study-session-deletion-v1",
            "sessionManifestSHA256": digest,
        }
        path = (
            self.capture_store
            / "deletion-tombstones"
            / f"{session_id}.json"
        )
        canonical_write(path, value)
        return path

    def _create_capture(self, index, prompt):
        authorization_id = str(uuid.UUID(int=100 + index))
        capture_id = str(uuid.UUID(int=200 + index))
        capture_directory = self.captures_directory / authorization_id
        outcome_directory = self.outcomes_directory / authorization_id
        capture_directory.mkdir()
        outcome_directory.mkdir()
        self.capture_directories[index] = capture_directory
        self.outcome_directories[index] = outcome_directory

        trajectory = canonical_json_bytes(packet_value(index))
        trajectory_digest, trajectory_count = artifact(trajectory)
        envelope = {
            "artifactKind": "engineering-dry-run-trajectory-v1",
            "authorizationBinding": {
                "authorizationID": authorization_id,
                "kind": "local-engineering-dry-run-v1",
                "schemaVersion": "recognition-study-authorization-binding-v1",
            },
            "captureOrdinal": index,
            "clientCapturedAtUnixMilliseconds": 1_790_000_000_100 + index,
            "collectionProtocolVersion": "engineering-dry-run-v1",
            "localCaptureID": capture_id,
            "localSessionID": SESSION_ID,
            "presentedSurface": {
                "canvasHeight": bits(375.0),
                "canvasWidth": bits(780.0),
                "clientObservedOrientation": "portrait",
                "presentedChartStyle": prompt.chart_style,
                "presentedConstructionInstruction": prompt.construction,
                "presentedPaceInstruction": prompt.pace,
                "presentedSizeInstruction": prompt.size,
                "surfaceVersion": "recognition-study-presented-surface-v1",
            },
            "schemaVersion": "recognition-study-capture-envelope-v1",
            "sessionManifestSHA256": hashlib.sha256(
                canonical_json_bytes(self.session)
            ).hexdigest(),
            "trajectoryDescriptor": {
                "canonicalPacketByteCount": trajectory_count,
                "canonicalPacketSHA256": trajectory_digest,
                "containsNonFiniteTiming": False,
                "coordinateSpace": "transformed-prepared-drawing",
                "creationTimingCoverage": "complete",
                "emptyStrokeCount": 0,
                "overallTimingCoverage": "complete",
                "packetFormatVersion": "ink-trajectory-packet-v1",
                "pointCount": 2,
                "pointTimingCoverage": "complete",
                "schemaVersion": "recognition-study-trajectory-descriptor-v1",
                "strokeCount": 1,
            },
        }
        envelope_data = canonical_json_bytes(envelope)
        envelope_digest, envelope_count = artifact(envelope_data)
        capture_commit = {
            "authorizationID": authorization_id,
            "envelopeByteCount": envelope_count,
            "envelopeSHA256": envelope_digest,
            "localCaptureID": capture_id,
            "localSessionID": SESSION_ID,
            "schemaVersion": "recognition-study-local-commit-v1",
            "trajectoryByteCount": trajectory_count,
            "trajectorySHA256": trajectory_digest,
        }
        (capture_directory / "trajectory.json").write_bytes(trajectory)
        (capture_directory / "envelope.json").write_bytes(envelope_data)
        canonical_write(capture_directory / "commit.json", capture_commit)

        outcome = {
            "adaptedRecognizerOutcome": {
                "adaptationState": "disabled-for-study",
                "correctionMemoryState": "disabled-for-study",
                "disposition": "not-run",
            },
            "artifactKind": "local-engineering-semantic-outcome-v1",
            "authorizationID": authorization_id,
            "baseRecognizerOutcome": {
                "candidate": prompt.canonical_chord,
                "canonicalCandidate": prompt.canonical_chord,
                "disposition": "review",
                "recognizerID": "apple-vision-text-baseline",
                "recognizerVersion": "apple-vision-text-baseline-v1",
            },
            "captureEnvelopeSHA256": envelope_digest,
            "clientRecordedAtUnixMilliseconds": 1_790_000_000_200 + index,
            "consentProvenanceStatus": "not-established",
            "corpusAdjudicationStatus": "not-established",
            "dataUse": "local-engineering-only-not-corpus-eligible-v1",
            "localCaptureID": capture_id,
            "localSessionID": SESSION_ID,
            "promptOutcome": {
                "intendedChord": prompt.canonical_chord,
                "promptID": prompt.prompt_id,
                "writerConfirmationState": "as-prompted",
            },
            "schemaVersion": "recognition-study-semantic-outcome-v1",
            "trajectoryPacketSHA256": trajectory_digest,
        }
        outcome_data = canonical_json_bytes(outcome)
        outcome_digest, outcome_count = artifact(outcome_data)
        outcome_commit = {
            "authorizationID": authorization_id,
            "localCaptureID": capture_id,
            "localSessionID": SESSION_ID,
            "outcomeByteCount": outcome_count,
            "outcomeSHA256": outcome_digest,
            "schemaVersion": "recognition-study-outcome-commit-v1",
        }
        (outcome_directory / "outcome.json").write_bytes(outcome_data)
        canonical_write(outcome_directory / "commit.json", outcome_commit)

    def rewrite_outcome(self, index, mutation):
        directory = self.outcome_directories[index]
        outcome_path = directory / "outcome.json"
        outcome = json.loads(outcome_path.read_bytes())
        mutation(outcome)
        outcome_data = canonical_json_bytes(outcome)
        outcome_path.write_bytes(outcome_data)
        commit_path = directory / "commit.json"
        commit = json.loads(commit_path.read_bytes())
        commit["outcomeSHA256"], commit["outcomeByteCount"] = artifact(outcome_data)
        canonical_write(commit_path, commit)

    def rewrite_envelope(self, index, mutation):
        capture_directory = self.capture_directories[index]
        envelope_path = capture_directory / "envelope.json"
        envelope = json.loads(envelope_path.read_bytes())
        mutation(envelope)
        envelope_data = canonical_json_bytes(envelope)
        envelope_path.write_bytes(envelope_data)
        envelope_digest, envelope_count = artifact(envelope_data)
        commit_path = capture_directory / "commit.json"
        commit = json.loads(commit_path.read_bytes())
        commit["envelopeSHA256"] = envelope_digest
        commit["envelopeByteCount"] = envelope_count
        canonical_write(commit_path, commit)
        self.rewrite_outcome(
            index,
            lambda outcome: outcome.update(
                {"captureEnvelopeSHA256": envelope_digest}
            ),
        )


class RecognitionStudySessionImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.study = SyntheticStudy(self.root / "study")

    def tearDown(self):
        self.temporary.cleanup()

    def test_complete_session_import_is_deterministic_and_explicitly_ineligible(self):
        first_output = self.root / "first"
        second_output = self.root / "second"
        first = import_study_session(self.study.root, first_output)
        second = import_study_session(
            self.study.root, second_output, local_session_id=SESSION_ID
        )

        self.assertEqual(first.capture_count, len(ENGINEERING_DRY_RUN_PROMPTS))
        self.assertEqual(first.receipt_sha256, second.receipt_sha256)
        self.assertEqual(
            first.receipt_path.read_bytes(), second.receipt_path.read_bytes()
        )
        receipt = json.loads(first.receipt_path.read_bytes())
        self.assertEqual(receipt["authority"], "mechanical-validation-only")
        self.assertEqual(receipt["status"], "validated-local-engineering-session")
        self.assertFalse(receipt["corpus_eligible"])
        self.assertFalse(receipt["evaluation_eligible"])
        self.assertFalse(receipt["model_supervision_eligible"])
        self.assertEqual(receipt["ground_truth_status"], "not-established")
        self.assertEqual(receipt["consent_provenance_status"], "not-established")
        self.assertEqual(receipt["corpus_adjudication_status"], "not-established")
        self.assertEqual(
            [capture["prompt_intent"]["prompt_id"] for capture in receipt["captures"]],
            [prompt.prompt_id for prompt in ENGINEERING_DRY_RUN_PROMPTS],
        )
        feature_files = sorted((first_output / "features").iterdir())
        self.assertEqual(len(feature_files), 2 * len(ENGINEERING_DRY_RUN_PROMPTS))
        for capture in receipt["captures"]:
            for artifact_value in capture["features"].values():
                path = first_output / artifact_value["relative_path"]
                payload = path.read_bytes()
                self.assertEqual(len(payload), artifact_value["byte_count"])
                self.assertEqual(
                    hashlib.sha256(payload).hexdigest(), artifact_value["sha256"]
                )

    def test_incomplete_pass_and_missing_outcome_fail_without_output(self):
        incomplete = self.study.capture_directories[9]
        shutil.rmtree(incomplete)
        output = self.root / "incomplete-output"
        with self.assertRaisesRegex(ContractError, "incomplete_engineering_pass"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

        self.study = SyntheticStudy(self.root / "study-two")
        shutil.rmtree(self.study.outcome_directories[3])
        output = self.root / "missing-outcome"
        with self.assertRaisesRegex(ContractError, "missing_directory"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

    def test_deletion_tombstone_dominates_retained_session_files(self):
        self.study.write_deletion_tombstone()
        shutil.rmtree(self.study.capture_directories[9])
        output = self.root / "deleted-session-output"
        with self.assertRaisesRegex(ContractError, "session_deleted"):
            import_study_session(
                self.study.root,
                output,
                local_session_id=SESSION_ID,
            )
        self.assertFalse(output.exists())

    def test_historical_tombstone_does_not_block_an_unrelated_live_session(self):
        deleted_session_id = str(uuid.UUID(int=999))
        self.study.write_deletion_tombstone(
            digest="a" * 64,
            session_id=deleted_session_id,
        )
        output = self.root / "unrelated-tombstone-output"
        receipt = import_study_session(self.study.root, output)
        self.assertEqual(receipt.capture_count, len(ENGINEERING_DRY_RUN_PROMPTS))
        self.assertTrue(receipt.receipt_path.is_file())

    def test_implicit_selection_excludes_manifest_bound_tombstoned_session(self):
        deleted_session_id = str(uuid.UUID(int=998))
        deleted_session = dict(self.study.session)
        deleted_session["localSessionID"] = deleted_session_id
        deleted_directory = (
            self.study.capture_store / "sessions" / deleted_session_id
        )
        deleted_directory.mkdir()
        session_data = canonical_json_bytes(deleted_session)
        (deleted_directory / "session.json").write_bytes(session_data)
        self.study.write_deletion_tombstone(
            digest=hashlib.sha256(session_data).hexdigest(),
            session_id=deleted_session_id,
        )

        output = self.root / "implicit-live-session-output"
        receipt = import_study_session(self.study.root, output)
        self.assertEqual(receipt.value["local_session_id"], SESSION_ID)
        self.assertTrue(receipt.receipt_path.is_file())

    def test_out_of_plan_ordinal_is_a_contract_failure_not_an_index_error(self):
        self.study.rewrite_envelope(
            0,
            lambda envelope: envelope.update({"captureOrdinal": 10}),
        )
        output = self.root / "out-of-plan-ordinal"
        with self.assertRaisesRegex(ContractError, "unexpected_capture_ordinal"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

    def test_prompt_and_surface_must_match_the_frozen_study_plan(self):
        self.study.rewrite_outcome(
            2,
            lambda outcome: outcome["promptOutcome"].update(
                {"promptID": ENGINEERING_DRY_RUN_PROMPTS[1].prompt_id}
            ),
        )
        output = self.root / "prompt-mismatch"
        with self.assertRaisesRegex(ContractError, "prompt_plan_mismatch"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

        self.study = SyntheticStudy(self.root / "study-three")
        self.study.rewrite_envelope(
            4,
            lambda envelope: envelope["presentedSurface"].update(
                {"presentedSizeInstruction": "small"}
            ),
        )
        output = self.root / "surface-mismatch"
        with self.assertRaisesRegex(
            ContractError, "presented_surface_prompt_mismatch"
        ):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

    def test_commit_and_descriptor_tampering_are_detected_after_rebinding(self):
        trajectory_path = self.study.capture_directories[0] / "trajectory.json"
        trajectory_path.write_bytes(trajectory_path.read_bytes() + b"\n")
        output = self.root / "tampered-packet"
        with self.assertRaisesRegex(ContractError, "noncanonical_json"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

        self.study = SyntheticStudy(self.root / "study-four")
        self.study.rewrite_envelope(
            0,
            lambda envelope: envelope["trajectoryDescriptor"].update(
                {"pointCount": 3}
            ),
        )
        output = self.root / "descriptor-mismatch"
        with self.assertRaisesRegex(ContractError, "trajectory_descriptor_mismatch"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

    def test_unknown_fields_symlinks_and_existing_output_are_refused(self):
        self.study.rewrite_outcome(
            0, lambda outcome: outcome.update({"groundTruth": "C"})
        )
        output = self.root / "unknown-field"
        with self.assertRaisesRegex(ContractError, "unknown_field"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

        self.study = SyntheticStudy(self.root / "study-five")
        trajectory_path = self.study.capture_directories[0] / "trajectory.json"
        real_path = self.root / "linked-trajectory.json"
        real_path.write_bytes(trajectory_path.read_bytes())
        trajectory_path.unlink()
        trajectory_path.symlink_to(real_path)
        output = self.root / "symlink-output"
        with self.assertRaisesRegex(ContractError, "invalid_artifact"):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

        existing = self.root / "existing"
        existing.mkdir()
        with self.assertRaises(OperationRefusedError):
            import_study_session(self.study.root, existing)

    def test_output_tree_must_be_disjoint_from_the_authoritative_store(self):
        output = self.study.outcome_store / "staging" / "import-output"
        with self.assertRaisesRegex(
            OperationRefusedError, "overlapping_input_output_trees"
        ):
            import_study_session(self.study.root, output)
        self.assertFalse(output.exists())

    def test_publish_does_not_replace_a_destination_created_after_preflight(self):
        output = self.root / "raced-output"
        original_reservation = study_session._reserve_output_directory

        def create_destination_then_reserve(parent_descriptor, output_name):
            output.mkdir()
            (output / "other-writer.txt").write_text("preserve", encoding="utf-8")
            original_reservation(parent_descriptor, output_name)

        with mock.patch.object(
            study_session,
            "_reserve_output_directory",
            side_effect=create_destination_then_reserve,
        ):
            with self.assertRaisesRegex(
                OperationRefusedError, "output_directory_exists"
            ):
                import_study_session(self.study.root, output)

        self.assertEqual(
            (output / "other-writer.txt").read_text(encoding="utf-8"),
            "preserve",
        )
        self.assertFalse((output / "receipt.json").exists())

    def test_output_parent_swap_cannot_redirect_publication_into_source_store(self):
        safe_parent = self.root / "safe-parent"
        output = safe_parent / "output"
        moved_parent = self.root / "safe-parent-before-swap"
        source_staging = self.study.outcome_store / "staging"
        original_open = study_session._open_output_parent_descriptor

        def swap_parent_then_open(study_root, output_directory):
            safe_parent.rename(moved_parent)
            safe_parent.symlink_to(source_staging, target_is_directory=True)
            return original_open(study_root, output_directory)

        with mock.patch.object(
            study_session,
            "_open_output_parent_descriptor",
            side_effect=swap_parent_then_open,
        ):
            with self.assertRaisesRegex(
                OperationRefusedError,
                "unsafe_output_parent|overlapping_input_output_trees",
            ):
                import_study_session(self.study.root, output)

        self.assertEqual(list(source_staging.iterdir()), [])
        self.assertEqual(list(moved_parent.iterdir()), [])

    def test_post_open_parent_rename_cannot_report_a_false_receipt_path(self):
        safe_parent = self.root / "post-open-parent"
        output = safe_parent / "output"
        moved_parent = self.root / "post-open-parent-renamed"
        source_staging = self.study.outcome_store / "staging"
        original_open = study_session._open_output_parent_descriptor

        def open_then_swap_parent(study_root, output_directory):
            descriptor = original_open(study_root, output_directory)
            safe_parent.rename(moved_parent)
            safe_parent.symlink_to(source_staging, target_is_directory=True)
            return descriptor

        with mock.patch.object(
            study_session,
            "_open_output_parent_descriptor",
            side_effect=open_then_swap_parent,
        ):
            with self.assertRaisesRegex(
                OperationRefusedError,
                "output_parent_changed|overlapping_input_output_trees",
            ):
                import_study_session(self.study.root, output)

        self.assertEqual(list(source_staging.iterdir()), [])
        self.assertFalse((output / "receipt.json").exists())
        self.assertTrue((moved_parent / "output" / "receipt.json").is_file())

    def test_receipt_publication_never_replaces_a_concurrent_child(self):
        output = self.root / "receipt-race-output"
        original_link = study_session.os.link
        inserted = False

        def insert_receipt_then_link(source, destination, *args, **kwargs):
            nonlocal inserted
            if source == "receipt.json" and not inserted:
                inserted = True
                descriptor = study_session.os.open(
                    "receipt.json",
                    study_session.os.O_WRONLY
                    | study_session.os.O_CREAT
                    | study_session.os.O_EXCL,
                    0o600,
                    dir_fd=kwargs["dst_dir_fd"],
                )
                try:
                    study_session.os.write(descriptor, b"preserve")
                finally:
                    study_session.os.close(descriptor)
            return original_link(source, destination, *args, **kwargs)

        with mock.patch.object(
            study_session.os,
            "link",
            side_effect=insert_receipt_then_link,
        ):
            with self.assertRaises(FileExistsError):
                import_study_session(self.study.root, output)

        self.assertTrue(inserted)
        self.assertEqual((output / "receipt.json").read_bytes(), b"preserve")

    def test_cli_publishes_only_a_mechanical_validation_receipt(self):
        output = self.root / "cli-output"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(
                [
                    "import-study-session",
                    "--study-root",
                    str(self.study.root),
                    "--output-dir",
                    str(output),
                    "--local-session-id",
                    SESSION_ID,
                ]
            )
        self.assertEqual((code, stderr.getvalue()), (0, ""))
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["authority"], "mechanical-validation-only")
        self.assertFalse(result["corpus_eligible"])
        self.assertEqual(result["capture_count"], 10)
        self.assertEqual(
            Path(result["receipt"]).read_bytes(), (output / "receipt.json").read_bytes()
        )


if __name__ == "__main__":
    unittest.main()
