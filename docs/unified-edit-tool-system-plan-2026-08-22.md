# Unified Edit Tool System Plan

Date: 2026-08-22
Branch: `codex/unified-edit-tool-plan`
Planning base: `48ff04e` (`Document chord lane fallback checkpoint`)
Chord-lane fallback checkpoint: `697c2a5` (`Establish chord lane draft render baseline`)

This began as a handoff plan for replacing the current overloaded `Select` behavior with a safer, clearer unified `Edit` tool. The implementation checkpoint below records the first completed pass and the proof gathered so far.

## Implementation Checkpoint

Date: 2026-08-22

Current implemented checkpoint before this doc update: `235511c` (`Extract rendered edit hit overlay`) on `codex/unified-edit-tool-slice-10`.

Implemented slice commits:

- `0f7629e` - Plan unified edit tool system
- `be1f804` - Rename Select tool to Edit
- `a562256` - Add rendered edit type vocabulary
- `1a086de` - Add rendered edit target providers
- `03fd8a6` - Route rendered edit taps through router
- `e63bc43` - Route rendered edit drag starts through router
- `dbd4c2e` - Add selected rendered edit action tray
- `b3cb403` - Add selected measure editing in Edit
- `9d24ac4` - Route structural marks into Edit
- `3de9167` - Rename rendered edit interaction internals
- `235511c` - Extract rendered edit hit overlay

Implemented behavior:

- User-facing `Select` is now `Edit`.
- Rendered edit identity, action, priority, mutation-risk, selection, router, and provider types exist.
- Edit taps route through the rendered edit router for chords, committed chord barlines, cue text, roadmap point markers, measures, header, repeat spans, ending spans, and time signatures.
- Edit drag starts route through the rendered edit router for supported movable/resizable objects.
- A selected-object action tray exposes explicit object actions instead of mutating from body taps.
- Measures can be selected in Edit and show selected-only resize handles.
- Repeat spans, ending spans, and time signatures open the existing scoped editors without direct destructive gestures.
- Generic rendered edit overlay/policy names no longer use chord-only names where they now cover multiple rendered object families.

Verification captured:

- Slice 8: `/tmp/iChart-unified-edit-slice8.xcresult` - 168 passed, 0 failed.
- Slice 9: `/tmp/iChart-unified-edit-slice9-20260821-a.xcresult` - 128 passed, 0 failed.
- Slice 10: `/tmp/iChart-unified-edit-slice10-20260821-a.xcresult` - 128 passed, 0 failed.
- Focused editor/chord-lane matrix: `/tmp/iChart-unified-edit-focused-20260821-a.xcresult` - 466 passed, 0 failed.
- `git diff --check` passed for the cleanup slices.
- `xcodegen generate` completed during slice 10.

Still deferred:

- Physical iPad acceptance is still required before calling interaction quality complete.
- Key-change rendered selection is intentionally deferred because the current layout surface does not expose a safe source measure identity for every rendered key marker.
- A command-executor consolidation remains future work. Current mutations still call the existing object-specific chart editing paths.
- Renaming `EditorCanvasMode.browse` to `.edit` remains intentionally deferred because the churn is broad and not needed for the first stable Edit tool pass.

Scope guard:

- This implementation did not change chord recognition accuracy, OCR, chord recognition scoring, trust arbitration, or handwriting fixture behavior.

## Product Goal

Make editing rendered chart objects feel like one coherent tool:

- Tap `Edit`.
- Tap any rendered object on the page.
- The selected object exposes the correct controls for that object.
- Move, resize, delete, or open the object-specific editor from one place.
- A plain tap selects. A destructive change requires an explicit selected object plus an explicit destructive control.

The key product decision is that `Edit` should be one unified object editor, not a separate always-visible lane for every editable object. The UI should feel like a one-stop shop, while the implementation remains object-specific and guarded.

## Non-Goals

