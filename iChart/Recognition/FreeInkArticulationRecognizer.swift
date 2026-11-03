import Foundation

/// Recognizes one mark from its centerline geometry.
enum FreeInkArticulationRecognizer {
    /// Automatic recognition may claim only a fresh, isolated stroke suffix.
    /// An adjacent stroke outside that suffix can veto the match but cannot
    /// become part of it.
    static func automaticCandidate(
        in strokes: [InkStroke],
        eligibleStrokeIndices: Set<Int>
    ) -> (kind: FreeInkArticulationKind, indices: [Int])? {
        guard let last = strokes.indices.last, eligibleStrokeIndices.contains(last) else { return nil }

        var suffixes = [[last]]
        if last > 0, eligibleStrokeIndices.contains(last - 1),
           belongsToSameMark(strokes[last - 1], strokes[last]) {
            suffixes.append([last - 1, last])
        }
        let matches = suffixes.compactMap { indices -> (kind: FreeInkArticulationKind, indices: [Int])? in
            guard let kind = recognize(indices.map { strokes[$0] }) else { return nil }
            return (kind, indices)
        }
        guard matches.count == 1, let match = matches.first else { return nil }

        let markBounds = InkBounds.enclosing(match.indices.map { InkBounds.enclosing(strokes[$0].points) })
        let clearance = max(markBounds.width, markBounds.height) * 0.22
        let hasNearbyInk = strokes.indices.contains { index in
            guard !match.indices.contains(index) else { return false }
            let neighbor = strokes[index].bounds
            return neighbor.maxX >= markBounds.minX - clearance
                && neighbor.minX <= markBounds.maxX + clearance
                && neighbor.maxY >= markBounds.minY - clearance
                && neighbor.minY <= markBounds.maxY + clearance
        }
        return hasNearbyInk ? nil : match
    }

    private static func belongsToSameMark(_ first: InkStroke, _ second: InkStroke) -> Bool {
        guard let firstEnd = first.timelineEndTimeOffset,
              let secondStart = second.timelineStartTimeOffset else { return false }
        // Allow small timestamp overlap from PencilKit while excluding a
        // separate mark written after a deliberate pause.
        return (-0.04...0.55).contains(secondStart - firstEnd)
    }

    static func recognize(_ strokes: [InkStroke]) -> FreeInkArticulationKind? {
        guard (1...2).contains(strokes.count),
              strokes.allSatisfy({ stroke in
                  !stroke.points.isEmpty && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
              }) else {
            return nil
        }

        let first = strokes[0].points
        if strokes.count == 2 {
            let second = strokes[1].points
            let firstBounds = InkBounds.enclosing(first)
            let secondBounds = InkBounds.enclosing(second)
            let (arc, arcBounds, dotBounds) = firstBounds.width >= secondBounds.width
                ? (first, firstBounds, secondBounds)
                : (second, secondBounds, firstBounds)
            if isFermata(arc: arc, arcBounds: arcBounds, dotBounds: dotBounds) {
                return .fermata
            }
            return unambiguousChevron(accent: isAccent(first[...], second[...]),
                marcato: isMarcato(first[...], second[...]))
        }

        let accent = isSingleStrokeAccent(first)
        let marcato: Bool
        if let apex = first.indices.min(by: { first[$0].y < first[$1].y }),
           apex > first.startIndex, apex < first.index(before: first.endIndex) {
            marcato = isMarcato(first[...apex], first[apex...])
        } else {
            marcato = false
        }
        return unambiguousChevron(accent: accent, marcato: marcato)
    }

    private static func unambiguousChevron(accent: Bool, marcato: Bool) -> FreeInkArticulationKind? {
        switch (accent, marcato) {
        case (true, false): return .accent
        case (false, true): return .marcato
        default: return nil
        }
    }

