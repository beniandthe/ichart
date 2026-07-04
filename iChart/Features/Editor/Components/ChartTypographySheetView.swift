import SwiftUI

struct ChartTypographySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chart: Chart
    @State private var operationMessage: String?
    @State private var operationID = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section("Matched Set") {
                    ForEach(ChartFontFamilyPreset.selectableCases) { preset in
                        TypographyChoiceRow(
                            title: preset.displayText,
                            detail: preset.detailText,
                            preview: chordPreviewText,
                            previewFont: preset.chordTextPreviewFont(size: 24),
                            isSelected: chart.typography.matchedSet == preset
                        ) {
                            applyTypographyChange {
                                chart.setMatchedFontFamily(preset)
                            }
                        }
                    }
                }

                overrideSection(
                    title: "Chord Font",
                    selected: chart.typography.chordOverride,
                    preview: chordPreviewText,
                    previewFont: { $0.chordTextPreviewFont(size: 24) },
                    action: { preset in
                        applyTypographyChange {
                            chart.setChordFontOverride(preset)
                        }
                    }
                )

                overrideSection(
                    title: "Header Font",
                    selected: chart.typography.headerOverride,
                    preview: "Almost Like Being In Love",
                    previewFont: { $0.textPreviewFont(size: 20) },
                    action: { preset in
                        applyTypographyChange {
                            chart.setHeaderFontOverride(preset)
                        }
                    }
                )

                overrideSection(
                    title: "Text / Cue Font",
                    selected: chart.typography.textOverride,
                    preview: "(Medium Swing)  To Coda",
                    previewFont: { $0.textPreviewFont(size: 17) },
                    action: { preset in
                        applyTypographyChange {
                            chart.setTextFontOverride(preset)
                        }
                    }
                )

                Section("Notation Symbols") {
                    ForEach(NotationFontPreset.selectableCases) { preset in
                        TypographyChoiceRow(
                            title: preset.displayText,
                            detail: preset.detailText,
                            preview: notationPreview(for: preset),
                            previewFont: preset.notationPreviewFont(size: 22),
                            isSelected: chart.notationFont == preset
                        ) {
                            applyTypographyChange {
                                chart.setNotationFont(preset)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .overlay {
            if let operationMessage {
                ChartTypographyOperationOverlay(message: operationMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: operationMessage)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func overrideSection(
        title: String,
        selected: ChartFontFamilyPreset?,
        preview: String,
        previewFont: @escaping (ChartFontFamilyPreset) -> Font,
        action: @escaping (ChartFontFamilyPreset?) -> Void
    ) -> some View {
        Section(title) {
            TypographyChoiceRow(
                title: "Use Matched Set",
                detail: chart.typography.matchedSet.detailText,
                preview: preview,
                previewFont: previewFont(chart.typography.matchedSet),
                isSelected: selected == nil
            ) {
                action(nil)
            }

            ForEach(ChartFontFamilyPreset.selectableCases) { preset in
                TypographyChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    preview: preview,
                    previewFont: previewFont(preset),
                    isSelected: selected == preset
                ) {
                    action(preset)
                }
            }
        }
    }

    private var chordPreviewText: String {
        "Bb△7  C°7  Fø7"
    }

    private func notationPreview(for preset: NotationFontPreset) -> String {
        let four = NotationGlyphCatalog.timeSignatureDigit(4) ?? "4"
        let three = NotationGlyphCatalog.timeSignatureDigit(3) ?? "3"
        return "\(four)\(four)   \(three)\(four)"
    }

    private func applyTypographyChange(_ work: @escaping () -> Void) {
        let nextOperationID = UUID()
        operationID = nextOperationID
        operationMessage = "Updating fonts..."

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            work()
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard operationID == nextOperationID else {
                return
            }

            operationMessage = nil
        }
    }
}

private struct ChartTypographyOperationOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

private struct TypographyChoiceRow: View {
    let title: String
    let detail: String
    var preview: String?
    var previewFont: Font?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let preview {
                        Text(preview)
                            .font(previewFont ?? .subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
