import XCTest
@testable import iChart

final class StrokeClustererTests: XCTestCase {
    private let clusterer = StrokeClusterer()

    func testClustersDefaultRegressionFixturesIntoGlyphSizedGroups() throws {
        try assertClustersIntoExpectedGlyphGroups(
            fixtures: InkFixtureLoader.loadDefaultRegressionFixtures(file: #filePath)
        )
    }

    func testClustersFullInkFixtureArchiveWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to run the full ink fixture archive."
        )
        try assertClustersIntoExpectedGlyphGroups(fixtures: InkFixtureLoader.loadAll(file: #filePath))
    }

    private func assertClustersIntoExpectedGlyphGroups(fixtures: [InkFixture]) throws {
        for fixture in fixtures {
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

    func testAttachedFlatModifierSplitsFromRootConstruction() {
        let stem = InkStroke(points: [
            InkPoint(x: 10, y: 20, timeOffset: 0.0),
            InkPoint(x: 10, y: 31, timeOffset: 0.03),
            InkPoint(x: 10, y: 42, timeOffset: 0.06),
            InkPoint(x: 10, y: 53, timeOffset: 0.09)
        ])
        let rootBody = InkStroke(points: [
            InkPoint(x: 11, y: 22, timeOffset: 0.12),
            InkPoint(x: 17, y: 22, timeOffset: 0.15),
            InkPoint(x: 23, y: 26, timeOffset: 0.18),
            InkPoint(x: 27, y: 33, timeOffset: 0.21),
            InkPoint(x: 27, y: 40, timeOffset: 0.24),
            InkPoint(x: 23, y: 48, timeOffset: 0.27),
            InkPoint(x: 16, y: 53, timeOffset: 0.30),
            InkPoint(x: 11, y: 53, timeOffset: 0.33)
        ])
        let flatModifier = InkStroke(points: [
            InkPoint(x: 25, y: 10, timeOffset: 0.36),
            InkPoint(x: 25, y: 18, timeOffset: 0.39),
            InkPoint(x: 25, y: 26, timeOffset: 0.42),
            InkPoint(x: 29, y: 22, timeOffset: 0.45),
            InkPoint(x: 35, y: 20, timeOffset: 0.48),
            InkPoint(x: 38, y: 24, timeOffset: 0.51),
            InkPoint(x: 34, y: 30, timeOffset: 0.54),
            InkPoint(x: 27, y: 32, timeOffset: 0.57)
        ])

        let clusters = clusterer.cluster([stem, rootBody, flatModifier])

        XCTAssertEqual(clusters.map(\.strokes.count), [2, 1])
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
