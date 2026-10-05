#if DEBUG && canImport(CoreML)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Opt-in recording of stopped, unlabelled query ink. This never teaches or
/// scores a query, and is not a live-recognizer or independent-writer gate.
final class PersonalInkFreshQueryFreezeRuntimeTests: XCTestCase {
    private struct Request: Decodable {
        let version: String
        let journalPath: String
        let journalSHA256: String
        let oldProfilePath: String
        let oldProfileSHA256: String
        let newProfilePath: String
        let newProfileSHA256: String
        let runIDs: [UUID]
        let runtimeDirectory: String
        let runtimeFileMapPath: String
        let runtimeFileMapSHA256: String
        let repositoryRoot: String
        let codeFileMapPath: String
        let codeFileMapSHA256: String
        let outputPath: String
    }

    func testProvidedStoppedUnlabeledRunsFreezeBothSupportProfiles() throws {
        guard let requestPath = ProcessInfo.processInfo.environment["ICHART_FRESH_QUERY_FREEZE_REQUEST"] else {
            throw XCTSkip("Provide a source-bound fresh-query freeze request before labeling")
        }
        let requestURL = file(requestPath)
        let requestData = try bounded(requestURL, maximum: 32_768)
        let request = try JSONDecoder().decode(Request.self, from: requestData)
        guard request.version == "fresh-unlabeled-query-freeze-request-v1",
              (1...2).contains(request.runIDs.count),
              Set(request.runIDs).count == request.runIDs.count else {
            return XCTFail("Select one or two distinct stopped runs, not expected answers or counts")
        }
        let journalURL = file(request.journalPath)
        let oldProfileURL = file(request.oldProfilePath), newProfileURL = file(request.newProfilePath)
        let runtime = file(request.runtimeDirectory), repository = file(request.repositoryRoot)
        let codeMapURL = file(request.codeFileMapPath), runtimeMapURL = file(request.runtimeFileMapPath)
        let output = file(request.outputPath)
        let inputFiles = [requestURL, journalURL, oldProfileURL, newProfileURL, codeMapURL, runtimeMapURL]
        guard !inputFiles.contains(output),
              ![runtime, repository].contains(where: { output.path.hasPrefix($0.path + "/") }),
              !inputFiles.map({ $0.deletingLastPathComponent() }).contains(where: {
                  output.path.hasPrefix($0.path + "/")
              }),
              !FileManager.default.fileExists(atPath: output.path) else {
            return XCTFail("Freeze output must be new and separate from input, code and runtime files")
        }
        let journalData = try bounded(journalURL, maximum: PersonalInkEvaluationStore.maximumJournalByteCount)
        let oldData = try bounded(oldProfileURL, maximum: 2_000_000)
        let newData = try bounded(newProfileURL, maximum: 2_000_000)
        let codeMapData = try bounded(codeMapURL, maximum: 1_024 * 1_024)
        let runtimeMapData = try bounded(runtimeMapURL, maximum: 1_024 * 1_024)
        guard sha(journalData) == request.journalSHA256,
              sha(oldData) == request.oldProfileSHA256, sha(newData) == request.newProfileSHA256,
              sha(codeMapData) == request.codeFileMapSHA256,
              sha(runtimeMapData) == request.runtimeFileMapSHA256 else {
            return XCTFail("Source bytes differ from the pre-inference commitments")
        }
        let codeMap = try JSONDecoder().decode([String: String].self, from: codeMapData)
        let runtimeMap = try JSONDecoder().decode([String: String].self, from: runtimeMapData)
        let required: Set<String> = [
            "iChart/Recognition/PersonalInkBlindAnchoredComparisonFreeze.swift",
            "iChart/Recognition/PersonalInkBlindPredictionFreeze.swift",
            "iChart/Recognition/PersonalInkLearnedComparison.swift",
            "iChart/Recognition/PersonalInkVisualEncoder.swift",
            "iChart/Recognition/PersonalInkResidualHead.swift",
            "iChart/Recognition/PersonalInkAdaptiveHead.swift",
            "iChart/Recognition/PersonalInkAnchoredResidualHead.swift",
            "iChart/Recognition/ChordInkPersonalization.swift",
            "iChart/Recognition/PersonalInkEvaluation.swift",
            "iChart/Recognition/PersonalInkEvaluationSource.swift",
            "iChart/Recognition/ChordInkTargetOwnershipSnapshot.swift",
            "iChart/Recognition/PersonalInkLearningLineage.swift",
            "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
            "iChart/Recognition/InkTypes.swift",
            "iChart/Recognition/InkTrajectoryTypes.swift",
            "iChart/Recognition/StrokeClusterer.swift",
            "iChart/Recognition/StrokeClustererSupport.swift",
            "iChart/Recognition/Learned/ChordInkRasterizer.swift",
            "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
            "iChart/Services/ChordRecognitionCompendium.swift",
            "iChart/Services/ChartParsers.swift",
            "iChart/Models/MusicTheory.swift",
            "iChart/Models/ChordEvent.swift",
            "iChartTests/Recognition/PersonalInkFreshQueryFreezeRuntimeTests.swift",
            "project.yml",
            "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        ]
        guard required.isSubset(of: Set(codeMap.keys)),
              try canonical(codeMap) == codeMapData, try canonical(runtimeMap) == runtimeMapData,
              try fileMap(repository, paths: Set(codeMap.keys)) == codeMap,
              try completeMap(runtime) == runtimeMap else {
            return XCTFail("Actual code or complete runtime file map differs from its commitment")
        }
        let retained = zip(inputFiles, [requestData, journalData, oldData, newData, codeMapData, runtimeMapData])
            .map { ($0.0, $0.1) }
        defer {
            for (url, data) in retained { XCTAssertEqual(try? Data(contentsOf: url), data) }
            XCTAssertEqual(try? fileMap(repository, paths: Set(codeMap.keys)), codeMap)
            XCTAssertEqual(try? completeMap(runtime), runtimeMap)
        }
        let older = try JSONDecoder().decode(PersonalInkProfile.self, from: oldData)
        let newer = try JSONDecoder().decode(PersonalInkProfile.self, from: newData)
        var retainedOlder = newer
        retainedOlder.examples = older.examples
        retainedOlder.revision = older.revision
        let additions = Array(newer.examples.dropFirst(older.examples.count))
        guard older.isEnabled, newer.isEnabled, retainedOlder == older,
              newer.examples.count > older.examples.count,
              Array(newer.examples.prefix(older.examples.count)) == older.examples,
              additions.allSatisfy({ $0.kind == .glyph && $0.source == .explicitCorrection }) else {
            return XCTFail("Profiles must differ only by appended explicit glyph lessons and revision")
        }
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalData)
        guard journal.version == 1, journal.runs.count <= PersonalInkEvaluationStore.maximumRuns,
              Set(journal.runs.map(\.id)).count == journal.runs.count else {
            return XCTFail("Invalid or ambiguous source journal")
        }
        let runs = try request.runIDs.map { id -> PersonalInkEvaluationRun in
            let run = try XCTUnwrap(journal.runs.first { $0.id == id })
            guard run.status == .labeling, run.phase == .afterCorrections, run.profile == newer,
                  run.finishedAt == nil, run.expectedChordCount == nil,
                  run.sourceCaptureState == .complete, run.sourceCaptureIsWithinStorageBounds,
                  run.teachingReceipt == nil,
                  Set(run.records.map(\.id)).count == run.records.count,
                  run.records.allSatisfy({ $0.intended == nil && !$0.groupingIssue && !$0.taught
                    && $0.isWithinStorageBounds }),
                  ["simpleChordSheet", "rhythmSectionSheet"].contains(run.style) else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            let snapshot = try XCTUnwrap(run.sourceSnapshot)
            try snapshot.validate()
            guard run.sourceRequestID == snapshot.requestID, run.sourceInkRevision == snapshot.inkRevision,
                  run.recordsMatchSourceCapture(run.records, snapshot: snapshot),
                  run.profileLineage == PersonalInkProfileLineageSummary(profile: newer, querySessionID: run.id) else {
                throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
            }
            return run
        }
        guard Set(runs.map(\.style)).count == runs.count else {
            return XCTFail("A two-run request must contain both chart styles")
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtime)
        guard encoder.anchorBank != nil else { return XCTFail("Requires the unchanged pinned v2 anchored package") }
        // Both support fits are frozen before any target is queried. Whole-chord
        // rankings are never queried or used to select a symbol, group or chord.
        let models = try [older, newer].map {
            try PersonalInkLearnedComparison(profile: $0, encoder: encoder, grouping: .losslessSourceV2)
        }
        var sources: [[String: Any]] = []
        var targetCount = 0
        for run in runs {
            let snapshot = try XCTUnwrap(run.sourceSnapshot)
            var targets: [[String: Any]] = []
            for group in snapshot.ownership.targetGroups {
                let strokes = group.visibleFragmentIndices.map { snapshot.visibleStrokes[$0] }
                let packet = try ChordInkCanonicalTrajectoryPacket(strokes: strokes).canonicalData()
                let freezes = try models.map { model in
                    try PersonalInkBlindAnchoredComparisonFreeze.freeze(sourcePacketData: packet,
                        suppliedOriginalIndexGroups: nil, ownershipReceiptSHA256: nil,
                        runtimeSHA256: request.runtimeFileMapSHA256, codeSHA256: request.codeFileMapSHA256,
                        model: model, currentProfile: { model.profile })
                }
                let oldArm = freezes[0].automatic, newArm = freezes[1].automatic
                guard oldArm.outcome == newArm.outcome,
                      oldArm.glyphs.map(\.originalStrokeIndexes) == newArm.glyphs.map(\.originalStrokeIndexes),
                      oldArm.glyphs.map(\.sharedRanks) == newArm.glyphs.map(\.sharedRanks) else {
                    return XCTFail("Support changes may not change source groups or shared query ranks")
                }
                let record = try XCTUnwrap(run.records.first { $0.targetOrdinal == group.targetOrdinal })
                targets.append([
                    "targetOrdinal": group.targetOrdinal, "recordID": record.id.uuidString,
                    "childToParentVisibleFragmentIndices": group.visibleFragmentIndices,
                    "sourcePacketSHA256": sha(packet),
                    "sourcePacketData": packet.base64EncodedString(),
                    "olderProfileFreeze": try JSONSerialization.jsonObject(with: freezes[0].canonicalData()),
                    "newerProfileFreeze": try JSONSerialization.jsonObject(with: freezes[1].canonicalData())
                ])
                targetCount += 1
            }
            // Preserve full valid parents independently of the smaller per-target
            // model budget. Empty targets and unassigned/barline ink remain here.
            sources.append([
                "runID": run.id.uuidString, "style": run.style, "pipeline": run.pipeline,
                "sourceSnapshot": try JSONSerialization.jsonObject(with: canonical(snapshot)),
                "sourcePacketSHA256": sha(snapshot.canonicalVisibleTrajectoryData),
                "frozenProfileSHA256": sha(try canonical(run.profile)),
                "profileLineage": try JSONSerialization.jsonObject(with: canonical(run.profileLineage)),
                "targets": targets
            ])
        }
        // Recheck all commitments before publication; never overwrite a prior
        // freeze or substitute later profile lessons/labels into this report.
        for (url, data) in retained { XCTAssertEqual(try Data(contentsOf: url), data) }
        XCTAssertEqual(try fileMap(repository, paths: Set(codeMap.keys)), codeMap)
        XCTAssertEqual(try completeMap(runtime), runtimeMap)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = [
            "version": "fresh-unlabeled-paired-profile-freeze-v1",
            "createdAtUnixSeconds": Date().timeIntervalSince1970,
            "sourceJournalSHA256": sha(journalData), "requestSHA256": sha(requestData),
            "oldProfileFileSHA256": sha(oldData), "newProfileFileSHA256": sha(newData),
            "oldProfileCanonicalSHA256": sha(try canonical(older)),
            "newProfileCanonicalSHA256": sha(try canonical(newer)),
            "oldExampleCount": older.examples.count, "newExampleCount": newer.examples.count,
            "runtimeFileMapSHA256": request.runtimeFileMapSHA256,
            "codeFileMapSHA256": request.codeFileMapSHA256,
            "encoderIdentity": encoder.identity, "sources": sources,
            "sourceSnapshotUnlabeled": true, "exportedFromUnannotatedStoppedRun": true,
            "olderProfileIsCounterfactualSupport": true, "accuracyMeasured": false,
            "independentAnnotation": false, "freshWritingVerified": false,
            "nativeLiveResult": false, "trainingEligible": false,
            "predictionChronologyVerified": false, "profileChanged": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 64 * 1_024 * 1_024 else { return XCTFail("Freeze report budget exceeded; no evidence was truncated") }
        try data.write(to: output, options: .withoutOverwriting)
        XCTAssertEqual(try Data(contentsOf: output), data)
        print("FRESH_UNLABELED_PROFILE_FREEZE runs=\(runs.count) targets=\(targetCount) oldExamples=\(older.examples.count) newExamples=\(newer.examples.count) sharedUnchanged=true noTeaching=true accuracyMeasured=false reportSHA256=\(sha(data))")
    }

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    }
    private func bounded(_ url: URL, maximum: Int) throws -> Data {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              (properties.fileSize ?? Int.max) <= maximum else {
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
    private func completeMap(_ root: URL) throws -> [String: String] {
        let iterator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var paths = Set<String>()
        for case let path as String in iterator {
            let properties = try root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else { throw PersonalInkLearnedComparison.Failure.invalidEncoder }
            if properties.isRegularFile == true { paths.insert(path) }
        }
        return try fileMap(root, paths: paths)
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
