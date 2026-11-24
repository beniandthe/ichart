import SwiftUI

/// Existing editor commands beside the viewport, or in a compact row. The
/// parent owns placement so these buttons never overlay the score.
struct EditorQuickActions: View {
    let isVertical: Bool
    let isMeasuresSelected: Bool
    let isRepeatInProgress: Bool
    let canUseRepeat: Bool
    let onMeasures: () -> Void
    let onRepeat: () -> Void
    let onCancelRepeat: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if isVertical {
                VStack(spacing: 8) {
                    measuresButton
                    repeatButton
                    if isRepeatInProgress { cancelRepeatButton }
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    measuresButton
                    repeatButton
                    if isRepeatInProgress {
                        cancelRepeatButton
                    } else {
                        cancelRepeatButton
                            .hidden()
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-quick-actions")
    }

    private var measuresButton: some View {
        actionButton(title: "Measures", systemImage: "rectangle.split.3x1",
            identifier: "editor-quick-measures", selected: isMeasuresSelected,
            disabled: isRepeatInProgress,
            hint: isRepeatInProgress
                ? "Finish or cancel the repeat before opening Measures."
                : "Open the measure controls.",
            action: onMeasures)
    }

    private var repeatButton: some View {
        actionButton(title: isRepeatInProgress ? "End Repeat" : "Start Repeat",
            systemImage: isRepeatInProgress ? "checkmark.circle" : "repeat",
            identifier: isRepeatInProgress ? "editor-quick-end-repeat" : "editor-quick-start-repeat",
            selected: isRepeatInProgress, disabled: !canUseRepeat,
            hint: isRepeatInProgress
                ? "Use the selected measure as the end of this repeat."
                : "Set the selected measure as the start of a repeat.",
            action: onRepeat)
    }

    private var cancelRepeatButton: some View {
        actionButton(title: "Cancel Repeat", systemImage: "xmark.circle",
            identifier: "editor-quick-cancel-repeat", selected: false, disabled: false,
            hint: "Cancel repeat placement without changing the chart.", action: onCancelRepeat)
    }

    private func actionButton(title: String, systemImage: String, identifier: String,
        selected: Bool, disabled: Bool, hint: String, action: @escaping () -> Void) -> some View {
        let enabled = isEnabled && !disabled
        return IChartTapFeedbackButton(cornerRadius: 10, action: action) {
            Group {
                if isVertical {
                    VStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.caption.weight(.semibold))
                    }
                } else {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(minWidth: EditorCommandLayoutPolicy.minimumTapTarget,
                maxWidth: .infinity, minHeight: EditorCommandLayoutPolicy.minimumTapTarget)
            .foregroundStyle(!enabled ? Color.secondary : (selected ? .white : IChartInterfaceStyle.actionText))
            .background(selected && enabled ? IChartInterfaceStyle.actionBlue : IChartInterfaceStyle.cardBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(enabled ? IChartInterfaceStyle.selectionBorder : Color.secondary.opacity(0.35),
                        lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .disabled(disabled)
        .accessibilityLabel("\(title), quick action")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
