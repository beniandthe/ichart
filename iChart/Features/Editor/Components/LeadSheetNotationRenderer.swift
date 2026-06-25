#if canImport(UIKit)
import CoreText
import UIKit

enum LeadSheetRoadmapLabelFitting {
    static func fittedBaseFontSize(
        for text: String,
        in rect: CGRect,
        baseFontSize: CGFloat,
        minimumFontSize: CGFloat,
        baseFontProvider: (CGFloat) -> UIFont,
        symbolFontProvider: (String, UIFont) -> UIFont
    ) -> CGFloat {
        guard rect.width > 1, rect.height > 1, !text.isEmpty else {
            return baseFontSize
        }

        let baseFont = baseFontProvider(baseFontSize)
        let baseBounds = measuredBounds(
            for: text,
            baseFont: baseFont,
            symbolFontProvider: symbolFontProvider
        )
        guard baseBounds.width > 0, baseBounds.height > 0 else {
            return baseFontSize
        }

        let widthScale = rect.width / baseBounds.width
        let heightScale = rect.height / baseBounds.height
        var fittedSize = baseFontSize
        let scale = min(widthScale, heightScale)
        if scale < 1 {
            fittedSize = max(minimumFontSize, floor(baseFontSize * scale * 0.98))
        }

        while fittedSize > minimumFontSize {
            let bounds = measuredBounds(
                for: text,
                baseFont: baseFontProvider(fittedSize),
                symbolFontProvider: symbolFontProvider
            )
            if ceil(bounds.width) <= rect.width + 0.5,
               ceil(bounds.height) <= rect.height + 0.5 {
                return fittedSize
            }

            fittedSize -= 0.5
        }

        return minimumFontSize
    }

    static func attributedText(
        _ text: String,
        baseFont: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        symbolFontProvider: (String, UIFont) -> UIFont
    ) -> NSMutableAttributedString {
        let normalizedText = text
            .replacingOccurrences(of: "𝄌", with: NotationGlyphCatalog.coda)
            .replacingOccurrences(of: "𝄋", with: NotationGlyphCatalog.segno)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping

        let attributedText = NSMutableAttributedString(
            string: normalizedText,
            attributes: [
                .font: baseFont,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )

        applyNotationFont(
            to: attributedText,
            symbolGlyph: NotationGlyphCatalog.coda,
            baseFont: baseFont,
            symbolFontProvider: symbolFontProvider
        )
        applyNotationFont(
            to: attributedText,
            symbolGlyph: NotationGlyphCatalog.segno,
            baseFont: baseFont,
            symbolFontProvider: symbolFontProvider
        )

        return attributedText
    }

    static func measuredBounds(
        for text: String,
        baseFont: UIFont,
        symbolFontProvider: (String, UIFont) -> UIFont
    ) -> CGRect {
        let attributedText = attributedText(
            text,
            baseFont: baseFont,
            color: .black,
            alignment: .center,
            symbolFontProvider: symbolFontProvider
        )
        return attributedText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }

    private static func applyNotationFont(
        to attributedText: NSMutableAttributedString,
        symbolGlyph: String,
        baseFont: UIFont,
        symbolFontProvider: (String, UIFont) -> UIFont
    ) {
        let fullRange = NSRange(location: 0, length: attributedText.length)
        let source = attributedText.string as NSString
        let symbolFont = symbolFontProvider(symbolGlyph, baseFont)
        var searchRange = fullRange

        while searchRange.length > 0 {
            let matchRange = source.range(of: symbolGlyph, options: [], range: searchRange)
            guard matchRange.location != NSNotFound else {
                return
            }

            attributedText.addAttributes(
                [
                    .font: symbolFont,
                    .baselineOffset: -baseFont.pointSize * 0.04
                ],
                range: matchRange
            )

            let nextLocation = matchRange.location + matchRange.length
            searchRange = NSRange(
                location: nextLocation,
                length: fullRange.location + fullRange.length - nextLocation
            )
        }
    }
}

struct LeadSheetNotationRenderer {
    let chart: Chart

    private var style: LeadSheetNotationStyle {
        LeadSheetNotationStyle(
            layoutStyle: chart.layoutStyle,
            documentStyle: chart.stylePreset,
            notationFont: chart.notationFont,
            typography: ChartTypographyResolver(chart: chart),
            engravingPreset: chart.engravingPreset
        )
    }

    func drawPaper(_ frame: CGRect, in context: CGContext, showsShadow: Bool = true) {
        if showsShadow {
            context.saveGState()
            let shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor
            context.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: shadowColor)
            let shadowPath = UIBezierPath(roundedRect: frame, cornerRadius: 4)
            UIColor.white.setFill()
            shadowPath.fill()
            context.restoreGState()
        }

        let paperPath = UIBezierPath(rect: frame)
        style.paperFillColor.setFill()
        paperPath.fill()
        drawPaperRuling(in: frame, context: context)
        style.paperBorderColor.setStroke()
        paperPath.lineWidth = 1.2 * style.strokeScale
        paperPath.stroke()
    }

    private func drawPaperRuling(in frame: CGRect, context: CGContext) {
        guard style.paperRuling == .staffPaper else {
            return
        }

        context.saveGState()
        UIBezierPath(rect: frame).addClip()

        let rulingBounds = frame.insetBy(dx: 34, dy: 48)
        let staffLineSpacing: CGFloat = style.paperRulingStaffLineSpacing
        let staffGroupSpacing: CGFloat = style.paperRulingStaffGroupSpacing
        var groupTop = rulingBounds.minY
        style.paperRulingColor.setStroke()

        while groupTop <= rulingBounds.maxY {
            let groupPath = UIBezierPath()
            for lineIndex in 0..<5 {
                let y = groupTop + CGFloat(lineIndex) * staffLineSpacing
                guard y <= rulingBounds.maxY else {
                    continue
                }
                groupPath.move(to: CGPoint(x: rulingBounds.minX, y: y))
                groupPath.addLine(to: CGPoint(x: rulingBounds.maxX, y: y))
            }
            groupPath.lineWidth = style.paperRulingLineWidth
            groupPath.stroke()
            groupTop += staffGroupSpacing
        }

        context.restoreGState()
    }

    func drawHeader(_ header: LeadSheetHeaderLayout) {
        guard chart.headerInputMode == .typed else {
            return
        }

        let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(
            style.headerTitleText(title),
            in: header.titleFrame,
            font: style.titleFont(size: style.titleFontSize),
            color: style.inkColor,
            alignment: .center
        )

        if let composerFrame = header.composerFrame,
           let composerCredit = normalizedText(chart.composerCredit) {
            drawText(
                composerCredit,
                in: composerFrame,
                font: style.metadataFont(size: style.headerMetadataFontSize),
                color: style.inkColor.withAlphaComponent(style.headerMetadataAlpha),
                alignment: .right
            )
        }

        if let styleNoteFrame = header.styleNoteFrame,
           let styleNote = LeadSheetPageLayoutEngine.resolvedStyleNote(for: chart) {
            drawText(
                styleNote,
                in: styleNoteFrame,
                font: style.metadataFont(size: style.headerMetadataFontSize),
                color: style.inkColor.withAlphaComponent(style.headerMetadataAlpha)
            )
        }

        if let keyFrame = header.keyFrame {
            drawText(
                chart.documentKey.transposed(for: chart.defaultTranspositionView).displayText.uppercased(),
                in: keyFrame,
                font: style.metadataFont(size: style.headerMetadataFontSize),
                color: style.inkColor.withAlphaComponent(style.headerMetadataAlpha),
                alignment: .center
            )
        }

        if let meterFrame = header.meterFrame {
            drawText(
                chart.defaultMeter.displayText,
                in: meterFrame,
                font: style.metadataFont(size: style.headerMetadataFontSize),
                color: style.inkColor.withAlphaComponent(style.headerMetadataAlpha),
                alignment: .center
            )
        }
    }

