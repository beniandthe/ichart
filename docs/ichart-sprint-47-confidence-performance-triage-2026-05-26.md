# iChart Sprint 47 Confidence And Performance Triage

Status: active planning artifact
Date: 2026-05-26
Source of truth: `docs/ichart-sprint-source-of-truth.md`
Prior evidence: `docs/ichart-sprint-46-latency-repeat-log-2026-05-26.md`

## Purpose

Sprint 47 separates the two remaining real-device hurdles:

- confidence/ink accuracy: `C` and `G/B` can still fall into low-confidence handling on real Pencil input
- conflict/performance/render time: the user-visible delay may include candidate conflict handling, trust routing, proposal UI, commit, ink clearing, or render handoff

This sprint is measurement-first. Do not retune scores, expand personal fixtures, or add a training loop from one writer's pass.

## Product Evidence

The Sprint 46 repeat pass found:

- `C` and `G/B` were low confidence and still took time.
- `Db7(b9)` was extremely quick.
- PDF export completed without issues.

This means the scheduler-only fix is not the whole answer. The next bottleneck is confidence/trust routing or render handoff, not export/share and not the altered-chord confirmation path.

## Working Hypotheses

1. `C` and `G/B` are slow because low confidence causes extra confirmation/trust routing or delayed proposal behavior.
2. The recognizer may be fast, but the UI may spend visible time in proposal, commit, ink clearing, or re-render.
3. Candidate conflict may be making common clear cases feel slower than a more complex altered chord when the altered chord's route is decisive.
4. Any fix must be writer-agnostic and should help general chord-shape interpretation, not memorize this tester's ink.

## First Tasks

- Inspect the live timing/logger path for low-confidence decisions and confirm which fields already capture delay, recognition time, OCR time, best candidate, confidence, and decision route.
- Add or tighten a bounded timing/debug surface only if existing logs cannot separate recognition compute from trust routing and render handoff.
- Audit the `C` and `G/B` path through `ChordInkRecognitionPolicy`, `ChordRecognitionTrustArbiter`, proposal routing, `Chart.commitRecognizedChordInk`, chord ink clearing, and page re-render.
- Keep `Db7(b9)` as a fast confirmation-gated control case.
- Use repo-local, writer-agnostic fixtures only for regression protection if a general bug is found. Do not import the latest iPad metadata as training data.

## Initial Measurement Surface

Current code already captures:

- scheduler delay and idle time in `ChordInkRecognitionTiming`
- recognizer phase timing: cluster, glyph, contextual glyph, compose, semantic, match, OCR, and total recognizer time
- stroke count, cluster count, raw candidate count, generated sequence count, sequence limit status, OCR candidate count, and best matched chord
- persisted diagnostic details after a committed chord: candidate scores, confidence, reason, close-race state, confidence gap, OCR evidence, trust source, agreement level, primary decision, metrics, and optional symbol-ledger data

Current gaps before Sprint 47 instrumentation:

- the console timing line did not include the final trust action, trust source, agreement level, close-race state, confidence gap, or reason
- the live editor path did not print proposal decision time or commit mutation time
- SwiftUI render completion is still not directly measured; if commit time is low but visual delay remains high, the next target is render/update instrumentation

## Sprint 47 Instrumentation

Sprint 47 added debug-only measurement labels without changing runtime recognition behavior:

- `iChart chord timing` now includes confidence, primary action, final action, trust source, agreement level, close-race marker, confidence gap, and final reason.
- `iChart chord proposal` records editor proposal decision time after a recognition payload reaches `EditorView`.
- `iChart chord commit` records structured chart commit mutation time after a chord candidate is accepted or auto-rendered.

Expected use on the next real-device pass:

- If recognition time and proposal/commit time are low but the UI still feels slow, inspect render/update handoff next.
- If final action is `confirm` with low confidence for `C` or `G/B`, investigate confidence/ink interpretation before changing debounce.
- If OCR appears for clear `C` or `G/B`, verify it was requested only because the primary decision needed ambiguity evidence.
- If `Db7(b9)` stays quick, keep it as the confirmation-gated control case.

## Timing Capture Gate

Use `docs/ichart-sprint-47-timing-capture-log-2026-05-26.md` for the next real iPad/Pencil pass.

Copy the Xcode/device console output that includes the three Sprint 47 labels and parse it with:

```bash
python3 scripts/analyze_chord_timing_logs.py path/to/device-console.log
```

The parser groups the timing, proposal, and commit lines into chord attempts and prints the fields needed to route Sprint 48. The pass remains product evidence only; do not import its ink metadata as fixtures or retune recognition from one writer.

## Acceptance Criteria

- Sprint 47 identifies whether the remaining delay is primarily confidence/trust routing, candidate conflict, recognizer compute, UI proposal/commit, ink clearing, or render handoff.
- Any code change is backed by timing evidence and preserves writer-agnostic recognition.
- `Db7(b9)` remains confirmation-gated and quick.
- Export/share remains unchanged and working.
- No personal fixture expansion, score retuning from one pass, default OCR expansion, or symbol-ledger diagnostics cost.

## Non-Goals

- No broad recognition quality retuning.
- No new handwriting corpus or repeated-pass training loop.
- No StoreKit/export sprint unless a fresh export regression appears.
- No attempt to make all low-confidence reads auto-render; correction trust remains more important than guessing fast.
