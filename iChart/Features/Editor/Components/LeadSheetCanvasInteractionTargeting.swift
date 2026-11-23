#if canImport(UIKit)
import Foundation
import UIKit

struct LeadSheetChordMovePositionPreview {
    var measureID: UUID
    var referenceFrame: CGRect
    var guideFrame: CGRect
    var guideXs: [CGFloat]
    var activeGuideX: CGFloat?
    var targetFraction: Double
    var targetX: CGFloat
}

struct ActiveChordMoveDrag {
    var chordID: UUID
    var sourcePageLayout: LeadSheetPageLayout
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startLocation: CGPoint
    var currentPositionPreview: LeadSheetChordMovePositionPreview? = nil
    var screenPointsPerDisplayedPoint: CGFloat = 1
}

struct ActiveChordResizeDrag {
    enum Edge: Equatable {
        case leading
        case trailing
    }

    var chordID: UUID
    var sourcePageLayout: LeadSheetPageLayout
    var edge: Edge
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startLocation: CGPoint
    var initialHorizontalScale: CGFloat = 1
    var screenPointsPerDisplayedPoint: CGFloat = 1
}

typealias LeadSheetChordMovePositionGuidePolicy = LeadSheetChordPlacementGuidePolicy

struct LeadSheetCueTextMoveProjection {
    var measureID: UUID
    // Discrete compatibility anchor for older builds; never drives live x.
    var fraction: Double?
    var verticalOffset: Double
    var cueLayout: LeadSheetCueTextLayout
    var horizontalPlacement: CueTextHorizontalPlacement? = nil
    var attachmentGuide: CGPoint? = nil
    // Nil preserves the source archive during a no-op. A body move authors
    // its achieved page-bounded height without the legacy ±72-point limit.
    var manualVerticalOffset: Double? = nil
}

struct LeadSheetCueTextMoveAnchor: Hashable {
    var measureID: UUID
    var fraction: Double?
    var horizontalPlacement: CueTextHorizontalPlacement? = nil
}

struct LeadSheetCueTextMoveTemplateKey: Equatable {
    var measureID: UUID
    var fraction: Double?
    var wrapWidth: Double?
}

struct LeadSheetCueTextMoveMeasureGeometry {
    var id: UUID
    var staffFrame: CGRect
    var meter: Meter
}

struct LeadSheetCueTextMoveRowGeometry {
    var minimumY: CGFloat
    var maximumY: CGFloat
    var paper: CGRect
    var measures: [LeadSheetCueTextMoveMeasureGeometry]
    var leadingMargin: ClosedRange<CGFloat>?
    var trailingMargin: ClosedRange<CGFloat>?
}

struct LeadSheetCueTextMoveProjectionKey: Equatable {
    var anchor: LeadSheetCueTextMoveAnchor
    var verticalOffset: Double
}

enum LeadSheetCueTextMoveDragPolicy {
    private struct HorizontalTarget {
        var measure: LeadSheetCueTextMoveMeasureGeometry
        var fraction: Double?
        var placement: CueTextHorizontalPlacement?
    }

