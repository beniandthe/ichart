#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// A newly recognized boundary partitions an existing musical measure. Ranges
/// ending after that measure must still cover its right-hand material, while
/// the existing ending label, original ink and point-marker identity survive.
@MainActor
final class ChordInkAutomaticStructuralSpanTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 500)

    func testDirectSimpleSplitExtendsSingleMeasureRangesThroughRepeatedRightSplits() throws {
        var chart = makeChart(measureCount: 1)
        let originalID = chart.measures[0].id
        let objects = try addRanges(to: &chart, startID: originalID, endID: originalID)
        let pointID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno,
            anchorMeasureID: originalID, displayText: "Keep this marker"))
        let point = try XCTUnwrap(chart.roadmapObject(id: pointID))

        // Automatic handwritten boundaries use this same public split method.
        // Its attachment repair must therefore work independently of a later
        // renderer pass or a special preview-only remapping step.
        let firstRight = try XCTUnwrap(chart.splitSimpleChordMeasure(originalID, atFraction: 0.45))
        try assertRanges(objects, in: chart, startID: originalID, endID: firstRight)
        XCTAssertEqual(chart.roadmapObject(id: pointID), point)
        XCTAssertTrue(try XCTUnwrap(chart.measure(id: originalID)).roadmapObjectIDs.contains(pointID))
        XCTAssertFalse(try XCTUnwrap(chart.measure(id: firstRight)).roadmapObjectIDs.contains(pointID))

        let finalRight = try XCTUnwrap(chart.splitSimpleChordMeasure(firstRight, atFraction: 0.55))
        try assertRanges(objects, in: chart, startID: originalID, endID: finalRight)
        for object in objects {
            XCTAssertFalse(try XCTUnwrap(chart.measure(id: firstRight)).roadmapObjectIDs.contains(object.id),
                "The former end is an interior segment after a second split")
        }
        XCTAssertEqual(chart.roadmapObject(id: pointID), point)
        XCTAssertNil(chart.roadmapObject(id: pointID)?.endMeasureID)
        try assertRoundTrip(chart)
    }

    func testAutomaticBarlineExtendsMultiMeasureRangesAndPreservesNeighborAndPointMarker() throws {
        var chart = makeChart(measureCount: 3)
        let ids = chart.measures.map(\.id)
        let objects = try addRanges(to: &chart, startID: ids[0], endID: ids[1])
        let neighborID = try XCTUnwrap(chart.addEndingSpan(.ending2,
            startMeasureID: ids[2], endMeasureID: ids[2], displayText: "On cue", endStyle: .closed))
        installArchivedInk(on: neighborID, in: &chart, seed: 70)
        let neighbor = try XCTUnwrap(chart.roadmapObject(id: neighborID))
        let pointID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno,
            anchorMeasureID: ids[1], displayText: "Point stays left"))
        let point = try XCTUnwrap(chart.roadmapObject(id: pointID))
        let beforeMeasureIDs = chart.measures.map(\.id)

        let outcome = try automaticSplit(of: ids[1], in: chart, seed: 80)
        let splitIndex = try XCTUnwrap(outcome.chart.measures.firstIndex { $0.id == ids[1] })
        let rightID = outcome.chart.measures[splitIndex + 1].id
        var expectedOrder = beforeMeasureIDs
        expectedOrder.insert(rightID, at: 2)
        XCTAssertEqual(outcome.chart.measures.map(\.id), expectedOrder)
        try assertRanges(objects, in: outcome.chart, startID: ids[0], endID: rightID)
        for object in objects {
            XCTAssertFalse(try XCTUnwrap(outcome.chart.measure(id: ids[1])).roadmapObjectIDs.contains(object.id),
                "A former range end must not keep a stale endpoint attachment")
        }
        assertObjectContent(neighbor, actual: try XCTUnwrap(outcome.chart.roadmapObject(id: neighborID)))
        XCTAssertEqual(outcome.chart.roadmapObject(id: neighborID)?.startMeasureID, ids[2])
        XCTAssertEqual(outcome.chart.roadmapObject(id: neighborID)?.endMeasureID, ids[2])
        XCTAssertEqual(outcome.chart.roadmapObject(id: pointID), point)
        XCTAssertTrue(try XCTUnwrap(outcome.chart.measure(id: ids[1])).roadmapObjectIDs.contains(pointID))
        XCTAssertFalse(try XCTUnwrap(outcome.chart.measure(id: rightID)).roadmapObjectIDs.contains(pointID))
        XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
        try assertRoundTrip(outcome.chart)
    }

    func testRepeatedAutomaticBarlinesKeepCustomEndingAndRepeatCoveringTheOriginalOuterEnd() throws {
        var chart = makeChart(measureCount: 1)
        let originalID = chart.measures[0].id
        let objects = try addRanges(to: &chart, startID: originalID, endID: originalID)
        let pointID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: originalID))
        let point = try XCTUnwrap(chart.roadmapObject(id: pointID))

        let first = try automaticSplit(of: originalID, in: chart, seed: 90)
        let firstRight = first.chart.measures[1].id
        try assertRanges(objects, in: first.chart, startID: originalID, endID: firstRight)
        let second = try automaticSplit(of: firstRight, in: first.chart, seed: 91)
        let finalRight = second.chart.measures[2].id
        XCTAssertEqual(second.chart.measures[0].id, originalID)
        XCTAssertEqual(second.chart.measures[1].id, firstRight)
        try assertRanges(objects, in: second.chart, startID: originalID, endID: finalRight)
        XCTAssertEqual(second.chart.roadmapObjects.count, objects.count + 1,
            "Partitioning existing ranges must not duplicate or replace their objects")
        XCTAssertEqual(second.chart.roadmapObject(id: pointID), point)
        for object in objects {
            XCTAssertFalse(try XCTUnwrap(second.chart.measure(id: firstRight)).roadmapObjectIDs.contains(object.id))
        }
        XCTAssertTrue(second.drawing.strokes.isEmpty)
        XCTAssertNil(second.chart.pageHandwrittenChordData)
        try assertRoundTrip(second.chart)
    }

    func testDirectRhythmSplitExtendsSingleMeasureRangesWithoutChangingTheirReceipts() throws {
        var chart = makeChart(measureCount: 1, style: .rhythmSectionSheet)
        let originalID = chart.measures[0].id
        let objects = try addRanges(to: &chart, startID: originalID, endID: originalID)
        let firstRight = try XCTUnwrap(chart.splitOpenRhythmSectionMeasure(originalID, atFraction: 0.4))
        try assertRanges(objects, in: chart, startID: originalID, endID: firstRight)
        let finalRight = try XCTUnwrap(chart.splitOpenRhythmSectionMeasure(firstRight, atFraction: 0.6))
        try assertRanges(objects, in: chart, startID: originalID, endID: finalRight)
        for object in objects {
            XCTAssertFalse(try XCTUnwrap(chart.measure(id: firstRight)).roadmapObjectIDs.contains(object.id))
        }
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        try assertRoundTrip(chart)
    }

    func testRepeatedAutomaticRhythmBarlinesPreserveValidRangeEndpointsAndSource() throws {
        var chart = makeChart(measureCount: 1, style: .rhythmSectionSheet)
        let originalID = chart.measures[0].id
        let objects = try addRanges(to: &chart, startID: originalID, endID: originalID)
        let first = try automaticSplit(of: originalID, in: chart, seed: 100)
        let firstRight = first.chart.measures[1].id
        try assertRanges(objects, in: first.chart, startID: originalID, endID: firstRight)
        let second = try automaticSplit(of: firstRight, in: first.chart, seed: 101)
        let finalRight = second.chart.measures[2].id
        try assertRanges(objects, in: second.chart, startID: originalID, endID: finalRight)
        XCTAssertEqual(second.chart.roadmapObjects.count, objects.count)
        XCTAssertTrue(second.drawing.strokes.isEmpty)
        XCTAssertNil(second.chart.pageHandwrittenChordData)
        try assertRoundTrip(second.chart)
    }

    func testRhythmPointMarkerStillRefusesDirectAndAutomaticSplitWithoutChangingChartOrSource() throws {
        var chart = makeChart(measureCount: 1, style: .rhythmSectionSheet)
        let originalID = chart.measures[0].id
        _ = try addRanges(to: &chart, startID: originalID, endID: originalID)
        let pointID = try XCTUnwrap(chart.addPointRoadmapMarker(.segno, anchorMeasureID: originalID))
        let before = chart
        XCTAssertNil(chart.splitOpenRhythmSectionMeasure(originalID, atFraction: 0.5),
            "The range-only exception must not admit an attached point marker")
        XCTAssertEqual(chart, before)
        let fixture = try automaticSplitAttempt(of: originalID, in: chart, seed: 110,
            requiresRecognizedBoundary: false)
        XCTAssertNil(fixture.attempt.outcome,
            "An unplaceable structural transaction must not become an ink-consuming outcome")
        XCTAssertEqual(chart, before)
        XCTAssertEqual(chart.roadmapObject(id: pointID), before.roadmapObject(id: pointID))
        XCTAssertEqual(fixture.source.strokes.count, 1)
        XCTAssertTrue(fixture.state.draftChords.isEmpty)
        // Existing point-marker geometry may exclude this source before the
        // model split guard is reached. Either admission layer must preserve
        // the ink; the positive cases above still require a real detected bar.
        XCTAssertLessThanOrEqual(fixture.state.draftBarlines.count, 1)
    }

    private func makeChart(measureCount: Int, style: ChartLayoutStyle = .simpleChordSheet) -> Chart {
        var chart = Chart.draft(title: "Structural range preservation", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: measureCount)
        return chart
    }

    private func addRanges(to chart: inout Chart, startID: UUID, endID: UUID) throws -> [RoadmapObject] {
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1,
            startMeasureID: startID, endMeasureID: endID,
            displayText: "1–3, On cue", endStyle: .open))
        let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: startID, endMeasureID: endID))
        installArchivedInk(on: endingID, in: &chart, seed: 31)
        installArchivedInk(on: repeatID, in: &chart, seed: 32)
        return try [endingID, repeatID].map { try XCTUnwrap(chart.roadmapObject(id: $0)) }
    }

    private func installArchivedInk(on id: UUID, in chart: inout Chart, seed: Int) {
        guard let index = chart.roadmapObjects.firstIndex(where: { $0.id == id }) else { return }
        let source = PKDrawing(strokes: [stroke([CGPoint(x: 10, y: 10), CGPoint(x: 25, y: 20)], seed: seed)])
        chart.roadmapObjects[index].sourceInkData = source.dataRepresentation()
        chart.roadmapObjects[index].horizontalOffsetWithinMeasure = 0.125
        chart.roadmapObjects[index].scale = 1.125
    }

    private func automaticSplit(of measureID: UUID, in chart: Chart, seed: Int) throws
        -> ChordInkDraftRenderCoordinator.AutomaticOutcome {
        let fixture = try automaticSplitAttempt(of: measureID, in: chart, seed: seed)
        return try XCTUnwrap(fixture.attempt.outcome,
            "A complete current barline must split without shortening existing repeat/ending ranges: \(fixture.attempt.feedback)")
    }

    private func automaticSplitAttempt(of measureID: UUID, in chart: Chart, seed: Int,
        requiresRecognizedBoundary: Bool = true) throws
        -> (attempt: ChordInkDraftRenderCoordinator.AutomaticAttempt, source: PKDrawing, state: ChordPreviewState) {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == measureID } })
        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureID })
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let x = measure.frame.midX - region.frame.minX
        let y1 = lane.minY + lane.height * 0.08 - region.frame.minY
        let y2 = lane.maxY - lane.height * 0.08 - region.frame.minY
        let source = LeadSheetPersistentInkColorPolicy.normalizedDrawing(
            PKDrawing(strokes: [stroke([CGPoint(x: x, y: y1), CGPoint(x: x, y: y2)], seed: seed)]))
        let preparation = ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: inputAt, requestedDelay: 0,
            drawingData: source.dataRepresentation(), chordFrame: region.frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        if requiresRecognizedBoundary {
            XCTAssertEqual(preparation.barlines.count, 1,
                "Use an actual recognized, exact-source structural boundary rather than an invented draft")
            XCTAssertEqual(preparation.barlines.first?.measureID, measureID)
        }
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: preparation.barlines)
        state.layoutPageSize = pageSize
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(
            chart: chart, state: state, currentDrawing: source,
            coordinateSpace: PersistentInkCoordinateSpace(size: region.frame.size),
            now: inputAt.addingTimeInterval(10), lastInputAt: inputAt,
            isUsingTool: false, sourcePageLayout: layout, sourceChordFrame: region.frame)
        return (attempt, source, state)
    }

    private func assertRanges(_ originals: [RoadmapObject], in chart: Chart,
        startID: UUID, endID: UUID, file: StaticString = #filePath, line: UInt = #line) throws {
        for original in originals {
            let actual = try XCTUnwrap(chart.roadmapObject(id: original.id), file: file, line: line)
            assertObjectContent(original, actual: actual, file: file, line: line)
            XCTAssertEqual(actual.startMeasureID, startID, file: file, line: line)
            XCTAssertEqual(actual.endMeasureID, endID,
                "The range's original outer end belongs after the new right segment", file: file, line: line)
            XCTAssertTrue(try XCTUnwrap(chart.measure(id: startID), file: file, line: line)
                .roadmapObjectIDs.contains(original.id), file: file, line: line)
            XCTAssertTrue(try XCTUnwrap(chart.measure(id: endID), file: file, line: line)
                .roadmapObjectIDs.contains(original.id), file: file, line: line)
        }
    }

    private func assertObjectContent(_ original: RoadmapObject, actual: RoadmapObject,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.type, original.type, file: file, line: line)
        XCTAssertEqual(actual.displayText, original.displayText, file: file, line: line)
        XCTAssertEqual(actual.rawInput, original.rawInput, file: file, line: line)
        XCTAssertEqual(actual.endingEndStyle, original.endingEndStyle, file: file, line: line)
        XCTAssertEqual(actual.sourceInkData, original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.horizontalOffsetWithinMeasure, original.horizontalOffsetWithinMeasure, file: file, line: line)
        XCTAssertEqual(actual.scale, original.scale, file: file, line: line)
        XCTAssertEqual(actual.count, original.count, file: file, line: line)
        XCTAssertEqual(actual.linkedTargetID, original.linkedTargetID, file: file, line: line)
    }

    private func assertRoundTrip(_ chart: Chart, file: StaticString = #filePath, line: UInt = #line) throws {
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        XCTAssertEqual(reopened.roadmapObjects, chart.roadmapObjects, file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.roadmapObjectIDs), chart.measures.map(\.roadmapObjectIDs),
            file: file, line: line)
    }

    private func stroke(_ points: [CGPoint], seed: Int) -> PKStroke {
        let path = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path,
                creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }
}
#endif
