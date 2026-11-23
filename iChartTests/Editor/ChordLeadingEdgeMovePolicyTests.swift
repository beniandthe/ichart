#if canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordLeadingEdgeMovePolicyTests: XCTestCase {
    func testOffCenterLeadingEdgePreviewKeepsMeasureUntilItsPhysicalBoundaryIsCrossed() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try fixture(style: style)
            let page = layout(fixture.chart)
            let measure = try measure(fixture.measureID, in: page)
            let chord = try XCTUnwrap(measure.chordLayouts.first { $0.id == fixture.chordID })
            let guideX = LeadSheetChordPlacementGuidePolicy.guideFrame(
                for: measure, referenceFrame: measure.chordBandFrame).minX
            let previousID = fixture.chart.measures[0].id
            XCTAssertGreaterThan(chord.frame.minX, guideX + 6)

            for grabOffset in [CGFloat(1), chord.frame.width - 1] {
                let start = CGPoint(x: chord.frame.minX + grabOffset, y: chord.frame.midY)
                var drag = ActiveChordMoveDrag(chordID: fixture.chordID, sourcePageLayout: page,
                    initialFrame: chord.frame, currentFrame: chord.frame, startLocation: start)

                let guidePoint = CGPoint(x: guideX + 0.5 + grabOffset, y: start.y)
                let guidePreview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
                    at: guidePoint, for: drag, chart: fixture.chart))
                XCTAssertEqual(guidePreview.measureID, fixture.measureID)
                XCTAssertEqual(guidePreview.targetX, guideX, accuracy: 0.0001)
                XCTAssertEqual(try XCTUnwrap(guidePreview.activeGuideX), guideX, accuracy: 0.0001)
                drag.currentPositionPreview = guidePreview

                let leadingPoint = CGPoint(x: measure.chordBandFrame.minX + 1 + grabOffset, y: start.y)
                let leadingPreview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
                    at: leadingPoint, for: drag, chart: fixture.chart))
                XCTAssertEqual(leadingPreview.measureID, fixture.measureID)
                XCTAssertEqual(leadingPreview.targetX, measure.chordBandFrame.minX + 1, accuracy: 0.0001)
                XCTAssertLessThan(leadingPreview.targetX, guideX)
                XCTAssertNil(leadingPreview.activeGuideX)
                drag.currentPositionPreview = leadingPreview

                let physicalBoundary = CGPoint(x: measure.staffFrame.minX + grabOffset, y: start.y)
                let boundaryPreview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
                    at: physicalBoundary, for: drag, chart: fixture.chart))
                XCTAssertEqual(boundaryPreview.measureID, fixture.measureID,
                    "The exact physical barline still belongs to the measure on its right")
                XCTAssertEqual(boundaryPreview.targetX, measure.chordBandFrame.minX, accuracy: 0.0001)
                drag.currentPositionPreview = boundaryPreview

                let crossedBoundary = CGPoint(x: measure.staffFrame.minX - 0.25 + grabOffset, y: start.y)
                let crossedPreview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
                    at: crossedBoundary, for: drag, chart: fixture.chart))
                XCTAssertEqual(crossedPreview.measureID, previousID,
                    "Only crossing the physical boundary transfers the chord to the previous measure")
            }
        }
    }

    func testCommitFromLaterBeatIntoPreGuideSpaceStoresDownbeatAndPreciseVisualPosition() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var fixture = try fixture(style: style)
            let original = fixture.chart
            let eventBefore = try XCTUnwrap(original.chordEvent(id: fixture.chordID))
            XCTAssertEqual(eventBefore.startPosition.beat, 3)
            let page = layout(original)
            let measure = try measure(fixture.measureID, in: page)
            let chord = try XCTUnwrap(measure.chordLayouts.first { $0.id == fixture.chordID })
            let start = CGPoint(x: chord.frame.maxX - 1, y: chord.frame.midY)
            let grabOffset = start.x - chord.frame.minX
            let desiredX = measure.chordBandFrame.minX + 1.375
            let destination = CGPoint(x: desiredX + grabOffset, y: start.y)
            var drag = ActiveChordMoveDrag(chordID: fixture.chordID, sourcePageLayout: page,
                initialFrame: chord.frame, currentFrame: chord.frame, startLocation: start)
            let preview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
                at: destination, for: drag, chart: original))
            XCTAssertEqual(preview.measureID, fixture.measureID)
            XCTAssertEqual(preview.targetX, desiredX, accuracy: 0.0001)
            XCTAssertLessThan(preview.targetX, preview.guideFrame.minX)
            XCTAssertNil(preview.activeGuideX)
            drag.currentPositionPreview = preview

            XCTAssertTrue(LeadSheetChordMoveDragPolicy.commit(drag, at: destination, in: &fixture.chart))

            let moved = try XCTUnwrap(fixture.chart.chordEvent(id: fixture.chordID))
            XCTAssertEqual(moved.startPosition.beat, 1)
            XCTAssertEqual(moved.startPosition.subdivision, 0)
            XCTAssertEqual(try XCTUnwrap(moved.manualVisualLaneFraction), preview.targetFraction, accuracy: 0.000001)
            XCTAssertEqual(moved.manualVisualAllowsLeadingInset, true)
            XCTAssertGreaterThan(try XCTUnwrap(moved.manualVisualLaneFraction), 0,
                "The exact visual offset is independent of its beat-one musical position")
            assertReceipt(moved, matches: eventBefore)
            XCTAssertEqual(fixture.chart.measureContainingChordEvent(id: fixture.chordID)?.id, fixture.measureID)
            XCTAssertEqual(fixture.chart.measures.map(\.id), original.measures.map(\.id))
            XCTAssertEqual(fixture.chart.measures[0], original.measures[0])
            XCTAssertEqual(fixture.chart.measures[2], original.measures[2])
            try assertReopenedPosition(fixture.chart, chordID: fixture.chordID,
                measureID: fixture.measureID, expectedX: preview.targetX)
        }
    }

    func testCrowdedSimpleCommitMovesLaterChordFirstWithoutRewritingOtherEvents() throws {
        var fixture = try fixture(style: .simpleChordSheet, crowded: true)
        let original = fixture.chart
        let targetBefore = try XCTUnwrap(original.measure(id: fixture.measureID))
        let untouched = targetBefore.chordEvents.filter { $0.id != fixture.chordID }
        XCTAssertEqual(targetBefore.chordEvents.count, 3)
        XCTAssertNotEqual(targetBefore.chordEvents.first?.id, fixture.chordID)
        let movedBefore = try XCTUnwrap(original.chordEvent(id: fixture.chordID))
        let page = layout(original)
        let measure = try measure(fixture.measureID, in: page)
        let chord = try XCTUnwrap(measure.chordLayouts.first { $0.id == fixture.chordID })
        let start = CGPoint(x: chord.frame.minX + 1, y: chord.frame.midY)
        let destination = CGPoint(x: measure.chordBandFrame.minX + 0.75 + 1, y: start.y)
        var drag = ActiveChordMoveDrag(chordID: fixture.chordID, sourcePageLayout: page,
            initialFrame: chord.frame, currentFrame: chord.frame, startLocation: start)
        let preview = try XCTUnwrap(LeadSheetChordMoveDragPolicy.positionPreview(
            at: destination, for: drag, chart: original))
        XCTAssertEqual(preview.measureID, fixture.measureID)
        XCTAssertLessThan(preview.targetX, preview.guideFrame.minX)
        drag.currentPositionPreview = preview

        XCTAssertTrue(LeadSheetChordMoveDragPolicy.commit(drag, at: destination, in: &fixture.chart))

        let targetAfter = try XCTUnwrap(fixture.chart.measure(id: fixture.measureID))
        let moved = try XCTUnwrap(targetAfter.chordEvents.first)
        XCTAssertEqual(moved.id, fixture.chordID)
        XCTAssertEqual(moved.startPosition.beat, 1)
        XCTAssertEqual(moved.startPosition.subdivision, 0)
        XCTAssertEqual(moved.manualLaneFraction, 0,
            "The musical lane position is beat one, rather than the original later beat")
        XCTAssertEqual(try XCTUnwrap(moved.manualVisualLaneFraction), preview.targetFraction, accuracy: 0.000001)
        XCTAssertEqual(moved.manualVisualAllowsLeadingInset, true)
        XCTAssertEqual(Array(targetAfter.chordEvents.dropFirst()), untouched,
            "Sorting the moved chord first must preserve every neighboring event field and ID")
        assertReceipt(moved, matches: movedBefore)
        XCTAssertEqual(fixture.chart.measures[0], original.measures[0])
        XCTAssertEqual(fixture.chart.measures[2], original.measures[2])
        try assertReopenedPosition(fixture.chart, chordID: fixture.chordID,
            measureID: fixture.measureID, expectedX: preview.targetX)
    }

    private func fixture(style: ChartLayoutStyle, crowded: Bool = false)
        throws -> (chart: Chart, measureID: UUID, chordID: UUID) {
        var chart = Chart.blank(title: "Leading edge move", measureCount: 3, layoutStyle: style)
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                chart.systems[systemIndex].measures[measureIndex].authoringState = .committed
            }
        }
        let moved = try event("G7", beat: 3, fraction: 0.5)
        var events = [moved]
        if crowded {
            var first = try event("C7", beat: 1, fraction: 0)
            first.manualVisualLaneFraction = 0.15
            events = [first, moved, try event("F7", beat: 4, fraction: 0.75)]
        }
        chart.systems[0].measures[0].chordEvents = [try event("Bb7", beat: 1, fraction: 0.2)]
        chart.systems[0].measures[1].chordEvents = events
        chart.systems[0].measures[2].chordEvents = [try event("Eb7", beat: 1, fraction: 0.2)]
        return (chart, chart.measures[1].id, moved.id)
    }

    private func event(_ text: String, beat: Int, fraction: Double) throws -> ChordEvent {
        ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: beat, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .quarter, rhythmPlacement: .inline, tieOut: false, hitStyle: .accent,
            rawInput: text, sourceInkData: drawing().dataRepresentation(),
            sourceCandidateSignature: [text], sourceRecognitionPipelineVersion: "leading-edge-policy-test",
            manualHorizontalScale: 0.85, manualLaneFraction: fraction, manualVisualLaneFraction: fraction)
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 14, y: 2), CGPoint(x: 18, y: 10)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 200))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor), path: path)])
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 1180, height: 1400))
    }

    private func measure(_ id: UUID, in page: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func assertReceipt(_ actual: ChordEvent, matches original: ChordEvent,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.symbol, original.symbol, file: file, line: line)
        XCTAssertEqual(actual.sourceInkData, original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.sourceCandidateSignature, original.sourceCandidateSignature, file: file, line: line)
        XCTAssertEqual(actual.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion, file: file, line: line)
        XCTAssertEqual(actual.rawInput, original.rawInput, file: file, line: line)
        XCTAssertEqual(actual.spellingIntent, original.spellingIntent, file: file, line: line)
        XCTAssertEqual(actual.spellingOverrideSource, original.spellingOverrideSource, file: file, line: line)
        XCTAssertEqual(actual.manualHorizontalScale, original.manualHorizontalScale, file: file, line: line)
        XCTAssertEqual(actual.tieOut, original.tieOut, file: file, line: line)
        XCTAssertEqual(actual.hitStyle, original.hitStyle, file: file, line: line)
    }

    private func assertReopenedPosition(_ chart: Chart, chordID: UUID, measureID: UUID, expectedX: CGFloat,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        XCTAssertEqual(reopened, chart, file: file, line: line)
        let displayed = try measure(measureID, in: layout(reopened))
        let chord = try XCTUnwrap(displayed.chordLayouts.first { $0.id == chordID }, file: file, line: line)
        XCTAssertEqual(chord.frame.minX, expectedX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(chord.fitFrame.minX, expectedX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(reopened.chordEvent(id: chordID)?.startPosition.beat, 1, file: file, line: line)
    }
}
#endif