    static func update(_ drag: inout ActiveCueTextMoveDrag, at location: CGPoint) {
        let dx = location.x - drag.startLocation.x
        let dy = location.y - drag.startLocation.y
        guard dx.isFinite, dy.isFinite else { drag.currentProjection = nil; return }
        if max(abs(dx), abs(dy)) * drag.screenPointsPerDisplayedPoint <= 0.1 {
            restoreInitialProjection(&drag)
            return
        }
        // Jitter protection belongs to vertical movement. A small deliberate
        // horizontal move still follows the Pencil continuously.
        let horizontalScreenTravel = abs(dx) * drag.screenPointsPerDisplayedPoint
        let keepsVerticalAnchor = horizontalScreenTravel <= 2 && abs(dy) > abs(dx)
        // A tall adjustment can include a few points of intentional X motion.
        // Keep that motion visible while measuring ownership in the source row;
        // crossing a real barline still changes the owner. Larger diagonals can
        // deliberately carry the cue to another row or page.
        let retainsSourceRow = horizontalScreenTravel <= 12 && abs(dy) > abs(dx) * 1.5
        let target: HorizontalTarget
        if keepsVerticalAnchor {
            target = HorizontalTarget(measure: .init(id: drag.sourceCue.anchorMeasureID,
                staffFrame: drag.sourceMeasure.staffFrame, meter: drag.sourceMeter),
                fraction: drag.sourceCue.beatFraction,
                placement: drag.sourceCue.horizontalPlacement)
        } else if let resolved = horizontalTarget(for: &drag, dx: dx, dy: retainsSourceRow ? 0 : dy) {
            target = resolved
        } else {
            drag.currentProjection = nil
            return
        }
        let measureID = target.measure.id
        let templateKey = LeadSheetCueTextMoveTemplateKey(measureID: measureID,
            fraction: target.placement == nil ? target.fraction : nil, wrapWidth: target.placement?.wrapWidth)
        let template: LeadSheetCueTextMovePreviewTemplate
        if drag.previewTemplateKey == templateKey, let cached = drag.previewTemplate {
            template = cached
        } else {
            guard let resolved = LeadSheetPageLayoutEngine.cueTextMovePreviewTemplate(
                chart: drag.sourceChart, sourcePageLayout: drag.sourcePageLayout, cueID: drag.cueTextID,
                targetMeasureID: measureID, fraction: target.fraction, horizontalPlacement: target.placement)
            else { drag.currentProjection = nil; return }
            template = resolved
            drag.previewTemplateKey = templateKey
            drag.previewTemplate = resolved
        }
        let intendedDY = abs(dy) * drag.screenPointsPerDisplayedPoint <= 1 ? 0 : dy
        let baseY = template.frame.minY - template.verticalOffsetFromDefault
        let offset = Double(drag.initialFrame.minY + intendedDY - baseY)
        let anchor = LeadSheetCueTextMoveAnchor(measureID: measureID, fraction: target.fraction,
            horizontalPlacement: target.placement)
        let key = LeadSheetCueTextMoveProjectionKey(anchor: anchor, verticalOffset: offset)
        guard drag.lastProjectionKey != key else { return }
        drag.lastProjectionKey = key
        guard let layout = LeadSheetPageLayoutEngine.cueTextMovePreview(chart: drag.sourceChart,
            sourcePageLayout: drag.sourcePageLayout, cueID: drag.cueTextID, targetMeasureID: measureID,
            fraction: target.fraction, verticalOffset: offset,
            horizontalPlacement: target.placement, template: template,
            usesFreeVerticalPlacement: true) else {
            drag.currentProjection = nil
            return
        }
        if measureID == drag.sourceCue.anchorMeasureID,
           abs(layout.frame.minX - drag.initialFrame.minX) < 0.001,
           abs(layout.frame.minY - drag.initialFrame.minY) < 0.001,
           abs(layout.frame.width - drag.initialFrame.width) < 0.001,
           abs(layout.frame.height - drag.initialFrame.height) < 0.001 {
            restoreInitialProjection(&drag)
            return
        }
        drag.currentProjection = LeadSheetCueTextMoveProjection(measureID: measureID,
            fraction: target.fraction, verticalOffset: Double(layout.verticalOffsetFromDefault), cueLayout: layout,
            horizontalPlacement: target.placement,
            attachmentGuide: guide(for: target.placement, measure: target.measure),
            manualVerticalOffset: Double(layout.verticalOffsetFromDefault))
        drag.currentFrame = layout.frame
    }

