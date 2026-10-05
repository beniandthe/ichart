# Fresh full-chord comparison, September 30

This is a one-writer development test of the customizable recognition pipeline,
not a new-writer accuracy estimate or permission to promote ML into live reading.
Branch: codex/recognition-generalization-reset, base 160aa31. Existing work and
private device evidence were preserved. No intended answer was used for fitting,
symbol selection, grouping, or a fallback.

## Frozen test and actual runtime

Both completed before-corrections runs contain six human-labeled, fresh captured
inputs and the same pre-test profile: 30 examples, comprising 12 symbol lessons
and 18 whole-chord lessons. There are no missing records, known-ink exclusions,
human-reported grouping problems, or missing original inputs in these runs.
The intended chords were B-flat-major-7, E-flat-7, D7, G-minor-7, F-sharp-7 and
C/E. Reported absence of slow ink or unexpected chart changes is user feedback,
not an instrumented latency or stability measurement.

The exact saved iPad inputs ran through the existing compiled Core ML visual
model and both personal learners using the Swift/macOS runtime. Neither the
model, frozen profile, hyperparameters nor top-choice composition rules changed
for this comparison. This verifies actual model inference on fresh iPad ink;
it does not establish physical-iPad ML interaction or recognition across writers.

| Complete exact reads | Simple | Rhythm | Combined |
| --- | ---: | ---: | ---: |
| Recorded standard app | 4/6 | 3/6 | 7/12 |
| Recorded app with personal suggestions | 4/6 | 2/6 | 6/12 |
| Shared ML | 1/6 | 2/6 | 3/12 |
| Original personal ML | 1/6 | 3/6 | 4/12 |
| Anchored personal ML | 1/6 | 2/6 | 3/12 |

All incorrect ML attempts failed strict complete-input composition rather than
becoming accepted wrong chords. They remain in the denominator: shared ML had
nine no-reads, original personal ML eight, and anchored personal ML nine.
The original personal learner gained one Rhythm C/E reading over shared ML;
the anchored learner did not retain that gain. Whole-chord rankings never
replaced failed symbol reads. These results are evidence against promotion.

The recorded app made a trusted E-flat-7 to F-flat-7 error in Simple. In Rhythm,
the personal suggestion displaced a correct but uncertain F-sharp-7 reading
with E-flat-major-7. Baseline recognition errors remain unresolved.

## General safety repair and fair scoring

- Live arbitration now retains every available standard reading as the default
  when a personal match disagrees. The personal alternative remains selectable.
  Agreement and review-only recovery of a missing native reading still work;
  personal matches do not gain automatic trust. This rule applies to every
  chord, provenance and edited-target state, not a special F-sharp-7 case.
- Policy identity is baseline-preserved-v3-personal-alternatives; pipeline is
  maximum-trust-v28-personal-alternatives-v1-2026-09-30. Replaying the recorded
  native decisions gives 4/6 Simple and 3/6 Rhythm with no personal regressions.
  That is counterfactual policy replay, not a fresh v28 recognition result.
- New comparison reports persist intended labels and recorded standard/personal
  results only as scoring evidence. One eligibility set is shared by all five
  methods. Missing attempts and unsupported inference inputs are not silently
  removed from a valid whole-chart denominator.
- Invalid labels, known ink, incomplete grouping/original input evidence, or
  contradictory counts withhold the whole-chart score. Zero eligible targets
  display an explanation rather than a meaningless 0/0 result. Old reports
  remain readable without invented scorecards.
- Reports retain the original whole-run SHA and add a versioned evaluation-only
  digest that omits later teaching flags/receipts. Teaching metadata cannot
  rewrite the frozen evaluation evidence or its identity. Duplicate record IDs
  are rejected before fitting.

## What the actual ink shows

The diagnostic rendering shows the Simple major triangle split into two proposed
glyph groups, whereas the Rhythm triangle stays intact but reads as A. The
generic 97-character vocabulary and frozen profile both lack a major-triangle
lesson. Other failures include 7, sharp, slash and root-letter substitutions.
This identifies symbol coverage/classification and one grouping failure as work
areas, not proof that four lessons will fix complete-chord recognition.

