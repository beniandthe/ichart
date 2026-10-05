#if DEBUG && canImport(CoreML)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Opt-in real-encoder connection gate. These previously inspected captures
/// provide numerical/preservation evidence, not blind recognition accuracy.
final class PersonalInkLocalAnchoredRuntimeTests: XCTestCase {
    private struct Envelope: Decodable {
        let version: String
        let artifactKind: String
        let trainingEligible: Bool
        let runID: UUID
        let sourceSnapshot: PersonalInkEvaluationSourceSnapshot
        let frozenProfile: PersonalInkProfile
        let profileLineage: PersonalInkProfileLineageSummary
    }
    private let inputs = [
        ("simple", "2adafba0667d01ae1f1cbeaf4d12c94111cebe1916d5d360be6c464917cd3892",
         "1b5b60361f08da4d9c5a587ca1943fc74d8492f43b6235674142bfc12eb4af7e"),
        ("rhythm", "cf411ba2a90d997c7f1bbe91b0dc544fabd358b83ce4da2c3b2325072a5cacba",
         "9646645ea35da98655ae83ba240c0a5e29b445a3af00fabf3d76eb6a7396cd0e")
    ]

    func testProvidedFrozenNaturalTargetsExportCompleteLocalComparison() throws {
        let env = ProcessInfo.processInfo.environment
        let names = ["ICHART_LOCAL_COMPARISON_SOURCE_ROOT", "ICHART_PERSONAL_ML_RUNTIME_DIRECTORY",
            "ICHART_LOCAL_COMPARISON_REPOSITORY_ROOT", "ICHART_LOCAL_COMPARISON_CODE_MAP",
            "ICHART_LOCAL_COMPARISON_CODE_SHA256", "ICHART_LOCAL_COMPARISON_RUNTIME_MAP",
            "ICHART_LOCAL_COMPARISON_RUNTIME_SHA256", "ICHART_LOCAL_COMPARISON_REPORT"]
        guard names.allSatisfy({ env[$0] != nil }) else {
            throw XCTSkip("Provide frozen captures, pinned runtime, actual code/file commitments and new report path")
        }
        guard names.allSatisfy({ !(env[$0] ?? "").isEmpty }) else { return XCTFail("Empty fixture argument") }
        func url(_ index: Int) -> URL {
            URL(fileURLWithPath: env[names[index]]!).standardizedFileURL.resolvingSymlinksInPath()
        }
        let sourceRoot = url(0), runtime = url(1), repository = url(2)
        let codeURL = url(3), runtimeURL = url(5), reportURL = url(7)
        guard !FileManager.default.fileExists(atPath: reportURL.path),
              ![sourceRoot, runtime, repository].contains(where: { reportURL.path.hasPrefix($0.path + "/") }),
              reportURL != codeURL, reportURL != runtimeURL else {
            return XCTFail("Report must be exclusive and outside source, runtime and repository")
        }
        let codeData = try bounded(codeURL, limit: 1_024 * 1_024)
        let runtimeData = try bounded(runtimeURL, limit: 1_024 * 1_024)
        let codeMap = try JSONDecoder().decode([String: String].self, from: codeData)
        let runtimeMap = try JSONDecoder().decode([String: String].self, from: runtimeData)
        let required: Set<String> = [
            "iChart/Recognition/PersonalInkLocalAnchoredComparison.swift",
            "iChart/Recognition/PersonalInkLocalAnchoredResidualHead.swift",
            "iChart/Recognition/PersonalInkBlindLocalAnchoredComparisonFreeze.swift",
            "iChart/Recognition/PersonalInkVisualEncoder.swift",
            "iChart/Recognition/PersonalInkAnchoredResidualHead.swift",
            "iChart/Recognition/PersonalInkResidualHead.swift",
            "iChart/Recognition/PersonalInkLearnedComparison.swift",
            "iChart/Recognition/ChordInkPersonalization.swift",
            "iChart/Recognition/PersonalInkLearningLineage.swift",
            "iChart/Recognition/PersonalInkEvaluationSource.swift",
            "iChart/Recognition/ChordInkTargetOwnershipSnapshot.swift",
            "iChart/Recognition/PersonalInkBlindPredictionFreeze.swift",
            "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
            "iChart/Recognition/InkTrajectoryTypes.swift",
            "iChart/Recognition/InkTypes.swift",
            "iChart/Recognition/StrokeClusterer.swift",
            "iChart/Recognition/StrokeClustererSupport.swift",
            "iChart/Recognition/Learned/ChordInkRasterizer.swift",
            "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChart/Services/ChordRecognitionCompendium.swift",
            "iChart/Services/ChartParsers.swift",
            "iChart/Models/MusicTheory.swift",
            "iChartTests/Recognition/PersonalInkLocalAnchoredRuntimeTests.swift"
        ]
        guard sha(codeData) == env[names[4]], sha(runtimeData) == env[names[6]],
              try canonical(codeMap) == codeData, try canonical(runtimeMap) == runtimeData,
              required.isSubset(of: Set(codeMap.keys)),
              try fileMap(repository, expectedPaths: Set(codeMap.keys)) == codeMap,
              try completeMap(runtime) == runtimeMap else {
            return XCTFail("Actual source and runtime commitments differ from supplied receipts")
        }
        let manifest = try bounded(runtime.appendingPathComponent("manifest.json"), limit: 32_768)
        guard sha(manifest) == PersonalInkVisualEncoder.anchoredManifestSHA256 else {
            return XCTFail("Concrete runtime requires pinned v2 anchor manifest")
        }
        var retained: [(URL, Data)] = [(codeURL, codeData), (runtimeURL, runtimeData)]
        var captures: [(String, Data, Envelope)] = []
        for (name, packetSHA, envelopeSHA) in inputs {
            let directory = sourceRoot.appendingPathComponent("source-\(name)")
            let packetURL = directory.appendingPathComponent("trajectory.json")
            let envelopeURL = directory.appendingPathComponent("source-envelope.json")
            let packet = try bounded(packetURL, limit: PersonalInkBlindPredictionFreeze.maximumPacketBytes)
            let data = try bounded(envelopeURL, limit: 24 * 1_024 * 1_024)
            guard sha(packet) == packetSHA, sha(data) == envelopeSHA else {
                return XCTFail("Exact retained capture commitment changed")
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == "blind-ink-capture-source-envelope-v1",
                  envelope.artifactKind == "engineering-only-local-development-capture-v1",
                  !envelope.trainingEligible,
                  envelope.sourceSnapshot.canonicalVisibleTrajectoryData == packet,
                  envelope.profileLineage == PersonalInkProfileLineageSummary(
                    profile: envelope.frozenProfile, querySessionID: envelope.runID) else {
                return XCTFail("Capture source/profile lineage disagreement")
            }
            try envelope.sourceSnapshot.validate()
            retained += [(packetURL, packet), (envelopeURL, data)]
            captures.append((name, packet, envelope))
        }
        defer {
            for (file, data) in retained { XCTAssertEqual(try? Data(contentsOf: file), data) }
            XCTAssertEqual(try? fileMap(repository, expectedPaths: Set(codeMap.keys)), codeMap)
            XCTAssertEqual(try? completeMap(runtime), runtimeMap)
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtime)
        let profile = try XCTUnwrap(captures.first?.2.frozenProfile)
        XCTAssertTrue(captures.allSatisfy { $0.2.frozenProfile == profile })
        guard testRun?.failureCount == 0 else { return }
        // Both heads are fitted completely before any query packet is read.
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(model.modelIdentity.runtimeKind, PersonalInkLocalAnchoredComparison.pinnedRuntimeKind)
        XCTAssertEqual(model.modelIdentity.pinnedAnchorArtifactSHA256, PersonalInkVisualEncoder.anchorSHA256)
        XCTAssertEqual(model.modelIdentity.pinnedManifestArtifactSHA256, PersonalInkVisualEncoder.anchoredManifestSHA256)
        guard testRun?.failureCount == 0 else { return }
        let profileData = try canonical(profile)
        var sources: [[String: Any]] = []
        var attempted = 0
        for (name, packetData, envelope) in captures {
            let packet = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(packetData)
            let source = packet.preparedStrokes()
            let snapshot = envelope.sourceSnapshot
            var targets: [[String: Any]] = []
            for target in snapshot.ownership.targetGroups {
                let indexes = target.visibleFragmentIndices
                let child = indexes.map { source[$0] }
                let childData = try ChordInkCanonicalTrajectoryPacket(strokes: child).canonicalData()
                let comparison = try PersonalInkBlindLocalAnchoredComparisonFreeze.freeze(
                    sourcePacketData: childData, suppliedOriginalIndexGroups: nil,
                    ownershipReceiptSHA256: nil, runtimeSHA256: env[names[6]]!,
                    codeSHA256: env[names[4]]!, model: model, currentProfile: { profile })
                targets.append(["targetOrdinal": target.targetOrdinal,
                    "childToParentOriginalStrokeIndexes": indexes,
                    "comparison": try JSONSerialization.jsonObject(with: comparison.canonicalData())])
                attempted += 1
            }
            // Completeness comes from the captured partition, not a requested
            // written-chord count or a recognition answer.
            let assigned = snapshot.ownership.targetGroups.flatMap(\.visibleFragmentIndices)
            let remainder = snapshot.ownership.barlineVisibleFragmentIndices
                + snapshot.ownership.unassignedVisibleFragmentIndices
            XCTAssertEqual(assigned.count, Set(assigned).count)
            XCTAssertTrue(Set(assigned).isDisjoint(with: Set(remainder)))
            XCTAssertEqual(Set(assigned + remainder), Set(source.indices))
            sources.append(["style": name, "runID": envelope.runID.uuidString,
                "sourcePacketSHA256": sha(packetData),
                "sourceEnvelopeSHA256": inputs.first(where: { $0.0 == name })!.2,
                "parentCanonicalTrajectoryData": packetData.base64EncodedString(),
                "capturedOwnership": try JSONSerialization.jsonObject(with: canonical(snapshot.ownership)),
                "profileLineage": try JSONSerialization.jsonObject(with: canonical(envelope.profileLineage)),
                "targets": targets])
        }
        XCTAssertEqual(try canonical(model.profile), profileData)
        for (file, data) in retained { XCTAssertEqual(try Data(contentsOf: file), data) }
        XCTAssertEqual(try completeMap(runtime), runtimeMap)
        XCTAssertEqual(try fileMap(repository, expectedPaths: Set(codeMap.keys)), codeMap)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = [
            "version": "offline-local-anchored-runtime-connection-v1",
            "nativeLiveResult": false, "accuracyMeasured": false,
            "glyphOwnershipVerified": false, "trainingEligible": false,
            "predictionChronologyVerified": false, "profileChanged": false,
            "encoderIdentity": encoder.identity, "profileSHA256": sha(profileData),
            "runtimeSHA256": env[names[6]]!, "codeSHA256": env[names[4]]!,
            "vocabulary": model.vocabulary,
            "support": try JSONSerialization.jsonObject(with: canonical(model.support)),
            "sources": sources]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .withoutEscapingSlashes])
        try data.write(to: reportURL, options: .withoutOverwriting)
        print("LOCAL_ANCHORED_RUNTIME_CONNECTION sources=\(sources.count) targetsAttempted=\(attempted) featureCount=128 fullRanks=true noTruthJoin=true noTeaching=true accuracyMeasured=false")
    }

    private func bounded(_ file: URL, limit: Int) throws -> Data {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              (properties.fileSize ?? Int.max) <= limit else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        return try Data(contentsOf: file)
    }
    private func fileMap(_ root: URL, expectedPaths: Set<String>) throws -> [String: String] {
        guard (1...1_024).contains(expectedPaths.count) else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        var result: [String: String] = [:]
        for path in expectedPaths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let file = root.appendingPathComponent(path).standardizedFileURL
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  file.path.hasPrefix(root.path + "/"), file.resolvingSymlinksInPath() == file else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            result[path] = sha(try bounded(file, limit: 4 * 1_024 * 1_024))
        }
        return result
    }
    private func completeMap(_ root: URL) throws -> [String: String] {
        let iterator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var paths = Set<String>()
        for case let path as String in iterator {
            let properties = try root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else { throw PersonalInkLearnedComparison.Failure.invalidEncoder }
            if properties.isRegularFile == true { paths.insert(path) }
        }
        return try fileMap(root, expectedPaths: paths)
    }
    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