    private static func horizontalTarget(for drag: inout ActiveCueTextMoveDrag,
        dx: CGFloat, dy: CGFloat) -> HorizontalTarget? {
        let y = drag.sourceMeasure.frame.midY + dy
        let rowIndex: Int
        if drag.ownershipY == y, let cached = drag.ownershipRowIndex {
            rowIndex = cached
        } else {
            var bestIndex: Int?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (index, row) in drag.ownershipRows.enumerated() {
                let distance = max(row.minimumY - y, y - row.maximumY, 0)
                if distance < bestDistance { bestIndex = index; bestDistance = distance }
            }
            // Free vertical placement can end in the whitespace well beyond
            // a row. Ownership chooses the nearest row; paper bounds, rather
            // than the old local-offset reach, constrain the displayed cue.
            guard let found = bestIndex else { return nil }
            rowIndex = found
            drag.ownershipY = y
            drag.ownershipRowIndex = found
        }
        let row = drag.ownershipRows[rowIndex]
        guard let first = row.measures.first, let last = row.measures.last else { return nil }
        let minimumX = row.paper.minX + 4
        let maximumX = max(minimumX, row.paper.maxX - 4 - drag.initialFrame.width)
        let x = min(max(drag.initialFrame.minX + dx, minimumX), maximumX)
        let region: CueTextHorizontalPlacement.Region
        let owner: LeadSheetCueTextMoveMeasureGeometry
        let range: ClosedRange<CGFloat>
        if x < first.staffFrame.minX, let margin = row.leadingMargin {
            region = .leadingMargin
            owner = first
            range = margin
        } else if x >= last.staffFrame.maxX, let margin = row.trailingMargin {
            region = .trailingMargin
            owner = last
            range = margin
        } else {
            region = .measure
            // Only the leading origin crossing a true boundary changes owner.
            owner = row.measures.first(where: { x < $0.staffFrame.maxX }) ?? last
            range = owner.staffFrame.minX...owner.staffFrame.maxX
        }
        let boundedX = min(max(x, range.lowerBound), range.upperBound)
        let fraction = Double((boundedX - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound))
        let wrapWidth = drag.sourceCue.horizontalPlacement?.wrapWidth
            ?? Double(max(1, drag.sourceMeasure.staffFrame.width - 12))
        let placement = CueTextHorizontalPlacement(region: region, fraction: fraction, wrapWidth: wrapWidth)
        // This fallback helps older builds; the continuous override alone
        // determines rendering and the Pencil never snaps to this beat value.
        let fallbackFraction = region == .leadingMargin ? 0 : (region == .trailingMargin ? 0.9999 : fraction)
        let legacyFraction = MeasurePlacementGrid.snappedFraction(fallbackFraction, in: owner.meter)
        return HorizontalTarget(measure: owner, fraction: legacyFraction, placement: placement)
    }

    private static func guide(for placement: CueTextHorizontalPlacement?,
        measure: LeadSheetCueTextMoveMeasureGeometry) -> CGPoint? {
        if let placement, placement.region != .measure { return nil }
        return CGPoint(x: measure.staffFrame.midX, y: measure.staffFrame.midY)
    }

    @discardableResult
    static func commit(_ drag: ActiveCueTextMoveDrag, in chart: inout Chart) -> Bool {
        guard chart.id == drag.sourceChart.id, chart.cueText(id: drag.cueTextID) == drag.sourceCue,
              let target = drag.currentProjection,
              target.measureID != drag.sourceCue.anchorMeasureID
                || target.fraction != drag.sourceCue.beatFraction
                || target.horizontalPlacement != drag.sourceCue.horizontalPlacement
                || target.manualVerticalOffset != drag.sourceCue.manualVerticalOffset
                || abs(target.verticalOffset - drag.sourceCue.verticalOffset) > 1e-9 else { return false }
        return apply(target, drag: drag, to: &chart)
    }

    static func finish(_ drag: inout ActiveCueTextMoveDrag) {
        guard var target = drag.currentProjection else { return }
        // Movement inside the same owner is already projected on the frozen
        // row. Only a reattachment can require one final pagination pass.
        if target.measureID == drag.sourceCue.anchorMeasureID { return }
        var projected = drag.sourceChart
        guard commit(drag, in: &projected) else { return }
        // Reanchoring can change a row’s automatic reserve and page breaks.
        // It uses the same resolved placement; release never reinterprets the
        // Pencil endpoint or changes the selected cue's continuous target.
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: projected,
            pageSize: drag.sourcePageSize)
        guard let cue = layout.systems.flatMap(\.measures).flatMap(\.cueTextLayouts)
            .first(where: { $0.id == drag.cueTextID }) else { return }
        target.cueLayout = cue
        target.verticalOffset = Double(cue.verticalOffsetFromDefault)
        target.manualVerticalOffset = Double(cue.verticalOffsetFromDefault)
        if let measure = layout.systems.flatMap(\.measures).first(where: { $0.sourceMeasureID == target.measureID }) {
            target.attachmentGuide = guide(for: target.horizontalPlacement,
                measure: .init(id: target.measureID, staffFrame: measure.staffFrame,
                    meter: projected.measure(id: target.measureID)?.resolvedMeter(defaultMeter: projected.defaultMeter)
                        ?? projected.defaultMeter))
        }
        drag.currentProjection = target
        drag.currentFrame = cue.frame
        drag.pageLayoutProjectionCount += 1
    }

    private static func apply(_ target: LeadSheetCueTextMoveProjection,
        drag: ActiveCueTextMoveDrag, to chart: inout Chart) -> Bool {
        if target.measureID == drag.sourceCue.anchorMeasureID,
           target.fraction == drag.sourceCue.beatFraction,
           target.horizontalPlacement == drag.sourceCue.horizontalPlacement {
            // Existing archives can contain a non-grid fraction. A vertical
            // adjustment must not silently resnap that horizontal anchor.
            guard let offset = target.manualVerticalOffset else { return false }
            return chart.setCueTextManualVerticalOffset(drag.cueTextID, to: offset)
        }
        return chart.moveCueText(drag.cueTextID, to: target.measureID,
            atFraction: target.fraction, horizontalPlacement: target.horizontalPlacement,
            manualVerticalOffset: target.manualVerticalOffset)
    }

    private static func restoreInitialProjection(_ drag: inout ActiveCueTextMoveDrag) {
        guard let layout = drag.sourceMeasure.cueTextLayouts.first(where: { $0.id == drag.cueTextID }) else { return }
        drag.currentProjection = LeadSheetCueTextMoveProjection(measureID: drag.sourceCue.anchorMeasureID,
            fraction: drag.sourceCue.beatFraction, verticalOffset: drag.sourceCue.verticalOffset, cueLayout: layout,
            horizontalPlacement: drag.sourceCue.horizontalPlacement,
            attachmentGuide: guide(for: drag.sourceCue.horizontalPlacement,
                measure: .init(id: drag.sourceCue.anchorMeasureID, staffFrame: drag.sourceMeasure.staffFrame,
                    meter: drag.sourceMeter)),
            manualVerticalOffset: drag.sourceCue.manualVerticalOffset)
        drag.currentFrame = drag.initialFrame
        drag.lastProjectionKey = nil
    }
}

