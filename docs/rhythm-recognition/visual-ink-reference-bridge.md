# Visual Ink Reference Bridge

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Purpose

This file connects raw handwritten ink interpretation to the backend rhythm reference documents:

- `references/simple-rest-and-rhythm.jpg`
- `references/rhythm-combinations.pdf`
- `backend-rhythm-reference.md`
- `RhythmRecognitionContextRules`
- `recognizer-decision-contract.md`
- `golden-fixture-matrix.md`

It is not user-facing Help content. It describes what the visual interpreter should see before the rhythm engine decides what the music means.

The core rule is simple: classify shape evidence first, then validate it against duration, meter position, grouping, and neighboring symbols. A mark that looks like an eighth rest alone should not become an eighth note just because another stroke appears nearby.

Before assigning semantic music labels, the visualizer should preserve neutral morphology: compact dots, heavy vertical strokes, horizontal strokes, diagonals, curve hooks, zig-zag bodies, and loops. These raw shape tokens are evidence, not final rhythm values. A tall angular mark should not become a `filledNotehead` merely because it has mass; it should remain a `zigZagBody`/`verticalStroke` candidate until notehead, rest-body, dot, stem, and meter context agree.

## Visual Interpreter Vocabulary

Normalize every ink cluster into these visual tokens before assigning a rhythm value:

| Token | Visual meaning | Recognition use |
| --- | --- | --- |
| `openNotehead` | Closed oval, eye, loop, or hollow notehead with an empty center. | Whole, half, dotted half, dotted whole candidates. |
| `filledNotehead` | Dark filled oval, teardrop, blob, or scribbled notehead mass. | Quarter, dotted quarter, eighth, dotted eighth, sixteenth candidates. |
| `slashNotehead` | Diagonal slash used as a rhythmic placeholder instead of a pitched head. | Slash notation candidates. |
| `stem` | Upright or near-upright line attached to or visually aligned with a notehead. | Half and shorter note candidates. |
| `singleFlag` | One curved hook or short tail attached near the stem top. | Eighth-note family evidence. |
| `doubleFlag` | Two hooks/tails attached near the stem top. | Sixteenth-note family evidence. |
| `singleBeam` | One horizontal or slanted connector across adjacent stems. | Grouped eighth-note evidence. |
| `doubleBeam` | Two parallel connectors across adjacent stems. | Grouped sixteenth-note evidence. |
| `augmentationDot` | Small detached dot to the right of a note/rest body. | Dotted duration evidence. |
| `rectRestBlock` | Filled horizontal block sitting on or hanging from a staff line. | Whole-rest or half-rest evidence. |
| `quarterRestSquiggle` | Compact vertical zig-zag, lightning, or soft S gesture. | Quarter-rest evidence. |
| `eighthRestHook` | Small upper dot/comma plus descending angled tail. | Eighth-rest evidence. |
| `sixteenthRestHook` | Eighth-rest-like gesture with two hook/dot levels. | Sixteenth-rest evidence. |
| `tieArc` | Smooth curved arc connecting sustained values. | Tie/continuation evidence, not a new attack. |
| `tupletNumber` | Small number above or near a grouped rhythm, especially `3`. | Tuplet grouping evidence. |
| `verticalStroke` | Tall mark with heavy y-axis travel and small x-axis spread. | Neutral morphology before deciding stem, rest body, or noise. |
| `horizontalStroke` | Flat mark with heavy x-axis travel and small y-axis spread. | Neutral morphology before deciding beam, rest block, staff-relative rest, or noise. |
| `diagonalStroke` | Slanted line that is not yet a slash, stem, or beam. | Neutral morphology before assigning placeholder slash or gesture fragment. |
| `curveHook` | Curved or hooked mark that is not yet a flag, tie, or rest hook. | Neutral morphology before assigning flag/tie/rest meaning. |
| `zigZagBody` | Angular vertical squiggle/lightning/S-like body. | Neutral rest-body morphology, especially quarter-rest family evidence. |
| `loop` | Closed or nearly closed stroke. | Neutral morphology before deciding open/filled notehead or overdraw. |

## Global Shape Rules

