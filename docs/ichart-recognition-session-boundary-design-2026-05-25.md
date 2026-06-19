# iChart Recognition Session Boundary Design

Status: Sprint 35 design proposal; first implementation completed in Sprint 37
Date: 2026-05-25
Branch: `main`
Baseline commit: `4f1de60 Audit editor recognition execution path`
Primary source of truth: `docs/ichart-sprint-source-of-truth.md`
Supporting audit: `docs/ichart-editor-recognition-execution-audit-2026-05-24.md`

## Summary

Sprint 35 defined a future recognition-session boundary before any more code was moved out of `LeadSheetCanvasHostView.swift`. Sprint 37 implemented the first behavior-preserving version of that boundary. It did not change recognition behavior, OCR behavior, chart mutation, chord ink clearing, native `PKCanvasView`, parser/compendium authority, or fixture policy.

The goal is to make the next extraction safe by separating two concerns:

- The editor bridge owns UIKit/PencilKit state, active mode, page layout, and callbacks.
- `ChordInkRecognitionSession` owns one in-flight recognition request from prepared ink input to a main-thread proposal payload.

This boundary is not a new training or personalization layer. Recognition must
remain writer-agnostic by default. Real Pencil validation should measure whether
the pipeline generalizes beyond one hand; it should not become a continuous
personal chord-sample loop.

This boundary was explicitly selected for Sprint 37 after Sprint 36 reset fixture authority and writer-agnostic recognition policy.

## Why This Boundary Exists

Sprint 34 found that the remaining chord path is not just view scaffolding. It crosses:

- native `PKCanvasView` drawing updates
- delayed request scheduling
- active request cancellation
- mode and active-scope guards
- target-measure calculation
- PencilKit-to-pure-ink conversion
- background `ChordInkRecognizer` execution
- optional Vision OCR
- trust-policy sidecar timing
- continuation-grace requeue
- SwiftUI confirmation or auto-render routing
- structured `ChordEvent` commit
- diagnostic recording
- current chord ink clearing

The next extraction should avoid changing those semantics by giving the future helper a narrow, testable contract.

## Proposed Type

Implemented type name:

```swift
final class ChordInkRecognitionSession
```

Owner: `iChart/Features/Editor/Components/ChordInkRecognitionSession.swift`.

The type should be editor-adjacent, not a core recognition package type, because it depends on UI/runtime concerns: scheduling, queueing, optional Vision OCR image input, and main-thread proposal delivery.

## Inputs

The session request receives only prepared values:

- `requestID: UUID`
- `scheduledAt: Date`
- `requestedDelay: TimeInterval`
- `strokes: [InkStroke]`
- `drawingData: Data`
- `drawingForOCR: PKDrawing` or an already-rendered OCR image provider closure
- `target: (measureID: UUID, fraction: Double)`
- `recognizer: ChordInkRecognizing`
- `options: ChordInkRecognitionOptions`
- `ocrCandidateProvider: ChordOCRCandidateProviding?`

The session should not read directly from `PKCanvasView`, `Chart`, `selectedMeasureID`, `pageLayout`, or `EditorCanvasMode`.

## Outputs

The session should return a main-thread proposal payload:

```swift
struct ChordInkRecognitionProposalPayload {
    var requestID: UUID
    var result: ChordInkRecognitionResult
    var drawingData: Data
    var target: (measureID: UUID, fraction: Double)
    var timing: ChordInkRecognitionTiming
}
```

The payload should not append a chord, clear ink, open UI, record diagnostics, or mutate chart state.

## Ownership Rules

### Remains In `LeadSheetCanvasHostView.swift`

- `PKCanvasViewDelegate.canvasViewDrawingDidChange`
- active `EditorCanvasMode` checks
- active ink scope resolution
- current drawing-data lookup
- target selection through `LeadSheetChordInkRecognitionTargeting`
- stale request validation before accepting a completed payload
- continuation-grace decision and requeue unless a later design moves it explicitly
- `onChordInkRecognitionProposal` callback

### Moves To Future Session

- background queue execution wrapper
- `ChordInkRecognizer.recognize`
- primary decision calculation for OCR gating
- optional OCR request
- OCR timing measurement
- final `ChordInkRecognitionTiming` construction

### Remains In `EditorView.swift`

- primary/trust decision used for auto-render vs confirmation UI
- compendium validation before commit
- `appendRecognizedChordEvent`
- debug diagnostic recording
- `setPageHandwrittenChordDrawing(nil)` after commit or rewrite
- sheet state and user correction flow

