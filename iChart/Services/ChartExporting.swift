import Foundation

struct ExportedPDF: Identifiable, Hashable {
    let url: URL
    let chartTitle: String
    // Personal PDFs retain their page content and have no native chart settings.
    let layoutStyle: ChartLayoutStyle?
    let transpositionView: TranspositionView?
    let chordTranspositionSemitones: Int?
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

    var transpositionText: String? {
        guard let transpositionView, let chordTranspositionSemitones else {
            return layoutStyle == nil ? nil : ForumPDFInstrumentSnapshot.unknownViewText
        }
        guard chordTranspositionSemitones != 0 else {
            return transpositionView.displayText
        }

        return "\(transpositionView.displayText) · \(Chart.intervalDisplayText(forNormalizedSemitones: chordTranspositionSemitones))"
    }
}

struct ForumPDFCredit: Hashable {
    let creatorDisplayName: String
    let forumPostID: UUID
    let exportedAt: Date

    var footerText: String {
        let dateText = Self.dateFormatter.string(from: exportedAt)
        return "Shared from iChart Forums - Creator: \(creatorDisplayName) - Post: \(forumPostID.uuidString) - Exported: \(dateText)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct ChartPDFExportContext: Hashable {
    var forumCredit: ForumPDFCredit?
    var showsIChartCredit: Bool = false

    static let standard = ChartPDFExportContext(forumCredit: nil)

    static func personalChart(entitlements: AppEntitlements, now: Date = Date()) -> Self {
        let entitlements = entitlements.evaluated(at: now)
        // Grace keeps local Pro benefits even though its effective plan is free.
        guard entitlements.accessPolicy.offersPaidPurchases,
              entitlements.activePlan == .free,
              entitlements.subscription.status != .proGrace else { return .standard }
        return ChartPDFExportContext(forumCredit: nil, showsIChartCredit: true)
    }
}

protocol ChartExporting {
    func exportPDF(for chart: Chart, context: ChartPDFExportContext) async throws -> ExportedPDF
}

extension ChartExporting {
    func exportPDF(for chart: Chart) async throws -> ExportedPDF {
        try await exportPDF(for: chart, context: .standard)
    }
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
        let baseDirectory = IChartStorageNamespace.cachesDirectory(fileManager: fileManager)

        return PDFChartExporter(
            exportDirectory: baseDirectory.appendingPathComponent("iChartExports", isDirectory: true),
            fileManager: fileManager
        )
    }

    func exportPDF(for chart: Chart, context: ChartPDFExportContext) async throws -> ExportedPDF {
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Preview/share/forum tasks may retain an earlier export while a new
        // export of a same-title chart is generated. Keep the human filename,
        // but give each operation its own directory so no result is replaced.
        let outputDirectory = exportDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: false,
            attributes: nil
        )
        do {
            let outputURL = outputDirectory.appendingPathComponent(exportFileName(for: chart), isDirectory: false)
            let renderer = ChartPDFRenderer(chart: chartForPDF(chart), exportContext: context)
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
        } catch {
            // This operation created the directory above. Never clean the
            // shared export root or any previously returned export URL.
            try? fileManager.removeItem(at: outputDirectory)
            throw error
        }
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

    private func chartForPDF(_ chart: Chart) -> Chart {
        guard chart.usesPaperMeasureLayout,
              chart.pageHandwrittenNotationData == nil, chart.pageHandwrittenChordData == nil,
              chart.freeInkArticulations.isEmpty, chart.freehandSymbols.isEmpty,
              chart.sectionLabels.isEmpty, chart.cueTexts.isEmpty, chart.roadmapObjects.isEmpty,
              chart.keyChanges.isEmpty, chart.timeSignatureChanges.isEmpty else { return chart }
        let lastAuthoredRow = chart.systems.lastIndex { system in
            system.startsNewPage || system.measures.contains { measure in
                measure.authoringState == .committed
                    || measure.paperLayout?.leadingBarline != nil
                    || !measure.chordEvents.isEmpty || !measure.pitchedNoteEvents.isEmpty
                    || measure.rhythmMap != nil || measure.handwrittenRhythmicNotationData != nil
                    || measure.meterOverride != nil || !measure.cueTextIDs.isEmpty || !measure.roadmapObjectIDs.isEmpty
            }
        } ?? 0
        var exported = chart
        exported.systems = Array(chart.systems.prefix(lastAuthoredRow + 1))
        return exported
    }

    static func sanitizedFileNameStem(from title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedTitle.isEmpty ? "iChart" : trimmedTitle
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
        return cleaned.isEmpty ? "iChart" : cleaned
    }
}

private struct ChartPDFRenderer {
    let chart: Chart
    let exportContext: ChartPDFExportContext

