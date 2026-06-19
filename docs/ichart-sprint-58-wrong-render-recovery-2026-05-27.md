# iChart Sprint 58: Wrong Render Recovery And Replace UX

Status: complete locally
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Goal

Stop wrong auto-renders from repeating after the user deletes them, without turning correction behavior into global handwriting training.

## Implementation

- Preserved the existing delete-feedback path for ink-origin rendered chords.
- Added a stored `sourceCandidateSignature` to `ChordEvent` so deleted auto-renders can remember the supported top-candidate shape that produced the wrong render.
- Kept old chart snapshots compatible by defaulting missing `sourceCandidateSignature` to an empty signature during decode.
- Extended local rejected-auto-render memory to block by either exact ink digest or the stored candidate signature.
- Passed confirmation candidate signatures through the commit path so deletion feedback can reroute a similar future pass to confirmation instead of repeating the same wrong auto-render.
- Kept the block local and user-specific: it only reroutes to confirmation/direct input; it does not change global recognition scores.

## Verification

- Focused SwiftPM recovery tests passed: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint58-recovery --filter ChordInkUserCorrectionMemoryTests`, `7` tests, `0` failures.
- Focused SwiftPM chart-editing tests passed: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint58-chart --filter ChartEditingTests`, `32` tests, `0` failures.
- XcodeBuildMCP focused iOS simulator test passed: `iChartTests/ChordInkUserCorrectionMemoryTests`, `7` tests, `0` failures.
- `git diff --check` passed.

## Behavior Boundary

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No parser/compendium authority change.
- No export behavior change.
- No accepted-chord ink clearing change.

## Next

Move to Sprint 59: confirmation and direct input polish. The direct-input path is now more important because repeated wrong auto-renders should route there cleanly.
