#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetCachedDragPreviewTests: XCTestCase {
    func testLargeMultiPagePreviewStaysWithinTheDocumentRasterBudget() {
        let budget = CGFloat(16 * 1024 * 1024)
        for size in [
            CGSize(width: 140, height: 60),
            CGSize(width: 1200, height: 4800),
            CGSize(width: 1200, height: 100_000)
        ] {
            let scale = LeadSheetCachedDragPreview.rasterScale(for: size, preferredScale: 8)
            XCTAssertTrue(scale.isFinite)
            XCTAssertGreaterThan(scale, 0)
            XCTAssertLessThanOrEqual(scale, 4)
            XCTAssertLessThanOrEqual(size.width * scale * size.height * scale, budget + 0.01,
                "A multi-system ending must not allocate an unbounded full-resolution raster")
        }
        let large = LeadSheetCachedDragPreview.rasterScale(
            for: CGSize(width: 1200, height: 100_000), preferredScale: 4)
        XCTAssertLessThan(large, 1,
            "The raster budget must take precedence over a one-pixel-per-point floor")
    }

    func testNotationMarkerContentIncludesTheExpandedDrawnLabel() {
        for type in [RoadmapType.codaMarker, .segno] {
            let marker = LeadSheetRoadmapMarkerLayout(
                roadmapObjectID: UUID(), type: type, text: "",
                frame: CGRect(x: 123, y: 241, width: 60, height: 42),
                movementFrame: CGRect(x: 100, y: 200, width: 500, height: 100),
                anchorMeasureID: UUID(), scale: 1)
            let label = LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker)
            let source = LeadSheetCachedDragPreview.markerContentFrame(for: marker)
            XCTAssertTrue(source.contains(marker.frame))
            XCTAssertTrue(source.contains(label))
            XCTAssertEqual(source.minX, marker.frame.minX)
            XCTAssertGreaterThan(source.maxY, marker.frame.maxY + 3,
                "The marker label extends beyond the cache's ordinary three-point padding")
        }
    }

    func testCachedGlyphMovesAndScalesWithoutRecaptureAndClearsOnCancel() throws {
        let parent = CALayer()
        parent.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1500)
        let preview = LeadSheetCachedDragPreview(name: "test.preview")
        let source = CGRect(x: 100, y: 200, width: 120, height: 40)
        var captures = 0
        preview.begin(contentFrame: source, in: parent, scale: 2) {
            captures += 1
            UIColor.black.setFill()
            UIBezierPath(rect: source).fill()
        }
        let glyph = try XCTUnwrap(preview.layer.sublayers?.first { $0.name == "test.preview.glyph" })
        let selection = try XCTUnwrap(preview.layer.sublayers?.compactMap { $0 as? CAShapeLayer }
            .first { $0.path != nil })
        XCTAssertTrue(preview.isActive)
        XCTAssertNotNil(glyph.contents)
        XCTAssertEqual(glyph.frame, source.insetBy(dx: -3, dy: -3))

        let target = CGRect(x: 145, y: 210, width: 180, height: 60)
        for _ in 0..<40 { preview.update(contentFrame: target) }
        XCTAssertEqual(captures, 1, "Changed samples must reuse the captured glyph")
        XCTAssertEqual(glyph.frame, target.insetBy(dx: -4.5, dy: -4.5))
        XCTAssertEqual(try XCTUnwrap(selection.path).boundingBoxOfPath, target.insetBy(dx: -2, dy: -2))
        let guide = UIBezierPath()
        guide.move(to: source.origin)
        guide.addLine(to: target.origin)
        preview.updateGuide(guide.cgPath)

        preview.end()
        XCTAssertFalse(preview.isActive)
        XCTAssertNil(preview.layer.superlayer)
        XCTAssertNil(glyph.contents)
        XCTAssertTrue(preview.layer.sublayers?.compactMap { $0 as? CAShapeLayer }
            .allSatisfy { $0.path == nil } == true)
        preview.update(contentFrame: source)
        XCTAssertFalse(preview.isActive)

        preview.begin(contentFrame: target, in: parent, scale: 2) {
            captures += 1
            UIColor.black.setFill()
            UIBezierPath(rect: target).fill()
        }
        XCTAssertEqual(captures, 2)
        XCTAssertTrue(preview.layer.superlayer === parent)
        XCTAssertEqual(glyph.frame, target.insetBy(dx: -3, dy: -3))
    }
}
#endif
