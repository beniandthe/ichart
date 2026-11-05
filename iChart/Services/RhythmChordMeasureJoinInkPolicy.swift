import CoreGraphics
import Foundation
#if canImport(PencilKit)
import PencilKit
#endif

/// A chord-only merge cannot retain two independent staff-ink registration
/// frames inside the resulting single measure. Leave that boundary in place
/// whenever the archived page ink could depend on either frame.
enum RhythmChordMeasureJoinInkPolicy {
    #if canImport(PencilKit)
    private final class Bounds: NSObject {
        let frames: [CGRect]?
        init(_ frames: [CGRect]?) { self.frames = frames }
    }

    private static let boundsCache: NSCache<NSData, Bounds> = {
        let cache = NSCache<NSData, Bounds>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
    #endif

    static func preventsJoin(
        drawingData: Data?, sourceCoordinateSpace: PersistentInkCoordinateSpace?,
        measureIDs: Set<UUID>
    ) -> Bool {
        guard let drawingData, !drawingData.isEmpty else { return false }
        #if canImport(PencilKit)
        let key = drawingData as NSData
        let stored: Bounds
        if let cached = boundsCache.object(forKey: key) {
            stored = cached
        } else {
            stored = Bounds((try? PKDrawing(data: drawingData))?.strokes.map(\.renderBounds))
            boundsCache.setObject(stored, forKey: key, cost: drawingData.count)
        }
        guard let frames = stored.frames else { return true }
        guard !frames.isEmpty else { return false }
        guard let anchors = sourceCoordinateSpace?.measureAnchors else { return true }
        let affected = anchors.filter { measureIDs.contains($0.measureID) }
        guard Set(affected.map(\.measureID)) == measureIDs,
              affected.count == measureIDs.count,
              affected.allSatisfy({ $0.staffFrame != nil }) else { return true }
        let staffAnchors = anchors.filter { $0.staffFrame != nil }
        let leftEdge = min(0, frames.map(\.minX).min() ?? 0) - 1
        let rightEdge = max(CGFloat(sourceCoordinateSpace?.width ?? 0), frames.map(\.maxX).max() ?? 0) + 1
        return affected.contains { anchor in
            guard let staff = anchor.staffFrame?.rect else { return true }
            let row = staffAnchors.filter { abs(($0.staffFrame?.rect.minY ?? .infinity) - staff.minY) < 0.01 }
                .sorted { $0.staffFrame!.rect.minX < $1.staffFrame!.rect.minX }
            guard let index = row.firstIndex(where: { $0.measureID == anchor.measureID }) else { return true }
            // The engraving projector assigns margin/ledger ink to its nearest
            // measure too. Include that ownership region, not just the staff's
            // interior rectangle, so a mark just outside the first bar cannot
            // lose its future registration when the boundary disappears.
            let minX = index > 0 ? (row[index - 1].staffFrame!.rect.maxX + staff.minX) / 2 : leftEdge
            let maxX = index + 1 < row.count ? (staff.maxX + row[index + 1].staffFrame!.rect.minX) / 2 : rightEdge
            let top = row.map { $0.frame.rect.minY }.min() ?? staff.minY
            let nextTop = staffAnchors.filter { $0.staffFrame!.rect.minY > staff.minY + 0.01 }
                .map { $0.frame.rect.minY }.min()
            let bottom = nextTop ?? staff.maxY + max(80, staff.height * 2)
            let region = CGRect(x: minX, y: top,
                width: max(1, maxX - minX), height: max(1, bottom - top)).insetBy(dx: -1, dy: -1)
            return frames.contains { $0.intersects(region) }
        }
        #else
        // Without a drawing decoder, nonempty source is not evidence that the
        // affected frames are unused. Keep the operation non-destructive.
        return true
        #endif
    }
}
