#if canImport(UIKit)
import UIKit

/// A transient snapshot of the moving chord. The caller owns targeting and
/// persistence; updates here move only the glyph and its placement feedback.
final class LeadSheetChordMoveOverlayView: UIView {
    private let glyph = CALayer()
    private let selection = CAShapeLayer()
    private let guideField = CAShapeLayer()
    private let inactiveGuides = CAShapeLayer()
    private let activeGuide = CAShapeLayer()
    private let targetGuide = CAShapeLayer()
    private var sourceFrame: CGRect?
    private var screenPointsPerDisplayedPoint: CGFloat = 1
    private let glyphPadding: CGFloat = 2

    private(set) var isActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// All geometry, including canvasBounds, uses the canvas's coordinates.
    /// drawChord receives the unchanged layout inside a UIKit image context,
    /// retaining the renderer's typography, compression and ink color.
    func begin(
        chordLayout: LeadSheetChordLayout,
        canvasBounds: CGRect,
        screenPointsPerDisplayedPoint: CGFloat,
        screenScale: CGFloat,
        drawChord: (LeadSheetChordLayout) -> Void
    ) {
        end()
        let imageFrame = chordLayout.frame.insetBy(dx: -glyphPadding, dy: -glyphPadding)
        guard imageFrame.width.isFinite, imageFrame.height.isFinite,
              imageFrame.width > 0, imageFrame.height > 0 else { return }
        let displayScale = screenPointsPerDisplayedPoint.isFinite && screenPointsPerDisplayedPoint > 0
            ? screenPointsPerDisplayedPoint : 1
        let resolvedScreenScale = screenScale.isFinite && screenScale > 0 ? screenScale : 1
        self.screenPointsPerDisplayedPoint = displayScale
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = min(8, max(1, resolvedScreenScale * displayScale))
        let image = UIGraphicsImageRenderer(size: imageFrame.size, format: format).image { context in
            context.cgContext.translateBy(x: -imageFrame.minX, y: -imageFrame.minY)
            drawChord(chordLayout)
        }

        withoutAnimations {
            // Matching origins keeps paths and positions in canvas coordinates,
            // even when the parent's bounds do not start at zero.
            frame = canvasBounds
            bounds = canvasBounds
            for shape in shapeLayers {
                shape.frame = canvasBounds
                shape.bounds = canvasBounds
                shape.contentsScale = image.scale
            }
            glyph.bounds = CGRect(origin: .zero, size: imageFrame.size)
            glyph.contents = image.cgImage
            glyph.contentsScale = image.scale
            sourceFrame = chordLayout.frame
            isActive = true
            isHidden = false
            update(frame: chordLayout.frame, positionPreview: nil)
        }
    }

    /// Only the incoming origin moves the glyph. Its selected size is frozen
    /// for the drag, including near a measure edge.
    func update(frame: CGRect, positionPreview: LeadSheetChordMovePositionPreview?) {
        guard let sourceFrame, isActive else { return }
        let displayFrame = CGRect(origin: frame.origin, size: sourceFrame.size)
        withoutAnimations {
            glyph.position = CGPoint(x: displayFrame.midX, y: displayFrame.midY)
            selection.path = UIBezierPath(
                roundedRect: displayFrame.insetBy(dx: -6, dy: -2), cornerRadius: 5
            ).cgPath
            selection.lineWidth = 1.4 / screenPointsPerDisplayedPoint
            updateGuides(positionPreview)
        }
    }

    /// Reuse this for commit, cancellation, and removal from the canvas.
    func end() {
        withoutAnimations {
            isActive = false
            isHidden = true
            sourceFrame = nil
            glyph.contents = nil
            for shape in shapeLayers { shape.path = nil }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }

    private var shapeLayers: [CAShapeLayer] {
        [guideField, inactiveGuides, activeGuide, targetGuide, selection]
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
        clipsToBounds = false
        for (name, shape) in [
            ("chordMove.guideField", guideField),
            ("chordMove.inactiveGuides", inactiveGuides),
            ("chordMove.activeGuide", activeGuide),
            ("chordMove.targetGuide", targetGuide),
            ("chordMove.selection", selection)
        ] {
            shape.name = name
            shape.fillColor = nil
            layer.addSublayer(shape)
        }
        selection.fillColor = UIColor(red: 0.88, green: 0.93, blue: 1, alpha: 0.30).cgColor
        selection.strokeColor = UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.92).cgColor
        targetGuide.lineCap = .round
        glyph.name = "chordMove.glyph"
        layer.addSublayer(glyph)
    }

    private func updateGuides(_ preview: LeadSheetChordMovePositionPreview?) {
        guard let preview else {
            for shape in [guideField, inactiveGuides, activeGuide, targetGuide] { shape.path = nil }
            return
        }
        let scale = screenPointsPerDisplayedPoint
        let isAligned = preview.activeGuideX != nil
        let color = isAligned
            ? UIColor(red: 0.02, green: 0.62, blue: 0.28, alpha: 1)
            : UIColor(red: 0.06, green: 0.31, blue: 0.94, alpha: 1)
        let fieldFrame = preview.guideFrame.insetBy(dx: -4, dy: -8)
        guideField.path = UIBezierPath(roundedRect: fieldFrame, cornerRadius: 5).cgPath
        guideField.fillColor = color.withAlphaComponent(isAligned ? 0.08 : 0.06).cgColor
        guideField.strokeColor = color.withAlphaComponent(isAligned ? 0.34 : 0.22).cgColor
        guideField.lineWidth = 1 / scale

        let inactivePath = CGMutablePath()
        let activePath = CGMutablePath()
        for x in preview.guideXs {
            let isActiveGuide = preview.activeGuideX.map { abs($0 - x) < 0.5 } ?? false
            let path = isActiveGuide ? activePath : inactivePath
            path.move(to: CGPoint(x: x, y: fieldFrame.minY - 2))
            path.addLine(to: CGPoint(x: x, y: fieldFrame.maxY + 2))
        }
        inactiveGuides.path = inactivePath
        inactiveGuides.strokeColor = UIColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.24).cgColor
        inactiveGuides.lineWidth = 0.9 / scale
        inactiveGuides.lineDashPattern = [NSNumber(value: Double(3 / scale)), NSNumber(value: Double(6 / scale))]
        activeGuide.path = activePath
        activeGuide.strokeColor = color.withAlphaComponent(0.82).cgColor
        activeGuide.lineWidth = 1.7 / scale
        activeGuide.lineDashPattern = [NSNumber(value: Double(5 / scale)), NSNumber(value: Double(2 / scale))]
        let targetPath = CGMutablePath()
        targetPath.move(to: CGPoint(x: preview.targetX, y: fieldFrame.minY - 4))
        targetPath.addLine(to: CGPoint(x: preview.targetX, y: fieldFrame.maxY + 4))
        targetGuide.path = targetPath
        targetGuide.strokeColor = color.withAlphaComponent(isAligned ? 0.88 : 0.60).cgColor
        targetGuide.lineWidth = (isAligned ? 2 : 1.3) / scale
    }

    private func withoutAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}
#endif
