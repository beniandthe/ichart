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
    private var operationGeneration = 0
    private var lastObservedAuthContext: AuthContext?

    private enum ConnectionMode: Equatable { case unconfigured, signedOut, offline, online }

    private struct AuthContext: Equatable {
        let accountID: UUID?
        let connection: ConnectionMode
        let hasCloudAccess: Bool
        let libraryReadFailed: Bool
    }

    private struct OperationContext: Sendable {
        let generation: Int
        let accountID: UUID
    }

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

        invalidatePendingOperations()
        lastObservedAuthContext = nil
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
        let connection: ConnectionMode
        switch authState {
        case .signedIn(let session), .passwordRecovery(let session):
            connection = .online
            accountID = session.id
        case .temporarilyOffline(let session):
            connection = .offline
            accountID = session.id
        case .unconfigured:
            connection = .unconfigured
            accountID = nil
        case .signedOut, .pendingEmailVerification:
            connection = .signedOut
            accountID = nil
        }
        let context = AuthContext(accountID: accountID, connection: connection,
            hasCloudAccess: isCloudSyncEntitled,
            libraryReadFailed: libraryStore?.hasUnresolvedLoadFailure == true)
        // SwiftUI observes account and entitlement state in several places.
        // Repeated equivalent observations must not cancel a manual restore or
        // restart the first upload before its acknowledgements can be saved.
        guard context != lastObservedAuthContext else { return }
        lastObservedAuthContext = context
        if accountID != feedbackAccountID {
            invalidatePendingOperations()
            clearOperationFeedback()
        }
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

        let currentSnapshot = libraryStore.snapshot
        guard validateLocalCharts(in: currentSnapshot, for: .backup) else { return }

        let snapshot = enrollLocalCharts
            ? libraryStore.enrollLocalChartsForCloudBackup()
            : currentSnapshot
        invalidatePendingOperations()
        guard let context = currentOperationContext else { return }
        syncTask = Task { [weak self] in
            guard let self, self.isAuthorized(context), !Task.isCancelled else { return }
            await self.runPush(snapshot: snapshot, service: service, context: context,
                               forceRemoteWrite: enrollLocalCharts)
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

        let snapshot = libraryStore.snapshot
        guard validateLocalCharts(in: snapshot, for: .restore) else { return }

        invalidatePendingOperations()
        guard let context = currentOperationContext else { return }
        syncTask = Task { [weak self] in
            guard let self, self.isAuthorized(context), !Task.isCancelled else { return }
            await self.runRestore(snapshot: snapshot, service: service, context: context)
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

        guard validateLocalCharts(in: snapshot, for: .backup),
              allowsAutomaticUpload(snapshot, at: Date()),
              let context = currentOperationContext else {
            return
        }

        queuedUploadTask?.cancel()
        queuedUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, self?.isAuthorized(context) == true else {
                return
            }
            guard self?.beginQueuedAutomaticUpload(snapshot) == true else {
                return
            }
            await self?.runPush(snapshot: snapshot, service: service, context: context,
                                forceRemoteWrite: false)
        }
    }

    private func beginQueuedAutomaticUpload(_ snapshot: ChartLibrarySnapshot) -> Bool {
        queuedUploadTask = nil
        return allowsAutomaticUpload(snapshot, at: Date())
    }

    private func validateLocalCharts(in snapshot: ChartLibrarySnapshot, for operation: ChartCloudSyncOperation) -> Bool {
        guard libraryStore?.hasUnresolvedLoadFailure != true else {
            invalidatePendingOperations()
            let failure = ChartCloudSyncFailure(
                operation: operation, stage: .validatingLocalCharts, category: .localStorage
            )
            let feedbackID = beginOperationFeedback(operation)
            state = .failed(failure.detailText)
            failOperationFeedback(failure, feedbackID: feedbackID)
            return false
        }
        guard Set(snapshot.charts.map(\.id)).count == snapshot.charts.count else {
            queuedUploadTask?.cancel()
            queuedUploadTask = nil
            let failure = ChartCloudSyncFailure(
                operation: operation, stage: .validatingLocalCharts, category: .invalidLocalLibrary
            )
            let feedbackID = beginOperationFeedback(operation)
            state = .failed(failure.detailText)
            failOperationFeedback(failure, feedbackID: feedbackID)
            return false
        }
        return true
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

    private func runRestore(snapshot: ChartLibrarySnapshot, service: any ChartCloudSyncServicing, context: OperationContext) async {
        guard isAuthorized(context), !Task.isCancelled else { return }
        isWorking = true
        defer { finishWorkingState(for: context) }
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
                await self?.updateProgress(stage, operation: .restore, feedbackID: feedbackID, context: context)
            })
            guard isAuthorized(context), !Task.isCancelled else { return }
            let result = outcome.syncResult
            guard result.snapshot.cloudMetadata.ownerID == context.accountID else {
                let failure = ChartCloudSyncFailure(operation: .restore,
                    stage: .preparingSession, category: .sessionRequired)
                state = .failed(failure.detailText)
                failOperationFeedback(failure, feedbackID: feedbackID)
                return
            }
            updateProgress(.applyingSnapshot, operation: .restore, feedbackID: feedbackID, context: context)
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
            guard isAuthorized(context), !Task.isCancelled else { return }
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
    }

    private func runPush(snapshot: ChartLibrarySnapshot, service: any ChartCloudSyncServicing,
                         context: OperationContext, forceRemoteWrite: Bool) async {
        guard isAuthorized(context), !Task.isCancelled else { return }
        queuedUploadTask = nil
        guard !isWorking else {
            queueUpload(snapshot)
            return
        }

        let stateBeforePush = state
        let failureBeforePush = lastFailure
        isWorking = true
        defer { finishWorkingState(for: context) }
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
            let result = try await service.pushLocalSnapshot(snapshot, forceRemoteWrite: forceRemoteWrite, onProgress: { [weak self] stage in
                await self?.updateProgress(stage, operation: .backup, feedbackID: feedbackID, context: context)
            })
            guard isAuthorized(context), !Task.isCancelled else { return }
            guard result.ownerID == context.accountID else {
                let failure = ChartCloudSyncFailure(operation: .backup,
                    stage: .preparingSession, category: .sessionRequired)
                state = .failed(failure.detailText)
                failOperationFeedback(failure, feedbackID: feedbackID)
                return
            }
            if result.didPerformRemoteWrites {
                libraryStore?.markChartsBackedUpToCloud(
                    chartIDs: result.backedUpChartIDs,
                    ownerID: result.ownerID,
                    backedUpAt: result.lastRemoteBackupAt,
                    from: snapshot,
                    acknowledgedContentSHA256ByChartID: result.acknowledgedContentSHA256ByChartID
                )
                libraryStore?.updateCloudMetadataFromSync(
                    ownerID: result.ownerID,
                    lastSyncAt: Date(),
                    lastRemoteBackupAt: result.lastRemoteBackupAt
                )
                automaticUploadBackoff.recordSuccess()
                lastRemoteBackupAt = result.lastRemoteBackupAt
                if feedbackOperationID == feedbackID { state = .synced(Date()) }
            } else if feedbackOperationID == feedbackID {
                // A local durable acknowledgement is not a new network check.
                // Preserve prior failure/offline information and backup dates.
                switch stateBeforePush {
                case .synced, .failed, .offline:
                    state = stateBeforePush
                default:
                    state = lastRemoteBackupAt.map(ChartSyncState.synced) ?? .idle
                }
            }
            finishOperationFeedback(
                ChartCloudSyncOperationResult(
                    operation: .backup,
                    completedAt: Date(),
                    remoteChartCount: nil,
                    backedUpChartCount: result.backedUpChartIDs.count,
                    tombstonedChartCount: result.tombstonedChartIDs.count,
                    libraryChartCount: libraryStore?.charts.count ?? snapshot.charts.count,
                    didApplySnapshot: nil,
                    didPerformRemoteWrites: result.didPerformRemoteWrites
                ),
                feedbackID: feedbackID
            )
            guard result.didPerformRemoteWrites else {
                lastFailure = failureBeforePush
                return
            }
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
            guard isAuthorized(context), !Task.isCancelled else { return }
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
    }

    private func cancelPendingSyncWork() {
        clearOperationFeedback()
        invalidatePendingOperations()
        automaticUploadBackoff.reset()
    }

    private func invalidatePendingOperations() {
        operationGeneration += 1
        queuedUploadTask?.cancel()
        queuedUploadTask = nil
        syncTask?.cancel()
        syncTask = nil
        isWorking = false
    }

    private var currentOperationContext: OperationContext? {
        guard isSignedIn, let feedbackAccountID else { return nil }
        return OperationContext(generation: operationGeneration, accountID: feedbackAccountID)
    }

    private func isAuthorized(_ context: OperationContext) -> Bool {
        context.generation == operationGeneration
            && context.accountID == feedbackAccountID
            && isSignedIn
            && isCloudSyncEntitled
            && libraryStore?.hasUnresolvedLoadFailure != true
    }

    private func finishWorkingState(for context: OperationContext) {
        // An old task must not clear a newer account/operation's busy state.
        guard context.generation == operationGeneration,
              context.accountID == feedbackAccountID else { return }
        isWorking = false
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

    private func updateProgress(_ stage: ChartCloudSyncStage, operation: ChartCloudSyncOperation, feedbackID: UUID, context: OperationContext) {
        guard isAuthorized(context), feedbackOperationID == feedbackID else { return }
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
