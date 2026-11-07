import Foundation

enum IChartSetlistUnavailableReason: Equatable {
    case removedFromLibrary
    case requiresLibraryAccess
    case missingFile
    case lockedPDF
    case unreadablePDF

    var message: String {
        switch self {
        case .removedFromLibrary:
            return "This song’s PDF is no longer in the PDF Library. Replace its setlist reference with another PDF, or skip to the next song."
        case .requiresLibraryAccess:
            return "This forum PDF is saved, but your current plan does not include access. Tap Done, then open Settings to check your account. You can also choose an available replacement or skip to the next song."
        case .missingFile:
            return "The saved PDF file is missing. Import it again and choose Replace PDF, or skip to the next song."
        case .lockedPDF:
            return "This PDF is password protected. Import an unlocked copy and choose Replace PDF, or skip to the next song."
        case .unreadablePDF:
            return "This file could not be read as a PDF. Import a working copy and choose Replace PDF, or skip to the next song."
        }
    }

    var shortTitle: String {
        switch self {
        case .removedFromLibrary: return "PDF removed from library"
        case .requiresLibraryAccess: return "Forum PDF needs access"
        case .missingFile: return "Saved file missing"
        case .lockedPDF: return "Password-protected PDF"
        case .unreadablePDF: return "Unreadable PDF"
        }
    }
}

enum IChartSetlistAvailability {
    static func reason(isInLibrary: Bool, isVisible: Bool, hasFile: Bool,
        readFailure: IChartSetlistUnavailableReason? = nil) -> IChartSetlistUnavailableReason? {
        guard isInLibrary else { return .removedFromLibrary }
        guard isVisible else { return .requiresLibraryAccess }
        guard hasFile else { return .missingFile }
        return readFailure
    }
}

enum IChartSetlistListOrder: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case name = "Name"
    var id: Self { self }
}

enum IChartSetlistSearch {
    static func matches(_ title: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || title.localizedStandardContains(trimmed)
    }

    static func setlists(_ values: [IChartPDFSetlist], query: String, order: IChartSetlistListOrder) -> [IChartPDFSetlist] {
        values.filter { matches($0.name, query: query) }.sorted { lhs, rhs in
            if order == .recent, lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func pdfs(_ values: [IChartPDFLibraryItem], query: String, order: IChartSetlistListOrder) -> [IChartPDFLibraryItem] {
        values.filter { matches($0.displayTitle, query: query) }.sorted { lhs, rhs in
            if order == .recent, lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            let comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