enum LeadSheetChordMoveDragPolicy {
    static func hasMeaningfulTranslation(
        for drag: ActiveChordMoveDrag,
        at location: CGPoint
    ) -> Bool {
        hypot(location.x - drag.startLocation.x, location.y - drag.startLocation.y)
            * max(0.0001, drag.screenPointsPerDisplayedPoint) >= 0.1
    }

    static func previewFrame(
        for drag: ActiveChordMoveDrag,
        at location: CGPoint,
        boundedBy movementFrame: CGRect
    ) -> CGRect {
        let proposedFrame = drag.initialFrame.offsetBy(
            dx: location.x - drag.startLocation.x,
            dy: location.y - drag.startLocation.y
        )
        let resolvedWidth = min(max(1, proposedFrame.width), max(1, movementFrame.width))
        let resolvedHeight = min(max(1, proposedFrame.height), max(1, movementFrame.height))
        let resolvedX = min(
            max(proposedFrame.minX, movementFrame.minX),
            max(movementFrame.minX, movementFrame.maxX - resolvedWidth)
        )
        let resolvedY = min(
            max(proposedFrame.minY, movementFrame.minY),
            max(movementFrame.minY, movementFrame.maxY - resolvedHeight)
        )

        return CGRect(
            x: resolvedX,
            y: resolvedY,
            width: resolvedWidth,
            height: resolvedHeight
        )
    }

