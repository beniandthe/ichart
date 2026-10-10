#if DEBUG && canImport(CoreML)
import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Counterfactual old lessons versus the actual captured profile on the same
/// saved transfer ink. This is neither a new capture nor independent-writer evidence.
final class PersonalInkLessonTransferAblationTests: XCTestCase {
    func testProvidedTransferRunsIsolateFourAddedSymbolLessons() throws {
        let env = ProcessInfo.processInfo.environment
        guard let journalPath = env["ICHART_PERSONAL_LESSON_ABLATION_JOURNAL"],
              let profilePath = env["ICHART_PERSONAL_LESSON_ABLATION_REFERENCE_PROFILE"],
              let selectedIDs = env["ICHART_PERSONAL_LESSON_ABLATION_RUN_IDS"],
              let runtimePath = env["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"],
              let reportPath = env["ICHART_PERSONAL_LESSON_ABLATION_REPORT_DIRECTORY"] else {
            throw XCTSkip("Provide the local transfer journal, old profile, preselected run IDs, runtime and separate report directory")
        }
        guard [journalPath, profilePath, selectedIDs, runtimePath, reportPath].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { XCTFail("Ablation environment values must be nonempty"); return }
        let ids = try selectedIDs.split(separator: ",", omittingEmptySubsequences: false).map {
            try XCTUnwrap(UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        guard !ids.isEmpty, Set(ids).count == ids.count else {
            XCTFail("Select distinct, nonempty run IDs"); return
        }
        func resolved(_ path: String) -> URL {
            URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        }
        let journalURL = resolved(journalPath), profileURL = resolved(profilePath)
        let runtimeURL = resolved(runtimePath), reportURL = resolved(reportPath)
        guard journalURL != profileURL,
              ![journalURL, profileURL, journalURL.deletingLastPathComponent(),
                profileURL.deletingLastPathComponent(), runtimeURL].contains(reportURL),
              !reportURL.path.hasPrefix(runtimeURL.path + "/") else {
            XCTFail("Reports must be separate from source evidence and the runtime package"); return
        }
        let manifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let journalBytes = try Data(contentsOf: journalURL), profileBytes = try Data(contentsOf: profileURL)
        let manifestBytes = try Data(contentsOf: manifestURL)
        defer {
            let preservedJournalBytes = try? Data(contentsOf: journalURL)
            XCTAssertTrue(preservedJournalBytes == journalBytes, "Source journal bytes must remain unchanged")
            XCTAssertTrue((try? Data(contentsOf: profileURL)) == profileBytes, "Old-profile file bytes must remain unchanged")
            XCTAssertTrue((try? Data(contentsOf: manifestURL)) == manifestBytes, "Runtime manifest bytes must remain unchanged")
            if let original = try? JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalBytes) {
                let preserved = preservedJournalBytes.flatMap { try? JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: $0) }
                XCTAssertTrue(preserved?.runs.count == original.runs.count &&
                    zip(preserved?.runs ?? [], original.runs).allSatisfy { $0.id == $1.id && $0.profile == $1.profile },
                    "Every source run must retain its actual frozen profile")
            }
        }
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalBytes)
        let oldProfile = try JSONDecoder().decode(PersonalInkProfile.self, from: profileBytes)
        guard journal.version == 1, oldProfile.examples.count == 30 else {
            XCTFail("This four-lesson ablation requires a v1 journal and the explicitly supplied 30-example profile"); return
        }
        let runs = try ids.map { id -> PersonalInkEvaluationRun in
            let matches = journal.runs.filter { $0.id == id }
            return try XCTUnwrap(matches.count == 1 ? matches.first : nil, "Each selected ID must identify one actual saved run")
        }
        let actualProfile = try XCTUnwrap(runs.first?.profile)
        guard runs.allSatisfy({ $0.status == .complete && !$0.records.isEmpty && $0.profile == actualProfile &&
            Set($0.records.map(\.id)).count == $0.records.count &&
            $0.expectedChordCount.map({ (1...64).contains($0) }) == true }),
            Set(runs.flatMap(\.records).map(\.id)).count == runs.flatMap(\.records).count else {
            XCTFail("Select completed runs with one actual frozen profile, valid written counts and unique record IDs"); return
        }
        guard oldProfile.version == actualProfile.version, oldProfile.generation == actualProfile.generation,
              oldProfile.isEnabled, actualProfile.isEnabled,
              oldProfile.learnsFromReviews == actualProfile.learnsFromReviews,
              oldProfile.revision != actualProfile.revision, actualProfile.examples.count == 34,
              Set(oldProfile.examples.map(\.id)).count == oldProfile.examples.count,
              Set(actualProfile.examples.map(\.id)).count == actualProfile.examples.count,
              oldProfile.examples.allSatisfy(actualProfile.examples.contains) else {
            XCTFail("The actual 34-example profile must preserve every old example and all non-lesson settings"); return
        }
        let oldIDs = Set(oldProfile.examples.map(\.id))
        let added = actualProfile.examples.filter { !oldIDs.contains($0.id) }
        guard added.count == 4, added.allSatisfy({ $0.kind == .glyph && $0.source == .setup }),
              Set(added.map(\.label)) == Set(["△", "7", "#", "/"]),
              oldProfile.examples.filter({ $0.kind == .chord }) == actualProfile.examples.filter({ $0.kind == .chord }) else {
            XCTFail("Only the four specified setup-symbol lessons may differ; whole-chord lessons must be unchanged"); return
        }
        let encoder = try PersonalInkVisualEncoder(directory: runtimeURL)
        guard encoder.anchorBank != nil else { XCTFail("This paired ablation requires both personal learner variants"); return }
        let oldModel = try PersonalInkLearnedComparison(profile: oldProfile, encoder: encoder, grouping: .legacyGeometryV1)
        var predictions: [[LessonAblation.Row]] = []
        let selected = Set(ids)
        let firstStart = try XCTUnwrap(runs.map(\.startedAt).min())
        var seen = Set(journal.runs.filter { !selected.contains($0.id) && $0.startedAt < firstStart }
            .flatMap(\.records).map(\.fingerprint))
        // All inference finishes before any intended labels are consulted.
        // The old profile is counterfactual; no run's captured profile is replaced.
        for run in runs {
            let actualModel = try PersonalInkLearnedComparison(profile: run.profile, encoder: encoder, grouping: .legacyGeometryV1)
            XCTAssertEqual(oldModel.encoderIdentity, actualModel.encoderIdentity)
            let inputs = run.records.map { LessonAblation.Input(id: $0.id, strokes: $0.recognitionStrokes,
                groupingIssue: $0.groupingIssue, knownInk: $0.knownInk, fingerprint: $0.fingerprint) }
            predictions.append(try LessonAblation.predict(inputs, old: oldModel, actual: actualModel, seen: &seen))
            XCTAssertTrue(actualModel.profile == run.profile && oldModel.profile == oldProfile)
        }
        let scoredRuns = try zip(runs, predictions).map { run, rows -> LessonAblation.Run in
            let scored = LessonAblation.score(rows, intended: Dictionary(uniqueKeysWithValues:
                run.records.map { ($0.id, $0.intended) }))
            return .init(id: run.id, style: run.style, sourcePipeline: run.pipeline,
                sourceRunSHA256: try LessonAblation.digest(run),
                evaluationSourceSHA256: try PersonalInkLearnedRunReport.evaluationSourceDigest(run),
                written: run.expectedChordCount, rows: scored)
        }
        let report = try LessonAblation.Report(journalSHA256: LessonAblation.digest(journalBytes),
            oldProfileFileSHA256: LessonAblation.digest(profileBytes), oldProfileSHA256: LessonAblation.digest(oldProfile),
            actualFrozenProfileSHA256: LessonAblation.digest(actualProfile),
            oldRevision: oldProfile.revision, actualFrozenRevision: actualProfile.revision,
            profileGeneration: oldProfile.generation, encoderIdentity: encoder.identity,
            runtimeManifestSHA256: LessonAblation.digest(manifestBytes),
            addedLessons: added.map { .init(id: $0.id, label: $0.label, kind: $0.kind, source: $0.source,
                exampleSHA256: try LessonAblation.digest($0)) }, runs: scoredRuns)
        guard testRun?.failureCount == 0 else { return }
        try FileManager.default.createDirectory(at: reportURL, withIntermediateDirectories: true)
        try LessonAblation.json(report).write(to: reportURL.appendingPathComponent("\(report.id.uuidString).json"),
            options: .withoutOverwriting)
        let allScores = scoredRuns.flatMap(\.scores)
        func total(_ variant: LessonAblation.Variant, _ value: (LessonAblation.Score) -> Int) -> Int {
            allScores.filter { $0.variant == variant }.reduce(0) { $0 + value($1) }
        }
        print("PERSONAL_LESSON_ABLATION runs=\(runs.count) addedLessons=\(added.count) captured=\(scoredRuns.reduce(0) { $0 + $1.rows.count }) eligible=\(scoredRuns.reduce(0) { $0 + $1.eligibleCount }) excluded=\(scoredRuns.reduce(0) { $0 + $1.rows.count - $1.eligibleCount }) wholeChartDenominators=\(scoredRuns.filter { $0.wholeChartDenominator != nil }.count) sharedCorrect=\(total(.shared, { $0.oldCorrect })) originalOldCorrect=\(total(.original, { $0.oldCorrect })) originalNewCorrect=\(total(.original, { $0.newCorrect })) originalGains=\(total(.original, { $0.gains })) originalHarms=\(total(.original, { $0.harms })) anchoredOldCorrect=\(total(.anchored, { $0.oldCorrect })) anchoredNewCorrect=\(total(.anchored, { $0.newCorrect })) anchoredGains=\(total(.anchored, { $0.gains })) anchoredHarms=\(total(.anchored, { $0.harms }))")
    }

    func testIntendedLabelsChangeAblationScoresWithoutChangingEitherProfilesPredictions() throws {
        struct Encoder: PersonalInkVisualEncoding {
            let identity = "controlled-ablation-wiring-only"
            let vocabulary = ["A", "B"]
            var anchorBank: PersonalInkAnchorBank? {
                .init(vocabulary: vocabulary, features: Array(repeating: [1.0] + Array(repeating: 0, count: 127), count: 2))
            }
            func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
                .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
            }
        }
        var old = PersonalInkProfile(); old.isEnabled = true
        var actual = old
        try actual.learn(strokes: [.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])],
            label: "B", kind: .glyph, source: .setup)
        let input = LessonAblation.Input(id: UUID(),
            strokes: [.init(points: [.init(x: 0, y: 0), .init(x: 2, y: 9), .init(x: 0, y: 20)])],
            groupingIssue: false, knownInk: false, fingerprint: "fresh-controlled-input")
        let oldModel = try PersonalInkLearnedComparison(profile: old, encoder: Encoder(), grouping: .legacyGeometryV1)
        let actualModel = try PersonalInkLearnedComparison(profile: actual, encoder: Encoder(), grouping: .legacyGeometryV1)
        var seen = Set<String>()
        let fixed = try LessonAblation.predict([input], old: oldModel, actual: actualModel, seen: &seen)
        let before = try LessonAblation.json(fixed)
        let a = LessonAblation.Run(id: UUID(), style: "fixture", sourcePipeline: "fixture",
            sourceRunSHA256: "fixture", evaluationSourceSHA256: "fixture", written: 1,
            rows: LessonAblation.score(fixed, intended: [input.id: "A"]))
        let b = LessonAblation.Run(id: a.id, style: "fixture", sourcePipeline: "fixture",
            sourceRunSHA256: "fixture", evaluationSourceSHA256: "fixture", written: 1,
            rows: LessonAblation.score(fixed, intended: [input.id: "B"]))
        XCTAssertEqual(try LessonAblation.json(fixed), before)
        XCTAssertEqual(a.rows[0].old, b.rows[0].old); XCTAssertEqual(a.rows[0].actual, b.rows[0].actual)
        XCTAssertEqual(a.scores.first { $0.variant == .original }?.harms, 1)
        XCTAssertEqual(b.scores.first { $0.variant == .original }?.gains, 1)
        XCTAssertEqual(oldModel.profile, old); XCTAssertEqual(actualModel.profile, actual)
        XCTAssertEqual(a.eligibleCount, 1); XCTAssertEqual(b.eligibleCount, 1)
        XCTAssertFalse(LessonAblation.score(fixed, intended: [input.id: "D>"])[0].exclusions.isEmpty)
    }
}

