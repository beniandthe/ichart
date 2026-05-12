import XCTest
@testable import SmartChart

final class ChordInkCandidateComposerTests: XCTestCase {
    private let composer = ChordInkCandidateComposer()

    func testComposesBbAheadOfInvalidEightFlatLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [
                glyph("8", confidence: 0.92),
                glyph("B", confidence: 0.86)
            ],
            [
                glyph("b", confidence: 0.84)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "Bb")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bb")
    }

    func testComposesSharpAccidentalWithRootWhenNearbyClusterIsPresent() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.93)],
            [glyph("#", confidence: 0.72)]
        ])

        XCTAssertEqual(candidates.first?.text, "F#")
    }

    func testComposesMinorAliasesToStandardMinorCandidate() throws {
        let dashCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.94)],
            [glyph("-", confidence: 0.86)]
        ])
        let mCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.94)],
            [glyph("m", confidence: 0.86)]
        ])

        XCTAssertEqual(dashCandidates.first?.text, "C-")
        XCTAssertEqual(mCandidates.first?.text, "C-")
        XCTAssertEqual(try ChordSymbolParser.parse(dashCandidates[0].text).displayText, "C-")
        XCTAssertEqual(try ChordSymbolParser.parse(mCandidates[0].text).displayText, "C-")
    }

    func testComposesMinorMExtensionToStandardDashMinorExtension() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("m", confidence: 0.86)],
            [glyph("7", confidence: 0.89)]
        ])

        XCTAssertEqual(candidates.first?.text, "C-7")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "C-7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "C-7")
    }

    func testComposesMinorNinthEleventhAndThirteenthToStandardDashMinorExtensions() throws {
        let dashMinorNinthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("-", confidence: 0.88)],
            [glyph("9", confidence: 0.89)]
        ])
        let mMinorNinthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("m", confidence: 0.88)],
            [glyph("9", confidence: 0.89)]
        ])
        let mMinorEleventhCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("m", confidence: 0.88)],
            [glyph("1", confidence: 0.90)],
            [glyph("1", confidence: 0.89)]
        ])
        let accidentalMinorThirteenthCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.96)],
            [glyph("b", confidence: 0.92)],
            [glyph("m", confidence: 0.88)],
            [glyph("1", confidence: 0.90)],
            [glyph("3", confidence: 0.90)]
        ])

        XCTAssertEqual(dashMinorNinthCandidates.first?.text, "C-9")
        XCTAssertEqual(mMinorNinthCandidates.first?.text, "C-9")
        XCTAssertEqual(mMinorEleventhCandidates.first?.text, "C-11")
        XCTAssertEqual(accidentalMinorThirteenthCandidates.first?.text, "Bb-13")
        XCTAssertEqual(try ChordSymbolParser.parse(dashMinorNinthCandidates[0].text).displayText, "C-9")
        XCTAssertEqual(try ChordSymbolParser.parse(mMinorNinthCandidates[0].text).displayText, "C-9")
        XCTAssertEqual(try ChordSymbolParser.parse(mMinorEleventhCandidates[0].text).displayText, "C-11")
        XCTAssertEqual(try ChordSymbolParser.parse(accidentalMinorThirteenthCandidates[0].text).displayText, "Bb-13")
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: accidentalMinorThirteenthCandidates.map(\.text))?.displayText,
            "Bb-13"
        )
    }

    func testComposesDominantSeventhAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("7", confidence: 0.89)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("7", confidence: 0.89)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("7", confidence: 0.89)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "C7")
        XCTAssertEqual(sharpCandidates.first?.text, "F#7")
        XCTAssertEqual(flatCandidates.first?.text, "Bb7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "C7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bb7")
    }

    func testComposesSixthAndNonAlteredDominantExtensionsAfterRootAndAccidental() throws {
        let naturalSixthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("6", confidence: 0.89)]
        ])
        let naturalNinthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("9", confidence: 0.89)]
        ])
        let sharpEleventhCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("1", confidence: 0.88)],
            [glyph("1", confidence: 0.87)]
        ])
        let flatThirteenthCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("1", confidence: 0.88)],
            [glyph("3", confidence: 0.87)]
        ])

        XCTAssertEqual(naturalSixthCandidates.first?.text, "C6")
        XCTAssertEqual(naturalNinthCandidates.first?.text, "C9")
        XCTAssertEqual(sharpEleventhCandidates.first?.text, "F#11")
        XCTAssertEqual(flatThirteenthCandidates.first?.text, "Bb13")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalSixthCandidates.map(\.text))?.displayText, "C6")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalNinthCandidates.map(\.text))?.displayText, "C9")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpEleventhCandidates.map(\.text))?.displayText, "F#11")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatThirteenthCandidates.map(\.text))?.displayText, "Bb13")
    }

    func testComposesSixthWhenFinalSixIsBelowTopThree() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.97)],
            [
                glyph("b", confidence: 0.98),
                glyph("G", confidence: 0.97),
                glyph("5", confidence: 0.62),
                glyph("6", confidence: 0.57)
            ],
            [
                glyph("b", confidence: 0.98),
                glyph("C", confidence: 0.95),
                glyph("5", confidence: 0.62),
                glyph("6", confidence: 0.59)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bb6")
    }

    func testNaturalThirteenthBeatsWeakAccidentalSeventhLookalike() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [
                glyph("1", confidence: 0.99),
                glyph("b", confidence: 0.59)
            ],
            [
                glyph("3", confidence: 0.99),
                glyph("7", confidence: 0.98)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "C13")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "C13")
    }

    func testLowConfidenceSlashDoesNotBeatMinorSeventhCandidate() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.97)],
            [glyph("b", confidence: 0.98)],
            [
                glyph("-", confidence: 0.48),
                glyph("/", confidence: 0.38)
            ],
            [
                glyph("C", confidence: 0.95),
                glyph("7", confidence: 0.45)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bb-7")
    }

    func testComposesExtensionAlterationAndSlashBassCandidates() throws {
        let db7b9Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("b", confidence: 0.82)],
            [glyph("9", confidence: 0.88)]
        ])
        let parenthesizedDb7b9Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("(", confidence: 0.80)],
            [glyph("b", confidence: 0.82)],
            [glyph("9", confidence: 0.88)],
            [glyph(")", confidence: 0.80)]
        ])
        let db7Sharp9Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("#", confidence: 0.82)],
            [glyph("9", confidence: 0.88)]
        ])
        let parenthesizedDb7Sharp9Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("(", confidence: 0.80)],
            [glyph("#", confidence: 0.82)],
            [glyph("9", confidence: 0.88)],
            [glyph(")", confidence: 0.80)]
        ])
        let db7Flat5Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("b", confidence: 0.82)],
            [glyph("5", confidence: 0.88)]
        ])
        let db7Flat13Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("b", confidence: 0.82)],
            [glyph("1", confidence: 0.88)],
            [glyph("3", confidence: 0.72)]
        ])
        let db7Sharp11Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("#", confidence: 0.82)],
            [glyph("1", confidence: 0.88)],
            [glyph("1", confidence: 0.72)]
        ])
        let parenthesizedDb7Sharp5Candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("(", confidence: 0.80)],
            [glyph("#", confidence: 0.82)],
            [glyph("5", confidence: 0.88)],
            [glyph(")", confidence: 0.80)]
        ])
        let slashCandidates = composer.compose(glyphCandidates: [
            [glyph("G", confidence: 0.94)],
            [glyph("/", confidence: 0.82)],
            [glyph("B", confidence: 0.90)]
        ])

        XCTAssertEqual(db7b9Candidates.first?.text, "Db7b9")
        XCTAssertEqual(try ChordSymbolParser.parse(db7b9Candidates[0].text).displayText, "Db7(b9)")
        XCTAssertEqual(parenthesizedDb7b9Candidates.first?.text, "Db7(b9)")
        XCTAssertEqual(try ChordSymbolParser.parse(parenthesizedDb7b9Candidates[0].text).displayText, "Db7(b9)")
        XCTAssertEqual(db7Sharp9Candidates.first?.text, "Db7#9")
        XCTAssertEqual(try ChordSymbolParser.parse(db7Sharp9Candidates[0].text).displayText, "Db7(#9)")
        XCTAssertEqual(parenthesizedDb7Sharp9Candidates.first?.text, "Db7(#9)")
        XCTAssertEqual(try ChordSymbolParser.parse(parenthesizedDb7Sharp9Candidates[0].text).displayText, "Db7(#9)")
        XCTAssertEqual(db7Flat5Candidates.first?.text, "Db7b5")
        XCTAssertEqual(try ChordSymbolParser.parse(db7Flat5Candidates[0].text).displayText, "Db7(b5)")
        XCTAssertEqual(db7Flat13Candidates.first?.text, "Db7b13")
        XCTAssertEqual(try ChordSymbolParser.parse(db7Flat13Candidates[0].text).displayText, "Db7(b13)")
        XCTAssertEqual(db7Sharp11Candidates.first?.text, "Db7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(db7Sharp11Candidates[0].text).displayText, "Db7(#11)")
        XCTAssertEqual(parenthesizedDb7Sharp5Candidates.first?.text, "Db7(#5)")
        XCTAssertEqual(try ChordSymbolParser.parse(parenthesizedDb7Sharp5Candidates[0].text).displayText, "Db7(#5)")
        XCTAssertEqual(slashCandidates.first?.text, "G/B")
        XCTAssertEqual(try ChordSymbolParser.parse(slashCandidates[0].text).displayText, "G/B")
    }

    func testComposesCompactSharpElevenWhenHandwrittenOnesMerge() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("#", confidence: 0.82)],
            [
                glyph("1", confidence: 0.82),
                glyph("9", confidence: 0.54)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "Db7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "Db7(#11)")
    }

    func testComposesSharpElevenWhenOpeningParenthesisReadsAsNoise() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("7", confidence: 0.88)],
            [
                glyph("1", confidence: 0.74),
                glyph("b", confidence: 0.72)
            ],
            [glyph("#", confidence: 0.86)],
            [glyph("1", confidence: 0.90)],
            [glyph("1", confidence: 0.89)]
        ])

        XCTAssertEqual(candidates.first?.text, "C7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "C7(#11)")
    }

    func testComposesSharpElevenWhenClosingParenthesisReadsAsNoise() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("#", confidence: 0.90)],
            [glyph("7", confidence: 0.88)],
            [glyph("#", confidence: 0.70)],
            [glyph("1", confidence: 0.90)],
            [glyph("1", confidence: 0.88)],
            [
                glyph("7", confidence: 0.76),
                glyph("C", confidence: 0.72)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "B#7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "B#7(#11)")
    }

    func testComposesSharpElevenWhenSharpIsWeakButElevenIsExplicit() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("#", confidence: 0.90)],
            [glyph("7", confidence: 0.88)],
            [
                glyph("5", confidence: 0.62),
                glyph("#", confidence: 0.51)
            ],
            [glyph("1", confidence: 0.90)],
            [glyph("1", confidence: 0.88)],
            [glyph("7", confidence: 0.76)]
        ])

        XCTAssertEqual(candidates.first?.text, "B#7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "B#7(#11)")
    }

    func testStrongSharpNineBeatsCompactSharpElevenFallback() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.88)],
            [glyph("7", confidence: 0.88)],
            [glyph("#", confidence: 0.90)],
            [
                glyph("9", confidence: 0.96),
                glyph("1", confidence: 0.55)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "Bb7#9")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "Bb7(#9)")
    }

    func testComposesTriangleMajorExtensionInsteadOfMajText() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("△", confidence: 0.83)],
            [glyph("7", confidence: 0.89)]
        ])

        XCTAssertEqual(candidates.first?.text, "C△7")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "C△7")
        XCTAssertFalse(candidates.map(\.text).contains("Cmaj7"))
    }

    func testComposesDiminishedAndHalfDiminishedSymbols() throws {
        let diminishedCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("°", confidence: 0.91)]
        ])
        let diminishedSeventhCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("°", confidence: 0.91)],
            [glyph("7", confidence: 0.89)]
        ])
        let halfDiminishedCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("ø", confidence: 0.91)],
            [glyph("7", confidence: 0.89)]
        ])

        XCTAssertEqual(diminishedCandidates.first?.text, "C°")
        XCTAssertEqual(diminishedSeventhCandidates.first?.text, "C°7")
        XCTAssertEqual(halfDiminishedCandidates.first?.text, "Cø7")
        XCTAssertEqual(try ChordSymbolParser.parse(diminishedCandidates[0].text).displayText, "C°")
        XCTAssertEqual(try ChordSymbolParser.parse(diminishedSeventhCandidates[0].text).displayText, "C°7")
        XCTAssertEqual(try ChordSymbolParser.parse(halfDiminishedCandidates[0].text).displayText, "Cø7")
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: halfDiminishedCandidates.map(\.text))?.displayText,
            "Cø7"
        )
    }

    func testComposesAugmentedSymbolAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("+", confidence: 0.90)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("+", confidence: 0.90)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("+", confidence: 0.90)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "C+")
        XCTAssertEqual(sharpCandidates.first?.text, "F#+")
        XCTAssertEqual(flatCandidates.first?.text, "Bb+")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "C+")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#+")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bb+")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "C+")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#+")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bb+")
    }

    func testAugmentedSymbolBeatsPromotedSixWhenPlusEvidenceIsStronger() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("G", confidence: 0.97)],
            [glyph("#", confidence: 0.99)],
            [
                glyph("b", confidence: 0.59),
                glyph("E", confidence: 0.54),
                glyph("+", confidence: 0.52),
                glyph("9", confidence: 0.48),
                glyph("6", confidence: 0.48)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "G#+")
    }

    func testComposesHalfDiminishedFromMinorSevenFlatFiveAlias() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("m", confidence: 0.88)],
            [glyph("7", confidence: 0.89)],
            [glyph("b", confidence: 0.88)],
            [glyph("5", confidence: 0.90)]
        ])

        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText,
            "Bbø7"
        )
    }

    private func glyph(_ text: String, confidence: Double) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: .template)
    }
}
