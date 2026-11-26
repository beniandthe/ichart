import XCTest
@testable import iChart

final class PaperEnclosedMeasureTests: XCTestCase {
    func testSavedBuild201GapBecomesARealMeasureWithoutMovingExistingContent() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = try savedGapChart(style)
            let original = chart
            let originalIDs = chart.measures.map(\.id)
            let date = chart.updatedAt

            XCTAssertTrue(chart.repairEnclosedPaperMeasures())

            XCTAssertEqual(chart.systems[0].measures.count, 4)
            XCTAssertEqual(chart.systems[0].measures.map(\.id).filter { originalIDs.contains($0) },
                original.systems[0].measures.map(\.id))
            let enclosed = chart.systems[0].measures[2]
            XCTAssertEqual(enclosed.authoringState, .committed)
            XCTAssertEqual(enclosed.paperLayout?.startFraction, 0.6510545522018801)
            XCTAssertEqual(enclosed.paperLayout?.endFraction, 0.843804119247897)
            XCTAssertEqual(enclosed.paperLayout?.leadingBarline, .single)
            XCTAssertEqual(enclosed.barlineAfter, .single)
            XCTAssertTrue(enclosed.chordEvents.isEmpty)
            XCTAssertEqual(chart.paperMeasureTarget(inRow: 0, at: 0.75)?.measureID, enclosed.id)
            for measure in original.measures {
                let retained = try XCTUnwrap(chart.measure(id: measure.id))
                XCTAssertEqual(retained.paperLayout, measure.paperLayout)
                XCTAssertEqual(retained.chordEvents, measure.chordEvents)
            }
            XCTAssertEqual(chart.systems[1].measures.count, 1)
            XCTAssertEqual(chart.systems[1].measures[0].paperLayout?.startFraction, 0.7480529221728673)
            XCTAssertEqual(chart.systems[1].measures[0].paperLayout?.endFraction, 1)
            XCTAssertEqual(chart.roadmapObjects, original.roadmapObjects)
            XCTAssertEqual(chart.updatedAt, date)
            let repaired = chart
            XCTAssertFalse(chart.repairEnclosedPaperMeasures())
            XCTAssertFalse(chart.finishPaperWritingRows())
            XCTAssertEqual(chart, repaired)
        }
    }

    func testDecodingTheSameBuild201ChartTwiceRepairsWithIdenticalMeasureIDs() throws {
        let original = try savedGapChart(.simpleChordSheet)
        let bytes = try JSONEncoder().encode(original)

        let first = try JSONDecoder().decode(Chart.self, from: bytes)
        let second = try JSONDecoder().decode(Chart.self, from: bytes)

        XCTAssertEqual(first.systems[0].measures.count, 4)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.updatedAt, original.updatedAt)
        XCTAssertEqual(try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(first)), first)
    }

    func testSequentialSeparateWritingSessionsRetainTheSpaceBetweenTheirBoundaries() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Separate writing", measureCount: 1, layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 2))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.1, kind: .double))
            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.3, kind: .double))
            _ = chart.finishPaperWritingRows()
            let firstID = chart.systems[0].measures[0].id

            XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.7, kind: .single))

            let enclosedID = try XCTUnwrap(chart.paperMeasureTarget(inRow: 0, at: 0.5)?.measureID)
            XCTAssertNotEqual(enclosedID, firstID)
            let enclosed = try XCTUnwrap(chart.measure(id: enclosedID))
            XCTAssertEqual(enclosed.authoringState, .committed)
            XCTAssertEqual(enclosed.paperLayout?.startFraction, 0.3)
            XCTAssertEqual(enclosed.paperLayout?.endFraction, 0.7)
            XCTAssertEqual(enclosed.paperLayout?.leadingBarline, .double)
            XCTAssertNil(chart.paperMeasureTarget(inRow: 0, at: 0.05))
        }
    }

    func testSingleFloatingMeasureAndEmptyRowsHaveNoSyntheticOutsideMeasures() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "One measure", measureCount: 1, layoutStyle: style)
            XCTAssertTrue(chart.initializePaperWritingRows(count: 2))
            _ = chart.placePaperBarline(inRow: 0, at: 0.78, kind: .double)
            _ = chart.placePaperBarline(inRow: 0, at: 0.98, kind: .double)
            _ = chart.finishPaperWritingRows()
            let before = chart

            XCTAssertFalse(chart.repairEnclosedPaperMeasures())
            XCTAssertEqual(chart, before)
            XCTAssertEqual(chart.systems[0].measures.count, 1)
            XCTAssertNil(chart.paperMeasureTarget(inRow: 0, at: 0.5))
            XCTAssertNil(chart.paperMeasureTarget(inRow: 0, at: 0.99))
        }
    }

    func testFrozenMovementProposalMatchesCommittedOriginalMeasurePositions() throws {
        var chart = try savedGapChart(.simpleChordSheet)
        _ = chart.repairEnclosedPaperMeasures()
        let movingID = chart.systems[0].measures.last!.id
        let frozen = try XCTUnwrap(chart.paperMeasureMovePositions(for: movingID))
        for fraction in [0.0, 0.2, 0.5, 0.9] {
            let proposal = try XCTUnwrap(PaperMeasureMoveProposal.positions(moving: movingID,
                toStartFraction: fraction, among: frozen))
            var moved = chart
            XCTAssertTrue(moved.movePaperMeasure(movingID, toStartFraction: fraction))
            for (id, position) in proposal {
                XCTAssertEqual(moved.measure(id: id)?.paperLayout, position)
            }
        }
    }

    func testShrinkingMiddleMeasureMakesBothEnclosedGapsSelectableAndPreservesRanges() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Shrink middle", measureCount: 3, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, Double($0.offset) / 3...Double($0.offset + 1) / 3)
            })
            XCTAssertTrue(chart.adoptPaperMeasureLayout([positions]))
            XCTAssertNotNil(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
            XCTAssertNotNil(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[2]))
            let references = chart.roadmapObjects

            XCTAssertTrue(chart.resizePaperMeasure(ids[1], startFraction: 0.42, endFraction: 0.58))

            XCTAssertEqual(chart.systems[0].measures.count, 5)
            XCTAssertEqual(chart.measures.filter { ids.contains($0.id) }.map(\.id), ids)
            let leftGapID = try XCTUnwrap(chart.paperMeasureTarget(inRow: 0, at: 0.38)?.measureID)
            let rightGapID = try XCTUnwrap(chart.paperMeasureTarget(inRow: 0, at: 0.62)?.measureID)
            XCTAssertFalse(ids.contains(leftGapID))
            XCTAssertFalse(ids.contains(rightGapID))
            XCTAssertNotEqual(leftGapID, rightGapID)
            XCTAssertEqual(chart.measure(id: ids[1])?.paperLayout?.startFraction, 0.42)
            XCTAssertEqual(chart.measure(id: ids[1])?.paperLayout?.endFraction, 0.58)
            XCTAssertEqual(chart.roadmapObjects, references)
            XCTAssertEqual(try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart)), chart)
        }
    }

    private func savedGapChart(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Build 201 paper gap", measureCount: 4, layoutStyle: style)
        chart.usesPaperMeasureLayout = true
        var measures = chart.measures
        let spans: [(Double, Double, BarlineType, BarlineType)] = [
            (0, 0.32552727610094007, .double, .double),
            (0.32552727610094007, 0.6510545522018801, .double, .single),
            (0.843804119247897, 1, .single, .single),
            (0.7480529221728673, 1, .double, .single)
        ]
        for index in measures.indices {
            let span = spans[index]
            measures[index].paperLayout = PaperMeasureLayout(rowIndex: index < 3 ? 0 : 1,
                startFraction: span.0, endFraction: span.1, leadingBarline: span.2)
            measures[index].barlineAfter = span.3
            _ = measures[index].appendChordEvent(symbol: try ChordSymbolParser.parse(index == 3 ? "F/G" : "Bbmaj7"),
                rawInput: index == 3 ? "F/G" : "Bbmaj7", defaultMeter: chart.defaultMeter)
        }
        let originalSystem = chart.systems[0]
        chart.systems = [
            ChartSystem(id: originalSystem.id, index: 0, spacingMode: .automatic,
                lineBreakRule: .automatic, measures: Array(measures.prefix(3))),
            ChartSystem(id: UUID(), index: 1, spacingMode: .automatic,
                lineBreakRule: .forced, measures: [measures[3]])
        ]
        XCTAssertNotNil(chart.addEndingSpan(.ending1, startMeasureID: measures[0].id, endMeasureID: measures[1].id))
        XCTAssertNotNil(chart.addRepeatSpan(startMeasureID: measures[0].id, endMeasureID: measures[2].id))
        return chart
    }
}
