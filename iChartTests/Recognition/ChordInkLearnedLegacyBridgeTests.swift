import XCTest
@testable import iChart

final class ChordInkLearnedLegacyBridgeTests: XCTestCase {
    func testEveryValidStrictSuffixAndPitchValueRoundTripsSemantically() throws {
        let root = ChordNotation.Pitch(letter: .c, accidental: .sharp)
        let bass = ChordNotation.Pitch(letter: .b, accidental: .flat)
        let extensions: [ChordNotation.Extension?] = [nil]
            + ChordNotation.Extension.allCases.map(Optional.some)
        let alterations = ChordNotation.Alteration.allCases
        var validatedSuffixCount = 0

        for form in ChordNotation.Form.allCases {
            for extensionTone in extensions {
                for mask in 0..<(1 << alterations.count) {
                    let selected = alterations.enumerated().compactMap { index, alteration in
                        mask & (1 << index) == 0 ? nil : alteration
                    }
                    guard let rooted = try? ChordNotation.Rooted(
                        root: root,
                        form: form,
                        extensionTone: extensionTone,
                        alterations: selected,
                        slashBass: bass
                    ) else {
                        continue
                    }

                    let notation = ChordNotation.rooted(rooted)
                    let symbol = try ChordNotationLegacyBridge.symbol(for: notation)
                    XCTAssertEqual(
                        try ChordNotationLegacyBridge.notation(for: symbol),
                        notation,
                        notation.canonicalDisplay
                    )
                    validatedSuffixCount += 1
                }
            }
        }
        XCTAssertGreaterThan(validatedSuffixCount, 1_000)

        for rootLetter in ChordNotation.Letter.allCases {
            for rootAccidental in ChordNotation.Accidental.allCases {
                for bassLetter in ChordNotation.Letter.allCases {
                    for bassAccidental in ChordNotation.Accidental.allCases {
                        let rooted = try ChordNotation.Rooted(
                            root: ChordNotation.Pitch(
                                letter: rootLetter,
                                accidental: rootAccidental
                            ),
                            extensionTone: .seven,
                            slashBass: ChordNotation.Pitch(
                                letter: bassLetter,
                                accidental: bassAccidental
                            )
                        )
                        let notation = ChordNotation.rooted(rooted)
                        let symbol = try ChordNotationLegacyBridge.symbol(for: notation)
                        XCTAssertEqual(
                            try ChordNotationLegacyBridge.notation(for: symbol),
                            notation,
                            notation.canonicalDisplay
                        )
                    }
                }
            }
        }
    }

    func testRepresentativeStrictGrammarRoundTripsThroughLegacySymbolSemantics() throws {
        let canonicalTexts = [
            "C",
            "Db-7",
            "F#△13(#11)/Bb",
            "A-△9/C#",
            "E+7",
            "B°7",
            "Gbø7",
            "D7sus",
            "Absus2",
            "Cadd11",
            "F7alt",
            "C-6",
            "E6/9/G#",
            "C7(b3)(#5)(b9)(#11)(b13)",
            "•/•"
        ]

        for canonicalText in canonicalTexts {
            let notation = try ChordNotation.parseCanonical(canonicalText)
            let symbol = try ChordNotationLegacyBridge.symbol(for: notation)
            let roundTripped = try ChordNotationLegacyBridge.notation(for: symbol)
            XCTAssertEqual(roundTripped, notation, canonicalText)
        }
    }

    func testStrictMinorSixSemanticsSurviveLegacyDisplayAlias() throws {
        let notation = try ChordNotation.parseCanonical("C-6")
        let symbol = try ChordNotationLegacyBridge.symbol(for: notation)

        XCTAssertEqual(symbol.quality, "-")
        XCTAssertEqual(symbol.extensions, ["6"])
        XCTAssertEqual(symbol.displayText, "Cm6")
        XCTAssertEqual(try ChordNotationLegacyBridge.notation(for: symbol), notation)
    }

    func testStrictInverseRejectsFriendlyButNoncanonicalLegacyFields() {
        let aliasQuality = ChordSymbol(
            root: .c,
            accidental: .natural,
            quality: "maj",
            extensions: ["7"],
            alterations: [],
            slashBass: nil
        )
        XCTAssertThrowsError(try ChordNotationLegacyBridge.notation(for: aliasQuality)) { error in
            XCTAssertEqual(
                error as? ChordNotationLegacyBridgeError,
                .unsupportedLegacyQuality("maj")
            )
        }

        let ambiguousExtensions = ChordSymbol(
            root: .c,
            accidental: .natural,
            quality: "",
            extensions: ["7", "9"],
            alterations: [],
            slashBass: nil
        )
        XCTAssertThrowsError(try ChordNotationLegacyBridge.notation(for: ambiguousExtensions))

        let invalidSlashBass = ChordSymbol(
            root: .c,
            accidental: .natural,
            quality: "",
            extensions: [],
            alterations: [],
            slashBass: "H"
        )
        XCTAssertThrowsError(try ChordNotationLegacyBridge.notation(for: invalidSlashBass))
    }

    func testDecodedCandidatesProjectIntoReviewOnlyLegacyResult() throws {
        let majorSeven = try ChordNotation.parseCanonical("C△7")
        let altered = try ChordNotation.parseCanonical("F7alt")
        let decoded = ChordInkLearnedDecodeResult(
            candidates: [
                ChordInkLearnedDecodedCandidate(
                    notation: majorSeven,
                    rawJointLogScore: -0.25
                ),
                ChordInkLearnedDecodedCandidate(
                    notation: altered,
                    rawJointLogScore: -1.5
                )
            ],
            noReadLogScore: -2
        )

        let output = try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: decoded)

        XCTAssertEqual(output.disposition, .reviewRequired)
        XCTAssertEqual(output.candidates.map(\.canonicalText), ["C△7", "F7alt"])
        XCTAssertEqual(output.candidates.map(\.rawJointLogScore), [-0.25, -1.5])
        XCTAssertNil(output.symbolForPrefill)
        XCTAssertNil(output.symbolForPersistence)

        let result = output.recognitionResult
        XCTAssertNil(result.match)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertTrue(result.candidateScores.isEmpty)
        XCTAssertEqual(result.reviewCandidateScores.map(\.text), ["C△7", "F7alt"])
        XCTAssertEqual(result.reviewCandidateScores.map(\.displayText), ["C△7", "F7alt"])
        XCTAssertTrue(result.reviewCandidateScores.allSatisfy { $0.confidence == 0 })

        let decision = ChordInkRecognitionPolicy.decision(for: result)
        XCTAssertEqual(decision.action, .confirm)
        XCTAssertNil(decision.acceptedText)
    }

    func testNoCandidatesProjectsIntoNoReadWithoutPrefillOrPersistence() throws {
        let decoded = ChordInkLearnedDecodeResult(
            candidates: [],
            noReadLogScore: -0.01
        )

        let output = try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: decoded)

        XCTAssertEqual(output.disposition, .noRead)
        XCTAssertTrue(output.candidates.isEmpty)
        XCTAssertTrue(output.recognitionResult.rawCandidates.isEmpty)
        XCTAssertTrue(output.recognitionResult.reviewCandidateScores.isEmpty)
        XCTAssertNil(output.recognitionResult.match)
        XCTAssertNil(output.symbolForPrefill)
        XCTAssertNil(output.symbolForPersistence)
        XCTAssertNil(ChordInkRecognitionPolicy.decision(for: output.recognitionResult).acceptedText)
    }

    func testBridgeRejectsDuplicateCandidatesAndNonFiniteScores() throws {
        let notation = try ChordNotation.parseCanonical("G7")
        let duplicate = ChordInkLearnedDecodeResult(
            candidates: [
                ChordInkLearnedDecodedCandidate(notation: notation, rawJointLogScore: -1),
                ChordInkLearnedDecodedCandidate(notation: notation, rawJointLogScore: -2)
            ],
            noReadLogScore: -3
        )
        XCTAssertThrowsError(
            try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: duplicate)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedLegacyBridgeError,
                .duplicateCanonicalCandidate("G7")
            )
        }

        let invalidCandidate = ChordInkLearnedDecodeResult(
            candidates: [
                ChordInkLearnedDecodedCandidate(
                    notation: notation,
                    rawJointLogScore: .infinity
                )
            ],
            noReadLogScore: -3
        )
        XCTAssertThrowsError(
            try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: invalidCandidate)
        )

        let positiveCandidate = ChordInkLearnedDecodeResult(
            candidates: [
                ChordInkLearnedDecodedCandidate(
                    notation: notation,
                    rawJointLogScore: 0.01
                )
            ],
            noReadLogScore: -3
        )
        XCTAssertThrowsError(
            try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: positiveCandidate)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedLegacyBridgeError,
                .positiveCandidateLogScore("G7")
            )
        }

        let invalidNoRead = ChordInkLearnedDecodeResult(
            candidates: [],
            noReadLogScore: .nan
        )
        XCTAssertThrowsError(
            try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: invalidNoRead)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedLegacyBridgeError,
                .nonFiniteNoReadLogScore
            )
        }

        let positiveNoRead = ChordInkLearnedDecodeResult(
            candidates: [],
            noReadLogScore: 0.01
        )
        XCTAssertThrowsError(
            try ChordInkLearnedLegacyBridge.reviewOnlyOutput(from: positiveNoRead)
        ) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedLegacyBridgeError,
                .positiveNoReadLogScore
            )
        }
    }
}
