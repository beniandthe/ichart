import XCTest
@testable import iChart

final class LibraryDeleteRequestTests: XCTestCase {
    func testConfirmationFreezesExactChartIDsAndNames() {
        var charts = [Chart.draft(title: "First"), Chart.draft(title: "Second")]
        let request = IChartLibraryDeleteRequest(charts: charts)
        let frozenIDs = Set(charts.map(\.id))
        charts.removeFirst()
        charts.append(Chart.draft(title: "Not selected"))
        XCTAssertEqual(request.ids, frozenIDs)
        XCTAssertEqual(request.titles, ["First", "Second"])
        XCTAssertEqual(request.confirmationTitle, "Delete 2 Charts?")
        XCTAssertEqual(request.deleteButtonTitle, "Delete 2")
        XCTAssertTrue(request.confirmationMessage.contains("Exported PDFs stay"))
        XCTAssertFalse(request.confirmationMessage.contains("Not selected"))
    }

    func testSinglePDFConfirmationSeparatesFileAndChartDeletion() {
        let pdf = IChartPDFLibraryItem(
            id: UUID(), source: .chartExport, fileName: "Song.pdf", displayTitle: "Song",
            layoutStyle: .leadSheet, transpositionView: .concert,
            chordTranspositionSemitones: 0, pageCount: 1, fileSizeBytes: 10,
            createdAt: Date(), relativePath: "Exports/Song.pdf"
        )
        let request = IChartLibraryDeleteRequest(pdfs: [pdf])
        XCTAssertEqual(request.ids, [pdf.id])
        XCTAssertEqual(request.confirmationTitle, "Delete PDF?")
        XCTAssertTrue(request.confirmationMessage.contains("permanently deletes"))
        XCTAssertTrue(request.confirmationMessage.contains("Original editable charts stay unchanged"))
        XCTAssertTrue(request.confirmationMessage.contains("Setlists keep their song entries"))
    }
}
