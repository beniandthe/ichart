import XCTest
@testable import iChart

final class ChordInkTheoryRoleContextTests: XCTestCase {
    func testLabelsRootAccidentalAndMinorQuality() {
        let context = roleContext(
            glyphs: [
                [glyph("D", confidence: 0.94)],
                [glyph("b", confidence: 0.82)],
                [glyph("-", confidence: 0.88)]
            ],
            bounds: [
                rootBounds(at: 0),
                highSuffixBounds(at: 42),
                suffixBounds(at: 64)
            ]
        )

        XCTAssertEqual(context.roles, [.rootBase, .rootAccidental, .quality])
        XCTAssertEqual(context.evidence[0].text, "D")
        XCTAssertEqual(context.evidence[1].text, "b")
    }

    func testLabelsNextBodyRootAsNewRootStart() {
        let context = roleContext(
            glyphs: [
                [glyph("D", confidence: 0.94)],
                [glyph("-", confidence: 0.88)],
                [glyph("7", confidence: 0.90)],
                [glyph("E", confidence: 0.93)],
                [glyph("-", confidence: 0.88)],
                [glyph("7", confidence: 0.90)]
            ],
            bounds: [
                rootBounds(at: 0),
                suffixBounds(at: 44),
                suffixBounds(at: 66),
                rootBounds(at: 118),
                suffixBounds(at: 162),
                suffixBounds(at: 184)
            ]
        )

        XCTAssertEqual(context.roles, [.rootBase, .quality, .chordExtension, .rootBase, .quality, .chordExtension])
    }

    func testSuffixOnlyFragmentsStayUnknown() {
        let context = roleContext(
            glyphs: [
                [glyph("7", confidence: 0.91)],
                [glyph("9", confidence: 0.89)],
                [glyph("s", confidence: 0.86)],
                [glyph("u", confidence: 0.86)],
                [glyph("s", confidence: 0.86)]
            ],
            bounds: [
                suffixBounds(at: 0),
                suffixBounds(at: 22),
                suffixBounds(at: 44),
                suffixBounds(at: 66),
                suffixBounds(at: 88)
            ]
        )

        XCTAssertEqual(context.roles, [.unknown, .unknown, .unknown, .unknown, .unknown])
    }

    func testLabelsDominantAlterationRoles() {
        let context = roleContext(
            glyphs: [
                [glyph("C", confidence: 0.95)],
                [glyph("7", confidence: 0.91)],
                [glyph("(", confidence: 0.88)],
                [glyph("b", confidence: 0.84)],
                [glyph("9", confidence: 0.90)],
                [glyph(")", confidence: 0.87)]
            ],
            bounds: [
                rootBounds(at: 0),
                suffixBounds(at: 44),
                suffixBounds(at: 66),
                suffixBounds(at: 88),
                suffixBounds(at: 110),
                suffixBounds(at: 132)
            ]
        )

        XCTAssertEqual(
            context.roles,
            [.rootBase, .chordExtension, .parenthesis, .alterationAccidental, .alterationDegree, .parenthesis]
        )
    }

    func testRejectsAlterationAccidentalWithoutExtensionContext() {
        let context = roleContext(
            glyphs: [
                [glyph("C", confidence: 0.95)],
                [glyph("(", confidence: 0.88)],
                [glyph("b", confidence: 0.84)],
                [glyph("9", confidence: 0.90)],
                [glyph(")", confidence: 0.87)]
            ],
            bounds: [
                rootBounds(at: 0),
                suffixBounds(at: 44),
                suffixBounds(at: 66),
                suffixBounds(at: 88),
                suffixBounds(at: 110)
            ]
        )

        XCTAssertEqual(context.roles, [.rootBase, .parenthesis, .unknown, .chordExtension, .parenthesis])
    }

