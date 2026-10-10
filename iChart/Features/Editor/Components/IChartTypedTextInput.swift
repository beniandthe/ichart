import SwiftUI
import UIKit

/// Native text entry lets Scribble start within the control and keyboard editing
/// on request. Chart ink and outside-field Pencil scrolling remain separate.
struct IChartTypedTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textAlignment: NSTextAlignment = .natural
    var borderStyle: UITextField.BorderStyle = .roundedRect
    var onKeyboardRequested: (() -> Void)?
    var onNext: (() -> Void)?

    func makeUIView(context: Context) -> IChartTypedUITextField {
        let field = IChartTypedUITextField()
        field.delegate = context.coordinator
        field.clearButtonMode = .never
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
        field.onKeyboardRequested = onKeyboardRequested
        field.keyboardButton.accessibilityLabel = "Use keyboard for \(placeholder)"
        // Wait until UIKit has applied the complete sibling focus update. A
        // previous row must not resign a newly requested row's first responder.
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            if field.requestsFocus, field.window != nil {
                if !field.isFirstResponder { IChartNativeKeyboardFocus.request(field) }
            } else if !field.requestsFocus, field.isFirstResponder {
                DispatchQueue.main.async { [weak field] in
                    guard let field, !field.requestsFocus, field.isFirstResponder else { return }
                    field.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    static func dismantleUIView(_ field: IChartTypedUITextField, coordinator: Coordinator) {
        field.requestsFocus = false
        field.resignFirstResponder()
        IChartKeyboardInputContext.finish(for: field)
    }

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
            IChartKeyboardInputContext.finish(for: textField)
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
        view.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 49)
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
            guard let view, view.requestsFocus, view.window != nil else { return }
            IChartNativeKeyboardFocus.request(view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    static func dismantleUIView(_ view: IChartTypedUITextView, coordinator: Coordinator) {
        view.requestsFocus = false
        view.resignFirstResponder()
        IChartKeyboardInputContext.finish(for: view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IChartTypedTextView
        var lastKeyboardFocusRequestID = 0
        weak var textView: IChartTypedUITextView?

        init(parent: IChartTypedTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? IChartTypedUITextView)?.requestsFocus = false
            IChartKeyboardInputContext.finish(for: textView)
        }
        @objc func doneTyping() {
            textView?.requestsFocus = false
            textView?.resignFirstResponder()
        }
    }
}

final class IChartTypedUITextField: UITextField, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    var requestsFocus = false
    var onKeyboardRequested: (() -> Void)?
    let keyboardButton = IChartNativeKeyboardFocus.makeButton()
    private lazy var keyboardTap = IChartNativeKeyboardFocus.makeTap(target: self,
        action: #selector(directTap), delegate: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        installInputControls()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installInputControls()
    }
    override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: max(0, bounds.width - 48), y: max(0, (bounds.height - 44) / 2), width: 44, height: 44)
    }
    private func installInputControls() {
        addInteraction(UIScribbleInteraction(delegate: self))
        rightView = keyboardButton
        rightViewMode = .always
        keyboardButton.addTarget(self, action: #selector(openKeyboard), for: .touchUpInside)
        addGestureRecognizer(keyboardTap)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus, !isFirstResponder { IChartNativeKeyboardFocus.request(self) }
        if window == nil { IChartKeyboardInputContext.finish(for: self) }
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { IChartKeyboardInputContext.finish(for: self) }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        guard isEnabled, isUserInteractionEnabled, bounds.contains(location),
              !rightViewRect(forBounds: bounds).contains(location) else { return false }
        IChartKeyboardInputContext.handwritingBegan(in: self)
        return true
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        IChartKeyboardInputContext.handwritingBegan(in: self)
    }
    @objc private func openKeyboard() {
        guard isEnabled, isUserInteractionEnabled else { return }
        IChartNativeKeyboardFocus.request(self)
        onKeyboardRequested?()
    }
    @objc private func directTap() { IChartNativeKeyboardFocus.request(self, restarting: false) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !keyboardButton.frame.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === keyboardTap || otherGestureRecognizer === keyboardTap
    }
}

