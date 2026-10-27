#if canImport(UIKit) && canImport(PencilKit)
import Foundation

struct PendingChordDraftRepeatConfirmation: Identifiable {
    let id = UUID()
    let chartID: UUID
    let draftID: UUID
    let sourceDrawingData: Data?
    let sourceCoordinateSpace: PersistentInkCoordinateSpace?
    let measureIDs: [UUID]
    let layoutStyle: ChartLayoutStyle
    let state: ChordPreviewState
}

/// A confirmation belongs to the exact reviewed draft and source snapshot.
/// The live canvas still validates its current drawing before any source ink is consumed.
enum ChordDraftRepeatReviewPolicy {
    static func blockingMessage(for state: ChordPreviewState) -> String? {
        let review = ChordInkRepeatSignPairingPolicy.review(state: state)
        if !review.nestedStartIDs.isEmpty {
            return "These repeat signs contain a start repeat before the previous repeat has ended. Add or correct the end repeat, then render again. Nothing was rendered or erased."
        }
        if !review.unmatchedStartIDs.isEmpty {
            return "A start repeat needs an end repeat. Add the closing sign, then render again. Nothing was rendered or erased."
        }
        return nil
    }

    static func confirmation(for chart: Chart, state: ChordPreviewState) -> PendingChordDraftRepeatConfirmation? {
        guard blockingMessage(for: state) == nil,
              let draftID = ChordInkRepeatSignPairingPolicy.review(state: state).unconfirmedEndIDs.first else { return nil }
        return PendingChordDraftRepeatConfirmation(
            chartID: chart.id, draftID: draftID,
            sourceDrawingData: chart.pageHandwrittenChordData,
            sourceCoordinateSpace: chart.pageHandwrittenChordCoordinateSpace,
            measureIDs: chart.measures.map(\.id), layoutStyle: chart.layoutStyle, state: state)
    }

    static func confirmedState(
        for request: PendingChordDraftRepeatConfirmation,
        chart: Chart,
        currentState: ChordPreviewState
    ) -> ChordPreviewState? {
        guard chart.id == request.chartID,
              chart.pageHandwrittenChordData == request.sourceDrawingData,
              chart.pageHandwrittenChordCoordinateSpace == request.sourceCoordinateSpace,
              chart.measures.map(\.id) == request.measureIDs,
              chart.layoutStyle == request.layoutStyle,
              currentState.draftChords == request.state.draftChords,
              currentState.draftBarlines == request.state.draftBarlines,
              currentState.layoutPageSize == request.state.layoutPageSize,
              blockingMessage(for: currentState) == nil,
              ChordInkRepeatSignPairingPolicy.review(state: currentState).unconfirmedEndIDs.first == request.draftID,
              let index = currentState.draftBarlines.firstIndex(where: { $0.id == request.draftID }) else { return nil }
        var confirmed = currentState
        confirmed.draftBarlines[index].repeatFromBeginningConfirmed = true
        return confirmed
    }
}
#endif
