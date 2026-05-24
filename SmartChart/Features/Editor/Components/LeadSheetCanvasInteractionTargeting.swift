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
                measure.chordBandFrame.insetBy(dx: -3, dy: -3).contains(location)
            }
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
}
#endif
