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
    let action: () -> Void

    func makeUIView(context: Context) -> PencilOnlyUIButton {
        let button = PencilOnlyUIButton(type: .system)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.performAction),
            for: .touchUpInside
        )
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: PencilOnlyUIButton, context: Context) {
        context.coordinator.action = action
        button.configuration = configuration
        button.isEnabled = isEnabled
        button.accessibilityLabel = accessibilityLabel ?? title
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    private var configuration: UIButton.Configuration {
        var configuration: UIButton.Configuration
        switch style {
        case .plain:
            configuration = .plain()
        case .bordered:
            configuration = .bordered()
        case .borderedProminent:
            configuration = .borderedProminent()
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

final class PencilOnlyUIButton: UIButton {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard touch.type == .pencil else {
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
            touch.type == .pencil
        }
    }
}
