import Foundation

protocol ChordInkRecognizing {
    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult
}

extension ChordInkRecognizing {
    func recognize(strokes: [InkStroke]) -> ChordInkRecognitionResult {
        recognize(strokes: strokes, options: .live)
    }
}

struct ChordInkRecognizer: ChordInkRecognizing {
    var clusterer: StrokeClusterer
    var glyphRecognizer: GestureTemplateRecognizer
    var candidateComposer: ChordInkCandidateComposer
    var semanticCandidateComposer: ChordInkSemanticCandidateComposer
    var semanticGlyphContextualizer: ChordInkSemanticGlyphContextualizer
    var symbolLedger: ChordInkSymbolLedger
    var templates: [GestureTemplate]
    var maxGlyphCandidatesPerCluster: Int
    var minimumAcceptedCandidateConfidence: Double

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        candidateComposer: ChordInkCandidateComposer = ChordInkCandidateComposer(),
        semanticCandidateComposer: ChordInkSemanticCandidateComposer = ChordInkSemanticCandidateComposer(),
        semanticGlyphContextualizer: ChordInkSemanticGlyphContextualizer = ChordInkSemanticGlyphContextualizer(),
        symbolLedger: ChordInkSymbolLedger = ChordInkSymbolLedger(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates,
        maxGlyphCandidatesPerCluster: Int = 8,
        minimumAcceptedCandidateConfidence: Double = 3.70
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.candidateComposer = candidateComposer
        self.semanticCandidateComposer = semanticCandidateComposer
        self.semanticGlyphContextualizer = semanticGlyphContextualizer
        self.symbolLedger = symbolLedger
        self.templates = templates
        self.maxGlyphCandidatesPerCluster = maxGlyphCandidatesPerCluster
        self.minimumAcceptedCandidateConfidence = minimumAcceptedCandidateConfidence
    }

