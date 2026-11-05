import CoreGraphics
import Foundation
#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
#endif

/// Free Ink belongs to fixed paper coordinates. Orientation changes the
/// viewport around that paper, rather than changing the document's width.
enum LeadSheetFreeInkDocumentLayoutPolicy {
    // Match the existing portrait export layout for new documents. Saved ink
    // retains its original paper geometry instead of migrating handwritten data.
    static let portraitCanvasWidth: CGFloat = 932
    static let portraitPageHeight: CGFloat = 1_100

    #if canImport(UIKit) && canImport(PencilKit)
    private static let pageInkBoundsCache: NSCache<NSData, NSValue> = {
        let cache = NSCache<NSData, NSValue>()
        cache.countLimit = 16
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    #endif

    static func savedPageInkBounds(for chart: Chart) -> CGRect? {
        #if canImport(UIKit) && canImport(PencilKit)
        guard let data = chart.pageHandwrittenNotationData, !data.isEmpty else { return nil }
        let key = data as NSData
        if let cached = pageInkBoundsCache.object(forKey: key) {
            return cached.cgRectValue.isNull ? nil : cached.cgRectValue
        }
        let bounds = (try? PKDrawing(data: data))?.bounds ?? .null
        pageInkBoundsCache.setObject(NSValue(cgRect: bounds), forKey: key, cost: data.count)
        return bounds.isNull ? nil : bounds
        #else
        return nil
        #endif
    }

    static func savedCanvasWidth(for chart: Chart) -> CGFloat? {
        guard let coordinateSpace = savedPageCoordinateSpace(for: chart) else { return nil }
        return LeadSheetPageLayoutEngine.canvasWidth(
            forPageWritingWidth: CGFloat(coordinateSpace.width),
            layoutStyle: chart.layoutStyle
        )
    }

    static func savedPageCoordinateSpace(for chart: Chart) -> PersistentInkCoordinateSpace? {
        if chart.pageHandwrittenNotationData?.isEmpty == false {
            return validPageCoordinateSpace(chart.pageHandwrittenNotationCoordinateSpace)
        }
        // A conversion can consume the final visible stroke. Its archived
        // drawing still records the width of the document it was authored on.
        return chart.freeInkArticulations.reversed().lazy.compactMap {
            validPageCoordinateSpace($0.sourceCoordinateSpace)
        }.first
    }

    private static func validPageCoordinateSpace(
        _ coordinateSpace: PersistentInkCoordinateSpace?
    ) -> PersistentInkCoordinateSpace? {
        guard let coordinateSpace,
              coordinateSpace.width.isFinite, coordinateSpace.height.isFinite,
              coordinateSpace.width > 0, coordinateSpace.height > 0 else { return nil }
        return coordinateSpace
    }

    static func canvasWidthToRetain(for chart: Chart, viewportWidth _: CGFloat) -> CGFloat {
        savedCanvasWidth(for: chart)
            ?? portraitCanvasWidth
    }

    static func resolvedCanvasWidth(
        retainedWidth: CGFloat?,
        chart: Chart,
        viewportWidth _: CGFloat
    ) -> CGFloat {
        if let retainedWidth, retainedWidth.isFinite, retainedWidth > 0 {
            return retainedWidth
        }
        if let savedWidth = savedCanvasWidth(for: chart) {
            return savedWidth
        }
        return portraitCanvasWidth
    }
}
