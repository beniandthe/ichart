#if canImport(UIKit)
import CoreGraphics
import Foundation

/// A measure-snapped gesture is a value transaction. Preview never writes to
/// the source chart, and commit accepts only the exact chart captured at begin.
struct LeadSheetEndingDragSession {
    let sourceChart: Chart
    let sourcePageLayout: LeadSheetPageLayout
    let endingObject: RoadmapObject
    /// Zero-based inclusive measure ordinals in sourceChart.measures.
    let initialRange: ClosedRange<Int>
    let sourceSystemIndex: Int
    let action: RenderedEditAction

    private struct MeasureTarget {
        let index: Int
        let frame: CGRect
    }

    private struct RowTarget {
        let systemIndex: Int
        let frame: CGRect
        let measures: [MeasureTarget]
    }

    private let rows: [RowTarget]
    private let startProgress: Double
    private let verticalGrabOffset: CGFloat
    private let trailingHandleGrabOffset: CGFloat

    init?(
        chart: Chart, endingID: UUID, action: RenderedEditAction,
        startLocation: CGPoint, sourcePageLayout: LeadSheetPageLayout,
        sourceSystemIndex: Int? = nil
    ) {
        guard action == .move || action == .resizeTrailing,
              Self.isFinite(startLocation),
              let ending = chart.roadmapObject(id: endingID), ending.type.isEnding else { return nil }
        let ids = chart.measures.map(\.id)
        guard !ids.isEmpty, Set(ids).count == ids.count,
              let start = ids.firstIndex(of: ending.startMeasureID),
              let end = ids.firstIndex(of: ending.endMeasureID ?? ending.startMeasureID), start <= end else { return nil }
        let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var represented = Set<UUID>()
        var rows: [RowTarget] = []
        for system in sourcePageLayout.systems {
            var measures: [MeasureTarget] = []
            for measure in system.measures {
                guard let id = measure.sourceMeasureID, let index = positions[id] else { continue }
                guard represented.insert(id).inserted, Self.isFiniteNonempty(measure.staffFrame) else { return nil }
                measures.append(MeasureTarget(index: index, frame: measure.staffFrame))
            }
            guard !measures.isEmpty else { continue }
            guard Self.isFiniteNonempty(system.frame) else { return nil }
            rows.append(RowTarget(systemIndex: system.index, frame: system.frame,
                measures: measures.sorted { $0.index < $1.index }))
        }
        guard represented == Set(ids), !rows.isEmpty else { return nil }
        rows.sort { $0.measures[0].index < $1.measures[0].index }
        let eligibleRows = rows.filter { row in row.measures.contains { (start...end).contains($0.index) } }
        let initialRow: RowTarget?
        if let sourceSystemIndex {
            initialRow = eligibleRows.first { $0.systemIndex == sourceSystemIndex }
        } else if action == .resizeTrailing {
            initialRow = eligibleRows.first { $0.measures.contains { $0.index == end } }
        } else {
            initialRow = eligibleRows.min { lhs, rhs in
                Self.verticalDistance(from: startLocation.y, to: lhs.frame)
                    < Self.verticalDistance(from: startLocation.y, to: rhs.frame)
            }
        }
        guard let initialRow,
              let initialProgress = Self.progress(atX: startLocation.x, in: initialRow) else { return nil }
        let trailingOffset: CGFloat
        if action == .resizeTrailing {
            guard let endMeasure = initialRow.measures.first(where: { $0.index == end }) else { return nil }
            trailingOffset = startLocation.x - endMeasure.frame.maxX
        } else {
            trailingOffset = 0
        }
        self.sourceChart = chart
        self.sourcePageLayout = sourcePageLayout
        endingObject = ending
        initialRange = start...end
        self.sourceSystemIndex = initialRow.systemIndex
        self.action = action
        self.rows = rows
        startProgress = initialProgress
        verticalGrabOffset = startLocation.y - initialRow.frame.midY
        trailingHandleGrabOffset = trailingOffset
    }