final class IChartTypedUITextView: UITextView, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    var requestsFocus = false
    let keyboardButton = IChartNativeKeyboardFocus.makeButton()
    private lazy var keyboardTap = IChartNativeKeyboardFocus.makeTap(target: self,
        action: #selector(directTap), delegate: self)

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        installInputControls()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installInputControls()
    }
    private func installInputControls() {
        addInteraction(UIScribbleInteraction(delegate: self))
        keyboardButton.accessibilityLabel = "Use keyboard for text"
        keyboardButton.addTarget(self, action: #selector(openKeyboard), for: .touchUpInside)
        addSubview(keyboardButton)
        addGestureRecognizer(keyboardTap)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        keyboardButton.frame = CGRect(x: bounds.maxX - 44, y: bounds.minY, width: 44, height: 44)
        keyboardButton.isEnabled = isEditable
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus, !isFirstResponder { IChartNativeKeyboardFocus.request(self) }
        if window == nil { IChartKeyboardInputContext.finish(for: self) }
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { IChartKeyboardInputContext.finish(for: self) }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        let keyboardFrame = CGRect(x: bounds.maxX - 44, y: bounds.minY, width: 44, height: 44)
        guard isEditable, isUserInteractionEnabled, bounds.contains(location),
              !keyboardFrame.contains(location) else { return false }
        IChartKeyboardInputContext.handwritingBegan(in: self)
        return true
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        IChartKeyboardInputContext.handwritingBegan(in: self)
    }
    @objc private func openKeyboard() {
        guard isEditable, isUserInteractionEnabled else { return }
        IChartNativeKeyboardFocus.request(self)
    }
    @objc private func directTap() { IChartNativeKeyboardFocus.request(self, restarting: false) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !keyboardButton.frame.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === keyboardTap || otherGestureRecognizer === keyboardTap
    }
}

/// Scope the shared expected-input hint to the owned native text control. A new
/// field takes ownership before UIKit resigns its sibling, so the sibling's
/// end-edit callback cannot restore Pencil intent over the keyboard request.
@MainActor
enum IChartKeyboardInputContext {
    private static weak var owner: UIView?
    private static var originalPencilInputExpected: Bool?
    private static var context: UITextInputContext?

    static func begin(for input: UIView) {
        guard input is IChartTypedUITextField || input is IChartTypedUITextView else { return }
        guard let current = UITextInputContext.current() else { return }
        if owner == nil {
            restore()
            originalPencilInputExpected = current.isPencilInputExpected
            context = current
        }
        owner = input
        current.isPencilInputExpected = false
    }

    static func finish(for input: UIView) {
        guard owner === input else { return }
        restore()
    }

    static func handwritingBegan(in input: UIView) {
        guard input is IChartTypedUITextField || input is IChartTypedUITextView else { return }
        // A new owned Scribble start may arrive before the previous sibling's
        // end-edit callback. Relinquish that keyboard lease immediately.
        restore()
        UITextInputContext.current()?.isPencilInputExpected = true
    }

    private static func restore() {
        if let context, let originalPencilInputExpected, !context.isPencilInputExpected {
            context.isPencilInputExpected = originalPencilInputExpected
        }
        owner = nil
        context = nil
        originalPencilInputExpected = nil
    }
}

@MainActor
private enum IChartNativeKeyboardFocus {
    static func request(_ input: UIView & UITextInput, restarting: Bool = true) {
        let selection = input.selectedTextRange
        if restarting, input.isFirstResponder { input.resignFirstResponder() }
        IChartKeyboardInputContext.begin(for: input)
        if input.isFirstResponder { input.reloadInputViews() }
        else if !input.becomeFirstResponder() { IChartKeyboardInputContext.finish(for: input) }
        if let selection { input.selectedTextRange = selection }
    }
    static func makeButton() -> UIButton {
        let button = IChartInputKeyboardButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "keyboard")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        button.configuration = configuration
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        return button
    }
    static func makeTap(target: AnyObject, action: Selector, delegate: UIGestureRecognizerDelegate) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer(target: target, action: action)
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                 NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        tap.cancelsTouchesInView = false
        tap.delegate = delegate
        return tap
    }
}