1. Note symbols need a notehead token. Eighth notes require `filledNotehead` plus `stem` plus `singleFlag` or `singleBeam`.
2. Rest symbols must not require a notehead. Quarter rests and eighth rests are gesture shapes, not missing-notehead notes.
3. Dots are duration modifiers, not standalone rhythms. A dot must attach to the nearest valid value to its left within the same beat neighborhood.
4. Beams are grouping evidence, not identity evidence. A beam can explain multiple short notes, but it must not erase rest identity or cross protected meter boundaries.
5. Strokes should be classified locally before phrase grouping. Neighboring noteheads, stems, or beams may add context, but they should not rewrite a clean rest cluster.
6. Reference-only symbols can inform visual decisions before they are supported for commit. If the renderer/model does not support a value yet, the recognizer should preserve ink or route to review.

## Single Symbol Descriptors

### Slash

Visualizer description:
One diagonal stroke with no head, stem, dot, flag, beam, or rest contour. It is usually a straight or lightly curved slash that occupies a beat slot.

Handwritten abstraction:
Users may draw it as a quick forward slash, backslash, or slightly arced mark. It can lean in either direction. It should stay simpler than a quarter rest and should not have a zig-zag body.

Key rejection cues:
Reject as slash when the mark has a clear rest squiggle, a notehead, a dot, a stem, or flag evidence.

### Whole Note

Visualizer description:
One hollow closed oval or eye-shaped notehead. There is no stem. The interior should read open, even if the line is thick or slightly overdrawn.

Handwritten abstraction:
Users may draw a sideways oval, a tall loop, a loose eye, or a one-stroke circle that closes imperfectly. The shape can be slightly lopsided. The important traits are closed outline, open center, and no stem.

Key rejection cues:
Reject as whole note when the head is filled, when a vertical stem is attached, or when a detached dot makes it a dotted value.

### Dotted Whole Note

Visualizer description:
A whole-note open oval plus one detached dot to the right of the notehead.

Handwritten abstraction:
Users may place the dot slightly high, low, or farther right than engraved notation. The dot should be separate from the oval and should not be a starting/ending overdraw lump.

Key rejection cues:
If the dot touches the oval, treat it as noisy overdraw until duration context supports a dotted value. Current V1 support is reference-only.

### Half Note

Visualizer description:
One hollow notehead with one stem. The stem is usually vertical or near-vertical and attached to the side of the open head.

Handwritten abstraction:
Users may draw the head first and then pull the stem, or draw a stem and loop into the head. The head might look like a thin almond instead of a perfect oval.

Key rejection cues:
Reject as half note when the head is filled, when a flag/beam appears, or when a detached dot creates a dotted-half candidate.

### Dotted Half Note

Visualizer description:
A half note plus one detached augmentation dot to the right.

Handwritten abstraction:
Users may make the dot as a tap, short dash, or small filled speck. It should sit to the right of the note body, not on top of the stem or inside the notehead.

Key rejection cues:
Reject dotted-half identity if the dot merges into the open head or if the following note is closer and owns the dot spatially.

### Quarter Note

Visualizer description:
One filled notehead with one stem. No flag, beam, or dot is required. The head should be a lower filled mass connected to the stem.

Handwritten abstraction:
Users often draw a quick stem with a filled blob at the bottom, or draw an oval and scribble it closed. The head may be compact, slanted, or slightly detached as long as it visually belongs to the stem.

Key rejection cues:
Reject as quarter note when a top flag/hook is present, when the head is hollow, or when a dot to the right creates dotted-quarter evidence.

### Dotted Quarter Note

Visualizer description:
A quarter note plus one detached dot to the right. Duration is 1.5 quarter-note beats in ordinary quarter-note meters.

Handwritten abstraction:
Users may make the dot small and low, especially on iPad ink. The dot may sit closer to the notehead than engraving would prefer, but it should remain separate.

Key rejection cues:
Do not confuse a messy filled notehead tail with an augmentation dot. The dot should be right-side evidence with a small bounding box and clear separation.

### Eighth Note

Visualizer description:
One filled notehead, one stem, and either one flag/hook or one beam connecting to another stem. The notehead is mandatory.

