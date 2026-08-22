#if canImport(UIKit)
import Foundation
import UIKit

struct ActiveChordMoveDrag {
    var chordID: UUID
    var sourcePageLayout: LeadSheetPageLayout
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startLocation: CGPoint
}

struct ActiveChordResizeDrag {
    enum Edge {
        case leading
        case trailing
    }

    var chordID: UUID
    var sourcePageLayout: LeadSheetPageLayout
    var edge: Edge
    var initialFrame: CGRect
    var currentFrame: CGRect
    var startLocation: CGPoint
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
        for drag: ActiveChordMoveDrag
    ) -> (measureID: UUID, fraction: Double)? {
        let locationTarget = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
            measureAnchor: location,
            fractionAnchorX: drag.currentFrame.minX,
            in: drag.sourcePageLayout
        )
        let frameMeasureAnchor = CGPoint(
            x: drag.currentFrame.midX,
            y: drag.currentFrame.midY
        )
        let frameTarget = LeadSheetCanvasInteractionTargeting.chordMoveTarget(
            measureAnchor: frameMeasureAnchor,
            fractionAnchorX: drag.currentFrame.minX,
            in: drag.sourcePageLayout
        )

        if drag.currentFrame == drag.initialFrame {
            return LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                at: location,
                in: drag.sourcePageLayout
            ) ?? frameTarget
        }

        return locationTarget ?? frameTarget
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

        switch drag.edge {
        case .leading:
            let proposedMinX = drag.initialFrame.minX + deltaX
            let resolvedMinX = min(
                max(proposedMinX, movementFrame.minX),
                drag.initialFrame.maxX - minimumWidth
            )
            let resolvedWidth = min(
                maximumWidth,
                max(minimumWidth, drag.initialFrame.maxX - resolvedMinX)
            )
            return CGRect(
                x: drag.initialFrame.maxX - resolvedWidth,
                y: drag.initialFrame.minY,
                width: resolvedWidth,
                height: drag.initialFrame.height
            )

        case .trailing:
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

    static func leadingTarget(
        for drag: ActiveChordResizeDrag
    ) -> (measureID: UUID, fraction: Double)? {
        LeadSheetCanvasInteractionTargeting.chordMoveTarget(
            at: CGPoint(x: drag.currentFrame.minX, y: drag.currentFrame.midY),
            in: drag.sourcePageLayout
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
        in pageLayout: LeadSheetPageLayout?
    ) -> (measureID: UUID, fraction: Double)? {
        chordMoveTarget(
            measureAnchor: location,
            fractionAnchorX: location.x,
            in: pageLayout
        )
    }

    static func chordMoveTarget(
        measureAnchor: CGPoint,
        fractionAnchorX: CGFloat,
        in pageLayout: LeadSheetPageLayout?
    ) -> (measureID: UUID, fraction: Double)? {
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
            let rawFraction = (fractionAnchorX - referenceFrame.minX)
                / max(1, referenceFrame.width)
            return (measureID, Double(min(max(rawFraction, 0), 0.9999)))
        }

        let measures = pageLayout.systems.flatMap(\.measures)
        if let targetMeasure = measures.first(where: { measure in
            measure.frame.insetBy(dx: -6, dy: -12).contains(measureAnchor)
        }),
           let measureID = targetMeasure.sourceMeasureID {
            let fraction = (fractionAnchorX - targetMeasure.chordBandFrame.minX)
                / max(1, targetMeasure.chordBandFrame.width)
            return (measureID, Double(min(max(fraction, 0), 0.9999)))
        }

        return nil
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
