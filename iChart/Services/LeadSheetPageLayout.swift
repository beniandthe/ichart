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
    var handwrittenFrame: CGRect
    var titleFrame: CGRect
    var composerFrame: CGRect?
    var styleNoteFrame: CGRect?
    var keyFrame: CGRect?
    var meterFrame: CGRect?
}

struct LeadSheetSystemLayout: Identifiable, Hashable {
    var id: UUID
    var index: Int
    var frame: CGRect
    var staffLineYPositions: [CGFloat]
    var clefFrame: CGRect?
    var keySignatureLayouts: [LeadSheetKeySignatureLayout]
    var timeSignatureFrame: CGRect?
    var sectionTextFrame: CGRect?
    var sectionText: String?
    var roadmapTextFrame: CGRect?
    var roadmapText: String?
    var roadmapMarkerLayouts: [LeadSheetRoadmapMarkerLayout]
    var endingLayouts: [LeadSheetEndingLayout]
    var measures: [LeadSheetMeasureLayout]
}

struct LeadSheetKeySignatureLayout: Hashable {
    var symbol: NotationGlyphCatalog.Symbol
    var frame: CGRect
    var staffOffset: CGFloat
    var staffSpace: CGFloat
}

struct LeadSheetMeasureLayout: Identifiable, Hashable {
    var id: UUID
    var sourceMeasureID: UUID?
    var index: Int
    var frame: CGRect
    var staffFrame: CGRect
    var freehandAboveFrame: CGRect?
    var freehandBelowFrame: CGRect?
    var chordBandFrame: CGRect
    var writableFrame: CGRect
    var chordLayouts: [LeadSheetChordLayout]
    var noteLayouts: [LeadSheetNoteLayout]
    var repeatMarkerLayouts: [LeadSheetRepeatMarkerLayout]
    var cueTextLayouts: [LeadSheetCueTextLayout]
    var leadingBarline: BarlineType?
    var barlineAfter: BarlineType
    var meterChange: Meter?
    var meterChangeFrame: CGRect?
    var trailingBarlineFrame: CGRect
    var isOpen: Bool
}

extension LeadSheetMeasureLayout {
    var chordWritingFrame: CGRect {
        if chordBandFrame.minY >= staffFrame.minY {
            return frame.insetBy(dx: 2, dy: 2)
        }

        let topY = frame.minY
        let bottomY = min(
            frame.maxY - 2,
            max(staffFrame.minY + 18, chordBandFrame.maxY)
        )
        return CGRect(
            x: frame.minX + 2,
            y: topY,
            width: max(1, frame.width - 4),
            height: max(1, bottomY - topY)
        )
    }
}

struct LeadSheetChordLayout: Identifiable, Hashable {
    var id: UUID
    var text: String
    var symbol: ChordSymbol?
    var frame: CGRect
    var fitFrame: CGRect
    var horizontalCompressionScale: CGFloat
    var snapGuideTarget: CGPoint

    init(
        id: UUID,
        text: String,
        symbol: ChordSymbol? = nil,
        frame: CGRect,
        fitFrame: CGRect? = nil,
        horizontalCompressionScale: CGFloat = 1,
        snapGuideTarget: CGPoint
    ) {
        self.id = id
        self.text = text
        self.symbol = symbol
        self.frame = frame
        self.fitFrame = fitFrame ?? frame
        self.horizontalCompressionScale = horizontalCompressionScale
        self.snapGuideTarget = snapGuideTarget
    }
}

struct LeadSheetNoteLayout: Identifiable, Hashable {
    enum SymbolStyle: Hashable {
        case pitchedNote
        case slash
        case wholeRest
        case halfRest
        case quarterRest
        case sixteenthRest
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
        case double
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

struct LeadSheetRepeatMarkerLayout: Identifiable, Hashable {
    enum Edge: String, Hashable {
        case leading
        case trailing
    }

    var roadmapObjectID: UUID
    var edge: Edge
    var frame: CGRect

    var id: String {
        "\(roadmapObjectID.uuidString)-\(edge.rawValue)"
    }
}

enum LeadSheetRepeatBoundaryPolicy {
    static func leadingMarkers(atStartOf measure: LeadSheetMeasureLayout) -> [LeadSheetRepeatMarkerLayout] {
        measure.repeatMarkerLayouts.filter { $0.edge == .leading }
    }

    static func repeatMarkers(
        after measure: LeadSheetMeasureLayout,
        before nextMeasure: LeadSheetMeasureLayout?
    ) -> [LeadSheetRepeatMarkerLayout] {
        var markers = measure.repeatMarkerLayouts.filter { $0.edge == .trailing }

        if let nextMeasure {
            markers.append(
                contentsOf: nextMeasure.repeatMarkerLayouts.filter { $0.edge == .leading }
            )
        }

        return markers
    }

    static func shouldDrawNormalTrailingBarline(
        after measure: LeadSheetMeasureLayout,
        before nextMeasure: LeadSheetMeasureLayout?
    ) -> Bool {
        repeatMarkers(after: measure, before: nextMeasure).isEmpty
    }

    static func markerIDs(_ repeatMarkers: [LeadSheetRepeatMarkerLayout]) -> Set<String> {
        Set(repeatMarkers.map(\.id))
    }

    static func visibleBarlineCount(for repeatMarkers: [LeadSheetRepeatMarkerLayout]) -> Int {
        repeatMarkers.isEmpty ? 0 : 2
    }
}

struct LeadSheetEndingLayout: Identifiable, Hashable {
    var roadmapObjectID: UUID
    var systemIndex: Int
    var type: RoadmapType
    var text: String
    var frame: CGRect
    var showsText: Bool
    var showsLeadingHook: Bool
    var showsTrailingHook: Bool

    var id: String {
        "\(roadmapObjectID.uuidString)-\(systemIndex)"
    }
}

struct LeadSheetRoadmapMarkerLayout: Identifiable, Hashable {
    var roadmapObjectID: UUID
    var type: RoadmapType
    var text: String
    var frame: CGRect
    var movementFrame: CGRect
    var anchorMeasureID: UUID

    var id: UUID {
        roadmapObjectID
    }
}

struct LeadSheetCueTextLayout: Identifiable, Hashable {
    var id: UUID
    var text: String
    var frame: CGRect
    var position: CuePosition
    var emphasis: CueEmphasis
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

struct LeadSheetFreehandSymbolLayout: Identifiable, Hashable {
    var id: UUID
    var symbol: FreehandSymbol
    var frame: CGRect
    var laneFrame: CGRect
}

enum LeadSheetPageLayoutEngine {
    private static let minimumResponsivePageWidth: CGFloat = 720
    private static let mediumOpenMeasureWidth: CGFloat = 252
    private static let preferredCommittedMeasureWidth: CGFloat = 140
    private static let systemTrailingPadding: CGFloat = 6
    private static let minimumPaperWidth: CGFloat = 640
    private static let rhythmSectionChordRenderOffset: CGFloat = 16 / 3

    private struct VisualPolicy {
        let chart: Chart

        var layoutStyle: ChartLayoutStyle {
            chart.layoutStyle
        }

        var metrics: LeadSheetEngravingMetrics {
            chart.engravingPreset.layoutMetrics
        }

        var headerTitleHorizontalBleed: CGFloat { 34 }
        var headerTitleTopInset: CGFloat { 6 }
        var headerTitleHeight: CGFloat { 54 }
        var headerMetadataTopSpacing: CGFloat { 6 }
        var headerMetadataHeight: CGFloat { 20 }
        var simpleLeadingMeterGutterWidth: CGFloat { 42 }
        var simpleTitleFrameHeight: CGFloat { 36 }
        var simpleMetadataHeight: CGFloat { 24 }
        var simpleChordHorizontalInset: CGFloat { 6 }

        func headerTitleFrame(in frame: CGRect) -> CGRect {
            guard layoutStyle == .simpleChordSheet else {
                return CGRect(
                    x: frame.minX - headerTitleHorizontalBleed,
                    y: frame.minY + headerTitleTopInset,
                    width: frame.width + headerTitleHorizontalBleed * 2,
                    height: headerTitleHeight
                )
            }

            return CGRect(
                x: frame.minX - headerTitleHorizontalBleed,
                y: frame.minY + 12,
                width: frame.width + headerTitleHorizontalBleed * 2,
                height: simpleTitleFrameHeight
            )
        }

        func headerMetadataFrameY(after titleFrame: CGRect) -> CGFloat {
            if layoutStyle == .simpleChordSheet {
                return titleFrame.maxY - 2
            }

            return titleFrame.maxY + headerMetadataTopSpacing
        }

