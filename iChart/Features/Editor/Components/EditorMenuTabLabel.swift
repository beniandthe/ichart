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
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? Color.white : (isTourHighlighted ? IChartTourStyle.navy : Color.primary))
            .background(
                isSelected
                ? selectedColor
                : (isTourHighlighted ? IChartTourStyle.orangeSoft : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .tourActionHighlight(
                isActive: isTourHighlighted,
                cornerRadius: 12,
                tint: IChartTourStyle.orange
            )
    }
}
