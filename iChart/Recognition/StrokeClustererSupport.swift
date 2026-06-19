import Foundation

struct MutableInkCluster: Hashable {
    var strokes: [InkStroke]
    var originalIndexes: [Int]

    var bounds: InkBounds {
        InkBounds.enclosing(strokes.map(\.bounds))
    }

    var startTimeOffset: TimeInterval? {
        strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .min()
    }

    var endTimeOffset: TimeInterval? {
        strokes
            .flatMap(\.points)
            .compactMap(\.timeOffset)
            .max()
    }

    var isRootBodyCandidate: Bool {
        bounds.width >= 8
            && bounds.height >= 16
            && bounds.recognitionArea >= 220
    }

    var isPlainSuspendedPrefixCandidate: Bool {
        isRootBodyCandidate
            || isFlatGlyphCandidate
            || isSharpGlyphCandidate
            || isSharpConstructionPart
    }

    var isSlashBassPrefixCandidate: Bool {
        guard !isSharpGlyphCandidate,
              !isSharpConstructionPart else {
            return false
        }

        return isSlashBassLeadingRootContextCandidate
            || hasRootConstructionVerticalStem && hasRootConstructionBar
    }

    var isSlashBassLeadingRootContextCandidate: Bool {
        guard !isSlashLikeSeparator else {
            return false
        }

        return hasRootConstructionBody
            || isRootBodyCandidate
            || (strokes.count >= 2 && bounds.width >= 8 && bounds.height >= 12)
    }

    var isSlashBassFollowingGlyphCandidate: Bool {
        guard !isSlashLikeSeparator,
              !isQualityOrExtensionGlyphCandidate,
              !isMinorSuffixCandidate,
              !isAlterationNumberCandidate,
              !isSharpConstructionPart else {
            return false
        }

        return hasRootConstructionBody
            || isRootBodyCandidate
            || (strokes.count >= 2 && bounds.width >= 8 && bounds.height >= 12)
    }

    var isAccidentalModifierCandidate: Bool {
        bounds.width >= 1
            && (bounds.height >= 4 || bounds.width >= 8)
            && bounds.recognitionArea >= 4
            && strokes.count <= 6
    }

