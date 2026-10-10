import XCTest
@testable import iChart

/// Synthetic contracts for observed local intake metadata, not writer,
/// acquisition, consent, freshness or recognition-quality evidence.
final class PersonalInkLearningLineageTests: XCTestCase {
    private let session = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let otherSession = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let querySession = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let capturedAt = Date(timeIntervalSinceReferenceDate: 100)

    private var ink: [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])]
    }
    private var chordInk: [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20), .init(x: 10, y: 20),
                        .init(x: 12, y: 10), .init(x: 10, y: 0), .init(x: 0, y: 0)]),
         .init(points: [.init(x: 40, y: 0), .init(x: 52, y: 0), .init(x: 42, y: 20)])]
    }
    private var context: PersonalInkCaptureContext {
        .init(sessionID: session, captureID: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
              capturedAt: capturedAt, origin: .setup, chartStyle: "simple-chord-sheet")
    }
    private var enabled: PersonalInkProfile {
        var profile = PersonalInkProfile(); profile.isEnabled = true; return profile
    }
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func learned(_ input: [InkStroke]? = nil, label: String = "A",
                         captureContext: PersonalInkCaptureContext? = nil) throws -> PersonalInkProfile {
        var profile = enabled
        try profile.learn(strokes: input ?? ink, label: label, kind: .chord, source: .setup,
                          captureContext: captureContext)
        return profile
    }

    func testExactLegacyProfileSchemaDecodesWithoutInventingLineage() throws {
        let oldJSON = #"{"version":1,"revision":"50000000-0000-0000-0000-000000000005","generation":"60000000-0000-0000-0000-000000000006","isEnabled":true,"learnsFromReviews":true,"examples":[{"id":"70000000-0000-0000-0000-000000000007","kind":"chord","label":"A","strokes":[{"points":[{"x":23.5,"y":2.5},{"x":23.5,"y":28.5}],"bounds":{"minX":23.5,"minY":2.5,"maxX":23.5,"maxY":28.5}}],"source":"setup"}]}"#
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: Data(oldJSON.utf8))
        XCTAssertNil(profile.examples[0].learningProvenance)
        XCTAssertNil(profile.examples[0].verifiedSymbolOrigin)
        let restored = String(decoding: try encoded(profile), as: UTF8.self)
        XCTAssertFalse(restored.contains("learningProvenance"))
        XCTAssertFalse(restored.contains("verifiedSymbolOrigin"))
        XCTAssertFalse(restored.contains("capturedAt"))
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(oldJSON.utf8)) as? NSDictionary)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(profile)) as? NSDictionary)
        XCTAssertEqual(after, before)
        let summary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: querySession)
        XCTAssertEqual(summary.untrackedExampleIDs, profile.examples.map(\.id))
        XCTAssertFalse(summary.isMetadataComplete)
        XCTAssertFalse(summary.areObservedSupportSessionsDisjoint)
    }

    func testNewLessonExplicitlyBindsExactRecognitionInputAsV2() throws {
        var input = ink
        input[0].points[0].timeOffset = 0
        input[0].points[1].timeOffset = 0.2
        input[0].creationTimeOffset = 0.5
        let profile = try learned(input, captureContext: context)
        let example = try XCTUnwrap(profile.examples.first)
        let provenance = try XCTUnwrap(example.learningProvenance)
        XCTAssertEqual(example.strokes, try XCTUnwrap(PersonalInkShape(strokes: input)).normalizedStrokes)
        XCTAssertEqual(example.recognitionStrokes, input)
        XCTAssertEqual(example.recognitionInput, input)
        XCTAssertNil(example.strokes[0].points[0].timeOffset)
        XCTAssertNil(example.strokes[0].creationTimeOffset)
        XCTAssertEqual(provenance.version, PersonalInkLearningProvenance.currentVersion)
        XCTAssertEqual(provenance.storedInputRole, .recognitionInput)
        XCTAssertEqual(provenance.context, context)
        XCTAssertTrue(provenance.taughtAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertEqual(provenance.originalInputSHA256, try PersonalInkLearningProvenance.inputSHA256(strokes: input))
        XCTAssertEqual(provenance.storedInputSHA256, try PersonalInkLearningProvenance.inputSHA256(strokes: input))
        XCTAssertEqual(provenance.originalInputSHA256, provenance.storedInputSHA256)
        XCTAssertNoThrow(try provenance.validate(example: example))
    }

    func testOriginalDigestPreservesSignedZeroAndTimingAvailability() throws {
        let stored = try XCTUnwrap(PersonalInkShape(strokes: ink)).normalizedStrokes
        let original = try PersonalInkLearningProvenance.make(context: context, taughtAt: capturedAt,
                                                              originalInput: ink, storedInput: stored)
        XCTAssertEqual(original.version, PersonalInkLearningProvenance.legacyVersion)
        XCTAssertNil(original.storedInputRole)
        var variants = [ink, ink, ink, ink]
        variants[0][0].points[0].x = -0.0
        variants[1][0].points[0].timeOffset = 0
        variants[2][0].creationTimeOffset = 0
        variants[3][0].bounds.minX = -0.0
        for changed in variants {
            let evidence = try PersonalInkLearningProvenance.make(context: context, taughtAt: capturedAt,
                                                                 originalInput: changed, storedInput: stored)
            XCTAssertNotEqual(evidence.originalInputSHA256, original.originalInputSHA256)
            XCTAssertEqual(evidence.storedInputSHA256, original.storedInputSHA256)
        }
    }

    func testStoredDigestRejectsChangedCoordinatesBoundsAndTiming() throws {
        let stored = try XCTUnwrap(PersonalInkShape(strokes: ink)).normalizedStrokes
        let provenance = try PersonalInkLearningProvenance.make(context: context, taughtAt: capturedAt,
                                                                originalInput: ink, storedInput: stored)
        var variants = [stored, stored, stored, stored]
        variants[0][0].points[0].x += 0.00001
        variants[1][0].bounds.maxX += 0.00001
        variants[2][0].points[0].timeOffset = 0
        variants[3][0].creationTimeOffset = 0
        for changed in variants {
            XCTAssertThrowsError(try provenance.validate(storedInput: changed)) { error in
                XCTAssertEqual(error as? PersonalInkLearningProvenance.Failure, .storedInputMismatch)
            }
        }
    }

    func testDuplicateAndCorrectionUpgradeRetainOriginalTrackedIntake() throws {
        var profile = try learned(captureContext: context)
        let original = profile.examples[0]
        var later = context; later.sessionID = otherSession; later.captureID = UUID(); later.origin = .chartReview
        let transformed = ink.map { stroke in
            InkStroke(points: stroke.points.map { .init(x: $0.x * 2 + 100, y: $0.y * 2 - 40) })
        }
        let bytes = try encoded(profile)
        XCTAssertFalse(try profile.learn(strokes: transformed, label: "A", kind: .chord,
                                         source: .confirmedReview, captureContext: later))
        XCTAssertEqual(try encoded(profile), bytes)
        XCTAssertTrue(try profile.learn(strokes: transformed, label: "A", kind: .chord,
                                        source: .explicitCorrection, captureContext: later))
        XCTAssertEqual(profile.examples.count, 1)
        XCTAssertEqual(profile.examples[0].id, original.id)
        XCTAssertEqual(profile.examples[0].learningProvenance, original.learningProvenance)
        XCTAssertEqual(profile.examples[0].source, .explicitCorrection)
        let upgraded = try encoded(profile)
        XCTAssertFalse(try profile.learn(strokes: ink, label: "A", kind: .chord,
                                         source: .explicitCorrection, captureContext: later))
        XCTAssertEqual(try encoded(profile), upgraded)
    }

    func testLegacyDuplicateUpgradeCannotBackfillInventedIntake() throws {
        var profile = try learned()
        let id = profile.examples[0].id
        XCTAssertFalse(try profile.learn(strokes: ink, label: "A", kind: .chord,
                                         source: .confirmedReview, captureContext: context))
        XCTAssertTrue(try profile.learn(strokes: ink, label: "A", kind: .chord,
                                        source: .explicitCorrection, captureContext: context))
        XCTAssertEqual(profile.examples.count, 1)
        XCTAssertEqual(profile.examples[0].id, id)
        XCTAssertNil(profile.examples[0].learningProvenance)
    }

    func testInvalidCaptureContextCannotPartiallyRemoveCorrectedLabels() throws {
        var invalid = [context, context, context, context]
        invalid[0].capturedAt = Date(timeIntervalSinceReferenceDate: .nan)
        invalid[1].capturedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        invalid[2].chartStyle = ""
        invalid[3].chartStyle = "unsupported-style"
        for capture in invalid {
            var profile = try learned(label: "B", captureContext: context)
            let before = try encoded(profile)
            XCTAssertThrowsError(try profile.learn(strokes: ink, label: "A", kind: .chord,
                                                   source: .explicitCorrection, captureContext: capture))
            XCTAssertEqual(try encoded(profile), before)
            XCTAssertEqual(profile.examples.map(\.label), ["B"])
        }
    }

    func testMalformedProvenanceFailsValidationWithoutChangingProfile() throws {
        let profile = try learned(captureContext: context)
        let original = try XCTUnwrap(profile.examples[0].learningProvenance)
        var invalid = [original, original, original, original, original]
        invalid[0].version = 999
        invalid[1].taughtAt = Date(timeIntervalSinceReferenceDate: .nan)
        invalid[2].context.capturedAt = Date(timeIntervalSinceReferenceDate: -.infinity)
        invalid[3].context.chartStyle = "simple-chord-sheet\n"
        invalid[4].originalInputSHA256 = String(repeating: "G", count: 64)
        let before = try encoded(profile)
        for provenance in invalid {
            XCTAssertThrowsError(try provenance.validate(storedInput: profile.examples[0].strokes))
        }
        XCTAssertEqual(try encoded(profile), before)
        XCTAssertThrowsError(try PersonalInkLearningProvenance.make(context: context,
            taughtAt: Date(timeIntervalSinceReferenceDate: .infinity), originalInput: ink, storedInput: ink))
    }

    func testCorruptedStoredInkIsMismatchedAndCannotClaimSessionDisjointness() throws {
        var profile = try learned(captureContext: context)
        profile.examples[0].strokes[0].points[0].x += 0.25
        let before = try encoded(profile)
        let summary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: querySession)
        XCTAssertEqual(summary.mismatchedExampleIDs, profile.examples.map(\.id))
        XCTAssertTrue(summary.trackedExampleIDs.isEmpty)
        XCTAssertTrue(summary.untrackedExampleIDs.isEmpty)
        XCTAssertTrue(summary.observedSupportSessionIDs.isEmpty)
        XCTAssertFalse(summary.isMetadataComplete)
        XCTAssertFalse(summary.areObservedSupportSessionsDisjoint)
        XCTAssertEqual(try encoded(profile), before)
    }

    func testMissingLineageAndObservedSessionOverlapRemainVisibleTogether() throws {
        var profile = try learned(captureContext: context)
        try profile.learn(strokes: ink, label: "B", kind: .glyph, source: .practice)
        let summary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: session)
        XCTAssertEqual(summary.trackedExampleIDs, [profile.examples[0].id])
        XCTAssertEqual(summary.untrackedExampleIDs, [profile.examples[1].id])
        XCTAssertEqual(summary.observedSupportSessionIDs, [session])
        XCTAssertEqual(summary.overlapExampleIDs, [profile.examples[0].id])
        XCTAssertTrue(summary.mismatchedExampleIDs.isEmpty)
        XCTAssertFalse(summary.isMetadataComplete)
        XCTAssertFalse(summary.areObservedSupportSessionsDisjoint)
    }

    func testCompleteObservedSessionsAreComparedAgainstTheQuerySession() throws {
        var profile = try learned(captureContext: context)
        var other = context; other.sessionID = otherSession; other.origin = .practice
        try profile.learn(strokes: ink, label: "B", kind: .glyph, source: .practice, captureContext: other)
        let disjoint = PersonalInkProfileLineageSummary(profile: profile, querySessionID: querySession)
        XCTAssertEqual(Set(disjoint.trackedExampleIDs), Set(profile.examples.map(\.id)))
        XCTAssertEqual(Set(disjoint.observedSupportSessionIDs), [session, otherSession])
        XCTAssertTrue(disjoint.isMetadataComplete)
        XCTAssertTrue(disjoint.areObservedSupportSessionsDisjoint)
        XCTAssertTrue(disjoint.overlapExampleIDs.isEmpty)
        let overlapping = PersonalInkProfileLineageSummary(profile: profile, querySessionID: otherSession)
        XCTAssertTrue(overlapping.isMetadataComplete)
        XCTAssertEqual(overlapping.overlapExampleIDs, [profile.examples[1].id])
        XCTAssertFalse(overlapping.areObservedSupportSessionsDisjoint)
    }

    func testEmptySummaryIsVacuousWithNoObservedSupports() {
        let summary = PersonalInkProfileLineageSummary(profile: enabled, querySessionID: querySession)
        XCTAssertTrue(summary.trackedExampleIDs.isEmpty)
        XCTAssertTrue(summary.untrackedExampleIDs.isEmpty)
        XCTAssertTrue(summary.mismatchedExampleIDs.isEmpty)
        XCTAssertTrue(summary.observedSupportSessionIDs.isEmpty)
        XCTAssertTrue(summary.overlapExampleIDs.isEmpty)
        XCTAssertTrue(summary.isMetadataComplete)
        XCTAssertTrue(summary.areObservedSupportSessionsDisjoint)
        XCTAssertTrue(summary.assuranceNote.contains("not verified"))
    }

    func testTrackedProfileAndLineageSummaryRoundTripThroughCodable() throws {
        let profile = try learned(captureContext: context)
        let decoded = try JSONDecoder().decode(PersonalInkProfile.self, from: encoded(profile))
        XCTAssertEqual(decoded, profile)
        let provenance = try XCTUnwrap(decoded.examples[0].learningProvenance)
        XCTAssertNoThrow(try provenance.validate(example: decoded.examples[0]))
        let summary = PersonalInkProfileLineageSummary(profile: decoded, querySessionID: querySession)
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkProfileLineageSummary.self, from: encoded(summary)), summary)
    }

    func testSavedSymbolInheritsKnownParentIntakeKeepsLegacyUnknownAndRejectsInvalidParent() throws {
        for tracked in [false, true] {
            var profile = try learned(chordInk, label: "D7", captureContext: tracked ? context : nil)
            let parent = profile.examples[0]
            let review = try PersonalInkSymbolTeachingReview(exampleID: parent.id, profile: profile)
            XCTAssertEqual(review.pieces.count, 2)
            _ = try review.teach(labels: [nil, "7"], profile: &profile)
            let symbol = try XCTUnwrap(profile.examples.last)
            XCTAssertEqual(profile.examples.first, parent)
            XCTAssertEqual(symbol.verifiedSymbolOrigin?.chordExampleID, parent.id)
            if tracked {
                let provenance = try XCTUnwrap(symbol.learningProvenance)
                XCTAssertEqual(provenance.context.sessionID, context.sessionID)
                XCTAssertEqual(provenance.context.captureID, context.captureID)
                XCTAssertEqual(provenance.context.capturedAt, context.capturedAt)
                XCTAssertEqual(provenance.context.chartStyle, context.chartStyle)
                XCTAssertEqual(provenance.context.origin, .selectedSavedSymbol)
                XCTAssertEqual(provenance.originalInputSHA256,
                               try PersonalInkLearningProvenance.inputSHA256(strokes: review.pieces[1].strokes))
                XCTAssertEqual(symbol.recognitionStrokes, review.pieces[1].strokes)
                XCTAssertEqual(provenance.storedInputRole, .recognitionInput)
                XCTAssertNoThrow(try provenance.validate(example: symbol))
            } else {
                XCTAssertNil(symbol.learningProvenance)
            }
        }
        var corrupt = try learned(chordInk, label: "D7", captureContext: context)
        let review = try PersonalInkSymbolTeachingReview(exampleID: corrupt.examples[0].id, profile: corrupt)
        corrupt.examples[0].learningProvenance?.storedInputSHA256 = String(repeating: "0", count: 64)
        let before = try encoded(corrupt)
        XCTAssertThrowsError(try review.teach(labels: ["D", "7"], profile: &corrupt)) { error in
            guard let failure = error as? PersonalInkSymbolTeachingReview.Failure,
                  case .changedSource = failure else {
                return XCTFail("Invalid parent metadata must report changedSource, got \(error)")
            }
        }
        XCTAssertEqual(try encoded(corrupt), before)
    }

    private struct Encoder: PersonalInkVisualEncoding {
        let identity = "lineage-only-synthetic-invariance-fixture"
        let vocabulary = ["A", "B"]
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
        }
    }

    func testMetadataDoesNotChangeRecognitionRankingsOrLearnFromPrediction() throws {
        var legacy = enabled
        try legacy.learn(strokes: ink, label: "B", kind: .glyph, source: .setup)
        var tracked = legacy
        tracked.examples[0].learningProvenance = try .make(context: context, taughtAt: capturedAt,
            originalInput: tracked.examples[0].recognitionInput,
            storedInput: tracked.examples[0].recognitionInput,
            storedInputRole: .recognitionInput)
        let legacyBytes = try encoded(legacy), trackedBytes = try encoded(tracked)
        let baseline = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let oldResult = PersonalInkSnapshot(profile: legacy).applying(to: baseline, strokes: ink)
        let newResult = PersonalInkSnapshot(profile: tracked).applying(to: baseline, strokes: ink)
        XCTAssertEqual(newResult.match, oldResult.match)
        XCTAssertEqual(newResult.confidence, oldResult.confidence)
        XCTAssertEqual(newResult.candidateScores, oldResult.candidateScores)
        XCTAssertEqual(newResult.personalSuggestion, oldResult.personalSuggestion)
        let oldModel = try PersonalInkLearnedComparison(profile: legacy, encoder: Encoder())
        let newModel = try PersonalInkLearnedComparison(profile: tracked, encoder: Encoder())
        let oldPrediction = try oldModel.predict(ink, currentProfile: legacy)
        let newPrediction = try newModel.predict(ink, currentProfile: tracked)
        XCTAssertEqual(newPrediction, oldPrediction)
        XCTAssertEqual(newPrediction.genericChord, "A")
        XCTAssertEqual(newPrediction.personalChord, "B")
        for _ in 0..<3 {
            _ = try newModel.predict(ink, currentProfile: tracked)
            _ = PersonalInkSnapshot(profile: tracked).suggestion(strokes: ink)
        }
        XCTAssertEqual(try encoded(legacy), legacyBytes)
        XCTAssertEqual(try encoded(tracked), trackedBytes)
        XCTAssertEqual(oldModel.profile, legacy)
        XCTAssertEqual(newModel.profile, tracked)
    }
}
