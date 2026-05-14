import XCTest
@testable import SmartChart

final class ChartLibraryStoreTests: XCTestCase {
    private final class RecordingChartRepository: ChartRepository {
        var snapshotToLoad: ChartLibrarySnapshot?
        private(set) var savedSnapshots: [ChartLibrarySnapshot] = []

        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            snapshotToLoad
        }

        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
            savedSnapshots.append(snapshot)
        }
    }

    func testFreePlanPreventsCreatingPastTheChartLimit() {
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(charts: charts, entitlements: .free)

        let didCreateChart = store.createBlankChart()

        XCTAssertFalse(didCreateChart)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedFreeChartLimit)
    }

    func testProPlanAllowsCreatingMoreCharts() {
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        let didCreateChart = store.createBlankChart(in: .bFlatMajor)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedFreeChartLimit + 1)
        XCTAssertEqual(store.charts.first?.documentKey, .bFlatMajor)
    }

    func testSetPlanUpdatesActiveEntitlements() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts, entitlements: .free)

        store.setPlan(.studioSubscription)

        XCTAssertEqual(store.entitlements.activePlan, .studioSubscription)
        XCTAssertTrue(store.canUse(.cloudBackup))
    }

    func testCreateBlankChartPersistsUpdatedSnapshot() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(
            charts: ChartSamples.previewCharts,
            repository: repository
        )

        let didCreateChart = store.createBlankChart(in: .gMajor)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(repository.savedSnapshots.last?.charts.first?.documentKey, .gMajor)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, store.selectedChartID)
    }

    func testCreateBlankChartCreatesUnconfiguredDraftPage() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts)

        let didCreateChart = store.createBlankChart()

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.first?.measures.count, 0)
        XCTAssertEqual(store.charts.first?.systems.count, 0)
        XCTAssertEqual(store.charts.first?.hasCompletedInitialSetup, false)
    }

    #if DEBUG
    func testCreateChordWritingTestChartResetsDisposablePreparedChart() throws {
        let existingTestChart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 2)
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        } + [existingTestChart]
        var didResetDiagnostics = false
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: .free,
            chordDiagnosticsResetter: {
                didResetDiagnostics = true
            }
        )

        let chartID = store.createChordWritingTestChart()

        let testChart = try XCTUnwrap(store.charts.first)
        XCTAssertTrue(didResetDiagnostics)
        XCTAssertEqual(testChart.id, chartID)
        XCTAssertEqual(testChart.title, "Chord Writing Test Chart")
        XCTAssertEqual(testChart.styleNote, "CHORD TEST LOOP")
        XCTAssertTrue(testChart.hasCompletedInitialSetup)
        XCTAssertEqual(testChart.measures.count, 8)
        XCTAssertEqual(testChart.measures.last?.barlineAfter, .double)
        XCTAssertTrue(testChart.measures.allSatisfy { $0.chordEvents.isEmpty })
        XCTAssertEqual(store.selectedChartID, chartID)
        XCTAssertEqual(
            store.charts.filter { $0.title == "Chord Writing Test Chart" }.count,
            1
        )
    }
    #endif

    func testSetPlanPersistsEntitlementsSnapshot() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(
            charts: ChartSamples.previewCharts,
            repository: repository
        )

        store.setPlan(.proLifetime)

        XCTAssertEqual(repository.savedSnapshots.last?.entitlements.activePlan, .proLifetime)
    }

    func testSnapshotInitializerPreservesValidSelection() {
        let charts = ChartSamples.previewCharts
        let snapshot = ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: charts.last?.id,
            entitlements: .free
        )

        let store = ChartLibraryStore(snapshot: snapshot)

        XCTAssertEqual(store.selectedChartID, charts.last?.id)
    }

    func testUniversalRhythmGuideSupportsExpectedReferenceSymbols() {
        XCTAssertEqual(
            Set(RhythmicNotationPrimitive.supportedUniversalGuidePrimitives),
            Set([
                .wholeNote,
                .halfNote,
                .dottedHalfNote,
                .quarterNote,
                .slash,
                .dottedQuarterNote,
                .eighthNote,
                .wholeRest,
                .quarterRest,
                .halfRest,
                .eighthRest
            ])
        )
        XCTAssertEqual(
            Set(RhythmicNotationPrimitive.pendingUniversalGuidePrimitives),
            Set([.tie])
        )
    }
}
