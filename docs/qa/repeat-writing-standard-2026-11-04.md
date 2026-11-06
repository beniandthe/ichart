# Historical handwritten repeat standard and acceptance — retired

**Retired November 5, 2026.** The user abandoned handwritten repeat ingestion
after the Build 143 Rhythm Section Sheet failure. The drawing rules, candidate
descriptions, and validation/install records below describe earlier revisions
only. They are not current instructions, a supported recognition contract, or a
promise to repair or reintroduce this feature. Use **Tools > Repeats** and select
measures for repeat notation. Existing saved repeats and source ink remain
preserved. See the [retirement record](../handwritten-repeat-ingestion-retirement-2026-11-05.md).

This historical local candidate kept handwritten repeat entry and defined a broader,
tested geometric contract. Complete signs are recognized as structure before
chord recognition. Identifiable unfinished signs keep their whole source group
and offer repeat-specific recovery. This is a local repair based on the source
used for the initial local patch, not physical iPad acceptance or release
approval. Build 139 integrates the patch onto the exact installed Build 138
source, `42d423f2`, preserving its unrelated fixes.

## November 5 dot-region follow-up — initial local-only checkpoint

The drawing contract below includes a local follow-up that counts compact dot
regions rather than raw Pencil strokes. Filling or retracing one dot can use
several stylus passes without becoming several dots. The follow-up removes the
per-stroke path-length limit while keeping bounds on each region's size, shape,
position, and separation.

At the earlier November 5 local-only checkpoint, this follow-up had not yet
been installed and the iPad remained on Build 139. That status was superseded
by the separately recorded Build 140 installation below. The November 4 test
and device records remain historical evidence for that earlier repair; the
follow-up's replay and source-ownership results are recorded separately.

## Evidence and diagnosis

IMG_0321 shows repeat bars approximately 52–60% of the visible Simple lane
height. The initial Build 137 baseline inherited the plain barline minimum of
62%. The later device provenance check established that Build 138 was already
installed and already accepted complete Simple repeats at 50%; bar height
alone therefore does not explain that screenshot. Build 139 preserves that
allowance and shares it across layouts.
IMG_0320 shows a Rhythm closing pair separated by approximately 25–28% of bar
height; the previous double-bar maximum was 22%. Both conditions can change
between attempts while the intended musical mark remains the same.

The tests reconstruct visible proportions from the screenshots. They are not
the original PencilKit paths, stroke counts, timing, masks, or chart state.
Current and legacy Rhythm lane frames can differ. These measurements explain
concrete failure mechanisms; they do not prove which gate rejected each
original attempt. The displayed B/bb messages establish that the feedback
presented a chord interpretation while repeat signs remained ink.

The Simple screenshot also has 35 pixels of visible whitespace between its
seventh and repeat dots, approximately 20% of the repeat height. The old 22%
neighboring-body halo can veto that detached seventh. The candidate uses 12%
clearance around the actual sign while retaining the connected-stem veto.

## Drawing contract

Use one or two upright bars covering at least half the blue lane, with two
compact, stacked dots beside the middle. Right dots start a repeat; left dots
end one; pairs on both sides end one repeat and start another. Bars and dots
may be written in either order and either stroke direction. Dots may be taps,
loops, filled marks, or retraced marks, provided they remain two separate compact
regions. A stylus pass inside the same compact region is not another dot. Line
weights do not have to differ.

The same repeat detector and limits apply across chart layouts and rendering
modes. A complete closing repeat without an earlier start uses the chart
beginning. An unmatched start or conflicting nesting requires correction.

The executable limits live in
`ChordDraftRepeatSignRecognizer.DrawingStandard`. Let L be the accepted writing
lane height and H the enclosing bar-group height. Point floors below are in
source-page coordinates, not screen pixels. Limits apply together.

| Property | Admission limits |
| --- | --- |
| Each bar | At least 50% lane coverage; height at most 135% of L; at least 1 source point |
| Bar direction and shape | At most 24° from vertical; straightness at least 0.70; width at most 35% of bar height or 12 points |
| Double-bar separation | At least max(1.5 points, 2% of H); at most 35% of H |
| Double-bar fit | Shorter bar at least 65% of H; vertical overlap at least 60% of H; center-height difference at most 22% of H |
| Dot count | Exactly two logical compact regions on each occupied side; raw stroke count does not determine dot count |
| Dot size | Each whole region's span at most max(2 points, 20% of H) |
| Dot formation | Same-side components connect when their bounds are within 2% of H; the complete connected union must remain compact |
| Grouping work bound | At most 128 admitted bounded source components beside a candidate bar group, total across both sides; larger candidates abstain rather than truncate |
| Dot shape | Whole-region axis ratio at least 0.30 unless span is at most max(2 points, 5% of H); taps, loops, fills, and retraces use the same bounds |
| Dot path length | No per-stroke path-length cap; repeated travel within an admitted compact region does not invalidate it |
| Dot position | Each center within 10–90% of H; side distance at most max(10 points, 45% of H); clear gap at least max(1 point, 1.5% of H) |
| Pair alignment | Horizontal center difference at most max(2.5 points, 18% of H) |
| Pair vertical fit | Separation 12–62% of H; pair midpoint within 22% of H from the bar midpoint |
| Neighboring chord bodies | Leave over 12% of H around the actual sign; ink connected to or crossing a bar still vetoes the group |

