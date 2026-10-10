import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Synthetic arrays only: no profile, ink, encoder, model inference, routing,
/// acceptance, or production comparison enters this operational-scale parity.
final class PersonalInkLocalAnchoredOperationalScaleTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Rank: Decodable { let label: String; let score: Double }
        struct Lesson: Decodable {
            let lessonID: String
            let label: String
            let feature: [Double]
            let baseScores: [Double]
        }
        struct Query: Decodable {
            let queryID: String
            let feature: [Double]
            let baseScores: [Double]
            let ranks: [Rank]
        }
        struct Case: Decodable {
            let caseID: String
            let vocabulary: [String]
            let lessonCount: Int
            let distinctLessonLabelCount: Int
            let explicitNovelLabelCount: Int
            let untaughtPublicAnchorCount: Int
            let lessons: [Lesson]
            let queryCount: Int
            let queries: [Query]
        }
        let schemaVersion: String
        let syntheticFeaturesAndScores: Bool
        let privateDataUsed: Bool
        let encoderInference: Bool
        let headVersion: String
        let featureCount: Int
        let width: Double
        let regularization: Double
        let modelManifestSHA256: String
        let publicVocabularySHA256: String
        let publicVocabulary: [String]
        let bankFeatures: [[Double]]
        let pythonCodeSHA256: [String: String]
        let cases: [Case]
    }

    func testEntireCallerBoundOperationalScaleFixtureMatchesCompletePythonRanks() throws {
        let environment = ProcessInfo.processInfo.environment
        let pathValue = environment["ICHART_LOCAL_ANCHORED_OPERATIONAL_FIXTURE"]
        let digestValue = environment["ICHART_LOCAL_ANCHORED_OPERATIONAL_FIXTURE_SHA256"]
        if pathValue == nil && digestValue == nil {
            throw XCTSkip("Provide the frozen synthetic operational-scale fixture and SHA-256")
        }
        let path = try XCTUnwrap(pathValue, "ICHART_LOCAL_ANCHORED_OPERATIONAL_FIXTURE is required")
        let expectedDigest = try XCTUnwrap(
            digestValue,
            "ICHART_LOCAL_ANCHORED_OPERATIONAL_FIXTURE_SHA256 is required"
        )
        XCTAssertEqual(expectedDigest, "dee6122a950d69fa103b709c4339f6064b77030b3477d2e5a5eefb263302f0a4")
        let url = URL(fileURLWithPath: path)
        let originalBytes = try Data(contentsOf: url)
        XCTAssertEqual(originalBytes.count, 1_363_014)
        let actualDigest = Self.digest(originalBytes)
        guard actualDigest == expectedDigest else {
            XCTFail("Operational-scale fixture digest does not match the caller-bound SHA-256")
            return
        }

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
        let topKeys: Set<String> = [
            "bankFeatures", "cases", "encoderInference", "featureCount", "headVersion",
            "modelManifestSHA256", "privateDataUsed", "publicVocabulary", "publicVocabularySHA256",
            "pythonCodeSHA256", "regularization", "schemaVersion", "syntheticFeaturesAndScores", "width"
        ]
        guard Set(raw.keys) == topKeys,
              let rawCases = raw["cases"] as? [[String: Any]], rawCases.count == 2 else {
            XCTFail("Unexpected operational-scale fixture schema")
            return
        }
        let caseKeys: Set<String> = [
            "caseID", "distinctLessonLabelCount", "explicitNovelLabelCount", "lessonCount", "lessons",
            "queries", "queryCount", "untaughtPublicAnchorCount", "vocabulary"
        ]
        let lessonKeys: Set<String> = ["baseScores", "feature", "label", "lessonID"]
        let queryKeys: Set<String> = ["baseScores", "feature", "queryID", "ranks"]
        let rankKeys: Set<String> = ["label", "score"]
        for rawCase in rawCases {
            guard Set(rawCase.keys) == caseKeys,
                  let lessons = rawCase["lessons"] as? [[String: Any]],
                  let queries = rawCase["queries"] as? [[String: Any]],
                  lessons.allSatisfy({ Set($0.keys) == lessonKeys }),
                  queries.allSatisfy({ query in
                      Set(query.keys) == queryKeys
                          && (query["ranks"] as? [[String: Any]])?.allSatisfy({ Set($0.keys) == rankKeys }) == true
                  }) else {
                XCTFail("Unexpected nested operational-scale fixture schema")
                return
            }
        }

        let fixture = try JSONDecoder().decode(Fixture.self, from: originalBytes)
        XCTAssertEqual(fixture.schemaVersion, "personal-local-anchored-operational-scale-python-parity-v1")
        XCTAssertTrue(fixture.syntheticFeaturesAndScores)
        XCTAssertFalse(fixture.privateDataUsed)
        XCTAssertFalse(fixture.encoderInference)
        XCTAssertEqual(fixture.headVersion, PersonalInkLocalAnchoredResidualHead.version)
        XCTAssertEqual(fixture.featureCount, PersonalInkLocalAnchoredResidualHead.maximumFeatureCount)
        XCTAssertEqual(fixture.width.bitPattern, PersonalInkLocalAnchoredResidualHead.kernelWidth.bitPattern)
        XCTAssertEqual(fixture.regularization.bitPattern,
                       PersonalInkLocalAnchoredResidualHead.regularization.bitPattern)
        XCTAssertEqual(fixture.modelManifestSHA256,
                       "d74225d5d1b77def8cdf2c46813048698e4f76448c5dbc169a047b86ff9122b1")
        Self.assertDigest(fixture.modelManifestSHA256)
        Self.assertDigest(fixture.publicVocabularySHA256)
        XCTAssertEqual(Self.vocabularyDigest(fixture.publicVocabulary), fixture.publicVocabularySHA256)
        XCTAssertTrue((2...512).contains(fixture.publicVocabulary.count))
        XCTAssertEqual(Set(fixture.publicVocabulary).count, fixture.publicVocabulary.count)
        XCTAssertTrue(fixture.publicVocabulary.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(fixture.bankFeatures.count, fixture.publicVocabulary.count)
        XCTAssertTrue(fixture.bankFeatures.allSatisfy { Self.isUnit($0, count: fixture.featureCount) })
        XCTAssertEqual(Set(fixture.pythonCodeSHA256.keys), Set([
            "recognition_ml/ichart_recognition_ml/research/personal_anchors.py",
            "recognition_ml/ichart_recognition_ml/research/personal_local.py",
            "recognition_ml/ichart_recognition_ml/research/personal_local_anchors.py",
            "recognition_ml/ichart_recognition_ml/research/personal_residual.py"
        ]))
        for value in fixture.pythonCodeSHA256.values { Self.assertDigest(value) }
        XCTAssertEqual(Set(fixture.cases.map(\.caseID)), Set(["sparse16", "maximum192"]))
        guard testRun?.failureCount == 0 else { return }

        let publicSet = Set(fixture.publicVocabulary)
        let bank = PersonalInkAnchorBank(vocabulary: fixture.publicVocabulary, features: fixture.bankFeatures)
        for testCase in fixture.cases {
            let expectedLessonCount: Int
            let expectedDistinctCount: Int
            switch testCase.caseID {
            case "sparse16": expectedLessonCount = 16; expectedDistinctCount = 13
            case "maximum192": expectedLessonCount = PersonalInkProfile.maximumExamples; expectedDistinctCount = 1
            default:
                XCTFail("Unexpected case ID \(testCase.caseID)")
                return
            }
            XCTAssertEqual(testCase.lessonCount, expectedLessonCount)
            XCTAssertEqual(testCase.lessons.count, expectedLessonCount)
            XCTAssertEqual(testCase.distinctLessonLabelCount, expectedDistinctCount)
            XCTAssertEqual(testCase.explicitNovelLabelCount, 1)
            XCTAssertEqual(testCase.queryCount, 6)
            XCTAssertEqual(testCase.queries.count, 6)
            XCTAssertTrue(testCase.vocabulary.starts(with: fixture.publicVocabulary))
            XCTAssertEqual(Set(testCase.vocabulary).count, testCase.vocabulary.count)
            let novelLabels = testCase.vocabulary.filter { !publicSet.contains($0) }
            XCTAssertEqual(novelLabels, ["△"])
            XCTAssertEqual(novelLabels.count, testCase.explicitNovelLabelCount)
            XCTAssertEqual(Set(testCase.lessons.map(\.label)).count, testCase.distinctLessonLabelCount)
            XCTAssertEqual(Set(testCase.lessons.map(\.lessonID)).count, testCase.lessonCount)
            XCTAssertTrue(testCase.lessons.allSatisfy {
                !$0.lessonID.isEmpty && testCase.vocabulary.contains($0.label)
                    && Self.isUnit($0.feature, count: fixture.featureCount)
                    && Self.isNormalized($0.baseScores, count: testCase.vocabulary.count)
            })
            let taughtLabels = Set(testCase.lessons.map(\.label))
            let untaughtAnchorCount = fixture.publicVocabulary.filter { !taughtLabels.contains($0) }.count
            XCTAssertEqual(testCase.untaughtPublicAnchorCount, untaughtAnchorCount)
            XCTAssertGreaterThan(untaughtAnchorCount, 0)
            XCTAssertEqual(Set(testCase.queries.map(\.queryID)).count, testCase.queryCount)
            XCTAssertTrue(testCase.queries.allSatisfy { query in
                !query.queryID.isEmpty
                    && Self.isUnit(query.feature, count: fixture.featureCount)
                    && Self.isNormalized(query.baseScores, count: testCase.vocabulary.count)
                    && query.ranks.count == testCase.vocabulary.count
                    && Set(query.ranks.map(\.label)) == Set(testCase.vocabulary)
                    && query.ranks.allSatisfy { $0.score.isFinite }
            })
            guard testRun?.failureCount == 0 else { return }

            let context = PersonalInkResidualHead.Context(
                isEnabled: true,
                profileRevision: UUID(),
                encoderIdentity: actualDigest + ":" + testCase.caseID
            )
            let lessons = testCase.lessons.map {
                PersonalInkResidualHead.Lesson(label: $0.label, features: $0.feature, baseScores: $0.baseScores)
            }
            let fitStart = ProcessInfo.processInfo.systemUptime
            let head = try PersonalInkLocalAnchoredResidualHead(
                context: context,
                vocabulary: testCase.vocabulary,
                featureCount: fixture.featureCount,
                lessons: lessons,
                bank: bank
            )
            let fitMilliseconds = (ProcessInfo.processInfo.systemUptime - fitStart) * 1_000
            XCTAssertEqual(head.lessonCount, testCase.lessonCount)
            XCTAssertEqual(head.activeAnchorCount, testCase.untaughtPublicAnchorCount)

            var maximumScoreError = 0.0
            var queryMilliseconds: [Double] = []
            for query in testCase.queries {
                let queryStart = ProcessInfo.processInfo.systemUptime
                let actual = try head.rankedCandidates(
                    features: query.feature,
                    baseScores: query.baseScores,
                    currentContext: context
                )
                queryMilliseconds.append((ProcessInfo.processInfo.systemUptime - queryStart) * 1_000)
                XCTAssertEqual(actual.count, testCase.vocabulary.count, query.queryID)
                XCTAssertEqual(actual.map(\.label), query.ranks.map(\.label), query.queryID)
                XCTAssertEqual(actual.first?.label, query.ranks.first?.label, query.queryID + " top-one")
                for (swift, python) in zip(actual, query.ranks) {
                    let error = abs(swift.score - python.score)
                    maximumScoreError = max(maximumScoreError, error)
                    XCTAssertLessThanOrEqual(error, 1e-4, query.queryID + ":" + python.label)
                }
            }
            let totalQueryMilliseconds = queryMilliseconds.reduce(0, +)
            print("PERSONAL_LOCAL_ANCHORED_OPERATIONAL_SCALE case=\(testCase.caseID) lessons=\(testCase.lessonCount) anchors=\(testCase.untaughtPublicAnchorCount) queries=\(testCase.queryCount) fitMilliseconds=\(fitMilliseconds) totalQueryMilliseconds=\(totalQueryMilliseconds) perQueryMilliseconds=\(queryMilliseconds) maxScoreError=\(maximumScoreError)")
        }
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }

    private static func isUnit(_ values: [Double], count: Int) -> Bool {
        values.count == count && values.allSatisfy(\.isFinite)
            && abs(sqrt(values.reduce(0) { $0 + $1 * $1 }) - 1) <= 1e-3
    }

    private static func isNormalized(_ values: [Double], count: Int) -> Bool {
        values.count == count && values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
            && abs(values.reduce(0, +) - 1) <= 1e-8
    }

    private static func vocabularyDigest(_ vocabulary: [String]) -> String {
        var data = Data()
        for label in vocabulary {
            data.append(contentsOf: label.precomposedStringWithCanonicalMapping.utf8)
            data.append(0)
        }
        return digest(data)
    }

    private static func assertDigest(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value.count, 64, file: file, line: line)
        XCTAssertTrue(value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }, file: file, line: line)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
