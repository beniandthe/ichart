import XCTest
@testable import iChart

final class PersonalInkEvaluationTests: XCTestCase {
    private var folder: URL!
    private var url: URL { folder.appendingPathComponent("evaluation.json") }
    private var store: PersonalInkEvaluationStore!
    private let chartID = UUID()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = PersonalInkEvaluationStore(url: url)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    func testStartFreezesProfileAndSurvivesReloadScopedToChart() throws {
        var profile = PersonalInkProfile(); profile.isEnabled = true
        let id = try start(profile: profile)
        profile.revision = UUID()
        XCTAssertEqual(store.context(chartID: chartID)?.runID, id)
        XCTAssertNotEqual(store.context(chartID: chartID)?.profile.profile.revision, profile.revision)
        XCTAssertNil(store.context(chartID: UUID()))
        let reloaded = PersonalInkEvaluationStore(url: url)
        XCTAssertEqual(reloaded.context(chartID: chartID)?.runID, id)
        XCTAssertEqual(reloaded.snapshot().journal.activeRun?.pipeline, "test-pipeline")
    }

    func testNewRunFreezesObservedSupportLineageWithoutBackfillingLegacyExamples() throws {
        var profile = PersonalInkProfile()
        try profile.learn(strokes: record("support").strokes, label: "C", kind: .chord, source: .setup)
        let id = try start(profile: profile)
        let frozen = try XCTUnwrap(run(id).profileLineage)
        XCTAssertEqual(frozen.querySessionID, id)
        XCTAssertEqual(frozen.untrackedExampleIDs, profile.examples.map(\.id))
        XCTAssertFalse(frozen.isMetadataComplete)
        XCTAssertFalse(frozen.areObservedSupportSessionsDisjoint)
        XCTAssertEqual(PersonalInkEvaluationStore(url: url).snapshot().journal.activeRun?.profileLineage, frozen)
        XCTAssertNil(run(id).profile.examples.first?.learningProvenance)
    }

    func testSavedExactInputTeachingBindsRunRecordAndStyleWithoutRewritingFrozenEvidence() throws {
        for style in ["simpleChordSheet", "rhythmSectionSheet"] {
            let profileURL = folder.appendingPathComponent("\(style)-profile.json")
            let profileStore = PersonalInkProfileStore(url: profileURL)
            try succeed { store.start(chartID: chartID, style: style, phase: .beforeCorrections,
                profile: profileStore.snapshot().profile, pipeline: "test", completion: $0) }
            let id = try XCTUnwrap(store.snapshot().journal.activeRun?.id)
            var r = record("exact-\(style)")
            r.recognitionStrokes = [InkStroke(points: [InkPoint(x: 100, y: 50, timeOffset: 0.1),
                InkPoint(x: 140, y: 90, timeOffset: 0.3)], creationTimeOffset: 4)]
            store.capture(runID: id, records: [r])
            try succeed { store.stop(runID: id, completion: $0) }
            try succeed { store.label(runID: id, recordID: r.id, text: "D7", groupingIssue: false, completion: $0) }
            try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
            let frozenProfile = run(id).profile, frozenLineage = run(id).profileLineage
            let frozenRecord = try XCTUnwrap(run(id).records.first)
            try succeed { store.teachLabeledExamples(runID: id, profileStore: profileStore, completion: $0) }
            let lesson = try XCTUnwrap(profileStore.snapshot().profile.examples.first)
            let provenance = try XCTUnwrap(lesson.learningProvenance)
            XCTAssertEqual(provenance.context.sessionID, id)
            XCTAssertEqual(provenance.context.captureID, r.id)
            XCTAssertEqual(provenance.context.capturedAt, r.capturedAt)
            XCTAssertEqual(provenance.context.origin, .savedEvaluation)
            XCTAssertEqual(provenance.context.chartStyle, PersonalInkCaptureContext.chartStyleToken(for: style))
            XCTAssertEqual(provenance.originalInputSHA256, try PersonalInkLearningProvenance.inputSHA256(strokes: r.recognitionInput))
            XCTAssertEqual(lesson.recognitionInput, r.recognitionInput)
            XCTAssertEqual(provenance.storedInputRole, .recognitionInput)
            try provenance.validate(example: lesson)
            XCTAssertEqual(run(id).profile, frozenProfile)
            XCTAssertEqual(run(id).profileLineage, frozenLineage)
            var delivered = try XCTUnwrap(run(id).records.first)
            delivered.taught = frozenRecord.taught
            XCTAssertEqual(delivered, frozenRecord)
            XCTAssertEqual(PersonalInkProfileStore(url: profileURL).snapshot().profile.examples.first?.learningProvenance, provenance)
        }
    }

