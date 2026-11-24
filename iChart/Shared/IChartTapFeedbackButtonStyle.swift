#if canImport(UIKit)
import SwiftUI

struct IChartTapFeedbackButtonStyle: ButtonStyle {
    private let isAcknowledged: Bool
    private let cornerRadius: CGFloat
    private let isRaised: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(isAcknowledged: Bool = false, cornerRadius: CGFloat = 8, isRaised: Bool = false) {
        self.isAcknowledged = isAcknowledged
        self.cornerRadius = cornerRadius
        self.isRaised = isRaised
    }

    func makeBody(configuration: Configuration) -> some View {
        let showsFeedback = isEnabled && (configuration.isPressed || isAcknowledged)
        let accent = showsFeedback ? IChartInterfaceStyle.actionText : Color.clear
        let width: CGFloat = colorSchemeContrast == .increased ? 3 : 2
        let outline = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .modifier(IChartToolButtonRelief(isRaised: isRaised, cornerRadius: cornerRadius,
                isPressed: configuration.isPressed))
            .contentShape(Rectangle())
            .overlay {
                ZStack {
                    outline.fill(accent.opacity(0.16))
                    outline.strokeBorder(accent, lineWidth: width)
                    outline.inset(by: width).strokeBorder(showsFeedback ? Color.white : Color.clear, lineWidth: 1)
                }
                .animation(reduceMotion || showsFeedback || !isEnabled ? nil : .easeOut(duration: 0.16),
                    value: showsFeedback)
                .allowsHitTesting(false)
            }
    }
}

private struct IChartToolButtonRelief: ViewModifier {
    let isRaised: Bool
    let cornerRadius: CGFloat
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        if isRaised {
            let face = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let isDepressed = isEnabled && isPressed
            let isDark = colorScheme == .dark
            let usesHighContrast = colorSchemeContrast == .increased
            let highlight = Color.white.opacity(isDark ? 0.08 : 0.18)
            let shade = isDark ? Color.black.opacity(0.18) : IChartInterfaceStyle.actionText.opacity(0.07)
            let edge = Color.primary.opacity(usesHighContrast ? 0.55 : 0.17)

            content
                .background {
                    face.fill(Color(uiColor: .tertiarySystemBackground))
                        .shadow(color: Color.black.opacity(isEnabled ? (isDark ? 0.40 : 0.18) : 0),
                            radius: isDepressed ? 0.5 : 1.5, y: isDepressed ? 0 : 2)
                        .allowsHitTesting(false)
                }
                .overlay {
                    if isEnabled {
                        face.fill(LinearGradient(colors: isDepressed ? [shade, highlight] : [highlight, shade],
                            startPoint: .top, endPoint: .bottom))
                            .overlay(face.strokeBorder(edge, lineWidth: usesHighContrast ? 1.25 : 0.75))
                            .allowsHitTesting(false)
                    }
                }
                .offset(y: isDepressed && !reduceMotion ? 1 : 0)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isDepressed)
        } else {
            content
        }
    }
}

extension ButtonStyle where Self == IChartTapFeedbackButtonStyle {
    static var iChartTapFeedback: Self { Self() }
    static var iChartRaisedToolTapFeedback: Self { Self(isRaised: true) }
}

extension View {
    /// Adds the editor tool face to controls with their own press colors.
    func iChartRaisedToolFace(cornerRadius: CGFloat = 8, isPressed: Bool) -> some View {
        modifier(IChartToolButtonRelief(isRaised: true, cornerRadius: cornerRadius, isPressed: isPressed))
    }

    /// Gives an on-screen Menu trigger the same press feedback as a Button.
    /// The menu's rows and submenu presentation still belong to SwiftUI.
    func iChartMenuTapFeedback(cornerRadius: CGFloat = 8, isRaised: Bool = false) -> some View {
        menuStyle(.button)
            .buttonStyle(IChartTapFeedbackButtonStyle(cornerRadius: cornerRadius, isRaised: isRaised))
    }
}

/// Keeps acknowledgement local to the control's existing Button action.
/// Pointer cancellation, scrolling and disabled buttons never dispatch it.
struct IChartTapFeedbackButton<Label: View>: View {
    var cornerRadius: CGFloat = 8
    var isRaised = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var acknowledgement: UUID?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard isEnabled else { return }
            acknowledgement = UUID()
            action()
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(IChartTapFeedbackButtonStyle(isAcknowledged: acknowledgement != nil,
            cornerRadius: cornerRadius, isRaised: isRaised))
        .task(id: acknowledgement) {
            guard let current = acknowledgement else { return }
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            if acknowledgement == current { acknowledgement = nil }
        }
    }
}
#endif
