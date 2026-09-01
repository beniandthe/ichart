import XCTest
@testable import iChart

final class ChordInkRecognizerTests: XCTestCase {
    private static let defaultFixtureCorpus: Result<[InkFixture], Error> = Result {
        try InkFixtureLoader.loadDefaultRegressionFixtures(file: #filePath)
    }
    private static let fullArchiveFixtureCorpus: Result<[InkFixture], Error> = Result {
        try InkFixtureLoader.loadAll(file: #filePath)
    }

    private let recognizer = ChordInkRecognizer()

    func testCandidateScoresKeepSupportedCandidatesBeyondRawTopEight() {
        let unsupportedNoise = [
            "E3",
            "E2",
            "E4",
            "E5",
            "E8",
            "E10",
            "Db7(b9)(b9)",
            "Cø9"
        ].enumerated().map { index, text in
            ChordInkCandidate(
                text: text,
                confidence: 5.0 - (Double(index) * 0.01),
                glyphCandidates: []
            )
        }
        let supportedCandidates = [
            ChordInkCandidate(text: "Db7b9", confidence: 3.93, glyphCandidates: []),
            ChordInkCandidate(text: "G/B", confidence: 3.92, glyphCandidates: [])
        ]

        let scores = ChordInkRecognizer.candidateScores(
            from: unsupportedNoise + supportedCandidates,
            minimumConfidence: 3.91,
            match: ChordRecognitionCompendium.match
        )
        let supportedDisplayTexts = ChordInkRecognitionPolicy
            .rankedSupportedScores(
                for: ChordInkRecognitionResult(
                    rawCandidates: [],
                    glyphCandidates: [],
                    match: nil,
                    confidence: 0,
                    candidateScores: scores
                )
            )
            .compactMap(\.displayText)

        XCTAssertEqual(scores.prefix(8).filter { $0.displayText == nil }.count, 8)
        XCTAssertTrue(supportedDisplayTexts.contains("Db7(b9)"))
        XCTAssertTrue(supportedDisplayTexts.contains("G/B"))
    }

    func testChordInkBatchClustererSplitsClearlySeparatedChordGroups() {
        let clusters = ChordInkBatchClusterer.clusters(
            for: [
                testStroke(minX: 0, maxX: 12),
                testStroke(minX: 18, maxX: 30),
                testStroke(minX: 88, maxX: 100),
                testStroke(minX: 108, maxX: 120)
            ]
        )

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].strokeIndices, [0, 1])
        XCTAssertEqual(clusters[1].strokeIndices, [2, 3])
    }

