#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Exercises the real canvas owner. A policy-only check cannot prove that the
/// resized canvas and the coordinates saved for its drawing still agree.
@MainActor
final class FinalDirtyChordInkRotationTests: XCTestCase {
    func testDirtyChordInkThenRotationThenNewStrokeReopensAtTheVisibleGeometryInBothStyles() throws {
        let portraitSize = CGSize(width: 800, height: 1_400)
        let landscapeSize = CGSize(width: 1_200, height: 1_200)

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let host = try makeHost(chart: makeChart(style), pageSize: portraitSize)
            defer { host.window.isHidden = true }
            let originalCanvasSize = host.canvas.bounds.size
            XCTAssertGreaterThan(originalCanvasSize.width, 0, style.rawValue)

            // The normal drawing callback makes the live chord role dirty.
            // Recognition is disabled only to keep this a coordinate/persistence
            // test; no private state or test-only hooks are used.
            host.canvas.drawing = PKDrawing(strokes: [stroke(x: 40, y: 24, seed: 1)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            XCTAssertEqual(host.canvas.drawing.strokes.count, 1, style.rawValue)
            let originalDrawing = host.canvas.drawing

            host.window.frame = CGRect(origin: .zero, size: landscapeSize)
            host.view.frame = CGRect(origin: .zero, size: landscapeSize)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let rotatedCanvasSize = host.canvas.bounds.size
            XCTAssertEqual(host.view.bounds.size, landscapeSize, style.rawValue)
            XCTAssertGreaterThan(rotatedCanvasSize.width - originalCanvasSize.width, 100,
                "The regression must exercise a real writing-frame width change: \(style.rawValue)")
            XCTAssertEqual(host.canvas.drawing.strokes.count, 1,
                "Rotation must preserve the original pending stroke: \(style.rawValue)")
            assertProjection(of: originalDrawing, from: originalCanvasSize,
                matches: host.canvas.drawing, in: rotatedCanvasSize, style: style)

            // This stroke is authored in the newly sized canvas. Save/reopen in
            // this same orientation must not transform either visible stroke.
            let postRotationStroke = stroke(x: rotatedCanvasSize.width * 0.7, y: 44, seed: 2)
            host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes + [postRotationStroke])
            host.view.canvasViewDrawingDidChange(host.canvas)
            let visibleDrawing = host.canvas.drawing
            XCTAssertEqual(visibleDrawing.strokes.count, 2, style.rawValue)

            try assertSaveAndReopen(host, pageSize: landscapeSize, visibleDrawing: visibleDrawing, style: style)
        }
    }

    func testRotationDuringActiveToolKeepsSourceFrameUntilEndAndProjectsOnceToLatestFrameInBothStyles() throws {
        let portraitSize = CGSize(width: 800, height: 1_400)
        let intermediateSize = CGSize(width: 1_200, height: 1_200)
        let finalSize = CGSize(width: 1_100, height: 1_300)

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let host = try makeHost(chart: makeChart(style), pageSize: portraitSize)
            defer { host.window.isHidden = true }
            host.canvas.drawing = PKDrawing(strokes: [stroke(x: 40, y: 24, seed: 1)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            let sourceFrame = host.canvas.frame
            let sourceSize = host.canvas.bounds.size
            let originalDrawing = host.canvas.drawing
            host.view.canvasViewDidBeginUsingTool(host.canvas)

            for size in [intermediateSize, finalSize] {
                resize(host, to: size)
                XCTAssertEqual(host.view.bounds.size, size, style.rawValue)
                XCTAssertEqual(host.canvas.frame, sourceFrame,
                    "A live stroke must finish in one frame: \(style.rawValue)")
                XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: host.canvas.drawing),
                    LeadSheetInkDrawingSnapshot(drawing: originalDrawing),
                    "No programmatic drawing transform is allowed mid-stroke: \(style.rawValue)")
            }

            // PencilKit delivers the stroke's last geometry in its original
            // frame before ending use of the tool.
            host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes
                + [stroke(x: sourceSize.width * 0.6, y: 44, seed: 2)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            let completedSourceDrawing = host.canvas.drawing
            XCTAssertEqual(host.canvas.frame, sourceFrame, style.rawValue)
            host.view.canvasViewDidEndUsingTool(host.canvas)

            let expectedLayout = LeadSheetPageLayoutEngine.pageLayout(for: host.view.chart,
                pageSize: finalSize, includesChordInkContinuationLanes: true)
            let finalFrame = LeadSheetActiveInkScope.chordWritingFrame(for: expectedLayout)
            XCTAssertEqual(host.canvas.frame, finalFrame,
                "Tool end must adopt the latest, not the intermediate, frame: \(style.rawValue)")
            XCTAssertNotEqual(host.canvas.bounds.size, sourceSize, style.rawValue)
            assertProjection(of: completedSourceDrawing, from: sourceSize,
                matches: host.canvas.drawing, in: host.canvas.bounds.size, style: style)

            let afterToolEnd = host.canvas.drawing
            resize(host, to: finalSize)
            XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: host.canvas.drawing),
                LeadSheetInkDrawingSnapshot(drawing: afterToolEnd),
                "Repeating the applied geometry must not project twice: \(style.rawValue)")
            host.canvas.drawing = PKDrawing(strokes: afterToolEnd.strokes
                + [stroke(x: host.canvas.bounds.width * 0.7, y: 60, seed: 3)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            try assertSaveAndReopen(host, pageSize: finalSize,
                visibleDrawing: host.canvas.drawing, style: style)
        }
    }

