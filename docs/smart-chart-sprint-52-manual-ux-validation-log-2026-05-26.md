# Smart Chart Sprint 52 Manual UX Validation Log

Status: ready for bounded manual pass
Date: 2026-05-26
Build/commit: `0a59588 Add sprint 52 chord confirmation user loop`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Sprint artifact: `docs/smart-chart-sprint-52-chord-confirmation-user-loop-2026-05-26.md`

## Purpose

Validate the new chord confirmation/user loop with one short real app pass.

This is not a recognition-training pass and not a fixture-capture loop. The only goal is to prove whether the new UX rules feel right:

- auto-render stays the default when trust is clear
- complete misses clear quickly for two attempts
- the third miss opens direct input
- close races show top-three choices
- manual entry remains available when suggestions are wrong

## Pass Setup

- Device: real iPad with Apple Pencil preferred
- Chart: any disposable test chart
- Mode: chord entry
- Export: not required unless the pass naturally reaches export

## Checklist

1. Complete-fail rewrite loop

Write an intentionally invalid or unreadable chord symbol in one measure slot.

Expected:

- attempt 1: ink clears automatically, no blocking sheet
- attempt 2: ink clears automatically, no blocking sheet
- attempt 3: direct input/confirmation opens

Record:

- Did ink clear fast enough after attempts 1 and 2?
- Did the third miss open direct input instead of silently clearing again?
- Did anything feel confusing or too aggressive?

2. Close-race confirmation

Write one chord that naturally creates ambiguity, preferably an altered or slash/altered shape.

Expected:

- confirmation sheet appears when the app is unsure
- only the top three supported suggestions are shown
- selecting a visible suggestion commits a structured chord and clears ink

Record:

- Were the three suggestions useful?
- Was the right chord present?
- Did the sheet feel fast enough?

3. Manual-entry exclusion path

When suggestions are wrong, type the intended supported chord manually.

Expected:

- manual entry commits through compendium/parser validation
- ink clears after commit
- the app should not appear to over-bias toward the wrong top-three suggestion set later

Record:

- What were the visible suggestions?
- What chord did you type?
- Did manual entry feel like a clear escape hatch?

4. Normal auto-render sanity check

Write one simple chord that already worked well, such as `C` or `G/B`.

Expected:

- no unnecessary confirmation
- no new latency or ink-clearing regression

## Results

Fill this section after the pass.

- Device:
- Chart:
- Complete-fail attempts:
- Close-race chord:
- Visible suggestions:
- Selected or typed chord:
- Auto-render sanity chord:
- Overall feel:

## Routing

- If this feels right, close Sprint 52 and route Sprint 53 to the next product polish lane.
- If complete-fail clearing is too aggressive, tune the failure loop UX before adding more correction memory.
- If top-three suggestions are not useful, improve candidate presentation before changing recognizer scoring.
- If local memory over-applies, tighten rule application further; do not retune global scores.