- Do not change chord recognition accuracy.
- Do not add OCR or revive OCR types, tests, scripts, or diagnostics.
- Do not alter chord-lane draft preview grouping, recognition scoring, trust arbitration, or fixture behavior.
- Do not weaken the chord-lane fallback baseline from commit `697c2a5`.
- Do not convert draft chord ink into a general edit object. Draft ink and draft barlines remain owned by the Chord tool until explicit `Render Chords`.
- Do not make a large interaction rewrite in one pass.

If a needed change touches chord recognizer internals, stop and move that work to the separate recognition-accuracy branch.

## Current Repo Fit

The existing code is close enough to support this, but the boundaries are blurry.

### Existing Strengths

- `EditorCanvasMode.browse` is already the current `Select` tool state. It can edit rendered chords and cue text, select headers, select measures, and route roadmap marker selection.
- `EditorCanvasMode` already has capability flags for object editing, measure selection, cue text editing, header selection, and ink modes.
- `LeadSheetInteractionModeStatePolicy` already centralizes which recognizers and overlays are active per mode.
- `LeadSheetChordEditOverlayGeometry` already contains reusable geometry and safety ideas:
  - select-first policy for chords
  - selected-only controls
  - delete control priority
  - tight overlay frames
  - cue text controls
  - roadmap marker controls
- `LeadSheetCanvasInteractionTargeting` already has low-level movement targeting for chords, cue text, and committed chord barlines.
- `ChartEditing.swift` already owns model mutations for measures, chord events, committed chord barlines, cue text, roadmap markers, time signatures, key changes, and rhythm maps.
- Focused tests already exist around interaction state, chord edit geometry, committed barline delete safeguards, chord movement, cue text movement, and simple-row affordances.

### Existing Weak Spots

- The user-facing label is `Select`, but behavior is already a partial editor.
- Internally, `.browse` means both passive browsing and edit selection.
- `LeadSheetCanvasHostView` is doing too much object routing directly:
  - chord object taps
  - committed barline taps
  - cue text taps
  - roadmap marker taps
  - measure taps
  - header taps
  - move and resize gestures
- Names such as `chordEditTapRecognizer`, `chordMovePanRecognizer`, `chordEditHitOverlayView`, and `clearsChordInteractionState` are now generic rendered-object behavior with chord-specific names.
- Selection state is split:
  - `selectedMeasureID`
  - `selectedCueTextID`
  - `selectedRoadmapMarkerID`
  - local `selectedChordID`
  - local `selectedDraftBarlineID`
  - local `selectedCommittedBarlineMeasureID`
  - `selectedNoteSelection`
- A selected rendered chord currently moves the app into `chordEntry`, and selected cue text moves into `textEdit`. This makes the toolbar state understandable locally, but it reinforces the feeling that editing objects lives in several different places.
- Measures, repeats, endings, time signatures, key changes, rendered chords, and cue text all mutate the same chart model, but their safeguards are not enforced by one shared edit command layer.

## Recommended Direction

Rename the user-facing tool from `Select` to `Edit`, then build a generic rendered-object edit router behind the current behavior.

The router should not replace every object editor immediately. It should first normalize identity, hit priority, selection, and mutation safety. Once those are stable, each object family can migrate into the unified route one at a time.

## Core Architecture

### 1. Rendered Object Identity

Introduce a single object identity enum for selected rendered page objects.

Proposed type:

```swift
enum RenderedEditObjectID: Hashable {
    case measure(UUID)
    case chord(UUID)
    case committedChordBarline(afterMeasureID: UUID)
    case cueText(UUID)
    case roadmapMarker(UUID)
    case repeatSpan(UUID)
    case endingSpan(UUID)
    case timeSignatureChange(afterMeasureID: UUID)
    case keyChange(measureID: UUID)
    case header
}
```

Initial implementation can support only the already-editable objects:

- `.measure`
- `.chord`
- `.committedChordBarline`
- `.cueText`
- `.roadmapMarker`
- `.header`

Repeat spans, ending spans, time signatures, and key changes can start as select/open-sheet objects later.

