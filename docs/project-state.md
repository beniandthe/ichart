# Project state and release backlog

Updated: 2026-10-05. This is the start-here document for the active app project.
Older sprint plans and recognition reports remain evidence, not an automatically
expanding work queue. Update this file when an item is implemented, verified, or
blocked; record the actual evidence before changing its status.

## Active tree and purpose

- Branch: `codex/app-release-normalization`.
- Worktree: `/Users/benirossman/.codex/worktrees/app-release-normalization/Smart Chart`.
- Recovery base: retained recognition snapshot `417113a`; the completed app
  fixes from `ad6cbee` were reconciled in merge `b717073` with both histories retained.
- Product scope: Simple Chord Sheet and Rhythm Section Sheet on iPad.
- Release objective: write, inspect, repair exceptions, render, edit, save, and
  export without losing useful work. A musician must be able to complete a chart
  even when the reader misses or misreads a chord.

Normalization implementation is complete. Automated and Release-build results
are recorded below as they finish. This is an actionable app-development baseline,
not approval to publish. A build or test count is not evidence of improved fresh
handwriting recognition. Signing, installation, Pencil interaction, upload, and
publication must each be recorded separately.

## Preserved work and current evidence

| Item | Recorded status | Meaning for this release |
| --- | --- | --- |
| Chord-only reader/suggestion boundary | Implemented in retained research tree; documented build 57 installed and launched on 2026-10-03 | Keep the safety behavior; do not claim a new accuracy gain. |
| Full input retained for newly taught lessons | Implemented and tested in retained tree; prepared build 60 was not installed at that checkpoint | Keep storage fix and legacy compatibility; discarded legacy points cannot be recovered. |
| Before/After learning eligibility and internal candidate cleanup | Implemented and tested in retained tree | Retain maintenance fixes; workflow tests do not establish personalization benefit. |
| Experimental personalized ML | Recorded failed acceptance criteria | Park it; no weight promotion or automatic release dependency. |
| Normalization and recovery/telemetry work listed below | Implemented; automated gates and unsigned Release build passed | Require the separately recorded physical-device acceptance before release. |

Evidence: [reader boundary](chord-reader-domain-boundary-2026-10-03.md),
[lesson fidelity](personal-lesson-input-fidelity-2026-10-03.md),
[paired handwriting results](personal-append-only-glyph-coverage-results-2026-10-03.md),
[support-match experiment verdict](personal-support-match-defer-results-2026-10-03.md).
These reports contain dated observations. They do not establish the current
device, remote deployment, or App Store state.

## Finite active backlog

All implementation items below are part of this normalization pass. Their
acceptance checks define completion; none is completed merely by being listed.

| Priority | Deliverable | Acceptance check | Status |
| --- | --- | --- | --- |
| 1 | Repair unread draft chords in review | User can type a valid intended chord for an unread target, navigate rows with a usable keyboard, and continue. Unsupported text remains unresolved. Exact remaining ink is preserved. | Implemented; device acceptance pending |
| 1 | Rewrite only the selected chord | Rewriting one target preserves every unrelated pending chord and its ink; stale/ambiguous ownership is refused safely. Explicit whole-draft discard remains available with clear meaning. | Implemented; device acceptance pending |
| 1 | One reliable write → review → repair → render flow | Both styles support mixed correct, uncertain, and unread drafts, cancellation, continued writing, and later editing. Rendering clears only ink covered by accepted objects. | Implemented; device acceptance pending |
| 1 | Explicit optional handwriting learning | No forced setup on ordinary chart entry. Existing profiles/examples remain available. Saved preference and reset/opt-out behavior are explicit and tested. | Implemented; existing choices preserved |
| 1 | Define and enforce release reader behavior | Standard reader is the default. Example-based learning is a separately chosen setting; research comparisons and model packages do not silently participate in normal entry. | Verified; Release artifact contains no experimental model/Study resources |
| 2 | Count review repairs and preserve attribution | Batch review corrections emit content-free metrics; current recognition-version names retain correction attribution. No chord text, raw ink, or handwriting examples enter ordinary telemetry. | Implemented; ingest deployment/delivery pending |
| 2 | Measure preview responsiveness accurately | Record last PencilKit input callback → preview publication, separately from recognizer computation. This includes waiting/preparation, but is not a screen-pixel or Pencil-latency measurement. | Implemented; dense-page device check pending |
| 2 | Establish ordinary-use measures | Use the metric definitions below, keep internal testing separate where classification is available, and do not infer chord accuracy from preview-event counts. | Defined below |
| 3 | Validate release candidate in both styles | Complete the release gates below, recording artifact/version and observed result. No unresolved ink-loss or blocked-recovery defect is acceptable. | Automated gates passed; physical acceptance/signing/delivery pending |

