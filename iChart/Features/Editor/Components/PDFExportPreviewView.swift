import PDFKit
import SwiftUI
import UIKit

struct PDFExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(IChartAppAppearance.preferenceKey, store: IChartStorageNamespace.defaults) private var appAppearanceValue = IChartAppAppearance.light.rawValue
    let exportedPDF: ExportedPDF
    var source: IChartPDFLibrarySource? = nil
    var pdfItemID: UUID? = nil
    var editableChartConversionUnavailableMessage: String? = nil
    var onSaveEditableChart: ((Chart) async -> Bool)? = nil
    @State private var showingShareSheet = false
    @State private var showingAddToSetlist = false
    @State private var showingEditableChartReview = false

    private var appearance: IChartAppAppearance {
        IChartAppAppearance(persistedValue: appAppearanceValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                exportSummary

                Divider()

                PDFDocumentView(url: exportedPDF.url)
                    .ichartDocumentDisplayAppearance()
            }
                .navigationTitle(exportedPDF.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(appearance.colorScheme, for: .navigationBar)
                .toolbarBackground(appearance.isDark ? Color.black : Color.white, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                        .accessibilityIdentifier("pdf.preview.done")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.colorScheme, appearance.colorScheme)
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(items: [exportedPDF.url])
        }
        .sheet(isPresented: $showingAddToSetlist) {
            if let pdfItemID { AddPDFToSetlistSheet(pdfItemIDs: [pdfItemID]) }
        }
        .sheet(isPresented: $showingEditableChartReview) {
            if let pdfItemID, let onSaveEditableChart {
                let review = PDFEditableChartReviewView(url: exportedPDF.url, title: exportedPDF.navigationTitle,
                    sourcePDFLibraryItemID: pdfItemID,
                    conversionUnavailableMessage: editableChartConversionUnavailableMessage,
                    onSave: onSaveEditableChart)
                if #available(iOS 18, *) {
                    review.presentationSizing(.page)
                } else {
                    review
                }
            }
        }
    }

    private var canCreateEditableChart: Bool {
        supportsEditableChartConversion && editableChartConversionUnavailableMessage == nil
    }

    private var supportsEditableChartConversion: Bool {
        source == .personalImport && pdfItemID != nil && onSaveEditableChart != nil
    }

    private var exportSummary: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(canCreateEditableChart
                ? "Read this PDF, Share it, add it to a setlist, or choose Create Editable Chart to review its chords."
                : pdfItemID == nil
                    ? "Check this reading copy, then Share it."
                    : "Read this saved PDF, Share it, or add it to a setlist.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pdf.preview.guidance")
            if pdfItemID != nil {
                Button {
                    showingAddToSetlist = true
                } label: {
                    Label("Add to Setlist", systemImage: "music.note.list")
                        .labelStyle(.titleAndIcon)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(IChartInterfaceStyle.actionText)
                .accessibilityHint("Choose a setlist for this saved PDF.")
                .accessibilityIdentifier("pdf.preview.add-to-setlist")
            }
            if supportsEditableChartConversion {
                Button {
                    guard canCreateEditableChart else { return }
                    showingEditableChartReview = true
                } label: {
                    Label("Create Editable Chart", systemImage: "square.and.pencil")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(IChartInterfaceStyle.actionText)
                .disabled(!canCreateEditableChart)
                .accessibilityHint(editableChartConversionUnavailableMessage
                    ?? "Review the chords and measures before saving a new Simple Chord Sheet.")
                .accessibilityIdentifier("pdf.preview.create-editable-chart")
                Text(editableChartConversionUnavailableMessage
                    ?? "For printed chord grids and selectable chords above full-width staff rows in one column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pdf.preview.conversion-guidance")
            }
            Text(exportedPDF.fileName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
                alignment: .center,
                spacing: 8
            ) {
                if source == .personalImport {
                    metadataText("Original PDF")
                }
                if let layoutStyle = exportedPDF.layoutStyle {
                    metadataText(layoutStyle.displayText)
                }
                if let transpositionText = exportedPDF.transpositionText
                    ?? (source == .forumDownload ? ForumPDFInstrumentSnapshot.unknownViewText : nil) {
                    metadataText(transpositionText)
                }
                metadataText(exportedPDF.pageCountText)
            }
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("pdf.preview.metadata")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(IChartInterfaceStyle.cardBackground)
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(.secondary)
    }
}

struct PDFDocumentView: UIViewRepresentable {
    let url: URL
    var pageRequest: PageRequest? = nil

    struct PageRequest: Equatable {
        let number: Int
        let selectionID: Int
    }

    final class Coordinator {
        var previousURL: URL?
        var previousPageRequest: PageRequest?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        // The document display filter handles dark viewing; keep the original
        // paper/surround light so a dark UIKit trait is not inverted twice.
        pdfView.backgroundColor = UIColor(white: 0.96, alpha: 1)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.previousURL != url {
            pdfView.document = PDFDocument(url: url)
            coordinator.previousURL = url
            coordinator.previousPageRequest = nil
        }
        guard coordinator.previousPageRequest != pageRequest else { return }
        coordinator.previousPageRequest = pageRequest
        guard let pageRequest, pageRequest.number > 0,
              let page = pdfView.document?.page(at: pageRequest.number - 1),
              pdfView.currentPage != page else { return }
        pdfView.go(to: page)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        uiViewController.completionWithItemsHandler = nil
    }
}
