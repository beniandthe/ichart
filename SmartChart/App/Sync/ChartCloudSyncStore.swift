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
                    sessionProvider: $0.sessionStore
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
                self?.queueUpload(snapshot)
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
        case .signedIn:
            isSignedIn = true
            syncNow()
        case .temporarilyOffline:
            cancelPendingSyncWork()
            isSignedIn = true
            state = .offline
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

    func syncNow() {
        guard isSignedIn, let service, let libraryStore else {
            state = service == nil ? .unconfigured : .signedOut
            return
        }

        queuedUploadTask?.cancel()
        syncTask?.cancel()
        let snapshot = libraryStore.snapshot
        syncTask = Task { [weak self] in
            await self?.runFullSync(snapshot: snapshot, service: service)
        }
    }

    private func queueUpload(_ snapshot: ChartLibrarySnapshot) {
        guard isSignedIn, let service else {
            return
        }

        queuedUploadTask?.cancel()
        queuedUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.runPush(snapshot: snapshot, service: service)
        }
    }

    private func runFullSync(snapshot: ChartLibrarySnapshot, service: ChartCloudSyncService) async {
        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing

        do {
            let result = try await service.syncNow(localSnapshot: snapshot)
            libraryStore?.applySyncedSnapshot(result.snapshot)
            lastRemoteBackupAt = result.lastRemoteBackupAt
            state = .synced(Date())
        } catch {
            state = Self.failureState(for: error)
        }

        isWorking = false
    }

    private func runPush(snapshot: ChartLibrarySnapshot, service: ChartCloudSyncService) async {
        guard !isWorking else {
            queueUpload(snapshot)
            return
        }

        isWorking = true
        lastSyncAttemptAt = Date()
        state = .syncing

        do {
            let backupAt = try await service.pushLocalSnapshot(snapshot)
            libraryStore?.updateCloudMetadataFromSync(lastSyncAt: Date(), lastRemoteBackupAt: backupAt)
            lastRemoteBackupAt = backupAt
            state = .synced(Date())
        } catch {
            state = Self.failureState(for: error)
        }

        isWorking = false
    }

    private func cancelPendingSyncWork() {
        queuedUploadTask?.cancel()
        queuedUploadTask = nil
        syncTask?.cancel()
        syncTask = nil
        isWorking = false
    }

    nonisolated static func failureState(for error: Error) -> ChartSyncState {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost].contains(urlError.code) {
            return .offline
        }

        if error is IChartSupabaseSessionError {
            return .failed("Sign in again to resume cloud backup.")
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

        return .failed("We could not finish cloud backup. Retry when you are ready.")
    }

    private nonisolated static func normalizedErrorText(_ values: String?...) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
