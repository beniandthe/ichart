# Explicit symbol ownership repair for personal teaching

This scoped app change addresses lesson intake, not recognition scoring. The
known-regressing ML candidates remain rejected/comparison-only. No shared
encoder, learned head, trust threshold, parser, live grouping rule, or reserved
writer evidence is changed by this work.

## Observed gap and implementation contract

Teach Symbols previously exposed only the immutable pieces proposed by
`StrokeClusterer`. An incorrectly merged/split piece had to be skipped; the
user could not repair its membership before explicitly labeling it. That
blocked correctly supervised glyph lessons even when a saved whole-chord
correction was available.

The shared Saved Examples flow now permits editing complete source-stroke
membership. Both chart styles route through that same flow. Selection operates
on the immutable, normalized/bounded saved example, not raw page-space ink.

- Proposed groups preserve original ink and have no preselected labels. If a
  proposal cannot safely partition its source, all source strokes remain
  available for manual selection, not an invented replacement partition.
- Adjusting a piece can separate merged glyphs or join fragmented multi-stroke
  glyphs. Selecting a new piece explicitly transfers its strokes out of other
  pieces. Any changed group's label is cleared; untouched groups keep theirs.
- Groups are disjoint, nonempty, in range and limited to sixteen. Acquisition
  order is restored within each selected group. Exact original point, bounds,
  and available timing values are copied into the review; no point/trajectory
  trimming occurs. The preexisting profile storage normalization is unchanged.
- Unassigned strokes stay visible and available. Removing a draft piece only
  unassigns it; it does not erase chart ink or remove existing lessons.
- Selection/cancel/opening are local draft operations. Only an explicit label
  and Teach operation persist a lesson. A single pen stroke spanning several
  symbols cannot be split here; teach a standalone example instead.
- Final saving retains generation/source equality, opt-out and evaluation-
  capture checks. Unknown legacy acquisition metadata remains unknown; tracked
  lessons inherit their parent intake rather than acquiring a fictional fresh
  writing session. Historical evaluations/profiles remain independent values.
- Conflicting labels for exactly equivalent normalized selected trajectories
  reject the batch. Every selected trajectory/label and the reviewed parent
  must survive the entire capped edit, otherwise nothing is saved. Identical
  same-label lessons deduplicate under the existing profile rule.

These are user-confirmed teaching labels, not independently adjudicated symbol
ownership, a new training-eligible corpus, or evidence that personalization
improves accuracy. Fresh comparisons in both chart styles and across writers
remain required before recognition-quality or shipping claims.

## Executed verification

The final focused iPad Simulator gate executed **91 tests: 91 passed, zero
failed, zero skipped**, confirmed from both the xcresult summary and executed
test tree. The first gate also passed 91; an additional fallback assertion was
added to an existing test, then the complete cached gate was rerun. These are
91 unique tests, not 182 independent cases or handwriting samples.

| Class | Executed |
| --- | ---: |
| PersonalInkSymbolSelectionDraftTests | 15 |
| PersonalInkSymbolTeachingTests | 10 |
| PersonalHandwritingSymbolTeachingModelTests | 8 |
| PersonalInkLearningLineageTests | 15 |
| PersonalHandwritingModelTests | 14 |
| ProjectConfigurationTests | 29 |
| Total | 91 |

Synthetic tests verify exact stored-source bounds/timing/acquisition order,
disjoint transfer/merge/split/removal, affected-label invalidation, no-op behavior,
partial coverage, the actual oversized-proposal fallback, invalid edits and
group limits, stale/reset/opt-out rejection, contradictory-label and per-label
batch-cap rejection, deduplication, persistent reload and unchanged historical
journal bytes. Controlled features verify the repaired multi-stroke lesson
reaches the learned comparator while its generic ranks remain unchanged. This
is wiring evidence, not fresh transfer or handwriting accuracy.

The actual teaching and selection SwiftUI views were rendered and their
attachments visually inspected at 820x1180 and 1180x820 points. Visible content
is readable without horizontal clipping; lower selection rows are in a scroll
view. Geometry tests check direct original-index hits for isolated lines,
dots/repeated points/background and explicit ambiguity at overlaps. These are
synthetic hosted views, not complete navigation/touch/Pencil acceptance on a
physical iPad. No live app/profile or natural handwriting was inspected or
relabeled in this pass.

Xcode 26.6 / 17F113; existing arm64 iPad (A16) Simulator
`0D3454BE-1A21-4910-8FD6-FFD3EB43E908`, iOS 26.5 / 23F77. Tested bundle:
`com.ichart.app`, version 1.2.1, build 51. Project regenerated from
`project.yml`, explicit `iChart.xcodeproj`/`iChart` scheme, generated Debug
configuration, signing disabled, serial tests and isolated DerivedData. The
generated app/test target compiler invocation uses `-O`; there was no global
optimization override. Existing deprecation/actor-isolation/build warning debt
is retained in the logs; this is not a warnings-clean build claim.