    func recognize(
        strokes: [InkStroke],
        options: ChordInkRecognitionOptions = .live
    ) -> ChordInkRecognitionResult {
        let recognitionStart = Date()
        let clusterStart = Date()
        let clusters = clusterer.cluster(strokes)
        let clusterMilliseconds = Self.elapsedMilliseconds(since: clusterStart)

        let glyphStart = Date()
        let glyphCandidateGroups = clusters.map { cluster in
            glyphRecognizer.rankedCandidates(
                for: cluster,
                templates: templates,
                limit: maxGlyphCandidatesPerCluster
            )
        }
        let glyphMilliseconds = Self.elapsedMilliseconds(since: glyphStart)

        let contextStart = Date()
        let contextualGlyphCandidateGroups = semanticGlyphContextualizer.contextualizedGlyphCandidateGroups(
            glyphCandidateGroups,
            clusters: clusters
        )
        let contextualGlyphMilliseconds = Self.elapsedMilliseconds(since: contextStart)

        let recognitionCandidateComposer = ChordInkRecognitionCandidateComposer(
            baseComposer: candidateComposer,
            semanticCandidateComposer: semanticCandidateComposer
        )
        let candidateResult = recognitionCandidateComposer.composeRecognitionCandidates(
            from: contextualGlyphCandidateGroups,
            clusters: clusters
        )
        let chordRepeatCandidate = ChordRepeatInkDetector.candidate(from: strokes)
        let chordCandidates: [ChordInkCandidate]
        if let chordRepeatCandidate {
            chordCandidates = [chordRepeatCandidate] + candidateResult.candidates.filter {
                $0.text != chordRepeatCandidate.text
            }
        } else {
            chordCandidates = candidateResult.candidates
        }
        let rawCandidates = chordCandidates.map(\.text)
        let symbolLedgerSnapshot = options.includesSymbolLedgerDiagnostics
            ? symbolLedger.snapshot(
                glyphCandidateGroups: contextualGlyphCandidateGroups,
                clusters: clusters,
                chordCandidates: chordCandidates
            )
            : nil

        let matchStart = Date()
        let minimumScoredCandidateConfidence = minimumAcceptedCandidateConfidence
            - ChordInkRecognitionPolicy.closeRaceConfidenceGap
        var matchCache: [String: ChordRecognitionMatch] = [:]
        var unmatchedCandidateTexts = Set<String>()
        func cachedMatch(_ text: String) -> ChordRecognitionMatch? {
            if let match = matchCache[text] {
                return match
            }
            if unmatchedCandidateTexts.contains(text) {
                return nil
            }

            guard let match = ChordRecognitionCompendium.match(text) else {
                unmatchedCandidateTexts.insert(text)
                return nil
            }

            matchCache[text] = match
            return match
        }

        let candidateScores = Self.candidateScores(
            from: chordCandidates,
            minimumConfidence: minimumScoredCandidateConfidence,
            match: cachedMatch
        )
        let acceptedCandidate = chordCandidates.lazy.compactMap { candidate -> (ChordRecognitionMatch, Double)? in
            guard let match = cachedMatch(candidate.text),
                  candidate.confidence >= minimumAcceptedCandidateConfidence else {
                return nil
            }

            return (match, candidate.confidence)
        }.first
        let match = acceptedCandidate?.0
        let acceptedConfidence = acceptedCandidate?.1 ?? 0
        let matchMilliseconds = Self.elapsedMilliseconds(since: matchStart)
        let symbolLedgerAssessment = symbolLedgerSnapshot?.assessment(
            primaryDisplayText: match?.displayText
        )

        return ChordInkRecognitionResult(
            rawCandidates: rawCandidates,
            glyphCandidates: contextualGlyphCandidateGroups,
            match: match,
            confidence: acceptedConfidence,
            candidateScores: candidateScores,
            symbolLedger: symbolLedgerSnapshot,
            symbolLedgerAssessment: symbolLedgerAssessment,
            metrics: ChordInkRecognitionMetrics(
                clusterMilliseconds: clusterMilliseconds,
                glyphMilliseconds: glyphMilliseconds,
                contextualGlyphMilliseconds: contextualGlyphMilliseconds,
                composeMilliseconds: candidateResult.composeMilliseconds,
                semanticMilliseconds: candidateResult.semanticMilliseconds,
                matchMilliseconds: matchMilliseconds,
                totalMilliseconds: Self.elapsedMilliseconds(since: recognitionStart),
                strokeCount: strokes.count,
                clusterCount: clusters.count,
                glyphCandidateColumnCount: contextualGlyphCandidateGroups.count,
                semanticCandidateCount: candidateResult.semanticCandidateCount + (chordRepeatCandidate == nil ? 0 : 1),
                rawCandidateCount: rawCandidates.count,
                compositionMetrics: candidateResult.compositionMetrics
            )
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }

    static func candidateScores(
        from chordCandidates: [ChordInkCandidate],
        minimumConfidence: Double,
        match: (String) -> ChordRecognitionMatch?
    ) -> [ChordInkCandidateScore] {
        let rawScorePrefixCount = 8
        let supportedScoreTargetCount = 12
        var scores: [ChordInkCandidateScore] = []
        var scoredCandidateTexts = Set<String>()
        var supportedDisplayTexts = Set<String>()

        func appendScore(for candidate: ChordInkCandidate, match: ChordRecognitionMatch?) {
            guard candidate.confidence >= minimumConfidence,
                  !scoredCandidateTexts.contains(candidate.text) else {
                return
            }

            let displayText = match?.displayText
            scores.append(
                ChordInkCandidateScore(
                    text: candidate.text,
                    displayText: displayText,
                    confidence: candidate.confidence
                )
            )
            scoredCandidateTexts.insert(candidate.text)

            if let displayText {
                supportedDisplayTexts.insert(displayText)
            }
        }

        for candidate in chordCandidates.prefix(rawScorePrefixCount) {
            appendScore(for: candidate, match: match(candidate.text))
        }

        for candidate in chordCandidates.dropFirst(rawScorePrefixCount) {
            guard candidate.confidence >= minimumConfidence,
                  let supportedMatch = match(candidate.text),
                  !supportedDisplayTexts.contains(supportedMatch.displayText) else {
                continue
            }

            appendScore(for: candidate, match: supportedMatch)
            if supportedDisplayTexts.count >= supportedScoreTargetCount {
                break
            }
        }

        return scores
    }
}

private enum ChordRepeatInkDetector {
    static func candidate(from strokes: [InkStroke]) -> ChordInkCandidate? {
        let indexedStrokes = strokes.enumerated().filter { !$0.element.points.isEmpty }
        guard indexedStrokes.count == 3 else {
            return nil
        }

        let bounds = InkBounds.enclosing(indexedStrokes.map(\.element.bounds))
        for slashStroke in indexedStrokes where isSlashLike(slashStroke.element, symbolBounds: bounds) {
            let dotStrokes = indexedStrokes.filter { $0.offset != slashStroke.offset }
            guard dotStrokes.count == 2,
                  dotStrokes.allSatisfy({ isDotLike($0.element, symbolBounds: bounds) }),
                  hasChordRepeatLayout(
                    slashStroke: slashStroke.element,
                    dotStrokes: dotStrokes.map(\.element),
                    symbolBounds: bounds
                  ) else {
                continue
            }

            return ChordInkCandidate(
                text: ChordSymbol.chordRepeatDisplayText,
                confidence: 4.95,
                glyphCandidates: [
                    GlyphCandidate(text: "•", confidence: 0.94, source: .composer),
                    GlyphCandidate(text: "/", confidence: 0.94, source: .composer),
                    GlyphCandidate(text: "•", confidence: 0.94, source: .composer)
                ]
            )
        }

        return nil
    }

