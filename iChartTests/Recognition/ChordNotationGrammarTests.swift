import XCTest
@testable import iChart

final class ChordNotationGrammarTests: XCTestCase {
    private let validExtensions: [ChordNotation.Form: Set<ChordNotation.Extension?>] = [
        .plain: [nil, .six, .seven, .nine, .eleven, .thirteen, .sixNine],
        .minor: [nil, .six, .seven, .nine, .eleven, .thirteen, .sixNine],
        .explicitMajor: [nil, .six, .seven, .nine, .eleven, .thirteen, .sixNine],
        .minorMajor: [.seven, .nine, .eleven, .thirteen],
        .augmented: [nil, .six, .seven, .nine, .eleven, .thirteen, .sixNine],
        .diminished: [nil, .seven],
        .halfDiminished: [.seven],
        .suspended: [nil, .two, .four, .seven, .nine, .thirteen],
        .addedTone: [.two, .four, .nine, .eleven],
        .altered: [.seven]
    ]

    func testFormSpecificExtensionMatrixIsExhaustive() throws {
        let everyExtension: [ChordNotation.Extension?] = [nil]
            + ChordNotation.Extension.allCases.map(Optional.some)

        for form in ChordNotation.Form.allCases {
            let expected = try XCTUnwrap(validExtensions[form])
            for extensionTone in everyExtension {
                XCTAssertEqual(
                    ChordNotation.Rooted.isValid(form: form, extensionTone: extensionTone),
                    expected.contains(extensionTone),
                    "\(form) \(String(describing: extensionTone))"
                )

                let result: Result<ChordNotation.Rooted, Error> = Result {
                    try ChordNotation.Rooted(
                        root: .init(letter: .c),
                        form: form,
                        extensionTone: extensionTone
                    )
                }
                XCTAssertEqual(result.isSuccess, expected.contains(extensionTone))
            }
        }
    }

    func testAllValidRootFormExtensionAndBassCombinationsRoundTripExactly() throws {
        let basses: [ChordNotation.Pitch?] = [
            nil,
            .init(letter: .a),
            .init(letter: .c, accidental: .sharp),
            .init(letter: .b, accidental: .flat)
        ]

        var checked = 0
        for letter in ChordNotation.Letter.allCases {
            for accidental in ChordNotation.Accidental.allCases {
                for form in ChordNotation.Form.allCases {
                    for extensionTone in try XCTUnwrap(validExtensions[form]) {
                        for slashBass in basses {
                            let rooted = try ChordNotation.Rooted(
                                root: .init(letter: letter, accidental: accidental),
                                form: form,
                                extensionTone: extensionTone,
                                slashBass: slashBass
                            )
                            let notation = ChordNotation.rooted(rooted)
                            let parsed = try ChordNotation.parseCanonical(notation.canonicalDisplay)

                            XCTAssertEqual(parsed, notation, notation.canonicalDisplay)
                            XCTAssertEqual(parsed.canonicalDisplay, notation.canonicalDisplay)
                            checked += 1
                        }
                    }
                }
            }
        }

        XCTAssertEqual(checked, 3_864)
    }

    func testCanonicalDescriptorsAreDeterministic() throws {
        let expectations: [(ChordNotation.Form, ChordNotation.Extension?, String)] = [
            (.plain, nil, "C"),
            (.plain, .sixNine, "C6/9"),
            (.minor, nil, "C-"),
            (.minor, .seven, "C-7"),
            (.explicitMajor, nil, "C△"),
            (.explicitMajor, .thirteen, "C△13"),
            (.minorMajor, .nine, "C-△9"),
            (.augmented, .seven, "C+7"),
            (.diminished, nil, "C°"),
            (.diminished, .seven, "C°7"),
            (.halfDiminished, .seven, "Cø7"),
            (.suspended, nil, "Csus"),
            (.suspended, .two, "Csus2"),
            (.suspended, .seven, "C7sus"),
            (.suspended, .thirteen, "Csus13"),
            (.addedTone, .eleven, "Cadd11"),
            (.altered, .seven, "C7alt")
        ]

        for (form, extensionTone, expected) in expectations {
            let chord = try ChordNotation.Rooted(
                root: .init(letter: .c),
                form: form,
                extensionTone: extensionTone
            )
            XCTAssertEqual(chord.canonicalDisplay, expected)
            XCTAssertEqual(try ChordNotation.parseCanonical(expected), .rooted(chord))
        }
    }

