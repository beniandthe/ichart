import Foundation
import Supabase

@MainActor
final class ChartCloudSyncStore: ObservableObject {
    @Published private(set) var state: ChartSyncState
    @Published private(set) var lastRemoteBackupAt: Date?
    @Published private(set) var lastSyncAttemptAt: Date?
    @Published private(set) var isWorking = false

    private let service: ChartCloudSyncService?
    private weak var libraryStore: ChartLibraryStore?
    private var isSignedIn = false
    private var automaticUploadBackoff = ChartCloudAutomaticUploadBackoff()
    private var queuedUploadTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    init(service: ChartCloudSyncService?) {
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

    private func runRestore(snapshot: ChartLibrarySnapshot, service: ChartCloudSyncService) async {
        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing
        let startedAt = Date()
        IChartTelemetry.record(
            "cloud.restore_started",
            properties: [
                "chart_count": .int(snapshot.charts.count),
                "result": .string("started")
            ]
        )

        do {
            let result = try await service.restoreFromCloud(localSnapshot: snapshot)
            if let libraryStore {
                let didApplySyncedSnapshot = libraryStore.applySyncedSnapshot(
                    result.snapshot,
                    ifUnchangedFrom: snapshot
                )
                if !didApplySyncedSnapshot {
                    queueUpload(libraryStore.snapshot)
                }
            }
            lastRemoteBackupAt = result.lastRemoteBackupAt
            if queuedUploadTask == nil {
                state = .synced(Date())
            }
            IChartTelemetry.record(
                "cloud.restore_succeeded",
                properties: [
                    "chart_count": .int(result.snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "result": .string("synced")
                ]
            )
        } catch {
            state = Self.failureState(for: error)
            IChartTelemetry.record(
                "cloud.restore_failed",
                properties: [
                    "chart_count": .int(snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "error_code": .string(Self.telemetryErrorCode(for: state)),
                    "result": .string("failed")
                ]
            )
        }

        isWorking = false
    }

    private func runPush(snapshot: ChartLibrarySnapshot, service: ChartCloudSyncService) async {
        queuedUploadTask = nil
        guard !isWorking else {
            queueUpload(snapshot)
            return
        }

        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing
        let startedAt = Date()
        IChartTelemetry.record(
            "cloud.push_started",
            properties: [
                "chart_count": .int(snapshot.charts.count),
                "result": .string("started")
            ]
        )

        do {
            let result = try await service.pushLocalSnapshot(snapshot)
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
            state = .synced(Date())
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
            state = Self.failureState(for: error)
            IChartTelemetry.record(
                "cloud.push_failed",
                properties: [
                    "chart_count": .int(snapshot.charts.count),
                    "duration_ms": .double(Date().timeIntervalSince(startedAt) * 1_000),
                    "error_code": .string(Self.telemetryErrorCode(for: state)),
                    "result": .string("failed")
                ]
            )
        }

        isWorking = false
    }

    private func cancelPendingSyncWork() {
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

    nonisolated static func failureState(for error: Error) -> ChartSyncState {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost].contains(urlError.code) {
            return .offline
        }

        if let postgrestError = error as? PostgrestError {
            let text = normalizedErrorText(
                postgrestError.message,
                postgrestError.detail,
                postgrestError.hint,
                postgrestError.code
            )
            return failureState(forNormalizedText: text)
        }

        if let authError = error as? AuthError {
            return failureState(forNormalizedText: normalizedErrorText(authError.localizedDescription))
        }

        return failureState(forNormalizedText: normalizedErrorText(error.localizedDescription))
    }

    private nonisolated static func telemetryErrorCode(for state: ChartSyncState) -> String {
        switch state {
        case .offline:
            return "offline"
        case .requiresPro:
            return "requires_pro"
        case .unconfigured:
            return "unconfigured"
        case .signedOut:
            return "signed_out"
        default:
            return "sync_error"
        }
    }

    private nonisolated static func failureState(forNormalizedText text: String) -> ChartSyncState {
        if text.contains("not connected")
            || text.contains("network connection")
            || text.contains("cannot find host")
            || text.contains("cannot connect") {
            return .offline
        }

        if text.contains("missing session")
            || text.contains("session missing")
            || text.contains("session expired")
            || text.contains("auth session")
            || text.contains("jwt")
            || text.contains("401")
            || text.contains("authorization") {
            return .failed("Sign in again to resume cloud backup.")
        }

        if text.contains("permission denied")
            || text.contains("row-level security")
            || text.contains("rls")
            || text.contains("403") {
            return .failed("Cloud permissions blocked backup. Sign in again, then retry.")
        }

        return .failed("We could not finish cloud backup. Retry when you are online.")
    }

    private nonisolated static func normalizedErrorText(_ values: String?...) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
