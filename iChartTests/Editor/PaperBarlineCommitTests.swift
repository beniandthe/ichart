#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import XCTest
@testable import iChart

@MainActor
final class PaperBarlineCommitTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testTwoDoubleBoundariesCreateOneMeasureAndConsumeTheirFourSourceStrokes() throws {
        for style in styles {
            var chart = makeChart(style)
            let input = try installBoundaries([(0.20, .double), (0.65, .double)], in: &chart)

            let result = chart.commitChordInkDraftBatch(input.state)

            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, style.rawValue)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(result.renderedBarlineCount, 2)
            XCTAssertNil(chart.pageHandwrittenChordData)
            try assertOneMeasure(in: chart, start: 0.20, end: 0.65)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            XCTAssertEqual(reopened, chart)
        }
    }

    func testAutomaticModeRendersBothDoubleBoundariesWithoutReview() throws {
        for style in styles {
            var chart = makeChart(style)
            let input = try installBoundaries([(0.20, .double), (0.65, .double)], in: &chart)

            let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(
                chart: chart, state: input.state, currentDrawing: input.drawing,
                coordinateSpace: .init(size: input.chordFrame.size),
                now: inputDate.addingTimeInterval(3), lastInputAt: inputDate,
                isUsingTool: false, sourcePageLayout: input.layout, sourceChordFrame: input.chordFrame)

            let outcome = try XCTUnwrap(attempt.outcome, style.rawValue)
            XCTAssertTrue(outcome.drawing.strokes.isEmpty)
            XCTAssertEqual(outcome.result.renderedBarlineCount, 2)
            XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
            try assertOneMeasure(in: outcome.chart, start: 0.20, end: 0.65)
        }
    }

    func testSecondStrokeAfterFirstBoundaryCommittedUpgradesItToDouble() throws {
        for style in styles {
            var chart = makeChart(style)
            let first = try installBoundaries([(0.20, .single)], in: &chart)
            XCTAssertEqual(chart.commitChordInkDraftBatch(first.state).renderedBarlineCount, 1)
            let firstLane = try lane(in: first.layout)
            let secondFraction = 0.20 + 7 / Double(firstLane.width)
            let second = try installBoundaries([(secondFraction, .single)], in: &chart)
            XCTAssertEqual(try lane(in: second.layout), firstLane, "The row's writing coordinates stay stable")

            let result = chart.commitChordInkDraftBatch(second.state)

            XCTAssertEqual(result.renderedBarlineCount, 1)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
            let row = chart.measures.filter { $0.paperLayout?.rowIndex == 0 }
            XCTAssertTrue(row.allSatisfy { $0.authoringState == .open })
            XCTAssertEqual(row.first?.paperLayout?.leadingBarline, .double)
            XCTAssertEqual(row.first?.paperLayout?.startFraction ?? 0, 0.20, accuracy: 0.001)
        }
    }

    func testRightEndOnlyMeasureKeepsItsAuthoredPositionThroughWritingCompletion() throws {
        for style in styles {
            var chart = makeChart(style)
            let input = try installBoundaries([(0.82, .double), (0.98, .double)], in: &chart)
            let result = chart.commitChordInkDraftBatch(input.state)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)

            XCTAssertTrue(chart.finishPaperWritingRows())

            try assertOneMeasure(in: chart, start: 0.82, end: 0.98)
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                pageSize: pageSize, includesChordInkContinuationLanes: true)
            let system = try XCTUnwrap(layout.systems.first)
            let writing = try XCTUnwrap(system.paperWritingFrame)
            let measure = try XCTUnwrap(system.measures.first)
            XCTAssertEqual(measure.frame.minX, writing.minX + writing.width * 0.82, accuracy: 0.5)
            XCTAssertEqual(measure.frame.maxX, writing.minX + writing.width * 0.98, accuracy: 0.5)
        }
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Paper boundary commit", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        XCTAssertTrue(chart.usesPaperMeasureLayout)
        return chart
    }

    private struct Input {
        var state: ChordPreviewState
        var drawing: PKDrawing
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
    }

    private func lane(in layout: LeadSheetPageLayout) throws -> CGRect {
        let system = try XCTUnwrap(layout.systems.first)
        return try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
    }

    private func installBoundaries(_ boundaries: [(Double, DraftBarlineKind)], in chart: inout Chart) throws -> Input {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: pageSize, includesChordInkContinuationLanes: true)
        let lane = try lane(in: layout)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let strokes = boundaries.flatMap { fraction, kind -> [PKStroke] in
            let x = lane.minX + lane.width * CGFloat(fraction) - frame.minX
            return (kind == .double ? [-3.5, 3.5] : [0]).map { offset in
                PKStroke(ink: .init(.pen, color: .black), path: PKStrokePath(
                    controlPoints: [lane.minY + 2, lane.maxY - 2].enumerated().map { index, y in
                        PKStrokePoint(location: CGPoint(x: x + offset, y: y - frame.minY),
                            timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2),
                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }, creationDate: inputDate))
            }
        }
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(
            from: source, chordFrame: frame, pageLayout: layout)
        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing), chordFrame: frame, pageLayout: layout)
        let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(recognition)
        let barlines = context.remappedBarlineRecognition(safe).barlines
        XCTAssertEqual(barlines.count, boundaries.count)
        let state = ChordPreviewState(draftBarlines: barlines, layoutPageSize: pageSize)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return Input(state: state, drawing: source, layout: layout, chordFrame: frame)
    }

    private func assertOneMeasure(in chart: Chart, start: Double, end: Double,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let closed = chart.measures.filter { $0.paperLayout?.rowIndex == 0 && $0.authoringState == .committed }
        XCTAssertEqual(closed.count, 1, file: file, line: line)
        let measure = try XCTUnwrap(closed.first, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.startFraction ?? 0, start, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.endFraction ?? 0, end, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.leadingBarline, .double, file: file, line: line)
        XCTAssertEqual(measure.barlineAfter, .double, file: file, line: line)
    }
}
#endif
