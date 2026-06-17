#if canImport(UIKit)
import XCTest
@testable import SmartChart

final class LeadSheetFreehandSymbolEditOverlayGeometryTests: XCTestCase {
    func testControlFramesAreFingerFriendly() {
        let symbolLayout = freehandSymbolLayout(
            frame: CGRect(x: 120, y: 70, width: 46, height: 12)
        )

        let controls = LeadSheetFreehandSymbolEditOverlayGeometry.controlFrames(for: symbolLayout)

        XCTAssertEqual(controls.delete.width, LeadSheetFreehandSymbolEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.delete.height, LeadSheetFreehandSymbolEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.move.width, LeadSheetFreehandSymbolEditOverlayGeometry.controlSize)
        XCTAssertEqual(controls.move.height, LeadSheetFreehandSymbolEditOverlayGeometry.controlSize)
        XCTAssertGreaterThanOrEqual(
            LeadSheetFreehandSymbolEditOverlayGeometry.editFrame(for: symbolLayout).height,
            26
        )
    }

    func testDeleteAndMoveControlsWinOverSelectionHitArea() {
        let symbolID = UUID()
        let symbolLayout = freehandSymbolLayout(
            id: symbolID,
            frame: CGRect(x: 140, y: 70, width: 62, height: 36)
        )
        let controls = LeadSheetFreehandSymbolEditOverlayGeometry.controlFrames(for: symbolLayout)

        let deleteTarget = LeadSheetFreehandSymbolEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: [symbolLayout]
        )
        XCTAssertEqual(deleteTarget?.symbolID, symbolID)
        assertAction(deleteTarget?.action, is: .delete)

        let moveTarget = LeadSheetFreehandSymbolEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.move.midX, y: controls.move.midY),
            in: [symbolLayout]
        )
        XCTAssertEqual(moveTarget?.symbolID, symbolID)
        assertAction(moveTarget?.action, is: .move)
    }

    func testSymbolBodySelectsFreehandSymbol() {
        let symbolID = UUID()
        let symbolLayout = freehandSymbolLayout(
            id: symbolID,
            frame: CGRect(x: 150, y: 82, width: 48, height: 16)
        )

        let target = LeadSheetFreehandSymbolEditOverlayGeometry.hitTarget(
            at: CGPoint(x: symbolLayout.frame.midX, y: symbolLayout.frame.midY),
            in: [symbolLayout]
        )

        XCTAssertEqual(target?.symbolID, symbolID)
        assertAction(target?.action, is: .select)
    }

    func testSelectedDragFrameExtendsBeyondEditHitFrame() {
        let symbolLayout = freehandSymbolLayout(
            frame: CGRect(x: 150, y: 82, width: 48, height: 16)
        )

        let editHitFrame = LeadSheetFreehandSymbolEditOverlayGeometry.editHitFrame(for: symbolLayout)
        let selectedDragFrame = LeadSheetFreehandSymbolEditOverlayGeometry.selectedDragFrame(for: symbolLayout)

        XCTAssertLessThan(selectedDragFrame.minX, editHitFrame.minX)
        XCTAssertLessThan(selectedDragFrame.minY, editHitFrame.minY)
        XCTAssertGreaterThan(selectedDragFrame.maxX, editHitFrame.maxX)
        XCTAssertGreaterThan(selectedDragFrame.maxY, editHitFrame.maxY)
    }

    func testClampedFrameKeepsMovedSymbolInsideOriginalLane() {
        let laneFrame = CGRect(x: 100, y: 50, width: 160, height: 40)
        let proposedFrame = CGRect(x: 20, y: 88, width: 70, height: 20)

        let clampedFrame = LeadSheetFreehandSymbolEditOverlayGeometry.clampedFrame(
            proposedFrame,
            in: laneFrame
        )

        XCTAssertEqual(clampedFrame.minX, laneFrame.minX, accuracy: 0.001)
        XCTAssertEqual(clampedFrame.maxY, laneFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(clampedFrame.width, proposedFrame.width, accuracy: 0.001)
        XCTAssertEqual(clampedFrame.height, proposedFrame.height, accuracy: 0.001)
    }

    private func assertAction(
        _ action: FreehandSymbolEditHitTarget.Action?,
        is expectedAction: FreehandSymbolEditHitTarget.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (action, expectedAction) {
        case (.delete?, .delete), (.move?, .move), (.select?, .select):
            break
        default:
            XCTFail("Expected \(expectedAction), got \(String(describing: action))", file: file, line: line)
        }
    }

    private func freehandSymbolLayout(
        id: UUID = UUID(),
        frame: CGRect
    ) -> LeadSheetFreehandSymbolLayout {
        let laneFrame = CGRect(x: 100, y: 60, width: 180, height: 48)
        return LeadSheetFreehandSymbolLayout(
            id: id,
            symbol: FreehandSymbol(
                id: id,
                anchorMeasureID: UUID(),
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(frame: frame, in: laneFrame),
                measureRelativeFrame: FreehandSymbolMeasureFrame(frame: frame, relativeTo: laneFrame),
                drawingData: Data([1, 2, 3]),
                zIndex: 0
            ),
            frame: frame,
            laneFrame: laneFrame
        )
    }
}
#endif
