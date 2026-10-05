import XCTest
import CryptoKit
@testable import iChart

/// Test-only paired analysis. Reference profiles are read, never trained; labels
/// are consulted only after all three predictions have been fixed.
private struct FrozenProfileComparison: Codable {
    enum Failure: Error {
        case unfinished, incompatibleProfile, differentPipeline
        case missingOrAmbiguousTraceInput(UUID)
        case missingRecognitionEvidence(UUID)
        case replayMismatch(record: UUID, recordedText: String?, replayedText: String?,
                            recordedAction: String, replayedAction: String,
                            recordedDisposition: String?, replayedDisposition: String,
                            recordedSuggestion: ChordInkPersonalSuggestion?, replayedSuggestion: ChordInkPersonalSuggestion?)
    }
    struct Row: Codable {
        let id: UUID
        let intended: String?
        let native: String?
        let referencePersonal: String?
        let capturedPersonal: String?
        let nativeAction: String
        let capturedAction: String
        let inputSource: String
        let inputGlyphClusters: [[Int]]
        let previewGlyphClusters: [[Int]]
        let exclusions: [String]
    }
    let runID: UUID
    let style: String
    let pipeline: String
    let referenceRevision: UUID
    let capturedRevision: UUID
    let referenceExampleCount: Int
    let capturedExampleCount: Int
    let written: Int
    let missing: Int
    let wholeChartDenominator: Int?
    let rows: [Row]

    var eligible: [Row] { rows.filter { $0.exclusions.isEmpty } }
    var nativeCorrect: Int { eligible.filter { $0.native == $0.intended }.count }
    var referenceCorrect: Int { eligible.filter { $0.referencePersonal == $0.intended }.count }
    var capturedCorrect: Int { eligible.filter { $0.capturedPersonal == $0.intended }.count }
    var gainsOverReference: Int {
        eligible.filter { $0.referencePersonal != $0.intended && $0.capturedPersonal == $0.intended }.count
    }
    var harmsOverReference: Int {
        eligible.filter { $0.referencePersonal == $0.intended && $0.capturedPersonal != $0.intended }.count
    }
    var gainsOverNative: Int { eligible.filter { $0.native != $0.intended && $0.capturedPersonal == $0.intended }.count }
    var harmsOverNative: Int { eligible.filter { $0.native == $0.intended && $0.capturedPersonal != $0.intended }.count }
    var nativeNoReads: Int { eligible.filter { $0.native == nil }.count }
    var referenceNoReads: Int { eligible.filter { $0.referencePersonal == nil }.count }
    var capturedNoReads: Int { eligible.filter { $0.capturedPersonal == nil }.count }
    var nativeTrustedWrong: Int { eligible.filter { $0.nativeAction == "trusted" && $0.native != $0.intended }.count }
    var capturedTrustedWrong: Int {
        eligible.filter { $0.capturedAction == "trusted" && $0.capturedPersonal != $0.intended }.count
    }

    /// Legacy journals saved thumbnail-sized geometry. Recover exact input only
    /// from a matching device event: never pick ink by its label or prediction.
    static func traceInputs(run: PersonalInkEvaluationRun,
                            events: [ChordDraftPreviewDeviceDiagnosticEvent]) throws -> [UUID: [InkStroke]] {
        var inputs: [UUID: [InkStroke]] = [:]
        for record in run.records {
            let matches = events.filter {
                ($0.stage == "finish_batch" || $0.stage == "finish_single") &&
                $0.recognitionPipelineVersion == run.pipeline && $0.layoutStyle == run.style &&
                $0.timestamp >= run.startedAt && abs($0.timestamp.timeIntervalSince(record.capturedAt)) < 2
            }.flatMap(\.payloads).filter {
                record.measureID != nil && $0.measureID == record.measureID &&
                record.visualOrder != nil && $0.visualOrder == record.visualOrder && $0.fraction == record.fraction
            }.compactMap { payload -> [InkStroke]? in
                guard let ink = payload.inkStrokes,
                      PersonalInkShape(strokes: ink)?.normalizedStrokes == record.strokes else { return nil }
                return ink
            }
            let unique = Set(matches)
            guard unique.count == 1, let ink = unique.first else {
                throw Failure.missingOrAmbiguousTraceInput(record.id)
            }
            inputs[record.id] = ink
        }
        return inputs
    }

