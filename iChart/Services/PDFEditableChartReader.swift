import Foundation
import PDFKit

enum PDFEditableChartReadError: LocalizedError, Equatable {
    case unavailable
    case unsupportedPageCount
    case noSelectableText

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This PDF cannot be opened for conversion."
        case .unsupportedPageCount:
            "Editable chart conversion currently supports one-page PDFs."
        case .noSelectableText:
            "This PDF has no selectable text. Use a printed chord chart saved as a text PDF."
        }
    }
}

enum PDFEditableChartReader {
    static func read(from url: URL, title: String) async throws -> PDFEditableChartDraft {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
                throw PDFEditableChartReadError.unavailable
            }
            guard document.pageCount == 1 else {
                throw PDFEditableChartReadError.unsupportedPageCount
            }
            guard let text = document.page(at: 0)?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PDFEditableChartReadError.noSelectableText
            }
            try Task.checkCancellation()
            return try PDFEditableChartDraft.read(title: title, pages: [text])
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
