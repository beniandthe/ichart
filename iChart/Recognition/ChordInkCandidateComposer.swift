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
        let sortedColumns = columns.map { column in
            ChordRecognitionDomain.projectTopRanked(column.sortedByConfidence, label: { $0.text })
        }
        // A rejected or missing symbol still owns its place in the complete
        // written chord. Do not drop it and manufacture a shorter read.
        guard !sortedColumns.isEmpty, sortedColumns.allSatisfy({ !$0.isEmpty }) else {
            return emptyCompositionResult()
        }
        let selectionPolicy = ChordInkCandidateSelectionPolicy(
            maxAlternativesPerCluster: configuration.maxAlternativesPerCluster
        )
        let candidateColumns = sortedColumns.indices
            .map { index in
                selectionPolicy.selectedGlyphCandidates(forColumnAt: index, in: sortedColumns)
            }

        guard candidateColumns.allSatisfy({ !$0.isEmpty }) else {
            return emptyCompositionResult()
        }

        var bestCandidatesByText: [String: ChordInkCandidate] = [:]
        var generatedSequenceCount = 0
        var hitGeneratedSequenceLimit = false
        let scoringPolicy = ChordInkCandidateScoringPolicy(scoring: configuration.scoring)
        let textVariantPolicy = ChordInkCandidateTextVariantPolicy()

        // Always evaluate the complete written sequence before recovery
        // prefixes. The previous shortest-first Cartesian walk could spend the
        // entire safety budget before reaching a long chord such as
        // `Db7(b9)/F`, making its slash bass impossible to recognize.
        for prefixLength in stride(from: candidateColumns.count, through: 1, by: -1) {
            guard generatedSequenceCount < configuration.maxGeneratedSequences else {
                hitGeneratedSequenceLimit = true
                break
            }

            let prefixColumns = Array(candidateColumns.prefix(prefixLength))
            let remainingBudget = configuration.maxGeneratedSequences - generatedSequenceCount
            let shorterPrefixCount = prefixLength - 1
            let reservedForShorterPrefixes = min(
                max(remainingBudget - 1, 0),
                shorterPrefixCount * 64
            )
            let sequenceBudget = max(remainingBudget - reservedForShorterPrefixes, 1)
            let generated = candidateSequences(
                from: prefixColumns,
                limit: sequenceBudget
            )
            hitGeneratedSequenceLimit = hitGeneratedSequenceLimit || generated.didTruncate

            for sequence in generated.sequences {
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
                       !isPreferred(candidate, over: currentBest) {
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

    private func emptyCompositionResult() -> ChordInkCandidateCompositionResult {
        ChordInkCandidateCompositionResult(
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

    func candidateSequences(
        from columns: [[GlyphCandidate]],
        limit: Int
    ) -> (sequences: [[GlyphCandidate]], didTruncate: Bool) {
        guard limit > 0 else {
            return ([], !columns.isEmpty)
        }

        struct RankedSequence {
            var glyphs: [GlyphCandidate]
            var confidenceSum: Double
            var signature: String
        }

        let rankedColumns = columns.map(\.sortedByConfidence)
        guard rankedColumns.allSatisfy({ !$0.isEmpty }) else {
            return ([], false)
        }

        var combinationCount = 1
        for column in rankedColumns {
            if combinationCount > limit / column.count {
                combinationCount = limit + 1
                break
            }
            combinationCount *= column.count
        }
        let didTruncate = combinationCount > limit

        if !didTruncate {
            // When every combination fits the safety budget, sequence order is
            // irrelevant: candidates are scored and deterministically reduced
            // by text below. Generate the Cartesian product directly and avoid
            // sorting every intermediate prefix. This is the common expensive
            // path for long, correctly written chord forms.
            var sequences: [[GlyphCandidate]] = []
            sequences.reserveCapacity(combinationCount)
            var current: [GlyphCandidate] = []
            current.reserveCapacity(rankedColumns.count)

            func appendSequences(columnIndex: Int) {
                guard columnIndex < rankedColumns.count else {
                    sequences.append(current)
                    return
                }
                for candidate in rankedColumns[columnIndex] {
                    current.append(candidate)
                    appendSequences(columnIndex: columnIndex + 1)
                    current.removeLast()
                }
            }
            appendSequences(columnIndex: 0)
            return (sequences, false)
        }

        // A truncated search affects whether the result may be trusted, so
        // preserve the established beam's exact floating-point accumulation,
        // ordering, and cutoff semantics on this uncommon path.
        var beam = [RankedSequence(glyphs: [], confidenceSum: 0, signature: "")]
        var didBeamTruncate = false
        for column in columns {
            var expanded: [RankedSequence] = []
            expanded.reserveCapacity(beam.count * column.count)
            for sequence in beam {
                for candidate in column {
                    expanded.append(RankedSequence(
                        glyphs: sequence.glyphs + [candidate],
                        confidenceSum: sequence.confidenceSum + candidate.confidence,
                        signature: sequence.signature + "\u{0}" + candidate.text
                    ))
                }
            }
            expanded.sort { lhs, rhs in
                if lhs.confidenceSum != rhs.confidenceSum {
                    return lhs.confidenceSum > rhs.confidenceSum
                }
                return lhs.signature < rhs.signature
            }
            if expanded.count > limit {
                expanded.removeSubrange(limit...)
                didBeamTruncate = true
            }
            beam = expanded
        }

        return (beam.map(\.glyphs), didBeamTruncate)
    }

    private func isPreferred(
        _ candidate: ChordInkCandidate,
        over current: ChordInkCandidate
    ) -> Bool {
        if candidate.confidence != current.confidence {
            return candidate.confidence > current.confidence
        }

        // Complete sequences are visited before recovery prefixes. Preserve
        // that priority for the vanishingly rare exact-score collision.
        guard candidate.glyphCandidates.count == current.glyphCandidates.count else {
            return false
        }

        let candidateSum = candidate.glyphCandidates.map(\.confidence).reduce(0, +)
        let currentSum = current.glyphCandidates.map(\.confidence).reduce(0, +)
        if candidateSum != currentSum {
            return candidateSum > currentSum
        }

        let candidateSignature = candidate.glyphCandidates
            .map(\.text)
            .joined(separator: "\u{0}")
        let currentSignature = current.glyphCandidates
            .map(\.text)
            .joined(separator: "\u{0}")
        return candidateSignature < currentSignature
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
