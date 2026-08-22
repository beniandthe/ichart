#if canImport(UIKit)
import CoreGraphics
import XCTest
@testable import iChart

final class RenderedEditTargetProvidersTests: XCTestCase {
    func testProviderSetExposesRenderedObjectFamilies() {
        let fixture = pageFixture()
        let context = RenderedEditContext(
            pageLayout: fixture.pageLayout,
            committedChordBarlineMeasures: [fixture.measure]
        )

        let objectIDs = Set(
            RenderedEditTargetProviderSet.renderedPageProviders
                .flatMap { $0.hitTargets(in: context) }
                .map(\.objectID)
        )

        XCTAssertTrue(objectIDs.contains(.chord(fixture.chordID)))
        XCTAssertTrue(objectIDs.contains(.committedChordBarline(afterMeasureID: fixture.measureID)))
        XCTAssertTrue(objectIDs.contains(.cueText(fixture.cueTextID)))
        XCTAssertTrue(objectIDs.contains(.roadmapMarker(fixture.roadmapID)))
        XCTAssertTrue(objectIDs.contains(.measure(fixture.measureID)))
        XCTAssertTrue(objectIDs.contains(.header))
    }

    func testChordProviderMatchesExistingBodyAndSelectedControls() throws {
        let fixture = pageFixture()
        let chordObjectID = RenderedEditObjectID.chord(fixture.chordID)
        let router = RenderedEditRouter()
        var selection = RenderedEditSelectionState()
        selection.select(chordObjectID)
        let context = RenderedEditContext(pageLayout: fixture.pageLayout, selection: selection)

        let bodyLocation = CGPoint(x: fixture.chordLayout.frame.midX, y: fixture.chordLayout.frame.midY)
        let legacyBodyTarget = LeadSheetChordEditOverlayGeometry.hitTarget(
            at: bodyLocation,
            in: fixture.pageLayout
        )
        let bodyTarget = try XCTUnwrap(router.tapTarget(at: bodyLocation, in: context))

        XCTAssertEqual(legacyBodyTarget?.chordID, fixture.chordID)
        XCTAssertEqual(bodyTarget.objectID, chordObjectID)
        XCTAssertEqual(bodyTarget.action, .select)

        let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: fixture.chordLayout)
        let legacyDeleteTarget = LeadSheetChordEditOverlayGeometry.hitTarget(
            at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
            in: fixture.pageLayout
        )
        let deleteTarget = try XCTUnwrap(
            router.tapTarget(
                at: CGPoint(x: controls.delete.midX, y: controls.delete.midY),
                in: context
            )
        )

