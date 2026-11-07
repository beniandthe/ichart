import SwiftUI

enum IChartQuickStartSetupPolicy {
    static let minimumStartingMeasureCount = 4

    static func initialMeasureCount(
        profileDefault: Int,
        isGuidedSimpleChart: Bool
    ) -> Int {
        guard isGuidedSimpleChart else {
            return profileDefault
        }

        return max(minimumStartingMeasureCount, profileDefault)
    }
}

struct ChartSetupDraftValues {
    var numerator: Int
    var denominator: Int
    var key: DocumentKey
    var clef: ChartClef
    var startingMeasureCount: Int
    var stylePreset: StylePreset
}

struct ChartSetupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var chart: Chart
    let onOperationStarted: (String) -> Void
    let onOperationFinished: () -> Void
    let isCreateActionHighlighted: Bool
    let showsCreateTourBanner: Bool
    let onSkipTour: () -> Void
    let onCancelCreation: (() -> Void)?
    let onBackToLayout: ((ChartSetupDraftValues) -> Void)?
    let onCreatePreparedChart: ((Chart) -> Bool)?

    @State private var numerator: Int
    @State private var denominator: Int
    @State private var selectedKey: DocumentKey
    @State private var selectedClef: ChartClef
    @State private var startingMeasureCount: Int
    @State private var selectedStylePreset: StylePreset
    @State private var isApplyingSetup = false
    @State private var creationError: String?

    init(
        chart: Binding<Chart>,
        isCreateActionHighlighted: Bool = false,
        showsCreateTourBanner: Bool = false,
        onSkipTour: @escaping () -> Void = {},
        onCancelCreation: (() -> Void)? = nil,
        initialDraftValues: ChartSetupDraftValues? = nil,
        onBackToLayout: ((ChartSetupDraftValues) -> Void)? = nil,
        onCreatePreparedChart: ((Chart) -> Bool)? = nil,
        onOperationStarted: @escaping (String) -> Void = { _ in },
        onOperationFinished: @escaping () -> Void = {}
    ) {
        self._chart = chart
        self.isCreateActionHighlighted = isCreateActionHighlighted
        self.showsCreateTourBanner = showsCreateTourBanner
        self.onSkipTour = onSkipTour
        self.onCancelCreation = onCancelCreation
        self.onBackToLayout = onBackToLayout
        self.onCreatePreparedChart = onCreatePreparedChart
        self.onOperationStarted = onOperationStarted
        self.onOperationFinished = onOperationFinished
        let profileDefaults = chart.wrappedValue.layoutStyle.profile.measureDefaults
        let setupPolicy = chart.wrappedValue.layoutStyle.profile.setupPolicy
        _numerator = State(initialValue: initialDraftValues?.numerator ?? chart.wrappedValue.defaultMeter.numerator)
        _denominator = State(initialValue: initialDraftValues?.denominator ?? chart.wrappedValue.defaultMeter.denominator)
        _selectedKey = State(initialValue: initialDraftValues?.key ?? chart.wrappedValue.displayedDocumentKey)
        _selectedClef = State(
            initialValue: initialDraftValues?.clef ?? (chart.wrappedValue.hasCompletedInitialSetup
                ? chart.wrappedValue.defaultClef
                : setupPolicy.creationDefaultClef)
        )
        _selectedStylePreset = State(initialValue: initialDraftValues?.stylePreset ?? chart.wrappedValue.stylePreset)
        let initialMeasureCount: Int
        if chart.wrappedValue.hasCompletedInitialSetup {
            initialMeasureCount = max(1, chart.wrappedValue.measures.count)
        } else {
            initialMeasureCount = IChartQuickStartSetupPolicy.initialMeasureCount(
                profileDefault: profileDefaults.initialMeasureCount,
                isGuidedSimpleChart: showsCreateTourBanner
                    && chart.wrappedValue.layoutStyle == .simpleChordSheet
            )
        }
        _startingMeasureCount = State(initialValue: initialDraftValues?.startingMeasureCount ?? initialMeasureCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let onBackToLayout {
                        Button {
                            onBackToLayout(currentDraftValues)
                        } label: {
                            Label("Back to Layouts", systemImage: "chevron.left")
                        }
                        .frame(minHeight: 44)
                        .accessibilityHint("Choose a different chart layout before creating the chart")
                    }

                    VStack(spacing: 6) {
                        Text(chart.hasCompletedInitialSetup ? "Update this chart's setup" : "Prepare a blank chart")
                            .font(.headline)
                        Text(chart.hasCompletedInitialSetup
                            ? "Choose the page settings, then tap Apply. Cancel leaves the chart unchanged."
                            : "Choose the key, meter and sheet style, then tap Create Blank Page.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if onCreatePreparedChart != nil {
                            Text("Nothing is added to your library until you create the page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("chart-setup-instruction")

                    if let creationError {
                        Text(creationError)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("chart-creation-error")
                    }

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
                if chart.hasCompletedInitialSetup || onCancelCreation != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if let onCancelCreation {
                                onCancelCreation()
                            } else {
                                dismiss()
                            }
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
        .tint(IChartInterfaceStyle.actionText)
    }

    private var createTourBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(IChartTourStyle.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Quick Start")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(IChartTourStyle.orange)

                    Text("1 of 8")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(IChartTourStyle.navy.opacity(0.74))

                    Text("Create A Page")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(IChartTourStyle.navy)
                }

                Text("Four measures are ready. Change the setup if you want, then tap Create Blank Page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSkipTour) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(IChartTourStyle.navy.opacity(0.72))
            .accessibilityLabel("End Quick Start")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IChartTourStyle.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(IChartTourStyle.navy.opacity(0.88), lineWidth: IChartTourStyle.borderLineWidth)
        }
        .shadow(color: IChartTourStyle.navy.opacity(0.12), radius: 10, y: 5)
    }

    private var setupPolicy: ChartLayoutSetupPolicy {
        chart.layoutStyle.profile.setupPolicy
    }

    private var currentDraftValues: ChartSetupDraftValues {
        ChartSetupDraftValues(numerator: numerator, denominator: denominator, key: selectedKey,
            clef: selectedClef, startingMeasureCount: startingMeasureCount, stylePreset: selectedStylePreset)
    }

    private var operationMessage: String {
        chart.hasCompletedInitialSetup ? "Updating page setup..." : "Creating blank page..."
    }

    private var shouldShowClefSection: Bool {
        !chart.hasCompletedInitialSetup && setupPolicy.allowsInitialClefSelection
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupSectionHeading("Layout Style")

            VStack(spacing: 8) {
                Image(systemName: chart.layoutStyle.systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IChartInterfaceStyle.actionText)
                    .frame(width: 28, height: 28)

                VStack(spacing: 4) {
                    Text(chart.layoutStyle.displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(chart.layoutStyle.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    private var sheetStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupSectionHeading("Sheet Style")

            VStack(spacing: 0) {
                ForEach(StylePreset.sheetPresets(for: chart.layoutStyle)) { preset in
                    Button {
                        selectedStylePreset = preset
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedStylePreset == preset ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selectedStylePreset == preset ? IChartInterfaceStyle.actionText : .secondary)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.sheetDisplayText(for: chart.layoutStyle))
                    .accessibilityHint(preset.sheetDetailText(for: chart.layoutStyle))

                    Divider()
                }
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupSectionHeading("Key")

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
            setupSectionHeading("Clef")

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
            setupSectionHeading("Time Signature")

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
            setupSectionHeading("Starting Measures")

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

    private func setupSectionHeading(_ title: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Capsule()
                .fill(IChartTourStyle.orange.opacity(0.7))
                .frame(width: 28, height: 3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func applySetupWithFeedback() {
        guard !isApplyingSetup else {
            return
        }

        isApplyingSetup = true
        creationError = nil
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
            var preparedChart = chart
            applySetup(to: &preparedChart)
            let didApply: Bool
            if let onCreatePreparedChart {
                didApply = onCreatePreparedChart(preparedChart)
            } else {
                chart = preparedChart
                didApply = true
            }
            IChartPerformanceTrace.end(completionSpan)
            if didApply {
                if onCreatePreparedChart == nil {
                    dismiss()
                }
            } else {
                creationError = "The chart could not be added. Check your chart limit and project access, then try again. Your setup is still here."
                isApplyingSetup = false
            }
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

    private func applySetup(to preparedChart: inout Chart) {
        let resolvedMeter: Meter
        if setupPolicy.includesTimeSignatureSelection {
            resolvedMeter = Meter(numerator: numerator, denominator: denominator)
        } else {
            resolvedMeter = chart.defaultMeter
        }

        preparedChart.completeInitialSetup(
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
