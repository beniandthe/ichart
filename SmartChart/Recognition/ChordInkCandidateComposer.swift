import Foundation

struct ChordInkCandidate: Hashable {
    var text: String
    var confidence: Double
    var glyphCandidates: [GlyphCandidate]
}

struct ChordInkCandidateCompositionResult: Hashable {
    var candidates: [ChordInkCandidate]
    var metrics: ChordInkCandidateCompositionMetrics
}

struct ChordInkCandidateComposerConfiguration: Hashable {
    var maxAlternativesPerCluster: Int
    var maxCandidateCount: Int
    var maxGeneratedSequences: Int
    var scoring: ChordInkCandidateComposerScoring

    static let chordSymbols = ChordInkCandidateComposerConfiguration(
        maxAlternativesPerCluster: 3,
        maxCandidateCount: 32,
        maxGeneratedSequences: 4096,
        scoring: ChordInkCandidateComposerScoring()
    )
}

struct ChordInkCandidateComposer {
    var configuration: ChordInkCandidateComposerConfiguration

    init(configuration: ChordInkCandidateComposerConfiguration = .chordSymbols) {
        self.configuration = configuration
    }

    func compose(glyphCandidates columns: [[GlyphCandidate]]) -> [ChordInkCandidate] {
        composeDetailed(glyphCandidates: columns).candidates
    }

    func composeDetailed(glyphCandidates columns: [[GlyphCandidate]]) -> ChordInkCandidateCompositionResult {
        let sortedColumns = columns.map(\.sortedByConfidence)
        let selectionPolicy = ChordInkCandidateSelectionPolicy(
            maxAlternativesPerCluster: configuration.maxAlternativesPerCluster
        )
        let candidateColumns = sortedColumns.indices
            .map { index in
                selectionPolicy.selectedGlyphCandidates(forColumnAt: index, in: sortedColumns)
            }
            .filter { !$0.isEmpty }

        guard !candidateColumns.isEmpty else {
            return ChordInkCandidateCompositionResult(
                candidates: [],
                metrics: ChordInkCandidateCompositionMetrics(
                    selectedColumnCount: 0,
                    generatedSequenceCount: 0,
                    returnedCandidateCount: 0,
                    maxGeneratedSequences: configuration.maxGeneratedSequences,
                    hitGeneratedSequenceLimit: false
                )
            )
        }

        var bestCandidatesByText: [String: ChordInkCandidate] = [:]
        var generatedSequenceCount = 0
        var hitGeneratedSequenceLimit = false
        let scoringPolicy = ChordInkCandidateScoringPolicy(scoring: configuration.scoring)
        let textVariantPolicy = ChordInkCandidateTextVariantPolicy()

        for prefixLength in 1...candidateColumns.count {
            let prefixColumns = Array(candidateColumns.prefix(prefixLength))
            for sequence in candidateSequences(from: prefixColumns) {
                guard generatedSequenceCount < configuration.maxGeneratedSequences else {
                    hitGeneratedSequenceLimit = true
                    break
                }

                generatedSequenceCount += 1

                for variant in textVariantPolicy.textVariants(for: sequence) {
                    let confidence = scoringPolicy.score(
                        text: variant,
                        glyphCandidates: sequence,
                        candidateColumns: candidateColumns,
                        totalClusterCount: candidateColumns.count
                    )
                    let candidate = ChordInkCandidate(
                        text: variant,
                        confidence: confidence,
                        glyphCandidates: sequence
                    )

                    if let currentBest = bestCandidatesByText[variant],
                       currentBest.confidence >= candidate.confidence {
                        continue
                    }

                    bestCandidatesByText[variant] = candidate
                }
            }
        }

        let candidates = Array(bestCandidatesByText.values)
            .sortedByConfidence
            .prefix(configuration.maxCandidateCount)
            .map { $0 }
        return ChordInkCandidateCompositionResult(
            candidates: candidates,
            metrics: ChordInkCandidateCompositionMetrics(
                selectedColumnCount: candidateColumns.count,
                generatedSequenceCount: generatedSequenceCount,
                returnedCandidateCount: candidates.count,
                maxGeneratedSequences: configuration.maxGeneratedSequences,
                hitGeneratedSequenceLimit: hitGeneratedSequenceLimit
            )
        )
    }

    private func candidateSequences(from columns: [[GlyphCandidate]]) -> [[GlyphCandidate]] {
        columns.reduce([[]]) { partialSequences, column in
            partialSequences.flatMap { sequence in
                column.map { candidate in
                    sequence + [candidate]
                }
            }
        }
    }

}

private extension Array where Element == GlyphCandidate {
    var sortedByConfidence: [GlyphCandidate] {
        sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
    }
}

private extension Array where Element == ChordInkCandidate {
    var sortedByConfidence: [ChordInkCandidate] {
        sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }

            return lhs.text < rhs.text
        }
    }
}
