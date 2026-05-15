import CoreGraphics
import Foundation

struct LeadSheetPageLayout: Hashable {
    var pageBounds: CGRect
    var paperFrame: CGRect
    var header: LeadSheetHeaderLayout
    var systems: [LeadSheetSystemLayout]
}

struct LeadSheetHeaderLayout: Hashable {
    var frame: CGRect
    var titleFrame: CGRect
    var composerFrame: CGRect?
    var styleNoteFrame: CGRect?
    var keyFrame: CGRect
    var meterFrame: CGRect
}

struct LeadSheetSystemLayout: Identifiable, Hashable {
    var id: UUID
    var index: Int
    var frame: CGRect
    var staffLineYPositions: [CGFloat]
    var clefFrame: CGRect?
    var timeSignatureFrame: CGRect?
    var sectionTextFrame: CGRect?
    var sectionText: String?
    var roadmapTextFrame: CGRect?
    var roadmapText: String?
    var measures: [LeadSheetMeasureLayout]
}

struct LeadSheetMeasureLayout: Identifiable, Hashable {
    var id: UUID
    var sourceMeasureID: UUID?
    var index: Int
    var frame: CGRect
    var staffFrame: CGRect
    var chordBandFrame: CGRect
    var writableFrame: CGRect
    var chordLayouts: [LeadSheetChordLayout]
    var noteLayouts: [LeadSheetNoteLayout]
    var barlineAfter: BarlineType
    var trailingMeterChange: Meter?
    var trailingMeterChangeFrame: CGRect?
    var trailingBarlineFrame: CGRect
    var isOpen: Bool
}

struct LeadSheetChordLayout: Identifiable, Hashable {
    var id: UUID
    var text: String
    var frame: CGRect
}

struct LeadSheetNoteLayout: Identifiable, Hashable {
    enum SymbolStyle: Hashable {
        case pitchedNote
        case slash
        case wholeRest
        case halfRest
        case quarterRest
        case eighthRest
    }

    enum HeadStyle: Hashable {
        case whole
        case half
        case filled
    }

    enum FlagStyle: Hashable {
        case none
        case single
    }

    var id: UUID
    var symbolStyle: SymbolStyle
    var noteheadSymbol: NotationGlyphCatalog.Symbol?
    var noteheadFrame: CGRect
    var staffSpace: CGFloat
    var headStyle: HeadStyle
    var stemStart: CGPoint?
    var stemEnd: CGPoint?
    var stemGoesUp: Bool
    var flagStyle: FlagStyle
    var dotFrame: CGRect?
    var tieFrame: CGRect?
    var beamEndPoint: CGPoint?
}

struct LeadSheetNoteSelection: Identifiable, Hashable {
    var measureID: UUID
    var noteIndex: Int

    var id: String {
        "\(measureID.uuidString)-\(noteIndex)"
    }
}

struct LeadSheetSelectableNote: Identifiable, Hashable {
    var selection: LeadSheetNoteSelection
    var noteLayout: LeadSheetNoteLayout
    var selectionFrame: CGRect
    var selectionAnchor: CGPoint

    var id: String {
        selection.id
    }
}

enum LeadSheetPageLayoutEngine {
    private static let mediumOpenMeasureWidth: CGFloat = 252
    private static let preferredCommittedMeasureWidth: CGFloat = 140
    private static let systemTrailingPadding: CGFloat = 6

    static func pageLayout(for chart: Chart, pageSize: CGSize) -> LeadSheetPageLayout {
        let resolvedPageSize = CGSize(
            width: max(pageSize.width, 900),
            height: max(pageSize.height, 1100)
        )
        let pageBounds = CGRect(origin: .zero, size: resolvedPageSize)
        let paperWidth = min(860, max(640, resolvedPageSize.width - 140))
        let horizontalInset = max(40, (resolvedPageSize.width - paperWidth) / 2)
        let paperX = horizontalInset
        let paperY: CGFloat = 30
        let paperHeight = max(
            resolvedPageSize.height - 60,
            estimatedPaperHeight(for: chart, paperWidth: paperWidth)
        )
        let paperFrame = CGRect(x: paperX, y: paperY, width: paperWidth, height: paperHeight)

        let headerFrame = CGRect(
            x: paperFrame.minX + 34,
            y: paperFrame.minY + 24,
            width: paperFrame.width - 68,
            height: 108
        )
        let header = headerLayout(for: chart, in: headerFrame)

        let systemFrames = systemLayouts(
            for: chart,
            paperFrame: paperFrame,
            firstSystemTop: headerFrame.maxY + 24
        )

        return LeadSheetPageLayout(
            pageBounds: pageBounds,
            paperFrame: paperFrame,
            header: header,
            systems: systemFrames
        )
    }

