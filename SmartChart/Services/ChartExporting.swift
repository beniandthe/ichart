import Foundation

protocol ChartExporting {
    func exportPDF(for chart: Chart) async throws -> URL
}

#if canImport(UIKit)
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

    func exportPDF(for chart: Chart) async throws -> URL {
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
        return outputURL
    }

    private func exportFileName(for chart: Chart) -> String {
        let baseName = sanitizedStem(from: chart.title)
        let viewSuffix = chart.defaultTranspositionView.displayText
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return "\(baseName)-\(viewSuffix).pdf"
    }

    private func sanitizedStem(from title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmedTitle.isEmpty ? "smart-chart" : trimmedTitle.lowercased()
        let collapsed = fallback.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        let cleaned = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "smart-chart" : cleaned
    }
}

private struct ChartPDFRenderer {
    let chart: Chart

    private let pageRect = CGRect(x: 0, y: 0, width: 792, height: 612)
    private let pageMargins = UIEdgeInsets(top: 36, left: 40, bottom: 36, right: 40)
    private let headerHeight: CGFloat = 64
    private let systemSpacing: CGFloat = 18
    private let badgeRowHeight: CGFloat = 24
    private let measureRowHeight: CGFloat = 152
    private let measureGap: CGFloat = 10
    private let blockCornerRadius: CGFloat = 14

    func render() -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Smart Chart",
            kCGPDFContextTitle as String: chart.title
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            var currentPageIndex = 1
            var cursorY = beginPage(index: currentPageIndex, in: context)

