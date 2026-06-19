# iChart Sprint 56 Repeat Validation Log

Status: complete by user report
Date: 2026-05-27
Baseline commit: `1fb2670 Set up sprint 56 repeat validation`
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

Run one short real iPad/Apple Pencil pass after the Sprint 56 parser/confirmation authority fix.

This pass answers two questions only:

- Does native real-device Pencil writing feel good without simulator shared-input artifacts?
- Does the confirmation sheet stay inside compendium/parser authority?

## Pass Setup

Device path:

- real iPad
- Apple Pencil
- native app/device build, not simulator sharing
- no mouse/trackpad input during chord entry

Chord set:

- `C`
- `G/B`
- `Db7(b9)`
- `Absus`
- one natural extra chord if the chart flow wants it

## Checklist

For each chord, record:

- intended chord
- auto-render, confirmation, direct input, or failure
- rendered/accepted chord
- whether top-three suggestions were all valid compendium chords
- whether any repeated/unsupported suggestion appeared, especially `Db(b9)(b9)`
- felt speed after final stroke
- whether placement matched the intended beat/slot

Global checks:

- [x] Pencil writing feels native on the device path.
- [x] No mouse/pointer contamination appears in chord ink.
- [x] Confirmation suggestions are all valid supported chord display text.
- [x] `Db7(b9)` remains available and does not disappear because of the parser fix.
- [x] Accepted chord ink clears.
- [x] Export to PDF/Preview still works.

## Result

The user reported the bounded repeat pass as "all golden" after the Sprint 56 parser/confirmation authority fix and real-device Pencil-only input policy.

Treat this as product validation evidence only. Do not convert the pass into a new personal handwriting fixture/training loop unless a future sprint identifies a transferable regression that needs explicit test coverage.

The next active lane is the chord-first side-sprint queue, starting with placement/edit behavior.

## Decision Rules

- If native Pencil writing feels good and suggestions stay valid, close Sprint 56 and route to the next chord-first product lane.
- If native Pencil writing still lags, inspect PencilKit/input ownership before recognition or scoring.
- If unsupported suggestions appear again, keep the fix in the confirmation/compendium boundary, not in user-specific training.
- If supported altered chords disappear, inspect parser validity and candidate display text before scorer changes.
- If placement or export fails, route narrowly to that lane.
