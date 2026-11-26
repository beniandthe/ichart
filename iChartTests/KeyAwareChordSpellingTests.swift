import XCTest
@testable import iChart

final class KeyAwareChordSpellingTests: XCTestCase {
    // Literal scale spellings provide an oracle independent of the spelling policy.
    private let scales: [(key: DocumentKey, pitches: String)] = [
        (.cMajor, "C D E F G A B"),
        (.gMajor, "G A B C D E F#"),
        (.dMajor, "D E F# G A B C#"),
        (.aMajor, "A B C# D E F# G#"),
        (.eMajor, "E F# G# A B C# D#"),
        (.bMajor, "B C# D# E F# G# A#"),
        (.fSharpMajor, "F# G# A# B C# D# E#"),
        (.cSharpMajor, "C# D# E# F# G# A# B#"),
        (.fMajor, "F G A Bb C D E"),
        (.bFlatMajor, "Bb C D Eb F G A"),
        (.eFlatMajor, "Eb F G Ab Bb C D"),
        (.aFlatMajor, "Ab Bb C Db Eb F G"),
        (.dFlatMajor, "Db Eb F Gb Ab Bb C"),
        (.gFlatMajor, "Gb Ab Bb Cb Db Eb F"),
        (.cFlatMajor, "Cb Db Eb Fb Gb Ab Bb"),
        (.aMinor, "A B C D E F G"),
        (.eMinor, "E F# G A B C D"),
        (.bMinor, "B C# D E F# G A"),
        (.fSharpMinor, "F# G# A B C# D E"),
        (.cSharpMinor, "C# D# E F# G# A B"),
        (.gSharpMinor, "G# A# B C# D# E F#"),
        (.dSharpMinor, "D# E# F# G# A# B C#"),
        (.aSharpMinor, "A# B# C# D# E# F# G#"),
        (.dMinor, "D E F G A Bb C"),
        (.gMinor, "G A Bb C D Eb F"),
        (.cMinor, "C D Eb F G Ab Bb"),
        (.fMinor, "F G Ab Bb C Db Eb"),
        (.bFlatMinor, "Bb C Db Eb F Gb Ab"),
        (.eFlatMinor, "Eb F Gb Ab Bb Cb Db"),
        (.aFlatMinor, "Ab Bb Cb Db Eb Fb Gb")
    ]

    func testEveryStandardKeySpellsEveryNaturalScaleDegreeFromEitherEnharmonic() throws {
        XCTAssertEqual(Set(scales.map(\.key)), Set(DocumentKey.allStandardKeys))
        for (key, scale) in scales {
            for expected in scale.split(separator: " ").map(String.init) {
                let pitch = try XCTUnwrap(ChordPitch.parse(expected))
                for preference in [PitchSpellingPreference.flats, .sharps] {
                    let input = ChordPitch.from(semitone: pitch.semitone, preference: preference)
                    let symbol = ChordSymbol(root: input.root, accidental: input.accidental,
                        quality: "", extensions: [], alterations: [], slashBass: nil)
                    XCTAssertEqual(symbol.spelledForChartDisplay(in: key).displayText,
                        expected, "\(key.displayText) degree \(expected)")
                }
            }
        }
    }

