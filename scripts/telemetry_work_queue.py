#!/usr/bin/env python3
"""Read the private telemetry work queue and write a local, actionable review.

No writes are made to PostgreSQL or an external task service. The database URL is
read only from ICHART_TELEMETRY_DATABASE_URL and is never passed on the command
line or copied to the output. Offline input uses the same reviewed JSON shape.
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from urllib.parse import urlsplit
from uuid import UUID


CATEGORY_ACTIONS = {
    "data_preservation": (
        "Data preservation",
        "Trace the saved revision and operation evidence; reproduce the source-content mismatch before modifying persistence.",
        "The same operation preserves source through save and reopen on the fixed build, including intentional erase/restore controls.",
    ),
    "disk_persistence": (
        "Disk persistence",
        "Reproduce the save/load failure with the recorded build and operation; inspect repository completion and generation handling.",
        "Save/load completes on the fixed build and disk readback agrees with the intended durable revision.",
    ),
    "ink_geometry_visibility": (
        "Ink geometry and visibility",
        "Reproduce the scope and coordinate transition; inspect stroke/point conservation and finite geometry, then verify placement on screen.",
        "The same transition preserves source and visible placement; count conservation alone does not close the task.",
    ),
    "render_transaction": (
        "Render transaction",
        "Trace the operation's live draft, transferred source receipts and committed objects; distinguish a safe rejection from destructive mutation.",
        "Successful renders retain the required source receipts, and rejected renders leave chart and live ink intact.",
    ),
    "cloud_backup_restore": (
        "Cloud backup and restore",
        "Inspect terminal operation and coarse error evidence; separate cancellation/offline/retry noise from server, authentication or durable-application failures.",
        "The affected operation completes with the expected applied/backed-up revision; a retry count decrease is insufficient.",
    ),
    "recognition_workflow": (
        "Recognition workflow",
        "Inspect repeated correction/review friction and obtain a fresh, explicitly consented reproduction when intended chord accuracy is needed.",
        "A fresh reviewed workflow reproduces the intended result without losing source; uncertainty counters do not establish recognition accuracy.",
    ),
}
BUILD_ORDER = {"release_build": 0, "debug_build": 1, "unknown": 2}
BUILD_LABELS = {
    "release_build": "Release build (may include internal testing)",
    "debug_build": "Debug build",
    "unknown": "Unknown build type",
}
EVIDENCE_LABELS = {
    "contract_violation": "Observed contract violation; the cause still requires investigation",
    "operation_failure": "Observed operation failure; data loss is not established",
    "investigation": "Investigation lead; no feature violation has been confirmed",
    "friction": "Workflow friction; this is not a recognition accuracy label",
}
CLOSED_STATUSES = {"resolved", "ignored"}
STATUSES = {"new", "triaged", "in_progress", "verifying", "resolved", "ignored"}
HEALTH_COUNTS = ("pending_count", "dead_letter_count", "rejected_count")
LAST_RUN_COUNTS = ("last_run_processed", "last_run_failed")
DELIVERY_COUNTS = ("delivery_reporting_installation_count", "queue_overflow_count", "queue_rejected_count",
                   "queue_quarantine_overflow_count", "queue_unacknowledged_batch_count")
HEALTH_DATES = ("oldest_pending_at", "last_run_at")
MAX_INPUT_BYTES = 8_000_000


class QueueError(Exception):
    """A safe, user-facing error that contains no connector details."""


def _text(value, field, maximum=160, nullable=False):
    if value is None and nullable:
        return None
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise QueueError("Invalid queue field: " + field)
    normalized = " ".join(re.sub(r"[\x00-\x1f\x7f]", " ", value).split())
    if not normalized:
        raise QueueError("Invalid queue field: " + field)
    return normalized


def _count(value, field, default=None):
    if value is None and default is not None:
        return default
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value > 10**15:
        raise QueueError("Invalid queue count: " + field)
    return value


def _date(value, field, nullable=False):
    if value is None and nullable:
        return None
    value = _text(value, field, 64)
    try:
        # PostgreSQL omits insignificant fractional zeroes. Python 3.9 only
        # accepts three or six fractional digits, while PostgreSQL emits 1–6.
        iso_value = value.replace("Z", "+00:00")
        iso_value = re.sub(r"(\d{2}:\d{2}:\d{2})\.(\d{1,6})(?=[+-]\d{2}:\d{2}$)",
                           lambda match: match.group(1) + "." + match.group(2).ljust(6, "0"), iso_value)
        parsed = datetime.fromisoformat(iso_value)
    except ValueError:
        raise QueueError("Invalid queue timestamp: " + field) from None
    if parsed.tzinfo is None:
        raise QueueError("Queue timestamps require a timezone: " + field)
    return parsed.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def _uuid(value, field, nullable=False):
    if value is None and nullable:
        return None
    try:
        return str(UUID(_text(value, field, 36)))
    except ValueError:
        raise QueueError("Invalid queue identifier: " + field) from None


def _labels(value, field):
    if not isinstance(value, list) or len(value) > 500:
        raise QueueError("Invalid queue label list: " + field)
    return sorted(set(_text(item, field, 64) for item in value))


def normalize_payload(value, limit=500):
    """Validate only the documented aggregate fields; discard unknown content."""
    if not isinstance(value, dict) or not isinstance(value.get("incidents"), list):
        raise QueueError("Input must contain an incidents array and a health object.")
    replay_context = value.get("replay_context")
    if replay_context is not None and (
        not isinstance(replay_context, dict) or set(replay_context) != {"mode", "anonymized"}
        or replay_context.get("mode") != "local_replay" or replay_context.get("anonymized") is not True
    ):
        raise QueueError("Unrecognized replay context; only the fixed anonymized local replay marker is accepted.")
    if len(value["incidents"]) > 10_000:
        raise QueueError("Offline input exceeds the 10,000 incident safety limit.")
    health = value.get("health")
    if not isinstance(health, dict):
        raise QueueError("Input must contain a health object.")
    clean_health = {field: _count(health.get(field), field) for field in HEALTH_COUNTS}
    clean_health.update({field: _count(health[field], field) if health.get(field) is not None else None
                         for field in LAST_RUN_COUNTS})
    clean_health.update({field: _date(health.get(field), field, nullable=True) for field in HEALTH_DATES})
    clean_health.update({field: _count(health[field], field) if health.get(field) is not None else None
                         for field in DELIVERY_COUNTS})
    clean_health["last_delivery_reported_at"] = _date(health.get("last_delivery_reported_at"),
                                                    "last_delivery_reported_at", nullable=True)
    incidents = []
    seen_ids = set()
    for row in value["incidents"]:
        if not isinstance(row, dict):
            raise QueueError("Every incident must be an object.")
        category = _text(row.get("category"), "category", 64)
        if category not in CATEGORY_ACTIONS:
            raise QueueError("Unrecognized task category; update the consumer for the new detector schema.")
        build_source = row.get("build_source") or "unknown"
        if build_source == "unlabelled":
            build_source = "unknown"
        if build_source not in BUILD_ORDER:
            raise QueueError("Unrecognized build source; update the consumer for the new detector schema.")
        status = _text(row.get("status"), "status", 32)
        if status not in STATUSES:
            raise QueueError("Unrecognized task status; update the consumer for the new detector schema.")
        incident_id = _uuid(row.get("incident_id"), "incident_id")
        if incident_id in seen_ids:
            raise QueueError("Input contains duplicate incident identifiers.")
        seen_ids.add(incident_id)
        evidence_available = row.get("evidence_available", row.get("event_count", 0) > 0)
        if not isinstance(evidence_available, bool):
            raise QueueError("Invalid evidence availability flag.")
        clean = {
            "incident_id": incident_id,
            "rule_id": _text(row.get("rule_id"), "rule_id", 96),
            "rule_version": _count(row.get("rule_version"), "rule_version"),
            "category": category,
            "severity": _text(row.get("severity"), "severity", 32),
            "evidence_kind": _text(row.get("evidence_kind"), "evidence_kind", 48),
            "build_source": build_source,
            "status": status,
            "title": _text(row.get("title"), "title", 240),
            "first_seen_at": _date(row.get("first_seen_at"), "first_seen_at", nullable=not evidence_available),
            "last_seen_at": _date(row.get("last_seen_at"), "last_seen_at", nullable=not evidence_available),
            "evidence_available": evidence_available,
            "event_count": _count(row.get("event_count"), "event_count"),
            "installation_count": _count(row.get("installation_count"), "installation_count"),
            "session_count": _count(row.get("session_count"), "session_count"),
            "operation_count": _count(row["operation_count"], "operation_count") if row.get("operation_count") is not None else None,
            "affected_chart_count": _count(row["affected_chart_count"], "affected_chart_count") if row.get("affected_chart_count") is not None else None,
            "operation_linked_event_count": _count(row.get("operation_linked_event_count"), "operation_linked_event_count", default=0),
            "chart_linked_event_count": _count(row.get("chart_linked_event_count"), "chart_linked_event_count", default=0),
            "app_versions": _labels(row.get("app_versions", []), "app_versions"),
            "build_numbers": _labels(row.get("build_numbers", []), "build_numbers"),
            "latest_event_id": _uuid(row.get("latest_event_id"), "latest_event_id", nullable=True),
            "fixed_build_number": row.get("fixed_build_number"),
            "verification_ref": _text(row.get("verification_ref"), "verification_ref", 500, nullable=True),
            "resolved_at": _date(row.get("resolved_at"), "resolved_at", nullable=True),
            "reopened_count": _count(row.get("reopened_count"), "reopened_count", default=0),
            "priority_rank": _count(row.get("priority_rank"), "priority_rank"),
        }
        if clean["severity"] not in {"critical", "high", "medium", "low"}:
            raise QueueError("Unrecognized incident severity; update the consumer for the new detector schema.")
        if clean["evidence_kind"] not in EVIDENCE_LABELS:
            raise QueueError("Unrecognized evidence kind; update the consumer for the new detector schema.")
        if clean["fixed_build_number"] is not None:
            fixed_build = str(clean["fixed_build_number"])
            if not re.fullmatch(r"[0-9]{1,32}", fixed_build):
                raise QueueError("Invalid fixed build number.")
            clean["fixed_build_number"] = fixed_build
        if clean["installation_count"] > clean["event_count"] or clean["session_count"] > clean["event_count"]:
            raise QueueError("Distinct installation/session counts exceed the evidence event count.")
        for distinct_field, coverage_field in (("operation_count", "operation_linked_event_count"),
                                               ("affected_chart_count", "chart_linked_event_count")):
            if clean[coverage_field] > clean["event_count"]:
                raise QueueError("Operation/chart linkage coverage exceeds the evidence event count.")
            if clean[distinct_field] is not None and clean[distinct_field] > clean[coverage_field]:
                raise QueueError("Distinct operation/chart counts exceed the evidence linkage coverage.")
        if clean["first_seen_at"] and clean["last_seen_at"] and clean["first_seen_at"] > clean["last_seen_at"]:
            raise QueueError("Incident first-seen timestamp follows last-seen timestamp.")
        if not evidence_available and (clean["event_count"] or clean["installation_count"] or clean["session_count"]):
            raise QueueError("Unavailable evidence cannot have surviving event counts.")
        if status not in CLOSED_STATUSES:
            incidents.append(clean)
    incidents.sort(key=lambda row: (
        row["priority_rank"], BUILD_ORDER[row["build_source"]],
        -row["installation_count"], -row["event_count"], row["first_seen_at"] or "9999", row["incident_id"],
    ))
    total = _count(value.get("active_incident_count"), "active_incident_count", default=len(incidents))
    if total < len(incidents):
        raise QueueError("Active incident total is smaller than the returned queue.")
    generated_at = value.get("generated_at") or datetime.now(timezone.utc).isoformat()
    reviewed = {
        "schema_version": 1,
        "generated_at": _date(generated_at, "generated_at"),
        "active_incident_count": total,
        "returned_incident_count": min(len(incidents), limit),
        "truncated": total > min(len(incidents), limit),
        "health": clean_health,
        "incidents": incidents[:limit],
    }
    if replay_context is not None:
        reviewed["replay_context"] = {"mode": "local_replay", "anonymized": True}
    return reviewed


def read_database(limit, environment=None):
    if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 10_000:
        raise QueueError("Queue limit must be between 1 and 10000.")
    environment = dict(os.environ if environment is None else environment)
    dsn = environment.get("ICHART_TELEMETRY_DATABASE_URL", "")
    try:
        valid_dsn = urlsplit(dsn).scheme in {"postgres", "postgresql"}
    except ValueError:
        valid_dsn = False
    if not valid_dsn or any(character in dsn for character in "\r\n\x00") or len(dsn) > 4000:
        raise QueueError("Set ICHART_TELEMETRY_DATABASE_URL to a PostgreSQL connection URL, or use --from-json.")
    child_env = {key: value for key, value in environment.items()
                 if not key.startswith("PG") and key not in {"PSQLRC", "ICHART_TELEMETRY_DATABASE_URL"}}
    child_env.update({"PGDATABASE": dsn, "PGCONNECT_TIMEOUT": "5", "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=10000"})
    query = """
