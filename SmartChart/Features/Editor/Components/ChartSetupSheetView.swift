import SwiftUI

struct ChartSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart

    @State private var draftKey: DocumentKey
    @State private var numerator: Int
    @State private var denominator: Int
    @State private var startingMeasureCount: Int
    @State private var draftClef: ChartClef

    init(chart: Binding<Chart>) {
        self._chart = chart
        let profileDefaults = chart.wrappedValue.layoutStyle.profile.measureDefaults
        _draftKey = State(initialValue: chart.wrappedValue.documentKey)
        _numerator = State(initialValue: chart.wrappedValue.defaultMeter.numerator)
        _denominator = State(initialValue: chart.wrappedValue.defaultMeter.denominator)
        _startingMeasureCount = State(
            initialValue: chart.wrappedValue.hasCompletedInitialSetup
                ? max(1, chart.wrappedValue.measures.count)
                : profileDefaults.initialMeasureCount
        )
        _draftClef = State(initialValue: chart.wrappedValue.defaultClef)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    layoutSection
                    if setupPolicy.includesKeySelection {
                        keySection
                    }
                    if setupPolicy.includesTimeSignatureSelection {
                        meterSection
                    }
                    if setupPolicy.includesStartingMeasureSelection, !chart.hasCompletedInitialSetup {
                        startingMeasuresSection
                    }
                    if !setupPolicy.clefOptions.isEmpty {
                        clefSection
                    }
                }
                .padding(24)
            }
            .navigationTitle(chart.hasCompletedInitialSetup ? "Chart" : "New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!chart.hasCompletedInitialSetup)
            .toolbar {
                if chart.hasCompletedInitialSetup {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(chart.hasCompletedInitialSetup ? "Apply" : "Create Blank Page") {
                        applySetup()
                        dismiss()
                    }
                }
            }
        }
    }

    private var setupPolicy: ChartLayoutSetupPolicy {
        chart.layoutStyle.profile.setupPolicy
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

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(DocumentKey.commonCreationKeys, id: \.self) { key in
                    Button {
                        draftKey = key
                    } label: {
                        Text(key.displayText)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(draftKey == key ? .blue : .secondary.opacity(0.3))
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

    private var clefSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clef")
                .font(.headline)

            Picker("Clef", selection: $draftClef) {
                ForEach(setupPolicy.clefOptions) { clef in
                    Text(clef.displayText).tag(clef)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func applySetup() {
        let resolvedKey = setupPolicy.includesKeySelection ? draftKey : chart.documentKey
        let resolvedMeter: Meter
        if setupPolicy.includesTimeSignatureSelection {
            resolvedMeter = Meter(numerator: numerator, denominator: denominator)
        } else {
            resolvedMeter = chart.defaultMeter
        }

        let resolvedClef: ChartClef
        if setupPolicy.clefOptions.contains(draftClef) {
            resolvedClef = draftClef
        } else {
            resolvedClef = setupPolicy.clefOptions.first ?? chart.defaultClef
        }

        chart.completeInitialSetup(
            title: chart.title,
            key: resolvedKey,
            meter: resolvedMeter,
            staffStyle: .fiveLine,
            startingMeasureCount: startingMeasureCount,
            clef: resolvedClef
        )
    }

}
