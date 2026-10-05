#if DEBUG && canImport(CoreML)
import CryptoKit
import XCTest
@testable import iChart

final class PersonalInkVisualRuntimeTests: XCTestCase {
    func testProvidedCompletedEvaluationRunsUseFrozenProfilesAndExactSavedInk() throws {
        let env = ProcessInfo.processInfo.environment
        guard let journalPath = env["ICHART_PERSONAL_EVALUATION_JOURNAL"],
              let selectedIDs = env["ICHART_PERSONAL_EVALUATION_RUN_IDS"],
              let runtimePath = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let reportPath = env["ICHART_PERSONAL_EVALUATION_REPORT_DIRECTORY"] else {
            throw XCTSkip("Provide an authorized local evaluation journal, selected run IDs, runtime package and report directory")
        }
        guard [journalPath, selectedIDs, runtimePath, reportPath].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { XCTFail("Evaluation environment values must be nonempty"); return }
        let grouping: PersonalInkLearnedComparison.Grouping
        if let version = env["ICHART_PERSONAL_EVALUATION_GROUPING_VERSION"] {
            grouping = try XCTUnwrap(PersonalInkLearnedComparison.Grouping(rawValue: version),
                                     "Select an explicit supported grouping version")
        } else { grouping = .legacyGeometryV1 }
        let requestedIDs = try selectedIDs.split(separator: ",", omittingEmptySubsequences: false).map {
            try XCTUnwrap(UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)),
                          "Every selected run ID must be a UUID")
        }
        guard !requestedIDs.isEmpty, Set(requestedIDs).count == requestedIDs.count else {
            XCTFail("Select distinct, nonempty run IDs")
            return
        }
        let journalURL = URL(fileURLWithPath: journalPath).standardizedFileURL.resolvingSymlinksInPath()
        let runtimeDirectory = URL(fileURLWithPath: runtimePath).standardizedFileURL.resolvingSymlinksInPath()
        let reportDirectory = URL(fileURLWithPath: reportPath).standardizedFileURL.resolvingSymlinksInPath()
        guard reportDirectory != journalURL, reportDirectory != runtimeDirectory,
              !reportDirectory.path.hasPrefix(runtimeDirectory.path + "/") else {
            XCTFail("Save comparison reports separately from the source journal and runtime package")
            return
        }
        let manifestURL = runtimeDirectory.appendingPathComponent("manifest.json")
        let journalData = try Data(contentsOf: journalURL)
        let manifestData = try Data(contentsOf: manifestURL)
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalData)
        let frozenRuns = journal.runs
        defer {
            let preservedData = try? Data(contentsOf: journalURL)
            XCTAssertTrue(preservedData == journalData, "The source journal bytes must remain unchanged")
            XCTAssertTrue((try? Data(contentsOf: manifestURL)) == manifestData,
                          "The runtime model manifest bytes must remain unchanged")
            let preservedJournal = preservedData.flatMap {
                try? JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: $0)
            }
            let preservedRuns = preservedJournal?.runs ?? []
            XCTAssertTrue(preservedJournal != nil && preservedRuns.count == frozenRuns.count &&
                          zip(preservedRuns, frozenRuns).allSatisfy {
                              $0.0.id == $0.1.id && $0.0.profile == $0.1.profile
                          }, "Every saved run must retain its frozen profile")
        }
        guard journal.version == 1 else { XCTFail("Unsupported evaluation journal version"); return }
        var selectedRuns: [PersonalInkEvaluationRun] = []
        for id in requestedIDs {
            let matches = journal.runs.filter { $0.id == id }
            let run = try XCTUnwrap(matches.count == 1 ? matches.first : nil,
                                    "Each selected ID must identify exactly one saved run")
            guard run.status == .complete, !run.records.isEmpty else {
                XCTFail("Every selected run must be completed and contain captured records")
                return
            }
            guard run.records.allSatisfy({ $0.recognitionStrokes?.isEmpty == false }) else {
                XCTFail("Every selected record must retain its exact saved recognition input")
                return
            }
            selectedRuns.append(run)
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtimeDirectory)
        var recordCount = 0, predictionCount = 0, exclusionCount = 0, reportCount = 0
        for run in selectedRuns {
            let frozenProfile = run.profile
            // Intended answers are read only by the report's scoring path;
            // comparison fitting uses the run's frozen profile lessons.
            let report = try PersonalInkLearnedRunReport.compare(run, encoder: encoder, grouping: grouping)
            XCTAssertTrue(run.profile == frozenProfile, "Comparison must preserve the frozen profile")
            XCTAssertTrue(report.runID == run.id && report.profileRevision == frozenProfile.revision,
                          "Comparison must identify the selected run and its frozen profile")
            XCTAssertTrue(report.rows.map(\.id) == run.records.map(\.id),
                          "Comparison must retain every selected record, including failed reads")
            XCTAssertEqual(report.groupingVersion, grouping.rawValue)
            try report.save(in: reportDirectory)
            recordCount += report.rows.count
            predictionCount += report.rows.filter { $0.prediction != nil }.count
            exclusionCount += report.rows.filter { $0.exclusion != nil }.count
            reportCount += 1
        }
        XCTAssertEqual(reportCount, requestedIDs.count)
        print("PERSONAL_ML_COMPLETED_RUN_COMPARISON grouping=\(grouping.rawValue) runs=\(selectedRuns.count) records=\(recordCount) predictions=\(predictionCount) exclusions=\(exclusionCount) reports=\(reportCount)")
    }

    func testProvidedExactDeviceTraceUsesRuntimeBridgeWithoutTeaching() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let trace = env["ICHART_PERSONAL_EVIDENCE_TRACE"], let profilePath = env["ICHART_PERSONAL_EVIDENCE_PROFILE"],
              let pipeline = env["ICHART_PERSONAL_EVIDENCE_PIPELINE"] else {
            throw XCTSkip("Provide authorized exact device trace and frozen profile for development replay")
        }
        let profileURL = URL(fileURLWithPath: profilePath), traceURL = URL(fileURLWithPath: trace)
        let profileData = try Data(contentsOf: profileURL), traceData = try Data(contentsOf: traceURL)
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: profileData)
        let encoder = try PersonalInkVisualEncoder(directory: URL(fileURLWithPath: directory))
        let comparison = try PersonalInkLearnedComparison(profile: profile, encoder: encoder)
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL).loadEvents()
            .filter { $0.recognitionPipelineVersion == pipeline && ["finish_single", "finish_batch"].contains($0.stage) }
        var rows: [[String: Any]] = [], seen = Set<[InkStroke]>()
        for (pass, event) in events.enumerated() {
            for payload in event.payloads {
                let ink = try XCTUnwrap(payload.inkStrokes)
                let prediction = try comparison.predict(ink, currentProfile: profile)
                let clusters = StrokeClusterer().indexedClusters(ink.map { InkStroke(points: $0.points) })
                XCTAssertEqual(clusters.count, prediction.glyphs.count)
                let glyphDetails: [[String: Any]] = try prediction.glyphs.map { glyph in
                    let strokes = glyph.originalStrokeIndexes.map { ink[$0] }
                    let cluster = try XCTUnwrap(clusters.first { $0.originalIndexes == glyph.originalStrokeIndexes })
                    // This diagnostic must inspect the actual model input, not
                    // a reconstruction that silently lost a cluster transform.
                    XCTAssertEqual(cluster.cluster.strokes.map(\.points), strokes.map(\.points))
                    let features = try encoder.encode(strokes)
                    let scores = try PersonalInkResidualHead.normalizedScores(logits: features.genericLogits)
                    let ranks = zip(encoder.vocabulary, scores).sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                    XCTAssertEqual(Array(ranks.prefix(3)).map(\.0), glyph.generic.map(\.label))
                    for (actual, expected) in zip(ranks.prefix(3), glyph.generic) {
                        XCTAssertEqual(actual.1, expected.score, accuracy: 1e-12)
                    }
                    return ["originalStrokeIndexes": glyph.originalStrokeIndexes,
                            "genericRanks": ranks.prefix(10).map { ["label": $0.0, "score": $0.1] },
                            "personalRanks": glyph.personal.map { ["label": $0.label, "score": $0.score] }]
                }
                rows.append(["pass": pass, "style": event.layoutStyle ?? "unknown", "target": payload.targetIndex,
                             "unique": seen.insert(ink).inserted, "knownInk": prediction.knownInk,
                             "native": payload.matchText ?? "no-read", "generic": prediction.genericChord ?? "no-complete-read",
                             "personal": prediction.personalChord ?? "no-complete-read",
                             "personalTokens": prediction.glyphs.compactMap { $0.personal.first?.label }.joined(),
                             "anchoredAvailable": prediction.anchored != nil,
                             "anchored": prediction.anchored?.chord ?? "no-complete-read",
                             "anchoredTokens": prediction.anchored?.glyphRanks.compactMap { $0.first?.label }.joined() ?? "unavailable",
                             "glyphDetails": glyphDetails,
                             "closedSetWholeCandidates": prediction.wholeChordRanks.map(\.label)])
            }
        }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileData)
        XCTAssertEqual(try Data(contentsOf: traceURL), traceData)
        let report: [String: Any] = ["scope": "seen-input development replay; ranks only; no teaching or fresh accuracy",
            "encoder": encoder.identity, "profileRevision": profile.revision.uuidString,
            "traceSHA256": SHA256.hash(data: traceData).map { String(format: "%02x", $0) }.joined(),
            "profileSHA256": SHA256.hash(data: profileData).map { String(format: "%02x", $0) }.joined(),
            "missingPersonalSymbols": comparison.missingPersonalSymbols, "observations": rows.count, "uniqueInputs": seen.count,
            "rows": rows]
        if let output = env["ICHART_PERSONAL_ML_TRACE_REPORT"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        }
        print("PERSONAL_ML_BRIDGE_REPLAY observations=\(rows.count) unique=\(seen.count) noTeaching=true")
    }

    #if canImport(UIKit)
    func testOptedInDebugAppLoadsActualBundledModel() throws {
        guard let directory = PersonalInkVisualEncoder.bundledDirectory() else {
            throw XCTSkip("This optional research-artifact gate requires the opted-in Debug build")
        }
        let encoder = try PersonalInkVisualEncoder(directory: directory)
        let features = try encoder.encode([.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])])
        XCTAssertEqual(features.embedding.count, 128)
        XCTAssertEqual(features.genericLogits.count, 97)
        XCTAssertEqual(features.embedding.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 1e-3)
        XCTAssertTrue(features.genericLogits.allSatisfy(\.isFinite))
        if encoder.identity.contains("personal-visual-comparison-v2") {
            XCTAssertEqual(encoder.anchorBank?.vocabulary, encoder.vocabulary)
            XCTAssertEqual(encoder.anchorBank?.features.count, 97)
        }
    }
    #endif
    func testPinnedAppRuntimeMatchesRecordedCoreMLFeaturesAndNeverChangesItsPackage() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let parityPath = env["ICHART_PERSONAL_RESIDUAL_PARITY"] else {
            throw XCTSkip("Provide the verified Debug comparison bundle and parity packet")
        }
        let directory = URL(fileURLWithPath: path)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let before = try Data(contentsOf: manifestURL)
        struct Sample: Decodable { let strokes: [[InkPoint]]; let embedding: [Double]; let genericLogits: [Double] }
        struct Packet: Decodable { let vocabulary: [String]; let samples: [Sample] }
        let packet = try JSONDecoder().decode(Packet.self, from: Data(contentsOf: URL(fileURLWithPath: parityPath)))
        let encoder = try PersonalInkVisualEncoder(directory: directory)
        XCTAssertEqual(encoder.vocabulary, packet.vocabulary)
        // A model integration check, not a recognition benchmark. Existing
        // exhaustive parity still covers all 1,552 trajectories.
        for sample in [try XCTUnwrap(packet.samples.first), try XCTUnwrap(packet.samples.last)] {
            let result = try encoder.encode(sample.strokes.map { .init(points: $0) })
            XCTAssertEqual(result.embedding.count, 128)
            XCTAssertEqual(result.genericLogits.count, 97)
            for (actual, expected) in zip(result.embedding, sample.embedding) { XCTAssertEqual(actual, expected, accuracy: 1e-4) }
            for (actual, expected) in zip(result.genericLogits, sample.genericLogits) { XCTAssertEqual(actual, expected, accuracy: 1e-4) }
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), before)
    }

    func testMissingOrAlteredManifestCannotLoadADifferentModel() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try PersonalInkVisualEncoder(directory: folder))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try PersonalInkVisualEncoder(directory: folder))
    }

    func testProvidedAnchorArtifactFailsClosedWhenMissingOrChanged() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"] else {
            throw XCTSkip("Provide the pinned anchored comparison package")
        }
        let source = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNotNil(try PersonalInkVisualEncoder(directory: folder).anchorBank)
        let url = folder.appendingPathComponent("public-anchors.json")
        let data = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try PersonalInkVisualEncoder(directory: folder))
        try (data + Data(" ".utf8)).write(to: url)
        XCTAssertThrowsError(try PersonalInkVisualEncoder(directory: folder))
    }

    func testProvidedLegacyArtifactStillLoadsWithoutChangingItsIdentity() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PERSONAL_ML_LEGACY_DIRECTORY"] else {
            throw XCTSkip("Provide the original pinned comparison package")
        }
        let encoder = try PersonalInkVisualEncoder(directory: URL(fileURLWithPath: path))
        XCTAssertNil(encoder.anchorBank)
        XCTAssertEqual(encoder.identity, "personal-visual-comparison-v1:c51029092ea80e6d2621db4606f7051139177169dc9d036b89c9e74b2f5988f5:personal-residual-ridge-v1")
    }
}
#endif