New recognizer changes enter this backlog only for a specific reproduced defect.
Keep the standard-reader comparison fixed, check new wrong reads as well as
recoveries, and preserve exact ink. Do not add broad model training, public-corpus
intake, additional writers, or repeated favorable-prompt testing to this pass.

## Measurement for the trial

Use three product questions. Telemetry is a diagnostic aid; it cannot supply
ground truth about a written chord without an explicit labeled test.

| Question | Measure | Limits and interpretation |
| --- | --- | --- |
| Can users complete useful work? | Successful render and PDF export events, plus a controlled create/save/reopen/export pass | An export event is not a completed-chart accuracy score. Installation IDs are not guaranteed distinct customers; classify internal tests where possible. |
| How much repair does writing require? | Batch-review changes, post-render corrections, local rewrites, and draft discards per eligible workflow | Distinguish recognition repair from intentional musical edits where possible. Do not use repeated previews as a written-chord denominator. |
| Does writing remain responsive and preserve work? | Input-to-preview timings, computation timings separately, persistence errors, and observed dense-page Pencil behavior | Instrumented preview delay does not prove visible ink latency. Orientation, key changes, saving, and reopening need device checks. |

Inspect failures and denominators before comparing builds. Retain the existing
telemetry; add only the repair/attribution/latency fields needed for these
questions. Any production telemetry function deployment needs its own recorded
outcome; a locally passing backend test is not a deployment receipt.

## Release gates

1. **Source and configuration:** finish reconciliation, inspect the active diff,
   and record branch/commit. Generate from `project.yml`. Use a fresh DerivedData
   path without experimental comparison opt-in; confirm the normal app contains
   no comparison model package.
2. **App verification:** run SwiftPM and the iChart Xcode suites relevant to the
   change. Check a nonzero executed test count from the `.xcresult` summary and
   inspect failures/skips. Keep existing parser, recognition trust, ink, layout,
   profile compatibility, and persistence regression checks.
3. **Physical iPad acceptance, both styles:** write a mixed draft, repair one
   unread chord, edit one misread chord, locally rewrite one target, cancel and
   resume review, render, move/edit rendered chords, save/reopen, and export.
   Dense-page writing, erasure, rotation, and key/transposition changes must
   preserve ink placement and usable layout. Check repeats/setup staff lines,
   header/text input, margins, and form-marker sizing on existing fixtures.
4. **Trial verdict:** record whether the write-and-repair workflow is comfortable
   enough to trial. If repair effort defeats the input method, name that blocker
   and revise the flow. Do not reinterpret workflow success as near-perfect
   recognition or prescribe another open-ended ML run.
5. **Release mechanics:** verify version/build, signing, app installation and
   launch, telemetry delivery for the actual candidate, and release archive.
   Record upload/TestFlight/App Store outcomes separately; none is implied by a
   successful local build. Existing signing/account/release checklists remain
   supporting procedures, not evidence that this candidate passed them.

Ordinary CI runs SwiftPM and iChart Simulator tests. ResearchStudy and Python/
Core ML contracts are explicit opt-in checks through workflow dispatch. This
changes which project is required for an app pass; core app tests remain enabled.

## Parked research and reopening rule

