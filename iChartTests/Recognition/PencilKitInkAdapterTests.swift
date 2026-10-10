#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class PencilKitInkAdapterTests: XCTestCase {
    func testConvertsPencilKitDrawingToPureInkStrokes() throws {
        let firstCreationDate = Date(timeIntervalSinceReferenceDate: 1234.5)
        let secondCreationDate = Date(timeIntervalSinceReferenceDate: 1235.25)
        let drawing = PKDrawing(strokes: [
            stroke([
                CGPoint(x: 10, y: 12),
                CGPoint(x: 20, y: 28),
                CGPoint(x: 30, y: 44)
            ], creationDate: firstCreationDate),
            stroke([
                CGPoint(x: 50, y: 16),
                CGPoint(x: 62, y: 16)
            ], creationDate: secondCreationDate)
        ])

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let decodedInkStrokes = try PencilKitInkAdapter.inkStrokes(from: drawing.dataRepresentation())

        XCTAssertEqual(inkStrokes.count, 2)
        XCTAssertEqual(inkStrokes[0].points.map(\.x), [10, 20, 30])
        XCTAssertEqual(inkStrokes[0].points.map(\.y), [12, 28, 44])
        XCTAssertEqual(inkStrokes[0].bounds.minX, 10)
        XCTAssertEqual(inkStrokes[0].bounds.maxY, 44)
        XCTAssertEqual(inkStrokes[0].creationTimeOffset, 0)
        XCTAssertEqual(inkStrokes[0].timelineStartTimeOffset, 0)
        XCTAssertEqual(
            try XCTUnwrap(inkStrokes[0].timelineEndTimeOffset),
            0.02,
            accuracy: 0.000_001
        )
        XCTAssertEqual(inkStrokes[1].creationTimeOffset, 0.75)
        XCTAssertEqual(decodedInkStrokes.count, inkStrokes.count)
        XCTAssertEqual(decodedInkStrokes.map(\.creationTimeOffset), inkStrokes.map(\.creationTimeOffset))
    }

    func testExportsPencilKitDrawingDataAsReusableInkFixture() throws {
        let drawing = PKDrawing(strokes: [
            stroke([
                CGPoint(x: 10, y: 10),
                CGPoint(x: 20, y: 20),
                CGPoint(x: 30, y: 16)
            ])
        ])

        let json = try ChordInkFixtureExporter.fixtureJSONString(
            expectedDisplayText: "C",
            drawingData: drawing.dataRepresentation()
        )
        let decoded = try JSONDecoder().decode(InkFixtureDocument.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "C")
        XCTAssertEqual(decoded.expectedDisplayText, "C")
        XCTAssertEqual(decoded.expectedTopGlyphs, ["C"])
        XCTAssertEqual(decoded.strokes.count, 1)
    }

    func testAppliesPersistedPencilKitStrokeTransformToRecognitionPoints() throws {
        let sourceDrawing = PKDrawing(strokes: [
            stroke([
                CGPoint(x: 10, y: 20),
                CGPoint(x: 30, y: 40)
            ])
        ])
        let transform = CGAffineTransform(translationX: 8, y: -4)
            .scaledBy(x: 2, y: 0.5)
        let transformedDrawing = sourceDrawing.transformed(using: transform)

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: transformedDrawing)
        let decodedInkStrokes = try PencilKitInkAdapter.inkStrokes(
            from: transformedDrawing.dataRepresentation()
        )
        let expectedPoints = [CGPoint(x: 28, y: 6), CGPoint(x: 68, y: 16)]

        XCTAssertEqual(inkStrokes.count, 1)
        XCTAssertEqual(inkStrokes[0].points.map(\.x), expectedPoints.map { Double($0.x) })
        XCTAssertEqual(inkStrokes[0].points.map(\.y), expectedPoints.map { Double($0.y) })
        XCTAssertEqual(decodedInkStrokes, inkStrokes)
    }

    func testAdaptsOnlyVisibleBitmapEraserMaskRanges() throws {
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let maskedStroke = stroke(
            [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 20, y: 0),
                CGPoint(x: 30, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 50, y: 0)
            ],
            mask: mask
        )
        let drawing = PKDrawing(strokes: [maskedStroke])

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let decodedInkStrokes = try PencilKitInkAdapter.inkStrokes(
            from: drawing.dataRepresentation()
        )

        print(
            "bitmap_mask_ranges=\(maskedStroke.maskedPathRanges) "
                + "render_bounds=\(maskedStroke.renderBounds) "
                + "adapted_bounds=\(inkStrokes.map(\.bounds))"
        )
        XCTAssertEqual(maskedStroke.maskedPathRanges.count, 2)
        XCTAssertEqual(inkStrokes.count, 2)
        XCTAssertEqual(decodedInkStrokes, inkStrokes)
        XCTAssertLessThanOrEqual(inkStrokes[0].bounds.maxX, 16)
        XCTAssertGreaterThanOrEqual(inkStrokes[1].bounds.minX, 34)
    }

    func testAppliesTransformAfterSplittingVisibleBitmapMaskRanges() throws {
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let transform = CGAffineTransform(
            a: 1.5,
            b: 0,
            c: 0,
            d: 0.75,
            tx: 80,
            ty: 30
        )
        let sourceMaskedStroke = stroke(
            [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 20, y: 0),
                CGPoint(x: 30, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 50, y: 0)
            ],
            mask: mask
        )
        let drawing = PKDrawing(strokes: [sourceMaskedStroke]).transformed(using: transform)
        let maskedStroke = try XCTUnwrap(drawing.strokes.first)

        let fragments = PencilKitInkAdapter.visibleStrokeFragments(from: maskedStroke)
        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let decodedInkStrokes = try PencilKitInkAdapter.inkStrokes(
            from: drawing.dataRepresentation()
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments.allSatisfy { $0.mask == nil })
        XCTAssertTrue(fragments.allSatisfy { $0.transform == maskedStroke.transform })
        XCTAssertEqual(inkStrokes.count, 2)
        XCTAssertEqual(decodedInkStrokes, inkStrokes)
        XCTAssertLessThan(inkStrokes[0].bounds.maxX, 110)
        XCTAssertGreaterThan(inkStrokes[1].bounds.minX, 125)
        XCTAssertGreaterThanOrEqual(inkStrokes[0].bounds.minY, 30)
        XCTAssertGreaterThanOrEqual(inkStrokes[1].bounds.minY, 30)
    }

    func testFullyMaskedStrokeProducesNoRecognitionFragments() throws {
        let hiddenMask = UIBezierPath(
            rect: CGRect(x: 200, y: 200, width: 20, height: 20)
        )
        let hiddenStroke = stroke(
            [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 20, y: 20)
            ],
            mask: hiddenMask
        )
        let drawing = PKDrawing(strokes: [hiddenStroke])

        XCTAssertTrue(hiddenStroke.maskedPathRanges.isEmpty)
        XCTAssertTrue(PencilKitInkAdapter.visibleStrokeFragments(from: hiddenStroke).isEmpty)
        XCTAssertTrue(PencilKitInkAdapter.inkStrokes(from: drawing).isEmpty)
        XCTAssertTrue(
            try PencilKitInkAdapter.inkStrokes(from: drawing.dataRepresentation()).isEmpty
        )
    }

    func testFullyMaskedEarlierStrokeDoesNotShiftVisibleInkTimeline() throws {
        let hiddenMask = UIBezierPath(
            rect: CGRect(x: 200, y: 200, width: 20, height: 20)
        )
        let hiddenStroke = stroke(
            [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 10)
            ],
            creationDate: Date(timeIntervalSinceReferenceDate: 1_000),
            mask: hiddenMask
        )
        let visibleStroke = stroke(
            [
                CGPoint(x: 40, y: 20),
                CGPoint(x: 60, y: 30)
            ],
            creationDate: Date(timeIntervalSinceReferenceDate: 1_005)
        )
        let visibleOnlyDrawing = PKDrawing(strokes: [visibleStroke])
        let drawingWithHiddenEarlierStroke = PKDrawing(strokes: [hiddenStroke, visibleStroke])

        let visibleOnlyInk = PencilKitInkAdapter.inkStrokes(from: visibleOnlyDrawing)
        let inkWithHiddenEarlierStroke = PencilKitInkAdapter.inkStrokes(
            from: drawingWithHiddenEarlierStroke
        )

        XCTAssertEqual(visibleOnlyInk.count, 1)
        XCTAssertEqual(inkWithHiddenEarlierStroke, visibleOnlyInk)
        XCTAssertEqual(inkWithHiddenEarlierStroke.first?.creationTimeOffset, 0)
    }

    private func stroke(
        _ points: [CGPoint],
        creationDate: Date = Date(),
        transform: CGAffineTransform = .identity,
        mask: UIBezierPath? = nil
    ) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: creationDate)
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: path,
            transform: transform,
            mask: mask
        )
    }
}
#endif
