# Recognizer Decision Contract

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Purpose

This parked contract defines what any future rhythm recognition pass would need to return before it could affect the chart. The shipping editor does not use handwritten rhythm recognition; rhythm entry ships through Free-Write until a literal rhythm input method is implemented.

If recognition is revisited, it is not allowed to be a black box that returns only `[RhythmValue]`. It must explain:

1. what ink it saw,
2. what typed glyph evidence it extracted,
3. which symbols it considered,
4. how those symbols fit the meter,
5. whether grouping or beaming rules were violated,
6. why the result committed, kept waiting, or requested review.

## Contract Shape

Every decision must map to one of the existing decision outcomes:

| Outcome | Meaning | Allowed chart effect |
| --- | --- | --- |
| `commit` | The recognizer found a supported, exact-fit, context-valid phrase. | Mark ready during idle; render and clear committed ink only when tap/finalization allows commit. |
| `keepWriting` | The ink is incomplete, empty, or still plausibly in progress. | Preserve ink and keep the measure active. |
| `needsReview` | The recognizer found something useful but unsafe for automatic render. | Preserve ink, keep the measure selected, and show review/rewrite options. |

Live advisory recognition is parked with the dedicated Rhythm tool. If it returns later, advisory passes may inspect stable selected rhythm ink, update diagnostics, and show readiness/review feedback, but they must not render values, clear ink, or mutate the rhythm map until an explicit literal or user-confirmed action commits.

## Required Fields

Each recognition attempt should expose these fields through `RhythmPhraseHypothesis`, `RhythmicNotationMeasureProposal`, diagnostics, or their V2 replacements.

| Field | Required for | Description |
| --- | --- | --- |
| `source` | all outcomes | The recognizer layer that produced the phrase. Future research must identify its source explicitly; no source is active in the shipping editor. |
| `strokeCoverage` | all outcomes with ink | Which input strokes were consumed and which were left uncovered. |
| `glyphEvidence` | all outcomes with ink | Local typed glyph evidence such as filled/open notehead, stem, single/double beam, duration dot, tie arc, slash, quarter-rest zigzag, eighth-rest hook, sixteenth-rest double hook, half-rest block, or whole-rest block. |
| `symbolHypotheses` | all outcomes with ink | Candidate rhythm symbols per cluster, including rejected alternatives when useful. |
| `selectedValues` | `commit`, `needsReview` | The selected rhythm values, if any. |
| `candidateScores` | `commit`, `needsReview` | Confidence or distance scores per candidate path. |
| `meter` | all outcomes | Time signature context for the active measure. |
| `durationUnits` | `commit`, `needsReview`, underfilled/overflow `keepWriting` | Natural duration total and target duration total. |
| `groupingBoundaries` | all short-value outcomes | Beam boundaries and protected meter boundaries from `RhythmRecognitionContextRules`. |
| `reason` | non-commit outcomes | Exact reason: underfilled, overflow, unsupported, ambiguous, uncovered strokes, non-natural exact fit, or manual review. |
| `safeUserAction` | non-commit outcomes | What the app should do next: wait, preserve ink, ask for review, or show rewrite controls. |

## Commit Requirements

A `commit` is allowed only when all of these are true:

1. Every non-noise stroke is covered by a local symbol or deliberate modifier.
2. Each committed symbol has enough local visual evidence.
3. The selected values are supported by the current renderer/model.
4. The values exactly fit the active meter without stretching.
5. `RhythmRecognitionContextRules` does not report a protected grouping violation.
6. Rest clusters remain rest-owned; neighboring notes cannot donate noteheads.
7. Dots, beams, ties, and tuplets modify existing values instead of creating hidden values.
8. No stronger conflicting candidate remains unresolved.

## Keep-Writing Requirements

Use `keepWriting` when the ink is probably incomplete or intentionally still in progress:

- no ink,
- underfilled but visually coherent,
- a dot, beam, tie, or second stroke may still be arriving,
- live drawing has changed since the recognition attempt started.

The chart must not render a partial guess during `keepWriting`.

## Needs-Review Requirements

Use `needsReview` when the recognizer sees meaningful musical intent but cannot safely offer a tap-render proposal:

- unsupported value, such as sixteenth, dotted eighth, dotted rest, or triplet in the current V1 model,
- exact duration fit but weak local visual evidence,
- competing exact-fit phrases,
- rest/note conflict,
- uncovered strokes,
- beam crossing a protected meter boundary,
- phrase only fits by stretching or by inventing a whole-measure fit without local glyph evidence.

The app should preserve ink and make the proposed reading inspectable.

## Hard Negative Rules

These cases must not render without user confirmation:

1. An eighth-rest-shaped cluster cannot become an eighth note unless that cluster has its own lower filled notehead.
2. A beam cannot force two eighths together across a protected beat or meter boundary.
3. A slash cannot replace a real note/rest candidate just because it makes the measure fit.
4. A dot cannot be inferred from notehead overdraw without clear right-side duration-dot evidence.
5. A reference-only rhythm value cannot be collapsed to the nearest supported value just to avoid review.
6. Uncovered strokes cannot be ignored if they are large enough to represent a symbol or modifier.

## Diagnostics Minimum

For debug builds, every non-commit should be explainable in one compact diagnostic string:

`source=<layer> reason=<reason> values=<candidate-values> units=<natural>/<target> uncovered=<count> grouping=<status>`

Examples:

- `source=gridFirst reason=underfilled values=eighthRest,eighth units=1/8 uncovered=0 grouping=ok`
- `source=gridFirst reason=manualReview values=dottedEighth,sixteenth units=1/4 uncovered=0 grouping=unsupported`
- `source=gridFirst reason=ambiguousPhrase values=eighth,eighth|eighthRest,eighth units=1/4 uncovered=0 grouping=rest-note-conflict`

## Build Order

1. Local stroke clustering.
2. Typed glyph-evidence assignment.
3. Per-cluster symbol hypotheses.
4. Phrase candidate path search.
5. Meter exact-fit validation.
6. Grouping and beaming validation.
7. Decision contract output.
8. UI commit/review/keep-writing behavior.