Numerical tolerance of 1e-8 makes transformed coordinates honor inclusive
boundaries. It does not widen the handwriting envelope perceptibly. Plain
barlines keep their existing thresholds; shorter bars qualify only as part of
a repeat construction.

Raw components require finite geometry and the dot-size bound; the aspect-ratio
check applies to the whole region after grouping. Narrow filling passes may
therefore form one compact dot together, while separate horizontal dashes still
fail the final region-shape check.

The component-connection distance uses the Euclidean gap between source bounds,
with the same numerical tolerance as other inclusive limits. A chain of nearby
strokes is evaluated as one whole union. If that union exceeds the compactness
bounds, the detector does not split it arbitrarily into convenient dot pieces.
The dot count, position, and pair-fit checks use these regions. Every original
stroke index and its geometry remain owned by the resulting complete or
incomplete repeat group; filling a dot never authorizes dropping a stylus pass.

## Unfinished signs and timing

An isolated eligible bar group with one dot region, a third separate compact
dot region, or a malformed pair is reserved as a nonrenderable incomplete repeat.
Filling or retracing within one compact region does not add a dot. A third
separate region is not discarded to force a two-dot interpretation. Potential
double bars group
through 50% of H so a pair just outside the 35% rendering limit cannot silently
become a single-bar repeat. Connected chord bodies, crowded bar groups, shared
source claims, and interfering ink retain their rejection safeguards. Marks
without enough repeat evidence are not promised structural classification.

**Fix Writing** explains bars, stacked dots, direction, and focused rewriting.
Manual entry offers **Review & Render** for incomplete-only repeat ink. Exact,
fresh incomplete groups can be deleted together; stale or fragmented source
cannot be deleted through an earlier preview.

Automatic structural entry still uses the existing two-second pause. Finish
bars and dots before pausing. A bare bar that has already rendered cannot gain
repeat semantics from later dots alone; use **Tools > Repeats** for those
rendered boundaries. A draft sign can be erased and redrawn as a whole. A new
dot cannot authorize consuming an older plain-bar preview.

## Ending contract

Ending recognition retains its existing geometry: draw a roof near the top of
the blue lane across the intended measures, with a short left hook and optional
right hook. Keep its label below the roof and chords lower in the lane. The
roof and hooks can be connected or separate.

The app detects the bracket; it does not automatically transcribe its label.
**Review Ending** supplies the exact label, **Start measure**, **End measure**,
and **Right edge**. **Use Ending** confirms the draft; rendering replaces the
owned bracket and label ink. **Back to Writing** keeps it. Incomplete repeat
punctuation under a roof stays separately owned, never becoming label text.

## Historical acceptance boundary — withdrawn

Native tests cover reconstructed screenshot signs across all three layouts
and three page sizes, inclusive limits and outside-limit cases, handwriting
wobble, stroke order, false-positive controls, incomplete-source isolation,
safe deletion, ending interactions, and repeat pairing. A real PencilKit
short/wide pair is also prepared and rendered in Simple and Rhythm layouts
using both Automatic and Manual, with exact source archiving and persistence
round-trip checks.

Before Build 138 integration, the focused native selection executed 405 tests: 402 passed, three optional local
fixture replays skipped, zero failures. Results are retained at
`/private/tmp/ichart-repeat-standard-20261104/final-with-context.xcresult`.
The seven mounted editor checks include Simple/Rhythm in both modes and the
Rhythm Manual helper at `.xxxLarge`. Automatic recovery activates the actual
status control and verifies visible help plus unchanged source. Manual review
coverage observes rendered controls and checks the underlying policy and
coordinator; it does not claim an automated Manual toolbar tap. Rendered-text
recognition verifies toolbar content where the hosted accessibility provider
does not expose its scroll-view children.

An additional, broader run encountered four existing Select/Measures guidance
test lookup failures. Retained screenshots show their Add/Delete controls, but
the in-process accessibility provider omits or misclassifies those nodes. Those
tests and production paths were not changed here; their pre-patch runtime
status was not established. The focused pass is not a claim that the entire
application test suite is green.

At this historical checkpoint, release acceptance still required fresh physical
Pencil attempts in both sheet styles, including natural pauses,
incomplete/retraced signs, nearby chords, ending review, rotation, and
save/reopen. The November 5 retirement withdraws this ingestion acceptance lane;
it is not a pending test request or future repair promise.

