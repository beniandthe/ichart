import PDFKit
import SwiftUI
import UIKit

struct PDFExportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let exportedPDF: ExportedPDF
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                exportSummary

                Divider()

                PDFDocumentView(url: exportedPDF.url)
                    .background(Color(uiColor: .systemBackground))
            }
                .navigationTitle(exportedPDF.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
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
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(items: [exportedPDF.url])
        }
    }

    private var exportSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("PDF ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer(minLength: 12)

                Text(exportedPDF.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(exportedPDF.fileName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                metadataPill(exportedPDF.layoutStyle.displayText)
                metadataPill(exportedPDF.transpositionText)
                metadataPill(exportedPDF.pageCountText)
                metadataPill(exportedPDF.fileSizeText)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
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
