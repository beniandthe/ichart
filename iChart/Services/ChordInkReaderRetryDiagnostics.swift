#if canImport(UIKit)
import Foundation

/// Ephemeral evidence created by two actual invocations of the same current
/// Vision read. The authorization is never encoded in the receipt.
struct ChordInkReaderRetryProof: Hashable, Sendable {
    let episodeID: UUID
    let failedAttemptMilliseconds: Double
    let recoveredAttemptMilliseconds: Double
    let supportedCandidateCount: Int
    let consent: IChartTelemetryConsentSnapshot
}

enum ChordInkReaderRetryDiagnostics {
    static var receiptURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("iChart-reader-retry-v1.json")
    }

    #if ICHART_READER_RETRY_QA
    private static let writer = DispatchQueue(label: "com.ichart.reader-retry-receipt", qos: .utility)
    #endif

    /// The file contains only the latest complete, verified automatic commit.
    /// No diagnostic state is added to the library or to network telemetry.
    struct Receipt: Encodable {
        let schemaVersion = 1
        let build: Int
        let episodeID: UUID
        let provider = "apple_vision"
        let firstAttemptOutcome = "technical_failure"
        let retryOutcome = "completed_supported"
        let attemptCount = 2
        let failedAttemptMilliseconds: Int
        let recoveredAttemptMilliseconds: Int
        let supportedCandidateCount: Int
        let commitOutcome = "automatic_render_complete"
        let committedAtEpochSeconds: Int
        let sourceStrokeCount: Int
        let consumedStrokeCount: Int
        let retainedStrokeCount: Int
        let sourceStillCurrent = true
        let sourcePreserved = true

        init?(
            proof: ChordInkReaderRetryProof,
            build: Int,
            committedAt: Date,
            sourceStrokeCount: Int,
            consumedStrokeCount: Int,
            retainedStrokeCount: Int
        ) {
            let timestamp = committedAt.timeIntervalSince1970
            guard proof.consent.isGranted, (1...999_999).contains(build),
                  (0...30_000).contains(proof.failedAttemptMilliseconds),
                  (0...30_000).contains(proof.recoveredAttemptMilliseconds),
                  (1...64).contains(proof.supportedCandidateCount),
                  (1...4_096).contains(sourceStrokeCount),
                  (1...sourceStrokeCount).contains(consumedStrokeCount),
                  retainedStrokeCount == sourceStrokeCount - consumedStrokeCount,
                  (0...4_102_444_799).contains(timestamp) else { return nil }
            self.build = build
            episodeID = proof.episodeID
            failedAttemptMilliseconds = Int(proof.failedAttemptMilliseconds.rounded())
            recoveredAttemptMilliseconds = Int(proof.recoveredAttemptMilliseconds.rounded())
            supportedCandidateCount = proof.supportedCandidateCount
            committedAtEpochSeconds = Int(timestamp)
            self.sourceStrokeCount = sourceStrokeCount
            self.consumedStrokeCount = consumedStrokeCount
            self.retainedStrokeCount = retainedStrokeCount
        }
    }

    /// Call only after the automatic transaction consumed the proven candidate
    /// and verified exact source preservation. Disk I/O stays off the editor.
    static func recordCommit(
        proof: ChordInkReaderRetryProof,
        committedAt: Date,
        sourceStrokeCount: Int,
        consumedStrokeCount: Int,
        retainedStrokeCount: Int
    ) {
        #if ICHART_READER_RETRY_QA
        guard let url = receiptURL,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = Int(version),
              let receipt = Receipt(
                  proof: proof, build: build, committedAt: committedAt,
                  sourceStrokeCount: sourceStrokeCount, consumedStrokeCount: consumedStrokeCount,
                  retainedStrokeCount: retainedStrokeCount
              ),
              let data = try? JSONEncoder().encode(receipt) else { return }
        writer.async {
            _ = try? IChartTelemetryConsentStore.shared.publishLocalDiagnosticReceipt(
                data, to: url, matching: proof.consent
            )
        }
        #endif
    }
}
#endif
