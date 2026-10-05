import CryptoKit
import XCTest
@testable import iChart

/// Freezes hypotheses from existing public generic ranks. This file neither
/// decodes truth/writer fields nor performs inference, teaching or scoring.
final class PersonalInkMLChordPublicRankReplayTests: XCTestCase {
    private typealias Replay = PersonalInkMLChordPublicRankReplay

    func testProvidedPublicRanksFreezeCompleteTokenPredictions() throws {
        guard let (inputPath, outputPath) = try Replay.environmentPaths(ProcessInfo.processInfo.environment) else {
            throw XCTSkip("Provide ICHART_PUBLIC_COMPLETE_TOKEN_INPUT and a new ICHART_PUBLIC_COMPLETE_TOKEN_PREDICTIONS path")
        }
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        try Replay.validatePaths(input: inputURL, output: outputURL)
        let properties = try inputURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = properties.fileSize, size <= Replay.maximumInputBytes else { throw Replay.Failure.invalidInput }
        let bytes = try Data(contentsOf: inputURL)
        guard Replay.digest(bytes) == Replay.pinnedInputSHA256 else { throw Replay.Failure.invalidInput }
        let input = try Replay.decodeBlind(bytes)
        try Replay.validateProvidedInput(input)
        let root = Replay.repositoryRoot()
        let files = try Replay.sourceIdentity(repositoryRoot: root)
        guard files[Replay.composerSourcePath] == Replay.pinnedComposerSHA256 else { throw Replay.Failure.changedSource }
        let metadata = try Replay.makeMetadata(input: input, inputPath: inputURL.path,
            inputSHA256: Replay.digest(bytes), sourceFilesSHA256: files)
        let packet = Replay.freeze(input, metadata: metadata)
        XCTAssertEqual(packet.rows.count, 3104)
        XCTAssertEqual(packet.rows.map(\.id), input.rows.map(\.id))
        guard testRun?.failureCount == 0,
              try Data(contentsOf: inputURL) == bytes,
              try Replay.sourceIdentity(repositoryRoot: root) == files else { throw Replay.Failure.changedSource }
        try Replay.writePacket(packet, to: outputURL, input: inputURL)
        print("PUBLIC_COMPLETE_TOKEN_PREDICTIONS rows=3104 routes=6208 inferenceRuns=0 scoringRuns=0")
    }

    private func reading(_ tokens: [String], sourceCount: Int? = nil) -> Replay.BlindReading {
        .init(sourceStrokeCount: sourceCount ?? tokens.count, encoderIdentity: "synthetic-frozen-encoder",
              glyphs: tokens.enumerated().map { .init(originalStrokeIndexes: [$0.offset],
                  generic: [.init(label: $0.element, score: 1)]) })
    }
    private func fixture(_ rows: [Replay.BlindRow]) -> Replay.Input {
        .init(version: "public-conditional-identity-v1", sourceSHA256: String(repeating: "a", count: 64),
              sourceRecords: 1, evaluatedRecords: 1, evaluatedWriters: 8, reservedWriterTransformsOrInference: 0,
              codeSHA256: ["prior.swift": String(repeating: "b", count: 64)],
              runtimeFilesSHA256: ["manifest.json": String(repeating: "c", count: 64)],
              runtimeSHA256: String(repeating: "d", count: 64), encoderIdentity: "synthetic-frozen-encoder",
              vocabularySHA256: String(repeating: "e", count: 64), profileRevision: UUID(), profileEnabled: true,
              glyphLessonCount: 0, wholeChordLessonCount: 0, parserRuns: 0, wholeChordInferenceRuns: 0, rows: rows)
    }
    private func metadata(_ input: Replay.Input, path: String = "/synthetic/input.json", hash: String? = nil) throws -> Replay.Metadata {
        try Replay.makeMetadata(input: input, inputPath: path, inputSHA256: hash ?? Replay.pinnedInputSHA256,
            sourceFilesSHA256: [Replay.composerSourcePath: Replay.pinnedComposerSHA256,
                                "synthetic-replay.swift": String(repeating: "f", count: 64)])
    }

