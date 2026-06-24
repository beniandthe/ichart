#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit

extension RhythmicNotationQuantizer {
    static func v4SupportedTemplateValuesForTesting() -> Set<RhythmValue> {
        RhythmVisualCompendium.supportedValues
    }

    static func v4SymbolCropsForTesting(
        drawing: PKDrawing,
        drawingFrame: CGRect
    ) -> [RhythmSymbolCrop] {
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations(from: drawing),
            drawingFrame: drawingFrame
        )
        return rasterTemplateSymbolCrops(from: input)
    }

    static func v4TemplateValuesForTesting(
        drawing: PKDrawing,
        drawingFrame: CGRect
    ) -> [[RhythmValue]] {
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations(from: drawing),
            drawingFrame: drawingFrame
        )
        return rasterTemplateSymbolCrops(from: input).map { crop in
            rasterTemplateMatches(for: crop, input: input).flatMap(\.values)
        }
    }

    static func v4TemplateMatchesForTesting(
        drawing: PKDrawing,
        drawingFrame: CGRect
    ) -> [[RhythmTemplateMatch]] {
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations(from: drawing),
            drawingFrame: drawingFrame
        )
        return rasterTemplateSymbolCrops(from: input).map { crop in
            rasterTemplateMatches(for: crop, input: input)
        }
    }

    static func v4RenderComparisonForTesting(
        values: [RhythmValue],
        observedXPositions: [CGFloat],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRenderComparison {
        RhythmRenderComparison.evaluate(
            values: values,
            observedXPositions: observedXPositions,
            meter: meter,
            drawingFrame: drawingFrame
        )
    }

    static func v4UnderfilledExactFitPromotionDecisionForTesting(
        candidateScores: [[RhythmValue: Double]],
        observedXPositions: [CGFloat],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision? {
        guard candidateScores.count == observedXPositions.count,
              !candidateScores.isEmpty else {
            return nil
        }

        let crops = observedXPositions.enumerated().map { index, xPosition in
            RhythmSymbolCrop(
                index: index,
                strokeIndices: [index],
                bounds: CGRect(x: xPosition - 6, y: drawingFrame.midY - 12, width: 12, height: 24),
                normalizedBounds: .zero,
                rasterCells: [],
                strokes: []
            )
        }
        let candidateGroups = candidateScores.map { scoresByValue in
            scoresByValue
                .map { value, score in
                    RhythmCandidate(value: value, score: score)
                }
                .sorted { lhs, rhs in
                    if abs(lhs.score - rhs.score) > 0.0001 {
                        return lhs.score < rhs.score
                    }
                    return lhs.value.rawValue < rhs.value.rawValue
                }
        }
        let matchesByCrop = zip(crops, candidateGroups).map { crop, candidates in
            candidates.map { candidate in
                RhythmTemplateMatch(
                    values: [candidate.value],
                    score: candidate.score,
                    templateName: "test-\(candidate.value.rawValue)",
                    cropBounds: crop.bounds,
                    canDriveExactFit: candidate.canDriveExactFit,
                    canExtendAutoApplyStability: candidate.canExtendAutoApplyStability
                )
            }
        }
        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        guard naturalPath.units < rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
              let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter),
              exactPath.values != naturalPath.values,
              RhythmicNotationCompendium.accepts(exactPath.values, in: meter),
              rasterTemplateCanPromoteUnderfilledExactPath(
                    exactPath,
                    over: naturalPath,
                    candidateGroups: candidateGroups,
                    crops: crops,
                    matchesByCrop: matchesByCrop,
                    meter: meter,
                    drawingFrame: drawingFrame
              ) else {
            return .keepWriting(
                .underfilled,
                RhythmPhraseHypothesis(
                    source: .rasterTemplate,
                    primitives: [],
                    symbols: [],
                    uncoveredStrokeIndices: [],
                    naturalValues: naturalPath.values,
                    naturalUnits: naturalPath.units,
                    targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
                    passesCompendium: RhythmicNotationCompendium.accepts(naturalPath.values, in: meter)
                )
            )
        }

        let proposal = measureProposal(
            from: candidateGroups,
            exactPath: exactPath,
            meter: meter,
            includeExtendedStability: true
        )
        let symbols = zip(crops, candidateGroups).enumerated().map { index, pair in
            let (crop, candidates) = pair
            return RhythmSymbolHypothesis(
                coveredStrokeIndices: Set(crop.strokeIndices),
                bounds: crop.bounds,
                candidateValues: candidates.map(\.value),
                selectedValue: exactPath.values.indices.contains(index) ? exactPath.values[index] : nil
            )
        }
        let phrase = RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: [],
            symbols: symbols,
            uncoveredStrokeIndices: [],
            naturalValues: exactPath.values,
            naturalUnits: exactPath.units,
            targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
            passesCompendium: RhythmicNotationCompendium.accepts(exactPath.values, in: meter)
        )
        return .commit(proposal, phrase)
    }

    static func v4GridFirstDecisionForTesting(
        drawing: PKDrawing,
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRecognitionDecision? {
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations(from: drawing),
            drawingFrame: drawingFrame
        )
        let crops = rasterTemplateSymbolCrops(from: input)
        let matchesByCrop = crops.map { crop in
            rasterTemplateMatches(for: crop, input: input)
        }
        let naturalPath = bestNaturalPath(
            from: rasterTemplateCandidateGroups(from: matchesByCrop),
            meter: meter
        )
        return rasterTemplateGridFirstRecognitionDecision(
            input: input,
            crops: crops,
            matchesByCrop: matchesByCrop,
            naturalPath: naturalPath,
            meter: meter,
            drawingFrame: drawingFrame,
            includeExtendedStability: true
        )
    }

    static func rasterTemplateRecognitionDecision(
        strokeObservations: [StrokeObservation],
        meter: Meter,
        drawingFrame: CGRect,
        includeExtendedStability: Bool
    ) -> RhythmRecognitionDecision? {
        let input = rasterTemplateInput(
            strokeObservations: strokeObservations,
            drawingFrame: drawingFrame
        )
        let crops = rasterTemplateSymbolCrops(from: input)
        guard !crops.isEmpty else {
            return .keepWriting(.unsupported, nil)
        }

        let matchesByCrop = crops.map { crop in
            rasterTemplateMatches(for: crop, input: input)
        }
        let unsupportedCrops = zip(crops, matchesByCrop)
            .compactMap { crop, matches in
                matches.isEmpty ? crop : nil
            }
        let candidateGroups = rasterTemplateCandidateGroups(from: matchesByCrop)
        guard !candidateGroups.isEmpty else {
            return nil
        }
        let naturalPath = bestNaturalPath(from: candidateGroups, meter: meter)
        let phrase = rasterTemplatePhraseHypothesis(
            input: input,
            crops: crops,
            matchesByCrop: matchesByCrop,
            unsupportedCrops: unsupportedCrops,
            candidateGroups: candidateGroups,
            naturalPath: naturalPath,
            meter: meter
        )

        if !unsupportedCrops.isEmpty {
            return .keepWriting(.unsupported, phrase)
        }
        let hasBeamedTemplate = matchesByCrop.contains { matches in
            (matches.first?.values.count ?? 0) > 1
        }
        if rasterTemplateHasUnbeamedSameBeatEighthRun(
            in: naturalPath,
            crops: crops,
            matchesByCrop: matchesByCrop,
            input: input,
            meter: meter
        ) {
            let proposal = RhythmicNotationMeasureProposal(
                values: naturalPath.values,
                safety: .manualReview,
                isNaturalExactFit: phrase.isNaturalExactFit
            )
            return .needsReview(.ambiguousPhrase, phrase, proposal)
        }

        if phrase.isNaturalExactFit {
            let renderComparison = rasterTemplateRenderComparison(
                values: naturalPath.values,
                crops: crops,
                matchesByCrop: matchesByCrop,
                meter: meter,
                drawingFrame: drawingFrame
            )
            guard renderComparison.aligned || hasBeamedTemplate else {
                let proposal = RhythmicNotationMeasureProposal(
                    values: naturalPath.values,
                    safety: .manualReview,
                    isNaturalExactFit: true
                )
                return .needsReview(.ambiguousPhrase, phrase, proposal)
            }

            let measuredProposal = measureProposal(
                from: candidateGroups,
                exactPath: naturalPath,
                meter: meter,
                includeExtendedStability: includeExtendedStability
            )
            var proposal = rasterTemplateAdjustedProposal(
                measuredProposal,
                matchesByCrop: matchesByCrop
            )
            if proposal.safety == .manualReview,
               rasterTemplateCanPromoteDenseExactPhrase(phrase) {
                proposal = RhythmicNotationMeasureProposal(
                    values: proposal.values,
                    safety: .autoApply,
                    isNaturalExactFit: proposal.isNaturalExactFit
                )
            }
            if phraseHasTightMixedRestNoteCluster(phrase, drawingFrame: drawingFrame),
               !rasterTemplateCanPromoteDenseExactPhrase(phrase) {
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

        if let gridFirstDecision = rasterTemplateGridFirstRecognitionDecision(
            input: input,
            crops: crops,
            matchesByCrop: matchesByCrop,
            naturalPath: naturalPath,
            meter: meter,
            drawingFrame: drawingFrame,
            includeExtendedStability: includeExtendedStability
        ) {
            return gridFirstDecision
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        if naturalPath.units < targetUnits {
            if let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter),
               exactPath.values != naturalPath.values,
               RhythmicNotationCompendium.accepts(exactPath.values, in: meter),
               rasterTemplateCanPromoteUnderfilledExactPath(
                    exactPath,
                    over: naturalPath,
                    candidateGroups: candidateGroups,
                    crops: crops,
                    matchesByCrop: matchesByCrop,
                    meter: meter,
                    drawingFrame: drawingFrame
               ) {
                let exactPhrase = rasterTemplatePhraseHypothesis(
                    input: input,
                    crops: crops,
                    matchesByCrop: matchesByCrop,
                    unsupportedCrops: unsupportedCrops,
                    candidateGroups: candidateGroups,
                    naturalPath: exactPath,
                    meter: meter
                )
                let measuredProposal = measureProposal(
                    from: candidateGroups,
                    exactPath: exactPath,
                    meter: meter,
                    includeExtendedStability: includeExtendedStability
                )
                let proposal = RhythmicNotationMeasureProposal(
                    values: exactPath.values,
                    safety: measuredProposal.safety,
                    isNaturalExactFit: true
                )
                if proposal.safety == .manualReview {
                    let reviewReason = manualReviewReason(
                        for: exactPath,
                        candidateGroups: candidateGroups,
                        meter: meter
                    ) ?? .manualReview
                    return .needsReview(reviewReason, exactPhrase, proposal)
                }
                return .commit(proposal, exactPhrase)
            }
            return .keepWriting(.underfilled, phrase)
        }

        if naturalPath.units > targetUnits {
            let overflowUnits = naturalPath.units - targetUnits
            if hasBeamedTemplate && overflowUnits == 1 {
                return nil
            }
            if let exactPath = bestReviewOnlyExactPath(from: candidateGroups, targetUnits: targetUnits, meter: meter),
               RhythmicNotationCompendium.accepts(exactPath.values, in: meter),
               rasterTemplateCanPromoteRestAnchoredOverflowExactPath(
                    exactPath,
                    over: naturalPath,
                    candidateGroups: candidateGroups,
                    crops: crops,
                    matchesByCrop: matchesByCrop,
                    meter: meter,
                    drawingFrame: drawingFrame
               ) {
                let exactPhrase = rasterTemplatePhraseHypothesis(
                    input: input,
                    crops: crops,
                    matchesByCrop: matchesByCrop,
                    unsupportedCrops: unsupportedCrops,
                    candidateGroups: candidateGroups,
                    naturalPath: exactPath,
                    meter: meter
                )
                let proposal = RhythmicNotationMeasureProposal(
                    values: exactPath.values,
                    safety: .extendedStability,
                    isNaturalExactFit: true
                )
                return .commit(proposal, exactPhrase)
            }
            let exactPath = overflowUnits == 1
                ? bestReviewOnlyExactPath(from: candidateGroups, targetUnits: targetUnits, meter: meter)
                : bestMeasureAlignedPath(from: candidateGroups, meter: meter)
            if let exactPath,
               RhythmicNotationCompendium.accepts(exactPath.values, in: meter) {
                let proposal = RhythmicNotationMeasureProposal(
                    values: exactPath.values,
                    safety: .manualReview,
                    isNaturalExactFit: false
                )
                return .needsReview(.nonNaturalExactFit, phrase, proposal)
            }

            return .keepWriting(.overflow, phrase)
        }

        if let exactPath = bestMeasureAlignedPath(from: candidateGroups, meter: meter),
           exactPath.values != naturalPath.values,
           RhythmicNotationCompendium.accepts(exactPath.values, in: meter) {
            let proposal = RhythmicNotationMeasureProposal(
                values: exactPath.values,
                safety: .manualReview,
                isNaturalExactFit: false
            )
            return .needsReview(.nonNaturalExactFit, phrase, proposal)
        }

        return .keepWriting(.unsupported, phrase)
    }

    static func rasterTemplateInput(
        strokeObservations: [StrokeObservation],
        drawingFrame: CGRect
    ) -> RhythmInkRasterInput {
        let orderedStrokes = strokeObservations.sortedByVisualPosition()
        let strokes = orderedStrokes.filter { stroke in
            !stroke.isIgnorableRasterTemplateNoise(
                among: orderedStrokes,
                drawingFrame: drawingFrame
            )
        }
        return RhythmInkRasterInput(
            strokes: strokes,
            drawingFrame: drawingFrame
        )
    }

    private static func bestReviewOnlyExactPath(
        from candidateGroups: [[RhythmCandidate]],
        targetUnits: Int,
        meter: Meter
    ) -> CandidatePath? {
        var states: [Int: CandidatePath] = [
            0: CandidatePath(values: [], score: 0, units: 0)
        ]

        for candidates in candidateGroups {
            var nextStates: [Int: CandidatePath] = [:]
            for state in states.values {
                for candidate in candidates {
                    guard candidate.isConfidentEnoughForMeasureFit || candidate.canExtendAutoApplyStability else {
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
                    if let existingPath = nextStates[nextUnits],
                       existingPath.score <= nextPath.score {
                        continue
                    }
                    nextStates[nextUnits] = nextPath
                }
            }

            states = nextStates
        }

        return states[targetUnits]
    }

    static func rasterTemplateSymbolCrops(
        from input: RhythmInkRasterInput
    ) -> [RhythmSymbolCrop] {
        let groupedSymbols = groupedSymbols(
            from: input.strokes,
            drawingFrame: input.drawingFrame
        )
        let indexByStroke = Dictionary(
            uniqueKeysWithValues: input.strokes.enumerated().map { index, stroke in
                (stroke, index)
            }
        )

        return groupedSymbols.enumerated().compactMap { index, symbol in
            let strokeIndices = symbol.strokes.compactMap { indexByStroke[$0] }.sorted()
            guard !strokeIndices.isEmpty,
                  !symbol.bounds.isNull,
                  !symbol.bounds.isEmpty else {
                return nil
            }
            return RhythmSymbolCrop(
                index: index,
                strokeIndices: strokeIndices,
                bounds: symbol.bounds,
                normalizedBounds: input.normalizedBounds(for: symbol.bounds),
                rasterCells: RhythmInkRasterInput.rasterCells(
                    for: symbol.strokes.flatMap(\.points),
                    in: symbol.bounds
                ),
                strokes: symbol.strokes
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.bounds.minX - rhs.bounds.minX) > 0.5 {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.bounds.midY < rhs.bounds.midY
        }
    }

    static func rasterTemplateVisualNoteAnchors(
        from input: RhythmInkRasterInput
    ) -> [RhythmVisualNoteAnchor] {
        let crops = rasterTemplateSymbolCrops(from: input)
        let matchesByCrop = crops.map { crop in
            rasterTemplateMatches(for: crop, input: input)
        }

        return zip(crops, matchesByCrop).flatMap { crop, matches -> [RhythmVisualNoteAnchor] in
            let bestMatch = matches.first
            let valueCount = bestMatch?.values.allSatisfy(\.supportsPitchedLeadSheetNote) == true
                ? bestMatch?.values.count ?? 1
                : 1
            let hasNoteheadAnchor = crop.strokes.contains { $0.looksLikeVisualNotehead(in: crop.bounds) }
            guard bestMatch?.values.allSatisfy(\.supportsPitchedLeadSheetNote) == true || hasNoteheadAnchor else {
                return []
            }

            let centers = rasterTemplateVisualNoteAnchorCenters(
                for: crop,
                valueCount: valueCount,
                drawingFrame: input.drawingFrame
            )
            return centers.enumerated().map { offset, center in
                RhythmVisualNoteAnchor(
                    index: crop.index + offset,
                    center: center,
                    bounds: crop.bounds,
                    normalizedBounds: crop.normalizedBounds
                )
            }
        }
        .sorted { lhs, rhs in
            if abs(lhs.center.x - rhs.center.x) > 0.5 {
                return lhs.center.x < rhs.center.x
            }
            return lhs.center.y < rhs.center.y
        }
        .enumerated()
        .map { index, anchor in
            RhythmVisualNoteAnchor(
                index: index,
                center: anchor.center,
                bounds: anchor.bounds,
                normalizedBounds: anchor.normalizedBounds
            )
        }
    }

    static func rasterTemplateMatches(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> [RhythmTemplateMatch] {
        let symbol = SymbolObservation(strokes: crop.strokes)
        let features = SymbolFeatures(symbol: symbol, drawingFrame: input.drawingFrame)
        var matches: [RhythmTemplateMatch] = []

        func add(
            _ values: [RhythmValue],
            score: Double,
            template: String,
            canDriveExactFit: Bool = true,
            canExtendAutoApplyStability: Bool = false
        ) {
            guard !values.isEmpty,
                  values.allSatisfy(RhythmVisualCompendium.supportedValues.contains),
                  values.allSatisfy({
                      rasterTemplateValueHasRequiredEvidence(
                          $0,
                          crop: crop,
                          features: features,
                          templateName: template
                      )
                  }) else {
                return
            }
            let clampedScore = max(0, score)
            if let existingIndex = matches.firstIndex(where: { $0.values == values }) {
                if matches[existingIndex].score <= clampedScore {
                    return
                }
                matches[existingIndex] = RhythmTemplateMatch(
                    values: values,
                    score: clampedScore,
                    templateName: template,
                    cropBounds: crop.bounds,
                    canDriveExactFit: canDriveExactFit,
                    canExtendAutoApplyStability: canExtendAutoApplyStability
                )
                return
            }
            matches.append(
                RhythmTemplateMatch(
                    values: values,
                    score: clampedScore,
                    templateName: template,
                    cropBounds: crop.bounds,
                    canDriveExactFit: canDriveExactFit,
                    canExtendAutoApplyStability: canExtendAutoApplyStability
                )
            )
        }

        let beamedCount = rasterTemplateBeamedEighthCount(for: crop, input: input)
        if beamedCount >= 2 {
            let hasBeamedEighthEvidence = rasterTemplateHasBeamedEighthEvidence(
                for: crop,
                input: input
            )
            if let beamedSixteenthRun = rasterTemplateBeamedSixteenthRunValues(
                for: crop,
                input: input
            ) {
                add(beamedSixteenthRun, score: 0.0, template: "beamed-sixteenth-run")
                add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.65, template: "beamed-eighth-run")
            } else if let beamedMixedSixteenthRun = rasterTemplateBeamedMixedSixteenthRunValues(
                for: crop,
                input: input
            ) {
                add(beamedMixedSixteenthRun, score: 0.0, template: "beamed-sixteenth-mixed-run")
                add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.6, template: "beamed-eighth-run")
            } else if let beamedSixteenthPair = rasterTemplateBeamedSixteenthPairValues(
                for: crop,
                beamedCount: beamedCount,
                input: input
            ) {
                add(beamedSixteenthPair, score: 0.0, template: "beamed-sixteenth-pair")
                add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.55, template: "beamed-eighth-run")
            } else if let leadingRestValues = rasterTemplateBeamedEighthValuesWithLeadingRest(
                for: crop,
                beamedCount: beamedCount,
                input: input
            ) {
                add(leadingRestValues, score: 0.0, template: "beamed-eighth-run-leading-rest")
                add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.65, template: "beamed-eighth-run")
            } else if let terminalRestValues = rasterTemplateBeamedEighthValuesWithTerminalRest(
                for: crop,
                beamedCount: beamedCount,
                input: input
            ) {
                add(terminalRestValues, score: 0.0, template: "beamed-eighth-run-terminal-rest")
                add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.55, template: "beamed-eighth-run")
            } else {
                add(
                    Array(repeating: .eighth, count: min(beamedCount, 4)),
                    score: hasBeamedEighthEvidence ? 0.0 : 0.35,
                    template: "beamed-eighth-run"
                )
            }
        }

        if let slashValues = rasterTemplatePlaceholderSlashValues(for: crop, input: input) {
            add(slashValues, score: 0.0, template: "placeholder-slash")
            return matches.sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score < rhs.score
                }
                if lhs.values.count != rhs.values.count {
                    return lhs.values.count > rhs.values.count
                }
                return lhs.values.map(\.rawValue).lexicographicallyPrecedes(rhs.values.map(\.rawValue))
            }
        }

        if rasterCellsMatchForwardSlash(crop.rasterCells) {
            add([.slash], score: 0.0, template: "forward-slash")
        }

        if crop.index == 0,
           crop.strokes.looksLikeContextualLeadingEighthRest(drawingFrame: input.drawingFrame) {
            add([.eighthRest], score: 0.0, template: "rest-eighth-contextual-leading")
        }
        if let restCandidates = visualRestCandidates(for: symbol, drawingFrame: input.drawingFrame) {
            for candidate in restCandidates {
                add([candidate.value], score: candidate.score, template: "rest-\(candidate.value.rawValue)")
            }
        }
        let hasSixteenthRestMatch = symbol.sixteenthRestComparisonScore(in: input.sceneBounds) != nil
        let hasStrongNonEighthRestMatch = matches.contains { match in
            guard match.score <= 0.2,
                  match.values.count == 1,
                  let value = match.values.first else {
                return false
            }
            return value.isRest && value != .eighthRest
        } || hasSixteenthRestMatch
        let hasLaterInk = input.strokes.contains { stroke in
            stroke.bounds.minX > crop.bounds.maxX + max(CGFloat(2), input.drawingFrame.width * 0.006)
        }
        let suppressFilledShorthandEighthRestVote = crop.index > 0
            && hasLaterInk
            && crop.strokes.count == 1
            && crop.strokes.contains { $0.looksFilledNoteHead && !$0.looksHollowNoteHead }
        let hasEighthRestMatch = !suppressFilledShorthandEighthRestVote
            && (symbol.eighthRestComparisonScore(in: input.sceneBounds) != nil
            || symbol.sevenLikeEighthRestComparisonScore(in: input.sceneBounds) != nil
            )
        if hasSixteenthRestMatch {
            add([.sixteenthRest], score: 0.0, template: "rest-sixteenth-raster")
        }
        if hasEighthRestMatch && !hasStrongNonEighthRestMatch {
            add([.eighthRest], score: 0.0, template: "rest-eighth-raster")
        }
        let hasStrongRestMatch = matches.contains { match in
            match.values.allSatisfy(\.isRest) && match.score <= 0.2
        }
        if hasStrongRestMatch {
            return matches.filter { match in
                match.values.allSatisfy(\.isRest)
            }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score < rhs.score
                }
                return lhs.values.map(\.rawValue).lexicographicallyPrecedes(rhs.values.map(\.rawValue))
            }
        }

        for candidate in classifyCandidates(symbol, drawingFrame: input.drawingFrame) {
            guard candidate.score <= 0.85 else {
                continue
            }
            if (candidate.value == .dottedQuarter || candidate.value == .dottedHalf),
               features.hasStem,
               features.hasFlag || cropHasUpperFlagMass(crop, features: features) {
                continue
            }
            if featuresShouldRejectClassifierCandidate(
                candidate.value,
                for: symbol,
                drawingFrame: input.drawingFrame
            ) {
                continue
            }
            add([candidate.value], score: candidate.score + rasterTemplateAdjustment(for: candidate.value, crop: crop), template: "glyph-\(candidate.value.rawValue)")
        }

        let hasStemmedNoteRaster = rasterCellsMatchStemmedNote(crop.rasterCells)
            && cropHasLowerHeadMass(crop)
        let hasUpperHeadMass = cropHasUpperHeadMass(crop)
        let hasHollowInkHead = crop.strokes.contains { stroke in
            stroke.looksHollowNoteHead
        }
        let hasFilledInkHead = crop.strokes.contains { stroke in
            stroke.looksFilledNoteHead && !stroke.looksHollowNoteHead
        }
        if features.hasStem,
           features.hasDot,
           !features.hasFlag,
           (features.hasHollowHead || hasHollowInkHead),
           !hasFilledInkHead {
            add([.dottedHalf], score: 0.05, template: "dotted-hollow-stem")
        }
        if features.hasStem,
           features.hasDot,
           !features.hasFlag,
           !features.hasHollowHead,
           !hasHollowInkHead,
           (features.hasFilledHead || features.hasLowerHeadMass || features.hasStemAndKick || hasStemmedNoteRaster) {
            add([.dottedQuarter], score: 0.05, template: "dotted-filled-stem")
        }
        if features.hasStem,
           !features.hasHollowHead,
           !hasHollowInkHead,
           (features.hasFilledHead || hasFilledInkHead || hasUpperHeadMass || features.hasLowerHeadMass || features.hasStemAndKick || hasStemmedNoteRaster) {
            add([.quarter], score: 0.08, template: "filled-stem")
        }
        let hasDoubleFlagEvidence = rasterTemplateHasDoubleFlagEvidence(crop, features: features)
        if features.hasStem,
           hasDoubleFlagEvidence {
            add([.sixteenth], score: 0.0, template: "double-flagged-stem")
        }
        if features.hasStem,
           !hasDoubleFlagEvidence,
           (features.hasFlag || cropHasUpperFlagMass(crop, features: features)) {
            add([.eighth], score: 0.05, template: "flagged-stem")
        }
        if features.hasStem,
           (features.hasHollowHead || hasHollowInkHead),
           !hasFilledInkHead {
            add([.half], score: 0.08, template: "hollow-stem")
        }
        if !features.hasStem,
           cropLooksLikeWholeNoteCircle(crop, drawingFrame: input.drawingFrame) {
            add([.whole], score: 0.0, template: "whole-note-circle")
        }

        let sortedMatches = matches.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.0001 {
                return lhs.score < rhs.score
            }
            if lhs.values.count != rhs.values.count {
                return lhs.values.count > rhs.values.count
            }
            return lhs.values.map(\.rawValue).lexicographicallyPrecedes(rhs.values.map(\.rawValue))
        }
        if let bestMatch = sortedMatches.first,
           bestMatch.values.allSatisfy(\.isRest) {
            return sortedMatches.filter { match in
                match.values.allSatisfy(\.isRest)
            }
        }
        return sortedMatches
    }

    private static func rasterTemplateCandidateGroups(
        from matchesByCrop: [[RhythmTemplateMatch]]
    ) -> [[RhythmCandidate]] {
        matchesByCrop.flatMap { matches -> [[RhythmCandidate]] in
            guard let bestMatch = matches.first else {
                return []
            }

            if bestMatch.values.count > 1 {
                return bestMatch.values.map { value in
                    [
                        RhythmCandidate(
                            value: value,
                            score: bestMatch.score,
                            canDriveExactFit: bestMatch.canDriveExactFit,
                            canExtendAutoApplyStability: bestMatch.canExtendAutoApplyStability
                        )
                    ]
                }
            }

            let singleValueMatches = matches.filter { $0.values.count == 1 }
            let bestEvidenceByValue = singleValueMatches.reduce(into: [RhythmValue: RhythmTemplateCandidateEvidence]()) { evidenceByValue, match in
                guard let value = match.values.first else {
                    return
                }
                let evidence = RhythmTemplateCandidateEvidence(
                    score: match.score,
                    canDriveExactFit: match.canDriveExactFit,
                    canExtendAutoApplyStability: match.canExtendAutoApplyStability
                )
                guard let existingEvidence = evidenceByValue[value] else {
                    evidenceByValue[value] = evidence
                    return
                }
                if existingEvidence.score < evidence.score {
                    return
                }
                if abs(existingEvidence.score - evidence.score) <= 0.0001 {
                    evidenceByValue[value] = RhythmTemplateCandidateEvidence(
                        score: existingEvidence.score,
                        canDriveExactFit: existingEvidence.canDriveExactFit || evidence.canDriveExactFit,
                        canExtendAutoApplyStability: existingEvidence.canExtendAutoApplyStability || evidence.canExtendAutoApplyStability
                    )
                } else {
                    evidenceByValue[value] = evidence
                }
            }

            return [
                bestEvidenceByValue
                    .map { value, evidence in
                        RhythmCandidate(
                            value: value,
                            score: evidence.score,
                            canDriveExactFit: evidence.canDriveExactFit,
                            canExtendAutoApplyStability: evidence.canExtendAutoApplyStability
                        )
                    }
                    .sorted { lhs, rhs in
                        if abs(lhs.score - rhs.score) > 0.0001 {
                            return lhs.score < rhs.score
                        }
                        return lhs.value.wholeNoteLength < rhs.value.wholeNoteLength
                    }
            ]
        }
    }

    private static func rasterTemplateGridFirstRecognitionDecision(
        input: RhythmInkRasterInput,
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        naturalPath: CandidatePath,
        meter: Meter,
        drawingFrame: CGRect,
        includeExtendedStability: Bool
    ) -> RhythmRecognitionDecision? {
        guard let plan = rasterTemplateGridFirstPlan(
            input: input,
            crops: crops,
            matchesByCrop: matchesByCrop,
            naturalPath: naturalPath,
            meter: meter,
            drawingFrame: drawingFrame
        ) else {
            return nil
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        let phrase = RhythmPhraseHypothesis(
            source: .gridFirst,
            primitives: rhythmInkPrimitives(from: input.strokes, drawingFrame: input.drawingFrame),
            symbols: plan.symbols,
            uncoveredStrokeIndices: [],
            naturalValues: plan.values,
            naturalUnits: targetUnits,
            targetUnits: targetUnits,
            passesCompendium: true
        )
        let exactPath = CandidatePath(
            values: plan.values,
            score: plan.score,
            units: targetUnits
        )
        var proposal = measureProposal(
            from: plan.candidateGroups,
            exactPath: exactPath,
            meter: meter,
            includeExtendedStability: includeExtendedStability
        )
        if plan.requiresManualReview {
            proposal = RhythmicNotationMeasureProposal(
                values: proposal.values,
                safety: .manualReview,
                isNaturalExactFit: proposal.isNaturalExactFit
            )
        }

        if proposal.safety == .manualReview {
            let reviewReason = manualReviewReason(
                for: exactPath,
                candidateGroups: plan.candidateGroups,
                meter: meter
            ) ?? .ambiguousPhrase
            return .needsReview(reviewReason, phrase, proposal)
        }

        return .commit(proposal, phrase)
    }

    private static func rasterTemplateGridFirstPlan(
        input: RhythmInkRasterInput,
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        naturalPath: CandidatePath,
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmGridFirstPlan? {
        guard crops.count >= 2 else {
            return nil
        }

        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        guard targetUnits > 0 else {
            return nil
        }

        var states: [RhythmGridFirstStateKey: RhythmGridFirstState] = [
            RhythmGridFirstStateKey(cropIndex: 0, units: 0): RhythmGridFirstState(
                values: [],
                candidateGroups: [],
                groups: [],
                score: 0,
                maxAlignmentDiff: 0,
                mergedCropCount: 0
            )
        ]
        let maxGroupSize = min(4, crops.count)

        for cropIndex in 0..<crops.count {
            let activeStates = states.filter { $0.key.cropIndex == cropIndex }
            guard !activeStates.isEmpty else {
                continue
            }

            for (stateKey, state) in activeStates {
                let remainingCrops = crops.count - cropIndex
                let rangeLimit = min(maxGroupSize, remainingCrops)
                for groupSize in 1...rangeLimit {
                    let range = cropIndex..<(cropIndex + groupSize)
                    let groupCrop = rasterTemplateCombinedCrop(
                        crops: crops,
                        range: range,
                        input: input
                    )
                    let groupMatches = rasterTemplateGridFirstMatches(
                        for: groupCrop,
                        originalMatches: groupSize == 1 ? matchesByCrop[cropIndex] : nil,
                        input: input
                    )
                    guard !groupMatches.isEmpty else {
                        continue
                    }

                    for match in groupMatches {
                        guard RhythmicNotationCompendium.supportedValues.isSuperset(of: match.values),
                              !match.values.isEmpty else {
                            continue
                        }
                        let valueUnits = match.values.reduce(0) { partialResult, value in
                            partialResult + rhythmUnits(for: value, meter: meter)
                        }
                        let nextUnits = stateKey.units + valueUnits
                        guard valueUnits > 0,
                              nextUnits <= targetUnits,
                              rasterTemplateCanUseGridGroup(
                                crop: groupCrop,
                                groupSize: groupSize,
                                values: match.values,
                                drawingFrame: drawingFrame
                              ) else {
                            continue
                        }

                        guard let alignment = rasterTemplateGridAlignment(
                            values: match.values,
                            crop: groupCrop,
                            startUnits: stateKey.units,
                            meter: meter,
                            drawingFrame: drawingFrame
                        ) else {
                            continue
                        }

                        let groupingPenalty = Double(max(0, groupSize - 1)) * 0.12
                        let matchScore = match.score + alignment.scorePenalty + groupingPenalty
                        let candidateScore = max(0, matchScore / Double(max(1, match.values.count)))
                        let candidateGroups = match.values.map { value in
                            [
                                RhythmCandidate(
                                    value: value,
                                    score: candidateScore,
                                    canDriveExactFit: match.canDriveExactFit && alignment.canDriveExactFit,
                                    canExtendAutoApplyStability: match.canExtendAutoApplyStability
                                )
                            ]
                        }
                        let nextState = RhythmGridFirstState(
                            values: state.values + match.values,
                            candidateGroups: state.candidateGroups + candidateGroups,
                            groups: state.groups + [
                                RhythmGridFirstGroup(
                                    cropRange: range,
                                    values: match.values,
                                    candidateValues: Array(Set(groupMatches.flatMap(\.values))).sorted { lhs, rhs in
                                        if lhs.wholeNoteLength != rhs.wholeNoteLength {
                                            return lhs.wholeNoteLength < rhs.wholeNoteLength
                                        }
                                        return lhs.rawValue < rhs.rawValue
                                    },
                                    bounds: groupCrop.bounds,
                                    strokeIndices: groupCrop.strokeIndices
                                )
                            ],
                            score: state.score + matchScore,
                            maxAlignmentDiff: max(state.maxAlignmentDiff, alignment.maxDiff),
                            mergedCropCount: state.mergedCropCount + max(0, groupSize - 1)
                        )
                        let key = RhythmGridFirstStateKey(cropIndex: range.upperBound, units: nextUnits)
                        if let existing = states[key],
                           existing.score <= nextState.score {
                            continue
                        }
                        states[key] = nextState
                    }
                }
            }
        }

        guard let exactState = states[RhythmGridFirstStateKey(cropIndex: crops.count, units: targetUnits)],
              RhythmicNotationCompendium.accepts(exactState.values, in: meter) else {
            return nil
        }

        let reducedFragmentation = exactState.groups.count < crops.count
            || exactState.mergedCropCount > 0
        guard reducedFragmentation,
              exactState.values != naturalPath.values,
              rasterTemplateGridFirstPreservesRestIntent(
                from: naturalPath.values,
                to: exactState.values,
                meter: meter
              ) else {
            return nil
        }

        let averageScore = exactState.score / Double(max(1, exactState.values.count))
        let hardMaxDiff = max(CGFloat(42), drawingFrame.width * 0.13)
        guard averageScore <= 1.05,
              exactState.maxAlignmentDiff <= hardMaxDiff else {
            return nil
        }

        let symbols = exactState.groups.flatMap { group -> [RhythmSymbolHypothesis] in
            group.values.map { selectedValue in
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: Set(group.strokeIndices),
                    bounds: group.bounds,
                    candidateValues: group.candidateValues,
                    selectedValue: selectedValue
                )
            }
        }

        return RhythmGridFirstPlan(
            values: exactState.values,
            candidateGroups: exactState.candidateGroups,
            symbols: symbols,
            score: exactState.score,
            maxAlignmentDiff: exactState.maxAlignmentDiff,
            requiresManualReview: averageScore > 0.72 || exactState.maxAlignmentDiff > max(CGFloat(30), drawingFrame.width * 0.095)
        )
    }

    private static func rasterTemplateCombinedCrop(
        crops: [RhythmSymbolCrop],
        range: Range<Int>,
        input: RhythmInkRasterInput
    ) -> RhythmSymbolCrop {
        let selectedCrops = Array(crops[range])
        let strokes = selectedCrops.flatMap(\.strokes)
        let bounds = selectedCrops.reduce(into: CGRect.null) { partialResult, crop in
            partialResult = partialResult.union(crop.bounds)
        }
        let strokeIndices = selectedCrops.flatMap(\.strokeIndices).sorted()
        return RhythmSymbolCrop(
            index: range.lowerBound,
            strokeIndices: strokeIndices,
            bounds: bounds,
            normalizedBounds: input.normalizedBounds(for: bounds),
            rasterCells: RhythmInkRasterInput.rasterCells(
                for: strokes.flatMap(\.points),
                in: bounds
            ),
            strokes: strokes
        )
    }

    private static func rasterTemplateGridFirstMatches(
        for crop: RhythmSymbolCrop,
        originalMatches: [RhythmTemplateMatch]?,
        input: RhythmInkRasterInput
    ) -> [RhythmTemplateMatch] {
        let matches = originalMatches ?? rasterTemplateMatches(for: crop, input: input)
        guard !matches.isEmpty else {
            return []
        }

        return matches.filter { match in
            match.values.allSatisfy(RhythmicNotationCompendium.supportedValues.contains)
        }
    }

    private static func rasterTemplateCanUseGridGroup(
        crop: RhythmSymbolCrop,
        groupSize: Int,
        values: [RhythmValue],
        drawingFrame: CGRect
    ) -> Bool {
        guard groupSize > 1 else {
            return true
        }

        if values.count > 1 {
            return true
        }

        guard values.first?.isRest == true else {
            return false
        }

        let maxSingleEventWidth = max(CGFloat(62), drawingFrame.width * 0.19)
        guard crop.bounds.width <= maxSingleEventWidth else {
            return false
        }

        let sortedCrops = crop.strokes
            .map(\.bounds)
            .sorted { lhs, rhs in lhs.minX < rhs.minX }
        let maxGap = zip(sortedCrops, sortedCrops.dropFirst()).map { lhs, rhs in
            max(CGFloat(0), rhs.minX - lhs.maxX)
        }
        .max() ?? 0

        return maxGap <= max(CGFloat(18), drawingFrame.width * 0.055)
    }

    private static func rasterTemplateGridFirstPreservesRestIntent(
        from naturalValues: [RhythmValue],
        to gridValues: [RhythmValue],
        meter: Meter
    ) -> Bool {
        var gridSpans: [(range: Range<Int>, value: RhythmValue)] = []
        var gridCursor = 0
        for value in gridValues {
            let units = rhythmUnits(for: value, meter: meter)
            gridSpans.append((gridCursor..<(gridCursor + units), value))
            gridCursor += units
        }

        var naturalCursor = 0
        for value in naturalValues {
            let units = rhythmUnits(for: value, meter: meter)
            defer {
                naturalCursor += units
            }
            guard value.isRest else {
                continue
            }
            let replacement = gridSpans.first { span in
                span.range.contains(naturalCursor)
            }?.value
            guard replacement?.isRest == true else {
                return false
            }
        }
        return true
    }

    private static func rasterTemplateGridAlignment(
        values: [RhythmValue],
        crop: RhythmSymbolCrop,
        startUnits: Int,
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmGridAlignment? {
        if values.count == 4,
           values.allSatisfy({ $0 == .sixteenth }) {
            let beatUnits = rhythmUnits(forWholeNotes: meter.beatUnitWholeNoteLength)
            guard beatUnits == 4,
                  startUnits.isMultiple(of: beatUnits) else {
                return nil
            }
        }
        if values == [.eighth, .sixteenth, .sixteenth]
            || values == [.sixteenth, .sixteenth, .eighth] {
            let beatUnits = rhythmUnits(forWholeNotes: meter.beatUnitWholeNoteLength)
            guard beatUnits == 4,
                  startUnits.isMultiple(of: beatUnits) else {
                return nil
            }
        }

        let observedPositions: [CGFloat]
        if values.count > 1 {
            observedPositions = rasterTemplateAttackXPositions(
                for: crop,
                valueCount: values.count,
                drawingFrame: drawingFrame
            )
        } else {
            observedPositions = [crop.bounds.midX]
        }
        guard observedPositions.count == values.count else {
            return nil
        }

        var cursorUnits = startUnits
        var expectedPositions: [CGFloat] = []
        for value in values {
            expectedPositions.append(
                rasterTemplateGridAttackX(
                    startUnits: cursorUnits,
                    value: value,
                    meter: meter,
                    drawingFrame: drawingFrame
                )
            )
            cursorUnits += rhythmUnits(for: value, meter: meter)
        }

        let diffs = zip(expectedPositions, observedPositions).map { expected, observed in
            abs(expected - observed)
        }
        let averageDiff = diffs.reduce(0, +) / CGFloat(max(1, diffs.count))
        let maxDiff = diffs.max() ?? 0
        let softTolerance = max(CGFloat(24), drawingFrame.width * 0.075)
        let hardTolerance = max(CGFloat(58), drawingFrame.width * 0.18)
        guard maxDiff <= hardTolerance else {
            return nil
        }

        let overSoft = max(CGFloat(0), maxDiff - softTolerance)
        let scorePenalty = Double(averageDiff / softTolerance) * 0.55
            + Double(overSoft / softTolerance) * 0.9
        return RhythmGridAlignment(
            scorePenalty: scorePenalty,
            maxDiff: maxDiff,
            canDriveExactFit: maxDiff <= max(CGFloat(42), drawingFrame.width * 0.13)
        )
    }

    private static func rasterTemplateGridAttackX(
        startUnits: Int,
        value: RhythmValue,
        meter: Meter,
        drawingFrame: CGRect
    ) -> CGFloat {
        let startOffset = Double(startUnits) / 8.0
        let attackLaneLength = min(
            max(0, value.wholeNoteLength(in: meter)),
            meter.beatUnitWholeNoteLength
        )
        let attackCenterOffset = min(
            meter.measureLengthInWholeNotes,
            startOffset + attackLaneLength / 2
        )
        let fraction = meter.measureLengthInWholeNotes > 0
            ? attackCenterOffset / meter.measureLengthInWholeNotes
            : 0
        return drawingFrame.minX + drawingFrame.width * CGFloat(fraction)
    }

    private static func rasterTemplateAdjustedProposal(
        _ proposal: RhythmicNotationMeasureProposal,
        matchesByCrop: [[RhythmTemplateMatch]]
    ) -> RhythmicNotationMeasureProposal {
        let hasBeamedTemplate = matchesByCrop.contains { matches in
            (matches.first?.values.count ?? 0) > 1
        }
        let hasStrongWholeNoteTemplate = rasterTemplateHasStrongWholeNoteTemplate(
            proposal: proposal,
            matchesByCrop: matchesByCrop
        )
        guard proposal.safety == .manualReview,
              proposal.isNaturalExactFit,
              hasBeamedTemplate || hasStrongWholeNoteTemplate else {
            return proposal
        }

        return RhythmicNotationMeasureProposal(
            values: proposal.values,
            safety: .autoApply,
            isNaturalExactFit: proposal.isNaturalExactFit
        )
    }

    private static func rasterTemplateCanPromoteDenseExactPhrase(
        _ phrase: RhythmPhraseHypothesis
    ) -> Bool {
        guard phrase.isNaturalExactFit,
              phrase.passesCompendium,
              phrase.uncoveredStrokeIndices.isEmpty,
              phrase.naturalValues.count > 1,
              !phrase.naturalValues.contains(.whole),
              !phrase.naturalValues.contains(.wholeRest) else {
            return false
        }

        var seenCoveredStrokeSets: Set<Set<Int>> = []
        return phrase.symbols.contains { symbol in
            guard !symbol.coveredStrokeIndices.isEmpty,
                  symbol.selectedValue != nil else {
                return false
            }
            let inserted = seenCoveredStrokeSets.insert(symbol.coveredStrokeIndices)
            return !inserted.inserted
        }
    }

    private static func rasterTemplateCanPromoteUnderfilledExactPath(
        _ exactPath: CandidatePath,
        over naturalPath: CandidatePath,
        candidateGroups: [[RhythmCandidate]],
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        meter: Meter,
        drawingFrame: CGRect
    ) -> Bool {
        guard exactPath.units == rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
              exactPath.units > naturalPath.units,
              exactPath.values.count == naturalPath.values.count,
              exactPath.values.count == candidateGroups.count else {
            return false
        }

        let onlyLengthensExistingCandidates = zip(naturalPath.values, exactPath.values)
            .allSatisfy { naturalValue, exactValue in
                rhythmUnits(for: exactValue, meter: meter) >= rhythmUnits(for: naturalValue, meter: meter)
            }
        guard onlyLengthensExistingCandidates else {
            return false
        }

        let selectedCandidates = zip(exactPath.values, candidateGroups).compactMap { value, candidates in
            candidates.first { $0.value == value }
        }
        guard selectedCandidates.count == exactPath.values.count,
              selectedCandidates.allSatisfy(\.isConfidentEnoughForMeasureFit) else {
            return false
        }

        let tolerance = max(0.35, Double(candidateGroups.count) * 0.18)
        guard exactPath.score <= naturalPath.score + tolerance else {
            return false
        }

        return rasterTemplateRenderComparison(
            values: exactPath.values,
            crops: crops,
            matchesByCrop: matchesByCrop,
            meter: meter,
            drawingFrame: drawingFrame
        ).aligned
    }

    private static func rasterTemplateCanPromoteRestAnchoredOverflowExactPath(
        _ exactPath: CandidatePath,
        over naturalPath: CandidatePath,
        candidateGroups: [[RhythmCandidate]],
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        meter: Meter,
        drawingFrame: CGRect
    ) -> Bool {
        let targetUnits = rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes)
        guard exactPath.units == targetUnits,
              naturalPath.units > targetUnits,
              exactPath.values.count == naturalPath.values.count,
              exactPath.values.count == candidateGroups.count else {
            return false
        }

        let changedIndices = exactPath.values.indices.filter { index in
            exactPath.values[index] != naturalPath.values[index]
        }
        guard changedIndices.count == 1,
              let changedIndex = changedIndices.first,
              changedIndex > 0,
              exactPath.values[changedIndex - 1] == .eighthRest,
              exactPath.values[changedIndex] == .eighth,
              naturalPath.values[changedIndex] == .quarter
                || naturalPath.values[changedIndex] == .dottedQuarter else {
            return false
        }

        let selectedCandidates = zip(exactPath.values, candidateGroups).compactMap { value, candidates in
            candidates.first { $0.value == value }
        }
        guard selectedCandidates.count == exactPath.values.count else {
            return false
        }

        for (index, candidate) in selectedCandidates.enumerated() {
            if index == changedIndex {
                guard candidate.canExtendAutoApplyStability || candidate.isConfidentEnoughForMeasureFit,
                      candidate.score <= 1.1 else {
                    return false
                }
            } else if !candidate.isConfidentEnoughForMeasureFit {
                return false
            }
        }

        let tolerance = max(1.15, Double(candidateGroups.count) * 0.28)
        guard exactPath.score <= naturalPath.score + tolerance else {
            return false
        }

        return rasterTemplateRenderComparison(
            values: exactPath.values,
            crops: crops,
            matchesByCrop: matchesByCrop,
            meter: meter,
            drawingFrame: drawingFrame
        ).aligned
    }

    private static func rasterTemplateHasStrongWholeNoteTemplate(
        proposal: RhythmicNotationMeasureProposal,
        matchesByCrop: [[RhythmTemplateMatch]]
    ) -> Bool {
        guard proposal.values == [.whole],
              matchesByCrop.count == 1,
              let matches = matchesByCrop.first else {
            return false
        }

        return matches.contains { match in
            match.values == [.whole]
                && match.cropBounds.width >= 8
                && match.cropBounds.height >= 6
        }
    }

    private static func cropLooksLikeWholeNoteCircle(
        _ crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> Bool {
        guard !crop.bounds.isNull,
              crop.bounds.width >= max(CGFloat(7), drawingFrame.width * 0.015),
              crop.bounds.height >= max(CGFloat(5), drawingFrame.height * 0.055) else {
            return false
        }

        let ratio = crop.bounds.width / max(1, crop.bounds.height)
        guard ratio >= 0.45,
              ratio <= 2.8 else {
            return false
        }

        return crop.strokes.contains { stroke in
            let strokeRatio = stroke.bounds.width / max(1, stroke.bounds.height)
            return stroke.bounds.width >= 6
                && stroke.bounds.height >= 5
                && strokeRatio >= 0.45
                && strokeRatio <= 2.8
                && (stroke.looksClosed || stroke.looksHollowNoteHead)
        }
    }

    private static func rasterTemplatePhraseHypothesis(
        input: RhythmInkRasterInput,
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        unsupportedCrops: [RhythmSymbolCrop],
        candidateGroups: [[RhythmCandidate]],
        naturalPath: CandidatePath,
        meter: Meter
    ) -> RhythmPhraseHypothesis {
        let primitives = rhythmInkPrimitives(
            from: input.strokes,
            drawingFrame: input.drawingFrame
        )
        let unsupportedStrokeIndices = Array(Set(unsupportedCrops.flatMap(\.strokeIndices))).sorted()
        let selectedValuesByCrop = naturalPath.values.count == crops.count
            ? naturalPath.values
            : []
        let symbols = zip(crops.indices, zip(crops, matchesByCrop)).flatMap { cropIndex, pair -> [RhythmSymbolHypothesis] in
            let (crop, matches) = pair
            guard let bestMatch = matches.first else {
                return [
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: Set(crop.strokeIndices),
                        bounds: crop.bounds,
                        candidateValues: [],
                        selectedValue: nil
                    )
                ]
            }
            let candidateValues = Array(
                Set(matches.flatMap(\.values))
            ).sorted { lhs, rhs in
                if lhs.wholeNoteLength != rhs.wholeNoteLength {
                    return lhs.wholeNoteLength < rhs.wholeNoteLength
                }
                return lhs.rawValue < rhs.rawValue
            }
            let selectedValues = selectedValuesByCrop.indices.contains(cropIndex)
                ? [selectedValuesByCrop[cropIndex]]
                : bestMatch.values
            return selectedValues.map { selectedValue in
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: Set(crop.strokeIndices),
                    bounds: crop.bounds,
                    candidateValues: candidateValues,
                    selectedValue: selectedValue
                )
            }
        }

        return RhythmPhraseHypothesis(
            source: .rasterTemplate,
            primitives: primitives,
            symbols: symbols,
            uncoveredStrokeIndices: unsupportedStrokeIndices,
            naturalValues: naturalPath.values,
            naturalUnits: naturalPath.units,
            targetUnits: rhythmUnits(forWholeNotes: meter.measureLengthInWholeNotes),
            passesCompendium: RhythmicNotationCompendium.accepts(naturalPath.values, in: meter)
        )
    }

    static func rasterTemplateRenderComparison(
        values: [RhythmValue],
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRenderComparison {
        let observedPositions = zip(crops, matchesByCrop).flatMap { crop, matches -> [CGFloat] in
            guard let bestMatch = matches.first else {
                return []
            }
            if bestMatch.values.count > 1 {
                return rasterTemplateAttackXPositions(
                    for: crop,
                    valueCount: bestMatch.values.count,
                    drawingFrame: drawingFrame
                )
            }
            return [crop.bounds.midX]
        }

        return RhythmRenderComparison.evaluate(
            values: values,
            observedXPositions: observedPositions,
            meter: meter,
            drawingFrame: drawingFrame
        )
    }

    private static func rasterTemplateBeamedEighthValuesWithTerminalRest(
        for crop: RhythmSymbolCrop,
        beamedCount: Int,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        let valueCount = min(beamedCount, 4)
        guard valueCount >= 2,
              let trailingStroke = crop.strokes.max(by: { lhs, rhs in
                  lhs.bounds.maxX < rhs.bounds.maxX
              }) else {
            return nil
        }

        let trailingBounds = trailingStroke.bounds
        let previousMaxX = crop.strokes
            .filter { $0 != trailingStroke }
            .map(\.bounds.maxX)
            .max() ?? crop.bounds.minX
        let rightAnchored = trailingBounds.midX >= crop.bounds.minX + crop.bounds.width * 0.62
        let separatedFromNotes = trailingBounds.minX - previousMaxX >= max(CGFloat(3), input.drawingFrame.width * 0.008)
        let restSized = trailingBounds.height >= max(CGFloat(16), crop.bounds.height * 0.55)
            && trailingBounds.width <= max(CGFloat(28), crop.bounds.width * 0.55)
        let trailingSymbol = SymbolObservation(strokes: [trailingStroke])
        let hasRestShape = trailingSymbol.eighthRestComparisonScore(in: input.sceneBounds) != nil
            || trailingSymbol.sevenLikeEighthRestComparisonScore(in: input.sceneBounds) != nil
            || trailingStroke.looksLikeFlexibleOneStrokeEighthRest(in: input.drawingFrame)

        guard rightAnchored,
              separatedFromNotes,
              restSized,
              hasRestShape else {
            return nil
        }

        return Array(repeating: RhythmValue.eighth, count: valueCount - 1) + [.eighthRest]
    }

    private static func rasterTemplateBeamedEighthValuesWithLeadingRest(
        for crop: RhythmSymbolCrop,
        beamedCount: Int,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        let valueCount = min(beamedCount, 4)
        guard valueCount >= 2 else {
            return nil
        }

        let sortedStrokes = crop.strokes.sortedByVisualPosition()
        let maxPrefixCount = min(2, sortedStrokes.count - 1)
        guard maxPrefixCount >= 1 else {
            return nil
        }

        for prefixCount in 1...maxPrefixCount {
            let prefix = Array(sortedStrokes.prefix(prefixCount))
            let remaining = Array(sortedStrokes.dropFirst(prefixCount))
            guard let prefixBounds = prefix.nonEmptyBounds,
                  let remainingBounds = remaining.nonEmptyBounds,
                  prefixBounds.midX < remainingBounds.midX,
                  remaining.hasNoteheadBackedNoteEvidence(drawingFrame: input.drawingFrame) else {
                continue
            }

            let leftAnchored = prefixBounds.midX <= crop.bounds.minX + crop.bounds.width * 0.44
            let separatedFromNotes = remainingBounds.minX - prefixBounds.maxX >= -max(CGFloat(4), input.drawingFrame.width * 0.012)
            let restSized = prefixBounds.height >= max(CGFloat(12), crop.bounds.height * 0.38)
                && prefixBounds.width <= max(CGFloat(26), crop.bounds.width * 0.62)
            let prefixSymbol = SymbolObservation(strokes: prefix)
            let hasRestShape = prefixSymbol.eighthRestComparisonScore(in: input.sceneBounds) != nil
                || prefixSymbol.sevenLikeEighthRestComparisonScore(in: input.sceneBounds) != nil
                || prefix.looksLikeContextualLeadingEighthRest(drawingFrame: input.drawingFrame)
            guard leftAnchored,
                  separatedFromNotes,
                  restSized,
                  hasRestShape else {
                continue
            }

            let remainingEighthCount = max(
                1,
                SymbolObservation(strokes: remaining)
                    .beamedEighthNoteCount(drawingFrame: input.drawingFrame)
            )
            let noteCount = min(valueCount - 1, remainingEighthCount)
            return [.eighthRest] + Array(repeating: RhythmValue.eighth, count: noteCount)
        }

        return nil
    }

    private static func rasterTemplateBeamedSixteenthPairValues(
        for crop: RhythmSymbolCrop,
        beamedCount: Int,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        guard beamedCount == 2,
              rasterTemplateHasBeamedSixteenthPairEvidence(
                for: crop,
                drawingFrame: input.drawingFrame
              ) else {
            return nil
        }

        return [.sixteenth, .sixteenth]
    }

    private static func rasterTemplateBeamedSixteenthRunValues(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        guard rasterTemplateHasBeamedSixteenthRunEvidence(
            for: crop,
            drawingFrame: input.drawingFrame
        ) else {
            return nil
        }

        return Array(repeating: .sixteenth, count: 4)
    }

    private static func rasterTemplateBeamedMixedSixteenthRunValues(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        guard rasterTemplateHasBeamedEighthEvidence(for: crop, input: input),
              let evidence = rasterTemplateBeamedMixedSixteenthRunEvidence(
                for: crop,
                drawingFrame: input.drawingFrame
              ) else {
            return nil
        }

        return evidence.values
    }

    private static func rasterTemplateBeamedEighthCount(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> Int {
        let symbol = SymbolObservation(strokes: crop.strokes)
        let directCount = symbol.beamedEighthNoteCount(drawingFrame: input.drawingFrame)
        if directCount >= 2 {
            return directCount
        }

        let noteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .map(\.bounds.midX)
            .clusteredXs(minimumSeparation: max(CGFloat(7), input.drawingFrame.width * 0.03))
        let stemXs = crop.strokes
            .stemAnchorStrokes(drawingFrame: input.drawingFrame)
            .map(\.bounds.midX)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let clusteredStemXs = (stemXs + inferredStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(7), input.drawingFrame.width * 0.03))
        let beamishStrokes = crop.strokes.filter { stroke in
            stroke.looksLikeVisualBeamSeed(in: crop.bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: crop.strokes.stemAnchorStrokes(drawingFrame: input.drawingFrame),
                    in: crop.bounds,
                    drawingFrame: input.drawingFrame
                )
                || stroke.looksLikeFoldedBeamStemSeed(
                    over: crop.strokes.stemAnchorStrokes(drawingFrame: input.drawingFrame),
                    in: crop.bounds,
                    drawingFrame: input.drawingFrame
                )
                || stroke.connectedBeamStemXs(in: crop.bounds).count >= 1
        }
        if noteheadXs.count >= 2,
           (!beamishStrokes.isEmpty || clusteredStemXs.count >= 2) {
            if clusteredStemXs.count >= 2 {
                return min(clusteredStemXs.count, 4)
            }
            return min(max(2, noteheadXs.count), 4)
        }

        let hasBeam = crop.strokes.contains { stroke in
            stroke.isSharedBeam(across: crop.strokes.stemAnchorStrokes(drawingFrame: input.drawingFrame))
                || stroke.isSharedBeam(
                    overNoteheadXs: clusteredStemXs,
                    in: crop.bounds
                )
                || stroke.isConnectedBeamFrame(overNoteheadXs: clusteredStemXs, in: crop.bounds)
        }
        guard hasBeam,
              clusteredStemXs.count >= 2 else {
            return 0
        }
        return clusteredStemXs.count
    }

    private static func rasterTemplateHasBeamedSixteenthPairEvidence(
        for crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> Bool {
        let noteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .map(\.bounds.midX)
            .clusteredXs(minimumSeparation: max(CGFloat(7), drawingFrame.width * 0.03))
        let stems = crop.strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let anchorXs = (noteheadXs + stems.map(\.bounds.midX) + inferredStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(7), drawingFrame.width * 0.03))
            .sorted()

        let activeAnchorXs: [CGFloat]
        if let stemEndpoints = rasterTemplateEndpointAnchorPair(from: stems.map(\.bounds.midX)) {
            activeAnchorXs = stemEndpoints
        } else if let singleStemPair = rasterTemplateSingleStemBeamedAnchorPair(
            stemX: stems.first?.bounds.midX,
            noteheadXs: noteheadXs
        ) {
            activeAnchorXs = singleStemPair
        } else if let inferredStemEndpoints = rasterTemplateEndpointAnchorPair(from: inferredStemXs) {
            activeAnchorXs = inferredStemEndpoints
        } else if let noteheadEndpoints = rasterTemplateEndpointAnchorPair(from: noteheadXs) {
            activeAnchorXs = noteheadEndpoints
        } else if let anchorEndpoints = rasterTemplateEndpointAnchorPair(from: anchorXs) {
            activeAnchorXs = anchorEndpoints
        } else {
            return false
        }

        guard (noteheadXs.count >= 2 || stems.count >= 1),
              crop.strokes.contains(where: { $0.looksLikeVisualNotehead(in: crop.bounds) }) else {
            return false
        }

        let beamLevelYs = rasterTemplateBeamedSixteenthPairBeamLevelYs(
            for: crop,
            anchorXs: activeAnchorXs,
            stems: stems,
            drawingFrame: drawingFrame
        )
        return beamLevelYs.count >= 2
    }

    private static func rasterTemplateHasBeamedSixteenthRunEvidence(
        for crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> Bool {
        let anchors = rasterTemplateBeamedSixteenthRunAnchorXs(
            for: crop,
            drawingFrame: drawingFrame
        )
        guard anchors.count == 4 else {
            return false
        }

        let stems = crop.strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        let firstPairLevels = rasterTemplateBeamedSixteenthPairBeamLevelYs(
            for: crop,
            anchorXs: Array(anchors[0...1]),
            stems: stems,
            drawingFrame: drawingFrame
        )
        let secondPairLevels = rasterTemplateBeamedSixteenthPairBeamLevelYs(
            for: crop,
            anchorXs: Array(anchors[2...3]),
            stems: stems,
            drawingFrame: drawingFrame
        )

        return firstPairLevels.count >= 2
            && secondPairLevels.count >= 2
    }

    private static func rasterTemplateHasBeamedMixedSixteenthRunEvidence(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> Bool {
        guard rasterTemplateHasBeamedEighthEvidence(for: crop, input: input) else {
            return false
        }

        return rasterTemplateBeamedMixedSixteenthRunEvidence(
            for: crop,
            drawingFrame: input.drawingFrame
        ) != nil
    }

    private static func rasterTemplateBeamedSixteenthRunAnchorXs(
        for crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> [CGFloat] {
        let minimumSeparation = max(CGFloat(7), drawingFrame.width * 0.03)
        let lowerNoteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .filter { $0.bounds.midY >= crop.bounds.minY + crop.bounds.height * 0.55 }
            .map(\.bounds.midX)
            .clusteredXs(minimumSeparation: minimumSeparation)
            .sorted()
        if lowerNoteheadXs.count >= 4 {
            return Array(lowerNoteheadXs.prefix(4))
        }

        let stemXs = crop.strokes
            .stemAnchorStrokes(drawingFrame: drawingFrame)
            .map(\.bounds.midX)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let anchors = (lowerNoteheadXs + stemXs + inferredStemXs)
            .clusteredXs(minimumSeparation: minimumSeparation)
            .sorted()
        guard anchors.count >= 4 else {
            return []
        }
        return Array(anchors.prefix(4))
    }

    private static func rasterTemplateBeamedMixedSixteenthRunAnchorXs(
        for crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> [CGFloat] {
        rasterTemplateBeamedMixedSixteenthRunEvidence(
            for: crop,
            drawingFrame: drawingFrame
        )?.anchors ?? []
    }

    private static func rasterTemplateBeamedMixedSixteenthRunEvidence(
        for crop: RhythmSymbolCrop,
        drawingFrame: CGRect
    ) -> (values: [RhythmValue], anchors: [CGFloat])? {
        let minimumSeparation = max(CGFloat(7), drawingFrame.width * 0.03)
        let lowerNoteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .filter { $0.bounds.midY >= crop.bounds.minY + crop.bounds.height * 0.55 }
            .map(\.bounds.midX)
            .clusteredXs(minimumSeparation: minimumSeparation)
            .sorted()
        let stemXs = crop.strokes
            .stemAnchorStrokes(drawingFrame: drawingFrame)
            .map(\.bounds.midX)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let allAnchors = (lowerNoteheadXs + stemXs + inferredStemXs)
            .clusteredXs(minimumSeparation: minimumSeparation)
            .sorted()
        var candidates: [[CGFloat]] = []

        func appendWindows(from anchors: [CGFloat]) {
            guard anchors.count >= 3 else {
                return
            }

            for index in 0...(anchors.count - 3) {
                let window = Array(anchors[index..<(index + 3)])
                if !candidates.contains(window) {
                    candidates.append(window)
                }
            }
        }

        appendWindows(from: lowerNoteheadXs)
        appendWindows(from: allAnchors)

        let stems = crop.strokes.stemAnchorStrokes(drawingFrame: drawingFrame)
        for anchors in candidates {
            let leadingPairLevels = rasterTemplateBeamedSixteenthPairBeamLevelYs(
                for: crop,
                anchorXs: Array(anchors[0...1]),
                stems: stems,
                drawingFrame: drawingFrame
            )
            let trailingPairLevels = rasterTemplateBeamedSixteenthPairBeamLevelYs(
                for: crop,
                anchorXs: Array(anchors[1...2]),
                stems: stems,
                drawingFrame: drawingFrame
            )

            if leadingPairLevels.count >= 2,
               trailingPairLevels.count < 2 {
                return ([.sixteenth, .sixteenth, .eighth], anchors)
            }
            if trailingPairLevels.count >= 2,
               leadingPairLevels.count < 2 {
                return ([.eighth, .sixteenth, .sixteenth], anchors)
            }
        }

        return nil
    }

    private static func rasterTemplateEndpointAnchorPair(from xs: [CGFloat]) -> [CGFloat]? {
        let sorted = xs.sorted()
        guard let first = sorted.first,
              let last = sorted.last,
              abs(last - first) >= CGFloat(7) else {
            return nil
        }
        return [first, last]
    }

    private static func rasterTemplateSingleStemBeamedAnchorPair(
        stemX: CGFloat?,
        noteheadXs: [CGFloat]
    ) -> [CGFloat]? {
        guard let stemX,
              noteheadXs.count >= 2 else {
            return nil
        }

        let minimumSeparation = CGFloat(7)
        let farthestHeadX = noteheadXs
            .max { lhs, rhs in
                abs(lhs - stemX) < abs(rhs - stemX)
            }
        guard let farthestHeadX,
              abs(farthestHeadX - stemX) >= minimumSeparation else {
            return nil
        }
        return [stemX, farthestHeadX].sorted()
    }

    private static func rasterTemplateBeamedSixteenthPairBeamLevelYs(
        for crop: RhythmSymbolCrop,
        anchorXs: [CGFloat],
        stems: [StrokeObservation],
        drawingFrame: CGRect
    ) -> [CGFloat] {
        guard anchorXs.count == 2 else {
            return []
        }

        let beamStrokes = crop.strokes.filter { stroke in
            let beamLike = stroke.isSharedBeam(across: stems)
                || stroke.isSharedBeam(overNoteheadXs: anchorXs, in: crop.bounds)
                || stroke.isConnectedBeamFrame(overNoteheadXs: anchorXs, in: crop.bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: crop.bounds,
                    drawingFrame: drawingFrame
                )
            guard beamLike,
                  stroke.bounds.midY <= crop.bounds.minY + crop.bounds.height * 0.64 else {
                return false
            }

            let tolerance = stroke.beamedCoverageTolerance(in: crop.bounds)
            let coveredAnchorCount = anchorXs.filter { anchorX in
                stroke.bounds.minX <= anchorX + tolerance
                    && stroke.bounds.maxX >= anchorX - tolerance
            }.count
            return coveredAnchorCount == 2
        }
        let connectedBeamMassStrokes = crop.strokes.filter { stroke in
            !beamStrokes.contains(stroke)
                && rasterTemplateLooksLikeConnectedSixteenthBeamMass(
                    stroke,
                    over: anchorXs,
                    in: crop.bounds
                )
        }

        let minimumYSeparation = max(CGFloat(3), crop.bounds.height * 0.08)
        let separatedLevels = beamStrokes
            .map(\.bounds.midY)
            .sorted()
            .reduce(into: [CGFloat]()) { levels, y in
                guard let last = levels.last else {
                    levels.append(y)
                    return
                }
                if abs(y - last) >= minimumYSeparation {
                    levels.append(y)
                }
            }
        if separatedLevels.count >= 2 {
            return separatedLevels
        }

        let sameLevelDoubleBeamStrokes = beamStrokes
            .sorted { lhs, rhs in
                if lhs.bounds.midY == rhs.bounds.midY {
                    return lhs.bounds.width > rhs.bounds.width
                }
                return lhs.bounds.midY < rhs.bounds.midY
            }
        if sameLevelDoubleBeamStrokes.count >= 2 {
            let first = sameLevelDoubleBeamStrokes[0].bounds.midY
            let second = sameLevelDoubleBeamStrokes[1].bounds.midY
            return [first, second]
        }
        if let beamY = beamStrokes.first?.bounds.midY,
           let massY = connectedBeamMassStrokes.first?.bounds.midY {
            return [beamY, massY]
        }

        return separatedLevels
    }

    private static func rasterTemplateLooksLikeConnectedSixteenthBeamMass(
        _ stroke: StrokeObservation,
        over anchorXs: [CGFloat],
        in symbolBounds: CGRect
    ) -> Bool {
        guard anchorXs.count == 2,
              stroke.bounds.midY <= symbolBounds.minY + symbolBounds.height * 0.56,
              stroke.bounds.width >= max(CGFloat(16), symbolBounds.width * 0.52),
              stroke.bounds.height >= max(CGFloat(10), symbolBounds.height * 0.26),
              stroke.bounds.height <= max(CGFloat(42), symbolBounds.height * 0.86) else {
            return false
        }

        let tolerance = stroke.beamedCoverageTolerance(in: symbolBounds)
        let coveredAnchorCount = anchorXs.filter { anchorX in
            stroke.bounds.minX <= anchorX + tolerance
                && stroke.bounds.maxX >= anchorX - tolerance
        }.count
        guard coveredAnchorCount == 2 else {
            return false
        }

        let topBandMaxY = stroke.bounds.minY + stroke.bounds.height * 0.45
        let topBandPoints = stroke.points.filter { $0.y <= topBandMaxY }
        return topBandPoints.xSpread >= max(CGFloat(12), symbolBounds.width * 0.34)
    }

    private static func rasterTemplateHasBeamedEighthEvidence(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> Bool {
        let stems = crop.strokes.stemAnchorStrokes(drawingFrame: input.drawingFrame)
        let noteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .map(\.bounds.midX)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let anchorXs = (noteheadXs + stems.map(\.bounds.midX) + inferredStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(7), input.drawingFrame.width * 0.03))
        guard anchorXs.count >= 2 else {
            return false
        }

        return crop.strokes.contains { stroke in
            let beamLike = stroke.isSharedBeam(across: stems)
                || stroke.isSharedBeam(overNoteheadXs: anchorXs, in: crop.bounds)
                || stroke.isConnectedBeamFrame(overNoteheadXs: anchorXs, in: crop.bounds)
                || stroke.looksLikeSlopedVisualBeamSeed(
                    over: stems,
                    in: crop.bounds,
                    drawingFrame: input.drawingFrame
                )
                || stroke.looksLikeFoldedBeamStemSeed(
                    over: stems,
                    in: crop.bounds,
                    drawingFrame: input.drawingFrame
                )
            guard beamLike else {
                return false
            }

            let tolerance = stroke.beamedCoverageTolerance(in: crop.bounds)
            let coveredAnchorCount = anchorXs.filter { anchorX in
                stroke.bounds.minX <= anchorX + tolerance
                    && stroke.bounds.maxX >= anchorX - tolerance
            }.count
            return coveredAnchorCount >= 2
        }
    }

    private static func rasterTemplateHasUnbeamedSameBeatEighthRun(
        in path: CandidatePath,
        crops: [RhythmSymbolCrop],
        matchesByCrop: [[RhythmTemplateMatch]],
        input: RhythmInkRasterInput,
        meter: Meter
    ) -> Bool {
        var valueIndex = 0
        var cursorUnits = 0

        for (crop, matches) in zip(crops, matchesByCrop) {
            guard let bestMatch = matches.first else {
                continue
            }
            let valueCount = bestMatch.values.count
            guard valueCount > 0 else {
                continue
            }
            guard path.values.count >= valueIndex + valueCount else {
                return false
            }

            let values = Array(path.values[valueIndex..<(valueIndex + valueCount)])
            if values.count > 1,
               values.allSatisfy({ $0 == .eighth }),
               rasterTemplateValuesContainSameBeatEighthPair(
                    values,
                    startUnits: cursorUnits,
                    meter: meter
               ),
               !rasterTemplateHasBeamedEighthEvidence(for: crop, input: input) {
                return true
            }

            cursorUnits += values.reduce(0) { $0 + rhythmUnits(for: $1, meter: meter) }
            valueIndex += valueCount
        }

        return false
    }

    private static func rasterTemplateValuesContainSameBeatEighthPair(
        _ values: [RhythmValue],
        startUnits: Int,
        meter: Meter
    ) -> Bool {
        let beatUnits = max(1, rhythmUnits(forWholeNotes: meter.beatUnitWholeNoteLength))
        var cursorUnits = startUnits
        var previousEighthStart: Int?

        for value in values {
            defer {
                cursorUnits += rhythmUnits(for: value, meter: meter)
            }

            guard value == .eighth else {
                previousEighthStart = nil
                continue
            }

            if let previousEighthStart,
               previousEighthStart / beatUnits == cursorUnits / beatUnits {
                return true
            }
            previousEighthStart = cursorUnits
        }

        return false
    }

    private static func featuresShouldRejectClassifierCandidate(
        _ value: RhythmValue,
        for symbol: SymbolObservation,
        drawingFrame: CGRect
    ) -> Bool {
        let features = SymbolFeatures(symbol: symbol, drawingFrame: drawingFrame)
        let hasHollowInkHead = symbol.strokes.contains { stroke in
            stroke.looksHollowNoteHead
        }
        let hasFilledInkHead = symbol.strokes.contains { stroke in
            stroke.looksFilledNoteHead && !stroke.looksHollowNoteHead
        }
        if features.hasNoNoteheadRestShape {
            switch value {
            case .quarter, .dottedQuarter, .sixteenth, .eighth, .half, .dottedHalf, .whole:
                return true
            case .slash, .sixteenthRest, .eighthRest, .quarterRest, .halfRest, .wholeRest, .tiedContinuation:
                break
            }
        }
        switch value {
        case .quarter, .dottedQuarter:
            return (features.hasHollowHead || hasHollowInkHead)
                && !features.hasFilledHead
                && !hasFilledInkHead
        case .half, .dottedHalf:
            return (features.hasFilledHead || hasFilledInkHead)
                && !features.hasHollowHead
                && !hasHollowInkHead
        default:
            return false
        }
    }

    private static func rasterTemplateValueHasRequiredEvidence(
        _ value: RhythmValue,
        crop: RhythmSymbolCrop,
        features: SymbolFeatures,
        templateName: String
    ) -> Bool {
        let hasHollowInkHead = features.headStrokes.contains { stroke in
            stroke.looksHollowNoteHead
        }
        let hasFilledInkHead = features.headStrokes.contains { stroke in
            stroke.looksFilledNoteHead && !stroke.looksHollowNoteHead
        }
        let hasAttachedCompactHead = crop.strokes.contains { stroke in
            guard stroke != features.stemStroke else {
                return false
            }
            return stroke.looksLikeLowerNotehead(in: crop.bounds)
                || strokeLooksLikeCompactHeadAttachedToStem(stroke, crop: crop, features: features)
        }
        let hasHollowNoteheadEvidence = features.hasHollowHead || hasHollowInkHead
        let hasFilledNoteheadEvidence = !hasHollowNoteheadEvidence
            && (
                features.hasFilledHead
                    || hasFilledInkHead
                    || hasAttachedCompactHead
                    || features.hasLowerHeadMass
                    || features.hasStemAndKick
                    || (features.hasStem && cropHasLowerHeadMass(crop))
            )

        switch value {
        case .slash:
            return templateName == "placeholder-slash"
                || (
                    !cropHasNoteGlyphEvidence(crop, features: features)
                        && (templateName == "forward-slash" || rasterCellsMatchForwardSlash(crop.rasterCells))
                )
        case .eighth:
            guard !features.hasNoNoteheadRestShape else {
                return false
            }
            let hasShortValueMarker = templateName.contains("beamed")
                || features.hasFlag
                || cropHasUpperFlagMass(crop, features: features)
            if templateName.contains("beamed") {
                return features.hasStem
                    && cropHasNoteGlyphEvidence(crop, features: features)
            }
            return features.hasStem
                && hasFilledNoteheadEvidence
                && hasShortValueMarker
        case .sixteenth:
            guard !features.hasNoNoteheadRestShape else {
                return false
            }
            if templateName == "beamed-sixteenth-pair" {
                return features.hasStem
                    && cropHasNoteGlyphEvidence(crop, features: features)
                    && rasterTemplateHasBeamedSixteenthPairEvidence(
                        for: crop,
                        drawingFrame: features.drawingFrame
                    )
            }
            if templateName == "beamed-sixteenth-run" {
                return cropHasNoteGlyphEvidence(crop, features: features)
                    && rasterTemplateHasBeamedSixteenthRunEvidence(
                        for: crop,
                        drawingFrame: features.drawingFrame
                    )
            }
            if templateName == "beamed-sixteenth-mixed-run" {
                return cropHasNoteGlyphEvidence(crop, features: features)
                    && rasterTemplateHasBeamedMixedSixteenthRunEvidence(
                        for: crop,
                        input: rasterTemplateInput(
                            strokeObservations: crop.strokes,
                            drawingFrame: features.drawingFrame
                        )
                    )
            }
            if templateName == "double-flagged-stem" {
                return features.hasStem
                    && cropHasNoteGlyphEvidence(crop, features: features)
                    && rasterTemplateHasDoubleFlagEvidence(crop, features: features)
            }
            return false
        case .dottedQuarter:
            return cropHasDetachedDotEvidence(features)
                && features.hasStem
                && hasFilledNoteheadEvidence
                && !hasHollowNoteheadEvidence
        case .dottedHalf:
            return cropHasDetachedDotEvidence(features)
                && features.hasStem
                && hasHollowNoteheadEvidence
                && !hasFilledNoteheadEvidence
        case .quarter:
            return features.hasStem
                && hasFilledNoteheadEvidence
                && !hasHollowNoteheadEvidence
        case .half:
            return features.hasStem
                && hasHollowNoteheadEvidence
                && !hasFilledNoteheadEvidence
        case .whole:
            return !features.hasStem
                && (hasHollowNoteheadEvidence || cropLooksLikeWholeNoteCircle(crop, drawingFrame: features.drawingFrame))
        case .sixteenthRest, .eighthRest, .quarterRest:
            return true
        case .halfRest, .wholeRest:
            return !cropHasStemmedNoteEvidence(crop, features: features)
        case .tiedContinuation:
            return false
        }
    }

    private static func cropHasStemmedNoteEvidence(
        _ crop: RhythmSymbolCrop,
        features: SymbolFeatures
    ) -> Bool {
        features.hasStem
            || features.hasFlag
            || features.hasStemAndKick
            || (features.hasHollowHead && cropHasLowerHeadMass(crop))
    }

    private static func cropHasNoteGlyphEvidence(
        _ crop: RhythmSymbolCrop,
        features: SymbolFeatures
    ) -> Bool {
        features.hasClearNoteGlyph
            || features.hasFilledHead
            || features.hasHollowHead
            || features.hasLowerHeadMass
            || cropHasUpperHeadMass(crop)
            || features.hasStemAndKick
            || (features.hasStem && cropHasLowerHeadMass(crop))
    }

    private static func cropHasDetachedDotEvidence(_ features: SymbolFeatures) -> Bool {
        guard features.hasDot else {
            return false
        }

        let stemRightEdge = features.stemStroke?.bounds.maxX ?? features.contentBounds.midX
        let dotBandTop = features.contentBounds.midY - features.height * 0.15
        let dotBandBottom = features.contentBounds.maxY + features.height * 0.32
        return features.dotStrokes.contains { stroke in
            let compact = stroke.bounds.width <= max(CGFloat(8), features.width * 0.34)
                && stroke.bounds.height <= max(CGFloat(8), features.height * 0.34)
                && stroke.pathLength <= max(CGFloat(28), features.height * 1.25)
            let rightOfStem = stroke.center.x >= stemRightEdge + max(CGFloat(1), features.width * 0.04)
            let inDotBand = stroke.center.y >= dotBandTop && stroke.center.y <= dotBandBottom
            let tooLargeForDot = stroke.bounds.width > max(CGFloat(9), features.width * 0.38)
                || stroke.bounds.height > max(CGFloat(9), features.height * 0.38)

            return compact && rightOfStem && inDotBand && !tooLargeForDot
        }
    }

    private static func strokeLooksLikeCompactHeadAttachedToStem(
        _ stroke: StrokeObservation,
        crop: RhythmSymbolCrop,
        features: SymbolFeatures
    ) -> Bool {
        guard let stemStroke = features.stemStroke else {
            return false
        }

        let horizontalTolerance = max(CGFloat(8), crop.bounds.width * 0.4)
        let verticallyNearStemEnd = min(
            abs(stroke.center.y - stemStroke.startPoint.y),
            abs(stroke.center.y - stemStroke.endPoint.y)
        ) <= max(CGFloat(9), crop.bounds.height * 0.26)
        let horizontallyAttached = stroke.bounds.maxX >= stemStroke.bounds.minX - horizontalTolerance
            && stroke.bounds.minX <= stemStroke.bounds.maxX + horizontalTolerance
        let noteheadSized = stroke.bounds.width >= max(CGFloat(5), crop.bounds.width * 0.18)
            && stroke.bounds.height >= max(CGFloat(5), crop.bounds.height * 0.12)
        let substantialAttachedBlob = stroke.bounds.width >= max(CGFloat(7), crop.bounds.width * 0.42)
            && stroke.bounds.height >= max(CGFloat(6), crop.bounds.height * 0.14)
        let noteheadLike = stroke.looksFilledNoteHead
            || stroke.looksHollowNoteHead
            || stroke.looksClosed
            || substantialAttachedBlob

        return horizontallyAttached
            && verticallyNearStemEnd
            && noteheadSized
            && noteheadLike
    }

    private static func rasterTemplateAttackXPositions(
        for crop: RhythmSymbolCrop,
        valueCount: Int,
        drawingFrame: CGRect
    ) -> [CGFloat] {
        if valueCount == 3 {
            let mixedBeamAnchors = rasterTemplateBeamedMixedSixteenthRunAnchorXs(
                for: crop,
                drawingFrame: drawingFrame
            )
            if mixedBeamAnchors.count == valueCount {
                return mixedBeamAnchors
            }
        }

        let noteheadXs = crop.strokes
            .filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
            .map(\.bounds.midX)
        let stemXs = crop.strokes
            .stemAnchorStrokes(drawingFrame: drawingFrame)
            .map(\.bounds.midX)
        let inferredStemXs = crop.strokes
            .flatMap { $0.connectedBeamStemXs(in: crop.bounds) }
        let xs = (noteheadXs + stemXs + inferredStemXs)
            .clusteredXs(minimumSeparation: max(CGFloat(7), drawingFrame.width * 0.03))
            .sorted()
        if xs.count >= valueCount {
            return Array(xs.prefix(valueCount))
        }

        guard valueCount > 1 else {
            return [crop.bounds.midX]
        }

        let step = crop.bounds.width / CGFloat(valueCount)
        return (0..<valueCount).map { index in
            crop.bounds.minX + step * (CGFloat(index) + 0.5)
        }
    }

    private static func rasterTemplateVisualNoteAnchorCenters(
        for crop: RhythmSymbolCrop,
        valueCount: Int,
        drawingFrame: CGRect
    ) -> [CGPoint] {
        let xPositions = valueCount > 1
            ? rasterTemplateAttackXPositions(
                for: crop,
                valueCount: valueCount,
                drawingFrame: drawingFrame
            )
            : [rasterTemplateSingleNoteAnchorX(for: crop)]

        return xPositions.map { xPosition in
            rasterTemplateVisualNoteAnchorCenter(
                for: crop,
                nearX: xPosition,
                valueCount: valueCount,
                drawingFrame: drawingFrame
            )
        }
    }

    private static func rasterTemplateSingleNoteAnchorX(for crop: RhythmSymbolCrop) -> CGFloat {
        let noteheadStrokes = crop.strokes.filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
        guard let noteheadBounds = noteheadStrokes.nonEmptyBounds else {
            return crop.bounds.midX
        }

        return noteheadBounds.midX
    }

    private static func rasterTemplateVisualNoteAnchorCenter(
        for crop: RhythmSymbolCrop,
        nearX xPosition: CGFloat,
        valueCount: Int,
        drawingFrame: CGRect
    ) -> CGPoint {
        let noteheadStrokes = crop.strokes.filter { $0.looksLikeVisualNotehead(in: crop.bounds) }
        if let nearestNotehead = noteheadStrokes.min(by: { lhs, rhs in
            abs(lhs.center.x - xPosition) < abs(rhs.center.x - xPosition)
        }) {
            return nearestNotehead.center
        }

        let xWindow = max(CGFloat(9), crop.bounds.width / CGFloat(max(2, valueCount * 2)))
        let lowerPoints = crop.strokes
            .flatMap(\.points)
            .filter { point in
                point.y >= crop.bounds.minY + crop.bounds.height * 0.46
                    && abs(point.x - xPosition) <= xWindow
            }
        if let lowerBounds = lowerPoints.nonEmptyBounds {
            return CGPoint(x: lowerBounds.midX, y: lowerBounds.midY)
        }

        let widerLowerPoints = crop.strokes
            .flatMap(\.points)
            .filter { point in
                point.y >= crop.bounds.minY + crop.bounds.height * 0.46
            }
        if let lowerBounds = widerLowerPoints.nonEmptyBounds {
            return CGPoint(x: xPosition, y: lowerBounds.midY)
        }

        return CGPoint(
            x: xPosition,
            y: crop.bounds.maxY - min(max(CGFloat(4), crop.bounds.height * 0.14), 10)
        )
    }

    private static func rasterTemplateAdjustment(
        for value: RhythmValue,
        crop: RhythmSymbolCrop
    ) -> Double {
        switch value {
        case .slash:
            return rasterCellsMatchForwardSlash(crop.rasterCells) ? 0 : 0.12
        case .quarter, .dottedQuarter, .sixteenth, .eighth:
            return rasterCellsMatchStemmedNote(crop.rasterCells) ? 0 : 0.08
        case .half, .dottedHalf:
            return cropHasLowerHeadMass(crop) ? 0 : 0.08
        default:
            return 0
        }
    }

    private static func rasterTemplatePlaceholderSlashValues(
        for crop: RhythmSymbolCrop,
        input: RhythmInkRasterInput
    ) -> [RhythmValue]? {
        guard !crop.strokes.isEmpty,
              crop.strokes.allSatisfy({
                  !$0.looksLikeQuarterRestBody(in: $0.bounds)
                      && !$0.looksLikeFlexibleOneStrokeQuarterRest(in: $0.bounds)
                      && !$0.looksLikeFlexibleOneStrokeSixteenthRest(in: input.drawingFrame)
                      && !$0.looksLikeFlexibleOneStrokeEighthRest(in: input.drawingFrame)
                      && $0.looksLikeRhythmicPlaceholderSlash(in: $0.bounds)
                      && $0.isIsolatedPlaceholderSlash(
                          among: input.strokes,
                          sceneBounds: input.sceneBounds
                      )
              }) else {
            return nil
        }

        return Array(repeating: .slash, count: crop.strokes.count)
    }

    private static func rasterCellsMatchForwardSlash(_ cells: Set<RhythmRasterCell>) -> Bool {
        guard !cells.isEmpty else {
            return false
        }

        let lowerLeft = cells.filter { $0.x <= 4 && $0.y >= 7 }.count
        let middle = cells.filter { $0.x >= 4 && $0.x <= 8 && $0.y >= 4 && $0.y <= 8 }.count
        let upperRight = cells.filter { $0.x >= 7 && $0.y <= 4 }.count
        let upperLeft = cells.filter { $0.x <= 4 && $0.y <= 4 }.count
        let lowerRight = cells.filter { $0.x >= 7 && $0.y >= 7 }.count
        return lowerLeft > 0
            && middle > 0
            && upperRight > 0
            && upperLeft <= max(1, lowerLeft)
            && lowerRight <= max(1, upperRight)
    }

    private static func rasterCellsMatchStemmedNote(_ cells: Set<RhythmRasterCell>) -> Bool {
        guard !cells.isEmpty else {
            return false
        }

        let upperStemCells = cells.filter { $0.y <= 5 }
        let lowerHeadCells = cells.filter { $0.y >= 7 }
        let stemColumns = Dictionary(grouping: upperStemCells, by: \.x)
            .filter { _, cells in cells.count >= 2 }
        let lowerWidth = Set(lowerHeadCells.map(\.x)).count
        return !stemColumns.isEmpty && lowerWidth >= 2
    }

    private static func cropHasLowerHeadMass(_ crop: RhythmSymbolCrop) -> Bool {
        let lowerPoints = crop.strokes
            .flatMap(\.points)
            .filter { point in
                point.y >= crop.bounds.minY + crop.bounds.height * 0.48
            }
        guard let lowerBounds = lowerPoints.nonEmptyBounds else {
            return false
        }

        return lowerBounds.width >= max(CGFloat(4), crop.bounds.width * 0.22)
            && lowerBounds.height >= max(CGFloat(3), crop.bounds.height * 0.08)
    }

    private static func cropHasUpperFlagMass(
        _ crop: RhythmSymbolCrop,
        features: SymbolFeatures
    ) -> Bool {
        let noteheadStrokes = Set(
            crop.strokes.filter {
                $0.looksLikeVisualNotehead(in: crop.bounds) || $0.isNoteheadLikeMark
            }
        )
        let stemStroke = features.stemStroke
        let upperPoints = crop.strokes
            .filter { stroke in
                !noteheadStrokes.contains(stroke) && stroke != stemStroke
            }
            .flatMap(\.points)
            .filter { point in
                point.y <= crop.bounds.minY + crop.bounds.height * 0.36
            }
        guard let upperBounds = upperPoints.nonEmptyBounds else {
            return false
        }

        return upperBounds.width >= max(CGFloat(4), crop.bounds.width * 0.18)
            && upperBounds.height <= max(CGFloat(16), crop.bounds.height * 0.42)
    }

    private static func rasterTemplateHasDoubleFlagEvidence(
        _ crop: RhythmSymbolCrop,
        features: SymbolFeatures
    ) -> Bool {
        let flagLikeStrokes = features.flagStrokes.filter { stroke in
            stroke.bounds.width >= max(CGFloat(3), features.height * 0.08)
                || stroke.bounds.height >= max(CGFloat(5), features.height * 0.16)
                || stroke.directionChangeCount >= 1
        }
        if flagLikeStrokes.count >= 2 {
            return true
        }

        guard let stemStroke = features.stemStroke else {
            return false
        }

        let upperMarks = crop.strokes.filter { stroke in
            stroke != stemStroke
                && !features.headStrokes.contains(stroke)
                && stroke.center.y <= features.contentBounds.midY
                && stroke.bounds.minX <= stemStroke.bounds.maxX + features.height * 0.55
                && stroke.bounds.maxX >= stemStroke.bounds.minX - features.height * 0.2
                && stroke.bounds.width >= max(CGFloat(4), features.width * 0.12)
        }
        return upperMarks.count >= 2
    }

    private static func cropHasUpperHeadMass(_ crop: RhythmSymbolCrop) -> Bool {
        let upperHeadStrokes = crop.strokes.filter { stroke in
            stroke.isNoteheadLikeMark
                && stroke.center.y <= crop.bounds.midY
                && stroke.bounds.width >= max(CGFloat(4), crop.bounds.width * 0.18)
                && stroke.bounds.height >= max(CGFloat(4), crop.bounds.height * 0.12)
        }
        return !upperHeadStrokes.isEmpty
    }
}

struct RhythmTemplateCandidateEvidence: Hashable {
    let score: Double
    let canDriveExactFit: Bool
    let canExtendAutoApplyStability: Bool
}

private struct RhythmGridFirstPlan: Hashable {
    let values: [RhythmValue]
    let candidateGroups: [[RhythmCandidate]]
    let symbols: [RhythmSymbolHypothesis]
    let score: Double
    let maxAlignmentDiff: CGFloat
    let requiresManualReview: Bool
}

private struct RhythmGridFirstStateKey: Hashable {
    let cropIndex: Int
    let units: Int
}

private struct RhythmGridFirstState: Hashable {
    let values: [RhythmValue]
    let candidateGroups: [[RhythmCandidate]]
    let groups: [RhythmGridFirstGroup]
    let score: Double
    let maxAlignmentDiff: CGFloat
    let mergedCropCount: Int
}

private struct RhythmGridFirstGroup: Hashable {
    let cropRange: Range<Int>
    let values: [RhythmValue]
    let candidateValues: [RhythmValue]
    let bounds: CGRect
    let strokeIndices: [Int]
}

private struct RhythmGridAlignment: Hashable {
    let scorePenalty: Double
    let maxDiff: CGFloat
    let canDriveExactFit: Bool
}

struct RhythmRasterCell: Hashable {
    let x: Int
    let y: Int
}

struct RhythmInkRasterInput: Hashable {
    let strokes: [StrokeObservation]
    let drawingFrame: CGRect
    let sceneBounds: CGRect
    let rasterCells: Set<RhythmRasterCell>

    init(strokes: [StrokeObservation], drawingFrame: CGRect) {
        self.strokes = strokes
        self.drawingFrame = drawingFrame
        self.sceneBounds = strokes.nonEmptyBounds ?? drawingFrame
        self.rasterCells = Self.rasterCells(
            for: strokes.flatMap(\.points),
            in: strokes.nonEmptyBounds ?? drawingFrame
        )
    }

    func normalizedBounds(for bounds: CGRect) -> CGRect {
        guard !drawingFrame.isEmpty,
              drawingFrame.width > 0,
              drawingFrame.height > 0 else {
            return .zero
        }

        return CGRect(
            x: (bounds.minX - drawingFrame.minX) / drawingFrame.width,
            y: (bounds.minY - drawingFrame.minY) / drawingFrame.height,
            width: bounds.width / drawingFrame.width,
            height: bounds.height / drawingFrame.height
        )
    }

    static func rasterCells(
        for points: [CGPoint],
        in bounds: CGRect,
        gridSize: Int = 12
    ) -> Set<RhythmRasterCell> {
        guard !points.isEmpty,
              !bounds.isNull,
              !bounds.isEmpty,
              bounds.width > 0,
              bounds.height > 0,
              gridSize > 1 else {
            return []
        }

        return Set(points.map { point in
            let normalizedX = max(CGFloat(0), min(CGFloat(0.999), (point.x - bounds.minX) / bounds.width))
            let normalizedY = max(CGFloat(0), min(CGFloat(0.999), (point.y - bounds.minY) / bounds.height))
            return RhythmRasterCell(
                x: Int((normalizedX * CGFloat(gridSize)).rounded(.down)),
                y: Int((normalizedY * CGFloat(gridSize)).rounded(.down))
            )
        })
    }
}

struct RhythmSymbolCrop: Hashable {
    let index: Int
    let strokeIndices: [Int]
    let bounds: CGRect
    let normalizedBounds: CGRect
    let rasterCells: Set<RhythmRasterCell>
    let strokes: [StrokeObservation]
}

struct RhythmVisualNoteAnchor: Hashable {
    let index: Int
    let center: CGPoint
    let bounds: CGRect
    let normalizedBounds: CGRect
}

struct RhythmVisualTemplate: Hashable {
    let name: String
    let value: RhythmValue
    let expectedCells: Set<RhythmRasterCell>
}

struct RhythmTemplateMatch: Hashable {
    let values: [RhythmValue]
    let score: Double
    let templateName: String
    let cropBounds: CGRect
    let canDriveExactFit: Bool
    let canExtendAutoApplyStability: Bool
}

enum RhythmVisualCompendium {
    static let supportedValues: Set<RhythmValue> = [
        .slash,
        .quarter,
        .half,
        .whole,
        .sixteenth,
        .eighth,
        .dottedQuarter,
        .dottedHalf,
        .sixteenthRest,
        .eighthRest,
        .quarterRest,
        .halfRest,
        .wholeRest
    ]

    static let templates: [RhythmVisualTemplate] = [
        RhythmVisualTemplate(name: "forward-slash", value: .slash, expectedCells: [
            RhythmRasterCell(x: 2, y: 10),
            RhythmRasterCell(x: 5, y: 7),
            RhythmRasterCell(x: 9, y: 2)
        ]),
        RhythmVisualTemplate(name: "filled-stem", value: .quarter, expectedCells: [
            RhythmRasterCell(x: 6, y: 1),
            RhythmRasterCell(x: 6, y: 5),
            RhythmRasterCell(x: 4, y: 9)
        ]),
        RhythmVisualTemplate(name: "flagged-stem", value: .eighth, expectedCells: [
            RhythmRasterCell(x: 6, y: 1),
            RhythmRasterCell(x: 9, y: 3),
            RhythmRasterCell(x: 4, y: 9)
        ]),
        RhythmVisualTemplate(name: "beamed-eighth-run", value: .eighth, expectedCells: [
            RhythmRasterCell(x: 2, y: 2),
            RhythmRasterCell(x: 6, y: 2),
            RhythmRasterCell(x: 10, y: 2),
            RhythmRasterCell(x: 3, y: 9),
            RhythmRasterCell(x: 9, y: 9)
        ]),
        RhythmVisualTemplate(name: "dotted-filled-stem", value: .dottedQuarter, expectedCells: [
            RhythmRasterCell(x: 5, y: 1),
            RhythmRasterCell(x: 5, y: 8),
            RhythmRasterCell(x: 10, y: 9)
        ]),
        RhythmVisualTemplate(name: "hollow-stem", value: .half, expectedCells: [
            RhythmRasterCell(x: 6, y: 1),
            RhythmRasterCell(x: 6, y: 5),
            RhythmRasterCell(x: 4, y: 9)
        ]),
        RhythmVisualTemplate(name: "dotted-hollow-stem", value: .dottedHalf, expectedCells: [
            RhythmRasterCell(x: 5, y: 1),
            RhythmRasterCell(x: 5, y: 8),
            RhythmRasterCell(x: 10, y: 9)
        ]),
        RhythmVisualTemplate(name: "hollow-head", value: .whole, expectedCells: [
            RhythmRasterCell(x: 3, y: 6),
            RhythmRasterCell(x: 6, y: 5),
            RhythmRasterCell(x: 9, y: 6)
        ]),
        RhythmVisualTemplate(name: "eighth-rest", value: .eighthRest, expectedCells: [
            RhythmRasterCell(x: 3, y: 2),
            RhythmRasterCell(x: 7, y: 4),
            RhythmRasterCell(x: 6, y: 9)
        ]),
        RhythmVisualTemplate(name: "sixteenth-rest", value: .sixteenthRest, expectedCells: [
            RhythmRasterCell(x: 3, y: 2),
            RhythmRasterCell(x: 7, y: 4),
            RhythmRasterCell(x: 5, y: 6),
            RhythmRasterCell(x: 6, y: 10)
        ]),
        RhythmVisualTemplate(name: "quarter-rest", value: .quarterRest, expectedCells: [
            RhythmRasterCell(x: 5, y: 1),
            RhythmRasterCell(x: 4, y: 5),
            RhythmRasterCell(x: 6, y: 10)
        ]),
        RhythmVisualTemplate(name: "half-rest", value: .halfRest, expectedCells: [
            RhythmRasterCell(x: 2, y: 5),
            RhythmRasterCell(x: 9, y: 5)
        ]),
        RhythmVisualTemplate(name: "whole-rest", value: .wholeRest, expectedCells: [
            RhythmRasterCell(x: 2, y: 5),
            RhythmRasterCell(x: 9, y: 6)
        ])
    ]
}

struct RhythmRenderComparison: Hashable {
    let score: Double
    let aligned: Bool
    let expectedXPositions: [CGFloat]
    let observedXPositions: [CGFloat]

    static func evaluate(
        values: [RhythmValue],
        observedXPositions: [CGFloat],
        meter: Meter,
        drawingFrame: CGRect
    ) -> RhythmRenderComparison {
        guard !values.isEmpty,
              values.count == observedXPositions.count,
              let slots = MeasureRhythmMap(values: values).resolvedSlots(for: meter) else {
            return RhythmRenderComparison(
                score: .greatestFiniteMagnitude,
                aligned: false,
                expectedXPositions: [],
                observedXPositions: observedXPositions
            )
        }

        if values.count == 1 {
            return RhythmRenderComparison(
                score: 0,
                aligned: true,
                expectedXPositions: observedXPositions,
                observedXPositions: observedXPositions
            )
        }

        let expectedXPositions = slots.map { slot in
            renderedAttackX(
                for: slot,
                meter: meter,
                drawingFrame: drawingFrame
            )
        }
        guard expectedXPositions.count == observedXPositions.count else {
            return RhythmRenderComparison(
                score: .greatestFiniteMagnitude,
                aligned: false,
                expectedXPositions: expectedXPositions,
                observedXPositions: observedXPositions
            )
        }

        let diffs = zip(expectedXPositions, observedXPositions).map { expected, observed in
            abs(expected - observed)
        }
        let averageDiff = diffs.reduce(0, +) / max(1, Double(diffs.count))
        let maxDiff = diffs.max() ?? 0
        let tolerance = max(CGFloat(52), drawingFrame.width * 0.25)
        let expectedSpan = max(CGFloat(1), (expectedXPositions.max() ?? 0) - (expectedXPositions.min() ?? 0))
        let observedSpan = max(CGFloat(1), (observedXPositions.max() ?? 0) - (observedXPositions.min() ?? 0))
        let hasEnoughSpan = values.count <= 2 || observedSpan >= expectedSpan * 0.48
        let isMonotonic = zip(observedXPositions, observedXPositions.dropFirst()).allSatisfy { lhs, rhs in
            rhs >= lhs - 1
        }

        return RhythmRenderComparison(
            score: Double(averageDiff),
            aligned: maxDiff <= tolerance && hasEnoughSpan && isMonotonic,
            expectedXPositions: expectedXPositions,
            observedXPositions: observedXPositions
        )
    }

    private static func renderedAttackX(
        for slot: MeasureRhythmSlot,
        meter: Meter,
        drawingFrame: CGRect
    ) -> CGFloat {
        let startOffset = slot.startPosition.startOffset(in: meter) ?? 0
        let attackLaneLength = min(
            max(0, slot.duration.wholeNoteLength(in: meter)),
            meter.beatUnitWholeNoteLength
        )
        let attackCenterOffset = min(
            meter.measureLengthInWholeNotes,
            startOffset + attackLaneLength / 2
        )
        let fraction = meter.measureLengthInWholeNotes > 0
            ? attackCenterOffset / meter.measureLengthInWholeNotes
            : 0
        return drawingFrame.minX + drawingFrame.width * CGFloat(fraction)
    }
}
#endif
