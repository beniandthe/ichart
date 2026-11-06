import SwiftUI
import UIKit

enum IChartTourStyle {
    static let navy = Color(red: 0.04, green: 0.17, blue: 0.36)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let orange = Color(red: 0.86, green: 0.36, blue: 0.06)
    static let orangeSoft = Color(red: 1.00, green: 0.89, blue: 0.74)
    static let borderLineWidth: CGFloat = 2.4
}

/// Color communicates a role; spacing and native separators group content.
/// Keep gold for guidance, blue for actions, and neutral bounds for inputs.
enum IChartInterfaceStyle {
    static let actionBlue = Color(red: 0.10, green: 0.34, blue: 0.72)
    static let cardBackground = Color(uiColor: .systemBackground)
    static let cardBorder = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.78, alpha: 0.65)
            : UIColor(white: 0.12, alpha: 0.65)
    })
    static let guidanceBackground = IChartTourStyle.navy
    static let guidanceTitle = IChartTourStyle.orangeSoft
    static let guidanceText = Color.white
    static let guidanceSecondary = Color.white.opacity(0.86)
    static let selectionFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.23, blue: 0.40, alpha: 1)
            : UIColor(red: 0.90, green: 0.94, blue: 1, alpha: 1)
    })
    static let actionText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.43, green: 0.67, blue: 1, alpha: 1)
            : UIColor(red: 0.10, green: 0.34, blue: 0.72, alpha: 1)
    })
    static let selectionBorder = actionText
    static let noteBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1)
            : UIColor(red: 1, green: 0.95, blue: 0.86, alpha: 1)
    })
    static let noteText = Color.primary
    static let sectionAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.76, blue: 0.43, alpha: 1)
            : UIColor(red: 0.55, green: 0.25, blue: 0.03, alpha: 1)
    })
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
