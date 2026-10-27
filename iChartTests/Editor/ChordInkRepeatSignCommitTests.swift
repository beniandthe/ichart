#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkRepeatSignCommitTests: XCTestCase {
    func testPairingReviewRequiresExplicitBeginningForAStandaloneClosingSign() {
        let measureID = UUID()
        var closing = sign(.repeatEnd, measureID: measureID, fraction: 0.6)
        var state = preview([closing])
        let unconfirmed = ChordInkRepeatSignPairingPolicy.review(state: state)
        XCTAssertEqual(unconfirmed.unconfirmedEndIDs, [closing.id])
        XCTAssertFalse(unconfirmed.canRender)
        closing.repeatFromBeginningConfirmed = true
        state.draftBarlines = [closing]
        XCTAssertTrue(ChordInkRepeatSignPairingPolicy.review(state: state).canRender)
    }

    func testPairingReviewIdentifiesNestedAndUnmatchedStarts() {
        let measureID = UUID()
        let first = sign(.repeatStart, measureID: measureID, fraction: 0.2)
        let nested = sign(.repeatStart, measureID: measureID, fraction: 0.4)
        let close = sign(.repeatEnd, measureID: measureID, fraction: 0.7)
        let review = ChordInkRepeatSignPairingPolicy.review(state: preview([first, nested, close]))
        XCTAssertEqual(Set(review.nestedStartIDs), [first.id, nested.id])
        XCTAssertFalse(review.canRender)
        let unmatched = ChordInkRepeatSignPairingPolicy.review(state: preview([first]))
        XCTAssertEqual(unmatched.unmatchedStartIDs, [first.id])
    }

    func testSharedCloseAndOpenBoundaryUsesOppositeSidesAndSharesOnlyItsOwnInk() {
        let ids = (0..<4).map { _ in UUID() }
        let start = sign(.repeatStart, measureID: ids[0], fraction: 0.2, indices: [0, 1, 2])
        let both = sign(.repeatBoth, measureID: ids[0], fraction: 0.5, indices: [3, 4, 5, 6, 7])
        let end = sign(.repeatEnd, measureID: ids[0], fraction: 0.8, indices: [8, 9, 10])
        let plan = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
            .init(draft: end, leftMeasureID: ids[2], rightMeasureID: ids[3]),
            .init(draft: start, leftMeasureID: ids[0], rightMeasureID: ids[1]),
            .init(draft: both, leftMeasureID: ids[1], rightMeasureID: ids[2])
        ], orderedMeasureIDs: ids)
        XCTAssertTrue(plan.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(plan.spans.map(\.startMeasureID), [ids[1], ids[2]])
        XCTAssertEqual(plan.spans.map(\.endMeasureID), [ids[1], ids[2]])
        XCTAssertEqual(plan.spans[0].sourceStrokeIndices, Set(0...7))
        XCTAssertEqual(plan.spans[1].sourceStrokeIndices, Set(3...10))
    }

    func testSeparateRowEndAndNextRowStartShareBoundaryRegardlessOfUUIDOrder() throws {
        let ids = (0..<4).map { _ in UUID() }
        let lowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        for (endID, nextStartID) in [(highID, lowID), (lowID, highID)] {
            var start = sign(.repeatStart, measureID: ids[0], fraction: 0, indices: [0, 1, 2])
            start.laneLocation = ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0)
            var end = sign(.repeatEnd, measureID: ids[1], fraction: 0.9999, indices: [3, 4, 5])
            end.id = endID
            end.laneLocation = ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.9999)
            var nextStart = sign(.repeatStart, measureID: ids[2], fraction: 0, indices: [6, 7, 8])
            nextStart.id = nextStartID
            nextStart.laneLocation = ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0)
            var nextEnd = sign(.repeatEnd, measureID: ids[3], fraction: 0.9999, indices: [9, 10, 11])
            nextEnd.laneLocation = ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.9999)
            let drafts = [nextStart, nextEnd, end, start]
            XCTAssertTrue(ChordInkRepeatSignPairingPolicy.review(state: preview(drafts)).canRender,
                "The visual row order forms two complete consecutive repeats")
            let plan = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
                .init(draft: nextStart, leftMeasureID: ids[1], rightMeasureID: ids[2]),
                .init(draft: nextEnd, leftMeasureID: ids[3], rightMeasureID: nil),
                .init(draft: end, leftMeasureID: ids[1], rightMeasureID: ids[2]),
                .init(draft: start, leftMeasureID: nil, rightMeasureID: ids[0])
            ], orderedMeasureIDs: ids)
            XCTAssertTrue(plan.unresolvedDraftIDs.isEmpty,
                "Coincident musical boundaries must not reorder an end after the next row's start based on UUID")
            XCTAssertEqual(plan.spans.map(\.startMeasureID), [ids[0], ids[2]])
            XCTAssertEqual(plan.spans.map(\.endMeasureID), [ids[1], ids[3]])
            XCTAssertEqual(plan.spans.map(\.sourceDraftIDs), [[start.id, end.id], [nextStart.id, nextEnd.id]])
            XCTAssertEqual(plan.spans.map(\.sourceStrokeIndices), [Set(0...5), Set(6...11)],
                "Separate signs retain only their own start/end source pair")
        }
    }

    func testCoincidentSameKindSignsRemainUnresolvedInsteadOfBecomingExtraRepeats() {
        let ids = (0..<2).map { _ in UUID() }
        let start = sign(.repeatStart, measureID: ids[0], fraction: 0)
        let end = sign(.repeatEnd, measureID: ids[1], fraction: 0.9999)
        for duplicatedKind in [DraftBarlineKind.repeatStart, .repeatEnd] {
            var duplicate = duplicatedKind == .repeatStart ? start : end
            duplicate.id = UUID()
            let duplicateBoundary = ChordInkRepeatSignCommitPolicy.Boundary(draft: duplicate,
                leftMeasureID: duplicatedKind == .repeatStart ? nil : ids[1],
                rightMeasureID: duplicatedKind == .repeatStart ? ids[0] : nil)
            let plan = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
                .init(draft: start, leftMeasureID: nil, rightMeasureID: ids[0]),
                duplicateBoundary,
                .init(draft: end, leftMeasureID: ids[1], rightMeasureID: nil)
            ], orderedMeasureIDs: ids)
            XCTAssertTrue(plan.spans.isEmpty)
            XCTAssertFalse(plan.unresolvedDraftIDs.isEmpty)
        }
    }

    func testCombinedSignStillClosesPreviousSpanAndStartsNextAtSharedBoundary() {
        let ids = (0..<4).map { _ in UUID() }
        let start = sign(.repeatStart, measureID: ids[0], fraction: 0, indices: [0])
        let both = sign(.repeatBoth, measureID: ids[1], fraction: 0.9999, indices: [1, 2])
        let end = sign(.repeatEnd, measureID: ids[3], fraction: 0.9999, indices: [3])
        let plan = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
            .init(draft: end, leftMeasureID: ids[3], rightMeasureID: nil),
            .init(draft: both, leftMeasureID: ids[1], rightMeasureID: ids[2]),
            .init(draft: start, leftMeasureID: nil, rightMeasureID: ids[0])
        ], orderedMeasureIDs: ids)
        XCTAssertTrue(plan.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(plan.spans.map(\.startMeasureID), [ids[0], ids[2]])
        XCTAssertEqual(plan.spans.map(\.endMeasureID), [ids[1], ids[3]])
        XCTAssertEqual(plan.spans.map(\.sourceStrokeIndices), [[0, 1, 2], [1, 2, 3]])
    }

    func testEmptyAndNonadjacentMappedBoundariesRejectEverySpan() {
        let ids = (0..<3).map { _ in UUID() }
        let start = sign(.repeatStart, measureID: ids[0], fraction: 0.2)
        let end = sign(.repeatEnd, measureID: ids[0], fraction: 0.8)
        let empty = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
            .init(draft: start, leftMeasureID: ids[0], rightMeasureID: ids[1]),
            .init(draft: end, leftMeasureID: ids[0], rightMeasureID: ids[1])
        ], orderedMeasureIDs: ids)
        XCTAssertTrue(empty.spans.isEmpty)
        XCTAssertEqual(Set(empty.unresolvedDraftIDs), [start.id, end.id])
        let disconnected = ChordInkRepeatSignCommitPolicy.plan(boundaries: [
            .init(draft: start, leftMeasureID: ids[0], rightMeasureID: ids[2]),
            .init(draft: end, leftMeasureID: ids[1], rightMeasureID: ids[2])
        ], orderedMeasureIDs: ids)
        XCTAssertTrue(disconnected.spans.isEmpty)
        XCTAssertTrue(disconnected.unresolvedDraftIDs.contains(start.id))
    }

    func testEndpointToleranceUsesSourcePointsAndLeavesInteriorBoundariesInterior() {
        XCTAssertEqual(ChordInkRepeatSignCommitPolicy.boundaryPlacement(fraction: 0.005, sourceWidth: 800), .leading)
        XCTAssertEqual(ChordInkRepeatSignCommitPolicy.boundaryPlacement(fraction: 0.995, sourceWidth: 800), .trailing)
        XCTAssertEqual(ChordInkRepeatSignCommitPolicy.boundaryPlacement(fraction: 0.02, sourceWidth: 800), .interior)
        XCTAssertEqual(ChordInkRepeatSignCommitPolicy.boundaryPlacement(fraction: 0.5, sourceWidth: 20), .interior)
    }

    func testRealPairedInkCreatesTwoSpansAfterSplittingAndSurvivesChartJSON() throws {
        for spacing in [ChordDraftBarlineSpacingMode.drawn, .even] {
            var chart = draftChart()
            chart.staffSystemDensity = .dense
            chart.pageHandwrittenNotationData = Data([1, 2, 3])
            chart.pageHandwrittenHeaderData = Data([4, 5, 6])
            let fixture = try fixture(chart)
            let drawing = PKDrawing(strokes:
                repeatStrokes(.repeatStart, x: fixture.lane.minX + fixture.lane.width * 0.2, fixture: fixture)
                + repeatStrokes(.repeatBoth, x: fixture.lane.minX + fixture.lane.width * 0.5, fixture: fixture)
                + repeatStrokes(.repeatEnd, x: fixture.lane.minX + fixture.lane.width * 0.8, fixture: fixture))
            let source = try install(drawing, in: &chart, fixture: fixture)
            let original = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let result = chart.commitChordInkDraftBatch(source, barlineSpacingMode: spacing)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(result.renderedBarlineCount, 3)
            XCTAssertEqual(chart.measures.count, 4)
            let spans = chart.roadmapObjects.filter { $0.type == .repeatSpan }
            XCTAssertEqual(spans.count, 2)
            XCTAssertEqual(spans.map(\.startMeasureID), [chart.measures[1].id, chart.measures[2].id])
            XCTAssertEqual(spans.map(\.endMeasureID), [chart.measures[1].id, chart.measures[2].id])
            for (span, indices) in zip(spans, [Array(0...7), Array(3...10)]) {
                let retained = try PKDrawing(data: XCTUnwrap(span.sourceInkData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: PKDrawing(strokes: indices.map { original.strokes[$0] }), current: retained))
            }
            XCTAssertNil(chart.pageHandwrittenChordData)
            XCTAssertEqual(chart.staffSystemDensity, .dense)
            XCTAssertEqual(chart.pageHandwrittenNotationData, Data([1, 2, 3]))
            XCTAssertEqual(chart.pageHandwrittenHeaderData, Data([4, 5, 6]))
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertEqual(reopened, chart)
        }
    }

    func testExistingLeadingAndTerminalBoundariesDoNotCreateSliverMeasures() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .leadSheet] {
            var chart = Chart.blank(title: "Existing boundaries", measureCount: 2, layoutStyle: style)
            let fixture = try fixture(chart)
            let first = try XCTUnwrap(fixture.system.measures.first)
            let last = try XCTUnwrap(fixture.system.measures.last)
            let firstDisplay = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(first, in: fixture.system, paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: style)
            let lastDisplay = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(last, in: fixture.system, paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: style)
            let drawing = PKDrawing(strokes:
                repeatStrokes(.repeatStart, x: firstDisplay.frame.minX + 1, fixture: fixture)
                + repeatStrokes(.repeatEnd, x: lastDisplay.frame.maxX - 1, fixture: fixture))
            let state = try install(drawing, in: &chart, fixture: fixture)
            let ids = chart.measures.map(\.id)
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage, style.rawValue)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, style.rawValue)
            XCTAssertEqual(result.renderedBarlineCount, 2, style.rawValue)
            XCTAssertEqual(chart.measures.map(\.id), ids, style.rawValue)
            let span = try XCTUnwrap(chart.roadmapObjects.first { $0.type == .repeatSpan })
            XCTAssertEqual(span.startMeasureID, ids.first)
            XCTAssertEqual(span.endMeasureID, ids.last)
            XCTAssertNotNil(span.sourceInkData)
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testLeadSheetInteriorRepeatCannotPartiallyCommitOrClearInk() throws {
        var chart = Chart.blank(title: "No rhythmic split", measureCount: 1, layoutStyle: .leadSheet)
        let fixture = try fixture(chart)
        let measure = try XCTUnwrap(fixture.system.measures.first)
        let drawing = PKDrawing(strokes:
            repeatStrokes(.repeatStart, x: measure.frame.minX + measure.frame.width * 0.25, fixture: fixture)
            + repeatStrokes(.repeatEnd, x: measure.frame.minX + measure.frame.width * 0.75, fixture: fixture))
        let state = try install(drawing, in: &chart, fixture: fixture)
        let before = chart
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(Set(result.unresolvedDraftIDs), Set(state.draftBarlines.map(\.id)))
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertEqual(chart, before)
    }

    func testUnsplittableOrdinaryBarlineRejectsMixedRepeatBatchWithoutInkLoss() throws {
        var chart = Chart.blank(title: "Mixed repeat transaction", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let fixture = try fixture(chart)
        let first = try XCTUnwrap(fixture.system.measures.first)
        let last = try XCTUnwrap(fixture.system.measures.last)
        let centerX = first.staffFrame.midX - fixture.chordFrame.minX
        let centerY = fixture.lane.midY - fixture.chordFrame.minY
        let height = fixture.lane.height * 0.84
        let ordinary = stroke([CGPoint(x: centerX, y: centerY - height / 2), CGPoint(x: centerX, y: centerY + height / 2)])
        let drawing = PKDrawing(strokes:
            repeatStrokes(.repeatStart, x: first.staffFrame.minX + 1, fixture: fixture)
            + [ordinary]
            + repeatStrokes(.repeatEnd, x: last.staffFrame.maxX - 1, fixture: fixture))
        let state = try install(drawing, in: &chart, fixture: fixture, allRepeatSigns: false)
        let ordinaryDraft = try XCTUnwrap(state.draftBarlines.first { $0.kind == .single })
        XCTAssertEqual(state.draftBarlines.filter { $0.kind.isRepeat }.count, 2)
        let before = chart
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertTrue(result.unresolvedDraftIDs.contains(ordinaryDraft.id))
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(chart, before)
        XCTAssertEqual(chart.pageHandwrittenChordData, before.pageHandwrittenChordData)
    }

    func testRejectedPairThroughConvenienceMethodLeavesExactChartAndInk() throws {
        var chart = draftChart()
        let fixture = try fixture(chart)
        let drawing = PKDrawing(strokes: repeatStrokes(.repeatStart, x: fixture.lane.midX, fixture: fixture))
        let state = try install(drawing, in: &chart, fixture: fixture)
        let before = chart
        let rendered = chart.commitChordInkDraftBarlines(state.draftBarlines, layoutPageSize: state.layoutPageSize)
        XCTAssertTrue(rendered.isEmpty)
        XCTAssertEqual(chart, before)
        XCTAssertEqual(chart.pageHandwrittenChordData, before.pageHandwrittenChordData)
    }

    func testRedrawnExistingRepeatRejectsAtomicallyWithLegacyAndStoredSource() throws {
        for hasPriorSource in [false, true] {
            var chart = Chart.blank(title: "Preserve existing span", measureCount: 2, layoutStyle: .simpleChordSheet)
            let ids = chart.measures.map(\.id)
            let existingID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1]))
            if hasPriorSource {
                let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == existingID })
                chart.roadmapObjects[index].sourceInkData = PKDrawing(strokes: [stroke([CGPoint(x: 25, y: 25)])]).dataRepresentation()
            }
            let fixture = try fixture(chart)
            let first = try XCTUnwrap(fixture.system.measures.first)
            let last = try XCTUnwrap(fixture.system.measures.last)
            let lastDisplay = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(last, in: fixture.system, paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: chart.layoutStyle)
            let drawing = PKDrawing(strokes:
                repeatStrokes(.repeatStart, x: first.frame.minX + 1, fixture: fixture)
                + repeatStrokes(.repeatEnd, x: lastDisplay.frame.maxX - 1, fixture: fixture))
            let state = try install(drawing, in: &chart, fixture: fixture)
            let before = chart
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(Set(result.unresolvedDraftIDs), Set(state.draftBarlines.map(\.id)))
            XCTAssertEqual(result.renderedBarlineCount, 0)
            XCTAssertEqual(chart, before)
            XCTAssertEqual(chart.pageHandwrittenChordData, before.pageHandwrittenChordData)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
            // The chart decoder normalizes page PKDrawing serialization. Its
            // visible ink must survive even when PencilKit emits new bytes.
            let beforeInk = try PKDrawing(data: XCTUnwrap(before.pageHandwrittenChordData))
            let reopenedInk = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: beforeInk, current: reopenedInk))
            XCTAssertEqual(reopened.roadmapObjects, before.roadmapObjects)
            XCTAssertEqual(reopened.roadmapObjects.first { $0.id == existingID }?.sourceInkData,
                before.roadmapObjects.first { $0.id == existingID }?.sourceInkData)
            XCTAssertEqual(reopened.systems, before.systems)
            XCTAssertEqual(reopened.id, before.id)
            XCTAssertEqual(reopened.createdAt, before.createdAt)
            XCTAssertEqual(reopened.updatedAt, before.updatedAt)
            var expectedReopened = before
            expectedReopened.pageHandwrittenChordData = reopened.pageHandwrittenChordData
            XCTAssertEqual(reopened, expectedReopened, "Every other persisted chart field remains exact.")
        }
    }

    private struct Fixture {
        var layout: LeadSheetPageLayout
        var system: LeadSheetSystemLayout
        var chordFrame: CGRect
        var lane: CGRect
    }

    private func draftChart() -> Chart {
        var chart = Chart.draft(title: "Repeat commit", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func fixture(_ chart: Chart) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(layout: layout, system: system, chordFrame: region.frame, lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func install(_ drawing: PKDrawing, in chart: inout Chart, fixture: Fixture, allRepeatSigns: Bool = true) throws -> ChordPreviewState {
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let stored = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.repeatAwareVisibleDrawingContext(from: stored, chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let fresh = ChordDraftBarlineRecognizer.recognizeIncludingRepeats(strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing), chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(fresh)
        let signs = context.remappedBarlineRecognition(safe).barlines
        XCTAssertFalse(signs.isEmpty)
        if allRepeatSigns { XCTAssertTrue(signs.allSatisfy { $0.kind.isRepeat }) }
        let state = preview(signs, pageSize: fixture.layout.pageBounds.size)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return state
    }

    private func repeatStrokes(_ kind: DraftBarlineKind, x: CGFloat, fixture: Fixture) -> [PKStroke] {
        let lane = fixture.lane
        let origin = fixture.chordFrame.origin
        let center = CGPoint(x: x - origin.x, y: lane.midY - origin.y)
        let height = lane.height * 0.84
        var strokes = [stroke([CGPoint(x: center.x, y: center.y - height / 2), CGPoint(x: center.x, y: center.y + height / 2)])]
        for side in [-1.0, 1.0] where (side < 0 ? kind.endsRepeat : kind.startsRepeat) {
            for vertical in [-1.0, 1.0] {
                strokes.append(stroke([CGPoint(x: center.x + CGFloat(side) * height * 0.20, y: center.y + CGFloat(vertical) * height * 0.18)], size: 1.4))
            }
        }
        return strokes
    }

    private func sign(_ kind: DraftBarlineKind, measureID: UUID, fraction: Double, indices: Set<Int> = []) -> DraftBarline {
        DraftBarline(measureID: measureID, measureIndex: 0, fraction: fraction,
            metrics: DraftBarlineGestureMetrics(height: 50, width: 0, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.9),
            kind: kind, sourceStrokeIndices: indices)
    }

    private func preview(_ signs: [DraftBarline], pageSize: CGSize? = nil) -> ChordPreviewState {
        var state = ChordPreviewState()
        state.draftBarlines = signs
        state.layoutPageSize = pageSize
        return state
    }

    private func stroke(_ points: [CGPoint], size: CGFloat = 3) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}
#endif
