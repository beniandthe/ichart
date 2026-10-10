#if canImport(UIKit)
import Foundation
import PencilKit

/// Session-local state only. Never carry page-space ownership across charts or
/// coordinate/layout changes, or adopt the result of superseded preparation.
struct ChordInkEditedTargetSessionState {
    struct Scope: Equatable {
        var chartID: UUID
        var chordFrame: CGRect
        var pageLayout: LeadSheetPageLayout?
        var layoutStyle: ChartLayoutStyle
    }

    private var scope: Scope?
    private var ownership = ChordInkEditedTargetOwnership()

    mutating func snapshot(in nextScope: Scope) -> ChordInkEditedTargetOwnership {
        if scope != nextScope {
            scope = nextScope
            ownership = .init()
        }
        return ownership
    }

    mutating func accept(_ next: ChordInkEditedTargetOwnership, in expectedScope: Scope) {
        guard scope == expectedScope else { return }
        ownership = next
    }

    mutating func reset() {
        scope = nil
        ownership = .init()
    }
}

enum ChordInkEditedTargetPreparation {
    struct Result {
        var targets: [LeadSheetChordInkRecognitionBatchTarget]
        var nextOwnership: ChordInkEditedTargetOwnership
    }

    /// Operates on exact recognition indices before preview load filtering.
    /// Restores proven owners or unions targets; never drops, duplicates, or rescales ink.
    static func resolve(
        _ targets: [LeadSheetChordInkRecognitionBatchTarget],
        ownership: ChordInkEditedTargetOwnership,
        visibleStrokes: [InkStroke],
        recognitionStrokes: [InkStroke],
        recognitionDrawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> Result {
        let drawingStrokes = recognitionDrawing.strokes
        let indices = targets.flatMap(\.recognitionStrokeIndices)
        guard drawingStrokes.count == recognitionStrokes.count,
              Set(indices).count == indices.count,
              targets.allSatisfy({ target in
                  !target.recognitionStrokeIndices.isEmpty &&
                  target.recognitionStrokeIndices.allSatisfy { recognitionStrokes.indices.contains($0) } &&
                  target.recognitionStrokeIndices.map { recognitionStrokes[$0] } == target.strokes
              }) else {
            return Result(targets: targets.map { target in
                var target = target; target.requiresEditReview = true; return target
            }, nextOwnership: .init())
        }
        let proposed = targets.map {
            ChordInkEditedTargetOwnership.Target(lane: $0.laneLocation?.systemIndex ?? -1, strokes: $0.strokes)
        }
        let resolution = ownership.resolving(proposed, visibleStrokes: visibleStrokes)
        let resolved = resolution.sourceStrokes.enumerated().map { ordinal, sources in
            var target = targets[sources[0].targetIndex]
            target.requiresEditReview = resolution.requiresReview.contains(ordinal)
            let indices = sources.map { targets[$0.targetIndex].recognitionStrokeIndices[$0.strokeIndex] }.sorted()
            guard indices != target.recognitionStrokeIndices else { return target }
            let drawing = PKDrawing(strokes: indices.map { drawingStrokes[$0] })
            target.recognitionStrokeIndices = indices
            target.strokes = indices.map { recognitionStrokes[$0] }
            target.drawing = drawing
            target.drawingData = drawing.dataRepresentation()
            if let anchor = LeadSheetChordInkRecognitionTargeting.target(
                for: drawing, chordFrame: chordFrame, pageLayout: pageLayout) {
                target.measureID = anchor.measureID
                target.fraction = anchor.fraction
            }
            target.laneLocation = LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: drawing, chordFrame: chordFrame, pageLayout: pageLayout)
            target.visualOrder = LeadSheetChordInkRecognitionTargeting.visualOrder(
                for: drawing, chordFrame: chordFrame, pageLayout: pageLayout) ?? target.visualOrder
            return target
        }
        return Result(targets: resolved, nextOwnership: resolution.next)
    }
}
#endif
