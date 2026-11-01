#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class LeadSheetEndingDragPolicyTests: XCTestCase {
    func testMovePreservesCountAcrossRowsInEveryLayoutAndKeepsUnrelatedChartData() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try fixture(style: style, count: 9, range: 1...3)
            let start = try point(in: fixture, measure: 1, fraction: 0.5)
            let destination = try point(in: fixture, measure: 5, fraction: 0.5)
            let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: .move, startLocation: start,
                sourcePageLayout: fixture.layout, sourceSystemIndex: try row(in: fixture, measure: 1).index))
            XCTAssertEqual(session.previewRange(at: start), 1...3)
            XCTAssertEqual(session.previewRange(at: destination), 5...7, style.rawValue)
            let preview = try XCTUnwrap(session.previewChart(at: destination))
            let committed = try XCTUnwrap(session.committedChart(at: destination, currentChart: fixture.chart))
            assertEnding(in: committed, id: fixture.endingID, range: 5...7)
            assertNonEndingContentEqual(fixture.chart, committed, endingID: fixture.endingID)
            XCTAssertEqual(session.sourceChart, fixture.chart)
            XCTAssertEqual(preview.roadmapObject(id: fixture.endingID), committed.roadmapObject(id: fixture.endingID))
            let ending = try XCTUnwrap(committed.roadmapObject(id: fixture.endingID))
            let original = try XCTUnwrap(fixture.chart.roadmapObject(id: fixture.endingID))
            XCTAssertEqual(ending.displayText, original.displayText)
            XCTAssertEqual(ending.endingEndStyle, original.endingEndStyle)
            XCTAssertEqual(ending.rawInput, original.rawInput)
            XCTAssertEqual(ending.sourceInkData, original.sourceInkData)
            XCTAssertEqual(ending.type, original.type)
        }
    }

    func testMoveClampsAtChartEndsWithoutChangingMeasureCount() throws {
        let fixture = try fixture(count: 8, range: 2...4)
        let start = try point(in: fixture, measure: 2, fraction: 0.5)
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
            endingID: fixture.endingID, action: .move, startLocation: start, sourcePageLayout: fixture.layout))
        XCTAssertEqual(session.previewRange(at: CGPoint(x: -100_000, y: start.y)), 0...2)
        let last = try row(in: fixture, measure: 7)
        XCTAssertEqual(session.previewRange(at: CGPoint(x: 100_000, y: last.frame.midY)), 5...7)
        XCTAssertEqual(session.previewRange(at: CGPoint(x: CGFloat.greatestFiniteMagnitude,
            y: last.frame.midY)), 5...7)
    }

    func testMoveFromContinuationFragmentAndHandleAboveBandHasNoInitialJump() throws {
        let fixture = try fixture(count: 12, range: 1...7)
        let sourceRow = try row(in: fixture, measure: 5)
        let targetRow = try row(in: fixture, measure: 8)
        let sourcePoint = try point(in: fixture, measure: 5, fraction: 0.5)
        let start = CGPoint(x: sourcePoint.x, y: sourceRow.frame.minY - 60)
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
            endingID: fixture.endingID, action: .move, startLocation: start,
            sourcePageLayout: fixture.layout, sourceSystemIndex: sourceRow.index))
        XCTAssertEqual(session.previewRange(at: start), 1...7)
        XCTAssertEqual(session.previewChart(at: start), fixture.chart)
        let targetPoint = try point(in: fixture, measure: 8, fraction: 0.5)
        let destination = CGPoint(x: targetPoint.x,
            y: targetRow.frame.midY + start.y - sourceRow.frame.midY)
        XCTAssertEqual(session.previewRange(at: destination), 4...10)
    }

    func testLengthChangesOnlyRightEndpointAcrossRowsAndClampsToOneMeasure() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try fixture(style: style, count: 12, range: 1...2)
            let sourceRow = try row(in: fixture, measure: 2)
            let endFrame = try measure(in: fixture, index: 2).staffFrame
            let start = CGPoint(x: endFrame.maxX + 26, y: sourceRow.frame.minY - 44)
            let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: .resizeTrailing, startLocation: start,
                sourcePageLayout: fixture.layout, sourceSystemIndex: sourceRow.index))
            XCTAssertEqual(session.previewRange(at: start), 1...2, style.rawValue)
            let targetRow = try row(in: fixture, measure: 8)
            let target = try measure(in: fixture, index: 8).staffFrame
            let destination = CGPoint(x: target.maxX + 26,
                y: targetRow.frame.midY + start.y - sourceRow.frame.midY)
            XCTAssertEqual(session.previewRange(at: destination), 1...8, style.rawValue)
            let shortened = CGPoint(x: -100_000, y: start.y)
            XCTAssertEqual(session.previewRange(at: shortened), 1...1)
            let lastRow = try row(in: fixture, measure: 11)
            let extended = CGPoint(x: 100_000,
                y: lastRow.frame.midY + start.y - sourceRow.frame.midY)
            XCTAssertEqual(session.previewRange(at: extended), 1...11)
            let committed = try XCTUnwrap(session.committedChart(at: destination, currentChart: fixture.chart))
            assertEnding(in: committed, id: fixture.endingID, range: 1...8)
            assertNonEndingContentEqual(fixture.chart, committed, endingID: fixture.endingID)
        }
    }

    func testLengthTargetsRealMeasuresAcrossUnrolledPages() throws {
        let fixture = try fixture(count: 48, range: 1...2, pageSize: CGSize(width: 900, height: 700))
        XCTAssertGreaterThan(fixture.layout.pages.count, 1)
        let sourceRow = try row(in: fixture, measure: 2)
        let end = try measure(in: fixture, index: 2).staffFrame
        let start = CGPoint(x: end.maxX + 22, y: sourceRow.frame.minY - 38)
        let targetRow = try row(in: fixture, measure: 40)
        let sourcePaper = try XCTUnwrap(fixture.layout.pages.first { $0.systemIDs.contains(sourceRow.id) })
        let targetPaper = try XCTUnwrap(fixture.layout.pages.first { $0.systemIDs.contains(targetRow.id) })
        XCTAssertGreaterThan(targetPaper.index, sourcePaper.index)
        XCTAssertGreaterThan(targetRow.frame.minY, sourcePaper.frame.maxY)
        let target = try measure(in: fixture, index: 40).staffFrame
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
            endingID: fixture.endingID, action: .resizeTrailing, startLocation: start,
            sourcePageLayout: fixture.layout, sourceSystemIndex: sourceRow.index))
        let destination = CGPoint(x: target.maxX + 22,
            y: targetRow.frame.midY + start.y - sourceRow.frame.midY)
        XCTAssertEqual(session.previewRange(at: destination), 1...40)
        let committed = try XCTUnwrap(session.committedChart(at: destination, currentChart: fixture.chart))
        assertEnding(in: committed, id: fixture.endingID, range: 1...40)
    }

    func testNoopPreservesLegacyNilFieldsOriginalInkAndTimestamp() throws {
        var fixture = try fixture(count: 6, range: 3...3)
        let index = try XCTUnwrap(fixture.chart.roadmapObjects.firstIndex { $0.id == fixture.endingID })
        fixture.chart.roadmapObjects[index].endMeasureID = nil
        fixture.chart.roadmapObjects[index].anchorSystemID = nil
        fixture.chart.roadmapObjects[index].displayText = nil
        fixture.chart.roadmapObjects[index].endingEndStyle = nil
        fixture.chart.updatedAt = Date(timeIntervalSince1970: 123)
        fixture.layout = layout(fixture.chart)
        let sourceRow = try row(in: fixture, measure: 3)
        let frame = try measure(in: fixture, index: 3).staffFrame
        for action in [RenderedEditAction.move, .resizeTrailing] {
            let start = CGPoint(x: frame.maxX + 30, y: sourceRow.frame.minY - 52)
            let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: action, startLocation: start,
                sourcePageLayout: fixture.layout, sourceSystemIndex: sourceRow.index))
            XCTAssertEqual(session.previewRange(at: start), 3...3)
            XCTAssertEqual(session.previewChart(at: start), fixture.chart)
            XCTAssertNil(session.committedChart(at: start, currentChart: fixture.chart))
            XCTAssertNil(session.previewChart(at: start)?.roadmapObject(id: fixture.endingID)?.endMeasureID)
            XCTAssertNil(session.previewChart(at: start)?.roadmapObject(id: fixture.endingID)?.anchorSystemID)
            XCTAssertEqual(session.previewChart(at: start)?.updatedAt, fixture.chart.updatedAt)
        }
    }

    func testCommitRejectsStaleNotationTopologyEndingAndInkSnapshotsWithoutOverwriting() throws {
        let fixture = try fixture(count: 9, range: 1...3)
        let start = try point(in: fixture, measure: 1, fraction: 0.5)
        let destination = try point(in: fixture, measure: 5, fraction: 0.5)
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
            endingID: fixture.endingID, action: .move, startLocation: start, sourcePageLayout: fixture.layout))
        var variants: [Chart] = []
        var changed = fixture.chart
        changed.title += " changed"
        variants.append(changed)
        changed = fixture.chart
        changed.updatedAt = changed.updatedAt.addingTimeInterval(1)
        variants.append(changed)
        changed = fixture.chart
        changed.pageHandwrittenChordData?.append(255)
        variants.append(changed)
        changed = fixture.chart
        changed.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 901, height: 1_400)
        variants.append(changed)
        changed = fixture.chart
        let objectIndex = try XCTUnwrap(changed.roadmapObjects.firstIndex { $0.id == fixture.endingID })
        changed.roadmapObjects[objectIndex].displayText = "On cue"
        variants.append(changed)
        changed = fixture.chart
        changed.roadmapObjects[objectIndex].sourceInkData?.append(1)
        variants.append(changed)
        changed = fixture.chart
        changed.systems[0].measures.swapAt(0, 1)
        variants.append(changed)
        changed = fixture.chart
        _ = changed.deleteRoadmapObject(fixture.endingID)
        variants.append(changed)
        changed = fixture.chart
        _ = changed.appendMeasure()
        variants.append(changed)
        changed = fixture.chart
        changed.layoutStyle = .leadSheet
        variants.append(changed)
        for stale in variants {
            let before = stale
            XCTAssertNil(session.committedChart(at: destination, currentChart: stale))
            XCTAssertEqual(stale, before)
        }
        XCTAssertNotNil(session.committedChart(at: destination, currentChart: fixture.chart))
    }

    func testInvalidActionsGeometryAndMissingEndingCannotBegin() throws {
        let fixture = try fixture(count: 6, range: 1...2)
        let start = try point(in: fixture, measure: 1, fraction: 0.5)
        for action in [RenderedEditAction.select, .resizeLeading, .editText, .delete] {
            XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: action, startLocation: start, sourcePageLayout: fixture.layout))
        }
        XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart, endingID: UUID(), action: .move,
            startLocation: start, sourcePageLayout: fixture.layout))
        XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart, endingID: fixture.endingID, action: .move,
            startLocation: CGPoint(x: CGFloat.nan, y: 0), sourcePageLayout: fixture.layout))
        var incomplete = fixture.layout
        incomplete.systems[0].measures.removeFirst()
        XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart, endingID: fixture.endingID, action: .move,
            startLocation: start, sourcePageLayout: incomplete))
        var invalid = fixture.layout
        invalid.systems[0].measures[0].staffFrame.size.width = 0
        XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart, endingID: fixture.endingID, action: .move,
            startLocation: start, sourcePageLayout: invalid))
        XCTAssertNil(LeadSheetEndingDragSession(chart: fixture.chart, endingID: fixture.endingID, action: .move,
            startLocation: start, sourcePageLayout: fixture.layout, sourceSystemIndex: 9_999))
    }

    func testNonfiniteUpdatesCannotPreviewOrCommit() throws {
        let fixture = try fixture(count: 6, range: 1...2)
        let start = try point(in: fixture, measure: 1, fraction: 0.5)
        for action in [RenderedEditAction.move, .resizeTrailing] {
            let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: action, startLocation: start, sourcePageLayout: fixture.layout))
            for point in [CGPoint(x: CGFloat.nan, y: 10), CGPoint(x: 10, y: CGFloat.nan),
                          CGPoint(x: CGFloat.infinity, y: 10), CGPoint(x: 10, y: -CGFloat.infinity)] {
                XCTAssertNil(session.previewRange(at: point))
                XCTAssertNil(session.previewChart(at: point))
                XCTAssertNil(session.committedChart(at: point, currentChart: fixture.chart))
            }
        }
    }

    func testSyntheticWritingRowsNeverCreateMeasuresOrTargets() throws {
        var chart = Chart.draft(title: "Real measure only", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let id = try XCTUnwrap(chart.measures.first?.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: id, endMeasureID: id,
            displayText: "On cue", endStyle: .open))
        let page = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_400),
            includesChordInkContinuationLanes: true)
        let source = try XCTUnwrap(page.systems.first { $0.measures.contains { $0.sourceMeasureID == id } })
        let real = try XCTUnwrap(source.measures.first { $0.sourceMeasureID == id })
        let synthetic = try XCTUnwrap(page.systems.first { $0.measures.allSatisfy { $0.sourceMeasureID == nil } })
        let start = CGPoint(x: real.staffFrame.midX, y: source.frame.midY)
        XCTAssertNil(LeadSheetEndingDragSession(chart: chart, endingID: endingID, action: .move,
            startLocation: start, sourcePageLayout: page, sourceSystemIndex: synthetic.index))
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: chart, endingID: endingID, action: .move,
            startLocation: start, sourcePageLayout: page, sourceSystemIndex: source.index))
        let target = CGPoint(x: synthetic.frame.maxX + 100, y: synthetic.frame.midY)
        XCTAssertEqual(session.previewRange(at: target), 0...0)
        XCTAssertNil(session.committedChart(at: target, currentChart: chart))
        XCTAssertEqual(session.sourceChart.measures.count, 1)
    }

    func testVeryShortOverlappingEndingMovesOnlyTheSelectedIdentity() throws {
        var fixture = try fixture(count: 6, range: 2...2)
        let other = try XCTUnwrap(fixture.chart.addEndingSpan(.ending2,
            startMeasureID: fixture.chart.measures[2].id, endMeasureID: fixture.chart.measures[2].id,
            displayText: "On cue", endStyle: .closed))
        let otherBefore = fixture.chart.roadmapObject(id: other)
        fixture.layout = layout(fixture.chart)
        let sourceRow = try row(in: fixture, measure: 2)
        let rowIndex = try XCTUnwrap(fixture.layout.systems.firstIndex { $0.index == sourceRow.index })
        let index = try XCTUnwrap(fixture.layout.systems[rowIndex].measures.firstIndex {
            $0.sourceMeasureID == fixture.chart.measures[2].id
        })
        fixture.layout.systems[rowIndex].measures[index].staffFrame.size.width = 5
        let short = try measure(in: fixture, index: 2).staffFrame
        let start = CGPoint(x: short.minX + short.width * 0.4, y: sourceRow.frame.midY)
        let destination = try point(in: fixture, measure: 3, fraction: 0.4)
        let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
            endingID: fixture.endingID, action: .move, startLocation: start, sourcePageLayout: fixture.layout,
            sourceSystemIndex: sourceRow.index))
        XCTAssertEqual(session.previewRange(at: destination), 3...3)
        let result = try XCTUnwrap(session.committedChart(at: destination, currentChart: fixture.chart))
        XCTAssertEqual(result.roadmapObject(id: other), otherBefore)
        assertEnding(in: result, id: fixture.endingID, range: 3...3)
    }

    @MainActor
    func testMovedEndingRangeAndCustomLabelSurviveJSONAndPDFInEveryLayout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        for style in ChartLayoutStyle.allCases {
            let fixture = try fixture(style: style, count: 9, range: 1...3)
            let start = try point(in: fixture, measure: 1, fraction: 0.5)
            let destination = try point(in: fixture, measure: 5, fraction: 0.5)
            let session = try XCTUnwrap(LeadSheetEndingDragSession(chart: fixture.chart,
                endingID: fixture.endingID, action: .move, startLocation: start, sourcePageLayout: fixture.layout))
            let moved = try XCTUnwrap(session.committedChart(at: destination, currentChart: fixture.chart))
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(moved))
            XCTAssertTrue(reopened == moved,
                "Round-trip fields changed: \(persistenceDifferenceKeys(reopened, moved))")
            assertEnding(in: reopened, id: fixture.endingID, range: 5...7)
            let exported = try await exporter.exportPDF(for: reopened)
            let pdf = try XCTUnwrap(PDFDocument(url: exported.url))
            let text = (pdf.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(text.contains("1–3, 5"), style.rawValue)
            let paperSize = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox).size
            let rendered = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: paperSize)
            let segments = rendered.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == fixture.endingID }
            XCTAssertEqual(segments.filter(\.showsText).map(\.text), ["1–3, 5"])
            XCTAssertTrue(segments.allSatisfy { !$0.showsTrailingHook }, "Open right edge survives movement")
            XCTAssertEqual(session.sourceChart, fixture.chart)
        }
    }

    private struct Fixture {
        var chart: Chart
        var layout: LeadSheetPageLayout
        var endingID: UUID
    }

    private func fixture(
        style: ChartLayoutStyle = .simpleChordSheet, count: Int, range: ClosedRange<Int>,
        pageSize: CGSize = CGSize(width: 900, height: 1_400)
    ) throws -> Fixture {
        var chart = Chart.blank(title: "Ending drag proof", measureCount: count, layoutStyle: style)
        let ids = chart.measures.map(\.id)
        for system in chart.systems.indices {
            for index in chart.systems[system].measures.indices {
                let ordinal = try XCTUnwrap(ids.firstIndex(of: chart.systems[system].measures[index].id))
                chart.systems[system].measures[index].manualLayoutWidth = [90.0, 150.0, 120.0][ordinal % 3]
                chart.systems[system].measures[index].authoringState = .committed
            }
        }
        for index in stride(from: 3, to: count, by: 3) {
            _ = chart.insertSystemBreak(before: ids[index])
        }
        let ink = sourceInk()
        XCTAssertFalse(LeadSheetPersistentInkColorPolicy.needsNormalization(try PKDrawing(data: ink)),
            "A persisted fixture must already use the app pen color/type before testing byte-preserving reopen")
        chart.pageHandwrittenChordData = ink
        chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        chart.pageHandwrittenHeaderData = ink
        chart.pageHandwrittenHeaderCoordinateSpace = PersistentInkCoordinateSpace(width: 901, height: 1_401)
        chart.pageHandwrittenNotationData = ink
        chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 902, height: 1_402)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1,
            startMeasureID: ids[range.lowerBound], endMeasureID: ids[range.upperBound],
            displayText: "1–3, 5", endStyle: .open))
        let object = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == endingID })
        chart.roadmapObjects[object].sourceInkData = ink
        return Fixture(chart: chart, layout: layout(chart, pageSize: pageSize), endingID: endingID)
    }

    private func layout(_ chart: Chart, pageSize: CGSize = CGSize(width: 900, height: 1_400)) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
    }

    private func row(in fixture: Fixture, measure index: Int) throws -> LeadSheetSystemLayout {
        let id = fixture.chart.measures[index].id
        return try XCTUnwrap(fixture.layout.systems.first { $0.measures.contains { $0.sourceMeasureID == id } })
    }

    private func measure(in fixture: Fixture, index: Int) throws -> LeadSheetMeasureLayout {
        let id = fixture.chart.measures[index].id
        return try XCTUnwrap(fixture.layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func point(in fixture: Fixture, measure index: Int, fraction: CGFloat) throws -> CGPoint {
        let row = try row(in: fixture, measure: index)
        let measure = try measure(in: fixture, index: index)
        return CGPoint(x: measure.staffFrame.minX + measure.staffFrame.width * fraction, y: row.frame.midY)
    }

    private func assertEnding(
        in chart: Chart, id: UUID, range: ClosedRange<Int>, file: StaticString = #filePath, line: UInt = #line
    ) {
        let object = chart.roadmapObject(id: id)
        XCTAssertEqual(object?.startMeasureID, chart.measures[range.lowerBound].id, file: file, line: line)
        XCTAssertEqual(object?.endMeasureID, chart.measures[range.upperBound].id, file: file, line: line)
        XCTAssertTrue(chart.measures[range.lowerBound].roadmapObjectIDs.contains(id), file: file, line: line)
        XCTAssertTrue(chart.measures[range.upperBound].roadmapObjectIDs.contains(id), file: file, line: line)
    }

    private func assertNonEndingContentEqual(
        _ before: Chart, _ after: Chart, endingID: UUID, file: StaticString = #filePath, line: UInt = #line
    ) {
        func withoutEnding(_ chart: Chart) -> Chart {
            var result = chart
            result.roadmapObjects.removeAll { $0.id == endingID }
            for system in result.systems.indices {
                for measure in result.systems[system].measures.indices {
                    result.systems[system].measures[measure].roadmapObjectIDs.removeAll { $0 == endingID }
                }
            }
            result.updatedAt = Date(timeIntervalSince1970: 0)
            return result
        }
        XCTAssertEqual(withoutEnding(before), withoutEnding(after), file: file, line: line)
    }

    private func sourceInk() -> Data {
        let points = [CGPoint(x: 15, y: 20), CGPoint(x: 23, y: 37), CGPoint(x: 31, y: 20)]
        let stroke = PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor), path: PKStrokePath(controlPoints:
            points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }

    private func persistenceDifferenceKeys(_ lhs: Chart, _ rhs: Chart) -> [String] {
        do {
            let left = try JSONSerialization.jsonObject(with: ChartPersistenceCoders.encoder.encode(lhs)) as? NSDictionary
            let right = try JSONSerialization.jsonObject(with: ChartPersistenceCoders.encoder.encode(rhs)) as? NSDictionary
            guard let left, let right else { return ["invalid encoded chart object"] }
            let keys = Set(left.allKeys.compactMap { $0 as? String })
                .union(right.allKeys.compactMap { $0 as? String })
            return keys.sorted().filter { key in
                let first = left[key] as? NSObject ?? NSNull()
                let second = right[key] as? NSObject ?? NSNull()
                return !first.isEqual(second)
            }
        } catch {
            return ["chart encoding failed"]
        }
    }
}
#endif
