#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class TypedTextInputTests: XCTestCase {
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
        let root = ChartHeaderSheetView(chart: Binding(get: { chart }, set: { chart = $0 }))
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let fields = descendants(host.view).compactMap { $0 as? IChartTypedUITextField }
        let title = try XCTUnwrap(fields.first { $0.placeholder == "Title" })
        let composer = try XCTUnwrap(fields.first { $0.placeholder == "Composer / Credit" })
        let style = try XCTUnwrap(fields.first { $0.placeholder == "Style Note" })
        XCTAssertEqual(fields.count, 3)
        XCTAssertTrue(fields.allSatisfy { !$0.isFirstResponder })
        for field in fields {
            let scribble = try XCTUnwrap(field.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
            XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), false)
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
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: .zero), false)
        model.focusRequest += 1
        for _ in 0..<20 where !view.isFirstResponder { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(view.isFirstResponder)
        view.text = "Verse\nKeep this exact text"
        view.delegate?.textViewDidChange?(view)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.text, "Verse\nKeep this exact text")
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
    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
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
}

private struct TextFieldHarness: View {
    @ObservedObject var model: TextFieldModel
    var body: some View {
        IChartTypedTextField(placeholder: "Typed field", text: $model.text, isFocused: $model.focused)
            .frame(height: 52)
    }
}
#endif