    init(run: PersonalInkEvaluationRun, reference: PersonalInkProfile, priorFingerprints: Set<String> = [],
         traceEvents: [ChordDraftPreviewDeviceDiagnosticEvent]? = nil) throws {
        guard run.status == .complete, let written = run.expectedChordCount, written > 0 else { throw Failure.unfinished }
        guard run.pipeline == ChordInkRecognitionPipelineIdentity.version else { throw Failure.differentPipeline }
        guard reference.version == run.profile.version, reference.generation == run.profile.generation,
              reference.isEnabled, run.profile.isEnabled else { throw Failure.incompatibleProfile }
        let old = PersonalInkSnapshot(profile: reference)
        let frozen = PersonalInkSnapshot(profile: run.profile)
        let exactInputs = try traceEvents.map { try Self.traceInputs(run: run, events: $0) }
        var seen = priorFingerprints
        var rows: [Row] = []
        for record in run.records {
            let input = exactInputs?[record.id] ?? record.recognitionInput
            guard let baselineTrusted = record.baselineEvidenceIsTrusted else {
                throw Failure.missingRecognitionEvidence(record.id)
            }
            let oldSelection = PersonalInkArbitrationPolicy.select(baselineText: record.baseline,
                baselineTrusted: baselineTrusted, suggestion: old.suggestion(strokes: input))
            let replaySuggestion = frozen.suggestion(strokes: input)
            let replay = PersonalInkArbitrationPolicy.select(baselineText: record.baseline,
                baselineTrusted: baselineTrusted, suggestion: replaySuggestion)
            guard replay.text == record.personalized,
                  (replay.prefersPersonal ? "confirm" : record.baselineAction) == record.personalizedAction,
                  record.personalArbitration == nil || replay.disposition.rawValue == record.personalArbitration else {
                throw Failure.replayMismatch(record: record.id, recordedText: record.personalized, replayedText: replay.text,
                    recordedAction: record.personalizedAction,
                    replayedAction: replay.prefersPersonal ? "confirm" : record.baselineAction,
                    recordedDisposition: record.personalArbitration, replayedDisposition: replay.disposition.rawValue,
                    recordedSuggestion: record.personalSuggestion, replayedSuggestion: replaySuggestion)
            }
            // Exclude learned/repeated ink under either profile, even if an
            // older capture omitted its known-ink flag. Keep exclusions visible.
            var exclusions: [String] = []
            if record.groupingIssue { exclusions.append("grouping") }
            if PersonalInkShape(strokes: input) == nil { exclusions.append("invalidInk") }
            if record.knownInk || old.wasAlreadyLearned(strokes: input)
                || frozen.wasAlreadyLearned(strokes: input) { exclusions.append("knownInk") }
            if !seen.insert(record.fingerprint).inserted { exclusions.append("repeatedFingerprint") }
            if record.intended.flatMap({ ChordRecognitionCompendium.match($0) })?.displayText != record.intended
                || record.intended == nil { exclusions.append("unlabeledOrInvalid") }
            rows.append(Row(id: record.id, intended: record.intended, native: record.baseline,
                referencePersonal: oldSelection.text, capturedPersonal: record.personalized,
                nativeAction: record.baselineAction, capturedAction: record.personalizedAction,
                inputSource: exactInputs != nil ? "matchedExactDeviceTrace" :
                    (record.recognitionStrokes == nil ? "savedNormalizedInk" : "savedExactRecognitionInput"),
                inputGlyphClusters: StrokeClusterer().indexedClusters(input.map { InkStroke(points: $0.points) }).map(\.originalIndexes),
                previewGlyphClusters: StrokeClusterer().indexedClusters(record.strokes.map { InkStroke(points: $0.points) }).map(\.originalIndexes),
                exclusions: exclusions))
        }
        runID = run.id; style = run.style; pipeline = run.pipeline
        referenceRevision = reference.revision; capturedRevision = run.profile.revision
        referenceExampleCount = reference.examples.count; capturedExampleCount = run.profile.examples.count
        self.written = written; missing = max(0, written - rows.count); self.rows = rows
        wholeChartDenominator = written >= rows.count && rows.allSatisfy { $0.exclusions.isEmpty } ? written : nil
    }
}

