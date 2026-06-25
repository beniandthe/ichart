#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

enum RhythmicNotationQuantizer {
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

    static func autoApplyProposal(
        drawingData: Data,
        meter: Meter,
        drawingFrame: CGRect
    ) throws -> RhythmicNotationMeasureProposal {
        let drawing = try PKDrawing(data: drawingData)
        return try autoApplyProposal(drawing: drawing, meter: meter, drawingFrame: drawingFrame)
    }

    static func autoApplyProposal(
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
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations(from: drawing),
            drawingFrame: drawingFrame
        )
        return rasterTemplateVisualNoteAnchors(from: input)
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
        let primitives = rhythmInkPrimitives(
            from: strokeObservations,
            drawingFrame: drawingFrame
        )
        guard !strokeObservations.isEmpty else {
            return .keepWriting(.noInk, nil)
        }

        let rasterTemplateDecision = rasterTemplateRecognitionDecision(
            strokeObservations: strokeObservations,
            meter: meter,
            drawingFrame: drawingFrame,
            includeExtendedStability: includeExtendedStability
        )

        let visualDecision = VisualRhythmRecognizer.recognition(
            from: strokeObservations,
            drawingFrame: drawingFrame
        ).map { visualRecognition in
            visualRecognitionDecision(
                recognition: visualRecognition,
                strokeObservations: strokeObservations,
                primitives: primitives,
                meter: meter,
                includeExtendedStability: includeExtendedStability,
                drawingFrame: drawingFrame
            )
        }

        let legacyDecision = legacyFallbackRecognitionDecision(
            strokeObservations: strokeObservations,
            primitives: primitives,
            meter: meter,
            drawingFrame: drawingFrame
        )

        let reasoningPaths = [
            rasterTemplateDecision?.reasoningPath(kind: .rasterTemplate),
            visualDecision?.reasoningPath(kind: .visualShape),
            legacyDecision.reasoningPath(kind: .legacyFallback)
        ].compactMap { $0 }

