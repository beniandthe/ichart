import Foundation

/// Complete-token hypotheses conditional on the supplied source partition and
/// column order. Neither the partition nor reading order is verified here.
/// Raw learned scores rank hypotheses; they are not probabilities or trust.
struct PersonalInkMLChordComposer {
    static let version = "conditional-complete-token-lattice-v2-chord-domain-v1"
    static let tiePolicy = "raw-additive-descending/internal-rank-position-lexicographic-v1"
    static let maximumSearchBudget = 4_096
    static let maximumCandidateBudget = 16

    struct Column: Codable, Equatable {
        let originalStrokeIndexes: [Int]
        let ranks: [PersonalInkLearnedComparison.Rank]
    }

    struct Candidate: Codable, Equatable {
        let text: String
        let tokens: [String]
        /// Indexes in the caller's original rank arrays, before internal sorting.
        let selectedRankIndexes: [Int]
        let originalStrokeIndexGroups: [[Int]]
        let rawAdditiveScore: Double
    }

    struct Result: Codable, Equatable {
        let version: String
        let candidates: [Candidate]
        let examinedSequenceCount: Int
        /// The complete Cartesian universe of the supplied retained ranks only.
        let totalSequenceCount: Int
        let searchComplete: Bool
        /// True when either the search budget or the result cap omits evidence.
        let truncated: Bool
        let rejectedCompleteSequenceCount: Int
        let maximumExaminedSequences: Int
        let assuranceNote: String
        /// Valid examined sequences omitted solely because of the candidate cap.
        /// Unexamined validity is unknown when `searchComplete` is false.
        let omittedCandidates: Bool
        let tiePolicy: String
    }

    enum Failure: Error, Equatable {
        case invalidSourceStrokeCount
        case invalidColumnCount
        case invalidRanks
        case invalidPartition
        case invalidSearchLimits
        case nonFiniteSequenceScore
    }

    func compose(
        sourceStrokeCount: Int,
        orderedColumns: [Column],
        maximumExaminedSequences: Int = 4_096,
        maximumCandidates: Int = 3
    ) throws -> Result {
        guard (1...64).contains(sourceStrokeCount) else {
            throw Failure.invalidSourceStrokeCount
        }
        guard (1...16).contains(orderedColumns.count) else {
            throw Failure.invalidColumnCount
        }
        guard (1...Self.maximumSearchBudget).contains(maximumExaminedSequences),
              (1...Self.maximumCandidateBudget).contains(maximumCandidates) else {
            throw Failure.invalidSearchLimits
        }

        let indexes = orderedColumns.flatMap(\.originalStrokeIndexes)
        guard orderedColumns.allSatisfy({ !$0.originalStrokeIndexes.isEmpty }),
              indexes.count == sourceStrokeCount,
              indexes.allSatisfy({ (0..<sourceStrokeCount).contains($0) }),
              Set(indexes).count == sourceStrokeCount else {
            throw Failure.invalidPartition
        }
        let sourceGroups = orderedColumns.map { $0.originalStrokeIndexes.sorted() }
        let scoreMagnitudeLimit = Double.greatestFiniteMagnitude / Double(orderedColumns.count)
        let columns = try orderedColumns.map { column -> [RankedToken] in
            guard (1...3).contains(column.ranks.count),
                  Set(column.ranks.map(\.label)).count == column.ranks.count,
                  column.ranks.allSatisfy({ rank in
                      let normalized = rank.label.precomposedStringWithCanonicalMapping
                      return rank.label.unicodeScalars.count == 1
                          && Array(rank.label.unicodeScalars) == Array(normalized.unicodeScalars)
                          && rank.score.isFinite
                          && abs(rank.score) <= scoreMagnitudeLimit
                  }) else {
                throw Failure.invalidRanks
            }
            return column.ranks.enumerated().map { index, rank in
                RankedToken(label: rank.label, score: rank.score, originalRankIndex: index)
            }.sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                if left.label != right.label { return left.label < right.label }
                return left.originalRankIndex < right.originalRankIndex
            }
        }
        // Keep the complete caller-supplied lattice for receipts. If the true
        // top rank in any column is outside the chord domain, every complete
        // path remains rejected; a lower legal rank must never be promoted by
        // deleting the written column or the model's actual winner.
        let hasForbiddenTopRank = columns.contains { ranks in
            ChordRecognitionDomain.projectTopRanked(ranks) { $0.label }.isEmpty
        }

