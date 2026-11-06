# Basic telemetry reduction — local handoff

Local branch: `codex/basic-telemetry-20261105`
Base: `4971b3ed82b7afc0239330df9bfdfb1f9ff5d88a` (canonical main, build 140 metadata)

The user authorized a local reduction to useful error counts and operation timings, with telemetry unable to gate launch, writing, rendering, or saving. Installs and automations remain paused. This checkout is isolated from the existing dirty notation and Build 142 worktrees. It is a source patch, not a device update.

## Retained diagnostics

Diagnostics remain optional, default off. Network telemetry accepts only fixed event names for launch/bootstrap, recognition failures, rendered counts, correction categories, PDF export, cloud backup/restore, and failures in account/purchase/forum operations. Only fixed error/operation/result categories, bounded counts, elapsed milliseconds, app/build, coarse platform/OS, and anonymous installation/session context are admitted. Delivery uses the existing anonymous publishable-key endpoint contract, without an account bearer token.

The local manual performance report retains a fixed list of completed operation timings and typed outcomes/error categories. It stays local until the user explicitly shares its sanitized export from Contact Us. Clear Report removes only the diagnostic trace and prepared report, including when a legacy trace has no eligible basic entries.

No chord text, chart title/content, raw ink, stroke geometry, appearance statistics, chart fingerprint/reference, arbitrary error message, keyboard/view-tree inspection, or authoring/rotation/visibility contract evidence is collected by these paths. Existing richer diagnostic queue entries are filtered on the worker before any upload. Existing performance traces are sanitized only for explicit export; their original bytes are retained until manual clearing.

## Failure isolation

- The app constructs real library/PDF stores before starting optional telemetry on a detached utility task. Startup never awaits telemetry configuration, queue migration, cleanup, or HTTP.
- Network recording admits fixed scalar values with a try-lock into a maximum 64-command buffer. A busy or full buffer drops optional observations. One utility task drains it; a separately coalesced consent task can cancel an upload held by HTTP.
- The timing recorder has an independent bounded buffer and utility queue. Producer calls never flush, export, clear, encode, or access diagnostic files. Legacy metadata autoclosures are not evaluated.
- Persistence no longer invokes diagnostic library rereads, hashes, checkpoints, or observers on the serial save queue. Actual save errors, retry behavior, serialization, source ownership, and render-consumption guards remain authoritative.
- Consent withdrawal invalidates captured grants immediately; regrant cannot revive old queued observations. Legacy checkpoint authorization and publication remain disabled. Optional observations can be absent because of consent, contention, capacity, or failures; absence is unknown, not success.

## Preservation boundary

There are no edits to Models, actual chart repositories, recognition algorithms, the render coordinator, or source-coverage policy. Source ink archives, pending ink, rendered chords, PDF files, and setlists are not migrated or deleted. Diagnostic cleanup uses only its exact known file paths. Tests use synthetic documents/bytes/drawings and temporary stores. No user chart/archive, iPad container, production database, deployment, release, or existing incident status was accessed or changed.

## Validation

Final native validation selected 439 tests: 437 passed, two optional device-archive replay tests skipped, zero failures. The synthetic blocked-diagnostic-storage save/reopen test and held-upload writing/rendering test passed. The focused portable persistence/configuration/privacy run passed 115 tests; the focused performance privacy run passed 25 tests. The native gate also compiles the full test target. Exact artifact paths and source patch identity are recorded in `.build/basic-telemetry-validation.json`. Portable model/configuration/privacy tests, focused Foundation telemetry tests, and focused local timing tests are separate from native UIKit/PencilKit tests. Native tests run only in a newly created local Simulator; they do not establish physical Pencil acceptance or an installed-device preservation result.

All five related iChart automations were read locally and remain PAUSED: monitor-ichart-telemetry-health; continue-after-sprint-62-setup-checks; continue-graph-and-myscript-mvps; finish-ichart-release-candidate-checks; verify-ipad-reader-retry-recovery. No monitoring checkpoint was advanced during this implementation.
