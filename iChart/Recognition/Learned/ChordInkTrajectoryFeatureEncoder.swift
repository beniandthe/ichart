import Foundation

enum ChordInkTrajectoryFeatureEncoder {
    private struct Sample {
        let x: Double
        let y: Double
        let localTime: Double?
        let absoluteTime: Double?
    }

    static func encode(
        _ packet: ChordInkCanonicalTrajectoryPacket
    ) throws -> ChordInkTrajectoryFeatureTensor {
        try encode(prepared: ChordInkPreparedFeatureGeometry.prepare(packet: packet))
    }

    static func encode(
        strokes: [InkStroke]
    ) throws -> ChordInkTrajectoryFeatureTensor {
        try encode(prepared: ChordInkPreparedFeatureGeometry.prepare(strokes: strokes))
    }

    private static func encode(
        prepared: ChordInkPreparedFeatureGeometry
    ) throws -> ChordInkTrajectoryFeatureTensor {
        let allocations = try sampleAllocations(for: prepared.strokes)
        let channelCount = ChordInkFeatureSchema.trajectoryChannelCount
        var values = Array(
            repeating: Float.zero,
            count: ChordInkFeatureSchema.trajectorySampleCount * channelCount
        )
        var outputIndex = 0
        var previousGlobalSample: Sample?

        for (strokeIndex, stroke) in prepared.strokes.enumerated() {
            let samples = resample(stroke: stroke, count: allocations[strokeIndex])
            var previousStrokeSample: Sample?

            for (sampleIndex, sample) in samples.enumerated() {
                let deltaX = sample.x - (previousStrokeSample?.x ?? sample.x)
                let deltaY = sample.y - (previousStrokeSample?.y ?? sample.y)
                let arcStep = hypot(deltaX, deltaY)
                let timing = timingDelta(
                    current: sample,
                    previousInStroke: previousStrokeSample,
                    previousGlobally: previousGlobalSample
                )

                set(sample.x, at: outputIndex, channel: .x, in: &values)
                set(sample.y, at: outputIndex, channel: .y, in: &values)
                set(deltaX, at: outputIndex, channel: .deltaX, in: &values)
                set(deltaY, at: outputIndex, channel: .deltaY, in: &values)
                set(arcStep, at: outputIndex, channel: .arcStep, in: &values)
                set(timing.value, at: outputIndex, channel: .normalizedDeltaTime, in: &values)
                set(timing.available ? 1 : 0, at: outputIndex, channel: .timingAvailable, in: &values)
                set(sampleIndex == 0 ? 1 : 0, at: outputIndex, channel: .strokeStart, in: &values)
                set(sampleIndex == samples.count - 1 ? 1 : 0, at: outputIndex, channel: .strokeEnd, in: &values)
                set(1, at: outputIndex, channel: .valid, in: &values)

                outputIndex += 1
                previousStrokeSample = sample
                previousGlobalSample = sample
            }
        }

        return ChordInkTrajectoryFeatureTensor(values: values)
    }

    private static func sampleAllocations(
        for strokes: [ChordInkPreparedFeatureGeometry.Stroke]
    ) throws -> [Int] {
        let minimum = strokes.map { $0.points.count == 1 ? 1 : 2 }
        let required = minimum.reduce(0, +)
        let capacity = ChordInkFeatureSchema.trajectorySampleCount
        guard required <= capacity else {
            throw ChordInkFeatureEncodingError.noRead(
                .representationCannotFit(
                    requiredMinimumSamples: required,
                    capacity: capacity
                )
            )
        }

        var allocations = minimum
        let remaining = capacity - required
        let totalArcLength = strokes.reduce(0.0) { $0 + $1.arcLength }
        guard remaining > 0, totalArcLength > 0 else {
            return allocations
        }

        struct Remainder {
            let index: Int
            let value: Double
        }
        var remainders: [Remainder] = []
        var assigned = 0
        for (index, stroke) in strokes.enumerated() {
            let exact = Double(remaining) * stroke.arcLength / totalArcLength
            let whole = Int(floor(exact))
            allocations[index] += whole
            assigned += whole
            remainders.append(Remainder(index: index, value: exact - Double(whole)))
        }

        remainders.sort {
            if $0.value == $1.value { return $0.index < $1.index }
            return $0.value > $1.value
        }
        for remainder in remainders.prefix(remaining - assigned) {
            allocations[remainder.index] += 1
        }
        return allocations
    }

