# iChart Sprint 64 New Chart Layout Style Chooser

Status: complete implementation slice
Date: 2026-05-27
Source of truth: `docs/ichart-sprint-source-of-truth.md`

## Purpose

Sprint 64 implements the first thin chart-layout slice from Sprint 63: `New Chart` asks which layout style the user wants before opening the editor.

This sprint should make layout choice durable without starting a renderer rewrite. `ChartLayoutStyle` is the chart-level product contract; recognition, editor mode, and the legacy `ChartType` are not layout authority.

## Step-By-Step Plan

1. Model the layout style.
   - Add `ChartLayoutStyle` with `Simple Chord Sheet`, `Rhythm Section Sheet`, and `Lead Sheet`.
   - Persist it on `Chart`.
   - Decode older saved charts as `Lead Sheet`.

2. Route New Chart through the layout picker.
   - Tapping `New Chart` opens a three-choice picker.
   - Selecting a layout creates the draft chart and opens the editor.
   - Existing chart-opening behavior remains unchanged.

3. Apply safe setup defaults only.
   - `Simple Chord Sheet`: compact defaults for dense chord roadmaps.
   - `Rhythm Section Sheet`: wider/gig-style defaults for rhythm and cue space.
   - `Lead Sheet`: current balanced lead-sheet defaults.

4. Surface the selected layout style.
   - Show the layout in library summaries.
   - Show the layout in the setup sheet.
   - Keep changing layout after creation out of scope until conversion rules exist.

5. Verify proportionally.
   - Focused model/store tests for persistence, defaults, and legacy decoding.
   - SwiftPM full suite as a broad non-UI sanity check.
   - iOS simulator app build because the picker/setup surfaces are SwiftUI app-target code.

## Current Local Implementation State

- `ChartLayoutStyle` defines the three layout styles with display copy, icons, and safe defaults.
- `Chart.layoutStyle` persists the selected style and defaults missing legacy data to `Lead Sheet`.
- `Chart.draft`, `Chart.blank`, and `ChartLibraryStore.createBlankChart` accept the selected layout style.
- `LibraryView` presents a layout picker before creating a new chart.
- Library rows and the setup sheet show the selected layout style.
- Renderer branching remains deferred.

## Checkpoint Status

1. Model the layout style: implemented and covered by focused tests.
2. Route New Chart through the layout picker: implemented.
3. Apply safe setup defaults only: implemented through existing style/engraving presets.
4. Surface the selected layout style: implemented in library rows and the setup sheet.
5. Verify proportionally: automated checks, simulator build, and quick simulator/manual picker-flow check passed.

## Guardrails

- No personal handwriting fixture expansion.
- No recognition score retuning.
- No parser or compendium authority change.
- No default OCR expansion.
- No symbol-ledger diagnostics cost.
- No full notation, melody entry, playback, or broad renderer rewrite.
- No layout-specific renderer path until layout contracts are explicit.

## Acceptance Criteria

- `New Chart` presents `Simple Chord Sheet`, `Rhythm Section Sheet`, and `Lead Sheet`.
- A new draft chart can be created from each style.
- The selected style persists on the chart.
- Older saved charts decode with `Lead Sheet`.
- Existing editor/export rendering continues to use the current lead-sheet renderer path.
- The sprint source-of-truth records verification before closeout.

## Verification Log

- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutstyle --filter 'ChartEditingTests|ChartLibraryStoreTests'` passed with `43` selected tests, `0` failures.
- `swift test --scratch-path /tmp/iChartSwiftBuild-layoutstyle` passed with `334` tests, `36` skipped, `0` failures.
- `xcodegen generate` completed for simulator verification; the generated ignored project was removed afterward to keep repo debris clean.
- XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO` passed for the `iChart` scheme on the configured iPad simulator.
- XcodeBuildMCP `build_run_sim CODE_SIGNING_ALLOWED=NO` passed and launched the app. Simulator UI hierarchy confirmed `New Chart` opened a picker with `Simple Chord Sheet`, `Rhythm Section Sheet`, and `Lead Sheet`; selecting `Rhythm Section Sheet` showed that layout in setup, and `Create Blank Page` opened the editor.
- `git diff --check` passed.
- `git clean -ndX` showed no ignored/generated debris after removing the generated project; `git clean -nd` reports only this intentional untracked Sprint 64 doc.

## Next Step

Sprint 65 should define layout-profile contracts for toolbar emphasis, measure defaults, notation-lane intent, and future renderer routing. Keep renderer behavior on the current lead-sheet path until those contracts are explicit and verified.
