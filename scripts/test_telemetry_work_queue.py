#!/usr/bin/env python3
"""Focused consumer checks; no database or network access is required."""

import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import telemetry_work_queue as queue


def incident(number=1, **overrides):
    row = {
        "incident_id": "00000000-0000-4000-8000-%012d" % number,
        "rule_id": "contract.chart.save.save_failed",
        "rule_version": 1,
        "category": "disk_persistence",
        "severity": "high",
        "evidence_kind": "operation_failure",
        "build_source": "release_build",
        "status": "new",
        "title": "Library save failed",
        "first_seen_at": "2026-10-30T14:30:00Z",
        "last_seen_at": "2026-10-30T14:31:00Z",
        "event_count": 3,
        "installation_count": 2,
        "session_count": 2,
        "app_versions": ["1.2.3"],
        "build_numbers": ["90", "91"],
        "latest_event_id": "10000000-0000-4000-8000-%012d" % number,
        "fixed_build_number": None,
        "verification_ref": None,
        "resolved_at": None,
        "reopened_count": 0,
        "priority_rank": 1,
    }
    row.update(overrides)
    return row


def payload(*rows):
    return {
        "generated_at": "2026-10-30T14:33:00Z",
        "health": {
            "pending_count": 0,
            "dead_letter_count": 0,
            "rejected_count": 0,
            "oldest_pending_at": None,
            "last_run_at": "2026-10-30T14:32:00Z",
            "last_run_processed": 20,
            "last_run_failed": 0,
            "delivery_reporting_installation_count": 1,
            "last_delivery_reported_at": "2026-10-30T14:31:00Z",
            "queue_overflow_count": 0,
            "queue_rejected_count": 0,
            "queue_quarantine_overflow_count": 0,
            "queue_unacknowledged_batch_count": 0,
        },
        "incidents": list(rows),
    }