    static func target(
        at location: CGPoint,
        for drag: ActiveChordMoveDrag,
        chart: Chart? = nil
    ) -> (measureID: UUID, fraction: Double)? {
        if let chart {
            // Commit the exact drag preview. Re-running the stateless 18-point
            // placement policy here would undo the user's fine adjustment.
            guard let preview = drag.currentPositionPreview
                ?? positionPreview(at: location, for: drag, chart: chart) else {
                return nil
            }
            return (preview.measureID, preview.targetFraction)
        }

        let locationTarget = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
            measureAnchor: location,
            fractionAnchorX: drag.currentFrame.minX,
            in: drag.sourcePageLayout,
            chart: chart
        )
        let frameMeasureAnchor = CGPoint(
            x: drag.currentFrame.midX,
            y: drag.currentFrame.midY
        )
        let frameTarget = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
            measureAnchor: frameMeasureAnchor,
            fractionAnchorX: drag.currentFrame.minX,
            in: drag.sourcePageLayout,
            chart: chart
        )

        if drag.currentFrame == drag.initialFrame {
            return LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                at: location,
                in: drag.sourcePageLayout,
                chart: chart
            ) ?? frameTarget
        }

        return locationTarget ?? frameTarget
    }

    static func positionPreview(
        at location: CGPoint,
        for drag: ActiveChordMoveDrag,
        chart: Chart
    ) -> LeadSheetChordMovePositionPreview? {
        let initialCenter = CGPoint(x: drag.initialFrame.midX, y: drag.initialFrame.midY)
        let movementFrame = drag.sourcePageLayout.paperFrame(containing: initialCenter)
            ?? drag.sourcePageLayout.paperFrame
        let rawFrame = previewFrame(for: drag, at: location, boundedBy: movementFrame)
        let sourceMeasure = drag.sourcePageLayout.systems.flatMap(\.measures).first {
            $0.chordLayouts.contains { $0.id == drag.chordID }
        }
        let sourceGuideX = sourceMeasure.map {
            LeadSheetChordPlacementGuidePolicy.guideFrame(for: $0, referenceFrame: $0.chordBandFrame).minX
        } ?? drag.initialFrame.minX
        // Only the leading-edge adjustment changes ownership from the glyph
        // edge. Ordinary rightward moves retain the established pointer target.
        let followsLeadingEdge = rawFrame.minX <= sourceGuideX
            && (rawFrame.minX <= drag.initialFrame.minX || drag.initialFrame.minX <= sourceGuideX)
        let measureAnchor = followsLeadingEdge
            ? CGPoint(x: rawFrame.minX, y: location.y) : location
        return LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
            measureAnchor: measureAnchor,
            fractionAnchorX: rawFrame.minX,
            in: drag.sourcePageLayout,
            chart: chart,
            dragInitialX: drag.initialFrame.minX,
            screenPointsPerDisplayedPoint: drag.screenPointsPerDisplayedPoint,
            usesPhysicalMeasureBoundaries: followsLeadingEdge
        ) ?? LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
            measureAnchor: CGPoint(x: followsLeadingEdge ? rawFrame.minX : rawFrame.midX, y: rawFrame.midY),
            fractionAnchorX: rawFrame.minX,
            in: drag.sourcePageLayout,
            chart: chart,
            dragInitialX: drag.initialFrame.minX,
            screenPointsPerDisplayedPoint: drag.screenPointsPerDisplayedPoint,
            usesPhysicalMeasureBoundaries: followsLeadingEdge
        )
    }

    @discardableResult
    static func commit(_ drag: ActiveChordMoveDrag, at location: CGPoint, in chart: inout Chart) -> Bool {
        guard hasMeaningfulTranslation(for: drag, at: location),
              let preview = drag.currentPositionPreview ?? positionPreview(at: location, for: drag, chart: chart),
              let chord = chart.chordEvent(id: drag.chordID) else { return false }
        let isSameMeasure = chart.measureContainingChordEvent(id: drag.chordID)?.id == preview.measureID
        let isBeforeDownbeat = preview.targetX < preview.guideFrame.minX - 0.0001
        let isAtDownbeatGuide = preview.activeGuideX.map { abs($0 - preview.guideFrame.minX) <= 0.0001 } ?? false
        let targetsDownbeat = isBeforeDownbeat || isAtDownbeatGuide
        let isAlreadyOnDownbeat = chord.startPosition.beat == 1 && chord.startPosition.subdivision == 0
        let preserveMusicalPlacement = isSameMeasure && (targetsDownbeat
            ? isAlreadyOnDownbeat : preview.activeGuideX == nil)
        return chart.moveChordEventInCommittedChordLane(drag.chordID, to: preview.measureID,
            atFraction: targetsDownbeat ? 0 : preview.targetFraction,
            visualFraction: preview.targetFraction, preserveMusicalPlacement: preserveMusicalPlacement,
            allowsLeadingVisualInset: isBeforeDownbeat)
    }
}

enum LeadSheetChordResizeDragPolicy {
    static func hasMeaningfulTranslation(
        for drag: ActiveChordResizeDrag,
        at location: CGPoint
    ) -> Bool {
        abs(location.x - drag.startLocation.x)
            * max(0.0001, drag.screenPointsPerDisplayedPoint) >= 0.1
    }

    static func horizontalScale(for drag: ActiveChordResizeDrag) -> Double {
        ChordEvent.clampedManualHorizontalScale(
            Double(drag.initialHorizontalScale * drag.currentFrame.width / max(0.001, drag.initialFrame.width))
        )
    }

    static func visualPlacement(for drag: ActiveChordResizeDrag) -> (measureID: UUID, fraction: Double)? {
        guard let measure = drag.sourcePageLayout.systems.flatMap(\.measures).first(where: {
            $0.chordLayouts.contains { $0.id == drag.chordID }
        }), let measureID = measure.sourceMeasureID, measure.chordBandFrame.width > 0 else {
            return nil
        }
        return (
            measureID,
            ChordEvent.clampedManualLaneFraction(Double(
                (drag.currentFrame.minX - measure.chordBandFrame.minX) / measure.chordBandFrame.width
            ))
        )
    }

