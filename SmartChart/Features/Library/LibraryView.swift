import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void

    private var chartCountText: String {
        let count = store.charts.count
        return count == 1 ? "1 chart" : "\(count) charts"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LibraryHeaderView(
                    chartCountText: chartCountText,
                    capacityText: store.chartCapacityText,
                    canCreateChart: store.canCreateChart,
                    onCreateChart: createNewChart
                )
                projectsSection
                #if DEBUG || targetEnvironment(simulator)
                developerToolsSection
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
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

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Charts")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text(chartCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if store.charts.isEmpty {
                ContentUnavailableView(
                    "No Projects Yet",
                    systemImage: "music.note",
                    description: Text("Create a new chart to start the first project.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.white.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.charts) { chart in
                        Button {
                            onOpenChart(chart.id, .browse)
                        } label: {
                            ProjectRowView(
                                title: chart.title,
                                summary: chartSummary(for: chart),
                                updatedText: "Updated \(chart.updatedAt.formatted(date: .abbreviated, time: .shortened))",
                                isSelected: store.selectedChartID == chart.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    #if DEBUG || targetEnvironment(simulator)
    private var developerToolsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    openChordWritingTestChart()
                } label: {
                    Label("Open Chord Test Chart", systemImage: "pencil.and.scribble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Opens a fresh disposable 8-measure chart for the chord-writing loop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        } label: {
            Label("Developer Tools", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .background(Color.white.opacity(0.60))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    #endif

    private func chartSummary(for chart: Chart) -> String {
        if !chart.hasCompletedInitialSetup {
            return "Setup pending"
        }

        if chart.measures.isEmpty {
            return "\(chart.documentKey.displayText) · \(chart.defaultMeter.displayText) · blank page"
        }

        return "\(chart.documentKey.displayText) · \(chart.defaultMeter.displayText) · \(chart.measures.count) measures"
    }

    private func createNewChart() {
        guard store.createBlankChart(), let chartID = store.selectedChartID else {
            return
        }

        onOpenChart(chartID, .browse)
    }

    #if DEBUG || targetEnvironment(simulator)
    private func openChordWritingTestChart() {
        let chartID = store.createChordWritingTestChart()
        onOpenChart(chartID, .chordEntry)
    }
    #endif
}

private struct LibraryHeaderView: View {
    let chartCountText: String
    let capacityText: String
    let canCreateChart: Bool
    let onCreateChart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    titleBlock

                    Spacer(minLength: 24)

                    newChartButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    newChartButton
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(chartCountText, systemImage: "doc.text")
                    .font(.caption.weight(.medium))

                Text(capacityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local library")
                .font(.title2.weight(.semibold))

            Text("Create, open, and export charts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var newChartButton: some View {
        Button(action: onCreateChart) {
            Label("New Chart", systemImage: "square.and.pencil")
                .frame(minWidth: 150)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canCreateChart)
    }
}

private struct ProjectRowView: View {
    let title: String
    let summary: String
    let updatedText: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
    }

    private var cardBackground: Color {
        isSelected ? Color.blue.opacity(0.10) : Color.white.opacity(0.72)
    }

    private var cardBorderColor: Color {
        isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.06)
    }
}