    private static func resample(
        stroke: ChordInkPreparedFeatureGeometry.Stroke,
        count: Int
    ) -> [Sample] {
        precondition(count > 0)
        let points = stroke.points
        if count == 1 {
            return [sample(point: points[0], creationTime: stroke.creationTimeOffset)]
        }
        if stroke.arcLength == 0 {
            return [
                sample(point: points[0], creationTime: stroke.creationTimeOffset),
                sample(point: points[points.count - 1], creationTime: stroke.creationTimeOffset)
            ]
        }

        var cumulative = Array(repeating: 0.0, count: points.count)
        for index in points.indices.dropFirst() {
            cumulative[index] = cumulative[index - 1] + hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            )
        }

        var result: [Sample] = []
        result.reserveCapacity(count)
        var segment = 1
        for sampleIndex in 0..<count {
            if sampleIndex == 0 {
                result.append(sample(point: points[0], creationTime: stroke.creationTimeOffset))
                continue
            }
            if sampleIndex == count - 1 {
                result.append(
                    sample(point: points[points.count - 1], creationTime: stroke.creationTimeOffset)
                )
                continue
            }

            let target = stroke.arcLength * Double(sampleIndex) / Double(count - 1)
            while segment < cumulative.count - 1, cumulative[segment] < target {
                segment += 1
            }
            let lower = segment - 1
            let segmentLength = cumulative[segment] - cumulative[lower]
            if segmentLength <= 0 {
                result.append(sample(point: points[segment], creationTime: stroke.creationTimeOffset))
                continue
            }
            let fraction = (target - cumulative[lower]) / segmentLength
            let localTime = interpolatedTime(
                from: points[lower].timeOffset,
                to: points[segment].timeOffset,
                fraction: fraction
            )
            result.append(
                makeSample(
                    x: points[lower].x + (points[segment].x - points[lower].x) * fraction,
                    y: points[lower].y + (points[segment].y - points[lower].y) * fraction,
                    localTime: localTime,
                    creationTime: stroke.creationTimeOffset
                )
            )
        }
        return result
    }

    private static func sample(
        point: ChordInkPreparedFeatureGeometry.Point,
        creationTime: Double?
    ) -> Sample {
        makeSample(
            x: point.x,
            y: point.y,
            localTime: point.timeOffset,
            creationTime: creationTime
        )
    }

    private static func makeSample(
        x: Double,
        y: Double,
        localTime: Double?,
        creationTime: Double?
    ) -> Sample {
        let absoluteTime: Double?
        if let localTime, let creationTime {
            let sum = localTime + creationTime
            absoluteTime = sum.isFinite ? sum : nil
        } else {
            absoluteTime = nil
        }
        return Sample(x: x, y: y, localTime: localTime, absoluteTime: absoluteTime)
    }

    private static func interpolatedTime(
        from start: Double?,
        to end: Double?,
        fraction: Double
    ) -> Double? {
        guard let start, let end, end >= start else { return nil }
        let value = start + (end - start) * fraction
        return value.isFinite ? value : nil
    }

    private static func timingDelta(
        current: Sample,
        previousInStroke: Sample?,
        previousGlobally: Sample?
    ) -> (value: Double, available: Bool) {
        let deltaAndCap: (delta: Double, cap: Double)?
        if let previousInStroke,
           let currentTime = current.localTime,
           let previousTime = previousInStroke.localTime {
            deltaAndCap = (
                currentTime - previousTime,
                ChordInkFeatureSchema.maximumWithinStrokeDeltaTimeSeconds
            )
        } else if previousInStroke == nil,
                  let previousGlobally,
                  let currentTime = current.absoluteTime,
                  let previousTime = previousGlobally.absoluteTime {
            deltaAndCap = (
                currentTime - previousTime,
                ChordInkFeatureSchema.maximumPenUpDeltaTimeSeconds
            )
        } else {
            deltaAndCap = nil
        }

        guard let deltaAndCap,
              deltaAndCap.delta.isFinite,
              deltaAndCap.delta >= 0 else {
            return (0, false)
        }
        return (
            min(deltaAndCap.delta, deltaAndCap.cap) / deltaAndCap.cap,
            true
        )
    }

    private static func set(
        _ value: Double,
        at sample: Int,
        channel: ChordInkFeatureSchema.TrajectoryChannel,
        in values: inout [Float]
    ) {
        let converted = Float(value)
        precondition(converted.isFinite)
        values[sample * ChordInkFeatureSchema.trajectoryChannelCount + channel.rawValue] = converted
    }
}
