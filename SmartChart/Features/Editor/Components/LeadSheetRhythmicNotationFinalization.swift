#if canImport(UIKit)
import CoreGraphics
import Foundation

enum LeadSheetRhythmicNotationFinalization {
    static func shouldFinalizeSelectionChange(
        interactionMode: EditorCanvasMode,
        isRestoringSelection: Bool,
        isApplyingTapSelection: Bool,
        previousMeasureID: UUID?,
        nextMeasureID: UUID?
    ) -> Bool {
        interactionMode.allowsDirectRhythmicNotationInk
            && !isRestoringSelection
            && !isApplyingTapSelection
            && previousMeasureID != nil
            && previousMeasureID != nextMeasureID
    }

    static func shouldFinalizeTap(
        interactionMode: EditorCanvasMode,
        selectedMeasureID: UUID?,
        activeMeasureLayout: LeadSheetMeasureLayout?,
        location: CGPoint,
        nextMeasureID: UUID?
    ) -> Bool {
        guard interactionMode.allowsDirectRhythmicNotationInk,
              let activeMeasureID = selectedMeasureID,
              let activeMeasureLayout else {
            return false
        }

        if nextMeasureID != activeMeasureID {
            return true
        }

        let activeWritingFrame = activeMeasureLayout.writableFrame.insetBy(dx: -8, dy: -8)
        return !activeWritingFrame.contains(location)
    }

    static func chartByPersistingLiveDrawing(
        _ liveDrawingData: Data?,
        for measureID: UUID,
        in chart: Chart
    ) -> Chart? {
        var updatedChart = chart
        guard updatedChart.setMeasureHandwrittenRhythmicNotationDrawing(liveDrawingData, for: measureID) else {
            return nil
        }

        return updatedChart
    }

    static func quantize(
        drawingData: Data,
        measure: Measure,
        defaultMeter: Meter,
        measureLayout: LeadSheetMeasureLayout
    ) throws -> [RhythmValue] {
        try RhythmicNotationQuantizer.quantize(
            drawingData: drawingData,
            meter: measure.resolvedMeter(defaultMeter: defaultMeter),
            drawingFrame: CGRect(
                origin: .zero,
                size: measureLayout.writableFrame.insetBy(dx: 2, dy: 2).size
            )
        )
    }

    static func chartByApplyingQuantizedRhythmMap(
        _ values: [RhythmValue],
        drawingData: Data,
        for measureID: UUID,
        in chart: Chart
    ) -> Chart? {
        var updatedChart = chart
        let appliedRhythmMap = updatedChart.setMeasureRhythmMap(
            values,
            drawingData: drawingData,
            for: measureID
        )
        let clearedInk = updatedChart.clearMeasureRhythmicNotation(
            for: measureID,
            clearRhythmMap: false
        )

        return appliedRhythmMap || clearedInk ? updatedChart : nil
    }
}
#endif
