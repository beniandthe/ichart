# iChart Rhythm Section Chart Plan

Status: active Rhythm Section chart contract; core authoring and V4 rhythm gate verified locally
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Product Contract

`Rhythm Section Sheet` is the working iChart chart for players who need staff-line measures, rhythmic hits/slashes, and fast chord-roadmap authoring.

- No official key setup for now.
- Starting time and starting measures remain part of New Chart setup.
- A chart can never start with zero measures.
- Measures render with staff lines.
- Measures can be added at the beginning or after the selected measure.
- Measures can be compressed and stretched through manual width controls.
- Rhythm notation is written strictly inside the measure lane.
- Chords are written above the staff in the chord lane.
- Free-hand articulation marks are below the measure only.

## Measure System

- The current measure model remains the authority.
- New charts clamp starting measures to at least one.
- Beginning insertion reindexes measures and preserves existing measure IDs, time behavior, and anchors.
- Manual width overrides remain clamped by the existing measure-width rules for this core sprint.
- Section and system layout rules are deferred.

## Rhythm Lane

- User taps `Rhythmic Notation` to lock into rhythm notation.
- Rhythm Section keeps rhythmic-notation ink enabled through `ChartLayoutProfile`, while styles that do not own a rhythm lane cannot enter that active ink scope.
- Ink is scoped to the selected measure's writable rhythm area.
- The quantizer reads rhythm symbols left to right.
- A rhythm map auto-commits when the recognized values fit the measure exactly and the measure proposal is safe to auto-apply.
- Underfilled, overflow, and unsupported rhythm passes stay local while the user is still writing.
- `RhythmicNotationCompendium` is the final gate for supported rhythm values and exact meter fit.
- Supported v1 vocabulary: forward slash, quarter, half, whole, single eighth, beamed eighth notes, dotted quarter, dotted half, eighth rest, quarter rest, half rest, whole rest.
- Beamed eighth handwriting includes separate-stem beams, sloped beams, and folded beam/right-stem gestures when local stem/notehead evidence supports that read.
- If protected beamed-eighth ink is underfilled, it stays local instead of falling through to a longer dotted-value reinterpretation for false exact-fit auto-render.
- The visual rhythm pass protects stemmed noteheads from being read as eighth rests before attached stem/dot evidence is considered, and it treats local touch-up strokes around a beamed pair as part of that beamed event before fallback grouping runs.
- Auto-render uses a measure proposal that can request extra stability for terminal quarter-like stems with eighth alternatives, so a last-beat beamed pair is not cleared while the first eighth still looks like a quarter.
- Auto-render can also mark exact-fit proposals for manual review. Current V4 evidence can clear strong single-crop whole-note reads automatically, while whole rests and low-information whole-like marks remain review-only.
- Rhythm notation opens with a left-side write/erase tab in write mode. Erase mode uses the stylus as an ink-only eraser for the active handwritten rhythm strokes and does not affect rendered rhythm maps.
- After erasing rhythm ink, rendering can commit only if the remaining ink is a natural exact-fit read, which preserves the valid "erase the extra symbol" flow while blocking stretched missing-beat reinterpretations.
- Natural exact fit is now required for all live rhythm commits and selection finalization. Fallback meter-fit proposals can remain diagnostic/manual evidence, but they cannot clear ink or render automatically.
- Rhythm Recognition V3 has started rebuilding the internals around ordered ink primitives, symbol hypotheses, phrase hypotheses, and explicit commit/keep-writing/review decisions.
- Only a V3 `commit` decision can render and clear rhythm ink. `keepWriting` and `needsReview` keep the handwritten rhythm local to the measure.
- Rhythm Recognition V4 now owns the first deterministic raster/template phrase gate ahead of V3. It crops live measure ink left-to-right, matches supported visual templates, validates exact values through the rhythm compendium and `MeasureRhythmMap`, rejects tiny isolated noise before crop grouping, and requires render alignment before auto-commit.
- The V4 raster/template core lives in `RhythmicNotationRasterTemplateRecognizer.swift`; `RhythmicNotationQuantizer` remains the public entrypoint and fail-closed bridge into the current rhythm proposal flow.
- Unsupported or ambiguous V4 crops stay local; completed-looking unread crops can be highlighted at the symbol level instead of blaming the whole measure.
- V4 visual note anchors are available for Lead Sheet pitch snapping, but Rhythm Section keeps rendering committed rhythm maps as slash/rest notation and does not store pitched-note events.
- Individual rhythm editing is not a Rhythm Section user-facing workflow yet; the layout profile owns that disabled state so the editor does not hardcode a style exception.

## Chord Lane

- Chords stay above the staff.
- If a measure has a rhythm map, chords snap to playable rhythm slots.
- Rest slots remain non-playable snap targets.
- If a measure has no rhythm map, the first chord falls back to beat 1 and later chords use the beat grid.
- Moving a chord reuses the same snap target map instead of creating a second placement authority.
- The active move interaction draws a guide from the chord box to the resolved beat/rhythm attack target.

## Free-Hand Articulation Lane

- Rhythm Section free-hand symbols are raw ink objects anchored to a measure.
- The only supported lane is below the staff.
- These marks are editable and movable like Simple Chord Sheet free-hand symbols.
- They are not recognized, rhythm-snapped, or promoted into global recognizer training.

## Deferred

- Section/system layout.
- Individual rhythm editing for Rhythm Section.
- Lead Sheet pitched-note entry belongs to the separate Lead Sheet baseline, not this Rhythm Section contract.
- Articulation recognition.
- Any new recognition scoring, OCR expansion, fixture expansion, or symbol-ledger runtime diagnostics.
