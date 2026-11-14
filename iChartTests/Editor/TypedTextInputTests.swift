#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class TypedTextInputTests: XCTestCase {
    func testStandaloneSearchAcceptsFirstKeyboardActionAndKeepsFocusWhileResultsChange() async throws {
        let model = TextFieldModel()
        let host = UIHostingController(rootView: SearchFieldHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), false)
        field.requestKeyboard()
        try await waitForFocus(field)
        XCTAssertTrue((field.text ?? "").isEmpty, "Focusing the search field must leave the query empty")
        field.insertText("Autumn.")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(model.text, "Autumn.", "Intentional keyboard punctuation must reach the query")
        XCTAssertEqual(field.returnKeyType, .search)
        XCTAssertEqual(field.delegate?.textFieldShouldReturn?(field), false)
        XCTAssertEqual(model.submitted, "Autumn.")
        XCTAssertTrue(field.isFirstResponder)
    }

    func testPencilScrollingStartsOutsideOwnedTextControls() throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 1200)
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 1200))
        scrollView.addSubview(content)
        let field = IChartTypedUITextField(frame: CGRect(x: 40, y: 100, width: 240, height: 52))
        let textView = IChartTypedUITextView(frame: CGRect(x: 40, y: 300, width: 240, height: 120), textContainer: nil)
        content.addSubview(field)
        content.addSubview(textView)
        let marker = IChartTypedSheetScrollSupport.ScrollMarker()
        content.addSubview(marker)
        let originalTouchTypes = scrollView.panGestureRecognizer.allowedTouchTypes
        let originalDelegate = scrollView.panGestureRecognizer.delegate
        marker.configureScrollView()
        marker.configureScrollView()
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        XCTAssertFalse(scrollView.panGestureRecognizer.allowedTouchTypes.contains(pencil))
        XCTAssertEqual(scrollView.gestureRecognizers?.filter { $0 !== scrollView.panGestureRecognizer
            && $0.allowedTouchTypes == [pencil] }.count, 1, "Repeated updates cannot duplicate the Pencil scroll gesture")
        let scopedPencilPan = try XCTUnwrap(scrollView.gestureRecognizers?.first { $0 !== scrollView.panGestureRecognizer
            && $0.allowedTouchTypes == [pencil] })
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalDelegate,
                      "The built-in UIKit gesture delegate must remain untouched")
        XCTAssertFalse(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 50, y: 110), in: scrollView))
        XCTAssertFalse(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 50, y: 310), in: scrollView))
        XCTAssertTrue(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 20, y: 110), in: scrollView))
        scrollView.contentOffset = CGPoint(x: 0, y: 240)
        XCTAssertFalse(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 50, y: 310), in: scrollView),
                       "Field exclusion must follow the current scrolled coordinate space")
        XCTAssertTrue(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 20, y: 310), in: scrollView))
        scrollView.isScrollEnabled = false
        marker.configureScrollView()
        XCTAssertFalse(scopedPencilPan.isEnabled, "Disabling scrolling must cancel the owned Pencil pan")
        XCTAssertFalse(IChartTypedSheetScrollSupport.ScrollMarker.allowsPencilScroll(at: CGPoint(x: 20, y: 310), in: scrollView))
        scrollView.isScrollEnabled = true
        marker.configureScrollView()
        XCTAssertTrue(scopedPencilPan.isEnabled)
        marker.detachScrollView()
        XCTAssertEqual(scrollView.panGestureRecognizer.allowedTouchTypes, originalTouchTypes)
        XCTAssertTrue(scrollView.panGestureRecognizer.delegate === originalDelegate)
    }

    func testRepeatedKeyboardRequestKeepsNativeDraftAndSelection() async throws {
        let context = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = context.isPencilInputExpected
        context.isPencilInputExpected = true
        let model = TextFieldModel()
        let host = UIHostingController(rootView: TextFieldHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            context.isPencilInputExpected = originalExpectation
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertTrue(field.rightView === field.inputModeButton)
        XCTAssertEqual(field.rightViewMode, .always, "Scribble must be reachable before the field is focused")
        field.requestKeyboard()
        try await waitForFocus(field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertFalse(context.isPencilInputExpected, "The action must convey keyboard intent, not only reissue focus")
        field.text = "Ebmaj7"
        field.sendActions(for: .editingChanged)
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 2))
        field.selectedTextRange = field.textRange(from: start, to: start)
        let session = TypedEditingSessionProbe(input: field)
        field.requestKeyboard()
        try await waitForFocus(field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(session.ended, 0, "Reusing the keyboard action cannot dismiss and reopen the active editor")
        XCTAssertEqual(session.began, 0, "An active field must keep the same editing session")
        XCTAssertEqual(field.text, "Ebmaj7")
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 2)
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), false,
                       "A second Pencil tap in the text body must still be reserved for typing or moving the caret")
        XCTAssertFalse(context.isPencilInputExpected, "Checking for Scribble cannot change keyboard intent")
        let toolbar = try XCTUnwrap(field.inputAccessoryView as? UIToolbar)
        let done = try XCTUnwrap(toolbar.items?.first { $0.accessibilityLabel == "Done typing" })
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(done.action), to: done.target, from: done, for: nil))
        XCTAssertTrue(context.isPencilInputExpected, "Done restores the expectation that preceded typing")
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), false)
    }

    func testKeyboardIntentOwnershipIgnoresSiblingResignAndUnrelatedInputs() throws {
        let context = try XCTUnwrap(UITextInputContext.current())
        let originalPencil = context.isPencilInputExpected
        let originalHardware = context.isHardwareKeyboardInputExpected
        let originalDictation = context.isDictationInputExpected
        let first = IChartTypedUITextField()
        let second = IChartTypedUITextField()
        let unrelated = UITextField()
        defer {
            IChartKeyboardInputContext.finish(for: second)
            context.isPencilInputExpected = originalPencil
        }
        context.isPencilInputExpected = true
        IChartKeyboardInputContext.begin(for: unrelated)
        XCTAssertTrue(context.isPencilInputExpected, "Unowned UIKit controls cannot change the shared input hint")
        IChartKeyboardInputContext.begin(for: first)
        XCTAssertFalse(context.isPencilInputExpected)
        IChartKeyboardInputContext.begin(for: second)
        IChartKeyboardInputContext.finish(for: first)
        XCTAssertFalse(context.isPencilInputExpected, "An old sibling's delayed resignation cannot undo the new keyboard owner")
        IChartKeyboardInputContext.finish(for: unrelated)
        XCTAssertFalse(context.isPencilInputExpected, "Unrelated controls do not own this input expectation")
        IChartKeyboardInputContext.handwritingBegan(in: unrelated)
        XCTAssertFalse(context.isPencilInputExpected)
        XCTAssertEqual(context.isHardwareKeyboardInputExpected, originalHardware)
        XCTAssertEqual(context.isDictationInputExpected, originalDictation)
        IChartKeyboardInputContext.finish(for: second)
        XCTAssertTrue(context.isPencilInputExpected)
    }

    func testNativeFocusAndDismissSynchronizePendingFocusRequests() async throws {
        let model = TextFieldModel()
        let host = UIHostingController(rootView: TextFieldHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        // Tap/native focus can arrive before the initial SwiftUI update's queued
        // focus reconciliation. UIKit's delegate must invalidate stale intent.
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertTrue(field.requestsFocus)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(field.isFirstResponder, "A stale unfocused update cannot undo a field tap")
        XCTAssertTrue(model.focused)

        model.text = "Keep the draft"
        host.view.layoutIfNeeded()
        XCTAssertTrue(field.resignFirstResponder())
        XCTAssertFalse(field.requestsFocus, "Native dismissal must immediately invalidate a queued focus request")
        model.text += "!"
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(field.isFirstResponder, "A binding update after dismissal cannot reopen typing")
        XCTAssertFalse(model.focused)
        XCTAssertEqual(field.text, "Keep the draft!")
    }

    func testHeaderTapsAndNextFocusTypedFieldsWithoutApplyingDraft() async throws {
        let context = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = context.isPencilInputExpected
        var chart = Chart.draft(title: "Original title")
        let root = HeaderPresentationHarness(chart: Binding(get: { chart }, set: { chart = $0 }))
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previousKeyWindow?.makeKeyAndVisible()
            context.isPencilInputExpected = originalExpectation
        }
        var fields: [IChartTypedUITextField] = []
        for _ in 0..<40 {
            window.layoutIfNeeded()
            fields = descendants(window).compactMap { $0 as? IChartTypedUITextField }
            if fields.count == 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        // The harness presents its sheet asynchronously. Existing fields alone
        // do not establish settled window activation; finish this test-owned
        // window's focus setup once, without changing the app's input behavior.
        window.makeKeyAndVisible()
        for _ in 0..<20 {
            window.layoutIfNeeded()
            if window.isKeyWindow && host.presentedViewController?.view.window === window { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(window.isKeyWindow, "The header's owning scene window must be key for real input presentation")
        let presented = try XCTUnwrap(host.presentedViewController,
            "Exercise Header in a sheet, matching its editor presentation")
        XCTAssertTrue(presented.view.window === window, "The header sheet must belong to its focused test window")
        func assertLargeDetent() {
            // Some presentation environments adapt the sheet without exposing
            // a UISheetPresentationController to the hosting controller.
            guard let sheet = presented.sheetPresentationController else { return }
            XCTAssertEqual(sheet.detents.count, 1)
            if let selectedDetent = sheet.selectedDetentIdentifier {
                XCTAssertEqual(selectedDetent, .large)
            }
        }
        assertLargeDetent()
        let title = try XCTUnwrap(fields.first { $0.placeholder == "Title" })
        let composer = try XCTUnwrap(fields.first { $0.placeholder == "Composer / Credit" })
        let style = try XCTUnwrap(fields.first { $0.placeholder == "Style Note" })
        XCTAssertEqual(fields.count, 3)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), false)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
            XCTAssertTrue(field.rightView === field.inputModeButton)
            XCTAssertEqual(field.rightViewMode, .always)
            XCTAssertGreaterThanOrEqual(field.inputModeButton.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(field.inputModeButton.bounds.height, 44)
        }
        title.requestKeyboard()
        try await waitForFocus(title)
        XCTAssertTrue(title.isFirstResponder, "One field tap must focus the header")
        XCTAssertFalse(context.isPencilInputExpected)
        title.text = "Typed draft"
        title.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(title.isFirstResponder, "Editing the draft must keep focus on Title")
        assertLargeDetent()
        XCTAssertEqual(title.delegate?.textFieldShouldReturn?(title), false)
        try await waitForFocus(composer)
        XCTAssertTrue(composer.isFirstResponder)
        XCTAssertFalse(title.isFirstResponder)
        XCTAssertEqual(composer.delegate?.textFieldShouldReturn?(composer), false)
        try await waitForFocus(style)
        XCTAssertTrue(style.isFirstResponder)
        XCTAssertFalse(composer.isFirstResponder)
        assertLargeDetent()
        XCTAssertEqual(style.returnKeyType, .done)
        XCTAssertEqual(style.delegate?.textFieldShouldReturn?(style), false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        assertLargeDetent()
        XCTAssertEqual(title.text, "Typed draft")
        XCTAssertEqual(chart.title, "Original title", "Next and Done only navigate; Apply owns the chart transaction")
        XCTAssertNil(descendants(window).compactMap { $0 as? UIButton }
            .first { $0.accessibilityLabel == "Use keyboard for header text" },
            "There must not be a second conditional toolbar step")
        captureHeaderDiagnostics(window)
        let titleMode = title.inputModeButton
        let titleScribble = try XCTUnwrap(title.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        let composerScribble = try XCTUnwrap(composer.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        let titleFrame = title.convert(title.bounds, to: window)
        let writePoint = CGPoint(x: 10, y: 10)
        XCTAssertEqual(titleMode.accessibilityLabel, "Start Scribble for Title")
        try assertPencilTapRouting(in: title, at: writePoint, expectsTyping: true)
        context.isPencilInputExpected = false
        titleMode.sendActions(for: .touchUpInside)
        XCTAssertTrue(title.isScribbleEnabled)
        XCTAssertFalse(title.isFirstResponder, "Arming Scribble must not present the keyboard")
        try assertPencilTapRouting(in: title, at: writePoint, expectsTyping: false)
        XCTAssertEqual(titleMode.accessibilityLabel, "Use keyboard for Title")
        XCTAssertEqual(titleScribble.delegate?.scribbleInteraction?(titleScribble, shouldBeginAt: writePoint), true)
        XCTAssertFalse(context.isPencilInputExpected, "Admission alone must leave the input hint untouched")
        XCTAssertEqual(composerScribble.delegate?.scribbleInteraction?(composerScribble, shouldBeginAt: writePoint), false)
        let buttonPoint = CGPoint(x: titleMode.frame.midX, y: titleMode.frame.midY)
        XCTAssertEqual(titleScribble.delegate?.scribbleInteraction?(titleScribble, shouldBeginAt: buttonPoint), false)
        titleScribble.delegate?.scribbleInteractionWillBeginWriting?(titleScribble)
        XCTAssertTrue(context.isPencilInputExpected, "Only a real writing session changes the input hint")
        titleScribble.delegate?.scribbleInteractionDidFinishWriting?(titleScribble)
        XCTAssertTrue(title.isScribbleEnabled, "Pausing between words must leave Scribble armed")
        XCTAssertEqual(title.convert(title.bounds, to: window), titleFrame, "Changing input mode must not move the field")
        titleMode.sendActions(for: .touchUpInside)
        try await waitForFocus(title)
        XCTAssertTrue(title.isFirstResponder)
        XCTAssertFalse(title.isScribbleEnabled)
        XCTAssertFalse(context.isPencilInputExpected)
        XCTAssertEqual(title.text, "Typed draft")
        XCTAssertEqual(title.delegate?.textFieldShouldReturn?(title), false)
        try await waitForFocus(composer)
        XCTAssertTrue(composer.isFirstResponder)
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: writePoint), false,
                           "Moving focus to a sibling must leave ordinary field taps in typing mode")
        }
    }

    func testTextViewScribbleAndTypingKeepTextWithoutRestartingFocus() async throws {
        let context = try XCTUnwrap(UITextInputContext.current())
        let originalExpectation = context.isPencilInputExpected
        let model = TextViewModel()
        let host = UIHostingController(rootView: TextViewHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            context.isPencilInputExpected = originalExpectation
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let view = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextView }.first)
        XCTAssertFalse(view.isFirstResponder)
        let scribble = try XCTUnwrap(view.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        let writePoint = CGPoint(x: 10, y: 10)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: writePoint), false)
        try assertPencilTapRouting(in: view, at: writePoint, expectsTyping: true)
        let button = view.inputModeButton
        XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(view.isScribbleEnabled)
        XCTAssertFalse(view.isFirstResponder)
        try assertPencilTapRouting(in: view, at: writePoint, expectsTyping: false)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: writePoint), true)
        let buttonPoint = CGPoint(x: button.frame.midX, y: button.frame.midY)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: buttonPoint), false)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
        button.sendActions(for: .touchUpInside)
        for _ in 0..<20 where !view.isFirstResponder { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertFalse(view.isScribbleEnabled)
        XCTAssertFalse(context.isPencilInputExpected)
        view.text = "Verse\nKeep this exact text"
        view.delegate?.textViewDidChange?(view)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.text, "Verse\nKeep this exact text")
        let cursor = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: 3))
        view.selectedTextRange = view.textRange(from: cursor, to: cursor)
        let session = TypedEditingSessionProbe(input: view)
        view.requestKeyboard()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertEqual(session.ended, 0, "The shared text-view action must also keep its editing session")
        XCTAssertEqual(session.began, 0)
        XCTAssertEqual(view.text, "Verse\nKeep this exact text")
        XCTAssertEqual(view.offset(from: view.beginningOfDocument,
            to: try XCTUnwrap(view.selectedTextRange).start), 3)
        let toolbar = try XCTUnwrap(view.inputAccessoryView as? UIToolbar)
        let done = try XCTUnwrap(toolbar.items?.first { $0.accessibilityLabel == "Done typing" })
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(done.action), to: done.target, from: done, for: nil))
        model.text += "!"
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(view.isFirstResponder, "A text update after Done cannot reopen the keyboard")
        XCTAssertEqual(view.text, "Verse\nKeep this exact text!")
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: writePoint), false)
    }

    private func assertPencilTapRouting(in input: UIView, at point: CGPoint, expectsTyping: Bool) throws {
        let tap = try XCTUnwrap(input.gestureRecognizers?.first { $0 is UITapGestureRecognizer && $0.delegate === input })
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let touch = TextInputPencilTouch(point: point, input: input)
        let acceptsPencil = tap.allowedTouchTypes.contains(pencil)
            && tap.delegate?.gestureRecognizer?(tap, shouldReceive: touch) != false
        XCTAssertEqual(acceptsPencil, expectsTyping)
    }

    private func waitForFocus(_ field: UITextField) async throws {
        for _ in 0..<20 where !field.isFirstResponder { try await Task.sleep(nanoseconds: 50_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    private func captureHeaderDiagnostics(_ window: UIWindow) {
        let hierarchy = XCTAttachment(string: viewHierarchy(window))
        hierarchy.name = "Presented header public view hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        screenshot.name = "Presented header after native field focus"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    private func viewHierarchy(_ view: UIView, depth: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: depth)
        var details = "\(prefix)\(String(reflecting: type(of: view))) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alpha) label=\(view.accessibilityLabel ?? "")"
        if let field = view as? UITextField {
            details += " placeholder=\(field.placeholder ?? "") firstResponder=\(field.isFirstResponder)"
        }
        if let button = view as? UIButton { details += " title=\(button.configuration?.title ?? button.currentTitle ?? "")" }
        return ([details] + view.subviews.map { viewHierarchy($0, depth: depth + 1) }).joined(separator: "\n")
    }
    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}

@MainActor
private final class TextInputPencilTouch: UITouch {
    let point: CGPoint
    let input: UIView

    init(point: CGPoint, input: UIView) {
        self.point = point
        self.input = input
        super.init()
    }

    override var type: UITouch.TouchType { .pencil }
    override func location(in view: UIView?) -> CGPoint { input.convert(point, to: view) }
}

@MainActor
private final class TypedEditingSessionProbe: NSObject {
    private(set) var began = 0
    private(set) var ended = 0

    init(input: UIView) {
        super.init()
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(didBegin), name: name, object: input)
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(didEnd), name: name, object: input)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func didBegin() { began += 1 }
    @objc private func didEnd() { ended += 1 }
}

private struct HeaderPresentationHarness: View {
    @Binding var chart: Chart
    @State private var presentsHeader = false
    var body: some View {
        Color.clear
            .sheet(isPresented: $presentsHeader) { ChartHeaderSheetView(chart: $chart) }
            .onAppear { presentsHeader = true }
    }
}

@MainActor
private final class TextViewModel: ObservableObject {
    @Published var text = ""
}

private struct TextViewHarness: View {
    @ObservedObject var model: TextViewModel
    var body: some View {
        IChartTypedTextView(text: $model.text).frame(height: 100)
    }
}

@MainActor
private final class TextFieldModel: ObservableObject {
    @Published var text = ""
    @Published var focused = false
    @Published var submitted = ""
}

private struct SearchFieldHarness: View {
    @ObservedObject var model: TextFieldModel
    var body: some View {
        VStack {
            IChartTypedTextField(placeholder: "Search charts", text: $model.text,
                returnKeyType: .search, onSubmit: { model.submitted = model.text })
                .frame(height: 52)
            if !model.text.isEmpty { Text("Results for \(model.text)") }
        }
    }
}

private struct TextFieldHarness: View {
    @ObservedObject var model: TextFieldModel
    var body: some View {
        IChartTypedTextField(placeholder: "Typed field", text: $model.text, isFocused: $model.focused)
            .frame(height: 52)
    }
}
#endif
