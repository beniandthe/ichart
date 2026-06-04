import Foundation

struct ExportedPDF: Identifiable, Hashable {
    let url: URL
    let chartTitle: String
    let layoutStyle: ChartLayoutStyle
    let transpositionView: TranspositionView
    let chordTranspositionSemitones: Int
    let pageCount: Int
    let fileSizeBytes: Int
    let exportedAt: Date

    var id: URL { url }

    var fileName: String {
        url.lastPathComponent
    }

    var navigationTitle: String {
        let trimmedTitle = chartTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmedTitle
    }

    var pageCountText: String {
        pageCount == 1 ? "1 page" : "\(pageCount) pages"
    }

    var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(fileSizeBytes),
            countStyle: .file
        )
    }

    var transpositionText: String {
        guard chordTranspositionSemitones != 0 else {
            return transpositionView.displayText
        }

        return "\(transpositionView.displayText) · \(chordTranspositionDisplayText)"
    }

    private var chordTranspositionDisplayText: String {
        switch Chart.normalizedChordTranspositionSemitones(chordTranspositionSemitones) {
        case 0:
            return "Written"
        case 1:
            return "+1 half step"
        default:
            return "+\(Chart.normalizedChordTranspositionSemitones(chordTranspositionSemitones)) half steps"
        }
    }
}

protocol ChartExporting {
    func exportPDF(for chart: Chart) async throws -> ExportedPDF
}

#if canImport(UIKit)
import PDFKit
import UIKit

struct PDFChartExporter: ChartExporting {
    let exportDirectory: URL
    let fileManager: FileManager

    init(exportDirectory: URL, fileManager: FileManager = .default) {
        self.exportDirectory = exportDirectory
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) -> PDFChartExporter {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return PDFChartExporter(
            exportDirectory: baseDirectory.appendingPathComponent("SmartChartExports", isDirectory: true),
            fileManager: fileManager
        )
    }

    func exportPDF(for chart: Chart) async throws -> ExportedPDF {
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let outputURL = exportDirectory.appendingPathComponent(exportFileName(for: chart), isDirectory: false)
        let renderer = ChartPDFRenderer(chart: chart)
        let pdfData = await MainActor.run {
            renderer.render()
        }

        try pdfData.write(to: outputURL, options: .atomic)
        return ExportedPDF(
            url: outputURL,
            chartTitle: chart.title,
            layoutStyle: chart.layoutStyle,
            transpositionView: chart.defaultTranspositionView,
            chordTranspositionSemitones: chart.chordTranspositionSemitones,
            pageCount: PDFDocument(data: pdfData)?.pageCount ?? 1,
            fileSizeBytes: pdfData.count,
            exportedAt: Date()
        )
    }

    func exportFileName(for chart: Chart) -> String {
        var components = [
            Self.sanitizedFileNameStem(from: chart.title),
            chart.layoutStyle.displayText,
            chart.defaultTranspositionView.displayText
        ]

        if chart.chordTranspositionSemitones != 0 {
            components.append(chart.chordTranspositionDisplayText)
        }

        return "\(components.joined(separator: " - ")).pdf"
    }

    static func sanitizedFileNameStem(from title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedTitle.isEmpty ? "Smart Chart" : trimmedTitle
        let stripped = fallback.replacingOccurrences(
            of: #"[\\/:*?"<>|\p{C}]+"#,
            with: " ",
            options: .regularExpression
        )
        let collapsedWhitespace = stripped.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let cleaned = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Smart Chart" : cleaned
    }
}

private struct ChartPDFRenderer {
    let chart: Chart

    private let layoutCanvasWidth: CGFloat = 932
    private let minimumLayoutCanvasHeight: CGFloat = 1_100

