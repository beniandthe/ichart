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

    func testClosingRepeatDoesNotConsumeAnEmptyCommittedFollowingMeasure() throws {
        var chart = chartWithEmptyOpenTail()
        let tailID = chart.measures[2].id
        let systemIndex = try XCTUnwrap(chart.systems.firstIndex {
            $0.measures.contains { $0.id == tailID }
        })
        let measureIndex = try XCTUnwrap(chart.systems[systemIndex].measures.firstIndex { $0.id == tailID })
        chart.systems[systemIndex].measures[measureIndex].authoringState = .committed

        try assertRepeatStaysAtItsOwnBoundary(fixture(chart: chart))
    }

    func testClosingRepeatDoesNotConsumeAnOpenTailContainingACue() throws {
        var chart = chartWithEmptyOpenTail()
        XCTAssertNotNil(chart.addCueText("On cue", anchorMeasureID: chart.measures[2].id))
        let fixture = try fixture(chart: chart)
        XCTAssertFalse(try XCTUnwrap(fixture.system.measures.last).cueTextLayouts.isEmpty)

        try assertRepeatStaysAtItsOwnBoundary(fixture)
    }

    func testClosingRepeatDoesNotMoveAcrossAnOpenTailStartingAnotherRepeat() throws {
        var chart = chartWithEmptyOpenTail()
        let tailID = chart.measures[2].id
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
    }

    private func chartWithEmptyOpenTail() -> Chart {
        var chart = Chart.draft(title: "Terminal repeat continuation", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: chart.title,
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 3
        )
        let ids = chart.measures.map(\.id)
        for id in ids {
            _ = chart.setMeasureManualLayoutWidth(96, for: id)
        }
        _ = chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1])
        return chart
    }

    private func fixture(chart: Chart) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1_400)
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
            marker: marker
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
        XCTAssertEqual(repeatFrame, fixture.marker.occupiedFrame, file: file, line: line)
        XCTAssertLessThan(repeatFrame.maxX, try terminalBarlineX(fixture), file: file, line: line)
    }
}
#endif
