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
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
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
                .frame(maxWidth: .infinity, alignment: .leading)

                if !guidance.details.isEmpty {
                    Button {
                        showingGuide = true
                    } label: {
                        Label("Guide", systemImage: "book")
                            .font(.caption.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(guidance.detailsTitle)
                    .accessibilityHint("Open examples and detailed instructions without changing the chart.")
                    .accessibilityIdentifier("editor-tool-guide-button")
                }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("editor-guidance-status")
    }

    private func guidanceSteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if steps.count > 1 {
                        Text("\(index + 1).")
                            .fontWeight(.medium)
                            .accessibilityHidden(true)
                    }
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("editor-guidance-step-\(index + 1)")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A matching top instruction for sheets that stage or apply a short task.
struct EditorSheetInstruction: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if steps.count > 1 {
                        Text("\(index + 1).")
                            .accessibilityHidden(true)
                    }
                    Text(step)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    }
                }

                ForEach(Array(guidance.details.enumerated()), id: \.offset) { _, section in
                    Section(section.title) {
                        if let example = section.example {
                            Text(example)
                                .font(.title2)
                                .fixedSize(horizontal: false, vertical: true)
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
