import SwiftUI
import UIKit

/// Native text entry uses a field tap for typing and a field-local Scribble action.
struct IChartTypedTextField: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let placeholder: String
    @Binding var text: String
    var isFocused: Binding<Bool>? = nil
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textAlignment: NSTextAlignment = .natural
    var borderStyle: UITextField.BorderStyle = .roundedRect
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType? = nil
    var textColor: UIColor = .label
    var placeholderColor: UIColor? = nil
    var tintColor: UIColor? = nil
    var accessibilityIdentifier: String? = nil
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil
    var onKeyboardRequested: (() -> Void)?
    var onNext: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeUIView(context: Context) -> IChartTypedUITextField {
        let field = IChartTypedUITextField()
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        if let placeholderColor {
            field.attributedPlaceholder = NSAttributedString(string: placeholder,
                attributes: [.foregroundColor: placeholderColor])
        } else {
            field.placeholder = placeholder
        }
        field.autocapitalizationType = autocapitalizationType
        field.autocorrectionType = autocorrectionType
        field.font = font
        field.textAlignment = textAlignment
        field.borderStyle = borderStyle
        if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
        if !isEnabled { field.exitScribble() }
        field.keyboardType = keyboardType
        field.returnKeyType = returnKeyType ?? (onNext == nil ? .done : .next)
        field.textColor = textColor
        field.tintColor = tintColor
        field.accessibilityIdentifier = accessibilityIdentifier
        field.accessibilityLabel = accessibilityLabel
        field.accessibilityHint = accessibilityHint
        if field.markedTextRange == nil, field.text != text { field.text = text }
        field.onKeyboardRequested = onKeyboardRequested
        field.setInputName(accessibilityLabel ?? placeholder)
        guard let isFocused else { return }
        field.requestsFocus = isEnabled && isFocused.wrappedValue
        guard field.requestsFocus != field.isFirstResponder else { return }
        // Wait until UIKit has applied the complete sibling focus update. A
        // previous row must not resign a newly requested row's first responder.
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            if field.requestsFocus, field.window != nil {
                if !field.isFirstResponder { field.requestKeyboard() }
            } else if !field.requestsFocus, field.isFirstResponder {
                DispatchQueue.main.async { [weak field] in
                    guard let field, !field.requestsFocus, field.isFirstResponder else { return }
                    _ = field.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    static func dismantleUIView(_ field: IChartTypedUITextField, coordinator: Coordinator) {
        field.requestsFocus = false
        field.exitScribble()
        _ = field.resignFirstResponder()
        IChartKeyboardInputContext.finish(for: field)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: IChartTypedTextField
        private weak var activeField: UITextField?

        init(parent: IChartTypedTextField) { self.parent = parent }

        @objc func textDidChange(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            activeField = textField
            (textField as? IChartTypedUITextField)?.didBeginInput()
            (textField as? IChartTypedUITextField)?.requestsFocus = true
            parent.isFocused?.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            (textField as? IChartTypedUITextField)?.requestsFocus = false
            (textField as? IChartTypedUITextField)?.exitScribble()
            IChartKeyboardInputContext.finish(for: textField)
            parent.isFocused?.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let onNext = parent.onNext {
                onNext()
            } else if let onSubmit = parent.onSubmit {
                onSubmit()
            } else {
                doneTyping()
            }
            return false
        }

        @objc func nextField() { parent.onNext?() }

        @objc func doneTyping() {
            (activeField as? IChartTypedUITextField)?.requestsFocus = false
            (activeField as? IChartTypedUITextField)?.exitScribble()
            activeField?.resignFirstResponder()
            parent.isFocused?.wrappedValue = false
        }
    }
}

struct IChartTypedTextView: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    var placeholder: String? = nil
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var autocorrectionType: UITextAutocorrectionType = .yes
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var placeholderColor: UIColor = .placeholderText
    var tintColor: UIColor? = nil
    var accessibilityIdentifier: String? = nil
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil

    func makeUIView(context: Context) -> IChartTypedUITextView {
        let view = IChartTypedUITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 49)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.keyboardDismissMode = .interactive
        view.inputAccessoryView = IChartTypingAccessory.make(target: context.coordinator,
            next: nil, done: #selector(Coordinator.doneTyping))
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: IChartTypedUITextView, context: Context) {
        context.coordinator.parent = self
        if view.isEditable != isEnabled { view.isEditable = isEnabled }
        if !isEnabled { view.exitScribble() }
        view.font = font
        view.autocapitalizationType = autocapitalizationType
        view.autocorrectionType = autocorrectionType
        view.textColor = textColor
        view.tintColor = tintColor
        view.accessibilityIdentifier = accessibilityIdentifier
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityHint = accessibilityHint
        view.setInputName(accessibilityLabel ?? placeholder ?? "text")
        if view.markedTextRange == nil, view.text != text { view.text = text }
        view.setPlaceholder(placeholder, color: placeholderColor)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    static func dismantleUIView(_ view: IChartTypedUITextView, coordinator: Coordinator) {
        view.exitScribble()
        _ = view.resignFirstResponder()
        IChartKeyboardInputContext.finish(for: view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IChartTypedTextView
        weak var textView: IChartTypedUITextView?

        init(parent: IChartTypedTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            (textView as? IChartTypedUITextView)?.updatePlaceholderVisibility()
            parent.text = textView.text
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            (textView as? IChartTypedUITextView)?.didBeginInput()
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? IChartTypedUITextView)?.exitScribble()
            IChartKeyboardInputContext.finish(for: textView)
        }
        @objc func doneTyping() {
            textView?.exitScribble()
            _ = textView?.resignFirstResponder()
        }
    }
}

final class IChartTypedUITextField: UITextField, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    var requestsFocus = false
    var onKeyboardRequested: (() -> Void)?
    private let inputMode = IChartTextInputMode()
    var inputModeButton: UIButton { inputMode.button }
    var isScribbleEnabled: Bool { inputMode.isScribbleEnabled }
    private lazy var keyboardTap = IChartNativeKeyboardFocus.makeTap(target: self,
        action: #selector(directTap(_:)), delegate: self)

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
        rightView = inputModeButton
        rightViewMode = .always
        inputModeButton.addTarget(self, action: #selector(toggleInputMode), for: .touchUpInside)
        addGestureRecognizer(keyboardTap)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus, !isFirstResponder { requestKeyboard() }
        if window == nil {
            exitScribble()
            IChartKeyboardInputContext.finish(for: self)
        }
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { IChartKeyboardInputContext.finish(for: self) }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        isScribbleEnabled && isEnabled && isUserInteractionEnabled && bounds.contains(location)
            && !rightViewRect(forBounds: bounds).contains(location)
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        if isScribbleEnabled { IChartKeyboardInputContext.handwritingBegan(in: self) }
    }
    func setInputName(_ name: String) { inputMode.setName(name) }
    func didBeginInput() { inputMode.dismissOtherScribble() }
    func exitScribble() { inputMode.exitScribble() }
    func requestKeyboard(at point: CGPoint? = nil) {
        guard isEnabled, isUserInteractionEnabled else { return }
        inputMode.dismissOtherScribble()
        exitScribble()
        IChartNativeKeyboardFocus.request(self, at: point)
        if isFirstResponder { onKeyboardRequested?() }
    }
    @objc private func toggleInputMode() {
        guard isEnabled, isUserInteractionEnabled else { return }
        if isScribbleEnabled { requestKeyboard() } else { inputMode.armScribble(in: self) }
    }
    @objc private func directTap(_ recognizer: UITapGestureRecognizer) {
        requestKeyboard(at: recognizer.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isEnabled && inputMode.allowsTypingTap(touch.type)
            && !rightViewRect(forBounds: bounds).contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === keyboardTap || otherGestureRecognizer === keyboardTap
    }
}

final class IChartTypedUITextView: UITextView, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    private let inputMode = IChartTextInputMode()
    var inputModeButton: UIButton { inputMode.button }
    var isScribbleEnabled: Bool { inputMode.isScribbleEnabled }
    private let placeholderLabel = UILabel()
    private lazy var keyboardTap = IChartNativeKeyboardFocus.makeTap(target: self,
        action: #selector(directTap(_:)), delegate: self)

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
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isHidden = true
        addSubview(placeholderLabel)
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        panGestureRecognizer.allowedTouchTypes.removeAll { $0 == pencil }
        inputModeButton.addTarget(self, action: #selector(toggleInputMode), for: .touchUpInside)
        addSubview(inputModeButton)
        addGestureRecognizer(keyboardTap)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        if !placeholderLabel.isHidden {
            let width = max(0, bounds.width - inset.left - inset.right)
            let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: size.height)
        }
        inputModeButton.frame = inputModeButtonFrame
        inputModeButton.isEnabled = isEditable
    }
    func setPlaceholder(_ placeholder: String?, color: UIColor) {
        guard placeholderLabel.text != placeholder || placeholderLabel.textColor != color
                || placeholderLabel.font != font else {
            updatePlaceholderVisibility()
            return
        }
        placeholderLabel.text = placeholder
        placeholderLabel.textColor = color
        placeholderLabel.font = font
        updatePlaceholderVisibility()
        setNeedsLayout()
    }
    func updatePlaceholderVisibility() {
        let hidden = placeholderLabel.text?.isEmpty != false || !text.isEmpty
        if placeholderLabel.isHidden != hidden {
            placeholderLabel.isHidden = hidden
            if !hidden { setNeedsLayout() }
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            exitScribble()
            IChartKeyboardInputContext.finish(for: self)
        }
    }
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { IChartKeyboardInputContext.finish(for: self) }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        isScribbleEnabled && isEditable && isUserInteractionEnabled && bounds.contains(location)
            && !inputModeButtonFrame.contains(location)
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        if isScribbleEnabled { IChartKeyboardInputContext.handwritingBegan(in: self) }
    }
    private var inputModeButtonFrame: CGRect {
        CGRect(x: bounds.maxX - 44, y: bounds.minY, width: 44, height: 44)
    }
    func setInputName(_ name: String) { inputMode.setName(name) }
    func didBeginInput() { inputMode.dismissOtherScribble() }
    func exitScribble() { inputMode.exitScribble() }
    func requestKeyboard(at point: CGPoint? = nil) {
        guard isEditable, isUserInteractionEnabled else { return }
        inputMode.dismissOtherScribble()
        exitScribble()
        IChartNativeKeyboardFocus.request(self, at: point)
    }
    @objc private func toggleInputMode() {
        guard isEditable, isUserInteractionEnabled else { return }
        if isScribbleEnabled { requestKeyboard() } else { inputMode.armScribble(in: self) }
    }
    @objc private func directTap(_ recognizer: UITapGestureRecognizer) {
        requestKeyboard(at: recognizer.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isEditable && inputMode.allowsTypingTap(touch.type)
            && !inputModeButtonFrame.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === keyboardTap || otherGestureRecognizer === keyboardTap
    }
}

/// A single accessory slot keeps the input and its controls in place. An armed
/// field owns Scribble until the user chooses typing or another field takes over.
@MainActor
private final class IChartTextInputMode {
    private static weak var scribbleOwner: IChartTextInputMode?
    let button = IChartInputModeButton(type: .system)
    private var name = "text"

    var isScribbleEnabled: Bool { Self.scribbleOwner === self }

    init() {
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        updateButton()
    }

    func setName(_ name: String) {
        guard self.name != name else { return }
        self.name = name
        updateButton()
    }

    func allowsTypingTap(_ touchType: UITouch.TouchType) -> Bool {
        touchType != .pencil || !isScribbleEnabled
    }

    func armScribble(in input: UIView) {
        if input.isFirstResponder {
            guard input.resignFirstResponder() else { return }
        } else {
            input.window?.endEditing(false)
        }
        dismissOtherScribble()
        Self.scribbleOwner = self
        updateButton()
    }

    func dismissOtherScribble() {
        if !isScribbleEnabled { Self.scribbleOwner?.exitScribble() }
    }

    func exitScribble() {
        guard isScribbleEnabled else { return }
        Self.scribbleOwner = nil
        updateButton()
    }

    private func updateButton() {
        let isWriting = isScribbleEnabled
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: isWriting ? "keyboard" : "pencil.and.scribble")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        button.configuration = configuration
        button.accessibilityLabel = isWriting ? "Use keyboard for \(name)" : "Start Scribble for \(name)"
        button.accessibilityHint = isWriting ? nil : "Then write in this field with Apple Pencil."
        button.accessibilityValue = isWriting ? "Scribble on" : nil
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

    @discardableResult
    static func begin(for input: UIView) -> Bool {
        guard input is IChartTypedUITextField || input is IChartTypedUITextView else { return false }
        guard let current = UITextInputContext.current() else { return false }
        if owner == nil || context !== current {
            restore()
            originalPencilInputExpected = current.isPencilInputExpected
            context = current
        }
        owner = input
        guard current.isPencilInputExpected else { return false }
        current.isPencilInputExpected = false
        return true
    }

    static func finish(for input: UIView) {
        guard owner === input else { return }
        restore()
    }

    static func handwritingBegan(in input: UIView) {
        guard input is IChartTypedUITextField || input is IChartTypedUITextView else { return }
        // A new owned Scribble start may arrive before the previous sibling's
        // end-edit callback. Relinquish that keyboard lease immediately.
        let current = UITextInputContext.current()
        if context === current {
            clearOwner()
        } else {
            restore()
        }
        if let current, !current.isPencilInputExpected { current.isPencilInputExpected = true }
    }

    private static func restore() {
        if let context, originalPencilInputExpected == true, !context.isPencilInputExpected {
            context.isPencilInputExpected = true
        }
        clearOwner()
    }

    private static func clearOwner() {
        owner = nil
        context = nil
        originalPencilInputExpected = nil
    }
}

@MainActor
private enum IChartNativeKeyboardFocus {
    static func request(_ input: UIView & UITextInput, at point: CGPoint? = nil) {
        let wasFocused = input.isFirstResponder
        let selection = input.selectedTextRange
        let changesInputMode = IChartKeyboardInputContext.begin(for: input)
        // Keep an active editing session intact. Reload only when an existing
        // Scribble responder actually needs to switch to keyboard input.
        if input.isFirstResponder {
            if changesInputMode { input.reloadInputViews() }
        } else if !input.becomeFirstResponder() {
            IChartKeyboardInputContext.finish(for: input)
            return
        }
        if !wasFocused, input.markedTextRange == nil, let point, let position = input.closestPosition(to: point) {
            input.selectedTextRange = input.textRange(from: position, to: position)
        } else if changesInputMode, input.markedTextRange == nil, let selection {
            input.selectedTextRange = selection
        }
    }
    static func makeTap(target: AnyObject, action: Selector, delegate: UIGestureRecognizerDelegate) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer(target: target, action: action)
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                 NSNumber(value: UITouch.TouchType.pencil.rawValue),
                                 NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        tap.cancelsTouchesInView = false
        tap.delegate = delegate
        return tap
    }
}

/// UITextField sizes its right view from sizeThatFits, not its initial frame.
/// Keep the embedded action's actual target at least 44 points in both axes.
private final class IChartInputModeButton: UIButton {
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
    func makeUIView(context: Context) -> ScrollMarker {
        ScrollMarker()
    }
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
