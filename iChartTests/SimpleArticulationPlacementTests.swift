import CoreGraphics
import Foundation
import XCTest
@testable import iChart

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
#endif

final class SimpleArticulationPlacementTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_100)

    func testSimpleAttachmentUsesNearestVisibleChordAndRejectsEmptyMeasureOrRawInk() throws {
        let fixture = try makeFixture()
        let layout = pageLayout(fixture.chart)
        for chordID in [fixture.firstID, fixture.secondID] {
            let chord = try chordLayout(chordID, in: layout)
            let point = CGPoint(x: chord.frame.midX, y: chord.frame.midY)
            let match = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
                near: point, chart: fixture.chart, pageLayout: layout))
            XCTAssertEqual(match.attachment, .chord(id: chordID))
            XCTAssertEqual(match.measureID, fixture.chart.measures[0].id)
            XCTAssertEqual(match.guidePoint, CGPoint(x: chord.frame.midX, y: chord.frame.minY))
        }

        let emptyID = fixture.chart.measures[1].id
        let empty = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == emptyID })
        let point = CGPoint(x: empty.frame.midX, y: empty.frame.midY)
        let handwriting = CGRect(x: point.x - 3, y: point.y - 4, width: 6, height: 8)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: point, chart: fixture.chart,
            pageLayout: layout, staffInkBounds: [handwriting], allowsBareStaff: true))
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: point, chart: fixture.chart,
            pageLayout: layout, staffInkBounds: [handwriting], allowsBareStaff: false,
            staffInkVerticalAllowance: 100))
    }

    func testSimpleGuideRetainsOverlappingChordUntilItLeavesThatChordHitbox() throws {
        let fixture = try makeFixture()
        var layout = pageLayout(fixture.chart)
        let first = try chordLayout(fixture.firstID, in: layout)
        let systemIndex = try XCTUnwrap(layout.systems.firstIndex {
            $0.measures.contains { $0.chordLayouts.contains { $0.id == fixture.secondID } }
        })
        let measureIndex = try XCTUnwrap(layout.systems[systemIndex].measures.firstIndex {
            $0.chordLayouts.contains { $0.id == fixture.secondID }
        })
        let chordIndex = try XCTUnwrap(layout.systems[systemIndex].measures[measureIndex].chordLayouts.firstIndex {
            $0.id == fixture.secondID
        })
        var second = try chordLayout(fixture.secondID, in: layout)
        second.frame = first.frame.offsetBy(dx: first.frame.width * 0.7, dy: 0)
        second.fitFrame = second.frame
        second.naturalFrame = second.frame
        second.renderFontSize = first.renderFontSize
        second.baseFontSize = first.baseFontSize
        layout.systems[systemIndex].measures[measureIndex].chordLayouts[chordIndex] = second
        let acquired = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: CGPoint(x: first.frame.midX, y: first.frame.midY), chart: fixture.chart, pageLayout: layout))
        XCTAssertEqual(acquired.attachment, .chord(id: fixture.firstID))
        let points = stride(from: first.frame.midX, through: second.frame.maxX + 100, by: 0.5).map {
            CGPoint(x: $0, y: first.frame.midY)
        }
        let overlap = try XCTUnwrap(points.first {
            acquired.retains(at: $0) && FreeInkArticulationPlacement.attachment(
                near: $0, chart: fixture.chart, pageLayout: layout)?.attachment == .chord(id: fixture.secondID)
        })
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(near: overlap, chart: fixture.chart,
            pageLayout: layout, retaining: acquired), acquired)
        let beyondFirst = try XCTUnwrap(points.first {
            !acquired.retains(at: $0) && FreeInkArticulationPlacement.attachment(
                near: $0, chart: fixture.chart, pageLayout: layout)?.attachment == .chord(id: fixture.secondID)
        })
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(near: beyondFirst, chart: fixture.chart,
            pageLayout: layout, retaining: acquired)?.attachment, .chord(id: fixture.secondID))
        let beyondBoth = CGPoint(x: second.frame.maxX + 200, y: first.frame.midY)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: beyondBoth, chart: fixture.chart,
            pageLayout: layout, retaining: acquired))
    }

    func testSimpleStackedMarksFollowMovedChordAndReflowWithoutChangingSourceFields() throws {
        let fixture = try makeFixture()
        var chart = fixture.chart
        let initialLayout = pageLayout(chart)
        chart.freeInkArticulations = try marks(attachedTo: fixture.firstID, chart: chart, layout: initialLayout)
        let originalMarks = chart.freeInkArticulations
        let initialTargets = try targets(in: chart, layout: initialLayout)
        let initialChord = try chordLayout(fixture.firstID, in: initialLayout)
        XCTAssertLessThan(initialTargets[0].markFrame.maxY, initialChord.frame.minY)
        XCTAssertLessThan(initialTargets[1].markFrame.maxY, initialTargets[0].markFrame.minY)
        let destination = chart.measures[2].id
        XCTAssertTrue(chart.moveChordEvent(fixture.firstID, to: destination, atFraction: 0.65))
        XCTAssertTrue(chart.insertSystemBreak(before: destination))
        chart.setEngravingPreset(.compact)
        let movedLayout = pageLayout(chart)
        let movedChord = try chordLayout(fixture.firstID, in: movedLayout)
        let movedTargets = try targets(in: chart, layout: movedLayout)
        for target in movedTargets {
            XCTAssertEqual(target.measureID, destination)
            XCTAssertEqual(target.center.x, movedChord.frame.midX, accuracy: 0.01)
            XCTAssertLessThan(target.markFrame.maxY, movedChord.frame.minY)
        }
        XCTAssertGreaterThan(movedTargets[0].center.y, initialTargets[0].center.y)
        XCTAssertLessThan(movedTargets[1].markFrame.maxY, movedTargets[0].markFrame.minY)
        assertSourceFields(chart.freeInkArticulations, equal: originalMarks)
    }

    func testSimpleSymbolMetricUsesVisibleChordFontAndIgnoresStaffLinesAndHorizontalCompression() throws {
        let fixture = try makeFixture()
        var chart = fixture.chart
        let layout = pageLayout(chart)
        chart.freeInkArticulations = try marks(attachedTo: fixture.firstID, chart: chart, layout: layout)
        let mark = try XCTUnwrap(chart.freeInkArticulations.first)
        let initial = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout))
        var fakeStaffLayout = layout
        for index in fakeStaffLayout.systems.indices {
            fakeStaffLayout.systems[index].staffLineYPositions = [1, 101, 201, 301, 401]
        }
        XCTAssertEqual(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: fakeStaffLayout), initial)
        for index in fakeStaffLayout.systems.indices {
            fakeStaffLayout.systems[index].staffLineYPositions = []
        }
        XCTAssertEqual(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: fakeStaffLayout), initial)

        XCTAssertEqual(chart.setChordEventManualHorizontalScale(0.5, for: fixture.firstID), 0.5)
        let compressedLayout = pageLayout(chart)
        let compressedChord = try chordLayout(fixture.firstID, in: compressedLayout)
        let naturalChord = try chordLayout(fixture.firstID, in: layout)
        XCTAssertLessThan(compressedChord.frame.width, naturalChord.frame.width)
        XCTAssertEqual(compressedChord.renderFontSize, naturalChord.renderFontSize)
        let compressed = try XCTUnwrap(FreeInkArticulationPlacement.target(
            for: mark, chart: chart, pageLayout: compressedLayout))
        XCTAssertEqual(compressed.center.x, compressedChord.frame.midX, accuracy: 0.01)
        XCTAssertEqual(compressed.staffSpace, initial.staffSpace, accuracy: 0.01)
        XCTAssertEqual(compressed.markFrame.size, initial.markFrame.size)

        var largeLayout = compressedLayout
        for systemIndex in largeLayout.systems.indices {
            for measureIndex in largeLayout.systems[systemIndex].measures.indices {
                let index = largeLayout.systems[systemIndex].measures[measureIndex].chordLayouts.firstIndex {
                    $0.id == fixture.firstID
                }
                guard let index else { continue }
                var largeChord = compressedChord
                largeChord.frame = CGRect(x: compressedChord.frame.minX, y: compressedChord.frame.minY,
                    width: compressedChord.frame.width, height: compressedChord.frame.height * 2)
                largeChord.renderFontSize = (compressedChord.renderFontSize ?? compressedChord.baseFontSize) * 2
                largeChord.baseFontSize *= 2
                largeLayout.systems[systemIndex].measures[measureIndex].chordLayouts[index] = largeChord
            }
        }
        let larger = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: largeLayout))
        XCTAssertGreaterThan(larger.markFrame.height, compressed.markFrame.height)
        XCTAssertEqual(larger.center.x, compressedChord.frame.midX, accuracy: 0.01)
    }

    func testSimpleDeletionKeepsMovedStackedMarksAtTheirLastDisplayedPagePoints() throws {
        let fixture = try makeFixture()
        var chart = fixture.chart
        chart.freeInkArticulations = try marks(attachedTo: fixture.firstID, chart: chart, layout: pageLayout(chart))
        let originalMarks = chart.freeInkArticulations
        let destination = chart.measures[2].id
        XCTAssertTrue(chart.moveChordEvent(fixture.firstID, to: destination, atFraction: 0.65))
        XCTAssertTrue(chart.insertSystemBreak(before: destination))
        let movedLayout = pageLayout(chart)
        let displayed = try targets(in: chart, layout: movedLayout)
        chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: chart, pageLayout: movedLayout)
        for (mark, target) in zip(chart.freeInkArticulations, displayed) {
            let point = try XCTUnwrap(mark.pagePoint)
            let savedCenter = try XCTUnwrap(FreeInkArticulationPlacement.center(for: point, pageLayout: movedLayout))
            XCTAssertEqual(savedCenter.x, target.center.x, accuracy: 0.01)
            XCTAssertEqual(savedCenter.y, target.center.y, accuracy: 0.01)
        }
        XCTAssertTrue(chart.deleteChordEvent(fixture.firstID))
        let deletedLayout = pageLayout(chart)
        let floating = try targets(in: chart, layout: deletedLayout)
        XCTAssertEqual(chart.freeInkArticulations.map(\.attachment), [nil, nil])
        for (before, after) in zip(displayed, floating) {
            XCTAssertNil(after.measureID)
            XCTAssertEqual(after.center.x, before.center.x, accuracy: 0.01)
            XCTAssertEqual(after.center.y, before.center.y, accuracy: 0.01)
        }
        assertSourceFields(chart.freeInkArticulations, equal: originalMarks)
    }

    #if canImport(UIKit) && canImport(PencilKit)
    func testSimpleSnapshotKeepsLegacySourcePointSeparateFromDraggedChordTarget() throws {
        let fixture = try makeFixture()
        var chart = fixture.chart
        let destination = chart.measures[2].id
        let symbol = try XCTUnwrap(ChordRecognitionCompendium.match("F"))
        XCTAssertTrue(chart.appendRecognizedChord(symbol.symbol, rawInput: "F", to: destination, atFraction: 0.25))
        let targetID = try XCTUnwrap(chart.measure(id: destination)?.chordEvents.first?.id)
        let layout = pageLayout(chart)
        let sourceFrame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let sourceChord = try chordLayout(fixture.firstID, in: layout)
        let origin = CGPoint(x: sourceChord.frame.midX - sourceFrame.minX,
            y: sourceChord.frame.minY - 24 - sourceFrame.minY)
        let path = PKStrokePath(controlPoints: [origin, CGPoint(x: origin.x + 8, y: origin.y - 4),
            CGPoint(x: origin.x + 16, y: origin.y)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 123))
        let source = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: 123)])
        let bytes = source.dataRepresentation()
        var sourceSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: sourceFrame))
        let sourceMeasureID = try XCTUnwrap(chart.measureContainingChordEvent(id: fixture.firstID)?.id)
        sourceSpace.measureAnchors = sourceSpace.measureAnchors?.filter { $0.measureID == sourceMeasureID }
        sourceSpace.chordAnchors = nil
        let mark = FreeInkArticulation(kind: .fermata, measureID: destination, sourceInkData: bytes,
            sourceCoordinateSpace: sourceSpace, attachment: .chord(id: targetID))
        chart.freeInkArticulations = [mark]
        let displayed = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout))
        chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: chart, pageLayout: layout)
        let captured = try XCTUnwrap(chart.freeInkArticulations.first)
        let sourcePoint = try XCTUnwrap(captured.sourcePagePoint)
        let actualSource = try XCTUnwrap(FreeInkArticulationPlacement.center(for: sourcePoint, pageLayout: layout))
        XCTAssertEqual(actualSource.x, source.bounds.midX + sourceFrame.minX, accuracy: 0.01)
        XCTAssertEqual(actualSource.y, source.bounds.midY + sourceFrame.minY, accuracy: 0.01)
        let fallback = try XCTUnwrap(captured.pagePoint)
        let actualFallback = try XCTUnwrap(FreeInkArticulationPlacement.center(for: fallback, pageLayout: layout))
        XCTAssertEqual(actualFallback.x, displayed.center.x, accuracy: 0.01)
        XCTAssertEqual(actualFallback.y, displayed.center.y, accuracy: 0.01)
        XCTAssertNotEqual(sourcePoint, fallback)

        XCTAssertTrue(chart.moveChordEvent(targetID, to: chart.measures[1].id, atFraction: 0.4))
        let movedLayout = pageLayout(chart)
        let movedTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(for: captured, chart: chart, pageLayout: movedLayout))
        chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: chart, pageLayout: movedLayout)
        let updated = try XCTUnwrap(chart.freeInkArticulations.first)
        XCTAssertEqual(updated.sourcePagePoint, sourcePoint)
        XCTAssertEqual(updated.sourceInkData, bytes)
        XCTAssertEqual(updated.sourceCoordinateSpace, sourceSpace)
        let movedFallback = try XCTUnwrap(FreeInkArticulationPlacement.center(
            for: XCTUnwrap(updated.pagePoint), pageLayout: movedLayout))
        XCTAssertEqual(movedFallback.x, movedTarget.center.x, accuracy: 0.01)
        XCTAssertEqual(movedFallback.y, movedTarget.center.y, accuracy: 0.01)
    }
    #endif

    private func pageLayout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
    }

    private func chordLayout(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetChordLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).first { $0.id == id })
    }

    private func marks(attachedTo chordID: UUID, chart: Chart, layout: LeadSheetPageLayout) throws -> [FreeInkArticulation] {
        let measure = try XCTUnwrap(chart.measureContainingChordEvent(id: chordID))
        let authoredPoint = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(
            at: CGPoint(x: layout.paperFrame.midX, y: layout.paperFrame.maxY - 100), pageLayout: layout))
        return [FreeInkArticulationKind.fermata, .accent].enumerated().map { index, kind in
            FreeInkArticulation(kind: kind, measureID: measure.id, sourceInkData: Data([0x81, UInt8(index), 0x42]),
                sourceCoordinateSpace: PersistentInkCoordinateSpace(width: 800, height: 1_100),
                attachment: .chord(id: chordID), pagePoint: authoredPoint, sourcePagePoint: authoredPoint)
        }
    }

    private func targets(in chart: Chart, layout: LeadSheetPageLayout) throws -> [FreeInkArticulationPlacement.Target] {
        try chart.freeInkArticulations.map {
            try XCTUnwrap(FreeInkArticulationPlacement.target(for: $0, chart: chart, pageLayout: layout))
        }
    }

    private func assertSourceFields(_ actual: [FreeInkArticulation], equal expected: [FreeInkArticulation],
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.map(\.id), expected.map(\.id), file: file, line: line)
        XCTAssertEqual(actual.map(\.kind), expected.map(\.kind), file: file, line: line)
        XCTAssertEqual(actual.map(\.sourceInkData), expected.map(\.sourceInkData), file: file, line: line)
        XCTAssertEqual(actual.map(\.sourceCoordinateSpace), expected.map(\.sourceCoordinateSpace), file: file, line: line)
        XCTAssertEqual(actual.map(\.sourcePagePoint), expected.map(\.sourcePagePoint), file: file, line: line)
    }

    private func makeFixture() throws -> (chart: Chart, firstID: UUID, secondID: UUID) {
        var chart = Chart.draft(title: "Simple articulation placement", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 3)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        for (text, fraction) in [("Cmaj7", 0.0), ("G7", 0.75)] {
            let match = try XCTUnwrap(ChordRecognitionCompendium.match(text))
            XCTAssertTrue(chart.appendRecognizedChord(match.symbol, rawInput: text,
                to: measureID, atFraction: fraction))
        }
        let events = try XCTUnwrap(chart.measure(id: measureID)).chordEvents
        XCTAssertEqual(events.count, 2)
        return (chart, try XCTUnwrap(events.first?.id), try XCTUnwrap(events.last?.id))
    }
}
