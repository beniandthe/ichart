import Foundation

struct IChartPDFSetlistEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let pdfItemID: UUID
    let displayTitle: String

    init(id: UUID = UUID(), pdfItemID: UUID, displayTitle: String) {
        self.id = id
        self.pdfItemID = pdfItemID
        self.displayTitle = displayTitle
    }
}

struct IChartPDFSetlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var entries: [IChartPDFSetlistEntry]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        entries: [IChartPDFSetlistEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func resolvedEntries(in items: [IChartPDFLibraryItem]) -> [IChartPDFSetlistResolvedEntry] {
        let itemsByID = items.reduce(into: [UUID: IChartPDFLibraryItem]()) { lookup, item in
            if lookup[item.id] == nil {
                lookup[item.id] = item
            }
        }
        return entries.map { entry in
            IChartPDFSetlistResolvedEntry(entry: entry, pdfItem: itemsByID[entry.pdfItemID])
        }
    }
}

struct IChartPDFSetlistResolvedEntry: Identifiable, Equatable {
    let entry: IChartPDFSetlistEntry
    let pdfItem: IChartPDFLibraryItem?

    var id: UUID { entry.id }
    var displayTitle: String { pdfItem?.displayTitle ?? entry.displayTitle }
}
