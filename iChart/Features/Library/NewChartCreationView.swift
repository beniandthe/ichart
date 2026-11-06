#if canImport(UIKit)
import SwiftUI

/// Owns an unsaved chart until the final Create action. Going back or
/// cancelling never inserts a draft into the real library.
struct NewChartCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let onSkipTour: () -> Void
    let onCreate: (Chart) -> Bool

    @State private var stagedChart = Chart.draft(
        title: "Untitled Chart", key: .cMajor, layoutStyle: .simpleChordSheet
    )
    @State private var selectedLayout: ChartLayoutStyle?
    @State private var setupDraftValues: ChartSetupDraftValues?
    @State private var showingSetup = false
    @State private var highlightsSimpleLayout: Bool

    init(
        highlightsSimpleLayout: Bool = false,
        onSkipTour: @escaping () -> Void = {},
        onCreate: @escaping (Chart) -> Bool
    ) {
        self._highlightsSimpleLayout = State(initialValue: highlightsSimpleLayout)
        self.onSkipTour = onSkipTour
        self.onCreate = onCreate
    }

    var body: some View {
        Group {
            if showingSetup {
                ChartSetupSheetView(
                    chart: $stagedChart,
                    isCreateActionHighlighted: highlightsSimpleLayout
                        && stagedChart.layoutStyle == .simpleChordSheet,
                    showsCreateTourBanner: highlightsSimpleLayout
                        && stagedChart.layoutStyle == .simpleChordSheet,
                    onSkipTour: {
                        highlightsSimpleLayout = false
                        onSkipTour()
                    },
                    onCancelCreation: { dismiss() },
                    initialDraftValues: setupDraftValues,
                    onBackToLayout: { values in
                        setupDraftValues = values
                        showingSetup = false
                    },
                    onCreatePreparedChart: { preparedChart in
                        guard onCreate(preparedChart) else { return false }
                        dismiss()
                        return true
                    }
                )
                .id(stagedChart.id)
            } else {
                layoutPicker
            }
        }
    }

    private var layoutPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Choose a chart layout")
                            .font(.headline)
                        Text("Pick the example that fits your chart. Next, choose its setup. Nothing is saved until Create Blank Page.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("new-chart-layout-instruction")

                    ForEach(ChartLayoutStyle.v1NewChartOptions) { layoutStyle in
                        layoutChoice(layoutStyle)
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func layoutChoice(_ layoutStyle: ChartLayoutStyle) -> some View {
        let isTourTarget = highlightsSimpleLayout && layoutStyle == .simpleChordSheet
        let sample = Chart.blank(title: "Layout Example", layoutStyle: layoutStyle)
        return Button {
            if selectedLayout != layoutStyle {
                stagedChart = Chart.draft(title: "Untitled Chart", key: .cMajor, layoutStyle: layoutStyle)
                selectedLayout = layoutStyle
                setupDraftValues = nil
            }
            showingSetup = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(layoutStyle.displayText)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(layoutStyle.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NotationReadabilityPreview(chart: sample)
                    .frame(height: 118)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text("Example layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTourTarget ? Color.accentColor.opacity(0.10) : Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layoutStyle.displayText)
        .accessibilityHint(layoutStyle.detailText + " Opens setup. No chart is saved yet.")
        .accessibilityIdentifier("new-chart-layout-\(layoutStyle.rawValue)")
        .tourActionHighlight(isActive: isTourTarget, cornerRadius: 12, tint: .blue)
    }

}
#endif