/// UITextField sizes its right view from sizeThatFits, not its initial frame.
/// Keep the embedded action's actual target at least 44 points in both axes.
private final class IChartInputKeyboardButton: UIButton {
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
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

/// Finger scrolling uses UIKit's native pan. A separate Pencil pan starts only
/// outside owned text controls so it cannot compete with field-bound Scribble.
struct IChartTypedSheetScrollSupport: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollMarker { ScrollMarker() }
    func updateUIView(_ view: ScrollMarker, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.configureScrollView() }
    }
    static func dismantleUIView(_ view: ScrollMarker, coordinator: ()) { view.detachScrollView() }

    final class ScrollMarker: UIView, UIGestureRecognizerDelegate {
        private weak var scrollView: UIScrollView?
        private var originalPanTouchTypes: [NSNumber]?
        private var startingOffset = CGPoint.zero
        private lazy var pencilPan: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(scrollWithPencil(_:)))
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            gesture.maximumNumberOfTouches = 1
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detachScrollView() } else { configureScrollView() }
        }

        func configureScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    guard self.scrollView !== scrollView else {
                        pencilPan.isEnabled = scrollView.isScrollEnabled
                        return
                    }
                    detachScrollView()
                    self.scrollView = scrollView
                    originalPanTouchTypes = scrollView.panGestureRecognizer.allowedTouchTypes
                    let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
                    scrollView.panGestureRecognizer.allowedTouchTypes = scrollView.panGestureRecognizer.allowedTouchTypes
                        .filter { $0 != pencil }
                    scrollView.addGestureRecognizer(pencilPan)
                    pencilPan.isEnabled = scrollView.isScrollEnabled
                    return
                }
                ancestor = view.superview
            }
        }

        func detachScrollView() {
            if let scrollView {
                scrollView.removeGestureRecognizer(pencilPan)
                if let originalPanTouchTypes { scrollView.panGestureRecognizer.allowedTouchTypes = originalPanTouchTypes }
            }
            scrollView = nil
            originalPanTouchTypes = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === pencilPan, let scrollView else { return false }
            return Self.allowsPencilScroll(at: touch.location(in: scrollView), in: scrollView)
        }

        static func allowsPencilScroll(at point: CGPoint, in scrollView: UIScrollView) -> Bool {
            guard scrollView.isScrollEnabled, scrollView.bounds.contains(point) else { return false }
            return !containsOwnedTextControl(at: point, in: scrollView, coordinateView: scrollView)
        }

        private static func containsOwnedTextControl(at point: CGPoint, in view: UIView, coordinateView: UIView) -> Bool {
            guard !view.isHidden, view.alpha > 0.01, view.isUserInteractionEnabled else { return false }
            if view is IChartTypedUITextField || view is IChartTypedUITextView {
                return view.bounds.contains(view.convert(point, from: coordinateView))
            }
            return view.subviews.contains { containsOwnedTextControl(at: point, in: $0, coordinateView: coordinateView) }
        }

        @objc private func scrollWithPencil(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            guard scrollView.isScrollEnabled else {
                gesture.isEnabled = false
                return
            }
            switch gesture.state {
            case .began:
                startingOffset = scrollView.contentOffset
            case .changed:
                let translation = gesture.translation(in: scrollView)
                let inset = scrollView.adjustedContentInset
                let maximumY = max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
                let y = min(maximumY, max(-inset.top, startingOffset.y - translation.y))
                scrollView.setContentOffset(CGPoint(x: startingOffset.x, y: y), animated: false)
            default:
                break
            }
        }
    }
}
