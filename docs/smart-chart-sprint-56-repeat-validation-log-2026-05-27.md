# Smart Chart Sprint 56 Repeat Validation Log

Status: ready
Date: 2026-05-27
Baseline commit: `1ef7980 Restore supported altered extensions`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

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

- [ ] Pencil writing feels native on the device path.
- [ ] No mouse/pointer contamination appears in chord ink.
- [ ] Confirmation suggestions are all valid supported chord display text.
- [ ] `Db7(b9)` remains available and does not disappear because of the parser fix.
- [ ] Accepted chord ink clears.
- [ ] Export to PDF/Preview still works.

## Decision Rules

- If native Pencil writing feels good and suggestions stay valid, close Sprint 56 and route to the next chord-first product lane.
- If native Pencil writing still lags, inspect PencilKit/input ownership before recognition or scoring.
- If unsupported suggestions appear again, keep the fix in the confirmation/compendium boundary, not in user-specific training.
- If supported altered chords disappear, inspect parser validity and candidate display text before scorer changes.
- If placement or export fails, route narrowly to that lane.
