#if DEBUG
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Test-only post-inference composition of already frozen first choices. No
/// encoder, profile fit, teaching, truth join, scoring or inference occurs.
final class PersonalInkAppendOnlyGlyphSetupCompositionTests: XCTestCase {
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
    private struct SupportLesson: Codable {
        let id: UUID
        let label: String
        let kind: PersonalInkExampleKind
        let source: PersonalInkExampleSource
        let exampleData: Data
        let exampleSHA256: String
    }
    private struct SupportDelta: Codable {
        let referenceCount: Int
        let candidateCount: Int
        let addedLessons: [SupportLesson]
    }
    private struct Prediction: Decodable {
        let version: String
        let codeFileMapSHA256: String
        let sourceJournalSHA256: String
        let referenceProfileCanonicalSHA256: String
        let candidateProfileCanonicalSHA256: String
        let referenceExampleCount: Int
        let candidateExampleCount: Int
        let supportDelta: SupportDelta
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
        let referenceProfileFreeze: Frozen
        let candidateProfileFreeze: Frozen
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
    private struct Legacy: Decodable, Equatable {
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
        let originalReference: String?
        let originalCandidate: String?
        let anchoredReference: String?
        let anchoredCandidate: String?
        private enum CodingKeys: String, CodingKey {
            case sharedML, originalReference, originalCandidate, anchoredReference, anchoredCandidate
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sharedML, forKey: .sharedML)
            try container.encode(originalReference, forKey: .originalReference)
            try container.encode(originalCandidate, forKey: .originalCandidate)
            try container.encode(anchoredReference, forKey: .anchoredReference)
            try container.encode(anchoredCandidate, forKey: .anchoredCandidate)
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
        let version = "append-only-glyph-setup-top-choice-composition-v2"
        let requestSHA256: String
        let predictionSHA256: String
        let codeFileMapSHA256: String
        let sourceJournalSHA256: String
        let referenceProfileCanonicalSHA256: String
        let candidateProfileCanonicalSHA256: String
        let referenceExampleCount: Int
        let candidateExampleCount: Int
        let supportDelta: SupportDelta
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
        "iChart/Services/ChordRecognitionCompendium.swift",
        "iChart/Recognition/ChordInkPersonalization.swift",
        "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
        "iChart/Recognition/PersonalInkBlindPredictionFreeze.swift",
        "iChart/Recognition/InkTrajectoryTypes.swift",
        "iChart/Recognition/PersonalInkLearningLineage.swift"
    ]

