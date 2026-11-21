import Combine
import Foundation

enum IChartPDFSetlistStoreError: LocalizedError, Equatable {
    case emptyName
    case setlistNotFound
    case entryNotFound
    case invalidOffsets
    case unreadableManifest(String)
    case unsupportedVersion(Int)
    case duplicateIdentifiers

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a name for the setlist."
        case .setlistNotFound:
            return "This setlist is no longer available."
        case .entryNotFound:
            return "This song is no longer in the setlist."
        case .invalidOffsets:
            return "The song order changed. Try again."
        case .unreadableManifest(let message):
            return "Saved setlists could not be read. Reload before making changes. \(message)"
        case .unsupportedVersion:
            return "These setlists were saved by an unsupported app version."
        case .duplicateIdentifiers:
            return "The saved setlists contain duplicate identifiers."
        }
    }
}

@MainActor
final class IChartPDFSetlistStore: ObservableObject {
    @Published private(set) var setlists: [IChartPDFSetlist]
    @Published private(set) var loadError: String?
    var onSaved: (() -> Void)?
    var automaticCloudOwnerID: UUID?
    private(set) var cloudOwners: [UUID: UUID] = [:]
    private(set) var cloudCheckpoints: [UUID: IChartPDFSetlistCloudCheckpoint] = [:]
    private var unavailableCloudMetadata: [String: IChartJSONValue]?
    var cloudMetadataUnavailable: Bool { unavailableCloudMetadata != nil }

    private struct Manifest: Codable {
        var version: Int
        var setlists: [IChartPDFSetlist]
        var cloudOwners: [UUID: UUID]?
        var cloudCheckpoints: [UUID: IChartPDFSetlistCloudCheckpoint]?
        var rawMetadata: [String: IChartJSONValue]?

        enum CodingKeys: String, CodingKey { case version, setlists, cloudOwners, cloudCheckpoints }

        init(version: Int, setlists: [IChartPDFSetlist], cloudOwners: [UUID: UUID]?,
            cloudCheckpoints: [UUID: IChartPDFSetlistCloudCheckpoint]?, rawMetadata: [String: IChartJSONValue]? = nil) {
            self.version = version
            self.setlists = setlists
            self.cloudOwners = cloudOwners
            self.cloudCheckpoints = cloudCheckpoints
            self.rawMetadata = rawMetadata
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decode(Int.self, forKey: .version)
            setlists = try values.decode([IChartPDFSetlist].self, forKey: .setlists)
            do {
                cloudOwners = try values.decodeIfPresent([UUID: UUID].self, forKey: .cloudOwners)
                cloudCheckpoints = try values.decodeIfPresent([UUID: IChartPDFSetlistCloudCheckpoint].self,
                    forKey: .cloudCheckpoints)
                for checkpoint in (cloudCheckpoints ?? [:]).values {
                    guard checkpoint.revision > 0 else { throw IChartPDFSetlistCloudError.invalidBackup }
                    try IChartPDFSetlistCloudValidation.validate(.init(setlists: checkpoint.setlists, pdfs: checkpoint.pdfs))
                }
            } catch {
                // Optional sync metadata cannot make offline setlists unreadable.
                // Retain it verbatim as JSON while local editing remains available.
                var raw: [String: IChartJSONValue] = [:]
                for key in [CodingKeys.cloudOwners, .cloudCheckpoints] where values.contains(key) {
                    raw[key.rawValue] = try values.decode(IChartJSONValue.self, forKey: key)
                }
                rawMetadata = raw
                cloudOwners = nil
                cloudCheckpoints = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(version, forKey: .version)
            try values.encode(setlists, forKey: .setlists)
            if let rawMetadata {
                for key in [CodingKeys.cloudOwners, .cloudCheckpoints] {
                    if let raw = rawMetadata[key.rawValue] { try values.encode(raw, forKey: key) }
                }
            } else {
                try values.encodeIfPresent(cloudOwners, forKey: .cloudOwners)
                try values.encodeIfPresent(cloudCheckpoints, forKey: .cloudCheckpoints)
            }
        }
    }

    private let baseDirectory: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let writeManifest: (Data, URL) throws -> Void

    init(
        baseDirectory: URL,
        fileManager: FileManager = .default,
        writeManifest: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.baseDirectory = baseDirectory
        self.manifestURL = baseDirectory.appendingPathComponent("pdf-setlists.json", isDirectory: false)
        self.fileManager = fileManager
        self.writeManifest = writeManifest
        self.setlists = []
        self.loadError = nil
        do {
            let loaded = try Self.loadManifest(from: manifestURL, fileManager: fileManager)
            setlists = loaded.setlists
            cloudOwners = loaded.cloudOwners ?? [:]
            cloudCheckpoints = loaded.cloudCheckpoints ?? [:]
            unavailableCloudMetadata = loaded.rawMetadata
        } catch {
            loadError = error.localizedDescription
        }
    }