    private static func estimatedPaperHeight(for chart: Chart, paperWidth: CGFloat) -> CGFloat {
        let metrics = chart.engravingPreset.layoutMetrics
        let systemCount = max(1, packedSystemPlans(for: chart, maxSystemWidth: paperWidth - 68).count)
        let headerHeight: CGFloat = 164
        let footerHeight: CGFloat = 54
        return headerHeight
            + CGFloat(systemCount) * metrics.systemHeight
            + CGFloat(max(0, systemCount - 1)) * metrics.systemSpacing
            + footerHeight
            + max(0, paperWidth * 0.18)
    }

    static func estimatedSystemCount(for chart: Chart, pageWidth: CGFloat) -> Int {
        let resolvedPageWidth = max(pageWidth, 900)
        let paperWidth = min(860, max(640, resolvedPageWidth - 140))
        return max(1, packedSystemPlans(for: chart, maxSystemWidth: paperWidth - 68).count)
    }

    private static func headerLayout(for chart: Chart, in frame: CGRect) -> LeadSheetHeaderLayout {
        let titleWidth = frame.width * 0.62
        let titleFrame = CGRect(
            x: frame.midX - titleWidth / 2,
            y: frame.minY + 20,
            width: titleWidth,
            height: 44
        )
        let composerFrame: CGRect?
        if let composerCredit = normalizedText(chart.composerCredit), !composerCredit.isEmpty {
            composerFrame = CGRect(
                x: frame.maxX - 190,
                y: titleFrame.minY + 10,
                width: 190,
                height: 20
            )
        } else {
            composerFrame = nil
        }

        let styleNoteFrame: CGRect?
        if let styleNote = resolvedStyleNote(for: chart), !styleNote.isEmpty {
            styleNoteFrame = CGRect(
                x: frame.minX,
                y: titleFrame.maxY + 2,
                width: 180,
                height: 18
            )
        } else {
            styleNoteFrame = nil
        }

        let keyFrame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: 80,
            height: 18
        )
        let meterFrame = CGRect(
            x: frame.minX,
            y: frame.minY + 18,
            width: 80,
            height: 18
        )

