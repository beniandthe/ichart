#if canImport(UIKit)
import PencilKit

enum LeadSheetChordInkImageRenderer {
    static func renderBounds(for drawing: PKDrawing) -> CGRect {
        drawing.strokes.reduce(CGRect.null) { partialBounds, stroke in
            let strokeBounds = stroke.renderBounds
            guard !strokeBounds.isNull else {
                return partialBounds
            }

            return partialBounds.isNull ? strokeBounds : partialBounds.union(strokeBounds)
        }
    }
}
#endif
