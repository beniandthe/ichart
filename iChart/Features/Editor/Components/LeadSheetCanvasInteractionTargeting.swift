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
}

struct ActiveChordResizeDrag {
    enum Edge {
        case trailing
    }

    var chordID: UUID
    var sourcePageLayout: LeadSheetPageLayout
    var edge: Edge
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startLocation: CGPoint
}

enum LeadSheetChordMovePositionGuidePolicy {
    static let snapTolerance: CGFloat = 18
    static let leadingArtifactInset: CGFloat = 12
    static let artifactGap: CGFloat = 6

    static func guideFractions(for meter: Meter) -> [Double] {
        let beatCount = max(1, meter.numerator)
        return (0..<beatCount).map { beatIndex in
            Double(beatIndex) / Double(beatCount)
        }
    }

    static func guideXs(for meter: Meter, in referenceFrame: CGRect) -> [CGFloat] {
        guideFractions(for: meter).map { fraction in
            referenceFrame.minX + referenceFrame.width * CGFloat(fraction)
        }
    }

    static func guideFrame(
        for measure: LeadSheetMeasureLayout,
        referenceFrame: CGRect
    ) -> CGRect {
        let leadingRepeatMaxX = measure.repeatMarkerLayouts
            .filter { $0.edge == .leading }
            .map(\.frame.maxX)
            .max()
        let reservedArtifactMaxX = [
            leadingRepeatMaxX,
            measure.meterChangeFrame?.maxX
        ]
            .compactMap { $0 }
            .max()
        let artifactSafeMinX = reservedArtifactMaxX.map { $0 + artifactGap }
            ?? referenceFrame.minX
        let preferredMinX = max(
            referenceFrame.minX + leadingArtifactInset,
            artifactSafeMinX
        )
        let resolvedMinX = min(
            max(referenceFrame.minX, preferredMinX),
            max(referenceFrame.minX, referenceFrame.maxX - 1)
        )

        return CGRect(
            x: resolvedMinX,
            y: referenceFrame.minY,
            width: max(1, referenceFrame.maxX - resolvedMinX),
            height: referenceFrame.height
        )
    }

    static func resolvedFraction(
        rawFraction: Double,
        referenceFrame: CGRect,
        guideFrame: CGRect,
        meter: Meter,
        tolerance: CGFloat = snapTolerance
    ) -> (fraction: Double, activeGuideX: CGFloat?) {
        let clampedFraction = ChordEvent.clampedManualLaneFraction(rawFraction)
        let rawX = referenceFrame.minX + referenceFrame.width * CGFloat(clampedFraction)
        let guideXs = guideXs(for: meter, in: guideFrame)
        guard let closestGuideX = guideXs.min(by: { lhs, rhs in
            abs(lhs - rawX) < abs(rhs - rawX)
        }) else {
            return (clampedFraction, nil)
        }

        guard abs(closestGuideX - rawX) <= tolerance else {
            return (clampedFraction, nil)
        }

        let snappedFraction = Double(
            (closestGuideX - referenceFrame.minX)
                / max(1, referenceFrame.width)
        )
        return (
            ChordEvent.clampedManualLaneFraction(snappedFraction),
            closestGuideX
        )
    }
}

enum LeadSheetChordMoveDragPolicy {
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
        LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
            measureAnchor: location,
            fractionAnchorX: drag.currentFrame.minX,
            in: drag.sourcePageLayout,
            chart: chart
        )
    }
}

