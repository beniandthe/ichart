#if canImport(UIKit)
import CoreGraphics
import Foundation

/// Geometry-only structural recognition. A complete bar/dot group owns its
/// original input indices before ordinary barline deduplication or chord targeting.
/// These thresholds are conservative shape gates, not recognition confidence.
enum ChordDraftRepeatSignRecognizer {
    private struct Bar {
        let index: Int
        let stroke: InkStroke
        let draft: DraftBarline

        var centerX: Double { (stroke.bounds.minX + stroke.bounds.maxX) / 2 }
        var centerY: Double { (stroke.bounds.minY + stroke.bounds.maxY) / 2 }
    }

    private struct Dot {
        let index: Int
        let bounds: InkBounds
        var centerX: Double { (bounds.minX + bounds.maxX) / 2 }
        var centerY: Double { (bounds.minY + bounds.maxY) / 2 }
    }

    static func recognize(
        strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> ChordDraftBarlineRecognition {
        guard let pageLayout,
              chordFrame.minX.isFinite, chordFrame.minY.isFinite else {
            return ChordDraftBarlineRecognition(barlines: [], strokeIndices: [])
        }
        let bars = strokes.enumerated().compactMap { index, stroke -> Bar? in
            guard hasFiniteGeometry(stroke),
                  let draft = ChordDraftBarlineRecognizer.candidate(
                    for: stroke, chordFrame: chordFrame, pageLayout: pageLayout
                  ) else { return nil }
            return Bar(index: index, stroke: stroke, draft: draft)
        }
        let groups = barGroups(bars)
        let candidates = groups.compactMap { group in
            repeatSign(group: group, strokes: strokes, chordFrame: chordFrame, pageLayout: pageLayout)
        }
        // Two distinct signs cannot both consume the same dot/stroke. Retain
        // neither claim when their ownership overlaps, rather than picking one.
        let claimCounts = candidates.reduce(into: [Int: Int]()) { counts, candidate in
            for index in candidate.ownedSourceStrokeIndices { counts[index, default: 0] += 1 }
        }
        let accepted = candidates.filter { candidate in
            candidate.ownedSourceStrokeIndices.allSatisfy { claimCounts[$0] == 1 }
        }.sorted { $0.visualOrder < $1.visualOrder }
        return ChordDraftBarlineRecognition(
            barlines: accepted,
            strokeIndices: accepted.reduce(into: Set<Int>()) { $0.formUnion($1.ownedSourceStrokeIndices) }
        )
    }

    private static func barGroups(_ bars: [Bar]) -> [[Bar]] {
        var remaining = bars.sorted { $0.centerX < $1.centerX }
        var groups: [[Bar]] = []
        while !remaining.isEmpty {
            var group = [remaining.removeFirst()]
            var foundNeighbor = true
            while foundNeighbor {
                foundNeighbor = false
                for index in remaining.indices.reversed() {
                    let next = remaining[index]
                    if group.contains(where: { bar in
                        guard bar.draft.laneLocation?.systemIndex == next.draft.laneLocation?.systemIndex else { return false }
                        let height = max(bar.stroke.bounds.height, next.stroke.bounds.height)
                        let overlap = min(bar.stroke.bounds.maxY, next.stroke.bounds.maxY)
                            - max(bar.stroke.bounds.minY, next.stroke.bounds.minY)
                        return abs(bar.centerX - next.centerX) <= max(8, height * 0.22)
                            && overlap >= min(bar.stroke.bounds.height, next.stroke.bounds.height) * 0.65
                    }) {
                        group.append(remaining.remove(at: index))
                        foundNeighbor = true
                    }
                }
            }
            groups.append(group.sorted { $0.centerX < $1.centerX })
        }
        return groups
    }

    private static func repeatSign(
        group: [Bar],
        strokes: [InkStroke],
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout
    ) -> DraftBarline? {
        guard (1...2).contains(group.count), let anchor = group.first else { return nil }
        let bounds = InkBounds.enclosing(group.map { $0.stroke.bounds })
        let height = bounds.height
        guard height > 0 else { return nil }
        if group.count == 2 {
            let first = group[0], second = group[1]
            let overlap = min(first.stroke.bounds.maxY, second.stroke.bounds.maxY)
                - max(first.stroke.bounds.minY, second.stroke.bounds.minY)
            let separation = second.centerX - first.centerX
            guard separation >= max(1.5, height * 0.02),
                  separation <= height * 0.22,
                  min(first.stroke.bounds.height, second.stroke.bounds.height) >= height * 0.70,
                  overlap >= height * 0.70,
                  abs(first.centerY - second.centerY) <= height * 0.15 else { return nil }
        }

        let barIndices = Set(group.map(\.index))
        let dots = strokes.enumerated().compactMap { index, stroke -> Dot? in
            guard !barIndices.contains(index), isCompactDot(stroke, barHeight: height) else { return nil }
            let dot = Dot(index: index, bounds: stroke.bounds)
            let relativeY = (dot.centerY - bounds.minY) / height
            guard relativeY >= 0.18, relativeY <= 0.82 else { return nil }
            return dot
        }
        let maximumDotDistance = max(10, height * 0.32)
        let minimumClearance = max(1, height * 0.015)
        let left = dots.filter {
            $0.bounds.maxX <= bounds.minX - minimumClearance
                && bounds.minX - $0.centerX <= maximumDotDistance
        }
        let right = dots.filter {
            $0.bounds.minX >= bounds.maxX + minimumClearance
                && $0.centerX - bounds.maxX <= maximumDotDistance
        }
        // Incomplete or crowded punctuation on either side remains unclaimed.
        guard (left.isEmpty || isDotPair(left, barBounds: bounds)),
              (right.isEmpty || isDotPair(right, barBounds: bounds)),
              !left.isEmpty || !right.isEmpty else { return nil }
        let members = barIndices.union(left.map(\.index)).union(right.map(\.index))
        let signBounds = InkBounds.enclosing(members.map { strokes[$0].bounds })
        guard !hasInterferingInk(strokes, members: members, barBounds: bounds, signBounds: signBounds) else { return nil }

        // Locate the complete boundary at the center of its bars, not a dot or
        // whichever pen-down stroke happened to be delivered first.
        let boundaryX = group.map(\.centerX).reduce(0, +) / Double(group.count)
        let centerLine = InkStroke(points: [
            InkPoint(x: boundaryX, y: bounds.minY, timeOffset: nil),
            InkPoint(x: boundaryX, y: bounds.maxY, timeOffset: nil)
        ])
        guard var draft = ChordDraftBarlineRecognizer.candidate(
            for: centerLine, chordFrame: chordFrame, pageLayout: pageLayout
        ) else { return nil }
        draft.kind = left.isEmpty ? .repeatStart : (right.isEmpty ? .repeatEnd : .repeatBoth)
        draft.sourceStrokeIndex = anchor.index
        draft.sourceStrokeIndices = members
        draft.sourceStrokeGeometry = members.sorted().map { strokes[$0] }
        return draft
    }

    private static func isDotPair(_ dots: [Dot], barBounds: InkBounds) -> Bool {
        guard dots.count == 2 else { return false }
        let ordered = dots.sorted { $0.centerY < $1.centerY }
        let upper = ordered[0]
        let lower = ordered[1]
        let height = barBounds.height
        let separation = lower.centerY - upper.centerY
        let centerY = (upper.centerY + lower.centerY) / 2
        return abs(upper.centerX - lower.centerX) <= max(2.5, height * 0.07)
            && separation >= height * 0.15 && separation <= height * 0.52
            && abs(centerY - (barBounds.minY + barBounds.maxY) / 2) <= height * 0.12
    }

    private static func isCompactDot(_ stroke: InkStroke, barHeight: Double) -> Bool {
        guard hasFiniteGeometry(stroke) else { return false }
        let span = max(stroke.bounds.width, stroke.bounds.height)
        guard span <= max(2, barHeight * 0.16),
              pathLength(of: stroke) <= max(4, barHeight * 0.55) else { return false }
        // Stationary PencilKit taps have nonempty point paths but zero bounds.
        // Larger short lines/slashes must not be mistaken for repeat dots.
        return span <= max(2, barHeight * 0.05)
            || min(stroke.bounds.width, stroke.bounds.height) / max(0.001, span) >= 0.35
    }

    private static func hasInterferingInk(
        _ strokes: [InkStroke], members: Set<Int>, barBounds: InkBounds, signBounds: InkBounds
    ) -> Bool {
        let height = barBounds.height
        for (index, stroke) in strokes.enumerated() where !members.contains(index) {
            guard hasFiniteGeometry(stroke) else { return true }
            let other = stroke.bounds
            let overlapsBarHeight = other.maxY >= barBounds.minY - height * 0.08
                && other.minY <= barBounds.maxY + height * 0.08
            guard overlapsBarHeight else { continue }
            // A B/1 stem, accidental, or other connected construction cannot
            // surrender its vertical stroke merely because nearby ink has dots.
            let crossesBarNeighborhood = other.maxX >= barBounds.minX - height * 0.08
                && other.minX <= barBounds.maxX + height * 0.08
            if crossesBarNeighborhood { return true }
            let reachesSign = other.maxX >= signBounds.minX - height * 0.22
                && other.minX <= signBounds.maxX + height * 0.22
            let comparableBody = max(other.width, other.height) >= height * 0.22
            if reachesSign && comparableBody { return true }
        }
        return false
    }

    private static func hasFiniteGeometry(_ stroke: InkStroke) -> Bool {
        !stroke.points.isEmpty
            && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && [stroke.bounds.minX, stroke.bounds.minY, stroke.bounds.maxX, stroke.bounds.maxY].allSatisfy(\.isFinite)
            && stroke.bounds.maxX >= stroke.bounds.minX && stroke.bounds.maxY >= stroke.bounds.minY
    }

    private static func pathLength(of stroke: InkStroke) -> Double {
        zip(stroke.points, stroke.points.dropFirst()).reduce(0) { length, pair in
            length + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }
}
#endif
