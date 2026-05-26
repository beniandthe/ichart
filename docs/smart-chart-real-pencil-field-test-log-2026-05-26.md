# Smart Chart Real Pencil Field Test Log

Status: Sprint 43 test log template
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

- tester:
- device model:
- iPadOS version:
- Apple Pencil model:
- app build/commit:
- date/time:
- chart title:
- notes on input environment:

## Preflight

- [ ] App opens to Projects/Library.
- [ ] Clean chart is created or opened.
- [ ] Chord-writing mode is reachable.
- [ ] Apple Pencil writes native ink without obvious lag before recognition starts.
- [ ] Export path is reachable.

## Bounded Test Cases

| Case | Expected route | Actual route | Pencil feel | Correction friction | Export result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `C` | Auto-render or clear correction path |  |  |  |  |  |
| `G/B` | Auto-render slash chord |  |  |  |  |  |
| `Db7(b9)` | Confirmation, not blind auto-render |  |  |  |  |  |

## Product Observations

### Writing Feel

- latency:
- stroke fragmentation:
- pressure/visual feel:
- accidental mode/tool friction:

### Recognition Trust

- auto-render felt correct when:
- confirmation felt necessary when:
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

- PDF readability:
- chord placement:
- title/header/layout:
- share/export friction:

## Evidence

Attach or reference only product-useful evidence:

- screenshots:
- screen recording:
- exported PDF:
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
