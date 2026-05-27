# Smart Chart Chord-First Side Sprints

Status: active side-sprint lane
Created: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

This document keeps the chord-specific improvement lane organized while the living sprint source of truth remains the active authority.

Use these side sprints for focused chord work after the Sprint 56 field-validation pass. Each side sprint should be small enough to implement, verify, and close without reopening the whole recognition/audit recovery plan.

## Guardrails

- Auto-render remains the preferred lane when confidence and compendium validation are strong.
- Close races route to concise confirmation with the top supported choices and direct input.
- Complete recognition misses should recover quickly without trapping the user in a write -> fail -> rewrite loop.
- User feedback may create local correction rules, exclusions, or rejection memory, but it must not become global handwriting training.
- Suggestions and accepted chords must always pass `ChordRecognitionCompendium` / `ChordSymbolParser` authority.
- OCR and symbol-ledger evidence remain sidecars only.
- Verification should stay proportional. Use focused tests for focused chord UX changes; reserve full app or full CI waits for broad recognition, editor, export, or project-configuration changes.

## Current Working State

- The native iPad/Apple Pencil path is the product validation path for writing feel.
- Chord ink clears after accepted render.
- PDF export now exports the full chart page and worked in the post-export field pass.
- `C`, `G/B`, `Db7(b9)`, and `Absus` have all been through bounded real-use validation without adding personal handwriting as training data.
- Confirmation UX is cleaner than the first implementation and no longer intends to expose raw unsupported recognizer strings.
- Placement and timing diagnostics exist and can support targeted placement/render follow-up.

## Open Product Questions

- Can rendered chords be placed, inspected, and corrected with less friction after recognition?
- Can a wrong auto-render be replaced without creating a repeated write -> delete -> rewrite trap?
- Can direct input feel like part of the flow rather than a debug fallback?
- Are there general candidate-availability gaps that should be fixed at the compendium/composer boundary without one-writer score retuning?
- Is perceived final-stroke-to-render time now good enough across basic and complex chords, or does the handoff still need polish?

## Side Sprint Queue

### Side Sprint 57: Chord Placement And Edit Loop

Status: complete locally; awaiting GitHub verification.

Goal: make the post-render chord feel editable and correctly anchored after recognition.

Candidate work:

- Kept current placement math and move APIs intact.
- Enlarged delete/move controls for a more Pencil/finger-friendly edit target.
- Added an explicit move grip and active move highlight.
- Added focused iOS geometry coverage for delete, move, and review hit-target priority.

### Side Sprint 58: Wrong Render Recovery And Replace UX

Status: active.

Goal: make wrong auto-renders recover cleanly.

Candidate work:

- Treat deletion of an ink-origin rendered chord as local negative feedback for that ink/chord pairing.
- Route repeated rejection away from the same auto-render and toward confirmation or direct input.
- Make the replacement path obvious without forcing another full rewrite when direct correction is faster.

### Side Sprint 59: Confirmation And Direct Input Polish

Goal: turn confirmation/direct entry into a calm product loop.

Candidate work:

- Keep the sheet centered around three supported candidates, one manual field, and clear accept/rewrite actions.
- Ensure manual entry that beats all suggestions records the right local exclusion/correction evidence.
- Avoid creating local positive rules from extremely tight competitions.

### Side Sprint 60: General Candidate Availability Hardening

Goal: fix transferable chord-family gaps without handwriting-specific training.

Candidate work:

- Search diagnostics for missing supported candidates before touching scores.
- Improve compendium/parser/composer availability for general families such as suspended, slash, flat-root, and altered-extension chords.
- Add only transferable regression tests, not another personal fixture loop.

### Side Sprint 61: Raster/Render Handoff Polish

Goal: keep the writing-to-render handoff feeling immediate without premature rendering.

Candidate work:

- Inspect timing telemetry before changing debounce or render policy.
- Separate recognition wait from commit/render/export work.
- Keep `PKCanvasView` as the native ink renderer.

### Side Sprint 62: Chord-First Release Candidate Pass

Goal: close the chord-first lane with one bounded real chart pass.

Candidate work:

- Validate write -> recognize -> auto-render or confirm -> clear ink -> edit if needed -> export.
- Capture only summary evidence unless a new bug needs diagnostics.
- Move remaining non-chord polish back to the normal backlog.
