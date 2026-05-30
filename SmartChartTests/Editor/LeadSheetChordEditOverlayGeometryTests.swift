#if canImport(UIKit)
import XCTest
@testable import SmartChart

final class LeadSheetChordEditOverlayGeometryTests: XCTestCase {
    func testControlFramesAreFingerFriendly() {
        let chordLayout = LeadSheetChordLayout(
            id: UUID(),
            text: "G/B",
            frame: CGRect(x: 120, y: 72, width: 42, height: 36),
            snapGuideTarget: CGPoint(x: 141, y: 132)
        )

        let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)

        XCTAssertEqual(controls.delete.width, LeadSheetChordEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.delete.height, LeadSheetChordEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.move.width, LeadSheetChordEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.move.height, LeadSheetChordEditOverlayGeometry.controlSize)
        XCTAssertGreaterThanOrEqual(controls.move.width, 18)
    }

    func testMoveAndDeleteControlsWinOverReviewHitArea() {
        let measureID = UUID()
        let chordID = UUID()
        let chordLayout = LeadSheetChordLayout(
            id: chordID,
            text: "Db7(b9)",
            frame: CGRect(x: 160, y: 88, width: 76, height: 36),
            snapGuideTarget: CGPoint(x: 198, y: 132)
        )
        let pageLayout = pageLayout(measureID: measureID, chordLayout: chordLayout)
        let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: chordLayout)

        let deleteTarget = LeadSheetChordEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: pageLayout
        )
        XCTAssertEqual(deleteTarget?.measureID, measureID)
        XCTAssertEqual(deleteTarget?.chordID, chordID)
        assertAction(deleteTarget?.action, is: .delete)

        let moveTarget = LeadSheetChordEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.move.maxX + 8, y: controls.move.midY),
            in: pageLayout
        )
        XCTAssertEqual(moveTarget?.measureID, measureID)
        XCTAssertEqual(moveTarget?.chordID, chordID)
        assertAction(moveTarget?.action, is: .move)
    }

    func testChordBodyStillRequestsReview() {
        let measureID = UUID()
        let chordID = UUID()
        let chordLayout = LeadSheetChordLayout(
            id: chordID,
            text: "Absus",
            frame: CGRect(x: 140, y: 90, width: 58, height: 34),
            snapGuideTarget: CGPoint(x: 169, y: 132)
        )
        let pageLayout = pageLayout(measureID: measureID, chordLayout: chordLayout)

        let target = LeadSheetChordEditOverlayGeometry.hitTarget(
            at: CGPoint(x: chordLayout.frame.midX, y: chordLayout.frame.midY),
            in: pageLayout
        )

        XCTAssertEqual(target?.measureID, measureID)
        XCTAssertEqual(target?.chordID, chordID)
        assertAction(target?.action, is: .review)
    }

    func testEditFrameWrapsVisibleChordFrameNotMeasureFitFrame() {
        let chordLayout = LeadSheetChordLayout(
            id: UUID(),
            text: "B7(b5)",
            frame: CGRect(x: 140, y: 90, width: 88, height: 44),
            fitFrame: CGRect(x: 140, y: 90, width: 220, height: 44),
            snapGuideTarget: CGPoint(x: 250, y: 132)
        )

        let editFrame = LeadSheetChordEditOverlayGeometry.editFrame(for: chordLayout)

        XCTAssertLessThan(editFrame.width, chordLayout.fitFrame.width * 0.6)
        XCTAssertEqual(editFrame.minX, chordLayout.frame.minX - 6, accuracy: 0.001)
        XCTAssertEqual(editFrame.maxX, chordLayout.frame.maxX + 6, accuracy: 0.001)
    }

    private func assertAction(
        _ action: ChordEditHitTarget.Action?,
        is expectedAction: ChordEditHitTarget.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (action, expectedAction) {
        case (.delete?, .delete), (.move?, .move), (.review?, .review):
            break
        default:
            XCTFail("Expected \(expectedAction), got \(String(describing: action))", file: file, line: line)
        }
    }

    private func pageLayout(
        measureID: UUID,
        chordLayout: LeadSheetChordLayout
    ) -> LeadSheetPageLayout {
        let measure = LeadSheetMeasureLayout(
            id: UUID(),
            sourceMeasureID: measureID,
            index: 1,
            frame: CGRect(x: 100, y: 80, width: 180, height: 90),
            staffFrame: CGRect(x: 108, y: 116, width: 164, height: 34),
            freehandAboveFrame: nil,
            freehandBelowFrame: nil,
            chordBandFrame: CGRect(x: 104, y: 84, width: 172, height: 34),
            writableFrame: CGRect(x: 104, y: 84, width: 172, height: 72),
            chordLayouts: [chordLayout],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 280, y: 116, width: 1.6, height: 34),
            isOpen: false
        )

        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 1,
            frame: CGRect(x: 100, y: 80, width: 180, height: 90),
            staffLineYPositions: [],
            clefFrame: nil,
            keySignatureLayouts: [],
            timeSignatureFrame: nil,
            sectionTextFrame: nil,
            sectionText: nil,
            roadmapTextFrame: nil,
            roadmapText: nil,
            roadmapMarkerLayouts: [],
            endingLayouts: [],
            measures: [measure]
        )

        return LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            paperFrame: CGRect(x: 40, y: 40, width: 420, height: 420),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 60, y: 60, width: 380, height: 80),
                titleFrame: CGRect(x: 120, y: 70, width: 220, height: 36),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: CGRect(x: 60, y: 60, width: 80, height: 18),
                meterFrame: CGRect(x: 60, y: 78, width: 80, height: 18)
            ),
            systems: [system]
        )
    }
}
#endif
