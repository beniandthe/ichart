import XCTest
@testable import iChart

final class PersonalInkMLCanonicalProbabilityDecoderTests: XCTestCase {
    private typealias Decoder = PersonalInkMLCanonicalProbabilityDecoder
    private let decoder = Decoder()

    private func column(
        _ sourceIndexes: [Int],
        _ values: [(String, Double)]
    ) -> Decoder.Column {
        Decoder.Column(
            originalStrokeIndexes: sourceIndexes,
            probabilities: values.map { Decoder.TokenProbability($0.0, probability: $0.1) }
        )
    }

    func testJointProbabilityRankingCorrectsAdditiveProbabilityCounterexample() throws {
        let columns = [
            column([0], [("C", 0.80), ("D", 0.19), ("!", 0.01)]),
            column([1], [("m", 0.10), ("△", 0.40), ("E", 0.50)]),
            column([2], [("7", 0.10), ("9", 0.40), ("F", 0.50)])
        ]
        let additiveMinorSeven = 0.80 + 0.10 + 0.10
        let additiveMajorNine = 0.19 + 0.40 + 0.40
        let jointMinorSeven = 0.80 * 0.10 * 0.10
        let jointMajorNine = 0.19 * 0.40 * 0.40
        XCTAssertGreaterThan(additiveMinorSeven, additiveMajorNine)
        XCTAssertLessThan(jointMinorSeven, jointMajorNine)

        let result = try decoder.decode(
            sourceStrokeCount: 3,
            orderedColumns: columns
        )

        XCTAssertEqual(result.totalSequenceCount, 27)
        XCTAssertTrue(result.searchComplete)
        XCTAssertTrue(result.sourcePartitionCoverageValidated)
        XCTAssertFalse(result.sourceOwnershipVerifiedByDecoder)
        XCTAssertFalse(result.readingOrderVerifiedByDecoder)
        let minorSevenIndex = try XCTUnwrap(result.candidates.firstIndex { $0.text == "C-7" })
        let majorNineIndex = try XCTUnwrap(result.candidates.firstIndex { $0.text == "D△9" })
        XCTAssertLessThan(majorNineIndex, minorSevenIndex)
        XCTAssertEqual(
            try XCTUnwrap(result.candidates.first { $0.text == "C-7" })
                .probabilityLowerBound,
            jointMinorSeven,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try XCTUnwrap(result.candidates.first { $0.text == "D△9" })
                .probabilityLowerBound,
            jointMajorNine,
            accuracy: 1e-12
        )
    }

