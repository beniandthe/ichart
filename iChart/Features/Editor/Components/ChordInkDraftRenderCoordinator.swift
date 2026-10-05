#if canImport(UIKit) && canImport(PencilKit)
import PencilKit

/// Synchronous bridge to the canvas owner. Capturing live ink, preparing the
/// chart, and consuming the canvas can happen in one main-thread callback.
@MainActor
final class ChordInkDraftRenderCoordinator {
    struct Outcome {
        let chart: Chart
        let result: ChordInkDraftBatchRenderResult

        var canConsumeSource: Bool {
            !result.didRejectIncompleteSourceCoverage
                && result.unresolvedDraftIDs.isEmpty
                && (result.renderedChordCount > 0 || result.renderedBarlineCount > 0)
        }
    }

    var renderer: ((Chart, ChordPreviewState) -> Outcome?)?
    struct RewriteOutcome {
        let chart: Chart
        let drawing: PKDrawing
    }

    var rewriter: ((Chart, ChordPreviewState, ChordInkDraft) -> RewriteOutcome?)?
    // Actual PencilKit input callbacks, not summed recognizer compute time.
    var lastInputAt: Date?

    init() {}

    func render(chart: Chart, state: ChordPreviewState) -> Outcome? {
        renderer?(chart, state)
    }

    func rewrite(chart: Chart, state: ChordPreviewState, draft: ChordInkDraft) -> RewriteOutcome? {
        rewriter?(chart, state, draft)
    }

    static func prepareRewrite(
        chart: Chart, state: ChordPreviewState, draft: ChordInkDraft, currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) -> RewriteOutcome? {
        guard let plan = ChordInkDraftLocalRewritePolicy.plan(for: draft, in: state, source: currentDrawing),
              let remaining = plan.rewrittenDrawing(ifCurrentSource: currentDrawing) else { return nil }
        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: remaining)
        var updatedChart = chart
        _ = updatedChart.setPageHandwrittenChordDrawing(
            remaining.strokes.isEmpty ? nil : serialization.drawingData,
            coordinateSpace: remaining.strokes.isEmpty ? nil : coordinateSpace,
            assumesNormalizedPersistentInk: true
        )
        return RewriteOutcome(chart: updatedChart, drawing: remaining)
    }

    /// Prepare exclusively from current live ink, never a cached chart ink
    /// snapshot. This value transaction does not clear or otherwise touch a
    /// canvas. Any rejected, empty, or partial commit returns the original
    /// chart, including its original source bytes, metadata, and timestamps.
    static func prepare(
        chart: Chart,
        state: ChordPreviewState,
        currentDrawing: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace?
    ) -> Outcome {
        // The Chart coverage API intentionally accepts nil stored ink because
        // no stored source is erased. That shortcut must not let stale drafts
        // render after the live canvas has become empty.
        guard !currentDrawing.strokes.isEmpty else {
            return Outcome(chart: chart, result: ChordInkDraftBatchRenderResult(
                renderedChordIDs: [], renderedBarlineIDs: [], unresolvedDraftIDs: [],
                didRejectIncompleteSourceCoverage: !state.isEmpty
            ))
        }

        let serialization = LeadSheetPersistentInkColorPolicy.serialization(for: currentDrawing)
        var preparedChart = chart
        _ = preparedChart.setPageHandwrittenChordDrawing(
            serialization.drawingData,
            coordinateSpace: coordinateSpace,
            assumesNormalizedPersistentInk: true
        )
        let result = preparedChart.commitChordInkDraftBatch(state)
        let outcome = Outcome(chart: preparedChart, result: result)
        return outcome.canConsumeSource ? outcome : Outcome(chart: chart, result: result)
    }
}
#endif
