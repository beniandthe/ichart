import Foundation
import PDFKit

struct IChartPDFImportLimits: Equatable, Sendable {
    let maximumFileSizeBytes: Int
    let maximumPageCount: Int

    static let standard = IChartPDFImportLimits(
        maximumFileSizeBytes: 50 * 1_024 * 1_024,
        maximumPageCount: 200
    )
}

enum IChartPDFImportError: LocalizedError, Equatable {
    case invalidLimits
    case notPDF
    case notRegularFile
    case unreadablePDF
    case emptyPDF
    case encryptedPDF
    case fileTooLarge(maximumBytes: Int)
    case tooManyPages(maximum: Int)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidLimits:
            return "The PDF import limits are invalid."
        case .notPDF:
            return "Choose a PDF document."
        case .notRegularFile:
            return "Choose a readable PDF file, rather than a folder or shortcut."
        case .unreadablePDF:
            return "This file could not be read as a PDF. It may be damaged or incomplete."
        case .emptyPDF:
            return "This PDF has no readable pages."
        case .encryptedPDF:
            return "Password-protected PDFs cannot be imported. Save an unlocked copy and try again."
        case .fileTooLarge(let maximumBytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file)
            return "This PDF is too large. Choose a PDF smaller than \(size)."
        case .tooManyPages(let maximum):
            return "This PDF has too many pages. Import up to \(maximum) pages at a time."
        case .rollbackFailed(let message):
            return "The PDF could not be saved to the library. A retained copy could not be cleaned up. \(message)"
        }
    }
}

/// Prepares an owned, validated copy while the provider URL is accessible. No
/// manifest or observable library state is changed until the store commits it.
enum IChartPDFImportService {
    struct PreparedPDF: Sendable {
        let stagingDirectory: URL
        let url: URL
        let originalFileName: String
        let displayTitle: String
        let pageCount: Int
        let fileSizeBytes: Int
    }

    static func prepare(
        from sourceURL: URL,
        title: String?,
        limits: IChartPDFImportLimits,
        fileManager: FileManager
    ) async throws -> PreparedPDF {
        let task = Task.detached(priority: .userInitiated) {
            try prepareSynchronously(from: sourceURL, title: title, limits: limits, fileManager: fileManager)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func prepareSynchronously(
        from sourceURL: URL,
        title: String?,
        limits: IChartPDFImportLimits,
        fileManager: FileManager
    ) throws -> PreparedPDF {
        try Task.checkCancellation()
        guard limits.maximumFileSizeBytes > 0, limits.maximumPageCount > 0 else {
            throw IChartPDFImportError.invalidLimits
        }
        guard sourceURL.isFileURL, sourceURL.pathExtension.lowercased() == "pdf" else {
            throw IChartPDFImportError.notPDF
        }

        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("iChart-PDF-Import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let stagedURL = stagingDirectory.appendingPathComponent("original.pdf")
        var preparedSuccessfully = false
        defer {
            if !preparedSuccessfully { try? fileManager.removeItem(at: stagingDirectory) }
        }

        // File coordination lets Files providers materialize their content before
        // copying it. The security scope covers this actual background read.
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readableURL in
            copyResult = Result {
                try Task.checkCancellation()
                let attributes = try fileManager.attributesOfItem(atPath: readableURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw IChartPDFImportError.notRegularFile
                }
                let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard byteCount <= limits.maximumFileSizeBytes else {
                    throw IChartPDFImportError.fileTooLarge(maximumBytes: limits.maximumFileSizeBytes)
                }
                try fileManager.copyItem(at: readableURL, to: stagedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copyResult else { throw IChartPDFImportError.unreadablePDF }
        try copyResult.get()
        try Task.checkCancellation()

        // Validate the retained bytes, rather than metadata or a provider file
        // that might subsequently change. Never re-render an imported original.
        let stagedAttributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
        let byteCount = (stagedAttributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount <= limits.maximumFileSizeBytes else {
            throw IChartPDFImportError.fileTooLarge(maximumBytes: limits.maximumFileSizeBytes)
        }
        guard byteCount > 0, let document = PDFDocument(url: stagedURL) else {
            throw IChartPDFImportError.unreadablePDF
        }
        guard !document.isEncrypted, !document.isLocked else { throw IChartPDFImportError.encryptedPDF }
        guard document.pageCount > 0 else { throw IChartPDFImportError.emptyPDF }
        guard document.pageCount <= limits.maximumPageCount else {
            throw IChartPDFImportError.tooManyPages(maximum: limits.maximumPageCount)
        }
        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex) else { throw IChartPDFImportError.emptyPDF }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                throw IChartPDFImportError.emptyPDF
            }
        }
        try Task.checkCancellation()
        let requestedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalTitle = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = PreparedPDF(
            stagingDirectory: stagingDirectory,
            url: stagedURL,
            originalFileName: sourceURL.lastPathComponent,
            displayTitle: requestedTitle.isEmpty ? (originalTitle.isEmpty ? "Imported PDF" : originalTitle) : requestedTitle,
            pageCount: document.pageCount,
            fileSizeBytes: byteCount
        )
        preparedSuccessfully = true
        return result
    }
}
