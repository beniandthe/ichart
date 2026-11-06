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
                    VStack(spacing: 8) {
                        Text("Choose a chart layout")
                            .font(.headline)
                        Capsule()
                            .fill(IChartTourStyle.orange)
                            .frame(width: 40, height: 3)
                            .accessibilityHidden(true)
                        Text("Pick the example that fits your chart. Next, choose its setup. Nothing is saved until Create Blank Page.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("new-chart-layout-instruction")

                    ForEach(ChartLayoutStyle.v1NewChartOptions) { layoutStyle in
                        layoutChoice(layoutStyle)
                        Divider()
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .tint(IChartInterfaceStyle.actionText)
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
            VStack(spacing: 10) {
                ZStack(alignment: .trailing) {
                    Text(layoutStyle.displayText)
                        .font(.headline)
                        .foregroundStyle(IChartInterfaceStyle.actionText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(IChartInterfaceStyle.actionText)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layoutStyle.displayText)
        .accessibilityHint(layoutStyle.detailText + " Opens setup. No chart is saved yet.")
        .accessibilityIdentifier("new-chart-layout-\(layoutStyle.rawValue)")
        .tourActionHighlight(isActive: isTourTarget, cornerRadius: 12, tint: .blue)
    }

}
#endif
