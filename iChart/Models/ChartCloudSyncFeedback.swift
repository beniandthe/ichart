import Foundation

enum ChartCloudSyncOperation: String, Equatable, Sendable {
    case backup
    case restore

    var displayName: String { self == .restore ? "cloud restore" : "cloud backup" }
}

/// Fixed stage names are safe for diagnostics; never include chart/account data.
enum ChartCloudSyncStage: String, CaseIterable, Equatable, Sendable {
    case preparingSession = "preparing_session"
    case readingDocuments = "reading_documents"
    case readingSnapshots = "reading_snapshots"
    case decodingCharts = "decoding_charts"
    case mergingCharts = "merging_charts"
    case writingDocument = "writing_document"
    case encodingSnapshot = "encoding_snapshot"
    case writingSnapshot = "writing_snapshot"
    case resolvingSnapshot = "resolving_snapshot"
    case linkingSnapshot = "linking_snapshot"
    case writingDeletion = "writing_deletion"
    case applyingSnapshot = "applying_snapshot"
    case unknown

    var detailText: String {
        switch self {
        case .preparingSession: "Connecting to your cloud account…"
        case .readingDocuments: "Checking your cloud charts…"
        case .readingSnapshots, .decodingCharts: "Downloading charts…"
        case .mergingCharts: "Combining cloud and local charts…"
        case .writingDocument, .encodingSnapshot, .writingSnapshot, .resolvingSnapshot, .linkingSnapshot: "Saving charts to cloud…"
        case .writingDeletion: "Updating removed cloud charts…"
        case .applyingSnapshot: "Adding cloud changes to this iPad…"
        case .unknown: "Finishing the cloud operation…"
        }
    }
}

struct ChartCloudSyncProgress: Equatable, Sendable {
    let operation: ChartCloudSyncOperation
    let stage: ChartCloudSyncStage

    var displayTitle: String { operation == .restore ? "Restoring charts" : "Backing up charts" }
    var detailText: String { stage.detailText }
    var systemImageName: String { operation == .restore ? "icloud.and.arrow.down" : "icloud.and.arrow.up" }
}

struct ChartCloudSyncOperationResult: Equatable, Sendable {
    let operation: ChartCloudSyncOperation
    let completedAt: Date
    /// Available active charts downloaded, not the merged library size.
    let remoteChartCount: Int?
    let backedUpChartCount: Int
    let tombstonedChartCount: Int
    /// Actual local library count after the existing conditional apply attempt.
    let libraryChartCount: Int
    /// Nil for backup. False means local edits prevented applying the download.
    let didApplySnapshot: Bool?

    var displayTitle: String {
        if operation == .backup { return "Backup complete" }
        if didApplySnapshot == false { return "Restore not applied" }
        return remoteChartCount == 0 ? "Restore complete — no cloud charts" : "Restore complete"
    }

    var detailText: String {
        if operation == .backup {
            if backedUpChartCount == 0 && tombstonedChartCount == 0 {
                return "No eligible charts or cloud deletions were included in this backup."
            }
            let deletionText = tombstonedChartCount > 0 ? " Synced \(chartCount(tombstonedChartCount, noun: "deletion"))." : ""
            return "Backed up \(chartCount(backedUpChartCount)).\(deletionText)"
        }

        let available = chartCount(remoteChartCount ?? 0)
        if didApplySnapshot == false {
            return "Found \(available) in cloud, but this iPad changed during restore. Your current library was kept. Retry restore to apply cloud changes."
        }
        return "Found \(available) in cloud. Restore applied; this iPad now has \(chartCount(libraryChartCount))."
    }

    var systemImageName: String {
        didApplySnapshot == false ? "exclamationmark.icloud" : "checkmark.icloud"
    }

