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

    func testMutatingChartElementPersistsEditedChartSnapshot() throws {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Editor Binding", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )
        let committedMeasureID = try XCTUnwrap(store.charts.first?.measures.first?.id)
        let unresolvedMeasureID = try XCTUnwrap(store.charts.first?.measures.dropFirst().first?.id)
        let pendingChordInk = Data("pending-editor-chord-ink".utf8)
        let committedRhythmInk = Data("committed-editor-rhythm-ink".utf8)
        let unresolvedRhythmInk = Data("unresolved-editor-rhythm-ink".utf8)
        let committedChordInk = Data("committed-editor-G-slash-B".utf8)

        store.charts[0].setPageHandwrittenChordDrawing(pendingChordInk)
        store.charts[0].setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            drawingData: committedRhythmInk,
            for: committedMeasureID
        )
        store.charts[0].setMeasureHandwrittenRhythmicNotationDrawing(
            unresolvedRhythmInk,
            for: unresolvedMeasureID
        )
        store.charts[0].appendRecognizedChord(
            try ChordSymbolParser.parse("G/B"),
            rawInput: "G/B",
            to: committedMeasureID,
            atFraction: 0.05,
            sourceInkData: committedChordInk,
            sourceCandidateSignature: ["G/B"]
        )

        let savedChart = try XCTUnwrap(repository.savedSnapshots.last?.charts.first)
        XCTAssertEqual(savedChart.id, chart.id)
        XCTAssertEqual(savedChart.pageHandwrittenChordData, pendingChordInk)
        XCTAssertEqual(
            savedChart.measure(id: committedMeasureID)?.rhythmMap?.values,
            [.quarter, .quarter, .quarter, .quarter]
        )
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.rhythmMap?.drawingData, committedRhythmInk)
        XCTAssertEqual(
            savedChart.measure(id: unresolvedMeasureID)?.handwrittenRhythmicNotationData,
            unresolvedRhythmInk
        )
        XCTAssertNil(savedChart.measure(id: unresolvedMeasureID)?.rhythmMap)
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.rawInput, "G/B")
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.sourceInkData, committedChordInk)
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.sourceCandidateSignature, ["G/B"])
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, chart.id)
    }

    func testCreateBlankChartCreatesUnconfiguredDraftPage() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts)

        let didCreateChart = store.createBlankChart()

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.first?.measures.count, 0)
        XCTAssertEqual(store.charts.first?.systems.count, 0)
        XCTAssertEqual(store.charts.first?.hasCompletedInitialSetup, false)
    }

    func testCreateBlankChartUsesSelectedLayoutStyle() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts)

        let didCreateChart = store.createBlankChart(layoutStyle: .rhythmSectionSheet)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.first?.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(store.charts.first?.engravingPreset, .wide)
        XCTAssertEqual(store.charts.first?.stylePreset, .gigSheet)
    }

    func testV1NewChartOptionsExposeOnlyActiveReleaseStyles() {
        XCTAssertEqual(ChartLayoutStyle.v1NewChartOptions, [.simpleChordSheet, .rhythmSectionSheet])
        XCTAssertTrue(ChartLayoutStyle.allCases.contains(.leadSheet))
        XCTAssertFalse(ChartLayoutStyle.v1NewChartOptions.contains(.leadSheet))
    }

    func testLibrarySummaryHidesKeyForStylesThatDoNotExposeKeySetup() {
        var simpleChart = Chart.blank(
            title: "Simple",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        simpleChart.defaultMeter = Meter(numerator: 3, denominator: 4)
        var rhythmChart = Chart.blank(
            title: "Rhythm",
            key: .eFlatMajor,
            measureCount: 8,
            layoutStyle: .rhythmSectionSheet
        )
        rhythmChart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let leadChart = Chart.blank(
            title: "Lead",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .leadSheet
        )

        XCTAssertEqual(simpleChart.librarySummaryText, "Simple Chord Sheet · 3/4 · 4 measures")
        XCTAssertEqual(rhythmChart.librarySummaryText, "Rhythm Section Sheet · 6/8 · 8 measures")
        XCTAssertEqual(leadChart.librarySummaryText, "Lead Sheet · Bb major · 4/4 · 4 measures")
    }

    func testLibrarySummaryUsesSetupPendingForUnconfiguredDraft() {
        let draft = Chart.draft(title: "New Chart", layoutStyle: .rhythmSectionSheet)

        XCTAssertEqual(draft.librarySummaryText, "Rhythm Section Sheet · setup pending")
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
