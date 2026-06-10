import Foundation

@MainActor
final class ChartCloudSyncStore: ObservableObject {
    @Published private(set) var state: ChartSyncState
    @Published private(set) var lastRemoteBackupAt: Date?
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
            state = .unconfigured
            isSignedIn = false
            return
        }

        switch authState {
        case .signedIn:
            isSignedIn = true
            syncNow()
        case .unconfigured:
            isSignedIn = false
            state = .unconfigured
        case .signedOut, .pendingEmailVerification:
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
        state = .syncing

        do {
            let result = try await service.syncNow(localSnapshot: snapshot)
            libraryStore?.applySyncedSnapshot(result.snapshot)
            lastRemoteBackupAt = result.lastRemoteBackupAt
            state = .synced(Date())
        } catch {
            state = syncFailureState(for: error)
        }

        isWorking = false
    }

    private func runPush(snapshot: ChartLibrarySnapshot, service: ChartCloudSyncService) async {
        guard !isWorking else {
            queueUpload(snapshot)
            return
        }

        isWorking = true
        state = .syncing

        do {
            let backupAt = try await service.pushLocalSnapshot(snapshot)
            libraryStore?.updateCloudMetadataFromSync(lastSyncAt: Date(), lastRemoteBackupAt: backupAt)
            lastRemoteBackupAt = backupAt
            state = .synced(Date())
        } catch {
            state = syncFailureState(for: error)
        }

        isWorking = false
    }

    private func syncFailureState(for error: Error) -> ChartSyncState {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost].contains(urlError.code) {
            return .offline
        }

        return .failed(error.localizedDescription)
    }
}