    func drawSectionText(_ text: String, in frame: CGRect) {
        if chart.layoutStyle == .simpleChordSheet || chart.layoutStyle == .rhythmSectionSheet {
            let isRhythmSection = chart.layoutStyle == .rhythmSectionSheet
            let font = style.sectionBadgeFont(size: isRhythmSection ? 13.5 : 15)
            let label = text.uppercased()
            let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
            let boxHeight = min(frame.height, isRhythmSection ? 20 : 22)
            let horizontalPadding: CGFloat = isRhythmSection ? 7 : 8
            let boxWidth = min(frame.width, max(boxHeight, ceil(textWidth) + horizontalPadding))
            let boxFrame = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: boxWidth,
                height: boxHeight
            )
            let boxPath = UIBezierPath(rect: boxFrame)
            style.inkColor.setFill()
            boxPath.fill()
            drawText(
                label,
                in: boxFrame.insetBy(dx: 2, dy: 0),
                font: font,
                color: style.paperFillColor,
                alignment: .center
            )
            return
        }

        drawText(
            text.uppercased(),
            in: frame,
            font: style.metadataFont(size: 15),
            color: style.inkColor.withAlphaComponent(0.9)
        )
    }

    func drawRoadmapText(_ text: String, in frame: CGRect) {
        let isRhythmSection = chart.layoutStyle == .rhythmSectionSheet
        drawRoadmapLabel(
            text.uppercased(),
            in: frame,
            font: style.textFont(size: isRhythmSection ? 13.4 : 13),
            color: style.inkColor.withAlphaComponent(isRhythmSection ? 0.86 : 0.78),
            alignment: .right
        )
    }

    func drawCueText(_ cueTextLayout: LeadSheetCueTextLayout) {
        let fontSize: CGFloat
        let alpha: CGFloat
        switch cueTextLayout.emphasis {
        case .subtle:
            fontSize = chart.layoutStyle == .rhythmSectionSheet ? 12.5 : 12
            alpha = chart.layoutStyle == .rhythmSectionSheet ? 0.72 : 0.68
        case .normal:
            fontSize = chart.layoutStyle == .rhythmSectionSheet ? 14 : 13.5
            alpha = chart.layoutStyle == .rhythmSectionSheet ? 0.82 : 0.78
        case .strong:
            fontSize = chart.layoutStyle == .rhythmSectionSheet ? 15.5 : 15
            alpha = chart.layoutStyle == .rhythmSectionSheet ? 0.92 : 0.88
        }

        drawText(
            cueTextLayout.text,
            in: cueTextLayout.frame,
            font: style.textFont(size: fontSize * cueTextLayout.scale),
            color: style.inkColor.withAlphaComponent(alpha),
            alignment: cueTextLayout.position == .trailingEdge ? .right : .left
        )
    }

    func drawEnding(_ endingLayout: LeadSheetEndingLayout) {
        let isRhythmSection = chart.layoutStyle == .rhythmSectionSheet
        let bracketY = endingLayout.frame.minY + 3
        let hookBottomY = endingLayout.frame.maxY
        let path = UIBezierPath()
        path.move(to: CGPoint(x: endingLayout.frame.minX, y: bracketY))
        path.addLine(to: CGPoint(x: endingLayout.frame.maxX, y: bracketY))
        if endingLayout.showsLeadingHook {
            path.move(to: CGPoint(x: endingLayout.frame.minX, y: bracketY))
            path.addLine(to: CGPoint(x: endingLayout.frame.minX, y: hookBottomY))
        }
        if endingLayout.showsTrailingHook {
            path.move(to: CGPoint(x: endingLayout.frame.maxX, y: bracketY))
            path.addLine(to: CGPoint(x: endingLayout.frame.maxX, y: hookBottomY))
        }
        path.lineWidth = (isRhythmSection ? 1.45 : 1.35) * style.strokeScale
        style.inkColor.setStroke()
        path.stroke()

        guard endingLayout.showsText else {
            return
        }

        drawText(
            endingLayout.text,
            in: CGRect(
                x: endingLayout.frame.minX + 6,
                y: bracketY + 1,
                width: min(70, max(1, endingLayout.frame.width - 12)),
                height: max(1, endingLayout.frame.height - 4)
            ),
            font: style.textFont(size: isRhythmSection ? 12.4 : 12),
            color: style.inkColor.withAlphaComponent(isRhythmSection ? 0.92 : 0.88)
        )
    }

    func drawRoadmapMarker(_ markerLayout: LeadSheetRoadmapMarkerLayout) {
        let isRhythmSection = chart.layoutStyle == .rhythmSectionSheet
        let baseFontSize = roadmapMarkerBaseFontSize(for: markerLayout)
        let label = markerLayout.text.uppercased()
        let labelFrame = roadmapMarkerLabelFrame(for: markerLayout)
        let fontSize = LeadSheetRoadmapLabelFitting.fittedBaseFontSize(
            for: label,
            in: labelFrame,
            baseFontSize: baseFontSize,
            minimumFontSize: roadmapMarkerMinimumFontSize(for: markerLayout),
            baseFontProvider: { style.textFont(size: $0) },
            symbolFontProvider: roadmapSymbolFont(for:baseFont:)
        )

        drawRoadmapLabel(
            label,
            in: labelFrame,
            font: style.textFont(size: fontSize),
            color: style.inkColor.withAlphaComponent(isRhythmSection ? 0.94 : 0.88),
            alignment: .center
        )
    }

    func drawStaffLines(for system: LeadSheetSystemLayout) {
        let staffSpace = system.staffSpace
        let horizontalSpan = staffLineHorizontalSpan(for: system, staffSpace: staffSpace)
        for lineY in system.staffLineYPositions {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: horizontalSpan.minX, y: lineY))
            path.addLine(to: CGPoint(x: horizontalSpan.maxX, y: lineY))
            path.lineWidth = style.staffLineWidth(staffSpace: staffSpace)
            style.inkColor.withAlphaComponent(style.staffLineAlpha).setStroke()
            path.stroke()
        }
    }

    private func staffLineHorizontalSpan(
        for system: LeadSheetSystemLayout,
        staffSpace: CGFloat
    ) -> (minX: CGFloat, maxX: CGFloat) {
        guard chart.layoutStyle == .rhythmSectionSheet,
              let firstMeasure = system.measures.first,
              let lastMeasure = system.measures.last else {
            return (system.frame.minX, system.frame.maxX)
        }

        let startX = rhythmSectionSystemStartX(for: firstMeasure, staffSpace: staffSpace)
        let endX = rhythmSectionSystemEndX(for: lastMeasure, staffSpace: staffSpace)
        return (min(startX, endX), max(startX, endX))
    }

    private func rhythmSectionSystemStartX(
        for measure: LeadSheetMeasureLayout,
        staffSpace: CGFloat
    ) -> CGFloat {
        if let leadingRepeatFrame = measure.repeatMarkerLayouts
            .filter({ $0.edge == .leading })
            .map(\.frame)
            .min(by: { $0.minX < $1.minX }) {
            return leadingRepeatFrame.minX
        }

        let barline = measure.leadingBarline ?? .single
        let x = measure.frame.minX
        switch barline {
        case .single:
            return x
        case .double, .final:
            return x - style.barlineSeparation(staffSpace: staffSpace)
        }
    }

    private func rhythmSectionSystemEndX(
        for measure: LeadSheetMeasureLayout,
        staffSpace: CGFloat
    ) -> CGFloat {
        if let trailingRepeatFrame = measure.repeatMarkerLayouts
            .filter({ $0.edge == .trailing })
            .map(\.frame)
            .max(by: { $0.maxX < $1.maxX }) {
            return trailingRepeatFrame.maxX
        }

        let x = measure.trailingBarlineFrame.midX
        switch measure.barlineAfter {
        case .single:
            return x
        case .double, .final:
            return x + style.barlineSeparation(staffSpace: staffSpace) / 2
        }
    }

    func drawClef(in frame: CGRect) {
        let symbol: NotationGlyphCatalog.Symbol = chart.defaultClef == .bass ? .bassClef : .trebleClef
        drawNotationSymbol(
            symbol,
            centeredAt: CGPoint(x: frame.midX, y: frame.midY + 2),
            staffSpace: style.defaultStaffSpace
        )
    }

    func drawKeySignature(_ layouts: [LeadSheetKeySignatureLayout]) {
        for layout in layouts {
            drawNotationSymbol(
                layout.symbol,
                centeredAt: layout.frame.center,
                staffSpace: layout.staffSpace
            )
        }
    }

    func drawTimeSignature(_ meter: Meter, in frame: CGRect) {
        if NotationGlyphCatalog.glyph(for: .timeSignatureDigit(meter.numerator)) != nil,
           NotationGlyphCatalog.glyph(for: .timeSignatureDigit(meter.denominator)) != nil {
            let digitStaffSpace = style.defaultStaffSpace * 0.84
            drawNotationSymbol(
                .timeSignatureDigit(meter.numerator),
                centeredAt: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.22),
                staffSpace: digitStaffSpace
            )
            drawNotationSymbol(
                .timeSignatureDigit(meter.denominator),
                centeredAt: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.78),
                staffSpace: digitStaffSpace
            )
        } else {
            let numberHeight = frame.height * 0.42
            let fontSize = min(19, frame.height * 0.34)
            let numeratorRect = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: numberHeight
            )
            let denominatorRect = CGRect(
                x: frame.minX,
                y: frame.maxY - numberHeight,
                width: frame.width,
                height: numberHeight
            )
            drawText(
                "\(meter.numerator)",
                in: numeratorRect,
                font: style.timeSignatureFont(size: fontSize),
                color: style.inkColor,
                alignment: .center
            )
            drawText(
                "\(meter.denominator)",
                in: denominatorRect,
                font: style.timeSignatureFont(size: fontSize),
                color: style.inkColor,
                alignment: .center
            )
        }
    }

    func drawChord(_ chordLayout: LeadSheetChordLayout) {
        if chart.layoutStyle == .simpleChordSheet {
            drawSimpleChord(chordLayout)
            return
        }

        drawStructuredChord(chordLayout)
    }

    private func drawStructuredChord(_ chordLayout: LeadSheetChordLayout) {
        let rootFontSize = style.chordFontSize(
            fitting: chordLayout.frame,
            text: chordLayout.text
        )
        let suffixFontSize = style.structuredChordSuffixFontSize(primarySize: rootFontSize)
        let slashBassFontSize = style.structuredChordSlashBassFontSize(primarySize: rootFontSize)
        let rootFont = style.chordFont(size: rootFontSize)
        let suffixFont = style.chordFont(size: suffixFontSize)
        let slashBassFont = style.chordFont(size: slashBassFontSize)
        let symbolFont = style.chordSymbolFont(size: suffixFontSize)
        let runs = chordRenderRuns(
            for: chordLayout,
            rootFont: rootFont,
            suffixFont: suffixFont,
            slashBassFont: slashBassFont,
            symbolFont: symbolFont,
            suffixFontSize: suffixFontSize
        )
        let gapWidth = runs.count > 1
            ? CGFloat(runs.count - 1) * ChartTypographyResolver.simpleChordTokenGapWidth
            : 0
        let totalWidth = max(1, runs.reduce(CGFloat(0)) { $0 + $1.size.width } + gapWidth)
        let horizontalScale = min(1, chordLayout.frame.width / totalWidth)
        let renderedWidth = totalWidth * horizontalScale
        let startX = chordLayout.frame.minX + max(0, (chordLayout.frame.width - renderedWidth) / 2)
        let rootHeight = runs
            .filter { $0.role == .primaryText }
            .map(\.size.height)
            .max() ?? (chordLayout.text as NSString).size(withAttributes: [.font: rootFont]).height
        let rootY = chordLayout.frame.midY - rootHeight / 2
        let suffixY = rootY + rootHeight * 0.18
        let slashBassHeight = runs
            .filter { $0.role == .slashBassText }
            .map(\.size.height)
            .max() ?? ("/B" as NSString).size(withAttributes: [.font: slashBassFont]).height
        let slashBassY = rootY + max(0, rootHeight - slashBassHeight * 0.92)

        guard let context = UIGraphicsGetCurrentContext() else {
            drawChordRuns(
                runs,
                originX: startX,
                rootY: rootY,
                suffixY: suffixY,
                slashBassY: slashBassY
            )
            return
        }

        context.saveGState()
        context.translateBy(x: startX, y: 0)
        context.scaleBy(x: horizontalScale, y: 1)
        defer { context.restoreGState() }

        drawChordRuns(runs, originX: 0, rootY: rootY, suffixY: suffixY, slashBassY: slashBassY)
    }

    private func drawSimpleChord(_ chordLayout: LeadSheetChordLayout) {
        let rootFontSize = style.simpleChordPrimaryFontSize(
            fitting: chordLayout.frame,
            text: chordLayout.text
        )
        let rootFont = style.chordFont(size: rootFontSize)
        let suffixFontSize = style.simpleChordSuffixFontSize(primarySize: rootFontSize)
        let slashBassFontSize = style.simpleChordSlashBassFontSize(primarySize: rootFontSize)
        let suffixFont = style.chordFont(size: suffixFontSize)
        let slashBassFont = style.chordFont(size: slashBassFontSize)
        let symbolFont = style.chordSymbolFont(size: suffixFontSize)
        let runs = chordRenderRuns(
            for: chordLayout,
            rootFont: rootFont,
            suffixFont: suffixFont,
            slashBassFont: slashBassFont,
            symbolFont: symbolFont,
            suffixFontSize: suffixFontSize
        )
        let gapWidth = runs.count > 1
            ? CGFloat(runs.count - 1) * ChartTypographyResolver.simpleChordTokenGapWidth
            : 0
        let totalWidth = max(1, runs.reduce(CGFloat(0)) { $0 + $1.size.width } + gapWidth)
        let requestedHorizontalScale = min(
            1,
            max(0.01, chordLayout.horizontalCompressionScale)
        )
        let fittingHorizontalScale = min(1, chordLayout.frame.width / totalWidth)
        let horizontalScale = min(requestedHorizontalScale, fittingHorizontalScale)
        let renderedWidth = totalWidth * horizontalScale
        let startX = chordLayout.frame.minX + max(0, (chordLayout.frame.width - renderedWidth) / 2)
        let rootHeight = runs
            .filter { $0.role == .primaryText }
            .map(\.size.height)
            .max() ?? (chordLayout.text as NSString).size(withAttributes: [.font: rootFont]).height
        let rootY = chordLayout.frame.midY - rootHeight / 2
        let suffixY = rootY + rootHeight * 0.16
        let slashBassHeight = runs
            .filter { $0.role == .slashBassText }
            .map(\.size.height)
            .max() ?? ("/B" as NSString).size(withAttributes: [.font: slashBassFont]).height
        let slashBassY = rootY + max(0, rootHeight - slashBassHeight * 0.96)

        guard let context = UIGraphicsGetCurrentContext() else {
            drawChordRuns(
                runs,
                originX: startX,
                rootY: rootY,
                suffixY: suffixY,
                slashBassY: slashBassY
            )
            return
        }

        context.saveGState()
        context.translateBy(x: startX, y: 0)
        context.scaleBy(x: horizontalScale, y: 1)
        defer { context.restoreGState() }

        drawChordRuns(runs, originX: 0, rootY: rootY, suffixY: suffixY, slashBassY: slashBassY)
    }

    private func chordRenderRuns(
        for chordLayout: LeadSheetChordLayout,
        rootFont: UIFont,
        suffixFont: UIFont,
        slashBassFont: UIFont,
        symbolFont: UIFont,
        suffixFontSize: CGFloat
    ) -> [ChordRenderRun] {
        let tokens: [ChordTypographyToken]
        if let symbol = chordLayout.symbol {
            tokens = style.chordTokens(for: symbol)
        } else {
            let parts = SimpleChordTextParts(text: chordLayout.text)
            tokens = [
                ChordTypographyToken(text: parts.root, role: .primaryText),
                ChordTypographyToken(text: parts.suffix, role: .suffixText)
            ].filter { !$0.text.isEmpty }
        }

        return tokens.map { token in
            let font: UIFont
            switch token.role {
            case .primaryText:
                font = rootFont
            case .suffixText:
                font = suffixFont
            case .slashBassText:
                font = slashBassFont
            case .musicSymbol:
                font = suffixFont.supportsNotationGlyph(token.text) ? suffixFont : symbolFont
            }

            let drawsVectorSymbol = token.role == .musicSymbol
                && !font.supportsNotationGlyph(token.text)
            let size = drawsVectorSymbol
                ? vectorChordSymbolSize(for: token.text, fontSize: suffixFontSize)
                : (token.text as NSString).size(withAttributes: [.font: font])

            return ChordRenderRun(
                text: token.text,
                role: token.role,
                font: font,
                size: size,
                drawsVectorSymbol: drawsVectorSymbol
            )
        }
    }

    private func drawChordRuns(
        _ runs: [ChordRenderRun],
        originX: CGFloat,
        rootY: CGFloat,
        suffixY: CGFloat,
        slashBassY: CGFloat
    ) {
        var cursorX = originX

        for (index, run) in runs.enumerated() {
            if index > 0 {
                cursorX += ChartTypographyResolver.simpleChordTokenGapWidth
            }

            let y: CGFloat
            switch run.role {
            case .primaryText:
                y = rootY
            case .slashBassText:
                y = slashBassY
            case .suffixText, .musicSymbol:
                y = suffixY
            }
            if run.drawsVectorSymbol {
                let symbolFrame = CGRect(
                    x: cursorX,
                    y: y + run.size.height * 0.12,
                    width: run.size.width,
                    height: run.size.height * 0.78
                )
                drawVectorChordSymbol(run.text, in: symbolFrame)
            } else {
                (run.text as NSString).draw(
                    at: CGPoint(x: cursorX, y: y),
                    withAttributes: [
                        .font: run.font,
                        .foregroundColor: style.inkColor
                    ]
                )
            }

            cursorX += run.size.width
        }
    }

    private func vectorChordSymbolSize(for text: String, fontSize: CGFloat) -> CGSize {
        switch text {
        case "△", "Δ", "∆":
            return CGSize(width: fontSize * 0.78, height: fontSize * 0.82)
        case "ø":
            return CGSize(width: fontSize * 0.72, height: fontSize * 0.86)
        case "°":
            return CGSize(width: fontSize * 0.46, height: fontSize * 0.66)
        default:
            return CGSize(width: fontSize * 0.62, height: fontSize * 0.8)
        }
    }

    private func drawVectorChordSymbol(_ text: String, in frame: CGRect) {
        let lineWidth = max(CGFloat(1), min(frame.width, frame.height) * 0.1)
        style.inkColor.setStroke()

        switch text {
        case "△", "Δ", "∆":
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: frame.midX, y: frame.minY + lineWidth / 2))
            triangle.addLine(to: CGPoint(x: frame.maxX - lineWidth / 2, y: frame.maxY - lineWidth / 2))
            triangle.addLine(to: CGPoint(x: frame.minX + lineWidth / 2, y: frame.maxY - lineWidth / 2))
            triangle.close()
            triangle.lineWidth = lineWidth
            triangle.lineJoinStyle = .round
            triangle.stroke()
        case "°", "ø":
            let circleFrame = text == "ø"
                ? frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.12)
                : frame.insetBy(dx: frame.width * 0.08, dy: frame.height * 0.08)
            let circle = UIBezierPath(ovalIn: circleFrame)
            circle.lineWidth = lineWidth
            circle.stroke()

            if text == "ø" {
                let slash = UIBezierPath()
                slash.move(to: CGPoint(x: circleFrame.minX - lineWidth, y: circleFrame.maxY + lineWidth))
                slash.addLine(to: CGPoint(x: circleFrame.maxX + lineWidth, y: circleFrame.minY - lineWidth))
                slash.lineWidth = lineWidth
                slash.lineCapStyle = .round
                slash.stroke()
            }
        default:
            break
        }
    }

    func drawNote(_ noteLayout: LeadSheetNoteLayout) {
        switch noteLayout.symbolStyle {
        case .pitchedNote:
            drawPitchedNote(noteLayout)
        case .slash:
            drawSlashNote(noteLayout)
        case .wholeRest:
            drawRest(.wholeRest, for: noteLayout)
        case .halfRest:
            drawRest(.halfRest, for: noteLayout)
        case .quarterRest:
            drawRest(.quarterRest, for: noteLayout)
        case .sixteenthRest:
            drawRest(.sixteenthRest, for: noteLayout)
        case .eighthRest:
            drawRest(.eighthRest, for: noteLayout)
        }
    }

    func drawBarline(_ barline: BarlineType, in frame: CGRect) {
        switch barline {
        case .single:
            drawSingleBarline(at: frame.midX, from: frame.minY, to: frame.maxY)
        case .double:
            let staffSpace = staffSpace(fromStaffHeight: frame.height)
            let separation = style.barlineSeparation(staffSpace: staffSpace)
            drawSingleBarline(at: frame.midX - separation / 2, from: frame.minY, to: frame.maxY)
            drawSingleBarline(at: frame.midX + separation / 2, from: frame.minY, to: frame.maxY)
        case .final:
            let staffSpace = staffSpace(fromStaffHeight: frame.height)
            let separation = style.barlineSeparation(staffSpace: staffSpace)
            drawSingleBarline(at: frame.midX - separation / 2, from: frame.minY, to: frame.maxY)
            drawSingleBarline(
                at: frame.midX + separation / 2,
                from: frame.minY,
                to: frame.maxY,
                semanticWidth: .thick
            )
        }
    }

    func drawLeadingBarline(_ barline: BarlineType, at x: CGFloat, from startY: CGFloat, to endY: CGFloat) {
        switch barline {
        case .single:
            drawSingleBarline(at: x, from: startY, to: endY)
        case .double:
            let staffSpace = staffSpace(fromStaffHeight: endY - startY)
            let separation = style.barlineSeparation(staffSpace: staffSpace)
            drawSingleBarline(at: x - separation, from: startY, to: endY)
            drawSingleBarline(at: x, from: startY, to: endY)
        case .final:
            let staffSpace = staffSpace(fromStaffHeight: endY - startY)
            let separation = style.barlineSeparation(staffSpace: staffSpace)
            drawSingleBarline(at: x - separation, from: startY, to: endY)
            drawSingleBarline(
                at: x,
                from: startY,
                to: endY,
                semanticWidth: .thick
            )
        }
    }

    func drawRepeatMarker(_ marker: LeadSheetRepeatMarkerLayout) {
        drawRepeatBoundary([marker])
    }

    func drawRepeatBoundary(_ markers: [LeadSheetRepeatMarkerLayout]) {
        guard let firstMarker = markers.first else {
            return
        }

        let frame = markers
            .dropFirst()
            .reduce(firstMarker.frame) { partialFrame, marker in
                partialFrame.union(marker.frame)
            }
        let staffSpace = staffSpace(fromStaffHeight: frame.height)
        let separation = style.repeatBarlineSeparation(staffSpace: staffSpace)
        let lineWidth = style.repeatLineWidth(staffSpace: staffSpace)
        let dotRadius = style.repeatDotRadius(staffSpace: staffSpace)
        let dotOffset = style.repeatDotOffset(
            thinLineWidth: lineWidth,
            dotRadius: dotRadius,
            staffSpace: staffSpace
        )
        let centerX = firstMarker.frame.midX
        let leadingLineX = centerX - separation / 2
        let trailingLineX = centerX + separation / 2
        let edges = Set(markers.map(\.edge))

        drawRepeatBarline(
            at: leadingLineX,
            from: frame.minY,
            to: frame.maxY,
            width: lineWidth
        )
        drawRepeatBarline(
            at: trailingLineX,
            from: frame.minY,
            to: frame.maxY,
            width: lineWidth
        )

        if edges.contains(.trailing) {
            drawRepeatDots(
                atX: leadingLineX - dotOffset,
                in: frame,
                staffSpace: staffSpace,
                radius: dotRadius
            )
        }

        if edges.contains(.leading) {
            drawRepeatDots(
                atX: trailingLineX + dotOffset,
                in: frame,
                staffSpace: staffSpace,
                radius: dotRadius
            )
        }
    }

    func drawSingleBarline(
        at x: CGFloat,
        from startY: CGFloat,
        to endY: CGFloat,
        width: CGFloat? = nil,
        semanticWidth: BarlineStrokeWidth = .thin
    ) {
        let staffSpace = staffSpace(fromStaffHeight: endY - startY)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: startY))
        path.addLine(to: CGPoint(x: x, y: endY))
        let resolvedWidth = width.map { $0 * style.strokeScale }
            ?? style.barlineWidth(semanticWidth, staffSpace: staffSpace)
        path.lineWidth = chart.layoutStyle == .simpleChordSheet
            ? max(resolvedWidth * 1.65, 1.55 * style.strokeScale)
            : resolvedWidth
        style.inkColor.setStroke()
        path.stroke()
    }

    private func drawRepeatBarline(at x: CGFloat, from startY: CGFloat, to endY: CGFloat, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: startY))
        path.addLine(to: CGPoint(x: x, y: endY))
        path.lineWidth = width
        style.inkColor.setStroke()
        path.stroke()
    }

    private func drawRepeatDots(
        atX dotX: CGFloat,
        in frame: CGRect,
        staffSpace: CGFloat,
        radius dotRadius: CGFloat
    ) {
        let dotCenters = [
            CGPoint(x: dotX, y: frame.midY - staffSpace / 2),
            CGPoint(x: dotX, y: frame.midY + staffSpace / 2)
        ]

        style.inkColor.setFill()
        for center in dotCenters {
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            ).fill()
        }
    }

    func drawOpenMeasureHint(_ measure: LeadSheetMeasureLayout) {
        let guidePath = UIBezierPath()
        guidePath.move(to: CGPoint(x: measure.trailingBarlineFrame.midX, y: measure.staffFrame.minY))
        guidePath.addLine(to: CGPoint(x: measure.trailingBarlineFrame.midX, y: measure.staffFrame.maxY))
        guidePath.lineWidth = style.strokeScale
        guidePath.setLineDash([4, 4], count: 2, phase: 0)
        UIColor(white: 0.55, alpha: 0.6).setStroke()
        guidePath.stroke()
    }

    func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping

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

    private func drawRoadmapLabel(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let attributedText = LeadSheetRoadmapLabelFitting.attributedText(
            text,
            baseFont: font,
            color: color,
            alignment: alignment,
            symbolFontProvider: roadmapSymbolFont(for:baseFont:)
        )

        attributedText.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            context: nil
        )
    }

    private func roadmapMarkerBaseFontSize(for markerLayout: LeadSheetRoadmapMarkerLayout) -> CGFloat {
        if chart.layoutStyle == .simpleChordSheet {
            return markerLayout.type.isStandaloneNotationMarker ? 22 : 20
        }

        return chart.layoutStyle == .rhythmSectionSheet ? 15.2 : 14.8
    }

    private func roadmapMarkerLabelFrame(for markerLayout: LeadSheetRoadmapMarkerLayout) -> CGRect {
        if markerLayout.type.containsNotationMarkerGlyph {
            return markerLayout.frame.insetBy(
                dx: markerLayout.type.isStandaloneNotationMarker ? 0 : 2,
                dy: 0
            )
        }

        return markerLayout.frame.insetBy(dx: 2, dy: 1)
    }

    private func roadmapMarkerMinimumFontSize(for markerLayout: LeadSheetRoadmapMarkerLayout) -> CGFloat {
        if chart.layoutStyle == .simpleChordSheet {
            return markerLayout.type.isStandaloneNotationMarker ? 21 : 17.5
        }

        return chart.layoutStyle == .rhythmSectionSheet ? 8.5 : 8
    }

    private func roadmapSymbolFont(for symbolGlyph: String, baseFont: UIFont) -> UIFont {
        style.notationGlyphFont(
            size: baseFont.pointSize * 1.12,
            requiring: symbolGlyph
        )
    }

    private func drawPitchedNote(_ noteLayout: LeadSheetNoteLayout) {
        drawNotationSymbol(
            noteLayout.noteheadSymbol ?? NotationNoteheadGlyph.pitched(noteLayout.headStyle).symbol,
            centeredAt: noteLayout.noteheadFrame.center,
            staffSpace: noteLayout.staffSpace
        )
        drawStemAndAdornment(for: noteLayout)
        drawSharedNoteAdornment(for: noteLayout)
    }

    private func drawSlashNote(_ noteLayout: LeadSheetNoteLayout) {
        drawNotationSymbol(
            noteLayout.noteheadSymbol ?? NotationNoteheadGlyph.slash(noteLayout.headStyle).symbol,
            centeredAt: noteLayout.noteheadFrame.center,
            staffSpace: noteLayout.staffSpace
        )
        drawStemAndAdornment(for: noteLayout)
        drawSharedNoteAdornment(for: noteLayout)
    }

    private func drawStemAndAdornment(for noteLayout: LeadSheetNoteLayout) {
        guard let stemStart = noteLayout.stemStart,
              let stemEnd = noteLayout.stemEnd else {
            return
        }

        let stemPath = UIBezierPath()
        stemPath.move(to: stemStart)
        stemPath.addLine(to: stemEnd)
        stemPath.lineWidth = style.stemWidth(staffSpace: noteLayout.staffSpace)
        style.inkColor.setStroke()
        stemPath.stroke()

        if let beamEndPoint = noteLayout.beamEndPoint {
            drawBeam(from: stemEnd, to: beamEndPoint, staffSpace: noteLayout.staffSpace)
            if noteLayout.flagStyle == .double {
                let secondaryOffset = style.beamThickness(staffSpace: noteLayout.staffSpace) * 1.75
                drawBeam(
                    from: CGPoint(x: stemEnd.x, y: stemEnd.y + secondaryOffset),
                    to: CGPoint(x: beamEndPoint.x, y: beamEndPoint.y + secondaryOffset),
                    staffSpace: noteLayout.staffSpace
                )
            }
        } else if noteLayout.flagStyle == .secondaryBackward {
            drawSecondaryBeamBackward(
                from: stemEnd,
                stemGoesUp: noteLayout.stemGoesUp,
                staffSpace: noteLayout.staffSpace
            )
        } else if noteLayout.flagStyle != .none {
            drawFlag(
                from: stemEnd,
                stemGoesUp: noteLayout.stemGoesUp,
                flagStyle: noteLayout.flagStyle,
                staffSpace: noteLayout.staffSpace
            )
        }
    }

    private func drawBeam(from stemEnd: CGPoint, to beamEndPoint: CGPoint, staffSpace: CGFloat) {
        let beamThickness = style.beamThickness(staffSpace: staffSpace)
        let beamPath = UIBezierPath()
        beamPath.move(to: stemEnd)
        beamPath.addLine(to: beamEndPoint)
        beamPath.addLine(to: CGPoint(x: beamEndPoint.x, y: beamEndPoint.y + beamThickness))
        beamPath.addLine(to: CGPoint(x: stemEnd.x, y: stemEnd.y + beamThickness))
        beamPath.close()
        style.inkColor.setFill()
        beamPath.fill()
    }

    private func drawSecondaryBeamBackward(from stemEnd: CGPoint, stemGoesUp: Bool, staffSpace: CGFloat) {
        let beamThickness = style.beamThickness(staffSpace: staffSpace)
        let secondaryOffset = beamThickness * (stemGoesUp ? -1.75 : 1.75)
        let beamLength = staffSpace * 1.25
        let secondaryBeamY = stemEnd.y + secondaryOffset
        drawBeam(
            from: CGPoint(x: stemEnd.x - beamLength, y: secondaryBeamY),
            to: CGPoint(x: stemEnd.x, y: secondaryBeamY),
            staffSpace: staffSpace
        )
    }

    private func drawFlag(
        from stemEnd: CGPoint,
        stemGoesUp: Bool,
        flagStyle: LeadSheetNoteLayout.FlagStyle,
        staffSpace: CGFloat
    ) {
        let flag: NotationGlyphCatalog.Symbol
        switch flagStyle {
        case .double:
            flag = stemGoesUp ? .flag16thUp : .flag16thDown
        case .single, .secondaryBackward, .none:
            flag = stemGoesUp ? .flag8thUp : .flag8thDown
        }
        let stemAnchorName = stemGoesUp ? "stemUpNW" : "stemDownSW"
        drawNotationSymbol(flag, anchoredAt: stemEnd, anchorName: stemAnchorName, staffSpace: staffSpace)
    }

    private func drawSharedNoteAdornment(for noteLayout: LeadSheetNoteLayout) {
        if let dotFrame = noteLayout.dotFrame {
            drawNotationSymbol(
                .augmentationDot,
                centeredAt: dotFrame.center,
                staffSpace: noteLayout.staffSpace
            )
        }

        if let tieFrame = noteLayout.tieFrame {
            drawTie(in: tieFrame, staffSpace: noteLayout.staffSpace)
        }
    }

    private func drawTie(in tieFrame: CGRect, staffSpace: CGFloat) {
        let tiePath = UIBezierPath()
        tiePath.move(to: CGPoint(x: tieFrame.minX, y: tieFrame.midY))
        tiePath.addCurve(
            to: CGPoint(x: tieFrame.maxX, y: tieFrame.midY),
            controlPoint1: CGPoint(x: tieFrame.minX + tieFrame.width * 0.28, y: tieFrame.maxY),
            controlPoint2: CGPoint(x: tieFrame.maxX - tieFrame.width * 0.28, y: tieFrame.maxY)
        )
        tiePath.lineWidth = style.tieMidpointWidth(staffSpace: staffSpace)
        style.inkColor.setStroke()
        tiePath.stroke()
    }

    private func drawRest(_ rest: NotationRestGlyph, for noteLayout: LeadSheetNoteLayout) {
        drawNotationSymbol(
            rest.symbol,
            centeredAt: rest.center(from: noteLayout.noteheadFrame),
            staffSpace: noteLayout.staffSpace
        )
    }

    private func drawNotationSymbol(
        _ symbol: NotationGlyphCatalog.Symbol,
        centeredAt center: CGPoint,
        staffSpace: CGFloat
    ) {
        guard let glyph = NotationGlyphCatalog.glyph(for: symbol) else {
            return
        }
        let metrics = style.glyphMetrics(for: symbol)
        let fontSize = style.notationGlyphPointSize(
            for: symbol,
            staffSpace: staffSpace,
            metrics: metrics
        )

        if let centerAnchor = metrics?.boundingBox?.center,
           drawNotationGlyphPath(
            glyph,
            anchoredAt: center,
            smuflAnchor: centerAnchor,
            fontSize: fontSize
           ) {
            return
        }

        drawNotationGlyph(
            glyph,
            centeredAt: center,
            fontSize: fontSize
        )
    }

    private func drawNotationSymbol(
        _ symbol: NotationGlyphCatalog.Symbol,
        anchoredAt anchorPoint: CGPoint,
        anchorName: String,
        staffSpace: CGFloat
    ) {
        guard let glyph = NotationGlyphCatalog.glyph(for: symbol) else {
            return
        }
        let metrics = style.glyphMetrics(for: symbol)
        let fontSize = style.notationGlyphPointSize(
            for: symbol,
            staffSpace: staffSpace,
            metrics: metrics
        )

        guard let anchor = metrics?.anchor(named: anchorName),
              drawNotationGlyphPath(
                glyph,
                anchoredAt: anchorPoint,
                smuflAnchor: anchor,
                fontSize: fontSize
              ) else {
            drawNotationSymbol(symbol, centeredAt: anchorPoint, staffSpace: staffSpace)
            return
        }
    }

    private func drawNotationGlyph(
        _ glyph: String,
        in rect: CGRect,
        fontSize: CGFloat,
        alignment: NSTextAlignment = .center
    ) {
        drawText(
            glyph,
            in: rect,
            font: style.notationGlyphFont(size: fontSize, requiring: glyph),
            color: style.inkColor,
            alignment: alignment
        )
    }

    private func drawNotationGlyph(_ glyph: String, centeredAt center: CGPoint, fontSize: CGFloat) {
        let font = style.notationGlyphFont(size: fontSize, requiring: glyph)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.inkColor
        ]
        let glyphSize = (glyph as NSString).size(withAttributes: attributes)
        let origin = CGPoint(
            x: center.x - glyphSize.width / 2,
            y: center.y - glyphSize.height / 2
        )
        (glyph as NSString).draw(at: origin, withAttributes: attributes)
    }

    @discardableResult
    private func drawNotationGlyphPath(
        _ glyph: String,
        anchoredAt anchorPoint: CGPoint,
        smuflAnchor: SmuflPoint,
        fontSize: CGFloat
    ) -> Bool {
        let font = style.notationGlyphFont(size: fontSize, requiring: glyph) as CTFont
        let characters = Array(glyph.utf16)
        guard characters.count == 1 else {
            return false
        }

        var character = characters[0]
        var cgGlyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &cgGlyph, 1),
              let glyphPath = CTFontCreatePathForGlyph(font, cgGlyph, nil),
              let context = UIGraphicsGetCurrentContext() else {
            return false
        }

        let smuflScale = fontSize / 4
        let glyphOrigin = CGPoint(
            x: anchorPoint.x - CGFloat(smuflAnchor.x) * smuflScale,
            y: anchorPoint.y + CGFloat(smuflAnchor.y) * smuflScale
        )

        context.saveGState()
        context.translateBy(x: glyphOrigin.x, y: glyphOrigin.y)
        context.scaleBy(x: 1, y: -1)
        context.addPath(glyphPath)
        context.setFillColor(style.inkColor.cgColor)
        context.fillPath()
        context.restoreGState()
        return true
    }

    private func normalizedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func staffSpace(fromStaffHeight height: CGFloat) -> CGFloat {
        max(1, (height - 4) / 4)
    }
}

