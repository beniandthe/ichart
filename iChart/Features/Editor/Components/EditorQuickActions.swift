import SwiftUI

struct EditorQuickToolAction: Identifiable {
    let destination: EditorCommandDestination
    let title: String
    let systemImage: String
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var id: EditorCommandDestination { destination }
}

struct EditorQuickRepeatAction {
    let isInProgress: Bool
    let canUseRepeat: Bool
    let onRepeat: () -> Void
    let onCancelRepeat: () -> Void
}

/// The parent reserves space outside the score. An empty tool list selects
/// the compact, repeat-only row without creating a second command surface.
struct EditorQuickActions: View {
    let tools: [EditorQuickToolAction]
    let repeatAction: EditorQuickRepeatAction?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if tools.isEmpty {
                if let repeatAction {
                    HStack(alignment: .center, spacing: 6) {
                        repeatButton(repeatAction, isVertical: false)
                        if repeatAction.isInProgress {
                            cancelRepeatButton(repeatAction, isVertical: false)
                        } else {
                            cancelRepeatButton(repeatAction, isVertical: false)
                                .hidden()
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(tools) { tool in
                        actionButton(title: tool.title, systemImage: tool.systemImage,
                            identifier: "editor-quick-tool-\(tool.destination.rawValue)",
                            selected: tool.selected, disabled: tool.disabled, isVertical: true,
                            hint: "Open \(tool.title).", action: tool.action)
                    }
                    if let repeatAction {
                        Divider().accessibilityHidden(true)
                        repeatButton(repeatAction, isVertical: true)
                        if repeatAction.isInProgress {
                            cancelRepeatButton(repeatAction, isVertical: true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-quick-actions")
    }

    private func repeatButton(_ repeatAction: EditorQuickRepeatAction, isVertical: Bool) -> some View {
        actionButton(title: repeatAction.isInProgress ? "End Repeat" : "Start Repeat",
            systemImage: repeatAction.isInProgress ? "checkmark.circle" : "repeat",
            identifier: repeatAction.isInProgress ? "editor-quick-end-repeat" : "editor-quick-start-repeat",
            selected: repeatAction.isInProgress, disabled: !repeatAction.canUseRepeat, isVertical: isVertical,
            hint: repeatAction.isInProgress
                ? "Use the selected measure as the end of this repeat."
                : "Set the selected measure as the start of a repeat.",
            action: repeatAction.onRepeat)
    }

    private func cancelRepeatButton(_ repeatAction: EditorQuickRepeatAction, isVertical: Bool) -> some View {
        actionButton(title: "Cancel Repeat", systemImage: "xmark.circle",
            identifier: "editor-quick-cancel-repeat", selected: false, disabled: false, isVertical: isVertical,
            hint: "Cancel repeat placement without changing the chart.", action: repeatAction.onCancelRepeat)
    }

    private func actionButton(title: String, systemImage: String, identifier: String,
        selected: Bool, disabled: Bool, isVertical: Bool, hint: String, action: @escaping () -> Void) -> some View {
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
