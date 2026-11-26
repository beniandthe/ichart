#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class LeadSheetSimpleChordTerminalBarlineGeometryTests: XCTestCase {
    func testClosingRepeatStillUsesRowEndAcrossAnEmptyRealOpenTail() throws {
        let fixture = try fixture(chart: chartWithEmptyOpenTail())
        let tail = try XCTUnwrap(fixture.system.measures.last)
        XCTAssertNotNil(tail.sourceMeasureID)
        XCTAssertTrue(tail.isOpen)
        XCTAssertTrue(tail.chordLayouts.isEmpty)
        XCTAssertFalse(tail.preservesOpenMeasureBoundary,
            "Only an unsized, implicitly continued blank may share the row-end repeat")

        let terminalX = try XCTUnwrap(terminalRepeatX(fixture))
        XCTAssertEqual(terminalX, try terminalBarlineX(fixture), accuracy: 0.001)
        XCTAssertGreaterThan(terminalX, fixture.marker.frame.maxX)
        XCTAssertTrue(LeadSheetSimpleChordTerminalBarlineGeometry
            .usesTerminalBarlineAsTrailingRepeatBoundary(
                for: fixture.system,
                paperFrame: fixture.paperFrame,
                layoutStyle: .simpleChordSheet
            ))
    }

    func testClosingRepeatStillUsesRowEndAcrossSyntheticContinuationFrames() throws {
        var fixture = try fixture(chart: chartWithEmptyOpenTail())
        let tailIndex = try XCTUnwrap(fixture.system.measures.indices.last)
        fixture.system.measures[tailIndex].sourceMeasureID = nil
        fixture.system.measures[tailIndex].isOpen = false

        XCTAssertEqual(
            try XCTUnwrap(terminalRepeatX(fixture)),
            try terminalBarlineX(fixture),
            accuracy: 0.001
        )
    }

    func testSavedManualWidthOpenTailKeepsItsOwnBoundaryAfterReopen() throws {
        var chart = chartWithEmptyOpenTail()
        let tailID = chart.measures[2].id
        XCTAssertNotNil(chart.setMeasureManualLayoutWidth(96, for: tailID))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        let tail = try XCTUnwrap(reopened.measure(id: tailID))
        XCTAssertEqual(tail.manualLayoutWidth, 96)
        XCTAssertFalse(tail.isExplicitlyAddedOpenMeasure,
            "A legacy saved width preserves the boundary without a new insertion flag")
        for size in [CGSize(width: 900, height: 1_400), CGSize(width: 612, height: 792)] {
            let fixture = try fixture(chart: reopened, pageSize: size)
            XCTAssertTrue(try XCTUnwrap(fixture.system.measures.last).preservesOpenMeasureBoundary)
            try assertRepeatStaysAtItsOwnBoundary(fixture)
        }
    }

    func testExplicitlyAddedUnsizedOpenTailKeepsItsOwnBoundaryAfterReopen() throws {
        let chart = chartWithEmptyOpenTail(explicitlyAdded: true)
        let tailID = try XCTUnwrap(chart.measures.last?.id)
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        let tail = try XCTUnwrap(reopened.measure(id: tailID))
        XCTAssertEqual(reopened.measures.count, 3)
        XCTAssertNil(tail.manualLayoutWidth)
        XCTAssertTrue(tail.isExplicitlyAddedOpenMeasure)
        XCTAssertNotEqual(reopened.roadmapObjects.first?.endMeasureID, tailID,
            "Add After Repeat must retain the original repeat endpoint")
        for size in [CGSize(width: 900, height: 1_400), CGSize(width: 612, height: 792)] {
            let fixture = try fixture(chart: reopened, pageSize: size)
            XCTAssertTrue(try XCTUnwrap(fixture.system.measures.last).preservesOpenMeasureBoundary)
            try assertRepeatStaysAtItsOwnBoundary(fixture)
        }
    }

    func testClosingRepeatDoesNotConsumeAnEmptyCommittedFollowingMeasure() throws {
        var chart = chartWithEmptyOpenTail()
        let tailID = chart.measures[2].id
        XCTAssertNotNil(chart.setMeasureManualLayoutWidth(96, for: tailID))
        let systemIndex = try XCTUnwrap(chart.systems.firstIndex {
            $0.measures.contains { $0.id == tailID }
        })
        let measureIndex = try XCTUnwrap(chart.systems[systemIndex].measures.firstIndex { $0.id == tailID })
        chart.systems[systemIndex].measures[measureIndex].authoringState = .committed

        try assertRepeatStaysAtItsOwnBoundary(fixture(chart: chart))
    }

    func testClosingRepeatDoesNotConsumeAnOpenTailContainingACue() throws {
        var chart = chartWithEmptyOpenTail()
        XCTAssertNotNil(chart.setMeasureManualLayoutWidth(96, for: chart.measures[2].id))
        XCTAssertNotNil(chart.addCueText("On cue", anchorMeasureID: chart.measures[2].id))
        let fixture = try fixture(chart: chart)
        XCTAssertFalse(try XCTUnwrap(fixture.system.measures.last).cueTextLayouts.isEmpty)

        try assertRepeatStaysAtItsOwnBoundary(fixture)
    }

    func testClosingRepeatDoesNotMoveAcrossAnOpenTailStartingAnotherRepeat() throws {
        var chart = chartWithEmptyOpenTail()
        let tailID = chart.measures[2].id
        XCTAssertNotNil(chart.setMeasureManualLayoutWidth(96, for: tailID))
        XCTAssertNotNil(chart.addRepeatSpan(startMeasureID: tailID, endMeasureID: tailID))
        let fixture = try fixture(chart: chart)
        XCTAssertFalse(try XCTUnwrap(fixture.system.measures.last).repeatMarkerLayouts.isEmpty)

        try assertRepeatStaysAtItsOwnBoundary(fixture)
    }

    private struct Fixture {
        var system: LeadSheetSystemLayout
        var paperFrame: CGRect
        var repeatedMeasure: LeadSheetMeasureLayout
        var marker: LeadSheetRepeatMarkerLayout
        var repeatSeparation: CGFloat
    }

    private func chartWithEmptyOpenTail(explicitlyAdded: Bool = false) -> Chart {
        var chart = Chart.draft(title: "Terminal repeat continuation", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: chart.title,
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: explicitlyAdded ? 2 : 3
        )
        let ids = chart.measures.map(\.id)
        // Size the repeated measures, not the implicit blank continuation.
        for id in ids.prefix(2) {
            _ = chart.setMeasureManualLayoutWidth(96, for: id)
        }
        _ = chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1])
        if explicitlyAdded {
            XCTAssertNotNil(chart.insertOneMeasureAfterForEditing(ids[1]))
        }
        return chart
    }

    private func fixture(chart: Chart, pageSize: CGSize = CGSize(width: 900, height: 1_400)) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize
        )
        let repeatedID = chart.measures[1].id
        let system = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.id == repeatedID } })
        XCTAssertEqual(system.measures.compactMap(\.sourceMeasureID), chart.measures.map(\.id))
        let repeatedMeasure = try XCTUnwrap(system.measures.first { $0.id == repeatedID })
        let marker = try XCTUnwrap(repeatedMeasure.repeatMarkerLayouts.first { $0.edge == .trailing })
        return Fixture(
            system: system,
            paperFrame: layout.paperFrame(for: system),
            repeatedMeasure: repeatedMeasure,
            marker: marker,
            repeatSeparation: LeadSheetRepeatReadabilityMetrics(chart: chart,
                staffHeight: marker.frame.height).separation
        )
    }

    private func terminalRepeatX(_ fixture: Fixture) -> CGFloat? {
        LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
            after: fixture.repeatedMeasure,
            in: fixture.system,
            paperFrame: fixture.paperFrame,
            layoutStyle: .simpleChordSheet
        )
    }

    private func terminalBarlineX(_ fixture: Fixture) throws -> CGFloat {
        try XCTUnwrap(LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
            for: fixture.system,
            paperFrame: fixture.paperFrame,
            layoutStyle: .simpleChordSheet
        )).midX
    }

    private func assertRepeatStaysAtItsOwnBoundary(
        _ fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertNil(terminalRepeatX(fixture), file: file, line: line)
        let repeatFrame = LeadSheetSimpleChordTerminalBarlineGeometry.renderedRepeatMarkerFrame(
            fixture.marker,
            after: fixture.repeatedMeasure,
            in: fixture.system,
            paperFrame: fixture.paperFrame,
            layoutStyle: .simpleChordSheet
        )
        let repeatedIndex = try XCTUnwrap(fixture.system.measures.firstIndex {
            $0.id == fixture.repeatedMeasure.id
        }, file: file, line: line)
        let following = try XCTUnwrap(fixture.system.measures.dropFirst(repeatedIndex + 1).first,
            file: file, line: line)
        let boundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
            after: fixture.repeatedMeasure, before: following, excludingRepeatMarkerIDs: [],
            in: fixture.system, paperFrame: fixture.paperFrame, layoutStyle: .simpleChordSheet)
        guard case .repeatBoundary(let markers, let closingLineX) = boundary else {
            return XCTFail("The repeat must retain its rendered closing boundary", file: file, line: line)
        }
        XCTAssertTrue(markers.contains { $0.id == fixture.marker.id }, file: file, line: line)
        if following.isOpen && following.preservesOpenMeasureBoundary {
            XCTAssertEqual(try XCTUnwrap(closingLineX, file: file, line: line),
                following.leadingBarlineX, accuracy: 0.001, file: file, line: line)
            // Standard readability deliberately leaves the optional override
            // absent. The chart's repeat metrics still define both strokes.
            let separation = fixture.repeatSeparation
            XCTAssertGreaterThan(separation, 0, file: file, line: line)
            XCTAssertEqual(repeatFrame.midX + separation / 2, following.leadingBarlineX,
                accuracy: 0.001, "The outside repeat stroke is the following measure's left barline",
                file: file, line: line)
            XCTAssertEqual(repeatFrame.size, fixture.marker.occupiedFrame.size, file: file, line: line)
            XCTAssertEqual(repeatFrame.minY, fixture.marker.occupiedFrame.minY,
                accuracy: 0.001, file: file, line: line)
        } else {
            XCTAssertNil(closingLineX, file: file, line: line)
            XCTAssertEqual(repeatFrame, fixture.marker.occupiedFrame, file: file, line: line)
        }
        XCTAssertLessThan(repeatFrame.maxX, following.trailingBarlineFrame.midX,
            "The closing repeat cannot consume the following real measure", file: file, line: line)
        XCTAssertLessThan(repeatFrame.maxX, try terminalBarlineX(fixture), file: file, line: line)
    }
}
#endif
