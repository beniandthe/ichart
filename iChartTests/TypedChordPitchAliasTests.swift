import XCTest
@testable import iChart

final class TypedChordPitchAliasTests: XCTestCase {
    func testUnicodeRootAccidentalsPreserveTriangleMeanings() throws {
        for root in ["A", "B", "C", "D", "E", "F", "G"] {
            for (alias, accidental) in [("♭", "b"), ("♯", "#"), ("＃", "#")] {
                for triangle in ["△", "Δ", "∆"] {
                    for suffix in ["", "7"] {
                        let input = root + alias + triangle + suffix
                        let ascii = root + accidental + "△" + suffix
                        XCTAssertEqual(
                            try ChordSymbolParser.parse(input),
                            try ChordSymbolParser.parse(ascii),
                            input
                        )
                    }
                }
            }
        }
    }

    func testUnicodeSlashBassAndRootPitchUseTheSameTypedAliases() throws {
        for (input, ascii) in [
            ("G7/B♭", "G7/Bb"),
            ("C∆7/F♯", "Cmaj7/F#"),
            ("D♭Δ7/A♭", "Dbmaj7/Ab"),
            ("E♭△/G＃", "Eb△/G#")
        ] {
            XCTAssertEqual(
                try ChordSymbolParser.parse(input),
                try ChordSymbolParser.parse(ascii),
                input
            )
        }
        XCTAssertEqual(ChordPitch.parse("B♭"), ChordPitch.parse("Bb"))
        XCTAssertEqual(ChordPitch.parse("F♯"), ChordPitch.parse("F#"))
        XCTAssertEqual(ChordPitch.parse("G＃"), ChordPitch.parse("G#"))
    }

    func testMalformedAccidentalsAndUnsupportedPunctuationAreNotRepaired() {
        for input in ["C♭♭7", "C♯♭7", "C♯#7", "C♭7?", "B♭△8", "C♯△7!", "H♭△7", "B♭▲7"] {
            XCTAssertThrowsError(try ChordSymbolParser.parse(input), input)
        }
        XCTAssertNil(ChordPitch.parse("B♭♭"))
        XCTAssertNil(ChordPitch.parse("F♯#"))
    }

    func testCanonicalStorageGrammarStillRejectsInputAliases() throws {
        XCTAssertEqual(try ChordNotation.parseCanonical("Bb△7").canonicalDisplay, "Bb△7")
        for alias in ["B♭△7", "C♯△7", "CΔ7", "C∆7"] {
            XCTAssertThrowsError(try ChordNotation.parseCanonical(alias), alias)
        }
    }

    func testTriangleWithAndWithoutSevenKeepDistinctSemantics() throws {
        for triangle in ["△", "Δ", "∆"] {
            let plain = try ChordSymbolParser.parse("C" + triangle)
            let seventh = try ChordSymbolParser.parse("C" + triangle + "7")
            XCTAssertEqual(plain.quality, "△")
            XCTAssertTrue(plain.extensions.isEmpty)
            XCTAssertEqual(seventh, try ChordSymbolParser.parse("Cmaj7"))
            XCTAssertNotEqual(plain, seventh)
        }
    }
}
