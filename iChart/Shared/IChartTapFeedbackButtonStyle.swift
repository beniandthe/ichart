#if canImport(UIKit)
import SwiftUI

struct IChartTapFeedbackButtonStyle: ButtonStyle {
    private let isAcknowledged: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(isAcknowledged: Bool = false) {
        self.isAcknowledged = isAcknowledged
    }

    func makeBody(configuration: Configuration) -> some View {
        let showsFeedback = isEnabled && (configuration.isPressed || isAcknowledged)
        let accent = showsFeedback ? IChartInterfaceStyle.actionText : Color.clear
        let width: CGFloat = colorSchemeContrast == .increased ? 3 : 2
        let outline = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
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

extension ButtonStyle where Self == IChartTapFeedbackButtonStyle {
    static var iChartTapFeedback: Self { Self() }
}

/// Keeps acknowledgement local to the control's existing Button action.
/// Pointer cancellation, scrolling and disabled buttons never dispatch it.
struct IChartTapFeedbackButton<Label: View>: View {
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
            label()
        }
        .buttonStyle(IChartTapFeedbackButtonStyle(isAcknowledged: acknowledgement != nil))
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