private enum LeadSheetPaperRuling {
    case none
    case staffPaper
}

private struct LeadSheetNotationStyle {
    let layoutStyle: ChartLayoutStyle
    let documentStyle: StylePreset
    let notationFont: NotationFontPreset
    let typography: ChartTypographyResolver
    let engravingPreset: EngravingPreset
    let defaultStaffSpace: CGFloat = 10.5

    private var smuflDefaults: SmuflEngravingDefaults {
        notationFont.smuflEngravingDefaults
    }

    var strokeScale: CGFloat {
        switch engravingPreset {
        case .compact:
            return 0.92
        case .balanced, .wide:
            return 1
        case .bold:
            return 1.28
        }
    }

    func staffLineWidth(staffSpace: CGFloat) -> CGFloat {
        scaledStaffSpaceValue(smuflDefaults.staffLineThickness, staffSpace: staffSpace, minimum: 0.7)
            * sheetStaffLineScale
    }

    func stemWidth(staffSpace: CGFloat) -> CGFloat {
        scaledStaffSpaceValue(smuflDefaults.stemThickness, staffSpace: staffSpace, minimum: 0.75)
    }

    func beamThickness(staffSpace: CGFloat) -> CGFloat {
        scaledStaffSpaceValue(smuflDefaults.beamThickness, staffSpace: staffSpace, minimum: 2.5)
    }