    func testProvidedAppendOnlySetupFrozenRanksComposeWithoutInferenceOrTruthJoin() throws {
        guard let path = ProcessInfo.processInfo.environment[
            "ICHART_APPEND_ONLY_GLYPH_SETUP_COMPOSITION_REQUEST"
        ] else {
            throw XCTSkip("Provide the committed v2 prediction/code snapshot and a new composition output path")
        }
        let requestURL = file(path)
        let requestData = try bounded(requestURL, maximum: 32_768)
        let request = try JSONDecoder().decode(Request.self, from: requestData)
        guard request.version == "append-only-glyph-setup-top-choice-composition-request-v2" else {
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
            return XCTFail("Current composer/parser/validation dependencies changed since prediction freeze")
        }
        defer {
            XCTAssertEqual(try? Data(contentsOf: requestURL), requestData)
            XCTAssertEqual(try? Data(contentsOf: predictionURL), predictionData)
            XCTAssertEqual(try? Data(contentsOf: mapURL), mapData)
            XCTAssertEqual(try? fileMap(frozenRoot, paths: Set(map.keys)), map)
            XCTAssertEqual(try? fileMap(currentRoot, paths: dependencies), composerHashes)
        }
        let prediction = try JSONDecoder().decode(Prediction.self, from: predictionData)
        guard prediction.version == "fresh-unlabeled-append-only-glyph-profile-freeze-v2",
              prediction.codeFileMapSHA256 == request.codeFileMapSHA256,
              isSHA256(prediction.sourceJournalSHA256),
              isSHA256(prediction.referenceProfileCanonicalSHA256),
              isSHA256(prediction.candidateProfileCanonicalSHA256),
              prediction.referenceProfileCanonicalSHA256 != prediction.candidateProfileCanonicalSHA256,
              !prediction.profileChanged, !prediction.accuracyMeasured,
              !prediction.nativeLiveResult, !prediction.trainingEligible,
              (1...2).contains(prediction.sources.count),
              Set(prediction.sources.map(\.runID)).count == prediction.sources.count,
              Set(prediction.sources.map(\.style)).count == prediction.sources.count else {
            return XCTFail("Unsupported, ambiguous or scored prediction source")
        }
        try validateSupportDelta(prediction.supportDelta,
            referenceCount: prediction.referenceExampleCount, candidateCount: prediction.candidateExampleCount)
        var compositions: [Composition] = []
        var recordIDs = Set<UUID>()
        for source in prediction.sources {
            guard ["simpleChordSheet", "rhythmSectionSheet"].contains(source.style),
                  isSHA256(source.sourcePacketSHA256), source.targets.count <= 64,
                  source.targets.map(\.targetOrdinal) == Array(source.targets.indices) else {
                return XCTFail("Frozen targets must retain their original source order")
            }
            for target in source.targets {
                guard recordIDs.insert(target.recordID).inserted,
                      sha(target.sourcePacketData) == target.sourcePacketSHA256 else {
                    return XCTFail("Duplicate target record or changed child source bytes")
                }
                try validate(target.referenceProfileFreeze, target: target,
                    profileSHA256: prediction.referenceProfileCanonicalSHA256, codeSHA256: request.codeFileMapSHA256)
                try validate(target.candidateProfileFreeze, target: target,
                    profileSHA256: prediction.candidateProfileCanonicalSHA256, codeSHA256: request.codeFileMapSHA256)
                let reference = target.referenceProfileFreeze.automatic
                let candidate = target.candidateProfileFreeze.automatic
                guard reference.outcome == candidate.outcome,
                      reference.glyphs.map(\.originalStrokeIndexes) == candidate.glyphs.map(\.originalStrokeIndexes),
                      reference.glyphs.map(\.sharedRanks) == candidate.glyphs.map(\.sharedRanks) else {
                    return XCTFail("Shared composition requires identical frozen groups and shared ranks")
                }
                compositions.append(.init(runID: source.runID, recordID: target.recordID,
                    targetOrdinal: target.targetOrdinal, style: source.style,
                    sourcePacketSHA256: target.sourcePacketSHA256,
                    parentSourcePacketSHA256: source.sourcePacketSHA256,
                    methods: methods(reference: reference, candidate: candidate)))
            }
        }
        // Revalidate every bound input and source snapshot before publication.
        XCTAssertEqual(try Data(contentsOf: requestURL), requestData)
        XCTAssertEqual(try Data(contentsOf: predictionURL), predictionData)
        XCTAssertEqual(try Data(contentsOf: mapURL), mapData)
        XCTAssertEqual(try fileMap(frozenRoot, paths: Set(map.keys)), map)
        XCTAssertEqual(try fileMap(currentRoot, paths: dependencies), composerHashes)
        guard testRun?.failureCount == 0 else { return }
        let data = try canonical(Report(requestSHA256: sha(requestData), predictionSHA256: sha(predictionData),
            codeFileMapSHA256: sha(mapData), sourceJournalSHA256: prediction.sourceJournalSHA256,
            referenceProfileCanonicalSHA256: prediction.referenceProfileCanonicalSHA256,
            candidateProfileCanonicalSHA256: prediction.candidateProfileCanonicalSHA256,
            referenceExampleCount: prediction.referenceExampleCount, candidateExampleCount: prediction.candidateExampleCount,
            supportDelta: prediction.supportDelta, composerDependencyHashes: composerHashes, targets: compositions))
        guard data.count <= 4 * 1_024 * 1_024 else { return XCTFail("Composition report budget exceeded") }
        try data.write(to: output, options: .withoutOverwriting)
        XCTAssertEqual(try Data(contentsOf: output), data)
        print("APPEND_ONLY_GLYPH_SETUP_COMPOSITION targets=\(compositions.count) inferenceRerun=false accuracyMeasured=false reportSHA256=\(sha(data))")
    }

