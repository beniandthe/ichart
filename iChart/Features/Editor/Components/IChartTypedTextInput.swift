import SwiftUI
import UIKit

/// Text entry is deliberately separate from chart ink. Keeping Scribble out of
/// these controls lets a Pencil drag in a review sheet remain a scroll gesture.
struct IChartTypedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textAlignment: NSTextAlignment = .natural
    var borderStyle: UITextField.BorderStyle = .roundedRect
    var onNext: (() -> Void)?

    func makeUIView(context: Context) -> IChartTypedUITextField {
        let field = IChartTypedUITextField()
        field.delegate = context.coordinator
        field.clearButtonMode = .whileEditing
        field.adjustsFontForContentSizeCategory = true
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        field.inputAccessoryView = IChartTypingAccessory.make(target: context.coordinator,
            next: onNext == nil ? nil : #selector(Coordinator.nextField), done: #selector(Coordinator.doneTyping))
        return field
    }

    func updateUIView(_ field: IChartTypedUITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.autocapitalizationType = autocapitalizationType
        field.autocorrectionType = autocorrectionType
        field.font = font
        field.textAlignment = textAlignment
        field.borderStyle = borderStyle
        field.returnKeyType = onNext == nil ? .done : .next
        if field.text != text { field.text = text }
        field.requestsFocus = isFocused
        // Wait until UIKit has applied the complete sibling focus update. A
        // previous row must not resign a newly requested row's first responder.
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            if field.requestsFocus, field.window != nil, !field.isFirstResponder {
                field.becomeFirstResponder()
            } else if !field.requestsFocus, field.isFirstResponder {
                DispatchQueue.main.async { [weak field] in
                    guard let field, !field.requestsFocus, field.isFirstResponder else { return }
                    field.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: IChartTypedTextField
        private weak var activeField: UITextField?

        init(parent: IChartTypedTextField) { self.parent = parent }

        @objc func textDidChange(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            activeField = textField
            (textField as? IChartTypedUITextField)?.requestsFocus = true
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            (textField as? IChartTypedUITextField)?.requestsFocus = false
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let onNext = parent.onNext { onNext() } else { doneTyping() }
            return false
        }

        @objc func nextField() { parent.onNext?() }

        @objc func doneTyping() {
            (activeField as? IChartTypedUITextField)?.requestsFocus = false
            activeField?.resignFirstResponder()
            parent.isFocused = false
        }
    }
}

struct IChartTypedTextView: UIViewRepresentable {
    @Binding var text: String
    let keyboardFocusRequestID: Int

    func makeUIView(context: Context) -> IChartTypedUITextView {
        let view = IChartTypedUITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.autocorrectionType = .yes
        view.isScrollEnabled = true
        view.keyboardDismissMode = .interactive
        view.inputAccessoryView = IChartTypingAccessory.make(target: context.coordinator,
            next: nil, done: #selector(Coordinator.doneTyping))
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: IChartTypedUITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        guard keyboardFocusRequestID > 0,
              context.coordinator.lastKeyboardFocusRequestID != keyboardFocusRequestID else { return }
        context.coordinator.lastKeyboardFocusRequestID = keyboardFocusRequestID
        view.requestsFocus = true
        DispatchQueue.main.async { [weak view] in
            guard let view, view.requestsFocus, view.window != nil, !view.isFirstResponder else { return }
            view.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IChartTypedTextView
        var lastKeyboardFocusRequestID = 0
        weak var textView: IChartTypedUITextView?

        init(parent: IChartTypedTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? IChartTypedUITextView)?.requestsFocus = false
        }
        @objc func doneTyping() {
            textView?.requestsFocus = false
            textView?.resignFirstResponder()
        }
    }
}

final class IChartTypedUITextField: UITextField, UIScribbleInteractionDelegate {
    var requestsFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addInteraction(UIScribbleInteraction(delegate: self))
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addInteraction(UIScribbleInteraction(delegate: self))
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus { becomeFirstResponder() }
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool { false }
}

final class IChartTypedUITextView: UITextView, UIScribbleInteractionDelegate {
    var requestsFocus = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addInteraction(UIScribbleInteraction(delegate: self))
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addInteraction(UIScribbleInteraction(delegate: self))
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus { becomeFirstResponder() }
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool { false }
}

private enum IChartTypingAccessory {
    static func make(target: AnyObject, next: Selector?, done: Selector) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        var items: [UIBarButtonItem] = []
        if let next {
            let button = UIBarButtonItem(title: "Next", style: .plain, target: target, action: next)
            button.accessibilityLabel = "Next field"
            items.append(button)
        }
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: target, action: done)
        doneButton.accessibilityLabel = "Done typing"
        items.append(doneButton)
        toolbar.items = items
        return toolbar
    }
}

/// Scope Pencil scrolling to a typed sheet's own scroll view. The chart canvas
/// keeps its independent drawing and finger-navigation policy.
struct IChartTypedSheetScrollSupport: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollMarker { ScrollMarker() }
    func updateUIView(_ view: ScrollMarker, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.configureScrollView() }
    }

    final class ScrollMarker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureScrollView()
        }

        func configureScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    var touchTypes = scrollView.panGestureRecognizer.allowedTouchTypes
                    let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
                    if !touchTypes.contains(pencil) { touchTypes.append(pencil) }
                    scrollView.panGestureRecognizer.allowedTouchTypes = touchTypes
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
