#if canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class LeadSheetChordInkRecognitionTargetingTests: XCTestCase {
    func testAccumulatedRepeatRetainsVisiblePointDotInBothChartStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let context = try chordContext(style: style)
            let lane = try XCTUnwrap(context.inputFrames.first)
            let rootStrokes = try templateStrokes(
                "C", x: lane.minX + 40, centerY: lane.midY, chordFrame: context.chordFrame
            )
            let repeatPoints: [[CGPoint]] = [
                [CGPoint(x: 180, y: 26)],
                [CGPoint(x: 198, y: 62), CGPoint(x: 224, y: 12)],
                [CGPoint(x: 238, y: 53), CGPoint(x: 240, y: 54), CGPoint(x: 238, y: 55)]
            ]
            let repeatStrokes = repeatPoints.map { points in
                pkStroke(points: points.map { point in
                    CGPoint(
                        x: lane.minX + 150 + (point.x - 180) * 0.5 - context.chordFrame.minX,
                        y: lane.midY + (point.y - 37) * 0.5 - context.chordFrame.minY
                    )
                })
            }
            XCTAssertTrue(ChordInkDraftVisibleStrokePolicy.isVisible(repeatStrokes[0]))
            let expectedInk = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: repeatStrokes))
            let recognizer = ChordInkRecognizer()
            XCTAssertEqual(recognizer.recognize(strokes: expectedInk).match?.displayText, "•/•")

            let drawing = PKDrawing(strokes: rootStrokes + repeatStrokes)
            let measure = try XCTUnwrap(context.layout.systems.first?.measures.first)
            let barline = DraftBarline(
                measureID: try XCTUnwrap(measure.chordInkTargetMeasureID),
                measureIndex: 1, fraction: 0.15,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.15),
                metrics: DraftBarlineGestureMetrics(
                    height: 54, width: 2, angleDegreesFromVertical: 0,
                    straightness: 1, laneCoverage: 0.9
                )
            )
            for barlines in [[], [barline]] {
                let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
                    for: drawing, chordFrame: context.chordFrame,
                    pageLayout: context.layout, draftBarlines: barlines
                )
                let target = try XCTUnwrap(
                    result.targets.first {
                        ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                            expected: PKDrawing(strokes: repeatStrokes), current: $0.drawing
                        )
                    }, diagnostics(result)
                )
                XCTAssertEqual(target.strokes.count, 3)
                XCTAssertEqual(recognizer.recognize(strokes: target.strokes).match?.displayText, "•/•")
                XCTAssertEqual(result.targets.reduce(0) { $0 + $1.strokes.count }, drawing.strokes.count)
            }
        }
    }

    func testAddingFirstRootOnContinuationLanePreservesPreviousTargets() throws {
        let context = try chordContext()
        let firstLane = try XCTUnwrap(context.inputFrames.first)
        let secondLane = try XCTUnwrap(context.inputFrames.dropFirst().first)
        let firstDrawing = PKDrawing(strokes:
            try templateStrokes("C", x: firstLane.minX + 40, centerY: firstLane.midY, chordFrame: context.chordFrame)
            + templateStrokes("D", x: firstLane.minX + 100, centerY: firstLane.midY, chordFrame: context.chordFrame)
        )
        let firstResult = targets(firstDrawing, context: context)
        XCTAssertEqual(firstResult.targets.count, 2, diagnostics(firstResult))
        XCTAssertEqual(firstResult.diagnostics.selectedRoute, "lane_root_sequence", diagnostics(firstResult))

        let expandedDrawing = PKDrawing(strokes: firstDrawing.strokes + (try templateStrokes(
            "C", x: secondLane.minX + 40, centerY: secondLane.midY, chordFrame: context.chordFrame
        )))
        let expandedResult = targets(expandedDrawing, context: context)

        // A lane with one chord currently falls through to measure grouping. The completed
        // preceding lane must retain the same stroke ownership despite this route change.
        XCTAssertEqual(expandedResult.targets.count, 3, diagnostics(expandedResult))
        XCTAssertEqual(expandedResult.targets.map { $0.laneLocation?.systemIndex }, [0, 0, 1], diagnostics(expandedResult))
        XCTAssertEqual(Array(expandedResult.targets.prefix(2)).map(\.strokes), firstResult.targets.map(\.strokes), diagnostics(expandedResult))
    }

    func testAddingVisibleInkOutsideLanesPreservesPreviousTargets() throws {
        let context = try chordContext()
        let firstLane = try XCTUnwrap(context.inputFrames.first)
        let firstDrawing = PKDrawing(strokes:
            try templateStrokes("C", x: firstLane.minX + 40, centerY: firstLane.midY, chordFrame: context.chordFrame)
            + templateStrokes("D", x: firstLane.minX + 100, centerY: firstLane.midY, chordFrame: context.chordFrame)
        )
        let firstResult = targets(firstDrawing, context: context)
        XCTAssertEqual(firstResult.targets.count, 2, diagnostics(firstResult))
        let outsideStroke = pkStroke(points: [
            CGPoint(x: firstLane.minX + 42 - context.chordFrame.minX, y: firstLane.maxY + 24 - context.chordFrame.minY),
            CGPoint(x: firstLane.minX + 48 - context.chordFrame.minX, y: firstLane.maxY + 36 - context.chordFrame.minY)
        ])
        let expandedResult = targets(PKDrawing(strokes: firstDrawing.strokes + [outsideStroke]), context: context)

        // Unowned ink must not change the stroke ownership of completed in-lane chords.
        for previous in firstResult.targets {
            XCTAssertTrue(expandedResult.targets.contains { $0.strokes == previous.strokes }, diagnostics(expandedResult))
        }
    }

    private struct Context {
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var inputFrames: [CGRect]
    }

    private func chordContext(style: ChartLayoutStyle = .simpleChordSheet) throws -> Context {
        var chart = Chart.draft(title: "Accumulating Chord Targets", layoutStyle: style)
        chart.completeInitialSetup(
            title: "Accumulating Chord Targets",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        XCTAssertFalse(region.inputFrames.isEmpty)
        return Context(layout: layout, chordFrame: region.frame, inputFrames: region.inputFrames)
    }

    private func targets(_ drawing: PKDrawing, context: Context) -> LeadSheetChordInkRecognitionBatchTargetingResult {
        LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: context.chordFrame,
            pageLayout: context.layout
        )
    }

    private func diagnostics(_ result: LeadSheetChordInkRecognitionBatchTargetingResult) -> String {
        "route=\(result.diagnostics.selectedRoute) laneRoots=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) strokeCounts=\(result.targets.map(\.strokes.count))"
    }

    private func templateStrokes(_ text: String, x: CGFloat, centerY: CGFloat, chordFrame: CGRect) throws -> [PKStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text })
        return template.strokes.map { stroke in
            pkStroke(points: stroke.points.map { point in
                CGPoint(
                    x: x + CGFloat(point.x) * 0.72 - chordFrame.minX,
                    y: centerY + CGFloat(point.y - 36) * 0.72 - chordFrame.minY
                )
            })
        }
    }

    private func pkStroke(points: [CGPoint]) -> PKStroke {
        PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.05, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date())
        )
    }
}
#endif