    static func live(fileManager: FileManager = .default) -> IChartPDFSetlistStore {
        let applicationSupportURL = IChartStorageNamespace.applicationSupportDirectory(fileManager: fileManager)
        let baseDirectory = applicationSupportURL
            .appendingPathComponent("iChart", isDirectory: true)
            .appendingPathComponent("Setlists", isDirectory: true)
        return IChartPDFSetlistStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    func setlist(id: UUID) -> IChartPDFSetlist? {
        setlists.first { $0.id == id }
    }

    @discardableResult
    func create(name: String, pdfItems: [IChartPDFLibraryItem] = []) throws -> IChartPDFSetlist {
        try requireLoadedManifest()
        let name = try normalizedName(name)
        let date = Date()
        let setlist = IChartPDFSetlist(name: name, entries: Self.entries(for: pdfItems), createdAt: date, updatedAt: date)
        var candidate = setlists
        candidate.insert(setlist, at: 0)
        var owners = cloudOwners
        if let automaticCloudOwnerID { owners[setlist.id] = automaticCloudOwnerID }
        try commit(candidate, owners: owners)
        return setlist
    }

    func rename(setlistID: UUID, to name: String) throws {
        let name = try normalizedName(name)
        try update(setlistID: setlistID) { $0.name = name }
    }

    func delete(setlistID: UUID) throws {
        try requireLoadedManifest()
        guard setlists.contains(where: { $0.id == setlistID }) else {
            throw IChartPDFSetlistStoreError.setlistNotFound
        }
        try commit(setlists.filter { $0.id != setlistID })
    }

    @discardableResult
    func add(pdfItem: IChartPDFLibraryItem, to setlistID: UUID) throws -> IChartPDFSetlistEntry {
        try add(pdfItems: [pdfItem], to: setlistID)[0]
    }

    @discardableResult
    func add(pdfItems: [IChartPDFLibraryItem], to setlistID: UUID) throws -> [IChartPDFSetlistEntry] {
        let entries = Self.entries(for: pdfItems)
        try update(setlistID: setlistID) { $0.entries.append(contentsOf: entries) }
        return entries
    }

    /// Replacing a song changes only the selected reference, preserving its
    /// position and identity. The original PDF remains in the PDF Library.
    func replace(entryID: UUID, in setlistID: UUID, with pdfItem: IChartPDFLibraryItem) throws {
        try update(setlistID: setlistID) { setlist in
            guard let index = setlist.entries.firstIndex(where: { $0.id == entryID }) else {
                throw IChartPDFSetlistStoreError.entryNotFound
            }
            let replacement = Self.entries(for: [pdfItem])[0]
            setlist.entries[index] = IChartPDFSetlistEntry(
                id: entryID, pdfItemID: replacement.pdfItemID, displayTitle: replacement.displayTitle
            )
        }
    }

    private static func entries(for pdfItems: [IChartPDFLibraryItem]) -> [IChartPDFSetlistEntry] {
        pdfItems.map { item in
            let title = item.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return IChartPDFSetlistEntry(
                pdfItemID: item.id,
                displayTitle: title.isEmpty ? "Untitled PDF" : item.displayTitle
            )
        }
    }

    func remove(entryID: UUID, from setlistID: UUID) throws {
        try update(setlistID: setlistID) { setlist in
            guard setlist.entries.contains(where: { $0.id == entryID }) else {
                throw IChartPDFSetlistStoreError.entryNotFound
            }
            setlist.entries.removeAll { $0.id == entryID }
        }
    }

    func removeEntries(at offsets: IndexSet, from setlistID: UUID) throws {
        try update(setlistID: setlistID) { setlist in
            guard offsets.allSatisfy({ setlist.entries.indices.contains($0) }) else {
                throw IChartPDFSetlistStoreError.invalidOffsets
            }
            setlist.entries = setlist.entries.enumerated().compactMap { index, entry in
                offsets.contains(index) ? nil : entry
            }
        }
    }

    func moveEntries(in setlistID: UUID, fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        try update(setlistID: setlistID) { setlist in
            guard (0...setlist.entries.count).contains(destination),
                  offsets.allSatisfy({ setlist.entries.indices.contains($0) }) else {
                throw IChartPDFSetlistStoreError.invalidOffsets
            }
            let movingEntries = offsets.map { setlist.entries[$0] }
            var remainingEntries = setlist.entries.enumerated().compactMap { index, entry in
                offsets.contains(index) ? nil : entry
            }
            let insertionIndex = destination - offsets.filter { $0 < destination }.count
            remainingEntries.insert(contentsOf: movingEntries, at: insertionIndex)
            setlist.entries = remainingEntries
        }
    }

    func reload() throws {
        do {
            let loaded = try Self.loadManifest(from: manifestURL, fileManager: fileManager)
            if setlists != loaded.setlists { setlists = loaded.setlists }
            cloudOwners = loaded.cloudOwners ?? [:]
            cloudCheckpoints = loaded.cloudCheckpoints ?? [:]
            unavailableCloudMetadata = loaded.rawMetadata
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            throw error
        }
    }

    private func update(setlistID: UUID, mutation: (inout IChartPDFSetlist) throws -> Void) throws {
        try requireLoadedManifest()
        guard let index = setlists.firstIndex(where: { $0.id == setlistID }) else {
            throw IChartPDFSetlistStoreError.setlistNotFound
        }
        var candidate = setlists
        try mutation(&candidate[index])
        guard candidate != setlists else { return }
        candidate[index].updatedAt = Date()
        try commit(candidate)
    }

    func cloudSetlists(for ownerID: UUID, enrollingUnowned: Bool) -> [IChartPDFSetlist] {
        setlists.filter { cloudOwners[$0.id] == ownerID || (enrollingUnowned && cloudOwners[$0.id] == nil) }
    }

    func applyCloudMerge(_ merged: [IChartPDFSetlist], ownerID: UUID,
        checkpoint: IChartPDFSetlistCloudCheckpoint, expectedLocal: [IChartPDFSetlist]) throws {
        try requireLoadedManifest()
        guard !cloudMetadataUnavailable else { throw IChartPDFSetlistCloudError.invalidBackup }
        guard setlists == expectedLocal else { throw CocoaError(.fileWriteFileExists) }
        let ownedIDs = Set(cloudSetlists(for: ownerID, enrollingUnowned: false).map(\.id)).union(merged.map(\.id))
        let unrelated = setlists.filter { !ownedIDs.contains($0.id) }
        guard Set(merged.map(\.id)).count == merged.count,
              merged.allSatisfy({ cloudOwners[$0.id] == nil || cloudOwners[$0.id] == ownerID }),
              Set(unrelated.map(\.id)).isDisjoint(with: Set(merged.map(\.id))) else {
            throw IChartPDFSetlistStoreError.duplicateIdentifiers
        }
        var owners = cloudOwners
        for list in merged { owners[list.id] = ownerID }
        var checkpoints = cloudCheckpoints
        checkpoints[ownerID] = checkpoint
        try commit(unrelated + merged, owners: owners, checkpoints: checkpoints)
    }

    private func commit(_ candidate: [IChartPDFSetlist], owners: [UUID: UUID]? = nil,
        checkpoints: [UUID: IChartPDFSetlistCloudCheckpoint]? = nil) throws {
        let nextOwners = owners ?? cloudOwners
        let nextCheckpoints = checkpoints ?? cloudCheckpoints
        let data = try ChartPersistenceCoders.encoder.encode(Manifest(version: 1, setlists: candidate,
            cloudOwners: nextOwners.isEmpty ? nil : nextOwners,
            cloudCheckpoints: nextCheckpoints.isEmpty ? nil : nextCheckpoints,
            rawMetadata: unavailableCloudMetadata))
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try writeManifest(data, manifestURL)
        // Setlists refer to existing PDF IDs. Only this manifest is written;
        // deleting a setlist or entry never deletes or modifies a PDF file.
        setlists = candidate
        cloudOwners = nextOwners
        cloudCheckpoints = nextCheckpoints
        onSaved?()
    }

    private func requireLoadedManifest() throws {
        if let loadError {
            throw IChartPDFSetlistStoreError.unreadableManifest(loadError)
        }
    }

    private func normalizedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw IChartPDFSetlistStoreError.emptyName }
        return name
    }

    private static func loadManifest(from url: URL, fileManager: FileManager) throws -> Manifest {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return Manifest(version: 1, setlists: [], cloudOwners: nil, cloudCheckpoints: nil)
        }
        let manifest = try ChartPersistenceCoders.decoder.decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1 else { throw IChartPDFSetlistStoreError.unsupportedVersion(manifest.version) }
        guard Set(manifest.setlists.map(\.id)).count == manifest.setlists.count,
              manifest.setlists.allSatisfy({ Set($0.entries.map(\.id)).count == $0.entries.count }) else {
            throw IChartPDFSetlistStoreError.duplicateIdentifiers
        }
        return manifest
    }
}
