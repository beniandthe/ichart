#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

enum RhythmicNotationQuantizer {
    private enum HorizontalRestBlockPlacement {
        case whole
        case half
        case ambiguous
    }

    static func quantize(
        drawingData: Data,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> [RhythmValue] {
        let drawing = try PKDrawing(data: drawingData)
        return try quantize(drawing: drawing, meter: meter, drawingFrame: drawingFrame)
    }

    static func quantize(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> [RhythmValue] {
        try measureProposal(
            drawing: drawing,
            meter: meter,
            drawingFrame: drawingFrame,
            includeExtendedStability: false
        ).values
    }

    static func renderProposal(
        drawingData: Data,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> RhythmicNotationMeasureProposal {
        let drawing = try PKDrawing(data: drawingData)
        return try renderProposal(drawing: drawing, meter: meter, drawingFrame: drawingFrame)
    }

    static func renderProposal(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> RhythmicNotationMeasureProposal {
        try proposal(
            from: recognitionDecision(
                drawing: drawing,
                meter: meter,
                drawingFrame: drawingFrame
            ),
            meter: meter
        )
    }

    static func recognitionDecision(
        drawingData: Data,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> RhythmRecognitionDecision {
        let drawing = try PKDrawing(data: drawingData)
        return recognitionDecision(drawing: drawing, meter: meter, drawingFrame: drawingFrame)
    }

    static func recognitionDecision(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision {
        recognitionDecision(
            strokeObservations: strokeObservations(from: drawing),
            meter: meter,
            drawingFrame: drawingFrame,
            includeExtendedStability: true
        )
    }

    static func visualNoteAnchors(
        drawingData: Data,
        drawingFrame: CGRect
    ) throws -> [RhythmVisualNoteAnchor] {
        let drawing = try PKDrawing(data: drawingData)
        return visualNoteAnchors(drawing: drawing, drawingFrame: drawingFrame)
    }

    static func visualNoteAnchors(
        drawing: PKDrawing,
        drawingFrame: CGRect
    ) -> [RhythmVisualNoteAnchor] {
        []
    }

    private static func proposal(
        from decision: RhythmRecognitionDecision,
        meter: Meter
    ) throws -> RhythmicNotationMeasureProposal {
        if let proposal = decision.proposal {
            return proposal
        }

        throw quantizationError(
            for: decision.reason ?? .unsupported,
            phrase: decision.phrase,
            meter: meter
        )
    }

    private static func recognitionDecision(
        strokeObservations: [StrokeObservation],
        meter: Meter,
        drawingFrame: CGRect,
        includeExtendedStability: Bool
    ) -> RhythmRecognitionDecision {
        let tieStrokes = strokeObservations.filter { $0.looksLikeTieArc(in: drawingFrame) }
        let durationStrokeObservations = strokeObservations.filter { !$0.looksLikeTieArc(in: drawingFrame) }
        guard !durationStrokeObservations.isEmpty else {
            return .keepWriting(.noInk, nil)
        }
        let retiredDecision = retiredRecognitionDecision(
            strokeObservations: durationStrokeObservations,
            meter: meter
        )
        guard RhythmRecognitionOverhaulGate.shipsDedicatedRhythmTool else {
            return retiredDecision
        }

        let glyphOCRDecision = retiredDecision

        let meterCheckedDecision = decisionByApplyingMeterValidityRules(
            glyphOCRDecision,
            meter: meter
        )
        let contextCheckedDecision = decisionByApplyingContextRules(
            meterCheckedDecision,
            meter: meter
        )
        let tieAwareDecision = decisionByApplyingTieMetadata(
            contextCheckedDecision,
            tieStrokes: tieStrokes,
            meter: meter,
            drawingFrame: drawingFrame
        )
        let contextPath = contextReasoningPath(
            for: tieAwareDecision,
            meter: meter
        )
        return tieAwareDecision.addingReasoningPaths([
            glyphOCRDecision.reasoningPath(kind: .glyphOCR),
            contextPath
        ])
    }

    private static func retiredRecognitionDecision(
        strokeObservations: [StrokeObservation],
        meter: Meter
    ) -> RhythmRecognitionDecision {
        RhythmRecognitionDecision.keepWriting(
            .unsupported,
            RhythmPhraseHypothesis(
                source: .gridFirst,
                glyphEvidence: [],
                symbols: [],
                uncoveredStrokeIndices: Array(strokeObservations.indices),
                naturalValues: [],
                naturalUnits: 0,
                targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
                passesCompendium: false,
                reasoningPaths: [
                    RhythmRecognitionReasoningPath(
                        kind: .glyphOCR,
                        outcome: .unavailable,
                        values: [],
                        reason: .unsupported,
                        summary: "source=gridFirst reason=retired values="
                    )
                ]
            )
        )
    }

    private static func decisionByApplyingMeterValidityRules(
        _ decision: RhythmRecognitionDecision,
        meter: Meter
    ) -> RhythmRecognitionDecision {
        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        if let proposal = decision.proposal {
            let proposalUnits = proposal.values.reduce(0) { partialResult, value in
                partialResult + rhythmUnits(for: value, meter: meter)
            }
            guard proposalUnits <= targetUnits else {
                return .keepWriting(.overflow, decision.phrase)
            }
        }

        if decision.proposal == nil,
           let phrase = decision.phrase,
           phrase.naturalUnits > targetUnits {
            return .keepWriting(.overflow, phrase)
        }

        return decision
    }

    private static func decisionByApplyingTieMetadata(
        _ decision: RhythmRecognitionDecision,
        tieStrokes: [StrokeObservation],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision {
        guard !tieStrokes.isEmpty,
              let proposal = decision.proposal else {
            return decision
        }

        let tieOutSlotIndices = inferredTieOutSlotIndices(
            from: tieStrokes,
            values: proposal.values,
            meter: meter,
            drawingFrame: drawingFrame
        )
        guard !tieOutSlotIndices.isEmpty else {
            return decision
        }

        let tiedProposal = RhythmicNotationMeasureProposal(
            values: proposal.values,
            safety: proposal.safety,
            isNaturalExactFit: proposal.isNaturalExactFit,
            tieOutSlotIndices: tieOutSlotIndices
        )

        switch decision {
        case .commit(_, let phrase):
            return .commit(tiedProposal, phrase)
        case .needsReview(let reason, let phrase, _):
            return .needsReview(reason, phrase, tiedProposal)
        case .keepWriting:
            return decision
        }
    }

    private static func inferredTieOutSlotIndices(
        from tieStrokes: [StrokeObservation],
        values: [RhythmValue],
        meter: Meter,
        drawingFrame: CGRect
    ) -> Set<Int> {
        guard let slots = MeasureRhythmMap(values: values).resolvedSlots(for: meter),
              slots.count >= 2 else {
            return []
        }

        let centers = slots.map { slot -> CGFloat in
            let startOffset = slot.startPosition.startOffset(in: meter) ?? 0
            let centerOffset = startOffset + slot.duration.wholeNoteLength(in: meter) / 2
            let fraction = meter.measureLengthInWholeNotes > 0
                ? centerOffset / meter.measureLengthInWholeNotes
                : 0
            return drawingFrame.minX + drawingFrame.width * CGFloat(fraction)
        }

        var tiedIndices = Set<Int>()
        for tieStroke in tieStrokes {
            var bestIndex: Int?
            var bestScore = CGFloat.greatestFiniteMagnitude

            for index in 0..<(slots.count - 1) {
                guard slots[index].duration.supportsPitchedLeadSheetNote,
                      slots[index + 1].duration.supportsPitchedLeadSheetNote else {
                    continue
                }

                let leftCenter = centers[index]
                let rightCenter = centers[index + 1]
                guard rightCenter > leftCenter else {
                    continue
                }

                let pairMidX = (leftCenter + rightCenter) / 2
                let pairSpan = rightCenter - leftCenter
                let tieMidX = tieStroke.bounds.midX
                let centerScore = abs(tieMidX - pairMidX) / max(CGFloat(1), pairSpan)
                let spanScore = abs(tieStroke.bounds.width - pairSpan) / max(CGFloat(1), pairSpan)
                let overlapsPair = tieStroke.bounds.maxX >= leftCenter - pairSpan * 0.25
                    && tieStroke.bounds.minX <= rightCenter + pairSpan * 0.25
                guard overlapsPair else {
                    continue
                }

                let score = centerScore + spanScore * 0.45
                if score < bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            if let bestIndex,
               bestScore <= 0.9 {
                tiedIndices.insert(bestIndex)
            }
        }

        return tiedIndices
    }

    private static func decisionByApplyingContextRules(
        _ decision: RhythmRecognitionDecision,
        meter: Meter
    ) -> RhythmRecognitionDecision {
        guard let proposal = decision.proposal,
              RhythmRecognitionContextRules.hasProtectedBeamableBoundary(
                in: proposal.values,
                meter: meter
              ) else {
            return decision
        }

        let reviewProposal = RhythmicNotationMeasureProposal(
            values: proposal.values,
            safety: .manualReview,
            isNaturalExactFit: proposal.isNaturalExactFit
        )
        return .needsReview(.manualReview, decision.phrase, reviewProposal)
    }

    private static func contextReasoningPath(
        for decision: RhythmRecognitionDecision,
        meter: Meter
    ) -> RhythmRecognitionReasoningPath {
        let values = decision.proposal?.values ?? decision.phrase?.naturalValues ?? []
        guard !values.isEmpty else {
            return RhythmRecognitionReasoningPath(
                kind: .contextRules,
                outcome: .unavailable,
                values: [],
                reason: decision.reason,
                summary: "context=unavailable"
            )
        }

        let isBlocked = RhythmRecognitionContextRules.hasProtectedBeamableBoundary(
            in: values,
            meter: meter
        )
        return RhythmRecognitionReasoningPath(
            kind: .contextRules,
            outcome: isBlocked ? .blocked : .commitCandidate,
            values: values,
            reason: isBlocked ? .manualReview : nil,
            summary: isBlocked ? "context=protectedMeterBoundary" : "context=ok"
        )
    }

    private static func quantizationError(
        for reason: RhythmRecognitionReason,
        phrase: RhythmPhraseHypothesis?,
        meter: Meter
    ) -> RhythmicNotationQuantizationError {
        let expectedBeats = meter.measureLengthInWholeNotes / meter.beatUnitWholeNoteLength
        let actualWholeNotes = Double(phrase?.naturalUnits ?? 0) / Double(rhythmUnits(forWholeNotes: 1))
        let actualBeats = actualWholeNotes / meter.beatUnitWholeNoteLength

        switch reason {
        case .underfilled, .noInk:
            return .underfilled(expectedBeats: expectedBeats, actualBeats: actualBeats)
        case .overflow:
            return .overflow(expectedBeats: expectedBeats, actualBeats: actualBeats)
        case .unsupported, .nonNaturalExactFit, .ambiguousPhrase, .manualReview, .uncoveredStrokes:
            return .unsupportedSymbol(0)
        }
    }

    private static func measureProposal(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect,
        includeExtendedStability: Bool
    ) throws -> RhythmicNotationMeasureProposal {
        try proposal(
            from: recognitionDecision(
                strokeObservations: strokeObservations(from: drawing),
                meter: meter,
                drawingFrame: drawingFrame,
                includeExtendedStability: includeExtendedStability
            ),
            meter: meter
        )
    }

    static func strokeObservations(from drawing: PKDrawing) -> [StrokeObservation] {
        drawing.strokes.compactMap { stroke in
            let points = Array(stroke.path).map(\.location)
            guard !points.isEmpty else {
                return nil
            }

            let bounds = points.reduce(into: CGRect.null) { partialResult, point in
                partialResult = partialResult.union(CGRect(origin: point, size: .zero).insetBy(dx: -0.5, dy: -0.5))
            }
            let pathLength = points.count < 2
                ? CGFloat.zero
                : zip(points, points.dropFirst()).reduce(CGFloat.zero) { partialResult, segment in
                    partialResult + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
                }
            let directionChanges = points.count < 3 ? 0 : directionChangeCount(for: points)

            return StrokeObservation(
                points: points,
                bounds: bounds.integral,
                pathLength: pathLength,
                startPoint: points.first ?? .zero,
                endPoint: points.last ?? .zero,
                directionChangeCount: directionChanges
            )
        }
    }

    private static func directionChangeCount(for points: [CGPoint]) -> Int {
        guard points.count >= 3 else {
            return 0
        }

        var changeCount = 0
        for index in 0..<(points.count - 2) {
            let firstDelta = CGPoint(
                x: points[index + 1].x - points[index].x,
                y: points[index + 1].y - points[index].y
            )
            let secondDelta = CGPoint(
                x: points[index + 2].x - points[index + 1].x,
                y: points[index + 2].y - points[index + 1].y
            )
            let firstMagnitude = hypot(firstDelta.x, firstDelta.y)
            let secondMagnitude = hypot(secondDelta.x, secondDelta.y)
            guard firstMagnitude > 0.2, secondMagnitude > 0.2 else {
                continue
            }

            let dotProduct = firstDelta.x * secondDelta.x + firstDelta.y * secondDelta.y
            let cosine = dotProduct / max(0.0001, firstMagnitude * secondMagnitude)
            if cosine < 0.35 {
                changeCount += 1
            }
        }

        return changeCount
    }

    static func rhythmUnits(for value: RhythmValue) -> Int {
        rhythmUnits(forWholeNotes: value.wholeNoteLength)
    }

    static func rhythmUnits(for value: RhythmValue, meter: Meter?) -> Int {
        guard let meter else {
            return rhythmUnits(for: value)
        }

        return rhythmUnits(forWholeNotes: value.wholeNoteLength(in: meter))
    }

    static func rhythmUnits(forWholeNotes wholeNotes: Double) -> Int {
        Int((wholeNotes * 16).rounded())
    }

    // Whole and half rests use the same horizontal block shape; placement resolves the value.
    private static func horizontalRestBlockPlacement(for features: SymbolFeatures) -> HorizontalRestBlockPlacement {
        guard features.hasHorizontalRestBlock else {
            return .ambiguous
        }

        if let shelfPlacement = horizontalRestShelfPlacement(for: features) {
            return shelfPlacement
        }

        let frameHeight = max(CGFloat(1), features.drawingFrame.height)
        let relativeMidY = (features.contentBounds.midY - features.drawingFrame.minY) / frameHeight
        if relativeMidY <= 0.49 {
            return .whole
        }
        if relativeMidY >= 0.51 {
            return .half
        }

        let centerTolerance = max(CGFloat(1.2), frameHeight * 0.015)
        if features.contentBounds.midY < features.drawingFrame.midY - centerTolerance {
            return .whole
        }
        if features.contentBounds.midY > features.drawingFrame.midY + centerTolerance {
            return .half
        }

        return .ambiguous
    }

    private static func horizontalRestShelfPlacement(for features: SymbolFeatures) -> HorizontalRestBlockPlacement? {
        let horizontalStrokes = features.contentStrokes.filter { stroke in
            stroke.looksLikeHorizontalRestBlockStroke(in: features.contentBounds)
                || (
                    stroke.bounds.width >= max(CGFloat(8), features.width * 0.42)
                        && stroke.bounds.height <= max(CGFloat(10), features.height * 0.62)
                        && stroke.pathLength >= max(CGFloat(6), stroke.bounds.width * 0.72)
                )
        }
        guard let shelfStroke = horizontalStrokes.max(by: { lhs, rhs in
            if abs(lhs.bounds.width - rhs.bounds.width) > 0.5 {
                return lhs.bounds.width < rhs.bounds.width
            }
            return lhs.pathLength < rhs.pathLength
        }) else {
            return nil
        }

        let bodyStrokes = features.contentStrokes.filter { $0 != shelfStroke }
        guard let bodyBounds = bodyStrokes.nonEmptyBounds else {
            return nil
        }

        let minimumSeparation = max(CGFloat(3), features.height * 0.14)
        if shelfStroke.bounds.midY <= bodyBounds.midY - minimumSeparation {
            return .whole
        }
        if shelfStroke.bounds.midY >= bodyBounds.midY + minimumSeparation {
            return .half
        }

        return nil
    }

    private static func looksLikeWholeRest(_ features: SymbolFeatures) -> Bool {
        if features.hasHorizontalRestBlock {
            return horizontalRestBlockPlacement(for: features) == .whole
        }

        guard features.width > features.height * 1.05,
              !features.hasStem,
              !features.hasStemAndKick,
              !features.hasFlag,
              !features.hasHollowHead else {
            return false
        }

        let denseBlock = features.contentStrokes.contains { stroke in
            stroke.looksDense
                && stroke.bounds.width > stroke.bounds.height * 0.95
                && stroke.bounds.height < features.height * 0.85
        }
        let compactRestBody = features.height <= max(16, features.width * 0.7)
        return denseBlock && compactRestBody
    }

    private static func looksLikeHalfRest(_ features: SymbolFeatures) -> Bool {
        if features.hasHorizontalRestBlock {
            let placement = horizontalRestBlockPlacement(for: features)
            return placement == .half || placement == .ambiguous
        }

        guard features.width > max(8, features.height * 1.05),
              !features.hasStem,
              !features.hasStemAndKick,
              !features.hasFlag,
              !features.hasHollowHead,
              !features.contentStrokes.contains(where: \.looksDense) else {
            return false
        }

        let horizontalStrokes = features.contentStrokes.filter(\.isMostlyHorizontal)
        guard !horizontalStrokes.isEmpty else {
            return false
        }

        let hasUpperStroke = horizontalStrokes.contains { stroke in
            stroke.bounds.midY <= features.contentBounds.midY + features.height * 0.2
        }
        let hasBaseOrCorners = features.contentStrokes.count >= 2
            || features.contentStrokes.contains { stroke in
                stroke.bounds.width > features.width * 0.55
                    && stroke.bounds.midY >= features.contentBounds.midY - features.height * 0.2
            }

        return hasUpperStroke && hasBaseOrCorners
    }
}

struct StrokeObservation: Hashable {
    let points: [CGPoint]
    let bounds: CGRect
    let pathLength: CGFloat
    let startPoint: CGPoint
    let endPoint: CGPoint
    let directionChangeCount: Int

    var looksClosed: Bool {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) <= max(6, pathLength * 0.12)
            && bounds.width > 5
            && bounds.height > 5
    }

    var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    var isMostlyVertical: Bool {
        bounds.height > max(6, bounds.width * 1.65)
    }

    var isMostlyHorizontal: Bool {
        bounds.width > max(6, bounds.height * 1.55)
    }

    var densityRatio: CGFloat {
        pathLength / max(1, (bounds.width + bounds.height) * 2)
    }

    var looksDense: Bool {
        densityRatio > 1.45 || directionChangeCount >= 5
    }

    var hasInteriorFillGesture: Bool {
        guard bounds.width > 4,
              bounds.height > 4 else {
            return false
        }

        let insetBounds = bounds.insetBy(dx: bounds.width * 0.15, dy: bounds.height * 0.15)
        let interiorPointCount = points.filter { insetBounds.contains($0) }.count
        return looksClosed && interiorPointCount >= 2
    }

    var looksHollowNoteHead: Bool {
        let ratio = bounds.width / max(1, bounds.height)
        let ovalish = ratio > 0.45 && ratio < 2.5
        let outlineLike = pathLength >= (bounds.width + bounds.height) * 0.75
            && pathLength <= (bounds.width + bounds.height) * 2.8
        let sparseOutline = pathLength <= (bounds.width + bounds.height) * 1.8

        return bounds.width > 5
            && bounds.height > 5
            && ovalish
            && outlineLike
            && !looksDense
            && (!hasInteriorFillGesture || sparseOutline)
    }

    var looksFilledNoteHead: Bool {
        let ratio = bounds.width / max(1, bounds.height)
        let ovalish = ratio > 0.45 && ratio < 2.5
        let sparseOutline = pathLength <= (bounds.width + bounds.height) * 1.8
        return bounds.width > 4
            && bounds.height > 4
            && ovalish
            && (looksDense || (hasInteriorFillGesture && !sparseOutline))
    }

    var looksLikeSingleStrokeEighthNote: Bool {
        let upperFlagBand = points.filter { point in
            point.y <= bounds.minY + bounds.height * 0.42
        }
        let upperXSpread = upperFlagBand.xSpread
        let hasUpperHook = upperXSpread >= max(4, bounds.width * 0.28)
        let hasEnoughBody = bounds.height > max(10, bounds.width * 1.0)
            && bounds.width >= max(5, bounds.height * 0.14)
        let hasHandwrittenTurn = directionChangeCount >= 1
            || pathLength > bounds.height * 1.22

        return hasEnoughBody
            && hasUpperHook
            && hasHandwrittenTurn
            && !looksClosed
    }

    var hasHorizontalUpperHook: Bool {
        guard points.count >= 2,
              bounds.width >= 3 else {
            return false
        }

        let topBandMaxY = bounds.minY + bounds.height * 0.38
        return zip(points, points.dropFirst()).contains { segment in
            let firstPoint = segment.0
            let secondPoint = segment.1
            let midpointY = (firstPoint.y + secondPoint.y) / 2
            guard midpointY <= topBandMaxY else {
                return false
            }

            let deltaX = secondPoint.x - firstPoint.x
            let deltaY = secondPoint.y - firstPoint.y
            let isBeamLike = abs(deltaX) >= max(CGFloat(3), abs(deltaY) * 1.15)
            let wideEnough = abs(deltaX) >= max(CGFloat(3), bounds.width * 0.18)
            return isBeamLike && wideEnough
        }
    }

    func isCompactMark(comparedTo referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(1, referenceBounds.height)
        let referenceWidth = max(1, referenceBounds.width)
        let compactWidth = bounds.width <= max(10, referenceWidth * 0.42)
        let compactHeight = bounds.height <= max(10, referenceHeight * 0.42)
        let shortPath = pathLength <= max(34, referenceHeight * 1.75)

        return compactWidth && compactHeight && shortPath
    }

    func hasRestBodyVerticalMotion(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let minimumEndpointTravel = max(CGFloat(5), bounds.height * 0.16)
        let minimumSegmentTravel = max(CGFloat(3), bounds.height * 0.12)
        let endpointTravelsDown = endPoint.y >= startPoint.y + minimumEndpointTravel
        let endpointTravelsUp = startPoint.y >= endPoint.y + minimumEndpointTravel
        let segmentDeltas = zip(points, points.dropFirst()).map { segment in
            segment.1.y - segment.0.y
        }
        let hasDownwardSegment = segmentDeltas.contains { $0 >= minimumSegmentTravel }
        let hasUpwardSegment = segmentDeltas.contains { $0 <= -minimumSegmentTravel }
        let spansEnoughBody = bounds.height >= max(CGFloat(16), referenceHeight * 0.42)
        let hasRestTurn = directionChangeCount >= 1
            || pathLength >= hypot(bounds.width, bounds.height) * 1.12

        return spansEnoughBody
            && (
                endpointTravelsDown
                    || (endpointTravelsUp && directionChangeCount >= 2)
                    || (hasDownwardSegment && hasRestTurn)
                    || (hasDownwardSegment && hasUpwardSegment)
            )
    }

    func looksLikeQuarterRestBody(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let coversRestHeight = bounds.height >= max(CGFloat(28), referenceHeight * 0.55)
        let narrowEnough = bounds.width <= max(referenceBounds.width * 1.05, bounds.height * 1.35)
        let spansBody = bounds.minY <= referenceBounds.minY + referenceHeight * 0.24
            && bounds.maxY >= referenceBounds.maxY - referenceHeight * 0.18
        let hasHandwrittenZigZag = directionChangeCount >= 2
            || (bounds.width <= bounds.height * 0.5 && pathLength >= bounds.height * 1.08)
        let hasRestGestureContour = bounds.height > bounds.width * 0.72 || directionChangeCount >= 2
        let upperHookSuggestsEighthRest = hasHorizontalUpperHook && directionChangeCount <= 2

        return coversRestHeight
            && narrowEnough
            && spansBody
            && hasRestBodyVerticalMotion(in: referenceBounds)
            && hasHandwrittenZigZag
            && hasRestGestureContour
            && !upperHookSuggestsEighthRest
            && !looksClosed
    }

    func looksLikeFlexibleOneStrokeQuarterRest(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let diagonalSpan = hypot(bounds.width, bounds.height)
        let horizontalDirections = zip(points, points.dropFirst()).compactMap { segment -> Int? in
            let deltaX = segment.1.x - segment.0.x
            guard abs(deltaX) >= 0.75 else {
                return nil
            }
            return deltaX > 0 ? 1 : -1
        }
        let horizontalTurnCount = zip(horizontalDirections, horizontalDirections.dropFirst())
            .filter { $0 != $1 }
            .count
        let coversRestHeight = bounds.height >= max(CGFloat(28), referenceHeight * 0.62)
        let narrowEnough = bounds.width <= max(CGFloat(18), bounds.height * 0.48)
        let hasRestMotion = directionChangeCount >= 2
            || horizontalTurnCount >= 2
            || (directionChangeCount >= 1 && pathLength >= diagonalSpan * 1.12)
        let moreThanStraightStroke = pathLength >= max(bounds.height * 1.02, diagonalSpan * 1.02)
            || horizontalTurnCount >= 2
        let upperHookSuggestsEighthRest = hasHorizontalUpperHook && directionChangeCount <= 2

        return coversRestHeight
            && narrowEnough
            && hasRestBodyVerticalMotion(in: referenceBounds)
            && hasRestMotion
            && moreThanStraightStroke
            && !upperHookSuggestsEighthRest
            && !looksClosed
            && !looksDense
            && !looksFilledNoteHead
            && !looksHollowNoteHead
    }

    func looksLikeFlexibleOneStrokeEighthRest(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let diagonalSpan = hypot(bounds.width, bounds.height)
        let horizontalDirections = zip(points, points.dropFirst()).compactMap { segment -> Int? in
            let deltaX = segment.1.x - segment.0.x
            guard abs(deltaX) >= 0.65 else {
                return nil
            }
            return deltaX > 0 ? 1 : -1
        }
        let horizontalTurnCount = zip(horizontalDirections, horizontalDirections.dropFirst())
            .filter { $0 != $1 }
            .count
        let compactHeight = bounds.height >= max(CGFloat(12), referenceHeight * 0.15)
            && bounds.height <= max(CGFloat(36), referenceHeight * 0.48)
        let narrowEnough = bounds.width <= max(CGFloat(22), bounds.height * 0.92)
        let drawnDownward = endPoint.y >= startPoint.y + max(CGFloat(5), bounds.height * 0.18)
        let hasOneZig = directionChangeCount >= 1
            || horizontalTurnCount >= 1
            || pathLength >= diagonalSpan * 1.08
        let notQuarterRestSize = bounds.height < max(CGFloat(42), referenceHeight * 0.56)

        return compactHeight
            && narrowEnough
            && drawnDownward
            && hasOneZig
            && notQuarterRestSize
            && !looksClosed
            && !looksHollowNoteHead
    }

    func looksLikeFlexibleOneStrokeSixteenthRest(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let horizontalDirections = zip(points, points.dropFirst()).compactMap { segment -> Int? in
            let deltaX = segment.1.x - segment.0.x
            guard abs(deltaX) >= 0.65 else {
                return nil
            }
            return deltaX > 0 ? 1 : -1
        }
        let horizontalTurnCount = zip(horizontalDirections, horizontalDirections.dropFirst())
            .filter { $0 != $1 }
            .count
        let compactHeight = bounds.height >= max(CGFloat(16), referenceHeight * 0.18)
            && bounds.height <= max(CGFloat(42), referenceHeight * 0.58)
        let narrowEnough = bounds.width <= max(CGFloat(24), bounds.height * 0.96)
        let drawnDownward = endPoint.y >= startPoint.y + max(CGFloat(6), bounds.height * 0.2)
        let hasTwoShortValueTurns = directionChangeCount >= 3
            || horizontalTurnCount >= 2
        let hasTwoFlagLevels = hasDistinctOneStrokeSixteenthRestFlagLevels(in: bounds)
        let notQuarterRestSize = bounds.height < max(CGFloat(48), referenceHeight * 0.64)

        return compactHeight
            && narrowEnough
            && drawnDownward
            && hasTwoShortValueTurns
            && hasTwoFlagLevels
            && notQuarterRestSize
            && !looksClosed
            && !looksHollowNoteHead
            && !looksFilledNoteHead
    }

    func hasDistinctOneStrokeSixteenthRestFlagLevels(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let horizontalDirections = zip(points, points.dropFirst()).compactMap { segment -> Int? in
            let deltaX = segment.1.x - segment.0.x
            guard abs(deltaX) >= 0.65 else {
                return nil
            }
            return deltaX > 0 ? 1 : -1
        }
        let horizontalTurnCount = zip(horizontalDirections, horizontalDirections.dropFirst())
            .filter { $0 != $1 }
            .count
        let upperPoints = points.filter { point in
            point.y <= referenceBounds.minY + referenceHeight * 0.32
        }
        let middleFlagPoints = points.filter { point in
            point.y >= referenceBounds.minY + referenceHeight * 0.44
                && point.y <= referenceBounds.minY + referenceHeight * 0.76
        }
        let lowerTailPoints = points.filter { point in
            point.y >= referenceBounds.minY + referenceHeight * 0.72
        }

        guard let upperBounds = upperPoints.nonEmptyBounds,
              let middleFlagBounds = middleFlagPoints.nonEmptyBounds,
              let lowerTailBounds = lowerTailPoints.nonEmptyBounds else {
            return false
        }

        let upperFlag = upperBounds.width >= max(CGFloat(4), referenceWidth * 0.24)
            || hasHorizontalUpperHook
        let middleFlag = middleFlagBounds.width >= max(CGFloat(6), referenceWidth * 0.34)
            && middleFlagBounds.height <= max(CGFloat(12), referenceHeight * 0.46)
        let separatedFlagLevels = middleFlagBounds.midY - upperBounds.midY >= max(CGFloat(6), referenceHeight * 0.22)
        let descendingTail = lowerTailBounds.maxY >= referenceBounds.minY + referenceHeight * 0.84
        let lowerFlagHasIndependentMotion = horizontalTurnCount >= 2
            || containsSegmentAngle(
                inDegrees: 0...55,
                minimumLength: max(CGFloat(4), referenceHeight * 0.16)
            )

        return upperFlag
            && middleFlag
            && separatedFlagLevels
            && descendingTail
            && lowerFlagHasIndependentMotion
    }

    func looksLikeShortRestBodyCandidate(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let diagonalSpan = hypot(bounds.width, bounds.height)
        let compactHeight = bounds.height >= max(CGFloat(14), referenceHeight * 0.18)
            && bounds.height <= max(CGFloat(44), referenceHeight * 0.7)
        let narrowEnough = bounds.width <= max(CGFloat(26), bounds.height * 1.02)
        let hasRestMotion = endPoint.y >= startPoint.y + max(CGFloat(4), bounds.height * 0.14)
            || hasRestBodyVerticalMotion(in: referenceBounds)
            || directionChangeCount >= 1
            || pathLength >= diagonalSpan * 1.05
        let hasHookOrFlag = hasHorizontalUpperHook
            || containsSegmentAngle(
                inDegrees: 0...60,
                minimumLength: max(CGFloat(3), bounds.height * 0.1)
            )

        return compactHeight
            && narrowEnough
            && hasRestMotion
            && hasHookOrFlag
            && !looksClosed
            && !looksLikeQuarterRestBody(in: referenceBounds)
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeSixteenthRestEighthBodyCandidate(
        symbolBounds: CGRect,
        sceneBounds: CGRect
    ) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let symbolHeight = max(CGFloat(1), symbolBounds.height)
        let compactHeight = bounds.height >= max(CGFloat(12), sceneHeight * 0.18)
            && bounds.height <= max(CGFloat(42), sceneHeight * 0.64)
        let narrowEnough = bounds.width <= max(CGFloat(26), bounds.height * 1.32)
        let reachesLowerRestBody = bounds.maxY >= symbolBounds.minY + symbolHeight * 0.54
        let hasRestGesture = looksLikeFlexibleOneStrokeEighthRest(in: sceneBounds)
            || looksLikeSingleStrokeEighthRest(in: symbolBounds)
            || looksLikeShortRestBodyCandidate(in: sceneBounds)
            || looksLikeShortRestBodyCandidate(in: symbolBounds)
            || hasRestBodyVerticalMotion(in: symbolBounds)
            || directionChangeCount >= 1

        return compactHeight
            && narrowEnough
            && reachesLowerRestBody
            && hasRestGesture
            && !looksClosed
            && !looksFilledNoteHead
            && !looksHollowNoteHead
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
            && !looksLikeNeutralHorizontalStrokePrimitive(in: symbolBounds)
    }

    func looksLikeAddedSixteenthRestFlag(
        attachedTo bodyBounds: CGRect,
        symbolBounds: CGRect,
        sceneBounds: CGRect
    ) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let bodyHeight = max(CGFloat(1), bodyBounds.height)
        let bodyWidth = max(CGFloat(1), bodyBounds.width)
        let compactEnough = bounds.height <= max(CGFloat(10), bodyHeight * 0.72)
            && bounds.width <= max(CGFloat(20), bodyWidth * 1.4)
        let visibleEnough = bounds.width >= max(CGFloat(3), bodyWidth * 0.18)
            || pathLength >= max(CGFloat(4), sceneHeight * 0.05)
            || isCompactMark(comparedTo: symbolBounds)
        let overlapsBodyHorizontally = bounds.maxX >= bodyBounds.minX - max(CGFloat(5), bodyWidth * 0.38)
            && bounds.minX <= bodyBounds.maxX + max(CGFloat(5), bodyWidth * 0.38)
        let internalFlagLane = center.y >= bodyBounds.minY + bodyHeight * 0.22
            && center.y <= bodyBounds.maxY + bodyHeight * 0.46
        let detachedDurationDot = bounds.minX >= bodyBounds.maxX + max(CGFloat(3), bodyWidth * 0.22)
        let topEighthRestDotLane = center.y <= bodyBounds.minY + bodyHeight * 0.18
        let compactInternalMark = isCompactMark(comparedTo: symbolBounds)
            || bounds.width <= max(CGFloat(8), bodyWidth * 0.72)
                && bounds.height <= max(CGFloat(8), bodyHeight * 0.42)

        return compactEnough
            && visibleEnough
            && overlapsBodyHorizontally
            && internalFlagLane
            && !detachedDurationDot
            && !topEighthRestDotLane
            && (!looksClosed || compactInternalMark)
            && (!looksFilledNoteHead || compactInternalMark)
            && !looksHollowNoteHead
    }

    func looksLikeQuarterRestSegment(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let largeEnough = bounds.height >= referenceHeight * 0.18
            || bounds.width >= max(CGFloat(5), referenceBounds.width * 0.32)
        let angledOrCurved = directionChangeCount >= 1
            || (!isMostlyHorizontal && !isMostlyVertical)
            || pathLength >= max(CGFloat(8), hypot(bounds.width, bounds.height) * 1.0)

        return largeEnough
            && angledOrCurved
            && !looksClosed
            && !isCompactMark(comparedTo: referenceBounds)
    }

    func looksLikeHorizontalRestBlockStroke(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let wideEnough = bounds.width >= max(CGFloat(8), referenceHeight * 0.14)
        let compactEnough = bounds.height <= max(CGFloat(24), referenceHeight * 0.32)
        let horizontalBody = isMostlyHorizontal
            || (bounds.width >= bounds.height * 0.85 && (looksDense || looksClosed))
        let notVerticalGlyph = !looksLikeNeutralVerticalStrokePrimitive(in: referenceBounds)
            && !looksLikeVisualStem(in: referenceBounds)

        return wideEnough
            && compactEnough
            && horizontalBody
            && notVerticalGlyph
            && !looksLikeLooseDot(in: referenceBounds)
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeEighthRestHook(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        if looksLikeEighthRestDot(in: referenceBounds) {
            return true
        }

        let compactEnough = bounds.width <= max(CGFloat(18), referenceWidth * 0.68)
            && bounds.height <= max(CGFloat(14), referenceHeight * 0.48)
        let upperLeftEnough = center.y <= referenceBounds.midY + referenceHeight * 0.2
            && center.x <= referenceBounds.midX + referenceWidth * 0.18
        let hookLike = isCompactMark(comparedTo: referenceBounds)
            || looksFilledNoteHead
            || directionChangeCount >= 1
            || bounds.width >= bounds.height * 0.72

        return compactEnough
            && upperLeftEnough
            && hookLike
            && (!looksClosed || looksFilledNoteHead)
    }

    func looksLikeSingleStrokeEighthRest(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let touchesUpperBody = bounds.minY <= referenceBounds.midY + referenceHeight * 0.1
        let reachesLowerBody = bounds.maxY >= referenceBounds.midY + referenceHeight * 0.18
            || bounds.maxY >= referenceBounds.maxY - referenceHeight * 0.12
        let hasHookOrLean = hasHorizontalUpperHook
            || directionChangeCount >= 1
            || bounds.width >= max(CGFloat(5), bounds.height * 0.18)
        let restSized = bounds.height >= max(CGFloat(8), referenceHeight * 0.42)
            && bounds.width <= max(CGFloat(28), referenceBounds.width * 1.12)

        return restSized
            && touchesUpperBody
            && reachesLowerBody
            && hasHookOrLean
            && !looksLikeQuarterRestBody(in: referenceBounds)
            && !looksClosed
    }

    func looksLikeEighthRestDot(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let compactEnough = bounds.width <= max(CGFloat(10), referenceWidth * 0.42)
            && bounds.height <= max(CGFloat(10), referenceHeight * 0.36)
        let topEnough = center.y <= referenceBounds.minY + referenceHeight * 0.34
            && bounds.maxY <= referenceBounds.minY + referenceHeight * 0.5
        let notTooFarRight = center.x <= referenceBounds.midX + referenceWidth * 0.28
        let filledCircle = looksFilledNoteHead || (looksClosed && (looksDense || hasInteriorFillGesture))
        let tapDot = pathLength <= 1
            && bounds.width <= max(CGFloat(4), referenceWidth * 0.22)
            && bounds.height <= max(CGFloat(4), referenceHeight * 0.22)
        let compactHandwrittenDot = isCompactMark(comparedTo: referenceBounds)
            && bounds.width >= 1
            && bounds.height >= 1
            && (directionChangeCount >= 2 || looksDense)

        return compactEnough
            && topEnough
            && notTooFarRight
            && (filledCircle || tapDot || compactHandwrittenDot)
    }

    func hasTwoRestFlagLevels(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let upperPoints = points.filter { point in
            point.y <= referenceBounds.minY + referenceHeight * 0.38
        }
        let middlePoints = points.filter { point in
            point.y >= referenceBounds.minY + referenceHeight * 0.42
                && point.y <= referenceBounds.minY + referenceHeight * 0.78
        }
        guard let upperBounds = upperPoints.nonEmptyBounds,
              let middleBounds = middlePoints.nonEmptyBounds else {
            return false
        }

        let upperHook = upperBounds.width >= max(CGFloat(3), referenceWidth * 0.16)
            || upperBounds.height >= max(CGFloat(3), referenceHeight * 0.08)
        let middleHook = middleBounds.width >= max(CGFloat(4.5), referenceWidth * 0.22)
            || (
                middleBounds.width >= max(CGFloat(3), referenceWidth * 0.14)
                    && containsSegmentAngle(
                        inDegrees: 0...55,
                        minimumLength: max(CGFloat(3), referenceHeight * 0.09)
                    )
            )
        let separatedLevels = middleBounds.midY - upperBounds.midY >= max(CGFloat(4), referenceHeight * 0.16)
        return upperHook && middleHook && separatedLevels
    }

    func looksLikeEighthRestDescendingTail(
        belowOrBeside dot: StrokeObservation,
        in referenceBounds: CGRect
    ) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let tallEnough = bounds.height >= max(CGFloat(10), referenceHeight * 0.36)
        let reachesLowerBody = bounds.maxY >= referenceBounds.midY + referenceHeight * 0.14
            || bounds.maxY >= dot.bounds.maxY + referenceHeight * 0.34
        let startsNearDot = bounds.minY <= dot.bounds.maxY + referenceHeight * 0.28
        let closeHorizontally = bounds.minX <= dot.bounds.maxX + referenceWidth * 0.72
            && bounds.maxX >= dot.bounds.minX - referenceWidth * 0.28
        let mostlyTailLike = bounds.width <= max(CGFloat(30), referenceWidth * 1.08)
            && pathLength >= max(CGFloat(10), hypot(bounds.width, bounds.height) * 0.9)
        let explicitDotAnchorsTail = bounds.width <= max(CGFloat(14), referenceWidth * 0.78)
            && dot.bounds.maxY <= bounds.minY + referenceHeight * 0.34

        return !looksClosed
            && tallEnough
            && reachesLowerBody
            && startsNearDot
            && closeHorizontally
            && mostlyTailLike
            && (!looksLikeQuarterRestBody(in: referenceBounds) || explicitDotAnchorsTail)
    }

    func looksLikeRhythmicPlaceholderSlash(in referenceBounds: CGRect) -> Bool {
        let leftPoint = points.min { lhs, rhs in
            if abs(lhs.x - rhs.x) > 0.001 {
                return lhs.x < rhs.x
            }
            return lhs.y > rhs.y
        } ?? startPoint
        let rightPoint = points.max { lhs, rhs in
            if abs(lhs.x - rhs.x) > 0.001 {
                return lhs.x < rhs.x
            }
            return lhs.y > rhs.y
        } ?? endPoint
        let horizontalTravel = max(CGFloat(0), rightPoint.x - leftPoint.x)
        let upwardTravel = max(CGFloat(0), leftPoint.y - rightPoint.y)
        let axisAngle = atan2(upwardTravel, max(CGFloat(0.001), horizontalTravel)) * 180 / .pi
        let diagonalSpan = hypot(bounds.width, bounds.height)
        let straightEnough = pathLength <= max(diagonalSpan * 2.0, diagonalSpan + 14)

        return axisAngle >= 10
            && axisAngle <= 80
            && horizontalTravel >= 4
            && upwardTravel >= 4
            && diagonalSpan >= 8
            && straightEnough
            && !looksClosed
            && !looksDense
    }

    func containsSegmentAngle(inDegrees angleRange: ClosedRange<CGFloat>, minimumLength: CGFloat) -> Bool {
        zip(points, points.dropFirst()).contains { firstPoint, secondPoint in
            let deltaX = secondPoint.x - firstPoint.x
            let deltaY = secondPoint.y - firstPoint.y
            let length = hypot(deltaX, deltaY)
            guard length >= minimumLength else {
                return false
            }

            let angle = atan2(abs(deltaY), abs(deltaX)) * 180 / .pi
            return angleRange.contains(angle)
        }
    }

    func looksLikeLowerNotehead(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let separatedLowerBody = center.y >= referenceBounds.midY + referenceHeight * 0.06
            || bounds.maxY >= referenceBounds.maxY - referenceHeight * 0.18
        let noteheadSized = bounds.width >= max(CGFloat(7), referenceWidth * 0.12)
            && bounds.height >= max(CGFloat(5), referenceHeight * 0.1)
        let ovalOrDenseHead = looksClosed
            || (looksFilledNoteHead && bounds.width >= bounds.height * 0.5)
        let notStemOrTail = bounds.width >= bounds.height * 0.48

        return separatedLowerBody
            && noteheadSized
            && ovalOrDenseHead
            && notStemOrTail
    }
}

extension StrokeObservation {
    var isNoteheadLikeMark: Bool {
        bounds.width >= 4
            && bounds.height >= 4
            && (looksFilledNoteHead || looksHollowNoteHead || looksClosed)
    }

    func looksLikeRhythmNotehead(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let largeEnough = bounds.width >= 4
            && bounds.height >= 4
        let lowerOrSubstantial = center.y >= sceneBounds.minY + sceneHeight * 0.32
            || bounds.height >= sceneHeight * 0.18
        let roundedHead = looksFilledNoteHead || looksHollowNoteHead

        return largeEnough
            && lowerOrSubstantial
            && roundedHead
            && !looksLikeZigZagBodyPrimitive(in: sceneBounds)
            && !looksLikeNeutralVerticalStrokePrimitive(in: sceneBounds)
    }

    func looksLikeOpenRhythmNotehead(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let sceneWidth = max(CGFloat(1), sceneBounds.width)
        let largeEnough = bounds.width >= max(CGFloat(7), sceneWidth * 0.06)
            && bounds.height >= max(CGFloat(6), sceneHeight * 0.12)
        let lowerEnough = center.y >= sceneBounds.minY + sceneHeight * 0.38
            || bounds.maxY >= sceneBounds.maxY - sceneHeight * 0.16
        let aspect = bounds.width / max(CGFloat(1), bounds.height)
        let ovalish = aspect >= 0.45 && aspect <= 2.25
        let outlineLength = pathLength >= max(CGFloat(10), (bounds.width + bounds.height) * 0.68)
        let notStraightAxis = !isMostlyVertical && !isMostlyHorizontal
        let openOrCurved = looksHollowNoteHead
            || looksClosed
            || directionChangeCount >= 1
            || pathLength >= hypot(bounds.width, bounds.height) * 1.18

        return largeEnough
            && lowerEnough
            && ovalish
            && outlineLength
            && notStraightAxis
            && openOrCurved
            && !looksDense
            && !looksLikeZigZagBodyPrimitive(in: sceneBounds)
            && !looksLikeNeutralVerticalStrokePrimitive(in: sceneBounds)
            && !looksLikeShortRestBodyCandidate(in: sceneBounds)
    }

    func looksLikeZigZagBodyPrimitive(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let diagonalSpan = hypot(bounds.width, bounds.height)
        let tallEnough = bounds.height >= max(CGFloat(14), referenceHeight * 0.14)
        let yDominant = bounds.height >= bounds.width * 1.18
        let hasAngularMotion = directionChangeCount >= 1
            || pathLength >= diagonalSpan * 1.08
        let stemLikeVertical = isMostlyVertical
            && bounds.width <= max(CGFloat(8), bounds.height * 0.24)
            && directionChangeCount <= 1
            && pathLength <= bounds.height * 1.8
        let notPlainStem = !stemLikeVertical

        return tallEnough
            && yDominant
            && hasAngularMotion
            && notPlainStem
            && !looksClosed
            && !looksLikeLooseDot(in: referenceBounds)
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeNeutralVerticalStrokePrimitive(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let tallEnough = bounds.height >= max(CGFloat(12), referenceHeight * 0.16)
        let narrowEnough = bounds.width <= max(CGFloat(12), bounds.height * 0.5)
        let mostlyStraight = directionChangeCount <= 1
            && pathLength <= bounds.height * 2.2

        return tallEnough
            && narrowEnough
            && mostlyStraight
            && !looksClosed
            && !looksLikeLooseDot(in: referenceBounds)
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeNeutralHorizontalStrokePrimitive(in referenceBounds: CGRect) -> Bool {
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let wideEnough = bounds.width >= max(CGFloat(10), referenceWidth * 0.07)
        let thinEnough = bounds.height <= max(CGFloat(10), bounds.width * 0.5)
        let mostlyStraight = directionChangeCount <= 1
            && pathLength <= bounds.width * 2.1

        return wideEnough
            && thinEnough
            && mostlyStraight
            && !looksClosed
            && !looksLikeLooseDot(in: referenceBounds)
    }

    func looksLikeNeutralDiagonalStrokePrimitive(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let largeEnough = bounds.width >= max(CGFloat(6), referenceHeight * 0.07)
            && bounds.height >= max(CGFloat(8), referenceHeight * 0.1)
        let diagonalEnough = !isMostlyHorizontal
            && !isMostlyVertical
            && abs(endPoint.x - startPoint.x) >= bounds.width * 0.42
            && abs(endPoint.y - startPoint.y) >= bounds.height * 0.42
        let mostlyStraight = directionChangeCount <= 1
            && pathLength <= hypot(bounds.width, bounds.height) * 1.55

        return largeEnough
            && diagonalEnough
            && mostlyStraight
            && !looksClosed
            && !looksLikeLooseDot(in: referenceBounds)
    }

    func looksLikeNeutralCurveHookPrimitive(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let compactEnough = bounds.height <= max(CGFloat(22), referenceHeight * 0.36)
        let hasCurveOrHook = hasHorizontalUpperHook
            || directionChangeCount >= 1
            || pathLength >= hypot(bounds.width, bounds.height) * 1.12

        return compactEnough
            && hasCurveOrHook
            && !looksClosed
            && !looksLikeLooseDot(in: referenceBounds)
            && !looksLikeVisualStem(in: referenceBounds)
    }

    func looksLikeVisualStem(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let tallEnough = bounds.height >= max(CGFloat(9), sceneHeight * 0.32)
        let narrowEnough = bounds.width <= max(CGFloat(10), bounds.height * 0.55)

        return tallEnough
            && narrowEnough
            && !looksClosed
            && !looksLikeLooseDot(in: sceneBounds)
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
            && (isMostlyVertical || pathLength <= bounds.height * 2.4 || looksLikeSingleStrokeEighthNote)
    }

    func looksLikeVisualBeamSeed(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let wideEnough = bounds.width >= max(CGFloat(10), sceneHeight * 0.2)
        let thinEnough = bounds.height <= max(CGFloat(9), sceneHeight * 0.22)

        return wideEnough
            && thinEnough
            && isMostlyHorizontal
            && !looksClosed
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeSlopedVisualBeamSeed(
        over stems: [StrokeObservation],
        in sceneBounds: CGRect,
        drawingFrame: CGRect
    ) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let wideEnough = bounds.width >= max(CGFloat(12), sceneHeight * 0.24)
        let compactEnough = bounds.height <= max(CGFloat(16), sceneHeight * 0.38)
        let horizontalEnough = bounds.width >= bounds.height * 1.2
        let strokeIsSimple = directionChangeCount <= 2
            && pathLength <= hypot(bounds.width, bounds.height) * 1.45
        let coveragePadding = max(CGFloat(9), drawingFrame.width * 0.03)
        let verticalReach = max(CGFloat(12), sceneHeight * 0.22)
        let coveredStemCount = stems.filter { stem in
            bounds.minX - coveragePadding <= stem.bounds.midX
                && bounds.maxX + coveragePadding >= stem.bounds.midX
                && stem.bounds.minY <= bounds.maxY + verticalReach
                && stem.bounds.maxY >= bounds.minY - verticalReach * 0.35
        }.count

        return wideEnough
            && compactEnough
            && horizontalEnough
            && strokeIsSimple
            && coveredStemCount >= 2
            && !looksClosed
            && !looksLikeVisualStem(in: sceneBounds)
            && !looksLikeRhythmNotehead(in: sceneBounds)
    }

    func looksLikeFoldedBeamStemSeed(
        over stems: [StrokeObservation],
        in sceneBounds: CGRect,
        drawingFrame: CGRect
    ) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let inferredStemXs = connectedBeamStemXs(in: bounds)
        guard inferredStemXs.count == 1,
              let inferredStemX = inferredStemXs.first else {
            return false
        }

        let wideEnough = bounds.width >= max(CGFloat(12), sceneHeight * 0.22)
        let tallEnough = bounds.height >= max(CGFloat(12), sceneHeight * 0.28)
        let notTooTall = bounds.height <= max(CGFloat(42), sceneHeight * 0.82)
        let strokeIsSimple = directionChangeCount <= 2
            && pathLength <= (bounds.width + bounds.height) * 1.45
        let topBandMaxY = bounds.minY + bounds.height * 0.42
        let topPoints = points.filter { $0.y <= topBandMaxY }
        let hasBeamTop = topPoints.xSpread >= max(CGFloat(10), bounds.width * 0.42)
        let coveragePadding = max(CGFloat(9), drawingFrame.width * 0.03)
        let verticalReach = max(CGFloat(12), sceneHeight * 0.22)
        let hasExternalStem = stems.contains { stem in
            abs(stem.bounds.midX - inferredStemX) >= max(CGFloat(10), drawingFrame.width * 0.035)
                && bounds.minX - coveragePadding <= stem.bounds.midX
                && bounds.maxX + coveragePadding >= stem.bounds.midX
                && stem.bounds.minY <= bounds.maxY + verticalReach
                && stem.bounds.maxY >= bounds.minY - verticalReach * 0.35
        }
        return wideEnough
            && tallEnough
            && notTooTall
            && strokeIsSimple
            && hasBeamTop
            && hasExternalStem
            && !looksClosed
            && !looksLikeRhythmicPlaceholderSlash(in: bounds)
    }

    func looksLikeVisualRestDot(in referenceBounds: CGRect) -> Bool {
        looksLikeEighthRestDot(in: referenceBounds)
    }

    func looksLikeLooseDot(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let maxDotSide = max(CGFloat(10), min(CGFloat(14), referenceHeight * 0.26))
        let compactEnough = bounds.width <= maxDotSide
            && bounds.height <= maxDotSide
        let shortEnough = pathLength <= max(CGFloat(36), referenceHeight * 1.5)
        let dotLikeBody = pathLength <= 1
            || looksFilledNoteHead
            || isCompactMark(comparedTo: referenceBounds)

        return compactEnough
            && shortEnough
            && dotLikeBody
    }

    func looksLikeTieArc(in referenceBounds: CGRect) -> Bool {
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let wideEnough = bounds.width >= max(CGFloat(18), referenceWidth * 0.08)
        let shallowEnough = bounds.height <= max(CGFloat(18), bounds.width * 0.34)
        let tallEnoughToCurve = bounds.height >= max(CGFloat(3), referenceHeight * 0.035)
        let endpointsLevel = abs(startPoint.y - endPoint.y) <= max(CGFloat(9), bounds.height * 0.85)
        let horizontalTravel = abs(endPoint.x - startPoint.x) >= bounds.width * 0.62
        let chordLength = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        let hasCurvature = pathLength >= max(chordLength + 2.5, chordLength * 1.05)
            || directionChangeCount >= 1
        let notStraightBeam = bounds.height >= 4
            || pathLength >= chordLength * 1.08

        return wideEnough
            && shallowEnough
            && tallEnoughToCurve
            && endpointsLevel
            && horizontalTravel
            && hasCurvature
            && notStraightBeam
            && !looksClosed
            && !looksDense
            && !isMostlyVertical
    }

    func looksLikeAugmentationDot(toRightOf symbolBounds: CGRect, headBounds: CGRect) -> Bool {
        let horizontalGap = bounds.minX - symbolBounds.maxX
        let rightOfHead = bounds.midX >= headBounds.midX + headBounds.width * 0.75
        let closeEnough = horizontalGap <= max(CGFloat(34), symbolBounds.width * 1.15)
        let verticallyAligned = abs(bounds.midY - headBounds.midY) <= max(CGFloat(14), headBounds.height * 1.35)

        return rightOfHead
            && closeEnough
            && verticallyAligned
    }

    func looksLikeVisualFlag(near stem: StrokeObservation, in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let nearStemTop = bounds.minY <= stem.bounds.minY + sceneHeight * 0.34
            && center.y <= stem.bounds.midY
        let closeToStem = bounds.minX <= stem.bounds.maxX + sceneHeight * 0.35
            && bounds.maxX >= stem.bounds.minX - sceneHeight * 0.18
        let flagShape = hasHorizontalUpperHook
            || bounds.width >= max(CGFloat(4), sceneHeight * 0.08)
            || directionChangeCount >= 1
        let compactDotOnly = looksLikeLooseDot(in: sceneBounds)
            && bounds.width <= max(CGFloat(6), sceneHeight * 0.16)
            && bounds.height <= max(CGFloat(6), sceneHeight * 0.16)

        return !looksClosed
            && nearStemTop
            && closeToStem
            && flagShape
            && !compactDotOnly
    }

    func isIsolatedPlaceholderSlash(
        among strokes: [StrokeObservation],
        sceneBounds: CGRect
    ) -> Bool {
        let nearbyStructuralStroke = strokes.contains { other in
            guard other != self else {
                return false
            }

            let horizontalDistance = abs(other.bounds.midX - bounds.midX)
            let verticalDistance = abs(other.bounds.midY - bounds.midY)
            let nearEnough = horizontalDistance <= max(CGFloat(18), sceneBounds.width * 0.07)
                && verticalDistance <= max(CGFloat(24), sceneBounds.height * 0.42)
            return nearEnough
                && (other.looksLikeVisualStem(in: sceneBounds)
                    || other.looksLikeRhythmNotehead(in: sceneBounds)
                    || other.looksLikeVisualBeamSeed(in: sceneBounds))
        }

        return !nearbyStructuralStroke
    }

    func isIgnorableVisualNoise(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        return bounds.width <= 1.5
            && bounds.height <= 1.5
            && pathLength <= 0.5
            && center.y < sceneBounds.minY - sceneHeight * 0.15
    }

    func isIgnorableRasterTemplateNoise(
        among strokes: [StrokeObservation],
        drawingFrame: CGRect
    ) -> Bool {
        guard isTinyRasterTemplateNoiseMark(in: drawingFrame) else {
            return false
        }

        let nearbyStructuralInk = strokes.contains { other in
            guard other != self,
                  !other.isTinyRasterTemplateNoiseMark(in: drawingFrame) else {
                return false
            }

            let horizontalDistance = abs(other.bounds.midX - bounds.midX)
            let verticalDistance = abs(other.bounds.midY - bounds.midY)
            return horizontalDistance <= max(CGFloat(10), drawingFrame.width * 0.04)
                && verticalDistance <= max(CGFloat(12), drawingFrame.height * 0.18)
        }

        return !nearbyStructuralInk
    }

    private func isTinyRasterTemplateNoiseMark(in drawingFrame: CGRect) -> Bool {
        bounds.width <= max(CGFloat(2.5), drawingFrame.width * 0.008)
            && bounds.height <= max(CGFloat(2.5), drawingFrame.height * 0.03)
            && pathLength <= max(CGFloat(2.5), drawingFrame.height * 0.03)
    }

    func isCloseToVisualSymbol(
        anchoredBy anchor: StrokeObservation,
        in sceneBounds: CGRect
    ) -> Bool {
        let symbolHeight = max(CGFloat(1), sceneBounds.height)
        let candidateBounds = bounds.union(anchor.bounds)
        let horizontalGap = max(
            CGFloat(0),
            max(bounds.minX, anchor.bounds.minX) - min(bounds.maxX, anchor.bounds.maxX)
        )
        let verticalGap = max(
            CGFloat(0),
            max(bounds.minY, anchor.bounds.minY) - min(bounds.maxY, anchor.bounds.maxY)
        )

        return candidateBounds.width <= max(CGFloat(34), symbolHeight * 0.9)
            && candidateBounds.height <= max(CGFloat(46), symbolHeight * 1.15)
            && horizontalGap <= max(CGFloat(10), symbolHeight * 0.34)
            && verticalGap <= max(CGFloat(12), symbolHeight * 0.38)
    }

    func isBeamedEventTouchUp(
        near eventBounds: CGRect,
        sceneBounds: CGRect,
        drawingFrame: CGRect
    ) -> Bool {
        let glyphLike = looksLikeVisualStem(in: sceneBounds)
            || looksLikeRhythmNotehead(in: sceneBounds)
            || looksLikeVisualBeamSeed(in: sceneBounds)
            || looksLikeLooseDot(in: sceneBounds)
        guard glyphLike else {
            return false
        }

        let horizontalPadding = max(CGFloat(10), drawingFrame.width * 0.04)
        let verticalPadding = max(CGFloat(8), sceneBounds.height * 0.18)
        let expandedBounds = eventBounds.insetBy(
            dx: -horizontalPadding,
            dy: -verticalPadding
        )

        return expandedBounds.intersects(bounds)
            || expandedBounds.contains(center)
    }
}

struct SymbolObservation: Hashable {
    let strokes: [StrokeObservation]
    let bounds: CGRect

    init(strokes: [StrokeObservation]) {
        self.strokes = strokes
        self.bounds = strokes.reduce(into: CGRect.null) { partialResult, stroke in
            partialResult = partialResult.union(stroke.bounds)
        }
    }
}

extension SymbolObservation {
    func sixteenthRestComparisonScore(in sceneBounds: CGRect) -> CGFloat? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty else {
            return nil
        }

        if let score = eighthRestBodyPlusAddedFlagScore(in: sceneBounds) {
            return score
        }

        let features = SymbolFeatures(symbol: self, drawingFrame: sceneBounds)
        guard !features.hasStem,
              !features.hasClearNoteGlyph,
              !features.hasFilledHead,
              !features.hasHollowHead,
              !features.hasLowerHeadMass,
              !containsNoteheadSizedMass(in: sceneBounds) else {
            return nil
        }

        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let symbolHeight = max(CGFloat(1), bounds.height)
        let symbolWidth = max(CGFloat(1), bounds.width)
        let narrowRestEnvelope = symbolWidth <= max(CGFloat(42), sceneHeight * 1.05)
        let tallEnough = symbolHeight >= max(CGFloat(18), sceneHeight * 0.34)
        guard narrowRestEnvelope,
              tallEnough,
              !containsLowerNoteheadMass(in: sceneBounds) else {
            return nil
        }

        let singleStrokeDoubleFlag = strokes.count == 1 && strokes.contains { stroke in
            stroke.looksLikeFlexibleOneStrokeSixteenthRest(in: sceneBounds)
        }
        let twoFlagLevels = strokes.count >= 2
            && (
                strokes.contains { stroke in
                    stroke.hasTwoRestFlagLevels(in: bounds)
                } || hasTwoRestFlagLevels(in: sceneBounds)
            )
        guard singleStrokeDoubleFlag || twoFlagLevels else {
            return nil
        }

        let baseScore = eighthRestComparisonScore(in: sceneBounds)
            ?? sevenLikeEighthRestComparisonScore(in: sceneBounds)
            ?? CGFloat(0.22)
        let secondFlagPenalty = singleStrokeDoubleFlag ? CGFloat(0) : CGFloat(0.08)
        return baseScore + secondFlagPenalty
    }

    private func eighthRestBodyPlusAddedFlagScore(in sceneBounds: CGRect) -> CGFloat? {
        guard strokes.count >= 2,
              strokes.count <= 5 else {
            return nil
        }

        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let symbolHeight = max(CGFloat(1), bounds.height)
        let symbolWidth = max(CGFloat(1), bounds.width)
        guard symbolWidth <= max(CGFloat(42), sceneHeight * 1.05),
              symbolHeight >= max(CGFloat(14), sceneHeight * 0.24),
              symbolHeight <= max(CGFloat(46), sceneHeight * 0.74) else {
            return nil
        }

        let bodyCandidates = strokes.filter { stroke in
            stroke.looksLikeSixteenthRestEighthBodyCandidate(
                symbolBounds: bounds,
                sceneBounds: sceneBounds
            )
        }

        guard !bodyCandidates.isEmpty else {
            return nil
        }

        for body in bodyCandidates {
            let addedFlags = strokes.filter { stroke in
                stroke != body
                    && stroke.looksLikeAddedSixteenthRestFlag(
                        attachedTo: body.bounds,
                        symbolBounds: bounds,
                        sceneBounds: sceneBounds
                    )
            }
            guard !addedFlags.isEmpty else {
                continue
            }

            let baseScore = SymbolObservation(strokes: [body]).eighthRestComparisonScore(in: sceneBounds)
                ?? SymbolObservation(strokes: [body]).sevenLikeEighthRestComparisonScore(in: sceneBounds)
                ?? CGFloat(0.18)
            let flagScore = addedFlags.map { flag in
                let verticalTarget = body.bounds.minY + body.bounds.height * 0.48
                return abs(flag.bounds.midY - verticalTarget) / max(CGFloat(1), body.bounds.height) * 0.12
            }.min() ?? 0
            return baseScore + flagScore
        }

        return nil
    }

    func eighthRestComparisonScore(in sceneBounds: CGRect) -> CGFloat? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty else {
            return nil
        }

        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let symbolHeight = max(CGFloat(1), bounds.height)
        let symbolWidth = max(CGFloat(1), bounds.width)
        let narrowRestEnvelope = symbolWidth <= max(CGFloat(42), sceneHeight * 1.05)
        let tallEnough = symbolHeight >= max(CGFloat(18), sceneHeight * 0.34)
        guard narrowRestEnvelope,
              tallEnough,
              !containsLowerNoteheadMass(in: sceneBounds) else {
            return nil
        }

        if let sevenLikeScore = sevenLikeEighthRestComparisonScore(in: sceneBounds) {
            return sevenLikeScore
        }

        let verticalEnough = symbolHeight >= symbolWidth * 1.15
        guard verticalEnough else {
            return nil
        }

        let topDotPoints = points.filter { point in
            point.x <= bounds.minX + symbolWidth * 0.58
                && point.y <= bounds.minY + symbolHeight * 0.42
        }
        guard let dotBounds = topDotPoints.nonEmptyBounds else {
            return nil
        }

        let dotAspect = dotBounds.width / max(CGFloat(1), dotBounds.height)
        let topAnchoredDot = dotBounds.midY <= bounds.minY + symbolHeight * 0.31
            && dotBounds.maxY <= bounds.minY + symbolHeight * 0.46
        let compactFilledDot = topDotPoints.count >= max(7, points.count / 7)
            && dotBounds.width >= 3
            && dotBounds.height >= 3
            && dotBounds.width <= max(CGFloat(15), symbolWidth * 0.78)
            && dotBounds.height <= max(CGFloat(16), symbolHeight * 0.58)
            && dotAspect >= 0.35
            && dotAspect <= 2.4
            && topAnchoredDot

        let hookPoints = points.filter { point in
            point.x >= dotBounds.maxX + max(CGFloat(2.5), symbolWidth * 0.1)
                && point.y >= dotBounds.minY - max(CGFloat(4), symbolHeight * 0.12)
                && point.y <= dotBounds.maxY + max(CGFloat(9), symbolHeight * 0.25)
        }
        let tailPoints = points.filter { point in
            point.y >= dotBounds.maxY + max(CGFloat(4), symbolHeight * 0.12)
                && point.x >= bounds.minX - symbolWidth * 0.1
                && point.x <= bounds.maxX + symbolWidth * 0.12
        }
        guard let hookBounds = hookPoints.nonEmptyBounds,
              let tailBounds = tailPoints.nonEmptyBounds else {
            return nil
        }

        let outwardHook = hookBounds.maxX >= dotBounds.maxX + max(CGFloat(4), symbolWidth * 0.18)
            || hookBounds.width >= max(CGFloat(2.4), symbolWidth * 0.14)
        let descendingTail = tailBounds.height >= max(CGFloat(8), symbolHeight * 0.28)
            && tailBounds.maxY >= bounds.minY + symbolHeight * 0.82
            && tailBounds.width <= max(CGFloat(20), symbolWidth * 1.35)

        guard compactFilledDot, outwardHook, descendingTail else {
            return nil
        }

        let idealAspect = CGFloat(0.48)
        let aspectScore = abs((symbolWidth / symbolHeight) - idealAspect)
        let dotPlacementScore = abs((dotBounds.midY - bounds.minY) / symbolHeight - 0.2)
        let hookScore = max(CGFloat(0), CGFloat(5) - hookBounds.width) * 0.05
        return aspectScore + dotPlacementScore + hookScore
    }

    func sevenLikeEighthRestComparisonScore(in sceneBounds: CGRect) -> CGFloat? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty else {
            return nil
        }

        let symbolHeight = max(CGFloat(1), bounds.height)
        let symbolWidth = max(CGFloat(1), bounds.width)
        let totalDirectionChanges = strokes.reduce(0) { $0 + $1.directionChangeCount }
        guard symbolHeight >= max(CGFloat(15), sceneBounds.height * 0.28),
              symbolWidth <= max(CGFloat(42), sceneBounds.height * 1.05),
              symbolHeight >= symbolWidth * 0.52,
              !strokes.contains(where: \.looksClosed) else {
            return nil
        }

        let topPoints = points.filter { point in
            point.y <= bounds.minY + symbolHeight * 0.42
        }
        let tailPoints = points.filter { point in
            point.y >= bounds.minY + symbolHeight * 0.32
        }
        guard let topBounds = topPoints.nonEmptyBounds,
              let tailBounds = tailPoints.nonEmptyBounds else {
            return nil
        }

        let topHook = topBounds.width >= max(CGFloat(4), symbolWidth * 0.24)
            && topBounds.maxY <= bounds.minY + symbolHeight * 0.5
        let descendingTail = tailBounds.height >= max(CGFloat(7), symbolHeight * 0.36)
            && tailBounds.maxY >= bounds.minY + symbolHeight * 0.72
        let sevenCorner = topBounds.maxX >= bounds.minX + symbolWidth * 0.48
            && tailBounds.minX <= topBounds.maxX + max(CGFloat(5), symbolWidth * 0.28)
        let containsLongAngledSegment = strokes.contains { stroke in
            stroke.containsSegmentAngle(inDegrees: 35...90, minimumLength: max(CGFloat(4), symbolHeight * 0.12))
        }
        let tailEnvelopeIsAngledOrVertical = tailBounds.height >= max(CGFloat(7), tailBounds.width * 1.05)
            || abs(tailBounds.midX - topBounds.maxX) <= max(CGFloat(8), symbolWidth * 0.34)
        let slashOnly = topBounds.width < max(CGFloat(6), symbolWidth * 0.32)
            && totalDirectionChanges <= 1

        guard topHook,
              descendingTail,
              sevenCorner,
              (containsLongAngledSegment || tailEnvelopeIsAngledOrVertical),
              !slashOnly else {
            return nil
        }

        let idealAspect = CGFloat(0.48)
        let aspectScore = abs((symbolWidth / symbolHeight) - idealAspect)
        let topScore = abs((topBounds.midY - bounds.minY) / symbolHeight - 0.14)
        let tailScore = abs((tailBounds.midX - bounds.midX) / max(CGFloat(1), symbolWidth)) * 0.2
        let wobbleScore = CGFloat(max(0, totalDirectionChanges - 4)) * 0.015
        return aspectScore + topScore + tailScore + wobbleScore + 0.08
    }

    private func hasTwoRestFlagLevels(in sceneBounds: CGRect) -> Bool {
        let points = strokes.flatMap(\.points)
        let symbolHeight = max(CGFloat(1), bounds.height)
        let symbolWidth = max(CGFloat(1), bounds.width)
        let upperPoints = points.filter { point in
            point.y <= bounds.minY + symbolHeight * 0.4
        }
        let middlePoints = points.filter { point in
            point.y >= bounds.minY + symbolHeight * 0.28
                && point.y <= bounds.minY + symbolHeight * 0.68
        }
        let lowerTailPoints = points.filter { point in
            point.y >= bounds.minY + symbolHeight * 0.56
        }
        guard let upperBounds = upperPoints.nonEmptyBounds,
              let middleBounds = middlePoints.nonEmptyBounds,
              let lowerTailBounds = lowerTailPoints.nonEmptyBounds else {
            return false
        }

        let upperHook = upperBounds.width >= max(CGFloat(3), symbolWidth * 0.16)
            || upperBounds.height >= max(CGFloat(3), symbolHeight * 0.08)
        let middleHook = middleBounds.width >= max(CGFloat(3), symbolWidth * 0.16)
            || middleBounds.height >= max(CGFloat(4), symbolHeight * 0.12)
        let separatedLevels = middleBounds.midY - upperBounds.midY >= max(CGFloat(3), symbolHeight * 0.12)
        let descendingTail = lowerTailBounds.height >= max(CGFloat(5), symbolHeight * 0.18)
            && lowerTailBounds.maxY >= bounds.minY + symbolHeight * 0.72
        let compactEnough = bounds.width <= max(CGFloat(42), sceneBounds.height * 1.05)

        return compactEnough && upperHook && middleHook && separatedLevels && descendingTail
    }

    func hasAttachedLowerNotehead(
        among strokes: [StrokeObservation],
        in sceneBounds: CGRect
    ) -> Bool {
        let leftTolerance = max(CGFloat(5), bounds.width * 0.3)
        let rightTolerance = max(CGFloat(3), bounds.width * 0.18)
        let lowerBandY = bounds.minY + bounds.height * 0.45

        return strokes.contains { stroke in
            guard !self.strokes.contains(stroke) else {
                return false
            }

            return stroke.looksLikeRhythmNotehead(in: sceneBounds)
                && stroke.center.y >= lowerBandY
                && stroke.bounds.midX >= bounds.minX - leftTolerance
                && stroke.bounds.midX <= bounds.maxX + rightTolerance
                && stroke.bounds.minX <= bounds.maxX + rightTolerance
        }
    }

    func isSingleRhythmNoteheadWithAttachedStem(
        among strokes: [StrokeObservation],
        in sceneBounds: CGRect
    ) -> Bool {
        guard self.strokes.count == 1,
              let notehead = self.strokes.first,
              notehead.looksLikeRhythmNotehead(in: sceneBounds) else {
            return false
        }

        let horizontalTolerance = max(CGFloat(10), sceneBounds.height * 0.22)
        let verticalTolerance = max(CGFloat(5), sceneBounds.height * 0.1)

        return strokes.contains { stroke in
            guard stroke != notehead,
                  stroke.looksLikeVisualStem(in: sceneBounds) else {
                return false
            }

            let horizontallyAttached = stroke.bounds.midX >= notehead.bounds.minX - horizontalTolerance
                && stroke.bounds.midX <= notehead.bounds.maxX + horizontalTolerance
            let verticallyAttached = stroke.bounds.minY <= notehead.bounds.midY
                && stroke.bounds.maxY >= notehead.bounds.minY - verticalTolerance
            return horizontallyAttached && verticallyAttached
        }
    }

    func containsLowerNoteheadMass(in sceneBounds: CGRect) -> Bool {
        let lowerBandY = bounds.minY + bounds.height * 0.45
        return strokes.contains { stroke in
            guard !stroke.looksLikeShortRestBodyCandidate(in: bounds),
                  !stroke.looksLikeShortRestBodyCandidate(in: sceneBounds) else {
                return false
            }

            let compactWithinSymbol = stroke.bounds.height <= max(CGFloat(16), bounds.height * 0.45)
                && stroke.bounds.width <= max(CGFloat(18), bounds.width * 0.75)
            return compactWithinSymbol
                && stroke.center.y >= lowerBandY
                && stroke.looksLikeRhythmNotehead(in: sceneBounds)
        }
    }

    func containsNoteheadSizedMass(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        return strokes.contains { stroke in
            guard !stroke.looksLikeShortRestBodyCandidate(in: bounds),
                  !stroke.looksLikeShortRestBodyCandidate(in: referenceBounds) else {
                return false
            }

            let noteheadSized = stroke.bounds.width >= max(CGFloat(8), referenceHeight * 0.09)
                && stroke.bounds.height >= max(CGFloat(7), referenceHeight * 0.07)
            let roundedMass = stroke.looksFilledNoteHead
                || stroke.looksHollowNoteHead
                || stroke.looksClosed

            return noteheadSized && roundedMass
        }
    }

    func beamedEighthNoteCount(drawingFrame: CGRect) -> Int {
        guard strokes.count >= 3 else {
            return 0
        }

        let noteheadXs = beamedNoteheadXs(drawingFrame: drawingFrame)
        let stemXs = inferredStemXs(drawingFrame: drawingFrame)
        guard noteheadXs.count >= 2 || stemXs.count >= 2 else {
            return 0
        }

        if noteheadXs.count >= 2 {
            let hasEnoughStemInformation = stemXs.count >= 2
                || noteheadXs.allSatisfy { noteheadX in
                    stemXs.contains { abs($0 - noteheadX) <= max(CGFloat(8), drawingFrame.width * 0.045) }
                }
            guard hasEnoughStemInformation else {
                return 0
            }

            let beamedNoteheadXs = noteheadXs.filter { noteheadX in
                strokes.contains { stroke in
                    stroke.coversBeamedNotehead(at: noteheadX, noteheadXs: noteheadXs, in: bounds)
                }
            }
            if beamedNoteheadXs.count >= 2 {
                return min(beamedNoteheadXs.count, 4)
            }

            if hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) {
                return min(noteheadXs.count, 4)
            }
        }

        let beamedStemXs = stemXs.filter { stemX in
            strokes.contains { stroke in
                stroke.coversBeamedNotehead(at: stemX, noteheadXs: stemXs, in: bounds)
            }
        }
        guard beamedStemXs.count >= 2 else {
            if stemXs.count >= 2,
               hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) {
                return min(stemXs.count, 4)
            }
            return 0
        }

        return min(beamedStemXs.count, 4)
    }

    func isSelfContainedBeamedEighthRun(drawingFrame: CGRect) -> Bool {
        let beamedCount = beamedEighthNoteCount(drawingFrame: drawingFrame)
        guard beamedCount >= 2,
              hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) else {
            return false
        }

        let noteheadCount = beamedNoteheadXs(drawingFrame: drawingFrame).count
        let stemCount = inferredStemXs(drawingFrame: drawingFrame).count
        let anchorCount = max(noteheadCount, stemCount)
        return anchorCount == beamedCount
    }

    func isSelfContainedMixedBeamedSixteenthRun(drawingFrame: CGRect) -> Bool {
        guard hasExplicitBeamedEighthConnector(drawingFrame: drawingFrame) else {
            return false
        }

        let anchors = beamedNoteheadXs(drawingFrame: drawingFrame).sorted()
        guard anchors.count >= 3 else {
            return false
        }

        let activeAnchors = Array(anchors.suffix(3))
        return hasLeadingSecondaryBeam(over: activeAnchors, drawingFrame: drawingFrame)
            || hasTrailingSecondaryBeam(over: activeAnchors, drawingFrame: drawingFrame)
    }

    private func hasLeadingSecondaryBeam(
        over anchors: [CGFloat],
        drawingFrame: CGRect
    ) -> Bool {
        guard anchors.count == 3 else {
            return false
        }

        let stems = strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        let leadingAnchors = Array(anchors[0...1])
        return strokes.contains { stroke in
            let beamLike = stroke.isSharedBeam(overNoteheadXs: leadingAnchors, in: bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: bounds,
                    drawingFrame: drawingFrame
                )
            guard beamLike,
                  stroke.bounds.height <= max(CGFloat(10), bounds.height * 0.32),
                  stroke.bounds.midY <= bounds.minY + bounds.height * 0.62 else {
                return false
            }

            let tolerance = stroke.beamedCoverageTolerance(in: bounds)
            let coversLeadingPair = leadingAnchors.allSatisfy { anchorX in
                stroke.bounds.minX <= anchorX + tolerance
                    && stroke.bounds.maxX >= anchorX - tolerance
            }
            let endsBeforeTrailingAttack = stroke.bounds.maxX < anchors[2] - tolerance * 0.35
            return coversLeadingPair && endsBeforeTrailingAttack
        }
    }

    private func hasTrailingSecondaryBeam(
        over anchors: [CGFloat],
        drawingFrame: CGRect
    ) -> Bool {
        guard anchors.count == 3 else {
            return false
        }

        let stems = strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        let trailingAnchors = Array(anchors[1...2])
        return strokes.contains { stroke in
            let beamLike = stroke.isSharedBeam(overNoteheadXs: trailingAnchors, in: bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: bounds,
                    drawingFrame: drawingFrame
                )
            guard beamLike,
                  stroke.bounds.height <= max(CGFloat(10), bounds.height * 0.32),
                  stroke.bounds.midY <= bounds.minY + bounds.height * 0.62 else {
                return false
            }

            let tolerance = stroke.beamedCoverageTolerance(in: bounds)
            let coversTrailingPair = trailingAnchors.allSatisfy { anchorX in
                stroke.bounds.minX <= anchorX + tolerance
                    && stroke.bounds.maxX >= anchorX - tolerance
            }
            let startsAfterLeadingAttack = stroke.bounds.minX > anchors[0] + tolerance * 0.35
            return coversTrailingPair && startsAfterLeadingAttack
        }
    }

    func hasExplicitBeamedEighthConnector(drawingFrame: CGRect) -> Bool {
        let stems = strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        let noteheadXs = beamedNoteheadXs(drawingFrame: drawingFrame)
        let inferredStemXs = inferredStemXs(drawingFrame: drawingFrame)
        let anchorXs = (noteheadXs + stems.map(\.bounds.midX) + inferredStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(7), drawingFrame.width * 0.03))
        guard anchorXs.count >= 2 else {
            return false
        }

        return strokes.contains { stroke in
            stroke.isSharedBeam(across: stems)
                || stroke.isSharedBeam(overNoteheadXs: anchorXs, in: bounds)
                || stroke.isConnectedBeamFrame(overNoteheadXs: anchorXs, in: bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: bounds,
                    drawingFrame: drawingFrame
                )
                || stroke.looksLikeFoldedBeamStemSeed(
                    over: stems,
                    in: bounds,
                    drawingFrame: drawingFrame
                )
        }
    }

