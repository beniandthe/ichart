import SwiftUI
import UIKit

/// Keeps the extracted draft beside its saved source until the user accepts it.
struct PDFEditableChartReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let title: String
    let sourcePDFLibraryItemID: UUID
    var conversionUnavailableMessage: String? = nil
    let onSave: (Chart) async -> Bool

    @State private var draft: PDFEditableChartDraft?
    @State private var showingOriginalPDF = false
    @State private var isReading = false
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?
    @State private var canRetryReading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reviewInstruction
                if draft != nil {
                    Picker("Review view", selection: $showingOriginalPDF) {
                        Text("Chords").tag(false)
                        Text("Original PDF").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("pdf.editable-chart.source-toggle")
                }
                Divider()
                if let draft {
                    ZStack {
                        draftFields(draft)
                            .opacity(showingOriginalPDF ? 0 : 1)
                            .allowsHitTesting(!showingOriginalPDF)
                            .accessibilityHidden(showingOriginalPDF)
                        PDFDocumentView(url: url)
                            .ichartDocumentDisplayAppearance()
                            .opacity(showingOriginalPDF ? 1 : 0)
                            .allowsHitTesting(showingOriginalPDF)
                            .accessibilityHidden(!showingOriginalPDF)
                            .accessibilityIdentifier("pdf.editable-chart.original")
                    }
                } else if conversionUnavailableMessage != nil {
                    PDFDocumentView(url: url)
                        .ichartDocumentDisplayAppearance()
                } else if errorMessage == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading PDF chords…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pdf.editable-chart.reading")
                } else {
                    VStack(spacing: 16) {
                        Text(errorMessage ?? "This PDF could not be read.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("pdf.editable-chart.read-error")
                        if canRetryReading {
                            Button("Try Again") { Task { await readDraft() } }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("pdf.editable-chart.retry")
                        }
                        PDFDocumentView(url: url)
                            .ichartDocumentDisplayAppearance()
                    }
                    .padding()
                }
            }
            .navigationTitle("Review PDF Chords")
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

    private var reviewInstruction: some View {
        VStack(spacing: 6) {
            Text("Check every chord and measure against the Original PDF. Separate chords with spaces, then tap Save as New Chart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Creates a Simple Chord Sheet in 4/4, with chords evenly spaced within each measure.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if draft?.usesDrawnBarlines == true {
                Text("Leave a measure blank when the PDF shows no chord change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Printed notes, drawn repeat signs, and ending brackets are not copied. Add needed notation in the new chart.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let conversionUnavailableMessage {
                Text(draft == nil ? conversionUnavailableMessage
                    : "\(conversionUnavailableMessage) Your review is kept here while this screen stays open.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pdf.editable-chart.access-guidance")
            }
            if isSaving {
                ProgressView("Saving chart…")
                    .accessibilityIdentifier("pdf.editable-chart.saving")
            } else if didSave {
                Text("Chart saved.")
                    .font(.subheadline)
                    .accessibilityIdentifier("pdf.editable-chart.saved")
            } else if draft != nil, let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("pdf.editable-chart.save-error")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("pdf.editable-chart.guidance")
    }

    private func draftFields(_ current: PDFEditableChartDraft) -> some View {
        List {
            Section("Chart title") {
                IChartTypedTextField(placeholder: "Chart title", text: Binding(
                    get: { draft?.title ?? title },
                    set: { draft?.title = $0 }
                ), autocapitalizationType: .words, autocorrectionType: .yes,
                    accessibilityIdentifier: "pdf.editable-chart.title",
                    accessibilityLabel: "Chart title",
                    accessibilityHint: inputHint, compact: true)
                    .disabled(isSaving || didSave)
                    .background(IChartTypedSheetScrollSupport())
            }
            ForEach(current.rows.indices, id: \.self) { rowIndex in
                Section(current.rowLabel(rowIndex)) {
                    ForEach(current.rows[rowIndex].indices, id: \.self) { measureIndex in
                        let number = measureNumber(rowIndex: rowIndex, measureIndex: measureIndex)
                        VStack(alignment: .leading, spacing: 5) {
                            IChartTypedTextField(
                                placeholder: "Chords in measure \(number)",
                                text: measureText(rowIndex: rowIndex, measureIndex: measureIndex),
                                accessibilityIdentifier: "pdf.editable-chart.measure.\(number)",
                                accessibilityLabel: "Measure \(number)",
                                accessibilityHint: inputHint,
                                compact: true
                            )
                            .disabled(isSaving || didSave)
                            if let issue = current.reviewIssue(forMeasure: current.rows[rowIndex][measureIndex]) {
                                Text(issue)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("pdf.editable-chart.measure-issue.\(number)")
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var inputHint: String {
        "Choose Keyboard to type. Choose Scribble, then tap the field with Apple Pencil before writing."
    }

    private var canSave: Bool {
        guard conversionUnavailableMessage == nil,
              let draft, !isReading, !isSaving, !didSave,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let measures = draft.rows.flatMap { $0 }
        return !measures.isEmpty && measures.allSatisfy { draft.reviewIssue(forMeasure: $0) == nil }
    }

    private func measureNumber(rowIndex: Int, measureIndex: Int) -> Int {
        (draft?.rows.prefix(rowIndex).reduce(0) { $0 + $1.count } ?? 0) + measureIndex + 1
    }

    private func measureText(rowIndex: Int, measureIndex: Int) -> Binding<String> {
        Binding(
            get: { draft?.rows[rowIndex][measureIndex] ?? "" },
            set: { draft?.rows[rowIndex][measureIndex] = $0 }
        )
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
}
