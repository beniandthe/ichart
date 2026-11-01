#if canImport(UIKit)
import CoreGraphics
import UIKit

/// Ephemeral editor feedback. Its range is zero-based and inclusive; none of
/// this presentation state is written into the chart or exported notation.
struct LeadSheetEndingDragFeedback: Equatable {
    let action: RenderedEditAction
    let range: ClosedRange<Int>
    let sourceSystemIndex: Int
}

/// Owns a temporary ending drag. The canvas applies the returned chart once,
/// after a completed gesture; previews never write to its chart binding.
struct LeadSheetEndingEditInteraction {
    struct Effect {
        var began = false
        var finished = false
        var needsDisplay = false
        var committedChart: Chart?
        var action: RenderedEditAction?
    }

    private var session: LeadSheetEndingDragSession?
    private var sourceChart: Chart?
    private var sourceLayout: LeadSheetPageLayout?
    private var activeEndingID: UUID?
    private var activeAction: RenderedEditAction?
    private var previewedRange: ClosedRange<Int>?
    private(set) var previewChart: Chart?
    private(set) var dragFeedback: LeadSheetEndingDragFeedback?

    var isActive: Bool { session != nil }

    func isCompatible(chart: Chart, pageLayout: LeadSheetPageLayout?, selectedEndingID: UUID?) -> Bool {
        !isActive || (sourceChart == chart && sourceLayout == pageLayout && activeEndingID == selectedEndingID)
    }

    @discardableResult
    mutating func cancel() -> Bool {
        let wasActive = isActive
        session = nil
        sourceChart = nil
        sourceLayout = nil
        activeEndingID = nil
        activeAction = nil
        previewedRange = nil
        previewChart = nil
        dragFeedback = nil
        return wasActive
    }

    mutating func handle(
        state: UIGestureRecognizer.State, startLocation: CGPoint, location: CGPoint,
        chart: Chart, pageLayout: LeadSheetPageLayout?, selectedEndingID: UUID?,
        target: RenderedEditHitTarget?, screenPointsPerDisplayedPoint: CGFloat = 1
    ) -> Effect {
        if state == .began {
            let replacedActiveSession = cancel()
            let rejected = Effect(finished: replacedActiveSession, needsDisplay: replacedActiveSession)
            guard let pageLayout, let target, case .endingSpan(let endingID) = target.objectID,
                  endingID == selectedEndingID,
                  target.action == .move || target.action == .resizeTrailing else { return rejected }
            let controls = LeadSheetEndingEditOverlay.controlFrames(for: endingID, in: pageLayout,
                screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint)
            guard let sourceSystemIndex = controls.first(where: { controls in
                let frame = target.action == .move ? controls.moveHandle : controls.lengthenHandle
                return frame?.contains(startLocation) == true
            })?.systemIndex else { return rejected }
            guard let drag = LeadSheetEndingDragSession(chart: chart, endingID: endingID,
                action: target.action, startLocation: startLocation, sourcePageLayout: pageLayout,
                sourceSystemIndex: sourceSystemIndex) else { return rejected }
            session = drag
            sourceChart = chart
            sourceLayout = pageLayout
            activeEndingID = endingID
            activeAction = target.action
            previewedRange = drag.initialRange
            dragFeedback = LeadSheetEndingDragFeedback(action: target.action,
                range: drag.initialRange, sourceSystemIndex: drag.sourceSystemIndex)
            return Effect(began: true, finished: replacedActiveSession, needsDisplay: true, action: target.action)
        }

        guard let session else { return Effect() }
        guard isCompatible(chart: chart, pageLayout: pageLayout, selectedEndingID: selectedEndingID) else {
            _ = cancel()
            return Effect(finished: true, needsDisplay: true)
        }
        switch state {
        case .changed:
            let range = session.previewRange(at: location)
            let changed = range != previewedRange
            if changed {
                previewedRange = range
                previewChart = range == nil ? nil : session.previewChart(at: location)
                dragFeedback = range.map { LeadSheetEndingDragFeedback(action: session.action,
                    range: $0, sourceSystemIndex: session.sourceSystemIndex) }
            }
            return Effect(needsDisplay: changed, action: activeAction)
        case .ended:
            let committed = session.committedChart(at: location, currentChart: chart)
            let action = activeAction
            _ = cancel()
            return Effect(finished: true, needsDisplay: true, committedChart: committed, action: action)
        case .cancelled, .failed:
            _ = cancel()
            return Effect(finished: true, needsDisplay: true)
        default:
            return Effect()
        }
    }
}
#endif
