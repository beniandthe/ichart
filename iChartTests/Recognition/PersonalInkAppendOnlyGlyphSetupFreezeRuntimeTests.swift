#if DEBUG && canImport(CoreML)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Opt-in recording of stopped, unlabelled query ink against an exact
/// append-only setup-glyph support delta. This never teaches or scores a query,
/// and is not a live-recognizer or independent-writer gate.
final class PersonalInkAppendOnlyGlyphSetupFreezeRuntimeTests: XCTestCase {
    private enum ValidationFailure: Error {
        case invalidRequest
        case invalidSupportDelta
    }

    private struct AddedLesson: Codable, Equatable {
        let id: UUID
        let label: String
        let kind: PersonalInkExampleKind
        let source: PersonalInkExampleSource
        let exampleData: Data
        let exampleSHA256: String
    }

    private struct SupportDelta: Codable, Equatable {
        let referenceCount: Int
        let candidateCount: Int
        let addedLessons: [AddedLesson]
    }

    private struct Request: Decodable {
        let version: String
        let journalPath: String
        let journalSHA256: String
        let referenceProfilePath: String
        let referenceProfileSHA256: String
        let candidateProfilePath: String
        let candidateProfileSHA256: String
        let supportDelta: SupportDelta
        let runIDs: [UUID]
        let runtimeDirectory: String
        let runtimeFileMapPath: String
        let runtimeFileMapSHA256: String
        let repositoryRoot: String
        let codeFileMapPath: String
        let codeFileMapSHA256: String
        let outputPath: String
    }

