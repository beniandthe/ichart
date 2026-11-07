import Foundation

/// Local retrieval shares the same title matching and stable ordering across
/// libraries. It never changes the underlying saved order or selected items.
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recent
    case name

    var id: String { rawValue }
    var title: String { self == .recent ? "Recent" : "Name" }
}

struct LibrarySelectionScope: Equatable {
    let visibleIDs: Set<UUID>
    let hiddenIDs: Set<UUID>
}

enum LibraryRetrievalPolicy {
    /// Displayed selection counts and destructive actions use the same scope.
    /// Selections outside a search stay selected but are never deleted from it.
    static func selectionScope(selectedIDs: Set<UUID>, availableIDs: Set<UUID>) -> LibrarySelectionScope {
        LibrarySelectionScope(visibleIDs: selectedIDs.intersection(availableIDs),
                              hiddenIDs: selectedIDs.subtracting(availableIDs))
    }

    static func togglingVisibleSelection(selectedIDs: Set<UUID>, availableIDs: Set<UUID>) -> Set<UUID> {
        selectedIDs.isSuperset(of: availableIDs)
            ? selectedIDs.subtracting(availableIDs)
            : selectedIDs.union(availableIDs)
    }

    static func matches(_ text: String, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { term in
            text.range(of: String(term), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func items<Item>(
        _ items: [Item], query: String, order: LibrarySortOrder,
        title: (Item) -> String, date: (Item) -> Date
    ) -> [Item] {
        items.enumerated().filter { matches(title($0.element), query: query) }
            .sorted { lhs, rhs in
                if order == .recent, date(lhs.element) != date(rhs.element) {
                    return date(lhs.element) > date(rhs.element)
                }
                let comparison = title(lhs.element).localizedStandardCompare(title(rhs.element))
                return comparison == .orderedSame ? lhs.offset < rhs.offset : comparison == .orderedAscending
            }.map(\.element)
    }

    /// A query being edited does not invalidate the last submitted results.
    /// Clearing the field explicitly returns to the default browse view.
    static func shouldRestoreForumBrowsing(editedQuery: String, submittedQuery: String) -> Bool {
        editedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !submittedQuery.isEmpty
    }
}
