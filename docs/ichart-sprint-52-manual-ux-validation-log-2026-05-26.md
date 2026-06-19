# iChart Sprint 52 Manual UX Validation Log

Status: validated; closeout routed to Sprint 53 validation-speed cleanup
Date: 2026-05-26
Build/commit: `bded045 Record deleted chord auto-render rejections`
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Sprint artifact: `docs/ichart-sprint-52-chord-confirmation-user-loop-2026-05-26.md`

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

5. Wrong auto-render deletion path

If a chord auto-renders incorrectly, delete it with the x control, then write the same shape again.

Expected:

- the deleted ink-origin chord records local negative feedback
- the same ink/chord pair does not silently auto-render as the same wrong chord again
- the app should route back to confirmation/direct input so the user can choose or type the intended chord

Record:

- What chord auto-rendered incorrectly?
- What did you intend?
- Did deleting it prevent the same wrong auto-render on the next attempt?

## Results

- Device: app validation pass; real-device details not re-recorded in this closeout note
- Chart: disposable validation chart
- Complete-fail attempts: user reported the new loop seems to be working
- Close-race chord: user reported the confirmation/user loop seems to be working
- Visible suggestions: no top-three presentation regression reported
- Selected or typed chord: no manual-entry escape regression reported
- Auto-render sanity chord: no auto-render regression reported
- Wrong auto-render deleted: deletion-feedback rule added and focused tests passed; user goal is to avoid a write-delete-rewrite-delete loop
- Overall feel: validated enough to move on; future work should treat infinite correction loops as a product failure, not normal behavior

## Routing

- Sprint 52 is validated and routed to Sprint 53 validation-speed cleanup.
- If complete-fail clearing is too aggressive, tune the failure loop UX before adding more correction memory.
- If top-three suggestions are not useful, improve candidate presentation before changing recognizer scoring.
- If deleting a wrong auto-render does not prevent the repeat, fix local negative-memory application before touching global recognition.
- If local memory over-applies, tighten rule application further; do not retune global scores.
