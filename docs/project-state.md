# Project state and release backlog

Updated: 2026-10-09. This is the start-here document for the active app project.
Older sprint plans and recognition reports remain evidence, not an automatically
expanding work queue. Update this file when an item is implemented, verified, or
blocked; record the actual evidence before changing its status.

## Current closeout sequence — October 9

The user approved proceeding down this finite list. Do not restart recognition
research or expand it into a new app backlog.

1. **Privacy / telemetry:** the explicitly approved telemetry migration is now
   deployed. The daily 180-day cutoff and validated account-linked deletion rule
   are verified as configuration; no live purge or account deletion was run.
   The first actual Cron run, public policy and fresh App Privacy alignment
   remain open. The user approved retaining submitted support messages/reports
   only as needed for resolution/follow-up and honoring verified deletion
   requests except required legal/security records; the draft now includes it.
   Disclosure and manifest/help repairs pass 38 focused native tests and are now
   Development-signed, installed and normally launched as `1.2.1 (75)`. Saved
   charts/ink, PDFs, setlists/profile data and current access are preserved.
   See [the current closeout receipt](privacy-telemetry-release-closeout-2026-10-09.md).
2. **Short physical acceptance — passed, user-reported:** after the current
   `1.2.1 (75)` privacy delivery, the user reported **“Both passed”** for Simple
   and Rhythm. The checklist covered privacy/legal controls, keyboard/Scribble
   review and scrolling, render/save/reopen/PDF, and a small Free Ink rotation
   check. This closes that short checklist, not dense-page performance or general
   recognition accuracy; no new ML teaching or long recognition test was needed.
3. **Existing Apple purchase:** its next genuine boundary is October 10 at
   **8:42:40 AM PDT**. Verify the existing offer's actual signed free-period
   transaction and term; later paid renewal is a separate observation. Do not
   buy again or activate the public campaign to bypass this wait. Remaining
   new/returning/active-annual cohort checks stay explicit, not inferred.
4. **Final candidate — local gates passed:** inventory/source review, full
   native (2,374 passed / 103 skipped), SwiftPM (1,677 passed / 89 skipped),
   backend contracts and fresh unsigned Release artifact checks passed with
   zero test failures. Two native-only test guards and one disclosure assertion
   were repaired; CI now includes the offer/authority/account contracts. The
   inspected Release artifact remains `1.2.1 (75)`, with 13 warning diagnostics.
   See [the final candidate receipt](final-candidate-review-2026-10-09.md).
   Distribution signing/archive, commit, push/remote CI, upload, public policy
   publication and campaign activation remain separate authorized outcomes.

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