The current chord-entry rule remains: accepting/rendering a chord consumes the chord-writing pass and clears the chord ink layer.

## Threading Contract

The editor starts requests from the main thread.

The session executes recognition and OCR on `chordInkRecognitionQueue`.

The session must deliver its completion on the main thread.

The editor must still reject stale completions by checking `requestID` against `LeadSheetChordInkRecognitionRequestState` before showing proposals or mutating any UI state.

## Cancellation Contract

Cancellation stays cooperative:

- scheduling cancellation cancels pending work before the session starts
- mode changes clear active request state
- completed stale requests are ignored on the main thread

Do not attempt to hard-cancel `ChordInkRecognizer.recognize` mid-flight unless profiling proves it is necessary. The current recognizer work is small enough that request identity is the safer boundary.

## OCR Contract

OCR remains optional and sidecar-only:

- only request OCR when `ChordRecognitionTrustArbiter.shouldRequestOCR` says it is useful
- OCR candidates must remain normalized through `ChordOCRCandidate`
- OCR must not bypass `ChordRecognitionCompendium`
- OCR must not directly render a chord
- OCR availability must remain optional for platforms without Vision/CoreGraphics support

## Policy Contract

The session may calculate the primary decision only to decide whether OCR should run.

The final auto-render vs confirmation decision should remain in `EditorView.swift` for now because that decision crosses UI state, sheet routing, chart mutation, diagnostics, and chord ink clearing.

This avoids accidentally moving product behavior into a background execution helper.

## Implementation Status

Sprint 37 completed the first implementation:

- added `ChordInkRecognitionSessionRequest`
- added `ChordInkRecognitionProposalPayload`
- added `ChordInkRecognitionSession`
- moved background recognizer execution, primary decision calculation for OCR gating, optional OCR request, OCR timing, and timing construction into the session
- kept active-mode guards, target selection, stale-request validation, continuation-grace requeue, proposal callbacks, chart mutation, diagnostics, and chord ink clearing in the host/editor layers
- added app-target session tests for main-thread payload delivery and OCR gating

## Proposed Implementation Steps

1. Add `ChordInkRecognitionProposalPayload`.
2. Add `ChordInkRecognitionSession` with dependency-injected queue, recognizer, and OCR provider.
3. Move only the background `recognizer.recognize` plus optional OCR block into the session.
4. Keep all preflight guards in `LeadSheetCanvasHostView.swift`.
5. Keep stale-request validation in `finishChordInkRecognition`.
6. Keep continuation-grace logic in the host for the first implementation.
7. Verify no change to auto-render/confirmation/commit behavior.

## Test Plan

- `swift test --scratch-path /tmp/iChartSwiftBuild-sprint-session --filter ChordInkRecognizerTests`
- `swift test --scratch-path /tmp/iChartSwiftBuild-sprint-session --filter ChartEditingTests`
- `swift test --scratch-path /tmp/iChartSwiftBuild-sprint-session --filter LeadSheetPageLayoutTests`
- full `swift test --scratch-path /tmp/iChartSwiftBuild-sprint-session`
- `python3 -m py_compile scripts/audit_chord_entry_diagnostics.py scripts/import_chord_fixture.py scripts/watch_simulator_chord_fixtures.py`
- `git diff --check`
- `xcodegen generate`
- XcodeBuildMCP iOS simulator `iChart` scheme tests
- XcodeBuildMCP build/run and screenshot

Behavior checks:

- default recognition results unchanged
- OCR remains ambiguity-only and compendium-gated
- stale requests are ignored
- continuation grace still requeues the same way
- auto-render vs confirm decisions unchanged
- accepting/rendering still clears the chord ink pass

## Non-Goals

- no recognition scoring changes
- no parser or compendium changes
- no fixture archive pruning
- no PencilKit replacement
- no StoreKit/export work
- no change to the current chord ink clear rule
- no new training layer or handwriting personalization
- no tuning based on one person's repeated chord-writing passes
- no automatic or hidden user-specific corpus growth

## Recommendation

Sprint 37 implemented the behavior-preserving session boundary. The next product-safe step should be real Pencil validation across general/user-like handwriting before any recognition tuning. If the work stays repo-local, further session cleanup should stay limited to behavior-preserving boundary polish and must keep auto-render/confirmation, structured commit, diagnostics, and chord ink clearing outside the session.