        return LeadSheetHeaderLayout(
            frame: frame,
            titleFrame: titleFrame,
            composerFrame: composerFrame,
            styleNoteFrame: styleNoteFrame,
            keyFrame: keyFrame,
            meterFrame: meterFrame
        )
    }

    private static func systemLayouts(
        for chart: Chart,
        paperFrame: CGRect,
        firstSystemTop: CGFloat
    ) -> [LeadSheetSystemLayout] {
        let plans = packedSystemPlans(for: chart, maxSystemWidth: paperFrame.width - 68)
        let metrics = chart.engravingPreset.layoutMetrics

        return plans.enumerated().map { systemIndex, plan in
            let systemFrame = CGRect(
                x: paperFrame.minX + 34,
                y: firstSystemTop + CGFloat(systemIndex) * (metrics.systemHeight + metrics.systemSpacing),
                width: min(paperFrame.width - 68, plan.frameWidth),
                height: metrics.systemHeight
            )
            return systemLayout(for: plan, chart: chart, index: systemIndex, frame: systemFrame)
        }
    }

    private static func systemLayout(
        for plan: PackedLeadSheetSystemPlan,
        chart: Chart,
        index: Int,
        frame: CGRect
    ) -> LeadSheetSystemLayout {
        let metrics = chart.engravingPreset.layoutMetrics
        let lineSpacing = metrics.staffLineSpacing
        let chordBandHeight = metrics.chordBandHeight
        let staffTop = frame.minY + chordBandHeight + 2
        let staffLineYPositions = (0..<5).map { staffTop + CGFloat($0) * lineSpacing }
        let staffFrame = CGRect(
            x: frame.minX,
            y: staffTop - 2,
            width: frame.width,
            height: lineSpacing * 4 + 4
        )
        let measureStartX = frame.minX + plan.leadingSignatureWidth

        let clefFrame = index == 0
            ? CGRect(x: frame.minX, y: staffTop - 12, width: 26, height: 54)
            : nil
        let timeSignatureFrame = index == 0
            ? CGRect(x: frame.minX + 28, y: staffTop - 10, width: 24, height: 50)
            : nil
        let measureIDs = plan.measures.compactMap(\.measure?.id)
        let sectionText = chart.sectionLabels.first(where: { measureIDs.contains($0.anchorMeasureID) })?.text
        let sectionTextFrame = sectionText.map { _ in
            CGRect(x: frame.minX, y: frame.minY + 2, width: 140, height: 18)
        }
        let roadmapText = chart.roadmapObjects.first(where: {
            measureIDs.contains($0.startMeasureID) || ($0.endMeasureID.map(measureIDs.contains) ?? false)
        })?.resolvedDisplayText
        let roadmapTextFrame = roadmapText.map { _ in
            CGRect(x: frame.maxX - 160, y: frame.minY + 2, width: 160, height: 18)
        }

        var measureX = measureStartX
        let measures = plan.measures.enumerated().map { offset, measurePlan in
            defer {
                measureX += measurePlan.width
            }

            return measureLayout(
                for: measurePlan.measure,
                chart: chart,
                index: offset,
                frame: CGRect(
                    x: measureX,
                    y: frame.minY,
                    width: measurePlan.width,
                    height: frame.height
                ),
                staffFrame: CGRect(
                    x: measureX,
                    y: staffFrame.minY,
                    width: measurePlan.width,
                    height: staffFrame.height
                ),
                chordBandHeight: chordBandHeight,
                staffLineYPositions: staffLineYPositions,
                trailingMeterChange: trailingMeterChange(after: measurePlan.measure, in: chart)
            )
        }

        return LeadSheetSystemLayout(
            id: plan.id,
            index: index,
            frame: frame,
            staffLineYPositions: staffLineYPositions,
            clefFrame: clefFrame,
            timeSignatureFrame: timeSignatureFrame,
            sectionTextFrame: sectionTextFrame,
            sectionText: sectionText,
            roadmapTextFrame: roadmapTextFrame,
            roadmapText: roadmapText,
            measures: measures
        )
    }

    private static func packedSystemPlans(
        for chart: Chart,
        maxSystemWidth: CGFloat
    ) -> [PackedLeadSheetSystemPlan] {
        let sourceMeasures = chart.measures
        guard !sourceMeasures.isEmpty else {
            let metrics = chart.engravingPreset.layoutMetrics
            return [
                PackedLeadSheetSystemPlan(
                    id: UUID(),
                    leadingSignatureWidth: metrics.firstSystemSignatureWidth,
                    frameWidth: metrics.firstSystemSignatureWidth
                        + mediumOpenMeasureWidth * metrics.measureWidthScale
                        + systemTrailingPadding,
                    measures: [
                        PackedLeadSheetMeasurePlan(
                            measure: nil,
                            width: mediumOpenMeasureWidth * metrics.measureWidthScale
                        )
                    ]
                )
            ]
        }

        let metrics = chart.engravingPreset.layoutMetrics
        var plans: [PackedLeadSheetSystemPlan] = []
        var currentMeasures: [PackedLeadSheetMeasurePlan] = []
        var currentLeadingSignatureWidth = metrics.firstSystemSignatureWidth
        var currentBodyWidth: CGFloat = 0

        func flushCurrentSystem() {
            guard !currentMeasures.isEmpty else {
                return
            }

            plans.append(
                PackedLeadSheetSystemPlan(
                    id: UUID(),
                    leadingSignatureWidth: currentLeadingSignatureWidth,
                    frameWidth: currentLeadingSignatureWidth + currentBodyWidth + systemTrailingPadding,
                    measures: currentMeasures
                )
            )
            currentMeasures = []
            currentLeadingSignatureWidth = metrics.continuationSystemSignatureWidth
            currentBodyWidth = 0
        }

        for measure in sourceMeasures {
            let preferredWidth = preferredWidth(for: measure, chart: chart)
            let nextFrameWidth = currentLeadingSignatureWidth
                + currentBodyWidth
                + preferredWidth
                + systemTrailingPadding

            if !currentMeasures.isEmpty && nextFrameWidth > maxSystemWidth {
                flushCurrentSystem()
            }

            currentMeasures.append(
                PackedLeadSheetMeasurePlan(measure: measure, width: preferredWidth)
            )
            currentBodyWidth += preferredWidth
        }

        flushCurrentSystem()
        return plans
    }

    private static func preferredWidth(for measure: Measure, chart: Chart) -> CGFloat {
        let metrics = chart.engravingPreset.layoutMetrics
        let defaultWidth = measure.authoringState == .open
            ? mediumOpenMeasureWidth * metrics.measureWidthScale
            : preferredCommittedMeasureWidth * metrics.measureWidthScale
        return measure.resolvedLayoutWidth(defaultWidth: defaultWidth)
    }

    private static func effectiveMeter(for measure: Measure?, defaultMeter: Meter) -> Meter? {
        guard let measure else {
            return nil
        }

        return measure.meterOverride ?? defaultMeter
    }

    private static func trailingMeterChange(after measure: Measure?, in chart: Chart) -> Meter? {
        guard let measure,
              let currentMeasureIndex = chart.measures.firstIndex(where: { $0.id == measure.id }) else {
            return nil
        }

        let nextMeasureIndex = currentMeasureIndex + 1
        guard chart.measures.indices.contains(nextMeasureIndex) else {
            return nil
        }

        let currentMeter = effectiveMeter(for: measure, defaultMeter: chart.defaultMeter)
        let nextMeter = effectiveMeter(for: chart.measures[nextMeasureIndex], defaultMeter: chart.defaultMeter)
        return currentMeter == nextMeter ? nil : nextMeter
    }

    private static func measureLayout(
        for measure: Measure?,
        chart: Chart,
        index: Int,
        frame: CGRect,
        staffFrame: CGRect,
        chordBandHeight: CGFloat,
        staffLineYPositions: [CGFloat],
        trailingMeterChange: Meter?
    ) -> LeadSheetMeasureLayout {
        let chordBandFrame = CGRect(
            x: frame.minX + 3,
            y: frame.minY,
            width: frame.width - 6,
            height: chordBandHeight - 4
        )
        let writableFrame = CGRect(
            x: frame.minX + 2,
            y: chordBandFrame.minY,
            width: frame.width - 4,
            height: staffFrame.maxY - chordBandFrame.minY + 8
        )
        let trailingBarlineFrame = CGRect(
            x: frame.maxX,
            y: staffFrame.minY,
            width: 1.6,
            height: staffFrame.height
        )
        let trailingMeterChangeFrame = trailingMeterChange.map { _ in
            CGRect(
                x: max(frame.minX + 8, trailingBarlineFrame.minX - 24),
                y: staffFrame.minY - 10,
                width: 20,
                height: 44
            )
        }

        guard let measure else {
            return LeadSheetMeasureLayout(
                id: UUID(),
                sourceMeasureID: nil,
                index: index + 1,
                frame: frame,
                staffFrame: staffFrame,
                chordBandFrame: chordBandFrame,
                writableFrame: writableFrame,
                chordLayouts: [],
                noteLayouts: [],
                barlineAfter: .single,
                trailingMeterChange: trailingMeterChange,
                trailingMeterChangeFrame: trailingMeterChangeFrame,
                trailingBarlineFrame: trailingBarlineFrame,
                isOpen: true
            )
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let displayedPlacements = measure.renderedChordPlacements(defaultMeter: chart.defaultMeter)
            .sorted {
                ($0.startPosition.startOffset(in: meter) ?? 0) <
                    ($1.startPosition.startOffset(in: meter) ?? 0)
            }

        let chordLayouts = displayedPlacements.map { placement in
            chordLayout(
                for: placement,
                chart: chart,
                meter: meter,
                chordBandFrame: chordBandFrame,
                staffFrame: staffFrame
            )
        }
        let noteLayouts = slashNoteLayouts(
            for: measure,
            chart: chart,
            meter: meter,
            staffFrame: staffFrame,
            staffLineYPositions: staffLineYPositions
        ) ?? []

        return LeadSheetMeasureLayout(
            id: measure.id,
            sourceMeasureID: measure.id,
            index: measure.index,
            frame: frame,
            staffFrame: staffFrame,
            chordBandFrame: chordBandFrame,
            writableFrame: writableFrame,
            chordLayouts: chordLayouts,
            noteLayouts: noteLayouts,
            barlineAfter: measure.barlineAfter,
            trailingMeterChange: trailingMeterChange,
            trailingMeterChangeFrame: trailingMeterChangeFrame,
            trailingBarlineFrame: trailingBarlineFrame,
            isOpen: measure.authoringState == .open
        )
    }

    private static func chordLayout(
        for placement: MeasureChordPlacement,
        chart: Chart,
        meter: Meter,
        chordBandFrame: CGRect,
        staffFrame: CGRect
    ) -> LeadSheetChordLayout {
        let event = placement.chordEvent.transposed(for: chart.defaultTranspositionView)
        let textWidth = estimatedChordTextWidth(for: event.symbol.displayText)
        let usableWidth = staffFrame.width - 16
        let attackCenterX = beatAttackCenterX(
            startPosition: placement.startPosition,
            duration: placement.duration ?? .quarter,
            meter: meter,
            staffFrame: staffFrame,
            usableWidth: usableWidth
        )
        let chordX = min(
            max(chordBandFrame.minX + 1, attackCenterX - textWidth / 2),
            chordBandFrame.maxX - textWidth
        )

        return LeadSheetChordLayout(
            id: placement.chordEvent.id,
            text: event.symbol.displayText,
            frame: CGRect(x: chordX, y: chordBandFrame.minY, width: textWidth, height: chordBandFrame.height)
        )
    }

    private static func estimatedChordTextWidth(for text: String) -> CGFloat {
        let baseWidth = text.reduce(CGFloat(0)) { partialWidth, character in
            partialWidth + estimatedChordCharacterWidth(character)
        }
        return max(28, baseWidth + 12)
    }

    private static func estimatedChordCharacterWidth(_ character: Character) -> CGFloat {
        switch character {
        case "i", "l", "I", "1":
            return 5
        case "m", "M", "w", "W":
            return 15
        case "#", "♯", "b", "♭", "7", "9", "5", "6", "3":
            return 10
        case "0"..."8":
            return 9
        case "-", "+", "°", "ø", "/", "(", ")":
            return 7
        case "△", "Δ":
            return 13
        default:
            return 12
        }
    }

    private static func slashNoteheadSymbol(
        for headStyle: LeadSheetNoteLayout.HeadStyle
    ) -> NotationGlyphCatalog.Symbol {
        switch headStyle {
        case .whole:
            return .slashWholeNotehead
        case .half:
            return .slashHalfNotehead
        case .filled:
            return .slashNotehead
        }
    }

    private static func noteheadFrame(
        for symbol: NotationGlyphCatalog.Symbol,
        centeredAt center: CGPoint,
        staffSpace: CGFloat,
        notationFont: NotationFontPreset,
        engravingPreset: EngravingPreset,
        fallbackSize: CGSize
    ) -> CGRect {
        guard let boundingBox = SmuflFontMetadataStore.metrics(
            for: symbol,
            in: notationFont
        )?.boundingBox else {
            return CGRect(
                x: center.x - fallbackSize.width / 2,
                y: center.y - fallbackSize.height / 2,
                width: fallbackSize.width,
                height: fallbackSize.height
            )
        }

        let scale = smuflScale(staffSpace: staffSpace, engravingPreset: engravingPreset)
        let centerPoint = boundingBox.center
        let minX = center.x + CGFloat(boundingBox.southWest.x - centerPoint.x) * scale
        let maxX = center.x + CGFloat(boundingBox.northEast.x - centerPoint.x) * scale
        let minY = center.y - CGFloat(boundingBox.northEast.y - centerPoint.y) * scale
        let maxY = center.y - CGFloat(boundingBox.southWest.y - centerPoint.y) * scale

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func stemAnchorPoint(
        for symbol: NotationGlyphCatalog.Symbol,
        centeredAt center: CGPoint,
        staffSpace: CGFloat,
        notationFont: NotationFontPreset,
        engravingPreset: EngravingPreset,
        stemGoesUp: Bool,
        fallback: CGPoint
    ) -> CGPoint {
        let anchorName = stemGoesUp ? "stemUpSE" : "stemDownNW"
        guard let metrics = SmuflFontMetadataStore.metrics(for: symbol, in: notationFont),
              let boundingBox = metrics.boundingBox,
              let anchor = metrics.anchor(named: anchorName) else {
            return fallback
        }

        let scale = smuflScale(staffSpace: staffSpace, engravingPreset: engravingPreset)
        let centerPoint = boundingBox.center
        return CGPoint(
            x: center.x + CGFloat(anchor.x - centerPoint.x) * scale,
            y: center.y - CGFloat(anchor.y - centerPoint.y) * scale
        )
    }

    private static func smuflScale(staffSpace: CGFloat, engravingPreset: EngravingPreset) -> CGFloat {
        staffSpace * CGFloat(engravingPreset.glyphScale)
    }

    private static func slashNoteLayouts(
        for measure: Measure,
        chart: Chart,
        meter: Meter,
        staffFrame: CGRect,
        staffLineYPositions: [CGFloat]
    ) -> [LeadSheetNoteLayout]? {
        guard let slots = measure.resolvedRhythmSlots(defaultMeter: meter),
              !slots.isEmpty else {
            return nil
        }

        let usableWidth = staffFrame.width - 16
        let slashCenterY = staffLineYPositions[2] + 1
        let stemBottomY = staffFrame.maxY + 10
        let staffSpace = staffLineYPositions[1] - staffLineYPositions[0]

        return slots.enumerated().map { index, slot in
            let noteCenterX = slashAttackCenterX(
                for: slot,
                meter: meter,
                staffFrame: staffFrame,
                usableWidth: usableWidth
            )

            switch slot.duration {
            case .wholeRest:
                return wholeRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .halfRest:
                return halfRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .quarterRest:
                return quarterRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .eighthRest:
                return eighthRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .tiedContinuation:
                return quarterRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            default:
                let headStyle = headStyle(for: slot.duration)
                let noteheadSymbol = slashNoteheadSymbol(for: headStyle)
                let noteheadFrame = noteheadFrame(
                    for: noteheadSymbol,
                    centeredAt: CGPoint(x: noteCenterX, y: slashCenterY),
                    staffSpace: staffSpace,
                    notationFont: chart.notationFont,
                    engravingPreset: chart.engravingPreset,
                    fallbackSize: CGSize(width: 10, height: 16)
                )
                let fallbackStemStart = CGPoint(x: noteheadFrame.minX + 1, y: noteheadFrame.maxY - 2)
                let stemStart = slot.duration == .whole || slot.duration == .slash
                    ? nil
                    : stemAnchorPoint(
                        for: noteheadSymbol,
                        centeredAt: noteheadFrame.center,
                        staffSpace: staffSpace,
                        notationFont: chart.notationFont,
                        engravingPreset: chart.engravingPreset,
                        stemGoesUp: false,
                        fallback: fallbackStemStart
                    )
                let stemEnd = stemStart.map { CGPoint(x: $0.x, y: stemBottomY) }
                let beamEndPoint = beamEndPointForSlash(
                    at: index,
                    slots: slots,
                    chart: chart,
                    meter: meter,
                    slashCenterY: slashCenterY,
                    staffSpace: staffSpace,
                    stemBottomY: stemBottomY,
                    staffFrame: staffFrame,
                    usableWidth: usableWidth
                )
                let isBeamedFromPrevious = isSlashEighthBeamedFromPrevious(
                    at: index,
                    slots: slots,
                    meter: meter
                )
                let flagStyle: LeadSheetNoteLayout.FlagStyle = slot.duration == .eighth
                    && beamEndPoint == nil
                    && !isBeamedFromPrevious
                    ? .single
                    : .none
                let dotFrame = dottedDuration(slot.duration)
                    ? CGRect(x: noteheadFrame.maxX + 3, y: noteheadFrame.midY - 1.5, width: 3, height: 3)
                    : nil

                return LeadSheetNoteLayout(
                    id: UUID(),
                    symbolStyle: .slash,
                    noteheadSymbol: noteheadSymbol,
                    noteheadFrame: noteheadFrame,
                    staffSpace: staffSpace,
                    headStyle: headStyle,
                    stemStart: stemStart,
                    stemEnd: stemEnd,
                    stemGoesUp: false,
                    flagStyle: flagStyle,
                    dotFrame: dotFrame,
                    tieFrame: nil,
                    beamEndPoint: beamEndPoint
                )
            }
        }
    }

    private static func beamEndPointForSlash(
        at index: Int,
        slots: [MeasureRhythmSlot],
        chart: Chart,
        meter: Meter,
        slashCenterY: CGFloat,
        staffSpace: CGFloat,
        stemBottomY: CGFloat,
        staffFrame: CGRect,
        usableWidth: CGFloat
    ) -> CGPoint? {
        guard slots[index].duration == .eighth,
              index + 1 < slots.count,
              slots[index + 1].duration == .eighth else {
            return nil
        }

        let currentStart = slots[index].startPosition.startOffset(in: meter) ?? 0
        let nextStart = slots[index + 1].startPosition.startOffset(in: meter) ?? 0
        guard abs((currentStart + slots[index].duration.wholeNoteLength) - nextStart) < 0.0001 else {
            return nil
        }
        guard slots[index].startPosition.beat == slots[index + 1].startPosition.beat else {
            return nil
        }

        let nextCenterX = slashAttackCenterX(
            for: slots[index + 1],
            meter: meter,
            staffFrame: staffFrame,
            usableWidth: usableWidth
        )
        let nextNoteheadSymbol = slashNoteheadSymbol(for: headStyle(for: slots[index + 1].duration))
        let nextNoteheadFrame = noteheadFrame(
            for: nextNoteheadSymbol,
            centeredAt: CGPoint(x: nextCenterX, y: slashCenterY),
            staffSpace: staffSpace,
            notationFont: chart.notationFont,
            engravingPreset: chart.engravingPreset,
            fallbackSize: CGSize(width: 10, height: 16)
        )
        let nextStemStart = stemAnchorPoint(
            for: nextNoteheadSymbol,
            centeredAt: nextNoteheadFrame.center,
            staffSpace: staffSpace,
            notationFont: chart.notationFont,
            engravingPreset: chart.engravingPreset,
            stemGoesUp: false,
            fallback: CGPoint(x: nextNoteheadFrame.minX + 1, y: nextNoteheadFrame.maxY - 2)
        )
        return CGPoint(x: nextStemStart.x, y: stemBottomY)
    }

    private static func slashAttackCenterX(
        for slot: MeasureRhythmSlot,
        meter: Meter,
        staffFrame: CGRect,
        usableWidth: CGFloat
    ) -> CGFloat {
        beatAttackCenterX(
            startPosition: slot.startPosition,
            duration: slot.duration,
            meter: meter,
            staffFrame: staffFrame,
            usableWidth: usableWidth
        )
    }

    private static func beatAttackCenterX(
        startPosition: BeatPosition,
        duration: RhythmValue,
        meter: Meter,
        staffFrame: CGRect,
        usableWidth: CGFloat
    ) -> CGFloat {
        let startOffset = startPosition.startOffset(in: meter) ?? 0
        let attackLaneLength = slashAttackLaneLength(for: duration, meter: meter)
        let attackCenterOffset = min(
            meter.measureLengthInWholeNotes,
            startOffset + attackLaneLength / 2
        )
        let centerFraction = meter.measureLengthInWholeNotes > 0
            ? attackCenterOffset / meter.measureLengthInWholeNotes
            : 0
        return staffFrame.minX + 8 + usableWidth * CGFloat(centerFraction)
    }

    private static func slashAttackLaneLength(for duration: RhythmValue, meter: Meter) -> Double {
        let durationLength = max(0, duration.wholeNoteLength)
        guard durationLength > 0 else {
            return meter.beatUnitWholeNoteLength
        }

        return min(durationLength, meter.beatUnitWholeNoteLength)
    }

    private static func isSlashEighthBeamedFromPrevious(
        at index: Int,
        slots: [MeasureRhythmSlot],
        meter: Meter
    ) -> Bool {
        guard index > 0,
              slots[index].duration == .eighth,
              slots[index - 1].duration == .eighth,
              slots[index - 1].startPosition.beat == slots[index].startPosition.beat else {
            return false
        }

        let previousStart = slots[index - 1].startPosition.startOffset(in: meter) ?? 0
        let currentStart = slots[index].startPosition.startOffset(in: meter) ?? 0
        return abs((previousStart + slots[index - 1].duration.wholeNoteLength) - currentStart) < 0.0001
    }

    private static func wholeRestLayout(
        centerX: CGFloat,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let restFrame = CGRect(
            x: centerX - 9,
            y: staffLineYPositions[1] + 1,
            width: 18,
            height: 6
        )
        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .wholeRest,
            noteheadSymbol: nil,
            noteheadFrame: restFrame,
            staffSpace: staffLineYPositions[1] - staffLineYPositions[0],
            headStyle: .whole,
            stemStart: nil,
            stemEnd: nil,
            stemGoesUp: true,
            flagStyle: .none,
            dotFrame: nil,
            tieFrame: nil,
            beamEndPoint: nil
        )
    }

    private static func halfRestLayout(
        centerX: CGFloat,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let restFrame = CGRect(
            x: centerX - 9,
            y: staffLineYPositions[2] - 6,
            width: 18,
            height: 7
        )
        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .halfRest,
            noteheadSymbol: nil,
            noteheadFrame: restFrame,
            staffSpace: staffLineYPositions[1] - staffLineYPositions[0],
            headStyle: .half,
            stemStart: nil,
            stemEnd: nil,
            stemGoesUp: true,
            flagStyle: .none,
            dotFrame: nil,
            tieFrame: nil,
            beamEndPoint: nil
        )
    }

    private static func quarterRestLayout(
        centerX: CGFloat,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let restFrame = CGRect(
            x: centerX - 7,
            y: staffLineYPositions[1] - 1,
            width: 14,
            height: 28
        )
        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .quarterRest,
            noteheadSymbol: nil,
            noteheadFrame: restFrame,
            staffSpace: staffLineYPositions[1] - staffLineYPositions[0],
            headStyle: .filled,
            stemStart: nil,
            stemEnd: nil,
            stemGoesUp: true,
            flagStyle: .none,
            dotFrame: nil,
            tieFrame: nil,
            beamEndPoint: nil
        )
    }

    private static func eighthRestLayout(
        centerX: CGFloat,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let restFrame = CGRect(
            x: centerX - 7,
            y: staffLineYPositions[1] - 2,
            width: 14,
            height: 24
        )
        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .eighthRest,
            noteheadSymbol: nil,
            noteheadFrame: restFrame,
            staffSpace: staffLineYPositions[1] - staffLineYPositions[0],
            headStyle: .filled,
            stemStart: nil,
            stemEnd: nil,
            stemGoesUp: true,
            flagStyle: .none,
            dotFrame: nil,
            tieFrame: nil,
            beamEndPoint: nil
        )
    }

    private static func headStyle(for duration: RhythmValue) -> LeadSheetNoteLayout.HeadStyle {
        switch duration {
        case .whole, .wholeRest:
            return .whole
        case .half, .dottedHalf, .halfRest:
            return .half
        case .slash, .quarter, .dottedQuarter, .eighth, .quarterRest, .eighthRest, .tiedContinuation:
            return .filled
        }
    }

    private static func dottedDuration(_ duration: RhythmValue) -> Bool {
        switch duration {
        case .dottedQuarter, .dottedHalf:
            return true
        case .slash, .eighth, .eighthRest, .quarter, .quarterRest, .half, .halfRest, .whole, .wholeRest, .tiedContinuation:
            return false
        }
    }

    static func resolvedStyleNote(for chart: Chart) -> String? {
        if let explicitStyleNote = normalizedText(chart.styleNote), !explicitStyleNote.isEmpty {
            return explicitStyleNote
        }

        switch chart.measures.first?.beatGridPreset {
        case .swung:
            return "MED. SWING"
        case .eighthSubdivision:
            return "STRAIGHT 8THS"
        case .tripletSubdivision:
            return "TRIPLET FEEL"
        case .simple, .none:
            return nil
        }
    }

    private static func normalizedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

