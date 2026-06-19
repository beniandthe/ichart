#if canImport(UIKit)
import PencilKit
import UIKit

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

    static func ocrImage(for drawing: PKDrawing) -> CGImage? {
        let inkBounds = renderBounds(for: drawing)
        guard !inkBounds.isNull,
              inkBounds.width > 1,
              inkBounds.height > 1 else {
            return nil
        }

        let cropBounds = inkBounds.insetBy(dx: -18, dy: -18)
        let inkImage = drawing.image(from: cropBounds, scale: 3)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.opaque = true
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: inkImage.size, format: rendererFormat)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: inkImage.size))
            inkImage.draw(in: CGRect(origin: .zero, size: inkImage.size))
        }

        return image.cgImage
    }
}
#endif
