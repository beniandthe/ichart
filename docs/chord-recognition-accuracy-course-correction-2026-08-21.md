# Chord Recognition Accuracy Course Correction

Date: 2026-08-21
Base branch: `codex/1.1.7-build49-testflight`
Clean base commit: `885355e` (`Record corrected TestFlight branch cleanup`)

This document captures the recognition analysis and reset plan after the August 2026 recovery stop. It is intentionally separate from the chord-lane auto-render implementation plan.

## Objective

The recognizer must prioritize accuracy, trust, and correctness over coverage.

Acceptance target:

- at least 90% correctness on the supported chord vocabulary under realistic iPad writing
- no-read is acceptable when the system is unsure
- wrong confident reads are not acceptable
- a later chord must not retroactively change an earlier chord

The preview exists so the user can erase or keep writing. The system does not need to guess every mark.

## Desired Recognition Flow

For each staff/system, process ink left-to-right:

1. User writes a base root letter.
2. User writes optional accidental and suffix/extension glyphs.
3. User moves to the next base root letter.
4. The next base root starts a new chord.
5. The previous chord becomes immutable for preview grouping.
6. Suffix glyphs belong to the active chord until a new base root starts.
7. A vertical/near-vertical stroke by itself is a barline, not a chord glyph.

This is a sequential grouping contract. It is not a generic gap-splitting problem.

## What Went Wrong

The branch drifted into a mixed patch stream:

- OCR was reintroduced as a trust source.
- root classifiers and OCR trust arbitration changed together.
- preview persistence/sync changed in the same period.
- E/F and D issues were patched in isolation.
- batch grouping still split by spatial gaps before chord semantics.
- suffix fragments could become separate chord events.
- later ink could cause previous preview groups to change.
- tests began encoding local patches instead of product behavior.
- simulator launch failures added noise to product debugging.

The result was a branch that could pass some narrow tests while still violating the actual user flow.

## OCR Analysis

OCR should not be the backbone of chord recognition for this flow.

Observed/product reasons:

- Apple text recognition can work well in Notes, Scribble, and other apps because those surfaces provide text-entry context.
- Isolated chord glyphs in a blue drawing lane are not the same problem as sentence/word handwriting.
- Chord symbols are short, spatial, and music-specific: `D-7`, `Cmaj7`, `Bb-7`, `F#`, `G/B`, `C7(b9)`.
- OCR tends to split suffixes, ignore punctuation-like glyphs, or return no useful candidate for isolated roots/extensions.
- OCR can confuse the preview pipeline by appearing authoritative when it is actually reading a different task.
- In the prior diagnostic pass, OCR agreement was not reliable enough to resolve the core root/suffix errors.

Engineering reasons:

- OCR adds async latency and sync-state complexity.
- OCR introduces another candidate stream with different confidence semantics.
- OCR can make the preview flash or update late.
- OCR telemetry was not sufficient to prove a real accuracy lift.
- OCR-era changes made rollback boundaries harder to reason about.

Decision:

- Remove OCR from the core chord recognition path.
- Do not use OCR for render trust.
- Do not use OCR to override the template/gesture recognizer.
- Keep OCR only as a possible future offline diagnostic experiment, not production recognition.

## Scribble Analysis

Apple Scribble may explain why handwriting feels better in Apple text-entry surfaces, but it should not be assumed to be a drop-in recognizer for this lane.

Important distinction:

- Scribble is a system text-entry experience.
- The chord lane is a custom PencilKit drawing and music-layout surface.
- A text field can benefit from system text input behavior.
- A freeform lane needs structured music-symbol recognition, placement, grouping, and barline detection.

Potential future experiments:

- Create a separate hidden or explicit text-entry correction surface and test whether Scribble can enter chord text there.
- Offer a manual correction field that benefits from system handwriting input.
- Evaluate a mode where selected preview text can be corrected through normal text input.

Do not do yet:

- do not embed invisible text fields across the lane as the primary recognizer
- do not route raw lane strokes through a text-field hack
- do not assume Scribble can return per-glyph recognition data
- do not replace music-symbol recognition with generic text entry

Decision:

- Scribble is a possible correction/editing affordance, not the core recognizer.
- Before any Scribble implementation, verify current Apple APIs and build a throwaway prototype outside the release branch.

## Recognition Architecture Direction

The recognizer should be split into clean stages:

1. Stroke capture
2. Barline detection
3. Sequential chord grouping
4. Glyph recognition inside each group
5. Chord grammar/candidate composition
6. Trust decision
7. Preview publication
8. Explicit render

### Stage 1: Stroke Capture

- collect lane-local PencilKit strokes
- preserve stroke order and creation time
- preserve authored system/lane anchor
- do not persist draft drawing on every stroke if it slows ink