### 2. Edit Actions

Introduce a common action vocabulary.

Proposed type:

```swift
enum RenderedEditAction: Hashable {
    case select
    case move
    case resizeLeading
    case resizeTrailing
    case resizeLeft
    case resizeRight
    case grow
    case shrink
    case editText
    case correctChord
    case delete
    case openInspector
}
```

The action vocabulary should be generic. Each provider decides which actions are valid for its object type.

### 3. Hit Targets

Introduce one generic hit target returned by object-specific providers.

Proposed type:

```swift
struct RenderedEditHitTarget: Hashable {
    var objectID: RenderedEditObjectID
    var action: RenderedEditAction
    var priority: RenderedEditHitPriority
    var frame: CGRect
    var requiresSelection: Bool
    var mutationRisk: RenderedEditMutationRisk
}
```

Priority order should be deterministic:

1. Selected-object destructive controls.
2. Selected-object resize handles.
3. Selected-object edit/correct controls.
4. Selected-object move body.
5. Object body select.
6. Measure select.
7. Page/header fallback.

This is the core failsafe against tap confusion.

### 4. Object Providers

Move object-specific hit geometry behind small providers:

- `ChordRenderedEditProvider`
- `CommittedChordBarlineRenderedEditProvider`
- `CueTextRenderedEditProvider`
- `RoadmapMarkerRenderedEditProvider`
- `MeasureRenderedEditProvider`
- `HeaderRenderedEditProvider`

Later providers:

- `RepeatSpanRenderedEditProvider`
- `EndingSpanRenderedEditProvider`
- `TimeSignatureRenderedEditProvider`
- `KeyChangeRenderedEditProvider`

The first migration should be an adapter over the existing geometry, not a rewrite. Existing geometry types can remain until the router has parity tests.

### 5. Selection State

Introduce a single rendered edit selection state.

Proposed type:

```swift
struct RenderedEditSelectionState: Equatable {
    var selectedObjectID: RenderedEditObjectID?
}
```

During migration, this can coexist with the current state. The bridge layer maps:

- `.measure(id)` <-> `selectedMeasureID`
- `.cueText(id)` <-> `selectedCueTextID`
- `.roadmapMarker(id)` <-> `selectedRoadmapMarkerID`
- `.chord(id)` <-> local `selectedChordID`
- `.committedChordBarline(afterMeasureID)` <-> local `selectedCommittedBarlineMeasureID`

Long-term, `LeadSheetCanvasHostView` should read one selected rendered object and derive local drawing state from it.

### 6. Command Executor

All mutations should run through a small command executor before calling `ChartEditing.swift`.

Proposed type:

```swift
enum RenderedEditCommand {
    case delete(RenderedEditObjectID)
    case move(RenderedEditObjectID, target: RenderedEditMoveTarget)
    case resize(RenderedEditObjectID, target: RenderedEditResizeTarget)
    case openEditor(RenderedEditObjectID)
}
```

Rules:

- The executor validates the selected object still exists.
- The executor validates the action is allowed for that object.
- The executor calls the existing model mutation API.
- The executor updates selection after mutation.
- The executor records a local breadcrumb for structural mutations.

## Gesture Contract

The user-facing edit grammar should be strict:

- One tap selects one rendered object.
- First tap on an unselected object never deletes, resizes, or structurally changes the chart.
- Delete requires the object to be selected and the tap to land on a visible delete control.
- Moving starts only from a selected movable object or from an explicitly allowed move body.
- Resizing starts only from visible handles.
- Committed barline body taps select only. They never delete.
- Measures can be selected in Edit, but deleting a measure remains a toolbar/action-tray command, not a canvas body tap.
- Repeat spans, ending spans, time signatures, and key changes should open their editor/inspector first. Direct destructive gestures come later, only after tests prove safety.
- Pencil movement should keep scrolling behavior predictable. If Pencil starts on a move target, object movement wins. If it starts on ordinary page space, page scroll should remain available where the current scroll policy allows it.

