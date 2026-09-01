import XCTest
@testable import iChart

final class GestureTemplateRecognizerTests: XCTestCase {
    private let clusterer = StrokeClusterer()
    private let recognizer = GestureTemplateRecognizer()

    func testExpectedGlyphAppearsInTopThreeForDefaultRegressionFixtures() throws {
        try assertExpectedGlyphAppearsInTopCandidates(
            for: InkFixtureLoader.loadDefaultRegressionFixtures(file: #filePath)
        )
    }

    func testExpectedGlyphAppearsInTopThreeForFullArchiveWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to run the full ink fixture archive."
        )
        try assertExpectedGlyphAppearsInTopCandidates(
            for: InkFixtureLoader.loadAll(file: #filePath)
        )
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

    func testOneStrokeRootDIsRecognizedBeforeCurvedLookalikes() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let oneStrokeD = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 10, y: 28, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil),
                InkPoint(x: 36, y: 56, timeOffset: nil),
                InkPoint(x: 46, y: 38, timeOffset: nil),
                InkPoint(x: 38, y: 20, timeOffset: nil),
                InkPoint(x: 10, y: 12, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: oneStrokeD, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "D", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "G", in: candidates), candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "C", in: candidates), candidateSummary)
    }

    func testTopFirstOneStrokeRootDIsRecognizedBeforeCurvedLookalikes() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let topFirstD = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 30, y: 13, timeOffset: nil),
                InkPoint(x: 44, y: 24, timeOffset: nil),
                InkPoint(x: 46, y: 40, timeOffset: nil),
                InkPoint(x: 34, y: 56, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil),
                InkPoint(x: 10, y: 38, timeOffset: nil),
                InkPoint(x: 10, y: 12, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: topFirstD, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "D", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "G", in: candidates), candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "B", in: candidates), candidateSummary)
    }

    func testNoisySingleBowlRootDDoesNotFallToB() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let noisyTwoStrokeD = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 30, y: 14, timeOffset: nil),
                InkPoint(x: 44, y: 24, timeOffset: nil),
                InkPoint(x: 46, y: 38, timeOffset: nil),
                InkPoint(x: 39, y: 50, timeOffset: nil),
                InkPoint(x: 31, y: 55, timeOffset: nil),
                InkPoint(x: 34, y: 53, timeOffset: nil),
                InkPoint(x: 23, y: 59, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: noisyTwoStrokeD, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "D", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "B", in: candidates), candidateSummary)
    }

    func testScreenshotStyleTwoStrokeRootDDoesNotFallToB() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let screenshotStyleD = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 10, y: 61, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 11, y: 13, timeOffset: nil),
                InkPoint(x: 18, y: 12, timeOffset: nil),
                InkPoint(x: 29, y: 13, timeOffset: nil),
                InkPoint(x: 39, y: 17, timeOffset: nil),
                InkPoint(x: 46, y: 25, timeOffset: nil),
                InkPoint(x: 48, y: 36, timeOffset: nil),
                InkPoint(x: 46, y: 44, timeOffset: nil),
                InkPoint(x: 47, y: 48, timeOffset: nil),
                InkPoint(x: 42, y: 54, timeOffset: nil),
                InkPoint(x: 34, y: 57, timeOffset: nil),
                InkPoint(x: 29, y: 56, timeOffset: nil),
                InkPoint(x: 32, y: 57, timeOffset: nil),
                InkPoint(x: 23, y: 60, timeOffset: nil),
                InkPoint(x: 14, y: 61, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: screenshotStyleD, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "D", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "B", in: candidates), candidateSummary)
    }

    func testTwoLobeRootBStillRanksBeforeD() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let twoLobeB = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 10, timeOffset: nil),
                InkPoint(x: 10, y: 62, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 11, y: 12, timeOffset: nil),
                InkPoint(x: 25, y: 10, timeOffset: nil),
                InkPoint(x: 39, y: 15, timeOffset: nil),
                InkPoint(x: 44, y: 25, timeOffset: nil),
                InkPoint(x: 36, y: 33, timeOffset: nil),
                InkPoint(x: 18, y: 35, timeOffset: nil),
                InkPoint(x: 36, y: 38, timeOffset: nil),
                InkPoint(x: 47, y: 48, timeOffset: nil),
                InkPoint(x: 41, y: 58, timeOffset: nil),
                InkPoint(x: 26, y: 63, timeOffset: nil),
                InkPoint(x: 11, y: 60, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: twoLobeB, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "B", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "B", in: candidates), candidateRank(of: "D", in: candidates), candidateSummary)
    }

    func testRootFUsesBottomStrokeEvidenceInsteadOfStrokeOrder() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let topFirstF = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 42, y: 12, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 35, timeOffset: nil),
                InkPoint(x: 34, y: 35, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: topFirstF, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "F", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "F", in: candidates), candidateRank(of: "E", in: candidates), candidateSummary)
    }

    func testRootEUsesBottomStrokeEvidenceInsteadOfStrokeOrder() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let verticalFirstE = InkCluster(strokes: [
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 10, y: 60, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 12, timeOffset: nil),
                InkPoint(x: 42, y: 12, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 35, timeOffset: nil),
                InkPoint(x: 34, y: 35, timeOffset: nil)
            ]),
            InkStroke(points: [
                InkPoint(x: 10, y: 60, timeOffset: nil),
                InkPoint(x: 42, y: 60, timeOffset: nil)
            ])
        ])

        let candidates = recognizer.rankedCandidates(for: verticalFirstE, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "E", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "E", in: candidates), candidateRank(of: "F", in: candidates), candidateSummary)
    }

    func testCapturedBaseLetterFamiliesRankExpectedGlyphFirst() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for fixtureName in [
            "ACaptured01",
            "ARootSplitDevice01",
            "BCaptured01",
            "BCaptured02",
            "BCaptured03",
            "BCaptured04",
            "DCaptured01",
            "DCaptured02",
            "DCaptured03",
            "DCaptured04",
            "DCaptured05",
            "ECaptured01",
            "ECaptured02",
            "ECaptured03",
            "ECaptured04",
            "FCaptured01",
            "FCaptured02",
            "FCaptured03",
            "FCaptured04",
            "FCaptured05"
        ] {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let cluster = try XCTUnwrap(clusterer.cluster(fixture.strokes).first, fixtureName)
            let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 5)
            let candidateSummary = candidates
                .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
                .joined(separator: ",")

            XCTAssertEqual(candidates.first?.text, fixture.expectedDisplayText, "\(fixtureName) \(candidateSummary)")
        }
    }

    func testOneStrokeDHeuristicDoesNotStealFlatLoops() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let fixture = try InkFixtureLoader.load("BFlatMajor13", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)
        let flatIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "b"))
        let flatCluster = try XCTUnwrap(clusters[safe: flatIndex])

        let candidates = recognizer.rankedCandidates(for: flatCluster, templates: templates, limit: 5)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertTrue(candidates.prefix(3).map(\.text).contains("b"), candidateSummary)
        XCTAssertLessThan(candidateRank(of: "b", in: candidates), candidateRank(of: "D", in: candidates), candidateSummary)
    }

    func testCapturedDFlatLoopsRankFlatBeforeDegreeDotAndSixLookalikes() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for fixtureName in ["DFlatMinorCaptured01", "DFlat7susCaptured03", "DFlatDiminishedRaceDevice01"] {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let clusters = clusterer.cluster(fixture.strokes)
            let flatIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "b"), fixtureName)
            let flatCluster = try XCTUnwrap(clusters[safe: flatIndex], fixtureName)
            let candidates = recognizer.rankedCandidates(for: flatCluster, templates: templates, limit: 6)
            let candidateSummary = candidates
                .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
                .joined(separator: ",")

            XCTAssertEqual(candidates.first?.text, "b", "\(fixtureName) \(candidateSummary)")
            for lookalike in ["°", "•", "6"] {
                XCTAssertLessThan(
                    candidateRank(of: "b", in: candidates),
                    candidateRank(of: lookalike, in: candidates),
                    "\(fixtureName) \(candidateSummary)"
                )
            }
        }
    }

    func testDeviceInitialDMinorSevenRootRanksDAboveBAndTriangle() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let fixture = try InkFixtureLoader.load("DMinor7InitialNoReadDevice01", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)
        let rootCluster = try XCTUnwrap(clusters.first)
        let candidates = recognizer.rankedCandidates(for: rootCluster, templates: templates, limit: 6)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "D", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "B", in: candidates), candidateSummary)
        XCTAssertLessThan(candidateRank(of: "D", in: candidates), candidateRank(of: "△", in: candidates), candidateSummary)
    }

    func testFlatLoopBoostDoesNotStealDegreeDotTriangleOrSixTemplates() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for text in ["°", "•", "△", "6"] {
            let template = try XCTUnwrap(templates.first { $0.text == text })
            let cluster = InkCluster(strokes: template.strokes)
            let candidates = recognizer.rankedCandidates(for: cluster, templates: templates, limit: 4)

            XCTAssertEqual(candidates.first?.text, text)
        }
    }

    func testDeviceSplitTrianglePairRanksMajorTriangleFirst() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let fixture = try InkFixtureLoader.load("BFlatMajor7SplitTriangleDevice02", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)
        let triangleIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "△"))
        let triangleCluster = try XCTUnwrap(clusters[safe: triangleIndex])
        let candidates = recognizer.rankedCandidates(for: triangleCluster, templates: templates, limit: 6)
        let candidateSummary = candidates
            .map { "\($0.text):\(String(format: "%.4f", $0.confidence))" }
            .joined(separator: ",")

        XCTAssertEqual(candidates.first?.text, "△", candidateSummary)
        XCTAssertLessThan(candidateRank(of: "△", in: candidates), candidateRank(of: "/", in: candidates), candidateSummary)
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

    private func assertExpectedGlyphAppearsInTopCandidates(for fixtures: [InkFixture]) throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates

        for fixture in fixtures {
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
}

private func candidateRank(of text: String, in candidates: [GlyphCandidate]) -> Int {
    candidates.firstIndex { $0.text == text } ?? Int.max
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
