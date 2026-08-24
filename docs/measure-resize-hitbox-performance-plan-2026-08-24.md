# Measure Resize, Hit Boxes, And Edit Performance Plan

Created: 2026-08-24
Branch: `codex/measure-resize-hitbox-performance`
Base: clean `codex/ink-performance-snappy` at `3918f24`

## Scope

This branch is for rendered edit interaction architecture only:

- measure resize smoothness
- chord versus measure hit-target arbitration
- resize preview clarity
- local drag performance around rendered edit objects
- guide overlays that explain alignment and affected row geometry

This branch must not change:

- chord recognition accuracy
- OCR
- chord ink candidate scoring
- chord parsing rules
- persistence semantics for free-write or chord-lane ink unless a resize/edit interaction directly exposes a bug

## Problem Statement

The current resize path feels inconsistent because the live drag preview and the committed layout do not share one authority.

Observed behavior:

- Dragging one measure can visibly compress other measures more than expected.
- The preview can imply a local single-measure resize while commit triggers row-level reflow.
- Chord hit boxes can steal taps that visually read as measure-body taps.
- Resize and object gestures compete in the same rendered page area.

Current code facts:

- `LeadSheetMeasureResizePreviewPolicy.previewFrame` previews only the selected frame.
- `handleMeasureResizePan(.ended)` commits one `manualLayoutWidth` and then lets the layout engine reflow the row.
- Simple Chord Sheet layout treats `manualLayoutWidth` as a weight and can redistribute row overflow across several measures.
- Rendered chord selection uses an expanded body hit frame, while measure selection has lower priority.

## Architecture Contract

Resize must behave as a transaction:

1. Resolve the hit target once at gesture start.
2. Freeze the affected row snapshot.
3. During drag, update only lightweight transient preview frames and guides.
4. Do not mutate the chart during drag.
5. On release, commit the explicit model widths predicted by the preview.
6. Run the real layout engine once after commit.

The user-facing rule:

- A resize drag should not surprise the user on release.
- If another measure will be affected, the blue guide preview must show that before release.
- A plain body tap must select; only selected handles resize.

## Initial Resize Behavior

The first implementation keeps the behavior conservative:

- Resizing a selected measure affects only the selected measure and the nearest same-row neighbor on the dragged edge.
- If the dragged edge is at the row boundary, the selected measure resizes against available row/filler space.
- The preview clamps at readable minimum widths before commit.
- The guide overlay shows:
  - the frozen row bounds
  - current measure boundaries for affected measures
  - the active dragged edge
  - subtle affected-measure fills

This is intentionally not a rigid permanent grid. It is a transaction preview and alignment helper. The chart model still stores measure layout intent and the page layout engine still owns final rendering.

## Hit Target Contract

- Selected resize handles beat move/body targets.
- Selected chord move can keep a forgiving movement halo.
- Unselected chord selection should not claim empty-looking space around the chord.
- Measure body selection should win in measure body space that is outside visible chord/edit controls.
- No body tap may structurally mutate the chart.

## Performance Contract

During active resize drag:

- No chart model writes.
- No persistence writes.
- No full-page layout recompute.
- No hit-target regeneration after gesture start.
- Drawing should be limited to the existing canvas invalidation plus transient row preview data.

On release:

- Commit model widths once.
- Recompute layout once through the existing chart update path.

## Implementation Slices

### Slice 1: Transaction Snapshot

- Add a measure resize transaction snapshot type.
- Capture same-row measure frames, selected edge, selected measure id, and layout style at drag start.
- Produce preview frames and commit widths from translation.
- Unit-test right-edge and left-edge neighbor balancing.

### Slice 2: Live Preview And Guides

- Store the transaction preview in the active drag state.
- Draw guide lines and affected measure fills from the frozen preview.
- Keep `.changed` local to the active drag state and `setNeedsDisplay`.

### Slice 3: Commit Predicted Widths

- Commit all widths returned by the transaction, not only the selected measure.
- Do this once on `.ended`.
- Test that the committed Simple Chord Sheet row approximates the preview widths.

### Slice 4: Hit-Target Arbitration

- Split chord body hit areas into unselected selection frame and selected movement frame.
- Keep selected chord movement forgiving.
- Ensure measure body taps outside visible chord frames select the measure.
- Ensure resize handles keep top priority.

### Slice 5: Physical iPad Gate

Manual validation on connected iPad:

- resize middle measure right and left
- resize row-end measure
- tap measure body near chords
- drag selected chord body
- confirm resize feels continuous and release does not jump

## Stop Conditions

Stop and reassess if:

- preview and commit cannot be made to match without changing the broader layout engine
- resizing requires global row repacking beyond the selected row
- chord hit-box changes make selected chord movement hard
- any change pulls in chord recognition or OCR

## Implementation Status

Implemented in this branch:

