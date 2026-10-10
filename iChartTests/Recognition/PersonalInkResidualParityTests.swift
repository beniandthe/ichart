#if canImport(CoreML)
import CoreML
import CryptoKit
import XCTest
@testable import iChart

final class PersonalInkResidualParityTests: XCTestCase {
    private struct Packet: Decodable {
        var version: String
        var residualVersion: String
        var researchOnly: Bool
        var includesGenericLogits: Bool
        var vocabulary: [String]
        var modelPackageSHA256: String
        var samples: [Sample]
        var queries: [Query]
    }
    private struct Sample: Decodable {
        var identity: String
        var writer: String
        var session: Int
        var label: String
        var strokes: [[InkPoint]]
        var rasterSHA256: String
        var embedding: [Double]
        var genericLogits: [Double]
    }
    private struct Query: Decodable { var identity: String; var ranks: [Rank] }
    private struct Rank: Decodable { var label: String; var score: Double }

    func testEntireFrozenDevelopmentComparisonMatchesSwiftAndCoreML() throws {
        let env = ProcessInfo.processInfo.environment
        guard let packetPath = env["ICHART_PERSONAL_RESIDUAL_PARITY"],
              let modelPath = env["ICHART_PERSONAL_RESIDUAL_MODEL"] else {
            throw XCTSkip("Provide the frozen residual research package and 1552-sample parity packet")
        }
        let url = URL(fileURLWithPath: packetPath)
        let sourceBytes = try Data(contentsOf: url)
        let packet = try JSONDecoder().decode(Packet.self, from: sourceBytes)
        XCTAssertEqual(packet.version, "personal-residual-parity-v1")
        XCTAssertEqual(packet.residualVersion, PersonalInkResidualHead.version)
        XCTAssertTrue(packet.researchOnly)
        XCTAssertTrue(packet.includesGenericLogits)
        XCTAssertEqual(packet.samples.count, 1_552)
        XCTAssertEqual(Set(packet.samples.map(\.identity)).count, 1_552)
        XCTAssertEqual(packet.queries.count, 776)
        XCTAssertEqual(Set(packet.queries.map(\.identity)).count, 776)
        XCTAssertEqual(packet.vocabulary.count, 97)
        XCTAssertTrue(packet.samples.allSatisfy { $0.writer.hasPrefix("trn_") })
        let artifact = URL(fileURLWithPath: modelPath)
        XCTAssertEqual(try packageDigest(artifact), packet.modelPackageSHA256)
        guard testRun?.failureCount == 0 else { return }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let compiled = try MLModel.compileModel(at: artifact)
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        XCTAssertEqual(model.modelDescription.inputDescriptionsByName["inkRaster"]?.multiArrayConstraint?.shape.map(\.intValue), [1, 1, 96, 256])
        XCTAssertEqual(model.modelDescription.outputDescriptionsByName["personalEmbedding"]?.multiArrayConstraint?.shape.map(\.intValue), [1, 128])
        XCTAssertEqual(model.modelDescription.outputDescriptionsByName["genericLogits"]?.multiArrayConstraint?.shape.map(\.intValue), [1, 97])
        var embeddings: [String: [Double]] = [:], normalizedScores: [String: [Double]] = [:]
        var maxFeatureError = 0.0, maxLogitError = 0.0
        for sample in packet.samples {
            let raster = try ChordInkRasterizer.rasterize(strokes: sample.strokes.map { InkStroke(points: $0) })
            XCTAssertEqual(digest(Data(raster.pixels)), sample.rasterSHA256, sample.identity)
            let input = try MLMultiArray(shape: [1, 1, 96, 256], dataType: .float32)
            for i in raster.pixels.indices { input[i] = NSNumber(value: Float(raster.pixels[i]) / 255) }
            let provider = try MLDictionaryFeatureProvider(dictionary: ["inkRaster": MLFeatureValue(multiArray: input)])
            let prediction = try model.prediction(from: provider)
            let featureArray = try XCTUnwrap(prediction.featureValue(for: "personalEmbedding")?.multiArrayValue)
            let logitArray = try XCTUnwrap(prediction.featureValue(for: "genericLogits")?.multiArrayValue)
            let feature = (0..<featureArray.count).map { featureArray[$0].doubleValue }
            let logits = (0..<logitArray.count).map { logitArray[$0].doubleValue }
            XCTAssertEqual(feature.count, sample.embedding.count)
            XCTAssertEqual(logits.count, sample.genericLogits.count)
            XCTAssertTrue(feature.allSatisfy(\.isFinite) && logits.allSatisfy(\.isFinite))
            let featureError = zip(feature, sample.embedding).map { abs($0 - $1) }.max() ?? .infinity
            let logitError = zip(logits, sample.genericLogits).map { abs($0 - $1) }.max() ?? .infinity
            maxFeatureError = max(maxFeatureError, featureError)
            maxLogitError = max(maxLogitError, logitError)
            XCTAssertLessThanOrEqual(featureError, 1e-4, sample.identity)
            XCTAssertLessThanOrEqual(logitError, 1e-4, sample.identity)
            embeddings[sample.identity] = feature
            normalizedScores[sample.identity] = try PersonalInkResidualHead.normalizedScores(logits: logits)
        }
        let expected = Dictionary(uniqueKeysWithValues: packet.queries.map { ($0.identity, $0.ranks) })
        let writers = Set(packet.samples.map(\.writer)).sorted()
        XCTAssertEqual(writers.count, 8)
        var comparedQueries = 0
        for writer in writers {
            let support = packet.samples.filter { $0.writer == writer && $0.session == 1 }
            let queries = packet.samples.filter { $0.writer == writer && $0.session == 2 }
            XCTAssertEqual(support.count, 97); XCTAssertEqual(queries.count, 97)
            let context = PersonalInkResidualHead.Context(isEnabled: true, profileRevision: UUID(),
                                                          encoderIdentity: packet.modelPackageSHA256)
            let lessons = try support.map { sample in
                PersonalInkResidualHead.Lesson(label: sample.label, features: try XCTUnwrap(embeddings[sample.identity]),
                                              baseScores: try XCTUnwrap(normalizedScores[sample.identity]))
            }
            let personal = try PersonalInkResidualHead(context: context, vocabulary: packet.vocabulary,
                                                       featureCount: 128, lessons: lessons)
            for query in queries {
                let actual = try personal.rankedCandidates(features: XCTUnwrap(embeddings[query.identity]),
                    baseScores: XCTUnwrap(normalizedScores[query.identity]), currentContext: context)
                let reference = try XCTUnwrap(expected[query.identity])
                XCTAssertEqual(Array(actual.prefix(reference.count)).map(\.label), reference.map(\.label), query.identity)
                for (a, b) in zip(actual, reference) { XCTAssertEqual(a.score, b.score, accuracy: 1e-4, query.identity) }
                comparedQueries += 1
            }
        }
        XCTAssertEqual(comparedQueries, 776)
        XCTAssertEqual(try Data(contentsOf: url), sourceBytes)
        XCTAssertEqual(try packageDigest(artifact), packet.modelPackageSHA256)
        print("PERSONAL_RESIDUAL_SWIFT_PARITY inputs=1552 queries=\(comparedQueries) featureError=\(maxFeatureError) logitError=\(maxLogitError)")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func packageDigest(_ directory: URL) throws -> String {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: directory.path))
        let names = try enumerator.compactMap { $0 as? String }.filter { name in
            let properties = try directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertNotEqual(properties.isSymbolicLink, true)
            return properties.isRegularFile == true
        }.sorted()
        XCTAssertFalse(names.isEmpty)
        var payload = Data()
        for name in names {
            payload.append(Data(name.utf8)); payload.append(0)
            payload.append(Data(digest(try Data(contentsOf: directory.appendingPathComponent(name))).utf8)); payload.append(10)
        }
        return digest(payload)
    }
}
#endif
