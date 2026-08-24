# Ink Canvas Layer And State-Flow Audit

Date: 2026-08-24
Branch context: `codex/ink-performance-snappy`
Status: current architecture map and optimization planning aid

## Purpose

This document records how the current iChart editor canvas is actually layered, how state moves between those layers, and where performance or persistence regressions are most likely to appear.

This is not a chord-recognition accuracy plan. It should not be used to justify recognizer experiments, OCR revival, or broad product behavior changes.

## Current Conclusion

The editor does not have random independent canvas systems. It has several legitimate layers that are coordinated mostly through one large UIKit bridge:

- `iChart/Features/Editor/EditorView.swift`
- `iChart/Features/Editor/EditorCanvasMode.swift`
- `iChart/Features/Editor/Components/LeadSheetCanvasHostView.swift`
- `iChart/Features/Editor/Components/LeadSheetInteractionModeStatePolicy.swift`
- `iChart/Features/Editor/Components/LeadSheetActiveInkScope.swift`

The main risk is concentration. `LeadSheetCanvasHostView.swift` currently owns mode transitions, live PencilKit state, renderer invalidation, gesture recognizers, edit overlays, ink persistence, chord preview scheduling, rhythm advisory scheduling, and chart write-back. That makes the system functional but fragile: a change intended for one workflow can accidentally affect another if it touches shared live-canvas, dirty-state, or scheduling paths.

## Layer Map

### 1. SwiftUI Editor Shell

`EditorView.swift` owns high-level editor state:

- selected tool/mode
- selected measure/chord/cue/roadmap IDs
- active top-bar controls
- `LeadSheetCanvasHostView` construction
- callbacks that mutate the `Chart`

The SwiftUI shell does not directly draw ink. It passes bindings and callbacks into the UIKit canvas host.

### 2. Product Mode

`EditorCanvasMode.swift` defines the broad editor mode:

- `browse`
- `measureEdit`
- `repeatEdit`
- `timeSignatureEdit`
- `rhythmicNotationEdit`
- `headerEntry`
- `chordEntry`
- `noteEdit`
- `freeHand`
- `textEdit`

This layer decides broad product affordances such as whether active tool controls show, whether document actions lock, whether measure selection is allowed, and whether page/header/chord ink editing is active.

Important implication: mode is broad. It does not by itself fully define gesture behavior, persistence behavior, or the active PencilKit frame.

### 3. Interaction Policy

`LeadSheetInteractionModeStatePolicy.swift` maps product mode plus ink tool mode into UIKit behavior:

- selection tap enabled
- ink selection tap enabled
- measure resize pan enabled
- rendered edit tap enabled
- rendered object move pan enabled
- rendered edit overlay hidden/interactive
- page ink canvas interactive/hidden
- active PencilKit tool
- PencilKit drawing policy

This is the correct place for mode-to-control gating. New mode behavior should first ask whether the policy can express it before adding more direct conditionals to the host.

### 4. Active Ink Scope

`LeadSheetActiveInkScope.swift` decides what the live PencilKit canvas is editing:

- page ink
- handwritten header
- chord lane ink
- one rhythmic measure
- temporary note selection

It also computes the active input frame. Chord mode is special because multiple visible chord lanes are represented by one larger backing canvas frame plus local input frames.

Current structural risk: persistence accessors exist both on `LeadSheetActiveInkScope` and `LeadSheetActiveInkScope.Identity`. That duplication is useful for pending-persistence reconciliation, but it creates a maintenance risk because both mappings must stay semantically identical.

### 5. UIKit Canvas Host

`LeadSheetCanvasHostView.swift` is the central coordinator.

It receives SwiftUI state through `updateUIView`, applies pending persisted ink to incoming chart values, updates selected object state, applies mode/tool policy, and routes callbacks back to SwiftUI.

The host owns:

- `pageInkCanvasView`, the live PencilKit surface
- chord preview and confirmation overlays
- rendered edit hit overlay
- parent scroll gesture gate
- chord recognition session and request state
- selection/resize/move/tap gesture recognizers
- active ink dirty-state
- pending ink coalescing and persistence work items
- pending persisted ink map
- last persisted ink snapshot map
- rendered object drag state
- layout invalidation and redraw

This is the primary optimization target. The file is not wrong just because it is large, but the number of responsibilities means future fixes should prefer extracting named coordinators instead of adding more workflow-specific flags here.

### 6. Manual Renderer Layer

The host's `draw(_:)` path renders:

- paper
- header
- saved header ink when header is not actively editing
- chord-writing lanes in chord mode
- systems and measures
- saved page ink when page ink is not actively editing
- chord draft preview
- selected committed chord barline
- measure resize handles and row affordances

