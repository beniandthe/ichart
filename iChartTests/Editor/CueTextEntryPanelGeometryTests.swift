import CoreGraphics
import XCTest
@testable import iChart

final class CueTextEntryPanelGeometryTests: XCTestCase {
    func testIPadTextEntryPanelStaysCompactInPortraitAndLandscape() {
        let portraitWidth = CueTextEntryPanelGeometry.panelWidth(for: 820)
        let landscapeWidth = CueTextEntryPanelGeometry.panelWidth(for: 1_180)

        XCTAssertEqual(portraitWidth, CueTextEntryPanelGeometry.maximumWidth, accuracy: 0.001)
        XCTAssertEqual(landscapeWidth, CueTextEntryPanelGeometry.maximumWidth, accuracy: 0.001)
        XCTAssertLessThan(portraitWidth, 820 * 0.6)
        XCTAssertLessThan(landscapeWidth, 1_180 * 0.4)
        XCTAssertLessThanOrEqual(CueTextEntryPanelGeometry.inputHeight, 72)
        XCTAssertEqual(CueTextEntryPanelGeometry.panelHeight, 146, accuracy: 0.001)
        XCTAssertLessThan(CueTextEntryPanelGeometry.panelHeight, 180)
    }

    func testCompactTextEntryPanelPreservesHorizontalMargins() {
        let availableWidth: CGFloat = 360
        let panelWidth = CueTextEntryPanelGeometry.panelWidth(for: availableWidth)

        XCTAssertEqual(
            panelWidth,
            availableWidth - CueTextEntryPanelGeometry.horizontalMargin * 2,
            accuracy: 0.001
        )
    }

    func testTextEntryPanelHeightAccountsForOnlyHeaderInputSpacingAndPadding() {
        XCTAssertEqual(
            CueTextEntryPanelGeometry.panelHeight,
            CueTextEntryPanelGeometry.headerHeight
                + CueTextEntryPanelGeometry.inputHeight
                + CueTextEntryPanelGeometry.verticalSpacing
                + CueTextEntryPanelGeometry.verticalPadding * 2,
            accuracy: 0.001
        )
    }
}
