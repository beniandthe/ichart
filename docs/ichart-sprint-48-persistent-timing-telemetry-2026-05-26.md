# iChart Sprint 48 Persistent Timing Telemetry

Status: active implementation and bounded-pass setup
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Prior evidence: `docs/ichart-sprint-47-timing-capture-log-2026-05-26.md`

## Purpose

Sprint 48 makes chord-entry timing evidence persist into `chord-entry-diagnostics.jsonl` so the next bounded pass does not depend on console capture.

This remains measurement work. Do not expand personal handwriting fixtures, retune recognition scores, broaden OCR, or enable symbol-ledger diagnostics by default.

## What Changed

- `ChordEntryDiagnosticEvent` can now include optional `timingEvidence`.
- Live chord-entry diagnostics can persist:
  - requested scheduler delay
  - idle time before recognition starts
  - recognizer execution time
  - total scheduled-to-recognition-finished time
  - editor proposal decision time
  - structured chart commit mutation time
  - SwiftUI chart-change/render-handoff observation time
- `EditorView` appends a normal diagnostic at commit time, then appends a superseding diagnostic for the same chord event when SwiftUI observes the chart change.
- The audit script prints `timing=[delay=..., idle=..., recognition=..., total=..., proposal=..., commit=..., render=...]`.
- The console parser also understands `iChart chord render: ...` lines when console capture is available.

## Behavior Boundary

- Recognition scores, parser authority, compendium rules, OCR request policy, symbol-ledger policy, fixture corpus, PencilKit capture, export, and chord ink clearing are unchanged.
- The extra diagnostics are debug/simulator evidence only along the existing diagnostic path.
- The append-only diagnostic log may contain a superseded row for a chord event; the audit tooling already resolves latest diagnostics by chord event.

## Bounded Pass Setup

Run one short pass on the current green build after checks pass:

| Case | Expected route | What to observe |
| --- | --- | --- |
| `C` | Auto-render if confidence is high enough | Timing evidence should say whether visible delay is scheduler/idle, proposal/commit, render handoff, or only perceived latency |
| `G/B` | Auto-render slash chord if confidence is high enough | Watch close-race/confidence, but do not retune from one writer |
| `Db7(b9)` | Confirmation-gated control when close race | Confirm route remains trustworthy; OCR should remain ambiguity-only |

After the pass, run:

```bash
python3 scripts/audit_chord_entry_diagnostics.py --app-data "$APP_DATA" --chart-id "$CHART_ID" --details --scores 5
```

Use the printed `timing=[...]` block to route Sprint 49:

- high `delay`/`idle`, low everything else: scheduler/waiting policy
- high `recognition`/`total`: recognizer compute or candidate generation
- high `proposal` or `commit`: editor proposal or structured chart mutation
- high `render`: SwiftUI update/render handoff
- low timing everywhere but poor trust: confidence/ink interpretation or correction UX

## Acceptance Criteria

- Existing focused, full SwiftPM, and iOS simulator scheme tests pass.
- Diagnostics for accepted chord ink include timing evidence on the latest row for each chord event.
- The next bounded pass can classify the remaining perceived delay without importing ink as fixtures.
- `C`, `G/B`, and `Db7(b9)` retain their current trust/export/ink-clearing behavior.

## Guardrails

- No personal fixture expansion.
- No score retuning from one writer's pass.
- No default OCR expansion.
- No symbol-ledger diagnostics cost on the live path.
- No export or StoreKit changes.
