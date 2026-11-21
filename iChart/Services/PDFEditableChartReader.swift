import Foundation
import PDFKit

enum PDFEditableChartReadError: LocalizedError, Equatable {
    case unavailable
    case noSelectableText
    case unsupportedStaffPage(Int)
    case noStaffChords

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "This PDF cannot be opened for conversion."
        case .noSelectableText:
            "This PDF has no selectable text. Use a printed chord chart saved as a text PDF."
        case .unsupportedStaffPage(let page):
            "iChart couldn't read the staff barlines on PDF page \(page). Use a single-staff chord chart with clear measure dividers."
        case .noStaffChords:
            "iChart found the staff and barlines but couldn't find chords above them."
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
            return try read(document, title: title)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func read(_ document: PDFDocument, title: String) throws -> PDFEditableChartDraft {
        var textGridError: Error?
        if document.pageCount == 1, let text = document.page(at: 0)?.string {
            do {
                return try PDFEditableChartDraft.read(title: title, pages: [text])
            } catch {
                textGridError = error
            }
        }

        var rows: [[String]] = []
        var pageNumbers: [Int] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let pageRows = try autoreleasepool {
                guard let page = document.page(at: index),
                      let text = page.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PDFEditableChartReadError.noSelectableText
                }
                let systems: [PDFStaffSystemGeometry]
                do {
                    systems = try PDFStaffBarlineDetector.detect(in: page)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw textGridError ?? PDFEditableChartReadError.unsupportedStaffPage(index + 1)
                }
                guard !systems.isEmpty else {
                    throw textGridError ?? PDFEditableChartReadError.unsupportedStaffPage(index + 1)
                }
                return try PDFStaffChordReader.read(from: page, systems: systems)
            }
            rows.append(contentsOf: pageRows)
            pageNumbers.append(contentsOf: repeatElement(index + 1, count: pageRows.count))
        }
        guard rows.contains(where: { $0.contains { !$0.isEmpty } }) else {
            throw PDFEditableChartReadError.noStaffChords
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PDFEditableChartDraft(title: trimmedTitle.isEmpty ? "Imported Chart" : trimmedTitle,
            rows: rows, staffPageNumbers: pageNumbers)
    }
}
