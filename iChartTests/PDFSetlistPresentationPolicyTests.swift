import Foundation
import XCTest
@testable import iChart

final class PDFSetlistPresentationPolicyTests: XCTestCase {
    func testUnavailableReasonsDistinguishReferenceAccessFileAndReadFailures() {
        XCTAssertEqual(IChartSetlistAvailability.reason(isInLibrary: false, isVisible: false, hasFile: false), .removedFromLibrary)
        XCTAssertEqual(IChartSetlistAvailability.reason(isInLibrary: true, isVisible: false, hasFile: true), .requiresLibraryAccess)
        XCTAssertEqual(IChartSetlistAvailability.reason(isInLibrary: true, isVisible: true, hasFile: false), .missingFile)
        XCTAssertEqual(IChartSetlistAvailability.reason(isInLibrary: true, isVisible: true, hasFile: true, readFailure: .lockedPDF), .lockedPDF)
        XCTAssertEqual(IChartSetlistAvailability.reason(isInLibrary: true, isVisible: true, hasFile: true, readFailure: .unreadablePDF), .unreadablePDF)
        XCTAssertNil(IChartSetlistAvailability.reason(isInLibrary: true, isVisible: true, hasFile: true))
        XCTAssertFalse(IChartSetlistUnavailableReason.missingFile.message.contains("current plan"))
        XCTAssertTrue(IChartSetlistUnavailableReason.requiresLibraryAccess.message.contains("Settings"))
    }

    func testSearchHandlesWhitespaceCaseAndAccentsWithoutChangingOriginalValues() {
        let first = IChartPDFSetlist(name: "Café Set", updatedAt: Date(timeIntervalSince1970: 1))
        let second = IChartPDFSetlist(name: "Afternoon", updatedAt: Date(timeIntervalSince1970: 2))
        let values = [first, second]
        XCTAssertEqual(IChartSetlistSearch.setlists(values, query: " CAFE ", order: .recent), [first])
        XCTAssertEqual(IChartSetlistSearch.setlists(values, query: "", order: .recent), [second, first])
        XCTAssertEqual(IChartSetlistSearch.setlists(values, query: "", order: .name), [second, first])
        XCTAssertEqual(values, [first, second])
        XCTAssertTrue(IChartSetlistSearch.setlists(values, query: "missing", order: .name).isEmpty)
    }

    func testPDFSearchAndSortRetainItemIdentity() {
        let alpha = item("Alpha", createdAt: 1)
        let beta = item("Beta", createdAt: 2)
        XCTAssertEqual(IChartSetlistSearch.pdfs([alpha, beta], query: "", order: .name).map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(IChartSetlistSearch.pdfs([alpha, beta], query: "", order: .recent).map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(IChartSetlistSearch.pdfs([alpha, beta], query: " BET ", order: .name).map(\.id), [beta.id])
    }

    private func item(_ title: String, createdAt: TimeInterval) -> IChartPDFLibraryItem {
        IChartPDFLibraryItem(id: UUID(), source: .personalImport, fileName: "\(title).pdf", displayTitle: title,
            layoutStyle: nil, transpositionView: nil, chordTranspositionSemitones: nil, pageCount: 1,
            fileSizeBytes: 1, createdAt: Date(timeIntervalSince1970: createdAt), relativePath: "Imports/\(title).pdf")
    }
}
