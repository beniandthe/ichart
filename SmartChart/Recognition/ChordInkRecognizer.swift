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
    var symbolLedger: ChordInkSymbolLedger
    var templates: [GestureTemplate]
    var maxGlyphCandidatesPerCluster: Int
    var minimumAcceptedCandidateConfidence: Double

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        candidateComposer: ChordInkCandidateComposer = ChordInkCandidateComposer(),
        semanticCandidateComposer: ChordInkSemanticCandidateComposer = ChordInkSemanticCandidateComposer(),
        symbolLedger: ChordInkSymbolLedger = ChordInkSymbolLedger(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates,
        maxGlyphCandidatesPerCluster: Int = 8,
        minimumAcceptedCandidateConfidence: Double = 3.70
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.candidateComposer = candidateComposer
        self.semanticCandidateComposer = semanticCandidateComposer
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
        let contextualGlyphCandidateGroups = semanticCandidateComposer.contextualizedGlyphCandidateGroups(
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
        let chordCandidates = candidateResult.candidates
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

        let candidateScores = chordCandidates.prefix(8)
            .filter { $0.confidence >= minimumScoredCandidateConfidence }
            .map { candidate in
                let match = cachedMatch(candidate.text)
                return ChordInkCandidateScore(
                    text: candidate.text,
                    displayText: match?.displayText,
                    confidence: candidate.confidence
                )
            }
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
                semanticCandidateCount: candidateResult.semanticCandidateCount,
                rawCandidateCount: rawCandidates.count,
                compositionMetrics: candidateResult.compositionMetrics
            )
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1_000
    }
}
