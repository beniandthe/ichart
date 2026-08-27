import SwiftUI

struct ChartSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart
    let onOperationStarted: (String) -> Void
    let onOperationFinished: () -> Void
    let isCreateActionHighlighted: Bool
    let showsCreateTourBanner: Bool
    let onSkipTour: () -> Void

    @State private var numerator: Int
    @State private var denominator: Int
    @State private var selectedKey: DocumentKey
    @State private var selectedClef: ChartClef
    @State private var startingMeasureCount: Int
    @State private var selectedStylePreset: StylePreset
    @State private var isApplyingSetup = false

    init(
        chart: Binding<Chart>,
        isCreateActionHighlighted: Bool = false,
        showsCreateTourBanner: Bool = false,
        onSkipTour: @escaping () -> Void = {},
        onOperationStarted: @escaping (String) -> Void = { _ in },
        onOperationFinished: @escaping () -> Void = {}
    ) {
        self._chart = chart
        self.isCreateActionHighlighted = isCreateActionHighlighted
        self.showsCreateTourBanner = showsCreateTourBanner
        self.onSkipTour = onSkipTour
        self.onOperationStarted = onOperationStarted
        self.onOperationFinished = onOperationFinished
        let profileDefaults = chart.wrappedValue.layoutStyle.profile.measureDefaults
        let setupPolicy = chart.wrappedValue.layoutStyle.profile.setupPolicy
        _numerator = State(initialValue: chart.wrappedValue.defaultMeter.numerator)
        _denominator = State(initialValue: chart.wrappedValue.defaultMeter.denominator)
        _selectedKey = State(initialValue: chart.wrappedValue.displayedDocumentKey)
        _selectedClef = State(
            initialValue: chart.wrappedValue.hasCompletedInitialSetup
                ? chart.wrappedValue.defaultClef
                : setupPolicy.creationDefaultClef
        )
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
                    if showsCreateTourBanner && !chart.hasCompletedInitialSetup {
                        createTourBanner
                    }

                    layoutSection
                    if setupPolicy.includesKeySelection {
                        keySection
                    }
                    if shouldShowClefSection {
                        clefSection
                    }
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
                    .tourActionHighlight(
                        isActive: isCreateActionHighlighted && !chart.hasCompletedInitialSetup,
                        cornerRadius: 8,
                        tint: .blue
                    )
                }
            }
        }
    }

    private var createTourBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IChartTourStyle.orange)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create The Page")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(IChartTourStyle.navy)

                    Text("For the example, use C, 4/4, and set Starting Measures to 8 before creating the page.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("The walkthrough cannot continue until Create Blank Page finishes.", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IChartTourStyle.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Label("Tap Create Blank Page", systemImage: "hand.tap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IChartTourStyle.navy)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(IChartTourStyle.orangeSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(IChartTourStyle.orange.opacity(0.72), lineWidth: 1.4)
                    }

                Spacer(minLength: 0)

                Button("Skip Tour", action: onSkipTour)
                    .buttonStyle(.bordered)
                    .tint(IChartTourStyle.navy)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IChartTourStyle.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(IChartTourStyle.navy.opacity(0.88), lineWidth: IChartTourStyle.borderLineWidth)
        }
        .shadow(color: IChartTourStyle.navy.opacity(0.16), radius: 14, y: 7)
    }

    private var setupPolicy: ChartLayoutSetupPolicy {
        chart.layoutStyle.profile.setupPolicy
    }

    private var operationMessage: String {
        chart.hasCompletedInitialSetup ? "Updating page setup..." : "Creating blank page..."
    }

    private var shouldShowClefSection: Bool {
        !chart.hasCompletedInitialSetup && setupPolicy.allowsInitialClefSelection
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

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key")
                .font(.headline)

            Picker("Key", selection: $selectedKey) {
                Section("Major") {
                    ForEach(DocumentKey.standardMajorKeys) { key in
                        Text(key.titleDisplayText).tag(key)
                    }
                }

                Section("Minor") {
                    ForEach(DocumentKey.standardMinorKeys) { key in
                        Text(key.titleDisplayText).tag(key)
                    }
                }
            }
            .pickerStyle(.navigationLink)
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

            Picker("Clef", selection: $selectedClef) {
                ForEach(setupPolicy.clefOptions) { clef in
                    Text(clef.displayText).tag(clef)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        let setupSpan = IChartPerformanceTrace.start(
            "chartSetup.applySetup",
            metadata: setupTraceMetadata
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            let completionSpan = IChartPerformanceTrace.start(
                "chartSetup.completeInitialSetup",
                metadata: setupTraceMetadata
            )
            applySetup()
            IChartPerformanceTrace.end(completionSpan)
            dismiss()
            try? await Task.sleep(nanoseconds: 180_000_000)
            onOperationFinished()
            IChartPerformanceTrace.end(setupSpan)
        }
    }

    private var setupTraceMetadata: [String: String] {
        [
            "layoutStyle": chart.layoutStyle.rawValue,
            "completedBefore": chart.hasCompletedInitialSetup ? "true" : "false",
            "key": selectedKey.displayText,
            "clef": selectedClef.rawValue,
            "meter": "\(numerator)/\(denominator)",
            "startingMeasureCount": "\(startingMeasureCount)",
            "stylePreset": selectedStylePreset.rawValue
        ]
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
            key: setupPolicy.includesKeySelection
                ? selectedKey.concertKey(for: chart.defaultTranspositionView)
                : chart.documentKey,
            meter: resolvedMeter,
            staffStyle: .fiveLine,
            startingMeasureCount: startingMeasureCount,
            clef: shouldShowClefSection ? selectedClef : chart.defaultClef,
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
