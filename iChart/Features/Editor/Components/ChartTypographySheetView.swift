import SwiftUI
import UIKit

struct ChartTypographySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var chart: Chart
    var premiumFontAccess: () -> Bool = { false }
    private var canUsePremiumFonts: Bool { premiumFontAccess() }
    @State private var operationMessage: String?
    @State private var operationID = UUID()
    @State private var showsIndividualFonts = false
    @State private var presentationDetent: PresentationDetent = .large
    @State private var showingPremiumFontUpgrade = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EditorSheetInstruction(title: "Choose a font set", steps: [
                        "Tap a matched set to update this chart and its PDF immediately.",
                        "Open Customize to change individual parts.",
                        canUsePremiumFonts
                            ? "Your Pro access includes Petaluma, MuseJazz, and Finale Jazz."
                            : "Petaluma, MuseJazz, and Finale Jazz require Pro to apply. Fonts already saved in a chart stay in use."
                    ])
                    .accessibilityIdentifier("fonts-sheet-instruction")
                }

                Section("Chart preview") {
                    NotationReadabilityPreview(chart: chart)
                        .frame(height: 118)
                        .background(Color.white)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ChartAppearancePreviewPolicy.accessibilityLabel(for: chart))
                }

                Section("Matched Set") {
                    ForEach(ChartFontFamilyPreset.selectableCases) { preset in
                        TypographyChoiceRow(
                            title: preset.displayText,
                            detail: preset.detailText,
                            preview: chordPreviewText,
                            previewFont: preset.chordTextPreviewFont(size: 24),
                            isSelected: chart.typography.matchedSet.releaseSafeTextFamily == preset,
                            requiresUpgrade: !canUsePremiumFonts && preset.requiresPremiumFonts
                        ) {
                            selectFont(.matchedSet(preset))
                        }
                        .accessibilityIdentifier("font-matched-\(preset.rawValue)")
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showsIndividualFonts) {
                        Text("Choose separate fonts for chords, the heading, cues, or notation symbols. Choose Use Matched Set to restore that part to the selected family.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("fonts-customize")
                }

                if showsIndividualFonts {
                    overrideSection(
                        title: "Chord Font",
                        selected: chart.typography.chordOverride,
                        preview: chordPreviewText,
                        previewFont: { $0.chordTextPreviewFont(size: 24) },
                        action: { selectFont(.chordOverride($0)) }
                    )

                    overrideSection(
                        title: "Header Font",
                        selected: chart.typography.headerOverride,
                        preview: "Almost Like Being In Love",
                        previewFont: { $0.textPreviewFont(size: 20) },
                        action: { selectFont(.headerOverride($0)) }
                    )

                    overrideSection(
                        title: "Text / Cue Font",
                        selected: chart.typography.textOverride,
                        preview: "(Medium Swing)  To Coda",
                        previewFont: { $0.textPreviewFont(size: 17) },
                        action: { selectFont(.textOverride($0)) }
                    )

                    Section("Notation Symbols") {
                        ForEach(NotationFontPreset.selectableCases) { preset in
                            TypographyChoiceRow(
                                title: preset.displayText,
                                detail: preset.detailText,
                                preview: notationPreview(for: preset),
                                previewFont: preset.notationPreviewFont(size: 22),
                                isSelected: chart.notationFont.releaseSafePreset == preset,
                                requiresUpgrade: !canUsePremiumFonts && preset.requiresPremiumFonts
                            ) {
                                selectFont(.notation(preset))
                            }
                            .accessibilityIdentifier("font-notation-\(preset.rawValue)")
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
        .presentationDetents([.medium, .large], selection: $presentationDetent)
        .sheet(isPresented: $showingPremiumFontUpgrade) {
            UpgradeSheetView(feature: .fontPresets)
                .accessibilityIdentifier("fonts-upgrade-sheet")
        }
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
                isSelected: selected == nil,
                requiresUpgrade: !canUsePremiumFonts && chart.typography.matchedSet.requiresPremiumFonts
            ) {
                action(nil)
            }

            ForEach(ChartFontFamilyPreset.selectableCases) { preset in
                TypographyChoiceRow(
                    title: preset.displayText,
                    detail: preset.detailText,
                    preview: preview,
                    previewFont: previewFont(preset),
                    isSelected: selected?.releaseSafeTextFamily == preset,
                    requiresUpgrade: !canUsePremiumFonts && preset.requiresPremiumFonts
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
        preset.notationPreviewSampleText
    }

    private func selectFont(_ selection: ChartFontSelection) {
        guard ChartFontSelectionPolicy.canApply(selection, to: chart, canUsePremiumFonts: canUsePremiumFonts) else {
            showingPremiumFontUpgrade = true
            return
        }
        applyTypographyChange {
            guard ChartFontSelectionPolicy.apply(selection, to: &chart,
                canUsePremiumFonts: premiumFontAccess()) else {
                operationMessage = nil
                showingPremiumFontUpgrade = true
                return
            }
        }
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
    var requiresUpgrade = false
    let action: () -> Void

    var body: some View {
        IChartTapFeedbackButton(isRaised: true, action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if requiresUpgrade {
                        Text("Pro")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pro font")
                    }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .foregroundStyle(IChartInterfaceStyle.actionText)
                            .accessibilityLabel("Selected")
                    }
                }

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
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(requiresUpgrade
            ? "Opens Pro font options. The chart keeps its current fonts."
            : "Applies immediately to this chart and its PDF")
    }
}
