import Foundation

struct GestureTemplate: Hashable {
    var text: String
    var strokes: [InkStroke]

    init(text: String, strokes: [InkStroke]) {
        self.text = text
        self.strokes = strokes
    }
}

struct GestureTemplateRecognizerConfiguration: Hashable {
    var samplePointCount: Int
    var aspectRatioWeight: Double
    var strokeCountWeight: Double

    static let chordGlyphs = GestureTemplateRecognizerConfiguration(
        samplePointCount: 48,
        aspectRatioWeight: 0.18,
        strokeCountWeight: 0.12
    )
}

struct GestureTemplateRecognizer {
    var configuration: GestureTemplateRecognizerConfiguration

    init(configuration: GestureTemplateRecognizerConfiguration = .chordGlyphs) {
        self.configuration = configuration
    }

    func rankedCandidates(
        for cluster: InkCluster,
        templates: [GestureTemplate],
        limit: Int? = nil
    ) -> [GlyphCandidate] {
        guard let normalizedInput = NormalizedGesture(
            strokes: cluster.strokes,
            samplePointCount: configuration.samplePointCount
        ) else {
            return []
        }
        let inputFeatures = RootGlyphFeatures(cluster: cluster)

        var candidatesByText = templates.reduce(into: [String: GlyphCandidate]()) { bestCandidates, template in
            if template.text == "(",
               !isParenthesisLike(inputFeatures, direction: .left) {
                return
            }

            if template.text == ")",
               !isParenthesisLike(inputFeatures, direction: .right) {
                return
            }

            if template.text == "s",
               !isSuspendedSLike(inputFeatures),
               !isHandwrittenSuspendedSLike(inputFeatures) {
                return
            }

            if template.text == "u",
               !isSuspendedULike(inputFeatures),
               !isHandwrittenSuspendedULike(inputFeatures) {
                return
            }

            if template.text == "a",
               !isAlteredALike(inputFeatures) {
                return
            }

            if template.text == "l",
               !isAlteredLLike(inputFeatures) {
                return
            }

            if template.text == "t",
               !isAlteredTLike(inputFeatures) {
                return
            }

            guard let normalizedTemplate = NormalizedGesture(
                strokes: template.strokes,
                samplePointCount: configuration.samplePointCount
            ) else {
                return
            }

            let distance = distance(from: normalizedInput, to: normalizedTemplate)
            let confidence = 1 / (1 + distance * 2.4)
            let candidate = GlyphCandidate(
                text: template.text,
                confidence: confidence,
                source: .template
            )

            if let currentBestCandidate = bestCandidates[template.text],
               currentBestCandidate.confidence >= candidate.confidence {
                return
            }

            bestCandidates[template.text] = candidate
        }

        for candidate in heuristicCandidates(for: cluster) {
            if let currentBestCandidate = candidatesByText[candidate.text],
               currentBestCandidate.confidence >= candidate.confidence {
                continue
            }

            candidatesByText[candidate.text] = candidate
        }

        let candidates = candidatesByText.values.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }

        if let limit {
            return Array(candidates.prefix(limit))
        }

