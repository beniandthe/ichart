import Foundation

/// Grammar-constrained complete-token hypotheses from full generic categorical
/// distributions. This decoder has no ownership, recognition, rendering, or
/// trust authority. In particular, personal residual scores are not categorical
/// probabilities and must never be passed through this API.
struct PersonalInkMLCanonicalProbabilityDecoder {
    static let version = "canonical-probability-lattice-v2-chord-domain-v1"
    static let tiePolicy = "joint-log-probability-descending/position-vector-lexicographic-v1"
    static let maximumSearchBudget = 4_096
    static let maximumCandidateBudget = 4_096
    static let maximumSourceStrokeCount = 64
    static let maximumColumnCount = 16
    static let maximumDistributionCount = 512
    static let distributionSumTolerance = 1e-8
    /// Deliberately conservative deterministic guard against emitting a ranking
    /// certificate for a floating-point near tie. This is a policy tolerance,
    /// not a rigorous interval-arithmetic error bound.
    static let certificateRoundoffGuardPerExaminedPath = 1e-12

    struct TokenProbability: Codable, Equatable {
        let label: String
        let probability: Double

        init(_ label: String, probability: Double) {
            self.label = label
            self.probability = probability
        }
    }

    struct Column: Codable, Equatable {
        let originalStrokeIndexes: [Int]
        let probabilities: [TokenProbability]
    }

    struct PathReceipt: Codable, Equatable {
        let tokens: [String]
        /// Indexes in each caller-provided probability array before sorting and
        /// before zero-probability entries are excluded.
        let selectedSourceProbabilityIndexes: [Int]
        /// Zero-based ranks after sorting the positive categorical probabilities.
        let selectedProbabilityRanks: [Int]
        let originalStrokeIndexGroups: [[Int]]
        let selectedInputProbabilities: [Double]
        /// Whole-column normalization only corrects accepted floating-point sum
        /// drift. It never renormalizes grammar-valid survivors.
        let selectedCategoricalProbabilities: [Double]
        let jointLogProbability: Double
        let jointProbability: Double
    }

    struct Candidate: Codable, Equatable {
        let text: String
        /// Probability mass observed for this canonical chord among examined
        /// complete paths. This is a lower bound when search is incomplete.
        let probabilityLowerBound: Double
        /// The conservative upper bound assigns all unexamined mass to this chord.
        let probabilityUpperBound: Double
        let observedPathCount: Int
        let paths: [PathReceipt]
    }

    struct RankingCertificate: Codable, Equatable {
        let candidateText: String
        let candidateProbabilityLowerBound: Double
        let strongestAlternativeProbabilityUpperBound: Double
        /// A conservative policy tolerance used to suppress numerical near-tie
        /// certificates. It is not a formal floating-point error interval.
        let numericalComparisonGuard: Double
        let assertion: String
    }

    struct Result: Codable, Equatable {
        let version: String
        /// True means only that the caller supplied a complete, disjoint
        /// partition of indexes `0..<sourceStrokeCount`.
        let sourcePartitionCoverageValidated: Bool
        /// This decoder has no evidence that the supplied partition represents
        /// the correct visual ownership or column order.
        let sourceOwnershipVerifiedByDecoder: Bool
        let readingOrderVerifiedByDecoder: Bool
        let candidates: [Candidate]
        /// Canonical candidates observed in the examined paths but omitted only
        /// because of `maximumReturnedCandidates`.
        let observedOmittedCandidates: [Candidate]
        let examinedSequenceCount: Int
        /// Nil means the positive-probability Cartesian universe overflowed
        /// UInt64. Valid input is not rejected for that bookkeeping overflow.
        let totalSequenceCount: UInt64?
        let totalSequenceCountOverflowed: Bool
        let searchComplete: Bool
        let truncated: Bool
        let examinedProbabilityMass: Double
        let rejectedGrammarProbabilityMass: Double
        let observedAcceptedProbabilityMass: Double
        /// Conservative bound required by the categorical contract. No grammar-
        /// survivor renormalization is performed.
        let unexaminedProbabilityMassUpperBound: Double
        let observedOmittedCanonicalCandidateCount: Int
        let observedOmittedProbabilityMass: Double
        let rankingCertificate: RankingCertificate?
        let maximumExaminedSequences: Int
        let maximumReturnedCandidates: Int
        let tiePolicy: String
        let assuranceNote: String
    }

