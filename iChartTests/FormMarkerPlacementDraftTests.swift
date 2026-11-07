import XCTest
@testable import iChart

final class FormMarkerPlacementDraftTests: XCTestCase {
    func testDefaultAndExplicitTargetsAreShownWithoutMutatingChart() {
        for layout in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = Chart.blank(title: "Marker preview", measureCount: 4, layoutStyle: layout)
            let original = chart
            let initial = FormMarkerPlacementDraft(chart: chart, initialMeasureID: nil)
            XCTAssertEqual(initial.measureID, chart.measures.first?.id)
            XCTAssertEqual(initial.targetDescription(in: chart), "Add Coda to measure 1")
            let selected = FormMarkerPlacementDraft(chart: chart, initialMeasureID: chart.measures[2].id, markerType: .segno)
            XCTAssertEqual(selected.targetDescription(in: chart), "Add Segno to measure 3")
            XCTAssertTrue(selected.canApply(to: chart))
            XCTAssertEqual(chart, original)
        }
    }

    func testRemovedTargetAndNonPointTypesCannotApply() {
        let chart = Chart.blank(title: "Marker guard", measureCount: 4, layoutStyle: .simpleChordSheet)
        var draft = FormMarkerPlacementDraft(chart: chart, initialMeasureID: nil)
        draft.measureID = UUID()
        XCTAssertFalse(draft.canApply(to: chart))
        XCTAssertNil(draft.targetDescription(in: chart))
        draft.measureID = chart.measures[0].id
        draft.markerType = .repeatSpan
        XCTAssertFalse(draft.canApply(to: chart))
    }

    func testAllExistingPointMarkerTypesRetainPlacementAndMeaning() {
        let chart = Chart.blank(title: "All markers", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        XCTAssertEqual(RoadmapType.navigationPointMarkerTypes.count, 9)
        for type in RoadmapType.navigationPointMarkerTypes {
            let draft = FormMarkerPlacementDraft(chart: chart, initialMeasureID: chart.measures[1].id, markerType: type)
            XCTAssertTrue(draft.canApply(to: chart))
            XCTAssertFalse(type.placementMeaning.isEmpty)
            XCTAssertEqual(draft.targetDescription(in: chart), "Add \(type.editorMenuDisplayText) to measure 2")
        }
    }
}
