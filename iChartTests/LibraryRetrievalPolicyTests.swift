import Foundation
import XCTest
@testable import iChart

final class LibraryRetrievalPolicyTests: XCTestCase {
    private struct Item: Equatable { let id: Int; let title: String; let date: Date }

    func testTitleSearchFindsAllWordsRegardlessOfCaseAccentOrOrder() {
        XCTAssertTrue(LibraryRetrievalPolicy.matches("Café Blues", query: " blues CAFÉ "))
        XCTAssertTrue(LibraryRetrievalPolicy.matches("Café Blues", query: "cafe"))
        XCTAssertFalse(LibraryRetrievalPolicy.matches("Café Blues", query: "cafe swing"))
        XCTAssertTrue(LibraryRetrievalPolicy.matches("Any title", query: " \n "))
    }

    func testRetrievalChangesDisplayOrderWithoutChangingSourceOrDuplicateOrder() {
        let items = [Item(id: 1, title: "Blues 10", date: Date(timeIntervalSince1970: 2)),
                     Item(id: 2, title: "Blues 2", date: Date(timeIntervalSince1970: 1)),
                     Item(id: 3, title: "Blues 2", date: Date(timeIntervalSince1970: 1))]
        let byName = LibraryRetrievalPolicy.items(items, query: "Blues", order: .name,
            title: { $0.title }, date: { $0.date })
        XCTAssertEqual(byName.map(\.id), [2, 3, 1])
        let byDate = LibraryRetrievalPolicy.items(items, query: "", order: .recent,
            title: { $0.title }, date: { $0.date })
        XCTAssertEqual(byDate.map(\.id), [1, 2, 3])
        XCTAssertEqual(items.map(\.id), [1, 2, 3])
    }

    func testFilteringSelectionKeepsHiddenItemsOutOfTheCountAndDeleteScope() {
        let shown = UUID(), hidden = UUID()
        let selected: Set<UUID> = [shown, hidden]
        let scope = LibraryRetrievalPolicy.selectionScope(selectedIDs: selected, availableIDs: [shown])
        XCTAssertEqual(scope.visibleIDs.count, 1)
        XCTAssertEqual(scope.visibleIDs, [shown], "The Delete action receives exactly the selected IDs counted in the current results")
        XCTAssertEqual(scope.hiddenIDs, [hidden])
        let retainedLibraryIDs = Set([shown, hidden]).subtracting(scope.visibleIDs)
        XCTAssertEqual(retainedLibraryIDs, [hidden], "Deleting the displayed selection must retain the selected item hidden by search")
        XCTAssertEqual(selected, [shown, hidden], "Retrieval must not discard the original selection")
    }

    func testSelectingAndDeselectingSearchResultsPreservesSelectionOutsideTheSearch() {
        let shown = UUID(), hidden = UUID()
        let selected = LibraryRetrievalPolicy.togglingVisibleSelection(selectedIDs: [hidden], availableIDs: [shown])
        XCTAssertEqual(selected, [shown, hidden])
        let deselected = LibraryRetrievalPolicy.togglingVisibleSelection(selectedIDs: selected, availableIDs: [shown])
        XCTAssertEqual(deselected, [hidden])
        let noMatches = LibraryRetrievalPolicy.selectionScope(selectedIDs: deselected, availableIDs: [])
        XCTAssertTrue(noMatches.visibleIDs.isEmpty, "Delete stays unavailable when only hidden items are selected")
        XCTAssertEqual(noMatches.hiddenIDs, [hidden])
    }

    func testRefiningForumQueryRetainsSubmittedResultsUntilCleared() {
        XCTAssertFalse(LibraryRetrievalPolicy.shouldRestoreForumBrowsing(editedQuery: "Blue Train", submittedQuery: "Blue"))
        XCTAssertFalse(LibraryRetrievalPolicy.shouldRestoreForumBrowsing(editedQuery: "Blue", submittedQuery: "Blue"))
        XCTAssertTrue(LibraryRetrievalPolicy.shouldRestoreForumBrowsing(editedQuery: "  ", submittedQuery: "Blue"))
        XCTAssertFalse(LibraryRetrievalPolicy.shouldRestoreForumBrowsing(editedQuery: "", submittedQuery: ""))
    }
}
