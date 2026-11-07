#if canImport(UIKit)
import PencilKit
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
                drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision,
                candidateTexts: [text])
        }
        var lastEdits: [UUID: String] = [:]
        var acceptedTexts: [UUID: String]?
        var backCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: confirmations),
            onAcceptAll: { acceptedTexts = $0 }, onClearAndRewrite: {},
            onBackToInk: { backCount += 1 }, onEditedTextsChanged: { lastEdits = $0 })
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
        func renderButton() throws -> PencilOnlyUIButton {
            try XCTUnwrap(descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
                .first { $0.accessibilityLabel == "Render All" })
        }
        let back = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Back to Writing" })
        XCTAssertTrue(try renderButton().isEnabled)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        XCTAssertEqual(fields.map(\.text), ["C", "F"])
        XCTAssertTrue(lastEdits.isEmpty, "Untouched recognition guesses are not user edits")

        let firstSuggestion = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "C" })
        firstSuggestion.sendActions(for: .touchUpInside)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(lastEdits, [confirmations[0].id: "C"],
                       "Choosing a suggestion is explicit even when its text is already displayed")
        XCTAssertNil(acceptedTexts)

        // The native single-line field normalizes line breaks; use actual
        // field input here and keep newline trimming in the policy test above.
        first.text = "   "
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(try renderButton().isEnabled)
        XCTAssertEqual(lastEdits, [confirmations[0].id: "   "])
        XCTAssertEqual(first.text, "   ", "Validation must preserve the field's exact whitespace draft")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: fields.map(\.text)), 1)

        first.text = "not a chord"
        first.sendActions(for: .editingChanged)
        second.text = ""
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(try renderButton().isEnabled)
        XCTAssertEqual(lastEdits, [confirmations[0].id: "not a chord", confirmations[1].id: ""])
        XCTAssertEqual(first.text, "not a chord", "Unsupported text must remain available for correction")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: fields.map(\.text)), 2)
        back.sendActions(for: .touchUpInside)
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(lastEdits[confirmations[1].id], "", "Back to Writing must retain an intentional empty edit")
        XCTAssertNil(acceptedTexts)

        second.text = "D7"
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(try renderButton().isEnabled)
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: fields.map(\.text)), 1)

        first.text = " Ebmaj7 "
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(try renderButton().isEnabled)
        XCTAssertEqual(first.text, " Ebmaj7 ")
        XCTAssertEqual(lastEdits[confirmations[0].id], " Ebmaj7 ", "Review must retain the exact typed draft")
        XCTAssertEqual(ChordInkReviewEntryValidation.remainingCount(for: fields.map(\.text)), 0)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder }, "Validation must never start typing automatically")
        XCTAssertNil(acceptedTexts)
        try renderButton().sendActions(for: .touchUpInside)
        XCTAssertEqual(acceptedTexts, [confirmations[0].id: "Ebmaj7", confirmations[1].id: "D7"])
    }

    func testRestoredManualEntryAndRecoveryActionsPreserveEditingWithoutRendering() async throws {
        let result = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let confirmation = PendingChordInkConfirmation(measureID: UUID(), measureIndex: 0,
            result: result, drawingData: Data(), targetFraction: 0,
            primaryDecision: decision, decision: decision)
        var lastEdits: [UUID: String] = [:]
        var accepted = false
        var backCount = 0
        var localRewriteCount = 0
        var wholeRewriteCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: [confirmation]),
            onAcceptAll: { _ in accepted = true }, onClearAndRewrite: { wholeRewriteCount += 1 },
            onBackToInk: { backCount += 1 }, onRewriteChord: { selected in
                XCTAssertEqual(selected.id, confirmation.id)
                localRewriteCount += 1
            }, initialEditedTextsByID: [confirmation.id: "D7", UUID(): "C"],
            onEditedTextsChanged: { lastEdits = $0 })
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
        XCTAssertEqual(lastEdits, [confirmation.id: "D7"], "Unknown restored IDs cannot become review rows")
        field.text = "G7"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(lastEdits, [confirmation.id: "G7"])
        let buttons = descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
        let back = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Back to Writing" })
        back.sendActions(for: .touchUpInside)
        let local = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "Rewrite chord 1 in measure 1" })
        local.sendActions(for: .touchUpInside)
        XCTAssertEqual(backCount, 1)
        XCTAssertEqual(localRewriteCount, 1)
        XCTAssertEqual(wholeRewriteCount, 0)
        XCTAssertFalse(accepted)
        XCTAssertEqual(lastEdits[confirmation.id], "G7", "Recovery must retain edited neighbor text for its owner")
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
        let footerButtons = buttons.filter { ["Render All", "Clear Draft Ink"].contains($0.accessibilityLabel ?? "") }
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

    func testVisibleBatchEntryKeepsItsViewportAcrossRepeatedTypingAndUnchangedKeyboardNotification() async throws {
        let inputContext = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = inputContext.isPencilInputExpected
        let batch = stationaryReviewBatch()
        var accepted = false
        let root = Color.clear.sheet(isPresented: .constant(true)) {
            ChordInkBatchConfirmationSheetView(batch: batch,
                onAcceptAll: { _ in accepted = true }, onClearAndRewrite: {})
        }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            inputContext.isPencilInputExpected = originalExpectation
        }
        let fields = try await mountedReviewFields(in: host, window: window, count: batch.confirmations.count)
        let field = fields[1]
        let scroll = try XCTUnwrap(ancestorScrollView(of: field))
        field.keyboardButton.sendActions(for: .touchUpInside)
        try await waitForFocus(field)
        try await Task.sleep(nanoseconds: 600_000_000)
        window.layoutIfNeeded()

        // The user has deliberately positioned an already visible input away
        // from the row's top. Further keyboard requests must preserve that view.
        let contentFrame = field.convert(field.bounds, to: scroll)
        let inset = scroll.adjustedContentInset
        let maximum = max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let y = min(maximum, max(-inset.top, contentFrame.midY - scroll.bounds.height * 0.45))
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        window.layoutIfNeeded()
        XCTAssertTrue(scroll.convert(scroll.bounds, to: window).insetBy(dx: -1, dy: -1)
            .contains(field.convert(field.bounds, to: window)))
        let originalOffset = scroll.contentOffset
        let originalFieldFrame = field.convert(field.bounds, to: window)
        let originalScrollFrame = scroll.convert(scroll.bounds, to: window)
        let focusEvents = ReviewFocusEventRecorder(field: field)
        let keyboardFrame = CGRect(x: 0, y: window.bounds.maxY,
            width: window.bounds.width, height: 0)
        let duplicateKeyboardInfo: [AnyHashable: Any] = [
            UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboardFrame),
            UIResponder.keyboardAnimationDurationUserInfoKey: 0
        ]
        // This duplicates an unchanged lifecycle event. Real software-keyboard
        // avoidance is covered separately by the landscape hosted editor tests.
        NotificationCenter.default.post(name: UIResponder.keyboardDidShowNotification,
            object: nil, userInfo: duplicateKeyboardInfo)
        field.keyboardButton.sendActions(for: .touchUpInside)
        NotificationCenter.default.post(name: UIResponder.keyboardDidShowNotification,
            object: nil, userInfo: duplicateKeyboardInfo)

        var maximumOffsetTravel: CGFloat = 0
        var maximumFieldTravel: CGFloat = 0
        var maximumViewportTravel: CGFloat = 0
        for _ in 0..<40 {
            window.layoutIfNeeded()
            maximumOffsetTravel = max(maximumOffsetTravel, abs(scroll.contentOffset.y - originalOffset.y))
            let currentField = field.convert(field.bounds, to: window)
            let currentScroll = scroll.convert(scroll.bounds, to: window)
            maximumFieldTravel = max(maximumFieldTravel, abs(currentField.minY - originalFieldFrame.minY))
            maximumViewportTravel = max(maximumViewportTravel, abs(currentScroll.minY - originalScrollFrame.minY),
                abs(currentScroll.height - originalScrollFrame.height))
            if let presentation = scroll.layer.presentation() {
                maximumOffsetTravel = max(maximumOffsetTravel, abs(presentation.bounds.minY - originalOffset.y))
            }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        XCTAssertLessThanOrEqual(maximumOffsetTravel, 1.5, "A visible input must not be pulled to the row's top")
        XCTAssertLessThanOrEqual(maximumFieldTravel, 1.5, "Repeated typing must not start another panel movement")
        XCTAssertLessThanOrEqual(maximumViewportTravel, 1.5)
        XCTAssertEqual(focusEvents.beginCount, 0, "An already focused input must not restart editing")
        XCTAssertEqual(focusEvents.endCount, 0, "A repeated keyboard request must not resign the input")
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(fields.map(\.text), batch.confirmations.map(\.bestCandidateText))
        XCTAssertFalse(accepted)
    }

    func testInitiallyTargetedOffscreenBatchEntryBecomesVisibleWithoutAcceptingDraft() async throws {
        let inputContext = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = inputContext.isPencilInputExpected
        let batch = stationaryReviewBatch()
        let target = try XCTUnwrap(batch.confirmations.last)
        var accepted = false
        let root = Color.clear.sheet(isPresented: .constant(true)) {
            ChordInkBatchConfirmationSheetView(batch: batch,
                onAcceptAll: { _ in accepted = true }, onClearAndRewrite: {},
                initialFocusedConfirmationID: target.id)
        }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            inputContext.isPencilInputExpected = originalExpectation
        }
        let fields = try await mountedReviewFields(in: host, window: window, count: batch.confirmations.count)
        let field = try XCTUnwrap(fields.last)
        let scroll = try XCTUnwrap(ancestorScrollView(of: field))
        var visible = false
        for _ in 0..<100 {
            window.layoutIfNeeded()
            let viewport = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            visible = field.isFirstResponder && viewport.insetBy(dx: -1, dy: -1)
                .contains(field.convert(field.bounds, to: window))
            if visible { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertGreaterThan(field.convert(field.bounds, to: scroll).minY, scroll.bounds.height,
            "The selected row must begin below the initial viewport to exercise targeted focus")
        XCTAssertTrue(visible, "Initial focus must reveal the requested field without requiring a row-to-top animation")
        XCTAssertEqual(field.text, target.bestCandidateText)
        XCTAssertFalse(accepted)
    }

    private func stationaryReviewBatch() -> PendingChordInkBatchConfirmation {
        let confirmations = ["C", "D7", "Em7", "F", "G7", "Am7"].enumerated().map { index, text in
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                match: ChordRecognitionCompendium.match(text), confidence: 1)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return PendingChordInkConfirmation(measureID: UUID(), measureIndex: index, result: result,
                drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision)
        }
        return PendingChordInkBatchConfirmation(confirmations: confirmations)
    }

    private func mountedReviewFields(in host: UIViewController, window: UIWindow, count: Int) async throws
        -> [IChartTypedUITextField] {
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if let presented = host.presentedViewController,
               !presented.isBeingPresented, !presented.isBeingDismissed,
               presented.viewIfLoaded?.window === window {
                let fields = descendants(presented.view).compactMap { $0 as? IChartTypedUITextField }
                    .filter { $0.placeholder == "Chord" }
                if fields.count == count, fields.allSatisfy({ $0.bounds.height > 0 }) { return fields }
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        return try XCTUnwrap(nil as [IChartTypedUITextField]?, "Expected the complete native review sheet to mount")
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

@MainActor
private final class ReviewFocusEventRecorder: NSObject {
    private weak var field: UITextField?
    private(set) var beginCount = 0
    private(set) var endCount = 0

    init(field: UITextField) {
        self.field = field
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(began(_:)),
            name: UITextField.textDidBeginEditingNotification, object: field)
        NotificationCenter.default.addObserver(self, selector: #selector(ended(_:)),
            name: UITextField.textDidEndEditingNotification, object: field)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func began(_ notification: Notification) { beginCount += 1 }
    @objc private func ended(_ notification: Notification) { endCount += 1 }
}

extension ChordInkReviewInputTests {
    func testMixedNoReadAndWrongReadReviewSavesBothCorrectionsWithTheirOriginalInk() async throws {
        var chart = Chart.draft(title: "Mixed chord review", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 2)
        let chartID = chart.id
        let measureIDs = chart.measures.map(\.id)
        let coordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1_400)
        let unread = PKDrawing(strokes: [
            Self.reviewStroke([(75, 120), (58, 125), (55, 141), (73, 148)])
        ])
        let misread = PKDrawing(strokes: [
            Self.reviewStroke([(198, 121), (198, 151)]),
            Self.reviewStroke([(198, 122), (211, 125), (198, 135), (215, 141), (198, 150)]),
            Self.reviewStroke([(224, 140), (234, 122), (244, 140), (224, 140)])
        ])
        let liveDrawing = PKDrawing(strokes: unread.strokes + misread.strokes)
        _ = chart.setPageHandwrittenChordDrawing(liveDrawing.dataRepresentation(), coordinateSpace: coordinateSpace)
        let sourceDrawings = [unread, misread]
        let sourceData = sourceDrawings.map { $0.dataRepresentation() }
        func draftState(guess: String) -> ChordPreviewState {
            var state = ChordPreviewState()
            state.replaceDraftChords(with: [nil, guess].enumerated().map { index, suggestion in
                let candidates = suggestion.map { [$0] } ?? []
                let result = ChordInkRecognitionResult(rawCandidates: candidates, glyphCandidates: [],
                    match: suggestion.flatMap { ChordRecognitionCompendium.match($0) },
                    confidence: suggestion == nil ? 0 : 1)
                return ChordInkDraftInput(measureID: measureIDs[index], measureIndex: index,
                    targetFraction: 0.5, drawingData: sourceData[index], candidateTexts: candidates,
                    bestCandidateText: suggestion, confidence: result.confidence,
                    strokeCount: sourceDrawings[index].strokes.count, recognitionResult: result)
            })
            return state
        }

        var cache = ChordInkReviewEditCache()
        var editedTexts: [UUID: String] = [:]
        var acceptedTexts: [UUID: String]?
        var backCount = 0
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        defer { window.isHidden = true }
        func mount(_ batch: PendingChordInkBatchConfirmation) async throws -> UIView {
            let root = ChordInkBatchConfirmationSheetView(batch: batch,
                onAcceptAll: { acceptedTexts = $0 }, onClearAndRewrite: {}, onBackToInk: { backCount += 1 },
                initialEditedTextsByID: cache.initialEdits(for: batch, chartID: chartID),
                onEditedTextsChanged: { edits in
                    editedTexts = edits
                    cache.storeEdits(edits, for: batch, chartID: chartID)
                })
            let host = UIHostingController(rootView: root)
            window.isHidden = true
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            return host.view
        }
        func field(in view: UIView, text: String) throws -> IChartTypedUITextField {
            try XCTUnwrap(descendants(view).compactMap { $0 as? IChartTypedUITextField }
                .first { $0.placeholder == "Chord" && $0.text == text })
        }
        func button(in view: UIView, title: String) throws -> PencilOnlyUIButton {
            try XCTUnwrap(descendants(view).compactMap { $0 as? PencilOnlyUIButton }
                .first { $0.accessibilityLabel == title })
        }
        func attachReview(_ view: UIView, name: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            })
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let original = draftState(guess: "Bbø7")
        let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: original))
        let unreadRow = try XCTUnwrap(batch.confirmations.first { $0.measureID == measureIDs[0] })
        let wrongRow = try XCTUnwrap(batch.confirmations.first { $0.measureID == measureIDs[1] })
        let firstView = try await mount(batch)
        let unreadField = try field(in: firstView, text: "")
        let wrongField = try field(in: firstView, text: "Bbø7")
        let initialRender = try button(in: firstView, title: "Render All")
        XCTAssertTrue(unreadRow.requiresDirectEntry)
        XCTAssertEqual(wrongRow.bestCandidateText, "Bbø7")
        XCTAssertTrue(editedTexts.isEmpty, "Displaying a guess does not make it a user edit")
        XCTAssertFalse(initialRender.isEnabled)
        initialRender.sendActions(for: .touchUpInside)
        XCTAssertNil(acceptedTexts, "A blank row blocks submission")
        attachReview(firstView, name: "RHY-003 missing chord and recognition guess")
        unreadField.text = "Cmaj7"
        unreadField.sendActions(for: .editingChanged)
        // Capture the ready button after UIKit settles its state animation.
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(editedTexts, [unreadRow.id: "Cmaj7"])
        XCTAssertEqual(wrongField.text, "Bbø7")
        XCTAssertTrue(try button(in: firstView, title: "Render All").isEnabled, "Render All includes the still-displayed guess")
        attachReview(firstView, name: "RHY-003 user edit and remaining recognition guess")
        try button(in: firstView, title: "Back to Writing").sendActions(for: .touchUpInside)
        XCTAssertEqual(backCount, 1)
        XCTAssertNil(acceptedTexts)

        let refreshed = draftState(guess: "Bb7")
        let reopenedBatch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: refreshed))
        let reopenedUnread = try XCTUnwrap(reopenedBatch.confirmations.first { $0.measureID == measureIDs[0] })
        let reopenedWrong = try XCTUnwrap(reopenedBatch.confirmations.first { $0.measureID == measureIDs[1] })
        XCTAssertNotEqual(reopenedUnread.id, unreadRow.id)
        XCTAssertEqual(cache.initialEdits(for: reopenedBatch, chartID: chartID), [reopenedUnread.id: "Cmaj7"])
        let reopenedView = try await mount(reopenedBatch)
        _ = try field(in: reopenedView, text: "Cmaj7")
        let refreshedGuess = try field(in: reopenedView, text: "Bb7")
        refreshedGuess.text = "Bbmaj7"
        refreshedGuess.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        let expectedEdits = [reopenedUnread.id: "Cmaj7", reopenedWrong.id: "Bbmaj7"]
        XCTAssertEqual(editedTexts, expectedEdits)
        XCTAssertEqual(reopenedWrong.bestCandidateText, "Bb7", "Editing does not replace recognition evidence")
        let render = try button(in: reopenedView, title: "Render All")
        XCTAssertTrue(render.isEnabled)
        render.sendActions(for: .touchUpInside)
        XCTAssertEqual(acceptedTexts, expectedEdits)

        let reviewed = try ChordInkDraftReviewPolicy.validation(from: refreshed, batch: reopenedBatch,
            candidateTextByDraftID: XCTUnwrap(acceptedTexts)).get()
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
            currentDrawing: liveDrawing, coordinateSpace: coordinateSpace)
        XCTAssertTrue(outcome.canConsumeSource)
        XCTAssertEqual(outcome.result.renderedChordCount, 2)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library-state.json")
        try FileChartRepository(url: file).saveSnapshot(ChartLibrarySnapshot(charts: [outcome.chart],
            selectedChartID: chartID, entitlements: .free))
        let snapshot = try XCTUnwrap(try FileChartRepository(url: file).loadSnapshot())
        XCTAssertEqual(snapshot.selectedChartID, chartID)
        let saved = try XCTUnwrap(snapshot.charts.first)
        XCTAssertEqual(saved.id, chartID)
        XCTAssertEqual(saved.measures.map(\.id), measureIDs)
        XCTAssertNil(saved.pageHandwrittenChordData)
        XCTAssertNil(saved.pageHandwrittenChordCoordinateSpace)
        XCTAssertTrue(refreshed.draftChords[0].sourceCandidateSignature.isEmpty)
        XCTAssertFalse(refreshed.draftChords[1].sourceCandidateSignature.isEmpty)
        for (index, expected) in ["Cmaj7", "Bbmaj7"].enumerated() {
            let measure = try XCTUnwrap(saved.measures.first { $0.id == measureIDs[index] })
            XCTAssertEqual(measure.chordEvents.count, 1)
            let event = try XCTUnwrap(measure.chordEvents.first)
            XCTAssertEqual(event.rawInput, expected)
            XCTAssertEqual(event.symbol.displayText, ChordRecognitionCompendium.match(expected)?.displayText)
            XCTAssertEqual(event.sourceCandidateSignature, refreshed.draftChords[index].sourceCandidateSignature)
            let archivedDrawing = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: sourceDrawings[index], current: archivedDrawing))
        }
    }

    private static func reviewStroke(_ points: [(CGFloat, CGFloat)]) -> PKStroke {
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.0, y: point.1), timeOffset: Double(index) * 0.05,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }
}
#endif
