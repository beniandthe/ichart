import XCTest
@testable import iChart

final class PersonalInkSymbolTeachingTests: XCTestCase {
    private func ink(bend: Double = 0) -> [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20), .init(x: 10, y: 20),
                        .init(x: 12, y: 10), .init(x: 10, y: 0), .init(x: 0, y: 0)]),
         .init(points: [.init(x: 40, y: 0), .init(x: 52, y: 0), .init(x: 42 + bend, y: 20)])]
    }

    private func prepared() throws -> (PersonalInkProfile, PersonalInkSymbolTeachingReview) {
        var profile = PersonalInkProfile(); profile.isEnabled = true
        try profile.learn(strokes: ink(), label: "D7", kind: .chord, source: .explicitCorrection)
        return (profile, try .init(exampleID: XCTUnwrap(profile.examples.first?.id), profile: profile))
    }

    func testReviewIsLabelBlindAndDoesNotTeachOnOpenOrSkip() throws {
        var (profile, review) = try prepared()
        let before = profile
        XCTAssertEqual(review.pieces.count, 2)
        XCTAssertEqual(review.pieces.flatMap(\.originalStrokeIndexes).sorted(), [0, 1])
        XCTAssertTrue(profile.examples.allSatisfy { $0.kind == .chord })
        XCTAssertThrowsError(try review.teach(labels: [nil, nil], profile: &profile))
        XCTAssertEqual(profile, before)
        for piece in review.pieces {
            XCTAssertEqual(piece.strokes, piece.originalStrokeIndexes.map { review.source.recognitionInput[$0] })
        }
    }

    func testExplicitSymbolChoicePersistsOriginAndIsDeduplicated() throws {
        var (profile, review) = try prepared()
        let generation = profile.generation
        let receipt = try review.teach(labels: [nil, "7"], profile: &profile)
        XCTAssertEqual(receipt, .init(selectedSymbolCount: 1, changedSymbolCount: 1, previousExampleCount: 1, savedExampleCount: 2))
        XCTAssertEqual(profile.examples.first, review.source)
        let symbol = try XCTUnwrap(profile.examples.last)
        XCTAssertEqual(symbol.kind, .glyph)
        XCTAssertEqual(symbol.label, "7")
        XCTAssertEqual(symbol.source, .explicitCorrection)
        XCTAssertEqual(symbol.verifiedSymbolOrigin, .init(chordExampleID: review.source.id, chordLabel: "D7", originalStrokeIndexes: [1]))
        XCTAssertEqual(profile.generation, generation)
        let beforeRepeat = profile
        let repeated = try review.teach(labels: [nil, "7"], profile: &profile)
        XCTAssertEqual(repeated.changedSymbolCount, 0)
        XCTAssertEqual(profile, beforeRepeat)
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkProfile.self, from: JSONEncoder().encode(profile)), profile)
    }

    func testLabelsComeFromUserNotCanonicalChordText() throws {
        var (profile, review) = try prepared()
        _ = try review.teach(labels: [nil, "9"], profile: &profile)
        XCTAssertEqual(profile.examples.last?.label, "9", "The implementation cannot overrule an explicit symbol label using the whole chord")
        XCTAssertFalse(profile.examples.contains { $0.kind == .glyph && $0.label == "7" })
    }

    func testInvalidLaterSelectionCannotPartiallySaveEarlierSymbol() throws {
        var (profile, review) = try prepared()
        let before = profile
        for labels: [String?] in [["D", "not-a-symbol"], ["D"], [], [nil, ""]] {
            XCTAssertThrowsError(try review.teach(labels: labels, profile: &profile))
            XCTAssertEqual(profile, before)
        }
    }

    func testResetOptOutDeletionAndEditedSourceInvalidatePendingReview() throws {
        let (original, review) = try prepared()
        for variation in 0..<4 {
            var profile = original
            switch variation {
            case 0: profile.generation = UUID()
            case 1: profile.isEnabled = false
            case 2: profile.examples.removeAll()
            default: profile.examples[0].label = "C7"
            }
            let before = profile
            XCTAssertThrowsError(try review.teach(labels: [nil, "7"], profile: &profile))
            XCTAssertEqual(profile, before)
        }
    }

    func testStandaloneSymbolKeepsItsOriginWhenDuplicateTaughtFromChord() throws {
        var (profile, review) = try prepared()
        try profile.learn(strokes: review.pieces[1].strokes, label: "7", kind: .glyph, source: .setup)
        let id = try XCTUnwrap(profile.examples.last?.id)
        _ = try review.teach(labels: [nil, "7"], profile: &profile)
        XCTAssertEqual(profile.examples.last?.id, id)
        XCTAssertNil(profile.examples.last?.verifiedSymbolOrigin)
        XCTAssertEqual(profile.examples.last?.source, .explicitCorrection)
    }

    func testRemovingWholeChordDoesNotDeleteIndependentlyVerifiedSymbol() throws {
        var (profile, review) = try prepared()
        _ = try review.teach(labels: [nil, "7"], profile: &profile)
        let symbol = try XCTUnwrap(profile.examples.last)
        XCTAssertTrue(profile.removeExample(id: review.source.id))
        XCTAssertEqual(profile.examples, [symbol])
    }

    func testFullProfileCannotEvictReviewedSourceWhileSavingSymbols() throws {
        var (profile, review) = try prepared()
        profile.examples += (1..<PersonalInkProfile.maximumExamples).map { _ in
            PersonalInkExample(kind: .chord, label: "C", strokes: ink(), source: .setup)
        }
        let before = profile
        XCTAssertThrowsError(try review.teach(labels: [nil, "7"], profile: &profile))
        XCTAssertEqual(profile, before)
    }

    func testOldExamplesStillDecodeWithoutNewOriginField() throws {
        let (profile, _) = try prepared()
        let data = try JSONEncoder().encode(profile)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("verifiedSymbolOrigin"))
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkProfile.self, from: data), profile)
    }

    private struct Encoder: PersonalInkVisualEncoding {
        let identity = "controlled-symbol-learning-fixture"
        let vocabulary = ["D", "7", "T"]
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            let closed = strokes.count == 1 && strokes[0].points.first == strokes[0].points.last
            let features = closed ? [1.0, 0.0] : [0.0, 1.0]
            return .init(embedding: features + Array(repeating: 0, count: 126), genericLogits: closed ? [3, 0, 0] : [0, 1, 1.1])
        }
    }

    func testVerifiedSymbolActuallyTrainsLearnedReaderWithoutChangingGenericRead() throws {
        var (profile, review) = try prepared()
        let frozen = profile
        let query = ink(bend: 1)
        let before = try PersonalInkLearnedComparison(profile: profile, encoder: Encoder()).predict(query, currentProfile: profile)
        XCTAssertNil(before.personalChord)
        _ = try review.teach(labels: [nil, "7"], profile: &profile)
        let after = try PersonalInkLearnedComparison(profile: profile, encoder: Encoder()).predict(query, currentProfile: profile)
        XCTAssertEqual(after.personalChord, "D7")
        XCTAssertEqual(after.genericChord, before.genericChord)
        XCTAssertEqual(after.glyphs.map(\.generic), before.glyphs.map(\.generic))
        XCTAssertEqual(frozen.examples.count, 1, "Pre-test profiles must remain independent values")
        // A controlled model proves wiring, not handwriting accuracy.
    }
}