        var resolvedHeaderMetadataHeight: CGFloat {
            layoutStyle == .simpleChordSheet ? simpleMetadataHeight : headerMetadataHeight
        }

        var showsHeaderMeter: Bool {
            layoutStyle == .leadSheet
        }

        func simpleInitialTimeSignatureFrame(
            in systemFrame: CGRect,
            staffFrame: CGRect,
            leadingSignatureWidth: CGFloat
        ) -> CGRect {
            CGRect(
                x: systemFrame.minX + 3,
                y: staffFrame.midY - 28,
                width: max(24, leadingSignatureWidth - 10),
                height: 56
            )
        }

        func inlineMeterChangeFrame(
            in measureFrame: CGRect,
            staffFrame: CGRect
        ) -> CGRect {
            let isSimpleChordSheet = layoutStyle == .simpleChordSheet
            return CGRect(
                x: measureFrame.minX + (isSimpleChordSheet ? 8 : 6),
                y: isSimpleChordSheet ? staffFrame.midY - 27 : staffFrame.minY - 12,
                width: isSimpleChordSheet ? 24 : 24,
                height: 54
            )
        }
    }

    private static func paperHorizontalInset(for resolvedPageWidth: CGFloat) -> CGFloat {
        resolvedPageWidth >= 1180 ? 18 : 24
    }

    private static func paperWidth(for chart: Chart, resolvedPageWidth: CGFloat) -> CGFloat {
        guard chart.layoutStyle != .leadSheet else {
            return min(860, max(minimumPaperWidth, resolvedPageWidth - 140))
        }

        let inset = paperHorizontalInset(for: resolvedPageWidth)
        return max(minimumPaperWidth, resolvedPageWidth - inset * 2)
    }

    static func pageLayout(for chart: Chart, pageSize: CGSize) -> LeadSheetPageLayout {
        let visualPolicy = VisualPolicy(chart: chart)
        let resolvedPageSize = CGSize(
            width: max(pageSize.width, minimumResponsivePageWidth),
            height: max(pageSize.height, 1100)
        )
        let pageBounds = CGRect(origin: .zero, size: resolvedPageSize)
        let paperWidth = paperWidth(for: chart, resolvedPageWidth: resolvedPageSize.width)
        let horizontalInset = max(0, (resolvedPageSize.width - paperWidth) / 2)
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
        let header = headerLayout(for: chart, in: headerFrame, visualPolicy: visualPolicy)

        let systemFrames = systemLayouts(
            for: chart,
            paperFrame: paperFrame,
            firstSystemTop: headerFrame.maxY + 24,
            visualPolicy: visualPolicy
        )

        return LeadSheetPageLayout(
            pageBounds: pageBounds,
            paperFrame: paperFrame,
            header: header,
            systems: systemFrames
        )
    }

    private static func estimatedPaperHeight(for chart: Chart, paperWidth: CGFloat) -> CGFloat {
        let metrics = VisualPolicy(chart: chart).metrics
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
        let resolvedPageWidth = max(pageWidth, minimumResponsivePageWidth)
        let paperWidth = paperWidth(for: chart, resolvedPageWidth: resolvedPageWidth)
        return max(1, packedSystemPlans(for: chart, maxSystemWidth: paperWidth - 68).count)
    }

