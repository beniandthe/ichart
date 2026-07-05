#if canImport(UIKit)
import Foundation
import UIKit

struct ActiveChordMoveDrag {
    var chordID: UUID
}

enum LeadSheetCanvasInteractionTargeting {
    static func measure(
        at location: CGPoint,
        in pageLayout: LeadSheetPageLayout?
    ) -> LeadSheetMeasureLayout? {
        pageLayout?.systems
            .flatMap(\.measures)
            .first(where: { $0.frame.insetBy(dx: -6, dy: -6).contains(location) })
    }

    static func chordWritingBandContains(
        _ location: CGPoint,
        in pageLayout: LeadSheetPageLayout
    ) -> Bool {
        pageLayout.systems
            .flatMap(\.measures)
            .contains { measure in
                measure.chordWritingFrame.insetBy(dx: -4, dy: -4).contains(location)
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
        guard let pageLayout else {
            return nil
        }

        let measures = pageLayout.systems.flatMap(\.measures)
        guard let targetMeasure = measures.first(where: { measure in
            measure.frame.insetBy(dx: -6, dy: -12).contains(location)
        }),
              let measureID = targetMeasure.sourceMeasureID else {
            return nil
        }

        let fraction = (location.x - targetMeasure.chordBandFrame.minX)
            / max(1, targetMeasure.chordBandFrame.width)
        return (measureID, Double(min(max(fraction, 0), 0.9999)))
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
}

#endif
