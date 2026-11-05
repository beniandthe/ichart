import XCTest
@testable import iChart

final class MajorTriangleFallbackPolicyTests: XCTestCase {
    func testPlausibleWeakTriangleCannotManufactureHalfDiminishedFromLetterAndSeven() {
        let policy = ChordInkCandidateSelectionPolicy(maxAlternativesPerCluster: 3)
        for confidence in [0.42, 0.462, 0.50, 0.549] {
            let columns = qualityColumns(triangleConfidence: confidence)
            let selected = policy.selectedGlyphCandidates(forColumnAt: 1, in: columns)

            XCTAssertFalse(selected.contains { $0.text == "ø" }, "triangle confidence \(confidence)")
            XCTAssertTrue(selected.contains { $0.text == "△" }, "Keep the actual triangle alternative")
            let displayTexts = ChordInkCandidateComposer().compose(glyphCandidates: columns)
                .compactMap { ChordRecognitionCompendium.match($0.text)?.displayText }
            XCTAssertFalse(displayTexts.contains("Cø7"))
            XCTAssertTrue(displayTexts.contains("C△7"))
        }
    }

    func testExplicitHalfDiminishedEvidenceKeepsItsQualityDespiteWeakTriangleAlternative() {
        let policy = ChordInkCandidateSelectionPolicy(maxAlternativesPerCluster: 3)
        var columns = qualityColumns(triangleConfidence: 0.462)
        columns[1].insert(glyph("ø", confidence: 0.95), at: 0)
        let selected = policy.selectedGlyphCandidates(forColumnAt: 1, in: columns)

        XCTAssertEqual(selected.first?.text, "ø")
        XCTAssertEqual(selected.first?.confidence, 0.95)
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates:
            ChordInkCandidateComposer().compose(glyphCandidates: columns).map(\.text))?.displayText, "Cø7")
    }

    func testActualTriangleOutsideOrdinaryGlyphBeamRemainsAvailableWhenRoundFallbackIsVetoed() {
        let triangle = glyph("△", confidence: 0.462)
        let columns = [[glyph("C", confidence: 0.99)],
            [glyph("D", confidence: 0.639), glyph("G", confidence: 0.60), glyph("B", confidence: 0.56), triangle],
            [glyph("7", confidence: 0.99)]]
        let selected = ChordInkCandidateSelectionPolicy(maxAlternativesPerCluster: 3)
            .selectedGlyphCandidates(forColumnAt: 1, in: columns)

        XCTAssertTrue(selected.contains(triangle), "Retain actual low-ranked evidence without changing its confidence or source")
        XCTAssertFalse(selected.contains { $0.text == "ø" && $0.source == .composer })
        let displayTexts = ChordInkCandidateComposer().compose(glyphCandidates: columns)
            .compactMap { ChordRecognitionCompendium.match($0.text)?.displayText }
        XCTAssertTrue(displayTexts.contains("C△7"))
        XCTAssertFalse(displayTexts.contains("Cø7"))
    }

    func testRoundOnlyQualityRecoveryAndDominantRootRemainAvailable() {
        let composer = ChordInkCandidateComposer()
        let roundColumns = [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.90)],
            [glyph("B", confidence: 0.74), glyph("G", confidence: 0.70), glyph("3", confidence: 0.68)],
            [glyph("7", confidence: 0.88)]
        ]
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates:
            composer.compose(glyphCandidates: roundColumns).map(\.text))?.displayText, "Bbø7")
        let dominantColumns = [[glyph("D", confidence: 0.99)], [glyph("7", confidence: 0.99)]]
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates:
            composer.compose(glyphCandidates: dominantColumns).map(\.text))?.displayText, "D7")
    }

    func testRetracedBaseTriangleCannotAlsoOwnHalfDiminishedHeuristic() {
        let recognizer = GestureTemplateRecognizer()
        let left = [(5.0, 0.0), (2.5, 4.0), (0.0, 8.0)]
        var right = [(5.0, 0.0), (8.5, 4.0), (12.0, 8.0)]
        for pass in 0..<5 {
            let xs = pass.isMultiple(of: 2) ? [9.0, 6.0, 3.0, 0.0] : [3.0, 6.0, 9.0, 12.0]
            right += xs.map { ($0, 8.0) }
        }
        for scale in [1.0, 1.1, 1.3] {
            for leftReversed in [false, true] {
                for rightReversed in [false, true] {
                    let lhs = stroke(left, scale: scale, reversed: leftReversed)
                    let rhs = stroke(right, scale: scale, reversed: rightReversed)
                    for pair in [[lhs, rhs], [rhs, lhs]] {
                        XCTAssertTrue(InkSplitMajorTriangleGeometry.matches(pair[0], pair[1]))
                        let candidates = recognizer.rankedCandidates(for: InkCluster(strokes: pair), templates: [])
                        XCTAssertEqual(candidates.first?.text, "△")
                        XCTAssertFalse(candidates.contains { $0.text == "ø" && $0.source == .heuristic })
                    }
                }
            }
        }
    }

    func testCircleAndSlashKeepOwnedHalfDiminishedHeuristicInEitherStrokeOrderAndDirection() {
        let circle = (0...32).map { step -> (Double, Double) in
            let angle = Double(step) * 2 * .pi / 32
            return (6 + 6 * cos(angle), 6 + 6 * sin(angle))
        }
        let slash = [(-2.0, 12.0), (6.0, 6.0), (14.0, 0.0)]
        let recognizer = GestureTemplateRecognizer()
        for reverseCircle in [false, true] {
            for reverseSlash in [false, true] {
                let loop = stroke(circle, reversed: reverseCircle)
                let diagonal = stroke(slash, reversed: reverseSlash)
                for pair in [[loop, diagonal], [diagonal, loop]] {
                    XCTAssertFalse(InkSplitMajorTriangleGeometry.matches(pair[0], pair[1]))
                    let candidates = recognizer.rankedCandidates(for: InkCluster(strokes: pair), templates: [])
                    XCTAssertTrue(candidates.contains { $0.text == "ø" && $0.source == .heuristic })
                    XCTAssertFalse(candidates.contains { $0.text == "△" && $0.source == .heuristic })
                }
            }
        }
    }

    func testCapturedHalfDiminishedControlsRetainTheirExpectedChords() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
            .filter { $0.expectedDisplayText.contains("ø") }
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let result = ChordInkMaximumTrustRecognizer().recognize(strokes: fixture.strokes)
            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
        }
    }

    private func qualityColumns(triangleConfidence: Double) -> [[GlyphCandidate]] {
        [[glyph("C", confidence: 0.99)],
         [glyph("D", confidence: 0.639), glyph("△", confidence: triangleConfidence), glyph("B", confidence: 0.40)],
         [glyph("7", confidence: 0.99)]]
    }

    private func glyph(_ text: String, confidence: Double) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: .template)
    }

    private func stroke(_ points: [(Double, Double)], scale: Double = 1, reversed: Bool = false) -> InkStroke {
        let ordered = reversed ? Array(points.reversed()) : points
        return InkStroke(points: ordered.map { InkPoint(x: 80 + $0.0 * scale, y: 40 + $0.1 * scale) })
    }
}
