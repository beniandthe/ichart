import SwiftUI

enum ChartAppearancePanel: String, Identifiable {
    case documentStyle
    case notationFont
    case engraving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documentStyle:
            return "Document Style"
        case .notationFont:
            return "Notation Fonts"
        case .engraving:
            return "Engraving"
        }
    }

    var subtitle: String {
        switch self {
        case .documentStyle:
            return "Set the overall visual personality of the chart."
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
        .presentationDetents([.medium, .large])
    }

    private var documentStyleRows: some View {
        Section("Style") {
            ForEach(StylePreset.allCases, id: \.self) { preset in
                AppearanceChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    isSelected: chart.stylePreset == preset
                ) {
                    chart.setStylePreset(preset)
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
                    chart.setNotationFont(preset)
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
                    chart.setEngravingPreset(preset)
                }
            }
        }
    }

    private func notationPreview(for preset: NotationFontPreset) -> String {
        let four = NotationGlyphCatalog.timeSignatureDigit(4) ?? "4"
        let three = NotationGlyphCatalog.timeSignatureDigit(3) ?? "3"
        return "\(four)\(four)   \(three)\(four)"
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