    func testBlindProjectionIgnoresMutatedTruthWriterSourceIDsAndPersonalRanks() throws {
        let input = fixture([.init(id: "synthetic-1", arm: .isolatedPoints32,
            sourceOwnerReading: reading(["C"]), automaticReading: reading(["C"]))])
        let original = try Replay.encoded(input)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        rows[0]["expectedTokens"] = ["poison"]
        rows[0]["writers"] = ["ignored-person"]
        rows[0]["sourceIDs"] = ["ignored-source-label"]
        rows[0]["oracleOrderedTop1Exact"] = true
        rows[0]["automaticIdentity"] = "deliberately wrong ignored type"
        var owner = try XCTUnwrap(rows[0]["sourceOwnerReading"] as? [String: Any])
        var glyphs = try XCTUnwrap(owner["glyphs"] as? [[String: Any]])
        glyphs[0]["personal"] = [["label": ["wrong-type"], "score": "wrong-type"]]
        owner["glyphs"] = glyphs; rows[0]["sourceOwnerReading"] = owner; object["rows"] = rows
        object["summaries"] = "ignored scoring material"
        let mutated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let projected = try Replay.decodeBlind(mutated)
        XCTAssertEqual(projected, try Replay.decodeBlind(original))
        XCTAssertEqual(Replay.freeze(projected, metadata: try metadata(input)),
                       Replay.freeze(input, metadata: try metadata(input)))
        XCTAssertNotEqual(Replay.digest(mutated), Replay.digest(original), "The full source-byte commitment still detects changed input")
    }

    func testFreezeRetainsEveryRowAndBothRoutesIncludingRejectedAndFailedReadings() throws {
        let input = fixture([
            .init(id: "valid", arm: .isolatedPoints32, sourceOwnerReading: reading(["C", "7"]), automaticReading: reading(["A", "7"])),
            .init(id: "rejected", arm: .adjacentSecond32Gap8, sourceOwnerReading: reading(["C", ">"]), automaticReading: reading(["C", "!"])),
            .init(id: "failed", arm: .isolatedPoints32, sourceOwnerReading: reading(["C"], sourceCount: 0), automaticReading: reading(["C"], sourceCount: 2))
        ])
        let packet = Replay.freeze(input, metadata: try metadata(input))
        XCTAssertEqual(packet.rows.map(\.id), ["valid", "rejected", "failed"])
        XCTAssertEqual(packet.rows[0].sourceOwner.composerResult?.candidates.first?.text, "C7")
        XCTAssertEqual(packet.rows[0].automatic.composerResult?.candidates.first?.text, "A7")
        XCTAssertEqual(packet.rows[1].sourceOwner.composerResult?.rejectedCompleteSequenceCount, 1)
        XCTAssertEqual(packet.rows[1].automatic.composerResult?.candidates, [])
        XCTAssertNil(packet.rows[1].sourceOwner.failure)
        XCTAssertEqual(packet.rows[2].sourceOwner.failure, "invalidSourceStrokeCount")
        XCTAssertEqual(packet.rows[2].automatic.failure, "invalidPartition")
        XCTAssertNil(packet.rows[2].sourceOwner.composerResult)
        XCTAssertNil(packet.rows[2].automatic.composerResult)
        for row in packet.rows {
            for route in [row.sourceOwner, row.automatic] {
                XCTAssertNotEqual(route.composerResult == nil, route.failure == nil)
            }
        }
    }

