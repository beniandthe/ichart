# iChart Rhythm Recognition Boundary

Date: 2026-06-22
Branch: `codex/rhythm-recognition-overhaul`

## Goal

Park handwritten rhythm recognition as research and keep the shipping rhythm-entry path reliable. V1 ships without the dedicated Rhythm tool; Rhythm Section users enter rhythm notation with Free-Write until a literal rhythm input method is designed and implemented.

## Keep Active

- Rhythm chart layout, measure sizing, systems, and scrolling behavior.
- `MeasureRhythmMap`, `MeasureRhythmSlot`, and rhythm-map rendering.
- Existing rendered rhythm values already saved in charts.
- Free-Write page ink for rhythm notation, cues, articulations, and personal markings.
- PDF/export behavior for charts that already contain rendered rhythm maps.

## Current Recognition System

- The dedicated Rhythm toolbar tool is hidden and unavailable in the shipping editor.
- `RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool` is disabled.
- `EditorCanvasMode.allowsDirectRhythmicNotationInk` is false while the gate is disabled, so live Pencil input cannot enter the recognizer path from the app surface.
- Existing rhythm reference documents remain parked for future research, but no recognizer path is part of the active rhythm-entry UX.

## Parked Recognizer Research

- `RhythmicNotationQuantizer` remains as parked research code and must not be reachable from the shipping editor while the dedicated Rhythm tool is retired.
- `RhythmicNotationRecognitionTypes` owns the archived decision, phrase, typed glyph-evidence, symbol, and proposal contracts.
- `RhythmRecognitionContextRules` remains as archived meter, grouping, beaming, and impossible-render context.
- `RhythmRecognitionOverhaulGate.isConstrainedGlyphOCRPrimaryForSimpleMeters` is disabled while the dedicated tool is retired.

## Removed Systems

- Timer-driven rhythm map commits from handwritten ink.
- Whole-measure inferred repair paths that invent a fit without local glyph evidence.
- Cross-path arbitration between competing recognizers.
- Constrained OCR experiments from the rejected rhythm-recognition pass.
- Template crop ownership as a runtime recognition authority.
- One-off diagnostic helpers that bypass the current glyph OCR decision contract.

## Future Build Direction

Build a literal rhythm input method before reintroducing any dedicated rhythm tool:

1. Keep Free-Write as the reliable rhythm-entry path for launch.
2. Design a literal selector/palette for rhythms, rests, dots, ties, and grouped beaming.
3. Make selector input deterministic: no shape guessing, no inferred render from handwriting.
4. Preserve the existing rhythm-map renderer/export path for data created by the future selector.
5. Revisit handwritten recognition only as an optional research surface after the literal input loop is trusted.
