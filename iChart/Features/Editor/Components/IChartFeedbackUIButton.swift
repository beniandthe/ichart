import UIKit

enum IChartNativeButtonFeedbackPhase: Equatable {
    case idle
    case pressed
    case accepted
}

/// Feedback decorates the existing control without changing its hit target,
/// content layout, selected state, first responder, or action registration.
class IChartFeedbackUIButton: UIButton {
    private let feedbackFill = CAShapeLayer()
    private let feedbackEdge = CAShapeLayer()
    private var feedbackGeneration = 0
    private var acceptedFeedbackVisible = false
    private(set) var feedbackPhase: IChartNativeButtonFeedbackPhase = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        installFeedbackLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installFeedbackLayers()
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                feedbackGeneration &+= 1
                acceptedFeedbackVisible = false
            }
            updateFeedback()
        }
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                feedbackGeneration &+= 1
                acceptedFeedbackVisible = false
            }
            updateFeedback()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFeedbackGeometry()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateFeedback()
    }

    override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        guard isEnabled, isUserInteractionEnabled else { return }
        acceptedFeedbackVisible = true
        feedbackGeneration &+= 1
        let generation = feedbackGeneration
        updateFeedback()
        // Dispatch remains synchronous. The accent acknowledges this accepted
        // action rather than claiming that its operation has already finished.
        super.sendAction(action, to: target, for: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.feedbackGeneration == generation else { return }
            self.acceptedFeedbackVisible = false
            self.updateFeedback(fadesOut: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled, isUserInteractionEnabled else { return false }
        // These shared controls register their existing action on touchUpInside.
        // VoiceOver uses the same dispatch hook and never bypasses its guards.
        sendActions(for: .touchUpInside)
        return true
    }

    private func installFeedbackLayers() {
        feedbackFill.name = "iChart.button-feedback.fill"
        feedbackEdge.name = "iChart.button-feedback.edge"
        for decoration in [feedbackFill, feedbackEdge] {
            decoration.isHidden = true
            decoration.zPosition = 1_000
            decoration.actions = ["path": NSNull(), "hidden": NSNull(), "opacity": NSNull(),
                "fillColor": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull()]
            layer.addSublayer(decoration)
        }
        feedbackEdge.fillColor = UIColor.clear.cgColor
    }

    private var increasedContrast: Bool {
        traitCollection.accessibilityContrast == .high || UIAccessibility.isDarkerSystemColorsEnabled
    }

    private func updateFeedback(fadesOut: Bool = false) {
        let previousPhase = feedbackPhase
        feedbackPhase = !isEnabled ? .idle : (acceptedFeedbackVisible ? .accepted : (isHighlighted ? .pressed : .idle))
        let accent = IChartInterfaceStyle.actionUIColor
        feedbackFill.fillColor = accent.withAlphaComponent(increasedContrast ? 0.26 : 0.16).cgColor
        feedbackFill.strokeColor = accent.cgColor
        feedbackEdge.strokeColor = UIColor.white.withAlphaComponent(increasedContrast ? 1 : 0.92).cgColor
        updateFeedbackGeometry()
        let visible = feedbackPhase != .idle
        for decoration in [feedbackFill, feedbackEdge] {
            decoration.removeAllAnimations()
            decoration.isHidden = !visible
            if !visible, fadesOut, previousPhase != .idle {
                decoration.isHidden = false
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = 0.10
                decoration.opacity = 0
                decoration.add(fade, forKey: "acceptedFeedbackFade")
            } else {
                decoration.opacity = visible ? 1 : 0
            }
        }
    }

    private func updateFeedbackGeometry() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let local = CGRect(origin: .zero, size: size)
        let outlineWidth: CGFloat = increasedContrast ? 3 : 2
        feedbackFill.frame = local
        feedbackEdge.frame = local
        feedbackFill.lineWidth = outlineWidth
        feedbackEdge.lineWidth = increasedContrast ? 1.5 : 1
        let outer = local.insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2)
        let inner = local.insetBy(dx: outlineWidth + 0.5, dy: outlineWidth + 0.5)
        let radius = min(9, max(0, outer.height / 2))
        feedbackFill.path = UIBezierPath(roundedRect: outer, cornerRadius: radius).cgPath
        feedbackEdge.path = UIBezierPath(roundedRect: inner, cornerRadius: max(0, radius - outlineWidth)).cgPath
    }
}
