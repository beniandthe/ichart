#if canImport(UIKit)
import XCTest
@testable import iChart

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
    }

    func testDeleteControlWinsOverReviewAndMoveHitAreas() {
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

        let moveTarget = LeadSheetChordEditOverlayGeometry.moveHitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: pageLayout
        )
        XCTAssertNil(moveTarget)
    }

    func testChordBodyCanStartMoveWithoutSeparateResizeHandle() {
        let measureID = UUID()
        let chordID = UUID()
        let chordLayout = LeadSheetChordLayout(
            id: chordID,
            text: "Db7(b9)",
            frame: CGRect(x: 160, y: 88, width: 76, height: 36),
            snapGuideTarget: CGPoint(x: 198, y: 132)
        )
        let pageLayout = pageLayout(measureID: measureID, chordLayout: chordLayout)

        let moveTarget = LeadSheetChordEditOverlayGeometry.moveHitTarget(
            at: CGPoint(x: chordLayout.frame.midX, y: chordLayout.frame.midY),
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

    func testSelectFirstPolicyTurnsUnselectedChordTapIntoSelection() {
        let measureID = UUID()
        let chordID = UUID()
        let rawTarget = ChordEditHitTarget(measureID: measureID, chordID: chordID, action: .review)

        let resolvedTarget = LeadSheetChordObjectInteractionPolicy.resolvedTapTarget(
            rawTarget,
            selectedChordID: nil,
            requiresSelectionBeforeAction: true
        )

        XCTAssertEqual(resolvedTarget?.measureID, measureID)
        XCTAssertEqual(resolvedTarget?.chordID, chordID)
        assertAction(resolvedTarget?.action, is: .select)
    }

    func testSelectFirstPolicyAllowsActionsAfterChordSelection() {
        let measureID = UUID()
        let chordID = UUID()
        let rawDeleteTarget = ChordEditHitTarget(measureID: measureID, chordID: chordID, action: .delete)
        let rawMoveTarget = ChordEditHitTarget(measureID: measureID, chordID: chordID, action: .move)

        let resolvedDeleteTarget = LeadSheetChordObjectInteractionPolicy.resolvedTapTarget(
            rawDeleteTarget,
            selectedChordID: chordID,
            requiresSelectionBeforeAction: true
        )
        let resolvedMoveTarget = LeadSheetChordObjectInteractionPolicy.resolvedMoveTarget(
            rawMoveTarget,
            selectedChordID: chordID,
            requiresSelectionBeforeMove: true
        )

        assertAction(resolvedDeleteTarget?.action, is: .delete)
        assertAction(resolvedMoveTarget?.action, is: .move)
    }

    func testSelectFirstPolicyBlocksUnselectedChordMoveStart() {
        let rawMoveTarget = ChordEditHitTarget(measureID: UUID(), chordID: UUID(), action: .move)

        let resolvedMoveTarget = LeadSheetChordObjectInteractionPolicy.resolvedMoveTarget(
            rawMoveTarget,
            selectedChordID: nil,
            requiresSelectionBeforeMove: true
        )

        XCTAssertNil(resolvedMoveTarget)
    }

    func testActiveChordPolicyLeavesRenderedChordActionsAvailableImmediately() {
        let chordID = UUID()
        let rawReviewTarget = ChordEditHitTarget(measureID: UUID(), chordID: chordID, action: .review)
        let rawMoveTarget = ChordEditHitTarget(measureID: UUID(), chordID: chordID, action: .move)

        let resolvedReviewTarget = LeadSheetChordObjectInteractionPolicy.resolvedTapTarget(
            rawReviewTarget,
            selectedChordID: nil,
            requiresSelectionBeforeAction: false
        )
        let resolvedMoveTarget = LeadSheetChordObjectInteractionPolicy.resolvedMoveTarget(
            rawMoveTarget,
            selectedChordID: nil,
            requiresSelectionBeforeMove: false
        )

        assertAction(resolvedReviewTarget?.action, is: .review)
        assertAction(resolvedMoveTarget?.action, is: .move)
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawBox(
                for: chordID,
                selectedChordID: nil,
                activeMoveChordID: nil,
                drawsAllBoxes: true
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
                for: chordID,
                selectedChordID: nil,
                activeMoveChordID: nil,
                drawsAllControls: true
            )
        )
    }

    func testSelectFirstPolicyDrawsBoxesOnlyAfterSelectionOrMove() {
        let selectedChordID = UUID()
        let movingChordID = UUID()
        let idleChordID = UUID()

        XCTAssertFalse(
            LeadSheetChordObjectInteractionPolicy.shouldDrawBox(
                for: idleChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: movingChordID,
                drawsAllBoxes: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawBox(
                for: selectedChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: nil,
                drawsAllBoxes: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawBox(
                for: movingChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: movingChordID,
                drawsAllBoxes: false
            )
        )
        XCTAssertFalse(
            LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
                for: idleChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: movingChordID,
                drawsAllControls: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
                for: selectedChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: nil,
                drawsAllControls: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
                for: movingChordID,
                selectedChordID: selectedChordID,
                activeMoveChordID: movingChordID,
                drawsAllControls: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordObjectInteractionPolicy.shouldDrawControls(
                for: idleChordID,
                selectedChordID: nil,
                activeMoveChordID: nil,
                drawsAllControls: true
            )
        )
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

    func testRoadmapMarkerEditFrameIsTightToMarkerNotMeasure() {
        let markerLayout = roadmapMarkerLayout(
            frame: CGRect(x: 126, y: 72, width: 42, height: 40),
            movementFrame: CGRect(x: 120, y: 69, width: 180, height: 40)
        )

        let editFrame = LeadSheetRoadmapMarkerEditOverlayGeometry.editFrame(for: markerLayout)

        XCTAssertLessThan(editFrame.width, markerLayout.movementFrame.width * 0.35)
        XCTAssertLessThan(editFrame.width, markerLayout.movementFrame.width)
        XCTAssertEqual(editFrame.midX, markerLayout.frame.midX, accuracy: 0.001)
        XCTAssertEqual(editFrame.midY, markerLayout.frame.midY, accuracy: 0.001)
        XCTAssertTrue(editFrame.contains(markerLayout.frame))
        XCTAssertGreaterThan(editFrame.height, markerLayout.frame.height)
    }

    func testRoadmapMarkerDeleteOnlyWinsForSelectedMarker() {
        let markerID = UUID()
        let markerLayout = roadmapMarkerLayout(id: markerID)
        let deleteFrame = LeadSheetRoadmapMarkerEditOverlayGeometry
            .controlFrames(for: markerLayout)
            .delete

        let selectedTarget = LeadSheetRoadmapMarkerEditOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            in: [markerLayout],
            selectedMarkerID: markerID
        )
        XCTAssertEqual(selectedTarget?.markerID, markerID)
        assertRoadmapAction(selectedTarget?.action, is: .delete)

        let unselectedTarget = LeadSheetRoadmapMarkerEditOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            in: [markerLayout],
            selectedMarkerID: nil
        )
        XCTAssertEqual(unselectedTarget?.markerID, markerID)
        assertRoadmapAction(unselectedTarget?.action, is: .select)

        let bodyTarget = LeadSheetRoadmapMarkerEditOverlayGeometry.hitTarget(
            at: CGPoint(x: markerLayout.frame.midX + 4, y: markerLayout.frame.midY + 4),
            in: [markerLayout],
            selectedMarkerID: markerID
        )
        XCTAssertEqual(bodyTarget?.markerID, markerID)
        assertRoadmapAction(bodyTarget?.action, is: .select)
    }

    func testRoadmapMarkerBodyCanStartHorizontalMove() {
        let markerID = UUID()
        let markerLayout = roadmapMarkerLayout(id: markerID)

        let moveTarget = LeadSheetRoadmapMarkerEditOverlayGeometry.moveHitTarget(
            at: CGPoint(x: markerLayout.frame.midX, y: markerLayout.frame.midY),
            in: [markerLayout]
        )

        XCTAssertEqual(moveTarget?.id, markerID)
    }

    func testRoadmapMarkerDragClampsAndNormalizesWithinMovementFrame() {
        let movementFrame = CGRect(x: 120, y: 72, width: 180, height: 34)
        let proposedFrame = CGRect(x: 284, y: 54, width: 40, height: 28)

        let clampedFrame = LeadSheetRoadmapMarkerEditOverlayGeometry.clampedFrame(
            proposedFrame,
            in: movementFrame
        )
        let offset = LeadSheetRoadmapMarkerEditOverlayGeometry.normalizedOffset(
            for: clampedFrame,
            in: movementFrame
        )

        XCTAssertEqual(clampedFrame.maxX, movementFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(clampedFrame.midY, movementFrame.midY, accuracy: 0.001)
        XCTAssertEqual(offset, 1, accuracy: 0.001)
    }

    func testCueTextBodySelectsAndCanStartMove() {
        let cueTextID = UUID()
        let cueTextLayout = cueTextLayout(id: cueTextID)

        let tapTarget = LeadSheetCueTextEditOverlayGeometry.hitTarget(
            at: CGPoint(x: cueTextLayout.frame.midX, y: cueTextLayout.frame.midY),
            in: [cueTextLayout],
            selectedCueTextID: nil
        )
        let moveTarget = LeadSheetCueTextEditOverlayGeometry.moveHitTarget(
            at: CGPoint(x: cueTextLayout.frame.midX, y: cueTextLayout.frame.midY),
            in: [cueTextLayout]
        )

        XCTAssertEqual(tapTarget?.cueTextID, cueTextID)
        assertCueTextAction(tapTarget?.action, is: .select)
        XCTAssertEqual(moveTarget?.id, cueTextID)
    }

    func testCueTextControlsOnlyActivateForSelectedCueText() {
        let cueTextID = UUID()
        let cueTextLayout = cueTextLayout(id: cueTextID)
        let controls = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cueTextLayout)

        let unselectedControlTarget = LeadSheetCueTextEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: [cueTextLayout],
            selectedCueTextID: nil
        )
        XCTAssertNil(unselectedControlTarget)

        let selectedDeleteTarget = LeadSheetCueTextEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: [cueTextLayout],
            selectedCueTextID: cueTextID
        )
        XCTAssertEqual(selectedDeleteTarget?.cueTextID, cueTextID)
        assertCueTextAction(selectedDeleteTarget?.action, is: .delete)

        XCTAssertEqual(
            LeadSheetCueTextEditOverlayGeometry.hitTarget(
                at: CGPoint(x: controls.edit.midX, y: controls.edit.midY),
                in: [cueTextLayout],
                selectedCueTextID: cueTextID
            )?.action,
            .edit
        )
        XCTAssertEqual(
            LeadSheetCueTextEditOverlayGeometry.hitTarget(
                at: CGPoint(x: controls.shrink.midX, y: controls.shrink.midY),
                in: [cueTextLayout],
                selectedCueTextID: cueTextID
            )?.action,
            .shrink
        )
        XCTAssertEqual(
            LeadSheetCueTextEditOverlayGeometry.hitTarget(
                at: CGPoint(x: controls.grow.midX, y: controls.grow.midY),
                in: [cueTextLayout],
                selectedCueTextID: cueTextID
            )?.action,
            .grow
        )
    }

    func testRoadmapLabelFittingShrinksLongLabelsIntoMarkerFrame() {
        let frame = CGRect(x: 0, y: 0, width: 104, height: 40)
        let fittedSize = LeadSheetRoadmapLabelFitting.fittedBaseFontSize(
            for: "D.C. AL FINE",
            in: frame,
            baseFontSize: 20,
            minimumFontSize: 17.5,
            baseFontProvider: Self.testBaseFont(size:),
            symbolFontProvider: Self.testSymbolFont(for:baseFont:)
        )
        let bounds = LeadSheetRoadmapLabelFitting.measuredBounds(
            for: "D.C. AL FINE",
            baseFont: Self.testBaseFont(size: fittedSize),
            symbolFontProvider: Self.testSymbolFont(for:baseFont:)
        )

        XCTAssertLessThanOrEqual(fittedSize, 20)
        XCTAssertGreaterThanOrEqual(fittedSize, 17.5)
        XCTAssertLessThanOrEqual(ceil(bounds.width), frame.width + 0.5)
        XCTAssertLessThanOrEqual(ceil(bounds.height), frame.height + 0.5)
    }

    func testRoadmapLabelFittingKeepsStandaloneCodaCloseToTextRoadmaps() {
        let frame = CGRect(x: 0, y: 0, width: 44, height: 40)
        let fittedSize = LeadSheetRoadmapLabelFitting.fittedBaseFontSize(
            for: NotationGlyphCatalog.coda,
            in: frame,
            baseFontSize: 22,
            minimumFontSize: 21,
            baseFontProvider: Self.testBaseFont(size:),
            symbolFontProvider: Self.testSymbolFont(for:baseFont:)
        )

        XCTAssertEqual(fittedSize, 22, accuracy: 0.001)
    }

    private func assertAction(
        _ action: ChordEditHitTarget.Action?,
        is expectedAction: ChordEditHitTarget.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (action, expectedAction) {
        case (.select?, .select), (.delete?, .delete), (.move?, .move), (.review?, .review):
            break
        default:
            XCTFail("Expected \(expectedAction), got \(String(describing: action))", file: file, line: line)
        }
    }

    private func assertRoadmapAction(
        _ action: RoadmapMarkerEditHitTarget.Action?,
        is expectedAction: RoadmapMarkerEditHitTarget.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (action, expectedAction) {
        case (.select?, .select), (.delete?, .delete), (.move?, .move):
            break
        default:
            XCTFail("Expected \(expectedAction), got \(String(describing: action))", file: file, line: line)
        }
    }

    private func assertCueTextAction(
        _ action: CueTextEditHitTarget.Action?,
        is expectedAction: CueTextEditHitTarget.Action,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (action, expectedAction) {
        case (.select?, .select),
             (.edit?, .edit),
             (.shrink?, .shrink),
             (.grow?, .grow),
             (.delete?, .delete):
            break
        default:
            XCTFail("Expected \(expectedAction), got \(String(describing: action))", file: file, line: line)
        }
    }

    private static func testBaseFont(size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size)
    }

    private static func testSymbolFont(for symbolGlyph: String, baseFont: UIFont) -> UIFont {
        UIFont.systemFont(ofSize: baseFont.pointSize * 1.12)
    }

    private func roadmapMarkerLayout(
        id: UUID = UUID(),
        frame: CGRect = CGRect(x: 126, y: 72, width: 34, height: 34),
        movementFrame: CGRect = CGRect(x: 120, y: 72, width: 180, height: 34)
    ) -> LeadSheetRoadmapMarkerLayout {
        LeadSheetRoadmapMarkerLayout(
            roadmapObjectID: id,
            type: .codaMarker,
            text: NotationGlyphCatalog.coda,
            frame: frame,
            movementFrame: movementFrame,
            anchorMeasureID: UUID()
        )
    }

    private func cueTextLayout(
        id: UUID = UUID(),
        frame: CGRect = CGRect(x: 150, y: 94, width: 86, height: 24)
    ) -> LeadSheetCueTextLayout {
        LeadSheetCueTextLayout(
            id: id,
            text: "Repeat 3x",
            frame: frame,
            hitFrame: frame.insetBy(dx: -8, dy: -6),
            position: .above,
            emphasis: .normal,
            scale: 1,
            beatFraction: 0.5,
            verticalOffset: 0
        )
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
            chordBandFrame: CGRect(x: 104, y: 84, width: 172, height: 34),
            writableFrame: CGRect(x: 104, y: 84, width: 172, height: 72),
            chordLayouts: [chordLayout],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
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
                handwrittenFrame: CGRect(x: 60, y: 60, width: 380, height: 80),
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
