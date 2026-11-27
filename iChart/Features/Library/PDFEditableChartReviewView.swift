import SwiftUI
import UIKit

/// Keeps the imported measures and the saved PDF together until review is complete.
struct PDFEditableChartReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var minimumMeasureWidth: CGFloat = 72
    let url: URL
    let title: String
    let sourcePDFLibraryItemID: UUID
    var conversionUnavailableMessage: String? = nil
    let onSave: (Chart) async -> Bool

    @State private var draft: PDFEditableChartDraft?
    @State private var selectedMeasure: MeasureLocation?
    @State private var sourceMeasure: MeasureLocation?
    @State private var showingOriginalPDF = false
    @State private var isEditingTitle = false
    @State private var showingImportDetails = false
    @State private var isReading = false
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?
    @State private var canRetryReading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reviewStatus
                if let draft {
                    GeometryReader { geometry in
                        reviewWorkspace(draft, width: geometry.size.width)
                    }
                } else if conversionUnavailableMessage != nil {
                    originalPDF()
                } else if let errorMessage {
                    readError(errorMessage)
                } else {
                    ProgressView("Reading PDF chords…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("pdf.editable-chart.reading")
                }
            }
            .navigationTitle("Review Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("pdf.editable-chart.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save as New Chart") {
                        Task { await saveDraft() }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("pdf.editable-chart.save")
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: showingOriginalPDF) { _, isShowingPDF in
            if isShowingPDF { endEditing() }
        }
        .onChange(of: conversionUnavailableMessage) { _, message in
            guard message == nil, draft == nil, !isReading else { return }
            Task { await readDraft() }
        }
        .task {
            guard draft == nil, !isReading else { return }
            await readDraft()
        }
    }

    @ViewBuilder
    private var reviewStatus: some View {
        if let conversionUnavailableMessage {
            statusBanner(draft == nil ? conversionUnavailableMessage
                : "\(conversionUnavailableMessage) Your review is kept here while this screen stays open.",
                systemImage: "lock", identifier: "pdf.editable-chart.access-guidance")
        }
        if isSaving {
            ProgressView("Saving chart…")
                .padding(8)
                .accessibilityIdentifier("pdf.editable-chart.saving")
        } else if didSave {
            statusBanner("Chart saved.", systemImage: "checkmark",
                         identifier: "pdf.editable-chart.saved")
        } else if draft != nil, let errorMessage {
            statusBanner(errorMessage, systemImage: "exclamationmark.circle",
                         identifier: "pdf.editable-chart.save-error")
        }
    }

    private func statusBanner(_ message: String, systemImage: String, identifier: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground))
            .accessibilityLabel(message)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func reviewWorkspace(_ current: PDFEditableChartDraft, width: CGFloat) -> some View {
        if width >= 740 {
            let chartWidth = (width - 1) * 0.56
            HStack(spacing: 0) {
                chartPane(current, width: chartWidth)
                    .frame(width: chartWidth)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Original PDF")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider()
                    originalPDF(at: sourceMeasure)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                Picker("Review view", selection: $showingOriginalPDF) {
                    Text("Chart").tag(false)
                    Text("Original PDF").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityIdentifier("pdf.editable-chart.source-toggle")
                Divider()
                ZStack {
                    chartPane(current, width: width)
                        .opacity(showingOriginalPDF ? 0 : 1)
                        .allowsHitTesting(!showingOriginalPDF)
                        .accessibilityHidden(showingOriginalPDF)
                    originalPDF(at: showingOriginalPDF ? sourceMeasure : nil)
                        .opacity(showingOriginalPDF ? 1 : 0)
                        .allowsHitTesting(showingOriginalPDF)
                        .accessibilityHidden(!showingOriginalPDF)
                }
            }
        }
    }

    private func originalPDF(at measure: MeasureLocation? = nil) -> some View {
        PDFDocumentView(url: url, pageRequest: measure.map {
            PDFDocumentView.PageRequest(number: $0.page, selectionID: $0.number)
        })
            .ichartDocumentDisplayAppearance()
            .accessibilityIdentifier("pdf.editable-chart.original")
    }

    private func chartPane(_ current: PDFEditableChartDraft, width: CGFloat) -> some View {
        let rows = measureLocations(in: current)
        let issues = rows.flatMap { $0 }.filter { location in
            current.reviewIssue(forMeasure: current.rows[location.row][location.column],
                                rowIndex: location.row) != nil
        }

        return ScrollViewReader { scroll in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        chartHeading(current, measureCount: rows.reduce(0) { $0 + $1.count })
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(rows.indices, id: \.self) { row in
                                chartRow(current, locations: rows[row], row: row,
                                         width: max(0, width - 32))
                                    .id("row-\(row)")
                            }
                        }
                    }
                    .padding(16)
                    .background(IChartTypedSheetScrollSupport())
                }
                .scrollDismissesKeyboard(.interactively)
                if let selectedMeasure, !isEditingTitle {
                    Divider()
                    measureInspector(current, location: selectedMeasure, issues: issues, scroll: scroll)
                } else if !issues.isEmpty, !isEditingTitle {
                    Divider()
                    nextIssueControl(issues, scroll: scroll)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func chartHeading(_ current: PDFEditableChartDraft, measureCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if isEditingTitle {
                HStack(spacing: 8) {
                    IChartTypedTextField(placeholder: "Chart title", text: Binding(
                        get: { draft?.title ?? title },
                        set: { draft?.title = $0 }
                    ), autocapitalizationType: .words, autocorrectionType: .yes,
                        accessibilityIdentifier: "pdf.editable-chart.title",
                        accessibilityLabel: "Chart title", accessibilityHint: inputHint,
                        compact: true, onSubmit: finishTitleEditing)
                        .disabled(isSaving || didSave)
                    Button("Done", action: finishTitleEditing)
                        .frame(minHeight: 44)
                }
            } else {
                Button {
                    endEditing()
                    isEditingTitle = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(current.title.isEmpty ? "Untitled Chart" : current.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving || didSave)
                .accessibilityHint("Edit chart title.")
                .accessibilityIdentifier("pdf.editable-chart.rename")
            }

            HStack(spacing: 6) {
                Text("\(measureCount) measures · 4/4")
                    .foregroundStyle(.secondary)
                Button {
                    showingImportDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Import details")
                .popover(isPresented: $showingImportDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Import details")
                            .font(.headline)
                        Text("Saves a Simple Chord Sheet in 4/4 with changes evenly spaced in each measure.")
                        Text("Add printed notes, repeats, or endings in the new chart when needed.")
                    }
                    .padding()
                    .frame(maxWidth: 320, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }
            .font(.subheadline)
            Text("Tap a measure to edit. Compare with Original PDF before saving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pdf.editable-chart.guidance")
        }
    }

    private func nextIssueControl(_ issues: [MeasureLocation], scroll: ScrollViewProxy) -> some View {
        Button {
            guard let next = issues.first(where: { $0.number > (selectedMeasure?.number ?? 0) })
                ?? issues.first else { return }
            selectMeasure(next)
            withAnimation(.easeOut(duration: 0.18)) {
                scroll.scrollTo("row-\(next.row)", anchor: .center)
            }
        } label: {
            if selectedMeasure == nil {
                Label(issues.count == 1 ? "1 measure to check" : "\(issues.count) measures to check",
                      systemImage: "exclamationmark.circle")
            } else {
                Text("Next Check")
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
        .disabled(isSaving || didSave)
        .accessibilityIdentifier("pdf.editable-chart.next-issue")
    }

    private func chartRow(_ current: PDFEditableChartDraft, locations: [MeasureLocation], row: Int,
                          width: CGFloat) -> some View {
        let minimumWidth = CGFloat(locations.count) * minimumMeasureWidth
        return VStack(alignment: .leading, spacing: 5) {
            Text(current.rowLabel(row))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if minimumWidth > width {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        staffRow(current, locations: locations, width: minimumWidth)
                    }
                    .onChange(of: selectedMeasure, initial: true) { _, selection in
                        guard let selection, selection.row == row else { return }
                        scroll.scrollTo(selection.number, anchor: .center)
                    }
                }
            } else {
                staffRow(current, locations: locations, width: width)
            }
        }
    }

    private func staffRow(_ current: PDFEditableChartDraft, locations: [MeasureLocation],
                          width: CGFloat) -> some View {
        PDFReviewSystemLayout(width: width) {
            ForEach(locations) { location in
                measureCell(current, location: location)
                    .id(location.number)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .leading) { barline }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.26)).frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var barline: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.47))
            .frame(width: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func measureCell(_ current: PDFEditableChartDraft, location: MeasureLocation) -> some View {
        let raw = current.rows[location.row][location.column]
        let hasIssue = current.reviewIssue(forMeasure: raw, rowIndex: location.row) != nil
        let content = hasIssue ? "Check" : current.previewText(forMeasure: raw, rowIndex: location.row)
        let isSelected = selectedMeasure == location && !isEditingTitle
        return Button {
            selectMeasure(location)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 3) {
                    Text(location.number, format: .number)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if hasIssue {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(IChartInterfaceStyle.sectionAccent)
                    }
                }
                Text(content.isEmpty ? "—" : content)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(hasIssue ? IChartInterfaceStyle.sectionAccent
                        : content.isEmpty ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 29, alignment: .topLeading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : .clear)
            .overlay(alignment: .trailing) { barline }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.26))
                    .frame(height: isSelected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving || didSave)
        .accessibilityLabel("Measure \(location.number)")
        .accessibilityValue(hasIssue ? "Check chords" : content.isEmpty ? "Empty" : content)
        .accessibilityHint("Edit measure chords.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pdf.editable-chart.select-measure.\(location.number)")
    }

    private func measureInspector(_ current: PDFEditableChartDraft, location: MeasureLocation,
                                  issues: [MeasureLocation], scroll: ScrollViewProxy) -> some View {
        let raw = current.rows[location.row][location.column]
        let issue = current.reviewIssue(forMeasure: raw, rowIndex: location.row)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Measure \(location.number)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if issues.contains(where: { $0 != location }) {
                    nextIssueControl(issues, scroll: scroll)
                }
                Button("Done") {
                    endEditing()
                    selectedMeasure = nil
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("pdf.editable-chart.done-editing")
            }
            IChartTypedTextField(placeholder: "Chords separated by spaces",
                text: measureText(location),
                accessibilityIdentifier: "pdf.editable-chart.measure.\(location.number)",
                accessibilityLabel: "Chords in measure \(location.number)",
                accessibilityHint: inputHint, compact: true)
                .disabled(isSaving || didSave)
            if let issue {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pdf.editable-chart.measure-issue.\(location.number)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private func readError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBanner(message, systemImage: "doc.text.magnifyingglass",
                         identifier: "pdf.editable-chart.read-error")
            if canRetryReading {
                Button("Try Again") { Task { await readDraft() } }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("pdf.editable-chart.retry")
            }
            Divider()
            originalPDF()
        }
    }

    private var inputHint: String {
        "Choose Keyboard to type. Choose Scribble, then tap the field with Apple Pencil before writing."
    }

    private var canSave: Bool {
        guard conversionUnavailableMessage == nil,
              let draft, !isReading, !isSaving, !didSave,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !draft.rows.isEmpty && draft.rows.enumerated().allSatisfy { rowIndex, row in
            !row.isEmpty && row.allSatisfy { draft.reviewIssue(forMeasure: $0, rowIndex: rowIndex) == nil }
        }
    }

    private func measureLocations(in current: PDFEditableChartDraft) -> [[MeasureLocation]] {
        var number = 0
        return current.rows.enumerated().map { row, measures in
            let page = current.sourcePageNumber(forRow: row) ?? 1
            return measures.indices.map { column in
                number += 1
                return MeasureLocation(row: row, column: column, number: number, page: page)
            }
        }
    }

    private func measureText(_ location: MeasureLocation) -> Binding<String> {
        Binding(
            get: { draft?.rows[location.row][location.column] ?? "" },
            set: { draft?.rows[location.row][location.column] = $0 }
        )
    }

    @MainActor
    private func selectMeasure(_ location: MeasureLocation) {
        guard selectedMeasure != location || isEditingTitle else { return }
        endEditing()
        isEditingTitle = false
        selectedMeasure = location
        sourceMeasure = location
    }

    @MainActor
    private func finishTitleEditing() {
        endEditing()
        if draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            isEditingTitle = false
        }
    }

    @MainActor
    private func readDraft() async {
        guard !isReading, conversionUnavailableMessage == nil else { return }
        isReading = true
        errorMessage = nil
        canRetryReading = false
        defer { isReading = false }
        do {
            let recognized = try await PDFEditableChartReader.read(from: url, title: title)
            guard !Task.isCancelled else { return }
            draft = recognized
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            canRetryReading = error as? PDFEditableChartReadError == .unavailable
        }
    }

    @MainActor
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @MainActor
    private func saveDraft() async {
        guard !isSaving, !didSave else { return }
        endEditing()
        guard canSave, let draft else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let chart = try draft.makeChart(sourcePDFLibraryItemID: sourcePDFLibraryItemID)
            if await onSave(chart) {
                didSave = true
            } else {
                errorMessage = "The chart could not be saved. Your review is still here. Try Save as New Chart again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct MeasureLocation: Identifiable, Equatable {
        let row: Int
        let column: Int
        let number: Int
        let page: Int
        var id: Int { number }
    }
}

/// Gives every measure in the system the height required by the longest chord line.
private struct PDFReviewSystemLayout: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measureWidth = width / CGFloat(max(1, subviews.count))
        let measureProposal = ProposedViewSize(width: measureWidth, height: nil)
        let height = subviews.map { $0.sizeThatFits(measureProposal).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measureWidth = width / CGFloat(max(1, subviews.count))
        let measureProposal = ProposedViewSize(width: measureWidth, height: bounds.height)
        for (index, measure) in subviews.enumerated() {
            measure.place(at: CGPoint(x: bounds.minX + CGFloat(index) * measureWidth, y: bounds.minY),
                          anchor: .topLeading, proposal: measureProposal)
        }
    }
}
