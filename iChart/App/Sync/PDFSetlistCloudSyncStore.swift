import Combine
import Foundation
import SwiftUI

@MainActor
final class IChartPDFSetlistCloudSyncStore: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Setlists and PDFs are saved on this device."
    @Published private(set) var pendingConflict = false
    @Published private(set) var canSync = false
    @Published private(set) var isOnline = false
    @Published private(set) var isSignedIn = false

    private let service: (any IChartPDFSetlistCloudServicing)?
    private weak var setlistStore: IChartPDFSetlistStore?
    private weak var pdfStore: IChartPDFLibraryStore?
    private var ownerID: UUID?
    private var generation = 0
    private var task: Task<Void, Never>?
    private var pending: Pending?
    private var applyingMerge = false

    private struct Pending {
        var ownerID: UUID
        var generation: Int
        var localSnapshot: [IChartPDFSetlist]
        var pdfSnapshot: [IChartPDFLibraryItem]
        var merge: IChartPDFSetlistCloudMerge
        var remote: IChartPDFSetlistCloudEnvelope
    }

    init(service: (any IChartPDFSetlistCloudServicing)?) { self.service = service }

    static func live(clients: IChartSupabaseClients?) -> IChartPDFSetlistCloudSyncStore {
        IChartPDFSetlistCloudSyncStore(service: clients.map {
            IChartPDFSetlistCloudService(client: $0.dataClient,
                sessionRefresher: IChartSupabaseSessionRefresher(authClient: $0.authClient,
                    sessionStore: $0.sessionStore))
        })
    }

    func attach(setlistStore: IChartPDFSetlistStore, pdfStore: IChartPDFLibraryStore) {
        guard self.setlistStore !== setlistStore || self.pdfStore !== pdfStore else { return }
        invalidate()
        self.setlistStore = setlistStore
        self.pdfStore = pdfStore
        setlistStore.onSaved = { [weak self] in self?.scheduleAutomaticSync() }
        updateAutomaticOwner()
    }

    func updateAccess(ownerID: UUID?, canSync: Bool, isOnline: Bool = true) {
        guard self.ownerID != ownerID || self.canSync != canSync || self.isOnline != isOnline else { return }
        invalidate()
        self.ownerID = ownerID
        self.canSync = canSync
        self.isOnline = isOnline
        isSignedIn = ownerID != nil
        updateAutomaticOwner()
        if service == nil { status = "Setlist cloud service is unavailable. Local setlists are available." }
        else if ownerID == nil { status = "Sign in to back up setlists and their PDFs with Pro." }
        else if !canSync { status = "Pro adds cloud backup and sync. Your local setlists and PDFs are available." }
        else if !isOnline { status = "Offline. Your setlist edits are saved on this device." }
        else { status = "Back up local setlists or restore this account’s setlists." }
        scheduleAutomaticSync()
    }

    func backUpNow() { start(enrollingUnowned: true) }
    func restoreFromCloud() { start(enrollingUnowned: false) }

    func resolveConflicts(_ resolution: IChartPDFSetlistCloudMerge.Resolution) {
        guard let pending, authorized(pending), let service else { return }
        self.pending = nil
        pendingConflict = false
        isWorking = true
        task = Task { [weak self] in
            await self?.complete(pending, resolution: resolution, service: service)
        }
    }

    func dismissConflictPresentation() { pendingConflict = false }

    func cancelConflict() {
        pending = nil
        pendingConflict = false
        status = "Local setlists are available. Sync again when you are ready to resolve the versions."
    }

    private func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
        pending = nil
        pendingConflict = false
        isWorking = false
    }

    private func updateAutomaticOwner() {
        guard let ownerID, canSync, setlistStore?.cloudCheckpoints[ownerID] != nil else {
            setlistStore?.automaticCloudOwnerID = nil
            return
        }
        setlistStore?.automaticCloudOwnerID = ownerID
    }

    private func authorized(_ pending: Pending) -> Bool {
        !Task.isCancelled && ownerID == pending.ownerID && generation == pending.generation
            && canSync && isOnline
    }

    private func scheduleAutomaticSync() {
        guard !applyingMerge, !isWorking, !pendingConflict, let ownerID, canSync, isOnline,
              setlistStore?.cloudCheckpoints[ownerID] != nil else { return }
        task?.cancel()
        let expectedGeneration = generation
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.start(enrollingUnowned: false)
        }
    }

    private func start(enrollingUnowned: Bool) {
        guard !isWorking, let service, let ownerID, canSync, isOnline,
              let lists = setlistStore, let pdfs = pdfStore else { return }
        guard !lists.cloudMetadataUnavailable else {
            status = "Setlist sync metadata needs recovery. Your local setlists and PDFs remain available."
            return
        }
        guard lists.loadError == nil, pdfs.recoveryErrorMessage == nil else {
            status = "Reload your local setlists and PDF library before syncing."
            return
        }
        task?.cancel()
        pending = nil
        pendingConflict = false
        isWorking = true
        status = "Checking cloud setlists…"
        let expectedGeneration = generation
        let localSnapshot = lists.setlists
        let pdfSnapshot = pdfs.items
        let local = lists.cloudSetlists(for: ownerID, enrollingUnowned: enrollingUnowned)
        let baseline = lists.cloudCheckpoints[ownerID]?.setlists ?? []
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let remote = try await service.fetch(ownerID: ownerID)
                let remoteLists = remote.manifest?.setlists ?? []
                // A colliding unowned local identifier is a conflict to review,
                // and does not silently become this account's remote version.
                let localIDs = Set(local.map(\.id))
                let remoteIDs = Set(remoteLists.map(\.id))
                let collisions = localSnapshot.filter {
                    lists.cloudOwners[$0.id] == nil && remoteIDs.contains($0.id) && !localIDs.contains($0.id)
                }
                let pending = Pending(ownerID: ownerID, generation: expectedGeneration, localSnapshot: localSnapshot,
                    pdfSnapshot: pdfSnapshot, merge: .init(local: local + collisions, remote: remoteLists, baseline: baseline), remote: remote)
                guard self.authorized(pending) else { return }
                guard lists.setlists == localSnapshot else { throw IChartPDFSetlistCloudError.newerLocalChanges }
                if !pending.merge.conflictingIDs.isEmpty {
                    self.pending = pending
                    self.pendingConflict = true
                    self.isWorking = false
                    self.status = "Local and cloud versions changed. Choose which versions to keep."
                } else {
                    await self.complete(pending, resolution: .local, service: service)
                }
            } catch {
                self.finishFailure(error, generation: expectedGeneration)
            }
        }
    }

    private func complete(_ pending: Pending, resolution: IChartPDFSetlistCloudMerge.Resolution,
        service: any IChartPDFSetlistCloudServicing) async {
        do {
            guard authorized(pending), let lists = setlistStore, let library = pdfStore else { return }
            guard lists.setlists == pending.localSnapshot, library.items == pending.pdfSnapshot else {
                throw IChartPDFSetlistCloudError.newerLocalChanges
            }
            let merged = pending.merge.resolved(resolution)
            let neededIDs = Set(merged.flatMap(\.entries).map(\.pdfItemID))
            let remotePDFs = Dictionary(uniqueKeysWithValues: (pending.remote.manifest?.pdfs ?? []).map { ($0.item.id, $0) })
            var metadata: [IChartPDFSetlistCloudPDF] = []
            let staging = IChartStorageNamespace.temporaryDirectory().appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var filesByID: [UUID: URL] = [:]
            var downloadedPDFs: [IChartPDFSetlistCloudPDF] = []
            var downloadedFiles: [UUID: URL] = [:]
            for id in neededIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                try Task.checkCancellation()
                if let item = library.items.first(where: { $0.id == id }), let file = library.exportedPDF(for: item) {
                    let staged = try await IChartPDFSetlistCloudFiles.stageLocal(item, from: file.url, in: staging)
                    guard authorized(pending) else { return }
                    let pdf = staged.pdf
                    if let remote = remotePDFs[id] {
                        guard remote.sha256 == pdf.sha256, remote.item.source == item.source else {
                            throw IChartPDFSetlistCloudError.invalidBackup
                        }
                        // A restore may rename the local file to avoid a name
                        // collision. Keep the account's published metadata so
                        // syncing another device cannot churn its manifest.
                        metadata.append(remote)
                    } else {
                        metadata.append(pdf)
                    }
                    filesByID[id] = staged.file
                } else if let pdf = remotePDFs[id] {
                    status = "Downloading linked PDFs…"
                    let data = try await service.download(pdf, ownerID: pending.ownerID)
                    guard authorized(pending) else { return }
                    let file = try await IChartPDFSetlistCloudFiles.stageDownload(data, for: pdf, in: staging)
                    guard authorized(pending) else { return }
                    metadata.append(pdf)
                    downloadedPDFs.append(pdf)
                    downloadedFiles[id] = file
                    filesByID[id] = file
                } else { throw IChartPDFSetlistCloudError.missingPDF }
            }
            guard merged.allSatisfy({ lists.cloudOwners[$0.id] == nil || lists.cloudOwners[$0.id] == pending.ownerID }) else {
                throw IChartPDFSetlistCloudError.accountChanged
            }
            let document = IChartPDFSetlistCloudDocument(setlists: merged, pdfs: metadata)
            try IChartPDFSetlistCloudValidation.validate(document)
            let uploadedHashes = Set((pending.remote.manifest?.pdfs ?? []).map(\.sha256))
            for pdf in metadata where !uploadedHashes.contains(pdf.sha256) {
                guard authorized(pending), lists.setlists == pending.localSnapshot,
                      library.items == pending.pdfSnapshot else {
                    throw IChartPDFSetlistCloudError.newerLocalChanges
                }
                status = "Backing up linked PDFs…"
                guard let file = filesByID[pdf.item.id] else { throw IChartPDFSetlistCloudError.missingPDF }
                let data = try await IChartPDFSetlistCloudFiles.read(file)
                guard authorized(pending) else { return }
                try await service.upload(pdf, data: data, ownerID: pending.ownerID)
            }
            guard authorized(pending), lists.setlists == pending.localSnapshot,
                      library.items == pending.pdfSnapshot else {
                throw IChartPDFSetlistCloudError.newerLocalChanges
            }
            status = "Saving cloud setlists…"
            let receipt: IChartPDFSetlistCloudEnvelope
            if pending.remote.manifest == document {
                receipt = pending.remote
            } else {
                receipt = try await service.commit(document, expectedVersion: pending.remote.version,
                    ownerID: pending.ownerID)
            }
            guard authorized(pending) else { return }
            guard lists.setlists == pending.localSnapshot, library.items == pending.pdfSnapshot else {
                throw IChartPDFSetlistCloudError.newerLocalChanges
            }
            // PDF bytes are validated and committed before references are
            // published. A later setlist write failure leaves recoverable PDFs.
            try library.mergeCloudItems(downloadedPDFs.map(\.item), files: downloadedFiles)
            applyingMerge = true
            defer { applyingMerge = false }
            try lists.applyCloudMerge(merged, ownerID: pending.ownerID,
                checkpoint: .init(revision: receipt.version, setlists: merged, pdfs: metadata),
                expectedLocal: pending.localSnapshot)
            updateAutomaticOwner()
            isWorking = false
            status = "Setlists and linked PDFs are backed up and available offline."
        } catch { finishFailure(error, generation: pending.generation) }
    }

    private func finishFailure(_ error: Error, generation expected: Int) {
        guard generation == expected, !Task.isCancelled else { return }
        isWorking = false
        status = error.localizedDescription
    }
}

