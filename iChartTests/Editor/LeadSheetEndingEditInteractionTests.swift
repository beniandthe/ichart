#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetEndingEditInteractionTests: XCTestCase {
    func testMovePreviewDoesNotPublishChartAndEndReturnsOneAtomicCommit() throws {
        let fixture = try fixture()
        let start = fixture.moveStart
        let destination = fixture.moveDestination
        var interaction = LeadSheetEndingEditInteraction()
        let begin = handle(&interaction, .began, start: start, point: start, fixture: fixture)
        XCTAssertTrue(begin.began)
        XCTAssertNil(begin.committedChart)
        XCTAssertNil(interaction.previewChart)
        XCTAssertEqual(interaction.dragFeedback, LeadSheetEndingDragFeedback(action: .move,
            range: 1...2, sourceSystemIndex: try XCTUnwrap(fixture.layout.systems.first).index))
        let change = handle(&interaction, .changed, start: start, point: destination, fixture: fixture)
        XCTAssertNil(change.committedChart, "A drag preview has no chart writeback authority")
        let preview = try XCTUnwrap(interaction.previewChart)
        XCTAssertEqual(interaction.dragFeedback?.range, 2...3)
        XCTAssertEqual(preview.roadmapObject(id: fixture.endingID)?.startMeasureID, fixture.ids[2])
        XCTAssertEqual(preview.roadmapObject(id: fixture.endingID)?.endMeasureID, fixture.ids[3])
        XCTAssertEqual(fixture.chart.roadmapObject(id: fixture.endingID)?.startMeasureID, fixture.ids[1])
        XCTAssertFalse(handle(&interaction, .changed, start: start, point: destination,
            fixture: fixture).needsDisplay, "Movement within the same snapped range does not rebuild the ghost")
        let end = handle(&interaction, .ended, start: start, point: destination, fixture: fixture)
        let committed = try XCTUnwrap(end.committedChart)
        XCTAssertTrue(end.finished)
        XCTAssertFalse(interaction.isActive)
        XCTAssertNil(interaction.previewChart)
        XCTAssertNil(interaction.dragFeedback)
        XCTAssertEqual(committed.roadmapObject(id: fixture.endingID)?.startMeasureID, fixture.ids[2])
        XCTAssertEqual(committed.roadmapObject(id: fixture.endingID)?.endMeasureID, fixture.ids[3])
        XCTAssertEqual(committed.roadmapObject(id: fixture.endingID)?.displayText, "1–3, 5; on cue")
        XCTAssertEqual(committed.roadmapObject(id: fixture.endingID)?.endingEndStyle, .open)
        XCTAssertEqual(committed.roadmapObject(id: fixture.endingID)?.sourceInkData,
            fixture.chart.roadmapObject(id: fixture.endingID)?.sourceInkData)
        XCTAssertEqual(committed.measures.map(\.chordEvents), fixture.chart.measures.map(\.chordEvents))
        XCTAssertEqual(committed.pageHandwrittenChordData, fixture.chart.pageHandwrittenChordData)
        XCTAssertNil(handle(&interaction, .ended, start: start, point: destination, fixture: fixture).committedChart,
            "A duplicate gesture callback cannot publish a second edit")
    }

    func testLengthGesturePreservesStartAndUsesOnlyItsFinalEndpoint() throws {
        let fixture = try fixture()
        let controls = try XCTUnwrap(LeadSheetEndingEditOverlay.controlFrames(for: fixture.endingID, in: fixture.layout).last)
        let length = try XCTUnwrap(controls.lengthenHandle)
        let start = CGPoint(x: length.midX, y: length.midY)
        let destination = CGPoint(x: start.x + fixture.measure(3).staffFrame.maxX - fixture.measure(2).staffFrame.maxX, y: start.y)
        var interaction = LeadSheetEndingEditInteraction()
        XCTAssertTrue(handle(&interaction, .began, start: start, point: start,
            fixture: fixture, action: .resizeTrailing).began)
        XCTAssertEqual(interaction.dragFeedback?.action, .resizeTrailing)
        XCTAssertEqual(interaction.dragFeedback?.range, 1...2)
        _ = handle(&interaction, .changed, start: start, point: destination,
            fixture: fixture, action: .resizeTrailing)
        XCTAssertEqual(interaction.dragFeedback?.range, 1...3)
        let result = handle(&interaction, .ended, start: start, point: destination,
            fixture: fixture, action: .resizeTrailing)
        let ending = try XCTUnwrap(result.committedChart?.roadmapObject(id: fixture.endingID))
        XCTAssertEqual(ending.startMeasureID, fixture.ids[1])
        XCTAssertEqual(ending.endMeasureID, fixture.ids[3])
        XCTAssertEqual(ending.displayText, "1–3, 5; on cue")
        XCTAssertEqual(ending.resolvedEndingEndStyle, .open)
        XCTAssertNil(interaction.dragFeedback)
    }

    func testImmediateFeedbackRetainsCachedRangeUntilTheNextMeasureSnap() throws {
        let fixture = try fixture(), start = fixture.moveStart
        var interaction = LeadSheetEndingEditInteraction()
        _ = handle(&interaction, .began, start: start, point: start, fixture: fixture)
        let initialFeedback = try XCTUnwrap(interaction.dragFeedback,
            "Feedback must appear at the grab before there is a candidate chart")
        XCTAssertNil(interaction.previewChart)
        let withinInitialRange = CGPoint(x: start.x + 1, y: start.y)
        XCTAssertFalse(handle(&interaction, .changed, start: start, point: withinInitialRange,
            fixture: fixture).needsDisplay)
        XCTAssertEqual(interaction.dragFeedback, initialFeedback)
        XCTAssertNil(interaction.previewChart, "No redundant candidate is built while the snapped range is unchanged")

        XCTAssertTrue(handle(&interaction, .changed, start: start, point: fixture.moveDestination,
            fixture: fixture).needsDisplay)
        let changedFeedback = try XCTUnwrap(interaction.dragFeedback)
        XCTAssertEqual(changedFeedback.action, .move)
        XCTAssertEqual(changedFeedback.range, 2...3)
        XCTAssertEqual(changedFeedback.sourceSystemIndex, initialFeedback.sourceSystemIndex)
        let cachedChart = try XCTUnwrap(interaction.previewChart)
        let withinChangedRange = CGPoint(x: fixture.moveDestination.x + 1, y: fixture.moveDestination.y)
        XCTAssertFalse(handle(&interaction, .changed, start: start, point: withinChangedRange,
            fixture: fixture).needsDisplay)
        XCTAssertEqual(interaction.dragFeedback, changedFeedback)
        XCTAssertEqual(interaction.previewChart, cachedChart)
        XCTAssertTrue(interaction.cancel())
        XCTAssertNil(interaction.dragFeedback)
        XCTAssertNil(interaction.previewChart)
    }

    func testCancelledAndFailedGesturesDiscardTheirPreviewWithoutACommit() throws {
        let fixture = try fixture()
        let start = fixture.moveStart, destination = fixture.moveDestination
        for cancellation: UIGestureRecognizer.State in [.cancelled, .failed] {
            var interaction = LeadSheetEndingEditInteraction()
            _ = handle(&interaction, .began, start: start, point: start, fixture: fixture)
            _ = handle(&interaction, .changed, start: start, point: destination, fixture: fixture)
            XCTAssertNotNil(interaction.previewChart)
            XCTAssertNotNil(interaction.dragFeedback)
            let effect = handle(&interaction, cancellation, start: start, point: destination, fixture: fixture)
            XCTAssertTrue(effect.finished, "The canvas must release its scroll lock")
            XCTAssertNil(effect.committedChart)
            XCTAssertFalse(interaction.isActive)
            XCTAssertNil(interaction.previewChart)
            XCTAssertNil(interaction.dragFeedback)
            XCTAssertEqual(fixture.chart.roadmapObject(id: fixture.endingID)?.endMeasureID, fixture.ids[2])
        }
    }

    func testNoOpGestureAndUnselectedHandleNeverPublishEdits() throws {
        let fixture = try fixture(), start = fixture.moveStart
        var interaction = LeadSheetEndingEditInteraction()
        let target = dragTarget(fixture: fixture, action: .move, at: start)
        let unselected = interaction.handle(state: .began, startLocation: start, location: start,
            chart: fixture.chart, pageLayout: fixture.layout, selectedEndingID: nil, target: target)
        XCTAssertFalse(unselected.began)
        XCTAssertFalse(interaction.isActive)
        XCTAssertNil(interaction.dragFeedback)
        _ = handle(&interaction, .began, start: start, point: start, fixture: fixture)
        let end = handle(&interaction, .ended, start: start, point: start, fixture: fixture)
        XCTAssertTrue(end.finished)
        XCTAssertNil(end.committedChart, "Selecting or touching a handle is not a content change")
        XCTAssertFalse(interaction.isActive)
        XCTAssertNil(interaction.dragFeedback)
    }

    func testBeginMustMatchARealHandleAndInterruptedBeginReleasesPreviousSession() throws {
        let fixture = try fixture(), start = fixture.moveStart
        var interaction = LeadSheetEndingEditInteraction()
        let body = CGPoint(x: fixture.measure(1).staffFrame.midX, y: fixture.measure(1).staffFrame.midY)
        let invalidStart = handle(&interaction, .began, start: body, point: body, fixture: fixture)
        XCTAssertFalse(invalidStart.began, "A body or stale hit frame cannot silently start an ending move")
        XCTAssertFalse(interaction.isActive)
        XCTAssertNil(interaction.dragFeedback)
        XCTAssertTrue(handle(&interaction, .began, start: start, point: start, fixture: fixture).began)
        let rejected = interaction.handle(state: .began, startLocation: start, location: start,
            chart: fixture.chart, pageLayout: fixture.layout, selectedEndingID: nil, target: nil)
        XCTAssertFalse(rejected.began)
        XCTAssertTrue(rejected.finished, "Rejecting a restart must release the old scroll lock")
        XCTAssertFalse(interaction.isActive)
        XCTAssertTrue(handle(&interaction, .began, start: start, point: start, fixture: fixture).began)
        let replacement = handle(&interaction, .began, start: start, point: start, fixture: fixture)
        XCTAssertTrue(replacement.finished, "Release the prior lock before acquiring the replacement")
        XCTAssertTrue(replacement.began)
        XCTAssertTrue(interaction.isActive)
        _ = interaction.cancel()
        XCTAssertNil(interaction.dragFeedback)
    }

    func testStaleChartSelectionOrLayoutCancelsTheGestureInsteadOfOverwritingEdits() throws {
        let fixture = try fixture(), start = fixture.moveStart, destination = fixture.moveDestination
        for mutation in 0..<3 {
            var interaction = LeadSheetEndingEditInteraction()
            _ = handle(&interaction, .began, start: start, point: start, fixture: fixture)
            var changedChart = fixture.chart
            var layout = fixture.layout
            let selected: UUID? = mutation == 1 ? nil : fixture.endingID
            if mutation == 0 { changedChart.title = "Changed independently" }
            if mutation == 2 {
                layout = LeadSheetPageLayoutEngine.pageLayout(for: changedChart,
                    pageSize: CGSize(width: 1000, height: 1_400))
            }
            XCTAssertFalse(interaction.isCompatible(chart: changedChart, pageLayout: layout, selectedEndingID: selected))
            let effect = interaction.handle(state: .ended, startLocation: start, location: destination,
                chart: changedChart, pageLayout: layout, selectedEndingID: selected, target: nil)
            XCTAssertTrue(effect.finished)
            XCTAssertNil(effect.committedChart)
            XCTAssertFalse(interaction.isActive)
            XCTAssertNil(interaction.previewChart)
            XCTAssertNil(interaction.dragFeedback)
        }
    }

    func testCanvasSelectionsAndLeavingSelectClearEndingSelectionThroughBindingCallback() throws {
        let fixture = try fixture()
        let view = LeadSheetCanvasUIKitView(frame: .zero)
        view.chart = fixture.chart
        var changes: [UUID?] = []
        view.onEndingSpanSelectionChanged = { changes.append($0) }
        view.selectedCueTextID = UUID()
        view.selectedEndingSpanID = fixture.endingID
        XCTAssertNil(view.selectedCueTextID)
        XCTAssertEqual(changes, [fixture.endingID])
        view.selectedChordID = UUID()
        XCTAssertNil(view.selectedEndingSpanID)
        XCTAssertEqual(changes, [fixture.endingID, nil])
        view.selectedEndingSpanID = fixture.endingID
        XCTAssertNil(view.selectedChordID)
        view.interactionMode = .chordEntry
        XCTAssertNil(view.selectedEndingSpanID, "Rendered ending controls must not enter the ink workflow")
        XCTAssertEqual(changes.last!, nil)
    }

    func testCommittedMoveUpdatesContextualMeasureAnchorAndRetainsEndingSelection() throws {
        let fixture = try fixture(), start = fixture.moveStart
        var interaction = LeadSheetEndingEditInteraction()
        _ = handle(&interaction, .began, start: start, point: start, fixture: fixture)
        let effect = handle(&interaction, .ended, start: start, point: fixture.moveDestination, fixture: fixture)
        let committed = try XCTUnwrap(effect.committedChart)
        let view = LeadSheetCanvasUIKitView(frame: .zero)
        view.chart = fixture.chart
        view.selectedMeasureID = fixture.ids[1]
        view.selectedEndingSpanID = fixture.endingID
        var charts: [Chart] = []
        var anchors: [UUID?] = []
        var endingChanges: [UUID?] = []
        view.onChartChanged = { charts.append($0) }
        view.onMeasureSelectionChanged = { anchors.append($0) }
        view.onEndingSpanSelectionChanged = { endingChanges.append($0) }

        view.applyCommittedEndingEdit(committed, action: effect.action)

        XCTAssertEqual(charts, [committed], "The ending drag has one content writeback")
        XCTAssertEqual(anchors, [fixture.ids[2]], "Measures and Repeats must act on the ending's new start")
        XCTAssertEqual(view.selectedMeasureID, fixture.ids[2])
        XCTAssertEqual(view.selectedEndingSpanID, fixture.endingID)
        XCTAssertTrue(endingChanges.isEmpty, "Refreshing the structural anchor must not deselect the ending")
        XCTAssertEqual(view.chart.pageHandwrittenChordData, fixture.chart.pageHandwrittenChordData)
        view.applyCommittedEndingEdit(committed, action: effect.action)
        XCTAssertEqual(charts.count, 1, "Reapplying the identical committed value is a no-op")
    }

    func testParentSelectionSynchronizationIsSilentAndDeletedEndingClearsSelection() throws {
        let fixture = try fixture()
        let view = LeadSheetCanvasUIKitView(frame: .zero)
        view.chart = fixture.chart
        var changes: [UUID?] = []
        view.onEndingSpanSelectionChanged = { changes.append($0) }
        view.applyParentSelectionState(selectedMeasureID: fixture.ids[1], selectedNoteSelection: nil,
            selectedChordID: nil, selectedCommittedBarlineMeasureID: nil, selectedCueTextID: nil,
            selectedRoadmapMarkerID: nil, selectedEndingSpanID: fixture.endingID)
        XCTAssertTrue(changes.isEmpty, "A SwiftUI update must not publish another selection mutation")
        XCTAssertEqual(view.selectedEndingSpanID, fixture.endingID)
        var deleted = fixture.chart
        XCTAssertTrue(deleted.deleteRoadmapObject(fixture.endingID))
        view.chart = deleted
        XCTAssertNil(view.selectedEndingSpanID)
        XCTAssertEqual(changes, [nil])
        XCTAssertEqual(view.chart.pageHandwrittenChordData, fixture.chart.pageHandwrittenChordData)
    }

    private struct Fixture {
        var chart: Chart
        var endingID: UUID
        var layout: LeadSheetPageLayout
        var ids: [UUID] { chart.measures.map(\.id) }
        func measure(_ index: Int) -> LeadSheetMeasureLayout {
            layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == ids[index] }!
        }
        var moveStart: CGPoint {
            let frame = LeadSheetEndingEditOverlay.controlFrames(for: endingID, in: layout).first!.moveHandle
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        var moveDestination: CGPoint {
            CGPoint(x: moveStart.x + measure(2).staffFrame.midX - measure(1).staffFrame.midX, y: moveStart.y)
        }
    }

    private func fixture() throws -> Fixture {
        var chart = Chart.blank(title: "Ending manual adjustment", measureCount: 4, layoutStyle: .simpleChordSheet)
        let ids = chart.measures.map(\.id)
        for id in ids { _ = chart.setMeasureManualLayoutWidth(150, for: id) }
        XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse("Db"), rawInput: "Db", to: ids[1], atFraction: 0.2))
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[1], endMeasureID: ids[2],
            displayText: "1–3, 5; on cue", endStyle: .open))
        let point = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [
            PKStrokePoint(location: CGPoint(x: 20, y: 20), timeOffset: 0,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ], creationDate: Date(timeIntervalSinceReferenceDate: 100)))
        let data = PKDrawing(strokes: [point]).dataRepresentation()
        chart.roadmapObjects[try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == endingID })].sourceInkData = data
        _ = chart.setPageHandwrittenChordDrawing(data)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400))
        return Fixture(chart: chart, endingID: endingID, layout: layout)
    }

    private func dragTarget(fixture: Fixture, action: RenderedEditAction, at point: CGPoint) -> RenderedEditHitTarget {
        RenderedEditHitTarget(objectID: .endingSpan(fixture.endingID), action: action,
            priority: action == .move ? .selectedObjectMoveBody : .selectedObjectResizeHandle,
            frame: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44),
            requiresSelection: true, mutationRisk: .structural)
    }

    private func handle(_ interaction: inout LeadSheetEndingEditInteraction, _ state: UIGestureRecognizer.State,
        start: CGPoint, point: CGPoint, fixture: Fixture, action: RenderedEditAction = .move
    ) -> LeadSheetEndingEditInteraction.Effect {
        interaction.handle(state: state, startLocation: start, location: point, chart: fixture.chart,
            pageLayout: fixture.layout, selectedEndingID: fixture.endingID,
            target: state == .began ? dragTarget(fixture: fixture, action: action, at: start) : nil)
    }
}
#endif
