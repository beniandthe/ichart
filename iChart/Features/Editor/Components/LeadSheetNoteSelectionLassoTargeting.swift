#if canImport(UIKit)
import PencilKit
import UIKit

enum LeadSheetNoteSelectionLassoTargeting {
    static func lassoFrame(
        for drawing: PKDrawing,
        activeInkScope: LeadSheetActiveInkScope?,
        ignoringTapAt tapLocation: CGPoint,
        allowsNoteSelection: Bool
    ) -> CGRect? {
        guard let activeInkScope else {
            return nil
        }

        let tapLocationInInkScope = CGPoint(
            x: tapLocation.x - activeInkScope.frame.minX,
            y: tapLocation.y - activeInkScope.frame.minY
        )
        let lassoBounds = drawing.strokes.reduce(CGRect?.none) { partialResult, stroke in
            let strokeBounds = stroke.renderBounds
            guard !isIncidentalTapStroke(
                strokeBounds,
                near: tapLocationInInkScope,
                allowsNoteSelection: allowsNoteSelection
            ) else {
                return partialResult
            }

            return partialResult?.union(strokeBounds) ?? strokeBounds
        }

        guard let lassoBounds,
              !lassoBounds.isNull,
              lassoBounds.width >= 10,
              lassoBounds.height >= 10 else {
            return nil
        }

        return lassoBounds
            .offsetBy(dx: activeInkScope.frame.minX, dy: activeInkScope.frame.minY)
            .insetBy(dx: -4, dy: -4)
    }

    private static func isIncidentalTapStroke(
        _ strokeBounds: CGRect,
        near tapLocation: CGPoint,
        allowsNoteSelection: Bool
    ) -> Bool {
        let maximumTapDotSize: CGFloat = 12
        let tapSlop: CGFloat = 18
        guard strokeBounds.width <= maximumTapDotSize,
              strokeBounds.height <= maximumTapDotSize else {
            return false
        }

        return allowsNoteSelection
            || strokeBounds.insetBy(dx: -tapSlop, dy: -tapSlop).contains(tapLocation)
    }
}
#endif