    private func beamedNoteheadXs(drawingFrame: CGRect) -> [CGFloat] {
        let symbolHeight = max(CGFloat(1), bounds.height)
        let lowerBandY = bounds.minY + symbolHeight * 0.43
        let maxHeadWidth = max(CGFloat(18), drawingFrame.width * 0.09)
        let maxHeadHeight = max(CGFloat(18), symbolHeight * 0.58)
        let candidates = strokes.compactMap { stroke -> CGFloat? in
            guard !stroke.looksLikeShortRestBodyCandidate(in: bounds),
                  !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame),
                  !stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame),
                  !stroke.looksLikeSingleStrokeEighthRest(in: drawingFrame),
                  !stroke.looksLikeQuarterRestBody(in: bounds) else {
                return nil
            }

            let sitsInHeadBand = stroke.bounds.maxY >= lowerBandY
                || stroke.center.y >= bounds.midY - symbolHeight * 0.12
            let compactEnough = stroke.bounds.width <= maxHeadWidth
                && stroke.bounds.height <= maxHeadHeight
            let readsAsHead = stroke.looksFilledNoteHead
                || stroke.looksClosed
                || (stroke.looksDense && stroke.bounds.width >= 3 && stroke.bounds.height >= 3)

            return sitsInHeadBand && compactEnough && readsAsHead ? stroke.center.x : nil
        }

        return candidates.clusteredXs(minimumSeparation: max(CGFloat(8), drawingFrame.width * 0.035))
    }

    private func inferredStemXs(drawingFrame: CGRect) -> [CGFloat] {
        let symbolHeight = max(CGFloat(1), bounds.height)
        let directStems = strokes.compactMap { stroke -> CGFloat? in
            guard !stroke.looksLikeShortRestBodyCandidate(in: bounds),
                  !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame),
                  !stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame),
                  !stroke.looksLikeSingleStrokeEighthRest(in: drawingFrame),
                  !stroke.looksLikeQuarterRestBody(in: bounds) else {
                return nil
            }

            let verticalEnough = stroke.bounds.height >= max(CGFloat(10), symbolHeight * 0.36)
            let narrowEnough = stroke.bounds.width <= max(CGFloat(10), stroke.bounds.height * 0.62)
            let touchesLowerBody = stroke.bounds.maxY >= bounds.minY + symbolHeight * 0.42

            return verticalEnough && narrowEnough && touchesLowerBody && !stroke.looksClosed
                ? stroke.bounds.midX
                : nil
        }

        let connectedStemXs = strokes.flatMap { stroke in
            stroke.connectedBeamStemXs(in: bounds)
        }

        return (directStems + connectedStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(8), drawingFrame.width * 0.035))
    }
}