    enum Failure: Error, Equatable {
        case invalidSourceStrokeCount
        case invalidColumnCount
        case invalidDistribution(columnIndex: Int)
        case invalidPartition
        case invalidSearchLimits
        case nonFiniteSequenceScore
    }

    func decode(
        sourceStrokeCount: Int,
        orderedColumns: [Column],
        maximumExaminedSequences: Int = Self.maximumSearchBudget,
        maximumReturnedCandidates: Int = 16
    ) throws -> Result {
        guard (1...Self.maximumSourceStrokeCount).contains(sourceStrokeCount) else {
            throw Failure.invalidSourceStrokeCount
        }
        guard (1...Self.maximumColumnCount).contains(orderedColumns.count) else {
            throw Failure.invalidColumnCount
        }
        guard (1...Self.maximumSearchBudget).contains(maximumExaminedSequences),
              (1...Self.maximumCandidateBudget).contains(maximumReturnedCandidates) else {
            throw Failure.invalidSearchLimits
        }

        let sourceIndexes = orderedColumns.flatMap(\.originalStrokeIndexes)
        guard orderedColumns.allSatisfy({ !$0.originalStrokeIndexes.isEmpty }),
              sourceIndexes.count == sourceStrokeCount,
              sourceIndexes.allSatisfy({ (0..<sourceStrokeCount).contains($0) }),
              Set(sourceIndexes).count == sourceStrokeCount else {
            throw Failure.invalidPartition
        }
        let sourceGroups = orderedColumns.map { $0.originalStrokeIndexes.sorted() }
        let columns = try orderedColumns.enumerated().map { columnIndex, column in
            try Self.rankedTokens(in: column, columnIndex: columnIndex)
        }
        // Reader projection is fail-closed at the column winner. An illegal raw
        // winner cannot be discarded in favor of a lower-probability legal
        // token, because that would turn rejected model mass into an apparent
        // chord read. The complete categorical lattice is still traversed so
        // its original examined, rejected, and unexamined mass remains auditable.
        let containsForbiddenColumnWinner = columns.contains { ranks in
            ChordRecognitionDomain.projectTopRanked(ranks) { $0.label }.isEmpty
        }
        let totalSequenceCount = Self.exactSequenceCount(columns.map(\.count))
        let totalSequenceCountOverflowed = totalSequenceCount == nil
        let initialPositions = Array(repeating: 0, count: columns.count)
        var frontier = SequenceHeap()
        frontier.insert(Sequence(
            positions: initialPositions,
            jointLogProbability: try Self.jointLogProbability(
                positions: initialPositions,
                columns: columns
            )
        ))
        var discovered: Set<[Int]> = [initialPositions]
        var examinedSequenceCount = 0
        var acceptedLogMass = -Double.infinity
        var rejectedLogMass = -Double.infinity
        var aggregates: [String: CanonicalAggregate] = [:]

        while examinedSequenceCount < maximumExaminedSequences,
              let sequence = frontier.removeFirst() {
            examinedSequenceCount += 1
            let selected = columns.indices.map { columns[$0][sequence.positions[$0]] }
            let tokens = selected.map(\.label)
            let containsIgnoredToken = tokens.contains { token in
                token.unicodeScalars.contains {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                        || CharacterSet.controlCharacters.contains($0)
                }
            }
            let containsForbiddenToken = tokens.contains {
                !ChordRecognitionDomain.isAllowedGlyphToken($0)
            }
            let jointProbability = Self.probability(fromLog: sequence.jointLogProbability)
            let receipt = PathReceipt(
                tokens: tokens,
                selectedSourceProbabilityIndexes: selected.map(\.sourceProbabilityIndex),
                selectedProbabilityRanks: selected.map(\.probabilityRank),
                originalStrokeIndexGroups: sourceGroups,
                selectedInputProbabilities: selected.map(\.inputProbability),
                selectedCategoricalProbabilities: selected.map(\.categoricalProbability),
                jointLogProbability: sequence.jointLogProbability,
                jointProbability: jointProbability
            )

            if !containsForbiddenColumnWinner,
               !containsIgnoredToken,
               !containsForbiddenToken,
               let symbol = try? ChordSymbolParser.parse(tokens.joined()) {
                acceptedLogMass = Self.logSumExp(acceptedLogMass, sequence.jointLogProbability)
                let canonicalText = symbol.displayText
                if var aggregate = aggregates[canonicalText] {
                    aggregate.observedLogMass = Self.logSumExp(
                        aggregate.observedLogMass,
                        sequence.jointLogProbability
                    )
                    aggregate.paths.append(receipt)
                    aggregates[canonicalText] = aggregate
                } else {
                    aggregates[canonicalText] = CanonicalAggregate(
                        text: canonicalText,
                        observedLogMass: sequence.jointLogProbability,
                        paths: [receipt]
                    )
                }
            } else {
                rejectedLogMass = Self.logSumExp(rejectedLogMass, sequence.jointLogProbability)
            }

            guard examinedSequenceCount < maximumExaminedSequences else { break }
            for columnIndex in columns.indices {
                var neighbor = sequence.positions
                neighbor[columnIndex] += 1
                guard neighbor[columnIndex] < columns[columnIndex].count,
                      discovered.insert(neighbor).inserted else {
                    continue
                }
                frontier.insert(Sequence(
                    positions: neighbor,
                    jointLogProbability: try Self.jointLogProbability(
                        positions: neighbor,
                        columns: columns
                    )
                ))
            }
        }

        let searchComplete = totalSequenceCount.map {
            $0 == UInt64(examinedSequenceCount)
        } ?? false
        let observedAcceptedProbabilityMass = Self.probability(fromLog: acceptedLogMass)
        let rejectedGrammarProbabilityMass = Self.probability(fromLog: rejectedLogMass)
        let examinedProbabilityMass = min(
            1,
            observedAcceptedProbabilityMass + rejectedGrammarProbabilityMass
        )
        let unexaminedProbabilityMassUpperBound = max(0, 1 - examinedProbabilityMass)

        let allCandidates = aggregates.values
            .sorted { left, right in
                if left.observedLogMass != right.observedLogMass {
                    return left.observedLogMass > right.observedLogMass
                }
                return left.text < right.text
            }
            .map {
                Self.candidate(
                    from: $0,
                    unexaminedProbabilityMassUpperBound: unexaminedProbabilityMassUpperBound
                )
            }
        let candidates = Array(allCandidates.prefix(maximumReturnedCandidates))
        let observedOmittedCandidates = Array(allCandidates.dropFirst(maximumReturnedCandidates))
        let observedOmittedProbabilityMass = observedOmittedCandidates.reduce(0) {
            $0 + $1.probabilityLowerBound
        }
        let rankingCertificate = Self.rankingCertificate(
            for: allCandidates,
            unexaminedProbabilityMassUpperBound: unexaminedProbabilityMassUpperBound,
            examinedSequenceCount: examinedSequenceCount
        )

        return Result(
            version: Self.version,
            sourcePartitionCoverageValidated: true,
            sourceOwnershipVerifiedByDecoder: false,
            readingOrderVerifiedByDecoder: false,
            candidates: candidates,
            observedOmittedCandidates: observedOmittedCandidates,
            examinedSequenceCount: examinedSequenceCount,
            totalSequenceCount: totalSequenceCount,
            totalSequenceCountOverflowed: totalSequenceCountOverflowed,
            searchComplete: searchComplete,
            truncated: !searchComplete || !observedOmittedCandidates.isEmpty,
            examinedProbabilityMass: examinedProbabilityMass,
            rejectedGrammarProbabilityMass: rejectedGrammarProbabilityMass,
            observedAcceptedProbabilityMass: observedAcceptedProbabilityMass,
            unexaminedProbabilityMassUpperBound: unexaminedProbabilityMassUpperBound,
            observedOmittedCanonicalCandidateCount: observedOmittedCandidates.count,
            observedOmittedProbabilityMass: observedOmittedProbabilityMass,
            rankingCertificate: rankingCertificate,
            maximumExaminedSequences: maximumExaminedSequences,
            maximumReturnedCandidates: maximumReturnedCandidates,
            tiePolicy: Self.tiePolicy,
            assuranceNote: "Generic categorical probabilities only. Joint path mass is the conditional-independence product of the caller's declared per-column distributions; it is not calibrated chord probability or confidence. Complete source coverage validates neither ownership nor reading order. The parser is applied only to complete token paths. An out-of-domain raw column winner blocks every accepted path rather than promoting a lower-ranked legal token. Out-of-domain and blocked path mass remains in rejectedGrammarProbabilityMass; grammar-valid survivor mass is not renormalized. Candidate lower bounds contain examined canonical mass only; candidate upper bounds conservatively add every unexamined path. A ranking certificate proves only the declared mass inequality after a conservative numerical near-tie guard, not correctness, calibration, ownership, or trust."
        )
    }