The lossless handling of parenthesis strokes also remains a known assembly
limitation. Strict all-strokes checking correctly counts that as a failed read;
it is not a repair to grouping. Historical edit-trace tests that reconstruct old
policy through current code were not used as a historical parity gate.

## Executed gates

- Focused iOS Simulator gate: 106 tests executed, 106 passed, zero failed/skipped,
  checked with xcresulttool.
- Final review-screen check after the zero-case wording change: two iOS tests
  executed, both passed, zero failed/skipped. Portrait and landscape attachments
  were visually inspected; these use a controlled test model/profile.
- Swift/macOS real-model comparison: 18 executed, all passed, zero failed/skipped.
  Includes the two exact fresh runs and separately saved reports.
- Swift/macOS policy/replay gate: 19 executed, 18 passed, one optional external
  fixture test skipped, zero failed. The supplied journal replay was executed.
- Final physical Debug build succeeded. Strict code-signature verification
  succeeded with the macOS trust store. Installation and device launch succeeded
  on the paired iPad; these are distinct from user interaction validation.
- Profile and evaluation journal are byte-identical before/after installation:
  30 examples and ten saved runs, including the 12 new records. Private reports,
  inputs and model artifacts stay outside the repository.
- All 13 chart IDs and non-ink chart content are preserved. Two PencilKit chord
  drawings reserialized on load. Both decoded drawings compare equal, with all
  exposed ordered stroke/point properties unchanged: 59 strokes and 892 points.
  Same-runtime serialization matches; rendered-pixel equality was not tested.
- A temporary startup Free/expired entitlement resolved to Studio/active in the
  settled local snapshot. The user confirmed existing charts open normally.
  Selected-chart state cleared on relaunch; no billing or authentication data
  was changed directly to restore access.

Evidence is local and durable:
/Users/benirossman/.local/share/ichart/recognition-development/fresh-20260930.HgC4zd/.
The unchanged opted-in model package is retained in the preceding
resume-20260930.ilcFHS/PersonalMLComparison directory. This is still Debug-only
development packaging, not a clean-checkout shipping model distribution.

## Next experiment

Keep both before-learning runs frozen and untaught. Through My Handwriting →
Choose Examples → Choose one symbol, explicitly save normal-size examples of
major triangle, 7, sharp and slash. Preserve existing examples; do not reset the
profile or infer part labels from whole-chord lessons.

After confirming those lessons persisted, compare saved ink only as a diagnostic,
then freeze a new protocol using genuinely new chord compositions and fresh ink
in both chart styles. Check gains, regressions, missing reads and trusted wrong
reads together. Independent-writer evidence remains required for user-agnostic
recognition claims. No commit, push, release or backend change was performed.

## Explicit lessons verified and transfer protocol frozen

The user saved the four requested symbols. A fresh device pull confirms 30 → 34
examples: 16 symbol lessons and the same 18 whole-chord lessons. The additions
are explicitly labeled setup examples of triangle, 7, sharp and slash. Every
prior example remains identical, profile generation is unchanged, revision
advanced, and all ten evaluation runs remain unchanged. This establishes saved
learning inputs, not improved recognition.

The next targeted transfer prompts, in order, are F-major-7 (written F△7),
A-flat-7, A7, E-minor-7 (E-7), C-sharp-7 and G/D. None is a taught whole-chord
label or one of the preceding six test prompts. Write six fresh chords, one per
measure, in a new blank chart of each style. Capture before writing and finish
with six as the actual written count; do not render, confirm, teach or rewrite
failures during capture. Preserve grouping and missing-read failures.

Use the existing Before corrections phase for each new untaught test. Its
frozen 34-example profile, not the phase name, establishes that symbol learning
preceded this transfer test. The installed v28 app, compiled model and learner
settings remain unchanged during capture. A separate lossless-grouping audit
identified deliberate legacy wrapper removal and geometry-only input grouping;
no grouping change was implemented or installed for this protocol.

The paired comparisons use identical new inputs within each run, not an assumed
before/after gain across different chord sets. These are targeted one-writer
transfer tests; independent-writer accuracy is still unproven. Private checkpoint:
/Users/benirossman/.local/share/ichart/recognition-development/symbol-transfer-20260930.nsdvuQ/.