- Frozen same-row resize transaction snapshots.
- Lightweight resize preview frames and guide overlays.
- Commit-on-release width application for affected measures only.
- Chord selection hit box split:
  - unselected chords use the visible edit frame for tap selection
  - selected chords keep the larger forgiving move frame for drag
- Explicit `Even Row` measure action for Simple Chord Sheet rows:
  - equalizes the currently selected visible row on demand
  - compensates for the rendered terminal staff barline so the final visible measure does not appear wider than the others
  - leaves resize drags direct instead of adding hidden snap behavior
- Resize guide feedback:
  - draws faint vertical guide lines at the selected row's even division points
  - turns the active resize edge green when it is within tolerance of an even division point
  - previews all visible row measures as equal when the dragged edge reaches its green even-division point
  - commits terminal-aware row equalization on release from the green state, using the same width policy as `Even Row`
- Chord move positioning feedback:
  - keeps existing arbitrary `manualLaneFraction` precision available for stored chord events
  - draws a transient chord-position field during rendered chord move drags
  - shows beat-position guide lines inside the target measure
  - turns the active target guide green when the dragged chord is within snap tolerance
  - commits the snapped beat-anchor fraction only for the live edit drag path when the chart is supplied
- Focused tests for right-edge resize, left-edge resize, minimum neighbor clamp, and chord-versus-measure hit arbitration.

Validation on 2026-08-24:

- `git diff --check`: passed.
- Focused simulator tests on `iPad Pro 13-inch (M5)` simulator:
  - `LeadSheetInteractionModeStatePolicyTests`
  - `RenderedEditTargetProvidersTests`
  - xcresult: `/tmp/ichart-measure-resize-hitbox-20260824-2.xcresult`
  - result: 146 passed, 0 failed.
- Project configuration tests:
  - xcresult: `/tmp/ichart-measure-resize-project-config-20260824-1.xcresult`
  - result: 29 passed, 0 failed.
- Unsigned iphoneos build:
  - command used `CODE_SIGNING_ALLOWED=NO`
  - derived data: `/tmp/ichart-device-build-measure-resize-hitbox-nosign-20260824-1`
  - result: build succeeded.

Physical iPad gate:

