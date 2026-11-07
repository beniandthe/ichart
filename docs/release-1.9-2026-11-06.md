# iChart 1.9 release integration — November 6, 2026

## Candidate

The user accepted installed development Build 149 as the new baseline and
requested v1.9 submission with automatic public release after approval, without
a phased rollout. The distribution package must be built afresh from the
integrated release source; the development-signed 1.2.4 (149) app is preserved
locally as recovery evidence.

- Accepted branch: `codex/clarity-workflows-20261106`, tip `745f961a`.
- Accepted app source: `d8774fa7`; the tip adds installation documentation only.
- Main integrated alongside it: `c850c98d` (#104), with #103 already inherited.
- Authoritative package configuration: **1.9 (150)**. Live App Store Connect
  inspection confirmed no existing 1.9 version/upload; its latest completed
  upload is 1.2.3 (78).
- Personal comparison resources remain excluded explicitly with
  `ICHART_INCLUDE_PERSONAL_ML_COMPARISON=NO`.

The 1.9 Apple version record is created with automatic release after approval
and immediate release to all users (no phased rollout). These are saved release
settings, not a review submission or public-availability receipt.

## Included behavior

Structured mode/layout-specific tool explainers and a local Guide; stable
instruction space; explicit form-marker and measure targets; readable Measure
Layout actions with availability reasons; cancellable chart creation;
search/sort and scoped visible-result deletion; direct PDF/setlist handoffs and
specific unavailable-file recovery; semantic action/guidance colors and fewer
nested panels. Existing recognizer, recovery and source-ink ownership remain.

Preserve `cccd92b7`'s concrete SwiftUI button and row type boundaries: they repair
the physical Write & Render entry stack overflow. Handwritten chord-repeat `%`
remains supported. Handwritten bar-and-dot measure/range repeat ingestion stays
retired; those operations use Tools > Repeats. Graph, MyScript and ML-core work
remain parked.

## Evidence and delivery gates

The accepted source has recorded focused and broad Simulator validation, plus
the earlier physical entry regression. Build 149's stopped-data preservation
receipt is separate from fresh physical Pencil accuracy; its two later physical
QA automation attempts timed out before feature methods ran. The user's overall
Build 149 acceptance does not change those evidence limits.

This integration requires fresh exact-source configuration/workflow checks,
ordinary protected PR checks, a distribution-signed Release archive/export,
strict artifact identity/signature/profile/ML-exclusion inspection, and live
Apple upload/processing/selection/submission verification. Keep review and
public-distribution status separate. Do not claim submission or availability
from local archive or CI success.

Fresh release checks caught an unconditional UIKit import in a shared styling
file. The UIKit import and UIKit-only color enum are now conditionally compiled;
the active iOS implementation is unchanged. Help-content contracts retain their
content/access checks while dropping assertions for the retired nested-card
styling. A separate simulator-wrapper fixture repair preserves the production
wrapper and its child-reaping order, adds a bounded restoration deadline, and
checks that restoration observes the child already reaped. Its 26 mock tests
and 20 repeated cancellation subcases passed locally.

Both native CI lanes also exposed accumulated camera rounding when tool chrome
changed the viewport height. Four repeated tool round trips measured two screen
points of drift before rotation. The viewport now retains its requested paper
focus separately from UIKit's pixel-rounded offset, while genuine pan/zoom
changes establish a new focus and edge clamps admit the reachable focus on each
axis. Paper geometry, source ink and saved notation are unchanged. The original
failing integration test passes with its original one-point assertions intact.
All 24 owning native geometry tests passed locally, including new repeated
both-layout tool/rotation, fractional-height, native pan/zoom and independent
axis-clamp coverage. Fresh hosted checks and rebuilt release artifacts remain
required for this source change.

The next full native pass caught a review-form fixture assumption: the ending
label row can remain uncreated below the unscrolled SwiftUI Form. The hosted
failure and unchanged local reproduction both stopped before typing or approval;
the panel, suspended input and cleared clock were already correct. The fixture
now scrolls only the presented Form to reveal an enabled, visible label, following
the existing feedback-test pattern. Its three-second panel budget, subsequent
four-second commit budget and all source-ink/chart assertions remain intact.
This follow-up changes tests and documentation only; the distribution runtime
and captured screenshot source inputs are unchanged.

## Repository preservation

Before integration, all 153 local refs (including raw tree refs and annotated
tags) were bundled, restored with exact ref/object equality, and passed full
Git integrity checks. Nine dirty worktrees have private patches and hashed
changed/untracked-file archives verified by readback. Ignored build trees,
personal device snapshots, database archives and credentials remain outside
cleanup scope. Nothing from these private packets belongs in GitHub or Apple
metadata.

GitHub had no open PRs and only protected `main` before this release branch.
Retain unfinished or parked work; remove only demonstrably redundant clean
refs/worktrees after recoverability checks. Keep the existing issue #96 open
until its independent missing-event investigation has evidence of resolution.
