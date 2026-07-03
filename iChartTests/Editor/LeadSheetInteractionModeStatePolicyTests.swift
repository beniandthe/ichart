#if canImport(UIKit)
import PencilKit
import XCTest
@testable import iChart

final class LeadSheetInteractionModeStatePolicyTests: XCTestCase {
    func testChordEntryPreservesOriginalPenWeight() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertEqual(policy.inkTool.inkType, .pen)
        XCTAssertEqual(policy.inkTool.width, 2.5, accuracy: 0.001)
    }

    func testInkToolPolicyUsesEraserForInkEraseMode() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: .rhythmicNotationEdit,
            inkToolMode: .erase
        )

        XCTAssertEqual(policy.inkToolMode, .erase)
        XCTAssertTrue(policy.canvasTool is PKEraserTool)
    }

    func testInkToolPolicyIgnoresEraseModeWhenCanvasIsNotInking() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: .browse,
            inkToolMode: .erase
        )

        XCTAssertEqual(policy.inkToolMode, .write)
        XCTAssertTrue(policy.canvasTool is PKInkingTool)
    }

    func testChordEntryKeepsSimulatorPointerInputForAutomation() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        #if targetEnvironment(simulator)
        XCTAssertEqual(policy.drawingPolicy, .anyInput)
        #else
        XCTAssertEqual(policy.drawingPolicy, .pencilOnly)
        #endif
    }

    func testChordEntryKeepsInkCanvasAndEnablesRenderedChordObjects() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertTrue(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.chordEditTapEnabled)
        XCTAssertTrue(policy.chordMovePanEnabled)
        XCTAssertFalse(policy.chordEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.chordEntry.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.chordEntry.requiresChordSelectionBeforeObjectActions)
        XCTAssertTrue(EditorCanvasMode.chordEntry.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.chordEntry.drawsAllChordObjectEditControls)
    }

    func testChordTargetingAcceptsInkAcrossFullRhythmSectionChordLane() throws {
        let chart = Chart.blank(title: "Top Lane Chord", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let inkStartInView = CGPoint(
            x: measure.chordWritingFrame.midX - 8,
            y: measure.chordWritingFrame.maxY - 8
        )
        let inkEndInView = CGPoint(
            x: measure.chordWritingFrame.midX + 8,
            y: measure.chordWritingFrame.maxY - 4
        )
        let localStart = CGPoint(
            x: inkStartInView.x - chordFrame.minX,
            y: inkStartInView.y - chordFrame.minY
        )
        let localEnd = CGPoint(
            x: inkEndInView.x - chordFrame.minX,
            y: inkEndInView.y - chordFrame.minY
        )

        XCTAssertTrue(measure.chordWritingFrame.contains(inkStartInView))
        XCTAssertFalse(measure.chordBandFrame.contains(inkStartInView))

        let drawing = PKDrawing(strokes: [
            stroke(points: [localStart, localEnd], creationDate: Date(timeIntervalSince1970: 30))
        ])
        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: layout
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThanOrEqual(target.fraction, 0)
        XCTAssertLessThan(target.fraction, 1)
    }

    func testChordActiveInkScopeUsesExpandedChordLanesInsteadOfWholePage() throws {
        let chart = Chart.blank(title: "Scoped Chord Lane", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)

        let scope = LeadSheetActiveInkScope.resolve(
            interactionMode: .chordEntry,
            chartLayoutStyle: chart.layoutStyle,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: layout
        )

        guard case .chords(let frame, let inputFrames) = scope else {
            XCTFail("Chord mode should resolve a scoped chord ink region.")
            return
        }

        XCTAssertNotEqual(frame, LeadSheetActiveInkScope.pageWritingFrame(for: layout))
        XCTAssertTrue(frame.contains(firstMeasure.chordWritingFrame))
        XCTAssertTrue(inputFrames.contains { $0.contains(firstMeasure.chordWritingFrame) })
        XCTAssertFalse(inputFrames.contains { $0.contains(CGPoint(x: firstMeasure.staffFrame.midX, y: firstMeasure.frame.maxY - 2)) })
    }

    func testChordWritingBandContainsExpandedLaneOutsideRenderedBand() throws {
        let chart = Chart.blank(title: "Simple Lane", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let expandedLanePoint = CGPoint(
            x: measure.chordWritingFrame.midX,
            y: (measure.chordWritingFrame.minY + measure.chordBandFrame.minY) / 2
        )

        XCTAssertTrue(measure.chordWritingFrame.contains(expandedLanePoint))
        XCTAssertFalse(measure.chordBandFrame.contains(expandedLanePoint))
        XCTAssertTrue(LeadSheetCanvasInteractionTargeting.chordWritingBandContains(expandedLanePoint, in: layout))
    }

    func testOnlyOutsideChordLaneTapConfirmsWaitingChordInk() {
        let chart = Chart.blank(title: "Confirm Drag", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let outsideLaneStart = CGPoint(x: layout.paperFrame.midX, y: layout.paperFrame.maxY - 28)
        let insideLaneStart = CGPoint(
            x: layout.systems[0].measures[0].chordWritingFrame.midX,
            y: layout.systems[0].measures[0].chordWritingFrame.midY
        )

        XCTAssertTrue(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: outsideLaneStart,
                pageLayout: layout,
                hasChordInk: true
            )
        )
        XCTAssertFalse(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: insideLaneStart,
                pageLayout: layout,
                hasChordInk: true
            )
        )
        XCTAssertFalse(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: outsideLaneStart,
                pageLayout: layout,
                hasChordInk: false
            )
        )
    }

    func testBrowseSelectModeEditsRenderedChordsWithoutInkCanvas() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .browse)

        XCTAssertFalse(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.chordEditTapEnabled)
        XCTAssertTrue(policy.chordMovePanEnabled)
        XCTAssertFalse(policy.chordEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.browse.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.browse.requiresChordSelectionBeforeObjectActions)
        XCTAssertTrue(EditorCanvasMode.browse.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.browse.drawsAllChordObjectEditControls)
    }

    func testBrowseSelectModeRoutesHeaderTapsToHeaderAuthoring() {
        let chart = Chart.blank(title: "Header Tap", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let headerPoint = CGPoint(
            x: layout.header.handwrittenFrame.midX,
            y: layout.header.handwrittenFrame.midY
        )
        let measurePoint = CGPoint(
            x: layout.systems[0].measures[0].frame.midX,
            y: layout.systems[0].measures[0].frame.midY
        )

        XCTAssertTrue(EditorCanvasMode.browse.allowsHeaderAuthoringSelection)
        XCTAssertFalse(EditorCanvasMode.measureEdit.allowsHeaderAuthoringSelection)
        XCTAssertFalse(EditorCanvasMode.headerEntry.allowsHeaderAuthoringSelection)
        XCTAssertTrue(
            LeadSheetCanvasInteractionTargeting.headerAuthoringContains(headerPoint, in: layout)
        )
        XCTAssertFalse(
            LeadSheetCanvasInteractionTargeting.headerAuthoringContains(measurePoint, in: layout)
        )
    }

    func testFreehandObjectSelectionIsDisabledForRawPageInk() {
        XCTAssertFalse(EditorCanvasMode.browse.allowsFreehandObjectSelection)
        XCTAssertFalse(EditorCanvasMode.freeHand.allowsFreehandObjectSelection)
        XCTAssertFalse(EditorCanvasMode.measureEdit.allowsFreehandObjectSelection)
        XCTAssertFalse(EditorCanvasMode.chordEntry.allowsFreehandObjectSelection)
    }

    func testOnlyInkModesRestrictPageScrollToOutsideMargins() {
        XCTAssertFalse(EditorCanvasMode.browse.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.measureEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.repeatEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.timeSignatureEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.rhythmicNotationEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.headerEntry.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.chordEntry.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.noteEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.freeHand.restrictsPageScrollToOutsideMargins)
    }

    func testInkResponsivenessPolicyClampsValues() {
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(-0.4), 0)
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(1.4), 1)
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(0.65), 0.65)
    }

    func testInkResponsivenessPolicyMapsHigherValuesToMoreInputCoalescing() {
        let direct = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: 0)
        let balanced = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(
            for: LeadSheetInkResponsivenessPolicy.defaultValue
        )
        let smooth = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: 1)

        XCTAssertLessThan(direct, balanced)
        XCTAssertLessThan(balanced, smooth)
        XCTAssertEqual(direct, 0.004, accuracy: 0.001)
        XCTAssertEqual(smooth, 0.030, accuracy: 0.001)
    }

    func testFreehandTabTitleStaysStableWhenActive() {
        XCTAssertEqual(EditorCanvasMode.browse.freeHandTabTitle, "Free-Hand")
        XCTAssertEqual(EditorCanvasMode.repeatEdit.freeHandTabTitle, "Free-Hand")
        XCTAssertEqual(EditorCanvasMode.rhythmicNotationEdit.freeHandTabTitle, "Free-Hand")
        XCTAssertEqual(EditorCanvasMode.headerEntry.freeHandTabTitle, "Free-Hand")
        XCTAssertEqual(EditorCanvasMode.freeHand.freeHandTabTitle, "Free-Hand")
        XCTAssertEqual(EditorCanvasMode.freeHand.freeHandTabSymbol, "pencil.and.scribble")
    }

    func testActiveToolControlsAreShownOutsideBrowseMode() {
        XCTAssertFalse(EditorCanvasMode.browse.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.measureEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.repeatEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.timeSignatureEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.rhythmicNotationEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.headerEntry.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.chordEntry.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.noteEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.freeHand.showsActiveToolControls)
    }

    func testActiveToolMetadataMatchesPrimaryEditorModes() {
        XCTAssertEqual(EditorCanvasMode.browse.activeToolTitle, "Select")
        XCTAssertEqual(EditorCanvasMode.measureEdit.activeToolTitle, "Measures")
        XCTAssertEqual(EditorCanvasMode.repeatEdit.activeToolTitle, "Repeats")
        XCTAssertEqual(EditorCanvasMode.rhythmicNotationEdit.activeToolTitle, "Rhythm")
        XCTAssertEqual(EditorCanvasMode.headerEntry.activeToolTitle, "Header")
        XCTAssertEqual(EditorCanvasMode.chordEntry.activeToolTitle, "Chord")
        XCTAssertEqual(EditorCanvasMode.freeHand.activeToolTitle, "Free-Hand")
    }

    func testScrollMarginPolicyBlocksPaperGesturesOnlyWhenRestricted() {
        let paperFrame = CGRect(x: 100, y: 80, width: 300, height: 420)

        XCTAssertTrue(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 180, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: false
            )
        )
        XCTAssertFalse(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 180, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
        XCTAssertTrue(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 70, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
        XCTAssertFalse(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: paperFrame.minX - LeadSheetScrollMarginPolicy.paperHitSlop / 2, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
    }

    func testScrollMarginPolicyExposesVisibleDragAreaFramesOutsidePaper() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 600)
        let paperFrame = CGRect(x: 100, y: 80, width: 300, height: 420)

        let dragAreaFrames = LeadSheetScrollMarginPolicy.dragAreaFrames(
            in: bounds,
            paperFrame: paperFrame
        )

        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 40, y: 300)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 460, y: 300)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 40)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 560)) })
        XCTAssertFalse(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 300)) })
        XCTAssertFalse(dragAreaFrames.contains { $0.intersects(paperFrame) })
    }

    func testChordMoveDoesNotRecognizeSimultaneouslyWithParentScroll() {
        XCTAssertFalse(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: true,
                involvesParentScroll: true
            )
        )
        XCTAssertTrue(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: true,
                involvesParentScroll: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: false,
                involvesParentScroll: true
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyChordInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .chords(
                    frame: CGRect(x: 0, y: 0, width: 100, height: 40),
                    inputFrames: [CGRect(x: 0, y: 0, width: 100, height: 40)]
                ),
                interactionMode: .chordEntry,
                sessionState: dirtyInkSessionState(.chord),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyRhythmInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .rhythmicMeasure(
                    measureID: UUID(),
                    frame: CGRect(x: 0, y: 0, width: 100, height: 40)
                ),
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(.rhythm),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyHeaderInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyFreehandInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                interactionMode: .freeHand,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyAllowsPassiveInkReloadWhenCleanOrSynced() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x01])
            )
        )
    }

    func testInkCanvasSyncPolicyAllowsModelReloadWhenRhythmInkIsCleanOrAlreadySynced() {
        let activeScope = LeadSheetActiveInkScope.rhythmicMeasure(
            measureID: UUID(),
            frame: CGRect(x: 0, y: 0, width: 100, height: 40)
        )

        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: activeScope,
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: activeScope,
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(.rhythm),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x01])
            )
        )
    }

    func testFreehandActiveInkScopeUsesRawPageInkForAllV1Styles() {
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leadPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: rhythmPage
        )
        let leadScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .leadSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: leadPage
        )

        guard case .page(let simpleFrame) = simpleScope,
              case .page(let rhythmFrame) = rhythmScope,
              case .page(let leadFrame) = leadScope else {
            XCTFail("Free-Hand should resolve to raw page ink scopes")
            return
        }
        XCTAssertEqual(simpleFrame, LeadSheetActiveInkScope.pageWritingFrame(for: simplePage))
        XCTAssertEqual(rhythmFrame, LeadSheetActiveInkScope.pageWritingFrame(for: rhythmPage))
        XCTAssertEqual(leadFrame, LeadSheetActiveInkScope.pageWritingFrame(for: leadPage))
    }

    func testHeaderActiveInkScopeUsesHeaderFrameForAllV1Styles() {
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .headerEntry,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .headerEntry,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: rhythmPage
        )

        guard case .header(let simpleFrame) = simpleScope,
              case .header(let rhythmFrame) = rhythmScope else {
            XCTFail("Header writing should resolve a header ink scope")
            return
        }

        XCTAssertEqual(simpleFrame, simplePage.header.handwrittenFrame)
        XCTAssertEqual(rhythmFrame, rhythmPage.header.handwrittenFrame)
    }

    func testRhythmicNotationActiveInkScopeRequiresProfileRhythmTool() throws {
        let simpleChart = Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet)
        let rhythmChart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let leadChart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: simpleChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: rhythmChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leadPage = LeadSheetPageLayoutEngine.pageLayout(
            for: leadChart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleMeasureLayout = try XCTUnwrap(simplePage.systems.first?.measures.first)
        let rhythmMeasureLayout = try XCTUnwrap(rhythmPage.systems.first?.measures.first)
        let leadMeasureLayout = try XCTUnwrap(leadPage.systems.first?.measures.first)
        let simpleMeasureID = try XCTUnwrap(simpleChart.measures.first?.id)
        let rhythmMeasureID = try XCTUnwrap(rhythmChart.measures.first?.id)
        let leadMeasureID = try XCTUnwrap(leadChart.measures.first?.id)

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: simpleMeasureID,
            selectedMeasureLayout: simpleMeasureLayout,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: rhythmMeasureID,
            selectedMeasureLayout: rhythmMeasureLayout,
            pageLayout: rhythmPage
        )
        let leadScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .leadSheet,
            selectedMeasureID: leadMeasureID,
            selectedMeasureLayout: leadMeasureLayout,
            pageLayout: leadPage
        )

        XCTAssertNil(simpleScope)
        guard case .rhythmicMeasure(rhythmMeasureID, _) = rhythmScope,
              case .rhythmicMeasure(leadMeasureID, _) = leadScope else {
            XCTFail("Rhythm Section and Lead Sheet should resolve rhythm ink scopes")
            return
        }
        XCTAssertEqual(rhythmMeasureID, rhythmChart.measures.first?.id)
        XCTAssertEqual(leadMeasureID, leadChart.measures.first?.id)
    }

    func testRhythmicNotationActiveInkScopeUsesExpandedCaptureFrame() throws {
        let chart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let page = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measureLayout = try XCTUnwrap(page.systems.first?.measures.first)
        let measureID = try XCTUnwrap(chart.measures.first?.id)

        let scope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: measureID,
            selectedMeasureLayout: measureLayout,
            pageLayout: page
        )

        guard case .rhythmicMeasure(_, let captureFrame) = scope else {
            XCTFail("Rhythm Section should resolve an expanded rhythm ink scope")
            return
        }

        let legacyFrame = measureLayout.writableFrame.insetBy(dx: 2, dy: 2)
        XCTAssertEqual(
            captureFrame,
            LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(for: measureLayout)
        )
        XCTAssertTrue(captureFrame.contains(measureLayout.writableFrame))
        XCTAssertLessThan(captureFrame.minX, legacyFrame.minX)
        XCTAssertLessThan(captureFrame.minY, legacyFrame.minY)
        XCTAssertGreaterThan(captureFrame.maxX, legacyFrame.maxX)
        XCTAssertGreaterThan(captureFrame.maxY, legacyFrame.maxY)
    }

    func testRhythmTapFinalizeUsesExpandedCaptureFrame() throws {
        let chart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let page = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measureLayout = try XCTUnwrap(page.systems.first?.measures.first)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let oldTapFrame = measureLayout.writableFrame.insetBy(dx: -8, dy: -8)
        let expandedTapFrame = LeadSheetRhythmicNotationInkCapturePolicy.tapFinalizeFrame(
            for: measureLayout
        )
        XCTAssertGreaterThan(expandedTapFrame.maxY, oldTapFrame.maxY)

        let stillWritingLocation = CGPoint(
            x: expandedTapFrame.midX,
            y: (oldTapFrame.maxY + expandedTapFrame.maxY) / 2
        )
        XCTAssertFalse(oldTapFrame.contains(stillWritingLocation))
        XCTAssertTrue(expandedTapFrame.contains(stillWritingLocation))
        XCTAssertFalse(
            LeadSheetRhythmicNotationFinalization.shouldFinalizeTap(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                activeMeasureLayout: measureLayout,
                location: stillWritingLocation,
                nextMeasureID: measureID
            )
        )
    }

    func testSimpleRowGroupAffordanceGroupsSelectedMeasureThroughCurrentRow() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let affordance = try XCTUnwrap(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: measureIDs[1],
                in: layout,
                layoutStyle: chart.layoutStyle
            )
        )
        let selectedMeasure = try XCTUnwrap(
            layout.systems[0].measures.first { $0.sourceMeasureID == measureIDs[1] }
        )
        let lastGroupedMeasure = try XCTUnwrap(
            layout.systems[0].measures.first { $0.sourceMeasureID == measureIDs[3] }
        )

        XCTAssertEqual(affordance.selectedMeasureID, measureIDs[1])
        XCTAssertEqual(affordance.groupedMeasureIDs, Array(measureIDs[1..<4]))
        XCTAssertEqual(affordance.groupFrame.minX, selectedMeasure.frame.minX, accuracy: 0.001)
        XCTAssertEqual(affordance.groupFrame.maxX, lastGroupedMeasure.frame.maxX, accuracy: 0.001)
        XCTAssertLessThan(affordance.guideY, affordance.groupFrame.midY)
    }

    func testSimpleRowGroupAffordanceIsSimpleOnly() throws {
        let chart = Chart.blank(title: "Pocket", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertNil(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: measureID,
                in: layout,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: nil,
                in: layout,
                layoutStyle: .simpleChordSheet
            )
        )
    }

    func testRhythmAutoApplyRequiresStableNonEmptyScheduledSnapshot() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertTrue(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
                currentInkSnapshot: nil,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
                currentInkSnapshot: nil,
                scheduledInkSnapshot: nil
            )
        )
    }

    func testInkAuthoringSessionPolicyRequiresStableSnapshotForScheduledRecognitionWork() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertTrue(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: nil
            )
        )
    }

    func testRhythmLiveAdvisoryRecognitionAnalyzesStableSelectedRhythmInk() {
        let measureID = UUID()
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertFalse(LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.persistsLiveInkDuringAdvisory)
        XCTAssertTrue(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
    }

    func testRhythmLiveAdvisoryRecognitionRejectsStaleOrUnselectedInk() {
        let measureID = UUID()
        let otherMeasureID = UUID()
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: otherMeasureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .browse,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
    }

    func testRhythmAutoApplySnapshotIgnoresSerializedDrawingMetadata() {
        let firstDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let secondDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 20))])
        let firstSnapshot = LeadSheetInkDrawingSnapshot(drawing: firstDrawing)
        let secondSnapshot = LeadSheetInkDrawingSnapshot(drawing: secondDrawing)

        XCTAssertNotNil(firstSnapshot)
        XCTAssertNotNil(secondSnapshot)
        XCTAssertTrue(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAttemptAutoApply(
                currentInkSnapshot: firstSnapshot,
                scheduledInkSnapshot: secondSnapshot
            )
        )
    }

    func testRhythmAutoApplyRequiresNaturalExactFit() {
        let naturallyExactProposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .half],
            safety: .autoApply,
            isNaturalExactFit: true
        )
        let stretchedProposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .half],
            safety: .autoApply,
            isNaturalExactFit: false
        )

        XCTAssertFalse(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAutoApplyProposal(
                stretchedProposal,
                requiresNaturalExactFitAfterErase: true
            )
        )
        XCTAssertTrue(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAutoApplyProposal(
                naturallyExactProposal,
                requiresNaturalExactFitAfterErase: true
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAutoApplyPolicy.canAutoApplyProposal(
                stretchedProposal,
                requiresNaturalExactFitAfterErase: false
            )
        )
    }

    func testRhythmAutoApplyKeepsGraceWindowAfterFirstExactFitSnapshot() {
        let totalAutoApplyDelay = LeadSheetRhythmicNotationAutoApplyPolicy.idleDelay
            + LeadSheetRhythmicNotationAutoApplyPolicy.exactFitGraceDelay

        XCTAssertGreaterThanOrEqual(totalAutoApplyDelay, 1.0)
        XCTAssertLessThanOrEqual(totalAutoApplyDelay, 1.4)
    }

    func testRhythmTapToRenderAdvisoryWaitsLongerThanLegacyAutoApply() {
        XCTAssertGreaterThan(
            LeadSheetRhythmicNotationAutoApplyPolicy.tapToRenderAdvisoryDelay,
            LeadSheetRhythmicNotationAutoApplyPolicy.idleDelay
        )
        XCTAssertLessThanOrEqual(
            LeadSheetRhythmicNotationAutoApplyPolicy.tapToRenderAdvisoryDelay,
            1.3
        )
    }

    func testRhythmAutoApplyExtendsGraceForAmbiguousTerminalStem() {
        let normalAutoApplyDelay = LeadSheetRhythmicNotationAutoApplyPolicy.idleDelay
            + LeadSheetRhythmicNotationAutoApplyPolicy.exactFitGraceDelay(
                requiresExtendedStability: false
            )
        let ambiguousAutoApplyDelay = LeadSheetRhythmicNotationAutoApplyPolicy.idleDelay
            + LeadSheetRhythmicNotationAutoApplyPolicy.exactFitGraceDelay(
                requiresExtendedStability: true
            )

        XCTAssertGreaterThan(
            ambiguousAutoApplyDelay,
            normalAutoApplyDelay
        )
        XCTAssertLessThanOrEqual(ambiguousAutoApplyDelay, 2.3)
    }

    func testRhythmLiveDecisionRouteMarksSafeProposalReadyUntilUserTap() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .autoApply,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        guard case .readyToRender(let values) = route else {
            return XCTFail("Expected a safe full-measure phrase to wait for tap-to-render.")
        }
        XCTAssertEqual(values, proposal.values)
    }

    func testRhythmLiveDecisionRouteCommitsSafeProposalDuringTapFinalization() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .autoApply,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false,
            allowsCommit: true
        )

        guard case .commit(let values, let requiresExtendedStability) = route else {
            return XCTFail("Expected tap finalization to commit a safe full-measure phrase.")
        }
        XCTAssertEqual(values, proposal.values)
        XCTAssertFalse(requiresExtendedStability)
    }

    func testRhythmLiveAdvisoryRecognitionNeverCommitsRenderedValues() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .autoApply,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )
        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .readyToRender(values: proposal.values))
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldCommitFromAdvisoryRoute(route)
        )
    }

    func testRhythmLiveDecisionRoutePreservesManualReviewWithoutConfirmationFallback() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .manualReview,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.needsReview(
            .manualReview,
            completedRhythmPhrase(values: proposal.values),
            proposal
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testRhythmLiveDecisionRouteShowsUnderfilledFeedbackWhenInkWasRecognized() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .rasterTemplate,
                primitives: [],
                symbols: [],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter],
                naturalUnits: 4,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
        XCTAssertEqual(
            LeadSheetRhythmicNotationFeedbackPolicy.feedbackMessage(for: decision),
            "Needs 2 more beats"
        )
    }

    func testRhythmUnderfilledFeedbackNamesSingleMissingBeat() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .rasterTemplate,
                primitives: [],
                symbols: [
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [0],
                        bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                        candidateValues: [.eighth],
                        selectedValue: .eighth
                    )
                ],
                uncoveredStrokeIndices: [],
                naturalValues: [.eighth, .eighth, .half],
                naturalUnits: 6,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
        XCTAssertEqual(
            LeadSheetRhythmicNotationFeedbackPolicy.feedbackMessage(for: decision),
            "Needs 1 more beat"
        )
    }

    func testRhythmLiveDecisionRouteLocalizesUnreadFeedbackForCompleteFailedPhrase() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .unsupported,
            RhythmPhraseHypothesis(
                source: .rasterTemplate,
                primitives: [],
                symbols: [
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [0],
                        bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [1],
                        bounds: CGRect(x: 46, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [2],
                        bounds: CGRect(x: 80, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [3],
                        bounds: CGRect(x: 114, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [4],
                        bounds: CGRect(x: 150, y: 18, width: 10, height: 30),
                        candidateValues: [],
                        selectedValue: nil
                    )
                ],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter, .quarter, .quarter],
                naturalUnits: 8,
                targetUnits: 8,
                passesCompendium: true
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testRhythmUnreadInkFeedbackWaitsForCompletedTargetedDecision() {
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.nonVisualFallback, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .needsReview(.ambiguousPhrase, nil, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.underfilled, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.noInk, nil)
            )
        )
    }

    func testRhythmUnreadInkFeedbackDoesNotFallbackToWholeCanvasFrame() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.nonVisualFallback, nil),
            canvasFrame: CGRect(x: 30, y: 40, width: 120, height: 80)
        )

        XCTAssertNil(feedbackFrame)
    }

    func testRhythmUnreadInkFeedbackFramesUnderfilledInkImmediately() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .rasterTemplate,
                primitives: [],
                symbols: [],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter],
                naturalUnits: 4,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        XCTAssertTrue(LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(for: decision))

        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: decision,
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 38, y: 92)) ?? false)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 50, y: 68)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 160, y: 120)) ?? true)
    }

    func testRhythmUnreadInkFeedbackTargetsUncoveredStrokeFrameWhenAvailable() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .visual,
            primitives: [
                RhythmInkPrimitive(
                    strokeIndex: 0,
                    kind: .slash,
                    bounds: CGRect(x: 8, y: 52, width: 12, height: 18)
                ),
                RhythmInkPrimitive(
                    strokeIndex: 1,
                    kind: .unknown,
                    bounds: CGRect(x: 78, y: 20, width: 6, height: 24)
                )
            ],
            symbols: [],
            uncoveredStrokeIndices: [1],
            naturalValues: [.slash, .slash, .slash, .slash],
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )

        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.uncoveredStrokes, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 111, y: 72)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 44, y: 101)) ?? true)
    }

    func testRhythmUnreadInkFeedbackDoesNotTargetUnreadV4SymbolBeforeMeasureIsComplete() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: [],
            symbols: [
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [0],
                    bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [1],
                    bounds: CGRect(x: 86, y: 18, width: 10, height: 30),
                    candidateValues: [],
                    selectedValue: nil
                )
            ],
            uncoveredStrokeIndices: [],
            naturalValues: [.quarter],
            naturalUnits: 2,
            targetUnits: 8,
            passesCompendium: false
        )

        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.unsupported, phrase)
            )
        )
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.unsupported, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNil(feedbackFrame)
    }

    func testRhythmUnreadInkFeedbackTargetsUnreadV4SymbolFrameWhenMeasureIsComplete() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: [],
            symbols: [
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [0],
                    bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [1],
                    bounds: CGRect(x: 46, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [2],
                    bounds: CGRect(x: 80, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [3],
                    bounds: CGRect(x: 114, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [4],
                    bounds: CGRect(x: 150, y: 18, width: 10, height: 30),
                    candidateValues: [],
                    selectedValue: nil
                )
            ],
            uncoveredStrokeIndices: [],
            naturalValues: [.quarter, .quarter, .quarter, .quarter],
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )

        XCTAssertTrue(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.unsupported, phrase)
            )
        )
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.unsupported, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 180, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 184, y: 62)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 45, y: 93)) ?? true)
    }

    private func completedRhythmPhrase(values: [RhythmValue]) -> RhythmPhraseHypothesis {
        RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: [],
            symbols: [],
            uncoveredStrokeIndices: [],
            naturalValues: values,
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )
    }

    private func dirtyInkSessionState(
        _ roles: LeadSheetInkAuthoringSessionRole...
    ) -> LeadSheetInkAuthoringSessionState {
        var state = LeadSheetInkAuthoringSessionState()
        roles.forEach { state.markDirty($0) }
        return state
    }

    private func snapshotStroke(creationDate: Date) -> PKStroke {
        stroke(
            points: [
                CGPoint(x: 8, y: 52),
                CGPoint(x: 20, y: 28)
            ],
            creationDate: creationDate
        )
    }

    private func stroke(points: [CGPoint], creationDate: Date) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.05,
                size: CGSize(width: 2, height: 2),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: creationDate)
        )
    }
}
#endif