begin read only;
select jsonb_build_object(
  'generated_at', now(),
  'health', (select to_jsonb(h) from private.telemetry_pipeline_health h),
  'active_incident_count', (select count(*) from private.telemetry_work_queue where status not in ('resolved','ignored')),
  'incidents', (select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) from (
    select incident_id,rule_id,rule_version,category,severity,evidence_kind,build_source,status,title,
           first_seen_at,last_seen_at,event_count,installation_count,session_count,
           operation_count,affected_chart_count,operation_linked_event_count,chart_linked_event_count,app_versions,build_numbers,
           latest_event_id,evidence_available,fixed_build_number,verification_ref,resolved_at,reopened_count,priority_rank
    from private.telemetry_work_queue where status not in ('resolved','ignored')
    order by priority_rank, case build_source when 'release_build' then 0 when 'debug_build' then 1 else 2 end,
             installation_count desc,event_count desc,first_seen_at,incident_id
    limit %d
  ) q)
);
commit;
""" % limit
    try:
        result = subprocess.run(
            ["psql", "--no-psqlrc", "--no-password", "--quiet", "--tuples-only", "--no-align", "--set", "ON_ERROR_STOP=1", "--command", query],
            env=child_env, capture_output=True, text=True, timeout=20, check=False,
        )
    except FileNotFoundError:
        raise QueueError("psql is required for database mode; install PostgreSQL client tools or use --from-json.") from None
    except (OSError, subprocess.TimeoutExpired):
        raise QueueError("Telemetry queue query could not complete; inspect database access and pipeline health locally.") from None
    if result.returncode != 0:
        # libpq errors can include the URL, hostname, username or password. Do
        # not interpolate stderr, stdout, exception repr, command or environment.
        raise QueueError("Telemetry queue query failed; verify credentials, private-view access, and migration deployment locally.")
    if len(result.stdout.encode("utf-8")) > MAX_INPUT_BYTES:
        raise QueueError("Database result exceeds the queue input safety limit; use a smaller --limit.")
    try:
        return json.loads(result.stdout)
    except (ValueError, TypeError):
        raise QueueError("Database returned an invalid queue document.") from None


def health_warnings(payload):
    health = payload["health"]
    warnings = []
    if health["dead_letter_count"]:
        warnings.append("ACTION: %d detector events are in the dead-letter queue; classification is incomplete." % health["dead_letter_count"])
    if health["rejected_count"]:
        warnings.append("REVIEW: %d detector inputs were rejected; inspect schema/version coverage before treating silence as health." % health["rejected_count"])
    if health["last_run_failed"]:
        warnings.append("ACTION: The last worker run failed to classify %d events; investigate retries and detector errors." % health["last_run_failed"])
    if not health["delivery_reporting_installation_count"]:
        warnings.append("COVERAGE: No installation has reported delivery counters; queue delivery/overflow coverage is unknown.")
    elif any(health[field] for field in DELIVERY_COUNTS[1:]):
        warnings.append("REVIEW: Latest cumulative delivery counters include loss/rejection or unacknowledged batches; these totals are not incident counts or rates.")
    now = datetime.fromisoformat(payload["generated_at"].replace("Z", "+00:00"))
    last_run = health["last_run_at"]
    if last_run is None:
        warnings.append("ACTION: No worker execution has been recorded; automatic processing is unverified.")
    elif (now - datetime.fromisoformat(last_run.replace("Z", "+00:00"))).total_seconds() > 900:
        warnings.append("ACTION: The last recorded worker run is over fifteen minutes old; inspect scheduling and worker failures.")
    oldest = health["oldest_pending_at"]
    if oldest and (now - datetime.fromisoformat(oldest.replace("Z", "+00:00"))).total_seconds() > 900:
        warnings.append("ACTION: Pending detector evidence is over fifteen minutes old; work queue coverage is delayed.")
    return warnings


def markdown_text(value):
    """Render external labels as literal text, never links, HTML or headings."""
    text = str(value)
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return re.sub(r"([\\`*_{}\[\]()#+.!|\-])", r"\\\1", text)


def render_markdown(payload):
    health = payload["health"]
    lines = [
        "# Telemetry work queue", "", "Generated: " + markdown_text(payload["generated_at"]), "",
        "%d active incidents; %d shown%s." % (
            payload["active_incident_count"], payload["returned_incident_count"],
            " (bounded preview; remaining incidents are not shown)" if payload["truncated"] else "",
        ), "",
        "Counts describe evidence events and reporting installations/sessions, not users, charts or independent attempts. Release builds may include internal testing. Missing/opted-out telemetry is not evidence of a healthy experience.", "",
        "Linked operation/chart counts use only evidence carrying valid correlation identifiers. Chart references identify a chart within an installation; neither chart nor installation counts identify unique people. Missing linkage is unknown coverage, not zero affected charts.", "",
        "## Pipeline health", "",
        "Pending: %d. Dead letter: %d. Rejected inputs: %d. Last run: %s. Last run processed: %s. Last run failed: %s." % (
            health["pending_count"], health["dead_letter_count"], health["rejected_count"],
            markdown_text(health["last_run_at"] or "not recorded"),
            health["last_run_processed"] if health["last_run_processed"] is not None else "not recorded",
            health["last_run_failed"] if health["last_run_failed"] is not None else "not recorded",
        ), "",
    ]
    if payload.get("replay_context"):
        lines[4:4] = [
            "**Local replay.** This report evaluates a minimal production event export with identifiers replaced in an isolated local database. Incident/evidence UUIDs below are local replay identities. It does not show activation of a live production pipeline.", "",
        ]
    for warning in health_warnings(payload):
        lines.extend(["- " + warning])
    if health_warnings(payload):
        lines.append("")
    lines.extend([
        "Delivery reports: %s distinct reporting installations; latest received: %s." % (
            health["delivery_reporting_installation_count"] if health["delivery_reporting_installation_count"] is not None else "not recorded",
            markdown_text(health["last_delivery_reported_at"] or "not recorded"),
        ),
        "Latest cumulative counters per reporting installation, summed across those installations: queue overflow %s; ingest rejection %s; quarantine overflow %s; unacknowledged batches %s. Unknown values mean no usable reports, not zero loss." % tuple(
            health[field] if health[field] is not None else "unknown" for field in DELIVERY_COUNTS[1:]
        ), "",
    ])
    if not payload["incidents"]:
        lines.extend(["No active incidents were returned. Check pipeline health and instrumented feature coverage before interpreting this as an absence of problems.", ""])
        return "\n".join(lines)
    # Preserve severity priority across category sections by ordering categories
    # by their highest-ranked incident, then split build cohorts inside each.
    category_order = list(dict.fromkeys(row["category"] for row in payload["incidents"]))
    for category in category_order:
        label, action, acceptance = CATEGORY_ACTIONS[category]
        lines.extend(["## " + label, ""])
        rows = [row for row in payload["incidents"] if row["category"] == category]
        for build_source in BUILD_ORDER:
            cohort = [row for row in rows if row["build_source"] == build_source]
            if not cohort:
                continue
            lines.extend(["### " + BUILD_LABELS[build_source], ""])
            for row in cohort:
                lines.extend([
                    "#### " + markdown_text(row["title"]), "",
                    "- Incident: " + markdown_text(row["incident_id"]),
                    "- Priority: %s; status: %s; rule: %s v%d." % (
                        markdown_text(row["severity"]), markdown_text(row["status"]),
                        markdown_text(row["rule_id"]), row["rule_version"],
                    ),
                    "- Evidence classification: " + EVIDENCE_LABELS[row["evidence_kind"]] + ".",
                    "- Evidence: %d events, %d distinct installations, %d distinct sessions; builds: %s; app versions: %s." % (
                        row["event_count"], row["installation_count"], row["session_count"],
                        markdown_text(", ".join(row["build_numbers"]) or "unknown"),
                        markdown_text(", ".join(row["app_versions"]) or "unknown"),
                    ),
                    "- First/last evidence received: %s / %s. Reopened: %d." % (
                        markdown_text(row["first_seen_at"] or "unavailable"),
                        markdown_text(row["last_seen_at"] or "unavailable"), row["reopened_count"],
                    ),
                    "- Linked operations: %s distinct (linkage in %d of %d evidence events). Linked chart references: %s distinct (linkage in %d of %d evidence events)." % (
                        row["operation_count"] if row["operation_count"] is not None else "unknown",
                        row["operation_linked_event_count"], row["event_count"],
                        row["affected_chart_count"] if row["affected_chart_count"] is not None else "unknown",
                        row["chart_linked_event_count"], row["event_count"],
                    ),
                    ("- Latest local replay evidence reference: " if payload.get("replay_context")
                     else "- Latest raw evidence reference: ") + markdown_text(row["latest_event_id"] or "unavailable after retention/deletion"),
                    "- Next action: " + action,
                    "- Verification required: " + acceptance,
                ])
                if not row["evidence_available"]:
                    lines.append("- Evidence unavailable: raw events expired or were erased. This retained task needs fresh permitted evidence; zero surviving counts do not establish a healthy feature or a verified fix.")
                if row["fixed_build_number"] is not None or row["verification_ref"]:
                    lines.append("- Proposed fix build: %s; verification reference: %s." % (
                        markdown_text(row["fixed_build_number"] or "unset"),
                        markdown_text(row["verification_ref"] or "unset"),
                    ))
                lines.append("")
    return "\n".join(lines)


def write_outputs(payload, output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, content in (
        ("work-queue.json", json.dumps(payload, indent=2, ensure_ascii=False) + "\n"),
        ("work-queue.md", render_markdown(payload)),
    ):
        destination = output_dir / name
        temporary_name = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output_dir,
                                             prefix=name + ".", suffix=".tmp", delete=False) as temporary:
                temporary_name = temporary.name
                temporary.write(content)
            os.replace(temporary_name, destination)
        finally:
            if temporary_name and Path(temporary_name).exists():
                Path(temporary_name).unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-json", type=Path, help="Read a saved aggregate queue payload instead of connecting to PostgreSQL.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory for work-queue.md and work-queue.json.")
    parser.add_argument("--limit", type=int, default=500, help="Maximum active incidents to return, 1–10000 (default 500).")
    args = parser.parse_args(argv)
    if not 1 <= args.limit <= 10_000:
        parser.error("--limit must be between 1 and 10000")
    try:
        if args.from_json:
            if args.from_json.stat().st_size > MAX_INPUT_BYTES:
                raise QueueError("Offline input exceeds the queue input safety limit.")
            value = json.loads(args.from_json.read_text(encoding="utf-8"))
        else:
            value = read_database(args.limit)
        payload = normalize_payload(value, args.limit)
        write_outputs(payload, args.output_dir)
    except QueueError as error:
        print("Telemetry queue: " + str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, TypeError):
        print("Telemetry queue: Could not read or write the local queue document.", file=sys.stderr)
        return 1
    print("Wrote %d of %d active incidents to %s" % (
        payload["returned_incident_count"], payload["active_incident_count"], args.output_dir,
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