    func testChordInkBatchClustererKeepsOneChordCharactersTogether() {
        let clusters = ChordInkBatchClusterer.clusters(
            for: [
                testStroke(minX: 0, maxX: 12),
                testStroke(minX: 24, maxX: 36),
                testStroke(minX: 49, maxX: 62)
            ]
        )

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].strokeIndices, [0, 1, 2])
    }

    func testRecognizesDefaultRegressionFixturesThroughPureSwiftPipeline() throws {
        try assertRecognizes(fixtures: allFixtures())
    }

    func testRecognizesFullInkFixtureArchiveWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to run the full ink fixture archive."
        )
        try assertRecognizes(fixtures: fullArchiveFixtures())
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

    func testDeviceDFlatDiminishedRacePrefersRootAccidentalButRequiresConfirmation() throws {
        let fixture = try InkFixtureLoader.load("DFlatDiminishedRaceDevice01", file: #filePath)
        let result = recognizer.recognize(strokes: fixture.strokes)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let rankedDisplayTexts = ChordInkRecognitionPolicy
            .rankedSupportedScores(for: result)
            .compactMap(\.displayText)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), scores: \(result.candidateScores.prefix(8)), decision: \(decision)"

        XCTAssertEqual(result.match?.displayText, "Db", debugSummary)
        XCTAssertEqual(decision.acceptedText, "Db", debugSummary)
        XCTAssertEqual(decision.action, .confirm, debugSummary)
        XCTAssertTrue(rankedDisplayTexts.contains("D°"), debugSummary)
    }

    func testDeviceInitialDMinorSevenNoReadBecomesConservativeSupportedRead() throws {
        let fixture = try InkFixtureLoader.load("DMinor7InitialNoReadDevice01", file: #filePath)
        let result = recognizer.recognize(strokes: fixture.strokes)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let rankedDisplayTexts = ChordInkRecognitionPolicy
            .rankedSupportedScores(for: result)
            .compactMap(\.displayText)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8)), decision: \(decision)"

        XCTAssertEqual(result.match?.displayText, "D-7", debugSummary)
        XCTAssertEqual(decision.acceptedText, "D-7", debugSummary)
        XCTAssertEqual(decision.action, .confirm, debugSummary)
        XCTAssertEqual(rankedDisplayTexts.first, "D-7", debugSummary)
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

    func testRecognizesChordRepeatSymbolFromDotSlashDotInk() throws {
        let strokes = try shiftedTemplateStrokes("•", offsetX: 0)
            + shiftedTemplateStrokes("/", offsetX: 35)
            + shiftedTemplateStrokes("•", offsetX: 90)

        let result = recognizer.recognize(strokes: strokes)

        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) })"

        XCTAssertEqual(result.match?.displayText, "•/•", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("•/•"), debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, 3)
    }

    func testRecognizesChordRepeatSymbolWhenInkIsCloseAndStrokeOrderVaries() {
        let slash = InkStroke(points: [
            InkPoint(x: 30, y: 58, timeOffset: nil),
            InkPoint(x: 39, y: 36, timeOffset: nil),
            InkPoint(x: 51, y: 10, timeOffset: nil)
        ])
        let lowerDot = InkStroke(points: [
            InkPoint(x: 52, y: 45, timeOffset: nil),
            InkPoint(x: 56, y: 42, timeOffset: nil),
            InkPoint(x: 60, y: 45, timeOffset: nil),
            InkPoint(x: 59, y: 50, timeOffset: nil),
            InkPoint(x: 54, y: 51, timeOffset: nil),
            InkPoint(x: 52, y: 48, timeOffset: nil)
        ])
        let upperDot = InkStroke(points: [
            InkPoint(x: 19, y: 17, timeOffset: nil),
            InkPoint(x: 23, y: 13, timeOffset: nil),
            InkPoint(x: 28, y: 15, timeOffset: nil),
            InkPoint(x: 29, y: 20, timeOffset: nil),
            InkPoint(x: 24, y: 22, timeOffset: nil),
            InkPoint(x: 20, y: 20, timeOffset: nil)
        ])

        let result = recognizer.recognize(strokes: [slash, lowerDot, upperDot])

        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) })"

        XCTAssertEqual(result.match?.displayText, "•/•", debugSummary)
        XCTAssertEqual(result.rawCandidates.first, "•/•", debugSummary)
        XCTAssertGreaterThanOrEqual(result.confidence, 4.90, debugSummary)
    }

    func testChordRepeatRecognitionCanBeTrustedWithoutRootEvidence() {
        let result = recognitionResult(
            matchText: "•/•",
            confidence: 4.95,
            scores: [candidateScore("•/•", confidence: 4.95)],
            glyphCandidates: [
                [glyph("•", confidence: 0.94)],
                [glyph("/", confidence: 0.94)],
                [glyph("•", confidence: 0.94)]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
        XCTAssertEqual(decision.acceptedText, "•/•")
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

    func testDeviceSplitTriangleMajorSevenDoesNotBecomeHalfDiminished() {
        let result = recognizer.recognize(strokes: deviceSplitTriangleMajorSevenStrokes())
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Bb△7", debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Bb△7"), debugSummary)
        XCTAssertFalse(Array(result.rawCandidates.prefix(8)).contains("Bbø7"), debugSummary)
    }

    func testCurrentDeviceSplitTriangleMajorSevenDoesNotBecomeSlashAlteration() throws {
        let fixture = try InkFixtureLoader.load("BFlatMajor7SplitTriangleDevice02", file: #filePath)
        let result = recognizer.recognize(strokes: fixture.strokes)
        let debugSummary = "raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(result.glyphCandidates.map { $0.prefix(8).map(\.text) }), scores: \(result.candidateScores.prefix(8))"

        XCTAssertEqual(result.match?.displayText, "Bb△7", debugSummary)
        XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, debugSummary)
        XCTAssertTrue(result.rawCandidates.contains("Bb△7"), debugSummary)
        XCTAssertFalse(Array(result.rawCandidates.prefix(8)).contains("Bb/C"), debugSummary)
        XCTAssertFalse(Array(result.rawCandidates.prefix(8)).contains("Bb9b5"), debugSummary)
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

    func testRecognizerReturnsCandidateScoresForTrustedCandidateDecisions() throws {
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

    func testResolutionPolicyTrustsDecisiveMatches() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 4.80,
            scores: [
                candidateScore("C", confidence: 4.80),
                candidateScore("G", confidence: 4.10)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
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

    func testResolutionPolicyTrustsModerateLiveLoopMargins() throws {
        let result = recognitionResult(
            matchText: "Db-7",
            confidence: 4.35,
            scores: [
                candidateScore("Db-7", confidence: 4.35),
                candidateScore("Bb-7", confidence: 4.29)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
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

    func testResolutionPolicyTrustsClearLoopCandidatesBelowOldThreshold() throws {
        let result = recognitionResult(
            matchText: "C",
            confidence: 3.965,
            scores: [
                candidateScore("C", confidence: 3.965)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
        XCTAssertEqual(decision.acceptedText, "C")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsForSingleCandidateWhenRootGlyphIsWeakAndAmbiguous() throws {
        let result = recognitionResult(
            matchText: "B7",
            confidence: 3.953,
            scores: [
                candidateScore("B7", confidence: 3.953)
            ],
            glyphCandidates: [
                [
                    glyph("B", confidence: 0.680),
                    glyph("F", confidence: 0.637),
                    glyph("D", confidence: 0.636),
                    glyph("A", confidence: 0.476)
                ],
                [
                    glyph("7", confidence: 0.985)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "B7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsWhenRootGlyphRaceIsCloseDespiteDecisiveChordScore() throws {
        let result = recognitionResult(
            matchText: "D/F#",
            confidence: 4.960,
            scores: [
                candidateScore("D/F#", confidence: 4.960),
                candidateScore("B/F#", confidence: 4.410)
            ],
            glyphCandidates: [
                [
                    glyph("D", confidence: 0.718),
                    glyph("B", confidence: 0.748),
                    glyph("F", confidence: 0.610)
                ],
                [
                    glyph("/", confidence: 0.980)
                ],
                [
                    glyph("F", confidence: 0.960)
                ],
                [
                    glyph("#", confidence: 0.950)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "D/F#")
        XCTAssertTrue(decision.isCloseRace)
        XCTAssertEqual(decision.competingCandidateText, "B")
        XCTAssertEqual(try XCTUnwrap(decision.confidenceGap), 0.030, accuracy: 0.0001)
    }

    func testResolutionPolicyTrustsWhenAcceptedRootGlyphIsClearDespiteAlternateChordScore() throws {
        let result = recognitionResult(
            matchText: "D/F#",
            confidence: 4.960,
            scores: [
                candidateScore("D/F#", confidence: 4.960),
                candidateScore("B/F#", confidence: 4.410)
            ],
            glyphCandidates: [
                [
                    glyph("D", confidence: 0.910),
                    glyph("B", confidence: 0.748),
                    glyph("F", confidence: 0.610)
                ],
                [
                    glyph("/", confidence: 0.980)
                ],
                [
                    glyph("F", confidence: 0.960)
                ],
                [
                    glyph("#", confidence: 0.950)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
        XCTAssertEqual(decision.acceptedText, "D/F#")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyStillTrustsSingleCandidateWithStrongRootGlyph() throws {
        let result = recognitionResult(
            matchText: "C7",
            confidence: 4.120,
            scores: [
                candidateScore("C7", confidence: 4.120)
            ],
            glyphCandidates: [
                [
                    glyph("C", confidence: 0.965),
                    glyph("G", confidence: 0.621)
                ],
                [
                    glyph("7", confidence: 0.985)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
        XCTAssertEqual(decision.acceptedText, "C7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsWhenRootEvidenceIsMissingFromGlyphs() throws {
        let result = recognitionResult(
            matchText: "C7",
            confidence: 4.120,
            scores: [
                candidateScore("C7", confidence: 4.120)
            ],
            glyphCandidates: [
                [
                    glyph("G", confidence: 0.965),
                    glyph("D", confidence: 0.940)
                ],
                [
                    glyph("7", confidence: 0.985)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsWhenGeneratedSequenceLimitWasHit() throws {
        var metrics = ChordInkRecognitionMetrics()
        metrics.compositionMetrics = ChordInkCandidateCompositionMetrics(
            selectedColumnCount: 7,
            generatedSequenceCount: 4096,
            returnedCandidateCount: 32,
            maxGeneratedSequences: 4096,
            hitGeneratedSequenceLimit: true
        )
        let result = recognitionResult(
            matchText: "C7",
            confidence: 4.120,
            scores: [
                candidateScore("C7", confidence: 4.120)
            ],
            glyphCandidates: [
                [
                    glyph("C", confidence: 0.965),
                    glyph("G", confidence: 0.621)
                ],
                [
                    glyph("7", confidence: 0.985)
                ]
            ],
            metrics: metrics
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyPromptsWhenUnsupportedCandidateHasHighPressure() throws {
        let result = recognitionResult(
            matchText: "C7",
            confidence: 4.120,
            scores: [
                ChordInkCandidateScore(text: "C7add9add9", displayText: nil, confidence: 4.125),
                candidateScore("C7", confidence: 4.120)
            ],
            glyphCandidates: [
                [
                    glyph("C", confidence: 0.965),
                    glyph("G", confidence: 0.621)
                ],
                [
                    glyph("7", confidence: 0.985)
                ]
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .confirm)
        XCTAssertEqual(decision.acceptedText, "C7")
        XCTAssertFalse(decision.isCloseRace)
    }

    func testResolutionPolicyTrustsClearSlashWinnerFromLiveLoop() throws {
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

        XCTAssertEqual(decision.action, .trusted)
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

    func testResolutionPolicyTrustsCommonSpellingOverUncommonCloseRunnerUp() throws {
        let result = recognitionResult(
            matchText: "F#",
            confidence: 3.9796,
            scores: [
                candidateScore("F#", confidence: 3.9796),
                candidateScore("B#", confidence: 3.9324)
            ]
        )

        let decision = ChordInkRecognitionPolicy.decision(for: result)

        XCTAssertEqual(decision.action, .trusted)
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

    private func deviceSplitTriangleMajorSevenStrokes() -> [InkStroke] {
        [
            InkStroke(points: [
                InkPoint(x: 31.396404266357422, y: 44.16988754272461, timeOffset: nil),
                InkPoint(x: 31.396404266357422, y: 46.08440017700195, timeOffset: nil),
                InkPoint(x: 31.462312698364258, y: 48.32902145385742, timeOffset: nil),
                InkPoint(x: 31.6600399017334, y: 49.91342544555664, timeOffset: nil),
                InkPoint(x: 31.923688888549805, y: 51.95998764038086, timeOffset: nil),
                InkPoint(x: 32.121429443359375, y: 54.46864318847656, timeOffset: nil),
                InkPoint(x: 32.25324630737305, y: 57.043338775634766, timeOffset: nil),
                InkPoint(x: 32.319156646728516, y: 59.816062927246094, timeOffset: nil),
                InkPoint(x: 32.385074615478516, y: 62.58881759643555, timeOffset: nil),
                InkPoint(x: 32.450984954833984, y: 65.36154174804688, timeOffset: nil),
                InkPoint(x: 32.450984954833984, y: 68.06829071044922, timeOffset: nil),
                InkPoint(x: 32.450984954833984, y: 70.84101104736328, timeOffset: nil),
                InkPoint(x: 32.450984954833984, y: 72.8875732421875, timeOffset: nil),
                InkPoint(x: 32.51689529418945, y: 76.05641174316406, timeOffset: nil),
                InkPoint(x: 32.648712158203125, y: 78.03693389892578, timeOffset: nil),
                InkPoint(x: 33.966941833496094, y: 79.81942749023438, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 29.287229537963867, y: 47.40476989746094, timeOffset: nil),
                InkPoint(x: 28.232648849487305, y: 45.490257263183594, timeOffset: nil),
                InkPoint(x: 29.74861717224121, y: 44.499996185302734, timeOffset: nil),
                InkPoint(x: 31.85778045654297, y: 43.83980941772461, timeOffset: nil),
                InkPoint(x: 35.021522521972656, y: 43.311676025390625, timeOffset: nil),
                InkPoint(x: 37.657981872558594, y: 42.915557861328125, timeOffset: nil),
                InkPoint(x: 39.1739387512207, y: 42.717498779296875, timeOffset: nil),
                InkPoint(x: 43.32636642456055, y: 42.453433990478516, timeOffset: nil),
                InkPoint(x: 45.83099365234375, y: 42.453433990478516, timeOffset: nil),
                InkPoint(x: 48.006065368652344, y: 42.519439697265625, timeOffset: nil),
                InkPoint(x: 49.39020538330078, y: 43.113616943359375, timeOffset: nil),
                InkPoint(x: 50.444786071777344, y: 44.63201141357422, timeOffset: nil),
                InkPoint(x: 50.444786071777344, y: 46.54652404785156, timeOffset: nil),
                InkPoint(x: 49.45612716674805, y: 47.9989128112793, timeOffset: nil),
                InkPoint(x: 48.07198715209961, y: 49.71536636352539, timeOffset: nil),
                InkPoint(x: 46.2923698425293, y: 51.299800872802734, timeOffset: nil),
                InkPoint(x: 44.31503677368164, y: 52.95024871826172, timeOffset: nil),
                InkPoint(x: 41.283111572265625, y: 55.260841369628906, timeOffset: nil),
                InkPoint(x: 38.910301208496094, y: 56.91128921508789, timeOffset: nil),
                InkPoint(x: 37.06477737426758, y: 58.033599853515625, timeOffset: nil),
                InkPoint(x: 39.76714324951172, y: 57.76953125, timeOffset: nil),
                InkPoint(x: 41.283111572265625, y: 57.70352554321289, timeOffset: nil),
                InkPoint(x: 42.99680709838867, y: 57.70352554321289, timeOffset: nil),
                InkPoint(x: 44.71050262451172, y: 57.76953125, timeOffset: nil),
                InkPoint(x: 46.35829162597656, y: 58.36367416381836, timeOffset: nil),
                InkPoint(x: 47.940155029296875, y: 59.485984802246094, timeOffset: nil),
                InkPoint(x: 49.19247817993164, y: 61.00437927246094, timeOffset: nil),
                InkPoint(x: 50.11524200439453, y: 62.91889190673828, timeOffset: nil),
                InkPoint(x: 50.64252471923828, y: 65.36154174804688, timeOffset: nil),
                InkPoint(x: 50.70843505859375, y: 67.93624114990234, timeOffset: nil),
                InkPoint(x: 50.2470588684082, y: 71.96331787109375, timeOffset: nil),
                InkPoint(x: 49.258384704589844, y: 74.07588958740234, timeOffset: nil),
                InkPoint(x: 47.940155029296875, y: 75.92436218261719, timeOffset: nil),
                InkPoint(x: 46.2923698425293, y: 77.5748062133789, timeOffset: nil),
                InkPoint(x: 44.57867431640625, y: 78.49906158447266, timeOffset: nil),
                InkPoint(x: 42.53541946411133, y: 79.09320068359375, timeOffset: nil),
                InkPoint(x: 40.096702575683594, y: 79.42330932617188, timeOffset: nil),
                InkPoint(x: 37.85572052001953, y: 79.42330932617188, timeOffset: nil),
                InkPoint(x: 35.68063735961914, y: 79.291259765625, timeOffset: nil),
                InkPoint(x: 33.439659118652344, y: 78.49906158447266, timeOffset: nil),
                InkPoint(x: 31.85778045654297, y: 77.5748062133789, timeOffset: nil),
                InkPoint(x: 30.737289428710938, y: 76.51853942871094, timeOffset: nil),
                InkPoint(x: 30.209993362426758, y: 74.6040267944336, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 59.34283447265625, y: 34.59735870361328, timeOffset: nil),
                InkPoint(x: 59.606468200683594, y: 36.115753173828125, timeOffset: nil),
                InkPoint(x: 59.93602752685547, y: 38.16228103637695, timeOffset: nil),
                InkPoint(x: 60.79288101196289, y: 43.113616943359375, timeOffset: nil),
                InkPoint(x: 61.320167541503906, y: 45.688316345214844, timeOffset: nil),
                InkPoint(x: 61.84746170043945, y: 48.52704620361328, timeOffset: nil),
                InkPoint(x: 62.11111068725586, y: 50.11148452758789, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 61.320167541503906, y: 44.896080017089844, timeOffset: nil),
                InkPoint(x: 62.37474822998047, y: 43.7738037109375, timeOffset: nil),
                InkPoint(x: 64.41799926757812, y: 42.915557861328125, timeOffset: nil),
                InkPoint(x: 66.79080963134766, y: 42.849552154541016, timeOffset: nil),
                InkPoint(x: 68.37268829345703, y: 43.17962646484375, timeOffset: nil),
                InkPoint(x: 69.62500762939453, y: 44.56600570678711, timeOffset: nil),
                InkPoint(x: 70.02047729492188, y: 46.15044021606445, timeOffset: nil),
                InkPoint(x: 69.9545669555664, y: 48.262977600097656, timeOffset: nil),
                InkPoint(x: 68.57042694091797, y: 49.38528823852539, timeOffset: nil),
                InkPoint(x: 66.52717590332031, y: 49.91342544555664, timeOffset: nil),
                InkPoint(x: 63.03386306762695, y: 49.91342544555664, timeOffset: nil),
                InkPoint(x: 61.320167541503906, y: 48.72510528564453, timeOffset: nil),
                InkPoint(x: 60.72697067260742, y: 47.33872604370117, timeOffset: nil)
            ]),
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
            ]),
            InkStroke(points: [
                InkPoint(x: 95.85772705078125, y: 33.87116622924805, timeOffset: nil),
                InkPoint(x: 96.97823333740234, y: 32.35273742675781, timeOffset: nil),
                InkPoint(x: 98.8896713256836, y: 31.824602127075195, timeOffset: nil),
                InkPoint(x: 100.60335540771484, y: 31.626543045043945, timeOffset: nil),
                InkPoint(x: 102.6466064453125, y: 31.560535430908203, timeOffset: nil),
                InkPoint(x: 105.87626647949219, y: 31.560535430908203, timeOffset: nil),
                InkPoint(x: 107.5240478515625, y: 31.560535430908203, timeOffset: nil),
                InkPoint(x: 108.97411346435547, y: 32.15467834472656, timeOffset: nil),
                InkPoint(x: 109.1059341430664, y: 33.80512237548828, timeOffset: nil),
                InkPoint(x: 108.51272583007812, y: 35.521575927734375, timeOffset: nil),
                InkPoint(x: 107.12859344482422, y: 38.22832489013672, timeOffset: nil),
                InkPoint(x: 106.0739974975586, y: 40.53892135620117, timeOffset: nil),
                InkPoint(x: 105.54672241210938, y: 42.38742446899414, timeOffset: nil)
            ])
        ]
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
        scores: [ChordInkCandidateScore],
        glyphCandidates: [[GlyphCandidate]] = [],
        metrics: ChordInkRecognitionMetrics = ChordInkRecognitionMetrics()
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: scores.map(\.text),
            glyphCandidates: glyphCandidates,
            match: matchText.flatMap(ChordRecognitionCompendium.match),
            confidence: confidence,
            candidateScores: scores,
            metrics: metrics
        )
    }

    private func glyph(_ text: String, confidence: Double) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: .template)
    }

    private func candidateScore(_ text: String, confidence: Double) -> ChordInkCandidateScore {
        let match = ChordRecognitionCompendium.match(text)
        return ChordInkCandidateScore(
            text: text,
            displayText: match?.displayText,
            confidence: confidence
        )
    }

    private func testStroke(minX: Double, maxX: Double) -> InkStroke {
        InkStroke(
            points: [
                InkPoint(x: minX, y: 0, timeOffset: nil),
                InkPoint(x: maxX, y: 42, timeOffset: nil)
            ]
        )
    }

    private func allFixtures() throws -> [InkFixture] {
        try Self.defaultFixtureCorpus.get()
    }

    private func fullArchiveFixtures() throws -> [InkFixture] {
        try Self.fullArchiveFixtureCorpus.get()
    }

    private func assertRecognizes(fixtures: [InkFixture]) throws {
        for fixture in fixtures {
            let result = recognizer.recognize(strokes: fixture.strokes)
            let glyphSummary = result.glyphCandidates.map { group in
                group.prefix(8).map { "\($0.text):\($0.confidence)" }
            }
            let debugSummary = "\(fixture.name) raw: \(Array(result.rawCandidates.prefix(16))), glyphs: \(glyphSummary), scores: \(result.candidateScores.prefix(8))"

            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, debugSummary)
            XCTAssertFalse(result.rawCandidates.isEmpty, debugSummary)
            if !fixture.allowsCompactSemanticRecognition {
                XCTAssertEqual(result.glyphCandidates.count, fixture.expectedClusterCount, debugSummary)
            }
            XCTAssertGreaterThan(result.confidence, 0, debugSummary)
        }
    }
}

private extension InkFixture {
    var allowsCompactSemanticRecognition: Bool {
        expectedDisplayText.contains("(#11)")
            || expectedDisplayText.contains("7alt")
    }
}