    func testLabelsSlashBassRootInsideActiveChord() {
        let context = roleContext(
            glyphs: [
                [glyph("G", confidence: 0.95)],
                [glyph("/", confidence: 0.90)],
                [glyph("B", confidence: 0.92)]
            ],
            bounds: [
                rootBounds(at: 0),
                slashBounds(at: 46),
                rootBounds(at: 74)
            ]
        )

        XCTAssertEqual(context.roles, [.rootBase, .slashSeparator, .slashBassRoot])
        XCTAssertFalse(context.evidence[2].opensChordGroup)
    }

    func testLabelsSixNineSlashAsExtensionSeparator() {
        let context = roleContext(
            glyphs: [
                [glyph("C", confidence: 0.95)],
                [glyph("6", confidence: 0.92)],
                [glyph("/", confidence: 0.90)],
                [glyph("9", confidence: 0.92)]
            ],
            bounds: [
                rootBounds(at: 0),
                suffixBounds(at: 44),
                slashBounds(at: 66),
                suffixBounds(at: 88)
            ]
        )

        XCTAssertEqual(context.roles, [.rootBase, .chordExtension, .sixNineSeparator, .chordExtension])
    }

    func testLabelsChordRepeatAsSpecialNonRootedSymbol() {
        let context = roleContext(
            glyphs: [
                [glyph("•", confidence: 0.94)],
                [glyph("/", confidence: 0.94)],
                [glyph("•", confidence: 0.94)]
            ],
            bounds: [
                dotBounds(at: 0, y: 24),
                slashBounds(at: 18),
                dotBounds(at: 42, y: 38)
            ]
        )

        XCTAssertEqual(context.roles, [.chordRepeatDot, .chordRepeatSlash, .chordRepeatDot])
        XCTAssertFalse(context.evidence.contains(where: \.opensChordGroup))
    }

    func testExposesChordRepeatGlyphCandidatesOnlyForValidatedLayout() {
        let validContext = roleContext(
            glyphs: [
                [glyph("•", confidence: 0.94)],
                [glyph("/", confidence: 0.94)],
                [glyph("•", confidence: 0.94)]
            ],
            bounds: [
                dotBounds(at: 0, y: 24),
                slashBounds(at: 18),
                dotBounds(at: 42, y: 38)
            ]
        )
        let invalidContext = roleContext(
            glyphs: [
                [glyph("•", confidence: 0.94)],
                [glyph("/", confidence: 0.94)],
                [glyph("•", confidence: 0.94)]
            ],
            bounds: [
                dotBounds(at: 0, y: 24),
                slashBounds(at: 18),
                dotBounds(at: 20, y: 38)
            ]
        )

        XCTAssertEqual(validContext.chordRepeatGlyphCandidates?.map(\.text), ["•", "/", "•"])
        XCTAssertNil(invalidContext.chordRepeatGlyphCandidates)
    }

    private func roleContext(
        glyphs: [[GlyphCandidate]],
        bounds: [InkBounds]
    ) -> ChordInkTheoryRoleContext {
        ChordInkTheoryRoleContext(
            glyphCandidateGroups: glyphs,
            clusters: bounds.map { InkCluster(strokes: [], bounds: $0) }
        )
    }

    private func glyph(
        _ text: String,
        confidence: Double,
        source: RecognitionSource = .template
    ) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: source)
    }

    private func rootBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 10, maxX: x + 34, maxY: 60)
    }

    private func highSuffixBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 14, maxX: x + 14, maxY: 34)
    }

    private func suffixBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 24, maxX: x + 18, maxY: 56)
    }

    private func slashBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 14, maxX: x + 14, maxY: 58)
    }

    private func dotBounds(at x: Double, y: Double) -> InkBounds {
        InkBounds(minX: x, minY: y, maxX: x + 8, maxY: y + 8)
    }
}

private extension ChordInkTheoryRoleContext {
    var roles: [ChordInkTheoryRole] {
        evidence.map(\.primaryRole)
    }
}