    func testMissingGlyphCannotBeSilentlyShortenedAndSemanticNoReadsEncodeAsNull() throws {
        let missingCases: [[String?]] = [["C", nil, "7"], ["C", "", "7"]]
        for labels in missingCases {
            let arm = syntheticArm(labels)
            for method in [Method.shared, .original, .anchored] { XCTAssertNil(compose(arm, method: method)) }
        }
        let nonRead = Arm(outcome: "invalid-ink", anchorStatus: "available", glyphs: [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: canonical(methods(reference: nonRead, candidate: nonRead))) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["sharedML", "originalReference", "originalCandidate", "anchoredReference", "anchoredCandidate"])
        XCTAssertTrue(object.values.allSatisfy { $0 is NSNull })
    }

    func testInvalidCompletePunctuationCannotBeSilentlyDroppedOrRescuedByLowerRank() {
        let arm = syntheticArm(["C", ">", "7"], alternative: "m")
        for method in [Method.shared, .original, .anchored] { XCTAssertNil(compose(arm, method: method)) }
    }

    func testValidMinorNinthUsesOnlyCompleteTopChoicesWithoutLabelRescue() {
        let arm = syntheticArm(["A", "m", "9"], alternative: "G")
        for method in [Method.shared, .original, .anchored] {
            XCTAssertEqual(compose(arm, method: method), "A-9")
        }
    }

    func testSupportDeltaRejectsCountsDuplicateIDsWrongKindSourceMetadataAndChangedBytes() throws {
        let lesson = try syntheticLesson()
        XCTAssertNoThrow(try validateSupportDelta(.init(referenceCount: 1, candidateCount: 2, addedLessons: [lesson]),
            referenceCount: 1, candidateCount: 2))
        for delta in [
            SupportDelta(referenceCount: 1, candidateCount: 1, addedLessons: []),
            SupportDelta(referenceCount: 1, candidateCount: 3, addedLessons: [lesson]),
            SupportDelta(referenceCount: 1, candidateCount: 3, addedLessons: [lesson, lesson]),
            SupportDelta(referenceCount: 1, candidateCount: PersonalInkProfile.maximumExamples + 1, addedLessons: [lesson])
        ] {
            XCTAssertThrowsError(try validateSupportDelta(delta,
                referenceCount: delta.referenceCount, candidateCount: delta.candidateCount))
        }
        XCTAssertThrowsError(try validateSupportDelta(.init(referenceCount: 1, candidateCount: 2, addedLessons: [lesson]),
            referenceCount: 0, candidateCount: 2))
        let wrongLessons = [
            SupportLesson(id: lesson.id, label: lesson.label, kind: .chord, source: .setup,
                exampleData: lesson.exampleData, exampleSHA256: lesson.exampleSHA256),
            SupportLesson(id: lesson.id, label: lesson.label, kind: .glyph, source: .explicitCorrection,
                exampleData: lesson.exampleData, exampleSHA256: lesson.exampleSHA256),
            SupportLesson(id: UUID(), label: lesson.label, kind: .glyph, source: .setup,
                exampleData: lesson.exampleData, exampleSHA256: lesson.exampleSHA256),
            SupportLesson(id: lesson.id, label: "B", kind: .glyph, source: .setup,
                exampleData: lesson.exampleData, exampleSHA256: lesson.exampleSHA256),
            SupportLesson(id: lesson.id, label: lesson.label, kind: .glyph, source: .setup,
                exampleData: lesson.exampleData + Data([0]), exampleSHA256: lesson.exampleSHA256)
        ]
        for wrong in wrongLessons {
            XCTAssertThrowsError(try validateSupportDelta(.init(referenceCount: 1, candidateCount: 2, addedLessons: [wrong]),
                referenceCount: 1, candidateCount: 2))
        }
    }