- Device detected: `Ben’s iPad` / `376D59F8-92F2-5260-B10E-BA0BEAF941AB`.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-measure-resize-hitbox-20260824-signed-1`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - provisioning profile: `iOS Team Provisioning Profile: com.ichart.app`
- Signature verified with `codesign -dv --verbose=4`:
  - bundle id: `com.ichart.app`
  - architecture: `arm64`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `7b7ee8ee9423e3667add5d9c6fa1f13ce774ca4e`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.

Additional validation after artifact-aware chord position guides and trailing-only chord resize:

- Behavior change:
  - chord move guide anchors now use an artifact-aware guide field that starts after left-side artifacts instead of tight against the measure's raw left barline.
  - the guide field reserves clearance for leading barlines, leading repeat markers, and inline meter-change frames before computing quarter-position guide anchors.
  - snapped guide positions are converted back into the measure's raw committed fraction, so the visual snap point and the saved chord position stay aligned on release.
  - chord leading resize is deprecated in the edit UI and hit-target providers; chord width edits now use trailing resize only, so resizing no longer changes the chord's placement anchor.
- `git diff --check`: passed.
- Focused simulator tests:
  - xcresult: `/tmp/ichart-chord-artifact-guides-focused-20260824-4.xcresult`
  - result confirmed by `xcresulttool`: 8 passed, 0 failed.
- Broader simulator groups:
  - xcresult: `/tmp/ichart-chord-artifact-guides-groups-20260824-1.xcresult`
  - suites selected:
    - `LeadSheetInteractionModeStatePolicyTests`
    - `RenderedEditTargetProvidersTests`
    - `LeadSheetChordEditOverlayGeometryTests`
    - `LeadSheetPageLayoutTests`
  - result confirmed by `xcresulttool`: 283 passed, 0 failed.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-chord-artifact-guides-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `09aeb87f1fd8eae7ac7045c2ed7caf044bba437c`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.
- Known warnings were unchanged from earlier local gates:
  - `LibraryView.swift` deprecated `onChange(of:perform:)`
  - `IChartTelemetry.swift` `UIDevice.current` main actor warnings
  - AppIntents metadata warnings for missing shortcuts/framework metadata

Additional validation after chord guide clearance calibration:

- Behavior change:
  - reduced the default leading guide clearance from `22pt` to `12pt`.
  - reduced artifact clearance from `10pt` to `6pt`.
  - artifact-aware guide behavior remains intact for leading repeat markers and inline meter-change frames.
  - chord leading resize remains deprecated.
- `git diff --check`: passed.
- Focused simulator tests:
  - xcresult: `/tmp/ichart-chord-guide-clearance-focused-20260824-1.xcresult`
  - result confirmed by `xcresulttool`: 13 passed, 0 failed.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-chord-guide-clearance-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `a755c45231712052eb4ba00aee49f4464fa83c48`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.

Additional validation after green-guide whole-row equalization:

- Cause confirmed:
  - the previous green guide only checked the dragged boundary against an even division point
  - the resize transaction still committed only the selected measure and nearest neighbor
  - that made it possible to align one boundary while another measure, usually the terminal measure, remained visually uneven
- Fix:
  - normal resize drags remain selected-measure-plus-neighbor transactions
  - green even-division alignment now switches the preview to whole-row equal visible frames
  - release from the green state commits all row measure widths through `LeadSheetSimpleChordRowEqualizationPolicy`, including terminal-barline compensation
- `git diff --check`: passed.
- Focused simulator tests:
  - first attempted bundle: `/tmp/ichart-measure-resize-green-row-equalize-focused-20260824-1.xcresult`
  - result: build failed due to a local helper-name shadowing error in the new transaction code
  - corrected bundle: `/tmp/ichart-measure-resize-green-row-equalize-focused-20260824-2.xcresult`
  - result: 6 passed, 0 failed.
- Broader simulator groups:
  - xcresult: `/tmp/ichart-measure-resize-green-row-equalize-groups-20260824-1.xcresult`
  - result: 258 passed, 0 failed.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-measure-resize-green-row-equalize-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `7df10260eb70e38f001430fe46238a0c3f1f929e`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.

Additional validation after chord move position guides:

- `git diff --check`: passed.
- Focused simulator tests:
  - xcresult: `/tmp/ichart-chord-position-guides-focused-20260824-1.xcresult`
  - tests selected: 9 chord move target, snap, and preview tests
  - result confirmed by `xcresulttool`: 9 passed, 0 failed.
- Broader simulator groups:
  - xcresult: `/tmp/ichart-chord-position-guides-groups-20260824-1.xcresult`
  - suites selected:
    - `LeadSheetInteractionModeStatePolicyTests`
    - `RenderedEditTargetProvidersTests`
    - `LeadSheetPageLayoutTests`
  - result confirmed by `xcresulttool`: 261 passed, 0 failed.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-chord-position-guides-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `610c379c0ac1049cf92ab7245b749c8cad384cd9`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.
- Known warnings were unchanged from earlier local gates:
  - `IChartTelemetry.swift` `UIDevice.current` main actor warnings
  - AppIntents metadata warnings for missing shortcuts/framework metadata

Additional validation after `Even Row` visible-row equalization:

- `git diff --check`: passed.
- Focused simulator tests:
  - xcresult: `/tmp/ichart-measure-resize-even-row-focused-20260824-1.xcresult`
  - result: 147 passed, 0 failed.
  - covered `LeadSheetInteractionModeStatePolicyTests`, `RenderedEditTargetProvidersTests`, and `LeadSheetPageLayoutTests/testSimpleChordSheetEqualRowManualWidthMakesShortRowVisuallyEven`.
- Full page-layout simulator tests:
  - xcresult: `/tmp/ichart-measure-resize-page-layout-20260824-1.xcresult`
  - result: 110 passed, 0 failed.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-measure-resize-even-row-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `5db28a5863e163040dc703057a8e06209d5037e6`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Initial launch was blocked while the iPad was locked.
- After the iPad became available, launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.

Additional validation after even-division guide feedback:

- `git diff --check`: passed.
- Focused simulator tests:
  - xcresult: `/tmp/ichart-measure-resize-guide-feedback-focused-20260824-1.xcresult`
  - result: 5 passed, 0 failed.
  - covered the resize transaction guide-highlight path, right-edge resize, left-edge resize, minimum neighbor clamp, and Simple Chord Sheet equal-row layout.
- Broader simulator groups:
  - xcresult: `/tmp/ichart-measure-resize-guide-feedback-groups-20260824-1.xcresult`
  - result: 257 passed, 0 failed.
  - covered `LeadSheetInteractionModeStatePolicyTests`, `RenderedEditTargetProvidersTests`, and `LeadSheetPageLayoutTests`.
- Signed Debug device build succeeded:
  - derived data: `/tmp/ichart-device-build-measure-resize-guide-feedback-20260824-signed-1`
  - bundle id: `com.ichart.app`
  - build: `1.1.7` / `49`
  - signing identity: `Apple Development: Benjamin Rossman (8BHT3N56XX)`
  - TeamIdentifier: `N6G8X4K46U`
  - CDHash: `2884be026faa31f5cda0755d96d3b37997e4de4d`
- Installed on Ben's iPad with `xcrun devicectl device install app`.
- Launched on Ben's iPad with `xcrun devicectl device process launch --terminate-existing com.ichart.app`.
