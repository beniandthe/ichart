import Combine
import Foundation

enum IChartPDFLibrarySource: String, Codable, CaseIterable, Identifiable {
    case chartExport
    case forumDownload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chartExport:
            return "Exports"
        case .forumDownload:
            return "Forum Downloads"
        }
    }

    var itemTitle: String {
        switch self {
        case .chartExport:
            return "Chart Export"
        case .forumDownload:
            return "Forum Download"
        }
    }

    var emptyTitle: String {
        switch self {
        case .chartExport:
            return "No Exports Yet"
        case .forumDownload:
            return "No Forum Downloads Yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .chartExport:
            return "Export a chart as a PDF and it will land here."
        case .forumDownload:
            return "Download a forum chart PDF and it will land here."
        }
    }

    var systemImageName: String {
        switch self {
        case .chartExport:
            return "square.and.arrow.up"
        case .forumDownload:
            return "arrow.down.doc"
        }
    }

    var directoryName: String {
        switch self {
        case .chartExport:
            return "Exports"
        case .forumDownload:
            return "Forum Downloads"
        }
    }
}

struct IChartPDFLibraryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let source: IChartPDFLibrarySource
    let fileName: String
    let displayTitle: String
    let layoutStyle: ChartLayoutStyle
    let transpositionView: TranspositionView
    let chordTranspositionSemitones: Int
    let pageCount: Int
    let fileSizeBytes: Int
    let createdAt: Date
    let relativePath: String

    var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(fileSizeBytes),
            countStyle: .file
        )
    }

    var pageCountText: String {
        pageCount == 1 ? "1 page" : "\(pageCount) pages"
    }

    var transpositionText: String {
        guard chordTranspositionSemitones != 0 else {
            return transpositionView.displayText
        }

        return "\(transpositionView.displayText) · \(Chart.intervalDisplayText(forNormalizedSemitones: chordTranspositionSemitones))"
    }

    func url(relativeTo baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    func exportedPDF(relativeTo baseDirectory: URL) -> ExportedPDF {
        ExportedPDF(
            url: url(relativeTo: baseDirectory),
            chartTitle: displayTitle,
            layoutStyle: layoutStyle,
            transpositionView: transpositionView,
            chordTranspositionSemitones: chordTranspositionSemitones,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            exportedAt: createdAt
        )
    }
}

final class IChartPDFLibraryStore: ObservableObject {
    @Published private(set) var items: [IChartPDFLibraryItem]
    @Published private(set) var recoveryErrorMessage: String?

    private struct DeletionFile: Codable {
        var item: IChartPDFLibraryItem
        var stagedFileName: String
    }

    private struct DeletionTransaction: Codable {
        var itemIDs: [UUID]
        var files: [DeletionFile]
    }

    private let baseDirectory: URL
    private let manifestURL: URL
    private let fileManager: FileManager