        return candidates
    }

    private enum ParenthesisDirection {
        case left
        case right
    }

    private func isParenthesisLike(
        _ features: RootGlyphFeatures,
        direction: ParenthesisDirection
    ) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let middlePoints = stroke.points.filter { point in
            let yRatio = stroke.normalizedYRatio(of: point)
            return yRatio >= 0.22 && yRatio <= 0.78
        }
        let middleMinX = middlePoints
            .map { stroke.normalizedXRatio(of: $0) }
            .min() ?? startX
        let middleMaxX = middlePoints
            .map { stroke.normalizedXRatio(of: $0) }
            .max() ?? startX

        let curvesLeft = startX >= 0.50
            && endX >= 0.50
            && middleMinX <= 0.45
        let curvesRight = startX <= 0.50
            && endX <= 0.50
            && middleMaxX >= 0.55

        return stroke.pointCount >= 4
            && stroke.bounds.height >= 12
            && stroke.bounds.width >= 3
            && stroke.aspectRatio >= 0.10
            && stroke.aspectRatio <= 0.78
            && stroke.straightness >= 0.42
            && stroke.straightness <= 0.94
            && stroke.horizontalDirectionChangeCount >= 1
            && !stroke.hasEarlyTopHorizontalRun
            && (direction == .left ? curvesLeft : curvesRight)
    }

    private func isSuspendedSLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)

        return stroke.pointCount >= 5
            && features.aspectRatio >= 0.45
            && features.aspectRatio <= 1.10
            && stroke.straightness >= 0.25
            && stroke.straightness <= 0.72
            && stroke.horizontalDirectionChangeCount >= 2
            && startX >= 0.62
            && startY <= 0.35
            && endX <= 0.38
            && endY >= 0.55
            && !stroke.hasLowerThenUpperReturn
            && !stroke.hasVerticalTailAndLoopReturn
    }

    private func isSuspendedULike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)
        let hasLowBody = stroke.points.contains { point in
            stroke.normalizedYRatio(of: point) >= 0.74
                && stroke.normalizedXRatio(of: point) >= 0.18
                && stroke.normalizedXRatio(of: point) <= 0.82
        }

        return stroke.pointCount >= 4
            && features.aspectRatio >= 0.70
            && features.aspectRatio <= 1.70
            && stroke.horizontalDirectionChangeCount <= 1
            && startX <= 0.35
            && startY <= 0.35
            && endX >= 0.65
            && endY <= 0.40
            && hasLowBody
            && !stroke.hasVerticalTailAndLoopReturn
    }

    private func isAlteredALike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 6
            && stroke.bounds.width >= 10
            && stroke.bounds.height >= 14
            && stroke.aspectRatio >= 0.45
            && stroke.aspectRatio <= 1.60
            && stroke.straightness <= 0.78
    }

    private func isAlteredLLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.bounds.height >= 18
            && stroke.bounds.width <= max(5, stroke.bounds.height * 0.25)
            && stroke.straightness >= 0.70
            && abs(abs(stroke.angleDegrees) - 90) <= 24
    }

    private func isAlteredTLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount >= 2 else {
            return false
        }

        return features.hasLooseVerticalStroke
            && features.looseHorizontalStrokeCount >= 1
            && features.bounds.width >= 8
            && features.bounds.height >= 12
            && features.aspectRatio >= 0.25
            && features.aspectRatio <= 1.25
    }

    private func heuristicCandidates(for cluster: InkCluster) -> [GlyphCandidate] {
        let features = RootGlyphFeatures(cluster: cluster)
        var candidates = accidentalCandidates(features)
        candidates += qualityAndExtensionCandidates(features)

        if isConstructedRootALike(features) {
            candidates.append(heuristicCandidate("A", confidence: 0.998))
        }

        switch features.strokeCount {
        case 1:
            candidates += oneStrokeRootCandidates(features)
        case 2:
            candidates += twoStrokeRootCandidates(features)
        case 3:
            candidates += threeStrokeRootCandidates(features)
        case 4:
            candidates += fourStrokeRootCandidates(features)
        default:
            break
        }

        return candidates
    }

    private func qualityAndExtensionCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        var candidates: [GlyphCandidate] = []

        if isDashMinorLike(features) {
            candidates.append(heuristicCandidate("-", confidence: 0.995))
        }

        if isMinorMLike(features) {
            candidates.append(heuristicCandidate("m", confidence: 0.99))
        }

        if isDiminishedCircleLike(features) {
            let confidence = isOpenDescendingFlatLoopLike(features) ? 0.965 : 0.9995
            candidates.append(heuristicCandidate("°", confidence: confidence))
        }

        if isPlusLike(features) {
            candidates.append(heuristicCandidate("+", confidence: 0.999))
        }

        if isHalfDiminishedLike(features) {
            candidates.append(heuristicCandidate("ø", confidence: 0.999))
        }

        if isTriangleMajorLike(features) {
            candidates.append(heuristicCandidate("△", confidence: 0.999))
        }

        if isChordRepeatDotLike(features) {
            let confidence = isOpenDescendingFlatLoopLike(features) ? 0.955 : 0.997
            candidates.append(heuristicCandidate("•", confidence: confidence))
        }

        if isSixLike(features) {
            candidates.append(heuristicCandidate("6", confidence: 0.995))
        }

        if isSevenLike(features) {
            candidates.append(heuristicCandidate("7", confidence: 0.985))
        }

        if isNineLike(features) {
            candidates.append(heuristicCandidate("9", confidence: 0.999))
        } else if isOpenHandwrittenNineLike(features) {
            candidates.append(heuristicCandidate("9", confidence: 0.997))
        } else if isCompactAlteredNineLike(features) {
            candidates.append(heuristicCandidate("9", confidence: 0.55))
        }

        if isHandwrittenSuspendedSLike(features) {
            candidates.append(heuristicCandidate("s", confidence: 0.55))
        }

        if isHandwrittenSuspendedULike(features) {
            candidates.append(heuristicCandidate("u", confidence: 0.55))
        }

        if isSlashSeparatorLike(features) {
            candidates.append(heuristicCandidate("/", confidence: 0.72))
        }

        if isOneLike(features) {
            candidates.append(heuristicCandidate("1", confidence: 0.996))
        }

        if isThreeLike(features) {
            candidates.append(heuristicCandidate("3", confidence: 0.997))
        }

        if let fiveConfidence = fiveLikeConfidence(features) {
            candidates.append(heuristicCandidate("5", confidence: fiveConfidence))
        }

        return candidates
    }

    private func isDashMinorLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let standardDash = stroke.bounds.width >= 5
            && stroke.aspectRatio >= 1.80
            && stroke.straightness >= 0.55
            && abs(stroke.angleDegrees) <= 35
        let compactDash = stroke.pointCount >= 3
            && stroke.pointCount <= 7
            && stroke.bounds.width >= 4
            && stroke.bounds.height <= max(2.5, stroke.bounds.width * 0.30)
            && stroke.aspectRatio >= 2.20
            && stroke.straightness >= 0.30
            && abs(stroke.angleDegrees) <= 32
        let slantedCompactDash = stroke.pointCount >= 3
            && stroke.pointCount <= 9
            && stroke.bounds.width >= 6
            && stroke.bounds.height <= max(7, stroke.bounds.width * 0.70)
            && stroke.aspectRatio >= 1.35
            && stroke.straightness >= 0.40
            && abs(stroke.angleDegrees) <= 42
        let ultraCompactDash = stroke.pointCount >= 2
            && stroke.pointCount <= 3
            && stroke.bounds.width >= 1.2
            && stroke.bounds.height <= 2.2
            && stroke.aspectRatio >= 1.10
            && stroke.straightness >= 0.85
            && abs(stroke.angleDegrees) <= 42

        return standardDash || compactDash || slantedCompactDash || ultraCompactDash
    }

    private func isMinorMLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 12
            && stroke.bounds.width >= 12
            && stroke.bounds.height >= 8
            && stroke.aspectRatio >= 0.70
            && stroke.aspectRatio <= 2.25
            && stroke.straightness <= 0.56
            && abs(stroke.angleDegrees) <= 55
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isTriangleMajorLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let compactClosedTriangle = stroke.pointCount >= 4
            && stroke.endpointClosureRatio <= 0.18
        let handwrittenTriangle = stroke.pointCount >= 14
            && stroke.straightness <= 0.32
            && stroke.angleDegrees >= 60
            && stroke.angleDegrees <= 135
            && stroke.hasLowerBodyThenUpperPeakReturn
            && stroke.normalizedXRatio(of: stroke.endPoint) <= 0.58
            && stroke.normalizedYRatio(of: stroke.endPoint) >= 0.55

        return stroke.bounds.width >= 7
            && stroke.bounds.height >= 11
            && stroke.bounds.height <= 26
            && stroke.aspectRatio >= 0.40
            && stroke.aspectRatio <= 1.10
            && !stroke.hasEarlyTopHorizontalRun
            && (compactClosedTriangle || handwrittenTriangle)
    }

    private func isDiminishedCircleLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return isDiminishedCircleStroke(stroke)
    }

    private func isChordRepeatDotLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 2
            && stroke.bounds.width >= 2
            && stroke.bounds.width <= 18
            && stroke.bounds.height >= 2
            && stroke.bounds.height <= 18
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 1.85
            && stroke.endpointClosureRatio <= 0.90
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isHalfDiminishedLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 2 else {
            return false
        }

        let circleStroke = features.strokes.first(where: isDiminishedCircleStroke(_:))
        let slashStroke = features.strokes.first { stroke in
            isHalfDiminishedSlashStroke(stroke)
        }

        guard circleStroke != nil, slashStroke != nil else {
            return false
        }

        return features.bounds.width <= 26
            && features.bounds.height <= 26
            && features.aspectRatio >= 0.45
            && features.aspectRatio <= 1.80
    }

    private func isPlusLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 2,
              let verticalStroke = features.strokes.first(where: \.isLooseVertical),
              let horizontalStroke = features.strokes.first(where: \.isLooseHorizontal) else {
            return false
        }

        let verticalCenterX = verticalStroke.bounds.recognitionMidX
        let horizontalCenterY = horizontalStroke.bounds.recognitionMidY
        let crossesHorizontalStroke = horizontalStroke.bounds.minX - 2 <= verticalCenterX
            && verticalCenterX <= horizontalStroke.bounds.maxX + 2
        let crossesVerticalStroke = verticalStroke.bounds.minY - 2 <= horizontalCenterY
            && horizontalCenterY <= verticalStroke.bounds.maxY + 2

        return features.bounds.width >= 7
            && features.bounds.width <= 28
            && features.bounds.height >= 7
            && features.bounds.height <= 30
            && features.aspectRatio >= 0.35
            && features.aspectRatio <= 1.90
            && crossesHorizontalStroke
            && crossesVerticalStroke
    }

    private func isDiminishedCircleStroke(_ stroke: RootStrokeFeatures) -> Bool {
        let compactLoop = stroke.bounds.width >= 4
            && stroke.bounds.width <= 17
            && stroke.bounds.height >= 4
            && stroke.bounds.height <= 20
        let roundEnough = stroke.aspectRatio >= 0.42
            && stroke.aspectRatio <= 1.55
        let loopedPath = stroke.pointCount >= 8
            && stroke.straightness <= 0.26
            && stroke.endpointClosureRatio <= 0.82
        let tinyLooseCircle = stroke.bounds.width <= 10
            && stroke.bounds.height <= 8
            && stroke.endpointClosureRatio <= 0.62
        let startsLikeWrittenCircle = stroke.normalizedYRatio(of: stroke.startPoint) <= 0.42
            || stroke.endpointClosureRatio <= 0.45
            || tinyLooseCircle
        let looksLikeTriangleReturn = stroke.hasLowerBodyThenUpperPeakReturn
            && stroke.angleDegrees >= 55
            && stroke.angleDegrees <= 130
            && stroke.normalizedXRatio(of: stroke.endPoint) <= 0.62
            && stroke.normalizedYRatio(of: stroke.endPoint) >= 0.55

        return compactLoop
            && roundEnough
            && loopedPath
            && startsLikeWrittenCircle
            && !looksLikeTriangleReturn
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isHalfDiminishedSlashStroke(_ stroke: RootStrokeFeatures) -> Bool {
        let diagonalAngle = stroke.diagonalAngleMagnitude

        return stroke.bounds.width >= 4
            && stroke.bounds.height >= 4
            && stroke.straightness >= 0.54
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 2.60
            && diagonalAngle >= 20
            && diagonalAngle <= 80
            && (!stroke.hasEarlyTopHorizontalRun || abs(stroke.angleDegrees) >= 100)
    }

    private func isSixLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startsNearTop = stroke.startPoint.y <= stroke.bounds.minY + stroke.bounds.height * 0.35
        let reachesLowerBody = stroke.points.contains { point in
            point.y >= stroke.bounds.minY + stroke.bounds.height * 0.70
        }
        let hasLoopTurn = stroke.horizontalDirectionChangeCount >= 1
        let startXRatio = stroke.normalizedXRatio(of: stroke.startPoint)
        let upperRightReach = stroke.normalizedMaxX(aboveYRatio: 0.45) >= 0.85
        let lowerMinX = stroke.normalizedMinX(belowYRatio: 0.55)
        let lowerMaxX = stroke.normalizedMaxX(belowYRatio: 0.55)
        let lowerWideLoop = lowerMinX <= 0.12
            && lowerMaxX >= 0.80
            && lowerMaxX - lowerMinX >= 0.68
        let hasSixLoopShape = upperRightReach || (lowerWideLoop && startXRatio >= 0.12)

        return stroke.pointCount >= 10
            && stroke.bounds.width >= 7
            && stroke.bounds.height >= 17
            && stroke.bounds.height <= 24
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 1.20
            && stroke.straightness >= 0.10
            && stroke.straightness <= 0.65
            && stroke.angleDegrees >= 58
            && stroke.angleDegrees <= 115
            && startsNearTop
            && reachesLowerBody
            && hasLoopTurn
            && hasSixLoopShape
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isSevenLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let standardSeven = stroke.pointCount >= 7
            && stroke.bounds.width >= 5
            && stroke.bounds.height >= 8
            && stroke.aspectRatio >= 0.25
            && stroke.aspectRatio <= 1.65
            && stroke.endPoint.y >= stroke.startPoint.y + stroke.bounds.height * 0.25
            && stroke.hasEarlyTopHorizontalRun
        let compactSeven = stroke.pointCount >= 5
            && stroke.bounds.width >= 5
            && stroke.bounds.height >= 6.5
            && stroke.bounds.height <= 18
            && stroke.aspectRatio >= 0.55
            && stroke.aspectRatio <= 1.65
            && stroke.endPoint.y >= stroke.startPoint.y + stroke.bounds.height * 0.45
            && stroke.hasEarlyTopHorizontalRun

        return standardSeven || compactSeven
    }

    private func isNineLike(_ features: RootGlyphFeatures) -> Bool {
        if isTwoStrokeNineLike(features) {
            return true
        }

        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let upperLoopBounds = stroke.upperLoopBounds
        let hasUpperLoopBody = upperLoopBounds.width >= 3.5
            && upperLoopBounds.height >= max(4, stroke.bounds.height * 0.22)
        let startsNearTop = stroke.startPoint.y <= stroke.bounds.minY + stroke.bounds.height * 0.35
        let descendsIntoTail = stroke.endPoint.y >= stroke.bounds.minY + stroke.bounds.height * 0.62
        let compactTopCurl = stroke.aspectRatio <= 0.38
            && upperLoopBounds.height >= max(5, stroke.bounds.height * 0.25)
            && stroke.leftCurlDepthFromStart >= max(1.5, upperLoopBounds.width * 0.25)
        let hasNineTurn = !stroke.hasEarlyTopHorizontalRun
            || stroke.hasLowerThenUpperReturn
            || compactTopCurl

        return stroke.pointCount >= 10
            && stroke.bounds.height >= 12
            && stroke.aspectRatio >= 0.12
            && stroke.aspectRatio <= 0.85
            && stroke.straightness >= 0.28
            && stroke.straightness <= 0.72
            && startsNearTop
            && descendsIntoTail
            && hasUpperLoopBody
            && stroke.hasUpperReturnAfterMidpoint
            && stroke.aspectRatio <= 0.60
            && hasNineTurn
    }

    private func isTwoStrokeNineLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 2 else {
            return false
        }

        let orderedStrokes = features.strokes.sorted { lhs, rhs in
            lhs.bounds.minX < rhs.bounds.minX
        }
        let loopStroke = orderedStrokes[0]
        let tailStroke = orderedStrokes[1]
        let horizontalGap = loopStroke.bounds.horizontalGap(to: tailStroke.bounds)
        let verticalOverlap = loopStroke.bounds.verticalOverlap(with: tailStroke.bounds)
        let referenceHeight = max(min(loopStroke.bounds.height, tailStroke.bounds.height), 1)

        return loopStroke.isCompactNineLoopFragment
            && tailStroke.isCompactNineTailFragment
            && tailStroke.bounds.recognitionMidX > loopStroke.bounds.recognitionMidX
            && horizontalGap <= 22
            && verticalOverlap >= referenceHeight * 0.18
            && features.bounds.width <= 38
            && features.bounds.height <= 44
            && features.aspectRatio >= 0.35
            && features.aspectRatio <= 1.40
    }

    private func isOpenHandwrittenNineLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 16
            && stroke.bounds.height >= 14
            && stroke.aspectRatio >= 0.18
            && stroke.aspectRatio <= 0.95
            && stroke.straightness <= 0.45
            && stroke.normalizedYRatio(of: stroke.startPoint) >= 0.06
            && stroke.endPoint.y >= stroke.bounds.minY + stroke.bounds.height * 0.70
            && stroke.hasLowerThenUpperReturn
            && stroke.hasUpperReturnAfterMidpoint
            && stroke.normalizedMaxX(aboveYRatio: 0.45) >= 0.45
            && stroke.hasVerticalTailAndLoopReturn
    }

    private func isCompactAlteredNineLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 10
            && stroke.bounds.width >= 4.5
            && stroke.bounds.width <= 15
            && stroke.bounds.height >= 10
            && stroke.bounds.height <= 30
            && stroke.aspectRatio >= 0.22
            && stroke.aspectRatio <= 1.05
            && stroke.endPoint.y >= stroke.bounds.minY + stroke.bounds.height * 0.52
            && (stroke.horizontalDirectionChangeCount >= 1 || stroke.straightness <= 0.68)
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isOneLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let standardOne = stroke.pointCount >= 4
            && stroke.bounds.height >= 8
            && stroke.bounds.width <= max(6, stroke.bounds.height * 0.35)
            && stroke.straightness >= 0.60
            && abs(abs(stroke.angleDegrees) - 90) <= 28
        let compactSuffixOne = stroke.pointCount >= 3
            && stroke.bounds.height >= 4
            && stroke.bounds.width <= max(4, stroke.bounds.height * 0.55)
            && stroke.straightness >= 0.72
            && stroke.angleDegrees >= 55
            && stroke.angleDegrees <= 115

        return standardOne || compactSuffixOne
    }

    private func isSlashSeparatorLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let diagonalAngle = stroke.diagonalAngleMagnitude
        let dx = stroke.endPoint.x - stroke.startPoint.x
        let dy = stroke.endPoint.y - stroke.startPoint.y

        return stroke.bounds.width >= 4
            && stroke.bounds.height >= 8
            && stroke.aspectRatio >= 0.18
            && stroke.aspectRatio <= 0.82
            && stroke.straightness >= 0.38
            && dx * dy < 0
            && diagonalAngle >= 30
            && diagonalAngle <= 84
            && (!stroke.hasEarlyTopHorizontalRun || stroke.straightness >= 0.70 || abs(stroke.angleDegrees) >= 100)
    }

    private func isHandwrittenSuspendedSLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)
        let descendsThroughBody = endY >= 0.58
            && stroke.endPoint.y >= stroke.startPoint.y + stroke.bounds.height * 0.45
        let curvesBackLeft = endX <= startX - 0.12
            || stroke.normalizedMinX(belowYRatio: 0.45) <= startX - 0.16
        let narrowTrailingS = stroke.aspectRatio <= 0.78
            && stroke.straightness >= 0.42
            && abs(abs(stroke.angleDegrees) - 90) <= 36
        let rootSizedOpenC = startX >= 0.82
            && endX >= 0.82
            && stroke.hasLeftThenRightHook
            && stroke.straightness <= 0.65

        return stroke.pointCount >= 8
            && stroke.bounds.width >= 4
            && stroke.bounds.width <= 22
            && stroke.bounds.height >= 14
            && stroke.bounds.height <= 30
            && stroke.aspectRatio >= 0.18
            && stroke.aspectRatio <= 1.05
            && stroke.straightness >= 0.20
            && stroke.straightness <= 0.86
            && startY <= 0.35
            && descendsThroughBody
            && (!stroke.hasEarlyTopHorizontalRun || narrowTrailingS)
            && !rootSizedOpenC
            && (curvesBackLeft || narrowTrailingS)
    }

    private func isHandwrittenSuspendedULike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)
        let reachesLowerBody = stroke.normalizedMaxY >= 0.82
        let movesLeftToRight = endX >= startX + 0.42
        let shallowCup = stroke.angleDegrees >= 12
            && stroke.angleDegrees <= 58
            && stroke.straightness <= 0.58

        return stroke.pointCount >= 12
            && stroke.bounds.width >= 8
            && stroke.bounds.width <= 22
            && stroke.bounds.height >= 8
            && stroke.bounds.height <= 22
            && stroke.aspectRatio >= 0.55
            && stroke.aspectRatio <= 1.75
            && startX <= 0.35
            && startY <= 0.60
            && endX >= 0.62
            && endY >= 0.55
            && reachesLowerBody
            && movesLeftToRight
            && shallowCup
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func isThreeLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 12
            && stroke.bounds.width >= 8
            && stroke.bounds.height >= 12
            && stroke.bounds.height <= 28
            && stroke.aspectRatio >= 0.42
            && stroke.aspectRatio <= 1.35
            && stroke.straightness >= 0.22
            && stroke.straightness <= 0.62
            && stroke.angleDegrees >= 35
            && stroke.angleDegrees <= 110
            && (stroke.horizontalDirectionChangeCount >= 2
                || stroke.hasEarlyTopHorizontalRun
                || stroke.hasRelaxedTopShelfForThree)
    }

    private func fiveLikeConfidence(_ features: RootGlyphFeatures) -> Double? {
        if features.strokeCount >= 2 && features.strokeCount <= 4 {
            let hasTopShelf = features.strokes.contains { stroke in
                stroke.bounds.width >= 5
                    && stroke.bounds.height <= max(6, stroke.bounds.width * 0.75)
                    && abs(stroke.angleDegrees) <= 45
            }
            let hasLowerBody = features.strokes.contains { stroke in
                stroke.bounds.height >= 8
                    && stroke.endPoint.y >= stroke.bounds.minY + stroke.bounds.height * 0.50
                    && (stroke.horizontalDirectionChangeCount >= 1 || stroke.straightness <= 0.78)
            }

            if features.bounds.width >= 7
                && features.bounds.width <= 42
                && features.bounds.height >= 10
                && features.bounds.height <= 38
                && features.aspectRatio >= 0.20
                && features.aspectRatio <= 1.70
                && hasTopShelf
                && hasLowerBody {
                return 0.992
            }

            let hasLooseBody = hasLowerBody || features.hasLooseVerticalStroke
            let hasLooseTopCue = hasTopShelf || features.looseHorizontalStrokeCount > 0
            let looksLikeLooseAlterationFive = features.bounds.width >= 7
                && features.bounds.width <= 34
                && features.bounds.height >= 8
                && features.bounds.height <= 40
                && features.aspectRatio >= 0.20
                && features.aspectRatio <= 1.75
                && (hasLooseTopCue && hasLooseBody || features.strokeCount >= 3 && hasLooseBody)

            if looksLikeLooseAlterationFive {
                return 0.62
            }

            return nil
        }

        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return nil
        }

        let looksLikeSingleStrokeFive = stroke.pointCount >= 5
            && stroke.bounds.width >= 4
            && stroke.bounds.width <= 20
            && stroke.bounds.height >= 8
            && stroke.bounds.height <= 34
            && stroke.aspectRatio >= 0.18
            && stroke.aspectRatio <= 1.55
            && stroke.endPoint.y >= stroke.bounds.minY + stroke.bounds.height * 0.55
            && (stroke.hasEarlyTopHorizontalRun || stroke.horizontalDirectionChangeCount >= 1 || stroke.straightness <= 0.72)

        return looksLikeSingleStrokeFive ? 0.62 : nil
    }

    private func isConstructedRootALike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount >= 2,
              features.strokeCount <= 3,
              features.bounds.width >= 12,
              features.bounds.height >= 18,
              features.aspectRatio >= 0.35,
              features.aspectRatio <= 1.25 else {
            return false
        }

        guard let crossbarIndex = features.strokes.indices.first(where: { index in
            isRootACrossbar(features.strokes[index], in: features)
        }) else {
            return false
        }

        let frameStrokes = features.strokes.indices
            .filter { $0 != crossbarIndex }
            .map { features.strokes[$0] }

        if frameStrokes.count == 1 {
            return isSingleStrokeRootAFrame(frameStrokes[0], in: features)
        }

        if frameStrokes.count == 2 {
            return isSplitStrokeRootAFrame(frameStrokes[0], frameStrokes[1], in: features)
        }

        return false
    }

    private func isRootACrossbar(
        _ stroke: RootStrokeFeatures,
        in features: RootGlyphFeatures
    ) -> Bool {
        let centerYRatio = features.normalizedYCenter(of: stroke)
        let widthCoverage = stroke.bounds.width / max(features.bounds.width, 1)

        return stroke.isLooseHorizontal
            && centerYRatio >= 0.36
            && centerYRatio <= 0.72
            && widthCoverage >= 0.18
            && stroke.bounds.height <= max(5, features.bounds.height * 0.18)
    }

    private func isSingleStrokeRootAFrame(
        _ stroke: RootStrokeFeatures,
        in features: RootGlyphFeatures
    ) -> Bool {
        let lowerMinX = stroke.normalizedMinX(belowYRatio: 0.58)
        let lowerMaxX = stroke.normalizedMaxX(belowYRatio: 0.58)
        let upperPoints = stroke.points.filter { point in
            stroke.normalizedYRatio(of: point) <= 0.28
        }
        let upperApexX = upperPoints
            .map { stroke.normalizedXRatio(of: $0) }
            .reduce(0, +) / Double(max(upperPoints.count, 1))

        return stroke.pointCount >= 8
            && stroke.bounds.height >= features.bounds.height * 0.78
            && stroke.bounds.width >= features.bounds.width * 0.55
            && stroke.straightness <= 0.82
            && lowerMinX <= 0.24
            && lowerMaxX >= 0.72
            && !upperPoints.isEmpty
            && upperApexX >= 0.22
            && upperApexX <= 0.74
    }

    private func isSplitStrokeRootAFrame(
        _ lhs: RootStrokeFeatures,
        _ rhs: RootStrokeFeatures,
        in features: RootGlyphFeatures
    ) -> Bool {
        guard let lhsLeg = rootALegProfile(for: lhs),
              let rhsLeg = rootALegProfile(for: rhs),
              lhsLeg.direction != rhsLeg.direction else {
            return false
        }

        let topBand = features.bounds.minY + features.bounds.height * 0.34
        let bottomBand = features.bounds.minY + features.bounds.height * 0.62
        let apexDistance = abs(lhsLeg.topPoint.x - rhsLeg.topPoint.x)
        let bottomSpan = abs(lhsLeg.bottomPoint.x - rhsLeg.bottomPoint.x)

        return lhs.bounds.verticalOverlap(with: rhs.bounds) >= min(lhs.bounds.height, rhs.bounds.height) * 0.58
            && lhsLeg.topPoint.y <= topBand
            && rhsLeg.topPoint.y <= topBand
            && lhsLeg.bottomPoint.y >= bottomBand
            && rhsLeg.bottomPoint.y >= bottomBand
            && apexDistance <= max(8, features.bounds.width * 0.32)
            && bottomSpan >= max(10, features.bounds.width * 0.48)
    }

    private func rootALegProfile(for stroke: RootStrokeFeatures) -> RootALegProfile? {
        guard stroke.pointCount >= 2,
              stroke.bounds.height >= 14,
              stroke.bounds.width >= 3,
              stroke.aspectRatio >= 0.08,
              stroke.aspectRatio <= 0.82,
              stroke.straightness >= 0.50,
              stroke.diagonalAngleMagnitude >= 30,
              stroke.diagonalAngleMagnitude <= 82,
              let topPoint = stroke.points.min(by: { $0.y < $1.y }),
              let bottomPoint = stroke.points.max(by: { $0.y < $1.y }) else {
            return nil
        }

        let horizontalAdvance = bottomPoint.x - topPoint.x
        guard abs(horizontalAdvance) >= max(2.5, stroke.bounds.height * 0.08) else {
            return nil
        }

        return RootALegProfile(
            direction: horizontalAdvance < 0 ? .downLeft : .downRight,
            topPoint: topPoint,
            bottomPoint: bottomPoint
        )
    }

    private func accidentalCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        var candidates: [GlyphCandidate] = []

        if isSharpLike(features) {
            candidates.append(heuristicCandidate("#", confidence: 0.99))
        } else if isCompactAlterationSharpLike(features) {
            candidates.append(heuristicCandidate("#", confidence: 0.72))
        }

        if isOpenSingleStrokeFlatLoopLike(features) {
            candidates.append(heuristicCandidate("b", confidence: 0.9996))
        } else if isFlatLike(features) {
            candidates.append(heuristicCandidate("b", confidence: 0.98))
        } else if isSplitAlterationFlatLike(features) {
            candidates.append(heuristicCandidate("b", confidence: 0.46))
        }

        return candidates
    }

    private func isSharpLike(_ features: RootGlyphFeatures) -> Bool {
        features.strokeCount >= 4
            && features.strokeCount <= 6
            && features.looseVerticalStrokeCount >= 2
            && features.looseHorizontalStrokeCount >= 1
            && features.aspectRatio >= 0.35
            && features.aspectRatio <= 1.20
    }

    private func isCompactAlterationSharpLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount >= 4 && features.strokeCount <= 5,
              features.bounds.width >= 10,
              features.bounds.width <= 30,
              features.bounds.height >= 10,
              features.bounds.height <= 30,
              features.aspectRatio >= 0.40,
              features.aspectRatio <= 1.85 else {
            return false
        }

        return features.looseVerticalStrokeCount >= 1
            && features.looseHorizontalStrokeCount >= 1
    }

    private func isFlatLike(_ features: RootGlyphFeatures) -> Bool {
        if isTwoStrokeCompactFlatLike(features) {
            return true
        }

        if features.strokeCount == 1,
           let stroke = features.strokes.first,
           stroke.pointCount >= 12,
           stroke.bounds.height >= 10,
           stroke.bounds.height <= 33,
           stroke.bounds.width <= 22,
           stroke.aspectRatio >= 0.40,
           stroke.aspectRatio <= 1.05,
           stroke.straightness >= 0.05,
           stroke.straightness <= 0.62,
           abs(stroke.angleDegrees) >= 35,
           abs(stroke.angleDegrees) <= 115,
           (stroke.aspectRatio <= 0.98 || abs(stroke.angleDegrees) >= 55),
           !stroke.hasEarlyTopHorizontalRun {
            return true
        }

        if features.strokeCount == 1,
           let stroke = features.strokes.first,
           stroke.pointCount >= 7,
           stroke.bounds.width <= 12,
           stroke.bounds.height >= 8,
           stroke.aspectRatio >= 0.35,
           stroke.aspectRatio <= 1.20,
           stroke.straightness >= 0.22,
           stroke.straightness <= 0.84,
           abs(stroke.angleDegrees) >= 35,
           abs(stroke.angleDegrees) <= 115,
           !stroke.hasEarlyTopHorizontalRun {
            return true
        }

        if features.strokeCount == 1,
           let stroke = features.strokes.first,
           stroke.pointCount >= 12,
           stroke.bounds.width <= 20,
           stroke.bounds.height >= 10,
           stroke.bounds.height <= 24,
           stroke.aspectRatio >= 0.55,
           stroke.aspectRatio <= 1.35,
           stroke.straightness <= 0.45,
           abs(stroke.angleDegrees) >= 25,
           abs(stroke.angleDegrees) <= 120,
           !stroke.hasEarlyTopHorizontalRun {
            return true
        }

        if features.strokeCount == 2,
           features.hasLooseVerticalStroke,
           let curvedStroke = features.strokes
            .filter({ !$0.isLooseVertical })
            .max(by: { $0.pathLength < $1.pathLength }),
           curvedStroke.pointCount >= 8,
           curvedStroke.straightness <= 0.45,
           (features.bounds.width * features.bounds.height <= 430
                || features.bounds.width <= 14
                || features.aspectRatio <= 0.55),
           features.aspectRatio >= 0.45,
           features.aspectRatio <= 1.35 {
            return true
        }

        return false
    }

    private func isOpenSingleStrokeFlatLoopLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)
        let looksLikeTriangleReturn = stroke.hasLowerBodyThenUpperPeakReturn
            && stroke.angleDegrees >= 55
            && stroke.angleDegrees <= 130
            && stroke.normalizedXRatio(of: stroke.endPoint) <= 0.62
            && stroke.normalizedYRatio(of: stroke.endPoint) >= 0.55

        return stroke.pointCount >= 12
            && stroke.bounds.width >= 6
            && stroke.bounds.width <= 18
            && stroke.bounds.height >= 14
            && stroke.bounds.height <= 30
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 1.05
            && stroke.straightness >= 0.08
            && stroke.straightness <= 0.36
            && stroke.angleDegrees >= 55
            && stroke.angleDegrees <= 115
            && stroke.endpointClosureRatio >= 0.30
            && stroke.endpointClosureRatio <= 0.82
            && startY <= 0.35
            && endY >= 0.42
            && stroke.horizontalDirectionChangeCount >= 1
            && !stroke.hasEarlyTopHorizontalRun
            && !looksLikeTriangleReturn
    }

    private func isOpenDescendingFlatLoopLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first,
              isFlatLike(features) else {
            return false
        }

        let startY = stroke.normalizedYRatio(of: stroke.startPoint)
        let endY = stroke.normalizedYRatio(of: stroke.endPoint)

        return startY <= 0.35
            && endY >= 0.42
            && endY - startY >= 0.22
            && stroke.endpointClosureRatio >= 0.30
    }

    private func isSplitAlterationFlatLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount >= 2 && features.strokeCount <= 4,
              features.bounds.width >= 8,
              features.bounds.width <= 40,
              features.bounds.height >= 12,
              features.bounds.height <= 44,
              features.aspectRatio >= 0.24,
              features.aspectRatio <= 1.75 else {
            return false
        }

        let orderedStrokes = features.strokes.sorted { lhs, rhs in
            lhs.bounds.minX < rhs.bounds.minX
        }
        let hasStemLikeStroke = orderedStrokes.contains { stroke in
            stroke.isCompactFlatStemFragment || stroke.isLooseVertical
        }
        let hasBodyLikeStroke = orderedStrokes.contains { stroke in
            stroke.isCompactFlatBodyFragment
                || stroke.horizontalDirectionChangeCount >= 1
                || stroke.straightness <= 0.58
        }
        let hasRightBodyMass = orderedStrokes.contains { stroke in
            stroke.bounds.recognitionMidX >= features.bounds.recognitionMidX
                && stroke.bounds.height >= 6
                && stroke.bounds.width >= 4
        }

        return hasStemLikeStroke && hasBodyLikeStroke && hasRightBodyMass
    }

    private func isTwoStrokeCompactFlatLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 2 else {
            return false
        }

        let orderedStrokes = features.strokes.sorted { lhs, rhs in
            lhs.bounds.minX < rhs.bounds.minX
        }
        let stemStroke = orderedStrokes[0]
        let bodyStroke = orderedStrokes[1]
        let horizontalGap = stemStroke.bounds.horizontalGap(to: bodyStroke.bounds)
        let verticalOverlap = stemStroke.bounds.verticalOverlap(with: bodyStroke.bounds)
        let referenceHeight = max(min(stemStroke.bounds.height, bodyStroke.bounds.height), 1)

        return stemStroke.isCompactFlatStemFragment
            && bodyStroke.isCompactFlatBodyFragment
            && bodyStroke.bounds.recognitionMidX > stemStroke.bounds.recognitionMidX
            && horizontalGap <= 18
            && verticalOverlap >= referenceHeight * 0.18
            && features.bounds.width <= 32
            && features.bounds.height <= 42
            && features.aspectRatio >= 0.35
            && features.aspectRatio <= 1.35
    }

    private func oneStrokeRootCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        guard let stroke = features.strokes.first,
              stroke.bounds.height >= 8,
              stroke.bounds.width >= 4,
              stroke.straightness < 0.65 else {
            if isNarrowOpenCLike(features) {
                return [heuristicCandidate("C", confidence: 0.965)]
            }

            return []
        }

        if isNarrowOpenCLike(features) {
            return [heuristicCandidate("C", confidence: 0.965)]
        }

        if isSingleStrokeDLike(features) {
            return [heuristicCandidate("D", confidence: 0.979)]
        }

        if stroke.straightness < 0.35 {
            return [heuristicCandidate("G", confidence: 0.97)]
        }

        if stroke.straightness >= 0.35 && stroke.endPoint.y > features.bounds.recognitionMidY {
            return [heuristicCandidate("C", confidence: 0.95)]
        }

        return []
    }

    private func isNarrowOpenCLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        return stroke.pointCount >= 8
            && stroke.bounds.height >= 16
            && stroke.aspectRatio >= 0.20
            && stroke.aspectRatio <= 0.72
            && stroke.straightness >= 0.55
            && stroke.normalizedXRatio(of: stroke.startPoint) >= 0.70
            && stroke.normalizedYRatio(of: stroke.endPoint) >= 0.60
            && stroke.endPoint.y >= stroke.startPoint.y + stroke.bounds.height * 0.60
            && stroke.hasLeftThenRightHook
    }

    private func isSingleStrokeDLike(_ features: RootGlyphFeatures) -> Bool {
        guard features.strokeCount == 1,
              let stroke = features.strokes.first else {
            return false
        }

        let startX = stroke.normalizedXRatio(of: stroke.startPoint)
        let endX = stroke.normalizedXRatio(of: stroke.endPoint)
        let leftSidePoints = stroke.points.filter { point in
            stroke.normalizedXRatio(of: point) <= 0.30
        }
        let leftSideBounds = InkBounds.enclosing(leftSidePoints.isEmpty ? [stroke.startPoint, stroke.endPoint] : leftSidePoints)
        let leftSideVerticalSpan = leftSideBounds.height / max(stroke.bounds.height, 1)
        let reachesRightBody = stroke.points.contains { point in
            let xRatio = stroke.normalizedXRatio(of: point)
            let yRatio = stroke.normalizedYRatio(of: point)
            return xRatio >= 0.78 && yRatio >= 0.14 && yRatio <= 0.90
        }
        let anchoredOnLeft = min(startX, endX) <= 0.30
            && max(startX, endX) <= 0.48
        let baseShape = stroke.pointCount >= 7
            && stroke.bounds.width >= 10
            && stroke.bounds.height >= 16
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 1.25
            && leftSideVerticalSpan >= 0.58
            && reachesRightBody
            && anchoredOnLeft

        let leftStemFirstD = stroke.horizontalDirectionChangeCount >= 1
            && !stroke.hasEarlyTopHorizontalRun
            && !stroke.hasLowerBodyThenUpperPeakReturn
        let topFirstSingleBowlD = stroke.horizontalDirectionChangeCount <= 1
            && stroke.normalizedYRatio(of: stroke.startPoint) <= 0.25

        return baseShape && (leftStemFirstD || topFirstSingleBowlD)
    }

    private func twoStrokeRootCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        if features.hasHorizontalStroke,
           !features.hasVerticalStem,
           let mainStroke = features.strokes.max(by: { $0.pathLength < $1.pathLength }),
           mainStroke.straightness < 0.45,
           features.aspectRatio >= 0.50,
           features.aspectRatio <= 0.95 {
            return [heuristicCandidate("A", confidence: 0.98)]
        }

        if features.hasVerticalStem,
           let bodyStroke = features.strokes
           .filter({ !$0.isVerticalStem })
            .max(by: { $0.pathLength < $1.pathLength }) {
            if isDLikeBody(bodyStroke, in: features) {
                return [heuristicCandidate("D", confidence: 0.985)]
            }

            if isNoisySingleBowlDLikeBody(bodyStroke, in: features) {
                return [heuristicCandidate("D", confidence: 0.92)]
            }

            if isLooseSingleBowlDLikeBody(bodyStroke, in: features) {
                return [heuristicCandidate("D", confidence: 0.74)]
            }

            if bodyStroke.pointCount >= 18
                && bodyStroke.straightness < 0.55
                && bodyStroke.horizontalDirectionChangeCount >= 2
                && hasTwoLobeBBodyEvidence(bodyStroke) {
                return [heuristicCandidate("B", confidence: 0.987)]
            }

            if isCompactBLikeBody(bodyStroke, in: features) {
                return [heuristicCandidate("B", confidence: 0.987)]
            }
        }

        return []
    }

    private func isCompactBLikeBody(_ bodyStroke: RootStrokeFeatures, in features: RootGlyphFeatures) -> Bool {
        bodyStroke.pointCount >= 15
            && bodyStroke.straightness < 0.55
            && bodyStroke.horizontalDirectionChangeCount >= 3
            && bodyStroke.bounds.height >= features.bounds.height * 0.78
            && features.aspectRatio >= 0.42
            && features.aspectRatio <= 0.80
            && hasTwoLobeBBodyEvidence(bodyStroke)
    }

    private func isDLikeBody(_ bodyStroke: RootStrokeFeatures, in features: RootGlyphFeatures) -> Bool {
        if bodyStroke.pointCount <= 17,
           features.aspectRatio >= 0.50,
           features.aspectRatio <= 0.95,
           bodyStroke.horizontalDirectionChangeCount <= 1,
           bodyStroke.straightness < 0.55 {
            return true
        }

        if bodyStroke.pointCount <= 22,
           bodyStroke.bounds.width >= 18,
           features.aspectRatio >= 0.55,
           features.aspectRatio <= 0.95,
           bodyStroke.horizontalDirectionChangeCount <= 1,
           bodyStroke.straightness < 0.62 {
            return true
        }

        if bodyStroke.pointCount <= 14,
           features.aspectRatio >= 0.50,
           bodyStroke.horizontalDirectionChangeCount <= 1,
           bodyStroke.straightness >= 0.38,
           bodyStroke.straightness < 0.82 {
            return true
        }

        if features.aspectRatio >= 0.90,
           bodyStroke.aspectRatio >= 0.90,
           bodyStroke.pointCount <= 22,
           bodyStroke.horizontalDirectionChangeCount <= 1,
           bodyStroke.straightness < 0.60 {
            return true
        }

        return false
    }

    private func isNoisySingleBowlDLikeBody(_ bodyStroke: RootStrokeFeatures, in features: RootGlyphFeatures) -> Bool {
        let startsOrEndsOnLeft = min(
            bodyStroke.normalizedXRatio(of: bodyStroke.startPoint),
            bodyStroke.normalizedXRatio(of: bodyStroke.endPoint)
        ) <= 0.22
        let returnsToLowerLeft = [
            bodyStroke.startPoint,
            bodyStroke.endPoint
        ].contains { point in
            bodyStroke.normalizedXRatio(of: point) <= 0.28
                && bodyStroke.normalizedYRatio(of: point) >= 0.70
        }
        let reachesRightBody = bodyStroke.normalizedMaxX(betweenLowerYRatio: 0.18, upperYRatio: 0.78) >= 0.78
        let middleStaysOnRightSide = bodyStroke.normalizedMinX(betweenLowerYRatio: 0.34, upperYRatio: 0.66) > 0.42
        let spansMostOfRootHeight = bodyStroke.bounds.height >= features.bounds.height * 0.70

        return bodyStroke.pointCount >= 12
            && bodyStroke.pointCount <= 48
            && bodyStroke.bounds.width >= 14
            && features.aspectRatio >= 0.42
            && features.aspectRatio <= 1.05
            && bodyStroke.straightness < 0.74
            && startsOrEndsOnLeft
            && returnsToLowerLeft
            && reachesRightBody
            && middleStaysOnRightSide
            && spansMostOfRootHeight
            && !hasTwoLobeBBodyEvidence(bodyStroke)
    }

    private func isLooseSingleBowlDLikeBody(_ bodyStroke: RootStrokeFeatures, in features: RootGlyphFeatures) -> Bool {
        let startsOrEndsOnLeft = min(
            bodyStroke.normalizedXRatio(of: bodyStroke.startPoint),
            bodyStroke.normalizedXRatio(of: bodyStroke.endPoint)
        ) <= 0.25
        let returnsToLowerLeft = [
            bodyStroke.startPoint,
            bodyStroke.endPoint
        ].contains { point in
            bodyStroke.normalizedXRatio(of: point) <= 0.30
                && bodyStroke.normalizedYRatio(of: point) >= 0.64
        }
        let reachesRightBody = bodyStroke.normalizedMaxX(betweenLowerYRatio: 0.18, upperYRatio: 0.78) >= 0.74
        let middleStaysOnRightSide = bodyStroke.normalizedMinX(betweenLowerYRatio: 0.34, upperYRatio: 0.66) > 0.55
        let spansMostOfRootHeight = bodyStroke.bounds.height >= features.bounds.height * 0.62

        return bodyStroke.pointCount >= 18
            && bodyStroke.pointCount <= 64
            && bodyStroke.bounds.width >= 12
            && features.aspectRatio >= 0.42
            && features.aspectRatio <= 1.12
            && bodyStroke.straightness < 0.78
            && startsOrEndsOnLeft
            && returnsToLowerLeft
            && reachesRightBody
            && middleStaysOnRightSide
            && spansMostOfRootHeight
            && !hasTwoLobeBBodyEvidence(bodyStroke)
    }

    private func hasTwoLobeBBodyEvidence(_ bodyStroke: RootStrokeFeatures) -> Bool {
        let upperRightReach = bodyStroke.normalizedMaxX(aboveYRatio: 0.42) >= 0.58
        let lowerRightReach = bodyStroke.normalizedMaxX(belowYRatio: 0.58) >= 0.70
        let middleMinX = bodyStroke.normalizedMinX(betweenLowerYRatio: 0.34, upperYRatio: 0.66)
        let middleMaxX = bodyStroke.normalizedMaxX(betweenLowerYRatio: 0.34, upperYRatio: 0.66)
        let hasMiddleWaist = middleMinX <= 0.78
            && middleMaxX - middleMinX >= 0.22

        return upperRightReach
            && lowerRightReach
            && hasMiddleWaist
    }

    private func threeStrokeRootCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        guard features.aspectRatio >= 0.45,
              features.aspectRatio <= 1.05 else {
            return []
        }

        let hasTop = hasTopRootHorizontalEvidence(in: features)
        let hasMiddle = hasMiddleRootHorizontalEvidence(in: features)
        let hasBottom = hasBottomRootEvidence(in: features)

        if hasTop && hasBottom {
            return [heuristicCandidate("E", confidence: 0.996)]
        }

        if features.hasVerticalStem && hasTop && hasMiddle {
            return [heuristicCandidate("F", confidence: 0.996)]
        }

        if !features.hasVerticalStem && features.horizontalStrokeCount >= 1 {
            return [heuristicCandidate("E", confidence: 0.985)]
        }

        return []
    }

    private func fourStrokeRootCandidates(_ features: RootGlyphFeatures) -> [GlyphCandidate] {
        guard features.aspectRatio >= 0.45,
              features.aspectRatio <= 1.15 else {
            return []
        }

        let hasTop = hasTopRootHorizontalEvidence(in: features)
        let hasMiddle = hasMiddleRootHorizontalEvidence(in: features)
        let hasBottom = hasBottomRootEvidence(in: features)

        if features.hasVerticalStem && hasTop && hasMiddle && hasBottom {
            return [heuristicCandidate("E", confidence: 0.997)]
        }

        return []
    }

    private func hasTopRootHorizontalEvidence(in features: RootGlyphFeatures) -> Bool {
        features.strokes.contains { stroke in
            guard stroke.isLooseHorizontal else {
                return false
            }

            let centerYRatio = features.normalizedYCenter(of: stroke)
            return centerYRatio <= 0.30
                && stroke.bounds.width >= features.bounds.width * 0.30
        }
    }

    private func hasMiddleRootHorizontalEvidence(in features: RootGlyphFeatures) -> Bool {
        features.strokes.contains { stroke in
            guard stroke.isLooseHorizontal else {
                return false
            }

            let centerYRatio = features.normalizedYCenter(of: stroke)
            return centerYRatio >= 0.30
                && centerYRatio <= 0.72
                && stroke.bounds.width >= features.bounds.width * 0.25
        }
    }

    private func hasBottomRootEvidence(in features: RootGlyphFeatures) -> Bool {
        features.strokes.contains { stroke in
            let centerYRatio = features.normalizedYCenter(of: stroke)
            let widthCoverage = stroke.bounds.width / max(features.bounds.width, 1)
            let reachesRight = stroke.bounds.maxX >= features.bounds.minX + features.bounds.width * 0.58

            let explicitBottomStroke = stroke.isLooseHorizontal
                && centerYRatio >= 0.72
                && widthCoverage >= 0.30
                && reachesRight
            let lowerRightBody = !stroke.isLooseHorizontal
                && stroke.bounds.maxY >= features.bounds.minY + features.bounds.height * 0.86
                && stroke.bounds.maxX >= features.bounds.minX + features.bounds.width * 0.62
                && widthCoverage >= 0.35
                && stroke.bounds.height >= features.bounds.height * 0.42

            return explicitBottomStroke || lowerRightBody
        }
    }

    private func heuristicCandidate(_ text: String, confidence: Double) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: .heuristic)
    }

    private func distance(
        from input: NormalizedGesture,
        to template: NormalizedGesture
    ) -> Double {
        let pointDistance = zip(input.points, template.points)
            .map { lhs, rhs in
                lhs.distance(to: rhs)
            }
            .reduce(0, +) / Double(max(input.points.count, 1))

        let aspectPenalty = abs(log(input.aspectRatio / template.aspectRatio))
            * configuration.aspectRatioWeight
        let strokeCountPenalty = Double(abs(input.strokeCount - template.strokeCount))
            / Double(max(input.strokeCount, template.strokeCount, 1))
            * configuration.strokeCountWeight

        return pointDistance + aspectPenalty + strokeCountPenalty
    }
}

