# Golden Fixture Matrix

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Purpose

This is the backend must-pass and must-not-autocommit matrix for the rhythm recognition overhaul. It turns the visual reference docs into concrete recognition expectations.

The first recognizer implementation does not need to support every reference-only value, but it must not misread unsupported values as safer-looking supported values.

## Decision Labels

| Label | Meaning |
| --- | --- |
| `mustCommit` | Supported value sequence should become ready to render, then commit when the user taps/finalizes. |
| `mustKeepWriting` | Incomplete or underfilled ink should stay live without rendering. |
| `mustReview` | Intent is visible but unsupported, ambiguous, or unsafe for tap-render without confirmation. |
| `mustRejectRenderProposal` | A tempting wrong read must not become a render proposal, even if it creates an exact fit. |

## Core V1 Supported Fixtures

| ID | Meter | Intended read | Decision | Required local evidence | Guardrail |
| --- | --- | --- | --- | --- | --- |
| `slash-four-beats` | 4/4 | slash, slash, slash, slash | `mustCommit` | Four separate diagonal slash tokens. | Slashes do not need noteheads. |
| `quarter-four-beats` | 4/4 | quarter, quarter, quarter, quarter | `mustCommit` | Four filled noteheads, four stems, no flags. | Do not convert filled heads to slashes. |
| `whole-note-full-measure` | 4/4 | whole | `mustCommit` | One open notehead, no stem. | No hidden quarter expansion. |
| `two-half-notes` | 4/4 | half, half | `mustCommit` | Two open noteheads, two stems. | Hollow heads remain half notes. |
| `dotted-half-quarter` | 4/4 | dotted half, quarter | `mustCommit` | Open head plus stem plus right-side dot, then filled head plus stem. | Dot must belong to the half note. |
| `dotted-quarter-eighth-half` | 4/4 | dotted quarter, eighth, half | `mustCommit` | Filled dotted quarter, filled eighth with flag/beam, open half. | Dot and flag evidence both required. |
| `quarter-rest-quarter-rest-half` | 4/4 | quarter rest, quarter, quarter rest, quarter | `mustCommit` | Rest squiggles stay separate from notehead/stem clusters. | Quarter rests do not require noteheads. |
| `eighth-pair-first-beat` | 4/4 | eighth, eighth, quarter, quarter, quarter | `mustCommit` | Two filled noteheads, two stems, shared beam or flags. | Beam is valid inside beat one. |
| `eighth-rest-eighth-quarter-half` | 4/4 | eighth rest, eighth, quarter, half | `mustCommit` | Rest hook has no lower notehead; following eighth has its own filled notehead. | Neighboring notehead cannot satisfy rest cluster. |

## Must-Review Or Must-Not-Autocommit Fixtures

| ID | Meter | Intended read | Decision | Required local evidence | Guardrail |
| --- | --- | --- | --- | --- | --- |
| `eighth-rest-plus-eighth-not-note-pair` | 4/4 | eighth rest, eighth | `mustRejectRenderProposal` | First cluster is rest hook without lower notehead; second cluster is eighth note. | Must not become eighth, eighth. |
| `dotted-quarter-eighth-eighth-dotted-quarter` | 4/4 | dotted quarter, eighth, eighth, dotted quarter | `mustRejectRenderProposal` | Two adjacent eighths are separated by beat 3. | Must not beam eighths across protected midpoint. |
| `quarter-rest-too-small-as-eighth-rest` | 4/4 | quarter rest | `mustReview` | Ambiguous squiggle too small for quarter rest but too tall for eighth rest. | Preserve ink instead of forcing exact fit. |
| `dotted-eighth-sixteenth` | 4/4 | dotted eighth, sixteenth | `mustReview` | Eighth note with right-side dot, then double-flag/double-beam short value. | Reference-only until model supports it. |
| `sixteenth-dotted-eighth` | 4/4 | sixteenth, dotted eighth | `mustReview` | Double-flag short value followed by dotted eighth. | Do not reorder or collapse to eighth pair. |
| `four-sixteenths` | 4/4 | sixteenth, sixteenth, sixteenth, sixteenth | `mustReview` | Four filled heads/stems with double beams. | Do not flatten to eighths or quarters. |
| `eighth-triplet` | 4/4 | eighth triplet group | `mustReview` | Three beamed eighths with visible `3`. | Tuplets need explicit model support. |
| `uncovered-large-stroke` | 4/4 | quarter, quarter, unknown, half | `mustReview` | One large uncovered mark remains. | Large uncovered strokes cannot be ignored. |
| `underfilled-clean-pair` | 4/4 | eighth rest, eighth | `mustKeepWriting` | Clean supported symbols, only one beat total in 4/4. | Do not render partial measure. |
| `overflow-five-quarters` | 4/4 | quarter, quarter, quarter, quarter, quarter | `mustReview` | Five clean quarter notes. | Overflow cannot be squeezed into measure. |

## Meter And Grouping Fixtures

| ID | Meter | Intended read | Decision | Required local evidence | Guardrail |
| --- | --- | --- | --- | --- | --- |
| `six-eight-two-dotted-beats` | 6/8 | six eighth notes grouped 3 + 3 | `mustCommit` after support | Eighth noteheads and stems with grouping at dotted-quarter boundary. | Compound meter protects 3-eighth groups. |
| `six-eight-crosses-dotted-beat` | 6/8 | six eighth notes with one beam across all six | `mustReview` | Beam crosses the dotted-beat boundary. | Context rules decide whether style allows it. |
| `three-four-three-quarters` | 3/4 | quarter, quarter, quarter | `mustCommit` | Three filled noteheads and stems. | Do not expect four beats. |
| `three-eight-three-eighths` | 3/8 | eighth, eighth, eighth | `mustCommit` after support | Three short values matching top number. | Slash/rhythm count follows numerator. |

## Acceptance Bar Before V2 Auto-Commit

Before the new recognizer becomes render authority, it should pass at least:

1. all `mustCommit` fixtures currently supported by `RhythmValue`,
2. all `mustRejectRenderProposal` fixtures,
3. all underfilled/overflow safety fixtures,
4. the eighth-rest/eighth-note separation fixtures,
5. the dotted-quarter/eighth/eighth/dotted-quarter grouping fixture.

Reference-only fixtures can initially pass by producing `mustReview` with preserved ink.
