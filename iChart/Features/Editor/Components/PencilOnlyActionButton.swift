import SwiftUI
import UIKit

struct PencilOnlyActionButton: UIViewRepresentable {
    enum Style: Equatable {
        case plain
        case bordered
        case borderedProminent
    }

    enum Role: Equatable {
        case standard
        case destructive
    }

    let title: String
    var systemImageName: String?
    var style: Style = .bordered
    var role: Role = .standard
    var isEnabled = true
    var accessibilityLabel: String?
    // Modal controls opt in; canvas/toolbar controls retain Pencil-only input.
    var acceptsDirectTouches = false
    let action: () -> Void

    func makeUIView(context: Context) -> PencilOnlyUIButton {
        let button = PencilOnlyUIButton(type: .system)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.performAction),
            for: .touchUpInside
        )
        button.usesRaisedToolFace = true
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: PencilOnlyUIButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled && context.environment.isEnabled
        button.configuration = configuration(increasedContrast:
            context.environment.colorSchemeContrast == .increased)
        button.accessibilityLabel = accessibilityLabel ?? title
        button.acceptsDirectTouches = acceptsDirectTouches
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    private func configuration(increasedContrast: Bool) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        switch style {
        case .plain:
            configuration = .plain()
        case .bordered:
            configuration = .bordered()
        case .borderedProminent:
            configuration = .borderedProminent()
        }

        configuration.background.strokeColor = UIColor.label.withAlphaComponent(increasedContrast ? 0.55 : 0.17)
        configuration.background.strokeWidth = increasedContrast ? 1.25 : 0.75
        if style == .plain {
            configuration.background.backgroundColor = .tertiarySystemBackground
            configuration.background.cornerRadius = 8
        }
        configuration.title = title
        configuration.image = systemImageName.flatMap(UIImage.init(systemName:))
        configuration.imagePadding = systemImageName == nil ? 0 : 6
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: style == .plain ? 6 : 8,
            leading: style == .plain ? 4 : 10,
            bottom: style == .plain ? 6 : 8,
            trailing: style == .plain ? 4 : 10
        )
        if role == .destructive {
            configuration.baseForegroundColor = .systemRed
        }
        return configuration
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

final class PencilOnlyUIButton: IChartFeedbackUIButton {
    var acceptsDirectTouches = false
    var usesRaisedToolFace = false {
        didSet {
            if usesRaisedToolFace {
                updateToolElevation()
            } else {
                layer.shadowOpacity = 0
                layer.shadowPath = nil
            }
        }
    }

    override var isHighlighted: Bool {
        didSet { updateToolElevation() }
    }

    override var isEnabled: Bool {
        didSet { updateToolElevation() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateToolElevation()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateToolElevation()
    }

    private func updateToolElevation() {
        guard usesRaisedToolFace else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = isEnabled ? (traitCollection.userInterfaceStyle == .dark ? 0.4 : 0.18) : 0
        layer.shadowRadius = isHighlighted ? 0.5 : 1.5
        layer.shadowOffset = CGSize(width: 0, height: isHighlighted ? 0 : 2)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
        CATransaction.commit()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
            touchType: touch.type, acceptsDirectTouches: acceptsDirectTouches
        ) else {
            return false
        }

        return super.beginTracking(touch, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else {
            return false
        }
        guard let touches = event?.allTouches,
              !touches.isEmpty else {
            return true
        }

        return touches.contains { touch in
            PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
                touchType: touch.type, acceptsDirectTouches: acceptsDirectTouches
            )
        }
    }
}

enum PencilOnlyActionButtonInputPolicy {
    static func allowsButtonTouch(
        touchType: UITouch.TouchType,
        acceptsDirectTouches: Bool = false,
        environment: LeadSheetLiveInkInputPolicy.RuntimeEnvironment = .current
    ) -> Bool {
        switch environment {
        case .device:
            return touchType == .pencil
                || (acceptsDirectTouches && (touchType == .direct || touchType == .indirectPointer))
        case .simulator:
            return true
        }
    }
}
