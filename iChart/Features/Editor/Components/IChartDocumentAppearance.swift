import SwiftUI

/// Display preference only. It is never part of a chart or an exported PDF.
enum IChartAppAppearance: String {
    case light
    case dark

    static let preferenceKey = "iChartHomeAppearanceMode"

    init(persistedValue: String) {
        self = Self(rawValue: persistedValue) ?? .light
    }

    var isDark: Bool { self == .dark }
    var colorScheme: ColorScheme { isDark ? .dark : .light }
}

extension View {
    func ichartDocumentDisplayAppearance() -> some View {
        modifier(IChartSelectedDocumentAppearance())
    }

    func ichartDocumentDisplayAppearance(isDark: Bool) -> some View {
        modifier(IChartDocumentDisplayAppearance(isDark: isDark))
    }
}

private struct IChartSelectedDocumentAppearance: ViewModifier {
    @AppStorage(IChartAppAppearance.preferenceKey) private var appearanceValue = IChartAppAppearance.light.rawValue

    func body(content: Content) -> some View {
        content.ichartDocumentDisplayAppearance(isDark: IChartAppAppearance(persistedValue: appearanceValue).isDark)
    }
}

private struct IChartDocumentDisplayAppearance: ViewModifier {
    let isDark: Bool

    func body(content: Content) -> some View {
        // Keep the native canvas/PDF view in the same SwiftUI identity path.
        // Replacing it with a conditional filtered view could discard live ink
        // or reset PDF navigation when the preference changes.
        content
            .background(isDark ? Color.white : Color.clear)
            .overlay {
                Color.white.opacity(isDark ? 1 : 0)
                    .blendMode(.difference)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .compositingGroup()
            // Invert luminance while keeping colored selection/ink cues near
            // their original hue instead of turning blue controls orange.
            .hueRotation(.degrees(isDark ? 180 : 0))
    }
}
