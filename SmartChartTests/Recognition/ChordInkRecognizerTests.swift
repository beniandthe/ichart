import XCTest
@testable import SmartChart

final class ChordInkRecognizerTests: XCTestCase {
    private static let fixtureCorpus: Result<[InkFixture], Error> = Result {
        try InkFixtureLoader.loadAll(file: #filePath)
    }

    private let recognizer = ChordInkRecognizer()

    func testRecognizesEveryInkFixtureThroughPureSwiftPipeline() throws {
        for fixture in try allFixtures() {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertFalse(result.rawCandidates.isEmpty, fixture.name)
            if !fixture.allowsCompactSemanticRecognition {
                XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            }
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantFlatFiveInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("(b5)") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantSharpFiveInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("(#5)") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantSharpNineInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("(#9)") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantFlatThirteenInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("(b13)") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, "\(fixture.name) \(debugSummary)")
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantSharpElevenInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("(#11)") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesDominantAlteredInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("7alt") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesPlainSuspendedInkFixtures() throws {
        let fixtureNames = [
            "Csus",
            "CsusCaptured01",
            "Gsus",
            "GsusCaptured01",
            "BFlatsus",
            "BFlatsusCaptured01",
            "FSharpsus",
            "FSharpsusCaptured01"
        ]

        for fixtureName in fixtureNames {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesSuspendedFourthWithContextualFinalGlyph() throws {
        let strokes = try shiftedTemplateStrokes("C", offsetX: 0)
            + shiftedTemplateStrokes("s", offsetX: 52)
            + shiftedTemplateStrokes("u", offsetX: 88)
            + shiftedTemplateStrokes("s", offsetX: 128)
            + [
                InkStroke(points: [
                    InkPoint(x: 252, y: 16, timeOffset: nil),
                    InkPoint(x: 234, y: 42, timeOffset: nil),
                    InkPoint(x: 261, y: 42, timeOffset: nil),
                    InkPoint(x: 255, y: 42, timeOffset: nil),
                    InkPoint(x: 255, y: 60, timeOffset: nil)
                ])
            ]

        let result = recognizer.recognize(strokes: strokes)

        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) })"

        XCTAssertEqual(result.match?.displayText, "Csus4", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Csus4"), debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, 5)
    }

    func testRecognizesDominantSuspendedFromGlyphSequence() throws {
        let strokes = try shiftedTemplateStrokes("C", offsetX: 0)
            + shiftedTemplateStrokes("7", offsetX: 100)
            + shiftedTemplateStrokes("s", offsetX: 200)
            + shiftedTemplateStrokes("u", offsetX: 300)
            + shiftedTemplateStrokes("s", offsetX: 400)

        let result = recognizer.recognize(strokes: strokes)

        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) })"

