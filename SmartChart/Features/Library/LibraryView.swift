import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                projectsSection
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.96, blue: 0.93),
                    Color(red: 0.92, green: 0.94, blue: 0.97)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start a chart from a blank page.")
                .font(.system(size: 34, weight: .semibold, design: .serif))

            Text("Open an existing project or create a new chart to choose the key and time signature before the jazz page appears.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)

            Button {
                guard store.createBlankChart(), let chartID = store.selectedChartID else {
                    return
                }
                onOpenChart(chartID, .browse)
            } label: {
                Label("New Chart", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canCreateChart)

            #if DEBUG || targetEnvironment(simulator)
            Button {
                let chartID = store.createChordWritingTestChart()
                onOpenChart(chartID, .chordEntry)
            } label: {
                Label("Open Chord Test Chart", systemImage: "pencil.and.scribble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Debug build: opens a fresh disposable 8-measure chart for the chord-writing loop.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif

            Text(store.canCreateChart ? store.chartCapacityText : store.upgradeSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Existing Projects")
                .font(.title3.weight(.semibold))

            if store.charts.isEmpty {
                ContentUnavailableView(
                    "No Projects Yet",
                    systemImage: "music.note",
                    description: Text("Create a new chart to start the first project.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.white.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(store.charts) { chart in
                        Button {
                            onOpenChart(chart.id, .browse)
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(chart.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(chartSummary(for: chart))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text("Updated \(chart.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground(for: chart))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(cardBorderColor(for: chart), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chartSummary(for chart: Chart) -> String {
        if !chart.hasCompletedInitialSetup {
            return "Setup pending"
        }

        if chart.measures.isEmpty {
            return "\(chart.documentKey.displayText) · \(chart.defaultMeter.displayText) · blank page"
        }

        return "\(chart.documentKey.displayText) · \(chart.defaultMeter.displayText) · \(chart.measures.count) measures"
    }

    private func cardBackground(for chart: Chart) -> Color {
        store.selectedChartID == chart.id ? Color.blue.opacity(0.10) : Color.white.opacity(0.72)
    }

    private func cardBorderColor(for chart: Chart) -> Color {
        store.selectedChartID == chart.id ? Color.blue.opacity(0.35) : Color.black.opacity(0.06)
    }
}
