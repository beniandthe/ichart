#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

enum LeadSheetSavedInkRenderer {
    private final class RenderCacheKey: NSObject {
        private let drawingData: Data
        private let boundsX: Double
        private let boundsY: Double
        private let boundsWidth: Double
        private let boundsHeight: Double
        private let sourceCoordinateSpace: PersistentInkCoordinateSpace?
        private let targetCoordinateSpace: PersistentInkCoordinateSpace?
        private let scale: Double

        init(
            drawingData: Data,
            bounds: CGRect,
            sourceCoordinateSpace: PersistentInkCoordinateSpace?,
            targetCoordinateSpace: PersistentInkCoordinateSpace?,
            scale: CGFloat
        ) {
            self.drawingData = drawingData
            boundsX = Double(bounds.origin.x)
            boundsY = Double(bounds.origin.y)
            boundsWidth = Double(bounds.width)
            boundsHeight = Double(bounds.height)
            self.sourceCoordinateSpace = sourceCoordinateSpace
            self.targetCoordinateSpace = targetCoordinateSpace
            self.scale = Double(scale)
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(drawingData)
            hasher.combine(boundsX)
            hasher.combine(boundsY)
            hasher.combine(boundsWidth)
            hasher.combine(boundsHeight)
            hasher.combine(sourceCoordinateSpace)
            hasher.combine(targetCoordinateSpace)
            hasher.combine(scale)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? RenderCacheKey else {
                return false
            }
            return drawingData == other.drawingData
                && boundsX == other.boundsX
                && boundsY == other.boundsY
                && boundsWidth == other.boundsWidth
                && boundsHeight == other.boundsHeight
                && sourceCoordinateSpace == other.sourceCoordinateSpace
                && targetCoordinateSpace == other.targetCoordinateSpace
                && scale == other.scale
        }
    }

    private static let renderedInkImageCache: NSCache<RenderCacheKey, UIImage> = {
        let cache = NSCache<RenderCacheKey, UIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()

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
        guard let drawingData,
              !drawingData.isEmpty,
              bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        let cacheKey = RenderCacheKey(
            drawingData: drawingData,
            bounds: bounds,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace,
            scale: scale
        )
        if let cachedImage = renderedInkImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let drawing = normalizedDrawing(
            for: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace,
            targetFrame: bounds
        ) else {
            return nil
        }

        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        let renderedImage = image ?? drawing.image(from: bounds, scale: scale)
        let persistentInkImage = imageByForcingPersistentInkColor(renderedImage, scale: scale)
        renderedInkImageCache.setObject(
            persistentInkImage,
            forKey: cacheKey,
            cost: renderedImageCost(bounds: bounds, scale: scale)
        )
        return persistentInkImage
    }

    static func resetRenderedInkImageCacheForTesting() {
        renderedInkImageCache.removeAllObjects()
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

    private static func renderedImageCost(bounds: CGRect, scale: CGFloat) -> Int {
        let resolvedScale = max(1, Double(scale))
        let byteCount = Double(bounds.width)
            * Double(bounds.height)
            * resolvedScale
            * resolvedScale
            * 4
        guard byteCount.isFinite,
              byteCount > 0 else {
            return 0
        }
        return Int(min(byteCount.rounded(.up), Double(Int.max)))
    }
}
#endif
