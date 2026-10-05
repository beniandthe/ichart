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

Normalization implementation is complete. Automated, Release-build and physical
installation results are recorded below. This is an actionable app-development baseline,
not approval to publish. A build or test count is not evidence of improved fresh
handwriting recognition. Signing, installation, Pencil interaction, upload, and
publication must each be recorded separately.

Build 61's later review-input, spacing and typed-header reports reopened the
bounded UI work below. Its prior acceptance receipts are not acceptance of
the new build 62 candidate.

## Preserved work and current evidence

| Item | Recorded status | Meaning for this release |
| --- | --- | --- |
| Chord-only reader/suggestion boundary | Implemented in retained research tree; documented build 57 installed and launched on 2026-10-03 | Keep the safety behavior; do not claim a new accuracy gain. |
| Full input retained for newly taught lessons | Implemented and tested in retained tree; prepared build 60 was not installed at that checkpoint | Keep storage fix and legacy compatibility; discarded legacy points cannot be recovered. |
| Before/After learning eligibility and internal candidate cleanup | Implemented and tested in retained tree | Retain maintenance fixes; workflow tests do not establish personalization benefit. |
| Experimental personalized ML | Recorded failed acceptance criteria | Park it; no weight promotion or automatic release dependency. |
| Normalization and recovery/telemetry work listed below | Implemented; automated gates, unsigned Release build, signed Debug iPad install/launch and user-reported short workflow passes completed | New telemetry delivery is verified; distribution and the remaining targeted release checks are separate. |

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
| 1 | Repair unread draft chords in review | User can type a valid intended chord for an unread target, navigate rows with a usable keyboard, and continue. Unsupported text remains unresolved. Exact remaining ink is preserved. | Implemented/tested; shared review flow accepted in both styles. A naturally unread target was not separately identified in the human report. |
| 1 | Rewrite only the selected chord | Rewriting one target preserves every unrelated pending chord and its ink; stale/ambiguous ownership is refused safely. Explicit whole-draft discard remains available with clear meaning. | Implemented/tested; user completed the short rewrite/review checklist in both styles without reporting a defect. Unsafe-ownership cases remain automated evidence. |
| 1 | One reliable write → review → repair → render flow | Both styles support mixed correct, uncertain, and unread drafts, cancellation, continued writing, and later editing. Rendering clears only ink covered by accepted objects. | Short workflow passes completed in both styles; saved rendered chords and both PDF exports verified. |
| 1 | Explicit optional handwriting learning | No forced setup on ordinary chart entry. Existing profiles/examples remain available. Saved preference and reset/opt-out behavior are explicit and tested. | Implemented; existing choices preserved |
| 1 | Define and enforce release reader behavior | Standard reader is the default. Example-based learning is a separately chosen setting; research comparisons and model packages do not silently participate in normal entry. | Verified; Release artifact contains no experimental model/Study resources |
| 2 | Count review repairs and preserve attribution | Batch review corrections emit content-free metrics; current recognition-version names retain correction attribution. No chord text, raw ink, or handwriting examples enter ordinary telemetry. | Production ingest v10 deployed with user approval; real build-61 review/render fields retained. Rewrite-event retention verified by an internal schema probe. |
| 2 | Measure preview responsiveness accurately | Record last PencilKit input callback → preview publication, separately from recognizer computation. This includes waiting/preparation, but is not a screen-pixel or Pencil-latency measurement. | Real build-61 input-to-preview field retained; short workflow accepted. Dense-page stress/visible-ink latency are not established by this sample. |
| 2 | Establish ordinary-use measures | Use the metric definitions below, keep internal testing separate where classification is available, and do not infer chord accuracy from preview-event counts. | Defined below |
| 3 | Validate release candidate in both styles | Complete the release gates below, recording artifact/version and observed result. No unresolved ink-loss or blocked-recovery defect is acceptable. | Automated/device short-workflow/export/telemetry gates complete. Remaining targeted regression checks, entitled cloud-backup QA and distribution mechanics are below. |

