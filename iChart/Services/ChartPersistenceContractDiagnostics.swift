import CryptoKit
import Foundation

/// Only aggregate evidence leaves this type. File/content digests are local
/// checkpoint bindings and must never be copied into a telemetry property.
struct ChartPersistenceContractCheck: Equatable {
    var contractID: String
    var operationID: UUID
    var operation: String
    var outcome: String
    var reason: String
    var scope: String = "library"
    /// Local only; the app transport derives its consent-scoped opaque reference.
    var chartID: UUID?
    var expectedCount: Int = 0
    var actualCount: Int = 0
    var expectedBytes: Int = 0
    var actualBytes: Int = 0
    var contentMatches: Bool?
    var durationMilliseconds: Double?
}

struct ChartExperienceInkSummary: Codable, Equatable {
    var chartID: UUID
    var updatedAt: Date
    var scope: String
    /// Counts nonempty source attachments, not strokes or recognition targets.
    var count: Int
    var bytes: Int
    var contentDigest: String
}

/// The identity survives app launches; the generation distinguishes withdrawal
/// and another opt-in while an older background observation is still running.
struct ChartPersistenceDiagnosticAuthorization: Equatable, Sendable {
    var identity: String
    var generation: UInt64
}

enum ChartExperienceContractSummary {
    /// Call only on a diagnostic/persistence queue: source digests never run
    /// on the PencilKit or main-thread authoring path.
    static func capture(_ snapshot: ChartLibrarySnapshot) -> [ChartExperienceInkSummary] {
        snapshot.charts.flatMap { chart -> [ChartExperienceInkSummary] in
            let measures = chart.measures
            let sources: [(String, [Data?])] = [
                ("page", [chart.pageHandwrittenNotationData]),
                ("header", [chart.pageHandwrittenHeaderData]),
                ("chords", [chart.pageHandwrittenChordData]),
                ("rhythm", measures.map(\.handwrittenRhythmicNotationData)),
                ("chord_sources", measures.flatMap(\.chordEvents).map(\.sourceInkData)),
                ("note_sources", measures.flatMap(\.pitchedNoteEvents).map(\.sourceInkData)),
                ("roadmap_sources", chart.roadmapObjects.map(\.sourceInkData))
            ]
            return sources.map { scope, attachments in
                let byteCounts = attachments.compactMap { $0?.count }.filter { $0 > 0 }
                var digest = SHA256()
                for data in attachments {
                    var length = Int64(data?.count ?? -1).bigEndian
                    withUnsafeBytes(of: &length) { digest.update(data: Data($0)) }
                    if let data { digest.update(data: data) }
                }
                return ChartExperienceInkSummary(
                    chartID: chart.id, updatedAt: chart.updatedAt, scope: scope, count: byteCounts.count,
                    bytes: byteCounts.reduce(0, +),
                    contentDigest: digest.finalize().map { String(format: "%02x", $0) }.joined()
                )
            }
        }
    }

    static func checks(
        expected: [ChartExperienceInkSummary], actual: [ChartExperienceInkSummary], operationID: UUID
    ) -> [ChartPersistenceContractCheck] {
        let actualByKey = Dictionary(actual.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        return expected.compactMap { expected in
            let observed = actualByKey[key(expected)]
            let count = observed?.count ?? 0
            let bytes = observed?.bytes ?? 0
            let sameRevision = observed?.updatedAt == expected.updatedAt
            let matches = sameRevision && count == expected.count && bytes == expected.bytes
                && observed?.contentDigest == expected.contentDigest
            guard expected.count > 0 || count > 0 else { return nil }
            return ChartPersistenceContractCheck(
                contractID: "ink.reopen_preservation", operationID: operationID, operation: "reopen",
                outcome: !sameRevision ? "unknown" : (matches ? "passed" : "violated"),
                reason: !sameRevision ? "baseline_changed" : (matches ? "reopen_matches" : "reopen_mismatch"), scope: expected.scope,
                chartID: expected.chartID, expectedCount: expected.count,
                actualCount: count, expectedBytes: expected.bytes, actualBytes: bytes,
                contentMatches: sameRevision ? matches : nil
            )
        }
    }

    private static func key(_ summary: ChartExperienceInkSummary) -> String {
        summary.chartID.uuidString + ":" + summary.scope
    }
}

/// Call `didSave` on the repository's serialized background persistence queue.
/// Reads are sampled; no telemetry work changes save success, callbacks or data.
final class ChartPersistenceContractDiagnostics {
    struct Checkpoint: Codable {
        var version = 1
        var identity: String
        var fileDigest: String
        var chartCount: Int
        var summaries: [ChartExperienceInkSummary]
    }

