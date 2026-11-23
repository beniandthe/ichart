#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Production gesture policy: only the saved compatibility beat is discrete.
/// The current renderer and Pencil preview use continuous spatial placement.
@MainActor
final class CueTextDragProjectionTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let positions: [CuePosition] = [.above, .below]

    func testSmallHorizontalMovesFollowEveryGrabPointWithoutBeatSnapping() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let original = try cue(fixture.cueID, in: fixture.layout)
                for scale: CGFloat in [0.5, 1, 2.5] {
                    for grab: CGFloat in [0.05, 0.5, 0.95] {
                        let start = CGPoint(x: original.frame.minX + original.frame.width * grab, y: original.frame.midY)
                        var drag = try makeDrag(fixture, start: start, scale: scale)
                        var previousX = original.frame.minX
                        for distance: CGFloat in [0.4, 0.9, 1.4, 2.1, 3.7, 5.2] {
                            LeadSheetCueTextMoveDragPolicy.update(&drag,
                                at: CGPoint(x: start.x + distance, y: start.y))
                            let projected = try XCTUnwrap(drag.currentProjection)
                            XCTAssertEqual(projected.cueLayout.frame.minX, original.frame.minX + distance, accuracy: 0.001)
                            XCTAssertGreaterThan(projected.cueLayout.frame.minX, previousX)
                            XCTAssertEqual(projected.horizontalPlacement?.region, .measure)
                            try assertGuideCenter(projected, in: fixture.layout)
                            XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                            previousX = projected.cueLayout.frame.minX
                        }
                        try assertCommitAndReopenMatch(drag, fixture: fixture)
                    }
                }
            }
        }
    }

    func testHundredsOfSmallHorizontalSamplesCrossRealBoundariesContinuouslyWithoutPagePacking() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let row = try XCTUnwrap(fixture.layout.systems.first)
                let first = try XCTUnwrap(row.measures.first)
                let last = try XCTUnwrap(row.measures.last)
                let paper = fixture.layout.paperFrame(for: row)
                let minimumX = paper.minX + 4
                let maximumX = paper.maxX - 4 - original.frame.width
                XCTAssertGreaterThan(maximumX, last.staffFrame.maxX, "Short cue must fit in the real right margin")
                let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                var drag = try makeDrag(fixture, start: start)
                var previousX = -CGFloat.greatestFiniteMagnitude
                var owners = Set<UUID>()
                var sawLeading = false
                var sawTrailing = false
                for sample in 0...320 {
                    let x = minimumX + (maximumX - minimumX) * CGFloat(sample) / 320
                    LeadSheetCueTextMoveDragPolicy.update(&drag,
                        at: CGPoint(x: start.x + x - original.frame.minX, y: start.y))
                    let projected = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(projected.cueLayout.frame.minX, x, accuracy: 0.01)
                    XCTAssertGreaterThanOrEqual(projected.cueLayout.frame.minX + 0.001, previousX)
                    XCTAssertEqual(projected.cueLayout.frame.size, original.frame.size)
                    XCTAssertEqual(drag.pageLayoutProjectionCount, 0,
                        "Continuous fractions must never repack the document during changed")
                    if x < first.staffFrame.minX {
                        XCTAssertEqual(projected.horizontalPlacement?.region, .leadingMargin)
                        XCTAssertNil(projected.attachmentGuide)
                        sawLeading = true
                    } else if x >= last.staffFrame.maxX {
                        XCTAssertEqual(projected.horizontalPlacement?.region, .trailingMargin)
                        XCTAssertNil(projected.attachmentGuide)
                        sawTrailing = true
                    } else {
                        let expectedOwner = try XCTUnwrap(row.measures.first { x < $0.staffFrame.maxX }?.sourceMeasureID)
                        XCTAssertEqual(projected.measureID, expectedOwner)
                        XCTAssertEqual(projected.horizontalPlacement?.region, .measure)
                        try assertGuideCenter(projected, in: fixture.layout)
                        owners.insert(projected.measureID)
                    }
                    previousX = projected.cueLayout.frame.minX
                }
                XCTAssertTrue(sawLeading)
                XCTAssertTrue(sawTrailing)
                XCTAssertEqual(owners, Set(row.measures.compactMap(\.sourceMeasureID)))
                XCTAssertEqual(try encoded(drag.sourceChart), try encoded(fixture.chart))
                LeadSheetCueTextMoveDragPolicy.finish(&drag)
                XCTAssertLessThanOrEqual(drag.pageLayoutProjectionCount, 1)
                try assertCommitAndReopenMatch(drag, fixture: fixture)
            }
        }
    }

    func testOnlyTheLeadingOriginCrossingARealMeasureBoundaryRetargetsTheCue() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let measures = try XCTUnwrap(fixture.layout.systems.first).measures
            let boundary = measures[0].staffFrame.maxX
            let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            for delta: CGFloat in [-0.25, 0.25] {
                let requestedX = boundary + delta
                LeadSheetCueTextMoveDragPolicy.update(&drag,
                    at: CGPoint(x: start.x + requestedX - original.frame.minX, y: start.y))
                let projection = try XCTUnwrap(drag.currentProjection)
                XCTAssertEqual(projection.measureID, delta < 0 ? fixture.measureIDs[0] : fixture.measureIDs[1])
                XCTAssertEqual(projection.cueLayout.frame.minX, requestedX, accuracy: 0.001)
                try assertGuideCenter(projection, in: fixture.layout)
            }
            LeadSheetCueTextMoveDragPolicy.finish(&drag)
            try assertCommitAndReopenMatch(drag, fixture: fixture)
        }
    }

    func testMarginsDetachSaveAtTheEdgeAndReattachWhenTheOriginReturns() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let row = try XCTUnwrap(fixture.layout.systems.first)
                let first = try XCTUnwrap(row.measures.first?.sourceMeasureID)
                let last = try XCTUnwrap(row.measures.last?.sourceMeasureID)
                let paper = fixture.layout.paperFrame(for: row)
                for (requestedX, region, owner) in [
                    (paper.minX - 100, CueTextHorizontalPlacement.Region.leadingMargin, first),
                    (paper.maxX + 100, .trailingMargin, last)
                ] {
                    let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                    var drag = try makeDrag(fixture, start: start)
                    LeadSheetCueTextMoveDragPolicy.update(&drag,
                        at: CGPoint(x: start.x + requestedX - original.frame.minX, y: start.y))
                    let detached = try XCTUnwrap(drag.currentProjection)
                    XCTAssertEqual(detached.horizontalPlacement?.region, region)
                    XCTAssertEqual(detached.measureID, owner)
                    XCTAssertNil(detached.attachmentGuide)
                    XCTAssertGreaterThanOrEqual(detached.cueLayout.frame.minX, paper.minX + 4 - 0.001)
                    XCTAssertLessThanOrEqual(detached.cueLayout.frame.maxX, paper.maxX - 4 + 0.001)
                    LeadSheetCueTextMoveDragPolicy.finish(&drag)
                    try assertCommitAndReopenMatch(drag, fixture: fixture)
                    LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
                    var untouched = fixture.chart
                    XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &untouched))
                    XCTAssertNotNil(drag.currentProjection?.attachmentGuide)
                    XCTAssertNil(drag.currentProjection?.horizontalPlacement)
                    XCTAssertEqual(try encoded(untouched), try encoded(fixture.chart))
                }
            }
        }
    }

    func testLongCueKeepsItsWrapWidthAndCannotBeForcedIntoANarrowRightMargin() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .below,
                text: "Horns enter together after the second repeat, then watch the conductor", shortRows: false)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let source = try measure(fixture.measureIDs[0], in: fixture.layout)
            let row = try XCTUnwrap(fixture.layout.systems.first)
            let last = try XCTUnwrap(row.measures.last)
            let paper = fixture.layout.paperFrame(for: row)
            XCTAssertGreaterThan(original.frame.width, paper.maxX - 4 - last.staffFrame.maxX)
            let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            LeadSheetCueTextMoveDragPolicy.update(&drag,
                at: CGPoint(x: start.x + paper.maxX + 100 - original.frame.minX, y: start.y))
            let preview = try XCTUnwrap(drag.currentProjection)
            XCTAssertEqual(preview.horizontalPlacement?.region, .measure)
            XCTAssertNotNil(preview.attachmentGuide)
            XCTAssertEqual(preview.cueLayout.frame.width, original.frame.width, accuracy: 0.001)
            XCTAssertEqual(preview.cueLayout.frame.height, original.frame.height, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(preview.horizontalPlacement?.wrapWidth), Double(source.staffFrame.width - 12), accuracy: 0.001)
            XCTAssertLessThanOrEqual(preview.cueLayout.frame.maxX, paper.maxX - 4 + 0.001)
            LeadSheetCueTextMoveDragPolicy.finish(&drag)
            try assertCommitAndReopenMatch(drag, fixture: fixture)
        }
    }

    func testVerticalJitterPreservesLegacyOrDetachedAttachmentFarPastNeighboringRows() throws {
        for style in styles {
            for detached in [false, true] {
                let base = try fixture(style: style, position: .below)
                var chart = base.chart
                if detached {
                    let source = try measure(base.measureIDs[0], in: base.layout)
                    XCTAssertTrue(chart.moveCueText(base.cueID, to: base.measureIDs[0], atFraction: 0,
                        horizontalPlacement: .init(region: .leadingMargin, fraction: 0.4,
                            wrapWidth: Double(source.staffFrame.width - 12))))
                }
                let fixture = Fixture(chart: chart,
                    layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                    cueID: base.cueID, measureIDs: base.measureIDs)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let sourceCue = try XCTUnwrap(chart.cueText(id: fixture.cueID))
                let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
                for scale: CGFloat in [0.5, 1, 2.5] {
                    for horizontalScreenTravel: CGFloat in [-1.9, 0, 1.9] {
                        var drag = try makeDrag(fixture, start: start, scale: scale)
                        LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(
                            x: start.x + horizontalScreenTravel / scale,
                            y: start.y + fixture.layout.pageBounds.height * 2))
                        let projection = try XCTUnwrap(drag.currentProjection)
                        XCTAssertEqual(projection.measureID, sourceCue.anchorMeasureID)
                        XCTAssertEqual(projection.fraction, sourceCue.beatFraction)
                        XCTAssertEqual(projection.horizontalPlacement, sourceCue.horizontalPlacement)
                        XCTAssertEqual(projection.cueLayout.frame.minX, original.frame.minX, accuracy: 0.001)
                        XCTAssertEqual(projection.attachmentGuide == nil, detached)
                        XCTAssertGreaterThan(try XCTUnwrap(projection.manualVerticalOffset), 72)
                        XCTAssertLessThanOrEqual(projection.cueLayout.frame.maxY,
                            fixture.layout.paperFrame.maxY)
                        LeadSheetCueTextMoveDragPolicy.finish(&drag)
                        XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                        try assertCommitAndReopenMatch(drag, fixture: fixture)
                    }
                }
            }
        }
    }

    func testTallVerticalDragsKeepTheOriginalRowWhileSmallIntentionalXStillMovesContinuously() throws {
        for style in styles {
            for position in positions {
                let fixture = try fixture(style: style, position: position)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let source = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID))
                let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                for scale: CGFloat in [0.5, 1, 2.5] {
                    for horizontalScreenTravel: CGFloat in [-6, 6, 11.9] {
                        var drag = try makeDrag(fixture, start: start, scale: scale)
                        let dx = horizontalScreenTravel / scale
                        LeadSheetCueTextMoveDragPolicy.update(&drag,
                            at: CGPoint(x: start.x + dx, y: start.y + 360))
                        let projection = try XCTUnwrap(drag.currentProjection)
                        XCTAssertEqual(projection.measureID, source.anchorMeasureID)
                        XCTAssertEqual(projection.cueLayout.frame.minX, original.frame.minX + dx, accuracy: 0.001)
                        XCTAssertEqual(projection.cueLayout.frame.minY, original.frame.minY + 360, accuracy: 0.001)
                        XCTAssertGreaterThan(try XCTUnwrap(projection.manualVerticalOffset), 72)
                        try assertGuideCenter(projection, in: fixture.layout)
                        XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                        LeadSheetCueTextMoveDragPolicy.finish(&drag)
                        XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                        try assertCommitAndReopenMatch(drag, fixture: fixture)
                    }
                }
            }
        }
    }

    func testSmallHorizontalBoundaryCrossingDuringTallDragSwitchesOnlyToTheNeighborInTheOriginalRow() throws {
        for style in styles {
            let base = try fixture(style: style, position: .above)
            let source = try measure(base.measureIDs[0], in: base.layout)
            let boundary = source.staffFrame.maxX
            var chart = base.chart
            XCTAssertTrue(chart.moveCueText(base.cueID, to: base.measureIDs[0], atFraction: 0.95,
                horizontalPlacement: .init(region: .measure,
                    fraction: Double((boundary - 5 - source.staffFrame.minX) / source.staffFrame.width),
                    wrapWidth: Double(source.staffFrame.width - 12))))
            let fixture = Fixture(chart: chart,
                layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                cueID: base.cueID, measureIDs: base.measureIDs)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            for dx: CGFloat in [4.75, 5.25] {
                LeadSheetCueTextMoveDragPolicy.update(&drag,
                    at: CGPoint(x: start.x + dx, y: start.y + 360))
                let projection = try XCTUnwrap(drag.currentProjection)
                XCTAssertEqual(projection.measureID, dx < 5 ? fixture.measureIDs[0] : fixture.measureIDs[1])
                XCTAssertEqual(projection.cueLayout.frame.minX, boundary - 5 + dx, accuracy: 0.001)
                try assertGuideCenter(projection, in: fixture.layout)
                XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
            }
            LeadSheetCueTextMoveDragPolicy.finish(&drag)
            try assertCommitAndReopenMatch(drag, fixture: fixture)
        }
    }

    func testSavedLargeManualHeightRemainsANoOpUntilMovedAndCanImmediatelyMoveBack() throws {
        for style in styles {
            let base = try fixture(style: style, position: .below)
            var chart = base.chart
            XCTAssertTrue(chart.setCueTextManualVerticalOffset(base.cueID, to: 500))
            let fixture = Fixture(chart: chart,
                layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                cueID: base.cueID, measureIDs: base.measureIDs)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
            var untouched = chart
            XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &untouched))
            XCTAssertEqual(try encoded(untouched), try encoded(chart))
            XCTAssertEqual(drag.currentProjection?.manualVerticalOffset, 500)
            LeadSheetCueTextMoveDragPolicy.update(&drag,
                at: CGPoint(x: start.x + 1, y: start.y - 160))
            let projection = try XCTUnwrap(drag.currentProjection)
            XCTAssertEqual(projection.cueLayout.frame.minY, original.frame.minY - 160, accuracy: 0.001)
            XCTAssertEqual(projection.measureID, fixture.measureIDs[0])
            XCTAssertGreaterThan(try XCTUnwrap(projection.manualVerticalOffset), 72)
            try assertGuideCenter(projection, in: fixture.layout)
            try assertCommitAndReopenMatch(drag, fixture: fixture)
        }
    }

    func testDeliberateDiagonalIntoPageWhitespaceKeepsAPageBoundedPreview() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            LeadSheetCueTextMoveDragPolicy.update(&drag,
                at: CGPoint(x: start.x + 30, y: start.y + pageSize.height * 3))
            let projection = try XCTUnwrap(drag.currentProjection)
            XCTAssertEqual(projection.measureID, fixture.measureIDs[4])
            XCTAssertGreaterThan(try XCTUnwrap(projection.manualVerticalOffset), 72)
            XCTAssertLessThanOrEqual(projection.cueLayout.frame.maxY, fixture.layout.paperFrame.maxY)
            try assertGuideCenter(projection, in: fixture.layout)
            XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
            LeadSheetCueTextMoveDragPolicy.finish(&drag)
            try assertCommitAndReopenMatch(drag, fixture: fixture)
        }
    }

    func testNoOpCancelReturnAndStaleCueEditsPreserveTheExistingSource() throws {
        for style in styles {
            let fixture = try fixture(style: style, position: .above)
            let original = try cue(fixture.cueID, in: fixture.layout)
            let start = CGPoint(x: original.frame.midX, y: original.frame.midY)
            var drag = try makeDrag(fixture, start: start)
            var chart = fixture.chart
            LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
            XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart))
            LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(x: start.x + 17.3, y: start.y))
            XCTAssertNotNil(drag.currentProjection?.horizontalPlacement)
            XCTAssertEqual(try encoded(chart), try encoded(fixture.chart), "Preview/cancellation never writes the document")
            LeadSheetCueTextMoveDragPolicy.update(&drag, at: start)
            XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart))
            XCTAssertNil(drag.currentProjection?.horizontalPlacement)
            XCTAssertEqual(try encoded(chart), try encoded(fixture.chart))
            LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(x: start.x + 19.7, y: start.y))
            XCTAssertTrue(chart.updateCueText(fixture.cueID, text: "Independent edit"))
            let independentlyEdited = try encoded(chart)
            XCTAssertFalse(LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart))
            XCTAssertEqual(try encoded(chart), independentlyEdited)
        }
    }

    func testDeliberateDiagonalDropsAcrossRowsAndPagesKeepContinuousPlacementAndSourceInk() throws {
        for style in styles {
            for pageBreak in [false, true] {
                let base = try fixture(style: style, position: .above)
                var chart = base.chart
                chart.systems[1].startsNewPage = pageBreak
                let fixture = Fixture(chart: chart,
                    layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
                    cueID: base.cueID, measureIDs: base.measureIDs)
                let original = try cue(fixture.cueID, in: fixture.layout)
                let source = try measure(fixture.measureIDs[0], in: fixture.layout)
                let destination = try measure(fixture.measureIDs[4], in: fixture.layout)
                let start = CGPoint(x: original.frame.maxX - 1, y: original.frame.midY)
                var desiredX = destination.staffFrame.minX + destination.staffFrame.width * 0.371
                if abs(desiredX - original.frame.minX) <= 12 { desiredX = original.frame.minX + 30 }
                var drag = try makeDrag(fixture, start: start)
                LeadSheetCueTextMoveDragPolicy.update(&drag, at: CGPoint(
                    x: start.x + desiredX - original.frame.minX,
                    y: start.y + destination.staffFrame.minY - source.staffFrame.minY))
                let preview = try XCTUnwrap(drag.currentProjection)
                XCTAssertEqual(preview.measureID, fixture.measureIDs[4])
                XCTAssertEqual(preview.cueLayout.frame.minX, desiredX, accuracy: 0.001)
                XCTAssertNotNil(preview.attachmentGuide)
                XCTAssertEqual(drag.pageLayoutProjectionCount, 0)
                LeadSheetCueTextMoveDragPolicy.finish(&drag)
                XCTAssertLessThanOrEqual(drag.pageLayoutProjectionCount, 1)
                try assertCommitAndReopenMatch(drag, fixture: fixture)
            }
        }
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let cueID: UUID
        let measureIDs: [UUID]
    }

    private func fixture(style: ChartLayoutStyle, position: CuePosition,
        text: String = "Cue", shortRows: Bool = true) throws -> Fixture {
        var chart = Chart.blank(title: "Continuous cue projection", measureCount: 8, layoutStyle: style)
        chart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let measures = chart.measures
        chart.systems = [Array(measures.prefix(4)), Array(measures.dropFirst(4))].enumerated().map {
            ChartSystem(id: UUID(), index: $0.offset, spacingMode: .automatic, lineBreakRule: .forced, measures: $0.element)
        }
        let ids = chart.measures.map(\.id)
        if shortRows {
            for (index, id) in ids.enumerated() {
                XCTAssertNotNil(chart.setMeasureManualLayoutWidth(CGFloat(100 + (index % 3) * 5), for: id))
            }
        }
        for index in [0, 1, 4] {
            XCTAssertNotNil(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse(index == 0 ? "Cmaj7" : "G7"),
                rawInput: index == 0 ? "Cmaj7" : "G7", to: ids[index], atFraction: 0.25))
        }
        let id = try XCTUnwrap(chart.addCueText(text, anchorMeasureID: ids[0], position: position, atFraction: 0.25))
        let ink = try XCTUnwrap(LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: sourceDrawing()))
        chart.systems[0].measures[0].chordEvents[0].sourceInkData = ink
        chart.pageHandwrittenChordData = ink
        chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.pageHandwrittenNotationData = ink
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.systems[0].measures[0].handwrittenRhythmicNotationData = ink
        chart.systems[0].measures[0].handwrittenRhythmicNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 180, height: 80)
        chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
        return Fixture(chart: chart, layout: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize),
            cueID: id, measureIDs: ids)
    }

    private func makeDrag(_ fixture: Fixture, start: CGPoint, scale: CGFloat = 1) throws -> ActiveCueTextMoveDrag {
        try XCTUnwrap(ActiveCueTextMoveDrag(cueTextID: fixture.cueID, chart: fixture.chart,
            pageLayout: fixture.layout, pageSize: pageSize, startLocation: start, screenPointsPerDisplayedPoint: scale))
    }

    private func assertCommitAndReopenMatch(_ drag: ActiveCueTextMoveDrag, fixture: Fixture,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let projection = try XCTUnwrap(drag.currentProjection, file: file, line: line)
        var chart = fixture.chart
        if !LeadSheetCueTextMoveDragPolicy.commit(drag, in: &chart) {
            XCTAssertEqual(try encoded(chart), try encoded(fixture.chart), file: file, line: line)
            assertEqual(projection.cueLayout.frame, drag.initialFrame, file: file, line: line)
            XCTAssertEqual(projection.measureID, drag.sourceCue.anchorMeasureID, file: file, line: line)
            XCTAssertEqual(projection.horizontalPlacement, drag.sourceCue.horizontalPlacement, file: file, line: line)
            return
        }
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
        assertEqual(try cue(fixture.cueID, in: layout).frame, projection.cueLayout.frame, file: file, line: line)
        let moved = try XCTUnwrap(reopened.cueText(id: fixture.cueID), file: file, line: line)
        XCTAssertEqual(moved.anchorMeasureID, projection.measureID, file: file, line: line)
        if let expected = projection.fraction {
            XCTAssertEqual(try XCTUnwrap(moved.beatFraction), expected, accuracy: 1e-12, file: file, line: line)
        } else { XCTAssertNil(moved.beatFraction, file: file, line: line) }
        XCTAssertEqual(moved.horizontalPlacement?.region, projection.horizontalPlacement?.region, file: file, line: line)
        if let expected = projection.horizontalPlacement {
            let actual = try XCTUnwrap(moved.horizontalPlacement)
            XCTAssertEqual(actual.fraction, expected.fraction, accuracy: 1e-12, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(actual.wrapWidth), try XCTUnwrap(expected.wrapWidth), accuracy: 1e-9, file: file, line: line)
        }
        let manualOffset = try XCTUnwrap(projection.manualVerticalOffset, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(moved.manualVerticalOffset, file: file, line: line),
            manualOffset, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(moved.verticalOffset, CueText.clampedVerticalOffset(manualOffset), accuracy: 1e-9, file: file, line: line)
        var expected = try XCTUnwrap(fixture.chart.cueText(id: fixture.cueID))
        expected.anchorMeasureID = projection.measureID
        expected.beatFraction = moved.beatFraction
        expected.horizontalPlacement = moved.horizontalPlacement
        expected.verticalOffset = moved.verticalOffset
        expected.manualVerticalOffset = moved.manualVerticalOffset
        XCTAssertEqual(moved, expected, file: file, line: line)
        XCTAssertEqual(reopened.cueTexts.filter { $0.id != fixture.cueID }, fixture.chart.cueTexts.filter { $0.id != fixture.cueID }, file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.id), fixture.chart.measures.map(\.id), file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.chordEvents), fixture.chart.measures.map(\.chordEvents), file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.rhythmMap), fixture.chart.measures.map(\.rhythmMap), file: file, line: line)
        XCTAssertEqual(reopened.pageHandwrittenChordData, fixture.chart.pageHandwrittenChordData, file: file, line: line)
        XCTAssertEqual(reopened.pageHandwrittenNotationData, fixture.chart.pageHandwrittenNotationData, file: file, line: line)
        XCTAssertEqual(reopened.measures.map(\.handwrittenRhythmicNotationData), fixture.chart.measures.map(\.handwrittenRhythmicNotationData), file: file, line: line)
        XCTAssertEqual(reopened.systems.map(\.startsNewPage), fixture.chart.systems.map(\.startsNewPage), file: file, line: line)
    }

    private func cue(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetCueTextLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == id })
    }
    private func measure(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }
    private func assertGuideCenter(_ projection: LeadSheetCueTextMoveProjection, in layout: LeadSheetPageLayout,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let staff = try measure(projection.measureID, in: layout).staffFrame
        let guide = try XCTUnwrap(projection.attachmentGuide, file: file, line: line)
        XCTAssertEqual(guide.x, staff.midX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(guide.y, staff.midY, accuracy: 0.001, file: file, line: line)
    }
    private func encoded(_ chart: Chart) throws -> Data { try ChartPersistenceCoders.encoder.encode(chart) }
    private func assertEqual(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
    private func sourceDrawing() -> PKDrawing {
        let points = [CGPoint(x: 24, y: 24), CGPoint(x: 40, y: 12), CGPoint(x: 52, y: 40)].enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.01,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10)),
            transform: .identity, mask: nil, randomSeed: 17)])
    }
}
#endif
