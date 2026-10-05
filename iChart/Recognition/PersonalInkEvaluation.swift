import Foundation
import CryptoKit

/// Evaluation data is local, opt-in, and never enters training automatically.
struct PersonalInkEvaluationRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var capturedAt = Date()
    var measureIndex: Int
    var fraction: Double
    var strokes: [InkStroke]
    var fingerprint: String
    var baseline: String?
    var personalized: String?
    var baselineAction: String
    var personalizedAction: String
    var knownInk: Bool
    var recognitionMilliseconds: Double
    var totalMilliseconds: Double
    var cacheHit: Bool
    var intended: String?
    var groupingIssue = false
    var taught = false
    // Additive v1 fields: older runs retain their original scores unchanged.
    var personalSuggestion: ChordInkPersonalSuggestion? = nil
    var personalArbitration: String? = nil
    var measureID: UUID? = nil
    var visualOrder: Double? = nil
    // Thumbnail geometry is scaled and may be decimated. Glyph clustering uses
    // page-space distances, so it is not an interchangeable recognition input.
    // New opt-in local captures retain exactly what recognition consumed. Older
    // journals still load; their missing exact input must remain visible.
    var recognitionStrokes: [InkStroke]? = nil
    /// Request-local context affects trust even when stroke geometry is cached.
    /// Nil denotes older captures made before edit continuity was introduced.
    var requiresEditReview: Bool? = nil
    /// Native evidence before the separate edit-review gate; needed to replay
    /// personalization without mistaking an edit for weak recognition evidence.
    var baselineRecognitionAction: String? = nil
    /// Present only when this target is bound to a retained whole-source
    /// preparation request. Legacy records intentionally decode as nil.
    var sourceRequestID: UUID? = nil
    var targetOrdinal: Int? = nil

    var recognitionInput: [InkStroke] { recognitionStrokes ?? strokes }

    var baselineEvidenceIsTrusted: Bool? {
        // Older edited captures cannot reconstruct this input from the gated
        // action alone. Leave it unknown instead of inventing an untrusted read.
        guard let action = baselineRecognitionAction ?? (requiresEditReview == true ? nil : baselineAction),
              ["trusted", "confirm", "reject"].contains(action) else { return nil }
        return action == "trusted"
    }

    var isWithinStorageBounds: Bool {
        strokes.count <= 64 && strokes.reduce(0, { $0 + $1.points.count }) <= 8_256 &&
        (recognitionStrokes.map { $0.count <= 64 && $0.reduce(0, { $0 + $1.points.count }) <= 32_768 } ?? true)
    }

    /// Re-delivering identical content is not a new observation. Recognition,
    /// placement and timing changes still matter even when the ink is identical.
    func hasSameCapturedContent(as other: Self) -> Bool {
        var comparable = other
        comparable.id = id
        comparable.capturedAt = capturedAt
        return self == comparable
    }
}

struct PersonalInkTeachingReceipt: Codable, Equatable {
    var savedAt = Date()
    let taughtRecordIDs: [UUID]
    let profileRevision: UUID
    let profileGeneration: UUID
    let previousExampleCount: Int
    let savedExampleCount: Int
}

struct PersonalInkEvaluationRun: Codable, Identifiable {
    enum Phase: String, Codable, CaseIterable { case beforeCorrections, afterCorrections }
    enum Status: String, Codable { case capturing, labeling, complete, cancelled }
    enum SourceCaptureState: String, Codable {
        case pendingPreparation
        case awaitingPredictions
        case complete
    }
    var id = UUID()
    var startedAt = Date()
    var finishedAt: Date?
    var chartID: UUID
    var style: String
    var phase: Phase
    var pipeline: String
    var profile: PersonalInkProfile
    var status: Status = .capturing
    var records: [PersonalInkEvaluationRecord] = []
    var expectedChordCount: Int?
    var inkFeltSlow: Bool?
    var unexpectedChartChanges: Bool?
    var snapshotCount = 0
    // Optional so journals from before save receipts keep their original data.
    var teachingReceipt: PersonalInkTeachingReceipt? = nil
    // Frozen only at new-run start. Old journals retain unknown lineage; later
    // teaching must not rewrite the support metadata of a completed comparison.
    var profileLineage: PersonalInkProfileLineageSummary? = nil
    // Additive whole-source evidence. All four values remain nil for journals
    // and runs created before source capture was introduced.
    var sourceRequestID: UUID? = nil
    var sourceInkRevision: UInt64? = nil
    var sourceCaptureState: SourceCaptureState? = nil
    var sourceSnapshot: PersonalInkEvaluationSourceSnapshot? = nil