## Object-by-Object Plan

### Rendered Chords

Current state:

- Existing chord overlay supports select, review/correction, delete, move, leading resize, and trailing resize.
- Existing tests cover select-first behavior and move/resize targeting.

Plan:

1. Keep existing chord behavior as the first provider.
2. Wrap `LeadSheetChordEditOverlayGeometry` in `ChordRenderedEditProvider`.
3. Map actions:
   - chord body tap -> `.select` if unselected
   - selected chord body or double tap -> `.correctChord`
   - selected delete control -> `.delete`
   - selected body drag -> `.move`
   - selected handles -> `.resizeLeading` / `.resizeTrailing`
4. Preserve frozen-layout movement and one mutation on gesture end.

Failsafes:

- Do not permit unselected chord move start.
- Do not delete from chord body.
- Do not change recognition code.

### Committed Chord Barlines

Current state:

- Existing geometry returns `.select` on line tap and `.delete` only from the selected delete control.
- Model deletion merges adjacent simple-chord measures and repositions chord fractions.

Plan:

1. Treat committed barlines as rendered edit objects.
2. Select the barline on line tap.
3. Show a small selected-only delete control.
4. Delete only through command executor after `chart.canDeleteCommittedSimpleChordBarline(after:)` passes.
5. Consider a confirmation or undo checkpoint for barline deletion because it can merge measures and move chords.

Failsafes:

- Never delete from a plain barline tap.
- Never delete a barline across a key change or meter change.
- Breadcrumb every committed barline delete attempt and result.

### Cue Text

Current state:

- Existing cue text geometry supports select, edit, grow, shrink, delete, and move.
- Existing SwiftUI toolbar actions also edit, resize, and delete selected cue text.

Plan:

1. Wrap `LeadSheetCueTextEditOverlayGeometry` in `CueTextRenderedEditProvider`.
2. Select text with body tap.
3. Show selected-only controls:
   - edit
   - grow
   - shrink
   - delete
4. Keep the text entry sheet as the editor.
5. Preserve beat-snapped cue text move targeting.

Failsafes:

- Unselected text controls should not activate.
- Delete requires selected delete control or selected action tray button.
- After delete, selection returns to the anchor measure or clears if the anchor is gone.

### Roadmap Point Markers

Current state:

- Existing geometry supports select, selected-only delete, and horizontal move.
- Toolbar actions can resize/delete selected roadmap markers.

Plan:

1. Wrap `LeadSheetRoadmapMarkerEditOverlayGeometry` in `RoadmapMarkerRenderedEditProvider`.
2. Select marker on tap.
3. Show selected-only controls for delete, grow, and shrink.
4. Horizontal drag moves only within the marker movement frame.

Failsafes:

- No body tap deletion.
- Drag clamps to movement frame.
- Span roadmap objects remain out of direct drag until separately designed.

### Measures

Current state:

- Measures are selected in browse, measure edit, repeat edit, and time edit modes.
- Measure resizing is currently tied to `measureEdit`.
- Measure deletion and range deletion already exist as toolbar commands.

Plan:

1. Add measure selection to Edit as a rendered object selection.
2. Do not immediately expose measure resize handles in Edit until the generic router is stable.
3. Once stable, expose selected measure resize handles through `MeasureRenderedEditProvider`.
4. Keep measure add/delete/range/new-row actions in the Measures tool or a selected-measure action tray.

Failsafes:

- A measure body tap selects only.
- Measure delete must remain an explicit toolbar or action-tray command.
- Range delete remains a two-step explicit flow.
- New row/join remains explicit.

### Header

Current state:

- Browse mode can tap the handwritten header area and request header authoring.

Plan:

1. Treat the header as a select/open-editor target.
2. Header tap in Edit opens the existing header authoring flow.
3. Do not expose delete/move/resize for header in the first pass.

Failsafes:

- Header taps should not steal measure/object taps below the header.
- Header authoring remains controlled by existing header input mode.

