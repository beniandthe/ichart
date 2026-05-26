# Smart Chart Sprint 47 Timing Capture Log

Status: simulator/Preview evidence recorded; real iPad/Pencil timing capture still pending if latency persists
Date: 2026-05-26
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Triage artifact: `docs/smart-chart-sprint-47-confidence-performance-triage-2026-05-26.md`
Test build: current green `main` at `b8add53 Set up sprint 47 timing capture`

## Purpose

Capture one bounded real-device pass with the Sprint 47 debug timing labels.

This pass is not training data. It should classify the remaining delay for `C` and `G/B` without expanding personal handwriting fixtures, retuning scores, enabling default OCR, or adding symbol-ledger diagnostics cost.

## Capture Setup

- tester: Beni
- device model: iPad Pro 13-inch (M5) simulator artifact visible in Preview
- iPadOS version: iOS 26.5 simulator
- Apple Pencil model: not applicable to this artifact; no physical device was visible to `devicectl`
- app build/commit: `b8add53`
- date/time: 2026-05-26 16:31:35Z to 16:31:58Z
- chart title: `Untitled Chart`
- chart id: `4C07805D-48BC-4447-B003-8445FE7CFAFC`
- Xcode/device console log file: not captured; unified log search did not return `SmartChart chord` timing lines
- metadata source: CoreSimulator app data `Library/Application Support/SmartChart/chord-entry-diagnostics.jsonl`
- exported PDF result: `Library/Caches/SmartChartExports/untitled-chart-concert.pdf`, modified 2026-05-26 16:31:58Z, rendered visually in Preview and via `sips`

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

Simulator/Preview artifact result:

| Case | Expected route | Metadata result | Recognizer cost | Trust/correction | Ink clearing/export | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Clear auto-render if confidence is high enough | `autoRendered`, confidence `3.96`, OCR not requested | `0.53ms` total, `2/4096` sequences | Primary recognizer accepted | Final PDF shows `C`; active chart has exactly one `C` event | This artifact does not explain a perceived multi-second delay because scheduler/proposal/commit console lines were not captured |
| `G/B` | Clear slash-chord auto-render if confidence is high enough | `autoRendered`, confidence `4.98`, OCR not requested | `1.06ms` total, `39/4096` sequences | Primary recognizer accepted | Final PDF shows `G/B`; active chart has exactly one `G/B` event | Recognizer compute is not the blocker for this pass |
| `Db7(b9)` | Confirmation-gated, quick control case | `confirmedSuggestion`, confidence `4.82`, close race gap `0.02`, OCR invalid | `19.28ms` recognizer total plus `45.09ms` OCR, `579/4096` sequences | Confirmation route preserved | Final PDF shows `Db7(b9)`; active chart has exactly one `Db7(b9)` event | A stale superseded diagnostic for `Db7/Gb` exists, but it is not present in the current chart or exported PDF |

## Parsed Timing Table

Paste the parser output here after the pass.

| attempt | best | accepted | confidence | primaryAction | finalAction | trust | agreement | closeRace | gap | delayMs | idleMs | recognitionMs | totalMs | proposalMs | commitMs | ocrCount | ocrMs | reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Not captured | C | C | 3.96 | autoRender | autoRender | primaryRecognizer | ocrNotRequested | false | - | - | - | - | 0.53ms | - | - | 0 | - | Confident read. Placed automatically. |
| Not captured | G/B | G/B | 4.98 | autoRender | autoRender | primaryRecognizer | ocrNotRequested | false | - | - | - | - | 1.06ms | - | - | 0 | - | Confident read. Placed automatically. |
| Not captured | Db7(b9) | Db7(b9) | 4.82 | confirm | confirm | primaryRecognizer | ocrInvalid | true | 0.02 | - | - | - | 19.28ms | - | - | 1 | 45.09ms | Close race. Choose the chord you meant, or type it in. |

The rows above come from committed diagnostics, not from the Sprint 47 console timing parser. They prove recognizer compute and final export state for the simulator/Preview artifact, but they do not yet classify scheduler delay, proposal time, commit time, or render handoff.

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
