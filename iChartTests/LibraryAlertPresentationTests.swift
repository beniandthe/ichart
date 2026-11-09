import XCTest
@testable import iChart

final class LibraryAlertPresentationTests: XCTestCase {
    func testLateDismissalCannotClearTheNextChartsConfirmation() throws {
        let charts = [Chart.draft(title: "First"), Chart.draft(title: "Next")]
        let first = IChartLibraryDeleteRequest(charts: [charts[0]])
        let next = IChartLibraryDeleteRequest(charts: [charts[1]])
        var presentation = IChartLibraryAlertPresentation()

        presentation.requestDeletion(first)
        presentation.dismiss(id: first.id)
        presentation.requestDeletion(next)
        // Reproduce an old presenter completing its teardown after the next
        // row's action. A Boolean reset would clear the new request here.
        presentation.dismiss(id: first.id)
        presentation.dismiss(id: nil)

        XCTAssertEqual(presentation.item, .deletion(next))
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertEqual(next.ids, [charts[1].id])
        presentation.dismiss(id: next.id)
        XCTAssertNil(presentation.item)
    }

    func testCancelAndRequestTheSameChartCreatesAFreshPresentation() {
        let chart = Chart.draft(title: "Keep until confirmed")
        let cancelled = IChartLibraryDeleteRequest(charts: [chart])
        let retried = IChartLibraryDeleteRequest(charts: [chart])
        var presentation = IChartLibraryAlertPresentation()
        presentation.requestDeletion(cancelled)
        presentation.dismiss(id: cancelled.id)
        presentation.requestDeletion(retried)
        presentation.dismiss(id: cancelled.id)

        XCTAssertNotEqual(cancelled.id, retried.id)
        XCTAssertEqual(presentation.item, .deletion(retried))
        XCTAssertEqual(retried.ids, cancelled.ids)
    }

    func testConfirmedSnapshotKeepsItsIDsWhileTheRowsChange() {
        let charts = [Chart.draft(title: "First"), Chart.draft(title: "Second"), Chart.draft(title: "Keep")]
        let store = ChartLibraryStore(charts: charts)
        let request = IChartLibraryDeleteRequest(charts: [charts[0]])
        var presentation = IChartLibraryAlertPresentation()
        presentation.requestDeletion(request)
        guard case .deletion(let confirmed) = presentation.item else {
            return XCTFail("The menu request must be presented")
        }

        presentation.dismiss(id: confirmed.id)
        XCTAssertEqual(store.deleteCharts(ids: confirmed.ids), 1)
        XCTAssertEqual(store.charts.map(\.id), [charts[1].id, charts[2].id])
        let next = IChartLibraryDeleteRequest(charts: [store.charts[0]])
        presentation.requestDeletion(next)
        presentation.dismiss(id: confirmed.id)
        XCTAssertEqual(presentation.item, .deletion(next))
        presentation.dismiss(id: next.id)
        XCTAssertEqual(store.deleteCharts(ids: next.ids), 1)
        XCTAssertEqual(store.charts, [charts[2]])
        XCTAssertEqual(Set(store.deletionTombstones.map(\.chartID)), [charts[0].id, charts[1].id])
    }

    func testDeleteDismissalCannotEraseSaveFailureAndFailureCannotEraseNextRequest() throws {
        let request = IChartLibraryDeleteRequest(charts: [Chart.draft(title: "Chart")])
        var presentation = IChartLibraryAlertPresentation()
        presentation.requestDeletion(request)
        presentation.dismiss(id: request.id)
        presentation.presentFailure("Could not save")
        let failureID = try XCTUnwrap(presentation.item?.id)
        presentation.dismiss(id: request.id)
        XCTAssertEqual(presentation.item, .failure(id: failureID, message: "Could not save"))

        let next = IChartLibraryDeleteRequest(charts: [Chart.draft(title: "Next")])
        presentation.dismiss(id: failureID)
        presentation.requestDeletion(next)
        presentation.dismiss(id: failureID)
        XCTAssertEqual(presentation.item, .deletion(next))
    }

    func testRepeatedIdenticalSaveErrorsHaveDistinctPresentations() throws {
        var presentation = IChartLibraryAlertPresentation()
        presentation.presentFailure("Could not save")
        let firstID = try XCTUnwrap(presentation.item?.id)
        presentation.dismiss(id: firstID)
        presentation.presentFailure("Could not save")
        let secondID = try XCTUnwrap(presentation.item?.id)
        presentation.dismiss(id: firstID)
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(presentation.item, .failure(id: secondID, message: "Could not save"))
    }

    func testEmptySelectionDoesNotOpenOrReplaceAConfirmation() {
        let request = IChartLibraryDeleteRequest(charts: [Chart.draft(title: "Chart")])
        var presentation = IChartLibraryAlertPresentation()
        presentation.requestDeletion(IChartLibraryDeleteRequest(charts: []))
        XCTAssertNil(presentation.item)
        presentation.requestDeletion(request)
        presentation.requestDeletion(IChartLibraryDeleteRequest(charts: []))
        XCTAssertEqual(presentation.item, .deletion(request))
    }
}
