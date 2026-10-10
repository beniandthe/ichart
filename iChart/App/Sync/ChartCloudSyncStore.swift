import Foundation
import Supabase

@MainActor
final class ChartCloudSyncStore: ObservableObject {
    @Published private(set) var state: ChartSyncState
    @Published private(set) var lastRemoteBackupAt: Date?
    @Published private(set) var lastSyncAttemptAt: Date?
    @Published private(set) var isWorking = false
    @Published private(set) var progress: ChartCloudSyncProgress?
    @Published private(set) var lastOperationResult: ChartCloudSyncOperationResult?
    @Published private(set) var lastRestoreResult: ChartCloudSyncOperationResult?
    @Published private(set) var lastFailure: ChartCloudSyncFailure?

    private let service: (any ChartCloudSyncServicing)?
    private weak var libraryStore: ChartLibraryStore?
    private var isSignedIn = false
    private var automaticUploadBackoff = ChartCloudAutomaticUploadBackoff()
    private var queuedUploadTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var feedbackOperationID: UUID?
    private var feedbackAccountID: UUID?

    init(service: (any ChartCloudSyncServicing)?) {
        self.service = service
        state = service == nil ? .unconfigured : .signedOut
    }

    static func live(clients: IChartSupabaseClients?) -> ChartCloudSyncStore {
        ChartCloudSyncStore(
            service: clients.map {
                ChartCloudSyncService(
                    client: $0.dataClient,
                    sessionRefresher: IChartSupabaseSessionRefresher(
                        authClient: $0.authClient,
                        sessionStore: $0.sessionStore
                    )
                )
            }
        )
    }

    func attach(libraryStore: ChartLibraryStore) {
        guard self.libraryStore !== libraryStore else {
            return
        }

        self.libraryStore = libraryStore
        lastRemoteBackupAt = libraryStore.cloudMetadata.lastRemoteBackupAt
        libraryStore.onSnapshotSaved = { [weak self] snapshot in
            Task { @MainActor in
                self?.handleSavedSnapshot(snapshot)
            }
        }
    }

    func authStateChanged(_ authState: IChartAuthState) {
        let accountID: UUID?
        switch authState {
        case .signedIn(let session), .passwordRecovery(let session), .temporarilyOffline(let session):
            accountID = session.id
        default:
            accountID = nil
        }
        if accountID != feedbackAccountID { clearOperationFeedback() }
        feedbackAccountID = accountID
        guard service != nil else {
            cancelPendingSyncWork()
            state = .unconfigured
            isSignedIn = false
            return
        }

        switch authState {
        case .signedIn, .passwordRecovery:
            isSignedIn = true
            guard isCloudSyncEntitled else {
                cancelPendingSyncWork()
                state = .requiresPro
                return
            }

            backUpNow(enrollLocalCharts: false)
        case .temporarilyOffline:
            cancelPendingSyncWork()
            isSignedIn = true
            state = isCloudSyncEntitled ? .offline : .requiresPro
        case .unconfigured:
            cancelPendingSyncWork()
            isSignedIn = false
            state = .unconfigured
        case .signedOut, .pendingEmailVerification:
            cancelPendingSyncWork()
            isSignedIn = false
            state = .signedOut
        }
    }

