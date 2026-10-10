#if canImport(UIKit)
import PencilKit
import UIKit

enum LeadSheetManualInkEraseSamplingPolicy {
    static let minimumSegmentDistance: CGFloat = 4
    static let maximumSegmentDistance: CGFloat = 12
    static let denseInkStrokeThreshold = 64
    static let maximumDensityStrokeCount = 512

    static func segmentDistance(strokeCount: Int) -> CGFloat {
        guard strokeCount > denseInkStrokeThreshold else {
            return minimumSegmentDistance
        }

        let progress = min(
            1,
            CGFloat(strokeCount - denseInkStrokeThreshold)
                / CGFloat(maximumDensityStrokeCount - denseInkStrokeThreshold)
        )
        return minimumSegmentDistance
            + (maximumSegmentDistance - minimumSegmentDistance) * progress
    }

    static func shouldProcessSegment(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        forcesFinalSample: Bool,
        strokeCount: Int = 0
    ) -> Bool {
        guard !forcesFinalSample else {
            return true
        }

        return hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
            >= segmentDistance(strokeCount: strokeCount)
    }
}

final class LeadSheetScopedInkCanvasView: PKCanvasView {
    var manualEraseEnabled = false {
        didSet {
            guard oldValue != manualEraseEnabled else {
                return
            }

            lastManualEraseLocation = nil
        }
    }

    // Reading PKDrawing.strokes can materialize the full stroke array. Keep
    // that work out of both tool selection and raw Pencil movement; the host
    // refreshes this count for every delegate or programmatic drawing change.
    var manualEraseSamplingStrokeCount = 0

    var manualEraseHandler: ((CGPoint, CGPoint) -> Void)?
    var liveInkInputBeganHandler: (() -> Void)?
    var localInputFrames: [CGRect] = [] {
        didSet {
            guard oldValue != localInputFrames else {
                return
            }

            setNeedsLayout()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else {
            return false
        }
        guard !localInputFrames.isEmpty else {
            return true
        }

        return localInputFrames.contains { inputFrame in
            inputFrame.insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouches = pencilEligibleTouches(from: touches) else {
            return
        }
        if !handleManualErase(activeTouches, with: event, forcesFinalSample: true) {
            // Give PencilKit the contact before acquiring any cancellation locks.
            // Pending recognition/persistence completions are dispatched on the
            // main queue, so cancelling them immediately afterward is still
            // ordered ahead of any stale UI completion while prioritizing the
            // first visible ink sample.
            super.touchesBegan(activeTouches, with: event)
            liveInkInputBeganHandler?()
            return
        }

        liveInkInputBeganHandler?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouches = pencilEligibleTouches(from: touches) else {
            return
        }
        guard handleManualErase(activeTouches, with: event, forcesFinalSample: false) else {
            super.touchesMoved(activeTouches, with: event)
            return
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouches = pencilEligibleTouches(from: touches) else {
            lastManualEraseLocation = nil
            return
        }
        if handleManualErase(activeTouches, with: event, forcesFinalSample: true) {
            lastManualEraseLocation = nil
            return
        }

        lastManualEraseLocation = nil
        super.touchesEnded(activeTouches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastManualEraseLocation = nil
        guard let activeTouches = pencilEligibleTouches(from: touches) else {
            return
        }
        guard manualEraseEnabled else {
            super.touchesCancelled(activeTouches, with: event)
            return
        }
    }

    private var lastManualEraseLocation: CGPoint?

    private func handleManualErase(
        _ touches: Set<UITouch>,
        with event: UIEvent?,
        forcesFinalSample: Bool
    ) -> Bool {
        guard manualEraseEnabled,
              let touch = touches.first else {
            return false
        }
        guard drawingPolicy != .pencilOnly || touch.type == .pencil else {
            lastManualEraseLocation = nil
            return false
        }

        let location = touch.location(in: self)
        guard point(inside: location, with: event) else {
            lastManualEraseLocation = nil
            return false
        }

        let previousLocation = lastManualEraseLocation ?? touch.previousLocation(in: self)
        guard LeadSheetManualInkEraseSamplingPolicy.shouldProcessSegment(
            from: previousLocation,
            to: location,
            forcesFinalSample: forcesFinalSample,
            strokeCount: manualEraseSamplingStrokeCount
        ) else {
            // Keep the previous processed point so skipped movement is folded into
            // the next segment rather than creating a gap in the erase path.
            return true
        }

        lastManualEraseLocation = location
        manualEraseHandler?(previousLocation, location)
        return true
    }

    private func pencilEligibleTouches(from touches: Set<UITouch>) -> Set<UITouch>? {
        guard drawingPolicy == .pencilOnly else {
            return touches
        }

        let pencilTouches = touches.filter { touch in
            touch.type == .pencil
        }
        guard !pencilTouches.isEmpty else {
            lastManualEraseLocation = nil
            return nil
        }

        return Set(pencilTouches)
    }
}
#endif
