import Foundation

/// An immutable confirmation snapshot, never a live selection binding.
struct IChartLibraryDeleteRequest: Identifiable, Equatable {
    enum Kind: Equatable { case charts, pdfs }
    let id = UUID()
    let kind: Kind
    let ids: Set<UUID>
    let titles: [String]

    init(charts: [Chart]) {
        kind = .charts
        ids = Set(charts.map(\.id))
        titles = charts.map(\.title)
    }

    init(pdfs: [IChartPDFLibraryItem]) {
        kind = .pdfs
        ids = Set(pdfs.map(\.id))
        titles = pdfs.map(\.displayTitle)
    }

    var confirmationTitle: String {
        let noun = kind == .charts ? "Chart" : "PDF"
        return ids.count == 1 ? "Delete \(noun)?" : "Delete \(ids.count) \(noun)s?"
    }

    var deleteButtonTitle: String {
        ids.count == 1 ? "Delete" : "Delete \(ids.count)"
    }

    var confirmationMessage: String {
        let names = titles.prefix(5).joined(separator: "\n")
        let remainder = titles.count > 5 ? "\n…and \(titles.count - 5) more" : ""
        let scope = kind == .charts
            ? "This deletes the selected charts from your library, including their cloud backups when sync is available. Exported PDFs stay in the PDF Library."
            : "This permanently deletes the selected PDF files from this device. Original editable charts stay unchanged. Setlists keep their song entries, marked unavailable."
        return "\(names)\(remainder)\n\n\(scope)"
    }
}
