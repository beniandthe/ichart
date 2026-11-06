import XCTest
@testable import iChart

final class ChordRecognitionDomainTests: XCTestCase {
    private struct Rank: Equatable {
        let label: String
        let score: Double
    }

    func testAllowedGlyphTokensKeepContextualChordFragmentsButRejectUnrelatedGlyphs() {
        for token in [
            "A", "g", "b", "#", "-", "m", "j", "1", "3", "/", "(", ")",
            "△", "Δ", "°", "º", "ø", "o", "11", "13", "6/9", "maj", "sus", "alt"
        ] {
            XCTAssertTrue(ChordRecognitionDomain.isAllowedGlyphToken(token), token)
        }

        for token in ["J", "ñ", "Ñ", "0", "8", "?", "🎵", "€", "foo", ""] {
            XCTAssertFalse(ChordRecognitionDomain.isAllowedGlyphToken(token), token)
        }
    }

    func testProjectTopRankedNeverPromotesPastIllegalRawTop() {
        let illegalTop = [
            Rank(label: "ñ", score: 9),
            Rank(label: "C", score: 8),
            Rank(label: "1", score: 7)
        ]
        XCTAssertTrue(
            ChordRecognitionDomain.projectTopRanked(illegalTop, label: \.label).isEmpty
        )

        let legalTop = [
            Rank(label: "C", score: 9),
            Rank(label: "ñ", score: 8),
            Rank(label: "1", score: 7),
            Rank(label: "j", score: 6)
        ]
        XCTAssertEqual(
            ChordRecognitionDomain.projectTopRanked(legalTop, label: \.label),
            [legalTop[0], legalTop[2], legalTop[3]]
        )
    }

    func testInputCharacterBoundaryRejectsAccentsControlsAndNonChordDecoration() {
        for input in ["C11", "C13", "Cmaj7", "CMaj7", "CMAJ7", "Csus4", "Cdim7", "D/F#", "• / •"] {
            XCTAssertTrue(ChordRecognitionDomain.containsOnlyChordInputCharacters(input), input)
        }

        for input in ["J", "1", "Ć", "Cmiñ7", "D/Fñ", "C?", "C🎵", "C\t7", "C7."] {
            XCTAssertFalse(ChordRecognitionDomain.containsOnlyChordInputCharacters(input), input)
        }
    }

    func testCompendiumCannotManufactureValidChordByDroppingInput() {
        for input in [
            "C?", "C🎵", "C()", "C(m)", "Ć", "Cmiñ7", "D/Fñ", "D/FF",
            "D>", ">C", "C!", "Cmaj!7", "F?", "C7.", "Bb7%"
        ] {
            XCTAssertNil(ChordRecognitionCompendium.match(input), input)
        }
    }

    func testCompendiumPreservesSupportedChordFamiliesAndAliases() {
        let expectations = [
            "C11": "C11",
            "C13": "C13",
            "Cmaj7": "C△7",
            "CMaj7": "C△7",
            "CMAJ7": "C△7",
            "CMAJOR7": "C△7",
            "CM7": "C△7",
            "Csus4": "Csus4",
            "Cadd11": "Cadd11",
            "C7alt": "C7alt",
            "Cdim7": "C°7",
            "CØ7": "Cø7",
            "C7(b9)/E": "C7(b9)/E",
            "C6/9/E": "C6/9/E",
            "C-△9": "C-△9",
            "D flat minor": "Db-",
            "F sharp m": "F#-",
            "D FLAT": "Db",
            "B♭": "Bb"
        ]

        for (input, expected) in expectations {
            XCTAssertEqual(ChordRecognitionCompendium.match(input)?.displayText, expected, input)
        }

        for repeatText in ["•/•", "• / •", "·/·", "∙ / ∙", "%", "./."] {
            XCTAssertEqual(
                ChordRecognitionCompendium.match(repeatText)?.displayText,
                ChordSymbol.chordRepeatDisplayText,
                repeatText
            )
        }
    }

    func testContextualLettersAndDigitsRequireACompleteSupportedChord() {
        for input in ["1", "C1", "J", "CJ", "Cj", "Cs", "Cdi"] {
            XCTAssertNil(ChordRecognitionCompendium.match(input), input)
        }

        for input in ["C11", "C13", "C7(#11)", "C7(b13)", "Cmaj7", "Csus4", "Cdim7"] {
            XCTAssertNotNil(ChordRecognitionCompendium.match(input), input)
        }
    }

    func testEveryPublishedCompendiumAliasRemainsInsideTheDomainAndMatches() {
        for word in ChordRecognitionCompendium.recognitionWords {
            XCTAssertTrue(ChordRecognitionDomain.containsOnlyChordInputCharacters(word), word)
            XCTAssertNotNil(ChordRecognitionCompendium.match(word), word)
        }
    }
}
