import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class FreeInkDocumentLayoutPolicyTests: XCTestCase {
#if canImport(UIKit)
    func testSavedInkReconstructsTheSamePaperAndMeasureGeometryAcrossV1Styles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            for sourceCanvasWidth in [CGFloat(800), CGFloat(1_200)] {
                var chart = Chart.blank(title: "Fixed paper", measureCount: 12, layoutStyle: style)
                let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: sourceCanvasWidth, height: 1_400))
                let sourceFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
                chart.pageHandwrittenNotationData = Data([1, 2, 3])
                chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(size: sourceFrame.size)
                let originalChart = chart

                let width = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
                let restored = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: width, height: 1_200))
                let restoredFrame = LeadSheetActiveInkScope.pageWritingFrame(for: restored)

                XCTAssertEqual(restoredFrame.width, sourceFrame.width, accuracy: 0.001,
                    "Saved paper width changed for \(style.rawValue).")
                XCTAssertEqual(restored.systems.flatMap(\.measures).compactMap(\.sourceMeasureID),
                    sourceLayout.systems.flatMap(\.measures).compactMap(\.sourceMeasureID))
                for (before, after) in zip(sourceLayout.systems.flatMap(\.measures), restored.systems.flatMap(\.measures)) {
                    let sourceLocal = before.frame.offsetBy(dx: -sourceFrame.minX, dy: -sourceFrame.minY)
                    let restoredLocal = after.frame.offsetBy(dx: -restoredFrame.minX, dy: -restoredFrame.minY)
                    XCTAssertEqual(restoredLocal, sourceLocal,
                        "Reconstructing saved paper moved a measure relative to its ink.")
                }
                XCTAssertEqual(chart, originalChart, "Resolving viewport geometry must not edit the chart.")
            }
        }
    }
#endif

    func testRetainedDocumentWidthDoesNotGrowOrShrinkWithTheViewport() {
        let chart = Chart.blank(title: "New Free Ink")
        for retainedWidth in [CGFloat(780), CGFloat(1_180)] {
            for viewportWidth in [CGFloat(780), CGFloat(1_180), CGFloat(780)] {
                XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                    retainedWidth: retainedWidth, chart: chart, viewportWidth: viewportWidth), retainedWidth)
            }
        }
    }

    func testSavedDocumentWidthOverridesViewportUntilItIsRetained() throws {
        var chart = Chart.blank(title: "Saved Free Ink")
        chart.pageHandwrittenNotationData = Data([1])
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 1_112, height: 1_020)
        let savedWidth = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
        for viewportWidth in [CGFloat(780), CGFloat(1_180)] {
            XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                retainedWidth: nil, chart: chart, viewportWidth: viewportWidth), savedWidth)
        }
    }

    func testChartsWithoutFreeInkUseCanonicalPaperRegardlessOfViewportWidth() {
        var chart = Chart.blank(title: "No Free Ink")
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 1_112, height: 1_020)
        for data in [nil, Data()] {
            chart.pageHandwrittenNotationData = data
            XCTAssertNil(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
            for width in [CGFloat(500), CGFloat(780), CGFloat(1_180), CGFloat(1_400)] {
                XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                    retainedWidth: nil, chart: chart, viewportWidth: width), 932)
                XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
                    for: chart, viewportWidth: width), 932)
            }
        }
    }

    func testInvalidSavedCoordinateSizesCannotLockTheDocumentToInvalidGeometry() {
        var chart = Chart.blank(title: "Invalid Free Ink space")
        chart.pageHandwrittenNotationData = Data([1])
        for (width, height) in [(Double.nan, 1_020), (Double.infinity, 1_020),
            (0, 1_020), (-10, 1_020), (1_112, Double.nan),
            (1_112, Double.infinity), (1_112, 0), (1_112, -10)] {
            chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: width, height: height)
            XCTAssertNil(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
            XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                retainedWidth: nil, chart: chart, viewportWidth: 780), 932)
        }
        chart.pageHandwrittenNotationCoordinateSpace = nil
        XCTAssertNil(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
    }