## Build 139 device installation

On November 4, Build 139 was signed and installed in place after integrating
onto the exact installed Build 138 source. The integrated source preserves
the independent structural toolbar guard, floating-articulation preservation,
forum fixes, telemetry fixes, and the Simple half-lane repeat allowance.

The integration selection executed 452 tests with three optional fixture
skips. Three inherited manual-toolbar tests could not discover their controls
through the in-process accessibility provider; that limitation remains open.
The changed help-copy expectation was corrected and all 34 configuration
tests passed on recheck. The repeat, ending, source-preservation, and floating
articulation suites passed.

A complete stopped-app backup was independently verified before installation.
The post-install library, PDFs, setlists, ink, preferences, and other
non-snapshot files were byte-identical before launch. After normal launch, all
23 charts, 20 PDFs, one setlist with 15 entries, and saved/draft ink were
preserved. Library serialization changed only deletion-record ordering;
preferences changed only the bounded SDK transaction-check timestamp. The
experience checkpoint refreshed an already-stale pre-install file digest;
its identity and summaries remained exact. Build 139 was left running for
physical Pencil testing. No App Store release was performed.


## November 5 saved ink diagnosis and local verification

The authorized saved-ink read contained nine original PencilKit strokes. The
left sign had two bars and three compact dot strokes: one upper dot and two
overlapping strokes making the lower dot. Build 139 requires exactly two raw
dot strokes per side, so that left sign was marked incomplete even though its
two visible dot areas satisfy the drawing geometry. The right sign had two
bars and two dot strokes. This establishes a specific raw-count failure rather
than a missing dot or a pairing mistake.

The local follow-up groups the left dots as one upper source and the two
overlapping lower sources, and groups the right dots separately. All nine
source strokes remain owned exactly once. No private chart or ink archive is
added to the repository. Native verification executed 428 tests: 425 passed,
three optional local fixture replays skipped, and zero failures. Retracing,
compact hatching, long bounded filling, distinct-third-region rejection,
source coverage, deletion, and ending coexistence are included. This follow-up
was not installed at the time of that diagnostic check; the physical iPad
remained on Build 139 until the separately authorized update below.

## Build 140 saved-ink verification and installation

On November 5 the user authorized installing the logical-dot correction and
asked to retry the existing ink automatically. Build 140 retains the exact
Build 139 integration and changes the detector, its matching How To guidance,
and a stale source comment about the existing readiness path.

Two private snapshots passed native iOS Simulator replay through preparation,
current-source ownership, automatic commit, and persistence readback. The
original nine-stroke snapshot produces one repeat span; all nine repeat
strokes are archived exactly. The later 18-stroke snapshot produces two repeat
spans and a plain boundary; all 17 repeat strokes are archived exactly and the
remaining stroke supplies the plain boundary. Both produce zero chords and
retain no draft ink. Each source index is claimed exactly once. Private input
files are unchanged and are not embedded in source or the test bundle.

The focused 14-suite run selects 429 tests: 425 pass, four optional local-data
replays skip, and none fail. The private replay test is one of those default
skips and passes separately against both authorized snapshots. An initial
Simulator Busy launch error for the later snapshot cleared after restarting
the dedicated Simulator; it did not execute the test or establish a product
failure.

Saved ink is checked when the user opens the chart and enters Write & Render
in Automatic. A fresh current-source census arms session readiness without
inventing a pen callback; the existing structural pause then applies. A review
panel invalidates earlier readiness. Select followed by Write & Render, or
reopening the chart, safely takes another census. App launch alone does not
open the chart or promise to consume saved ink. Manual Render with Preview
continues to require its normal render/review action.

The iPad reports 1.2.4 (140) after in-place installation. Two independently
copied stopped-app backups match across all 66 files. The prelaunch readback
preserves the library, 24 charts, all saved ink, 20 PDFs, and one setlist with
15 entries byte-for-byte; only OS SplashBoard snapshot cache filenames change.
Signed executable, backup, deployment, and postlaunch verification receipts
are under `/private/tmp/ichart-repeat140-install-20261105/`; the persistent
preinstall backup is `.build/repeat-install-20261105/current-app-data-before`.

The replay results are not observation of automatic rendering on the physical
iPad. At that checkpoint, physical acceptance required entering Write & Render
on that chart and observing its result. This requirement is historical; the
November 5 retirement ends further acceptance work on repeat ingestion.

## GitHub consolidation provenance — November 5

This document preserves the chronological local verification and installation
records supplied with the working source. The GitHub consolidation also includes
the current E/F and split-major-triangle source/test work. This publication does
not independently verify a live iPad, bind every pending change to an installed
binary, or establish fresh physical repeat acceptance. No device action or
App Store release is part of this repository consolidation.
