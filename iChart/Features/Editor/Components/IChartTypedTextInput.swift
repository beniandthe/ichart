import SwiftUI
import UIKit

/// A native text field with a stable pair of Keyboard and Scribble controls.
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
                if !field.isFirstResponder { field.requestSelectedInputMode() }
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

final class IChartTypedUITextField: UITextField, IChartNativeTextInput, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    var requestsFocus = false
    var onKeyboardRequested: (() -> Void)?
    private let inputMode = IChartTextInputMode()
    var inputModeControls: UIView { inputMode.controls }
    var keyboardModeButton: UIButton { inputMode.keyboardButton }
    var scribbleModeButton: UIButton { inputMode.scribbleButton }
    var isScribbleEnabled: Bool { inputMode.isScribbleEnabled }
    var isScribblePrepared: Bool { inputMode.isScribblePrepared && isFirstResponder }
    private lazy var inputTap = IChartNativeKeyboardFocus.makeTap(target: self,
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
        let size = inputMode.controls.intrinsicContentSize
        return CGRect(x: max(0, bounds.maxX - size.width - 4), y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
    }
    private func installInputControls() {
        addInteraction(UIScribbleInteraction(delegate: self))
        rightView = inputMode.controls
        rightViewMode = .always
        inputMode.keyboardButton.addTarget(self, action: #selector(selectKeyboard), for: .touchUpInside)
        inputMode.scribbleButton.addTarget(self, action: #selector(selectScribble), for: .touchUpInside)
        addGestureRecognizer(inputTap)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, requestsFocus, !isFirstResponder { requestSelectedInputMode() }
        if window == nil {
            exitScribble()
            IChartKeyboardInputContext.finish(for: self)
        }
    }
    override func resignFirstResponder() -> Bool {
        inputMode.rememberSelection(in: self)
        let resigned = super.resignFirstResponder()
        if resigned {
            exitScribble()
            IChartKeyboardInputContext.finish(for: self)
        }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        isScribblePrepared && isEnabled && isUserInteractionEnabled && bounds.contains(location)
            && !rightViewRect(forBounds: bounds).contains(location)
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        if isScribblePrepared { IChartKeyboardInputContext.handwritingBegan(in: self) }
    }
    func setInputName(_ name: String) { inputMode.setName(name) }
    func didBeginInput() { inputMode.didBegin(in: self) }
    func exitScribble() { inputMode.exitScribble() }
    func requestSelectedInputMode() {
        if isScribbleEnabled { prepareScribble() } else { requestKeyboard() }
    }
    func requestKeyboard(at point: CGPoint? = nil) {
        guard isEnabled, isUserInteractionEnabled else { return }
        inputMode.requestKeyboard(in: self, at: point)
        if isFirstResponder { onKeyboardRequested?() }
    }
    func prepareScribble(at point: CGPoint? = nil) {
        guard isEnabled, isUserInteractionEnabled else { return }
        inputMode.prepareScribble(in: self, at: point)
    }
    @objc private func selectKeyboard() { requestKeyboard() }
    @objc private func selectScribble() {
        guard isEnabled, isUserInteractionEnabled else { return }
        inputMode.armScribble(in: self)
    }
    @objc private func directTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if isScribbleEnabled {
            // Finish routing the initiating touch before admitting Pencil ink.
            DispatchQueue.main.async { [weak self] in self?.prepareScribble(at: point) }
        } else {
            requestKeyboard(at: point)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isEnabled && inputMode.allowsBodyTap(touch.type)
            && !rightViewRect(forBounds: bounds).contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === inputTap || otherGestureRecognizer === inputTap
    }
}

final class IChartTypedUITextView: UITextView, IChartNativeTextInput, UIScribbleInteractionDelegate, UIGestureRecognizerDelegate {
    private let inputMode = IChartTextInputMode()
    var inputModeControls: UIView { inputMode.controls }
    var keyboardModeButton: UIButton { inputMode.keyboardButton }
    var scribbleModeButton: UIButton { inputMode.scribbleButton }
    var isScribbleEnabled: Bool { inputMode.isScribbleEnabled }
    var isScribblePrepared: Bool { inputMode.isScribblePrepared && isFirstResponder }
    private let placeholderLabel = UILabel()
    private lazy var inputTap = IChartNativeKeyboardFocus.makeTap(target: self,
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
        textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8,
            right: inputMode.controls.intrinsicContentSize.width + 5)
        inputMode.keyboardButton.addTarget(self, action: #selector(selectKeyboard), for: .touchUpInside)
        inputMode.scribbleButton.addTarget(self, action: #selector(selectScribble), for: .touchUpInside)
        addSubview(inputMode.controls)
        addGestureRecognizer(inputTap)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        if !placeholderLabel.isHidden {
            let width = max(0, bounds.width - inset.left - inset.right)
            let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: size.height)
        }
        inputMode.controls.frame = inputModeControlsFrame
        inputMode.keyboardButton.isEnabled = isEditable
        inputMode.scribbleButton.isEnabled = isEditable
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
        inputMode.rememberSelection(in: self)
        let resigned = super.resignFirstResponder()
        if resigned {
            exitScribble()
            IChartKeyboardInputContext.finish(for: self)
        }
        return resigned
    }
    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        isScribblePrepared && isEditable && isUserInteractionEnabled && bounds.contains(location)
            && !inputModeControlsFrame.contains(location)
    }
    func scribbleInteractionWillBeginWriting(_ interaction: UIScribbleInteraction) {
        if isScribblePrepared { IChartKeyboardInputContext.handwritingBegan(in: self) }
    }
    private var inputModeControlsFrame: CGRect {
        let size = inputMode.controls.intrinsicContentSize
        return CGRect(x: bounds.maxX - size.width, y: bounds.minY, width: size.width, height: size.height)
    }
    func setInputName(_ name: String) { inputMode.setName(name) }
    func didBeginInput() { inputMode.didBegin(in: self) }
    func exitScribble() { inputMode.exitScribble() }
    func requestKeyboard(at point: CGPoint? = nil) {
        guard isEditable, isUserInteractionEnabled else { return }
        inputMode.requestKeyboard(in: self, at: point)
    }
    func prepareScribble(at point: CGPoint? = nil) {
        guard isEditable, isUserInteractionEnabled else { return }
        inputMode.prepareScribble(in: self, at: point)
    }
    @objc private func selectKeyboard() { requestKeyboard() }
    @objc private func selectScribble() {
        guard isEditable, isUserInteractionEnabled else { return }
        inputMode.armScribble(in: self)
    }
    @objc private func directTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if isScribbleEnabled {
            DispatchQueue.main.async { [weak self] in self?.prepareScribble(at: point) }
        } else {
            requestKeyboard(at: point)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isEditable && inputMode.allowsBodyTap(touch.type)
            && !inputModeControlsFrame.contains(touch.location(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === inputTap || otherGestureRecognizer === inputTap
    }
}

@MainActor
private protocol IChartNativeTextInput: UITextInput where Self: UIView {
    var inputView: UIView? { get set }
    var inputAccessoryView: UIView? { get set }
}

/// The selected mode controls the input view before UIKit receives focus. A
/// separate preparation step rejects the initiating Pencil tap as handwriting.
@MainActor
private final class IChartTextInputMode {
    private static weak var scribbleOwner: IChartTextInputMode?
    private weak var input: (any IChartNativeTextInput)?
    private let writingInputView = UIView(frame: .zero)
    private var typingAccessory: UIView?
    private var savedSelection: IChartTextSelection?
    let controls = IChartInputModeControls()
    var keyboardButton: UIButton { controls.keyboard }
    var scribbleButton: UIButton { controls.scribble }
    var isScribbleEnabled: Bool { Self.scribbleOwner === self }
    private(set) var isScribblePrepared = false

    init() { updateButtons() }

    func setName(_ name: String) {
        keyboardButton.accessibilityHint = "Type in \(name)."
        scribbleButton.accessibilityHint = "Tap \(name), then write with Apple Pencil."
    }

    func allowsBodyTap(_ touchType: UITouch.TouchType) -> Bool {
        touchType != .pencil || !isScribblePrepared
    }

    func armScribble(in input: any IChartNativeTextInput) {
        guard !isScribbleEnabled else { return }
        Self.scribbleOwner?.exitScribble()
        if !input.isFirstResponder { input.window?.endEditing(false) }
        rememberSelection(in: input)
        self.input = input
        Self.scribbleOwner = self
        typingAccessory = input.inputAccessoryView
        input.inputView = writingInputView
        input.inputAccessoryView = nil
        updateButtons()
        if input.isFirstResponder {
            IChartKeyboardInputContext.handwritingBegan(in: input)
            input.reloadInputViews()
            savedSelection?.restore(in: input)
        }
    }

    func prepareScribble(in input: any IChartNativeTextInput, at point: CGPoint?) {
        guard isScribbleEnabled, !isScribblePrepared, input.window != nil else { return }
        IChartKeyboardInputContext.handwritingBegan(in: input)
        guard input.isFirstResponder || input.becomeFirstResponder() else {
            IChartKeyboardInputContext.finish(for: input)
            return
        }
        if let savedSelection {
            savedSelection.restore(in: input)
        } else if let point, let position = input.closestPosition(to: point) {
            input.selectedTextRange = input.textRange(from: position, to: position)
        }
        isScribblePrepared = true
    }

    func requestKeyboard(in input: any IChartNativeTextInput, at point: CGPoint?) {
        let changesInputView = isScribbleEnabled
        let selection = input.isFirstResponder ? IChartTextSelection(input) : savedSelection
        Self.scribbleOwner?.exitScribble()
        IChartNativeKeyboardFocus.request(input, at: point, selection: selection,
            reloadsInputViews: changesInputView)
    }

    func didBegin(in input: any IChartNativeTextInput) {
        if !isScribbleEnabled {
            Self.scribbleOwner?.exitScribble()
            IChartKeyboardInputContext.begin(for: input)
        }
    }

    func rememberSelection(in input: any IChartNativeTextInput) {
        if input.isFirstResponder, input.markedTextRange == nil {
            savedSelection = IChartTextSelection(input)
        }
    }

    func exitScribble() {
        guard isScribbleEnabled else { return }
        Self.scribbleOwner = nil
        isScribblePrepared = false
        input?.inputView = nil
        input?.inputAccessoryView = typingAccessory
        input = nil
        typingAccessory = nil
        updateButtons()
    }

    private func updateButtons() {
        controls.select(isScribbleEnabled ? scribbleButton : keyboardButton)
    }
}

private struct IChartTextSelection {
    let start: Int
    let end: Int

    @MainActor
    init?(_ input: any UITextInput) {
        guard let selection = input.selectedTextRange else { return nil }
        start = input.offset(from: input.beginningOfDocument, to: selection.start)
        end = input.offset(from: input.beginningOfDocument, to: selection.end)
    }

    @MainActor
    func restore(in input: any UITextInput) {
        guard input.markedTextRange == nil else { return }
        let length = input.offset(from: input.beginningOfDocument, to: input.endOfDocument)
        guard let first = input.position(from: input.beginningOfDocument, offset: min(start, length)),
              let last = input.position(from: input.beginningOfDocument, offset: min(end, length)) else { return }
        input.selectedTextRange = input.textRange(from: first, to: last)
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
        claim(for: input, expectsPencil: false)
    }

    static func handwritingBegan(in input: UIView) {
        _ = claim(for: input, expectsPencil: true)
    }

    private static func claim(for input: UIView, expectsPencil: Bool) -> Bool {
        guard input is IChartTypedUITextField || input is IChartTypedUITextView else { return false }
        guard let current = UITextInputContext.current() else { return false }
        // A different UIKit input context has its own initial expectation.
        // Restore the old context before taking ownership of the new one.
        if context !== current || owner == nil {
            restore()
            originalPencilInputExpected = current.isPencilInputExpected
            context = current
        }
        owner = input
        guard current.isPencilInputExpected != expectsPencil else { return false }
        current.isPencilInputExpected = expectsPencil
        return true
    }

    static func finish(for input: UIView) {
        guard owner === input else { return }
        restore()
    }

    private static func restore() {
        if let context, let originalPencilInputExpected,
           context.isPencilInputExpected != originalPencilInputExpected {
            context.isPencilInputExpected = originalPencilInputExpected
        }
        owner = nil
        context = nil
        originalPencilInputExpected = nil
    }
}

@MainActor
private enum IChartNativeKeyboardFocus {
    static func request(_ input: any IChartNativeTextInput, at point: CGPoint?,
        selection: IChartTextSelection?, reloadsInputViews: Bool) {
        let wasFocused = input.isFirstResponder
        let changesInputHint = IChartKeyboardInputContext.begin(for: input)
        if wasFocused {
            // Native mode transitions keep the current responder and undo
            // session. Unchanged keyboard requests need no reload.
            if reloadsInputViews || changesInputHint { input.reloadInputViews() }
        } else if !input.becomeFirstResponder() {
            IChartKeyboardInputContext.finish(for: input)
            return
        }
        if !wasFocused, input.markedTextRange == nil, let point, let position = input.closestPosition(to: point) {
            input.selectedTextRange = input.textRange(from: position, to: position)
        } else if !wasFocused || reloadsInputViews || changesInputHint {
            selection?.restore(in: input)
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

/// One fixed accessory footprint keeps the text and hit targets in place as
/// either input mode becomes active. Each labeled control gets a 44pt target.
private final class IChartInputModeControls: UIStackView {
    let keyboard = UIButton(type: .system)
    let scribble = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .fill
        distribution = .fillEqually
        addArrangedSubview(keyboard)
        addArrangedSubview(scribble)
        for (button, title) in [(keyboard, "Keyboard"), (scribble, "Scribble")] {
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = title
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.layer.cornerRadius = 8
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 140, height: 44) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    func select(_ selected: UIButton) {
        for button in [keyboard, scribble] {
            let isSelected = button === selected
            button.isSelected = isSelected
            button.backgroundColor = isSelected ? UIColor.tintColor.withAlphaComponent(0.13) : .clear
            if isSelected { button.accessibilityTraits.insert(.selected) }
            else { button.accessibilityTraits.remove(.selected) }
        }
    }
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
