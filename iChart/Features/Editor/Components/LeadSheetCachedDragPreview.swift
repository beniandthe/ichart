#if canImport(UIKit)
import UIKit

/// A frozen object raster and vector outline, updated without redrawing paper.
@MainActor
final class LeadSheetCachedDragPreview {
    let layer = CALayer()
    private let glyph = CALayer()
    private let selection = CAShapeLayer()
    private let guide = CAShapeLayer()
    private var sourceContentFrame: CGRect?
    private let padding: CGFloat = 3

    var isActive: Bool { sourceContentFrame != nil }

    init(name: String) {
        layer.name = name
        glyph.name = name + ".glyph"
        selection.name = name + ".selection"
        selection.fillColor = UIColor.clear.cgColor
        selection.strokeColor = UIColor.systemBlue.cgColor
        selection.lineWidth = 1.3
        guide.fillColor = UIColor.clear.cgColor
        guide.strokeColor = UIColor.systemBlue.withAlphaComponent(0.65).cgColor
        guide.lineWidth = 1.2
        layer.addSublayer(glyph)
        layer.addSublayer(selection)
        layer.addSublayer(guide)
    }

    static func rasterScale(for logicalSize: CGSize, preferredScale: CGFloat) -> CGFloat {
        LeadSheetCanvasUIKitView.boundedDocumentRasterScale(logicalSize: logicalSize,
            screenScale: min(4, max(1, preferredScale)), zoomScale: 1)
    }

    static func markerContentFrame(for marker: LeadSheetRoadmapMarkerLayout) -> CGRect {
        marker.frame.union(LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker))
    }

    func begin(contentFrame: CGRect, in parent: CALayer, scale: CGFloat,
        showsOutline: Bool = true, draw: () -> Void) {
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }
        let imageFrame = contentFrame.insetBy(dx: -padding, dy: -padding)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = Self.rasterScale(for: imageFrame.size, preferredScale: scale)
        let image = UIGraphicsImageRenderer(size: imageFrame.size, format: format).image { context in
            context.cgContext.translateBy(x: -imageFrame.minX, y: -imageFrame.minY)
            draw()
        }
        sourceContentFrame = contentFrame
        selection.strokeColor = showsOutline ? UIColor.systemBlue.cgColor : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = parent.bounds
        layer.bounds = parent.bounds
        glyph.contents = image.cgImage
        glyph.contentsScale = image.scale
        parent.addSublayer(layer)
        CATransaction.commit()
        update(contentFrame: contentFrame)
    }

    func update(contentFrame: CGRect) {
        guard let source = sourceContentFrame else { return }
        let sx = contentFrame.width / source.width
        let sy = contentFrame.height / source.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.frame = contentFrame.insetBy(dx: -padding * sx, dy: -padding * sy)
        selection.path = UIBezierPath(roundedRect: contentFrame.insetBy(dx: -2, dy: -2),
            cornerRadius: 5).cgPath
        CATransaction.commit()
    }

    func end() {
        sourceContentFrame = nil
        layer.removeFromSuperlayer()
        glyph.contents = nil
        selection.path = nil
        guide.path = nil
    }

    func updateGuide(_ path: CGPath?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guide.path = path
        CATransaction.commit()
    }
}
#endif
