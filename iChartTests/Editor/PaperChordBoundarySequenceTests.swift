#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class PaperChordBoundarySequenceTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testChordWrittenBeforeBoundariesKeepsItsPositionAndFollowsTheCompletedMeasure() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for automatic in [false, true] {
                var chart = makeChart(style)
                let chordInput = try installInput(in: &chart, includesChord: true, includesBoundaries: false)
                let firstResult = try render(chordInput, in: &chart, automatic: automatic)
                XCTAssertEqual(firstResult.renderedChordCount, 1, "\(style) automatic=\(automatic)")
                XCTAssertTrue(firstResult.unresolvedDraftIDs.isEmpty)
                XCTAssertNil(chart.pageHandwrittenChordData)
                let open = try XCTUnwrap(chart.measures.first { !$0.chordEvents.isEmpty })
                let originalChord = try XCTUnwrap(open.chordEvents.first)
                let source = try XCTUnwrap(originalChord.sourceInkData)
                XCTAssertEqual(open.authoringState, .open)
                XCTAssertGreaterThan(originalChord.manualVisualLaneFraction ?? 0, 0.70,
                    "The chord remains near the handwriting until a measure is completed")

                let boundaryInput = try installInput(in: &chart, includesChord: false, includesBoundaries: true)
                let secondResult = try render(boundaryInput, in: &chart, automatic: automatic)

                XCTAssertEqual(secondResult.renderedBarlineCount, 2)
                XCTAssertTrue(secondResult.unresolvedDraftIDs.isEmpty)
                XCTAssertNil(chart.pageHandwrittenChordData)
                let completed = try assertOneRightEndMeasure(in: chart)
                let chord = try XCTUnwrap(completed.chordEvents.first)
                XCTAssertEqual(chord.id, originalChord.id)
                XCTAssertEqual(chord.sourceInkData, source)
                XCTAssertEqual(chord.startPosition, BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1))
                XCTAssertTrue(chord.anchorsToMeasureStart)
                let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
                XCTAssertEqual(reopened, chart)
                XCTAssertEqual(reopened.measure(id: completed.id)?.chordEvents.first?.sourceInkData, source)
            }
        }
    }

    func testChordAndLaterDrawnBoundariesInOneBatchCreateOneRightEndMeasure() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for automatic in [false, true] {
                var chart = makeChart(style)
                let input = try installInput(in: &chart, includesChord: true, includesBoundaries: true)

                let result = try render(input, in: &chart, automatic: automatic)

                XCTAssertEqual(result.renderedChordCount, 1, "\(style) automatic=\(automatic)")
                XCTAssertEqual(result.renderedBarlineCount, 2)
                XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
                XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
                XCTAssertNil(chart.pageHandwrittenChordData)
                let completed = try assertOneRightEndMeasure(in: chart)
                let chord = try XCTUnwrap(completed.chordEvents.first)
                XCTAssertEqual(chord.symbol, try ChordSymbolParser.parse("C"))
                let source = try PKDrawing(data: XCTUnwrap(chord.sourceInkData))
                let expected = try PKDrawing(data: XCTUnwrap(input.chordData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: source))
                XCTAssertEqual(chord.startPosition.beat, 1)
                XCTAssertTrue(chord.anchorsToMeasureStart)
            }
        }
    }

    func testChordBeforeFirstSingleBarlineCreatesTheFirstMeasureWithoutAnOpeningAnchor() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for automatic in [false, true] {
                var chart = makeChart(style)
                let input = try installInput(in: &chart, includesChord: true, includesBoundaries: true,
                    chordFraction: 0.15, boundaryFractions: [0.30], boundaryKind: .single)

                let result = try render(input, in: &chart, automatic: automatic)

                XCTAssertEqual(result.renderedChordCount, 1, "\(style) automatic=\(automatic)")
                XCTAssertEqual(result.renderedBarlineCount, 1)
                XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
                XCTAssertNil(chart.pageHandwrittenChordData)
                let closed = chart.measures.filter { $0.paperLayout?.rowIndex == 0 && $0.authoringState == .committed }
                XCTAssertEqual(closed.count, 1)
                let firstMeasure = try XCTUnwrap(closed.first)
                XCTAssertEqual(firstMeasure.paperLayout?.startFraction ?? -1, 0, accuracy: 0.002)
                XCTAssertEqual(firstMeasure.paperLayout?.endFraction ?? 0, 0.30, accuracy: 0.002)
                XCTAssertNil(firstMeasure.paperLayout?.leadingBarline)
                XCTAssertEqual(firstMeasure.barlineAfter, .single)
                let chord = try XCTUnwrap(firstMeasure.chordEvents.first)
                XCTAssertEqual(chord.symbol, try ChordSymbolParser.parse("C"))
                XCTAssertEqual(chord.startPosition.beat, 1)
                XCTAssertTrue(chord.anchorsToMeasureStart)
                let source = try PKDrawing(data: XCTUnwrap(chord.sourceInkData))
                let expected = try PKDrawing(data: XCTUnwrap(input.chordData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: source))
            }
        }
    }

    private struct Input {
        var state: ChordPreviewState
        var drawing: PKDrawing
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var chordData: Data?
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Paper chord boundary sequence", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        XCTAssertTrue(chart.usesPaperMeasureLayout)
        return chart
    }

    private func installInput(in chart: inout Chart, includesChord: Bool, includesBoundaries: Bool,
        chordFraction: Double = 0.85, boundaryFractions: [Double] = [0.80, 0.98],
        boundaryKind: DraftBarlineKind = .double) throws -> Input {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: pageSize, includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        var strokes: [PKStroke] = []
        if includesChord {
            let center = CGPoint(x: lane.minX + lane.width * CGFloat(chordFraction) - frame.minX,
                y: lane.midY - frame.minY)
            strokes.append(stroke([
                CGPoint(x: center.x + 10, y: center.y - 10),
                CGPoint(x: center.x, y: center.y - 10),
                CGPoint(x: center.x - 6, y: center.y),
                CGPoint(x: center.x, y: center.y + 10),
                CGPoint(x: center.x + 10, y: center.y + 10)
            ]))
        }
        if includesBoundaries {
            for fraction in boundaryFractions {
                let x = lane.minX + lane.width * CGFloat(fraction) - frame.minX
                for offset in boundaryKind == .double ? [-3.5, 3.5] : [0] {
                    strokes.append(stroke([
                        CGPoint(x: x + CGFloat(offset), y: lane.minY + 2 - frame.minY),
                        CGPoint(x: x + CGFloat(offset), y: lane.maxY - 2 - frame.minY)
                    ]))
                }
            }
        }
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        var state = ChordPreviewState(layoutPageSize: pageSize)
        var chordData: Data?
        if includesChord {
            let drawing = PKDrawing(strokes: [try XCTUnwrap(source.strokes.first)])
            let data = drawing.dataRepresentation()
            chordData = data
            let measure = try XCTUnwrap(chart.measures.first)
            let laneLocation = ChordInkDraftLaneLocation(systemIndex: 0, fraction: chordFraction)
            let anchor = ChordInkDraftAnchor(measureID: measure.id,
                laneLocation: laneLocation, visualOrder: chordFraction, fraction: chordFraction)
            let lifecycle = ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: anchor,
                ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)), stage: .stable)
            let input = ChordInkDraftInput(measureID: measure.id, measureIndex: measure.index,
                targetFraction: chordFraction, visualOrder: chordFraction, laneLocation: laneLocation,
                layoutPageSize: pageSize, drawingData: data, candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4.2, strokeCount: drawing.strokes.count,
                targetLifecycle: lifecycle)
            state.draftChords = [ChordInkDraft(input: input, selectedText: "C")]
        }
        if includesBoundaries {
            let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(
                from: source, chordFrame: frame, pageLayout: layout)
            let recognition = ChordDraftBarlineRecognizer.recognize(
                strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing),
                chordFrame: frame, pageLayout: layout)
            let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(recognition)
            state.draftBarlines = context.remappedBarlineRecognition(safe).barlines
            XCTAssertEqual(state.draftBarlines.count, boundaryFractions.count)
        }
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return Input(state: state, drawing: source, layout: layout, chordFrame: frame, chordData: chordData)
    }

    private func render(_ input: Input, in chart: inout Chart, automatic: Bool) throws -> ChordInkDraftBatchRenderResult {
        guard automatic else { return chart.commitChordInkDraftBatch(input.state) }
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(
            chart: chart, state: input.state, currentDrawing: input.drawing,
            coordinateSpace: .init(size: input.chordFrame.size),
            now: inputDate.addingTimeInterval(3), lastInputAt: inputDate,
            isUsingTool: false, sourcePageLayout: input.layout, sourceChordFrame: input.chordFrame)
        let outcome = try XCTUnwrap(attempt.outcome, "\(chart.layoutStyle)")
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertTrue(outcome.remainingState.isEmpty)
        chart = outcome.chart
        return outcome.result
    }

    private func assertOneRightEndMeasure(in chart: Chart,
        file: StaticString = #filePath, line: UInt = #line) throws -> Measure {
        let completed = chart.measures.filter { $0.paperLayout?.rowIndex == 0 && $0.authoringState == .committed }
        XCTAssertEqual(completed.count, 1, file: file, line: line)
        let measure = try XCTUnwrap(completed.first, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.startFraction ?? 0, 0.80, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.endFraction ?? 0, 0.98, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(measure.paperLayout?.leadingBarline, .double, file: file, line: line)
        XCTAssertEqual(measure.barlineAfter, .double, file: file, line: line)
        XCTAssertEqual(measure.chordEvents.count, 1, file: file, line: line)
        XCTAssertEqual(chart.measures.flatMap(\.chordEvents).count, 1, file: file, line: line)
        return measure
    }

    private func stroke(_ points: [CGPoint]) -> PKStroke {
        PKStroke(ink: .init(.pen, color: .black),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: inputDate))
    }
}
#endif
