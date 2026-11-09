#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class RenderedEditTypesTests: XCTestCase {
    func testObjectIdentityKeepsObjectFamiliesDistinct() {
        let id = UUID()
        let objects: Set<RenderedEditObjectID> = [
            .measure(id),
            .chord(id),
            .committedChordBarline(afterMeasureID: id),
            .cueText(id),
            .roadmapMarker(id),
            .repeatSpan(id),
            .endingSpan(id),
            .timeSignatureChange(afterMeasureID: id),
            .keyChange(measureID: id),
            .header
        ]

        XCTAssertEqual(objects.count, 10)
        XCTAssertNotEqual(RenderedEditObjectID.chord(id), .cueText(id))
        XCTAssertNotEqual(RenderedEditObjectID.measure(id), .committedChordBarline(afterMeasureID: id))
    }

    func testSelectionStateTracksOneRenderedObject() {
        let chordID = RenderedEditObjectID.chord(UUID())
        let cueTextID = RenderedEditObjectID.cueText(UUID())
        var selection = RenderedEditSelectionState()

        XCTAssertTrue(selection.isEmpty)
        XCTAssertFalse(selection.contains(chordID))

        selection.select(chordID)
        XCTAssertFalse(selection.isEmpty)
        XCTAssertTrue(selection.contains(chordID))

        selection.select(cueTextID)
        XCTAssertFalse(selection.contains(chordID))
        XCTAssertTrue(selection.contains(cueTextID))

        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func testHighestPriorityTargetKeepsDestructiveControlsAheadOfBodySelection() {
        let objectID = RenderedEditObjectID.chord(UUID())
        let lowPriorityTarget = hitTarget(
            objectID: objectID,
            action: .select,
            priority: .objectBodySelect,
            mutationRisk: .nonMutating
        )
        let highPriorityTarget = hitTarget(
            objectID: objectID,
            action: .delete,
            priority: .selectedObjectDestructiveControl,
            requiresSelection: true,
            mutationRisk: .destructive
        )
        let middlePriorityTarget = hitTarget(
            objectID: objectID,
            action: .correctChord,
            priority: .selectedObjectEditControl,
            requiresSelection: true,
            mutationRisk: .content
        )

        let bestTarget = RenderedEditHitTarget.highestPriority(
            in: [lowPriorityTarget, highPriorityTarget, middlePriorityTarget]
        )

        XCTAssertEqual(bestTarget?.action, .delete)
        XCTAssertEqual(bestTarget?.priority, .selectedObjectDestructiveControl)
    }

    func testHighestPriorityTargetKeepsFirstCandidateWhenPrioritiesTie() {
        let firstObjectID = RenderedEditObjectID.chord(UUID())
        let secondObjectID = RenderedEditObjectID.cueText(UUID())
        let firstTarget = hitTarget(
            objectID: firstObjectID,
            action: .select,
            priority: .objectBodySelect
        )
        let secondTarget = hitTarget(
            objectID: secondObjectID,
            action: .select,
            priority: .objectBodySelect
        )

        let bestTarget = RenderedEditHitTarget.highestPriority(in: [firstTarget, secondTarget])

        XCTAssertEqual(bestTarget?.objectID, firstObjectID)
    }

    func testHighestPriorityTargetUsesNearestCenterToBreakPriorityTie() {
        let firstObjectID = RenderedEditObjectID.chord(UUID())
        let secondObjectID = RenderedEditObjectID.chord(UUID())
        var firstTarget = hitTarget(
            objectID: firstObjectID,
            action: .select,
            priority: .objectBodySelect
        )
        var secondTarget = hitTarget(
            objectID: secondObjectID,
            action: .select,
            priority: .objectBodySelect
        )
        firstTarget.frame = CGRect(x: 10, y: 20, width: 40, height: 40)
        secondTarget.frame = CGRect(x: 30, y: 20, width: 40, height: 40)

        let bestTarget = RenderedEditHitTarget.highestPriority(
            in: [firstTarget, secondTarget],
            nearestTo: CGPoint(x: 58, y: 40)
        )

        XCTAssertEqual(bestTarget?.objectID, secondObjectID)
    }

    func testSelectFirstResolutionConvertsUnselectedMutatingTapIntoSelection() {
        let objectID = RenderedEditObjectID.committedChordBarline(afterMeasureID: UUID())
        let deleteTarget = hitTarget(
            objectID: objectID,
            action: .delete,
            priority: .selectedObjectDestructiveControl,
            requiresSelection: true,
            mutationRisk: .structural
        )

        let resolvedTarget = RenderedEditSelectionPolicy.resolvedTapTarget(
            deleteTarget,
            selection: RenderedEditSelectionState()
        )

        XCTAssertEqual(resolvedTarget?.objectID, objectID)
        XCTAssertEqual(resolvedTarget?.action, .select)
        XCTAssertEqual(resolvedTarget?.priority, .objectBodySelect)
        XCTAssertFalse(resolvedTarget?.requiresSelection ?? true)
        XCTAssertEqual(resolvedTarget?.mutationRisk, .nonMutating)
    }

    func testSelectFirstResolutionKeepsSelectedMutatingTap() {
        let objectID = RenderedEditObjectID.cueText(UUID())
        var selection = RenderedEditSelectionState()
        selection.select(objectID)
        let deleteTarget = hitTarget(
            objectID: objectID,
            action: .delete,
            priority: .selectedObjectDestructiveControl,
            requiresSelection: true,
            mutationRisk: .destructive
        )

        let resolvedTarget = RenderedEditSelectionPolicy.resolvedTapTarget(
            deleteTarget,
            selection: selection
        )

        XCTAssertEqual(resolvedTarget, deleteTarget)
    }

    func testDragResolutionBlocksUnselectedMovesAndResizeHandles() {
        let objectID = RenderedEditObjectID.chord(UUID())
        let moveTarget = hitTarget(
            objectID: objectID,
            action: .move,
            priority: .selectedObjectMoveBody,
            requiresSelection: true,
            mutationRisk: .visual
        )
        let resizeTarget = hitTarget(
            objectID: objectID,
            action: .resizeTrailing,
            priority: .selectedObjectResizeHandle,
            requiresSelection: true,
            mutationRisk: .visual
        )
        var selection = RenderedEditSelectionState()

        XCTAssertNil(RenderedEditSelectionPolicy.resolvedDragTarget(moveTarget, selection: selection))
        XCTAssertNil(RenderedEditSelectionPolicy.resolvedDragTarget(resizeTarget, selection: selection))

        selection.select(objectID)
        XCTAssertEqual(
            RenderedEditSelectionPolicy.resolvedDragTarget(moveTarget, selection: selection),
            moveTarget
        )
        XCTAssertEqual(
            RenderedEditSelectionPolicy.resolvedDragTarget(resizeTarget, selection: selection),
            resizeTarget
        )
    }

    func testDragResolutionRejectsNonDragActions() {
        let target = hitTarget(
            objectID: .header,
            action: .openInspector,
            priority: .selectedObjectEditControl,
            mutationRisk: .nonMutating
        )

        XCTAssertNil(
            RenderedEditSelectionPolicy.resolvedDragTarget(
                target,
                selection: RenderedEditSelectionState(selectedObjectID: .header)
            )
        )
    }

    func testDragStateAcceptsOnlyMoveAndResizeTargets() throws {
        let moveTarget = hitTarget(
            objectID: .chord(UUID()),
            action: .move,
            priority: .selectedObjectMoveBody,
            requiresSelection: true,
            mutationRisk: .visual
        )
        let resizeTarget = hitTarget(
            objectID: .chord(UUID()),
            action: .resizeTrailing,
            priority: .selectedObjectResizeHandle,
            requiresSelection: true,
            mutationRisk: .visual
        )
        let tapTarget = hitTarget(
            objectID: .chord(UUID()),
            action: .select,
            priority: .objectBodySelect
        )

        let startLocation = CGPoint(x: 17, y: 29)
        let moveState = try XCTUnwrap(RenderedEditDragState(target: moveTarget, startLocation: startLocation))
        let resizeState = try XCTUnwrap(RenderedEditDragState(target: resizeTarget, startLocation: startLocation))

        XCTAssertEqual(moveState.target, moveTarget)
        XCTAssertEqual(resizeState.target, resizeTarget)
        XCTAssertNil(RenderedEditDragState(target: tapTarget, startLocation: startLocation))
    }

    func testDestructiveTapRequiresTheSameTargetAtTouchDownAndLift() {
        let objectID = RenderedEditObjectID.chord(UUID())
        let delete = hitTarget(objectID: objectID, action: .delete,
            priority: .selectedObjectDestructiveControl, requiresSelection: true, mutationRisk: .destructive)
        let body = hitTarget(objectID: objectID, action: .select, priority: .objectBodySelect)
        let otherDelete = hitTarget(objectID: .chord(UUID()), action: .delete,
            priority: .selectedObjectDestructiveControl, requiresSelection: true, mutationRisk: .destructive)
        var intent = RenderedEditTapIntent()

        XCTAssertNil(intent.resolvedTarget(at: delete))
        intent.begin(target: body)
        XCTAssertNil(intent.resolvedTarget(at: delete), "Sliding off the body onto the red X cannot delete")
        intent.begin(target: delete)
        XCTAssertNil(intent.resolvedTarget(at: otherDelete), "A different chord's X cannot inherit intent")
        XCTAssertNil(intent.resolvedTarget(at: nil))
        XCTAssertEqual(intent.resolvedTarget(at: delete), delete)
        intent.cancelForDrag()
        XCTAssertNil(intent.resolvedTarget(at: delete), "Recognized or cancelled movement cannot fall through to delete")
        intent.reset()
        XCTAssertNil(intent.resolvedTarget(at: delete))
    }

    func testDestructiveTapMovementLimitUsesScreenPointsAtDifferentCanvasScales() {
        let delete = hitTarget(objectID: .chord(UUID()), action: .delete,
            priority: .selectedObjectDestructiveControl, requiresSelection: true, mutationRisk: .destructive)
        let start = CGPoint(x: 20, y: 30)
        var intent = RenderedEditTapIntent()
        for scale: CGFloat in [0.5, 1, 2] {
            intent.begin(target: delete, startLocation: start,
                screenPointsPerDisplayedPoint: scale, maximumScreenMovement: 4)
            let withinLimit = CGPoint(x: start.x + 4 / scale, y: start.y)
            let beyondLimit = CGPoint(x: start.x + 4.25 / scale, y: start.y)
            XCTAssertEqual(intent.resolvedTarget(at: delete, endLocation: withinLimit), delete)
            XCTAssertNil(intent.resolvedTarget(at: delete, endLocation: beyondLimit),
                "Remaining inside a large control hit area is not enough to establish tap intent")
            XCTAssertNil(intent.resolvedTarget(at: delete), "A captured start requires a measured lift")
        }
        intent.begin(target: delete, startLocation: start,
            screenPointsPerDisplayedPoint: 2, maximumScreenMovement: 6)
        XCTAssertEqual(intent.resolvedTarget(at: delete,
            endLocation: CGPoint(x: start.x + 3, y: start.y)), delete)
        XCTAssertNil(intent.resolvedTarget(at: delete,
            endLocation: CGPoint(x: start.x + 3.25, y: start.y)))
    }

    func testBodySelectionDoesNotNeedDestructiveControlIntent() {
        let body = hitTarget(objectID: .chord(UUID()), action: .select, priority: .objectBodySelect)
        var intent = RenderedEditTapIntent()
        intent.begin(target: body)
        XCTAssertEqual(intent.resolvedTarget(at: body), body)
    }

    private func hitTarget(
        objectID: RenderedEditObjectID,
        action: RenderedEditAction,
        priority: RenderedEditHitPriority,
        requiresSelection: Bool = false,
        mutationRisk: RenderedEditMutationRisk = .nonMutating
    ) -> RenderedEditHitTarget {
        RenderedEditHitTarget(
            objectID: objectID,
            action: action,
            priority: priority,
            frame: CGRect(x: 10, y: 20, width: 30, height: 40),
            requiresSelection: requiresSelection,
            mutationRisk: mutationRisk
        )
    }
}
#endif
