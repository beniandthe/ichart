# Smart Chart Sprint 60 General Candidate Availability Hardening

Status: complete locally; awaiting GitHub verification after push
Date: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Goal

Improve transferable candidate availability without personal handwriting training, score retuning, OCR expansion, or symbol-ledger diagnostics cost.

## Evidence

The recognizer already scanned all composed candidates for the accepted match, but the candidate-score evidence exposed to trust policy, confirmation, and diagnostics only came from the top raw candidate prefix. When unsupported numeric/noisy candidates occupied that prefix, a valid supported candidate just outside it could be missing from the confirmation suggestions even though it was available in the composed candidate list.

That is a general candidate-availability issue, not a handwriting-specific accuracy issue.

## Implementation

- Preserved the existing top raw candidate-score prefix for diagnostics.
- Added a supported-candidate backfill pass that appends unique compendium/parser-approved candidates from beyond the raw prefix.
- Capped the supported backfill so candidate evidence stays bounded.
- Left candidate confidence values and recognition scoring untouched.

## Verification

- `swift test --scratch-path /tmp/SmartChartSwiftBuild-sprint60-availability --filter ChordInkRecognizerTests`
  - `41` tests executed
  - `1` skipped by the opt-in full fixture archive gate
  - `0` failures
- `git diff --check`

## Behavior Boundary

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No parser/compendium authority change.
- No editor, export, placement, direct-input, correction-memory, or ink-clearing behavior change.

## Follow-Up

Sprint 61 should focus on raster/render handoff polish only if timing or visual evidence shows a real handoff problem. Keep validation proportional.