## Fresh symbol-transfer results

Both new runs completed on the unchanged installed v28 app with the same frozen
34-example profile. Profile bytes are identical before and after capture, and
all prior ten runs remain intact. The Simple run retains six labeled inputs for
six written chords. Rhythm retains seven targets for six written chords, with
two human-flagged grouping failures at the final slash chord. Its whole-chart
score is withheld; the five correctly grouped labeled targets can support only
a limited target-level comparison. Neither no-reads nor supported wrong reads
are excluded from that comparison. Reported absence of slow ink/unexpected
changes is feedback, not instrumented latency evidence.

| Exact complete reads | Simple, six written | Rhythm, five eligible targets only |
| --- | ---: | ---: |
| Recorded standard app | 5/6 | 4/5 |
| Recorded app with personal suggestions | 5/6 | 4/5 |
| Shared ML | 2/6 | 1/5 |
| Original personal ML | 3/6 | 2/5 |
| Anchored personal ML | 2/6 | 2/5 |

The app's defaults match the standard readings on every retained target: no
personal default regressions were observed in this pass. This does not repair
the app's Simple F-major-7 misread or Rhythm E-minor-7 no-read. Each experimental
ML arm reads the Rhythm minor chord as E7; that is an incorrect hypothesis in
the private comparison, not a trusted live app result. All other unsuccessful
ML attempts are no-reads. ML remains comparison-only and materially behind the
current app on these inputs.

### Isolate what the four lessons changed

A separate append-only lesson-ablation-v1 report compares the old 30-example
profile directly with each run's actual frozen 34-example profile on identical
saved inputs. No run profile is replaced, and labels enter scoring only after
all inference. Both arms use the unchanged encoder, legacy grouping, learner
settings and identical whole-chord lessons. The profile delta is verified as
exactly the four explicit setup glyphs; known/repeated ink and grouping failures
use a common eligibility set.