Handwritten abstraction:
Users may write a compact filled head and a fast stem with a curved top hook. In beamed groups, users may draw stems first and then drag a single connecting beam. The beam may be slanted and imperfect.

Key rejection cues:
Reject as eighth note when there is no filled notehead, when the lower mass is absent, or when the visible gesture is a compact rest hook rather than a notehead-plus-stem.

### Dotted Eighth Note

Visualizer description:
An eighth note plus one detached dot to the right. It commonly pairs with a sixteenth note inside one beat.

Handwritten abstraction:
Users may draw the flag/beam loosely and place the dot closer to the stem than the notehead. The note still needs a filled notehead and one flag or beam.

Key rejection cues:
Current V1 support is reference-only. If detected, it should inform phrase context and review, not auto-commit unless model/render support exists.

### Sixteenth Note

Visualizer description:
One filled notehead, one stem, and either two flags or two beams. It is visually like an eighth note with doubled short-value evidence.

Handwritten abstraction:
Users may draw two quick hooks, a scribbly double-flag, or two nearly parallel beams. The two beams may be close together or partially merged at speed.

Key rejection cues:
Current V1 support is reference-only. Do not collapse a messy two-flag symbol into an eighth note if the phrase duration only fits with sixteenth values.

### Whole Rest

Visualizer description:
A filled horizontal block hanging below a staff line. It looks like a small dark rectangle attached to the underside of the line.

Handwritten abstraction:
Users may draw a short filled rectangle, a thick dash under a line, or a rough block. It may not be perfectly filled.

Key rejection cues:
Reject as whole rest when the block sits above the line like a half rest, when it is a notehead, or when there is vertical rest-squiggle travel.

### Dotted Whole Rest

Visualizer description:
A whole rest plus one detached dot to the right.

Handwritten abstraction:
Users may draw a rough block and a small tap-dot. Staff-line relationship still matters: the block hangs below the line.

Key rejection cues:
Current support is reference-only. Do not confuse dust/noise near the rectangle for a dot unless spacing and duration context agree.

### Half Rest

Visualizer description:
A filled horizontal block sitting on top of a staff line. It looks like a small dark rectangle resting on the line.

Handwritten abstraction:
Users may draw it as a hat, bridge, or short filled cap. The base line may extend past the block.

Key rejection cues:
Reject as half rest when it hangs below the line, becomes a filled notehead, or has a vertical squiggle shape.

### Dotted Half Rest

Visualizer description:
A half rest plus one detached dot to the right.

Handwritten abstraction:
Users may place the dot slightly low or far right. The rest block still needs to read as sitting on the line.

Key rejection cues:
Current support is reference-only. The dot must attach to the rest block by right-side position and duration context.

### Quarter Rest

Visualizer description:
A compact vertical zig-zag or soft S-shaped gesture. It normally has one main stroke, with top-to-bottom travel and no notehead.

Handwritten abstraction:
Users may write textbook quarter rests poorly: as a lightning bolt, loose squiggle, open Z shape, or rounded S. The common abstraction is a single descending gesture that changes direction at least once and does not have a filled lower notehead.

Key rejection cues:
Reject as quarter rest when the shape has a clear notehead plus stem, when it is only a diagonal slash, or when it is a small eighth-rest hook with no larger vertical zig-zag body.

### Dotted Quarter Rest

Visualizer description:
A quarter-rest squiggle plus one detached dot to the right.

Handwritten abstraction:
Users may draw the rest quickly and tap the dot. The dot can be close but should not be part of the zig-zag stroke.

Key rejection cues:
Do not create this from generic dot proximity. Segment the quarter-rest body first, then attach a compact lower-lane dot only if it trails the glyph within the bounded x/y attachment window; otherwise keep the plain rest or route to review.

### Eighth Rest

Visualizer description:
A compact rest mark with a small upper dot/comma and a descending angled or curved tail. It has no lower filled notehead and no stem-plus-notehead relationship.

Handwritten abstraction:
Users often write it as a small `7`, comma-with-tail, hooked slash, or one-zig gesture. It may be one stroke or two strokes. It is usually smaller than a quarter rest and normally has only one main hook/zig.