    func testLegacyGreedyHandlingAndExactIncomingRankSourceReceiptsRemainSeparate() throws {
        let input = Replay.BlindReading(sourceStrokeCount: 4, encoderIdentity: "synthetic-frozen-encoder", glyphs: [
            .init(originalStrokeIndexes: [2, 0], generic: [.init(label: "C", score: 2), .init(label: "A", score: 1)]),
            .init(originalStrokeIndexes: [1], generic: [.init(label: " ", score: 1)]),
            .init(originalStrokeIndexes: [3], generic: [.init(label: "7", score: 1)])
        ])
        let result = Replay.replay(input)
        XCTAssertEqual(result.originalTop1Tokens, ["C", " ", "7"])
        XCTAssertEqual(result.legacyGreedyText, "C7", "Retain the previous parser's exact joined-top-1 behavior")
        XCTAssertEqual(result.columns.map(\.originalStrokeIndexes), [[2, 0], [1], [3]])
        XCTAssertEqual(result.columns.map(\.ranks), input.glyphs.map(\.generic))
        XCTAssertEqual(result.composerResult?.candidates, [], "The composer cannot discard a whitespace column")
        XCTAssertEqual(result.composerResult?.examinedSequenceCount, 2)
        XCTAssertEqual(result.composerResult?.rejectedCompleteSequenceCount, 2)
        XCTAssertNil(result.failure)
        let absent = Replay.BlindReading(sourceStrokeCount: 1, encoderIdentity: input.encoderIdentity,
            glyphs: [.init(originalStrokeIndexes: [0], generic: [])])
        XCTAssertEqual(Replay.replay(absent).originalTop1Tokens, [nil])
        XCTAssertNil(Replay.replay(absent).legacyGreedyText)
        XCTAssertEqual(Replay.replay(absent).failure, "invalidRanks")
    }

    func testExclusiveWriteRejectsOverwriteAliasesSymlinksAndBlankEnvironmentPaths() throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inputURL = folder.appendingPathComponent("input.json"), outputURL = folder.appendingPathComponent("predictions.json")
        let input = fixture([.init(id: "synthetic", arm: .isolatedPoints32,
            sourceOwnerReading: reading(["C"]), automaticReading: reading(["C"]))])
        let bytes = try Replay.encoded(input)
        try bytes.write(to: inputURL, options: .withoutOverwriting)
        let packet = Replay.freeze(input, metadata: try metadata(input, path: inputURL.path, hash: Replay.digest(bytes)))
        try Replay.writePacket(packet, to: outputURL, input: inputURL)
        let frozen = try Data(contentsOf: outputURL)
        XCTAssertThrowsError(try Replay.writePacket(packet, to: outputURL, input: inputURL))
        XCTAssertEqual(try Data(contentsOf: outputURL), frozen)
        XCTAssertEqual(try Data(contentsOf: inputURL), bytes)
        XCTAssertThrowsError(try Replay.validatePaths(input: inputURL, output: inputURL))
        let linkedInput = folder.appendingPathComponent("input-link.json")
        try FileManager.default.createSymbolicLink(at: linkedInput, withDestinationURL: inputURL)
        XCTAssertThrowsError(try Replay.validatePaths(input: linkedInput, output: folder.appendingPathComponent("new.json")))
        let linkedOutput = folder.appendingPathComponent("output-link.json")
        try FileManager.default.createSymbolicLink(at: linkedOutput, withDestinationURL: folder.appendingPathComponent("missing.json"))
        XCTAssertThrowsError(try Replay.validatePaths(input: inputURL, output: linkedOutput))
        XCTAssertThrowsError(try Replay.environmentPaths(["ICHART_PUBLIC_COMPLETE_TOKEN_INPUT": " \n"]))
        XCTAssertThrowsError(try Replay.environmentPaths(["ICHART_PUBLIC_COMPLETE_TOKEN_INPUT": "relative.json",
            "ICHART_PUBLIC_COMPLETE_TOKEN_PREDICTIONS": "/synthetic/new.json"]))
        XCTAssertNil(try Replay.environmentPaths([:]))
    }

    func testPacketRoundTripPreservesInputRuntimeSourceSnapshotsAndLabelFreeReceipts() throws {
        let input = fixture([.init(id: "synthetic", arm: .isolatedPoints32,
            sourceOwnerReading: reading(["C"]), automaticReading: reading(["A"]))])
        let packet = Replay.freeze(input, metadata: try metadata(input))
        let bytes = try Replay.encoded(packet)
        XCTAssertEqual(try JSONDecoder().decode(Replay.Packet.self, from: bytes), packet)
        XCTAssertEqual(packet.version, "public-complete-token-predictions-v1")
        XCTAssertEqual(packet.metadata.inputSHA256, Replay.pinnedInputSHA256)
        XCTAssertEqual(packet.metadata.composerSourceSHA256, Replay.pinnedComposerSHA256)
        XCTAssertEqual(packet.metadata.runtimeFilesSHA256, input.runtimeFilesSHA256)
        XCTAssertEqual(packet.metadata.runtimeSHA256, input.runtimeSHA256)
        XCTAssertEqual(packet.metadata.encoderIdentity, input.encoderIdentity)
        XCTAssertEqual(packet.metadata.profileRevision, input.profileRevision)
        XCTAssertEqual(packet.metadata.priorCodeSHA256, input.codeSHA256)
        XCTAssertEqual(packet.metadata.sourceSnapshotSHA256, Replay.digest(try Replay.encoded(packet.metadata.sourceFilesSHA256)))
        let text = String(decoding: bytes, as: UTF8.self)
        for forbiddenKey in ["expectedTokens", "writers", "sourceIDs", "correct", "personal"] {
            XCTAssertFalse(text.contains("\"\(forbiddenKey)\":"))
        }
    }
}