Important implication: visible ink can come from either saved model rendering or the live `PKCanvasView`, depending on mode. Bugs where ink appears, disappears, or returns usually involve an incorrect handoff between those two layers.

### 7. Live PencilKit Layer

`pageInkCanvasView` is a `PKCanvasView` configured as the live authoring surface. It is reused for multiple scopes rather than creating separate canvas views per tool.

The current design is efficient in principle, but it requires strict sync rules:

- do not reload model drawing over dirty active ink
- do not normalize live drawing while the user is writing
- do not render saved ink on top of the active live canvas for the same scope
- do not clear dirty state before the model has accepted the latest drawing

### 8. Gesture And Overlay Layer

The host owns gesture recognizers for:

- measure selection
- ink selection
- measure resize
- rendered object movement
- rendered edit tap
- chord correction double-tap
- chord ink confirmation

Rendered object movement and parent scrolling have explicit policy gates. This is good, but the gesture layer still shares host state with ink persistence and layout redraws. Drag/edit performance should be evaluated separately from PencilKit writing performance.

### 9. Ink Scheduling Layer

Drawing changes flow through:

1. `canvasViewDrawingDidChange`
2. `handleActiveCanvasDrawingChange`
3. `scheduleInkSessionWorkAfterDrawingChange`
4. `schedulePersistActiveInk`

The scheduling layer currently routes different authoring roles through one shared set of pending work items:

- chord ink schedules draft preview recognition
- rhythm ink schedules tap-to-render advisory behavior
- passive ink schedules idle persistence
- fallback schedules direct persistence

This debounce structure is useful. The risk is that chord, rhythm, and passive ink workflows share cancellation machinery. Future changes that need independent timing should not overload the same work item without a clear policy.

### 10. Persistence Layer

`persistActiveInkIfNeeded` serializes the current `PKDrawing`, calculates coordinate space, persists through the active scope, records pending persisted ink, updates last persisted snapshots, mutates the local chart, calls `onChartChanged`, emits telemetry, and clears dirty state.

This is a cold-path function that can become hot if called too often. It should happen after idle, on explicit mode/scope transitions, or on explicit render/commit boundaries. It should not become part of the immediate Pencil movement loop.

### 11. Chord Preview Layer

Chord draft preview scheduling and recognition also live in the host.

Important boundary:

- preview may inspect current chord ink
- preview may persist current chord ink so restore/reopen works
- preview must not commit rendered chords or barlines
- preview must not improve or alter recognizer accuracy in this branch

Performance concern: draft preview currently shares persistence and scheduling paths with other ink workflows. Dense chord-lane ink can therefore expose both recognition cost and persistence cost.

## State Flows

### Free-Write Enter

1. SwiftUI sets `EditorCanvasMode.freeHand`.
2. Host `interactionMode.didSet` resolves previous and next active ink scopes.
3. Outgoing scope may persist.
4. `updateInteractionMode` applies gesture and canvas policy.
5. `syncPageInkCanvas` resolves page scope and either preserves dirty active canvas or loads saved page ink into `pageInkCanvasView`.
6. Manual draw stops drawing saved page ink while page ink is active.

Failure class: if sync loads stale model data after the user has erased or written, ink appears to fight back.

### Free-Write Draw

1. PencilKit updates `pageInkCanvasView.drawing`.
2. `canvasViewDrawingDidChange` fires.
3. Host marks passive ink dirty.
4. Scheduling coalesces input changes.
5. Passive ink persists after idle.

Performance class: this path must stay lightweight. Anything that serializes the whole drawing, mutates the live drawing, invalidates the whole layout, or calls chart write-back too often can make writing feel heavy.

### Free-Write Erase

1. Manual erase handler identifies stroke indices to remove.
2. Host assigns a new drawing with those strokes removed.
3. Host records erase telemetry and routes the change through the normal drawing-change path.
4. Passive persistence writes the empty drawing as a real clear/tombstone state.

Current behavior note: erasure is whole-stroke based in this path. That is less precise than PencilKit's native vector eraser behavior, but it avoids the recent persistence bug where erased ink returned after `Done`.

### Free-Write Exit

1. SwiftUI changes mode away from `freeHand`.
2. Host persists outgoing page scope if policy says it should.
3. `updateInteractionMode` hides or disables the live canvas.
4. Manual draw resumes saved page ink rendering.

Failure class: if the outgoing empty drawing is not persisted before the live canvas hides, saved model ink can reappear.

### Chord Mode Enter

