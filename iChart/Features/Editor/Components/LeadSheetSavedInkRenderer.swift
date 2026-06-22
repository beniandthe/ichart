#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

enum LeadSheetSavedInkRenderer {
    static func drawPageInk(_ drawingData: Data?, in pageLayout: LeadSheetPageLayout) {
        drawInk(
            drawingData,
            in: LeadSheetActiveInkScope.pageWritingFrame(for: pageLayout)
        )
    }

    static func drawHeaderInk(_ drawingData: Data?, in pageLayout: LeadSheetPageLayout) {
        drawInk(
            drawingData,
            in: pageLayout.header.handwrittenFrame
        )
    }

    static func drawChordInk(_ drawingData: Data?, in pageLayout: LeadSheetPageLayout) {
        drawInk(
            drawingData,
            in: LeadSheetActiveInkScope.chordWritingFrame(for: pageLayout)
        )
    }

    static func drawRhythmicNotationInk(_ drawingData: Data?, in measureLayout: LeadSheetMeasureLayout) {
        drawInk(
            drawingData,
            in: LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(for: measureLayout)
        )
    }

    static func drawFreehandSymbols(_ symbolLayouts: [LeadSheetFreehandSymbolLayout]) {
        for symbolLayout in symbolLayouts {
            drawInk(symbolLayout.symbol.drawingData, in: symbolLayout.frame)
        }
    }

    private static func drawInk(_ drawingData: Data?, in frame: CGRect) {
        guard let drawingData,
              let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty else {
            return
        }

        let image = drawing.image(
            from: CGRect(origin: .zero, size: frame.size),
            scale: UIScreen.main.scale
        )
        image.draw(in: frame)
    }
}
#endif
