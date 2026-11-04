#if canImport(UIKit)
import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class CommittedRhythmSplitLayoutTests: XCTestCase {
    func testCommittedSplitPreservesUnrelatedEqualRowIntentAcrossRotationAndReopen() throws {
        try assertUnrelatedRowPreserved(equalized: true)
    }

    func testCommittedSplitPreservesUnrelatedAutomaticRowAcrossRotationAndReopen() throws {
        try assertUnrelatedRowPreserved(equalized: false)
    }

    func testTwoCommittedDividersPartitionOriginalRhythmSlotsBeforePadding() throws {
        var chart = Chart.blank(title: "Two timed dividers", measureCount: 1,
            layoutStyle: .rhythmSectionSheet)
        let id = chart.measures[0].id
        chart.systems[0].measures[0].rhythmMap = MeasureRhythmMap(
            values: [.quarter, .quarter, .quarter, .quarter])
        let notes = (0..<4).map { LeadSheetPitchedNoteEvent(rhythmSlotIndex: $0,
            staffPosition: LeadSheetStaffPosition(staffStep: $0)) }
        chart.systems[0].measures[0].pitchedNoteEvents = notes
        let size = CGSize(width: 900, height: 1_400)
        var state = ChordPreviewState(layoutPageSize: size)
        state.replaceDraftBarlines(with: [0.25, 0.75].map { fraction in
            DraftBarline(measureID: id, measureIndex: 1, fraction: fraction,
                layoutPageSize: size, metrics: DraftBarlineGestureMetrics(height: 54, width: 2,
                    angleDegreesFromVertical: 1, straightness: 0.98, laneCoverage: 0.9))
        })

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 3)
        guard chart.measures.count == 3 else { return }
        XCTAssertEqual(chart.measures[0].pitchedNoteEvents.map(\.id), [notes[0].id])
        XCTAssertEqual(chart.measures[1].pitchedNoteEvents.map(\.id), [notes[1].id, notes[2].id])
        XCTAssertEqual(chart.measures[2].pitchedNoteEvents.map(\.id), [notes[3].id])
        XCTAssertEqual(chart.measures[0].pitchedNoteEvents.map(\.rhythmSlotIndex), [0])
        XCTAssertEqual(chart.measures[1].pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 1])
        XCTAssertEqual(chart.measures[2].pitchedNoteEvents.map(\.rhythmSlotIndex), [0])
        XCTAssertEqual(chart.measures.flatMap(\.pitchedNoteEvents).map(\.id), notes.map(\.id))
        XCTAssertTrue(chart.measures.allSatisfy { $0.rhythmMap?.fitsExactly(in: chart.defaultMeter) == true })
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
        XCTAssertEqual(reopened, chart)
    }

    func testEqualRowAfterCommittedSplitUsesEveryPhysicalMeasureAcrossRotationAndReopen() throws {
        let fixture = try splitChartForExplicitLayoutEdit()
        var chart = fixture.chart
        let firstRowIDs = Array(chart.measures.prefix(5)).map(\.id)
        XCTAssertEqual(chart.measure(id: fixture.leftID)?.rhythmSectionSplitLayoutSource?.groupID,
            chart.measure(id: fixture.rightID)?.rhythmSectionSplitLayoutSource?.groupID)
        XCTAssertNotNil(chart.measure(id: fixture.leftID)?.rhythmSectionSplitLayoutSource)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_400))
        let sourceRow = try XCTUnwrap(sourceLayout.systems.first)
        let equalized = LeadSheetRhythmSectionRowEqualizationPolicy.manualLayoutWidths(
            for: sourceRow, in: sourceLayout, chart: chart)
        XCTAssertEqual(Set(equalized.keys), Set(firstRowIDs))
        for (id, width) in equalized {
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(width, for: id))
        }
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
        XCTAssertTrue(firstRowIDs.allSatisfy { reopened.measure(id: $0)?.rhythmSectionSplitLayoutSource == nil })
        XCTAssertTrue(firstRowIDs.allSatisfy { reopened.measure(id: $0)?.usesDrawnRhythmTailWidth == false })
        for size in [CGSize(width: 900, height: 1_400), CGSize(width: 1_400, height: 900)] {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: size)
            let firstRow = try XCTUnwrap(layout.systems.first)
            XCTAssertEqual(firstRow.measures.compactMap(\.sourceMeasureID), firstRowIDs)
            let physicalWidth = try XCTUnwrap(firstRow.measures.first?.staffFrame.width)
            for measure in firstRow.measures {
                XCTAssertEqual(measure.staffFrame.width, physicalWidth, accuracy: 0.01)
            }
            // The next automatic row derives its default from five independent
            // measures, rather than collapsing the former sibling pair to one.
            let later = try XCTUnwrap(layout.systems.flatMap(\.measures).first {
                $0.sourceMeasureID == fixture.untouchedID
            })
            XCTAssertEqual(later.staffFrame.width, physicalWidth, accuracy: 0.01)
        }
    }

    func testExplicitResizeAndResetRetireWholeSplitGroupAndKeepSiblingWidths() throws {
        for reset in [false, true] {
            let fixture = try splitChartForExplicitLayoutEdit()
            var chart = fixture.chart
            let sibling = try XCTUnwrap(chart.measure(id: fixture.rightID))
            let unrelatedGroupID = try XCTUnwrap(chart.measures[2].rhythmSectionSplitLayoutSource?.groupID)
            _ = chart.setMeasureManualLayoutWidth(reset ? nil : 210, for: fixture.leftID)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            XCTAssertNil(reopened.measure(id: fixture.leftID)?.rhythmSectionSplitLayoutSource)
            XCTAssertNil(reopened.measure(id: fixture.rightID)?.rhythmSectionSplitLayoutSource)
            XCTAssertEqual(reopened.measure(id: fixture.rightID)?.manualLayoutWidth, sibling.manualLayoutWidth)
            XCTAssertEqual(reopened.measure(id: fixture.rightID)?.usesDrawnRhythmTailWidth, sibling.usesDrawnRhythmTailWidth)
            XCTAssertEqual(reopened.measures[2].rhythmSectionSplitLayoutSource?.groupID, unrelatedGroupID)
            XCTAssertEqual(reopened.measure(id: fixture.leftID)?.manualLayoutWidth, reset ? nil : 210)
            XCTAssertEqual(reopened.measure(id: fixture.leftID)?.usesDrawnRhythmTailWidth, false)
        }

        // Old saved states can carry lineage after their drawn-width flag was
        // cleared. Reapplying the same explicit width still retires the group.
        var chart = Chart.blank(title: "Same explicit width", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let leftID = chart.measures[0].id
        _ = chart.setMeasureManualLayoutWidth(400, for: leftID)
        let rightID = try XCTUnwrap(chart.splitCommittedRhythmSectionMeasure(leftID, atFraction: 0.5))
        chart.systems[0].measures[0].usesDrawnRhythmTailWidth = false
        XCTAssertEqual(chart.setMeasureManualLayoutWidth(200, for: leftID), 200)
        XCTAssertNil(chart.measure(id: leftID)?.rhythmSectionSplitLayoutSource)
        XCTAssertNil(chart.measure(id: rightID)?.rhythmSectionSplitLayoutSource)
    }

    private func splitChartForExplicitLayoutEdit() throws -> (chart: Chart, leftID: UUID, rightID: UUID, untouchedID: UUID) {
        var chart = Chart.blank(title: "Explicit layout after divider", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let ids = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: ids[4]))
        var state = ChordPreviewState(layoutPageSize: CGSize(width: 900, height: 1_400))
        state.replaceDraftBarlines(with: [DraftBarline(measureID: ids[0], measureIndex: 1, fraction: 0.5,
            layoutPageSize: state.layoutPageSize, metrics: DraftBarlineGestureMetrics(height: 54, width: 2,
                angleDegreesFromVertical: 1, straightness: 0.98, laneCoverage: 0.9))])
        XCTAssertEqual(chart.commitChordInkDraftBatch(state).renderedBarlineCount, 1)
        XCTAssertEqual(chart.measures.count, 9)
        return (chart, ids[0], chart.measures[1].id, ids[4])
    }

    private func assertUnrelatedRowPreserved(equalized: Bool) throws {
        var chart = Chart.blank(title: "Committed split row preservation", measureCount: 8,
            layoutStyle: .rhythmSectionSheet)
        let originalIDs = chart.measures.map(\.id)
        let untouchedIDs = Array(originalIDs.suffix(4))
        XCTAssertTrue(chart.insertSystemBreak(before: untouchedIDs[0]))
        if equalized {
            for id in originalIDs { XCTAssertNotNil(chart.setMeasureManualLayoutWidth(140, for: id)) }
        }
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C"),
            rawInput: "C", to: originalIDs[0], atFraction: 0.1))
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("G7"),
            rawInput: "G7", to: originalIDs[0], atFraction: 0.8))
        let baseline = chart
        let portrait = CGSize(width: 900, height: 1_400)
        let source = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: portrait,
            includesChordInkContinuationLanes: true)
        let row = try XCTUnwrap(source.systems.first)
        let first = try XCTUnwrap(row.measures.first { $0.sourceMeasureID == originalIDs[0] })
        XCTAssertEqual(row.measures.compactMap(\.sourceMeasureID), Array(originalIDs.prefix(4)))
        XCTAssertEqual(first.chordLayouts.count, 2)
        let left = first.chordLayouts[0].frame
        let right = first.chordLayouts[1].frame
        let cutX = (left.maxX + right.minX) / 2
        let fraction = Double((cutX - first.staffFrame.minX) / first.staffFrame.width)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: row, paperFrame: source.paperFrame(for: row)))
        let barline = DraftBarline(measureID: originalIDs[0], measureIndex: 1, fraction: fraction,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: row.index,
                fraction: Double((cutX - lane.minX) / lane.width)), layoutPageSize: portrait,
            metrics: DraftBarlineGestureMetrics(height: 54, width: 2,
                angleDegreesFromVertical: 1, straightness: 0.98, laneCoverage: 0.9))
        var state = ChordPreviewState(layoutPageSize: portrait)
        state.replaceDraftBarlines(with: [barline])
        let result = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, baseline.measures.count + 1)
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))

        for id in untouchedIDs {
            let before = try XCTUnwrap(baseline.measure(id: id))
            let after = try XCTUnwrap(reopened.measure(id: id))
            XCTAssertEqual(after.manualLayoutWidth, before.manualLayoutWidth,
                "A divider in another row must preserve this row's stored width intent")
            XCTAssertEqual(after.usesDrawnRhythmTailWidth, before.usesDrawnRhythmTailWidth)
        }
        for size in [portrait, CGSize(width: 1_400, height: 900)] {
            let expected = LeadSheetPageLayoutEngine.pageLayout(for: baseline, pageSize: size,
                includesChordInkContinuationLanes: true)
            let actual = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: size,
                includesChordInkContinuationLanes: true)
            for id in untouchedIDs {
                let before = try XCTUnwrap(expected.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
                let after = try XCTUnwrap(actual.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
                assertFrame(after.frame, matches: before.frame, id: id, size: size)
                assertFrame(after.staffFrame, matches: before.staffFrame, id: id, size: size)
                assertFrame(after.chordWritingFrame, matches: before.chordWritingFrame, id: id, size: size)
            }
        }
    }

    private func assertFrame(_ actual: CGRect, matches expected: CGRect, id: UUID, size: CGSize) {
        let context = "Unrelated measure \(id) at \(size)"
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01, context)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01, context)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, context)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, context)
    }
}
#endif
