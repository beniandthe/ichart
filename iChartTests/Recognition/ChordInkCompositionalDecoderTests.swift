import XCTest
@testable import iChart

final class ChordInkCompositionalDecoderTests: XCTestCase {
    func testDecodesTypedGrammarCandidateAndReturnsAtMostThreeRawScores() throws {
        let output = ChordInkLearnedTestFactory.output(
            root: .b,
            rootAccidental: .flat,
            quality: .explicitMajor,
            extensionTone: .seven,
            alterations: [.sharpEleven],
            slashBassLetter: .d,
            hasSlash: true
        )

        let result = try ChordInkCompositionalDecoder().decode(output)

        XCTAssertEqual(result.candidates.count, 3)
        XCTAssertEqual(result.candidates.first?.notation.canonicalDisplay, "Bb△7(#11)/D")
        XCTAssertTrue(zip(result.candidates, result.candidates.dropFirst()).allSatisfy {
            $0.rawJointLogScore >= $1.rawJointLogScore
        })
        for candidate in result.candidates {
            XCTAssertEqual(
                try ChordNotation.parseCanonical(candidate.notation.canonicalDisplay),
                candidate.notation
            )
            XCTAssertLessThanOrEqual(candidate.rawJointLogScore, 0)
        }
    }

    func testGrammarRejectsHighestScoringInvalidFactorCombinationWithoutRenormalizingSurvivors() throws {
        let base = ChordInkLearnedTestFactory.output()
        var qualityValues = Dictionary(
            uniqueKeysWithValues: ChordNotation.Form.allCases.map { ($0, -10.0) }
        )
        qualityValues[.halfDiminished] = 10
        qualityValues[.plain] = 0

        var extensionValues = Dictionary(
            uniqueKeysWithValues: ChordInkExtensionFactorLabel.allCases.map { ($0, -10.0) }
        )
        extensionValues[.none] = 10
        extensionValues[.seven] = 0

        let output = ChordInkLearnedFactorOutput(
            validity: base.validity,
            kind: base.kind,
            rootLetter: base.rootLetter,
            rootAccidental: base.rootAccidental,
            quality: ChordInkFactorLogits(qualityValues),
            extensionTone: ChordInkFactorLogits(extensionValues),
            alterations: base.alterations,
            slashPresence: base.slashPresence,
            slashBassLetter: base.slashBassLetter,
            slashBassAccidental: base.slashBassAccidental
        )

        let result = try ChordInkCompositionalDecoder().decode(output)

        XCTAssertFalse(result.candidates.contains { candidate in
            guard case .rooted(let rooted) = candidate.notation else { return false }
            return rooted.form == .halfDiminished && rooted.extensionTone == nil
        })
        XCTAssertLessThan(result.candidates[0].rawJointLogScore, -9)
    }

