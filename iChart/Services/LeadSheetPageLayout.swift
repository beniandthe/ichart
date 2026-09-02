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
    var layoutStyle: ChartLayoutStyle = .leadSheet
    var frame: CGRect
    var staffLineYPositions: [CGFloat]
    var clefFrame: CGRect?
    var keySignatureLayouts: [LeadSheetKeySignatureLayout]
    var keyTextFrame: CGRect?
    var keyText: String?
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
    var chordInkTargetMeasureID: UUID?
    var index: Int
    var frame: CGRect
    var staffFrame: CGRect
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
    var leadingBarlineX: CGFloat {
        staffFrame.minX
    }

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
            x: staffFrame.minX + 2,
            y: topY,
            width: max(1, staffFrame.width - 4),
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
        case measureRepeat
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
        case secondaryBackward
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
        !measure.isOpen && repeatMarkers(after: measure, before: nextMeasure).isEmpty
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
    var scale: CGFloat

    var id: UUID {
        roadmapObjectID
    }
}

struct LeadSheetCueTextLayout: Identifiable, Hashable {
    var id: UUID
    var text: String
    var frame: CGRect
    var hitFrame: CGRect
    var position: CuePosition
    var emphasis: CueEmphasis
    var scale: CGFloat
    var beatFraction: CGFloat?
    var verticalOffset: CGFloat
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
    private static let minimumResponsivePageWidth: CGFloat = 720
    private static let mediumOpenMeasureWidth: CGFloat = 252
    private static let preferredCommittedMeasureWidth: CGFloat = 140
    private static let systemTrailingPadding: CGFloat = 6
    private static let minimumPaperWidth: CGFloat = 640
    private static let rhythmSectionChordRenderOffset: CGFloat = 16 / 3
    private static let rhythmSectionChordLeadingInset: CGFloat = 16
    private static let rhythmSectionChordMinimumFrameGap: CGFloat = 10
    private static let rhythmSectionChordVisibleFrameHeight: CGFloat = 32
    private static let simpleChordMinimumFrameGap: CGFloat = 16
    private static let simpleChordMeasureContentPadding: CGFloat = 24
    private static let simpleChordLaneEdgeInset: CGFloat = 1

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
        var simpleLeadingMeterGutterWidth: CGFloat { 58 }
        var rhythmFirstSystemSignatureWidth: CGFloat { max(metrics.firstSystemSignatureWidth, 66) }
        var rhythmContinuationSignatureWidth: CGFloat { 40 }
        var simpleTitleFrameHeight: CGFloat { 36 }
        var simpleMetadataHeight: CGFloat { 24 }

        func leadingClefFrame(in frame: CGRect, staffFrame: CGRect) -> CGRect {
            guard layoutStyle == .rhythmSectionSheet else {
                return CGRect(x: frame.minX, y: staffFrame.minY - 10, width: 26, height: 54)
            }

            return CGRect(
                x: frame.minX + 8,
                y: staffFrame.midY - 29,
                width: 24,
                height: 54
            )
        }

        func leadingTimeSignatureFrame(
            in frame: CGRect,
            staffFrame: CGRect,
            x: CGFloat
        ) -> CGRect {
            guard layoutStyle == .rhythmSectionSheet else {
                return CGRect(x: x, y: staffFrame.minY - 11, width: 24, height: 56)
            }

            return CGRect(
                x: x,
                y: staffFrame.midY - 28,
                width: 24,
                height: 56
            )
        }

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