private struct RootGlyphFeatures: Hashable {
    var strokes: [RootStrokeFeatures]
    var bounds: InkBounds

    init(cluster: InkCluster) {
        strokes = cluster.strokes.map(RootStrokeFeatures.init(stroke:))
        bounds = cluster.bounds
    }

    var strokeCount: Int {
        strokes.count
    }

    var aspectRatio: Double {
        max(bounds.width, 1) / max(bounds.height, 1)
    }

    var hasHorizontalStroke: Bool {
        horizontalStrokeCount > 0
    }

    var horizontalStrokeCount: Int {
        strokes.filter(\.isHorizontal).count
    }

    var looseHorizontalStrokeCount: Int {
        strokes.filter(\.isLooseHorizontal).count
    }

    var looseVerticalStrokeCount: Int {
        strokes.filter(\.isLooseVertical).count
    }

    var hasLooseVerticalStroke: Bool {
        looseVerticalStrokeCount > 0
    }

    var hasVerticalStem: Bool {
        strokes.contains(where: \.isVerticalStem)
    }

    func normalizedYCenter(of stroke: RootStrokeFeatures) -> Double {
        (stroke.bounds.recognitionMidY - bounds.minY) / max(bounds.height, 1)
    }
}

private struct RootStrokeFeatures: Hashable {
    var points: [InkPoint]
    var bounds: InkBounds
    var startPoint: InkPoint
    var endPoint: InkPoint
    var pathLength: Double
    var pointCount: Int
    var straightness: Double
    var angleDegrees: Double

