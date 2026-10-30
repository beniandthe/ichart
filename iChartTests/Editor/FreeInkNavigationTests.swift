#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FreeInkNavigationTests: XCTestCase {
    func testHostParentPanRequiresExactlyTwoDirectFingersAndLeavesPencilForInk() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        setMode(.freeHand, on: host.canvas)
        let pan = host.scrollView.panGestureRecognizer
        XCTAssertEqual(pan.minimumNumberOfTouches, 2,
            "A one-finger paper drag must not start the parent scroll.")
        XCTAssertEqual(pan.maximumNumberOfTouches, 2)
        XCTAssertEqual(pan.allowedTouchTypes.map(\.intValue), [UITouch.TouchType.direct.rawValue],
            "Pencil cannot count toward the two-finger threshold, including a finger plus Pencil.")
        XCTAssertTrue(pan.requiresExclusiveTouchType)
        XCTAssertTrue(host.scrollView.isScrollEnabled)
        XCTAssertFalse(host.authoring.isScrollEnabled)
        XCTAssertEqual(LeadSheetLiveInkInputPolicy.drawingPolicy(for: .freeHand, environment: .device), .pencilOnly)

        let blocker = try XCTUnwrap(host.scrollView.gestureRecognizers?.first {
            $0.name == "LeadSheetParentScrollPanBlocker"
        })
        XCTAssertFalse(blocker.isEnabled,
            "Disable the old blocker so its failure dependency cannot keep the two-finger native pan waiting.")
        setMode(.browse, on: host.canvas)
        XCTAssertTrue(blocker.isEnabled,
            "Select must restore the existing blocker for its normal gesture policy.")
        assertOriginalConfiguration(pan)
    }

    func testSelectAndOtherToolsRestoreTheActualParentConfiguration() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        for mode in [EditorCanvasMode.browse, .chordEntry, .headerEntry, .measureEdit] {
            setMode(.freeHand, on: host.canvas)
            XCTAssertEqual(host.scrollView.panGestureRecognizer.minimumNumberOfTouches, 2)
            setMode(mode, on: host.canvas)
            assertOriginalConfiguration(host.scrollView.panGestureRecognizer)
        }
    }

    func testRepeatedLayoutDoesNotReplaceTheSavedParentConfigurationAndDetachRestoresIt() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        setMode(.freeHand, on: host.canvas)
        for _ in 0..<4 {
            host.canvas.setNeedsLayout()
            host.canvas.layoutIfNeeded()
        }
        XCTAssertEqual(host.scrollView.panGestureRecognizer.minimumNumberOfTouches, 2)
        host.canvas.removeFromSuperview()
        assertOriginalConfiguration(host.scrollView.panGestureRecognizer)
        XCTAssertFalse(host.scrollView.gestureRecognizers?.contains {
            $0.name == "LeadSheetParentScrollPanBlocker"
        } ?? true)
    }

    func testMovingCanvasToAnotherScrollViewRestoresEachParentsOwnConfiguration() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        setMode(.freeHand, on: host.canvas)
        let secondScroll = UIScrollView(frame: host.scrollView.bounds)
        secondScroll.panGestureRecognizer.minimumNumberOfTouches = 3
        secondScroll.panGestureRecognizer.maximumNumberOfTouches = 4
        secondScroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        secondScroll.panGestureRecognizer.requiresExclusiveTouchType = false
        host.scrollView.addSubview(secondScroll)
        secondScroll.addSubview(host.canvas)
        host.canvas.setNeedsLayout()
        host.canvas.layoutIfNeeded()
        assertOriginalConfiguration(host.scrollView.panGestureRecognizer)
        XCTAssertEqual(secondScroll.panGestureRecognizer.minimumNumberOfTouches, 2)
        host.canvas.removeFromSuperview()
        XCTAssertEqual(secondScroll.panGestureRecognizer.minimumNumberOfTouches, 3)
        XCTAssertEqual(secondScroll.panGestureRecognizer.maximumNumberOfTouches, 4)
        XCTAssertEqual(secondScroll.panGestureRecognizer.allowedTouchTypes.map(\.intValue), [UITouch.TouchType.indirectPointer.rawValue])
        XCTAssertFalse(secondScroll.panGestureRecognizer.requiresExclusiveTouchType)
    }

    func testNativeScrollCanReachBothPageEdgesWithoutChangingInkOrItsCoordinateSpace() throws {
        let host = try makeHost()
        defer { host.window.isHidden = true }
        setMode(.freeHand, on: host.canvas)
        let point = CGPoint(x: host.authoring.bounds.width - 30, y: host.authoring.bounds.height - 30)
        let original = drawing(endingAt: point)
        host.authoring.drawing = original
        host.canvas.canvasViewDrawingDidChange(host.authoring)
        let snapshot = LeadSheetInkDrawingSnapshot(drawing: host.authoring.drawing)
        let frame = host.authoring.frame
        let chartBefore = host.canvas.chart
        let maximum = CGPoint(x: host.scrollView.contentSize.width - host.scrollView.bounds.width,
            y: host.scrollView.contentSize.height - host.scrollView.bounds.height)
        XCTAssertGreaterThan(maximum.x, 0)
        XCTAssertGreaterThan(maximum.y, 0)
        host.scrollView.setContentOffset(maximum, animated: false)
        XCTAssertEqual(host.scrollView.contentOffset, maximum)
        XCTAssertTrue(host.scrollView.bounds.contains(host.authoring.convert(point, to: host.scrollView)),
            "The ink at the far right and bottom of the logical paper must be reachable.")
        host.scrollView.setContentOffset(.zero, animated: false)
        XCTAssertEqual(host.scrollView.contentOffset, .zero)
        XCTAssertEqual(host.authoring.frame, frame)
        XCTAssertEqual(LeadSheetInkDrawingSnapshot(drawing: host.authoring.drawing), snapshot)
        XCTAssertEqual(host.canvas.chart.pageHandwrittenNotationData, chartBefore.pageHandwrittenNotationData)
        XCTAssertEqual(host.canvas.chart.pageHandwrittenNotationCoordinateSpace,
            chartBefore.pageHandwrittenNotationCoordinateSpace)
    }

    private struct Host {
        let window: UIWindow
        let scrollView: UIScrollView
        let canvas: LeadSheetCanvasUIKitView
        let authoring: PKCanvasView
    }

    private func makeHost() throws -> Host {
        let viewport = CGSize(width: 600, height: 700)
        let chart = Chart.blank(title: "Synthetic fixed paper", measureCount: 8, layoutStyle: .simpleChordSheet)
        let logicalWidth: CGFloat = 1_200
        // Match the production document extent. An arbitrary tall canvas adds
        // trailing blank space below fixed-height paper; scrolling to its end
        // would correctly move a bottom-of-paper stroke above the viewport.
        let paper = CGSize(width: logicalWidth,
            height: LeadSheetPageLayoutEngine.estimatedCanvasHeight(for: chart,
                pageSize: CGSize(width: logicalWidth, height: viewport.height)))
        let scroll = UIScrollView(frame: CGRect(origin: .zero, size: viewport))
        scroll.contentSize = paper
        scroll.panGestureRecognizer.minimumNumberOfTouches = 1
        scroll.panGestureRecognizer.maximumNumberOfTouches = 3
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        scroll.panGestureRecognizer.requiresExclusiveTouchType = false
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: paper))
        canvas.recognizesChordInk = false
        canvas.chart = chart
        scroll.addSubview(canvas)
        let controller = UIViewController()
        controller.view = scroll
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewport))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let authoring = try XCTUnwrap(canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
        return Host(window: window, scrollView: scroll, canvas: canvas, authoring: authoring)
    }

    private func setMode(_ mode: EditorCanvasMode, on canvas: LeadSheetCanvasUIKitView) {
        canvas.interactionMode = mode
        canvas.restrictsParentScrollToOutsideMargins = mode.restrictsPageScrollToOutsideMargins
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
    }

    private func assertOriginalConfiguration(_ pan: UIPanGestureRecognizer,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pan.minimumNumberOfTouches, 1, file: file, line: line)
        XCTAssertEqual(pan.maximumNumberOfTouches, 3, file: file, line: line)
        XCTAssertEqual(pan.allowedTouchTypes.map(\.intValue),
            [UITouch.TouchType.direct.rawValue, UITouch.TouchType.pencil.rawValue], file: file, line: line)
        XCTAssertFalse(pan.requiresExclusiveTouchType, file: file, line: line)
    }

    private func drawing(endingAt point: CGPoint) -> PKDrawing {
        let points = [CGPoint(x: point.x - 20, y: point.y - 20), point].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)))])
    }
}
#endif