The [parked research index](parked-recognition/README.md) records recovery refs,
retained locations, and key verdicts. Resume research only with a specific new
hypothesis, fixed inputs/acceptance criteria, a bounded budget, and a named
decision the experiment can resolve. Preserve failed results and stop when the
fixed criteria fail. Existing personal tests do not establish unseen-writer
accuracy, and the user's preference is to use their own writing for any further
handwriting evidence.

### Implemented recovery boundaries

- Located targets excluded by recognition's load limits now remain unread,
  manually editable placeholders. They bypass recognition, personalization and
  caches; the recognition limits themselves are unchanged.
- If a recognized chord grows into a review-only target, its expanded drawing
  replaces the stale visual stand-in rather than claiming the same ink twice.
- Review is bound to an exact draft/barline/layout snapshot. Rendering is a
  live-canvas, all-or-nothing transaction; changed or incomplete source coverage
  cannot render a neighbor first or clear the page.
- Local rewrite deletes only complete, uniquely owned original strokes. Shared
  bitmap fragments, duplicate owners and stale source fail safely. Back to Ink
  does not erase ink. Typed review edits are retained temporarily by exact ink
  source until rendering, whole-draft rewrite or discard.
- Unlocated ink does not receive invented chord placement. It remains on the
  canvas for erasure/rewrite; source coverage blocks unsafe rendering/clearing.
- My Handwriting remains reachable explicitly. Existing examples and saved
  opt-in choices are not reset. New profiles still default disabled; trained ML
  comparison resources are not part of the ordinary build.

### Candidate and verification receipts

- Candidate source version: **1.2.1 (61)**; reader identity
  `maximum-trust-v35-chord-only-scored-candidates-2026-10-05`.
- Verification directory: `/private/tmp/iChartNormalization-20261005.0BpXRb/`.
  Temporary build artifacts can expire; the checks are reproducible from source.
- Recovery gate: `RecoveryFinal.xcresult`, **38 passed, 0 failed, 0 skipped**.
  This precedes the last review-only placeholder change; the final full gate
  below includes that change.
- Final full iChart Simulator gate: `AppVerified.xcresult`, **2,069 passed,
  0 failed, 103 skipped** (2,172 total). Nonzero execution and results tree
  verified with `xcresulttool`; summary is `app-summary.json` and tree is
  `app-test-tree.json`. This includes the last review-only placeholder change.
- Final full SwiftPM gate: `swiftpm-verified.log`, **1,532 passed, 0 failed,
  89 skipped** (1,621 total), command exit 0.
- Skips are declared opt-in research/private-input, research-artifact and live
  Supabase checks. Those experiments/services were not certified by this pass.
- Content-free ingest contracts: **16 passed, 0 failed, 0 skipped** locally.
- Unsigned iOS Release build: **passed**, `Release.xcresult` / `release.log`.
  Artifact: `ReleaseDerivedData/Build/Products/Release-iphoneos/iChart.app`
  inside the verification directory. Its plist is **1.2.1 (61)** and executable
  is arm64. Resource scan found no `PersonalMLComparison`, RecognitionStudy,
  `.mlmodel`, `.mlmodelc` or `.mlpackage`. Code signing is explicitly absent.
- CI YAML parses; normal checks retain full SwiftPM/app tests and now include
  the bounded content-free telemetry contract suite. Remote CI and branch
  protection were not run/changed because this branch has not been pushed.
- No physical install/Pencil acceptance, production ingest deployment, GitHub
  push, TestFlight upload or publication has occurred in this normalization pass.

### Next bounded pass

Use this branch/worktree, not either parked tree. Once automated/build gates
pass, install candidate 61 and perform one workflow acceptance pass in each
style: write a mixed draft, edit a proposed chord and enter a missing one, go
back to ink and reopen review to check the edits, locally rewrite one target,
render, move/edit a rendered chord, rotate/change key, save/reopen and export.
Include a dense page and the existing repeat/setup-staff fixture. This is app
QA, not another handwriting-training protocol. Record actual defects and fix
them individually. Deploy the reviewed ingest allowlist separately before
expecting new trial metrics to arrive; verify a real delivery afterward.