/// Internal visibility supports a separate scorer which verifies this packet
/// before decoding labeled material. No truth-bearing fields exist here.
enum PersonalInkMLChordPublicRankReplay {
    static let pinnedInputSHA256 = "c4b6acc6caf76e0f7d0af9ee8036cd672673f1690e790fee3dcf14fea329c01b"
    static let pinnedComposerSHA256 = "d2988c65de55ee43e8462cbee5063c532f27c43a479c2c1f9307acb92562d288"
    static let composerSourcePath = "iChart/Recognition/PersonalInkMLChordComposer.swift"
    static let maximumInputBytes = 64 * 1024 * 1024
    enum Failure: Error { case invalidInput, invalidPath, outputExists, changedSource }
    enum Arm: String, Codable { case isolatedPoints32, adjacentSecond32Gap8 }
    struct BlindGlyph: Codable, Equatable {
        let originalStrokeIndexes: [Int]
        let generic: [PersonalInkLearnedComparison.Rank]
    }
    struct BlindReading: Codable, Equatable {
        let sourceStrokeCount: Int
        let encoderIdentity: String
        let glyphs: [BlindGlyph]
    }
    struct BlindRow: Codable, Equatable {
        let id: String
        let arm: Arm
        let sourceOwnerReading: BlindReading
        let automaticReading: BlindReading
    }
    struct Input: Codable, Equatable {
        let version: String
        let sourceSHA256: String
        let sourceRecords: Int
        let evaluatedRecords: Int
        let evaluatedWriters: Int
        let reservedWriterTransformsOrInference: Int
        let codeSHA256: [String: String]
        let runtimeFilesSHA256: [String: String]
        let runtimeSHA256: String
        let encoderIdentity: String
        let vocabularySHA256: String
        let profileRevision: UUID
        let profileEnabled: Bool
        let glyphLessonCount: Int
        let wholeChordLessonCount: Int
        let parserRuns: Int
        let wholeChordInferenceRuns: Int
        let rows: [BlindRow]
    }
    struct FrozenReading: Codable, Equatable {
        let sourceStrokeCount: Int
        let encoderIdentity: String
        let columns: [PersonalInkMLChordComposer.Column]
        let originalTop1Tokens: [String?]
        let legacyGreedyText: String?
        let composerResult: PersonalInkMLChordComposer.Result?
        let failure: String?
    }
    struct Row: Codable, Equatable {
        let id: String
        let arm: Arm
        let sourceOwner: FrozenReading
        let automatic: FrozenReading
    }
    struct Metadata: Codable, Equatable {
        let inputPath: String
        let inputSHA256: String
        let inputVersion: String
        let composerSourcePath: String
        let composerSourceSHA256: String
        let sourceFilesSHA256: [String: String]
        let sourceSnapshotSHA256: String
        let sourceSHA256: String
        let sourceRecords: Int
        let evaluatedRecords: Int
        let evaluatedWriters: Int
        let reservedWriterTransformsOrInference: Int
        let priorCodeSHA256: [String: String]
        let runtimeFilesSHA256: [String: String]
        let runtimeSHA256: String
        let encoderIdentity: String
        let vocabularySHA256: String
        let profileRevision: UUID
        let profileEnabled: Bool
        let glyphLessonCount: Int
        let wholeChordLessonCount: Int
        let priorParserRuns: Int
        let priorWholeChordInferenceRuns: Int
    }
    struct Packet: Codable, Equatable {
        var version = "public-complete-token-predictions-v1"
        let metadata: Metadata
        let rows: [Row]
    }

