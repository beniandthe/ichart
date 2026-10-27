#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class FlexibleEndingHitTargetTests: XCTestCase {
    func testCustomEndingAndEveryContinuationOpenTheSameInspector() throws {
        for style in ChartLayoutStyle.allCases {
            var chart = Chart.blank(title: "Custom ending targets", measureCount: 12, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            if style != .leadSheet {
                XCTAssertTrue(chart.insertSystemBreak(before: ids[4]))
                XCTAssertTrue(chart.insertSystemBreak(before: ids[8]))
            }
            let id = try XCTUnwrap(chart.addEndingSpan(
                .ending1, startMeasureID: ids[0], endMeasureID: ids[11],
                displayText: "1, 2, 3, 5, 7. Last time on cue", endStyle: .open
            ))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 740, height: 1500))
            let context = RenderedEditContext(pageLayout: layout)
            let segments = layout.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == id }
            XCTAssertGreaterThan(segments.count, 1)
            let targets = EndingSpanRenderedEditHitTargetProvider().hitTargets(in: context)
            XCTAssertEqual(targets.filter { $0.objectID == .endingSpan(id) }.count, segments.count)
            for segment in segments {
                let location = CGPoint(x: segment.frame.midX, y: segment.frame.minY + 3)
                let target = try XCTUnwrap(RenderedEditRouter().tapTarget(at: location, in: context))
                XCTAssertEqual(target.objectID, .endingSpan(id))
                XCTAssertEqual(target.action, .openInspector)
                XCTAssertEqual(target.mutationRisk, .nonMutating)
                XCTAssertNil(RenderedEditRouter().dragTarget(at: location, in: context))
                if segment.showsText {
                    XCTAssertTrue(target.frame.contains(segment.labelFrame))
                }
            }
        }
    }

    func testOverlappingEndingLabelsRemainIndividuallySelectable() throws {
        var chart = Chart.blank(title: "Separate ending targets", measureCount: 4, layoutStyle: .simpleChordSheet)
        let ids = chart.measures.map(\.id)
        let first = try XCTUnwrap(chart.addEndingSpan(
            .ending1, startMeasureID: ids[0], endMeasureID: ids[3], displayText: "1, 2, 3."
        ))
        let second = try XCTUnwrap(chart.addEndingSpan(
            .ending1, startMeasureID: ids[0], endMeasureID: ids[3], displayText: "4, 5."
        ))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 1000, height: 1500))
        let context = RenderedEditContext(pageLayout: layout)
        let segments = layout.systems.flatMap(\.endingLayouts)
        for id in [first, second] {
            let segment = try XCTUnwrap(segments.first { $0.roadmapObjectID == id && $0.showsText })
            let location = CGPoint(x: segment.labelFrame.midX, y: segment.labelFrame.midY)
            XCTAssertEqual(RenderedEditRouter().tapTarget(at: location, in: context)?.objectID, .endingSpan(id))
        }
    }
}
#endif