    private func chartCount(_ count: Int, noun: String = "chart") -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

enum ChartCloudSyncFailureCategory: String, CaseIterable, Equatable, Sendable {
    case cancelled
    case offline
    case timeout
    case network
    case sessionRequired = "session_required"
    case permissionDenied = "permission_denied"
    case localStorage = "local_storage"
    case encoding
    case decoding
    case authentication
    case server
    case unknown

    /// Foundation-only classification; SDK-specific evidence is handled by the
    /// cloud store. Error descriptions are not evidence of an auth/RLS cause.
    static func foundationCategory(for error: Error) -> Self {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost: return .offline
            case .timedOut: return .timeout
            default: return .network
            }
        }
        if error is EncodingError { return .encoding }
        if error is DecodingError { return .decoding }
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain { return .localStorage }
        let storageCodes: [CocoaError.Code] = [
            .fileReadUnknown, .fileReadNoPermission, .fileReadNoSuchFile,
            .fileReadCorruptFile, .fileWriteUnknown, .fileWriteNoPermission,
            .fileWriteOutOfSpace, .fileWriteInvalidFileName
        ]
        if nsError.domain == NSCocoaErrorDomain,
           storageCodes.contains(where: { $0.rawValue == nsError.code }) {
            return .localStorage
        }
        return .unknown
    }
}

struct ChartCloudSyncFailure: Equatable, Sendable {
    let operation: ChartCloudSyncOperation
    let stage: ChartCloudSyncStage
    let category: ChartCloudSyncFailureCategory

    var displayTitle: String {
        if category == .cancelled { return operation == .restore ? "Restore interrupted" : "Backup interrupted" }
        return operation == .restore ? "Cloud restore needs attention" : "Cloud backup needs attention"
    }

    var detailText: String {
        switch category {
        case .cancelled:
            return "The \(operation.displayName) was interrupted. Retry when you are ready."
        case .offline:
            return "Reconnect to finish \(operation.displayName), then retry."
        case .timeout:
            return "The \(operation.displayName) timed out. Retry when your connection is stable."
        case .network:
            return "The connection could not finish \(operation.displayName). Retry, or contact support if it continues."
        case .sessionRequired:
            return "Your cloud session could not be validated. Sign in again, then retry \(operation.displayName)."
        case .permissionDenied:
            return "Cloud permissions blocked \(operation.displayName). Retry, or contact support if it continues."
        case .localStorage:
            return "This iPad could not prepare local storage for \(operation.displayName). Retry, or contact support if it continues."
        case .encoding:
            return "A chart could not be prepared for \(operation.displayName). Retry, or contact support if it continues."
        case .decoding:
            return "Downloaded cloud data could not be read. Retry, or contact support if it continues."
        case .authentication:
            return "The cloud account service could not finish \(operation.displayName). Retry, or contact support if it continues."
        case .server:
            return "The cloud service could not finish \(operation.displayName). Retry, or contact support if it continues."
        case .unknown:
            return "We could not finish \(operation.displayName). Retry, or contact support if it continues."
        }
    }

    var systemImageName: String { category == .offline ? "wifi.slash" : "exclamationmark.icloud" }

    var diagnosticStage: String { "cloud_stage_\(stage.rawValue)" }
}

/// Retains the original error for existing service fallback decisions. Only the
/// fixed stage/category above may be presented or sent as diagnostics.
struct ChartCloudSyncStageError: Error {
    let stage: ChartCloudSyncStage
    let underlyingError: Error
}

typealias ChartCloudSyncProgressHandler = @Sendable (ChartCloudSyncStage) async -> Void

enum ChartCloudSyncStageReporting {
    @discardableResult
    static func perform<Value>(
        _ stage: ChartCloudSyncStage,
        onProgress: ChartCloudSyncProgressHandler?,
        operation: () async throws -> Value
    ) async throws -> Value {
        await onProgress?(stage)
        do {
            return try await operation()
        } catch {
            if error is ChartCloudSyncStageError { throw error }
            throw ChartCloudSyncStageError(stage: stage, underlyingError: error)
        }
    }
}
