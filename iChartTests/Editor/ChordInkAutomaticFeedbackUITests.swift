#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Mounts the shipping EditorView and injects frozen proposals through its
/// actual canvas callback. These are status/recovery tests, not accuracy tests.
@MainActor
final class ChordInkAutomaticFeedbackUITests: XCTestCase {
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
        try await injectUncertainPair(into: mounted)
        let review = try await waitForNode(in: mounted.window) { node in
            node.isButton && node.element.accessibilityLabel == "Review & Render"
        }
        XCTAssertTrue(review.isEnabled)
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

    func testLandscapeSoftwareKeyboardLeavesBothReviewEntriesReachableAndCancelPreservesSource() async throws {
        let mounted = try await mount(manual: true, viewport: CGSize(width: 1_180, height: 820),
            sourceDrawing: landscapeSourceDrawing())
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
        fields[0].keyboardButton.sendActions(for: .touchUpInside)
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
        let mounted = try await mount(manual: true, viewport: CGSize(width: 1_180, height: 820),
            sourceDrawing: landscapeSourceDrawing())
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
        fields[1].keyboardButton.sendActions(for: .touchUpInside)
        _ = try await waitForReviewFields(in: mounted.window, count: 2)
        XCTAssertTrue(fields[1].isFirstResponder)
        try await establishReviewKeyboardWindow(for: fields[1], in: mounted)
        fields[1].keyboardButton.sendActions(for: .touchUpInside)
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
            let text = index == 0 ? "C" : "Bb"
            let data = PKDrawing(strokes: [stroke]).dataRepresentation()
            let ink = PencilKitInkAdapter.inkStrokes(from: PKDrawing(strokes: [stroke]))
            let fraction = index == 0 ? 0.25 : 0.75
            let anchor = ChordInkDraftAnchor(measureID: measureID, laneLocation: nil,
                visualOrder: Double(index), fraction: fraction)
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                match: ChordRecognitionCompendium.match(text), confidence: 0,
                candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: 0)])
            let time = Date().addingTimeInterval(-2)
            return ChordInkRecognitionProposalPayload(requestID: UUID(), result: result,
                strokes: ink, drawingData: data, target: (measureID, fraction), visualOrder: Double(index),
                targetLifecycle: ChordInkRecognitionTargetLifecycle(generationID: UUID(), anchor: anchor,
                    ownership: .init(preparedStrokes: ink), stage: .stable),
                timing: .init(scheduledAt: time, requestedDelay: 0, recognitionStartedAt: time,
                    recognitionFinishedAt: time, strokeCount: 1))
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

    private func waitForNode(in window: UIWindow,
        matching predicate: (NativeAccessibilityLookup.Node) -> Bool) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: predicate) { return node }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(window, name: "Automatic feedback - missing control failure viewport")
        let diagnostics = try NativeAccessibilityLookup.nodes(in: window).map {
            "\($0.automaticFeedbackIdentifier ?? "-"): \($0.element.accessibilityLabel ?? "-") frame=\($0.frame(in: window))"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "Automatic feedback accessibility nodes"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
        XCTFail("The expected automatic feedback or review control was not exposed")
        throw Failure.missingStatus
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
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
        sourceDrawing: PKDrawing? = nil) async throws -> Mounted {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(manual, forKey: key)
        var chart = Chart.draft(title: "Disposable automatic feedback", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        _ = chart.setPageHandwrittenChordDrawing((sourceDrawing ?? drawing()).dataRepresentation())
        let model = FeedbackEditorChartModel(chart)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = NavigationStack {
            EditorView(chart: Binding(get: { model.chart }, set: { model.chart = $0 }),
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry)
        }
        .environmentObject(ChartLibraryStore(charts: [chart], selectedChartID: chart.id))
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        .environment(\.accessibilityEnabled, true)
        let wantsLandscape = viewport.width > viewport.height
        let requestedMask: UIInterfaceOrientationMask = wantsLandscape ? .landscapeRight : .portrait
        let host = FeedbackFixtureHostingController(rootView: root)
        host.onFixtureLayout = { [weak self] view in self?.freezeFixtureRecognition(in: view) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousOrientation = scene.effectiveGeometry.interfaceOrientation
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        freezeFixtureRecognition(in: host.view)
        // A new key window's orientation controller is installed during its
        // appearance transaction. Requesting geometry synchronously from
        // makeKeyAndVisible can still consult the previous portrait host,
        // even though this host already reports support for landscape.
        for _ in 0..<40 {
            freezeFixtureRecognition(in: host.view)
            if host.hasAppeared, window.isKeyWindow { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow,
            "The fixture must own an appeared key-window host before requesting scene geometry")
        host.setNeedsUpdateOfSupportedInterfaceOrientations()
        try await Task.sleep(nanoseconds: 50_000_000)
        freezeFixtureRecognition(in: host.view)
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
            freezeFixtureRecognition(in: host.view)
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
                canvas.recognizesChordInk = false
                XCTAssertTrue(model.chart.measures.flatMap(\.chordEvents).isEmpty,
                    "A frozen review fixture must not automatically commit during its orientation setup")
                let mounted = Mounted(model: model, window: window, canvas: canvas, previousWindow: previousWindow,
                    previousPreference: previous, directory: directory, previousOrientation: previousOrientation)
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
        (element as? UIAccessibilityIdentification)?.accessibilityIdentifier
    }
}

@MainActor
private final class FeedbackEditorChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}
#endif
