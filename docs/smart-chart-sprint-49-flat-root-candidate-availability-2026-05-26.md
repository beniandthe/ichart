# Smart Chart Sprint 49 Flat Root Candidate Availability

Status: active implementation
Date: 2026-05-26
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Prior evidence: `docs/smart-chart-sprint-48-persistent-timing-telemetry-2026-05-26.md`

## Purpose

Sprint 49 fixes the remaining `Db7(b9)` product-loop failure from the Sprint 48 bounded pass without expanding personal handwriting fixtures or retuning recognition scores.

The issue is candidate availability, not score ranking: the latest diagnostics showed no suggested chords because the root-bearing prefix never reached composition.

## Sprint 48 Pass Evidence

Metadata source inspected locally:

- app data: CoreSimulator app container `Library/Application Support/SmartChart`
- chart ID: `DA226639-62AA-4DD0-8D9A-E5CEC1777F98`
- diagnostics: `chord-entry-diagnostics.jsonl`

Observed result:

| Case | Result | Timing classification | Recognition classification |
| --- | --- | --- | --- |
| `C` | Auto-rendered | `575ms` scheduled-to-finished, `1ms` recognition, `23ms` render handoff | Stable clear root case |
| `G/B` | Auto-rendered | `892ms` scheduled-to-finished, `1ms` recognition, `9ms` render handoff | Stable slash case |
| `Db7(b9)` | Manual correction, zero suggestions | `955ms` scheduled-to-finished, `62ms` recognition including `50ms` OCR, `17ms` render handoff | Failed before trust ranking because no supported chord candidate was available |

Key diagnostic signal:

- `Db7(b9)` raw candidates were suffix-only strings such as `#7b9`, `#7D9`, `+7b9`, and `67b9`.
- `suggestedCandidateTexts` was empty.
- The replay glyph dump showed the written `D` plus root-flat modifier had fused into one 3-stroke cluster, so the composer never saw a separate root plus flat prefix.

## What Changed

- `StrokeClusterer` now splits a right-side attached flat modifier from a root-construction cluster when the left strokes form a root body/stem and the high right stroke looks like a flat modifier.
- `ChordEntryPassReplayTests` can target a specific saved chart with `SMART_CHART_REPLAY_CHART_ID`, and can optionally print glyph and stroke diagnostics.
- Added a synthetic clusterer unit test for the attached flat-root split.

## Behavior Boundary

- No personal handwriting fixture was imported.
- No recognition score was retuned.
- No OCR authority changed.
- No symbol-ledger diagnostics were enabled.
- No export/share or ink-clearing behavior changed.

## Acceptance Criteria

- The same saved pass replays `Db7(b9)` with root-bearing candidates instead of an empty suggestion list.
- `C` and `G/B` remain stable.
- Existing recognizer and writing-to-render readiness tests pass.
- Full SwiftPM and iOS simulator scheme tests pass before closeout.

## Next Bounded Pass

After checks pass, run one short pass:

- `C`
- `G/B`
- `Db7(b9)`

Expected observation:

- `C` and `G/B` should still feel quick and auto-render.
- `Db7(b9)` should no longer land in an empty-suggestion manual-correction state. It may auto-render if the read is decisive, or ask for confirmation if candidates are close.