extension Array where Element == [StrokeObservation] {
    func reattachingLeadingEighthRestDotsToFollowingTails(drawingFrame: CGRect) -> [[StrokeObservation]] {
        var resolvedGroups = self
        guard resolvedGroups.count > 1 else {
            return resolvedGroups
        }

        let dotSizeLimit = Swift.max(CGFloat(5), Swift.min(CGFloat(9), drawingFrame.height * 0.1))
        var index = 0
        while index + 1 < resolvedGroups.count {
            guard let currentBounds = resolvedGroups[index].nonEmptyBounds,
                  let nextBounds = resolvedGroups[index + 1].nonEmptyBounds else {
                index += 1
                continue
            }

            let nextLooksLikeEighthRestTail = nextBounds.height >= Swift.max(CGFloat(18), drawingFrame.height * 0.28)
                && nextBounds.width <= Swift.max(CGFloat(12), nextBounds.height * 0.38)
                && nextBounds.midY > currentBounds.midY
            guard nextLooksLikeEighthRestTail else {
                index += 1
                continue
            }

            let currentHasQuarterRestBody = resolvedGroups[index].contains { stroke in
                stroke.looksLikeQuarterRestBody(in: currentBounds)
                    || stroke.looksLikeFlexibleOneStrokeQuarterRest(in: currentBounds)
            }
            let movableDots = resolvedGroups[index].filter { stroke in
                let dotLike = stroke.isDotLike(in: currentBounds)
                    && stroke.bounds.width <= dotSizeLimit * 1.2
                    && stroke.bounds.height <= dotSizeLimit * 1.2
                let nearNextTail = stroke.bounds.maxX >= nextBounds.minX - dotSizeLimit
                    && stroke.bounds.minX <= nextBounds.midX + dotSizeLimit
                let aboveTail = stroke.center.y < nextBounds.midY
                let trailingCurrentDot = stroke.bounds.minX >= currentBounds.midX

                let readsAsCurrentRestAugmentation = currentHasQuarterRestBody
                    && stroke.center.x >= currentBounds.midX
                    && stroke.center.y >= currentBounds.minY + currentBounds.height * 0.25
                    && stroke.center.y <= currentBounds.maxY + currentBounds.height * 0.55

                return dotLike && nearNextTail && aboveTail && trailingCurrentDot && !readsAsCurrentRestAugmentation
            }

            guard !movableDots.isEmpty else {
                index += 1
                continue
            }

            resolvedGroups[index].removeAll { movableDots.contains($0) }
            resolvedGroups[index + 1].append(contentsOf: movableDots)
            if resolvedGroups[index].isEmpty {
                resolvedGroups.remove(at: index)
            } else {
                index += 1
            }
        }

        return resolvedGroups
    }

