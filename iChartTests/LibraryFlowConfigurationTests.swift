import Foundation
import XCTest

/// Source integration checks supplement store/runtime tests, not touch acceptance.
final class LibraryFlowConfigurationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testBothDeleteEntrypointsRequireTheSameImmutableConfirmation() throws {
        let source = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"))
        XCTAssertTrue(source.contains("IChartLibraryDeleteRequest(charts: [chart])"))
        XCTAssertTrue(source.contains("IChartLibraryDeleteRequest(pdfs: [item])"))
        XCTAssertTrue(source.contains(".alert(item: libraryAlertBinding)"))
        XCTAssertTrue(source.contains("title: Text(request.confirmationTitle)"))
        XCTAssertTrue(source.contains("primaryButton: .destructive(Text(request.deleteButtonTitle))"))
        XCTAssertTrue(source.contains("libraryAlert.dismiss(id: request.id)\n                        performDeletion(request)"))
        XCTAssertTrue(source.contains("libraryAlert.dismiss(id: presentedID)"))
        XCTAssertFalse(source.contains("deleteConfirmationPresented"))
        XCTAssertFalse(source.contains(".alert(\"Library Needs Attention\""))
        XCTAssertTrue(source.contains("store.deleteCharts(ids: request.ids)"))
        XCTAssertTrue(source.contains("try pdfLibraryStore.deleteItems(ids: request.ids)"))
        XCTAssertFalse(source.contains("pdfLibraryStore.delete(item)"))
        XCTAssertTrue(source.contains("LibraryRetrievalPolicy.selectionScope(selectedIDs: selectedIDs.wrappedValue, availableIDs: availableIDs)"))
        XCTAssertTrue(source.contains("onDelete(scope.visibleIDs)"))
        XCTAssertTrue(source.contains(".disabled(scope.visibleIDs.isEmpty)"))
        XCTAssertTrue(source.contains("presentLibraryError(error.localizedDescription)"))
        XCTAssertTrue(source.contains(".onReceive(store.$persistenceStatus.dropFirst())"))
        XCTAssertTrue(source.contains("guard awaitingChartDeleteSave else { return }"))
    }

    func testSetlistsHaveTheirOwnTabAndPersistentEnvironmentWithoutNewBillingGate() throws {
        let source = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("iChart/App/IChartApp.swift"))
        let views = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/SetlistsView.swift"))
        XCTAssertTrue(source.contains("case setlists"))
        XCTAssertTrue(source.contains("case .setlists:\n            SetlistsView()"))
        XCTAssertTrue(app.contains("IChartPDFSetlistStore.live()"))
        XCTAssertTrue(app.contains(".environmentObject(setlistStore)"))
        XCTAssertTrue(views.contains("visibleItems(for:"))
        XCTAssertFalse(views.contains("canUse(.setlistsAndVersionHistory)"))
    }
}