    func testAlterationsAreTypedUniqueAndCanonicallySorted() throws {
        let chord = try ChordNotation.Rooted(
            root: .init(letter: .b, accidental: .flat),
            extensionTone: .seven,
            alterations: [.flatThirteen, .sharpEleven, .flatThree, .sharpFive, .flatNine],
            slashBass: .init(letter: .d)
        )

        XCTAssertEqual(
            chord.alterations,
            [.flatThree, .sharpFive, .flatNine, .sharpEleven, .flatThirteen]
        )
        XCTAssertEqual(chord.canonicalDisplay, "Bb7(b3)(#5)(b9)(#11)(b13)/D")
        XCTAssertEqual(
            try ChordNotation.parseCanonical(chord.canonicalDisplay),
            .rooted(chord)
        )

        XCTAssertThrowsError(
            try ChordNotation.Rooted(
                root: .init(letter: .c),
                alterations: [.flatFive, .sharpFive]
            )
        ) { error in
            XCTAssertEqual(
                error as? ChordNotation.ValidationError,
                .duplicateAlterationDegree(5)
            )
        }
    }

    func testFormsThatForbidExplicitAlterationsRejectEverySupportedAlteration() throws {
        let forbiddenForms: [(ChordNotation.Form, ChordNotation.Extension?)] = [
            (.minorMajor, .seven),
            (.augmented, nil),
            (.diminished, nil),
            (.halfDiminished, .seven),
            (.addedTone, .nine),
            (.altered, .seven)
        ]

        for (form, extensionTone) in forbiddenForms {
            for alteration in ChordNotation.Alteration.allCases {
                XCTAssertThrowsError(
                    try ChordNotation.Rooted(
                        root: .init(letter: .c),
                        form: form,
                        extensionTone: extensionTone,
                        alterations: [alteration]
                    )
                ) { error in
                    XCTAssertEqual(
                        error as? ChordNotation.ValidationError,
                        .alterationsNotAllowed(form: form)
                    )
                }
            }
        }
    }

    func testStrictParserRejectsAliasesWhitespaceAndLookalikeRepair() {
        let rejected = [
            "", " C", "C ", "c", "H", "C♯", "C♭", "C＃",
            "Cm", "Cmin", "Cmaj7", "CM7", "CΔ7", "C∆7",
            "Cdim7", "CØ7", "Chalf-dim7", "C7sus4", "Csus7",
            "Cadd6", "Calt", "C altered", "%", "./.", "• / •",
            "C7b9", "C7(b9)(#5)", "C7(b9)(b9)", "C7(#5)(b5)",
            "C/E5", "C/eb", "C6/8", "C6/9/", "C6/9/E5"
        ]

        for input in rejected {
            XCTAssertThrowsError(try ChordNotation.parseCanonical(input), input)
        }
    }

    func testChordRepeatAndCodableRoundTrip() throws {
        let repeatNotation = ChordNotation.chordRepeat
        XCTAssertEqual(repeatNotation.canonicalDisplay, "•/•")
        XCTAssertEqual(try ChordNotation.parseCanonical("•/•"), repeatNotation)

        let chord = ChordNotation.rooted(
            try ChordNotation.Rooted(
                root: .init(letter: .f, accidental: .sharp),
                form: .suspended,
                extensionTone: .seven,
                alterations: [.flatNine],
                slashBass: .init(letter: .c, accidental: .sharp)
            )
        )

        for notation in [repeatNotation, chord] {
            let data = try JSONEncoder().encode(notation)
            XCTAssertEqual(try JSONDecoder().decode(ChordNotation.self, from: data), notation)
        }
    }

    func testGrammarReplaysEveryCanonicalNotationWithoutADeadPrefix() throws {
        var notations: [ChordNotation] = [.chordRepeat]
        for form in ChordNotation.Form.allCases {
            for extensionTone in try XCTUnwrap(validExtensions[form]) {
                let allowsAlterations = ChordNotation.Rooted.allowsAlterations(form: form)
                let chord = try ChordNotation.Rooted(
                    root: .init(letter: .g, accidental: .flat),
                    form: form,
                    extensionTone: extensionTone,
                    alterations: allowsAlterations ? [.flatNine, .sharpEleven] : [],
                    slashBass: .init(letter: .d, accidental: .flat)
                )
                notations.append(.rooted(chord))
            }
        }

        for notation in notations {
            var state = ChordNotationGrammar.start
            for token in ChordNotationGrammar.tokens(for: notation) {
                state = try XCTUnwrap(
                    ChordNotationGrammar.transition(from: state, consuming: token),
                    "Rejected \(token) in \(notation.canonicalDisplay)"
                )
            }
            XCTAssertTrue(state.isTerminal)
            XCTAssertEqual(state.completedNotation, notation)
        }
    }

