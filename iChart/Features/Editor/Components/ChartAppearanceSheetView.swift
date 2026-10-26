import SwiftUI
import UIKit

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
                    notationReadabilityRows
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
            ForEach(NotationFontPreset.selectableCases) { preset in
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

    private var notationReadabilityRows: some View {
        Section {
            NotationReadabilityPreview(chart: chart)
                .frame(height: 118)
                .background(Color.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Repeat and first ending preview. \(chart.notationReadability.displayText) readability. Angled repeat wings \(chart.repeatWings ? "on" : "off").")

            ForEach(NotationReadabilityPreset.allCases) { preset in
                AppearanceChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    isSelected: chart.notationReadability == preset
                ) {
                    applyAppearanceChange("Updating notation...") {
                        chart.setNotationReadability(preset)
                    }
                }
            }

            Toggle("Angled Repeat Wings", isOn: Binding(
                get: { chart.repeatWings },
                set: { chart.setRepeatWings($0) }
            ))
        } header: {
            Text("Notation Readability")
        } footer: {
            Text("Applies to this chart and its exported PDF.")
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

private struct NotationReadabilityPreview: UIViewRepresentable {
    let chart: Chart

    func makeUIView(context: Context) -> NotationReadabilityPreviewView {
        NotationReadabilityPreviewView()
    }

    func updateUIView(_ view: NotationReadabilityPreviewView, context: Context) {
        view.applyAppearance(from: chart)
    }
}

private final class NotationReadabilityPreviewView: UIView {
    private var chart = NotationReadabilityPreviewView.makeSampleChart()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    func applyAppearance(from source: Chart) {
        chart.notationReadability = source.notationReadability
        chart.repeatWings = source.repeatWings
        chart.notationFont = source.notationFont
        chart.typography = source.typography
        chart.engravingPreset = source.engravingPreset
        chart.staffSystemDensity = source.staffSystemDensity
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0 else {
            return
        }

        let page = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 720, height: 1_100)
        )
        guard let system = page.systems.first else {
            return
        }

        let previewMeasures = system.measures.filter { $0.sourceMeasureID != nil }
        let contentFrames = previewMeasures.flatMap { measure in
            [measure.staffFrame] + measure.chordLayouts.map(\.frame) + measure.repeatMarkerLayouts.map(\.occupiedFrame)
        } + system.endingLayouts.map(\.frame)
        guard let firstFrame = contentFrames.first else {
            return
        }
        let contentFrame = contentFrames.dropFirst().reduce(firstFrame) { $0.union($1) }
            .insetBy(dx: -16, dy: -16)
        let scale = min(bounds.width / contentFrame.width, bounds.height / contentFrame.height)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(
            x: (bounds.width - contentFrame.width * scale) / 2,
            y: (bounds.height - contentFrame.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -contentFrame.minX, y: -contentFrame.minY)

        let renderer = LeadSheetNotationRenderer(chart: chart)
        renderer.drawStaffLines(for: system)
        for ending in system.endingLayouts {
            renderer.drawEnding(ending)
        }
        if let firstMeasure = previewMeasures.first {
            renderer.drawRepeatBoundary(LeadSheetRepeatBoundaryPolicy.leadingMarkers(atStartOf: firstMeasure))
        }
        for (index, measure) in previewMeasures.enumerated() {
            for chord in measure.chordLayouts {
                renderer.drawChord(chord)
            }
            let nextMeasure = previewMeasures.indices.contains(index + 1) ? previewMeasures[index + 1] : nil
            let markers = LeadSheetRepeatBoundaryPolicy.repeatMarkers(after: measure, before: nextMeasure)
            if markers.isEmpty {
                renderer.drawBarline(measure.barlineAfter, in: measure.trailingBarlineFrame)
            } else {
                renderer.drawRepeatBoundary(markers)
            }
        }
    }

    private static func makeSampleChart() -> Chart {
        var sample = Chart.blank(title: "Notation Preview", measureCount: 2, layoutStyle: .simpleChordSheet)
        sample.stylePreset = .plainWhite
        for (index, text) in ["Cmaj7", "G7"].enumerated() {
            guard let symbol = try? ChordSymbolParser.parse(text) else {
                continue
            }
            sample.systems[0].measures[index].chordEvents = [ChordEvent(
                id: UUID(),
                symbol: symbol,
                startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 2),
                duration: .whole,
                rhythmPlacement: .hidden,
                tieOut: false,
                hitStyle: .none,
                rawInput: text
            )]
        }
        let measures = sample.measures
        sample.addRepeatSpan(startMeasureID: measures[0].id, endMeasureID: measures[1].id)
        sample.addEndingSpan(.ending1, startMeasureID: measures[1].id, endMeasureID: measures[1].id)
        return sample
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
