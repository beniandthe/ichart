#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetChordMoveOverlayTests: XCTestCase {
    func testManyMovesReuseOneGlyphRenderingAndPreserveChosenSize() throws {
        let overlay = LeadSheetChordMoveOverlayView(frame: .zero)
        let chord = layout(frame: CGRect(x: 120, y: 210, width: 94, height: 28))
        var renderCount = 0
        overlay.begin(chordLayout: chord, canvasBounds: CGRect(x: 0, y: 0, width: 900, height: 1200),
                      screenPointsPerDisplayedPoint: 1.5, screenScale: 2) { rendered in
            renderCount += 1
            XCTAssertEqual(rendered, chord)
            UIColor.black.setFill()
            UIBezierPath(rect: rendered.frame).fill()
        }
        let glyph = try layer("chordMove.glyph", in: overlay)
        let image = try XCTUnwrap(glyph.contents)
        let initialSize = glyph.bounds.size
        for offset in 1...120 {
            // A narrow incoming frame at the measure edge must not resize the
            // snapshotted glyph or its selection box.
            overlay.update(frame: CGRect(x: 120 + CGFloat(offset), y: 210 + CGFloat(offset), width: 1, height: 1),
                           positionPreview: nil)
        }
        XCTAssertEqual(renderCount, 1)
        XCTAssertTrue(overlay.isActive)
        XCTAssertEqual(glyph.bounds.size, initialSize)
        XCTAssertEqual(initialSize, CGSize(width: 98, height: 32))
        XCTAssertEqual(glyph.position, CGPoint(x: 240 + 47, y: 330 + 14))
        XCTAssertTrue((glyph.contents as AnyObject?) === (image as AnyObject))
        let selection = try shape("chordMove.selection", in: overlay)
        XCTAssertEqual(selection.path?.boundingBoxOfPath, CGRect(x: 234, y: 328, width: 106, height: 32))
        XCTAssertNil(glyph.animationKeys())
        XCTAssertNil(selection.animationKeys())
        XCTAssertFalse(overlay.isUserInteractionEnabled)
        XCTAssertFalse(overlay.point(inside: glyph.position, with: nil))
    }

    func testCanvasCoordinatesAndScreenSizedGuidesSurviveNonzeroBoundsAndZoom() throws {
        let canvasBounds = CGRect(x: -180, y: -90, width: 900, height: 1200)
        let parent = UIView(frame: CGRect(origin: .zero, size: canvasBounds.size))
        parent.bounds = canvasBounds
        let overlay = LeadSheetChordMoveOverlayView(frame: .zero)
        parent.addSubview(overlay)
        let chord = layout(frame: CGRect(x: -140, y: -60, width: 70, height: 24))
        overlay.begin(chordLayout: chord, canvasBounds: canvasBounds,
                      screenPointsPerDisplayedPoint: 2, screenScale: 3) { _ in }
        let reference = CGRect(x: -160, y: -70, width: 400, height: 40)
        let preview = LeadSheetChordMovePositionPreview(
            measureID: UUID(), referenceFrame: reference, guideFrame: reference,
            guideXs: [-148, -51, 46, 143], activeGuideX: 46,
            targetFraction: 0.515, targetX: 46
        )
        overlay.update(frame: CGRect(x: 46, y: 100, width: 70, height: 24), positionPreview: preview)
        XCTAssertEqual(overlay.frame, canvasBounds)
        XCTAssertEqual(overlay.bounds, canvasBounds)
        let glyph = try layer("chordMove.glyph", in: overlay)
        XCTAssertEqual(glyph.contentsScale, 6)
        XCTAssertEqual(overlay.layer.convert(glyph.position, to: parent.layer), CGPoint(x: 81, y: 112))
        let target = try shape("chordMove.targetGuide", in: overlay)
        let active = try shape("chordMove.activeGuide", in: overlay)
        XCTAssertEqual(target.path?.boundingBoxOfPath, CGRect(x: 46, y: -82, width: 0, height: 64))
        XCTAssertEqual(active.path?.boundingBoxOfPath, CGRect(x: 46, y: -80, width: 0, height: 60))
        XCTAssertEqual(target.lineWidth, 1)
        XCTAssertEqual(active.lineWidth, 0.85)
        XCTAssertEqual(active.lineDashPattern, [2.5, 1] as [NSNumber])
        let targetPoint = target.convert(CGPoint(x: 46, y: -82), to: parent.layer)
        XCTAssertEqual(targetPoint, CGPoint(x: 46, y: -82))
        XCTAssertNil(target.animationKeys())
        overlay.update(frame: chord.frame, positionPreview: nil)
        XCTAssertNil(target.path)
        XCTAssertNil(active.path)
    }

    func testEndClearsGlyphAndFeedbackAndAllowsAnotherDrag() throws {
        let overlay = LeadSheetChordMoveOverlayView(frame: .zero)
        let chord = layout(frame: CGRect(x: 50, y: 60, width: 30, height: 20))
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 1200)
        var renderCount = 0
        let render: (LeadSheetChordLayout) -> Void = { _ in renderCount += 1 }
        overlay.begin(chordLayout: chord, canvasBounds: bounds,
                      screenPointsPerDisplayedPoint: 1, screenScale: 2, drawChord: render)
        overlay.end()
        overlay.end()
        overlay.update(frame: chord.frame.offsetBy(dx: 300, dy: 0), positionPreview: nil)
        XCTAssertFalse(overlay.isActive)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertNil(try layer("chordMove.glyph", in: overlay).contents)
        for sublayer in overlay.layer.sublayers ?? [] {
            if let shape = sublayer as? CAShapeLayer { XCTAssertNil(shape.path) }
        }
        overlay.begin(chordLayout: chord, canvasBounds: bounds,
                      screenPointsPerDisplayedPoint: 1, screenScale: 2, drawChord: render)
        XCTAssertEqual(renderCount, 2)
        XCTAssertTrue(overlay.isActive)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertNotNil(try layer("chordMove.glyph", in: overlay).contents)
    }

    private func layout(frame: CGRect) -> LeadSheetChordLayout {
        LeadSheetChordLayout(id: UUID(), text: "Db7(b9)", frame: frame,
                             horizontalCompressionScale: 0.65,
                             snapGuideTarget: CGPoint(x: frame.minX, y: frame.maxY))
    }

    private func layer(_ name: String, in view: UIView) throws -> CALayer {
        try XCTUnwrap(view.layer.sublayers?.first { $0.name == name })
    }

    private func shape(_ name: String, in view: UIView) throws -> CAShapeLayer {
        try XCTUnwrap(try layer(name, in: view) as? CAShapeLayer)
    }
}
#endif