    func testLegacyThumbnailTeachingRetainsUnknownLineageAndOldRunHasNoInventedSummary() throws {
        let r = record("legacy")
        var oldRun = PersonalInkEvaluationRun(chartID: chartID, style: "simpleChordSheet",
            phase: .beforeCorrections, pipeline: "old-test", profile: .init())
        oldRun.status = .complete
        var labeled = r; labeled.intended = "C"
        oldRun.records = [labeled]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldData = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [oldRun]))
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("profileLineage"))
        try oldData.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        let profileStore = PersonalInkProfileStore(url: folder.appendingPathComponent("legacy-profile.json"))
        XCTAssertNil(run(oldRun.id).profileLineage)
        try succeed { store.teachLabeledExamples(runID: oldRun.id, profileStore: profileStore, completion: $0) }
        XCTAssertEqual(profileStore.snapshot().profile.examples.count, 1)
        XCTAssertNil(profileStore.snapshot().profile.examples.first?.learningProvenance)
        XCTAssertNil(run(oldRun.id).profileLineage)
        XCTAssertEqual(run(oldRun.id).profile, oldRun.profile)
    }

    func testExactRecognitionInputRoundTripsAndLegacyRemainsExplicitlyMissing() throws {
        let legacy = record("legacy")
        let oldData = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("recognitionStrokes"))
        let decoded = try JSONDecoder().decode(PersonalInkEvaluationRecord.self, from: oldData)
        XCTAssertNil(decoded.recognitionStrokes)
        XCTAssertEqual(decoded.recognitionInput, legacy.strokes)
        var current = legacy
        current.recognitionStrokes = [InkStroke(points: [InkPoint(x: 40, y: 90, timeOffset: 0.1),
                                                        InkPoint(x: 80, y: 120, timeOffset: 0.2)], creationTimeOffset: 3)]
        let id = try start()
        store.capture(runID: id, records: [current])
        try succeed { store.stop(runID: id, completion: $0) }
        let saved = try XCTUnwrap(PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first?.records.first)
        XCTAssertEqual(saved, current)
        XCTAssertEqual(saved.recognitionInput, current.recognitionStrokes)
        XCTAssertNotEqual(saved.recognitionInput, saved.strokes)
    }

    func testExactInputStorageRemainsBoundedAndRejectsRatherThanTruncates() throws {
        var r = record("bounded")
        r.recognitionStrokes = [InkStroke(points: Array(repeating: InkPoint(x: 0, y: 0), count: 32_768))]
        XCTAssertTrue(r.isWithinStorageBounds)
        r.recognitionStrokes![0].points.append(InkPoint(x: 1, y: 1))
        XCTAssertFalse(r.isWithinStorageBounds)
        let id = try start()
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        XCTAssertTrue(run(id).records.isEmpty)
        r.recognitionStrokes = Array(repeating: InkStroke(points: []), count: 65)
        XCTAssertFalse(r.isWithinStorageBounds)
    }

    func testLatestDraftReplacesPartialStrokesAndStopFlushesQueuedCapture() throws {
        let id = try start()
        store.capture(runID: id, records: [record("partial", baseline: "C", personalized: "A")])
        store.capture(runID: id, records: [record("final-1"), record("final-2")])
        try succeed { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).records.map(\.fingerprint), ["final-1", "final-2"])
        XCTAssertEqual(run(id).snapshotCount, 2)
        XCTAssertNil(store.context(chartID: chartID))
        let reloaded = PersonalInkEvaluationStore(url: url)
        XCTAssertEqual(reloaded.snapshot().journal.runs[0].records.count, 2)
    }

    func testChangedPredictionForUnchangedInkKeepsLatestDeliveredEvidence() throws {
        let id = try start()
        let initial = record("unchanged-ink", baseline: nil, personalized: nil)
        var final = record("unchanged-ink", baseline: "C", personalized: "C")
        final.baselineAction = "trusted"; final.personalizedAction = "trusted"
        final.personalArbitration = "agreement"; final.cacheHit = true
        final.recognitionMilliseconds = 2; final.totalMilliseconds = 5
        store.capture(runID: id, records: [initial])
        store.capture(runID: id, records: [final])
        try succeed { store.stop(runID: id, completion: $0) }
        let saved = try XCTUnwrap(PersonalInkEvaluationStore(url: url).snapshot().journal.runs[0].records.first)
        XCTAssertEqual(saved.baseline, "C")
        XCTAssertEqual(saved.personalized, "C")
        XCTAssertEqual(saved.baselineAction, "trusted")
        XCTAssertEqual(saved.personalArbitration, "agreement")
        XCTAssertTrue(saved.cacheHit)
        XCTAssertEqual(saved.recognitionMilliseconds, 2)
        XCTAssertEqual(saved.totalMilliseconds, 5)
        XCTAssertEqual(run(id).snapshotCount, 2)
    }

    func testSameInkPlacementAndPersonalEvidenceChangesAreNotDropped() throws {
        let id = try start()
        let initial = record("unchanged-ink")
        var relocated = initial
        relocated.measureID = UUID(); relocated.measureIndex = 3
        relocated.fraction = 0.5; relocated.visualOrder = 4
        var reviewed = relocated
        reviewed.personalSuggestion = .init(text: "G", source: .wholeChord, distance: 0.02,
                                            supportingExampleCount: 2, correctionSupportCount: 1)
        reviewed.personalArbitration = "protectedBaseline"
        store.capture(runID: id, records: [initial])
        store.capture(runID: id, records: [relocated])
        store.capture(runID: id, records: [reviewed])
        try succeed { store.stop(runID: id, completion: $0) }
        let saved = try XCTUnwrap(run(id).records.first)
        XCTAssertEqual(saved.measureID, reviewed.measureID)
        XCTAssertEqual(saved.measureIndex, 3)
        XCTAssertEqual(saved.fraction, 0.5)
        XCTAssertEqual(saved.visualOrder, 4)
        XCTAssertEqual(saved.personalSuggestion, reviewed.personalSuggestion)
        XCTAssertEqual(saved.personalArbitration, "protectedBaseline")
        XCTAssertEqual(run(id).snapshotCount, 3)
    }

    func testEquivalentDeliveredContentDoesNotBecomeAnExtraSnapshot() throws {
        let id = try start()
        let initial = record("unchanged-ink")
        var duplicate = initial
        duplicate.id = UUID(); duplicate.capturedAt = initial.capturedAt.addingTimeInterval(1)
        store.capture(runID: id, records: [initial, initial])
        store.capture(runID: id, records: [duplicate, duplicate])
        try succeed { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).snapshotCount, 1)
        XCTAssertEqual(run(id).records.map(\.knownInk), [false, true])
        XCTAssertEqual(run(id).records.first?.id, initial.id)
    }

    func testStaleAndPostStopCallbacksCannotRewriteEvidence() throws {
        let id = try start()
        store.capture(runID: UUID(), records: [record("stale")])
        store.capture(runID: id, records: [record("final")])
        try succeed { store.stop(runID: id, completion: $0) }
        store.capture(runID: id, records: [record("too-late")])
        let r = try XCTUnwrap(run(id).records.first)
        try succeed { store.label(runID: id, recordID: r.id, text: "C", groupingIssue: false, completion: $0) }
        XCTAssertEqual(run(id).records.map(\.fingerprint), ["final"])
        XCTAssertEqual(run(id).records.first?.intended, "C")
    }

    func testLabelsMustFollowPredictionAndCompletingRequiresAllLabels() throws {
        let id = try start()
        let r = record("one")
        store.capture(runID: id, records: [r])
        try fails { store.label(runID: id, recordID: r.id, text: "C", groupingIssue: false, completion: $0) }
        try succeed { store.stop(runID: id, completion: $0) }
        try fails { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
        try fails { store.label(runID: id, recordID: r.id, text: "not a chord", groupingIssue: false, completion: $0) }
        XCTAssertNil(run(id).records.first?.intended)
    }

    func testScoreIncludesNoReadsAndReportsGainsAndHarmsSeparately() throws {
        let id = try start()
        let records = [record("fixed", baseline: nil, personalized: "C"), record("broken", baseline: "C", personalized: "G"), record("none", baseline: nil, personalized: nil)]
        store.capture(runID: id, records: records)
        try succeed { store.stop(runID: id, completion: $0) }
        for r in records { try succeed { store.label(runID: id, recordID: r.id, text: "C", groupingIssue: false, completion: $0) } }
        try succeed { store.finish(runID: id, expectedCount: 4, slowInk: true, unexpectedChanges: true, completion: $0) }
        let scored = run(id)
        XCTAssertEqual(scored.improvements, 1); XCTAssertEqual(scored.regressions, 1)
        XCTAssertEqual(scored.baselineNoReads, 2); XCTAssertEqual(scored.personalizedNoReads, 1)
        XCTAssertEqual(scored.missingCount, 1)
        XCTAssertTrue(scored.wholeChartScoreAvailable)
        XCTAssertEqual(scored.expectedChordCount, 4, "Missing attempts must remain in the whole-chart denominator")
        let reloaded = PersonalInkEvaluationStore(url: url).snapshot().journal.runs[0]
        XCTAssertEqual(reloaded.baselineCorrect, 1); XCTAssertEqual(reloaded.personalizedCorrect, 1)
        XCTAssertEqual(reloaded.inkFeltSlow, true); XCTAssertEqual(reloaded.unexpectedChartChanges, true)
    }

    func testGroupingOrCountMismatchWithholdsWholeChartAccuracy() throws {
        let id = try start(); let r = record("merged")
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: nil, groupingIssue: true, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 2, slowInk: false, unexpectedChanges: false, completion: $0) }
        XCTAssertFalse(run(id).wholeChartScoreAvailable)
        XCTAssertTrue(run(id).scoreable.isEmpty)
        var mismatch = run(id); mismatch.expectedChordCount = 0
        XCTAssertFalse(mismatch.wholeChartScoreAvailable)
    }

    func testRepeatedGeometryIsFlaggedWithinAndAcrossRuns() throws {
        let first = try start()
        store.capture(runID: first, records: [record("same"), record("same")])
        try succeed { store.stop(runID: first, completion: $0) }
        XCTAssertEqual(run(first).records.map(\.knownInk), [false, true])
        let second = try start()
        store.capture(runID: second, records: [record("same")])
        try succeed { store.stop(runID: second, completion: $0) }
        XCTAssertEqual(run(second).records.first?.knownInk, true)
    }

    func testLearningIsExplicitAfterScoringAndNeverChangesFrozenResults() throws {
        let profile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let id = try start(); let r = record("teach", baseline: "G", personalized: "G")
        store.capture(runID: id, records: [r])
        try fails { store.teach(runID: id, recordID: r.id, profileStore: profile, completion: $0) }
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: "C", groupingIssue: false, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
        XCTAssertTrue(profile.snapshot().profile.examples.isEmpty)
        try succeed { store.teach(runID: id, recordID: r.id, profileStore: profile, completion: $0) }
        XCTAssertEqual(profile.snapshot().profile.examples.count, 1)
        XCTAssertEqual(run(id).personalizedCorrect, 0)
        XCTAssertTrue(run(id).profile.examples.isEmpty)
        XCTAssertTrue(run(id).records[0].taught)
        try succeed { store.teach(runID: id, recordID: r.id, profileStore: profile, completion: $0) }
        XCTAssertEqual(profile.snapshot().profile.examples.count, 1)
    }

    func testSecondActiveRunAndInvalidWrittenCountsAreRejected() throws {
        let id = try start()
        try fails { store.start(chartID: UUID(), style: "rhythmSectionSheet", phase: .afterCorrections, profile: .init(), pipeline: "test", completion: $0) }
        try succeed { store.stop(runID: id, completion: $0) }
        for count in [0, 65, -1] { try fails { store.finish(runID: id, expectedCount: count, slowInk: false, unexpectedChanges: false, completion: $0) } }
    }

    func testZeroCaptureIsPersistedAsFailureNotZeroAttemptSuccess() throws {
        let id = try start()
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 10, slowInk: false, unexpectedChanges: false, completion: $0) }
        XCTAssertEqual(run(id).missingCount, 10)
        XCTAssertEqual(run(id).personalizedCorrect, 0)
        XCTAssertTrue(run(id).wholeChartScoreAvailable)
    }

    func testInvalidJournalFailsClosedWithoutOverwritingFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bad = Data("not json".utf8); try bad.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNotNil(store.snapshot().error)
        try fails { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections, profile: .init(), pipeline: "test", completion: $0) }
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }

    func testSixteenSavedRunsAppendSeventeenthWithoutRewritingHistory() throws {
        let savedRuns = try historicalRuns(count: 16)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let frozenHistory = try encoder.encode(savedRuns)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(PersonalInkEvaluationJournal(runs: savedRuns)).write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNil(store.snapshot().error)
        XCTAssertEqual(try encoder.encode(store.snapshot().journal.runs), frozenHistory)

        let id = try start()
        let r = record("seventeenth")
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: "C", groupingIssue: false, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }

        let current = store.snapshot()
        XCTAssertNil(current.error)
        XCTAssertEqual(current.journal.runs.map(\.id), savedRuns.map(\.id) + [id])
        XCTAssertEqual(try encoder.encode(Array(current.journal.runs.prefix(16))), frozenHistory)
        let reloaded = PersonalInkEvaluationStore(url: url).snapshot()
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.journal.runs.map(\.id), savedRuns.map(\.id) + [id])
        let retained = Array(reloaded.journal.runs.prefix(16))
        XCTAssertEqual(try encoder.encode(retained), frozenHistory)
        XCTAssertEqual(retained.map(\.profile), savedRuns.map(\.profile))
        XCTAssertEqual(retained.map(\.profileLineage), savedRuns.map(\.profileLineage))
        XCTAssertEqual(retained.map { $0.sourceSnapshot?.canonicalVisibleTrajectoryData },
                       savedRuns.map { $0.sourceSnapshot?.canonicalVisibleTrajectoryData })
        XCTAssertEqual(retained.map { $0.sourceSnapshot?.normalizedDrawingData },
                       savedRuns.map { $0.sourceSnapshot?.normalizedDrawingData })
    }

    func testThirtyTwoSavedRunsRejectStartWithoutEvictingOrChangingFile() throws {
        XCTAssertEqual(PersonalInkEvaluationStore.maximumRuns, 32)
        let savedRuns = try historicalRuns(count: PersonalInkEvaluationStore.maximumRuns)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let savedData = try encoder.encode(PersonalInkEvaluationJournal(runs: savedRuns))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try savedData.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNil(store.snapshot().error)

        try fails { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections,
                                profile: .init(), pipeline: "test", completion: $0) }
        XCTAssertEqual(try Data(contentsOf: url), savedData)
        XCTAssertNil(store.context(chartID: chartID))
        XCTAssertEqual(try encoder.encode(store.snapshot().journal.runs), try encoder.encode(savedRuns))
        let reloaded = PersonalInkEvaluationStore(url: url).snapshot()
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.journal.runs.count, 32)
        XCTAssertEqual(try encoder.encode(reloaded.journal.runs), try encoder.encode(savedRuns))
    }

    func testJournalAboveThirtyTwoRunsFailsClosedWithoutOverwritingFile() throws {
        let savedRuns = try historicalRuns(count: PersonalInkEvaluationStore.maximumRuns + 1)
        let savedData = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: savedRuns))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try savedData.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNotNil(store.snapshot().error)
        XCTAssertTrue(store.snapshot().journal.runs.isEmpty)
        XCTAssertNil(store.context(chartID: chartID))

        try fails { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections,
                                profile: .init(), pipeline: "test", completion: $0) }
        XCTAssertEqual(try Data(contentsOf: url), savedData)
        XCTAssertNotNil(PersonalInkEvaluationStore(url: url).snapshot().error)
    }

    func testTwentyFourMegabyteBudgetRejectsWritesAndLoadsWithoutChangingSource() throws {
        XCTAssertEqual(PersonalInkEvaluationStore.maximumJournalByteCount, 24_000_000)
        let savedRuns = try historicalRuns(count: 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let savedData = try encoder.encode(PersonalInkEvaluationJournal(runs: savedRuns))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try savedData.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNil(store.snapshot().error)
        let oversizedPipeline = String(repeating: "x", count: PersonalInkEvaluationStore.maximumJournalByteCount)

        try fails { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections,
                                profile: .init(), pipeline: oversizedPipeline, completion: $0) }
        XCTAssertEqual(try Data(contentsOf: url), savedData)
        XCTAssertNil(store.context(chartID: chartID))
        XCTAssertEqual(try encoder.encode(store.snapshot().journal.runs), try encoder.encode(savedRuns))

        var oversizedRun = savedRuns[0]
        oversizedRun.pipeline = oversizedPipeline
        let oversizedData = try encoder.encode(PersonalInkEvaluationJournal(runs: [oversizedRun]))
        XCTAssertGreaterThan(oversizedData.count, PersonalInkEvaluationStore.maximumJournalByteCount)
        try oversizedData.write(to: url)
        store = PersonalInkEvaluationStore(url: url)
        XCTAssertNotNil(store.snapshot().error)
        XCTAssertTrue(store.snapshot().journal.runs.isEmpty)
        try fails { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections,
                                profile: .init(), pipeline: "test", completion: $0) }
        XCTAssertEqual(try Data(contentsOf: url), oversizedData)
    }

    func testOlderJournalDecodesWithoutPersonalEvidenceAndKeepsOldScores() throws {
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                          pipeline: "old", profile: .init())
        var r = record("old", baseline: "C", personalized: "G"); r.intended = "C"
        run.records = [r]; run.status = .complete; run.expectedChordCount = 1
        let data = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [run]))
        let restored = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: data).runs[0]
        XCTAssertNil(restored.records[0].personalSuggestion)
        XCTAssertNil(restored.records[0].personalArbitration)
        XCTAssertNil(restored.records[0].sourceRequestID)
        XCTAssertNil(restored.records[0].targetOrdinal)
        XCTAssertNil(restored.sourceRequestID)
        XCTAssertNil(restored.sourceInkRevision)
        XCTAssertNil(restored.sourceCaptureState)
        XCTAssertNil(restored.sourceSnapshot)
        XCTAssertEqual(restored.baselineCorrect, 1)
        XCTAssertEqual(restored.personalizedCorrect, 0, "A new arbitration policy cannot rewrite historical scores")
    }

    func testPersonalEvidenceAndStableMeasureIDSurviveReload() throws {
        let id = try start(); var r = record("evidence")
        r.personalSuggestion = .init(text: "G", source: .symbols, distance: 0.02, supportingExampleCount: 2)
        r.personalArbitration = "protectedBaseline"; r.measureID = UUID(); r.visualOrder = 3.2
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        let saved = try XCTUnwrap(PersonalInkEvaluationStore(url: url).snapshot().journal.runs[0].records.first)
        XCTAssertEqual(saved.personalSuggestion, r.personalSuggestion)
        XCTAssertEqual(saved.personalArbitration, r.personalArbitration)
        XCTAssertEqual(saved.measureID, r.measureID)
        XCTAssertEqual(saved.visualOrder, r.visualOrder)
    }

    func testBatchTeachingIsExplicitIdempotentAndExcludesGroupingFailures() throws {
        let profile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let id = try start()
        let records = [record("one"), record("two"), record("merged")]
        store.capture(runID: id, records: records)
        try fails { store.teachLabeledExamples(runID: id, profileStore: profile, completion: $0) }
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: records[0].id, text: "A", groupingIssue: false, completion: $0) }
        try succeed { store.label(runID: id, recordID: records[1].id, text: "A", groupingIssue: false, completion: $0) }
        try succeed { store.label(runID: id, recordID: records[2].id, text: nil, groupingIssue: true, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 4, slowInk: false, unexpectedChanges: false, completion: $0) }
        let oldProfile = try JSONEncoder().encode(run(id).profile)
        let oldPredictions = run(id).records.map(\.personalized)
        try succeed { store.teachLabeledExamples(runID: id, profileStore: profile, completion: $0) }
        XCTAssertEqual(run(id).records.map(\.taught), [true, true, false])
        XCTAssertTrue(run(id).teachableRecords.isEmpty)
        XCTAssertEqual(profile.snapshot().profile.examples.count, 1, "Identical examples cannot create duplicate weight")
        XCTAssertEqual(profile.snapshot().profile.examples[0].source, .explicitCorrection)
        let receipt = try XCTUnwrap(run(id).teachingReceipt)
        XCTAssertEqual(receipt.taughtRecordIDs, Array(records.prefix(2)).map(\.id))
        XCTAssertEqual(receipt.previousExampleCount, 0)
        XCTAssertEqual(receipt.savedExampleCount, 1)
        let reloadedProfile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        XCTAssertEqual(receipt.profileRevision, reloadedProfile.snapshot().profile.revision)
        XCTAssertEqual(PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first?.teachingReceipt, receipt)
        XCTAssertEqual(run(id).profile.revision, try JSONDecoder().decode(PersonalInkProfile.self, from: oldProfile).revision)
        XCTAssertEqual(run(id).records.map(\.personalized), oldPredictions)
        try succeed { store.teachLabeledExamples(runID: id, profileStore: profile, completion: $0) }
        XCTAssertEqual(profile.snapshot().profile.examples.count, 1)
        XCTAssertEqual(run(id).teachingReceipt, receipt, "A no-op retry must retain the actual save receipt")
    }

    func testAfterCorrectionsRequiresPersistedExplicitLearningNotJustPhaseOrRevision() throws {
        let profile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let id = try start(profile: profile.snapshot().profile)
        let r = record("one")
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: "A", groupingIssue: false, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
        func after(_ completion: @escaping (String?) -> Void) {
            store.start(chartID: UUID(), style: "rhythmSectionSheet", phase: .afterCorrections,
                        profile: profile.snapshot().profile, pipeline: "test", completion: completion)
        }
        try fails(after)
        try profile.update { $0.isEnabled = true }
        try fails(after)
        try profile.update { try $0.learn(strokes: r.strokes, label: "A", kind: .chord, source: .setup) }
        try fails(after)
        try succeed { store.teachLabeledExamples(runID: id, profileStore: profile, completion: $0) }
        XCTAssertTrue(store.snapshot().journal.hasCorrectionsSinceBaseline(profile: profile.snapshot().profile))
        try succeed(after)
        XCTAssertEqual(store.snapshot().journal.activeRun?.profile.revision, run(id).teachingReceipt?.profileRevision)
        var reset = profile.snapshot().profile; reset.generation = UUID()
        XCTAssertFalse(store.snapshot().journal.hasCorrectionsSinceBaseline(profile: reset))
        var disabled = profile.snapshot().profile; disabled.isEnabled = false
        XCTAssertFalse(store.snapshot().journal.hasCorrectionsSinceBaseline(profile: disabled))
    }

    func testFailedProfileSaveDoesNotAcknowledgeTeachingAndCanBeRetried() throws {
        let id = try start(); let r = record("one")
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: "A", groupingIssue: false, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
        let notFolder = folder.appendingPathComponent("not-a-folder")
        try Data("test fixture".utf8).write(to: notFolder)
        let unavailable = PersonalInkProfileStore(url: notFolder.appendingPathComponent("profile.json"))
        try fails { store.teachLabeledExamples(runID: id, profileStore: unavailable, completion: $0) }
        XCTAssertNil(run(id).teachingReceipt)
        XCTAssertEqual(run(id).records.map(\.taught), [false])
        XCTAssertTrue(unavailable.snapshot().profile.examples.isEmpty)
        let available = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try succeed { store.teachLabeledExamples(runID: id, profileStore: available, completion: $0) }
        XCTAssertNotNil(run(id).teachingReceipt)
        XCTAssertEqual(run(id).records.map(\.taught), [true])
    }

    func testAnotherActiveRunBlocksBatchTeachingFromACompletedRun() throws {
        let profile = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let id = try start(); let r = record("one")
        store.capture(runID: id, records: [r])
        try succeed { store.stop(runID: id, completion: $0) }
        try succeed { store.label(runID: id, recordID: r.id, text: "A", groupingIssue: false, completion: $0) }
        try succeed { store.finish(runID: id, expectedCount: 1, slowInk: false, unexpectedChanges: false, completion: $0) }
        _ = try start()
        try fails { store.teachLabeledExamples(runID: id, profileStore: profile, completion: $0) }
        XCTAssertTrue(profile.snapshot().profile.examples.isEmpty)
    }

    func testWholeSourceExactMappingRoundTripsWithoutChangingFrozenProfile() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        let id = try start(profile: profile)
        let frozenProfile = run(id).profile
        let frozenLineage = run(id).profileLineage
        let requestID = UUID()
        let source = try sourceSnapshot(
            requestID: requestID,
            inkRevision: 7,
            targetGroups: [[0, 2], [1]]
        )
        store.beginSourceCapture(runID: id, requestID: requestID, inkRevision: 7)
        store.captureSource(runID: id, snapshot: source, expectsPredictions: true)
        let records = [
            sourceRecord(source, targetOrdinal: 0, fingerprint: "source-0"),
            sourceRecord(source, targetOrdinal: 1, fingerprint: "source-1")
        ]
        store.capture(runID: id, records: records, sourceRequestID: requestID)
        try succeed { store.stop(runID: id, completion: $0) }

        let saved = run(id)
        XCTAssertEqual(saved.sourceCaptureState, .complete)
        XCTAssertEqual(saved.sourceRequestID, requestID)
        XCTAssertEqual(saved.sourceInkRevision, 7)
        XCTAssertEqual(saved.sourceSnapshot, source)
        XCTAssertEqual(saved.records.map(\.targetOrdinal), [0, 1])
        XCTAssertEqual(saved.records.map(\.recognitionStrokes), [
            source.recognitionStrokes(forTargetOrdinal: 0),
            source.recognitionStrokes(forTargetOrdinal: 1)
        ])
        XCTAssertEqual(saved.snapshotCount, 1)
        XCTAssertEqual(saved.profile, frozenProfile)
        XCTAssertEqual(saved.profileLineage, frozenLineage)

        let canonical = try ChordInkCanonicalTrajectoryPacket(
            strokes: source.visibleStrokes
        ).canonicalData()
        XCTAssertEqual(source.canonicalVisibleTrajectoryData, canonical)
        XCTAssertEqual(
            try ChordInkCanonicalTrajectoryPacket.decodeCanonicalData(canonical)
                .preparedStrokes(),
            source.visibleStrokes
        )
        let reloaded = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(reloaded.sourceSnapshot, source)
        XCTAssertEqual(reloaded.records, saved.records)
        XCTAssertEqual(reloaded.profile, frozenProfile)
    }

    func testSourceDescriptorRoundTripPreservesLayoutOrderAndRepeatedTargetRouting() throws {
        let repeatedTargetID = UUID()
        let firstVisualID = UUID()
        let secondVisualID = UUID()
        let measures = [
            PersonalInkEvaluationSourceSnapshot.Measure(
                measureID: firstVisualID,
                targetMeasureID: repeatedTargetID,
                index: 8,
                chordWritingFrame: CGRect(x: -12, y: 20, width: 100, height: 30)
            ),
            PersonalInkEvaluationSourceSnapshot.Measure(
                measureID: secondVisualID,
                targetMeasureID: repeatedTargetID,
                index: 2,
                chordWritingFrame: CGRect(x: 90, y: 20, width: 100, height: 30)
            )
        ]
        let source = try sourceSnapshot(targetGroups: [], measures: measures)
        let decoded = try JSONDecoder().decode(
            PersonalInkEvaluationSourceSnapshot.self,
            from: JSONEncoder().encode(source)
        )
        XCTAssertEqual(decoded.measures.map(\.measureID), [firstVisualID, secondVisualID])
        XCTAssertEqual(decoded.measures.map(\.targetMeasureID), [repeatedTargetID, repeatedTargetID])
        XCTAssertEqual(decoded.measures.map(\.index), [8, 2])
        XCTAssertEqual(decoded, source)
    }

    func testTargetlessSourceCompletesWithoutPredictionRecords() throws {
        let id = try start()
        let requestID = UUID()
        let source = try sourceSnapshot(
            requestID: requestID,
            inkRevision: 12,
            targetGroups: [],
            outcome: "noRecognitionData"
        )
        store.beginSourceCapture(runID: id, requestID: requestID, inkRevision: 12)
        store.captureSource(runID: id, expectsPredictions: false) { source }
        try succeed { store.stop(runID: id, completion: $0) }

        let saved = run(id)
        XCTAssertEqual(saved.status, .labeling)
        XCTAssertEqual(saved.sourceCaptureState, .complete)
        XCTAssertEqual(saved.sourceSnapshot, source)
        XCTAssertTrue(saved.records.isEmpty)
        XCTAssertEqual(saved.snapshotCount, 1)
    }

    func testPendingSourcePreventsStopWithReturnToChordsGuidance() throws {
        let id = try start()
        let requestID = UUID()
        store.beginSourceCapture(runID: id, requestID: requestID, inkRevision: 3)
        let message = try rejection { store.stop(runID: id, completion: $0) }
        XCTAssertTrue(message.contains("return to Chords"))
        XCTAssertEqual(run(id).status, .capturing)
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)
        XCTAssertTrue(run(id).records.isEmpty)
        XCTAssertEqual(run(id).snapshotCount, 0)
    }

    func testRepeatedPendingCaptureKeepsLatestInMemoryUntilDurableCancel() throws {
        let id = try start()
        let firstRequestID = UUID()
        let latestRequestID = UUID()
        store.beginSourceCapture(runID: id, requestID: firstRequestID, inkRevision: 20)
        waitUntil {
            self.run(id).sourceRequestID == firstRequestID
                && self.run(id).sourceCaptureState == .pendingPreparation
        }
        XCTAssertNil(store.snapshot().error)

        let firstDurable = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(firstDurable.sourceRequestID, firstRequestID)
        XCTAssertEqual(firstDurable.sourceInkRevision, 20)
        XCTAssertEqual(firstDurable.sourceCaptureState, .pendingPreparation)

        store.beginSourceCapture(runID: id, requestID: latestRequestID, inkRevision: 21)
        waitUntil {
            self.run(id).sourceRequestID == latestRequestID
                && self.run(id).sourceInkRevision == 21
        }
        XCTAssertEqual(run(id).sourceRequestID, latestRequestID)
        XCTAssertEqual(run(id).sourceInkRevision, 21)
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)

        let stillFirstDurable = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(stillFirstDurable.sourceRequestID, firstRequestID)
        XCTAssertEqual(stillFirstDurable.sourceInkRevision, 20)

        _ = try rejection { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).sourceRequestID, latestRequestID)
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)

        try succeed { store.cancel(runID: id, completion: $0) }
        let cancelled = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(cancelled.sourceRequestID, latestRequestID)
        XCTAssertEqual(cancelled.sourceInkRevision, 21)
        XCTAssertEqual(cancelled.sourceCaptureState, .pendingPreparation)
    }

    func testLatestSourceRequestRejectsStaleRunAndRevisionCallbacks() throws {
        let id = try start()
        let staleRequestID = UUID()
        let latestRequestID = UUID()
        let stale = try sourceSnapshot(
            requestID: staleRequestID,
            inkRevision: 1,
            targetGroups: []
        )
        let latest = try sourceSnapshot(
            requestID: latestRequestID,
            inkRevision: 2,
            targetGroups: []
        )
        store.beginSourceCapture(runID: id, requestID: staleRequestID, inkRevision: 1)
        store.beginSourceCapture(runID: id, requestID: latestRequestID, inkRevision: 2)
        store.captureSource(runID: UUID(), snapshot: latest, expectsPredictions: false)
        store.captureSource(runID: id, snapshot: stale, expectsPredictions: false)
        _ = try rejection { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).sourceRequestID, latestRequestID)
        XCTAssertEqual(run(id).sourceInkRevision, 2)
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)
        XCTAssertNil(run(id).sourceSnapshot)

        store.captureSource(runID: id, snapshot: latest, expectsPredictions: false)
        try succeed { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).sourceSnapshot?.requestID, latestRequestID)
        XCTAssertEqual(run(id).snapshotCount, 1)
    }

    func testLatestCoalescedSourceAndMappedRecordsBecomeDurableTogether() throws {
        let id = try start()
        let firstRequestID = UUID()
        let latestRequestID = UUID()
        store.beginSourceCapture(runID: id, requestID: firstRequestID, inkRevision: 30)
        store.beginSourceCapture(runID: id, requestID: latestRequestID, inkRevision: 31)
        let source = try sourceSnapshot(
            requestID: latestRequestID,
            inkRevision: 31,
            targetGroups: [[0, 2], [1]]
        )
        store.captureSource(runID: id, snapshot: source, expectsPredictions: true)
        store.capture(runID: id, records: [
            sourceRecord(source, targetOrdinal: 0, fingerprint: "durable-0"),
            sourceRecord(source, targetOrdinal: 1, fingerprint: "durable-1")
        ], sourceRequestID: latestRequestID)
        try succeed { store.stop(runID: id, completion: $0) }

        let durable = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(durable.sourceRequestID, latestRequestID)
        XCTAssertEqual(durable.sourceInkRevision, 31)
        XCTAssertEqual(durable.sourceCaptureState, .complete)
        XCTAssertEqual(durable.sourceSnapshot, source)
        XCTAssertEqual(durable.records.map(\.targetOrdinal), [0, 1])
        XCTAssertEqual(durable.snapshotCount, 1)
    }

    func testInvalidLatestSourceCannotAcknowledgePendingCapture() throws {
        let id = try start()
        let requestID = UUID()
        var invalid = try sourceSnapshot(
            requestID: requestID,
            inkRevision: 40,
            targetGroups: []
        )
        invalid.normalizedDrawingData = Data()
        store.beginSourceCapture(runID: id, requestID: requestID, inkRevision: 40)
        store.captureSource(runID: id, snapshot: invalid, expectsPredictions: false)
        _ = try rejection { store.stop(runID: id, completion: $0) }

        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)
        XCTAssertNil(run(id).sourceSnapshot)
        XCTAssertTrue(run(id).records.isEmpty)
        XCTAssertEqual(run(id).snapshotCount, 0)
        let durable = try XCTUnwrap(
            PersonalInkEvaluationStore(url: url).snapshot().journal.runs.first
        )
        XCTAssertEqual(durable.sourceCaptureState, .pendingPreparation)
        XCTAssertNil(durable.sourceSnapshot)
    }

    func testFailedFirstPendingWriteStillInvalidatesCachedCompleteSource() throws {
        let id = try start()
        let completedRequestID = UUID()
        let completedSource = try sourceSnapshot(
            requestID: completedRequestID,
            inkRevision: 50,
            targetGroups: []
        )
        store.beginSourceCapture(
            runID: id,
            requestID: completedRequestID,
            inkRevision: 50
        )
        store.captureSource(
            runID: id,
            snapshot: completedSource,
            expectsPredictions: false
        )
        try fails {
            store.finish(
                runID: id,
                expectedCount: 1,
                slowInk: false,
                unexpectedChanges: false,
                completion: $0
            )
        }
        XCTAssertEqual(run(id).sourceCaptureState, .complete)
        XCTAssertEqual(run(id).sourceSnapshot, completedSource)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let pendingRequestID = UUID()
        let pendingSource = try sourceSnapshot(
            requestID: pendingRequestID,
            inkRevision: 51,
            targetGroups: []
        )
        store.beginSourceCapture(
            runID: id,
            requestID: pendingRequestID,
            inkRevision: 51
        )
        store.captureSource(
            runID: id,
            snapshot: pendingSource,
            expectsPredictions: false
        )
        let cancelFailure = try rejection {
            store.cancel(runID: id, completion: $0)
        }

        let cached = run(id)
        XCTAssertEqual(cached.status, .capturing)
        XCTAssertEqual(cached.sourceRequestID, pendingRequestID)
        XCTAssertEqual(cached.sourceInkRevision, 51)
        XCTAssertEqual(cached.sourceCaptureState, .pendingPreparation)
        XCTAssertNil(cached.sourceSnapshot)
        XCTAssertTrue(cached.records.isEmpty)
        XCTAssertEqual(cached.snapshotCount, 1)
        XCTAssertEqual(store.snapshot().error, cancelFailure)

        let retryRequestID = UUID()
        store.beginSourceCapture(
            runID: id,
            requestID: retryRequestID,
            inkRevision: 52
        )
        waitUntil {
            self.run(id).sourceRequestID == retryRequestID
                && self.run(id).sourceInkRevision == 52
        }
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)
        XCTAssertNil(run(id).sourceSnapshot)
        XCTAssertNotNil(store.snapshot().error)

        let stopFailure = try rejection { store.stop(runID: id, completion: $0) }
        XCTAssertTrue(stopFailure.contains("return to Chords"))
        XCTAssertEqual(run(id).status, .capturing)
        XCTAssertEqual(run(id).sourceCaptureState, .pendingPreparation)
        XCTAssertNil(run(id).sourceSnapshot)
    }

    func testDamagedSourceRecordMappingIsRejectedAtomicallyAndCanRetry() throws {
        let id = try start()
        let requestID = UUID()
        let source = try sourceSnapshot(
            requestID: requestID,
            inkRevision: 4,
            targetGroups: [[0, 2], [1]]
        )
        store.beginSourceCapture(runID: id, requestID: requestID, inkRevision: 4)
        store.captureSource(runID: id, snapshot: source, expectsPredictions: true)
        var damaged = sourceRecord(source, targetOrdinal: 0, fingerprint: "damaged")
        damaged.recognitionStrokes = [source.visibleStrokes[1]]
        let other = sourceRecord(source, targetOrdinal: 1, fingerprint: "other")
        store.capture(
            runID: id,
            records: [damaged, other],
            sourceRequestID: requestID
        )
        _ = try rejection { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).sourceCaptureState, .awaitingPredictions)
        XCTAssertTrue(run(id).records.isEmpty)
        XCTAssertEqual(run(id).snapshotCount, 0)

        store.capture(runID: id, records: [
            sourceRecord(source, targetOrdinal: 0, fingerprint: "fixed-0"),
            sourceRecord(source, targetOrdinal: 1, fingerprint: "fixed-1")
        ], sourceRequestID: requestID)
        try succeed { store.stop(runID: id, completion: $0) }
        XCTAssertEqual(run(id).sourceCaptureState, .complete)
        XCTAssertEqual(run(id).records.count, 2)
        XCTAssertEqual(run(id).snapshotCount, 1)
    }

    func testSourceBoundsAndCanonicalCopyRejectDamageInsteadOfTruncating() throws {
        let finiteDot = InkStroke(points: [
            InkPoint(x: -0.0, y: -4, timeOffset: -0.25)
        ], creationTimeOffset: -2)
        let finiteDotSource = try sourceSnapshot(
            targetGroups: [[0]],
            visibleStrokes: [finiteDot]
        )
        XCTAssertEqual(finiteDotSource.visibleStrokes, [finiteDot])
        XCTAssertEqual(finiteDotSource.recognitionStrokes, [finiteDot])

        XCTAssertThrowsError(try sourceSnapshot(
            targetGroups: [],
            normalizedDrawingData: Data(
                repeating: 0x1,
                count: PersonalInkEvaluationSourceSnapshot.maximumDrawingByteCount + 1
            )
        ))
        let onePointStroke = InkStroke(points: [InkPoint(x: 0, y: 0)])
        XCTAssertThrowsError(try sourceSnapshot(
            targetGroups: [],
            visibleStrokes: Array(
                repeating: onePointStroke,
                count: PersonalInkEvaluationSourceSnapshot.maximumVisibleStrokeCount + 1
            )
        ))
        XCTAssertThrowsError(try sourceSnapshot(
            targetGroups: [],
            visibleStrokes: [InkStroke(points: Array(
                repeating: InkPoint(x: 0, y: 0),
                count: PersonalInkEvaluationSourceSnapshot.maximumPointCount + 1
            ))]
        ))
        let tooManyTargetStrokes = Array(repeating: onePointStroke, count: 65)
        XCTAssertThrowsError(try sourceSnapshot(
            targetGroups: tooManyTargetStrokes.indices.map { [$0] },
            visibleStrokes: tooManyTargetStrokes
        ))

        var damagedOwnership = try sourceSnapshot(targetGroups: [])
        damagedOwnership.ownership.unassignedVisibleFragmentIndices = []
        XCTAssertThrowsError(try damagedOwnership.validate())

        var damagedCanonical = try sourceSnapshot(targetGroups: [])
        damagedCanonical.canonicalVisibleTrajectoryData.append(0x0a)
        XCTAssertThrowsError(try damagedCanonical.validate())

        XCTAssertThrowsError(try sourceSnapshot(targetGroups: [], outcome: "ready"))
        XCTAssertThrowsError(try sourceSnapshot(targetGroups: [[0]], outcome: "noTarget"))
    }

    private func historicalRuns(count: Int) throws -> [PersonalInkEvaluationRun] {
        try (0..<count).map { index in
            var profile = PersonalInkProfile()
            profile.isEnabled = index.isMultiple(of: 2)
            try profile.learn(strokes: record("support-\(index)").strokes,
                              label: "C", kind: .chord, source: .setup)
            var saved = PersonalInkEvaluationRun(chartID: UUID(),
                style: index.isMultiple(of: 2) ? "simpleChordSheet" : "rhythmSectionSheet",
                phase: .beforeCorrections, pipeline: "saved-pipeline-\(index)", profile: profile)
            saved.startedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            saved.finishedAt = saved.startedAt.addingTimeInterval(10)
            saved.status = index.isMultiple(of: 2) ? .complete : .cancelled
            saved.expectedChordCount = index.isMultiple(of: 2) ? 2 : nil
            saved.inkFeltSlow = index.isMultiple(of: 3)
            saved.unexpectedChartChanges = index.isMultiple(of: 5)
            saved.snapshotCount = index + 1
            saved.profileLineage = .init(profile: profile, querySessionID: saved.id)
            let source = try sourceSnapshot(inkRevision: UInt64(index + 1),
                targetGroups: [[0, 2], [1]], normalizedDrawingData: Data([0x1, UInt8(index), 0x3]))
            saved.sourceRequestID = source.requestID
            saved.sourceInkRevision = source.inkRevision
            saved.sourceCaptureState = .complete
            saved.sourceSnapshot = source
            saved.records = (0..<2).map { ordinal in
                var r = sourceRecord(source, targetOrdinal: ordinal, fingerprint: "saved-\(index)-\(ordinal)")
                if saved.status == .complete { r.intended = "C" }
                return r
            }
            return saved
        }
    }

    private func start(profile: PersonalInkProfile = .init()) throws -> UUID {
        try succeed { store.start(chartID: chartID, style: "simpleChordSheet", phase: .beforeCorrections, profile: profile, pipeline: "test-pipeline", completion: $0) }
        return try XCTUnwrap(store.snapshot().journal.activeRun?.id)
    }
    private func run(_ id: UUID) -> PersonalInkEvaluationRun { store.snapshot().journal.runs.first { $0.id == id }! }
    private func record(_ fingerprint: String, baseline: String? = "C", personalized: String? = "C") -> PersonalInkEvaluationRecord {
        .init(measureIndex: 0, fraction: 0, strokes: [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 20)])],
              fingerprint: fingerprint, baseline: baseline, personalized: personalized, baselineAction: "confirm", personalizedAction: "confirm",
              knownInk: false, recognitionMilliseconds: 12, totalMilliseconds: 150, cacheHit: false)
    }
    private func sourceSnapshot(
        requestID: UUID = UUID(),
        inkRevision: UInt64 = 1,
        targetGroups: [[Int]],
        normalizedDrawingData: Data = Data([0x1, 0x2, 0x3]),
        outcome: String? = nil,
        measures: [PersonalInkEvaluationSourceSnapshot.Measure]? = nil,
        visibleStrokes suppliedVisibleStrokes: [InkStroke]? = nil
    ) throws -> PersonalInkEvaluationSourceSnapshot {
        let defaultVisibleStrokes = [
            InkStroke(points: [
                InkPoint(x: -20, y: 10, timeOffset: -0.2),
                InkPoint(x: -10, y: 20, timeOffset: 0.1)
            ], creationTimeOffset: -1),
            InkStroke(points: [
                InkPoint(x: 20, y: 15, timeOffset: nil),
                InkPoint(x: 30, y: 25, timeOffset: 0.3)
            ], creationTimeOffset: 0),
            InkStroke(points: [
                InkPoint(x: 50, y: 5, timeOffset: 0),
                InkPoint(x: 60, y: 35, timeOffset: 0.4)
            ], creationTimeOffset: 0.5)
        ]
        let visibleStrokes = suppliedVisibleStrokes ?? defaultVisibleStrokes
        let ownership = try XCTUnwrap(ChordInkTargetOwnershipSnapshot(
            sourcePencilStrokeCount: visibleStrokes.count,
            visibleFragmentSourceStrokeIndices: Array(visibleStrokes.indices),
            barlineVisibleFragmentIndices: [],
            targetVisibleFragmentIndices: targetGroups
        ))
        return try PersonalInkEvaluationSourceSnapshot(
            requestID: requestID,
            inkRevision: inkRevision,
            normalizedDrawingData: normalizedDrawingData,
            chordFrame: CGRect(x: -30, y: 0, width: 200, height: 60),
            pageBounds: CGRect(x: -40, y: -10, width: 300, height: 400),
            pages: [.init(index: 0, frame: CGRect(x: -40, y: -10, width: 300, height: 400))],
            measures: measures ?? [
                .init(measureID: UUID(), index: 0,
                      chordWritingFrame: CGRect(x: -30, y: 0, width: 200, height: 60))
            ],
            visibleStrokes: visibleStrokes,
            recognitionVisibleFragmentIndices: Array(visibleStrokes.indices),
            ownership: ownership,
            outcome: outcome ?? (targetGroups.isEmpty ? "noTarget" : "ready")
        )
    }
    private func sourceRecord(
        _ source: PersonalInkEvaluationSourceSnapshot,
        targetOrdinal: Int,
        fingerprint: String
    ) -> PersonalInkEvaluationRecord {
        var value = record(fingerprint)
        value.sourceRequestID = source.requestID
        value.targetOrdinal = targetOrdinal
        value.recognitionStrokes = source.recognitionStrokes(
            forTargetOrdinal: targetOrdinal
        )
        return value
    }
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition())
    }
    private func succeed(_ call: (@escaping (String?) -> Void) -> Void) throws {
        let done = expectation(description: "saved")
        call { error in XCTAssertNil(error); done.fulfill() }
        wait(for: [done], timeout: 3)
    }
    private func fails(_ call: (@escaping (String?) -> Void) -> Void) throws {
        let done = expectation(description: "rejected")
        call { error in XCTAssertNotNil(error); done.fulfill() }
        wait(for: [done], timeout: 3)
    }
    private func rejection(_ call: (@escaping (String?) -> Void) -> Void) throws -> String {
        let done = expectation(description: "rejected with message")
        var captured: String?
        call { error in captured = error; done.fulfill() }
        wait(for: [done], timeout: 3)
        return try XCTUnwrap(captured)
    }
}
