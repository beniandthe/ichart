import CoreGraphics
import Foundation

/// Free Ink belongs to fixed paper coordinates. Orientation changes the
/// viewport around that paper, rather than changing the document's width.
enum LeadSheetFreeInkDocumentLayoutPolicy {
    // Match the existing portrait export layout for new documents. Saved ink
    // retains its original paper geometry instead of migrating handwritten data.
    static let portraitCanvasWidth: CGFloat = 932
    static let portraitPageHeight: CGFloat = 1_100

    static func savedCanvasWidth(for chart: Chart) -> CGFloat? {
        guard chart.pageHandwrittenNotationData?.isEmpty == false,
              let coordinateSpace = chart.pageHandwrittenNotationCoordinateSpace,
              coordinateSpace.width.isFinite,
              coordinateSpace.height.isFinite,
              coordinateSpace.width > 0,
              coordinateSpace.height > 0 else {
            return nil
        }

        return LeadSheetPageLayoutEngine.canvasWidth(
            forPageWritingWidth: CGFloat(coordinateSpace.width),
            layoutStyle: chart.layoutStyle
        )
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
