import SwiftUI

enum IChartTourStyle {
    static let navy = Color(red: 0.04, green: 0.17, blue: 0.36)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let orange = Color(red: 0.86, green: 0.36, blue: 0.06)
    static let orangeSoft = Color(red: 1.00, green: 0.89, blue: 0.74)
    static let borderLineWidth: CGFloat = 2.4
}

private struct TourActionHighlightModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.96), lineWidth: 3)
                        .padding(-6)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: isActive ? tint.opacity(0.34) : .clear, radius: isActive ? 12 : 0)
    }
}

extension View {
    /// A warm surface for instructions and section introductions. Text keeps
    /// its semantic foreground so the accent does not reduce readability.
    func ichartWarmPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(IChartWarmPanelModifier(cornerRadius: cornerRadius))
    }

    func tourActionHighlight(
        isActive: Bool,
        cornerRadius: CGFloat = 10,
        tint: Color = IChartTourStyle.orange
    ) -> some View {
        modifier(
            TourActionHighlightModifier(
                isActive: isActive,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}

private struct IChartWarmPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                IChartTourStyle.orangeSoft.opacity(colorScheme == .dark ? 0.10 : 0.48),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(IChartTourStyle.orange.opacity(colorScheme == .dark ? 0.46 : 0.24), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
