#if canImport(UIKit)
import Foundation
import UIKit

struct ActiveMeasureResizeDrag {
    enum Edge {
        case left
        case right
    }

    var measureID: UUID
    var edge: Edge
    var initialWidth: CGFloat
}

struct LeadSheetMeasureResizeHandleFrames {
    let left: CGRect
    let right: CGRect
}

struct LeadSheetSimpleRowGroupAffordance {
    var selectedMeasureID: UUID
    var groupedMeasureIDs: [UUID]
    var groupFrame: CGRect
    var guideY: CGFloat
}

enum LeadSheetMeasureResizeGeometry {
    static func handleFrames(for measure: LeadSheetMeasureLayout) -> LeadSheetMeasureResizeHandleFrames {
        let handleSize = CGSize(width: 18, height: 34)
        let handleY = measure.staffFrame.midY - handleSize.height / 2
        return LeadSheetMeasureResizeHandleFrames(
            left: CGRect(
                x: measure.frame.minX - handleSize.width / 2,
                y: handleY,
                width: handleSize.width,
                height: handleSize.height
            ),
            right: CGRect(
                x: measure.frame.maxX - handleSize.width / 2,
                y: handleY,
                width: handleSize.width,
                height: handleSize.height
            )
        )
    }

    static func hitTarget(at location: CGPoint, in measure: LeadSheetMeasureLayout) -> ActiveMeasureResizeDrag? {
        guard let measureID = measure.sourceMeasureID else {
            return nil
        }

        let handleFrames = handleFrames(for: measure)
        let touchInsetX: CGFloat = -12
        let touchInsetY: CGFloat = -10

        if handleFrames.left.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .left,
                initialWidth: measure.frame.width
            )
        }

        if handleFrames.right.insetBy(dx: touchInsetX, dy: touchInsetY).contains(location) {
            return ActiveMeasureResizeDrag(
                measureID: measureID,
                edge: .right,
                initialWidth: measure.frame.width
            )
        }

        return nil
    }
}

enum LeadSheetSimpleRowGroupAffordanceGeometry {
    static func affordance(
        for selectedMeasureID: UUID?,
        in pageLayout: LeadSheetPageLayout?,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetSimpleRowGroupAffordance? {
        guard layoutStyle == .simpleChordSheet,
              let selectedMeasureID,
              let pageLayout else {
            return nil
        }

        for system in pageLayout.systems {
            guard let selectedIndex = system.measures.firstIndex(where: { measure in
                measure.sourceMeasureID == selectedMeasureID
            }) else {
                continue
            }

            let groupedMeasures = system.measures[selectedIndex...]
                .filter { $0.sourceMeasureID != nil }
            guard let firstMeasure = groupedMeasures.first else {
                return nil
            }

            let groupFrame = groupedMeasures
                .dropFirst()
                .reduce(firstMeasure.frame) { partialFrame, measure in
                    partialFrame.union(measure.frame)
                }
            let guideY = max(system.frame.minY + 10, groupFrame.minY - 11)

            return LeadSheetSimpleRowGroupAffordance(
                selectedMeasureID: selectedMeasureID,
                groupedMeasureIDs: groupedMeasures.compactMap(\.sourceMeasureID),
                groupFrame: groupFrame,
                guideY: guideY
            )
        }

        return nil
    }
}
#endif
