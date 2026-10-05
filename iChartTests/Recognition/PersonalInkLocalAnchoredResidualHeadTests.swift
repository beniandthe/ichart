import CryptoKit
import Foundation
import XCTest
@testable import iChart

final class PersonalInkLocalAnchoredResidualHeadTests: XCTestCase {
    private struct PythonFixture: Decodable {
        struct Rank: Decodable { let label: String; let score: Double }
        let bankFeatures: [[Double]]
        let bankVocabulary: [String]
        let base: [[Double]]
        let codeSHA256: [String: String]
        let features: [[Double]]
        let labels: [String]
        let privateDataUsed: Bool
        let queries: [[Double]]
        let queryBase: [[Double]]
        let ranks: [[Rank]]
        let version: String
        let vocabulary: [String]
        let width: Double
    }

    private let context = PersonalInkResidualHead.Context(
        isEnabled: true,
        profileRevision: UUID(),
        encoderIdentity: "local-anchor-parity-fixture"
    )

    func testFixedContractAndEmptyProfilePreserveEveryCompetitor() throws {
        XCTAssertEqual(PersonalInkLocalAnchoredResidualHead.version, "personal-local-untaught-anchor-v1")
        XCTAssertEqual(PersonalInkLocalAnchoredResidualHead.kernelWidth.bitPattern,
                       0.16684838059285878.bitPattern)
        XCTAssertEqual(PersonalInkLocalAnchoredResidualHead.regularization, 0.1)
        let bank = PersonalInkAnchorBank(vocabulary: ["B", "A"], features: [[0, 1], [1, 0]])
        let head = try PersonalInkLocalAnchoredResidualHead(
            context: context,
            vocabulary: ["B", "A", "△"],
            featureCount: 2,
            lessons: [],
            bank: bank
        )
        let ranks = try head.rankedCandidates(
            features: [1, 0],
            baseScores: [0.4, 0.4, 0.2],
            currentContext: context
        )
        XCTAssertEqual(ranks, [
            .init(label: "A", score: 0.4),
            .init(label: "B", score: 0.4),
            .init(label: "△", score: 0.2)
        ])
        XCTAssertEqual(Set(ranks.map(\.label)), Set(["A", "B", "△"]))
        XCTAssertEqual(head.lessonCount, 0)
        XCTAssertEqual(head.activeAnchorCount, 2)
    }