    private var layoutCanvasWidth: CGFloat {
        LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart)
            ?? LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth
    }
    private let minimumLayoutCanvasHeight: CGFloat = 1_100
    private let iChartCreditStripHeight: CGFloat = 28

    func render() -> Data {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: layoutCanvasWidth, height: minimumLayoutCanvasHeight)
        )
        let firstPageRect = CGRect(origin: .zero, size: pageLayout.paperFrame.size)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "iChart",
            kCGPDFContextTitle as String: chart.title
        ]
        if let forumCredit = exportContext.forumCredit {
            format.documentInfo[kCGPDFContextSubject as String] = ForumPDFInstrumentSnapshot(
                chart: chart, forumPostID: forumCredit.forumPostID).subjectText
        }

        let renderer = UIGraphicsPDFRenderer(bounds: firstPageRect, format: format)

        return renderer.pdfData { rendererContext in
            for paperPage in pageLayout.pages {
                let pageRect = CGRect(origin: .zero, size: paperPage.frame.size)
                rendererContext.beginPage(withBounds: pageRect, pageInfo: [:])
                UIColor.white.setFill()
                UIBezierPath(rect: pageRect).fill()

                guard let cgContext = UIGraphicsGetCurrentContext() else {
                    return
                }

                let showsIChartCredit = exportContext.showsIChartCredit
                    && exportContext.forumCredit == nil && paperPage.index == 0
                cgContext.saveGState()
                if showsIChartCredit {
                    // Free Ink can occupy the normal footer margin. Fit the
                    // entire original paper content above a separate strip,
                    // keeping its proportions, page count and saved geometry.
                    // Paper ruling and borders retain their original scale.
                    LeadSheetNotationRenderer(chart: chart).drawPaper(pageRect,
                        in: cgContext, showsShadow: false)
                    let contentScale = max(1, pageRect.height - iChartCreditStripHeight) / pageRect.height
                    cgContext.translateBy(x: (pageRect.width - pageRect.width * contentScale) / 2, y: 0)
                    cgContext.scaleBy(x: contentScale, y: contentScale)
                }
                cgContext.translateBy(
                    x: -paperPage.frame.minX,
                    y: -paperPage.frame.minY
                )
                if showsIChartCredit { cgContext.clip(to: paperPage.frame) }
                drawLeadSheetPage(pageLayout, paperPage: paperPage,
                    drawsPaper: !showsIChartCredit, in: cgContext)
                cgContext.restoreGState()
                drawForumCreditFooter(in: pageRect)
                if showsIChartCredit { drawIChartCredit(in: pageRect) }
            }
        }
    }

    private func drawIChartCredit(in pageRect: CGRect) {
        let footerRect = CGRect(x: pageRect.minX + 46, y: pageRect.maxY - 23,
            width: pageRect.width - 92, height: 18)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.black.withAlphaComponent(0.45),
            .paragraphStyle: paragraphStyle
        ]
        NSString(string: "Made with iChart").draw(in: footerRect, withAttributes: attributes)
    }

    private func drawForumCreditFooter(in pageRect: CGRect) {
        guard let forumCredit = exportContext.forumCredit else {
            return
        }

        let footerRect = CGRect(
            x: pageRect.minX + 46,
            y: pageRect.maxY - 34,
            width: pageRect.width - 92,
            height: 18
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.black.withAlphaComponent(0.45),
            .paragraphStyle: paragraphStyle
        ]

        NSString(string: forumCredit.footerText).draw(in: footerRect, withAttributes: attributes)
    }

    private func drawLeadSheetPage(
        _ pageLayout: LeadSheetPageLayout,
        paperPage: LeadSheetPaperPageLayout,
        drawsPaper: Bool,
        in context: CGContext
    ) {
        let renderer = LeadSheetNotationRenderer(chart: chart)
        if drawsPaper { renderer.drawPaper(paperPage.frame, in: context, showsShadow: false) }
        if paperPage.includesHeader {
            renderer.drawHeader(pageLayout.header)
        }
        if paperPage.includesHeader,
           chart.headerInputMode == .handwritten {
            LeadSheetSavedInkRenderer.drawHeaderInk(
                chart.pageHandwrittenHeaderData,
                coordinateSpace: chart.pageHandwrittenHeaderCoordinateSpace,
                in: pageLayout
            )
        }

        let pageSystems = pageLayout.systems.filter { system in
            paperPage.systemIDs.contains(system.id)
        }
        for system in pageSystems {
            drawSystem(system, paperFrame: paperPage.frame, using: renderer)
        }
        renderer.drawFreeInkArticulations(for: paperPage, pageLayout: pageLayout, in: context)

        context.saveGState()
        UIBezierPath(rect: paperPage.frame).addClip()
        LeadSheetSavedInkRenderer.drawPageInk(
            chart.pageHandwrittenNotationData,
            coordinateSpace: chart.pageHandwrittenNotationCoordinateSpace,
            chart: chart,
            in: pageLayout
        )
        context.restoreGState()
    }

    private func drawSystem(
        _ system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        using renderer: LeadSheetNotationRenderer
    ) {
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

        if let keyTextFrame = system.keyTextFrame,
           let keyText = system.keyText {
            renderer.drawKeyText(keyText, in: keyTextFrame)
        }

        if let timeSignatureFrame = system.timeSignatureFrame {
            renderer.drawTimeSignature(chart.defaultMeter, in: timeSignatureFrame)
        }

        var drawnRepeatMarkerIDs = Set<String>()
        if let firstMeasure = system.measures.first, !firstMeasure.usesPaperMeasureLayout {
            let leadingMarkers = LeadSheetRepeatBoundaryPolicy.leadingMarkers(atStartOf: firstMeasure)
            if leadingMarkers.isEmpty {
                renderer.drawLeadingBarline(
                    firstMeasure.leadingBarline ?? .single,
                    at: firstMeasure.leadingBarlineX,
                    from: firstMeasure.staffFrame.minY,
                    to: firstMeasure.staffFrame.maxY
                )
            } else {
                drawRepeatMarkers(leadingMarkers, using: renderer)
                drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(leadingMarkers))
            }
        }

        for (measureIndex, measure) in system.measures.enumerated() {
            let precedingMeasure = measureIndex > 0 ? system.measures[measureIndex - 1] : nil
            if let leadingBarline = measure.explicitPaperLeadingBarline(after: precedingMeasure) {
                renderer.drawLeadingBarline(
                    leadingBarline,
                    at: measure.leadingBarlineX,
                    from: measure.staffFrame.minY,
                    to: measure.staffFrame.maxY
                )
            }
            let nextMeasureIndex = measureIndex + 1
            let nextMeasure = system.measures.indices.contains(nextMeasureIndex)
                ? system.measures[nextMeasureIndex]
                : nil
            drawMeasure(
                measure,
                in: system,
                paperFrame: paperFrame,
                nextMeasure: nextMeasure,
                drawnRepeatMarkerIDs: &drawnRepeatMarkerIDs,
                using: renderer
            )
        }

        if LeadSheetSimpleChordTerminalBarlineGeometry.shouldDrawStandaloneTerminalBarline(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: chart.layoutStyle
        ) {
            renderer.drawSimpleChordStanzaTerminalBarline(for: system, paperFrame: paperFrame)
        }
    }

    private func drawMeasure(
        _ measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        nextMeasure: LeadSheetMeasureLayout?,
        drawnRepeatMarkerIDs: inout Set<String>,
        using renderer: LeadSheetNotationRenderer
    ) {
        let leadingMarkers = measure.repeatMarkerLayouts.filter {
            $0.edge == .leading && !drawnRepeatMarkerIDs.contains($0.id)
        }
        drawRepeatMarkers(leadingMarkers, using: renderer)
        drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(leadingMarkers))

        for chordLayout in renderer.fittedChordLayouts(measure.chordLayouts) {
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

        let boundary = LeadSheetSimpleChordTerminalBarlineGeometry.renderedBoundary(
            after: measure,
            before: nextMeasure,
            excludingRepeatMarkerIDs: drawnRepeatMarkerIDs,
            in: system,
            paperFrame: paperFrame,
            layoutStyle: chart.layoutStyle
        )

        switch boundary {
        case .repeatBoundary(let repeatBoundaryMarkers, let trailingLineX):
            drawRepeatMarkers(
                repeatBoundaryMarkers,
                trailingLineX: trailingLineX,
                using: renderer
            )
            drawnRepeatMarkerIDs.formUnion(LeadSheetRepeatBoundaryPolicy.markerIDs(repeatBoundaryMarkers))
        case .normalBarline(let barline, let frame):
            renderer.drawBarline(barline, in: frame)
        case .none:
            if measure.isOpen && !measure.usesPaperMeasureLayout && chart.layoutStyle != .simpleChordSheet {
                renderer.drawOpenMeasureHint(measure)
            }
        }
    }

    private func drawRepeatMarkers(
        _ repeatMarkers: [LeadSheetRepeatMarkerLayout],
        trailingLineX: CGFloat? = nil,
        using renderer: LeadSheetNotationRenderer
    ) {
        guard !repeatMarkers.isEmpty else {
            return
        }

        renderer.drawRepeatBoundary(
            repeatMarkers,
            trailingLineX: trailingLineX
        )
    }

    private func drawSavedMeasureRhythmicNotation(_ measure: LeadSheetMeasureLayout) {
        guard let sourceMeasureID = measure.sourceMeasureID else {
            return
        }

        let sourceMeasure = chart.measure(id: sourceMeasureID)
        LeadSheetSavedInkRenderer.drawRhythmicNotationInk(
            sourceMeasure?.handwrittenRhythmicNotationData,
            coordinateSpace: sourceMeasure?.handwrittenRhythmicNotationCoordinateSpace,
            in: measure
        )
    }
}
#endif
