#if canImport(UIKit)
import CoreGraphics
import Foundation

/// A bounded search for editor controls, without changing notation layout.
enum LeadSheetEndingOverlayPlacement {
    static func notationObstacles(in layout: LeadSheetPageLayout, scale: CGFloat) -> [CGRect] {
        var frames = [layout.header.frame, layout.header.handwrittenFrame]
        for system in layout.systems {
            frames += system.endingLayouts.map(\.occupiedFrame)
            frames += system.roadmapMarkerLayouts.map(\.frame)
            frames += system.keySignatureLayouts.map(\.frame)
            frames += [system.clefFrame, system.keyTextFrame, system.timeSignatureFrame,
                system.sectionTextFrame, system.roadmapTextFrame].compactMap { $0 }
            for measure in system.measures {
                if system.layoutStyle != .simpleChordSheet { frames.append(measure.staffFrame) }
                frames += measure.chordLayouts.map { $0.frame.union($0.naturalFrame) }
                frames += measure.noteLayouts.map(\.selectionFrame)
                frames += measure.cueTextLayouts.map(\.frame)
                frames += measure.repeatMarkerLayouts.map(\.occupiedFrame)
                if let meter = measure.meterChangeFrame { frames.append(meter) }
                frames.append(CGRect(x: measure.staffFrame.minX - 1 / scale, y: measure.staffFrame.minY,
                    width: 2 / scale, height: measure.staffFrame.height))
                frames.append(measure.trailingBarlineFrame.insetBy(dx: -1 / scale, dy: 0))
            }
        }
        return frames.filter(valid).map { $0.insetBy(dx: -3 / scale, dy: -3 / scale) }
    }

    static func frame(
        size: CGSize, preferredOrigin: CGPoint, inside paper: CGRect,
        obstacles: [CGRect], reserved: [CGRect], scale: CGFloat,
        requiresClearSpace: Bool = false,
        maximumScreenOriginTravel: CGFloat? = nil,
        clearanceScreenPoints: CGFloat = 6
    ) -> CGRect? {
        let usable = paper.insetBy(dx: 6 / scale, dy: 6 / scale)
        guard valid(usable), size.width > 0, size.height > 0,
              size.width <= usable.width, size.height <= usable.height else { return nil }
        let gap = clearanceScreenPoints / scale
        let blocked = obstacles.filter { $0.intersects(usable) }
        let hard = reserved.filter { $0.intersects(usable) }.map { $0.insetBy(dx: -gap, dy: -gap) }
        let preferred = CGRect(origin: preferredOrigin, size: size)
        let nearest = (blocked + hard).sorted {
            distance($0.origin, preferredOrigin) < distance($1.origin, preferredOrigin)
        }.prefix(12)
        var xs = [preferred.minX, usable.minX, usable.maxX - size.width, usable.midX - size.width / 2]
        var ys = [preferred.minY, usable.minY, usable.maxY - size.height, usable.midY - size.height / 2]
        for frame in nearest {
            xs += [frame.minX - gap - size.width, frame.maxX + gap]
            ys += [frame.minY - gap - size.height, frame.maxY + gap]
        }
        // The clear-space card must consider both edges of all twelve nearby
        // obstacles. Truncating their first sixteen coordinates can discard a
        // later clear inter-row gap, even within the allowed travel distance.
        let coordinateLimit = requiresClearSpace ? 32 : 16
        xs = coordinates(xs, lower: usable.minX, upper: usable.maxX - size.width, scale: scale, limit: coordinateLimit)
        ys = coordinates(ys, lower: usable.minY, upper: usable.maxY - size.height, scale: scale, limit: coordinateLimit)
        var best: CGRect?
        var bestOverlap = CGFloat.infinity
        var bestDistance = CGFloat.infinity
        for x in xs {
            for y in ys {
                let candidate = CGRect(x: x, y: y, width: size.width, height: size.height)
                let travel = distance(candidate.origin, preferredOrigin)
                if let maximumScreenOriginTravel,
                   travel * scale * scale > maximumScreenOriginTravel * maximumScreenOriginTravel { continue }
                guard !hard.contains(where: { candidate.intersects($0) }) else { continue }
                var overlap: CGFloat = 0
                for obstacle in blocked {
                    let intersection = candidate.intersection(obstacle)
                    if !intersection.isNull { overlap += intersection.width * intersection.height }
                }
                if overlap < bestOverlap || (overlap == bestOverlap && travel < bestDistance) {
                    best = candidate
                    bestOverlap = overlap
                    bestDistance = travel
                }
            }
        }
        // Essential handles retain the least obstructive usable placement.
        // Supplementary status can disappear when no clear space exists.
        return requiresClearSpace && bestOverlap > 0 ? nil : best
    }

    private static func coordinates(_ values: [CGFloat], lower: CGFloat, upper: CGFloat, scale: CGFloat, limit: Int) -> [CGFloat] {
        var result: [CGFloat] = []
        for value in values where value.isFinite {
            let value = min(max(value, lower), upper)
            if !result.contains(where: { abs($0 - value) < 0.5 / scale }) { result.append(value) }
            if result.count == limit { break }
        }
        return result
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let x = a.x - b.x, y = a.y - b.y
        return x * x + y * y
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && !frame.isInfinite
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }
}
#endif