    init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.manifestURL = baseDirectory.appendingPathComponent("pdf-library.json", isDirectory: false)
        self.fileManager = fileManager
        do {
            self.items = try Self.loadItems(from: manifestURL, fileManager: fileManager)
            self.recoveryErrorMessage = nil
        } catch {
            self.items = []
            self.recoveryErrorMessage = "Could not read the PDF library. \(error.localizedDescription)"
        }
        if recoveryErrorMessage == nil {
            recoverDeletionsAndPruneIfPossible()
        }
    }

    static func live(fileManager: FileManager = .default) -> IChartPDFLibraryStore {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL
            .appendingPathComponent("iChart", isDirectory: true)
            .appendingPathComponent("PDF Library", isDirectory: true)

        return IChartPDFLibraryStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    func items(for source: IChartPDFLibrarySource) -> [IChartPDFLibraryItem] {
        items.filter { $0.source == source }
    }

    func visibleItems(for subscription: IChartSubscriptionEntitlement) -> [IChartPDFLibraryItem] {
        guard subscription.allowsForumDownloadAccess else {
            return items.filter { $0.source != .forumDownload }
        }

        return items
    }

    func exportedPDF(for item: IChartPDFLibraryItem) -> ExportedPDF? {
        let url = item.url(relativeTo: baseDirectory)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        return item.exportedPDF(relativeTo: baseDirectory)
    }

    @discardableResult
    func save(_ exportedPDF: ExportedPDF, source: IChartPDFLibrarySource) throws -> ExportedPDF {
        if let recoveryErrorMessage {
            throw IChartPDFLibraryDeletionError.recoveryUnavailable(recoveryErrorMessage)
        }
        let directory = baseDirectory.appendingPathComponent(source.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = try uniqueFileName(
            preferredFileName: exportedPDF.fileName,
            fallbackTitle: exportedPDF.navigationTitle,
            in: directory
        )
        let destinationURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try copyPDF(from: exportedPDF.url, to: destinationURL)

        let relativePath = source.directoryName + "/" + fileName
        let item = IChartPDFLibraryItem(
            id: UUID(),
            source: source,
            fileName: fileName,
            displayTitle: exportedPDF.navigationTitle,
            layoutStyle: exportedPDF.layoutStyle,
            transpositionView: exportedPDF.transpositionView,
            chordTranspositionSemitones: exportedPDF.chordTranspositionSemitones,
            pageCount: exportedPDF.pageCount,
            fileSizeBytes: exportedPDF.fileSizeBytes,
            createdAt: Date(),
            relativePath: relativePath
        )

        items.insert(item, at: 0)
        sortItems()
        try persist()

        return item.exportedPDF(relativeTo: baseDirectory)
    }

    @discardableResult
    func delete(_ item: IChartPDFLibraryItem) throws -> Int {
        try deleteItems(ids: [item.id])
    }

    /// The confirmed IDs are a fixed target snapshot. New or unselected items
    /// cannot join a deletion because the library was filtered or reloaded.
    @discardableResult
    func deleteItems(ids itemIDs: Set<IChartPDFLibraryItem.ID>) throws -> Int {
        guard !itemIDs.isEmpty else { return 0 }
        do {
            guard fileManager.fileExists(atPath: manifestURL.path) || items.isEmpty else {
                throw IChartPDFLibraryDeletionError.manifestUnavailable
            }
            // A second store may have saved new items since confirmation.
            // Current disk state is the authority; only confirmed IDs join it.
            let persistedItems = try Self.loadItems(from: manifestURL, fileManager: fileManager)
            items = persistedItems
        } catch {
            recoveryErrorMessage = "Could not read the PDF library. \(error.localizedDescription)"
            throw error
        }
        do {
            try validateDeletionDirectory()
            try recoverPendingDeletions()
            recoveryErrorMessage = nil
        } catch {
            recoveryErrorMessage = error.localizedDescription
            throw error
        }

        let removedItems = items.filter { itemIDs.contains($0.id) }
        guard !removedItems.isEmpty else { return 0 }
        let remainingItems = items.filter { !itemIDs.contains($0.id) }
        let remainingPaths = Set(remainingItems.map {
            $0.url(relativeTo: baseDirectory).standardizedFileURL.resolvingSymlinksInPath().path
        })
        var seenPaths = Set<String>()
        var files = [DeletionFile]()
        for item in removedItems {
            let url = try validatedLibraryURL(for: item)
            let resolvedPath = url.resolvingSymlinksInPath().path
            guard !remainingPaths.contains(resolvedPath) else {
                throw IChartPDFLibraryDeletionError.sharedFile(item.fileName)
            }
            guard seenPaths.insert(url.path).inserted,
                  fileManager.fileExists(atPath: url.path) else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw IChartPDFLibraryDeletionError.invalidFile(item.fileName)
            }
            files.append(DeletionFile(item: item, stagedFileName: "\(item.id.uuidString).pdf"))
        }

        let transaction = DeletionTransaction(itemIDs: removedItems.map(\.id), files: files)
        let directory = deletionDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let journal = try ChartPersistenceCoders.encoder.encode(transaction)
            try journal.write(to: directory.appendingPathComponent("transaction.json"), options: .atomic)
            for file in files {
                try fileManager.moveItem(
                    at: validatedLibraryURL(for: file.item),
                    to: directory.appendingPathComponent(file.stagedFileName)
                )
            }
            // Keep the published library unchanged until its complete new
            // manifest is durable. A failed write restores every staged file.
            try persist(remainingItems)
        } catch {
            do {
                try restoreDeletionFiles(transaction, from: directory)
                try fileManager.removeItem(at: directory)
            } catch let recoveryError {
                let failure = IChartPDFLibraryDeletionError.recoveryFailed(
                    operation: error.localizedDescription,
                    recovery: recoveryError.localizedDescription,
                    directory: directory.path
                )
                recoveryErrorMessage = failure.localizedDescription
                throw failure
            }
            throw error
        }

        items = remainingItems
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            // The whole deletion has committed; the journal lets a later
            // recovery retry removal of temporary copies without restoring it.
            throw IChartPDFLibraryDeletionError.cleanupFailed(
                count: removedItems.count, message: error.localizedDescription
            )
        }
        return removedItems.count
    }

    @discardableResult
    func removeForumDownloadsIfInactive(for subscription: IChartSubscriptionEntitlement) -> Int {
        guard recoveryErrorMessage == nil, subscription.shouldRemoveForumDownloads else {
            return 0
        }

        return removeItems(for: .forumDownload)
    }

    func reload() {
        do {
            guard fileManager.fileExists(atPath: manifestURL.path) || items.isEmpty else {
                throw IChartPDFLibraryDeletionError.manifestUnavailable
            }
            let loadedItems = try Self.loadItems(from: manifestURL, fileManager: fileManager)
            items = loadedItems
            recoverDeletionsAndPruneIfPossible()
        } catch {
            // Preserve the last readable library and every retained file.
            recoveryErrorMessage = "Could not read the PDF library. \(error.localizedDescription)"
        }
    }

    private var deletionDirectory: URL {
        baseDirectory.appendingPathComponent(".deletions", isDirectory: true)
    }

    private func validateDeletionDirectory() throws {
        let root = baseDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard deletionDirectory.standardizedFileURL.resolvingSymlinksInPath().path == root + "/.deletions" else {
            throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery folder")
        }
    }

    private func validatedLibraryURL(for item: IChartPDFLibraryItem) throws -> URL {
        let url = item.url(relativeTo: baseDirectory).standardizedFileURL
        let root = baseDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard item.relativePath == item.source.directoryName + "/" + item.fileName,
              item.fileName == url.lastPathComponent,
              !item.fileName.contains("/"),
              url.pathExtension.lowercased() == "pdf",
              url.resolvingSymlinksInPath().path == root + "/" + item.relativePath else {
            throw IChartPDFLibraryDeletionError.invalidFile(item.fileName)
        }
        return url
    }

    private func restoreDeletionFiles(_ transaction: DeletionTransaction, from directory: URL) throws {
        var failures = [String]()
        for file in transaction.files.reversed() {
            // Recovery reads a local journal, so validate its staging name too.
            guard file.stagedFileName == "\(file.item.id.uuidString).pdf" else {
                failures.append("Invalid recovery filename.")
                continue
            }
            let stagedURL = directory.appendingPathComponent(file.stagedFileName)
            do {
                let destination = try validatedLibraryURL(for: file.item)
                if !fileManager.fileExists(atPath: stagedURL.path) {
                    guard fileManager.fileExists(atPath: destination.path) else {
                        throw IChartPDFLibraryDeletionError.restoreFailed("The retained copy of \(file.item.fileName) is missing.")
                    }
                    continue
                }
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw IChartPDFLibraryDeletionError.recoveryCollision(file.item.fileName)
                }
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: stagedURL, to: destination)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if !failures.isEmpty {
            throw IChartPDFLibraryDeletionError.restoreFailed(failures.joined(separator: " "))
        }
    }

    private func recoverPendingDeletions() throws {
        guard fileManager.fileExists(atPath: deletionDirectory.path) else { return }
        try validateDeletionDirectory()
        let directories = try fileManager.contentsOfDirectory(
            at: deletionDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        )
        let liveIDs = Set(items.map(\.id))
        for directory in directories {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  directory.resolvingSymlinksInPath().path == deletionDirectory.resolvingSymlinksInPath().path + "/" + directory.lastPathComponent else {
                throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery transaction")
            }
            let journalURL = directory.appendingPathComponent("transaction.json")
            guard fileManager.fileExists(atPath: journalURL.path) else { continue }
            let journalAttributes = try fileManager.attributesOfItem(atPath: journalURL.path)
            guard journalAttributes[.type] as? FileAttributeType == .typeRegular else {
                throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery journal")
            }
            let transaction = try ChartPersistenceCoders.decoder.decode(
                DeletionTransaction.self, from: Data(contentsOf: journalURL)
            )
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                throw IChartPDFLibraryDeletionError.manifestUnavailable
            }
            try validateDeletionTransaction(transaction, directory: directory)
            if !liveIDs.isDisjoint(with: transaction.itemIDs) {
                try restoreDeletionFiles(transaction, from: directory)
            }
            try fileManager.removeItem(at: directory)
        }
    }

    private func validateDeletionTransaction(_ transaction: DeletionTransaction, directory: URL) throws {
        let targetIDs = Set(transaction.itemIDs)
        guard !targetIDs.isEmpty, targetIDs.count == transaction.itemIDs.count else {
            throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery journal")
        }
        var expectedNames: Set<String> = ["transaction.json"]
        for file in transaction.files {
            _ = try validatedLibraryURL(for: file.item)
            guard targetIDs.contains(file.item.id),
                  file.stagedFileName == "\(file.item.id.uuidString).pdf",
                  expectedNames.insert(file.stagedFileName).inserted else {
                throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery journal")
            }
            let stagedURL = directory.appendingPathComponent(file.stagedFileName)
            if fileManager.fileExists(atPath: stagedURL.path) {
                let attributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery file")
                }
            }
        }
        let actualNames = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
        guard actualNames.isSubset(of: expectedNames) else {
            throw IChartPDFLibraryDeletionError.invalidFile("PDF recovery folder contents")
        }
    }

    private func recoverDeletionsAndPruneIfPossible() {
        do {
            try recoverPendingDeletions()
            recoveryErrorMessage = nil
            pruneMissingFilesAndPersistIfNeeded()
        } catch {
            // Never prune an entry whose file is retained in a failed recovery.
            recoveryErrorMessage = error.localizedDescription
        }
    }

    private func copyPDF(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func uniqueFileName(
        preferredFileName: String,
        fallbackTitle: String,
        in directory: URL
    ) throws -> String {
        let sanitizedFileName = Self.sanitizedPDFFileName(
            from: preferredFileName,
            fallbackTitle: fallbackTitle
        )
        let stem = (sanitizedFileName as NSString).deletingPathExtension
        let fileExtension = (sanitizedFileName as NSString).pathExtension.isEmpty
            ? "pdf"
            : (sanitizedFileName as NSString).pathExtension

        var candidate = "\(stem).\(fileExtension)"
        var index = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path(percentEncoded: false)) {
            candidate = "\(stem) \(index).\(fileExtension)"
            index += 1
        }

        return candidate
    }

    private static func sanitizedPDFFileName(from fileName: String, fallbackTitle: String) -> String {
        let rawStem = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackStem = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceStem = rawStem.isEmpty ? fallbackStem : rawStem
        let stripped = sourceStem.replacingOccurrences(
            of: #"[\\/:*?"<>|\p{C}]+"#,
            with: " ",
            options: .regularExpression
        )
        let collapsedWhitespace = stripped.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let cleaned = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((cleaned.isEmpty ? "iChart PDF" : cleaned)).pdf"
    }

    private func pruneMissingFilesAndPersistIfNeeded() {
        let originalCount = items.count
        items.removeAll { item in
            !fileManager.fileExists(atPath: item.url(relativeTo: baseDirectory).path(percentEncoded: false))
        }
        sortItems()

        guard items.count != originalCount else {
            return
        }

        try? persist()
    }

    private func removeItems(for source: IChartPDFLibrarySource) -> Int {
        let removedItems = items.filter { $0.source == source }
        guard !removedItems.isEmpty else {
            return 0
        }

        for item in removedItems {
            try? fileManager.removeItem(at: item.url(relativeTo: baseDirectory))
        }
        items.removeAll { $0.source == source }
        try? persist()
        return removedItems.count
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.fileName < rhs.fileName
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private func persist() throws {
        try persist(items)
    }

    private func persist(_ updatedItems: [IChartPDFLibraryItem]) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try ChartPersistenceCoders.encoder.encode(updatedItems)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func loadItems(from url: URL, fileManager: FileManager) throws -> [IChartPDFLibraryItem] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw IChartPDFLibraryDeletionError.invalidFile("PDF library manifest")
        }

        let data = try Data(contentsOf: url)
        return try ChartPersistenceCoders.decoder.decode([IChartPDFLibraryItem].self, from: data)
    }
}