    private static func isSlashLike(_ stroke: InkStroke, symbolBounds: InkBounds) -> Bool {
        stroke.bounds.width >= 4
            && stroke.bounds.height >= max(14, symbolBounds.height * 0.42)
            && stroke.diagonalAngleMagnitude >= 40
            && stroke.diagonalAngleMagnitude <= 82
            && stroke.straightness >= 0.55
    }

    private static func isDotLike(_ stroke: InkStroke, symbolBounds: InkBounds) -> Bool {
        let maximumDotSize = max(14, min(22, max(symbolBounds.width, symbolBounds.height) * 0.42))
        let width = stroke.bounds.width
        let height = stroke.bounds.height
        let aspect = max(max(width, height), 1) / max(min(width, height), 1)
        let longThinMark = max(width, height) >= 8 && aspect >= 2.2

        return width <= maximumDotSize
            && height <= maximumDotSize
            && !longThinMark
    }

    private static func hasChordRepeatLayout(
        slashStroke: InkStroke,
        dotStrokes: [InkStroke],
        symbolBounds: InkBounds
    ) -> Bool {
        let orderedDots = dotStrokes.sorted { lhs, rhs in
            lhs.bounds.recognitionMidX < rhs.bounds.recognitionMidX
        }
        guard let leftDot = orderedDots.first,
              let rightDot = orderedDots.last else {
            return false
        }

        let horizontalTolerance = max(8, symbolBounds.width * 0.22)
        let verticalTolerance = max(10, symbolBounds.height * 0.30)
        let dotHorizontalSpread = rightDot.bounds.recognitionMidX - leftDot.bounds.recognitionMidX
        let slashCenterX = slashStroke.bounds.recognitionMidX
        let slashBetweenDots = slashCenterX >= leftDot.bounds.recognitionMidX - horizontalTolerance
            && slashCenterX <= rightDot.bounds.recognitionMidX + horizontalTolerance
        let slashCoversDotsVertically = slashStroke.bounds.minY <= min(leftDot.bounds.recognitionMidY, rightDot.bounds.recognitionMidY) + verticalTolerance
            && slashStroke.bounds.maxY >= max(leftDot.bounds.recognitionMidY, rightDot.bounds.recognitionMidY) - verticalTolerance
        let diagonalRepeatDots = leftDot.bounds.recognitionMidY <= slashStroke.bounds.recognitionMidY + verticalTolerance
            && rightDot.bounds.recognitionMidY >= slashStroke.bounds.recognitionMidY - verticalTolerance
        let horizontalRepeatDots = abs(leftDot.bounds.recognitionMidY - rightDot.bounds.recognitionMidY) <= verticalTolerance

        return dotHorizontalSpread >= max(8, symbolBounds.width * 0.24)
            && slashBetweenDots
            && slashCoversDotsVertically
            && (diagonalRepeatDots || horizontalRepeatDots)
    }
}