    func attachingTrailingDurationDotsToPreviousGlyphs(drawingFrame: CGRect) -> [[StrokeObservation]] {
        var mergedGroups: [[StrokeObservation]] = []

        for group in self {
            guard group.nonEmptyBounds != nil else {
                continue
            }

            if var previousGroup = mergedGroups.popLast() {
                if group.canAttachAsTrailingDurationDot(
                    to: previousGroup,
                    drawingFrame: drawingFrame
                ) {
                    previousGroup.append(contentsOf: group)
                    mergedGroups.append(previousGroup)
                    continue
                }

                mergedGroups.append(previousGroup)
            }

            mergedGroups.append(group)
        }

        return mergedGroups
    }

    func splittingCompoundStemmedSymbols(drawingFrame: CGRect) -> [[StrokeObservation]] {
        flatMap { group -> [[StrokeObservation]] in
            if let splitGroups = group.splittingLeadingRestFromFollowingNote(drawingFrame: drawingFrame) {
                return splitGroups
            }

            let symbol = SymbolObservation(strokes: group)
            if symbol.isSelfContainedBeamedEighthRun(drawingFrame: drawingFrame)
                || symbol.isSelfContainedMixedBeamedSixteenthRun(drawingFrame: drawingFrame) {
                return [group]
            }

            let stemAnchors = group.stemAnchorStrokes(drawingFrame: drawingFrame)
            guard stemAnchors.count > 1 else {
                return [group]
            }

            var buckets = stemAnchors.map { [$0] }
            for stroke in group where !stemAnchors.contains(stroke) {
                if stroke.isSharedBeam(across: stemAnchors),
                   let firstCoveredIndex = stemAnchors.firstIndex(where: { stroke.bounds.minX <= $0.bounds.midX && stroke.bounds.maxX >= $0.bounds.midX }) {
                    for index in firstCoveredIndex..<stemAnchors.count
                    where stroke.bounds.minX <= stemAnchors[index].bounds.midX
                        && stroke.bounds.maxX >= stemAnchors[index].bounds.midX {
                        buckets[index].append(stroke)
                    }
                    continue
                }

                let targetIndex: Int
                if stroke.isDotLike(in: group.nonEmptyBounds ?? stroke.bounds),
                   !stroke.looksLikeLowerNotehead(in: group.nonEmptyBounds ?? stroke.bounds),
                   let previousStemIndex = stemAnchors.lastIndex(where: { $0.bounds.midX < stroke.center.x }) {
                    targetIndex = previousStemIndex
                } else {
                    targetIndex = stemAnchors.nearestIndex(toX: stroke.center.x) ?? 0
                }

                buckets[targetIndex].append(stroke)
            }

            return buckets
                .filter { !$0.isEmpty }
                .sorted { lhs, rhs in
                    (lhs.nonEmptyBounds?.minX ?? 0) < (rhs.nonEmptyBounds?.minX ?? 0)
                }
        }
    }