    var scoreable: [PersonalInkEvaluationRecord] {
        records.filter { $0.intended != nil && !$0.groupingIssue && !$0.knownInk }
    }
    var teachableRecords: [PersonalInkEvaluationRecord] {
        records.filter { $0.intended != nil && !$0.groupingIssue && !$0.taught }
    }
    var baselineCorrect: Int { scoreable.filter { $0.baseline == $0.intended }.count }
    var personalizedCorrect: Int { scoreable.filter { $0.personalized == $0.intended }.count }
    var improvements: Int { scoreable.filter { $0.baseline != $0.intended && $0.personalized == $0.intended }.count }
    var regressions: Int { scoreable.filter { $0.baseline == $0.intended && $0.personalized != $0.intended }.count }
    var baselineNoReads: Int { scoreable.filter { $0.baseline == nil }.count }
    var personalizedNoReads: Int { scoreable.filter { $0.personalized == nil }.count }
    var missingCount: Int { max(0, (expectedChordCount ?? 0) - records.count) }
    // A merged/split target cannot be treated as one intended chord. Preserve
    // the problem, but withhold a misleading whole-chart percentage.
    var wholeChartScoreAvailable: Bool {
        expectedChordCount != nil && expectedChordCount! >= records.count &&
        records.allSatisfy { $0.intended != nil && !$0.groupingIssue && !$0.knownInk }
    }

    var sourceCaptureIsWithinStorageBounds: Bool {
        let hasAnySourceMetadata = sourceRequestID != nil || sourceInkRevision != nil
            || sourceCaptureState != nil || sourceSnapshot != nil
        guard hasAnySourceMetadata else {
            return records.allSatisfy { $0.sourceRequestID == nil && $0.targetOrdinal == nil }
        }
        guard let sourceRequestID, let sourceInkRevision, let sourceCaptureState else {
            return false
        }
        if let sourceSnapshot {
            guard sourceSnapshot.requestID == sourceRequestID,
                  sourceSnapshot.inkRevision == sourceInkRevision,
                  (try? sourceSnapshot.validate()) != nil else {
                return false
            }
        }
        if sourceCaptureState != .complete,
           status != .capturing && status != .cancelled {
            return false
        }
        switch sourceCaptureState {
        case .pendingPreparation:
            return sourceSnapshot == nil && records.isEmpty
        case .awaitingPredictions:
            return sourceSnapshot?.ownership.targetGroups.isEmpty == false && records.isEmpty
        case .complete:
            guard let sourceSnapshot else { return false }
            if sourceSnapshot.ownership.targetGroups.isEmpty {
                return records.isEmpty
            }
            return recordsMatchSourceCapture(records, snapshot: sourceSnapshot)
        }
    }

    func recordsMatchSourceCapture(
        _ candidate: [PersonalInkEvaluationRecord],
        snapshot: PersonalInkEvaluationSourceSnapshot
    ) -> Bool {
        guard let sourceRequestID,
              snapshot.requestID == sourceRequestID,
              candidate.count == snapshot.ownership.targetGroups.count else {
            return false
        }
        return zip(candidate, snapshot.ownership.targetGroups).allSatisfy { record, group in
            record.sourceRequestID == sourceRequestID
                && record.targetOrdinal == group.targetOrdinal
                && record.recognitionStrokes
                    == snapshot.recognitionStrokes(forTargetOrdinal: group.targetOrdinal)
        }
    }
}

