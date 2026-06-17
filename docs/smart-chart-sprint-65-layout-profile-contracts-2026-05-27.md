# Smart Chart Sprint 65 Layout Profile Contracts

Status: complete implementation slice
Date: 2026-05-27
Source of truth: `docs/smart-chart-sprint-source-of-truth.md`

## Purpose

Sprint 65 gives each `ChartLayoutStyle` a model-level profile contract before Smart Chart branches any renderer, export, or editor behavior by layout.

The contract should describe how each layout family wants to behave without making recognition, parser, OCR, symbol-ledger, fixture, or renderer changes.

## Step-By-Step Plan

1. Add a computed `ChartLayoutProfile`.
   - Keep profile data derived from `ChartLayoutStyle`.
   - Do not persist duplicate profile fields on `Chart`.

2. Define the structural contract.
   - Toolbar emphasis: which authoring tools should feel primary.
   - Measure defaults: starting density and preferred measures per system.
   - Notation-lane intent: chord grid, rhythm/hit lane, or staff-led lead-sheet lane.
   - Renderer route: current lead-sheet renderer for all styles until future renderer work is scoped.

3. Keep Sprint 64 behavior stable.
   - `ChartLayoutStyle` remains the durable saved choice.
   - Existing style and engraving defaults should flow through the profile.
   - No layout-specific renderer branch in this sprint.

4. Verify proportionally.
   - Focused model tests for the three profile contracts.
   - Focused SwiftPM suite first; broader SwiftPM run after the model slice compiles.

## Guardrails

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No parser or compendium authority change.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No layout-specific renderer/export branch.
- No full notation, melody entry, playback, or broad editor rewrite.
- No layout-changing UI after chart creation until conversion rules exist.

## Acceptance Criteria

- Each `ChartLayoutStyle` exposes a distinct `ChartLayoutProfile`.
- Profiles define toolbar emphasis, measure defaults, notation-lane intent, and renderer route.
- Existing style/engraving defaults are owned by the profile contract.
- All styles still route to the current lead-sheet renderer.
- Tests document the profile differences.

## Implementation State

- `ChartLayoutProfile` is computed from `ChartLayoutStyle`, not persisted on `Chart`.
- `Simple Chord Sheet` uses chord-roadmap emphasis, compact measure defaults, chord-grid lane intent, and the current lead-sheet renderer route.
- `Rhythm Section Sheet` uses rhythm/hit emphasis, wider rhythm-aware measure defaults, rhythm/hit lane intent, and the current lead-sheet renderer route.
- `Lead Sheet` uses lead-sheet page emphasis, balanced staff/page defaults, lead-sheet staff lane intent, and the current lead-sheet renderer route.
- Existing `defaultStylePreset` and `defaultEngravingPreset` now flow through the profile.

## Verification Log

- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile --filter ChartEditingTests` passed with `35` tests, `0` failures.
- `swift test --scratch-path /tmp/SmartChartSwiftBuild-layoutprofile` passed with `336` tests, `36` skipped, `0` failures.
- `xcodegen generate` completed; XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `SmartChart` scheme on the configured iPad simulator.
- The generated ignored `SmartChart.xcodeproj` was removed after simulator verification.
- `git diff --check` passed.
- `git clean -ndX` showed no ignored/generated debris after removing the generated project.

## Next Step

Sprint 66 should decide whether to apply layout profiles as executable chart-structure defaults for initial measure count, measures per system, spacing mode, and beat-grid defaults while keeping renderer/export behavior on the current lead-sheet path.
