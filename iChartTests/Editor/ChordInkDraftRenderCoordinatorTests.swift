#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkDraftRenderCoordinatorTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testCompleteLiveInkCommitsAndClearsPreparedSourceInBothStylesWithoutMutatingInput() async throws {
        for style in styles {
            let chart = makeChart(style)
            let liveDrawing = PKDrawing(strokes: [stroke(10), stroke(90)])
            let originalBytes = liveDrawing.dataRepresentation()
            let state = makeState(chart, drawing: liveDrawing)

            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
                currentDrawing: liveDrawing, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))

            XCTAssertTrue(outcome.canConsumeSource, style.rawValue)
            XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(outcome.result.renderedChordCount, 2)
            XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(outcome.chart.measures.flatMap(\.chordEvents).count, 2)
            XCTAssertNil(outcome.chart.pageHandwrittenChordData)
            XCTAssertNil(outcome.chart.pageHandwrittenChordCoordinateSpace)
            XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
            XCTAssertNil(chart.pageHandwrittenChordData)
            XCTAssertEqual(liveDrawing.dataRepresentation(), originalBytes,
                "prepare must never consume or normalize the caller's canvas")
        }
    }

    func testOmittedNewLiveInkRejectsEvenWhenPersistedSnapshotHasCompleteCoverage() async throws {
        for style in styles {
            var chart = makeChart(style)
            let snapshot = PKDrawing(strokes: [stroke(10), stroke(90)])
            _ = chart.setPageHandwrittenChordDrawing(snapshot.dataRepresentation(),
                coordinateSpace: PersistentInkCoordinateSpace(size: CGSize(width: 700, height: 1_000)))
            let storedSnapshot = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let state = makeState(chart, drawing: storedSnapshot)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
            let originalChart = chart
            let currentDrawing = PKDrawing(strokes: storedSnapshot.strokes + [stroke(170)])

            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
                currentDrawing: currentDrawing, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))

            XCTAssertFalse(outcome.canConsumeSource, style.rawValue)
            XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertEqual(outcome.chart, originalChart,
                "A failed transaction cannot persist a new source snapshot or mutate any chart field")
        }
    }

    func testPartialUnresolvedCommitIsDiscardedAndEntireOriginalChartPreserved() async throws {
        for style in styles {
            var chart = makeChart(style)
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(250)]).dataRepresentation(),
                coordinateSpace: PersistentInkCoordinateSpace(size: CGSize(width: 700, height: 1_000)))
            let originalChart = chart
            let currentDrawing = PKDrawing(strokes: [stroke(10), stroke(90)])
            var state = makeState(chart, drawing: currentDrawing)
            state.draftChords[1].candidateTexts = []
            state.draftChords[1].bestCandidateText = nil
            state.draftChords[1].selectedText = nil

            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
                currentDrawing: currentDrawing, coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))

            XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage,
                "Recognition labels cannot change source coverage")
            XCTAssertEqual(outcome.result.renderedChordCount, 0,
                "The atomic batch must not report a rendered neighbor when one target remains unresolved")
            XCTAssertEqual(outcome.result.unresolvedDraftIDs, [state.draftChords[1].id])
            XCTAssertFalse(outcome.canConsumeSource)
            XCTAssertEqual(outcome.chart, originalChart, style.rawValue)
            XCTAssertTrue(outcome.chart.measures.allSatisfy(\.chordEvents.isEmpty))
        }
    }

    func testEmptyLiveCanvasRejectsStaleDraftsInsteadOfTakingNilStoredSourceShortcut() async throws {
        for style in styles {
            var chart = makeChart(style)
            let snapshot = PKDrawing(strokes: [stroke(10), stroke(90)])
            _ = chart.setPageHandwrittenChordDrawing(snapshot.dataRepresentation())
            let state = makeState(chart, drawing: try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData)))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))

            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
                currentDrawing: PKDrawing(), coordinateSpace: PersistentInkCoordinateSpace(size: pageSize))

            XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertFalse(outcome.canConsumeSource)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertEqual(outcome.chart, chart, style.rawValue)
        }
    }

    func testNoRendererAndUnavailableRendererReturnNilWhileRegisteredCallbackIsSynchronous() async throws {
        let coordinator = ChordInkDraftRenderCoordinator()
        let chart = makeChart(.simpleChordSheet)
        let currentDrawing = PKDrawing(strokes: [stroke(10), stroke(90)])
        let state = makeState(chart, drawing: currentDrawing)
        XCTAssertNil(coordinator.render(chart: chart, state: state))
        coordinator.renderer = { _, _ in nil }
        XCTAssertNil(coordinator.render(chart: chart, state: state))

        var calls = 0
        coordinator.renderer = { receivedChart, receivedState in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(receivedChart, chart)
            XCTAssertEqual(receivedState, state)
            calls += 1
            return ChordInkDraftRenderCoordinator.prepare(chart: receivedChart, state: receivedState,
                currentDrawing: currentDrawing, coordinateSpace: PersistentInkCoordinateSpace(size: self.pageSize))
        }
        let outcome = try XCTUnwrap(coordinator.render(chart: chart, state: state))
        XCTAssertEqual(calls, 1, "render must not enqueue a delayed source capture")
        XCTAssertTrue(outcome.canConsumeSource)
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Atomic render", layoutStyle: style)
        chart.completeInitialSetup(title: "Atomic render", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    func testLocalRewritePreparesOnlyRemainingInkWithoutChangingMusicalContentInBothStyles() async throws {
        for style in styles {
            let chart = makeChart(style)
            let live = PKDrawing(strokes: [stroke(10), stroke(90)])
            let originalBytes = live.dataRepresentation()
            let state = makeState(chart, drawing: live)
            let outcome = try XCTUnwrap(ChordInkDraftRenderCoordinator.prepareRewrite(
                chart: chart, state: state, draft: state.draftChords[0], currentDrawing: live,
                coordinateSpace: PersistentInkCoordinateSpace(size: pageSize)))
            XCTAssertEqual(outcome.chart.measures, chart.measures)
            XCTAssertEqual(outcome.chart.layoutStyle, chart.layoutStyle)
            XCTAssertEqual(outcome.chart.documentKey, chart.documentKey)
            XCTAssertEqual(outcome.chart.title, chart.title)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [live.strokes[1]]), current: outcome.drawing))
            let persisted = try PKDrawing(data: XCTUnwrap(outcome.chart.pageHandwrittenChordData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: outcome.drawing, current: persisted))
            XCTAssertEqual(live.dataRepresentation(), originalBytes)
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testLocalRewriteRejectsChangedTargetAndDuplicateNeighborWithoutMutation() async throws {
        let chart = makeChart(.simpleChordSheet)
        let live = PKDrawing(strokes: [stroke(10), stroke(90)])
        var state = makeState(chart, drawing: live)
        let target = state.draftChords[0]
        let modified = PKDrawing(strokes: [stroke(11), live.strokes[1]])
        XCTAssertNil(ChordInkDraftRenderCoordinator.prepareRewrite(chart: chart, state: state,
            draft: target, currentDrawing: modified, coordinateSpace: nil))
        state.draftChords[1].drawingData = target.drawingData
        XCTAssertNil(ChordInkDraftRenderCoordinator.prepareRewrite(chart: chart, state: state,
            draft: target, currentDrawing: live, coordinateSpace: nil))
        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    private func makeState(_ chart: Chart, drawing: PKDrawing) -> ChordPreviewState {
        let normalized = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        let drafts = normalized.strokes.enumerated().map { index, stroke in
            ChordInkDraft(input: ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(normalized.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4, strokeCount: 1))
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let points = [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.marker, color: .red),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif
