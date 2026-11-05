import XCTest
@testable import iChart

final class DetachedBaseMajorTriangleTests: XCTestCase {
    func testCaretAndSeparateBaseShareGlyphAndClusterRecognitionInEitherOrderAndDirection() throws {
        let fixture = try InkFixtureLoader.load("BFlatMajor7SplitTriangleDevice02", file: #filePath)
        for baseFirst in [false, true] {
            for reverseCaret in [false, true] {
                for reverseBase in [false, true] {
                    let caret = stroke([(0, 10), (2.5, 5), (5, 0), (7.5, 5), (10, 10)], reversed: reverseCaret)
                    let base = stroke([(0, 10), (5, 10), (10, 10)], reversed: reverseBase)
                    let pair = baseFirst ? [base, caret] : [caret, base]
                    let context = "base first \(baseFirst), caret reversed \(reverseCaret), base reversed \(reverseBase)"
                    XCTAssertTrue(InkSplitMajorTriangleGeometry.matches(pair[0], pair[1]), context)
                    let glyphs = GestureTemplateRecognizer().rankedCandidates(
                        for: InkCluster(strokes: pair), templates: ChordGlyphTemplateLibrary.initialTemplates)
                    XCTAssertEqual(glyphs.first?.text, "△", context)

                    let source = Array(fixture.strokes.prefix(4)) + pair + Array(fixture.strokes.suffix(1))
                    let clusters = StrokeClusterer().indexedClusters(source)
                    XCTAssertEqual(clusters.map(\.originalIndexes), [[0, 1], [2, 3], [4, 5], [6]], context)
                    let result = ChordInkMaximumTrustRecognizer().recognize(strokes: source)
                    XCTAssertEqual(result.match?.displayText, "Bb△7", "\(context), \(result.rawCandidates.prefix(6))")
                    XCTAssertFalse(result.requiresTriangleQualityReview, context)
                    XCTAssertFalse(result.rawCandidates.prefix(3).contains("Bbø7"), context)
                }
            }
        }
    }

    func testSeparateBaseNeedsBothClosedFeetAndStraightLegs() {
        let caret = stroke([(0, 10), (2.5, 5), (5, 0), (7.5, 5), (10, 10)])
        let controls = [
            // A crossbar and a caret followed by a detached minus are distinct shapes.
            stroke([(2, 6), (5, 6), (8, 6)]),
            stroke([(0, 13), (5, 13), (10, 13)]),
            stroke([(11, 10), (16, 10), (21, 10)]),
            stroke([(3, 10), (5, 10), (7, 10)]),
            stroke([(0, 10), (5, 7), (10, 10)])
        ]
        for base in controls {
            XCTAssertFalse(InkSplitMajorTriangleGeometry.matches(caret, base))
            XCTAssertFalse(InkSplitMajorTriangleGeometry.matches(base, caret))
        }
        let curvedArch = stroke([(0, 10), (0, 4), (5, 0), (10, 4), (10, 10)])
        let base = stroke([(0, 10), (5, 10), (10, 10)])
        XCTAssertFalse(InkSplitMajorTriangleGeometry.matches(curvedArch, base))
    }

    func testSeparateBaseKeepsCapturedHalfDiminishedAndRootAReadings() throws {
        for name in ["BFlatHalfDiminished7Captured01", "BFlatHalfDiminished7Captured02", "A", "ACaptured01"] {
            let fixture = try InkFixtureLoader.load(name, file: #filePath)
            let result = ChordInkMaximumTrustRecognizer().recognize(strokes: fixture.strokes)
            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, name)
            XCTAssertFalse(result.requiresTriangleQualityReview, name)
        }
    }

    private func stroke(_ locations: [(Double, Double)], reversed: Bool = false) -> InkStroke {
        let ordered = reversed ? Array(locations.reversed()) : locations
        return InkStroke(points: ordered.map { x, y in
            InkPoint(x: 87 + x, y: 41 + y, timeOffset: nil)
        })
    }
}