    static func previewFrame(
        for drag: ActiveChordResizeDrag,
        at location: CGPoint,
        boundedBy _: CGRect
    ) -> CGRect {
        let deltaX = location.x - drag.startLocation.x
        guard deltaX.isFinite else { return drag.initialFrame }
        let initialScale = CGFloat(ChordEvent.clampedManualHorizontalScale(Double(drag.initialHorizontalScale)))
        let proposedWidth = drag.initialFrame.width + (drag.edge == .leading ? -deltaX : deltaX)
        // Width-only compression has explicit limits, never a density-based
        // font fit. Height and vertical position remain fixed throughout a drag.
        let scale = CGFloat(ChordEvent.clampedManualHorizontalScale(
            Double(initialScale * proposedWidth / max(0.001, drag.initialFrame.width))
        ))
        var width = drag.initialFrame.width * scale / initialScale
        if drag.edge == .leading,
           let sourceMeasure = drag.sourcePageLayout.systems.flatMap(\.measures).first(where: {
               $0.chordLayouts.contains { $0.id == drag.chordID }
           }) {
            let movement = LeadSheetChordPlacementGuidePolicy.visualMovementFrame(
                for: sourceMeasure, referenceFrame: sourceMeasure.chordBandFrame)
            // A leading grip holds the right visible edge. It may approach the
            // measure's safe visual start, but never crosses a signature/repeat
            // reserve or changes the chord's musical measure/beat.
            let minimumX = min(drag.initialFrame.minX, movement.minX)
            width = min(width, max(0.001, drag.initialFrame.maxX - minimumX))
        }
        return CGRect(
            x: drag.edge == .leading ? drag.initialFrame.maxX - width : drag.initialFrame.minX,
            y: drag.initialFrame.minY,
            width: width,
            height: drag.initialFrame.height
        )
    }
}

struct CommittedChordBarlineHitTarget: Equatable {
    enum Action: Equatable {
        case select
        case delete
    }

    var measureID: UUID
    var action: Action
}

enum LeadSheetCommittedChordBarlineOverlayGeometry {
    static let lineHitWidth: CGFloat = 20
    static let deleteControlSize: CGFloat = 18
    static let deleteHitOutset: CGFloat = 12

    static func lineFrame(
        for measure: LeadSheetMeasureLayout,
        layoutStyle: ChartLayoutStyle = .simpleChordSheet
    ) -> CGRect {
        let reference = layoutStyle == .rhythmSectionSheet ? measure.staffFrame : measure.chordBandFrame
        return CGRect(
            x: measure.trailingBarlineFrame.midX - lineHitWidth / 2,
            y: reference.minY,
            width: lineHitWidth,
            height: reference.height
        )
    }

    static func controlFrames(
        for measure: LeadSheetMeasureLayout,
        layoutStyle: ChartLayoutStyle = .simpleChordSheet
    ) -> ChordDraftBarlineControlFrames {
        let lineFrame = lineFrame(for: measure, layoutStyle: layoutStyle)
        return ChordDraftBarlineControlFrames(
            delete: CGRect(
                x: lineFrame.midX - deleteControlSize / 2,
                y: lineFrame.minY - deleteControlSize - 3,
                width: deleteControlSize,
                height: deleteControlSize
            )
        )
    }

    static func hitTarget(
        at location: CGPoint,
        measures: [LeadSheetMeasureLayout],
        selectedMeasureID: UUID?,
        layoutStyle: ChartLayoutStyle = .simpleChordSheet
    ) -> CommittedChordBarlineHitTarget? {
        for measure in measures.reversed() {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            if selectedMeasureID == measureID {
                let controls = controlFrames(for: measure, layoutStyle: layoutStyle)
                if controls.delete.insetBy(dx: -deleteHitOutset, dy: -deleteHitOutset).contains(location) {
                    return CommittedChordBarlineHitTarget(measureID: measureID, action: .delete)
                }
            }

            if lineFrame(for: measure, layoutStyle: layoutStyle).insetBy(dx: 3, dy: 8).contains(location) {
                return CommittedChordBarlineHitTarget(
                    measureID: measureID,
                    action: .select
                )
            }
        }

        return nil
    }
}