    private let fileURL: URL?
    private let checkpointURL: URL?
    private let currentAuthorization: () -> ChartPersistenceDiagnosticAuthorization?
    private let publishCheckpoint: ((Data, URL, ChartPersistenceDiagnosticAuthorization) throws -> Bool)?
    private let isEnabled: () -> Bool
    private let record: (ChartPersistenceContractCheck) -> Void
    private let clock: () -> TimeInterval
    private let minimumReadbackInterval: TimeInterval
    private var lastReadbackAt: TimeInterval?
    private var lastAuthorization: ChartPersistenceDiagnosticAuthorization?

    init(
        fileURL: URL? = nil,
        identity: String,
        currentIdentity: (() -> String?)? = nil,
        currentAuthorization: (() -> ChartPersistenceDiagnosticAuthorization?)? = nil,
        publishCheckpoint: ((Data, URL, ChartPersistenceDiagnosticAuthorization) throws -> Bool)? = nil,
        minimumReadbackInterval: TimeInterval = 30,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        isEnabled: @escaping () -> Bool,
        record: @escaping (ChartPersistenceContractCheck) -> Void
    ) {
        self.fileURL = fileURL
        self.checkpointURL = fileURL.map(Self.checkpointURL(for:))
        let identityProvider = currentIdentity ?? { identity }
        self.currentAuthorization = currentAuthorization ?? {
            identityProvider().map { ChartPersistenceDiagnosticAuthorization(identity: $0, generation: 0) }
        }
        self.publishCheckpoint = publishCheckpoint
        self.minimumReadbackInterval = minimumReadbackInterval
        self.clock = clock
        self.isEnabled = isEnabled
        self.record = record
    }

    static func checkpointURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("experience-checkpoint.json")
    }

    func didLoad(_ snapshot: ChartLibrarySnapshot?, error: Error?, durationMilliseconds: Double) {
        guard isEnabled(), let authorization = currentAuthorization() else { return }
        let identity = authorization.identity
        let operationID = UUID()
        let checkpoint: Checkpoint? = checkpointURL.flatMap { url in
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(Checkpoint.self, from: data),
                  saved.version == 1, saved.identity == identity else { return nil }
            return saved
        }
        // A successful saved checkpoint establishes that a library existed.
        // Absence on a later load must not be disguised as a fresh install.
        let missingKnownLibrary = error == nil && snapshot == nil && checkpoint != nil
        emit(ChartPersistenceContractCheck(
            contractID: "chart.load", operationID: operationID, operation: "load",
            outcome: error == nil && !missingKnownLibrary ? "passed" : "violated",
            reason: error != nil || missingKnownLibrary ? "load_failed" : (snapshot == nil ? "first_launch" : "load_completed"),
            expectedCount: checkpoint?.chartCount ?? 0, actualCount: snapshot?.charts.count ?? 0,
            contentMatches: missingKnownLibrary ? false : nil,
            durationMilliseconds: durationMilliseconds
        ), authorization: authorization)
        guard error == nil, let snapshot, checkpointURL != nil, let fileURL else { return }
        // An unmatched file binding is unknown, never proof of source loss: a
        // crash can occur after atomic library write but before checkpoint write.
        guard let checkpoint else {
            recordUnknownReopen(operationID: operationID, reason: "baseline_missing", authorization: authorization)
            return
        }
        let exactFileMatches = (try? Data(contentsOf: fileURL)).map(Self.digest) == checkpoint.fileDigest
        if exactFileMatches {
            emit(ChartPersistenceContractCheck(
                contractID: "ink.reopen_preservation", operationID: operationID, operation: "reopen",
                outcome: checkpoint.chartCount == snapshot.charts.count ? "passed" : "violated",
                reason: checkpoint.chartCount == snapshot.charts.count ? "reopen_matches" : "reopen_mismatch",
                expectedCount: checkpoint.chartCount, actualCount: snapshot.charts.count,
                contentMatches: checkpoint.chartCount == snapshot.charts.count
            ), authorization: authorization)
        } else {
            recordUnknownReopen(operationID: operationID, reason: "baseline_changed", authorization: authorization)
        }
        let checks = ChartExperienceContractSummary.checks(
            expected: checkpoint.summaries,
            actual: ChartExperienceContractSummary.capture(snapshot), operationID: operationID
        )
        for check in checks { emit(check, authorization: authorization) }
    }

