import XCTest
@testable import iChart

final class ChordInkSemanticGlyphContextualizerTests: XCTestCase {
    private let contextualizer = ChordInkSemanticGlyphContextualizer()

    func testPromotesRootPositionCOverFlatLookalike() throws {
        let groups = [[
            glyph("b", confidence: 0.98, source: .heuristic),
            glyph("C", confidence: 0.95, source: .heuristic),
            glyph("G", confidence: 0.71, source: .template)
        ]]

        let contextualGroups = contextualizer.contextualizedGlyphCandidateGroups(
            groups,
            clusters: [
                cluster(minX: 0, minY: 0, maxX: 16, maxY: 24)
            ]
        )

        XCTAssertEqual(contextualGroups[0].first?.text, "C")
        XCTAssertGreaterThan(
            try XCTUnwrap(confidence("C", in: contextualGroups[0])),
            try XCTUnwrap(confidence("b", in: contextualGroups[0]))
        )
    }

    func testKeepsFlatAccidentalStrongAfterOwnedRoot() {
        let groups = [
            [glyph("C", confidence: 0.95, source: .heuristic)],
            [
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic)
            ]
        ]

        let contextualGroups = contextualizer.contextualizedGlyphCandidateGroups(
            groups,
            clusters: [
                cluster(minX: 0, minY: 0, maxX: 16, maxY: 24),
                cluster(minX: 20, minY: 0, maxX: 36, maxY: 24)
            ]
        )

        XCTAssertEqual(contextualGroups[1].first?.text, "b")
        XCTAssertEqual(confidence("b", in: contextualGroups[1]), 0.98)
    }

    func testRaisedFlatAndCappedSevenKeepTheirRolesAroundClosedTriangle() throws {
        func stroke(_ coordinates: [(Double, Double)]) -> InkStroke {
            InkStroke(points: coordinates.map { InkPoint(x: $0.0, y: $0.1, timeOffset: nil) })
        }

        let groups = [
            [glyph("B", confidence: 0.987, source: .heuristic)],
            [glyph("G", confidence: 0.97), glyph("b", confidence: 0.54)],
            [glyph("△", confidence: 0.99)],
            [glyph("3", confidence: 0.997), glyph("7", confidence: 0.98)]
        ]
        let root = cluster(minX: 0, minY: 20, maxX: 18, maxY: 54)
        let flat = InkCluster(strokes: [stroke([
            (25, 0), (24, 5), (24, 11), (25, 16), (25, 21), (30, 15),
            (34, 15), (36, 19), (33, 23), (27, 25), (25, 24)
        ])])
        let caret = stroke([(39, 18), (48, 2), (56, 18)])
        let base = stroke([(39, 18), (48, 18), (56, 18)])
        let seven = InkCluster(strokes: [stroke([
            (60, 1), (65, 1), (70, 1), (75, 2), (71, 7),
            (68, 12), (65, 17), (63, 22)
        ])])

        let closedTriangle = InkCluster(strokes: [caret, base])
        let adjusted = contextualizer.contextualizedGlyphCandidateGroups(
            groups, clusters: [root, flat, closedTriangle, seven]
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(confidence("b", in: adjusted[1])),
            try XCTUnwrap(confidence("G", in: adjusted[1]))
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(confidence("7", in: adjusted[3])),
            try XCTUnwrap(confidence("3", in: adjusted[3]))
        )

        let openCaret = InkCluster(strokes: [caret])
        let openAdjusted = contextualizer.contextualizedGlyphCandidateGroups(
            groups, clusters: [root, flat, openCaret, seven]
        )
        XCTAssertEqual(confidence("b", in: openAdjusted[1]), confidence("b", in: groups[1]))
        XCTAssertEqual(confidence("7", in: openAdjusted[3]), confidence("7", in: groups[3]))
    }

    func testDoesNotPromoteCOverCompetingHeuristicRoot() {
        let groups = [[
            glyph("b", confidence: 0.98, source: .heuristic),
            glyph("G", confidence: 0.97, source: .heuristic),
            glyph("C", confidence: 0.95, source: .heuristic)
        ]]

        let contextualGroups = contextualizer.contextualizedGlyphCandidateGroups(
            groups,
            clusters: [
                cluster(minX: 0, minY: 0, maxX: 16, maxY: 24)
            ]
        )

        XCTAssertEqual(contextualGroups[0].first?.text, "b")
        XCTAssertEqual(confidence("C", in: contextualGroups[0]), 0.95)
    }

    func testUsesRoleContextRootAccidentalPrefixForDominantSuspendedContext() {
        let groups = dominantSuspendedGroups(rootGroup: [glyph("D", confidence: 0.94)])
        let clusters = dominantSuspendedClusters()

        let contextualGroups = contextualizer.contextualizedGlyphCandidateGroups(
            groups,
            clusters: clusters
        )

        XCTAssertEqual(confidence("s", in: contextualGroups[3]), 0.78)
        XCTAssertEqual(confidence("u", in: contextualGroups[4]), 0.78)
        XCTAssertEqual(confidence("s", in: contextualGroups[5]), 0.78)
    }

    func testDoesNotApplySemanticBoostsWhenRoleContextRejectsWeakRootPrefix() {
        let groups = dominantSuspendedGroups(rootGroup: [
            glyph("6", confidence: 0.92),
            glyph("D", confidence: 0.55)
        ])
        let clusters = dominantSuspendedClusters()

        let contextualGroups = contextualizer.contextualizedGlyphCandidateGroups(
            groups,
            clusters: clusters
        )

        XCTAssertEqual(contextualGroups, groups)
    }

    private func dominantSuspendedGroups(rootGroup: [GlyphCandidate]) -> [[GlyphCandidate]] {
        [
            rootGroup,
            [glyph("b", confidence: 0.84)],
            [glyph("7", confidence: 0.90)],
            [glyph("s", confidence: 0.46)],
            [glyph("u", confidence: 0.46)],
            [glyph("s", confidence: 0.46)]
        ]
    }

    private func dominantSuspendedClusters() -> [InkCluster] {
        [
            cluster(minX: 0, minY: 10, maxX: 34, maxY: 60),
            cluster(minX: 42, minY: 14, maxX: 56, maxY: 34),
            cluster(minX: 68, minY: 12, maxX: 84, maxY: 50),
            cluster(minX: 104, minY: 42, maxX: 118, maxY: 66),
            cluster(minX: 126, minY: 42, maxX: 142, maxY: 62),
            cluster(minX: 150, minY: 42, maxX: 164, maxY: 66)
        ]
    }

    private func confidence(_ text: String, in group: [GlyphCandidate]) -> Double? {
        group.first { $0.text == text }?.confidence
    }

    private func glyph(
        _ text: String,
        confidence: Double,
        source: RecognitionSource = .template
    ) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: source)
    }

    private func cluster(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) -> InkCluster {
        let bounds = InkBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        return InkCluster(
            strokes: [
                InkStroke(
                    points: [
                        InkPoint(x: minX, y: minY, timeOffset: nil),
                        InkPoint(x: maxX, y: maxY, timeOffset: nil)
                    ],
                    bounds: bounds
                )
            ],
            bounds: bounds
        )
    }
}
