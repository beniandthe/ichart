#if canImport(UIKit)
import PencilKit
import UIKit

enum LeadSheetChordInkImageRenderer {
    private static let ocrImageScale: CGFloat = 4
    private static let ocrCropPadding = CGSize(width: 30, height: 28)
    private static let minimumOCRCropSize = CGSize(width: 96, height: 96)

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
        let drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        let inkBounds = renderBounds(for: drawing)
        guard !inkBounds.isNull,
              inkBounds.width > 1,
              inkBounds.height > 1 else {
            return nil
        }

        let cropBounds = ocrCropBounds(for: inkBounds)
        guard let drawingData = LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing),
              let inkImage = LeadSheetSavedInkRenderer.renderedInkImage(
                drawingData,
                in: cropBounds,
                scale: ocrImageScale
              ) else {
            return nil
        }
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.opaque = true
        rendererFormat.scale = inkImage.scale > 0 ? inkImage.scale : ocrImageScale
        let renderer = UIGraphicsImageRenderer(size: inkImage.size, format: rendererFormat)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: inkImage.size))
            inkImage.draw(in: CGRect(origin: .zero, size: inkImage.size))
        }

        return image.cgImage
    }

    private static func ocrCropBounds(for inkBounds: CGRect) -> CGRect {
        let paddedBounds = inkBounds.insetBy(
            dx: -ocrCropPadding.width,
            dy: -ocrCropPadding.height
        )
        let width = max(paddedBounds.width, minimumOCRCropSize.width)
        let height = max(paddedBounds.height, minimumOCRCropSize.height)

        return CGRect(
            x: paddedBounds.midX - width / 2,
            y: paddedBounds.midY - height / 2,
            width: width,
            height: height
        )
    }
}
#endif
