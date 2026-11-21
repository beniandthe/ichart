import CryptoKit
import Foundation

struct IChartPDFSetlistCloudMerge {
    enum Resolution { case local, cloud, both }

    let local: [IChartPDFSetlist]
    let remote: [IChartPDFSetlist]
    let baseline: [IChartPDFSetlist]

    var conflictingIDs: Set<UUID> {
        let old = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let mine = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let theirs = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        return Set(mine.keys).union(theirs.keys).filter {
            mine[$0] != theirs[$0] && mine[$0] != old[$0] && theirs[$0] != old[$0]
        }
    }

    func resolved(_ resolution: Resolution = .local) -> [IChartPDFSetlist] {
        let old = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let mine = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let theirs = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var result: [IChartPDFSetlist] = []
        for id in Set(mine.keys).union(theirs.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            if mine[id] == theirs[id] || theirs[id] == old[id] {
                if let list = mine[id] { result.append(list) }
            } else if mine[id] == old[id] {
                if let list = theirs[id] { result.append(list) }
            } else {
                switch resolution {
                case .local:
                    if let list = mine[id] { result.append(list) }
                case .cloud:
                    if let list = theirs[id] { result.append(list) }
                case .both:
                    if let list = theirs[id] { result.append(list) }
                    if let list = mine[id] {
                        result.append(IChartPDFSetlist(id: UUID(), name: list.name + " (Local copy)",
                            entries: list.entries, createdAt: list.createdAt, updatedAt: list.updatedAt))
                    }
                }
            }
        }
        return result
    }
}

enum IChartPDFSetlistCloudError: LocalizedError {
    case invalidBackup
    case missingPDF
    case accountChanged
    case newerLocalChanges
    case cloudChanged

    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This setlist backup could not be verified. Your local setlists are available."
        case .missingPDF: return "A linked PDF is unavailable. Add or replace that PDF before backing up this setlist."
        case .accountChanged: return "The account changed during this operation. Try again with the account you want to use."
        case .newerLocalChanges: return "Your setlists changed during this operation. Sync again to include the latest edits."
        case .cloudChanged: return "Another device changed the cloud setlists. Sync again to review those changes."
        }
    }
}

enum IChartPDFSetlistCloudValidation {
    static let maximumPDFBytes = 50 * 1_024 * 1_024

    static func payload(_ document: IChartPDFSetlistCloudDocument) throws -> IChartJSONValue {
        try JSONDecoder().decode(IChartJSONValue.self, from: ChartPersistenceCoders.encoder.encode(document))
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ document: IChartPDFSetlistCloudDocument) throws {
        guard document.schemaVersion == 1,
              Set(document.setlists.map(\.id)).count == document.setlists.count,
              Set(document.pdfs.map { $0.item.id }).count == document.pdfs.count,
              document.setlists.allSatisfy({ list in
                  !list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && list.createdAt.timeIntervalSinceReferenceDate.isFinite
                    && list.updatedAt.timeIntervalSinceReferenceDate.isFinite
                    && Set(list.entries.map(\.id)).count == list.entries.count
              }),
              document.pdfs.allSatisfy({ pdf in
                  pdf.sha256.count == 64 && pdf.sha256.allSatisfy { "0123456789abcdef".contains($0) }
                    && (1...maximumPDFBytes).contains(pdf.item.fileSizeBytes)
                    && pdf.item.pageCount > 0
              }) else { throw IChartPDFSetlistCloudError.invalidBackup }
        let ids = Set(document.pdfs.map { $0.item.id })
        guard document.setlists.flatMap(\.entries).allSatisfy({ ids.contains($0.pdfItemID) }) else {
            throw IChartPDFSetlistCloudError.missingPDF
        }
    }

    static func validate(_ data: Data, for pdf: IChartPDFSetlistCloudPDF) throws {
        guard data.count == pdf.item.fileSizeBytes, data.count <= maximumPDFBytes,
              data.starts(with: Data("%PDF-".utf8)), digest(data) == pdf.sha256 else {
            throw IChartPDFSetlistCloudError.invalidBackup
        }
    }
}