    func testTiedFactorsDecodeDeterministically() throws {
        let output = ChordInkLearnedFactorOutput(
            validity: ChordInkLearnedTestFactory.tiedLogits(ChordInkValidityFactorLabel.self),
            kind: ChordInkLearnedTestFactory.tiedLogits(ChordInkKindFactorLabel.self),
            rootLetter: ChordInkLearnedTestFactory.tiedLogits(ChordNotation.Letter.self),
            rootAccidental: ChordInkLearnedTestFactory.tiedLogits(ChordInkAccidentalFactorLabel.self),
            quality: ChordInkLearnedTestFactory.tiedLogits(ChordNotation.Form.self),
            extensionTone: ChordInkLearnedTestFactory.tiedLogits(ChordInkExtensionFactorLabel.self),
            alterations: ChordInkLearnedTestFactory.tiedLogits(ChordNotation.Alteration.self),
            slashPresence: ChordInkLearnedTestFactory.tiedLogits(ChordInkSlashPresenceFactorLabel.self),
            slashBassLetter: ChordInkLearnedTestFactory.tiedLogits(ChordNotation.Letter.self),
            slashBassAccidental: ChordInkLearnedTestFactory.tiedLogits(ChordInkAccidentalFactorLabel.self)
        )
        let decoder = ChordInkCompositionalDecoder()

        let first = try decoder.decode(output)
        let second = try decoder.decode(output)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.candidates.count, 3)
    }

    func testMissingFactorLabelFailsClosed() throws {
        let base = ChordInkLearnedTestFactory.output()
        var incompleteValidity = base.validity.values
        incompleteValidity.removeValue(forKey: .noRead)
        let output = ChordInkLearnedFactorOutput(
            validity: ChordInkFactorLogits(incompleteValidity),
            kind: base.kind,
            rootLetter: base.rootLetter,
            rootAccidental: base.rootAccidental,
            quality: base.quality,
            extensionTone: base.extensionTone,
            alterations: base.alterations,
            slashPresence: base.slashPresence,
            slashBassLetter: base.slashBassLetter,
            slashBassAccidental: base.slashBassAccidental
        )

        XCTAssertThrowsError(try ChordInkCompositionalDecoder().decode(output)) { error in
            XCTAssertEqual(
                error as? ChordInkLearnedDecodeError,
                .labelSetMismatch(
                    head: ChordInkLearnedOutputContract.validityHeadName,
                    expected: ChordInkValidityFactorLabel.allCases.map(\.rawValue),
                    actual: [ChordInkValidityFactorLabel.notation.rawValue]
                )
            )
        }
    }

    func testNonFiniteFactorFailsClosed() throws {
        let base = ChordInkLearnedTestFactory.output()
        var values = base.kind.values
        values[.rooted] = .nan
        let output = ChordInkLearnedFactorOutput(
            validity: base.validity,
            kind: ChordInkFactorLogits(values),
            rootLetter: base.rootLetter,
            rootAccidental: base.rootAccidental,
            quality: base.quality,
            extensionTone: base.extensionTone,
            alterations: base.alterations,
            slashPresence: base.slashPresence,
            slashBassLetter: base.slashBassLetter,
            slashBassAccidental: base.slashBassAccidental
        )

        XCTAssertThrowsError(try ChordInkCompositionalDecoder().decode(output))
    }

    func testIndependentAlterationHeadSupportsFiveGrammarLegalAlterations() throws {
        let output = ChordInkLearnedTestFactory.output(
            extensionTone: .thirteen,
            alterations: [.flatThree, .flatFive, .flatNine, .sharpEleven, .flatThirteen]
        )

        let result = try ChordInkCompositionalDecoder().decode(output)

        XCTAssertEqual(
            result.candidates.first?.notation.canonicalDisplay,
            "C13(b3)(b5)(b9)(#11)(b13)"
        )
        guard case .rooted(let rooted) = result.candidates.first?.notation else {
            return XCTFail("Expected rooted chord")
        }
        XCTAssertEqual(rooted.alterations.count, 5)
    }

    func testConflictingAlterationMassIsNotRenormalizedOntoLegalSubset() throws {
        let base = ChordInkLearnedTestFactory.output()
        var alterationValues = Dictionary(
            uniqueKeysWithValues: ChordNotation.Alteration.allCases.map { ($0, -10.0) }
        )
        alterationValues[.flatFive] = 10
        alterationValues[.sharpFive] = 10
        let output = ChordInkLearnedFactorOutput(
            validity: base.validity,
            kind: base.kind,
            rootLetter: base.rootLetter,
            rootAccidental: base.rootAccidental,
            quality: base.quality,
            extensionTone: base.extensionTone,
            alterations: ChordInkFactorLogits(alterationValues),
            slashPresence: base.slashPresence,
            slashBassLetter: base.slashBassLetter,
            slashBassAccidental: base.slashBassAccidental
        )

        let result = try ChordInkCompositionalDecoder().decode(output)

        for candidate in result.candidates {
            guard case .rooted(let rooted) = candidate.notation else { continue }
            XCTAssertFalse(
                rooted.alterations.contains(.flatFive)
                    && rooted.alterations.contains(.sharpFive)
            )
        }
        XCTAssertLessThan(result.candidates[0].rawJointLogScore, -9)
    }
}
