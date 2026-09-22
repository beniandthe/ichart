import Foundation

/// Frozen input contract for learned chord-recognition models.
///
/// Changing any value in this schema requires a new model/schema version. The
/// encoders deliberately fail closed instead of dropping strokes or points.
enum ChordInkFeatureSchema {
    static let version = "chord-ink-features-v1"

    static let trajectoryShape = [1, 256, 10]
    static let trajectorySampleCount = 256
    static let trajectoryChannelCount = 10

    enum TrajectoryChannel: Int, CaseIterable, Sendable {
        case x = 0
        case y
        case deltaX
        case deltaY
        case arcStep
        case normalizedDeltaTime
        case timingAvailable
        case strokeStart
        case strokeEnd
        case valid
    }

    static let maximumWithinStrokeDeltaTimeSeconds = 0.250
    static let maximumPenUpDeltaTimeSeconds = 1.0

    static let rasterWidth = 256
    static let rasterHeight = 96
    static let rasterPadding = 8.0
    static let rasterStrokeWidth = 3.0
    static let rasterBackground: UInt8 = 0
    static let rasterForeground: UInt8 = 255

    static let maximumStrokeCount = 512
    static let maximumInputPointCount = 8_192
}

enum ChordInkFeatureNoReadReason: Error, Equatable, Sendable {
    case emptyInput
    case emptyStroke(index: Int)
    case nonFiniteGeometry(strokeIndex: Int, pointIndex: Int?, component: String)
    case invalidBounds(strokeIndex: Int)
    case strokeComplexityExceeded(limit: Int, actual: Int)
    case pointComplexityExceeded(limit: Int, actual: Int)
    case geometryExtentNotRepresentable
    case representationCannotFit(requiredMinimumSamples: Int, capacity: Int)
}

enum ChordInkFeatureEncodingError: Error, Equatable, Sendable {
    case noRead(ChordInkFeatureNoReadReason)
}

struct ChordInkTrajectoryFeatureTensor: Equatable, Sendable {
    let shape: [Int]
    let values: [Float]

    init(values: [Float]) {
        precondition(
            values.count
                == ChordInkFeatureSchema.trajectorySampleCount
                    * ChordInkFeatureSchema.trajectoryChannelCount
        )
        shape = ChordInkFeatureSchema.trajectoryShape
        self.values = values
    }

    subscript(
        sample sample: Int,
        channel channel: ChordInkFeatureSchema.TrajectoryChannel
    ) -> Float {
        values[sample * ChordInkFeatureSchema.trajectoryChannelCount + channel.rawValue]
    }
}

