# iChart Sprint 46 Latency Repeat Log

Status: repeat complete; Sprint 47 confidence/performance split selected
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Latency triage: `docs/ichart-recognition-latency-triage-2026-05-26.md`
Test build: `72e6d91 Tune sprint 46 chord recognition scheduling`

## Purpose

Repeat the short real-device product pass after Sprint 46 scheduler tuning.

This pass answers one question: does the writing-to-render loop feel faster and trustworthy enough after the scheduler change?

This is not a handwriting-training pass. Do not add fixtures, expand the corpus, or retune recognition scores from this pass unless a later sprint identifies a transferable regression that should generalize beyond one writer.

## What Changed

- Default chord-ink idle delay changed from `1.2s` to `0.85s`.
- Root-only continuation grace changed from `1.2s` to `0.55s`.
- Extension prefixes still keep the full `1.2s` continuation grace.
- Slash chords and altered chords still do not use continuation grace.
- `Db7(b9)` remains confirmation-gated.

## Test Setup

- tester: Beni
- device model:
- iPadOS version:
- Apple Pencil model:
- app build/commit: `72e6d91`
- date/time: user-reported pass complete on 2026-05-26
- chart title:
- notes on input environment: real iPad/Pencil pass; exported PDF without issues.

## Preflight

- [x] App opens to Projects/Library.
- [x] Clean chart is created or opened.
- [x] Chord-writing mode is reachable.
- [x] Apple Pencil writes native ink before recognition starts.
- [x] Export/share path is reachable.

## Bounded Cases

| Case | Expected route | Actual route | Perceived latency | Trust/correction | Ink clearing | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `C` | Auto-render after shorter scheduler wait, no premature render | Low-confidence path | Still took time | Confidence/ink accuracy is now the blocker | Not reported as failing | PDF export passed | Slowdown appears tied to confidence, not only debounce policy |
| `G/B` | Auto-render slash chord after shorter idle window | Low-confidence path | Still took time | Confidence/ink accuracy is now the blocker | Not reported as failing | PDF export passed | Slowdown appears tied to confidence, not only debounce policy |
| `Db7(b9)` | Confirmation, not blind auto-render | Extremely quick | Fast | Confirmation/trust route felt acceptable | Not reported as failing | PDF export passed | Altered chord was faster than the clear-case low-confidence reads |

## Pass Questions

- Did `C` feel materially faster than the previous couple-second delay?
- Did `C` ever render too early while the chord was still being written?
- Did `G/B` feel materially faster or at least no worse?
- Did `Db7(b9)` still require confirmation and accept cleanly?
- Did accepted chord ink clear after render/confirmation?
- Did export/share still produce the full chart PDF?
- Did any stroke break, duplicate screen state, or unexpected UI issue reproduce?

## Decision Routing

- [ ] Close Sprint 46 - choose this if `C`/`G/B` feel faster enough, `Db7(b9)` remains trustworthy, ink clears, and export still works.
- [x] Inspect live timing logs - choose this if `C` or `G/B` still feels slow after the scheduler change.
- [ ] Revisit scheduler policy - choose this only if timing evidence shows remaining wait is still intentional debounce/grace policy.
- [x] Route to recognition trust sprint - choose this only if `Db7(b9)` or another general chord class exposes a transferable trust issue.
- [ ] Route to input/UI sprint - choose this if stroke breaks, duplicate UI state, or export regression reproduces.

## Decision Notes

The repeat did not show export trouble, and `Db7(b9)` was extremely quick. The remaining slow path is now `C` and `G/B` entering low-confidence handling, which means Sprint 46's scheduler-only fix is not enough to close the product concern.

The next sprint should separate two issues before making any recognition change:

- confidence/ink accuracy: why clear `C` and `G/B` are low confidence on real Pencil input
- conflict/performance/render time: whether extra delay is candidate conflict handling, trust routing, UI proposal/commit/render handoff, or actual drawing-to-render cost

Do not treat this pass as training data. It is product evidence that the next sprint needs timing and confidence instrumentation before score tuning.

## Guardrails

- Do not expand personal handwriting fixtures.
- Do not retune recognition scores from this pass.
- Do not enable default OCR or symbol-ledger diagnostics.
- Do not change export/share, ink clearing, or confirmation routing during the repeat.
