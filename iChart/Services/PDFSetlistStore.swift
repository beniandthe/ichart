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

    private struct Manifest: Codable {
        var version: Int
        var setlists: [IChartPDFSetlist]
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
            setlists = try Self.load(from: manifestURL, fileManager: fileManager)
        } catch {
            loadError = error.localizedDescription
        }
    }

    static func live(fileManager: FileManager = .default) -> IChartPDFSetlistStore {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let baseDirectory = applicationSupportURL
            .appendingPathComponent("iChart", isDirectory: true)
            .appendingPathComponent("Setlists", isDirectory: true)
        return IChartPDFSetlistStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    func setlist(id: UUID) -> IChartPDFSetlist? {
        setlists.first { $0.id == id }
    }

    @discardableResult
    func create(name: String) throws -> IChartPDFSetlist {
        try requireLoadedManifest()
        let name = try normalizedName(name)
        let date = Date()
        let setlist = IChartPDFSetlist(name: name, createdAt: date, updatedAt: date)
        var candidate = setlists
        candidate.insert(setlist, at: 0)
        try commit(candidate)
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
        let entries = pdfItems.map { item in
            let title = item.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return IChartPDFSetlistEntry(
                pdfItemID: item.id,
                displayTitle: title.isEmpty ? "Untitled PDF" : item.displayTitle
            )
        }
        try update(setlistID: setlistID) { $0.entries.append(contentsOf: entries) }
        return entries
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
            let loaded = try Self.load(from: manifestURL, fileManager: fileManager)
            if setlists != loaded {
                setlists = loaded
            }
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

    private func commit(_ candidate: [IChartPDFSetlist]) throws {
        let data = try ChartPersistenceCoders.encoder.encode(Manifest(version: 1, setlists: candidate))
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try writeManifest(data, manifestURL)
        // Setlists refer to existing PDF IDs. Only this manifest is written;
        // deleting a setlist or entry never deletes or modifies a PDF file.
        setlists = candidate
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

    private static func load(from url: URL, fileManager: FileManager) throws -> [IChartPDFSetlist] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        let manifest = try ChartPersistenceCoders.decoder.decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1 else { throw IChartPDFSetlistStoreError.unsupportedVersion(manifest.version) }
        guard Set(manifest.setlists.map(\.id)).count == manifest.setlists.count,
              manifest.setlists.allSatisfy({ Set($0.entries.map(\.id)).count == $0.entries.count }) else {
            throw IChartPDFSetlistStoreError.duplicateIdentifiers
        }
        return manifest.setlists
    }
}
