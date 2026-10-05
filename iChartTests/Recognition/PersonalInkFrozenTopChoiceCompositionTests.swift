#if DEBUG
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Post-inference composition only. Inputs are already frozen ranks, not ink
/// queries or truth labels. No encoder, profile fit, scoring or teaching occurs.
final class PersonalInkFrozenTopChoiceCompositionTests: XCTestCase {
    private struct Request: Decodable {
        let version: String
        let predictionPath: String
        let predictionSHA256: String
        let codeFileMapPath: String
        let codeFileMapSHA256: String
        let frozenCodeRoot: String
        let currentRepositoryRoot: String
        let outputPath: String
    }
    private struct Prediction: Decodable {
        let version: String
        let codeFileMapSHA256: String
        let sourceJournalSHA256: String
        let oldProfileCanonicalSHA256: String
        let newProfileCanonicalSHA256: String
        let oldExampleCount: Int
        let newExampleCount: Int
        let profileChanged: Bool
        let accuracyMeasured: Bool
        let nativeLiveResult: Bool
        let trainingEligible: Bool
        let sources: [Source]
    }
    private struct Source: Decodable {
        let runID: UUID
        let style: String
        let sourcePacketSHA256: String
        let targets: [Target]
    }
    private struct Target: Decodable {
        let recordID: UUID
        let targetOrdinal: Int
        let childToParentVisibleFragmentIndices: [Int]
        let sourcePacketSHA256: String
        let sourcePacketData: Data
        let olderProfileFreeze: Frozen
        let newerProfileFreeze: Frozen
    }
    private struct Frozen: Decodable {
        let version: String
        let rankingScope: String
        let glyphOwnershipVerified: Bool
        let accuracyMeasured: Bool
        let nativeLiveResult: Bool
        let trainingEligible: Bool
        let legacyFreeze: Legacy
        let legacyCanonicalData: Data
        let legacyCanonicalSHA256: String
        let automatic: Arm
        let supplied: Arm?
    }
    private struct Legacy: Decodable {
        let sourcePacketSHA256: String
        let sourceStrokeCount: Int
        let profileSHA256: String
        let codeSHA256: String
        let ownershipReceiptSHA256: String?
    }
    private struct Arm: Decodable {
        let outcome: String
        let anchorStatus: String
        let glyphs: [Glyph]
    }
    private struct Glyph: Decodable {
        let originalStrokeIndexes: [Int]
        let sharedRanks: [PersonalInkLearnedComparison.Rank]
        let originalResidualRanks: [PersonalInkLearnedComparison.Rank]
        let anchoredRanks: [PersonalInkLearnedComparison.Rank]?
    }
    private enum Method: Equatable { case shared, original, anchored }
    private struct Methods: Encodable {
        let sharedML: String?
        let original34: String?
        let original37: String?
        let anchored34: String?
        let anchored37: String?
        private enum CodingKeys: String, CodingKey {
            case sharedML, original34, original37, anchored34, anchored37
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sharedML, forKey: .sharedML)
            try container.encode(original34, forKey: .original34)
            try container.encode(original37, forKey: .original37)
            try container.encode(anchored34, forKey: .anchored34)
            try container.encode(anchored37, forKey: .anchored37)
        }
    }
    private struct Composition: Encodable {
        let runID: UUID
        let recordID: UUID
        let targetOrdinal: Int
        let style: String
        let sourcePacketSHA256: String
        let parentSourcePacketSHA256: String
        let methods: Methods
        let glyphOwnershipVerified = false
    }
    private struct Report: Encodable {
        let version = "frozen-top-choice-composition-v1"
        let requestSHA256: String
        let predictionSHA256: String
        let codeFileMapSHA256: String
        let sourceJournalSHA256: String
        let composerDependencyHashes: [String: String]
        let targets: [Composition]
        let glyphOwnershipVerified = false
        let profileChanged = false
        let inferenceRerun = false
        let accuracyMeasured = false
    }
    private let dependencies: Set<String> = [
        "iChart/Recognition/PersonalInkLearnedComparison.swift",
        "iChart/Services/ChartParsers.swift",
        "iChart/Models/ChordEvent.swift",
        "iChart/Models/MusicTheory.swift",
        "iChart/Services/ChordRecognitionCompendium.swift"
    ]

    func testProvidedFrozenRanksComposeWithoutInferenceOrTruthJoin() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_FROZEN_TOP_CHOICE_REQUEST"] else {
            throw XCTSkip("Provide the committed prediction/code snapshot and a new composition output path")
        }
        let requestURL = file(path)
        let requestData = try bounded(requestURL, maximum: 32_768)
        let request = try JSONDecoder().decode(Request.self, from: requestData)
        guard request.version == "frozen-top-choice-composition-request-v1" else {
            return XCTFail("Unsupported composition request")
        }
        let predictionURL = file(request.predictionPath), mapURL = file(request.codeFileMapPath)
        let frozenRoot = file(request.frozenCodeRoot), currentRoot = file(request.currentRepositoryRoot)
        let output = file(request.outputPath)
        let inputs = [requestURL, predictionURL, mapURL]
        let prohibitedRoots = [frozenRoot, currentRoot] + inputs.map { $0.deletingLastPathComponent() }
        guard !inputs.contains(output), !prohibitedRoots.contains(where: {
            output == $0 || output.path.hasPrefix($0.path + "/")
        }), !FileManager.default.fileExists(atPath: output.path) else {
            return XCTFail("Composition output must be new and separate from inputs and both code roots")
        }
        let predictionData = try bounded(predictionURL, maximum: 64 * 1_024 * 1_024)
        let mapData = try bounded(mapURL, maximum: 1_024 * 1_024)
        guard sha(predictionData) == request.predictionSHA256,
              sha(mapData) == request.codeFileMapSHA256 else {
            return XCTFail("Prediction or frozen code map differs from its committed bytes")
        }
        let map = try JSONDecoder().decode([String: String].self, from: mapData)
        guard dependencies.isSubset(of: Set(map.keys)), try canonical(map) == mapData,
              try fileMap(frozenRoot, paths: Set(map.keys)) == map else {
            return XCTFail("Every frozen source snapshot must match the original prediction code map")
        }
        let composerHashes = try fileMap(currentRoot, paths: dependencies)
        guard composerHashes.allSatisfy({ map[$0.key] == $0.value }) else {
            return XCTFail("Current composer/parser/display dependencies changed since prediction freeze")
        }
        defer {
            XCTAssertEqual(try? Data(contentsOf: requestURL), requestData)
            XCTAssertEqual(try? Data(contentsOf: predictionURL), predictionData)
            XCTAssertEqual(try? Data(contentsOf: mapURL), mapData)
            XCTAssertEqual(try? fileMap(frozenRoot, paths: Set(map.keys)), map)
            XCTAssertEqual(try? fileMap(currentRoot, paths: dependencies), composerHashes)
        }
        let prediction = try JSONDecoder().decode(Prediction.self, from: predictionData)
        guard prediction.version == "fresh-unlabeled-paired-profile-freeze-v1",
              prediction.codeFileMapSHA256 == request.codeFileMapSHA256,
              prediction.oldExampleCount == 34, prediction.newExampleCount == 37,
              !prediction.profileChanged, !prediction.accuracyMeasured,
              !prediction.nativeLiveResult, !prediction.trainingEligible,
              (1...2).contains(prediction.sources.count),
              Set(prediction.sources.map(\.runID)).count == prediction.sources.count,
              Set(prediction.sources.map(\.style)).count == prediction.sources.count else {
            return XCTFail("Unsupported, ambiguous or scored prediction source")
        }
        var compositions: [Composition] = []
        var recordIDs = Set<UUID>()
        for source in prediction.sources {
            guard ["simpleChordSheet", "rhythmSectionSheet"].contains(source.style),
                  source.targets.count <= 64,
                  source.targets.map(\.targetOrdinal) == Array(source.targets.indices) else {
                return XCTFail("Frozen targets must retain their original source order")
            }
            for target in source.targets {
                guard recordIDs.insert(target.recordID).inserted,
                      sha(target.sourcePacketData) == target.sourcePacketSHA256 else {
                    return XCTFail("Duplicate target record or changed child source bytes")
                }
                try validate(target.olderProfileFreeze, target: target,
                    profileSHA256: prediction.oldProfileCanonicalSHA256, codeSHA256: request.codeFileMapSHA256)
                try validate(target.newerProfileFreeze, target: target,
                    profileSHA256: prediction.newProfileCanonicalSHA256, codeSHA256: request.codeFileMapSHA256)
                let old = target.olderProfileFreeze.automatic, new = target.newerProfileFreeze.automatic
                guard old.outcome == new.outcome,
                      old.glyphs.map(\.originalStrokeIndexes) == new.glyphs.map(\.originalStrokeIndexes),
                      old.glyphs.map(\.sharedRanks) == new.glyphs.map(\.sharedRanks) else {
                    return XCTFail("Shared composition requires identical frozen groups and shared ranks")
                }
                compositions.append(.init(runID: source.runID, recordID: target.recordID,
                    targetOrdinal: target.targetOrdinal, style: source.style,
                    sourcePacketSHA256: target.sourcePacketSHA256,
                    parentSourcePacketSHA256: source.sourcePacketSHA256,
                    methods: .init(sharedML: compose(old, method: .shared),
                        original34: compose(old, method: .original), original37: compose(new, method: .original),
                        anchored34: compose(old, method: .anchored), anchored37: compose(new, method: .anchored))))
            }
        }
        // Revalidate before publication, including every original code snapshot.
        XCTAssertEqual(try Data(contentsOf: requestURL), requestData)
        XCTAssertEqual(try Data(contentsOf: predictionURL), predictionData)
        XCTAssertEqual(try Data(contentsOf: mapURL), mapData)
        XCTAssertEqual(try fileMap(frozenRoot, paths: Set(map.keys)), map)
        XCTAssertEqual(try fileMap(currentRoot, paths: dependencies), composerHashes)
        guard testRun?.failureCount == 0 else { return }
        let data = try canonical(Report(requestSHA256: sha(requestData), predictionSHA256: sha(predictionData),
            codeFileMapSHA256: sha(mapData), sourceJournalSHA256: prediction.sourceJournalSHA256,
            composerDependencyHashes: composerHashes, targets: compositions))
        guard data.count <= 1_024 * 1_024 else { return XCTFail("Composition report budget exceeded") }
        try data.write(to: output, options: .withoutOverwriting)
        XCTAssertEqual(try Data(contentsOf: output), data)
        print("FROZEN_TOP_CHOICE_COMPOSITION targets=\(compositions.count) inferenceRerun=false accuracyMeasured=false reportSHA256=\(sha(data))")
    }

    func testMissingGlyphCannotBeSilentlyShortenedAndNoReadsEncodeAsNull() throws {
        let missingCases: [[String?]] = [["C", nil, "7"], ["C", "", "7"]]
        for labels in missingCases {
            let arm = syntheticArm(labels)
            for method in [Method.shared, .original, .anchored] { XCTAssertNil(compose(arm, method: method)) }
        }
        let nonRead = Arm(outcome: "invalid-ink", anchorStatus: "available", glyphs: [])
        for method in [Method.shared, .original, .anchored] { XCTAssertNil(compose(nonRead, method: method)) }
        let arm = syntheticArm(["C", nil, "7"])
        let methods = Methods(sharedML: compose(arm, method: .shared),
            original34: compose(arm, method: .original), original37: compose(arm, method: .original),
            anchored34: compose(arm, method: .anchored), anchored37: compose(arm, method: .anchored))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(methods)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["sharedML", "original34", "original37", "anchored34", "anchored37"])
        XCTAssertTrue(object.values.allSatisfy { $0 is NSNull })
    }

    func testInvalidCompletePunctuationCannotBeSilentlyDropped() {
        let arm = syntheticArm(["C", ">", "7"])
        for method in [Method.shared, .original, .anchored] { XCTAssertNil(compose(arm, method: method)) }
    }

    private func compose(_ arm: Arm, method: Method) -> String? {
        guard arm.outcome == "read", method != .anchored || arm.anchorStatus == "available" else { return nil }
        // Map, never compactMap: one missing glyph invalidates the complete
        // sequence. Incoming glyph order and only the first rank are preserved.
        let choices: [String?] = arm.glyphs.map { glyph in
            switch method {
            case .shared: return glyph.sharedRanks.first?.label
            case .original: return glyph.originalResidualRanks.first?.label
            case .anchored: return glyph.anchoredRanks?.first?.label
            }
        }
        guard choices.allSatisfy({ $0?.isEmpty == false }) else { return nil }
        return PersonalInkLearnedComparison.compose(choices)
    }

    private func syntheticArm(_ labels: [String?]) -> Arm {
        .init(outcome: "read", anchorStatus: "available", glyphs: labels.enumerated().map { index, label in
            let ranks = label.map { [PersonalInkLearnedComparison.Rank(label: $0, score: 1)] } ?? []
            return .init(originalStrokeIndexes: [index], sharedRanks: ranks,
                originalResidualRanks: ranks, anchoredRanks: ranks)
        })
    }

    private func validate(_ frozen: Frozen, target: Target, profileSHA256: String, codeSHA256: String) throws {
        let legacy = frozen.legacyFreeze, arm = frozen.automatic
        guard frozen.version == "blind-ink-anchored-comparison-freeze-v1",
              frozen.rankingScope == "same-reader-returned-top-three", frozen.supplied == nil,
              !frozen.glyphOwnershipVerified, !frozen.accuracyMeasured,
              !frozen.nativeLiveResult, !frozen.trainingEligible,
              sha(frozen.legacyCanonicalData) == frozen.legacyCanonicalSHA256,
              legacy.sourcePacketSHA256 == target.sourcePacketSHA256,
              legacy.sourceStrokeCount == target.childToParentVisibleFragmentIndices.count,
              legacy.profileSHA256 == profileSHA256, legacy.codeSHA256 == codeSHA256,
              legacy.ownershipReceiptSHA256 == nil,
              ["available", "unavailable"].contains(arm.anchorStatus) else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        if arm.glyphs.isEmpty {
            guard arm.outcome != "read" else { throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage }
            return
        }
        let indexes = arm.glyphs.flatMap(\.originalStrokeIndexes)
        guard (1...16).contains(arm.glyphs.count),
              arm.glyphs.allSatisfy({ !$0.originalStrokeIndexes.isEmpty
                && $0.originalStrokeIndexes == $0.originalStrokeIndexes.sorted() }),
              indexes.count == legacy.sourceStrokeCount,
              Set(indexes) == Set(0..<legacy.sourceStrokeCount),
              arm.glyphs.allSatisfy({ glyph in
                  validRanks(glyph.sharedRanks) && validRanks(glyph.originalResidualRanks)
                    && (glyph.anchoredRanks.map(validRanks) ?? true)
              }) else { throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage }
    }

    private func validRanks(_ ranks: [PersonalInkLearnedComparison.Rank]) -> Bool {
        ranks.count <= 3 && Set(ranks.map(\.label)).count == ranks.count
            && ranks.allSatisfy { $0.label.count <= 1 && $0.score.isFinite }
            && zip(ranks, ranks.dropFirst()).allSatisfy {
                $0.0.score > $0.1.score || ($0.0.score == $0.1.score && $0.0.label < $0.1.label)
            }
    }
    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }
    private func bounded(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximum else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximum else { throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage }
        return data
    }
    private func fileMap(_ root: URL, paths: Set<String>) throws -> [String: String] {
        guard (1...1_024).contains(paths.count) else { throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage }
        var result: [String: String] = [:]
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let url = root.appendingPathComponent(path).standardizedFileURL
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  url.path.hasPrefix(root.path + "/"), url.resolvingSymlinksInPath() == url else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            result[path] = sha(try bounded(url, maximum: 4 * 1_024 * 1_024))
        }
        return result
    }
    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
