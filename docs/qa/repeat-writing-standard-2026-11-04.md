# Handwritten repeat standard and acceptance

This local candidate keeps handwritten repeat entry and defines a broader,
tested geometric contract. Complete signs are recognized as structure before
chord recognition. Identifiable unfinished signs keep their whole source group
and offer repeat-specific recovery. This is a local repair based on the source
matching the supplied screenshots, not physical iPad acceptance or release
approval.

## Evidence and diagnosis

IMG_0321 shows repeat bars approximately 52–60% of the visible Simple lane
height. The previous detector inherited the plain barline minimum of 62%.
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
may be written in either order and either stroke direction. Tap dots and small
loop dots are supported. Line weights do not have to differ.

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
| Dot count | Exactly two on each occupied side |
| Dot size and path | Span at most max(2 points, 20% of H); path length at most max(4 points, 75% of H) |
| Dot shape | Small loops or taps; axis ratio at least 0.30 unless span is at most max(2 points, 5% of H) |
| Dot position | Each center within 10–90% of H; side distance at most max(10 points, 45% of H); clear gap at least max(1 point, 1.5% of H) |
| Pair alignment | Horizontal center difference at most max(2.5 points, 18% of H) |
| Pair vertical fit | Separation 12–62% of H; pair midpoint within 22% of H from the bar midpoint |
| Neighboring chord bodies | Leave over 12% of H around the actual sign; ink connected to or crossing a bar still vetoes the group |

Numerical tolerance of 1e-8 makes transformed coordinates honor inclusive
boundaries. It does not widen the handwriting envelope perceptibly. Plain
barlines keep their existing thresholds; shorter bars qualify only as part of
a repeat construction.

## Unfinished signs and timing

An isolated eligible bar group with one dot, an extra dot, or a malformed pair
is reserved as a nonrenderable incomplete repeat. Potential double bars group
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

## Acceptance boundary

Native tests cover reconstructed screenshot signs across all three layouts
and three page sizes, inclusive limits and outside-limit cases, handwriting
wobble, stroke order, false-positive controls, incomplete-source isolation,
safe deletion, ending interactions, and repeat pairing. A real PencilKit
short/wide pair is also prepared and rendered in Simple and Rhythm layouts
using both Automatic and Manual, with exact source archiving and persistence
round-trip checks.

The final native selection executed 405 tests: 402 passed, three optional local
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

Release acceptance still needs fresh physical Pencil attempts in both sheet
styles, including natural pauses, incomplete/retraced signs, nearby chords,
ending review, rotation, and save/reopen. A single successful retry does not
satisfy that acceptance condition. No device install or release is part of
this local patch.
