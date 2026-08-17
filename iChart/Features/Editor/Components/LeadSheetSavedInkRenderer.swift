#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

enum LeadSheetSavedInkRenderer {
    static func drawPageInk(
        _ drawingData: Data?,
        coordinateSpace: PersistentInkCoordinateSpace? = nil,
        chart: Chart? = nil,
        in pageLayout: LeadSheetPageLayout
    ) {
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: pageLayout)
        drawInk(
            drawingData,
            sourceCoordinateSpace: chart.map {
                LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
                    coordinateSpace,
                    chart: $0
                )
            } ?? coordinateSpace,
            targetCoordinateSpace: LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: pageLayout,
                relativeTo: frame
            ),
            in: frame
        )
    }

    static func drawHeaderInk(
        _ drawingData: Data?,
        coordinateSpace: PersistentInkCoordinateSpace? = nil,
        in pageLayout: LeadSheetPageLayout
    ) {
        drawInk(
            drawingData,
            sourceCoordinateSpace: coordinateSpace,
            in: pageLayout.header.handwrittenFrame
        )
    }

    static func drawChordInk(
        _ drawingData: Data?,
        coordinateSpace: PersistentInkCoordinateSpace? = nil,
        in pageLayout: LeadSheetPageLayout
    ) {
        drawInk(
            drawingData,
            sourceCoordinateSpace: coordinateSpace,
            in: LeadSheetActiveInkScope.chordWritingFrame(for: pageLayout)
        )
    }

    static func drawRhythmicNotationInk(
        _ drawingData: Data?,
        coordinateSpace: PersistentInkCoordinateSpace? = nil,
        in measureLayout: LeadSheetMeasureLayout
    ) {
        drawInk(
            drawingData,
            sourceCoordinateSpace: coordinateSpace,
            in: LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(for: measureLayout)
        )
    }

    static func renderedInkImage(
        _ drawingData: Data?,
        size: CGSize,
        sourceCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        targetCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        renderedInkImage(
            drawingData,
            in: CGRect(origin: .zero, size: size),
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace,
            scale: scale
        )
    }

    static func renderedInkImage(
        _ drawingData: Data?,
        in bounds: CGRect,
        sourceCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        targetCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard let drawing = normalizedDrawing(
            for: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace,
            targetFrame: bounds
        ),
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        let renderedImage = image ?? drawing.image(from: bounds, scale: scale)
        return imageByForcingPersistentInkColor(renderedImage, scale: scale)
    }

    static func imageByForcingPersistentInkColor(
        _ image: UIImage,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage {
        let imageBounds = CGRect(origin: .zero, size: image.size)
        guard imageBounds.width > 0,
              imageBounds.height > 0 else {
            return image
        }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale > 0 ? scale : image.scale
        rendererFormat.opaque = false

        return UIGraphicsImageRenderer(size: image.size, format: rendererFormat).image { _ in
            LeadSheetPersistentInkColorPolicy.inkColor.setFill()
            UIBezierPath(rect: imageBounds).fill()
            image.draw(in: imageBounds, blendMode: .destinationIn, alpha: 1)
        }
    }

    private static func drawInk(
        _ drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        in frame: CGRect
    ) {
        guard let image = renderedInkImage(
            drawingData,
            size: frame.size,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        ) else {
            return
        }

        image.draw(in: frame)
    }

    private static func normalizedDrawing(
        for drawingData: Data?,
        sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        targetCoordinateSpace: PersistentInkCoordinateSpace? = nil,
        targetFrame: CGRect
    ) -> PKDrawing? {
        guard let drawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
                ?? LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(for: targetFrame)
        ) else {
            return nil
        }
        return drawing.strokes.isEmpty ? nil : drawing
    }
}
#endif
