#if canImport(UIKit)
import CoreText
import UIKit

struct LeadSheetNotationRenderer {
    let chart: Chart

    private var style: LeadSheetNotationStyle {
        LeadSheetNotationStyle(
            documentStyle: chart.stylePreset,
            notationFont: chart.notationFont,
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
        UIColor(white: 0.35, alpha: 1).setStroke()
        paperPath.lineWidth = 1.2 * style.strokeScale
        paperPath.stroke()
    }

    func drawHeader(_ header: LeadSheetHeaderLayout) {
        let title = chart.title.trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(
            title.isEmpty ? "UNTITLED CHART" : title.uppercased(),
            in: header.titleFrame,
            font: style.titleFont(size: 38),
            color: style.inkColor,
            alignment: .center
        )

        if let composerFrame = header.composerFrame,
           let composerCredit = normalizedText(chart.composerCredit) {
            drawText(
                composerCredit,
                in: composerFrame,
                font: style.metadataFont(size: 14),
                color: style.inkColor.withAlphaComponent(0.8),
                alignment: .right
            )
        }

        if let styleNoteFrame = header.styleNoteFrame,
           let styleNote = LeadSheetPageLayoutEngine.resolvedStyleNote(for: chart) {
            drawText(
                styleNote,
                in: styleNoteFrame,
                font: style.metadataFont(size: 14),
                color: style.inkColor.withAlphaComponent(0.8)
            )
        }

        if let keyFrame = header.keyFrame {
            drawText(
                chart.documentKey.transposed(for: chart.defaultTranspositionView).displayText.uppercased(),
                in: keyFrame,
                font: style.metadataFont(size: 14),
                color: style.inkColor.withAlphaComponent(0.8),
                alignment: .center
            )
        }

        if let meterFrame = header.meterFrame {
            drawText(
                chart.defaultMeter.displayText,
                in: meterFrame,
                font: style.metadataFont(size: 14),
                color: style.inkColor.withAlphaComponent(0.8),
                alignment: .center
            )
        }
    }

    func drawSectionText(_ text: String, in frame: CGRect) {
        drawText(
            text.uppercased(),
            in: frame,
            font: style.metadataFont(size: 15),
            color: style.inkColor.withAlphaComponent(0.9)
        )
    }

    func drawRoadmapText(_ text: String, in frame: CGRect) {
        drawText(
            text.uppercased(),
            in: frame,
            font: style.metadataFont(size: 13),
            color: style.inkColor.withAlphaComponent(0.78),
            alignment: .right
        )
    }

    func drawCueText(_ cueTextLayout: LeadSheetCueTextLayout) {
        let fontSize: CGFloat
        let alpha: CGFloat
        switch cueTextLayout.emphasis {
        case .subtle:
            fontSize = 10.5
            alpha = 0.56
        case .normal:
            fontSize = 11.5
            alpha = 0.68
        case .strong:
            fontSize = 12.5
            alpha = 0.82
        }

        drawText(
            cueTextLayout.text,
            in: cueTextLayout.frame,
            font: style.metadataFont(size: fontSize),
            color: style.inkColor.withAlphaComponent(alpha),
            alignment: cueTextLayout.position == .trailingEdge ? .right : .left
        )
    }

    func drawEnding(_ endingLayout: LeadSheetEndingLayout) {
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
        path.lineWidth = 1.35 * style.strokeScale
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
            font: style.metadataFont(size: 12),
            color: style.inkColor.withAlphaComponent(0.88)
        )
    }

    func drawRoadmapMarker(_ markerLayout: LeadSheetRoadmapMarkerLayout) {
        let markerPath = UIBezierPath(
            roundedRect: markerLayout.frame.insetBy(dx: 0.5, dy: 1.5),
            cornerRadius: 2.5
        )
        style.inkColor.withAlphaComponent(0.055).setFill()
        markerPath.fill()
        style.inkColor.withAlphaComponent(0.62).setStroke()
        markerPath.lineWidth = 0.9 * style.strokeScale
        markerPath.stroke()

        drawText(
            markerLayout.text.uppercased(),
            in: markerLayout.frame.insetBy(dx: 5, dy: 2),
            font: style.metadataFont(size: 10.8),
            color: style.inkColor.withAlphaComponent(0.82),
            alignment: .center
        )
    }

