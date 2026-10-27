#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class EndingEditorSheetTests: XCTestCase {
    func testCustomDraftAndCancellationDoNotCreateAnEnding() {
        let chart = Chart.blank(title: "Custom ending draft", measureCount: 4)
        let before = chart
        var draft = EndingEditorDraft(request: EndingEditorRequest(startMeasureID: chart.measures[0].id))
        draft.label = "  1–3, 5.  "
        draft.endMeasureID = chart.measures[2].id
        draft.endStyle = .open

        XCTAssertEqual(draft.normalizedLabel, "1–3, 5.")
        XCTAssertTrue(draft.canApply(to: chart))
        XCTAssertEqual(chart, before, "Editing or discarding a draft cannot create a chart object.")
        XCTAssertTrue(chart.roadmapObjects.isEmpty)
    }

    func testApplyCreatesOneCustomEndingWithChosenRangeAndEdge() throws {
        var chart = Chart.blank(title: "Apply custom ending", measureCount: 4)
        let systems = chart.systems
        let ids = chart.measures.map(\.id)
        var draft = EndingEditorDraft(request: EndingEditorRequest(startMeasureID: ids[0]))
        draft.label = "1–3, 5."
        draft.endMeasureID = ids[2]
        draft.endStyle = .open

        let endingID = try XCTUnwrap(draft.apply(to: &chart))
        let ending = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertEqual(chart.roadmapObjects.count, 1)
        XCTAssertEqual(ending.startMeasureID, ids[0])
        XCTAssertEqual(ending.endMeasureID, ids[2])
        XCTAssertEqual(ending.resolvedEndingDisplayText, "1–3, 5.")
        XCTAssertEqual(ending.resolvedEndingEndStyle, .open)
        XCTAssertEqual(chart.systems.flatMap(\.measures).map(\.chordEvents), systems.flatMap(\.measures).map(\.chordEvents))
    }

    func testQuickPresetCancellationLeavesChartUntouchedAndApplyCreatesOneEnding() throws {
        for type in [RoadmapType.ending1, .ending2] {
            var chart = Chart.blank(title: "Quick ending draft", measureCount: 4)
            let before = chart
            let ids = chart.measures.map(\.id)
            let request = EndingEditorRequest(preset: type, startMeasureID: ids[1], endMeasureID: ids[3])
            let draft = EndingEditorDraft(request: request)

            XCTAssertNil(request.endingID)
            XCTAssertEqual(draft.normalizedLabel, type.compactEndingDisplayText ?? "")
            XCTAssertEqual(draft.endStyle, .closed)
            XCTAssertEqual(chart, before, "Completing or cancelling a quick preset draft cannot create an ending.")
            XCTAssertEqual(chart.updatedAt, before.updatedAt)
            let endingID = try XCTUnwrap(draft.apply(to: &chart))
            XCTAssertEqual(chart.roadmapObjects.count, 1)
            let ending = try XCTUnwrap(chart.roadmapObject(id: endingID))
            XCTAssertEqual(ending.type, type)
            XCTAssertEqual(ending.startMeasureID, ids[1])
            XCTAssertEqual(ending.endMeasureID, ids[3])
            XCTAssertEqual(ending.resolvedEndingEndStyle, .closed)
        }
    }

    func testApplyEditsExactExistingEndingAndPreservesItsNeighbor() throws {
        var chart = Chart.blank(title: "Edit ending identity", measureCount: 4)
        let ids = chart.measures.map(\.id)
        let firstID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
        let secondID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
        let secondBefore = try XCTUnwrap(chart.roadmapObject(id: secondID))
        var draft = EndingEditorDraft(request: EndingEditorRequest(ending: try XCTUnwrap(chart.roadmapObject(id: firstID))))
        draft.label = "On cue"
        draft.startMeasureID = ids[1]
        draft.endMeasureID = ids[3]
        draft.endStyle = .open

        XCTAssertEqual(draft.apply(to: &chart), firstID)
        XCTAssertEqual(chart.roadmapObjects.count, 2)
        let updated = try XCTUnwrap(chart.roadmapObject(id: firstID))
        XCTAssertEqual(updated.startMeasureID, ids[1])
        XCTAssertEqual(updated.endMeasureID, ids[3])
        XCTAssertEqual(updated.resolvedEndingDisplayText, "On cue")
        XCTAssertEqual(updated.resolvedEndingEndStyle, .open)
        XCTAssertEqual(chart.roadmapObject(id: secondID), secondBefore)
        XCTAssertFalse(chart.measure(id: ids[0])?.roadmapObjectIDs.contains(firstID) == true)
        XCTAssertTrue(chart.measure(id: ids[3])?.roadmapObjectIDs.contains(firstID) == true)
    }

    func testBlankInvalidRangeAndStaleEndingCannotApply() throws {
        var chart = Chart.blank(title: "Invalid ending draft", measureCount: 3)
        let ids = chart.measures.map(\.id)
        var draft = EndingEditorDraft(request: EndingEditorRequest(startMeasureID: ids[0]))
        let before = chart
        draft.label = "   "
        XCTAssertNil(draft.apply(to: &chart))
        draft.label = "3."
        draft.startMeasureID = ids[2]
        draft.endMeasureID = ids[0]
        XCTAssertNil(draft.apply(to: &chart))
        XCTAssertEqual(chart, before)

        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[0], endMeasureID: ids[1]))
        draft = EndingEditorDraft(request: EndingEditorRequest(ending: try XCTUnwrap(chart.roadmapObject(id: endingID))))
        XCTAssertEqual(draft.endStyle, .closed, "Opening a legacy second ending must preserve its existing closed hook.")
        XCTAssertTrue(chart.deleteRoadmapObject(endingID))
        let afterDeletion = chart
        draft.label = "On cue"
        XCTAssertNil(draft.apply(to: &chart))
        XCTAssertEqual(chart, afterDeletion, "A stale editor cannot silently recreate a deleted ending.")
    }

    func testNativeLabelSupportsScribbleAndCancelDiscardsTyping() async throws {
        let inputContext = UITextInputContext.current()
        let originalPencilExpectation = inputContext?.isPencilInputExpected
        defer {
            if let inputContext, let originalPencilExpectation {
                inputContext.isPencilInputExpected = originalPencilExpectation
            }
        }
        var chart = Chart.blank(title: "Native ending cancellation", measureCount: 4)
        let before = chart
        var appliedID: UUID?
        var cancelCount = 0
        let sheet = EndingEditorSheet(
            chart: Binding(get: { chart }, set: { chart = $0 }),
            request: EndingEditorRequest(startMeasureID: chart.measures[0].id),
            onApplied: { appliedID = $0 },
            onDeleted: { XCTFail("A new ending has no delete action.") },
            onCancelled: { cancelCount += 1 }
        )
        let mounted = try mount(sheet)
        defer { unmount(mounted) }
        try await settle()
        let field = try labelField(in: mounted.host.view)
        XCTAssertTrue((field.text ?? "").isEmpty)
        XCTAssertFalse(field.isFirstResponder, "Opening the ending editor must leave keyboard entry optional.")
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 10)), false)
        XCTAssertEqual(field.keyboardButton.accessibilityLabel, "Use keyboard for Ending label")
        let apply = try await button("Apply", in: mounted)
        XCTAssertFalse(apply.isEnabled)

        field.text = "1–3, 5."
        field.sendActions(for: .editingChanged)
        try await settle()
        XCTAssertTrue(apply.isEnabled)
        XCTAssertEqual(field.text, "1–3, 5.")
        XCTAssertEqual(chart, before)
        XCTAssertNil(appliedID)
        attach(mounted.window, name: "ending-editor-custom-draft")

        let cancel = try await button("Cancel", in: mounted)
        cancel.sendActions(for: .touchUpInside)
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(chart, before)
        XCTAssertNil(appliedID)
    }

    func testNativeApplyUpdatesExistingEndingWithoutCreatingAnother() async throws {
        var chart = Chart.blank(title: "Native ending apply", measureCount: 4)
        let ids = chart.measures.map(\.id)
        let endingID = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: ids[1], endMeasureID: ids[3]))
        var appliedID: UUID?
        let sheet = EndingEditorSheet(
            chart: Binding(get: { chart }, set: { chart = $0 }),
            request: EndingEditorRequest(ending: try XCTUnwrap(chart.roadmapObject(id: endingID))),
            onApplied: { appliedID = $0 },
            onDeleted: { XCTFail("Apply must not delete an ending.") }
        )
        let mounted = try mount(sheet)
        defer { unmount(mounted) }
        try await settle()
        let field = try labelField(in: mounted.host.view)
        XCTAssertEqual(field.text, "2.")
        field.text = "On cue"
        field.sendActions(for: .editingChanged)
        try await settle()
        XCTAssertNil(appliedID)
        XCTAssertEqual(chart.roadmapObject(id: endingID)?.resolvedEndingDisplayText, "2.")

        let apply = try await button("Apply", in: mounted)
        apply.sendActions(for: .touchUpInside)
        XCTAssertEqual(appliedID, endingID)
        XCTAssertEqual(chart.roadmapObjects.count, 1)
        let saved = try XCTUnwrap(chart.roadmapObject(id: endingID))
        XCTAssertEqual(saved.startMeasureID, ids[1])
        XCTAssertEqual(saved.endMeasureID, ids[3])
        XCTAssertEqual(saved.resolvedEndingDisplayText, "On cue")
        XCTAssertEqual(saved.resolvedEndingEndStyle, .closed)
    }

    private typealias Mounted = (window: UIWindow, host: UIHostingController<EndingEditorSheet>, previousKeyWindow: UIWindow?)

    private func mount(_ sheet: EndingEditorSheet) throws -> Mounted {
        let host = UIHostingController(rootView: sheet)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        return (window, host, previousKeyWindow)
    }

    private func unmount(_ mounted: Mounted) {
        mounted.window.isHidden = true
        mounted.window.rootViewController = nil
        mounted.previousKeyWindow?.makeKey()
    }

    private func labelField(in view: UIView) throws -> IChartTypedUITextField {
        try XCTUnwrap(descendants(view).compactMap { $0 as? IChartTypedUITextField }
            .first { $0.placeholder == "Ending label" })
    }

    private func button(_ title: String, in mounted: Mounted) async throws -> PencilOnlyUIButton {
        // NavigationStack owns its toolbar outside the hosting content view.
        // Inspect the complete scene window, including dynamic accessibility children.
        for _ in 0..<20 {
            mounted.window.layoutIfNeeded()
            mounted.host.view.layoutIfNeeded()
            let nodes = try NativeAccessibilityLookup.nodes(in: mounted.window)
            let controls = descendants(mounted.window).compactMap { $0 as? PencilOnlyUIButton }
                + nodes.compactMap { $0.element as? PencilOnlyUIButton }
            if let button = controls.first(where: {
                ($0.accessibilityLabel == title || $0.configuration?.title == title)
                    && !$0.bounds.isEmpty && !$0.isHidden && $0.window === mounted.window
            }) {
                XCTAssertTrue(button.acceptsDirectTouches, "Ending editor controls must accept finger and Pencil input.")
                return button
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        attach(mounted.window, name: "ending-editor-missing-\(title.lowercased())")
        let diagnostics = try NativeAccessibilityLookup.nodes(in: mounted.window).map {
            "\(type(of: $0.element)): label=\($0.element.accessibilityLabel ?? "nil"), id=\(($0.element as? UIView)?.accessibilityIdentifier ?? "nil"), frame=\($0.frame(in: mounted.window))"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "Ending editor \(title) control lookup"
        attachment.lifetime = .keepAlways
        add(attachment)
        throw NSError(domain: "EndingEditorSheetTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The rendered ending editor did not expose its \(title) control."])
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
