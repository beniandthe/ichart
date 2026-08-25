import XCTest
@testable import iChart

final class ChordInkSequentialGrouperTests: XCTestCase {
    private let grouper = ChordInkSequentialGrouper()

    func testGroupsDMinorSevenEMinorSevenByRootStarts() throws {
        let strokes = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].rootText, "D")
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2, 3])
        XCTAssertEqual(groups[1].rootText, "E")
        XCTAssertEqual(groups[1].strokeIndices, [4, 5, 6, 7])
    }

    func testGroupsMajorTriangleAndMinorExtensionsByRootStarts() throws {
        let strokes = try glyphStrokes([
            ("C", 0), ("△", 0), ("7", 0),
            ("D", 118), ("-", 118), ("7", 118),
            ("E", 236), ("-", 236), ("9", 236)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.rootText), ["C", "D", "E"])
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2])
        XCTAssertEqual(groups[1].strokeIndices, [3, 4, 5, 6])
        XCTAssertEqual(groups[2].strokeIndices, [7, 8, 9, 10])
    }

    func testSuffixOnlyFragmentsDoNotCreateIndependentChordGroups() throws {
        let strokes = try glyphStrokes([
            ("-", 0), ("7", 0), ("9", 0)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertTrue(groups.isEmpty)
    }

    func testSoloVerticalBarlineLikeStrokeDoesNotCreateChordGroup() {
        let barline = InkStroke(points: [
            InkPoint(x: 24, y: 12, timeOffset: nil),
            InkPoint(x: 24, y: 62, timeOffset: nil)
        ])

        let groups = grouper.groups(for: indexed([barline]))

        XCTAssertTrue(groups.isEmpty)
    }

    func testTightAdjacentRootsSplitEvenWhenGapFallbackWouldKeepOneGroup() throws {
        let strokes = try glyphStrokes([
            ("C", 0),
            ("D", 55)
        ])

        let sequentialGroups = grouper.groups(for: indexed(strokes))
        let gapClusters = ChordInkBatchClusterer.clusters(for: strokes)

        XCTAssertEqual(gapClusters.count, 1)
        XCTAssertEqual(sequentialGroups.count, 2)
        XCTAssertEqual(sequentialGroups.map(\.rootText), ["C", "D"])
    }

    func testSlashBassRootDoesNotStartASecondGroup() throws {
        let strokes = try glyphStrokes([
            ("G", 0),
            ("/", 0),
            ("B", 78)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rootText, "G")
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2, 3])
    }

    func testAddingRightSideInkDoesNotChangeClosedGroupBoundaries() throws {
        let firstPass = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118)
        ])
        let secondPass = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118),
            ("F", 236), ("-", 236), ("7", 236)
        ])

        let firstGroups = grouper.groups(for: indexed(firstPass))
        let secondGroups = grouper.groups(for: indexed(secondPass))

        XCTAssertEqual(secondGroups.count, 3)
        XCTAssertEqual(Array(secondGroups.prefix(2)).map(\.strokeIndices), firstGroups.map(\.strokeIndices))
        XCTAssertEqual(Array(secondGroups.prefix(2)).map(\.rootText), firstGroups.map(\.rootText))
    }

    private func glyphStrokes(_ glyphs: [(String, Double)]) throws -> [InkStroke] {
        try glyphs.flatMap { text, offsetX in
            try templateStrokes(text, offsetX: offsetX)
        }
    }

    private func templateStrokes(_ text: String, offsetX: Double) throws -> [InkStroke] {
        let template = try XCTUnwrap(
            ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text },
            "Missing template \(text)"
        )

        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x + offsetX,
                        y: point.y,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func indexed(_ strokes: [InkStroke]) -> [(index: Int, stroke: InkStroke)] {
        strokes.enumerated().map { index, stroke in
            (index: index, stroke: stroke)
        }
    }
}
