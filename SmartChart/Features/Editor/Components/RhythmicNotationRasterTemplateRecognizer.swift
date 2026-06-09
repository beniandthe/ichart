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
            let proposal = rasterTemplateAdjustedProposal(
                measuredProposal,
                matchesByCrop: matchesByCrop
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
            add(Array(repeating: .eighth, count: min(beamedCount, 4)), score: 0.0, template: "beamed-eighth-run")
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

        if let restCandidates = visualRestCandidates(for: symbol, drawingFrame: input.drawingFrame) {
            for candidate in restCandidates {
                add([candidate.value], score: candidate.score, template: "rest-\(candidate.value.rawValue)")
            }
        }
        let hasStrongNonEighthRestMatch = matches.contains { match in
            guard match.score <= 0.2,
                  match.values.count == 1,
                  let value = match.values.first else {
                return false
            }
            return value.isRest && value != .eighthRest
        }
        let hasEighthRestMatch = symbol.eighthRestComparisonScore(in: input.sceneBounds) != nil
            || symbol.sevenLikeEighthRestComparisonScore(in: input.sceneBounds) != nil
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
           (features.hasHollowHead || hasHollowInkHead),
           !hasFilledInkHead {
            add([.dottedHalf], score: 0.05, template: "dotted-hollow-stem")
        }
        if features.hasStem,
           features.hasDot,
           !features.hasHollowHead,
           !hasHollowInkHead,
           (features.hasFilledHead || features.hasLowerHeadMass || features.hasStemAndKick || hasStemmedNoteRaster) {
            add([.dottedQuarter], score: 0.05, template: "dotted-filled-stem")
        }
        if features.hasStem,
           !hasHollowInkHead,
           (features.hasFilledHead || hasFilledInkHead || hasUpperHeadMass || features.hasLowerHeadMass || features.hasStemAndKick || hasStemmedNoteRaster) {
            add([.quarter], score: 0.08, template: "filled-stem")
            add(
                [.eighth],
                score: 1.0,
                template: "filled-stem-eighth-alternative",
                canDriveExactFit: false,
                canExtendAutoApplyStability: true
            )
        }
        if features.hasStem,
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
        switch value {
        case .slash:
            return templateName == "placeholder-slash"
                || (
                    !cropHasNoteGlyphEvidence(crop, features: features)
                        && (templateName == "forward-slash" || rasterCellsMatchForwardSlash(crop.rasterCells))
                )
        case .eighth:
            return templateName == "filled-stem-eighth-alternative"
                || templateName.contains("beamed")
                || features.hasFlag
                || cropHasUpperFlagMass(crop, features: features)
        case .dottedQuarter, .dottedHalf:
            return cropHasDetachedDotEvidence(features)
        case .quarter, .half, .whole:
            return cropHasNoteGlyphEvidence(crop, features: features)
        case .eighthRest, .quarterRest, .halfRest, .wholeRest:
            return true
        case .tiedContinuation:
            return false
        }
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

    private static func rasterTemplateAttackXPositions(
        for crop: RhythmSymbolCrop,
        valueCount: Int,
        drawingFrame: CGRect
    ) -> [CGFloat] {
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
        case .quarter, .dottedQuarter, .eighth:
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
                  $0.looksLikeRhythmicPlaceholderSlash(in: $0.bounds)
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
        .eighth,
        .dottedQuarter,
        .dottedHalf,
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
