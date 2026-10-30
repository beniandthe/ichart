# Chart and ink telemetry: feature contracts and work queue

The phased implementation and separately gated handwriting-contribution design
are maintained in [the implementation plan](telemetry-implementation-plan-2026-10-30.md).

This pipeline turns a measured feature failure into retained evidence and a categorized engineering task. Its operating loop is:

`feature promise → local contract check → consented event → durable evaluation outbox → deterministic detector → deduplicated incident → fix → verification → recurrence check`

The backend was deployed on October 30, 2026 as migration
`20261030151740_telemetry_feature_contract_pipeline`, with `app-telemetry-ingest`
version 43. Actual scheduled runs at 8:20 and 8:25 a.m. Pacific completed the
historical backfill and synthetic end-to-end verification. See the
[deployment receipt](qa/telemetry-backend-deployment-2026-10-30.md). The new
on-device checks still require a client containing this instrumentation; this
backend activation did not release or install an app.

## What earns a task

Every detector names a feature contract, the observation that would contradict it, the evidence required, and exclusions. Client-supplied severity or task category is never authoritative. The backend registry supplies those values.

| Feature promise | Contract check | Category | Evidence boundary |
| --- | --- | --- | --- |
| An accepted library save reports its real repository result. | `chart.save` | `disk_persistence` | A failed save is an observed operation failure. It does not by itself establish that existing data was lost. Coalesced or superseded generations are not failed saves. |
| Opening a library reports a real load result. | `chart.load` | `disk_persistence` | A load exception is observable. A missing library with a valid prior durable checkpoint is also a failed load; legitimate first launch without a file/checkpoint is not. |
| A sampled completed save can be read back as intended. | `chart.save_readback` | `disk_persistence` | A missing, older or mixed readback after successful save is a mismatch. Only a positively newer concurrent revision of the same chart set is excluded as unknown. Readback exceptions remain unknown, rather than proving loss. |
| A known durable source baseline remains consistent when reopened. | `ink.reopen_preservation` | `data_preservation` | A comparable baseline is required. Missing or externally changed baselines remain unknown, rather than becoming invented loss events. |
| Rendering transfers required source before consuming the live draft; safe rejection preserves it. | `ink.render_preservation` | `render_transaction` | A successful render intentionally clears the live draft. Check committed source receipts and intentionally consumed structural barline input. Safe stale/incomplete-review rejection is a protected rejection. |
| Reprojection conserves source and produces finite geometry. | `ink.rotation_preservation` | `ink_geometry_visibility` | Stroke/point conservation does not prove that screen placement or focal-point behavior was correct. Device acceptance still matters. |
| Export reports terminal failure. | `chart.export` | `render_transaction` | The registry supports this contract. A registry entry alone does not establish client instrumentation coverage. |
| Backup/restore failures can be investigated without retry noise being labeled data loss. | Legacy cloud failure rules | `cloud_backup_restore` | Server/authentication/timeout/sync-error evidence is an investigation lead. Cancellation and offline conditions are not automatic defect tasks. |
| Repeated manual corrections reveal workflow friction. | Legacy rendered-correction rule | `recognition_workflow` | Corrections do not label the intended chord or prove recognition accuracy. Equivalent spelling can be an intentional edit. |

Use four evidence labels consistently:

- `contract_violation`: a supplied local invariant contradicted the feature contract. Investigate the cause before claiming a specific defect.
- `operation_failure`: the operation actually failed, with no automatic claim that data was lost.
- `investigation`: a legacy operational signal needing diagnosis.
- `friction`: a measured workflow cost, without an accuracy or data-loss claim.

Passed checks, unknown checks, and safe protected rejections remain useful coverage evidence. They do not all create bug tasks. The `private.telemetry_contract_outcomes` view keeps contract/outcome coverage separate from the incident queue. Inspect it before treating an empty category as proof of health.

## Event and privacy boundary

New checks use `feature.contract_checked` with a versioned contract ID, an operation UUID, a typed outcome and reason, and bounded counts/bytes/equality flags. `build_source` is recorded on new events so a missing launch event does not erase build provenance. Where chart linkage is needed, `chart_reference` is derived from the consented installation namespace and chart identity; it is not the chart's raw UUID or a hash of its musical contents.

Diagnostics stay behind the existing explicit telemetry opt-in. Withdrawal invalidates the consent generation and installation namespace. This pipeline does not authorize collection of chart/song titles, chord text, raw strokes/drawings, screenshots, PDF contents, chart JSON or content hashes. Content comparisons happen locally; only their result and permitted aggregates are transmitted.

The client and ingest sanitizers both validate the event schema. Unknown fields and invalid typed values are rejected or dropped according to the ingest contract. Transport acknowledgments identify accepted event IDs, so a partial successful HTTP response cannot silently remove the entire queued batch.

