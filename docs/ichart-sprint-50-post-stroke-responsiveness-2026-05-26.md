# iChart Sprint 50 Post-Stroke Responsiveness

Status: complete
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Prior evidence: `docs/ichart-sprint-49-flat-root-candidate-availability-2026-05-26.md`

## Purpose

Sprint 50 makes the writing-to-render loop feel a little quicker after the final ink stroke now that Sprint 49 restored `Db7(b9)` candidate availability.

This is a scheduler polish sprint, not recognition training. Do not add personal handwriting fixtures, retune scores, expand OCR authority, or enable symbol-ledger diagnostics by default.

## Sprint 49 Repeat Pass Evidence

Metadata source inspected locally:

- app data: CoreSimulator app container `Library/Application Support/iChart`
- chart ID: `ED98F246-3A73-493C-BF8A-9106DAE76F04`
- diagnostics: `chord-entry-diagnostics.jsonl`

Observed result:

| Case | Result | Timing classification | Recognition classification |
| --- | --- | --- | --- |
| `C` | Auto-rendered | `575ms` scheduled-to-finished on the final root-continuation pass, `1ms` recognition, `32ms` render handoff | Stable clear root case |
| `G/B` | Auto-rendered | `890ms` scheduled-to-finished, `2ms` recognition, `12ms` render handoff | Stable slash case |
| `Db7(b9)` | Auto-rendered | `908ms` scheduled-to-finished, `19ms` recognition, `10ms` render handoff | Sprint 49 fix worked; root-bearing candidates were available |

Key signal:

- The user reported the pass felt smooth and all three cases auto-rendered correctly.
- The remaining felt delay is mostly intentional scheduler wait after ink settles, not recognizer compute, proposal/commit time, or render handoff.

## What Changed

- Normal chord-ink idle delay moved from `0.85s` to `0.75s`.
- Root-only continuation grace moved from `0.55s` to `0.40s`.
- Extension prefixes still keep the full `1.2s` continuation grace.
- Slash chords and altered chords still do not use continuation grace.

Expected product impact:

- A clear root-only case such as `C` can propose after about `1.15s` of scheduler time instead of about `1.40s`.
- Slash and altered chords can propose after about `0.75s` of idle time instead of about `0.85s`.
- Multi-stroke extension prefixes remain protected from premature render by the full continuation grace.

## Behavior Boundary

- No personal handwriting fixture was imported.
- No recognition score was retuned.
- No OCR authority changed.
- No symbol-ledger diagnostics were enabled.
- No export/share or ink-clearing behavior changed.

## Acceptance Criteria

- Scheduling policy tests prove the new conservative delay budget.
- Writing-to-render readiness tests still pass.
- Full SwiftPM and iOS simulator scheme tests pass before closeout.
- One bounded repeat pass confirms `C` and `G/B` still auto-render correctly, `Db7(b9)` remains trust-correct with supported suggestions when close, and the loop feels at least as smooth as Sprint 49.

## Repeat Pass Result

Metadata source inspected locally:

- app data: CoreSimulator app container `Library/Application Support/iChart`
- chart ID: `3800A7BA-DA57-4596-A4F2-A3336FA5742B`
- diagnostics: `chord-entry-diagnostics.jsonl`

Observed result:

| Case | Result | Timing classification | Recognition classification |
| --- | --- | --- | --- |
| `C` | Auto-rendered | `405ms` scheduled-to-finished on the final root-continuation pass, `0ms` recognition, `7ms` render handoff | Stable clear root case |
| `G/B` | Auto-rendered | `782ms` scheduled-to-finished, `2ms` recognition, `13ms` render handoff | Stable slash case |
| `Db7(b9)` | Confirmed suggestion | `813ms` scheduled-to-finished, `28ms` recognition, `6ms` render handoff | Trust-correct close race with supported suggestions |

Key signal:

- `C` is substantially quicker in persisted timing evidence.
- `G/B` follows the new `0.75s` idle window and stays decisive.
- `Db7(b9)` no longer has the empty-suggestion failure. It confirms because the primary race is tight against `Db7(b5)` and related spellings, which is the intended trust behavior.

Closeout note:

- The user confirmed the pass felt good and everything rendered when it was supposed to. Sprint 50 closes without another code change.