        let selectedDecision = preferredRecognitionDecision(
            rasterTemplateDecision: rasterTemplateDecision,
            visualDecision: visualDecision,
            legacyDecision: legacyDecision
        )
        let contextCheckedDecision = decisionByApplyingContextRules(
            selectedDecision,
            meter: meter
        )
        let confidenceCheckedDecision = decisionByApplyingCrossPathReviewRules(
            contextCheckedDecision,
            reasoningPaths: reasoningPaths,
            meter: meter
        )
        let evidenceCheckedDecision = decisionByApplyingInternalEvidenceReviewRules(
            confidenceCheckedDecision,
            reasoningPaths: reasoningPaths,
            meter: meter
        )
        let contextPath = contextReasoningPath(
            for: evidenceCheckedDecision,
            meter: meter
        )
        return evidenceCheckedDecision.addingReasoningPaths(reasoningPaths + [contextPath])
    }

    private static func preferredRecognitionDecision(
        rasterTemplateDecision: RhythmRecognitionDecision?,
        visualDecision: RhythmRecognitionDecision?,
        legacyDecision: RhythmRecognitionDecision
    ) -> RhythmRecognitionDecision {
        guard let rasterTemplateDecision else {
            return visualDecision ?? legacyDecision
        }

        guard let visualDecision,
              case .commit(let visualProposal, let visualPhrase) = visualDecision,
              visualPhrase.isNaturalExactFit,
              visualProposal.safety != .manualReview else {
            return rasterTemplateDecision
        }

        switch rasterTemplateDecision {
        case .keepWriting:
            return visualDecision
        case .needsReview(let reason, let rasterPhrase, let rasterProposal):
            let rasterValues = rasterProposal?.values ?? rasterPhrase?.naturalValues ?? []
            let visualValues = visualProposal.values
            let sameValues = rasterValues == visualValues
            let rasterIsNaturalExactFit = rasterPhrase?.isNaturalExactFit == true
            if sameValues || !rasterIsNaturalExactFit || reason == .nonNaturalExactFit {
                return visualDecision
            }
            return rasterTemplateDecision
        case .commit:
            return rasterTemplateDecision
        }
    }

    private static func decisionByApplyingCrossPathReviewRules(
        _ decision: RhythmRecognitionDecision,
        reasoningPaths: [RhythmRecognitionReasoningPath],
        meter: Meter
    ) -> RhythmRecognitionDecision {
        guard case .commit(let proposal, let phrase) = decision,
              proposal.safety != .manualReview else {
            return decision
        }

        let competingRestNotePaths = reasoningPaths.filter { path in
            path.outcome == .commitCandidate
                && path.values != proposal.values
                && hasSameDurationGrid(path.values, proposal.values, meter: meter)
                && hasRestNoteDisagreement(path.values, proposal.values)
        }

        if let restAwarePath = competingRestNotePaths.first(where: { path in
            canPromoteRestAwarePath(path, over: proposal.values, phrase: phrase, meter: meter)
        }) {
            let promotedProposal = RhythmicNotationMeasureProposal(
                values: restAwarePath.values,
                safety: proposal.safety,
                isNaturalExactFit: proposal.isNaturalExactFit
            )
            return .commit(
                promotedProposal,
                phraseByPromotingRestAwareValues(
                    restAwarePath.values,
                    from: phrase,
                    meter: meter
                )
            )
        }

        if let glyphRestValues = restAwareValuesFromGlyphEvidence(
            over: proposal.values,
            phrase: phrase,
            meter: meter
        ) {
            let promotedProposal = RhythmicNotationMeasureProposal(
                values: glyphRestValues,
                safety: proposal.safety,
                isNaturalExactFit: proposal.isNaturalExactFit
            )
            return .commit(
                promotedProposal,
                phraseByPromotingRestAwareValues(
                    glyphRestValues,
                    from: phrase,
                    meter: meter,
                    source: phrase.source
                )
            )
        }

        guard !competingRestNotePaths.isEmpty else {
            return decision
        }

        let reviewProposal = RhythmicNotationMeasureProposal(
            values: proposal.values,
            safety: .manualReview,
            isNaturalExactFit: proposal.isNaturalExactFit
        )
        return .needsReview(.competingExactPhrases, phrase, reviewProposal)
    }

    private static func canPromoteRestAwarePath(
        _ path: RhythmRecognitionReasoningPath,
        over selectedValues: [RhythmValue],
        phrase: RhythmPhraseHypothesis,
        meter: Meter
    ) -> Bool {
        guard path.kind == .visualShape,
              path.values.reduce(0, { $0 + rhythmUnits(for: $1, meter: meter) }) == phrase.targetUnits,
              RhythmicNotationCompendium.accepts(path.values, in: meter) else {
            return false
        }

        return zip(path.values, selectedValues).enumerated().contains { index, pair in
            let (candidateValue, selectedValue) = pair
            return candidateValue.isRest
                && !selectedValue.isRest
                && rhythmUnits(for: candidateValue, meter: meter) == rhythmUnits(for: selectedValue, meter: meter)
                && phraseHasRestShapeEvidence(phrase, atSymbolIndex: index)
        }
    }

    private static func phraseByPromotingRestAwareValues(
        _ values: [RhythmValue],
        from phrase: RhythmPhraseHypothesis,
        meter: Meter,
        source: RhythmPhraseSource = .visual
    ) -> RhythmPhraseHypothesis {
        let promotedSymbols: [RhythmSymbolHypothesis]
        if phrase.symbols.count == values.count {
            promotedSymbols = zip(phrase.symbols, values).map { symbol, value in
                let candidateValues = symbol.candidateValues.contains(value)
                    ? symbol.candidateValues
                    : symbol.candidateValues + [value]
                return RhythmSymbolHypothesis(
                    coveredStrokeIndices: symbol.coveredStrokeIndices,
                    bounds: symbol.bounds,
                    candidateValues: candidateValues,
                    selectedValue: value
                )
            }
        } else {
            promotedSymbols = phrase.symbols
        }

        return RhythmPhraseHypothesis(
            source: source,
            primitives: phrase.primitives,
            symbols: promotedSymbols,
            uncoveredStrokeIndices: phrase.uncoveredStrokeIndices,
            naturalValues: values,
            naturalUnits: values.reduce(0) { $0 + rhythmUnits(for: $1, meter: meter) },
            targetUnits: phrase.targetUnits,
            passesCompendium: RhythmicNotationCompendium.accepts(values, in: meter)
        )
    }

    private static func restAwareValuesFromGlyphEvidence(
        over selectedValues: [RhythmValue],
        phrase: RhythmPhraseHypothesis,
        meter: Meter
    ) -> [RhythmValue]? {
        for index in selectedValues.indices {
            let selectedValue = selectedValues[index]
            guard !selectedValue.isRest,
                  let restValue = sameDurationRestValue(for: selectedValue),
                  phraseSymbolHasRestDominantEvidence(phrase, atSymbolIndex: index) else {
                continue
            }

            var promotedValues = selectedValues
            promotedValues[index] = restValue
            guard hasSameDurationGrid(promotedValues, selectedValues, meter: meter),
                  RhythmicNotationCompendium.accepts(promotedValues, in: meter) else {
                continue
            }
            return promotedValues
        }

        return nil
    }

    private static func sameDurationRestValue(for value: RhythmValue) -> RhythmValue? {
        switch value {
        case .sixteenth:
            return .sixteenthRest
        case .eighth:
            return .eighthRest
        case .quarter:
            return .quarterRest
        case .half:
            return .halfRest
        case .whole:
            return .wholeRest
        case .slash, .dottedEighth, .sixteenthRest, .eighthRest, .quarterRest, .dottedQuarter, .halfRest, .dottedHalf,
             .wholeRest, .tiedContinuation:
            return nil
        }
    }

    private static func decisionByApplyingInternalEvidenceReviewRules(
        _ decision: RhythmRecognitionDecision,
        reasoningPaths: [RhythmRecognitionReasoningPath],
        meter: Meter
    ) -> RhythmRecognitionDecision {
        guard case .commit(let proposal, let phrase) = decision,
              proposal.safety != .manualReview,
              !reasoningPathsHaveExactVisualRasterConsensus(reasoningPaths, values: proposal.values, phrase: phrase, meter: meter),
              !phraseHasRestAuthoritativeExactFit(phrase, values: proposal.values, meter: meter),
              phraseHasInternalRestNoteEvidenceConflict(phrase) else {
            return decision
        }

        let reviewProposal = RhythmicNotationMeasureProposal(
            values: proposal.values,
            safety: .manualReview,
            isNaturalExactFit: proposal.isNaturalExactFit
        )
        return .needsReview(.ambiguousPhrase, phrase, reviewProposal)
    }

    private static func reasoningPathsHaveExactVisualRasterConsensus(
        _ reasoningPaths: [RhythmRecognitionReasoningPath],
        values: [RhythmValue],
        phrase: RhythmPhraseHypothesis,
        meter: Meter
    ) -> Bool {
        guard values == phrase.naturalValues,
              phrase.naturalUnits == phrase.targetUnits,
              RhythmicNotationCompendium.accepts(values, in: meter) else {
            return false
        }

        let rasterAgrees = reasoningPaths.contains { path in
            path.kind == .rasterTemplate
                && path.outcome == .commitCandidate
                && path.values == values
        }
        let visualAgrees = reasoningPaths.contains { path in
            path.kind == .visualShape
                && path.outcome == .commitCandidate
                && path.values == values
        }
        return rasterAgrees && visualAgrees
    }

    private static func phraseHasRestAuthoritativeExactFit(
        _ phrase: RhythmPhraseHypothesis,
        values: [RhythmValue],
        meter: Meter
    ) -> Bool {
        guard phrase.source == .visual,
              values == phrase.naturalValues,
              values.contains(where: \.isRest),
              phrase.naturalUnits == phrase.targetUnits,
              RhythmicNotationCompendium.accepts(values, in: meter) else {
            return false
        }

        return values.indices.contains { index in
            values[index].isRest && phraseHasRestShapeEvidence(phrase, atSymbolIndex: index)
        }
    }

    private static func hasSameDurationGrid(
        _ lhs: [RhythmValue],
        _ rhs: [RhythmValue],
        meter: Meter
    ) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { pair in
                rhythmUnits(for: pair.0, meter: meter) == rhythmUnits(for: pair.1, meter: meter)
            }
    }

    private static func hasRestNoteDisagreement(
        _ lhs: [RhythmValue],
        _ rhs: [RhythmValue]
    ) -> Bool {
        zip(lhs, rhs).contains { pair in
            pair.0.isRest != pair.1.isRest
        }
    }

    private static func phraseHasRestShapeEvidence(
        _ phrase: RhythmPhraseHypothesis,
        atSymbolIndex symbolIndex: Int
    ) -> Bool {
        let primitiveByStrokeIndex = Dictionary(
            uniqueKeysWithValues: phrase.primitives.map { primitive in
                (primitive.strokeIndex, primitive)
            }
        )
        guard phrase.symbols.indices.contains(symbolIndex) else {
            return phrase.primitives.contains { $0.kind == .restShape }
        }

        return phrase.symbols[symbolIndex].coveredStrokeIndices.contains { strokeIndex in
            primitiveByStrokeIndex[strokeIndex]?.kind == .restShape
        }
    }

    private static func phraseSymbolHasRestDominantEvidence(
        _ phrase: RhythmPhraseHypothesis,
        atSymbolIndex symbolIndex: Int
    ) -> Bool {
        let primitiveByStrokeIndex = Dictionary(
            uniqueKeysWithValues: phrase.primitives.map { primitive in
                (primitive.strokeIndex, primitive)
            }
        )
        guard phrase.symbols.indices.contains(symbolIndex) else {
            return false
        }

        let primitiveKinds = phrase.symbols[symbolIndex].coveredStrokeIndices.compactMap { strokeIndex in
            primitiveByStrokeIndex[strokeIndex]?.kind
        }
        return primitiveKinds.contains(.restShape)
            && !primitiveKinds.contains(.notehead)
            && !primitiveKinds.contains(.stem)
            && !primitiveKinds.contains(.beam)
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

    private static func visualRecognitionDecision(
        recognition: VisualRhythmRecognition,
        strokeObservations: [StrokeObservation],
        primitives: [RhythmInkPrimitive],
        meter: Meter,
        includeExtendedStability: Bool,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision {
        let candidateGroups = recognition.candidateGroups
        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        let orderedStrokes = strokeObservations.sortedByVisualPosition()
        let phrase = phraseHypothesis(
            source: .visual,
            primitives: primitives,
            symbols: symbolHypotheses(
                from: recognition.events,
                orderedStrokes: orderedStrokes
            ),
            uncoveredStrokeIndices: strokeIndices(
                for: recognition.uncoveredStrokes,
                orderedStrokes: orderedStrokes
            ),
            candidateGroups: candidateGroups,
            naturalPath: naturalPath,
            meter: meter
        )

        if !phrase.uncoveredStrokeIndices.isEmpty {
            return .keepWriting(.uncoveredStrokes, phrase)
        }

        if phrase.isNaturalExactFit {
            let proposal = measureProposal(
                from: candidateGroups,
                exactPath: naturalPath,
                meter: meter,
                includeExtendedStability: includeExtendedStability
            )
            if phraseHasTightMixedRestNoteCluster(phrase, drawingFrame: drawingFrame) {
                let reviewProposal = RhythmicNotationMeasureProposal(
                    values: proposal.values,
                    safety: .manualReview,
                    isNaturalExactFit: proposal.isNaturalExactFit
                )
                return .needsReview(.ambiguousPhrase, phrase, reviewProposal)
            }
            if proposal.safety == .manualReview {
                let reviewReason = manualReviewReason(
                    for: naturalPath,
                    candidateGroups: candidateGroups,
                    meter: meter
                ) ?? .manualReview
                return .needsReview(reviewReason, phrase, proposal)
            }
            return .commit(proposal, phrase)
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        if let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter),
           RhythmicNotationCompendium.accepts(exactPath.values, in: meter) {
            let proposal = RhythmicNotationMeasureProposal(
                values: exactPath.values,
                safety: .manualReview,
                isNaturalExactFit: false
            )
            return .needsReview(.nonNaturalExactFit, phrase, proposal)
        }

        if naturalPath.units < targetUnits {
            return .keepWriting(.underfilled, phrase)
        }
        if naturalPath.units > targetUnits {
            return .keepWriting(.overflow, phrase)
        }

        return .keepWriting(.unsupported, phrase)
    }

    private static func legacyFallbackRecognitionDecision(
        strokeObservations: [StrokeObservation],
        primitives: [RhythmInkPrimitive],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision {
        let candidateGroups: [[RhythmCandidate]]
        do {
            candidateGroups = try leftToRightCandidateGroups(
                from: strokeObservations,
                drawingFrame: drawingFrame
            )
        } catch {
            return .keepWriting(.unsupported, nil)
        }

        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        let phrase = phraseHypothesis(
            source: .legacyFallback,
            primitives: primitives,
            symbols: legacySymbolHypotheses(from: candidateGroups),
            uncoveredStrokeIndices: [],
            candidateGroups: candidateGroups,
            naturalPath: naturalPath,
            meter: meter
        )

        if let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter),
           RhythmicNotationCompendium.accepts(exactPath.values, in: meter) {
            return .keepWriting(.nonVisualFallback, phrase)
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        if naturalPath.units < targetUnits {
            return .keepWriting(.underfilled, phrase)
        }
        if naturalPath.units > targetUnits {
            return .keepWriting(.overflow, phrase)
        }

        return .keepWriting(.unsupported, phrase)
    }

    private static func phraseHypothesis(
        source: RhythmPhraseSource,
        primitives: [RhythmInkPrimitive],
        symbols: [RhythmSymbolHypothesis],
        uncoveredStrokeIndices: [Int],
        candidateGroups: [[RhythmCandidate]],
        naturalPath: CandidatePath,
        meter: Meter
    ) -> RhythmPhraseHypothesis {
        RhythmPhraseHypothesis(
            source: source,
            primitives: primitives,
            symbols: symbols,
            uncoveredStrokeIndices: uncoveredStrokeIndices,
            naturalValues: naturalPath.values,
            naturalUnits: naturalPath.units,
            targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
            passesCompendium: RhythmicNotationCompendium.accepts(naturalPath.values, in: meter)
        )
    }

    private static func symbolHypotheses(
        from events: [VisualRhythmEvent],
        orderedStrokes: [StrokeObservation]
    ) -> [RhythmSymbolHypothesis] {
        let indexByStroke = Dictionary(
            uniqueKeysWithValues: orderedStrokes.enumerated().map { index, stroke in
                (stroke, index)
            }
        )

        return events.flatMap { event -> [RhythmSymbolHypothesis] in
            let coveredStrokeIndices = Set(event.strokes.compactMap { indexByStroke[$0] })
            let bounds = Array(event.strokes).nonEmptyBounds ?? .null
            return event.candidateGroups.map { candidates in
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: coveredStrokeIndices,
                    bounds: bounds,
                    candidateValues: candidates.map(\.value),
                    selectedValue: candidates.min { lhs, rhs in lhs.score < rhs.score }?.value
                )
            }
        }
    }

    private static func strokeIndices(
        for strokes: [StrokeObservation],
        orderedStrokes: [StrokeObservation]
    ) -> [Int] {
        let uncoveredStrokes = Set(strokes)
        return orderedStrokes.enumerated().compactMap { index, stroke in
            uncoveredStrokes.contains(stroke) ? index : nil
        }
    }

    private static func legacySymbolHypotheses(
        from candidateGroups: [[RhythmCandidate]]
    ) -> [RhythmSymbolHypothesis] {
        candidateGroups.map { candidates in
            RhythmSymbolHypothesis(
                coveredStrokeIndices: [],
                bounds: .null,
                candidateValues: candidates.map(\.value),
                selectedValue: candidates.min { lhs, rhs in lhs.score < rhs.score }?.value
            )
        }
    }

    static func phraseHasTightMixedRestNoteCluster(
        _ phrase: RhythmPhraseHypothesis,
        drawingFrame: CGRect
    ) -> Bool {
        let selectedSymbols = phrase.symbols
            .compactMap { symbol -> (bounds: CGRect, value: RhythmValue)? in
                guard let value = symbol.selectedValue,
                      !symbol.bounds.isNull,
                      !symbol.bounds.isEmpty else {
                    return nil
                }
                return (symbol.bounds, value)
            }
            .sorted { lhs, rhs in
                if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                    return lhs.bounds.minX < rhs.bounds.minX
                }
                return lhs.bounds.midY < rhs.bounds.midY
            }

        guard selectedSymbols.count >= 2,
              selectedSymbols.contains(where: { $0.value.isRest }),
              selectedSymbols.contains(where: { !$0.value.isRest }) else {
            return false
        }

        for (lhs, rhs) in zip(selectedSymbols, selectedSymbols.dropFirst()) {
            guard lhs.value.isRest != rhs.value.isRest else {
                continue
            }

            let horizontalOverlap = min(lhs.bounds.maxX, rhs.bounds.maxX)
                - max(lhs.bounds.minX, rhs.bounds.minX)
            let verticalOverlap = min(lhs.bounds.maxY, rhs.bounds.maxY) - max(lhs.bounds.minY, rhs.bounds.minY)
            let verticalOverlapRatio = verticalOverlap / max(CGFloat(1), min(lhs.bounds.height, rhs.bounds.height))
            let collisionTolerance = max(CGFloat(2), min(CGFloat(5), drawingFrame.width * 0.012))
            let symbolsCollide = horizontalOverlap >= -collisionTolerance
            if symbolsCollide && verticalOverlapRatio >= 0.35 {
                return true
            }
        }

        return false
    }

    static func phraseHasInternalRestNoteEvidenceConflict(
        _ phrase: RhythmPhraseHypothesis
    ) -> Bool {
        let primitiveByStrokeIndex = Dictionary(
            uniqueKeysWithValues: phrase.primitives.map { primitive in
                (primitive.strokeIndex, primitive)
            }
        )

        return phrase.symbols.contains { symbol in
            guard let selectedValue = symbol.selectedValue,
                  !selectedValue.isRest else {
                return false
            }

            let primitiveKinds = symbol.coveredStrokeIndices.compactMap { strokeIndex in
                primitiveByStrokeIndex[strokeIndex]?.kind
            }
            let hasRestShape = primitiveKinds.contains(.restShape)
            let hasNotehead = primitiveKinds.contains(.notehead)
            let hasNoteStructure = primitiveKinds.contains(.stem) || primitiveKinds.contains(.beam)
            if phraseHasSelectedRestSharingEvidence(phrase, with: symbol) {
                return false
            }
            guard hasRestShape,
                  hasNotehead,
                  !hasNoteStructure else {
                return false
            }

            let candidateIncludesRest = symbol.candidateValues.contains(where: \.isRest)
            return !candidateIncludesRest || primitiveKinds.contains(.dot)
        }
    }

    private static func phraseHasSelectedRestSharingEvidence(
        _ phrase: RhythmPhraseHypothesis,
        with symbol: RhythmSymbolHypothesis
    ) -> Bool {
        phrase.symbols.contains { otherSymbol in
            guard otherSymbol.selectedValue?.isRest == true else {
                return false
            }

            return !otherSymbol.coveredStrokeIndices.isDisjoint(with: symbol.coveredStrokeIndices)
        }
    }

    static func rhythmInkPrimitives(
        from strokes: [StrokeObservation],
        drawingFrame: CGRect
    ) -> [RhythmInkPrimitive] {
        let orderedStrokes = strokes.sortedByVisualPosition()
        let sceneBounds = orderedStrokes.nonEmptyBounds ?? drawingFrame
        let stems = orderedStrokes.filter { $0.looksLikeVisualStem(in: sceneBounds) }

        return orderedStrokes.enumerated().map { index, stroke in
            let kind: RhythmInkPrimitiveKind
            let singleStrokeFeatures = SymbolFeatures(
                symbol: SymbolObservation(strokes: [stroke]),
                drawingFrame: sceneBounds
            )
            if stroke.looksLikeVisualNotehead(in: sceneBounds) {
                kind = .notehead
            } else if stroke.looksLikeLooseDot(in: sceneBounds) {
                kind = .dot
            } else if stroke.looksLikeRhythmicPlaceholderSlash(in: stroke.bounds) {
                kind = .slash
            } else if stroke.looksLikeVisualBeamSeed(in: sceneBounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: sceneBounds,
                    drawingFrame: drawingFrame
                )
                || stroke.looksLikeFoldedBeamStemSeed(
                    over: stems,
                    in: sceneBounds,
                    drawingFrame: drawingFrame
                ) {
                kind = .beam
            } else if stroke.looksLikeQuarterRestBody(in: sceneBounds)
                || stroke.looksLikeFlexibleOneStrokeEighthRest(in: sceneBounds)
                || stroke.looksLikeSingleStrokeEighthRest(in: sceneBounds)
                || stroke.looksLikeEighthRestHook(in: sceneBounds)
                || looksLikeHalfRest(singleStrokeFeatures)
                || looksLikeWholeRest(singleStrokeFeatures) {
                kind = .restShape
            } else if stroke.looksLikeVisualStem(in: sceneBounds) {
                kind = .stem
            } else if stroke.isIgnorableVisualNoise(in: sceneBounds) {
                kind = .cleanup
            } else {
                kind = .unknown
            }

            return RhythmInkPrimitive(
                strokeIndex: index,
                kind: kind,
                bounds: stroke.bounds
            )
        }
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
        case .unsupported, .nonNaturalExactFit, .ambiguousPhrase, .manualReview, .nonVisualFallback, .uncoveredStrokes, .competingExactPhrases:
            return .unsupportedSymbol(0)
        }
    }

    private static func measureProposal(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect,
        includeExtendedStability: Bool
    ) throws -> RhythmicNotationMeasureProposal {
        let strokeObservations = strokeObservations(from: drawing)
        if let visualRecognition = VisualRhythmRecognizer.recognition(
            from: strokeObservations,
            drawingFrame: drawingFrame
        ),
           visualRecognition.uncoveredStrokes.isEmpty {
            let visualNaturalPath = bestNaturalPath(from: visualRecognition.candidateGroups, meter: meter)
            if visualRecognition.containsBeamedEighthEvent,
               visualNaturalPath.units == rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
               RhythmicNotationCompendium.accepts(visualNaturalPath.values, in: meter) {
                return measureProposal(
                    from: visualRecognition.candidateGroups,
                    exactPath: visualNaturalPath,
                    meter: meter,
                    includeExtendedStability: includeExtendedStability
                )
            }

            if let visualPath = bestMeasureAlignedPath(from: visualRecognition.candidateGroups, meter: meter) {
                return measureProposal(
                    from: visualRecognition.candidateGroups,
                    exactPath: visualPath,
                    meter: meter,
                    includeExtendedStability: includeExtendedStability
                )
            }

            if visualRecognition.containsBeamedEighthEvent {
                return try measureProposal(
                    candidateGroups: visualRecognition.candidateGroups,
                    meter: meter,
                    includeExtendedStability: includeExtendedStability
                )
            }
        }

        return try measureProposal(
            candidateGroups: leftToRightCandidateGroups(
                from: strokeObservations,
                drawingFrame: drawingFrame
            ),
            meter: meter,
            includeExtendedStability: includeExtendedStability
        )
    }

    private static func leftToRightCandidateGroups(
        from strokeObservations: [StrokeObservation],
        drawingFrame: CGRect
    ) throws -> [[RhythmCandidate]] {
        let symbolGroups = groupedSymbols(from: strokeObservations, drawingFrame: drawingFrame)
        var candidateGroups: [[RhythmCandidate]] = []
        for (index, group) in symbolGroups.enumerated() {
            if let slashGroups = slashCandidateGroups(for: group, drawingFrame: drawingFrame) {
                candidateGroups.append(contentsOf: slashGroups)
                continue
            }

            if let beamedEighthGroups = beamedEighthCandidateGroups(for: group, drawingFrame: drawingFrame) {
                candidateGroups.append(contentsOf: beamedEighthGroups)
                continue
            }

            let candidates = classifyCandidates(group, drawingFrame: drawingFrame)
            guard !candidates.isEmpty else {
                throw RhythmicNotationQuantizationError.unsupportedSymbol(index)
            }
            candidateGroups.append(candidates)
        }

        return candidateGroups
    }

    private static func measureProposal(
        candidateGroups: [[RhythmCandidate]],
        meter: Meter,
        includeExtendedStability: Bool
    ) throws -> RhythmicNotationMeasureProposal {
        if let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter) {
            return measureProposal(
                from: candidateGroups,
                exactPath: exactPath,
                meter: meter,
                includeExtendedStability: includeExtendedStability
            )
        }

        let expectedBeats = meter.measureLengthInWholeNotes / meter.beatUnitWholeNoteLength
        let values = bestNaturalValues(from: candidateGroups, meter: meter)
        let actualBeats = values.reduce(0) { partialResult, value in
            partialResult + value.wholeNoteLength(in: meter) / meter.beatUnitWholeNoteLength
        }
        let delta = actualBeats - expectedBeats

        if delta < 0 {
            throw RhythmicNotationQuantizationError.underfilled(
                expectedBeats: expectedBeats,
                actualBeats: actualBeats
            )
        }

        throw RhythmicNotationQuantizationError.overflow(
            expectedBeats: expectedBeats,
            actualBeats: actualBeats
        )
    }

    static func measureProposal(
        from candidateGroups: [[RhythmCandidate]],
        exactPath: CandidatePath,
        meter: Meter,
        includeExtendedStability: Bool
    ) -> RhythmicNotationMeasureProposal {
        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        return RhythmicNotationMeasureProposal(
            values: exactPath.values,
            safety: proposalSafety(
                for: exactPath,
                candidateGroups: candidateGroups,
                meter: meter,
                includeExtendedStability: includeExtendedStability
            ),
            isNaturalExactFit: naturalPath.units == rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
                && naturalPath.values == exactPath.values
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

    static func groupedSymbols(
        from strokes: [StrokeObservation],
        drawingFrame: CGRect
    ) -> [SymbolObservation] {
        let sortedStrokes = strokes.sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.bounds.midY < rhs.bounds.midY
        }

        let gapThreshold = max(14, min(32, drawingFrame.width * 0.085))
        let glyphAttachThreshold = max(CGFloat(5), min(CGFloat(10), drawingFrame.width * 0.028))
        let dotThreshold = max(CGFloat(5), min(CGFloat(9), drawingFrame.height * 0.1))
        var groups: [[StrokeObservation]] = []

        for stroke in sortedStrokes {
            guard var currentGroup = groups.popLast() else {
                groups.append([stroke])
                continue
            }

            let currentBounds = currentGroup.reduce(into: CGRect.null) { partialResult, member in
                partialResult = partialResult.union(member.bounds)
            }
            let horizontalGap = stroke.bounds.minX - currentBounds.maxX
            let verticalDistance = abs(stroke.bounds.midY - currentBounds.midY)
            let verticalTolerance = max(18, drawingFrame.height * 0.42)
            let attachesAsDot = stroke.bounds.width <= dotThreshold
                && stroke.bounds.height <= dotThreshold
                && horizontalGap <= gapThreshold * 1.55
                && verticalDistance <= verticalTolerance
                && stroke.bounds.minX >= currentBounds.midX

            let combinedStrokes = currentGroup + [stroke]
            let combinedBounds = currentBounds.union(stroke.bounds)
            let currentBeamCount = SymbolObservation(strokes: currentGroup)
                .beamedEighthNoteCount(drawingFrame: drawingFrame)
            let combinedBeamCount = SymbolObservation(strokes: combinedStrokes)
                .beamedEighthNoteCount(drawingFrame: drawingFrame)
            let beamConnectsGlyphs = combinedBeamCount >= 2
                && combinedBeamCount > currentBeamCount
            let attachesWithinGlyph = horizontalGap <= glyphAttachThreshold
                || currentGroup.canAttachStrokeWithinSingleGlyph(stroke, drawingFrame: drawingFrame)

            let overlapsEnough = (attachesWithinGlyph || beamConnectsGlyphs)
                && stroke.bounds.minY <= currentBounds.maxY + verticalTolerance * 0.65
                && stroke.bounds.maxY >= currentBounds.minY - verticalTolerance * 0.65
                && combinedBounds.width <= max(currentBounds.width + stroke.bounds.width + glyphAttachThreshold, drawingFrame.width * 0.48)

            if attachesAsDot || overlapsEnough {
                currentGroup.append(stroke)
                groups.append(currentGroup)
            } else {
                groups.append(currentGroup)
                groups.append([stroke])
            }
        }

        return groups
            .mergingLooseDots(drawingFrame: drawingFrame)
            .reattachingLeadingEighthRestDotsToFollowingTails(drawingFrame: drawingFrame)
            .reattachingLeadingNoteheadsToFollowingBeams(drawingFrame: drawingFrame)
            .splittingCompoundStemmedSymbols(drawingFrame: drawingFrame)
            .reattachingLeadingEighthRestDotsToFollowingTails(drawingFrame: drawingFrame)
            .reattachingLeadingNoteheadsToFollowingBeams(drawingFrame: drawingFrame)
            .reattachingLeadingDotsToPreviousSymbols(drawingFrame: drawingFrame)
            .map(SymbolObservation.init(strokes:))
    }

    private static func bestMeasureAlignedValues(
        from candidateGroups: [[RhythmCandidate]],
        meter: Meter
    ) -> [RhythmValue]? {
        bestMeasureAlignedPath(from: candidateGroups, meter: meter)?.values
    }

    static func bestMeasureAlignedPath(
        from candidateGroups: [[RhythmCandidate]],
        meter: Meter
    ) -> CandidatePath? {
        guard !candidateGroups.isEmpty else {
            return nil
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        if naturalPath.units == targetUnits {
            return naturalPath
        }

        guard let exactPath = bestExactPath(from: candidateGroups, targetUnits: targetUnits, meter: meter) else {
            return nil
        }

        let tolerance = max(1.0, Double(candidateGroups.count) * 0.5)
        guard exactPath.score <= naturalPath.score + tolerance else {
            return nil
        }

        return exactPath
    }

    private static func bestNaturalValues(from candidateGroups: [[RhythmCandidate]], meter: Meter) -> [RhythmValue] {
        bestNaturalPath(from: candidateGroups, meter: meter).values
    }

    static func bestNaturalPath(from candidateGroups: [[RhythmCandidate]], meter: Meter? = nil) -> CandidatePath {
        candidateGroups.reduce(CandidatePath(values: [], score: 0, units: 0)) { partialResult, candidates in
            guard let bestCandidate = candidates.min(by: { $0.score < $1.score }) else {
                return partialResult
            }

            return CandidatePath(
                values: partialResult.values + [bestCandidate.value],
                score: partialResult.score + bestCandidate.score,
                units: partialResult.units + rhythmUnits(for: bestCandidate.value, meter: meter)
            )
        }
    }

    private static func bestExactPath(
        from candidateGroups: [[RhythmCandidate]],
        targetUnits: Int,
        meter: Meter? = nil
    ) -> CandidatePath? {
        rankedExactPaths(
            from: candidateGroups,
            targetUnits: targetUnits,
            meter: meter
        ).first
    }

    private static func rankedExactPaths(
        from candidateGroups: [[RhythmCandidate]],
        targetUnits: Int,
        meter: Meter? = nil
    ) -> [CandidatePath] {
        var states: [Int: [CandidatePath]] = [
            0: [CandidatePath(values: [], score: 0, units: 0)]
        ]

        for candidates in candidateGroups {
            var nextStates: [Int: [CandidatePath]] = [:]
            for rankedStates in states.values {
                for state in rankedStates {
                    for candidate in candidates {
                        guard candidate.isConfidentEnoughForMeasureFit else {
                            continue
                        }

                        let nextUnits = state.units + rhythmUnits(for: candidate.value, meter: meter)
                        guard nextUnits <= targetUnits else {
                            continue
                        }

                        let nextPath = CandidatePath(
                            values: state.values + [candidate.value],
                            score: state.score + candidate.score,
                            units: nextUnits
                        )
                        nextStates[nextUnits, default: []].append(nextPath)
                    }
                }
            }

            states = nextStates.mapValues { paths in
                rankedUniquePaths(paths, limit: 4, meter: meter)
            }
        }

        return rankedUniquePaths(states[targetUnits] ?? [], limit: 4, meter: meter)
    }

    private static func rankedUniquePaths(_ paths: [CandidatePath], limit: Int, meter: Meter? = nil) -> [CandidatePath] {
        var bestByValues: [[RhythmValue]: CandidatePath] = [:]
        for path in paths {
            if let existingPath = bestByValues[path.values],
               existingPath.score <= path.score {
                continue
            }
            bestByValues[path.values] = path
        }

        return Array(bestByValues.values)
            .sorted { lhs, rhs in
                let lhsContextRank = recognitionContextRank(for: lhs.values, meter: meter)
                let rhsContextRank = recognitionContextRank(for: rhs.values, meter: meter)
                if lhsContextRank != rhsContextRank {
                    return lhsContextRank < rhsContextRank
                }
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score < rhs.score
                }
                if lhs.values.count != rhs.values.count {
                    return lhs.values.count > rhs.values.count
                }
                return lhs.values.map(\.rawValue).lexicographicallyPrecedes(rhs.values.map(\.rawValue))
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func recognitionContextRank(for values: [RhythmValue], meter: Meter?) -> Int {
        guard let meter else {
            return 0
        }

        return RhythmRecognitionContextRules.hasProtectedBeamableBoundary(
            in: values,
            meter: meter
        ) ? 1 : 0
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

    // Auto-apply is stricter than manual quantize because a bad live commit clears the user's ink.
    private static func proposalSafety(
        for exactPath: CandidatePath,
        candidateGroups: [[RhythmCandidate]],
        meter: Meter,
        includeExtendedStability: Bool
    ) -> RhythmicNotationMeasureProposalSafety {
        guard includeExtendedStability else {
            return .autoApply
        }

        if manualReviewReason(
            for: exactPath,
            candidateGroups: candidateGroups,
            meter: meter
        ) != nil {
            return .manualReview
        }

        if requiresExtendedStabilityBeforeAutoApply(
            for: exactPath,
            candidateGroups: candidateGroups
        ) {
            return .extendedStability
        }

        return .autoApply
    }

    static func manualReviewReason(
        for exactPath: CandidatePath,
        candidateGroups: [[RhythmCandidate]],
        meter: Meter
    ) -> RhythmRecognitionReason? {
        if exactPath.values.count == 1 {
            switch exactPath.values[0] {
            case .whole, .wholeRest:
                return .manualReview
            default:
                break
            }
        }

        if exactPath.values.count == candidateGroups.count {
            let selectedCandidates = zip(exactPath.values, candidateGroups).compactMap { value, candidates in
                candidates.first { $0.value == value }
            }
            if selectedCandidates.contains(where: { !$0.canDriveExactFit }) {
                return .manualReview
            }
            if selectedCandidates.contains(where: { $0.score >= 1.1 }) {
                return .manualReview
            }
        }

        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        if exactPath.values != naturalPath.values {
            let stretchTolerance = max(0.35, Double(candidateGroups.count) * 0.18)
            if exactPath.score > naturalPath.score + stretchTolerance {
                return .manualReview
            }
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        let rankedPaths = rankedExactPaths(from: candidateGroups, targetUnits: targetUnits, meter: meter)
        if let bestPath = rankedPaths.first,
           bestPath.values == exactPath.values,
           let alternatePath = rankedPaths.dropFirst().first {
            let margin = alternatePath.score - bestPath.score
            let requiredMargin = max(0.45, Double(candidateGroups.count) * 0.12)
            if margin < requiredMargin {
                return .competingExactPhrases
            }
        }

        return nil
    }

    static func exactFitReviewReasonForTesting(
        exactValues: [RhythmValue],
        candidateScores: [[RhythmValue: Double]],
        meter: Meter
    ) -> RhythmRecognitionReason? {
        let candidateGroups = candidateScores.map { scoresByValue in
            scoresByValue.map { value, score in
                RhythmCandidate(value: value, score: score)
            }
        }
        let exactScore = zip(exactValues, candidateGroups).reduce(0) { partialResult, pair in
            let candidateScore = pair.1.first { $0.value == pair.0 }?.score ?? Double.greatestFiniteMagnitude
            return partialResult + candidateScore
        }
        let exactPath = CandidatePath(
            values: exactValues,
            score: exactScore,
            units: exactValues.reduce(0) { $0 + rhythmUnits(for: $1, meter: meter) }
        )
        return manualReviewReason(for: exactPath, candidateGroups: candidateGroups, meter: meter)
    }

    static func bestExactValuesForTesting(
        candidateScores: [[RhythmValue: Double]],
        meter: Meter
    ) -> [RhythmValue]? {
        let candidateGroups = candidateScores.map { scoresByValue in
            scoresByValue.map { value, score in
                RhythmCandidate(value: value, score: score)
            }
        }
        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        return bestExactPath(
            from: candidateGroups,
            targetUnits: targetUnits,
            meter: meter
        )?.values
    }

    static func crossPathReviewReasonForTesting(
        selectedValues: [RhythmValue],
        alternateValues: [RhythmValue],
        meter: Meter
    ) -> RhythmRecognitionReason? {
        let proposal = RhythmicNotationMeasureProposal(
            values: selectedValues,
            safety: .autoApply,
            isNaturalExactFit: true
        )
        let phrase = RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: [],
            symbols: [],
            uncoveredStrokeIndices: [],
            naturalValues: selectedValues,
            naturalUnits: selectedValues.reduce(0) { $0 + rhythmUnits(for: $1, meter: meter) },
            targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
            passesCompendium: true
        )
        let alternatePath = RhythmRecognitionReasoningPath(
            kind: .visualShape,
            outcome: .commitCandidate,
            values: alternateValues,
            reason: nil,
            summary: "source=visual reason=none values=\(alternateValues.map(\.rawValue).joined(separator: ","))"
        )
        let decision = decisionByApplyingCrossPathReviewRules(
            .commit(proposal, phrase),
            reasoningPaths: [alternatePath],
            meter: meter
        )

        return decision.reason
    }

    private static func requiresExtendedStabilityBeforeAutoApply(
        for exactPath: CandidatePath,
        candidateGroups: [[RhythmCandidate]]
    ) -> Bool {
        guard exactPath.values.count == candidateGroups.count,
              exactPath.values.last == .quarter,
              let terminalCandidates = candidateGroups.last else {
            return false
        }

        let hasSelectedQuarter = terminalCandidates.contains { candidate in
            candidate.value == .quarter && candidate.isConfidentEnoughForMeasureFit
        }
        let hasPlayableEighthAlternative = terminalCandidates.contains { candidate in
            candidate.value == .eighth
                && (candidate.isConfidentEnoughForMeasureFit || candidate.canExtendAutoApplyStability)
        }

        return hasSelectedQuarter && hasPlayableEighthAlternative
    }

    static func classifyCandidates(
        _ symbol: SymbolObservation,
        drawingFrame: CGRect
    ) -> [RhythmCandidate] {
        let features = SymbolFeatures(symbol: symbol, drawingFrame: drawingFrame)
        guard !features.contentStrokes.isEmpty else {
            return []
        }

        var candidateScores: [RhythmValue: Double] = [:]
        func add(_ value: RhythmValue, score: Double) {
            let clampedScore = max(0, score)
            if let existingScore = candidateScores[value],
               existingScore <= clampedScore {
                return
            }
            candidateScores[value] = clampedScore
        }

        let sixteenthRestMatch = looksLikeSixteenthRest(features)
        let quarterRestMatch = looksLikeQuarterRest(features)
        let eighthRestMatch = looksLikeEighthRest(features)
        if sixteenthRestMatch || quarterRestMatch || eighthRestMatch {
            if sixteenthRestMatch {
                add(.sixteenthRest, score: 0.0)
                add(.eighthRest, score: 1.15)
                add(.quarterRest, score: 1.55)
            } else if eighthRestMatch {
                add(.eighthRest, score: 0.0)
                add(.quarterRest, score: 1.35)
            } else {
                add(.quarterRest, score: 0.0)
                add(.eighthRest, score: 1.35)
            }

            return candidateScores
                .map { RhythmCandidate(value: $0.key, score: $0.value) }
                .sorted { lhs, rhs in
                    if abs(lhs.score - rhs.score) > 0.0001 {
                        return lhs.score < rhs.score
                    }
                    return lhs.value.wholeNoteLength < rhs.value.wholeNoteLength
                }
        }

        if looksLikeRhythmSlash(symbol, drawingFrame: drawingFrame) {
            return [
                RhythmCandidate(value: .slash, score: 0.0)
            ]
        }

        if looksLikeWholeRest(features) {
            add(.wholeRest, score: 0.05)
            add(.halfRest, score: 0.9)
        }

        if looksLikeHalfRest(features) {
            add(.halfRest, score: 0.05)
            add(.wholeRest, score: 1.15)
        }

        if features.hasStem {
            if features.hasFlag {
                if features.hasDot {
                    add(.dottedEighth, score: 0.02)
                }
                add(.eighth, score: features.hasDot ? 1.25 : (features.hasLowerHeadMass ? 0.02 : 0.18))
                add(.quarter, score: features.hasDot ? 1.8 : 1.25)
            }

            if features.hasDot,
               !features.hasFlag {
                if features.hasHollowHead && !features.hasFilledHead {
                    add(.dottedHalf, score: 0.02)
                    add(.dottedQuarter, score: 0.5)
                    add(.half, score: 1.55)
                } else if features.hasFilledHead || features.hasLowerHeadMass || features.hasStemAndKick {
                    add(.dottedQuarter, score: 0.02)
                    add(.quarter, score: 1.6)
                    add(.dottedHalf, score: 0.9)
                } else {
                    add(.dottedQuarter, score: 0.18)
                    add(.dottedHalf, score: 0.28)
                }
            }

            if features.hasHollowHead && !features.hasFilledHead {
                add(.half, score: features.hasDot ? 1.55 : 0.05)
                add(.quarter, score: 0.75)
            }

            if !features.hasHollowHead,
               features.hasFilledHead || features.hasLowerHeadMass || features.hasStemAndKick {
                add(.quarter, score: features.hasDot ? 1.6 : 0.05)
                add(.half, score: 0.9)
            }
        }

        if features.hasHollowHead && !features.hasStem {
            add(.whole, score: 0.05)
            add(.half, score: 1.0)
        }

        if candidateScores.isEmpty {
            addFallbackCandidates(for: features, into: &candidateScores)
        }

        return candidateScores
            .map { RhythmCandidate(value: $0.key, score: $0.value) }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score < rhs.score
                }
                return lhs.value.wholeNoteLength < rhs.value.wholeNoteLength
            }
    }

    static func visualRestCandidates(
        for symbol: SymbolObservation,
        drawingFrame: CGRect
    ) -> [RhythmCandidate]? {
        let features = SymbolFeatures(symbol: symbol, drawingFrame: drawingFrame)
        guard !features.contentStrokes.isEmpty else {
            return nil
        }

        var candidateScores: [RhythmValue: Double] = [:]
        func add(_ value: RhythmValue, score: Double) {
            let clampedScore = max(0, score)
            if let existingScore = candidateScores[value],
               existingScore <= clampedScore {
                return
            }
            candidateScores[value] = clampedScore
        }

        if looksLikeSixteenthRest(features) {
            add(.sixteenthRest, score: 0.0)
            add(.eighthRest, score: 1.15)
            add(.quarterRest, score: 1.55)
        }

        if features.contentStrokes.count == 1,
           let stroke = features.contentStrokes.first,
           stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame),
           !stroke.looksFilledNoteHead {
            add(.eighthRest, score: 0.0)
            add(.quarterRest, score: 1.35)
        }

        if looksLikeEighthRest(features) {
            add(.eighthRest, score: 0.0)
            add(.quarterRest, score: 1.35)
        }

        let hasQuarterRestBody = features.contentStrokes.contains {
            $0.looksLikeQuarterRestBody(in: features.contentBounds)
        }
        let hasOneStrokeQuarterRestGesture = features.contentStrokes.count == 1
            && features.contentStrokes.contains {
                $0.looksLikeFlexibleOneStrokeQuarterRest(in: features.contentBounds)
            }
        let hasFullZigZagRestGesture = features.contentStrokes.count == 1
            && features.contentStrokes.contains { stroke in
                stroke.directionChangeCount >= 3
                    && stroke.bounds.height >= max(CGFloat(18), features.contentBounds.height * 0.72)
            }
        let isSevenLikeEighthRest = symbol.sevenLikeEighthRestComparisonScore(in: features.contentBounds) != nil
        if looksLikeQuarterRest(features),
           hasQuarterRestBody || hasOneStrokeQuarterRestGesture || hasFullZigZagRestGesture || !isSevenLikeEighthRest {
            add(.quarterRest, score: 0.0)
            add(.eighthRest, score: 1.35)
        }

        if looksLikeWholeRest(features) {
            add(.wholeRest, score: 0.05)
            add(.halfRest, score: 0.9)
        }

        if symbol.strokes.count >= 2,
           looksLikeHalfRest(features) {
            add(.halfRest, score: 0.05)
            add(.wholeRest, score: 1.15)
        }

        guard !candidateScores.isEmpty else {
            return nil
        }

        return candidateScores
            .map { RhythmCandidate(value: $0.key, score: $0.value) }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score < rhs.score
                }
                return lhs.value.wholeNoteLength < rhs.value.wholeNoteLength
            }
    }

    private static func beamedEighthCandidateGroups(
        for symbol: SymbolObservation,
        drawingFrame: CGRect
    ) -> [[RhythmCandidate]]? {
        let noteheadCount = symbol.beamedEighthNoteCount(drawingFrame: drawingFrame)
        guard noteheadCount >= 2 else {
            return nil
        }

        return (0..<noteheadCount).map { _ in
            [RhythmCandidate(value: .eighth, score: 0.01)]
        }
    }

    private static func addFallbackCandidates(
        for features: SymbolFeatures,
        into candidateScores: inout [RhythmValue: Double]
    ) {
        func add(_ value: RhythmValue, score: Double) {
            if let existingScore = candidateScores[value],
               existingScore <= score {
                return
            }
            candidateScores[value] = score
        }

        if features.hasNoNoteheadRestShape {
            add(.eighthRest, score: 0.0)
            add(.quarterRest, score: 1.35)
            return
        }

        if features.hasSingleStrokeFlagGesture {
            add(.eighth, score: 0.65)
            add(.quarter, score: 1.25)
        }

        if features.hasStem || features.height > features.width * 1.05 {
            add(.quarter, score: 1.2)
            add(.eighth, score: 1.35)
            add(.quarterRest, score: 1.45)
            add(.eighthRest, score: 1.55)
        }

        if features.width > features.height * 1.05 {
            add(.half, score: 1.25)
            add(.halfRest, score: 1.35)
            add(.whole, score: 1.55)
            add(.wholeRest, score: 1.65)
        }
    }

    private static func looksLikeRhythmSlash(_ symbol: SymbolObservation, drawingFrame: CGRect) -> Bool {
        guard symbol.strokes.count == 1,
              let stroke = symbol.strokes.first else {
            return false
        }
        guard !stroke.looksLikeQuarterRestBody(in: symbol.bounds),
              !stroke.looksLikeFlexibleOneStrokeQuarterRest(in: symbol.bounds),
              !stroke.looksLikeFlexibleOneStrokeSixteenthRest(in: drawingFrame),
              !stroke.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame) else {
            return false
        }

        return stroke.looksLikeRhythmicPlaceholderSlash(in: symbol.bounds)
    }

    private static func slashCandidateGroups(for symbol: SymbolObservation, drawingFrame: CGRect) -> [[RhythmCandidate]]? {
        guard !symbol.strokes.isEmpty,
              symbol.strokes.allSatisfy({
                  !$0.looksLikeQuarterRestBody(in: $0.bounds)
                      && !$0.looksLikeFlexibleOneStrokeQuarterRest(in: $0.bounds)
                      && !$0.looksLikeFlexibleOneStrokeSixteenthRest(in: drawingFrame)
                      && !$0.looksLikeFlexibleOneStrokeEighthRest(in: drawingFrame)
                      && $0.looksLikeRhythmicPlaceholderSlash(in: $0.bounds)
              }) else {
            return nil
        }

        return symbol.strokes.map { _ in
            [RhythmCandidate(value: .slash, score: 0.0)]
        }
    }

    private static func looksLikeQuarterRest(_ features: SymbolFeatures) -> Bool {
        guard features.contentStrokes.count <= 5,
              features.height > max(8, features.width * 0.55),
              !features.hasDefiniteLowerNotehead,
              !features.hasClearNoteGlyph else {
            return false
        }

        if features.contentStrokes.contains(where: { $0.looksLikeQuarterRestBody(in: features.contentBounds) }) {
            return true
        }

        if features.contentStrokes.count == 1,
           let stroke = features.contentStrokes.first,
           stroke.looksLikeFlexibleOneStrokeQuarterRest(in: features.contentBounds) {
            return true
        }

        let stackedNarrowGesture = features.contentStrokes.count >= 2
            && features.height > features.width * 0.9
            && features.contentStrokes.allSatisfy { !$0.looksClosed && !$0.looksFilledNoteHead }
            && features.contentStrokes.filter { $0.bounds.height >= features.height * 0.18 }.count >= 2
        if stackedNarrowGesture {
            return true
        }

        let angularSegments = features.contentStrokes.filter { stroke in
            stroke.looksLikeQuarterRestSegment(in: features.contentBounds)
        }
        return angularSegments.count >= 2
    }

    private static func looksLikeSixteenthRest(_ features: SymbolFeatures) -> Bool {
        guard features.contentStrokes.count <= 6,
              features.height > max(7, features.width * 0.72),
              !features.hasDefiniteLowerNotehead,
              !features.hasClearNoteGlyph else {
            return false
        }

        let symbol = SymbolObservation(strokes: features.contentStrokes)
        if symbol.sixteenthRestComparisonScore(in: features.drawingFrame) != nil {
            return true
        }

        if features.contentStrokes.count == 1,
           let stroke = features.contentStrokes.first,
           stroke.looksLikeFlexibleOneStrokeSixteenthRest(in: features.drawingFrame) {
            return true
        }

        return false
    }

    private static func looksLikeEighthRest(_ features: SymbolFeatures) -> Bool {
        guard features.contentStrokes.count <= 5,
              features.height > max(7, features.width * 0.72),
              !features.hasDefiniteLowerNotehead,
              !features.hasClearNoteGlyph else {
            return false
        }

        if features.hasNoNoteheadRestShape {
            return true
        }

        if features.contentStrokes.count == 1,
           let stroke = features.contentStrokes.first,
           stroke.looksLikeFlexibleOneStrokeEighthRest(in: features.drawingFrame) {
            return true
        }

        let upperDots = features.contentStrokes.filter {
            $0.looksLikeEighthRestDot(in: features.contentBounds)
        }
        guard !upperDots.isEmpty else {
            return false
        }

        return upperDots.contains { dot in
            features.contentStrokes.contains { stroke in
                stroke != dot && stroke.looksLikeEighthRestDescendingTail(
                    belowOrBeside: dot,
                    in: features.contentBounds
                )
            }
        }
    }

    private static func looksLikeWholeRest(_ features: SymbolFeatures) -> Bool {
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

    func looksLikeQuarterRestBody(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        let coversRestHeight = bounds.height >= referenceHeight * 0.55
        let narrowEnough = bounds.width <= max(referenceBounds.width * 1.05, bounds.height * 1.35)
        let spansBody = bounds.minY <= referenceBounds.minY + referenceHeight * 0.24
            && bounds.maxY >= referenceBounds.maxY - referenceHeight * 0.18
        let drawnDownward = endPoint.y >= startPoint.y + max(CGFloat(6), bounds.height * 0.18)
        let hasHandwrittenZigZag = directionChangeCount >= 2
            || (bounds.width <= bounds.height * 0.5 && pathLength >= bounds.height * 1.08)
        let restShaped = bounds.height > bounds.width * 0.72 || directionChangeCount >= 2
        let upperHookSuggestsEighthRest = hasHorizontalUpperHook && directionChangeCount <= 2

        return coversRestHeight
            && narrowEnough
            && spansBody
            && drawnDownward
            && hasHandwrittenZigZag
            && restShaped
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
        let coversRestHeight = bounds.height >= max(CGFloat(18), referenceHeight * 0.62)
        let narrowEnough = bounds.width <= max(CGFloat(18), bounds.height * 0.48)
        let drawnDownward = endPoint.y >= startPoint.y + max(CGFloat(6), bounds.height * 0.22)
        let hasRestMotion = directionChangeCount >= 2
            || horizontalTurnCount >= 2
            || (directionChangeCount >= 1 && pathLength >= diagonalSpan * 1.12)
        let moreThanStraightStroke = pathLength >= max(bounds.height * 1.02, diagonalSpan * 1.02)
            || horizontalTurnCount >= 2
        let upperHookSuggestsEighthRest = hasHorizontalUpperHook && directionChangeCount <= 2

        return coversRestHeight
            && narrowEnough
            && drawnDownward
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
        let compactHeight = bounds.height >= max(CGFloat(14), referenceHeight * 0.15)
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
        let compactHeight = bounds.height >= max(CGFloat(16), referenceHeight * 0.18)
            && bounds.height <= max(CGFloat(42), referenceHeight * 0.58)
        let narrowEnough = bounds.width <= max(CGFloat(24), bounds.height * 0.96)
        let drawnDownward = endPoint.y >= startPoint.y + max(CGFloat(6), bounds.height * 0.2)
        let hasTwoShortValueTurns = directionChangeCount >= 2
            || horizontalTurnCount >= 2
            || pathLength >= diagonalSpan * 1.24
        let hasTwoFlagLevels = hasTwoRestFlagLevels(in: bounds)
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
            point.y <= referenceBounds.minY + referenceHeight * 0.4
        }
        let middlePoints = points.filter { point in
            point.y >= referenceBounds.minY + referenceHeight * 0.28
                && point.y <= referenceBounds.minY + referenceHeight * 0.68
        }
        guard let upperBounds = upperPoints.nonEmptyBounds,
              let middleBounds = middlePoints.nonEmptyBounds else {
            return false
        }

        let upperHook = upperBounds.width >= max(CGFloat(3), referenceWidth * 0.16)
            || upperBounds.height >= max(CGFloat(3), referenceHeight * 0.08)
        let middleHook = middleBounds.width >= max(CGFloat(3), referenceWidth * 0.16)
            || middleBounds.height >= max(CGFloat(4), referenceHeight * 0.12)
        let separatedLevels = middleBounds.midY - upperBounds.midY >= max(CGFloat(3), referenceHeight * 0.12)
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

private struct VisualRhythmRecognizer {
    static func recognition(
        from strokes: [StrokeObservation],
        drawingFrame: CGRect
    ) -> VisualRhythmRecognition? {
        let orderedStrokes = strokes.sortedByVisualPosition()
        guard !orderedStrokes.isEmpty else {
            return nil
        }

        let sceneBounds = orderedStrokes.nonEmptyBounds ?? drawingFrame
        var usedStrokes = Set<StrokeObservation>()
        var events: [VisualRhythmEvent] = []

        func append(_ event: VisualRhythmEvent) {
            events.append(event)
            usedStrokes.formUnion(event.strokes)
        }

        for event in eighthRestEvents(
            from: orderedStrokes,
            usedStrokes: usedStrokes,
            sceneBounds: sceneBounds
        ) {
            append(event)
        }

        for event in slashEvents(
            from: orderedStrokes,
            usedStrokes: usedStrokes,
            sceneBounds: sceneBounds
        ) {
            append(event)
        }

        for event in beamedEighthEvents(
            from: orderedStrokes,
            usedStrokes: usedStrokes,
            sceneBounds: sceneBounds,
            drawingFrame: drawingFrame
        ) {
            append(event)
        }

        for event in noteEvents(
            from: orderedStrokes,
            usedStrokes: usedStrokes,
            sceneBounds: sceneBounds
        ) {
            append(event)
        }

        for event in restEvents(
            from: orderedStrokes,
            usedStrokes: usedStrokes,
            sceneBounds: sceneBounds,
            drawingFrame: drawingFrame
        ) {
            append(event)
        }

        guard !events.isEmpty else {
            return nil
        }

        let uncoveredStrokes = orderedStrokes.filter { stroke in
            !usedStrokes.contains(stroke)
                && !stroke.isIgnorableVisualNoise(in: sceneBounds)
        }

        let orderedEvents = events
            .sorted { lhs, rhs in
                if abs(lhs.xPosition - rhs.xPosition) > 0.5 {
                    return lhs.xPosition < rhs.xPosition
                }
                return lhs.yPosition < rhs.yPosition
            }
        return VisualRhythmRecognition(
            events: orderedEvents,
            uncoveredStrokes: uncoveredStrokes
        )
    }

    private static func beamedEighthEvents(
        from strokes: [StrokeObservation],
        usedStrokes: Set<StrokeObservation>,
        sceneBounds: CGRect,
        drawingFrame: CGRect
    ) -> [VisualRhythmEvent] {
        let availableStrokes = strokes.filter { !usedStrokes.contains($0) }
        let noteheads = noteheadClusters(from: availableStrokes, sceneBounds: sceneBounds)
        let stems = availableStrokes.filter { $0.looksLikeVisualStem(in: sceneBounds) }
        let beamSeeds = availableStrokes.filter { stroke in
            let connectedStemXs = stroke.connectedBeamStemXs(in: stroke.bounds)
            let frameNoteheadCount = noteheads.filter { head in
                connectedStemXs.contains { stemX in
                    abs(stemX - head.bounds.midX) <= max(CGFloat(12), drawingFrame.width * 0.04)
                }
            }.count
            let connectedFrameHasNoteheads = connectedStemXs.count >= 2 && frameNoteheadCount >= 2
            if !connectedFrameHasNoteheads {
                if let restCandidates = RhythmicNotationQuantizer.visualRestCandidates(
                    for: SymbolObservation(strokes: [stroke]),
                    drawingFrame: drawingFrame
                ),
                   restCandidates.first?.value == .quarterRest {
                    return false
                }
            }

            return stroke.looksLikeVisualBeamSeed(in: sceneBounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: sceneBounds,
                    drawingFrame: drawingFrame
                )
                || stroke.looksLikeFoldedBeamStemSeed(
                    over: stems,
                    in: sceneBounds,
                    drawingFrame: drawingFrame
                )
                || connectedFrameHasNoteheads
        }

        var events: [VisualRhythmEvent] = []
        var locallyUsedStrokes = Set<StrokeObservation>()
        for beam in beamSeeds.sortedByVisualPosition() where !locallyUsedStrokes.contains(beam) {
            let inferredStemXs = beam.connectedBeamStemXs(in: beam.bounds)
            let coveredStems = stems.filter { stem in
                guard !locallyUsedStrokes.contains(stem) else {
                    return false
                }

                if inferredStemXs.contains(where: { abs($0 - stem.bounds.midX) <= max(CGFloat(9), beam.bounds.width * 0.18) }) {
                    return true
                }

                let coveragePadding = max(CGFloat(8), drawingFrame.width * 0.025)
                let horizontallyCovered = beam.bounds.minX - coveragePadding <= stem.bounds.midX
                    && beam.bounds.maxX + coveragePadding >= stem.bounds.midX
                let verticallyConnected = stem.bounds.minY <= beam.bounds.maxY + max(CGFloat(10), sceneBounds.height * 0.16)
                    && stem.bounds.maxY >= beam.bounds.maxY
                return horizontallyCovered && verticallyConnected
            }

            let stemXs = (coveredStems.map(\.bounds.midX) + inferredStemXs)
                .clusteredXs(minimumSeparation: max(CGFloat(8), drawingFrame.width * 0.03))
            guard stemXs.count >= 2 else {
                continue
            }

            let coveredNoteheads = noteheads.filter { head in
                stemXs.contains { stemX in
                    abs(stemX - head.bounds.midX) <= max(CGFloat(12), drawingFrame.width * 0.04)
                }
            }
            let baseEventStrokeList = [beam]
                + coveredStems
                + coveredNoteheads.flatMap(\.strokes)
            let baseEventBounds = baseEventStrokeList.nonEmptyBounds ?? beam.bounds
            let touchUpStrokes = availableStrokes.filter { stroke in
                guard !locallyUsedStrokes.contains(stroke),
                      !baseEventStrokeList.contains(stroke),
                      stroke.isBeamedEventTouchUp(
                          near: baseEventBounds,
                          sceneBounds: sceneBounds,
                          drawingFrame: drawingFrame
                      ) else {
                    return false
                }

                return true
            }
            let eventStrokeList = baseEventStrokeList + touchUpStrokes
            let eventStrokes = Set(eventStrokeList)
            let eventBounds = eventStrokeList.nonEmptyBounds ?? beam.bounds
            let noteCount = max(stemXs.count, coveredNoteheads.count)
            guard noteCount >= 2 else {
                continue
            }
            let hasProtectedNoteheads = coveredNoteheads.count >= 2

            locallyUsedStrokes.formUnion(eventStrokes)
            events.append(
                VisualRhythmEvent(
                    xPosition: eventBounds.minX,
                    yPosition: eventBounds.midY,
                    candidateGroups: (0..<min(noteCount, 4)).map { _ in
                        [RhythmCandidate(value: .eighth, score: 0.0)]
                    },
                    strokes: eventStrokes,
                    isBeamedEighthEvent: hasProtectedNoteheads
                )
            )
        }

        return events
    }

    private static func eighthRestEvents(
        from strokes: [StrokeObservation],
        usedStrokes: Set<StrokeObservation>,
        sceneBounds: CGRect
    ) -> [VisualRhythmEvent] {
        let availableStrokes = strokes.filter { !usedStrokes.contains($0) }
        var events: [VisualRhythmEvent] = []
        var locallyUsedStrokes = Set<StrokeObservation>()

        for anchor in availableStrokes.sortedByVisualPosition() where !locallyUsedStrokes.contains(anchor) {
            let nearbyStrokes = availableStrokes
                .filter { stroke in
                    !locallyUsedStrokes.contains(stroke)
                        && stroke.isCloseToVisualSymbol(anchoredBy: anchor, in: sceneBounds)
                }
                .sortedByVisualPosition()
            let candidateSymbols = nearbyStrokes
                .subsets(containing: anchor, maximumCount: 4)
                .compactMap { strokes -> (symbol: SymbolObservation, score: CGFloat)? in
                    let symbol = SymbolObservation(strokes: strokes)
                    guard !symbol.strokes.allSatisfy({
                        !$0.looksLikeQuarterRestBody(in: $0.bounds)
                            && !$0.looksLikeFlexibleOneStrokeQuarterRest(in: $0.bounds)
                            && !$0.looksLikeFlexibleOneStrokeEighthRest(in: sceneBounds)
                            && $0.looksLikeRhythmicPlaceholderSlash(in: $0.bounds)
                            && $0.isIsolatedPlaceholderSlash(
                                among: availableStrokes,
                                sceneBounds: sceneBounds
                            )
                    }) else {
                        return nil
                    }
                    guard !symbol.hasAttachedLowerNotehead(among: availableStrokes, in: sceneBounds) else {
                        return nil
                    }
                    guard !symbol.isSingleVisualNoteheadWithAttachedStem(
                        among: availableStrokes,
                        in: sceneBounds
                    ) else {
                        return nil
                    }
                    if let restCandidates = RhythmicNotationQuantizer.visualRestCandidates(
                        for: symbol,
                        drawingFrame: sceneBounds
                    ),
                       restCandidates.first?.value == .quarterRest {
                        return nil
                    }
                    guard let score = symbol.eighthRestComparisonScore(in: sceneBounds) else {
                        return nil
                    }
                    return (symbol, score)
                }

            guard let bestSymbol = candidateSymbols.min(by: { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.001 {
                    return lhs.score < rhs.score
                }
                return lhs.symbol.bounds.width < rhs.symbol.bounds.width
            }) else {
                continue
            }

            let eventStrokes = Set(bestSymbol.symbol.strokes)
            let eventBounds = bestSymbol.symbol.bounds
            locallyUsedStrokes.formUnion(eventStrokes)
            events.append(
                VisualRhythmEvent(
                    xPosition: eventBounds.minX,
                    yPosition: eventBounds.midY,
                    candidateGroups: [[
                        RhythmCandidate(value: .eighthRest, score: 0.0),
                        RhythmCandidate(value: .quarterRest, score: 1.45)
                    ]],
                    strokes: eventStrokes,
                    isBeamedEighthEvent: false
                )
            )
        }

        return events
    }

    private static func restEvents(
        from strokes: [StrokeObservation],
        usedStrokes: Set<StrokeObservation>,
        sceneBounds: CGRect,
        drawingFrame: CGRect
    ) -> [VisualRhythmEvent] {
        let availableStrokes = strokes.filter { !usedStrokes.contains($0) }
        var events: [VisualRhythmEvent] = []
        var locallyUsedStrokes = Set<StrokeObservation>()

        for anchor in availableStrokes.sortedByVisualPosition() where !locallyUsedStrokes.contains(anchor) {
            let nearbyStrokes = availableStrokes
                .filter { stroke in
                    !locallyUsedStrokes.contains(stroke)
                        && stroke.isCloseToVisualSymbol(anchoredBy: anchor, in: sceneBounds)
                }
                .sortedByVisualPosition()
            let candidateSymbols = nearbyStrokes
                .subsets(containing: anchor, maximumCount: 5)
                .compactMap { strokes -> (symbol: SymbolObservation, candidates: [RhythmCandidate])? in
                    let symbol = SymbolObservation(strokes: strokes)
                    guard let candidates = RhythmicNotationQuantizer.visualRestCandidates(
                        for: symbol,
                        drawingFrame: drawingFrame
                    ) else {
                        return nil
                    }
                    return (symbol, candidates)
                }

            guard let bestSymbol = candidateSymbols.min(by: { lhs, rhs in
                let lhsScore = lhs.candidates.first?.score ?? .greatestFiniteMagnitude
                let rhsScore = rhs.candidates.first?.score ?? .greatestFiniteMagnitude
                if abs(lhsScore - rhsScore) > 0.001 {
                    return lhsScore < rhsScore
                }
                return lhs.symbol.bounds.width < rhs.symbol.bounds.width
            }) else {
                continue
            }

            let eventStrokes = Set(bestSymbol.symbol.strokes)
            let eventBounds = bestSymbol.symbol.bounds
            locallyUsedStrokes.formUnion(eventStrokes)
            events.append(
                VisualRhythmEvent(
                    xPosition: eventBounds.minX,
                    yPosition: eventBounds.midY,
                    candidateGroups: [bestSymbol.candidates],
                    strokes: eventStrokes,
                    isBeamedEighthEvent: false
                )
            )
        }

        return events
    }

    private static func noteEvents(
        from strokes: [StrokeObservation],
        usedStrokes: Set<StrokeObservation>,
        sceneBounds: CGRect
    ) -> [VisualRhythmEvent] {
        let availableStrokes = strokes.filter { !usedStrokes.contains($0) }
        let noteheads = noteheadClusters(from: availableStrokes, sceneBounds: sceneBounds)
        let stemCandidates = availableStrokes.filter { $0.looksLikeVisualStem(in: sceneBounds) }
        let dotCandidates = availableStrokes.filter { $0.looksLikeLooseDot(in: sceneBounds) }
        var events: [VisualRhythmEvent] = []
        var locallyUsedStrokes = Set<StrokeObservation>()

        for notehead in noteheads.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            guard notehead.strokes.allSatisfy({ !locallyUsedStrokes.contains($0) }) else {
                continue
            }

            let nearestStem = stemCandidates
                .filter { stem in
                    !locallyUsedStrokes.contains(stem)
                        && abs(stem.bounds.midX - notehead.bounds.midX) <= max(CGFloat(16), notehead.bounds.width * 2.5)
                        && stem.bounds.minY <= notehead.bounds.midY
                        && stem.bounds.maxY >= notehead.bounds.minY - max(CGFloat(4), sceneBounds.height * 0.06)
                }
                .min { lhs, rhs in
                    abs(lhs.bounds.midX - notehead.bounds.midX) < abs(rhs.bounds.midX - notehead.bounds.midX)
                }

            let provisionalBounds = ([notehead.bounds] + (nearestStem.map { [$0.bounds] } ?? []))
                .reduce(CGRect.null) { partialResult, bounds in
                    partialResult.union(bounds)
                }
            let augmentationDot = dotCandidates
                .filter { dot in
                    !locallyUsedStrokes.contains(dot)
                        && !notehead.strokes.contains(dot)
                        && dot.looksLikeAugmentationDot(toRightOf: provisionalBounds, headBounds: notehead.bounds)
                }
                .min { lhs, rhs in lhs.bounds.minX < rhs.bounds.minX }

            let flagStroke = nearestStem.flatMap { stem in
                availableStrokes
                    .filter { stroke in
                        !locallyUsedStrokes.contains(stroke)
                            && !notehead.strokes.contains(stroke)
                            && stroke != stem
                            && stroke != augmentationDot
                            && stroke.looksLikeVisualFlag(near: stem, in: sceneBounds)
                    }
                    .min { lhs, rhs in
                        abs(lhs.bounds.midX - stem.bounds.midX) < abs(rhs.bounds.midX - stem.bounds.midX)
                    }
            }

            guard let rhythmCandidates = candidates(
                for: notehead,
                stem: nearestStem,
                flag: flagStroke,
                dot: augmentationDot
            ) else {
                continue
            }

            let eventStrokeList = notehead.strokes
                + (nearestStem.map { [$0] } ?? [])
                + (flagStroke.map { [$0] } ?? [])
                + (augmentationDot.map { [$0] } ?? [])
            let eventStrokes = Set(eventStrokeList)
            let eventBounds = eventStrokeList.nonEmptyBounds ?? notehead.bounds

            locallyUsedStrokes.formUnion(eventStrokes)
            events.append(
                VisualRhythmEvent(
                    xPosition: eventBounds.minX,
                    yPosition: eventBounds.midY,
                    candidateGroups: [rhythmCandidates],
                    strokes: eventStrokes,
                    isBeamedEighthEvent: false
                )
            )
        }

        return events
    }

    private static func slashEvents(
        from strokes: [StrokeObservation],
        usedStrokes: Set<StrokeObservation>,
        sceneBounds: CGRect
    ) -> [VisualRhythmEvent] {
        strokes
            .filter { stroke in
                !usedStrokes.contains(stroke)
                    && !stroke.looksLikeQuarterRestBody(in: stroke.bounds)
                    && !stroke.looksLikeFlexibleOneStrokeQuarterRest(in: stroke.bounds)
                    && !stroke.looksLikeFlexibleOneStrokeEighthRest(in: sceneBounds)
                    && stroke.looksLikeRhythmicPlaceholderSlash(in: stroke.bounds)
                    && stroke.isIsolatedPlaceholderSlash(among: strokes, sceneBounds: sceneBounds)
            }
            .map { stroke in
                VisualRhythmEvent(
                    xPosition: stroke.bounds.minX,
                    yPosition: stroke.bounds.midY,
                    candidateGroups: [[RhythmCandidate(value: .slash, score: 0.0)]],
                    strokes: [stroke],
                    isBeamedEighthEvent: false
                )
            }
    }

    private static func noteheadClusters(
        from strokes: [StrokeObservation],
        sceneBounds: CGRect
    ) -> [VisualNotehead] {
        strokes
            .filter { $0.looksLikeVisualNotehead(in: sceneBounds) }
            .sortedByVisualPosition()
            .reduce(into: [[StrokeObservation]]()) { clusters, stroke in
                guard var previousCluster = clusters.popLast(),
                      let previousBounds = previousCluster.nonEmptyBounds else {
                    clusters.append([stroke])
                    return
                }

                let horizontalDistance = abs(stroke.bounds.midX - previousBounds.midX)
                let verticalDistance = abs(stroke.bounds.midY - previousBounds.midY)
                let belongsToSameHead = horizontalDistance <= max(CGFloat(10), previousBounds.width * 1.35)
                    && verticalDistance <= max(CGFloat(10), previousBounds.height * 1.4)

                if belongsToSameHead {
                    previousCluster.append(stroke)
                    clusters.append(previousCluster)
                } else {
                    clusters.append(previousCluster)
                    clusters.append([stroke])
                }
            }
            .map(VisualNotehead.init(strokes:))
    }

    private static func candidates(
        for notehead: VisualNotehead,
        stem: StrokeObservation?,
        flag: StrokeObservation?,
        dot: StrokeObservation?
    ) -> [RhythmCandidate]? {
        let hasDot = dot != nil
        if let stem {
            if hasDot {
                if notehead.isHollow {
                    return [
                        RhythmCandidate(value: .dottedHalf, score: 0.0),
                        RhythmCandidate(value: .half, score: 1.4),
                        RhythmCandidate(value: .dottedQuarter, score: 0.8)
                    ]
                }

                return [
                    RhythmCandidate(value: .dottedEighth, score: 0.0),
                    RhythmCandidate(value: .dottedQuarter, score: 0.0),
                    RhythmCandidate(value: .quarter, score: 1.5),
                    RhythmCandidate(value: .dottedHalf, score: 0.95)
                ]
            }

            if notehead.isHollow {
                return [
                    RhythmCandidate(value: .half, score: 0.0),
                    RhythmCandidate(value: .quarter, score: 0.9)
                ]
            }

            if flag != nil || stem.looksLikeSingleStrokeEighthNote {
                return [
                    RhythmCandidate(value: .eighth, score: 0.0),
                    RhythmCandidate(value: .quarter, score: 1.2)
                ]
            }

            return [
                RhythmCandidate(value: .quarter, score: 0.0),
                RhythmCandidate(value: .eighth, score: 1.15)
            ]
        }

        if notehead.isHollow {
            return [
                RhythmCandidate(value: .whole, score: 0.0),
                RhythmCandidate(value: .half, score: 1.0)
            ]
        }

        return nil
    }
}