struct ChordInkRasterFeaturePlane: Equatable, Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(pixels: [UInt8]) {
        precondition(
            pixels.count
                == ChordInkFeatureSchema.rasterWidth * ChordInkFeatureSchema.rasterHeight
        )
        width = ChordInkFeatureSchema.rasterWidth
        height = ChordInkFeatureSchema.rasterHeight
        self.pixels = pixels
    }

    subscript(x x: Int, y y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

struct ChordInkPreparedFeatureGeometry: Sendable {
    struct Point: Sendable {
        let x: Double
        let y: Double
        let timeOffset: Double?
    }

    struct Stroke: Sendable {
        let points: [Point]
        let creationTimeOffset: Double?
        let arcLength: Double
    }

    let strokes: [Stroke]
    let normalizedWidth: Double
    let normalizedHeight: Double

    static func prepare(
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws -> ChordInkPreparedFeatureGeometry {
        try prepare(strokes: packet.preparedStrokes())
    }

    static func prepare(strokes sourceStrokes: [InkStroke]) throws -> Self {
        guard !sourceStrokes.isEmpty else {
            throw ChordInkFeatureEncodingError.noRead(.emptyInput)
        }
        guard sourceStrokes.count <= ChordInkFeatureSchema.maximumStrokeCount else {
            throw ChordInkFeatureEncodingError.noRead(
                .strokeComplexityExceeded(
                    limit: ChordInkFeatureSchema.maximumStrokeCount,
                    actual: sourceStrokes.count
                )
            )
        }

        var pointCount = 0
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity

        for (strokeIndex, stroke) in sourceStrokes.enumerated() {
            guard !stroke.points.isEmpty else {
                throw ChordInkFeatureEncodingError.noRead(.emptyStroke(index: strokeIndex))
            }
            pointCount += stroke.points.count
            guard pointCount <= ChordInkFeatureSchema.maximumInputPointCount else {
                throw ChordInkFeatureEncodingError.noRead(
                    .pointComplexityExceeded(
                        limit: ChordInkFeatureSchema.maximumInputPointCount,
                        actual: pointCount
                    )
                )
            }

            let boundsComponents = [
                ("bounds.minX", stroke.bounds.minX),
                ("bounds.minY", stroke.bounds.minY),
                ("bounds.maxX", stroke.bounds.maxX),
                ("bounds.maxY", stroke.bounds.maxY)
            ]
            for (component, value) in boundsComponents where !value.isFinite {
                throw ChordInkFeatureEncodingError.noRead(
                    .nonFiniteGeometry(
                        strokeIndex: strokeIndex,
                        pointIndex: nil,
                        component: component
                    )
                )
            }
            guard stroke.bounds.minX <= stroke.bounds.maxX,
                  stroke.bounds.minY <= stroke.bounds.maxY else {
                throw ChordInkFeatureEncodingError.noRead(.invalidBounds(strokeIndex: strokeIndex))
            }

            for (pointIndex, point) in stroke.points.enumerated() {
                guard point.x.isFinite else {
                    throw ChordInkFeatureEncodingError.noRead(
                        .nonFiniteGeometry(
                            strokeIndex: strokeIndex,
                            pointIndex: pointIndex,
                            component: "point.x"
                        )
                    )
                }
                guard point.y.isFinite else {
                    throw ChordInkFeatureEncodingError.noRead(
                        .nonFiniteGeometry(
                            strokeIndex: strokeIndex,
                            pointIndex: pointIndex,
                            component: "point.y"
                        )
                    )
                }
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }

        let width = maxX - minX
        let height = maxY - minY
        let maximumDimension = max(width, height)
        guard width.isFinite, height.isFinite, maximumDimension.isFinite else {
            throw ChordInkFeatureEncodingError.noRead(.geometryExtentNotRepresentable)
        }

        let normalizedWidth = maximumDimension > 0 ? width / maximumDimension : 0
        let normalizedHeight = maximumDimension > 0 ? height / maximumDimension : 0
        var preparedStrokes: [Stroke] = []
        preparedStrokes.reserveCapacity(sourceStrokes.count)

        for sourceStroke in sourceStrokes {
            let hasMonotonicLocalTiming = zip(
                sourceStroke.points,
                sourceStroke.points.dropFirst()
            ).allSatisfy { previous, current in
                guard let previousTime = previous.timeOffset,
                      let currentTime = current.timeOffset,
                      previousTime.isFinite,
                      currentTime.isFinite else {
                    return false
                }
                return currentTime >= previousTime
            } && sourceStroke.points.allSatisfy {
                $0.timeOffset?.isFinite == true
            }
            let points = sourceStroke.points.map { sourcePoint -> Point in
                let x: Double
                let y: Double
                if maximumDimension > 0 {
                    x = (sourcePoint.x - minX) / maximumDimension - normalizedWidth / 2
                    y = (sourcePoint.y - minY) / maximumDimension - normalizedHeight / 2
                } else {
                    x = 0
                    y = 0
                }
                return Point(
                    x: x,
                    y: y,
                    timeOffset: hasMonotonicLocalTiming
                        ? sourcePoint.timeOffset
                        : nil
                )
            }

            var arcLength = 0.0
            for index in points.indices.dropFirst() {
                arcLength += hypot(
                    points[index].x - points[index - 1].x,
                    points[index].y - points[index - 1].y
                )
            }
            preparedStrokes.append(
                Stroke(
                    points: points,
                    creationTimeOffset: sourceStroke.creationTimeOffset.flatMap {
                        $0.isFinite ? $0 : nil
                    },
                    arcLength: arcLength
                )
            )
        }

        return Self(
            strokes: preparedStrokes,
            normalizedWidth: normalizedWidth,
            normalizedHeight: normalizedHeight
        )
    }
}
