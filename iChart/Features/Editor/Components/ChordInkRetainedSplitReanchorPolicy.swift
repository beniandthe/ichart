#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Rebuilds retained chord anchors after an ordinary divider partitions an
/// open measure. This is source verification, not permission to consume ink:
/// the caller still owns the pen-up, transaction, and glyph collision checks.
enum ChordInkRetainedSplitReanchorPolicy {
    static func reanchored(
        state: ChordPreviewState,
        drawing: PKDrawing,
        originalLayout: LeadSheetPageLayout,
        destinationLayout: LeadSheetPageLayout,
        sourceFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> ChordPreviewState? {
        let originalRegion = LeadSheetActiveInkScope.chordWritingRegion(for: originalLayout)
        let destinationRegion = LeadSheetActiveInkScope.chordWritingRegion(for: destinationLayout)
        guard layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet,
              originalRegion == destinationRegion,
              originalRegion.frame == sourceFrame,
              originalLayout.pageBounds == destinationLayout.pageBounds,
              state.draftBarlines.isEmpty, state.draftEndings.isEmpty,
              !state.draftChords.isEmpty else { return nil }

        // Match whole, uniquely owned live strokes, including chronology and
        // transforms. Neither a nearby mark nor a bitmap fragment shared with
        // another target may inherit a correction or a new measure anchor.
        var ownedIndices = Set<Int>()
        for draft in state.draftChords {
            guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: drawing),
                  ownedIndices.isDisjoint(with: plan.originalStrokeIndices) else { return nil }
            ownedIndices.formUnion(plan.originalStrokeIndices)
        }

        // Run the shipping full-source partitioner on the destination layout.
        // A split, merge, extra target, or newly structural interpretation is
        // deliberately refused rather than assigning old text to changed ink.
        guard let drawingData = LeadSheetPersistentInkColorPolicy.serialization(for: drawing).drawingData else { return nil }
        let preparation = ChordInkRecognitionPreparation.prepare(.init(
            requestID: UUID(), scheduledAt: .now, requestedDelay: 0,
            drawingData: drawingData,
            chordFrame: sourceFrame, pageLayout: destinationLayout,
            flow: .draftPreview, options: .live, layoutStyle: layoutStyle
        ))
        guard preparation.barlines.isEmpty, preparation.endings.isEmpty,
              case .ready(let requests, _) = preparation.outcome,
              requests.count == state.draftChords.count else { return nil }

        var result = state
        var claimedRequests = Set<Int>()
        for index in result.draftChords.indices {
            let original = state.draftChords[index]
            guard let source = try? PKDrawing(data: original.drawingData) else { return nil }
            let matches = requests.indices.filter { requestIndex in
                guard let preparedSource = try? PKDrawing(data: requests[requestIndex].drawingData) else { return false }
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: preparedSource)
            }
            guard matches.count == 1, let requestIndex = matches.first,
                  claimedRequests.insert(requestIndex).inserted else { return nil }
            let request = requests[requestIndex]
            guard let originalLane = LeadSheetChordInkRecognitionTargeting.laneLocation(
                    for: source, chordFrame: sourceFrame, pageLayout: originalLayout),
                  let destinationLane = request.laneLocation,
                  samePhysicalRow(originalLane: originalLane, destinationLane: destinationLane,
                    originalLayout: originalLayout, destinationLayout: destinationLayout),
                  let measure = destinationLayout.systems.flatMap(\.measures).first(where: {
                    $0.chordInkTargetMeasureID == request.target.measureID
                  }) else { return nil }

            // Preserve the exact source archive, row ID, and explicit edit.
            // A fresh collecting identity prevents the old frozen owner from
            // bypassing recognition in its newly partitioned measure.
            result.draftChords[index].measureID = request.target.measureID
            result.draftChords[index].measureIndex = measure.index
            result.draftChords[index].targetFraction = request.target.fraction
            result.draftChords[index].visualOrder = request.visualOrder
            result.draftChords[index].laneLocation = destinationLane
            result.draftChords[index].layoutPageSize = request.layoutPageSize
            result.draftChords[index].anchor = request.collectingTargetLifecycle.anchor
            result.draftChords[index].targetLifecycle = request.collectingTargetLifecycle
            result.draftChords[index].requiresManualReviewOnly = original.requiresManualReviewOnly
                || request.requiresManualReviewOnly
        }
        result.layoutPageSize = destinationLayout.pageBounds.size
        return result
    }

    private static func samePhysicalRow(
        originalLane: ChordInkDraftLaneLocation,
        destinationLane: ChordInkDraftLaneLocation,
        originalLayout: LeadSheetPageLayout,
        destinationLayout: LeadSheetPageLayout
    ) -> Bool {
        let originalRows = originalLayout.systems.filter { $0.index == originalLane.systemIndex }
        let destinationRows = destinationLayout.systems.filter { $0.index == destinationLane.systemIndex }
        guard originalRows.count == 1, destinationRows.count == 1,
              let original = originalRows.first, let destination = destinationRows.first,
              let originalFrame = LeadSheetActiveInkScope.chordWritingSystemInputFrame(
                for: original, paperFrame: originalLayout.paperFrame(for: original)),
              let destinationFrame = LeadSheetActiveInkScope.chordWritingSystemInputFrame(
                for: destination, paperFrame: destinationLayout.paperFrame(for: destination)) else { return false }
        return originalFrame == destinationFrame
            && original.staffLineYPositions == destination.staffLineYPositions
    }
}
#endif