private struct VisualRhythmRecognition {
    let events: [VisualRhythmEvent]
    let uncoveredStrokes: [StrokeObservation]

    var candidateGroups: [[RhythmCandidate]] {
        events.flatMap(\.candidateGroups)
    }

    var containsBeamedEighthEvent: Bool {
        events.contains(where: \.isBeamedEighthEvent)
    }
}

private struct VisualRhythmEvent: Hashable {
    let xPosition: CGFloat
    let yPosition: CGFloat
    let candidateGroups: [[RhythmCandidate]]
    let strokes: Set<StrokeObservation>
    let isBeamedEighthEvent: Bool
}

private struct VisualNotehead: Hashable {
    let strokes: [StrokeObservation]
    let bounds: CGRect
    let isFilled: Bool
    let isHollow: Bool

    init(strokes: [StrokeObservation]) {
        self.strokes = strokes
        self.bounds = strokes.nonEmptyBounds ?? .null
        self.isFilled = strokes.contains(where: \.looksFilledNoteHead)
        self.isHollow = strokes.contains(where: \.looksHollowNoteHead)
    }
}

extension StrokeObservation {
    var isNoteheadLikeMark: Bool {
        bounds.width >= 4
            && bounds.height >= 4
            && (looksFilledNoteHead || looksHollowNoteHead || looksClosed)
    }

