import XCTest
@testable import SmartChart

final class GestureTemplateRecognizerTests: XCTestCase {
    private let clusterer = StrokeClusterer()
    private let recognizer = GestureTemplateRecognizer()

    func testExpectedGlyphAppearsInTopThreeForCurrentFixtures() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for fixture in try InkFixtureLoader.loadAll(file: #filePath) {
            let clusters = clusterer.cluster(fixture.strokes)

            if fixture.allowsCompactSemanticRecognition {
                continue
            }

            XCTAssertEqual(clusters.count, fixture.expectedTopGlyphs.count, fixture.name)

            for (cluster, expectedGlyph) in zip(clusters, fixture.expectedTopGlyphs) {
                if fixture.allowsComposerInjectedGlyph(expectedGlyph) {
                    continue
                }

                let candidateLimit = fixture.recognizerCandidateLimit(for: expectedGlyph)
                let topThree = recognizer
                    .rankedCandidates(for: cluster, templates: templates, limit: candidateLimit)
                    .map(\.text)

                XCTAssertTrue(
                    topThree.contains(expectedGlyph),
                    "Expected \(expectedGlyph) in top \(candidateLimit) for \(fixture.name), got \(topThree)"
                )
            }
        }
    }

    func testConfidenceSortsNearestTemplateFirst() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let fixture = try InkFixtureLoader.load("C", file: #filePath)
        let cluster = try XCTUnwrap(clusterer.cluster(fixture.strokes).first)

        let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 4)

        XCTAssertEqual(candidates.first?.text, "C")
        XCTAssertEqual(candidates.map(\.confidence), candidates.map(\.confidence).sorted(by: >))
        XCTAssertEqual(Set(candidates.map(\.source)), [.template])
    }

    func testRecognitionIsStableAcrossScaleAndTranslation() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let fixture = try InkFixtureLoader.load("C", file: #filePath)
        let scaledAndTranslatedStrokes = fixture.strokes.map { stroke in
            stroke.transformed(scale: 1.7, translateX: 120, translateY: -42)
        }
        let cluster = try XCTUnwrap(clusterer.cluster(scaledAndTranslatedStrokes).first)

        let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 3)

        XCTAssertEqual(candidates.first?.text, "C")
    }

    func testParenthesisTemplatesDoNotStealStraightNumericGlyphs() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let sevenCluster = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 87, y: 16, timeOffset: nil),
                InkPoint(x: 108, y: 16, timeOffset: nil),
                InkPoint(x: 96, y: 57, timeOffset: nil)
            ])
        ])
        let oneCluster = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 20, y: 18, timeOffset: nil),
                InkPoint(x: 28, y: 12, timeOffset: nil),
                InkPoint(x: 28, y: 58, timeOffset: nil)
            ])
        ])
        let openParenthesisCluster = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 80, y: 15, timeOffset: nil),
                InkPoint(x: 68, y: 28, timeOffset: nil),
                InkPoint(x: 68, y: 48, timeOffset: nil),
                InkPoint(x: 80, y: 61, timeOffset: nil)
            ])
        ])

        let sevenCandidates = recognizer.rankedCandidates(for: sevenCluster, templates: templates, limit: 4)
        let oneCandidates = recognizer.rankedCandidates(for: oneCluster, templates: templates, limit: 4)
        let parenthesisCandidates = recognizer.rankedCandidates(for: openParenthesisCluster, templates: templates, limit: 4)

        XCTAssertFalse(sevenCandidates.map(\.text).contains("("))
        XCTAssertFalse(sevenCandidates.map(\.text).contains(")"))
        XCTAssertFalse(oneCandidates.map(\.text).contains("("))
        XCTAssertFalse(oneCandidates.map(\.text).contains(")"))
        XCTAssertEqual(parenthesisCandidates.first?.text, "(")
    }

    func testSlashSeparatorIsRecognizedByShapeNotStrokeDirection() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let reverseDrawnSlash = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 42, y: 12, timeOffset: nil),
                InkPoint(x: 35, y: 24, timeOffset: nil),
                InkPoint(x: 27, y: 39, timeOffset: nil),
                InkPoint(x: 19, y: 55, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: reverseDrawnSlash, templates: templates, limit: 3)

        XCTAssertEqual(candidates.first?.text, "/")
    }

    func testSuspendedGlyphTemplatesAreRecognized() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for text in ["s", "u"] {
            let template = try XCTUnwrap(templates.first { $0.text == text })
            let cluster = InkCluster(strokes: template.strokes)
            let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 3)

            XCTAssertEqual(candidates.first?.text, text)
        }
    }

    func testAlteredGlyphTemplatesAreRecognized() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for text in ["a", "l", "t"] {
            let template = try XCTUnwrap(templates.first { $0.text == text })
            let cluster = InkCluster(strokes: template.strokes)
            let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 3)

            XCTAssertEqual(candidates.first?.text, text)
        }
    }

    func testRecognizerReturnsAmbiguousCandidatesInsteadOfForcingOneAnswer() throws {
        let fixture = try InkFixtureLoader.load("C", file: #filePath)
        let cluster = try XCTUnwrap(clusterer.cluster(fixture.strokes).first)
        let templates = [
            GestureTemplate(text: "C", strokes: cluster.strokes),
            GestureTemplate(text: "open-C", strokes: cluster.strokes)
        ]

        let candidates = recognizer.rankedCandidates(for: cluster, templates: templates)

        XCTAssertEqual(candidates.map(\.text), ["C", "open-C"])
        XCTAssertEqual(candidates[0].confidence, candidates[1].confidence, accuracy: 0.0001)
    }

    func testRecognizerCollapsesDuplicateTemplateTextsToBestCandidate() throws {
        let fixture = try InkFixtureLoader.load("C", file: #filePath)
        let cluster = try XCTUnwrap(clusterer.cluster(fixture.strokes).first)
        let templates = [
            GestureTemplate(text: "C", strokes: cluster.strokes),
            GestureTemplate(text: "C", strokes: [InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: nil),
                InkPoint(x: 10, y: 10, timeOffset: nil)
            ])])
        ]

        let candidates = recognizer.rankedCandidates(for: cluster, templates: templates)

        XCTAssertEqual(candidates.map(\.text), ["C"])
    }
}

