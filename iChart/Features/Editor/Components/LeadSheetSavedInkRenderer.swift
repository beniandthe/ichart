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

    static func renderedInkImage(
        _ drawingData: Data?,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        renderedInkImage(
            drawingData,
            in: CGRect(origin: .zero, size: size),
            scale: scale
        )
    }

    static func renderedInkImage(
        _ drawingData: Data?,
        in bounds: CGRect,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard let drawing = normalizedDrawing(for: drawingData),
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        return image ?? drawing.image(from: bounds, scale: scale)
    }

    private static func drawInk(_ drawingData: Data?, in frame: CGRect) {
        guard let image = renderedInkImage(drawingData, size: frame.size) else {
            return
        }

        image.draw(in: frame)
    }

    private static func normalizedDrawing(for drawingData: Data?) -> PKDrawing? {
        guard let drawingData,
              let savedDrawing = try? PKDrawing(data: drawingData) else {
            return nil
        }

        let drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(savedDrawing)
        return drawing.strokes.isEmpty ? nil : drawing
    }
}
#endif
