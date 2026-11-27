import CoreGraphics
import XCTest
@testable import iChart

final class PaperMeasureLayoutTests: XCTestCase {
    func testEmptyPaperRowsHaveStableTargetsAndNoImplicitLeadingBarsInEitherStyle() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Empty page", layoutStyle: style)
            chart.initializePaperWritingRows(count: 3)

            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart, pageSize: CGSize(width: 1000, height: 1400),
                includesChordInkContinuationLanes: true)

            XCTAssertEqual(layout.systems.map(\.id), chart.systems.map(\.id))
            XCTAssertEqual(layout.systems.count, 3)
            for system in layout.systems {
                let measure = try XCTUnwrap(system.measures.first)
                let writingFrame = try XCTUnwrap(system.paperWritingFrame)
                XCTAssertTrue(measure.isPaperWritingPlaceholder)
                XCTAssertNil(measure.leadingBarline)
                XCTAssertNil(measure.explicitPaperLeadingBarline(after: nil))
                XCTAssertFalse(measure.preservesOpenMeasureBoundary)
                XCTAssertEqual(measure.staffFrame.minX, writingFrame.minX, accuracy: 0.001)
                XCTAssertEqual(measure.staffFrame.maxX, writingFrame.maxX, accuracy: 0.001)
                XCTAssertEqual(system.staffLineYPositions.count, style == .rhythmSectionSheet ? 5 : 0)
            }
        }
    }

    func testRightEndOnlyMeasureRetainsItsRelativePositionAcrossReopenAndPageSizes() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Right end", layoutStyle: style)
            chart.initializePaperWritingRows(count: 1)
            chart.systems[0].measures[0].paperLayout = PaperMeasureLayout(
                rowIndex: 0, startFraction: 0.78, endFraction: 0.98, leadingBarline: .double)
            chart.systems[0].measures[0].authoringState = .committed
            chart.systems[0].measures[0].barlineAfter = .double
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            for width: CGFloat in [680, 1180] {
                let layout = LeadSheetPageLayoutEngine.pageLayout(
                    for: reopened, pageSize: CGSize(width: width, height: 1500))
                let system = try XCTUnwrap(layout.systems.first)
                let axis = try XCTUnwrap(system.paperWritingFrame)
                let measure = try XCTUnwrap(system.measures.first)
                XCTAssertEqual(measure.staffFrame.minX, axis.minX + axis.width * 0.78, accuracy: 0.001)
                XCTAssertEqual(measure.staffFrame.maxX, axis.minX + axis.width * 0.98, accuracy: 0.001)
                XCTAssertEqual(measure.explicitPaperLeadingBarline(after: nil), .double)
                XCTAssertEqual(measure.barlineAfter, .double)
                XCTAssertFalse(measure.isOpen)
            }
        }
    }

    func testSeparatedMeasuresKeepGapsAndEachExplicitOpeningBar() throws {
        var chart = Chart.blank(title: "Free positions", layoutStyle: .simpleChordSheet)
        chart.initializePaperWritingRows(count: 1)
        var first = chart.systems[0].measures[0]
        first.authoringState = .committed
        first.paperLayout = PaperMeasureLayout(
            rowIndex: 0, startFraction: 0.1, endFraction: 0.3, leadingBarline: .single)
        var second = first
        second.id = UUID()
        second.index = 2
        second.paperLayout = PaperMeasureLayout(
            rowIndex: 0, startFraction: 0.65, endFraction: 0.85, leadingBarline: .double)
        chart.systems[0].measures = [first, second]

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart, pageSize: CGSize(width: 1000, height: 1400))
        let system = try XCTUnwrap(layout.systems.first)
        let axis = try XCTUnwrap(system.paperWritingFrame)
        XCTAssertEqual(system.measures.map(\.sourceMeasureID), [first.id, second.id])
        XCTAssertEqual(system.measures[1].staffFrame.minX - system.measures[0].staffFrame.maxX,
            axis.width * 0.35, accuracy: 0.001)
        XCTAssertEqual(system.measures[1].explicitPaperLeadingBarline(after: system.measures[0]), .double)
    }

    func testSharedBoundaryDrawsOnceAndOpenTailKeepsTheFullWritingAxis() throws {
        var chart = Chart.blank(title: "Shared boundary", layoutStyle: .rhythmSectionSheet)
        chart.initializePaperWritingRows(count: 1)
        var first = chart.systems[0].measures[0]
        first.authoringState = .committed
        first.paperLayout = PaperMeasureLayout(
            rowIndex: 0, startFraction: 0.2, endFraction: 0.6, leadingBarline: .double)
        first.barlineAfter = .double
        var tail = first
        tail.id = UUID()
        tail.index = 2
        tail.authoringState = .open
        tail.paperLayout = PaperMeasureLayout(
            rowIndex: 0, startFraction: 0.6, endFraction: 1, leadingBarline: .double)
        chart.systems[0].measures = [first, tail]

        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart, pageSize: CGSize(width: 1000, height: 1400),
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let axis = try XCTUnwrap(system.paperWritingFrame)
        XCTAssertGreaterThan(system.measures[0].staffFrame.minX, axis.minX)
        XCTAssertNil(system.measures[1].explicitPaperLeadingBarline(after: system.measures[0]))
        XCTAssertTrue(system.measures[1].isPaperWritingPlaceholder)
        XCTAssertEqual(system.measures[1].staffFrame.maxX, axis.maxX, accuracy: 0.001)
    }
}