enum LeadSheetChordResizeDragPolicy {
    static func previewFrame(
        for drag: ActiveChordResizeDrag,
        at location: CGPoint,
        boundedBy movementFrame: CGRect
    ) -> CGRect {
        let minimumWidth = CGFloat(ChordEvent.minimumManualDisplayWidth)
        let maximumWidth = min(
            CGFloat(ChordEvent.maximumManualDisplayWidth),
            max(minimumWidth, movementFrame.width)
        )
        let deltaX = location.x - drag.startLocation.x

        let proposedWidth = drag.initialFrame.width + deltaX
        let availableWidth = max(minimumWidth, movementFrame.maxX - drag.initialFrame.minX)
        let resolvedWidth = min(
            maximumWidth,
            min(availableWidth, max(minimumWidth, proposedWidth))
        )
        return CGRect(
            x: drag.initialFrame.minX,
            y: drag.initialFrame.minY,
            width: resolvedWidth,
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

    static func lineFrame(for measure: LeadSheetMeasureLayout) -> CGRect {
        CGRect(
            x: measure.trailingBarlineFrame.midX - lineHitWidth / 2,
            y: measure.chordBandFrame.minY,
            width: lineHitWidth,
            height: measure.chordBandFrame.height
        )
    }

    static func controlFrames(for measure: LeadSheetMeasureLayout) -> ChordDraftBarlineControlFrames {
        let lineFrame = lineFrame(for: measure)
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
        selectedMeasureID: UUID?
    ) -> CommittedChordBarlineHitTarget? {
        for measure in measures.reversed() {
            guard let measureID = measure.sourceMeasureID else {
                continue
            }

            if selectedMeasureID == measureID {
                let controls = controlFrames(for: measure)
                if controls.delete.insetBy(dx: -deleteHitOutset, dy: -deleteHitOutset).contains(location) {
                    return CommittedChordBarlineHitTarget(measureID: measureID, action: .delete)
                }
            }

            if lineFrame(for: measure).insetBy(dx: 3, dy: 8).contains(location) {
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
                paperFrame: pageLayout.paperFrame,
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
        chart: Chart
    ) -> LeadSheetChordMovePositionPreview? {
        guard let target = chordMoveRawTarget(
            measureAnchor: measureAnchor,
            fractionAnchorX: fractionAnchorX,
            in: pageLayout
        ),
              let measure = chart.measure(id: target.measureID) else {
            return nil
        }

        let meter = measure.resolvedMeter(defaultMeter: chart.defaultMeter)
        let resolved = LeadSheetChordMovePositionGuidePolicy.resolvedFraction(
            rawFraction: target.rawFraction,
            referenceFrame: target.referenceFrame,
            guideFrame: target.guideFrame,
            meter: meter
        )
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
        in pageLayout: LeadSheetPageLayout?
    ) -> (measureID: UUID, referenceFrame: CGRect, guideFrame: CGRect, rawFraction: Double)? {
        guard let pageLayout else {
            return nil
        }

        for system in pageLayout.systems {
            guard let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame
            ),
                  laneFrame.insetBy(dx: -8, dy: -8).contains(measureAnchor) else {
                continue
            }

            let systemMeasures = system.measures.compactMap { measure -> LeadSheetMeasureLayout? in
                guard measure.sourceMeasureID != nil else {
                    return nil
                }

                return measure
            }
            guard let targetMeasure = systemMeasures.first(where: { measure in
                chordMoveLaneSegmentFrame(for: measure).contains(measureAnchor)
            }) ?? systemMeasures.min(by: { lhs, rhs in
                horizontalDistance(from: measureAnchor.x, to: chordMoveLaneSegmentFrame(for: lhs))
                    < horizontalDistance(from: measureAnchor.x, to: chordMoveLaneSegmentFrame(for: rhs))
            }),
                  let measureID = targetMeasure.sourceMeasureID else {
                return nil
            }

            let isFullWidthOpenLane = systemMeasures.count == 1
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

    static func cueTextMoveTarget(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout?,
        chart: Chart
    ) -> (measureID: UUID, fraction: Double)? {
        guard let pageLayout else {
            return nil
        }

        let verticalPadding = CGFloat(CueText.maximumVerticalOffset + 18)
        let measures = pageLayout.systems.flatMap(\.measures)
        let targetMeasure = measures
            .compactMap { measure -> (measure: LeadSheetMeasureLayout, distance: CGFloat)? in
                guard measure.frame
                    .insetBy(dx: -6, dy: -verticalPadding)
                    .contains(location) else {
                    return nil
                }

                let horizontalDistance = distance(from: location.x, to: measure.frame.minX...measure.frame.maxX)
                let verticalDistance = distance(from: location.y, to: measure.frame.minY...measure.frame.maxY)
                return (measure, horizontalDistance + verticalDistance)
            }
            .min(by: { $0.distance < $1.distance })?
            .measure

        guard let targetMeasure,
              let measureID = targetMeasure.sourceMeasureID,
              let sourceMeasure = chart.measure(id: measureID) else {
            return nil
        }

        let rawFraction = (location.x - targetMeasure.staffFrame.minX)
            / max(1, targetMeasure.staffFrame.width)
        let meter = sourceMeasure.resolvedMeter(defaultMeter: chart.defaultMeter)
        return (
            measureID,
            snappedBeatFraction(
                Double(min(max(rawFraction, 0), 0.9999)),
                meter: meter
            )
        )
    }

    private static func snappedBeatFraction(_ fraction: Double, meter: Meter) -> Double {
        MeasurePlacementGrid.snappedFraction(fraction, in: meter)
    }

    private static func distance(from value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        if value < range.lowerBound {
            return range.lowerBound - value
        }

        if value > range.upperBound {
            return value - range.upperBound
        }

        return 0
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