**Current authorization — October 8:** the user has lifted the build-75 hold
for building and installing an updated test app only. **1.2.1 (75)** is now
Development-signed, installed and launched, with the accepted privacy/cleanup
changes and handwriting setup/teaching/runtime personalization parked. Saved
chart content and ink, PDFs, setlist and profile data were preserved in the
before/after checks below. This is not authorization
for archive/export, upload, public release, policy publication or campaign
activation. Complimentary Pro is **one calendar month free, then automatic paid
renewal unless canceled**, following explicit Apple offer acceptance. New/expired
users use the introductory/promotional purchase path; the one known active
annual subscriber needs separate same-plan treatment. The app flow, signer and
campaign ledger are locally implemented. The delegated claim-window decision is
90 days beginning at public release; no absolute clock starts during cleanup.
Matching monthly/annual promotional definitions are now saved in Apple.
The approved signing key is protected in iChart's server secrets and verified;
the ledger and authenticated endpoint are deployed with the campaign off.
The separately approved Sandbox QA-owner guard is now deployed inactive.
On October 9, an explicit Sandbox override and single-owner allowlist were
staged for the current, verified Sandbox-only iChart account; all campaign dates
remain unconfigured and enabled remains false. Its backend and
inactive-live checks are recorded below. A later, bounded future-start status
check now passes through fresh owned Apple Sandbox history; the test was closed
with the campaign disabled and temporary dates removed. That earlier status
check did not establish offer acceptance, benefit fulfillment or renewal; the
later accepted/scheduled QA purchase is recorded immediately below.
Introductory dates and verified Apple fulfillment remain open.
**Latest QA outcome — October 9:** the accepted monthly Sandbox offer is now
confirmed as **scheduled** through a separately authorized, existing-purchase-only
recovery path. The ledger changed from prepared to scheduled at **19:44:25 UTC**;
its two existing attempts did not increase. Its verified start is **October 10,
15:42:40 UTC**; actual redeemed end remains null. The app received the matching
schedule, retained `studioSubscription` / `proActive`, and its matching local
pending marker cleared naturally after the acknowledgement repair at **19:50 UTC**.
The failed guard was the old pending validator's `FREE_TRIAL`-only assumption:
Apple's fresh signed renewal instead reports exact `PAY_UP_FRONT`, full `P1M`
and numeric zero. The pending-only economic rule does not relax completed
redemption verification or grant a gift entitlement.
The final focused gate passes **113 native tests and 469 server tests**, zero
failures/skips; the same **1.2.1 (75)** revision is signed, installed and launched.
Five charts/ink, 11 PDFs and setlist/profile/evaluation files remain unchanged.
Public campaign activation and new preparation/signing stayed disabled; both
temporary QA cutoffs and purchase-date secrets were removed after recovery.
Ordinary billing/signing configuration and the singleton Sandbox guard are
unchanged. No new purchase, public activation, push, archive or upload occurred.
Actual free-period redemption/renewal, new/returning-customer acceptance and
active annual same-plan behavior remain separate open gates. See the
[current recovery receipt](#access-recovery-and-pending-term-diagnosis--october-9);
the initial failure remains in its preceding historical acceptance receipt.

**Latest follow-up — October 9:** completed promotional confirmation now
accepts the exact configured product/offer, `P1M`, numeric actual transaction
`price:0`, and `FREE_TRIAL` or `PAY_UP_FRONT`. Introductory validation remains
`FREE_TRIAL` only. Actual dates must be finite numeric, in range and ordered;
pending renewal quotes/estimated ends cannot establish redemption. A native
prepared `nextBillingEvent` attempt can now accept a matching completed result
if billing occurs between status and confirmation. All campaign/product/offer/
attempt bindings remain required. The existing disabled QA recovery stays
scheduled-only; no recovery window was opened and no new purchase was started.
The focused local gate passes **115 native / 487 server tests**, zero failures
or skips, with the native nonzero count verified by `xcresulttool`. After separate
user approval, the backend fix is **deployed at endpoint version 38**, JWT
enforcement enabled; all 12 deployed files match the tested source and all six
other services' hashes/versions/JWT settings are unchanged. The native
billing-boundary revision is now **Development-signed, installed and normally
launched as 1.2.1 (75)**; signature/profile checks and the saved-content comparison
pass. Current Pro plan/status/expiry/auto-renew and selected chart are unchanged;
only backup/sync/verification timestamps and trace changed. Fresh
monthly/annual authenticated app responses report `campaign_disabled`, no attempt
and no signature; the iPad was then relaunched without diagnostic flags. A
fresh comparison preserves all 19 files' saved content: five charts/ink, 11 PDFs,
setlists and profile/evaluation data. Pro plan/status remain active; in the earlier
backend smoke, previously
missing expiry/auto-renew metadata was populated by verified refresh, so strict
entitlement/full-state identity did not pass and is not claimed. Device expiry
and auto-renew now match ordinary server authority. A current database read shows
ordinary active/auto-renewing Pro and the scheduled gift; the signed start is
**October 10 at 8:42:40 AM PDT**. No completed free-period transaction or paid
renewal is evidenced. See the
[scoped completion receipt](#completed-offer-and-billing-boundary-local-repair--october-9)
and [focused deployment receipt](#completed-offer-focused-inactive-deployment--october-9),
then the [native delivery receipt](#completed-offer-native-delivery--october-9),
before resuming.

The current privacy, cleanup and handwriting-parking changes are newer than the
physically accepted and distribution-archived build-74 source; those older
receipts do not validate the modified app. Build 75 has fresh focused native,
artifact, installation and startup checks plus the October 9 user-reported short
physical checklist in both styles. This is not a renewed full stress assessment,
Apple offer fulfillment or distribution approval. Start with the
[build-75 test receipt](#build-75-test-build-and-install-receipt--october-8)
and [current cleanup decisions](#pre-build-75-cleanup-and-decisions--2026-10-07)
below, not the historical outstanding-item lists.

Build 61's later review-input, spacing and typed-header reports reopened the
bounded UI work below. Its prior acceptance receipts are not acceptance of
the new build 62 candidate.

## Preserved work and current evidence

| Priority | Deliverable | Acceptance check | Status |
| --- | --- | --- | --- |
| Chord-only reader/suggestion boundary | Implemented in retained research tree; documented build 57 installed and launched on 2026-10-03 | Keep the safety behavior; do not claim a new accuracy gain. |
| Full input retained for newly taught lessons | Implemented and tested in retained tree; prepared build 60 was not installed at that checkpoint | Keep storage fix and legacy compatibility; discarded legacy points cannot be recovered. |
| Before/After learning eligibility and internal candidate cleanup | Implemented and tested in retained tree | Retain maintenance fixes; workflow tests do not establish personalization benefit. |
| Experimental personalized ML | Recorded failed acceptance criteria | Park it; no weight promotion or automatic release dependency. |
| Handwriting setup, teaching, evaluation and runtime personalization | User approved parking on October 8; app source gated off and focused native gate passed | Saved examples/preferences/journals and dormant code retained. Ordinary Write & Render and manual corrections remain; no fresh accuracy claim. |
| Normalization and recovery/telemetry work listed below | Implemented; build-74 physical workflow, bounded cloud recovery and local distribution archive/export passed in the later dated receipts | No upload/publication approval. New privacy source is not covered by the old frozen build-74 acceptance. |

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
| 1 | Park handwriting learning for the next candidate | No setup/teaching/evaluation UI or runtime personalization on ordinary chart entry. Saved profiles/examples/preferences/journals and research code are preserved. | Implemented October 8; build 75 installed/launched with 70 saved examples byte-unchanged. Default-session profile/evaluation bypass is tested. Human UI acceptance remains separate. |
| 1 | Define and enforce release reader behavior | Standard reader only for ordinary entry while learning is parked. Existing personal profiles and correction-memory rules do not silently influence later reads. | Central product policy is false in Debug and Release; build-75 focused policy gate passed and actual Debug device artifact excludes experimental model packages. Release artifact exclusion must be refreshed with the distribution candidate. |
| 2 | Count review repairs and preserve attribution | Batch review corrections emit content-free metrics; current recognition-version names retain correction attribution. No chord text, raw ink, or handwriting examples enter ordinary telemetry. | Production ingest v10 deployed with user approval; real build-61 review/render fields retained. Rewrite-event retention verified by an internal schema probe. |
| 2 | Measure preview responsiveness accurately | Record last PencilKit input callback → preview publication, separately from recognizer computation. This includes waiting/preparation, but is not a screen-pixel or Pencil-latency measurement. | Real build-61 input-to-preview field retained; short workflow accepted. Dense-page stress/visible-ink latency are not established by this sample. |
| 2 | Establish ordinary-use measures | Use the metric definitions below, keep internal testing separate where classification is available, and do not infer chord accuracy from preview-event counts. | Defined below |
| 3 | Validate release candidate in both styles | Complete the release gates below, recording artifact/version and observed result. No unresolved ink-loss or blocked-recovery defect is acceptable. | Historical build-74 physical workflow, bounded cloud recovery and local archive/export passed. Build 75 passes focused tests, signed-artifact checks, install/launch and saved-content preservation; the user reported both short physical passes successful October 9. Apple offer/lifecycle, privacy publication and fresh distribution checks remain; no distribution approval. |

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

Prior device candidate: **1.2.1 (63)**. The user described 62 as "much better"
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

### Direct mixed input, batch deletion and PDF setlists — build 64

Build-64 device candidate: **1.2.1 (64)**, superseded by the small build-65 cleanup
below. This is a bounded input/library update,
not a recognition or learning change.

- Shared header, review/correction, cue and library/setlist naming inputs retain
  native Scribble and have one embedded 44-point keyboard action. Separate
  Header Keyboard and review Edit actions are removed. Finger/pointer taps and
  the embedded action request keyboard intent as well as focus; accepted
  Scribble restores Pencil intent. Next/Done, draft preservation and sheet/canvas
  input isolation remain. Apple's input hint is not an unconditional software
  keyboard command: the visible one-tap transition still needs physical QA.
- Charts and PDFs support Select, multiple selection, Select All and confirmed
  batch deletion. Individual PDF deletion also requires confirmation. Targets
  are an immutable snapshot. Chart save errors are surfaced, including delayed
  failures. PDF deletion stages exact files and commits the manifest atomically;
  failed or unreadable recovery preserves retained copies and reports an error.
- The Setlists tab supports named local sets, adding PDFs from the PDF Library,
  repeated songs, reordering, rename, remove and confirmed setlist deletion.
  Perform opens a full-screen PDF reader with Previous/Next Song. Removing a
  song or setlist never deletes its source PDF. Deleted/unavailable PDF entries
  keep their place and can be skipped. Existing PDF access rules remain; no new
  subscription gate, cloud setlist sync or combined-PDF export was added.
- Setlist workspace headers/actions are in-content controls, separate from the
  Library's hidden navigation bar. Earlier native runs exposed real missing
  navigation controls and undersized keyboard targets, plus test presentation/
  lookup issues. Those failed receipts are retained separately; they are not
  counted as passing evidence.
- Receipts and preserved signed app:
  `/private/tmp/iChartLibraryFlow-20261005.2IenNo/`.
  Final full native `AppFinal.xcresult`: **2,150 passed, 0 failed, 103 skipped**
  (2,253 total), verified with `xcresulttool` summary and test tree. Targeted
  input and setlist gates also passed 12 and 8 tests respectively; actual
  rendered setlist root/detail and settled unavailable-reader screenshots were
  inspected. `store-final.log` records **97 passed, 0 failed** targeted SwiftPM
  chart/PDF/setlist/confirmation tests. Synthetic deletion tests did not touch
  the user's library. These gates do not establish a recognition-accuracy gain.
- `DeviceFinal.xcresult` built with ordinary Development signing. The preserved
  app passed strict deep signature verification and reports 1.2.1/64. Installed
  version and successful launch on Ben's paired iPad are recorded. No credential
  access, signing prompt, provisioning update or keychain change was needed.
  No experimental comparison/Study/model resources were found in the app.
- Fresh before-install and immediate after-install copies of all **18**
  Application Support files were byte-identical. After launch, all **4 chart
  objects**, including stored ink, projects, deletion records and cloud metadata
  are unchanged; all **11 PDFs** and their manifest and the **70-example profile**
  are byte-identical. Ordinary launch refreshed entitlements and cleared the
  selected-chart pointer; the performance trace also advanced. No chart/PDF
  deletion, restoration or teaching was performed.
- **Short physical feedback:** the user reports the setlist works great and the
  Keyboard/Scribble path works well now, while explicitly requesting more
  thorough input testing. Do not turn this into exhaustive acceptance. Longer
  mixed-input review/Header/cue checks and batch-delete/Cancel acceptance remain
  pending. Use throwaway items for any actual deletion test. No GitHub push,
  distribution upload or production deployment was performed in this pass.

### Centralized setlist controls — build 65

Current installed device candidate: **1.2.1 (65)**.

- Removed the redundant Perform/play footer. Tapping a PDF row still opens the
  full-screen reader; its Previous/Next behavior is unchanged. Add PDFs now sits
  in the top row alongside Back, the title, Edit and options. The empty-state
  duplicate Add action was removed. No input, recognition, persistence or billing
  policy was changed by this cleanup.
- Receipt directory and preserved signed app:
  `/private/tmp/iChartSetlistCleanup-20261005.SNm0W3/`.
  Focused `SetlistHeader.xcresult`: **10 passed, 0 failed, 0 skipped**, verified
  in the native result summary and test tree. The mounted-view test verifies
  one top-band Add PDFs action, no Perform button and 44-point targets; the
  exported detail screenshot was inspected. This focused gate supplements,
  rather than replaces, build 64's full-suite receipt above.
- `DeviceFinal.xcresult` records a successful Development Debug build. The
  preserved artifact passed strict deep signature verification; installation,
  launch and device-reported 1.2.1/65 are recorded. This is not a distribution
  archive or upload.
- All **19 Application Support files** were byte-identical immediately after
  installation. After launch, all **4 chart objects** and stored ink, projects,
  deletion records and cloud metadata are semantically unchanged. All **11 PDFs**,
  their manifest, the **1 saved setlist** and the **70-example handwriting profile**
  are byte-identical. Only the entitlement object and performance trace changed
  during normal launch. No user data was deleted, restored or taught.
- Free-access/subscription options were discussed only. No offer, entitlement,
  price, production configuration or billing change was made. The remaining
  release gates below stay open.

### Display-only dark documents and readable dense measures — build 66

- Historical receipt: the user rejected this build's content-driven measure
  widening and disproportionate bars. The build-67 fixed-width policy below
  supersedes that density strategy; the dark-document changes are retained.
- The one-month free-Pro proposal and final release gates are parked in the
  final pre-push queue below. No billing, offer, entitlement-policy, production
  deployment, commit or push was performed in this pass.
- Setlist workspace/detail, naming, PDF picker and performance-reader chrome
  follow the saved Home appearance choice, including when system appearance
  differs. The reader's owning modal receives native appearance updates; the
  presenting controller and window root are not changed. The existing top
  Add PDFs action and row-to-open flow remain intact; no Play footer returns.
- Both chart styles and the shared PDF preview/reader use a display-only
  luminance inversion with hue compensation. Native canvas/PDF identity,
  PencilKit drawing bytes and tool properties are retained across mode changes.
  Exported and stored PDF colors/bytes are not changed by dark viewing. Existing
  PDFs need re-exporting to receive new chord layout; this is not a file rewrite.
- Read-only device capture identified four rendered chords in the current
  Simple measure: B7, G△7, A-9 and D-7. Its close A/D anchors and D-7's saved
  18-point display width were reproduced with the exact lane fractions, timing
  and manual measure widths. The 18-point resize's provenance was not established.
- Content-derived width floors and whole-measure collision fitting allocate
  usable chord space in both styles. Font size is reduced proportionally before
  horizontal compression. Saved chord values, timing, snap targets, manual
  layout metadata and ink are not rewritten. Readable manual row proportions
  remain respected. Reachable pitch spellings reserve stable content width for
  transposition; key-signature gutter changes remain a separate layout concern.
- A row with more total content than available paper width can still fall below
  the fitting readability floor. This pass does not add automatic row wrapping
  or claim arbitrary density will always fit.
- Receipt: `/private/tmp/iChartDarkDense-20261005.iC1Iy9/`.
  `TargetedInitial.xcresult` recorded 424 passed, 2 failed and 2 skipped: existing
  Join Row and Move to Row Below equalization tests caught a regression. The
  source was repaired without weakening those tests. `TargetedFinal.xcresult`
  then passed 428 tests with 0 failures and 2 skips. Visual inspection found a
  remaining live reader-toolbar contrast issue. Its native-modal fix was retained;
  `TargetedToolbarFinal.xcresult` exposed a test lookup failure before the first
  screenshot, with gesture teardown masking the lookup error. A test-only native
  accessibility/frame lookup correction preserved the contrast requirements;
  `ReaderRetest.xcresult` executed and passed the single affected test.
- **Final targeted native gate:** `FinalGate.xcresult` executed **428 passed,
  0 failed, 2 skipped / 430 total**. The skips are the two optional saved-device
  ink/key replay tests requiring explicit snapshot environment variables, not
  silently successful tests. Coverage includes actual PencilKit/PDF pixel and
  identity checks, live reader/preview navigation and toolbar contrast, layout,
  row movement, mixed text input, review input, chord edit geometry and PDF export.
  Six-font/two-width fitting fixtures and complex chords in both styles passed.
  Native PDF proofs and Poppler-rendered Broadway/Petaluma four-chord pages were
  visually inspected. These results do not substitute for physical Pencil UX.
- `DeviceToolbarFinal.xcresult` built the normal Development Debug app with
  comparison opt-in off. The separate preserved final artifact passed strict
  deep signature verification, installed over the existing app and launched.
  Device info reports **1.2.1/66**. This is not a distribution archive or upload.
- All **19 Application Support files** were byte-identical immediately after
  install. After launch, all **5 chart objects** and their stored ink, projects,
  **49 deletion records**, cloud metadata, **11 PDFs** and their manifest,
  **1 saved setlist** and the **70-example handwriting profile** were preserved.
  Only entitlements, the performance trace and the selected-chart pointer
  changed; selection was cleared, not a chart deleted. Chart-open access on this
  build and live dark/dense-measure acceptance still need user confirmation.

### Fixed-width chord fitting and precise measure resizing — build 67

- Chord text no longer drives measure width in either Simple Chord Sheet or
  Rhythm Section Sheet. Simple implicit bars have equal weight; explicit manual
  proportions remain proportional. Adding/removing chords leaves measure,
  staff and barline geometry equal to the chordless baseline.
- Crowded automatic chords share a proportionally reduced font size within
  their measure. Roots, suffixes, slash bass and token gaps scale together;
  horizontal text scale stays exactly 1. Editor and PDF export share the same
  selected-font fitting path, with a bounded 1,024-entry metrics cache. The
  12-point diagnostic threshold is not a width floor or a false promise that
  arbitrary chord density will always remain readable.
- Simple multi-chord fitting retains committed guide/overflow slot starts,
  including manually moved beat-four positions after save/reopen. Rhythm keeps
  its established 10-point visual gap when there is physically enough space.
  Recognition and stored chord timing/position/ink are not changed by fitting.
- Fine measure resizing starts as a continuous edit when already on or near an
  even boundary. The automatic even-row snap requires an approach from more
  than 6 screen points away into a narrow 2-screen-point zone. Distances follow
  zoom; the commit dead zone is 0.1 screen point. Explicit Even Row remains.
- Fractional drags in both directions survive JSON save/reopen and redraw in
  both styles, including compressed rows. Rhythm precision edits may normalize
  the row's stored manual widths to its current displayed baseline so exiting
  responsive Even Row does not move untouched bars. This is layout metadata
  normalization, not a change to content or ink. The existing 96-point model
  minimum remains: a bar already at that minimum cannot shrink further.
- The user explicitly authorized resetting current D−7 to automatic sizing.
  With the app confirmed stopped, only chord
  `2D34B58B-2A86-46C4-B69B-0613C73D44E4` in chart
  `4F756CF6-E658-42E1-AF3B-2D9560B15F0E` had its saved
  `manualDisplayWidth: 18` override removed. The original is backed up. Exact
  semantic comparison confirms all other chart fields, including source ink,
  timing and lane fractions, are unchanged. Original D18 manual-size behavior
  and the automatic-reset case are separately covered in the native tests.
- Receipt: `/private/tmp/iChartTextFitPrecision-20261005.Kwb8EY/`.
  The first two attempts failed compilation on ambiguous numeric/point
  expressions; those were repaired and are not test passes. The first executed
  gate (`TargetedCompiled.xcresult`) recorded **431 passed, 4 failed, 2 skipped /
  437 total**. Existing Simple anchoring and Rhythm gap requirements caught the
  regressions; source was repaired without weakening those expectations.
- **Final targeted native gate:** `FinalGate.xcresult` reports **436 passed,
  0 failed, 2 skipped / 438 total**. The two skips remain optional saved-device
  page-ink/key replay cases requiring explicit snapshot environment variables.
  Coverage includes layout, proportional rendering across six fonts/two widths,
  precise resize persistence, row movement, chord editing, PDF export, dark
  documents/readers and mixed review/header text input. Native automatic-size
  Broadway/Petaluma PDF proofs and a complex Rhythm proof were rendered with
  Poppler and visually inspected. Physical Pencil feel is not proved by tests.
- `DeviceFinal.xcresult` built the normal Development Debug app with comparison
  opt-in off. The preserved final artifact passed strict deep signature
  verification, installed and launched. Device info confirms **1.2.1/67**.
  This is not a distribution archive, upload, commit or push.
- All **19 Application Support files** were byte-identical after installation.
  After the authorized reset and launch, all other content in **5 charts**,
  stored ink, projects, **49 deletion records**, cloud metadata, **11 PDFs**,
  their manifest, **1 setlist** and the **70-example profile** remained unchanged.
  Only the authorized chord-width field, normal entitlement/performance state
  and the cleared selected-chart pointer changed. No chart or PDF was deleted.
- The user reported "that works" after build 67, then requested the same fine
  adjustment for chord placement. This is bounded user acceptance of that pass,
  not completion of every remaining release gate. The free-month offer and final
  release gates stay parked; no billing or production changes were made.

### Fine chord placement with deliberate snapping — build 68

- Both Simple Chord Sheet and Rhythm Section Sheet now allow continuous visual
  chord placement within a measure. A drag beginning on or near a grid line can
  make a small off-grid nudge without being pulled back to the starting guide.
  Snapping requires approaching a guide from more than 6 screen points away
  into its narrow 2-screen-point zone. The distances follow zoom, and meaningful
  movement begins at 0.1 screen point. No additional mode, toggle or button.
- Drag updates use the frozen initial frame rather than the previous snapped
  frame. Commit uses the exact cached preview target, avoiding an additional
  broad snap at release. Existing cross-measure targeting remains available.
- The optional saved `manualVisualLaneFraction` is separate from musical
  placement. Unsnapped same-measure nudges leave chord timing, event order,
  rhythm-map association, source ink and page ink unchanged. Deliberate grid
  snaps and cross-measure moves retain their existing musical-placement path.
  Legacy musical moves clear stale visual overrides. Old charts decode without
  the field, and untouched chords retain build 67 geometry.
- Explicit visual anchors survive save/reopen and share editor/PDF placement.
  Repeat/meter setup space and the right edge bound the drag. Neighbor labels
  fit their remaining text budgets without widening measures or relocating
  authored anchors. Exact coincident user-authored anchors are not automatically
  separated and are not promised to remain readable at arbitrary density.
- Receipt: `/private/tmp/iChartChordPlacementPrecision-20261005.Rhw1Jy/`.
  `Targeted.xcresult` confirms **618 passed, 0 failed, 2 skipped / 620 total**.
  The skips are the two optional saved-device page-ink/key replay cases requiring
  explicit snapshot environment variables. Coverage includes fractional nudges,
  weak-snap entry/escape, zoom, preview/commit equality, mapped Rhythm chords,
  persistence, bounds, legacy behavior and the accepted measure-resize tests.
- Four native PDF proofs cover both chart styles with Finale Broadway and
  Petaluma. Exported label bounds were checked against persisted layout; Simple
  Broadway and Rhythm Petaluma pages were rendered with Poppler and visually
  inspected. This proves bounded placement/export behavior, not physical Pencil
  feel or recognition accuracy. Recognition was not changed.
- `Device.xcresult` reports a successful normal Development Debug build, zero
  errors and seven warnings outside this placement change. Comparison opt-in
  remains off. The preserved artifact passed strict deep signature verification,
  installed and launched; device info confirms **1.2.1/68**. This is not an
  archive, upload, commit or push.
- All **19 Application Support files** were byte-identical after installation.
  After launch, all content in **5 charts**, saved ink, **49 deletion records**,
  cloud metadata, **11 PDFs**, their manifest, **1 setlist** and the **70-example
  profile** remained unchanged. Only normal entitlement/performance state,
  cleared selected-chart pointer and a newly created telemetry queue changed.
  No chart or PDF was deleted or rewritten. The user subsequently accepted the
  fine chord placement, then requested user-controlled proportional sizing.
  The free-month offer and final gates remain parked.

### User-controlled proportional chord sizing — build 69

- This deliberately supersedes build 67's crowd-driven automatic chord fitting.
  Chords retain their configured size unless the user resizes them. Dense or
  coincident labels may overlap: manual placement and sizing resolve that,
  rather than widening measures or shrinking the whole measure's chord cohort.
- The existing trailing resize handle now scales the entire chord: root,
  suffix, slash bass, token gaps, width and height together. It keeps the visual
  left edge and vertical center fixed. The visible selection box follows that
  size rather than retaining a fixed height or 18-point width floor; interaction
  controls remain finger-sized. The original size is no longer the maximum.
- Optional `manualDisplayScale` persists the explicit user choice independently
  of musical timing and fine visual placement. Its finite safety range is
  0.1–32 times the default. A legacy saved `manualDisplayWidth` remains stored
  and is interpreted as explicit proportional sizing without a migration.
  Only a new explicit resize replaces that old width with scale plus the exact
  visual anchor. No existing chart is rewritten simply by opening it.
- Sizing-neutral anchor planning prevents resizing one chord from moving or
  resizing its neighbors. Measure, staff, barline, rhythm and saved-ink geometry
  remain separate. Closer/Dense pagination reserves natural chord bounds, so
  a user size edit does not repaginate the chart or shift other systems. Default
  measured Rhythm glyphs retain 0.5-point staff clearance without reducing their
  configured font; explicit enlargement keeps the same center. Header and
  roadmap fitting and recognition are unchanged.
- Receipt: `/private/tmp/iChartManualChordSizing-20261005.El5GkG/`.
  The first executed gate (`Targeted.xcresult`) reports **625 passed, 3 failed,
  2 skipped / 630 total**. Two obsolete width/non-overlap expectations were
  replaced with exact chosen-size geometry and complete isolated native-PDF
  chord checks; overlapping full-page PDF text interleaves tokens and is not
  represented as legible. A real default-font staff-clearance issue was fixed
  without shrinking text or changing staff geometry.
- The next gate (`FinalGate.xcresult`) reports **628 passed, 2 failed, 2 skipped /
  632 total**. The added pagination test compared regenerated layout UUIDs rather
  than persistent measure membership; that fixture was corrected while keeping
  all system/page/measure/staff/ink checks. A header-input fixture failed its
  key-window setup assertion after asynchronous sheet presentation; setup now
  re-requests the test window once, waits for activation and verifies sheet
  ownership, retaining all keyboard/Scribble/navigation/draft assertions. No app
  keyboard source was changed, and this is not claimed as an app keyboard fix.
- **Final native gate:** `VerifiedGate.xcresult` reports **630 passed, 0 failed,
  2 skipped / 632 total**. The skips remain the optional saved-device page-ink/
  key replay cases requiring explicit snapshot environment variables. Fractional
  size/placement, preview/commit/reopen, old-width conversion, neighboring chord
  geometry, all three system densities, pagination, ink, measure resizing and
  mixed keyboard/Scribble tests are included. The prior failed gates remain
  separate evidence, not passing counts.
- Four native manual-size PDF proofs cover both styles/Broadway/Petaluma at
  0.5/1/1.6 scales with pixel width/height and actual root/suffix/bass PDF-font
  checks. Simple Broadway and Rhythm Petaluma proofs were rendered with Poppler
  and visually inspected. This is export/geometry evidence, not Pencil feel or
  recognition accuracy.
- `DeviceFinal.xcresult` built the normal Development Debug app with zero errors
  and seven existing unrelated warnings. Comparison opt-in is off. The preserved
  final artifact passed strict deep signature verification, installed and
  launched; device info confirms **1.2.1/69**. The earlier pre-clearance artifact
  was not installed. This is not a distribution archive or upload.
- All **19 Application Support files** were byte-identical after installation.
  After launch, all content in **5 charts**, saved ink, **49 deletion records**,
  cloud metadata, **11 PDFs**, their manifest, **1 setlist** and the **70-example
  profile** remained unchanged. Only normal entitlement/performance state and
  the cleared selected-chart pointer changed. No chart/PDF was deleted, no
  existing size override was migrated and no lesson was taught.
- The user accepted the interaction as very close, then clarified that resizing
  must change width only while all chord heights stay fixed. Build 70 supersedes
  this proportional-sizing behavior; the build 69 receipts remain historical.
  The free-month offer and remaining final release gates stay parked.
  This pass does not authorize a commit, push, production or billing change.

### Manual width-only chord compression — build 70

- The existing trailing handle now controls horizontal compression only in
  Simple and Rhythm. Default font sizes, natural height, top edge and saved
  left anchor stay fixed; root, suffix, slash bass, symbol paths and gaps receive
  the same x-only drawing transform. Chords no longer grow or shrink vertically.
- The explicit range is **35%–100% of natural width**: 100% is minimum
  compression and 35% is maximum compression. There is no stretch beyond the
  natural width and no automatic shrinking to fit neighboring chords. Extremely
  crowded or coincident labels still require deliberate placement/compression;
  the minimum is a safety bound, not a claim of universal readability.
- Optional `manualHorizontalScale` stores a new explicit width choice.
  Existing build 69 scale and older width values remain stored and are interpreted
  as bounded horizontal compression at default height without a migration. Only
  an explicit edit replaces those older fields. Compression does not change
  musical timing, neighboring chord anchors, measure/staff/ink geometry, system
  membership or pagination. Fine placement and measure resizing remain intact.
- Receipt: `/private/tmp/iChartChordCompression-20261005.Xw4q4Y/`.
  The first native gate, `Targeted.xcresult`, reports **631 passed, 2 failed,
  2 skipped / 635 total**. The failures are in new native-PDF typography checks:
  PDFKit's attributed-font point size averages the horizontal and vertical
  transform, so an x-only 35% scale reports 67.5% of the fixed font size.
  The raw PDF operator check and pixel-height checks pass. Vector music symbols
  are PDF paths and are not represented by extracted text; their visible/path
  verification is separate. App source is not changed to satisfy these probes.
- **Final native gate:** `VerifiedGate.xcresult` reports **633 passed, 0 failed,
  2 skipped / 635 total**. The two skips are optional saved-device page-ink/key
  replays requiring explicit snapshot environment variables. Preview/commit/
  reopen parity, old-value compatibility, constant height, fine placement,
  neighboring geometry, all system densities, pagination, ink and existing
  keyboard/Scribble workflows are included. The failed initial gate remains
  separate evidence. Only test methodology changed between these runs.
- Four native PDF proofs cover Simple/Rhythm and Broadway/Petaluma at
  35%/65%/100% widths. Independent x/y operator assertions retain every expected
  root/suffix/bass vertical font size, while rendered bounds keep constant height.
  Vector symbol paths and all extractable chord text are checked. Poppler renders
  of Simple Broadway and Rhythm Petaluma were visually inspected under the PDF
  verification workflow. This is export/geometry evidence, not Pencil feel or
  recognition accuracy.
- `Device.xcresult` built the normal Development Debug app with zero errors and
  seven existing unrelated warnings. Comparison opt-in is off. The preserved
  app passed strict deep signature verification, installed and launched; device
  info confirms **1.2.1/70**. This is not a distribution archive, upload, commit
  or push.
- All **19 Application Support files** were byte-identical after installation.
  After launch, all content in **5 charts**, saved ink, **49 deletion records**,
  cloud metadata, **11 PDFs**, their manifest, **1 setlist** and the **70-example
  profile** remained unchanged. Only normal entitlement/performance state and
  the cleared selected-chart pointer changed. No saved override was migrated,
  no chart/PDF was deleted and no lesson was taught.
- The user subsequently accepted the fixed-height compression interaction.
  The free-month offer and final release gates remain parked. No recognition,
  profile-learning, production or billing change is included.

### Purpose-specific writing tool names — build 71

- The shared main writing tool is now **Write & Render**, not Chords. It covers
  currently supported handwritten chords and lane barlines without narrowing the
  name to one notation type or promising unsupported future notation. The
  secondary annotation tool is now **Free Ink**, not Ink: its notes and marks
  remain handwriting and are not converted to chart notation.
- Toolbar and active-tool titles use the same mode metadata in Simple and
  Rhythm. Tool instructions, accessibility hints, Quick Start, How To, rhythm
  fallback guidance and existing handwriting-test instructions use the new
  names. Review's **Back to Writing** action returns to the existing structured
  writing mode, not Free Ink. Render Chords, Confirm Chords, chord counts and
  ink rewrite actions retain their accurate domain/action labels.
- This is a copy/accessibility update only. Input routing, recognition, persisted
  enum/data keys, telemetry IDs, primary destination order, five-control limit,
  keyboard/Scribble, fine placement and width-only compression are unchanged.
- Receipt: `/private/tmp/iChartWritingToolNames-20261005.LNhXgN/`.
  `Targeted.xcresult` reports **262 passed, 0 failed, 2 skipped / 264 total**
  across editor command layout, interaction modes, project/tutorial configuration
  and native chord-review input. The skips are optional saved-device page-ink/key
  replays requiring snapshot environment variables. A new naming/routing test
  also checks unchanged recognition-vs-annotation input eligibility, telemetry
  IDs, destinations and five-control count.
- `Device.xcresult` built the normal Development Debug app with zero errors and
  seven existing unrelated warnings. Comparison opt-in is off; the preserved app
  passed strict deep signature verification, installed and launched. Device info
  confirms **1.2.1/71**; this is not a distribution archive or upload.
- All **19 Application Support files** were byte-identical after installation.
  After launch, all **5 charts** and saved ink, **49 deletion records**, cloud
  metadata, **11 PDFs** and manifest, **1 setlist**, and the **70-example profile**
  remained unchanged. Only normal entitlement/performance state and the cleared
  selected-chart pointer changed. The free-month offer and final release gates
  remain parked; no production, billing, learning, commit or push is included.

### Review and selected-chord polish — build 72

- Shared Simple/Rhythm review now shows live empty/unsupported-entry feedback
  and a remaining count. This explains existing eligibility rather than adding
  a new gate: unread ink can still enter review; the final render still requires
  each row to match a supported chord. Exact draft text remains available for
  correction. Committed-chord correction keeps its existing nonempty-text rule.
- Quick Start, the in-editor tour and How To now name the conditional
  **Render Chords / Review & Render** actions, editing or suggestions in review,
  and local rewriting as another option. Review is not forced for every draft.
- Selecting a chord exposes a compact movement/right-handle width hint.
  **Reset Width** appears only for a saved sizing override and restores natural
  100% width at the same height. Fine placement and musical timing remain intact.
  For legacy structured width boxes without a fine-placement anchor, reset first
  records the existing visible left edge using the current page geometry, then
  clears sizing; reopening preserves that edge. No reset occurs merely by
  selecting or reading a chord.
- **Clear Draft Ink** replaces Discard. Nonempty pending chord/barline ink
  requires confirmation, with Cancel available and a captured chart-ID guard.
  The request itself does not mutate ink. Only confirmation invokes the existing
  clear handler; rendered notation and Free Ink remain outside its scope.
- Receipt: `/private/tmp/iChartEditorPolish-20261005.UcMl9L/`.
  Final frozen-source `FinalGate.xcresult`: **439 passed, 0 failed, 2 skipped /
  441 total**, verified with `xcresulttool`. Eight targeted native classes cover
  live review/keyboard input, unchanged unread-draft eligibility, source wiring,
  help configuration, width reset in both styles/fonts, preserved ink/model
  fields, exact placement and JSON reopen. The two skips are optional saved-device
  page-ink/key replays; this is not a new recognition-accuracy study.
- Two initial compile attempts hit the editor's SwiftUI type-check complexity
  limit. The new confirmation was isolated from the existing large modifier
  expression. The intermediate native gate then recorded **437 passed, 1 failed,
  2 skipped**: a new test incorrectly expected a native single-line text field
  to retain an injected newline. Its live fixture now uses actual spaces and
  checks exact field/callback preservation; pure validation still checks newline
  trimming. No input policy was changed for that test repair. The intermediate
  device artifact was not installed. Final source hashes are retained.
- `DeviceDelivery.xcresult` succeeded with zero errors and one reported existing
  deprecation warning. The exact preserved Development Debug artifact passed
  strict deep signature verification, installed and launched; device info
  confirms **1.2.1/72**. Experimental comparison/Study/model resources were absent.
  All **19 Application Support files** were byte-identical after installation,
  before launch. This is not a distribution archive or upload.
- After launch, all **5 charts** and saved ink, **49 deletion records**, cloud
  metadata, **11 PDFs** and manifest, **1 setlist**, and the **70-example profile**
  remained unchanged. Only normal entitlement/performance state and the cleared
  selected-chart pointer changed. No current chord was reset during delivery.
- Physical acceptance of the new clear-dialog Cancel/Confirm taps and the
  selected-chord tray remains separate from automated source/model checks.
  Use disposable draft ink for confirmation testing. The recognition/learning
  engine, production telemetry, billing, free-month proposal and remaining
  release gates were not changed; no commit or push was performed.

### Render-review handoff hardening — build 73

- The physical build-72 retry still rejected an enabled final Render action.
  Read-only captures preserved the same pending ink; the former generic alert
  could not distinguish changed drafts/barlines/layout from mismatched review
  entries or unsupported text. The exact incident cause is **not established**.
  Two actual SwiftUI sheet dismissal/reopen and replacement diagnostics passed
  before this repair, so stale sheet state is not a proven explanation.
- Both chord and barline preview callbacks now use one shared suspension policy
  while batch review, single review or correction is open. Previously the chord
  callback suspended updates during review but the barline callback did not.
  Each batch sheet has explicit batch identity; submission owns only that batch's
  visible row IDs. Missing rows stay empty rather than inheriting stale entries.
- Review validation now returns a specific failure reason. The alert names the
  failed safeguard and includes a diagnostic code; the local performance trace
  records that code with counts and equality flags, not chord text, chart titles,
  handwriting or identifiers. No production telemetry deployment is included.
  Full draft/barline/source ownership and layout equality, supported-entry checks
  and the downstream atomic live-ink coverage checks remain required.
- Receipt: `/private/tmp/iChartReviewHandoff-20261006.y6Ox7R/`.
  The first native gate executed **171 tests: 170 passed, 1 failed, 0 skipped**.
  The failure was a new test passing raw `C9` plus a newline directly to the
  unchanged lexical boundary. Its fixture now uses supported surrounding spaces;
  the submission test still verifies newline trimming before validation, and
  raw-newline rejection has explicit coverage. No production code changed for
  this fixture repair. The next attempt failed at Simulator launch/preflight
  before executing tests and is not validation evidence. After boot recovery,
  final frozen-source `FinalGateVerified.xcresult` recorded **171 passed,
  0 failed, 0 skipped / 171 total**, verified with `xcresulttool`. This includes
  all 11 rejection reasons, source/ownership and atomic-render protections,
  native review/keyboard paths, real sheet reuse and the 80-combination shared
  preview-suspension policy. Application source hashes match the device build.
- Device build succeeded with zero errors and 15 reported warnings in existing
  unrelated code (actor isolation, deprecations, unused results and unreachable
  code). The preserved Development Debug app is **1.2.1/73** and passed strict
  deep signature verification. Comparison/Study/model resources were absent.
  The exact preserved artifact installed and launched; device info confirms
  **1.2.1/73**. All **19 Application Support files** were byte-identical after
  installation and before launch.
- After launch, all **5 charts**, **49 deletion records**, cloud metadata,
  **11 PDFs** and manifest, **1 setlist**, and the **70-example profile** were
  preserved. Entitlement/performance state and the cleared selected-chart pointer
  changed as before. The current chart's pending chord-ink blob was reencoded
  (7,216 to 7,244 Base64 characters); it was **not byte-identical after launch**.
  A native `PKDrawing` comparison found the same **10 strokes**, identical points,
  transforms, masks, ink types/colors, bounds and creation dates, and exactly
  equal complete reserialized drawings. The content-free equivalence receipt is
  hash-bound to these captured blobs. All other chart fields remained unchanged.
  The reencoding path already existed in `HEAD`: chart decode normalizes valid
  saved ink through `PKDrawing.dataRepresentation()`, and later library saves
  persist the decoded snapshot. No restore, rewrite or profile change occurred.
- This is a scoped review-handoff candidate, not a recognition/learning change
  or a verified fix for the exact physical incident. The same-ink physical retry,
  remaining release gates and free-month proposal remain pending. No commit,
  push, distribution archive or upload is included.

### Bounded final integration audit — 2026-10-06

The user approved the [final integration audit](final-integration-audit-2026-10-06.md)
after positive build-73 feedback. The initial native reproduction found actual
dirty-rotation/save-reopen geometry failures and clipped long/multiline cues in
both styles. The shared coordinate handoff and wrapped cue layout/rendering were
repaired, including below-cue clearance against actual notation paint bounds.
A mounted EditorView test also reproduced missing Clear Draft Ink for retained
sub-threshold ink with an empty preview; its shared eligibility was repaired
without changing confirmation semantics. The unchanged width-reset model policy
was moved to Services for package compilation, and the non-UIKit natural-width
fallback no longer depends on clipped slot width or the old height-based floor.
These are scoped app defects, not recognition or learning evidence.

Delivered candidate: **1.2.1/74**, Development Debug, signature verified,
installed and launched. Final frozen-source gates: native **2,241 passed,
0 failed, 103 skipped / 2,344 total**, verified with `xcresulttool`; SwiftPM
**1,600 passed, 0 failed, 89 skipped / 1,689 total**, command exit 0. Skips remain
explicit historical/private-input, research/runtime/profile and live backend
checks; no core editor/delete/setlist case was silently skipped. Failed earlier
receipts are retained separately. PDF raster inspection verified long/multiline
cue endings in both styles/fonts and below-cue clearance in Rhythm.

Before install: **5 charts, 49 deletion records, 11 PDFs, 1 setlist and
70 handwriting examples**. Installation left all 19 backed-up support files
byte-identical. After launch, chart fields and saved ink, PDFs, setlists,
deletion records and profile remained identical; only entitlements, cleared
chart selection and the performance trace changed. No ink waiver was needed.
On **2026-10-07**, the user reported “ok i think that clears the physical gaps”
after receiving the build-74 physical checklist. The overall physical workflow
gate is accepted by the user. This is not an itemized execution log, a recognition
accuracy result, or release approval; individual destructive touch steps were
not separately reported. The source/resource/config and generated-project
fingerprints were rechecked unchanged on 2026-10-07, so no new app build or
repeated automated suite was needed to record acceptance.

Remaining release work is entitled cloud backup/restore, production telemetry
delivery for the actual candidate, Release/distribution preparation and checks,
and the final free-month decision. Final source reconciliation/commit and push
authorization remain separate. No production, billing, profile, commit, push,
archive or upload change is included in this acceptance record.

This paragraph records the outstanding work at that acceptance checkpoint.
Later October 7 cloud and local distribution receipts supersede those two
pending items, within their stated coverage. The current privacy/cleanup hold
below supersedes any implied instruction to prepare the next candidate now.

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

**Active final pre-push queue — October 9:** the one-month offer policy is decided
and its focused inactive-backend/Sandbox checks are recorded below. Acceptance of
the existing QA purchase is scheduled, not fulfilled. Public campaign activation,
cohort/annual behavior and actual free-period/renewal evidence remain open.
Handwriting setup/teaching/runtime personalization is parked. Privacy retention
configuration is deployed with separate approval; disclosure publication and the
short physical checklist has passed by user report, not a full stress assessment;
fresh distribution checks are not waived. Use the current
closeout sequence above, then record each gate before requesting push approval.

1. **Source and configuration:** finish reconciliation, inventory tracked changes
   **and untracked candidate files**, inspect the active diff, and map the source
   groups to existing test/delivery receipts before selecting uncovered
   regressions. Record branch/commit when authorized. Generate from `project.yml`.
   Use a fresh DerivedData
   path without experimental comparison opt-in; confirm the normal app contains
   no comparison model package.
2. **App verification:** run SwiftPM and the iChart Xcode suites relevant to the
   change. Check a nonzero executed test count from the `.xcresult` summary and
   inspect failures/skips. Keep existing parser, recognition trust, ink, layout,
   profile compatibility, and persistence regression checks.
3. **Physical iPad acceptance, both styles — user accepted build 74 on
   2026-10-07:** the retained procedure is to write a mixed draft, repair one
   unread chord, edit one misread chord, locally rewrite one target, cancel and
   resume review, render, move/edit rendered chords, save/reopen, and export.
   Dense-page writing, erasure, rotation, and key/transposition changes must
   preserve ink placement and usable layout. Check repeats/setup staff lines,
   header/text input, margins, and form-marker sizing on existing fixtures.
   The latest build-75 short privacy/input/save/export/Free Ink rotation checklist
   was reported passed in both styles on October 9; it does not remeasure every
   stress case in this retained procedure.
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
The current backend CI job retains telemetry-ingest contracts and now adds the
complimentary-offer, transaction-authority and account-deletion contracts. Its
new command passes 502 tests locally; together the two commands select 518
contracts. Remote execution remains unverified. Local retention and Deno
composition evidence stays separate; those fixtures are not part of this job.

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

**Cloud gate refreshed 2026-10-07:** the [current cloud gate record](cloud-backup-release-gate-2026-10-07.md)
contains fresh physical backups and installation-scoped production reads for
build 74. Restore Purchases at 08:00:01 PDT returned free/proExpired rather than
recovering the expired September-3 production subscription. The user then
confirmed Apple's explicitly noncharging monthly test purchase. At 08:44:39
PDT, the matched server account was verified StoreKit Sandbox/active Pro with
expiry October 8 at 08:42:40 PDT, no revocation, and true cloud eligibility.
The entitlement prerequisite is satisfied. Two automatic pushes at
08:42:46–47 failed with generic sync_error, but the user's manual retry then
succeeded at 08:52:27 and 08:52:44. That initial backup stored four active chart documents
and eight snapshots, with all four latest payloads matching the freshly saved
iPad charts (including Free Ink in one chart, excluding backup-status stamps).
All four are Simple sheets. Clean-client Simulator restore succeeded at 09:56:07
PDT: all four saved chart objects match before and after normal app restart,
including Free Ink and its persisted coordinates. All four opened; the ink chart
reopened after restart. A separately labelled eight-measure Rhythm QA fixture
with typed header, repeat span and synthetic Free Ink was created through the
Simulator app. Its latest cloud snapshot matches the saved fixture exactly.
Physical iPad restore succeeded at 12:14:51 PDT with five charts; the user opened
the QA Rhythm chart and reported all green. Direct before/after file comparison
confirms all four original charts unchanged, all 49 tombstones and projects
preserved, and no unexpected resurrection. The fixture's only byte difference
is its Free Ink archive encoding; actual PencilKit geometry, point properties,
transforms, masks, random seeds, bounds, ink type/color and coordinates match.
After normal iPad app relaunch, all five saved chart objects match the immediate
post-restore capture. The bounded basic cloud gate passes. The Rhythm fixture
has header/repeat/Free Ink but no chords, pitched notes, rhythm maps or pending
draft; do not claim every musical-content combination or physical reinstall
recovery. No chart was deleted or replaced. The earlier restore flow
gave no visible result text, and its generic permissions error incorrectly
suggests another sign-in as a remedy; those UX follow-ups are recorded, not
implemented in this diagnostic pass. Do not use
ordinary deletion as a restore test or reset the populated iPad; use isolated QA
clients. The agent performed the authorized app restore/QA-fixture workflow;
no billing/policy mutation or new app build was made in this gate refresh.
The user's genuine test purchase updated server
entitlement through the app. The remaining push cause is not established;
duplicate-trigger cancellation and session persistence are source-supported
diagnostic candidates, not device-proven causes.

1. **Cloud backup/access QA:** genuine active Sandbox server access and physical
   Simple-chart backup/content integrity and clean Simulator restore/restart are
   verified. Rhythm fixture backup, first-time physical restore and saved restart
   persistence also passed; the bounded basic cloud gate is complete with the
   fixture coverage limits above. The initial automatic
   failure remains a diagnostic follow-up; current telemetry does not preserve
   the exact push
   error/stage. Do not fabricate entitlement rows, change RLS, purchase a paid
   production subscription or delete current charts to bypass this gate.
2. **Remaining targeted regression checks:** cover dense-page visible Pencil
   responsiveness, the existing repeat/setup-staff fixture, header/text input,
   margins and form-marker sizing if not already exercised on this candidate.
   The broad historical list is not a request to retrain recognition. Preserve
   exact failing ink; fix only a reproduced defect. Naturally unread and unsafe
   ownership cases not encountered manually remain explicitly unexercised.
3. **Distribution:** local distribution-signed Release archive and App Store
   export passed on October 7 as recorded below. Resolve the confirmed privacy
   gaps and prepare a new marketing version in the next scoped pass; then review
   GitHub push/remote CI and separately authorize upload/TestFlight delivery.
   Local archive/export is not upload, TestFlight availability or publication.

### Local distribution readiness and privacy hold — 2026-10-07

**Status: local App Store packaging passed; publication remains on hold.** The
accepted build-74 app source and generated-project/dependency hashes still
match the frozen October 6 manifests. No app implementation, version/build,
package, provisioning/account/keychain, backend, or App Store setting was
changed in this distribution-readiness pass.

- Evidence directory: `/private/tmp/iChartDistributionReadiness-20261007.GFD6wQ/`.
  Normal Release archive and local App Store Connect export both exited **0**.
  `Archive.xcresult` build results report **succeeded, 0 errors, 14 warnings,
  0 analyzer warnings**. This was an archive action, not a test action; no
  earlier test counts are attributed to it. The remaining warnings include
  deprecations, unused-responder/unreachable-branch warnings and six UIKit
  actor-isolation warnings in telemetry code.
- Archive: `iChart-1.2.1-74.xcarchive`. Deep/strict code-signature verification
  passed with Apple Distribution for team `N6G8X4K46U`. The matching manual
  `iChart App Store` profile is `4c854b12-3de3-4288-a036-bc1215a7f347`, expires
  **2027-06-20**, has no provisioned-device list and matches the app/team.
  Entitlements include `get-task-allow=false` and `beta-reports-active=true`.
  This is distribution signing, not the earlier Apple Development Debug receipt.
- Archived and exported app metadata report `com.ichart.app`, **1.2.1 (74)**,
  `iphoneos`, minimum iOS 17 and device family 2. Hosted Supabase configuration
  is present for `pausvvwoazbvmzyrebwl.supabase.co`, with an `sb_publishable_`
  client key; no key value is recorded here. The bounded filename scan found
  the app and swift-crypto privacy manifests and no Study, experimental personal
  model/comparison, or `.storekit` resources. This scan is not privacy approval.
- Local export: `LocalExport/iChart.ipa`, **14,583,478 bytes**, SHA-256
  `87aa6e05481625cde423dd5cb8afc117ae823e7db4596f458631da5e45532a60`.
  `LocalExport/DistributionSummary.plist` confirms the App Store profile,
  Apple Distribution and **1.2.1 (74)**. A fresh unpack under
  `ExportedIPAInspection/` also passed deep/strict signature verification.
  No distribution-installed physical workflow is established by these receipts.

Read-only App Store Connect checks found **1.2.1 Ready for Distribution using
build 51**, with automatic release selected. That is the older released version,
not this candidate. The visible 1.2.1 TestFlight table contains build 51 marked
Ready to Submit. After the uploads list loaded, its latest visible row was
**1.2.1 (51), Complete, September 2**, followed by builds 50, 49 and older in
descending order; no build 74/newer candidate was visible. A new marketing
version is required for the next release; **1.2.2 (75) is recommended after the
scoped privacy fixes**, not applied. Future version/build availability is not
reserved or guaranteed by this read. New review/TestFlight metadata and the
intended next-version release mode still need a fresh check.

Confirmed privacy/review blockers for the next scoped pass:

1. **In-app legal links:** the subscription upgrade and Settings purchase
   surfaces lack direct Terms of Use and Privacy Policy links. Help's inline
   summaries do not resolve that omission. Source: `UpgradeSheetView.swift:99`
   and `LibraryView.swift:6343`. The metadata draft also lacks a Terms/EULA link;
   current App Store Terms/EULA configuration is not established by that draft.
2. **Telemetry consent, withdrawal and retention:** telemetry initializes and
   records launch before UI, with no consent/withdrawal control found. No
   evidence resolving the applicable consent exception was reviewed. A
   180-day purge helper exists in source, but a scheduled live cleanup is not
   established. Retention and withdrawal must be resolved rather than inferred
   from a helper or account deletion. Source: `IChartApp.swift:19`,
   `IChartTelemetry.swift:196` and
   `20260813192919_telemetry_foundation.sql:120`.
3. **Required-reason API mismatch:** shareable performance reports contain raw
   `systemUptime`, while the app manifest declares only boot-time reason
   `35F9.1`. The source audit identified a disclosure/use mismatch; the smallest
   repair is to remove raw uptime from exported reports and retain elapsed
   durations, followed by verification. Source: `IChartPerformanceTrace.swift:51`,
   `LibraryView.swift:4862` and `PrivacyInfo.xcprivacy:21`.
4. **Verified store/policy disclosure drift:** current App Privacy was published
   two months earlier and lists eight linked App Functionality types: Customer
   Support, Email Address, Product Interaction, Other Usage Data, Purchase
   History, Name, User ID and Other User Content. It has no Device ID,
   Performance Data or Other Diagnostic Data categories and no Analytics
   purposes, unlike the current nine-category app manifest and telemetry
   inventory. App Store Connect stores `https://useichart.com/privacy`; its
   privacy-choices URL is blank. A fresh `/privacy` read redirects the client to
   `/privacy.html`; the public Terms page is accessible. The privacy page serves the older
   **August 13** policy, without the installation/session/account linkage
   paragraph present in local **September 12** source, and without telemetry
   retention/withdrawal disclosure. This is a current observed mismatch, not
   merely an assumption from the historical checklist. Reconcile actual
   collection, manifest, store labels and deployed policy in the scoped pass.

Apple references used by the focused privacy audit:
[subscription legal links](https://developer.apple.com/app-store/subscriptions/),
[privacy requirements](https://developer.apple.com/app-store/review/guidelines/#privacy),
and [required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc).

These findings do not invalidate the bounded cloud gate or local signing/export
receipts, and those receipts do not waive the privacy blockers. Privacy fixes
require the next scoped implementation/verification pass and a refreshed
candidate. Optional telemetry default-off with a withdrawal control, legal URLs
and removal of shared raw uptime are the proposed bounded app fixes; the
telemetry product choice is awaiting user direction. Store/site writes require
separate approval. No commit, push, upload, review submission, publication or
commercial offer change was performed; no such action is authorized by this
bookkeeping.

### Pre-build-75 cleanup and decisions — 2026-10-07

**Scope:** implement the app-side privacy repairs, live-price savings badge,
cloud operation feedback and obsolete QA presentation cleanup; inventory
remaining product choices and preserve parked work. Do not prepare build 75.
No recognition, profile, chart merge, billing, authentication, RLS or
production-ingest behavior is changed. Local optional diagnostics now require
consent; cloud failures use fixed stage/category values in already-supported
diagnostic fields.

App privacy implementation:

- Optional diagnostics are **off by default**, including for upgrades with no
  current explicit consent. Settings → Privacy contains one switch and explains
  the technical data, random identifiers and signed-in account linkage. No
  startup consent modal or purchase/feature dependency was added.
- The gate applies before recording, queue append and network request start.
  Withdrawal stops collection/sending, cancels in-flight work where possible,
  removes the local installation identifier and clears unsent events. A request
  already sent may finish; withdrawal does not erase received server records.
  Consent generations reject old detached tasks and acknowledgements. A
  persisted reset marker prevents off → on → termination/relaunch from reviving
  an old queue; it is cleared only after successful generation-matched cleanup.
- Upgrade and Settings purchase surfaces now have direct Terms/Privacy links
  and an auto-renewal/cancellation notice; Help also links the public documents.
  Product IDs, prices, purchase options and entitlement authority are unchanged.
- Performance reports no longer record raw device uptime. Sharing creates a
  separate typed/allowlisted JSONL snapshot, also stripping legacy uptime and
  unknown fields from older saved logs. Malformed lines are omitted, never
  forwarded raw; elapsed durations remain. Sanitization failure cannot fall
  back to sharing the original trace. Local source logs are preserved.
- `public-site/useichart/privacy.html` is a **local draft**, not a deployed policy.
  Its default-off/withdrawal text describes the future consent-enabled app, not
  the old app currently distributed. Publish only after retention/deletion,
  actual App Store disclosures and rollout timing are reconciled.

Verification: evidence is at
`/private/tmp/iChartPrivacyCleanup-20261007.bLnPnB/`. Final native
`PrivacyFinalRerunTests.xcresult` reports **62 passed, 0 failed, 0 skipped**, read
with `xcresulttool`, including project configuration, telemetry model/transport,
trial readiness, legacy-report sanitization and UI wiring. SwiftPM separately
ran the report/UI-wiring tests: **7 passed, 0 failed**, command exit 0. These
overlap the native gate and are not 69 distinct cases. `xcodegen generate` and
`git diff --check` passed; version/build remain **1.2.1 (74)**. No new dependency
resolution or upgrade was performed.

The first gate passed 60 tests before adding two persisted-reset regression
cases. The expanded gate then exposed an incorrect implicit-flush expectation
in the new relaunch test: an immediately preceding empty flush correctly
starts the existing throttle. The test now proves a fresh, distinct event is
queued and explicitly flushes it; startup deletion, generation and delivery
assertions were retained. Failed and initial receipts remain separate; only
the final rerun above validates the completed changes.

These are local consent/transport/report checks, not physical Pencil acceptance,
visual/touch acceptance of the new Privacy/legal controls, improved recognition
accuracy, or a refreshed distribution archive. Those app controls still need a
physical check when the user authorizes the next candidate, including legal-link
access in landscape/larger text. The prior six UIKit actor-isolation warning
sites remain known debt; this pass does not claim they were removed.

Read-only production configuration check: `pg_cron` and the telemetry purge
helper exist, but **zero** `cron.job` entries have commands naming either
`purge_old_telemetry_events` or `telemetry_events`. No customer rows or job
commands were read, and no purge was executed. The source helper defaults to
180 days, but its existence is not an implemented retention schedule. This
bounded catalog check cannot exclude an external scheduler or indirectly
invoked job. Retention and received-record deletion remain unresolved; do not
publish a verified 180-day guarantee or deploy server cleanup without approval.

| Cleanup item | Current evidence | Next bounded action / decision |
| --- | --- | --- |
| Complimentary Pro period | One calendar month free with automatic paid renewal unless canceled, after Apple acceptance. New-authorizations window is 90 days from actual public release. Introductory/promotional app flow is implemented locally. Matching monthly/annual Free/1 Month promotional definitions are saved in Apple; introductory dates are deferred. Approved signing credentials, environment-scoped ledger and authenticated endpoint are deployed and verified inactive. One recorded active annual subscriber is the known case, not a complete Apple buyer ledger. Offer-code association is parked. | Follow the [Sandbox QA gate](ichart-storekit-subscription-runbook.md#next-gate-isolated-sandbox-purchase-qa): obtain approval for the updated test app, then prove new/lapsed monthly/annual and same-product active annual scheduling. Use a separate QA account; existing one-row subscription authority is unchanged. No live activation or base-price/entitlement write occurred; build 75 remains on hold. |
| My Handwriting setup | Parked by user decision October 8. Central unconditional false policy hides entry and disables profile matching, learning and older correction-memory personalization. Saved preferences/examples/files remain unchanged. | Physical absence/ordinary workflow check with the eventual candidate. Do not reactivate merely by restoring Debug UI. No general accuracy gain claimed. |
| Saved Chart Test / Teach / Teach Symbols | Parked with setup. Ordinary canvas evaluation context/source/preview capture is disabled, including preserved active runs; teaching and comparison UI is unreachable. Dormant research/test APIs remain. | Retain saved runs and journals; do not finish or reset an active evaluation while parking. Any future reactivation requires an explicit decision and fresh evidence. |
| Annual subscription savings badge | Locally implemented and tested: calculated from Apple's fetched monthly/annual recurring prices only when currency and billing periods are comparable. Whole-percent savings round down; missing, invalid or non-saving comparisons omit the badge. Debug local preview remains separate. | Physical/storefront display check on the eventual candidate. Product IDs, prices, offers, purchases and server entitlement authority are unchanged. |
| Cloud feedback and diagnostics | Locally implemented and tested: distinct backup/restore progress, persistent last-restore receipt, actual remote versus resulting local counts, operation-specific retry labels and typed content-free failure categories/stages. Late completion cannot replace signed-out feedback. Initial automatic-push cause remains unproven. | Physical visual check and refreshed cloud acceptance on the eventual candidate. Existing restore/merge, permission fallback and scheduling behavior are preserved; no server deployment was needed. This is not a broader cancellation/data-application repair. |
| Research and old QA leftovers | Study sources/resources remain excluded. Handwriting/comparison entry and runtime participation are now parked regardless of configuration; dormant Debug comparison artifact settings are preserved. Plan Preview and synthetic fixtures remain Debug Simulator-only. Logo resources and research evidence remain intact. | Refresh Release exclusion checks with the eventual candidate. No broad research integration, model promotion or evidence deletion. |
| Privacy rollout / release records | App repairs are local. Existing App Store labels and live August-13 policy were observed out of sync with current collection. Server retention/deletion is not established. Old archive remains valid for its frozen source only. | Resolve retention/deletion and reconcile manifest, store labels, legal metadata and deployed policy before publication. Then refresh the candidate/version, physical acceptance, archive, remote CI and separately authorized upload. |

The subscription runbook now points here for current state; its older setup
steps are historical configuration guidance, not a request to recreate products.
Nothing has been discarded, promoted into the live recognizer, committed,
pushed, uploaded, published or commercially activated in this pass.

#### Handwriting parking and universal-offer design — October 8

The user approved parking **all handwriting setup/new recognition flows for the
next build**, not deleting them. `HandwritingPersonalizationProductPolicy` is
unconditionally false in both Debug and Release. Editor entry/teaching UI is
hidden, ordinary sessions do not load or apply personal profiles, and canvas
evaluation context/capture/recording is disabled. The older correction-memory
load/update/auto-apply/save path is also parked; standard recognition, preview,
review, manual correction and chart commits remain.

Saved profiles, preferences, examples, correction-memory files and evaluation
journals are not reset, migrated or deleted. A preserved active evaluation is
left active in storage but receives no new ordinary-chart observations while
the UI is parked. Dormant research/test APIs remain explicitly callable;
personalization tests opt in rather than changing the product default.

Evidence: `/private/tmp/iChartHandwritingParking-20261008.KMCAvS/`.

- `ParkingTests.xcresult`: **86 passed, 0 failed, 0 skipped**, nonzero execution
  verified with `xcresulttool get test-results summary`.
- Classes: project configuration (29), parked product policy (2), recognition
  session (15), render resolution (9), draft suggestions (7), correction memory
  contracts (19), and dormant evaluation capture contracts (5). The new runtime
  regression injects an enabled saved profile and evaluation context into the
  default session: standard result retained, no personal/evaluation prediction,
  exact profile bytes unchanged.
- The full app compiled for the pinned Simulator. `xcodegen generate` passed;
  version/build remain **1.2.1 (74)**. No build-75 preparation, iPad install,
  archive/export/upload or push was performed. This is not physical UI acceptance
  or evidence of fresh handwriting accuracy.

The complimentary-Pro audience is now agreed: **new, returning/expired and
existing users**. The [subscription runbook](ichart-storekit-subscription-runbook.md#complimentary-pro-campaign--design-not-an-activated-offer)
records the settled one-calendar-month, automatic-paid-renewal terms after
explicit Apple acceptance, and the selected introductory/promotional purchase
path. The later read-only lookup found one current production annual entitlement;
the existing annual case is treated separately without hardcoded customer
identity or an assumption that unlinked Apple purchases cannot exist. The
current StoreKit claim contract still rejects missing/mismatched account binding.
Existing paid users need real added value, not simultaneous local access to a
term they already bought. No offer configuration, signer, free-access grant,
redemption UI, server write or live offer was introduced in this decision pass.

#### Complimentary Pro implementation receipt — October 8

The subsequent authorized code pass implements the token-bound one-month offer
flow locally. It validates Apple's fetched offer terms, selects introductory
versus signed promotional purchase from eligibility and fresh verified history,
and preserves active monthly/annual products and their paid terms. A scheduled
benefit is not represented as active; its future end is explicitly estimated
until an actual redeemed transaction supplies the end date. No full-price
fallback or local entitlement override is used. The normal claim must succeed
before campaign confirmation; optional telemetry is not required for a benefit.

The new authenticated endpoint and server-only signer are disabled by default.
The campaign ledger migration uses RLS, service-only RPC privileges, row locks,
attempt CAS and original-chain uniqueness. Canceled preparation does not consume
the benefit, explicit new purchases receive fresh nonces, and first actual
benefit dates cannot be extended by replay. No person-specific allowlist was
added. Saved handwriting data and parked recognition flows remain unchanged.

Evidence: `/private/tmp/iChartComplimentaryPro-20261008.eEabuA/`.

- `backend-final-tests.log`: **184 passed, 0 failed, 0 skipped**, four new
  campaign suites plus four existing claim/verifier/ownership suites. Includes
  actual cross-module adapters, fresh-history failure boundaries, normal-claim
  ordering and isolated campaign Sandbox configuration.
- `ledger-final-qa.log`: **12 passed, 0 failed** against the exact migration in
  synthetic PGlite 0.5.8 PostgreSQL. Covers role denial/RLS, nonce retry rules,
  stale attempts, cross-product/owner duplication, immutable benefit and account
  deletion cascade. Not deployed PostgREST or real Apple concurrency evidence.
- `ComplimentaryFinalTests.xcresult`: **78 passed, 0 failed, 2 skipped**;
  actual nonzero execution verified with `xcresulttool`. Includes campaign
  policy/source-integration, ordinary transaction recovery, product catalog,
  entitlements, project wiring, privacy/legal and handwriting-parking checks.
  The two skipped tests are existing live Supabase forum/cloud CRUD tests,
  explicitly opt-in; they do not establish deployed campaign behavior.
- Final Deno type/compile check and actual runtime import passed. With no
  configuration, the runtime remains disabled. Temporary official Deno and
  PGlite tools are outside the repository; no app dependency was added.

The full app compiled for the pinned Simulator after the final recovery fix;
`xcodegen generate` and `git diff --check` passed. Ordinary transactions bypass
the optional endpoint before session/status lookup, while known campaign and
account/product-bound pending transactions remain recoverable if confirmation
is unavailable. Simulator compilation/testing is not a real Apple purchase or
physical UI acceptance. Version/build remain **1.2.1 (74)**.

Live gates remain: App Store Connect login/inventory, claim-window decision,
server signing material, migration/function deployment and real Sandbox
introductory/promotional, cancellation/retry, account mismatch, duplicate/reinstall
and same-product annual scheduling/full-Pro checks. Apple and the SQL ledger
are not globally atomic; delayed signature redemption remains a live gate.
No build-75 preparation, iPad installation, archive/export/upload, commit, push
or production activation occurred in this implementation pass.

#### Complimentary Pro window/configuration follow-up — October 8

The user signed into App Store Connect and delegated claim timing. The chosen
new-authorization window is **90 days starting with actual public release**;
no absolute timestamps, campaign activation or free-month access clock have
started. The two promotional definitions were created and visibly verified:

- Monthly: `ichart_complimentary_monthly_1m_v1`, **Free for the first month**,
  175 countries/regions.
- Annual: `ichart_complimentary_annual_1m_v1`, **Free for the first month**,
  175 countries/regions. Existing annual product/year and group levels unchanged.

Before creation both products had no introductory/promotional definitions.
Both introductory pages remain empty; their dates are deferred until release
because Apple can present them independently of the new client/campaign flag.
Both base products have Family Sharing off. The public approved 1.2.1 listing
references build 51, not local build 74; this is a release-version boundary,
not evidence this local offer flow is already publicly deployed. The Apple
In-App Purchase key inventory shows **Active (0)**; action-time approval to
generate/protect a server key was requested. No private key or issuer material
was read/downloaded, no server secrets changed, and no function/migration was
deployed in this follow-up. These promotional definitions are configuration,
not verified customer acceptance or fulfillment.

The new unapplied migration now scopes campaign accounts/attempts, row locks,
CAS, confirmation and original-chain uniqueness by Apple environment as well
as owner/campaign. Sandbox usage cannot consume Production's campaign benefit.
Cached seeds are filtered by environment. The normal subscription authority is
unchanged and still has one row per owner; use a separate iChart QA account for
Sandbox campaigns, not the paid Production account.

New preparation checks cutoff after Apple verification, DB reservation and
signing. If cutoff is crossed, it returns no fresh signature/authorization.
`canPrepare:false` permits prepared recovery metadata but cannot authorize a
new client purchase. A predeadline persisted introductory authorization can
support late exact Apple-verified completion, without an invented approval
grace period or local entitlement override. Authorization is the server's
reservation timestamp, not proof of when Apple buy was launched. Already-issued
promotional signatures retain Apple's 24-hour acceptance validity. Closing
new authorizations uses `ENDS_AT`; keep the campaign enabled for accepted-benefit
recovery. Emergency disable is a separate safety action.

Expired unrevoked/non-upgraded exact gifts preserve the original redeemed dates
and can complete recovery as **ended**, with no access renewal or second gift.
Revoked/upgraded/invalid-term evidence still fails closed; terminal finishing
for those states remains a focused lifecycle QA gate, not a claimed result.

Evidence, independently rerun after the final changes:

- `backend-window-final-tests.log`: **202 passed, 0 failed, 0 skipped**, exact
  eight campaign/adapter/Apple/existing-claim suites.
- `ledger-window-qa.log`: **16 passed, 0 failed** against the exact migration
  using synthetic local PGlite PostgreSQL, including same-owner environment
  isolation and cross-environment attempt/CAS denial. Not a live PostgREST or
  multi-connection/Apple atomicity test.
- `ComplimentaryWindowFinalTests.xcresult`: **80 passed, 0 failed, 2 skipped**
  (82 total), verified with `xcresulttool`; the two skips are the existing
  opt-in live cloud/forum tests. Full Simulator app compilation completed.
- Deno endpoint check passes; actual runtime import with no configuration
  stays disabled. Source review verified the cutoff and client authorization
  findings were closed; existing claim-authority source has no change.
- Saved browser proof: `monthly-offer-saved.png`, `annual-offer-saved.png` and
  `apple-signing-key-approval.png` in the existing private temporary evidence
  directory. No credential/private-key material is in these captures.

Version/build stay **1.2.1 (74)**. No build-75 setup, device installation,
archive/export/upload, customer purchase/refund/renewal extension, commit or
push occurred. Remaining gates are protected signing setup, inactive server
deployment, real Apple Sandbox cohort/lifecycle/full-Pro delivery checks, then
release-aligned introductory dates and explicit commercial activation. Local
tests/configuration do not substitute for those gates.

#### Complimentary Pro signing-key staging receipt — October 8

After explicit approval, the `iChart Server Offers v1` Apple In-App Purchase key
was created and downloaded once. Its material was validated as P-256 PKCS8 and
stored only in the protected iChart Supabase Edge Function secrets:
`APP_STORE_SUBSCRIPTION_KEY_ID`, `APP_STORE_SUBSCRIPTION_KEY_P8` and
`APP_STORE_ISSUER_ID`. Remote digests match the approved source. All preexisting
secret digests are unchanged; no existing verifier configuration was replaced.

The explicit campaign flag was set to **false** and verified before adding
credentials. No campaign timestamps or introductory dates were set. The
`storekit-complimentary-offers` endpoint remains absent, and no migration or
function code was deployed. All six existing deployed function code hashes and
JWT settings are unchanged. Supabase secret updates increased their platform
revision numbers by three; that revision change is not a function-code release.

Validation boundaries:

- Local crypto roundtrip and the actual app's legacy promotional DER signer
  verified against the downloaded key using synthetic account/nonce data.
- Read-only Apple Production and Sandbox probes using a synthetic transaction
  ID each returned HTTP 404 / API `4040010` (transaction not found). This checks
  the authenticated request boundary, not real ownership, redemption, offer
  scheduling or full-Pro delivery. No customer subscription was changed.
- Temporary plaintext download and serialized secret-import environment file
  were removed after remote digest verification. Apple's original download
  cannot be repeated; the protected server copy remains. Private material,
  JWTs and signatures were not printed or committed.

Evidence: `signing-secrets-receipt.json`,
`apple-key-readonly-final-qa.log` and `apple-signing-key-created.png` in
`/private/tmp/iChartComplimentaryPro-20261008.eEabuA/`. This receipt supersedes
the missing-key status in the preceding configuration follow-up. No app build
or test suite was rerun for this credential/documentation-only step; earlier
local test receipts retain their original scope.

Remaining gates: inactive migration/function deployment, real Apple Sandbox
cohort/lifecycle/full-Pro checks, then release-aligned introductory dates and
explicit Production activation. Version/build remain **1.2.1 (74)**. No build-75
preparation, installation, archive/export/upload, commit or push occurred.

#### Complimentary Pro inactive deployment receipt — October 8

The user authorized continuing to the next gate. Only the new campaign migration
and `storekit-complimentary-offers` function were deployed to the verified iChart
project, with `ICHART_COMPLIMENTARY_CAMPAIGN_ENABLED=false` and no absolute campaign
dates. JWT verification is enabled on the new endpoint, version **1**. The six
preexisting function code hashes, versions and JWT settings are unchanged from
the post-key-staging baseline. Existing claim/notification authority was not
redeployed. Parked recognition-study migrations/functions were not deployed.

The migration was applied through the authenticated management migration tool;
its assigned version is **20261008173453**. The local unapplied file was renamed
to this remote version (original preparation filename `20261008161104`), preserving
the tested SQL. A predeployment database-guidance check added the owner-leading
index for `auth.users` deletion/cascade lookup; no unrelated schema was changed.

Fresh evidence in `/private/tmp/iChartComplimentaryPro-20261008.eEabuA/`:

- `backend-inactive-deployment-tests.log`: **208 passed, 0 failed, 0 skipped**,
  nine campaign/Apple/store/integration/existing billing suites.
- `ledger-deployed-file-qa.log`: **17 passed, 0 failed**, exact final migration
  against synthetic local PGlite, including the account-cleanup index. Not live
  multi-connection or Apple transaction evidence.
- Deno check of the actual endpoint passed.
- Live SQL confirms both tables have RLS, no client table privileges, and no
  client RPC execution. RPCs are security invoker with empty search paths and
  service-role-only execution. Both invalid-input RPC calls rejected before
  writes. Campaign account/attempt counts stayed **0/0** after smoke checks.
- `inactive-deployment-final-qa.log` and `inactive-deployment-receipt.json`:
  **10/10** live checks passed. The actual handler boots and reports disabled;
  a public anonymous JWT cannot act as a signed-in user. Anonymous REST reads
  and RPC calls are denied. Existing claims require authentication; notification
  handling rejects missing/fake Apple payloads. No real user token was extracted.

Postdeployment advisors report no new warning/error-level findings or unindexed
campaign foreign keys. The two new RLS-with-no-policy informational notices are
intentional server-only deny-by-default tables, not a reason to grant clients
access. The new owner index is informationally unused because the ledger is empty.
Preexisting MFA warning and other index/connection advisories are unchanged and
outside this scoped deployment: [MFA guidance](https://supabase.com/docs/guides/auth/auth-mfa),
[RLS advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Not yet established: an authenticated user's disabled request; active
status/prepare/confirm through deployed PostgREST; real introductory/promotional
purchase, active-annual scheduling, account/reinstall recovery or full-Pro
delivery. Those need the [isolated Sandbox QA gate](ichart-storekit-subscription-runbook.md#next-gate-isolated-sandbox-purchase-qa)
and an approved updated test app. The installed build 74 predates the offer UI.
No Sandbox or Production campaign activation, Apple purchase, customer
subscription change, build-75 preparation, install, archive/export/upload,
commit or push occurred at that deployment checkpoint. Version/build remained
**1.2.1 (74)**; the later limited build-75 authorization and results follow.

#### Build-75 test build and install receipt — October 8

The user explicitly approved lifting the build hold for **build/install testing
only**. `project.yml` was changed to **1.2.1 (75)** and the generated project
refreshed with `xcodegen generate`. No recognition, billing or other native
implementation was changed during this gate. Pinned package versions were
retained; no package upgrades or provisioning updates were needed.

Private evidence: `/private/tmp/iChartBuild75Test-20261008.UDD7kZ/`.

- `Build75FocusedTests.xcresult` / `native-test-summary.json`: **147 passed,
  0 failed, 2 skipped** (149 total), independently verified with `xcresulttool`.
  Coverage includes campaign policy/client integration, product/entitlement
  regressions, project configuration, handwriting parking, privacy/consent,
  telemetry, cloud feedback, typed/review input and library/setlists. The two
  skipped cases are existing opt-in live Supabase cloud/forum tests. Source
  integration checks are not live Apple offer-purchase evidence.
- `Build75Device.xcresult` / `device-build.log`: device Debug build succeeded
  with ordinary Apple Development signing. Strict deep signature verification
  passed; the development profile includes the paired iPad and is unexpired.
  Actual app metadata is **1.2.1 (75)**. Artifact QA verifies the privacy manifest
  and absence of experimental comparison/Study/model packages.
- `artifact-qa-receipt.json` and protected `candidate-source-manifest.json`
  bind the tested source and signed artifact. Executable SHA-256:
  `d29ef05fd71f35570d5a222345190d312437571780385315a12be1112e755d78`.
  Non-documentation source was rechecked unchanged after installation.
- `install.json`, `app-after.json` and `launch.json`: installed over existing
  build 74 without uninstall/reset, then launched normally on Ben's paired iPad.
  `process-after-launch.json` confirms the app remained running several minutes
  after startup. No injected auth environment, signing prompt or credential
  document access was needed.
- Application Support and Documents were backed up before installation and
  after launch. Immediate post-launch saved non-diagnostic files were
  byte-identical: **5 charts, 11 PDFs, 1 setlist and 70 handwriting examples**.
  A second capture after initialization shows the same chart content and ink;
  the only changed per-chart field is `cloudBackupStatus.lastBackedUpAt` on all
  five charts. Library sync/access metadata and selected-chart state refreshed.
  PDFs, setlist and handwriting profile remain byte-identical; project and
  deletion records are unchanged. See `data-preservation-receipt.json` and
  `data-preservation-bootstrap-receipt.json`. Do not call the later complete
  library file byte-identical or infer cloud restore from these captures.
- `campaign-still-disabled.log`: **10/10** existing live inactive-deployment
  smoke checks passed again. No server code/schema/config was changed.
  A read-only startup-window log aggregate records six authenticated HTTP 200
  requests to the new offer endpoint and three authenticated HTTP 202 requests
  to ordinary subscription claims. No user identifier, JWT, request payload or
  response body was queried. This establishes authenticated endpoint reachability
  during startup, not full-Pro delivery or Apple offer fulfillment.

The campaign remains **off**, with no Sandbox/Production window or introductory
dates started. Saved personalization data is retained while its product flow and
runtime use remain parked. No purchase, customer subscription change, archive,
export, upload, public release, commit or push occurred.

The user subsequently confirmed existing charts open normally: **"yes everything
seems good"**. This closes the requested physical chart-opening check. It is not
a new full Pencil/keyboard/PDF/cloud-restore acceptance pass or Apple offer test.

The read-only Sandbox planning checkpoint found a prerequisite before activation:
the campaign environment override scopes Apple lookups and ledger rows, but
did not restrict endpoint callers to a QA cohort. The handler then accepted
any authenticated owner UUID. Merely setting the shared endpoint to Sandbox is
not production-user isolation. Normal subscription claims also upsert by owner,
not environment; the real paid iChart account must not be used for Sandbox buys.
No isolation guard or live configuration change was implemented by that planning
check. The subsequently approved guard work is recorded immediately below.
The staged
[Sandbox plan](ichart-storekit-subscription-runbook.md#next-gate-isolated-sandbox-purchase-qa)
keeps actual introductory-offer dates as a separate commercial decision.
Sandbox activation and purchases require their own approval; this install
authorization does not supply it.

#### Sandbox QA-owner guard inactive deployment receipt — October 8

The user explicitly approved implementing, verifying and deploying the narrow
QA-account-only Sandbox guard while keeping the campaign off. This did not
authorize purchases, public offers or release.

- Source/test changes: `complimentary_offer_campaign.mjs`, the new
  `complimentary_offer_sandbox_qa.test.mjs`, and explicit synthetic QA configuration
  in the existing campaign and integration tests. No native app source changed.
- Effective Sandbox requests now require the authenticated owner in server-only
  `ICHART_COMPLIMENTARY_SANDBOX_QA_OWNER_IDS`: a bounded JSON array of 1–32 unique
  UUIDs. Missing, empty, malformed, sparse, duplicate and oversized configurations
  fail closed, including direct handler configuration and environment fallback.
  Client fields, headers and user-editable metadata cannot supply cohort membership.
  All status/prepare/confirm and recovery paths deny non-QA access before ledger,
  subscription seed, verification, Apple, reservation, recording or signing work.
  Denied status reports `enabled: false`; Production does not read the QA setting.
- Node syntax and cached Deno endpoint checks passed. The ten-suite backend gate
  executed **237 tests: 237 passed, 0 failed, 0 skipped**. Independent read-only
  review found no concrete remaining bypass/regression; its overlapping test count
  is not added to this total.
- Only `storekit-complimentary-offers` was deployed, to the verified iChart project
  `pausvvwoazbvmzyrebwl`. It is **version 2**, active, with JWT verification enabled
  and code hash `36ffff152ab857c24b337d9f08f5dc507f694efdbf765c0c15c6a576637d34bc`.
  All **11** returned deployed source files byte-match the tested deployment.
  The six other function code hashes, revisions and JWT settings stayed unchanged.
- **10/10 live inactive checks passed**, covering endpoint boot/auth boundaries,
  anonymous campaign-table/RPC denial and existing claim/webhook controls.
  All server-secret digests were unchanged. Campaign enabled remains **false**;
  no dates or QA-owner list are configured. Campaign accounts/attempts stayed
  **0/0** before and after the checks.
- Managed evidence and exact version-1 rollback source are retained at
  `/Users/benirossman/.codex/state/plugins/codex-security/scans/Smart-Chart/artifacts-263dba0e26d37571d9e515362ac3e570f5e80f2ce154cccf0556090114e4cbd4/artifacts/qa-guard/`.
  Start with `verification-summary.md` and `inactive-guard-deployment-receipt.json`.

Limits: enabled-path authorization and legitimate controls were tested locally
against byte-matching deployed code, not with a live approved customer token.
Actual Apple offer purchases, annual scheduling and full-Pro delivery remain open.
No schema/policy change, real-account allowlisting, campaign clock, purchase,
customer-subscription change, app rebuild/install, archive/export, upload, public
release, commit or push occurred in this guard pass. Build 75 remains the installed
candidate; this server-only change did not require a new app build.

Next: follow the October 9 same-owner realignment receipt below rather than
switching the populated iPad to an unverified empty QA account. Preserve the
real paid subscription and global claim verifier settings. Actual introductory
dates/public offers and any purchase acceptance remain separate decisions.

#### Isolated Sandbox setup preflight — October 8

The user subsequently approved the dedicated QA account, Apple Sandbox tester
and isolated test-window setup. This is not purchase, introductory-date or public
offer approval. Read-only checks found an existing iChart QA-account candidate
with a confirmed email, free/inactive plan, no StoreKit transaction, **0 cloud
charts, 0 snapshots and 0 campaign accounts/attempts**. An existing Apple tester
named **iChart Sandbox** is visible in the authenticated App Store Connect
inventory. Neither candidate's usable login has been verified; the blank Apple
last-purchase column is not proof of an empty lifetime purchase history.

The browser permission control denied further App Store Connect access during
the tester-detail step. No workaround was attempted. No account was created or
changed, no credential was reset, and no campaign configuration was written.
The test window must not start while account/tester access remains unresolved.
Resume with restored browser permission and verified QA logins, then stage the
Sandbox override, single-owner list and short explicit UTC window while disabled;
enable last for status-only checks. Keep the populated iPad/account and ordinary
claim verifier unchanged. Disable first before removing any Sandbox override:
an absent override falls back to the global Apple environment and could otherwise
expose a Production campaign. Actual purchase acceptance remains a later step.

#### Same-owner Sandbox realignment receipt — October 9

The user's iPad screenshot shows their current Apple login in the dedicated
Developer → Sandbox Apple Account setting. Do not dismiss this as a main
Apple/iCloud login or insist on changing it solely because App Store Connect
shows a differently named tester. The denied App Store Connect origin was not
accessed through another browser, raw requests, or native-app automation.

Fresh read-only server checks established that the current iChart owner has an
active Sandbox monthly subscription with a matching appAccountToken. This owner
is **not** the separately recorded active Production annual owner. Switching to
an empty iChart QA account while retaining this Apple purchase history could
correctly trigger token/original-transaction ownership rejection. The existing
same-owner Sandbox account is therefore the narrower test path; it is not proof
of fresh-customer introductory eligibility.

With the campaign disabled, only three campaign settings were written:
enabled=false, explicit environment=Sandbox, and a single-owner QA allowlist for
that verified owner. Follow-up digest checks confirmed these exact values, no
start/end dates, and unchanged ordinary Apple environment and signing-key
digests. No offer window started, no purchase was prepared or accepted, no
subscription authority was changed, and campaign accounts/attempts remained
**0/0**. The campaign still fails closed without dates.

Device and local evidence:

- Fresh CoreDevice inventory confirms **iChart 1.2.1 (75)** installed. The
  existing app was launched without termination, reinstall, sign-out, or preview
  overrides. This is not a new human UI/offer acceptance receipt.
- Read-only Library backup contains **5 charts, 11 saved PDFs, 1 setlist and 70
  handwriting examples**. Documents was independently confirmed empty after its
  empty-directory copy failed; Library copy succeeded. No device file was
  overwritten or deleted. Backup and CLI receipts are at
  `/private/tmp/iChartSandboxRealignment-20261009.nq1mFN/`.
- Fresh focused backend gate: **79 passed, 0 failed, 0 skipped**, across campaign,
  Sandbox QA and integration suites. This is local authorization/workflow
  evidence, not live Apple offer fulfillment.

Next bounded gate: obtain a genuine signed-in app status request for the same
owner, then verify a separately bounded Sandbox window before any explicit Apple
purchase. An enabled status lookup fetches fresh signed Apple history and may
record an already accepted benefit; it does not issue a signature or grant normal
subscription access. Every historical transaction must still match the owner.
The current active monthly plan can only use a verified same-monthly-product
next-billing promotional offer; annual crossgrade and immediate expired-user
cases are separate. Do not manufacture a session or relax ownership checks to
complete this gate. Apple introductory configuration, actual purchase/lifecycle
verification, distribution, push and publication remain open.

#### Same-owner live status and signer compatibility receipt — October 9

The user explicitly approved deployment of the focused compatibility fix to
`storekit-complimentary-offers` and another isolated status-only check. No purchase
or public campaign was authorized. App Store Connect's denied origin was not
accessed through another browser, native automation, cookies or raw requests.

- A Debug-only, physical-device, explicit-opt-in observer records fixed,
  content-free metadata for the existing status request. It binds the response
  to that request's actual bearer-session owner and checks the final session.
  It adds no request, prepare, purchase or claim. No tokens, JWS, signatures,
  owner identifiers, chart text or ink are recorded. Simulator/Release/default
  launches do not enable this observer.
- The diagnostic revision remains **1.2.1 (75)**, with executable SHA-256
  `47a5c917574fca7e5cc95127b1e2f534cccbcfa0fa281173e846732eedadbae8`.
  **48 native tests passed, 0 failed, 0 skipped**, verified from the result
  bundle. Its Development signature, installation and launch passed. This is
  not a distribution artifact or renewed physical editor/Pencil acceptance.
- The first enabled status check returned `campaign_not_configured`. Synthetic
  local probes reproduced Deno/Node P-256 curve-name differences, the pinned
  Apple SDK's JWT validation incompatibility, and Deno 2.1.14 ignoring the
  requested P1363 signature encoding. The fix accepts only equivalent P-256
  aliases and converts strictly validated DER to the required 64-byte JWT
  signature. Legacy promotional signatures remain DER. Only the offer-owned
  default client overrides JWT creation; ordinary claims and JWS verification
  remain unchanged. The actual hosted runtime version was not independently
  identified; local Deno 2.1.14 is reproduction evidence, not that identification.
- Final backend gates: **203 Node tests passed, 0 failed, 0 skipped**;
  **150 Deno tests plus 54 nested steps passed, 0 failed**. The pinned Apple
  SDK/default-factory Deno composition test verifies status and V2-history
  JWTs with native WebCrypto and an intercepted test-only transport. Synthetic
  tests alone are not Apple fulfillment evidence.
- Deployed source bytes match the tested files: exactly two existing runtime
  files changed and one runtime module was added. JWT enforcement remains on;
  the other six functions' code hashes and JWT flags are unchanged. Secret
  changes can advance platform deployment versions; versions alone are not
  evidence of another service's source change.
- The first post-deploy launch produced no status receipt during the bounded
  observation and was closed. Its begin-only startup trace does not establish
  which await stalled. An ordinary launch then completed startup in five
  seconds, and a disabled diagnostic launch returned both products normally.
  The user confirmed a normal app screen; no credential/account change was made.
- The final future-start run returned **four genuine status responses** for
  monthly/annual at **18:01:50–18:01:53 UTC**, all with matching owner/schema/
  campaign/product, `enabled=true`, `reason=campaign_not_started`, and no
  signature or attempt. Server receipts are HTTP 200, 2.47–3.27 seconds. A
  fresh read-only check confirms one valid owned Sandbox subscription seed.
  The verified request path fetches and verifies nonempty owned Apple status
  and complete history before returning this decision. This establishes the
  live history/status gate, not promotional eligibility or offer acceptance.
- Disablement was verified before removing temporary dates. Final baseline:
  **disabled**, no start/end dates, explicit Sandbox and single-owner QA guard
  retained, ordinary Apple environment/signing-key digests unchanged, and
  campaign accounts/attempts **0/0**. The final normal launch completed startup
  with the opt-in observer off. No purchase, signature or benefit was created.
- Final read-only data comparison retains the same **19 saved files, 5 charts,
  11 PDFs, 1 setlist and 70 handwriting examples**. Chart content/ink and
  PDF/setlist/profile/evaluation bytes are unchanged. Only ordinary cloud
  backup/verification timestamps and the performance trace changed.

Protected local receipts: `/private/tmp/iChartOfferStatusQA-20261009.Tyi7d7/`.
Next gate requires separate approval for an explicit Sandbox promotional-offer
acceptance test, followed by verified scheduling/benefit/renewal and recovery.
Fresh/lapsed introductory eligibility, active annual same-plan handling,
distribution, push, upload and publication remain separate open gates.

#### Sandbox monthly acceptance setup — October 9; closed before Apple sheet

The user approved setup of the next explicit Sandbox acceptance test. A fresh
server read confirms the same QA owner still has an active monthly Sandbox plan,
automatic renewal, a valid original-transaction seed and matching purchase token.
No account, Apple login, transaction history or ordinary subscription was changed.

After verifying the closed baseline, dates were staged while disabled and the
single-owner Sandbox test was enabled last. Its temporary claim window is
**2026-10-09 18:09–18:45 UTC (11:09–11:45 AM Pacific)**, not the public release's
90-day window. Normal Apple environment and signing-key digests remain unchanged.
The existing diagnostic app was cold-launched; no new build or deployment.

Genuine monthly status responses at 18:10:57 UTC are enabled, available,
scheduledPromotional and nextBillingEvent, with matching owner/schema/campaign/
product and no signature or attempt. Annual status at 18:11:00–18:11:01 correctly
rejects the active monthly account with active_subscription_same_product_required.
The observer's `reason=other` is its nil/unknown sanitization bucket, not a captured
raw server failure. Bootstrap completed. Campaign accounts/attempts remain 0/0.

Handoff: Library Settings → Plan → Pro Subscription → One Month Free →
**Review Free Month at Renewal**. Use the gift offer, not a standard paid plan.
The tap rechecks fresh status and actual StoreKit metadata before preparing an
authorization and opening Apple. Ask for the purchase-sheet screenshot before
manual confirmation to verify the Sandbox/no-charge notice, same monthly plan,
free-month timing and subsequent paid-monthly terms. Do not infer those displayed
terms, preparation success, acceptance or scheduling from the available status.
Protected setup receipts share `/private/tmp/iChartOfferStatusQA-20261009.Tyi7d7/`.

Later manual result: the user tapped the gift button, it disabled and reenabled,
and no sheet appeared. At 18:13:53 UTC the existing opt-in trace recorded
status_request_failed with owner_match=true. No typed response or underlying
transport/HTTP category was retained. No matching completed offer-function
request was found in the bounded server-log window, and existing purchase
telemetry/queue was unavailable; neither absence proves a specific network/auth
cause. Campaign account/attempt/benefit counts remain **0/0/0**, so no purchase
authorization or benefit was prepared/recorded. Source places this status check
before prepare and Apple purchase.

The Settings gift handler discards the false result, while the failure message
is shown only below paid-plan/restore/manage/legal controls and can be off-screen.
This confirms a feedback-visibility defect, not the underlying request cause.
The campaign was disabled and verified, then dates were removed with baseline
digests/QA isolation verified. A normal app launch removed diagnostic opt-in.
Next scoped proposal: visible gift-card failure feedback and an opt-in fixed
failure category, followed by one bounded retry. No UI/code fix or new build was
performed by this diagnosis; no account reset, Apple history change, purchase,
deployment, push or public activation occurred.

#### Gift-button feedback and classified QA retry — October 9

User authorization: implement/install the focused visible-failure repair and
fixed-category diagnostics, then set up one controlled retry. This is not an
underlying network/auth repair or public campaign/release authorization.

- Settings and Upgrade now capture the failed gift action's nonblank existing
  unavailable message beside its matching offer button. An accessible warning
  and instruction point to the same manual retry button. If the card disappears,
  feedback remains before the paid plans. Success/cancellation do not show an
  error. Explicit gift, paid, Restore and Manage starts clear old feedback; no
  automatic retry, new purchase action or paid fallback was introduced.
- The opted-in physical-Debug status observer distinguishes fixed HTTP/relay,
  network, decoding, cancellation and unknown categories. Non-offer HTTP bodies
  retain only an allowlisted status and fixed shape category. No body, URL,
  NSError userInfo, decoding path, raw error text or credential is logged.
  Owner mismatch/missing owner still suppresses response/error detail. The
  largest recorded event is bounded to 18 fields. Existing invocation executes
  once and returns/rethrows unchanged; Release/default and prepare/confirm paths
  are unchanged. These are local QA traces, not new production telemetry fields.
- Fresh native gate: `FocusedVerifiedTests.xcresult`, **85 passed, 0 failed,
  0 skipped**, independently read with xcresulttool. Includes feedback behavior,
  diagnostic privacy/categories/owner gates, complimentary policies/integration,
  catalog and ordinary entitlements. The initial synthetic CodingKey fixture
  did not compile; it was corrected before this fresh passing run. That failed
  compilation is not counted as validation.
- Development-signed **1.2.1 (75)** revision installed without uninstall/reset;
  strict signature, exact backend/app/team/device provisioning checked. Executable
  SHA-256: `20b8f71ed2fa343e0f8bbdaed0eb79c28dc3daab614a8ac7e9075a0deb375b09`.
  This supersedes the earlier diagnostic revision's executable receipt, not the
  frozen distribution artifact. No archive/upload/push occurred.
- Fresh before/after read-only comparison: **19 files, 5 charts, 11 PDFs**;
  chart content/ink and PDF/setlist/profile/evaluation bytes unchanged. Changes
  are limited to ordinary backup/sync/verification timestamps and local trace.
  Disabled-campaign startup completed at **18:34:07 UTC**, with four correctly
  owner-bound monthly/annual `campaign_disabled` responses and no attempt/signature.
- Then staged/verified the temporary **18:35–19:05 UTC** window while disabled,
  enabled last, and verified explicit Sandbox + exact single-owner guard and
  unchanged ordinary environment/signing-key digests. Fresh launch at 18:36:40 UTC;
  status responses at **18:36:47–50 UTC** report monthly available,
  `scheduledPromotional` / `nextBillingEvent`, and annual ineligible with
  `active_subscription_same_product_required`. Startup completes; account,
  schema/campaign/product binding pass. Ledger remains **0 accounts, 0 attempts,
  0 benefits** before human retry. No tool initiated a purchase.

Evidence: `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`. Next physical step:
Settings → Plan → **Review Free Month at Renewal**, once, then capture the Apple
sheet **before confirming**, or the new inline error. The previous request's
root cause, this new visible failure's device acceptance, and Apple benefit/
renewal fulfillment remain open. Local feedback is product-bound rather than
owner-bound; an account switch while the view stays alive can retain a prior
generic message. This narrow pass added no new auth dependency.

**Physical Apple-sheet gate — October 9, 18:40 UTC:** the user supplied
`IMG_0300.PNG`. The Sandbox Apple sheet is awaiting Touch ID and displays
**one month free starting October 10, then $7.99/month starting November 10**,
with the explicit testing/no-charge notice. This verifies sheet presentation
and displayed same-plan next-billing terms, not acceptance or a recorded benefit.
The readonly ledger has one monthly `prepared` account and one
`scheduledPromotional` attempt created at **18:40:32.252 UTC**, no benefit and
no access interval. The tap's status and prepare requests both returned HTTP
200; server execution times are **3,886 ms and 2,417 ms** (6,303 ms combined).
That establishes server work contributing to the reported delay, not total
tap-to-sheet latency or the cause of the earlier failed tap. There are no
per-phase client timers or sheet-presentation timestamp. The app/sheet and
campaign were left untouched during the readonly check. Next: the user approves
the displayed Sandbox terms, then verify Apple scheduling, ledger confirmation
and recovery before closing the restricted window. No purchase was approved by
an agent, and no build/deployment occurred in this inspection.

#### Apple acceptance and unfinished recovery — October 9

The user subsequently approved Apple's Sandbox sheet. This receipt supersedes
the earlier awaiting-approval/resume instructions; **do not repeat the purchase**.

- The verified notification pipeline recorded `OFFER_REDEEMED` at
  **18:45:40.873 UTC**. The current QA subscription is monthly, active,
  Sandbox-only, auto-renewing, with a matching app-account token and an existing
  entitlement expiry of **October 10, 15:42:40 UTC**. A fresh read after the
  recovery check confirms those values. Apple acceptance is established;
  iChart benefit fulfillment and actual free-period/renewal behavior are not.
- The ledger remains **one prepared account, two attempts, zero benefits**;
  access start/end and benefit-recorded dates are null. The pending purchase
  preference still identifies the same QA owner/monthly scheduled-promotional
  attempt. No preference or ledger was erased or manually promoted.
- One controlled normal-app relaunch at **18:52:06 UTC**, bootstrap complete
  **18:52:14**, received four correctly owner/schema/campaign/product-bound
  status responses with `pending_campaign_offer_not_verifiable`. This means
  the pending known-offer renewal branch failed a validation guard. Current
  diagnostics do not distinguish which guard failed; do not weaken Apple term,
  expiry, product, ownership or renewal checks based on a guess.
- Read-only before/after saved-content comparison passes for **19 files,
  five charts, 11 PDFs**: chart content/source ink and PDF/setlist/profile/
  evaluation bytes remain unchanged. A separate strict full-state comparison
  failed: device entitlement changed from `studioSubscription`/`proActive` to
  `free`/`unavailable`, and selected-chart state changed. Backup/sync timestamps
  and local trace also changed in the broader preinstall comparison. Do not
  relabel this as a fully preserved or accepted access state.
- Source review finds physical-device claim-failure handling can assign
  unavailable and return before a fresh remote entitlement read. Gift purchase
  also defers applying a successful ordinary claim until gift confirmation.
  Pending-offer refresh itself does not directly clear paid entitlement. The
  actual refresh branch taken still needs fixed-category evidence; the live
  mismatch is not proof of a particular branch or bad Apple field.
- New preparation was first cut off at **18:50 UTC**, while same-owner recovery
  remained available for the controlled relaunch. After collecting that failure,
  enabled was set **false**, both temporary date secrets removed, and Sandbox/
  exact-owner guards plus ordinary environment/signing-key digests verified
  unchanged. Full disablement now suspends campaign reconciliation, without
  deleting the pending attempt or changing the verified ordinary subscription.
- This verification changed no app/backend source behavior and did not build,
  install, initiate another purchase, deploy a new repair, push, archive or upload.
  Next scoped work: identify the failed pending-offer predicate, repair verified
  recovery, and keep independently verified paid access separate from a pending
  gift. Fresh diagnostics/deployment and any new QA window need scoped approval.

Private receipts: `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`, including
`config-final-closed.json`, `recovered-content-only.json`, preserved accepted/
recovered app-container snapshots and the recovery trace. The content-only
receipt explicitly says `fullStatePreservationPassed: false`.

#### Access recovery and pending-term diagnosis — October 9

The user authorized the focused confirmation/access repair, keeping the public
campaign disabled. The ordinary claim path now checks request and result owner,
and reads a fresh, same-owner remote entitlement if claiming fails or returns no
usable row. A successful ordinary claim is applied before a separate gift
confirmation; a pending gift does not itself create Pro access. Request-local
clients use the genuine session rather than allowing the shared SDK adapter to
substitute a token during an asynchronous request.

- The first repair gate passed **104 native tests, 0 failures/skips** and
  **210 endpoint tests, 0 failures/skips**. The fixed-category follow-up passed
  **105 native tests and 211 endpoint tests**, also with zero failures/skips.
  Native counts were independently read with `xcresulttool`. Compile-only
  fixture failures remain separate failed receipts, not validation.
- The Development-signed **1.2.1 (75)** revision installed in place and launched.
  At **19:21 UTC**, saved device access changed from unavailable to
  `studioSubscription` / `proActive`, with the existing server expiry and
  auto-renew flag. No local gift clock or cached entitlement was used as a grant.
- Saved-content checks pass for all **19 files / five charts / 11 PDFs**;
  chart content and ink, PDF, setlist, profile and evaluation data are unchanged.
  Entitlement and backup/sync timestamp changes are explicitly separate from
  content preservation. The comparison did not claim an unchanged full state.
- A separate, opt-in, singleton-owner Sandbox diagnostic used fresh verified
  Apple status and emitted fixed booleans/categories only. Two matching reads
  at **19:31:59 UTC** identify `PAY_UP_FRONT`, a full `P1M` offer, zero next-billing
  price, the known monthly offer, same product/chain, active unrevoked unexpired
  ownership, auto-renew on and a valid future renewal date. No raw Apple payload,
  identifier, JWS or arbitrary upstream error was added to diagnostic output.
- Diagnostic endpoint version **29** has JWT verification enabled. Only the
  campaign and runtime files differed from the prior deployed bundle; ordinary
  subscription claim/notification endpoints were not deployed. Its diagnostic
  cutoff was removed after collection; the original deadline also expires
  fail-closed. Campaign enabled remains false and purchase date secrets absent.
- Apple's public definitions connect a next-billing price including the offer
  discount, a full one-month `P1M` duration, and an upfront price covering that
  duration. A pending-only allowance for exact `PAY_UP_FRONT` + `P1M` + numeric
  zero is therefore an economic-policy inference for a scheduled zero-charge
  month, not a claim that the enum equals `FREE_TRIAL`. Completed redemption
  still requires actual verified transaction terms/dates; longer, positive,
  missing, nonnumeric or unknown-mode offers remain rejected.

The user separately approved a short, QA-account-only recovery check for the
already accepted purchase. Its guarded implementation passed **469 server
tests** and initially **112 native tests**, with zero failures/skips. The final
client acknowledgement revision passed **113 native tests**, zero failures/skips,
verified with `xcresulttool`, then was signed, installed in place and launched.

- Existing ledger recovery passed at **19:44:25.521 UTC**: state is scheduled,
  benefit is recorded, start is **2026-10-10 15:42:40 UTC**, and actual end remains
  null. Attempt count stays **two**; no new reservation/purchase/signature occurred.
  Fresh reads after subsequent acknowledgement retain the same first benefit.
- First native recovery read displayed the verified schedule but retained its
  local pending marker. The follow-up separates marker acknowledgement from
  Apple transaction finishing: only a valid matching recovery-only scheduled
  response, stable owner and unchanged pending snapshot may clear that marker.
  It cannot finish a transaction without the existing verified StoreKit path.
- Bound device reads at **19:50:21–25 UTC** report the same scheduled monthly
  benefit with `enabled:false`, no signature and matching schema/product/owner.
  The local marker is now absent without any manual preference edit. Pro remains
  active with its preexisting expiry and auto-renew setting. Annual requests
  remain disabled and cannot crossgrade the monthly subscription.
- Final saved-content comparison still passes for **19 files / five charts /
  11 PDFs**, including ink, setlists and retained research/profile data. No app
  uninstall/reset or chart/profile mutation occurred. Backup/sync timestamps and
  QA traces are not confused with content changes.
- Both temporary QA cutoffs were removed, public enabled remains false, purchase
  dates remain absent, and ordinary environment/signing digests are unchanged.
  The tested endpoint was refreshed to version **37**, JWT verification enabled,
  with unchanged source from the successful recovery deployment. A fresh
  post-close check at **19:52:55–56 UTC** passes: four owner-bound monthly/annual
  responses report `campaign_disabled`, no attempt and no signature. Warm isolate
  configuration is not assumed to update solely from secret removal. The iPad
  was then relaunched normally with opt-in diagnostic flags omitted. The final
  post-relaunch saved snapshot retains Pro active/auto-renew and passes the
  same 19-file saved-content comparison; no renewed UI/Pencil acceptance is
  inferred from that state read.
- Final Development executable SHA-256:
  `2b9b7aaaac84f0fbe959c688002652a61a1e4c06711a369c2876678d6efefeda`.

This passes **existing monthly scheduling/confirmation recovery**, not actual
free-period redemption/paid renewal or another customer cohort. No public
activation, subscription change, push, archive or upload is authorized by this
receipt. Do not repeat the already accepted purchase.

Private receipts remain `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`.
Primary field contracts: [renewal price](https://developer.apple.com/documentation/AppStoreServerAPI/renewalPrice),
[offer duration](https://developer.apple.com/documentation/appstoreserverapi/offerperiod),
and [upfront payment mode](https://developer.apple.com/documentation/storekit/product/subscriptionoffer/paymentmode-swift.struct/payupfront).

#### Completed-offer and billing-boundary local repair — October 9

The next-gate audit found a conditional failure: an actual configured promotional
`PAY_UP_FRONT` / `P1M` / numeric zero transaction was rejected even though those
terms could establish the already accepted zero-charge month. The rejected
known offer still consumed its ledger under the existing first-benefit policy.
This was reproduced with local fixtures, not an observed completed Apple event.

- Completed promotional verification now requires the exact product's offer,
  `P1M`, numeric actual transaction price zero and either `FREE_TRIAL` or
  `PAY_UP_FRONT`. Introductory selection/acceptance stays `FREE_TRIAL` only.
  Missing, string, positive, negative, nonfinite, other-mode, other-period and
  wrong-product offer terms do not establish a valid complimentary result.
- Completed dates come only from finite, in-range, ordered Apple transaction
  purchase/expiry timestamps. A prospective zero renewal quote or estimated end
  is not sufficient. Refunded/upgraded/invalid known gifts remain consumed and
  unavailable; an ended valid gift remains consumed with its original dates.
- Native prepared-attempt recovery now accepts both a still-scheduled response
  and an actually redeemed response at a billing boundary, retaining enabled/
  non-recovery scope and exact campaign/product/decision/activation/offer/attempt
  bindings. Estimates cannot pass as completed dates. This validates campaign
  confirmation only; ordinary subscription authority continues to grant access.
- Existing SQL already supports same-owner/product/chain/attempt
  scheduled-to-redeemed recording and immutable redeemed replay. No migration,
  ordinary authority/auth/runtime change or disabled recovery extension was made.
- Final focused gate: **115 native tests, 0 failures/skips**, verified from
  `CompletedBillingFinalTests.xcresult`; **487 server tests, 0 failures/skips**,
  with receipt `completed-billing-endpoint-tests.log`. Handler/adapter lifecycle
  fixtures use mocked I/O and do not claim live PostgreSQL/Apple completion.
- Physical iOS **build 75** compilation passed with signing disabled:
  `CompletedBillingDeviceCompile.xcresult` / `completed-billing-device-compile.log`.
  This is an unsigned local compile, not a signed/installed/accepted revision.
  Existing unrelated deprecation/concurrency warnings remain; this is not a
  warning-free repository claim. The changed production sources at this gate:
  native model SHA-256 `08e0800cf394fb884d5da53fdc0fac672a7f56ba85de78e55b60615e9974bc43`;
  campaign module SHA-256 `3f4088e6dc9ad2ea84396dc71bbed75ed8880cfdba1f8bbef10e017a6f3dcc9e`.
- Read-only database follow-up retains scheduled monthly Sandbox state, two
  attempts, actual end null and the original benefit-recorded timestamp. The
  ordinary entitlement remains active/auto-renewing with expiry **October 10,
  15:42:40 UTC**; no newer notification is recorded than the accepted offer.
  Database freshness is not a new App Store Server API fetch.
- Fresh protected-configuration digest checks all pass:
  `completed-billing-config-closed.json` confirms disabled campaign, unchanged
  singleton Sandbox guard, absent purchase/diagnostic/recovery dates, and
  unchanged ordinary Apple environment/signing key. Only booleans were retained;
  no credential values were printed or changed.

These changes are local, not deployed/installed. Campaign remains off; purchase,
diagnostic and recovery windows were not opened. No new purchase, account switch,
Sandbox-history reset, production annual subscription change, push or upload.
The existing purchase's signed start is **October 10, 8:42:40 AM PDT**. Next real
gate: observe its completed signed transaction/actual zero-charge term and then
paid renewal. A focused deployment and any bounded reconciliation window need
separate approval; do not repeat the accepted purchase. New/returning/annual
cohorts still need isolated legitimate QA histories and scoped purchase approval.

Private receipts: `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`.
Primary contracts: [actual transaction price](https://developer.apple.com/documentation/appstoreserverapi/price),
[offer duration](https://developer.apple.com/documentation/appstoreserverapi/offerperiod),
and [discount payment mode](https://developer.apple.com/documentation/appstoreserverapi/offerdiscounttype).

#### Completed-offer focused inactive deployment — October 9

The user approved continuing after the explicit request to deploy the verified
completion check only, with the campaign disabled and all purchase/recovery
windows closed. This supersedes the local-only backend status in the preceding
receipt; the native revision is still unsigned/uninstalled.

- Pre-deployment gate reran **487 server tests**, zero failures/skips. Only
  `complimentary_offer_campaign.mjs` differed from the prior deployed 12-file
  bundle. All other imported source files matched. No schema/auth/runtime or
  ordinary subscription endpoint source change was bundled.
- `storekit-complimentary-offers` alone deployed to **version 38**, ACTIVE with
  `verify_jwt:true`. All 12 deployed files exactly match local tested bytes.
  All six other services retain their prior code hash/version/JWT/status.
  The deployment reused pinned dependencies and ordinary signing configuration.
- Protected configuration checks before/after pass: disabled campaign, same
  singleton Sandbox guard, purchase/diagnostic/recovery dates absent, ordinary
  Apple environment/signing key unchanged. No secrets were changed or printed.
- The existing installed build's opt-in status observer received four genuine
  owner/schema/campaign/product-bound responses at **22:11:11–12 UTC**, covering
  monthly and annual. All report disabled/unavailable with `campaign_disabled`,
  no signature and no attempt. This demonstrates disabled authenticated
  compatibility, not completed transaction acceptance through the live branch.
  The server's disabled guard does not fetch Apple history, sign or record a
  benefit in this smoke. App bootstrap still performs ordinary verified claim/
  refresh and normal backup; the whole relaunch is not called read-only.
- The iPad was returned to a normal launch with all QA observer flags omitted.
  Fresh before/after content checks pass for **19 files / five charts / 11 PDFs**,
  including all source ink, setlists, correction memory and parked profiles/
  evaluation data. Selection did not change. Backup/sync/verification timestamps
  and local trace changed separately; no app reinstall/reset occurred.
- Strict entitlement identity failed: the prelaunch saved Pro status lacked
  expiry/auto-renew fields; the verified normal refresh populated the existing
  server expiry **2026-10-10 15:42:40 UTC** and auto-renew true. Plan and Pro status
  stayed the same. The absence's cause is not established; a Debug preview can
  produce this shape but is not evidence the user selected it. The original
  strict failure is preserved, and the separate current-authority check passes.
  Do not relabel this as an unchanged full state.
- A fresh ordinary server row at **22:11:08.965 UTC** remains active and
  auto-renewing. Gift ledger remains scheduled with original start/first benefit,
  two attempts and actual end null. No new purchase, reservation, offer signing,
  public campaign activation, recovery window, real annual modification, push,
  archive or upload occurred.

Private receipts in `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`:
`completed-billing-deploy.log`, `completed-billing-postdeploy-source.json`,
`completed-billing-postdeploy-config-closed.json`,
`completed-billing-live-verified-smoke.json`,
`completed-billing-strict-access-comparison.json`,
`completed-billing-content-comparison.json`, and before/normal-launch snapshots.

Next genuine gate remains the existing monthly purchase's signed start:
**October 10 at 8:42:40 AM PDT**. Require the actual signed zero-charge transaction,
original dates and later paid renewal. This deployment does not open a window to
reconcile its ledger while disabled; any such bounded check requires scoped
approval. Do not repeat the accepted purchase. New/returning/active-annual Apple
cohorts and public introductory dates remain separately open.

#### Completed-offer native delivery — October 9

The user authorized continuing with the tested native confirmation change under
the existing build/install-only scope. This supersedes the unsigned/uninstalled
native status in the two preceding historical receipts; it does not change
backend campaign configuration or authorize another purchase.

- The current native model SHA-256 still matches the **115-test** receipt:
  `08e0800cf394fb884d5da53fdc0fac672a7f56ba85de78e55b60615e9974bc43`.
  Independent re-reading of `CompletedBillingFinalTests.xcresult` confirms
  **115 passed, 0 failed, 0 skipped**. The existing **487-server-test** gate and
  deployed version-38 source remain unchanged; no source fix was added in this
  delivery step.
- Physical Debug build **1.2.1 (75)** succeeded with the existing Development
  identity/team/device provisioning. `codesign --verify --deep --strict` passes;
  profile app/team/device bindings, Development status and validity pass.
  Existing unrelated deprecation/concurrency warnings are not called resolved.
  Signed executable SHA-256 is
  `e68f2820e8b0f1c583d59f09c8a917f3b36d832c9899593a97471a7702884e38`.
- Apple device installation and normal-launch JSON receipts report success.
  The launched executable URL matches the newly installed bundle, with no
  diagnostic/purchase arguments or environment flags. No uninstall, app-data
  reset, account switch or signing-credential change occurred.
- Fresh before/after snapshots preserve all **19 files' saved content: five
  charts/source ink, 11 PDFs, setlists, correction memory and parked profile/
  evaluation data**. Selected chart and current plan/status/expiry/auto-renew
  fields are unchanged. Backup/sync/verification timestamps and trace changed
  during normal bootstrap; strict full-entitlement/full-state identity is not
  claimed. This check is not fresh Pencil interaction or visual acceptance.
- A fresh ordinary server verification at **22:22:01.351 UTC** retains active,
  auto-renewing Pro with expiry **October 10, 15:42:40 UTC**, matching the device.
  The gift remains scheduled with the original start/benefit timestamp, two
  attempts and actual end null. This is not actual gift redemption or renewal.
- Fresh protected-digest checks confirm disabled campaign, unchanged singleton
  Sandbox guard, absent purchase/diagnostic/recovery dates and unchanged ordinary
  environment/signing key. No new purchase, campaign activation, recovery
  window, push, archive or upload occurred.

Private receipts in `/private/tmp/iChartOfferButtonQA-20261009.SPko45/`:
`CompletedBillingSignedDeviceBuild.xcresult`,
`completed-billing-signed-device-build.log`,
`completed-billing-native-profile-verified.json`,
`completed-billing-native-install.json`,
`completed-billing-native-normal-launch.json`,
`completed-billing-native-content-comparison.json`,
`completed-billing-native-install-verification.json`,
`completed-billing-native-config-closed.json`, and the fresh before/after
native-install snapshots. The verification helper retains separate content,
access, install/launch and not-yet-observed Apple/Pencil boundaries.

Next genuine gate remains **October 10 at 8:42:40 AM PDT**: observe the existing
purchase's actual signed zero-charge transaction and original term, then its
later paid renewal. Do not repeat the purchase. Any bounded reconciliation while
the campaign is disabled, new/returning/annual cohort purchases, introductory
dates and public activation remain separately authorized/verified steps.

#### Objective cleanup implementation receipt — October 7

The live-price badge, cloud feedback and QA presentation rows above are now
implemented locally. The free-month and handwriting/evaluation choices were
presented to the user but are **not yet decided**; no default selection or lack
of an answer authorizes offer activation or changing existing profiles.

- Cloud progress distinguishes backup from restore. A successful restore receipt
  remains visible after a later automatic backup; it separates available remote
  charts from the resulting local library count. An empty remote library is not
  reported as newly restored local charts. If concurrent local edits prevent
  the existing conditional apply, the receipt says restore was not applied and
  the current library was retained.
- Errors use typed session/permission/network/storage/encoding categories and
  fixed stages, not arbitrary error text. Permission failures no longer assert
  that signing in again will fix them. Account/access reset clears operation
  feedback, and superseded terminal success/failure cannot overwrite that reset.
  These guards cover displayed feedback; underlying cancellation, merge/apply,
  backoff and scheduling behavior were not redesigned.
- Cloud telemetry uses the existing `error_code` and `reason` fields, with
  category and `cloud_stage_<fixed stage>` values. No raw error descriptions,
  chart names or chart content were added. The default-off consent gate applies.
  The existing ingest sanitizer retains the fixed values and drops chart-title
  input; no ingest allowlist/schema update or production deployment occurred.

Evidence directory: `/private/tmp/iChartPreBuildCleanup-20261007.KYbrIJ/`.

- Final native focused gate: `CleanupFinalTests.xcresult`, **95 passed,
  0 failed, 0 skipped**, verified with `xcresulttool`. This covers product
  comparison, entitlement regression checks, cloud feedback/store behavior,
  existing merge/backoff/state tests, project configuration, library flow and
  privacy wiring. Earlier `CleanupTests.xcresult` passed 94 cases before adding
  the final stale-failure display regression case; it is not the final receipt.
- SwiftPM: `swiftpm-cleanup.log`, **46 passed, 0 failed**. These Foundation
  product/feedback/merge/backoff/entitlement cases overlap the native gate and
  are not additional distinct coverage. The terminal-state follow-up changed
  only native store code/tests and is covered by the final native receipt.
- Existing local ingest suite: `telemetry-ingest.log`, **16 passed, 0 failed,
  0 skipped**. A separate local sanitizer probe confirmed stage/category
  retention and chart-title exclusion. No live customer records were queried.
- `xcodegen generate` and `git diff --check` passed. Pinned dependency resolution
  was retained; no package upgrades. Existing deprecation/tool warnings remain;
  this is not a warning-free build claim.

Version remains **1.2.1 (74)**. No build-75 preparation, physical iPad install,
new distribution archive/export, live cloud recovery pass, offer activation,
GitHub push, store upload or publication was performed. Local compilation and
tests do not replace the eventual physical UI/keyboard/Pencil checks or refresh
the earlier frozen build-74 release acceptance.