    func barlineWidth(_ width: BarlineStrokeWidth, staffSpace: CGFloat) -> CGFloat {
        switch width {
        case .thin:
            return LeadSheetBarlineMetrics.thinWidth(staffSpace: staffSpace, strokeScale: strokeScale)
        case .thick:
            return LeadSheetBarlineMetrics.thickWidth(staffSpace: staffSpace, strokeScale: strokeScale)
        }
    }

    func repeatLineWidth(staffSpace: CGFloat) -> CGFloat {
        LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: strokeScale,
            layoutStyle: layoutStyle
        )
    }

    func barlineSeparation(staffSpace: CGFloat) -> CGFloat {
        LeadSheetBarlineMetrics.separation(staffSpace: staffSpace)
    }

    func repeatBarlineSeparation(staffSpace: CGFloat) -> CGFloat {
        LeadSheetBarlineMetrics.repeatSeparation(
            staffSpace: staffSpace,
            layoutStyle: layoutStyle
        )
    }

    func repeatDotRadius(staffSpace: CGFloat) -> CGFloat {
        LeadSheetBarlineMetrics.repeatDotRadius(
            staffSpace: staffSpace,
            layoutStyle: layoutStyle
        )
    }

    func repeatDotOffset(thinLineWidth: CGFloat, dotRadius: CGFloat, staffSpace: CGFloat) -> CGFloat {
        LeadSheetBarlineMetrics.repeatDotOffset(
            thinLineWidth: thinLineWidth,
            dotRadius: dotRadius,
            staffSpace: staffSpace,
            layoutStyle: layoutStyle
        )
    }

    func tieMidpointWidth(staffSpace: CGFloat) -> CGFloat {
        scaledStaffSpaceValue(smuflDefaults.tieMidpointThickness, staffSpace: staffSpace, minimum: 0.9)
    }

    var glyphScale: CGFloat {
        CGFloat(engravingPreset.glyphScale)
    }

    var inkColor: UIColor {
        switch documentStyle {
        case .cleanStudio:
            return UIColor(white: 0.055, alpha: 1)
        case .gigSheet:
            return UIColor(white: 0.035, alpha: 1)
        case .plainWhite:
            return UIColor(white: 0.07, alpha: 1)
        case .rehearsalDraft:
            return UIColor(white: 0.18, alpha: 1)
        }
    }

    var paperFillColor: UIColor {
        switch layoutStyle {
        case .simpleChordSheet, .leadSheet:
            switch documentStyle {
            case .cleanStudio:
                return UIColor(red: 1.0, green: 0.976, blue: 0.892, alpha: 1)
            case .gigSheet:
                return UIColor(red: 0.988, green: 0.965, blue: 0.906, alpha: 1)
            case .plainWhite:
                return UIColor(white: 1.0, alpha: 1)
            case .rehearsalDraft:
                return UIColor(white: 1.0, alpha: 1)
            }
        case .rhythmSectionSheet:
            switch documentStyle {
            case .cleanStudio:
                return UIColor(red: 0.992, green: 0.975, blue: 0.922, alpha: 1)
            case .gigSheet:
                return UIColor(red: 0.962, green: 0.986, blue: 0.982, alpha: 1)
            case .plainWhite:
                return UIColor(white: 1.0, alpha: 1)
            case .rehearsalDraft:
                return UIColor(red: 0.988, green: 0.992, blue: 0.996, alpha: 1)
            }
        }
    }

    var paperBorderColor: UIColor {
        switch documentStyle {
        case .cleanStudio:
            return UIColor(red: 0.62, green: 0.52, blue: 0.38, alpha: 1)
        case .gigSheet:
            return layoutStyle == .rhythmSectionSheet
                ? UIColor(red: 0.42, green: 0.54, blue: 0.55, alpha: 1)
                : UIColor(red: 0.55, green: 0.48, blue: 0.38, alpha: 1)
        case .plainWhite:
            return UIColor(white: 0.70, alpha: 1)
        case .rehearsalDraft:
            return UIColor(white: 0.62, alpha: 1)
        }
    }

    var paperRuling: LeadSheetPaperRuling {
        guard layoutStyle == .simpleChordSheet else {
            return .none
        }

        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return .none
        case .gigSheet, .rehearsalDraft:
            return .staffPaper
        }
    }

    var paperRulingColor: UIColor {
        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return UIColor.clear
        case .gigSheet:
            return UIColor(red: 0.34, green: 0.40, blue: 0.42, alpha: 0.14)
        case .rehearsalDraft:
            return UIColor(white: 0.42, alpha: 0.12)
        }
    }

    var paperRulingLineWidth: CGFloat {
        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return 0
        case .gigSheet:
            return 0.7
        case .rehearsalDraft:
            return 0.55
        }
    }

    var paperRulingStaffLineSpacing: CGFloat {
        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return 0
        case .gigSheet:
            return 7.2
        case .rehearsalDraft:
            return 7.0
        }
    }

    var paperRulingStaffGroupSpacing: CGFloat {
        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return 0
        case .gigSheet:
            return 74
        case .rehearsalDraft:
            return 78
        }
    }

    var staffLineAlpha: CGFloat {
        switch layoutStyle {
        case .simpleChordSheet:
            return 0.72
        case .leadSheet:
            return 0.74
        case .rhythmSectionSheet:
            switch documentStyle {
            case .cleanStudio:
                return 0.78
            case .gigSheet:
                return 0.9
            case .plainWhite:
                return 0.72
            case .rehearsalDraft:
                return 0.58
            }
        }
    }

    private var sheetStaffLineScale: CGFloat {
        guard layoutStyle == .rhythmSectionSheet else {
            return 1
        }

        switch documentStyle {
        case .cleanStudio, .plainWhite:
            return 1
        case .gigSheet:
            return 1.14
        case .rehearsalDraft:
            return 0.9
        }
    }

    var titleFontSize: CGFloat {
        layoutStyle == .simpleChordSheet ? 24 : 38
    }

    var headerMetadataFontSize: CGFloat {
        layoutStyle == .simpleChordSheet ? 18 : 14
    }

    var headerMetadataAlpha: CGFloat {
        layoutStyle == .simpleChordSheet ? 0.92 : 0.8
    }

    func headerTitleText(_ rawTitle: String) -> String {
        guard !rawTitle.isEmpty else {
            return layoutStyle == .simpleChordSheet ? "Untitled Chart" : "UNTITLED CHART"
        }

        return layoutStyle == .simpleChordSheet ? rawTitle : rawTitle.uppercased()
    }

    func titleFont(size: CGFloat) -> UIFont {
        if layoutStyle == .simpleChordSheet {
            return typography.headerUIFont(
                size: size,
                weight: .bold,
                fallback: UIFont.systemFont(ofSize: size, weight: .bold)
            )
        }

        let fallback: UIFont
        switch documentStyle {
        case .cleanStudio, .plainWhite:
            fallback = UIFont.systemFont(ofSize: size * 0.94, weight: .semibold)
        case .gigSheet:
            fallback = UIFont.systemFont(ofSize: size * 0.94, weight: .semibold)
        case .rehearsalDraft:
            fallback = UIFont.systemFont(ofSize: size * 0.9, weight: .bold)
        }
        return typography.headerUIFont(size: fallback.pointSize, weight: .semibold, fallback: fallback)
    }

    func metadataFont(size: CGFloat) -> UIFont {
        if layoutStyle == .simpleChordSheet {
            return typography.headerUIFont(
                size: size,
                weight: .regular,
                fallback: UIFont.systemFont(ofSize: size, weight: .regular)
            )
        }

        let fallback: UIFont
        switch documentStyle {
        case .cleanStudio, .gigSheet, .plainWhite:
            fallback = UIFont.systemFont(ofSize: size, weight: .semibold)
        case .rehearsalDraft:
            fallback = UIFont.systemFont(ofSize: size, weight: .semibold)
        }
        return typography.headerUIFont(size: size, weight: .semibold, fallback: fallback)
    }

    func textFont(size: CGFloat) -> UIFont {
        typography.textUIFont(
            size: size,
            weight: .semibold,
            fallback: markerFont(size: size, weight: .semibold)
        )
    }

    func chordFont(size: CGFloat) -> UIFont {
        if layoutStyle == .simpleChordSheet {
            return typography.chordTextUIFont(size: size, fallback: simpleChordFont(size: size))
        }

        return typography.chordTextUIFont(size: size, fallback: markerFont(size: size, weight: .regular))
    }

    func chordSymbolFont(size: CGFloat) -> UIFont {
        typography.chordSymbolUIFont(size: size, fallback: notationGlyphFont(size: size))
    }

    func chordTokens(for symbol: ChordSymbol) -> [ChordTypographyToken] {
        typography.chordTokens(for: symbol)
    }

    func simpleChordFont(size: CGFloat) -> UIFont {
        UIFont(name: "AvenirNextCondensed-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
    }

    func chordFontSize(fitting frame: CGRect, text: String) -> CGFloat {
        guard layoutStyle == .simpleChordSheet else {
            return ChartTypographyResolver.structuredChordPrimaryFontSize
        }

        var size = min(56, max(24, frame.height * 0.92))
        while size > 16 {
            let font = chordFont(size: size)
            let renderedWidth = (text as NSString).size(withAttributes: [.font: font]).width
            if renderedWidth <= frame.width {
                break
            }
            size -= 1
        }
        return size
    }

    func simpleChordPrimaryFontSize(fitting frame: CGRect, text: String) -> CGFloat {
        ChartTypographyResolver.simpleChordPrimaryFontSize
    }

    func simpleChordSuffixFontSize(primarySize: CGFloat) -> CGFloat {
        ChartTypographyResolver.simpleChordSuffixFontSize(primarySize: primarySize)
    }

    func simpleChordSlashBassFontSize(primarySize: CGFloat) -> CGFloat {
        ChartTypographyResolver.simpleChordSlashBassFontSize(primarySize: primarySize)
    }

    func structuredChordSuffixFontSize(primarySize: CGFloat) -> CGFloat {
        ChartTypographyResolver.structuredChordSuffixFontSize(primarySize: primarySize)
    }

    func structuredChordSlashBassFontSize(primarySize: CGFloat) -> CGFloat {
        ChartTypographyResolver.structuredChordSlashBassFontSize(primarySize: primarySize)
    }

    func sectionBadgeFont(size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .bold)
    }

    func timeSignatureFont(size: CGFloat) -> UIFont {
        notationFont.textUIFont(size: size, fallback: markerFont(size: size, weight: .regular))
    }

    func notationGlyphFont(size: CGFloat, requiring glyph: String? = nil) -> UIFont {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let selectedFont = UIFont(name: notationFont.postScriptName, size: size)
        if let selectedFont,
           glyph.map(selectedFont.supportsNotationGlyph) ?? true {
            return selectedFont
        }

        let bravuraFont = UIFont(name: NotationFontPreset.bravura.postScriptName, size: size)
        if let bravuraFont,
           glyph.map(bravuraFont.supportsNotationGlyph) ?? true {
            return bravuraFont
        }

        return selectedFont ?? bravuraFont ?? UIFont.systemFont(ofSize: size)
    }

    func glyphMetrics(for symbol: NotationGlyphCatalog.Symbol) -> SmuflGlyphMetrics? {
        SmuflFontMetadataStore.metrics(for: symbol, in: notationFont)
    }

    func notationGlyphPointSize(
        for symbol: NotationGlyphCatalog.Symbol,
        staffSpace: CGFloat,
        metrics: SmuflGlyphMetrics?
    ) -> CGFloat {
        if metrics?.boundingBox != nil {
            return max(1, staffSpace * 4 * glyphScale)
        }

        return NotationGlyphCatalog.pointSize(for: symbol, staffSpace: staffSpace) * glyphScale
    }

    private func markerFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if let markerFelt = UIFont(name: "MarkerFelt-Wide", size: size) {
            return markerFelt
        }

        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func scaledStaffSpaceValue(_ value: Double, staffSpace: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, CGFloat(value) * staffSpace * strokeScale)
    }
}