    func reattachingLeadingNoteheadsToFollowingBeams(drawingFrame: CGRect) -> [[StrokeObservation]] {
        var resolvedGroups: [[StrokeObservation]] = []
        var index = 0

        while index < count {
            guard index + 1 < count,
                  let currentBounds = self[index].nonEmptyBounds,
                  let nextBounds = self[index + 1].nonEmptyBounds,
                  self[index].isLooseNoteheadOnly(drawingFrame: drawingFrame),
                  SymbolObservation(strokes: self[index + 1]).beamedEighthNoteCount(drawingFrame: drawingFrame) >= 2 else {
                resolvedGroups.append(self[index])
                index += 1
                continue
            }

            let horizontalGap = nextBounds.minX - currentBounds.maxX
            let allowedGap = Swift.max(CGFloat(6), Swift.min(CGFloat(14), drawingFrame.width * 0.045))
            let verticallyBelongsToBeamGroup = currentBounds.midY >= nextBounds.midY - nextBounds.height * 0.15
                && currentBounds.midY <= nextBounds.maxY + nextBounds.height * 0.25

            if horizontalGap <= allowedGap,
               currentBounds.midX < nextBounds.midX,
               verticallyBelongsToBeamGroup {
                resolvedGroups.append(self[index] + self[index + 1])
                index += 2
            } else {
                resolvedGroups.append(self[index])
                index += 1
            }
        }

        return resolvedGroups
    }

