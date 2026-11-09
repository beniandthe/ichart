# iPad Build 154 distribution integration

Date: November 9, 2026. Distribution identity: **1.9.1 (155)**.

The physical iPad inventory reports com.ichart.app 1.2.4 (154). Its retained
development-signed ZIP matches all 56 signed-file entries and SHA-256
`ed3f00d66ea4ce422f1bec1971317a168b726f39c4eb9bfe96a483481e8f39f5`.
All 1,294 captured final source files match the current isolated chord-drag
worktree. Replaying its 42-file patch against d8774fa7 reconstructs all 37
changed runtime/test files exactly. The five QA documents include later install
readbacks and remain separate from the compiled-source claim.

This integration starts at main 9c21e5df and applies only the captured delta.
All 16 changed app files remain exact. Main's telemetry retry, viewport camera
rounding and UIKit portability fixes remain exact. Two overlapping source tests
were reconciled against the actual controls. Release version and build are
authoritative in project.yml and ProjectConfigurationTests.swift. The original
dirty worktree and signed development artifact are preserved.

## Behavior and guidance

- Direct chord movement retains touch-down ownership, separates body movement
  from explicit delete/resize actions and uses a transient movement preview.
- Measures, Repeats and Time Signature retain canvas measure selection when
  an object overlay is inactive.
- A single identity-bound Library confirmation permits successive deletions
  while preserving immutable confirmed targets and cancellation behavior.
- Bounded geometry caching avoids repeated editor sizing work without changing
  chart/ink data or the layout engines.
- Automatic rendering matures independent completed targets between strokes;
  structural waits belong to their unchanged source, and retained ink is
  reanchored only with fresh one-to-one ownership and row proofs. Manual preview
  rendering retains its explicit commit flow.

Tool helpers, Guide, Settings, accessibility, Quick Start and How To are updated
together. Handwritten % chord repeats remain supported. Bar-and-dot measure
repeat ingestion remains retired; range repeats use Tools > Repeats.

## Evidence boundaries

The prepackage portable suite executed 2,065 cases: 1,973 passed, 92 skipped and
zero failed. Native build-for-testing succeeded on an isolated iPad Simulator.
Focused native/UI execution and final GitHub release checks are tracked in the
release packet and PR; this document does not claim pending checks have passed.

Read-only source review found no confirmed release blocker. A follow-up coverage
boundary remains for an explicit correction carried through a placement-refused
partial barline split and the next Editor census; no normal-UI failure has been
demonstrated. Chart-only deletion UI coverage does not establish the mounted
PDF/error handoff path. Existing store behavior remains unchanged.

The prior installation receipt separately records saved-content preservation.
This distribution task does not stop, replace or alter the physical iPad app.
It does not establish fresh physical Pencil cadence or drag-feel acceptance,
backend health, or telemetry delivery. Parked ML work and other dirty worktrees
are outside the integration.

## Full hosted native follow-up

Both original hosted native runs executed 3,479 cases and reported the same four
assertion events in three existing document-navigation test methods. All 80 new
unit methods passed. Local reproduction matched the hosted failures.

The blank-paper fixture sampled (172.4, 248), inside the neighboring Cmaj7/E
glyph frame (117, 212.843568, 86.74748, 66.312864). The point was inside the
viewport with navigation enabled. Select correctly retained the visible chord
owner immediately after the old post-render editing delay was removed. The
fixture now chooses and asserts visible paper outside every chord body and
padded control; finger and Pencil scrolling expectations remain true.

The narrow C/G fixtures required the former padded-control interception that
the installed Build 154 intentionally removes. They now require every visible
sample to resolve review for the exact chord and measure, and require padded
controls to remain outside the body. All selected/unselected finger/Pencil
correction dispatch, outside-control rejection and exact chart/ink assertions
remain. No tolerances or deadlines were relaxed.

All eight owning navigation tests passed after these test-only corrections.
An independent source review found no weakened contract. All 396 distribution
source inputs and the delivered IPA remain byte-exact; no app, configuration,
resource, signing or workflow changes follow the archive. The final hosted
checks must run against the corrected test commit before merge/submission.
