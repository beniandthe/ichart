# Telemetry backend deployment and live verification

Date: October 30, 2026. Project: iChart (`pausvvwoazbvmzyrebwl`).
The user explicitly authorized backend/ingest deployment and end-to-end verification.
Implementation source: `59f50b60d8b47a9f696355587b444da762ceb0d9`.

## Deployed artifacts

- Migration: `20261030151740_telemetry_feature_contract_pipeline`.
  The local migration filename was synchronized with the production-assigned
  version to prevent a later duplicate application. SQL contents were unchanged.
- `app-telemetry-ingest`: active version **43**, replacing version 42.
- All four retrieved deployed files matched the reviewed local files byte for
  byte: entrypoint, telemetry ingest, feature contract schema and existing
  subscription-authority helper. The helper and entrypoint were unchanged from
  the prior deployment. Existing API-key enforcement and `verify_jwt=false`
  were preserved; no authentication configuration was changed.
- Cron job 5: `ichart-telemetry-feature-contracts`, `*/5 * * * *`, active.

The prior function source/configuration is saved as `function-before-v42.json`
in the deployment evidence directory. Restore that exact artifact through the
normal function deployment tool if a rollback is required. The new tables are
additive; disable the named Cron job first if evaluation needs to be stopped.
Do not erase incidents or user telemetry as an automatic rollback action.

## Live acceptance results

The fixture used fresh UUIDs, `app_version=internal-verification`,
`build_number=0`, `build_source=debug_build`, `platform=iPadOS`, and a synthetic
chart reference. It contained no user chart, ink, chord text or account data.

| Check | Observed result |
| --- | --- |
| Valid request through deployed HTTP ingest | HTTP 202; six accepted IDs, one explicitly rejected malformed ID. |
| Identical retry | Same acknowledgment; exactly six fixture raw rows remained, with one evidence link per matched rule. |
| Wrong API key | HTTP 401; no records inserted by that request. |
| Reopen mismatch | One `data_preservation` contract-violation task; one operation/chart counted. |
| Readback exception with unknown content status | One `disk_persistence` operation-failure task; no claim of proven ink loss. |
| Passed reopen, safe render rejection, ordinary unknown baseline | Three ignored evaluations, zero task evidence links. |
| Legacy ink event | Accepted without requiring the new contract envelope; no contract-evaluation task. |
| Scheduled worker | Actual Cron runs 2412 and 2413 succeeded at 8:20 and 8:25 a.m. Pacific. |
| Queue health after scheduled processing | Pending 0, dead letters 0, rejected detector inputs 0, latest worker failures 0. |

The first scheduled run processed 250 outbox rows; the second processed 191.
This comprised 436 historical backfill events and five synthetic contract checks.
No manual worker invocation was used for this production acceptance test.

The two fixture tasks were resolved only after verification, with fixed build 0
and an explicit synthetic-verification reference. Their raw evidence/history was
retained under the ordinary telemetry retention policy. The fixture predicate
required the exact synthetic installation and `internal-verification` version;
no customer/release or historical task was modified or closed.

## Useful live work and coverage

The active queue contains **10 historical investigation/friction groups**:
seven cloud backup/restore groups and three recognition-workflow groups,
separated by debug/release/unknown build provenance. They contain **308** retained
historical evidence events. This live rolling backfill differs from the earlier
fixed-window replay (443 inputs/314 evidence) because the 30-day lower boundary
advanced before deployment. Historical problems have not been claimed fixed.

Device-origin contract checks and delivery counters have not yet arrived from a
released new client. Their absence remains unknown coverage, not zero failures.
The new app instrumentation still requires a separately released app update.
Raw handwriting contributions remain plan-only. Graph/MyScript remain paused.

## Access, retention and test fidelity

- `anon` and `authenticated` cannot use the private schema, read queue/outbox
  records, or execute the worker.
- The live database intentionally denies `service_role` private-schema usage
  under an earlier research-consent hardening migration. That boundary was
  preserved. Cron runs under its trusted PostgreSQL owner; the task consumer
  uses an authorized operator database connection, not a public/service API key.
- Permitted service-role insertion into public raw telemetry still reaches the
  private outbox through its definer trigger. Local integration tests now
  reproduce the live namespace denial and test actual role behavior.
- Existing account-deletion cascade and the active 180-day retention job were
  verified before deployment. Raw-evidence/outbox foreign keys cascade raw
  deletion; task records retain no copied installation/account identifiers.
- Security-advisor categories/counts were unchanged by this deployment; no new
  telemetry finding was reported. Existing unrelated notices were not modified.
- Post-deployment local checks: 25 ingest/schema checks, 13 native PostgreSQL
  checks and 14 task-consumer checks passed. The earlier 136 simulator tests
  remain the client implementation evidence; no device install was performed.

## Evidence locations

Durable deployment directory:
`/Users/benirossman/.codex/visualizations/2026/10/30/01a18d3a-4ef7-70f1-865b-2968d97b4810/telemetry-deployment/`.

- `preflight.json`, `deployment-state.json`, `access-verification.json`.
- `http-verification.json`, `synthetic-request.json`, `synthetic-identifiers.json`.
- `end-to-end-verification.json`, `synthetic-task-closure.json`.
- `live-work-queue.json`, `live-review/work-queue.md`, `live-review/work-queue.json`.
- `function-before-v42.json` for exact function rollback source.

The temporary publishable-key file used by the HTTP verification was removed.
No secret/service key was copied into the request, evidence or repository.