enum LeadSheetCanvasInteractionTargeting {
    static func measure(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout?,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetMeasureLayout? {
        guard let pageLayout else {
            return nil
        }

        for measure in pageLayout.systems.flatMap(\.measures) {
            if measure.frame.insetBy(dx: -6, dy: -6).contains(location) {
                return measure
            }
        }

        guard layoutStyle == .simpleChordSheet else {
            return nil
        }

        for system in pageLayout.systems {
            guard let lastMeasure = system.measures.last,
                  lastMeasure.sourceMeasureID != nil else {
                continue
            }

            let displayMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                lastMeasure,
                in: system,
                paperFrame: pageLayout.paperFrame(for: system),
                layoutStyle: layoutStyle
            )
            if displayMeasure.frame.insetBy(dx: -6, dy: -6).contains(location) {
                return lastMeasure
            }
        }

        return nil
    }

    static func chordWritingBandContains(
        _ location: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> Bool {
        LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout)
            .contains { frame in
                frame.insetBy(dx: -4, dy: -4).contains(location)
            }
    }

    static func headerAuthoringContains(
        _ location: CGPoint,
        in pageLayout: LeadSheetPageLayout?
    ) -> Bool {
        guard let pageLayout else {
            return false
        }

        return pageLayout.header.handwrittenFrame
            .insetBy(dx: -12, dy: -10)
            .contains(location)
    }

    static func chordMoveTarget(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout?,
        chart: Chart? = nil
    ) -> (measureID: UUID, fraction: Double)? {
        chordMoveTarget(
            measureAnchor: location,
            fractionAnchorX: location.x,
            in: pageLayout,
            chart: chart
        )
    }

    static func chordMoveTarget(
        measureAnchor: CGPoint,
        fractionAnchorX: CGFloat,
        in pageLayout: LeadSheetPageLayout?,
        chart: Chart? = nil
    ) -> (measureID: UUID, fraction: Double)? {
        guard let target = chordMoveRawTarget(
            measureAnchor: measureAnchor,
            fractionAnchorX: fractionAnchorX,
            in: pageLayout
        ) else {
            return nil
        }

        return (
            target.measureID,
            resolvedChordMoveFraction(
                target.rawFraction,
                referenceFrame: target.referenceFrame,
                guideFrame: target.guideFrame,
                measureID: target.measureID,
                chart: chart
            )
        )
    }