private struct NotationNoteheadGlyph {
    let symbol: NotationGlyphCatalog.Symbol

    static func pitched(_ headStyle: LeadSheetNoteLayout.HeadStyle) -> NotationNoteheadGlyph {
        switch headStyle {
        case .whole:
            return NotationNoteheadGlyph(symbol: .noteheadWhole)
        case .half:
            return NotationNoteheadGlyph(symbol: .noteheadHalf)
        case .filled:
            return NotationNoteheadGlyph(symbol: .noteheadBlack)
        }
    }

    static func slash(_ headStyle: LeadSheetNoteLayout.HeadStyle) -> NotationNoteheadGlyph {
        switch headStyle {
        case .whole:
            return NotationNoteheadGlyph(symbol: .slashWholeNotehead)
        case .half:
            return NotationNoteheadGlyph(symbol: .slashHalfNotehead)
        case .filled:
            return NotationNoteheadGlyph(symbol: .slashNotehead)
        }
    }
}

enum BarlineStrokeWidth {
    case thin
    case thick
}

private enum NotationRestGlyph {
    case wholeRest
    case halfRest
    case quarterRest
    case sixteenthRest
    case eighthRest

    var symbol: NotationGlyphCatalog.Symbol {
        switch self {
        case .wholeRest:
            return .wholeRest
        case .halfRest:
            return .halfRest
        case .quarterRest:
            return .quarterRest
        case .sixteenthRest:
            return .sixteenthRest
        case .eighthRest:
            return .eighthRest
        }
    }

