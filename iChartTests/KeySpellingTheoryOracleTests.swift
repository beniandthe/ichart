import XCTest
@testable import iChart

/// Independent spelling expectations use scale-degree letters and chord-member
/// intervals. They deliberately do not derive expected names from the policy.
final class KeySpellingTheoryOracleTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testLegacyTrustPatternRepairsAllDiatonicSpellingsWithoutChangingSavedEvents() throws {
        let inputs = Array(repeating: "C#", count: 3)
            + Array(repeating: "A#m", count: 3)
            + Array(repeating: "F#", count: 6)
            + Array(repeating: "D#m", count: 3)
            + ["G#m"] + Array(repeating: "%", count: 10)
        let expected = Array(repeating: "Db", count: 3)
            + Array(repeating: "Bb-", count: 3)
            + Array(repeating: "Gb", count: 6)
            + Array(repeating: "Eb-", count: 3)
            + ["Ab-"] + Array(repeating: "•/•", count: 10)
        for style in styles {
            // Recreate old persisted .userSelection without a key scope. This
            // is intentionally not the current correction API, which records one.
            let chart = try fixture(key: .dFlatMajor, style: style, texts: inputs, intent: .explicit)
            let original = chart
            XCTAssertEqual(displayTexts(chart), expected)
            XCTAssertEqual(chart, original, "Display repair must not rewrite source evidence")
            let reopened = try reopen(chart)
            XCTAssertEqual(displayTexts(reopened), expected)
            XCTAssertEqual(reopened.measures.map(\.chordEvents), original.measures.map(\.chordEvents))
        }
    }

    func testDiatonicLettersIncludeSingleAccidentalEnharmonicsOutsideBlackKeys() throws {
        let cases: [(DocumentKey, String, String)] = [
            (.fSharpMajor, "Fdim", "E#°"),
            (.cSharpMajor, "Cdim", "B#°"),
            (.gFlatMajor, "B", "Cb"),
            (.cFlatMajor, "E", "Fb")
        ]
        for style in styles {
            for (key, input, expected) in cases {
                let chart = try fixture(key: key, style: style, texts: [input])
                XCTAssertEqual(displayTexts(chart), [expected], "\(key.displayText): \(input)")
            }
        }
    }

    func testMinorLeadingToneKeepsItsSeventhDegreeLetter() throws {
        let cases: [(DocumentKey, String, String)] = [
            (.gMinor, "Gbdim7", "F#°7"),
            (.dMinor, "Dbdim7", "C#°7"),
            (.cSharpMinor, "Cdim7", "B#°7"),
            (.fSharpMinor, "Fdim7", "E#°7")
        ]
        for style in styles {
            for (key, input, expected) in cases {
                let chart = try fixture(key: key, style: style, texts: [input])
                XCTAssertEqual(displayTexts(chart), [expected], "\(key.displayText): \(input)")
            }
        }
    }

    func testSlashThirdSpellingAgreesWithTheChordRoot() throws {
        let cases: [(DocumentKey, String, String)] = [
            (.dMajor, "Db7/F", "C#7/E#"),
            (.eFlatMajor, "D7/Gb", "D7/F#"),
            (.fSharpMajor, "C#/F", "C#/E#"),
            (.dFlatMajor, "D#m/F#", "Eb-/Gb"),
            (.gFlatMajor, "Bmaj7/D#", "Cb△7/Eb")
        ]
        for style in styles {
            for (key, input, expected) in cases {
                let chart = try fixture(key: key, style: style, texts: [input])
                XCTAssertEqual(displayTexts(chart), [expected], "\(key.displayText): \(input)")
            }
        }
    }

    func testAlteredBassRetainsSharpElevenVersusFlatFiveAndUnrelatedPedals() throws {
        let cases: [(String, String)] = [
            ("C7(#11)/Gb", "C7(#11)/F#"),
            ("C7(b5)/F#", "C7(b5)/Gb"),
            ("C7(b9)/C#", "C7(b9)/Db"),
            ("Csus4/E", "Csus4/E")
        ]
        for style in styles {
            for (input, expected) in cases {
                let chart = try fixture(key: .cMajor, style: style, texts: [input])
                let event = try XCTUnwrap(chart.measures.first?.chordEvents.first)
                let displayed = chart.displayedChordSymbol(for: event, in: chart.measures[0].id)
                XCTAssertEqual(displayed.displayText, expected)
                XCTAssertEqual(displayed.quality, event.symbol.quality)
                XCTAssertEqual(displayed.extensions, event.symbol.extensions)
                XCTAssertEqual(displayed.alterations, event.symbol.alterations)
                XCTAssertEqual(event.sourceInkData, Data(input.utf8))
            }
        }
    }

    func testTranspositionRetainsBorrowedAndRaisedDegreeFunctions() throws {
        for style in styles {
            var chart = try fixture(key: .cMajor, style: style,
                texts: ["Bb7", "Ebmaj7", "F#dim7/A", "C7(#11)/E"])
            let before = chart
            XCTAssertTrue(chart.setDocumentKey(.dFlatMajor))
            XCTAssertEqual(displayTexts(chart), ["Cb7", "Fb△7", "G°7/Bb", "Db7(#11)/F"])
            try assertSourceEvidence(chart, sameAs: before)
            let after = try reopen(chart)
            XCTAssertEqual(displayTexts(after), displayTexts(chart))
            XCTAssertEqual(after, chart)
        }
    }

    func testLocalKeyEditOnlyTransposesTheAffectedSection() throws {
        for style in styles {
            var chart = try fixture(key: .cMajor, style: style,
                texts: ["C/E", "F#dim/A", "G/B", "Am/C", "F/A"])
            let ids = chart.measures.map(\.id)
            chart.keyChanges = [KeyChange(measureID: ids[2], key: .gMajor),
                                KeyChange(measureID: ids[4], key: .fMajor)]
            let before = chart
            XCTAssertTrue(chart.setKeyChange(.aFlatMajor, atStartOf: ids[2]))
            XCTAssertEqual(displayTexts(chart), ["C/E", "F#°/A", "Ab/C", "Bb-/Db", "F/A"])
            XCTAssertEqual(chart.measure(id: ids[0])?.chordEvents, before.measure(id: ids[0])?.chordEvents)
            XCTAssertEqual(chart.measure(id: ids[1])?.chordEvents, before.measure(id: ids[1])?.chordEvents)
            XCTAssertEqual(chart.measure(id: ids[4])?.chordEvents, before.measure(id: ids[4])?.chordEvents)
            XCTAssertEqual(chart.effectiveKey(forMeasureID: ids[3]), .aFlatMajor)
            XCTAssertEqual(chart.effectiveKey(forMeasureID: ids[4]), .fMajor)
            try assertSourceEvidence(chart, sameAs: before)
        }
    }

    func testInstrumentViewUsesItsDisplayedKeyWithoutMutatingConcertEvidence() throws {
        let cases: [(DocumentKey, TranspositionView, [String], DocumentKey, [String])] = [
            (.fSharpMajor, .bb, ["F#", "A#m", "E#dim"], .aFlatMajor, ["Ab", "C-", "G°"]),
            (.cMajor, .eb, ["C/E", "F", "Bdim"], .aMajor, ["A/C#", "D", "G#°"]),
            (.dMinor, .bb, ["Dm", "C#dim7"], .eMinor, ["E-", "D#°7"])
        ]
        for style in styles {
            for (key, view, inputs, displayedKey, expected) in cases {
                var chart = try fixture(key: key, style: style, texts: inputs)
                let before = chart
                chart.setInstrumentTranspositionView(view)
                XCTAssertEqual(chart.displayedDocumentKey, displayedKey)
                XCTAssertEqual(displayTexts(chart), expected)
                XCTAssertEqual(chart.systems, before.systems)
                try assertSourceEvidence(chart, sameAs: before)
                XCTAssertEqual(displayTexts(try reopen(chart)), expected)
            }
        }
    }

    func testFreshSpellingChoiceIsScopedAndDoesNotSurviveIntoADifferentKey() throws {
        for style in styles {
            var chart = try fixture(key: .dMajor, style: style, texts: ["Db7/F"])
            let eventID = try XCTUnwrap(chart.measures.first?.chordEvents.first?.id)
            XCTAssertTrue(chart.replaceChordEvent(eventID, with: try ChordSymbolParser.parse("Db7/F"),
                rawInput: "Db7/F", spellingIntent: .explicit))
            XCTAssertEqual(displayTexts(chart), ["Db7/F"])
            XCTAssertEqual(displayTexts(try reopen(chart)), ["Db7/F"])
            XCTAssertTrue(chart.setDocumentKey(.eFlatMajor))
            XCTAssertEqual(displayTexts(chart), ["D7/F#"])
            XCTAssertEqual(displayTexts(try reopen(chart)), ["D7/F#"])
        }
    }

    func testLegacyPersistedOffsetIsAppliedOnceAndPreservesSourceEvidence() throws {
        for style in styles {
            let source = try fixture(key: .dFlatMajor, style: style, texts: ["C#/G#"])
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
                as? [String: Any])
            object["chordTranspositionSemitones"] = 2
            let bytes = try JSONSerialization.data(withJSONObject: object)
            let migrated = try JSONDecoder().decode(Chart.self, from: bytes)
            XCTAssertEqual(migrated.chordTranspositionSemitones, 0)
            XCTAssertEqual(migrated.documentKey, source.documentKey)
            XCTAssertEqual(migrated.defaultTranspositionView, source.defaultTranspositionView)
            XCTAssertEqual(displayTexts(migrated), ["Eb/Bb"])
            try assertSourceEvidence(migrated, sameAs: source)
            let reopened = try reopen(migrated)
            XCTAssertEqual(reopened, migrated)
            XCTAssertEqual(displayTexts(reopened), ["Eb/Bb"])
        }
    }

    private func fixture(key: DocumentKey, style: ChartLayoutStyle, texts: [String],
                         intent: ChordSpellingIntent = .automatic) throws -> Chart {
        var chart = Chart.blank(title: "Key spelling oracle", key: key,
            measureCount: texts.count, layoutStyle: style)
        var next = 0
        for system in chart.systems.indices {
            for measure in chart.systems[system].measures.indices {
                let input = texts[next]
                chart.systems[system].measures[measure].authoringState = .committed
                chart.systems[system].measures[measure].chordEvents = [ChordEvent(id: UUID(),
                    symbol: try ChordSymbolParser.parse(input), spellingIntent: intent,
                    startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
                    duration: .slash, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
                    rawInput: input, sourceInkData: Data(input.utf8),
                    sourceCandidateSignature: [input], manualHorizontalScale: 0.75,
                    manualLaneFraction: 0.2, manualVisualLaneFraction: 0.15)]
                next += 1
            }
        }
        XCTAssertEqual(next, texts.count)
        return chart
    }

    private func displayTexts(_ chart: Chart) -> [String] {
        chart.measures.flatMap { measure in
            measure.chordEvents.map { chart.displayedChordSymbol(for: $0, in: measure.id).displayText }
        }
    }

    private func assertSourceEvidence(_ chart: Chart, sameAs original: Chart,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(chart.measures.map(\.id), original.measures.map(\.id), file: file, line: line)
        for source in original.measures.flatMap(\.chordEvents) {
            let retained = try XCTUnwrap(chart.chordEvent(id: source.id), file: file, line: line)
            XCTAssertEqual(retained.sourceInkData, source.sourceInkData, file: file, line: line)
            XCTAssertEqual(retained.sourceCandidateSignature, source.sourceCandidateSignature, file: file, line: line)
            XCTAssertEqual(retained.symbol.quality, source.symbol.quality, file: file, line: line)
            XCTAssertEqual(retained.symbol.extensions, source.symbol.extensions, file: file, line: line)
            XCTAssertEqual(retained.symbol.alterations, source.symbol.alterations, file: file, line: line)
            XCTAssertEqual(retained.startPosition, source.startPosition, file: file, line: line)
            XCTAssertEqual(retained.manualHorizontalScale, source.manualHorizontalScale, file: file, line: line)
            XCTAssertEqual(retained.manualLaneFraction, source.manualLaneFraction, file: file, line: line)
            XCTAssertEqual(retained.manualVisualLaneFraction, source.manualVisualLaneFraction, file: file, line: line)
        }
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
    }
}