    func backUpNow(enrollLocalCharts: Bool = true) {
        guard isSignedIn, let service, let libraryStore else {
            clearOperationFeedback()
            state = service == nil ? .unconfigured : .signedOut
            return
        }

        guard isCloudSyncEntitled else {
            cancelPendingSyncWork()
            state = .requiresPro
            return
        }

        let snapshot = enrollLocalCharts
            ? libraryStore.enrollLocalChartsForCloudBackup()
            : libraryStore.snapshot
        queuedUploadTask?.cancel()
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.runPush(snapshot: snapshot, service: service)
        }
    }

    func restoreChartsFromCloud() {
        guard isSignedIn, let service, let libraryStore else {
            clearOperationFeedback()
            state = service == nil ? .unconfigured : .signedOut
            return
        }

        guard isCloudSyncEntitled else {
            cancelPendingSyncWork()
            state = .requiresPro
            return
        }

        queuedUploadTask?.cancel()
        syncTask?.cancel()
        let snapshot = libraryStore.snapshot
        syncTask = Task { [weak self] in
            await self?.runRestore(snapshot: snapshot, service: service)
        }
    }

    private func queueUpload(_ snapshot: ChartLibrarySnapshot) {
        guard isSignedIn, let service else {
            return
        }

        guard snapshot.entitlements.includes(.cloudBackup) else {
            cancelPendingSyncWork()
            state = .requiresPro
            return
        }

        guard allowsAutomaticUpload(snapshot, at: Date()) else {
            return
        }

        queuedUploadTask?.cancel()
        queuedUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else {
                return
            }
            guard self?.beginQueuedAutomaticUpload(snapshot) == true else {
                return
            }
            await self?.runPush(snapshot: snapshot, service: service)
        }
    }

    private func beginQueuedAutomaticUpload(_ snapshot: ChartLibrarySnapshot) -> Bool {
        queuedUploadTask = nil
        return allowsAutomaticUpload(snapshot, at: Date())
    }

    private func allowsAutomaticUpload(_ snapshot: ChartLibrarySnapshot, at date: Date) -> Bool {
        guard automaticUploadBackoff.allowsAutomaticUpload(at: date) else {
            IChartPerformanceTrace.record(
                "cloud.automatic_push_suppressed",
                metadata: [
                    "reason": "failure_backoff",
                    "retry_after_ms": "\(Int(automaticUploadBackoff.remainingCooldown(at: date) * 1_000))",
                    "chart_count": "\(snapshot.charts.count)"
                ]
            )
            return false
        }

        return true
    }

    private func runRestore(snapshot: ChartLibrarySnapshot, service: any ChartCloudSyncServicing) async {
        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing
        let feedbackID = beginOperationFeedback(.restore)
        let startedAt = Date()
        IChartTelemetry.record(
            "cloud.restore_started",
            properties: [
                "chart_count": .int(snapshot.charts.count),
                "result": .string("started")
            ]
        )

        do {
            let outcome = try await service.restoreFromCloud(localSnapshot: snapshot, onProgress: { [weak self] stage in
                await self?.updateProgress(stage, operation: .restore, feedbackID: feedbackID)
            })
            let result = outcome.syncResult
            updateProgress(.applyingSnapshot, operation: .restore, feedbackID: feedbackID)
            var didApplySyncedSnapshot = false
            if let libraryStore {
                didApplySyncedSnapshot = libraryStore.applySyncedSnapshot(
                    result.snapshot,
                    ifUnchangedFrom: snapshot
                )
                if !didApplySyncedSnapshot {
                    queueUpload(libraryStore.snapshot)
                }
            }
            lastRemoteBackupAt = result.lastRemoteBackupAt
            if queuedUploadTask == nil, feedbackOperationID == feedbackID {
                state = .synced(Date())
            }
            finishOperationFeedback(
                ChartCloudSyncOperationResult(
                    operation: .restore,
                    completedAt: Date(),
                    remoteChartCount: outcome.remoteChartCount,
                    backedUpChartCount: outcome.backedUpChartCount,
                    tombstonedChartCount: outcome.tombstonedChartCount,
                    libraryChartCount: libraryStore?.charts.count ?? snapshot.charts.count,
                    didApplySnapshot: didApplySyncedSnapshot
                ),
                feedbackID: feedbackID
            )
            IChartTelemetry.record(
                "cloud.restore_succeeded",
                properties: [
                    "chart_count": .int(result.snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "result": .string("synced")
                ]
            )
        } catch {
            let failure = Self.failureFeedback(for: error, operation: .restore)
            if feedbackOperationID == feedbackID {
                state = Self.failureState(for: error, operation: .restore)
            }
            failOperationFeedback(failure, feedbackID: feedbackID)
            IChartTelemetry.record(
                "cloud.restore_failed",
                properties: [
                    "chart_count": .int(snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "error_code": .string(failure.category.rawValue),
                    "reason": .string(failure.diagnosticStage),
                    "result": .string("failed")
                ]
            )
        }

        isWorking = false
    }

    private func runPush(snapshot: ChartLibrarySnapshot, service: any ChartCloudSyncServicing) async {
        queuedUploadTask = nil
        guard !isWorking else {
            queueUpload(snapshot)
            return
        }

        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing
        let feedbackID = beginOperationFeedback(.backup)
        let startedAt = Date()
        IChartTelemetry.record(
            "cloud.push_started",
            properties: [
                "chart_count": .int(snapshot.charts.count),
                "result": .string("started")
            ]
        )

        do {
            let result = try await service.pushLocalSnapshot(snapshot, onProgress: { [weak self] stage in
                await self?.updateProgress(stage, operation: .backup, feedbackID: feedbackID)
            })
            libraryStore?.markChartsBackedUpToCloud(
                chartIDs: result.backedUpChartIDs,
                ownerID: result.ownerID,
                backedUpAt: result.lastRemoteBackupAt,
                from: snapshot
            )
            libraryStore?.updateCloudMetadataFromSync(
                ownerID: result.ownerID,
                lastSyncAt: Date(),
                lastRemoteBackupAt: result.lastRemoteBackupAt
            )
            automaticUploadBackoff.recordSuccess()
            lastRemoteBackupAt = result.lastRemoteBackupAt
            if feedbackOperationID == feedbackID { state = .synced(Date()) }
            finishOperationFeedback(
                ChartCloudSyncOperationResult(
                    operation: .backup,
                    completedAt: Date(),
                    remoteChartCount: nil,
                    backedUpChartCount: result.backedUpChartIDs.count,
                    tombstonedChartCount: result.tombstonedChartIDs.count,
                    libraryChartCount: libraryStore?.charts.count ?? snapshot.charts.count,
                    didApplySnapshot: nil
                ),
                feedbackID: feedbackID
            )
            IChartTelemetry.record(
                "cloud.push_succeeded",
                properties: [
                    "chart_count": .int(snapshot.charts.count),
                    "cloud_backed_up_count": .int(result.backedUpChartIDs.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "result": .string("synced")
                ]
            )
        } catch {
            automaticUploadBackoff.recordFailure(at: Date())
            let failure = Self.failureFeedback(for: error, operation: .backup)
            if feedbackOperationID == feedbackID { state = Self.failureState(for: error) }
            failOperationFeedback(failure, feedbackID: feedbackID)
            IChartTelemetry.record(
                "cloud.push_failed",
                properties: [
                    "chart_count": .int(snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "error_code": .string(failure.category.rawValue),
                    "reason": .string(failure.diagnosticStage),
                    "result": .string("failed")
                ]
            )
        }

        isWorking = false
    }

    private func cancelPendingSyncWork() {
        clearOperationFeedback()
        queuedUploadTask?.cancel()
        queuedUploadTask = nil
        syncTask?.cancel()
        syncTask = nil
        isWorking = false
        automaticUploadBackoff.reset()
    }

    private var isCloudSyncEntitled: Bool {
        libraryStore?.canUse(.cloudBackup) == true
    }

    private func beginOperationFeedback(_ operation: ChartCloudSyncOperation) -> UUID {
        let id = UUID()
        feedbackOperationID = id
        progress = ChartCloudSyncProgress(operation: operation, stage: .preparingSession)
        lastOperationResult = nil
        lastFailure = nil
        if operation == .restore { lastRestoreResult = nil }
        return id
    }

    private func updateProgress(_ stage: ChartCloudSyncStage, operation: ChartCloudSyncOperation, feedbackID: UUID) {
        guard feedbackOperationID == feedbackID else { return }
        progress = ChartCloudSyncProgress(operation: operation, stage: stage)
    }

    private func finishOperationFeedback(_ result: ChartCloudSyncOperationResult, feedbackID: UUID) {
        guard feedbackOperationID == feedbackID else { return }
        feedbackOperationID = nil
        progress = nil
        lastFailure = nil
        lastOperationResult = result
        if result.operation == .restore { lastRestoreResult = result }
    }

    private func failOperationFeedback(_ failure: ChartCloudSyncFailure, feedbackID: UUID) {
        guard feedbackOperationID == feedbackID else { return }
        feedbackOperationID = nil
        progress = nil
        lastOperationResult = nil
        lastFailure = failure
    }

    private func clearOperationFeedback() {
        feedbackOperationID = nil
        progress = nil
        lastOperationResult = nil
        lastRestoreResult = nil
        lastFailure = nil
    }

    private func handleSavedSnapshot(_ snapshot: ChartLibrarySnapshot) {
        guard isSignedIn else {
            return
        }

        guard snapshot.entitlements.includes(.cloudBackup) else {
            cancelPendingSyncWork()
            state = .requiresPro
            return
        }

        queueUpload(snapshot)
    }

    nonisolated static func failureState(for error: Error, operation: ChartCloudSyncOperation = .backup) -> ChartSyncState {
        let failure = failureFeedback(for: error, operation: operation)
        return failure.category == .offline ? .offline : .failed(failure.detailText)
    }

    nonisolated static func failureFeedback(for error: Error, operation: ChartCloudSyncOperation) -> ChartCloudSyncFailure {
        let stagedError = error as? ChartCloudSyncStageError
        let underlying = stagedError?.underlyingError ?? error
        let category: ChartCloudSyncFailureCategory
        let foundationCategory = ChartCloudSyncFailureCategory.foundationCategory(for: underlying)
        if foundationCategory != .unknown {
            category = foundationCategory
        } else if let postgrestError = underlying as? PostgrestError {
            switch postgrestError.code {
            case "42501": category = .permissionDenied
            case "PGRST301", "PGRST302", "PGRST303": category = .sessionRequired
            default: category = .server
            }
        } else if let authError = underlying as? AuthError {
            let sessionCodes = [
                "session_not_found", "session_expired", "refresh_token_not_found",
                "refresh_token_already_used", "bad_jwt", "invalid_jwt", "no_authorization"
            ]
            if authError == .sessionMissing || sessionCodes.contains(authError.errorCode.rawValue) {
                category = .sessionRequired
            } else if case .api(_, _, _, let response) = authError, response.statusCode == 403 {
                category = .permissionDenied
            } else {
                category = .authentication
            }
        } else {
            category = .unknown
        }
        return ChartCloudSyncFailure(
            operation: operation,
            stage: stagedError?.stage ?? .unknown,
            category: category
        )
    }
}
