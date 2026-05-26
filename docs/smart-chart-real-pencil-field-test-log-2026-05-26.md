# Smart Chart Real Pencil Field Test Log

Status: Sprint 43 field-test evidence captured; follow-up decision pending
Date: 2026-05-26
Protocol: `docs/smart-chart-real-life-testing-readiness-2026-05-25.md`
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Use this file to record the first bounded real Apple Pencil validation pass after Sprint 42.

This is product evidence for the writing-to-render loop:

```text
open -> write -> recognize -> snap -> fix -> export
```

This is not a handwriting training session. Do not add fixtures, tune scores, or expand the corpus from this pass unless the observation proves a transferable product regression.

## Test Setup

- tester: Beni
- device model: real iPad used; exact model not yet recorded. Exported PDF artifact inspected locally was found in the configured iOS simulator Preview/export containers.
- iPadOS version: not yet recorded from tester; exported PDF metadata reports iOS Version 26.5 (Build 23F77)
- Apple Pencil model: real Apple Pencil used; exact model not yet recorded
- app build/commit: `56ef6ae Set up real Pencil field test`
- date/time: user-reported pass complete on 2026-05-25; exported PDF metadata timestamp `2026-05-26T03:01:32Z` (`2026-05-25 20:01:32 PDT`)
- chart title: `Untitled Chart`
- notes on input environment: user confirmed the writing pass was completed on a real iPad with Apple Pencil. Local metadata confirms the inspected Preview PDF artifact came from simulator/Preview export storage, so it proves generated PDF shape and metadata rather than physical iPad file provenance.

## Preflight

- [x] App opens to Projects/Library.
- [x] Clean chart is created or opened.
- [x] Chord-writing mode is reachable.
- [ ] Apple Pencil writes native ink without obvious lag before recognition starts. Partial pass: tester reported native writing feel with small stroke-break issues.
- [ ] Export/share path is reachable on tested iPad. Tester reported export/share was not available on iPad and only available from MacBook/local Preview flow.

## Bounded Test Cases

| Case | Expected route | Actual route | Pencil feel | Correction friction | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Auto-render or clear correction path | Auto-rendered correctly, but slowly | Native feel with small stroke breaks | No correction needed | Visible in local Preview PDF M1 | Visual export proof shows label and beat subtitle legibly rendered |
| `G/B` | Auto-render slash chord | Auto-rendered correctly, but slowly | Native feel with small stroke breaks | No correction needed | Visible in local Preview PDF M2 | Slash chord label rendered without clipping |
| `Db7(b9)` | Confirmation, not blind auto-render | Recognition had issues, mostly around the altered extension note | Native feel with small stroke breaks | Altered extension correction/trust friction observed | Visible in local Preview PDF M3 after successful output | Altered chord label rendered without clipping once exported |

## Product Observations

### Writing Feel

- latency: writing itself felt native, but recognition/auto-render was slow for `C` and `G/B`.
- stroke fragmentation: small stroke-break issues observed.
- pressure/visual feel: native Apple Pencil feel was acceptable overall.
- accidental mode/tool friction: not reported.

### Recognition Trust

- auto-render felt correct when: `C` and `G/B` both auto-rendered correctly.
- confirmation felt necessary when: `Db7(b9)` remained the ambiguous altered-chord case; friction centered on the altered extension note.
- surprising result: auto-render speed was slower than desired; altered extension recognition was weaker than the simple/slash-chord cases.

### Correction Flow

- suggestion clarity: `Db7(b9)` needs follow-up; altered extension handling did not feel trustworthy enough yet.
- manual edit friction: not fully recorded.
- recovery from wrong/unsupported chord: not fully recorded.

### Ink Lifecycle

- chord ink cleared after accepted render: pass. Tester confirmed all chord ink cleared.
- unexpected ink left behind: not visible in exported PDF; live canvas state not yet recorded
- unexpected ink cleared too early: not reported.

### Export

- PDF readability: pass. Rendered PNG proof is legible at `792x612`; white page background is stable.
- chord placement: pass. `C`, `G/B`, and `Db7(b9)` appear in M1, M2, and M3 respectively with no visible clipping; M4 remains empty.
- title/header/layout: pass. Header shows `Untitled Chart`, `C major`, `Concert`, `4/4`, `4 measures`, and `Page 1`.
- share/export friction: fail on real iPad. Tester reported export/share was not available on iPad and only available from MacBook/local Preview flow.
- export fidelity: fail for product expectations. The generated PDF uses old singular/card-like measure blocks rather than the full actual chart/page surface.

## Evidence

Attach or reference only product-useful evidence:

- screenshots:
- screen recording:
- exported PDF:
  - Preview/export cache path: `/Users/benirossman/Library/Developer/CoreSimulator/Devices/42254D11-2E65-4586-AEBE-C6317AF2DD10/data/Containers/Data/Application/40BBB488-7B7B-430E-864C-1FF6A81B0005/Library/Caches/SmartChartExports/untitled-chart-concert.pdf`
  - Preview documents path: `/Users/benirossman/Library/Developer/CoreSimulator/Devices/42254D11-2E65-4586-AEBE-C6317AF2DD10/data/Containers/Data/Application/16C71DA8-5ED6-467B-944B-BD84EE5B0698/Documents/untitled-chart-concert.pdf`
  - size: `23824` bytes
  - SHA-256: `0e73bc58afdffcdf82393a300a61b60274effe235b3f98d80aa160199e8e80aa`
  - PDF metadata: creator `Smart Chart`, title `Untitled Chart`, producer `iOS Version 26.5 (Build 23F77) Quartz PDFContext`, creation/modification timestamp `2026-05-26T03:01:32Z`
- rendered QA image: `/tmp/SmartChartRealPencilFieldTest/untitled-chart-concert.png`
- visual QA notes: first page renders as a clean landscape chart with four visible measures; `C`, `G/B`, and `Db7(b9)` are legible and not clipped.
- metadata confirmation:
  - inspected artifact provenance: CoreSimulator path for booted `iPad Pro 13-inch (M5)` simulator `42254D11-2E65-4586-AEBE-C6317AF2DD10`
  - physical iPad/Pencil provenance: confirmed by tester notes, not by the local PDF file path
  - current export renderer implementation: `PDFChartExporter` renders fixed 792x612 pages with card-style measure blocks; it does not yet share the full on-screen chart/page geometry
- console/log notes:

Do not save repeated personal handwriting samples unless a specific transferable regression needs a fixture later.

## Decision

Choose the next sprint from the observed product friction:

- [ ] Pencil/input feel sprint
- [ ] recognition trust routing sprint
- [ ] correction UX sprint
- [ ] renderer/export sprint
- [ ] beta/readiness polish sprint
- [ ] no code change; repeat field test with another writer/device

Decision notes:

The field test confirms the recovered writing-to-render loop works in principle on real iPad/Pencil: native writing feel is mostly intact, `C` and `G/B` can auto-render, and accepted chord ink clears. The pass also exposes real product blockers: small stroke breaks, slow auto-render, `Db7(b9)` altered-extension recognition friction, unavailable iPad export/share, and PDF export fidelity that still looks like old measure cards instead of the actual chart page. These findings should route the next sprint toward export availability/fidelity first, with recognition latency and altered-extension trust as the next bounded follow-up. Do not respond by adding more personal handwriting fixtures.