    private struct RankedToken {
        let label: String
        let inputProbability: Double
        let categoricalProbability: Double
        let sourceProbabilityIndex: Int
        let probabilityRank: Int
    }

    private struct CanonicalAggregate {
        let text: String
        var observedLogMass: Double
        var paths: [PathReceipt]
    }

    private struct Sequence {
        let positions: [Int]
        let jointLogProbability: Double

        static func precedes(_ left: Self, _ right: Self) -> Bool {
            if left.jointLogProbability != right.jointLogProbability {
                return left.jointLogProbability > right.jointLogProbability
            }
            return left.positions.lexicographicallyPrecedes(right.positions)
        }
    }

    private static func rankedTokens(
        in column: Column,
        columnIndex: Int
    ) throws -> [RankedToken] {
        guard (1...Self.maximumDistributionCount).contains(column.probabilities.count) else {
            throw Failure.invalidDistribution(columnIndex: columnIndex)
        }
        var labels = Set<String>()
        var sum = 0.0
        var compensation = 0.0
        for item in column.probabilities {
            let normalized = item.label.precomposedStringWithCanonicalMapping
            guard item.label.count == 1,
                  item.label.unicodeScalars.count == 1,
                  item.label == normalized,
                  labels.insert(item.label).inserted,
                  item.probability.isFinite,
                  (0...1).contains(item.probability) else {
                throw Failure.invalidDistribution(columnIndex: columnIndex)
            }
            let adjusted = item.probability - compensation
            let next = sum + adjusted
            compensation = (next - sum) - adjusted
            sum = next
        }
        guard sum.isFinite,
              abs(sum - 1) <= Self.distributionSumTolerance else {
            throw Failure.invalidDistribution(columnIndex: columnIndex)
        }

        // Normalize the complete declared categorical distribution only to
        // remove accepted floating-point sum drift. This happens before grammar
        // evaluation and never reallocates mass among grammar-valid survivors.
        let positive = column.probabilities.enumerated().compactMap { index, item
            -> (label: String, inputProbability: Double, categoricalProbability: Double,
                sourceProbabilityIndex: Int)? in
            guard item.probability > 0 else { return nil }
            return (
                label: item.label,
                inputProbability: item.probability,
                categoricalProbability: item.probability / sum,
                sourceProbabilityIndex: index
            )
        }.sorted { left, right in
            if left.categoricalProbability != right.categoricalProbability {
                return left.categoricalProbability > right.categoricalProbability
            }
            if left.label != right.label { return left.label < right.label }
            return left.sourceProbabilityIndex < right.sourceProbabilityIndex
        }
        guard !positive.isEmpty else {
            throw Failure.invalidDistribution(columnIndex: columnIndex)
        }
        return positive.enumerated().map { rank, item in
            RankedToken(
                label: item.label,
                inputProbability: item.inputProbability,
                categoricalProbability: item.categoricalProbability,
                sourceProbabilityIndex: item.sourceProbabilityIndex,
                probabilityRank: rank
            )
        }
    }