    func testPythonClosedFormFixtureAndDuplicateLabelBalance() throws {
        let bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [1, 0]])
        let lesson = PersonalInkResidualHead.Lesson(label: "A", features: [1, 0], baseScores: [0.2, 0.8])
        let single = try makeHead(lessons: [lesson], bank: bank)
        let duplicate = try makeHead(lessons: [lesson, lesson], bank: bank)
        let expected = ["A": 0.2 + 0.8 / 2.1, "B": 0.8 - 0.8 / 2.1]
        for head in [single, duplicate] {
            let byLabel = Dictionary(uniqueKeysWithValues: try head.rankedCandidates(
                features: [1, 0], baseScores: [0.2, 0.8], currentContext: context
            ).map { ($0.label, $0.score) })
            XCTAssertEqual(try XCTUnwrap(byLabel["A"]), try XCTUnwrap(expected["A"]), accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(byLabel["B"]), try XCTUnwrap(expected["B"]), accuracy: 1e-12)
        }
        XCTAssertEqual(single.activeAnchorCount, 1)
        XCTAssertEqual(duplicate.lessonCount, 2)
    }

    func testFullBankCoverageMatchesUnanchoredLocalLimitAndDecays() throws {
        let bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, 1]])
        let lessons: [PersonalInkResidualHead.Lesson] = [
            .init(label: "A", features: [1, 0], baseScores: [0.2, 0.8]),
            .init(label: "B", features: [0, 1], baseScores: [0.7, 0.3])
        ]
        let head = try makeHead(lessons: lessons, bank: bank)
        XCTAssertEqual(head.activeAnchorCount, 0)
        let atLesson = try head.rankedCandidates(
            features: [1, 0], baseScores: [0.2, 0.8], currentContext: context
        )
        let far = try head.rankedCandidates(
            features: [-1, 0], baseScores: [0.2, 0.8], currentContext: context
        )
        XCTAssertGreaterThan(try XCTUnwrap(atLesson.first { $0.label == "A" }).score, 0.2)
        XCTAssertEqual(try XCTUnwrap(far.first { $0.label == "A" }).score, 0.2, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(far.first { $0.label == "B" }).score, 0.8, accuracy: 1e-5)
    }

    func testUntaughtAnchorOrderDoesNotChangeRanks() throws {
        let lessons: [PersonalInkResidualHead.Lesson] = [
            .init(label: "A", features: [sqrt(0.5), sqrt(0.5)], baseScores: [0.2, 0.6, 0.2])
        ]
        let first = PersonalInkAnchorBank(
            vocabulary: ["A", "B", "C"],
            features: [[1, 0], [0, 1], [-1, 0]]
        )
        let reversed = PersonalInkAnchorBank(
            vocabulary: ["C", "B", "A"],
            features: [[-1, 0], [0, 1], [1, 0]]
        )
        let a = try PersonalInkLocalAnchoredResidualHead(
            context: context, vocabulary: ["A", "B", "C"], featureCount: 2, lessons: lessons, bank: first
        )
        let b = try PersonalInkLocalAnchoredResidualHead(
            context: context, vocabulary: ["A", "B", "C"], featureCount: 2, lessons: lessons, bank: reversed
        )
        let lhs = try a.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.6, 0.2], currentContext: context)
        let rhs = try b.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.6, 0.2], currentContext: context)
        XCTAssertEqual(lhs.map(\.label), rhs.map(\.label))
        for (left, right) in zip(lhs, rhs) { XCTAssertEqual(left.score, right.score, accuracy: 1e-12) }
    }

    func testExplicitNovelLabelLearnsWithoutInventingNovelAnchor() throws {
        let bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, 1]])
        let head = try PersonalInkLocalAnchoredResidualHead(
            context: context,
            vocabulary: ["A", "B", "△"],
            featureCount: 2,
            lessons: [.init(label: "△", features: [1, 0], baseScores: [0.5, 0.5, 0])],
            bank: bank
        )
        let ranks = try head.rankedCandidates(
            features: [1, 0], baseScores: [0.5, 0.5, 0], currentContext: context
        )
        XCTAssertGreaterThan(try XCTUnwrap(ranks.first { $0.label == "△" }).score, 0)
        XCTAssertEqual(head.activeAnchorCount, 2)
        XCTAssertEqual(ranks.count, 3)
    }

    func testInputsAreValueOwnedAndRefitDoesNotMutateExistingHead() throws {
        var lessons = [PersonalInkResidualHead.Lesson(label: "A", features: [1, 0], baseScores: [0.2, 0.8])]
        var bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, 1]])
        let head = try makeHead(lessons: lessons, bank: bank)
        let before = try head.rankedCandidates(features: [1, 0], baseScores: [0.2, 0.8], currentContext: context)
        lessons[0].features = [0, 1]
        bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[0, 1], [1, 0]])
        _ = try makeHead(lessons: lessons, bank: bank)
        XCTAssertEqual(try head.rankedCandidates(
            features: [1, 0], baseScores: [0.2, 0.8], currentContext: context
        ), before)
    }

    func testMalformedBudgetContextAndQueryInputsFailClosed() throws {
        let bank = PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, 1]])
        for malformed in [
            PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[0, 0], [0, 1]]),
            PersonalInkAnchorBank(vocabulary: ["A", "B"], features: [[1, 0], [0, .nan]]),
            PersonalInkAnchorBank(vocabulary: ["A", "A"], features: [[1, 0], [0, 1]]),
            PersonalInkAnchorBank(vocabulary: ["A", "Z"], features: [[1, 0], [0, 1]])
        ] {
            XCTAssertThrowsError(try makeHead(lessons: [], bank: malformed))
        }
        XCTAssertThrowsError(try PersonalInkLocalAnchoredResidualHead(
            context: context, vocabulary: ["A", "B"], featureCount: 129, lessons: [], bank: bank
        ))
        let tooMany = Array(repeating: PersonalInkResidualHead.Lesson(
            label: "A", features: [1, 0], baseScores: [0.2, 0.8]
        ), count: PersonalInkProfile.maximumExamples + 1)
        XCTAssertThrowsError(try makeHead(lessons: tooMany, bank: bank))

        let head = try makeHead(
            lessons: [.init(label: "A", features: [1, 0], baseScores: [0.2, 0.8])],
            bank: bank
        )
        var stale = context
        stale.profileRevision = UUID()
        XCTAssertThrowsError(try head.rankedCandidates(
            features: [1, 0], baseScores: [0.2, 0.8], currentContext: stale
        ))
        stale = context
        stale.isEnabled = false
        XCTAssertThrowsError(try head.rankedCandidates(
            features: [1, 0], baseScores: [0.2, 0.8], currentContext: stale
        ))
        XCTAssertThrowsError(try head.rankedCandidates(
            features: [0, 0], baseScores: [0.2, 0.8], currentContext: context
        ))
        XCTAssertThrowsError(try head.rankedCandidates(
            features: [1, 0], baseScores: [2, -1], currentContext: context
        ))
        let disabled = PersonalInkResidualHead.Context(
            isEnabled: false, profileRevision: UUID(), encoderIdentity: context.encoderIdentity
        )
        XCTAssertThrowsError(try PersonalInkLocalAnchoredResidualHead(
            context: disabled, vocabulary: ["A", "B"], featureCount: 2, lessons: [], bank: bank
        ))
    }

    func testEntireCallerBoundPythonFixtureMatchesCompleteSwiftRanks() throws {
        let environment = ProcessInfo.processInfo.environment
        let pathValue = environment["ICHART_LOCAL_ANCHOR_PYTHON_FIXTURE"]
        let digestValue = environment["ICHART_LOCAL_ANCHOR_PYTHON_FIXTURE_SHA256"]
        if pathValue == nil && digestValue == nil {
            throw XCTSkip("Provide the frozen synthetic Python fixture path and SHA-256")
        }
        let path = try XCTUnwrap(pathValue, "ICHART_LOCAL_ANCHOR_PYTHON_FIXTURE is required")
        let expectedDigest = try XCTUnwrap(
            digestValue,
            "ICHART_LOCAL_ANCHOR_PYTHON_FIXTURE_SHA256 is required"
        )
        XCTAssertEqual(expectedDigest, "4a9d732156cdc53257a2244adfac5528a611a0574ab4b2a26267a813be20a6c5")
        let url = URL(fileURLWithPath: path)
        let originalBytes = try Data(contentsOf: url)
        let actualDigest = SHA256.hash(data: originalBytes).map { String(format: "%02x", $0) }.joined()
        guard actualDigest == expectedDigest else {
            XCTFail("Python fixture digest does not match the caller-bound SHA-256")
            return
        }
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), Set([
            "bankFeatures", "bankVocabulary", "base", "codeSHA256", "features", "labels",
            "privateDataUsed", "queries", "queryBase", "ranks", "version", "vocabulary", "width"
        ]))
        let fixture = try JSONDecoder().decode(PythonFixture.self, from: originalBytes)
        XCTAssertEqual(fixture.version, "local-anchor-synthetic-python-parity-v1")
        XCTAssertFalse(fixture.privateDataUsed, "The opt-in fixture must remain synthetic-only")
        XCTAssertEqual(fixture.width.bitPattern, PersonalInkLocalAnchoredResidualHead.kernelWidth.bitPattern)
        XCTAssertEqual(fixture.vocabulary.count, 4)
        XCTAssertEqual(Set(fixture.vocabulary).count, fixture.vocabulary.count)
        XCTAssertTrue(fixture.vocabulary.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(fixture.features.count, fixture.labels.count)
        XCTAssertEqual(fixture.features.count, fixture.base.count)
        XCTAssertEqual(fixture.bankFeatures.count, fixture.bankVocabulary.count)
        XCTAssertEqual(fixture.queries.count, 4)
        XCTAssertEqual(fixture.queryBase.count, fixture.queries.count)
        XCTAssertEqual(fixture.ranks.count, fixture.queries.count)
        let featureCount = try XCTUnwrap(fixture.features.first?.count)
        XCTAssertEqual(featureCount, 4)
        XCTAssertTrue((fixture.features + fixture.bankFeatures + fixture.queries).allSatisfy {
            $0.count == featureCount && $0.allSatisfy(\.isFinite)
        })
        XCTAssertTrue((fixture.base + fixture.queryBase).allSatisfy {
            $0.count == fixture.vocabulary.count && $0.allSatisfy(\.isFinite)
        })
        XCTAssertTrue(fixture.ranks.allSatisfy { row in
            row.count == fixture.vocabulary.count
                && Set(row.map(\.label)) == Set(fixture.vocabulary)
                && row.allSatisfy { $0.score.isFinite }
        })
        XCTAssertEqual(Set(fixture.codeSHA256.keys), Set([
            "recognition_ml/ichart_recognition_ml/research/personal_anchors.py",
            "recognition_ml/ichart_recognition_ml/research/personal_local.py",
            "recognition_ml/ichart_recognition_ml/research/personal_local_anchors.py",
            "recognition_ml/ichart_recognition_ml/research/personal_residual.py"
        ]))
        XCTAssertTrue(fixture.codeSHA256.values.allSatisfy {
            $0.count == 64 && $0.allSatisfy { $0.isHexDigit }
        })
        guard testRun?.failureCount == 0 else { return }

        let parityContext = PersonalInkResidualHead.Context(
            isEnabled: true,
            profileRevision: UUID(),
            encoderIdentity: actualDigest
        )
        let lessons = fixture.labels.indices.map { index in
            PersonalInkResidualHead.Lesson(
                label: fixture.labels[index],
                features: fixture.features[index],
                baseScores: fixture.base[index]
            )
        }
        let head = try PersonalInkLocalAnchoredResidualHead(
            context: parityContext,
            vocabulary: fixture.vocabulary,
            featureCount: featureCount,
            lessons: lessons,
            bank: .init(vocabulary: fixture.bankVocabulary, features: fixture.bankFeatures)
        )
        var maximumScoreError = 0.0
        for index in fixture.queries.indices {
            let actual = try head.rankedCandidates(
                features: fixture.queries[index],
                baseScores: fixture.queryBase[index],
                currentContext: parityContext
            )
            let expected = fixture.ranks[index]
            XCTAssertEqual(actual.map(\.label), expected.map(\.label), "query \(index)")
            XCTAssertEqual(actual.first?.label, expected.first?.label, "query \(index) top-one")
            for (swift, python) in zip(actual, expected) {
                let error = abs(swift.score - python.score)
                maximumScoreError = max(maximumScoreError, error)
                XCTAssertLessThanOrEqual(error, 1e-4, "query \(index), label \(python.label)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        print("PERSONAL_LOCAL_ANCHORED_SWIFT_PARITY queries=\(fixture.queries.count) maxScoreError=\(maximumScoreError)")
    }

    private func makeHead(
        lessons: [PersonalInkResidualHead.Lesson],
        bank: PersonalInkAnchorBank
    ) throws -> PersonalInkLocalAnchoredResidualHead {
        try PersonalInkLocalAnchoredResidualHead(
            context: context,
            vocabulary: ["A", "B"],
            featureCount: 2,
            lessons: lessons,
            bank: bank
        )
    }
}
