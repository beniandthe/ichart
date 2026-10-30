#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetDocumentViewportTests: XCTestCase {
    func testInitialViewportFitsTheWidthAndStartsAtTheTopOfTheSameLogicalDocument() throws {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport

        XCTAssertEqual(viewport.zoomScale, 800 / 932, accuracy: 0.0001)
        XCTAssertEqual(viewport.contentOffset.x, 0, accuracy: 0.001)
        XCTAssertEqual(viewport.contentOffset.y, 0, accuracy: 0.001)
        XCTAssertEqual(viewport.minimumZoomScale, viewport.fitWidthScale * 0.25, accuracy: 0.0001)
        XCTAssertEqual(viewport.maximumZoomScale, viewport.fitWidthScale * 4, accuracy: 0.0001)
        let initialPinch = try XCTUnwrap(viewport.pinchGestureRecognizer)
        XCTAssertTrue(initialPinch.isEnabled)
        XCTAssertEqual(initialPinch.allowedTouchTypes,
            [NSNumber(value: UITouch.TouchType.direct.rawValue)],
            "The first enabled pinch must exclude Pencil before any later model update.")
        XCTAssertTrue(initialPinch.requiresExclusiveTouchType)
        assertLogicalDocumentUnchanged(fixture)
    }

    func testMultiPageInteriorFocusAndUserZoomSurviveBothRotationDirections() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        let documentInstance = viewport.documentView
        viewport.setZoomScale(viewport.fitWidthScale * 1.8, animated: false)
        let focalPoint = CGPoint(x: 466, y: 1_900)
        center(focalPoint, in: viewport)
        assertFocalPoint(focalPoint, in: viewport)

        for size in [CGSize(width: 1_200, height: 650), CGSize(width: 800, height: 1_000)] {
            resize(viewport, to: size)
            XCTAssertEqual(viewport.zoomScale / viewport.fitWidthScale, 1.8, accuracy: 0.0001)
            assertFocalPoint(focalPoint, in: viewport)
            XCTAssertTrue(viewport.documentView === documentInstance,
                "Rotation must preserve the actual live drawing owner.")
            assertLogicalDocumentUnchanged(fixture)
        }
    }

    func testModelEchoesAndToolChangesPreserveZoomAndOffsetWithoutDefeatingScrollLock() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 2_400),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 2, animated: false)
        center(CGPoint(x: 460, y: 1_100), in: viewport)
        let scale = viewport.zoomScale
        let offset = viewport.contentOffset
        viewport.panGestureRecognizer.isEnabled = false

        for mode in [EditorCanvasMode.freeHand, .browse, .chordEntry, .headerEntry, .browse] {
            viewport.update(documentID: fixture.documentID,
                documentSize: fixture.documentSize, interactionMode: mode)
            viewport.layoutIfNeeded()
            XCTAssertEqual(viewport.zoomScale, scale, accuracy: 0.0001)
            XCTAssertEqual(viewport.contentOffset, offset)
            XCTAssertFalse(viewport.panGestureRecognizer.isEnabled,
                "A model or mode update must not release an active drag's scroll lock.")
            XCTAssertEqual(viewport.panGestureRecognizer.minimumNumberOfTouches,
                mode.allowsAnyInkEditing ? 2 : 1)
        }
        let directTouches = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        XCTAssertEqual(viewport.panGestureRecognizer.allowedTouchTypes, directTouches)
        XCTAssertEqual(viewport.pinchGestureRecognizer?.allowedTouchTypes, directTouches)
    }

    func testZoomingBelowFitCentersSmallContentOnBothAxes() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 300),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 0.25, animated: false)
        viewport.layoutIfNeeded()

        XCTAssertEqual(viewport.zoomScale, viewport.minimumZoomScale, accuracy: 0.0001)
        XCTAssertGreaterThan(viewport.contentInset.left, 0)
        XCTAssertGreaterThan(viewport.contentInset.top, 0)
        XCTAssertEqual(viewport.contentOffset.x, -viewport.contentInset.left, accuracy: oneScreenPixel(in: viewport))
        XCTAssertEqual(viewport.contentOffset.y, -viewport.contentInset.top, accuracy: oneScreenPixel(in: viewport))
        let documentCenter = viewport.documentContainerView.convert(
            CGPoint(x: fixture.documentSize.width / 2, y: fixture.documentSize.height / 2), to: viewport)
        XCTAssertEqual(documentCenter.x, viewport.bounds.midX, accuracy: oneScreenPixel(in: viewport))
        XCTAssertEqual(documentCenter.y, viewport.bounds.midY, accuracy: oneScreenPixel(in: viewport))
        assertLogicalDocumentUnchanged(fixture)
    }

    func testAChangedDocumentHeightPreservesTheInteriorFocusAndUserFactor() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 2_400),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 1.5, animated: false)
        let focalPoint = CGPoint(x: 466, y: 1_200)
        center(focalPoint, in: viewport)
        let enlargedDocument = CGSize(width: 932, height: 3_600)
        viewport.update(documentID: fixture.documentID,
            documentSize: enlargedDocument, interactionMode: .freeHand)
        viewport.layoutIfNeeded()

        XCTAssertEqual(viewport.zoomScale / viewport.fitWidthScale, 1.5, accuracy: 0.0001)
        assertFocalPoint(focalPoint, in: viewport)
        XCTAssertEqual(viewport.documentView.bounds.size, enlargedDocument)
        XCTAssertEqual(viewport.documentView.transform, .identity)
    }

    func testANewDocumentResetsToFitWidthAndTop() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 2, animated: false)
        center(CGPoint(x: 466, y: 1_900), in: viewport)
        let newID = UUID()
        viewport.update(documentID: newID,
            documentSize: fixture.documentSize, interactionMode: .freeHand)
        viewport.layoutIfNeeded()

        XCTAssertEqual(viewport.documentID, newID)
        XCTAssertEqual(viewport.zoomScale, viewport.fitWidthScale, accuracy: 0.0001)
        XCTAssertEqual(viewport.userZoomFactor, 1, accuracy: 0.0001)
        XCTAssertEqual(viewport.contentOffset, .zero)
    }

    func testRotationClampsOnlyTheFocusThatCannotRemainVisibleAtAnEdge() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 1_100),
            viewportSize: CGSize(width: 1_200, height: 650))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setContentOffset(CGPoint(x: 0,
            y: viewport.contentSize.height - viewport.bounds.height), animated: false)
        let oldFactor = viewport.userZoomFactor
        resize(viewport, to: CGSize(width: 800, height: 1_000))

        XCTAssertEqual(viewport.userZoomFactor, oldFactor, accuracy: 0.0001)
        XCTAssertEqual(viewport.contentOffset.y, -viewport.contentInset.top, accuracy: oneScreenPixel(in: viewport),
            "A short scaled document must center rather than leave an unreachable offset.")
        XCTAssertFalse(viewport.bounces)
        XCTAssertFalse(viewport.bouncesZoom)
        assertLogicalDocumentUnchanged(fixture)
    }

    func testSixtyFourRotationCyclesDoNotAccumulateCameraDriftBeyondOnePhysicalPixel() {
        for (portrait, landscape) in [(CGSize(width: 800, height: 1_000), CGSize(width: 1_200, height: 650)),
            (CGSize(width: 834, height: 1_024), CGSize(width: 1_194, height: 690))] {
            for (initialSize, otherSize) in [(portrait, landscape), (landscape, portrait)] {
                for userFactor in [CGFloat(1.3), CGFloat(1.8)] {
                    let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
                        viewportSize: initialSize)
                    defer { fixture.window.isHidden = true }
                    let viewport = fixture.viewport
                    viewport.setZoomScale(viewport.fitWidthScale * userFactor, animated: false)
                    center(CGPoint(x: 466, y: 1_900), in: viewport)
                    let initialActualFocus = actualFocalPoint(in: viewport)
                    for _ in 0..<64 {
                        resize(viewport, to: otherSize)
                        assertFocalPoint(initialActualFocus, in: viewport)
                        resize(viewport, to: initialSize)
                        assertFocalPoint(initialActualFocus, in: viewport)
                        XCTAssertEqual(viewport.userZoomFactor, userFactor, accuracy: 0.0001)
                        assertLogicalDocumentUnchanged(fixture)
                    }
                }
            }
        }
    }

    func testZoomedOutMultiPageFocusSurvivesTransitionsBetweenCenteredAndScrollableContent() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 0.25, animated: false)
        viewport.layoutIfNeeded()
        XCTAssertGreaterThan(viewport.contentInset.top, 0)
        let initialActualFocus = actualFocalPoint(in: viewport)
        for _ in 0..<32 {
            resize(viewport, to: CGSize(width: 1_200, height: 650))
            XCTAssertEqual(viewport.contentInset.top, 0)
            assertFocalPoint(initialActualFocus, in: viewport)
            resize(viewport, to: CGSize(width: 800, height: 1_000))
            XCTAssertGreaterThan(viewport.contentInset.top, 0)
            assertFocalPoint(initialActualFocus, in: viewport)
            XCTAssertEqual(viewport.userZoomFactor, 0.25, accuracy: 0.0001)
            assertLogicalDocumentUnchanged(fixture)
        }
    }

    func testSixtyPinchUpdatesCompositeExistingPaperAndRefreshSharpnessOnceAtTheEnd() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        var refreshScales: [CGFloat] = []
        viewport.onZoomChanged = { refreshScales.append($0) }
        viewport.scrollViewWillBeginZooming(viewport, with: viewport.documentContainerView)
        for step in 1...60 {
            viewport.setZoomScale(viewport.fitWidthScale * (1 + CGFloat(step) / 60), animated: false)
            viewport.layoutIfNeeded()
            XCTAssertTrue(refreshScales.isEmpty,
                "A pinch must transform existing pixels instead of resizing the full-page raster each frame.")
            assertLogicalDocumentUnchanged(fixture)
        }
        viewport.scrollViewDidEndZooming(viewport, with: viewport.documentContainerView,
            atScale: viewport.zoomScale)
        XCTAssertEqual(refreshScales.count, 1)
        XCTAssertEqual(refreshScales.last ?? 0, viewport.zoomScale, accuracy: 0.0001)
        XCTAssertEqual(viewport.userZoomFactor, 2, accuracy: 0.0001)
    }

    func testOverlappingPinchPanAndModelUpdatesWaitForDecelerationToFinish() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        var refreshScales: [CGFloat] = []
        viewport.onZoomChanged = { refreshScales.append($0) }
        viewport.scrollViewWillBeginDragging(viewport)
        viewport.scrollViewWillBeginZooming(viewport, with: viewport.documentContainerView)
        viewport.setZoomScale(viewport.fitWidthScale * 1.8, animated: false)
        for _ in 0..<20 {
            viewport.update(documentID: fixture.documentID, documentSize: fixture.documentSize,
                interactionMode: .freeHand)
            viewport.requestDocumentDisplayRefresh()
        }
        viewport.scrollViewDidEndZooming(viewport, with: viewport.documentContainerView,
            atScale: viewport.zoomScale)
        XCTAssertTrue(refreshScales.isEmpty, "Lifting the pinch must not redraw during a continuing pan.")
        viewport.scrollViewDidEndDragging(viewport, willDecelerate: true)
        for step in 1...30 {
            viewport.contentOffset.y = CGFloat(step) * 20
            viewport.requestDocumentDisplayRefresh()
        }
        XCTAssertTrue(refreshScales.isEmpty, "Momentum scrolling must not start deferred raster work.")
        let focus = actualFocalPoint(in: viewport)
        viewport.scrollViewDidEndDecelerating(viewport)
        XCTAssertEqual(refreshScales.count, 1)
        XCTAssertEqual(refreshScales.last ?? 0, viewport.zoomScale, accuracy: 0.0001)
        assertFocalPoint(focus, in: viewport)
        assertLogicalDocumentUnchanged(fixture)
    }

    func testEndingPanBeforePinchStillWaitsAndPlainPanDoesNotRequestAnExtraRedraw() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        var refreshCount = 0
        viewport.onZoomChanged = { _ in refreshCount += 1 }
        viewport.scrollViewWillBeginDragging(viewport)
        viewport.scrollViewWillBeginZooming(viewport, with: viewport.documentContainerView)
        viewport.setZoomScale(viewport.fitWidthScale * 1.5, animated: false)
        viewport.scrollViewDidEndDragging(viewport, willDecelerate: false)
        XCTAssertEqual(refreshCount, 0)
        viewport.scrollViewDidEndZooming(viewport, with: viewport.documentContainerView,
            atScale: viewport.zoomScale)
        XCTAssertEqual(refreshCount, 1)
        viewport.scrollViewWillBeginDragging(viewport)
        viewport.contentOffset.y += 100
        viewport.scrollViewDidEndDragging(viewport, willDecelerate: false)
        XCTAssertEqual(refreshCount, 1, "Panning alone does not change raster sharpness.")
    }

    func testRotationDuringPinchKeepsFocusWithoutStartingRasterWorkUntilGestureEnds() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        viewport.setZoomScale(viewport.fitWidthScale * 1.8, animated: false)
        center(CGPoint(x: 466, y: 1_900), in: viewport)
        let focus = actualFocalPoint(in: viewport)
        var refreshCount = 0
        viewport.onZoomChanged = { _ in refreshCount += 1 }
        viewport.scrollViewWillBeginZooming(viewport, with: viewport.documentContainerView)
        resize(viewport, to: CGSize(width: 1_200, height: 650))
        XCTAssertEqual(refreshCount, 0)
        assertFocalPoint(focus, in: viewport)
        XCTAssertEqual(viewport.userZoomFactor, 1.8, accuracy: 0.0001)
        viewport.scrollViewDidEndZooming(viewport, with: viewport.documentContainerView,
            atScale: viewport.zoomScale)
        XCTAssertEqual(refreshCount, 1)
        assertLogicalDocumentUnchanged(fixture)
    }

    func testDetachingDuringAGestureCannotLeaveFutureRefreshesBlocked() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        var refreshCount = 0
        viewport.onZoomChanged = { _ in refreshCount += 1 }
        viewport.scrollViewWillBeginDragging(viewport)
        viewport.requestDocumentDisplayRefresh()
        XCTAssertEqual(refreshCount, 0)
        viewport.removeFromSuperview()
        fixture.window.rootViewController?.view.addSubview(viewport)
        XCTAssertEqual(refreshCount, 1)
        viewport.requestDocumentDisplayRefresh()
        XCTAssertEqual(refreshCount, 2)
    }

    func testANewPinchReleasesAnInterruptedMomentumWaitWithoutRefreshingMidGesture() {
        let fixture = makeViewport(documentSize: CGSize(width: 932, height: 3_600),
            viewportSize: CGSize(width: 800, height: 1_000))
        defer { fixture.window.isHidden = true }
        let viewport = fixture.viewport
        var refreshCount = 0
        viewport.onZoomChanged = { _ in refreshCount += 1 }
        viewport.scrollViewWillBeginDragging(viewport)
        viewport.requestDocumentDisplayRefresh()
        viewport.scrollViewDidEndDragging(viewport, willDecelerate: true)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertFalse(viewport.isDecelerating,
            "This lifecycle replay represents momentum that UIKit has already interrupted.")
        viewport.scrollViewWillBeginZooming(viewport, with: viewport.documentContainerView)
        viewport.setZoomScale(viewport.fitWidthScale * 1.6, animated: false)
        XCTAssertEqual(refreshCount, 0)
        viewport.scrollViewDidEndZooming(viewport, with: viewport.documentContainerView,
            atScale: viewport.zoomScale)
        XCTAssertEqual(refreshCount, 1,
            "A missing end-deceleration callback from the earlier gesture must not block sharpness forever.")
        assertLogicalDocumentUnchanged(fixture)
    }

    private struct Fixture {
        let window: UIWindow
        let viewport: LeadSheetDocumentViewport
        let documentID: UUID
        let documentSize: CGSize
    }

    private func makeViewport(documentSize: CGSize, viewportSize: CGSize) -> Fixture {
        let window = UIWindow(frame: CGRect(origin: .zero, size: viewportSize))
        let controller = UIViewController()
        window.rootViewController = controller
        let document = UIView()
        let viewport = LeadSheetDocumentViewport(documentView: document)
        viewport.frame = CGRect(origin: .zero, size: viewportSize)
        controller.view.addSubview(viewport)
        window.makeKeyAndVisible()
        viewport.frame = CGRect(origin: .zero, size: viewportSize)
        let documentID = UUID()
        viewport.update(documentID: documentID, documentSize: documentSize, interactionMode: .freeHand)
        viewport.setNeedsLayout()
        viewport.layoutIfNeeded()
        return Fixture(window: window, viewport: viewport,
            documentID: documentID, documentSize: documentSize)
    }

    private func resize(_ viewport: LeadSheetDocumentViewport, to size: CGSize) {
        viewport.frame = CGRect(origin: .zero, size: size)
        viewport.setNeedsLayout()
        viewport.layoutIfNeeded()
    }

    private func center(_ point: CGPoint, in viewport: LeadSheetDocumentViewport) {
        viewport.setContentOffset(CGPoint(x: point.x * viewport.zoomScale - viewport.bounds.width / 2,
            y: point.y * viewport.zoomScale - viewport.bounds.height / 2), animated: false)
        viewport.layoutIfNeeded()
    }

    private func assertFocalPoint(_ expected: CGPoint, in viewport: LeadSheetDocumentViewport,
        file: StaticString = #filePath, line: UInt = #line) {
        let actual = actualFocalPoint(in: viewport)
        // UIScrollView rounds contentOffset to screen pixels. Express that one
        // physical pixel in logical paper coordinates, without relaxing ink or
        // document-geometry comparisons.
        let tolerance = oneScreenPixel(in: viewport) / viewport.zoomScale
        XCTAssertEqual(actual.x, expected.x, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: tolerance, file: file, line: line)
    }

    private func actualFocalPoint(in viewport: LeadSheetDocumentViewport) -> CGPoint {
        viewport.documentContainerView.convert(
            CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY), from: viewport)
    }

    private func oneScreenPixel(in viewport: LeadSheetDocumentViewport) -> CGFloat {
        1 / max(1, viewport.window?.screen.scale ?? UIScreen.main.scale)
    }

    private func assertLogicalDocumentUnchanged(_ fixture: Fixture,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.viewport.documentView.frame,
            CGRect(origin: .zero, size: fixture.documentSize), file: file, line: line)
        XCTAssertEqual(fixture.viewport.documentView.bounds.size, fixture.documentSize,
            file: file, line: line)
        XCTAssertEqual(fixture.viewport.documentView.transform, .identity, file: file, line: line)
        XCTAssertEqual(fixture.viewport.documentContainerView.bounds.size, fixture.documentSize,
            file: file, line: line)
    }
}
#endif
