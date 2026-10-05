#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Real canvas-owner integration; preparation-only tests cannot prove clearing.
@MainActor
final class ChordInkDraftLiveRenderTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testCompleteLiveSourceIsConsumedAndReturnedChartContainsEventsInBothStyles() async throws {
        for style in styles {
            let chart = makeChart(style)
            let host = try makeHost(chart)
            defer { host.window.isHidden = true }
            host.canvas.drawing = drawing()
            host.view.canvasViewDrawingDidChange(host.canvas)
            let state = makeState(chart, drawing: host.canvas.drawing, pageSize: host.view.bounds.size)

            let outcome = try XCTUnwrap(host.view.renderChordDraftAtomically(chart: chart, state: state))

            XCTAssertTrue(outcome.canConsumeSource, style.rawValue)
            XCTAssertEqual(outcome.result.renderedChordCount, 2)
            XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(outcome.chart.measures.flatMap(\.chordEvents).count, 2)
            XCTAssertNil(outcome.chart.pageHandwrittenChordData)
            XCTAssertNil(outcome.chart.pageHandwrittenChordCoordinateSpace)
            XCTAssertTrue(host.canvas.drawing.strokes.isEmpty,
                "A successful preparation must also consume the real live canvas")
            XCTAssertEqual(host.view.chart, chart, "UIKit returns the chart; Editor publishes it after consumption")
            host.view.chart = outcome.chart
            host.view.layoutIfNeeded()
            XCTAssertTrue(host.canvas.drawing.strokes.isEmpty, "Publishing the returned model must not restore consumed ink")
        }
    }

    func testPersistedSourceCannotAuthorizeClearingAdditionalCurrentLiveInk() async throws {
        for style in styles {
            var chart = makeChart(style)
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(10)]).dataRepresentation())
            let stored = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let state = makeState(chart, drawing: stored, pageSize: pageSize)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
            let host = try makeHost(chart)
            defer { host.window.isHidden = true }
            host.canvas.drawing = PKDrawing(strokes: stored.strokes + [stroke(90)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            let actualBytes = host.canvas.drawing.dataRepresentation()
            let originalChart = host.view.chart

            let outcome = try XCTUnwrap(host.view.renderChordDraftAtomically(chart: chart, state: state))

            XCTAssertFalse(outcome.canConsumeSource, style.rawValue)
            XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertEqual(outcome.chart, chart)
            XCTAssertEqual(host.view.chart, originalChart)
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), actualBytes,
                "Rejection must preserve the entire current source, not just the newly added stroke")
            XCTAssertEqual(host.canvas.drawing.strokes.count, 2)
        }
    }

    func testActualDrawingClearsEvenWhenDelegateHasNotUpdatedCachedStrokeCount() async throws {
        for style in styles {
            let chart = makeChart(style)
            let host = try makeHost(chart)
            defer { host.window.isHidden = true }
            XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
            let delegate = host.canvas.delegate
            host.canvas.delegate = nil
            defer { host.canvas.delegate = delegate }
            // A normal public canvas assignment with no delegate notification:
            // the host's loaded empty-canvas count remains zero.
            host.canvas.drawing = drawing()
            let state = makeState(chart, drawing: host.canvas.drawing, pageSize: host.view.bounds.size)

            let outcome = try XCTUnwrap(host.view.renderChordDraftAtomically(chart: chart, state: state))

            XCTAssertTrue(outcome.canConsumeSource, style.rawValue)
            XCTAssertEqual(outcome.result.renderedChordCount, 2)
            XCTAssertTrue(host.canvas.drawing.strokes.isEmpty,
                "Cached stroke count is not authority to skip destructive source consumption")
        }
    }

    func testActiveToolRejectsRenderAndEndUsingToolAllowsCompleteSource() async throws {
        for style in styles {
            let chart = makeChart(style)
            let host = try makeHost(chart)
            defer { host.window.isHidden = true }
            host.canvas.drawing = drawing()
            host.view.canvasViewDrawingDidChange(host.canvas)
            let state = makeState(chart, drawing: host.canvas.drawing, pageSize: host.view.bounds.size)
            let actualBytes = host.canvas.drawing.dataRepresentation()
            host.view.canvasViewDidBeginUsingTool(host.canvas)

            XCTAssertNil(host.view.renderChordDraftAtomically(chart: chart, state: state), style.rawValue)
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), actualBytes)
            XCTAssertEqual(host.view.chart, chart)

            host.view.canvasViewDidEndUsingTool(host.canvas)
            let outcome = try XCTUnwrap(host.view.renderChordDraftAtomically(chart: chart, state: state))
            XCTAssertTrue(outcome.canConsumeSource)
            XCTAssertTrue(host.canvas.drawing.strokes.isEmpty)
        }
    }

    func testWrongChartWrongScopeAndUnavailableResidentScopeNeverClearLiveInk() async throws {
        for style in styles {
            let chart = makeChart(style)
            let host = try makeHost(chart)
            defer { host.window.isHidden = true }
            host.canvas.drawing = drawing()
            host.view.canvasViewDrawingDidChange(host.canvas)
            let state = makeState(chart, drawing: host.canvas.drawing, pageSize: host.view.bounds.size)
            let actualBytes = host.canvas.drawing.dataRepresentation()
            let otherChart = makeChart(style)
            XCTAssertNotEqual(chart.id, otherChart.id)

            XCTAssertNil(host.view.renderChordDraftAtomically(chart: otherChart, state: state))
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), actualBytes)
            XCTAssertEqual(host.view.chart, chart)

            // Switch through the actual scope machinery, then install ordinary
            // page ink. It must not be treated as chord-source clearing authority.
            host.view.interactionMode = .freeHand
            host.canvas.drawing = drawing()
            host.view.canvasViewDrawingDidChange(host.canvas)
            let pageBytes = host.canvas.drawing.dataRepresentation()
            let pageChart = host.view.chart
            XCTAssertNil(host.view.renderChordDraftAtomically(chart: pageChart, state: state))
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), pageBytes)
            XCTAssertEqual(host.view.chart, pageChart)

            let unavailable = LeadSheetCanvasUIKitView(frame: .zero)
            unavailable.recognizesChordInk = false
            unavailable.chart = chart
            unavailable.interactionMode = .chordEntry
            let resident = try XCTUnwrap(unavailable.subviews.compactMap { $0 as? PKCanvasView }.last)
            resident.delegate = nil
            resident.drawing = drawing()
            let residentBytes = resident.drawing.dataRepresentation()
            XCTAssertNil(unavailable.renderChordDraftAtomically(chart: chart, state: state))
            XCTAssertEqual(resident.drawing.dataRepresentation(), residentBytes)
            XCTAssertEqual(unavailable.chart, chart)
        }
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
    }

    private func makeHost(_ chart: Chart) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        view.recognizesChordInk = false
        view.chart = chart
        view.interactionMode = .chordEntry
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvases = view.subviews.compactMap { $0 as? PKCanvasView }
        XCTAssertEqual(canvases.count, 3)
        let canvas = try XCTUnwrap(canvases.last)
        XCTAssertFalse(canvas.isHidden, "The real chord authoring surface must be active")
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        XCTAssertGreaterThan(canvas.bounds.height, 0)
        XCTAssertEqual(view.bounds.size, pageSize)
        return Host(view: view, canvas: canvas, window: window)
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Live render source ownership", layoutStyle: style)
        chart.completeInitialSetup(title: "Live render source ownership", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func makeState(_ chart: Chart, drawing: PKDrawing, pageSize: CGSize) -> ChordPreviewState {
        let normalized = LeadSheetPersistentInkColorPolicy.normalizedDrawing(drawing)
        let drafts = normalized.strokes.enumerated().map { index, stroke in
            ChordInkDraft(input: ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(normalized.strokes.count + 1), layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [stroke]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4, strokeCount: 1))
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }

    private func drawing() -> PKDrawing {
        PKDrawing(strokes: [stroke(10), stroke(90)])
    }

    private func stroke(_ x: CGFloat) -> PKStroke {
        let points = [CGPoint(x: x, y: 8), CGPoint(x: x + 14, y: 24)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.marker, color: .red),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 100)),
            transform: .identity, mask: nil, randomSeed: 17)
    }
}
#endif