    func looksLikeVisualNotehead(in sceneBounds: CGRect) -> Bool {
        let sceneHeight = max(CGFloat(1), sceneBounds.height)
        let largeEnough = bounds.width >= 4
            && bounds.height >= 4
        let lowerOrSubstantial = center.y >= sceneBounds.minY + sceneHeight * 0.32
            || bounds.height >= sceneHeight * 0.18
        let roundedHead = looksFilledNoteHead || looksHollowNoteHead

        return largeEnough
            && lowerOrSubstantial
            && roundedHead
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
            && !looksLikeVisualNotehead(in: sceneBounds)
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
        let referenceWidth = max(CGFloat(1), referenceBounds.width)
        let compactEnough = bounds.width <= max(CGFloat(10), referenceWidth * 0.34)
            && bounds.height <= max(CGFloat(10), referenceHeight * 0.34)
        let shortEnough = pathLength <= max(CGFloat(36), referenceHeight * 1.5)
        let dotLikeBody = pathLength <= 1
            || looksFilledNoteHead
            || isCompactMark(comparedTo: referenceBounds)

        return compactEnough
            && shortEnough
            && dotLikeBody
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
                    || other.looksLikeVisualNotehead(in: sceneBounds)
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
            || looksLikeVisualNotehead(in: sceneBounds)
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

        let singleStrokeDoubleFlag = strokes.contains { stroke in
            stroke.looksLikeFlexibleOneStrokeSixteenthRest(in: sceneBounds)
        }
        let twoFlagLevels = strokes.contains { stroke in
            stroke.hasTwoRestFlagLevels(in: bounds)
        } || hasTwoRestFlagLevels(in: sceneBounds)
        guard singleStrokeDoubleFlag || twoFlagLevels else {
            return nil
        }

        let baseScore = eighthRestComparisonScore(in: sceneBounds)
            ?? sevenLikeEighthRestComparisonScore(in: sceneBounds)
            ?? CGFloat(0.22)
        let secondFlagPenalty = singleStrokeDoubleFlag ? CGFloat(0) : CGFloat(0.08)
        return baseScore + secondFlagPenalty
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

            return stroke.looksLikeVisualNotehead(in: sceneBounds)
                && stroke.center.y >= lowerBandY
                && stroke.bounds.midX >= bounds.minX - leftTolerance
                && stroke.bounds.midX <= bounds.maxX + rightTolerance
                && stroke.bounds.minX <= bounds.maxX + rightTolerance
        }
    }

    func isSingleVisualNoteheadWithAttachedStem(
        among strokes: [StrokeObservation],
        in sceneBounds: CGRect
    ) -> Bool {
        guard self.strokes.count == 1,
              let notehead = self.strokes.first,
              notehead.looksLikeVisualNotehead(in: sceneBounds) else {
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
            let compactWithinSymbol = stroke.bounds.height <= max(CGFloat(16), bounds.height * 0.45)
                && stroke.bounds.width <= max(CGFloat(18), bounds.width * 0.75)
            return compactWithinSymbol
                && stroke.center.y >= lowerBandY
                && stroke.looksLikeVisualNotehead(in: sceneBounds)
        }
    }

    func containsNoteheadSizedMass(in referenceBounds: CGRect) -> Bool {
        let referenceHeight = max(CGFloat(1), referenceBounds.height)
        return strokes.contains { stroke in
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

            let movableDots = resolvedGroups[index].filter { stroke in
                let dotLike = stroke.isDotLike(in: currentBounds)
                    && stroke.bounds.width <= dotSizeLimit * 1.2
                    && stroke.bounds.height <= dotSizeLimit * 1.2
                let nearNextTail = stroke.bounds.maxX >= nextBounds.minX - dotSizeLimit
                    && stroke.bounds.minX <= nextBounds.midX + dotSizeLimit
                let aboveTail = stroke.center.y < nextBounds.midY
                let trailingCurrentDot = stroke.bounds.minX >= currentBounds.midX

                return dotLike && nearNextTail && aboveTail && trailingCurrentDot
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

    func mergingLooseDots(drawingFrame: CGRect) -> [[StrokeObservation]] {
        var mergedGroups: [[StrokeObservation]] = []
        let dotSizeLimit = Swift.max(CGFloat(5), Swift.min(CGFloat(9), drawingFrame.height * 0.1))
        let mergeGapLimit = Swift.max(CGFloat(36), drawingFrame.width * 0.17)
        let verticalLimit = Swift.max(CGFloat(24), drawingFrame.height * 0.5)

        for group in self {
            guard let groupBounds = group.nonEmptyBounds else {
                continue
            }

            let isLooseDotGroup = group.count <= 2
                && groupBounds.width <= dotSizeLimit
                && groupBounds.height <= dotSizeLimit

            if isLooseDotGroup,
               var previousGroup = mergedGroups.popLast(),
               let previousBounds = previousGroup.nonEmptyBounds {
                let horizontalGap = groupBounds.minX - previousBounds.maxX
                let verticalDistance = abs(groupBounds.midY - previousBounds.midY)
                let shouldMergeAsDottedRhythm = horizontalGap >= -dotSizeLimit
                    && horizontalGap <= mergeGapLimit
                    && verticalDistance <= verticalLimit
                    && groupBounds.midX >= previousBounds.midX

                if shouldMergeAsDottedRhythm {
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
                    && !stroke.looksLikeVisualNotehead(in: groupBounds)
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
        let strokeIsHead = stroke.looksLikeVisualNotehead(in: groupBounds.union(stroke.bounds))

        let attachesStemToLooseHead = !groupFeatures.hasStem
            && strokeIsStem
            && contains { $0.looksLikeVisualNotehead(in: groupBounds) }
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
                    && !stroke.looksLikeVisualNotehead(in: localContentBounds)
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
        }
    }

    var hasFilledHead: Bool {
        headStrokes.contains { stroke in
            stroke.looksFilledNoteHead
                && stroke.bounds.width >= max(4, width * 0.14)
                && stroke.bounds.height >= max(4, height * 0.14)
                && stroke.center.y >= contentBounds.midY - height * 0.2
        }
    }

    var hasLowerHeadMass: Bool {
        headStrokes.contains { stroke in
            stroke.center.y >= contentBounds.midY
                && stroke.bounds.width >= max(4, width * 0.12)
                && stroke.bounds.height >= max(4, height * 0.12)
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
        if let restCandidate = RhythmicNotationQuantizer.visualRestCandidates(
            for: SymbolObservation(strokes: self),
            drawingFrame: drawingFrame
        )?.first,
           restCandidate.value == .eighthRest,
           restCandidate.score <= 0.35 {
            return true
        }

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
