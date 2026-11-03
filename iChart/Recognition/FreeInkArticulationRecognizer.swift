import Foundation

/// Recognizes one explicitly selected mark from its centerline geometry.
enum FreeInkArticulationRecognizer {
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
            return isAccent(first[...], second[...]) ? .accent : nil
        }

        guard let tip = first.indices.max(by: { first[$0].x < first[$1].x }),
              tip > first.startIndex, tip < first.index(before: first.endIndex) else {
            return nil
        }
        return isAccent(first[...tip], first[tip...]) ? .accent : nil
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
        guard let firstLeg = straightLeg(first), let secondLeg = straightLeg(second) else { return false }
        let bounds = InkBounds.enclosing(Array(first) + Array(second))
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
            && tipTop >= bounds.minY + 0.26 * height
            && tipBottom <= bounds.maxY - 0.26 * height
            && hypot(firstLeg.right.x - secondLeg.right.x, tipBottom - tipTop) <= 0.16 * width
    }

    private static func straightLeg(_ points: ArraySlice<InkPoint>) -> (left: InkPoint, right: InkPoint)? {
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
                  return deviation <= 0.09 * length
              }) else {
            return nil
        }
        return (left, right)
    }
}
