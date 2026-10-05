import XCTest
@testable import iChart

final class PersonalInkResidualHeadTests: XCTestCase {
    private typealias Head = PersonalInkResidualHead
    private let vocabulary = ["B", "G"]
    private let context = PersonalInkResidualHead.Context(isEnabled: true, profileRevision: UUID(), encoderIdentity: "frozen-test-encoder")

    func testEmptyAndAlreadyCorrectLessonsDoNotChangeBase() throws {
        let empty = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [])
        let perfect = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [
            .init(label: "B", features: [1, 0], baseScores: [1, 0]),
            .init(label: "G", features: [0, 1], baseScores: [0, 1])])
        for model in [empty, perfect] {
            XCTAssertEqual(try model.rankedCandidates(features: [1, 0], baseScores: [0.8, 0.2], currentContext: context),
                           [.init(label: "B", score: 0.8), .init(label: "G", score: 0.2)])
        }
    }

    func testLearnsClosedFormCorrectionWithoutSwampingDuplicateLabel() throws {
        let lesson = Head.Lesson(label: "B", features: [1, 0], baseScores: [0.2, 0.8])
        let other = Head.Lesson(label: "G", features: [0, 1], baseScores: [0.1, 0.9])
        let once = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [lesson, other])
        let repeated = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [lesson, lesson, other])
        let single = try once.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context)
        let doubled = try repeated.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context)
        XCTAssertEqual(single.map(\.label), ["B", "G"])
        XCTAssertEqual(single[0].score, 0.2 + 0.8 / 1.1, accuracy: 1e-12)
        for (a, b) in zip(single, doubled) { XCTAssertEqual(a.score, b.score, accuracy: 1e-12) }
    }

    func testOptOutIsEnforcedAtFitAndPrediction() throws {
        var disabled = context
        disabled.isEnabled = false
        XCTAssertThrowsError(try Head(context: disabled, vocabulary: [], featureCount: 0, lessons: [])) {
            XCTAssertEqual($0 as? Head.Failure, .disabled)
        }
        let head = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [])
        XCTAssertThrowsError(try head.rankedCandidates(features: [], baseScores: [], currentContext: disabled)) {
            XCTAssertEqual($0 as? Head.Failure, .disabled)
        }
    }

    func testCorrectionAndRemovalRequireNewSnapshotAndDoNotRewriteOldOne() throws {
        let old = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [
            .init(label: "B", features: [1, 0], baseScores: [0.2, 0.8])])
        var revision = context
        revision.profileRevision = UUID()
        let corrected = try Head(context: revision, vocabulary: vocabulary, featureCount: 2, lessons: [
            .init(label: "G", features: [1, 0], baseScores: [0.2, 0.8])])
        let removed = try Head(context: revision, vocabulary: vocabulary, featureCount: 2, lessons: [])
        XCTAssertEqual(try old.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context).first?.label, "B")
        XCTAssertEqual(try corrected.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: revision).first?.label, "G")
        XCTAssertEqual(try removed.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: revision).first?.score, 0.8)
        XCTAssertThrowsError(try old.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: revision)) {
            XCTAssertEqual($0 as? Head.Failure, .staleContext)
        }
        revision.encoderIdentity = "different-encoder"
        XCTAssertThrowsError(try corrected.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: revision)) {
            XCTAssertEqual($0 as? Head.Failure, .staleContext)
        }
    }

    func testMalformedLessonsAndQueriesAreRejected() throws {
        for lesson in [Head.Lesson(label: "A", features: [1, 0], baseScores: [0.5, 0.5]),
                       .init(label: "B", features: [.nan, 0], baseScores: [0.5, 0.5]),
                       .init(label: "B", features: [0, 0], baseScores: [0.5, 0.5]),
                       .init(label: "B", features: [1, 0], baseScores: [2, -1])] {
            XCTAssertThrowsError(try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [lesson]))
        }
        let head = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [])
        XCTAssertThrowsError(try head.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.2], currentContext: context))
        XCTAssertThrowsError(try head.rankedCandidates(features: [1], baseScores: [0.2, 0.8], currentContext: context))
    }

    func testLogitNormalizationIsStableWithoutConferringTrust() throws {
        XCTAssertEqual(try Head.normalizedScores(logits: [1000, -1000]), [1, 0])
        let a = try Head.normalizedScores(logits: [3, 5])
        let b = try Head.normalizedScores(logits: [103, 105])
        XCTAssertEqual(a, b)
        XCTAssertThrowsError(try Head.normalizedScores(logits: [.nan, 0]))
        let head = try Head(context: context, vocabulary: vocabulary, featureCount: 2, lessons: [
            .init(label: "B", features: [1, 0], baseScores: [0, 1])])
        let ranks = try head.rankedCandidates(features: [-1, 0], baseScores: [0, 1], currentContext: context)
        XCTAssertLessThan(try XCTUnwrap(ranks.last?.score), 0, "Corrected scores are ranks, not probabilities")
    }
}
