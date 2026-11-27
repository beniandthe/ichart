import XCTest
@testable import iChart
#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
#endif

final class PaperMeasureEditingTests: XCTestCase {
    func testLegacyChartsOmitPaperMetadataAndRoundTripWithOriginalLayout() throws {
        let chart = Chart.blank(title: "Legacy", measureCount: 3, layoutStyle: .simpleChordSheet)
        let data = try JSONEncoder().encode(chart)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["paperMeasureLayoutVersion"])
        XCTAssertFalse(chart.usesPaperMeasureLayout)
        XCTAssertEqual(try JSONDecoder().decode(Chart.self, from: data), chart)
    }

    func testDoubleBarPairCreatesOneFloatingMeasureInBothStyles() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Floating", measureCount: 1, layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 2))
            XCTAssertEqual(chart.systems.count, 2)
            let original = try XCTUnwrap(chart.systems[0].measures.first?.id)
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.78, kind: .double))
            XCTAssertEqual(chart.systems[0].measures.count, 1)
            XCTAssertEqual(chart.systems[0].measures[0].authoringState, .open)
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.98, kind: .double))
            XCTAssertEqual(chart.systems[0].measures.filter { $0.authoringState == .committed }.count, 1)
            XCTAssertTrue(chart.finishPaperWritingRows())
            let measure = try XCTUnwrap(chart.systems[0].measures.first)
            XCTAssertEqual(chart.systems[0].measures.count, 1)
            XCTAssertEqual(measure.id, original)
            XCTAssertEqual(measure.paperLayout?.startFraction, 0.78)
            XCTAssertEqual(measure.paperLayout?.endFraction, 0.98)
            XCTAssertEqual(measure.paperLayout?.leadingBarline, .double)
            XCTAssertEqual(measure.barlineAfter, .double)
            XCTAssertEqual(try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart)), chart)
        }
    }

    func testClosingTwoMeasuresFitsOnlyTheirEditedRowAndDoesNotRefitManualMove() throws {
        var chart = paperChart()
        let untouched = chart.systems[1]
        for x in [0.1, 0.4, 0.7] {
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: x, kind: .single))
        }
        XCTAssertTrue(chart.finishPaperWritingRows())
        XCTAssertEqual(chart.systems[0].measures.count, 2)
        XCTAssertEqual(chart.systems[0].measures.map { $0.paperLayout?.startFraction }, [0, 0.5])
        XCTAssertEqual(chart.systems[0].measures.map { $0.paperLayout?.endFraction }, [0.5, 1])
        XCTAssertEqual(chart.systems[1].id, untouched.id)
        XCTAssertEqual(chart.systems[1].measures.map(\.id), untouched.measures.map(\.id))
        let id = chart.systems[0].measures[0].id
        XCTAssertTrue(chart.movePaperMeasure(id, toStartFraction: 0.5))
        let moved = chart.systems[0]
        XCTAssertFalse(chart.finishPaperWritingRows())
        XCTAssertEqual(chart.systems[0], moved)
    }

    func testFloatingMeasureCanMoveResizeAndLeaveRoomToWriteBeforeIt() throws {
        var chart = paperChart()
        _ = chart.placePaperBarline(inRow: 0, at: 0.75, kind: .double)
        _ = chart.placePaperBarline(inRow: 0, at: 0.95, kind: .double)
        _ = chart.finishPaperWritingRows()
        let id = chart.systems[0].measures[0].id
        XCTAssertTrue(chart.movePaperMeasure(id, toStartFraction: 0.65))
        XCTAssertEqual(try XCTUnwrap(chart.measure(id: id)?.paperLayout?.startFraction), 0.65, accuracy: 0.0001)
        XCTAssertTrue(chart.resizePaperMeasure(id, startFraction: 0.6, endFraction: 0.9))
        XCTAssertNil(chart.paperMeasureTarget(inRow: 0, at: 0.2))
        let target = try XCTUnwrap(chart.ensurePaperChordTarget(inRow: 0, at: 0.2))
        XCTAssertNotEqual(target.measureID, id)
        XCTAssertEqual(chart.measure(id: id)?.paperLayout?.startFraction, 0.6)
        XCTAssertEqual(chart.measure(id: id)?.paperLayout?.endFraction, 0.9)
    }

    func testRetracingDoubleBarKeepsItsKindAndLastRowExtendsWritingSpace() {
        var chart = paperChart()
        _ = chart.placePaperBarline(inRow: 0, at: 0.2, kind: .double)
        _ = chart.placePaperBarline(inRow: 0, at: 0.2, kind: .single)
        XCTAssertEqual(chart.systems[0].measures[0].paperLayout?.leadingBarline, .double)
        _ = chart.placePaperBarline(inRow: 1, at: 0.2, kind: .single)
        XCTAssertEqual(chart.systems.count, 3)
        XCTAssertEqual(chart.systems[2].measures.first?.authoringState, .open)
    }

    func testExistingRowsCanAdoptPaperPositionsAndReorderWithoutChangingChordIdentity() throws {
        var chart = Chart.blank(title: "Existing", measureCount: 3, layoutStyle: .simpleChordSheet)
        let source = chart.measures
        let frames = Dictionary(uniqueKeysWithValues: source.enumerated().map { index, measure in
            (measure.id, Double(index) / 3...Double(index + 1) / 3)
        })
        XCTAssertTrue(chart.adoptPaperMeasureLayout([frames]))
        XCTAssertTrue(chart.movePaperMeasure(source[0].id, toStartFraction: 2.0 / 3))
        XCTAssertEqual(chart.systems[0].measures.map(\.id), [source[1].id, source[2].id, source[0].id])
        for (index, measure) in chart.systems[0].measures.enumerated() {
            XCTAssertEqual(try XCTUnwrap(measure.paperLayout?.startFraction), Double(index) / 3, accuracy: 0.0001)
        }
        XCTAssertTrue(chart.resizePaperMeasure(source[0].id, startFraction: 0.4, endFraction: 1))
        let ranges = chart.systems[0].measures.compactMap(\.paperLayout)
        XCTAssertEqual(ranges.last?.endFraction, 1)
        for pair in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.endFraction, pair.1.startFraction)
        }
    }

    func testManualMeasureInsertionAndRowJoinRetainPaperIdentity() throws {
        var chart = paperChart()
        for row in 0..<2 {
            _ = chart.placePaperBarline(inRow: row, at: 0.2, kind: .single)
            _ = chart.placePaperBarline(inRow: row, at: 0.8, kind: .single)
        }
        _ = chart.finishPaperWritingRows()
        let firstID = chart.systems[0].measures[0].id
        let inserted = try XCTUnwrap(chart.insertOneMeasureAfterForEditing(firstID))
        XCTAssertEqual(chart.systems[0].measures.map(\.id), [firstID, inserted])
        XCTAssertEqual(chart.systems[0].measures.map { $0.paperLayout?.widthFraction }, [0.5, 0.5])
        let oldRows = chart.systems.prefix(2).map { $0.measures.map(\.id) }
        let expected = oldRows.flatMap { $0 }
        XCTAssertTrue(chart.reflowMeasureRows(oldRows, into: [expected], equalizedWidthPerMeasure: [100]))
        XCTAssertEqual(chart.systems[0].measures.map(\.id), expected)
        XCTAssertEqual(chart.systems[0].measures.map { $0.paperLayout?.rowIndex }, [0, 0, 0])
    }

    func testFullWidthResizeRetainsAllPeerPlacementsThroughReopen() throws {
        var chart = paperChart()
        for x in [0.1, 0.3, 0.5, 0.8] {
            _ = chart.placePaperBarline(inRow: 0, at: x, kind: .single)
        }
        _ = chart.finishPaperWritingRows()
        let ids = chart.systems[0].measures.map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(chart.resizePaperMeasure(ids[0], startFraction: 0, endFraction: 1))
        let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
        XCTAssertEqual(reopened.systems[0].measures.map(\.id), chart.systems[0].measures.map(\.id))
        XCTAssertTrue(reopened.systems[0].measures.allSatisfy { $0.paperLayout?.isValid == true })
        XCTAssertEqual(reopened, chart)
    }

    func testLateDoubleBarUpgradeIsRetainedWhenNeighborMovesIntoGap() throws {
        var chart = paperChart()
        for x in [0.1, 0.4, 0.7] {
            _ = chart.placePaperBarline(inRow: 0, at: x, kind: .single)
        }
        _ = chart.placePaperBarline(inRow: 0, at: 0.4, kind: .double)
        let left = chart.systems[0].measures[0]
        let right = chart.systems[0].measures[1]
        XCTAssertEqual(left.barlineAfter, .double)
        XCTAssertEqual(right.paperLayout?.leadingBarline, .double)
        XCTAssertTrue(chart.resizePaperMeasure(right.id, startFraction: 0.75, endFraction: 0.95))
        XCTAssertEqual(chart.measure(id: right.id)?.paperLayout?.leadingBarline, .double)
    }

    func testWiderLegacyMeasureCanMoveToTheFirstPosition() throws {
        var chart = Chart.blank(title: "Legacy widths", measureCount: 3, layoutStyle: .rhythmSectionSheet)
        let ids = chart.measures.map(\.id)
        XCTAssertTrue(chart.adoptPaperMeasureLayout([[
            ids[0]: 0...0.3, ids[1]: 0.3...0.6, ids[2]: 0.6...1
        ]]))
        XCTAssertTrue(chart.movePaperMeasure(ids[2], toStartFraction: 0))
        XCTAssertEqual(chart.systems[0].measures.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertEqual(chart.measure(id: ids[2])?.paperLayout?.startFraction, 0)
    }

    #if canImport(UIKit) && canImport(PencilKit)
    func testInkInOwnedMarginBelowOpenMeasureSurvivesFinishMoveAndResize() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            for operation in 0..<3 {
                var chart = Chart.blank(title: "Margin ink", measureCount: 1, layoutStyle: style)
                XCTAssertTrue(chart.initializePaperWritingRows(count: 1))
                _ = chart.placePaperBarline(inRow: 0, at: 0, kind: .double)
                _ = chart.placePaperBarline(inRow: 0, at: 0.35, kind: .single)
                let firstID = chart.systems[0].measures[0].id
                let ownerID = chart.systems[0].measures[1].id
                let frame = CGRect(x: 300, y: 200, width: 400, height: 100)
                let anchor = try XCTUnwrap(PersistentInkMeasureAnchor(measureID: ownerID, frame: frame))
                let source = PersistentInkCoordinateSpace(width: 900, height: 1400, measureAnchors: [anchor])
                let points = [CGPoint(x: 400, y: 340), CGPoint(x: 430, y: 350)]
                let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
                    PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                        size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                        azimuth: 0, altitude: .pi / 2)
                }, creationDate: .now)
                let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
                    path: path, transform: .identity, mask: nil, randomSeed: 43)])
                XCTAssertFalse(drawing.bounds.intersects(frame.insetBy(dx: 0, dy: -16)))
                var probe = source
                probe.measureAnchors?[0].frame.x += 1
                let projected = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(drawing,
                    sourceCoordinateSpace: source, targetCoordinateSpace: probe)
                XCTAssertNotEqual(projected.bounds, drawing.bounds, "The saved-ink policy owns this margin stroke")
                let data = drawing.dataRepresentation()
                chart.setPageHandwrittenNotationDrawing(data, coordinateSpace: source)
                let savedData = try XCTUnwrap(chart.pageHandwrittenNotationData)

                switch operation {
                case 0: XCTAssertTrue(chart.finishPaperWritingRows())
                case 1: XCTAssertTrue(chart.movePaperMeasure(firstID, toStartFraction: 0.55))
                default: XCTAssertTrue(chart.resizePaperMeasure(firstID, startFraction: 0, endFraction: 0.25))
                }

                XCTAssertNotNil(chart.measure(id: ownerID))
                XCTAssertEqual(chart.pageHandwrittenNotationData, savedData)
                XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, source)
                XCTAssertEqual(try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart)), chart)
            }
        }
    }
    #endif

    private func paperChart() -> Chart {
        var chart = Chart.blank(title: "Paper", measureCount: 1, layoutStyle: .simpleChordSheet)
        _ = chart.initializePaperWritingRows(count: 2)
        return chart
    }
}
