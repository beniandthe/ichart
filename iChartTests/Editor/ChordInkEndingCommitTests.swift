#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkEndingCommitTests: XCTestCase {
    func testPageBoundaryAliasesDoNotCompeteWithTheirOwnMusicalBoundary() {
        let ids = (0..<3).map { _ in UUID() }
        let boundaries: [ChordInkEndingCommitPolicy.PageBoundary] = [
            .init(leftMeasureID: ids[0], rightMeasureID: ids[1], sourceRanges: [100...100]),
            .init(leftMeasureID: ids[0], rightMeasureID: ids[1], sourceRanges: [112...128]),
            .init(leftMeasureID: ids[1], rightMeasureID: ids[2], sourceRanges: [180...180])
        ]
        XCTAssertEqual(ChordInkEndingCommitPolicy.measureID(atSourceX: 123,
            boundaries: boundaries, isStart: false), ids[0])
        XCTAssertEqual(ChordInkEndingCommitPolicy.measureID(atSourceX: 123,
            boundaries: boundaries, isStart: true), ids[1])
    }

    func testPageBoundarySnapsOnlyTheClearlyNearestDistinctBoundary() {
        let ids = (0..<3).map { _ in UUID() }
        let boundaries: [ChordInkEndingCommitPolicy.PageBoundary] = [
            .init(leftMeasureID: ids[0], rightMeasureID: ids[1], sourceRanges: [100...100]),
            .init(leftMeasureID: ids[1], rightMeasureID: ids[2], sourceRanges: [130...130])
        ]
        XCTAssertEqual(ChordInkEndingCommitPolicy.measureID(atSourceX: 112,
            boundaries: boundaries, isStart: false), ids[0])
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 115,
            boundaries: boundaries, isStart: false), "A midpoint cannot choose the following measure")
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 114,
            boundaries: boundaries, isStart: false), "A near tie still needs explicit review")
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 80,
            boundaries: boundaries, isStart: false), "Tolerance stays bounded in page points")
    }

    func testEndingAtRenderedTerminalRepeatUsesLastSplitSegmentAndExcludesOpenContinuation() throws {
        for (spacing, endpointOffset) in ChordDraftBarlineSpacingMode.allCases.flatMap({ spacing in
            [CGFloat(8), 24].map { (spacing, $0) }
        }) {
            var chart = Chart.blank(title: "Repeat ending join", measureCount: 6, layoutStyle: .simpleChordSheet)
            let ids = chart.measures.map(\.id)
            let widths: [Double] = [91, 120, 50, 92, 92, 64]
            for system in chart.systems.indices {
                for measure in chart.systems[system].measures.indices {
                    let id = chart.systems[system].measures[measure].id
                    chart.systems[system].measures[measure].manualLayoutWidth = widths[try XCTUnwrap(ids.firstIndex(of: id))]
                    chart.systems[system].measures[measure].authoringState = id == ids.last ? .open : .committed
                }
            }
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[3], endMeasureID: ids[4]))
            let existingEndingID = try XCTUnwrap(chart.addEndingSpan(.ending1,
                startMeasureID: ids[3], endMeasureID: ids[3], displayText: "1.", endStyle: .open))
            let repeatIndex = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == repeatID })
            chart.roadmapObjects[repeatIndex].sourceInkData = Data([7, 8, 9])
            let existingEnding = chart.roadmapObject(id: existingEndingID)
            let fixture = try fixture(chart)
            let repeatedMeasure = try XCTUnwrap(fixture.system.measures.first { $0.sourceMeasureID == ids[4] })
            let terminalX = try XCTUnwrap(LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: repeatedMeasure, in: fixture.system,
                paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: .simpleChordSheet))
            let startX = repeatedMeasure.frame.minX + repeatedMeasure.frame.width * 0.603
            let drawing = PKDrawing(strokes: bracket(fixture: fixture,
                left: startX, right: terminalX - endpointOffset).strokes + [barline(x: startX, fixture: fixture)])
            var state = try install(drawing, in: &chart, fixture: fixture)
            XCTAssertEqual(state.draftBarlines.count, 1)
            XCTAssertEqual(chart.draftEndingReviewMeasureCount(state: state), 7)
            XCTAssertEqual(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state), 6...6)
            try review(&state, chart: chart, label: "2–4", style: .open)
            let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: spacing)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, spacing.rawValue)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage, spacing.rawValue)
            XCTAssertEqual(result.renderedEndingCount, 1)
            XCTAssertEqual(chart.measures.count, 7)
            let ending = try XCTUnwrap(chart.roadmapObjects.last { $0.type.isEnding })
            XCTAssertEqual(ending.startMeasureID, chart.measures[5].id)
            XCTAssertEqual(ending.endMeasureID, chart.measures[5].id)
            XCTAssertEqual(chart.measures[6].id, ids[5], "The pre-existing open continuation stays outside")
            let repeatSpan = try XCTUnwrap(chart.roadmapObject(id: repeatID))
            XCTAssertEqual(repeatSpan.startMeasureID, ids[3])
            XCTAssertEqual(repeatSpan.endMeasureID, chart.measures[5].id)
            XCTAssertEqual(repeatSpan.sourceInkData, Data([7, 8, 9]))
            XCTAssertEqual(chart.roadmapObject(id: existingEndingID), existingEnding)
            XCTAssertFalse(chart.measure(id: ids[4])!.roadmapObjectIDs.contains(repeatID))
            XCTAssertTrue(chart.measures[5].roadmapObjectIDs.contains(repeatID))
        }
    }

    func testExplicitReviewedRangeIsTheOnlyOverrideAndStaleOrPartialChoicesRollBack() throws {
        var original = Chart.blank(title: "Reviewed range", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try fixture(original)
        var state = try install(bracket(fixture: fixture,
            left: fixture.lane.minX + fixture.lane.width * 0.2,
            right: fixture.lane.minX + fixture.lane.width * 0.7), in: &original, fixture: fixture)
        try review(&state, chart: original, label: "On cue", style: .open)
        let context = try XCTUnwrap(ChordDraftEndingRangeReviewContext.capture(chart: original, state: state))
        state.draftEndings[0].reviewedMeasureRange = 1...1
        state.draftEndings[0].reviewedRangeContext = context
        XCTAssertEqual(original.draftEndingMeasureRange(for: state.draftEndings[0], state: state), 1...1)
        XCTAssertNil(original.draftEndingMeasureRange(for: state.draftEndings[0], state: state, ignoringReviewedRange: true))
        var committed = original
        XCTAssertEqual(committed.commitChordInkDraftBatch(state).renderedEndingCount, 1)
        XCTAssertEqual(committed.roadmapObjects.last?.startMeasureID, original.measures[0].id)
        XCTAssertEqual(committed.roadmapObjects.last?.endMeasureID, original.measures[0].id)
        for variant in 0..<3 {
            var invalid = state
            var chart = original
            if variant == 0 { invalid.draftEndings[0].reviewedRangeContext = nil }
            if variant == 1 { invalid.draftEndings[0].reviewedMeasureRange = 1...3 }
            if variant == 2 { chart.title += " changed" }
            let before = chart
            let result = chart.commitChordInkDraftBatch(invalid)
            XCTAssertEqual(result.renderedEndingCount, 0)
            XCTAssertFalse(result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(chart, before)
            XCTAssertNil(chart.draftEndingMeasureRange(for: invalid.draftEndings[0], state: invalid))
        }
    }

    func testSourceBoundarySelectsOppositeSidesWithoutRenderedSpacing() {
        let ids = (0..<3).map { _ in UUID() }
        let boundaries: [ChordInkEndingCommitPolicy.PageBoundary] = [
            .init(leftMeasureID: nil, rightMeasureID: ids[0], sourceRanges: [0...0]),
            .init(leftMeasureID: ids[0], rightMeasureID: ids[1], sourceRanges: [160...160]),
            .init(leftMeasureID: ids[1], rightMeasureID: ids[2], sourceRanges: [560...560]),
            .init(leftMeasureID: ids[2], rightMeasureID: nil, sourceRanges: [800...800])
        ]
        XCTAssertEqual(ChordInkEndingCommitPolicy.measureID(atSourceX: 160,
            boundaries: boundaries, isStart: true), ids[1])
        XCTAssertEqual(ChordInkEndingCommitPolicy.measureID(atSourceX: 560,
            boundaries: boundaries, isStart: false), ids[1])
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 800.0 / 3.0,
            boundaries: boundaries, isStart: true), "Rendered even positions cannot change source membership")
    }

    func testDistantAndAmbiguousPagePointsNeverForceAMeasureChoice() {
        let ids = (0..<3).map { _ in UUID() }
        let boundary = ChordInkEndingCommitPolicy.PageBoundary(leftMeasureID: ids[0],
            rightMeasureID: ids[1], sourceRanges: [400...400])
        let ambiguous = ChordInkEndingCommitPolicy.PageBoundary(leftMeasureID: ids[1],
            rightMeasureID: ids[2], sourceRanges: [400...400])
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 424,
            boundaries: [boundary], isStart: true))
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: 400,
            boundaries: [boundary, ambiguous], isStart: true))
        XCTAssertNil(ChordInkEndingCommitPolicy.measureID(atSourceX: .nan,
            boundaries: [boundary], isStart: true))
    }

    func testExactSourceRefreshPreservesReviewAndChangedLabelInkResetsIt() throws {
        var chart = Chart.blank(title: "Review identity", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        let original = try XCTUnwrap(state.draftEndings.first)
        state.draftEndings[0].label = "1–3, 5"
        state.draftEndings[0].endStyle = .open
        state.draftEndings[0].isReviewed = true
        state.replaceDraftEndings(with: [original])
        XCTAssertEqual(state.draftEndings.first?.id, original.id)
        XCTAssertEqual(state.draftEndings.first?.label, "1–3, 5")
        XCTAssertEqual(state.draftEndings.first?.endStyle, .open)
        XCTAssertTrue(try XCTUnwrap(state.draftEndings.first).isReviewed)
        var changed = original
        changed.sourceStrokeGeometry[0].points[0].x += 0.25
        state.replaceDraftEndings(with: [changed])
        XCTAssertFalse(try XCTUnwrap(state.draftEndings.first).isReviewed)
        XCTAssertEqual(state.draftEndings.first?.label, "")
    }

    func testEndingOnlyCustomLabelCommitsAndRetainsSourceAcrossJSONRoundTrip() throws {
        for label in ["1, 2, 3", "1–3, 5", "On cue"] {
            var chart = Chart.blank(title: "Ending only", measureCount: 2, layoutStyle: .simpleChordSheet)
            chart.pageHandwrittenHeaderData = Data([1, 2, 3])
            chart.pageHandwrittenNotationData = Data([4, 5, 6])
            let fixture = try fixture(chart)
            var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
            let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            try review(&state, chart: chart, label: "  \(label) \n", style: .open)
            let before = chart
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
            XCTAssertEqual(result.renderedEndingCount, 1)
            XCTAssertEqual(result.renderedBarlineCount, 0)
            let ending = try XCTUnwrap(chart.roadmapObjects.first { $0.type.isEnding })
            XCTAssertEqual(ending.startMeasureID, before.measures.first?.id)
            XCTAssertEqual(ending.endMeasureID, before.measures.last?.id)
            XCTAssertEqual(ending.resolvedEndingDisplayText, label)
            XCTAssertEqual(ending.resolvedEndingEndStyle, .open)
            let retained = try PKDrawing(data: XCTUnwrap(ending.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: retained))
            XCTAssertNil(chart.pageHandwrittenChordData)
            XCTAssertEqual(chart.pageHandwrittenHeaderData, before.pageHandwrittenHeaderData)
            XCTAssertEqual(chart.pageHandwrittenNotationData, before.pageHandwrittenNotationData)
            XCTAssertEqual(chart.measures.map(\.id), before.measures.map(\.id))
            XCTAssertEqual(try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart)), chart)
        }
    }

    func testUnreviewedAndBlankLabelsCannotClearSourceOrChangeTheChart() throws {
        var chart = Chart.blank(title: "Needs label", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        XCTAssertTrue(state.canRenderAny, "Render must be available to open ending review")
        let before = chart
        let unreviewed = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(unreviewed.renderedEndingCount, 0)
        XCTAssertEqual(unreviewed.unresolvedDraftIDs, state.draftEndings.map(\.id))
        XCTAssertEqual(chart, before)
        try review(&state, chart: chart, label: " \n\t ", style: .closed)
        let blank = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(blank.renderedEndingCount, 0)
        XCTAssertEqual(chart, before)
    }

    func testNewBarlineSplitsUseSourceMembershipInBothSpacingModes() throws {
        for spacing in ChordDraftBarlineSpacingMode.allCases {
            var chart = draftChart()
            let fixture = try fixture(chart)
            let x0 = fixture.lane.minX + fixture.lane.width * 0.2
            let x1 = fixture.lane.minX + fixture.lane.width * 0.7
            let drawing = PKDrawing(strokes: bracket(fixture: fixture, left: x0, right: x1).strokes
                + [barline(x: x0, fixture: fixture), barline(x: x1, fixture: fixture)])
            var state = try install(drawing, in: &chart, fixture: fixture)
            XCTAssertEqual(state.draftBarlines.count, 2)
            let beforeRangeReview = chart
            XCTAssertEqual(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state), 2...2)
            XCTAssertEqual(chart, beforeRangeReview, "Range preview must not persist its temporary split plan")
            try review(&state, chart: chart, label: "3–5", style: .closed)
            let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: spacing)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage, spacing.rawValue)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, spacing.rawValue)
            XCTAssertEqual(result.renderedEndingCount, 1, spacing.rawValue)
            XCTAssertEqual(chart.measures.count, 3, spacing.rawValue)
            let ending = try XCTUnwrap(chart.roadmapObjects.first { $0.type.isEnding })
            XCTAssertEqual(ending.startMeasureID, chart.measures[1].id, spacing.rawValue)
            XCTAssertEqual(ending.endMeasureID, chart.measures[1].id,
                "The following measure must remain outside the ending in \(spacing.rawValue) spacing")
        }
    }

    func testBracketEndpointsDoNotCreateNewSplitsWithoutBarlines() throws {
        var chart = draftChart()
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture,
            left: fixture.lane.minX + fixture.lane.width * 0.2,
            right: fixture.lane.minX + fixture.lane.width * 0.7), in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "On cue", style: .open)
        let before = chart
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(result.unresolvedDraftIDs, state.draftEndings.map(\.id))
        XCTAssertEqual(result.renderedEndingCount, 0)
        XCTAssertEqual(chart, before)
        XCTAssertNil(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state))
    }

    func testEndingOnlyOnContinuationRowMaterializesExactlyItsTargetRow() throws {
        var chart = draftChart()
        let fixture = try fixture(chart, systemIndex: 1)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "After solo", style: .open)
        XCTAssertEqual(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state), 2...2)
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertFalse(result.didRejectIncompleteSourceCoverage)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(result.renderedEndingCount, 1)
        XCTAssertEqual(chart.systems.count, 2)
        let ending = try XCTUnwrap(chart.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(ending.startMeasureID, chart.systems[1].measures.first?.id)
        XCTAssertEqual(ending.endMeasureID, chart.systems[1].measures.first?.id)
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testExistingBoundariesInLeadAndRhythmLayoutsKeepRangeAndSourceReceipt() throws {
        for style in [ChartLayoutStyle.leadSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Existing ending bounds", measureCount: 2, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let fixture = try fixture(chart)
            var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
            let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            XCTAssertEqual(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state),
                1...2, style.rawValue)
            try review(&state, chart: chart, label: "On cue", style: .closed)
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertFalse(result.didRejectIncompleteSourceCoverage, style.rawValue)
            XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, style.rawValue)
            XCTAssertEqual(result.renderedEndingCount, 1, style.rawValue)
            XCTAssertEqual(chart.measures.map(\.id), ids, style.rawValue)
            let ending = try XCTUnwrap(chart.roadmapObjects.first { $0.type.isEnding })
            XCTAssertEqual(ending.startMeasureID, ids.first, style.rawValue)
            XCTAssertEqual(ending.endMeasureID, ids.last, style.rawValue)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source,
                current: try PKDrawing(data: XCTUnwrap(ending.sourceInkData))), style.rawValue)
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testDuplicateExistingEndingKeepsOriginalReceiptAndCurrentPageInk() throws {
        var chart = Chart.blank(title: "Duplicate", measureCount: 2, layoutStyle: .simpleChordSheet)
        let ids = chart.measures.map(\.id)
        let id = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1],
            displayText: "On cue", endStyle: .open))
        chart.roadmapObjects[0].sourceInkData = Data([7, 8, 9])
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "On cue", style: .open)
        let before = chart
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(result.renderedEndingCount, 0)
        XCTAssertFalse(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart, before)
        XCTAssertEqual(chart.roadmapObject(id: id)?.sourceInkData, Data([7, 8, 9]))
    }

    func testRoofFarPastLeadMeasureCannotClampToItsTrailingBoundary() throws {
        var chart = Chart.blank(title: "Ending overhang", measureCount: 1, layoutStyle: .leadSheet)
        let lastID = try XCTUnwrap(chart.measures.last?.id)
        XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse("Ab"), rawInput: "Ab",
            to: lastID, atFraction: 0.2))
        let fixture = try fixture(chart)
        let last = try XCTUnwrap(fixture.system.measures.first { $0.sourceMeasureID == lastID })
        let display = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(last, in: fixture.system,
            paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: .leadSheet)
        XCTAssertGreaterThan(fixture.lane.maxX - display.frame.maxX, 16)
        var state = try install(bracket(fixture: fixture, right: fixture.lane.maxX - 1),
            in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "On cue", style: .open)
        XCTAssertNil(chart.draftEndingMeasureRange(for: try XCTUnwrap(state.draftEndings.first), state: state))
        let before = chart
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(result.renderedEndingCount, 0)
        XCTAssertEqual(result.unresolvedDraftIDs, state.draftEndings.map(\.id))
        XCTAssertEqual(chart, before)
    }

    @MainActor
    func testChangedSourceCannotReuseReviewedEndingAndLivePrepareRollsBack() async throws {
        var chart = Chart.blank(title: "Fresh source", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "1, 4", style: .closed)
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let changed = PKDrawing(strokes: source.strokes + [stroke([CGPoint(x: 12, y: 100)])])
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: changed, coordinateSpace: chart.pageHandwrittenChordCoordinateSpace)
        XCTAssertFalse(outcome.canConsumeSource)
        XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(outcome.chart, chart)
    }

    @MainActor
    func testSameGeometryWithNewChronologyCannotReuseLabelApproval() async throws {
        var chart = Chart.blank(title: "New source path", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try fixture(chart)
        var state = try install(bracket(fixture: fixture), in: &chart, fixture: fixture)
        try review(&state, chart: chart, label: "On cue", style: .open)
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let changed = PKDrawing(strokes: source.strokes.map { original in
            PKStroke(ink: original.ink,
                path: PKStrokePath(controlPoints: original.path.map { $0 },
                    creationDate: original.path.creationDate.addingTimeInterval(1)), transform: original.transform)
        })
        XCTAssertEqual(PencilKitInkAdapter.inkStrokes(from: changed), PencilKitInkAdapter.inkStrokes(from: source))
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
            currentDrawing: changed, coordinateSpace: chart.pageHandwrittenChordCoordinateSpace)
        XCTAssertFalse(outcome.canConsumeSource)
        XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(outcome.chart, chart)
    }

    private struct Fixture {
        var layout: LeadSheetPageLayout
        var system: LeadSheetSystemLayout
        var chordFrame: CGRect
        var lane: CGRect
    }

    private func fixture(_ chart: Chart, systemIndex: Int = 0) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400), includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first { $0.index == systemIndex })
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        return Fixture(layout: layout, system: system, chordFrame: frame,
            lane: try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
                paperFrame: layout.paperFrame(for: system))))
    }

    private func install(_ drawing: PKDrawing, in chart: inout Chart, fixture: Fixture) throws -> ChordPreviewState {
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let stored = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.structuralVisibleDrawingContext(from: stored,
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let strokes = PencilKitInkAdapter.inkStrokes(from: context.drawing)
        let endings = ChordDraftEndingRecognizer.recognize(strokes: strokes,
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        let bars = ChordDraftEndingRecognizer.recognizeBarlinesExcludingEndings(strokes: strokes,
            chordFrame: fixture.chordFrame, pageLayout: fixture.layout)
        var state = ChordPreviewState()
        state.replaceDraftEndings(with: context.remappedEndingRecognition(
            context.endingRecognitionWithUnambiguousSourceStrokes(endings)).endings)
        state.replaceDraftBarlines(with: context.remappedBarlineRecognition(
            context.barlineRecognitionWithUnambiguousSourceStrokes(bars)).barlines)
        state.layoutPageSize = fixture.layout.pageBounds.size
        XCTAssertEqual(state.draftEndings.count, 1)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return state
    }

    private func bracket(fixture: Fixture, left: CGFloat? = nil, right: CGFloat? = nil) -> PKDrawing {
        let measures = fixture.system.measures
        let first = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measures[0], in: fixture.system,
            paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: fixture.system.layoutStyle)
        let last = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measures[measures.count - 1], in: fixture.system,
            paperFrame: fixture.layout.paperFrame(for: fixture.system), layoutStyle: fixture.system.layoutStyle)
        let firstFrame = fixture.system.layoutStyle == .rhythmSectionSheet ? first.staffFrame : first.frame
        let lastFrame = fixture.system.layoutStyle == .rhythmSectionSheet ? last.staffFrame : last.frame
        let x0 = (left ?? firstFrame.minX + 1) - fixture.chordFrame.minX
        let x1 = (right ?? lastFrame.maxX - 1) - fixture.chordFrame.minX
        let top = fixture.lane.minY + fixture.lane.height * 0.10 - fixture.chordFrame.minY
        let hook = fixture.lane.height * 0.22
        let roof = stroke([CGPoint(x: x0, y: top + hook), CGPoint(x: x0, y: top),
            CGPoint(x: x1, y: top), CGPoint(x: x1, y: top + hook)])
        let label = stroke([CGPoint(x: x0 + 16, y: top + hook * 0.6),
            CGPoint(x: x0 + 16, y: top + hook * 1.25)])
        return PKDrawing(strokes: [roof, label])
    }

    private func barline(x: CGFloat, fixture: Fixture) -> PKStroke {
        stroke([CGPoint(x: x - fixture.chordFrame.minX,
            y: fixture.lane.minY + fixture.lane.height * 0.04 - fixture.chordFrame.minY),
            CGPoint(x: x - fixture.chordFrame.minX,
            y: fixture.lane.maxY - fixture.lane.height * 0.04 - fixture.chordFrame.minY)])
    }

    private func review(_ state: inout ChordPreviewState, chart: Chart, label: String, style: EndingEndStyle) throws {
        let drawing = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        for index in state.draftEndings.indices {
            state.draftEndings[index].label = label
            state.draftEndings[index].endStyle = style
            state.draftEndings[index].isReviewed = true
            state.draftEndings[index].reviewedSourceInkData = PKDrawing(strokes:
                state.draftEndings[index].sourceStrokeIndices.sorted().map { drawing.strokes[$0] }).dataRepresentation()
        }
    }

    private func draftChart() -> Chart {
        var chart = Chart.draft(title: "Draft ending", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }

    private func stroke(_ points: [CGPoint]) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints:
            points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}
#endif