enum IChartPDFLibraryDeletionError: LocalizedError {
    case manifestUnavailable
    case recoveryUnavailable(String)
    case invalidFile(String)
    case sharedFile(String)
    case recoveryCollision(String)
    case restoreFailed(String)
    case recoveryFailed(operation: String, recovery: String, directory: String)
    case cleanupFailed(count: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .manifestUnavailable:
            return "The PDF library manifest is missing. Retained PDF files were left untouched."
        case .recoveryUnavailable(let message):
            return "The PDF library must recover before it can save more files. \(message)"
        case .invalidFile(let name):
            return "Could not delete \(name) because its library file location is invalid."
        case .sharedFile(let name):
            return "Could not delete \(name) because another unselected library item uses the same file."
        case .recoveryCollision(let name):
            return "Could not restore \(name) because a file already exists at its original location."
        case .restoreFailed(let message):
            return "Could not restore all PDF files. \(message)"
        case .recoveryFailed(let operation, let recovery, let directory):
            return "PDF deletion failed. \(operation) \(recovery) Retained files are recoverable at \(directory)."
        case .cleanupFailed(let count, let message):
            return "\(count == 1 ? "The PDF was" : "The \(count) PDFs were") deleted from the library, but temporary copies could not be removed. \(message) Cleanup will be retried when the library reloads."
        }
    }
}
