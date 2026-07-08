import SwiftUI

struct ChartSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart
    let onOperationStarted: (String) -> Void
    let onOperationFinished: () -> Void

    @State private var numerator: Int
    @State private var denominator: Int
    @State private var startingMeasureCount: Int
    @State private var selectedStylePreset: StylePreset
    @State private var isApplyingSetup = false

    init(
        chart: Binding<Chart>,
        onOperationStarted: @escaping (String) -> Void = { _ in },
        onOperationFinished: @escaping () -> Void = {}
    ) {
        self._chart = chart
        self.onOperationStarted = onOperationStarted
        self.onOperationFinished = onOperationFinished
        let profileDefaults = chart.wrappedValue.layoutStyle.profile.measureDefaults
        _numerator = State(initialValue: chart.wrappedValue.defaultMeter.numerator)
        _denominator = State(initialValue: chart.wrappedValue.defaultMeter.denominator)
        _selectedStylePreset = State(initialValue: chart.wrappedValue.stylePreset)
        _startingMeasureCount = State(
            initialValue: chart.wrappedValue.hasCompletedInitialSetup
                ? max(1, chart.wrappedValue.measures.count)
                : profileDefaults.initialMeasureCount
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    layoutSection
                    if setupPolicy.includesTimeSignatureSelection {
                        meterSection
                    }
                    if setupPolicy.includesStartingMeasureSelection, !chart.hasCompletedInitialSetup {
                        startingMeasuresSection
                    }
                    sheetStyleSection
                }
                .padding(24)
            }
            .navigationTitle(chart.hasCompletedInitialSetup ? "Chart" : "New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!chart.hasCompletedInitialSetup || isApplyingSetup)
            .disabled(isApplyingSetup)
            .overlay {
                if isApplyingSetup {
                    ChartSetupOperationOverlay(message: operationMessage)
                }
            }
            .toolbar {
                if chart.hasCompletedInitialSetup {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applySetupWithFeedback()
                    } label: {
                        if isApplyingSetup {
                            ProgressView()
                        } else {
                            Text(chart.hasCompletedInitialSetup ? "Apply" : "Create Blank Page")
                        }
                    }
                    .disabled(isApplyingSetup)
                }
            }
        }
    }

    private var setupPolicy: ChartLayoutSetupPolicy {
        chart.layoutStyle.profile.setupPolicy
    }

    private var operationMessage: String {
        chart.hasCompletedInitialSetup ? "Updating page setup..." : "Creating blank page..."
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout Style")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: chart.layoutStyle.systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(chart.layoutStyle.displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(chart.layoutStyle.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sheetStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sheet Style")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(StylePreset.sheetPresets(for: chart.layoutStyle)) { preset in
                    Button {
                        selectedStylePreset = preset
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedStylePreset == preset ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selectedStylePreset == preset ? Color.accentColor : .secondary)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.sheetDisplayText(for: chart.layoutStyle))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(preset.sheetDetailText(for: chart.layoutStyle))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedStylePreset == preset
                                ? Color.accentColor.opacity(0.10)
                                : Color(uiColor: .secondarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.sheetDisplayText(for: chart.layoutStyle))
                    .accessibilityHint(preset.sheetDetailText(for: chart.layoutStyle))
                }
            }
        }
    }

    private var meterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Signature")
                .font(.headline)

            HStack(spacing: 14) {
                Stepper(value: $numerator, in: 1...12) {
                    Text("\(numerator)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 32)
                }

                Text("/")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Denominator", selection: $denominator) {
                    ForEach([2, 4, 8, 16], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var startingMeasuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starting Measures")
                .font(.headline)

            Stepper(value: $startingMeasureCount, in: 1...64) {
                HStack {
                    Text("Measures")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(startingMeasureCount)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func applySetupWithFeedback() {
        guard !isApplyingSetup else {
            return
        }

        isApplyingSetup = true
        onOperationStarted(operationMessage)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            applySetup()
            dismiss()
            try? await Task.sleep(nanoseconds: 420_000_000)
            onOperationFinished()
        }
    }

    private func applySetup() {
        let resolvedMeter: Meter
        if setupPolicy.includesTimeSignatureSelection {
            resolvedMeter = Meter(numerator: numerator, denominator: denominator)
        } else {
            resolvedMeter = chart.defaultMeter
        }

        chart.completeInitialSetup(
            title: chart.title,
            key: chart.documentKey,
            meter: resolvedMeter,
            staffStyle: .fiveLine,
            startingMeasureCount: startingMeasureCount,
            clef: chart.defaultClef,
            stylePreset: selectedStylePreset
        )
    }

}

private struct ChartSetupOperationOverlay: View {
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
