import SwiftUI

/// Keeps the next action visible while longer tool rules live in a sheet.
/// Reserve the ordinary content during recognition feedback so the writing
/// canvas does not move when a recovery message appears or disappears.
struct EditorToolGuidanceView: View {
    let guidance: EditorToolGuidance
    var reservedGuidance: EditorToolGuidance? = nil
    var statusMessage: String? = nil
    var onGuidePresentationChanged: (Bool) -> Void = { _ in }

    @State private var showingGuide = false
    @ScaledMetric(relativeTo: .caption) private var writingStepsHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            EditorToolGuidanceHeader(guidance: guidance) {
                showingGuide = true
            }

            if reservedGuidance != nil {
                // Fixed for this text size, independent of recognition state.
                // Keeping real content in the scroll view also exposes every
                // instruction to accessibility without a hidden overlay tree.
                ScrollView {
                    if let statusMessage {
                        statusText(statusMessage)
                    } else {
                        guidanceSteps(guidance.steps)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: writingStepsHeight)
            } else if let statusMessage {
                statusText(statusMessage)
            } else {
                guidanceSteps(guidance.steps)
            }

        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .ichartWarmPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-active-tool-instruction")
        .sheet(isPresented: $showingGuide, onDismiss: { onGuidePresentationChanged(false) }) {
            EditorToolGuideSheet(guidance: guidance)
        }
        .onChange(of: showingGuide) { _, showing in
            if showing { onGuidePresentationChanged(true) }
        }
        .onDisappear {
            if showingGuide { onGuidePresentationChanged(false) }
        }
    }

    private func statusText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("editor-guidance-status")
    }

    private func guidanceSteps(_ steps: [String]) -> some View {
        VStack(alignment: .center, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text(steps.count > 1 ? "\(index + 1). \(step)" : step)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(step)
                    .accessibilityIdentifier("editor-guidance-step-\(index + 1)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Keep the Guide naturally sized when text grows. The concrete boundary also
/// keeps its layout alternatives out of the editor toolbar's generic type.
struct EditorToolGuidanceHeader: View {
    let guidance: EditorToolGuidance
    let onOpenGuide: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var guideWidth: CGFloat = 64

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                purpose
                if !guidance.details.isEmpty {
                    guideButton(width: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack(alignment: .center, spacing: 6) {
                // Match the Guide reservation on both sides so the purpose
                // remains centered within the whole helper.
                if !guidance.details.isEmpty {
                    Color.clear.frame(width: guideWidth, height: 1).accessibilityHidden(true)
                }
                purpose
                if !guidance.details.isEmpty {
                    guideButton(width: guideWidth)
                }
            }
        }
    }

    private var purpose: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(guidance.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("editor-guidance-purpose")

            if let context = guidance.context {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("editor-guidance-context")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func guideButton(width: CGFloat?) -> some View {
        Button(action: onOpenGuide) {
            Label("Guide", systemImage: "book")
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(IChartTourStyle.orangeSoft.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(guidance.detailsTitle)
        .accessibilityHint("Open examples and detailed instructions without changing the chart.")
        .accessibilityIdentifier("editor-tool-guide-button")
    }
}

/// A matching top instruction for sheets that stage or apply a short task.
struct EditorSheetInstruction: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text(steps.count > 1 ? "\(index + 1). \(step)" : step)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(step)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .ichartWarmPanel()
        .accessibilityElement(children: .combine)
    }
}

private struct EditorToolGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let guidance: EditorToolGuidance

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EditorSheetInstruction(title: guidance.title, steps: guidance.steps)
                    if let context = guidance.context {
                        Text(context)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(guidance.details.enumerated()), id: \.offset) { _, section in
                    Section(section.title) {
                        if let example = section.example {
                            Text(example)
                                .font(.title2)
                                .foregroundStyle(IChartTourStyle.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Example: \(example)")
                        }
                        Text(section.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(guidance.detailsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("editor-tool-guide-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