Scoped independent code review covered selection, stale callback, atomic-save,
and provenance behavior. A retained row callback hazard was fixed with draft
revision guards before the gates. The review is not independent accuracy proof.
Native reader/grouper byte hashes remain unchanged:

- Reader: `f8488aa951f922afb7df7cfb1f20965d623ac46e751eb8d9349005feb598cee7`.
- Grouper: `a70f74bfa099bd04c15a39969e21c2ce683c76721dac7da2a6186e0779053474`.

## Evidence and remaining requirements

Temporary gate root:
`/private/tmp/iChartSymbolSelection-20261002.HdhJ0e`.
Durable root:
`/Users/benirossman/.local/share/ichart/recognition-development/symbol-selection-20261002.G9ruQi`.
The preserved result bundles, executed summaries/trees, logs, attachments and
tested source snapshots are separate from prior failed-model experiments and
real user profiles. Original evidence is retained, not deleted.

The personalized ML quality goal remains active. This repairs supervised
lesson intake; it does not eliminate the measured fresh/untaught-symbol
regressions or establish automatic glyph ownership. A physical-device flow
check and genuinely fresh paired handwriting in both chart styles remain
required. Existing profile data, chart ink and historical evidence are not
migrated or rewritten. During the Simulator implementation pass, no new
encoder/head fitting, model activation, physical device build/signing/install,
telemetry change, commit, push, deployment or release occurred.

Worktree: `recognition-generalization-reset`; branch
`codex/recognition-generalization-reset`; base HEAD
`160aa31594903508e241802e21ca83ec447de849` plus retained uncommitted work.

## Physical-device build preparation — 2026-10-02

The unchanged tested sources were regenerated from `project.yml` and compiled
for generic iOS arm64 as development build **1.2.1 (54)**, bundle
`com.ichart.app`. The build succeeded with automatic Apple Development signing,
team `N6G8X4K46U`. A separate `codesign --verify --deep --strict` check passed
with the macOS trust store. The first sandboxed verification could not resolve
certificate trust (`CSSMERR_TP_NOT_TRUSTED`); the unsandboxed check verified the
same app without rebuilding or resigning. This is not a physical launch or
Pencil acceptance result.

The isolated device build uses the tested source package cache, disables
automatic package resolution, and overrides only the local build number and
explicit Debug comparison-package settings. The embedded comparison directory
is byte-identical to the retained build-53 directory, including all five files.
No rejected model was embedded, no learner was promoted, and no recognition
scoring, grouping, or threshold was changed.

- Executable SHA-256:
  `55a19e1976f0febcd26e8907e6344d3927cd6183f74b40a4207c7348c8de549a`.
- Comparison manifest SHA-256:
  `d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1`.
- Public anchors SHA-256:
  `e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed`.

Initially the connected iPad rejected the read-only app-metadata request because it had
not been unlocked recently. No current device profile, journal, or chart library
has therefore been copied in this phase. Installation remains deliberately
pending until those data can be preserved; the successful build does not imply
that build 54 is installed. The user was asked to unlock the iPad and leave it
awake. No credential or password was read or supplied.

The signed app, build and signature receipts, tested source snapshots, prior
91-test summary/tree, and device access-error receipts are preserved separately:
`/Users/benirossman/.local/share/ichart/recognition-development/symbol-selection-device-20261002.vdp0V4`.
Prior result bundles and original evidence remain in the earlier durable root.

The preparation-stage gate was to preserve the current profile, journal and chart library; install and
launch build 54; verify data preservation; then check the actual saved-symbol
selection/cancel/label/save flow on the iPad. Fresh handwriting transfer in both
chart styles and independent writers is still required for quality claims. No
commit, push, upload, production change or release is part of this preparation.

## Physical installation and preservation — 2026-10-02

After the user unlocked the iPad, current metadata verified iChart 1.2.1 (53)
on Ben's iPad, CoreDevice ID `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
The profile, evaluation journal, and library were copied twice before install;
all three second copies were byte-identical to the first. Both complete copies
were durably preserved before replacing the app. The profile contains 34
examples (16 glyphs, 18 whole chords); the journal contains 16 runs (12 complete,
4 cancelled); the library contains 19 charts.

The preserved, separately signature-verified build-54 app was installed and
launched successfully. Fresh device metadata reports **1.2.1 (54)**. The exact
process returned by launch, PID 8104, remained present during the subsequent
process check. An initial executable-path filter failed because CoreDevice
exposes that field as a URL; querying the launch receipt's numeric PID succeeded.
This diagnostic error was not an app crash, and no second launch/reinstall was
performed to work around it.

Post-launch copies verify:

- Profile bytes identical, SHA-256
  `73df2f92728d0b39cb9ea04c8ec6f1477b2ee50d9c6f36a15e44cbd97f121327`.
- Evaluation journal bytes identical, SHA-256
  `09388e072ffe1d3bbcf1f5f01763d376e31c40e795925340d75a3b1d0cc828aa`.
- All 19 chart objects and chart order are structurally identical, including
  every saved ink field. No PencilKit archive reserialization was observed.
  Library root fields `selectedChartID` and `entitlements` changed; all other
  root fields remained equal. This is a preservation check, not a causal
  explanation of those app-state changes or physical visual acceptance.

