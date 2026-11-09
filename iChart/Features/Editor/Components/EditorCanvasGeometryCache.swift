import Combine
import CoreGraphics

/// Reuses document geometry across transient tool, selection and helper
/// updates. The complete chart remains the input: saved ink can retain pages,
/// and direct edits need not advance updatedAt. One entry per query is bounded
/// to this editor, with separate sizes so height and row queries do not thrash.
final class EditorCanvasGeometryCache: ObservableObject {
    private struct HeightEntry {
        let chart: Chart
        let pageSize: CGSize
        let height: CGFloat
    }

    private struct PageEntry {
        let chart: Chart
        let pageSize: CGSize
        let layout: LeadSheetPageLayout
    }

    private var heightEntry: HeightEntry?
    private var pageEntry: PageEntry?
    // Internal counters support deterministic work-reuse checks. They do not
    // publish changes or trigger another SwiftUI update.
    private(set) var canvasHeightBuildCount = 0
    private(set) var pageLayoutBuildCount = 0

    func canvasHeight(for chart: Chart, pageSize: CGSize) -> CGFloat {
        if let heightEntry, heightEntry.pageSize == pageSize, heightEntry.chart == chart {
            return heightEntry.height
        }

        let height: CGFloat
        if !chart.hasCompletedInitialSetup {
            height = max(760, pageSize.height)
        } else {
            let visibleSystemCount = LeadSheetPageLayoutEngine.estimatedSystemCount(
                for: chart, pageWidth: pageSize.width)
            let estimatedCanvasHeight = LeadSheetPageLayoutEngine.estimatedCanvasHeight(
                for: chart, pageSize: pageSize)
            height = max(pageSize.height, 1_200, estimatedCanvasHeight,
                CGFloat(visibleSystemCount) * 168 + 320)
        }

        canvasHeightBuildCount += 1
        heightEntry = HeightEntry(chart: chart, pageSize: pageSize, height: height)
        return height
    }

    func pageLayout(for chart: Chart, pageSize: CGSize) -> LeadSheetPageLayout {
        if let pageEntry, pageEntry.pageSize == pageSize, pageEntry.chart == chart {
            return pageEntry.layout
        }

        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        pageLayoutBuildCount += 1
        pageEntry = PageEntry(chart: chart, pageSize: pageSize, layout: layout)
        return layout
    }
}
