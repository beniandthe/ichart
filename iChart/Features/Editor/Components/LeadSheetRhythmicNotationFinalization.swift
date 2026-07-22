#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

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

        let activeWritingFrame = LeadSheetRhythmicNotationInkCapturePolicy.tapFinalizeFrame(
            for: activeMeasureLayout
        )
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
            drawingFrame: analysisDrawingFrame(for: measureLayout)
        )
    }

    static func renderProposal(
        drawingData: Data,
        measure: Measure,
        defaultMeter: Meter,
        measureLayout: LeadSheetMeasureLayout
    ) throws -> RhythmicNotationMeasureProposal {
        try RhythmicNotationQuantizer.renderProposal(
            drawingData: drawingData,
            meter: measure.resolvedMeter(defaultMeter: defaultMeter),
            drawingFrame: analysisDrawingFrame(for: measureLayout)
        )
    }

    static func recognitionDecision(
        drawingData: Data,
        measure: Measure,
        defaultMeter: Meter,
        measureLayout: LeadSheetMeasureLayout
    ) throws -> RhythmRecognitionDecision {
        try RhythmicNotationQuantizer.recognitionDecision(
            drawingData: drawingData,
            meter: measure.resolvedMeter(defaultMeter: defaultMeter),
            drawingFrame: analysisDrawingFrame(for: measureLayout)
        )
    }

    static func chartByApplyingQuantizedRhythmMap(
        _ values: [RhythmValue],
        drawingData: Data,
        tieOutSlotIndices: Set<Int> = [],
        for measureID: UUID,
        measureLayout: LeadSheetMeasureLayout? = nil,
        in chart: Chart
    ) -> Chart? {
        var updatedChart = chart
        guard let measure = updatedChart.measure(id: measureID),
              RhythmicNotationCompendium.accepts(
                  values,
                  in: measure.resolvedMeter(defaultMeter: updatedChart.defaultMeter)
              ) else {
            return nil
        }

        if updatedChart.layoutStyle == .leadSheet,
           values.contains(where: \.supportsPitchedLeadSheetNote) {
            guard let measureLayout,
                  let pitchedNoteInputs = leadSheetPitchedNoteSlotInputs(
                    values: values,
                    drawingData: drawingData,
                    measureLayout: measureLayout
                  ) else {
                return nil
            }

            return updatedChart.setLeadSheetRhythmMap(
                values,
                pitchedNotes: pitchedNoteInputs,
                tieOutSlotIndices: tieOutSlotIndices,
                for: measureID
            )
                ? updatedChart
                : nil
        }

        let appliedRhythmMap = updatedChart.setMeasureRhythmMap(
            values,
            drawingData: drawingData,
            tieOutSlotIndices: tieOutSlotIndices,
            for: measureID
        )
        let clearedInk = updatedChart.clearMeasureRhythmicNotation(
            for: measureID,
            clearRhythmMap: false
        )

        return appliedRhythmMap || clearedInk ? updatedChart : nil
    }

    static func leadSheetPitchedNoteInputs(
        values: [RhythmValue],
        drawingData: Data,
        measureLayout: LeadSheetMeasureLayout
    ) -> [LeadSheetPitchedNoteInput]? {
        guard !values.isEmpty,
              values.allSatisfy(\.supportsPitchedLeadSheetNote) else {
            return nil
        }

        let drawingFrame = analysisDrawingFrame(for: measureLayout)
        guard let anchors = try? RhythmicNotationQuantizer.visualNoteAnchors(
            drawingData: drawingData,
            drawingFrame: drawingFrame
        ),
            anchors.count == values.count else {
            return nil
        }

        return zip(values, anchors).map { value, anchor in
            LeadSheetPitchedNoteInput(
                rhythmValue: value,
                staffPosition: leadSheetStaffPosition(
                    for: anchor,
                    measureLayout: measureLayout
                )
            )
        }
    }

    static func leadSheetPitchedNoteSlotInputs(
        values: [RhythmValue],
        drawingData: Data,
        measureLayout: LeadSheetMeasureLayout
    ) -> [LeadSheetPitchedNoteSlotInput]? {
        guard values.contains(where: \.supportsPitchedLeadSheetNote) else {
            return nil
        }

        let drawingFrame = analysisDrawingFrame(for: measureLayout)
        guard let anchors = try? RhythmicNotationQuantizer.visualNoteAnchors(
            drawingData: drawingData,
            drawingFrame: drawingFrame
        ) else {
            return nil
        }

        let noteSlotIndices = values.indices.filter {
            values[$0].supportsPitchedLeadSheetNote
        }
        guard anchors.count == noteSlotIndices.count else {
            return nil
        }

        return zip(noteSlotIndices, anchors).map { slotIndex, anchor in
            LeadSheetPitchedNoteSlotInput(
                rhythmSlotIndex: slotIndex,
                staffPosition: leadSheetStaffPosition(
                    for: anchor,
                    measureLayout: measureLayout
                )
            )
        }
    }

    private static func leadSheetStaffPosition(
        for anchor: RhythmVisualNoteAnchor,
        measureLayout: LeadSheetMeasureLayout
    ) -> LeadSheetStaffPosition {
        let activeFrame = LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout)
        let staffLineSpacing = max(CGFloat(1), (measureLayout.staffFrame.height - 4) / 4)
        let topStaffLineY = measureLayout.staffFrame.minY + 2 - activeFrame.minY
        let staffStep = Int(((anchor.center.y - topStaffLineY) / (staffLineSpacing / 2)).rounded())
        return LeadSheetStaffPosition(staffStep: staffStep)
    }

    private static func analysisDrawingFrame(
        for measureLayout: LeadSheetMeasureLayout
    ) -> CGRect {
        CGRect(
            origin: .zero,
            size: LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout).size
        )
    }
}
#endif