    /// Zero-based inclusive measure ordinals. Moving preserves the original
    /// measure count; Length changes only the right endpoint and retains one
    /// measure at minimum. Synthetic writing lanes never become targets.
    func previewRange(at location: CGPoint) -> ClosedRange<Int>? {
        guard Self.isFinite(location) else { return nil }
        let adjustedY = location.y - verticalGrabOffset
        guard adjustedY.isFinite,
              let row = rows.min(by: {
                  Self.verticalDistance(from: adjustedY, to: $0.frame)
                      < Self.verticalDistance(from: adjustedY, to: $1.frame)
              }) else { return nil }
        let x = action == .resizeTrailing ? location.x - trailingHandleGrabOffset : location.x
        guard let progress = Self.progress(atX: x, in: row) else { return nil }
        switch action {
        case .move:
            let proposedStart = Double(initialRange.lowerBound) + (progress - startProgress)
            guard proposedStart.isFinite else { return nil }
            let count = initialRange.count
            let maximumStart = sourceChart.measures.count - count
            let start = Int(min(max(proposedStart, 0), Double(maximumStart)).rounded())
            return start...(start + count - 1)
        case .resizeTrailing:
            let minimumBoundary = initialRange.lowerBound + 1
            let boundary = Int(min(max(progress, Double(minimumBoundary)),
                Double(sourceChart.measures.count)).rounded())
            return initialRange.lowerBound...(boundary - 1)
        default:
            return nil
        }
    }

    /// A no-op preview is the exact original value, including legacy nil
    /// fields, timestamps, and original ink archive bytes.
    func previewChart(at location: CGPoint) -> Chart? {
        guard let range = previewRange(at: location) else { return nil }
        guard range != initialRange else { return sourceChart }
        var preview = sourceChart
        let ids = sourceChart.measures.map(\.id)
        guard preview.updateEndingSpan(endingObject.id,
            startMeasureID: ids[range.lowerBound], endMeasureID: ids[range.upperBound]) else { return nil }
        return preview
    }

    /// Nil means a cancelled/rejected/no-op transaction; the caller must make
    /// no chart writeback. Every other field is retained from the live chart.
    func committedChart(at location: CGPoint, currentChart: Chart) -> Chart? {
        guard currentChart == sourceChart,
              let range = previewRange(at: location), range != initialRange else { return nil }
        var committed = currentChart
        let ids = currentChart.measures.map(\.id)
        guard committed.updateEndingSpan(endingObject.id,
            startMeasureID: ids[range.lowerBound], endMeasureID: ids[range.upperBound]) else { return nil }
        return committed
    }

    private static func progress(atX x: CGFloat, in row: RowTarget) -> Double? {
        guard x.isFinite, let first = row.measures.first, let last = row.measures.last else { return nil }
        let result: Double
        if x < first.frame.minX {
            result = Double(first.index) + Double((x - first.frame.minX) / first.frame.width)
        } else if x > last.frame.maxX {
            result = Double(last.index + 1) + Double((x - last.frame.maxX) / last.frame.width)
        } else if let measure = row.measures.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) {
            result = Double(measure.index) + Double((x - measure.frame.minX) / measure.frame.width)
        } else {
            // Signature and spacing gaps lie on an existing boundary. They
            // must not invent a fractional or additional measure.
            guard let following = row.measures.first(where: { x < $0.frame.minX }) else { return nil }
            result = Double(following.index)
        }
        return result.isFinite ? result : nil
    }

    private static func verticalDistance(from y: CGFloat, to frame: CGRect) -> CGFloat {
        max(frame.minY - y, y - frame.maxY, 0)
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func isFiniteNonempty(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && [frame.minX, frame.maxX, frame.minY, frame.maxY].allSatisfy(\.isFinite)
    }
}
#endif
