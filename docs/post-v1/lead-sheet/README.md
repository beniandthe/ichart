# Post-V1 Lead Sheet Archive

Status: deferred until after V1
Created: 2026-05-29
Source of truth: `../../ichart-sprint-source-of-truth.md`

## Purpose

This directory preserves Lead Sheet planning and implementation notes for after iChart V1 ships.

The active V1 focus is now:

- `Simple Chord Sheet`
- `Rhythm Section Sheet`

Lead Sheet work should not drive Sprint 68 implementation decisions unless it is needed to preserve compatibility with existing code paths.

## Deferred Boundary

Lead Sheet is intentionally deferred because it pulls iChart toward full notation behavior. V1 should prove the chord-first and rhythm-aware product loop through Simple Chord Sheet and Rhythm Section Sheet before returning to richer Lead Sheet systems.

Deferred Lead Sheet systems include:

- named pitch spelling
- clef-aware pitch semantics beyond the current visual baseline
- key-aware note accidentals
- ledger-line policy and rendering
- individual note editing/moving
- richer beam engraving
- melody-entry UX
- full lead-sheet export polish

## Preserved Artifacts

- `ichart-lead-sheet-pitched-note-baseline-2026-05-29.md`: the implemented baseline and verification record for clef/key signature rendering plus the first narrow pitched-note proof.
- `jazz-lead-sheet-build-plan.md`: older historical concept work. Treat it as inspiration only; do not let the post-V1 Lead Sheet direction become genre-locked or jazz-only.

## Current Code Baseline To Preserve

- `ChartLayoutStyle.leadSheet` still exists for compatibility with the current layout-profile architecture.
- Lead Sheet setup can store key, time signature, starting measures, and treble/bass clef.
- The current renderer can show clef/key-signature layout and the narrow pitched-note baseline.
- These behaviors should remain stable, but new Lead Sheet feature work is parked until after V1.

## Resume Criteria

Return to this directory after V1 when:

- Simple Chord Sheet and Rhythm Section Sheet have a stable authoring/export loop.
- section labels, roadmap objects, cue text, and per-style export are working for the V1 sheet styles.
- the product intentionally chooses to expand from chord-first/rhythm-aware charting into richer notation-like Lead Sheet behavior.
