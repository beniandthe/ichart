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

/// One owner's acknowledged setlist state. Local PDFs remain available when
/// cloud access ends or the signed-in account changes.
struct IChartPDFSetlistCloudCheckpoint: Codable, Equatable {
    var revision: Int64
    var setlists: [IChartPDFSetlist]
    var pdfs: [IChartPDFSetlistCloudPDF]
}

struct IChartPDFSetlistCloudPDF: Codable, Equatable {
    var item: IChartPDFLibraryItem
    var sha256: String

    private enum CodingKeys: String, CodingKey {
        case id, item
        case sha256 = "content_sha256"
        case byteCount = "file_size_bytes"
    }

    init(item: IChartPDFLibraryItem, sha256: String) {
        self.item = item
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        item = try values.decode(IChartPDFLibraryItem.self, forKey: .item)
        sha256 = try values.decode(String.self, forKey: .sha256)
        guard try values.decode(UUID.self, forKey: .id) == item.id,
              try values.decode(Int.self, forKey: .byteCount) == item.fileSizeBytes else {
            throw DecodingError.dataCorruptedError(forKey: .item, in: values,
                debugDescription: "PDF metadata does not match its reference")
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(item.id, forKey: .id)
        try values.encode(item, forKey: .item)
        try values.encode(sha256, forKey: .sha256)
        try values.encode(item.fileSizeBytes, forKey: .byteCount)
    }
}

struct IChartPDFSetlistCloudDocument: Codable, Equatable {
    var schemaVersion = 1
    var setlists: [IChartPDFSetlist]
    var pdfs: [IChartPDFSetlistCloudPDF]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case setlists, pdfs
    }
}