        XCTAssertEqual(result.match?.displayText, "C7sus", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("C7sus"), debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, 5)
    }

    func testRecognizesDominantSuspendedInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("7sus") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesCompressedMinorEleventhTail() throws {
        let strokes = try transformedTemplateStrokes("C", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("-", offsetX: -10, offsetY: 0, scale: 1)
            + [
                InkStroke(points: [
                    InkPoint(x: 88, y: 16, timeOffset: nil),
                    InkPoint(x: 88, y: 43, timeOffset: nil)
                ]),
                InkStroke(points: [
                    InkPoint(x: 94, y: 17, timeOffset: nil),
                    InkPoint(x: 94, y: 44, timeOffset: nil)
                ])
            ]

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "C-11", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("C-11"), debugSummary)
    }

    func testRecognizesMinorSixthInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.hasSuffix("m6") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesMajorSixthInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.hasSuffix("6") && !$0.expectedDisplayText.hasSuffix("m6") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let glyphSummary = result.glyphCandidates.map { group in
                group.prefix(6).map { "\($0.text):\(String(format: "%.3f", $0.confidence))" }.joined(separator: ",")
            }
            let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(glyphSummary), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, "\(fixture.name) \(debugSummary)")
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testBodySizedFinalSixReadsAsMajorSixth() throws {
        let strokes = try transformedTemplateStrokes("C", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("6", offsetX: -35, offsetY: 0, scale: 1)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "C6", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("C6"), debugSummary)
    }

    func testSmallHighFlatAfterRootDoesNotReadAsMajorSixth() throws {
        let strokes = try transformedTemplateStrokes("C", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("b", offsetX: 24, offsetY: 4, scale: 0.46)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Cb", debugSummary)
        let flatScore = result.candidateScores.first { $0.displayText == "Cb" }?.confidence ?? 0
        let sixthScore = result.candidateScores.first { $0.displayText == "C6" }?.confidence ?? 0
        XCTAssertGreaterThan(flatScore, sixthScore, debugSummary)
    }

    func testRecognizesFlatDiminishedWhenFlatLooksLikeSixthOrDegree() throws {
        let strokes = try transformedTemplateStrokes("E", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("b", offsetX: 24, offsetY: 4, scale: 0.46)
            + transformedTemplateStrokes("°", offsetX: 35, offsetY: -4, scale: 0.55)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Eb°", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Eb°"), debugSummary)
    }

    func testRecognizesTinyUpperDegreeLookalikeBeforeSevenAsDiminishedSeventh() throws {
        let degreeLookalike = InkStroke(points: [
            InkPoint(x: 78, y: 5, timeOffset: nil),
            InkPoint(x: 83, y: 3, timeOffset: nil),
            InkPoint(x: 87, y: 8, timeOffset: nil),
            InkPoint(x: 85, y: 14, timeOffset: nil),
            InkPoint(x: 79, y: 13, timeOffset: nil),
            InkPoint(x: 77, y: 8, timeOffset: nil)
        ])
        let strokes = try transformedTemplateStrokes("G", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("b", offsetX: 33, offsetY: -8, scale: 0.46)
            + [degreeLookalike]
            + transformedTemplateStrokes("7", offsetX: 106, offsetY: -4, scale: 0.72)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Gb°7", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Gb°7"), debugSummary)
    }

    func testRecognizesAlteredDominantWhenSevenIsRoundedLookalike() throws {
        let roundedSevenLookalike = [
            InkStroke(points: [
                InkPoint(x: 120, y: 3, timeOffset: nil),
                InkPoint(x: 136, y: 4, timeOffset: nil),
                InkPoint(x: 134, y: 18, timeOffset: nil),
                InkPoint(x: 124, y: 28, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 123, y: 4, timeOffset: nil),
                InkPoint(x: 134, y: 17, timeOffset: nil),
                InkPoint(x: 139, y: 29, timeOffset: nil)
            ])
        ]
        let strokes = try transformedTemplateStrokes("D", offsetX: 0, offsetY: 0, scale: 1)
            + transformedTemplateStrokes("#", offsetX: 38, offsetY: -8, scale: 0.72)
            + roundedSevenLookalike
            + transformedTemplateStrokes("#", offsetX: 180, offsetY: -7, scale: 0.72)
            + transformedTemplateStrokes("9", offsetX: 220, offsetY: 0, scale: 0.78)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "D#7(#9)", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("D#7#9"), debugSummary)
    }

    func testRecognizesMajorAlteredExtensionWithoutCandidateExplosion() throws {
        let strokes = try shiftedTemplateStrokes("E", offsetX: 0)
            + shiftedTemplateStrokes("b", offsetX: 0)
            + shiftedTemplateStrokes("△", offsetX: 36)
            + shiftedTemplateStrokes("9", offsetX: -25)
            + shiftedTemplateStrokes("b", offsetX: 108)
            + shiftedTemplateStrokes("5", offsetX: 185)

        let result = recognizer.recognize(strokes: strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Eb△9(b5)", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Eb△9(b5)"), debugSummary)
    }

    func testRecognizesDominantNinthInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { fixture in
                fixture.expectedDisplayText.hasSuffix("9")
                    && !fixture.expectedDisplayText.contains("△")
                    && !fixture.expectedDisplayText.contains("-")
                    && !fixture.expectedDisplayText.contains("(")
            }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, "\(fixture.name) \(debugSummary)")
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizesMinorMajorSeventhInkFixtures() throws {
        let fixtures = try allFixtures()
            .filter { $0.expectedDisplayText.contains("-△7") }

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testMinorSixthDoesNotStealDashMinorOrSuspendedFixtures() throws {
        let fixtureNames = [
            "CMinor7Captured01",
            "CMinor9Captured01",
            "DFlatMinor9Captured01",
            "DSharpm7Captured03",
            "GSharpMinor9",
            "GsusCaptured01"
        ]

        for fixtureName in fixtureNames {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let result = recognizer.recognize(strokes: fixture.strokes)

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, fixture.name)
            XCTAssertGreaterThan(result.confidence, 0, fixture.name)
        }
    }

    func testRecognizerReturnsCandidateScoresForAutoRenderDecisions() throws {
        let result = recognizer.recognize(strokes: try shiftedTemplateStrokes("C", offsetX: 0))

        XCTAssertEqual(result.match?.displayText, "C")
        XCTAssertFalse(result.candidateScores.isEmpty)
        XCTAssertEqual(result.candidateScores.first?.displayText, "C")
        XCTAssertGreaterThan(result.candidateScores.first?.confidence ?? 0, 0)
    }

    func testRecognizerReportsPhaseMetricsForDiagnostics() throws {
        let strokes = try shiftedTemplateStrokes("C", offsetX: 0)
        let result = recognizer.recognize(strokes: strokes)
        let metrics = result.metrics

        XCTAssertEqual(metrics.strokeCount, strokes.count)
        XCTAssertGreaterThan(metrics.clusterCount, 0)
        XCTAssertEqual(metrics.glyphCandidateColumnCount, result.glyphCandidates.count)
        XCTAssertEqual(metrics.rawCandidateCount, result.rawCandidates.count)
        XCTAssertGreaterThan(metrics.compositionMetrics.generatedSequenceCount, 0)
        XCTAssertGreaterThan(metrics.compositionMetrics.maxGeneratedSequences, 0)
        XCTAssertGreaterThanOrEqual(metrics.totalMilliseconds, 0)
    }

    func testResolutionPolicyAutoRendersDecisiveMatches() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.10)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsForCloseRaces() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.77)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertTrue(decision.isCloseRace)
        XCTAssertEqual(decision.competingCandidateText, "G")
    }

    func testResolutionPolicyAutoRendersModerateLiveLoopMargins() throws {
        let result = recognitionResult(
            matchText: "Db-7",
            confidence: 4.35,
            scores: [
                candidateScore("Db-7", confidence: 4.35),
                candidateScore("Bb-7", confidence: 4.29)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "Db-7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsForLowConfidenceMatches() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 3.80,
            scores: [
                candidateScore("C", confidence: 3.80),
                candidateScore("G", confidence: 3.00)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyAutoRendersClearLoopCandidatesBelowOldThreshold() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 3.965,
            scores: [
                candidateScore("C", confidence: 3.965)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyAutoRendersClearSlashWinnerFromLiveLoop() throws {
        let result = recognitionResult(
            matchText: "G/B",
            confidence: 4.9767,
            scores: [
                candidateScore("G/B", confidence: 4.9767),
                candidateScore("G/D", confidence: 4.8564),
                candidateScore("G/A", confidence: 4.8178)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "G/B")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyStillPromptsForTightLiveLoopCollisions() throws {
        let result = recognitionResult(
            matchText: "Db7(b9)",
            confidence: 4.8158,
            scores: [
                candidateScore("Db7(b9)", confidence: 4.8158),
                candidateScore("Db7(b5)", confidence: 4.7952)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "Db7(b9)")
        XCTAssertTrue(decision.isCloseRace)
        XCTAssertEqual(decision.competingCandidateText, "Db7(b5)")
    }

    func testResolutionPolicyAutoRendersCommonSpellingOverUncommonCloseRunnerUp() throws {
        let result = recognitionResult(
            matchText: "F#",
            confidence: 3.9796,
            scores: [
                candidateScore("F#", confidence: 3.9796),
                candidateScore("B#", confidence: 3.9324)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .autoRender)
        XCTAssertEqual(decision.acceptedText, "F#")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyStillPromptsWhenUncommonSpellingIsTheWinner() throws {
        let result = recognitionResult(
            matchText: "B#",
            confidence: 3.9796,
            scores: [
                candidateScore("B#", confidence: 3.9796),
                candidateScore("F#", confidence: 3.9324)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "B#")
        XCTAssertTrue(decision.isCloseRace)
        XCTAssertEqual(decision.competingCandidateText, "F#")
    }

    func testResolutionPolicyPromptsWhenNoSupportedChordIsRead() {
        let result = recognitionResult(
            matchText: nil,
            confidence: 0,
            scores: [
                ChordInkCandidateScore(text: "EGG", displayText: nil, confidence: 3.80)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertNil(decision.acceptedText)
        XCTAssertFalse(decision.isCloseRace)
    }

    func testChordInkContinuationGraceWaitsForRootAndExtensionPrefixes() {
        XCTAssertTrue(
            ChordInkContinuationGracePolicy.shouldWaitForPossibleContinuation(
                result: recognitionResult(
                    matchText: "A",
                    confidence: 4.2,
                    scores: [candidateScore("A", confidence: 4.2)]
                ),
                strokeCount: 2
            )
        )

        XCTAssertTrue(
            ChordInkContinuationGracePolicy.shouldWaitForPossibleContinuation(
                result: recognitionResult(
                    matchText: "A9",
                    confidence: 4.2,
                    scores: [candidateScore("A9", confidence: 4.2)]
                ),
                strokeCount: 4
            )
        )
    }

    func testChordInkContinuationGraceDoesNotWaitOnceAlterationIsPresent() {
        XCTAssertFalse(
            ChordInkContinuationGracePolicy.shouldWaitForPossibleContinuation(
                result: recognitionResult(
                    matchText: "A9(#5)",
                    confidence: 4.2,
                    scores: [candidateScore("A9(#5)", confidence: 4.2)]
                ),
                strokeCount: 7
            )
        )
    }

    func testSuccessCriteriaFixturesArePresent() throws {
        let fixtures = try allFixtures()
        let displayTexts = Set(fixtures.map(\.expectedDisplayText))

        XCTAssertTrue(displayTexts.isSuperset(of: ["C", "Bb", "F#", "C-", "C-7", "Db7(b9)", "G/B"]))
    }

    func testRecognizerReturnsDebugDataWhenInkCannotMatchAChord() {
        let result = recognizer.recognize(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 10, timeOffset: 0),
                InkPoint(x: 18, y: 18, timeOffset: 0.1)
            ])
        ])

        XCTAssertNil(result.match)
        XCTAssertFalse(result.glyphCandidates.isEmpty)
        XCTAssertFalse(result.rawCandidates.isEmpty)
        XCTAssertEqual(result.confidence, 0)
    }

    private func shiftedTemplateStrokes(_ text: String, offsetX: Double) throws -> [InkStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text })
        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x + offsetX,
                        y: point.y,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func transformedTemplateStrokes(
        _ text: String,
        offsetX: Double,
        offsetY: Double,
        scale: Double
    ) throws -> [InkStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text })
        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x * scale + offsetX,
                        y: point.y * scale + offsetY,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func recognitionResult(
        matchText: String?,
        confidence: Double,
        scores: [ChordInkCandidateScore]
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: scores.map(\.text),
            glyphCandidates: [],
            match: matchText.flatMap(ChordRecognitionCompendium.match),
            confidence: confidence,
            candidateScores: scores
        )
    }

    private func candidateScore(_ text: String, confidence: Double) -> ChordInkCandidateScore {
        let match = ChordRecognitionCompendium.match(text)
        return ChordInkCandidateScore(
            text: text,
            displayText: match?.displayText,
            confidence: confidence
        )
    }

    private func allFixtures() throws -> [InkFixture] {
        try Self.fixtureCorpus.get()
    }
}

private extension InkFixture {
    var allowsCompactSemanticRecognition: Bool {
        expectedDisplayText.contains("(#11)")
            || expectedDisplayText.contains("7alt")
    }
}
