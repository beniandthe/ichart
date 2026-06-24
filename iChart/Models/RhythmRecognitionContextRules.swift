import Foundation

struct RhythmRecognitionBeamBoundary: Hashable {
    enum Reason: String, Hashable {
        case nonBeamableDuration
        case rest
        case protectedMeterBoundary
    }

    let boundaryIndex: Int
    let offsetInWholeNotes: Double
    let reasons: Set<Reason>

    var blocksBeam: Bool {
        !reasons.isEmpty
    }
}

enum RhythmRecognitionContextRules {
    static func allowsBeamAcrossBoundary(
        beforeValueAt boundaryIndex: Int,
        in values: [RhythmValue],
        meter: Meter
    ) -> Bool {
        beamBoundary(
            beforeValueAt: boundaryIndex,
            in: values,
            meter: meter
        )?.blocksBeam == false
    }

    static func beamBoundaries(
        for values: [RhythmValue],
        meter: Meter
    ) -> [RhythmRecognitionBeamBoundary] {
        guard values.count > 1 else {
            return []
        }

        return (1..<values.count).compactMap { boundaryIndex in
            beamBoundary(
                beforeValueAt: boundaryIndex,
                in: values,
                meter: meter
            )
        }
    }

    static func hasProtectedBeamableBoundary(
        in values: [RhythmValue],
        meter: Meter
    ) -> Bool {
        beamBoundaries(for: values, meter: meter).contains { boundary in
            guard boundary.reasons.contains(.protectedMeterBoundary),
                  values.indices.contains(boundary.boundaryIndex),
                  values.indices.contains(boundary.boundaryIndex - 1) else {
                return false
            }

            return values[boundary.boundaryIndex - 1].isBeamableRecognitionReferenceValue
                && values[boundary.boundaryIndex].isBeamableRecognitionReferenceValue
        }
    }

    static func protectedMeterBoundaryOffsets(for meter: Meter) -> [Double] {
        guard meter.numerator > 1,
              meter.denominator > 0 else {
            return []
        }

        if meter.numerator == 4, meter.denominator == 4 {
            return [meter.measureLengthInWholeNotes / 2]
        }

        if meter.denominator == 8,
           meter.numerator > 3,
           meter.numerator.isMultiple(of: 3) {
            let compoundBeatLength = 3.0 / Double(meter.denominator)
            return stride(
                from: compoundBeatLength,
                to: meter.measureLengthInWholeNotes,
                by: compoundBeatLength
            ).map { $0 }
        }

        if meter.denominator == 4 {
            let beatLength = 1.0 / Double(meter.denominator)
            return stride(
                from: beatLength,
                to: meter.measureLengthInWholeNotes,
                by: beatLength
            ).map { $0 }
        }

        return []
    }

    private static func beamBoundary(
        beforeValueAt boundaryIndex: Int,
        in values: [RhythmValue],
        meter: Meter
    ) -> RhythmRecognitionBeamBoundary? {
        guard values.indices.contains(boundaryIndex),
              values.indices.contains(boundaryIndex - 1) else {
            return nil
        }

        let offset = values[..<boundaryIndex].reduce(Double.zero) { partialResult, value in
            partialResult + value.wholeNoteLength(in: meter)
        }
        let previousValue = values[boundaryIndex - 1]
        let nextValue = values[boundaryIndex]
        var reasons = Set<RhythmRecognitionBeamBoundary.Reason>()

        if !previousValue.isBeamableRecognitionReferenceValue
            || !nextValue.isBeamableRecognitionReferenceValue {
            reasons.insert(.nonBeamableDuration)
        }

        if previousValue.isRest || nextValue.isRest {
            reasons.insert(.rest)
        }

        if protectedMeterBoundaryOffsets(for: meter).contains(where: { nearlyEqual($0, offset) }) {
            reasons.insert(.protectedMeterBoundary)
        }

        return RhythmRecognitionBeamBoundary(
            boundaryIndex: boundaryIndex,
            offsetInWholeNotes: offset,
            reasons: reasons
        )
    }

    private static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}

private extension RhythmValue {
    var isBeamableRecognitionReferenceValue: Bool {
        switch self {
        case .sixteenth, .eighth, .dottedEighth:
            return true
        case .slash, .sixteenthRest, .eighthRest, .quarter, .quarterRest, .dottedQuarter, .half, .halfRest,
             .dottedHalf, .whole, .wholeRest, .tiedContinuation:
            return false
        }
    }
}
