#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Source preservation is a functional render contract independent of optional diagnostics.
@MainActor
final class ChordInkEndingSourcePreservationTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testEndingOnlyCommitPreservesItsExactSourceAcrossReopen() throws {
        let f = try fixture()
        XCTAssertEqual(f.committed.result.renderedEndingCount, 1)
        XCTAssertEqual(f.committed.result.renderedChordCount, 0)
        XCTAssertNil(f.committed.chart.pageHandwrittenChordData)
        let ending = try XCTUnwrap(f.committed.chart.roadmapObjects.first { $0.type.isEnding })
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: f.source,
            current: try PKDrawing(data: XCTUnwrap(ending.sourceInkData))))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(f.committed.chart))
        XCTAssertEqual(reopened, f.committed.chart)
        XCTAssertEqual(reopened.roadmapObject(id: ending.id)?.sourceInkData, ending.sourceInkData)
    }

    func testMixedChordAndEndingKeepTheirSeparateExactSourceArchivesAcrossReopen() throws {
        let f = try fixture(includesChord: true)
        XCTAssertEqual(f.committed.result.renderedEndingCount, 1)
        XCTAssertEqual(f.committed.result.renderedChordCount, 1)
        XCTAssertNil(f.committed.chart.pageHandwrittenChordData)
        let ending = try XCTUnwrap(f.committed.chart.roadmapObjects.first { $0.type.isEnding })
        let chord = try XCTUnwrap(f.committed.chart.measures.flatMap(\.chordEvents).first)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [f.source.strokes[0]]),
            current: try PKDrawing(data: XCTUnwrap(ending.sourceInkData))))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [f.source.strokes[1]]),
            current: try PKDrawing(data: XCTUnwrap(chord.sourceInkData))))
        XCTAssertEqual(f.committed.chart.measures.map(\.id), f.original.measures.map(\.id))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(f.committed.chart))
        XCTAssertEqual(reopened, f.committed.chart)
        XCTAssertEqual(reopened.roadmapObject(id: ending.id)?.sourceInkData, ending.sourceInkData)
        XCTAssertEqual(reopened.chordEvent(id: chord.id)?.sourceInkData, chord.sourceInkData)
    }

    func testUnreviewedEndingRefusalPreservesTheChartAndItsSavedSource() throws {
        let f = try fixture(includesChord: true)
        var state = f.state
        state.draftEndings[0].isReviewed = false
        let refused = ChordInkDraftRenderCoordinator.prepare(chart: f.original, state: state,
            currentDrawing: f.source, coordinateSpace: .init(size: pageSize))
        XCTAssertFalse(refused.canConsumeSource)
        XCTAssertEqual(refused.result.renderedEndingCount, 0)
        XCTAssertEqual(refused.result.renderedChordCount, 0)
        XCTAssertEqual(refused.chart, f.original)
        XCTAssertEqual(refused.chart.pageHandwrittenChordData, f.original.pageHandwrittenChordData)
    }

    func testAnotherEndingCommitPreservesThePreviouslySavedSourceArchive() throws {
        let f = try fixture(includesExistingEnding: true)
        let existing = try XCTUnwrap(f.original.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(f.committed.chart.roadmapObject(id: existing.id), existing)
        let newEndings = f.committed.chart.roadmapObjects.filter {
            $0.type.isEnding && $0.id != existing.id
        }
        let added = try XCTUnwrap(newEndings.first)
        XCTAssertEqual(newEndings.count, 1)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: f.source,
            current: try PKDrawing(data: XCTUnwrap(added.sourceInkData))))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(f.committed.chart))
        XCTAssertEqual(reopened, f.committed.chart)
        XCTAssertEqual(reopened.roadmapObject(id: existing.id), existing)
    }

    private struct Fixture {
        var original: Chart
        var source: PKDrawing
        var state: ChordPreviewState
        var committed: ChordInkDraftRenderCoordinator.Outcome
    }

    private func fixture(includesChord: Bool = false, includesExistingEnding: Bool = false) throws -> Fixture {
        var chart = Chart.blank(title: "Synthetic ending source preservation", measureCount: 2, layoutStyle: .simpleChordSheet)
        if includesExistingEnding {
            let id = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: chart.measures[1].id,
                endMeasureID: chart.measures[1].id, displayText: "2.", endStyle: .open))
            let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == id })
            chart.roadmapObjects[index].sourceInkData = PKDrawing(strokes: [stroke([
                CGPoint(x: 15, y: 10), CGPoint(x: 25, y: 10)
            ], seed: 700)]).dataRepresentation()
        }
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
            paperFrame: layout.paperFrame(for: system)))
        let measure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(system.measures[0], in: system,
            paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle)
        let left = measure.frame.minX + 1 - frame.minX
        let right = measure.frame.maxX - 1 - frame.minX
        let top = lane.minY + lane.height * 0.1 - frame.minY
        let hook = lane.height * 0.22
        var strokes = [stroke([CGPoint(x: left, y: top + hook), CGPoint(x: left, y: top),
            CGPoint(x: right, y: top), CGPoint(x: right, y: top + hook)], seed: 701)]
        if includesChord {
            let x = (left + right) / 2
            let y = lane.minY + lane.height * 0.72 - frame.minY
            strokes.append(stroke([CGPoint(x: x, y: y), CGPoint(x: x + 8, y: y + 8)], seed: 702))
        }
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation(),
            coordinateSpace: .init(size: pageSize))
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(
            from: source, chordFrame: frame, pageLayout: layout)
        let found = ChordDraftEndingRecognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing),
            chordFrame: frame, pageLayout: layout)
        var state = ChordPreviewState(layoutPageSize: pageSize)
        state.replaceDraftEndings(with: context.remappedEndingRecognition(
            context.endingRecognitionWithUnambiguousSourceStrokes(found)).endings)
        XCTAssertEqual(state.draftEndings.count, 1)
        if includesChord {
            state.draftChords = [ChordInkDraft(input: .init(measureID: chart.measures[0].id, measureIndex: 1,
                targetFraction: 0.5, layoutPageSize: pageSize,
                drawingData: PKDrawing(strokes: [source.strokes[1]]).dataRepresentation(), candidateTexts: ["C"],
                bestCandidateText: "C", confidence: 4, strokeCount: 1))]
        }
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: request,
            chart: chart, currentState: state, label: "1.", endStyle: .closed))
        let committed = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
            currentDrawing: source, coordinateSpace: .init(size: pageSize))
        XCTAssertTrue(committed.canConsumeSource)
        return Fixture(original: chart, source: source, state: reviewed, committed: committed)
    }

    private func stroke(_ points: [CGPoint], seed: UInt32) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif
