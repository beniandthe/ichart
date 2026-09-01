import XCTest
@testable import iChart

final class ChordInkCandidateComposerTests: XCTestCase {
    private let composer = ChordInkCandidateComposer()
    private let recognitionComposer = ChordInkRecognitionCandidateComposer()

    func testRootSelectionMovesStrongCBeforeFlatLookalikeInFirstColumn() {
        let policy = ChordInkCandidateSelectionPolicy(maxAlternativesPerCluster: 3)

        let selected = policy.selectedGlyphCandidates(
            forColumnAt: 0,
            in: [[
                glyph("6", confidence: 0.995, source: .heuristic),
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic),
                glyph("G", confidence: 0.71, source: .template)
            ]]
        )

        XCTAssertEqual(selected.first?.text, "C")
        XCTAssertFalse(selected.contains { $0.text == "b" })
    }

    func testRootSelectionDoesNotMoveSecondColumnFlatAccidental() {
        let policy = ChordInkCandidateSelectionPolicy(maxAlternativesPerCluster: 3)

        let selected = policy.selectedGlyphCandidates(
            forColumnAt: 1,
            in: [
                [glyph("C", confidence: 0.95, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("C", confidence: 0.95, source: .heuristic)
                ]
            ]
        )

        XCTAssertEqual(selected.first?.text, "b")
    }

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

    func testDoesNotPromoteUppercaseSecondRootLetterAsFlatAccidental() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.96)],
            [
                glyph("F", confidence: 0.996, source: .heuristic),
                glyph("B", confidence: 0.59),
                glyph("D", confidence: 0.58)
            ]
        ])
        let candidateTexts = candidates.map(\.text)
        let supportedDisplayTexts = candidateTexts.compactMap { text in
            ChordRecognitionCompendium.match(text)?.displayText
        }

        XCTAssertFalse(candidateTexts.contains("CB"))
        XCTAssertFalse(supportedDisplayTexts.contains("Cb"))
    }

    func testStillComposesFlatWhenSecondGlyphIsLowercaseFlat() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("C", confidence: 0.96)],
            [glyph("b", confidence: 0.91)]
        ])

        XCTAssertEqual(candidates.first?.text, "Cb")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "Cb")
    }

    func testStillComposesSlashBassRootLetterAfterSlash() {
        let candidates = composer.compose(glyphCandidates: [
            [glyph("G", confidence: 0.96)],
            [glyph("/", confidence: 0.90)],
            [glyph("B", confidence: 0.91)]
        ])

        XCTAssertEqual(candidates.first?.text, "G/B")
        XCTAssertEqual(ChordRecognitionCompendium.match(candidates: candidates.map(\.text))?.displayText, "G/B")
    }

    func testRecognitionComposerRejectsDetachedBaseRootPressureAsQualitySuffix() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.95, source: .heuristic)],
                [
                    glyph("m", confidence: 0.99, source: .heuristic),
                    glyph("C", confidence: 0.95, source: .heuristic)
                ],
                [
                    glyph("E", confidence: 0.996, source: .heuristic),
                    glyph("5", confidence: 0.992, source: .heuristic),
                    glyph("6", confidence: 0.54)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 20, maxX: 24, maxY: 46),
                cluster(minX: 48, minY: 20, maxX: 70, maxY: 46),
                cluster(minX: 96, minY: 22, maxX: 118, maxY: 47)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("C-"))
        XCTAssertFalse(displayTexts.contains("Cm6"))
    }

    func testRecognitionComposerRejectsDetachedBaseRootPressureAsMajorSixthSuffix() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("D", confidence: 0.92, source: .heuristic)],
                [
                    glyph("E", confidence: 0.996, source: .heuristic),
                    glyph("5", confidence: 0.992, source: .heuristic),
                    glyph("6", confidence: 0.49)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 22, maxY: 49, strokes: 2),
                cluster(minX: 52, minY: 26, maxX: 74, maxY: 51, strokes: 3)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("D6"))
        XCTAssertEqual(displayTexts.first, "D")
    }

    func testRecognitionComposerRejectsDetachedBaseRootPressureAsMinorSuffix() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("F", confidence: 0.996, source: .heuristic)],
                [
                    glyph("m", confidence: 0.99, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic),
                    glyph("6", confidence: 0.67)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 26, maxX: 18, maxY: 50, strokes: 3),
                cluster(minX: 48, minY: 26, maxX: 71, maxY: 51)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("F-"))
        XCTAssertFalse(displayTexts.contains("F6"))
        XCTAssertEqual(displayTexts.first, "F")
    }

    func testRecognitionComposerStillAllowsAttachedFlatRootAccidentalWithRootPressureLookalike() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("D", confidence: 0.92, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 25, maxY: 53),
                cluster(minX: 31, minY: 14, maxX: 42, maxY: 42)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Cb")
    }

    func testRecognitionComposerStillAllowsAttachedFlatRootAccidentalWithGRootPressureLookalike() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 20, maxX: 24, maxY: 60),
                flatLikeCluster(minX: 41, minY: 23, maxX: 51, maxY: 55)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Cb")
    }

    func testRecognitionComposerStillAllowsReverseDrawnAttachedFlatRootAccidentalWithGRootPressureLookalike() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 20, maxX: 24, maxY: 60),
                reverseFlatLikeCluster(minX: 41, minY: 23, maxX: 51, maxY: 55)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Cb")
    }

    func testRecognitionComposerRejectsNarrowDetachedGRootAsFlatAccidental() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 20, maxX: 24, maxY: 60),
                cluster(minX: 41, minY: 23, maxX: 51, maxY: 55)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("Cb"))
        XCTAssertEqual(displayTexts.first, "C")
    }

    func testRecognitionComposerKeepsAccidentalSixthWhenSixHasRootPressure() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("B", confidence: 0.987, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("D", confidence: 0.979, source: .heuristic)
                ],
                [
                    glyph("6", confidence: 0.995, source: .heuristic),
                    glyph("D", confidence: 0.979, source: .heuristic),
                    glyph("b", confidence: 0.98, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 24, maxY: 54),
                cluster(minX: 30, minY: 12, maxX: 42, maxY: 44),
                cluster(minX: 70, minY: 22, maxX: 94, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertTrue(displayTexts.contains("Bb6"))
    }

    func testRecognitionComposerStillAllowsSlashBassBaseRootPressureAfterSlash() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("G", confidence: 0.96, source: .heuristic)],
                [glyph("/", confidence: 0.90)],
                [glyph("B", confidence: 0.95, source: .heuristic)]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 24, maxY: 54),
                cluster(minX: 32, minY: 20, maxX: 42, maxY: 58),
                cluster(minX: 64, minY: 24, maxX: 88, maxY: 54, strokes: 2)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "G/B")
    }

    func testRecognitionComposerRejectsDetachedRootAsFlatAccidental() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("D", confidence: 0.96, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 24, maxY: 54),
                cluster(minX: 66, minY: 25, maxX: 92, maxY: 56, strokes: 2)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("Cb"))
        XCTAssertEqual(displayTexts.first, "C")
    }

    func testRecognitionComposerRejectsDetachedGRootAsFlatAccidental() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 24, maxX: 24, maxY: 54),
                cluster(minX: 66, minY: 25, maxX: 92, maxY: 56, strokes: 2)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("Cb"))
        XCTAssertEqual(displayTexts.first, "C")
    }

    func testRecognitionComposerRejectsNarrowDetachedNonGRootAsFlatAccidental() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("C", confidence: 0.96, source: .heuristic)],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("D", confidence: 0.97, source: .heuristic)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 20, maxX: 24, maxY: 60),
                cluster(minX: 41, minY: 23, maxX: 51, maxY: 55)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertFalse(displayTexts.contains("Cb"))
        XCTAssertEqual(displayTexts.first, "C")
    }

    func testRecognitionComposerRejectsSlashBassWithoutOwnedSlashSeparator() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("E", confidence: 0.96, source: .heuristic)],
                [glyph("b", confidence: 0.91)],
                [
                    glyph("△", confidence: 0.94),
                    glyph("°", confidence: 0.90),
                    glyph("ø", confidence: 0.88)
                ],
                [
                    glyph("7", confidence: 0.95),
                    glyph("/", confidence: 0.93)
                ],
                [glyph("C", confidence: 0.92, source: .heuristic)]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 28, maxY: 58),
                cluster(minX: 34, minY: 14, maxX: 46, maxY: 38),
                angularTriangleCluster(minX: 58, minY: 22, maxX: 82, maxY: 48),
                cluster(minX: 92, minY: 18, maxX: 112, maxY: 52),
                cluster(minX: 132, minY: 22, maxX: 158, maxY: 58)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertTrue(displayTexts.contains("Eb△7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Eb°/C"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Ebø7"), "\(displayTexts)")
    }

    func testRecognitionComposerRejectsHalfDiminishedWhenTriangleOwnsQualityCluster() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("B", confidence: 0.97, source: .heuristic)],
                [glyph("b", confidence: 0.92)],
                [
                    glyph("△", confidence: 0.95),
                    glyph("ø", confidence: 0.92),
                    glyph("°", confidence: 0.88)
                ],
                [glyph("7", confidence: 0.94)]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 30, maxY: 58),
                cluster(minX: 36, minY: 14, maxX: 48, maxY: 38),
                angularTriangleCluster(minX: 60, minY: 22, maxX: 86, maxY: 48),
                cluster(minX: 98, minY: 18, maxX: 116, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertTrue(displayTexts.contains("Bb△7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Bbø7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Bb°7"), "\(displayTexts)")
    }

    func testRecognitionComposerProtectsAngularTriangleWhenRoundQualityCandidateScoresHigher() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("B", confidence: 0.97, source: .heuristic)],
                [glyph("b", confidence: 0.92)],
                [
                    glyph("°", confidence: 0.98),
                    glyph("ø", confidence: 0.94),
                    glyph("△", confidence: 0.76)
                ],
                [glyph("7", confidence: 0.94)]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 30, maxY: 58),
                cluster(minX: 36, minY: 14, maxX: 48, maxY: 38),
                angularTriangleCluster(minX: 60, minY: 22, maxX: 86, maxY: 48),
                cluster(minX: 98, minY: 18, maxX: 116, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertTrue(displayTexts.contains("Bb△7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Bb°7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Bbø7"), "\(displayTexts)")
    }

    func testRecognitionComposerRejectsNearTiedDiminishedWhenTriangleQualityIsPresent() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [
                    glyph("E", confidence: 0.996, source: .heuristic),
                    glyph("5", confidence: 0.992, source: .heuristic)
                ],
                [
                    glyph("D", confidence: 0.985),
                    glyph("b", confidence: 0.98, source: .heuristic)
                ],
                [
                    glyph("°", confidence: 1.00),
                    glyph("△", confidence: 0.999),
                    glyph("•", confidence: 0.997),
                    glyph("G", confidence: 0.97, source: .heuristic),
                    glyph("5", confidence: 0.62, source: .heuristic)
                ],
                [
                    glyph("7", confidence: 0.985, source: .heuristic),
                    glyph("C", confidence: 0.95, source: .heuristic),
                    glyph("△", confidence: 0.594)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 26, maxY: 58),
                cluster(minX: 32, minY: 14, maxX: 44, maxY: 38),
                openHandwrittenTriangleCluster(),
                cluster(minX: 96, minY: 18, maxX: 114, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Eb△7", "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Eb°7"), "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Ebø7"), "\(displayTexts)")
    }

    func testRecognitionComposerRejectsSyntheticHalfDiminishedWhenTriangleQualityIsPresent() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [
                    glyph("E", confidence: 0.996, source: .heuristic),
                    glyph("5", confidence: 0.992, source: .heuristic)
                ],
                [
                    glyph("b", confidence: 0.98, source: .heuristic),
                    glyph("G", confidence: 0.97, source: .heuristic),
                    glyph("•", confidence: 0.955)
                ],
                [
                    glyph("△", confidence: 0.627),
                    glyph("A", confidence: 0.510),
                    glyph("D", confidence: 0.483),
                    glyph("B", confidence: 0.482),
                    glyph("°", confidence: 0.453)
                ],
                [
                    glyph("3", confidence: 0.997, source: .heuristic),
                    glyph("7", confidence: 0.985, source: .heuristic),
                    glyph("C", confidence: 0.95, source: .heuristic),
                    glyph("△", confidence: 0.630),
                    glyph("°", confidence: 0.579)
                ]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 26, maxY: 58),
                cluster(minX: 32, minY: 14, maxX: 44, maxY: 38),
                openHandwrittenTriangleCluster(),
                cluster(minX: 96, minY: 18, maxX: 114, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Eb△7", "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Ebø7"), "\(displayTexts)")
    }

    func testRecognitionComposerDoesNotPromoteHalfDiminishedFallbackOverWeakTriangleMajorSeven() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [
                    glyph("B", confidence: 0.987, source: .heuristic),
                    glyph("D", confidence: 0.694),
                    glyph("F", confidence: 0.541)
                ],
                [
                    glyph("D", confidence: 0.985, source: .heuristic),
                    glyph("b", confidence: 0.980, source: .heuristic),
                    glyph("B", confidence: 0.581)
                ],
                [
                    glyph("△", confidence: 0.565),
                    glyph("D", confidence: 0.547),
                    glyph("B", confidence: 0.539),
                    glyph("5", confidence: 0.492),
                    glyph("A", confidence: 0.481),
                    glyph("3", confidence: 0.471),
                    glyph("7", confidence: 0.452)
                ],
                [
                    glyph("7", confidence: 0.985, source: .heuristic),
                    glyph("C", confidence: 0.950, source: .heuristic),
                    glyph("5", confidence: 0.620, source: .heuristic),
                    glyph("△", confidence: 0.574),
                    glyph("m", confidence: 0.548)
                ]
            ],
            clusters: [
                cluster(minX: 28.23, minY: 42.45, maxX: 50.71, maxY: 79.82, strokes: 2),
                cluster(minX: 59.34, minY: 34.60, maxX: 70.02, maxY: 50.11, strokes: 2),
                splitHandwrittenTriangleCluster(),
                cluster(minX: 95.86, minY: 31.56, maxX: 109.11, maxY: 42.39)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertEqual(displayTexts.first, "Bb△7", "\(displayTexts)")
        XCTAssertFalse(displayTexts.contains("Bbø7"), "\(displayTexts)")
    }

    func testRecognitionComposerStillAllowsOwnedHalfDiminishedQuality() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("B", confidence: 0.97, source: .heuristic)],
                [glyph("b", confidence: 0.92)],
                [
                    glyph("ø", confidence: 0.95),
                    glyph("△", confidence: 0.70),
                    glyph("°", confidence: 0.68)
                ],
                [glyph("7", confidence: 0.94)]
            ],
            clusters: [
                cluster(minX: 0, minY: 22, maxX: 30, maxY: 58),
                cluster(minX: 36, minY: 14, maxX: 48, maxY: 38),
                cluster(minX: 60, minY: 22, maxX: 86, maxY: 48, strokes: 2),
                cluster(minX: 98, minY: 18, maxX: 116, maxY: 52)
            ]
        )
        let displayTexts = result.candidates.compactMap { candidate in
            ChordRecognitionCompendium.match(candidate.text)?.displayText
        }

        XCTAssertTrue(displayTexts.contains("Bbø7"))
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
        XCTAssertLessThan(absusCandidate.confidence, ChordInkRecognitionPolicy.trustedMinimumConfidence)
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

    func testSemanticComposerRecognizesChordRepeatDotSlashDot() {
        let result = recognitionComposer.composeRecognitionCandidates(
            from: [
                [glyph("•", confidence: 0.92)],
                [glyph("/", confidence: 0.88)],
                [glyph("•", confidence: 0.91)]
            ],
            clusters: [
                cluster(minX: 10, minY: 24, maxX: 18, maxY: 32),
                cluster(minX: 34, minY: 10, maxX: 50, maxY: 56),
                cluster(minX: 66, minY: 36, maxX: 74, maxY: 44)
            ]
        )

        XCTAssertEqual(result.candidates.first?.text, "•/•")
        XCTAssertEqual(
            ChordRecognitionCompendium.match(candidates: result.candidates.map(\.text))?.displayText,
            "•/•"
        )
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

    private func angularTriangleCluster(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) -> InkCluster {
        let midX = minX + (maxX - minX) / 2
        let top = InkPoint(x: midX, y: minY, timeOffset: nil)
        let lowerLeft = InkPoint(x: minX, y: maxY, timeOffset: nil)
        let lowerRight = InkPoint(x: maxX, y: maxY, timeOffset: nil)

        return InkCluster(strokes: [
            InkStroke(points: [lowerLeft, top]),
            InkStroke(points: [top, lowerRight]),
            InkStroke(points: [lowerRight, lowerLeft])
        ])
    }

    private func flatLikeCluster(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) -> InkCluster {
        let height = maxY - minY
        let width = maxX - minX
        return InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: minX, y: minY, timeOffset: nil),
                InkPoint(x: minX, y: maxY, timeOffset: nil),
                InkPoint(x: maxX, y: minY + height * 0.75, timeOffset: nil),
                InkPoint(x: minX + width * 0.25, y: minY + height * 0.50, timeOffset: nil)
            ])
        ])
    }

    private func reverseFlatLikeCluster(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) -> InkCluster {
        let height = maxY - minY
        let width = maxX - minX
        return InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: minX + width * 0.25, y: minY + height * 0.50, timeOffset: nil),
                InkPoint(x: maxX, y: minY + height * 0.75, timeOffset: nil),
                InkPoint(x: minX, y: maxY, timeOffset: nil),
                InkPoint(x: minX, y: minY, timeOffset: nil)
            ])
        ])
    }

    private func openHandwrittenTriangleCluster() -> InkCluster {
        let points = [
            InkPoint(x: 432.9944763183594, y: 47.6688346862793, timeOffset: nil),
            InkPoint(x: 431.8739929199219, y: 49.31928253173828, timeOffset: nil),
            InkPoint(x: 431.14898681640625, y: 50.639617919921875, timeOffset: nil),
            InkPoint(x: 430.1603088378906, y: 52.42211151123047, timeOffset: nil),
            InkPoint(x: 428.7761535644531, y: 54.66670227050781, timeOffset: nil),
            InkPoint(x: 427.9852600097656, y: 56.11908721923828, timeOffset: nil),
            InkPoint(x: 429.5671081542969, y: 54.73270797729492, timeOffset: nil),
            InkPoint(x: 431.14898681640625, y: 52.95024871826172, timeOffset: nil),
            InkPoint(x: 432.0717468261719, y: 51.695919036865234, timeOffset: nil),
            InkPoint(x: 432.8626708984375, y: 50.37554931640625, timeOffset: nil),
            InkPoint(x: 433.851318359375, y: 48.52704620361328, timeOffset: nil),
            InkPoint(x: 434.5104675292969, y: 46.94264221191406, timeOffset: nil),
            InkPoint(x: 434.84002685546875, y: 44.16988754272461, timeOffset: nil),
            InkPoint(x: 435.2354736328125, y: 45.75432205200195, timeOffset: nil),
            InkPoint(x: 436.8832702636719, y: 48.0649528503418, timeOffset: nil),
            InkPoint(x: 437.7401123046875, y: 49.38528823852539, timeOffset: nil),
            InkPoint(x: 439.2560729980469, y: 51.695919036865234, timeOffset: nil),
            InkPoint(x: 439.78338623046875, y: 53.28032302856445, timeOffset: nil),
            InkPoint(x: 439.58563232421875, y: 55.1948356628418, timeOffset: nil),
            InkPoint(x: 437.7401123046875, y: 56.647220611572266, timeOffset: nil),
            InkPoint(x: 435.96051025390625, y: 57.30740737915039, timeOffset: nil),
            InkPoint(x: 433.7195129394531, y: 57.835540771484375, timeOffset: nil),
            InkPoint(x: 431.34674072265625, y: 58.16561508178711, timeOffset: nil),
            InkPoint(x: 429.237548828125, y: 58.231658935546875, timeOffset: nil),
            InkPoint(x: 427.4579162597656, y: 58.231658935546875, timeOffset: nil),
            InkPoint(x: 425.5464782714844, y: 57.835540771484375, timeOffset: nil),
            InkPoint(x: 424.88739013671875, y: 56.185096740722656, timeOffset: nil),
            InkPoint(x: 426.5351867675781, y: 55.32688522338867, timeOffset: nil)
        ]
        return InkCluster(strokes: [InkStroke(points: points)])
    }

    private func splitHandwrittenTriangleCluster() -> InkCluster {
        InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 84.25732421875, y: 37.568138122558594, timeOffset: nil),
                InkPoint(x: 83.46639251708984, y: 39.41664505004883, timeOffset: nil),
                InkPoint(x: 82.74137115478516, y: 40.8690299987793, timeOffset: nil),
                InkPoint(x: 81.55496215820312, y: 43.377685546875, timeOffset: nil),
                InkPoint(x: 80.89584350585938, y: 45.22618865966797, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 83.46639251708984, y: 36.77593994140625, timeOffset: nil),
                InkPoint(x: 85.04825592041016, y: 37.63414764404297, timeOffset: nil),
                InkPoint(x: 85.97103118896484, y: 38.88847351074219, timeOffset: nil),
                InkPoint(x: 86.9596939086914, y: 40.40690612792969, timeOffset: nil),
                InkPoint(x: 87.8824691772461, y: 41.859291076660156, timeOffset: nil),
                InkPoint(x: 88.80522155761719, y: 43.24563217163086, timeOffset: nil),
                InkPoint(x: 89.99163055419922, y: 45.22618865966797, timeOffset: nil),
                InkPoint(x: 90.91438293457031, y: 46.61253356933594, timeOffset: nil),
                InkPoint(x: 91.57349395751953, y: 48.32902145385742, timeOffset: nil),
                InkPoint(x: 90.05754089355469, y: 48.262977600097656, timeOffset: nil),
                InkPoint(x: 88.40974426269531, y: 48.13096237182617, timeOffset: nil),
                InkPoint(x: 86.16876220703125, y: 48.13096237182617, timeOffset: nil),
                InkPoint(x: 84.05960083007812, y: 48.13096237182617, timeOffset: nil),
                InkPoint(x: 82.27998352050781, y: 48.13096237182617, timeOffset: nil),
                InkPoint(x: 81.7527084350586, y: 48.0649528503418, timeOffset: nil)
            ])
        ])
    }
}