New recognizer changes enter this backlog only for a specific reproduced defect.
Keep the standard-reader comparison fixed, check new wrong reads as well as
recoveries, and preserve exact ink. Do not add broad model training, public-corpus
intake, additional writers, or repeated favorable-prompt testing to this pass.

## Bounded UI refinement before the remaining release gates

Candidate: **1.2.1 (62)**. These are reproduced workflow/layout changes, not a
recognition or learning iteration. Keep the standard-reader identity, profile,
saved source ink, and content-free telemetry behavior unchanged.

| Report | Change | Required acceptance |
| --- | --- | --- |
| Review scrolling activates handwriting; typing requires several controls | Typed-only shared fields in batch/single review, correction, header and cue text; large scrollable review; Pencil-enabled sheet scrolling; Next/Done; chart canvas input/focus suspended while a panel owns input | Runtime focus, review-draft and exact-ink preservation; physical Pencil scroll and actual keyboard dismissal/re-entry in both styles |
| Compact engraving fits only five systems | Separate Standard / Closer / Dense system spacing in Page settings. Standard is the legacy decoding/default; tighter choices keep staff/font/writing-lane sizes and reserve actual notation/cue clearance | More ordinary rows in shared editor/PDF layout; compatibility and source-byte preservation; visual check on the iPad |
| Typed header cuts off text accepted by the entry field | Complete-text fitting/wrapping in the shared header renderer, without changing handwritten-header storage | Actual preview/PDF output retains full title, credit and style-note endings; existing short text keeps its preferred size |

Private UI verification and before-install data backup:
`/private/tmp/iChartUIRefinement-20261005.75A99M/`.
The first runtime gate exposed remaining font-specific header clipping and an
invalid note-fixture assumption. Both were repaired before the final gate;
the failed receipts remain separate and are not counted as passing evidence.

- Full native Simulator gate: `AppFinal.xcresult`, **2,093 passed, 0 failed,
  103 skipped** (2,196 total). Nonzero execution and the results tree verified
  with `xcresulttool`; `app-summary.json` and `app-test-tree.json` are alongside
  the bundle. All 24 tests in the named typing/review/input-isolation/header/
  spacing classes passed, including their repeated style/font cases.
- Full SwiftPM gate: `swiftpm-final.log`, **1,542 passed, 0 failed, 89 skipped**
  (1,631 total), command exit 0. The separate Swift Testing footer has zero
  tests; the nonzero XCTest count above is the actual gate.
- Skips remain the explicit opt-in/private-input/research and live-service
  checks. These tests do not establish a recognition-accuracy gain.
- Actual full title/credit/style endings verified in renderer and exported PDF
  text. Inspected both styles' dense-page PDF raster images with chords, repeats
  and a below-row cue; also rendered the long Rhythm header PDF independently
  with Poppler and inspected its complete ending. Rendering checks cannot
  replace the physical keyboard/Pencil/palm acceptance below.
- Expected ordinary Compact first-page capacity at the tested width is Standard
  5, Closer 6, Dense 7. Extra notation/cue clearance can legitimately reduce
  capacity. Existing charts decode Standard; tighter spacing is opt-in through
  **chart title menu → System Spacing** and does not rewrite saved source ink
  or identities.
- Debug device build: `DeviceBuild.xcresult` / `device-build.log`, **passed**
  with ordinary Apple Development signing; strict deep signature verification
  passed. Bundle and installed-app query report **1.2.1 (62)**. Resource scan
  found no experimental comparison/Study/model packages. No signing prompt,
  credential-document access, provisioning update or keychain change was needed.
- Candidate 62 installed over the existing app and launched successfully on
  Ben's paired iPad. `install.json`, `installed-version.json`, and `launch.json`
  retain the receipts. Before-install and immediate after-install copies of all
  **22 Application Support files were byte-identical**, including 30 charts and
  the 70-example handwriting profile. Documents were also backed up.
