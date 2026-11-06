import PDFKit
import SwiftUI
import UIKit

struct PDFExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(IChartAppAppearance.preferenceKey) private var appAppearanceValue = IChartAppAppearance.light.rawValue
    let exportedPDF: ExportedPDF
    var source: IChartPDFLibrarySource? = nil
    var pdfItemID: UUID? = nil
    @State private var showingShareSheet = false
    @State private var showingAddToSetlist = false

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
    }

    private var exportSummary: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(pdfItemID == nil ? "Check this reading copy, then Share it." : "Read this saved PDF, Share it, or add it to a setlist.")
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
                .tint(IChartTourStyle.orange)
                .accessibilityHint("Choose a setlist for this saved PDF.")
                .accessibilityIdentifier("pdf.preview.add-to-setlist")
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
                    metadataPill("Original PDF")
                }
                if let layoutStyle = exportedPDF.layoutStyle {
                    metadataPill(layoutStyle.displayText)
                }
                if let transpositionText = exportedPDF.transpositionText
                    ?? (source == .forumDownload ? ForumPDFInstrumentSnapshot.unknownViewText : nil) {
                    metadataPill(transpositionText)
                }
                metadataPill(exportedPDF.pageCountText)
            }
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("pdf.preview.metadata")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .ichartWarmPanel(cornerRadius: 0)
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PDFDocumentView: UIViewRepresentable {
    let url: URL

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
        guard pdfView.document?.documentURL != url else {
            return
        }

        pdfView.document = PDFDocument(url: url)
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
