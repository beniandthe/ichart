#if canImport(UIKit)
import Combine
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class EditorCanvasGeometryCacheTests: XCTestCase {
    func testCachedHeightAndRowGeometryMatchTheOriginalEnginesInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = try populatedChart(style)
            let cache = EditorCanvasGeometryCache()
            for size in [CGSize(width: 932, height: 1_100), CGSize(width: 680, height: 1_650)] {
                XCTAssertEqual(cache.canvasHeight(for: chart, pageSize: size), originalHeight(chart, size))
                assertGeometry(cache.pageLayout(for: chart, pageSize: size),
                    matches: LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size))
            }
        }
        let draft = Chart.draft(title: "Incomplete setup")
        let cache = EditorCanvasGeometryCache()
        for size in [CGSize(width: 500, height: 600), CGSize(width: 932, height: 1_100)] {
            XCTAssertEqual(cache.canvasHeight(for: draft, pageSize: size), max(760, size.height))
        }
    }

    func testTransientQueriesReuseIndependentHeightAndPageEntriesWithoutPublishing() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = try populatedChart(style)
            let cache = EditorCanvasGeometryCache()
            let sizingSize = CGSize(width: 932, height: 1_100)
            let rowQuerySize = CGSize(width: 932, height: 1_800)
            var publications = 0
            let observation = cache.objectWillChange.sink { publications += 1 }
            let height = cache.canvasHeight(for: chart, pageSize: sizingSize)
            let layout = cache.pageLayout(for: chart, pageSize: rowQuerySize)

            // The caller may change tools, selected measure or helper context;
            // those values do not change either document query's inputs.
            for _ in 0..<40 {
                XCTAssertEqual(cache.canvasHeight(for: chart, pageSize: sizingSize), height)
                let repeated = cache.pageLayout(for: chart, pageSize: rowQuerySize)
                XCTAssertEqual(repeated.systems.map(\.id), layout.systems.map(\.id))
            }
            XCTAssertEqual(cache.canvasHeightBuildCount, 1)
            XCTAssertEqual(cache.pageLayoutBuildCount, 1)
            XCTAssertEqual(publications, 0, "Cache hits and counters must not schedule another editor update")
            withExtendedLifetime(observation) {}
        }
    }

    func testDirectMusicalAppearanceInkAndWidthEditsInvalidateWithUnchangedTimestamp() throws {
        let replacement = try ChordSymbolParser.parse("Db7(b9)")
        let ink = drawingData()
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let original = try populatedChart(style)
            let cache = EditorCanvasGeometryCache()
            let size = CGSize(width: 932, height: 1_100)
            _ = cache.canvasHeight(for: original, pageSize: size)
            _ = cache.pageLayout(for: original, pageSize: size)
            let edits: [(inout Chart) -> Void] = [
                { $0.systems[0].measures[0].chordEvents[0].symbol = replacement },
                { $0.systems[0].measures[0].meterOverride = Meter(numerator: 3, denominator: 4) },
                { $0.systems[0].measures[0].manualLayoutWidth = 360 },
                { $0.staffSystemDensity = .close },
                { $0.notationReadability = .standard },
                { $0.pageHandwrittenNotationData = ink },
                { $0.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(size: CGSize(width: 1_100, height: 2_200)) },
                { $0.id = UUID() }
            ]
            for (index, edit) in edits.enumerated() {
                var changed = original
                edit(&changed)
                XCTAssertEqual(changed.updatedAt, original.updatedAt,
                    "This regression must not rely on timestamps to invalidate geometry")
                XCTAssertEqual(cache.canvasHeight(for: changed, pageSize: size), originalHeight(changed, size))
                assertGeometry(cache.pageLayout(for: changed, pageSize: size),
                    matches: LeadSheetPageLayoutEngine.pageLayout(for: changed, pageSize: size))
                XCTAssertEqual(cache.canvasHeightBuildCount, index + 2)
                XCTAssertEqual(cache.pageLayoutBuildCount, index + 2)
            }
            let before = cache.canvasHeightBuildCount
            let narrower = CGSize(width: 650, height: 1_100)
            XCTAssertEqual(cache.canvasHeight(for: original, pageSize: narrower), originalHeight(original, narrower))
            _ = cache.pageLayout(for: original, pageSize: narrower)
            XCTAssertEqual(cache.canvasHeightBuildCount, before + 1)
            XCTAssertEqual(cache.pageLayoutBuildCount, before + 1)
        }
    }

    func testOccupiedInkIsPartOfTheKeyAndQueriesLeaveItsArchiveUnchanged() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = try populatedChart(style)
            let source = drawingData()
            chart.pageHandwrittenNotationData = source
            chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(
                size: CGSize(width: 932, height: 3_300))
            chart.systems[0].measures[0].chordEvents[0].sourceInkData = source
            let before = chart
            let cache = EditorCanvasGeometryCache()
            let size = CGSize(width: 932, height: 1_100)
            XCTAssertEqual(cache.canvasHeight(for: chart, pageSize: size), originalHeight(chart, size))
            _ = cache.pageLayout(for: chart, pageSize: size)
            XCTAssertEqual(chart, before)
            XCTAssertEqual(chart.pageHandwrittenNotationData, source)
            XCTAssertEqual(chart.systems[0].measures[0].chordEvents[0].sourceInkData, source)

            chart.pageHandwrittenNotationData = nil
            XCTAssertEqual(chart.updatedAt, before.updatedAt)
            XCTAssertEqual(cache.canvasHeight(for: chart, pageSize: size), originalHeight(chart, size))
            _ = cache.pageLayout(for: chart, pageSize: size)
            XCTAssertEqual(cache.canvasHeightBuildCount, 2)
            XCTAssertEqual(cache.pageLayoutBuildCount, 2)
        }
    }

    private func originalHeight(_ chart: Chart, _ size: CGSize) -> CGFloat {
        let count = LeadSheetPageLayoutEngine.estimatedSystemCount(for: chart, pageWidth: size.width)
        let estimate = LeadSheetPageLayoutEngine.estimatedCanvasHeight(for: chart, pageSize: size)
        return max(size.height, 1_200, estimate, CGFloat(count) * 168 + 320)
    }

    private func assertGeometry(_ actual: LeadSheetPageLayout, matches expected: LeadSheetPageLayout,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.pageBounds, expected.pageBounds, file: file, line: line)
        XCTAssertEqual(actual.paperFrames, expected.paperFrames, file: file, line: line)
        XCTAssertEqual(actual.header, expected.header, file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.frame), expected.systems.map(\.frame), file: file, line: line)
        let measures = actual.systems.flatMap(\.measures)
        let reference = expected.systems.flatMap(\.measures)
        XCTAssertEqual(measures.map(\.sourceMeasureID), reference.map(\.sourceMeasureID), file: file, line: line)
        XCTAssertEqual(measures.map(\.frame), reference.map(\.frame), file: file, line: line)
        XCTAssertEqual(measures.map(\.staffFrame), reference.map(\.staffFrame), file: file, line: line)
        XCTAssertEqual(measures.flatMap(\.chordLayouts).map(\.frame),
            reference.flatMap(\.chordLayouts).map(\.frame), file: file, line: line)
    }

    private func populatedChart(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Cache geometry", measureCount: 8, layoutStyle: style)
        chart.staffSystemDensity = .dense
        chart.notationReadability = .performance
        for measure in chart.measures {
            _ = chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("Cmaj7"),
                rawInput: nil, to: measure.id, atFraction: 0)
            _ = chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("D7"),
                rawInput: nil, to: measure.id, atFraction: 0.5)
        }
        _ = chart.addCueText("Play lightly", anchorMeasureID: chart.measures[0].id, position: .below)
        return chart
    }

    private func drawingData() -> Data {
        let points = [CGPoint(x: 30, y: 2_500), CGPoint(x: 70, y: 2_540)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1)))]).dataRepresentation()
    }
}
#endif