### Repeats And Endings

Current state:

- Repeat and ending creation/deletion is measure-selection driven in the Repeats tool.
- Span editing is not yet a generic rendered-object gesture system.

Plan:

1. Keep Repeats as the authoring tool.
2. In Edit, rendered repeat/ending markings can become selectable later.
3. First action should open a context tray or route to the Repeats tool with the correct measure/span selected.
4. Direct span resizing should wait until a span identity and boundary-handle model exists.

Failsafes:

- No direct repeat or ending deletion from first tap.
- No drag-to-resize span until start/end boundary semantics are explicit and tested.

### Time Signatures And Key Changes

Current state:

- Time and key changes are measure-scoped and can restructure chart layout/transposition.

Plan:

1. Keep Time as the authoring tool.
2. In Edit, rendered time/key labels can later become select/open-editor targets.
3. Do not expose direct delete or drag gestures in the first generic edit migration.

Failsafes:

- Time/key changes must use existing scoped application flows.
- Key changes can transpose chord events, so every key-change action needs explicit user intent.

### Free-Write And Raw Ink

Current state:

- Free-write/page ink is persisted separately from rendered objects.

Plan:

1. Leave raw free-write ink outside the unified rendered edit system for now.
2. If freehand symbols become movable objects later, define a separate `freehandObject` identity and convert them intentionally.

Failsafes:

- Edit mode should not accidentally erase, move, or normalize raw page ink.

## Step-by-Step Implementation Slices

### Slice 0: Planning Checkpoint

Status: this document.

Deliverables:

- Branch `codex/unified-edit-tool-plan`.
- This handoff plan under `docs/`.
- No app behavior change.

Gates:

- `git diff --check`
- Commit the doc as the planning checkpoint.

### Slice 1: Honest UI Rename

Goal: Make the current user-facing tool label match its current behavior.

Changes:

- Change toolbar title from `Select` to `Edit`.
- Change `EditorCanvasMode.browse.activeToolTitle` from `Select` to `Edit`.
- Rename helper methods only where low risk:
  - `activateSelectTool` can remain in first pass if renaming touches too much.
  - If renamed, use `activateEditTool` with a compatibility wrapper.
- Update guided tour copy only where it directly says the tool name.
- Update tests that assert `Select` text.

Do not:

- Change gestures.
- Change selection behavior.
- Add controls.
- Move object routing.

Gates:

- `git diff --check`
- `xcodegen generate`
- Focused tests:
  - `LeadSheetInteractionModeStatePolicyTests`
  - `ProjectConfigurationTests`
- Simulator smoke screenshot of toolbar.
- Physical iPad tap sanity check.

### Slice 2: Generic Edit Types Behind Current Behavior

Goal: Add the shared vocabulary without changing the app behavior.

Changes:

- Add `RenderedEditObjectID`.
- Add `RenderedEditAction`.
- Add `RenderedEditHitTarget`.
- Add `RenderedEditSelectionState`.
- Add `RenderedEditMutationRisk`.
- Add unit tests for identity equality, priority ordering, and select-first resolution.

Do not:

- Replace existing geometry.
- Remove existing selection state.
- Change `LeadSheetCanvasHostView` routing.

Gates:

- New unit tests for pure types.
- Existing focused tests unchanged.

### Slice 3: Provider Adapter Layer

Goal: Wrap existing object geometry in generic providers.

Changes:

- Add provider protocol:

```swift
protocol RenderedEditHitTargetProvider {
    func hitTargets(in context: RenderedEditContext) -> [RenderedEditHitTarget]
}
```

- Add adapter providers for:
  - chords
  - committed chord barlines
  - cue text
  - roadmap point markers
  - measures as select-only
  - header as open-editor only
- Build `RenderedEditRouter` that combines providers and resolves top priority.

Do not:

- Use the router in production gestures yet.

Gates:

- Parity tests comparing provider output to existing geometry output.
- Tests for object overlap priority:
  - selected delete control beats body select
  - selected resize handle beats move
  - committed barline line tap selects
  - measure body loses to chord/cue/roadmap object hit

### Slice 4: Route Taps Through The Router

Goal: Let one router handle rendered-object taps while preserving behavior.

Changes:

- Replace the object-specific ordering in `handleChordEditTap` with router resolution.
- Keep existing handler functions as command endpoints.
- Bridge router selection into current selection variables.
- Preserve current behavior that selected chord opens chord tooling only if product still wants that during migration. If possible, keep user in `Edit` after selecting rendered chords.

Do not:

- Change move/resize gestures yet.
- Change measure tool behavior.

Gates:

- Tests for tap resolution.
- Existing geometry tests.
- Manual simulator check:
  - tap rendered chord
  - tap chord delete control
  - tap committed barline body
  - tap committed barline delete control
  - tap cue text
  - tap roadmap marker
- Physical iPad check for accidental deletion prevention.

### Slice 5: Route Move And Resize Gestures Through The Router

Goal: Replace chord-specific pan naming and gesture gating with generic object move/resize routing.

Changes:

- Add `RenderedEditDragState`.
- Rename internal gesture/policy names where safe:
  - `chordMovePanRecognizer` -> `objectMovePanRecognizer`
  - `chordEditHitOverlayView` -> `renderedEditHitOverlayView`
  - `clearsChordInteractionState` -> `clearsRenderedObjectInteractionState`
- Preserve old names temporarily if the rename creates too much churn.
- Route chord move, chord resize, cue text move, and roadmap move through common drag start resolution.
- Keep each object family committing through its existing mutation API.

Do not:

- Add repeat span or time/key drag.

Gates:

- Existing movement tests:
  - chord frozen layout target
  - chord off-center grab target
  - full-width open chord lane target
  - cue text snapped move target
  - roadmap clamp/normalize
- Add tests that Pencil move starts only on actual move targets.
- Physical iPad drag check for chord, cue text, roadmap, committed barline non-drag.

### Slice 6: Selected Object Action Tray

Goal: Make Edit feel like a one-stop shop without showing every object control at once.

Changes:

- Add a compact Edit active tool/action tray when `canvasMode == .browse` or future `.edit`.
- Tray content is driven by selected object type:
  - chord: Correct, Delete, maybe Width controls
  - committed barline: Delete
  - cue text: Edit, Smaller, Larger, Delete
  - roadmap marker: Smaller, Larger, Delete
  - measure: Measures actions shortcut, but no one-tap delete
  - header: Edit Header
- Keep visible on-canvas controls for precise spatial edits.

Do not:

- Put every object on the canvas in edit boxes at once.
- Add instructional text in-app.

Gates:

- Visual inspection on iPad:
  - no overlapping toolbar/tray content
  - no giant text in compact tray
  - selected state is clear but quiet

### Slice 7: Measure Editing In Edit

Goal: Bring selected-measure resizing and common measure actions into Edit carefully.

Changes:

- Use `MeasureRenderedEditProvider` for selected measure resize handles.
- Keep add/delete/new-row/join in Measures tool or selected-measure action tray.
- If Delete appears in Edit tray, require selected measure and explicit Delete button, never a canvas tap.

Gates:

- Tests for selected-only measure resize handles.
- Tests for simple row group affordance still matching row geometry.
- Manual iPad measure resize and page scroll check.

### Slice 8: Structural Object Selection

Goal: Let Edit select structural rendered objects without direct destructive gestures.

Changes:

- Add select/open-editor support for:
  - repeat spans
  - endings
  - time signatures
  - key changes
- Route selected structural objects to existing authoring flows.

Do not:

- Directly drag/resize/delete spans until span boundary handles have a separate plan.
- Directly delete key/time changes from canvas body taps.

Gates:

- Tests for first tap select-only.
- Tests that object priority does not steal chord/cue/measure hits.

### Slice 9: Cleanup And Renames