    init(stroke: InkStroke) {
        points = stroke.points
        bounds = stroke.bounds
        startPoint = stroke.points.first ?? InkPoint(x: 0, y: 0, timeOffset: nil)
        endPoint = stroke.points.last ?? startPoint
        pointCount = stroke.points.count
        pathLength = zip(stroke.points, stroke.points.dropFirst())
            .map { start, end in
                start.distance(to: end)
            }
            .reduce(0, +)

        let directDistance = startPoint.distance(to: endPoint)
        straightness = pathLength > 0 ? directDistance / pathLength : 0
        angleDegrees = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x) * 180 / .pi
    }

    var isHorizontal: Bool {
        bounds.width >= 6
            && bounds.width / max(bounds.height, 1) >= 2.0
            && abs(angleDegrees) <= 35
            && straightness >= 0.55
    }

    var isLooseHorizontal: Bool {
        bounds.width >= 6
            && bounds.width / max(bounds.height, 1) >= 1.65
            && abs(angleDegrees) <= 45
    }

    var isLooseVertical: Bool {
        bounds.height >= 8
            && bounds.height / max(bounds.width, 1) >= 1.8
            && abs(abs(angleDegrees) - 90) <= 35
    }

    var isVerticalStem: Bool {
        bounds.height >= 8
            && bounds.height / max(bounds.width, 1) >= 1.95
            && abs(abs(angleDegrees) - 90) <= 30
            && straightness >= 0.45
    }

    var isCompactNineLoopFragment: Bool {
        pointCount >= 8
            && bounds.width >= 4.5
            && bounds.width <= 16
            && bounds.height >= 10
            && bounds.height <= 30
            && aspectRatio >= 0.18
            && aspectRatio <= 1.25
            && straightness <= 0.62
            && (!hasEarlyTopHorizontalRun || straightness <= 0.40 || aspectRatio <= 0.70)
    }

    var isCompactNineTailFragment: Bool {
        pointCount >= 6
            && bounds.height >= 17
            && bounds.height <= 38
            && bounds.width <= 16
            && aspectRatio <= 0.92
            && straightness >= 0.48
            && angleDegrees >= 50
            && angleDegrees <= 125
    }

    var isCompactFlatStemFragment: Bool {
        pointCount >= 5
            && bounds.height >= 14
            && bounds.height <= 38
            && bounds.width <= max(10, bounds.height * 0.42)
            && straightness >= 0.48
            && abs(abs(angleDegrees) - 90) <= 38
    }

    var isCompactFlatBodyFragment: Bool {
        pointCount >= 8
            && bounds.width >= 4.5
            && bounds.width <= 18
            && bounds.height >= 10
            && bounds.height <= 28
            && aspectRatio >= 0.18
            && aspectRatio <= 1.35
            && straightness <= 0.62
            && (!hasEarlyTopHorizontalRun || straightness <= 0.40 || aspectRatio <= 0.70)
    }

    var aspectRatio: Double {
        max(bounds.width, 1) / max(bounds.height, 1)
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

    var hasRelaxedTopShelfForThree: Bool {
        guard points.count >= 12 else {
            return false
        }

        let earlyCount = max(3, Int((Double(points.count) * 0.45).rounded(.up)))
        let earlyPoints = Array(points.prefix(min(points.count, earlyCount)))
        let earlyBounds = InkBounds.enclosing(earlyPoints)
        let averageY = earlyPoints.map(\.y).reduce(0, +) / Double(earlyPoints.count)

        return earlyBounds.width >= bounds.width * 0.45
            && earlyBounds.height <= max(5, bounds.height * 0.50)
            && averageY <= bounds.minY + bounds.height * 0.40
            && endPoint.y >= bounds.minY + bounds.height * 0.72
            && horizontalDirectionChangeCount >= 1
    }

    var upperLoopBounds: InkBounds {
        let upperLimit = bounds.minY + bounds.height * 0.58
        let upperPoints = points.filter { point in
            point.y <= upperLimit
        }

        return InkBounds.enclosing(upperPoints.isEmpty ? points : upperPoints)
    }

    var hasUpperReturnAfterMidpoint: Bool {
        guard points.count >= 8 else {
            return false
        }

        let midpoint = points.index(points.startIndex, offsetBy: points.count / 2)
        let upperReturnLimit = bounds.minY + bounds.height * 0.34

        return points[midpoint...].contains { point in
            point.y <= upperReturnLimit
        }
    }

    var hasLowerThenUpperReturn: Bool {
        guard points.count >= 8 else {
            return false
        }

        let lowerLimit = bounds.minY + bounds.height * 0.36
        let upperReturnLimit = bounds.minY + bounds.height * 0.34
        var sawLowerBody = false

        for (index, point) in points.enumerated() where index >= max(2, points.count / 4) {
            if point.y >= lowerLimit {
                sawLowerBody = true
            } else if sawLowerBody, point.y <= upperReturnLimit {
                return true
            }
        }

        return false
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

    var hasVerticalTailAndLoopReturn: Bool {
        guard points.count >= 8 else {
            return false
        }

        let tailX = normalizedXRatio(of: startPoint)
        let tailSideTolerance = 0.24
        let pointsOnTailSide = points.filter { point in
            abs(normalizedXRatio(of: point) - tailX) <= tailSideTolerance
        }
        let tailSpansHeight = InkBounds.enclosing(pointsOnTailSide).height >= bounds.height * 0.55
        let reachesOppositeSide = points.contains { point in
            abs(normalizedXRatio(of: point) - tailX) >= 0.35
        }
        let returnsTowardTail = abs(normalizedXRatio(of: endPoint) - tailX) <= 0.28

        return tailSpansHeight && reachesOppositeSide && returnsTowardTail
    }

    var leftCurlDepthFromStart: Double {
        guard !points.isEmpty else {
            return 0
        }

        let upperLimit = bounds.minY + bounds.height * 0.62
        let loopPoints = points.filter { point in
            point.y <= upperLimit
        }
        let minimumLoopX = loopPoints.map(\.x).min() ?? bounds.minX

        return max(0, startPoint.x - minimumLoopX)
    }

    var hasLeftThenRightHook: Bool {
        guard points.count >= 5 else {
            return false
        }

        let minX = points.map(\.x).min() ?? bounds.minX
        let startAndEndMinX = min(startPoint.x, endPoint.x)

        return minX <= startAndEndMinX - max(2, bounds.width * 0.25)
            && endPoint.x >= minX + bounds.width * 0.45
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

    var endpointClosureRatio: Double {
        startPoint.distance(to: endPoint) / max(bounds.width, bounds.height, 1)
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

    func normalizedMaxX(aboveYRatio ratio: Double) -> Double {
        let limit = bounds.minY + bounds.height * ratio
        let normalizedValues = points
            .filter { $0.y <= limit }
            .map(normalizedXRatio(of:))

        return normalizedValues.max() ?? normalizedXRatio(of: startPoint)
    }

    func normalizedMinX(belowYRatio ratio: Double) -> Double {
        let limit = bounds.minY + bounds.height * ratio
        let normalizedValues = points
            .filter { $0.y >= limit }
            .map(normalizedXRatio(of:))

        return normalizedValues.min() ?? normalizedXRatio(of: endPoint)
    }

    func normalizedMinX(betweenLowerYRatio lowerRatio: Double, upperYRatio: Double) -> Double {
        let lowerLimit = bounds.minY + bounds.height * lowerRatio
        let upperLimit = bounds.minY + bounds.height * upperYRatio
        let normalizedValues = points
            .filter { $0.y >= lowerLimit && $0.y <= upperLimit }
            .map(normalizedXRatio(of:))

        return normalizedValues.min() ?? min(
            normalizedXRatio(of: startPoint),
            normalizedXRatio(of: endPoint)
        )
    }

    func normalizedMaxX(belowYRatio ratio: Double) -> Double {
        let limit = bounds.minY + bounds.height * ratio
        let normalizedValues = points
            .filter { $0.y >= limit }
            .map(normalizedXRatio(of:))

        return normalizedValues.max() ?? normalizedXRatio(of: endPoint)
    }

    func normalizedMaxX(betweenLowerYRatio lowerRatio: Double, upperYRatio: Double) -> Double {
        let lowerLimit = bounds.minY + bounds.height * lowerRatio
        let upperLimit = bounds.minY + bounds.height * upperYRatio
        let normalizedValues = points
            .filter { $0.y >= lowerLimit && $0.y <= upperLimit }
            .map(normalizedXRatio(of:))

        return normalizedValues.max() ?? max(
            normalizedXRatio(of: startPoint),
            normalizedXRatio(of: endPoint)
        )
    }

    var normalizedMaxY: Double {
        points
            .map(normalizedYRatio(of:))
            .max() ?? normalizedYRatio(of: endPoint)
    }

}

private struct RootALegProfile: Hashable {
    var direction: RootALegDirection
    var topPoint: InkPoint
    var bottomPoint: InkPoint
}

private enum RootALegDirection: Hashable {
    case downLeft
    case downRight
}

private struct NormalizedGesture: Hashable {
    var points: [NormalizedPoint]
    var aspectRatio: Double
    var strokeCount: Int

    init?(strokes: [InkStroke], samplePointCount: Int) {
        let rawPoints = strokes.flatMap(\.points)
        guard !rawPoints.isEmpty else {
            return nil
        }

        let bounds = InkBounds.enclosing(rawPoints)
        let sampledPoints = Self.resampled(rawPoints, count: max(2, samplePointCount))
        let scale = max(bounds.width, bounds.height, 1)
        let scaledPoints = sampledPoints.map { point in
            NormalizedPoint(
                x: (point.x - bounds.minX) / scale,
                y: (point.y - bounds.minY) / scale
            )
        }
        let centroid = NormalizedPoint.centroid(of: scaledPoints)

        points = scaledPoints.map { point in
            NormalizedPoint(
                x: point.x - centroid.x,
                y: point.y - centroid.y
            )
        }
        aspectRatio = max(bounds.width, 1) / max(bounds.height, 1)
        strokeCount = strokes.count
    }

    private static func resampled(_ points: [InkPoint], count: Int) -> [InkPoint] {
        guard let firstPoint = points.first else {
            return []
        }

        guard points.count > 1 else {
            return Array(repeating: firstPoint, count: count)
        }

        let pathLength = zip(points, points.dropFirst())
            .map { start, end in
                start.distance(to: end)
            }
            .reduce(0, +)

        guard pathLength > 0 else {
            return Array(repeating: firstPoint, count: count)
        }

        let interval = pathLength / Double(count - 1)
        var sampledPoints = [firstPoint]
        var distanceSinceLastSample = 0.0
        var previousPoint = firstPoint
        var sourceIndex = points.index(after: points.startIndex)

        while sourceIndex < points.endIndex,
              sampledPoints.count < count {
            let currentPoint = points[sourceIndex]
            let segmentLength = previousPoint.distance(to: currentPoint)

            guard segmentLength > 0 else {
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
                continue
            }

            if distanceSinceLastSample + segmentLength >= interval {
                let remainingDistance = interval - distanceSinceLastSample
                let interpolationAmount = remainingDistance / segmentLength
                let newPoint = previousPoint.interpolated(
                    toward: currentPoint,
                    amount: interpolationAmount
                )
                sampledPoints.append(newPoint)
                previousPoint = newPoint
                distanceSinceLastSample = 0
            } else {
                distanceSinceLastSample += segmentLength
                previousPoint = currentPoint
                sourceIndex = points.index(after: sourceIndex)
            }
        }

        while sampledPoints.count < count {
            sampledPoints.append(points[points.index(before: points.endIndex)])
        }

        return Array(sampledPoints.prefix(count))
    }
}

private struct NormalizedPoint: Hashable {
    var x: Double
    var y: Double

    static func centroid(of points: [NormalizedPoint]) -> NormalizedPoint {
        guard !points.isEmpty else {
            return NormalizedPoint(x: 0, y: 0)
        }

        let totals = points.reduce(NormalizedPoint(x: 0, y: 0)) { partial, point in
            NormalizedPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return NormalizedPoint(
            x: totals.x / Double(points.count),
            y: totals.y / Double(points.count)
        )
    }

    func distance(to other: NormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

private extension InkPoint {
    func distance(to other: InkPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    func interpolated(toward other: InkPoint, amount: Double) -> InkPoint {
        InkPoint(
            x: x + (other.x - x) * amount,
            y: y + (other.y - y) * amount,
            timeOffset: nil
        )
    }
}
