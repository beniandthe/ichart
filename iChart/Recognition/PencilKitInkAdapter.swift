#if canImport(PencilKit)
import Foundation
import PencilKit

enum PencilKitInkAdapter {
    static func inkStrokes(from drawingData: Data) throws -> [InkStroke] {
        try inkStrokes(from: PKDrawing(data: drawingData))
    }

    static func inkStrokes(from drawing: PKDrawing) -> [InkStroke] {
        drawing.strokes.map(inkStroke(from:))
    }

    private static func inkStroke(from stroke: PKStroke) -> InkStroke {
        InkStroke(
            points: stroke.path.map { strokePoint in
                InkPoint(
                    x: Double(strokePoint.location.x),
                    y: Double(strokePoint.location.y),
                    timeOffset: strokePoint.timeOffset
                )
            }
        )
    }
}
#endif
