# iChart Sprint 57: Chord Placement And Edit Loop

Status: complete
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Goal

Make rendered chords easier to inspect and reposition after recognition without changing recognition, scoring, parser authority, export, or chord ink lifecycle behavior.

## Implementation

- Kept the existing model placement and move APIs intact.
- Enlarged the rendered-chord edit controls so delete and move targets are more Pencil/finger-friendly.
- Made the move affordance visually explicit with a simple grip mark instead of an unlabeled dot.
- Highlighted the active chord while it is being moved so the post-render edit loop feels clearer.
- Added focused iOS geometry tests for delete, move, and review hit-target priority.

## Verification

- `xcodegen generate` passed.
- XcodeBuildMCP focused iOS simulator test passed: `iChartTests/LeadSheetChordEditOverlayGeometryTests`, `3` tests, `0` failures.
- Focused SwiftPM placement tests passed: `swift test --scratch-path /tmp/iChartSwiftBuild-sprint57-placement --filter MeasureRhythmMappingTests`, `15` tests, `0` failures.
- `git diff --check` passed.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched `com.ichart.app` on the iPad simulator.

## Behavior Boundary

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No OCR or symbol-ledger behavior change.
- No parser/compendium authority change.
- No export behavior change.
- No accepted-chord ink clearing change.

## Next

Move to Sprint 58: wrong render recovery and replace UX. The goal is to make a wrong auto-render recover without trapping the user in repeated write -> delete -> rewrite cycles.
