#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkReviewInputTests: XCTestCase {
    func testReviewEntryFeedbackTracksExistingValidationAndRemainingCount() {
        var entries: [String?] = ["C", " D7 "]
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]), .valid)
        XCTAssertNil(ChordInkReviewEntryValidation(text: entries[0]).feedbackText())
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: entries), 0)
        XCTAssertNil(ChordInkReviewEntryValidation.remainingMessage(for: 0))

        entries[0] = " \n "
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]), .empty)
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]).feedbackText(), "Enter a chord")
        XCTAssertNil(ChordInkReviewEntryValidation(text: entries[0]).feedbackText(hasMissingChordGuidance: true),
                     "An unread entry already has guidance explaining how to resolve it")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: entries), 1)
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingMessage(for: 1), "1 chord needs attention")

        entries[0] = "not a chord"
        entries[1] = nil
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]), .unsupported)
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]).feedbackText(), "Check this chord spelling")
        XCTAssertEqual(ChordInkReviewEntryValidation(text: entries[0]).feedbackText(hasMissingChordGuidance: true),
                       "Check this chord spelling")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: entries), 2)
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingMessage(for: 2), "2 chords need attention")

        entries = [" Ebmaj7 ", ChordSymbol.chordRepeatDisplayText]
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: entries), 0)
        XCTAssertNil(ChordInkReviewEntryValidation(text: entries[0]).feedbackText())
        for text in ["", " \n ", "C", "D7", " Ebmaj7 ", "not a chord", ChordSymbol.chordRepeatDisplayText] {
            XCTAssertEqual(ChordInkReviewEntryValidation(text: text).isRenderable,
                           ChordRecognitionCompendium.match(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil,
                           "Feedback must preserve the existing compendium eligibility for \(text)")
        }
    }

    func testBatchValidationTracksLiveEditsAndPreservesExactDraftText() async throws {
        let confirmations = ["C", "F"].enumerated().map { index, text in
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                match: ChordRecognitionCompendium.match(text), confidence: 1)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return PendingChordInkConfirmation(measureID: UUID(), measureIndex: index, result: result,
                drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision)
        }
        var lastEntries: [UUID: String] = [:]
        var acceptedTexts: [UUID: String]?
        var backCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: confirmations),
            onAcceptAll: { acceptedTexts = $0 }, onClearAndRewrite: {},
            onBackToInk: { backCount += 1 }, onEntryTextsChanged: { lastEntries = $0 })
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let fields = descendants(host.view).compactMap { $0 as? IChartTypedUITextField }
            .filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 2)
        let first = try XCTUnwrap(fields.first)
        let second = try XCTUnwrap(fields.dropFirst().first)
        let buttons = descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
        let render = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Render All" })
        let back = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Back to Writing" })
        XCTAssertTrue(render.isEnabled)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })

        // The native single-line field normalizes line breaks; use actual
        // field input here and keep newline trimming in the policy test above.
        first.text = "   "
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(render.isEnabled)
        XCTAssertEqual(lastEntries[confirmations[0].id], "   ")
        XCTAssertEqual(first.text, "   ", "Validation must preserve the field's exact whitespace draft")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: confirmations.map { lastEntries[$0.id] }), 1)

        first.text = "not a chord"
        first.sendActions(for: .editingChanged)
        second.text = ""
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(render.isEnabled)
        XCTAssertEqual(lastEntries[confirmations[0].id], "not a chord")
        XCTAssertEqual(first.text, "not a chord", "Unsupported text must remain available for correction")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: confirmations.map { lastEntries[$0.id] }), 2)
        back.sendActions(for: .touchUpInside)
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(lastEntries[confirmations[0].id], "not a chord")
        XCTAssertNil(acceptedTexts)

        second.text = "D7"
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(render.isEnabled)
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: confirmations.map { lastEntries[$0.id] }), 1)

        first.text = " Ebmaj7 "
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(render.isEnabled)
        XCTAssertEqual(first.text, " Ebmaj7 ")
        XCTAssertEqual(lastEntries[confirmations[0].id], " Ebmaj7 ", "Review must retain the exact typed draft")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: confirmations.map { lastEntries[$0.id] }), 0)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Validation must never start typing automatically")
        XCTAssertNil(acceptedTexts)
        render.sendActions(for: .touchUpInside)
        XCTAssertEqual(acceptedTexts, [confirmations[0].id: "Ebmaj7", confirmations[1].id: "D7"])
    }

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
        let back = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Back to Writing" })
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
        let inputContext = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = inputContext.isPencilInputExpected
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
        defer {
            window.isHidden = true
            inputContext.isPencilInputExpected = originalExpectation
        }
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
        XCTAssertTrue(editButtons.isEmpty, "There must not be a separate Edit stage before the native keyboard action")
        let fields = descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 5)
        let first = try XCTUnwrap(fields.first)
        let second = try XCTUnwrap(fields.dropFirst().first)
        let firstKeyboard = first.keyboardButton
        let secondKeyboard = second.keyboardButton
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Opening review must not open text entry")
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true,
                           "Writing inside a field must remain available before its keyboard action is tapped")
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 10)), false,
                           "Writing cannot start in the scrolling space beside a field")
            XCTAssertTrue(field.rightView === field.keyboardButton)
            XCTAssertEqual(field.rightViewMode, .always)
            XCTAssertGreaterThanOrEqual(field.keyboardButton.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(field.keyboardButton.bounds.height, 44)
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
        firstKeyboard.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "One embedded keyboard action must survive the SwiftUI state update")
        XCTAssertFalse(inputContext.isPencilInputExpected)
        let scribble = try XCTUnwrap(first.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true,
                       "Keyboard editing cannot permanently disable subsequent Scribble")
        first.text = "Ebmaj7"
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(first.isFirstResponder, "Editing must not dismiss the keyboard")
        XCTAssertEqual(first.text, "Ebmaj7")
        let selection = first.selectedTextRange
        firstKeyboard.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertEqual(first.text, "Ebmaj7", "Repeating the keyboard action after native input must keep the draft")
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
        firstKeyboard.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "Switching backwards must also preserve focus")
        XCTAssertEqual(first.text, "Ebmaj7")
        XCTAssertEqual(second.text, "D7")
        try endTyping(first)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Done must end typing and retain every value")
        secondKeyboard.sendActions(for: .touchUpInside)
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
        let inputContext = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = inputContext.isPencilInputExpected
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            inputContext.isPencilInputExpected = originalExpectation
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        XCTAssertFalse(field.isFirstResponder, "An unread preview must not focus itself")
        XCTAssertEqual(field.text, initialText)
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), true)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
        XCTAssertTrue(field.rightView === field.keyboardButton)
        XCTAssertEqual(field.rightViewMode, .always)
        field.keyboardButton.sendActions(for: .touchUpInside)
        try await waitForFocus(field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertFalse(inputContext.isPencilInputExpected)
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
