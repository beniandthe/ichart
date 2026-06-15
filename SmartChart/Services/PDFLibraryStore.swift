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

    private let baseDirectory: URL
    private let manifestURL: URL
    private let fileManager: FileManager

    init(baseDirectory: URL, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.manifestURL = baseDirectory.appendingPathComponent("pdf-library.json", isDirectory: false)
        self.fileManager = fileManager
        self.items = (try? Self.loadItems(from: manifestURL, fileManager: fileManager)) ?? []
        pruneMissingFilesAndPersistIfNeeded()
    }

    static func live(fileManager: FileManager = .default) -> IChartPDFLibraryStore {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL
            .appendingPathComponent("SmartChart", isDirectory: true)
            .appendingPathComponent("PDF Library", isDirectory: true)

        return IChartPDFLibraryStore(baseDirectory: baseDirectory, fileManager: fileManager)
    }

    func items(for source: IChartPDFLibrarySource) -> [IChartPDFLibraryItem] {
        items.filter { $0.source == source }
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

    func delete(_ item: IChartPDFLibraryItem) {
        let url = item.url(relativeTo: baseDirectory)
        try? fileManager.removeItem(at: url)
        items.removeAll { $0.id == item.id }
        try? persist()
    }

    func reload() {
        items = (try? Self.loadItems(from: manifestURL, fileManager: fileManager)) ?? []
        pruneMissingFilesAndPersistIfNeeded()
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

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.fileName < rhs.fileName
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private func persist() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try ChartPersistenceCoders.encoder.encode(items)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func loadItems(from url: URL, fileManager: FileManager) throws -> [IChartPDFLibraryItem] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try ChartPersistenceCoders.decoder.decode([IChartPDFLibraryItem].self, from: data)
    }
}
