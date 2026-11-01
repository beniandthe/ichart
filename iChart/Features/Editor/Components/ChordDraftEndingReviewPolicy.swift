#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit

struct PendingChordDraftEndingReview: Identifiable {
    let id = UUID()
    let chartID: UUID
    let endingID: UUID
    let sourceDrawingData: Data?
    let sourceCoordinateSpace: PersistentInkCoordinateSpace?
    let measureIDs: [UUID]
    let layoutStyle: ChartLayoutStyle
    let state: ChordPreviewState
    let continuesRendering: Bool
    let ending: DraftEnding
    let sourceEndingDrawingData: Data
    let measureRange: ClosedRange<Int>?
    let availableMeasureCount: Int
    let rangeContext: ChordDraftEndingRangeReviewContext
    /// Range geometry and existing notation may change without replacing a
    /// measure ID. A label approval belongs to this complete chart snapshot.
    let chartSnapshot: Chart
}

/// Reviewing a label changes only a temporary ending draft. The live canvas
/// remains responsible for validating and consuming source during Render.
enum ChordDraftEndingReviewPolicy {
    static func firstEndingNeedingReview(chart: Chart, state: ChordPreviewState) -> DraftEnding? {
        state.draftEndings.sorted {
            if $0.visualOrder != $1.visualOrder { return $0.visualOrder < $1.visualOrder }
            return $0.id.uuidString < $1.id.uuidString
        }.first {
            !$0.isRenderable || chart.draftEndingMeasureRange(for: $0, state: state) == nil
        }
    }

    static func request(
        for chart: Chart,
        state: ChordPreviewState,
        endingID: UUID? = nil,
        continuesRendering: Bool = true
    ) -> PendingChordDraftEndingReview? {
        let ending: DraftEnding?
        if let endingID {
            ending = state.draftEndings.first { $0.id == endingID }
        } else {
            ending = firstEndingNeedingReview(chart: chart, state: state)
        }
        guard let ending,
              state.draftEndings.filter({ $0.id == ending.id }).count == 1,
              let sourceDrawingData = chart.pageHandwrittenChordData,
              let drawing = try? PKDrawing(data: sourceDrawingData),
              !ending.sourceStrokeIndices.isEmpty,
              ending.sourceStrokeIndices.allSatisfy({ drawing.strokes.indices.contains($0) }),
              let rangeContext = ChordDraftEndingRangeReviewContext.capture(chart: chart, state: state) else { return nil }
        let source = PKDrawing(strokes: ending.sourceStrokeIndices.sorted().map { drawing.strokes[$0] })
        return PendingChordDraftEndingReview(
            chartID: chart.id, endingID: ending.id,
            sourceDrawingData: sourceDrawingData,
            sourceCoordinateSpace: chart.pageHandwrittenChordCoordinateSpace,
            measureIDs: chart.measures.map(\.id), layoutStyle: chart.layoutStyle,
            state: state, continuesRendering: continuesRendering,
            ending: ending, sourceEndingDrawingData: source.dataRepresentation(),
            measureRange: chart.draftEndingMeasureRange(for: ending, state: state)
                ?? chart.draftEndingMeasureRange(for: ending, state: state, ignoringReviewedRange: true),
            availableMeasureCount: chart.draftEndingReviewMeasureCount(state: state) ?? 0,
            rangeContext: rangeContext,
            chartSnapshot: chart
        )
    }

    static func reviewedState(
        for request: PendingChordDraftEndingReview,
        chart: Chart,
        currentState: ChordPreviewState,
        label: String,
        endStyle: EndingEndStyle,
        measureRange: ClosedRange<Int>? = nil
    ) -> ChordPreviewState? {
        guard let normalizedLabel = RoadmapObject.normalizedEndingDisplayText(label),
              let chosenRange = measureRange ?? request.measureRange,
              chosenRange.lowerBound >= 1,
              chosenRange.upperBound <= request.availableMeasureCount,
              chart.id == request.chartID,
              chart == request.chartSnapshot,
              chart.pageHandwrittenChordData == request.sourceDrawingData,
              chart.pageHandwrittenChordCoordinateSpace == request.sourceCoordinateSpace,
              chart.measures.map(\.id) == request.measureIDs,
              chart.layoutStyle == request.layoutStyle,
              currentState.draftChords == request.state.draftChords,
              currentState.draftBarlines == request.state.draftBarlines,
              currentState.draftEndings == request.state.draftEndings,
              currentState.layoutPageSize == request.state.layoutPageSize,
              currentState.draftEndings.filter({ $0.id == request.endingID }).count == 1,
              let index = currentState.draftEndings.firstIndex(where: { $0.id == request.endingID }) else { return nil }
        var reviewed = currentState
        reviewed.draftEndings[index].label = normalizedLabel
        reviewed.draftEndings[index].endStyle = endStyle
        reviewed.draftEndings[index].reviewedSourceInkData = request.sourceEndingDrawingData
        reviewed.draftEndings[index].reviewedMeasureRange = chosenRange
        reviewed.draftEndings[index].reviewedRangeContext = request.rangeContext
        reviewed.draftEndings[index].isReviewed = true
        return reviewed
    }
}
#endif
