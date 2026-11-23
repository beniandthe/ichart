#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Shared projection/commit coverage. Mounted gesture routing and physical
/// Pencil acceptance are verified separately from this policy test lane.
@MainActor
final class CueTextDragProjectionTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let positions: [CuePosition] = [.above, .below]

    func testLeftCenterAndRightGrabsProduceTheSameSnappedCuePlacement() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.25)
                let source = try cue(fixture.cueID, in: fixture.layout)
                let measure = try measure(fixture.measureIDs[0], in: fixture.layout)
                let delta = CGPoint(x: measure.staffFrame.width * 0.26, y: 8)
                for screenScale: CGFloat in [0.5, 1, 2.5] {
                    var referenceFrame: CGRect?
                    var referenceFraction: Double?
                    for grabFraction: CGFloat in [0.05, 0.5, 0.95] {
                        let start = CGPoint(x: source.frame.minX + source.frame.width * grabFraction,
                            y: source.frame.midY)
                        var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                            chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start,
                            screenPointsPerDisplayedPoint: screenScale))
                        LeadSheetCueTextMoveDragPolicy.update(&drag,
                            at: CGPoint(x: start.x + delta.x, y: start.y + delta.y))
                        let projection = try XCTUnwrap(drag.currentProjection)
                        XCTAssertEqual(projection.measureID, fixture.measureIDs[0])
                        XCTAssertEqual(projection.cueLayout.position, position)
                        if let referenceFrame {
                            assertEqual(projection.cueLayout.frame, referenceFrame)
                            XCTAssertEqual(projection.fraction, referenceFraction)
                        } else {
                            referenceFrame = projection.cueLayout.frame
                            referenceFraction = projection.fraction
                        }
                        try assertCommitAndReopenMatch(drag, fixture: fixture)
                    }
                }
            }
        }
    }

    func testSnappedPlacementUsesTheCueAnchorAndKeepsTextInsideStaffMargins() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.5)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let measure = try measure(fixture.measureIDs[0], in: fixture.layout)
                for requestedFraction: CGFloat in [0.001, 0.27, 0.999] {
                    let requestedLeft = measure.staffFrame.minX + measure.staffFrame.width * requestedFraction
                    let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                    var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                        chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                    LeadSheetCueTextMoveDragPolicy.update(&drag,
                        at: CGPoint(x: start.x + requestedLeft - original.frame.minX, y: start.y))
                    let projection = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(projection.measureID, fixture.measureIDs[0])
                    let expectedFraction = MeasurePlacementGrid.snappedFraction(Double(requestedFraction),
                        in: fixture.chart.defaultMeter)
                    if projection.cueLayout.frame == original.frame {
                        XCTAssertEqual(projection.fraction, fixture.chart.cueText(id: fixture.cueID)?.beatFraction,
                            "A fully clamped no-op must not author an invisible horizontal change")
                    } else {
                        XCTAssertEqual(try XCTUnwrap(projection.fraction), expectedFraction, accuracy: 0.0001)
                    }
                    XCTAssertGreaterThanOrEqual(projection.cueLayout.frame.minX, measure.staffFrame.minX + 4 - 0.01)
                    XCTAssertLessThanOrEqual(projection.cueLayout.frame.maxX, measure.staffFrame.maxX - 4 + 0.01)
                    try assertCommitAndReopenMatch(drag, fixture: fixture)
                }
            }
        }
    }

    func testCrossMeasureAndCrossSystemDropsUseTheDestinationCueLane() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.25,
                    addsDestinationCue: true)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let sourceMeasure = try measure(fixture.measureIDs[0], in: fixture.layout)
                for targetIndex in [1, 4] {
                    let destination = try measure(fixture.measureIDs[targetIndex], in: fixture.layout)
                    let start = CGPoint(x: original.frame.maxX - 2, y: original.frame.midY)
                    let desiredLeft = deliberateDestinationX(in: destination, from: original.frame.minX,
                        meter: fixture.chart.measure(id: fixture.measureIDs[targetIndex])!
                            .resolvedMeter(defaultMeter: fixture.chart.defaultMeter))
                    let systemDeltaY = destination.staffFrame.minY - sourceMeasure.staffFrame.minY
                    var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                        chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                    LeadSheetCueTextMoveDragPolicy.update(&drag,
                        at: CGPoint(x: start.x + desiredLeft - original.frame.minX,
                            y: start.y + systemDeltaY))
                    let projection = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(projection.measureID, fixture.measureIDs[targetIndex])
                    XCTAssertEqual(projection.cueLayout.position, position)
                    XCTAssertEqual(projection.cueLayout.verticalOffset, original.verticalOffsetFromDefault,
                        accuracy: 0.001,
                        "Moving to another system requests the visible displacement, not that system's page distance")
                    XCTAssertEqual(projection.verticalOffset, Double(projection.cueLayout.verticalOffsetFromDefault),
                        accuracy: 0.001, "Only the achieved boundary-constrained displacement is committed")
                    try assertCommitAndReopenMatch(drag, fixture: fixture)
                }
            }
        }
    }

    func testNoMotionReturningToStartAndDiscardedPreviewLeaveTheChartAndInkUntouched() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: nil)
                let before = try encoded(fixture.chart)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                    chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                var chart = fixture.chart
                LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
                XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart))
                XCTAssertEqual(try encoded(chart), before)
                XCTAssertNil(chart.cueText(id: fixture.cueID)?.beatFraction,
                    "Touching an unpositioned cue must not author a new beat-zero position")

                LeadSheetCueTextMoveDragPolicy.update(&drag,
                    at: CGPoint(x: start.x + 35, y: start.y + 10))
                XCTAssertNotNil(drag.currentProjection)
                XCTAssertEqual(try encoded(chart), before,
                    "Discarding a preview is cancellation; projection must not mutate the chart or its source ink")
                LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
                XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart),
                    "Returning to the touchdown point must not commit an earlier cached projection")
                XCTAssertEqual(try encoded(chart), before)
            }
        }
    }

    func testVerticalMovementFarPastOtherRowsPreservesItsMeasureAndBeatWithPencilJitter() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.25,
                    addsDestinationCue: true)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let originalCue = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID))
                let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                for screenScale: CGFloat in [0.5, 1, 2.5] {
                    for horizontalScreenTravel: CGFloat in [-1.9, 0, 1.9] {
                        for direction: CGFloat in [-1, 1] {
                            var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                                chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize,
                                startLocation: start, screenPointsPerDisplayedPoint: screenScale))
                            LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(
                                x: start.x + horizontalScreenTravel / screenScale,
                                y: start.y + direction * fixture.layout.pageBounds.height * 2))
                            let preview = try XCTUnwrap(drag.currentProjection)
                            XCTAssertEqual(preview.measureID, originalCue.anchorMeasureID)
                            XCTAssertEqual(preview.fraction, originalCue.beatFraction)
                            XCTAssertEqual(preview.cueLayout.frame.minX, original.frame.minX, accuracy: 0.001)
                            XCTAssertEqual(drag.pageLayoutProjectionCount, 0,
                                "Vertical travel cannot become a row move or trigger document packing")
                            LeadSheetCueTextMoveDragPolicy.finish(&drag)
                            XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                            try assertCommitAndReopenMatch(drag, fixture: fixture)
                            var chart = fixture.chart
                            _ = LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart)
                            XCTAssertEqual(chart.cueText(id: fixture.cueID)?.anchorMeasureID, originalCue.anchorMeasureID)
                            XCTAssertEqual(chart.cueText(id: fixture.cueID)?.beatFraction, originalCue.beatFraction)
                            let actual = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                            XCTAssertEqual(actual.pages.map(\.frame), fixture.layout.pages.map(\.frame))
                            XCTAssertEqual(measureIDsByPage(actual), measureIDsByPage(fixture.layout))
                            XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.staffFrame),
                                fixture.layout.systems.flatMap(\.measures).map(\.staffFrame))
                        }
                    }
                }
            }
        }
    }

    func testSixtyRawSamplesWithinOneSnappedAnchorReuseTheBoundedLayoutCache() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.25)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let sourceMeasure = try measure(fixture.measureIDs[0], in: fixture.layout)
                let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                let horizontalMove = sourceMeasure.staffFrame.width * 0.25
                var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                    chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                LeadSheetCueTextMoveDragPolicy.update(&drag,
                    at: CGPoint(x: start.x + horizontalMove, y: start.y + 3))
                let anchor = try XCTUnwrap(drag.currentProjection)
                let pageProjectionCount = drag.pageLayoutProjectionCount
                for sample in 0..<60 {
                    let xJitter = CGFloat(sample % 5 - 2) * 0.2
                    let rawDY = CGFloat(sample % 13 - 6) * 0.75 + 3
                    LeadSheetCueTextMoveDragPolicy.update(&drag,
                        at: CGPoint(x: start.x + horizontalMove + xJitter, y: start.y + rawDY))
                    let projection = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(projection.measureID, anchor.measureID)
                    XCTAssertEqual(projection.fraction, anchor.fraction)
                    XCTAssertEqual(drag.pageLayoutProjectionCount, pageProjectionCount,
                        "Raw dy or sub-grid x changes must not repack the whole document per Pencil sample")
                    XCTAssertLessThanOrEqual(drag.anchorLayouts.count, 2)
                }
                XCTAssertLessThanOrEqual(drag.pageLayoutProjectionCount, 2)
                XCTAssertEqual(try encoded(drag.sourceChart), try encoded(fixture.chart))
            }
        }
    }

    func testHorizontalDraggingIgnoresResidualVerticalJitterWithinOneScreenPoint() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position, fraction: 0.25)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let sourceMeasure = try measure(fixture.measureIDs[0], in: fixture.layout)
                let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                for screenScale: CGFloat in [0.5, 1, 2.5] {
                    for jitter: CGFloat in [-0.9, -0.2, 0.2, 0.9] {
                        var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                            chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start,
                            screenPointsPerDisplayedPoint: screenScale))
                        LeadSheetCueTextMoveDragPolicy.update(&drag,
                            at: CGPoint(x: start.x + sourceMeasure.staffFrame.width * 0.25,
                                y: start.y + jitter / screenScale))
                        let projection = try XCTUnwrap(drag.currentProjection)
                        if projection.cueLayout.frame != original.frame {
                            XCTAssertEqual(projection.cueLayout.verticalOffset, original.verticalOffsetFromDefault,
                                accuracy: 0.001, "Horizontal jitter must not add a vertical request")
                            XCTAssertEqual(projection.verticalOffset, Double(projection.cueLayout.verticalOffsetFromDefault),
                                accuracy: 0.001)
                        }
                        try assertCommitAndReopenMatch(drag, fixture: fixture)
                    }
                }
            }
        }
    }

    func testVerticalDragPreservesAnExistingNonGridFraction() throws {
        for style in styles {
            for position in positions {
                let base = try fixture(style: style, position: position, fraction: 0.25)
                var chart = base.chart
                let cueIndex = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == base.cueID })
                chart.cueTexts[cueIndex].beatFraction = 0.137
                chart = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(chart))
                let fixture = Fixture(chart: chart,
                    layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                    cueID: base.cueID, measureIDs: base.measureIDs)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                    chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(x: start.x, y: start.y + 9))
                let projection = try XCTUnwrap(drag.currentProjection)
                XCTAssertEqual(projection.fraction, fixture.chart.cueText(id: fixture.cueID)?.beatFraction,
                    "A purely vertical adjustment must not quantize legacy horizontal placement")
                XCTAssertEqual(projection.cueLayout.frame.minX, original.frame.minX, accuracy: 0.001)
                try assertCommitAndReopenMatch(drag, fixture: fixture)
            }
        }
    }

    func testLargeVerticalMovesStayWithinSharedBoundariesWithoutRepackingOnRelease() throws {
        for style in styles {
            for position in positions {
                let base = try fixture(style: style, position: position, fraction: 0.25)
                var chart = base.chart
                chart.systems = [ChartSystem(id: chart.systems[0].id, index: 0,
                    spacingMode: .automatic, lineBreakRule: .forced, measures: [chart.measures[0]])]
                let fixture = Fixture(chart: chart,
                    layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                    cueID: base.cueID, measureIDs: [base.measureIDs[0]])
                let original = try cue(fixture.cueID, in: fixture.layout)
                let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                for dy: CGFloat in [-100, 100] {
                    var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                        chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                    LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(x: start.x, y: start.y + dy))
                    let preview = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(preview.measureID, fixture.measureIDs[0])
                    XCTAssertGreaterThanOrEqual(preview.cueLayout.verticalOffsetFromDefault,
                        CGFloat(CueText.minimumVerticalOffset))
                    XCTAssertLessThanOrEqual(preview.cueLayout.verticalOffsetFromDefault,
                        CGFloat(CueText.maximumVerticalOffset))
                    XCTAssertTrue(fixture.layout.paperFrame.contains(preview.cueLayout.frame))
                    let beforeFinishCount = drag.pageLayoutProjectionCount
                    LeadSheetCueTextMoveDragPolicy.finish(&drag)
                    XCTAssertEqual(drag.pageLayoutProjectionCount, beforeFinishCount,
                        "A same-anchor vertical release must not repack a document whose staves stay fixed")
                    let finished = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(finished.measureID, preview.measureID)
                    XCTAssertEqual(finished.fraction, preview.fraction)
                    XCTAssertEqual(finished.verticalOffset, preview.verticalOffset)
                    try assertCommitAndReopenMatch(drag, fixture: fixture)
                    var committed = fixture.chart
                    _ = LeadSheetCueTextMoveDragPolicy.commit(drag, in: &committed)
                    let actual = LeadSheetPageLayoutEngine.pageLayout(for: committed, pageSize: pageSize)
                    XCTAssertEqual(actual.pages.map(\.frame), fixture.layout.pages.map(\.frame))
                    XCTAssertEqual(measureIDsByPage(actual), measureIDsByPage(fixture.layout))
                    XCTAssertEqual(actual.systems.map(\.frame), fixture.layout.systems.map(\.frame))
                    XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.staffFrame),
                        fixture.layout.systems.flatMap(\.measures).map(\.staffFrame))
                }
            }
        }
    }

    func testMovingAcrossAnExplicitPageBreakKeepsThePhysicalPageSizeAndReopenedLayout() throws {
        for style in styles {
            for position in positions {
                let base = try fixture(style: style, position: position, fraction: 0.25)
                var chart = base.chart
                chart.systems[1].startsNewPage = true
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
                XCTAssertEqual(layout.pages.count, 2)
                XCTAssertGreaterThan(layout.pageBounds.height, pageSize.height,
                    "The scroll document must differ from the known physical page used for projection")
                let fixture = Fixture(chart: chart, layout: layout, cueID: base.cueID, measureIDs: base.measureIDs)
                let original = try cue(fixture.cueID, in: layout)
                let source = try measure(fixture.measureIDs[0], in: layout)
                let destination = try measure(fixture.measureIDs[4], in: layout)
                let start = CGPoint(x: original.frame.maxX - 2, y: original.frame.midY)
                let desiredLeft = deliberateDestinationX(in: destination, from: original.frame.minX,
                    meter: chart.measure(id: fixture.measureIDs[4])!.resolvedMeter(defaultMeter: chart.defaultMeter))
                var drag = try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID,
                    chart: fixture.chart, pageLayout: fixture.layout, pageSize: pageSize, startLocation: start))
                LeadSheetCueTextMoveDragPolicy.update(&drag,
                    at: CGPoint(x: start.x + desiredLeft - original.frame.minX,
                        y: start.y + destination.staffFrame.minY - source.staffFrame.minY))
                XCTAssertEqual(drag.currentProjection?.measureID, fixture.measureIDs[4])
                LeadSheetCueTextMoveDragPolicy.finish(&drag)
                let projection = try XCTUnwrap(drag.currentProjection)
                XCTAssertTrue(layout.pages[1].frame.contains(projection.cueLayout.frame),
                    "A second-page cue must stay on the second physical page, not a document-height page")
                try assertCommitAndReopenMatch(drag, fixture: fixture)

                var committed = fixture.chart
                XCTAssertTrue(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &committed))
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(committed))
                XCTAssertEqual(reopened.systems.map(\.startsNewPage), fixture.chart.systems.map(\.startsNewPage))
                let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
                XCTAssertEqual(finalLayout.pages.count, layout.pages.count)
                XCTAssertEqual(finalLayout.pages.map(\.frame), layout.pages.map(\.frame))
                assertEqual(try cue(fixture.cueID, in: finalLayout).frame, projection.cueLayout.frame)
            }
        }
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let cueID: UUID
        let measureIDs: [UUID]
    }

    private func deliberateDestinationX(in destination: LeadSheetMeasureLayout,
        from originalX: CGFloat, meter: Meter) -> CGFloat {
        var x = destination.staffFrame.minX + destination.staffFrame.width * 0.25
        if abs(x - originalX) <= 2 { x += 3 }
        XCTAssertGreaterThan(abs(x - originalX), 2,
            "A cross-row drop must express horizontal intent beyond Pencil jitter")
        let actualSlot = MeasurePlacementGrid.snappedFraction(Double(
            (x - destination.staffFrame.minX) / destination.staffFrame.width), in: meter)
        XCTAssertEqual(actualSlot, MeasurePlacementGrid.snappedFraction(0.25, in: meter), accuracy: 0.0001,
            "The deliberate x movement must remain inside the intended snapped slot")
        return x
    }

    private func fixture(style: ChartLayoutStyle, position: CuePosition,
        fraction: Double?, addsDestinationCue: Bool = false) throws -> Fixture {
        var chart = Chart.blank(title: "Cue projection", measureCount: 8, layoutStyle: style)
        chart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let originalMeasures = chart.measures
        chart.systems = [Array(originalMeasures.prefix(4)), Array(originalMeasures.dropFirst(4))]
            .enumerated().map { index, measures in
                ChartSystem(id: UUID(), index: index, spacingMode: .automatic,
                    lineBreakRule: .forced, measures: measures)
            }
        let measureIDs = chart.measures.map(\.id)
        for index in [0, 1, 4] {
            _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse(index == 0 ? "Cmaj7" : "G7"),
                rawInput: index == 0 ? "Cmaj7" : "G7", to: measureIDs[index], atFraction: 0.25))
        }
        let cueID = try XCTUnwrap(chart.addCueText("Horns enter", anchorMeasureID: measureIDs[0], position: position))
        if let fraction {
            XCTAssertTrue(chart.moveCueText(cueID, to: measureIDs[0], atFraction: fraction, verticalOffset: 12))
        }
        if addsDestinationCue {
            _ = try XCTUnwrap(chart.addCueText("On cue", anchorMeasureID: measureIDs[4], position: position))
        }

        let ink = try XCTUnwrap(LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: sourceDrawing()))
        chart.systems[0].measures[0].chordEvents[0].sourceInkData = ink
        chart.pageHandwrittenChordData = ink
        chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.pageHandwrittenNotationData = ink
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.systems[0].measures[0].handwrittenRhythmicNotationData = ink
        chart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 180, height: 80)
        chart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        XCTAssertGreaterThanOrEqual(layout.systems.count, 2)
        return Fixture(chart: chart, layout: layout, cueID: cueID, measureIDs: measureIDs)
    }

    private func assertCommitAndReopenMatch(_ drag: ActiveCueTextMoveDrag, fixture: Fixture,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let projection = try XCTUnwrap(drag.currentProjection, file: file, line: line)
        var chart = fixture.chart
        let didCommit = LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart)
        if !didCommit {
            XCTAssertEqual(try encoded(chart), try encoded(fixture.chart), file: file, line: line)
            assertEqual(projection.cueLayout.frame, drag.initialFrame, file: file, line: line)
            XCTAssertEqual(projection.measureID, drag.sourceCue.anchorMeasureID, file: file, line: line)
            XCTAssertEqual(projection.fraction, drag.sourceCue.beatFraction, file: file, line: line)
            XCTAssertEqual(projection.verticalOffset, drag.sourceCue.verticalOffset, file: file, line: line)
            return
        }
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        let after = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
        let rendered = try cue(fixture.cueID, in: after)
        assertEqual(rendered.frame, projection.cueLayout.frame, file: file, line: line)
        let moved = try XCTUnwrap(reopened.cueText(id: fixture.cueID), file: file, line: line)
        XCTAssertEqual(moved.anchorMeasureID, projection.measureID, file: file, line: line)
        if let expectedFraction = projection.fraction {
            XCTAssertEqual(try XCTUnwrap(moved.beatFraction, file: file, line: line),
                expectedFraction, accuracy: 1e-12, file: file, line: line)
        } else {
            XCTAssertNil(moved.beatFraction, file: file, line: line)
        }
        XCTAssertEqual(moved.verticalOffset, projection.verticalOffset, accuracy: 0.001, file: file, line: line)
        var expectedCue = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID), file: file, line: line)
        expectedCue.anchorMeasureID = projection.measureID
        expectedCue.beatFraction = moved.beatFraction
        expectedCue.verticalOffset = projection.verticalOffset
        XCTAssertEqual(moved, expectedCue, file: file, line: line)
        XCTAssertEqual(reopened.cueTexts.filter { $0.id != fixture.cueID },
            fixture.chart.cueTexts.filter { $0.id != fixture.cueID }, file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.id), fixture.chart.measures.map(\.id), file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.chordEvents), fixture.chart.measures.map(\.chordEvents), file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.rhythmMap), fixture.chart.measures.map(\.rhythmMap), file: file, line: line)
        XCTAssertEqual(reopened.pageHandwrittenChordData, fixture.chart.pageHandwrittenChordData, file: file, line: line)
        XCTAssertEqual(reopened.pageHandwrittenNotationData, fixture.chart.pageHandwrittenNotationData, file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.handwrittenRhythmicNotationData),
            fixture.chart.measures.map(\.handwrittenRhythmicNotationData), file: file, line: line)
    }

    private func cue(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetCueTextLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == id })
    }

    private func measure(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func measureIDsByPage(_ layout: LeadSheetPageLayout) -> [[UUID]] {
        layout.pages.map { page in
            layout.systems.filter { page.systemIDs.contains($0.id) }
                .flatMap(\.measures).compactMap(\.sourceMeasureID)
        }
    }

    private func encoded(_ chart: Chart) throws -> Data {
        try ChartPersistenceCoders.encoder.encode(chart)
    }

    private func assertEqual(_ actual: CGRect, _ expected: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }

    private func sourceDrawing() -> PKDrawing {
        let points = [CGPoint(x: 24, y: 24), CGPoint(x: 40, y: 12), CGPoint(x: 52, y: 40)]
            .enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)),
            transform: .identity, mask: nil, randomSeed: 17)])
    }
}
#endif