extension LeadSheetPageLayout {
    func selectableNotes() -> [LeadSheetSelectableNote] {
        systems.flatMap { system in
            system.measures.flatMap { measure in
                guard let sourceMeasureID = measure.sourceMeasureID else {
                    return [LeadSheetSelectableNote]()
                }

                return measure.noteLayouts.enumerated().map { noteIndex, noteLayout in
                    LeadSheetSelectableNote(
                        selection: LeadSheetNoteSelection(
                            measureID: sourceMeasureID,
                            noteIndex: noteIndex
                        ),
                        noteLayout: noteLayout,
                        selectionFrame: noteLayout.selectionFrame,
                        selectionAnchor: noteLayout.selectionAnchor
                    )
                }
            }
        }
    }

    func noteSelection(in lassoFrame: CGRect) -> LeadSheetNoteSelection? {
        let normalizedLassoFrame = lassoFrame.standardized.insetBy(dx: -6, dy: -6)
        guard normalizedLassoFrame.width >= 8,
              normalizedLassoFrame.height >= 8 else {
            return nil
        }

        let lassoCenter = CGPoint(
            x: normalizedLassoFrame.midX,
            y: normalizedLassoFrame.midY
        )
        let candidates = selectableNotes().compactMap { note -> (score: CGFloat, note: LeadSheetSelectableNote)? in
            let containsAnchor = normalizedLassoFrame.contains(note.selectionAnchor)
            let intersectsFrame = normalizedLassoFrame.intersects(note.selectionFrame)
            guard containsAnchor || intersectsFrame else {
                return nil
            }

            let dx = note.selectionAnchor.x - lassoCenter.x
            let dy = note.selectionAnchor.y - lassoCenter.y
            let anchorDistance = sqrt(dx * dx + dy * dy)
            let intersectionPenalty: CGFloat = containsAnchor ? 0 : 1_000
            return (intersectionPenalty + anchorDistance, note)
        }

        return candidates.min { $0.score < $1.score }?.note.selection
    }
}

