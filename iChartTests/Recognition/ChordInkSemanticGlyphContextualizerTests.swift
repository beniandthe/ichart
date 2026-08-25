import XCTest
@testable import iChart

final class ChordInkSemanticGlyphContextualizerTests: XCTestCase {
    private let contextualizer = ChordInkSemanticGlyphContextualizer()

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