    var isDominantSevenSuffixAnchor: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSevenCandidate
    }

    var isMinorSuffixCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isMinorMCandidate || stroke.isLooseMinorMSuffixCandidate || stroke.isDashMinorCandidate
    }

    var isMinorSixExtensionContextCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        let bounds = stroke.bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let aspectRatio = width / height
        let canBeLooseSix = stroke.points.count >= 8
            && bounds.width >= 4
            && bounds.width <= 22
            && bounds.height >= 10
            && bounds.height <= 38
            && aspectRatio >= 0.16
            && aspectRatio <= 1.45

        return canBeLooseSix
            || stroke.isNineGlyphCandidate
            || stroke.isFiveGlyphCandidate
    }

    var isDominantSevenAlterationAnchor: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSevenCandidate && stroke.hasEarlyTopHorizontalRun
    }

    var isDominantSevenInkAnchor: Bool {
        isDominantSevenSuffixAnchor || isDominantSevenAlterationAnchor
    }

    var isDominantFlatNineStemFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineStemFragment
    }

    var isDominantFlatNineCurvedFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineCurvedFragment
    }

    var isDominantFlatNineMergedFlatFragment: Bool {
        guard strokes.count == 2 else {
            return false
        }

        let orderedStrokes = strokes.sorted { lhs, rhs in
            lhs.bounds.minX < rhs.bounds.minX
        }

        return orderedStrokes[0].isDominantFlatNineStemFragment
            && orderedStrokes[1].isDominantFlatNineCurvedFragment
            && bounds.width <= 32
            && bounds.height <= 42
    }

    var isDominantFlatNineTailFragment: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDominantFlatNineTailFragment
    }

    var isParenthesizedAlterationWrapperCandidate: Bool {
        isOpeningParenthesizedAlterationWrapperCandidate
            || isClosingParenthesizedAlterationWrapperCandidate
    }

    var isOpeningParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOpeningParenthesizedAlterationWrapperCandidate
            || stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate
    }

    var isLooseOpeningParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate
    }

    var isClosingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isClosingParenthesizedAlterationWrapperCandidate
    }

    var isLooseClosingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isLooseClosingParenthesizedAlterationWrapperCandidate
    }

    var isTrailingParenthesizedAlterationWrapperCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isTrailingParenthesizedAlterationWrapperCandidate
    }

    var isLooseTrailingAlterationWrapperCandidate: Bool {
        strokes.count == 1
            && bounds.width <= 18
            && bounds.height >= 14
            && bounds.height <= 42
    }

    var isAlterationAccidentalCandidate: Bool {
        isSharpGlyphCandidate
            || isPartialSharpConstruction
            || isFlatGlyphCandidate
            || isDominantFlatNineMergedFlatFragment
            || isDominantFlatNineStemFragment
    }

    var isWrittenAlterationAccidentalCandidate: Bool {
        isSharpGlyphCandidate
            || isFlatGlyphCandidate
            || isDominantFlatNineMergedFlatFragment
    }

    var isAlterationNumberCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOneGlyphCandidate
            || stroke.isThreeGlyphCandidate
            || stroke.isFiveGlyphCandidate
            || stroke.isNineGlyphCandidate
    }

    var isLooseAlterationNumberCandidate: Bool {
        strokes.count == 1
            && bounds.width <= 18
            && bounds.height >= 8
            && bounds.height <= 34
    }

    var isLooseAlteredFiveFragmentCandidate: Bool {
        strokes.count <= 2
            && bounds.width <= 18
            && bounds.height >= 3
            && bounds.height <= 32
            && bounds.recognitionArea >= 8
    }

    var isStandaloneOneGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isOneGlyphCandidate
    }

    var isStandaloneThreeGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isThreeGlyphCandidate
    }

    var isSlashLikeSeparator: Bool {
        guard strokes.count == 1,
              let firstPoint = strokes[0].points.first,
              let lastPoint = strokes[0].points.last else {
            return false
        }

        let bounds = strokes[0].bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let slopeMagnitude = height / width
        let aspectRatio = width / height
        let dx = lastPoint.x - firstPoint.x
        let dy = lastPoint.y - firstPoint.y
        let diagonalAngleDegrees = strokes[0].diagonalAngleMagnitude
        let hasCleanSlashPath = strokes[0].horizontalDirectionChangeCount == 0
            || strokes[0].straightness >= 0.62

        return slopeMagnitude >= 0.65
            && slopeMagnitude <= 4.0
            && strokes[0].straightness >= 0.72
            && aspectRatio <= 0.82
            && hasCleanSlashPath
            && dx * dy < 0
            && diagonalAngleDegrees >= 38
            && diagonalAngleDegrees <= 82
            && width >= 4
            && height >= 8
            && (!strokes[0].hasEarlyTopHorizontalRun || strokes[0].straightness >= 0.70)
    }

    var isFlatGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first,
              let firstPoint = stroke.points.first,
              let lastPoint = stroke.points.last else {
            return false
        }

        let bounds = stroke.bounds
        let aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)
        let angleDegrees = atan2(lastPoint.y - firstPoint.y, lastPoint.x - firstPoint.x) * 180 / .pi

        return stroke.points.count >= 10
            && bounds.height >= 10
            && aspectRatio >= 0.42
            && aspectRatio <= 1.20
            && angleDegrees >= 42
            && angleDegrees <= 105
            && !stroke.hasEarlyTopHorizontalRun
            || stroke.points.count >= 7
            && bounds.width <= 12
            && bounds.height >= 8
            && aspectRatio >= 0.35
            && aspectRatio <= 1.20
            && angleDegrees >= 35
            && angleDegrees <= 115
            && !stroke.hasEarlyTopHorizontalRun
    }

    var isQualityOrExtensionGlyphCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDashMinorCandidate
            || stroke.isMinorMCandidate
            || stroke.isDiminishedCircleConstructionCandidate
            || stroke.isSevenCandidate
    }

    var isSuspendedSLikeCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSuspendedSLikeCandidate
    }

    var isSuspendedSLikeContextCandidate: Bool {
        isSuspendedSLikeCandidate
            || strokes.count == 1
            && bounds.width >= 4
            && bounds.width <= 18
            && bounds.height >= 12
            && bounds.height <= 32
            && bounds.recognitionArea >= 55
    }

    var isSuspendedULikeCandidate: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isSuspendedULikeCandidate
    }

    var isSuspendedULikeContextCandidate: Bool {
        isSuspendedULikeCandidate
            || strokes.count == 1
            && bounds.width >= 7
            && bounds.width <= 24
            && bounds.height >= 7
            && bounds.height <= 24
            && bounds.recognitionArea >= 60
    }

    var isLooseDominantSuspendedMiddleCandidate: Bool {
        isSuspendedULikeContextCandidate
            || strokes.count == 1
            && bounds.width >= 6
            && bounds.width <= 24
            && bounds.height >= 6
            && bounds.height <= 26
            && bounds.recognitionArea >= 48
    }

    var isSuspendedFourthLikeCandidate: Bool {
        if strokes.count == 1,
           let stroke = strokes.first {
            return stroke.isSuspendedFourthCandidate
        }

        guard strokes.count == 2 else {
            return false
        }

        let hasDownStem = strokes.contains { stroke in
            stroke.bounds.height >= 12
                && stroke.bounds.width <= max(8, stroke.bounds.height * 0.45)
                && stroke.straightness >= 0.45
                && abs(abs(stroke.angleDegrees) - 90) <= 40
        }
        let hasUpperArm = strokes.contains { stroke in
            stroke.bounds.minY <= bounds.minY + bounds.height * 0.45
                && stroke.bounds.width >= 5
                && stroke.bounds.height <= max(8, stroke.bounds.width * 0.95)
                && stroke.straightness >= 0.35
        }

        return hasDownStem
            && hasUpperArm
            && bounds.width >= 4
            && bounds.width <= 28
            && bounds.height >= 14
            && bounds.height <= 44
    }

    var isSharpGlyphCandidate: Bool {
        strokes.count >= 4
            && strokes.count <= 6
            && looseSharpVerticalStrokeCount >= 2
            && looseSharpHorizontalStrokeCount >= 1
            && bounds.width >= 8
            && bounds.height >= 12
    }

    var isPlusVerticalConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isPlusVerticalConstructionCandidate
    }

    var isPlusHorizontalConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isPlusHorizontalConstructionCandidate
    }

    var isDiminishedCircleConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isDiminishedCircleConstructionCandidate
    }

    var isHalfDiminishedSlashConstructionPart: Bool {
        guard strokes.count == 1,
              let stroke = strokes.first else {
            return false
        }

        return stroke.isHalfDiminishedSlashConstructionCandidate
    }

    var canMergeAsSharpFragment: Bool {
        !isRootBodyCandidate
            || isSharpGlyphCandidate
            || (strokes.count >= 2 && isSharpConstructionPart)
    }

    var looseSharpVerticalStrokeCount: Int {
        strokes.filter(\.isLooseSharpVerticalCandidate).count
    }

    var looseSharpHorizontalStrokeCount: Int {
        strokes.filter(\.isLooseSharpHorizontalCandidate).count
    }

    var hasSharpVerticalStroke: Bool {
        looseSharpVerticalStrokeCount > 0
    }

    var hasSharpHorizontalStroke: Bool {
        looseSharpHorizontalStrokeCount > 0
    }

    var isSharpConstructionPart: Bool {
        guard !strokes.isEmpty,
              strokes.allSatisfy({ $0.isSharpConstructionStrokeCandidate }) else {
            return false
        }

        let aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)

        return bounds.width <= max(26, bounds.height * 1.45)
            && bounds.height <= max(28, bounds.width * 3.2)
            && aspectRatio >= 0.04
            && aspectRatio <= 8.0
    }

    var isTallRootLikeSharpConstruction: Bool {
        strokes.count >= 2
            && hasSharpVerticalStroke
            && hasSharpHorizontalStroke
            && looseSharpVerticalStrokeCount <= 1
            && bounds.height > 23
            && bounds.width >= 10
    }

    var isPartialSharpConstruction: Bool {
        looseSharpVerticalStrokeCount >= 2
            || (hasSharpVerticalStroke && hasSharpHorizontalStroke)
    }

    var hasRootConstructionBar: Bool {
        strokes.contains { stroke in
            stroke.bounds.width >= 5
                && stroke.aspectRatio >= 1.6
                && stroke.straightness >= 0.50
                && stroke.horizontalAngleMagnitude <= 45
        }
    }

    var hasRootConstructionVerticalStem: Bool {
        strokes.contains { stroke in
            stroke.bounds.height >= 14
                && stroke.bounds.height / max(stroke.bounds.width, 1) >= 1.90
                && stroke.straightness >= 0.50
                && abs(abs(stroke.angleDegrees) - 90) <= 32
        }
    }

    var hasRootConstructionBody: Bool {
        bounds.height >= 14
            && bounds.width >= 8
            && bounds.recognitionArea >= 140
    }

    func merged(with other: MutableInkCluster) -> MutableInkCluster {
        MutableInkCluster(
            strokes: strokes + other.strokes,
            originalIndexes: originalIndexes + other.originalIndexes
        )
    }
}