The install/launch/process receipts, both pre-install backups, post-launch
copies and structured preservation report are retained in the same private
`symbol-selection-device-20261002.vdp0V4` evidence folder. Private profile,
journal, and chart data remain outside the repository. Original evidence and
the build-preparation handoff are retained separately.

The physical saved-symbol selection/cancel/apply/label/save interaction has
not yet been accepted by the user. The first requested check deliberately stops
before Teach: open a saved whole chord, select original strokes for one symbol,
apply the local draft selection, and verify usability while leaving the stored
profile unchanged. Neither installation nor preservation proves automatic
ownership, fresh recognition transfer, user-agnostic accuracy, or ship readiness.
The full recognition goal remains active; no model promotion, commit, push,
upload, production deployment, or release occurred.

## Real-runtime lesson connection gate — 2026-10-02

Added one opt-in test,
`PersonalInkSymbolSelectionRuntimeIntegrationTests/testRepairedSelectionPersistsAndReachesPinnedRuntimeWithoutChangingSharedReads`,
to connect previously separate selection, app persistence, and actual-model
checks. Its source is an isolated synthetic three-stroke parent with explicit
test supervision, not private handwriting, an adjudicated glyph or fresh
accuracy evidence. Source indexes `[2, 0]` are explicitly selected; acquisition
order `[0, 2]` is retained and index `[1]` stays unassigned.

The test executes the actual asynchronous `PersonalHandwritingModel.teachSymbols`
operation and reloads `PersonalInkProfileStore`. It checks the normalized lesson,
exact original-stroke origin and input hash, inherited capture context, unchanged
parent, and historical journal bytes. The concrete pinned Core ML encoder and
local anchored comparator then consume the reloaded lesson. Support embeddings
and base scores match direct encoding; the existing app learned-comparison route
also exposes the anchored ranks. Complete shared ranks and app generic ranks
remain unchanged across teaching, while comparison ranks are finite. Fitting and
reading leave saved profile/journal and all five bundled resource files intact.
No winning-label, transfer, calibrated-confidence or quality assertion is made.

The isolated opted-in Debug Simulator gate executed **1 test: 1 passed, zero
failed, zero skipped**, verified in both the xcresult summary and executed tree.
Its final runtime marker is present, so the result is not only compilation, a
missing-resource skip or an early-return check. The earlier 91-test gate remains
separate evidence; it was not rerun or relabeled as this runtime gate.

Xcode 26.6 / 17F113, arm64 iPad Simulator
`0D3454BE-1A21-4910-8FD6-FFD3EB43E908`, iOS 26.5; test-host app 1.2.1 (54),
signing disabled. The project was regenerated from `project.yml`; isolated
DerivedData, serial execution, existing source-package cache and disabled
automatic package resolution were used. The explicitly embedded v2 package is
byte-identical to the preserved physical build-54 package. The initial sandboxed
xcresult reads were denied Xcode report-cache writes; reads with cache access
succeeded without rerunning the test. Existing compiler/runtime warnings remain
in the log; this is not a warnings-clean claim.

Temporary root: `/private/tmp/iChartSymbolSelectionRuntime-20261002.7pxFDo`.
Durable root:
`/Users/benirossman/.local/share/ichart/recognition-development/symbol-selection-runtime-20261002.YuTMmO`.
The result bundle, executed receipts, log, exact source snapshots and pinned
resource files are retained. No iPad actions or user-profile reads/writes were
performed during this gate; installed build 54 remains unchanged. Only isolated
synthetic comparison heads were fitted, not a user model or encoder weights.
The native reader/grouper hashes remain unchanged. Physical selection-flow
feedback, explicit teaching acceptance and genuinely fresh paired handwriting
remain pending. Recognition regressions and across-writer quality are not
resolved by this gate; the full goal remains active.

## Later physical checkpoint — three symbol lessons saved

A subsequent read-only device copy shows three explicit symbol lessons from a
saved `Bb7` parent: `B` from original indexes `[0, 1]`, flat `b` from `[2]`, and
`7` from `[3]`. The profile grew 34→37; every old example and the entire 16-run
journal remained unchanged. Source-formula comparison reproduces selected
geometry exactly; missing legacy timing/intake provenance remains unknown.
This verifies persisted membership, not visual label acceptance or learning
benefit. The user has been asked to confirm the selections and controls.

The existing 16-run journal limit blocked new captures. A bounded 32-run
load/start limit now retains all history, with the same 24 MB byte budget and
source bounds. Forty-two focused persistence/UI-model tests passed with no
failures/skips. Build 55, with unchanged recognition/model resources, was signed,
installed and launched; profile/journal bytes and all 19 chart objects were
preserved. Fresh queries are still pending, not yet accuracy evidence.

The exact checkpoint, tested bounds, device handoff and fixed pre-label
comparison plan are in
[`personal-symbol-transfer-checkpoint-2026-10-02.md`](personal-symbol-transfer-checkpoint-2026-10-02.md).
