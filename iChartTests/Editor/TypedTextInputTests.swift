#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class TypedTextInputTests: XCTestCase {
    func testScribbleStartsWithinOwnedControlsAndPencilScrollingStartsOutside() throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 1200)
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 1200))
        scrollView.addSubview(content)
        let field = IChartTypedUITextField(frame: CGRect(x: 40, y: 100, width: 240, height: 52))
        let textView = IChartTypedUITextView(frame: CGRect(x: 40, y: 300, width: 240, height: 120), textContainer: nil)
        content.addSubview(field)
        content.addSubview(textView)
        for view in [field as UIView, textView] {
            let scribble = try XCTUnwrap(view.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true)
            for point in [CGPoint(x: -1, y: 10), CGPoint(x: view.bounds.maxX + 1, y: 10),
                          CGPoint(x: 10, y: view.bounds.maxY + 1)] {
                XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: point), false)
            }
        }
        let fieldScribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        field.isEnabled = false
        XCTAssertEqual(fieldScribble.delegate?.scribbleInteraction?(fieldScribble, shouldBeginAt: .zero), false)
        field.isEnabled = true
        let textScribble = try XCTUnwrap(textView.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        textView.isEditable = false
        XCTAssertEqual(textScribble.delegate?.scribbleInteraction?(textScribble, shouldBeginAt: .zero), false)
        textView.isEditable = true

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

    func testRepeatedKeyboardRequestKeepsNativeDraftSelectionAndScribbleAvailable() async throws {
        let model = TextFieldModel()
        let host = UIHostingController(rootView: TextFieldHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }.first)
        XCTAssertTrue(field.becomeFirstResponder())
        field.text = "Ebmaj7"
        field.sendActions(for: .editingChanged)
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 2))
        field.selectedTextRange = field.textRange(from: start, to: start)
        model.focusRequest += 1
        try await waitForFocus(field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.text, "Ebmaj7")
        let selection = try XCTUnwrap(field.selectedTextRange)
        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 2)
        let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), true,
                       "An explicit keyboard request cannot leave a hidden persistent Scribble mode")
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
        }
        var fields: [IChartTypedUITextField] = []
        for _ in 0..<40 {
            window.layoutIfNeeded()
            fields = descendants(window).compactMap { $0 as? IChartTypedUITextField }
            if fields.count == 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(window.isKeyWindow, "The header's owning scene window must be key for real input presentation")
        XCTAssertNotNil(host.presentedViewController, "Exercise Header in a sheet, matching its editor presentation")
        let title = try XCTUnwrap(fields.first { $0.placeholder == "Title" })
        let composer = try XCTUnwrap(fields.first { $0.placeholder == "Composer / Credit" })
        let style = try XCTUnwrap(fields.first { $0.placeholder == "Style Note" })
        XCTAssertEqual(fields.count, 3)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), true)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
        }
        XCTAssertTrue(title.becomeFirstResponder(), "A field tap's native focus action must remain available")
        title.text = "Typed draft"
        title.sendActions(for: .editingChanged)
        XCTAssertEqual(title.delegate?.textFieldShouldReturn?(title), false)
        try await waitForFocus(composer)
        XCTAssertTrue(composer.isFirstResponder)
        XCTAssertFalse(title.isFirstResponder)
        XCTAssertEqual(composer.delegate?.textFieldShouldReturn?(composer), false)
        try await waitForFocus(style)
        XCTAssertTrue(style.isFirstResponder)
        XCTAssertEqual(style.returnKeyType, .done)
        XCTAssertEqual(style.delegate?.textFieldShouldReturn?(style), false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        XCTAssertEqual(title.text, "Typed draft")
        XCTAssertEqual(chart.title, "Original title", "Next and Done only navigate; Apply owns the chart transaction")
        XCTAssertTrue(title.becomeFirstResponder())
        try await waitForFocus(title)
        var keyboardButton: PencilOnlyUIButton?
        for _ in 0..<20 {
            window.layoutIfNeeded()
            keyboardButton = descendants(window).compactMap { $0 as? PencilOnlyUIButton }
                .first { $0.accessibilityLabel == "Use keyboard for header text" }
            if keyboardButton != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        captureHeaderDiagnostics(window)
        let titleKeyboard = try XCTUnwrap(keyboardButton, "The focused header must render its single Keyboard action")
        titleKeyboard.sendActions(for: .touchUpInside)
        try await waitForFocus(title)
        XCTAssertTrue(title.isFirstResponder)
        titleKeyboard.sendActions(for: .touchUpInside)
        try await waitForFocus(title)
        XCTAssertTrue(title.isFirstResponder, "Edit must reissue the keyboard request even if native Scribble already focused this field")
        XCTAssertEqual(title.text, "Typed draft")
        XCTAssertEqual(title.delegate?.textFieldShouldReturn?(title), false)
        try await waitForFocus(composer)
        XCTAssertTrue(composer.isFirstResponder)
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), true,
                           "Done and repeated keyboard actions cannot leave Scribble disabled")
        }
    }

    func testTextViewFocusRequestAndDoneKeepTextWithoutRestartingFocus() async throws {
        let model = TextViewModel()
        let host = UIHostingController(rootView: TextViewHarness(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let view = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextView }.first)
        XCTAssertFalse(view.isFirstResponder)
        let scribble = try XCTUnwrap(view.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), true)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: -1, y: 0)), false)
        model.focusRequest += 1
        for _ in 0..<20 where !view.isFirstResponder { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(view.isFirstResponder)
        view.text = "Verse\nKeep this exact text"
        view.delegate?.textViewDidChange?(view)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.text, "Verse\nKeep this exact text")
        model.focusRequest += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertEqual(view.text, "Verse\nKeep this exact text")
        let toolbar = try XCTUnwrap(view.inputAccessoryView as? UIToolbar)
        let done = try XCTUnwrap(toolbar.items?.first { $0.accessibilityLabel == "Done typing" })
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(done.action), to: done.target, from: done, for: nil))
        model.text += "!"
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(view.isFirstResponder, "A text update after Done cannot reopen the keyboard")
        XCTAssertEqual(view.text, "Verse\nKeep this exact text!")
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
    @Published var focusRequest = 0
}

private struct TextViewHarness: View {
    @ObservedObject var model: TextViewModel
    var body: some View {
        IChartTypedTextView(text: $model.text, keyboardFocusRequestID: model.focusRequest).frame(height: 100)
    }
}

@MainActor
private final class TextFieldModel: ObservableObject {
    @Published var text = ""
    @Published var focused = false
    @Published var focusRequest = 0
}

private struct TextFieldHarness: View {
    @ObservedObject var model: TextFieldModel
    var body: some View {
        IChartTypedTextField(placeholder: "Typed field", text: $model.text, isFocused: $model.focused,
                            keyboardFocusRequestID: model.focusRequest)
            .frame(height: 52)
    }
}
#endif
