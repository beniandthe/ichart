import XCTest
@testable import iChart

@MainActor
final class LocalChartDowngradeAccessTests: XCTestCase {
    private final class RecordingRepository: ChartRepository {
        var snapshots: [ChartLibrarySnapshot] = []

        func loadSnapshot() throws -> ChartLibrarySnapshot? { snapshots.last }
        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { snapshots.append(snapshot) }
    }

    func testExpiredPaidProKeepsEverySavedChartEditableAboveBasicCapacity() throws {
        let charts = [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet].flatMap { style in
            (1...3).map { Chart.blank(title: "Saved \(style.rawValue) \($0)", layoutStyle: style) }
        }
        let repository = RecordingRepository()
        let store = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: .activePro(), accessPolicy: .paidSubscription),
            selectedChartID: charts.last?.id, repository: repository)

        store.applySubscriptionState(.proExpired())

        XCTAssertEqual(store.charts, charts, "Downgrading must not remove or rewrite saved charts")
        XCTAssertEqual(store.localChartLimit, 3)
        XCTAssertTrue(store.canUse(.pdfExport))
        XCTAssertFalse(store.canCreateChart)
        XCTAssertFalse(store.createBlankChart())
        XCTAssertFalse(store.createPreparedChart(Chart.blank(title: "New prepared chart")))
        XCTAssertNil(store.duplicateChart(id: charts[0].id))

        for chart in charts {
            let binding = try XCTUnwrap(store.editorBinding(for: chart.id))
            var edited = binding.wrappedValue
            edited.title += " edited"
            binding.wrappedValue = edited
            XCTAssertEqual(store.charts.first { $0.id == chart.id }, edited)
        }

        XCTAssertEqual(store.charts.map(\.id), charts.map(\.id))
        XCTAssertEqual(store.selectedChartID, charts.last?.id)
        let saved = try XCTUnwrap(repository.snapshots.last)
        XCTAssertEqual(saved.charts, store.charts)
        XCTAssertEqual(saved.charts.count, 6)
    }

    func testUnavailableBillingAndVoluntaryBetaBasicAlsoKeepOverCapacityChartsOpen() throws {
        let policies: [AppEntitlements] = [
            AppEntitlements(subscription: .basic, accessPolicy: .paidSubscription),
            AppEntitlements(subscription: .unavailable, accessPolicy: .paidSubscription),
            AppEntitlements(subscription: .basic, accessPolicy: .betaBasic)
        ]
        for entitlements in policies {
            let charts = (1...4).map { Chart.blank(title: "Retained \($0)") }
            let store = ChartLibraryStore(charts: charts, entitlements: entitlements)
            XCTAssertFalse(store.canCreateChart)
            XCTAssertEqual(store.charts, charts)
            for chart in charts {
                let binding = try XCTUnwrap(store.editorBinding(for: chart.id))
                XCTAssertEqual(binding.wrappedValue, chart)
                var edited = binding.wrappedValue
                edited.title += " edited"
                binding.wrappedValue = edited
                XCTAssertEqual(store.charts.first { $0.id == chart.id }, edited)
            }
            XCTAssertEqual(store.charts.map(\.id), charts.map(\.id))
        }
    }

    func testBasicCapacityOnlyBlocksNewChartsAndDuplicatesWhenAllThreeSlotsAreUsed() {
        let existing = (1...2).map { Chart.blank(title: "Saved \($0)") }
        let store = ChartLibraryStore(charts: existing,
            entitlements: AppEntitlements(subscription: .basic, accessPolicy: .paidSubscription))

        XCTAssertNotNil(store.duplicateChart(id: existing[0].id))
        XCTAssertEqual(store.charts.count, 3)
        XCTAssertFalse(store.canCreateChart)
        XCTAssertFalse(store.createBlankChart(layoutStyle: .rhythmSectionSheet))
        XCTAssertNil(store.duplicateChart(id: existing[1].id))
        XCTAssertTrue(store.renameChart(id: existing[1].id, to: "Still editable"))
        XCTAssertEqual(store.charts.first { $0.id == existing[1].id }?.title, "Still editable")
    }

    func testDowngradePreservesProjectMembershipReadOnlyWhileItsChartsRemainEditable() throws {
        let charts = (1...4).map { Chart.blank(title: "Part \($0)") }
        let store = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(subscription: .activePro(), accessPolicy: .paidSubscription))
        let projectID = try XCTUnwrap(store.createProject(title: "Saved song", chartIDs: charts.prefix(2).map(\.id)))
        let originalProjects = store.projects

        store.applySubscriptionState(.proExpired())

        let project = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(store.charts(in: project).map(\.id), Array(charts.prefix(2)).map(\.id))
        XCTAssertFalse(store.canUse(.projects))
        XCTAssertNil(store.createProject(title: "New project"))
        XCTAssertFalse(store.renameProject(id: projectID, to: "Renamed"))
        XCTAssertFalse(store.deleteProject(id: projectID))
        XCTAssertFalse(store.addChartToProject(chartID: charts[2].id, projectID: projectID))
        XCTAssertFalse(store.removeChartFromProject(chartID: charts[0].id, projectID: projectID))
        XCTAssertNil(store.duplicateChart(id: charts[0].id, projectID: projectID))
        XCTAssertFalse(store.createBlankChart(projectID: projectID))
        XCTAssertEqual(store.projects, originalProjects)

        let binding = try XCTUnwrap(store.editorBinding(for: charts[0].id))
        var edited = binding.wrappedValue
        edited.title = "Edited retained part"
        binding.wrappedValue = edited
        XCTAssertEqual(store.charts(in: project).first?.title, edited.title)
        XCTAssertEqual(store.projects, originalProjects)
    }

    func testBasicCannotAdmitEditablePDFConversionEvenBelowItsChartCapacity() async throws {
        let denied: [AppEntitlements] = [
            AppEntitlements(subscription: .basic, accessPolicy: .paidSubscription),
            AppEntitlements(subscription: .proExpired(), accessPolicy: .paidSubscription),
            AppEntitlements(subscription: .unavailable, accessPolicy: .paidSubscription),
            AppEntitlements(subscription: .basic, accessPolicy: .betaBasic)
        ]
        for entitlements in denied {
            let existing = Chart.blank(title: "Existing chart")
            let repository = RecordingRepository()
            let store = ChartLibraryStore(charts: [existing], entitlements: entitlements,
                selectedChartID: existing.id, repository: repository)
            let converted = try preparedPDFChart()

            XCTAssertTrue(store.canCreateChart, "The PDF gate is separate from ordinary chart capacity")
            let didSave = await store.saveConvertedPDFChart(converted)

            XCTAssertFalse(didSave)
            XCTAssertEqual(store.charts, [existing])
            XCTAssertEqual(store.selectedChartID, existing.id)
            XCTAssertTrue(repository.snapshots.isEmpty, "An unauthorized draft must never enter a persisted snapshot")
        }
    }

    func testPDFConversionRechecksAccessAfterReviewAndAllowsSameDraftAfterProReturns() async throws {
        let existing = Chart.blank(title: "Existing chart")
        let repository = RecordingRepository()
        let store = ChartLibraryStore(charts: [existing],
            entitlements: AppEntitlements(subscription: .activePro(), accessPolicy: .paidSubscription),
            selectedChartID: existing.id, repository: repository)
        let reviewedDraft = try preparedPDFChart()

        store.applySubscriptionState(.proExpired())
        let snapshotsBeforeSave = repository.snapshots.count
        let denied = await store.saveConvertedPDFChart(reviewedDraft)

        XCTAssertFalse(denied)
        XCTAssertEqual(store.charts, [existing])
        XCTAssertEqual(store.selectedChartID, existing.id)
        XCTAssertEqual(repository.snapshots.count, snapshotsBeforeSave)

        store.applySubscriptionState(.activePro())
        let retried = await store.saveConvertedPDFChart(reviewedDraft)

        XCTAssertTrue(retried)
        XCTAssertEqual(store.charts, [reviewedDraft, existing])
        XCTAssertEqual(store.charts.filter { $0.id == reviewedDraft.id }.count, 1)
        XCTAssertEqual(repository.snapshots.last?.charts, store.charts)
        XCTAssertEqual(store.selectedChartID, reviewedDraft.id)
    }

    func testFreeProBetaAndPaidProRetainEditablePDFCreation() async throws {
        let allowed: [AppEntitlements] = [
            AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures),
            AppEntitlements(subscription: .activePro(), accessPolicy: .paidSubscription)
        ]
        for entitlements in allowed {
            let converted = try preparedPDFChart()
            let repository = RecordingRepository()
            let store = ChartLibraryStore(charts: [], entitlements: entitlements, repository: repository)
            let didSave = await store.saveConvertedPDFChart(converted)
            XCTAssertTrue(didSave)
            XCTAssertEqual(store.charts, [converted])
            XCTAssertEqual(repository.snapshots.last?.charts, [converted])
            XCTAssertEqual(store.selectedChartID, converted.id)
        }
    }

    private func preparedPDFChart() throws -> Chart {
        try PDFEditableChartDraft(title: "Reviewed PDF", rows: [["Cmaj7", "Dm7 G7"]])
            .makeChart(sourcePDFLibraryItemID: UUID())
    }
}
