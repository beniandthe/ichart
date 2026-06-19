# iChart Sprint 51 Real-Life Polish

Status: complete; routed to Sprint 52 correction UX
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Prior evidence: `docs/ichart-sprint-50-post-stroke-responsiveness-2026-05-26.md`

## Purpose

Sprint 51 moves out of the bounded chord-recognition loop and into broader real-life product polish.

The core writing-to-render path is now good enough to test as an app flow: open -> write -> recognize -> snap -> fix -> export.

## Current Product State

- Native PencilKit writing feel is preserved.
- `C` and `G/B` auto-render reliably in the bounded pass.
- `Db7(b9)` no longer falls into empty suggestions; it confirms when close and keeps supported choices available.
- Export/share has already been fixed for full-chart PDF output.
- Recognition remains writer-agnostic: no personal fixture expansion, no score retuning from one writer, no OCR expansion, and no default symbol-ledger diagnostics cost.

## Sprint 51 Goals

- Run the app as a real chart-writing tool rather than a narrow chord fixture loop.
- Identify product friction across the full pipeline: opening a chart, writing chords, correcting close races, snapping/placing content, exporting, and returning to the chart.
- Keep each follow-up scoped to an observed product issue.
- Prefer one small product polish implementation at a time, with focused checks.

## Non-Goals

- No handwriting training loop.
- No broad recognition score tuning.
- No fixture corpus expansion.
- No speculative OCR or symbol-ledger authority changes.
- No long full-suite verification unless a sprint touches broad recognition, editor, export, or project configuration surfaces.

## First Evidence Pass

Use one normal chart-writing pass, not a stress test:

- Create or open a real chart.
- Write a short musical sequence with a mix of simple chords, slash chords, and one altered chord.
- Use correction only when the app asks for confirmation.
- Export the chart to PDF.

Capture:

- Whether writing feels native.
- Whether recognition waits, renders early, or asks for confirmation appropriately.
- Whether close-race correction is easy enough.
- Whether chord placement/snapping feels right.
- Whether export produces the actual full chart.
- Any duplicate-screen, navigation, or Library friction.

## Decision Routing

- If the full flow feels good, close the recovery/audit arc and move to feature prioritization.
- If correction friction is the main issue, route Sprint 52 to correction UX.
- If placement/snapping is the main issue, route Sprint 52 to chart placement polish.
- If export/share regresses, route Sprint 52 to export.
- If Library/navigation friction dominates, route Sprint 52 to app-shell polish.

## Outcome

The user chose correction UX as the first product polish lane after the bounded writing-to-render loop felt good. Sprint 52 starts the chord confirmation/user loop system:

- auto-render remains the preferred lane
- complete failures auto-clear for two attempts, then direct input appears
- close races show the top three suggestions
- local user-specific correction rules may apply only to non-extremely-tight close races
- manual entry after wrong suggestions records a local exclusion
- no personal handwriting fixture expansion, score retuning, OCR expansion, or symbol-ledger diagnostics cost