The original personal learner gains one Simple C-sharp-7 read (no-read → C#7),
with zero complete-chord harms. Rhythm's five eligible readings do not change;
its A-flat-7 gain over shared ML was already present with the old profile. The
anchored learner has no complete-chord changes in either style. Across eleven
eligible targets, the original learner changes 4 → 5 exact reads; this is not an
11-of-12 or whole-chart accuracy claim. Two macOS Swift tests executed and
passed, including the real-model ablation and a label-isolation wiring test.
One observed same-writer transfer gain does not establish broad personalization
or accuracy across new writers.

### Upstream stroke ownership, not missing capture

The latest Rhythm targeting trace contains 27 source strokes, 27 visible
strokes, 26 recognition strokes, one accepted barline and seven targets through
draft_barline_lane. An exact ordered point/time comparison matches all 26 saved
recognition strokes uniquely to the original PencilKit drawing, and all seven
finish payloads equal the seven saved recognition inputs. The sole excluded
source stroke is the slanted mark between the final two flagged targets: 16
points, height 29.774, width 10.348, angle 16.097 degrees from vertical,
straightness 0.91588. It passes the detector's absolute-width alternative despite
failing its width/height limit.

The barline is removed before recognition and becomes a hard target boundary.
The six-target alternative partitions also use the already filtered ink; simply
choosing their count would not restore the stroke. The original mark remains in
the saved drawing. This is recognition ownership loss, not source-ink deletion.
The read-only checker and result are retained privately in grouping-diagnosis/.

### Separately versioned lossless ML grouping

The new opt-in geometry-lossless-source-groups-v2 grouping preserves wrapper
strokes and passes each group's full original strokes, metadata and original
order to the encoder. It requires exact source-index coverage, validates raw
geometry and keeps invalid/unsupported input in failed-read accounting. The
legacy geometry-semantic-wrappers-v1 default remains unchanged; no installed
experiment or live app route switched to this option for the transfer capture.
Reports identify grouping separately from encoder and learner versions, and
older reports remain readable without an invented grouping identity.

The focused Swift gate executed 46 tests: 44 passed, two optional archive tests
skipped, zero failed. It covers source/metadata/wrapper invariants and the actual
new-run comparison. The separate lossless runtime gate executed one test and
passed; both grouping modes produce the same reads on all eleven eligible
transfer inputs. There is no measured recognition gain from this grouping
change on this set. Rerunning the prior twelve-input comparison with the default
mode reproduces its rows/scorecard/source digests exactly. These are structural
preservation and saved-input runtime gates, not fresh new-writer validation.

## Contextual barline ownership repair

The live candidate pipeline is now identified as
maximum-trust-v29-ink-owned-barlines-v1-2026-09-30. Before any candidate barline
leaves recognition, a same-lane neighboring-ink check retains it when local
construction strokes touch it, or comparable nearby ink closely flanks it on
both sides. The rule does not inspect chord labels, user identity, intended
answers, model ranks or the desired target count. Existing geometric barline
acceptance remains unchanged; other barline candidates are not text-ownership
evidence. No model, learner settings, arbitration policy, committed chart
symbols or ink storage geometry were changed for this repair.

Six synthetic test methods cover connected stems, steep narrow slanted marks,
order/direction/translation/scale, gap and height boundaries, spaced sloppy
separators, neighboring barlines and separate lanes. Very tightly packed or
touching intentional separators can conservatively remain recognition ink;
these ratios are ambiguity gates, not calibrated confidence. Isolated and
properly spaced separators retain support. Independent source review found no
concrete API/ownership issue; it is not a substitute for the executed gates.

The iOS build-for-testing passed. The focused Simulator gate executed 136 tests,
all passed with no failures/skips, verified through xcresulttool. It includes an
optional private-input test actually supplied with the original Rhythm drawing,
not a synthetic replacement: its saved canvas dimensions reproduce exactly at
the logical page width, all 27 original strokes reach preparation targets once,
the embedded mark is not a barline, and six targets replace the observed seven.
The private source library stays byte-identical. A separate Simple replay
executed one test and passed: all 28 original strokes reach six targets exactly
once. These tests invoke real iOS preparation but do not establish new
handwriting accuracy or physical-iPad interaction acceptance.

The physical Debug build and strict signature verification passed. The new
executable SHA256 is
067cbd3f3555a2b4df494ee97b3afaf8fbadd6d58ffdb53560879de22a3da710.
The embedded model manifest remains unchanged at
d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1.
Pre-install device backups match the post-transfer profile and journal exactly.
Installation and device launch passed on the paired iPad. The post-install
profile and all twelve saved evaluation runs are byte-identical to the backups.
All fifteen chart IDs and all non-ink chart content are unchanged. The two new
drawings reserialized; the read-only PencilKit checker finds equal decoded
drawings, equal same-runtime round-trip serialization, zero exposed-property
differences over 55 strokes/882 points, and equal bounded 2x rendered pixels.
This is not raw original drawing-blob identity or an instrumented performance
test. Selected-chart state cleared at relaunch.

The latest local post-startup access snapshot is Free/proExpired. No billing or
authentication state was modified to override it; a user chart-access check is
requested. Physical interaction acceptance and genuinely fresh post-repair
handwriting remain unverified. The requested first check is to open the saved
Rhythm transfer chart and inspect the last target without rewriting, rendering
or teaching. No commit, push, release or backend change was performed.

## Live v29 verification and independent grouping diagnosis

The later physical-device v29 trace records 27 source strokes, 27 visible and
27 recognition strokes, no accepted barline and six targets. The last target
contains the complete four-stroke G/D reading. This verifies the repaired
ownership path on retained ink, not a fresh six-chord accuracy gain.

A subsequent source count of 28 produces three raw targets but only two admitted
preview targets. The retained targets are the earlier first two inputs; the
third raw target's geometry is not exported. The current saved Rhythm chart has
no chord ink and no new chord events. Neither the trace nor the saved library
identifies the action that removed that ink. Do not attribute it to Render All
without additional evidence; the original drawing remains backed up.

Independent public development-writer measurements are recorded in
[the frozen glyph ownership protocol](personal-glyph-ownership-protocol-2026-09-30.md).
They expose isolated-symbol splits and adjacent-symbol merges before model
classification. Nine tests executed and passed, with no reserved-writer
evaluation, model inference, retraining or personal-profile change. These
component results are not full-chord/new-writer product accuracy. They support
working on general symbol boundaries and representation rather than fitting
fallbacks to this user's intended chord answers.

## v30 exact live-source rendering safety

Source inspection found an independent unsafe clearing path: the preview load
policy can exclude targets, while Render All previously considered only the
represented drafts and could clear all page chord ink. This source defect is
real; it does not establish the cause of the earlier absent Rhythm drawing.

The shared clearing guard now requires exact counted ownership of all
mask-visible PencilKit fragments. Missing, extra, duplicated, stale, malformed
or nonfinite source claims fail closed before chart mutation. Path/control-point
properties, absolute chronology, transform and random seed are checked. Ink
color/type are deliberately excluded because target ink is normalized to the
app pen. Recognition's minimum-size filter is not clearing authority: omitted
tiny drawn marks also block consumption. Fully mask-erased portions contribute
no visible fragments. Barline claims require fresh detection, safe one-to-one
source remapping and matching geometric/placement evidence; a UUID or chord
label does not establish ownership.

The Editor now requests a synchronous main-actor transaction from the live
canvas owner. It reads actual PKDrawing, not cached serialization, sampled
snapshots or cached stroke counts; checks the resident chord scope/chart ID;
and refuses an unfinished tool contact. A chart copy is prepared using current
source coordinates and the guarded commit. Only a complete successful result
cancels pending work, records an empty-source persistence tombstone and clears
the canvas, before returning the committed chart to Editor. Rejected or partial
preparations return the original chart and do not clear source. No deferred
render invalidation remains. Explicit Discard is still an intentional clearing
operation and supersedes older pending writeback before model synchronization.

Pipeline identity:
maximum-trust-v30-exact-live-render-coverage-v1-2026-09-30.
No recognizer thresholds, model, personal learner, baseline-preserving
arbitration or profile examples changed for this safety repair.

### Verified gates and preservation

- Simulator build and focused gate: 108 executed, 108 passed, no failures/skips,
  verified with xcresulttool. Includes real PencilKit ownership, both-layout
  real UIKit canvas transactions, active-tool and unavailable-scope rejection,
  stale cached count, pending-writeback rules, preview and cancellation checks.
- The initial gate had one tiny-mark fixture failure: PencilKit expanded the
  nib footprint above the recognition cutoff. The fixture now has an explicit
  preserved affine scale, and the complete gate was rerun. Production thresholds
  were not changed to satisfy the test. A separate replay-test layout-property
  typo was corrected before executing the replay gates.
- Exact saved-input coverage replay: one executed/passed test per style, zero
  failures/skips. Simple retains 28 strokes and Rhythm 27, with six targets each.
  The tests verify all source properties and target coverage without reading
  intended answers or executing chord classification. This is saved-source
  compatibility, not fresh recognition or physical review interaction.
- Physical Debug build, strict Development-signature verification, install and
  device launch succeeded. The exact signed app is preserved locally as
  tested-v30-iChart.app. Executable SHA-256:
  62c02a78995e508bf134242d7eec1fb361cca6f418fdcd12c431f0b7bb3ef920.
- The embedded model manifest is unchanged at
  d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1;
  public anchors remain unchanged at
  e1670f855301f2fdb7970d2a4d23a30ffd82e76a242347867751b6c4c78a76ed.
  Experimental ML remains opted-in Debug comparison-only.
- Pre/post-install profile and evaluation journal are byte-identical: 34
  examples, twelve runs. All fifteen chart IDs and all chart content are
  preserved, including raw drawing bytes: zero changed drawings and zero
  non-ink chart changes. No changed drawings required decoded/pixel comparison
  in this install; do not invent such an executed comparison. Selected-chart
  state cleared at relaunch.
- Startup and one later local access snapshot read Free/proExpired, versus
  Studio/proActive before installation. Billing/authentication state was not
  manually changed. A user check of actual existing-chart access is requested;
  the cached snapshot alone does not prove a restriction or restored access.

Evidence:
/Users/benirossman/.local/share/ichart/recognition-development/live-render-safety-20260930.NCyVC2/.
Physical acceptance of the new Render All transaction and fresh independent-
writer accuracy remain unverified. No commit, push, backend deployment or release
was performed. The recognition goal remains active; this protects learning and
evaluation source while the general ML pipeline is still under development.
