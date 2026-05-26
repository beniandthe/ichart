# Smart Chart Post-Export Field Test Log

Status: Sprint 45 setup; awaiting bounded real iPad/Pencil repeat
Date: 2026-05-26
Protocol: `docs/smart-chart-real-life-testing-readiness-2026-05-25.md`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`
Test build: `2501fdf Close sprint 44 export page rendering`

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
- Free/local field-test builds can reach PDF export before StoreKit through `AppEntitlements.pdfExportAvailableBeforeStoreKit`.
- Sprint 44 GitHub Actions passed on `2501fdf`.

## Test Setup

- tester:
- device model:
- iPadOS version:
- Apple Pencil model:
- app build/commit: `2501fdf Close sprint 44 export page rendering`
- date/time:
- chart title:
- notes on input environment:

## Preflight

- [ ] App opens to Projects/Library.
- [ ] Clean chart is created or opened.
- [ ] Chord-writing mode is reachable.
- [ ] Apple Pencil writes native ink before recognition starts.
- [ ] Export/share path is reachable on the tested iPad without simulator-only Pro Preview.

## Bounded Test Cases

| Case | Expected route | Actual route | Pencil feel | Correction friction | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Auto-render or clear correction path |  |  |  |  |  |
| `G/B` | Auto-render slash chord |  |  |  |  |  |
| `Db7(b9)` | Confirmation, not blind auto-render |  |  |  |  |  |

## Export Validation

- [ ] Preview/share sheet opens from the iPad.
- [ ] Exported PDF is the full lead-sheet page layout, not rounded card-style measure blocks.
- [ ] Header/title/key/meter are readable.
- [ ] `C`, `G/B`, and `Db7(b9)` are readable where committed.
- [ ] The PDF has a stable white page background.
- [ ] Exported file can be opened outside the app.

Evidence:

- screenshots:
- screen recording:
- exported PDF path or share destination:
- exported PDF size:
- SHA-256:
- rendered QA image:
- console/log notes:

## Product Observations

### Writing Feel

- latency:
- stroke fragmentation:
- pressure/visual feel:
- accidental mode/tool friction:

### Recognition Trust

- `C` route:
- `G/B` route:
- `Db7(b9)` route:
- surprising result:

### Correction Flow

- suggestion clarity:
- manual edit friction:
- recovery from wrong/unsupported chord:

### Ink Lifecycle

- chord ink cleared after accepted render:
- unexpected ink left behind:
- unexpected ink cleared too early:

### Export

- share/export reachability:
- PDF readability:
- chord placement:
- full-page fidelity:
- remaining export friction:

## Decision Routing

Choose the next sprint from the observed blocker:

- [ ] export/share fix sprint - choose this if export is still unavailable, broken, or not the full chart page.
- [ ] recognition latency/trust sprint - choose this if export is clean and slow auto-render or `Db7(b9)` trust is the main remaining issue.
- [ ] Pencil/input feel sprint - choose this if stroke breaks or raw ink fragmentation reproduce before recognition is involved.
- [ ] correction UX sprint - choose this if `Db7(b9)` reaches confirmation but manual correction is too slow or unclear.
- [ ] beta/readiness polish sprint - choose this if the loop is clean enough for a broader tester pass.

Decision notes:

Do not save repeated personal handwriting samples unless a specific transferable regression needs a fixture later.