    func testRepeatedDirtyRotationAndStaleSameGeometryModelUpdatesKeepResidentInkInBothStyles() throws {
        let portraitSize = CGSize(width: 800, height: 1_400)
        let landscapeSize = CGSize(width: 1_200, height: 1_200)

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let originalChart = makeChart(style)
            let host = try makeHost(chart: originalChart, pageSize: portraitSize)
            defer { host.window.isHidden = true }
            host.canvas.drawing = PKDrawing(strokes: [stroke(x: 40, y: 24, seed: 1)])
            host.view.canvasViewDrawingDidChange(host.canvas)
            for (index, size) in [landscapeSize, portraitSize, landscapeSize].enumerated() {
                let before = host.canvas.drawing
                let beforeSize = host.canvas.bounds.size
                resize(host, to: size)
                XCTAssertNotEqual(host.canvas.bounds.size, beforeSize, style.rawValue)
                assertProjection(of: before, from: beforeSize,
                    matches: host.canvas.drawing, in: host.canvas.bounds.size, style: style)
                host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes
                    + [stroke(x: host.canvas.bounds.width * 0.7,
                        y: CGFloat(44 + index * 16), seed: UInt32(index + 2))])
                host.view.canvasViewDrawingDidChange(host.canvas)
                let residentDrawing = host.canvas.drawing
                let residentFrame = host.canvas.frame

                // A stale model refresh with no geometry change must not load
                // its empty stored drawing over the pending resident source.
                var staleModel = originalChart
                staleModel.updatedAt = Date(timeIntervalSinceReferenceDate: Double(20 + index))
                host.view.chart = staleModel
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.canvas.frame, residentFrame, style.rawValue)
                XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: host.canvas.drawing),
                    LeadSheetInkDrawingSnapshot(drawing: residentDrawing),
                    "Same-geometry model refresh must preserve dirty live ink: \(style.rawValue)")
            }
            try assertSaveAndReopen(host, pageSize: landscapeSize,
                visibleDrawing: host.canvas.drawing, style: style)
        }
    }

    func testDirtyReprojectionRequiresChangedCoordinatesAndTheSameResidentScope() {
        XCTAssertFalse(LeadSheetInkCanvasSyncPolicy.shouldReprojectActiveCanvas(
            currentScopeIdentity: .chords, targetScopeIdentity: .chords,
            shouldPreserveDirtyActiveCanvas: true, hasCoordinateSpaceChange: false))
        XCTAssertTrue(LeadSheetInkCanvasSyncPolicy.shouldReprojectActiveCanvas(
            currentScopeIdentity: .chords, targetScopeIdentity: .chords,
            shouldPreserveDirtyActiveCanvas: true, hasCoordinateSpaceChange: true))
        XCTAssertFalse(LeadSheetInkCanvasSyncPolicy.shouldReprojectActiveCanvas(
            currentScopeIdentity: .page, targetScopeIdentity: .chords,
            shouldPreserveDirtyActiveCanvas: true, hasCoordinateSpaceChange: true))
        XCTAssertFalse(LeadSheetInkCanvasSyncPolicy.shouldReprojectActiveCanvas(
            currentScopeIdentity: nil, targetScopeIdentity: .chords,
            shouldPreserveDirtyActiveCanvas: true, hasCoordinateSpaceChange: true))
    }

    private func resize(_ host: Host, to pageSize: CGSize) {
        host.window.frame = CGRect(origin: .zero, size: pageSize)
        host.view.frame = CGRect(origin: .zero, size: pageSize)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    private func assertProjection(of source: PKDrawing, from sourceSize: CGSize,
        matches actual: PKDrawing, in targetSize: CGSize, style: ChartLayoutStyle,
        file: StaticString = #filePath, line: UInt = #line) {
        let expected = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(source,
            sourceCoordinateSpace: PersistentInkCoordinateSpace(size: sourceSize),
            targetCoordinateSpace: PersistentInkCoordinateSpace(size: targetSize))
        XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: actual),
            LeadSheetInkDrawingSnapshot(drawing: expected),
            "Resident ink must actually follow the new coordinates: \(style.rawValue)", file: file, line: line)
    }

    private func assertSaveAndReopen(_ host: Host, pageSize: CGSize,
        visibleDrawing: PKDrawing, style: ChartLayoutStyle,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let canvasSize = host.canvas.bounds.size
        // A real mode transition synchronously persists the outgoing dirty
        // canvas through the production canvas owner.
        host.view.interactionMode = .browse
        let savedChart = host.view.chart
        let savedSpace = try XCTUnwrap(savedChart.pageHandwrittenChordCoordinateSpace, file: file, line: line)
        XCTAssertEqual(savedSpace.size.width, canvasSize.width, accuracy: 0.001,
            "New ink must be stored in its visible coordinates: \(style.rawValue)", file: file, line: line)
        XCTAssertEqual(savedSpace.size.height, canvasSize.height, accuracy: 0.001,
            "The persisted height must describe the visible canvas: \(style.rawValue)", file: file, line: line)
        let persistedDrawing = try PKDrawing(data: XCTUnwrap(savedChart.pageHandwrittenChordData, file: file, line: line))
        XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: persistedDrawing),
            LeadSheetInkDrawingSnapshot(drawing: visibleDrawing),
            "Persistence itself must preserve all live ink: \(style.rawValue)", file: file, line: line)

        let reopenedChart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(savedChart))
        let reopenedHost = try makeHost(chart: reopenedChart, pageSize: pageSize)
        defer { reopenedHost.window.isHidden = true }
        XCTAssertEqual(reopenedHost.canvas.bounds.size, canvasSize, style.rawValue, file: file, line: line)
        XCTAssertEqual(reopenedHost.canvas.drawing.strokes.count, visibleDrawing.strokes.count,
            style.rawValue, file: file, line: line)
        XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: reopenedHost.canvas.drawing),
            LeadSheetInkDrawingSnapshot(drawing: visibleDrawing),
            "Same-orientation reopen must not shift or stretch ink: \(style.rawValue)", file: file, line: line)
        for index in visibleDrawing.strokes.indices where reopenedHost.canvas.drawing.strokes.indices.contains(index) {
            let expected = visibleDrawing.strokes[index].renderBounds
            let actual = reopenedHost.canvas.drawing.strokes[index].renderBounds
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01, "stroke \(index), \(style.rawValue)", file: file, line: line)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01, "stroke \(index), \(style.rawValue)", file: file, line: line)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, "stroke \(index), \(style.rawValue)", file: file, line: line)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, "stroke \(index), \(style.rawValue)", file: file, line: line)
        }
        XCTAssertEqual(reopenedChart.measures, savedChart.measures,
            "The coordinate test must not mutate musical content: \(style.rawValue)", file: file, line: line)
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let canvas: PKCanvasView
        let window: UIWindow
    }

    private func makeHost(chart: Chart, pageSize: CGSize) throws -> Host {
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
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertFalse(canvas.isHidden)
        XCTAssertTrue(canvas.isUserInteractionEnabled)
        XCTAssertGreaterThan(canvas.bounds.width, 0)
        XCTAssertGreaterThan(canvas.bounds.height, 0)
        return Host(view: view, canvas: canvas, window: window)
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Dirty rotation persistence", layoutStyle: style)
        chart.completeInitialSetup(title: "Dirty rotation persistence", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        return chart
    }

    private func stroke(x: CGFloat, y: CGFloat, seed: UInt32) -> PKStroke {
        let points = [CGPoint(x: x, y: y), CGPoint(x: x + 18, y: y + 12)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif
