#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Runtime ownership checks, not a claim about physical Pencil palm rejection
/// or iPadOS software-keyboard visibility.
@MainActor
final class EditorPanelInputIsolationTests: XCTestCase {
    func testReviewSuspendsDrawingWithoutClearingInkOrReclaimingTypedFocus() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let host = try makeHost(style: style)
            defer { host.window.isHidden = true }
            host.canvas.drawing = drawing()
            host.view.canvasViewDrawingDidChange(host.canvas)
            let sourceBytes = host.canvas.drawing.dataRepresentation()

            host.view.isInteractionSuspended = true
            XCTAssertFalse(host.view.isUserInteractionEnabled)
            XCTAssertFalse(host.canvas.isFirstResponder)
            XCTAssertEqual(host.view.interactionMode, .chordEntry)
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)

            let field = IChartTypedUITextField(frame: CGRect(x: 20, y: 20, width: 300, height: 44))
            host.window.rootViewController?.view.addSubview(field)
            XCTAssertTrue(field.becomeFirstResponder())
            var chart = host.view.chart
            chart.title = "Review is typing"
            host.view.chart = chart
            host.view.layoutIfNeeded()
            await Task.yield()

            XCTAssertTrue(field.isFirstResponder, "Canvas synchronization must not steal review focus")
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)
            host.view.isInteractionSuspended = false
            XCTAssertTrue(host.view.isUserInteractionEnabled)
            XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)
        }
    }

    func testPanelSuspensionDoesNotChangeSavedInkOrCommittedChartObjects() throws {
        let host = try makeHost(style: .rhythmSectionSheet)
        defer { host.window.isHidden = true }
        let originalChart = host.view.chart
        host.canvas.drawing = drawing()
        let sourceBytes = host.canvas.drawing.dataRepresentation()
        host.view.isInteractionSuspended = true
        host.view.inkToolMode = .erase
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.isUserInteractionEnabled)
        XCTAssertEqual(host.view.chart, originalChart)
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)
        host.view.isInteractionSuspended = false
        XCTAssertTrue(host.view.isUserInteractionEnabled)
        XCTAssertEqual(host.view.chart, originalChart)
        XCTAssertEqual(host.canvas.drawing.dataRepresentation(), sourceBytes)
    }

    func testSuspendedPanelPreventsFocusWhenAnInkToolIsActivated() throws {
        let host = try makeHost(style: .simpleChordSheet)
        defer { host.window.isHidden = true }
        host.view.isInteractionSuspended = true
        host.view.interactionMode = .freeHand
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.isUserInteractionEnabled)
        XCTAssertFalse(host.canvas.isFirstResponder)
        host.view.interactionMode = .chordEntry
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.canvas.isFirstResponder)
        XCTAssertFalse(host.view.isUserInteractionEnabled)
    }

    private func makeHost(style: ChartLayoutStyle) throws -> (window: UIWindow, view: LeadSheetCanvasUIKitView, canvas: PKCanvasView) {
        let size = CGSize(width: 900, height: 1_400)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: size))
        window.rootViewController?.view.addSubview(view)
        view.recognizesChordInk = false
        view.chart = Chart.blank(title: "Panel input isolation", measureCount: 8, layoutStyle: style)
        view.interactionMode = .chordEntry
        view.layoutIfNeeded()
        let canvas = try XCTUnwrap(view.subviews.compactMap { $0 as? PKCanvasView }.last)
        return (window, view, canvas)
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 24, y: 20), CGPoint(x: 46, y: 34)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.02,
                          size: CGSize(width: 2, height: 2), opacity: 1,
                          force: 0.8, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 100)))])
    }
}
#endif
