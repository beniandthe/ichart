#if canImport(UIKit)
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
        let input = CueTextEntryPanelGeometry.inputHeight(forContentHeight: 36, availableHeight: 900)
        XCTAssertEqual(input, 44, accuracy: 0.001)
        XCTAssertEqual(CueTextEntryPanelGeometry.panelHeight(forInputHeight: input), 118, accuracy: 0.001)
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
        let input: CGFloat = 89
        XCTAssertEqual(
            CueTextEntryPanelGeometry.panelHeight(forInputHeight: input),
            CueTextEntryPanelGeometry.headerHeight
                + input
                + CueTextEntryPanelGeometry.verticalSpacing
                + CueTextEntryPanelGeometry.verticalPadding * 2,
            accuracy: 0.001
        )
    }

    func testInputGrowsAndShrinksWithNativeMeasuredTextWithoutChangingWidth() {
        let width = CueTextEntryPanelGeometry.panelWidth(for: 820)
        let oneLine = CueTextEntryPanelGeometry.inputHeight(forContentHeight: 36.5, availableHeight: 600)
        let twoLines = CueTextEntryPanelGeometry.inputHeight(forContentHeight: 57.3, availableHeight: 600)
        let wrapped = CueTextEntryPanelGeometry.inputHeight(forContentHeight: 119.2, availableHeight: 600)
        let shortened = CueTextEntryPanelGeometry.inputHeight(forContentHeight: 36.5, availableHeight: 600)
        XCTAssertEqual(oneLine, 44)
        XCTAssertEqual(twoLines, 58)
        XCTAssertEqual(wrapped, 120)
        XCTAssertEqual(shortened, oneLine)
        XCTAssertEqual(CueTextEntryPanelGeometry.panelWidth(for: 820), width)
    }

    func testLongInputIsBoundedByKeyboardSpaceAndMaximumHeight() {
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 900, availableHeight: 700),
            CueTextEntryPanelGeometry.maximumInputHeight)
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 900, availableHeight: 96.8), 96)
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 63, availableHeight: 96), 63)
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 30, availableHeight: 700),
            CueTextEntryPanelGeometry.minimumInputHeight)
    }

    func testInvalidMeasurementsKeepPracticalTouchHeight() {
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: .nan, availableHeight: 600), 44)
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 100, availableHeight: .infinity), 100)
        XCTAssertEqual(CueTextEntryPanelGeometry.inputHeight(forContentHeight: 100, availableHeight: -10), 44)
    }
}
#endif
