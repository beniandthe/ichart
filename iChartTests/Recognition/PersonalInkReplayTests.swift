import XCTest
import CryptoKit
@testable import iChart

/// Opt-in, local-only diagnostic. No captured handwriting is bundled in tests.
/// Replays the personal layer against recorded base decisions; it does NOT run
/// OCR again, reconstruct raw Pencil input, or establish held-out accuracy.
final class PersonalInkReplayTests: XCTestCase {
    func testProvidedJournalReplaysPersonalPolicyWithoutMutatingEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PERSONAL_REPLAY_FILE"] else {
            throw XCTSkip("Provide an authorized local evaluation journal to run this diagnostic")
        }
        let url = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: url)
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: original)
        let runs = journal.runs.filter { $0.status == .complete }
        XCTAssertFalse(runs.isEmpty)
        var summaries: [[String: Any]] = []
        for run in runs {
            let records = run.scoreable
            XCTAssertFalse(records.isEmpty)
            let snapshot = PersonalInkSnapshot(profile: run.profile)
            var correct = 0
            var regressions = 0
            var correctionsPreferred = 0
            var recoveryPreferred = 0
            for record in records {
                let suggestion = snapshot.suggestion(strokes: record.recognitionInput)
                let selection = PersonalInkArbitrationPolicy.select(baselineText: record.baseline,
                    baselineTrusted: try XCTUnwrap(record.baselineEvidenceIsTrusted), suggestion: suggestion)
                // Only same-pipeline captures are parity evidence. Historical
                // runs remain a counterfactual replay of the current policy.
                if run.pipeline == ChordInkRecognitionPipelineIdentity.version {
                    XCTAssertEqual(selection.text, record.personalized, "Saved ink/profile changed the personal default in run \(run.id)")
                    XCTAssertEqual(selection.prefersPersonal ? "confirm" : record.baselineAction,
                                   record.personalizedAction)
                    if let disposition = record.personalArbitration {
                        XCTAssertEqual(selection.disposition.rawValue, disposition)
                    }
                }
                if selection.text == record.intended { correct += 1 }
                if record.baseline == record.intended && selection.text != record.intended { regressions += 1 }
                if selection.disposition == .correctedReview { correctionsPreferred += 1 }
                if selection.disposition == .personalRecovery { recoveryPreferred += 1 }
                if record.baselineAction == "trusted" { XCTAssertEqual(selection.text, record.baseline) }
            }
            summaries.append(["runID": run.id.uuidString, "phase": run.phase.rawValue, "pipeline": run.pipeline,
                "style": run.style, "targets": records.count, "wholeChartScoreAvailable": run.wholeChartScoreAvailable,
                "groupingTargetsExcluded": run.records.filter(\.groupingIssue).count, "recordedBaselineCorrect": run.baselineCorrect,
                "recordedPersonalCorrect": run.personalizedCorrect, "replayedPersonalCorrect": correct,
                "replayedRegressions": regressions, "correctionsPreferred": correctionsPreferred,
                "recoveriesPreferred": recoveryPreferred])
        }
        // A development experiment only: teach one chart's labels in an
        // in-memory profile, then evaluate distinct ink from another run.
        // Neither the iPad profile nor either frozen run is written.
        var transfer: [[String: Any]] = []
        let trainingRuns: [PersonalInkEvaluationRun]
        if let selected = ProcessInfo.processInfo.environment["ICHART_PERSONAL_REPLAY_TRAIN_RUN"] {
            let id = try XCTUnwrap(UUID(uuidString: selected))
            trainingRuns = runs.filter { $0.id == id && $0.phase == .beforeCorrections }
            XCTAssertEqual(trainingRuns.count, 1, "Use the preselected completed baseline, not the best-performing transfer")
        } else {
            trainingRuns = runs.filter { $0.phase == .beforeCorrections }
        }
        for training in trainingRuns {
            for testing in runs where testing.id != training.id && testing.profile.revision == training.profile.revision {
                var profile = training.profile
                for record in training.scoreable {
                    try profile.learn(strokes: record.recognitionInput, label: try XCTUnwrap(record.intended), kind: .chord, source: .explicitCorrection)
                }
                let trained = PersonalInkSnapshot(profile: profile)
                let trainingInk = Set(training.records.map(\.fingerprint))
                let eligible = testing.scoreable.filter { !trainingInk.contains($0.fingerprint) && !trained.wasAlreadyLearned(strokes: $0.recognitionInput) }
                var correct = 0
                var gains = 0
                var harms = 0
                var changed: [[String: String]] = []
                for record in eligible {
                    let suggestion = trained.suggestion(strokes: record.recognitionInput)
                    let selection = PersonalInkArbitrationPolicy.select(baselineText: record.baseline,
                        baselineTrusted: try XCTUnwrap(record.baselineEvidenceIsTrusted), suggestion: suggestion)
                    if selection.text == record.intended { correct += 1 }
                    if record.baseline != record.intended && selection.text == record.intended { gains += 1 }
                    if record.baseline == record.intended && selection.text != record.intended { harms += 1 }
                    if selection.text != record.baseline {
                        changed.append(["intended": record.intended ?? "", "recordedBaseline": record.baseline ?? "no-read",
                                        "selected": selection.text ?? "no-read", "disposition": selection.disposition.rawValue])
                    }
                }
                transfer.append(["trainRunID": training.id.uuidString, "testRunID": testing.id.uuidString,
                    "testPhase": testing.phase.rawValue, "testPipeline": testing.pipeline,
                    "trainedExamples": profile.examples.count, "trainStyle": training.style,
                    "testStyle": testing.style, "eligibleTargets": eligible.count,
                    "correct": correct, "gainsOverRecordedBaseline": gains, "regressions": harms, "changedDefaults": changed])
            }
        }
        let report: [String: Any] = ["scope": "development replay; recorded baseline; exact input when retained, normalized legacy ink otherwise; not a fresh accuracy test",
                                    "sourceSHA256": SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
                                    "policy": PersonalInkArbitrationPolicy.version, "runs": summaries, "crossChartTeachingExperiment": transfer]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        print("PERSONAL_REPLAY_REPORT\n\(String(decoding: encoded, as: UTF8.self))")
        if let output = ProcessInfo.processInfo.environment["ICHART_PERSONAL_REPLAY_REPORT"] {
            XCTAssertNotEqual(URL(fileURLWithPath: output).standardizedFileURL, url.standardizedFileURL)
            guard URL(fileURLWithPath: output).standardizedFileURL != url.standardizedFileURL else { return }
            try encoded.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
