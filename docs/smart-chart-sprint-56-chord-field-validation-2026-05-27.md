# Smart Chart Sprint 56: Chord Field Validation

Status: active
Date: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Goal

Run one bounded real iPad/Apple Pencil pass that validates the Sprint 55 chord-first changes in real use before more architecture work.

This sprint is evidence-first. It should decide the next chord-related implementation lane from product evidence:

- fast writing feel
- pointer/mouse exclusion on real device chord entry
- placement/snapping
- render/update handoff
- confidence/accuracy for the current supported chord set
- export fidelity

## Non-Goals

- Do not add personal handwriting fixtures.
- Do not retune recognition scores from one writer's pass.
- Do not expand OCR authority.
- Do not change symbol-ledger diagnostics cost.
- Do not start broad editor cleanup unless the field pass proves a specific editor bottleneck.

## Pass Setup

Use the current real-device build containing app commit `1ef7980 Restore supported altered extensions`.

Pass device:

- real iPad
- Apple Pencil
- avoid intentional mouse/trackpad input except for a quick negative check if convenient

Suggested chord set:

- `C`
- `G/B`
- `Db7(b9)`
- `Absus`
- one or two additional common chords that feel natural in the chart

Suggested placement check:

- write one chord near an obvious early beat
- write one chord near a later beat/start in a measure with longer rhythm value
- check whether the rendered chord lands where the writing intent felt clear

Suggested export check:

- export the resulting chart to PDF/Preview
- confirm the exported page matches the actual chart page, not old card blocks

## What To Record

For each notable chord:

- intended chord
- rendered or confirmed chord
- auto-render, confirmation, direct input, or failure
- felt speed after final stroke
- whether the ink felt native or like fighting the canvas
- whether any cursor/mouse/pointer stroke appeared in chord ink
- whether placement matched the intended beat/slot

Also record:

- whether accepted ink cleared
- whether export worked
- whether the confirmation sheet felt helpful when it appeared

## Acceptance Criteria

- Real device chord entry accepts Apple Pencil input without pointer/mouse contamination.
- Fast writing does not feel like the app is fighting the active stroke.
- `C`, `G/B`, `Db7(b9)`, and `Absus` remain usable without personal-fixture expansion.
- Placement evidence can be reviewed from diagnostics after the pass.
- Export still produces the full chart page.
- The next implementation sprint is chosen from the pass evidence, not from a broad recognition retune.

## Verification Plan

- Keep existing automated checks proportional unless code changes after the pass.
- Use `scripts/audit_chord_entry_diagnostics.py --details --scores 3` against the simulator or available app data when pass metadata is available.
- Use `git diff --check` for doc-only updates.

## Decision Rules

- If writing still feels like fighting the canvas, inspect PencilKit/input ownership before recognition.
- If timing feels slow but diagnostics show recognition/proposal/commit/render are low, inspect scheduler or UI update handoff.
- If placement is wrong, inspect placement/snapping and rhythm-map evidence.
- If suggestions are wrong or missing, inspect candidate availability before score tuning.
- If export is wrong, route to renderer/export fidelity.

## Pass Finding: Simulator Shared Input And Confirmation Authority

The first Sprint 56 report exposed two separate issues:

- When the tester manually removed the visible mouse cursor from simulator sharing on iPad, active ink felt much laggier. Treat this as simulator/shared-input evidence only. The current app policy keeps simulator chord entry on `.anyInput` for automation and shared-pointer testing, while real iPad/device chord entry uses `.pencilOnly`. Native real-device Pencil feel still needs to be validated separately from simulator sharing.
- The confirmation sheet surfaced unsupported raw chord text such as `Db(b9)(b9)`. This is a hard authority-boundary bug: confirmation suggestions must come only from compendium/parser-approved display text.

Sprint 56 follow-up:

- Reject repeated alterations and root-only altered suffixes such as `Db(b9)` / `Db(b9)(b9)` at the parser/compendium boundary.
- Keep `Db7(b9)` valid and supported.
- Build confirmation suggestions from ranked supported scores, the primary match, and supported OCR display text only; do not promote raw recognizer strings into the user-facing top-three list.

## Repeat Pass Gate

Status: ready after green checks for `1ef7980 Restore supported altered extensions`.

Use `docs/smart-chart-sprint-56-repeat-validation-log-2026-05-27.md` for the next bounded pass.

Keep this pass narrow:

- validate native iPad/Pencil feel rather than simulator sharing feel
- confirm no mouse/pointer contamination on the real-device chord-entry path
- confirm the confirmation sheet shows only compendium/parser-approved suggestions
- confirm `Db(b9)(b9)` or similar raw unsupported strings do not appear as suggestions
- confirm `Db7(b9)` and existing altered-extension families remain available