    func reattachingLeadingDotsToPreviousSymbols(drawingFrame: CGRect) -> [[StrokeObservation]] {
        reduce(into: [[StrokeObservation]]()) { resolvedGroups, group in
            guard !resolvedGroups.isEmpty,
                  let groupBounds = group.nonEmptyBounds,
                  let firstStem = group.stemAnchorStrokes(drawingFrame: drawingFrame).first else {
                resolvedGroups.append(group)
                return
            }

            let symbol = SymbolObservation(strokes: group)
            if symbol.eighthRestComparisonScore(in: groupBounds) != nil
                || symbol.sevenLikeEighthRestComparisonScore(in: groupBounds) != nil {
                resolvedGroups.append(group)
                return
            }

            let movableDots = group.filter { stroke in
                stroke.isDotLike(in: groupBounds)
                    && !stroke.looksLikeLowerNotehead(in: groupBounds)
                    && !stroke.looksLikeRhythmNotehead(in: groupBounds)
                    && stroke.bounds.maxX < firstStem.bounds.midX
                    && stroke.center.y >= groupBounds.midY - groupBounds.height * 0.12
            }
            guard !movableDots.isEmpty else {
                resolvedGroups.append(group)
                return
            }

            let remainingStrokes = group.filter { !movableDots.contains($0) }
            resolvedGroups[resolvedGroups.count - 1].append(contentsOf: movableDots)

            if !remainingStrokes.isEmpty {
                resolvedGroups.append(remainingStrokes)
            }
        }
    }
}

