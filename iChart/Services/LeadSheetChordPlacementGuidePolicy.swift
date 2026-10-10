import CoreGraphics
import Foundation

enum LeadSheetChordPlacementGuidePolicy {
    static let snapTolerance: CGFloat = 18
    static let leadingArtifactInset: CGFloat = 12
    static let artifactGap: CGFloat = 6

    static func guideFractions(for meter: Meter) -> [Double] {
        let beatCount = max(1, meter.numerator)
        return (0..<beatCount).map { beatIndex in
            Double(beatIndex) / Double(beatCount)
        }
    }

    static func guideXs(for meter: Meter, in referenceFrame: CGRect) -> [CGFloat] {
        guideFractions(for: meter).map { fraction in
            referenceFrame.minX + referenceFrame.width * CGFloat(fraction)
        }
    }

    static func guideFrame(
        for measure: LeadSheetMeasureLayout,
        referenceFrame: CGRect
    ) -> CGRect {
        let leadingRepeatMaxX = measure.repeatMarkerLayouts
            .filter { $0.edge == .leading }
            .map(\.frame.maxX)
            .max()
        return guideFrame(
            referenceFrame: referenceFrame,
            leadingRepeatMarkerMaxX: leadingRepeatMaxX,
            meterChangeFrame: measure.meterChangeFrame
        )
    }

    static func guideFrame(
        referenceFrame: CGRect,
        leadingRepeatMarkerMaxX: CGFloat?,
        meterChangeFrame: CGRect?
    ) -> CGRect {
        let reservedArtifactMaxX = [
            leadingRepeatMarkerMaxX,
            meterChangeFrame?.maxX
        ]
            .compactMap { $0 }
            .max()
        let artifactSafeMinX = reservedArtifactMaxX.map { $0 + artifactGap }
            ?? referenceFrame.minX
        let preferredMinX = max(
            referenceFrame.minX + leadingArtifactInset,
            artifactSafeMinX
        )
        let resolvedMinX = min(
            max(referenceFrame.minX, preferredMinX),
            max(referenceFrame.minX, referenceFrame.maxX - 1)
        )

        return CGRect(
            x: resolvedMinX,
            y: referenceFrame.minY,
            width: max(1, referenceFrame.maxX - resolvedMinX),
            height: referenceFrame.height
        )
    }

    static func resolvedFraction(
        rawFraction: Double,
        referenceFrame: CGRect,
        guideFrame: CGRect,
        meter: Meter,
        tolerance: CGFloat = snapTolerance
    ) -> (fraction: Double, activeGuideX: CGFloat?) {
        let clampedFraction = ChordEvent.clampedManualLaneFraction(rawFraction)
        let rawX = referenceFrame.minX + referenceFrame.width * CGFloat(clampedFraction)
        let guideXs = guideXs(for: meter, in: guideFrame)
        guard let closestGuideX = guideXs.min(by: { lhs, rhs in
            abs(lhs - rawX) < abs(rhs - rawX)
        }) else {
            return (clampedFraction, nil)
        }

        guard abs(closestGuideX - rawX) <= tolerance else {
            return (clampedFraction, nil)
        }

        let snappedFraction = Double(
            (closestGuideX - referenceFrame.minX)
                / max(1, referenceFrame.width)
        )
        return (
            ChordEvent.clampedManualLaneFraction(snappedFraction),
            closestGuideX
        )
    }

    static func resolvedDragFraction(
        rawFraction: Double,
        initialX: CGFloat,
        screenPointsPerDisplayedPoint: CGFloat,
        referenceFrame: CGRect,
        guideFrame: CGRect,
        meter: Meter
    ) -> (fraction: Double, activeGuideX: CGFloat?) {
        let scale = max(0.0001, screenPointsPerDisplayedPoint)
        let clampedFraction = ChordEvent.clampedManualLaneFraction(rawFraction)
        let rawX = referenceFrame.minX + referenceFrame.width * CGFloat(clampedFraction)
        let safeMinX = max(referenceFrame.minX, guideFrame.minX)
        let safeMaxX = max(safeMinX, referenceFrame.maxX - 1)
        let boundedX = min(max(rawX, safeMinX), safeMaxX)
        let boundedFraction = ChordEvent.clampedManualLaneFraction(Double(
            (boundedX - referenceFrame.minX) / max(1, referenceFrame.width)
        ))
        // Starting on/near a particular guide means precision editing around
        // it. Only deliberately approaching a different/farther guide enables
        // the weak snap; feedback from a prior preview is not an input.
        let eligibleGuides = guideXs(for: meter, in: guideFrame).filter { guideX in
            let initialDistance = abs(guideX - initialX) * scale
            let currentDistance = abs(guideX - boundedX) * scale
            return initialDistance > 6 && currentDistance <= 2 && currentDistance < initialDistance
        }
        guard let snappedX = eligibleGuides.min(by: { abs($0 - boundedX) < abs($1 - boundedX) }) else {
            return (boundedFraction, nil)
        }
        return (
            ChordEvent.clampedManualLaneFraction(Double(
                (snappedX - referenceFrame.minX) / max(1, referenceFrame.width)
            )),
            snappedX
        )
    }
}