1. SwiftUI sets `EditorCanvasMode.chordEntry`.
2. Active scope resolves to `.chords`.
3. Chord lane region is computed from current page layout systems.
4. Live PencilKit canvas frame spans all chord lane input frames.
5. Manual draw renders chord lanes and draft preview.

Failure class: if restored chord ink does not bootstrap draft preview, ink exists but preview/render readiness is missing.

### Chord Mode Draw And Preview

1. PencilKit drawing changes.
2. Host marks chord ink dirty.
3. Empty visible chord ink clears draft preview.
4. Non-empty chord ink schedules draft preview recognition.
5. Draft preview updates without rendering model chords.

Failure class: stale preview entries can appear if preview state is not derived from currently visible strokes, or if hidden/non-visible strokes are not filtered consistently.

### Chord Render

1. User explicitly taps render.
2. Draft chords and draft/user barlines should render together.
3. Rendered chords and barlines become real chart objects.
4. Draft ink clears only after render success.

Boundary: nothing in this flow should change recognizer accuracy. Recognition quality belongs on a separate branch.

### Rendered Edit Movement

1. Edit/browse mode enables rendered edit overlay and move pan according to interaction policy.
2. Tap/pan hit testing identifies editable objects.
3. Drag state should be transient while moving.
4. Chart mutation should happen at commit/release boundaries, not on every drag tick unless explicitly proven cheap.

Performance class: layout rebuilds during drag are likely to feel heavy. Object movement should favor preview state during drag and one chart write-back on completion.

## Current Known Risk Areas

### 1. Host Centralization

`LeadSheetCanvasHostView.swift` is the highest-risk file for performance and state regressions. It coordinates too many systems directly.

Recommended direction: extract behavior-preserving coordinators one at a time. Do not rewrite the whole host.

### 2. Live Canvas Mutation

Any assignment to `pageInkCanvasView.drawing` can cause visible flicker or erase fights if it happens at the wrong time.

Safe cases:

- explicit scope load when not dirty
- explicit clear after confirmed persistence/render behavior
- manual erase when followed by correct dirty/persistence state

Risky cases:

- normalization during active writing
- stale model reload during dirty active writing
- mode transition that hides the live canvas before persistence accepts the current drawing

### 3. Shared Scheduling

One set of pending work items currently supports passive persistence, chord preview, rhythm advisory, and fallback persistence.

This is acceptable while the policies are simple. It becomes risky if future work needs concurrent independent timers.

### 4. Persistence Cost

`PKDrawing.dataRepresentation()` and normalization are whole-drawing operations. They should stay off the immediate stroke path as much as possible.

Persistence should be bounded to:

- idle after writing
- explicit tool exit
- chart close/navigation
- render/commit
- recovery checkpoints that are proven necessary

### 5. Saved Ink Versus Live Ink

The app intentionally draws saved ink when a scope is inactive and uses live PencilKit when that scope is active.

This is a valid design, but it creates a recurring failure class:

- saved ink appears over live ink
- live ink hides before saved model is current
- stale saved model reloads into live canvas
- erase clears live canvas but not saved model

Every ink fix should identify which layer is the source of truth at that moment.

### 6. Scope Mapping Duplication

`LeadSheetActiveInkScope` and `LeadSheetActiveInkScope.Identity` both know how to read and write ink data from `Chart`.

This should eventually be consolidated or covered by focused tests. A mismatch here can create scope-specific persistence bugs that only show in one tool.

### 7. Rendered Object Editing And Ink Share The Host

Rendered chord/barline/cue movement lives beside ink authoring in the same host. This can be fine, but drag operations and ink writing should not share hot-path chart mutation or layout invalidation patterns.

## Recommended Optimization Plan

### Progress Log

2026-08-24:

- Extracted pure ink/session policy and state helpers from `LeadSheetCanvasHostView.swift` into `iChart/Features/Editor/Components/LeadSheetInkCanvasSession.swift`.
- This first slice moved ink responsiveness policy, drawing snapshots, pending persisted ink, persistence dedupe, pipeline metrics, authoring session roles/state, erase targeting policy, sync preservation policy, and live normalization policy behind a named file boundary.
- Extracted the live scoped `PKCanvasView` subclass into `iChart/Features/Editor/Components/LeadSheetScopedInkCanvasView.swift`.
- Extracted ink delayed-work bookkeeping into `iChart/Features/Editor/Components/LeadSheetInkSchedulingCoordinator.swift`.
- Behavior intent: no product behavior change. The host still chooses chord/rhythm/passive work, delays, chart mutation, callbacks, and active canvas sync orchestration; the new scheduler only owns cancel/schedule/clear mechanics for coalesced input and idle persistence/preview work.
- Consolidated active ink scope chart read/write routing so `LeadSheetActiveInkScope` delegates persisted drawing data, coordinate-space lookup, and chart write-back to `LeadSheetActiveInkScope.Identity`.
- Behavior intent: no product behavior change. This removes duplicate switch logic between scope and scope identity so pending-ink replay and live-scope persistence cannot drift independently.
- Extracted persistence-side state into `iChart/Features/Editor/Components/LeadSheetInkPersistenceCoordinator.swift`.
- Behavior intent: no product behavior change. Pending persisted ink replay, last persisted snapshot dedupe, and aggregate ink pipeline metrics now live behind one coordinator; live canvas serialization, chart mutation, and parent callbacks remain in the host.
- Verification: `xcodebuild test -project iChart.xcodeproj -scheme iChart -destination 'platform=iOS Simulator,id=501F3363-5743-448F-A799-47D3D142EB71' -only-testing:iChartTests/LeadSheetInteractionModeStatePolicyTests` passed after each extraction. Final `.xcresult` summary reported `125` passed, `0` failed.

Physical iPad validation checkpoint:

- Device: Ben's iPad, app `com.ichart.app`, iChart `1.1.7` build `49`.
- Scenario: create/write dense Free-Write page ink, erase the ink, tap `Done`, close the app, reopen the app, and reopen the same chart.
- Selected chart: `E7A2C2F3-2A1C-4D5A-BAE9-C5B1A12866A3`.
- Before erase, `pageHandwrittenNotationData` was populated with a large page-ink payload.
- After erase and `Done`, the selected chart had no populated page/header/chord/rhythm handwritten ink fields.
- After app close/reopen and chart reopen, the selected chart object was unchanged from the post-erase state; all handwritten ink fields remained empty.
- Reopen trace showed chart open/render events and did not show ink sync reload or ink persistence activity that would indicate erased ink was restored from stale model state.

What this proves:

- The local Free-Write page-ink erase path now persists through `Done`, app close, app reopen, and chart reopen for the tested chart.
- The specific erased-ink rehydration failure, where stale saved ink fought the live canvas and returned after tool exit/reopen, was not reproduced in this validation pass.

What this does not prove:

- It does not prove chord-lane erase/preview persistence under long preview sessions.
- It does not prove header, rhythm, or chord ink scope switching under rapid tool changes.
- It does not prove cloud sync correctness; cloud push failures were still present in telemetry and remain a separate concern from local persistence.
- It does not prove drag/edit performance is optimized.

Next acceptance checks:

- Repeat write/erase/`Done`/reopen validation for chord-lane ink.
- Repeat scope-switch validation across page, header, chord, and rhythm ink.
- Measure drag/edit transaction counts on iPad and confirm chart mutation happens at release/commit boundaries rather than every drag tick.
- Keep local persistence and remote sync evidence separate in reports.

Second architecture slice:

- Added aggregate editor interaction metrics in `iChart/Features/Editor/Components/LeadSheetEditorPerformanceMetrics.swift`.
- Instrumented layout invalidations, editor chart write-backs, and valid rendered-object/measure drag sessions.
- Routed host `chart = updatedChart` plus `onChartChanged` pairs through one helper so local trace evidence can count editor chart mutations consistently.
- Behavior intent: no product behavior change. This slice is observational and is meant to support the next physical-iPad performance pass by answering whether heavy feel comes from drag ticks, layout invalidation, chart write-back, or ink persistence.
- Added focused tests for drag commit/cancel aggregation and chart write-back/layout counters.

Second physical iPad validation checkpoint:

- Device: Ben's iPad, app `com.ichart.app`, iChart `1.1.7` build `49`.
- Scenario: mixed chord ink, Free-Write ink, deletion, rendered edit movement/resizing, old heavy chart open, old heavy Free-Write erasure, old heavy Free-Write rewrite, app close, app reopen, and chart reopen.
- User-facing result: close/reopen was verified by hand after the mixed sweep; the edited ink state held visually.
- Device trace result: iChart stayed running through the sweep, with no new local iChart diagnostic report observed during the pass.
- Local chart store result: `Chasing After You` retained a large page-ink payload after partial erase/rewrite, which matches the user action rather than indicating erase rehydration. A newer test chart retained its current page-ink payload.
- Ink trace result: `29` `ink.pipeline.aggregate` events, `19` manual erase events, `39` persistence attempts, `0` skipped persistence attempts, and only `1` `sync_loads` event. That single sync load corresponded to loading the existing heavy chart ink into the live canvas; the trace did not show repeated model reloads during dirty write/erase.
- Heavy-ink trace result: the largest observed drawing reached about `448` strokes / `147 KB`; max recorded persist time was about `10.11 ms`.
- Edit trace result: rendered chord movement, chord resize, and measure resize were exercised. Drag activity produced chart write-back/layout clusters around commits and layout events, not an obvious runaway pattern on every drag tick.

