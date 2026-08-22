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

enum LeadSheetSimpleChordTerminalBarlineGeometry {
    static func barlineFrame(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect? {
        guard layoutStyle == .simpleChordSheet,
              let referenceMeasure = system.measures.last,
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: paperFrame
              ) else {
            return nil
        }

        return referenceMeasure.trailingBarlineFrame.offsetBy(
            dx: laneFrame.maxX - 1 - referenceMeasure.trailingBarlineFrame.midX,
            dy: 0
        )
    }

    static func displayMeasure(
        _ measure: LeadSheetMeasureLayout,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> LeadSheetMeasureLayout {
        guard measure.isOpen,
              system.measures.last?.id == measure.id,
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return measure
        }

        let terminalX = terminalFrame.midX
        guard terminalX > measure.frame.maxX else {
            return measure
        }

        var displayMeasure = measure
        let addedWidth = terminalX - measure.frame.maxX
        displayMeasure.frame.size.width += addedWidth
        displayMeasure.staffFrame.size.width += addedWidth
        displayMeasure.chordBandFrame.size.width += addedWidth
        displayMeasure.writableFrame.size.width += addedWidth
        displayMeasure.trailingBarlineFrame = terminalFrame
        return displayMeasure
    }

    static func terminalFillerFrame(
        for system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> CGRect? {
        guard layoutStyle == .simpleChordSheet,
              system.staffLineYPositions.isEmpty,
              let referenceMeasure = system.measures.last,
              !referenceMeasure.isOpen,
              referenceMeasure.sourceMeasureID != nil,
              let laneFrame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: paperFrame
              ),
              let terminalFrame = barlineFrame(
                for: system,
                paperFrame: paperFrame,
                layoutStyle: layoutStyle
              ) else {
            return nil
        }

        let fillerStartX = max(referenceMeasure.frame.maxX, referenceMeasure.trailingBarlineFrame.midX)
        let fillerEndX = terminalFrame.midX
        guard fillerEndX > fillerStartX + 1 else {
            return nil
        }

        return CGRect(
            x: fillerStartX,
            y: laneFrame.minY,
            width: fillerEndX - fillerStartX,
            height: laneFrame.height
        )
    }

    static func containsTerminalFiller(
        _ location: CGPoint,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        terminalFillerFrame(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        )?.insetBy(dx: -4, dy: -4).contains(location) == true
    }

    static func terminalFillerContainsLaneX(
        _ laneX: CGFloat,
        in system: LeadSheetSystemLayout,
        paperFrame: CGRect,
        layoutStyle: ChartLayoutStyle
    ) -> Bool {
        guard let frame = terminalFillerFrame(
            for: system,
            paperFrame: paperFrame,
            layoutStyle: layoutStyle
        ) else {
            return false
        }

        return frame.minX < laneX && laneX < frame.maxX
    }
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

            let displayMeasures = groupedMeasures.map { measure in
                LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                    measure,
                    in: system,
                    paperFrame: pageLayout.paperFrame,
                    layoutStyle: layoutStyle
                )
            }
            let groupFrame = displayMeasures
                .dropFirst()
                .reduce(displayMeasures.first?.frame ?? firstMeasure.frame) { partialFrame, measure in
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