### Stage 2: Barline Detection

- detect solo vertical/near-vertical lane strokes before chord grouping
- remove accepted barline strokes from chord recognition input
- barline detection does not need chord context

### Stage 3: Sequential Chord Grouping

The grouping rule:

- a base root A-G starts a chord
- accidental after root stays in the chord
- suffix/extension glyphs stay in the active chord
- the next base root starts the next chord
- once the next root starts, previous chord grouping is immutable

This stage should not rely only on horizontal gap. Gap may help only when root evidence is missing.

### Stage 4: Glyph Recognition

Keep this isolated:

- template/gesture recognizer
- handwritten root heuristics
- suffix heuristics
- glyph candidates with confidence

Avoid per-letter patching unless it encodes a general visual rule.

Examples:

- E vs F can use stroke-count/shape evidence if written as block letters.
- D should require root-body evidence, not OCR fallback.
- 7 should be a suffix/extension candidate, not a new root.
- 9 should be a suffix/extension candidate, not a new root.

### Stage 5: Chord Grammar

Supported grammar should include:

- roots A-G
- accidentals `b` and `#`
- minor `-` and `m`
- major triangle
- diminished and half-diminished
- dominant 7
- 6, 9, 11, 13 where supported
- alterations `(b9)`, `(#9)`, `(b5)`, `(#5)`, `(#11)`, `(b13)`
- slash bass chords
- suspended chords
- chord repeat symbol if supported by current app behavior

The grammar should reject unsupported junk rather than render wrong text.

### Stage 6: Trust Decision

Trust policy:

- auto-render only decisive supported matches
- preview uncertain reads without committing
- no-read is allowed
- close races should not auto-render
- suffix-only fragments should not become independent chord events

Trust metadata should be aggregate and privacy-safe.

## Telemetry Requirements

Allowed aggregate properties:

- confidence bucket
- candidate count
- stroke count
- glyph count
- draft count
- rendered count
- unresolved count
- chart style
- timing bucket
- trust source, if non-textual
- route name, if allowlisted and non-PII

Disallowed:

- raw chord text
- drawing payloads
- chart title
- user names
- support/email data
- PII

Events that may be useful:

- `chord.preview_updated`
- `chord.preview_rendered`
- `chord.preview_discarded`
- `chord.preview_unread`
- `chord.draft_barline_added`
- `chord.draft_barline_rejected`
- `chord.rendered_chord_deleted`

Telemetry must prove whether a path is better before it becomes product policy.

## Test Strategy

The test suite should encode product contracts, not individual panic patches.

Required recognizer tests:

- base roots A-G
- accidentals with roots
- D is recognized as D in realistic fixture data
- E/F are distinguished by general shape/stroke evidence
- `D-7 E-7` groups as two chords
- `Cmaj7 Dmin7 Emin9` does not rewrite previous groups when new root appears
- suffix fragments do not become independent chord events
- unsupported marks produce no-read or confirm, not confident wrong render
- barline-only vertical stroke is removed from chord recognition

Fixture requirements:

- real iPad captured fixtures, not only template-generated fixtures
- natural D and E fixtures, not only flat/sharp variants
- base roots written in the user’s real hand
- suffix families: `-7`, `maj7`, `min7`, `7`, `9`, `sus`, `7sus`, altered dominants
- multi-chord same-lane sequences
- multi-system sequences

Comparison gates:

- compare to pre-OCR baseline
- compare to current clean build-49 base
- compare on the same fixture set
- require nonzero filtered test execution
- separate simulator runner failures from test failures

## Work Branch Policy

Dedicated recognition branch:

- branch name: `codex/chord-correction-accuracy`
- base: `885355e`
- only recognition/grouping/trust/fixtures/telemetry changes
- no chord-lane UI or render-flow refactors

Dedicated lane branch:

- branch name: `codex/chord-lane-auto-render`
- base: `885355e`
- only lane/render/edit/barline workflow changes
- no recognition accuracy experiments

## Stop Conditions

Stop and reassess if:

- a fix changes both recognizer internals and lane rendering
- a test passes only because it encodes one specific glyph workaround
- OCR is reintroduced as an authority
- simulator launch failures are treated as recognizer evidence
- previous chord previews still change after a later root is written
- physical iPad evidence contradicts simulator assumptions

## Next Best Path

1. Keep the clean base.
2. Develop chord-lane auto-render and chord recognition on separate branches.
3. For recognition, first implement sequential grouping and real fixture capture.
4. Do not optimize OCR.
5. Do not add UI complexity until the basic preview/render loop is stable.
6. Use physical iPad QA as the product acceptance signal.
