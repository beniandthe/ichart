#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class NativeButtonTapFeedbackTests: XCTestCase {
    func testPressAndAcceptedActionsKeepButtonLayoutAndSelectedMeaning() async throws {
        let button = PencilOnlyUIButton(type: .system)
        button.frame = CGRect(x: 24, y: 40, width: 180, height: 44)
        button.configuration = .borderedProminent()
        button.usesRaisedToolFace = true
        button.setTitle("Add", for: .normal)
        button.accessibilityLabel = "Add cue"
        button.isSelected = true
        let probe = ActionProbe()
        button.addTarget(probe, action: #selector(ActionProbe.recordActivation), for: .touchUpInside)
        let window = mount(button)
        defer { close(window) }
        button.layoutIfNeeded()
        let frame = button.frame
        let bounds = button.bounds
        let labelFrame = button.titleLabel?.frame
        let traits = button.accessibilityTraits
        XCTAssertGreaterThan(button.layer.shadowOpacity, 0)
        let restShadowHeight = button.layer.shadowOffset.height

        button.isHighlighted = true
        XCTAssertLessThan(button.layer.shadowOffset.height, restShadowHeight)
        XCTAssertEqual(button.feedbackPhase, .pressed)
        XCTAssertEqual(probe.count, 0, "Press feedback cannot run the action early")
        button.isHighlighted = false
        XCTAssertEqual(button.feedbackPhase, .idle, "A cancelled press cannot pretend acceptance")
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(probe.count, 1)
        XCTAssertEqual(button.feedbackPhase, .accepted)
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(probe.count, 2, "Accessibility must dispatch the registered action exactly once")
        XCTAssertEqual(button.feedbackPhase, .accepted)
        button.layoutIfNeeded()
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(button.bounds, bounds)
        XCTAssertEqual(button.titleLabel?.frame, labelFrame)
        XCTAssertEqual(button.transform, .identity)
        XCTAssertTrue(button.isSelected)
        XCTAssertEqual(button.accessibilityLabel, "Add cue")
        XCTAssertEqual(button.accessibilityTraits, traits)
        let accent = try feedbackLayer("fill", in: button)
        let edge = try feedbackLayer("edge", in: button)
        XCTAssertFalse(accent.isHidden)
        XCTAssertGreaterThan(accent.opacity, 0)
        XCTAssertNotNil(accent.path)
        XCTAssertNotNil(edge.path, "A contrasting shape must supplement the color change")
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(button.feedbackPhase, .idle)
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(button.titleLabel?.frame, labelFrame)
    }

    func testDisabledNativeActionRejectsTouchAndAccessibilityWithoutFeedback() {
        let button = PencilOnlyUIButton(type: .system)
        button.usesRaisedToolFace = true
        let probe = ActionProbe()
        button.addTarget(probe, action: #selector(ActionProbe.recordActivation), for: .touchUpInside)
        button.isEnabled = false
        button.isHighlighted = true
        button.sendActions(for: .touchUpInside)
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(probe.count, 0)
        XCTAssertEqual(button.layer.shadowOpacity, 0)
        XCTAssertEqual(button.feedbackPhase, .idle)
        button.isHighlighted = false
        button.isEnabled = true
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(button.feedbackPhase, .accepted)
        button.isEnabled = false
        XCTAssertEqual(button.feedbackPhase, .idle, "A busy/disabled transition must remove acknowledgement immediately")
    }

    func testHigherContrastUsesStrongerOutlineWithoutResizingControl() throws {
        let button = HighContrastButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 140, height: 44)
        let frame = button.frame
        button.isHighlighted = true
        button.layoutIfNeeded()
        XCTAssertEqual(try feedbackLayer("fill", in: button).lineWidth, 3)
        XCTAssertEqual(try feedbackLayer("edge", in: button).lineWidth, 1.5)
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(button.transform, .identity)
    }

    func testKeyboardAndScribbleFeedbackUseTheirRealActionsWithoutRestartingInput() async throws {
        let view = IChartTypedUITextView(frame: CGRect(x: 20, y: 30, width: 380, height: 72), textContainer: nil)
        view.text = "Keep this cue"
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        view.inputAccessoryView = toolbar
        let window = mount(view)
        defer {
            view.exitScribble()
            close(window)
        }
        window.layoutIfNeeded()
        view.requestKeyboard()
        for _ in 0..<20 where !view.isFirstResponder { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(view.isFirstResponder)
        let editing = EditingProbe()
        view.delegate = editing
        let cursor = try XCTUnwrap(view.position(from: view.beginningOfDocument, offset: 4))
        view.selectedTextRange = view.textRange(from: cursor, to: cursor)
        let keyboard = try XCTUnwrap(view.keyboardModeButton as? IChartFeedbackUIButton)
        let scribble = try XCTUnwrap(view.scribbleModeButton as? IChartFeedbackUIButton)
        let viewFrame = view.frame
        let controlsFrame = view.inputModeControls.frame
        let textInsets = view.textContainerInset
        let accessory = view.inputAccessoryView

        keyboard.isHighlighted = true
        XCTAssertEqual(keyboard.feedbackPhase, .pressed)
        XCTAssertTrue(view.isFirstResponder)
        keyboard.isHighlighted = false
        keyboard.sendActions(for: .touchUpInside)
        XCTAssertEqual(keyboard.feedbackPhase, .accepted)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertTrue(scribble.accessibilityActivate())
        XCTAssertEqual(scribble.feedbackPhase, .accepted)
        XCTAssertTrue(view.isScribbleEnabled)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertTrue(keyboard.accessibilityActivate())
        XCTAssertFalse(view.isScribbleEnabled)
        XCTAssertTrue(view.isFirstResponder)
        XCTAssertEqual(view.text, "Keep this cue")
        XCTAssertEqual(view.offset(from: view.beginningOfDocument,
            to: try XCTUnwrap(view.selectedTextRange).start), 4)
        XCTAssertEqual(view.frame, viewFrame)
        XCTAssertEqual(view.inputModeControls.frame, controlsFrame)
        XCTAssertEqual(view.textContainerInset, textInsets)
        XCTAssertTrue(view.inputAccessoryView === accessory)
        XCTAssertEqual(editing.began, 0)
        XCTAssertEqual(editing.ended, 0, "Visual feedback must not restart the native editing session")
    }

    private func feedbackLayer(_ suffix: String, in button: UIButton) throws -> CAShapeLayer {
        try XCTUnwrap(button.layer.sublayers?.first { $0.name == "iChart.button-feedback.\(suffix)" } as? CAShapeLayer)
    }

    private func mount(_ view: UIView) -> UIWindow {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1_180))
        host.view.addSubview(view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    private func close(_ window: UIWindow) {
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
    }

    private final class ActionProbe: NSObject {
        var count = 0
        @objc func recordActivation() { count += 1 }
    }

    private final class EditingProbe: NSObject, UITextViewDelegate {
        var began = 0
        var ended = 0
        func textViewDidBeginEditing(_ textView: UITextView) { began += 1 }
        func textViewDidEndEditing(_ textView: UITextView) { ended += 1 }
    }

    private final class HighContrastButton: IChartFeedbackUIButton {
        override var traitCollection: UITraitCollection {
            UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(accessibilityContrast: .high)])
        }
    }
}
#endif