    private static func headerLayout(
        for chart: Chart,
        in frame: CGRect,
        visualPolicy: VisualPolicy
    ) -> LeadSheetHeaderLayout {
        let composerCredit = normalizedText(chart.composerCredit)
        let titleFrame = visualPolicy.headerTitleFrame(in: frame)
        let metadataY = visualPolicy.headerMetadataFrameY(after: titleFrame)
        let metadataHeight = visualPolicy.resolvedHeaderMetadataHeight
        let sideMetadataWidth = min(220, frame.width * 0.32)

        let composerFrame: CGRect?
        if let composerCredit, !composerCredit.isEmpty {
            composerFrame = CGRect(
                x: frame.maxX - sideMetadataWidth,
                y: metadataY,
                width: sideMetadataWidth,
                height: metadataHeight
            )
        } else {
            composerFrame = nil
        }

        let styleNoteFrame: CGRect?
        if let styleNote = resolvedStyleNote(for: chart), !styleNote.isEmpty {
            styleNoteFrame = CGRect(
                x: frame.minX,
                y: metadataY,
                width: sideMetadataWidth,
                height: metadataHeight
            )
        } else {
            styleNoteFrame = nil
        }

        let centerMetadataWidth: CGFloat = chart.layoutStyle.profile.setupPolicy.includesKeySelection ? 150 : 88
        let centerMetadataX = frame.midX - centerMetadataWidth / 2
        let keyFrame: CGRect?
        if chart.layoutStyle.profile.setupPolicy.includesKeySelection {
            keyFrame = CGRect(
                x: centerMetadataX,
                y: metadataY,
                width: 78,
                height: metadataHeight
            )
        } else {
            keyFrame = nil
        }
        let meterFrame: CGRect?
        if visualPolicy.showsHeaderMeter {
            let meterX = keyFrame == nil ? centerMetadataX : centerMetadataX + 88
            meterFrame = CGRect(
                x: meterX,
                y: metadataY,
                width: keyFrame == nil ? centerMetadataWidth : 62,
                height: metadataHeight
            )
        } else {
            meterFrame = nil
        }

        let headerContentFrames = [
            titleFrame,
            composerFrame,
            styleNoteFrame,
            keyFrame,
            meterFrame
        ].compactMap { $0 }
        let handwrittenFrame = headerContentFrames
            .dropFirst()
            .reduce(headerContentFrames.first ?? frame) { partialFrame, contentFrame in
                partialFrame.union(contentFrame)
            }
            .union(frame)
            .insetBy(dx: 0, dy: -4)

        return LeadSheetHeaderLayout(
            frame: frame,
            handwrittenFrame: handwrittenFrame,
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
        firstSystemTop: CGFloat,
        visualPolicy: VisualPolicy
    ) -> [LeadSheetSystemLayout] {
        let plans = packedSystemPlans(for: chart, maxSystemWidth: paperFrame.width - 68)
        let metrics = visualPolicy.metrics

        return plans.enumerated().map { systemIndex, plan in
            let systemFrame = CGRect(
                x: paperFrame.minX + 34,
                y: firstSystemTop + CGFloat(systemIndex) * (metrics.systemHeight + metrics.systemSpacing),
                width: min(paperFrame.width - 68, plan.frameWidth),
                height: metrics.systemHeight
            )
            return systemLayout(
                for: plan,
                chart: chart,
                index: systemIndex,
                frame: systemFrame,
                visualPolicy: visualPolicy
            )
        }
    }

    private static func systemLayout(
        for plan: PackedLeadSheetSystemPlan,
        chart: Chart,
        index: Int,
        frame: CGRect,
        visualPolicy: VisualPolicy
    ) -> LeadSheetSystemLayout {
        let metrics = visualPolicy.metrics
        let lineSpacing = metrics.staffLineSpacing
        let chordBandHeight = metrics.chordBandHeight
        let isSimpleChordSheet = chart.layoutStyle == .simpleChordSheet
        let isRhythmSectionSheet = chart.layoutStyle == .rhythmSectionSheet
        let staffTop: CGFloat
        if isSimpleChordSheet {
            staffTop = frame.minY + 24
        } else if isRhythmSectionSheet {
            staffTop = frame.minY + chordBandHeight + 6
        } else {
            staffTop = frame.minY + chordBandHeight + 2
        }
        let staffLineYPositions = isSimpleChordSheet
            ? []
            : (0..<5).map { staffTop + CGFloat($0) * lineSpacing }
        let simpleChordGridHeight = min(76, max(56, frame.height - 46))
        let staffFrame = CGRect(
            x: frame.minX,
            y: staffTop - 2,
            width: frame.width,
            height: isSimpleChordSheet ? simpleChordGridHeight : lineSpacing * 4 + 4
        )
        let measureStartX = frame.minX + plan.leadingSignatureWidth

        let shouldShowLeadingNotation = index == 0 && !isSimpleChordSheet
        let shouldShowSimpleTimeSignature = index == 0 && isSimpleChordSheet
        let clefFrame = shouldShowLeadingNotation
            ? CGRect(x: frame.minX, y: staffTop - 12, width: 26, height: 54)
            : nil
        let keyLayouts = shouldShowLeadingNotation && chart.layoutStyle == .leadSheet
            ? keySignatureLayouts(
                for: chart,
                staffLineYPositions: staffLineYPositions,
                startX: (clefFrame?.maxX ?? frame.minX) + 6,
                staffSpace: lineSpacing
            )
            : []
        let timeSignatureX = keyLayouts.last.map { $0.frame.maxX + 7 } ?? (frame.minX + 28)
        let timeSignatureFrame: CGRect?
        if shouldShowLeadingNotation {
            timeSignatureFrame = CGRect(x: timeSignatureX, y: staffTop - 13, width: 24, height: 56)
        } else if shouldShowSimpleTimeSignature {
            timeSignatureFrame = visualPolicy.simpleInitialTimeSignatureFrame(
                in: frame,
                staffFrame: staffFrame,
                leadingSignatureWidth: plan.leadingSignatureWidth
            )
        } else {
            timeSignatureFrame = nil
        }
        let measureIDs = plan.measures.compactMap(\.measure?.id)
        let sectionText = chart.sectionLabels.first(where: { measureIDs.contains($0.anchorMeasureID) })?.text
        let sectionTextFrame = sectionText.map { _ in
            CGRect(
                x: frame.minX,
                y: frame.minY + (isRhythmSectionSheet ? 1 : 2),
                width: isRhythmSectionSheet ? 96 : 140,
                height: isRhythmSectionSheet ? 20 : 18
            )
        }
        let hasEndingLayouts = chart.roadmapObjects.contains {
            roadmapObject($0, intersects: measureIDs, in: chart)
        }
        let hasPointMarkerLayouts = chart.roadmapObjects.contains {
            $0.type.isPointMarker && measureIDs.contains($0.startMeasureID)
        }
        let roadmapTopReserveHeight: CGFloat
        if isSimpleChordSheet {
            roadmapTopReserveHeight = 0
        } else {
            let structuredRoadmapReserveHeight: CGFloat
            if hasPointMarkerLayouts && hasEndingLayouts {
                structuredRoadmapReserveHeight = 34
            } else if hasPointMarkerLayouts || hasEndingLayouts {
                structuredRoadmapReserveHeight = 20
            } else {
                structuredRoadmapReserveHeight = 0
            }
            let rhythmSectionLabelReserveHeight: CGFloat = isRhythmSectionSheet && sectionText != nil ? 22 : 0
            roadmapTopReserveHeight = max(structuredRoadmapReserveHeight, rhythmSectionLabelReserveHeight)
        }
        let roadmapText = chart.roadmapObjects.first(where: {
            !$0.type.usesStructuredLayout
                && (measureIDs.contains($0.startMeasureID) || ($0.endMeasureID.map(measureIDs.contains) ?? false))
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
                roadmapTopReserveHeight: roadmapTopReserveHeight,
                staffLineYPositions: staffLineYPositions,
                layoutStyle: chart.layoutStyle,
                visualPolicy: visualPolicy,
                meterChange: meterChange(for: measurePlan.measure, in: chart)
            )
        }
        let roadmapMarkerLayouts = roadmapMarkerLayouts(
            for: chart,
            systemFrame: frame,
            measureLayouts: measures
        )
        let endingLayouts = endingLayouts(
            for: chart,
            systemIndex: index,
            systemFrame: frame,
            topOffset: hasPointMarkerLayouts ? 14 : 0,
            measureLayouts: measures
        )

        return LeadSheetSystemLayout(
            id: plan.id,
            index: index,
            frame: frame,
            staffLineYPositions: staffLineYPositions,
            clefFrame: clefFrame,
            keySignatureLayouts: keyLayouts,
            timeSignatureFrame: timeSignatureFrame,
            sectionTextFrame: sectionTextFrame,
            sectionText: sectionText,
            roadmapTextFrame: roadmapTextFrame,
            roadmapText: roadmapText,
            roadmapMarkerLayouts: roadmapMarkerLayouts,
            endingLayouts: endingLayouts,
            measures: measures
        )
    }

    private static func roadmapObject(
        _ roadmapObject: RoadmapObject,
        intersects measureIDs: [UUID],
        in chart: Chart
    ) -> Bool {
        guard roadmapObject.type.isEnding,
              let endMeasureID = roadmapObject.endMeasureID else {
            return false
        }

        let orderedMeasureIDs = chart.measures.map(\.id)
        guard let startIndex = orderedMeasureIDs.firstIndex(of: roadmapObject.startMeasureID),
              let endIndex = orderedMeasureIDs.firstIndex(of: endMeasureID),
              startIndex <= endIndex else {
            return false
        }

        return measureIDs.contains { measureID in
            guard let measureIndex = orderedMeasureIDs.firstIndex(of: measureID) else {
                return false
            }

            return measureIndex >= startIndex && measureIndex <= endIndex
        }
    }

    private static func endingLayouts(
        for chart: Chart,
        systemIndex: Int,
        systemFrame: CGRect,
        topOffset: CGFloat,
        measureLayouts: [LeadSheetMeasureLayout]
    ) -> [LeadSheetEndingLayout] {
        let orderedMeasureIDs = chart.measures.map(\.id)
        let indexedMeasureLayouts = measureLayouts.compactMap { measureLayout -> (layout: LeadSheetMeasureLayout, index: Int)? in
            guard let sourceMeasureID = measureLayout.sourceMeasureID,
                  let measureIndex = orderedMeasureIDs.firstIndex(of: sourceMeasureID) else {
                return nil
            }

            return (measureLayout, measureIndex)
        }
        guard !indexedMeasureLayouts.isEmpty else {
            return []
        }

        return chart.roadmapObjects
            .filter { $0.type.isEnding }
            .compactMap { roadmapObject in
                guard let endMeasureID = roadmapObject.endMeasureID,
                      let startIndex = orderedMeasureIDs.firstIndex(of: roadmapObject.startMeasureID),
                      let endIndex = orderedMeasureIDs.firstIndex(of: endMeasureID),
                      startIndex <= endIndex else {
                    return nil
                }

                let segmentMeasures = indexedMeasureLayouts.filter {
                    $0.index >= startIndex && $0.index <= endIndex
                }
                guard let firstSegmentMeasure = segmentMeasures.first,
                      let lastSegmentMeasure = segmentMeasures.last else {
                    return nil
                }

                let startX = firstSegmentMeasure.layout.staffFrame.minX + 4
                let endX = lastSegmentMeasure.layout.staffFrame.maxX - 4
                let frame = CGRect(
                    x: startX,
                    y: systemFrame.minY + 3 + topOffset,
                    width: max(1, endX - startX),
                    height: 16
                )
                let text = roadmapObject.displayText
                    ?? roadmapObject.type.compactEndingDisplayText
                    ?? roadmapObject.resolvedDisplayText

                return LeadSheetEndingLayout(
                    roadmapObjectID: roadmapObject.id,
                    systemIndex: systemIndex,
                    type: roadmapObject.type,
                    text: text,
                    frame: frame,
                    showsText: firstSegmentMeasure.index == startIndex,
                    showsLeadingHook: firstSegmentMeasure.index == startIndex,
                    showsTrailingHook: lastSegmentMeasure.index == endIndex
                )
            }
    }

    private static func roadmapMarkerLayouts(
        for chart: Chart,
        systemFrame: CGRect,
        measureLayouts: [LeadSheetMeasureLayout]
    ) -> [LeadSheetRoadmapMarkerLayout] {
        let measureLayoutByID = Dictionary(
            uniqueKeysWithValues: measureLayouts.compactMap { measureLayout -> (UUID, LeadSheetMeasureLayout)? in
                guard let sourceMeasureID = measureLayout.sourceMeasureID else {
                    return nil
                }

                return (sourceMeasureID, measureLayout)
            }
        )

        return chart.roadmapObjects
            .filter { $0.type.isPointMarker }
            .compactMap { roadmapObject in
                guard let measureLayout = measureLayoutByID[roadmapObject.startMeasureID] else {
                    return nil
                }

                let text = roadmapObject.resolvedDisplayText
                let isSimpleChordSheet = chart.layoutStyle == .simpleChordSheet
                let containsNotationGlyph = roadmapObject.type.containsNotationMarkerGlyph
                let markerHeight: CGFloat
                let markerTopOffset: CGFloat
                if isSimpleChordSheet {
                    markerHeight = containsNotationGlyph ? 40 : 34
                    markerTopOffset = containsNotationGlyph ? -17 : -14
                } else {
                    markerHeight = containsNotationGlyph ? 28 : 24
                    markerTopOffset = containsNotationGlyph ? -8 : -5
                }
                let movementFrame = CGRect(
                    x: measureLayout.staffFrame.minX + 6,
                    y: systemFrame.minY + markerTopOffset,
                    width: max(1, measureLayout.staffFrame.width - 12),
                    height: markerHeight
                )
                let markerWidth = roadmapMarkerWidth(
                    for: text,
                    type: roadmapObject.type,
                    maxWidth: movementFrame.width,
                    isSimpleChordSheet: isSimpleChordSheet
                )
                let horizontalOffset = roadmapObject.resolvedHorizontalOffsetWithinMeasure
                let availableWidth = max(0, movementFrame.width - markerWidth)
                return LeadSheetRoadmapMarkerLayout(
                    roadmapObjectID: roadmapObject.id,
                    type: roadmapObject.type,
                    text: text,
                    frame: CGRect(
                        x: movementFrame.minX + availableWidth * CGFloat(horizontalOffset),
                        y: movementFrame.minY,
                        width: markerWidth,
                        height: markerHeight
                    ),
                    movementFrame: movementFrame,
                    anchorMeasureID: roadmapObject.startMeasureID
                )
            }
    }

    private static func roadmapMarkerWidth(
        for text: String,
        type: RoadmapType,
        maxWidth: CGFloat,
        isSimpleChordSheet: Bool
    ) -> CGFloat {
        let minimumWidth: CGFloat
        if type.isStandaloneNotationMarker {
            minimumWidth = isSimpleChordSheet ? 42 : 28
        } else {
            minimumWidth = isSimpleChordSheet ? 34 : 24
        }
        let characterWidth: CGFloat = isSimpleChordSheet ? 13 : 7.2
        let textWidth: CGFloat

        if type.isStandaloneNotationMarker {
            textWidth = minimumWidth
        } else {
            textWidth = CGFloat(text.count) * characterWidth + (isSimpleChordSheet ? 18 : 12)
        }

        return min(max(minimumWidth, textWidth), max(1, maxWidth))
    }

    private static func packedSystemPlans(
        for chart: Chart,
        maxSystemWidth: CGFloat
    ) -> [PackedLeadSheetSystemPlan] {
        let visualPolicy = VisualPolicy(chart: chart)
        let sourceMeasures = chart.measures
        guard !sourceMeasures.isEmpty else {
            let metrics = visualPolicy.metrics
            let leadingSignatureWidth = leadingSignatureWidth(
                for: chart,
                visualPolicy: visualPolicy,
                systemIndex: 0
            )
            return [
                PackedLeadSheetSystemPlan(
                    id: UUID(),
                    leadingSignatureWidth: leadingSignatureWidth,
                    frameWidth: leadingSignatureWidth
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

        let metrics = visualPolicy.metrics
        if chart.layoutStyle == .simpleChordSheet {
            return simpleChordSheetSystemPlans(
                for: chart,
                maxSystemWidth: maxSystemWidth,
                metrics: metrics,
                visualPolicy: visualPolicy
            )
        }

        var plans: [PackedLeadSheetSystemPlan] = []
        var currentMeasures: [PackedLeadSheetMeasurePlan] = []
        var currentSystemIndex = 0
        var currentLeadingSignatureWidth = leadingSignatureWidth(
            for: chart,
            visualPolicy: visualPolicy,
            systemIndex: currentSystemIndex
        )
        var currentBodyWidth: CGFloat = 0
        let forcedBreakStartIDs = chart.layoutStyle == .rhythmSectionSheet
            ? forcedSystemBreakStartIDs(for: chart)
            : Set<UUID>()

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
            currentSystemIndex += 1
            currentLeadingSignatureWidth = leadingSignatureWidth(
                for: chart,
                visualPolicy: visualPolicy,
                systemIndex: currentSystemIndex
            )
            currentBodyWidth = 0
        }

        for measure in sourceMeasures {
            if !currentMeasures.isEmpty && forcedBreakStartIDs.contains(measure.id) {
                flushCurrentSystem()
            }

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
        guard chart.layoutStyle == .rhythmSectionSheet else {
            return plans
        }

        return standardizedRhythmSectionSystemPlans(plans, maxSystemWidth: maxSystemWidth)
    }

    private static func forcedSystemBreakStartIDs(for chart: Chart) -> Set<UUID> {
        Set(
            chart.systems
                .dropFirst()
                .filter { $0.lineBreakRule == .forced }
                .compactMap(\.measures.first?.id)
        )
    }

    private static func standardizedRhythmSectionSystemPlans(
        _ plans: [PackedLeadSheetSystemPlan],
        maxSystemWidth: CGFloat
    ) -> [PackedLeadSheetSystemPlan] {
        guard let firstPlan = plans.first,
              let firstMeasure = firstPlan.measures.first else {
            return plans
        }

        let firstBodyWidth = max(1, maxSystemWidth - firstPlan.leadingSignatureWidth - systemTrailingPadding)
        let firstPreferredBodyWidth = firstPlan.measures.map(\.width).reduce(0, +)
        guard firstPreferredBodyWidth > 0 else {
            return plans
        }

        let maxMeasureCount = max(1, plans.map(\.measures.count).max() ?? 1)
        let largestBodyWidth = max(
            1,
            plans
                .map { maxSystemWidth - $0.leadingSignatureWidth - systemTrailingPadding }
                .min() ?? firstBodyWidth
        )
        let firstScale = firstBodyWidth / firstPreferredBodyWidth
        let firstSystemMeasureWidth = firstMeasure.width * firstScale
        let standardMeasureWidth = min(
            firstSystemMeasureWidth,
            largestBodyWidth / CGFloat(maxMeasureCount)
        )

        return plans.map { plan in
            standardizedRhythmSectionSystemPlan(
                plan,
                standardMeasureWidth: standardMeasureWidth
            )
        }
    }

    private static func standardizedRhythmSectionSystemPlan(
        _ plan: PackedLeadSheetSystemPlan,
        standardMeasureWidth: CGFloat
    ) -> PackedLeadSheetSystemPlan {
        let standardizedMeasures = plan.measures.map { measurePlan in
            let width: CGFloat
            if let manualLayoutWidth = measurePlan.measure?.manualLayoutWidth {
                width = Measure.clampedManualLayoutWidth(CGFloat(manualLayoutWidth))
            } else {
                width = standardMeasureWidth
            }

            return PackedLeadSheetMeasurePlan(
                measure: measurePlan.measure,
                width: width
            )
        }
        let bodyWidth = standardizedMeasures.map(\.width).reduce(0, +)

        return PackedLeadSheetSystemPlan(
            id: plan.id,
            leadingSignatureWidth: plan.leadingSignatureWidth,
            frameWidth: plan.leadingSignatureWidth + bodyWidth + systemTrailingPadding,
            measures: standardizedMeasures
        )
    }

    private static func simpleChordSheetSystemPlans(
        for chart: Chart,
        maxSystemWidth: CGFloat,
        metrics: LeadSheetEngravingMetrics,
        visualPolicy: VisualPolicy
    ) -> [PackedLeadSheetSystemPlan] {
        let cap = chart.layoutStyle.profile.measureDefaults.maximumMeasuresPerSystem
            ?? max(1, chart.measures.count)
        let leadingSignatureWidth = leadingSignatureWidth(
            for: chart,
            visualPolicy: visualPolicy,
            systemIndex: 0
        )
        let bodyWidth = max(1, maxSystemWidth - leadingSignatureWidth - systemTrailingPadding)
        let preferredMeasuresPerSystem = max(
            1,
            chart.layoutStyle.profile.measureDefaults.preferredMeasuresPerSystem
        )
        let standardMeasureWidth = bodyWidth / CGFloat(preferredMeasuresPerSystem)
        var plans: [PackedLeadSheetSystemPlan] = []

        func appendPlan(for measures: [Measure], id: UUID) {
            let weights = measures.map {
                simpleChordSheetMeasureWeight(for: $0, metrics: metrics)
            }
            let measurePlans: [PackedLeadSheetMeasurePlan]
            let rowBodyWidth: CGFloat
            let totalWeight = max(1, weights.reduce(0, +))

            if measures.count <= preferredMeasuresPerSystem,
               totalWeight <= CGFloat(preferredMeasuresPerSystem) {
                measurePlans = zip(measures, weights).map { measure, weight in
                    PackedLeadSheetMeasurePlan(
                        measure: measure,
                        width: standardMeasureWidth * weight
                    )
                }
                rowBodyWidth = measurePlans.map(\.width).reduce(0, +)
            } else {
                measurePlans = zip(measures, weights).map { measure, weight in
                    PackedLeadSheetMeasurePlan(
                        measure: measure,
                        width: bodyWidth * weight / totalWeight
                    )
                }
                rowBodyWidth = bodyWidth
            }

            plans.append(
                PackedLeadSheetSystemPlan(
                    id: id,
                    leadingSignatureWidth: leadingSignatureWidth,
                    frameWidth: leadingSignatureWidth + rowBodyWidth + systemTrailingPadding,
                    measures: measurePlans
                )
            )
        }

        for system in chart.systems where !system.measures.isEmpty {
            var cursor = 0
            while cursor < system.measures.count {
                let chunkEnd = min(cursor + cap, system.measures.count)
                let chunk = Array(system.measures[cursor..<chunkEnd])
                appendPlan(for: chunk, id: cursor == 0 ? system.id : UUID())
                cursor = chunkEnd
            }
        }

        if plans.isEmpty {
            appendPlan(for: chart.measures, id: chart.systems.first?.id ?? UUID())
        }

        return plans
    }

    private static func simpleChordSheetMeasureWeight(
        for measure: Measure,
        metrics: LeadSheetEngravingMetrics
    ) -> CGFloat {
        guard let manualLayoutWidth = measure.manualLayoutWidth else {
            return 1
        }

        let defaultWidth = preferredCommittedMeasureWidth * metrics.measureWidthScale
        return max(0.25, CGFloat(manualLayoutWidth) / max(1, defaultWidth))
    }

    private static func leadingSignatureWidth(
        for chart: Chart,
        visualPolicy: VisualPolicy,
        systemIndex: Int
    ) -> CGFloat {
        if chart.layoutStyle == .simpleChordSheet {
            return visualPolicy.simpleLeadingMeterGutterWidth
        }
        let metrics = visualPolicy.metrics
        if chart.layoutStyle == .rhythmSectionSheet {
            return metrics.firstSystemSignatureWidth
        }
        guard systemIndex == 0 else { return metrics.continuationSystemSignatureWidth }

        let keySignatureWidth = chart.layoutStyle == .leadSheet
            ? CGFloat(keySignatureAccidentalCount(for: chart.documentKey.transposed(for: chart.defaultTranspositionView))) * 10
            : 0
        return metrics.firstSystemSignatureWidth + keySignatureWidth
    }

    private static func keySignatureLayouts(
        for chart: Chart,
        staffLineYPositions: [CGFloat],
        startX: CGFloat,
        staffSpace: CGFloat
    ) -> [LeadSheetKeySignatureLayout] {
        guard let accidentalGroup = keySignatureAccidentals(
            for: chart.documentKey.transposed(for: chart.defaultTranspositionView)
        ),
            let topStaffLineY = staffLineYPositions.first else {
            return []
        }

        let offsets = keySignatureStaffOffsets(kind: accidentalGroup.kind, clef: chart.defaultClef)
        let symbol: NotationGlyphCatalog.Symbol = accidentalGroup.kind == .sharps
            ? .accidentalSharp
            : .accidentalFlat
        let accidentalAdvance = max(8, staffSpace * 0.95)
        let accidentalWidth = max(7, staffSpace)
        let accidentalHeight = staffSpace * 2.1

        return (0..<accidentalGroup.count).map { index in
            let staffOffset = offsets[index]
            let centerY = topStaffLineY + staffOffset * staffSpace
            return LeadSheetKeySignatureLayout(
                symbol: symbol,
                frame: CGRect(
                    x: startX + CGFloat(index) * accidentalAdvance,
                    y: centerY - accidentalHeight / 2,
                    width: accidentalWidth,
                    height: accidentalHeight
                ),
                staffOffset: staffOffset,
                staffSpace: staffSpace
            )
        }
    }

    private static func keySignatureAccidentalCount(for key: DocumentKey) -> Int {
        keySignatureAccidentals(for: key)?.count ?? 0
    }

    private static func keySignatureAccidentals(
        for key: DocumentKey
    ) -> (kind: LeadSheetKeySignatureAccidentalKind, count: Int)? {
        let keyName = "\(key.tonic.rawValue)\(key.accidental.rawValue)"
        let modeName = key.mode == .minor ? "minor" : "major"

        let count: Int
        let kind: LeadSheetKeySignatureAccidentalKind
        switch (keyName, modeName) {
        case ("C", "major"), ("A", "minor"):
            return nil

        case ("G", "major"), ("E", "minor"):
            kind = .sharps
            count = 1
        case ("D", "major"), ("B", "minor"):
            kind = .sharps
            count = 2
        case ("A", "major"), ("F#", "minor"):
            kind = .sharps
            count = 3
        case ("E", "major"), ("C#", "minor"):
            kind = .sharps
            count = 4
        case ("B", "major"), ("G#", "minor"):
            kind = .sharps
            count = 5
        case ("F#", "major"), ("D#", "minor"):
            kind = .sharps
            count = 6
        case ("C#", "major"), ("A#", "minor"):
            kind = .sharps
            count = 7

        case ("F", "major"), ("D", "minor"):
            kind = .flats
            count = 1
        case ("Bb", "major"), ("G", "minor"):
            kind = .flats
            count = 2
        case ("Eb", "major"), ("C", "minor"):
            kind = .flats
            count = 3
        case ("Ab", "major"), ("F", "minor"):
            kind = .flats
            count = 4
        case ("Db", "major"), ("Bb", "minor"):
            kind = .flats
            count = 5
        case ("Gb", "major"), ("Eb", "minor"):
            kind = .flats
            count = 6
        case ("Cb", "major"), ("Ab", "minor"):
            kind = .flats
            count = 7

        default:
            return nil
        }

        return (kind: kind, count: count)
    }

    private static func keySignatureStaffOffsets(
        kind: LeadSheetKeySignatureAccidentalKind,
        clef: ChartClef
    ) -> [CGFloat] {
        switch (kind, clef) {
        case (.sharps, .treble):
            return [0, 1.5, -0.5, 1, 2.5, 0.5, 2]
        case (.flats, .treble):
            return [2, 4, 2.5, 1, 3, 1.5, 0]
        case (.sharps, .bass):
            return [1, 2.5, 4, 2, 0, 1.5, 3]
        case (.flats, .bass):
            return [3, 1.5, 0, 2, 4, 2.5, 1]
        }
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

    private static func meterChange(for measure: Measure?, in chart: Chart) -> Meter? {
        guard let measure,
              let currentMeasureIndex = chart.measures.firstIndex(where: { $0.id == measure.id }),
              currentMeasureIndex > 0 else {
            return nil
        }

        let previousMeasure = chart.measures[currentMeasureIndex - 1]
        let previousMeter = effectiveMeter(for: previousMeasure, defaultMeter: chart.defaultMeter)
        let currentMeter = effectiveMeter(for: measure, defaultMeter: chart.defaultMeter)
        return previousMeter == currentMeter ? nil : currentMeter
    }

    private static func measureLayout(
        for measure: Measure?,
        chart: Chart,
        index: Int,
        frame: CGRect,
        staffFrame: CGRect,
        chordBandHeight: CGFloat,
        roadmapTopReserveHeight: CGFloat,
        staffLineYPositions: [CGFloat],
        layoutStyle: ChartLayoutStyle,
        visualPolicy: VisualPolicy,
        meterChange: Meter?
    ) -> LeadSheetMeasureLayout {
        let isSimpleChordSheet = layoutStyle == .simpleChordSheet
        let isRhythmSectionSheet = layoutStyle == .rhythmSectionSheet
        let freehandSymbolLanes = layoutStyle.profile.freehandSymbolLanes
        let freehandAboveFrame = freehandSymbolLanes.contains(.aboveMeasure) ? CGRect(
            x: staffFrame.minX + 4,
            y: frame.minY + 2,
            width: max(1, staffFrame.width - 8),
            height: max(1, staffFrame.minY - frame.minY - 8)
        ) : nil
        let freehandBelowTopInset: CGFloat = isRhythmSectionSheet ? 4 : 6
        let freehandBelowBottomInset: CGFloat = isRhythmSectionSheet ? 0 : 2
        let freehandBelowFrame = freehandSymbolLanes.contains(.belowMeasure) ? CGRect(
            x: staffFrame.minX + 4,
            y: staffFrame.maxY + freehandBelowTopInset,
            width: max(1, staffFrame.width - 8),
            height: max(1, frame.maxY - staffFrame.maxY - freehandBelowTopInset - freehandBelowBottomInset)
        ) : nil
        let chordBandFrame = isSimpleChordSheet ? CGRect(
            x: staffFrame.minX + 8,
            y: staffFrame.minY + 4,
            width: max(1, staffFrame.width - 16),
            height: max(1, staffFrame.height - 8)
        ) : CGRect(
            x: frame.minX + 3,
            y: frame.minY + roadmapTopReserveHeight,
            width: frame.width - 6,
            height: max(1, chordBandHeight - 4 - roadmapTopReserveHeight)
        )
        let writableFrame = isSimpleChordSheet ? staffFrame.insetBy(dx: 2, dy: 2) : CGRect(
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
        let meterChangeFrame = meterChange.map { _ in
            visualPolicy.inlineMeterChangeFrame(in: frame, staffFrame: staffFrame)
        }

        guard let measure else {
            return LeadSheetMeasureLayout(
                id: UUID(),
                sourceMeasureID: nil,
                index: index + 1,
                frame: frame,
                staffFrame: staffFrame,
                freehandAboveFrame: freehandAboveFrame,
                freehandBelowFrame: freehandBelowFrame,
                chordBandFrame: chordBandFrame,
                writableFrame: writableFrame,
                chordLayouts: [],
                noteLayouts: [],
                repeatMarkerLayouts: [],
                cueTextLayouts: [],
                leadingBarline: nil,
                barlineAfter: .single,
                meterChange: meterChange,
                meterChangeFrame: meterChangeFrame,
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
        let chordLayouts = displayedPlacements.enumerated().map { placementIndex, placement in
            let nextPlacementIndex = placementIndex + 1
            let nextPlacement = displayedPlacements.indices.contains(nextPlacementIndex)
                ? displayedPlacements[nextPlacementIndex]
                : nil
            return chordLayout(
                for: placement,
                nextPlacement: nextPlacement,
                chart: chart,
                meter: meter,
                chordBandFrame: chordBandFrame,
                staffFrame: staffFrame,
                visualPolicy: visualPolicy
            )
        }
        let noteLayouts = isSimpleChordSheet ? [] : noteLayouts(
            for: measure,
            chart: chart,
            meter: meter,
            staffFrame: staffFrame,
            staffLineYPositions: staffLineYPositions
        ) ?? []
        let repeatMarkerLayouts = repeatMarkerLayouts(
            for: measure,
            chart: chart,
            staffFrame: staffFrame
        )
        let cueTextLayouts = cueTextLayouts(
            for: measure,
            chart: chart,
            measureFrame: frame,
            chordBandFrame: chordBandFrame,
            staffFrame: staffFrame
        )

        return LeadSheetMeasureLayout(
            id: measure.id,
            sourceMeasureID: measure.id,
            index: measure.index,
            frame: frame,
            staffFrame: staffFrame,
            freehandAboveFrame: freehandAboveFrame,
            freehandBelowFrame: freehandBelowFrame,
            chordBandFrame: chordBandFrame,
            writableFrame: writableFrame,
            chordLayouts: chordLayouts,
            noteLayouts: noteLayouts,
            repeatMarkerLayouts: repeatMarkerLayouts,
            cueTextLayouts: cueTextLayouts,
            leadingBarline: measure.index == 1 ? .double : nil,
            barlineAfter: measure.barlineAfter,
            meterChange: meterChange,
            meterChangeFrame: meterChangeFrame,
            trailingBarlineFrame: trailingBarlineFrame,
            isOpen: measure.authoringState == .open
        )
    }

    private static func chordLayout(
        for placement: MeasureChordPlacement,
        nextPlacement: MeasureChordPlacement?,
        chart: Chart,
        meter: Meter,
        chordBandFrame: CGRect,
        staffFrame: CGRect,
        visualPolicy: VisualPolicy
    ) -> LeadSheetChordLayout {
        let displayedSymbol = chart.displayedChordSymbol(for: placement.chordEvent)
        let displayedText = displayedSymbol.displayText
        let usableWidth = staffFrame.width - 16
        let attackCenterX = beatAttackCenterX(
            startPosition: placement.startPosition,
            duration: placement.duration ?? .quarter,
            meter: meter,
            staffFrame: staffFrame,
            usableWidth: usableWidth
        )

        if visualPolicy.layoutStyle == .simpleChordSheet {
            let fitFrame = simpleChordFitFrame(
                for: placement,
                nextPlacement: nextPlacement,
                meter: meter,
                chordBandFrame: chordBandFrame,
                visualPolicy: visualPolicy
            )
            return LeadSheetChordLayout(
                id: placement.chordEvent.id,
                text: displayedText,
                symbol: displayedSymbol,
                frame: simpleChordDisplayFrame(
                    symbol: displayedSymbol,
                    text: displayedText,
                    fitFrame: fitFrame,
                    horizontalCompressionScale: 1,
                    reservesTrailingWritingSpace: simpleChordReservesTrailingWritingSpace(
                        placement: placement,
                        nextPlacement: nextPlacement,
                        meter: meter
                    )
                ),
                fitFrame: fitFrame,
                snapGuideTarget: CGPoint(x: attackCenterX, y: staffFrame.midY)
            )
        }

        let textWidth = estimatedChordTextWidth(for: displayedText)
        let chordX = min(
            max(chordBandFrame.minX + 1, attackCenterX - textWidth / 2),
            chordBandFrame.maxX - textWidth
        )
        let resolvedChordX = max(chordBandFrame.minX + 1, chordX)
        let resolvedWidth = min(textWidth, max(1, chordBandFrame.maxX - resolvedChordX))

        let structuredChordRenderOffset = visualPolicy.layoutStyle == .rhythmSectionSheet
            ? rhythmSectionChordRenderOffset
            : 0
        return LeadSheetChordLayout(
            id: placement.chordEvent.id,
            text: displayedText,
            symbol: displayedSymbol,
            frame: CGRect(
                x: resolvedChordX,
                y: chordBandFrame.minY + structuredChordRenderOffset,
                width: resolvedWidth,
                height: chordBandFrame.height
            ),
            snapGuideTarget: CGPoint(x: attackCenterX, y: staffFrame.midY)
        )
    }

    private static func simpleChordFitFrame(
        for placement: MeasureChordPlacement,
        nextPlacement: MeasureChordPlacement?,
        meter: Meter,
        chordBandFrame: CGRect,
        visualPolicy: VisualPolicy
    ) -> CGRect {
        let measureLength = max(0.0001, meter.measureLengthInWholeNotes)
        let startOffset = min(
            measureLength,
            max(0, placement.startPosition.startOffset(in: meter) ?? 0)
        )
        let nextOffset = nextPlacement?.startPosition.startOffset(in: meter)
        let proposedEndOffset = nextOffset ?? measureLength
        let endOffset = min(
            measureLength,
            max(
                startOffset + measureLength * 0.03,
                proposedEndOffset > startOffset ? proposedEndOffset : startOffset + meter.beatUnitWholeNoteLength
            )
        )
        let startFraction = startOffset / measureLength
        let endFraction = max(startFraction, endOffset / measureLength)
        let rawMinX = chordBandFrame.minX + chordBandFrame.width * CGFloat(startFraction)
        let rawMaxX = chordBandFrame.minX + chordBandFrame.width * CGFloat(endFraction)
        let inset = min(visualPolicy.simpleChordHorizontalInset, max(0, (rawMaxX - rawMinX) / 4))
        let minX = rawMinX + inset
        let maxX = max(minX + 1, rawMaxX - inset)

        return CGRect(
            x: minX,
            y: chordBandFrame.minY,
            width: max(1, maxX - minX),
            height: chordBandFrame.height
        )
    }

    private static func simpleChordDisplayFrame(
        symbol: ChordSymbol? = nil,
        text: String,
        fitFrame: CGRect,
        horizontalCompressionScale: CGFloat,
        reservesTrailingWritingSpace: Bool
    ) -> CGRect {
        let visualSlotFrame = reservesTrailingWritingSpace
            ? simpleChordPrimaryBeatVisualSlot(in: fitFrame)
            : fitFrame
        let fontSize = estimatedSimpleChordFontSize(fitting: visualSlotFrame, text: text)
        let estimatedWidth = max(
            1,
            estimatedSimpleChordTextWidth(for: symbol, fallbackText: text, fontSize: fontSize)
                * max(0.01, min(1, horizontalCompressionScale)) + 2
        )
        let frameWidth = min(estimatedWidth, visualSlotFrame.width)
        return CGRect(
            x: visualSlotFrame.minX,
            y: fitFrame.minY,
            width: frameWidth,
            height: fitFrame.height
        )
    }

    private static func simpleChordReservesTrailingWritingSpace(
        placement: MeasureChordPlacement,
        nextPlacement: MeasureChordPlacement?,
        meter: Meter
    ) -> Bool {
        guard nextPlacement == nil,
              let startOffset = placement.startPosition.startOffset(in: meter) else {
            return false
        }

        return startOffset <= meter.beatUnitWholeNoteLength * 0.05
    }

    private static func simpleChordPrimaryBeatVisualSlot(in fitFrame: CGRect) -> CGRect {
        let cappedWidth = min(
            fitFrame.width,
            max(54, fitFrame.width * 0.62)
        )
        return CGRect(
            x: fitFrame.minX,
            y: fitFrame.minY,
            width: cappedWidth,
            height: fitFrame.height
        )
    }

    private static func estimatedSimpleChordFontSize(fitting frame: CGRect, text: String) -> CGFloat {
        preferredSimpleChordFontSize()
    }

    private static func preferredSimpleChordFontSize() -> CGFloat {
        ChartTypographyResolver.simpleChordPrimaryFontSize
    }

    private static func estimatedSimpleChordTextWidth(
        for symbol: ChordSymbol?,
        fallbackText: String,
        fontSize: CGFloat
    ) -> CGFloat {
        guard let symbol else {
            return estimatedSimpleChordTextWidth(for: fallbackText, fontSize: fontSize)
        }

        let suffixFontSize = ChartTypographyResolver.simpleChordSuffixFontSize(primarySize: fontSize)
        return ChartTypographyResolver
            .estimatedChordTokenWidth(
                for: symbol,
                primaryFontSize: fontSize,
                suffixFontSize: suffixFontSize
            )
    }

    private static func estimatedSimpleChordTextWidth(
        for text: String,
        fontSize: CGFloat
    ) -> CGFloat {
        let parts = simpleChordTextParts(for: text)
        let rootBaseWidth = parts.root.reduce(CGFloat(0)) { partialWidth, character in
            partialWidth + estimatedChordCharacterWidth(character)
        }
        let suffixFontSize = ChartTypographyResolver.simpleChordSuffixFontSize(primarySize: fontSize)
        let suffixBaseWidth = parts.suffix.reduce(CGFloat(0)) { partialWidth, character in
            partialWidth + estimatedChordCharacterWidth(character)
        }
        let suffixGap = parts.suffix.isEmpty ? CGFloat(0) : ChartTypographyResolver.simpleChordTokenGapWidth
        let simpleChordFontWidthScale = ChartTypographyResolver.simpleChordEstimatedWidthScale
        return max(16, rootBaseWidth * (fontSize / 18) * simpleChordFontWidthScale)
            + suffixGap
            + suffixBaseWidth * (suffixFontSize / 18) * simpleChordFontWidthScale
    }

    private static func simpleChordTextParts(for text: String) -> (root: String, suffix: String) {
        guard let firstCharacter = text.first,
              "ABCDEFG".contains(firstCharacter) else {
            return (text, "")
        }

        var rootEnd = text.index(after: text.startIndex)
        if rootEnd < text.endIndex,
           ["b", "♭", "#", "♯"].contains(text[rootEnd]) {
            rootEnd = text.index(after: rootEnd)
        }

        return (
            String(text[..<rootEnd]),
            String(text[rootEnd...])
        )
    }

    private static func repeatMarkerLayouts(
        for measure: Measure,
        chart: Chart,
        staffFrame: CGRect
    ) -> [LeadSheetRepeatMarkerLayout] {
        let staffSpace = max(CGFloat(1), staffFrame.height / 4)
        let markerWidth = chart.layoutStyle == .simpleChordSheet
            ? max(CGFloat(8), staffSpace * 0.95)
            : max(CGFloat(12), staffSpace * 1.6)

        return chart.roadmapObjects
            .filter { $0.type == .repeatSpan }
            .flatMap { roadmapObject -> [LeadSheetRepeatMarkerLayout] in
                var layouts: [LeadSheetRepeatMarkerLayout] = []
                if roadmapObject.startMeasureID == measure.id {
                    layouts.append(
                        repeatMarkerLayout(
                            for: roadmapObject,
                            edge: .leading,
                            centerX: staffFrame.minX,
                            staffFrame: staffFrame,
                            markerWidth: markerWidth
                        )
                    )
                }

                if roadmapObject.endMeasureID == measure.id {
                    layouts.append(
                        repeatMarkerLayout(
                            for: roadmapObject,
                            edge: .trailing,
                            centerX: staffFrame.maxX,
                            staffFrame: staffFrame,
                            markerWidth: markerWidth
                        )
                    )
                }

                return layouts
            }
    }

    private static func repeatMarkerLayout(
        for roadmapObject: RoadmapObject,
        edge: LeadSheetRepeatMarkerLayout.Edge,
        centerX: CGFloat,
        staffFrame: CGRect,
        markerWidth: CGFloat
    ) -> LeadSheetRepeatMarkerLayout {
        LeadSheetRepeatMarkerLayout(
            roadmapObjectID: roadmapObject.id,
            edge: edge,
            frame: CGRect(
                x: centerX - markerWidth / 2,
                y: staffFrame.minY,
                width: markerWidth,
                height: staffFrame.height
            )
        )
    }

    private static func cueTextLayouts(
        for measure: Measure,
        chart: Chart,
        measureFrame: CGRect,
        chordBandFrame: CGRect,
        staffFrame: CGRect
    ) -> [LeadSheetCueTextLayout] {
        chart.cueTexts
            .filter { $0.anchorMeasureID == measure.id }
            .enumerated()
            .map { cueIndex, cueText in
                LeadSheetCueTextLayout(
                    id: cueText.id,
                    text: cueText.text,
                    frame: cueTextFrame(
                        for: cueText,
                        cueIndex: cueIndex,
                        measureFrame: measureFrame,
                        chordBandFrame: chordBandFrame,
                        staffFrame: staffFrame
                    ),
                    position: cueText.position,
                    emphasis: cueText.emphasis
                )
            }
    }

    private static func cueTextFrame(
        for cueText: CueText,
        cueIndex: Int,
        measureFrame: CGRect,
        chordBandFrame: CGRect,
        staffFrame: CGRect
    ) -> CGRect {
        let lineHeight: CGFloat = 17
        let lineGap: CGFloat = 2
        let offset = CGFloat(cueIndex) * (lineHeight + lineGap)
        let width = max(1, staffFrame.width - 12)
        let leadingFrame = CGRect(
            x: measureFrame.minX + 4,
            y: staffFrame.minY,
            width: min(58, max(1, staffFrame.width - 8)),
            height: lineHeight
        )
        let trailingFrame = CGRect(
            x: max(measureFrame.minX + 4, staffFrame.maxX - min(58, max(1, staffFrame.width - 8)) - 4),
            y: staffFrame.minY,
            width: min(58, max(1, staffFrame.width - 8)),
            height: lineHeight
        )

        switch cueText.position {
        case .above:
            if chordBandFrame.intersects(staffFrame) {
                return CGRect(
                    x: staffFrame.minX + 6,
                    y: min(measureFrame.maxY - lineHeight - 2, staffFrame.minY + 4 + offset),
                    width: width,
                    height: lineHeight
                )
            }

            return CGRect(
                x: staffFrame.minX + 6,
                y: max(measureFrame.minY + 2, chordBandFrame.maxY - lineHeight - 2 - offset),
                width: width,
                height: lineHeight
            )
        case .below:
            return CGRect(
                x: staffFrame.minX + 6,
                y: min(measureFrame.maxY - lineHeight - 2, staffFrame.maxY + 5 + offset),
                width: width,
                height: lineHeight
            )
        case .leadingEdge:
            return leadingFrame.offsetBy(dx: 0, dy: offset)
        case .trailingEdge:
            return trailingFrame.offsetBy(dx: 0, dy: offset)
        }
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

    private static func pitchedNoteheadSymbol(
        for headStyle: LeadSheetNoteLayout.HeadStyle
    ) -> NotationGlyphCatalog.Symbol {
        switch headStyle {
        case .whole:
            return .noteheadWhole
        case .half:
            return .noteheadHalf
        case .filled:
            return .noteheadBlack
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
            case .sixteenthRest:
                return sixteenthRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
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
                let isBeamedFromPrevious = isSlashBeamableValueBeamedFromPrevious(
                    at: index,
                    slots: slots,
                    meter: meter
                )
                let flagStyle: LeadSheetNoteLayout.FlagStyle = slot.duration.isSlashBeamableValue
                    && beamEndPoint == nil
                    && !isBeamedFromPrevious
                    ? flagStyle(for: slot.duration)
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

    private static func noteLayouts(
        for measure: Measure,
        chart: Chart,
        meter: Meter,
        staffFrame: CGRect,
        staffLineYPositions: [CGFloat]
    ) -> [LeadSheetNoteLayout]? {
        if chart.layoutStyle == .leadSheet,
           let pitchedLayouts = pitchedNoteLayouts(
            for: measure,
            chart: chart,
            meter: meter,
            staffFrame: staffFrame,
            staffLineYPositions: staffLineYPositions
           ) {
            return pitchedLayouts
        }

        return slashNoteLayouts(
            for: measure,
            chart: chart,
            meter: meter,
            staffFrame: staffFrame,
            staffLineYPositions: staffLineYPositions
        )
    }

    private static func pitchedNoteLayouts(
        for measure: Measure,
        chart: Chart,
        meter: Meter,
        staffFrame: CGRect,
        staffLineYPositions: [CGFloat]
    ) -> [LeadSheetNoteLayout]? {
        guard !measure.pitchedNoteEvents.isEmpty,
              let slots = measure.resolvedRhythmSlots(defaultMeter: meter),
              !slots.isEmpty,
              let fallbackLayouts = slashNoteLayouts(
                for: measure,
                chart: chart,
                meter: meter,
                staffFrame: staffFrame,
                staffLineYPositions: staffLineYPositions
              ) else {
            return nil
        }

        let pitchedEventsBySlot = Dictionary(
            grouping: measure.pitchedNoteEvents,
            by: \.rhythmSlotIndex
        ).compactMapValues(\.first)
        let usableWidth = staffFrame.width - 16
        let staffSpace = staffLineYPositions[1] - staffLineYPositions[0]

        return slots.enumerated().map { index, slot in
            guard slot.duration.supportsPitchedLeadSheetNote,
                  let event = pitchedEventsBySlot[index] else {
                return fallbackLayouts[index]
            }

            let noteCenter = CGPoint(
                x: slashAttackCenterX(
                    for: slot,
                    meter: meter,
                    staffFrame: staffFrame,
                    usableWidth: usableWidth
                ),
                y: staffY(for: event.staffPosition, staffLineYPositions: staffLineYPositions)
            )
            let headStyle = headStyle(for: slot.duration)
            let noteheadSymbol = pitchedNoteheadSymbol(for: headStyle)
            let noteheadFrame = noteheadFrame(
                for: noteheadSymbol,
                centeredAt: noteCenter,
                staffSpace: staffSpace,
                notationFont: chart.notationFont,
                engravingPreset: chart.engravingPreset,
                fallbackSize: CGSize(width: 10, height: 9)
            )
            let stemGoesUp = event.staffPosition.staffStep >= 4
            let stemStart = slot.duration == .whole
                ? nil
                : stemAnchorPoint(
                    for: noteheadSymbol,
                    centeredAt: noteheadFrame.center,
                    staffSpace: staffSpace,
                    notationFont: chart.notationFont,
                    engravingPreset: chart.engravingPreset,
                    stemGoesUp: stemGoesUp,
                    fallback: CGPoint(
                        x: stemGoesUp ? noteheadFrame.maxX - 1 : noteheadFrame.minX + 1,
                        y: stemGoesUp ? noteheadFrame.minY + 2 : noteheadFrame.maxY - 2
                    )
                )
            let stemLength = staffSpace * 3.45
            let stemEnd = stemStart.map { start in
                CGPoint(
                    x: start.x,
                    y: stemGoesUp ? start.y - stemLength : start.y + stemLength
                )
            }
            let flagStyle: LeadSheetNoteLayout.FlagStyle = flagStyle(for: slot.duration)
            let dotFrame = dottedDuration(slot.duration)
                ? CGRect(x: noteheadFrame.maxX + 3, y: noteheadFrame.midY - 1.5, width: 3, height: 3)
                : nil

            return LeadSheetNoteLayout(
                id: event.id,
                symbolStyle: .pitchedNote,
                noteheadSymbol: noteheadSymbol,
                noteheadFrame: noteheadFrame,
                staffSpace: staffSpace,
                headStyle: headStyle,
                stemStart: stemStart,
                stemEnd: stemEnd,
                stemGoesUp: stemGoesUp,
                flagStyle: flagStyle,
                dotFrame: dotFrame,
                tieFrame: nil,
                beamEndPoint: nil
            )
        }
    }

    private static func staffY(
        for staffPosition: LeadSheetStaffPosition,
        staffLineYPositions: [CGFloat]
    ) -> CGFloat {
        staffLineYPositions[0] + CGFloat(staffPosition.staffStep) * (staffLineYPositions[1] - staffLineYPositions[0]) / 2
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
        guard slots[index].duration.isSlashBeamableValue,
              index + 1 < slots.count,
              slots[index + 1].duration.isSlashBeamableValue else {
            return nil
        }

        let currentStart = slots[index].startPosition.startOffset(in: meter) ?? 0
        let nextStart = slots[index + 1].startPosition.startOffset(in: meter) ?? 0
        guard abs((currentStart + slots[index].duration.wholeNoteLength(in: meter)) - nextStart) < 0.0001 else {
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
        let durationLength = max(0, duration.wholeNoteLength(in: meter))
        guard durationLength > 0 else {
            return meter.beatUnitWholeNoteLength
        }

        return min(durationLength, meter.beatUnitWholeNoteLength)
    }

    private static func isSlashBeamableValueBeamedFromPrevious(
        at index: Int,
        slots: [MeasureRhythmSlot],
        meter: Meter
    ) -> Bool {
        guard index > 0,
              slots[index].duration.isSlashBeamableValue,
              slots[index - 1].duration.isSlashBeamableValue,
              slots[index - 1].startPosition.beat == slots[index].startPosition.beat else {
            return false
        }

        let previousStart = slots[index - 1].startPosition.startOffset(in: meter) ?? 0
        let currentStart = slots[index].startPosition.startOffset(in: meter) ?? 0
        return abs((previousStart + slots[index - 1].duration.wholeNoteLength(in: meter)) - currentStart) < 0.0001
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

    private static func sixteenthRestLayout(
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
            symbolStyle: .sixteenthRest,
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
        case .slash, .quarter, .dottedQuarter, .sixteenth, .eighth, .quarterRest, .sixteenthRest, .eighthRest, .tiedContinuation:
            return .filled
        }
    }

    private static func dottedDuration(_ duration: RhythmValue) -> Bool {
        switch duration {
        case .dottedQuarter, .dottedHalf:
            return true
        case .slash, .sixteenth, .sixteenthRest, .eighth, .eighthRest, .quarter, .quarterRest, .half, .halfRest, .whole, .wholeRest, .tiedContinuation:
            return false
        }
    }

    private static func flagStyle(for duration: RhythmValue) -> LeadSheetNoteLayout.FlagStyle {
        switch duration {
        case .sixteenth:
            return .double
        case .eighth:
            return .single
        case .slash, .sixteenthRest, .eighthRest, .quarter, .quarterRest, .dottedQuarter, .half, .halfRest,
             .dottedHalf, .whole, .wholeRest, .tiedContinuation:
            return .none
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
    func freehandSymbolLayouts(for chart: Chart) -> [LeadSheetFreehandSymbolLayout] {
        let supportedLanes = chart.layoutStyle.profile.freehandSymbolLanes
        guard !supportedLanes.isEmpty else {
            return []
        }

        let measureLayoutByID = Dictionary(
            uniqueKeysWithValues: systems
                .flatMap(\.measures)
                .compactMap { measureLayout -> (UUID, LeadSheetMeasureLayout)? in
                    guard let sourceMeasureID = measureLayout.sourceMeasureID else {
                        return nil
                    }

                    return (sourceMeasureID, measureLayout)
                }
        )

        return chart.freehandSymbols
            .filter { supportedLanes.contains($0.lane) }
            .sorted { $0.zIndex < $1.zIndex }
            .compactMap { symbol in
                guard let measureLayout = measureLayoutByID[symbol.anchorMeasureID] else {
                    return nil
                }

                let frame: CGRect
                let laneFrame: CGRect
                if symbol.lane == .chartArea {
                    laneFrame = paperFrame
                    frame = symbol.measureRelativeFrame?.resolved(relativeTo: measureLayout.frame)
                        ?? symbol.normalizedFrame.resolved(in: measureLayout.frame)
                } else {
                    guard let resolvedLaneFrame = measureLayout.freehandFrame(for: symbol.lane) else {
                        return nil
                    }

                    laneFrame = resolvedLaneFrame
                    frame = symbol.normalizedFrame.resolved(in: resolvedLaneFrame)
                }

                return LeadSheetFreehandSymbolLayout(
                    id: symbol.id,
                    symbol: symbol,
                    frame: frame,
                    laneFrame: laneFrame
                )
            }
    }

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

private extension RhythmValue {
    var isSlashBeamableValue: Bool {
        self == .eighth || self == .sixteenth
    }
}

extension LeadSheetMeasureLayout {
    func freehandFrame(for lane: FreehandSymbolLane) -> CGRect? {
        switch lane {
        case .chartArea:
            return frame
        case .aboveMeasure:
            return freehandAboveFrame
        case .belowMeasure:
            return freehandBelowFrame
        }
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

private enum LeadSheetKeySignatureAccidentalKind {
    case sharps
    case flats
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
                systemHeight: 156,
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
