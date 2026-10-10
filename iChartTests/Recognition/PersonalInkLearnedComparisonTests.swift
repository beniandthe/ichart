import XCTest
@testable import iChart

final class PersonalInkLearnedComparisonTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "unit-fixture-not-an-accuracy-test"
        let vocabulary = ["A", "B"]
        var calls = 0
        var malformed = false
        var anchorBank: PersonalInkAnchorBank?
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            calls += 1
            return .init(embedding: [malformed ? Double.nan : 1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
        }
    }
    private final class RecordingEncoder: PersonalInkVisualEncoding {
        let identity = "recorded-input-invariant-not-accuracy"
        let vocabulary = ["A", "B"]
        var inputs: [[InkStroke]] = []
        var anchorBank: PersonalInkAnchorBank? = nil
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            return .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
        }
    }
    private final class DomainEncoder: PersonalInkVisualEncoding {
        let identity = "synthetic-chord-domain-projection"
        let vocabulary: [String]
        let logits: [Double]
        var anchorBank: PersonalInkAnchorBank? = nil

        init(vocabulary: [String], logits: [Double]) {
            self.vocabulary = vocabulary
            self.logits = logits
        }

        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: logits)
        }
    }
    private var ink: [InkStroke] { [.init(points: [.init(x: 20, y: 20), .init(x: 20, y: 40)])] }
    private var enabled: PersonalInkProfile { var p = PersonalInkProfile(); p.isEnabled = true; return p }

    func testLessonFitEncodesExactDenseRecognitionInputNotBoundedPreview() throws {
        let points = (0..<257).map { index in
            InkPoint(x: Double(index), y: Double((index * index) % 31), timeOffset: Double(index) / 100)
        }
        let dense = [InkStroke(points: points, creationTimeOffset: 7)]
        var profile = enabled
        try profile.learn(strokes: dense, label: "A", kind: .glyph, source: .setup)
        let lesson = try XCTUnwrap(profile.examples.first)
        XCTAssertEqual(lesson.recognitionInput, dense)
        XCTAssertLessThan(lesson.strokes[0].points.count, dense[0].points.count)

        let encoder = RecordingEncoder()
        _ = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(encoder.inputs, [dense])
        XCTAssertNotEqual(encoder.inputs, [lesson.strokes])
    }

    func testNoLessonsPreserveSharedModelAndDoNotInventConfidence() throws {
        let p = enabled
        let model = try PersonalInkLearnedComparison(profile: p, encoder: Encoder())
        let prediction = try model.predict(ink, currentProfile: p)
        XCTAssertEqual(prediction.genericChord, "A")
        XCTAssertEqual(prediction.personalChord, "A")
        XCTAssertEqual(prediction.glyphs.first?.personal.first?.label, "A")
        XCTAssertTrue(prediction.wholeChordRanks.isEmpty)
        XCTAssertFalse(prediction.knownInk)
    }

    func testCompositionPreservesQualityWordsAndCannotDropAnUnreadSuffix() {
        for text in ["Cmaj7", "Dsus4", "Bb△7", "F#m7/C#", "C11", "C13"] {
            let expected = ChordRecognitionCompendium.match(text)?.displayText
            XCTAssertNotNil(expected, text)
            XCTAssertEqual(PersonalInkLearnedComparison.compose(text.map { String($0) }), expected, text)
        }
        XCTAssertNil(PersonalInkLearnedComparison.compose(["C", nil, "7"]))
        XCTAssertNil(PersonalInkLearnedComparison.compose(["C", ">", "7"]))
        for text in ["D>", ">C", "C!", "F?", "C7.", "Bb7%"] {
            XCTAssertNil(PersonalInkLearnedComparison.compose(text.map { String($0) }), text)
        }
        XCTAssertNil(PersonalInkLearnedComparison.compose(["J"]))
        XCTAssertNil(PersonalInkLearnedComparison.compose(["C", "ñ", "7"]))
        XCTAssertNil(PersonalInkLearnedComparison.compose([]))
    }

    func testReaderProjectionNeverPromotesAChordGlyphPastAnIllegalWinner() throws {
        let profile = enabled
        let encoder = DomainEncoder(vocabulary: ["ñ", "C", "J"], logits: [4, 3, 2])
        encoder.anchorBank = .init(
            vocabulary: encoder.vocabulary,
            features: (0..<3).map { index in
                (0..<128).map { $0 == index ? 1.0 : 0.0 }
            }
        )
        let illegalFirst = try PersonalInkLearnedComparison(
            profile: profile,
            encoder: encoder,
            grouping: .losslessSourceV2
        )
        let prediction = try illegalFirst.predict(ink, currentProfile: profile)
        let glyph = try XCTUnwrap(prediction.glyphs.first)
        XCTAssertEqual(glyph.generic.map(\.label), ["ñ", "C", "J"], "Raw forensic ranks stay complete")
        XCTAssertEqual(glyph.personal.map(\.label), ["ñ", "C", "J"])
        XCTAssertTrue(glyph.genericChordDomainRanks.isEmpty)
        XCTAssertTrue(glyph.personalChordDomainRanks.isEmpty)
        XCTAssertNil(prediction.genericChord)
        XCTAssertNil(prediction.personalChord)
        XCTAssertNil(prediction.anchored?.chord)
        XCTAssertEqual(prediction.anchored?.chordDomainGlyphRanks, [[]])

        let supplied = try illegalFirst.readSuppliedOriginalGroups(
            ink, originalIndexGroups: [[0]], currentProfile: profile
        )
        XCTAssertTrue(try XCTUnwrap(supplied.glyphs.first).genericChordDomainRanks.isEmpty)
        XCTAssertEqual(supplied.anchoredChordDomainRanks, [[]])
        XCTAssertEqual(supplied.anchoredGlyphRanks?[0].map(\.label), ["ñ", "C", "J"])
    }

    func testReaderProjectionKeepsLegalWinnerScoreWithoutRenormalizing() throws {
        let profile = enabled
        let model = try PersonalInkLearnedComparison(
            profile: profile,
            encoder: DomainEncoder(vocabulary: ["C", "ñ", "J"], logits: [4, 3, 2])
        )
        let prediction = try model.predict(ink, currentProfile: profile)
        let glyph = try XCTUnwrap(prediction.glyphs.first)
        XCTAssertEqual(glyph.generic.map(\.label), ["C", "ñ", "J"])
        XCTAssertEqual(glyph.genericChordDomainRanks.map(\.label), ["C"])
        XCTAssertEqual(glyph.genericChordDomainRanks[0].score, glyph.generic[0].score)
        XCTAssertEqual(glyph.personalChordDomainRanks.map(\.label), ["C"])
        XCTAssertEqual(glyph.personalChordDomainRanks[0].score, glyph.personal[0].score)
        XCTAssertEqual(prediction.genericChord, "C")
        XCTAssertEqual(prediction.personalChord, "C")
    }

    func testPresentationLabelsRequireOneCompleteChordWithoutPromotingLowerRanks() {
        func rank(_ label: String, _ score: Double = 1) -> PersonalInkLearnedComparison.Rank {
            .init(label: label, score: score)
        }
        func prediction(
            _ ranks: [[PersonalInkLearnedComparison.Rank]],
            anchored: [[PersonalInkLearnedComparison.Rank]]? = nil
        ) -> PersonalInkLearnedComparison.Prediction {
            .init(
                genericChord: nil,
                personalChord: nil,
                glyphs: ranks.enumerated().map { index, group in
                    .init(originalStrokeIndexes: [index], generic: group, personal: group)
                },
                wholeChordRanks: [],
                knownInk: false,
                anchored: anchored.map {
                    .init(learnerVersion: "synthetic-presentation-only", chord: nil, glyphRanks: $0)
                }
            )
        }

        for token in ["1", "j", "ñ", "J"] {
            let raw = [[rank(token, 2), rank("C", 1)]]
            let labels = prediction(raw, anchored: raw).chordDomainPresentationLabels
            XCTAssertEqual(labels.generic, [nil], token)
            XCTAssertEqual(labels.personal, [nil], token)
            XCTAssertEqual(labels.anchored, [nil], token)
        }

        let illegalInterior = [
            [rank("C")],
            [rank("ñ", 2), rank("1", 1)],
            [rank("7")]
        ]
        let illegalLabels = prediction(illegalInterior).chordDomainPresentationLabels
        XCTAssertEqual(illegalLabels.generic, [nil, nil, nil])
        XCTAssertEqual(illegalLabels.personal, [nil, nil, nil])

        let missingInterior = [[rank("C")], [], [rank("7")]]
        let missingLabels = prediction(missingInterior).chordDomainPresentationLabels
        XCTAssertEqual(missingLabels.generic, [nil, nil, nil])
        XCTAssertEqual(missingLabels.personal, [nil, nil, nil])
    }

    func testPresentationLabelsKeepContextualFragmentsInsideCompleteChords() {
        func prediction(_ text: String) -> PersonalInkLearnedComparison.Prediction {
            let ranks = text.enumerated().map { index, character in
                PersonalInkLearnedComparison.Glyph(
                    originalStrokeIndexes: [index],
                    generic: [.init(label: String(character), score: 1)],
                    personal: [.init(label: String(character), score: 1)]
                )
            }
            return .init(
                genericChord: nil,
                personalChord: nil,
                glyphs: ranks,
                wholeChordRanks: [],
                knownInk: false,
                anchored: .init(
                    learnerVersion: "synthetic-presentation-only",
                    chord: nil,
                    glyphRanks: ranks.map(\.generic)
                )
            )
        }

        for text in ["C11", "C13", "Cmaj7"] {
            let expected = text.map { Optional(String($0)) }
            let labels = prediction(text).chordDomainPresentationLabels
            XCTAssertEqual(labels.generic, expected, text)
            XCTAssertEqual(labels.personal, expected, text)
            XCTAssertEqual(labels.anchored, expected, text)
        }
    }

    func testAnchoredComparisonRetainsOriginalAndUsesSameFrozenExamplesAndInk() throws {
        var p = enabled
        try p.learn(strokes: ink, label: "B", kind: .glyph, source: .setup)
        let encoder = Encoder()
        let original = try PersonalInkLearnedComparison(profile: p, encoder: encoder).predict(ink, currentProfile: p)
        XCTAssertNil(original.anchored)
        let feature = [1.0] + Array(repeating: 0.0, count: 127)
        encoder.anchorBank = .init(vocabulary: encoder.vocabulary, features: [feature, feature])
        let model = try PersonalInkLearnedComparison(profile: p, encoder: encoder)
        let result = try model.predict(ink, currentProfile: p)
        XCTAssertEqual(result.genericChord, original.genericChord)
        XCTAssertEqual(result.personalChord, original.personalChord)
        XCTAssertEqual(result.glyphs, original.glyphs)
        let anchored = try XCTUnwrap(result.anchored)
        XCTAssertEqual(anchored.learnerVersion, PersonalInkAnchoredResidualHead.version)
        XCTAssertEqual(anchored.glyphRanks.count, result.glyphs.count)
        XCTAssertLessThan(try XCTUnwrap(anchored.glyphRanks[0].first { $0.label == "B" }).score,
                          try XCTUnwrap(result.glyphs[0].personal.first { $0.label == "B" }).score)
        var run = makeRun(profile: p)
        let before = try PersonalInkLearnedRunReport.compare(run, encoder: encoder)
        run.records[0].intended = "G7"
        let after = try PersonalInkLearnedRunReport.compare(run, encoder: encoder)
        XCTAssertEqual(before.rows[0].prediction, after.rows[0].prediction)
        XCTAssertEqual(model.profile, p)
        encoder.anchorBank = .init(vocabulary: ["B", "A"], features: [feature, feature])
        XCTAssertThrowsError(try PersonalInkLearnedComparison(profile: p, encoder: encoder))
    }

    func testEarlierComparisonReportsDecodeWithoutAnchoredFields() throws {
        let p = enabled
        let prediction = try PersonalInkLearnedComparison(profile: p, encoder: Encoder()).predict(ink, currentProfile: p)
        let data = try JSONEncoder().encode(prediction)
        let decoded = try JSONDecoder().decode(PersonalInkLearnedComparison.Prediction.self, from: data)
        XCTAssertEqual(prediction, decoded)
        XCTAssertNil(decoded.anchored)
    }

    func testOneInvalidCaptureDoesNotHideOtherTargets() throws {
        var run = makeRun(profile: enabled)
        var second = run.records[0]; second.id = UUID()
        run.records[0].recognitionStrokes = []
        run.records.append(second)
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        XCTAssertEqual(report.rows.count, 2)
        XCTAssertNil(report.rows[0].prediction)
        XCTAssertNotNil(report.rows[0].exclusion)
        XCTAssertEqual(report.rows[1].prediction?.personalChord, "A")
    }

    func testExplicitNovelMusicalSymbolIsLearnedAndRemovalReversesItsAvailability() throws {
        var p = enabled
        try p.learn(strokes: ink, label: "△", kind: .glyph, source: .setup)
        let original = p
        let model = try PersonalInkLearnedComparison(profile: p, encoder: Encoder())
        let prediction = try model.predict(ink, currentProfile: p)
        XCTAssertEqual(prediction.glyphs.first?.generic.first?.label, "A")
        XCTAssertEqual(prediction.glyphs.first?.personal.first?.label, "△")
        XCTAssertNil(prediction.personalChord, "A triangle alone is not a complete chord")
        XCTAssertTrue(prediction.knownInk)
        XCTAssertFalse(model.missingPersonalSymbols.contains("△"))
        p.removeExample(id: p.examples[0].id)
        XCTAssertThrowsError(try model.predict(ink, currentProfile: p))
        let revised = try PersonalInkLearnedComparison(profile: p, encoder: Encoder())
        XCTAssertEqual(try revised.predict(ink, currentProfile: p).glyphs.first?.personal.first?.label, "A")
        XCTAssertEqual(model.profile, original)
    }

    func testWholeChordLessonsDoNotFabricateSymbolLabelsOrOverrideSymbolRead() throws {
        var p = enabled
        try p.learn(strokes: ink, label: "Bb7", kind: .chord, source: .setup)
        try p.learn(strokes: [.init(points: [.init(x: 20, y: 20), .init(x: 40, y: 20)])],
                    label: "Eb7", kind: .chord, source: .setup)
        let model = try PersonalInkLearnedComparison(profile: p, encoder: Encoder())
        let prediction = try model.predict(ink, currentProfile: p)
        XCTAssertEqual(model.glyphLessonCount, 0)
        XCTAssertEqual(model.wholeChordLessonCount, 2)
        XCTAssertEqual(Set(prediction.wholeChordRanks.map(\.label)), ["Bb7", "Eb7"])
        XCTAssertEqual(prediction.personalChord, "A", "Closed-set whole guesses cannot replace symbol results")
        XCTAssertEqual(prediction.glyphs.first?.personal.first?.label, "A")
    }

    func testOptOutInvalidInkMalformedFeaturesAndUnversionedMutationsFailClosed() throws {
        let encoder = Encoder()
        XCTAssertThrowsError(try PersonalInkLearnedComparison(profile: .init(), encoder: encoder))
        XCTAssertEqual(encoder.calls, 0)
        let p = enabled
        let model = try PersonalInkLearnedComparison(profile: p, encoder: encoder)
        var changed = p; changed.learnsFromReviews.toggle()
        XCTAssertThrowsError(try model.predict(ink, currentProfile: changed))
        changed = p; changed.isEnabled = false
        XCTAssertThrowsError(try model.predict(ink, currentProfile: changed))
        XCTAssertThrowsError(try model.predict([], currentProfile: p))
        encoder.malformed = true
        XCTAssertThrowsError(try model.predict(ink, currentProfile: p))
    }

    func testSavedRunUsesFrozenProfileAndPredictionsDoNotDependOnIntendedAnswers() throws {
        var p = enabled
        try p.learn(strokes: ink, label: "B", kind: .glyph, source: .setup)
        var run = makeRun(profile: p)
        let before = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        run.records[0].intended = "G#maj7"
        run.records[0].baseline = "D7"
        let after = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        XCTAssertEqual(before.profileRevision, p.revision)
        XCTAssertEqual(before.rows[0].prediction, after.rows[0].prediction)
        XCTAssertEqual(after.rows[0].prediction?.personalChord, "B")
        XCTAssertNotNil(after.rows[0].exclusion, "Known ink is not a fresh test")
        XCTAssertEqual(run.profile, p)
    }

    func testOldThumbnailAndIncorrectGroupingAreNotPassedOffAsExactInput() throws {
        var run = makeRun(profile: enabled)
        run.records[0].recognitionStrokes = nil
        let encoder = Encoder()
        var report = try PersonalInkLearnedRunReport.compare(run, encoder: encoder)
        XCTAssertNil(report.rows[0].prediction)
        XCTAssertNotNil(report.rows[0].exclusion)
        XCTAssertEqual(encoder.calls, 0)
        run.records[0].recognitionStrokes = ink; run.records[0].groupingIssue = true
        report = try PersonalInkLearnedRunReport.compare(run, encoder: encoder)
        XCTAssertNil(report.rows[0].prediction)
        XCTAssertEqual(encoder.calls, 0)
        run.status = .labeling
        XCTAssertThrowsError(try PersonalInkLearnedRunReport.compare(run, encoder: encoder))
    }

    func testScorecardKeepsMissingAndUnsupportedAttemptsAndPairsGainsAndHarms() throws {
        var run = makeRun(profile: enabled)
        run.expectedChordCount = 4
        run.records[0].intended = "A"
        run.records[0].baseline = "B"
        run.records[0].personalized = "A"
        var broken = run.records[0]; broken.id = UUID()
        broken.baseline = "A"; broken.personalized = "B"; broken.personalizedAction = "trusted"
        var unsupported = broken; unsupported.id = UUID()
        unsupported.recognitionStrokes = []
        unsupported.baseline = nil; unsupported.personalized = nil
        run.records.append(contentsOf: [broken, unsupported])
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let card = try XCTUnwrap(report.scorecard)
        XCTAssertEqual(card.wholeChartDenominator, 4)
        XCTAssertEqual(card.eligibleCount, 3)
        XCTAssertEqual(card.missingCount, 1)
        XCTAssertEqual(card.unsupportedInputCount, 1)
        let app = try XCTUnwrap(card.scores.first { $0.method == .recordedPersonalized })
        XCTAssertEqual(app.correct, 1); XCTAssertEqual(app.wrongReads, 1); XCTAssertEqual(app.noReads, 1)
        XCTAssertEqual(app.improvements, 1); XCTAssertEqual(app.regressions, 1)
        XCTAssertEqual(app.trustedWrongReads, 1)
        let shared = try XCTUnwrap(card.scores.first { $0.method == .sharedML })
        XCTAssertEqual(shared.correct, 2); XCTAssertEqual(shared.noReads, 1)
        XCTAssertNil(shared.trustedWrongReads)
        XCTAssertEqual(report.rows[0].intended, "A")
        XCTAssertEqual(report.rows[0].recordedBaseline, "B")
        XCTAssertEqual(report.rows[0].recordedPersonalized, "A")
        let restored = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(restored.scorecard, card)
        XCTAssertEqual(restored.chartStyle, run.style)
        XCTAssertEqual(restored.profileGeneration, run.profile.generation)
    }

    func testScoringExclusionsWithholdWholeChartScoreForEveryMethod() throws {
        var run = makeRun(profile: enabled)
        var missing = run.records[0]; missing.id = UUID(); missing.recognitionStrokes = nil
        var grouped = run.records[0]; grouped.id = UUID(); grouped.groupingIssue = true
        var known = run.records[0]; known.id = UUID(); known.knownInk = true
        var unlabeled = run.records[0]; unlabeled.id = UUID(); unlabeled.intended = nil
        var invalid = run.records[0]; invalid.id = UUID(); invalid.intended = "D>"
        run.records.append(contentsOf: [missing, grouped, known, unlabeled, invalid])
        run.expectedChordCount = run.records.count
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let card = try XCTUnwrap(report.scorecard)
        XCTAssertNil(card.wholeChartDenominator)
        XCTAssertEqual(card.eligibleCount, 1)
        XCTAssertEqual(card.missingOriginalInputCount, 1)
        XCTAssertEqual(card.groupingIssueCount, 1)
        XCTAssertEqual(card.knownInkCount, 1)
        XCTAssertEqual(card.invalidLabelCount, 2)
        for score in card.scores {
            XCTAssertEqual(score.correct + score.wrongReads + score.noReads, card.eligibleCount)
        }
        run.expectedChordCount = 0
        XCTAssertNil(try PersonalInkLearnedRunReport.compare(run, encoder: Encoder()).scorecard?.wholeChartDenominator)
    }

    func testZeroCaptureCannotBecomePerfectZeroAttemptScore() throws {
        var run = makeRun(profile: enabled); run.records = []; run.expectedChordCount = 6
        let card = try XCTUnwrap(PersonalInkLearnedRunReport.compare(run, encoder: Encoder()).scorecard)
        XCTAssertEqual(card.wholeChartDenominator, 6)
        XCTAssertEqual(card.missingCount, 6)
        XCTAssertEqual(card.eligibleCount, 0)
        XCTAssertTrue(card.scores.allSatisfy { $0.correct == 0 })
    }

    func testCompleteParenthesizedInkUnsupportedByClusteringStillCountsAsFailedAttempt() throws {
        let fixture = try InkFixtureLoader.load("C7Sharp9", file: #filePath)
        var run = makeRun(profile: enabled)
        run.records[0].recognitionStrokes = fixture.strokes
        run.records[0].strokes = fixture.strokes
        run.records[0].intended = try ChordSymbolParser.parse("C7(#9)").displayText
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let card = try XCTUnwrap(report.scorecard)
        XCTAssertNil(report.rows[0].prediction, "The current comparison cannot drop wrapper strokes to claim a read")
        XCTAssertEqual(card.wholeChartDenominator, 1)
        XCTAssertEqual(card.eligibleCount, 1)
        XCTAssertEqual(card.unsupportedInputCount, 1)
        for score in card.scores where [.sharedML, .personalML, .anchoredML].contains(score.method) {
            XCTAssertEqual(score.correct, 0)
            XCTAssertEqual(score.noReads, 1)
        }
    }

    func testLosslessModeEncodesEveryOriginalStrokeInSourceOrderForAllThreeHeads() throws {
        let fixture = try InkFixtureLoader.load("C7Sharp9", file: #filePath)
        let source = fixture.strokes.enumerated().map { index, stroke -> InkStroke in
            var value = stroke
            value.creationTimeOffset = Double(index) * 10
            value.bounds.minX -= 0.25
            return value
        }
        let encoder = RecordingEncoder()
        let feature = [1.0] + Array(repeating: 0.0, count: 127)
        encoder.anchorBank = .init(vocabulary: encoder.vocabulary, features: [feature, feature])
        let profile = enabled
        let model = try PersonalInkLearnedComparison(profile: profile, encoder: encoder, grouping: .losslessSourceV2)
        let prediction = try model.predict(source, currentProfile: profile)
        XCTAssertEqual(prediction.glyphs.flatMap(\.originalStrokeIndexes).sorted(), Array(source.indices))
        XCTAssertEqual(encoder.inputs.count, prediction.glyphs.count, "Each group is encoded once, then shared by all heads")
        for (glyph, actualInput) in zip(prediction.glyphs, encoder.inputs) {
            XCTAssertEqual(glyph.originalStrokeIndexes, glyph.originalStrokeIndexes.sorted())
            XCTAssertEqual(actualInput, glyph.originalStrokeIndexes.map { source[$0] })
        }
        XCTAssertEqual(prediction.anchored?.glyphRanks.count, prediction.glyphs.count)
        // Grouping stays geometry-only: keeping source metadata at the encoder
        // boundary must not introduce a simultaneous timing-heuristic change.
        let geometryOnly = source.map { InkStroke(points: $0.points) }
        let expected = StrokeClusterer(wrapperPolicy: .preserveOriginalInk).indexedClusters(geometryOnly)
        XCTAssertEqual(prediction.glyphs.map(\.originalStrokeIndexes), expected.map { $0.originalIndexes.sorted() })
    }

    func testLosslessParenthesesReachInferenceButWrongReadsStillCountAsFailures() throws {
        let fixture = try InkFixtureLoader.load("C7Sharp9", file: #filePath)
        var run = makeRun(profile: enabled)
        run.records[0].recognitionStrokes = fixture.strokes
        run.records[0].strokes = fixture.strokes
        run.records[0].intended = try ChordSymbolParser.parse("C7(#9)").displayText
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: RecordingEncoder(), grouping: .losslessSourceV2)
        XCTAssertNotNil(report.rows[0].prediction)
        XCTAssertEqual(report.groupingVersion, PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue)
        let card = try XCTUnwrap(report.scorecard)
        XCTAssertEqual(card.wholeChartDenominator, 1)
        XCTAssertEqual(card.eligibleCount, 1)
        XCTAssertEqual(card.unsupportedInputCount, 0)
        for score in card.scores where [.sharedML, .personalML, .anchoredML].contains(score.method) {
            XCTAssertEqual(score.correct, 0)
            XCTAssertEqual(score.wrongReads + score.noReads, 1)
        }
        let before = report.rows[0].prediction
        run.records[0].intended = "G7"
        run.records[0].baseline = "D7"
        XCTAssertEqual(try PersonalInkLearnedRunReport.compare(run, encoder: RecordingEncoder(), grouping: .losslessSourceV2).rows[0].prediction, before)
    }

    func testLosslessInvalidBoundsAndTooManyGroupsFailBeforeEncoderAndStayInDenominator() throws {
        var run = makeRun(profile: enabled)
        var invalid = ink
        // Invalid but JSON-representable source geometry exercises a persisted
        // failed attempt. Nonfinite JSON cannot be a saved journal record.
        invalid[0].bounds.minX = invalid[0].bounds.maxX + 1
        run.records[0].recognitionStrokes = invalid
        let encoder = RecordingEncoder()
        var report = try PersonalInkLearnedRunReport.compare(run, encoder: encoder, grouping: .losslessSourceV2)
        XCTAssertNil(report.rows[0].prediction)
        XCTAssertEqual(report.scorecard?.unsupportedInputCount, 1)
        XCTAssertEqual(report.scorecard?.wholeChartDenominator, 1)
        let separated = (0..<17).map { i in
            InkStroke(points: [.init(x: Double(i) * 100, y: 0), .init(x: Double(i) * 100, y: 20)])
        }
        run.records[0].recognitionStrokes = separated
        report = try PersonalInkLearnedRunReport.compare(run, encoder: encoder, grouping: .losslessSourceV2)
        XCTAssertNil(report.rows[0].prediction)
        XCTAssertEqual(report.scorecard?.unsupportedInputCount, 1)
        XCTAssertEqual(report.scorecard?.wholeChartDenominator, 1)
        XCTAssertTrue(report.scorecard?.scores.filter { [.sharedML, .personalML].contains($0.method) }.allSatisfy { $0.noReads == 1 } == true)
        XCTAssertTrue(encoder.inputs.isEmpty)
    }

    func testGroupingVersionsAppendWithoutChangingFrozenEvidenceAndKeepLegacyDefault() throws {
        let run = makeRun(profile: enabled)
        let legacy = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let lossless = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder(), grouping: .losslessSourceV2)
        XCTAssertEqual(legacy.groupingVersion, PersonalInkLearnedComparison.Grouping.legacyGeometryV1.rawValue)
        XCTAssertNotEqual(legacy.groupingVersion, lossless.groupingVersion)
        XCTAssertNotEqual(legacy.id, lossless.id)
        XCTAssertEqual(legacy.sourceRunSHA256, lossless.sourceRunSHA256)
        XCTAssertEqual(legacy.evaluationSourceSHA256, lossless.evaluationSourceSHA256)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try legacy.save(in: directory)
        try lossless.save(in: directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "groupingVersion")
        let restored = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.groupingVersion)
        XCTAssertEqual(restored.rows[0].prediction, legacy.rows[0].prediction)
    }

    func testEvaluationDigestIgnoresTeachingButTracksLabelsInkAndFrozenProfile() throws {
        var run = makeRun(profile: enabled)
        let before = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        run.records[0].taught = true
        run.teachingReceipt = .init(taughtRecordIDs: [run.records[0].id], profileRevision: UUID(),
                                   profileGeneration: run.profile.generation, previousExampleCount: 0, savedExampleCount: 1)
        let after = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        XCTAssertEqual(before.evaluationSourceSHA256, after.evaluationSourceSHA256)
        XCTAssertNotEqual(before.sourceRunSHA256, after.sourceRunSHA256)
        let taught = run
        run.records[0].intended = "C"
        XCTAssertNotEqual(try PersonalInkLearnedRunReport.evaluationSourceDigest(run), before.evaluationSourceSHA256)
        run = taught; run.records[0].recognitionStrokes = []
        XCTAssertNotEqual(try PersonalInkLearnedRunReport.evaluationSourceDigest(run), before.evaluationSourceSHA256)
        run = taught; run.profile.revision = UUID()
        XCTAssertNotEqual(try PersonalInkLearnedRunReport.evaluationSourceDigest(run), before.evaluationSourceSHA256)
    }

    func testDuplicateRecordIDsFailBeforeFittingRatherThanMisalignAnswers() throws {
        var run = makeRun(profile: enabled); run.records.append(run.records[0])
        let encoder = Encoder()
        XCTAssertThrowsError(try PersonalInkLearnedRunReport.compare(run, encoder: encoder)) { error in
            guard case PersonalInkLearnedComparison.Failure.ambiguousRun = error else {
                return XCTFail("Expected ambiguous run, got \(error)")
            }
        }
        XCTAssertEqual(encoder.calls, 0)
    }

    func testEarlierSavedReportHasNoInventedScorecard() throws {
        let report = try PersonalInkLearnedRunReport.compare(makeRun(profile: enabled), encoder: Encoder())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        for key in ["scorecard", "evaluationSourceVersion", "evaluationSourceSHA256", "chartStyle", "phase",
                    "profileGeneration", "originalLearnerVersion", "groupingVersion"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(PersonalInkLearnedRunReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.scorecard)
        XCTAssertNil(restored.evaluationSourceSHA256)
        XCTAssertEqual(restored.sourceRunSHA256, report.sourceRunSHA256)
    }

    func testReportCarriesExactFrozenLineageWithoutChangingPredictionsScoresOrSource() throws {
        var profile = enabled
        let context = PersonalInkCaptureContext(sessionID: UUID(), origin: .setup,
                                               chartStyle: "simple-chord-sheet")
        try profile.learn(strokes: ink, label: "B", kind: .glyph, source: .setup,
                          captureContext: context)
        var run = makeRun(profile: profile)
        let old = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        XCTAssertNil(old.profileLineage, "A missing run-start summary must not be backfilled")
        let frozen = PersonalInkProfileLineageSummary(profile: run.profile, querySessionID: run.id)
        run.profileLineage = frozen
        let jsonEncoder = JSONEncoder(); jsonEncoder.outputFormatting = [.sortedKeys]
        let sourceBytes = try jsonEncoder.encode(run)
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        XCTAssertEqual(report.profileLineage, frozen)
        XCTAssertEqual(report.rows.map(\.prediction), old.rows.map(\.prediction))
        XCTAssertEqual(report.rows.map(\.exclusion), old.rows.map(\.exclusion))
        XCTAssertEqual(report.scorecard, old.scorecard)
        XCTAssertEqual(report.profileRevision, profile.revision)
        XCTAssertEqual(try jsonEncoder.encode(run), sourceBytes)
        let restored = try JSONDecoder().decode(PersonalInkLearnedRunReport.self,
                                                from: jsonEncoder.encode(report))
        XCTAssertEqual(restored.profileLineage, frozen)
        XCTAssertEqual(restored.rows.map(\.prediction), report.rows.map(\.prediction))
        XCTAssertEqual(restored.scorecard, report.scorecard)
    }

    func testLegacyReportMissingOrNullLineageRemainsUnknownWithoutChangingStoredResults() throws {
        var run = makeRun(profile: enabled)
        run.profileLineage = .init(profile: run.profile, querySessionID: run.id)
        let report = try PersonalInkLearnedRunReport.compare(run, encoder: Encoder())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        for nullValue in [false, true] {
            var json = original
            if nullValue { json["profileLineage"] = NSNull() }
            else { json.removeValue(forKey: "profileLineage") }
            let restored = try JSONDecoder().decode(PersonalInkLearnedRunReport.self,
                from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(restored.profileLineage)
            XCTAssertEqual(restored.rows.map(\.prediction), report.rows.map(\.prediction))
            XCTAssertEqual(restored.scorecard, report.scorecard)
            XCTAssertEqual(restored.sourceRunSHA256, report.sourceRunSHA256)
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
            XCTAssertNil(encoded["profileLineage"], "Unknown legacy metadata must remain absent when saved")
        }
    }

    func testCorruptFrozenLineageFailsBeforeLessonFitAndBeforeQueryEncoding() throws {
        var profile = enabled
        try profile.learn(strokes: ink, label: "B", kind: .glyph, source: .setup,
                          captureContext: .init(sessionID: UUID(), origin: .setup))
        var run = makeRun(profile: profile)
        run.profileLineage = .init(profile: profile, querySessionID: run.id)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(try XCTUnwrap(run.profileLineage))) as? [String: Any])
        let replacements: [(String, Any)] = [
            ("querySessionID", UUID().uuidString), ("trackedExampleIDs", [] as [String]),
            ("untrackedExampleIDs", [UUID().uuidString]), ("mismatchedExampleIDs", [UUID().uuidString]),
            ("observedSupportSessionIDs", [] as [String]), ("overlapExampleIDs", [profile.examples[0].id.uuidString]),
            ("isMetadataComplete", false), ("areObservedSupportSessionsDisjoint", false),
            ("assuranceNote", "Fresh independent handwriting verified"),
        ]
        let queryEncoder = Encoder()
        let fitted = try PersonalInkLearnedComparison(profile: profile, encoder: queryEncoder)
        queryEncoder.calls = 0
        let sourceEncoder = JSONEncoder(); sourceEncoder.outputFormatting = [.sortedKeys]
        for (key, value) in replacements {
            var changed = json; changed[key] = value
            run.profileLineage = try JSONDecoder().decode(PersonalInkProfileLineageSummary.self,
                from: JSONSerialization.data(withJSONObject: changed))
            let before = try sourceEncoder.encode(run)
            for grouping in [PersonalInkLearnedComparison.Grouping.legacyGeometryV1,
                             .losslessSourceV2, .selectiveLosslessOwnershipV3] {
                let encoder = Encoder()
                XCTAssertThrowsError(try PersonalInkLearnedRunReport.compare(run, encoder: encoder, grouping: grouping), key) { error in
                    guard case PersonalInkLearnedComparison.Failure.invalidFrozenLineage = error else {
                        return XCTFail("Expected invalidFrozenLineage for \(key), got \(error)")
                    }
                }
                XCTAssertEqual(encoder.calls, 0, "\(key): validation must precede every lesson fit")
                XCTAssertThrowsError(try PersonalInkLearnedRunReport.compare(run, model: fitted, grouping: grouping), key)
                XCTAssertEqual(queryEncoder.calls, 0, "\(key): validation must precede every query encoding")
            }
            XCTAssertEqual(try sourceEncoder.encode(run), before, "Invalid stored evidence is preserved")
        }
    }

    private func makeRun(profile: PersonalInkProfile) -> PersonalInkEvaluationRun {
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                           pipeline: "fixture", profile: profile)
        run.status = .complete; run.expectedChordCount = 1
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "fixture",
                             baseline: "A", personalized: "A", baselineAction: "confirm", personalizedAction: "confirm",
                             knownInk: false, recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false,
                             intended: "B", recognitionStrokes: ink)]
        return run
    }
}