Goal: Remove confusing duplicate names after parity is proven.

Changes:

- Rename `.browse` to `.edit` only if the churn is contained and tests can prove parity.
- Remove compatibility wrappers.
- Move generic router/provider files out of chord-specific filenames.
- Split `LeadSheetCanvasHostView` where practical:
  - rendering
  - gesture routing
  - command execution
  - ink sessions

Gates:

- Full focused editor test suite.
- Device acceptance pass.
- No unrelated recognition churn.

## Failure Modes And Protocols

### Accidental Structural Mutation

Risk:

- A tap on a barline, measure, repeat, or time/key marker changes the chart structure.

Protocol:

- First tap selects only.
- Delete/mutate requires explicit selected control or action tray.
- Structural actions validate `mutationRisk == .structural`.
- Breadcrumb every structural mutation attempt and result.

### Selection Desynchronization

Risk:

- `selectedMeasureID`, `selectedChordID`, `selectedCueTextID`, and `selectedRoadmapMarkerID` disagree.

Protocol:

- Introduce `RenderedEditSelectionState`.
- During migration, bridge outward to old fields from the single selected object.
- Add tests that selecting one object clears incompatible selected object state.

### Gesture Conflict

Risk:

- Pencil scroll, move, resize, and tap recognizers compete.

Protocol:

- Move starts only from router-approved move targets.
- Resize starts only from router-approved resize targets.
- Parent scroll lock remains only during active object drag.
- Preserve current Pencil policy: Pencil movement must not start object moves from empty page space.

### Object Priority Bugs

Risk:

- A measure or barline target wins when the user meant chord/cue text, or a delete control loses to body select.

Protocol:

- Centralize priority ordering.
- Test overlapping target cases.
- Providers return candidates; router chooses one.

### Model/Layout Reflow During Drag

Risk:

- Moving an object mutates the chart continuously and causes layout jumps.

Protocol:

- Use frozen source layout at drag start.
- Draw preview during drag.
- Commit one mutation on gesture end.
- Preserve existing chord-move behavior.

### Chord Tool Regression

Risk:

- Edit work destabilizes chord-lane draft ink, preview, render, or barline behavior.

Protocol:

- Do not touch chord recognition.
- Do not route draft chord ink through Edit.
- Keep Chord tool draft barlines separate from committed barlines.
- Run chord-lane focused tests after every slice that touches `LeadSheetCanvasHostView`.
- If behavior regresses, branch back from fallback commit `697c2a5`.

### Test Mirage

Risk:

- A zero-exit build is mistaken for proof of real editor safety.

Protocol:

- Require nonzero test counts from Xcode result output.
- Separate unit tests, simulator proof, and physical-iPad acceptance.
- Do not call device interaction complete from simulator only.

## Required Test Matrix

Run the smallest sufficient gate after each slice, then broaden when router/host code changes.

Baseline commands:

```bash
git diff --check
xcodegen generate
```

Focused tests to keep green:

- `ProjectConfigurationTests`
- `LeadSheetInteractionModeStatePolicyTests`
- `LeadSheetChordEditOverlayGeometryTests`
- `ChordInkDraftPreviewTests`
- `ChartEditingTests`
- `LeadSheetPageLayoutTests`

Specific cases to preserve or add:

- Browse/Edit mode enables rendered object overlay without enabling ink canvas.
- Chord Entry mode keeps draft ink and rendered object editing simultaneously.
- Unselected chord tap selects before action.
- Unselected chord cannot start move.
- Chord move uses frozen source layout.
- Chord resize requires selected resize handle.
- Committed chord barline line tap selects only.
- Committed chord barline delete requires selected delete control.
- Cue text controls activate only when selected.
- Roadmap marker delete activates only when selected.
- Pencil object move starts only on a movable target.
- Measure body tap selects only.
- Measure delete cannot be triggered by canvas body tap.
- Header tap opens header authoring only in the header region.
- Draft chord ink and draft barlines remain absent from Edit mode targeting.

