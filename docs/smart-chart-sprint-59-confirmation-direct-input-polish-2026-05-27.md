# Smart Chart Sprint 59 Confirmation Direct Input Polish

Status: complete locally; awaiting GitHub verification after push
Date: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Goal

Make the chord confirmation and direct-input sheet feel like a compact product loop instead of a debug fallback, especially when Sprint 58 reroutes a previously deleted wrong auto-render into confirmation.

## Implementation

- Kept the sheet centered on the current measure, the intended chord choice, top supported suggestions, manual entry, and rewrite controls.
- Changed the candidate area to a compact top-three grid with calmer labels.
- Added a clear manual-entry caption and focused the field when direct entry is required or no confident suggestions exist.
- Replaced deleted-render reroute copy with normal correction language.
- Clarified action labels with `Accept Chord` and `Rewrite Ink`.

## Verification

- `xcodegen generate`
- XcodeBuildMCP focused iOS simulator test: `SmartChartTests/ChordInkUserCorrectionMemoryTests` passed with `7` tests and `0` failures.
- `git diff --check`

## Behavior Boundary

- No recognition score retuning.
- No personal handwriting fixture expansion.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No parser, compendium, export, placement, ink-clearing, or chart persistence behavior change.
- Existing correction-memory behavior remains intact.

## Follow-Up

Sprint 60 should move to general candidate availability hardening: inspect transferable missing-candidate gaps before touching scoring, OCR, or personal handwriting evidence.
