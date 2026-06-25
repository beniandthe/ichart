import SwiftUI

enum ChartAppearancePanel: String, Identifiable {
    case documentStyle
    case notationFont
    case engraving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documentStyle:
            return "Sheet Style"
        case .notationFont:
            return "Notation Fonts"
        case .engraving:
            return "Engraving"
        }
    }

    var subtitle: String {
        switch self {
        case .documentStyle:
            return "Change the chart page surface without changing the app controls."
        case .notationFont:
            return "Choose the notation symbol style used in the chart."
        case .engraving:
            return "Control spacing and stroke weight for the page."
        }
    }
}

struct ChartAppearanceSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chart: Chart
    let panel: ChartAppearancePanel
    @State private var operationMessage: String?
    @State private var operationID = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(panel.subtitle)
                        .foregroundStyle(.secondary)
                }

                switch panel {
                case .documentStyle:
                    documentStyleRows
                case .notationFont:
                    notationFontRows
                case .engraving:
                    engravingRows
                }
            }
            .navigationTitle(panel.title)
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
                ChartAppearanceOperationOverlay(message: operationMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: operationMessage)
        .presentationDetents([.medium, .large])
    }

    private var documentStyleRows: some View {
        Section("Style") {
            ForEach(StylePreset.sheetPresets(for: chart.layoutStyle), id: \.self) { preset in
                AppearanceChoiceRow(
                    title: preset.sheetDisplayText(for: chart.layoutStyle),
                    detail: preset.sheetDetailText(for: chart.layoutStyle),
                    isSelected: chart.stylePreset == preset
                ) {
                    applyAppearanceChange("Updating page style...") {
                        chart.setStylePreset(preset)
                    }
                }
            }
        }
    }

    private var notationFontRows: some View {
        Section("Notation Font") {
            ForEach(NotationFontPreset.allCases) { preset in
                AppearanceChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    preview: notationPreview(for: preset),
                    previewFont: preset.notationPreviewFont(size: 22),
                    isSelected: chart.notationFont == preset
                ) {
                    applyAppearanceChange("Updating fonts...") {
                        chart.setNotationFont(preset)
                    }
                }
            }
        }
    }

    private var engravingRows: some View {
        Section("Preset") {
            ForEach(EngravingPreset.allCases) { preset in
                AppearanceChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    isSelected: chart.engravingPreset == preset
                ) {
                    applyAppearanceChange("Updating engraving...") {
                        chart.setEngravingPreset(preset)
                    }
                }
            }
        }
    }

    private func notationPreview(for preset: NotationFontPreset) -> String {
        let four = NotationGlyphCatalog.timeSignatureDigit(4) ?? "4"
        let three = NotationGlyphCatalog.timeSignatureDigit(3) ?? "3"
        return "\(four)\(four)   \(three)\(four)"
    }

    private func applyAppearanceChange(_ message: String, perform work: @escaping () -> Void) {
        let nextOperationID = UUID()
        operationID = nextOperationID
        operationMessage = message

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

private struct ChartAppearanceOperationOverlay: View {
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

private struct AppearanceChoiceRow: View {
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
                    }

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