        // At most 3^16 sequences, so this product is representable in Int.
        let totalSequenceCount = columns.reduce(1) { $0 * $1.count }
        let examinationLimit = min(maximumExaminedSequences, totalSequenceCount)
        let initialPositions = Array(repeating: 0, count: columns.count)
        var frontier = SequenceHeap()
        frontier.insert(Sequence(
            positions: initialPositions,
            rawAdditiveScore: try Self.additiveScore(positions: initialPositions, columns: columns)
        ))
        var discovered: Set<[Int]> = [initialPositions]
        var candidates: [Candidate] = []
        var examinedSequenceCount = 0
        var rejectedCompleteSequenceCount = 0
        var omittedCandidates = false

        while examinedSequenceCount < examinationLimit, let sequence = frontier.removeFirst() {
            examinedSequenceCount += 1
            let selected = columns.indices.map { columns[$0][sequence.positions[$0]] }
            let tokens = selected.map(\.label)
            let rawText = tokens.joined()
            // The parser intentionally accepts textual whitespace. A symbol
            // column cannot be silently discarded as formatting by this path.
            let containsIgnoredToken = tokens.contains { token in
                token.unicodeScalars.contains {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                        || CharacterSet.controlCharacters.contains($0)
                }
            }
            let containsForbiddenToken = tokens.contains {
                !ChordRecognitionDomain.isAllowedGlyphToken($0)
            }
            if !hasForbiddenTopRank,
               !containsIgnoredToken,
               !containsForbiddenToken,
               let symbol = try? ChordSymbolParser.parse(rawText) {
                if candidates.count < maximumCandidates {
                    candidates.append(Candidate(
                        text: symbol.displayText,
                        tokens: tokens,
                        selectedRankIndexes: selected.map(\.originalRankIndex),
                        originalStrokeIndexGroups: sourceGroups,
                        rawAdditiveScore: sequence.rawAdditiveScore
                    ))
                } else {
                    omittedCandidates = true
                }
            } else {
                rejectedCompleteSequenceCount += 1
            }

            guard examinedSequenceCount < examinationLimit else { break }
            for columnIndex in columns.indices {
                var neighbor = sequence.positions
                neighbor[columnIndex] += 1
                guard neighbor[columnIndex] < columns[columnIndex].count,
                      discovered.insert(neighbor).inserted else { continue }
                frontier.insert(Sequence(
                    positions: neighbor,
                    rawAdditiveScore: try Self.additiveScore(positions: neighbor, columns: columns)
                ))
            }
        }

        let searchComplete = examinedSequenceCount == totalSequenceCount
        return Result(
            version: Self.version,
            candidates: candidates,
            examinedSequenceCount: examinedSequenceCount,
            totalSequenceCount: totalSequenceCount,
            searchComplete: searchComplete,
            truncated: !searchComplete || omittedCandidates,
            rejectedCompleteSequenceCount: rejectedCompleteSequenceCount,
            maximumExaminedSequences: maximumExaminedSequences,
            assuranceNote: "Conditional hypotheses over supplied retained ranks only. Complete source coverage does not verify ownership or the supplied reading order. Raw additive scores are uncalibrated rankings, not probabilities, confidence, or acceptance. Out-of-domain token paths are rejected without score renormalization, and an out-of-domain raw winner blocks lower-rank promotion for the complete composition. Grammar validity does not resolve ownership or establish a correct read. Canonical aliases retain separate raw token and rank receipts. Omitted candidates concern examined valid sequences only; unexamined validity is unknown when search is incomplete.",
            omittedCandidates: omittedCandidates,
            tiePolicy: Self.tiePolicy
        )
    }

    private struct RankedToken {
        let label: String
        let score: Double
        let originalRankIndex: Int
    }

    private struct Sequence {
        let positions: [Int]
        let rawAdditiveScore: Double

        static func precedes(_ left: Self, _ right: Self) -> Bool {
            if left.rawAdditiveScore != right.rawAdditiveScore {
                return left.rawAdditiveScore > right.rawAdditiveScore
            }
            return left.positions.lexicographicallyPrecedes(right.positions)
        }
    }

    private static func additiveScore(positions: [Int], columns: [[RankedToken]]) throws -> Double {
        var sum = 0.0
        for columnIndex in columns.indices {
            sum += columns[columnIndex][positions[columnIndex]].score
            guard sum.isFinite else { throw Failure.nonFiniteSequenceScore }
        }
        return sum
    }

    /// Every neighbor advances one internally sorted rank position. Its score
    /// cannot increase, and its position vector sorts after its predecessor
    /// even when finite floating-point addition rounds the scores to a tie.
    /// Therefore the frontier emits exact descending-score/vector order without
    /// treating raw token spelling as an undiscovered equal-score tie breaker.
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