Persistence checks run outside the PencilKit authoring path. Successful saves/readbacks are sampled at the first actual save and then a minimum thirty-second interval; actual save failures are admitted immediately. A verified readback establishes a local checkpoint only after the real save, and a checkpoint-write failure cannot fail the user's save. Reopen source comparisons require the same chart revision; unrelated edits, a changed baseline or consent namespace remain unknown. The checkpoint and source digests stay local and are never telemetry properties.

Counts have explicit meanings:

- Event count is retained evidence occurrences, including repeated operations and retries.
- Installation and session counts are distinct identifiers among retained evidence. They are not unique people.
- `operation_count` and `affected_chart_count` use valid operation/chart correlation identifiers and remain null when linkage is unavailable. `operation_linked_event_count` and `chart_linked_event_count` disclose how much of the incident's evidence supports those counts. A chart reference is scoped to an installation; it is not a person or a global unique-chart count.
- Build type is `debug_build`, `release_build` or `unknown`. Release does not establish an App Store customer session; internal testing can use a release build.
- Passed/violated ratios are valid only within the same instrumented contract version, scope and sampling policy. Missing or opted-out sessions are outside that denominator.
- First/last incident evidence times are server receipt times. Late offline uploads can refer to older experiences.

## Automatic storage and classification

The migration `supabase/migrations/20261030151740_telemetry_feature_contract_pipeline.sql` adds private tables and views:

| Object | Purpose |
| --- | --- |
| `private.telemetry_contract_definitions` | Server-owned categories, severity, accepted reasons and rule version. |
| `private.telemetry_evaluation_outbox` | Atomic, durable evaluation request linked to the raw event. An insert trigger only enqueues work. |
| `private.telemetry_incidents` | Deduplicated task state for a rule/version/build-type cohort. |
| `private.telemetry_incident_events` | Unique raw-event/rule/version evidence links. Reprocessing cannot inflate the evidence count. |
| `private.telemetry_incident_history` | Task status transitions and recurrence history. |
| `private.telemetry_evaluation_runs` | Worker execution results. |
| `private.telemetry_work_queue` | Active task metadata and counts derived from retained raw evidence. |
| `private.telemetry_pipeline_health` | Pending/dead-letter/rejected counts and latest worker execution. |
| `private.telemetry_contract_outcomes` | Instrumented outcome coverage, separate from task creation. |

The worker runs every five minutes through pg_cron and processes a bounded batch. `FOR UPDATE SKIP LOCKED` permits overlapping invocations without processing the same pending row concurrently. Failure retries use backoff; repeatedly failing events enter a visible dead-letter state. This avoids a client timestamp cursor that would skip delayed or out-of-order events.

The migration also enqueues a bounded last-30-day backfill of existing cloud failures and rendered corrections, capped at 25,000 raw events. These become investigation/friction evidence only. It cannot reconstruct past ink-loss invariants that were never measured.

Outbox and evidence records reference raw telemetry with deletion cascades. Derived counts are computed from those retained links so account erasure or age-based retention does not leave stale distinct-installation counts. The engineering task survives evidence expiry/erasure, with `evidence_available=false`, zero surviving counts, empty build lists and unavailable first/last/evidence references. That state needs fresh permitted evidence; it is not a healthy outcome or a verified fix. Incident task metadata does not copy owner IDs, installation IDs, chart contents or raw properties into a separate permanent store. There is no public task-creation RPC.

The existing production boundary intentionally denies `service_role` usage of the `private` schema. This pipeline preserves that boundary: table/function grants alone do not make private objects accessible without schema usage. The ingest service inserts permitted raw events in `public.telemetry_events`; its narrowly scoped `SECURITY DEFINER` trigger enqueues evaluation. The scheduled worker runs as its trusted PostgreSQL scheduling owner. Private queue inspection and task-state changes use an authorized operator database connection, not a client or service API key. Do not restore broad private-schema usage to make an operator query work: that would also make previously granted private objects outside telemetry usable.

## Review the work queue

Use an authorized operator database URL with the necessary private-schema access from the existing local secret-management flow. A Supabase service API key is not that connection; a connection running as `service_role` cannot query this schema directly. Do not paste credentials into a script, issue, report or command argument. The consumer reads `ICHART_TELEMETRY_DATABASE_URL` and passes it to libpq through the child environment, never through the process command line.

```sh
python3 scripts/telemetry_work_queue.py --output-dir /private/tmp/ichart-telemetry-review
```

The command executes a read-only transaction and writes only local `work-queue.md` and `work-queue.json` files. It neither changes incident state nor creates GitHub/Linear tasks or sends notifications. Database errors are redacted because libpq messages can contain connection details.

The review groups tasks by the six categories, separates debug/release/unknown cohorts, and includes severity, evidence classification, repeated/distinct counts, operation/chart counts with linkage coverage, builds, raw evidence reference, a concrete next action and a verification condition. A bounded result states when additional incidents were omitted. `--limit` accepts 1–10,000, defaulting to 500.

Offline review uses the same aggregate JSON shape, without database access:

```sh
python3 scripts/telemetry_work_queue.py \
  --from-json /private/tmp/saved-queue.json \
  --output-dir /private/tmp/ichart-telemetry-review
```

The input has `generated_at`, `health`, `incidents`, and optional `active_incident_count`. The consumer discards undocumented input keys, validates counts/identifiers/timestamps, escapes external Markdown labels and fails visibly on unknown category/evidence schemas. Its JSON output contains reviewed aggregate fields only.

An anonymized local replay adds exactly `replay_context: {"mode":"local_replay","anonymized":true}`. The consumer then labels incident/evidence UUIDs as local replay identities and states that the report does not demonstrate a live production pipeline. A replay can evaluate a minimal production event export with identifiers replaced, while the inserted database row IDs belong only to its isolated database. The runner's `replay_evidence` identity map stays in the raw replay output and is discarded from the reviewed report. Arbitrary free-text replay notes are not accepted.

Always read the health block before interpreting an empty queue. Dead letters, schema rejects, a missing worker run, the latest run's failures, or pending/worker activity over fifteen minutes old produce visible review warnings. The fifteen-minute threshold allows three nominal worker intervals; it is an initial operating guardrail, not a measured service-level target. This local report exposes health only when it is run; separate notification scheduling must be configured explicitly if required.

Delivery-health coverage is tracked separately from incidents. `delivery_reporting_installation_count` and `last_delivery_reported_at` show whether compatible clients supplied any transport accounting. Queue overflow, ingest rejection, quarantine overflow and unacknowledged-batch totals are the latest cumulative counters per reporting installation, summed across those installations. They are not event counts, incident counts or failure rates. A null counter means no usable reporting coverage; it must not be converted into zero delivery loss. The consumer warns explicitly when no installation has reported these counters.

For direct operator inspection, use an authorized private-schema database connection:

```sql
select * from private.telemetry_pipeline_health;
select * from private.telemetry_work_queue order by priority_rank, last_seen_at desc;
select * from private.telemetry_contract_outcomes;
```

## Work, verify and reopen

The lifecycle is `new → triaged → in_progress → verifying → resolved`, with `ignored` available for a reviewed non-actionable rule pattern. Preserve the underlying evidence and record why a finding is non-actionable in the engineering work record. An ignored task should not be used to make incident volume look healthier.

An authorized operator may update status and fix evidence on `private.telemetry_incidents`. Resolution requires both a numeric `fixed_build_number` and a nonempty `verification_ref`; the database trigger rejects unsupported closure. The verification reference should identify the fresh reproduction, the changed behavior, the tested build and the relevant automated/device evidence. Merely seeing no new events is insufficient, especially with opt-out, sampling or low activity.

```sql
-- Replace the UUID and evidence with the reviewed task's actual values.
update private.telemetry_incidents
set status = 'triaged'
where incident_id = '00000000-0000-4000-8000-000000000001';

update private.telemetry_incidents
set status = 'resolved',
    fixed_build_number = '123',
    verification_ref = 'Reviewed reproduction and verification record for build 123'
where incident_id = '00000000-0000-4000-8000-000000000001';
```

Fresh post-resolution evidence on or after the fixed build reopens the incident and increments its recurrence count. A delayed event from an older build must not undo a verified fix. The automatic check does not replace device verification or prove the root cause of a recurrence.

The bounded worker can be run manually by an authorized operator:

```sql
select private.process_telemetry_evaluations(250);
```

After fixing a detector failure, reset only the reviewed dead-letter event IDs, then run a bounded batch. Do not erase all detector errors or replay an unbounded history to make health appear green.

```sql
update private.telemetry_evaluation_outbox
set dead_letter_at = null,
    attempts = 0,
    next_attempt_at = now(),
    last_error_code = null
where raw_event_id = '00000000-0000-4000-8000-000000000001'
  and dead_letter_at is not null;
select private.process_telemetry_evaluations(250);
```

## Acceptance gates

Before production activation, verify the migration and classifier with an isolated PostgreSQL database, including duplicate/late events, overlapping workers, rejection/unknown cases, retention/deletion cascades, status validation and fixed-build recurrence. Run ingest/client privacy and partial-acknowledgment tests. Activate the backend first: apply the reviewed migration, deploy the compatible ingest allowlist/acknowledgment handling, and verify the bounded worker and legacy intake before shipping the new client instrumentation. This prevents a newer client from sending contract checks to a backend that does not yet accept them. The queue must remain honest about which checks are actually arriving.

The local consumer has a focused offline test suite:

```sh
python3 -m unittest discover -s scripts -p test_telemetry_work_queue.py -v
```

After deployment, verify one authorized synthetic event through ingest, outbox, classification and work-queue evidence; verify a safe passed/unknown/protected-rejection event creates no defect task; inspect the actual cron run results. Keep synthetic/debug evidence separate from release cohorts. Then review existing investigation/friction tasks and take the first evidence-backed item through reproduction, fix and fresh verification. That completed loop is the acceptance criterion for useful telemetry consumption.