        XCTAssertEqual(legacyDeleteTarget?.chordID, fixture.chordID)
        XCTAssertEqual(legacyDeleteTarget?.action, .delete)
        XCTAssertEqual(deleteTarget.objectID, chordObjectID)
        XCTAssertEqual(deleteTarget.action, .delete)
        XCTAssertEqual(deleteTarget.priority, .selectedObjectDestructiveControl)
    }

    func testSelectedChordResizeHandleBeatsMoveBodyForDrag() throws {
        let fixture = pageFixture()
        let chordObjectID = RenderedEditObjectID.chord(fixture.chordID)
        let controls = LeadSheetChordEditOverlayGeometry.controlFrames(for: fixture.chordLayout)
        var selection = RenderedEditSelectionState()
        selection.select(chordObjectID)
        let context = RenderedEditContext(pageLayout: fixture.pageLayout, selection: selection)

        let dragTarget = try XCTUnwrap(
            RenderedEditRouter().dragTarget(
                at: CGPoint(x: controls.trailingResize.midX, y: controls.trailingResize.midY),
                in: context
            )
        )

        XCTAssertEqual(dragTarget.objectID, chordObjectID)
        XCTAssertEqual(dragTarget.action, .resizeTrailing)
        XCTAssertEqual(dragTarget.priority, .selectedObjectResizeHandle)
    }

    func testUnselectedChordBodyCannotStartMove() {
        let fixture = pageFixture()
        let context = RenderedEditContext(pageLayout: fixture.pageLayout)
        let bodyLocation = CGPoint(x: fixture.chordLayout.frame.midX, y: fixture.chordLayout.frame.midY)

        XCTAssertNil(RenderedEditRouter().dragTarget(at: bodyLocation, in: context))
    }

    func testSelectedRenderedObjectsCanStartMoveThroughRouter() throws {
        let fixture = pageFixture()
        let router = RenderedEditRouter()

        var chordSelection = RenderedEditSelectionState()
        chordSelection.select(.chord(fixture.chordID))
        let chordDrag = try XCTUnwrap(
            router.dragTarget(
                at: CGPoint(x: fixture.chordLayout.frame.midX, y: fixture.chordLayout.frame.midY),
                in: RenderedEditContext(pageLayout: fixture.pageLayout, selection: chordSelection)
            )
        )
        XCTAssertEqual(chordDrag.objectID, .chord(fixture.chordID))
        XCTAssertEqual(chordDrag.action, .move)

        var cueSelection = RenderedEditSelectionState()
        cueSelection.select(.cueText(fixture.cueTextID))
        let cueDrag = try XCTUnwrap(
            router.dragTarget(
                at: CGPoint(x: fixture.cueTextLayout.frame.midX, y: fixture.cueTextLayout.frame.midY),
                in: RenderedEditContext(pageLayout: fixture.pageLayout, selection: cueSelection)
            )
        )
        XCTAssertEqual(cueDrag.objectID, .cueText(fixture.cueTextID))
        XCTAssertEqual(cueDrag.action, .move)

        var roadmapSelection = RenderedEditSelectionState()
        roadmapSelection.select(.roadmapMarker(fixture.roadmapID))
        let roadmapDrag = try XCTUnwrap(
            router.dragTarget(
                at: CGPoint(x: fixture.roadmapLayout.frame.midX, y: fixture.roadmapLayout.frame.midY),
                in: RenderedEditContext(pageLayout: fixture.pageLayout, selection: roadmapSelection)
            )
        )
        XCTAssertEqual(roadmapDrag.objectID, .roadmapMarker(fixture.roadmapID))
        XCTAssertEqual(roadmapDrag.action, .move)
    }

    func testCommittedBarlineProviderMatchesExistingLineAndSelectedDeleteControl() throws {
        let fixture = pageFixture()
        let barlineObjectID = RenderedEditObjectID.committedChordBarline(afterMeasureID: fixture.measureID)
        var selection = RenderedEditSelectionState()
        selection.select(barlineObjectID)
        let context = RenderedEditContext(
            pageLayout: fixture.pageLayout,
            selection: selection,
            committedChordBarlineMeasures: [fixture.measure]
        )
        let router = RenderedEditRouter()
        let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: fixture.measure)
        let lineLocation = CGPoint(x: lineFrame.midX, y: lineFrame.midY)

        let legacyLineTarget = LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: lineLocation,
            measures: [fixture.measure],
            selectedMeasureID: fixture.measureID
        )
        let lineTarget = try XCTUnwrap(router.tapTarget(at: lineLocation, in: context))

        XCTAssertEqual(legacyLineTarget, CommittedChordBarlineHitTarget(measureID: fixture.measureID, action: .select))
        XCTAssertEqual(lineTarget.objectID, barlineObjectID)
        XCTAssertEqual(lineTarget.action, .select)

        let deleteFrame = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(for: fixture.measure).delete
        let legacyDeleteTarget = LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            measures: [fixture.measure],
            selectedMeasureID: fixture.measureID
        )
        let deleteTarget = try XCTUnwrap(
            router.tapTarget(
                at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
                in: context
            )
        )

        XCTAssertEqual(
            legacyDeleteTarget,
            CommittedChordBarlineHitTarget(measureID: fixture.measureID, action: .delete)
        )
        XCTAssertEqual(deleteTarget.objectID, barlineObjectID)
        XCTAssertEqual(deleteTarget.action, .delete)
        XCTAssertEqual(deleteTarget.mutationRisk, .structural)
    }

    func testCommittedBarlineLineWinsOverOverlappingChordBody() throws {
        let fixture = pageFixture(
            chordFrame: CGRect(x: 292, y: 128, width: 56, height: 28)
        )
        let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: fixture.measure)
        let context = RenderedEditContext(
            pageLayout: fixture.pageLayout,
            committedChordBarlineMeasures: [fixture.measure]
        )

        let target = try XCTUnwrap(
            RenderedEditRouter().tapTarget(
                at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
                in: context
            )
        )

        XCTAssertEqual(target.objectID, .committedChordBarline(afterMeasureID: fixture.measureID))
        XCTAssertEqual(target.action, .select)
    }

    func testMeasureBodyLosesToChordCueAndRoadmapObjectHits() throws {
        let fixture = pageFixture()
        let router = RenderedEditRouter()
        let context = RenderedEditContext(pageLayout: fixture.pageLayout)

        let chordTarget = try XCTUnwrap(
            router.tapTarget(
                at: CGPoint(x: fixture.chordLayout.frame.midX, y: fixture.chordLayout.frame.midY),
                in: context
            )
        )
        let cueTarget = try XCTUnwrap(
            router.tapTarget(
                at: CGPoint(x: fixture.cueTextLayout.frame.midX, y: fixture.cueTextLayout.frame.midY),
                in: context
            )
        )
        let roadmapTarget = try XCTUnwrap(
            router.tapTarget(
                at: CGPoint(x: fixture.roadmapLayout.frame.midX, y: fixture.roadmapLayout.frame.midY),
                in: context
            )
        )

        XCTAssertEqual(chordTarget.objectID, .chord(fixture.chordID))
        XCTAssertEqual(cueTarget.objectID, .cueText(fixture.cueTextID))
        XCTAssertEqual(roadmapTarget.objectID, .roadmapMarker(fixture.roadmapID))
    }

    func testMeasureResizeHandlesRequireSelectedMeasure() throws {
        let fixture = pageFixture()
        let router = RenderedEditRouter()
        let handles = LeadSheetMeasureResizeGeometry.handleFrames(for: fixture.measure)
        let leftHandlePoint = CGPoint(x: handles.left.midX, y: handles.left.midY)
        let rightHandlePoint = CGPoint(x: handles.right.midX, y: handles.right.midY)

        XCTAssertNil(
            router.dragTarget(
                at: leftHandlePoint,
                in: RenderedEditContext(pageLayout: fixture.pageLayout)
            )
        )

        var selection = RenderedEditSelectionState()
        selection.select(.measure(fixture.measureID))
        let context = RenderedEditContext(pageLayout: fixture.pageLayout, selection: selection)

        let leftTarget = try XCTUnwrap(router.dragTarget(at: leftHandlePoint, in: context))
        XCTAssertEqual(leftTarget.objectID, .measure(fixture.measureID))
        XCTAssertEqual(leftTarget.action, .resizeLeft)
        XCTAssertEqual(leftTarget.priority, .selectedObjectResizeHandle)
        XCTAssertEqual(leftTarget.mutationRisk, .visual)

        let rightTarget = try XCTUnwrap(router.dragTarget(at: rightHandlePoint, in: context))
        XCTAssertEqual(rightTarget.objectID, .measure(fixture.measureID))
        XCTAssertEqual(rightTarget.action, .resizeRight)
        XCTAssertEqual(rightTarget.priority, .selectedObjectResizeHandle)
        XCTAssertEqual(rightTarget.mutationRisk, .visual)
    }

    func testCueTextAndRoadmapControlsUseExistingSelectedControlFrames() throws {
        let fixture = pageFixture()
        var cueSelection = RenderedEditSelectionState()
        cueSelection.select(.cueText(fixture.cueTextID))
        let cueContext = RenderedEditContext(pageLayout: fixture.pageLayout, selection: cueSelection)
        let cueControls = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: fixture.cueTextLayout)

        let cueDeleteTarget = try XCTUnwrap(
            RenderedEditRouter().tapTarget(
                at: CGPoint(x: cueControls.delete.midX, y: cueControls.delete.midY),
                in: cueContext
            )
        )
        XCTAssertEqual(cueDeleteTarget.objectID, .cueText(fixture.cueTextID))
        XCTAssertEqual(cueDeleteTarget.action, .delete)

        var roadmapSelection = RenderedEditSelectionState()
        roadmapSelection.select(.roadmapMarker(fixture.roadmapID))
        let roadmapContext = RenderedEditContext(pageLayout: fixture.pageLayout, selection: roadmapSelection)
        let roadmapDelete = LeadSheetRoadmapMarkerEditOverlayGeometry
            .controlFrames(for: fixture.roadmapLayout)
            .delete

        let roadmapDeleteTarget = try XCTUnwrap(
            RenderedEditRouter().tapTarget(
                at: CGPoint(x: roadmapDelete.midX, y: roadmapDelete.midY),
                in: roadmapContext
            )
        )
        XCTAssertEqual(roadmapDeleteTarget.objectID, .roadmapMarker(fixture.roadmapID))
        XCTAssertEqual(roadmapDeleteTarget.action, .delete)
    }

    func testHeaderProviderMatchesHeaderAuthoringTargetFrame() throws {
        let fixture = pageFixture()
        let context = RenderedEditContext(pageLayout: fixture.pageLayout)
        let location = CGPoint(
            x: fixture.pageLayout.header.handwrittenFrame.midX,
            y: fixture.pageLayout.header.handwrittenFrame.midY
        )

        XCTAssertTrue(
            LeadSheetCanvasInteractionTargeting.headerAuthoringContains(
                location,
                in: fixture.pageLayout
            )
        )

        let target = try XCTUnwrap(RenderedEditRouter().tapTarget(at: location, in: context))
        XCTAssertEqual(target.objectID, .header)
        XCTAssertEqual(target.action, .openInspector)
    }

    private struct PageFixture {
        var measureID: UUID
        var chordID: UUID
        var cueTextID: UUID
        var roadmapID: UUID
        var chordLayout: LeadSheetChordLayout
        var cueTextLayout: LeadSheetCueTextLayout
        var roadmapLayout: LeadSheetRoadmapMarkerLayout
        var measure: LeadSheetMeasureLayout
        var pageLayout: LeadSheetPageLayout
    }

    private func pageFixture(
        chordFrame: CGRect = CGRect(x: 130, y: 128, width: 60, height: 28)
    ) -> PageFixture {
        let measureID = UUID()
        let chordID = UUID()
        let cueTextID = UUID()
        let roadmapID = UUID()
        let measureFrame = CGRect(x: 100, y: 120, width: 240, height: 90)
        let chordLayout = LeadSheetChordLayout(
            id: chordID,
            text: "D7",
            frame: chordFrame,
            snapGuideTarget: CGPoint(x: chordFrame.midX, y: 178)
        )
        let cueTextLayout = LeadSheetCueTextLayout(
            id: cueTextID,
            text: "Solo",
            frame: CGRect(x: 202, y: 132, width: 44, height: 22),
            hitFrame: CGRect(x: 194, y: 126, width: 60, height: 34),
            position: .above,
            emphasis: .normal,
            scale: 1,
            beatFraction: 0.5,
            verticalOffset: 0
        )
        let roadmapLayout = LeadSheetRoadmapMarkerLayout(
            roadmapObjectID: roadmapID,
            type: .codaMarker,
            text: NotationGlyphCatalog.coda,
            frame: CGRect(x: 264, y: 128, width: 34, height: 34),
            movementFrame: measureFrame,
            anchorMeasureID: measureID,
            scale: 1
        )
        let measure = LeadSheetMeasureLayout(
            id: UUID(),
            sourceMeasureID: measureID,
            chordInkTargetMeasureID: measureID,
            index: 0,
            frame: measureFrame,
            staffFrame: CGRect(x: 108, y: 156, width: 224, height: 34),
            chordBandFrame: CGRect(x: 104, y: 124, width: 232, height: 34),
            writableFrame: CGRect(x: 104, y: 124, width: 232, height: 78),
            chordLayouts: [chordLayout],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [cueTextLayout],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 340, y: 156, width: 1.6, height: 34),
            isOpen: false
        )
        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 0,
            frame: CGRect(x: 100, y: 120, width: 240, height: 90),
            staffLineYPositions: [],
            clefFrame: nil,
            keySignatureLayouts: [],
            keyTextFrame: nil,
            keyText: nil,
            timeSignatureFrame: nil,
            sectionTextFrame: nil,
            sectionText: nil,
            roadmapTextFrame: nil,
            roadmapText: nil,
            roadmapMarkerLayouts: [roadmapLayout],
            endingLayouts: [],
            measures: [measure]
        )
        let pageLayout = LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 500, height: 600),
            paperFrame: CGRect(x: 40, y: 30, width: 420, height: 540),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 60, y: 46, width: 380, height: 62),
                handwrittenFrame: CGRect(x: 60, y: 46, width: 380, height: 62),
                titleFrame: CGRect(x: 130, y: 58, width: 240, height: 34),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: nil,
                meterFrame: nil
            ),
            systems: [system]
        )

        return PageFixture(
            measureID: measureID,
            chordID: chordID,
            cueTextID: cueTextID,
            roadmapID: roadmapID,
            chordLayout: chordLayout,
            cueTextLayout: cueTextLayout,
            roadmapLayout: roadmapLayout,
            measure: measure,
            pageLayout: pageLayout
        )
    }
}
#endif
