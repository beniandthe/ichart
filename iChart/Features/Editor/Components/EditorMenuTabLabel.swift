import SwiftUI

struct EditorMenuTabLabel: View {
    let title: String
    let systemImage: String
    var isSelected: Bool = false
    var selectedColor = Color(red: 0.16, green: 0.38, blue: 0.82)
    var isTourHighlighted = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : (isTourHighlighted ? IChartTourStyle.navy : Color.primary))
            .background(
                isSelected
                ? selectedColor
                : (isTourHighlighted ? IChartTourStyle.orangeSoft : Color(uiColor: .secondarySystemBackground))
            )
            .clipShape(Capsule())
            .tourActionHighlight(
                isActive: isTourHighlighted,
                cornerRadius: 18,
                tint: IChartTourStyle.orange
            )
    }
}

struct EditorCodaTabLabel: View {
    var isSelected: Bool = false
    var isTourHighlighted = false

    var body: some View {
        codaGlyph
            .frame(width: 28, height: 28)
            .frame(minWidth: 40)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected
                ? Color(red: 0.16, green: 0.38, blue: 0.82)
                : (
                    isTourHighlighted
                    ? IChartTourStyle.orangeSoft
                    : Color(uiColor: .secondarySystemBackground)
                )
            )
            .clipShape(Capsule())
            .tourActionHighlight(
                isActive: isTourHighlighted,
                cornerRadius: 18
            )
            .accessibilityLabel("Coda")
    }

    private var symbolColor: Color {
        isSelected ? Color.white : (isTourHighlighted ? IChartTourStyle.navy : Color.primary)
    }

    private var codaGlyph: some View {
        ZStack {
            Circle()
                .stroke(symbolColor, lineWidth: 2.2)
                .frame(width: 18, height: 18)

            Rectangle()
                .fill(symbolColor)
                .frame(width: 2, height: 26)

            Rectangle()
                .fill(symbolColor)
                .frame(width: 26, height: 2)
        }
    }
}
