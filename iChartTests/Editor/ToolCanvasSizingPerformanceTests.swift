#if canImport(UIKit)
import CoreGraphics
import Foundation
import XCTest
@testable import iChart

/// Diagnostic timing of the actual sizing work done by EditorView.body. These
/// are synthetic charts, not measurements of a physical user's tap latency.
@MainActor
final class ToolCanvasSizingPerformanceTests: XCTestCase {
    func testRepeatedSizingCostForPopulatedSimpleSheets() throws {
        try recordSizingCost(style: .simpleChordSheet)
    }

    func testRepeatedSizingCostForPopulatedRhythmSheets() throws {
        try recordSizingCost(style: .rhythmSectionSheet)
    }

    private func recordSizingCost(style: ChartLayoutStyle) throws {
        for measureCount in [4, 32] {
            let chart = try populatedChart(style: style, measureCount: measureCount)
            let pageSize = CGSize(width: 932, height: 1_100)
            let baseline = editorSizing(chart: chart, pageSize: pageSize)
            XCTAssertGreaterThan(baseline.systemCount, 0)
            XCTAssertGreaterThanOrEqual(baseline.height, 1_200)
            XCTAssertTrue(baseline.height.isFinite)

            var durations: [Double] = []
            // Repeating an unchanged chart models the work caused by transient
            // tool/selection/helper updates; no chart mutation occurs here.
            for _ in 0..<8 {
                let start = ProcessInfo.processInfo.systemUptime
                let result = editorSizing(chart: chart, pageSize: pageSize)
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                XCTAssertEqual(result.systemCount, baseline.systemCount)
                XCTAssertEqual(result.height, baseline.height)
            }
            let ordered = durations.sorted()
            let cache = EditorCanvasGeometryCache()
            XCTAssertEqual(cache.canvasHeight(for: chart, pageSize: pageSize), baseline.height)
            var cachedDurations: [Double] = []
            for _ in 0..<8 {
                let start = ProcessInfo.processInfo.systemUptime
                let result = cache.canvasHeight(for: chart, pageSize: pageSize)
                cachedDurations.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                XCTAssertEqual(result, baseline.height)
            }
            XCTAssertEqual(cache.canvasHeightBuildCount, 1,
                "Transient lookups must reuse the same geometry instead of rerunning the engines")
            let cachedOrdered = cachedDurations.sorted()
            let report: [String: Any] = [
                "layoutStyle": style.rawValue,
                "measureCount": measureCount,
                "chordCount": chart.measures.reduce(0) { $0 + $1.chordEvents.count },
                "sampleCount": durations.count,
                "engineCallsPerSizing": 2,
                "systemCount": baseline.systemCount,
                "minimumMilliseconds": ordered.first!,
                "medianMilliseconds": (ordered[3] + ordered[4]) / 2,
                "maximumMilliseconds": ordered.last!,
                "totalMilliseconds": durations.reduce(0, +),
                "cachedLookupCount": cachedDurations.count,
                "cachedEnginePairBuildCount": cache.canvasHeightBuildCount,
                "cachedMedianMilliseconds": (cachedOrdered[3] + cachedOrdered[4]) / 2,
                "cachedTotalMilliseconds": cachedDurations.reduce(0, +)
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            // Keep only technical counts and timings in output/attachments.
            print("tool_canvas_sizing_diagnostic \(String(decoding: data, as: UTF8.self))")
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "tool-sizing-\(style.rawValue)-\(measureCount)-measures"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func editorSizing(chart: Chart, pageSize: CGSize) -> (systemCount: Int, height: CGFloat) {
        let count = LeadSheetPageLayoutEngine.estimatedSystemCount(for: chart, pageWidth: pageSize.width)
        let estimate = LeadSheetPageLayoutEngine.estimatedCanvasHeight(for: chart, pageSize: pageSize)
        return (count, max(pageSize.height, 1_200, estimate, CGFloat(count) * 168 + 320))
    }

    private func populatedChart(style: ChartLayoutStyle, measureCount: Int) throws -> Chart {
        var chart = Chart.blank(title: "Sizing diagnostic", measureCount: measureCount, layoutStyle: style)
        chart.staffSystemDensity = .dense
        chart.notationReadability = .performance
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                chart.systems[systemIndex].measures[measureIndex].authoringState = .committed
            }
        }
        let symbols = try ["Cmaj7", "Am7", "D7", "G7"].map(ChordSymbolParser.parse)
        for (index, measure) in chart.measures.enumerated() {
            for (offset, symbol) in symbols.enumerated() {
                XCTAssertNotNil(chart.appendRecognizedChordEvent(symbol, rawInput: nil,
                    to: measure.id, atFraction: Double(offset) / 4))
            }
            if index.isMultiple(of: 4) {
                XCTAssertNotNil(chart.addCueText("Play lightly", anchorMeasureID: measure.id, position: .below))
            }
        }
        return chart
    }
}
#endif
