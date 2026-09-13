#if canImport(PencilKit)
import Foundation
import PencilKit

enum PencilKitInkAdapter {
    static func inkStrokes(from drawingData: Data) throws -> [InkStroke] {
        try inkStrokes(from: PKDrawing(data: drawingData))
    }

    static func inkStrokes(from drawing: PKDrawing) -> [InkStroke] {
        let visibleFragments = drawing.strokes.flatMap(visibleStrokeFragments(from:))
        let timelineOrigin = visibleFragments.map { $0.path.creationDate }.min()
        return visibleFragments.map { fragment in
            inkStroke(from: fragment, timelineOrigin: timelineOrigin)
        }
    }

    static func inkStrokes(
        from drawing: PKDrawing,
        shouldContinue: () -> Bool
    ) -> [InkStroke]? {
        var visibleFragments = [PKStroke]()
        visibleFragments.reserveCapacity(drawing.strokes.count)
        for stroke in drawing.strokes {
            guard shouldContinue() else {
                return nil
            }
            visibleFragments.append(contentsOf: visibleStrokeFragments(from: stroke))
        }

        let timelineOrigin = visibleFragments.map { $0.path.creationDate }.min()
        var result = [InkStroke]()
        result.reserveCapacity(visibleFragments.count)
        for fragment in visibleFragments {
            guard shouldContinue() else {
                return nil
            }
            result.append(inkStroke(from: fragment, timelineOrigin: timelineOrigin))
        }
        return result
    }

    /// PencilKit's bitmap eraser retains the original path and clips the
    /// visible portions with a pre-transform mask. Recognition must consume
    /// those visible portions as independent pen-down strokes; concatenating
    /// disjoint ranges would invent a line through the erased gap.
    static func visibleStrokeFragments(from stroke: PKStroke) -> [PKStroke] {
        guard stroke.mask != nil else {
            return [stroke]
        }

        return stroke.maskedPathRanges.compactMap { range in
            let controlPoints = visibleControlPoints(in: stroke.path, range: range)
            guard !controlPoints.isEmpty else {
                return nil
            }
            return PKStroke(
                ink: stroke.ink,
                path: PKStrokePath(
                    controlPoints: controlPoints,
                    creationDate: stroke.path.creationDate
                ),
                transform: stroke.transform,
                mask: nil,
                randomSeed: stroke.randomSeed
            )
        }
    }

    private static func inkStroke(from stroke: PKStroke, timelineOrigin: Date?) -> InkStroke {
        let transform = stroke.transform
        return InkStroke(
            points: stroke.path.map { strokePoint in
                let location = strokePoint.location.applying(transform)
                return InkPoint(
                    x: Double(location.x),
                    y: Double(location.y),
                    timeOffset: strokePoint.timeOffset
                )
            },
            creationTimeOffset: timelineOrigin.map {
                stroke.path.creationDate.timeIntervalSince($0)
            }
        )
    }

    private static func visibleControlPoints(
        in path: PKStrokePath,
        range: ClosedRange<CGFloat>
    ) -> [PKStrokePoint] {
        guard !path.isEmpty else {
            return []
        }

        let minimumValue = CGFloat(path.startIndex)
        let maximumValue = CGFloat(path.endIndex - 1)
        let lowerBound = min(max(range.lowerBound, minimumValue), maximumValue)
        let upperBound = min(max(range.upperBound, minimumValue), maximumValue)
        guard upperBound >= lowerBound else {
            return []
        }

        let epsilon: CGFloat = 0.000_001
        var parametricValues = [lowerBound]
        var integerValue = ceil(lowerBound)
        while integerValue < upperBound {
            if integerValue - lowerBound > epsilon {
                parametricValues.append(integerValue)
            }
            integerValue += 1
        }
        if upperBound - (parametricValues.last ?? lowerBound) > epsilon {
            parametricValues.append(upperBound)
        }

        return parametricValues.map(path.interpolatedPoint(at:))
    }
}
#endif