extension Array where Element == StrokeObservation {
    fileprivate func canAttachAsTrailingDurationDot(
        to previousGroup: [StrokeObservation],
        drawingFrame: CGRect
    ) -> Bool {
        guard isLooseDurationDotGroup(drawingFrame: drawingFrame),
              previousGroup.canOwnTrailingDurationDot(drawingFrame: drawingFrame),
              let dotBounds = nonEmptyBounds,
              let previousBounds = previousGroup.nonEmptyBounds else {
            return false
        }

        let previousFeatures = SymbolFeatures(
            symbol: SymbolObservation(strokes: previousGroup),
            drawingFrame: drawingFrame
        )
        let bodyBounds = previousFeatures.contentStrokes.nonEmptyBounds ?? previousBounds
        let bodyWidth = Swift.max(CGFloat(1), bodyBounds.width)
        let bodyHeight = Swift.max(CGFloat(1), bodyBounds.height)
        let horizontalGap = dotBounds.minX - bodyBounds.maxX
        let minimumGap = -Swift.max(CGFloat(3), dotBounds.width * 0.55)
        let maximumGap = Swift.max(
            CGFloat(18),
            Swift.min(
                CGFloat(58),
                Swift.max(bodyWidth * 1.25, drawingFrame.width * 0.075)
            )
        )
        let sitsAfterGlyph = dotBounds.midX >= bodyBounds.midX + bodyWidth * 0.18
        let lowerLaneTop = bodyBounds.minY + bodyHeight * 0.30
        let lowerLaneBottom = bodyBounds.maxY + Swift.max(CGFloat(12), bodyHeight * 0.38)
        let sitsInLowerDotLane = dotBounds.midY >= lowerLaneTop
            && dotBounds.midY <= lowerLaneBottom
        let readsAsLeadingRestDot = dotBounds.midY <= bodyBounds.minY + bodyHeight * 0.28
            && dotBounds.midX <= bodyBounds.midX + bodyWidth * 0.22

        return horizontalGap >= minimumGap
            && horizontalGap <= maximumGap
            && sitsAfterGlyph
            && sitsInLowerDotLane
            && !readsAsLeadingRestDot
    }

    fileprivate func isLooseDurationDotGroup(drawingFrame: CGRect) -> Bool {
        guard count <= 2,
              let bounds = nonEmptyBounds else {
            return false
        }

        let maxDotSide = Swift.max(CGFloat(6), Swift.min(CGFloat(16), drawingFrame.height * 0.14))
        guard bounds.width <= maxDotSide,
              bounds.height <= maxDotSide else {
            return false
        }

        return allSatisfy { stroke in
            stroke.looksLikeLooseDot(in: drawingFrame)
                || stroke.isDotLike(in: drawingFrame)
                || stroke.isCompactMark(comparedTo: drawingFrame)
        }
    }

    fileprivate func canOwnTrailingDurationDot(drawingFrame: CGRect) -> Bool {
        guard let bounds = nonEmptyBounds else {
            return false
        }

        if SymbolObservation(strokes: self).isSelfContainedBeamedEighthRun(drawingFrame: drawingFrame)
            || SymbolObservation(strokes: self).isSelfContainedMixedBeamedSixteenthRun(drawingFrame: drawingFrame) {
            return false
        }

        if allSatisfy({ $0.looksLikeRhythmicPlaceholderSlash(in: bounds) }) {
            return false
        }

        let features = SymbolFeatures(
            symbol: SymbolObservation(strokes: self),
            drawingFrame: drawingFrame
        )
        guard !features.hasDot else {
            return false
        }

        let hasNoteGlyph = features.hasStem
            || features.hasStemAndKick
            || features.hasFilledHead
            || features.hasHollowHead
            || features.hasLowerHeadMass
            || features.hasDefiniteLowerNotehead
        let hasQuarterRestGlyph = features.contentStrokes.contains { stroke in
            stroke.looksLikeQuarterRestBody(in: features.contentBounds)
                || stroke.looksLikeFlexibleOneStrokeQuarterRest(in: features.contentBounds)
                || stroke.looksLikeQuarterRestSegment(in: features.contentBounds)
        }
        let hasNonNoteRestGlyph = features.hasNoNoteheadRestShape || hasQuarterRestGlyph
        let hasHorizontalRestBlock = bounds.width > Swift.max(CGFloat(8), bounds.height * 1.05)
            && contains { stroke in
                stroke.isMostlyHorizontal || stroke.looksDense
            }

        return hasNoteGlyph || hasNonNoteRestGlyph || hasHorizontalRestBlock
    }

    func sortedByVisualPosition() -> [StrokeObservation] {
        sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.bounds.midY < rhs.bounds.midY
        }
    }

    func canAttachStrokeWithinSingleGlyph(
        _ stroke: StrokeObservation,
        drawingFrame: CGRect
    ) -> Bool {
        guard let groupBounds = nonEmptyBounds else {
            return false
        }

        let localGap = Swift.max(CGFloat(6), Swift.min(CGFloat(12), drawingFrame.width * 0.035))
        let verticallyTouchesGroup = stroke.bounds.minY <= groupBounds.maxY + Swift.max(CGFloat(6), groupBounds.height * 0.2)
            && stroke.bounds.maxY >= groupBounds.minY - Swift.max(CGFloat(6), groupBounds.height * 0.2)
        guard stroke.bounds.minX <= groupBounds.maxX + localGap,
              verticallyTouchesGroup else {
            return false
        }

        let groupSymbol = SymbolObservation(strokes: self)
        let groupFeatures = SymbolFeatures(symbol: groupSymbol, drawingFrame: drawingFrame)
        let strokeIsStem = stroke.looksLikeVisualStem(in: groupBounds.union(stroke.bounds))
        let strokeIsHead = stroke.looksLikeRhythmNotehead(in: groupBounds.union(stroke.bounds))

        let attachesStemToLooseHead = !groupFeatures.hasStem
            && strokeIsStem
            && contains { $0.looksLikeRhythmNotehead(in: groupBounds) }
        let attachesHeadToLooseStem = groupFeatures.hasStem
            && !groupFeatures.hasClearNoteGlyph
            && strokeIsHead
        let attachesRestPiece = stroke.looksLikeQuarterRestBody(in: groupBounds.union(stroke.bounds))
            || stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame)
            || stroke.looksLikeSingleStrokeEighthRest(in: drawingFrame)
            || contains(where: { existingStroke in
                existingStroke.looksLikeQuarterRestBody(in: groupBounds)
                    || existingStroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame)
                    || existingStroke.looksLikeSingleStrokeEighthRest(in: drawingFrame)
            })

        return attachesStemToLooseHead || attachesHeadToLooseStem || attachesRestPiece
    }

    func stemAnchorStrokes(drawingFrame: CGRect) -> [StrokeObservation] {
        guard let groupBounds = nonEmptyBounds else {
            return []
        }

        let groupHeight = Swift.max(CGFloat(1), groupBounds.height)
        let stemCandidates = filter { stroke in
            let verticalEnough = stroke.bounds.height >= Swift.max(10, groupHeight * 0.42)
            let narrowEnough = stroke.bounds.width <= Swift.max(10, stroke.bounds.height * 0.58)
            let hasStemGesture = stroke.isMostlyVertical
                || stroke.looksLikeSingleStrokeEighthNote
                || (verticalEnough && stroke.pathLength <= stroke.bounds.height * 2.35)

            return verticalEnough
                && narrowEnough
                && hasStemGesture
                && !stroke.looksClosed
                && !stroke.isDotLike(in: groupBounds)
        }

        let minimumSeparation = Swift.max(CGFloat(7), drawingFrame.width * 0.04)
        return stemCandidates
            .sorted { lhs, rhs in
                if abs(lhs.bounds.midX - rhs.bounds.midX) > 0.5 {
                    return lhs.bounds.midX < rhs.bounds.midX
                }
                return lhs.bounds.height > rhs.bounds.height
            }
            .reduce(into: [StrokeObservation]()) { anchors, candidate in
                guard !anchors.contains(where: { abs($0.bounds.midX - candidate.bounds.midX) < minimumSeparation }) else {
                    return
                }
                anchors.append(candidate)
            }
    }

    func subsets(
        containing anchor: StrokeObservation,
        maximumCount: Int
    ) -> [[StrokeObservation]] {
        guard contains(anchor) else {
            return []
        }

        let remaining = filter { $0 != anchor }
        var results: [[StrokeObservation]] = [[anchor]]

        func appendSubsets(startIndex: Int, current: [StrokeObservation]) {
            guard current.count < maximumCount else {
                return
            }

            for index in startIndex..<remaining.count {
                let next = current + [remaining[index]]
                results.append(next)
                appendSubsets(startIndex: index + 1, current: next)
            }
        }

        appendSubsets(startIndex: 0, current: [anchor])
        return results
    }

    func nearestIndex(toX x: CGFloat) -> Int? {
        indices.min { lhs, rhs in
            abs(self[lhs].bounds.midX - x) < abs(self[rhs].bounds.midX - x)
        }
    }
}

extension StrokeObservation {
    func isDotLike(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        return bounds.width <= max(10, referenceWidth * 0.34)
            && bounds.height <= max(10, referenceHeight * 0.34)
            && pathLength <= max(36, referenceHeight * 1.8)
    }

    func isSharedBeam(across stems: [StrokeObservation]) -> Bool {
        guard stems.count > 1,
              isMostlyHorizontal,
              bounds.height <= max(7, bounds.width * 0.35) else {
            return false
        }

        let coverageTolerance = max(CGFloat(8), bounds.width * 0.25)
        let coveredStemCount = stems.filter { stem in
            bounds.minX <= stem.bounds.midX + coverageTolerance
                && bounds.maxX >= stem.bounds.midX - coverageTolerance
        }.count
        return coveredStemCount > 1
    }

    func isSharedBeam(overNoteheadXs noteheadXs: [CGFloat], in symbolBounds: CGRect) -> Bool {
        guard noteheadXs.count >= 2,
              bounds.width >= max(CGFloat(12), symbolBounds.height * 0.24),
              bounds.height <= max(CGFloat(9), symbolBounds.height * 0.28),
              bounds.midY <= symbolBounds.minY + symbolBounds.height * 0.42 else {
            return false
        }

        let coverageTolerance = beamedCoverageTolerance(in: symbolBounds)
        let coveredHeadCount = noteheadXs.filter { noteheadX in
            bounds.minX <= noteheadX + coverageTolerance
                && bounds.maxX >= noteheadX - coverageTolerance
        }.count
        return coveredHeadCount >= 2
    }

    func coversBeamedNotehead(
        at noteheadX: CGFloat,
        noteheadXs: [CGFloat],
        in symbolBounds: CGRect
    ) -> Bool {
        if isSharedBeam(overNoteheadXs: noteheadXs, in: symbolBounds) {
            let coverageTolerance = beamedCoverageTolerance(in: symbolBounds)
            return bounds.minX <= noteheadX + coverageTolerance
                && bounds.maxX >= noteheadX - coverageTolerance
        }

        guard isConnectedBeamFrame(overNoteheadXs: noteheadXs, in: symbolBounds) else {
            return false
        }

        return connectedBeamStemXs(in: symbolBounds).contains { stemX in
            abs(stemX - noteheadX) <= max(CGFloat(10), symbolBounds.width * 0.18)
        }
    }

    func isConnectedBeamFrame(overNoteheadXs noteheadXs: [CGFloat], in symbolBounds: CGRect) -> Bool {
        guard noteheadXs.count >= 2,
              bounds.width >= max(CGFloat(12), symbolBounds.height * 0.24),
              bounds.height >= max(CGFloat(10), symbolBounds.height * 0.48) else {
            return false
        }

        let topBandMaxY = symbolBounds.minY + symbolBounds.height * 0.38
        let lowerBandMinY = symbolBounds.minY + symbolBounds.height * 0.46
        let topPoints = points.filter { $0.y <= topBandMaxY }
        guard topPoints.xSpread >= max(CGFloat(12), symbolBounds.width * 0.34) else {
            return false
        }

        let stemXs = connectedBeamStemXs(in: symbolBounds)
        guard stemXs.count >= 2 else {
            return false
        }

        let coveredHeadCount = noteheadXs.filter { noteheadX in
            stemXs.contains { abs($0 - noteheadX) <= max(CGFloat(12), symbolBounds.width * 0.22) }
        }.count
        let hasLowerStemPoints = points.contains { $0.y >= lowerBandMinY }
        return coveredHeadCount >= 2 && hasLowerStemPoints
    }

    func connectedBeamStemXs(in symbolBounds: CGRect) -> [CGFloat] {
        guard bounds.width >= max(CGFloat(10), symbolBounds.width * 0.22),
              bounds.height >= max(CGFloat(10), symbolBounds.height * 0.38) else {
            return []
        }

        let lowerBandMinY = symbolBounds.minY + symbolBounds.height * 0.45
        let lowerPoints = points.filter { $0.y >= lowerBandMinY }
        return lowerPoints.map(\.x)
            .clusteredXs(minimumSeparation: max(CGFloat(7), symbolBounds.width * 0.14))
    }

    func beamedCoverageTolerance(in symbolBounds: CGRect) -> CGFloat {
        max(CGFloat(8), symbolBounds.width * 0.14)
    }
}