- After first launch: all 30 charts remain; the profile is semantically
  unchanged with all 70 examples. One selected chart's existing page ink was
  reserialized (16 strokes, different encoded bytes). A local PencilKit decode
  comparison verified exact exposed point geometry/timing/size/opacity/force/
  angles, stroke transforms/masks, ink types/colors and creation times unchanged
  (`check-ink-preservation.swift` / `ink-preservation.log`). No profile was taught
  or reset, and there was no implicit switch to tighter system spacing.
- **Physical UI acceptance remains pending.** Check Pencil scrolling in review,
  direct typed focus/Next/Done and return to handwriting, full typed headers,
  and explicit Dense spacing on existing charts in both styles. Native focus
  tests cannot certify the iPad's visible software keyboard or palm experience.
  This is not a Release archive, TestFlight upload, GitHub push or publication.

### Mixed input and visible suggestions — build 63

Current device candidate: **1.2.1 (63)**. The user described 62 as "much better"
but reported that input fields could no longer use Scribble. The typed-only
bridge above was a regression, not the intended final input policy.

- Header, review/correction and cue fields now allow native Scribble starts
  inside their own bounds. Keyboard editing remains available; repeated Edit
  requests preserve text/selection, Next navigates, and Done ends editing
  without accepting/rendering. Header has one functional Keyboard action, not
  a per-row mode selector. Outside-field Pencil dragging scrolls the owned
  sheet; native finger scrolling remains unchanged. The owned Pencil pan is
  clamped vertical dragging without inertial fling. Native Scribble focus no
  longer triggers the app's animated review-row scroll.
- Preview and review use the same complete, valid available suggestion even
  when recognition requires confirmation. Suggestions are not trusted reads.
  Native confidence, trust, source-coverage and explicit-render requirements
  are unchanged. Illegal/mismatched candidate text is excluded; an invalid
  explicit edit cannot silently fall back to another chord.
- The chord preview no longer uses a question mark. **Zero valid evidence or
  unsafe stale ownership shows Add chord**, with direct repair/rewrite available;
  an arbitrary chord is not invented to fill the field. This is the bounded
  exception to the request for an always-present chord suggestion.
- Receipts and exact signed app: `/private/tmp/iChartMixedInput-20261005.J9bDOu/`.
  The first native run had one header-toolbar lookup failure. The harness was
  repaired to present a real sheet in a key scene window and search the owned
  window. The button/action assertions were retained; no app logic changed for
  that repair. Failed receipts are preserved separately.
- Full native `AppFinal.xcresult`: **2,102 passed, 0 failed, 103 skipped**
  (2,205 total), verified with `xcresulttool` summary and results tree. This
  preceded the final button-width-only adjustment. `FinalInput.xcresult` then
  passed **47 tests, no failures or skips** on the exact final app source;
  its actual rendered Header attachment was inspected and the Keyboard label
  fits on one line. These are UI/invariant checks, not fresh accuracy evidence.
- SwiftPM parallel runner exited 0 after dispatching 1,631 XCTest cases. Its
  parallel log does not enumerate skips separately; do not convert that count
  into a passed-test total or use the separate zero-test Swift Testing footer.
- `DeviceFinal.xcresult` passed with ordinary Development signing; the preserved
  `iChart.app` passed strict deep signature verification and reports 1.2.1/63.
  No experimental model/Study resources were found. Installed version and
  successful launch are recorded; no credential access or signing prompt was
  needed. Final app source hashes are alongside the receipts.
- The user confirmed intentionally cleaning up the older charts. All **18**
  current Application Support files were byte-identical immediately after
  installation. After launch, all **4 chart objects are exactly unchanged**,
  including stored ink; the **70-example profile is byte-identical**. No teaching,
  profile reset, chart restoration/deletion or billing-policy change occurred.
  Ordinary launch refresh changed only the three library entitlement fields
  (`activePlan`, subscription status and verification date) to free/expired,
  as previously observed. Keep cache state distinct from human-confirmed access.
  The user subsequently confirmed **Charts open normally** on build 63; no
  entitlement workaround was performed.