    static func chordMovePositionPreview(
        measureAnchor: CGPoint,
        fractionAnchorX: CGFloat,
        in pageLayout: LeadSheetPageLayout?,
        chart: Chart,
        dragInitialX: CGFloat? = nil,
        screenPointsPerDisplayedPoint: CGFloat = 1,
        usesPhysicalMeasureBoundaries: Bool = false
    ) -> LeadSheetChordMovePositionPreview? {
        guard let target = chordMoveRawTarget(
            measureAnchor: measureAnchor,
            fractionAnchorX: fractionAnchorX,
            in: pageLayout,
            usesPhysicalMeasureBoundaries: usesPhysicalMeasureBoundaries
        ),
              let measure = chart.measure(id: target.measureID) else {
            return nil
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let resolved: (fraction: Double, activeGuideX: CGFloat?)
        if let dragInitialX {
            resolved = LeadSheetChordMovePositionGuidePolicy.resolvedDragFraction(
                rawFraction: target.rawFraction,
                initialX: dragInitialX,
                screenPointsPerDisplayedPoint: screenPointsPerDisplayedPoint,
                referenceFrame: target.referenceFrame,
                guideFrame: target.guideFrame,
                meter: meter,
                visualMovementFrame: usesPhysicalMeasureBoundaries ? target.visualMovementFrame : nil
            )
        } else {
            resolved = LeadSheetChordMovePositionGuidePolicy.resolvedFraction(
                rawFraction: target.rawFraction,
                referenceFrame: target.referenceFrame,
                guideFrame: target.guideFrame,
                meter: meter
            )
        }
        let targetX = target.referenceFrame.minX
            + target.referenceFrame.width * CGFloat(resolved.fraction)

        return LeadSheetChordMovePositionPreview(
            measureID: target.measureID,
            referenceFrame: target.referenceFrame,
            guideFrame: target.guideFrame,
            guideXs: LeadSheetChordMovePositionGuidePolicy.guideXs(
                for: meter,
                in: target.guideFrame
            ),
            activeGuideX: resolved.activeGuideX,
            targetFraction: resolved.fraction,
            targetX: targetX
        )
    }

    private static func chordMoveRawTarget(
        measureAnchor: CGPoint,
        fractionAnchorX: CGFloat,
        in pageLayout: LeadSheetPageLayout?,
        usesPhysicalMeasureBoundaries: Bool = false
    ) -> (measureID: UUID, referenceFrame: CGRect, guideFrame: CGRect, visualMovementFrame: CGRect, rawFraction: Double)? {
        guard let pageLayout else {
            return nil
        }

        for system in pageLayout.systems {
            guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame(for: system)
            ),
                  laneFrame.insetBy(dx: -8, dy: -8).contains(measureAnchor)
                    || (usesPhysicalMeasureBoundaries
                        && (laneFrame.minY - 8...laneFrame.maxY + 8).contains(measureAnchor.y)) else {
                continue
            }

            let systemMeasures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
                guard measure.sourceMeasureID != nil else {
                    return nil
                }

                return measure
            }
            let physicalTarget = usesPhysicalMeasureBoundaries
                ? (systemMeasures.last { measureAnchor.x >= $0.leadingBarlineX } ?? systemMeasures.first)
                : nil
            guard let targetMeasure = physicalTarget ?? systemMeasures.first(where: { measure in
                chordMoveLaneSegmentFrame(for: measure).contains(measureAnchor)
            }) ?? systemMeasures.min(by: { lhs, rhs in
                horizontalDistance(from: measureAnchor.x, to: chordMoveLaneSegmentFrame(for: lhs))
                    < horizontalDistance(from: measureAnchor.x, to: chordMoveLaneSegmentFrame(for: rhs))
            }),
                  let measureID = targetMeasure.sourceMeasureID else {
                return nil
            }

            let isFullWidthOpenLane = !usesPhysicalMeasureBoundaries && systemMeasures.count == 1
                && targetMeasure.isOpen
                && !chordMoveLaneSegmentFrame(for: targetMeasure).contains(measureAnchor)
            let referenceFrame = isFullWidthOpenLane ? laneFrame : targetMeasure.chordBandFrame
            let guideFrame = LeadSheetChordMovePositionGuidePolicy.guideFrame(
                for: targetMeasure,
                referenceFrame: referenceFrame
            )
            let rawFraction = (fractionAnchorX - referenceFrame.minX)
                / max(1, referenceFrame.width)
            return (
                measureID,
                referenceFrame,
                guideFrame,
                LeadSheetChordPlacementGuidePolicy.visualMovementFrame(for: targetMeasure, referenceFrame: referenceFrame),
                Double(min(max(rawFraction, 0), 0.9999))
            )
        }

        let measures = pageLayout.systems.flatMap(\.measures)
        if let targetMeasure = measures.first(where: { measure in
            measure.frame.insetBy(dx: -6, dy: -12).contains(measureAnchor)
        }),
           let measureID = targetMeasure.sourceMeasureID {
            let fraction = (fractionAnchorX - targetMeasure.chordBandFrame.minX)
                / max(1, targetMeasure.chordBandFrame.width)
            return (
                measureID,
                targetMeasure.chordBandFrame,
                LeadSheetChordMovePositionGuidePolicy.guideFrame(
                    for: targetMeasure,
                    referenceFrame: targetMeasure.chordBandFrame
                ),
                LeadSheetChordPlacementGuidePolicy.visualMovementFrame(for: targetMeasure,
                    referenceFrame: targetMeasure.chordBandFrame),
                Double(min(max(fraction, 0), 0.9999))
            )
        }

        return nil
    }

    private static func resolvedChordMoveFraction(
        _ rawFraction: Double,
        referenceFrame: CGRect,
        guideFrame: CGRect,
        measureID: UUID,
        chart: Chart?
    ) -> Double {
        guard let chart,
              let measure = chart.measure(id: measureID) else {
            return ChordEvent.clampedManualLaneFraction(rawFraction)
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        return LeadSheetChordMovePositionGuidePolicy.resolvedFraction(
            rawFraction: rawFraction,
            referenceFrame: referenceFrame,
            guideFrame: guideFrame,
            meter: meter
        ).fraction
    }

    private static func horizontalDistance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX {
            return frame.minX - x
        }
        if x > frame.maxX {
            return x - frame.maxX
        }

        return 0
    }

    private static func chordMoveLaneSegmentFrame(for measure: LeadSheetMeasureLayout) -> CGRect {
        measure.chordBandFrame.insetBy(dx: -6, dy: -8)
    }
}

#endif
