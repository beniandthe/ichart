#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

final class MeasureLayoutActionGuidanceTests: XCTestCase {
    func testAvailabilityUsesOwningPredicatesInBothLayouts() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Layout actions", measureCount: 8, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            XCTAssertTrue(chart.insertSystemBreak(before: ids[4]))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
            for id in ids {
                let move = MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(move.isEnabled, LeadSheetMoveMeasureToRowBelowPolicy.plan(for: id, in: layout, chart: chart) != nil)
                let join = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(join.isEnabled, chart.measureIDsForJoiningRow(startingAt: id) != nil && !LeadSheetJoinRowEqualizationPolicy.manualLayoutWidths(startingAt: id, in: layout, chart: chart).isEmpty)
                for action in MeasureLayoutAction.allCases {
                    let result = MeasureLayoutActionGuidance.availability(for: action, chart: chart, measureID: id, pageLayout: layout)
                    XCTAssertEqual(result.reason == nil, result.isEnabled)
                }
            }
            XCTAssertEqual(MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: ids[1], pageLayout: layout).reason, "Select the last measure in this row.")
        }
    }

    func testMissingSelectionAndKeyBoundaryExplainNextStepWithoutMutation() throws {
        var chart = Chart.blank(title: "Layout reasons", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let id = chart.measures[4].id
        XCTAssertTrue(chart.setKeyChange(.fMajor, atStartOf: id))
        let original = chart
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
        let empty = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: nil, pageLayout: layout)
        XCTAssertEqual(empty.reason, "Select a measure first.")
        let key = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: id, pageLayout: layout)
        XCTAssertFalse(key.isEnabled)
        XCTAssertEqual(key.reason, "Keep the row boundary at this key change.")
        XCTAssertEqual(chart, original)
    }
}
#endif