Physical iPad acceptance:

- Tap Edit.
- Tap a rendered chord. It selects only.
- Drag selected chord. It moves once on release without layout popping.
- Resize selected chord from each side.
- Delete selected chord via visible delete control.
- Tap committed barline body. It selects only.
- Delete committed barline via visible delete control.
- Tap cue text. It selects, then edit/grow/shrink/delete work.
- Tap roadmap marker. It selects, then move/resize/delete work.
- Tap empty lane/page space. Nothing destructive happens.
- Use Pencil to scroll when not starting on an object move target.
- Enter Chord tool and confirm draft lane behavior is unchanged.

## File Plan

Likely new files:

- `iChart/Features/Editor/Components/RenderedEditObjectID.swift`
- `iChart/Features/Editor/Components/RenderedEditAction.swift`
- `iChart/Features/Editor/Components/RenderedEditRouter.swift`
- `iChart/Features/Editor/Components/RenderedEditProviders.swift`
- `iChart/Features/Editor/Components/RenderedEditSelectionState.swift`
- `iChartTests/Editor/RenderedEditRouterTests.swift`

Likely migration files:

- `iChart/Features/Editor/EditorCanvasMode.swift`
- `iChart/Features/Editor/EditorView.swift`
- `iChart/Features/Editor/Components/LeadSheetCanvasHostView.swift`
- `iChart/Features/Editor/Components/LeadSheetInteractionModeStatePolicy.swift`
- `iChart/Features/Editor/Components/LeadSheetChordEditOverlayGeometry.swift`
- `iChart/Features/Editor/Components/LeadSheetCanvasInteractionTargeting.swift`
- `iChart/Features/Editor/Components/LeadSheetMeasureResizeGeometry.swift`

Likely no-change or call-only files:

- `iChart/Models/ChartEditing.swift`
- `iChart/Models/Chart.swift`
- `iChart/Services/LeadSheetPageLayout.swift`

The model layer should remain the mutation authority. The unified edit system should call existing chart editing APIs rather than duplicate model behavior.

## Performance Notes

- Providers should operate from the current `LeadSheetPageLayout` snapshot.
- Avoid recomputing layout during drag movement.
- Compute hit targets lazily for the tap/pan start location when possible.
- If target arrays are needed for drawing, cache them per layout version and selected object.
- Keep router work O(number of visible rendered objects), not O(all historical chart data).
- Do not call recognition code from the Edit router.

## Future Depth Ideas

These are worthwhile only after the basic router is stable:

- Selected-object action tray with object-specific controls.
- Lightweight undo checkpoints for structural object edits.
- Optional edit inspector for selected measure/chord/text/roadmap objects.
- Long-press context menu for touch users, while Pencil tap remains select-only.
- Multi-select for future batch movement/deletion, gated behind a separate plan.
- Visual hover/near-hit affordance for Apple Pencil hover, if target iPad hardware supports it.
- Accessibility labels and VoiceOver actions per rendered object.

## Handoff Rules

For the implementation branch:

1. Start from this planning branch or the current chord-lane fallback line.
2. Keep the chord-lane fallback commit `697c2a5` sacred until a newer checkpoint is intentionally created.
3. Implement one slice at a time.
4. Do not mix router work with chord-recognition accuracy work.
5. Do not reintroduce OCR.
6. After any `LeadSheetCanvasHostView` or gesture policy change, run focused tests and do physical iPad acceptance before declaring success.
7. If a plain tap can delete, merge, resize, transpose, or otherwise structurally mutate the chart, stop and fix the gesture contract before continuing.

## Recommended First Implementation PR

The first real implementation PR should be intentionally small:

- Rename user-facing `Select` to `Edit`.
- Keep `.browse` internally.
- Keep all gestures and object routing unchanged.
- Update tests and guided-tour text only as needed.
- Verify toolbar behavior on simulator and physical iPad.

That creates the product-language foundation without destabilizing the working chord-lane system.
