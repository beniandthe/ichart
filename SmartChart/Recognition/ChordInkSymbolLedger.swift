import Foundation

enum ChordInkSymbolStabilityReason: String, Codable, Hashable {
    case nextInkToRight
    case idleSettled
    case unresolvedOverlap
}

struct ChordInkSymbolCandidate: Codable, Hashable {
    var text: String
    var confidence: Double
    var source: RecognitionSource

    init(_ candidate: GlyphCandidate) {
        self.text = candidate.text
        self.confidence = candidate.confidence
        self.source = candidate.source
    }
}

struct ChordInkStableSymbol: Codable, Hashable {
    var index: Int
    var bounds: InkBounds
    var stabilityReason: ChordInkSymbolStabilityReason
    var candidates: [ChordInkSymbolCandidate]

    var bestText: String? {
        candidates.first?.text
    }
}

struct ChordInkRunningPrefix: Codable, Hashable {
    var symbolCount: Int
    var text: String
    var displayText: String?
    var supportedDisplayTexts: [String] = []

    var isSupported: Bool {
        displayText != nil || !supportedDisplayTexts.isEmpty
    }
}

struct ChordInkSymbolLedgerSnapshot: Codable, Hashable {
    var stableSymbols: [ChordInkStableSymbol]
    var runningPrefixes: [ChordInkRunningPrefix]
    var finalCandidateText: String?
    var finalCandidateDisplayText: String?

    var stableText: String {
        stableSymbols.compactMap(\.bestText).joined()
    }
}

struct ChordInkSymbolLedger {
    var candidateComposer: ChordInkCandidateComposer = ChordInkCandidateComposer()
    var maxCandidatesPerSymbol: Int = 5
    var maxSupportedPrefixesPerSymbol: Int = 5
    var minimumGapForNextInkStability: Double = 4
    var maximumOverlapForNextInkStability: Double = 2

    func snapshot(
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster],
        chordCandidates: [ChordInkCandidate]
    ) -> ChordInkSymbolLedgerSnapshot {
        let stableSymbols = stableSymbols(
            glyphCandidateGroups: glyphCandidateGroups,
            clusters: clusters
        )

        return ChordInkSymbolLedgerSnapshot(
            stableSymbols: stableSymbols,
            runningPrefixes: runningPrefixes(from: stableSymbols),
            finalCandidateText: chordCandidates.first?.text,
            finalCandidateDisplayText: chordCandidates.first
                .flatMap { ChordRecognitionCompendium.match($0.text)?.displayText }
        )
    }

    private func stableSymbols(
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkStableSymbol] {
        let count = min(glyphCandidateGroups.count, clusters.count)
        guard count > 0 else {
            return []
        }

        return (0..<count).map { index in
            ChordInkStableSymbol(
                index: index,
                bounds: clusters[index].bounds,
                stabilityReason: stabilityReason(
                    forClusterAt: index,
                    clusters: Array(clusters.prefix(count))
                ),
                candidates: glyphCandidateGroups[index]
                    .sortedByConfidence
                    .prefix(maxCandidatesPerSymbol)
                    .map(ChordInkSymbolCandidate.init)
            )
        }
    }

    private func stabilityReason(
        forClusterAt index: Int,
        clusters: [InkCluster]
    ) -> ChordInkSymbolStabilityReason {
        guard clusters.indices.contains(index + 1) else {
            return .idleSettled
        }

        let current = clusters[index].bounds
        let next = clusters[index + 1].bounds
        let gap = next.minX - current.maxX
        if gap >= minimumGapForNextInkStability {
            return .nextInkToRight
        }

        let overlap = current.maxX - next.minX
        if overlap <= maximumOverlapForNextInkStability {
            return .nextInkToRight
        }

        return .unresolvedOverlap
    }

    private func runningPrefixes(from symbols: [ChordInkStableSymbol]) -> [ChordInkRunningPrefix] {
        var prefixes: [ChordInkRunningPrefix] = []
        var columns: [[GlyphCandidate]] = []

        for symbol in symbols {
            guard !symbol.candidates.isEmpty else {
                continue
            }

            columns.append(
                symbol.candidates.map { candidate in
                    GlyphCandidate(
                        text: candidate.text,
                        confidence: candidate.confidence,
                        source: candidate.source
                    )
                }
            )

            let text = columns.compactMap(\.first?.text).joined()
            let match = ChordRecognitionCompendium.match(text)
            let supportedDisplayTexts = uniqueSupportedDisplayTexts(
                from: candidateComposer.compose(glyphCandidates: columns)
            )
            prefixes.append(
                ChordInkRunningPrefix(
                    symbolCount: symbol.index + 1,
                    text: text,
                    displayText: match?.displayText,
                    supportedDisplayTexts: supportedDisplayTexts
                )
            )
        }

        return prefixes
    }

    private func uniqueSupportedDisplayTexts(from candidates: [ChordInkCandidate]) -> [String] {
        var displayTexts: [String] = []
        for candidate in candidates {
            guard let match = ChordRecognitionCompendium.match(candidate.text),
                  !displayTexts.contains(match.displayText) else {
                continue
            }

            displayTexts.append(match.displayText)
            if displayTexts.count >= maxSupportedPrefixesPerSymbol {
                break
            }
        }

        return displayTexts
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