    func testGrammarStartAndChordRepeatTransitions() throws {
        XCTAssertEqual(
            ChordNotationGrammar.allowedNextTokenKinds(from: .init()),
            [.rootLetter, .chordRepeat]
        )

        let repeatState = try advance(.init(), .chordRepeat)
        XCTAssertFalse(repeatState.canEnd)
        XCTAssertEqual(
            ChordNotationGrammar.allowedNextTokenKinds(from: repeatState),
            [.end]
        )

        let ended = try advance(repeatState, .end)
        XCTAssertEqual(ended.completedNotation, .chordRepeat)
        XCTAssertNil(ChordNotationGrammar.transition(from: ended, consuming: .end))
    }

    func testGrammarPrunesNonCanonicalFormAndExtensionOrder() throws {
        let root = try advance(.init(), .rootLetter(.c))
        XCTAssertTrue(root.canEnd)

        let seven = try advance(root, .extensionTone(.seven))
        XCTAssertTrue(seven.canEnd)
        XCTAssertNotNil(ChordNotationGrammar.transition(from: seven, consuming: .form(.suspended)))
        XCTAssertNotNil(ChordNotationGrammar.transition(from: seven, consuming: .form(.altered)))
        XCTAssertNil(ChordNotationGrammar.transition(from: seven, consuming: .form(.minor)))

        let suspended = try advance(root, .form(.suspended))
        XCTAssertTrue(suspended.canEnd)
        XCTAssertNotNil(ChordNotationGrammar.transition(from: suspended, consuming: .extensionTone(.four)))
        XCTAssertNil(ChordNotationGrammar.transition(from: suspended, consuming: .extensionTone(.seven)))

        let halfDiminished = try advance(root, .form(.halfDiminished))
        XCTAssertFalse(halfDiminished.canEnd)
        XCTAssertNil(ChordNotationGrammar.transition(from: halfDiminished, consuming: .end))
        XCTAssertNil(ChordNotationGrammar.transition(from: halfDiminished, consuming: .extensionTone(.nine)))
        XCTAssertNotNil(ChordNotationGrammar.transition(from: halfDiminished, consuming: .extensionTone(.seven)))

        XCTAssertNil(ChordNotationGrammar.transition(from: root, consuming: .extensionTone(.two)))
        XCTAssertNil(ChordNotationGrammar.transition(from: root, consuming: .form(.plain)))
        XCTAssertNil(ChordNotationGrammar.transition(from: root, consuming: .form(.altered)))
    }

    func testGrammarRequiresCanonicalAlterationOrderAndUniqueDegrees() throws {
        var state = try advance(.init(), .rootLetter(.c))
        state = try advance(state, .extensionTone(.seven))
        state = try advance(state, .alteration(.flatFive))

        XCTAssertNil(ChordNotationGrammar.transition(from: state, consuming: .alteration(.flatThree)))
        XCTAssertNil(ChordNotationGrammar.transition(from: state, consuming: .alteration(.sharpFive)))

        state = try advance(state, .alteration(.sharpNine))
        state = try advance(state, .alteration(.flatThirteen))
        let ended = try advance(state, .end)
        XCTAssertEqual(ended.completedNotation?.canonicalDisplay, "C7(b5)(#9)(b13)")
    }

    func testGrammarSlashBassRequiresLetterBeforeOptionalAccidental() throws {
        var state = try advance(.init(), .rootLetter(.g))
        state = try advance(state, .slash)
        XCTAssertEqual(
            ChordNotationGrammar.allowedNextTokenKinds(from: state),
            [.bassLetter]
        )
        XCTAssertNil(ChordNotationGrammar.transition(from: state, consuming: .bassAccidental(.flat)))
        XCTAssertNil(ChordNotationGrammar.transition(from: state, consuming: .end))

        state = try advance(state, .bassLetter(.b))
        XCTAssertTrue(state.canEnd)
        XCTAssertNil(ChordNotationGrammar.transition(from: state, consuming: .bassAccidental(.natural)))
        state = try advance(state, .bassAccidental(.flat))
        let ended = try advance(state, .end)
        XCTAssertEqual(ended.completedNotation?.canonicalDisplay, "G/Bb")
    }

    private func advance(
        _ state: ChordNotationGrammar.State,
        _ token: ChordNotationGrammar.ComponentToken,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ChordNotationGrammar.State {
        try XCTUnwrap(
            ChordNotationGrammar.transition(from: state, consuming: token),
            "Grammar rejected \(token)",
            file: file,
            line: line
        )
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