struct PersonalInkEvaluationJournal: Codable {
    var version = 1
    var runs: [PersonalInkEvaluationRun] = []
    var activeRun: PersonalInkEvaluationRun? { runs.first { $0.status == .capturing } }

    /// A phase label is not evidence of learning. Require a new explicitly
    /// taught symbol or whole-chord correction since a completed baseline in
    /// this profile's lifetime. Keep the historical phase names in saved data;
    /// source upgrades, duplicate ink and administrative changes do not qualify.
    func hasCorrectionsSinceBaseline(profile: PersonalInkProfile) -> Bool {
        guard profile.isEnabled else { return false }
        return runs.contains { run in
            guard run.status == .complete, run.phase == .beforeCorrections,
                  run.profile.generation == profile.generation else { return false }
            return profile.examples.contains { example in
                guard example.hasValidRecognitionInput else { return false }
                switch (example.kind, example.source) {
                case (.chord, .explicitCorrection):
                    guard ChordRecognitionCompendium.match(example.label) != nil else { return false }
                case (.glyph, .setup), (.glyph, .explicitCorrection):
                    guard PersonalInkProfile.glyphLabels.contains(example.label) else { return false }
                default:
                    return false
                }
                return !run.profile.containsExactLesson(
                    strokes: example.recognitionInput, label: example.label, kind: example.kind
                )
            }
        }
    }
}

struct PersonalInkEvaluationContext {
    let runID: UUID
    let profile: PersonalInkSnapshot
}

struct PersonalInkEvaluationPrediction {
    let runID: UUID
    let baseline: String?
    let personalized: String?
    let baselineAction: String
    let personalizedAction: String
    let knownInk: Bool
    var personalSuggestion: ChordInkPersonalSuggestion? = nil
    var personalArbitration: String? = nil
    var baselineRecognitionAction: String? = nil
}

enum PersonalInkEvaluationError: LocalizedError {
    case unavailable, activeRun, invalidCount, incompleteLabels, full, noActiveRun,
         noSavedCorrections, sourceCapturePending
    var errorDescription: String? {
        switch self {
        case .unavailable: return "The saved test data could not be read or saved. Existing files were kept; do not reset your profile."
        case .activeRun: return "Stop the active chart test before changing or teaching the profile."
        case .invalidCount: return "Enter how many complete chords you wrote (1–64)."
        case .incompleteLabels: return "Label each captured chord, or mark it as incorrectly grouped, before finishing."
        case .full: return "This local test journal is full. Keep the saved results and ask for them to be collected before another pass."
        case .noActiveRun: return "This test is no longer capturing. Start a new test for new ink."
        case .noSavedCorrections: return "No new learning is saved since a completed Before learning test. Save a new setup symbol, teach a selected symbol, or explicitly correct a whole chord. Then start an After learning test with fresh ink. Selecting a phase or saving the same example again does not teach anything new."
        case .sourceCapturePending: return "Handwriting capture is still preparing or waiting for recognition. Wait for it to finish, or return to Chords and cancel this test."
        }
    }
}