- **Physical acceptance is pending:** in an existing chart, Scribble a review
  entry, use Edit to type, Done, then Scribble again; scroll outside fields with
  Pencil or with a finger. Check Header Keyboard and cue entry as well. No Teach
  or full recognition score test is needed for this bounded UI change. GitHub
  push, distribution archive, TestFlight upload and production deployment were
  not part of this follow-up.

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
- GitHub push, TestFlight upload and publication have not occurred in this
  normalization pass. Later device QA and ingest deployment receipts are below.

### Physical candidate 61 delivery — 2026-10-05

- App source: `1bb6e93ef141a32892e587fd2eb740953136e402` on the active branch.
  The generated project was refreshed from committed `project.yml`; app source
  was unchanged from the automated gate. Existing results were not rerun or
  reinterpreted as device acceptance.
- Fresh Debug device build **passed**, including ordinary Apple Development
  signing. No provisioning update, keychain change or credential-document access
  was needed. Strict deep signature verification passed against the normal
  macOS trust store; the embedded profile includes the actual iPad UDID.
- Device: Ben’s iPad, iPad Air (4th generation), iOS 26.6.2; wired, paired,
  Developer Mode enabled. Candidate plist and installed-app query both report
  **1.2.1 (61)**. It replaced build 57 without uninstalling the app.
- Evidence directory: `/private/tmp/iChartCandidate61Device-20261005.lagerk/`.
  `DeviceBuild.xcresult`, `device-build.log`, `install.json`, `launch.json` and
  `installed-version.json` record build/install/launch. Development app path:
  `DerivedData/Build/Products/Debug-iphoneos/iChart.app` inside that directory.
  Comparison opt-in was `NO`; no experimental model/Study resources were found
  in the bundle. Compiler/deprecation warnings remain; this was not warning-free.
- Existing Documents and Application Support were privately copied before
  installation. All 20 Application Support files were byte-identical after
  installation, before launch. Documents also matched. First launch left all
  chart objects, projects, cloud metadata, deletion records, profile, evaluation
  journal, correction memory and stored PDFs unchanged. No ink/profile reset or
  teaching occurred.
- First launch changed only three library entitlement fields plus the performance
  trace. The saved plan changed from `studioSubscription` / `proActive` to
  `free` / `proExpired` during ordinary subscription refresh. The library still
  contains all 28 charts. Current Basic policy limits local charts to 3 and locks
  editing while over that limit. This snapshot prompted a chart-access check;
  it is not evidence of a persistent restriction. The user subsequently
  confirmed **"The chart opens normally"** on build 61. No entitlement workaround,
  purchase, chart deletion or billing-policy change was made. Keep that cache
  observation distinct from the current human-confirmed access result.
- Installation, launch and human-confirmed chart opening are complete. The
  subsequent short workflow/export acceptance is recorded below. A
  development-signed Debug app is not a distribution archive or TestFlight upload.

### Short workflow acceptance and telemetry — 2026-10-05

- The user replied **"both complete"** to the short Simple/Rhythm checklist:
  natural-speed writing, review editing, Back to Ink/reopen, local rewrite,
  rendering, rotation/key change and save/reopen. No defect was reported. This
  is user-reported workflow acceptance, not a labeled recognition study or
  an exhaustive claim about every earlier layout fixture.
- Private evidence directory:
  `/private/tmp/iChartCandidate61Acceptance-20261005.jTpe4S/`.
  `ApplicationSupport/` is a non-destructive device capture. All 28 prior chart
  objects remain semantically unchanged. Two new charts are saved: Simple has
  7 rendered chord objects, Rhythm has 6. These are storage counts, not supplied
  written-target counts or accuracy denominators.
- All **70 saved handwriting examples are unchanged**. Profile use remains
  enabled by the existing choice; review learning changed from on to off,
  with the corresponding profile revision. No new teaching/examples occurred.