extension InkBounds {
    var recognitionArea: Double {
        max(width, 1) * max(height, 1)
    }

    func horizontalGap(to other: InkBounds) -> Double {
        if maxX < other.minX {
            return other.minX - maxX
        }

        if other.maxX < minX {
            return minX - other.maxX
        }

        return 0
    }

    func verticalMiss(to other: InkBounds) -> Double {
        if maxY < other.minY {
            return other.minY - maxY
        }

        if other.maxY < minY {
            return minY - other.maxY
        }

        return 0
    }

    func horizontalOverlap(with other: InkBounds) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }

    func verticalOverlap(with other: InkBounds) -> Double {
        max(0, min(maxY, other.maxY) - max(minY, other.minY))
    }

    var recognitionMidX: Double {
        minX + width / 2
    }

    var recognitionMidY: Double {
        minY + height / 2
    }
}

extension InkStroke {
    var straightness: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        let pathLength = zip(points, points.dropFirst())
            .map { start, end in
                start.clusterDistance(to: end)
            }
            .reduce(0, +)
        guard pathLength > 0 else {
            return 0
        }

        return firstPoint.clusterDistance(to: lastPoint) / pathLength
    }

    var aspectRatio: Double {
        max(bounds.width, 1) / max(bounds.height, 1)
    }

    var isDashMinorCandidate: Bool {
        let standardDash = bounds.width >= 5
            && aspectRatio >= 1.80
            && straightness >= 0.50
            && abs(angleDegrees) <= 40
        let compactDash = points.count >= 3
            && points.count <= 7
            && bounds.width >= 4
            && bounds.height <= max(2.5, bounds.width * 0.30)
            && aspectRatio >= 2.20
            && straightness >= 0.30
            && abs(angleDegrees) <= 32
        let slantedCompactDash = points.count >= 3
            && points.count <= 9
            && bounds.width >= 6
            && bounds.height <= max(7, bounds.width * 0.70)
            && aspectRatio >= 1.35
            && straightness >= 0.40
            && abs(angleDegrees) <= 42

        return standardDash || compactDash || slantedCompactDash
    }

    var isMinorMCandidate: Bool {
        points.count >= 16
            && bounds.width >= 12
            && bounds.height >= 8
            && aspectRatio >= 0.70
            && aspectRatio <= 2.35
            && straightness <= 0.60
            && !hasEarlyTopHorizontalRun
    }

    var isLooseMinorMSuffixCandidate: Bool {
        points.count >= 12
            && bounds.width >= 10
            && bounds.height >= 8
            && aspectRatio >= 0.55
            && aspectRatio <= 2.60
            && straightness <= 0.72
            && !hasEarlyTopHorizontalRun
    }

    var isSevenCandidate: Bool {
        let standardSeven = points.count >= 7
            && bounds.width >= 5
            && bounds.height >= 8
            && aspectRatio >= 0.25
            && aspectRatio <= 1.65
            && angleDegrees >= 35
            && angleDegrees <= 105
            && hasEarlyTopHorizontalRun
        let trailingSeven = points.count >= 7
            && bounds.width >= 5
            && bounds.height >= 8
            && aspectRatio >= 0.25
            && aspectRatio <= 1.65
            && angleDegrees >= 35
            && angleDegrees <= 105
            && points.last.map { $0.y >= bounds.minY + bounds.height * 0.70 } == true

        return standardSeven || trailingSeven
    }

    var isOneGlyphCandidate: Bool {
        points.count >= 4
            && bounds.height >= 8
            && bounds.width <= max(6, bounds.height * 0.35)
            && straightness >= 0.60
            && abs(abs(angleDegrees) - 90) <= 28
    }

    var isThreeGlyphCandidate: Bool {
        points.count >= 10
            && bounds.width >= 8
            && bounds.height >= 12
            && bounds.height <= 28
            && aspectRatio >= 0.42
            && aspectRatio <= 1.45
            && straightness >= 0.18
            && straightness <= 0.70
            && angleDegrees >= 35
            && angleDegrees <= 115
            && (horizontalDirectionChangeCount >= 2 || hasEarlyTopHorizontalRun)
    }

    var isDominantFlatNineStemFragment: Bool {
        points.count >= 5
            && bounds.height >= 14
            && bounds.height <= 38
            && bounds.width <= max(10, bounds.height * 0.42)
            && straightness >= 0.48
            && abs(abs(angleDegrees) - 90) <= 38
    }

    var isDominantFlatNineCurvedFragment: Bool {
        points.count >= 8
            && bounds.width >= 4.5
            && bounds.width <= 16
            && bounds.height >= 10
            && bounds.height <= 30
            && aspectRatio >= 0.18
            && aspectRatio <= 1.25
            && straightness <= 0.58
            && (!hasEarlyTopHorizontalRun || straightness <= 0.40 || aspectRatio <= 0.70)
    }

    var isDominantFlatNineTailFragment: Bool {
        points.count >= 6
            && bounds.height >= 17
            && bounds.height <= 38
            && bounds.width <= 16
            && aspectRatio <= 0.92
            && straightness >= 0.48
            && angleDegrees >= 50
            && angleDegrees <= 125
    }

    var isNineGlyphCandidate: Bool {
        points.count >= 8
            && bounds.width >= 4
            && bounds.width <= 18
            && bounds.height >= 10
            && bounds.height <= 34
            && aspectRatio >= 0.16
            && aspectRatio <= 1.20
            && (straightness <= 0.72 || angleDegrees >= 35 && angleDegrees <= 125)
            && !hasEarlyTopHorizontalRun
    }

    var isFiveGlyphCandidate: Bool {
        points.count >= 5
            && bounds.width >= 4
            && bounds.width <= 20
            && bounds.height >= 8
            && bounds.height <= 34
            && aspectRatio >= 0.18
            && aspectRatio <= 1.55
            && points.last.map { $0.y >= bounds.minY + bounds.height * 0.55 } == true
            && (hasEarlyTopHorizontalRun || horizontalDirectionChangeCount >= 1 || straightness <= 0.72)
    }

    var isSuspendedFourthCandidate: Bool {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return false
        }

        let startX = normalizedXRatio(of: firstPoint)
        let startY = normalizedYRatio(of: firstPoint)
        let endY = normalizedYRatio(of: lastPoint)
        let descendsIntoStem = endY >= 0.62
            && lastPoint.y >= firstPoint.y + bounds.height * 0.40
        let upperPoints = points.filter { point in
            normalizedYRatio(of: point) <= 0.45
        }
        let upperMaxX = upperPoints.map(normalizedXRatio(of:)).max() ?? startX
        let upperMinX = upperPoints.map(normalizedXRatio(of:)).min() ?? startX
        let hasUpperArmOrCorner = hasEarlyTopHorizontalRun
            || upperMaxX >= 0.70
            || upperMinX <= 0.30

        return points.count >= 5
            && bounds.width >= 3
            && bounds.width <= 24
            && bounds.height >= 10
            && bounds.height <= 42
            && aspectRatio >= 0.10
            && aspectRatio <= 1.15
            && startY <= 0.48
            && descendsIntoStem
            && hasUpperArmOrCorner
    }

    var isOpeningParenthesizedAlterationWrapperCandidate: Bool {
        isParenthesizedAlterationWrapperCandidate(curvingToward: .left)
    }

    var isLooseOpeningParenthesizedAlterationWrapperCandidate: Bool {
        points.count >= 4
            && bounds.height >= 14
            && bounds.height <= 38
            && bounds.width <= max(8, bounds.height * 0.40)
            && straightness >= 0.35
            && angleDegrees >= 48
            && angleDegrees <= 126
    }

    var isClosingParenthesizedAlterationWrapperCandidate: Bool {
        isParenthesizedAlterationWrapperCandidate(curvingToward: .right)
    }

    var isLooseClosingParenthesizedAlterationWrapperCandidate: Bool {
        isClosingParenthesizedAlterationWrapperCandidate
            || points.count >= 8
            && bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 4.5
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.85
            && straightness >= 0.15
            && straightness <= 0.98
            && normalizedXRatio(of: points[0]) <= 0.65
            && normalizedXRatio(of: points[points.count - 1]) <= 0.75
            && points[points.count - 1].y >= bounds.minY + bounds.height * 0.55
    }

    var isTrailingParenthesizedAlterationWrapperCandidate: Bool {
        points.count >= 5
            && bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 2
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.90
            && straightness >= 0.12
    }

    private enum ParenthesisCurveDirection {
        case left
        case right
    }

    private func isParenthesizedAlterationWrapperCandidate(
        curvingToward direction: ParenthesisCurveDirection
    ) -> Bool {
        guard points.count >= 8 else {
            return false
        }

        let middlePoints = points.filter { point in
            let yRatio = normalizedYRatio(of: point)
            return yRatio >= 0.22 && yRatio <= 0.78
        }
        let startX = normalizedXRatio(of: points[0])
        let endX = normalizedXRatio(of: points[points.count - 1])
        let middleMinX = middlePoints
            .map(normalizedXRatio(of:))
            .min() ?? startX
        let middleMaxX = middlePoints
            .map(normalizedXRatio(of:))
            .max() ?? startX
        let curvesLeft = startX >= 0.50
            && endX >= 0.38
            && middleMinX <= 0.55
        let curvesRight = startX <= 0.55
            && endX <= 0.70
            && middleMaxX >= 0.45

        return bounds.height >= 16
            && bounds.height <= 42
            && bounds.width >= 4.5
            && bounds.width <= 18
            && aspectRatio >= 0.08
            && aspectRatio <= 0.78
            && straightness >= 0.15
            && straightness <= 0.98
            && (direction == .left ? curvesLeft : curvesRight)
    }

    var isLooseSharpVerticalCandidate: Bool {
        bounds.height >= 8
            && bounds.width <= max(6, bounds.height * 0.45)
            && straightness >= 0.45
            && abs(abs(angleDegrees) - 90) <= 38
    }

    var isLooseSharpHorizontalCandidate: Bool {
        bounds.width >= 5
            && bounds.height <= max(7, bounds.width * 0.68)
            && straightness >= 0.45
            && abs(angleDegrees) <= 38
    }

    var isSharpConstructionStrokeCandidate: Bool {
        isLooseSharpVerticalCandidate || isLooseSharpHorizontalCandidate
    }

    var isPlusVerticalConstructionCandidate: Bool {
        bounds.height >= 7
            && bounds.height <= 30
            && bounds.width <= max(7, bounds.height * 0.50)
            && straightness >= 0.52
            && abs(abs(angleDegrees) - 90) <= 36
    }

    var isPlusHorizontalConstructionCandidate: Bool {
        bounds.width >= 7
            && bounds.width <= 30
            && bounds.height <= max(7, bounds.width * 0.55)
            && straightness >= 0.52
            && abs(angleDegrees) <= 38
    }

    var isDiminishedCircleConstructionCandidate: Bool {
        bounds.width >= 4
            && bounds.width <= 17
            && bounds.height >= 4
            && bounds.height <= 20
            && aspectRatio >= 0.42
            && aspectRatio <= 1.55
            && points.count >= 8
            && straightness <= 0.28
            && endpointClosureRatio <= 0.82
            && (startsLikeWrittenCircle || isTinyLooseCircle)
            && !looksLikeTriangleReturn
            && !hasEarlyTopHorizontalRun
    }

    var isHalfDiminishedSlashConstructionCandidate: Bool {
        bounds.width >= 4
            && bounds.height >= 4
            && straightness >= 0.54
            && aspectRatio >= 0.35
            && aspectRatio <= 2.80
            && diagonalAngleMagnitude >= 20
            && diagonalAngleMagnitude <= 80
            && (!hasEarlyTopHorizontalRun || abs(angleDegrees) >= 100)
    }

    var isLooseSlashBassSeparatorCandidate: Bool {
        let aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)

        return bounds.width >= 4
            && bounds.height >= 8
            && aspectRatio >= 0.18
            && aspectRatio <= 0.82
            && straightness >= 0.38
            && (points[points.count - 1].x - points[0].x) * (points[points.count - 1].y - points[0].y) < 0
            && diagonalAngleMagnitude >= 38
            && diagonalAngleMagnitude <= 82
            && (!hasEarlyTopHorizontalRun || straightness >= 0.70 || abs(angleDegrees) >= 100)
    }

    var isSuspendedSLikeCandidate: Bool {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return false
        }

        let startX = normalizedXRatio(of: firstPoint)
        let startY = normalizedYRatio(of: firstPoint)
        let endX = normalizedXRatio(of: lastPoint)
        let endY = normalizedYRatio(of: lastPoint)
        let descendsThroughBody = endY >= 0.58
            && lastPoint.y >= firstPoint.y + bounds.height * 0.45
        let curvesBackLeft = endX <= startX - 0.12
            || normalizedMinX(belowYRatio: 0.45) <= startX - 0.16
        let narrowTrailingS = aspectRatio <= 0.78
            && straightness >= 0.42
            && abs(abs(angleDegrees) - 90) <= 36
        let rootSizedOpenC = startX >= 0.82
            && endX >= 0.82
            && hasLeftThenRightHook
            && straightness <= 0.65

        return points.count >= 8
            && bounds.width >= 4
            && bounds.width <= 22
            && bounds.height >= 14
            && bounds.height <= 30
            && aspectRatio >= 0.18
            && aspectRatio <= 1.05
            && straightness >= 0.20
            && straightness <= 0.86
            && startY <= 0.35
            && descendsThroughBody
            && !hasEarlyTopHorizontalRun
            && !rootSizedOpenC
            && (curvesBackLeft || narrowTrailingS)
    }

    var isSuspendedULikeCandidate: Bool {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return false
        }

        let startX = normalizedXRatio(of: firstPoint)
        let startY = normalizedYRatio(of: firstPoint)
        let endX = normalizedXRatio(of: lastPoint)
        let endY = normalizedYRatio(of: lastPoint)
        let reachesLowerBody = normalizedMaxY >= 0.82
        let movesLeftToRight = endX >= startX + 0.42
        let shallowCup = angleDegrees >= 12
            && angleDegrees <= 58
            && straightness <= 0.58

        return points.count >= 12
            && bounds.width >= 8
            && bounds.width <= 22
            && bounds.height >= 8
            && bounds.height <= 22
            && aspectRatio >= 0.55
            && aspectRatio <= 1.75
            && startX <= 0.35
            && startY <= 0.60
            && endX >= 0.62
            && endY >= 0.55
            && reachesLowerBody
            && movesLeftToRight
            && shallowCup
            && !hasEarlyTopHorizontalRun
    }

    var hasEarlyTopHorizontalRun: Bool {
        guard points.count >= 4 else {
            return false
        }

        let earlyCount = max(3, Int((Double(points.count) * 0.45).rounded(.up)))
        let earlyPoints = Array(points.prefix(min(points.count, earlyCount)))
        let earlyBounds = InkBounds.enclosing(earlyPoints)
        let averageY = earlyPoints.map(\.y).reduce(0, +) / Double(earlyPoints.count)

        return earlyBounds.width >= bounds.width * 0.45
            && earlyBounds.height <= max(4.5, bounds.height * 0.45)
            && averageY <= bounds.minY + bounds.height * 0.38
    }

    var horizontalDirectionChangeCount: Int {
        var previousDirection = 0
        var changeCount = 0

        for (currentPoint, nextPoint) in zip(points, points.dropFirst()) {
            let deltaX = nextPoint.x - currentPoint.x
            guard abs(deltaX) >= 2 else {
                continue
            }

            let direction = deltaX > 0 ? 1 : -1
            if previousDirection != 0, direction != previousDirection {
                changeCount += 1
            }
            previousDirection = direction
        }

        return changeCount
    }

    var angleDegrees: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        return atan2(lastPoint.y - firstPoint.y, lastPoint.x - firstPoint.x) * 180 / .pi
    }

    var horizontalAngleMagnitude: Double {
        let absoluteAngle = abs(angleDegrees)
        return min(absoluteAngle, abs(180 - absoluteAngle))
    }

    var endpointClosureRatio: Double {
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return 0
        }

        return firstPoint.clusterDistance(to: lastPoint) / max(bounds.width, bounds.height, 1)
    }

    var startsLikeWrittenCircle: Bool {
        guard let firstPoint = points.first else {
            return false
        }

        let startYRatio = (firstPoint.y - bounds.minY) / max(bounds.height, 1)
        return startYRatio <= 0.42 || endpointClosureRatio <= 0.45
    }

    var isTinyLooseCircle: Bool {
        bounds.width <= 10
            && bounds.height <= 8
            && endpointClosureRatio <= 0.62
    }

    var looksLikeTriangleReturn: Bool {
        guard let lastPoint = points.last else {
            return false
        }

        let endXRatio = (lastPoint.x - bounds.minX) / max(bounds.width, 1)
        let endYRatio = (lastPoint.y - bounds.minY) / max(bounds.height, 1)

        return hasLowerBodyThenUpperPeakReturn
            && angleDegrees >= 55
            && angleDegrees <= 130
            && endXRatio <= 0.62
            && endYRatio >= 0.55
    }

    var diagonalAngleMagnitude: Double {
        let absoluteAngle = abs(angleDegrees)
        return min(absoluteAngle, abs(180 - absoluteAngle))
    }

    func normalizedXRatio(of point: InkPoint) -> Double {
        (point.x - bounds.minX) / max(bounds.width, 1)
    }

    func normalizedYRatio(of point: InkPoint) -> Double {
        (point.y - bounds.minY) / max(bounds.height, 1)
    }

    func normalizedMinX(belowYRatio ratio: Double) -> Double {
        let limit = bounds.minY + bounds.height * ratio
        let normalizedValues = points
            .filter { $0.y >= limit }
            .map(normalizedXRatio(of:))

        return normalizedValues.min() ?? points.last.map(normalizedXRatio(of:)) ?? 0
    }

    var normalizedMaxY: Double {
        points
            .map(normalizedYRatio(of:))
            .max() ?? points.last.map(normalizedYRatio(of:)) ?? 0
    }

    var hasLeftThenRightHook: Bool {
        guard points.count >= 5 else {
            return false
        }

        let minX = points.map(\.x).min() ?? bounds.minX
        guard let firstPoint = points.first,
              let lastPoint = points.last else {
            return false
        }

        let startAndEndMinX = min(firstPoint.x, lastPoint.x)

        return minX <= startAndEndMinX - max(2, bounds.width * 0.25)
            && lastPoint.x >= minX + bounds.width * 0.45
    }

    var hasLowerBodyThenUpperPeakReturn: Bool {
        guard points.count >= 8 else {
            return false
        }

        let lowerBodyLimit = bounds.minY + bounds.height * 0.62
        let upperPeakLimit = bounds.minY + bounds.height * 0.32
        var sawLowerBody = false

        for (index, point) in points.enumerated() where index >= max(1, points.count / 8) {
            if point.y >= lowerBodyLimit {
                sawLowerBody = true
            } else if sawLowerBody, point.y <= upperPeakLimit {
                return true
            }
        }

        return false
    }
}

extension InkPoint {
    func clusterDistance(to other: InkPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