    private static func exactSequenceCount(_ counts: [Int]) -> UInt64? {
        var result: UInt64 = 1
        for count in counts {
            let (next, overflow) = result.multipliedReportingOverflow(by: UInt64(count))
            if overflow { return nil }
            result = next
        }
        return result
    }

    private static func jointLogProbability(
        positions: [Int],
        columns: [[RankedToken]]
    ) throws -> Double {
        var sum = 0.0
        for index in columns.indices {
            sum += log(columns[index][positions[index]].categoricalProbability)
            guard sum.isFinite else { throw Failure.nonFiniteSequenceScore }
        }
        return sum
    }

    private static func candidate(
        from aggregate: CanonicalAggregate,
        unexaminedProbabilityMassUpperBound: Double
    ) -> Candidate {
        let lower = probability(fromLog: aggregate.observedLogMass)
        let paths = aggregate.paths.sorted { left, right in
            if left.jointLogProbability != right.jointLogProbability {
                return left.jointLogProbability > right.jointLogProbability
            }
            if left.selectedProbabilityRanks != right.selectedProbabilityRanks {
                return left.selectedProbabilityRanks.lexicographicallyPrecedes(
                    right.selectedProbabilityRanks
                )
            }
            return left.tokens.lexicographicallyPrecedes(right.tokens)
        }
        return Candidate(
            text: aggregate.text,
            probabilityLowerBound: lower,
            probabilityUpperBound: min(1, lower + unexaminedProbabilityMassUpperBound),
            observedPathCount: paths.count,
            paths: paths
        )
    }

