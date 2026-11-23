import XCTest
@testable import iChart

final class EditorCueTextEntryRequestTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testAddRequestFreezesExplicitDestinationAndCallerWithoutEditingChart() throws {
        for style in styles {
            var chart = Chart.blank(title: "Text destination", measureCount: 3, layoutStyle: style)
            let measureID = chart.measures[1].id
            let original = chart
            let placement = EditorCueTextPlacementPreview(measureID: measureID, position: nil, beatFraction: 0.38)
            let request = try XCTUnwrap(EditorCueTextEntryRequest.adding(in: chart, placement: placement,
                position: .above, callerTool: .text))
            XCTAssertEqual(chart, original, "Opening and cancelling a request must leave chart content untouched")
            XCTAssertEqual(request.callerTool, .text)
            XCTAssertEqual(request.placement.measureID, measureID)
            XCTAssertEqual(request.placement.position, .above)
            XCTAssertEqual(try XCTUnwrap(request.placement.beatFraction), 0.375, accuracy: 0.0001)
            XCTAssertNil(request.cueTextID)
            XCTAssertEqual(request.initialText, "")
            _ = chart.insertMeasureAtBeginning()
            let cueID = try XCTUnwrap(request.apply(text: "  Keep it light  ", to: &chart))
            let cue = try XCTUnwrap(chart.cueText(id: cueID))
            XCTAssertEqual(cue.anchorMeasureID, measureID, "Other selection/layout changes must not retarget the request")
            XCTAssertEqual(cue.position, .above)
            XCTAssertEqual(cue.beatFraction, request.placement.beatFraction)
            XCTAssertEqual(cue.text, "Keep it light")
            XCTAssertEqual(chart.cueTexts.count, 1)
        }
    }

    func testNewEntryPreservesLegacyNilAnchorAndUsesTargetMeasureMeterWhenSpecified() throws {
        for style in styles {
            var chart = Chart.blank(title: "Target meter", measureCount: 2, layoutStyle: style)
            chart.systems[0].measures[1].meterOverride = Meter(numerator: 6, denominator: 8)
            let measureID = chart.measures[1].id
            let leading = try XCTUnwrap(EditorCueTextEntryRequest.adding(in: chart,
                placement: .init(measureID: measureID, position: nil, beatFraction: nil),
                position: .below, callerTool: .text))
            let leadingID = try XCTUnwrap(leading.apply(text: "Leading default", to: &chart))
            XCTAssertNil(chart.cueText(id: leadingID)?.beatFraction)
            XCTAssertEqual(leading.destinationDescription(in: chart), "Below measure 2")
            let placed = try XCTUnwrap(EditorCueTextEntryRequest.adding(in: chart,
                placement: .init(measureID: measureID, position: nil, beatFraction: 0.10),
                position: .below, callerTool: .text))
            XCTAssertEqual(try XCTUnwrap(placed.placement.beatFraction), 1.0 / 12.0, accuracy: 0.0001)
            XCTAssertEqual(placed.destinationDescription(in: chart), "Below measure 2 · beat 1&")
        }
    }

    func testEditCapturesExactCueAndOriginAndDoesNotResetPlacementOrAppearance() throws {
        for style in styles {
            for caller in [EditorCueTextCallerTool.select, .text] {
                var chart = Chart.blank(title: "Edit exact cue", measureCount: 2, layoutStyle: style)
                let cueID = try XCTUnwrap(chart.addCueText("Original", anchorMeasureID: chart.measures[1].id,
                    position: .above, emphasis: .strong, atFraction: 0.625))
                XCTAssertTrue(chart.updateCueText(cueID, scale: 1.5, verticalOffset: -24))
                let original = chart
                let request = try XCTUnwrap(EditorCueTextEntryRequest.editing(in: chart, cueTextID: cueID, callerTool: caller))
                XCTAssertEqual(chart, original)
                XCTAssertEqual(request.cueTextID, cueID)
                XCTAssertEqual(request.callerTool, caller)
                XCTAssertEqual(request.initialText, "Original")
                XCTAssertEqual(request.destinationDescription(in: chart), "Above measure 2 · beat 3&")
                XCTAssertEqual(request.apply(text: "  Revised cue  ", to: &chart), cueID)
                var expected = try XCTUnwrap(original.cueText(id: cueID))
                expected.text = "Revised cue"
                expected.rawInput = "Revised cue"
                XCTAssertEqual(chart.cueText(id: cueID), expected)
                XCTAssertEqual(chart.measures.map(\.cueTextIDs), original.measures.map(\.cueTextIDs))
            }
        }
    }

    func testStaleChartOrDeletedTargetCannotFallBackToAnotherMeasure() throws {
        for style in styles {
            var chart = Chart.blank(title: "Stale destination", measureCount: 3, layoutStyle: style)
            let target = chart.measures[1].id
            let request = try XCTUnwrap(EditorCueTextEntryRequest.adding(in: chart,
                placement: .init(measureID: target, position: nil, beatFraction: 0.5),
                position: .below, callerTool: .text))
            var otherChart = chart
            otherChart.id = UUID()
            let otherOriginal = otherChart
            XCTAssertNil(request.apply(text: "Keep draft", to: &otherChart))
            XCTAssertEqual(otherChart, otherOriginal)
            XCTAssertEqual(request.destinationDescription(in: otherChart), "Location unavailable")
            XCTAssertTrue(chart.deleteMeasure(id: target))
            let afterDeletion = chart
            XCTAssertNil(request.apply(text: "Keep draft", to: &chart))
            XCTAssertEqual(chart, afterDeletion)
            XCTAssertTrue(chart.cueTexts.isEmpty)
        }
    }

    func testEditDescribesAndPreservesContinuousPlacementOrRowMargin() throws {
        for style in styles {
            var chart = Chart.blank(title: "Free cue destination", measureCount: 2, layoutStyle: style)
            let measureID = chart.measures[0].id
            let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: measureID, position: .above))
            for (region, expected) in [(CueTextHorizontalPlacement.Region.measure, "Above measure 1"),
                                       (.leadingMargin, "Left row margin"), (.trailingMargin, "Right row margin")] {
                let placement = CueTextHorizontalPlacement(region: region, fraction: 0.32, wrapWidth: 120)
                XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.375,
                    horizontalPlacement: placement))
                let request = try XCTUnwrap(EditorCueTextEntryRequest.editing(in: chart,
                    cueTextID: cueID, callerTool: .text))
                XCTAssertEqual(request.destinationDescription(in: chart), expected)
                XCTAssertEqual(request.apply(text: "Edited text", to: &chart), cueID)
                XCTAssertEqual(chart.cueText(id: cueID)?.horizontalPlacement, placement)
            }
        }
    }

    func testDeletedEditingCueDoesNotCreateAnotherCueAndEmptyApplyIsNonDestructive() throws {
        var chart = Chart.blank(title: "Exact cue ID", measureCount: 2)
        let cueID = try XCTUnwrap(chart.addCueText("Original", anchorMeasureID: chart.measures[1].id))
        let request = try XCTUnwrap(EditorCueTextEntryRequest.editing(in: chart, cueTextID: cueID, callerTool: .select))
        let original = chart
        XCTAssertNil(request.apply(text: " \n ", to: &chart))
        XCTAssertEqual(chart, original)
        XCTAssertTrue(chart.deleteCueText(cueID))
        let deleted = chart
        XCTAssertNil(request.apply(text: "Still the original edit", to: &chart))
        XCTAssertEqual(chart, deleted)
        XCTAssertNil(EditorCueTextEntryRequest.editing(in: chart, cueTextID: cueID, callerTool: .select))
    }

    func testMissingMeasureInvalidFractionAndIncompleteSetupCannotStartEntry() {
        let chart = Chart.blank(title: "Invalid target")
        for fraction in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(EditorCueTextEntryRequest.adding(in: chart,
                placement: .init(measureID: chart.measures[0].id, position: nil, beatFraction: fraction),
                position: .above, callerTool: .text))
        }
        XCTAssertNil(EditorCueTextEntryRequest.adding(in: chart,
            placement: .init(measureID: UUID(), position: nil, beatFraction: nil),
            position: .above, callerTool: .text))
        var draft = chart
        draft.hasCompletedInitialSetup = false
        XCTAssertNil(EditorCueTextEntryRequest.adding(in: draft,
            placement: .init(measureID: draft.measures[0].id, position: nil, beatFraction: nil),
            position: .above, callerTool: .text))
    }
}