/// Writes run on one background queue. The short state lock never covers disk
/// access or feature extraction, so PencilKit and chart reads cannot wait on IO.
final class PersonalInkEvaluationStore: @unchecked Sendable {
    // Retain the collected history when extending an evaluation session. This
    // is a run-count bound, not permission to exceed the existing byte budget;
    // full journals still fail closed instead of silently evicting evidence.
    static let maximumRuns = 32
    static let maximumJournalByteCount = 24_000_000
    static let shared = PersonalInkEvaluationStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PersonalHandwriting/evaluation-v1.json"))
    private let url: URL
    private let queue = DispatchQueue(label: "com.ichart.personal-evaluation", qos: .utility)
    private let lock = NSLock()
    private var journal = PersonalInkEvaluationJournal()
    private var frozen: PersonalInkEvaluationContext?
    private var failure: String?
    private var unreadable = false

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumJournalByteCount else { throw PersonalInkEvaluationError.unavailable }
            let loaded = try JSONDecoder().decode(PersonalInkEvaluationJournal.self, from: data)
            guard loaded.version == 1, loaded.runs.count <= Self.maximumRuns,
                  loaded.runs.filter({ $0.status == .capturing }).count <= 1,
                  loaded.runs.allSatisfy({ run in
                      run.records.count <= 64 && run.profile.examples.count <= PersonalInkProfile.maximumExamples &&
                      run.records.allSatisfy(\.isWithinStorageBounds) &&
                      run.sourceCaptureIsWithinStorageBounds
                  }) else { throw PersonalInkEvaluationError.unavailable }
            journal = loaded
            if let run = loaded.activeRun { frozen = .init(runID: run.id, profile: PersonalInkSnapshot(profile: run.profile)) }
        } catch { unreadable = true; failure = PersonalInkEvaluationError.unavailable.localizedDescription }
    }

    func snapshot() -> (journal: PersonalInkEvaluationJournal, error: String?) {
        lock.lock(); defer { lock.unlock() }
        return (journal, failure)
    }

    func context(chartID: UUID) -> PersonalInkEvaluationContext? {
        lock.lock(); defer { lock.unlock() }
        guard journal.activeRun?.chartID == chartID else { return nil }
        return frozen
    }

    var isCapturing: Bool { snapshot().journal.activeRun != nil }

    func start(chartID: UUID, style: String, phase: PersonalInkEvaluationRun.Phase,
               profile: PersonalInkProfile, pipeline: String, completion: @escaping (String?) -> Void) {
        update({ journal in
            guard journal.activeRun == nil else { throw PersonalInkEvaluationError.activeRun }
            if phase == .afterCorrections && !journal.hasCorrectionsSinceBaseline(profile: profile) {
                throw PersonalInkEvaluationError.noSavedCorrections
            }
            guard journal.runs.count < Self.maximumRuns else { throw PersonalInkEvaluationError.full }
            var run = PersonalInkEvaluationRun(chartID: chartID, style: style, phase: phase,
                                              pipeline: pipeline, profile: profile)
            run.profileLineage = .init(profile: profile, querySessionID: run.id)
            journal.runs.append(run)
        }, completion: completion)
    }

    /// Marks the newest drawing revision before preparation is coalesced. A new
    /// request replaces only the active draft evidence; completed/cancelled runs
    /// and the run's frozen profile remain unchanged.
    func beginSourceCapture(runID: UUID, requestID: UUID, inkRevision: UInt64) {
        update({ journal in
            guard let index = journal.runs.firstIndex(where: {
                $0.id == runID && $0.status == .capturing
            }) else { return }
            journal.runs[index].records = []
            journal.runs[index].sourceRequestID = requestID
            journal.runs[index].sourceInkRevision = inkRevision
            journal.runs[index].sourceCaptureState = .pendingPreparation
            journal.runs[index].sourceSnapshot = nil
        }, shouldPersist: { before, after in
            guard self.snapshot().error == nil else {
                return true
            }
            guard let beforeRun = before.runs.first(where: {
                $0.id == runID && $0.status == .capturing
            }), beforeRun.sourceCaptureState == .pendingPreparation,
                  let afterRun = after.runs.first(where: {
                      $0.id == runID && $0.status == .capturing
                  }), afterRun.sourceCaptureState == .pendingPreparation else {
                return true
            }
            return false
        }, commitEditedStateOnPersistenceFailure: true)
    }

    func captureSource(
        runID: UUID,
        snapshot: PersonalInkEvaluationSourceSnapshot,
        expectsPredictions: Bool
    ) {
        captureSource(runID: runID, expectsPredictions: expectsPredictions) { snapshot }
    }

    /// Snapshot construction, validation, serialization and disk IO all execute
    /// on the store queue; a 65K-point source never needs to be built on the UI
    /// thread by this API.
    func captureSource(
        runID: UUID,
        expectsPredictions: Bool,
        makeSnapshot: @escaping () throws -> PersonalInkEvaluationSourceSnapshot
    ) {
        update({ journal in
            guard let index = journal.runs.firstIndex(where: {
                $0.id == runID && $0.status == .capturing
            }), journal.runs[index].sourceCaptureState == .pendingPreparation else {
                return
            }
            let snapshot = try makeSnapshot()
            guard journal.runs[index].sourceRequestID == snapshot.requestID,
                  journal.runs[index].sourceInkRevision == snapshot.inkRevision else {
                return
            }
            try snapshot.validate()
            if expectsPredictions {
                guard !snapshot.ownership.targetGroups.isEmpty else {
                    throw PersonalInkEvaluationSourceError.invalid
                }
                journal.runs[index].sourceSnapshot = snapshot
                journal.runs[index].sourceCaptureState = .awaitingPredictions
            } else {
                guard snapshot.ownership.targetGroups.isEmpty else {
                    throw PersonalInkEvaluationSourceError.invalid
                }
                journal.runs[index].sourceSnapshot = snapshot
                journal.runs[index].sourceCaptureState = .complete
                journal.runs[index].snapshotCount += 1
            }
        })
    }

    /// Replace the current draft snapshot, not append every partial stroke as
    /// another attempt. Labels are entered only after capture has been stopped.
    func capture(
        runID: UUID,
        records: [PersonalInkEvaluationRecord],
        sourceRequestID: UUID? = nil
    ) {
        capture(runID: runID, sourceRequestID: sourceRequestID, makeRecords: { records })
    }

    func capture(
        runID: UUID,
        sourceRequestID: UUID? = nil,
        makeRecords: @escaping () -> [PersonalInkEvaluationRecord]
    ) {
        update({ journal in
            guard let index = journal.runs.firstIndex(where: { $0.id == runID && $0.status == .capturing }) else { return }
            let sourceSnapshot: PersonalInkEvaluationSourceSnapshot?
            if let expectedRequestID = journal.runs[index].sourceRequestID {
                guard sourceRequestID == expectedRequestID,
                      journal.runs[index].sourceCaptureState == .awaitingPredictions,
                      let snapshot = journal.runs[index].sourceSnapshot else {
                    return
                }
                sourceSnapshot = snapshot
            } else {
                guard sourceRequestID == nil else { return }
                sourceSnapshot = nil
            }
            let records = makeRecords()
            guard records.count <= 64 else { throw PersonalInkEvaluationError.full }
            guard records.allSatisfy(\.isWithinStorageBounds) else {
                throw PersonalInkEvaluationError.full
            }
            if let sourceSnapshot {
                guard journal.runs[index].recordsMatchSourceCapture(
                    records,
                    snapshot: sourceSnapshot
                ) else {
                    throw PersonalInkEvaluationSourceError.invalid
                }
            } else if records.contains(where: {
                $0.sourceRequestID != nil || $0.targetOrdinal != nil
            }) {
                throw PersonalInkEvaluationSourceError.invalid
            }
            let previous = journal.runs[index].records
            var seen = Set<String>()
            let earlier = Set(journal.runs.filter { $0.id != runID }.flatMap(\.records).map(\.fingerprint))
            let captured = records.map { record in
                var record = record
                record.knownInk = record.knownInk || earlier.contains(record.fingerprint) || !seen.insert(record.fingerprint).inserted
                return record
            }
            if previous.count == captured.count && zip(previous, captured).allSatisfy({ $0.hasSameCapturedContent(as: $1) }) { return }
            journal.runs[index].records = captured
            journal.runs[index].snapshotCount += 1
            if sourceSnapshot != nil {
                journal.runs[index].sourceCaptureState = .complete
            }
        })
    }

    func stop(runID: UUID, completion: @escaping (String?) -> Void) {
        update({ journal in
            guard let index = journal.runs.firstIndex(where: { $0.id == runID && $0.status == .capturing }) else {
                throw PersonalInkEvaluationError.noActiveRun
            }
            if let state = journal.runs[index].sourceCaptureState, state != .complete {
                throw PersonalInkEvaluationError.sourceCapturePending
            }
            journal.runs[index].status = .labeling
        }, completion: completion)
    }

    func label(runID: UUID, recordID: UUID, text: String?, groupingIssue: Bool, completion: @escaping (String?) -> Void) {
        update({ journal in
            guard let i = journal.runs.firstIndex(where: { $0.id == runID && $0.status == .labeling }),
                  let j = journal.runs[i].records.firstIndex(where: { $0.id == recordID }) else { throw PersonalInkEvaluationError.noActiveRun }
            let canonical = text.flatMap { ChordRecognitionCompendium.match($0)?.displayText }
            guard groupingIssue || canonical != nil else { throw PersonalInkError.invalidLabel }
            journal.runs[i].records[j].intended = canonical
            journal.runs[i].records[j].groupingIssue = groupingIssue
        }, completion: completion)
    }

    func finish(runID: UUID, expectedCount: Int, slowInk: Bool, unexpectedChanges: Bool, completion: @escaping (String?) -> Void) {
        update({ journal in
            guard (1...64).contains(expectedCount) else { throw PersonalInkEvaluationError.invalidCount }
            guard let i = journal.runs.firstIndex(where: { $0.id == runID && $0.status == .labeling }) else { throw PersonalInkEvaluationError.noActiveRun }
            guard journal.runs[i].records.allSatisfy({ $0.intended != nil || $0.groupingIssue }) else { throw PersonalInkEvaluationError.incompleteLabels }
            journal.runs[i].expectedChordCount = expectedCount
            journal.runs[i].inkFeltSlow = slowInk
            journal.runs[i].unexpectedChartChanges = unexpectedChanges
            journal.runs[i].finishedAt = Date()
            journal.runs[i].status = .complete
        }, completion: completion)
    }

    func cancel(runID: UUID, completion: @escaping (String?) -> Void) {
        update({ journal in
            guard let i = journal.runs.firstIndex(where: { $0.id == runID }) else { return }
            journal.runs[i].status = .cancelled
            journal.runs[i].finishedAt = Date()
        }, completion: completion)
    }

    /// Explicit teaching is allowed only AFTER a scored run. Its frozen profile
    /// and old results remain unchanged; the next run takes a new snapshot.
    func teach(runID: UUID, recordID: UUID, profileStore: PersonalInkProfileStore = .shared, completion: @escaping (String?) -> Void) {
        teach(runID: runID, recordIDs: [recordID], profileStore: profileStore, completion: completion)
    }

    func teachLabeledExamples(runID: UUID, profileStore: PersonalInkProfileStore = .shared, completion: @escaping (String?) -> Void) {
        teach(runID: runID, recordIDs: nil, profileStore: profileStore, completion: completion)
    }

    private func teach(runID: UUID, recordIDs: Set<UUID>?, profileStore: PersonalInkProfileStore,
                       completion: @escaping (String?) -> Void) {
        update({ journal in
            guard journal.activeRun == nil else { throw PersonalInkEvaluationError.activeRun }
            guard let i = journal.runs.firstIndex(where: { $0.id == runID && $0.status == .complete }) else {
                throw PersonalInkEvaluationError.incompleteLabels
            }
            if let recordIDs, !recordIDs.isSubset(of: Set(journal.runs[i].records.map(\.id))) {
                throw PersonalInkEvaluationError.incompleteLabels
            }
            let records = journal.runs[i].teachableRecords.filter { recordIDs?.contains($0.id) ?? true }
            guard !records.isEmpty else { return }
            let previousCount = profileStore.snapshot().profile.examples.count
            let run = journal.runs[i]
            try profileStore.update { profile in
                for record in records {
                    // Thumbnail-only legacy records cannot bind the original
                    // recognition input. Leave their new lesson untracked too.
                    let context = record.recognitionStrokes.map { _ in
                        PersonalInkCaptureContext(sessionID: run.id, captureID: record.id,
                            capturedAt: record.capturedAt, origin: .savedEvaluation,
                            chartStyle: PersonalInkCaptureContext.chartStyleToken(for: run.style))
                    }
                    try profile.learn(strokes: record.recognitionInput, label: record.intended!, kind: .chord,
                                      source: .explicitCorrection, captureContext: context)
                }
                profile.isEnabled = true
            }
            let saved = profileStore.snapshot().profile
            let taughtIDs = Set(records.map(\.id))
            for j in journal.runs[i].records.indices where taughtIDs.contains(journal.runs[i].records[j].id) {
                journal.runs[i].records[j].taught = true
            }
            journal.runs[i].teachingReceipt = .init(taughtRecordIDs: records.map(\.id),
                profileRevision: saved.revision, profileGeneration: saved.generation,
                previousExampleCount: previousCount, savedExampleCount: saved.examples.count)
        }, completion: completion)
    }

    private func update(
        _ edit: @escaping (inout PersonalInkEvaluationJournal) throws -> Void,
        shouldPersist: @escaping (
            PersonalInkEvaluationJournal,
            PersonalInkEvaluationJournal
        ) -> Bool = { _, _ in true },
        commitEditedStateOnPersistenceFailure: Bool = false,
        completion: ((String?) -> Void)? = nil
    ) {
        queue.async {
            do {
                guard !self.unreadable else { throw PersonalInkEvaluationError.unavailable }
                let before = self.snapshot().journal
                var next = before
                try edit(&next)
                let prepared = next.activeRun.map { run -> PersonalInkEvaluationContext in
                    if let existing = self.frozen, existing.runID == run.id { return existing }
                    return .init(runID: run.id, profile: PersonalInkSnapshot(profile: run.profile))
                }
                do {
                    if shouldPersist(before, next) {
                        let data = try JSONEncoder().encode(next)
                        guard data.count <= Self.maximumJournalByteCount else {
                            throw PersonalInkEvaluationError.full
                        }
                        let folder = self.url.deletingLastPathComponent()
                        try FileManager.default.createDirectory(
                            at: folder,
                            withIntermediateDirectories: true
                        )
                        var excluded = folder
                        var values = URLResourceValues()
                        values.isExcludedFromBackup = true
                        try excluded.setResourceValues(values)
                        #if os(iOS)
                        try data.write(
                            to: self.url,
                            options: [.atomic, .completeFileProtectionUnlessOpen]
                        )
                        #else
                        try data.write(to: self.url, options: .atomic)
                        #endif
                    }
                } catch {
                    let message = error.localizedDescription
                    self.lock.lock()
                    if commitEditedStateOnPersistenceFailure {
                        self.journal = next
                        self.frozen = prepared
                    }
                    self.failure = message
                    self.lock.unlock()
                    if let completion {
                        DispatchQueue.main.async { completion(message) }
                    }
                    return
                }
                self.lock.lock(); self.journal = next; self.frozen = prepared; self.failure = nil; self.lock.unlock()
                if let completion { DispatchQueue.main.async { completion(nil) } }
            } catch {
                let message = error.localizedDescription
                self.lock.lock(); self.failure = message; self.lock.unlock()
                if let completion { DispatchQueue.main.async { completion(message) } }
            }
        }
    }

    static func fingerprint(strokes: [InkStroke]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(strokes)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
