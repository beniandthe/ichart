import XCTest
@testable import SmartChart

final class StrokeClustererTests: XCTestCase {
    private let clusterer = StrokeClusterer()

    func testClustersPlanAcceptanceFixturesIntoGlyphSizedGroups() throws {
        for fixture in try InkFixtureLoader.loadAll(file: #filePath) {
            guard let expectedClusterCount = fixture.expectedClusterCount else {
                continue
            }

            let clusters = clusterer.cluster(fixture.strokes)

            if fixture.allowsCompactSemanticClusters {
                XCTAssertGreaterThanOrEqual(
                    clusters.count,
                    max(1, expectedClusterCount - 2),
                    "Expected \(fixture.name) to keep enough clusters to resolve \(fixture.expectedTopGlyphs)"
                )
                XCTAssertLessThanOrEqual(
                    clusters.count,
                    expectedClusterCount + 1,
                    "Expected \(fixture.name) to avoid over-splitting \(fixture.expectedTopGlyphs)"
                )
                XCTAssertTrue(clusters.areSortedLeftToRight)
                continue
            }

            XCTAssertEqual(
                clusters.count,
                expectedClusterCount,
                "Expected \(fixture.name) to split into \(fixture.expectedTopGlyphs)"
            )
            XCTAssertEqual(clusters.count, fixture.expectedTopGlyphs.count)
            XCTAssertTrue(clusters.areSortedLeftToRight)
            let clusteredStrokeCount = clusters.reduce(0) { $0 + $1.strokes.count }
            if fixture.allowsDiscardingSemanticParenthesisWrappers {
                let discardedStrokeCount = fixture.strokes.count - clusteredStrokeCount
                XCTAssertGreaterThanOrEqual(discardedStrokeCount, 0)
                XCTAssertLessThanOrEqual(
                    discardedStrokeCount,
                    2,
                    "Only literal altered-extension wrapper strokes should be discarded for \(fixture.name)"
                )
            } else {
                XCTAssertEqual(clusteredStrokeCount, fixture.strokes.count)
            }
        }
    }

    func testClustererOutputIsDeterministicForReorderedInput() throws {
        let fixture = try InkFixtureLoader.load("Db7b9", file: #filePath)

        let forwardClusters = clusterer.cluster(fixture.strokes)
        let reversedClusters = clusterer.cluster(Array(fixture.strokes.reversed()))

        XCTAssertEqual(forwardClusters.map(\.bounds), reversedClusters.map(\.bounds))
        XCTAssertEqual(forwardClusters.map(\.strokes.count), reversedClusters.map(\.strokes.count))
    }

    func testSlashBassKeepsSlashAsSeparatorCluster() throws {
        for fixtureName in [
            "GSlashB",
            "GSlashBCaptured02",
            "FSlashA",
            "BFlatSlashDCaptured01",
            "DSlashFSharpCaptured02",
            "FSharpSlashASharpCaptured01"
        ] {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let clusters = clusterer.cluster(fixture.strokes)
            let slashIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "/"))

            XCTAssertEqual(clusters.count, fixture.expectedClusterCount, fixtureName)
            XCTAssertEqual(clusters.count, fixture.expectedTopGlyphs.count, fixtureName)
            XCTAssertEqual(clusters[slashIndex].strokes.count, 1, fixtureName)
            XCTAssertGreaterThan(clusters[slashIndex].bounds.height, clusters[slashIndex].bounds.width, fixtureName)
            XCTAssertTrue(clusters.areSortedLeftToRight, fixtureName)
        }
    }

    func testRootStemAndBodyCanMergeWhenTheyTouchAtTheEdge() throws {
        let fixture = try InkFixtureLoader.load("BSharpMinor11Captured01", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.first?.strokes.count, 2)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testRootCrossbarAndBodyCanMergeWhenCrossbarIsDrawnRightToLeft() throws {
        let fixture = try InkFixtureLoader.load("ASharpCaptured05", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.first?.strokes.count, 2)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testTallMinorMStaysSeparateFromFollowingSeven() throws {
        let fixture = try InkFixtureLoader.load("CSharpm7Captured02", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.suffix(2).map(\.strokes.count), [1, 1])
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testLongTimeGapPreventsMergingEvenWhenGeometryIsNear() {
        let firstStroke = InkStroke(
            points: [
                InkPoint(x: 10, y: 10, timeOffset: 0.0),
                InkPoint(x: 10, y: 50, timeOffset: 0.1)
            ]
        )
        let secondStroke = InkStroke(
            points: [
                InkPoint(x: 13, y: 10, timeOffset: 1.2),
                InkPoint(x: 13, y: 50, timeOffset: 1.3)
            ]
        )

        let clusters = clusterer.cluster([firstStroke, secondStroke])

        XCTAssertEqual(clusters.count, 2)
    }
}

private extension InkFixture {
    var allowsDiscardingSemanticParenthesisWrappers: Bool {
        expectedDisplayText.contains("(#9)")
            || expectedDisplayText.contains("(b9)")
            || expectedDisplayText.contains("(#5)")
            || expectedDisplayText.contains("(b5)")
            || expectedDisplayText.contains("(b13)")
    }

    var allowsCompactSharpElevenClusters: Bool {
        expectedDisplayText.contains("(#11)")
    }

    var allowsCompactAlteredAltClusters: Bool {
        expectedDisplayText.contains("7alt")
    }

    var allowsCompactSemanticClusters: Bool {
        allowsCompactSharpElevenClusters || allowsCompactAlteredAltClusters
    }
}

private extension [InkCluster] {
    var areSortedLeftToRight: Bool {
        zip(self, dropFirst()).allSatisfy { lhs, rhs in
            lhs.bounds.minX <= rhs.bounds.minX
        }
    }
}
