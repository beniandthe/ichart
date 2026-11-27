#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

/// Rebuilds retained source anchors after an ordinary divider partitions an
/// open measure. This is source verification, not permission to consume ink:
/// the caller still owns the pen-up, transaction, and glyph collision checks.
@MainActor
enum ChordInkRetainedSplitReanchorPolicy {
    static func reanchored(
        state: ChordPreviewState,
        drawing: PKDrawing,
        originalLayout: LeadSheetPageLayout,
        destinationLayout: LeadSheetPageLayout,
        sourceFrame: CGRect,
        layoutStyle: ChartLayoutStyle,
        originalDrawing: PKDrawing? = nil,
        removingSourceIndices: Set<Int> = []
    ) -> ChordPreviewState? {
        let originalRegion = LeadSheetActiveInkScope.chordWritingRegion(for: originalLayout)
        let destinationRegion = LeadSheetActiveInkScope.chordWritingRegion(for: destinationLayout)
        guard layoutStyle == .simpleChordSheet || layoutStyle == .rhythmSectionSheet,
              originalRegion == destinationRegion,
              originalRegion.frame == sourceFrame,
              originalLayout.pageBounds == destinationLayout.pageBounds,
              state.draftEndings.isEmpty,
              !state.draftChords.isEmpty || !state.draftBarlines.isEmpty else { return nil }

        let remappedBarlines = ChordDraftBarlineDeletionPolicy.remappingSourceIndices(
            state.draftBarlines, afterRemoving: removingSourceIndices)
        guard remappedBarlines.count == state.draftBarlines.count else { return nil }
        if !state.draftBarlines.isEmpty {
            // Structural claims use indices into the whole original source.
            // Prove that rebasing them refers to those very same raw strokes,
            // rather than a nearby line at the new canonical fraction.
            guard let originalDrawing,
                  removingSourceIndices.allSatisfy(originalDrawing.strokes.indices.contains) else { return nil }
            let retainedSource = PKDrawing(strokes: originalDrawing.strokes.enumerated().compactMap {
                removingSourceIndices.contains($0.offset) ? nil : $0.element
            })
            guard ChordInkAutomaticSourcePrefixPolicy.hasIdenticalOrderedSource(
                snapshot: retainedSource, current: drawing) else { return nil }
        }

        // Match whole, uniquely owned live strokes, including chronology and
        // transforms. Neither a nearby mark nor a bitmap fragment shared with
        // another target may inherit a correction or a new measure anchor.
        var remappedState = state
        remappedState.draftBarlines = remappedBarlines
        var ownedIndices = Set<Int>()
        for draft in state.draftChords {
            guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: remappedState, source: drawing),
                  ownedIndices.isDisjoint(with: plan.originalStrokeIndices) else { return nil }
            ownedIndices.formUnion(plan.originalStrokeIndices)
        }
        for barline in remappedBarlines {
            let indices = barline.ownedSourceStrokeIndices
            guard !indices.isEmpty, indices.allSatisfy(drawing.strokes.indices.contains),
                  ownedIndices.isDisjoint(with: indices) else { return nil }
            ownedIndices.formUnion(indices)
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
        guard preparation.barlines.count == remappedBarlines.count, preparation.endings.isEmpty else { return nil }
        let requests: [ChordInkRecognitionSessionRequest]
        switch preparation.outcome {
        case .ready(let preparedRequests, _): requests = preparedRequests
        case .noRecognitionData where state.draftChords.isEmpty:
            // A retained boundary alone has no chord reader work. Its exact
            // structural source and canonical destination are still verified.
            requests = []
        default: return nil
        }
        guard requests.count == state.draftChords.count else { return nil }

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
        var claimedBarlines = Set<Int>()
        var canonicalBarlines: [DraftBarline] = []
        for prior in remappedBarlines {
            let matches = preparation.barlines.indices.filter { index in
                let fresh = preparation.barlines[index]
                return fresh.ownedSourceStrokeIndices == prior.ownedSourceStrokeIndices
                    && fresh.kind == prior.kind && fresh.ambiguity == prior.ambiguity
                    && fresh.metrics == prior.metrics
            }
            guard matches.count == 1, let index = matches.first,
                  claimedBarlines.insert(index).inserted,
                  let originalLane = prior.laneLocation,
                  let destinationLane = preparation.barlines[index].laneLocation,
                  samePhysicalRow(originalLane: originalLane, destinationLane: destinationLane,
                    originalLayout: originalLayout, destinationLayout: destinationLayout) else { return nil }
            var canonical = preparation.barlines[index]
            canonical.id = prior.id
            canonicalBarlines.append(canonical)
        }
        result.draftBarlines = canonicalBarlines
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