Key rejection cues:
Reject as eighth note when there is no lower filled notehead. Reject as quarter rest when the gesture is too small and hook-like rather than a larger vertical squiggle. Neighboring eighth notes must not donate their noteheads to this rest cluster.

### Dotted Eighth Rest

Visualizer description:
An eighth-rest hook plus one detached dot to the right.

Handwritten abstraction:
Users may write a small rest hook and tap the dot close to it. It can look cramped, so duration context is important.

Key rejection cues:
Current support is reference-only. If the dot is ambiguous, do not force it into the rest unless the beat math requires dotted-eighth duration and the dot is spatially right-side evidence.

### Sixteenth Rest

Visualizer description:
An eighth-rest-like shape with doubled hook evidence: two small hooks/dots or two flag-like curls on a descending stem/tail.

Handwritten abstraction:
Users may draw this as a longer eighth rest with an extra notch, a double comma, or a compact vertical mark with two small hooks. At speed, the second hook may be faint.

Key rejection cues:
Current support is reference-only. Do not demote to eighth rest if the phrase duration and visible double-hook evidence point to sixteenth rest.

### Tie / Continuation Arc

Visualizer description:
A smooth horizontal or shallow curved arc connecting one value into the next. It is not a notehead, not a rest, and not a slur-like phrase mark unless attached to rhythm values.

Handwritten abstraction:
Users may draw ties as low smiles, shallow arcs, or slightly angled curves. They may overlap stems or noteheads.

Key rejection cues:
Reject as a rhythm attack. Ties modify duration/continuation and should not add beats by themselves.

## Combination And Grouping Descriptors

These cells come from `rhythm-combinations.pdf` and the current rhythm-overhaul discussions. They describe phrase-level evidence, not just isolated symbols.

### Whole-Note Measure

Visualizer description:
One whole note occupying a full 4/4 measure. No stems, beams, or neighboring noteheads are expected.

Handwritten abstraction:
The user may draw one large open oval centered in the measure. Since there is only one attack, measure fit is the main confidence booster.

Recognition note:
If extra small marks appear, classify them as noise unless they form a clear augmentation dot or another supported value that changes the measure total.

### Two Half Notes

Visualizer description:
Two hollow noteheads with stems, spaced into two equal half-measure positions.

Handwritten abstraction:
Users may draw them with uneven spacing, but the phrase should still read as two open-head stemmed notes.

Recognition note:
Do not use spacing alone to turn open heads into quarter notes. The hollow interior is primary.

### Four Quarter Notes

Visualizer description:
Four filled noteheads with stems, usually one per beat in 4/4. No flags or beams.

Handwritten abstraction:
Users may make the four noteheads inconsistent in size. Some stems may lean. The repeated filled-head-plus-stem pattern is the anchor.

Recognition note:
If one note has a small accidental-looking blob near it, avoid treating it as a dot unless the measure otherwise underfills or the dot is cleanly placed to the right.

### Eighth-Note Pair

Visualizer description:
Two filled noteheads with stems and either two single flags or one shared beam. Total duration is one quarter-note beat.

Handwritten abstraction:
Users often draw two stems and a single slanted beam. The noteheads may be uneven, but both heads must exist.

Recognition note:
The shared beam should strengthen "two eighth notes" only when both noteheads are present and the pair stays inside a valid grouping boundary.

### Four Eighth Notes Across Two Beats

Visualizer description:
Four filled noteheads and stems. They may be grouped as two beamed pairs or as one beam group depending on meter/style.

Handwritten abstraction:
Users may draw one long beam across all four or two smaller beams. The engine should rely on meter grouping to decide whether a long beam is acceptable.

Recognition note:
In 4/4, the midpoint can be protected in certain contexts. Do not assume every visible long beam is musically valid.

### Sixteenth-Note Group Of Four

Visualizer description:
Four filled noteheads with stems connected by two beams, or each with two flags. Total duration is one quarter-note beat.

Handwritten abstraction:
Users may draw the double beam as a thick scribble or two nearly merged strokes. Noteheads can be very small.

