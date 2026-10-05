#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkReviewInputTests: XCTestCase {
    func testRestoredManualEntryAndRecoveryActionsPreserveEditingWithoutRendering() async throws {
        let result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let confirmation = PendingChordInkConfirmation(measureID: UUID(), measureIndex: 0,
            result: result, drawingData: Data(), targetFraction: 0,
            primaryDecision: decision, decision: decision)
        var lastEntries: [UUID: String] = [:]
        var accepted = false
        var backCount = 0
        var localRewriteCount = 0
        var wholeRewriteCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: [confirmation]),
            onAcceptAll: { _ in accepted = true }, onClearAndRewrite: { wholeRewriteCount += 1 },
            onBackToInk: { backCount += 1 }, onRewriteChord: { selected in
                XCTAssertEqual(selected.id, confirmation.id)
                localRewriteCount += 1
            }, initialEntryTextsByID: [confirmation.id: "D7", UUID(): "C"],
            onEntryTextsChanged: { lastEntries = $0 })
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextField }
            .first { $0.placeholder == "Chord" })
        XCTAssertEqual(field.text, "D7")
        XCTAssertEqual(lastEntries, [confirmation.id: "D7"], "Unknown restored IDs cannot become review rows")
        field.text = "G7"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(lastEntries, [confirmation.id: "G7"])
        let buttons = descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
        let back = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Back to Ink" })
        back.sendActions(for: .touchUpInside)
        let local = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Rewrite this chord in measure 1" })
        local.sendActions(for: .touchUpInside)
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(localRewriteCount, 1)
        XCTAssertEqual(wholeRewriteCount, 0)
        XCTAssertFalse(accepted)
        XCTAssertEqual(lastEntries[confirmation.id], "G7", "Recovery must retain edited neighbor text for its owner")
    }

    func testBatchFieldsKeepFocusAndEditedValuesWhenChangingRows() async throws {
        let confirmations = ["C", "A6(b5)", "D-7", "F", "G7"].enumerated().map { index, text in
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                                                   match: ChordRecognitionCompendium.match(text), confidence: 1)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return PendingChordInkConfirmation(measureID: UUID(), measureIndex: index, result: result,
                drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision)
        }
        var acceptedTexts: [UUID: String]?
        var rewriteCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: confirmations),
            onAcceptAll: { acceptedTexts = $0 }, onClearAndRewrite: { rewriteCount += 1 })
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let buttons = descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
        let footerButtons = buttons.filter { ["Render All", "Rewrite All Ink"].contains($0.accessibilityLabel ?? "") }
        XCTAssertEqual(footerButtons.count, 2)
        for button in footerButtons {
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            XCTAssertLessThanOrEqual(button.bounds.height, 80, "Footer buttons must not consume the review area")
        }
        XCTAssertTrue(buttons.allSatisfy(\.acceptsDirectTouches), "Review must accept finger taps on a physical iPad")
        let editButtons = buttons.filter { $0.accessibilityLabel?.hasPrefix("Type chord for measure ") == true }
        XCTAssertEqual(editButtons.count, 5)
        let firstEdit = try XCTUnwrap(editButtons.first)
        let secondEdit = try XCTUnwrap(editButtons.dropFirst().first)
        let fields = descendants(host.view).compactMap { $0 as? UITextField }.filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 5)
        let first = try XCTUnwrap(fields.first)
        let second = try XCTUnwrap(fields.dropFirst().first)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Opening review must not open text entry")
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true,
                           "Writing inside a field must remain available before Edit is tapped")
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 10)), false,
                           "Writing cannot start in the scrolling space beside a field")
        }
        let reviewScroll = try XCTUnwrap(ancestorScrollView(of: first))
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        XCTAssertFalse(reviewScroll.panGestureRecognizer.allowedTouchTypes.contains(pencil),
                       "The native pan must not take Pencil starts inside fields")
        XCTAssertTrue(reviewScroll.gestureRecognizers?.contains { gesture in
            gesture !== reviewScroll.panGestureRecognizer && gesture.allowedTouchTypes == [pencil]
        } == true, "Review must provide scoped Pencil scrolling outside fields")
        reviewScroll.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Moving the review viewport must not start typing")
        firstEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "Edit must focus its field and survive the SwiftUI state update")
        let scribble = try XCTUnwrap(first.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true,
                       "Keyboard editing cannot permanently disable subsequent Scribble")
        first.text = "Ebmaj7"
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(first.isFirstResponder, "Editing must not dismiss the keyboard")
        XCTAssertEqual(first.text, "Ebmaj7")
        let selection = first.selectedTextRange
        firstEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertEqual(first.text, "Ebmaj7", "Repeating Edit after native input must keep the draft")
        if let selection, let current = first.selectedTextRange {
            XCTAssertEqual(first.offset(from: first.beginningOfDocument, to: current.start),
                           first.offset(from: first.beginningOfDocument, to: selection.start))
        }
        XCTAssertEqual(first.returnKeyType, .next)
        XCTAssertEqual(first.delegate?.textFieldShouldReturn?(first), false)
        try await waitForFocus(second)
        XCTAssertTrue(second.isFirstResponder, "Next must transfer focus without the previous row stealing it")
        XCTAssertEqual(first.text, "Ebmaj7")
        second.text = "D7"
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(second.isFirstResponder)
        XCTAssertEqual(second.text, "D7")
        firstEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "Switching backwards must also preserve focus")
        XCTAssertEqual(first.text, "Ebmaj7")
        XCTAssertEqual(second.text, "D7")
        try endTyping(first)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Done must end typing and retain every value")
        secondEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(second)
        XCTAssertEqual(second.text, "D7")
        XCTAssertNil(acceptedTexts, "Editing must not implicitly render or train")
        XCTAssertEqual(rewriteCount, 0)
        let render = try XCTUnwrap(footerButtons.first { $0.accessibilityLabel == "Render All" })
        render.sendActions(for: .touchUpInside)
        XCTAssertEqual(acceptedTexts?[confirmations[0].id], "Ebmaj7")
        XCTAssertEqual(acceptedTexts?[confirmations[1].id], "D7")
        XCTAssertEqual(acceptedTexts?.count, 5)
        first.resignFirstResponder()
        try await Task.sleep(nanoseconds: 300_000_000)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Compact five-chord review with corrected values"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSingleReviewAndCorrectionRequireExplicitTypingAndDoneNeverAccepts() async throws {
        let result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let confirmation = PendingChordInkConfirmation(measureID: UUID(), measureIndex: 0,
            result: result, drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision)
        var accepted = false
        let single = ChordInkConfirmationSheetView(confirmation: confirmation,
            onAcceptCandidate: { _ in accepted = true }, onCopyFixtureJSON: { _ in .unavailable }, onClearAndRewrite: {})
        try await assertExplicitTyping(single, initialText: "", editedText: "D7")
        XCTAssertFalse(accepted)

        let correction = PendingChordCorrection(chordEventID: UUID(), measureID: UUID(), measureIndex: 0,
            currentText: "C", rawInput: nil, candidateTexts: [], enharmonicChoiceTexts: [])
        let correctionView = ChordCorrectionSheetView(correction: correction,
            onAcceptCandidate: { _, _ in accepted = true }, onCancel: {})
        try await assertExplicitTyping(correctionView, initialText: "C", editedText: "G7")
        XCTAssertFalse(accepted)
    }

    private func assertExplicitTyping<Content: View>(_ root: Content, initialText: String, editedText: String) async throws {
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        XCTAssertFalse(field.isFirstResponder, "An unread preview must not focus itself")
        XCTAssertEqual(field.text, initialText)
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), true)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
        let edit = try XCTUnwrap(descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
            .first { $0.accessibilityLabel == "Type chord for measure 1" })
        edit.sendActions(for: .touchUpInside)
        try await waitForFocus(field)
        XCTAssertTrue(field.isFirstResponder)
        field.text = editedText
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(field.delegate?.textFieldShouldReturn?(field), false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(field.isFirstResponder, "Done must dismiss typing without rendering")
        XCTAssertEqual(field.text, editedText)
    }

    private func endTyping(_ field: UITextField) throws {
        let toolbar = try XCTUnwrap(field.inputAccessoryView as? UIToolbar)
        let done = try XCTUnwrap(toolbar.items?.first { $0.accessibilityLabel == "Done typing" })
        let action = try XCTUnwrap(done.action)
        XCTAssertTrue(UIApplication.shared.sendAction(action, to: done.target, from: done, for: nil))
    }

    private func ancestorScrollView(of view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let parent = ancestor {
            if let scrollView = parent as? UIScrollView { return scrollView }
            ancestor = parent.superview
        }
        return nil
    }

    private func waitForFocus(_ field: UITextField) async throws {
        // Allow UIKit's keyboard/scroll animation, then assert focus stability.
        for _ in 0..<20 where !field.isFirstResponder {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
#endif
