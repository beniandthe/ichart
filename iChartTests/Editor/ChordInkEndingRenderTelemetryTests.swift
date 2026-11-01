#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Actual ending recognition/review/commit receipts enter the same preservation
/// checks as chords and repeat signs. All ink and labels here are synthetic.
@MainActor
final class ChordInkEndingRenderTelemetryTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testEndingOnlyCommitHasAnExactRoadmapReceiptAndPassesBothRenderChecks() throws {
        let f = try fixture()
        XCTAssertEqual(f.committed.result.renderedEndingCount, 1)
        XCTAssertEqual(f.committed.result.renderedChordCount, 0)
        XCTAssertNotNil(f.committed.chart.roadmapObjects.first(where: { $0.type.isEnding })?.sourceInkData)
        XCTAssertEqual(automatic(f).outcome, "passed")
        XCTAssertEqual(manual(f).outcome, "passed")
        let values = try XCTUnwrap(ChordInkAutomaticRenderTelemetry.transactionProperties(isEnabled: true,
            originalChart: f.original, state: f.state, sourceDrawing: f.source,
            outcome: f.automatic, observedChart: f.committed.chart, observedDrawing: PKDrawing(),
            mode: .reviewedAutomatic))
        XCTAssertEqual(values["source_stroke_count"], .int(f.source.strokes.count))
        XCTAssertEqual(values["consumed_stroke_count"], .int(f.source.strokes.count))
        XCTAssertEqual(values["retained_stroke_count"], .int(0))
        XCTAssertEqual(values["render_mode"], .string("reviewed_automatic"))
        XCTAssertNil(values["ending_label"])
        XCTAssertNil(values["drawing_data"])
    }

    func testMixedChordAndEndingCommitAccountsForBothSourceArchives() throws {
        let f = try fixture(includesChord: true)
        XCTAssertEqual(f.committed.result.renderedEndingCount, 1)
        XCTAssertEqual(f.committed.result.renderedChordCount, 1)
        let observed = automatic(f)
        XCTAssertEqual(observed.outcome, "passed")
        XCTAssertEqual(observed.expectedCount, f.source.strokes.count)
        XCTAssertEqual(observed.actualCount, f.source.strokes.count)
        XCTAssertEqual(manual(f).outcome, "passed")
    }

    func testMissingEndingArchiveIsDetectedWithAnEmptyCanvasAndSuccessfulResult() throws {
        let f = try fixture(includesChord: true)
        var broken = f.committed.chart
        let index = try XCTUnwrap(broken.roadmapObjects.firstIndex { $0.type.isEnding })
        broken.roadmapObjects[index].sourceInkData = nil
        XCTAssertEqual(automatic(f, observed: broken).reason, "render_source_missing")
        XCTAssertEqual(manual(f, observed: broken).reason, "render_source_missing")
    }

    func testChangedEndingArchiveCannotPassWithIdenticalStrokeAndPointCounts() throws {
        let f = try fixture()
        var broken = f.committed.chart
        let index = try XCTUnwrap(broken.roadmapObjects.firstIndex { $0.type.isEnding })
        let data = try XCTUnwrap(broken.roadmapObjects[index].sourceInkData)
        let receipt = try PKDrawing(data: data)
        let moved = receipt.transformed(using: CGAffineTransform(translationX: 1, y: 0))
        XCTAssertEqual(receipt.strokes.count, moved.strokes.count)
        XCTAssertEqual(receipt.strokes.reduce(0) { $0 + $1.path.count }, moved.strokes.reduce(0) { $0 + $1.path.count })
        broken.roadmapObjects[index].sourceInkData = moved.dataRepresentation()
        XCTAssertEqual(automatic(f, observed: broken).reason, "render_source_missing")
        XCTAssertEqual(manual(f, observed: broken).reason, "render_source_missing")
    }

    func testEndingReceiptHasExactMultiplicityRatherThanRepeatSignDuplicationPermission() throws {
        let f = try fixture()
        var broken = f.committed.chart
        let index = try XCTUnwrap(broken.roadmapObjects.firstIndex { $0.type.isEnding })
        let receipt = try PKDrawing(data: XCTUnwrap(broken.roadmapObjects[index].sourceInkData))
        broken.roadmapObjects[index].sourceInkData = PKDrawing(strokes: receipt.strokes + receipt.strokes).dataRepresentation()
        XCTAssertEqual(automatic(f, observed: broken).reason, "render_source_missing")
        XCTAssertEqual(manual(f, observed: broken).reason, "render_source_missing")
    }

    func testMissingNewEndingObjectCannotBorrowAnotherArchivedSource() throws {
        let f = try fixture(includesChord: true)
        var broken = f.committed.chart
        broken.roadmapObjects.removeAll { $0.type.isEnding }
        XCTAssertEqual(automatic(f, observed: broken).reason, "render_source_missing")
        XCTAssertEqual(manual(f, observed: broken).reason, "render_source_missing")
    }

    func testChangingExistingEndingSourceDuringAnotherCommitIsDetected() throws {
        let f = try fixture(includesExistingEnding: true)
        XCTAssertEqual(automatic(f).outcome, "passed")
        let originalID = try XCTUnwrap(f.original.roadmapObjects.first { $0.type.isEnding }?.id)
        var broken = f.committed.chart
        let index = try XCTUnwrap(broken.roadmapObjects.firstIndex { $0.id == originalID })
        broken.roadmapObjects[index].sourceInkData = nil
        XCTAssertEqual(automatic(f, observed: broken).reason, "render_source_missing")
    }

    func testUnreviewedEndingRefusalPreservesSourceWithoutAnInkLossClaim() throws {
        let f = try fixture()
        var unreviewed = f.state
        unreviewed.draftEndings[0].isReviewed = false
        let refused = ChordInkDraftRenderCoordinator.prepare(chart: f.original, state: unreviewed,
            currentDrawing: f.source, coordinateSpace: .init(size: pageSize))
        XCTAssertFalse(refused.canConsumeSource)
        let manualCheck = LeadSheetInkFeatureContract.renderAssessment(originalChart: f.original,
            state: unreviewed, sourceDrawing: f.source, outcome: refused, remainingCanvasDrawing: f.source)
        XCTAssertEqual(manualCheck.outcome, "protected_rejection")
        let automaticCheck = ChordInkAutomaticRenderTelemetry.assessment(originalChart: f.original,
            state: unreviewed, sourceDrawing: f.source, outcome: nil,
            observedChart: f.original, observedDrawing: f.source)
        XCTAssertEqual(automaticCheck.outcome, "protected_rejection")
    }

    private struct Fixture {
        var original: Chart
        var source: PKDrawing
        var state: ChordPreviewState
        var committed: ChordInkDraftRenderCoordinator.Outcome

        var automatic: ChordInkDraftRenderCoordinator.AutomaticOutcome {
            .init(chart: committed.chart, drawing: PKDrawing(), remainingState: .init(), result: committed.result,
                consumedDraftIDs: Set(state.draftChords.map(\.id) + state.draftEndings.map(\.id)))
        }
    }

    private func fixture(includesChord: Bool = false, includesExistingEnding: Bool = false) throws -> Fixture {
        var chart = Chart.blank(title: "Synthetic ending telemetry", measureCount: 2, layoutStyle: .simpleChordSheet)
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
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(
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

    private func automatic(_ fixture: Fixture, observed: Chart? = nil) -> LeadSheetInkFeatureContract.Assessment {
        let observed = observed ?? fixture.committed.chart
        let prepared = fixture.automatic
        let outcome = ChordInkDraftRenderCoordinator.AutomaticOutcome(chart: observed, drawing: prepared.drawing,
            remainingState: prepared.remainingState, result: prepared.result, consumedDraftIDs: prepared.consumedDraftIDs)
        return ChordInkAutomaticRenderTelemetry.assessment(originalChart: fixture.original, state: fixture.state,
            sourceDrawing: fixture.source, outcome: outcome, observedChart: observed, observedDrawing: PKDrawing())
    }

    private func manual(_ fixture: Fixture, observed: Chart? = nil) -> LeadSheetInkFeatureContract.Assessment {
        LeadSheetInkFeatureContract.renderAssessment(originalChart: fixture.original, state: fixture.state,
            sourceDrawing: fixture.source, outcome: .init(chart: observed ?? fixture.committed.chart,
                result: fixture.committed.result), remainingCanvasDrawing: PKDrawing())
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