extension LeadSheetNoteLayout {
    var selectionAnchor: CGPoint {
        noteheadFrame.center
    }

    var selectionFrame: CGRect {
        var frame = noteheadFrame.insetBy(dx: -8, dy: -8)

        if let stemStart,
           let stemEnd {
            frame = frame.union(CGRect.lineFrame(from: stemStart, to: stemEnd).insetBy(dx: -8, dy: -8))
        }

        if let dotFrame {
            frame = frame.union(dotFrame.insetBy(dx: -8, dy: -8))
        }

        if let tieFrame {
            frame = frame.union(tieFrame.insetBy(dx: -4, dy: -4))
        }

        return frame
    }
}

private struct PackedLeadSheetSystemPlan: Hashable {
    var id: UUID
    var leadingSignatureWidth: CGFloat
    var frameWidth: CGFloat
    var measures: [PackedLeadSheetMeasurePlan]
}

private struct PackedLeadSheetMeasurePlan: Hashable {
    var measure: Measure?
    var width: CGFloat
}

private struct LeadSheetEngravingMetrics {
    var measureWidthScale: CGFloat
    var systemHeight: CGFloat
    var systemSpacing: CGFloat
    var staffLineSpacing: CGFloat
    var chordBandHeight: CGFloat
    var firstSystemSignatureWidth: CGFloat
    var continuationSystemSignatureWidth: CGFloat
}

