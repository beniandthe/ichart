# iChart Rhythm Recognition Overhaul Parking Lot

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Goal

Park the unreliable handwritten rhythm-recognition pipeline without removing the rhythm chart authoring tool set. The overhaul branch should keep the product surface usable for rhythm charts while the new recognizer is rebuilt against live handwriting fixtures.

## Keep Active

- Rhythm chart layout, measure sizing, systems, and scrolling behavior.
- Rhythm chart tool rows and editor mode switching.
- `MeasureRhythmMap`, `MeasureRhythmSlot`, and rhythm-map rendering.
- Existing rendered rhythm values already saved in charts.
- Raw handwritten rhythm ink persistence in the selected measure.
- Rhythm edit/select/delete affordances that operate on saved chart data.
- PDF/export behavior for charts that already contain rendered rhythm maps.

## Parked Legacy Recognition Systems

- `RhythmicNotationQuantizer`
- `RhythmicNotationRasterTemplateRecognizer`
- `VisualRhythmRecognizer` and visual phrase heuristics inside the quantizer file.
- Legacy fallback recognition and exact-fit repair paths.
- Legacy live rhythm auto-apply from handwritten ink.
- Raster/template crop ownership heuristics.
- The recent diagnostic recorder/chip work as evidence collection only, not as the trusted engine.

## Current Code Boundary

`RhythmRecognitionOverhaulGate.isLegacyAutoRenderParked` and `RhythmRecognitionOverhaulGate.isTapToRenderRecognitionEnabled` are enabled on this branch.

When the gate is enabled:

- Pencil input in rhythm mode is still persisted as raw measure ink.
- Idle live advisory recognition may persist/analyze stable raw ink and surface a "tap outside to render" state.
- Selection changes and taps are allowed after raw ink is saved and are the only render authority for recognized rhythm ink.
- The legacy recognizer does not auto-render, auto-clear, or commit rhythm maps from handwritten ink on a timer.
- Existing legacy recognizer code remains in place for reference and comparison until V2 replaces it.

## Deferred Until V2

- Any threshold tuning in the old quantizer.
- Any new raster/template rest or note heuristics.
- Any broadening of exact-fit fallback repair.
- Any timer-driven auto-commit behavior from handwritten rhythm ink.
- Any user-facing confidence claim based only on synthetic recognizer tests.

## V2 Direction

Build the next recognizer fixture-first:

1. Capture replayable iPad rhythm ink fixtures.
2. Segment strokes into candidate symbol groups.
3. Classify symbols with ranked evidence.
4. Parse against the measure grid without inventing unsupported symbols.
5. Mark exact supported reads as ready, then commit only when the user taps to render/finalize.
6. Otherwise preserve ink and show a clear recovery/check state.