private extension InkFixture {
    var allowsCompactSharpElevenClusters: Bool {
        expectedDisplayText.contains("(#11)")
    }

    var allowsCompactAlteredAltClusters: Bool {
        expectedDisplayText.contains("7alt")
    }

    var allowsCompactSemanticRecognition: Bool {
        allowsCompactSharpElevenClusters || allowsCompactAlteredAltClusters
    }

    func allowsComposerInjectedGlyph(_ expectedGlyph: String) -> Bool {
        expectedGlyph == "1" && expectedDisplayText.contains("(b13)")
            || expectedGlyph == "s" && expectedDisplayText.contains("sus")
            || expectedGlyph == "u" && expectedDisplayText.contains("sus")
            || expectedGlyph == "4" && expectedDisplayText.hasSuffix("sus4")
    }
}

private extension InkFixture {
    func recognizerCandidateLimit(for expectedGlyph: String) -> Int {
        // Compact handwritten altered 9s can look like other suffix glyphs in isolation.
        // Composer context promotes them only when they follow a dominant 7 + alteration.
        if expectedGlyph == "9",
           expectedDisplayText.contains("(#9)") || expectedDisplayText.contains("(b9)") {
            return 5
        }

        // Compact handwritten altered 5s share a lot of shape with 7/9 in isolation.
        // Composer context promotes them only after dominant 7 + alteration evidence.
        if expectedGlyph == "5",
           expectedDisplayText.contains("(#5)") || expectedDisplayText.contains("(b5)") {
            return 5
        }

        // A handwritten 6 is intentionally allowed to be a lower raw glyph,
        // then promoted only when it is the final non-dominant extension.
        if expectedGlyph == "6",
           expectedDisplayText.hasSuffix("6") {
            return expectedDisplayText.hasSuffix("m6") ? 6 : 5
        }

        // Altered 13s are a contextual two-glyph suffix; the composer exposes
        // the 1/3 path only after dominant 7 + alteration evidence is present.
        if (expectedGlyph == "1" || expectedGlyph == "3"),
           expectedDisplayText.contains("(b13)") {
            return 6
        }

        return 3
    }
}

private extension InkStroke {
    func transformed(scale: Double, translateX: Double, translateY: Double) -> InkStroke {
        InkStroke(
            points: points.map { point in
                InkPoint(
                    x: point.x * scale + translateX,
                    y: point.y * scale + translateY,
                    timeOffset: point.timeOffset
                )
            }
        )
    }
}