private extension EngravingPreset {
    var layoutMetrics: LeadSheetEngravingMetrics {
        switch self {
        case .compact:
            return LeadSheetEngravingMetrics(
                measureWidthScale: 0.88,
                systemHeight: 124,
                systemSpacing: 18,
                staffLineSpacing: 9.8,
                chordBandHeight: 48,
                firstSystemSignatureWidth: 74,
                continuationSystemSignatureWidth: 16
            )
        case .balanced:
            return LeadSheetEngravingMetrics(
                measureWidthScale: 1,
                systemHeight: 132,
                systemSpacing: 22,
                staffLineSpacing: 10.5,
                chordBandHeight: 52,
                firstSystemSignatureWidth: 78,
                continuationSystemSignatureWidth: 18
            )
        case .wide:
            return LeadSheetEngravingMetrics(
                measureWidthScale: 1.18,
                systemHeight: 140,
                systemSpacing: 26,
                staffLineSpacing: 11.2,
                chordBandHeight: 56,
                firstSystemSignatureWidth: 82,
                continuationSystemSignatureWidth: 20
            )
        case .bold:
            return LeadSheetEngravingMetrics(
                measureWidthScale: 1.04,
                systemHeight: 137,
                systemSpacing: 24,
                staffLineSpacing: 10.8,
                chordBandHeight: 54,
                firstSystemSignatureWidth: 80,
                continuationSystemSignatureWidth: 18
            )
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    static func lineFrame(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(start.x - end.x)),
            height: max(1, abs(start.y - end.y))
        )
    }
}