#if canImport(UIKit)
    func testLegacySavedWritingWidthsSurviveCurrentResponsiveMinimumAndLeadSheetCap() throws {
        for (style, writingWidth) in [(ChartLayoutStyle.simpleChordSheet, CGFloat(620)),
            (.leadSheet, CGFloat(1_112))] {
            var chart = Chart.blank(title: "Legacy paper", measureCount: 4, layoutStyle: style)
            chart.pageHandwrittenNotationData = Data([1, 2, 3])
            chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(
                width: Double(writingWidth), height: 1_020)
            let sourceChart = chart
            let width = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: width, height: 1_200))
            XCTAssertEqual(LeadSheetActiveInkScope.pageWritingFrame(for: layout).width,
                writingWidth, accuracy: 0.001,
                "A saved ink document must keep its complete original paper width.")
            XCTAssertLessThanOrEqual(layout.paperFrame.maxX, layout.pageBounds.maxX)
            XCTAssertEqual(chart, sourceChart)

            // The saved-paper override applies to its canonical document size,
            // rather than changing unrelated responsive layout requests.
            let otherWidthLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: width + 200, height: 1_200))
            XCTAssertNotEqual(LeadSheetActiveInkScope.pageWritingFrame(for: otherWidthLayout).width,
                writingWidth)
            chart.pageHandwrittenNotationData = nil
            let withoutInk = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: CGSize(width: width, height: 1_200))
            XCTAssertNotEqual(LeadSheetActiveInkScope.pageWritingFrame(for: withoutInk).width,
                writingWidth, "Coordinate metadata alone must not override ordinary paper sizing.")
        }
    }
#endif

    func testNewFreeInkLatchesCanonicalPaperRegardlessOfItsFirstViewport() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            let chart = Chart.blank(title: "Narrow viewport", layoutStyle: style)
            for firstViewportWidth in [CGFloat(500), CGFloat(780), CGFloat(1_180)] {
                let retainedWidth = LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
                    for: chart, viewportWidth: firstViewportWidth)
                let resolvedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: retainedWidth, height: 1_200))

                XCTAssertEqual(retainedWidth, 932,
                    "Starting Free Ink in a different orientation must not select a different paper size.")
                XCTAssertEqual(retainedWidth, resolvedLayout.pageBounds.width)
                XCTAssertLessThanOrEqual(resolvedLayout.paperFrame.maxX, retainedWidth)
                for rotatedViewportWidth in [CGFloat(500), CGFloat(1_180), CGFloat(500)] {
                    XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                        retainedWidth: retainedWidth, chart: chart,
                        viewportWidth: rotatedViewportWidth), 932)
                }
            }
        }
    }

    func testNewChartsKeepIdenticalMeasureGeometryAcrossPortraitAndLandscapeViewports() {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            let chart = Chart.blank(title: "Canonical notation geometry", measureCount: 16, layoutStyle: style)
            let originalChart = chart
            let layouts = [CGFloat(500), CGFloat(780), CGFloat(1_180)].map { viewportWidth in
                LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(
                    width: LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                        retainedWidth: nil, chart: chart, viewportWidth: viewportWidth),
                    height: 1_400))
            }
            let originalMeasures = layouts[0].systems.flatMap(\.measures)
            for layout in layouts.dropFirst() {
                XCTAssertEqual(layout.pageBounds.width, 932)
                XCTAssertEqual(layout.paperFrame, layouts[0].paperFrame)
                XCTAssertEqual(layout.systems.flatMap(\.measures).map(\.frame), originalMeasures.map(\.frame),
                    "Orientation must not move notation underneath absolute Free Ink.")
                XCTAssertEqual(layout.systems.flatMap(\.measures).compactMap(\.sourceMeasureID),
                    originalMeasures.compactMap(\.sourceMeasureID))
            }
            XCTAssertEqual(chart, originalChart)
        }
    }

    func testInvalidViewportOrRetainedWidthsCannotChangeCanonicalPaper() {
        let chart = Chart.blank(title: "Invalid viewport")
        for viewportWidth in [CGFloat.nan, CGFloat.infinity, 0, -1, 500, 1_180] {
            XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                retainedWidth: nil, chart: chart, viewportWidth: viewportWidth), 932)
            XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
                for: chart, viewportWidth: viewportWidth), 932)
            for retainedWidth in [CGFloat.nan, CGFloat.infinity, 0, -1] {
                XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.resolvedCanvasWidth(
                    retainedWidth: retainedWidth, chart: chart, viewportWidth: viewportWidth), 932)
            }
        }
    }

    func testEnteringFreeInkRetainsSavedPaperInsteadOfTheNewViewportMinimum() throws {
        var chart = Chart.blank(title: "Saved wide paper")
        chart.pageHandwrittenNotationData = Data([1])
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 1_112, height: 1_020)
        let savedWidth = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
            for: chart, viewportWidth: 500), savedWidth)
    }

}
