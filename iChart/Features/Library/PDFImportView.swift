import SwiftUI
import UniformTypeIdentifiers

/// A local Files import. Capture and editable-chart conversion have separate
/// entry points; importing here only preserves the original PDF pages.
struct IChartPDFImportButton: View {
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    @AppStorage("iChartHomeAppearanceMode") private var appearanceMode = "light"
    let identifier: String
    let onImported: (IChartPDFLibraryItem) -> Void
    @State private var showingFilePicker = false
    @State private var selection: IChartPDFImportSelection?
    @State private var importedItem: IChartPDFLibraryItem?
    @State private var pickerError: String?

    var body: some View {
        Button {
            showingFilePicker = true
        } label: {
            Label("Import PDF", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier(identifier)
        .disabled(pdfStore.recoveryErrorMessage != nil)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { selection = IChartPDFImportSelection(url: url) }
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError {
                    pickerError = error.localizedDescription
                }
            }
        }
        .sheet(item: $selection, onDismiss: finishImport) { selection in
            IChartPDFImportConfirmationView(sourceURL: selection.url) { item in
                importedItem = item
            }
            .environmentObject(pdfStore)
            .preferredColorScheme(appearanceMode == "dark" ? .dark : .light)
            .environment(\.colorScheme, appearanceMode == "dark" ? .dark : .light)
        }
        .alert("Couldn’t Choose PDF", isPresented: Binding(
            get: { pickerError != nil },
            set: { if !$0 { pickerError = nil } }
        )) {
            Button("OK", role: .cancel) { pickerError = nil }
        } message: {
            Text(pickerError ?? "Choose the PDF again in Files.")
        }
    }

    private func finishImport() {
        guard let importedItem else { return }
        self.importedItem = nil
        // The import sheet has closed before the caller opens a preview or
        // updates its selection, avoiding overlapping sheet presentations.
        onImported(importedItem)
    }
}

private struct IChartPDFImportSelection: Identifiable {
    let id = UUID()
    let url: URL
}

struct IChartPDFImportConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pdfStore: IChartPDFLibraryStore
    let sourceURL: URL
    let onImported: (IChartPDFLibraryItem) -> Void
    @State private var title: String
    @State private var isTitleFocused = false
    @State private var importTask: Task<Void, Never>?
    @State private var isCanceling = false
    @State private var errorMessage: String?

    init(sourceURL: URL, onImported: @escaping (IChartPDFLibraryItem) -> Void) {
        self.sourceURL = sourceURL
        self.onImported = onImported
        _title = State(initialValue: sourceURL.deletingPathExtension().lastPathComponent)
    }

    private var isImporting: Bool { importTask != nil }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    IChartTypedTextField(placeholder: "Chart Title", text: $title, isFocused: $isTitleFocused,
                        autocapitalizationType: .words, autocorrectionType: .yes, borderStyle: .roundedRect)
                        .frame(minHeight: 44)
                        .disabled(isImporting)
                        .accessibilityIdentifier("pdf.import.title")
                }
                Section("Original PDF") {
                    Text(sourceURL.lastPathComponent)
                        .lineLimit(3)
                        .accessibilityIdentifier("pdf.import.filename")
                    Text("iChart saves its own copy for offline reading and setlists. The original pages stay as they are.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if isImporting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(isCanceling ? "Canceling import…" : "Saving PDF for offline use…")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pdf.import.progress")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("pdf.import.error")
                }
            }
            .navigationTitle("Import PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .disabled(isCanceling)
                        .accessibilityIdentifier("pdf.import.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: beginImport)
                        .disabled(trimmedTitle.isEmpty || isImporting)
                        .accessibilityIdentifier("pdf.import.save")
                }
            }
        }
        .interactiveDismissDisabled(isImporting)
        .onDisappear { importTask?.cancel() }
    }

    private func beginImport() {
        guard !isImporting, !trimmedTitle.isEmpty else { return }
        isTitleFocused = false
        errorMessage = nil
        let importTitle = trimmedTitle
        importTask = Task { @MainActor in
            do {
                // The service holds security-scoped access through its
                // coordinated background read, validates, and commits locally.
                let item = try await pdfStore.importPDF(from: sourceURL, title: importTitle)
                onImported(item)
                importTask = nil
                dismiss()
            } catch is CancellationError {
                importTask = nil
                dismiss()
            } catch {
                importTask = nil
                isCanceling = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel() {
        if let importTask {
            isCanceling = true
            importTask.cancel()
        } else {
            dismiss()
        }
    }
}
