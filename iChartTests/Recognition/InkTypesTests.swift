import XCTest
@testable import iChart

final class InkTypesTests: XCTestCase {
    func testStrokeComputesBoundsWithoutNormalizingPointOrder() {
        let stroke = InkStroke(
            points: [
                InkPoint(x: 12, y: 4, timeOffset: 0.20),
                InkPoint(x: 3, y: 18, timeOffset: 0.10),
                InkPoint(x: 20, y: 9, timeOffset: 0.35)
            ]
        )

        XCTAssertEqual(stroke.points.map(\.x), [12, 3, 20])
        XCTAssertEqual(stroke.bounds.minX, 3)
        XCTAssertEqual(stroke.bounds.minY, 4)
        XCTAssertEqual(stroke.bounds.maxX, 20)
        XCTAssertEqual(stroke.bounds.maxY, 18)
    }

    func testClusterComputesBoundsAndTimingFromStrokes() {
        let firstStroke = InkStroke(
            points: [
                InkPoint(x: 4, y: 6, timeOffset: 0.4),
                InkPoint(x: 8, y: 9, timeOffset: 0.6)
            ]
        )
        let secondStroke = InkStroke(
            points: [
                InkPoint(x: 20, y: 2, timeOffset: 0.9),
                InkPoint(x: 24, y: 12, timeOffset: 1.2)
            ]
        )

        let cluster = InkCluster(strokes: [firstStroke, secondStroke])

        XCTAssertEqual(cluster.bounds, InkBounds(minX: 4, minY: 2, maxX: 24, maxY: 12))
        XCTAssertEqual(cluster.startTimeOffset, 0.4)
        XCTAssertEqual(cluster.endTimeOffset, 1.2)
    }

    func testInkStrokeDecodesFromJsonWithoutPencilKit() throws {
        let json = """
        {
          "points": [
            { "x": 1.0, "y": 2.0, "timeOffset": 0.1 },
            { "x": 5.0, "y": 8.0, "timeOffset": 0.4 }
          ],
          "bounds": {
            "minX": 1.0,
            "minY": 2.0,
            "maxX": 5.0,
            "maxY": 8.0
          }
        }
        """

        let stroke = try JSONDecoder().decode(InkStroke.self, from: Data(json.utf8))

        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(stroke.bounds, InkBounds(minX: 1, minY: 2, maxX: 5, maxY: 8))
    }
}