    func center(from layoutFrame: CGRect) -> CGPoint {
        switch self {
        case .wholeRest, .halfRest:
            return layoutFrame.center
        case .quarterRest:
            return CGPoint(x: layoutFrame.midX, y: layoutFrame.midY - 1)
        case .sixteenthRest, .eighthRest:
            return CGPoint(x: layoutFrame.midX, y: layoutFrame.midY - 1)
        }
    }
}

private extension LeadSheetSystemLayout {
    var staffSpace: CGFloat {
        guard staffLineYPositions.count >= 2 else {
            return 10.5
        }

        return staffLineYPositions[1] - staffLineYPositions[0]
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension UIFont {
    func supportsNotationGlyph(_ glyph: String) -> Bool {
        let utf16Characters = Array(glyph.utf16)
        guard !utf16Characters.isEmpty else {
            return false
        }

        var characters = utf16Characters
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        let font = self as CTFont
        let hasGlyphs = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        return hasGlyphs && glyphs.allSatisfy { $0 != 0 }
    }
}

private struct ChordRenderRun {
    var text: String
    var role: ChordTypographyTokenRole
    var font: UIFont
    var size: CGSize
    var drawsVectorSymbol: Bool
}

private struct SimpleChordTextParts {
    var root: String
    var suffix: String

    init(text: String) {
        guard let firstCharacter = text.first,
              "ABCDEFG".contains(firstCharacter) else {
            root = text
            suffix = ""
            return
        }

        var rootEnd = text.index(after: text.startIndex)
        if rootEnd < text.endIndex,
           ["b", "♭", "#", "♯"].contains(text[rootEnd]) {
            rootEnd = text.index(after: rootEnd)
        }

        root = String(text[..<rootEnd])
        suffix = String(text[rootEnd...])
    }
}
#endif
