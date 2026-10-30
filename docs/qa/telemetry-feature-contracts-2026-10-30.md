# Telemetry feature-contract pipeline validation

Date: October 30, 2026. Implementation branch: `codex/telemetry-feature-contracts`.
Base: verified remote `main`, `2dab831600c0a5614ce18f8849b5a420fbb4caf2`.
Isolated checkout: `/private/tmp/ichart-telemetry-feature-contracts`.

## Local execution evidence

- Xcode simulator run: **136 passed, zero failed, zero skipped**. Verified through
  `xcresulttool get test-results summary`, including execution on iPad Pro 11-inch
  (M5), iOS 26.5, device `165234BC-33C0-48D7-896B-9AD058C13C53`.
- Executed app classes: `ChartLibraryStoreTests`,
  `ChartPersistenceContractDiagnosticsTests`, `ChordInkDraftLiveRenderTests`,
  `ChordInkDraftRenderCoordinatorTests`, `LeadSheetInkFeatureContractTests`,
  `TelemetryTests`, `TrialTelemetryTransportTests`.
- Ingest/schema Node suite: **25 passed**, zero failures/skips.
- Native PostgreSQL 17 integration suite: **13 passed**, zero failures/skips.
  Uses an isolated synthetic Unix-socket cluster. Cron scheduling is a registration
  adapter in this test, not a claim that the hosted Cron daemon ran.
- Task consumer Python suite: **14 passed**.
- Existing workflow-scope suite: **4 passed**.
- `git diff --check` passed. Recognition source/model paths have no changes.

Xcode log and result bundle:

- `/private/tmp/ichart-telemetry-validation/xcode-tests.log`
- `/private/tmp/ichart-telemetry-validation/AppTests.xcresult`
- `/private/tmp/ichart-telemetry-validation/test-summary.json`

## Existing-data replay

Read-only production export covered events received from September 30, 2026 at
14:33:28 UTC through October 30, 2026 at 14:33:28 UTC. It selected only cloud push
failures, cloud restore failures and rendered-chord correction events. Account
identifiers were omitted; original event, installation and session identifiers
were replaced by synthetic UUIDs inside the query. Only fixed detector fields
were selected. No charts, ink, chord text, titles or private documents were read.

The isolated local pipeline replay processed **443 events** into **10 task groups**:
seven cloud investigation groups and three recognition-friction groups, separated
by debug/release/unknown build type. Their evidence totals **314 events**; 99
cancellations, 25 offline events and five equivalent-spelling edits were excluded
from task creation. These are investigation/friction findings, not established
historical ink loss or recognition-accuracy measurements.

Replay and reviewed task artifacts are under:
`/Users/benirossman/.codex/visualizations/2026/10/30/01a18d3a-4ef7-70f1-865b-2968d97b4810/telemetry-pipeline/`.
The final preview is `production-review-v2/work-queue.md`; its incident/evidence
UUIDs belong to the local replay. `production-work-queue-v2.json` retains the
mapping to synthetic input event IDs. Legacy operation/chart linkage and transport
loss accounting remain unknown; the report preserves this missing coverage.

## Activation and acceptance boundaries

No production migration, Edge Function deployment, Cron job, external task,
push, PR, physical-device installation or App Store release was performed.
The production project still has its original raw-event/aggregate-view schema.
Backend activation must precede new-client shipment so supported contract events
do not enter the client's rejected-event quarantine.

The proposed migration adds private incident/evidence/outbox tables, the bounded
five-minute worker and a last-30-day backfill capped at 25,000 existing events.
It does not modify chart data, source ink, recognition decisions or app backup
contents. Actual new-device probes require an app containing this implementation.

After authorized backend activation, verify a marked synthetic contract violation
through ingest, outbox and task evidence; verify a safe passed/unknown/protected
check creates no defect task; inspect real Cron run results. Then take an existing
investigation through reproduction, fix and fresh verification. The pipeline is
not evidence that those product problems have already been resolved.

The separately authorized handwriting-contribution handoff is plan-only. See
`docs/telemetry-implementation-plan-2026-10-30.md`. Graph/MyScript remain paused.