- PDF export was initially not performed. After the separate export request,
  production received `pdf.export_succeeded` for each style and the device PDF
  library increased from 13 to 15 entries. Both new files are present, have a
  PDF header and match their manifest sizes: Simple **159,985 bytes / 1 page**;
  Rhythm **21,356 bytes / 1 page**. This verifies saved export artifacts, not a
  separately inspected print-layout proof. Files are in `AfterExports/`.
- The user explicitly approved deploying the content-free ingest update.
  `app-telemetry-ingest` on project `pausvvwoazbvmzyrebwl` is **ACTIVE v10**,
  deployed at **08:58 PDT**. Its three files match reviewed source exactly;
  `verify_jwt: false` and the existing custom client-key/user authentication
  behavior are unchanged. No schema, permission, key, billing or recognition
  change was made. The local ingest contract suite passed **16/16**.
- New ingest additions are `chord.preview_rewritten` and seven properties:
  `writing_batch_id`, `rewrite_outcome`, `reviewed_count`, `changed_chord_count`,
  `repaired_no_read_count`, `review_duration_ms`, `last_stroke_to_preview_ms`.
  Validation bounds UUIDs, outcomes, counts and durations. This does not add
  chord text, raw ink, chart identifiers or documents to ordinary telemetry.
- An explicitly labeled internal probe (`telemetry-v10-probe`,
  `backend-probe`, `flow: telemetry_schema_probe`) returned **202, stored 2,
  rejected 0**. A database read verified all added fields were retained and
  prohibited synthetic chord/title fields were absent. Exclude those probe
  events from real-device/customer usage; they are not app or accuracy evidence.
- After the user wrote/rendered one additional chord, production retained real
  **build-61 Simple** preview, confirmation and render events under one matching
  writing-batch ID. The render included reviewed count 1, changed count 0,
  repaired-no-read count 0 and review duration 920.672 ms; the preview included
  callback-to-preview time 662.528 ms. This proves actual client-to-storage
  field delivery, not handwriting accuracy or visible Pencil-ink latency. The
  original paired passes preceded v10; already acknowledged stripped fields
  cannot be reconstructed retroactively. Future customer builds containing this
  instrumentation can supply the fields; older distributed builds cannot.
- Rollback source is recoverable from **`b717073`**: the entrypoint,
  `_shared/telemetry_ingest.mjs` and `_shared/supabase_subscription_authority_store.mjs`
  were SHA-256 verified against the production-v9 files. A rollback redeploy
  creates a new version; do not change authentication settings. The additional
  private v9 bundle is at `/private/tmp/iChartTelemetryReadiness-20261005.OR8qH8/`.

### Next bounded release checks

Use this branch/worktree, not either parked tree. Do not restart an ML cycle or
repeat the completed short workflow without a named defect.

1. **Cloud backup/access QA:** the session recorded 15 `cloud.push_failed`
   events classified only as `sync_error`. Read-only account inspection found
   the test account's server-side StoreKit subscription is free/inactive,
   expired and outside grace; local QA access subsequently reports Pro. Cloud
   policy requires active server entitlement, so this test does not establish
   backup behavior for an entitled customer. Verify backup/restore with a
   legitimate active sandbox/test entitlement before calling the full trial
   ready. Do not fabricate entitlement rows, purchase, change RLS or delete
   charts to bypass this gate. No cloud/billing mutation was made in this pass.
2. **Remaining targeted regression checks:** cover dense-page visible Pencil
   responsiveness, the existing repeat/setup-staff fixture, header/text input,
   margins and form-marker sizing if not already exercised on this candidate.
   The broad historical list is not a request to retrain recognition. Preserve
   exact failing ink; fix only a reproduced defect. Naturally unread and unsafe
   ownership cases not encountered manually remain explicitly unexercised.
3. **Distribution:** review and authorize GitHub push/remote CI, prepare a
   distribution-signed Release archive, verify store/privacy metadata, then
   separately authorize upload/TestFlight delivery. Debug iPad acceptance is
   not an App Store signing, archive or upload receipt.