    static func decodeBlind(_ data: Data) throws -> Input {
        guard data.count <= maximumInputBytes else { throw Failure.invalidInput }
        return try JSONDecoder().decode(Input.self, from: data)
    }
    static func validateProvidedInput(_ input: Input) throws {
        guard input.version == "public-conditional-identity-v1", input.rows.count == 3104,
              Set(input.rows.map(\.id)).count == 3104,
              input.rows.filter({ $0.arm == .isolatedPoints32 }).count == 1552,
              input.rows.filter({ $0.arm == .adjacentSecond32Gap8 }).count == 1552,
              input.evaluatedRecords == 1552, input.evaluatedWriters == 8,
              input.glyphLessonCount == 0, input.wholeChordLessonCount == 0, input.profileEnabled,
              input.reservedWriterTransformsOrInference == 0, input.parserRuns == 0, input.wholeChordInferenceRuns == 0,
              !input.encoderIdentity.isEmpty, !input.runtimeFilesSHA256.isEmpty, !input.codeSHA256.isEmpty,
              input.rows.allSatisfy({ !$0.id.isEmpty && $0.sourceOwnerReading.encoderIdentity == input.encoderIdentity
                  && $0.automaticReading.encoderIdentity == input.encoderIdentity }) else { throw Failure.invalidInput }
    }
    static func legacyGreedyText(_ tokens: [String?]) -> String? {
        guard !tokens.isEmpty, tokens.allSatisfy({ $0 != nil }) else { return nil }
        return (try? ChordSymbolParser.parse(tokens.compactMap { $0 }.joined()))?.displayText
    }
    static func replay(_ reading: BlindReading) -> FrozenReading {
        let columns = reading.glyphs.map { PersonalInkMLChordComposer.Column(originalStrokeIndexes: $0.originalStrokeIndexes, ranks: $0.generic) }
        let tokens = reading.glyphs.map { $0.generic.first?.label }
        let result: PersonalInkMLChordComposer.Result?
        let failure: String?
        do {
            result = try PersonalInkMLChordComposer().compose(sourceStrokeCount: reading.sourceStrokeCount, orderedColumns: columns)
            failure = nil
        } catch {
            result = nil; failure = String(describing: error)
        }
        return .init(sourceStrokeCount: reading.sourceStrokeCount, encoderIdentity: reading.encoderIdentity,
            columns: columns, originalTop1Tokens: tokens, legacyGreedyText: legacyGreedyText(tokens),
            composerResult: result, failure: failure)
    }
    static func freeze(_ input: Input, metadata: Metadata) -> Packet {
        .init(metadata: metadata, rows: input.rows.map { .init(id: $0.id, arm: $0.arm,
            sourceOwner: replay($0.sourceOwnerReading), automatic: replay($0.automaticReading)) })
    }
    static func makeMetadata(input: Input, inputPath: String, inputSHA256: String,
                             sourceFilesSHA256: [String: String]) throws -> Metadata {
        guard let composerHash = sourceFilesSHA256[composerSourcePath] else { throw Failure.changedSource }
        return .init(inputPath: inputPath, inputSHA256: inputSHA256, inputVersion: input.version,
            composerSourcePath: composerSourcePath, composerSourceSHA256: composerHash,
            sourceFilesSHA256: sourceFilesSHA256, sourceSnapshotSHA256: digest(try encoded(sourceFilesSHA256)),
            sourceSHA256: input.sourceSHA256, sourceRecords: input.sourceRecords,
            evaluatedRecords: input.evaluatedRecords, evaluatedWriters: input.evaluatedWriters,
            reservedWriterTransformsOrInference: input.reservedWriterTransformsOrInference,
            priorCodeSHA256: input.codeSHA256, runtimeFilesSHA256: input.runtimeFilesSHA256,
            runtimeSHA256: input.runtimeSHA256, encoderIdentity: input.encoderIdentity,
            vocabularySHA256: input.vocabularySHA256, profileRevision: input.profileRevision,
            profileEnabled: input.profileEnabled, glyphLessonCount: input.glyphLessonCount,
            wholeChordLessonCount: input.wholeChordLessonCount, priorParserRuns: input.parserRuns,
            priorWholeChordInferenceRuns: input.wholeChordInferenceRuns)
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static func sourceIdentity(repositoryRoot: URL) throws -> [String: String] {
        let paths = [composerSourcePath,
            "iChart/Recognition/PersonalInkLearnedComparison.swift",
            "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChartTests/Recognition/PersonalInkMLChordPublicRankReplayTests.swift",
            "iChartTests/Recognition/PersonalInkMLChordPublicReplayScoringTests.swift",
            "docs/personal-complete-token-public-replay-protocol-2026-09-30.md",
            "iChart/Services/ChartParsers.swift", "iChart/Models/MusicTheory.swift", "iChart/Models/ChordEvent.swift"]
        return try Dictionary(uniqueKeysWithValues: paths.map { ($0, digest(try Data(contentsOf: repositoryRoot.appendingPathComponent($0)))) })
    }
    static func environmentPaths(_ environment: [String: String]) throws -> (String, String)? {
        let names = ["ICHART_PUBLIC_COMPLETE_TOKEN_INPUT", "ICHART_PUBLIC_COMPLETE_TOKEN_PREDICTIONS"]
        for value in names.compactMap({ environment[$0] }) {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.hasPrefix("/") else { throw Failure.invalidPath }
        }
        guard let input = environment[names[0]], let output = environment[names[1]] else { return nil }
        return (input, output)
    }
    static func validatePaths(input: URL, output: URL) throws {
        let manager = FileManager.default
        for url in [input, output] {
            let standardized = url.standardizedFileURL
            guard url.isFileURL, url.path.hasPrefix("/"),
                  standardized.path == standardized.resolvingSymlinksInPath().path,
                  (try? manager.destinationOfSymbolicLink(atPath: standardized.path)) == nil else { throw Failure.invalidPath }
        }
        guard input.standardizedFileURL != output.standardizedFileURL else { throw Failure.invalidPath }
        let properties = try input.resourceValues(forKeys: [.isRegularFileKey])
        guard properties.isRegularFile == true else { throw Failure.invalidPath }
        var parentIsDirectory = ObjCBool(false)
        guard manager.fileExists(atPath: output.deletingLastPathComponent().path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else { throw Failure.invalidPath }
        guard !manager.fileExists(atPath: output.path) else { throw Failure.outputExists }
    }
    static func writePacket(_ packet: Packet, to output: URL, input: URL) throws {
        try validatePaths(input: input, output: output)
        guard packet.metadata.inputPath == input.standardizedFileURL.path,
              digest(try Data(contentsOf: input)) == packet.metadata.inputSHA256 else { throw Failure.changedSource }
        try encoded(packet).write(to: output, options: .withoutOverwriting)
    }
}