private struct IChartPDFSetlistCloudEnvironmentKey: EnvironmentKey {
    static let defaultValue: IChartPDFSetlistCloudSyncStore? = nil
}

extension EnvironmentValues {
    var setlistCloudSyncStore: IChartPDFSetlistCloudSyncStore? {
        get { self[IChartPDFSetlistCloudEnvironmentKey.self] }
        set { self[IChartPDFSetlistCloudEnvironmentKey.self] = newValue }
    }
}


private enum IChartPDFSetlistCloudFiles {
    struct StagedPDF {
        let pdf: IChartPDFSetlistCloudPDF
        let file: URL
    }

    static func stageLocal(_ item: IChartPDFLibraryItem, from source: URL, in directory: URL) async throws -> StagedPDF {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: source)
            let pdf = IChartPDFSetlistCloudPDF(item: item, sha256: IChartPDFSetlistCloudValidation.digest(data))
            try IChartPDFSetlistCloudValidation.validate(data, for: pdf)
            let file = directory.appendingPathComponent(item.id.uuidString + ".pdf")
            try data.write(to: file, options: .atomic)
            return StagedPDF(pdf: pdf, file: file)
        }.value
    }

    static func stageDownload(_ data: Data, for pdf: IChartPDFSetlistCloudPDF, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try IChartPDFSetlistCloudValidation.validate(data, for: pdf)
            let file = directory.appendingPathComponent(pdf.item.id.uuidString + ".pdf")
            try data.write(to: file, options: .atomic)
            return file
        }.value
    }

    static func read(_ file: URL) async throws -> Data {
        try await Task.detached(priority: .utility) { try Data(contentsOf: file) }.value
    }
}