struct SymbolFeatures {
    let symbol: SymbolObservation
    let drawingFrame: CGRect
    let contentStrokes: [StrokeObservation]
    let dotStrokes: [StrokeObservation]
    let contentBounds: CGRect
    let stemStroke: StrokeObservation?
    let flagStrokes: [StrokeObservation]
    let headStrokes: [StrokeObservation]

    init(symbol: SymbolObservation, drawingFrame: CGRect) {
        self.symbol = symbol
        self.drawingFrame = drawingFrame
        let initialBody = symbol.strokes.filter { stroke in
            let relaxedDotSize = stroke.bounds.width <= max(14, symbol.bounds.width * 0.36)
                && stroke.bounds.height <= max(14, symbol.bounds.height * 0.36)
            return !stroke.isCompactMark(comparedTo: symbol.bounds) && !relaxedDotSize
                || stroke.center.x <= symbol.bounds.midX
        }
        let bodyBounds = initialBody.nonEmptyBounds ?? symbol.bounds
        let likelyStemStrokes = symbol.strokes.filter { stroke in
            stroke.bounds.height >= max(10, bodyBounds.height * 0.38)
                && stroke.bounds.width <= max(10, stroke.bounds.height * 0.58)
                && !stroke.isDotLike(in: bodyBounds)
        }
        let likelyHasStem = !likelyStemStrokes.isEmpty
        let localDotStrokes = symbol.strokes.filter { stroke in
            let relaxedDotSize = stroke.bounds.width <= max(14, bodyBounds.width * 0.62)
                && stroke.bounds.height <= max(14, bodyBounds.height * 0.62)
                && stroke.pathLength <= max(40, bodyBounds.height * 2.2)
            let dotLike = stroke.isCompactMark(comparedTo: bodyBounds) || relaxedDotSize
            let rightOfBody = stroke.bounds.minX >= bodyBounds.minX + bodyBounds.width * 0.34
                && stroke.center.x >= bodyBounds.midX - bodyBounds.width * 0.08
            let nearBodyVertically = stroke.center.y >= bodyBounds.minY - bodyBounds.height * 0.2
                && stroke.center.y <= bodyBounds.maxY + bodyBounds.height * 0.55
            let sitsInNoteheadDotBand = !likelyHasStem
                || stroke.center.y >= bodyBounds.minY + bodyBounds.height * 0.38
            let protectsTopFlag = likelyHasStem
                && stroke.center.y < bodyBounds.minY + bodyBounds.height * 0.42
                && stroke.center.x >= bodyBounds.midX - bodyBounds.width * 0.08

            return dotLike
                && rightOfBody
                && nearBodyVertically
                && sitsInNoteheadDotBand
                && !protectsTopFlag
        }
        let localContentStrokes = symbol.strokes.filter { stroke in
            !localDotStrokes.contains(stroke)
        }
        let localContentBounds = localContentStrokes.nonEmptyBounds ?? symbol.bounds

        let symbolHeight = max(1, localContentBounds.height)
        let stemCandidates = localContentStrokes.filter { stroke in
            stroke.bounds.height >= max(9, symbolHeight * 0.38)
                && stroke.bounds.width <= max(9, stroke.bounds.height * 0.48)
                && stroke.bounds.maxY >= localContentBounds.minY + symbolHeight * 0.45
        }
        let localStemStroke = stemCandidates.max { lhs, rhs in
            lhs.bounds.height < rhs.bounds.height
        }

        let localFlagStrokes: [StrokeObservation]
        let localHeadStrokes: [StrokeObservation]
        if let localStemStroke {
            localFlagStrokes = localContentStrokes.filter { stroke in
                let isLikelyDot = stroke.isCompactMark(comparedTo: localContentBounds)
                    && stroke.center.x > localStemStroke.bounds.maxX
                    && stroke.center.y > localContentBounds.minY + symbolHeight * 0.38
                let nearStemTop = stroke.bounds.minY <= localStemStroke.bounds.minY + symbolHeight * 0.62
                    && stroke.center.y <= localContentBounds.midY + symbolHeight * 0.08
                let closeToStem = stroke.bounds.minX <= localStemStroke.bounds.maxX + symbolHeight * 0.42
                    && stroke.bounds.maxX >= localStemStroke.bounds.minX - symbolHeight * 0.16
                let flagLikeShape = stroke.bounds.width >= max(3, symbolHeight * 0.08)
                    || stroke.bounds.height >= max(5, symbolHeight * 0.16)
                    || stroke.directionChangeCount >= 1

                return stroke != localStemStroke
                    && !isLikelyDot
                    && !stroke.looksLikeRhythmNotehead(in: localContentBounds)
                    && !stroke.isNoteheadLikeMark
                    && nearStemTop
                    && closeToStem
                    && flagLikeShape
                    && stroke.bounds.height <= max(symbolHeight * 0.75, 18)
            }
            localHeadStrokes = localContentStrokes.filter { stroke in
                stroke != localStemStroke
                    && !localFlagStrokes.contains(stroke)
                    && stroke.center.y >= localContentBounds.minY + symbolHeight * 0.32
            }
        } else {
            localFlagStrokes = []
            localHeadStrokes = localContentStrokes
        }

        self.dotStrokes = localDotStrokes
        self.contentStrokes = localContentStrokes
        self.contentBounds = localContentBounds
        self.stemStroke = localStemStroke
        self.flagStrokes = localFlagStrokes
        self.headStrokes = localHeadStrokes
    }

    var hasDot: Bool {
        !dotStrokes.isEmpty
    }

    var hasStem: Bool {
        stemStroke != nil
    }

    var hasFlag: Bool {
        !flagStrokes.isEmpty || hasSingleStrokeFlagGesture
    }

    var hasSingleStrokeFlagGesture: Bool {
        contentStrokes.contains { stroke in
            stroke.looksLikeSingleStrokeEighthNote
                && stroke.bounds.minY <= contentBounds.minY + height * 0.22
        }
    }

    var width: CGFloat {
        max(1, contentBounds.width)
    }

    var height: CGFloat {
        max(1, contentBounds.height)
    }

    var hasHollowHead: Bool {
        headStrokes.contains { stroke in
            stroke.looksHollowNoteHead
                && !stroke.looksLikeZigZagBodyPrimitive(in: contentBounds)
                && !stroke.looksLikeNeutralVerticalStrokePrimitive(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame)
        }
    }

    var hasFilledHead: Bool {
        headStrokes.contains { stroke in
            stroke.looksFilledNoteHead
                && stroke.bounds.width >= max(4, width * 0.14)
                && stroke.bounds.height >= max(4, height * 0.14)
                && stroke.center.y >= contentBounds.midY - height * 0.2
                && !stroke.looksLikeZigZagBodyPrimitive(in: contentBounds)
                && !stroke.looksLikeNeutralVerticalStrokePrimitive(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame)
        }
    }

    var hasLowerHeadMass: Bool {
        headStrokes.contains { stroke in
            stroke.center.y >= contentBounds.midY
                && stroke.bounds.width >= max(4, width * 0.12)
                && stroke.bounds.height >= max(4, height * 0.12)
                && !stroke.looksLikeZigZagBodyPrimitive(in: contentBounds)
                && !stroke.looksLikeNeutralVerticalStrokePrimitive(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame)
        }
    }

    var hasStemAndKick: Bool {
        guard let stemStroke else {
            return false
        }

        return contentStrokes.contains { stroke in
            stroke != stemStroke
                && stroke.center.y >= stemStroke.bounds.midY
                && stroke.bounds.maxX >= stemStroke.bounds.minX - width * 0.2
                && stroke.bounds.minX <= stemStroke.bounds.midX + width * 0.18
                && stroke.bounds.width > stroke.bounds.height * 0.45
        } || (contentStrokes.count == 1 && stemStroke.pathLength > stemStroke.bounds.height * 1.12)
    }

    var hasDefiniteLowerNotehead: Bool {
        contentStrokes.contains { stroke in
            stroke.looksLikeLowerNotehead(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: contentBounds)
                && !stroke.looksLikeShortRestBodyCandidate(in: drawingFrame)
        }
    }

    var hasClearNoteGlyph: Bool {
        guard hasStem else {
            return false
        }

        if hasDefiniteLowerNotehead {
            return true
        }

        return headStrokes.contains { stroke in
            let separatedLowerBody = stroke.center.y >= contentBounds.midY + height * 0.04
                || stroke.bounds.maxY >= contentBounds.maxY - height * 0.22
            let noteheadSized = stroke.bounds.width >= max(CGFloat(4), width * 0.14)
                && stroke.bounds.height >= max(CGFloat(4), height * 0.12)
            let ovalOrDenseHead = stroke.looksClosed
                || stroke.looksHollowNoteHead
                || (stroke.looksFilledNoteHead && stroke.bounds.width >= stroke.bounds.height * 0.55)

            return separatedLowerBody && noteheadSized && ovalOrDenseHead
        }
    }

    var hasNoNoteheadRestShape: Bool {
        guard !hasDefiniteLowerNotehead,
              !hasClearNoteGlyph,
              !hasFilledHead,
              !hasHollowHead,
              !hasLowerHeadMass else {
            return false
        }

        let hasQuarterRestBody = contentStrokes.contains { stroke in
            stroke.looksLikeQuarterRestBody(in: contentBounds)
                || stroke.looksLikeFlexibleOneStrokeQuarterRest(in: contentBounds)
        }
        guard !hasQuarterRestBody else {
            return false
        }

        if symbol.sixteenthRestComparisonScore(in: drawingFrame) != nil
            || symbol.eighthRestComparisonScore(in: drawingFrame) != nil
            || symbol.sevenLikeEighthRestComparisonScore(in: drawingFrame) != nil {
            return true
        }

        return contentStrokes.contains { stroke in
            (
                stroke.looksLikeFlexibleOneStrokeSixteenthRest(in: drawingFrame)
                    || stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame)
                    || stroke.looksLikeSingleStrokeEighthRest(in: drawingFrame)
            )
            && !stroke.looksFilledNoteHead
        }
    }

    var hasHorizontalRestBlock: Bool {
        let compactBody = height <= max(CGFloat(32), drawingFrame.height * 0.24)
        let blockAspect = width >= max(CGFloat(8), height * 0.78)
        let hasShelfStroke = contentStrokes.contains { stroke in
            stroke.looksLikeHorizontalRestBlockStroke(in: contentBounds)
                || (
                    stroke.bounds.width >= max(CGFloat(8), width * 0.48)
                        && stroke.bounds.height <= max(CGFloat(10), height * 0.62)
                        && stroke.pathLength >= max(CGFloat(6), stroke.bounds.width * 0.72)
                )
        }
        let hasDenseBody = contentStrokes.contains { stroke in
            stroke.bounds.width >= max(CGFloat(7), width * 0.38)
                && stroke.bounds.height >= max(CGFloat(4), height * 0.24)
                && stroke.bounds.height <= max(CGFloat(24), stroke.bounds.width * 1.2)
                && (stroke.looksDense || stroke.looksClosed)
        }
        let hasLongStem = contentStrokes.contains { stroke in
            stroke.looksLikeVisualStem(in: drawingFrame)
                && stroke.bounds.height >= max(CGFloat(30), drawingFrame.height * 0.24)
        }
        let hasSustainedVerticalAxis = contentStrokes.contains { stroke in
            stroke.isMostlyVertical
                && stroke.bounds.height >= max(CGFloat(28), height * 1.1)
        }

        return compactBody
            && blockAspect
            && (hasShelfStroke || hasDenseBody)
            && !hasLongStem
            && !hasSustainedVerticalAxis
            && !hasFlag
    }
}

extension Array where Element == StrokeObservation {
    fileprivate func splittingLeadingRestFromFollowingNote(drawingFrame: CGRect) -> [[StrokeObservation]]? {
        let sortedGroup = sortedByVisualPosition()
        guard sortedGroup.count >= 3 else {
            return nil
        }

        let maxPrefixCount = Swift.min(3, sortedGroup.count - 1)
        for prefixCount in stride(from: maxPrefixCount, through: 1, by: -1) {
            let prefix = Array(sortedGroup.prefix(prefixCount))
            let remaining = Array(sortedGroup.dropFirst(prefixCount))
            guard let prefixBounds = prefix.nonEmptyBounds,
                  let remainingBounds = remaining.nonEmptyBounds,
                  prefixBounds.midX < remainingBounds.midX,
                  remaining.hasNoteheadBackedNoteEvidence(drawingFrame: drawingFrame),
                  prefix.looksLikeContextualLeadingEighthRest(drawingFrame: drawingFrame) else {
                continue
            }

            return [prefix, remaining]
        }

        return nil
    }

    func hasNoteheadBackedNoteEvidence(drawingFrame: CGRect) -> Bool {
        let symbol = SymbolObservation(strokes: self)
        let features = SymbolFeatures(symbol: symbol, drawingFrame: drawingFrame)
        return features.hasStem
            && (
                features.hasClearNoteGlyph
                    || features.hasFilledHead
                    || features.hasHollowHead
                    || features.hasLowerHeadMass
                    || features.hasStemAndKick
            )
    }

    func looksLikeContextualLeadingEighthRest(drawingFrame: CGRect) -> Bool {
        guard count == 1,
              let stroke = first else {
            return false
        }

        return stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame)
    }

    func isLooseNoteheadOnly(drawingFrame: CGRect) -> Bool {
        guard let bounds = nonEmptyBounds,
              !isEmpty,
              count <= 2,
              bounds.width >= Swift.max(CGFloat(5), drawingFrame.width * 0.018),
              bounds.height >= Swift.max(CGFloat(5), drawingFrame.height * 0.055),
              bounds.width <= Swift.max(CGFloat(18), drawingFrame.width * 0.09),
              bounds.height <= Swift.max(CGFloat(18), drawingFrame.height * 0.24) else {
            return false
        }

        return allSatisfy { stroke in
            stroke.looksFilledNoteHead || stroke.looksClosed
        }
    }

    var nonEmptyBounds: CGRect? {
        guard !isEmpty else {
            return nil
        }

        return reduce(into: CGRect.null) { partialResult, stroke in
            partialResult = partialResult.union(stroke.bounds)
        }
    }
}

extension Array where Element == CGPoint {
    var nonEmptyBounds: CGRect? {
        guard !isEmpty else {
            return nil
        }

        return reduce(into: CGRect.null) { partialResult, point in
            partialResult = partialResult.union(CGRect(origin: point, size: .zero).insetBy(dx: -0.5, dy: -0.5))
        }
    }

    var xSpread: CGFloat {
        guard let first else {
            return 0
        }

        let range = reduce((minX: first.x, maxX: first.x)) { partialResult, point in
            (
                minX: Swift.min(partialResult.minX, point.x),
                maxX: Swift.max(partialResult.maxX, point.x)
            )
        }
        return range.maxX - range.minX
    }
}

extension Array where Element == CGFloat {
    func clusteredXs(minimumSeparation: CGFloat) -> [CGFloat] {
        sorted().reduce(into: [CGFloat]()) { clusters, value in
            guard let previous = clusters.last else {
                clusters.append(value)
                return
            }

            if abs(value - previous) < minimumSeparation {
                clusters[clusters.count - 1] = (previous + value) / 2
            } else {
                clusters.append(value)
            }
        }
    }
}
#endif