    private static func isSingleStrokeAccent(_ points: [InkPoint]) -> Bool {
        guard let tip = points.indices.max(by: { points[$0].x < points[$1].x }),
              tip > points.startIndex, tip < points.index(before: points.endIndex) else { return false }
        let beforeTip = points[...tip]
        let afterTip = points[tip...]
        if isAccent(beforeTip, afterTip) {
            return true
        }
        let bounds = InkBounds.enclosing(points)
        let reversedAfterTip = Array(afterTip.reversed())[...]
        return hasAccentWithRetracedLeadIn(beforeTip, reversedAfterTip, bounds: bounds)
            || hasAccentWithRetracedLeadIn(reversedAfterTip, beforeTip, bounds: bounds)
    }

    private static func isMarcato(_ first: ArraySlice<InkPoint>, _ second: ArraySlice<InkPoint>) -> Bool {
        guard let firstLeg = straightLeg(first), let secondLeg = straightLeg(second) else { return false }
        let bounds = InkBounds.enclosing(Array(first) + Array(second))
        let width = bounds.width
        let height = bounds.height
        guard width.isFinite, height.isFinite, height > 0, (0.65...1.9).contains(width / height) else {
            return false
        }

        // Require two straight, opposite slopes whose low ends spread out
        // from one centered high tip. A rounded arch or slanted mark stays ink.
        let (left, right) = firstLeg.left.x < secondLeg.left.x ? (firstLeg, secondLeg) : (secondLeg, firstLeg)
        let leftTip = left.right
        let rightTip = right.left
        let tipXRange = (bounds.minX + 0.34 * width)...(bounds.maxX - 0.34 * width)
        return left.left.x <= bounds.minX + 0.12 * width
            && right.right.x >= bounds.maxX - 0.12 * width
            && min(left.left.y, right.right.y) >= bounds.maxY - 0.16 * height
            && max(leftTip.y, rightTip.y) <= bounds.minY + 0.15 * height
            && tipXRange.contains(leftTip.x) && tipXRange.contains(rightTip.x)
            && hypot(leftTip.x - rightTip.x, leftTip.y - rightTip.y) <= 0.12 * min(width, height)
    }

    private static func isFermata(arc: [InkPoint], arcBounds: InkBounds, dotBounds: InkBounds) -> Bool {
        let width = arcBounds.width
        let height = arcBounds.height
        guard width.isFinite, height.isFinite, height > 0,
              (1.25...4.5).contains(width / height),
              max(dotBounds.width, dotBounds.height) <= 0.16 * width,
              dotBounds.minX >= arcBounds.minX + 0.26 * width,
              dotBounds.maxX <= arcBounds.maxX - 0.26 * width,
              dotBounds.minY >= arcBounds.minY + 0.47 * height,
              dotBounds.maxY <= arcBounds.maxY + 0.25 * width,
              let first = arc.first, let last = arc.last,
              let apex = arc.min(by: { $0.y < $1.y }) else {
            return false
        }

        let (left, right) = first.x < last.x ? (first, last) : (last, first)
        guard left.x <= arcBounds.minX + 0.15 * width,
              right.x >= arcBounds.maxX - 0.15 * width,
              min(left.y, right.y) >= arcBounds.minY + 0.64 * height,
              apex.x >= arcBounds.minX + 0.27 * width,
              apex.x <= arcBounds.maxX - 0.27 * width else {
            return false
        }

        // The arch bends above both straight chords from the ends to the
        // apex. Requiring the bend on both sides rejects a pointed caret.
        let horizontalTravel = zip(arc, arc.dropFirst()).reduce(0.0) { travel, pair in
            travel + abs(pair.1.x - pair.0.x)
        }
        return horizontalTravel <= 1.2 * width
            && bowsAboveChord(arc, from: left, to: apex, by: 0.09 * height)
            && bowsAboveChord(arc, from: apex, to: right, by: 0.09 * height)
    }

    private static func bowsAboveChord(
        _ points: [InkPoint], from start: InkPoint, to end: InkPoint, by rise: Double
    ) -> Bool {
        let width = end.x - start.x
        return points.contains { point in
            let fraction = (point.x - start.x) / width
            guard (0.2...0.8).contains(fraction) else { return false }
            let chordY = start.y + fraction * (end.y - start.y)
            return point.y <= chordY - rise
        }
    }