    static func pageLayout(
        for chart: Chart,
        pageSize: CGSize,
        includesChordInkContinuationLanes: Bool = false
    ) -> LeadSheetPageLayout {
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
            includesChordInkContinuationLanes: includesChordInkContinuationLanes,
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

    static func simpleChordSheetManualLayoutWidthForTargetRowWidth(
        _ targetRowWidth: CGFloat,
        chart: Chart,
        maxSystemWidth: CGFloat
    ) -> CGFloat {
        let clampedTargetWidth = min(max(targetRowWidth, 1), simpleChordSheetBodyWidth(chart: chart, maxSystemWidth: maxSystemWidth))
        let scale = simpleChordSheetManualLayoutWidthScale(
            chart: chart,
            maxSystemWidth: maxSystemWidth
        )
        return clampedTargetWidth * scale
    }

    static func simpleChordSheetTargetRowWidthForManualLayoutWidth(
        _ manualLayoutWidth: CGFloat,
        chart: Chart,
        maxSystemWidth: CGFloat
    ) -> CGFloat {
        let scale = simpleChordSheetManualLayoutWidthScale(
            chart: chart,
            maxSystemWidth: maxSystemWidth
        )
        return Measure.clampedManualLayoutWidth(manualLayoutWidth) / max(0.0001, scale)
    }

    static func simpleChordSheetManualLayoutWidthScale(
        chart: Chart,
        maxSystemWidth: CGFloat
    ) -> CGFloat {
        let bodyWidth = simpleChordSheetBodyWidth(chart: chart, maxSystemWidth: maxSystemWidth)
        let preferredMeasuresPerSystem = max(
            1,
            chart.layoutStyle.profile.measureDefaults.preferredMeasuresPerSystem
        )
        let standardMeasureWidth = bodyWidth / CGFloat(preferredMeasuresPerSystem)
        let visualPolicy = VisualPolicy(chart: chart)
        let defaultWidth = max(1, preferredCommittedMeasureWidth * visualPolicy.metrics.measureWidthScale)
        return defaultWidth / max(1, standardMeasureWidth)
    }

    static func simpleChordSheetMaximumRowBodyWidth(
        chart: Chart,
        maxSystemWidth: CGFloat
    ) -> CGFloat {
        simpleChordSheetBodyWidth(chart: chart, maxSystemWidth: maxSystemWidth)
    }

    private static func simpleChordSheetBodyWidth(
        chart: Chart,
        maxSystemWidth: CGFloat
    ) -> CGFloat {
        let visualPolicy = VisualPolicy(chart: chart)
        let leadingSignatureWidth = leadingSignatureWidth(
            for: chart,
            visualPolicy: visualPolicy,
            systemIndex: 0
        )
        return max(1, maxSystemWidth - leadingSignatureWidth - systemTrailingPadding)
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

        let centerMetadataWidth: CGFloat = 88
        let centerMetadataX = frame.midX - centerMetadataWidth / 2
        let keyFrame: CGRect? = nil
        let meterFrame: CGRect?
        if visualPolicy.showsHeaderMeter {
            meterFrame = CGRect(
                x: centerMetadataX,
                y: metadataY,
                width: centerMetadataWidth,
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
        includesChordInkContinuationLanes: Bool,
        visualPolicy: VisualPolicy
    ) -> [LeadSheetSystemLayout] {
        let metrics = visualPolicy.metrics
        let plans = includesChordInkContinuationLanes
            ? pageFilledPackedSystemPlans(
                for: chart,
                paperFrame: paperFrame,
                firstSystemTop: firstSystemTop,
                metrics: metrics
            )
            : packedSystemPlans(for: chart, maxSystemWidth: paperFrame.width - 68)

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

    private static func pageFilledPackedSystemPlans(
        for chart: Chart,
        paperFrame: CGRect,
        firstSystemTop: CGFloat,
        metrics: LeadSheetEngravingMetrics
    ) -> [PackedLeadSheetSystemPlan] {
        var plans = packedSystemPlans(for: chart, maxSystemWidth: paperFrame.width - 68)
        guard chart.layoutStyle == .simpleChordSheet,
              chart.hasCompletedInitialSetup,
              let openMeasureID = chart.measures.first(where: { $0.authoringState == .open })?.id else {
            return plans
        }

        let leadingSignatureWidth = leadingSignatureWidth(
            for: chart,
            visualPolicy: VisualPolicy(chart: chart),
            systemIndex: 0
        )
        let bodyWidth = max(1, paperFrame.width - 68 - leadingSignatureWidth - systemTrailingPadding)
        let rowStride = metrics.systemHeight + metrics.systemSpacing
        let usableBottom = paperFrame.maxY - 54
        let availableHeight = max(0, usableBottom - firstSystemTop + metrics.systemSpacing)
        let visibleSystemCapacity = max(
            plans.count,
            Int(floor(availableHeight / max(1, rowStride)))
        )
        guard visibleSystemCapacity > plans.count else {
            return plans
        }

        while plans.count < visibleSystemCapacity {
            plans.append(
                PackedLeadSheetSystemPlan(
                    id: UUID(),
                    leadingSignatureWidth: leadingSignatureWidth,
                    frameWidth: leadingSignatureWidth + bodyWidth + systemTrailingPadding,
                    measures: [
                        PackedLeadSheetMeasurePlan(
                            measure: nil,
                            chordInkTargetMeasureID: openMeasureID,
                            width: bodyWidth
                        )
                    ]
                )
            )
        }

        return plans
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
        let measureStartX = isRhythmSectionSheet
            ? frame.minX
            : frame.minX + plan.leadingSignatureWidth

        let shouldShowLeadingNotation = !isSimpleChordSheet
        let shouldShowLeadingTimeSignature = index == 0 && !isSimpleChordSheet
        let shouldShowSimpleTimeSignature = index == 0 && isSimpleChordSheet
        let activeKey = plan.measures
            .compactMap(\.measure)
            .first
            .map { chart.displayedEffectiveKey(for: $0) }
            ?? chart.displayedDocumentKey
        let clefFrame = shouldShowLeadingNotation
            ? visualPolicy.leadingClefFrame(in: frame, staffFrame: staffFrame)
            : nil
        let keyLayouts = shouldShowLeadingNotation
            ? keySignatureLayouts(
                for: activeKey,
                clef: chart.renderedClef,
                staffLineYPositions: staffLineYPositions,
                startX: (clefFrame?.maxX ?? frame.minX) + 6,
                staffSpace: lineSpacing
            )
            : []
        let keyTextFrame: CGRect? = nil
        let keyText: String? = nil
        let timeSignatureX = isRhythmSectionSheet
            ? keyLayouts.last.map { $0.frame.maxX + 6 } ?? (clefFrame?.maxX ?? frame.minX) + 4
            : keyLayouts.last.map { $0.frame.maxX + 7 } ?? (frame.minX + 28)
        let timeSignatureFrame: CGRect?
        if shouldShowLeadingTimeSignature {
            timeSignatureFrame = visualPolicy.leadingTimeSignatureFrame(
                in: frame,
                staffFrame: staffFrame,
                x: timeSignatureX
            )
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
                structuredRoadmapReserveHeight = 38
            } else if hasPointMarkerLayouts || hasEndingLayouts {
                structuredRoadmapReserveHeight = 24
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
            let leadingSignatureExtension = isRhythmSectionSheet && offset == 0
                ? plan.leadingSignatureWidth
                : 0
            let measureFrame = CGRect(
                x: measureX,
                y: frame.minY,
                width: measurePlan.width + leadingSignatureExtension,
                height: frame.height
            )
            let measureStaffFrame = CGRect(
                x: measureX + leadingSignatureExtension,
                y: staffFrame.minY,
                width: measurePlan.width,
                height: staffFrame.height
            )
            defer {
                measureX += measureFrame.width
            }

            return measureLayout(
                for: measurePlan.measure,
                chart: chart,
                index: offset,
                frame: measureFrame,
                staffFrame: measureStaffFrame,
                chordInkTargetMeasureID: measurePlan.chordInkTargetMeasureID,
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
            layoutStyle: chart.layoutStyle,
            frame: frame,
            staffLineYPositions: staffLineYPositions,
            clefFrame: clefFrame,
            keySignatureLayouts: keyLayouts,
            keyTextFrame: keyTextFrame,
            keyText: keyText,
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
                    y: systemFrame.minY + 2 + topOffset,
                    width: max(1, endX - startX),
                    height: 20
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
                let baseMarkerHeight: CGFloat
                let baseMarkerTopOffset: CGFloat
                if isSimpleChordSheet {
                    baseMarkerHeight = containsNotationGlyph ? 44 : 34
                    baseMarkerTopOffset = containsNotationGlyph ? -19 : -14
                } else {
                    baseMarkerHeight = containsNotationGlyph ? 32 : 24
                    baseMarkerTopOffset = containsNotationGlyph ? -10 : -5
                }
                let markerScale = CGFloat(roadmapObject.resolvedScale)
                let markerHeight = baseMarkerHeight * markerScale
                let markerTopOffset = baseMarkerTopOffset - (markerHeight - baseMarkerHeight) / 2
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
                    isSimpleChordSheet: isSimpleChordSheet,
                    scale: markerScale
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
                    anchorMeasureID: roadmapObject.startMeasureID,
                    scale: markerScale
                )
            }
    }

    private static func roadmapMarkerWidth(
        for text: String,
        type: RoadmapType,
        maxWidth: CGFloat,
        isSimpleChordSheet: Bool,
        scale: CGFloat
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

        return min(max(minimumWidth, textWidth) * scale, max(1, maxWidth))
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
                            chordInkTargetMeasureID: nil,
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
        let forcedBreakStartIDs: Set<UUID>
        if chart.layoutStyle == .rhythmSectionSheet || chart.layoutStyle == .leadSheet {
            forcedBreakStartIDs = forcedSystemBreakStartIDs(for: chart)
                .union(chart.keyChanges.map(\.measureID))
        } else {
            forcedBreakStartIDs = []
        }

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
                PackedLeadSheetMeasurePlan(
                    measure: measure,
                    chordInkTargetMeasureID: measure.id,
                    width: preferredWidth
                )
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
                chordInkTargetMeasureID: measurePlan.chordInkTargetMeasureID,
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
                simpleChordSheetMeasureWeight(for: $0, chart: chart, metrics: metrics)
            }
            let measurePlans: [PackedLeadSheetMeasurePlan]
            let rowBodyWidth: CGFloat
            let targetWidths = weights.map { standardMeasureWidth * $0 }
            let resolvedWidths = simpleChordSheetReadableRowWidths(
                targetWidths,
                weights: weights,
                maxBodyWidth: bodyWidth
            )
            var openLaneResolvedWidths = resolvedWidths
            var resolvedBodyWidth = openLaneResolvedWidths.reduce(0, +)
            if let lastMeasure = measures.last,
               lastMeasure.authoringState == .open,
               resolvedBodyWidth < bodyWidth - 0.001,
               let lastIndex = openLaneResolvedWidths.indices.last {
                openLaneResolvedWidths[lastIndex] += bodyWidth - resolvedBodyWidth
                resolvedBodyWidth = bodyWidth
            }

            if resolvedBodyWidth <= bodyWidth + 0.001 {
                measurePlans = zip(measures, openLaneResolvedWidths).map { measure, width in
                    PackedLeadSheetMeasurePlan(
                        measure: measure,
                        chordInkTargetMeasureID: measure.id,
                        width: width
                    )
                }
                rowBodyWidth = resolvedBodyWidth
            } else {
                let totalWidth = max(1, resolvedBodyWidth)
                measurePlans = zip(measures, openLaneResolvedWidths).map { measure, width in
                    PackedLeadSheetMeasurePlan(
                        measure: measure,
                        chordInkTargetMeasureID: measure.id,
                        width: bodyWidth * width / totalWidth
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

    private static func simpleChordSheetReadableRowWidths(
        _ targetWidths: [CGFloat],
        weights: [CGFloat],
        maxBodyWidth: CGFloat
    ) -> [CGFloat] {
        guard !targetWidths.isEmpty else {
            return []
        }

        let targetBodyWidth = targetWidths.reduce(0, +)
        guard targetBodyWidth > maxBodyWidth else {
            return targetWidths
        }

        var resolvedWidths = targetWidths
        var remainingOverflow = targetBodyWidth - maxBodyWidth
        let minimumWidth = CGFloat(20)
        let simpleMeasureIndices = weights.indices.filter {
            weights[$0] <= 1.001
        }
        remainingOverflow = reduceSimpleChordRowWidths(
            &resolvedWidths,
            overflow: remainingOverflow,
            reducibleIndices: simpleMeasureIndices,
            minimumWidth: minimumWidth
        )

        if remainingOverflow > 0.001 {
            remainingOverflow = reduceSimpleChordRowWidths(
                &resolvedWidths,
                overflow: remainingOverflow,
                reducibleIndices: resolvedWidths.indices.map { $0 },
                minimumWidth: minimumWidth
            )
        }

        if remainingOverflow > 0.001 {
            let totalWidth = max(1, resolvedWidths.reduce(0, +))
            resolvedWidths = resolvedWidths.map {
                max(1, $0 * maxBodyWidth / totalWidth)
            }
        }

        return resolvedWidths
    }

    private static func reduceSimpleChordRowWidths(
        _ widths: inout [CGFloat],
        overflow: CGFloat,
        reducibleIndices: [Int],
        minimumWidth: CGFloat
    ) -> CGFloat {
        var remainingOverflow = overflow
        var activeIndices = reducibleIndices.filter {
            widths.indices.contains($0) && widths[$0] > minimumWidth
        }

        while remainingOverflow > 0.001, !activeIndices.isEmpty {
            let reductionPerMeasure = remainingOverflow / CGFloat(activeIndices.count)
            var nextActiveIndices = [Int]()

            for index in activeIndices {
                let capacity = max(0, widths[index] - minimumWidth)
                let reduction = min(capacity, reductionPerMeasure)
                widths[index] -= reduction
                remainingOverflow -= reduction

                if widths[index] > minimumWidth + 0.001 {
                    nextActiveIndices.append(index)
                }
            }

            guard nextActiveIndices.count < activeIndices.count || reductionPerMeasure > 0 else {
                break
            }
            activeIndices = nextActiveIndices
        }

        return remainingOverflow
    }

    private static func simpleChordSheetMeasureWeight(
        for measure: Measure,
        chart: Chart,
        metrics: LeadSheetEngravingMetrics
    ) -> CGFloat {
        guard let manualLayoutWidth = measure.manualLayoutWidth else {
            return automaticSimpleChordSheetMeasureWeight(for: measure, chart: chart, metrics: metrics)
        }

        let defaultWidth = preferredCommittedMeasureWidth * metrics.measureWidthScale
        return max(0.25, CGFloat(manualLayoutWidth) / max(1, defaultWidth))
    }

    private static func automaticSimpleChordSheetMeasureWeight(
        for measure: Measure,
        chart: Chart,
        metrics: LeadSheetEngravingMetrics
    ) -> CGFloat {
        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let placements = sortedChordPlacements(
            measure.renderedChordPlacements(defaultMeter: chart.defaultMeter),
            meter: meter,
            useSimpleLaneFractions: true
        )
        guard !placements.isEmpty else {
            return 1
        }

        let fontSize = preferredSimpleChordFontSize()
        let defaultWidth = max(1, preferredCommittedMeasureWidth * metrics.measureWidthScale)
        let minimumDisplayWidth = metrics.chordBandHeight * 0.92
        let readableChordWidths = placements.map { placement in
            let displayedSymbol = chart.displayedChordSymbol(for: placement.chordEvent, in: measure.id)
            let displayedText = displayedSymbol.displayText
            return max(
                minimumDisplayWidth,
                estimatedSimpleChordTextWidth(
                    for: displayedSymbol,
                    fallbackText: displayedText,
                    fontSize: fontSize
                ) + 2
            )
        }
        let requiredMeasureWidth = max(
            defaultWidth,
            readableChordWidths.reduce(0, +)
                + simpleChordMinimumFrameGap * CGFloat(max(0, readableChordWidths.count - 1))
                + simpleChordMeasureContentPadding
        )

        return min(2.6, max(1, requiredMeasureWidth / defaultWidth))
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
            let keySignatureWidth = maxKeySignatureAccidentalCount(for: chart) * 10
            let clefRightEdge = CGFloat(32)
            let keySignatureRightEdge = clefRightEdge
                + (keySignatureWidth > 0 ? 6 + keySignatureWidth : 0)
            if systemIndex == 0 {
                let leadingTimeSignatureRightEdge = keySignatureRightEdge
                    + (keySignatureWidth > 0 ? 6 : 4)
                    + 24
                return max(
                    visualPolicy.rhythmFirstSystemSignatureWidth,
                    leadingTimeSignatureRightEdge + 8
                )
            }

            return max(
                visualPolicy.rhythmContinuationSignatureWidth,
                keySignatureRightEdge + 8
            )
        }

        let keySignatureWidth = maxKeySignatureAccidentalCount(for: chart) * 10
        if systemIndex == 0 {
            return metrics.firstSystemSignatureWidth + keySignatureWidth
        }

        return max(metrics.continuationSystemSignatureWidth, 42 + keySignatureWidth)
    }

    private static func maxKeySignatureAccidentalCount(for chart: Chart) -> CGFloat {
        let keys = [chart.documentKey] + chart.keyChanges.map(\.key)
        let maxCount = keys
            .map { $0.transposed(for: chart.defaultTranspositionView).keySignature?.count ?? 0 }
            .max() ?? 0
        return CGFloat(maxCount)
    }

    private static func keySignatureLayouts(
        for key: DocumentKey,
        clef: ChartClef,
        staffLineYPositions: [CGFloat],
        startX: CGFloat,
        staffSpace: CGFloat
    ) -> [LeadSheetKeySignatureLayout] {
        guard let accidentalGroup = key.keySignature,
            let topStaffLineY = staffLineYPositions.first else {
            return []
        }

        let offsets = keySignatureStaffOffsets(kind: accidentalGroup.kind, clef: clef)
        let symbol: NotationGlyphCatalog.Symbol = accidentalGroup.kind == .sharps
            ? .accidentalSharp
            : .accidentalFlat
        let accidentalAdvance = max(8, staffSpace * 0.95)
        let accidentalWidth = max(7, staffSpace)
        let accidentalHeight = staffSpace * 2.1

        return (0..<accidentalGroup.count).map { index in
            let staffOffset = offsets[index]
            let frameCenterStaffOffset = staffOffset
                + keySignatureFrameCenterAdjustment(kind: accidentalGroup.kind, clef: clef)
            let centerY = topStaffLineY + frameCenterStaffOffset * staffSpace
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

    private static func keySignatureFrameCenterAdjustment(
        kind: KeySignatureAccidentalKind,
        clef: ChartClef
    ) -> CGFloat {
        switch (kind, clef) {
        case (.flats, _):
            return -0.5
        default:
            return 0
        }
    }

    private static func keySignatureStaffOffsets(
        kind: KeySignatureAccidentalKind,
        clef: ChartClef
    ) -> [CGFloat] {
        switch (kind, clef) {
        case (.sharps, .treble):
            return [0, 1.5, -0.5, 1, 2.5, 0.5, 2]
        case (.flats, .treble):
            return [2, 0.5, 2.5, 1, 3, 1.5, 3.5]
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
        chordInkTargetMeasureID: UUID?,
        chordBandHeight: CGFloat,
        roadmapTopReserveHeight: CGFloat,
        staffLineYPositions: [CGFloat],
        layoutStyle: ChartLayoutStyle,
        visualPolicy: VisualPolicy,
        meterChange: Meter?
    ) -> LeadSheetMeasureLayout {
        let isSimpleChordSheet = layoutStyle == .simpleChordSheet
        let measureContentFrame = layoutStyle == .rhythmSectionSheet ? CGRect(
            x: staffFrame.minX,
            y: frame.minY,
            width: staffFrame.width,
            height: frame.height
        ) : frame
        let meterChangeFrame = meterChange.map { _ in
            visualPolicy.inlineMeterChangeFrame(in: measureContentFrame, staffFrame: staffFrame)
        }
        let baseChordBandFrame = isSimpleChordSheet ? CGRect(
            x: staffFrame.minX + simpleChordLaneEdgeInset,
            y: staffFrame.minY + 4,
            width: max(1, staffFrame.width - simpleChordLaneEdgeInset * 2),
            height: max(1, staffFrame.height - 8)
        ) : CGRect(
            x: measureContentFrame.minX + 3,
            y: measureContentFrame.minY + roadmapTopReserveHeight,
            width: measureContentFrame.width - 6,
            height: max(1, chordBandHeight - 4 - roadmapTopReserveHeight)
        )
        let chordBandFrame = chordBandFrameByReservingInlineMeterChange(
            baseChordBandFrame,
            meterChangeFrame: meterChangeFrame,
            visualPolicy: visualPolicy
        )
        let writableFrame = isSimpleChordSheet ? staffFrame.insetBy(dx: 2, dy: 2) : CGRect(
            x: measureContentFrame.minX + 2,
            y: chordBandFrame.minY,
            width: measureContentFrame.width - 4,
            height: staffFrame.maxY - chordBandFrame.minY + 8
        )
        let trailingBarlineFrame = CGRect(
            x: frame.maxX,
            y: staffFrame.minY,
            width: 1.6,
            height: staffFrame.height
        )

        guard let measure else {
            return LeadSheetMeasureLayout(
                id: UUID(),
                sourceMeasureID: nil,
                chordInkTargetMeasureID: chordInkTargetMeasureID,
                index: index + 1,
                frame: frame,
                staffFrame: staffFrame,
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
        let displayedPlacements = sortedChordPlacements(
            measure.renderedChordPlacements(defaultMeter: chart.defaultMeter),
            meter: meter,
            useSimpleLaneFractions: isSimpleChordSheet
        )
        let repeatMarkerLayouts = repeatMarkerLayouts(
            for: measure,
            chart: chart,
            staffFrame: staffFrame
        )
        let rawChordLayouts: [LeadSheetChordLayout]
        if isSimpleChordSheet {
            rawChordLayouts = simpleChordLayouts(
                for: displayedPlacements,
                chart: chart,
                meter: meter,
                chordBandFrame: chordBandFrame,
                staffFrame: staffFrame,
                measureID: measure.id,
                visualPolicy: visualPolicy,
                repeatMarkerLayouts: repeatMarkerLayouts,
                meterChangeFrame: meterChangeFrame
            )
        } else {
            rawChordLayouts = displayedPlacements.enumerated().map { placementIndex, placement in
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
                    measureID: measure.id,
                    visualPolicy: visualPolicy
                )
            }
        }
        let chordLayouts: [LeadSheetChordLayout]
        if isSimpleChordSheet {
            chordLayouts = resolvedSimpleChordCollisions(
                in: rawChordLayouts,
                chordBandFrame: chordBandFrame
            )
        } else if layoutStyle == .rhythmSectionSheet {
            chordLayouts = resolvedRhythmSectionChordCollisions(
                in: rawChordLayouts,
                chordBandFrame: chordBandFrame
            )
        } else {
            chordLayouts = rawChordLayouts
        }
        let noteLayouts = isSimpleChordSheet ? [] : noteLayouts(
            for: measure,
            chart: chart,
            meter: meter,
            staffFrame: staffFrame,
            staffLineYPositions: staffLineYPositions
        ) ?? []
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
            chordInkTargetMeasureID: measure.id,
            index: measure.index,
            frame: frame,
            staffFrame: staffFrame,
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

    private static func simpleChordLayouts(
        for placements: [MeasureChordPlacement],
        chart: Chart,
        meter: Meter,
        chordBandFrame: CGRect,
        staffFrame: CGRect,
        measureID: UUID,
        visualPolicy: VisualPolicy,
        repeatMarkerLayouts: [LeadSheetRepeatMarkerLayout],
        meterChangeFrame: CGRect?
    ) -> [LeadSheetChordLayout] {
        let leadingRepeatMaxX = repeatMarkerLayouts
            .filter { $0.edge == .leading }
            .map(\.frame.maxX)
            .max()
        let guideFrame = LeadSheetChordPlacementGuidePolicy.guideFrame(
            referenceFrame: chordBandFrame,
            leadingRepeatMarkerMaxX: leadingRepeatMaxX,
            meterChangeFrame: meterChangeFrame
        )
        let slotStartXs = simpleChordSlotStartXs(
            count: placements.count,
            meter: meter,
            guideFrame: guideFrame
        )
        let fitFrames = simpleChordSlotFitFrames(
            for: placements,
            chart: chart,
            chordBandFrame: chordBandFrame,
            slotStartXs: slotStartXs,
            measureID: measureID
        )

        return placements.enumerated().map { placementIndex, placement in
            chordLayout(
                for: placement,
                nextPlacement: nil,
                chart: chart,
                meter: meter,
                chordBandFrame: chordBandFrame,
                staffFrame: staffFrame,
                measureID: measureID,
                visualPolicy: visualPolicy,
                simpleFitFrameOverride: fitFrames[placementIndex]
            )
        }
    }

    private static func simpleChordSlotStartXs(
        count: Int,
        meter: Meter,
        guideFrame: CGRect
    ) -> [CGFloat] {
        guard count > 0 else {
            return []
        }

        let guideXs = LeadSheetChordPlacementGuidePolicy.guideXs(for: meter, in: guideFrame)
        if count <= guideXs.count {
            return simpleChordPreferredGuideIndexes(
                count: count,
                guideCount: guideXs.count
            )
            .map { guideXs[$0] }
            .sorted()
        }

        let firstSlotX = guideXs.first ?? guideFrame.minX
        let availableWidth = max(1, guideFrame.maxX - firstSlotX)
        return (0..<count).map { index in
            firstSlotX + availableWidth * CGFloat(index) / CGFloat(count)
        }
    }

    private static func simpleChordPreferredGuideIndexes(
        count: Int,
        guideCount: Int
    ) -> [Int] {
        guard count > 0,
              guideCount > 0 else {
            return []
        }

        var indexes = [0]
        if count > 1 {
            let midpointIndex = min(guideCount - 1, max(0, guideCount / 2))
            if !indexes.contains(midpointIndex) {
                indexes.append(midpointIndex)
            }
        }

        for index in 1..<guideCount where indexes.count < count {
            if !indexes.contains(index) {
                indexes.append(index)
            }
        }

        return Array(indexes.prefix(count))
    }

    private static func simpleChordSlotFitFrames(
        for placements: [MeasureChordPlacement],
        chart: Chart,
        chordBandFrame: CGRect,
        slotStartXs: [CGFloat],
        measureID: UUID
    ) -> [CGRect] {
        placements.enumerated().map { placementIndex, placement in
            let displayedSymbol = chart.displayedChordSymbol(for: placement.chordEvent, in: measureID)
            let displayedText = displayedSymbol.displayText
            let minimumFitFrameWidth = simpleChordMinimumFitFrameWidth(
                for: placement,
                displayedSymbol: displayedSymbol,
                displayedText: displayedText,
                chordBandFrame: chordBandFrame
            )
            let startX = slotStartXs.indices.contains(placementIndex)
                ? slotStartXs[placementIndex]
                : chordBandFrame.minX
            let nextStartX = slotStartXs.indices.contains(placementIndex + 1)
                ? slotStartXs[placementIndex + 1]
                : nil
            return simpleChordFitFrame(
                startX: startX,
                nextStartX: nextStartX,
                chordBandFrame: chordBandFrame,
                minimumWidth: minimumFitFrameWidth
            )
        }
    }

    private static func simpleChordMinimumFitFrameWidth(
        for placement: MeasureChordPlacement,
        displayedSymbol: ChordSymbol?,
        displayedText: String,
        chordBandFrame: CGRect
    ) -> CGFloat {
        max(
            chordBandFrame.height * 0.92,
            estimatedSimpleChordTextWidth(
                for: displayedSymbol,
                fallbackText: displayedText,
                fontSize: preferredSimpleChordFontSize()
            ) + 2,
            placement.chordEvent.manualDisplayWidth
                .map { CGFloat(ChordEvent.clampedManualDisplayWidth($0)) }
                ?? 1
        )
    }

    private static func chordLayout(
        for placement: MeasureChordPlacement,
        nextPlacement: MeasureChordPlacement?,
        chart: Chart,
        meter: Meter,
        chordBandFrame: CGRect,
        staffFrame: CGRect,
        measureID: UUID,
        visualPolicy: VisualPolicy,
        simpleFitFrameOverride: CGRect? = nil
    ) -> LeadSheetChordLayout {
        let displayedSymbol = chart.displayedChordSymbol(for: placement.chordEvent, in: measureID)
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
            let fitFrame = simpleFitFrameOverride ?? simpleChordFitFrame(
                for: placement,
                nextPlacement: nextPlacement,
                meter: meter,
                chordBandFrame: chordBandFrame,
                minimumWidth: simpleChordMinimumFitFrameWidth(
                    for: placement,
                    displayedSymbol: displayedSymbol,
                    displayedText: displayedText,
                    chordBandFrame: chordBandFrame
                )
            )
            return LeadSheetChordLayout(
                id: placement.chordEvent.id,
                text: displayedText,
                symbol: displayedSymbol,
                frame: simpleChordDisplayFrame(
                    symbol: displayedSymbol,
                    text: displayedText,
                    fitFrame: fitFrame,
                    manualDisplayWidth: placement.chordEvent.manualDisplayWidth
                ),
                fitFrame: fitFrame,
                snapGuideTarget: CGPoint(x: fitFrame.minX, y: staffFrame.midY)
            )
        }

        let textWidth = estimatedChordTextWidth(for: displayedText)
        let minimumChordX = visualPolicy.layoutStyle == .rhythmSectionSheet
            ? staffFrame.minX + rhythmSectionChordLeadingInset
            : chordBandFrame.minX + 1
        let chordX = min(
            max(minimumChordX, attackCenterX - textWidth / 2),
            chordBandFrame.maxX - textWidth
        )
        let resolvedChordX = max(minimumChordX, chordX)
        let resolvedWidth = min(textWidth, max(1, chordBandFrame.maxX - resolvedChordX))

        let structuredChordRenderOffset = visualPolicy.layoutStyle == .rhythmSectionSheet
            ? rhythmSectionChordRenderOffset
            : 0
        let fitFrame = CGRect(
            x: resolvedChordX,
            y: chordBandFrame.minY + structuredChordRenderOffset,
            width: resolvedWidth,
            height: chordBandFrame.height
        )
        let visibleFrameHeight = visualPolicy.layoutStyle == .rhythmSectionSheet
            ? min(chordBandFrame.height, rhythmSectionChordVisibleFrameHeight)
            : chordBandFrame.height
        return LeadSheetChordLayout(
            id: placement.chordEvent.id,
            text: displayedText,
            symbol: displayedSymbol,
            frame: CGRect(
                x: resolvedChordX,
                y: fitFrame.midY - visibleFrameHeight / 2,
                width: resolvedWidth,
                height: visibleFrameHeight
            ),
            fitFrame: fitFrame,
            snapGuideTarget: CGPoint(x: attackCenterX, y: staffFrame.midY)
        )
    }

    private static func sortedChordPlacements(
        _ placements: [MeasureChordPlacement],
        meter: Meter,
        useSimpleLaneFractions: Bool
    ) -> [MeasureChordPlacement] {
        placements.enumerated()
            .sorted { lhs, rhs in
                let lhsPosition = useSimpleLaneFractions
                    ? simpleChordPlacementVisualFraction(lhs.element, meter: meter)
                    : chordPlacementStartFraction(lhs.element, meter: meter)
                let rhsPosition = useSimpleLaneFractions
                    ? simpleChordPlacementVisualFraction(rhs.element, meter: meter)
                    : chordPlacementStartFraction(rhs.element, meter: meter)

                if abs(lhsPosition - rhsPosition) > 0.0001 {
                    return lhsPosition < rhsPosition
                }

                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    private static func simpleChordPlacementVisualFraction(
        _ placement: MeasureChordPlacement,
        meter: Meter
    ) -> Double {
        if !placement.isRhythmMapped,
           let manualLaneFraction = placement.chordEvent.manualLaneFraction {
            return ChordEvent.clampedManualLaneFraction(manualLaneFraction)
        }

        return chordPlacementStartFraction(placement, meter: meter)
    }

    private static func chordPlacementStartFraction(
        _ placement: MeasureChordPlacement,
        meter: Meter
    ) -> Double {
        guard meter.measureLengthInWholeNotes > 0,
              let startOffset = placement.startPosition.startOffset(in: meter) else {
            return 0
        }

        return ChordEvent.clampedManualLaneFraction(startOffset / meter.measureLengthInWholeNotes)
    }

    private static func chordBandFrameByReservingInlineMeterChange(
        _ chordBandFrame: CGRect,
        meterChangeFrame: CGRect?,
        visualPolicy: VisualPolicy
    ) -> CGRect {
        guard let meterChangeFrame else {
            return chordBandFrame
        }

        let gap = visualPolicy.layoutStyle == .simpleChordSheet ? CGFloat(8) : CGFloat(6)
        let reservedMinX = min(
            chordBandFrame.maxX - 1,
            max(chordBandFrame.minX, meterChangeFrame.maxX + gap)
        )
        return CGRect(
            x: reservedMinX,
            y: chordBandFrame.minY,
            width: max(1, chordBandFrame.maxX - reservedMinX),
            height: chordBandFrame.height
        )
    }

    private static func resolvedRhythmSectionChordCollisions(
        in chordLayouts: [LeadSheetChordLayout],
        chordBandFrame: CGRect
    ) -> [LeadSheetChordLayout] {
        guard chordLayouts.count > 1 else {
            return chordLayouts
        }

        var resolvedLayouts = [LeadSheetChordLayout]()
        resolvedLayouts.reserveCapacity(chordLayouts.count)

        for chordLayout in chordLayouts {
            var resolvedLayout = chordLayout
            if let previousLayout = resolvedLayouts.last {
                let minimumMinX = previousLayout.frame.maxX + rhythmSectionChordMinimumFrameGap
                if resolvedLayout.frame.minX < minimumMinX {
                    resolvedLayout = rhythmSectionChordLayout(
                        resolvedLayout,
                        byMovingVisibleMinXTo: minimumMinX,
                        boundedBy: chordBandFrame
                    )
                }
            }

            resolvedLayouts.append(resolvedLayout)
        }

        return resolvedLayouts
    }

    private static func rhythmSectionChordLayout(
        _ chordLayout: LeadSheetChordLayout,
        byMovingVisibleMinXTo proposedMinX: CGFloat,
        boundedBy chordBandFrame: CGRect
    ) -> LeadSheetChordLayout {
        let boundedMinX = min(
            max(chordBandFrame.minX + 1, proposedMinX),
            max(chordBandFrame.minX + 1, chordBandFrame.maxX - chordLayout.frame.width)
        )
        let deltaX = boundedMinX - chordLayout.frame.minX
        guard abs(deltaX) > 0.001 else {
            return chordLayout
        }

        var resolvedLayout = chordLayout
        resolvedLayout.frame = chordLayout.frame.offsetBy(dx: deltaX, dy: 0)
        resolvedLayout.fitFrame = chordLayout.fitFrame.offsetBy(dx: deltaX, dy: 0)
        return resolvedLayout
    }

    private static func resolvedSimpleChordCollisions(
        in chordLayouts: [LeadSheetChordLayout],
        chordBandFrame: CGRect
    ) -> [LeadSheetChordLayout] {
        guard chordLayouts.count > 1 else {
            return chordLayouts
        }

        let minimumGap = simpleChordMinimumFrameGap
        var resolvedLayouts = [LeadSheetChordLayout]()
        resolvedLayouts.reserveCapacity(chordLayouts.count)

        for chordLayout in chordLayouts {
            var resolvedLayout = chordLayout
            if let previousLayout = resolvedLayouts.last,
               resolvedLayout.frame.minX < previousLayout.frame.maxX + minimumGap {
                let minimumMinX = previousLayout.frame.maxX + minimumGap
                if let shiftedLayout = simpleChordLayout(
                    resolvedLayout,
                    byMovingVisibleMinXTo: minimumMinX,
                    boundedBy: chordBandFrame
                ) {
                    resolvedLayout = shiftedLayout
                } else {
                    let collisionWidth = previousLayout.frame.maxX + minimumGap - resolvedLayout.frame.minX
                    let reductions = weightedSimpleChordCollisionReductions(
                        collisionWidth: collisionWidth,
                        previousFrame: previousLayout.frame,
                        currentFrame: resolvedLayout.frame
                    )

                    if let previousIndex = resolvedLayouts.indices.last {
                        resolvedLayouts[previousIndex] = chordLayoutByReducingTrailingEdge(
                            of: previousLayout,
                            by: reductions.previous
                        )
                    }

                    resolvedLayout = chordLayoutByReducingLeadingEdge(
                        of: resolvedLayout,
                        by: reductions.current
                    )

                    if let balancedPreviousLayout = resolvedLayouts.last {
                        let minimumMinX = balancedPreviousLayout.frame.maxX + minimumGap
                        let remainingOverlap = minimumMinX - resolvedLayout.frame.minX
                        if remainingOverlap > 0 {
                            resolvedLayout = chordLayoutByReducingLeadingEdge(
                                of: resolvedLayout,
                                by: remainingOverlap
                            )
                        }
                    }
                }
            }

            if let previousIndex = resolvedLayouts.indices.last,
               resolvedLayout.frame.minX < resolvedLayouts[previousIndex].frame.maxX,
               let redistributedPair = redistributedTightSimpleChordPair(
                    previous: resolvedLayouts[previousIndex],
                    current: resolvedLayout,
                    minimumGap: minimumGap
               ) {
                resolvedLayouts[previousIndex] = redistributedPair.previous
                resolvedLayout = redistributedPair.current
            }

            resolvedLayouts.append(resolvedLayout)
        }

        return resolvedLayouts
    }

    private static func simpleChordLayout(
        _ chordLayout: LeadSheetChordLayout,
        byMovingVisibleMinXTo proposedMinX: CGFloat,
        boundedBy chordBandFrame: CGRect
    ) -> LeadSheetChordLayout? {
        let resolvedWidth = min(chordLayout.frame.width, max(1, chordBandFrame.width))
        let maximumMinX = chordBandFrame.maxX - resolvedWidth
        guard proposedMinX <= maximumMinX + 0.001 else {
            return nil
        }

        let boundedMinX = max(chordBandFrame.minX, proposedMinX)
        let deltaX = boundedMinX - chordLayout.frame.minX
        guard abs(deltaX) > 0.001 else {
            return chordLayout
        }

        var resolvedLayout = chordLayout
        resolvedLayout.frame = CGRect(
            x: boundedMinX,
            y: chordLayout.frame.minY,
            width: resolvedWidth,
            height: chordLayout.frame.height
        )
        resolvedLayout.fitFrame = CGRect(
            x: chordLayout.fitFrame.minX + deltaX,
            y: chordLayout.fitFrame.minY,
            width: min(
                max(chordLayout.fitFrame.width, resolvedWidth),
                max(1, chordBandFrame.maxX - boundedMinX)
            ),
            height: chordLayout.fitFrame.height
        )
        return resolvedLayout
    }

    private static func redistributedTightSimpleChordPair(
        previous: LeadSheetChordLayout,
        current: LeadSheetChordLayout,
        minimumGap: CGFloat
    ) -> (previous: LeadSheetChordLayout, current: LeadSheetChordLayout)? {
        let tightGapTolerance: CGFloat = 0.5
        let currentGap = current.frame.minX - previous.frame.maxX
        guard currentGap <= minimumGap + tightGapTolerance else {
            return nil
        }

        let pairMinX = previous.frame.minX
        let pairMaxX = current.frame.maxX
        let availableWidth = pairMaxX - pairMinX - minimumGap
        guard availableWidth > 2 else {
            return nil
        }

        let previousDesiredWidth = desiredSimpleChordFrameWidth(for: previous)
        let currentDesiredWidth = desiredSimpleChordFrameWidth(for: current)
        guard previousDesiredWidth + currentDesiredWidth > availableWidth + 0.001 else {
            return nil
        }

        let targetWidths = weightedSimpleChordPairWidths(
            availableWidth: availableWidth,
            previousDesiredWidth: previousDesiredWidth,
            currentDesiredWidth: currentDesiredWidth
        )
        let redistributedPrevious = chordLayoutBySettingTrailingEdgeWidth(
            of: previous,
            width: targetWidths.previous
        )
        let redistributedCurrent = chordLayoutBySettingLeadingEdgeWidth(
            of: current,
            width: targetWidths.current
        )

        return (redistributedPrevious, redistributedCurrent)
    }

    private static func desiredSimpleChordFrameWidth(for chordLayout: LeadSheetChordLayout) -> CGFloat {
        let fontSize = preferredSimpleChordFontSize()
        let estimatedWidth = estimatedSimpleChordTextWidth(
            for: chordLayout.symbol,
            fallbackText: chordLayout.text,
            fontSize: fontSize
        ) + 2
        return max(estimatedWidth, chordLayout.fitFrame.height * 0.92, chordLayout.frame.width)
    }

    private static func weightedSimpleChordPairWidths(
        availableWidth: CGFloat,
        previousDesiredWidth: CGFloat,
        currentDesiredWidth: CGFloat
    ) -> (previous: CGFloat, current: CGFloat) {
        let totalDesiredWidth = max(1, previousDesiredWidth + currentDesiredWidth)
        let minimumWidth: CGFloat = min(18, max(1, availableWidth / 2))
        let minimumTotalWidth = minimumWidth * 2
        guard availableWidth > minimumTotalWidth else {
            let previousWidth = max(1, availableWidth * previousDesiredWidth / totalDesiredWidth)
            return (previousWidth, max(1, availableWidth - previousWidth))
        }

        let remainingWidth = availableWidth - minimumTotalWidth
        let previousDesiredRemainder = max(0, previousDesiredWidth - minimumWidth)
        let currentDesiredRemainder = max(0, currentDesiredWidth - minimumWidth)
        let totalDesiredRemainder = max(1, previousDesiredRemainder + currentDesiredRemainder)
        let previousWidth = minimumWidth
            + remainingWidth * previousDesiredRemainder / totalDesiredRemainder

        return (previousWidth, max(1, availableWidth - previousWidth))
    }

    private static func weightedSimpleChordCollisionReductions(
        collisionWidth: CGFloat,
        previousFrame: CGRect,
        currentFrame: CGRect
    ) -> (previous: CGFloat, current: CGFloat) {
        let previousCapacity = max(0, previousFrame.width - 1)
        let currentCapacity = max(0, currentFrame.width - 1)
        guard collisionWidth > 0, previousCapacity + currentCapacity > 0 else {
            return (0, 0)
        }

        let combinedWidth = max(1, previousFrame.width + currentFrame.width)
        var previousReduction = min(
            collisionWidth * previousFrame.width / combinedWidth,
            previousCapacity
        )
        var currentReduction = min(
            collisionWidth * currentFrame.width / combinedWidth,
            currentCapacity
        )
        var remainingCollision = max(0, collisionWidth - previousReduction - currentReduction)

        while remainingCollision > 0.001 {
            let previousRemainingCapacity = max(0, previousCapacity - previousReduction)
            let currentRemainingCapacity = max(0, currentCapacity - currentReduction)
            guard previousRemainingCapacity + currentRemainingCapacity > 0 else {
                break
            }

            if previousRemainingCapacity >= currentRemainingCapacity {
                let extraReduction = min(remainingCollision, previousRemainingCapacity)
                previousReduction += extraReduction
                remainingCollision -= extraReduction
            } else {
                let extraReduction = min(remainingCollision, currentRemainingCapacity)
                currentReduction += extraReduction
                remainingCollision -= extraReduction
            }
        }

        return (previousReduction, currentReduction)
    }

    private static func chordLayoutBySettingTrailingEdgeWidth(
        of chordLayout: LeadSheetChordLayout,
        width: CGFloat
    ) -> LeadSheetChordLayout {
        var resolvedLayout = chordLayout
        let resolvedWidth = max(1, width)
        resolvedLayout.frame = CGRect(
            x: resolvedLayout.frame.minX,
            y: resolvedLayout.frame.minY,
            width: resolvedWidth,
            height: resolvedLayout.frame.height
        )
        resolvedLayout.fitFrame = CGRect(
            x: resolvedLayout.fitFrame.minX,
            y: resolvedLayout.fitFrame.minY,
            width: resolvedWidth,
            height: resolvedLayout.fitFrame.height
        )
        return resolvedLayout
    }

    private static func chordLayoutBySettingLeadingEdgeWidth(
        of chordLayout: LeadSheetChordLayout,
        width: CGFloat
    ) -> LeadSheetChordLayout {
        var resolvedLayout = chordLayout
        let resolvedWidth = max(1, width)
        let resolvedMinX = resolvedLayout.frame.maxX - resolvedWidth
        resolvedLayout.frame = CGRect(
            x: resolvedMinX,
            y: resolvedLayout.frame.minY,
            width: resolvedWidth,
            height: resolvedLayout.frame.height
        )
        resolvedLayout.fitFrame = CGRect(
            x: resolvedMinX,
            y: resolvedLayout.fitFrame.minY,
            width: max(resolvedWidth, resolvedLayout.fitFrame.maxX - resolvedMinX),
            height: resolvedLayout.fitFrame.height
        )
        return resolvedLayout
    }

    private static func chordLayoutByReducingTrailingEdge(
        of chordLayout: LeadSheetChordLayout,
        by reduction: CGFloat
    ) -> LeadSheetChordLayout {
        guard reduction > 0 else {
            return chordLayout
        }

        var resolvedLayout = chordLayout
        let resolvedWidth = max(1, resolvedLayout.frame.width - reduction)
        resolvedLayout.frame = CGRect(
            x: resolvedLayout.frame.minX,
            y: resolvedLayout.frame.minY,
            width: resolvedWidth,
            height: resolvedLayout.frame.height
        )
        resolvedLayout.fitFrame = CGRect(
            x: resolvedLayout.fitFrame.minX,
            y: resolvedLayout.fitFrame.minY,
            width: max(
                resolvedWidth,
                min(resolvedLayout.fitFrame.width, resolvedLayout.frame.maxX - resolvedLayout.fitFrame.minX)
            ),
            height: resolvedLayout.fitFrame.height
        )
        return resolvedLayout
    }

    private static func chordLayoutByReducingLeadingEdge(
        of chordLayout: LeadSheetChordLayout,
        by reduction: CGFloat
    ) -> LeadSheetChordLayout {
        guard reduction > 0 else {
            return chordLayout
        }

        var resolvedLayout = chordLayout
        let resolvedMinX = min(
            resolvedLayout.frame.maxX - 1,
            resolvedLayout.frame.minX + reduction
        )
        let resolvedWidth = max(1, resolvedLayout.frame.maxX - resolvedMinX)
        let fitFrameMaxX = resolvedLayout.fitFrame.maxX
        resolvedLayout.frame = CGRect(
            x: resolvedMinX,
            y: resolvedLayout.frame.minY,
            width: resolvedWidth,
            height: resolvedLayout.frame.height
        )
        resolvedLayout.fitFrame = CGRect(
            x: resolvedMinX,
            y: resolvedLayout.fitFrame.minY,
            width: max(1, fitFrameMaxX - resolvedMinX),
            height: resolvedLayout.fitFrame.height
        )

        return resolvedLayout
    }

    private static func simpleChordFitFrame(
        for placement: MeasureChordPlacement,
        nextPlacement: MeasureChordPlacement?,
        meter: Meter,
        chordBandFrame: CGRect,
        minimumWidth: CGFloat
    ) -> CGRect {
        let measureLength = max(0.0001, meter.measureLengthInWholeNotes)
        let startFraction = simpleChordPlacementVisualFraction(placement, meter: meter)
        let nextFraction = nextPlacement.map { simpleChordPlacementVisualFraction($0, meter: meter) }
        let proposedEndFraction = nextFraction ?? 1
        let beatFraction = meter.beatUnitWholeNoteLength / measureLength
        let resolvedEndFraction = min(
            1,
            max(
                startFraction + 0.03,
                proposedEndFraction > startFraction
                    ? proposedEndFraction
                    : startFraction + beatFraction
            )
        )
        let endFraction = max(startFraction, resolvedEndFraction)
        let rawMinX = chordBandFrame.minX + chordBandFrame.width * CGFloat(startFraction)
        let boundedMinX = min(
            max(chordBandFrame.minX, rawMinX),
            max(chordBandFrame.minX, chordBandFrame.maxX - minimumWidth)
        )
        let rawMaxX = chordBandFrame.minX + chordBandFrame.width * CGFloat(endFraction)

        return CGRect(
            x: boundedMinX,
            y: chordBandFrame.minY,
            width: min(
                max(1, rawMaxX - boundedMinX, minimumWidth),
                max(1, chordBandFrame.maxX - boundedMinX)
            ),
            height: chordBandFrame.height
        )
    }

    private static func simpleChordFitFrame(
        startX: CGFloat,
        nextStartX: CGFloat?,
        chordBandFrame: CGRect,
        minimumWidth: CGFloat
    ) -> CGRect {
        let boundedMinX = min(
            max(chordBandFrame.minX, startX),
            max(chordBandFrame.minX, chordBandFrame.maxX - minimumWidth)
        )
        let proposedMaxX = nextStartX.map {
            min(max($0 - simpleChordMinimumFrameGap, boundedMinX + 1), chordBandFrame.maxX)
        } ?? chordBandFrame.maxX

        return CGRect(
            x: boundedMinX,
            y: chordBandFrame.minY,
            width: min(
                max(1, proposedMaxX - boundedMinX, minimumWidth),
                max(1, chordBandFrame.maxX - boundedMinX)
            ),
            height: chordBandFrame.height
        )
    }

    private static func simpleChordDisplayFrame(
        symbol: ChordSymbol?,
        text: String,
        fitFrame: CGRect,
        manualDisplayWidth: Double? = nil
    ) -> CGRect {
        let fontSize = preferredSimpleChordFontSize()
        let estimatedWidth = max(
            1,
            estimatedSimpleChordTextWidth(for: symbol, fallbackText: text, fontSize: fontSize) + 2
        )
        let defaultVisibleWidth = max(estimatedWidth, fitFrame.height * 0.92)
        let requestedVisibleWidth = manualDisplayWidth
            .map { CGFloat(ChordEvent.clampedManualDisplayWidth($0)) }
            ?? defaultVisibleWidth
        let visibleWidth = min(fitFrame.width, max(1, requestedVisibleWidth))

        return CGRect(
            x: fitFrame.minX,
            y: fitFrame.minY,
            width: max(1, visibleWidth),
            height: fitFrame.height
        )
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
                let frame = cueTextFrame(
                    for: cueText,
                    cueIndex: cueIndex,
                    measureFrame: measureFrame,
                    chordBandFrame: chordBandFrame,
                    staffFrame: staffFrame
                )
                let hitFrame = cueTextHitFrame(
                    for: cueText,
                    cueIndex: cueIndex,
                    measureFrame: measureFrame,
                    chordBandFrame: chordBandFrame,
                    staffFrame: staffFrame
                )
                let beatFraction = cueText.beatFraction.map { CGFloat($0) }

                return LeadSheetCueTextLayout(
                    id: cueText.id,
                    text: cueText.text,
                    frame: frame,
                    hitFrame: hitFrame,
                    position: cueText.position,
                    emphasis: cueText.emphasis,
                    scale: CGFloat(cueText.scale),
                    beatFraction: beatFraction,
                    verticalOffset: CGFloat(cueText.verticalOffset)
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
        let textSize = cueTextSize(for: cueText)
        let lineHeight = textSize.height
        let lineGap: CGFloat = 3
        let offset = CGFloat(cueIndex) * (lineHeight + lineGap)
        let maximumWidth = max(1, staffFrame.width - 12)
        let width = min(maximumWidth, textSize.width)
        let leadingWidth = min(width, max(1, staffFrame.width - 8))
        let defaultTextX = staffFrame.minX + 6
        let beatAnchoredTextX = cueText.beatFraction.map { fraction in
            clampedCueTextX(
                staffFrame.minX + CGFloat(fraction) * staffFrame.width,
                width: width,
                staffFrame: staffFrame
            )
        }
        let leadingFrame = CGRect(
            x: measureFrame.minX + 4,
            y: staffFrame.minY,
            width: leadingWidth,
            height: lineHeight
        )
        let trailingFrame = CGRect(
            x: max(measureFrame.minX + 4, staffFrame.maxX - leadingWidth - 4),
            y: staffFrame.minY,
            width: leadingWidth,
            height: lineHeight
        )

        let baseFrame: CGRect
        switch cueText.position {
        case .above:
            let textX = beatAnchoredTextX ?? defaultTextX
            if chordBandFrame.intersects(staffFrame) {
                baseFrame = CGRect(
                    x: textX,
                    y: min(measureFrame.maxY - lineHeight - 2, staffFrame.minY + 4 + offset),
                    width: width,
                    height: lineHeight
                )
            } else {
                baseFrame = CGRect(
                    x: textX,
                    y: max(measureFrame.minY + 2, chordBandFrame.maxY - lineHeight - 2 - offset),
                    width: width,
                    height: lineHeight
                )
            }
        case .below:
            baseFrame = CGRect(
                x: beatAnchoredTextX ?? defaultTextX,
                y: min(measureFrame.maxY - lineHeight - 2, staffFrame.maxY + 5 + offset),
                width: width,
                height: lineHeight
            )
        case .leadingEdge:
            baseFrame = leadingFrame.offsetBy(dx: 0, dy: offset)
        case .trailingEdge:
            baseFrame = trailingFrame.offsetBy(dx: 0, dy: offset)
        }

        return baseFrame.offsetBy(dx: 0, dy: CGFloat(cueText.verticalOffset))
    }

    private static func clampedCueTextX(_ proposedX: CGFloat, width: CGFloat, staffFrame: CGRect) -> CGFloat {
        let minimumX = staffFrame.minX + 4
        let maximumX = max(minimumX, staffFrame.maxX - width - 4)
        return min(max(proposedX, minimumX), maximumX)
    }

    private static func cueTextHitFrame(
        for cueText: CueText,
        cueIndex: Int,
        measureFrame: CGRect,
        chordBandFrame: CGRect,
        staffFrame: CGRect
    ) -> CGRect {
        cueTextFrame(
            for: cueText,
            cueIndex: cueIndex,
            measureFrame: measureFrame,
            chordBandFrame: chordBandFrame,
            staffFrame: staffFrame
        )
        .insetBy(dx: -6, dy: -5)
    }

    private static func cueTextSize(for cueText: CueText) -> CGSize {
        let fontSize = cueTextFontSize(for: cueText)
        let estimatedWidth = cueText.text.reduce(CGFloat(0)) { partialWidth, character in
            partialWidth + estimatedCueTextCharacterWidth(character, fontSize: fontSize)
        }
        let height = max(16, fontSize * 1.34)
        return CGSize(width: max(28, estimatedWidth + 12), height: height)
    }

    private static func cueTextFontSize(for cueText: CueText) -> CGFloat {
        let baseSize: CGFloat
        switch cueText.emphasis {
        case .subtle:
            baseSize = 12.5
        case .normal:
            baseSize = 14
        case .strong:
            baseSize = 15.5
        }

        return baseSize * CGFloat(cueText.scale)
    }

    private static func estimatedCueTextCharacterWidth(_ character: Character, fontSize: CGFloat) -> CGFloat {
        switch character {
        case "i", "l", "I", "1", ".", ",", "'", " ":
            return fontSize * 0.32
        case "m", "M", "w", "W":
            return fontSize * 0.9
        case "A"..."Z":
            return fontSize * 0.68
        default:
            return fontSize * 0.58
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

        let baseLayouts = slots.enumerated().map { index, slot in
            let noteCenterX = slashAttackCenterX(
                for: slot,
                meter: meter,
                staffFrame: staffFrame,
                usableWidth: usableWidth
            )

            switch slot.duration {
            case .measureRepeat:
                return measureRepeatLayout(
                    staffFrame: staffFrame,
                    staffLineYPositions: staffLineYPositions
                )
            case .wholeRest:
                return wholeRestLayout(centerX: staffFrame.midX, staffLineYPositions: staffLineYPositions)
            case .halfRest:
                return halfRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .quarterRest:
                return quarterRestLayout(centerX: noteCenterX, staffLineYPositions: staffLineYPositions)
            case .dottedQuarterRest:
                return quarterRestLayout(
                    centerX: noteCenterX,
                    staffLineYPositions: staffLineYPositions,
                    isDotted: true
                )
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
                let resolvedFlagStyle: LeadSheetNoteLayout.FlagStyle
                if slot.duration == .sixteenth,
                   beamEndPoint != nil {
                    resolvedFlagStyle = .double
                } else if slot.duration == .sixteenth,
                          isBeamedFromPrevious {
                    resolvedFlagStyle = .secondaryBackward
                } else if slot.duration.isSlashBeamableValue,
                          beamEndPoint == nil,
                          !isBeamedFromPrevious {
                    resolvedFlagStyle = flagStyle(for: slot.duration)
                } else {
                    resolvedFlagStyle = .none
                }
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
                    flagStyle: resolvedFlagStyle,
                    dotFrame: dotFrame,
                    tieFrame: nil,
                    beamEndPoint: beamEndPoint
                )
            }
        }

        return layoutsByApplyingTieFrames(
            baseLayouts,
            slots: slots,
            tieOutSlotIndices: measure.rhythmMap?.tieOutSlotIndices ?? [],
            staffSpace: staffSpace
        )
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

        let baseLayouts = slots.enumerated().map { index, slot in
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

        return layoutsByApplyingTieFrames(
            baseLayouts,
            slots: slots,
            tieOutSlotIndices: measure.rhythmMap?.tieOutSlotIndices ?? [],
            staffSpace: staffSpace
        )
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
        guard RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
            beforeValueAt: index + 1,
            in: slots.map(\.duration),
            meter: meter
        ) else {
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
              RhythmRecognitionContextRules.allowsBeamAcrossBoundary(
                beforeValueAt: index,
                in: slots.map(\.duration),
                meter: meter
              ) else {
            return false
        }

        let previousStart = slots[index - 1].startPosition.startOffset(in: meter) ?? 0
        let currentStart = slots[index].startPosition.startOffset(in: meter) ?? 0
        return abs((previousStart + slots[index - 1].duration.wholeNoteLength(in: meter)) - currentStart) < 0.0001
    }

    private static func layoutsByApplyingTieFrames(
        _ layouts: [LeadSheetNoteLayout],
        slots: [MeasureRhythmSlot],
        tieOutSlotIndices: Set<Int>,
        staffSpace: CGFloat
    ) -> [LeadSheetNoteLayout] {
        guard !tieOutSlotIndices.isEmpty else {
            return layouts
        }

        var updatedLayouts = layouts
        for index in tieOutSlotIndices {
            guard updatedLayouts.indices.contains(index),
                  updatedLayouts.indices.contains(index + 1),
                  slots.indices.contains(index),
                  slots.indices.contains(index + 1),
                  slots[index].duration.supportsPitchedLeadSheetNote,
                  slots[index + 1].duration.supportsPitchedLeadSheetNote,
                  let tieFrame = tieFrame(
                    from: updatedLayouts[index].noteheadFrame,
                    to: updatedLayouts[index + 1].noteheadFrame,
                    staffSpace: staffSpace
                  ) else {
                continue
            }

            updatedLayouts[index].tieFrame = tieFrame
        }

        return updatedLayouts
    }

    private static func tieFrame(
        from currentNoteheadFrame: CGRect,
        to nextNoteheadFrame: CGRect,
        staffSpace: CGFloat
    ) -> CGRect? {
        let startX = currentNoteheadFrame.maxX - min(CGFloat(2), staffSpace * 0.2)
        let endX = nextNoteheadFrame.minX + min(CGFloat(2), staffSpace * 0.2)
        guard endX > startX + max(CGFloat(8), staffSpace * 0.7) else {
            return nil
        }

        let tieHeight = max(CGFloat(6), staffSpace * 0.72)
        let endpointY = min(currentNoteheadFrame.minY, nextNoteheadFrame.minY) - max(CGFloat(2), staffSpace * 0.18)
        return CGRect(
            x: startX,
            y: endpointY - tieHeight,
            width: endX - startX,
            height: tieHeight
        )
    }

    private static func wholeRestLayout(
        centerX: CGFloat,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let staffSpace = staffLineYPositions[1] - staffLineYPositions[0]
        let restFrame = CGRect(
            x: centerX - 9,
            y: staffLineYPositions[2] + 1,
            width: 18,
            height: 6
        )
        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .wholeRest,
            noteheadSymbol: nil,
            noteheadFrame: restFrame,
            staffSpace: staffSpace,
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
        staffLineYPositions: [CGFloat],
        isDotted: Bool = false
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
            dotFrame: isDotted
                ? CGRect(x: restFrame.maxX + 4, y: restFrame.midY - 1.5, width: 3, height: 3)
                : nil,
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

    private static func measureRepeatLayout(
        staffFrame: CGRect,
        staffLineYPositions: [CGFloat]
    ) -> LeadSheetNoteLayout {
        let staffSpace = staffLineYPositions[1] - staffLineYPositions[0]
        let symbolWidth = max(staffSpace * 2.35, CGFloat(28))
        let symbolHeight = max(staffSpace * 1.65, CGFloat(18))
        let symbolFrame = CGRect(
            x: staffFrame.midX - symbolWidth / 2,
            y: staffLineYPositions[2] - symbolHeight / 2,
            width: symbolWidth,
            height: symbolHeight
        )

        return LeadSheetNoteLayout(
            id: UUID(),
            symbolStyle: .measureRepeat,
            noteheadSymbol: nil,
            noteheadFrame: symbolFrame,
            staffSpace: staffSpace,
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
        case .slash, .quarter, .dottedQuarter, .dottedEighth, .sixteenth, .eighth, .quarterRest,
             .dottedQuarterRest, .sixteenthRest, .eighthRest, .measureRepeat, .tiedContinuation:
            return .filled
        }
    }

    private static func dottedDuration(_ duration: RhythmValue) -> Bool {
        switch duration {
        case .dottedEighth, .dottedQuarter, .dottedQuarterRest, .dottedHalf:
            return true
        case .slash, .sixteenth, .sixteenthRest, .eighth, .eighthRest, .quarter, .quarterRest, .half, .halfRest,
             .whole, .wholeRest, .measureRepeat, .tiedContinuation:
            return false
        }
    }

    private static func flagStyle(for duration: RhythmValue) -> LeadSheetNoteLayout.FlagStyle {
        switch duration {
        case .sixteenth:
            return .double
        case .dottedEighth, .eighth:
            return .single
        case .slash, .sixteenthRest, .eighthRest, .quarter, .quarterRest, .dottedQuarterRest, .dottedQuarter,
             .half, .halfRest, .dottedHalf, .whole, .wholeRest, .measureRepeat, .tiedContinuation:
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
        self == .eighth || self == .dottedEighth || self == .sixteenth
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
    var chordInkTargetMeasureID: UUID?
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