    func testProvidedStoppedUnlabeledRunsFreezeAppendOnlySetupProfiles() throws {
        guard let requestPath = ProcessInfo.processInfo.environment[
            "ICHART_APPEND_ONLY_GLYPH_SETUP_FREEZE_REQUEST"
        ] else {
            throw XCTSkip("Provide a source-bound append-only setup freeze request before labeling")
        }
        let requestURL = file(requestPath)
        let requestData = try bounded(requestURL, maximum: 2_000_000)
        try Self.validateRequestShape(requestData)
        let request = try JSONDecoder().decode(Request.self, from: requestData)
        guard request.version == "append-only-glyph-setup-freeze-request-v2",
              (1...2).contains(request.runIDs.count),
              Set(request.runIDs).count == request.runIDs.count else {
            return XCTFail("Select one or two distinct stopped runs without query prompts, truth or counts")
        }
        let journalURL = file(request.journalPath)
        let referenceProfileURL = file(request.referenceProfilePath)
        let candidateProfileURL = file(request.candidateProfilePath)
        let runtime = file(request.runtimeDirectory), repository = file(request.repositoryRoot)
        let codeMapURL = file(request.codeFileMapPath), runtimeMapURL = file(request.runtimeFileMapPath)
        let output = file(request.outputPath)
        let inputFiles = [requestURL, journalURL, referenceProfileURL, candidateProfileURL,
                          codeMapURL, runtimeMapURL]
        guard !inputFiles.contains(output),
              ![runtime, repository].contains(where: { output.path.hasPrefix($0.path + "/") }),
              !inputFiles.map({ $0.deletingLastPathComponent() }).contains(where: {
                  output.path.hasPrefix($0.path + "/")
              }),
              !FileManager.default.fileExists(atPath: output.path) else {
            return XCTFail("Freeze output must be new and separate from input, code and runtime files")
        }
        let journalData = try bounded(journalURL, maximum: PersonalInkEvaluationStore.maximumJournalByteCount)
        let referenceData = try bounded(referenceProfileURL, maximum: 2_000_000)
        let candidateData = try bounded(candidateProfileURL, maximum: 2_000_000)
        let codeMapData = try bounded(codeMapURL, maximum: 1_024 * 1_024)
        let runtimeMapData = try bounded(runtimeMapURL, maximum: 1_024 * 1_024)
        guard sha(journalData) == request.journalSHA256,
              sha(referenceData) == request.referenceProfileSHA256,
              sha(candidateData) == request.candidateProfileSHA256,
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
            "iChartTests/Recognition/PersonalInkAppendOnlyGlyphSetupFreezeRuntimeTests.swift",
            "project.yml",
            "iChart.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        ]
        guard required.isSubset(of: Set(codeMap.keys)),
              try canonical(codeMap) == codeMapData, try canonical(runtimeMap) == runtimeMapData,
              try fileMap(repository, paths: Set(codeMap.keys)) == codeMap,
              try completeMap(runtime) == runtimeMap else {
            return XCTFail("Actual code or complete runtime file map differs from its commitment")
        }
        let retained = zip(inputFiles, [requestData, journalData, referenceData, candidateData,
                                        codeMapData, runtimeMapData]).map { ($0.0, $0.1) }
        defer {
            for (url, data) in retained { XCTAssertEqual(try? Data(contentsOf: url), data) }
            XCTAssertEqual(try? fileMap(repository, paths: Set(codeMap.keys)), codeMap)
            XCTAssertEqual(try? completeMap(runtime), runtimeMap)
        }
        let reference = try JSONDecoder().decode(PersonalInkProfile.self, from: referenceData)
        let candidate = try JSONDecoder().decode(PersonalInkProfile.self, from: candidateData)
        do {
            try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                          supportDelta: request.supportDelta)
        } catch {
            return XCTFail("Profiles do not match the committed append-only setup-glyph delta")
        }
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalData)
        guard journal.version == 1, journal.runs.count <= PersonalInkEvaluationStore.maximumRuns,
              Set(journal.runs.map(\.id)).count == journal.runs.count else {
            return XCTFail("Invalid or ambiguous source journal")
        }
        let runs = try request.runIDs.map { id -> PersonalInkEvaluationRun in
            let run = try XCTUnwrap(journal.runs.first { $0.id == id })
            guard run.status == .labeling, run.phase == .afterCorrections, run.profile == candidate,
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
                  run.profileLineage == PersonalInkProfileLineageSummary(profile: candidate,
                                                                          querySessionID: run.id) else {
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
        let models = try [reference, candidate].map {
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
                let referenceArm = freezes[0].automatic, candidateArm = freezes[1].automatic
                guard referenceArm.outcome == candidateArm.outcome,
                      referenceArm.glyphs.map(\.originalStrokeIndexes)
                        == candidateArm.glyphs.map(\.originalStrokeIndexes),
                      referenceArm.glyphs.map(\.sharedRanks) == candidateArm.glyphs.map(\.sharedRanks) else {
                    return XCTFail("Support changes may not change source groups or shared query ranks")
                }
                let record = try XCTUnwrap(run.records.first { $0.targetOrdinal == group.targetOrdinal })
                targets.append([
                    "targetOrdinal": group.targetOrdinal, "recordID": record.id.uuidString,
                    "childToParentVisibleFragmentIndices": group.visibleFragmentIndices,
                    "sourcePacketSHA256": sha(packet),
                    "sourcePacketData": packet.base64EncodedString(),
                    "referenceProfileFreeze": try JSONSerialization.jsonObject(with: freezes[0].canonicalData()),
                    "candidateProfileFreeze": try JSONSerialization.jsonObject(with: freezes[1].canonicalData())
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
            "version": "fresh-unlabeled-append-only-glyph-profile-freeze-v2",
            "createdAtUnixSeconds": Date().timeIntervalSince1970,
            "sourceJournalSHA256": sha(journalData), "requestSHA256": sha(requestData),
            "referenceProfileFileSHA256": sha(referenceData),
            "candidateProfileFileSHA256": sha(candidateData),
            "referenceProfileCanonicalSHA256": sha(try canonical(reference)),
            "candidateProfileCanonicalSHA256": sha(try canonical(candidate)),
            "referenceExampleCount": reference.examples.count,
            "candidateExampleCount": candidate.examples.count,
            "supportDelta": try JSONSerialization.jsonObject(with: canonical(request.supportDelta)),
            "runtimeFileMapSHA256": request.runtimeFileMapSHA256,
            "codeFileMapSHA256": request.codeFileMapSHA256,
            "encoderIdentity": encoder.identity, "sources": sources,
            "sourceSnapshotUnlabeled": true, "exportedFromUnannotatedStoppedRun": true,
            "olderProfileIsCounterfactualSupport": true, "accuracyMeasured": false,
            "independentAnnotation": false, "freshWritingVerified": false,
            "nativeLiveResult": false, "trainingEligible": false,
            "predictionChronologyVerified": false, "profileChanged": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report,
                                               options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 64 * 1_024 * 1_024 else {
            return XCTFail("Freeze report budget exceeded; no evidence was truncated")
        }
        try data.write(to: output, options: .withoutOverwriting)
        XCTAssertEqual(try Data(contentsOf: output), data)
        print("APPEND_ONLY_GLYPH_SETUP_FREEZE runs=\(runs.count) targets=\(targetCount) referenceExamples=\(reference.examples.count) candidateExamples=\(candidate.examples.count) addedLessons=\(request.supportDelta.addedLessons.count) sharedUnchanged=true noTeaching=true accuracyMeasured=false reportSHA256=\(sha(data))")
    }

    func testProfileDeltaAcceptsArbitraryAppendOnlySetupLessons() throws {
        let original = example(label: "A", offset: 0)
        let additions = [example(label: "o", offset: 10), example(label: "(", offset: 20)]
        let (reference, candidate) = profiles(referenceExamples: [original], additions: additions)
        XCTAssertNoThrow(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                       supportDelta: delta(reference: reference,
                                                                           candidate: candidate)))
    }

    func testProfileDeltaRejectsPrefixMutation() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        var (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        candidate.examples[0].label = "B"
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: delta(reference: reference,
                                                                                candidate: candidate)))
    }

    func testProfileDeltaRejectsWrongSource() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", source: .explicitCorrection, offset: 10)
        let (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: delta(reference: reference,
                                                                                candidate: candidate)))
    }

    func testProfileDeltaRejectsMismatchedCommittedExampleData() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        let (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        let otherData = try Self.canonical(example(label: "7", offset: 99))
        let commitment = AddedLesson(id: addition.id, label: addition.label, kind: .glyph, source: .setup,
                                     exampleData: otherData, exampleSHA256: Self.sha(otherData))
        let support = SupportDelta(referenceCount: reference.examples.count,
                                   candidateCount: candidate.examples.count, addedLessons: [commitment])
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: support))
    }

    func testProfileDeltaRejectsMismatchedCommittedHash() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        let (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        let data = try Self.canonical(addition)
        let commitment = AddedLesson(id: addition.id, label: addition.label, kind: .glyph, source: .setup,
                                     exampleData: data, exampleSHA256: String(repeating: "0", count: 64))
        let support = SupportDelta(referenceCount: reference.examples.count,
                                   candidateCount: candidate.examples.count, addedLessons: [commitment])
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: support))
    }

    func testProfileDeltaRejectsMismatchedCommittedLabel() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        let (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        let data = try Self.canonical(addition)
        let commitment = AddedLesson(id: addition.id, label: "6", kind: .glyph, source: .setup,
                                     exampleData: data, exampleSHA256: Self.sha(data))
        let support = SupportDelta(referenceCount: reference.examples.count,
                                   candidateCount: candidate.examples.count, addedLessons: [commitment])
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: support))
    }

    func testProfileDeltaRejectsUnchangedRevision() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        var (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        candidate.revision = reference.revision
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: delta(reference: reference,
                                                                                candidate: candidate)))
    }

    func testProfileDeltaRejectsCountMismatch() throws {
        let original = example(label: "A", offset: 0)
        let addition = example(label: "7", offset: 10)
        let (reference, candidate) = profiles(referenceExamples: [original], additions: [addition])
        var support = try delta(reference: reference, candidate: candidate)
        support = SupportDelta(referenceCount: support.referenceCount,
                               candidateCount: support.candidateCount + 1,
                               addedLessons: support.addedLessons)
        XCTAssertThrowsError(try Self.validateProfileDelta(reference: reference, candidate: candidate,
                                                            supportDelta: support))
    }

    private static func validateRequestShape(_ data: Data) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let request = value as? [String: Any], Set(request.keys) == [
            "version", "journalPath", "journalSHA256", "referenceProfilePath",
            "referenceProfileSHA256", "candidateProfilePath", "candidateProfileSHA256",
            "supportDelta", "runIDs", "runtimeDirectory", "runtimeFileMapPath",
            "runtimeFileMapSHA256", "repositoryRoot", "codeFileMapPath",
            "codeFileMapSHA256", "outputPath"
        ], let support = request["supportDelta"] as? [String: Any],
        Set(support.keys) == ["referenceCount", "candidateCount", "addedLessons"],
        let additions = support["addedLessons"] as? [[String: Any]],
        additions.allSatisfy({ Set($0.keys) == [
            "id", "label", "kind", "source", "exampleData", "exampleSHA256"
        ] }) else {
            throw ValidationFailure.invalidRequest
        }
    }

    @discardableResult
    private static func validateProfileDelta(reference: PersonalInkProfile,
                                             candidate: PersonalInkProfile,
                                             supportDelta: SupportDelta) throws -> [PersonalInkExample] {
        guard reference.isEnabled, candidate.isEnabled,
              reference.revision != candidate.revision,
              supportDelta.referenceCount == reference.examples.count,
              supportDelta.candidateCount == candidate.examples.count,
              (0...PersonalInkProfile.maximumExamples).contains(supportDelta.referenceCount),
              (1...PersonalInkProfile.maximumExamples).contains(supportDelta.candidateCount),
              supportDelta.candidateCount - supportDelta.referenceCount == supportDelta.addedLessons.count,
              !supportDelta.addedLessons.isEmpty,
              Array(candidate.examples.prefix(reference.examples.count)) == reference.examples else {
            throw ValidationFailure.invalidSupportDelta
        }
        var retainedReference = candidate
        retainedReference.examples = reference.examples
        retainedReference.revision = reference.revision
        guard retainedReference == reference else { throw ValidationFailure.invalidSupportDelta }

        let referenceIDs = Set(reference.examples.map(\.id))
        let candidateIDs = candidate.examples.map(\.id)
        let committedIDs = supportDelta.addedLessons.map(\.id)
        guard referenceIDs.count == reference.examples.count,
              Set(candidateIDs).count == candidateIDs.count,
              Set(committedIDs).count == committedIDs.count,
              referenceIDs.isDisjoint(with: committedIDs) else {
            throw ValidationFailure.invalidSupportDelta
        }
        let additions = Array(candidate.examples.dropFirst(reference.examples.count))
        guard additions.count == supportDelta.addedLessons.count else {
            throw ValidationFailure.invalidSupportDelta
        }
        for (example, commitment) in zip(additions, supportDelta.addedLessons) {
            guard commitment.kind == .glyph, commitment.source == .setup,
                  example.kind == .glyph, example.source == .setup,
                  commitment.id == example.id, commitment.label == example.label,
                  commitment.kind == example.kind, commitment.source == example.source,
                  PersonalInkProfile.glyphLabels.contains(commitment.label),
                  sha(commitment.exampleData) == commitment.exampleSHA256,
                  try JSONDecoder().decode(PersonalInkExample.self,
                                           from: commitment.exampleData) == example else {
                throw ValidationFailure.invalidSupportDelta
            }
        }
        return additions
    }

    private func profiles(referenceExamples: [PersonalInkExample], additions: [PersonalInkExample])
        -> (PersonalInkProfile, PersonalInkProfile) {
        let generation = UUID()
        var reference = PersonalInkProfile()
        reference.generation = generation
        reference.isEnabled = true
        reference.examples = referenceExamples
        var candidate = reference
        candidate.revision = UUID()
        candidate.examples.append(contentsOf: additions)
        return (reference, candidate)
    }

    private func example(label: String, source: PersonalInkExampleSource = .setup,
                         offset: Double) -> PersonalInkExample {
        PersonalInkExample(kind: .glyph, label: label,
            strokes: [InkStroke(points: [
                InkPoint(x: offset, y: 0, timeOffset: nil),
                InkPoint(x: offset + 1, y: 2, timeOffset: nil)
            ])], source: source)
    }

    private func delta(reference: PersonalInkProfile, candidate: PersonalInkProfile) throws -> SupportDelta {
        let additions = candidate.examples.dropFirst(reference.examples.count)
        return try SupportDelta(referenceCount: reference.examples.count,
            candidateCount: candidate.examples.count, addedLessons: additions.map { example in
                let data = try Self.canonical(example)
                return AddedLesson(id: example.id, label: example.label, kind: example.kind,
                                   source: example.source, exampleData: data,
                                   exampleSHA256: Self.sha(data))
            })
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
        guard data.count <= maximum else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
        return data
    }

    private func fileMap(_ root: URL, paths: Set<String>) throws -> [String: String] {
        guard (1...1_024).contains(paths.count) else {
            throw PersonalInkLearnedComparison.Failure.invalidFrozenLineage
        }
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
            let properties = try root.appendingPathComponent(path)
                .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true else {
                throw PersonalInkLearnedComparison.Failure.invalidEncoder
            }
            if properties.isRegularFile == true { paths.insert(path) }
        }
        return try fileMap(root, paths: paths)
    }

    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        try Self.canonical(value)
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func sha(_ data: Data) -> String { Self.sha(data) }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
