import Foundation

struct InkPoint: Codable, Hashable {
    var x: Double
    var y: Double
    var timeOffset: TimeInterval?
}

struct InkBounds: Codable, Hashable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double {
        max(0, maxX - minX)
    }

    var height: Double {
        max(0, maxY - minY)
    }

    static let zero = InkBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)

    static func enclosing(_ points: [InkPoint]) -> InkBounds {
        guard let firstPoint = points.first else {
            return .zero
        }

        return points.dropFirst().reduce(
            InkBounds(
                minX: firstPoint.x,
                minY: firstPoint.y,
                maxX: firstPoint.x,
                maxY: firstPoint.y
            )
        ) { bounds, point in
            bounds.union(
                InkBounds(
                    minX: point.x,
                    minY: point.y,
                    maxX: point.x,
                    maxY: point.y
                )
            )
        }
    }

    static func enclosing(_ bounds: [InkBounds]) -> InkBounds {
        guard let firstBounds = bounds.first else {
            return .zero
        }

        return bounds.dropFirst().reduce(firstBounds) { partialBounds, nextBounds in
            partialBounds.union(nextBounds)
        }
    }

    func union(_ other: InkBounds) -> InkBounds {
        InkBounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}

struct InkStroke: Codable, Hashable {
    var points: [InkPoint]
    var bounds: InkBounds
    /// Path creation time relative to the first stroke in its drawing. This
    /// keeps cross-stroke chronology without retaining a user's wall-clock
    /// timestamp. Older exported fixtures decode this as nil because they only
    /// retained each path's own relative point offsets.
    var creationTimeOffset: TimeInterval?

    init(
        points: [InkPoint],
        bounds: InkBounds? = nil,
        creationTimeOffset: TimeInterval? = nil
    ) {
        self.points = points
        self.bounds = bounds ?? InkBounds.enclosing(points)
        self.creationTimeOffset = creationTimeOffset
    }

    var timelineStartTimeOffset: TimeInterval? {
        guard let creationTimeOffset else {
            return nil
        }

        return creationTimeOffset + (points.compactMap(\.timeOffset).min() ?? 0)
    }

    var timelineEndTimeOffset: TimeInterval? {
        guard let creationTimeOffset else {
            return nil
        }

        return creationTimeOffset + (points.compactMap(\.timeOffset).max() ?? 0)
    }
}
