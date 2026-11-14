#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import iChart

/// Mounts the shipping EditorView and injects frozen proposals through its
/// actual canvas callback. These are status/recovery tests, not accuracy tests.
@MainActor
final class ChordInkAutomaticFeedbackUITests: XCTestCase {
    private weak var frozenManualCanvas: LeadSheetCanvasUIKitView?
    private var allowsFrozenManualPreflight = true

    func testSimpleAutomaticBarlineDownbeatHelperKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .simpleChordSheet, manual: false)
    }

    func testSimpleManualBarlineDownbeatHelperKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .simpleChordSheet, manual: true)
    }

    func testRhythmAutomaticBarlineDownbeatHelperKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .rhythmSectionSheet, manual: false)
    }

    func testRhythmManualBarlineDownbeatHelperKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .rhythmSectionSheet, manual: true)
    }

    func testRhythmManualWritingHelperAtLargestStandardTextKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .rhythmSectionSheet, manual: true,
            dynamicTypeSize: .xxxLarge)
    }

    func testSimpleAutomaticWritingGuideInLandscapeKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .simpleChordSheet, manual: false, landscape: true)
    }

    func testSimpleManualWritingGuideInLandscapeKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .simpleChordSheet, manual: true, landscape: true)
    }

    func testRhythmAutomaticWritingGuideInLandscapeKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .rhythmSectionSheet, manual: false, landscape: true)
    }

    func testRhythmManualWritingGuideInLandscapeKeepsControlsReachableAndCanvasSteady() async throws {
        try await assertBarlineDownbeatHelper(layoutStyle: .rhythmSectionSheet, manual: true, landscape: true)
    }

    func testAutomaticToolGuideRestoresOriginalInjectedTimingOnlyAfterSourceRefresh() async throws {
        try await assertAutomaticGuideEpisodeResume(changesVisibleSource: false)
    }

    func testAutomaticToolGuideDoesNotResumeWhenVisibleSourceChanges() async throws {
        try await assertAutomaticGuideEpisodeResume(changesVisibleSource: true)
    }

    private func assertAutomaticGuideEpisodeResume(changesVisibleSource: Bool) async throws {
        // These are injected episode/census boundary tests. No Pencil event,
        // recognition accuracy, or natural retry is inferred from them.
        var censusReplayCount = 0
        let mounted = try await mount(manual: false, coordinatorOverride: { coordinator in
            coordinator.automaticCensusReplayer = {
                censusReplayCount += 1
                return true
            }
        })
        let expected = EditorCanvasMode.chordEntry.toolGuidance(layoutStyle: mounted.model.chart.layoutStyle,
            manualRenderWithPreview: false)
        let coordinator = try XCTUnwrap(mounted.canvas.chordDraftRenderCoordinator)
        let source = try XCTUnwrap(coordinator.currentSourceDrawing(),
            "Automatic help must read the actual source without relying on manual-preview readiness")
        XCTAssertFalse(source.strokes.isEmpty)
        let before = await settledCanvasFrame(in: mounted)
        let geometryBefore = guideGeometryDiagnostics(in: mounted)
        // Future injected deadlines keep the real renderer from racing the
        // presentation assertion. Closing help must restore these exact
        // values, rather than manufacturing a new input timestamp.
        let inputAt = Date().addingTimeInterval(60)
        // This frozen-reader fixture models an input episode. Its reader is
        // disabled, so it has no separate reader-readiness timestamp to restore.
        let readyAt: Date? = nil
        coordinator.lastInputAt = inputAt
        coordinator.renderSessionReadyAt = readyAt
        censusReplayCount = 0
        try activate(await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == expected.detailsTitle
        })
        let guideDone = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Done"
                && isInsidePresentedPanel($0, in: mounted.window)
        }
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if mounted.canvas.isInteractionSuspended,
               coordinator.lastInputAt == nil, coordinator.renderSessionReadyAt == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(mounted.canvas.isInteractionSuspended,
            "The guide must suspend underlying handwriting and automatic commits")
        XCTAssertNil(coordinator.lastInputAt)
        XCTAssertNil(coordinator.renderSessionReadyAt)
        XCTAssertEqual(censusReplayCount, 0, "Opening help must not resume or refresh an automatic episode")
        if changesVisibleSource {
            let live = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
            XCTAssertGreaterThan(source.strokes.count, 1)
            live.drawing = PKDrawing(strokes: Array(source.strokes.dropFirst()))
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: source, current: try XCTUnwrap(coordinator.currentSourceDrawing())))
        }
        try activate(guideDone)
        try await waitForReviewDismissal(in: mounted)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if !mounted.canvas.isInteractionSuspended,
               changesVisibleSource || coordinator.lastInputAt == inputAt { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(mounted.canvas.isInteractionSuspended)
        if changesVisibleSource {
            XCTAssertEqual(censusReplayCount, 0,
                "Changed visible source cannot reuse the episode captured before opening help")
            XCTAssertNotEqual(coordinator.lastInputAt, inputAt,
                "A drawing-change callback may supply fresh timing, but the captured old episode cannot be restored")
            XCTAssertNil(coordinator.renderSessionReadyAt)
        } else {
            XCTAssertEqual(censusReplayCount, 1,
                "Unchanged source requires one refreshed census before restoring the suspended episode")
            XCTAssertEqual(coordinator.lastInputAt, inputAt)
            XCTAssertEqual(coordinator.renderSessionReadyAt, readyAt)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: source, current: try XCTUnwrap(coordinator.currentSourceDrawing())))
        }
        let after = await settledCanvasFrame(in: mounted)
        attachGuideGeometry(before: geometryBefore, in: mounted, name: "Injected automatic guide episode")
        XCTAssertEqual(after, before)
        XCTAssertTrue(mounted.model.chart.measures.allSatisfy(\.chordEvents.isEmpty),
            "An injected guide-presentation test must not commit a chord")
    }

    private func assertBarlineDownbeatHelper(layoutStyle: ChartLayoutStyle, manual: Bool,
        dynamicTypeSize: DynamicTypeSize? = nil, landscape: Bool = false) async throws {
        var chart = Chart.blank(title: "Structured writing guidance", measureCount: 1, layoutStyle: layoutStyle)
        _ = chart.setPageHandwrittenChordDrawing(drawing().dataRepresentation())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let sceneSize = scene.coordinateSpace.bounds.size
        let shortSide = min(sceneSize.width, sceneSize.height)
        let longSide = max(sceneSize.width, sceneSize.height)
        let requestedViewport = landscape ? CGSize(width: longSide, height: shortSide)
            : CGSize(width: shortSide, height: longSide)
        let mounted = try await mount(manual: manual, viewport: requestedViewport, initialChart: chart,
            dynamicTypeSize: dynamicTypeSize)
        // Enter through the actual primary buttons, rather than only asserting
        // the injected initial mode. Source is frozen before the first layout.
        try activate(await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Select"
        })
        try activate(await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Write & Render"
        })
        let expected = EditorCanvasMode.chordEntry.toolGuidance(layoutStyle: layoutStyle,
            manualRenderWithPreview: manual)
        let viewport = mounted.window.bounds.insetBy(dx: -1, dy: -1)

        func assertVisibleGuidance() async throws -> CGRect {
            let purpose = try await waitForNode(in: mounted.window) {
                !$0.isButton && $0.element.accessibilityLabel == expected.title
            }
            XCTAssertEqual(purpose.element.accessibilityLabel, expected.title)
            var frame = purpose.frame(in: mounted.window)
            for (index, text) in expected.steps.enumerated() {
                let step = try await waitForNode(in: mounted.window) {
                    !$0.isButton && $0.element.accessibilityLabel == text
                }
                XCTAssertEqual(step.element.accessibilityLabel, text)
                XCTAssertTrue(viewport.contains(step.frame(in: mounted.window)),
                    "Each short next action must wrap fully within the viewport")
                frame = frame.union(step.frame(in: mounted.window))
            }
            let context = try await waitForNode(in: mounted.window) {
                !$0.isButton && $0.element.accessibilityLabel == (manual ? "Rendering: Manual" : "Rendering: Automatic")
            }
            XCTAssertEqual(context.element.accessibilityLabel, manual ? "Rendering: Manual" : "Rendering: Automatic")
            frame = frame.union(context.frame(in: mounted.window))
            XCTAssertTrue(viewport.contains(frame), "Purpose, mode, and next actions must remain visible together")
            return frame
        }

        let helperFrame = try await assertVisibleGuidance()
        let control = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == (manual ? "Done" : "Write")
        }
        let controlFrame = manual
            ? try await renderedActionFrame("Render Chords", below: helperFrame.maxY, in: mounted.window)
            : control.frame(in: mounted.window)
        XCTAssertFalse(controlFrame.isEmpty)
        XCTAssertTrue(viewport.contains(controlFrame), "The writing/render control must remain reachable")
        XCTAssertTrue(control.isEnabled)
        XCTAssertLessThan(helperFrame.maxY, controlFrame.minY, "The helper belongs above the writing controls")
        let beforeGuide = await settledCanvasFrame(in: mounted)
        let geometryBeforeGuide = guideGeometryDiagnostics(in: mounted)
        let sourceBeforeGuide = mounted.model.chart.pageHandwrittenChordData
        let guide = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == expected.detailsTitle
        }
        XCTAssertEqual(guide.element.accessibilityLabel, expected.detailsTitle)
        XCTAssertTrue(viewport.contains(guide.frame(in: mounted.window)))
        try activate(guide)
        let closeGuide = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Done"
                && isInsidePresentedPanel($0, in: mounted.window)
        }
        XCTAssertTrue(closeGuide.isEnabled)
        XCTAssertNotNil(mounted.window.rootViewController?.presentedViewController,
            "The detailed drawing guide must be reachable from the tool")
        try activate(closeGuide)
        try await waitForReviewDismissal(in: mounted)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenChordData, sourceBeforeGuide,
            "Opening and closing the guide cannot consume or rewrite source ink")
        let before = await settledCanvasFrame(in: mounted)
        attachGuideGeometry(before: geometryBeforeGuide, in: mounted, name: "\(layoutStyle.rawValue) \(manual ? "Manual" : "Automatic") guide")
        XCTAssertEqual(before, beforeGuide, "Local help must return to the same writing geometry")
        let visibleCanvas = before.intersection(viewport)
        XCTAssertGreaterThanOrEqual(visibleCanvas.width, 320, "The short guide must leave usable canvas width")
        XCTAssertGreaterThanOrEqual(visibleCanvas.height, landscape ? 200 : 300,
            "The short guide and controls must leave visible room to write")

        try await injectUncertainPair(into: mounted)
        let currentHelperFrame = try await assertVisibleGuidance()
        let feedbackFrame: CGRect
        if manual {
            feedbackFrame = try await renderedActionFrame("Review & Render", below: currentHelperFrame.maxY,
                in: mounted.window)
        } else {
            let feedbackControl = try await waitForNode(in: mounted.window) {
                $0.isButton && $0.element.accessibilityLabel == placementRefusalLabel
            }
            XCTAssertTrue(feedbackControl.isEnabled)
            feedbackFrame = feedbackControl.frame(in: mounted.window)
        }
        XCTAssertTrue(viewport.contains(feedbackFrame), "Inline feedback must not push its action out of reach")
        XCTAssertLessThan(currentHelperFrame.maxY, feedbackFrame.minY)
        let after = await settledCanvasFrame(in: mounted)
        XCTAssertEqual(after.minX, before.minX, accuracy: 0.1)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.1)
        XCTAssertEqual(after.width, before.width, accuracy: 0.1)
        XCTAssertEqual(after.height, before.height, accuracy: 0.1,
            "Guidance and inline recognition feedback must leave the writing canvas steady")
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
        let styleName = layoutStyle == .simpleChordSheet ? "Simple" : "Rhythm"
        let size = dynamicTypeSize == nil ? "" : " at xxxLarge text"
        attach(mounted.window, name: "\(styleName) \(manual ? "Manual" : "Automatic") structured guide \(landscape ? "landscape" : "portrait")\(size)")
    }

    func testSimpleFirstConvertedMarkKeepsTheEditorWritingCanvasSteady() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        let chart = Chart.blank(title: "Simple first mark layout", measureCount: 4, layoutStyle: .simpleChordSheet)
        let mounted = try await mount(manual: true, repository: repository, initialChart: chart, freezesRecognition: false)
        try activate(await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Free Ink"
        })
        _ = try await waitForNode(in: mounted.window) {
            !$0.isButton
                && $0.element.accessibilityLabel == "Write notes and reminders on the page"
        }
        let canvas = mounted.canvas
        XCTAssertEqual(canvas.interactionMode, .freeHand)
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        mounted.window.layoutIfNeeded()
        XCTAssertTrue(canvas.window === mounted.window)
        XCTAssertFalse(live.isHidden)
        XCTAssertTrue(live.isUserInteractionEnabled)
        XCTAssertGreaterThan(live.bounds.height, 500, "The page canvas must own Free Ink before injecting a stroke")
        let before = canvas.convert(canvas.bounds, to: mounted.window)
        let beforeInkFrame = live.frame
        let path = PKStrokePath(controlPoints: [CGPoint(x: 100, y: 400), CGPoint(x: 125, y: 410),
            CGPoint(x: 100, y: 420)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        canvas.canvasViewDidBeginUsingTool(live)
        live.drawing = drawing
        canvas.canvasViewDrawingDidChange(live)
        canvas.canvasViewDidEndUsingTool(live)
        _ = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Restore Ink"
        }
        for _ in 0..<10 {
            mounted.window.layoutIfNeeded()
            let after = canvas.convert(canvas.bounds, to: mounted.window)
            XCTAssertEqual(after.minX, before.minX, accuracy: 0.1)
            XCTAssertEqual(after.minY, before.minY, accuracy: 0.1)
            XCTAssertEqual(after.size.width, before.size.width, accuracy: 0.1)
            XCTAssertEqual(after.size.height, before.size.height, accuracy: 0.1)
            XCTAssertEqual(live.frame, beforeInkFrame)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(canvas.chart.freeInkArticulations.count, 1)
        XCTAssertEqual(canvas.chart.freeInkArticulations.first?.kind, .accent)
        XCTAssertTrue(live.drawing.strokes.isEmpty)
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
        attach(mounted.window, name: "Simple first automatic mark keeps the writing canvas steady")
    }

    func testSimpleFreeInkExplainerAndRestoreMenuAreVisibleAtTheNormalEntryPoint() async throws {
        var chart = Chart.blank(title: "Simple articulation guidance", measureCount: 4, layoutStyle: .simpleChordSheet)
        let path = PKStrokePath(controlPoints: [CGPoint(x: 190, y: 190), CGPoint(x: 210, y: 200),
            CGPoint(x: 190, y: 210)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let source = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        let point = FreeInkArticulationPagePoint(pageIndex: 0, x: 200, y: 200)
        chart.freeInkArticulations = [FreeInkArticulation(kind: .accent,
            sourceInkData: source.dataRepresentation(), pagePoint: point, sourcePagePoint: point)]
        let mounted = try await mount(manual: true, initialChart: chart)
        try activate(await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Free Ink"
        })
        let helper = try await waitForNode(in: mounted.window) {
            !$0.isButton
                && $0.element.accessibilityLabel == "Write notes and reminders on the page"
        }
        let restore = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Restore Ink"
        }
        XCTAssertTrue(restore.isEnabled)
        XCTAssertTrue(mounted.window.bounds.insetBy(dx: -1, dy: -1).contains(helper.frame(in: mounted.window)))
        XCTAssertTrue(mounted.window.bounds.insetBy(dx: -1, dy: -1).contains(restore.frame(in: mounted.window)))
        XCTAssertLessThan(helper.frame(in: mounted.window).maxY, restore.frame(in: mounted.window).minY)
        attach(mounted.window, name: "Simple Free Ink helper and Restore Ink at normal entry")
        XCTAssertEqual(mounted.model.chart.freeInkArticulations, chart.freeInkArticulations)
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
    }

    func testPlacementRefusalIsVisibleAndOpensFocusedFullReviewWithoutReorderingOrConsumingInk() async throws {
        let mounted = try await mount(manual: false)
        let sourceBefore = try XCTUnwrap(mounted.model.chart.pageHandwrittenChordData)
        let canvasFrameBefore = await settledCanvasFrame(in: mounted)
        try await injectUncertainPair(into: mounted)
        let drafts = mounted.canvas.chordPreviewState.draftChords
        XCTAssertEqual(drafts.map(\.previewText), ["C", "Bb"])
        XCTAssertTrue(drafts.allSatisfy { $0.recognitionDecision?.action == .confirm })
        let idsBefore = drafts.map(\.id)
        let status = try await waitForNode(in: mounted.window) { node in
            node.isButton && node.element.accessibilityLabel == placementRefusalLabel
        }
        XCTAssertEqual(status.element.accessibilityLabel, placementRefusalLabel)
        XCTAssertTrue(status.element.accessibilityValue?.isEmpty != false,
            "Automatic feedback must not present a normal pending-count Review all workflow")
        XCTAssertTrue(status.isEnabled)
        let statusFrame = status.frame(in: mounted.window)
        XCTAssertTrue(mounted.window.bounds.insetBy(dx: -1, dy: -1).contains(statusFrame),
            "The actionable uncertainty status must fit within the 820-point iPad viewport")
        mounted.window.layoutIfNeeded()
        let canvasFrameAfter = mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window)
        XCTAssertEqual(canvasFrameAfter.minX, canvasFrameBefore.minX, accuracy: 0.01)
        XCTAssertEqual(canvasFrameAfter.minY, canvasFrameBefore.minY, accuracy: 0.01)
        XCTAssertEqual(canvasFrameAfter.width, canvasFrameBefore.width, accuracy: 0.01)
        XCTAssertEqual(canvasFrameAfter.height, canvasFrameBefore.height, accuracy: 0.01,
            "Feedback updates must not move or resize the paper")
        attach(mounted.window, name: "Automatic feedback - visible placement refusal on iPad")
        // SwiftUI may replace its accessibility nodes during a layout or
        // capture. Activate the current visible control, not the earlier node.
        let currentStatus = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == placementRefusalLabel
        }
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.id), idsBefore)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenChordData, sourceBefore)
        try activate(currentStatus)

        let fields = try await waitForReviewFields(in: mounted.window, count: 2)
        XCTAssertEqual(fields.map(\.text), ["C", "Bb"],
            "Selecting the second unresolved target must retain the complete review in source order")
        XCTAssertEqual(fields.count, idsBefore.count, "Review must contain every current source-bound draft")
        let focused = try XCTUnwrap(fields.first { $0.isFirstResponder })
        XCTAssertEqual(focused.text, "Bb")
        XCTAssertTrue(focused === fields[1], "Tapping Bb must focus its second source-ordered review entry")
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.id), idsBefore)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenChordData, sourceBefore)
        attach(mounted.window, name: "Automatic feedback - full review focused on Bb")
        try await assertFocusedFieldVisibleInsideReview(focused, in: mounted)
        attach(mounted.window, name: "Automatic feedback - settled visible Bb review row")

        let back = try await waitForNode(in: mounted.window) { node in
            node.isButton && node.element.accessibilityLabel == "Back to Writing"
        }
        try activate(back)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if mounted.window.rootViewController?.presentedViewController == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
        let live = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
        let events = mounted.model.chart.measures.flatMap(\.chordEvents)
        let eventDrawings = try events.map { try PKDrawing(data: XCTUnwrap($0.sourceInkData)) }
        let allOwnedSource = PKDrawing(strokes: live.drawing.strokes + eventDrawings.flatMap(\.strokes))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: try PKDrawing(data: sourceBefore), current: allOwnedSource),
            "Automatic entry may resume after cancellation; every source stroke must still be owned exactly once")
        let stored = try mounted.model.chart.pageHandwrittenChordData.map(PKDrawing.init(data:)) ?? PKDrawing()
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: live.drawing, current: stored))
    }

    func testManualWorkflowKeepsItsReviewControlsAndHidesAutomaticStatusButtons() async throws {
        let mounted = try await mount(manual: true)
        let canvasTop = mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window).minY

        try await injectUncertainPair(into: mounted)
        let review = try await waitForNode(in: mounted.window) { node in
            node.isButton && node.element.accessibilityLabel == "Review & Render"
        }
        XCTAssertTrue(review.isEnabled)
        XCTAssertEqual(mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window).minY, canvasTop, accuracy: 1)
        attach(mounted.window, name: "RHY-003 manual Write and Render helper")
        let nodes = try NativeAccessibilityLookup.nodes(in: mounted.window)
        XCTAssertFalse(nodes.contains {
            guard $0.isButton, let label = $0.element.accessibilityLabel else { return false }
            return label.hasPrefix("Rendering ") || label == "No supported read. Fix writing"
                || label == "Reading chord" || label == "Writing chord"
                || label.hasPrefix("Saved chord ink.") || label.hasPrefix("Still reading chord.")
        })
        XCTAssertNotNil(mounted.model.chart.pageHandwrittenChordData)
        XCTAssertTrue(mounted.model.chart.measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testManualRenderSaveFailureKeepsChordInkAndRetrySavesTheRenderedBatchOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library-state.json")
        let disk = FileChartRepository(url: file)
        let repository = FailingFeedbackChartRepository(disk: disk)
        let mounted = try await mount(manual: true, repository: repository)
        let original = try XCTUnwrap(disk.loadSnapshot())
        let chartID = try XCTUnwrap(original.selectedChartID)
        let originalChart = try XCTUnwrap(original.charts.first { $0.id == chartID })
        let source = try PKDrawing(data: XCTUnwrap(originalChart.pageHandwrittenChordData))
        let originalDiskBytes = try Data(contentsOf: file)
        try await injectUncertainPair(into: mounted)
        let canvasFrameBefore = await settledCanvasFrame(in: mounted)

        func retryControl() async throws -> NativeAccessibilityLookup.Node {
            try await waitForNode(in: mounted.window) {
                $0.isButton && $0.element.accessibilityLabel == "Retry Save"
            }
        }

        let review = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Review & Render"
        }
        try activate(review)
        let fields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(fields.map(\.text), ["C", "Bb"])
        let render = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Render All"
        }
        repository.setWriteFailure(true)
        try activate(render)

        try await waitForReviewDismissal(in: mounted)
        let retry = try await retryControl()
        XCTAssertEqual(retry.element.accessibilityValue, "Chart not saved")
        let retryFrame = retry.frame(in: mounted.window)
        XCTAssertFalse(retryFrame.isEmpty)
        XCTAssertTrue(mounted.window.bounds.insetBy(dx: -1, dy: -1).contains(retryFrame))
        let canvasFrameAfter = await settledCanvasFrame(in: mounted)
        XCTAssertEqual(canvasFrameAfter.minY, canvasFrameBefore.minY, accuracy: 1,
            "A save warning must not move the writing canvas")
        attach(mounted.window, name: "RHY-005 rendered chart with a visible save retry")
        guard case .failed = mounted.store.persistenceStatus else {
            return XCTFail("The rendered chart must surface the repository's failed write")
        }
        XCTAssertEqual(try Data(contentsOf: file), originalDiskBytes, "Failed save must retain the previous durable draft")
        let inMemory = try XCTUnwrap(mounted.store.charts.first { $0.id == chartID })
        let rendered = inMemory.measures.flatMap(\.chordEvents)
        XCTAssertEqual(rendered.map(\.rawInput), ["C", "Bb"])
        XCTAssertEqual(rendered.count, source.strokes.count)
        XCTAssertNil(inMemory.pageHandwrittenChordData, "Rendered ink should move to event archives exactly once")
        for (stroke, chord) in zip(source.strokes, rendered) {
            let savedInk = try PKDrawing(data: XCTUnwrap(chord.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [stroke]), current: savedInk))
        }

        let failedWriteCount = repository.failedWriteCount
        XCTAssertGreaterThan(failedWriteCount, 0)
        try activate(await retryControl())
        for _ in 0..<60 {
            if repository.failedWriteCount > failedWriteCount, case .failed = mounted.store.persistenceStatus { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(repository.failedWriteCount, failedWriteCount, "A failed Retry Save must allow another attempt")
        XCTAssertEqual(try Data(contentsOf: file), originalDiskBytes)
        XCTAssertEqual(mounted.store.charts.first { $0.id == chartID }, inMemory)

        repository.setWriteFailure(false)
        try activate(await retryControl())
        for _ in 0..<60 {
            if case .saved = mounted.store.persistenceStatus { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard case .saved = mounted.store.persistenceStatus else {
            return XCTFail("Retry Save did not complete the real disk write")
        }
        let reopened = try XCTUnwrap(FileChartRepository(url: file).loadSnapshot())
        XCTAssertEqual(reopened.selectedChartID, chartID)
        let saved = try XCTUnwrap(reopened.charts.first { $0.id == chartID })
        XCTAssertEqual(saved.measures.map(\.id), originalChart.measures.map(\.id))
        XCTAssertEqual(saved.measures.flatMap(\.chordEvents), rendered, "Retry must save the same events and source without rendering again")
        XCTAssertNil(saved.pageHandwrittenChordData)
        XCTAssertNil(saved.pageHandwrittenChordCoordinateSpace)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if try NativeAccessibilityLookup.matching("Retry Save", in: mounted.window, buttonsOnly: true).isEmpty { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("A successful retry should dismiss the save warning")
    }

    func testManualReviewReopensLatestDelayedReadAndKeepsOnlySameInkEdits() async throws {
        let earlierInk = landscapeSourceDrawing()
        let detailPoints = [CGPoint(x: 310, y: 56), CGPoint(x: 311, y: 70)]
            .enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.02,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        let detail = PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: detailPoints, creationDate: Date(timeIntervalSinceReferenceDate: 3)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library-state.json")
        let mounted = try await mount(manual: true,
            sourceDrawing: earlierInk,
            repository: FileChartRepository(url: file))
        let chart = mounted.model.chart
        let initialSourceData = try XCTUnwrap(chart.pageHandwrittenChordData)
        let initialSource = try PKDrawing(data: initialSourceData)
        XCTAssertEqual(initialSource.strokes.count, 2)
        let source = PKDrawing(strokes: initialSource.strokes + [detail])
        var sourceData = initialSourceData
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let firstInk = PKDrawing(strokes: Array(initialSource.strokes.prefix(1)))
        let secondInk = PKDrawing(strokes: Array(initialSource.strokes.dropFirst().prefix(1)))
        let expandedSecondInk = PKDrawing(strokes: Array(source.strokes.dropFirst()))
        let first = uncertainPayload(text: "C", drawing: firstInk, measureID: measureID, index: 0, confidence: 4.5)
        let second = uncertainPayload(text: "Bb", drawing: secondInk, measureID: measureID, index: 1)
        var latest = uncertainPayload(text: "D7", drawing: expandedSecondInk, measureID: measureID, index: 1, confidence: 4.5)

        func activateAction(_ title: String) async throws {
            let action = try await waitForNode(in: mounted.window) {
                $0.isButton && $0.element.accessibilityLabel == title
            }
            try activate(action)
        }

        try XCTUnwrap(mounted.canvas.onChordInkDraftPreviewChanged)([first, second])
        try await activateAction("Review & Render")
        let fields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(fields.map(\.text), ["C", "Bb"])
        for (field, edit) in zip(fields, ["Cmaj7", "Bbmaj7"]) {
            field.text = edit
            field.sendActions(for: .editingChanged)
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        // A delayed same-source result cannot replace the resolution already
        // bound to that source. The sheet also retains the user's typed edits;
        // no source is changed behind the modal.
        var sameSourceLatest = uncertainPayload(text: "D7", drawing: secondInk,
            measureID: measureID, index: 1, confidence: 4.5)
        sameSourceLatest.timing.recognitionFinishedAt = .now
        try XCTUnwrap(mounted.canvas.onChordInkDraftPreviewChanged)([first, sameSourceLatest])
        try await Task.sleep(nanoseconds: 100_000_000)
        let activeFields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(activeFields.map(\.text), ["Cmaj7", "Bbmaj7"])
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.previewText), ["C", "Bb"],
            "An identical-source result reuses the existing source-bound resolution")
        XCTAssertEqual(mounted.store.charts.first?.pageHandwrittenChordData, initialSourceData)
        XCTAssertTrue(mounted.store.charts.allSatisfy { $0.measures.flatMap(\.chordEvents).isEmpty })

        try await activateAction("Back to Writing")
        try await waitForReviewDismissal(in: mounted)
        for _ in 0..<50 {
            mounted.window.layoutIfNeeded()
            if !mounted.canvas.isInteractionSuspended,
               mounted.canvas.chordPreviewState.draftChords.map(\.previewText) == ["C", "Bb"] { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(mounted.canvas.isInteractionSuspended)
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.strokeCount), [1, 1])
        XCTAssertEqual(mounted.store.charts.first?.pageHandwrittenChordData, initialSourceData)

        // Once review is dismissed, inject an external source update through
        // the owning chart binding. Recognition is frozen in this fixture, so
        // this exercises external chart arrival while writing, not Pencil input.
        let externalBinding = try XCTUnwrap(mounted.store.editorBinding(for: chart.id))
        var incomingChart = externalBinding.wrappedValue
        XCTAssertTrue(incomingChart.setPageHandwrittenChordDrawing(source.dataRepresentation(),
            coordinateSpace: incomingChart.pageHandwrittenChordCoordinateSpace))
        externalBinding.wrappedValue = incomingChart
        var expandedSourceReachedCanvas = false
        for _ in 0..<60 {
            mounted.window.layoutIfNeeded()
            if let saved = mounted.store.charts.first?.pageHandwrittenChordData,
               let drawing = try? PKDrawing(data: saved),
               let current = mounted.canvas.chordDraftRenderCoordinator?.currentSourceDrawing(),
               ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: drawing),
               ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: current) {
                sourceData = saved
                expandedSourceReachedCanvas = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if !expandedSourceReachedCanvas {
            let savedChart = mounted.store.charts.first(where: { $0.id == chart.id })
            let savedStrokeCount = savedChart?.pageHandwrittenChordData.flatMap { try? PKDrawing(data: $0).strokes.count }
            let current = mounted.canvas.chordDraftRenderCoordinator?.currentSourceDrawing()
            let diagnostic = XCTAttachment(string:
                "External source update while writing: expected=\(source.strokes.count) saved=\(String(describing: savedStrokeCount)) live=\(String(describing: current?.strokes.count)) suspended=\(mounted.canvas.isInteractionSuspended)\n" +
                "incomingCoordinateSpace=\(String(describing: incomingChart.pageHandwrittenChordCoordinateSpace)) savedCoordinateSpace=\(String(describing: savedChart?.pageHandwrittenChordCoordinateSpace))\n" +
                guideGeometryDiagnostics(in: mounted))
            diagnostic.name = "Delayed review external source update mismatch"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
        }
        XCTAssertTrue(expandedSourceReachedCanvas,
            "The external writing-state update must reach the owning store and live canvas before its injected census is published")
        latest.timing.recognitionFinishedAt = .now
        try XCTUnwrap(mounted.canvas.onChordInkDraftPreviewChanged)([first, latest])
        for _ in 0..<50 {
            mounted.window.layoutIfNeeded()
            if mounted.canvas.chordPreviewState.draftChords.map(\.strokeCount) == [1, 2] { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let refreshed = mounted.canvas.chordPreviewState.draftChords
        XCTAssertEqual(refreshed.map(\.previewText), ["C", "D7"])
        XCTAssertEqual(refreshed.map(\.strokeCount), [1, 2])
        XCTAssertFalse(mounted.canvas.chordPreviewState.requiresChordConfirmation,
            "The unchanged first target's retained edit must remain reviewable after the expanded target becomes trusted")
        XCTAssertEqual(mounted.store.charts.first?.pageHandwrittenChordData, sourceData)

        try await activateAction("Review & Render")
        let reopenedFields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(reopenedFields.map(\.text), ["Cmaj7", "D7"],
            "Reopening must keep the first row's edit and use the latest read for the changed second source")
        attach(mounted.window, name: "RHY-006 reopened review with retained edit and latest guess")
        try await activateAction("Render All")
        try await waitForReviewDismissal(in: mounted)

        let repository = FileChartRepository(url: file)
        var reopened: ChartLibrarySnapshot?
        for _ in 0..<60 {
            let candidate = try repository.loadSnapshot()
            if candidate?.charts.first?.measures.flatMap(\.chordEvents).count == 2 {
                reopened = candidate
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let snapshot = try XCTUnwrap(reopened)
        XCTAssertEqual(snapshot.selectedChartID, chart.id)
        let saved = try XCTUnwrap(snapshot.charts.first)
        XCTAssertEqual(saved.measures.map(\.id), chart.measures.map(\.id))
        XCTAssertNil(saved.pageHandwrittenChordData)
        let events = saved.measures.flatMap(\.chordEvents)
        XCTAssertEqual(events.map(\.rawInput), ["Cmaj7", "D7"])
        for (expected, event) in zip([firstInk, expandedSecondInk], events) {
            let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: archive))
        }
    }

    func testManualReviewRendersAfterBackupAcknowledgementWithoutLeavingReview() async throws {
        try await assertManualReviewRendersAfterBackupAcknowledgement(delayPreview: false)
    }

    func testManualRenderAllResumesAfterPreviewBecomesReadyWithoutAnotherTap() async throws {
        try await assertManualReviewRendersAfterBackupAcknowledgement(delayPreview: true)
    }

    private func assertManualReviewRendersAfterBackupAcknowledgement(delayPreview: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        var chart = Chart.draft(title: "Disposable same-ink review", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
        XCTAssertEqual(chart.systems.count, 1)
        let mounted = try await mount(manual: true, repository: repository, initialChart: chart,
            freezesRecognition: false)
        let canvas = mounted.canvas
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        let coordinator = try XCTUnwrap(canvas.chordDraftRenderCoordinator)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: canvas.bounds.size,
            includesChordInkContinuationLanes: true)
        XCTAssertGreaterThan(layout.systems.count, 1, "The fixture must generate wrapped rows from one source system")
        let system = try XCTUnwrap(layout.systems.first)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let first = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == chart.measures[0].id })
        let second = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == chart.measures[1].id })
        let y = lane.midY - sourceFrame.minY
        func stroke(_ offsets: [CGPoint], x: CGFloat, seed: UInt32) -> PKStroke {
            let path = PKStrokePath(controlPoints: offsets.enumerated().map { index, point in
                PKStrokePoint(location: CGPoint(x: x - sourceFrame.minX + point.x, y: y + point.y),
                    timeOffset: Double(index) * 0.05, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: seed)
        }
        let originalFirst = stroke([.init(x: 7, y: -8), .init(x: -7, y: -4), .init(x: -8, y: 5),
            .init(x: 7, y: 8)], x: first.staffFrame.midX, seed: 1)
        let originalSecond = stroke([.init(x: -5, y: -3), .init(x: 4, y: 4), .init(x: -5, y: 5)],
            x: second.staffFrame.midX, seed: 4)
        let replacedSecond = stroke([.init(x: -6, y: -9), .init(x: -6, y: 9), .init(x: 8, y: 3),
            .init(x: 8, y: -3), .init(x: -6, y: -9)], x: second.staffFrame.midX, seed: 7)
        let firstInk = PKDrawing(strokes: [originalFirst])
        let secondInk = PKDrawing(strokes: [replacedSecond])
        let latestSource = PKDrawing(strokes: [originalFirst, replacedSecond])

        func replaceDrawing(_ drawing: PKDrawing) async throws {
            canvas.canvasViewDidBeginUsingTool(live)
            live.drawing = drawing
            canvas.canvasViewDrawingDidChange(live)
            canvas.canvasViewDidEndUsingTool(live)
            for _ in 0..<80 {
                mounted.window.layoutIfNeeded()
                if coordinator.prepareManualPreviewForReview(),
                   let savedData = mounted.store.charts.first?.pageHandwrittenChordData,
                   let savedInk = try? PKDrawing(data: savedData),
                   ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: drawing, current: savedInk) { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTFail("The real Manual preview did not settle on the current saved ink")
            throw Failure.missingReview
        }
        func button(_ title: String) async throws -> NativeAccessibilityLookup.Node {
            try await waitForNode(in: mounted.window) { $0.isButton && $0.element.accessibilityLabel == title }
        }

        XCTAssertTrue(canvas.recognizesChordInk)
        try await replaceDrawing(PKDrawing(strokes: [originalFirst, originalSecond]))
        let firstRead = uncertainPayload(text: "C", drawing: firstInk, measureID: chart.measures[0].id, index: 0)
        var noRead = uncertainPayload(text: "", drawing: PKDrawing(strokes: [originalSecond]),
            measureID: chart.measures[1].id, index: 1)
        noRead.result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        try XCTUnwrap(canvas.onChordInkDraftPreviewChanged)([firstRead, noRead])
        try activate(await button("Review & Render"))
        let initialFields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(initialFields.map { $0.text ?? "" }, ["C", ""])
        initialFields[0].text = "Cmaj7"
        initialFields[0].sendActions(for: .editingChanged)
        try activate(await button("Back to Writing"))
        try await waitForReviewDismissal(in: mounted)

        try await replaceDrawing(latestSource)
        let nextRead = uncertainPayload(text: "D7", drawing: secondInk, measureID: chart.measures[1].id, index: 1)
        try XCTUnwrap(canvas.onChordInkDraftPreviewChanged)([firstRead, nextRead])
        try activate(await button("Review & Render"))
        let reopenedFields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(reopenedFields.map(\.text), ["Cmaj7", "D7"])

        XCTAssertTrue(coordinator.prepareManualPreviewForReview())
        let beforeBackup = mounted.store.snapshot
        let backedUpAt = Date(timeIntervalSinceReferenceDate: 10_000)
        mounted.store.markChartsBackedUpToCloud(chartIDs: [chart.id], ownerID: UUID(),
            backedUpAt: backedUpAt, from: beforeBackup)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if canvas.chart.cloudBackupStatus.lastBackedUpAt == backedUpAt { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(canvas.chart.cloudBackupStatus.lastBackedUpAt, backedUpAt)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: latestSource, current: live.drawing))
        let preparePreview = coordinator.manualPreviewPreparer
        var pendingChecks = 0
        if delayPreview {
            allowsFrozenManualPreflight = false
            coordinator.manualPreviewPreparer = {
                pendingChecks += 1
                return false
            }
        }
        try activate(await button("Render All"))
        if delayPreview {
            for _ in 0..<30 where pendingChecks == 0 {
                mounted.window.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertGreaterThan(pendingChecks, 0)
            let stillOpen = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
            XCTAssertEqual(stillOpen.map(\.text), ["Cmaj7", "D7"])
            let labels = try NativeAccessibilityLookup.nodes(in: mounted.window).compactMap {
                $0.element.accessibilityLabel
            }
            XCTAssertFalse(labels.contains("OK"), "Transient readiness must not open an alert")
            XCTAssertTrue(mounted.store.charts.first?.measures.flatMap(\.chordEvents).isEmpty == true)
            coordinator.manualPreviewPreparer = preparePreview
            allowsFrozenManualPreflight = true
            installFrozenManualReviewSourceIfNeeded()
            try XCTUnwrap(canvas.onManualChordPreviewReady)()
        }
        try await waitForReviewDismissal(in: mounted)

        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        XCTAssertEqual(snapshot.selectedChartID, chart.id)
        let saved = try XCTUnwrap(snapshot.charts.first)
        XCTAssertEqual(saved.measures.map(\.id), chart.measures.map(\.id))
        XCTAssertEqual(saved.cloudBackupStatus.lastBackedUpAt, backedUpAt)
        XCTAssertNil(saved.pageHandwrittenChordData)
        let events = saved.measures.flatMap(\.chordEvents)
        XCTAssertEqual(events.map(\.rawInput), ["Cmaj7", "D7"])
        for (expected, event) in zip([firstInk, secondInk], events) {
            let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: archive))
        }
    }

    func testSustainedRhythmBarlineWithConvertedMarkReportsBoundaryWithoutRestorationPrompt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        var chart = Chart.draft(title: "Sustained boundary with converted mark", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let measureID = try XCTUnwrap(measureIDs.first)
        XCTAssertTrue(chart.setMeasureRhythmMap([.whole], for: measureID))
        let mark = FreeInkArticulation(kind: .accent, measureID: measureID,
            sourceInkData: landscapeSourceDrawing().dataRepresentation(), attachment: .note(beat: 1, subdivision: 0))
        chart.freeInkArticulations = [mark]
        let originalRhythm = try XCTUnwrap(chart.measure(id: measureID)?.rhythmMap)
        let mounted = try await mount(manual: true, repository: repository, initialChart: chart,
            freezesRecognition: false)
        let canvas = mounted.canvas
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: canvas.bounds.size,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureID })
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let x = measure.staffFrame.midX - frame.minX
        let points = [CGPoint(x: x, y: lane.minY + lane.height * 0.08 - frame.minY),
                      CGPoint(x: x, y: lane.maxY - lane.height * 0.08 - frame.minY)]
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.05,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 300))
        let source = PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor), path: path,
            transform: .identity, mask: nil, randomSeed: 300)])
        canvas.canvasViewDidBeginUsingTool(live)
        live.drawing = source
        canvas.canvasViewDrawingDidChange(live)
        canvas.canvasViewDidEndUsingTool(live)

        let render = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.isEnabled && $0.element.accessibilityLabel == "Render Chords"
        }
        XCTAssertEqual(canvas.chordPreviewState.draftBarlines.count, 1)
        XCTAssertTrue(canvas.chordPreviewState.draftChords.isEmpty)
        try activate(render)
        let status = try await waitForNode(in: mounted.window) {
            $0.element.accessibilityLabel?.contains("rhythmic boundary") == true
        }
        let message = try XCTUnwrap(status.element.accessibilityLabel)
        XCTAssertTrue(message.contains("A note cannot sustain across the split"))
        XCTAssertFalse(message.contains("Restore Ink"), "Restoring this mark cannot make the sustained note divisible")
        XCTAssertLessThanOrEqual(status.frame(in: mounted.window).maxY,
            render.frame(in: mounted.window).minY, "Recovery remains inline above the writing controls")
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController)
        let labels = try NativeAccessibilityLookup.nodes(in: mounted.window).compactMap { $0.element.accessibilityLabel }
        XCTAssertFalse(labels.contains("OK"))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: live.drawing))

        var reopened: Chart?
        for _ in 0..<80 {
            if let saved = try repository.loadSnapshot()?.charts.first,
               let data = saved.pageHandwrittenChordData,
               let drawing = try? PKDrawing(data: data),
               ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: drawing) {
                reopened = saved
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let saved = try XCTUnwrap(reopened)
        XCTAssertEqual(saved.measures.map(\.id), measureIDs)
        XCTAssertEqual(saved.measure(id: measureID)?.rhythmMap, originalRhythm)
        XCTAssertTrue(saved.measures.flatMap(\.chordEvents).isEmpty)
        XCTAssertEqual(saved.freeInkArticulations, [mark])
    }

    func testManualRendersBarlineBetweenCommittedChordsAndNextChordWithoutDialog() async throws {
        try await assertCommittedBarlineAndIndependentChordRender(manual: true)
    }

    func testAutomaticRendersBarlineBetweenCommittedChordsAndNextChordWithoutDialog() async throws {
        try await assertCommittedBarlineAndIndependentChordRender(manual: false)
    }

    private func assertCommittedBarlineAndIndependentChordRender(manual: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        var chart = Chart.draft(title: "Committed barline and independent chord", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        let firstID = try XCTUnwrap(measureIDs.first)
        XCTAssertEqual(chart.measure(id: firstID)?.authoringState, .committed)
        let c = try XCTUnwrap(ChordRecognitionCompendium.match("C"))
        let g7 = try XCTUnwrap(ChordRecognitionCompendium.match("G7"))
        let firstEvent = try XCTUnwrap(chart.appendRecognizedChordEvent(
            c.symbol, rawInput: "C", to: firstID, atFraction: 0.05))
        let secondEvent = try XCTUnwrap(chart.appendRecognizedChordEvent(
            g7.symbol, rawInput: "G7", to: firstID, atFraction: 0.88))
        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(firstEvent, to: firstID, atFraction: nil,
            visualFraction: 0.16, preserveMusicalPlacement: true))
        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(secondEvent, to: firstID, atFraction: nil,
            visualFraction: 0.78, preserveMusicalPlacement: true))

        let mounted = try await mount(manual: manual, repository: repository, initialChart: chart,
            freezesRecognition: false)
        let canvas = mounted.canvas
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: canvas.bounds.size,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let first = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == firstID })
        let second = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureIDs[1] })
        let y = lane.midY - sourceFrame.minY
        func stroke(at pageX: CGFloat, offsets: [CGPoint], seed: UInt32) -> PKStroke {
            let path = PKStrokePath(controlPoints: offsets.enumerated().map { index, point in
                PKStrokePoint(location: CGPoint(x: pageX - sourceFrame.minX + point.x, y: y + point.y),
                    timeOffset: Double(index) * 0.05, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: seed)
        }
        let barline = stroke(at: first.staffFrame.midX, offsets: [
            CGPoint(x: -3, y: -lane.height * 0.42), CGPoint(x: 3, y: lane.height * 0.42)
        ], seed: 1)
        let chord = stroke(at: second.staffFrame.midX, offsets: [
            CGPoint(x: 7, y: -9), CGPoint(x: -5, y: -5), CGPoint(x: -8, y: 0),
            CGPoint(x: -5, y: 5), CGPoint(x: 7, y: 9)
        ], seed: 2)
        let source = PKDrawing(strokes: [barline, chord])
        canvas.canvasViewDidBeginUsingTool(live)
        live.drawing = source
        canvas.canvasViewDrawingDidChange(live)
        canvas.canvasViewDidEndUsingTool(live)

        if manual {
            let render = try await waitForNode(in: mounted.window) {
                $0.isButton && $0.isEnabled && $0.element.accessibilityLabel == "Render Chords"
            }
            try activate(render)
        }

        var saved: Chart?
        for _ in 0..<160 {
            mounted.window.layoutIfNeeded()
            let candidate = try repository.loadSnapshot()?.charts.first
            if candidate?.measure(id: measureIDs[1])?.chordEvents.count == 1,
               candidate?.measures.count == chart.measures.count + 1,
               candidate?.pageHandwrittenChordData == nil {
                saved = candidate
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(mounted.window.rootViewController?.presentedViewController,
            "Rendering a recognized barline must not open a dialog")
        if saved == nil {
            let state = canvas.chordPreviewState
            let labels = try NativeAccessibilityLookup.nodes(in: mounted.window).compactMap {
                $0.element.accessibilityLabel
            }
            let currentChart = try XCTUnwrap(mounted.store.charts.first)
            let staged = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: currentChart,
                state: state, currentDrawing: live.drawing, coordinateSpace: .init(size: sourceFrame.size),
                now: Date(timeIntervalSinceReferenceDate: 5), lastInputAt: Date(timeIntervalSinceReferenceDate: 0),
                isUsingTool: false, sourcePageLayout: layout, sourceChordFrame: sourceFrame)
            XCTFail("The committed barline and independent chord did not save. Preview: \(state.draftChords.map { ($0.previewText, $0.measureID, $0.targetLifecycle?.stage) }); barlines: \(state.draftBarlines); staged feedback: \(staged.feedback); staged outcome: \(staged.outcome != nil); labels: \(labels)")
        }
        let reopened = try XCTUnwrap(saved)
        XCTAssertEqual(reopened.measures.count, chart.measures.count + 1)
        XCTAssertEqual(reopened.measures.filter { measureIDs.contains($0.id) }.map(\.id), measureIDs)
        XCTAssertEqual(reopened.measures[0].chordEvents.map(\.id), [firstEvent])
        XCTAssertEqual(reopened.measures[1].chordEvents.map(\.id), [secondEvent])
        for id in [firstEvent, secondEvent] {
            let before = try XCTUnwrap(chart.chordEvent(id: id))
            let after = try XCTUnwrap(reopened.chordEvent(id: id))
            XCTAssertEqual(after.rawInput, before.rawInput)
            XCTAssertEqual(after.symbol, before.symbol)
            XCTAssertEqual(after.sourceInkData, before.sourceInkData)
            XCTAssertEqual(after.duration, before.duration)
            XCTAssertEqual(after.tieOut, before.tieOut)
        }
        let event = try XCTUnwrap(reopened.measure(id: measureIDs[1])?.chordEvents.first)
        XCTAssertEqual(event.rawInput, "C")
        let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [chord]), current: archive))
        XCTAssertNil(reopened.pageHandwrittenChordData)
        XCTAssertNil(reopened.pageHandwrittenChordCoordinateSpace)
        XCTAssertTrue(live.drawing.strokes.isEmpty)
        let labels = try NativeAccessibilityLookup.nodes(in: mounted.window).compactMap {
            $0.element.accessibilityLabel
        }
        XCTAssertFalse(labels.contains("OK"))
    }

    func testBlockedEndingBackToWritingFocusesOnlyTheDividerAndPreservesInk() async throws {
        try await assertBlockedEndingRecovery(manual: true)
    }

    func testAutomaticBarlineFeedbackFocusesInkWithoutOpeningReview() async throws {
        try await assertBlockedEndingRecovery(manual: false)
    }

    func testManualEndingRecoverySavesOriginalInkAfterBackupAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library-state.json")
        let repository = FileChartRepository(url: file)
        var chart = Chart.draft(title: "Disposable ending recovery", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 3)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.setMeasureRhythmMap([.whole], for: measureIDs[0]),
            "This fixture cuts a sustained note, so it remains a real unresolved boundary")
        let mounted = try await mount(manual: true, repository: repository, initialChart: chart,
            freezesRecognition: false)
        let canvas = mounted.canvas
        let live = try XCTUnwrap(canvas.subviews.compactMap { $0 as? LeadSheetScopedInkCanvasView }.last)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: canvas.bounds.size,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let first = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureIDs[0] })
        let second = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measureIDs[1] })
        let left = second.staffFrame.minX + 2 - sourceFrame.minX
        let right = second.staffFrame.maxX - 2 - sourceFrame.minX
        let top = lane.minY + lane.height * 0.12 - sourceFrame.minY
        let hook = max(6, lane.height * 0.20)
        let barX = first.staffFrame.midX - sourceFrame.minX
        let barTop = lane.minY + lane.height * 0.08 - sourceFrame.minY
        let barBottom = lane.maxY - lane.height * 0.08 - sourceFrame.minY
        func stroke(_ points: [CGPoint], seed: UInt32) -> PKStroke {
            let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.03,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: seed)
        }
        let divider = stroke([CGPoint(x: barX, y: barTop), CGPoint(x: barX, y: barBottom)], seed: 1)
        let endingInk = PKDrawing(strokes: [
            stroke([CGPoint(x: left, y: top + hook), CGPoint(x: left, y: top)], seed: 2),
            stroke([CGPoint(x: left, y: top), CGPoint(x: right, y: top)], seed: 3)
        ])
        let source = PKDrawing(strokes: [divider] + endingInk.strokes)
        canvas.canvasViewDidBeginUsingTool(live)
        live.drawing = source
        canvas.canvasViewDrawingDidChange(live)
        canvas.canvasViewDidEndUsingTool(live)

        func button(_ label: String) async throws -> NativeAccessibilityLookup.Node {
            try await waitForNode(in: mounted.window) { $0.isButton && $0.element.accessibilityLabel == label }
        }
        func waitForPreview(barlineCount: Int) async throws {
            for _ in 0..<80 {
                mounted.window.layoutIfNeeded()
                if canvas.chordPreviewState.draftBarlines.count == barlineCount,
                   canvas.chordPreviewState.draftEndings.count == 1,
                   canvas.chordDraftRenderCoordinator?.prepareManualPreviewForReview() == true { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTFail("The current barline and ending preview did not settle")
            throw Failure.missingReview
        }

        try await waitForPreview(barlineCount: 1)
        let blockerID = try XCTUnwrap(canvas.chordPreviewState.draftBarlines.first?.id)
        try activate(await button("Review & Render"))
        try activate(await button("Barline near measure 1"))
        try await waitForReviewDismissal(in: mounted)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if canvas.focusedDraftEndingBlocker?.id == blockerID { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(canvas.focusedDraftEndingBlocker?.id, blockerID)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: live.drawing))

        try activate(await button("Erase"))
        for _ in 0..<30 {
            mounted.window.layoutIfNeeded()
            if live.manualEraseEnabled { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(live.manualEraseEnabled)
        let erase = try XCTUnwrap(live.manualEraseHandler)
        let midpointY = (barTop + barBottom) / 2
        erase(CGPoint(x: barX - 2, y: midpointY), CGPoint(x: barX + 2, y: midpointY))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: endingInk, current: live.drawing))
        try activate(await button("Write"))
        try await waitForPreview(barlineCount: 0)
        try activate(await button("Review & Render"))
        _ = try await waitForNode(in: mounted.window) {
            $0.element.accessibilityLabel == "Measure 2"
        }
        let label = try await scrollToEndingLabelInPresentedReview(in: mounted)
        label.text = "1."
        label.sendActions(for: .editingChanged)
        let beforeBackup = try XCTUnwrap(mounted.store.charts.first)
        let backedUpAt = Date(timeIntervalSinceReferenceDate: 10_000)
        mounted.store.markChartsBackedUpToCloud(chartIDs: [chart.id], ownerID: UUID(),
            backedUpAt: backedUpAt, from: mounted.store.snapshot)
        XCTAssertEqual(mounted.store.charts.first?.cloudBackupStatus.lastBackedUpAt, backedUpAt)
        XCTAssertEqual(mounted.store.charts.first?.pageHandwrittenChordData, beforeBackup.pageHandwrittenChordData)
        let apply = try await waitForNode(in: mounted.window) {
            $0.element is PencilOnlyUIButton && $0.element.accessibilityLabel == "Use Ending" && $0.isEnabled
        }
        try activate(apply)

        var reopened: Chart?
        for _ in 0..<60 {
            let candidate = try FileChartRepository(url: file).loadSnapshot()?.charts.first { $0.id == chart.id }
            if candidate?.roadmapObjects.contains(where: { $0.type.isEnding }) == true {
                reopened = candidate
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if reopened == nil {
            attach(mounted.window, name: "RHY-007 ending did not save")
            let labels = try NativeAccessibilityLookup.nodes(in: mounted.window).compactMap { $0.element.accessibilityLabel }
            XCTFail("Ending did not save. Visible controls: \(labels). Preview: \(canvas.chordPreviewState.draftEndings.map { ($0.label, $0.isReviewed) })")
        }
        let saved = try XCTUnwrap(reopened, "Use Ending must render and persist the recovered bracket")
        let ending = try XCTUnwrap(saved.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(saved.measures.map(\.id), measureIDs)
        XCTAssertEqual(ending.startMeasureID, measureIDs[1])
        XCTAssertEqual(ending.endMeasureID, measureIDs[1])
        XCTAssertEqual(ending.resolvedEndingDisplayText, "1.")
        XCTAssertEqual(saved.cloudBackupStatus.lastBackedUpAt, backedUpAt)
        XCTAssertNil(saved.pageHandwrittenChordData)
        let archive = try PKDrawing(data: XCTUnwrap(ending.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: endingInk, current: archive))
    }

    private func assertBlockedEndingRecovery(manual: Bool) async throws {
        let pageSize = CGSize(width: 820, height: 1_180)
        var chart = Chart.draft(title: "Disposable ending review", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 2)
        XCTAssertTrue(chart.setMeasureRhythmMap([.whole], for: chart.measures[0].id),
            "A sustained note spanning the proposed boundary is the unresolved control")
        let measure = try XCTUnwrap(chart.measures.first)
        XCTAssertEqual(measure.authoringState, .committed)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let staff = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == measure.id })
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        func laneLocation(_ x: CGFloat) -> ChordInkDraftLaneLocation {
            .init(systemIndex: system.index, fraction: Double((x - lane.minX) / lane.width))
        }
        func mark(_ points: [CGPoint], seed: UInt32) -> PKStroke {
            let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: CGPoint(x: point.x - chordFrame.minX, y: point.y - chordFrame.minY),
                    timeOffset: Double(index) * 0.03, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: seed)
        }
        let left = staff.staffFrame.minX + 2
        let right = staff.staffFrame.maxX - 2
        let top = lane.minY + lane.height * 0.15
        let bottom = top + lane.height * 0.22
        let dividerX = staff.staffFrame.midX
        let barTop = lane.minY + lane.height * 0.35
        let barBottom = lane.minY + lane.height * 0.9
        let endingInk = mark([CGPoint(x: left, y: bottom), CGPoint(x: left, y: top),
            CGPoint(x: right, y: top), CGPoint(x: right, y: bottom)], seed: 1)
        let dividerInk = mark([CGPoint(x: dividerX, y: barTop), CGPoint(x: dividerX, y: barBottom)], seed: 2)
        let drawing = PKDrawing(strokes: [endingInk, dividerInk])
        let geometry = PencilKitInkAdapter.inkStrokes(from: drawing)
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: chordFrame.size))
        let ending = DraftEnding(
            start: .init(measureID: measure.id, measureIndex: 0, fraction: 0, laneLocation: laneLocation(left)),
            end: .init(measureID: measure.id, measureIndex: 0, fraction: 0.9999, laneLocation: laneLocation(right)),
            layoutPageSize: pageSize, sourceStrokeIndices: [0], sourceStrokeGeometry: [geometry[0]], endStyle: .closed)
        let blocker = DraftBarline(measureID: measure.id, measureIndex: 0, fraction: 0.5,
            laneLocation: laneLocation(dividerX), layoutPageSize: pageSize, sourceStrokeIndex: 1,
            metrics: .init(height: Double(barBottom - barTop), width: 1, angleDegreesFromVertical: 0,
                straightness: 1, laneCoverage: 0.55), sourceStrokeGeometry: [geometry[1]])
        let mounted = try await mount(manual: manual, initialChart: chart)
        let live = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
        let sourceBefore = live.drawing
        try XCTUnwrap(mounted.canvas.onChordInkDraftBarlinesChanged)([blocker])
        try XCTUnwrap(mounted.canvas.onChordInkDraftEndingsChanged)([ending])
        if !manual {
            mounted.canvas.onChordInkAutomaticActivityChanged?(.init(chartID: chart.id,
                sourceRevision: mounted.canvas.automaticChordInputRevision, hasSourceInk: true,
                phase: .settled, pendingTargetCount: 0, inputAt: nil,
                feedback: .init(globalReason: .barlinePlacementUnavailable)))
        }
        let reviewLabel = manual ? "Review & Render" : ChordInkAutomaticRenderReason.barlinePlacementUnavailable.userMessage
        let render = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == reviewLabel
        }
        if manual {
            // This injected completed census intentionally contains an
            // unrenderable boundary. Readiness permits reviewing it; the
            // renderer's stricter source-consumption policy still rejects it.
            allowsFrozenManualPreflight = false
            let coordinator = try XCTUnwrap(mounted.canvas.chordDraftRenderCoordinator)
            coordinator.manualPreviewPreparer = { [weak canvas = mounted.canvas] in
                guard let canvas, let current = canvas.currentChordInkSourceDrawing(),
                      canvas.chordPreviewState.draftBarlines.map(\.id) == [blocker.id],
                      canvas.chordPreviewState.draftEndings.map(\.id) == [ending.id] else { return false }
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: sourceBefore, current: current)
            }
        }
        defer { allowsFrozenManualPreflight = true }
        try activate(render)

        if manual {
            _ = try await waitForNode(in: mounted.window) {
                $0.isButton && $0.element.accessibilityLabel == "Barline near measure 1"
            }
            XCTAssertFalse(try NativeAccessibilityLookup.nodes(in: mounted.window).contains {
                let label = $0.element.accessibilityLabel ?? ""
                return label.contains("Start measure") || label.contains("End measure")
            })
            let apply = try await waitForNode(in: mounted.window) {
                $0.element is PencilOnlyUIButton && $0.element.accessibilityLabel == "Use Ending"
            }
            XCTAssertFalse(apply.isEnabled)
            attach(mounted.window, name: "RHY-007 deliberate ending review names its blocking divider")
            let back = try await waitForNode(in: mounted.window) {
                $0.isButton && $0.element.accessibilityLabel == "Back to Writing"
            }
            try activate(back)
            try await waitForReviewDismissal(in: mounted)
        } else {
            XCTAssertNil(mounted.window.rootViewController?.presentedViewController,
                "Automatic barline recovery must leave the canvas available")
        }
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if mounted.canvas.focusedDraftEndingBlocker?.id == blocker.id { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(mounted.canvas.focusedDraftEndingBlocker?.id, blocker.id)
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftEndings, [ending])
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftBarlines, [blocker])
        XCTAssertEqual(mounted.model.chart, chart)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: sourceBefore, current: live.drawing))
        attach(mounted.window, name: "RHY-007 Back to Writing highlights the divider without editing ink")
    }

    func testLandscapeSoftwareKeyboardLeavesBothReviewEntriesReachableAndCancelPreservesSource() async throws {
        try await assertLandscapeKeyboardCancellation(layoutStyle: .rhythmSectionSheet)
    }

    func testSimpleLandscapeSoftwareKeyboardLeavesBothReviewEntriesReachableAndCancelPreservesSource() async throws {
        try await assertLandscapeKeyboardCancellation(layoutStyle: .simpleChordSheet)
    }

    private func assertLandscapeKeyboardCancellation(layoutStyle: ChartLayoutStyle) async throws {
        let mounted = try await mountLandscapeKeyboardReview(layoutStyle: layoutStyle)
        let keyboard = FeedbackSoftwareKeyboardProbe(window: mounted.window)
        XCTAssertTrue(mounted.window.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape == true,
            "The software keyboard must be exercised in a real landscape scene")
        let sourceBefore = try XCTUnwrap(mounted.model.chart.pageHandwrittenChordData)
        let fields = try await openLandscapeReview(in: mounted)
        let ids = mounted.canvas.chordPreviewState.draftChords.map(\.id)
        let keyboardFrame = try await waitForSoftwareKeyboard(keyboard, in: mounted)
        try await assertSoftwareKeyboardViewport(for: fields[1], keyboard: keyboard, in: mounted)
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - second review entry visible")

        let scroll = try XCTUnwrap(ancestorScrollView(of: fields[0]))
        scroll.scrollRectToVisible(fields[0].convert(fields[0].bounds, to: scroll).insetBy(dx: 0, dy: -8), animated: false)
        fields[0].requestKeyboard()
        try await assertSoftwareKeyboardViewport(for: fields[0], keyboard: keyboard, in: mounted)
        fields[0].text = "C7"
        fields[0].sendActions(for: .editingChanged)
        let accessory = try XCTUnwrap(fields[0].inputAccessoryView as? UIToolbar)
        let next = try XCTUnwrap(accessory.items?.first { $0.accessibilityLabel == "Next field" })
        let action = try XCTUnwrap(next.action)
        XCTAssertTrue(UIApplication.shared.sendAction(action, to: next.target, from: next, for: nil))
        try await assertSoftwareKeyboardViewport(for: fields[1], keyboard: keyboard, in: mounted)
        XCTAssertEqual(fields.map(\.text), ["C7", "Bb"])
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.id), ids)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenChordData, sourceBefore)
        XCTAssertGreaterThanOrEqual(keyboardFrame.height, 180)
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - Next reaches second review entry")

        let back = try await scrollToReviewAction("Back to Writing", scroll: scroll, keyboard: keyboard, in: mounted)
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - scroll reaches review actions")
        try activate(back)
        try await waitForReviewDismissal(in: mounted)
        XCTAssertEqual(mounted.model.chart.pageHandwrittenChordData, sourceBefore)
        XCTAssertTrue(mounted.model.chart.measures.allSatisfy(\.chordEvents.isEmpty))
        let live = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: try PKDrawing(data: sourceBefore), current: live.drawing))
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.id), ids)
    }

    func testLandscapeSoftwareKeyboardReviewAcceptsBothEntriesWithExactSourceOwnership() async throws {
        try await assertLandscapeKeyboardRender(layoutStyle: .rhythmSectionSheet)
    }

    func testSimpleLandscapeSoftwareKeyboardReviewAcceptsBothEntriesWithExactSourceOwnership() async throws {
        try await assertLandscapeKeyboardRender(layoutStyle: .simpleChordSheet)
    }

    private func assertLandscapeKeyboardRender(layoutStyle: ChartLayoutStyle) async throws {
        let mounted = try await mountLandscapeKeyboardReview(layoutStyle: layoutStyle)
        let keyboard = FeedbackSoftwareKeyboardProbe(window: mounted.window)
        XCTAssertTrue(mounted.window.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape == true)
        let source = try PKDrawing(data: XCTUnwrap(mounted.model.chart.pageHandwrittenChordData))
        let fields = try await openLandscapeReview(in: mounted)
        let ids = mounted.canvas.chordPreviewState.draftChords.map(\.id)
        _ = try await waitForSoftwareKeyboard(keyboard, in: mounted)
        try await assertSoftwareKeyboardViewport(for: fields[1], keyboard: keyboard, in: mounted)
        fields[1].text = "Bb"
        fields[1].sendActions(for: .editingChanged)
        XCTAssertEqual(fields.map(\.text), ["C", "Bb"])
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.map(\.id), ids)
        let scroll = try XCTUnwrap(ancestorScrollView(of: fields[1]))
        let render = try await scrollToReviewAction("Render All", scroll: scroll, keyboard: keyboard, in: mounted)
        XCTAssertTrue(render.isEnabled)
        XCTAssertTrue(mounted.canvas.isInteractionSuspended)
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - visible source-bound Render All")
        try activate(render)
        try await waitForReviewDismissal(in: mounted)
        let events = mounted.model.chart.measures.flatMap(\.chordEvents)
        XCTAssertEqual(events.map(\.rawInput), ["C", "Bb"])
        XCTAssertEqual(events.count, source.strokes.count)
        for (index, event) in events.enumerated() {
            let committed = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [source.strokes[index]]), current: committed))
            XCTAssertNil(event.manualVisualLaneFraction, "The settings-based manual workflow keeps its existing visual placement")
        }
        XCTAssertNil(mounted.model.chart.pageHandwrittenChordData)
        let live = try XCTUnwrap(mounted.canvas.subviews.compactMap { $0 as? PKCanvasView }.last)
        XCTAssertTrue(live.drawing.strokes.isEmpty)
    }

    private func mountLandscapeKeyboardReview(layoutStyle: ChartLayoutStyle) async throws -> Mounted {
        var chart = Chart.draft(title: "Disposable landscape review", layoutStyle: layoutStyle)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        _ = chart.setPageHandwrittenChordDrawing(landscapeSourceDrawing().dataRepresentation())
        return try await mount(manual: true, viewport: CGSize(width: 1_180, height: 820), initialChart: chart)
    }

    private func openLandscapeReview(in mounted: Mounted) async throws -> [IChartTypedUITextField] {
        try await injectUncertainPair(into: mounted)
        let status = try await waitForNode(in: mounted.window) {
            $0.isButton && $0.element.accessibilityLabel == "Review & Render"
        }
        XCTAssertTrue(mounted.window.bounds.insetBy(dx: -1, dy: -1).contains(status.frame(in: mounted.window)))
        try activate(status)
        let fields = try await waitForReviewFields(in: mounted.window, count: 2, requiresFocus: false)
        XCTAssertEqual(fields.map(\.text), ["C", "Bb"])
        try await establishReviewKeyboardWindow(for: fields[1], in: mounted)
        fields[1].requestKeyboard()
        _ = try await waitForReviewFields(in: mounted.window, count: 2)
        XCTAssertTrue(fields[1].isFirstResponder)
        try await establishReviewKeyboardWindow(for: fields[1], in: mounted)
        fields[1].requestKeyboard()
        return fields
    }

    private func establishReviewKeyboardWindow(for field: IChartTypedUITextField,
        in mounted: Mounted) async throws {
        let editingWindow = try XCTUnwrap(field.window, "The current review field must be attached before keyboard focus")
        // A mounted field can exist before its sheet's appearance transaction
        // completes. Observe bounded presentation readiness; a broken
        // transition must fail rather than hang or retry the keyboard request.
        // The sheet may own a different window from the editor, so establish
        // ownership on the actual field window.
        var presentationReady = false
        var presentationDiagnostics = ""
        for _ in 0..<60 {
            editingWindow.layoutIfNeeded()
            let controller = editingWindow.rootViewController?.presentedViewController
                ?? editingWindow.rootViewController
            let transitioning = controller?.transitionCoordinator != nil
            let appearing = controller?.isBeingPresented == true
            let dismissing = controller?.isBeingDismissed == true
            let attached = editingWindow.rootViewController?.viewIfLoaded?.window === editingWindow
            presentationDiagnostics = "\(keyboardWindowDiagnostics(field: field, mountedWindow: mounted.window)); appearing=\(appearing), dismissing=\(dismissing), transitioning=\(transitioning), rootAttached=\(attached)"
            if field.window === editingWindow, !editingWindow.isHidden,
               editingWindow.windowScene?.activationState == .foregroundActive,
               attached, !appearing, !dismissing, !transitioning {
                presentationReady = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard presentationReady else {
            XCTFail("The review's actual window must finish presentation before keyboard focus. \(presentationDiagnostics)")
            throw Failure.missingReviewWindow
        }
        let before = keyboardWindowDiagnostics(field: field, mountedWindow: mounted.window)
        guard field.window === editingWindow, !editingWindow.isHidden,
              editingWindow.windowScene?.activationState == .foregroundActive,
              editingWindow.rootViewController?.viewIfLoaded?.window === editingWindow else {
            XCTFail("The review's actual window must be visible and active before keyboard focus. \(before)")
            throw Failure.missingReviewWindow
        }
        editingWindow.makeKey()
        let after = keyboardWindowDiagnostics(field: field, mountedWindow: mounted.window)
        let attachment = XCTAttachment(string: "Before key handoff:\n\(before)\nAfter key handoff:\n\(after)")
        attachment.name = "Landscape keyboard - actual review field window ownership"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard field.window === editingWindow, editingWindow.isKeyWindow else {
            XCTFail("The review field's actual window must own key status before keyboard focus. \(after)")
            throw Failure.missingReviewWindow
        }
    }

    private func keyboardWindowDiagnostics(field: IChartTypedUITextField, mountedWindow: UIWindow) -> String {
        func describe(_ window: UIWindow?) -> String {
            guard let window else { return "nil" }
            return "\(type(of: window))@\(ObjectIdentifier(window)): key=\(window.isKeyWindow), hidden=\(window.isHidden), bounds=\(window.bounds), sceneState=\(String(describing: window.windowScene?.activationState)), root=\(String(describing: window.rootViewController.map { type(of: $0) }))"
        }
        let keyWindows = field.window?.windowScene?.windows.filter(\.isKeyWindow).map { describe($0) } ?? []
        return "mountedWindow=\(describe(mountedWindow)); fieldWindow=\(describe(field.window)); sameWindow=\(field.window === mountedWindow); focused=\(field.isFirstResponder); sceneKeys=\(keyWindows)"
    }

    private func waitForSoftwareKeyboard(_ probe: FeedbackSoftwareKeyboardProbe,
        in mounted: Mounted) async throws -> CGRect {
        for _ in 0..<80 {
            mounted.window.layoutIfNeeded()
            if let frame = probe.frame(in: mounted.window), frame.height >= 180,
               frame.width >= mounted.window.bounds.width * 0.6 { return frame }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - missing software keyboard precondition")
        XCTFail("A real onscreen software keyboard of at least 180 points is required; hardware-keyboard accessory bars are insufficient. Last frame: \(String(describing: probe.frame(in: mounted.window))). Notifications: \(probe.diagnostics)")
        throw Failure.missingSoftwareKeyboard
    }

    private func assertSoftwareKeyboardViewport(for field: IChartTypedUITextField,
        keyboard: FeedbackSoftwareKeyboardProbe, in mounted: Mounted) async throws {
        var stableSamples = 0
        var previousGeometry: ReviewViewportGeometry?
        var diagnostics = ""
        var samples: [String] = []
        for sample in 0..<60 {
            mounted.window.layoutIfNeeded()
            let fieldFrame = field.convert(field.bounds, to: mounted.window)
            let scroll = ancestorScrollView(of: field)
            let scrollFrame = scroll.map { $0.convert($0.bounds, to: mounted.window) } ?? .null
            let keyboardFrame = keyboard.frame(in: mounted.window) ?? .null
            let aboveKeyboard = CGRect(x: mounted.window.bounds.minX, y: mounted.window.bounds.minY,
                width: mounted.window.bounds.width, height: max(0, keyboardFrame.minY - mounted.window.bounds.minY))
            let usable = scrollFrame.intersection(aboveKeyboard)
            let geometry = ReviewViewportGeometry(
                field: fieldFrame, presentedField: presentationFrame(of: field, in: mounted.window),
                scroll: scrollFrame, scrollBounds: scroll?.bounds ?? .null,
                presentedScrollBounds: scroll?.layer.presentation()?.bounds ?? .null,
                contentSize: scroll?.contentSize ?? .zero, inset: scroll?.adjustedContentInset ?? .zero,
                keyboard: keyboardFrame)
            let passes = field.isFirstResponder && keyboardFrame.height >= 180
                && !usable.isNull && usable.height >= 120
                && usable.insetBy(dx: -1, dy: -1).contains(fieldFrame)
                && fieldFrame.maxY <= keyboardFrame.minY - 2
            // A row can be fully visible while SwiftUI is still moving its
            // focus scroll. Observe both rendering and layout over successive
            // frames before the fixture initiates its separate action scroll.
            // Visibility alone previously accepted the middle of that motion.
            let settled = geometry == previousGeometry && geometry.modelAndPresentationAgree
            stableSamples = passes && settled ? stableSamples + 1 : 0
            previousGeometry = geometry
            diagnostics = "field=\(fieldFrame), presentedField=\(geometry.presentedField), scroll=\(scrollFrame), usable=\(usable), keyboard=\(keyboardFrame), focused=\(field.isFirstResponder), settled=\(settled), geometry=\(scroll.map(scrollAnimationDiagnostics) ?? "none")"
            samples.append("sample \(sample), t=\(ProcessInfo.processInfo.systemUptime), \(diagnostics)")
            if stableSamples >= 3 {
                let attachment = XCTAttachment(string: samples.joined(separator: "\n")
                    + "\nKeyboard notifications:\n" + keyboard.diagnostics)
                attachment.name = "Landscape keyboard - focused entry scroll geometry - " + (field.text ?? "nil")
                attachment.lifetime = .keepAlways
                add(attachment)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - clipped entry or collapsed viewport")
        XCTFail("Focused entry must settle fully above the real software keyboard with at least 120 points of usable scrolling: \(diagnostics). Notifications: \(keyboard.diagnostics)")
        throw Failure.missingReview
    }

    private func scrollToReviewAction(_ label: String, scroll: UIScrollView,
        keyboard: FeedbackSoftwareKeyboardProbe, in mounted: Mounted) async throws -> NativeAccessibilityLookup.Node {
        var diagnostics: [String] = []
        func record(_ stage: String, actionFrame: CGRect? = nil) {
            let fields = descendants(mounted.window).compactMap { $0 as? IChartTypedUITextField }
                .enumerated().map { index, field in
                    "field[\(index)]:focused=\(field.isFirstResponder),frame=\(field.convert(field.bounds, to: mounted.window))"
                }.joined(separator: "; ")
            diagnostics.append("\(stage): t=\(ProcessInfo.processInfo.systemUptime), offset=\(scroll.contentOffset), content=\(scroll.contentSize), bounds=\(scroll.bounds), scrollFrame=\(scroll.convert(scroll.bounds, to: mounted.window)), inset=\(scroll.adjustedContentInset), legalMax=\(max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), keyboard=\(String(describing: keyboard.frame(in: mounted.window))), action=\(String(describing: actionFrame)), tracking=\(scroll.isTracking), dragging=\(scroll.isDragging), decelerating=\(scroll.isDecelerating), diagnosticsOn=\(IChartTelemetry.isRecordingEnabled), animation=\(scrollAnimationDiagnostics(scroll)), \(fields)")
        }
        func attachTrace(_ result: String) {
            let attachment = XCTAttachment(string: "Result=\(result), action=\(label)\n" + diagnostics.joined(separator: "\n")
                + "\nKeyboard notifications:\n" + keyboard.diagnostics)
            attachment.name = "Landscape keyboard - action reachability geometry - " + label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        record("before scroll")
        var didScrollToAction = false
        var stableVisibleSamples = 0
        for sample in 0..<40 {
            mounted.window.layoutIfNeeded()
            if let node = try NativeAccessibilityLookup.nodes(in: mounted.window).first(where: {
                $0.isButton && $0.element.accessibilityLabel == label
            }), let keyboardFrame = keyboard.frame(in: mounted.window), keyboardFrame.height >= 180 {
                let frame = node.frame(in: mounted.window)
                let scrollFrame = scroll.convert(scroll.bounds, to: mounted.window)
                record("sample \(sample)", actionFrame: frame)
                if !didScrollToAction {
                    // UIKit can retain extra keyboard avoidance inset while
                    // its sheet settles. The legal bottom offset may move an
                    // action above the viewport. Scroll the actual action the
                    // minimum legal distance into the usable viewport instead.
                    let usable = scrollFrame.intersection(mounted.window.bounds)
                        .intersection(CGRect(x: mounted.window.bounds.minX, y: mounted.window.bounds.minY,
                            width: mounted.window.bounds.width, height: keyboardFrame.minY))
                        .insetBy(dx: 0, dy: 8)
                    if !usable.isNull, usable.height >= frame.height {
                        let delta = frame.maxY > usable.maxY ? frame.maxY - usable.maxY
                            : (frame.minY < usable.minY ? frame.minY - usable.minY : 0)
                        let minimum = -scroll.adjustedContentInset.top
                        let maximum = max(minimum,
                            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        let target = min(maximum, max(minimum, scroll.contentOffset.y + delta))
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
                        didScrollToAction = true
                        record("minimal legal action scroll")
                    }
                }
                let visible = didScrollToAction && scrollFrame.insetBy(dx: -1, dy: -1).contains(frame)
                    && frame.maxY <= keyboardFrame.minY - 2
                stableVisibleSamples = visible ? stableVisibleSamples + 1 : 0
                if stableVisibleSamples >= 2 {
                    attachTrace("reachable")
                    return node
                }
            } else { record("sample \(sample) - missing action or keyboard") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attachTrace("not reachable")
        attachSoftwareKeyboardScreen(mounted.window, name: "Landscape keyboard - review action not reachable")
        XCTFail("Scrolling must make \(label) visible and tappable above the software keyboard")
        throw Failure.missingReview
    }

    private func scrollAnimationDiagnostics(_ scroll: UIScrollView) -> String {
        let layers = [scroll.layer] + (scroll.layer.sublayers ?? [])
        let animations = layers.flatMap { layer in
            (layer.animationKeys() ?? []).map { "\(type(of: layer)).\($0)" }
        }
        return "model=\(scroll.bounds), presentation=\(String(describing: scroll.layer.presentation()?.bounds)), animations=\(animations)"
    }

    private func presentationFrame(of view: UIView, in window: UIWindow) -> CGRect {
        guard let layer = view.layer.presentation(), let windowLayer = window.layer.presentation() else { return .null }
        return layer.convert(layer.bounds, to: windowLayer)
    }

    private struct ReviewViewportGeometry: Equatable {
        let field: CGRect
        let presentedField: CGRect
        let scroll: CGRect
        let scrollBounds: CGRect
        let presentedScrollBounds: CGRect
        let contentSize: CGSize
        let inset: UIEdgeInsets
        let keyboard: CGRect

        var modelAndPresentationAgree: Bool {
            nearlyEqual(field, presentedField) && nearlyEqual(scrollBounds, presentedScrollBounds)
        }

        private func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            !lhs.isNull && !rhs.isNull && abs(lhs.minX - rhs.minX) < 0.5
                && abs(lhs.minY - rhs.minY) < 0.5 && abs(lhs.width - rhs.width) < 0.5
                && abs(lhs.height - rhs.height) < 0.5
        }
    }

    private func waitForReviewDismissal(in mounted: Mounted) async throws {
        for _ in 0..<60 {
            mounted.window.layoutIfNeeded()
            if mounted.window.rootViewController?.presentedViewController == nil { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The explicit review action did not dismiss its sheet")
        throw Failure.missingReview
    }

    private func injectUncertainPair(into mounted: Mounted) async throws {
        // Cancel a real restored-source reader before installing the frozen
        // proposals. It must not publish an unrelated result into this UI test.
        mounted.canvas.recognizesChordInk = false
        let inputAt = Date().addingTimeInterval(-2)
        mounted.canvas.chordDraftRenderCoordinator?.lastInputAt = inputAt
        let source = try PKDrawing(data: XCTUnwrap(mounted.model.chart.pageHandwrittenChordData))
        let callback = try XCTUnwrap(mounted.canvas.onChordInkDraftPreviewChanged)
        let measureID = mounted.model.chart.measures[0].id
        let payloads = source.strokes.enumerated().map { index, stroke in
            uncertainPayload(text: index == 0 ? "C" : "Bb", drawing: PKDrawing(strokes: [stroke]),
                measureID: measureID, index: index)
        }
        callback(payloads)
        for _ in 0..<40 {
            mounted.window.layoutIfNeeded()
            if mounted.canvas.chordPreviewState.draftChords.count == payloads.count { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(mounted.canvas.chordPreviewState.draftChords.count, 2)
        // The fixture is an already-completed uncertain result. Stop unrelated
        // real-reader bootstrap work; the Editor still owns the injected state.
        mounted.canvas.recognizesChordInk = false
        mounted.canvas.chordDraftRenderCoordinator?.lastInputAt = inputAt
        if !mounted.canvas.manualRenderWithPreview {
            let lastID = try XCTUnwrap(mounted.canvas.chordPreviewState.draftChords.last?.id)
            // A frozen actual-attempt refusal is injected separately from the
            // uncertain reader result. Ordinary supported guesses must not be
            // required to expose a Review action in automatic mode.
            let feedback = ChordInkAutomaticRenderFeedback(reasonsByDraftID: [lastID: .needsSpace])
            mounted.canvas.onChordInkAutomaticActivityChanged?(.init(chartID: mounted.model.chart.id,
                sourceRevision: mounted.canvas.automaticChordInputRevision, hasSourceInk: true,
                phase: .settled, pendingTargetCount: 0, inputAt: inputAt, feedback: feedback))
        }
    }

    private func uncertainPayload(text: String, drawing: PKDrawing, measureID: UUID,
        index: Int, confidence: Double = 0) -> ChordInkRecognitionProposalPayload {
        let ink = PencilKitInkAdapter.inkStrokes(from: drawing)
        let fraction = index == 0 ? 0.25 : 0.75
        let anchor = ChordInkDraftAnchor(measureID: measureID, laneLocation: nil,
            visualOrder: Double(index), fraction: fraction)
        let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: confidence,
            candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: confidence)])
        let time = Date().addingTimeInterval(-2)
        return ChordInkRecognitionProposalPayload(requestID: UUID(), result: result,
            strokes: ink, drawingData: drawing.dataRepresentation(), target: (measureID, fraction),
            visualOrder: Double(index), targetLifecycle: ChordInkRecognitionTargetLifecycle(
                generationID: UUID(), anchor: anchor, ownership: .init(preparedStrokes: ink), stage: .stable),
            timing: .init(scheduledAt: time, requestedDelay: 0, recognitionStartedAt: time,
                recognitionFinishedAt: time, strokeCount: drawing.strokes.count))
    }

    private var placementRefusalLabel: String {
        "Bb. \(ChordInkAutomaticRenderReason.needsSpace.userMessage) Fix writing"
    }

    private func waitForReviewFields(in window: UIWindow, count: Int,
        requiresFocus: Bool = true) async throws -> [IChartTypedUITextField] {
        for _ in 0..<50 {
            window.layoutIfNeeded()
            let fields = descendants(window).compactMap { $0 as? IChartTypedUITextField }
                .filter { $0.placeholder == "Chord" }
                .sorted { $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY }
            if fields.count == count, !requiresFocus || fields.contains(where: \.isFirstResponder) { return fields }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Automatic feedback - missing focused review failure")
        let fields = descendants(window).compactMap { $0 as? IChartTypedUITextField }
        let details = fields.map {
            "text=\($0.text ?? "nil"), placeholder=\($0.placeholder ?? "nil"), focused=\($0.isFirstResponder), frame=\($0.convert($0.bounds, to: window))"
        }.joined(separator: "\n")
        let labels = try NativeAccessibilityLookup.nodes(in: window).compactMap { $0.element.accessibilityLabel }
        let attachment = XCTAttachment(string: "presented=\(String(describing: window.rootViewController?.presentedViewController))\nfields:\n\(details)\nlabels:\n\(labels.joined(separator: "\n"))")
        attachment.name = "Automatic feedback - current review route and focus"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("The current editor did not present the complete focused chord review")
        throw Failure.missingReview
    }

    private func settledCanvasFrame(in mounted: Mounted) async -> CGRect {
        var previous = CGRect.null
        var stableSamples = 0
        for _ in 0..<16 {
            mounted.window.layoutIfNeeded()
            let frame = mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window)
            stableSamples = frame == previous ? stableSamples + 1 : 0
            if stableSamples >= 2 { return frame }
            previous = frame
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return mounted.canvas.convert(mounted.canvas.bounds, to: mounted.window)
    }

    private func assertFocusedFieldVisibleInsideReview(_ field: IChartTypedUITextField,
        in mounted: Mounted) async throws {
        var stableSamples = 0
        var lastDiagnostic = ""
        for _ in 0..<30 {
            mounted.window.layoutIfNeeded()
            var ancestor = field.superview
            var scroll: UIScrollView?
            while let current = ancestor {
                if let candidate = current as? UIScrollView { scroll = candidate; break }
                ancestor = current.superview
            }
            let fieldFrame = field.convert(field.bounds, to: mounted.window)
            let scrollFrame = scroll.map { $0.convert($0.bounds, to: mounted.window) } ?? .null
            let sheet = mounted.window.rootViewController?.presentedViewController?.view
            let sheetFrame = sheet.map { $0.convert($0.bounds, to: mounted.window) } ?? .null
            let keyboardFrame = mounted.window.keyboardLayoutGuide.layoutFrame.intersection(mounted.window.bounds)
            let keyboardTop = !keyboardFrame.isNull && keyboardFrame.height > 44
                ? keyboardFrame.minY : mounted.window.bounds.maxY
            let visible = field.isFirstResponder && !scrollFrame.isNull && !sheetFrame.isNull
                && scrollFrame.insetBy(dx: -1, dy: -1).contains(fieldFrame)
                && fieldFrame.minY >= sheetFrame.minY + 44
                && fieldFrame.maxY <= keyboardTop - 2
            stableSamples = visible ? stableSamples + 1 : 0
            if stableSamples >= 2 { return }
            lastDiagnostic = "field=\(fieldFrame), scroll=\(scrollFrame), sheet=\(sheetFrame), keyboard=\(keyboardFrame)"
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(mounted.window, name: "Automatic feedback - clipped focused row failure")
        XCTFail("Focused Bb entry must settle fully inside the review scroll viewport and above keyboard occlusion: \(lastDiagnostic)")
        throw Failure.missingReview
    }

    private func guideGeometryDiagnostics(in mounted: Mounted) -> String {
        let canvas = mounted.canvas
        var ancestry = [String]()
        var current: UIView? = canvas
        while let view = current {
            var detail = "\(type(of: view)): frame=\(view.frame), bounds=\(view.bounds), inWindow=\(view.convert(view.bounds, to: mounted.window)), transform=\(view.transform)"
            if let scroll = view as? UIScrollView {
                detail += "; offset=\(scroll.contentOffset), size=\(scroll.contentSize), adjustedInsets=\(scroll.adjustedContentInset), zoom=\(scroll.zoomScale), dragging=\(scroll.isDragging), decelerating=\(scroll.isDecelerating)"
            }
            ancestry.append(detail)
            current = view.superview
        }
        let responders = descendants(mounted.window).filter(\.isFirstResponder).map {
            "\(type(of: $0)): frame=\($0.convert($0.bounds, to: mounted.window))"
        }
        return """
        mode=\(canvas.interactionMode), suspended=\(canvas.isInteractionSuspended), manual=\(canvas.manualRenderWithPreview)
        window=\(mounted.window.bounds), safeArea=\(mounted.window.safeAreaInsets), orientation=\(String(describing: mounted.window.windowScene?.effectiveGeometry.interfaceOrientation))
        presented=\(String(describing: mounted.window.rootViewController?.presentedViewController))
        firstResponders=\(responders)
        ancestry:
        \(ancestry.joined(separator: "\n"))
        """
    }

    private func attachGuideGeometry(before: String, in mounted: Mounted, name: String) {
        let attachment = XCTAttachment(string: "Before Guide:\n\(before)\nAfter Guide:\n\(guideGeometryDiagnostics(in: mounted))")
        attachment.name = name + " - native canvas scroll and focus geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToEndingLabelInPresentedReview(in mounted: Mounted) async throws -> IChartTypedUITextField {
        for _ in 0..<60 {
            mounted.window.layoutIfNeeded()
            guard let panel = mounted.window.rootViewController?.presentedViewController?.view else {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            panel.layoutIfNeeded()
            let panelFrame = panel.convert(panel.bounds, to: mounted.window)
                .intersection(mounted.window.bounds)
            if let field = descendants(panel).compactMap({ $0 as? IChartTypedUITextField }).first(where: {
                $0.placeholder == "Ending label"
            }), let scroll = ancestorScrollView(of: field) {
                let fieldFrame = field.convert(field.bounds, to: mounted.window)
                let visibleForm = scroll.convert(scroll.bounds, to: mounted.window).intersection(panelFrame)
                if !field.isHidden, field.isEnabled, !fieldFrame.isEmpty,
                   visibleForm.insetBy(dx: -1, dy: -1).contains(fieldFrame) {
                    return field
                }
                // Use the review Form's real scroll container; the editor's
                // paper behind the sheet must never be scrolled to find a field.
                scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
            } else if let scroll = descendants(panel).compactMap({ $0 as? UIScrollView }).filter({
                !$0.isHidden && $0.contentSize.height + $0.adjustedContentInset.top + $0.adjustedContentInset.bottom > $0.bounds.height + 1
            }).max(by: {
                let lhs = $0.convert($0.bounds, to: mounted.window).intersection(panelFrame)
                let rhs = $1.convert($1.bounds, to: mounted.window).intersection(panelFrame)
                return lhs.width * lhs.height < rhs.width * rhs.height
            }) {
                // Form rows may be lazy. Scroll the actual presented form to
                // load the label row before trying to interact with its field.
                let maximumY = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let nextY = min(maximumY, scroll.contentOffset.y + scroll.bounds.height * 0.55)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: nextY), animated: false)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(mounted.window, name: "Ending review - label not reachable after scrolling its Form")
        XCTFail("Scrolling the presented Review Ending Form must reveal its enabled Ending label field")
        throw Failure.missingReview
    }

    private func isInsidePresentedPanel(_ node: NativeAccessibilityLookup.Node, in window: UIWindow) -> Bool {
        guard let panel = window.rootViewController?.presentedViewController?.view else { return false }
        return node.owner === panel || node.owner.isDescendant(of: panel)
    }

    private func waitForNode(in window: UIWindow,
        matching predicate: (NativeAccessibilityLookup.Node) -> Bool) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: predicate) { return node }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Automatic feedback - missing control failure viewport")
        let diagnostics = try NativeAccessibilityLookup.nodes(in: window).map {
            "\($0.automaticFeedbackIdentifier ?? "-"): \($0.element.accessibilityLabel ?? "-") frame=\($0.frame(in: window)) type=\(type(of: $0.element)) traits=\($0.element.accessibilityTraits.rawValue) owner=\(type(of: $0.owner)) ownerBounds=\($0.owner.bounds)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "Automatic feedback accessibility nodes"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
        XCTFail("The expected automatic feedback or review control was not exposed")
        throw Failure.missingStatus
    }

    private func renderedActionFrame(_ label: String, below minimumY: CGFloat,
        in window: UIWindow) async throws -> CGRect {
        if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: {
            $0.isButton && $0.element.accessibilityLabel == label
                && $0.frame(in: window).minY >= minimumY
        }) {
            XCTAssertTrue(node.isEnabled)
            return node.frame(in: window)
        }
        // Rendered-control coverage when the hosted SwiftUI ScrollView's AX
        // provider omits its children. OCR proves visible label geometry only;
        // it does not prove button enablement or simulate a tap.
        return try await renderedPhraseFrame(label, below: minimumY, in: window)
    }

    private func renderedPhraseFrame(_ phrase: String, below minimumY: CGFloat = 0,
        in window: UIWindow) async throws -> CGRect {
        func normalized(_ text: String) -> String {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        }
        let expected = normalized(phrase)
        var lastText = ""
        for _ in 0..<12 {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let bounds = observation.boundingBox
                let frame = CGRect(x: bounds.minX * window.bounds.width,
                    y: (1 - bounds.maxY) * window.bounds.height,
                    width: bounds.width * window.bounds.width, height: bounds.height * window.bounds.height)
                return frame.minY >= minimumY ? (text, frame) : nil
            }
            lastText = lines.map(\.0).joined(separator: "\n")
            for start in lines.indices {
                var text = ""
                var frame = CGRect.null
                for end in start..<min(lines.count, start + 8) {
                    text += " " + lines[end].0
                    frame = frame.union(lines[end].1)
                    if normalized(text).contains(expected) { return frame }
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Rendered repeat guidance missing expected text")
        let attachment = XCTAttachment(string: lastText)
        attachment.name = "Rendered repeat guidance OCR"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("The visible editor did not render \(phrase)")
        throw Failure.missingStatus
    }

    private func installFrozenManualReviewSourceIfNeeded() {
        guard let canvas = frozenManualCanvas, canvas.manualRenderWithPreview,
              let coordinator = canvas.chordDraftRenderCoordinator else { return }
        // These tests inject completed proposals while disabling the reader.
        // A representable update can reinstall the production reader preflight
        // without causing a host layout. Bind the frozen fixture explicitly at
        // the action boundary, using the REAL visible drawing and exact draft
        // source coverage; this does not bypass the renderer's source checks.
        coordinator.manualPreviewDrawingProvider = { [weak canvas] in
            canvas?.currentChordInkSourceDrawing()
        }
        guard allowsFrozenManualPreflight else { return }
        coordinator.manualPreviewPreparer = { [weak canvas] in
            guard let canvas, let current = canvas.currentChordInkSourceDrawing(),
                  !canvas.chordPreviewState.isEmpty else { return false }
            var currentChart = canvas.chart
            currentChart.pageHandwrittenChordData = current.dataRepresentation()
            return ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: currentChart,
                state: canvas.chordPreviewState)
        }
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if ["Render Chords", "Review & Render", "Render All"].contains(node.element.accessibilityLabel ?? "") {
            installFrozenManualReviewSourceIfNeeded()
        }
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
    }

    private func attachSoftwareKeyboardScreen(_ window: UIWindow, name: String) {
        // Hosted unit tests are not authorized to use XCUIScreen: that API
        // returned a black 1 x 1 image and recorded a UI-testing failure. Keep
        // app geometry here; root captures actual keyboard pixels via simctl.
        attach(window, name: name + " - app window only")
        let scene = window.windowScene
        let details = """
        App-window capture only; this image does not contain or prove system keyboard pixels.
        windowBounds=\(window.bounds)
        windowFrame=\(window.frame)
        sceneOrientation=\(String(describing: scene?.effectiveGeometry.interfaceOrientation))
        sceneCoordinateBounds=\(String(describing: scene?.coordinateSpace.bounds))
        keyboardLayoutGuide=\(window.keyboardLayoutGuide.layoutFrame)
        A separate real keyboard notification frame >=180 points is mandatory in the test.
        """
        let attachment = XCTAttachment(string: details)
        attachment.name = name + " - keyboard geometry and capture limitation"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
    }

    private func mount(manual: Bool, viewport: CGSize = CGSize(width: 820, height: 1_180),
        sourceDrawing: PKDrawing? = nil, repository: ChartRepository? = nil, initialChart: Chart? = nil,
        freezesRecognition: Bool = true, dynamicTypeSize: DynamicTypeSize? = nil,
        coordinatorOverride: ((ChordInkDraftRenderCoordinator) -> Void)? = nil) async throws -> Mounted {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(manual, forKey: key)
        let chart: Chart
        if let initialChart {
            chart = initialChart
        } else {
            var fixture = Chart.draft(title: "Disposable automatic feedback", layoutStyle: .rhythmSectionSheet)
            fixture.completeInitialSetup(title: fixture.title, key: .cMajor,
                meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
            _ = fixture.setPageHandwrittenChordDrawing((sourceDrawing ?? drawing()).dataRepresentation())
            chart = fixture
        }
        let model = FeedbackEditorChartModel(chart)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ChartLibraryStore(charts: [chart], selectedChartID: chart.id, repository: repository)
        let chartBinding: Binding<Chart>
        if let repository {
            try repository.saveSnapshot(store.snapshot)
            chartBinding = try XCTUnwrap(store.editorBinding(for: chart.id))
        } else {
            chartBinding = Binding(get: { model.chart }, set: { model.chart = $0 })
        }
        let root = NavigationStack {
            EditorView(chart: chartBinding,
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry,
                recognizesChordInk: !freezesRecognition)
        }
        .environmentObject(store)
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        .environment(\.accessibilityEnabled, true)
        .transformEnvironment(\.dynamicTypeSize) { currentSize in
            if let dynamicTypeSize { currentSize = dynamicTypeSize }
        }
        let wantsLandscape = viewport.width > viewport.height
        let requestedMask: UIInterfaceOrientationMask = wantsLandscape ? .landscapeRight : .portrait
        let host = FeedbackFixtureHostingController(rootView: root)
        if freezesRecognition || coordinatorOverride != nil {
            host.onFixtureLayout = { [weak self] view in
                if freezesRecognition { self?.freezeFixtureRecognition(in: view) }
                for canvas in self?.descendants(view).compactMap({ $0 as? LeadSheetCanvasUIKitView }) ?? [] {
                    if let coordinator = canvas.chordDraftRenderCoordinator { coordinatorOverride?(coordinator) }
                }
            }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousOrientation = scene.effectiveGeometry.interfaceOrientation
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        if freezesRecognition { freezeFixtureRecognition(in: host.view) }
        // A new key window's orientation controller is installed during its
        // appearance transaction. Requesting geometry synchronously from
        // makeKeyAndVisible can still consult the previous portrait host,
        // even though this host already reports support for landscape.
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if freezesRecognition { freezeFixtureRecognition(in: host.view) }
            if host.hasAppeared, window.isKeyWindow, scene.activationState == .foregroundActive { break }
            if host.hasAppeared, !window.isKeyWindow, scene.activationState == .foregroundActive {
                window.makeKey()
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow && scene.activationState == .foregroundActive,
            "The fixture must own an appeared active key-window host before requesting scene geometry: appeared=\(host.hasAppeared), key=\(window.isKeyWindow), scene=\(scene.activationState.rawValue), attached=\(host.view.window === window)")
        host.setNeedsUpdateOfSupportedInterfaceOrientations()
        try await Task.sleep(nanoseconds: 50_000_000)
        if freezesRecognition { freezeFixtureRecognition(in: host.view) }
        let beforeGeometry = geometryDiagnostics(scene: scene, window: window, host: host,
            requestedMask: requestedMask)
        var geometryError: String?
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: requestedMask)) { error in
            let error = error as NSError
            geometryError = "\(error.domain) code=\(error.code): \(error.localizedDescription); info=\(error.userInfo)"
        }
        var stableGeometrySamples = 0
        for _ in 0..<60 {
            let orientation = scene.effectiveGeometry.interfaceOrientation
            let matchesRequestedOrientation = requestedMask.rawValue & (1 << orientation.rawValue) != 0
            let sceneBounds = scene.coordinateSpace.bounds
            window.frame = sceneBounds
            window.layoutIfNeeded()
            // Rotation can rebuild the representable and restore its live
            // bridge. Freeze at first appearance, before every awaited delay.
            if freezesRecognition { freezeFixtureRecognition(in: host.view) }
            let matchesSceneBounds = abs(window.bounds.width - sceneBounds.width) < 0.5
                && abs(window.bounds.height - sceneBounds.height) < 0.5
            stableGeometrySamples = matchesRequestedOrientation && matchesSceneBounds ? stableGeometrySamples + 1 : 0
            if stableGeometrySamples >= 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let afterGeometry = geometryDiagnostics(scene: scene, window: window, host: host,
            requestedMask: requestedMask)
        let geometryAttachment = XCTAttachment(string: "Before request:\n\(beforeGeometry)\nAfter request:\n\(afterGeometry)\nRequest error: \(geometryError ?? "none reported")")
        geometryAttachment.name = wantsLandscape ? "Landscape scene geometry request" : "Portrait scene geometry request"
        geometryAttachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(geometryAttachment)
        XCTAssertNotEqual(requestedMask.rawValue & (1 << scene.effectiveGeometry.interfaceOrientation.rawValue), 0,
            "The actual scene must match the requested viewport. Geometry request error: \(geometryError ?? "none reported"). \(afterGeometry)")
        XCTAssertGreaterThanOrEqual(stableGeometrySamples, 3,
            "Exact orientation and window geometry must settle before opening the software keyboard")
        // Rotation can hand key status back to the application window after
        // the fixture's first appearance. Reclaim this controlled editor host
        // before presentation; keyboard focus later uses the field's window.
        window.makeKey()
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow && scene.activationState == .foregroundActive,
            "The appeared fixture must own an active key window after rotation. \(afterGeometry)")
        XCTAssertEqual(window.bounds.width, viewport.width, accuracy: 0.5,
            "The real scene must provide the requested test viewport width")
        XCTAssertEqual(window.bounds.height, viewport.height, accuracy: 0.5,
            "The real scene must provide the requested test viewport height")
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if let canvas = descendants(host.view).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first {
                if freezesRecognition { canvas.recognizesChordInk = false }
                if freezesRecognition {
                    XCTAssertEqual(model.chart.measures.flatMap(\.chordEvents), chart.measures.flatMap(\.chordEvents),
                        "A frozen review fixture must not automatically commit during its orientation setup")
                }
                let mounted = Mounted(model: model, store: store, window: window, canvas: canvas, previousWindow: previousWindow,
                    previousPreference: previous, directory: directory, previousOrientation: previousOrientation)
                frozenManualCanvas = freezesRecognition ? canvas : nil
                addTeardownBlock { await mounted.close() }
                return mounted
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        window.isHidden = true
        window.rootViewController = nil
        if let previous { UserDefaults.standard.set(previous, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        previousWindow?.makeKey()
        throw Failure.missingCanvas
    }

    private func freezeFixtureRecognition(in root: UIView) {
        for canvas in descendants(root).compactMap({ $0 as? LeadSheetCanvasUIKitView }) {
            canvas.recognizesChordInk = false
            // Existing coordinator injection keeps this presentation fixture
            // source-preserving if a restored read was already queued. The
            // real reviewed-render bridge remains installed for acceptance.
            canvas.chordDraftRenderCoordinator?.automaticAttempter = { _, state, _, _ in
                .init(feedback: .init(reasonsByDraftID: Dictionary(uniqueKeysWithValues:
                    state.draftChords.map { ($0.id, .needsSpace) })))
            }
        }
    }

    private func drawing() -> PKDrawing {
        // The earlier subpixel dots were intentionally invisible to source
        // preparation; a legitimate empty-census publication could erase the
        // injected preview while its old accessibility node remained cached.
        landscapeSourceDrawing()
    }



    private func geometryDiagnostics(scene: UIWindowScene, window: UIWindow, host: UIViewController,
        requestedMask: UIInterfaceOrientationMask) -> String {
        let windows = scene.windows.map { candidate in
            "\(type(of: candidate)): key=\(candidate.isKeyWindow), hidden=\(candidate.isHidden), bounds=\(candidate.bounds), root=\(String(describing: candidate.rootViewController.map { type(of: $0) })), rootMask=\(String(describing: candidate.rootViewController?.supportedInterfaceOrientations.rawValue))"
        }.joined(separator: "\n")
        let coordinateBounds: CGRect
        if #available(iOS 26.0, *) { coordinateBounds = scene.effectiveGeometry.coordinateSpace.bounds }
        else { coordinateBounds = scene.coordinateSpace.bounds }
        return """
        requestedMask=\(requestedMask.rawValue)
        legacyOrientation=\(scene.interfaceOrientation.rawValue)
        effectiveOrientation=\(scene.effectiveGeometry.interfaceOrientation.rawValue)
        sceneBounds=\(coordinateBounds), screenBounds=\(scene.screen.bounds)
        windowFrame=\(window.frame), windowBounds=\(window.bounds), key=\(window.isKeyWindow)
        hostMask=\(host.supportedInterfaceOrientations.rawValue), appMask=\(UIApplication.shared.supportedInterfaceOrientations(for: window).rawValue)
        bundleOrientations=\(String(describing: Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad")))
        windows:\n\(windows)
        """
    }

    private func landscapeSourceDrawing() -> PKDrawing {
        PKDrawing(strokes: [106.0, 300.0].enumerated().map { index, x in
            let locations = [CGPoint(x: x, y: 80), CGPoint(x: x, y: 48), CGPoint(x: x + 22, y: 48),
                CGPoint(x: x + 22, y: 80)]
            let points = locations.enumerated().map { offset, location in
                PKStrokePoint(location: location, timeOffset: Double(offset) * 0.01,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(index + 1))),
                transform: .identity, mask: nil, randomSeed: UInt32(index + 1))
        })
    }

    private func ancestorScrollView(of view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let parent = ancestor {
            if let scroll = parent as? UIScrollView { return scroll }
            ancestor = parent.superview
        }
        return nil
    }

    private func descendants(_ root: UIView) -> [UIView] { root.subviews.flatMap { [$0] + descendants($0) } }
    private enum Failure: Error { case missingCanvas, missingStatus, missingReview, missingReviewWindow, missingSoftwareKeyboard }

    @MainActor
    private struct Mounted {
        let model: FeedbackEditorChartModel
        let store: ChartLibraryStore
        let window: UIWindow
        let canvas: LeadSheetCanvasUIKitView
        let previousWindow: UIWindow?
        let previousPreference: Any?
        let directory: URL
        let previousOrientation: UIInterfaceOrientation
        func close() async {
            canvas.recognizesChordInk = false
            window.endEditing(true)
            if let root = window.rootViewController, root.presentedViewController != nil {
                await withCheckedContinuation { continuation in
                    root.dismiss(animated: false) { continuation.resume() }
                }
            }
            let scene = window.windowScene
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            let mask: UIInterfaceOrientationMask
            switch previousOrientation {
            case .landscapeLeft: mask = .landscapeLeft
            case .landscapeRight: mask = .landscapeRight
            case .portraitUpsideDown: mask = .portraitUpsideDown
            default: mask = .portrait
            }
            previousWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            await Task.yield()
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            var stableSamples = 0
            for _ in 0..<60 {
                let matchesOrientation = scene?.effectiveGeometry.interfaceOrientation == previousOrientation
                let restoredKeyWindow = previousWindow == nil || previousWindow?.isKeyWindow == true
                stableSamples = matchesOrientation && restoredKeyWindow ? stableSamples + 1 : 0
                if stableSamples >= 3 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertGreaterThanOrEqual(stableSamples, 3,
                "The fixture must finish keyboard/window/orientation teardown before the next UI test")
            let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
            if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}

/// Stops restored-source work synchronously in the hosting layout transaction,
/// before an automatic render callback can race the frozen UI fixture setup.
@MainActor
private final class FeedbackFixtureHostingController<Content: View>: UIHostingController<Content> {
    var onFixtureLayout: ((UIView) -> Void)?
    private(set) var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onFixtureLayout?(view)
    }
}

/// Records only real UIKit keyboard notifications; no synthetic notification
/// or custom inputView can satisfy the software-keyboard presence assertion.
@MainActor
private final class FeedbackSoftwareKeyboardProbe: NSObject {
    private weak var window: UIWindow?
    private var localFrame: CGRect?
    private var boundsAtNotification: CGRect?
    private var orientationAtNotification: UIInterfaceOrientation?
    private var events: [String] = []
    var diagnostics: String { events.joined(separator: " | ") }

    init(window: UIWindow) {
        self.window = window
        super.init()
        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden(_:)),
            name: UIResponder.keyboardDidHideNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func keyboardChanged(_ notification: Notification) {
        record(notification)
        guard let window,
              let screenFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        // Convert while the notification's screen geometry is current. A raw
        // frame retained through a scene rotation belongs to the old coordinate
        // space and can otherwise be mistaken for a full-window keyboard.
        localFrame = window.convert(screenFrame, from: window.screen.coordinateSpace).intersection(window.bounds)
        boundsAtNotification = window.bounds
        orientationAtNotification = window.windowScene?.effectiveGeometry.interfaceOrientation
    }
    @objc private func keyboardHidden(_ notification: Notification) {
        record(notification)
        localFrame = nil
    }
    func frame(in window: UIWindow) -> CGRect? {
        guard self.window === window, let local = localFrame,
              boundsAtNotification == window.bounds,
              orientationAtNotification == window.windowScene?.effectiveGeometry.interfaceOrientation else { return nil }
        return local.isNull || local.isEmpty ? nil : local
    }

    private func hasFirstResponder(in view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains { hasFirstResponder(in: $0) }
    }

    private func record(_ notification: Notification) {
        let raw = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let converted = window.flatMap { window in
            raw.map { window.convert($0, from: window.screen.coordinateSpace).intersection(window.bounds) }
        }
        let key = window?.isKeyWindow ?? false
        let focused = window.map { hasFirstResponder(in: $0) } ?? false
        let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation.rawValue
        let keyWindowTypes = window?.windowScene?.windows.filter(\.isKeyWindow).map { String(describing: type(of: $0)) }
        events.append("\(notification.name.rawValue): t=\(ProcessInfo.processInfo.systemUptime), raw=\(String(describing: raw)), local=\(String(describing: converted)), key=\(key), focused=\(focused), orientation=\(String(describing: orientation)), bounds=\(String(describing: window?.bounds)), sceneKeys=\(String(describing: keyWindowTypes))")
        if events.count > 20 { events.removeFirst(events.count - 20) }
    }
}

private extension NativeAccessibilityLookup.Node {
    var automaticFeedbackIdentifier: String? {
        identifier
    }
}

@MainActor
private final class FeedbackEditorChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}

private final class FailingFeedbackChartRepository: ChartRepository {
    let savesSnapshotsOffMainThread = true
    private let disk: FileChartRepository
    private let lock = NSLock()
    private var failsWrites = false
    private var failureCount = 0

    init(disk: FileChartRepository) { self.disk = disk }

    func setWriteFailure(_ failsWrites: Bool) {
        lock.withLock { self.failsWrites = failsWrites }
    }

    var failedWriteCount: Int { lock.withLock { failureCount } }

    func loadSnapshot() throws -> ChartLibrarySnapshot? { try disk.loadSnapshot() }

    func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
        try lock.withLock {
            if failsWrites {
                failureCount += 1
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        try disk.saveSnapshot(snapshot)
    }
}
#endif