What this additionally proves:

- Local Free-Write persistence, erasure, partial erasure of heavy existing ink, rewrite after erasure, and close/reopen restore are holding on the physical iPad for the tested flows.
- The original stale-model rehydration class was not reproduced during either the focused erase/reopen pass or the later mixed heavy-ink pass.
- The editor interaction metrics are useful enough to distinguish drag/edit workload from ink persistence workload.

What this still does not prove:

- It does not prove remote cloud backup/sync correctness. Telemetry still showed repeated `cloud.push_failed` events during the pass, which is separate from local iPad persistence.
- It does not prove cue text movement, roadmap marker movement, or cancelled drag paths; those counters were not exercised in the mixed pass.
- It does not prove recognition accuracy; that remains outside this branch.

Third architecture slice:

- Added `iChart/App/Sync/ChartCloudAutomaticUploadBackoff.swift`.
- Wired `ChartCloudSyncStore` so automatic cloud uploads pause briefly after a failed cloud push instead of trying again after every local ink/edit save.
- Manual `Back Up Now` still bypasses the automatic queue and can be used as an explicit retry.
- Successful cloud pushes and sync cancellation/reset paths clear the automatic-upload backoff.
- Behavior intent: protect local authoring from repeated failing background cloud pushes without changing local persistence, PencilKit behavior, chord recognition, OCR, or cloud merge semantics.
- This does not fix the underlying cloud push failure. It only reduces automatic retry pressure while the cloud path is failing.
- Added focused tests for the automatic-upload backoff policy.

### Phase 1: Instrument The Real Bottlenecks

Add or keep aggregate-only counters for:

- drawing changes per second
- scheduled work count
- persistence attempts, skips, bytes, and duration
- sync model loads
- full canvas draw duration
- layout invalidation count
- chart write-back count
- recognition scheduling count
- drag tick count versus commit count

Acceptance must be physical iPad behavior for ink feel. Simulator is useful for regression tests but is not enough for PencilKit acceptance.

### Phase 2: Lock The Live-Ink Contracts

Add focused tests or policy checks for:

- dirty active ink is not overwritten by model sync
- erased empty drawing persists as an intentional clear
- saved page ink is not drawn while page ink is actively editing
- chord ink preview clears when visible strokes are empty
- leaving an ink mode persists the outgoing scope before hiding the live canvas

### Phase 3: Extract Coordinators

Extract in small behavior-preserving slices:

1. `InkCanvasSessionController`
   - active scope identity
   - dirty state
   - dirty preserve decisions
   - live canvas sync decisions

2. `InkPersistenceCoordinator`
   - drawing serialization
   - normalization
   - dedupe
   - pending persisted ink
   - erase tombstones

3. `InkSchedulingCoordinator`
   - independent debounce channels by authoring role
   - cancellation policy
   - idle persistence scheduling

4. `ChordDraftPreviewCoordinator`
   - draft preview scheduling
   - restored ink preview bootstrap
   - visible-stroke filtering boundary

5. `RenderedEditInteractionController`
   - rendered object hit testing
   - transient drag state
   - release-time chart commit
   - parent scroll lock

Each extraction should keep behavior the same and add tests around the moved policy.

### Phase 4: Optimize Hot Paths

Only after instrumentation identifies the real cost:

- avoid serializing unchanged drawings
- avoid chart write-back when snapshots match
- avoid layout invalidation for visual-only drag ticks
- avoid full redraw for pure overlay movement if possible
- keep normalization at persistence/export boundaries
- keep recognition scheduling separate from passive page ink persistence

## Handoff Rules

Before changing ink, edit, or chord-lane performance behavior:

1. Name the active mode.
2. Name the active ink scope.
3. Name which layer currently owns visible ink: saved renderer or live PencilKit.
4. Identify whether the change can assign to `pageInkCanvasView.drawing`.
5. Identify whether the change can call `onChartChanged`.
6. Identify whether the change can cancel pending chord/rhythm/passive work.
7. Verify on physical iPad when the change affects Pencil feel.

If a proposed fix cannot answer those seven points, it is not ready to implement.

## Non-Goals For This Branch

- chord recognition accuracy changes
- OCR
- candidate UI
- handwritten-to-cleanup marketing claims
- broad rewrite of editor architecture
- export redesign
- app-wide telemetry dashboards

The immediate goal is a lighter, more reliable writing and editing path with clear state ownership.