final class PersonalInkFrozenProfileComparisonTests: XCTestCase {
    private let ink = [InkStroke(points: [InkPoint(x: 0, y: 25), InkPoint(x: 10, y: 0), InkPoint(x: 20, y: 25)]),
                       InkStroke(points: [InkPoint(x: 4, y: 15), InkPoint(x: 16, y: 15)])]

    private func fixture(exactInk: Bool = false) throws -> (PersonalInkProfile, PersonalInkEvaluationRun) {
        var reference = PersonalInkProfile()
        reference.isEnabled = true
        var updated = reference
        try updated.learn(strokes: ink, label: "A", kind: .chord, source: .explicitCorrection)
        var fresh = ink
        if !exactInk { fresh[0].points[1].x += 1.5 }
        let suggestion = PersonalInkSnapshot(profile: updated).suggestion(strokes: fresh)
        let choice = PersonalInkArbitrationPolicy.select(baselineText: "C", baselineTrusted: false, suggestion: suggestion)
        XCTAssertEqual(choice.text, "C")
        XCTAssertEqual(choice.disposition, .alternative)
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .afterCorrections,
            pipeline: ChordInkRecognitionPipelineIdentity.version, profile: updated)
        run.status = .complete; run.expectedChordCount = 1
        run.records = [PersonalInkEvaluationRecord(measureIndex: 0, fraction: 0.25, strokes: fresh,
            fingerprint: PersonalInkEvaluationStore.fingerprint(strokes: fresh), baseline: "C", personalized: choice.text,
            baselineAction: "confirm", personalizedAction: "confirm", knownInk: false,
            recognitionMilliseconds: 0, totalMilliseconds: 0, cacheHit: false, intended: "A")]
        return (reference, run)
    }

    func testLabelsChangeScoresButCannotChangePredictionsOrProfiles() throws {
        let (reference, run) = try fixture()
        let before = try JSONEncoder().encode(run.profile)
        let first = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(first.eligible.count, 1)
        XCTAssertEqual(first.nativeCorrect, 0); XCTAssertEqual(first.referenceCorrect, 0)
        XCTAssertEqual(first.capturedCorrect, 0); XCTAssertEqual(first.gainsOverReference, 0)
        var relabeled = run; relabeled.records[0].intended = "C"
        let second = try FrozenProfileComparison(run: relabeled, reference: reference)
        XCTAssertEqual(first.rows[0].referencePersonal, second.rows[0].referencePersonal)
        XCTAssertEqual(first.rows[0].capturedPersonal, second.rows[0].capturedPersonal)
        XCTAssertEqual(second.nativeCorrect, 1); XCTAssertEqual(second.referenceCorrect, 1)
        XCTAssertEqual(second.capturedCorrect, 1); XCTAssertEqual(second.harmsOverReference, 0)
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkProfile.self, from: before), run.profile)
        XCTAssertTrue(reference.examples.isEmpty)
    }

    func testTrustedWrongReadsStayVisibleAndNoReadsAreNotCountedAsMatches() throws {
        let (reference, valid) = try fixture()
        var run = valid
        run.records[0].baselineAction = "trusted"
        run.records[0].personalized = "C"
        run.records[0].personalizedAction = "trusted"
        let trusted = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(trusted.nativeTrustedWrong, 1); XCTAssertEqual(trusted.capturedTrustedWrong, 1)
        XCTAssertEqual(trusted.gainsOverNative, 0); XCTAssertEqual(trusted.capturedCorrect, 0)
        run = valid
        run.records[0].baseline = nil
        run.records[0].personalized = "A"
        let recovered = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(recovered.nativeNoReads, 1); XCTAssertEqual(recovered.referenceNoReads, 1)
        XCTAssertEqual(recovered.capturedNoReads, 0); XCTAssertEqual(recovered.gainsOverReference, 1)
        run.records[0].groupingIssue = true
        let grouped = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(grouped.eligible.count, 0); XCTAssertNil(grouped.wholeChartDenominator)
    }

    func testKnownAndRepeatedInkAreExcludedAndMissingCountsStayVisible() throws {
        let (reference, known) = try fixture(exactInk: true)
        let excluded = try FrozenProfileComparison(run: known, reference: reference)
        XCTAssertEqual(excluded.eligible.count, 0); XCTAssertNil(excluded.wholeChartDenominator)
        XCTAssertTrue(excluded.rows[0].exclusions.contains("knownInk"))
        var (_, fresh) = try fixture()
        fresh.profile.generation = reference.generation
        fresh.records[0].intended = "C"
        fresh.expectedChordCount = 2
        let missing = try FrozenProfileComparison(run: fresh, reference: reference)
        XCTAssertEqual(missing.missing, 1); XCTAssertEqual(missing.wholeChartDenominator, 2)
        XCTAssertEqual(missing.capturedCorrect, 1, "One observed match cannot become two written matches")
        let repeated = try FrozenProfileComparison(run: fresh, reference: reference,
            priorFingerprints: [fresh.records[0].fingerprint])
        XCTAssertEqual(repeated.eligible.count, 0); XCTAssertNil(repeated.wholeChartDenominator)
    }

    func testNoReadRecoveryCanShowGainsAndHarmsBetweenFrozenProfiles() throws {
        var (reference, run) = try fixture()
        try reference.learn(strokes: ink, label: "C", kind: .chord, source: .explicitCorrection)
        run.records[0].baseline = nil
        run.records[0].personalized = "A"
        run.records[0].intended = "C"
        let harm = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(harm.nativeNoReads, 1)
        XCTAssertEqual(harm.referenceCorrect, 1); XCTAssertEqual(harm.capturedCorrect, 0)
        XCTAssertEqual(harm.harmsOverReference, 1); XCTAssertEqual(harm.gainsOverReference, 0)
        run.records[0].intended = "A"
        let gain = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(harm.rows[0].referencePersonal, gain.rows[0].referencePersonal)
        XCTAssertEqual(harm.rows[0].capturedPersonal, gain.rows[0].capturedPersonal)
        XCTAssertEqual(gain.referenceCorrect, 0); XCTAssertEqual(gain.capturedCorrect, 1)
        XCTAssertEqual(gain.gainsOverReference, 1); XCTAssertEqual(gain.harmsOverReference, 0)
    }

    func testIncompleteRunsWrongProfilesAndReplayMismatchCannotProduceAReadout() throws {
        let (reference, valid) = try fixture()
        var run = valid; run.status = .capturing
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
        run = valid; run.profile.generation = UUID()
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
        run = valid; run.pipeline = "different-pipeline"
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
        run = valid; run.records[0].personalized = "B"
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
    }

    func testEditedCaptureReplaysEvidenceSeparatelyFromRequiredReview() throws {
        let (reference, valid) = try fixture()
        var run = valid
        run.records[0].requiresEditReview = true
        // An old edited record has lost the arbitration input. Do not make up
        // a score or mutate its saved profile to force parity.
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
        run.records[0].baselineRecognitionAction = "trusted"
        run.records[0].personalized = "C"
        run.records[0].personalArbitration = "protectedBaseline"
        let report = try FrozenProfileComparison(run: run, reference: reference)
        XCTAssertEqual(report.rows[0].capturedPersonal, "C")
        XCTAssertEqual(report.rows[0].capturedAction, "confirm")
        XCTAssertEqual(report.capturedTrustedWrong, 0)
        XCTAssertEqual(report.capturedCorrect, 0, "Review-only still does not mean correct")
        let decoded = try JSONDecoder().decode(PersonalInkEvaluationRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded.records[0].baselineEvidenceIsTrusted, true)
        run.records[0].baselineRecognitionAction = "invalid"
        XCTAssertThrowsError(try FrozenProfileComparison(run: run, reference: reference))
    }

    func testLegacyTraceRecoveryRequiresExactGeometryContextAndUniqueInput() throws {
        let (reference, valid) = try fixture()
        var run = valid
        let input = run.records[0].strokes
        run.records[0].strokes = try XCTUnwrap(PersonalInkShape(strokes: input)).normalizedStrokes
        run.records[0].measureID = UUID(); run.records[0].visualOrder = 0.25
        run.records[0].fingerprint = PersonalInkEvaluationStore.fingerprint(strokes: run.records[0].strokes)
        let record = run.records[0]
        var event = ChordDraftPreviewDeviceDiagnosticEvent(timestamp: record.capturedAt,
            stage: "finish_batch", recognitionPipelineVersion: run.pipeline, layoutStyle: run.style,
            payloads: [.init(targetIndex: 0, measureID: record.measureID, fraction: record.fraction,
                visualOrder: record.visualOrder, strokeCount: input.count, rawCandidates: [], supportedCandidates: [],
                action: "confirm", reason: "fixture", confidence: 0, closeRace: false, topScores: [], inkStrokes: input)])
        XCTAssertEqual(try FrozenProfileComparison.traceInputs(run: run, events: [event])[record.id], input)
        let report = try FrozenProfileComparison(run: run, reference: reference, traceEvents: [event])
        XCTAssertEqual(report.rows[0].inputSource, "matchedExactDeviceTrace")
        // Neither a label nor a recorded prediction participates in joining ink.
        var relabeled = run; relabeled.records[0].intended = "G"; relabeled.records[0].personalized = "F"
        XCTAssertEqual(try FrozenProfileComparison.traceInputs(run: relabeled, events: [event])[record.id], input)
        var wrongContext = event; wrongContext.layoutStyle = "anotherStyle"
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [wrongContext]))
        wrongContext = event; wrongContext.recognitionPipelineVersion = "anotherPipeline"
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [wrongContext]))
        wrongContext = event; wrongContext.timestamp = record.capturedAt.addingTimeInterval(3)
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [wrongContext]))
        wrongContext = event; wrongContext.payloads[0].measureID = UUID()
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [wrongContext]))
        wrongContext = event; wrongContext.payloads[0].inkStrokes![0].points[0].x += 7
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [wrongContext]))
        let original = event
        event.payloads[0].inkStrokes = input.map { InkStroke(points: $0.points, creationTimeOffset: 7) }
        XCTAssertThrowsError(try FrozenProfileComparison.traceInputs(run: run, events: [original, event]),
            "Different exact inputs sharing normalized geometry are ambiguous, not interchangeable")
        run.records[0].recognitionStrokes = input
        let roundTripped = try JSONDecoder().decode(PersonalInkEvaluationRun.self, from: JSONEncoder().encode(run))
        let saved = try FrozenProfileComparison(run: roundTripped, reference: reference)
        XCTAssertEqual(saved.rows[0].inputSource, "savedExactRecognitionInput")
        XCTAssertEqual(saved.capturedCorrect, report.capturedCorrect)
    }

    func testProvidedCompletedRunsAgainstFrozenReferenceProfile() throws {
        let env = ProcessInfo.processInfo.environment
        guard let journalPath = env["ICHART_PERSONAL_COMPARE_JOURNAL"],
              let referencePath = env["ICHART_PERSONAL_COMPARE_REFERENCE"],
              let selectedIDs = env["ICHART_PERSONAL_COMPARE_RUN_IDS"] else {
            throw XCTSkip("Supply a local journal, frozen reference profile and preselected run IDs")
        }
        let journalURL = URL(fileURLWithPath: journalPath).resolvingSymlinksInPath()
        let referenceURL = URL(fileURLWithPath: referencePath).resolvingSymlinksInPath()
        let journalData = try Data(contentsOf: journalURL), referenceData = try Data(contentsOf: referenceURL)
        let journal = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: journalData)
        let reference = try JSONDecoder().decode(PersonalInkProfile.self, from: referenceData)
        let traceURL = env["ICHART_PERSONAL_COMPARE_TRACE"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        let traceData = try traceURL.map { try Data(contentsOf: $0) }
        let traceEvents = try traceURL.map { try ChordDraftPreviewDeviceDiagnosticRecorder(url: $0).loadEvents() }
        let ids = try selectedIDs.split(separator: ",").map { try XCTUnwrap(UUID(uuidString: String($0))) }
        guard !ids.isEmpty, Set(ids).count == ids.count else { XCTFail("Select distinct, nonempty run IDs"); return }
        var reports: [[String: Any]] = []
        var frozenProfile: PersonalInkProfile?
        for id in ids {
            let run = try XCTUnwrap(journal.runs.first { $0.id == id })
            if let frozenProfile, run.profile != frozenProfile {
                XCTFail("Paired styles must freeze the same profile")
                return
            }
            frozenProfile = run.profile
            let earlier = Set(journal.runs.filter { $0.startedAt < run.startedAt }.flatMap(\.records).map(\.fingerprint))
            let report = try FrozenProfileComparison(run: run, reference: reference, priorFingerprints: earlier,
                traceEvents: traceEvents)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
            object["eligibleTargets"] = report.eligible.count
            object["nativeCorrect"] = report.nativeCorrect
            object["referenceCorrect"] = report.referenceCorrect
            object["capturedCorrect"] = report.capturedCorrect
            object["gainsOverReference"] = report.gainsOverReference
            object["harmsOverReference"] = report.harmsOverReference
            object["gainsOverNative"] = report.gainsOverNative
            object["harmsOverNative"] = report.harmsOverNative
            object["nativeNoReads"] = report.nativeNoReads
            object["referenceNoReads"] = report.referenceNoReads
            object["capturedNoReads"] = report.capturedNoReads
            object["nativeTrustedWrong"] = report.nativeTrustedWrong
            object["capturedTrustedWrong"] = report.capturedTrustedWrong
            reports.append(object)
        }
        var report: [String: Any] = [
            "scope": "same-writer frozen-profile comparison; recorded native decisions; reference is counterfactual; not cross-writer accuracy",
            "journalSHA256": SHA256.hash(data: journalData).map { String(format: "%02x", $0) }.joined(),
            "referenceSHA256": SHA256.hash(data: referenceData).map { String(format: "%02x", $0) }.joined(),
            "runs": reports
        ]
        if let traceData { report["traceSHA256"] = SHA256.hash(data: traceData).map { String(format: "%02x", $0) }.joined() }
        let output = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        if let path = env["ICHART_PERSONAL_COMPARE_REPORT"] {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard url != journalURL, url != referenceURL, url != traceURL else { XCTFail("Cannot overwrite input evidence"); return }
            try output.write(to: url, options: .atomic)
        }
        XCTAssertEqual(try Data(contentsOf: journalURL), journalData)
        XCTAssertEqual(try Data(contentsOf: referenceURL), referenceData)
        if let traceURL { XCTAssertEqual(try Data(contentsOf: traceURL), traceData) }
        print("PERSONAL_FROZEN_PROFILE_COMPARISON\n\(String(decoding: output, as: UTF8.self))")
    }
}