    private func validateSupportDelta(_ delta: SupportDelta, referenceCount: Int, candidateCount: Int) throws {
        guard (0...PersonalInkProfile.maximumExamples).contains(referenceCount),
              (1...PersonalInkProfile.maximumExamples).contains(candidateCount),
              candidateCount > referenceCount, delta.referenceCount == referenceCount,
              delta.candidateCount == candidateCount,
              delta.addedLessons.count == candidateCount - referenceCount,
              Set(delta.addedLessons.map(\.id)).count == delta.addedLessons.count else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        for lesson in delta.addedLessons {
            guard lesson.kind == .glyph, lesson.source == .setup,
                  PersonalInkProfile.glyphLabels.contains(lesson.label),
                  lesson.exampleData.count <= 2_000_000,
                  sha(lesson.exampleData) == lesson.exampleSHA256 else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            let example = try JSONDecoder().decode(PersonalInkExample.self, from: lesson.exampleData)
            guard example.id == lesson.id, example.label == lesson.label,
                  example.kind == lesson.kind, example.source == lesson.source,
                  example.strokes.contains(where: { !$0.points.isEmpty }) else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            let packet = try ChordInkCanonicalTrajectoryPacket(strokes: example.strokes)
            _ = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(packet.canonicalData())
        }
    }

    private func methods(reference: Arm, candidate: Arm) -> Methods {
        .init(sharedML: compose(reference, method: .shared),
            originalReference: compose(reference, method: .original), originalCandidate: compose(candidate, method: .original),
            anchoredReference: compose(reference, method: .anchored), anchoredCandidate: compose(candidate, method: .anchored))
    }
    private func compose(_ arm: Arm, method: Method) -> String? {
        guard arm.outcome == "read", method != .anchored || arm.anchorStatus == "available" else { return nil }
        // Map, never compactMap: missing/empty glyphs invalidate the complete
        // sequence. Preserve the frozen group order and only the first rank.
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
    private func syntheticArm(_ labels: [String?], alternative: String? = nil) -> Arm {
        .init(outcome: "read", anchorStatus: "available", glyphs: labels.enumerated().map { index, label in
            var ranks = label.map { [PersonalInkLearnedComparison.Rank(label: $0, score: 1)] } ?? []
            if let alternative, alternative != label { ranks.append(.init(label: alternative, score: 0)) }
            return .init(originalStrokeIndexes: [index], sharedRanks: ranks,
                originalResidualRanks: ranks, anchoredRanks: ranks)
        })
    }
    private func syntheticLesson() throws -> SupportLesson {
        let example = PersonalInkExample(kind: .glyph, label: "A", strokes: [InkStroke(points: [
            InkPoint(x: 0, y: 0), InkPoint(x: 1, y: 1)
        ])], source: .setup)
        let data = try canonical(example)
        return .init(id: example.id, label: example.label, kind: example.kind, source: example.source,
            exampleData: data, exampleSHA256: sha(data))
    }
    private func validate(_ frozen: Frozen, target: Target, profileSHA256: String, codeSHA256: String) throws {
        let legacy = frozen.legacyFreeze, arm = frozen.automatic
        let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(target.sourcePacketData)
        guard frozen.version == "blind-ink-anchored-comparison-freeze-v1",
              frozen.rankingScope == "same-reader-returned-top-three", frozen.supplied == nil,
              !frozen.glyphOwnershipVerified, !frozen.accuracyMeasured,
              !frozen.nativeLiveResult, !frozen.trainingEligible,
              sha(frozen.legacyCanonicalData) == frozen.legacyCanonicalSHA256,
              try JSONDecoder().decode(Legacy.self, from: frozen.legacyCanonicalData) == legacy,
              legacy.sourcePacketSHA256 == target.sourcePacketSHA256,
              legacy.sourceStrokeCount == packet.strokes.count,
              legacy.sourceStrokeCount == target.childToParentVisibleFragmentIndices.count,
              target.childToParentVisibleFragmentIndices.allSatisfy({ $0 >= 0 }),
              Set(target.childToParentVisibleFragmentIndices).count == target.childToParentVisibleFragmentIndices.count,
              target.childToParentVisibleFragmentIndices == target.childToParentVisibleFragmentIndices.sorted(),
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
    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
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
