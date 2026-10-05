import XCTest
@testable import iChart

final class PersonalInkAnchoredResidualHeadTests: XCTestCase {
    private let context = PersonalInkResidualHead.Context(isEnabled: true, profileRevision: UUID(), encoderIdentity: "fixture-with-bound-anchors")
    private let bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, 1]])

    func testEmptyAndFullProfilesExactlyPreserveOriginalLearner() throws {
        let full: [PersonalInkResidualHead.Lesson] = [
            .init(label: "A", features: [1, 0], baseScores: [0.2, 0.8]),
            .init(label: "B", features: [0, 1], baseScores: [0.1, 0.9])]
        for lessons in [[], full] {
            let a = try PersonalInkResidualHead(context: context, vocabulary: bank.vocabulary, featureCount: 2, lessons: lessons)
            let b = try PersonalInkAnchoredResidualHead(context: context, vocabulary: bank.vocabulary, featureCount: 2, lessons: lessons, bank: bank)
            XCTAssertEqual(try a.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context),
                           try b.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context))
        }
    }

    func testClosedFormConstraintClassBalanceAndImmutableCorrection() throws {
        let shared = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [1, 0]])
        let lesson = PersonalInkResidualHead.Lesson(label: "A", features: [1, 0], baseScores: [0.2, 0.8])
        let model = try PersonalInkAnchoredResidualHead(context: context, vocabulary: shared.vocabulary, featureCount: 2, lessons: [lesson], bank: shared)
        let duplicate = try PersonalInkAnchoredResidualHead(context: context, vocabulary: shared.vocabulary, featureCount: 2, lessons: [lesson, lesson], bank: shared)
        let rank = try model.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context)
        XCTAssertEqual(try XCTUnwrap(rank.first { $0.label == "A" }).score, 0.2 + 0.8 / 2.1, accuracy: 1e-12)
        XCTAssertEqual(model.activeAnchorCount, 1)
        XCTAssertEqual(model.lessonCount, 1, "Public constraints are never personal lessons")
        for (a, b) in zip(rank, try duplicate.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context)) {
            XCTAssertEqual(a.label, b.label); XCTAssertEqual(a.score, b.score, accuracy: 1e-12)
        }
        let corrected = try PersonalInkAnchoredResidualHead(context: context, vocabulary: shared.vocabulary, featureCount: 2,
            lessons: [.init(label: "B", features: [1, 0], baseScores: [0.2, 0.8])], bank: shared)
        XCTAssertEqual(try corrected.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context).first?.label, "B")
        XCTAssertEqual(try model.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context), rank)
    }

    func testNovelLabelsRequireExplicitLessonsNotInventedAnchors() throws {
        let model = try PersonalInkAnchoredResidualHead(context: context, vocabulary: ["A", "B", "△"], featureCount: 2,
            lessons: [.init(label: "△", features: [1, 0], baseScores: [0.5, 0.5, 0])], bank: bank)
        let ranks = try model.rankedCandidates(features: [1, 0], baseScores: [0.5, 0.5, 0], currentContext: context)
        XCTAssertGreaterThan(try XCTUnwrap(ranks.first { $0.label == "△" }).score, 0)
        XCTAssertEqual(model.activeAnchorCount, 2)
        XCTAssertEqual(model.lessonCount, 1)
    }

    func testInvalidAnchorsQueryAndStaleOrDisabledContextFailClosed() throws {
        for malformed in [PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[0, 0], [0, 1]]),
                          PersonalInkAnchorBank(vocabulary: ["A", "Z"], features: [[1, 0], [0, 1]]),
                          PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, .nan]]),
                          PersonalInkAnchorBank(vocabulary: ["A", "A"], features: [[1, 0], [0, 1]])] {
            XCTAssertThrowsError(try PersonalInkAnchoredResidualHead(context: context, vocabulary: ["A", "B"], featureCount: 2, lessons: [], bank: malformed))
        }
        let model = try PersonalInkAnchoredResidualHead(context: context, vocabulary: ["A", "B"], featureCount: 2,
            lessons: [.init(label: "A", features: [1, 0], baseScores: [0.2, 0.8])], bank: bank)
        var stale = context; stale.profileRevision = UUID()
        XCTAssertThrowsError(try model.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: stale))
        stale = context; stale.isEnabled = false
        XCTAssertThrowsError(try model.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: stale))
        XCTAssertThrowsError(try model.rankedCandidates(features: [0, 0], baseScores: [0.2, 0.8], currentContext: context))
        XCTAssertThrowsError(try model.rankedCandidates(features: [1, 0], baseScores: [2, -1], currentContext: context))
        XCTAssertThrowsError(try PersonalInkAnchoredResidualHead(context: stale, vocabulary: ["A", "B"], featureCount: 2, lessons: [], bank: bank))
    }

    func testAnchorOrderDoesNotChangePredictions() throws {
        let reordered = PersonalInkAnchorBank(vocabulary: ["B", "A"], features: [[0, 1], [1, 0]])
        let lessons: [PersonalInkResidualHead.Lesson] = [.init(label: "A", features: [sqrt(0.5), sqrt(0.5)], baseScores: [0.2, 0.8])]
        let a = try PersonalInkAnchoredResidualHead(context: context, vocabulary: bank.vocabulary, featureCount: 2, lessons: lessons, bank: bank)
        let b = try PersonalInkAnchoredResidualHead(context: context, vocabulary: bank.vocabulary, featureCount: 2, lessons: lessons, bank: reordered)
        XCTAssertEqual(try a.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context),
                       try b.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context))
    }
}
