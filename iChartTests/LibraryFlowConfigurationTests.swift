import Foundation
import XCTest

/// Source integration checks supplement store/runtime tests, not touch acceptance.
final class LibraryFlowConfigurationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testBothDeleteEntrypointsRequireTheSameImmutableConfirmation() throws {
        let source = try String(contentsOf: root.appendingPathComponent("iChart/Features/Library/LibraryView.swift"))
        XCTAssertTrue(source.contains("IChartLibraryDeleteRequest(charts: [chart])"))
        XCTAssertTrue(source.contains("IChartLibraryDeleteRequest(pdfs: [item])"))
        XCTAssertTrue(source.contains("deleteRequest?.confirmationTitle"))
        XCTAssertTrue(source.contains("Button(request.deleteButtonTitle, role: .destructive)"))
        XCTAssertTrue(source.contains("store.deleteCharts(ids: request.ids)"))
        XCTAssertTrue(source.contains("try pdfLibraryStore.deleteItems(ids: request.ids)"))
        XCTAssertFalse(source.contains("pdfLibraryStore.delete(item)"))
        XCTAssertTrue(source.contains("selectedIDs.wrappedValue.intersection(availableIDs).isEmpty"))
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