    func didSave(
        _ snapshot: ChartLibrarySnapshot, repository: ChartRepository,
        error: Error?, durationMilliseconds: Double
    ) {
        guard isEnabled(), let authorization = currentAuthorization() else { return }
        let identity = authorization.identity
        if lastAuthorization != authorization {
            lastReadbackAt = nil
            lastAuthorization = authorization
        }
        let now = clock()
        let shouldReadback = lastReadbackAt.map { now - $0 >= minimumReadbackInterval } ?? true
        guard error != nil || shouldReadback else { return }
        let operationID = UUID()
        emit(ChartPersistenceContractCheck(
            contractID: "chart.save", operationID: operationID, operation: "save",
            outcome: error == nil ? "passed" : "violated",
            reason: error == nil ? "save_completed" : "save_failed",
            expectedCount: snapshot.charts.count,
            actualCount: error == nil ? snapshot.charts.count : 0,
            durationMilliseconds: durationMilliseconds
        ), authorization: authorization)
        guard error == nil else { return }
        lastReadbackAt = now
        do {
            let loaded = try repository.loadSnapshot()
            guard isEnabled(), currentAuthorization() == authorization else { return }
            let matches = loaded == snapshot
            // Exempt only positively newer concurrent revisions of the same
            // chart set. Older/missing/mixed readbacks after a successful save
            // are evidence that the expected durable snapshot was not retained.
            let hasPositivelyNewerRevision = loaded.map { actual in
                let expectedRevisions = Dictionary(snapshot.charts.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
                let actualRevisions = Dictionary(actual.charts.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
                guard expectedRevisions.count == snapshot.charts.count,
                      actualRevisions.count == actual.charts.count,
                      Set(expectedRevisions.keys) == Set(actualRevisions.keys) else { return false }
                let hasNoOlderRevision = expectedRevisions.allSatisfy { chartID, expectedDate in
                    actualRevisions[chartID].map { $0 >= expectedDate } ?? false
                }
                let hasNewerRevision = expectedRevisions.contains { chartID, expectedDate in
                    actualRevisions[chartID].map { $0 > expectedDate } ?? false
                }
                return hasNoOlderRevision && hasNewerRevision
            } ?? false
            emit(ChartPersistenceContractCheck(
                contractID: "chart.save_readback", operationID: operationID, operation: "save_readback",
                outcome: hasPositivelyNewerRevision ? "unknown" : (matches ? "passed" : "violated"),
                reason: hasPositivelyNewerRevision ? "baseline_changed" : (matches ? "readback_matches" : "readback_mismatch"),
                expectedCount: snapshot.charts.count, actualCount: loaded?.charts.count ?? 0,
                contentMatches: hasPositivelyNewerRevision ? nil : matches
            ), authorization: authorization)
            guard matches, let fileURL, let checkpointURL,
                  let fileData = try? Data(contentsOf: fileURL) else { return }
            let checkpoint = Checkpoint(
                identity: identity, fileDigest: Self.digest(fileData), chartCount: snapshot.charts.count,
                summaries: ChartExperienceContractSummary.capture(snapshot)
            )
            // Hash and encode outside the consent lock. The app's publisher
            // revalidates this exact generation and atomically publishes under
            // the same lock that withdraws consent and removes the checkpoint.
            let checkpointData = try JSONEncoder().encode(checkpoint)
            guard isEnabled(), currentAuthorization() == authorization else { return }
            // A diagnostic checkpoint failure must never fail the user's save.
            if let publishCheckpoint {
                _ = try? publishCheckpoint(checkpointData, checkpointURL, authorization)
            } else {
                // Injected portable callers provide their own consent policy;
                // the production app always supplies the atomic publisher.
                try? checkpointData.write(to: checkpointURL, options: .atomic)
            }
        } catch {
            guard isEnabled(), currentAuthorization() == authorization else { return }
            emit(ChartPersistenceContractCheck(
                contractID: "chart.save_readback", operationID: operationID, operation: "save_readback",
                outcome: "unknown", reason: "readback_failed", expectedCount: snapshot.charts.count
            ), authorization: authorization)
        }
    }

    private func recordUnknownReopen(
        operationID: UUID, reason: String, authorization: ChartPersistenceDiagnosticAuthorization
    ) {
        emit(ChartPersistenceContractCheck(
            contractID: "ink.reopen_preservation", operationID: operationID, operation: "reopen",
            outcome: "unknown", reason: reason
        ), authorization: authorization)
    }

    private func emit(_ check: ChartPersistenceContractCheck, authorization: ChartPersistenceDiagnosticAuthorization) {
        guard isEnabled(), currentAuthorization() == authorization else { return }
        record(check)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