    private static func isAccent(_ first: ArraySlice<InkPoint>, _ second: ArraySlice<InkPoint>) -> Bool {
        // A handwritten chevron can round one leg or have an uneven angle.
        // Keep a straighter second leg, a shared tip, and two open ends.
        let straightFirst = straightLeg(first)
        let straightSecond = straightLeg(second)
        guard straightFirst != nil || straightSecond != nil,
              let firstLeg = straightFirst ?? straightLeg(first, maximumDeviation: 0.11),
              let secondLeg = straightSecond ?? straightLeg(second, maximumDeviation: 0.11) else { return false }
        return hasAccentOutline(firstLeg, secondLeg,
            bounds: InkBounds.enclosing(Array(first) + Array(second)),
            tipHeightRange: 0.23...0.77)
    }

    private static func hasAccentWithRetracedLeadIn(
        _ first: ArraySlice<InkPoint>, _ second: ArraySlice<InkPoint>, bounds: InkBounds
    ) -> Bool {
        guard let turn = first.indices.min(by: { first[$0].x < first[$1].x }),
              turn > first.startIndex, turn < first.index(before: first.endIndex),
              let leadIn = straightLeg(first[...turn]),
              let firstLeg = straightLeg(first[turn...]),
              let secondLeg = straightLeg(second),
              leadIn.right.x - leadIn.left.x <= 0.55 * (firstLeg.right.x - firstLeg.left.x),
              InkBounds.enclosing(Array(first[...turn])).height <= 0.10 * bounds.height else { return false }

        // A short horizontal retrace can precede the shallower leg of a
        // handwritten accent. Require both legs to remain straight and
        // share a single rightward tip.
        return hasAccentOutline(firstLeg, secondLeg, bounds: bounds, tipHeightRange: 0.16...0.84)
    }

    private typealias AccentLeg = (left: InkPoint, right: InkPoint)

    private static func hasAccentOutline(
        _ firstLeg: AccentLeg, _ secondLeg: AccentLeg, bounds: InkBounds,
        tipHeightRange: ClosedRange<Double>
    ) -> Bool {
        let width = bounds.width
        let height = bounds.height
        guard width.isFinite, height.isFinite, height > 0,
              (0.8...4).contains(width / height) else {
            return false
        }

        let top = min(firstLeg.left.y, secondLeg.left.y)
        let bottom = max(firstLeg.left.y, secondLeg.left.y)
        let tipTop = min(firstLeg.right.y, secondLeg.right.y)
        let tipBottom = max(firstLeg.right.y, secondLeg.right.y)
        return max(firstLeg.left.x, secondLeg.left.x) <= bounds.minX + 0.24 * width
            && min(firstLeg.right.x, secondLeg.right.x) >= bounds.maxX - 0.16 * width
            && top <= bounds.minY + 0.15 * height
            && bottom >= bounds.maxY - 0.15 * height
            && tipHeightRange.contains((tipTop - bounds.minY) / height)
            && tipHeightRange.contains((tipBottom - bounds.minY) / height)
            && hypot(firstLeg.right.x - secondLeg.right.x, tipBottom - tipTop) <= 0.16 * width
    }

    private static func straightLeg(_ points: ArraySlice<InkPoint>, maximumDeviation: Double = 0.09) -> AccentLeg? {
        guard let first = points.first, let last = points.last else { return nil }
        let (left, right) = first.x < last.x ? (first, last) : (last, first)
        let dx = right.x - left.x
        let dy = right.y - left.y
        let length = hypot(dx, dy)
        guard dx > 0, length.isFinite else { return nil }

        let travel = zip(points, points.dropFirst()).reduce(0.0) { length, pair in
            length + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        guard travel <= 1.13 * length,
              points.allSatisfy({ point in
                  let deviation = abs(dx / length * (point.y - left.y) - dy / length * (point.x - left.x))
                  return deviation <= maximumDeviation * length
              }) else {
            return nil
        }
        return (left, right)
    }
}
