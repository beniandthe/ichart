import XCTest
@testable import SmartChart

final class ChordInkCandidateComposerTests: XCTestCase {
    private let composer = ChordInkCandidateComposer()
    private let recognitionComposer = ChordInkRecognitionCandidateComposer()

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

    func testComposesMinorSixthNinthEleventhAndThirteenthToStandardDashMinorExtensions() throws {
        let mMinorSixthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("m", confidence: 0.88)],
            [glyph("6", confidence: 0.89)]
        ])
        let dashMinorSixthCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("-", confidence: 0.88)],
            [glyph("6", confidence: 0.89)]
        ])
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
        let accidentalMinorSixthCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.96)],
            [glyph("#", confidence: 0.92)],
            [glyph("m", confidence: 0.88)],
            [glyph("6", confidence: 0.90)]
        ])

        XCTAssertEqual(mMinorSixthCandidates.first?.text, "Cm6")
        XCTAssertEqual(dashMinorSixthCandidates.first?.text, "Cm6")
        XCTAssertEqual(dashMinorNinthCandidates.first?.text, "C-9")
        XCTAssertEqual(mMinorNinthCandidates.first?.text, "C-9")
        XCTAssertEqual(mMinorEleventhCandidates.first?.text, "C-11")
        XCTAssertEqual(accidentalMinorThirteenthCandidates.first?.text, "Bb-13")
        XCTAssertEqual(accidentalMinorSixthCandidates.first?.text, "F#m6")
        XCTAssertEqual(try ChordSymbolParser.parse(mMinorSixthCandidates[0].text).displayText, "Cm6")
        XCTAssertEqual(try ChordSymbolParser.parse(dashMinorSixthCandidates[0].text).displayText, "Cm6")
        XCTAssertEqual(try ChordSymbolParser.parse(dashMinorNinthCandidates[0].text).displayText, "C-9")
        XCTAssertEqual(try ChordSymbolParser.parse(mMinorNinthCandidates[0].text).displayText, "C-9")
        XCTAssertEqual(try ChordSymbolParser.parse(mMinorEleventhCandidates[0].text).displayText, "C-11")
        XCTAssertEqual(try ChordSymbolParser.parse(accidentalMinorThirteenthCandidates[0].text).displayText, "Bb-13")
        XCTAssertEqual(try ChordSymbolParser.parse(accidentalMinorSixthCandidates[0].text).displayText, "F#m6")
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: accidentalMinorThirteenthCandidates.map(\.text))?.displayText,
            "Bb-13"
        )
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: accidentalMinorSixthCandidates.map(\.text))?.displayText,
            "F#m6"
        )
    }

    func testDashMinorNinthDoesNotCloseTieWithMinorSixthLookalike() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("-", confidence: 0.995)],
            [
                glyph("9", confidence: 0.999),
                glyph("6", confidence: 0.995)
            ]
        ])

        let minorNinthScore = try XCTUnwrap(candidates.first { $0.text == "C-9" }?.confidence)
        let minorSixthScore = try XCTUnwrap(candidates.first { $0.text == "Cm6" }?.confidence)

        XCTAssertEqual(candidates.first?.text, "C-9")
        XCTAssertGreaterThan(
            minorNinthScore - minorSixthScore,
            ChordInkRecognitionPolicy.closeRaceConfidenceGap
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

    func testBareFlatAccidentalBeatsBareSixthLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.96)],
            [
                glyph("6", confidence: 0.91),
                glyph("b", confidence: 0.89)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "Bb")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bb")
    }

    func testBareSixthCanStillWinWithStrongExplicitSixEvidence() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.96)],
            [
                glyph("6", confidence: 0.96),
                glyph("b", confidence: 0.70)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "B6")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "B6")
    }

    func testNaturalSixthWinsWhenFinalColumnFavorsSixOverFlat() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [
                glyph("C", confidence: 0.95),
                glyph("6", confidence: 0.69),
                glyph("b", confidence: 0.60),
                glyph("5", confidence: 0.58)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "C6")
    }

    func testWeakLeadingRootDoesNotCreateAcceptedFlatSeventhSuggestion() {
        let candidates = composer.compose(glyphCandidates: [
            [
                glyph("5", confidence: 0.62),
                glyph("D", confidence: 0.55),
                glyph("B", confidence: 0.55)
            ],
            [glyph("b", confidence: 0.98)],
            [glyph("7", confidence: 0.99)]
        ])

        XCTAssertLessThan(candidates.first?.confidence ?? 0, 3.70)
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

    func testSuspendedSLookalikeSoftensSlashBassCandidate() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [
                glyph("s", confidence: 0.76),
                glyph("/", confidence: 0.72)
            ],
            [
                glyph("D", confidence: 0.53),
                glyph("9", confidence: 0.99)
            ],
            [
                glyph("b", confidence: 0.98),
                glyph("s", confidence: 0.55)
            ]
        ])

        let slashCandidate = candidates.first { $0.text == "C/Db" }

        XCTAssertLessThan(slashCandidate?.confidence ?? 0, 4.70)
    }

    func testCompactSuspendedCandidateIncludesPlausibleLowConfidenceFlatRoots() throws {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [
                    glyph("B", confidence: 0.555),
                    glyph("F", confidence: 0.535),
                    glyph("D", confidence: 0.515),
                    glyph("A", confidence: 0.507)
                ],
                [glyph("b", confidence: 0.980)],
                [
                    glyph("9", confidence: 0.999),
                    glyph("b", confidence: 0.980),
                    glyph("C", confidence: 0.950),
                    glyph("s", confidence: 0.550)
                ],
                [
                    glyph("1", confidence: 0.996),
                    glyph("C", confidence: 0.965),
                    glyph("b", confidence: 0.658),
                    glyph("s", confidence: 0.550)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 100, maxX: 22, maxY: 145, strokes: 2),
                cluster(minX: 25, minY: 92, maxX: 35, maxY: 119),
                cluster(minX: 43, minY: 126, maxX: 53, maxY: 145),
                cluster(minX: 61, minY: 124, maxX: 66, maxY: 145)
            ]
        )

        let supportedTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }
        let absusCandidate = try XCTUnwrap(result.candidates.first { candidate in
            candidate.text == "Absus"
        })

        XCTAssertTrue(supportedTexts.contains("Absus"))
        XCTAssertTrue(supportedTexts.contains("Bbsus"))
        XCTAssertGreaterThanOrEqual(absusCandidate.confidence, 3.70)
        XCTAssertLessThan(absusCandidate.confidence, ChordInkRecognitionPolicy.autoRenderMinimumConfidence)
    }

    func testSuspendedLookalikePenalizesSlashBassCandidateAtModestSConfidence() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("A", confidence: 0.95)],
            [glyph("b", confidence: 0.98)],
            [
                glyph("/", confidence: 0.72),
                glyph("s", confidence: 0.55)
            ],
            [
                glyph("C", confidence: 0.96),
                glyph("u", confidence: 0.78)
            ],
            [
                glyph("b", confidence: 0.98),
                glyph("s", confidence: 0.55)
            ]
        ])

        let slashCandidate = try XCTUnwrap(candidates.first { candidate in
            candidate.text == "Ab/Cb"
        })

        XCTAssertLessThan(slashCandidate.confidence, 4.95)
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

    func testAlteredThirteenRequiresExplicitOneAndThreeEvidence() {
        let parenthesizedFlatNineWithWrapperNoise = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [
                glyph("1", confidence: 0.996, source: .heuristic),
                glyph("(", confidence: 0.86)
            ],
            [
                glyph("+", confidence: 0.57),
                glyph("B", confidence: 0.57)
            ],
            [
                glyph("9", confidence: 0.999, source: .heuristic),
                glyph("b", confidence: 0.98, source: .heuristic)
            ],
            [
                glyph("1", confidence: 0.996, source: .heuristic),
                glyph(")", confidence: 0.81)
            ]
        ])
        let displayTexts = parenthesizedFlatNineWithWrapperNoise.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("Db7(b13)"))
    }

    func testExplicitAlteredThirteenStillComposesWhenOneAndThreeAreWritten() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.95)],
            [glyph("b", confidence: 0.85)],
            [glyph("7", confidence: 0.88)],
            [glyph("b", confidence: 0.82)],
            [glyph("1", confidence: 0.88)],
            [glyph("3", confidence: 0.72)]
        ])

        XCTAssertEqual(candidates.first?.text, "Db7b13")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Db7(b13)")
    }

    func testSlashBassFlatCanRecoverFromFinalFlatLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("E", confidence: 0.98)],
            [glyph("b", confidence: 0.98)],
            [glyph("7", confidence: 0.98)],
            [
                glyph("/", confidence: 0.72),
                glyph("1", confidence: 0.99)
            ],
            [glyph("B", confidence: 0.97)],
            [
                glyph("G", confidence: 0.97),
                glyph("5", confidence: 0.62)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Eb7/Bb")
    }

    func testPlainSlashBassDoesNotRequireTrailingFlatLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("E", confidence: 0.98)],
            [glyph("b", confidence: 0.98)],
            [glyph("7", confidence: 0.98)],
            [glyph("/", confidence: 0.72)],
            [glyph("B", confidence: 0.97)]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Eb7/B")
    }

    func testComposesNinthSharpFiveAboveFlatThirteenLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("G", confidence: 0.95)],
            [
                glyph("7", confidence: 0.86),
                glyph("b", confidence: 0.85)
            ],
            [
                glyph("9", confidence: 0.88),
                glyph("b", confidence: 0.82)
            ],
            [
                glyph("1", confidence: 0.88),
                glyph("#", confidence: 0.82)
            ],
            [
                glyph("5", confidence: 0.88),
                glyph("3", confidence: 0.72)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Gb9(#5)")
    }

    func testComposesNinthSharpFiveWithoutRootAccidental() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("A", confidence: 0.98)],
            [
                glyph("9", confidence: 0.999),
                glyph("7", confidence: 0.985)
            ],
            [glyph("#", confidence: 0.99)],
            [
                glyph("9", confidence: 0.66),
                glyph("5", confidence: 0.57)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "A9(#5)")
    }

    func testComposesNinthSharpFiveAheadOfSevenSharpFiveAcrossChromaticRoots() {
        let roots: [(display: String, glyphs: [String])] = [
            ("C", ["C"]),
            ("Db", ["D", "b"]),
            ("D", ["D"]),
            ("Eb", ["E", "b"]),
            ("E", ["E"]),
            ("F", ["F"]),
            ("Gb", ["G", "b"]),
            ("G", ["G"]),
            ("Ab", ["A", "b"]),
            ("A", ["A"]),
            ("Bb", ["B", "b"]),
            ("B", ["B"])
        ]

        for root in roots {
            let rootColumns = root.glyphs.map { [glyph($0, confidence: 0.98)] }
            let candidates = composer.compose(glyphCandidates: rootColumns + [
                [
                    glyph("9", confidence: 0.999),
                    glyph("7", confidence: 0.985)
                ],
                [glyph("#", confidence: 0.99)],
                [
                    glyph("9", confidence: 0.66),
                    glyph("5", confidence: 0.57)
                ]
            ])

            XCTAssertEqual(
                ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText,
                "\(root.display)9(#5)",
                "Expected \(root.display)9(#5) to beat \(root.display)7(#5)"
            )
        }
    }

    func testComposesDominantSharpFiveWhenSevenEvidenceBeatsNinth() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("A", confidence: 0.98)],
            [
                glyph("7", confidence: 0.99),
                glyph("9", confidence: 0.88)
            ],
            [glyph("#", confidence: 0.99)],
            [
                glyph("5", confidence: 0.72),
                glyph("9", confidence: 0.48)
            ]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "A7(#5)")
    }

    func testComposesNinthSharpFiveWhenRootLooksLikeFiveButStructureIsClear() {
        let candidates = composer.compose(glyphCandidates: [
            [
                glyph("5", confidence: 0.620),
                glyph("A", confidence: 0.535),
                glyph("b", confidence: 0.503)
            ],
            [
                glyph("9", confidence: 0.999),
                glyph("7", confidence: 0.985)
            ],
            [
                glyph("5", confidence: 0.992),
                glyph("#", confidence: 0.990)
            ],
            [
                glyph("3", confidence: 0.997),
                glyph("7", confidence: 0.985),
                glyph("G", confidence: 0.970),
                glyph("5", confidence: 0.659)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "A9#5")
        XCTAssertGreaterThanOrEqual(candidates.first?.confidence ?? 0, 3.70)
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "A9(#5)")
    }

    func testPenalizesLowercaseSlashBassRootLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("A", confidence: 0.95)],
            [glyph("#", confidence: 0.90)],
            [glyph("/", confidence: 0.86)],
            [
                glyph("b", confidence: 0.91),
                glyph("G", confidence: 0.90)
            ],
            [glyph("#", confidence: 0.86)]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "A#/G#")
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

    func testComposesCompactSharpElevenWhenWrapperAndTailAreBothNoisy() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.96)],
            [glyph("7", confidence: 0.89)],
            [
                glyph("7", confidence: 0.84),
                glyph("1", confidence: 0.82)
            ],
            [glyph("#", confidence: 0.88)],
            [glyph("1", confidence: 0.88)]
        ])

        XCTAssertEqual(candidates.first?.text, "C7#11")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "C7(#11)")
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

    func testComposesSharpNineWhenClosingWrapperLooksLikeOne() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("D", confidence: 0.985)],
            [glyph("#", confidence: 0.990)],
            [glyph("7", confidence: 0.820)],
            [glyph("#", confidence: 0.990)],
            [
                glyph("3", confidence: 0.997),
                glyph("7", confidence: 0.985),
                glyph("G", confidence: 0.970),
                glyph("5", confidence: 0.620),
                glyph("9", confidence: 0.595),
                glyph("1", confidence: 0.517)
            ],
            [
                glyph("1", confidence: 0.996),
                glyph("b", confidence: 0.980),
                glyph(")", confidence: 0.741),
                glyph("9", confidence: 0.680)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "D#7#9")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "D#7(#9)")
    }

    func testSharpFiveTailEvidenceBeatsSharpNineLookalike() throws {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("E", confidence: 0.96)],
            [glyph("b", confidence: 0.88)],
            [glyph("7", confidence: 0.90)],
            [glyph("#", confidence: 0.90)],
            [
                glyph("3", confidence: 0.997),
                glyph("7", confidence: 0.985),
                glyph("G", confidence: 0.970),
                glyph("5", confidence: 0.620),
                glyph("9", confidence: 0.579)
            ]
        ])

        XCTAssertEqual(candidates.first?.text, "Eb7#5")
        XCTAssertEqual(try ChordSymbolParser.parse(candidates[0].text).displayText, "Eb7(#5)")
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

    func testExplicitTriangleMajorQualityBeatsFlatAlteredLookalike() throws {
        let candidates = composer.compose(glyphCandidates: [
            [
                glyph("B", confidence: 0.97),
                glyph("D", confidence: 0.69),
                glyph("F", confidence: 0.52)
            ],
            [
                glyph("△", confidence: 1.00, source: .heuristic),
                glyph("9", confidence: 1.00, source: .heuristic),
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("G", confidence: 0.97, source: .heuristic)
            ],
            [
                glyph("7", confidence: 0.98, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic),
                glyph("3", confidence: 0.66)
            ],
            [glyph("#", confidence: 0.99, source: .heuristic)],
            [glyph("1", confidence: 1.00, source: .heuristic)]
        ])

        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText,
            "B△7(#11)"
        )
    }

    func testComposesMinorMajorSeventhFromDashTriangleQuality() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("-", confidence: 0.91)],
            [glyph("△", confidence: 0.88)],
            [glyph("7", confidence: 0.89)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("-", confidence: 0.90)],
            [glyph("△", confidence: 0.88)],
            [glyph("7", confidence: 0.89)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("-", confidence: 0.90)],
            [glyph("△", confidence: 0.88)],
            [glyph("7", confidence: 0.89)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "C-△7")
        XCTAssertEqual(sharpCandidates.first?.text, "F#-△7")
        XCTAssertEqual(flatCandidates.first?.text, "Bb-△7")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "C-△7")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#-△7")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bb-△7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "C-△7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#-△7")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bb-△7")
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

    func testComposesHalfDiminishedFromRoundLookalikeBeforeSeven() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.90)],
            [
                glyph("B", confidence: 0.74),
                glyph("G", confidence: 0.70),
                glyph("3", confidence: 0.68)
            ],
            [glyph("7", confidence: 0.88)]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bbø7")
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

    func testComposesPlainSuspendedSuffixAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "Csus")
        XCTAssertEqual(sharpCandidates.first?.text, "F#sus")
        XCTAssertEqual(flatCandidates.first?.text, "Bbsus")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "Csus")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#sus")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bbsus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "Csus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#sus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bbsus")
    }

    func testComposesPureAlteredSuffixAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("a", confidence: 0.89)],
            [glyph("l", confidence: 0.88)],
            [glyph("t", confidence: 0.87)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("a", confidence: 0.89)],
            [glyph("l", confidence: 0.88)],
            [glyph("t", confidence: 0.87)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("a", confidence: 0.89)],
            [glyph("l", confidence: 0.88)],
            [glyph("t", confidence: 0.87)]
        ])
        let explicitDominantCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("7", confidence: 0.91)],
            [glyph("a", confidence: 0.89)],
            [glyph("l", confidence: 0.88)],
            [glyph("t", confidence: 0.87)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "Calt")
        XCTAssertEqual(sharpCandidates.first?.text, "F#alt")
        XCTAssertEqual(flatCandidates.first?.text, "Bbalt")
        XCTAssertEqual(explicitDominantCandidates.first?.text, "C7alt")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "C7alt")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#7alt")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bb7alt")
        XCTAssertEqual(try ChordSymbolParser.parse(explicitDominantCandidates[0].text).displayText, "C7alt")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "C7alt")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#7alt")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bb7alt")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: explicitDominantCandidates.map(\.text))?.displayText, "C7alt")
    }

    func testComposesSuspendedFourthSuffixAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)],
            [glyph("4", confidence: 0.86)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)],
            [glyph("4", confidence: 0.86)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)],
            [glyph("4", confidence: 0.86)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "Csus4")
        XCTAssertEqual(sharpCandidates.first?.text, "F#sus4")
        XCTAssertEqual(flatCandidates.first?.text, "Bbsus4")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "Csus4")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#sus4")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bbsus4")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "Csus4")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#sus4")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bbsus4")
    }

    func testComposesDominantSuspendedSuffixAfterRootAndAccidental() throws {
        let naturalCandidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.95)],
            [glyph("7", confidence: 0.91)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])
        let sharpCandidates = composer.compose(glyphCandidates: [
            [glyph("F", confidence: 0.95)],
            [glyph("#", confidence: 0.91)],
            [glyph("7", confidence: 0.90)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])
        let flatCandidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [glyph("b", confidence: 0.91)],
            [glyph("7", confidence: 0.90)],
            [glyph("s", confidence: 0.89)],
            [glyph("u", confidence: 0.88)],
            [glyph("s", confidence: 0.87)]
        ])

        XCTAssertEqual(naturalCandidates.first?.text, "C7sus")
        XCTAssertEqual(sharpCandidates.first?.text, "F#7sus")
        XCTAssertEqual(flatCandidates.first?.text, "Bb7sus")
        XCTAssertEqual(try ChordSymbolParser.parse(naturalCandidates[0].text).displayText, "C7sus")
        XCTAssertEqual(try ChordSymbolParser.parse(sharpCandidates[0].text).displayText, "F#7sus")
        XCTAssertEqual(try ChordSymbolParser.parse(flatCandidates[0].text).displayText, "Bb7sus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: naturalCandidates.map(\.text))?.displayText, "C7sus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: sharpCandidates.map(\.text))?.displayText, "F#7sus")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: flatCandidates.map(\.text))?.displayText, "Bb7sus")
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

    func testPlainFlatSlashBassWinsTinyRaceAgainstDiminishedLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [
                glyph("°", confidence: 0.91),
                glyph("b", confidence: 0.90)
            ],
            [glyph("/", confidence: 0.90)],
            [glyph("D", confidence: 0.90)]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Bb/D")
    }

    func testClearDiminishedSlashBassStillWinsOverWeakFlatLookalike() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("B", confidence: 0.95)],
            [
                glyph("°", confidence: 0.97),
                glyph("b", confidence: 0.68)
            ],
            [glyph("/", confidence: 0.90)],
            [glyph("D", confidence: 0.90)]
        ])

        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "B°/D")
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
        maxY: Double,
        strokes: Int = 1
    ) -> InkCluster {
        let bounds = InkBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        return InkCluster(
            strokes: (0..<strokes).map { _ in
                InkStroke(
                    points: [
                        InkPoint(x: minX, y: minY, timeOffset: nil),
                        InkPoint(x: maxX, y: maxY, timeOffset: nil)
                    ],
                    bounds: bounds
                )
            },
            bounds: bounds
        )
    }
}
