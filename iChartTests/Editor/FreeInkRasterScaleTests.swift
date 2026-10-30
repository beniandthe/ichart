#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FreeInkRasterScaleTests: XCTestCase {
    private let pixelBudget: CGFloat = 16 * 1_024 * 1_024

    func testNormalHighZoomHonorsRequestedSharpnessAndTheEightScaleLimit() {
        let size = CGSize(width: 320, height: 240)
        XCTAssertEqual(LeadSheetCanvasUIKitView.boundedDocumentRasterScale(
            logicalSize: size, screenScale: 2, zoomScale: 3), 6, accuracy: 0.0001)
        XCTAssertEqual(LeadSheetCanvasUIKitView.boundedDocumentRasterScale(
            logicalSize: size, screenScale: 3, zoomScale: 10), 8, accuracy: 0.0001)
    }

    func testMultipageDocumentsStayWithinTheBackingPixelBudgetIncludingBelowScreenScale() {
        for size in [CGSize(width: 932, height: 3_600), CGSize(width: 932, height: 20_000)] {
            let scale = LeadSheetCanvasUIKitView.boundedDocumentRasterScale(
                logicalSize: size, screenScale: 2, zoomScale: 4)
            XCTAssertGreaterThan(scale, 0)
            XCTAssertLessThan(scale, 8)
            XCTAssertEqual(size.width * size.height * scale * scale, pixelBudget, accuracy: 0.001,
                "A high zoom must not allocate a backing bitmap proportional to zoom squared without a pixel cap.")
            if size.height == 20_000 {
                XCTAssertLessThan(scale, 1,
                    "The memory cap must take priority over a fixed 1x or screen-scale floor on long documents.")
            }
        }
    }

    func testExtremeFiniteLogicalSizeCannotOverflowTheMemoryLimitCalculation() {
        let size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let scale = LeadSheetCanvasUIKitView.boundedDocumentRasterScale(
            logicalSize: size, screenScale: 2, zoomScale: 4)
        XCTAssertTrue(scale.isFinite)
        XCTAssertGreaterThan(scale, 0)
        XCTAssertEqual((size.width * scale) * (size.height * scale), pixelBudget, accuracy: 0.001)
    }

    func testRepeatedSettledScaleRequestDoesNotDirtyTheCanvasAgain() {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        canvas.updateDocumentDisplayScale(for: 1.5)
        canvas.layer.displayIfNeeded()
        XCTAssertFalse(canvas.layer.needsDisplay())
        let scale = canvas.contentScaleFactor

        for _ in 0..<30 {
            canvas.updateDocumentDisplayScale(for: 1.5)
        }

        XCTAssertEqual(canvas.contentScaleFactor, scale)
        XCTAssertFalse(canvas.layer.needsDisplay(),
            "Unchanged model echoes must not schedule another full-canvas raster pass.")
    }

    func testChangedZoomStillRefreshesControlsWhenRasterScaleIsAlreadyCapped() {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        canvas.updateDocumentDisplayScale(for: 10)
        XCTAssertEqual(canvas.contentScaleFactor, 8, accuracy: 0.001)
        canvas.layer.displayIfNeeded()
        XCTAssertFalse(canvas.layer.needsDisplay())

        canvas.updateDocumentDisplayScale(for: 11)

        XCTAssertEqual(canvas.contentScaleFactor, 8, accuracy: 0.001)
        XCTAssertTrue(canvas.layer.needsDisplay(),
            "A changed zoom must refresh screen-sized control presentation even at the raster cap.")
        canvas.layer.displayIfNeeded()
        canvas.updateDocumentDisplayScale(for: 11)
        XCTAssertFalse(canvas.layer.needsDisplay(), "The same final zoom must then become a no-op.")
    }

    func testUnchangedZoomRepairsAnOverlayWhoseRasterScaleWasReset() throws {
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        let overlay = try XCTUnwrap(canvas.subviews.compactMap { $0 as? RenderedEditHitOverlayView }.first)
        canvas.updateDocumentDisplayScale(for: 2)
        let expectedScale = canvas.contentScaleFactor
        overlay.contentScaleFactor = 1
        canvas.layer.displayIfNeeded()
        XCTAssertFalse(canvas.layer.needsDisplay())

        canvas.updateDocumentDisplayScale(for: 2)

        XCTAssertEqual(overlay.contentScaleFactor, expectedScale, accuracy: 0.001)
        XCTAssertTrue(canvas.layer.needsDisplay(),
            "Scale idempotence must not hide a real UIKit overlay scale reset.")
    }
}
#endif
