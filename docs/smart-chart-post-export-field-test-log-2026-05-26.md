# Smart Chart Post-Export Field Test Log

Status: Sprint 45 field-test evidence captured; Sprint 46 recognition latency/trust route selected
Date: 2026-05-26
Protocol: `docs/smart-chart-real-life-testing-readiness-2026-05-25.md`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Test build: `2501fdf Close sprint 44 export page rendering`; source-of-truth setup commit `d8e2a74 Set up sprint 45 post-export validation`

## Purpose

Use this file to record the first real iPad/Pencil pass after Sprint 44 replaced the old card-block PDF export with the shared lead-sheet page renderer and temporarily made PDF export reachable before StoreKit.

This pass validates product behavior:

```text
open -> write -> recognize -> snap -> fix -> export
```

This is not a handwriting training pass. Do not add fixtures, tune scores, or expand the corpus from this pass unless the observation proves a transferable regression that should generalize beyond one writer.

## What Changed Since Sprint 43

- `PDFChartExporter` now renders through `LeadSheetPageLayoutEngine` and `LeadSheetNotationRenderer`.
- Export should produce a portrait full lead-sheet page with header, systems, staff lines, chords, rhythmic notation, saved page ink, saved chord ink, and saved rhythmic-notation ink when present.
- Basic/local builds can reach PDF export; export/share is not a Pro-only feature.
- Sprint 44 GitHub Actions passed on `2501fdf`.

## Test Setup

- tester: Beni
- device model: real iPad used; exact model not yet recorded
- iPadOS version: not yet recorded
- Apple Pencil model: real Apple Pencil used; exact model not yet recorded
- app build/commit: `2501fdf Close sprint 44 export page rendering`
- date/time: user-reported pass complete on 2026-05-26
- chart title: not yet recorded; exported PDF visible in Preview
- notes on input environment: user confirmed the pass ran on iPad with Apple Pencil, the chart exported as PDF to Preview, and ink metadata was present. The on-screen state was described as duplicated; treat that as a visual observation needing screenshot/repro if it persists, not as the primary Sprint 45 blocker.

## Preflight

- [x] App opens to Projects/Library.
- [x] Clean chart is created or opened.
- [x] Chord-writing mode is reachable.
- [x] Apple Pencil writes native ink before recognition starts.
- [x] Export/share path is reachable on the tested iPad without simulator-only Pro Preview.

## Bounded Test Cases

| Case | Expected route | Actual route | Pencil feel | Correction friction | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Auto-render or clear correction path | Auto-rendered correctly, but still slow | No stroke breaks reported | No correction needed | Exported to Preview PDF | Took a couple seconds after ink |
| `G/B` | Auto-render slash chord | Auto-rendered correctly, but still slow | No stroke breaks reported | No correction needed | Exported to Preview PDF | Took a couple seconds after ink |
| `Db7(b9)` | Confirmation, not blind auto-render | Needed confirmation and then was good | No stroke breaks reported | Confirmation was acceptable | Exported to Preview PDF | Behaved as the expected ambiguous altered-chord route |

## Export Validation

- [x] Preview/share sheet opens from the iPad.
- [x] Exported PDF is the full lead-sheet page layout, not rounded card-style measure blocks.
- [x] Header/title/key/meter are readable.
- [x] `C`, `G/B`, and `Db7(b9)` are readable where committed.
- [x] The PDF has a stable white page background.
- [x] Exported file can be opened outside the app.

Evidence:

- screenshots:
- screen recording:
- exported PDF path or share destination: exported as PDF to Preview from iPad
- exported PDF size:
- SHA-256:
- rendered QA image:
- console/log notes: user reported ink metadata was present. Do not convert this metadata into fixtures or training data unless a later sprint identifies a transferable regression.

## Product Observations

### Writing Feel

- latency: writing itself was acceptable, but `C` and `G/B` still took a couple seconds after ink before auto-render.
- stroke fragmentation: no stroke breaks reported in this pass.
- pressure/visual feel: acceptable enough to complete the pass.
- accidental mode/tool friction: not reported.

### Recognition Trust

- `C` route: correct auto-render, slow by a couple seconds.
- `G/B` route: correct auto-render, slow by a couple seconds.
- `Db7(b9)` route: needed confirmation and then was good.
- surprising result: export is now clean enough that recognition latency is the lead blocker.

### Correction Flow

- suggestion clarity: `Db7(b9)` confirmation route was acceptable.
- manual edit friction: not reported as a blocker.
- recovery from wrong/unsupported chord: not reported.

### Ink Lifecycle

- chord ink cleared after accepted render: pass.
- unexpected ink left behind: not reported.
- unexpected ink cleared too early: not reported.

### Export

- share/export reachability: pass; export worked as expected and opened in Preview.
- PDF readability: pass.
- chord placement: pass for the tested committed chords.
- full-page fidelity: pass; no old card-block export issue reported.
- remaining export friction: none reported.

## Decision Routing

Choose the next sprint from the observed blocker:

- [ ] export/share fix sprint - choose this if export is still unavailable, broken, or not the full chart page.
- [x] recognition latency/trust sprint - choose this if export is clean and slow auto-render or `Db7(b9)` trust is the main remaining issue.
- [ ] Pencil/input feel sprint - choose this if stroke breaks or raw ink fragmentation reproduce before recognition is involved.
- [ ] correction UX sprint - choose this if `Db7(b9)` reaches confirmation but manual correction is too slow or unclear.
- [ ] beta/readiness polish sprint - choose this if the loop is clean enough for a broader tester pass.

Decision notes:

Sprint 45 confirms the Sprint 44 export fix on the product loop: export/share worked, the PDF opened in Preview, chord ink cleared after accepted render, `Db7(b9)` correctly stayed confirmation-gated and was acceptable, and stroke breaks did not reproduce. The remaining lead blocker is recognition latency for clear auto-render cases (`C` and `G/B`) taking a couple seconds after ink. Sprint 46 should investigate the live recognition scheduling/latency path with instrumentation and bounded improvements, without expanding personal handwriting fixtures.