    func render() -> Data {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: layoutCanvasWidth, height: minimumLayoutCanvasHeight)
        )
        let pageRect = CGRect(origin: .zero, size: pageLayout.paperFrame.size)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Smart Chart",
            kCGPDFContextTitle as String: chart.title
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            UIBezierPath(rect: pageRect).fill()

            guard let cgContext = UIGraphicsGetCurrentContext() else {
                return
            }

            cgContext.saveGState()
            cgContext.translateBy(
                x: -pageLayout.paperFrame.minX,
                y: -pageLayout.paperFrame.minY
            )
            drawLeadSheetPage(pageLayout, in: cgContext)
            cgContext.restoreGState()
        }
    }

    private func drawLeadSheetPage(_ pageLayout: LeadSheetPageLayout, in context: CGContext) {
        let renderer = LeadSheetNotationRenderer(chart: chart)
        renderer.drawPaper(pageLayout.paperFrame, in: context, showsShadow: false)
        renderer.drawHeader(pageLayout.header)
        if chart.headerInputMode == .handwritten {
            LeadSheetSavedInkRenderer.drawHeaderInk(chart.pageHandwrittenHeaderData, in: pageLayout)
        }

        for system in pageLayout.systems {
            drawSystem(system, using: renderer)
        }

        LeadSheetSavedInkRenderer.drawFreehandSymbols(pageLayout.freehandSymbolLayouts(for: chart))
        LeadSheetSavedInkRenderer.drawPageInk(chart.pageHandwrittenNotationData, in: pageLayout)
        LeadSheetSavedInkRenderer.drawChordInk(chart.pageHandwrittenChordData, in: pageLayout)
    }

    private func drawSystem(_ system: LeadSheetSystemLayout, using renderer: LeadSheetNotationRenderer) {
        if let sectionTextFrame = system.sectionTextFrame,
           let sectionText = system.sectionText {
            renderer.drawSectionText(sectionText, in: sectionTextFrame)
        }

        if let roadmapTextFrame = system.roadmapTextFrame,
           let roadmapText = system.roadmapText {
            renderer.drawRoadmapText(roadmapText, in: roadmapTextFrame)
        }

        for roadmapMarkerLayout in system.roadmapMarkerLayouts {
            renderer.drawRoadmapMarker(roadmapMarkerLayout)
        }

        for endingLayout in system.endingLayouts {
            renderer.drawEnding(endingLayout)
        }

        renderer.drawStaffLines(for: system)

        if let clefFrame = system.clefFrame {
            renderer.drawClef(in: clefFrame)
        }

        renderer.drawKeySignature(system.keySignatureLayouts)

        if let timeSignatureFrame = system.timeSignatureFrame {
            renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
        }

        if let firstMeasure = system.measures.first,
           !firstMeasure.repeatMarkerLayouts.contains(where: { $0.edge == .leading }) {
            renderer.drawLeadingBarline(
                firstMeasure.leadingBarline ?? .single,
                at: firstMeasure.frame.minX,
                from: firstMeasure.staffFrame.minY,
                to: firstMeasure.staffFrame.maxY
            )
        }

        for measure in system.measures {
            drawMeasure(measure, using: renderer)
        }
    }

    private func drawMeasure(_ measure: LeadSheetMeasureLayout, using renderer: LeadSheetNotationRenderer) {
        drawRepeatMarkers(measure.repeatMarkerLayouts.filter { $0.edge == .leading }, using: renderer)

        for chordLayout in measure.chordLayouts {
            renderer.drawChord(chordLayout)
        }

        for noteLayout in measure.noteLayouts {
            renderer.drawNote(noteLayout)
        }

        for cueTextLayout in measure.cueTextLayouts {
            renderer.drawCueText(cueTextLayout)
        }

        drawSavedMeasureRhythmicNotation(measure)

        if let meterChange = measure.meterChange,
           let meterChangeFrame = measure.meterChangeFrame {
            renderer.drawTimeSignature(meterChange, in: meterChangeFrame)
        }

        if measure.isOpen && chart.layoutStyle != .simpleChordSheet {
            renderer.drawOpenMeasureHint(measure)
        } else if measure.repeatMarkerLayouts.contains(where: { $0.edge == .trailing }) {
            drawRepeatMarkers(measure.repeatMarkerLayouts.filter { $0.edge == .trailing }, using: renderer)
        } else {
            renderer.drawBarline(measure.barlineAfter, in: measure.trailingBarlineFrame)
        }
    }

    private func drawRepeatMarkers(
        _ repeatMarkers: [LeadSheetRepeatMarkerLayout],
        using renderer: LeadSheetNotationRenderer
    ) {
        for repeatMarker in repeatMarkers {
            renderer.drawRepeatMarker(repeatMarker)
        }
    }

    private func drawSavedMeasureRhythmicNotation(_ measure: LeadSheetMeasureLayout) {
        guard let sourceMeasureID = measure.sourceMeasureID else {
            return
        }

        LeadSheetSavedInkRenderer.drawRhythmicNotationInk(
            chart.measure(id: sourceMeasureID)?.handwrittenRhythmicNotationData,
            in: measure
        )
    }
}
#endif
