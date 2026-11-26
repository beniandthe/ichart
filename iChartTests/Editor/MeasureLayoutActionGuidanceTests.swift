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
                let newRow = MeasureLayoutActionGuidance.availability(for: .startNewRow, chart: chart, measureID: id, pageLayout: layout)
                XCTAssertEqual(newRow.isEnabled, chart.canInsertSystemBreak(before: id))
                let move = MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: id, pageLayout: layout)
                let below = try? LeadSheetAdjacentRowMovePolicy.plan(for: id, direction: .below, in: layout, chart: chart).get()
                XCTAssertEqual(move.isEnabled, below != nil)
                let join = MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: id, pageLayout: layout)
                let above = try? LeadSheetAdjacentRowMovePolicy.plan(for: id, direction: .above, in: layout, chart: chart).get()
                XCTAssertEqual(join.isEnabled, above != nil)
                for action in MeasureLayoutAction.allCases {
                    let result = MeasureLayoutActionGuidance.availability(for: action, chart: chart, measureID: id, pageLayout: layout)
                    XCTAssertEqual(result.reason == nil, result.isEnabled)
                }
            }
            XCTAssertTrue(MeasureLayoutActionGuidance.availability(for: .moveToRowBelow, chart: chart, measureID: ids[1], pageLayout: layout).isEnabled)
            XCTAssertTrue(MeasureLayoutActionGuidance.availability(for: .joinRowAbove, chart: chart, measureID: ids[5], pageLayout: layout).isEnabled)
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

    func testNewRowKeepsOwningPredicateForEveryLayoutAndRejectsMissingTargets() {
        for style in ChartLayoutStyle.allCases {
            let chart = Chart.blank(title: "New row availability", measureCount: 8, layoutStyle: style)
            let original = chart
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
            for measure in chart.measures {
                let result = MeasureLayoutActionGuidance.availability(for: .startNewRow,
                    chart: chart, measureID: measure.id, pageLayout: layout)
                XCTAssertEqual(result.isEnabled, chart.canInsertSystemBreak(before: measure.id))
                XCTAssertEqual(result.reason == nil, result.isEnabled)
            }
            for missingID in [nil, UUID()] as [UUID?] {
                let result = MeasureLayoutActionGuidance.availability(for: .startNewRow,
                    chart: chart, measureID: missingID, pageLayout: layout)
                XCTAssertFalse(result.isEnabled)
                XCTAssertEqual(result.reason, "Select a measure first.")
            }
            XCTAssertEqual(chart, original)
        }
    }
}
#endif