Recognition note:
Reference-only until sixteenth values are supported. Useful as a "do not misread as eighths" context when the visual has doubled beam evidence.

### Eighth Plus Two Sixteenths

Visualizer description:
One eighth note followed by two sixteenth notes inside one beat. Beaming often shows the first note with single-beam participation, then the latter two with double-beam subdivision.

Handwritten abstraction:
Users may draw one long upper beam across all three stems and a shorter second beam only over the two sixteenths.

Recognition note:
The second beam segment is the key visual cue. If omitted by handwriting, meter fit and spacing may make the phrase ambiguous.

### Two Sixteenths Plus Eighth

Visualizer description:
Two sixteenth notes followed by one eighth note inside one beat. The first two usually share a second beam; all three may share the primary beam.

Handwritten abstraction:
Users may reverse the beam pattern from the previous cell: a short lower beam over the first two notes, then only the upper beam to the final eighth.

Recognition note:
Reference-only for now. The recognizer should keep the internal order because reversing this cell changes the musical attack placement.

### Dotted Eighth Plus Sixteenth

Visualizer description:
A dotted eighth note followed by a sixteenth note. The first symbol has a filled head, stem, flag/beam, and dot; the second is a short value. Total duration is one beat.

Handwritten abstraction:
Users may write the dot close to the first stem and draw the following sixteenth tightly to the right. The dot may be the easiest mark to miss.

Recognition note:
Reference-only for now. Treat this as a high-risk syncopation cell because losing the dot turns the rhythm into a different beat total.

### Sixteenth Plus Dotted Eighth

Visualizer description:
A sixteenth note followed by a dotted eighth note. The short attack comes first; the longer dotted value follows.

Handwritten abstraction:
Users may draw the first note as a tiny head/stem with double-flag evidence, then a larger dotted eighth to the right.

Recognition note:
Reference-only for now. Do not reorder the values to fit a more familiar visual pattern.

### Triplet Of Eighth Notes

Visualizer description:
Three eighth-note attacks in the space of one beat, typically beamed together with a small `3` above or near the beam.

Handwritten abstraction:
Users may draw the `3` loosely, close to the beam, or slightly above the group. The three noteheads may be crowded.

Recognition note:
Reference-only until tuplets are modeled. Without the `3`, three eighth-looking notes inside one beat should not be force-committed as ordinary eighths.

### Dotted Quarter - Eighth - Eighth - Dotted Quarter

Visualizer description:
Four values across a 4/4 measure: dotted quarter, eighth, eighth, dotted quarter. The two eighth notes sit on opposite sides of beat 3.

Handwritten abstraction:
The user may naturally write the two eighths close together because they are adjacent on the page. That visual closeness is not permission to beam them together.

Recognition note:
The boundary between the two eighths is the center of the measure in 4/4. `RhythmRecognitionContextRules` must block a beam across that protected meter boundary.

## Eighth Rest Versus Eighth Note Decision Rule

This deserves its own bridge rule because it has been the most fragile recognition path.

Positive eighth-rest evidence:

- No lower filled notehead.
- Compact upper dot/comma or hook.
- Descending angled or curved tail.
- One small hook/zig rather than full quarter-rest vertical travel.
- Stroke can stand alone as a rest before phrase grouping.

Positive eighth-note evidence:

- Filled lower notehead.
- Stem attached to or aligned with that notehead.
- Single flag or beam evidence.
- In beamed context, a notehead exists for every stem participating in the beam.

Hard guardrail:
Do not let a neighboring note's head satisfy the notehead requirement for a rest-shaped cluster. If the cluster itself has no notehead and has hook/rest-tail evidence, it remains a rest candidate or review candidate.

## Suggested Pipeline Use

1. Build local stroke clusters.
2. Assign visual tokens to each cluster without looking at neighboring clusters.
3. Score symbol candidates from local tokens.
4. Add neighbor evidence for beams, dots, ties, and tuplets.
5. Run meter and grouping validation from `RhythmRecognitionContextRules`.
6. Commit only if the chosen phrase exactly fits the measure and does not violate protected grouping.
7. If a reference-only value is visually likely, preserve ink and show review feedback instead of collapsing to the nearest supported value.