    func testAllStandardKeyPairsRetainPitchesAndChordMeaning() throws {
        let parsed = try scales.map { entry in
            (key: entry.key, pitches: try entry.pitches.split(separator: " ").map {
                try XCTUnwrap(ChordPitch.parse(String($0)))
            })
        }
        var checked = 0
        var firstFailure: String?
        for source in parsed {
            for target in parsed {
                let delta = (target.key.pitch.semitone - source.key.pitch.semitone + 12) % 12
                for degree in 0..<7 {
                    let sourceRoot = source.pitches[degree]
                    let sourceBass = source.pitches[(degree + 2) % 7]
                    for quality in ["", "-", "dim", "△", "sus"] {
                        let chord = ChordSymbol(root: sourceRoot.root,
                            accidental: sourceRoot.accidental, quality: quality,
                            extensions: ["7", "9"], alterations: ["#11", "b9"],
                            slashBass: sourceBass.displayText)
                        let result = chord.transposedForChartDisplay(by: delta,
                            from: source.key, to: target.key)
                        let resultRoot = ChordPitch(root: result.root, accidental: result.accidental)
                        let resultBass = ChordPitch.parse(result.slashBass ?? "")
                        let metadataMatches = result.kind == chord.kind
                            && result.quality == chord.quality && result.extensions == chord.extensions
                            && result.alterations == chord.alterations
                        let pitchMatches = resultRoot.semitone == (sourceRoot.semitone + delta) % 12
                            && resultBass?.semitone == (sourceBass.semitone + delta) % 12
                        let scaleMatches = source.key.mode != target.key.mode
                            || (resultRoot == target.pitches[degree]
                                && resultBass == target.pitches[(degree + 2) % 7])
                        if firstFailure == nil && (!metadataMatches || !pitchMatches || !scaleMatches) {
                            firstFailure = "\(source.key.displayText)→\(target.key.displayText): "
                                + "\(chord.displayText) became \(result.displayText); "
                                + "metadata=\(metadataMatches), pitch=\(pitchMatches), scale=\(scaleMatches)"
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 31_500)
        XCTAssertNil(firstFailure, firstFailure ?? "")
    }

    func testZeroSemitoneEnharmonicKeyChangesRetainWrittenScaleDegrees() throws {
        for (source, target, inputs, expected) in [
            (DocumentKey.cSharpMajor, DocumentKey.dFlatMajor, "C# E# F# B#", "Db F Gb C"),
            (DocumentKey.fSharpMajor, DocumentKey.gFlatMajor, "F# A# B E#", "Gb Bb Cb F")
        ] {
            let symbols = try inputs.split(separator: " ").map {
                try ChordSymbolParser.parse(String($0)).transposedForChartDisplay(
                    by: 0, from: source, to: target).displayText
            }
            XCTAssertEqual(symbols.joined(separator: " "), expected)
        }
    }

    func testExplicitSpellingTransportAndUnsupportedDoubleAccidentalFallbackKeepPitch() throws {
        let source = try ChordSymbolParser.parse("E#/G#")
        XCTAssertEqual(source.transposedForChartDisplay(by: 1, from: .cMajor,
            to: .dFlatMajor, preservingSpelling: true).displayText, "F#/A")
        XCTAssertEqual(source.transposedForChartDisplay(by: 1, from: .cMajor,
            to: .dFlatMajor).displayText, "Gb/A")
        // F double sharp is unavailable in this model; its readable equivalent
        // must still sound the same as the harmonic-minor leading tone.
        let originalLeadingTone = try ChordSymbolParser.parse("Gdim7")
        let leadingTone = originalLeadingTone.spelledForChartDisplay(in: .gSharpMinor)
        XCTAssertEqual(ChordPitch(root: leadingTone.root,
            accidental: leadingTone.accidental).semitone, 7)
        XCTAssertEqual(leadingTone.quality, originalLeadingTone.quality)
        XCTAssertEqual(leadingTone.extensions, originalLeadingTone.extensions)
    }

    func testGenericEnharmonicPickerKeepsSlashChordMembersCoherent() throws {
        XCTAssertEqual(try ChordSymbolParser.parse("Db7/F").enharmonicDisplayTexts(),
            ["Db7/F", "C#7/E#"])
        XCTAssertEqual(try ChordSymbolParser.parse("D7/Gb")
            .spelledForChartDisplay(using: .flats).displayText, "D7/F#")
    }

    func testRepeatIsUnaffectedByKeySpellingAndKeyTransposition() {
        XCTAssertEqual(ChordSymbol.chordRepeat.spelledForChartDisplay(in: .cFlatMajor), .chordRepeat)
        XCTAssertEqual(ChordSymbol.chordRepeat.transposedForChartDisplay(by: 11,
            from: .cMajor, to: .bMajor), .chordRepeat)
    }

    func testScopedManualOverridePersistsWhileLegacyAndAutomaticEventsRemainUnscoped() throws {
        let explicit = ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse("Db7/F"),
            spellingIntent: .explicit,
            startPosition: BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .slash, rhythmPlacement: .hidden, tieOut: false, hitStyle: .none,
            rawInput: "Db7/F", spellingOverrideKey: .dMajor)
        let data = try JSONEncoder().encode(explicit)
        XCTAssertEqual(try JSONDecoder().decode(ChordEvent.self, from: data), explicit)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "spellingOverrideKey")
        let old = try JSONDecoder().decode(ChordEvent.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.spellingIntent, .explicit)
        XCTAssertEqual(old.spellingOverrideSource, .userSelection)
        XCTAssertNil(old.spellingOverrideKey)
        object["spellingIntent"] = "automatic"
        object["spellingOverrideKey"] = ["tonic": "D", "accidental": "", "mode": "major"]
        let automatic = try JSONDecoder().decode(ChordEvent.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(automatic.spellingOverrideKey)
        let automaticJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(automatic)) as? [String: Any])
        XCTAssertNil(automaticJSON["spellingOverrideKey"])
    }
}
