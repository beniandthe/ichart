import Foundation
import XCTest
@testable import iChart

final class ChartCreationTransactionTests: XCTestCase {
    private final class RecordingRepository: ChartRepository {
        var savesSnapshotsOffMainThread = false
        var savedSnapshots: [ChartLibrarySnapshot] = []
        var loadError: Error?
        var snapshotToLoad: ChartLibrarySnapshot?

        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            if let loadError { throw loadError }
            return snapshotToLoad ?? savedSnapshots.last
        }
        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws { savedSnapshots.append(snapshot) }
    }

    func testPreparedCreationCommitsCompletedSetupAndProjectTogetherForBothLayouts() throws {
        for layout in ChartLayoutStyle.v1NewChartOptions {
            let repository = RecordingRepository()
            let existing = Chart.blank(title: "Existing", layoutStyle: layout)
            let project = ChartProject(title: "Rehearsal", chartIDs: [existing.id])
            let store = ChartLibraryStore(charts: [existing], selectedChartID: existing.id,
                projects: [project], repository: repository)
            var prepared = Chart.draft(title: "Untitled Chart", key: .cMajor, layoutStyle: layout)
            prepared.completeInitialSetup(title: prepared.title, key: .eFlatMajor,
                meter: Meter(numerator: 3, denominator: 4), staffStyle: .fiveLine,
                startingMeasureCount: 6, clef: .bass, stylePreset: .plainWhite)

            XCTAssertEqual(store.charts, [existing], "Preparing a local chart must leave the library alone")
            XCTAssertTrue(repository.savedSnapshots.isEmpty)

            XCTAssertTrue(store.createPreparedChart(prepared, projectID: project.id))
            XCTAssertEqual(store.charts.first, prepared, "Creation must retain every staged setup value and identity")
            XCTAssertEqual(store.selectedChartID, prepared.id)
            XCTAssertEqual(store.projects.first?.chartIDs, [prepared.id, existing.id])
            XCTAssertEqual(repository.savedSnapshots.count, 1, "Chart, selection and project must be one persisted batch")

            let saved = try XCTUnwrap(repository.savedSnapshots.last)
            let reopened = try ChartPersistenceCoders.decoder.decode(ChartLibrarySnapshot.self,
                from: ChartPersistenceCoders.encoder.encode(saved))
            XCTAssertEqual(reopened.charts.first, prepared)
            XCTAssertEqual(reopened.projects.first?.chartIDs, [prepared.id, existing.id])
            XCTAssertTrue(try XCTUnwrap(reopened.charts.first).hasCompletedInitialSetup,
                "Opening the created chart must not reopen mandatory initial setup")
        }
    }

    func testIncompleteOrDuplicateCreationDoesNotMutateOrSaveTheLibrary() {
        let repository = RecordingRepository()
        let existing = Chart.blank(title: "Existing", layoutStyle: .simpleChordSheet)
        let store = ChartLibraryStore(charts: [existing], selectedChartID: existing.id, repository: repository)
        let initial = store.snapshot

        XCTAssertFalse(store.createPreparedChart(Chart.draft(title: "Unsaved", key: .cMajor,
            layoutStyle: .rhythmSectionSheet)))
        XCTAssertFalse(store.createPreparedChart(existing))
        XCTAssertEqual(store.snapshot, initial)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
    }

    func testCreationRechecksChartLimitAtFinalCommit() {
        let repository = RecordingRepository()
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map { Chart.blank(title: "Chart \($0)") }
        let store = ChartLibraryStore(charts: charts,
            entitlements: AppEntitlements(activePlan: .free, accessPolicy: .paidSubscription),
            selectedChartID: charts[0].id, repository: repository)
        let initial = store.snapshot

        XCTAssertFalse(store.createPreparedChart(Chart.blank(title: "Prepared", layoutStyle: .simpleChordSheet)))
        XCTAssertEqual(store.snapshot, initial)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
    }

    func testMissingProjectCannotCreateAnOrphanedChart() {
        let repository = RecordingRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)

        XCTAssertFalse(store.createPreparedChart(Chart.blank(title: "Prepared", layoutStyle: .rhythmSectionSheet),
            projectID: UUID()))
        XCTAssertTrue(store.charts.isEmpty)
        XCTAssertNil(store.selectedChartID)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
    }

    func testPreparedCreationIsBlockedUntilUnreadLibraryHasBeenRecovered() {
        for layout in ChartLayoutStyle.v1NewChartOptions {
            let repository = RecordingRepository()
            repository.loadError = CocoaError(.fileReadCorruptFile)
            let store = ChartLibraryStore.live(repository: repository)
            store.applyAccessPolicy(.freeAllFeatures)
            XCTAssertTrue(store.hasUnresolvedLoadFailure)
            XCTAssertTrue(store.canCreateChart, "Capacity must not hide the load-quarantine guard")
            let quarantinedSnapshot = store.snapshot
            let prepared = Chart.blank(title: "Prepared", layoutStyle: layout)
            var notificationCount = 0
            store.onSnapshotSaved = { _ in notificationCount += 1 }

            XCTAssertFalse(store.createPreparedChart(prepared))
            XCTAssertEqual(store.snapshot, quarantinedSnapshot)
            XCTAssertTrue(repository.savedSnapshots.isEmpty)
            XCTAssertEqual(notificationCount, 0)

            repository.loadError = nil
            repository.snapshotToLoad = .empty
            XCTAssertTrue(store.retryLoadingSavedSnapshot())
            XCTAssertFalse(store.hasUnresolvedLoadFailure)
            XCTAssertTrue(store.createPreparedChart(prepared))
            XCTAssertEqual(store.charts, [prepared])
            XCTAssertEqual(repository.savedSnapshots.count, 1)
            XCTAssertEqual(notificationCount, 1)
        }
    }

    func testProjectAccessIsRecheckedBeforeCommittingPreparedChart() {
        let repository = RecordingRepository()
        let project = ChartProject(title: "Existing project")
        let store = ChartLibraryStore(charts: [],
            entitlements: AppEntitlements(activePlan: .free, accessPolicy: .paidSubscription),
            projects: [project], repository: repository)
        let initial = store.snapshot

        XCTAssertFalse(store.createPreparedChart(Chart.blank(title: "Prepared", layoutStyle: .simpleChordSheet),
            projectID: project.id))
        XCTAssertEqual(store.snapshot, initial)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
    }
}
