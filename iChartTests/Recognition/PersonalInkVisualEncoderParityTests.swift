#if canImport(CoreML)
import CoreML
import CryptoKit
import XCTest
@testable import iChart

/// Research-only bridge using actual app rasterization and personal fitting.
/// An external artifact is never installed, taught, or added to app assets.
final class PersonalInkVisualEncoderParityTests: XCTestCase {
    private struct Packet: Decodable {
        var version: String
        var researchOnly: Bool
        var sourceSHA256: String
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
    }
    private struct Query: Decodable { var identity: String; var ranks: [Rank] }
    private struct Rank: Decodable { var label: String; var score: Double }

    func testProvidedPrivateTraceComparesFrozenPersonalGlyphEmbeddingsWithoutLearning() throws {
        let env = ProcessInfo.processInfo.environment
        guard let packetPath = env["ICHART_PERSONAL_ENCODER_PARITY"],
              let modelPath = env["ICHART_PERSONAL_ENCODER_MODEL"],
              let tracePath = env["ICHART_PERSONAL_EVIDENCE_TRACE"],
              let profilePath = env["ICHART_PERSONAL_EVIDENCE_PROFILE"],
              let pipeline = env["ICHART_PERSONAL_EVIDENCE_PIPELINE"] else {
            throw XCTSkip("Supply exact trace, enabled frozen profile and research encoder for read-only comparison")
        }
        let packet = try JSONDecoder().decode(Packet.self, from: Data(contentsOf: URL(fileURLWithPath: packetPath)))
        let traceURL = URL(fileURLWithPath: tracePath), profileURL = URL(fileURLWithPath: profilePath)
        let traceBytes = try Data(contentsOf: traceURL), profileBytes = try Data(contentsOf: profileURL)
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: profileBytes)
        XCTAssertTrue(profile.isEnabled, "This comparison cannot enable a disabled personal profile")
        XCTAssertTrue(packet.researchOnly)
        XCTAssertEqual(packet.version, "personal-visual-encoder-v1")
        let artifact = URL(fileURLWithPath: modelPath)
        XCTAssertEqual(try packageDigest(artifact), packet.modelPackageSHA256)
        guard testRun?.failureCount == 0 else { return }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: MLModel.compileModel(at: artifact), configuration: configuration)
        let examples = profile.examples.filter { $0.kind == .glyph }.sorted { $0.id.uuidString < $1.id.uuidString }
        let fitted = try PersonalInkBalancedRidge.fit(
            features: examples.map { try embedding(model: model, strokes: $0.strokes) },
            labels: examples.map(\.label), regularization: 0.1)
        let snapshot = PersonalInkSnapshot(profile: profile)
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL).loadEvents()
            .filter { $0.recognitionPipelineVersion == pipeline && ["finish_single", "finish_batch"].contains($0.stage) }
        var rows: [[String: Any]] = [], seen = Set<[InkStroke]>()
        for (pass, event) in events.enumerated() {
            for payload in event.payloads {
                let ink = try XCTUnwrap(payload.inkStrokes)
                let clusters = StrokeClusterer().indexedClusters(ink.map { InkStroke(points: $0.points) })
                var columns: [[[String: Any]]] = [], tokens: [String] = []
                for indexed in clusters {
                    let feature = try embedding(model: model, strokes: indexed.cluster.strokes)
                    var ranks: [Rank] = []
                    for (label, weight) in zip(fitted.labels, fitted.weights) {
                        var score = 0.0
                        for i in feature.indices { score += weight[i] * feature[i] }
                        ranks.append(Rank(label: label, score: score))
                    }
                    ranks.sort { $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score }
                    if let first = ranks.first { tokens.append(first.label) }
                    columns.append(ranks.prefix(3).map { ["label": $0.label, "score": $0.score] })
                }
                rows.append(["pass": pass, "style": event.layoutStyle ?? "unknown",
                    "targetIndex": payload.targetIndex, "uniqueInput": seen.insert(ink).inserted,
                    "inputFingerprint": PersonalInkEvaluationStore.fingerprint(strokes: ink),
                    "knownWholeInk": snapshot.wasAlreadyLearned(strokes: ink),
                    "native": payload.matchText ?? "no-read",
                    "existingPersonal": snapshot.suggestion(strokes: ink)?.text ?? "no-suggestion",
                    "glyphRanks": columns, "originalIndexes": clusters.map(\.originalIndexes),
                    "composedTop1Tokens": tokens.joined(),
                    "composedTop1Chord": tokens.count == clusters.count && !tokens.isEmpty
                        ? (ChordRecognitionCompendium.match(tokens.joined())?.displayText ?? "invalid") : "incomplete",
                    "rankOnlyNotAccepted": true])
            }
        }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(try Data(contentsOf: traceURL), traceBytes)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileBytes)
        XCTAssertEqual(try packageDigest(artifact), packet.modelPackageSHA256)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = ["scope": "exact seen-input personal glyph research; no learning or accuracy claim",
            "sourcePipeline": pipeline, "traceSHA256": digest(traceBytes), "profileSHA256": digest(profileBytes),
            "profileRevision": profile.revision.uuidString, "profileExampleCount": profile.examples.count,
            "glyphTrainingExamples": examples.count, "glyphLabels": fitted.labels,
            "modelPackageSHA256": packet.modelPackageSHA256, "observations": rows.count,
            "uniqueInputs": seen.count, "rows": rows]
        if let path = env["ICHART_PERSONAL_ENCODER_TRACE_REPORT"] {
            let output = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Use a new diagnostic destination")
            guard testRun?.failureCount == 0 else { return }
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .withoutOverwriting)
        }
        print("PERSONAL_ENCODER_PRIVATE_REPLAY observations=\(rows.count) unique=\(seen.count) glyphLessons=\(examples.count)")
    }

    func testFrozenResearchEncoderMatchesPythonThroughAppRasterizerAndPersonalFit() throws {
        let env = ProcessInfo.processInfo.environment
        guard let packetPath = env["ICHART_PERSONAL_ENCODER_PARITY"],
              let modelPath = env["ICHART_PERSONAL_ENCODER_MODEL"] else {
            throw XCTSkip("Supply the frozen research package and original-trajectory parity packet")
        }
        let packetURL = URL(fileURLWithPath: packetPath)
        let sourceBytes = try Data(contentsOf: packetURL)
        let packet = try JSONDecoder().decode(Packet.self, from: sourceBytes)
        XCTAssertEqual(packet.version, "personal-visual-encoder-v1")
        XCTAssertTrue(packet.researchOnly)
        XCTAssertEqual(packet.sourceSHA256, "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61")
        XCTAssertEqual(packet.samples.count, 112)
        XCTAssertEqual(packet.queries.count, 56)
        XCTAssertEqual(Set(packet.samples.map(\.identity)).count, 112)
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
        var features: [String: [Double]] = [:]
        var maximumError = 0.0
        for sample in packet.samples {
            let raster = try ChordInkRasterizer.rasterize(strokes: sample.strokes.map { InkStroke(points: $0) })
            XCTAssertEqual(digest(Data(raster.pixels)), sample.rasterSHA256, sample.identity)
            let input = try MLMultiArray(shape: [1, 1, 96, 256], dataType: .float32)
            for i in raster.pixels.indices { input[i] = NSNumber(value: Float(raster.pixels[i]) / 255) }
            let provider = try MLDictionaryFeatureProvider(dictionary: ["inkRaster": MLFeatureValue(multiArray: input)])
            let prediction = try model.prediction(from: provider)
            let output = try XCTUnwrap(prediction.featureValue(for: "personalEmbedding")?.multiArrayValue)
            XCTAssertEqual(output.count, 128)
            let actual = (0..<output.count).map { output[$0].doubleValue }
            XCTAssertTrue(actual.allSatisfy(\.isFinite))
            XCTAssertEqual(sample.embedding.count, 128)
            let error = zip(actual, sample.embedding).map { abs($0 - $1) }.max() ?? .infinity
            maximumError = max(maximumError, error)
            XCTAssertLessThanOrEqual(error, 1e-4, sample.identity)
            features[sample.identity] = actual
        }
        let expectedQueries = Dictionary(uniqueKeysWithValues: packet.queries.map { ($0.identity, $0.ranks) })
        var queryCount = 0
        for writer in Set(packet.samples.map(\.writer)).sorted() {
            let support = packet.samples.filter { $0.writer == writer && $0.session == 1 }
            let queries = packet.samples.filter { $0.writer == writer && $0.session == 2 }
            XCTAssertEqual(support.count, 7); XCTAssertEqual(queries.count, 7)
            let fitted = try PersonalInkBalancedRidge.fit(features: support.map { try XCTUnwrap(features[$0.identity]) },
                                                        labels: support.map(\.label), regularization: 0.1)
            for query in queries {
                let feature = try XCTUnwrap(features[query.identity])
                var ranks: [Rank] = []
                for (label, weight) in zip(fitted.labels, fitted.weights) {
                    var score = 0.0
                    for i in feature.indices { score += weight[i] * feature[i] }
                    ranks.append(Rank(label: label, score: score))
                }
                ranks.sort { $0.score == $1.score ? $0.label < $1.label : $0.score > $1.score }
                let expected = try XCTUnwrap(expectedQueries[query.identity])
                XCTAssertEqual(ranks.map(\.label), expected.map(\.label), query.identity)
                for (actual, reference) in zip(ranks, expected) {
                    XCTAssertEqual(actual.score, reference.score, accuracy: 1e-4, query.identity)
                }
                queryCount += 1
            }
        }
        XCTAssertEqual(queryCount, 56)
        XCTAssertEqual(try Data(contentsOf: packetURL), sourceBytes)
        XCTAssertEqual(try packageDigest(artifact), packet.modelPackageSHA256)
        print("PERSONAL_ENCODER_SWIFT_PARITY samples=112 rankings=\(queryCount) maxError=\(maximumError)")
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func embedding(model: MLModel, strokes: [InkStroke]) throws -> [Double] {
        let raster = try ChordInkRasterizer.rasterize(strokes: strokes)
        let input = try MLMultiArray(shape: [1, 1, 96, 256], dataType: .float32)
        for i in raster.pixels.indices { input[i] = NSNumber(value: Float(raster.pixels[i]) / 255) }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["inkRaster": MLFeatureValue(multiArray: input)])
        let prediction = try model.prediction(from: provider)
        let output = try XCTUnwrap(prediction.featureValue(for: "personalEmbedding")?.multiArrayValue)
        XCTAssertEqual(output.count, 128)
        let feature = (0..<output.count).map { output[$0].doubleValue }
        XCTAssertTrue(feature.allSatisfy(\.isFinite))
        return feature
    }

    private func packageDigest(_ directory: URL) throws -> String {
        // Use relative names directly: Foundation exposes /tmp and /private/tmp
        // differently between URL normalization and URL enumeration.
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: directory.path))
        let names = try enumerator.compactMap { $0 as? String }.filter { name in
            let file = directory.appendingPathComponent(name)
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            XCTAssertNotEqual(properties.isSymbolicLink, true)
            return properties.isRegularFile == true
        }.sorted()
        XCTAssertFalse(names.isEmpty)
        var payload = Data()
        for name in names {
            let file = directory.appendingPathComponent(name)
            payload.append(Data(name.utf8)); payload.append(0)
            payload.append(Data(digest(try Data(contentsOf: file)).utf8)); payload.append(10)
        }
        return digest(payload)
    }
}
#endif