private enum LessonAblation {
    struct Input {
        let id: UUID
        let strokes: [InkStroke]?
        let groupingIssue: Bool
        let knownInk: Bool
        let fingerprint: String
    }
    struct Row: Codable {
        let id: UUID
        let exactInputSHA256: String?
        let oldKnownInk: Bool
        let actualKnownInk: Bool
        let old: PersonalInkLearnedComparison.Prediction?
        let actual: PersonalInkLearnedComparison.Prediction?
        let unsupportedInput: Bool
        var exclusions: [String]
        var intended: String? = nil
    }
    enum Variant: String, Codable, CaseIterable { case shared, original, anchored }
    struct Score: Codable {
        let variant: Variant
        let oldCorrect: Int
        let newCorrect: Int
        let oldNoReads: Int
        let newNoReads: Int
        let oldWrongReads: Int
        let newWrongReads: Int
        let gains: Int
        let harms: Int
        let changedReads: Int
    }
    struct Run: Encodable {
        let id: UUID
        let style: String
        let sourcePipeline: String
        let sourceRunSHA256: String
        let evaluationSourceSHA256: String
        let written: Int?
        let rows: [Row]
        var eligibleCount: Int { rows.filter { $0.exclusions.isEmpty }.count }
        var missingCount: Int { max(0, (written ?? 0) - rows.count) }
        var groupingIssueCount: Int { rows.filter { $0.exclusions.contains("incorrectGrouping") }.count }
        var knownInkCount: Int {
            rows.filter { $0.oldKnownInk || $0.actualKnownInk || $0.exclusions.contains("recordedKnownInk") }.count
        }
        var unsupportedInputCount: Int { rows.filter { $0.exclusions.isEmpty && $0.unsupportedInput }.count }
        var wholeChartDenominator: Int? {
            guard let written, (1...64).contains(written), written >= rows.count,
                  eligibleCount == rows.count else { return nil }
            return written
        }
        var scores: [Score] {
            let eligible = rows.filter { $0.exclusions.isEmpty }
            return Variant.allCases.map { variant in
                func read(_ prediction: PersonalInkLearnedComparison.Prediction?) -> String? {
                    switch variant {
                    case .shared: return prediction?.genericChord
                    case .original: return prediction?.personalChord
                    case .anchored: return prediction?.anchored?.chord
                    }
                }
                let oldCorrect = eligible.filter { read($0.old) == $0.intended }.count
                let newCorrect = eligible.filter { read($0.actual) == $0.intended }.count
                let oldNoReads = eligible.filter { read($0.old) == nil }.count
                let newNoReads = eligible.filter { read($0.actual) == nil }.count
                return .init(variant: variant, oldCorrect: oldCorrect, newCorrect: newCorrect,
                    oldNoReads: oldNoReads, newNoReads: newNoReads,
                    oldWrongReads: eligible.count - oldCorrect - oldNoReads,
                    newWrongReads: eligible.count - newCorrect - newNoReads,
                    gains: eligible.filter { read($0.old) != $0.intended && read($0.actual) == $0.intended }.count,
                    harms: eligible.filter { read($0.old) == $0.intended && read($0.actual) != $0.intended }.count,
                    changedReads: eligible.filter { read($0.old) != read($0.actual) }.count)
            }
        }
        // Computed metrics are explicitly persisted, rather than lost by Codable.
        enum CodingKeys: String, CodingKey {
            case id, style, sourcePipeline, sourceRunSHA256, evaluationSourceSHA256, written, rows
            case eligibleCount, missingCount, groupingIssueCount, knownInkCount, unsupportedInputCount, wholeChartDenominator, scores
        }
        func encode(to encoder: Swift.Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(style, forKey: .style)
            try c.encode(sourcePipeline, forKey: .sourcePipeline); try c.encode(sourceRunSHA256, forKey: .sourceRunSHA256)
            try c.encode(evaluationSourceSHA256, forKey: .evaluationSourceSHA256); try c.encodeIfPresent(written, forKey: .written)
            try c.encode(rows, forKey: .rows); try c.encode(eligibleCount, forKey: .eligibleCount)
            try c.encode(missingCount, forKey: .missingCount); try c.encodeIfPresent(wholeChartDenominator, forKey: .wholeChartDenominator)
            try c.encode(groupingIssueCount, forKey: .groupingIssueCount); try c.encode(knownInkCount, forKey: .knownInkCount)
            try c.encode(unsupportedInputCount, forKey: .unsupportedInputCount)
            try c.encode(scores, forKey: .scores)
        }
    }
    struct AddedLesson: Codable {
        let id: UUID
        let label: String
        let kind: PersonalInkExampleKind
        let source: PersonalInkExampleSource
        let exampleSHA256: String
    }
    struct Report: Encodable {
        var id = UUID()
        var createdAt = Date()
        let version = "lesson-ablation-v1"
        let scope = "same-writer saved-input lesson ablation; old30 is counterfactual, actual34 was frozen in the selected runs; not independent-writer accuracy"
        let groupingVersion = PersonalInkLearnedComparison.Grouping.legacyGeometryV1.rawValue
        let originalLearnerVersion = PersonalInkResidualHead.version
        let anchoredLearnerVersion = PersonalInkAnchoredResidualHead.version
        let profileDigestFormat = "sorted-json-profile-v1"
        let journalSHA256: String
        let oldProfileFileSHA256: String
        let oldProfileSHA256: String
        let actualFrozenProfileSHA256: String
        let oldRevision: UUID
        let actualFrozenRevision: UUID
        let profileGeneration: UUID
        let encoderIdentity: String
        let runtimeManifestSHA256: String
        let addedLessons: [AddedLesson]
        let runs: [Run]
    }
    static func predict(_ inputs: [Input], old: PersonalInkLearnedComparison, actual: PersonalInkLearnedComparison,
                        seen: inout Set<String>) throws -> [Row] {
        let oldSnapshot = PersonalInkSnapshot(profile: old.profile), actualSnapshot = PersonalInkSnapshot(profile: actual.profile)
        return try inputs.map { input in
            let oldKnown = input.strokes.map { oldSnapshot.wasAlreadyLearned(strokes: $0) } ?? false
            let actualKnown = input.strokes.map { actualSnapshot.wasAlreadyLearned(strokes: $0) } ?? false
            var exclusions: [String] = []
            if input.groupingIssue { exclusions.append("incorrectGrouping") }
            if input.knownInk { exclusions.append("recordedKnownInk") }
            if oldKnown { exclusions.append("knownUnderOldProfile") }
            if actualKnown { exclusions.append("knownUnderActualFrozenProfile") }
            if !seen.insert(input.fingerprint).inserted { exclusions.append("repeatedCapturedFingerprint") }
            if input.strokes == nil { exclusions.append("missingExactRecognitionInput") }
            var oldPrediction: PersonalInkLearnedComparison.Prediction?, actualPrediction: PersonalInkLearnedComparison.Prediction?
            if let strokes = input.strokes, !input.groupingIssue {
                func predict(_ model: PersonalInkLearnedComparison) throws -> PersonalInkLearnedComparison.Prediction? {
                    do { return try model.predict(strokes, currentProfile: model.profile) }
                    catch PersonalInkLearnedComparison.Failure.invalidInk { return nil }
                }
                oldPrediction = try predict(old); actualPrediction = try predict(actual)
                XCTAssertEqual(oldPrediction == nil, actualPrediction == nil, "Changing lessons cannot change input validity")
                if let before = oldPrediction, let after = actualPrediction {
                    XCTAssertTrue(before.genericChord == after.genericChord, "Shared full-chord outputs must be identical")
                    XCTAssertTrue(before.glyphs.map(\.generic) == after.glyphs.map(\.generic), "Shared glyph rankings must be identical")
                    XCTAssertTrue(before.glyphs.map(\.originalStrokeIndexes) == after.glyphs.map(\.originalStrokeIndexes),
                        "Grouping must be identical")
                    XCTAssertTrue(before.wholeChordRanks == after.wholeChordRanks, "Whole-chord lessons are identical")
                    XCTAssertNotNil(before.anchored); XCTAssertNotNil(after.anchored)
                }
            }
            return .init(id: input.id, exactInputSHA256: try input.strokes.map { try digest($0) },
                oldKnownInk: oldKnown, actualKnownInk: actualKnown, old: oldPrediction, actual: actualPrediction,
                unsupportedInput: input.strokes != nil && !input.groupingIssue && oldPrediction == nil,
                exclusions: exclusions)
        }
    }
    static func score(_ predictions: [Row], intended: [UUID: String?]) -> [Row] {
        predictions.map { prediction in
            var row = prediction
            if let label = intended[row.id] ?? nil, let parsed = try? ChordSymbolParser.parse(label), parsed.displayText == label {
                row.intended = label
            } else { row.exclusions.append("unlabeledOrInvalidCompleteChord") }
            return row
        }
    }
    static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) throws -> String { digest(try json(value)) }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
#endif