    private static func rankingCertificate(
        for candidates: [Candidate],
        unexaminedProbabilityMassUpperBound: Double,
        examinedSequenceCount: Int
    ) -> RankingCertificate? {
        guard let leading = candidates.first else { return nil }
        let strongestObservedAlternative = candidates.dropFirst()
            .map(\.probabilityUpperBound)
            .max() ?? 0
        let strongestAlternativeUpperBound = max(
            strongestObservedAlternative,
            unexaminedProbabilityMassUpperBound
        )
        let numericalComparisonGuard = Double(examinedSequenceCount)
            * Self.certificateRoundoffGuardPerExaminedPath
        guard leading.probabilityLowerBound
                > strongestAlternativeUpperBound + numericalComparisonGuard else {
            return nil
        }
        return RankingCertificate(
            candidateText: leading.text,
            candidateProbabilityLowerBound: leading.probabilityLowerBound,
            strongestAlternativeProbabilityUpperBound: strongestAlternativeUpperBound,
            numericalComparisonGuard: numericalComparisonGuard,
            assertion: "The leading candidate's examined probability-mass lower bound exceeds every other observed or wholly unobserved candidate's conservative upper bound plus the disclosed numerical comparison guard. This certifies ranking only, not recognition correctness, calibration, ownership, or trust."
        )
    }

    private static func probability(fromLog value: Double) -> Double {
        guard value != -Double.infinity else { return 0 }
        return exp(value)
    }

    private static func logSumExp(_ left: Double, _ right: Double) -> Double {
        if left == -Double.infinity { return right }
        if right == -Double.infinity { return left }
        let high = max(left, right)
        let low = min(left, right)
        return high + log1p(exp(low - high))
    }

    private struct SequenceHeap {
        private var values: [Sequence] = []

        mutating func insert(_ sequence: Sequence) {
            values.append(sequence)
            var index = values.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard Sequence.precedes(values[index], values[parent]) else { break }
                values.swapAt(index, parent)
                index = parent
            }
        }

        mutating func removeFirst() -> Sequence? {
            guard let first = values.first else { return nil }
            let last = values.removeLast()
            guard !values.isEmpty else { return first }
            values[0] = last
            var index = 0
            while true {
                let left = 2 * index + 1
                guard left < values.count else { break }
                let right = left + 1
                let preferredChild = right < values.count
                    && Sequence.precedes(values[right], values[left]) ? right : left
                guard Sequence.precedes(values[preferredChild], values[index]) else { break }
                values.swapAt(index, preferredChild)
                index = preferredChild
            }
            return first
        }
    }
}
