# Smart Chart Sprint 47 Timing Capture Log

Status: ready for real iPad/Pencil timing pass
Date: 2026-05-26
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Triage artifact: `docs/smart-chart-sprint-47-confidence-performance-triage-2026-05-26.md`
Test build: current green `main` at `b8add53 Set up sprint 47 timing capture`

## Purpose

Capture one bounded real-device pass with the Sprint 47 debug timing labels.

This pass is not training data. It should classify the remaining delay for `C` and `G/B` without expanding personal handwriting fixtures, retuning scores, enabling default OCR, or adding symbol-ledger diagnostics cost.

## Capture Setup

- tester:
- device model:
- iPadOS version:
- Apple Pencil model:
- app build/commit: `b8add53`
- date/time:
- chart title:
- Xcode/device console log file:
- exported PDF result:

## Console Lines To Preserve

Save the complete lines for each chord attempt:

- `SmartChart chord timing: ...`
- `SmartChart chord proposal: ...`
- `SmartChart chord commit: ...`

Then summarize them locally with:

```bash
python3 scripts/analyze_chord_timing_logs.py path/to/device-console.log
```

## Bounded Cases

| Case | Expected route | Timing result | Perceived latency | Trust/correction | Ink clearing | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `C` | Clear auto-render if confidence is high enough | Pending | Pending | Pending | Pending | Pending | Capture timing/proposal/commit lines |
| `G/B` | Clear slash-chord auto-render if confidence is high enough | Pending | Pending | Pending | Pending | Pending | Capture timing/proposal/commit lines |
| `Db7(b9)` | Confirmation-gated, quick control case | Pending | Pending | Pending | Pending | Pending | Do not change this route unless evidence shows a transferable issue |

## Parsed Timing Table

Paste the parser output here after the pass.

| attempt | best | accepted | confidence | primaryAction | finalAction | trust | agreement | closeRace | gap | delayMs | idleMs | recognitionMs | totalMs | proposalMs | commitMs | ocrCount | ocrMs | reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending | Pending |

## Decision Routing

- [ ] Scheduler/waiting policy: choose only if `delayMs` or `idleMs` dominates while recognition/proposal/commit are low.
- [ ] Recognizer compute/candidate conflict: choose if `recognitionMs` or `totalMs` dominates, especially with many candidates/sequences or close-race evidence.
- [ ] Confidence/ink interpretation: choose if `C` or `G/B` stay low confidence or confirmation-routed despite low compute cost.
- [ ] UI proposal/commit: choose if `proposalMs` or `commitMs` is high.
- [ ] Render/update handoff: choose if recognizer/proposal/commit are all low but the visual render still appears late.
- [ ] Export/share regression: choose only if PDF export fails again.

## Guardrails

- Do not add new personal handwriting fixtures from this pass.
- Do not retune recognition scores from one writer's pass.
- Do not broaden OCR beyond the existing ambiguity-only, compendium-gated sidecar.
- Do not enable symbol-ledger diagnostics by default.
- Preserve chord ink clearing after accepted render.
- Preserve `Db7(b9)` confirmation routing unless a general trust issue is proven.