class QueueConsumerTests(unittest.TestCase):
    def test_priority_order_is_stable_and_bounded_without_mixing_build_cohorts(self):
        rows = [incident(3, build_source="debug_build"), incident(2), incident(1)]
        value = payload(*rows)
        value["active_incident_count"] = 5
        reviewed = queue.normalize_payload(value, limit=2)
        self.assertEqual([row["incident_id"] for row in reviewed["incidents"]],
                         [incident(1)["incident_id"], incident(2)["incident_id"]])
        self.assertTrue(reviewed["truncated"])
        self.assertEqual(reviewed["returned_incident_count"], 2)
        text = queue.render_markdown(reviewed)
        self.assertIn("5 active incidents; 2 shown (bounded preview", text)
        self.assertIn("Release build (may include internal testing)", text)

    def test_closed_tasks_do_not_enter_active_work_and_unknown_content_is_not_exported(self):
        row = incident(chart_title="Never Export", raw_ink="Never Export", owner_id="Never Export")
        value = payload(row, incident(2, status="resolved"))
        value["unexpected_user_content"] = "Never Export"
        reviewed = queue.normalize_payload(value)
        self.assertEqual(len(reviewed["incidents"]), 1)
        self.assertNotIn("Never Export", json.dumps(reviewed))

    def test_markdown_treats_external_titles_and_verification_as_literal_text(self):
        row = incident(title="[send](https://untrusted.test) <script>alert(1)</script>\n# Fake heading",
                       verification_ref="[click](https://untrusted.test)", fixed_build_number=92)
        text = queue.render_markdown(queue.normalize_payload(payload(row)))
        self.assertNotIn("[send](", text)
        self.assertNotIn("<script>", text)
        self.assertNotIn("\n# Fake heading", text)
        self.assertIn("\\[send\\]\\(", text)
        self.assertIn("&lt;script&gt;", text)
        self.assertIn("fixed build", text)

    def test_health_never_presents_stale_or_incomplete_processing_as_a_clean_queue(self):
        value = payload()
        value["health"].update({
            "pending_count": 10, "dead_letter_count": 2, "rejected_count": 3,
            "oldest_pending_at": "2026-10-30T14:00:00Z", "last_run_at": None,
            "last_run_processed": None, "last_run_failed": None,
        })
        reviewed = queue.normalize_payload(value)
        warnings = queue.health_warnings(reviewed)
        self.assertEqual(len(warnings), 4)
        text = queue.render_markdown(reviewed)
        self.assertIn("No worker execution has been recorded", text)
        self.assertIn("Last run processed: not recorded", text)
        self.assertIn("No active incidents were returned", text)
        self.assertIn("absence of problems", text)
        value["health"]["last_run_at"] = "2026-10-30T14:00:00Z"
        value["health"]["last_run_failed"] = 1
        warnings = queue.health_warnings(queue.normalize_payload(value))
        self.assertTrue(any("fifteen minutes old" in warning for warning in warnings))
        self.assertTrue(any("failed to classify 1" in warning for warning in warnings))

    def test_schema_drift_corrupt_counts_duplicate_ids_and_naive_dates_fail_visibly(self):
        invalid = [
            {"category": "unmaintained_new_category"}, {"build_source": "customer"},
            {"evidence_kind": "confirmed_accurate_chord"}, {"severity": "probably"},
            {"event_count": True}, {"event_count": -1}, {"installation_count": 4},
            {"first_seen_at": "2026-10-30T14:30:00"}, {"incident_id": "not-an-id"},
            {"fixed_build_number": "next"}, {"title": "\x00"},
        ]
        for override in invalid:
            with self.subTest(override=override), self.assertRaises(queue.QueueError):
                queue.normalize_payload(payload(incident(**override)))
        with self.assertRaises(queue.QueueError):
            queue.normalize_payload(payload(incident(), incident()))
        missing_health = payload()
        del missing_health["health"]["pending_count"]
        with self.assertRaises(queue.QueueError):
            queue.normalize_payload(missing_health)

    def test_timestamp_comparison_handles_fractional_seconds_and_timezones(self):
        row = incident(first_seen_at="2026-10-30T07:30:00-07:00",
                       last_seen_at="2026-10-30T14:30:00.100000Z")
        normalized = queue.normalize_payload(payload(row))["incidents"][0]
        self.assertEqual(normalized["first_seen_at"], "2026-10-30T14:30:00.000000Z")

    def test_real_postgresql_fractional_seconds_are_accepted_on_python39(self):
        value = payload(incident())
        value["health"]["last_run_at"] = "2026-10-30T15:00:59.93295+00:00"
        reviewed = queue.normalize_payload(value)
        self.assertEqual(reviewed["health"]["last_run_at"], "2026-10-30T15:00:59.932950Z")
        for fraction in ["9", "93", "932", "9329", "93295", "932951"]:
            value["health"]["last_run_at"] = "2026-10-30T15:00:59." + fraction + "+00:00"
            self.assertEqual(queue.normalize_payload(value)["health"]["last_run_at"],
                             "2026-10-30T15:00:59." + fraction.ljust(6, "0") + "Z")

    def test_task_with_erased_evidence_is_retained_without_false_healthy_counts(self):
        row = incident(evidence_available=False, event_count=0, installation_count=0, session_count=0,
                       first_seen_at=None, last_seen_at=None, latest_event_id=None,
                       app_versions=[], build_numbers=[])
        reviewed = queue.normalize_payload(payload(row))
        self.assertEqual(reviewed["returned_incident_count"], 1)
        self.assertIsNone(reviewed["incidents"][0]["first_seen_at"])
        text = queue.render_markdown(reviewed)
        self.assertIn("raw events expired or were erased", text)
        self.assertIn("zero surviving counts do not establish a healthy feature", text)
        with self.assertRaises(queue.QueueError):
            queue.normalize_payload(payload(incident(evidence_available=False)))

    def test_operation_and_chart_counts_preserve_legacy_unknowns_and_linkage_coverage(self):
        legacy = queue.normalize_payload(payload(incident()))
        self.assertIsNone(legacy["incidents"][0]["operation_count"])
        self.assertIsNone(legacy["incidents"][0]["affected_chart_count"])
        self.assertEqual(legacy["incidents"][0]["chart_linked_event_count"], 0)
        self.assertIn("Linked operations: unknown distinct (linkage in 0 of 3", queue.render_markdown(legacy))
        linked = queue.normalize_payload(payload(incident(operation_count=2, affected_chart_count=1,
            operation_linked_event_count=3, chart_linked_event_count=2)))
        self.assertEqual(linked["incidents"][0]["operation_count"], 2)
        self.assertEqual(linked["incidents"][0]["affected_chart_count"], 1)
        self.assertIn("Linked chart references: 1 distinct (linkage in 2 of 3", queue.render_markdown(linked))
        with self.assertRaises(queue.QueueError):
            queue.normalize_payload(payload(incident(operation_count=4, operation_linked_event_count=3)))

    def test_anonymized_local_replay_has_fixed_note_and_drops_identity_mapping(self):
        value = payload(incident())
        value["replay_context"] = {"mode": "local_replay", "anonymized": True}
        value["replay_evidence"] = [{"raw_event_id": "NeverExport", "client_event_id": "NeverExport"}]
        reviewed = queue.normalize_payload(value)
        self.assertEqual(reviewed["replay_context"], {"mode": "local_replay", "anonymized": True})
        self.assertNotIn("NeverExport", json.dumps(reviewed))
        text = queue.render_markdown(reviewed)
        self.assertIn("Incident/evidence UUIDs below are local replay identities", text)
        self.assertIn("does not show activation of a live production pipeline", text)
        self.assertIn("Latest local replay evidence reference", text)
        for context in ["arbitrary freeform", {"mode": "local_replay", "anonymized": 1},
                        {"mode": "production", "anonymized": True},
                        {"mode": "local_replay", "anonymized": True, "note": "NeverExport"}]:
            value["replay_context"] = context
            with self.subTest(context=context), self.assertRaises(queue.QueueError):
                queue.normalize_payload(value)

    def test_delivery_coverage_and_counters_preserve_unknown_separately_from_zero(self):
        value = payload()
        value["health"].update({field: None for field in queue.DELIVERY_COUNTS})
        value["health"]["delivery_reporting_installation_count"] = 0
        value["health"]["last_delivery_reported_at"] = None
        reviewed = queue.normalize_payload(value)
        self.assertTrue(any("No installation has reported delivery counters" in text
                            for text in queue.health_warnings(reviewed)))
        text = queue.render_markdown(reviewed)
        self.assertIn("queue overflow unknown", text)
        self.assertIn("not zero loss", text)
        value["health"]["delivery_reporting_installation_count"] = 2
        value["health"]["queue_overflow_count"] = 4
        text = queue.render_markdown(queue.normalize_payload(value))
        self.assertIn("not incident counts or rates", text)

    def test_database_query_is_read_only_and_credentials_are_not_in_argv_or_output(self):
        secret = "postgresql://person:DO_NOT_EXPOSE@database.example/private"
        completed = subprocess.CompletedProcess([], 0, json.dumps(payload(incident())), "")
        with mock.patch.object(queue.subprocess, "run", return_value=completed) as run:
            loaded = queue.read_database(12, {
                "ICHART_TELEMETRY_DATABASE_URL": secret,
                "PGHOST": "inherited-host", "PSQLRC": "/unwanted/config", "PATH": "/bin",
            })
        args, kwargs = run.call_args
        self.assertNotIn(secret, " ".join(args[0]))
        self.assertEqual(kwargs["env"]["PGDATABASE"], secret)
        self.assertNotIn("PGHOST", kwargs["env"])
        self.assertNotIn("PSQLRC", kwargs["env"])
        self.assertNotIn("ICHART_TELEMETRY_DATABASE_URL", kwargs["env"])
        self.assertIn("default_transaction_read_only=on", kwargs["env"]["PGOPTIONS"])
        self.assertIn("begin read only;", args[0][-1])
        self.assertIn("limit 12", args[0][-1])
        self.assertNotIn("shell", kwargs)
        self.assertEqual(loaded["incidents"][0]["title"], "Library save failed")
        failed = subprocess.CompletedProcess([], 1, secret, "password error: " + secret)
        with mock.patch.object(queue.subprocess, "run", return_value=failed), self.assertRaises(queue.QueueError) as error:
            queue.read_database(12, {"ICHART_TELEMETRY_DATABASE_URL": secret})
        self.assertNotIn("DO_NOT_EXPOSE", str(error.exception))
        self.assertNotIn("database.example", str(error.exception))

    def test_invalid_dsn_and_timeout_have_safe_errors(self):
        with self.assertRaises(queue.QueueError):
            queue.read_database(1, {"ICHART_TELEMETRY_DATABASE_URL": "not-a-url"})
        with mock.patch.object(queue.subprocess, "run", side_effect=subprocess.TimeoutExpired("DO_NOT_EXPOSE", 20)), \
                self.assertRaises(queue.QueueError) as error:
            queue.read_database(1, {"ICHART_TELEMETRY_DATABASE_URL": "postgresql://user:secret@host/db"})
        self.assertNotIn("DO_NOT_EXPOSE", str(error.exception))

    def test_offline_cli_writes_both_actionable_outputs_without_database_access(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            fixture = directory / "fixture.json"
            fixture.write_text(json.dumps(payload(incident())), encoding="utf-8")
            with mock.patch.object(queue, "read_database", side_effect=AssertionError("must stay offline")), \
                    mock.patch("sys.stdout", new_callable=io.StringIO):
                code = queue.main(["--from-json", str(fixture), "--output-dir", str(directory / "review")])
            self.assertEqual(code, 0)
            output = json.loads((directory / "review/work-queue.json").read_text())
            self.assertEqual(output["returned_incident_count"], 1)
            text = (directory / "review/work-queue.md").read_text()
            self.assertIn("Next action:", text)
            self.assertIn("Verification required:", text)
            self.assertIn("Observed operation failure; data loss is not established", text)
            self.assertEqual(list((directory / "review").glob("*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