    func testForbiddenRawWinnerCannotPromoteGrammarValidRankFourToken() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [
                column([0], [("!", 0.40), ("?", 0.30), ("H", 0.20), ("C", 0.10)])
            ]
        )

        XCTAssertEqual(result.totalSequenceCount, 4)
        XCTAssertEqual(result.examinedSequenceCount, 4)
        XCTAssertTrue(result.searchComplete)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 0, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.examinedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0, accuracy: 1e-12)
        XCTAssertNil(result.rankingCertificate)
    }

    func testCanonicalAliasesMergeMassAndRetainEveryRawPathReceipt() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 3,
            orderedColumns: [
                column([0], [("C", 1)]),
                column([1], [("m", 0.60), ("-", 0.40)]),
                column([2], [("7", 1)])
            ]
        )

        XCTAssertEqual(result.candidates.count, 1)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.text, "C-7")
        XCTAssertEqual(candidate.observedPathCount, 2)
        XCTAssertEqual(candidate.probabilityLowerBound, 1, accuracy: 1e-12)
        XCTAssertEqual(candidate.probabilityUpperBound, 1, accuracy: 1e-12)
        XCTAssertEqual(Set(candidate.paths.map(\.tokens)), Set([["C", "m", "7"], ["C", "-", "7"]]))
        XCTAssertEqual(candidate.paths.map(\.originalStrokeIndexGroups), [
            [[0], [1], [2]], [[0], [1], [2]]
        ])
    }

    func testTruncatedSearchAccountsForAcceptedRejectedAndUnexaminedMass() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 2,
            orderedColumns: [
                column([0], [("C", 0.60), ("D", 0.40)]),
                column([1], [("7", 0.60), ("!", 0.40)])
            ],
            maximumExaminedSequences: 2
        )

        XCTAssertEqual(result.totalSequenceCount, 4)
        XCTAssertEqual(result.examinedSequenceCount, 2)
        XCTAssertFalse(result.searchComplete)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 0.36, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 0.24, accuracy: 1e-12)
        XCTAssertEqual(result.examinedProbabilityMass, 0.60, accuracy: 1e-12)
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0.40, accuracy: 1e-12)
        XCTAssertEqual(
            result.observedAcceptedProbabilityMass + result.rejectedGrammarProbabilityMass,
            result.examinedProbabilityMass,
            accuracy: 1e-12
        )
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.text, "C7")
        XCTAssertEqual(candidate.probabilityLowerBound, 0.36, accuracy: 1e-12)
        XCTAssertEqual(candidate.probabilityUpperBound, 0.76, accuracy: 1e-12)
        XCTAssertNil(result.rankingCertificate)
    }

    func testFullyExaminedTinyUniverseHasExactBoundsAndRankingCertificate() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("C", 0.60), ("D", 0.40)])]
        )

        XCTAssertEqual(result.totalSequenceCount, 2)
        XCTAssertEqual(result.examinedSequenceCount, 2)
        XCTAssertTrue(result.searchComplete)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.examinedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 0, accuracy: 1e-12)
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0, accuracy: 1e-12)
        XCTAssertEqual(result.candidates.map(\.text), ["C", "D"])
        XCTAssertEqual(result.candidates[0].probabilityLowerBound, 0.60, accuracy: 1e-12)
        XCTAssertEqual(result.candidates[1].probabilityLowerBound, 0.40, accuracy: 1e-12)
        XCTAssertEqual(result.candidates[0].probabilityUpperBound, 0.60, accuracy: 1e-12)
        XCTAssertEqual(result.candidates[1].probabilityUpperBound, 0.40, accuracy: 1e-12)
        XCTAssertEqual(result.rankingCertificate?.candidateText, "C")
        XCTAssertEqual(
            try XCTUnwrap(result.rankingCertificate).numericalComparisonGuard,
            2e-12,
            accuracy: 1e-18
        )
        XCTAssertEqual(
            try XCTUnwrap(result.rankingCertificate)
                .strongestAlternativeProbabilityUpperBound,
            0.40,
            accuracy: 1e-12
        )
    }

    func testForbiddenRawWinnerBlocksLegalRunnerUpWithoutRenormalizingMass() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("ñ", 0.80), ("C", 0.15), ("J", 0.05)])]
        )

        XCTAssertTrue(result.searchComplete)
        XCTAssertEqual(result.totalSequenceCount, 3)
        XCTAssertEqual(result.examinedSequenceCount, 3)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 0, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.examinedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0, accuracy: 1e-12)
        XCTAssertNil(result.rankingCertificate)
    }

    func testLegalRawWinnerRetainsExactProbabilityWithoutIllegalMassReallocation() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("C", 0.80), ("ñ", 0.15), ("J", 0.05)])]
        )

        XCTAssertEqual(result.version, "canonical-probability-lattice-v2-chord-domain-v1")
        XCTAssertTrue(result.searchComplete)
        XCTAssertEqual(result.totalSequenceCount, 3)
        XCTAssertEqual(result.examinedSequenceCount, 3)
        XCTAssertEqual(result.candidates.map(\.text), ["C"])
        XCTAssertEqual(try XCTUnwrap(result.candidates.first).probabilityLowerBound, 0.80, accuracy: 1e-12)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 0.80, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 0.20, accuracy: 1e-12)
        XCTAssertEqual(result.examinedProbabilityMass, 1, accuracy: 1e-12)
        XCTAssertEqual(result.candidates[0].paths[0].tokens, ["C"])
        XCTAssertEqual(result.candidates[0].paths[0].selectedInputProbabilities, [0.80])
        XCTAssertEqual(result.candidates[0].paths[0].selectedCategoricalProbabilities, [0.80])
        XCTAssertEqual(result.rankingCertificate?.candidateText, "C")
    }

    func testTruncatedForbiddenRawWinnerRetainsRejectedAndUnexaminedMass() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("ñ", 0.60), ("C", 0.25), ("J", 0.15)])],
            maximumExaminedSequences: 1
        )

        XCTAssertEqual(result.totalSequenceCount, 3)
        XCTAssertEqual(result.examinedSequenceCount, 1)
        XCTAssertFalse(result.searchComplete)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.observedAcceptedProbabilityMass, 0, accuracy: 1e-12)
        XCTAssertEqual(result.rejectedGrammarProbabilityMass, 0.60, accuracy: 1e-12)
        XCTAssertEqual(result.examinedProbabilityMass, 0.60, accuracy: 1e-12)
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0.40, accuracy: 1e-12)
        XCTAssertNil(result.rankingCertificate)
    }

    func testAmbiguousUnexaminedTailPreventsRankingCertificate() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [
                column([0], [("C", 0.40), ("D", 0.35), ("E", 0.25)])
            ],
            maximumExaminedSequences: 1
        )

        XCTAssertEqual(result.candidates.first?.text, "C")
        XCTAssertEqual(
            try XCTUnwrap(result.candidates.first).probabilityLowerBound,
            0.40,
            accuracy: 1e-12
        )
        XCTAssertEqual(result.unexaminedProbabilityMassUpperBound, 0.60, accuracy: 1e-12)
        XCTAssertNil(result.rankingCertificate)
    }

    func testNumericalNearTieDoesNotProduceRankingCertificate() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [
                column([0], [("C", 0.500_000_000_000_5), ("D", 0.499_999_999_999_5)])
            ]
        )

        XCTAssertTrue(result.searchComplete)
        XCTAssertEqual(result.candidates.first?.text, "C")
        XCTAssertNil(result.rankingCertificate)
    }

    func testObservedCandidateCapDisclosesOmittedCanonicalMassAndStillAuditsRanking() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("C", 0.60), ("D", 0.40)])],
            maximumReturnedCandidates: 1
        )

        XCTAssertTrue(result.searchComplete)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.candidates.map(\.text), ["C"])
        XCTAssertEqual(result.observedOmittedCandidates.map(\.text), ["D"])
        XCTAssertEqual(result.observedOmittedCanonicalCandidateCount, 1)
        XCTAssertEqual(result.observedOmittedProbabilityMass, 0.40, accuracy: 1e-12)
        XCTAssertEqual(result.rankingCertificate?.candidateText, "C")
        XCTAssertEqual(
            try XCTUnwrap(result.rankingCertificate)
                .strongestAlternativeProbabilityUpperBound,
            0.40,
            accuracy: 1e-12
        )
    }

    func testZeroProbabilityEntriesAreExcludedFromUniverseAndReceipts() throws {
        let result = try decoder.decode(
            sourceStrokeCount: 1,
            orderedColumns: [column([0], [("C", 1), ("D", 0)])]
        )

        XCTAssertEqual(result.totalSequenceCount, 1)
        XCTAssertEqual(result.examinedSequenceCount, 1)
        XCTAssertEqual(result.candidates.map(\.text), ["C"])
        XCTAssertEqual(result.candidates[0].paths[0].selectedSourceProbabilityIndexes, [0])
    }

    func testOverflowingCartesianCountRemainsValidAndBounded() throws {
        let labels = (33..<127).map { String(UnicodeScalar($0)!) } + ["α", "β", "γ"]
        XCTAssertEqual(labels.count, 97)
        let distribution = labels.map {
            Decoder.TokenProbability($0, probability: 1 / Double(labels.count))
        }
        let columns = (0..<16).map {
            Decoder.Column(originalStrokeIndexes: [$0], probabilities: distribution)
        }

        let result = try decoder.decode(
            sourceStrokeCount: 16,
            orderedColumns: columns,
            maximumExaminedSequences: 1
        )

        XCTAssertNil(result.totalSequenceCount)
        XCTAssertTrue(result.totalSequenceCountOverflowed)
        XCTAssertEqual(result.examinedSequenceCount, 1)
        XCTAssertFalse(result.searchComplete)
        XCTAssertTrue(result.truncated)
    }

    func testInvalidOwnershipAndMalformedDistributionsFailBeforeSearch() {
        XCTAssertThrowsError(try decoder.decode(
            sourceStrokeCount: 2,
            orderedColumns: [
                column([0], [("C", 1)]),
                column([0], [("D", 1)])
            ]
        )) { error in
            XCTAssertEqual(error as? Decoder.Failure, .invalidPartition)
        }

        let malformed: [[(String, Double)]] = [
            [("C", 0.90)],
            [("C", 0.50), ("C", 0.50)],
            [("e\u{301}", 1)],
            [("maj", 1)],
            [("👩‍💻", 1)],
            [("C", .nan)]
        ]
        for values in malformed {
            XCTAssertThrowsError(try decoder.decode(
                sourceStrokeCount: 1,
                orderedColumns: [column([0], values)]
            )) { error in
                XCTAssertEqual(
                    error as? Decoder.Failure,
                    .invalidDistribution(columnIndex: 0),
                    "values=\(values)"
                )
            }
        }
    }
}
