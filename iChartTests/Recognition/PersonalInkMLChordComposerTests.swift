import XCTest
@testable import iChart

/// Synthetic rank lattices only. Grammar-valid hypotheses do not establish
/// handwriting identity, ownership, reading order, confidence or correctness.
final class PersonalInkMLChordComposerTests: XCTestCase {
    private typealias Composer = PersonalInkMLChordComposer
    private typealias Column = Composer.Column
    private typealias Rank = PersonalInkLearnedComparison.Rank
    private let composer = Composer()

    private func column(_ index: Int, _ ranks: [(String, Double)]) -> Column {
        .init(originalStrokeIndexes: [index], ranks: ranks.map { .init(label: $0.0, score: $0.1) })
    }
    private func columns(_ tokens: [String]) -> [Column] {
        tokens.enumerated().map { column($0.offset, [($0.element, 1)]) }
    }
    private func failure(_ expected: Composer.Failure, sourceCount: Int, columns: [Column],
                         budget: Int = 4096, cap: Int = 3,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try composer.compose(sourceStrokeCount: sourceCount, orderedColumns: columns,
            maximumExaminedSequences: budget, maximumCandidates: cap), file: file, line: line) { error in
            XCTAssertEqual(error as? Composer.Failure, expected, file: file, line: line)
        }
    }

    func testForbiddenTopSequenceCannotPromoteACompleteLowerRankHypothesis() throws {
        let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: [
            column(0, [("C", 4)]), column(1, [("ñ", 2), ("7", 1)])
        ])
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.examinedSequenceCount, 2)
        XCTAssertEqual(result.rejectedCompleteSequenceCount, 2)
        XCTAssertTrue(result.searchComplete)
        XCTAssertFalse(result.truncated)
    }

    func testForbiddenLowerRankIsRejectedWithoutChangingLegalScoresOrIndexes() throws {
        let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: [
            column(0, [("C", 4), ("J", 1)]), column(1, [("7", 2)])
        ])
        XCTAssertEqual(result.candidates.map(\.text), ["C7"])
        XCTAssertEqual(result.candidates[0].rawAdditiveScore, 6)
        XCTAssertEqual(result.candidates[0].selectedRankIndexes, [0, 0])
        XCTAssertEqual(result.examinedSequenceCount, 2)
        XCTAssertEqual(result.rejectedCompleteSequenceCount, 1)
    }

    func testValidHighestScoringDifferentRootRemainsFirstWithoutTargetCorrection() throws {
        let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: [
            column(0, [("A", 3), ("C", 2)]), column(1, [("7", 1)])
        ])
        XCTAssertEqual(result.candidates.map(\.text), ["A7", "C7"])
        XCTAssertEqual(result.candidates.map(\.tokens), [["A", "7"], ["C", "7"]])
        XCTAssertEqual(result.candidates.map(\.rawAdditiveScore), [4, 3])
        XCTAssertEqual(result.rejectedCompleteSequenceCount, 0)
    }

    func testGeneralRootsAndQualityWordsAreAvailableWithoutPersonalVocabulary() throws {
        for root in ["A", "B", "C", "D", "E", "F", "G"] {
            for suffix in ["", "maj7", "sus4", "13", "m7/C#"] {
                let raw = root + suffix
                let tokens = raw.map(String.init)
                let result = try composer.compose(sourceStrokeCount: tokens.count, orderedColumns: columns(tokens))
                XCTAssertEqual(result.candidates.first?.text, try ChordSymbolParser.parse(raw).displayText, raw)
                XCTAssertEqual(result.candidates.first?.tokens, tokens, raw)
                XCTAssertEqual(result.examinedSequenceCount, 1, raw)
                XCTAssertTrue(result.searchComplete, raw)
            }
        }
    }

    func testCompleteCoverageRetainsEveryWrapperTokenAndDeclaredColumnOrder() throws {
        let tokens = "Db7(b9)/F#".map(String.init)
        let supplied = tokens.enumerated().map { index, token in
            Column(originalStrokeIndexes: index == 0 ? [1, 0] : [index + 1],
                   ranks: [.init(label: token, score: 1)])
        }
        let result = try composer.compose(sourceStrokeCount: tokens.count + 1, orderedColumns: supplied)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.text, try ChordSymbolParser.parse(tokens.joined()).displayText)
        XCTAssertEqual(candidate.tokens, tokens)
        XCTAssertEqual(candidate.originalStrokeIndexGroups, [[0, 1]] + (2...tokens.count).map { [$0] })
        XCTAssertEqual(candidate.originalStrokeIndexGroups.flatMap { $0 }, Array(0...tokens.count))
        XCTAssertEqual(candidate.selectedRankIndexes, Array(repeating: 0, count: tokens.count))
        XCTAssertTrue(result.assuranceNote.contains("does not verify ownership"))
        XCTAssertTrue(result.assuranceNote.contains("uncalibrated rankings"))
        XCTAssertTrue(result.assuranceNote.contains("does not resolve ownership"))
    }

    func testSourceCountColumnCountAndPartitionValidationRejectMissingOrRepeatedSource() {
        for sourceCount in [0, -1, 65, Int.max] {
            failure(.invalidSourceStrokeCount, sourceCount: sourceCount, columns: columns(["C"]))
        }
        failure(.invalidColumnCount, sourceCount: 1, columns: [])
        failure(.invalidColumnCount, sourceCount: 17, columns: columns(Array(repeating: "C", count: 17)))
        let rank = [Rank(label: "C", score: 1)]
        for groups in [[[Int]()], [[0, 0]], [[1]], [[-1]], [[0], [0]]] {
            failure(.invalidPartition, sourceCount: 1,
                    columns: groups.map { .init(originalStrokeIndexes: $0, ranks: rank) })
        }
        failure(.invalidPartition, sourceCount: 2, columns: columns(["C"]))
    }

    func testRanksRequireOneToThreeUniqueExactNFCUnicodeScalars() {
        let invalidRanks: [[Rank]] = [
            [], ["A", "B", "C", "D"].map { .init(label: $0, score: 1) },
            [.init(label: "C", score: 1), .init(label: "C", score: 0)],
            [.init(label: "", score: 1)], [.init(label: "C7", score: 1)],
            [.init(label: "e\u{301}", score: 1)], [.init(label: "👩‍🎤", score: 1)]
        ]
        for ranks in invalidRanks {
            failure(.invalidRanks, sourceCount: 1, columns: [.init(originalStrokeIndexes: [0], ranks: ranks)])
        }
    }

    func testCompleteSequenceParsingCannotDropPunctuationWhitespaceOrControlColumns() throws {
        for tail in [">", "!", "?", " ", "\n", "\u{0000}", "/"] {
            let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: columns(["C", tail]))
            XCTAssertTrue(result.candidates.isEmpty, tail.debugDescription)
            XCTAssertEqual(result.totalSequenceCount, 1)
            XCTAssertEqual(result.examinedSequenceCount, 1)
            XCTAssertEqual(result.rejectedCompleteSequenceCount, 1)
            XCTAssertTrue(result.searchComplete)
            XCTAssertFalse(result.truncated)
            XCTAssertFalse(result.omittedCandidates)
        }
    }

    func testFiniteZeroNegativeAndGreaterThanOneScoresRemainRawRankings() throws {
        for (rootScore, suffixScore) in [(0.0, 0.0), (-2.0, -3.0), (5.0, -2.0), (2.0, 3.0)] {
            let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: [
                column(0, [("C", rootScore)]), column(1, [("7", suffixScore)])
            ])
            XCTAssertEqual(result.candidates.first?.text, "C7")
            XCTAssertEqual(result.candidates.first?.rawAdditiveScore, rootScore + suffixScore)
        }
    }

    func testNonfiniteAndOverflowRiskScoresFailEvenInAnUnexaminedLowerRank() {
        for score in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            failure(.invalidRanks, sourceCount: 2, columns: [
                column(0, [("C", 2), ("A", score)]), column(1, [("7", 1)])
            ], budget: 1, cap: 1)
        }
    }

    func testNonpositiveAndOversizedSearchLimitsFailBeforeAnySequence() {
        for budget in [0, -1, 4097, Int.max] {
            failure(.invalidSearchLimits, sourceCount: 1, columns: columns(["C"]), budget: budget)
        }
        for cap in [0, -1, 17, Int.max] {
            failure(.invalidSearchLimits, sourceCount: 1, columns: columns(["C"]), cap: cap)
        }
    }

    func testDeterministicTiePolicyUsesInternalPositionVectorAndRetainsIncomingRankIndexes() throws {
        let supplied = [column(0, [("A", 2), ("C", 3)]), column(1, [("9", 1), ("7", 2)])]
        let result = try composer.compose(sourceStrokeCount: 2, orderedColumns: supplied, maximumCandidates: 4)
        // C9 and A7 have equal totals. The internal [0, 1] vector precedes
        // [1, 0], even though the raw token string A7 sorts before C9.
        XCTAssertEqual(result.candidates.map(\.text), ["C7", "C9", "A7", "A9"])
        XCTAssertEqual(result.candidates.map(\.selectedRankIndexes), [[1, 1], [1, 0], [0, 1], [0, 0]])
        XCTAssertEqual(result.candidates.map(\.rawAdditiveScore), [5, 4, 4, 3])
        XCTAssertEqual(result.tiePolicy, "raw-additive-descending/internal-rank-position-lexicographic-v1")
        for _ in 0..<3 {
            XCTAssertEqual(try composer.compose(sourceStrokeCount: 2, orderedColumns: supplied, maximumCandidates: 4), result)
        }
        let withinColumnTie = try composer.compose(sourceStrokeCount: 2, orderedColumns: [
            column(0, [("C", 1), ("A", 1)]), column(1, [("7", 0)])
        ])
        XCTAssertEqual(withinColumnTie.candidates.map(\.text), ["A7", "C7"])
        XCTAssertEqual(withinColumnTie.candidates.map(\.selectedRankIndexes), [[1, 0], [0, 0]])
    }

    func testBudgetResultCapAndCompleteUniverseHaveSeparateReceipts() throws {
        let supplied = [column(0, [("C", 3), ("A", 2)]), column(1, [("7", 2), ("9", 1)])]
        let capped = try composer.compose(sourceStrokeCount: 2, orderedColumns: supplied,
                                          maximumExaminedSequences: 4, maximumCandidates: 1)
        XCTAssertEqual(capped.totalSequenceCount, 4)
        XCTAssertEqual(capped.examinedSequenceCount, 4, "The result cap must not terminate the search")
        XCTAssertEqual(capped.candidates.count, 1)
        XCTAssertEqual(capped.rejectedCompleteSequenceCount, 0)
        XCTAssertTrue(capped.searchComplete)
        XCTAssertTrue(capped.omittedCandidates)
        XCTAssertTrue(capped.truncated)
        let budgeted = try composer.compose(sourceStrokeCount: 2, orderedColumns: supplied,
                                            maximumExaminedSequences: 1, maximumCandidates: 3)
        XCTAssertEqual(budgeted.maximumExaminedSequences, 1)
        XCTAssertEqual(budgeted.totalSequenceCount, 4)
        XCTAssertEqual(budgeted.examinedSequenceCount, 1)
        XCTAssertEqual(budgeted.candidates.count, 1)
        XCTAssertFalse(budgeted.searchComplete)
        XCTAssertFalse(budgeted.omittedCandidates, "Unexamined validity must remain unknown")
        XCTAssertTrue(budgeted.truncated)
        let large = (0..<16).map { column($0, [("A", 3), ("B", 2), ("C", 1)]) }
        let bounded = try composer.compose(sourceStrokeCount: 16, orderedColumns: large,
                                           maximumExaminedSequences: 1, maximumCandidates: 1)
        XCTAssertEqual(bounded.totalSequenceCount, 43_046_721)
        XCTAssertEqual(bounded.examinedSequenceCount, 1)
        XCTAssertFalse(bounded.searchComplete)
        XCTAssertTrue(bounded.truncated)
    }

    func testCanonicalAliasesRetainSeparateRawTokenAndRankReceipts() throws {
        let supplied = [column(0, [("C", 1)]), column(1, [("m", 2), ("-", 1)]), column(2, [("7", 1)])]
        let result = try composer.compose(sourceStrokeCount: 3, orderedColumns: supplied)
        XCTAssertEqual(result.candidates.map(\.text), ["C-7", "C-7"])
        XCTAssertEqual(result.candidates.map(\.tokens), [["C", "m", "7"], ["C", "-", "7"]])
        XCTAssertEqual(result.candidates.map(\.selectedRankIndexes), [[0, 0, 0], [0, 1, 0]])
        XCTAssertEqual(result.examinedSequenceCount, 2)
        XCTAssertFalse(result.omittedCandidates)
        let capped = try composer.compose(sourceStrokeCount: 3, orderedColumns: supplied, maximumCandidates: 1)
        XCTAssertTrue(capped.omittedCandidates)
        XCTAssertTrue(capped.searchComplete)
        XCTAssertTrue(capped.truncated)
    }

    private struct OracleSequence {
        let positions: [Int]
        let originalIndexes: [Int]
        let tokens: [String]
        let score: Double
        var text: String? { (try? ChordSymbolParser.parse(tokens.joined()))?.displayText }
    }

    /// Exhaustive Cartesian enumeration is independent of the production
    /// frontier. It applies the declared rank/vector ordering and strict parse.
    private func exhaustiveOracle(_ supplied: [Column]) -> [OracleSequence] {
        let ranked = supplied.map { column in
            column.ranks.enumerated().sorted { left, right in
                if left.element.score != right.element.score { return left.element.score > right.element.score }
                if left.element.label != right.element.label { return left.element.label < right.element.label }
                return left.offset < right.offset
            }
        }
        var sequences: [OracleSequence] = []
        func visit(_ positions: [Int]) {
            if positions.count == ranked.count {
                let choices = ranked.indices.map { ranked[$0][positions[$0]] }
                sequences.append(.init(positions: positions, originalIndexes: choices.map(\.offset),
                    tokens: choices.map { $0.element.label }, score: choices.reduce(0) { $0 + $1.element.score }))
                return
            }
            for position in ranked[positions.count].indices { visit(positions + [position]) }
        }
        visit([])
        return sequences.sorted {
            $0.score == $1.score ? $0.positions.lexicographicallyPrecedes($1.positions) : $0.score > $1.score
        }
    }

    func testPrioritySearchMatchesFullThreeByFourBruteForceOracleAndEveryBudgetPrefix() throws {
        let supplied = [
            column(0, [("G", 2), ("C", 3), ("A", 3)]),
            column(1, [("m", 2), ("#", 3), ("b", 2)]),
            column(2, [("7", 1), ("1", 3), ("6", 2)]),
            column(3, [("!", 1), ("9", 2), ("3", 3)])
        ]
        let oracle = exhaustiveOracle(supplied)
        XCTAssertEqual(oracle.count, 81)
        XCTAssertTrue(oracle.contains { $0.text != nil })
        XCTAssertTrue(oracle.contains { $0.text == nil })
        for budget in [1, 2, 7, 27, 80, 81, 100] {
            let examined = Array(oracle.prefix(budget))
            let valid = examined.filter { $0.text != nil }
            let result = try composer.compose(sourceStrokeCount: 4, orderedColumns: supplied,
                                              maximumExaminedSequences: budget, maximumCandidates: 16)
            XCTAssertEqual(result.totalSequenceCount, oracle.count)
            XCTAssertEqual(result.examinedSequenceCount, examined.count)
            XCTAssertEqual(result.rejectedCompleteSequenceCount, examined.count - valid.count)
            let returned = Array(valid.prefix(16))
            XCTAssertEqual(result.candidates.map(\.text), returned.compactMap(\.text))
            XCTAssertEqual(result.candidates.map(\.tokens), returned.map(\.tokens))
            XCTAssertEqual(result.candidates.map(\.selectedRankIndexes), returned.map(\.originalIndexes))
            XCTAssertEqual(result.candidates.map(\.rawAdditiveScore), returned.map(\.score))
            XCTAssertTrue(result.candidates.allSatisfy { $0.originalStrokeIndexGroups == [[0], [1], [2], [3]] })
            XCTAssertEqual(result.searchComplete, examined.count == 81)
            XCTAssertEqual(result.truncated, examined.count != 81 || valid.count > 16)
            XCTAssertEqual(result.omittedCandidates, valid.count > 16)
        }
    }
}
