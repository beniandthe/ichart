import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    let onOpenChart: (Chart.ID, EditorCanvasMode) -> Void
    @State private var showingLayoutPicker = false
    @State private var renameRequest: ChartRenameRequest?
    @State private var deleteRequest: ChartDeleteRequest?

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
                    onCreateChart: {
                        showingLayoutPicker = true
                    }
                )
                projectsSection
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
        .sheet(isPresented: $showingLayoutPicker) {
            NewChartLayoutPickerView { layoutStyle in
                showingLayoutPicker = false
                createNewChart(layoutStyle: layoutStyle)
            }
        }
        .sheet(item: $renameRequest) { request in
            RenameChartSheetView(request: request) { chartID, title in
                store.renameChart(id: chartID, to: title)
            }
        }
        .alert(
            "Delete Chart?",
            isPresented: deleteConfirmationPresented,
            presenting: deleteRequest
        ) { request in
            Button("Delete", role: .destructive) {
                store.deleteChart(id: request.chartID)
                deleteRequest = nil
            }
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: { request in
            Text("This removes \(request.title) from the local library.")
        }
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
                        ProjectRowView(
                            title: chart.title,
                            summary: chartSummary(for: chart),
                            updatedText: "Updated \(chart.updatedAt.formatted(date: .abbreviated, time: .shortened))",
                            isSelected: store.selectedChartID == chart.id,
                            canDuplicate: store.canCreateChart,
                            onOpen: {
                                onOpenChart(chart.id, .browse)
                            },
                            onRename: {
                                renameRequest = ChartRenameRequest(chart: chart)
                            },
                            onDuplicate: {
                                store.duplicateChart(id: chart.id)
                            },
                            onDelete: {
                                deleteRequest = ChartDeleteRequest(chart: chart)
                            }
                        )
                    }
                }
            }
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { deleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteRequest = nil
                }
            }
        )
    }

    private func chartSummary(for chart: Chart) -> String {
        chart.librarySummaryText
    }

    private func createNewChart(layoutStyle: ChartLayoutStyle) {
        guard store.createBlankChart(layoutStyle: layoutStyle), let chartID = store.selectedChartID else {
            return
        }

        onOpenChart(chartID, .browse)
    }
}

private struct ChartRenameRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let currentTitle: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        currentTitle = chart.title
    }
}

private struct ChartDeleteRequest: Identifiable, Hashable {
    let chartID: Chart.ID
    let title: String

    var id: Chart.ID { chartID }

    init(chart: Chart) {
        chartID = chart.id
        title = chart.title
    }
}

private struct RenameChartSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChartRenameRequest
    let onSave: (Chart.ID, String) -> Void
    @State private var title: String

    init(
        request: ChartRenameRequest,
        onSave: @escaping (Chart.ID, String) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        _title = State(initialValue: request.currentTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chart title", text: $title)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle("Rename Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(sanitizedTitle.isEmpty)
                }
            }
        }
    }

    private var sanitizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !sanitizedTitle.isEmpty else {
            return
        }

        onSave(request.chartID, sanitizedTitle)
        dismiss()
    }
}

private struct NewChartLayoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ChartLayoutStyle) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ChartLayoutStyle.v1NewChartOptions) { layoutStyle in
                        Button {
                            onSelect(layoutStyle)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: layoutStyle.systemImageName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(layoutStyle.displayText)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(layoutStyle.detailText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("New Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

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
    let canDuplicate: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
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

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .disabled(!canDuplicate)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Chart actions")
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
        .contextMenu {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!canDuplicate)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var cardBackground: Color {
        isSelected ? Color.blue.opacity(0.10) : Color.white.opacity(0.72)
    }

    private var cardBorderColor: Color {
        isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.06)
    }
}