    func drawStaffLines(for system: LeadSheetSystemLayout) {
        let staffSpace = system.staffSpace
        for lineY in system.staffLineYPositions {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: system.frame.minX, y: lineY))
            path.addLine(to: CGPoint(x: system.frame.maxX, y: lineY))
            path.lineWidth = style.staffLineWidth(staffSpace: staffSpace)
            style.inkColor.withAlphaComponent(0.72).setStroke()
            path.stroke()
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
            drawNotationSymbol(
                .timeSignatureDigit(meter.numerator),
                centeredAt: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.28),
                staffSpace: style.defaultStaffSpace
            )
            drawNotationSymbol(
                .timeSignatureDigit(meter.denominator),
                centeredAt: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.72),
                staffSpace: style.defaultStaffSpace
            )
        } else {
            let numeratorRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2)
            let denominatorRect = CGRect(x: frame.minX, y: frame.midY - 2, width: frame.width, height: frame.height / 2)
            drawText(
                "\(meter.numerator)",
                in: numeratorRect,
                font: style.timeSignatureFont(size: 22),
                color: style.inkColor,
                alignment: .center
            )
            drawText(
                "\(meter.denominator)",
                in: denominatorRect,
                font: style.timeSignatureFont(size: 22),
                color: style.inkColor,
                alignment: .center
            )
        }
    }

    func drawChord(_ chordLayout: LeadSheetChordLayout) {
        drawText(
            chordLayout.text,
            in: chordLayout.frame,
            font: style.chordFont(size: 18),
            color: style.inkColor
        )
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

    func drawRepeatMarker(_ marker: LeadSheetRepeatMarkerLayout) {
        let staffSpace = staffSpace(fromStaffHeight: marker.frame.height)
        let separation = max(
            style.barlineSeparation(staffSpace: staffSpace) * 1.55,
            staffSpace * 0.46
        )
        let thinLineWidth = max(style.barlineWidth(.thin, staffSpace: staffSpace), 1.05)
        let heavyLineWidth = max(thinLineWidth * 1.45, 1.65)
        let centerX = marker.frame.midX
        let thinX: CGFloat
        let thickX: CGFloat
        let dotX: CGFloat

        switch marker.edge {
        case .leading:
            thickX = centerX - separation / 2
            thinX = centerX + separation / 2
            dotX = thinX + separation * 1.35
        case .trailing:
            thinX = centerX - separation / 2
            thickX = centerX + separation / 2
            dotX = thinX - separation * 1.35
        }

        drawRepeatBarline(
            at: thickX,
            from: marker.frame.minY,
            to: marker.frame.maxY,
            width: heavyLineWidth
        )
        drawRepeatBarline(
            at: thinX,
            from: marker.frame.minY,
            to: marker.frame.maxY,
            width: thinLineWidth
        )
        drawRepeatDots(atX: dotX, in: marker.frame, staffSpace: staffSpace)
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

    private func drawRepeatDots(atX dotX: CGFloat, in frame: CGRect, staffSpace: CGFloat) {
        let dotRadius = max(CGFloat(1.45), staffSpace * 0.16)
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
        } else if noteLayout.flagStyle == .single {
            drawFlag(from: stemEnd, stemGoesUp: noteLayout.stemGoesUp, staffSpace: noteLayout.staffSpace)
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

    private func drawFlag(from stemEnd: CGPoint, stemGoesUp: Bool, staffSpace: CGFloat) {
        let flag: NotationGlyphCatalog.Symbol = stemGoesUp ? .flag8thUp : .flag8thDown
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

private struct LeadSheetNotationStyle {
    let documentStyle: StylePreset
    let notationFont: NotationFontPreset
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
            return scaledStaffSpaceValue(smuflDefaults.thinBarlineThickness, staffSpace: staffSpace, minimum: 0.8)
        case .thick:
            return scaledStaffSpaceValue(smuflDefaults.thickBarlineThickness, staffSpace: staffSpace, minimum: 2.2)
        }
    }

    func barlineSeparation(staffSpace: CGFloat) -> CGFloat {
        scaledStaffSpaceValue(smuflDefaults.barlineSeparation, staffSpace: staffSpace, minimum: 2.4)
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
        case .rehearsalDraft:
            return UIColor(white: 0.18, alpha: 1)
        }
    }

    var paperFillColor: UIColor {
        switch documentStyle {
        case .cleanStudio:
            return UIColor(white: 0.995, alpha: 1)
        case .gigSheet:
            return UIColor(red: 1, green: 0.992, blue: 0.962, alpha: 1)
        case .rehearsalDraft:
            return UIColor(red: 0.985, green: 0.988, blue: 0.975, alpha: 1)
        }
    }

    func titleFont(size: CGFloat) -> UIFont {
        switch documentStyle {
        case .cleanStudio:
            return UIFont.systemFont(ofSize: size * 0.94, weight: .semibold)
        case .gigSheet:
            return UIFont.systemFont(ofSize: size * 0.94, weight: .semibold)
        case .rehearsalDraft:
            return UIFont.systemFont(ofSize: size * 0.9, weight: .bold)
        }
    }

    func metadataFont(size: CGFloat) -> UIFont {
        switch documentStyle {
        case .cleanStudio, .gigSheet:
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        case .rehearsalDraft:
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        }
    }

    func chordFont(size: CGFloat) -> UIFont {
        notationFont.textUIFont(size: size, fallback: markerFont(size: size, weight: .regular))
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
    case eighthRest

    var symbol: NotationGlyphCatalog.Symbol {
        switch self {
        case .wholeRest:
            return .wholeRest
        case .halfRest:
            return .halfRest
        case .quarterRest:
            return .quarterRest
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
        case .eighthRest:
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
#endif
