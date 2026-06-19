#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class PencilKitInkAdapterTests: XCTestCase {
    func testConvertsPencilKitDrawingToPureInkStrokes() throws {
        let drawing = PKDrawing(strokes: [
            stroke([
                CGPoint(x: 10, y: 12),
                CGPoint(x: 20, y: 28),
                CGPoint(x: 30, y: 44)
            ]),
            stroke([
                CGPoint(x: 50, y: 16),
                CGPoint(x: 62, y: 16)
            ])
        ])

        let inkStrokes = PencilKitInkAdapter.inkStrokes(from: drawing)
        let decodedInkStrokes = try PencilKitInkAdapter.inkStrokes(from: drawing.dataRepresentation())

        XCTAssertEqual(inkStrokes.count, 2)
        XCTAssertEqual(inkStrokes[0].points.map(\.x), [10, 20, 30])
        XCTAssertEqual(inkStrokes[0].points.map(\.y), [12, 28, 44])
        XCTAssertEqual(inkStrokes[0].bounds.minX, 10)
        XCTAssertEqual(inkStrokes[0].bounds.maxY, 44)
        XCTAssertEqual(decodedInkStrokes.count, inkStrokes.count)
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

    private func stroke(_ points: [CGPoint]) -> PKStroke {
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
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }
}
#endif
