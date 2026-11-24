import SwiftUI

struct FormMarkerToolControls<Done: View>: View {
    let isEnabled: Bool
    let onSelect: (RoadmapType) -> Void
    @ViewBuilder let done: () -> Done

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var buttonWidth: CGFloat = 76

    var body: some View {
        FlowLayout(spacing: 5, rowSpacing: 5, centersRows: true) {
            ForEach(RoadmapType.navigationPointMarkerTypes, id: \.self) { type in
                IChartTapFeedbackButton(isRaised: true) {
                    onSelect(type)
                } label: {
                    Text(type.editorMenuDisplayText)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .frame(minWidth: minimumButtonWidth, minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
                }
                .disabled(!isEnabled)
                .accessibilityLabel(type.editorMenuDisplayText)
                .accessibilityHint(isEnabled ? type.placementMeaning : "Select a measure first.")
                .accessibilityIdentifier("form-marker-option-\(type.rawValue)")
            }
            done()
        }
    }

    private var minimumButtonWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(140, buttonWidth) : buttonWidth
    }
}
