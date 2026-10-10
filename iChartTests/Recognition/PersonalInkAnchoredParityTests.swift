#if DEBUG && canImport(CoreML)
import CryptoKit
import XCTest
@testable import iChart

final class PersonalInkAnchoredParityTests: XCTestCase {
    private struct Sample: Decodable {
        let identity: String
        let writer: String
        let session: Int
        let label: String
        let strokes: [[InkPoint]]
        let embedding: [Double]
        let genericLogits: [Double]
    }
    private struct Packet: Decodable { let vocabulary: [String]; let samples: [Sample] }
    private struct Row: Decodable {
        let queryID: String
        let personalRanks: [Rank]
        let eligible: Bool
    }
    private struct Rank: Decodable { let label: String; let score: Double }
    private struct Task: Decodable { let supportLabels: [String]; let rows: [Row] }
    private struct Report: Decodable {
        let version: String
        let weightsSHA256: String
        let anchorSHA256: String
        let reservedWritersEvaluated: Bool
        let results: [String: Task]
    }

    func testEntireFrozenAnchorComparisonMatchesSwiftWithActualCoreMLInputs() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let packetPath = env["ICHART_PERSONAL_RESIDUAL_PARITY"],
              let reportPath = env["ICHART_PERSONAL_ANCHOR_REPORT"] else {
            throw XCTSkip("Provide the frozen public encoder, original trajectories and anchored reference report")
        }
        let reportURL = URL(fileURLWithPath: reportPath), packetURL = URL(fileURLWithPath: packetPath)
        let reportBytes = try Data(contentsOf: reportURL), packetBytes = try Data(contentsOf: packetURL)
        let report = try JSONDecoder().decode(Report.self, from: reportBytes)
        let packet = try JSONDecoder().decode(Packet.self, from: packetBytes)
        XCTAssertEqual(report.version, PersonalInkAnchoredResidualHead.version)
        XCTAssertEqual(report.weightsSHA256, "5cddc61266d283af28eecfba3bbd8ec6a5b4e396e36b2dba8751b93c880d70a0")
        XCTAssertEqual(report.anchorSHA256, PersonalInkVisualEncoder.anchorSHA256)
        XCTAssertEqual(SHA256.hash(data: reportBytes).map { String(format: "%02x", $0) }.joined(),
                       "3abe14e0845da4488a65db808455f1df8695df8515fe3a2d92c04862e3014391")
        XCTAssertFalse(report.reservedWritersEvaluated)
        XCTAssertEqual(packet.samples.count, 1_552)
        XCTAssertEqual(Set(packet.samples.map(\.identity)).count, 1_552)
        XCTAssertTrue(packet.samples.allSatisfy { $0.writer.hasPrefix("trn_") })
        XCTAssertEqual(Set(report.results.keys), ["sparse16", "full97"])
        guard testRun?.failureCount == 0 else { return }
        let encoder = try PersonalInkVisualEncoder(directory: URL(fileURLWithPath: directory))
        let bank = try XCTUnwrap(encoder.anchorBank)
        XCTAssertEqual(packet.vocabulary, encoder.vocabulary)
        var encoded: [String: PersonalInkVisualFeatures] = [:]
        var maxFeatureError = 0.0, maxLogitError = 0.0, maxRankError = 0.0
        for sample in packet.samples {
            let actual = try encoder.encode(sample.strokes.map { .init(points: $0) })
            maxFeatureError = max(maxFeatureError, zip(actual.embedding, sample.embedding).map { abs($0 - $1) }.max() ?? .infinity)
            maxLogitError = max(maxLogitError, zip(actual.genericLogits, sample.genericLogits).map { abs($0 - $1) }.max() ?? .infinity)
            encoded[sample.identity] = actual
        }
        XCTAssertLessThanOrEqual(maxFeatureError, 1e-4)
        XCTAssertLessThanOrEqual(maxLogitError, 1e-4)
        let writers = Set(packet.samples.map(\.writer)).sorted()
        XCTAssertEqual(writers.count, 8)
        var compared = 0
        for (name, task) in report.results {
            XCTAssertEqual(task.supportLabels.count, name == "sparse16" ? 16 : 97)
            XCTAssertEqual(task.rows.count, 776)
            XCTAssertEqual(Set(task.rows.map(\.queryID)).count, 776)
            XCTAssertEqual(task.rows.filter(\.eligible).count, 772)
            let expected = Dictionary(uniqueKeysWithValues: task.rows.map { ($0.queryID, $0.personalRanks) })
            for writer in writers {
                let support = packet.samples.filter { $0.writer == writer && $0.session == 1 && task.supportLabels.contains($0.label) }
                let queries = packet.samples.filter { $0.writer == writer && $0.session == 2 }
                XCTAssertEqual(support.count, task.supportLabels.count)
                XCTAssertEqual(queries.count, 97)
                let context = PersonalInkResidualHead.Context(isEnabled: true, profileRevision: UUID(), encoderIdentity: encoder.identity)
                let lessons = try support.map { sample -> PersonalInkResidualHead.Lesson in
                    let value = try XCTUnwrap(encoded[sample.identity])
                    return .init(label: sample.label, features: value.embedding,
                                 baseScores: try PersonalInkResidualHead.normalizedScores(logits: value.genericLogits))
                }
                let model = try PersonalInkAnchoredResidualHead(context: context, vocabulary: packet.vocabulary,
                                                                featureCount: 128, lessons: lessons, bank: bank)
                for query in queries {
                    let input = try XCTUnwrap(encoded[query.identity])
                    let actual = try model.rankedCandidates(features: input.embedding,
                        baseScores: PersonalInkResidualHead.normalizedScores(logits: input.genericLogits), currentContext: context)
                    let ranks = try XCTUnwrap(expected[query.identity])
                    XCTAssertEqual(Array(actual.prefix(5)).map(\.label), ranks.map(\.label), "\(name):\(query.identity)")
                    for (a, b) in zip(actual, ranks) { maxRankError = max(maxRankError, abs(a.score - b.score)) }
                    compared += 1
                }
            }
        }
        XCTAssertEqual(compared, 1_552)
        XCTAssertLessThanOrEqual(maxRankError, 1e-4)
        XCTAssertEqual(try Data(contentsOf: reportURL), reportBytes)
        XCTAssertEqual(try Data(contentsOf: packetURL), packetBytes)
        print("PERSONAL_ANCHORED_SWIFT_PARITY inputs=1552 rankedQueries=\(compared) featureError=\(maxFeatureError) logitError=\(maxLogitError) rankError=\(maxRankError)")
    }
}
#endif