            for system in chart.systems {
                let blockHeight = systemHeight(for: system)
                let maxY = pageRect.height - pageMargins.bottom

                if cursorY + blockHeight > maxY {
                    currentPageIndex += 1
                    cursorY = beginPage(index: currentPageIndex, in: context)
                }

                let systemRect = CGRect(
                    x: pageMargins.left,
                    y: cursorY,
                    width: pageRect.width - pageMargins.left - pageMargins.right,
                    height: blockHeight
                )
                drawSystem(system, in: systemRect)
                cursorY = systemRect.maxY + systemSpacing
            }
        }
    }

    private func beginPage(index: Int, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        context.beginPage()

        let headerRect = CGRect(
            x: pageMargins.left,
            y: pageMargins.top,
            width: pageRect.width - pageMargins.left - pageMargins.right,
            height: headerHeight
        )
        drawHeader(in: headerRect, pageIndex: index)

        return headerRect.maxY + 18
    }

    private func drawHeader(in rect: CGRect, pageIndex: Int) {
        drawText(
            chart.title,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.7, height: 28),
            font: chart.documentFont.pdfFont(size: 24, weight: .bold),
            color: UIColor(white: 0.08, alpha: 1)
        )

        let displayedKey = chart.documentKey.transposed(for: chart.defaultTranspositionView)
        let metadata = [
            displayedKey.displayText,
            chart.defaultTranspositionView.displayText,
            chart.defaultMeter.displayText,
            "\(chart.measures.count) measures"
        ].joined(separator: "  •  ")

        drawText(
            metadata,
            in: CGRect(x: rect.minX, y: rect.minY + 32, width: rect.width * 0.75, height: 20),
            font: chart.documentFont.pdfFont(size: 11, weight: .medium),
            color: UIColor(white: 0.35, alpha: 1)
        )

        drawText(
            "Page \(pageIndex)",
            in: CGRect(x: rect.maxX - 120, y: rect.minY + 6, width: 120, height: 18),
            font: chart.documentFont.pdfFont(size: 11, weight: .medium),
            color: UIColor(white: 0.45, alpha: 1),
            alignment: .right
        )

        let dividerPath = UIBezierPath()
        dividerPath.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        dividerPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        dividerPath.lineWidth = 1
        UIColor(white: 0.85, alpha: 1).setStroke()
        dividerPath.stroke()
    }

    private func systemHeight(for system: ChartSystem) -> CGFloat {
        var height = measureRowHeight

        if !roadmapObjects(for: system.id).isEmpty {
            height += badgeRowHeight
        }

        if !sectionLabels(for: system.id).isEmpty {
            height += badgeRowHeight
        }

        return height
    }

    private func drawSystem(_ system: ChartSystem, in rect: CGRect) {
        var cursorY = rect.minY

        let roadmapBadges = roadmapObjects(for: system.id)
        if !roadmapBadges.isEmpty {
            let badgeRect = CGRect(x: rect.minX, y: cursorY, width: rect.width, height: badgeRowHeight)
            drawBadgeRow(
                roadmapBadges.map(\.resolvedDisplayText),
                in: badgeRect,
                fillColor: UIColor(red: 0.98, green: 0.92, blue: 0.84, alpha: 1),
                textColor: UIColor(red: 0.48, green: 0.26, blue: 0.05, alpha: 1)
            )
            cursorY = badgeRect.maxY
        }

        let sectionBadges = sectionLabels(for: system.id)
        if !sectionBadges.isEmpty {
            let badgeRect = CGRect(x: rect.minX, y: cursorY, width: rect.width, height: badgeRowHeight)
            drawBadgeRow(
                sectionBadges.map { $0.text.uppercased() },
                in: badgeRect,
                fillColor: UIColor(red: 0.88, green: 0.93, blue: 0.99, alpha: 1),
                textColor: UIColor(red: 0.12, green: 0.29, blue: 0.56, alpha: 1)
            )
            cursorY = badgeRect.maxY
        }

        let rowRect = CGRect(x: rect.minX, y: cursorY, width: rect.width, height: measureRowHeight)
        drawMeasureRow(system.measures, in: rowRect)
    }

    private func drawBadgeRow(
        _ badges: [String],
        in rect: CGRect,
        fillColor: UIColor,
        textColor: UIColor
    ) {
        var badgeX = rect.minX

        for badge in badges {
            let badgeWidth = badgeWidth(for: badge)
            let badgeRect = CGRect(x: badgeX, y: rect.minY + 2, width: badgeWidth, height: rect.height - 4)

            let path = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height / 2)
            fillColor.setFill()
            path.fill()

            drawText(
                badge,
                in: badgeRect.insetBy(dx: 10, dy: 4),
                font: chart.documentFont.pdfFont(size: 10, weight: .bold),
                color: textColor,
                alignment: .center
            )

            badgeX = badgeRect.maxX + 8
        }
    }

    private func badgeWidth(for badge: String) -> CGFloat {
        let size = textSize(
            for: badge,
            font: chart.documentFont.pdfFont(size: 10, weight: .bold),
            maxSize: CGSize(width: 400, height: badgeRowHeight)
        )
        return size.width + 22
    }

    private func drawMeasureRow(_ measures: [Measure], in rect: CGRect) {
        guard !measures.isEmpty else {
            return
        }

        let totalGap = measureGap * CGFloat(max(0, measures.count - 1))
        let measureWidth = (rect.width - totalGap) / CGFloat(measures.count)

        for (index, measure) in measures.enumerated() {
            let measureX = rect.minX + CGFloat(index) * (measureWidth + measureGap)
            let measureRect = CGRect(x: measureX, y: rect.minY, width: measureWidth, height: rect.height)
            drawMeasure(measure, in: measureRect)
        }
    }

    private func drawMeasure(_ measure: Measure, in rect: CGRect) {
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let cues = cueTexts(for: measure.id)
        let placements = measure.renderedChordPlacements(defaultMeter: chart.defaultMeter).sorted {
            ($0.startPosition.startOffset(in: meter) ?? .greatestFiniteMagnitude) <
                ($1.startPosition.startOffset(in: meter) ?? .greatestFiniteMagnitude)
        }

        let backgroundPath = UIBezierPath(roundedRect: rect, cornerRadius: blockCornerRadius)
        UIColor(white: 0.985, alpha: 1).setFill()
        backgroundPath.fill()
        UIColor(white: 0.84, alpha: 1).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        drawText(
            "M\(measure.index)",
            in: CGRect(x: rect.minX + 12, y: rect.minY + 10, width: 40, height: 14),
            font: chart.documentFont.pdfFont(size: 10, weight: .bold),
            color: UIColor(white: 0.45, alpha: 1)
        )

        drawText(
            meter.displayText,
            in: CGRect(x: rect.maxX - 52, y: rect.minY + 10, width: 40, height: 14),
            font: chart.documentFont.pdfFont(size: 10, weight: .medium),
            color: UIColor(white: 0.45, alpha: 1),
            alignment: .right
        )

        let gridRect = CGRect(
            x: rect.minX + 12,
            y: rect.minY + 30,
            width: rect.width - 24,
            height: 84
        )
        drawRhythmGrid(for: measure, meter: meter, in: gridRect)

        if !placements.isEmpty {
            for (rowIndex, placement) in placements.enumerated() {
                drawChordEvent(
                    placement,
                    rowIndex: rowIndex,
                    meter: meter,
                    in: gridRect
                )
            }
        }

        if !cues.isEmpty {
            let cueText = cues.map(\.text).joined(separator: "  •  ")
            drawText(
                cueText,
                in: CGRect(x: rect.minX + 12, y: rect.maxY - 28, width: rect.width - 24, height: 18),
                font: chart.documentFont.pdfFont(size: 9, weight: .medium),
                color: UIColor(white: 0.38, alpha: 1)
            )
        }
    }

    private func drawRhythmGrid(for measure: Measure, meter: Meter, in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        UIColor(white: 1, alpha: 1).setFill()
        path.fill()
        UIColor(white: 0.9, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()

        let availableWidth = rect.width - 20
        let beatCount = max(1, meter.numerator)
        let beatWidth = availableWidth / CGFloat(beatCount)
        let guideTop = rect.minY + 10
        let guideBottom = rect.maxY - 10

        for beatIndex in 0...beatCount {
            let guideX = rect.minX + 10 + CGFloat(beatIndex) * beatWidth
            let guidePath = UIBezierPath()
            guidePath.move(to: CGPoint(x: guideX, y: guideTop))
            guidePath.addLine(to: CGPoint(x: guideX, y: guideBottom))
            guidePath.lineWidth = beatIndex == beatCount ? 1.2 : 0.8
            guidePath.setLineDash([3, 3], count: 2, phase: 0)
            UIColor(white: 0.87, alpha: 1).setStroke()
            guidePath.stroke()

            guard beatIndex < beatCount else {
                continue
            }

            drawText(
                "\(beatIndex + 1)",
                in: CGRect(x: guideX + 2, y: rect.minY + 2, width: max(18, beatWidth - 4), height: 12),
                font: chart.documentFont.pdfFont(size: 8, weight: .medium),
                color: UIColor(white: 0.6, alpha: 1)
            )
        }

        drawBarline(measure.barlineAfter, in: rect)
    }

    private func drawBarline(_ barline: BarlineType, in rect: CGRect) {
        let thinX = rect.maxX - 9
        let thickX = rect.maxX - 5
        let top = rect.minY + 8
        let bottom = rect.maxY - 8

        switch barline {
        case .single:
            drawLine(from: CGPoint(x: thickX, y: top), to: CGPoint(x: thickX, y: bottom), width: 1, color: UIColor(white: 0.3, alpha: 1))
        case .double:
            drawLine(from: CGPoint(x: thinX, y: top), to: CGPoint(x: thinX, y: bottom), width: 1, color: UIColor(white: 0.3, alpha: 1))
            drawLine(from: CGPoint(x: thickX, y: top), to: CGPoint(x: thickX, y: bottom), width: 1, color: UIColor(white: 0.3, alpha: 1))
        case .final:
            drawLine(from: CGPoint(x: thinX, y: top), to: CGPoint(x: thinX, y: bottom), width: 1, color: UIColor(white: 0.3, alpha: 1))
            drawLine(from: CGPoint(x: thickX, y: top), to: CGPoint(x: thickX, y: bottom), width: 2.6, color: UIColor(white: 0.15, alpha: 1))
        }
    }

    private func drawChordEvent(
        _ placement: MeasureChordPlacement,
        rowIndex: Int,
        meter: Meter,
        in rect: CGRect
    ) {
        let event = placement.chordEvent.transposed(for: chart.defaultTranspositionView)
        let clampedRow = min(rowIndex, 2)
        let rowY = rect.minY + 18 + CGFloat(clampedRow) * 22
        let horizontalInset: CGFloat = 10
        let usableWidth = rect.width - horizontalInset * 2
        let startFraction = placement.startPosition.startOffset(in: meter)
            .map { $0 / meter.measureLengthInWholeNotes }
            ?? 0
        let durationFraction = max(
            0.08,
            min(1, placement.effectiveWholeNoteLength / meter.measureLengthInWholeNotes)
        )
        let startX = rect.minX + horizontalInset + usableWidth * CGFloat(startFraction)
        let durationWidth = max(20, usableWidth * CGFloat(durationFraction))
        let eventColor: UIColor = placement.isAutoFill
            ? UIColor(red: 0.11, green: 0.42, blue: 0.2, alpha: 1)
            : UIColor(red: 0.11, green: 0.22, blue: 0.38, alpha: 1)

        drawText(
            event.symbol.displayText,
            in: CGRect(
                x: startX,
                y: rowY,
                width: max(28, rect.maxX - startX - 12),
                height: 14
            ),
            font: chart.documentFont.pdfFont(size: 13, weight: .semibold),
            color: eventColor
        )

        drawLine(
            from: CGPoint(x: startX, y: rowY + 16),
            to: CGPoint(x: min(rect.maxX - 12, startX + durationWidth), y: rowY + 16),
            width: 1.4,
            color: UIColor(red: 0.18, green: 0.45, blue: 0.77, alpha: 1)
        )

        drawText(
            "\(placement.startPosition.displayText) · \(placement.durationDisplayText)",
            in: CGRect(
                x: startX,
                y: rowY + 18,
                width: max(42, rect.maxX - startX - 12),
                height: 12
            ),
            font: chart.documentFont.pdfFont(size: 8, weight: .medium),
            color: UIColor(white: 0.45, alpha: 1)
        )
    }

    private func drawLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func sectionLabels(for systemID: UUID) -> [SectionLabel] {
        chart.sectionLabels.filter { $0.anchorSystemID == systemID }
    }

    private func roadmapObjects(for systemID: UUID) -> [RoadmapObject] {
        chart.roadmapObjects.filter { $0.anchorSystemID == systemID }
    }

    private func cueTexts(for measureID: UUID) -> [CueText] {
        chart.cueTexts.filter { $0.anchorMeasureID == measureID }
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private func textSize(for text: String, font: UIFont, maxSize: CGSize) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        ).integral.size
    }
}

private extension ChartFontPreset {
    func pdfFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        switch self {
        case .classic:
            return .systemFont(ofSize: size, weight: weight)
        case .rounded:
            return font(size: size, weight: weight, design: .rounded)
        case .serif:
            return font(size: size, weight: weight, design: .serif)
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    private func font(size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = baseFont.fontDescriptor.withDesign(design) else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: size)
    }
}
#endif
