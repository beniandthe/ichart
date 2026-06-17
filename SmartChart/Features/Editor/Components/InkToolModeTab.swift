import SwiftUI

struct InkToolModeTab: View {
    @Binding var mode: EditorInkToolMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorInkToolMode.allCases, id: \.self) { toolMode in
                Button {
                    mode = toolMode
                } label: {
                    Label(toolMode.accessibilityLabel, systemImage: toolMode.systemImageName)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 38)
                        .foregroundStyle(mode == toolMode ? Color.white : Color.primary.opacity(0.74))
                        .background(buttonBackground(for: toolMode))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(toolMode.accessibilityLabel)
                .accessibilityAddTraits(mode == toolMode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func buttonBackground(for toolMode: EditorInkToolMode) -> some View {
        if mode == toolMode {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.12, green: 0.38, blue: 0.86))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.04))
        }
    }
}
